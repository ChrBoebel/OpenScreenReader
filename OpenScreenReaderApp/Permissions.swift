import AppKit
import AVFoundation
import SwiftUI

/// The four macOS privacy grants Saywing can use. Each is requested only on an
/// explicit click; status is read with preflight APIs that never prompt.
enum SaywingPermission: String, CaseIterable, Identifiable {
    case screenRecording, inputMonitoring, microphone, accessibility

    var id: String { rawValue }

    static let reading: [Self] = [.screenRecording, .inputMonitoring]
    static let dictation: [Self] = [.microphone, .accessibility]

    var purpose: String {
        switch self {
        case .screenRecording: String(localized: "Captures only the region you mark, for local text recognition.")
        case .inputMonitoring: String(localized: "Lets Escape stop reading while another app is active. Only Escape is checked.")
        case .microphone: String(localized: "Records only while you dictate.")
        case .accessibility: String(localized: "Lets Fn start dictation and pastes the text into the app you were using.")
        }
    }

    /// Setup speaks about what the grant does; the system name follows in small print
    /// so it can still be found in System Settings.
    var setupTitle: String {
        switch self {
        case .screenRecording: String(localized: "Read the text you mark")
        case .inputMonitoring: String(localized: "Stop anytime with Escape")
        case .microphone: String(localized: "Hear you only while you dictate")
        case .accessibility: String(localized: "Type where you are writing")
        }
    }

    var setupMessage: String {
        switch self {
        case .screenRecording: String(localized: "Saywing captures only the region you drag and recognizes its text on this Mac. Nothing is saved.")
        case .inputMonitoring: String(localized: "Escape then stops reading while you work in another app. Saywing checks only the Escape key.")
        case .microphone: String(localized: "Saywing records only while you hold Fn or dictate hands-free. Audio never leaves this Mac.")
        case .accessibility: String(localized: "Fn starts dictation, and the text lands in the app you were using.")
        }
    }

    var setupSymbol: String {
        switch self {
        case .screenRecording: "rectangle.dashed"
        case .inputMonitoring: "escape" // Setup shows an "esc" key cap instead.
        case .microphone: "mic"
        case .accessibility: "character.cursor.ibeam"
        }
    }

    /// The pane's name in System Settings › Privacy & Security.
    var systemName: String {
        switch self {
        case .screenRecording:
            if #available(macOS 15, *) { String(localized: "Screen & System Audio Recording") } else { String(localized: "Screen Recording") }
        case .inputMonitoring: String(localized: "Input Monitoring")
        case .microphone: String(localized: "Microphone")
        case .accessibility: String(localized: "Accessibility")
        }
    }

    var activity: String {
        Self.reading.contains(self) ? String(localized: "Read Aloud") : String(localized: "Dictate")
    }

    var settingsURL: URL {
        let anchor = switch self {
        case .screenRecording: "Privacy_ScreenCapture"
        case .inputMonitoring: "Privacy_ListenEvent"
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }

    @MainActor var isGranted: Bool {
        switch self {
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .inputMonitoring: CGPreflightListenEventAccess()
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        }
    }

    /// Shows the system prompt where macOS still offers one; otherwise opens the matching pane.
    @MainActor func request(completion: @escaping @MainActor () -> Void) {
        switch self {
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings() }
        case .inputMonitoring:
            if !CGRequestListenEventAccess() { openSettings() }
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    DispatchQueue.main.async { completion() }
                }
                return
            case .denied, .restricted: openSettings()
            default: break
            }
        case .accessibility:
            if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) { openSettings() }
        }
        completion()
    }

    @MainActor func openSettings() { NSWorkspace.shared.open(settingsURL) }
}

/// Grant state shared by Setup and Settings. Refreshes when the user returns
/// from System Settings; it never requests anything by itself.
@MainActor
final class PermissionStatus: ObservableObject {
    @Published private(set) var granted: Set<SaywingPermission> = []
    private var observer: NSObjectProtocol?

    init(read: @escaping @MainActor (SaywingPermission) -> Bool = { $0.isGranted }) {
        self.read = read
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
    }
    isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    private let read: @MainActor (SaywingPermission) -> Bool

    func refresh() {
        let current = Set(SaywingPermission.allCases.filter(read))
        // Setup polls while waiting; publish only real changes.
        if current != granted { granted = current }
    }
    func isGranted(_ permission: SaywingPermission) -> Bool { granted.contains(permission) }

    /// Capture also needs Input Monitoring: without global Escape it refuses to start (ADR 0005).
    var canTestReading: Bool { SaywingPermission.reading.allSatisfy(isGranted) }
    var canTestDictation: Bool { isGranted(.microphone) }
}

struct PermissionRow: View {
    let permission: SaywingPermission
    @ObservedObject var status: PermissionStatus

    var body: some View {
        let granted = status.isGranted(permission)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Color.green : Color.orange)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.systemName).font(.body.weight(.medium))
                Text(permission.purpose).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted {
                Text("Allowed").font(.callout).foregroundStyle(.secondary)
            } else {
                // One action: the system prompt where macOS still offers it, otherwise its pane.
                Button("Allow…") {
                    permission.request { status.refresh() }
                }
                .accessibilityIdentifier("allow-\(permission.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(permission.systemName)
        .accessibilityValue(granted ? Text("Allowed") : Text("Not allowed"))
    }
}
