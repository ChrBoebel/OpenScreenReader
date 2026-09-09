import AppKit
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Label(model.isPaused ? "Paused" : model.status.title, systemImage: model.isPaused ? "pause.fill" : model.status.symbolName)
            .accessibilityLabel("Status")
            .accessibilityValue(model.isPaused ? "Paused" : model.status.title)

        Divider()

        Button(model.isPaused ? "Resume Reading" : "Pause Reading") { model.togglePause() }
            .disabled(!model.canPause)

        Button(model.readActionTitle) {
            model.enqueueReadRequest()
        }
        .help(model.canChangeShortcut ? "Select a screen region with \(model.shortcutConfiguration.displayName)"
              : "Stop playback and clear the queue. Escape also stops everything.")

        Button("Add Screen Region to Queue…") { model.enqueueAddRequest() }
            .disabled(!model.canAddToQueue)
            .help("Press \(model.shortcutConfiguration.displayName) again to add text. Playback continues.")
        Button("Next Text") { model.enqueueSkipRequest() }
            .disabled(!model.canSkipText)
        if model.queuedTextCount > 0 { Text("\(model.queuedTextCount) text(s) waiting") }
        if let notice = model.queueNotice { Text(notice).font(.caption) }
        Menu("Speed · \(SpeechSpeed.label(model.playbackRate))") {
            ForEach(SpeechSpeed.presets, id: \.self) { speed in
                Button {
                    model.setPlaybackRate(speed)
                } label: {
                    if model.playbackRate == speed { Label(SpeechSpeed.label(speed), systemImage: "checkmark") }
                    else { Text(SpeechSpeed.label(speed)) }
                }
            }
        }

        Text(model.captureFeedback)
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

        Button("Set Up & Test…") { model.showSetup() }

        Button("Quit OpenScreenReader") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
