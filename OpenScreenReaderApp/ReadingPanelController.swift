import AppKit
import SwiftUI

// Status only: never pass recognized text, screenshots or audio into the panel.
enum ReadingPanelState: Equatable {
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
        case .failed: "Details findest du im App-Menü."
        }
    }

    var symbol: String {
        switch self {
        case .recognizing: "text.viewfinder"
        case .preparing: "speaker.wave.1"
        case .speaking: "speaker.wave.2.fill"
        case .finished: "checkmark"
        case .stopped: "stop.fill"
        case .noText, .failed: "exclamationmark.circle"
        }
    }

    var isActive: Bool { self == .recognizing || self == .preparing || self == .speaking }
    var dismissesAutomatically: Bool { self == .finished || self == .stopped }
}

@MainActor
protocol ReadingStatusPresenting: AnyObject {
    func show(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?)
    func hide()
}

@MainActor
final class ReadingPanelController: NSObject, ReadingStatusPresenting {
    private(set) var state: ReadingPanelState?
    private(set) var panel: ReadingStatusPanel?
    private var displayID: UInt32?
    private var dismissalTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private let terminalDuration: Duration

    init(terminalDuration: Duration = .milliseconds(1400)) {
        self.terminalDuration = terminalDuration
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(displayLayoutChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    isolated deinit {
        dismissalTask?.cancel()
        panel?.close()
        NotificationCenter.default.removeObserver(self)
    }

    func show(_ state: ReadingPanelState, displayID: UInt32, onStop: (() -> Void)?) {
        dismissalTask?.cancel()
        dismissalTask = nil
        generation &+= 1
        let presentation = generation
        guard let screen = Self.screen(for: displayID) else { hide(); return }
        self.state = state
        self.displayID = displayID
        let panel = panel ?? ReadingStatusPanel()
        self.panel = panel
        panel.contentView = FirstClickHostingView(rootView: ReadingPanelView(state: state) { [weak self] in
            // An old button or delayed event must not stop a newer operation.
            guard let self, self.generation == presentation else { return }
            if state.isActive { onStop?() }
            else { self.hide() }
        })
        panel.setFrame(Self.frame(in: screen.visibleFrame), display: true)
        panel.orderFrontRegardless()
        // Never activate the app or make this panel key. The user's document keeps focus.
        if state.dismissesAutomatically {
            let duration = terminalDuration
            dismissalTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: duration) } catch { return }
                guard let self, self.generation == presentation else { return }
                self.hide()
            }
        }
    }

    func hide() {
        generation &+= 1
        dismissalTask?.cancel()
        dismissalTask = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        state = nil
        displayID = nil
    }

    static func frame(in visibleFrame: CGRect) -> CGRect {
        let width = min(320, visibleFrame.width)
        let height = min(64, visibleFrame.height)
        let bottomInset = min(20, max(0, visibleFrame.height - height))
        return CGRect(x: visibleFrame.midX - width / 2, y: visibleFrame.minY + bottomInset,
                      width: width, height: height)
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
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "Vorlesestatus"
        setAccessibilityIdentifier("readingStatusPanel")
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
    }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ReadingPanelView: View {
    let state: ReadingPanelState
    let action: () -> Void
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Approved brand tokens: opaque surfaces also respect Reduce Transparency.
    private let ink = Color(red: 11 / 255, green: 23 / 255, blue: 36 / 255)
    private let paper = Color(red: 247 / 255, green: 244 / 255, blue: 237 / 255)
    private let mint = Color(red: 85 / 255, green: 224 / 255, blue: 190 / 255)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(mint)
                .symbolEffect(.pulse, isActive: state == .speaking && !reduceMotion)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityIdentifier("readingStatusTitle")
                Text(state.detail)
                    .font(.system(size: 11))
            }
            .foregroundStyle(paper)
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            Button(action: action) {
                Image(systemName: state.isActive ? "stop.fill" : "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(paper)
                    .frame(width: 44, height: 44)
                    .background(paper.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isActive ? "Vorlesen stoppen" : "Status schließen")
            .accessibilityIdentifier("readingStatusAction")
            .help(state.isActive ? "Gesamten Vorgang stoppen (Esc)" : "Status schließen")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(paper.opacity(contrast == .increased ? 0.8 : 0.18), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readingStatusContent")
    }
}
