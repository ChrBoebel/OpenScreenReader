import AppKit
import SwiftUI
import Testing
@testable import OpenScreenReader

@Suite("Resumable setup", .serialized)
@MainActor
struct ResumableSetupTests {
    @Test func modelsAndShortcutsRemainDistinctSavedStepsBeforeTesting() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = SetupProgress(preferences: defaults)
        setup.continueToDictation(granted: Set(SaywingPermission.allCases))
        #expect(setup.step == .dictationModel)
        setup.advance(granted: Set(SaywingPermission.allCases))
        #expect(setup.step == .dictationShortcuts)
        let restored = SetupProgress(preferences: defaults)
        restored.begin(granted: Set(SaywingPermission.allCases))
        #expect(restored.step == .dictationShortcuts)
        restored.advance(granted: Set(SaywingPermission.allCases))
        #expect(restored.step == .dictationTest)
        restored.back()
        #expect(restored.step == .dictationShortcuts)
    }

    private func preferences() -> (UserDefaults, String) {
        let suite = "com.christopherbobel.OpenScreenReader.setup-tests.\(UUID())"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func permissionHandoffSurvivesSystemInitiatedRestart() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        // Reopening setup after an earlier dismissal must also be resumable.
        defaults.set(true, forKey: "setupDismissed.v1")
        let setup = SetupProgress(preferences: defaults)
        #expect(!setup.shouldOpenOnLaunch)
        setup.begin(granted: [])
        setup.prepareForPermission(.screenRecording)
        let relaunched = SetupProgress(preferences: UserDefaults(suiteName: suite)!)
        #expect(relaunched.shouldOpenOnLaunch)
        #expect(relaunched.step == .screenRecording)
        #expect(relaunched.waitingFor == .screenRecording)
        relaunched.refresh(granted: [.screenRecording])
        #expect(relaunched.step == .inputMonitoring)
        #expect(relaunched.waitingFor == nil)
    }

    @Test func restartSkipsGrantedPermissionsButKeepsModelAndShortcutChoices() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = SetupProgress(preferences: defaults)
        setup.begin(granted: [])
        setup.prepareForPermission(.screenRecording)
        let restored = SetupProgress(preferences: defaults)
        restored.refresh(granted: Set(SaywingPermission.allCases))
        #expect(restored.step == .readingModel)
        restored.continueToDictation(granted: Set(SaywingPermission.allCases))
        #expect(restored.step == .dictationModel)
    }

    @Test func dictationResumesAtItsMissingPermissionAndPreservesSkippedReading() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = SetupProgress(preferences: defaults)
        setup.continueToDictation(granted: [.microphone])
        setup.prepareForPermission(.accessibility)
        let restored = SetupProgress(preferences: defaults)
        restored.refresh(granted: [.microphone])
        #expect(restored.step == .accessibility)
        restored.refresh(granted: [.microphone, .accessibility])
        #expect(restored.step == .dictationModel)
    }

    @Test func optionalInputMonitoringDoesNotBlockReadingAndRevocationIsRechecked() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = SetupProgress(preferences: defaults)
        setup.begin(granted: [.screenRecording])
        setup.skipOptionalPermission()
        #expect(setup.step == .readingModel)
        setup.advance(granted: [.screenRecording])
        setup.advance(granted: [.screenRecording])
        #expect(setup.step == .readingTest)
        let restored = SetupProgress(preferences: defaults)
        restored.refresh(granted: [.screenRecording])
        #expect(restored.step == .readingTest)
        restored.refresh(granted: [])
        #expect(restored.step == .screenRecording)
    }

    @Test func laterKeepsTheStepWithoutForcingSetupOnEveryLaunch() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = SetupProgress(preferences: defaults)
        setup.continueToDictation(granted: [.microphone])
        setup.deferSetup()
        let restored = SetupProgress(preferences: defaults)
        #expect(!restored.shouldOpenOnLaunch)
        #expect(restored.step == .accessibility)
        restored.begin(granted: [.microphone])
        #expect(restored.shouldOpenOnLaunch)
        #expect(restored.step == .accessibility)
        restored.finish()
        #expect(!SetupProgress(preferences: defaults).shouldOpenOnLaunch)
        #expect(defaults.dictionary(forKey: SetupProgress.preferenceKey) == nil)
    }

    @Test func deniedPermissionAndRestartDoNotAdvanceOrLoopAutomatically() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let setup = SetupProgress(preferences: defaults)
        setup.prepareForPermission(.screenRecording)
        setup.refresh(granted: [])
        #expect(setup.step == .screenRecording)
        setup.prepareForRestart()
        let restored = SetupProgress(preferences: defaults)
        restored.refresh(granted: [])
        #expect(restored.shouldOpenOnLaunch)
        #expect(restored.step == .screenRecording)
        #expect(restored.waitingFor == .screenRecording)
    }

    @Test func restartSavesBeforeLaunchingAndNeverQuitsIfLaunchFails() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: RegisteredHotkeyManagerFake(),
                             preferences: defaults, setupPermissions: PermissionStatus { _ in false })
        model.setupProgress.continueToDictation(granted: [.microphone])
        var terminated = false
        model.restartSetup(launch: {
            let restored = SetupProgress(preferences: defaults)
            #expect(restored.shouldOpenOnLaunch)
            #expect(restored.step == .accessibility)
            throw CocoaError(.executableNotLoadable)
        }, terminate: { terminated = true })
        #expect(!terminated)
        #expect(!model.isRestartingSetup)
        #expect(model.setupRestartError != nil)
        model.restartSetup(launch: { nil }, terminate: { terminated = true })
        #expect(terminated)
        #expect(model.setupRestartError == nil)
    }

    @Test func restartIsBlockedWhileRecordingAShortcut() {
        let (defaults, suite) = preferences()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: RegisteredHotkeyManagerFake(),
                             preferences: defaults, setupPermissions: PermissionStatus { _ in false })
        model.setRecordingShortcut(true)
        var launched = false
        model.restartSetup(launch: { launched = true; return nil }, terminate: {})
        #expect(!launched)
        model.setRecordingShortcut(false)
    }

    /// Opt-in layout evidence, with simulated grant states clearly separated
    /// from the real permission/relaunch UI test.
    @Test func exportSetupStates() throws {
        guard let path = ProcessInfo.processInfo.environment["OSR_SETUP_PREVIEW_DIR"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let states: [(SetupStep, Set<SaywingPermission>)] = [
            (.screenRecording, []), (.inputMonitoring, [.screenRecording]),
            (.readingModel, [.screenRecording, .inputMonitoring]),
            (.readingShortcuts, [.screenRecording, .inputMonitoring]),
            (.readingTest, [.screenRecording, .inputMonitoring]), (.microphone, []),
            (.dictationModel, [.microphone, .accessibility]),
            (.dictationShortcuts, [.microphone, .accessibility]),
            (.accessibility, [.microphone]), (.dictationTest, [.microphone, .accessibility])
        ]
        for (step, granted) in states {
            let (defaults, suite) = preferences()
            defer { defaults.removePersistentDomain(forName: suite) }
            let resources = try DictationModelFixture.resources(bundling: [.whisperTurbo])
            defer { try? FileManager.default.removeItem(at: resources) }
            let dictation = DictationController(resources: resources, preferences: defaults, registerHotkey: false)
            defer { dictation.shutdown() }
            let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: RegisteredHotkeyManagerFake(),
                                 preferences: defaults, dictation: dictation, setupPermissions: PermissionStatus { granted.contains($0) })
            if step.isDictation { model.setupProgress.continueToDictation(granted: granted) }
            else { model.setupProgress.begin(granted: granted) }
            if step.stage > 0 { model.setupProgress.visit(stage: step.stage) }
            if let permission = step.permission { model.setupProgress.prepareForPermission(permission) }
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let host = NSHostingView(rootView: SetupView(model: model)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, suffix == "light" ? .light : .dark))
                host.appearance = NSAppearance(named: appearance)
                host.frame.size = host.fittingSize
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try #require(rep.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("\(step.rawValue)-\(suffix).png"))
                window.contentView = nil
            }
        }
    }
}

