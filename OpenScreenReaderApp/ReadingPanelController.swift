import AppKit
import QuartzCore

enum ReadingPanelEdge: String, CaseIterable {
    case bottom, left, right
    var title: String { switch self { case .bottom: String(localized: "Bottom"); case .left: String(localized: "Left"); case .right: String(localized: "Right") } }
    var popoverEdge: NSRectEdge { switch self { case .bottom: .maxY; case .left: .maxX; case .right: .minX } }
}

/// Physical motion for the dockable control, after Apple's fluid-interface model:
/// project momentum to choose the landing spot, resist softly at boundaries.
enum PanelMotion {
    /// Faster pointer readings are noise from coalesced events, not intent.
    static let maximumSpeed: CGFloat = 6000

    /// Distance travelled while decelerating like a scroll view (rate 0.998 per ms).
    static func project(_ velocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
        velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    /// Past a boundary, the control follows less the further it is pulled.
    static func rubberband(_ overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        return overshoot * dimension * constant / (dimension + constant * abs(overshoot))
    }
}

/// Pointer velocity from the last 100 ms before release only.
struct DragVelocity {
    private var samples: [(point: CGPoint, time: TimeInterval)] = []

    mutating func add(_ point: CGPoint, at time: TimeInterval) {
        samples.append((point, time))
        samples.removeAll { time - $0.time > 0.1 }
    }

    func velocity(at now: TimeInterval) -> CGVector {
        let recent = samples.filter { now - $0.time <= 0.1 }
        guard let first = recent.first, let last = recent.last, last.time - first.time >= 0.008 else { return .zero }
        let dt = CGFloat(last.time - first.time)
        var vector = CGVector(dx: (last.point.x - first.point.x) / dt, dy: (last.point.y - first.point.y) / dt)
        let speed = hypot(vector.dx, vector.dy)
        if speed > PanelMotion.maximumSpeed {
            vector.dx *= PanelMotion.maximumSpeed / speed
            vector.dy *= PanelMotion.maximumSpeed / speed
        }
        return vector
    }
}

/// One axis of a spring described like Apple's: damping ratio and response in seconds.
/// It always continues from the current position and velocity, so it can be retargeted.
struct PanelSpring {
    var position: CGFloat
    var velocity: CGFloat
    var target: CGFloat
    private let stiffness: CGFloat
    private let damping: CGFloat

    init(position: CGFloat, velocity: CGFloat, target: CGFloat, response: CGFloat = 0.3, dampingRatio: CGFloat = 1) {
        self.position = position
        self.velocity = velocity
        self.target = target
        stiffness = pow(2 * .pi / response, 2)
        damping = 4 * .pi * dampingRatio / response
    }

    mutating func step(_ duration: CGFloat) {
        var remaining = min(duration, 0.1)
        while remaining > 0 {
            let dt = min(remaining, 1.0 / 240)
            velocity += (-stiffness * (position - target) - damping * velocity) * dt
            position += velocity * dt
            remaining -= dt
        }
    }

    var isSettled: Bool { abs(position - target) < 0.5 && abs(velocity) < 5 }
}

/// Only an edge and a normalized offset are persisted, never screen contents or display IDs.
struct ReadingPanelPlacement: Equatable {
    static let edgeKey = "readingPanelEdge"
    static let fractionKey = "readingPanelOffset"
    static let changed = Notification.Name("ReadingPanelPlacementChanged")
    var edge: ReadingPanelEdge = .bottom
    var fraction: Double = 0.5

    static func load(from defaults: UserDefaults) -> Self {
        let edge = ReadingPanelEdge(rawValue: defaults.string(forKey: edgeKey) ?? "") ?? .bottom
        let value = defaults.object(forKey: fractionKey) as? Double ?? 0.5
        return Self(edge: edge, fraction: value.isFinite ? min(1, max(0, value)) : 0.5)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(edge.rawValue, forKey: Self.edgeKey)
        defaults.set(fraction, forKey: Self.fractionKey)
        NotificationCenter.default.post(name: Self.changed, object: defaults)
    }

    func frame(in visible: CGRect) -> CGRect {
        let vertical = edge != .bottom
        let size = CGSize(width: min(vertical ? 92 : 300, visible.width),
                          height: min(vertical ? 300 : 92, visible.height))
        let t = fraction.isFinite ? min(1, max(0, fraction)) : 0.5
        let dx = max(0, visible.width - size.width)
        let dy = max(0, visible.height - size.height)
        let x = edge == .bottom ? dx * t : edge == .left ? min(4, dx) : dx - min(4, dx)
        let y = vertical ? dy * t : min(4, dy)
        return CGRect(origin: CGPoint(x: visible.minX + x, y: visible.minY + y), size: size)
    }

