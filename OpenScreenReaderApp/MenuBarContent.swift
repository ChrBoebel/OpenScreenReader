import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Label(model.status.title, systemImage: model.status.symbolName)
            .accessibilityLabel("Status")
            .accessibilityValue(model.status.title)

        Divider()

        Button("Read Screen Region…") {}
            .disabled(true)
            .help("Region capture is not connected yet")

        Text("Capture is coming in the next implementation step.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Button("Quit OpenScreenReader") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
