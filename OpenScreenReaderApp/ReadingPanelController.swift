import AppKit
import QuartzCore

// Only status and an ephemeral scalar level cross the presentation boundary.
enum ReadingPanelState: Hashable {
    case recognizing, preparing, speaking, finished, stopped, noText, failed
    var title: String {
        switch self {
        case .recognizing: "Text erkennen …"
        case .preparing: "Vorbereiten …"
        case .speaking: "Vorlesen"
        case .finished: "Fertig"
        case .stopped: "Gestoppt"
        case .noText: "Kein Text erkannt"
        case .failed: "Vorlesen nicht möglich"
        }
    }
    var detail: String {
        switch self {
        case .recognizing, .preparing, .speaking: "Esc zum Stoppen"
        case .finished: "Alles vorgelesen"
        case .stopped: "Vorlesen beendet"
        case .noText: "Wähle einen Bereich mit Text."
        case .failed: "Details im App-Menü"
        }
    }
    var isActive: Bool { self == .recognizing || self == .preparing || self == .speaking }
    var dismissesAutomatically: Bool { self == .finished || self == .stopped }
    var needsAttention: Bool { self == .noText || self == .failed }
}

@MainActor
protocol ReadingStatusPresenting: AnyObject {
    func show(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?)
    func updateLevel(_ level: Double)
    func hide()
}

@MainActor
final class ReadingPanelController: NSObject, ReadingStatusPresenting {
    private(set) var state: ReadingPanelState?
    private(set) var panel: ReadingStatusPanel?
    private var content: ReadingControlView?
    private var displayID: UInt32?
    private var dismissalTask: Task<Void, Never>?
    private var transitionTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let terminalDuration: Duration
    private let interfaceSounds: (any InterfaceSoundPlaying)?

