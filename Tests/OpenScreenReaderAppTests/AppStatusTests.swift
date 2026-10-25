import AppKit
import Testing
@testable import OpenScreenReader

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
        let model = AppModel(modelTerms: .acceptedForTesting(), shortcutStore: MemoryShortcutStore(), hotkeyManager: RegisteredHotkeyManagerFake())
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
    }

    /// Capture refuses to start without Input Monitoring (global Escape, ADR 0005),
    /// so the reading test must not be offered with Screen Recording alone.
    @Test @MainActor
    func readingTestNeedsScreenRecordingAndInputMonitoring() {
        var granted: Set<SaywingPermission> = [.screenRecording]
        let status = PermissionStatus { granted.contains($0) }
        #expect(!status.canTestReading)
        #expect(!status.canTestDictation)
        granted = [.screenRecording, .inputMonitoring, .microphone]
        status.refresh()
        #expect(status.canTestReading)
        #expect(status.canTestDictation)
    }

    @Test
    func freshSetupWalksReadingThenOffersDictation() {
        var plan = SetupPlan(dictationAvailable: true)
        #expect(plan.first(granted: []) == .welcome)
        #expect(plan.next(after: .welcome, granted: []) == .permission(.screenRecording))
        #expect(plan.next(after: .permission(.screenRecording), granted: [.screenRecording]) == .permission(.inputMonitoring))
        #expect(plan.next(after: .permission(.inputMonitoring), granted: [.screenRecording, .inputMonitoring]) == .readingModel)
        #expect(plan.next(after: .tryReading, granted: [.screenRecording, .inputMonitoring]) == .dictationOffer)
        #expect(plan.next(after: .dictationOffer, granted: [.screenRecording, .inputMonitoring]) == .done)
        plan.wantsDictation = true
        let reading: Set<SaywingPermission> = [.screenRecording, .inputMonitoring]
        #expect(plan.next(after: .dictationOffer, granted: reading) == .permission(.microphone))
        #expect(plan.next(after: .permission(.microphone), granted: reading.union([.microphone])) == .permission(.accessibility))
        #expect(plan.next(after: .permission(.accessibility), granted: Set(SaywingPermission.allCases)) == .dictationModel)
        #expect(plan.next(after: .tryDictation, granted: Set(SaywingPermission.allCases)) == .done)
        #expect(plan.next(after: .done, granted: []) == .done)
    }

    @Test
    func setupSkipsGrantedStepsAndTestsThatCannotRun() {
        var plan = SetupPlan(dictationAvailable: true)
        // Returning users start where something is still missing, never at the welcome.
        #expect(plan.first(granted: [.inputMonitoring]) == .permission(.screenRecording))
        #expect(plan.first(granted: [.screenRecording, .inputMonitoring]) == .readingModel)
        // "Later" on a required grant also skips the test that would only fail.
        #expect(plan.next(after: .permission(.inputMonitoring), granted: [.inputMonitoring]) == .readingModel)
        plan.wantsDictation = true
        #expect(plan.next(after: .permission(.accessibility), granted: [.accessibility]) == .dictationModel)
        // The dictation test field works with the microphone alone.
        #expect(plan.next(after: .permission(.accessibility), granted: [.microphone]) == .dictationModel)
        // Dictation reached from its own error goes straight to its missing grants.
        #expect(plan.first(granted: [], entry: .dictation) == .permission(.microphone))
        #expect(plan.first(granted: [.microphone, .accessibility], entry: .dictation) == .dictationModel)
        let readingOnly = SetupPlan(dictationAvailable: false)
        #expect(readingOnly.next(after: .tryReading, granted: []) == .done)
        #expect(readingOnly.first(granted: [], entry: .dictation) == .welcome)
    }

    /// Success is shown only after speech actually played, not after a grant or a drag.
    @Test
    func readingTrialConfirmsOnlyHeardSpeech() {
        var trial = ReadingTrial.waiting
        trial = trial.advanced(by: .selecting, foundText: nil)
        #expect(trial == .working)
        trial = trial.advanced(by: .stopped, foundText: nil)
        #expect(trial == .waiting, "Escape during the selection is not a result")
        for status in [AppStatus.selecting, .capturing, .recognizing, .synthesizing] { trial = trial.advanced(by: status, foundText: nil) }
        #expect(trial == .working)
        trial = trial.advanced(by: .ready, foundText: false)
        #expect(trial == .noText)
        trial = trial.advanced(by: .synthesizing, foundText: true).advanced(by: .speaking, foundText: true)
        #expect(trial == .speaking)
        // Adding to the queue keeps speaking; Escape after hearing it is a success.
        #expect(trial.advanced(by: .selecting, foundText: true) == .speaking)
        #expect(trial.advanced(by: .stopped, foundText: true) == .heard)
        #expect(trial.advanced(by: .ready, foundText: true) == .heard)
        #expect(ReadingTrial.working.advanced(by: .error, foundText: nil) == .failed)
        #expect(ReadingTrial.waiting.advanced(by: .ready, foundText: nil) == .waiting)
    }

    /// Only a visible window that opted in can be read; the capsule and overlay never.
    @Test @MainActor
    func captureIncludesOnlyVisibleWindowsThatOptIn() {
        let readable = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        readable.identifier = .readableBySaywing
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        let hidden = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        hidden.identifier = .readableBySaywing
        readable.orderFront(nil); other.orderFront(nil)
        defer { readable.orderOut(nil); other.orderOut(nil) }
        #expect(ScreenCaptureService.readableWindowIDs(in: [readable, other, hidden]) == [CGWindowID(readable.windowNumber)])
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

    /// Open RAIL-M §4: every build, not only release packaging, carries the unchanged
    /// pinned license and the binding use restrictions for the bundled model.
    @Test
    func everyBuildBundlesTheSupertonicModelTerms() throws {
        let license = try #require(ModelTerms.licenseURL(in: .main))
        #expect(try SHA256Digest.hex(ofFileAt: license) == ModelTerms.pinnedLicenseSHA256)
        let document = try #require(ModelTerms.document(in: .main))
        #expect(document.contains("3cadd1ee6394adea1bd021217a0e650ede09a323"))
        #expect(document.contains("Binding terms for users of the model"))
        #expect(document.contains("You agree not to use the Model or Derivatives of the Model:"))
        #expect(document.hasSuffix(try String(contentsOf: license, encoding: .utf8)), "The full license follows the terms unchanged.")
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

@Suite("Persistent guided setup", .serialized)
@MainActor
struct PersistentGuidedSetupTests {
    private func fixture() -> (AppModel, UserDefaults, String) {
        let suite = "com.christopherbobel.OpenScreenReader.setup-merge-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let model = AppModel(modelTerms: .acceptedForTesting(), shortcutStore: MemoryShortcutStore(), hotkeyManager: RegisteredHotkeyManagerFake(), preferences: defaults)
        return (model, defaults, suite)
    }
    @Test func modelAndShortcutStepsSurviveRelaunchWithoutStartingATrial() {
        let (model, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let permissions = PermissionStatus { _ in true }
        let first = SetupFlowController(model: model, permissions: permissions, start: .readingModel)
        first.advance()
        #expect(first.step == .readingShortcuts)
        first.stop()
        let restored = SetupFlowController(model: model, permissions: permissions)
        defer { restored.stop() }
        #expect(restored.step == .readingShortcuts)
        #expect(restored.trial == .waiting)
        #expect(!restored.readingConfirmed)
        restored.advance()
        #expect(restored.step == .tryReading)
        #expect(model.status == .ready)
    }
    @Test func permissionHandoffRestoresWaitingAndSkipsOnlyAnAllowedGrant() {
        let (model, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["step": "screenRecording", "waitingFor": "screenRecording", "resume": true], forKey: SetupFlowController.checkpointKey)
        let waiting = SetupFlowController(model: model, permissions: PermissionStatus { _ in false })
        #expect(waiting.step == .permission(.screenRecording))
        #expect(waiting.awaiting == .screenRecording)
        waiting.stop()
        let restored = SetupFlowController(model: model, permissions: PermissionStatus { _ in true })
        defer { restored.stop() }
        #expect(restored.step == .readingModel)
        #expect(!restored.readingConfirmed)
    }
    @Test func revokedGrantIsRecheckedBeforeTrialButNotBeforeConfiguration() {
        let (model, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["step": "readingTest", "resume": true], forKey: SetupFlowController.checkpointKey)
        let trial = SetupFlowController(model: model, permissions: PermissionStatus { _ in false })
        #expect(trial.step == .permission(.screenRecording))
        trial.stop()
        defaults.set(["step": "readingShortcuts", "resume": true], forKey: SetupFlowController.checkpointKey)
        let configuration = SetupFlowController(model: model, permissions: PermissionStatus { _ in false })
        defer { configuration.stop() }
        #expect(configuration.step == .readingShortcuts)
    }
    @Test func laterKeepsCheckpointAndFinishClearsIt() {
        let (model, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        let flow = SetupFlowController(model: model, permissions: PermissionStatus { _ in false }, start: .readingShortcuts)
        defer { flow.stop() }
        flow.persistCheckpoint(resume: false)
        #expect(defaults.dictionary(forKey: SetupFlowController.checkpointKey)?["resume"] as? Bool == false)
        #expect(defaults.dictionary(forKey: SetupFlowController.checkpointKey)?["step"] as? String == "readingShortcuts")
        model.finishSetup()
        #expect(defaults.dictionary(forKey: SetupFlowController.checkpointKey) == nil)
    }
    @Test func failedRelaunchKeepsAppOpenAndShortcutCaptureBlocksRestart() {
        let (model, defaults, suite) = fixture()
        defer { defaults.removePersistentDomain(forName: suite) }
        var terminated = false
        model.restartSetup(launch: { throw CocoaError(.executableNotLoadable) }, terminate: { terminated = true })
        #expect(!terminated)
        #expect(model.setupRestartError != nil)
        model.setRecordingShortcut(true)
        var launched = false
        model.restartSetup(launch: { launched = true; return nil }, terminate: {})
        #expect(!launched)
        model.setRecordingShortcut(false)
    }
}

@Suite("Update check at launch")
@MainActor
struct UpdateLaunchTests {
    @Test func checksImmediatelyAfterStartWhenEnabled() throws {
        let updater = LaunchUpdaterStub()
        try AppUpdateController.startCheckingAtLaunch(updater)
        #expect(updater.events == ["start", "read preference", "background check"])
    }

    @Test func respectsPreferenceResolvedDuringStartup() throws {
        let updater = LaunchUpdaterStub()
        updater.enabledAfterStart = false
        try AppUpdateController.startCheckingAtLaunch(updater)
        #expect(updater.events == ["start", "read preference"])
    }

    @Test func failedStartupNeverChecksOrReadsPreferences() {
        let updater = LaunchUpdaterStub()
        updater.failStartup = true
        #expect(throws: LaunchUpdaterStub.StartError.self) {
            try AppUpdateController.startCheckingAtLaunch(updater)
        }
        #expect(updater.events == ["start"])
    }
}

@MainActor
private final class LaunchUpdaterStub: AppUpdaterStarting {
    struct StartError: Error {}
    var events: [String] = []
    var enabledAfterStart = true
    var failStartup = false
    private var enabled = true
    var automaticallyChecksForUpdates: Bool {
        events.append("read preference")
        return enabled
    }
    func start() throws {
        events.append("start")
        if failStartup { throw StartError() }
        enabled = enabledAfterStart
    }
    func checkForUpdatesInBackground() { events.append("background check") }
}