    /// The landing edge comes from where the throw is heading, not only where it was released.
    static func dropped(at release: CGPoint, velocity: CGVector = .zero, in visible: CGRect) -> Self {
        let point = CGPoint(
            x: min(visible.maxX, max(visible.minX, release.x + PanelMotion.project(velocity.dx))),
            y: min(visible.maxY, max(visible.minY, release.y + PanelMotion.project(velocity.dy))))
        let edge = ReadingPanelEdge.allCases.min { a, b in
            func distance(_ edge: ReadingPanelEdge) -> CGFloat {
                switch edge {
                case .bottom: abs(point.y - visible.minY)
                case .left: abs(point.x - visible.minX)
                case .right: abs(point.x - visible.maxX)
                }
            }
            return distance(a) < distance(b)
        } ?? .bottom
        let centered = Self(edge: edge).frame(in: visible)
        let available = edge == .bottom ? visible.width - centered.width : visible.height - centered.height
        let offset = edge == .bottom ? point.x - visible.minX - centered.width / 2
            : point.y - visible.minY - centered.height / 2
        return Self(edge: edge, fraction: available > 0 ? min(1, max(0, offset / available)) : 0.5)
    }
}

// Only status and an ephemeral scalar level cross the presentation boundary.
enum ReadingPanelState: Hashable {
    case recognizing, preparing, speaking, finished, stopped, noText, failed, positioning, waiting
    var title: String {
        switch self {
        case .recognizing: String(localized: "Recognizing text…")
        case .preparing: String(localized: "Preparing…")
        case .speaking: String(localized: "Reading aloud")
        case .finished: String(localized: "Done")
        case .stopped: String(localized: "Stopped")
        case .noText: String(localized: "No text found")
        case .failed: String(localized: "Can’t read aloud")
        case .positioning: String(localized: "Choose position")
        case .waiting: String(localized: "Waiting for next text")
        }
    }
    var detail: String {
        switch self {
        case .recognizing, .preparing, .speaking, .waiting: String(localized: "Escape stops everything and clears the queue")
        case .finished: String(localized: "Everything was read")
        case .stopped: String(localized: "Reading stopped")
        case .noText: String(localized: "Select a region with text.")
        case .failed: String(localized: "The question mark shows the reason and what to do next")
        case .positioning: String(localized: "Drag the waveform to a screen edge")
        }
    }
    var isActive: Bool { self == .recognizing || self == .preparing || self == .speaking || self == .waiting }
    var showsWaveform: Bool { isActive || self == .positioning }
    var dismissesAutomatically: Bool { self == .finished || self == .stopped }
    var needsAttention: Bool { self == .noText || self == .failed }
}

@MainActor
protocol ReadingStatusPresenting: AnyObject {
    func configureControls(_ onOpen: @escaping (NSView) -> Void)
    func configurePause(_ onToggle: @escaping () -> Void)
    func openControls()
    func updatePaused(_ paused: Bool)
    /// `origin` is the captured region in screen points. When present on the first
    /// visible state, the frame visibly collapses into the control before it opens.
    func show(_ state: ReadingPanelState, displayID: UInt32, origin: CGRect?, onStop: (() -> Void)?)
    func restore(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?)
    func updateLevel(_ level: Double)
    func updateQueueCount(_ count: Int)
    func hide()
}

extension ReadingStatusPresenting {
    func configureControls(_ onOpen: @escaping (NSView) -> Void) {}
    func configurePause(_ onToggle: @escaping () -> Void) {}
    func openControls() {}
    func updatePaused(_ paused: Bool) {}
    func restore(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?) {
        show(state, displayID: displayID, origin: nil, onStop: onStop)
    }
    func updateQueueCount(_ count: Int) {}
    func show(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?) {
        show(state, displayID: displayID, origin: nil, onStop: onStop)
    }
}

@MainActor
final class ReadingPanelController: NSObject, ReadingStatusPresenting {
    private var onOpenControls: ((NSView) -> Void)?
    private var onTogglePause: (() -> Void)?
    func configureControls(_ onOpen: @escaping (NSView) -> Void) { onOpenControls = onOpen }
    func configurePause(_ onToggle: @escaping () -> Void) { onTogglePause = onToggle }
    func openControls() { content?.openControls() }
    func updatePaused(_ paused: Bool) { content?.setPaused(paused) }
    private(set) var state: ReadingPanelState?
    private(set) var panel: ReadingStatusPanel?
    private(set) var flight: SelectionFlightWindow?
    private var content: ReadingControlView?
    private var displayID: UInt32?
    private var dismissalTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var flightTask: Task<Void, Never>?
    private var snap: (x: PanelSpring, y: PanelSpring, generation: UInt64)?
    private var snapClock: CADisplayLink?
    private var snapTick: CFTimeInterval?
    private var dragVelocity = DragVelocity()
    private var dragStart: (pointer: CGPoint, frame: CGRect)?
    private var didDrag = false
    private let defaults: UserDefaults
    private var placement: ReadingPanelPlacement
    private var generation: UInt64 = 0
    private var suppressOpeningCue = false
    private let terminalDuration: Duration
    private let interfaceSounds: (any InterfaceSoundPlaying)?
    private var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(terminalDuration: Duration = .milliseconds(1100), interfaceSounds: (any InterfaceSoundPlaying)? = nil,
         defaults: UserDefaults = InterfaceSoundPlayer.defaults) {
        self.terminalDuration = terminalDuration
        self.interfaceSounds = interfaceSounds
        self.defaults = defaults
        self.placement = .load(from: defaults)
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(displayLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(placementChanged),
            name: ReadingPanelPlacement.changed, object: nil)
    }
    isolated deinit {
        dismissalTask?.cancel()
        transitionTask?.cancel()
        flightTask?.cancel()
        stopSnap()
        content?.stopAnimating()
        flight?.close()
        panel?.close()
        NotificationCenter.default.removeObserver(self)
    }

