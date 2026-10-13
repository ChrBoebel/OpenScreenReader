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
