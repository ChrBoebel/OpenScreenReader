import AppKit

/// Presentation states distinguish a requested paste from a verified insertion.
enum DictationCapsuleState: String, CaseIterable {
    case idle, recording, processing, pasting, inserted, unconfirmed, attention

    var isBusy: Bool { self == .recording || self == .processing || self == .pasting }
}

/// A text-free mini bar: cancel, nine input bars, and finish.
/// The visual body is 120 × 28 pt; separate 32 × 44 pt hit areas stay easy to reach.
/// Only an ephemeral scalar level reaches this view; never PCM or the transcript.
@MainActor
final class DictationCapsuleView: NSView {
    static let surface = CGSize(width: 152, height: 60)
    private let body = NSView(frame: CGRect(x: 16, y: 16, width: 120, height: 28))
    private let effect = NSVisualEffectView()
    private let tint = CALayer()
    private let depth = CAGradientLayer()
    private let symbol = NSImageView()
    var bodyFrame: CGRect { body.frame }
    let finishButton = DictationMiniButton(frame: CGRect(x: 104, y: 8, width: 32, height: 44))
    let dismissButton = DictationMiniButton(frame: CGRect(x: 16, y: 8, width: 32, height: 44))
    private var bars = [CAShapeLayer]()
    private var clock: CADisplayLink?
    private var lastTick: TimeInterval?
    private var visible = false
    private var smoothedLevel = 0.0
    private(set) var state: DictationCapsuleState = .idle
    private(set) var inputLevel = 0.0
    private(set) var barHeights = [CGFloat](repeating: 3, count: 9)
    var isAnimating: Bool { clock != nil }
    var onFinish: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onDetails: (() -> Void)?
    private var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("dictationStatusContent")
        body.wantsLayer = true
        body.layer?.cornerRadius = 14
        body.layer?.shadowColor = NSColor.black.cgColor
        body.layer?.shadowOpacity = 0.3
        body.layer?.shadowRadius = 8
        body.layer?.shadowOffset = CGSize(width: 0, height: -2)
        body.layer?.shadowPath = CGPath(roundedRect: body.bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
        addSubview(body)
        effect.frame = body.bounds
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        body.addSubview(effect)
        tint.frame = body.bounds
        tint.cornerRadius = 14
        depth.frame = body.bounds
        depth.cornerRadius = 14
        depth.colors = SaywingCapsuleStyle.depthColors
        depth.locations = [0, 0.45, 1]
        depth.startPoint = CGPoint(x: 0.5, y: 1)
        depth.endPoint = CGPoint(x: 0.5, y: 0)
        effect.layer?.addSublayer(tint)
        effect.layer?.addSublayer(depth)
        symbol.frame = CGRect(x: 53, y: 7, width: 14, height: 14)
        symbol.setAccessibilityElement(false)
        body.addSubview(symbol)
        for _ in 0..<9 {
            let bar = CAShapeLayer()
            bar.fillColor = ReadingPalette.mint.cgColor
            effect.layer?.addSublayer(bar)
            bars.append(bar)
        }
        dismissButton.isCancel = true
        dismissButton.target = self
        dismissButton.action = #selector(dismiss)
        dismissButton.setAccessibilityIdentifier("dictationDiscard")
        finishButton.target = self
        finishButton.action = #selector(finish)
        finishButton.setAccessibilityIdentifier("dictationFinish")
        finishButton.setAccessibilityLabel("Aufnahme beenden und Text einfügen")
        finishButton.toolTip = "Aufnahme beenden & einfügen"
        addSubview(dismissButton)
        addSubview(finishButton)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        present(.idle, title: "Bereit zum Diktieren", detail: "")
        accessibilityChanged()
    }
    required init?(coder: NSCoder) { nil }
    isolated deinit { clock?.invalidate() }

    func present(_ state: DictationCapsuleState, title: String, detail: String) {
        let changed = self.state != state
        self.state = state
        if changed { inputLevel = 0 }
        finishButton.isEnabled = state == .recording
        finishButton.isHidden = state != .recording
        dismissButton.setAccessibilityLabel(state.isBusy ? "Diktat verwerfen" : "Hinweis schließen")
        dismissButton.toolTip = state.isBusy ? "Verwerfen · Esc" : "Hinweis schließen"
        let glyph: String
        let statusTitle: String
        switch state {
        case .recording: statusTitle = "Aufnahme"; glyph = "mic.fill"
        case .processing: statusTitle = "Text wird erkannt"; glyph = "ellipsis"
        case .pasting: statusTitle = "Einfügen ausgelöst"; glyph = "arrow.up.doc"
        case .inserted: statusTitle = "Eingefügt"; glyph = "checkmark"
        case .unconfirmed: statusTitle = "Einfügen ausgelöst – bitte Zielfeld prüfen"; glyph = "arrow.up.doc"
        case .attention: statusTitle = title; glyph = "exclamationmark"
        case .idle: statusTitle = title.isEmpty ? "Bereit zum Diktieren" : title; glyph = "mic"
        }
        symbol.isHidden = state == .recording || state == .processing
        let accent = state == .attention ? ReadingPalette.amber : ReadingPalette.mint
        symbol.image = NSImage(systemSymbolName: glyph, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        symbol.contentTintColor = accent
        toolTip = [statusTitle, detail].filter { !$0.isEmpty }.joined(separator: "\n")
        setAccessibilityLabel("Saywing · Diktieren · " + statusTitle)
        setAccessibilityHelp(detail)
        setAccessibilityCustomActions(state == .attention ? [NSAccessibilityCustomAction(
            name: "Details im Diktierfenster öffnen", handler: { [weak self] in self?.onDetails?(); return true })] : [])
        drawFrame(now: CACurrentMediaTime(), reducedMotion: reduced)
        refreshClock()
        if changed, visible {
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }

    func updateRecording(rms: Double) {
        guard state == .recording else { return }
        // Logarithmic amplitude, bounded and noise-gated. Silence never invents a voice.
        inputLevel = rms.isFinite && rms > 0.002 ? min(1, max(0, (20 * log10(rms) + 54) / 42)) : 0
        if reduced { drawFrame(now: CACurrentMediaTime(), reducedMotion: true) }
    }

    func show() {
        let opening = !visible
        visible = true
        accessibilityChanged()
        if opening { SaywingCapsuleStyle.materialize(layer, reduced: reduced) }
    }

    func stopAnimating() {
        visible = false
        clock?.invalidate()
        clock = nil
        layer?.removeAllAnimations()
        lastTick = nil
        inputLevel = 0
        smoothedLevel = 0
    }

    @objc private func accessibilityChanged() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        effect.isHidden = false
        tint.backgroundColor = ReadingPalette.void.withAlphaComponent(opaque ? 1 : 0.94).cgColor
        effect.layer?.borderWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 1.5 : 0.75
        effect.layer?.borderColor = ReadingPalette.mint.withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.9 : 0.16).cgColor
        CATransaction.commit()
        if reduced { layer?.removeAllAnimations() }
        drawFrame(now: CACurrentMediaTime(), reducedMotion: reduced)
        refreshClock()
    }