    func show(_ state: ReadingPanelState, displayID: UInt32, origin: CGRect?, onStop: (() -> Void)?) {
        dismissalTask?.cancel()
        transitionTask?.cancel()
        generation &+= 1
        let current = generation
        guard let screen = Self.screen(for: displayID) else { hide(); return }
        let previous = self.state
        self.state = state
        self.displayID = displayID
        let panel = panel ?? ReadingStatusPanel()
        self.panel = panel
        let appearing = content == nil
        stopSnap()
        let frame = dragStart != nil ? panel.frame : placement.frame(in: screen.visibleFrame)
        let view = content ?? ReadingControlView(frame: NSRect(origin: .zero, size: frame.size))
        view.isVertical = placement.edge != .bottom
        view.dockEdge = placement.edge
        content = view
        view.onOpenControls = { [weak self] view in self?.onOpenControls?(view) }
        view.onTogglePause = { [weak self] in self?.onTogglePause?() }
        if appearing { panel.contentView = view }
        panel.setFrame(frame, display: true)
        view.onDragStart = { [weak self] point in self?.beginDrag(at: point) }
        view.onDragMove = { [weak self] point in self?.moveDrag(to: point) }
        view.onDragEnd = { [weak self] in self?.endDrag() }
        let action = { [weak self] in
            guard let self, self.generation == current else { return }
            if state.isActive { onStop?() } else { self.dismiss() }
        }
        if previous != state { announce(state, from: view) }
        scheduleTerminalDismissal()
        if flight != nil {
            // The frame is still flying: remember the newest state, open when it lands.
            view.present(state, opening: false, action: action)
            return
        }
        if appearing, let origin, !reduced, screen.frame.intersects(origin) {
            view.present(state, opening: false, action: action)
            let landing = Self.landingRect(for: frame, vertical: view.isVertical)
            let flight = SelectionFlightWindow(screen: screen)
            self.flight = flight
            flight.fly(from: origin, to: landing)
            flightTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(SelectionFlightWindow.durationMilliseconds)) } catch { return }
                guard let self, self.flight === flight else { return }
                self.land(flight)
            }
            return
        }
        view.present(state, opening: appearing, action: action)
        panel.orderFrontRegardless()
        if appearing && !suppressOpeningCue { interfaceSounds?.play(.selection) }
    }

    func restore(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?) {
        suppressOpeningCue = true
        defer { suppressOpeningCue = false }
        show(state, displayID: displayID, origin: nil, onStop: onStop)
    }

    private func land(_ flight: SelectionFlightWindow) {
        guard let panel, let content, let state else { return }
        self.flight = nil
        panel.orderFrontRegardless()
        content.present(state, opening: true, action: content.currentAction)
        interfaceSounds?.play(.selection)
        flight.fade()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            flight.close()
        }
    }

    func updateLevel(_ level: Double) {
        guard state == .speaking else { return }
        content?.setLevel(level)
    }

    func updateQueueCount(_ count: Int) { content?.setQueueCount(count) }

    // Selection/capture and cancellation cleanup never wait for a visual transition.
    func hide() {
        generation &+= 1
        dismissalTask?.cancel()
        transitionTask?.cancel()
        flightTask?.cancel()
        stopSnap()
        dragStart = nil
        didDrag = false
        dismissalTask = nil
        transitionTask = nil
        flightTask = nil
        flight?.close()
        flight = nil
        content?.stopAnimating()
        panel?.orderOut(nil)
        panel?.contentView = nil
        content = nil
        state = nil
        displayID = nil
    }

    func dismiss() {
        guard panel?.isVisible == true else { hide(); return }
        generation &+= 1
        let current = generation
        dismissalTask?.cancel()
        transitionTask?.cancel()
        stopSnap()
        dragStart = nil
        content?.retract()
        transitionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
            guard let self, self.generation == current else { return }
            self.hide()
        }
    }

    private func announce(_ state: ReadingPanelState, from view: NSView) {
        // The control is deliberately text-free; VoiceOver users still hear every change,
        // except the start of speech itself, where VoiceOver would talk over the voice.
        guard state != .speaking else { return }
        let urgent = state.needsAttention
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: state == .failed ? "\(state.title). \(state.detail)" : state.title,
            .priority: (urgent ? NSAccessibilityPriorityLevel.high : .medium).rawValue,
        ])
    }

    /// The window is larger than the visible body so the drawn shadow has room.
    static func frame(in visibleFrame: CGRect) -> CGRect {
        ReadingPanelPlacement().frame(in: visibleFrame)
    }
    /// Where the collapsed dot sits, in screen points.
    static func landingRect(for panelFrame: CGRect, vertical: Bool = false) -> CGRect {
        let size = ReadingControlView.Metrics.height
        if vertical {
            return CGRect(x: panelFrame.minX + ReadingControlView.Metrics.bodyBottom, y: panelFrame.midY - size / 2,
                          width: size, height: size)
        }
        return CGRect(x: panelFrame.midX - size / 2, y: panelFrame.minY + ReadingControlView.Metrics.bodyBottom,
                      width: size, height: size)
    }
    private static func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
    @objc private func displayLayoutChanged() {
        guard let displayID, let screen = Self.screen(for: displayID) else { hide(); return }
        stopSnap()
        dragStart = nil
        panel?.setFrame(placement.frame(in: screen.visibleFrame), display: true)
    }

    @objc private func placementChanged() {
        let next = ReadingPanelPlacement.load(from: defaults)
        guard next != placement else { return }
        placement = next
        content?.isVertical = placement.edge != .bottom
        content?.dockEdge = placement.edge
        displayLayoutChanged()
        content?.tick(now: CACurrentMediaTime())
    }

    func beginDrag(at pointer: CGPoint) {
        guard let panel, panel.isVisible, state != nil else { return }
        stopSnap()
        dismissalTask?.cancel()
        dragStart = (pointer, panel.frame)
        didDrag = false
    }

    /// The control follows the pointer 1:1 from where it was grabbed and resists
    /// progressively past the usable screen area instead of stopping hard.
    func moveDrag(to pointer: CGPoint) {
        guard let start = dragStart, let panel, let displayID, let screen = Self.screen(for: displayID) else { return }
        let dx = pointer.x - start.pointer.x, dy = pointer.y - start.pointer.y
        dragVelocity.add(pointer, at: CACurrentMediaTime())
        guard didDrag || hypot(dx, dy) >= 5 else { return }
        didDrag = true
        let visible = screen.visibleFrame
        func resist(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat, _ dimension: CGFloat) -> CGFloat {
            if value < lower { return lower + PanelMotion.rubberband(value - lower, dimension: dimension) }
            if value > upper { return upper + PanelMotion.rubberband(value - upper, dimension: dimension) }
            return value
        }
        panel.setFrameOrigin(CGPoint(
            x: resist(start.frame.minX + dx, visible.minX, visible.maxX - panel.frame.width, visible.width),
            y: resist(start.frame.minY + dy, visible.minY, visible.maxY - panel.frame.height, visible.height)))
    }

    /// The landing edge is projected from the release velocity, and a spring carries
    /// that velocity into the dock so there is no seam between dragging and settling.
    func endDrag() {
        defer { dragStart = nil; didDrag = false; dragVelocity = DragVelocity(); scheduleTerminalDismissal() }
        guard dragStart != nil, didDrag, let panel, let displayID, let screen = Self.screen(for: displayID) else { return }
        let velocity = dragVelocity.velocity(at: CACurrentMediaTime())
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let wasVertical = placement.edge != .bottom
        let next = ReadingPanelPlacement.dropped(at: center, velocity: velocity, in: screen.visibleFrame)
        let target = next.frame(in: screen.visibleFrame)
        // Saving synchronously updates Settings and the layout, then the new orientation settles at its edge.
        next.save(to: defaults)
        panel.setFrame(target, display: true)
        guard !reduced else { return }
        if wasVertical != (next.edge != .bottom) {
            // The capsule turns at the release point: let it re-form rather than jump.
            SaywingCapsuleStyle.materialize(content?.layer, reduced: false)
        }
        let visible = screen.visibleFrame
        let start = CGPoint(x: min(visible.maxX - target.width, max(visible.minX, center.x - target.width / 2)),
                            y: min(visible.maxY - target.height, max(visible.minY, center.y - target.height / 2)))
        panel.setFrameOrigin(start)
        // Only a throw may overshoot a little; a placed release settles calmly.
        let ratio: CGFloat = hypot(velocity.dx, velocity.dy) > 600 ? 0.85 : 1
        snap = (PanelSpring(position: start.x, velocity: velocity.dx, target: target.minX, dampingRatio: ratio),
                PanelSpring(position: start.y, velocity: velocity.dy, target: target.minY, dampingRatio: ratio),
                generation)
        snapTick = nil
        if snapClock == nil, let view = panel.contentView {
            let link = view.displayLink(target: SnapClockProxy(controller: self), selector: #selector(SnapClockProxy.fire))
            link.add(to: .main, forMode: .common)
            snapClock = link
        }
        snapClock?.isPaused = false
    }

    fileprivate func stepSnap(now: CFTimeInterval) {
        guard var current = snap, current.generation == generation, let panel, panel.isVisible else { stopSnap(); return }
        let dt = CGFloat(min(1.0 / 20, now - (snapTick ?? now - 1.0 / 60)))
        snapTick = now
        current.x.step(dt)
        current.y.step(dt)
        snap = current
        guard !(current.x.isSettled && current.y.isSettled) else {
            panel.setFrameOrigin(CGPoint(x: current.x.target, y: current.y.target))
            // Feedback lands with the control, not when the pointer lets go.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            stopSnap()
            return
        }
        panel.setFrameOrigin(CGPoint(x: current.x.position, y: current.y.position))
    }

    private func stopSnap() {
        snap = nil
        snapTick = nil
        snapClock?.invalidate()
        snapClock = nil
    }

    private func scheduleTerminalDismissal() {
        dismissalTask?.cancel()
        guard state?.dismissesAutomatically == true, dragStart == nil else { return }
        let current = generation
        dismissalTask = Task { @MainActor [weak self, terminalDuration] in
            do { try await Task.sleep(for: terminalDuration) } catch { return }
            guard let self, self.generation == current else { return }
            self.dismiss()
        }
    }
}

