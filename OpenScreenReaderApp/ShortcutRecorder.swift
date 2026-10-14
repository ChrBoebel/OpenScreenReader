import AppKit
import SwiftUI

/// The familiar macOS shortcut field: click, press the new combination, done.
/// Escape cancels. Combinations a global shortcut cannot use are explained, never saved.
struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: ShortcutConfiguration
    let identifier: String
    /// What the shortcut does; two recorders must not both be called "Shortcut".
    var label = String(localized: "Shortcut")
    var onRecordingChange: (Bool) -> Void
    var onRecord: (ShortcutConfiguration) -> Void
    var onRejected: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.setAccessibilityIdentifier(identifier)
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ field: ShortcutRecorderField, context: Context) {
        field.shortcut = shortcut
        field.isEnabled = context.environment.isEnabled
        field.setAccessibilityLabel(label)
        field.onRecordingChange = onRecordingChange
        field.onRecord = onRecord
        field.onRejected = onRejected
    }
}

@MainActor
final class ShortcutRecorderField: NSView {
    var shortcut = ShortcutConfiguration.default { didSet { refresh() } }
    var isEnabled = true { didSet { if !isEnabled { stopRecording() }; refresh() } }
    var onRecordingChange: ((Bool) -> Void)?
    var onRecord: ((ShortcutConfiguration) -> Void)?
    var onRejected: (() -> Void)?
    private(set) var isRecording = false
    private var liveModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled }
    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Shortcut"))
        refresh()
    }
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isRecording ? stopRecording() : startRecording()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        startRecording()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            // Space or Return starts recording from the keyboard, like a button.
            if event.keyCode == 49 || event.keyCode == 36 { startRecording() } else { super.keyDown(with: event) }
            return
        }
        record(event)
    }

    /// Command combinations arrive here before menus could act on them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        liveModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stopRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); return } // Escape cancels.
        let character = event.characters(byApplyingModifiers: []) ?? ""
        guard let candidate = ShortcutConfiguration.recorded(character: character, flags: event.modifierFlags),
              candidate.isValid else {
            NSSound.beep()
            onRejected?()
            return
        }
        stopRecording()
        onRecord?(candidate)
    }

    private func startRecording() {
        guard !isRecording else { return }
        window?.makeFirstResponder(self)
        isRecording = true
        liveModifiers = []
        onRecordingChange?(true)
        refresh()
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
        onRecordingChange?(false)
        refresh()
    }

    private var title: String {
        guard isRecording else { return shortcut.displayName }
        let pending = ShortcutConfiguration.recorded(character: "a", flags: liveModifiers)?.displayName.dropLast() ?? ""
        return pending.isEmpty ? String(localized: "Type Shortcut") : String(pending) + "…"
    }

    private func refresh() {
        setAccessibilityValue(isRecording ? String(localized: "Recording. Type the new shortcut or press Escape.") : shortcut.displayName)
        setAccessibilityHelp(String(localized: "Click, then type a new shortcut."))
        NSAccessibility.post(element: self, notification: .valueChanged)
        needsDisplay = true
    }
    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor).setFill()
        shape.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = isRecording ? 1.5 : 1
        shape.stroke()
        let color: NSColor = !isEnabled ? .disabledControlTextColor : isRecording ? .secondaryLabelColor : .labelColor
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: isRecording ? .regular : .medium),
            .foregroundColor: color,
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}
