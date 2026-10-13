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

    var title: String {
        switch self {
        case .screenRecording: String(localized: "Screen Recording")
        case .inputMonitoring: String(localized: "Input Monitoring")
        case .microphone: String(localized: "Microphone")
        case .accessibility: String(localized: "Accessibility")
        }
    }

    var purpose: String {
        switch self {
        case .screenRecording: String(localized: "Captures only the region you mark, for local text recognition.")
        case .inputMonitoring: String(localized: "Lets Escape stop reading while another app is active. Only Escape is checked.")
        case .microphone: String(localized: "Records only while you dictate.")
        case .accessibility: String(localized: "Pastes dictated text into the app you were using.")
        }
    }

    /// Reading works without Input Monitoring; Escape then only stops while Saywing has focus.
    var isRequired: Bool { self != .inputMonitoring }

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

    func refresh() { granted = Set(SaywingPermission.allCases.filter(read)) }
    func isGranted(_ permission: SaywingPermission) -> Bool { granted.contains(permission) }

    /// The reading test needs only Screen Recording.
    var canTestReading: Bool { isGranted(.screenRecording) }
    var canTestDictation: Bool { isGranted(.microphone) }
}

struct PermissionRow: View {
    let permission: SaywingPermission
    @ObservedObject var status: PermissionStatus

    var body: some View {
        let granted = status.isGranted(permission)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : permission.isRequired ? "exclamationmark.circle" : "circle.dashed")
                .foregroundStyle(granted ? Color.green : permission.isRequired ? Color.orange : Color.secondary)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.body.weight(.medium))
                Text(permission.purpose).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Open System Settings") { permission.openSettings() }
                        .buttonStyle(.link).font(.callout)
                }
            }
            Spacer(minLength: 8)
            if granted {
                Text("Allowed").font(.callout).foregroundStyle(.secondary)
            } else {
                Button(permission.isRequired ? "Allow…" : "Allow (Optional)…") {
                    permission.request { status.refresh() }
                }
                .accessibilityIdentifier("allow-\(permission.rawValue)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(permission.title)
        .accessibilityValue(granted ? Text("Allowed") : Text("Not allowed"))
    }
}
