import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Label(model.status.title, systemImage: model.status.symbolName)
            .accessibilityLabel("Status")
            .accessibilityValue(model.status.title)

        Divider()

        Button(model.readActionTitle) {
            model.enqueueReadRequest()
        }
        .help("Select a screen region with ⌃⌥R")

        Text(model.lastCaptureSize == nil
             ? "Select a region to capture locally. Speech is not available yet."
             : "Region captured locally. No image was saved.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }

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