@MainActor
final class ReadingStatusPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = String(localized: "Reading status")
        setAccessibilityIdentifier("readingStatusPanel")
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
    }
}

/// The display link retains its target; this proxy keeps the controller collectable.
@MainActor
private final class SnapClockProxy: NSObject {
    private weak var controller: ReadingPanelController?
    init(controller: ReadingPanelController) { self.controller = controller }
    @objc func fire(_ link: CADisplayLink) { controller?.stepSnap(now: link.timestamp) }
}

/// A click-through window covering the selected display. It shows the captured
/// frame as a pale petrol ghost that collapses into a glowing dot at the control's spot.
@MainActor
final class SelectionFlightWindow: NSWindow {
    static let durationMilliseconds = 380
    /// Fast start, soft landing: the response is visible on the first frame.
    static let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1)
    private let ghost = CAShapeLayer()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        ghost.fillColor = ReadingPalette.voice.withAlphaComponent(0).cgColor
        ghost.strokeColor = ReadingPalette.voice.cgColor
        ghost.lineWidth = 2
        ghost.shadowColor = ReadingPalette.voice.cgColor
        ghost.shadowOffset = .zero
        ghost.shadowRadius = 14
        ghost.shadowOpacity = 0
        host.layer?.addSublayer(ghost)
        contentView = host
    }

    func fly(from origin: CGRect, to landing: CGRect) {
        let start = CGPath(roundedRect: convertFromScreen(origin).insetBy(dx: 1, dy: 1), cornerWidth: 5, cornerHeight: 5, transform: nil)
        let end = CGPath(roundedRect: convertFromScreen(landing), cornerWidth: landing.width / 2, cornerHeight: landing.height / 2, transform: nil)
        ghost.path = start
        orderFrontRegardless()
        let duration = Double(Self.durationMilliseconds) / 1000
        let timing = Self.timing
        func animate(_ keyPath: String, from: Any, to: Any) {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = timing
            ghost.add(animation, forKey: keyPath)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        animate("path", from: start, to: end)
        animate("fillColor", from: ReadingPalette.voice.withAlphaComponent(0).cgColor, to: ReadingPalette.voice.cgColor)
        animate("lineWidth", from: 2, to: 0)
        animate("shadowOpacity", from: 0, to: 0.9)
        ghost.path = end
        ghost.fillColor = ReadingPalette.voice.cgColor
        ghost.lineWidth = 0
        ghost.shadowOpacity = 0.9
        CATransaction.commit()
    }

    func fade() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.16
        ghost.add(animation, forKey: "fade")
        ghost.opacity = 0
    }
}

enum ReadingPalette {
    static let ink = NSColor(srgbRed: 23 / 255, green: 43 / 255, blue: 58 / 255, alpha: 1)
    /// Deep navy supports high-contrast pale petrol controls.
    static let void = NSColor(srgbRed: 14 / 255, green: 29 / 255, blue: 40 / 255, alpha: 1)
    static let paper = NSColor(srgbRed: 244 / 255, green: 242 / 255, blue: 236 / 255, alpha: 1)
    static let voice = NSColor(srgbRed: 139 / 255, green: 202 / 255, blue: 209 / 255, alpha: 1)
    static let voiceLight = NSColor(srgbRed: 221 / 255, green: 239 / 255, blue: 239 / 255, alpha: 1)
    /// Attention accent. Warm, not alarming; never used as body text.
    static let amber = NSColor(srgbRed: 228 / 255, green: 183 / 255, blue: 143 / 255, alpha: 1)

    static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let t = min(1, max(0, t))
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }
}

/// Shared visual and motion language for listening and speaking. Audio sources normalize
/// their own amplitude; this layer receives only a bounded, ephemeral level.
enum SaywingCapsuleStyle {
    static let height: CGFloat = 28
    static let barWidth: CGFloat = 2.5
    static let barGap: CGFloat = 3
    static let depthColors = [ReadingPalette.voiceLight.withAlphaComponent(0.10).cgColor,
                              ReadingPalette.ink.withAlphaComponent(0.25).cgColor,
                              NSColor.black.withAlphaComponent(0.22).cgColor]

    static func voiceColor(height: Double) -> NSColor {
        ReadingPalette.mix(ReadingPalette.voice, ReadingPalette.voiceLight,
                           min(1, max(0, (height - 2) / 16)) * 0.85)
    }

    @MainActor static func shadeVoice(_ bar: CAShapeLayer, height: Double, contrast: Bool) {
        bar.fillColor = voiceColor(height: height).cgColor
        bar.shadowColor = ReadingPalette.voice.cgColor
        bar.shadowOffset = .zero
        bar.shadowRadius = 3
        bar.shadowOpacity = contrast ? 0 : Float(min(1, max(0, (height - 2) / 16))) * 0.28
    }

    static func smooth(_ current: Double, toward target: Double, dt: Double) -> Double {
        current + (target - current) * (1 - exp(-max(0, dt) * (target > current ? 24 : 9)))
    }

    static func barHeight(index: Int, level: Double, reduced: Bool) -> Double {
        reduced ? 4 : 2 + 16 * min(1, max(0, level)) * (1 - abs(Double(index) - 4) * 0.16)
    }

    static func waitingOpacity(index: Int, now: TimeInterval, reduced: Bool) -> Float {
        reduced ? 1 : Float(0.35 + 0.65 * pow((sin(now * 3 - Double(index) * 0.55) + 1) / 2, 2))
    }

    @MainActor static func materialize(_ layer: CALayer?, reduced: Bool) {
        guard let layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.animation(forKey: "entryOpacity") == nil ? 0 : layer.presentation()?.opacity ?? 0
        fade.toValue = 1
        fade.duration = 0.14
        layer.add(fade, forKey: "entryOpacity")
        guard !reduced else { layer.removeAnimation(forKey: "entryScale"); return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = layer.animation(forKey: "entryScale") == nil ? 0.96
            : layer.presentation()?.value(forKeyPath: "transform.scale") ?? 0.96
        spring.toValue = 1
        spring.stiffness = 400
        spring.damping = 40 // Critical damping: settle without decorative overshoot.
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "entryScale")
    }
}

