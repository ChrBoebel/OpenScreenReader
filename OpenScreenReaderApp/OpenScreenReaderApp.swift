import SwiftUI

@main
struct OpenScreenReaderApp: App {
    @StateObject private var model: AppModel = {
        // One sound player serves pipeline cues and the reading control's press feedback.
        let sounds = InterfaceSoundPlayer()
        return AppModel(readingPanel: ReadingPanelController(interfaceSounds: sounds), interfaceSounds: sounds,
                        queueHotkeyManager: GlobalHotkeyManager())
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label("OpenScreenReader", systemImage: model.status.symbolName)
                .accessibilityLabel("OpenScreenReader, \(model.status.title)")
                .task { model.offerSetupIfNeeded() }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
