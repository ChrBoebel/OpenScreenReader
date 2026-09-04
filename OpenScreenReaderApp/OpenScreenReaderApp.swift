import SwiftUI

@main
struct OpenScreenReaderApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label("OpenScreenReader", systemImage: model.status.symbolName)
                .accessibilityLabel("OpenScreenReader, \(model.status.title)")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