/// A text-free capsule: nine voice bars that answer the rendered speech level,
/// one round stop control, and shape, colour and motion for every state.
/// Secondary controls stay inside the capsule; text appears briefly for attention states.
/// accessibility labels and announcements always carry the full status.
@MainActor
final class ReadingControlView: NSView, NSPopoverDelegate {
    var onOpenControls: ((NSView) -> Void)?
    var onTogglePause: (() -> Void)?
    private weak var controlsPopover: NSPopover?
    func holdControls(for popover: NSPopover) {
        controlsPopover = popover
        popover.delegate = self
        // Menu/VoiceOver can open this before a hover frame reveals the anchor.
        if queueBadge.alphaValue < 0.5 {
            controlsBlend = 1
            tick(now: CACurrentMediaTime())
        }
        resumeClock()
    }
    func popoverDidClose(_ notification: Notification) {
        guard notification.object as? NSPopover === controlsPopover else { return }
        controlsPopover = nil
        resumeClock()
    }
    private var paused = false
    func setPaused(_ value: Bool) {
        paused = value
        if value { setLevel(0) }
        setAccessibilityLabel(value ? String(localized: "Reading paused") : String(localized: "Reading status: \(state.title)"))
        // The menu closes on Pause, so nothing else would tell a VoiceOver user.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: value ? String(localized: "Paused") : String(localized: "Resumed")])
        updateOptions()
        tick(now: CACurrentMediaTime())
    }
    enum Metrics {
        static let surface = CGSize(width: 300, height: 92)
        static let height: CGFloat = 44
        static let bodyBottom: CGFloat = 24
        static let padding: CGFloat = 29
        static let barCount = 9
        static let barWidth = SaywingCapsuleStyle.barWidth
        static let barGap = SaywingCapsuleStyle.barGap
        static let button: CGFloat = 44
        static let options: CGFloat = 40
        static var barsWidth: CGFloat { CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap }
        static let activeWidth: CGFloat = 136
        static var terminalWidth: CGFloat { 18 + 24 + 14 + button }
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var currentAction: () -> Void { action ?? {} }
    var isVertical = false
    var dockEdge: ReadingPanelEdge = .bottom
    var onDragStart: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private let shadowHost = NSView()
    private let softShadow = CALayer()
    private let body = HoverView()
    /// Visible surface is smaller than the 44 pt interaction surface.
    var visualBodyFrame: CGRect { body.convert(effect.frame, to: self) }
    var barHeights: [Double] { heights }
    private let effect = NSVisualEffectView()
    private let canvas = NSView()
    private let tint = CALayer()
    private let depth = CAGradientLayer()
    private var bars: [CAShapeLayer] = []
    private let icon = CAShapeLayer()
    private let border = CAShapeLayer()
    private let note = NSTextField(labelWithString: "")
    private let queueBadge = ReadingInlineButton(frame: .zero)
    private let pauseButton = ReadingInlineButton(frame: .zero)
    private var queueCount = 0
    private let button = ReadingStopButton(frame: NSRect(x: 0, y: 0, width: Metrics.button, height: Metrics.button))

    private var clock: CADisplayLink?
    private var state: ReadingPanelState = .recognizing
    private var action: (() -> Void)?
    private var width = Metrics.height
    private var widthVelocity = 0.0
    private var exitStart: TimeInterval?
    private var noteUntil: TimeInterval = 0
    private var content = 0.0
    private var level = 0.0
    private var targetLevel = 0.0
    private var terminal = 0.0
    private var hover = 0.0
    private var controlsBlend = 0.0
    private var trackingPointer = false
    private var noteBlend = 0.0
    private var press = 0.0
    private var hovering = false
    private var pressing = false
    private var opened = false
    private var heights = [Double](repeating: 3, count: Metrics.barCount)
    private var lastTick: TimeInterval?
    private var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        autoresizingMask = [.width, .height]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("readingStatusContent")

        shadowHost.wantsLayer = true
        shadowHost.autoresizingMask = [.width, .height]
        for shadow in [softShadow] {
            shadow.shadowColor = NSColor.black.cgColor
            shadowHost.layer?.addSublayer(shadow)
        }
        softShadow.shadowOpacity = 0.3
        softShadow.shadowRadius = 8
        softShadow.shadowOffset = CGSize(width: 0, height: -2)
        addSubview(shadowHost)

        body.wantsLayer = true
        body.layer?.masksToBounds = true
        body.layer?.cornerCurve = .circular
        body.onHover = { [weak self] inside in
            self?.hovering = inside
            self?.resumeClock()
        }
        addSubview(body)

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        body.addSubview(effect)

        canvas.wantsLayer = true
        canvas.autoresizingMask = [.width, .height]
        body.addSubview(canvas)

        tint.backgroundColor = ReadingPalette.void.cgColor
        depth.colors = SaywingCapsuleStyle.depthColors
        depth.locations = [0, 0.45, 1]
        depth.startPoint = CGPoint(x: 0.5, y: 1)
        depth.endPoint = CGPoint(x: 0.5, y: 0)
        for _ in 0..<Metrics.barCount { bars.append(CAShapeLayer()) }
        icon.fillColor = nil
        icon.lineWidth = 2.4
        icon.lineCap = .round
        icon.lineJoin = .round
        icon.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        border.fillColor = nil
        for layer in [tint, depth] + bars + [icon, border] { canvas.layer?.addSublayer(layer) }
        setAccent(ReadingPalette.voice)

        note.font = .systemFont(ofSize: 11.5, weight: .semibold)
        note.textColor = ReadingPalette.paper.withAlphaComponent(0.92)
        note.lineBreakMode = .byTruncatingTail
        note.alphaValue = 0
        note.setAccessibilityIdentifier("readingStatusTitle")
        // The group label already says the state; the fading note would repeat it.
        note.setAccessibilityElement(false)
        body.addSubview(note)

        button.target = self
        button.action = #selector(activate)
        button.onPress = { [weak self] in
            self?.pressing = true
            self?.onPress?()
            self?.resumeClock()
        }
        button.onRelease = { [weak self] in
            self?.pressing = false
            self?.onRelease?()
        }
        button.setAccessibilityIdentifier("readingStatusAction")
        body.addSubview(button)
        queueBadge.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        queueBadge.contentTintColor = ReadingPalette.paper
        queueBadge.isBordered = false
        queueBadge.target = self
        queueBadge.action = #selector(openControls)
        queueBadge.alignment = .center
        queueBadge.wantsLayer = true
        queueBadge.isHidden = true
        queueBadge.setAccessibilityIdentifier("readingQueueCount")
        body.addSubview(queueBadge)
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        pauseButton.setAccessibilityIdentifier("readingPauseAction")
        body.addSubview(pauseButton)
        for control in [pauseButton, queueBadge] {
            control.onDragStart = { [weak self] point in
                self?.trackingPointer = true
                self?.onDragStart?(point)
            }
            control.onDragMove = { [weak self] in self?.onDragMove?($0) }
            control.onDragEnd = { [weak self] in
                self?.trackingPointer = false
                self?.onDragEnd?()
                self?.resumeClock()
            }
        }
        body.toolTip = String(localized: "Hover for pause and options · Drag to move · Escape stops everything")
        body.onDragStart = { [weak self] in self?.onDragStart?($0) }
        body.onDragMove = { [weak self] in self?.onDragMove?($0) }
        body.onDragEnd = { [weak self] in self?.onDragEnd?() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { clock?.invalidate() }

    func setQueueCount(_ count: Int) {
        let added = min(5, max(0, count)) > queueCount
        queueCount = min(5, max(0, count))
        if added {
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: String(localized: "\(queueCount) texts waiting")])
        }
        updateOptions()
        tick(now: CACurrentMediaTime())
    }