    private func refreshClock() {
        guard visible, !reduced, state == .recording || state == .processing else {
            clock?.invalidate()
            clock = nil
            lastTick = nil
            return
        }
        guard clock == nil else { return }
        let link = displayLink(target: DictationDisplayClockProxy(view: self),
                               selector: #selector(DictationDisplayClockProxy.fire))
        link.add(to: .main, forMode: .common)
        clock = link
    }

    func drawFrame(now: TimeInterval, reducedMotion: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let dt = min(1.0 / 20, max(0, now - (lastTick ?? now - 1.0 / 60)))
        lastTick = now
        smoothedLevel = SaywingCapsuleStyle.smooth(smoothedLevel, toward: inputLevel, dt: dt)
        for index in bars.indices {
            let height = state == .recording
                ? SaywingCapsuleStyle.barHeight(index: index, level: smoothedLevel, reduced: reducedMotion) : 2
            barHeights[index] = height
            let width = SaywingCapsuleStyle.barWidth
            let pitch = width + SaywingCapsuleStyle.barGap
            let start = (body.bounds.width - (CGFloat(bars.count) * pitch - SaywingCapsuleStyle.barGap)) / 2
            bars[index].path = CGPath(roundedRect: CGRect(x: start + CGFloat(index) * pitch,
                y: 14 - height / 2, width: width, height: height), cornerWidth: width / 2, cornerHeight: width / 2, transform: nil)
            SaywingCapsuleStyle.shadeVoice(bars[index], height: height,
                contrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            let waiting = state == .processing && !reducedMotion
            bars[index].opacity = waiting ? SaywingCapsuleStyle.waitingOpacity(index: index, now: now, reduced: reducedMotion) : 1
            bars[index].isHidden = ![.recording, .processing].contains(state)
        }
    }

    @objc private func finish() { if state == .recording { onFinish?() } }
    @objc private func dismiss() { onDismiss?() }
    override func mouseUp(with event: NSEvent) {
        if state == .attention { onDetails?() }
    }
}

@MainActor
private final class DictationDisplayClockProxy: NSObject {
    private weak var view: DictationCapsuleView?
    init(view: DictationCapsuleView) { self.view = view }
    @objc func fire(_ link: CADisplayLink) {
        view?.drawFrame(now: CACurrentMediaTime(), reducedMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

/// Small glyphs with generous, non-overlapping hit areas outside the visual pill.
@MainActor
final class DictationMiniButton: NSButton {
    var isCancel = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .exterior
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func highlight(_ flag: Bool) { super.highlight(flag); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if !isCancel || hovered || isHighlighted {
            let opacity = isCancel ? (isHighlighted ? 0.18 : 0.09) : (isHighlighted ? 0.26 : hovered ? 0.19 : 0.10)
            ReadingPalette.paper.withAlphaComponent(opacity).setFill()
            let face = NSBezierPath(ovalIn: CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22))
            face.fill()
            if !isCancel {
                ReadingPalette.mintLight.withAlphaComponent(contrast ? 0.75 : 0.18).setStroke()
                face.lineWidth = 1
                face.stroke()
            }
        }
        if isHighlighted && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.scale(by: 0.92)
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()
        }
        ReadingPalette.paper.withAlphaComponent(isCancel && !hovered && !contrast ? 0.75 : 1).set()
        if isCancel {
            let path = NSBezierPath()
            path.lineWidth = 1.4
            path.lineCapStyle = .round
            path.move(to: CGPoint(x: center.x - 3, y: center.y - 3))
            path.line(to: CGPoint(x: center.x + 3, y: center.y + 3))
            path.move(to: CGPoint(x: center.x - 3, y: center.y + 3))
            path.line(to: CGPoint(x: center.x + 3, y: center.y - 3))
            path.stroke()
        } else {
            NSBezierPath(roundedRect: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7),
                xRadius: 1.5, yRadius: 1.5).fill()
        }
    }
    override var focusRingMaskBounds: NSRect {
        CGRect(x: bounds.midX - 11, y: bounds.midY - 11, width: 22, height: 22)
    }
    override func drawFocusRingMask() { NSBezierPath(ovalIn: focusRingMaskBounds).fill() }
}