    init(terminalDuration: Duration = .milliseconds(1100), interfaceSounds: (any InterfaceSoundPlaying)? = nil) {
        self.terminalDuration = terminalDuration
        self.interfaceSounds = interfaceSounds
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(displayLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    isolated deinit {
        dismissalTask?.cancel()
        transitionTask?.cancel()
        content?.stopAnimating()
        panel?.close()
        NotificationCenter.default.removeObserver(self)
    }

    func show(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?) {
        dismissalTask?.cancel()
        transitionTask?.cancel()
        generation &+= 1
        let current = generation
        guard let screen = Self.screen(for: displayID) else { hide(); return }
        self.state = state
        self.displayID = displayID
        let panel = panel ?? ReadingStatusPanel()
        self.panel = panel
        let appearing = content == nil
        let view = content ?? ReadingControlView(frame: NSRect(origin: .zero, size: Self.frame(in: screen.visibleFrame).size))
        content = view
        if appearing { panel.contentView = view }
        panel.setFrame(Self.frame(in: screen.visibleFrame), display: true)
        view.onPress = { [weak self] in self?.interfaceSounds?.play(.tap) }
        view.present(state, opening: appearing) { [weak self] in
            guard let self, self.generation == current else { return }
            if state.isActive { onStop?() } else { self.dismiss() }
        }
        panel.orderFrontRegardless()
        if state.dismissesAutomatically {
            dismissalTask = Task { @MainActor [weak self, terminalDuration] in
                do { try await Task.sleep(for: terminalDuration) } catch { return }
                guard let self, self.generation == current else { return }
                self.dismiss()
            }
        }
    }

    func updateLevel(_ level: Double) {
        guard state == .speaking else { return }
        content?.setLevel(level)
    }

    // Selection/capture and cancellation cleanup never wait for a visual transition.
    func hide() {
        generation &+= 1
        dismissalTask?.cancel()
        transitionTask?.cancel()
        dismissalTask = nil
        transitionTask = nil
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
        content?.retract()
        transitionTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(240)) } catch { return }
            guard let self, self.generation == current else { return }
            self.hide()
        }
    }

    /// The window is larger than the visible body so the drawn shadow has room.
    static func frame(in visibleFrame: CGRect) -> CGRect {
        let width = min(ReadingControlView.Metrics.surface.width, visibleFrame.width)
        let height = min(ReadingControlView.Metrics.surface.height, visibleFrame.height)
        let inset = min(4, max(0, visibleFrame.height - height))
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.minY + inset, width: width, height: height)
    }
    private static func screen(for displayID: UInt32) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
    @objc private func displayLayoutChanged() {
        guard let displayID, let screen = Self.screen(for: displayID) else { hide(); return }
        panel?.setFrame(Self.frame(in: screen.visibleFrame), display: true)
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

enum ReadingPalette {
    static let ink = NSColor(srgbRed: 11 / 255, green: 23 / 255, blue: 36 / 255, alpha: 1)
    static let paper = NSColor(srgbRed: 247 / 255, green: 244 / 255, blue: 237 / 255, alpha: 1)
    static let mint = NSColor(srgbRed: 85 / 255, green: 224 / 255, blue: 190 / 255, alpha: 1)
    static let mintLight = NSColor(srgbRed: 184 / 255, green: 247 / 255, blue: 231 / 255, alpha: 1)
    /// Attention accent. Warm, not alarming; never used as body text.
    static let amber = NSColor(srgbRed: 1, green: 0.72, blue: 0.4, alpha: 1)
}

/// A small floating reading instrument: a translucent Local Ink island that
/// springs open from a dot, carries a glowing Voice Mint ribbon driven by the
/// rendered speech level, and closes back into the dot when it is done.
///
/// Fixed surface geometry, manual per-frame layout and Core Animation layers.
/// No Auto Layout and no SwiftUI hosting size constraints take part.
@MainActor
final class ReadingControlView: NSView {
    enum Metrics {
        static let surface = CGSize(width: 376, height: 100)
        static let body = CGSize(width: 312, height: 60)
        static let collapsed: CGFloat = 60
        static let corner: CGFloat = 20
        static let padding: CGFloat = 18
        static let ribbon: CGFloat = 92
        static let button: CGFloat = 44
        static let bodyBottom: CGFloat = 24
    }

    var onPress: (() -> Void)?

    private let shadowHost = NSView()
    private let softShadow = CALayer()
    private let contactShadow = CALayer()
    private let body = HoverView()
    private let effect = NSVisualEffectView()
    private let canvas = NSView()
    private let tint = CALayer()
    private let depth = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let halo = CAShapeLayer()
    private let ribbon = CAGradientLayer()
    private let ribbonMask = CAShapeLayer()
    private let comet = CAGradientLayer()
    private let icon = CAShapeLayer()
    private let border = CAShapeLayer()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let button = ReadingStopButton(frame: NSRect(x: 0, y: 0, width: Metrics.button, height: Metrics.button))

    private var clock: CADisplayLink?
    private var state: ReadingPanelState = .recognizing
    private var action: (() -> Void)?
    private var expansion = 0.0
    private var expansionVelocity = 0.0
    private var exitStart: TimeInterval?
    private var bumpStart: TimeInterval?
    private var content = 0.0
    private var level = 0.0
    private var targetLevel = 0.0
    private var voice = 0.0
    private var prepare = 0.0
    private var scan = 0.0
    private var terminal = 0.0
    private var hover = 0.0
    private var hovering = false
    private var phases = (0.0, 0.0, 0.0)
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
        softShadow.shadowOpacity = 0.45
        softShadow.shadowRadius = 16
        softShadow.shadowOffset = CGSize(width: 0, height: -6)
        contactShadow.shadowOpacity = 0.4
        contactShadow.shadowRadius = 2.5
        contactShadow.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(shadowHost)

        body.wantsLayer = true
        body.layer?.masksToBounds = true
        body.layer?.cornerCurve = .continuous
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
        effect.layer?.cornerCurve = .continuous
        effect.autoresizingMask = [.width, .height]
        body.addSubview(effect)

        canvas.wantsLayer = true
        canvas.autoresizingMask = [.width, .height]
        body.addSubview(canvas)

        tint.backgroundColor = ReadingPalette.ink.cgColor
        depth.colors = [ReadingPalette.paper.withAlphaComponent(0.11).cgColor, NSColor.clear.cgColor,
                        NSColor.black.withAlphaComponent(0.22).cgColor]
        depth.locations = [0, 0.48, 1]
        depth.startPoint = CGPoint(x: 0.5, y: 1)
        depth.endPoint = CGPoint(x: 0.5, y: 0)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        halo.fillColor = nil
        halo.lineWidth = 7
        halo.lineCap = .round
        halo.lineJoin = .round
        halo.shadowOffset = .zero
        halo.shadowRadius = 7
        halo.shadowOpacity = 1
        ribbon.startPoint = CGPoint(x: 0, y: 0.5)
        ribbon.endPoint = CGPoint(x: 1, y: 0.5)
        ribbonMask.fillColor = nil
        ribbonMask.strokeColor = NSColor.black.cgColor
        ribbonMask.lineWidth = 2.8
        ribbonMask.lineCap = .round
        ribbonMask.lineJoin = .round
        ribbon.mask = ribbonMask
        comet.colors = [NSColor.clear.cgColor, ReadingPalette.mintLight.cgColor, NSColor.clear.cgColor]
        comet.locations = [0, 0.5, 1]
        comet.startPoint = CGPoint(x: 0, y: 0.5)
        comet.endPoint = CGPoint(x: 1, y: 0.5)
        comet.bounds = CGRect(x: 0, y: 0, width: 64, height: 3)
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
        border.fillColor = nil
        border.lineWidth = 1
        for layer in [tint, depth, glow, halo, ribbon, comet, icon, border] { canvas.layer?.addSublayer(layer) }
        setAccent(ReadingPalette.mint)

        title.font = .systemFont(ofSize: 12.5, weight: .semibold)
        title.textColor = ReadingPalette.paper.withAlphaComponent(0.94)
        title.lineBreakMode = .byTruncatingTail
        title.setAccessibilityIdentifier("readingStatusTitle")
        detail.font = .systemFont(ofSize: 10.5, weight: .medium)
        detail.textColor = ReadingPalette.paper.withAlphaComponent(0.56)
        detail.lineBreakMode = .byTruncatingTail
        body.addSubview(title)
        body.addSubview(detail)

        button.target = self
        button.action = #selector(activate)
        button.onPress = { [weak self] in self?.onPress?() }
        button.setAccessibilityIdentifier("readingStatusAction")
        body.addSubview(button)
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { clock?.invalidate() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func layout() {
        super.layout()
        for shadow in [softShadow, contactShadow] { shadow.frame = bounds }
        glow.bounds = CGRect(x: 0, y: 0, width: 260, height: 170)
    }

    // MARK: State

    func present(_ state: ReadingPanelState, opening: Bool, action: @escaping () -> Void) {
        let previous = self.state
        self.state = state
        self.action = action
        exitStart = nil
        alphaValue = 1
        if opening {
            expansion = 0; expansionVelocity = 0; content = 0
            level = 0; voice = 0; prepare = 0; scan = 0; terminal = 0; hover = 0
            bumpStart = nil
            lastTick = nil
        }
        if state != .speaking { targetLevel = 0 }
        title.stringValue = state.title
        detail.stringValue = state.detail
        toolTip = state.detail
        setAccessibilityLabel("Vorlesestatus: " + state.title)
        setAccessibilityHelp(state.detail)
        setAccent(state.needsAttention ? ReadingPalette.amber : ReadingPalette.mint)
        button.terminal = !state.isActive
        button.isEnabled = true
        button.setAccessibilityLabel(state.isActive ? "Vorlesen stoppen" : "Status schließen")
        button.toolTip = state.isActive ? "Gesamten Vorgang stoppen (Esc)" : "Status schließen"
        if !state.isActive {
            showIcon(for: state, drawn: !opening && previous.isActive && !reduced)
            if state == .finished && !opening && !reduced { bumpStart = CACurrentMediaTime() }
        }
        resumeClock()
        tick(now: CACurrentMediaTime())
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
        glow.colors = [color.withAlphaComponent(0.5).cgColor, color.withAlphaComponent(0).cgColor]
        halo.strokeColor = color.withAlphaComponent(0.55).cgColor
        halo.shadowColor = color.cgColor
        ribbon.colors = [ReadingPalette.mintLight.cgColor, color.cgColor, color.withAlphaComponent(0.72).cgColor]
        icon.strokeColor = color.cgColor
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

    fileprivate func tick(now: TimeInterval) {
        let dt = min(1.0 / 20, max(1.0 / 240, now - (lastTick ?? now - 1.0 / 60)))
        lastTick = now
        let reduced = self.reduced
        let exiting = exitStart != nil
        let expansionGoal = exiting ? 0.0 : 1.0
        if reduced {
            expansion = expansionGoal
            expansionVelocity = 0
        } else {
            // One damped spring: perceptible overshoot on opening, none on closing.
            let stiffness = exiting ? 320.0 : 175.0
            let damping = exiting ? 36.0 : 17.5
            expansionVelocity += (-stiffness * (expansion - expansionGoal) - damping * expansionVelocity) * dt
            expansion += expansionVelocity * dt
        }
        func approach(_ value: inout Double, _ goal: Double, rate: Double) {
            value += (goal - value) * (reduced ? 1 : 1 - exp(-dt * rate))
        }
        approach(&voice, state == .speaking ? 1 : 0, rate: 8)
        approach(&prepare, state == .preparing ? 1 : 0, rate: 8)
        approach(&scan, state == .recognizing ? 1 : 0, rate: 8)
        approach(&terminal, state.isActive ? 0 : 1, rate: 10)
        approach(&hover, hovering ? 1 : 0, rate: 12)
        let contentGoal = exiting ? 0.0 : (expansion > 0.55 ? 1.0 : 0.0)
        approach(&content, contentGoal, rate: exiting ? 24 : 12)
        if reduced {
            level = state == .speaking ? 0.3 : 0
        } else {
            let goal = state == .speaking ? targetLevel : 0
            approach(&level, goal, rate: goal > level ? 42 : 9)
            phases.0 += dt * 5.6
            phases.1 += dt * 3.3
            phases.2 += dt * 8.1
        }
        if let bumpStart, now - bumpStart > 0.4 { self.bumpStart = nil }
        layoutFrame(now: now, reduced: reduced)
        if let exitStart { alphaValue = max(0, 1 - (now - exitStart) / 0.22) }

        let settled = abs(expansion - expansionGoal) < 0.002 && abs(expansionVelocity) < 0.02
            && abs(content - contentGoal) < 0.01 && abs(terminal - (state.isActive ? 0 : 1)) < 0.01
            && abs(hover - (hovering ? 1 : 0)) < 0.01 && bumpStart == nil
        if !state.isActive && settled && !exiting { clock?.isPaused = true }
    }

    private func layoutFrame(now: TimeInterval, reduced: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let progress = max(0, expansion)
        let bump = bumpStart.map { sin(min(1, (now - $0) / 0.4) * .pi) * 0.03 } ?? 0
        let width = min(bounds.width - 8, Metrics.collapsed + (Metrics.body.width - Metrics.collapsed) * progress) * (1 + bump)
        let height = Metrics.body.height * (1 + bump * 0.6)
        let bodyRect = CGRect(x: (bounds.width - width) / 2, y: Metrics.bodyBottom - (height - Metrics.body.height) / 2,
                              width: width, height: height)
        let radius = min(Metrics.corner + (Metrics.collapsed / 2 - Metrics.corner) * max(0, 1 - min(1, progress)), height / 2)
        body.frame = bodyRect
        body.layer?.cornerRadius = radius
        effect.layer?.cornerRadius = radius
        let transparencyReduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        effect.isHidden = transparencyReduced
        tint.opacity = transparencyReduced ? 1 : 0.86
        let shadowPath = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        softShadow.shadowPath = shadowPath
        contactShadow.shadowPath = shadowPath
        softShadow.opacity = Float(alphaValue)
        contactShadow.opacity = Float(alphaValue)

        let local = CGRect(origin: .zero, size: bodyRect.size)
        let centerY = local.midY
        tint.frame = local
        depth.frame = local
        border.frame = local
        border.path = CGPath(roundedRect: local.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius - 0.5,
                             cornerHeight: radius - 0.5, transform: nil)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        border.strokeColor = ReadingPalette.paper.withAlphaComponent(contrast ? 0.85 : 0.13 + hover * 0.09).cgColor

        // The ribbon lives in a fixed left region; the text slides left when the ribbon
        // collapses into a terminal symbol.
        let ribbonRect = CGRect(x: Metrics.padding, y: 0, width: Metrics.ribbon, height: local.height)
        ribbon.frame = ribbonRect
        ribbonMask.frame = CGRect(origin: .zero, size: ribbonRect.size)
        halo.frame = ribbonRect
        let breath = reduced ? 0 : sin(now * 2.1) * 0.6
        let amplitude = voice * (1.4 + level * 11.5 + breath) + prepare * (2.2 + (reduced ? 0 : sin(now * 3.3) * 0.8))
        let path = ribbonPath(amplitude: amplitude, width: ribbonRect.width, centerY: centerY)
        ribbonMask.path = path
        halo.path = path
        let visible = Float(content * (1 - terminal))
        ribbon.opacity = visible * Float(1 - scan * 0.45)
        halo.opacity = visible * Float(0.35 + voice * (0.15 + level * 0.6) + prepare * 0.2)
        glow.position = CGPoint(x: ribbonRect.midX, y: centerY)
        glow.opacity = Float(content) * Float((1 - terminal) * (0.12 + voice * (0.08 + level * 0.55) + prepare * 0.12 + scan * 0.08)
            + terminal * (state == .finished ? 0.2 : state.needsAttention ? 0.14 : 0))

        let travel = reduced ? 0.5 : (now * 0.8).truncatingRemainder(dividingBy: 1)
        comet.position = CGPoint(x: ribbonRect.minX + ribbonRect.width * travel, y: centerY)
        comet.opacity = reduced ? 0 : Float(scan * content * (1 - terminal))

        let eased = terminal * terminal * (3 - 2 * terminal)
        icon.position = CGPoint(x: Metrics.padding + 11, y: centerY)
        icon.opacity = Float(eased * content)
        let openTextX = Metrics.padding + Metrics.ribbon + 14
        let terminalTextX = Metrics.padding + 24 + 12
        let textX = openTextX + (terminalTextX - openTextX) * eased
        let buttonX = local.width - 10 - Metrics.button
        let textWidth = max(0, buttonX - textX - 8)
        title.frame = CGRect(x: textX, y: centerY + 1, width: textWidth, height: 16)
        detail.frame = CGRect(x: textX, y: centerY - 15, width: textWidth, height: 13)
        title.alphaValue = content
        detail.alphaValue = content * (0.75 + hover * 0.25)
        button.frame = CGRect(x: buttonX, y: (local.height - Metrics.button) / 2, width: Metrics.button, height: Metrics.button)
        button.alphaValue = content
    }

    private func ribbonPath(amplitude: Double, width: CGFloat, centerY: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let segments = 44
        for index in 0...segments {
            let t = Double(index) / Double(segments)
            let window = pow(sin(t * .pi), 1.15)
            let wave = sin(t * .pi * 3.4 - phases.0) * 0.62
                + sin(t * .pi * 5.7 + 1.1 - phases.1) * 0.27
                + sin(t * .pi * 9.1 + 2.3 + phases.2) * 0.11
            let point = CGPoint(x: Double(width) * t, y: Double(centerY) + wave * window * amplitude)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
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
}

/// A 44 pt control whose visible face compresses on press and springs back.
/// The hit area and screen position never move.
@MainActor
final class ReadingStopButton: NSButton {
    var terminal = false { didSet { updateGlyph() } }
    var onPress: (() -> Void)?
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
        face.path = CGPath(ellipseIn: CGRect(x: 4, y: 4, width: 36, height: 36), transform: nil)
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
    }

    private func press(_ down: Bool) {
        pressed = down
        let scale = down ? 0.86 : 1.0
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for layer in [face, glyph] {
            if !reduced {
                let spring = CASpringAnimation(keyPath: "transform.scale")
                spring.fromValue = (layer.presentation() ?? layer).value(forKeyPath: "transform.scale")
                spring.toValue = scale
                spring.stiffness = down ? 620 : 260
                spring.damping = down ? 32 : 13
                spring.duration = spring.settlingDuration
                layer.add(spring, forKey: "press")
            }
            layer.transform = CATransform3DMakeScale(scale, scale, 1)
        }
    }

    private func updateFace() {
        face.fillColor = ReadingPalette.paper.withAlphaComponent(pressed ? 0.28 : hovered ? 0.17 : 0.1).cgColor
        face.strokeColor = ReadingPalette.paper.withAlphaComponent(hovered ? 0.36 : 0.18).cgColor
    }

    private func updateGlyph() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let path = CGMutablePath()
        if terminal {
            path.move(to: CGPoint(x: 17, y: 17)); path.addLine(to: CGPoint(x: 27, y: 27))
            path.move(to: CGPoint(x: 17, y: 27)); path.addLine(to: CGPoint(x: 27, y: 17))
            glyph.fillColor = nil
            glyph.strokeColor = ReadingPalette.paper.cgColor
        } else {
            path.addRoundedRect(in: CGRect(x: 16, y: 16, width: 12, height: 12), cornerWidth: 3, cornerHeight: 3)
            glyph.fillColor = ReadingPalette.paper.cgColor
            glyph.strokeColor = nil
        }
        glyph.path = path
        CATransaction.commit()
    }
}
