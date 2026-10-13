import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Status first, then the primary action with its shortcut. Playback controls
/// appear only while something is reading; settings and quit stay at the bottom.
struct MenuBarContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Label(model.isPaused ? String(localized: "Paused") : model.status.title,
              systemImage: model.isPaused ? "pause.fill" : model.status.symbolName)
            .accessibilityLabel("Status")
            .accessibilityValue(model.isPaused ? String(localized: "Paused") : model.status.title)
        if let feedback = model.captureFeedback {
            Text(feedback)
        }
        if let errorMessage = model.errorMessage {
            Text(errorMessage)
            Button("Open Setup…") { model.showSetup() }
        }

        Divider()

        readButton
        if let dictation = model.dictation {
            DictationMenuContent(controller: dictation)
        }

        if model.isReadingActive {
            Divider()
            Button(model.isPaused ? "Resume Reading" : "Pause Reading") { model.togglePause() }
                .disabled(!model.canPause)
            Button("Next Text") { model.enqueueSkipRequest() }
                .disabled(!model.canSkipText)
            Button("Add Screen Region to Queue…") { model.enqueueAddRequest() }
                .disabled(!model.canAddToQueue)
            Button("Playback Controls…") { model.openPlaybackControls() }
            if model.queuedTextCount > 0 {
                Text("\(model.queuedTextCount) text(s) waiting")
            }
            if let notice = model.queueNotice { Text(notice) }
        }

        Divider()

        Menu("Speed · \(SpeechSpeed.label(model.playbackRate))") {
            ForEach(SpeechSpeed.presets, id: \.self) { speed in
                Toggle(SpeechSpeed.label(speed), isOn: Binding(
                    get: { model.playbackRate == speed },
                    set: { if $0 { model.setPlaybackRate(speed) } }))
            }
        }

        Divider()

        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Set Up & Test…") { model.showSetup() }

        Divider()

        Button("Quit Saywing") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// The global shortcut is shown next to the action, as macOS menus do.
    @ViewBuilder private var readButton: some View {
        let button = Button(model.readActionTitle) { model.enqueueReadRequest() }
            .help(model.isReadingActive ? String(localized: "Stop reading and clear the queue. Escape also stops.") : "")
        if !model.isReadingActive, let shortcut = model.shortcutConfiguration.keyboardShortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}

struct DictationMenuContent: View {
    @ObservedObject var controller: DictationController
    var body: some View {
        if controller.isActive {
            Text("Dictation · \(controller.statusText)")
            Button("Discard Dictation") { controller.cancel() }
        } else {
            // Fn cannot be shown as a menu key equivalent; name it in the title instead.
            Text("Dictate: Hold Fn")
        }
    }
}

extension ShortcutConfiguration {
    var keyboardShortcut: KeyboardShortcut? {
        guard isValid else { return nil }
        let keyEquivalent: KeyEquivalent = key == "Space" ? .space : KeyEquivalent(Character(key.lowercased()))
        var eventModifiers: SwiftUI.EventModifiers = []
        if modifiers & UInt32(cmdKey) != 0 { eventModifiers.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { eventModifiers.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { eventModifiers.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { eventModifiers.insert(.shift) }
        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }
}
