import SwiftUI

@main
struct OpenScreenReaderApp: App {
    @StateObject private var model: AppModel = {
        // One sound player serves pipeline cues and the reading control's press feedback.
        let sounds = InterfaceSoundPlayer()
        let testing = ProcessInfo.processInfo.arguments.contains("--uitesting")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["OSR_SHORTCUT_TEST_SUITE"] != nil
        let dictation: DictationController?
        #if DEBUG
        if testing && ProcessInfo.processInfo.arguments.contains("--test-setup") {
            let fixture = ProcessInfo.processInfo.environment["OSR_SETUP_MODEL_RESOURCES"].map { URL(fileURLWithPath: $0) }
            let store = fixture.map { DictationModelStore(resources: $0, installRoot: $0.appendingPathComponent("Installed")) }
            dictation = DictationController(resources: fixture, models: store, registerHotkey: false)
        } else { dictation = testing ? nil : DictationController() }
        #else
        dictation = testing ? nil : DictationController()
        #endif
        let model = AppModel(readingPanel: ReadingPanelController(interfaceSounds: sounds), interfaceSounds: sounds,
                        queueHotkeyManager: GlobalHotkeyManager(), dictation: dictation)
        // Prepare once the SwiftUI StateObject is established; never open the microphone.
        DispatchQueue.main.async {
            if !testing { dictation?.loadModel() }
            // Resume setup at launch, even before the menu bar item is opened.
            model.offerSetupIfNeeded()
        }
        if ProcessInfo.processInfo.arguments.contains("--dictation-smoke") {
            // Showing an AppKit window while SwiftUI constructs its StateObject
            // re-enters the scene graph. Begin the explicit GUI check next turn.
            DispatchQueue.main.async { dictation?.startSmoke() }
        } else if ProcessInfo.processInfo.arguments.contains("--dictation-setup") {
            DispatchQueue.main.async { dictation?.showWindow() }
        }
        return model
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label {
                Text("Saywing")
            } icon: {
                Image("SaywingMenuBar")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            }
                .accessibilityLabel("Saywing, \(model.activityTitle)")
                .help("Saywing · \(model.activityTitle)")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