    private func updateOptions() {
        queueBadge.title = state == .failed ? "?" : queueCount > 0 ? "+\(queueCount)" : "···"
        let label = state == .failed ? String(localized: "Show reason and help") : String(localized: "Playback and queue · \(queueCount) waiting")
        queueBadge.setAccessibilityLabel(label)
        queueBadge.toolTip = label
        queueBadge.isHidden = !state.isActive && state != .failed
        queueBadge.isEnabled = exitStart == nil
        queueBadge.needsDisplay = true
        pauseButton.title = paused ? "resume" : "pause"
        pauseButton.setAccessibilityLabel(paused ? String(localized: "Resume reading") : String(localized: "Pause reading"))
        pauseButton.toolTip = state == .speaking ? (paused ? String(localized: "Resume reading") : String(localized: "Pause reading")) : String(localized: "Pause becomes available when playback starts")
        pauseButton.isHidden = !state.isActive
        pauseButton.isEnabled = state == .speaking && exitStart == nil
        pauseButton.needsDisplay = true
        setAccessibilityValue(queueCount > 0 ? String(localized: "\(queueCount) waiting in the queue") : String(localized: "Queue empty"))
        var actions: [NSAccessibilityCustomAction] = []
        if state.isActive || state == .failed {
            actions.append(NSAccessibilityCustomAction(name: label, handler: { [weak self] in
                guard let self, self.queueBadge.isEnabled else { return false }
                self.openControls(); return true
            }))
        }
        if state == .speaking {
            actions.append(NSAccessibilityCustomAction(name: paused ? String(localized: "Resume reading") : String(localized: "Pause reading"), handler: { [weak self] in
                guard let self, self.pauseButton.isEnabled else { return false }
                self.togglePause(); return true
            }))
        }
        setAccessibilityCustomActions(actions)
    }

    @objc func openControls() {
        guard exitStart == nil, !queueBadge.isHidden, queueBadge.isEnabled else { return }
        onOpenControls?(queueBadge)
    }
    @objc private func togglePause() {
        guard exitStart == nil, state == .speaking, pauseButton.isEnabled else { return }
        onTogglePause?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === queueBadge || hit.isDescendant(of: queueBadge) { return hit }
        if hit === pauseButton || hit.isDescendant(of: pauseButton) { return hit }
        if hit === button || hit.isDescendant(of: button) { return hit }
        // Decorative layers and status labels are one drag surface, not a stop target.
        if hit === body || hit.isDescendant(of: body) { return body }
        return nil
    }
    override func layout() {
        super.layout()
        for shadow in [softShadow] { shadow.frame = bounds }
    }

    // MARK: State

    func present(_ state: ReadingPanelState, opening: Bool, action: @escaping () -> Void) {
        let previous = self.state
        let now = CACurrentMediaTime()
        self.state = state
        self.action = action
        for control in [pauseButton, queueBadge] { control.suppressClick() }
        exitStart = nil
        updateOptions()
        alphaValue = 1
        if opening {
            width = state.showsWaveform ? Metrics.activeWidth : Metrics.terminalWidth
            widthVelocity = 0; content = 1; opened = true
            level = 0; terminal = 0; hover = 0; noteBlend = 0; press = 0
            heights = [Double](repeating: 3, count: Metrics.barCount)
            SaywingCapsuleStyle.materialize(layer, reduced: reduced)
            lastTick = nil
        }
        if state != .speaking { targetLevel = 0 }
        toolTip = state.detail
        setAccessibilityLabel(paused && state == .speaking ? String(localized: "Reading paused") : String(localized: "Reading status: \(state.title)"))
        setAccessibilityHelp(state.detail)
        setAccent(state.needsAttention ? ReadingPalette.amber : ReadingPalette.voice)
        button.terminal = !state.isActive
        button.isEnabled = true
        button.setAccessibilityLabel(state.isActive ? String(localized: "Stop reading") : String(localized: "Close status"))
        button.toolTip = state.isActive ? String(localized: "Stop everything (Esc)") : String(localized: "Close status")
        note.stringValue = state.title
        noteUntil = state.needsAttention ? now + 2.4 : 0
        if !state.isActive {
            showIcon(for: state, drawn: opened && !opening && previous.isActive && !reduced)
        }
        resumeClock()
        tick(now: now)
    }

    func setLevel(_ level: Double) {
        targetLevel = level.isFinite ? min(1, max(0, level)) : 0
    }

    func retract() {
        exitStart = CACurrentMediaTime()
        action = nil
        button.isEnabled = false
        queueBadge.isEnabled = false
        pauseButton.isEnabled = false
        setAccessibilityCustomActions([])
        resumeClock()
    }

    func stopAnimating() {
        clock?.isPaused = true
        targetLevel = 0
        level = 0
        action = nil
        queueBadge.isEnabled = false
        pauseButton.isEnabled = false
        for control in [pauseButton, queueBadge] { control.suppressClick() }
        let popover = controlsPopover
        controlsPopover = nil
        popover?.delegate = nil
        popover?.close()
        setAccessibilityCustomActions([])
    }

    @objc private func activate() { action?() }

    @objc private func accessibilityChanged() {
        if reduced { layer?.removeAllAnimations(); icon.removeAllAnimations() }
        resumeClock()
        tick(now: CACurrentMediaTime())
    }

    private func setAccent(_ color: NSColor) {
        icon.strokeColor = color.cgColor
        for bar in bars { bar.fillColor = color.cgColor }
    }

    private func showIcon(for state: ReadingPanelState, drawn: Bool) {
        let path = CGMutablePath()
        switch state {
        case .finished:
            path.move(to: CGPoint(x: 4, y: 12))
            path.addLine(to: CGPoint(x: 9.5, y: 6.5))
            path.addLine(to: CGPoint(x: 20, y: 19))
        case .stopped:
            path.addRoundedRect(in: CGRect(x: 5.5, y: 5.5, width: 13, height: 13), cornerWidth: 3, cornerHeight: 3)
        default:
            path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
            path.move(to: CGPoint(x: 12, y: 17)); path.addLine(to: CGPoint(x: 12, y: 10.5))
            path.move(to: CGPoint(x: 12, y: 7.1)); path.addLine(to: CGPoint(x: 12, y: 6.4))
        }
        icon.removeAllAnimations()
        icon.path = path
        icon.strokeEnd = 1
        guard drawn else { return }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.34
        draw.beginTime = CACurrentMediaTime() + 0.12
        draw.fillMode = .backwards
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        icon.add(draw, forKey: "draw")
    }

    // MARK: Clock

