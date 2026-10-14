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
        #expect(plan.next(after: .permission(.inputMonitoring), granted: [.screenRecording, .inputMonitoring]) == .tryReading)
        #expect(plan.next(after: .tryReading, granted: [.screenRecording, .inputMonitoring]) == .dictationOffer)
        #expect(plan.next(after: .dictationOffer, granted: [.screenRecording, .inputMonitoring]) == .done)
        plan.wantsDictation = true
        let reading: Set<SaywingPermission> = [.screenRecording, .inputMonitoring]
        #expect(plan.next(after: .dictationOffer, granted: reading) == .permission(.microphone))
        #expect(plan.next(after: .permission(.microphone), granted: reading.union([.microphone])) == .permission(.accessibility))
        #expect(plan.next(after: .permission(.accessibility), granted: Set(SaywingPermission.allCases)) == .tryDictation)
        #expect(plan.next(after: .tryDictation, granted: Set(SaywingPermission.allCases)) == .done)
        #expect(plan.next(after: .done, granted: []) == .done)
    }

    @Test
    func setupSkipsGrantedStepsAndTestsThatCannotRun() {
        var plan = SetupPlan(dictationAvailable: true)
        // Returning users start where something is still missing, never at the welcome.
        #expect(plan.first(granted: [.inputMonitoring]) == .permission(.screenRecording))
        #expect(plan.first(granted: [.screenRecording, .inputMonitoring]) == .tryReading)
        // "Later" on a required grant also skips the test that would only fail.
        #expect(plan.next(after: .permission(.inputMonitoring), granted: [.inputMonitoring]) == .dictationOffer)
        plan.wantsDictation = true
        #expect(plan.next(after: .permission(.accessibility), granted: [.accessibility]) == .done)
        // The dictation test field works with the microphone alone.
        #expect(plan.next(after: .permission(.accessibility), granted: [.microphone]) == .tryDictation)
        // Dictation reached from its own error goes straight to its missing grants.
        #expect(plan.first(granted: [], entry: .dictation) == .permission(.microphone))
        #expect(plan.first(granted: [.microphone, .accessibility], entry: .dictation) == .tryDictation)
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
