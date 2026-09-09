import AppKit
import QuartzCore

enum ReadingPanelEdge: String, CaseIterable {
    case bottom, left, right
    var title: String { switch self { case .bottom: "Bottom"; case .left: "Left"; case .right: "Right" } }
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

    static func dropped(at point: CGPoint, in visible: CGRect) -> Self {
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
        case .recognizing: "Text erkennen …"
        case .preparing: "Vorbereiten …"
        case .speaking: "Vorlesen"
        case .finished: "Fertig"
        case .stopped: "Gestoppt"
        case .noText: "Kein Text erkannt"
        case .failed: "Vorlesen nicht möglich"
        case .positioning: "Position wählen"
        case .waiting: "Warte auf nächsten Text"
        }
    }
    var detail: String {
        switch self {
        case .recognizing, .preparing, .speaking, .waiting: "Esc stoppt alles und leert die Warteschlange"
        case .finished: "Alles vorgelesen"
        case .stopped: "Vorlesen beendet"
        case .noText: "Wähle einen Bereich mit Text."
        case .failed: "Einrichtung und Fehlerhilfe über die Fragezeichen-Taste"
        case .positioning: "Wellenform zum Bildschirmrand ziehen"
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
    func configureControls(_ onOpen: @escaping (NSView) -> Void) { onOpenControls = onOpen }
    func updatePaused(_ paused: Bool) { content?.setPaused(paused) }
    private(set) var state: ReadingPanelState?
    private(set) var panel: ReadingStatusPanel?
    private(set) var flight: SelectionFlightWindow?
    private var content: ReadingControlView?
    private var displayID: UInt32?
    private var dismissalTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var flightTask: Task<Void, Never>?
    private var snapTask: Task<Void, Never>?
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
        snapTask?.cancel()
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
        snapTask?.cancel()
        let frame = dragStart != nil ? panel.frame : placement.frame(in: screen.visibleFrame)
        let view = content ?? ReadingControlView(frame: NSRect(origin: .zero, size: frame.size))
        view.isVertical = placement.edge != .bottom
        content = view
        view.onOpenControls = { [weak self] view in self?.onOpenControls?(view) }
        if appearing { panel.contentView = view }
        panel.setFrame(frame, display: true)
        view.onPress = { [weak self] in self?.interfaceSounds?.play(.tap) }
        view.onRelease = { [weak self] in self?.interfaceSounds?.play(.release) }
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
        snapTask?.cancel()
        snapTask = nil
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
        snapTask?.cancel()
        dragStart = nil
        content?.retract()
        transitionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
            guard let self, self.generation == current else { return }
            self.hide()
        }
    }

    private func announce(_ state: ReadingPanelState, from view: NSView) {
        // The control is deliberately text-free; VoiceOver users still hear every change.
        NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
            .announcement: state.title,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
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
        snapTask?.cancel()
        dragStart = nil
        panel?.setFrame(placement.frame(in: screen.visibleFrame), display: true)
    }

    @objc private func placementChanged() {
        let next = ReadingPanelPlacement.load(from: defaults)
        guard next != placement else { return }
        placement = next
        content?.isVertical = placement.edge != .bottom
        displayLayoutChanged()
        content?.tick(now: CACurrentMediaTime())
    }

    func beginDrag(at pointer: CGPoint) {
        guard let panel, panel.isVisible, state != nil else { return }
        snapTask?.cancel()
        dismissalTask?.cancel()
        dragStart = (pointer, panel.frame)
        didDrag = false
    }

    func moveDrag(to pointer: CGPoint) {
        guard let start = dragStart, let panel, let displayID, let screen = Self.screen(for: displayID) else { return }
        let dx = pointer.x - start.pointer.x, dy = pointer.y - start.pointer.y
        guard didDrag || hypot(dx, dy) >= 5 else { return }
        didDrag = true
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: min(visible.maxX - panel.frame.width, max(visible.minX, start.frame.minX + dx)),
                                     y: min(visible.maxY - panel.frame.height, max(visible.minY, start.frame.minY + dy))))
    }

    func endDrag() {
        defer { dragStart = nil; didDrag = false; scheduleTerminalDismissal() }
        guard dragStart != nil, didDrag, let panel, let displayID, let screen = Self.screen(for: displayID) else { return }
        let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let next = ReadingPanelPlacement.dropped(at: center, in: screen.visibleFrame)
        let target = next.frame(in: screen.visibleFrame)
        // Saving synchronously updates Settings and the layout, then the new orientation settles at its edge.
        next.save(to: defaults)
        panel.setFrame(target, display: true)
        guard !reduced else { return }
        let start = CGPoint(x: min(screen.visibleFrame.maxX - target.width, max(screen.visibleFrame.minX, center.x - target.width / 2)),
                            y: min(screen.visibleFrame.maxY - target.height, max(screen.visibleFrame.minY, center.y - target.height / 2)))
        panel.setFrameOrigin(start)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        let current = generation
        snapTask = Task { @MainActor [weak self] in
            let began = CACurrentMediaTime()
            while !Task.isCancelled {
                guard let self, self.generation == current, self.panel?.isVisible == true else { return }
                let t = min(1, (CACurrentMediaTime() - began) / 0.22)
                let eased = 1 - pow(1 - t, 3)
                self.panel?.setFrameOrigin(CGPoint(x: start.x + (target.minX - start.x) * eased,
                                                   y: start.y + (target.minY - start.y) * eased))
                if t >= 1 { return }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            }
        }
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
        title = "Vorlesestatus"
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

/// A click-through window covering the selected display. It shows the captured
/// frame as a mint ghost that collapses into a glowing dot at the control's spot.
@MainActor
final class SelectionFlightWindow: NSWindow {
    static let durationMilliseconds = 460
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
        ghost.fillColor = ReadingPalette.mint.withAlphaComponent(0).cgColor
        ghost.strokeColor = ReadingPalette.mint.cgColor
        ghost.lineWidth = 2
        ghost.shadowColor = ReadingPalette.mint.cgColor
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
        let timing = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.2, 1)
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
        animate("fillColor", from: ReadingPalette.mint.withAlphaComponent(0).cgColor, to: ReadingPalette.mint.cgColor)
        animate("lineWidth", from: 2, to: 0)
        animate("shadowOpacity", from: 0, to: 0.9)
        ghost.path = end
        ghost.fillColor = ReadingPalette.mint.cgColor
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
    static let ink = NSColor(srgbRed: 11 / 255, green: 23 / 255, blue: 36 / 255, alpha: 1)
    /// Deeper than Local Ink so mint reads as light, not paint.
    static let void = NSColor(srgbRed: 5 / 255, green: 11 / 255, blue: 19 / 255, alpha: 1)
    static let paper = NSColor(srgbRed: 247 / 255, green: 244 / 255, blue: 237 / 255, alpha: 1)
    static let mint = NSColor(srgbRed: 85 / 255, green: 224 / 255, blue: 190 / 255, alpha: 1)
    static let mintLight = NSColor(srgbRed: 184 / 255, green: 247 / 255, blue: 231 / 255, alpha: 1)
    /// Attention accent. Warm, not alarming; never used as body text.
    static let amber = NSColor(srgbRed: 1, green: 0.72, blue: 0.4, alpha: 1)

    static func mix(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let t = min(1, max(0, t))
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
                       alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t)
    }
}

