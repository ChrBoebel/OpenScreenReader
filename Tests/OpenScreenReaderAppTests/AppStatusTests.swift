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
