import AppKit
import Carbon.HIToolbox
import SwiftUI

enum SettingsTab: Hashable { case general, reading, dictation, shortcuts, privacy }

/// Dictation preferences live here; the dictation window is only for trying it out.
struct DictationSettingsSection: View {
    @ObservedObject var controller: DictationController

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: Binding(get: { controller.selectedModel }, set: { controller.selectModel($0) })) {
                    ForEach(DictationModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .disabled(!controller.canChangeModel)
                .accessibilityIdentifier("dictationModel")
                Picker("Language", selection: Binding(get: { controller.language }, set: { controller.setLanguage($0) })) {
                    ForEach(DictationLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("dictationLanguage")
                Toggle("Wait 2 seconds before restoring the clipboard", isOn: Binding(
                    get: { controller.restoresClipboardSlowly }, set: { controller.setRestoresClipboardSlowly($0) }))
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("dictationSlowPaste")
                LabeledContent("Status", value: controller.statusText)
            } footer: {
                Text("The model loads automatically and stays ready while Saywing is open. Turn on the longer wait if an app pastes your previous clipboard instead of the dictation.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Hold Fn", value: String(localized: "Dictate, release to paste"))
                LabeledContent("Press Fn twice", value: String(localized: "Hands-free; Fn finishes"))
                LabeledContent("⌥⇧Space", value: String(localized: "Start or finish without Fn"))
                LabeledContent("Escape", value: String(localized: "Discard"))
                LabeledContent("") {
                    Button("Try Dictation…") { controller.showWindow() }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var permissions = PermissionStatus()
    @State private var draftShortcut = ShortcutConfiguration.default
    @State private var confirmCommonShortcut = false
    @State private var editingQueueShortcut = false
    @State private var tab: SettingsTab

    init(model: AppModel, initialTab: SettingsTab = .general) {
        self.model = model
        _tab = State(initialValue: initialTab)
    }
    @AppStorage(InterfaceSoundPlayer.preferenceKey, store: InterfaceSoundPlayer.defaults)
    private var interfaceSoundsEnabled = true
    @AppStorage(InterfaceSoundPlayer.volumeKey, store: InterfaceSoundPlayer.defaults)
    private var interfaceSoundsVolume = InterfaceSoundPlayer.defaultVolume
    @AppStorage(ReadingPanelPlacement.edgeKey, store: InterfaceSoundPlayer.defaults)
    private var readingPanelEdge = ReadingPanelEdge.bottom.rawValue

    /// macOS settings convention: one toolbar tab per activity, grouped forms,
    /// the common choices first and explanations only where they prevent a mistake.
    var body: some View {
        TabView(selection: $tab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            readingTab
                .tabItem { Label("Read Aloud", systemImage: "speaker.wave.2") }.tag(SettingsTab.reading)
            dictationTab
                .tabItem { Label("Dictate", systemImage: "mic") }.tag(SettingsTab.dictation)
            shortcutsTab
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(SettingsTab.shortcuts)
            privacyTab
                .tabItem { Label("Privacy", systemImage: "hand.raised") }.tag(SettingsTab.privacy)
        }
        .frame(width: 540)
        .accessibilityLabel("Saywing settings")
        .onAppear { draftShortcut = editingQueueShortcut ? model.queueShortcutConfiguration : model.shortcutConfiguration }
        .alert("Override app commands?", isPresented: $confirmCommonShortcut) {
            Button("Use Shortcut") { applyDraftShortcut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(draftShortcut.displayName) may replace a familiar command in other apps while Saywing is running. Use it anyway?")
        }
    }

    private var generalTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("Saywing Quiet Owl app logo")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saywing").font(.title2.weight(.semibold))
                        Text("Read aloud and dictate on your Mac.").foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Set Up & Test…") { model.showSetup() }
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle("Interface sounds", isOn: $interfaceSoundsEnabled)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("interfaceSoundsEnabled")
                Slider(value: $interfaceSoundsVolume, in: 0...1) { Text("Volume") }
                    .disabled(!interfaceSoundsEnabled)
                    .accessibilityIdentifier("interfaceSoundsVolume")
            } footer: {
                Text("Short cues when the control opens, when reading is done and when something needs attention. Never during speech.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var readingTab: some View {
        Form {
            Section {
                Picker("Speed", selection: Binding(get: { model.playbackRate }, set: { model.setPlaybackRate($0) })) {
                    ForEach(SpeechSpeed.presets, id: \.self) { speed in Text(SpeechSpeed.label(speed)).tag(speed) }
                }
                .accessibilityIdentifier("readingSpeed")
                Picker("Control position", selection: $readingPanelEdge) {
                    ForEach(ReadingPanelEdge.allCases, id: \.rawValue) { edge in
                        Text(edge.title).tag(edge.rawValue)
                    }
                }
                .accessibilityIdentifier("readingPanelPosition")
                .onChange(of: readingPanelEdge) { _, value in
                    // Keep the offset from dragging when Settings synchronizes the selected edge.
                    let placement = ReadingPanelPlacement.load(from: InterfaceSoundPlayer.defaults)
                    guard placement.edge.rawValue == value else { return }
                    NotificationCenter.default.post(name: ReadingPanelPlacement.changed, object: InterfaceSoundPlayer.defaults)
                }
                LabeledContent("") {
                    Button("Preview & Move Control") { model.previewReadingPanelPosition() }
                        .disabled(!model.canChangeShortcut)
                        .accessibilityIdentifier("previewReadingPanelPosition")
                }
            } footer: {
                Text("Speed changes immediately, without changing pitch. Drag the control to the left, right or bottom edge; its position is remembered.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Voice") {
                LabeledContent("Model", value: SpeechRuntimeConfiguration(root: LocalSpeechService.developmentRoot).modelName)
                LabeledContent("Voice", value: String(localized: "Machine-generated voice M1"))
                LabeledContent("License", value: "BigScience Open RAIL-M")
                LabeledContent("Runtime", value: LocalSpeechService.installationSummary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var dictationTab: some View {
        if let dictation = model.dictation {
            DictationSettingsSection(controller: dictation)
        } else {
            Form { Text("Dictation is not available in this build.").foregroundStyle(.secondary) }
                .formStyle(.grouped)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyTab: some View {
        Form {
            Section {
                Label("Text recognition, speech and dictation run on this Mac. Nothing is sent to a server.", systemImage: "lock.laptopcomputer")
                Label("Screenshots, recognized text and audio are never saved.", systemImage: "externaldrive.badge.xmark")
                Label("Reading never touches the clipboard. Dictation uses it briefly to paste and then restores it.", systemImage: "doc.on.clipboard")
            }
            .fixedSize(horizontal: false, vertical: true)
            Section("Permissions") {
                ForEach(SaywingPermission.allCases) { PermissionRow(permission: $0, status: permissions) }
                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shortcutsTab: some View {
        Form {
            Section {
                LabeledContent("Current shortcut", value: model.shortcutConfiguration.displayName)
                    .accessibilityIdentifier("activeShortcut")
                Picker("Action", selection: $editingQueueShortcut) {
                    Text("Read / Add to queue").tag(false)
                    Text("Additional queue shortcut").tag(true)
                }
                .accessibilityIdentifier("shortcutAction")
                .onChange(of: editingQueueShortcut) { _, queue in
                    draftShortcut = queue ? model.queueShortcutConfiguration : model.shortcutConfiguration
                }
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
                            applyDraftShortcut()
                        }
                    }
                    .disabled(!draftShortcut.isValid)
                    .accessibilityIdentifier("applyShortcut")
                    Button("Restore Default") {
                        draftShortcut = editingQueueShortcut ? .queueDefault : .default
                        applyDraftShortcut()
                    }
                }
                if !model.canChangeShortcut {
                    Text("Stop the current operation before changing its shortcut.")
                }
                if let notice = model.shortcutNotice {
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shortcutNotice")
                }
                LabeledContent("Add to queue", value: model.queueShortcutConfiguration.displayName)
                if let notice = model.queueShortcutNotice { Text(notice).font(.callout) }
            } header: {
                Text("Read Screen Region")
            } footer: {
                Text("Press the shortcut again while Saywing reads to add another region. Escape stops everything.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .disabled(!model.canChangeShortcut)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func applyDraftShortcut() {
        if editingQueueShortcut { model.enqueueQueueShortcutChange(draftShortcut) }
        else { model.enqueueShortcutChange(draftShortcut) }
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

struct PlaybackControlsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(model.isPaused ? "Pausiert" : model.status.title, systemImage: model.isPaused ? "pause.fill" : "waveform")
                    .font(.headline)
                Spacer()
                Button { model.enqueueStopRequest() } label: { Image(systemName: "stop.fill") }
                    .help("Alles stoppen und Warteschlange leeren")
                    .accessibilityLabel("Alles stoppen")
            }
            HStack(spacing: 12) {
                Button { model.togglePause() } label: {
                    Label(model.isPaused ? "Fortsetzen" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }.disabled(!model.canPause)
                    .accessibilityIdentifier("togglePlaybackPause")
                Button { model.enqueueSkipRequest() } label: { Label("Weiter", systemImage: "forward.end.fill") }
                    .disabled(!model.canSkipText)
            }
            Picker("Tempo", selection: Binding(get: { model.playbackRate }, set: { model.setPlaybackRate($0) })) {
                ForEach(SpeechSpeed.presets, id: \.self) { Text(SpeechSpeed.label($0)).tag($0) }
            }
            Divider()
            HStack {
                Text("Als Nächstes · \(model.queuedTextCount)").font(.headline)
                Spacer()
                Button { model.enqueueAddRequest() } label: { Image(systemName: "plus") }
                    .disabled(!model.canAddToQueue).help("Weiteren Bildschirmbereich auswählen")
            }
            if model.queueEntries.isEmpty {
                Text("Drücke \(model.shortcutConfiguration.displayName) erneut, um einen Text einzureihen.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.queueEntries.enumerated()), id: \.element.id) { index, entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.preview).lineLimit(2)
                        HStack {
                            Button("Jetzt lesen") { model.playQueueEntry(entry.id) }
                            Spacer()
                            Button { model.moveQueueEntry(entry.id, offset: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0).accessibilityLabel("Text nach oben")
                            Button { model.moveQueueEntry(entry.id, offset: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == model.queuedTextCount - 1).accessibilityLabel("Text nach unten")
                            Button { model.removeQueueEntry(entry.id) } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel("Text aus Warteschlange entfernen")
                        }.controlSize(.small)
                    }
                }
            }
            Text("Nur für diese Sitzung · nichts wird gespeichert").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 340)
        .tint(Color("AccentColor"))
        .accessibilityIdentifier("playbackControls")
    }
}

/// One setup for both activities: grants, then a real test of each. A green
/// grant is a system check only; the tests confirm the complete flow.
struct SetupView: View {
    @ObservedObject var model: AppModel
    @StateObject private var permissions = PermissionStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Saywing").font(.title2.weight(.semibold))
                    Text("Read screen text aloud and dictate – entirely on this Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(SaywingPermission.reading) { PermissionRow(permission: $0, status: permissions) }
                    Label(LocalSpeechService.installationSummary, systemImage: "waveform")
                        .font(.callout).foregroundStyle(.secondary)
                    Divider()
                    Text("Open some text in another app, then select a sentence. Press Escape while it reads.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Select Screen Region") { model.beginSetupCapture() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!permissions.canTestReading || !model.canChangeShortcut)
                            .accessibilityIdentifier("setupReadingTest")
                        Text(model.shortcutConfiguration.displayName).foregroundStyle(.secondary)
                            .accessibilityLabel("Shortcut \(model.shortcutConfiguration.displayName)")
                    }
                    if permissions.canTestReading && !permissions.isGranted(.inputMonitoring) {
                        Text("Without Input Monitoring, Escape stops reading only while Saywing is in front. The stop button always works.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
            } label: {
                Label("Read Aloud", systemImage: "speaker.wave.2")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(SaywingPermission.dictation) { PermissionRow(permission: $0, status: permissions) }
                    Divider()
                    Text("Hold Fn while you speak, release to paste. Try it in a test field first.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Dictation…") { model.dictation?.showWindow() }
                        .disabled(model.dictation == nil || !permissions.canTestDictation)
                        .accessibilityIdentifier("setupDictationTest")
                }
                .padding(8)
            } label: {
                Label("Dictate", systemImage: "mic")
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(model.isPaused ? "Paused" : model.status.title).foregroundStyle(.secondary)
                Spacer()
                Button("Check Again") { permissions.refresh() }
                Button("Done") { model.finishSetup() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