/// A text-free capsule: nine voice bars that answer the rendered speech level,
/// one round stop control, and shape, colour and motion for every state.
/// Text appears only on hover (Esc hint) and briefly for attention states;
/// accessibility labels and announcements always carry the full status.
@MainActor
final class ReadingControlView: NSView {
    var onOpenControls: ((NSView) -> Void)?
    private var paused = false
    func setPaused(_ value: Bool) {
        paused = value
        if value { setLevel(0) }
        setAccessibilityLabel(value ? "Vorlesen pausiert" : "Vorlesestatus: " + state.title)
        tick(now: CACurrentMediaTime())
    }
    enum Metrics {
        static let surface = CGSize(width: 300, height: 92)
        static let height: CGFloat = 44
        static let bodyBottom: CGFloat = 24
        static let padding: CGFloat = 22
        static let barCount = 9
        static let barWidth: CGFloat = 3
        static let barGap: CGFloat = 3.5
        static let barMaxHeight: CGFloat = 30
        static let button: CGFloat = 44
        static let keycapWidth: CGFloat = 40
        static var barsWidth: CGFloat { CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap }
        static var activeWidth: CGFloat { padding + barsWidth + 15 + button }
        static var terminalWidth: CGFloat { 18 + 24 + 14 + button }
    }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var currentAction: () -> Void { action ?? {} }
    var isVertical = false
    var onDragStart: ((CGPoint) -> Void)?
    var onDragMove: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?

