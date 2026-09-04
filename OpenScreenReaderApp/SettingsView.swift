import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var permissionNotice: String?
    @State private var draftShortcut = ShortcutConfiguration.default
    @State private var confirmCommonShortcut = false

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Status", value: model.status.title)
                LabeledContent("Global shortcut", value: model.shortcutConfiguration.displayName)
                    .accessibilityIdentifier("activeShortcut")
                LabeledContent("Speech model", value: "Not packaged yet")
            }

            Section("Keyboard shortcut") {
                HStack {
                    modifierToggle("Command ⌘", flag: UInt32(cmdKey))
                    modifierToggle("Shift ⇧", flag: UInt32(shiftKey))
                }
                HStack {
                    modifierToggle("Option ⌥", flag: UInt32(optionKey))
                    modifierToggle("Control ⌃", flag: UInt32(controlKey))
                }
                Picker("Key", selection: $draftShortcut.key) {
                    ForEach(ShortcutConfiguration.availableKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .accessibilityIdentifier("shortcutKey")
                LabeledContent("New shortcut", value: draftShortcut.displayName)
                HStack {
                    Button("Apply Shortcut") {
                        if draftShortcut.modifiers == UInt32(cmdKey) {
                            confirmCommonShortcut = true
                        } else {
                            model.enqueueShortcutChange(draftShortcut)
                        }
                    }
                    .disabled(!draftShortcut.isValid)
                    .accessibilityIdentifier("applyShortcut")
                    Button("Restore Default") {
                        draftShortcut = .default
                        model.enqueueShortcutChange(.default)
                    }
                }
                Text("Choose A–Z, 0–9, or Space with Command, Option, or Control; Shift is optional. Escape always cancels. Changes are saved locally.")
                    .font(.caption)
                Text("Shortcuts can override commands in other apps. Not all conflicts can be detected. The default ⌘⇧Y overlaps macOS’s Make Sticky service.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.canChangeShortcut {
                    Text("Stop the current operation before changing its shortcut.")
                }
                if let notice = model.shortcutNotice {
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shortcutNotice")
                }
            }
            .disabled(!model.canChangeShortcut)

            Section("Privacy") {
                Text("Only the selected region is captured in memory. Apple Vision recognizes German and English text locally. Images and recognized text are discarded after recognition; only character and line counts remain. Nothing is copied to the clipboard or sent over the network. Speech is not available yet.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Permissions") {
                Text("Screen Recording allows the selected region to be captured. Input Monitoring lets Escape cancel while another app is active; only Escape is checked, and monitoring stops when the operation ends.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Screen Recording…") {
                    let granted = CGRequestScreenCaptureAccess()
                    permissionNotice = granted ? "Screen Recording is allowed. Select a region to retry."
                        : "Enable OpenScreenReader under System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app if requested."
                }
                Button("Allow Input Monitoring…") {
                    let granted = CGRequestListenEventAccess()
                    permissionNotice = granted ? "Input Monitoring is allowed. Select a region to retry."
                        : "Enable OpenScreenReader under System Settings → Privacy & Security → Input Monitoring, then reopen the app if requested."
                }
                if let permissionNotice {
                    Text(permissionNotice).fixedSize(horizontal: false, vertical: true)
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 680)
        .padding()
        .navigationTitle("OpenScreenReader Settings")
        .accessibilityLabel("OpenScreenReader settings")
        .onAppear { draftShortcut = model.shortcutConfiguration }
        .alert("Override app commands?", isPresented: $confirmCommonShortcut) {
            Button("Use Shortcut") { model.enqueueShortcutChange(draftShortcut) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(draftShortcut.displayName) may replace a familiar command in other apps while OpenScreenReader is running. Use it anyway?")
        }
    }

    private func modifierToggle(_ title: String, flag: UInt32) -> some View {
        Toggle(title, isOn: Binding(
            get: { draftShortcut.modifiers & flag != 0 },
            set: { enabled in
                if enabled { draftShortcut.modifiers |= flag }
                else { draftShortcut.modifiers &= ~flag }
            }
        ))
        .toggleStyle(.checkbox)
    }
}