    private func resumeClock() {
        if clock == nil {
            let link = displayLink(target: DisplayClockProxy(view: self), selector: #selector(DisplayClockProxy.fire))
            link.add(to: .main, forMode: .common)
            clock = link
        }
        clock?.isPaused = false
    }

    func tick(now: TimeInterval) {
        tick(now: now, reducedMotion: reduced)
    }

    func tick(now: TimeInterval, reducedMotion: Bool) {
        let dt = min(1.0 / 20, max(1.0 / 240, now - (lastTick ?? now - 1.0 / 60)))
        lastTick = now
        let reduced = reducedMotion || paused
        let exiting = exitStart != nil
        func approach(_ value: inout Double, _ goal: Double, rate: Double) {
            value += (goal - value) * (reduced ? 1 : 1 - exp(-dt * rate))
        }
        approach(&terminal, state.showsWaveform ? 0 : 1, rate: 10)
        approach(&hover, hovering && !exiting ? 1 : 0, rate: 12)
        // Voice Control, Switch Control and VoiceOver users cannot hover to reveal the controls.
        let assistive = NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
        let showControls = state.isActive && !exiting && (hovering || trackingPointer || controlsPopover != nil || assistive)
        approach(&controlsBlend, showControls ? 1 : 0, rate: 22)
        approach(&press, pressing ? 1 : 0, rate: 30)
        let noteWanted = !isVertical && state.needsAttention && !exiting && (now < noteUntil || hovering)
        approach(&noteBlend, noteWanted ? 1 : 0, rate: 10)

        // State changes retarget the existing critically damped spring.
        let widthGoal: Double
        if exiting { widthGoal = Metrics.height }
        else if state.showsWaveform { widthGoal = Metrics.activeWidth }
        else if state.needsAttention { widthGoal = Metrics.terminalWidth + (state == .failed ? Metrics.options : 0) + noteBlend * max(0, noteWidth()) }
        else { widthGoal = Metrics.terminalWidth }
        let goal = widthGoal
        if reduced {
            width = goal; widthVelocity = 0
        } else {
            let stiffness = exiting ? 340.0 : 190.0
            let damping = 2 * sqrt(stiffness)
            widthVelocity += (-stiffness * (width - goal) - damping * widthVelocity) * dt
            width += widthVelocity * dt
        }
        let contentGoal = exiting ? 0.0 : (width > Metrics.height + 20 ? 1.0 : 0.0)
        approach(&content, contentGoal, rate: exiting ? 24 : 14)

        level = SaywingCapsuleStyle.smooth(level, toward: state == .speaking ? targetLevel : 0, dt: dt)
        updateBars(reduced: reduced)
        layoutFrame(now: now, reduced: reduced)
        if let exitStart { alphaValue = max(0, 1 - (now - exitStart) / 0.22) }

        let settled = abs(width - goal) < 0.05 && abs(widthVelocity) < 0.5 && abs(content - contentGoal) < 0.01
            && abs(terminal - (state.showsWaveform ? 0 : 1)) < 0.01 && abs(hover - (hovering ? 1 : 0)) < 0.01
            && abs(noteBlend - (noteWanted ? 1 : 0)) < 0.01 && press < 0.01
            && (!state.needsAttention || now >= noteUntil)
        if (reduced || !state.isActive) && settled && !exiting { clock?.isPaused = true }
    }

    private func noteWidth() -> Double {
        note.sizeThatFits(NSSize(width: 400, height: 20)).width + 12
    }

    private func updateBars(reduced: Bool) {
        for index in heights.indices {
            heights[index] = state == .speaking || state == .positioning
                ? SaywingCapsuleStyle.barHeight(index: index, level: state == .positioning ? 0.5 : level, reduced: reduced)
                : 2
        }
    }

    private func layoutFrame(now: TimeInterval, reduced: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let w = min((isVertical ? bounds.height : bounds.width) - 8, max(Metrics.height, width))
        let h = Metrics.height // Invisible interaction surface, not visual thickness.
        let bodyRect = isVertical
            ? CGRect(x: Metrics.bodyBottom, y: (bounds.height - w) / 2, width: h, height: w)
            : CGRect(x: (bounds.width - w) / 2, y: Metrics.bodyBottom, width: w, height: h)
        let inset = (h - SaywingCapsuleStyle.height) / 2
        let local = CGRect(origin: .zero, size: bodyRect.size)
        let visual = local.insetBy(dx: isVertical ? inset : 0, dy: isVertical ? 0 : inset)
        let radius = SaywingCapsuleStyle.height / 2
        body.frame = bodyRect
        effect.frame = visual
        effect.layer?.cornerRadius = radius
        canvas.frame = local
        let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        effect.isHidden = solid
        tint.opacity = solid ? 1 : 0.94
        let shadowPath = CGPath(roundedRect: visual.offsetBy(dx: bodyRect.minX, dy: bodyRect.minY),
                                cornerWidth: radius, cornerHeight: radius, transform: nil)
        softShadow.shadowPath = shadowPath
        softShadow.opacity = Float(alphaValue)

        // Map the horizontal layout into a top-to-bottom stack; glyphs themselves stay upright.
        let centerY = h / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            isVertical ? CGPoint(x: y, y: w - x) : CGPoint(x: x, y: y)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            isVertical ? CGRect(x: y, y: w - x - width, width: height, height: width)
                : CGRect(x: x, y: y, width: width, height: height)
        }
        tint.frame = visual
        tint.cornerRadius = radius
        depth.frame = visual
        depth.cornerRadius = radius
        border.frame = local
        border.path = CGPath(roundedRect: visual.insetBy(dx: 0.5, dy: 0.5),
                             cornerWidth: radius - 0.5, cornerHeight: radius - 0.5, transform: nil)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let accent = state.needsAttention ? ReadingPalette.amber : ReadingPalette.voice
        border.lineWidth = contrast ? 1.5 : 0.75
        border.strokeColor = accent.withAlphaComponent(contrast ? 0.9 : 0.16).cgColor

        // Stable slots: waveform, quiet options, stop. Hover never moves their targets.
        let barsX = Metrics.padding
        let visible = Float(content * (1 - terminal) * (1 - controlsBlend))
        for (index, bar) in bars.enumerated() {
            let height = heights[index]
            let x = barsX + CGFloat(index) * (Metrics.barWidth + Metrics.barGap)
            bar.frame = rect(x, centerY - height / 2, Metrics.barWidth, height)
            bar.path = CGPath(roundedRect: CGRect(origin: .zero, size: bar.frame.size),
                              cornerWidth: Metrics.barWidth / 2, cornerHeight: Metrics.barWidth / 2, transform: nil)
            SaywingCapsuleStyle.shadeVoice(bar, height: height, contrast: contrast)
            let waiting = state == .recognizing || state == .preparing || state == .waiting
            bar.opacity = visible * (waiting ? SaywingCapsuleStyle.waitingOpacity(index: index, now: now, reduced: reduced) : 1)
        }

        icon.position = point(18 + 12, centerY)
        icon.opacity = Float(terminal * terminal * (3 - 2 * terminal) * content)
        icon.setAffineTransform(CGAffineTransform(scaleX: 14 / 24, y: 14 / 24))

        let buttonX = w - Metrics.button
        let optionsX = buttonX - Metrics.options
        queueBadge.frame = rect(optionsX, (h - Metrics.button) / 2, Metrics.options, Metrics.button)
        pauseButton.frame = rect(optionsX - Metrics.options - 4, (h - Metrics.button) / 2, Metrics.options, Metrics.button)
        queueBadge.alphaValue = content * (state == .failed ? 1 : controlsBlend)
        pauseButton.alphaValue = content * controlsBlend
        let noteX = 18 + 24 + 10.0
        note.frame = CGRect(x: noteX, y: centerY - 8, width: max(0, (queueBadge.isHidden ? buttonX : optionsX) - noteX - 6), height: 16)
        note.alphaValue = isVertical ? 0 : noteBlend * content
        button.frame = rect(buttonX, (h - Metrics.button) / 2, Metrics.button, Metrics.button)
        button.alphaValue = content
    }
}