    private let shadowHost = NSView()
    private let softShadow = CALayer()
    private let contactShadow = CALayer()
    private let body = HoverView()
    private let effect = NSVisualEffectView()
    private let canvas = NSView()
    private let tint = CALayer()
    private let depth = CAGradientLayer()
    private let rim = CAShapeLayer()
    private let glow = CAGradientLayer()
    private var bars: [CAShapeLayer] = []
    private let comet = CAGradientLayer()
    private let icon = CAShapeLayer()
    private let bloom = CAShapeLayer()
    private let keycap = CAShapeLayer()
    private let keycapText = CATextLayer()
    private let border = CAShapeLayer()
    private let note = NSTextField(labelWithString: "")
    private let queueBadge = NSButton(title: "···", target: nil, action: nil)
    private let button = ReadingStopButton(frame: NSRect(x: 0, y: 0, width: Metrics.button, height: Metrics.button))

    private var clock: CADisplayLink?
    private var state: ReadingPanelState = .recognizing
    private var action: (() -> Void)?
    private var width = Metrics.height
    private var widthVelocity = 0.0
    private var exitStart: TimeInterval?
    private var bumpStart: TimeInterval?
    private var pulseStart: TimeInterval?
    private var changed: TimeInterval = 0
    private var noteUntil: TimeInterval = 0
    private var content = 0.0
    private var level = 0.0
    private var targetLevel = 0.0
    private var previousLevel = 0.0
    private var terminal = 0.0
    private var hover = 0.0
    private var noteBlend = 0.0
    private var press = 0.0
    private var hovering = false
    private var pressing = false
    private var opened = false
    private var heights = [Double](repeating: 3, count: Metrics.barCount)
    private var phase = 0.0
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
        for shadow in [softShadow, contactShadow] {
            shadow.shadowColor = NSColor.black.cgColor
            shadowHost.layer?.addSublayer(shadow)
        }
        softShadow.shadowOpacity = 0.5
        softShadow.shadowRadius = 16
        softShadow.shadowOffset = CGSize(width: 0, height: -6)
        contactShadow.shadowOpacity = 0.45
        contactShadow.shadowRadius = 2.5
        contactShadow.shadowOffset = CGSize(width: 0, height: -1)
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
        depth.colors = [ReadingPalette.paper.withAlphaComponent(0.09).cgColor, NSColor.clear.cgColor,
                        NSColor.black.withAlphaComponent(0.3).cgColor]
        depth.locations = [0, 0.45, 1]
        depth.startPoint = CGPoint(x: 0.5, y: 1)
        depth.endPoint = CGPoint(x: 0.5, y: 0)
        rim.fillColor = nil
        rim.lineWidth = 1
        rim.strokeColor = ReadingPalette.paper.withAlphaComponent(0.06).cgColor
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        for _ in 0..<Metrics.barCount {
            let bar = CAShapeLayer()
            bar.shadowColor = ReadingPalette.mint.cgColor
            bar.shadowOffset = .zero
            bar.shadowRadius = 4
            bars.append(bar)
        }
        comet.colors = [NSColor.clear.cgColor, ReadingPalette.mintLight.cgColor, NSColor.clear.cgColor]
        comet.locations = [0, 0.5, 1]
        comet.startPoint = CGPoint(x: 0, y: 0.5)
        comet.endPoint = CGPoint(x: 1, y: 0.5)
        comet.bounds = CGRect(x: 0, y: 0, width: 36, height: 3)
        comet.cornerRadius = 1.5
        comet.shadowColor = ReadingPalette.mintLight.cgColor
        comet.shadowOffset = .zero
        comet.shadowRadius = 5
        comet.shadowOpacity = 0.9
        comet.shadowPath = CGPath(roundedRect: comet.bounds, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        icon.fillColor = nil
        icon.lineWidth = 2.4
        icon.lineCap = .round
        icon.lineJoin = .round
        icon.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        bloom.fillColor = nil
        bloom.lineWidth = 2
        bloom.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        bloom.path = CGPath(ellipseIn: bloom.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        bloom.opacity = 0
        keycap.fillColor = ReadingPalette.paper.withAlphaComponent(0.08).cgColor
        keycap.strokeColor = ReadingPalette.paper.withAlphaComponent(0.3).cgColor
        keycap.lineWidth = 1
        keycap.bounds = CGRect(x: 0, y: 0, width: 30, height: 18)
        keycap.path = CGPath(roundedRect: keycap.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
        keycapText.string = "esc"
        keycapText.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        keycapText.fontSize = 9
        keycapText.alignmentMode = .center
        keycapText.foregroundColor = ReadingPalette.paper.withAlphaComponent(0.75).cgColor
        keycapText.contentsScale = 2
        keycapText.bounds = CGRect(x: 0, y: 0, width: 30, height: 11)
        keycap.addSublayer(keycapText)
        keycapText.position = CGPoint(x: 15, y: 8)
        border.fillColor = nil
        border.lineWidth = 1
        for layer in [tint, depth, glow] + bars + [comet, icon, bloom, keycap, rim, border] { canvas.layer?.addSublayer(layer) }
        setAccent(ReadingPalette.mint)

        note.font = .systemFont(ofSize: 11.5, weight: .semibold)
        note.textColor = ReadingPalette.paper.withAlphaComponent(0.92)
        note.lineBreakMode = .byTruncatingTail
        note.alphaValue = 0
        note.setAccessibilityIdentifier("readingStatusTitle")
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
        queueBadge.contentTintColor = ReadingPalette.mintLight
        queueBadge.isBordered = false
        queueBadge.target = self
        queueBadge.action = #selector(openControls)
        queueBadge.alignment = .center
        queueBadge.wantsLayer = true
        queueBadge.layer?.backgroundColor = ReadingPalette.void.cgColor
        queueBadge.layer?.cornerRadius = 8
        queueBadge.isHidden = true
        queueBadge.setAccessibilityIdentifier("readingQueueCount")
        addSubview(queueBadge)
        body.toolTip = "Wellenform ziehen: links, rechts oder unten einrasten"
        body.onDragStart = { [weak self] in self?.onDragStart?($0) }
        body.onDragMove = { [weak self] in self?.onDragMove?($0) }
        body.onDragEnd = { [weak self] in self?.onDragEnd?() }
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { clock?.invalidate() }

    func setQueueCount(_ count: Int) {
        queueBadge.title = state == .failed ? "?" : count > 0 ? "+\(count)" : "···"
        queueBadge.setAccessibilityLabel(state == .failed ? "Einrichtung und Fehlerhilfe öffnen" : "Wiedergabe und Warteschlange · \(count) Texte")
        queueBadge.isHidden = !state.isActive && state != .failed
        tick(now: CACurrentMediaTime())
    }

    @objc private func openControls() { onOpenControls?(queueBadge) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if hit === queueBadge || hit.isDescendant(of: queueBadge) { return hit }
        if hit === button || hit.isDescendant(of: button) { return hit }
        // Decorative layers and status labels are one drag surface, not a stop target.
        if hit === body || hit.isDescendant(of: body) { return body }
        return nil
    }
    override func layout() {
        super.layout()
        for shadow in [softShadow, contactShadow] { shadow.frame = bounds }
        glow.bounds = CGRect(x: 0, y: 0, width: 220, height: 150)
    }

    // MARK: State

    func present(_ state: ReadingPanelState, opening: Bool, action: @escaping () -> Void) {
        let previous = self.state
        let now = CACurrentMediaTime()
        self.state = state
        self.action = action
        exitStart = nil
        alphaValue = 1
        if opening {
            width = Metrics.height; widthVelocity = 0; content = 0; opened = true
            level = 0; previousLevel = 0; terminal = 0; hover = 0; noteBlend = 0; press = 0
            heights = [Double](repeating: 3, count: Metrics.barCount)
            bumpStart = nil; pulseStart = nil
            lastTick = nil
        }
        if previous != state || opening { changed = now }
        if state != .speaking { targetLevel = 0 }
        toolTip = state.detail
        setAccessibilityLabel("Vorlesestatus: " + state.title)
        setAccessibilityHelp(state.detail)
        setAccent(state.needsAttention ? ReadingPalette.amber : ReadingPalette.mint)
        button.terminal = !state.isActive
        button.isEnabled = true
        button.setAccessibilityLabel(state.isActive ? "Vorlesen stoppen" : "Status schließen")
        button.toolTip = state.isActive ? "Gesamten Vorgang stoppen (Esc)" : "Status schließen"
        note.stringValue = state.title
        noteUntil = state.needsAttention ? now + 2.4 : 0
        if !state.isActive {
            showIcon(for: state, drawn: opened && !opening && previous.isActive && !reduced)
            if state == .finished && !opening && !reduced {
                bumpStart = now
                runBloom()
            }
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
        resumeClock()
    }

    func stopAnimating() {
        clock?.isPaused = true
        targetLevel = 0
        level = 0
        action = nil
    }

    @objc private func activate() { action?() }

    private func setAccent(_ color: NSColor) {
        glow.colors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor]
        icon.strokeColor = color.cgColor
        bloom.strokeColor = color.cgColor
        for bar in bars { bar.shadowColor = color.cgColor }
    }

    private func showIcon(for state: ReadingPanelState, drawn: Bool) {
        let path = CGMutablePath()
        switch state {
        case .finished:
            path.move(to: CGPoint(x: 4, y: 12))
            path.addLine(to: CGPoint(x: 9.5, y: 6.5))
            path.addLine(to: CGPoint(x: 20, y: 17.5))
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

    private func runBloom() {
        bloom.removeAllAnimations()
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.5
        scale.toValue = 1.9
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.85, 0]
        fade.keyTimes = [0, 0.2, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.6
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bloom.add(group, forKey: "bloom")
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
        let dt = min(1.0 / 20, max(1.0 / 240, now - (lastTick ?? now - 1.0 / 60)))
        lastTick = now
        let reduced = self.reduced || paused
        let exiting = exitStart != nil
        func approach(_ value: inout Double, _ goal: Double, rate: Double) {
            value += (goal - value) * (reduced ? 1 : 1 - exp(-dt * rate))
        }
        approach(&terminal, state.showsWaveform ? 0 : 1, rate: 10)
        approach(&hover, hovering && !exiting ? 1 : 0, rate: 12)
        approach(&press, pressing ? 1 : 0, rate: 30)
        let noteWanted = !isVertical && state.needsAttention && !exiting && (now < noteUntil || hovering)
        approach(&noteBlend, noteWanted ? 1 : 0, rate: 10)

        // Width spring: one perceptible overshoot on opening, none on closing.
        let widthGoal: Double
        if exiting { widthGoal = Metrics.height }
        else if state.showsWaveform { widthGoal = Metrics.activeWidth + Metrics.keycapWidth * hover }
        else if state.needsAttention { widthGoal = Metrics.terminalWidth + noteBlend * max(0, noteWidth()) }
        else { widthGoal = Metrics.terminalWidth }
        let goal = widthGoal * (1 - 0.02 * press)
        if reduced {
            width = goal; widthVelocity = 0
        } else {
            let stiffness = exiting ? 340.0 : 190.0
            let damping = exiting ? 38.0 : 17.0
            widthVelocity += (-stiffness * (width - goal) - damping * widthVelocity) * dt
            width += widthVelocity * dt
        }
        let contentGoal = exiting ? 0.0 : (width > Metrics.height + 20 ? 1.0 : 0.0)
        approach(&content, contentGoal, rate: exiting ? 24 : 14)

        if reduced {
            level = state == .speaking ? 0.35 : 0
        } else {
            let levelGoal = state == .speaking ? targetLevel : 0
            approach(&level, levelGoal, rate: levelGoal > level ? 45 : 9)
            if state == .speaking && targetLevel - previousLevel > 0.22 && (pulseStart.map { now - $0 > 0.18 } ?? true) {
                pulseStart = now
            }
            previousLevel += (targetLevel - previousLevel) * (1 - exp(-dt * 20))
            phase += dt * (3.2 + level * 4)
        }
        updateBars(now: now, dt: dt, reduced: reduced)
        if let bumpStart, now - bumpStart > 0.45 { self.bumpStart = nil }
        layoutFrame(now: now, reduced: reduced)
        if let exitStart { alphaValue = max(0, 1 - (now - exitStart) / 0.22) }

        let settled = abs(width - goal) < 0.05 && abs(widthVelocity) < 0.5 && abs(content - contentGoal) < 0.01
            && abs(terminal - (state.showsWaveform ? 0 : 1)) < 0.01 && abs(hover - (hovering ? 1 : 0)) < 0.01
            && abs(noteBlend - (noteWanted ? 1 : 0)) < 0.01 && bumpStart == nil && press < 0.01
            && (!state.needsAttention || now >= noteUntil)
        if !state.isActive && settled && !exiting { clock?.isPaused = true }
    }

    private func noteWidth() -> Double {
        note.sizeThatFits(NSSize(width: 400, height: 20)).width + 12
    }

    private func updateBars(now: TimeInterval, dt: Double, reduced: Bool) {
        let shape: [Double] = [0.2, 0.45, 0.7, 0.9, 1, 0.9, 0.7, 0.45, 0.2]
        let sinceChange = now - changed
        for index in 0..<Metrics.barCount {
            var goal = 3.0
            switch state {
            case .recognizing:
                goal = 3
            case .positioning:
                goal = 6 + shape[index] * 14
            case .preparing:
                if reduced {
                    goal = 6 + shape[index] * 8
                } else {
                    // The voice takes a breath: 1.2 s in, a short hold, 1.3 s out. A drop falls into the
                    // middle when preparation starts and at the top of every breath, and ripples outward.
                    let cycle = 2.6
                    let t = sinceChange.truncatingRemainder(dividingBy: cycle)
                    let breath: Double
                    if t < 1.2 { let u = t / 1.2; breath = u * u * (3 - 2 * u) }
                    else if t < 1.3 { breath = 1 }
                    else { let u = (t - 1.3) / 1.3; breath = 1 - u * u * (3 - 2 * u) }
                    let age = sinceChange < 1.2 ? sinceChange : (t >= 1.2 ? t - 1.2 : t + cycle - 1.2)
                    let distance = abs(Double(index) - Double(Metrics.barCount - 1) / 2)
                    let ripple = max(0, 1 - abs(age * 14 - distance) / 1.3) * 7 * exp(-age * 2.2)
                    goal = 4 + shape[index] * (3 + 12 * breath) + ripple
                }
            case .speaking:
                if reduced {
                    goal = 4 + shape[index] * 22
                } else {
                    let wave = 0.55 + 0.45 * sin(phase + Double(index) * 0.85)
                    let kick = pulseStart.map { start -> Double in
                        let travel = (now - start) * 32 - Double(index)
                        return max(0, 1 - abs(travel) / 2.2) * 9
                    } ?? 0
                    goal = 4 + (level * 24 + 1.5) * wave * (0.55 + 0.45 * shape[index]) + kick * level
                }
            default:
                goal = 3
            }
            if pressing { goal = 3 }
            goal = min(goal, Metrics.barMaxHeight)
            if reduced {
                heights[index] = goal
            } else {
                let rate = goal > heights[index] ? 40.0 : 11.0
                heights[index] += (goal - heights[index]) * (1 - exp(-dt * rate))
            }
        }
    }

    private func layoutFrame(now: TimeInterval, reduced: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bump = bumpStart.map { sin(min(1, (now - $0) / 0.45) * .pi) * 0.04 } ?? 0
        // Squash: a fast-moving body flattens slightly and settles back.
        let squash = reduced ? 0 : min(3, abs(widthVelocity) * 0.006)
        let w = min((isVertical ? bounds.height : bounds.width) - 8, max(Metrics.height, width)) * (1 + bump)
        let h = (Metrics.height - squash) * (1 + bump * 0.7)
        let cross = Metrics.bodyBottom - (h - Metrics.height) / 2
        let bodyRect = isVertical
            ? CGRect(x: cross, y: (bounds.height - w) / 2, width: h, height: w)
            : CGRect(x: (bounds.width - w) / 2, y: cross, width: w, height: h)
        let radius = h / 2
        body.frame = bodyRect
        queueBadge.frame = CGRect(x: bodyRect.midX - 20, y: min(bounds.height - 24, bodyRect.maxY), width: 40, height: 24)
        body.layer?.cornerRadius = radius
        effect.layer?.cornerRadius = radius
        let transparencyReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect.isHidden = transparencyReduced
        tint.opacity = transparencyReduced ? 1 : 0.9
        let shadowPath = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        softShadow.shadowPath = shadowPath
        contactShadow.shadowPath = shadowPath
        softShadow.opacity = Float(alphaValue)
        contactShadow.opacity = Float(alphaValue)

        let local = CGRect(origin: .zero, size: bodyRect.size)
        // Map the horizontal layout into a top-to-bottom stack; glyphs themselves stay upright.
        let centerY = h / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            isVertical ? CGPoint(x: y, y: w - x) : CGPoint(x: x, y: y)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            isVertical ? CGRect(x: y, y: w - x - width, width: height, height: width)
                : CGRect(x: x, y: y, width: width, height: height)
        }
        tint.frame = local
        depth.frame = local
        rim.frame = local
        rim.path = CGPath(roundedRect: local.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius - 1.5, cornerHeight: radius - 1.5, transform: nil)
        border.frame = local
        border.path = CGPath(roundedRect: local.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius - 0.5, cornerHeight: radius - 0.5, transform: nil)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let accent = state.needsAttention ? ReadingPalette.amber : ReadingPalette.paper
        border.strokeColor = accent.withAlphaComponent(contrast ? 0.9 : (state.needsAttention ? 0.5 : 0.14) + hover * 0.1).cgColor

        // Bars sit left; the Esc keycap slides in on hover; terminal symbols take the bars' place.
        let keycapShift = Metrics.keycapWidth * hover
        let barsX = Metrics.padding + keycapShift
        let barsCenter = point(barsX + Metrics.barsWidth / 2, centerY)
        let visible = Float(content * (1 - terminal))
        var energy = 0.0
        for (index, bar) in bars.enumerated() {
            let height = heights[index]
            let t = CGFloat(min(1, max(0, (height - 3) / (Metrics.barMaxHeight - 3))))
            energy += Double(t)
            let x = barsX + CGFloat(index) * (Metrics.barWidth + Metrics.barGap)
            bar.frame = rect(x, centerY - height / 2, Metrics.barWidth, height)
            bar.path = CGPath(roundedRect: CGRect(origin: .zero, size: bar.frame.size),
                              cornerWidth: Metrics.barWidth / 2, cornerHeight: Metrics.barWidth / 2, transform: nil)
            let base = state.needsAttention ? ReadingPalette.amber : ReadingPalette.mint
            let dim = ReadingPalette.mix(base.withAlphaComponent(0.5), base, min(1, t * 3))
            let lit = ReadingPalette.mix(dim, ReadingPalette.mintLight, pow(t, 1.4))
            bar.fillColor = ReadingPalette.mix(lit, ReadingPalette.paper, max(0, t - 0.8) * 3).cgColor
            bar.shadowOpacity = Float(t) * 0.9
            bar.opacity = visible
        }
        energy /= Double(Metrics.barCount)
        glow.position = barsCenter
        glow.opacity = Float(content) * Float((1 - terminal) * (0.1 + energy * 0.8)
            + terminal * (state == .finished ? 0.25 : state.needsAttention ? 0.18 : 0.05))
            + Float((1 - content) * 0.9)

        let travel = reduced ? 0.5 : (now * 0.9).truncatingRemainder(dividingBy: 1)
        comet.position = point(barsX + Metrics.barsWidth * travel, centerY)
        comet.opacity = reduced ? 0 : Float((state == .recognizing ? 1 : 0) * content * (1 - terminal))

        icon.position = point(18 + 12, centerY)
        icon.opacity = Float(terminal * terminal * (3 - 2 * terminal) * content)
        bloom.position = icon.position

        keycap.position = point(Metrics.padding - 4 + 15, centerY)
        keycapText.string = state == .positioning ? (isVertical ? "↕" : "↔") : "esc"
        keycap.opacity = Float(hover * content * (1 - terminal))

        let buttonX = w - Metrics.button
        let noteX = 18 + 24 + 10.0
        note.frame = CGRect(x: noteX, y: centerY - 8, width: max(0, buttonX - noteX - 6), height: 16)
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
        face.path = CGPath(ellipseIn: CGRect(x: 6, y: 6, width: 32, height: 32), transform: nil)
        face.lineWidth = 1
        glyph.lineWidth = 2
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
        let scale = down ? 0.84 : 1.0
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for layer in [face, glyph] {
            if !reduced {
                let spring = CASpringAnimation(keyPath: "transform.scale")
                spring.fromValue = (layer.presentation() ?? layer).value(forKeyPath: "transform.scale")
                spring.toValue = scale
                spring.stiffness = down ? 640 : 260
                spring.damping = down ? 32 : 12
                spring.duration = spring.settlingDuration
                layer.add(spring, forKey: "press")
            }
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    private func updateFace() {
        face.fillColor = ReadingPalette.paper.withAlphaComponent(pressed ? 0.3 : hovered ? 0.19 : 0.11).cgColor
        face.strokeColor = ReadingPalette.paper.withAlphaComponent(hovered ? 0.38 : 0.2).cgColor
    }

    private func updateGlyph() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        if terminal {
            path.move(to: CGPoint(x: 17.5, y: 17.5)); path.addLine(to: CGPoint(x: 26.5, y: 26.5))
            path.move(to: CGPoint(x: 17.5, y: 26.5)); path.addLine(to: CGPoint(x: 26.5, y: 17.5))
            glyph.fillColor = nil
            glyph.strokeColor = ReadingPalette.paper.cgColor
        } else {
            path.addRoundedRect(in: CGRect(x: 16.5, y: 16.5, width: 11, height: 11), cornerWidth: 3, cornerHeight: 3)
            glyph.fillColor = ReadingPalette.paper.cgColor
            glyph.strokeColor = nil
        }
        glyph.path = path
        CATransaction.commit()
    }
}
