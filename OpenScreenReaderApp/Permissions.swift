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
        case .accessibility: String(localized: "Enables Fn dictation and pastes text into the app you were using.")
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

/// Only navigation is persisted, never permission grants or test results. The
/// checkpoint is written before leaving for System Settings: macOS may quit us.
enum SetupStep: String, CaseIterable {
    case screenRecording, inputMonitoring, readingTest, microphone, accessibility, dictationTest
    case readingModel, dictationModel, readingShortcuts, dictationShortcuts

    var permission: SaywingPermission? {
        switch self {
        case .screenRecording: .screenRecording
        case .inputMonitoring: .inputMonitoring
        case .microphone: .microphone
        case .accessibility: .accessibility
        default: nil
        }
    }
    var isDictation: Bool { [.microphone, .accessibility, .dictationModel, .dictationShortcuts, .dictationTest].contains(self) }
    var stage: Int {
        switch self {
        case .screenRecording, .inputMonitoring, .microphone, .accessibility: 0
        case .readingModel, .dictationModel: 1
        case .readingShortcuts, .dictationShortcuts: 2
        case .readingTest, .dictationTest: 3
        }
    }
    var next: Self {
        switch self {
        case .screenRecording: .inputMonitoring
        case .inputMonitoring: .readingModel
        case .readingModel: .readingShortcuts
        case .readingShortcuts: .readingTest
        case .readingTest: .microphone
        case .microphone: .accessibility
        case .accessibility: .dictationModel
        case .dictationModel: .dictationShortcuts
        case .dictationShortcuts, .dictationTest: .dictationTest
        }
    }
}

@MainActor
final class SetupProgress: ObservableObject {
    static let preferenceKey = "setupProgress.v1"
    @Published private(set) var step: SetupStep
    @Published private(set) var waitingFor: SaywingPermission?
    @Published private(set) var offersRestartHelp = false
    private let preferences: UserDefaults
    private var resumeOnLaunch: Bool

    init(preferences: UserDefaults) {
        self.preferences = preferences
        let saved = preferences.dictionary(forKey: Self.preferenceKey)
        step = (saved?["step"] as? String).flatMap(SetupStep.init(rawValue:)) ?? .screenRecording
        waitingFor = (saved?["waitingFor"] as? String).flatMap(SaywingPermission.init(rawValue:))
        resumeOnLaunch = saved?["resume"] as? Bool ?? false
        offersRestartHelp = waitingFor != nil && waitingFor != .microphone
    }

    var shouldOpenOnLaunch: Bool {
        resumeOnLaunch || !preferences.bool(forKey: "setupDismissed.v1")
    }

    func begin(granted: Set<SaywingPermission>) {
        resumeOnLaunch = true
        refresh(granted: granted)
    }

    func prepareForPermission(_ permission: SaywingPermission) {
        step = SetupStep(rawValue: permission.rawValue) ?? step
        waitingFor = permission
        offersRestartHelp = permission != .microphone
        resumeOnLaunch = true
        save()
    }

    func refresh(granted: Set<SaywingPermission>) {
        if let waitingFor, granted.contains(waitingFor) { self.waitingFor = nil }
        // Recheck required prerequisites, including access revoked while away.
        if step.stage == 0 || step.stage == 3 {
          if step.isDictation {
            if !granted.contains(.microphone) { step = .microphone }
            else if step == .dictationTest && !granted.contains(.accessibility) { step = .accessibility }
          } else if !granted.contains(.screenRecording) { step = .screenRecording }
        }
        while let permission = step.permission, granted.contains(permission) { step = step.next }
        save()
    }

    func showReading(granted: Set<SaywingPermission>) {
        step = .screenRecording
        waitingFor = nil
        offersRestartHelp = false
        begin(granted: granted)
    }

    func continueToDictation(granted: Set<SaywingPermission>) {
        step = .microphone
        waitingFor = nil
        offersRestartHelp = false
        begin(granted: granted)
    }

    func skipOptionalPermission() {
        guard step == .inputMonitoring else { return }
        step = .readingModel
        waitingFor = nil
        save()
    }

    func advance(granted: Set<SaywingPermission>) {
        guard step.stage == 1 || step.stage == 2 else { return }
        step = step.next
        begin(granted: granted)
    }

    func back() {
        switch step.stage {
        case 3: step = step.isDictation ? .dictationShortcuts : .readingShortcuts
        case 2: step = step.isDictation ? .dictationModel : .readingModel
        case 1: step = step.isDictation ? .microphone : .screenRecording
        default: return
        }
        waitingFor = nil
        save()
    }

    /// Visiting earlier stages is explicit; permission refresh never skips
    /// model/shortcut choices or starts a test on the user's behalf.
    func visit(stage: Int) {
        let stages: [SetupStep] = step.isDictation
            ? [.microphone, .dictationModel, .dictationShortcuts, .dictationTest]
            : [.screenRecording, .readingModel, .readingShortcuts, .readingTest]
        guard stages.indices.contains(stage) else { return }
        step = stages[stage]
        waitingFor = nil
        resumeOnLaunch = true
        save()
    }

    func prepareForRestart() {
        resumeOnLaunch = true
        save()
    }

    func deferSetup() {
        resumeOnLaunch = false
        preferences.set(true, forKey: "setupDismissed.v1")
        save()
    }

    func finish() {
        resumeOnLaunch = false
        step = .screenRecording
        waitingFor = nil
        offersRestartHelp = false
        preferences.set(true, forKey: "setupDismissed.v1")
        preferences.removeObject(forKey: Self.preferenceKey)
    }

    private func save() {
        var checkpoint: [String: Any] = ["step": step.rawValue, "resume": resumeOnLaunch]
        if let waitingFor { checkpoint["waitingFor"] = waitingFor.rawValue }
        preferences.set(checkpoint, forKey: Self.preferenceKey)
        // This handoff can be followed immediately by macOS terminating us.
        preferences.synchronize()
    }
}

/// A bounded local helper waits for this exact process to exit before opening
/// this bundle again, avoiding duplicate global shortcuts during relaunch.
enum SetupRelauncher {
    static let waitScript = """
        attempts=0
        while /bin/kill -0 "$1" 2>/dev/null; do
            [ "$attempts" -lt 300 ] || exit 1
            attempts=$((attempts + 1))
            /bin/sleep 0.1
        done
        exec /usr/bin/open -n "$2"
        """

    static func launchAfterExit(bundleURL: URL = Bundle.main.bundleURL,
                                processID: Int32 = ProcessInfo.processInfo.processIdentifier) throws -> Process {
        guard bundleURL.pathExtension == "app",
              let bundle = Bundle(url: bundleURL), let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CocoaError(.executableNotLoadable)
        }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Paths are positional arguments, never interpolated into shell code.
        helper.arguments = ["-c", waitScript, "saywing-relaunch", String(processID), bundleURL.path]
        helper.standardInput = FileHandle.nullDevice
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        try helper.run()
        return helper
    }
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
    var beforeRequest: (() -> Void)? = nil

    var body: some View {
        let granted = status.isGranted(permission)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .imageScale(.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title).font(.body.weight(.medium))
                Text(permission.purpose).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Open System Settings") {
                        beforeRequest?()
                        permission.openSettings()
                    }
                        .buttonStyle(.link).font(.callout)
                }
            }
            Spacer(minLength: 8)
            if granted {
                Text("Allowed").font(.callout).foregroundStyle(.secondary)
            } else {
                Button(permission.isRequired ? "Allow…" : "Allow (Optional)…") {
                    beforeRequest?()
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