/// The display link retains its target; this proxy keeps the view collectable.
@MainActor
private final class DisplayClockProxy: NSObject {
    private weak var view: ReadingControlView?
    init(view: ReadingControlView) { self.view = view }
    @objc func fire(_ link: CADisplayLink) { view?.tick(now: CACurrentMediaTime()) }
}

@MainActor
private final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDragStart: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onDragStart?(window.convertPoint(toScreen: event.locationInWindow))
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        NSCursor.closedHand.set()
        onDragMove?(window.convertPoint(toScreen: event.locationInWindow))
    }
    override func mouseUp(with event: NSEvent) {
        onDragEnd?()
        NSCursor.openHand.set()
    }
}

/// A quiet native button: no resting badge background, a generous independent hit area,
/// upright glyphs at every dock edge, and no extra sound competing with speech.
@MainActor
private final class ReadingInlineButton: NSButton {
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var pointerStart: CGPoint?
    private var dragged = false
    private var clickAllowed = false
    var onDragStart: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    func suppressClick() { clickAllowed = false; highlight(false) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = "···"
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 20
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard alphaValue >= 0.5 else { return nil }
        return super.hitTest(point)
    }
    // Normal responder events, not a nested tracking loop: cancellation and drawing
    // remain live. Moving 5 pt always drags, even if the pointer started on an icon.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        pointerStart = point
        dragged = false
        clickAllowed = isEnabled
        highlight(isEnabled)
        onDragStart?(point)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = pointerStart else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        if hypot(point.x - start.x, point.y - start.y) >= 5 { dragged = true }
        if dragged {
            highlight(false)
            NSCursor.closedHand.set()
            onDragMove?(point)
        }
    }
    override func mouseUp(with event: NSEvent) {
        guard pointerStart != nil else { return }
        let clicked = clickAllowed && !dragged && isEnabled && !isHidden
            && bounds.contains(convert(event.locationInWindow, from: nil))
        pointerStart = nil
        clickAllowed = false
        highlight(false)
        onDragEnd?()
        NSCursor.arrow.set()
        if clicked, isEnabled { sendAction(action, to: target) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateHighlight() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHighlight() }
    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateHighlight()
    }
    private func updateHighlight() {
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if hovered || isHighlighted {
            ReadingPalette.paper.withAlphaComponent(isHighlighted ? 0.18 : 0.09).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)).fill()
        }
        if isHighlighted && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.scale(by: 0.92)
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()
        }
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let color = ReadingPalette.paper.withAlphaComponent(!isEnabled ? 0.3 : contrast || hovered || isHighlighted ? 1 : 0.72)
        if title == "pause" {
            color.setFill()
            for offset in [-3.5, 1.5] {
                NSBezierPath(roundedRect: CGRect(x: center.x + offset, y: center.y - 4, width: 2, height: 8), xRadius: 1, yRadius: 1).fill()
            }
        } else if title == "resume" {
            color.setFill()
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x - 4, y: center.y - 6))
            path.line(to: CGPoint(x: center.x + 6, y: center.y))
            path.line(to: CGPoint(x: center.x - 4, y: center.y + 6))
            path.close()
            path.fill()
        } else if title == "···" {
            color.setFill()
            for offset in [-5.0, 0, 5] {
                NSBezierPath(ovalIn: CGRect(x: center.x + offset - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)).fill()
            }
        } else {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: color]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
        }
    }
    override var focusRingMaskBounds: NSRect {
        CGRect(x: bounds.midX - 11, y: bounds.midY - 11, width: 22, height: 22)
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: focusRingMaskBounds, xRadius: 18, yRadius: 18).fill()
    }
}

/// A 44 pt control whose visible face compresses on press and springs back.
/// The hit area and screen position never move.
@MainActor
final class ReadingStopButton: NSButton {
    var terminal = false { didSet { updateGlyph() } }
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    private let face = CAShapeLayer()
    private let glyph = CAShapeLayer()
    private var hovered = false { didSet { updateFace() } }
    private var pressed = false { didSet { updateFace() } }
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        let center = CGPoint(x: frame.width / 2, y: frame.height / 2)
        for layer in [face, glyph] {
            layer.bounds = CGRect(origin: .zero, size: frame.size)
            layer.position = center
            self.layer?.addSublayer(layer)
        }
        face.path = CGPath(ellipseIn: CGRect(x: 11, y: 11, width: 22, height: 22), transform: nil)
        face.lineWidth = 1
        glyph.lineWidth = 1.4
        glyph.lineCap = .round
        updateGlyph()
        updateFace()
    }
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {}
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onPress?()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        press(true)
        super.mouseDown(with: event)
        press(false)
        onRelease?()
    }

    private func press(_ down: Bool) {
        pressed = down
        let scale = down ? 0.92 : 1.0
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for layer in [face, glyph] {
            if !reduced {
                let spring = CASpringAnimation(keyPath: "transform.scale")
                spring.fromValue = (layer.presentation() ?? layer).value(forKeyPath: "transform.scale")
                spring.toValue = scale
                spring.stiffness = down ? 640 : 260
                spring.damping = 2 * sqrt(spring.stiffness)
                spring.duration = spring.settlingDuration
                layer.add(spring, forKey: "press")
            }
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    private func updateFace() {
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        face.fillColor = ReadingPalette.paper.withAlphaComponent(pressed ? 0.26 : hovered ? 0.19 : 0.10).cgColor
        face.strokeColor = ReadingPalette.voiceLight.withAlphaComponent(contrast ? 0.75 : 0.18).cgColor
    }

    private func updateGlyph() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        if terminal {
            path.move(to: CGPoint(x: 19, y: 19)); path.addLine(to: CGPoint(x: 25, y: 25))
            path.move(to: CGPoint(x: 19, y: 25)); path.addLine(to: CGPoint(x: 25, y: 19))
            glyph.fillColor = nil
            glyph.strokeColor = ReadingPalette.paper.cgColor
        } else {
            path.addRoundedRect(in: CGRect(x: 18.5, y: 18.5, width: 7, height: 7), cornerWidth: 1.5, cornerHeight: 1.5)
            glyph.fillColor = ReadingPalette.paper.cgColor
            glyph.strokeColor = nil
        }
        glyph.path = path
        CATransaction.commit()
    }
}