@Suite("App status")
struct AppStatusTests {
    @Test
    func appBundleUsesApprovedProductNameAndIcon() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String == "Saywing")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == "Saywing")
        #expect(Bundle.main.bundleIdentifier == "com.christopherbobel.OpenScreenReader")
        #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon")
    }

    @Test @MainActor
    func menuBarArtworkLoadsAsSystemColoredTemplate() throws {
        let image = try #require(NSImage(named: "SaywingMenuBar"))
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 22, height: 22))
        #expect(image.tiffRepresentation != nil)
    }
    @Test
    func userFacingTitlesCoverEveryPipelineState() {
        #expect(AppStatus.allCases.map(\.title) == [
            "Ready",
            "Selecting",
            "Capturing",
            "Recognizing",
            "Preparing voice",
            "Speaking",
            "Waiting for next text",
            "Stopped",
            "Error",
        ])
    }

    @Test
    @MainActor
    func appModelStartsReadyWithAnIdleCoordinator() async {
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: RegisteredHotkeyManagerFake())
        let snapshot = await model.pipelineCoordinator.snapshot()

        #expect(model.status == .ready)
        #expect(snapshot.activeContext == nil)
        #expect(snapshot.phase == .idle)
    }

    @Test
    func permissionsOpenTheirOwnPrivacyPane() {
        #expect(SaywingPermission.allCases.map(\.settingsURL.absoluteString) == [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
        #expect(SaywingPermission.reading == [.screenRecording, .inputMonitoring])
        #expect(SaywingPermission.dictation == [.microphone, .accessibility])
        #expect(SaywingPermission.allCases.filter { !$0.isRequired } == [.inputMonitoring])
    }

    @Test @MainActor
    func readingTestNeedsOnlyScreenRecording() {
        var granted: Set<SaywingPermission> = [.screenRecording]
        let status = PermissionStatus { granted.contains($0) }
        #expect(status.canTestReading)
        #expect(!status.canTestDictation)
        granted = [.inputMonitoring, .microphone]
        status.refresh()
        #expect(!status.canTestReading)
        #expect(status.canTestDictation)
        #expect(status.isGranted(.inputMonitoring))
    }

    @Test
    func germanLocalizationShipsInTheAppBundle() throws {
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        func de(_ key: String) -> String { german.localizedString(forKey: key, value: "MISSING", table: nil) }
        #expect(de("Read Screen Region…") == "Bildschirmbereich vorlesen…")
        #expect(de("Ready") == "Bereit")
        #expect(de("Stop reading") == "Vorlesen stoppen")
        #expect(de("Ready to dictate") == "Bereit zum Diktieren")
        #expect(String.localizedStringWithFormat(de("%lld texts waiting"), 1) == "1 Text wartet")
        #expect(String.localizedStringWithFormat(de("%lld texts waiting"), 3) == "3 Texte warten")
        #expect(german.localizedString(forKey: "NSMicrophoneUsageDescription", value: nil, table: "InfoPlist").hasPrefix("Saywing nimmt"))
        // Tests run with the English source strings.
        #expect(AppStatus.ready.title == "Ready")
    }

    /// Every shipped key has a German entry. Reading sources from the repository is
    /// left to scripts/check-localization.py so the test host never asks for folder access.
    @Test
    func germanTableCoversTheWholeCatalog() throws {
        let path = try #require(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "de"))
        let table = try #require(NSDictionary(contentsOfFile: path) as? [String: String])
        #expect(table.count > 280)
        #expect(table.values.allSatisfy { !$0.isEmpty })
    }

    @Test
    func appBundleIsConfiguredAsMenuBarOnly() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true)
    }
}

@MainActor
private final class RegisteredHotkeyManagerFake: HotkeyManaging {
    var onPress: (() -> Void)?

    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration {
        .registered
    }

    func unregister() {}
}
