import AppKit
import Carbon.HIToolbox
import SwiftUI

enum SettingsTab: Hashable { case general, reading, dictation, shortcuts, privacy }

/// Dictation preferences live here; the dictation window is only for trying it out.
struct DictationSettingsSection: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var models: DictationModelStore
    @State private var pendingInstall: DictationModel?
    /// Edited as free text; the controller keeps only the parsed terms.
    @State private var vocabularyText: String

    init(controller: DictationController) {
        self.controller = controller
        _models = ObservedObject(wrappedValue: controller.models)
        _vocabularyText = State(initialValue: controller.vocabulary.joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: Binding(get: { controller.selectedModel }, set: { choose($0) })) {
                    ForEach(DictationModel.allCases, id: \.self) { model in
                        Text(models.isInstalled(model) ? model.displayName
                             : String(localized: "Install \(model.displayName)… (\(downloadSize(model)))")).tag(model)
                    }
                }
                .disabled(!controller.canChangeModel)
                .accessibilityIdentifier("dictationModel")
                ForEach(DictationModel.allCases, id: \.self) { model in installRow(model) }
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
                TextEditor(text: $vocabularyText)
                    .font(.body)
                    .frame(minHeight: 66)
                    .accessibilityLabel("Vocabulary")
                    .accessibilityIdentifier("dictationVocabulary")
                    .onChange(of: vocabularyText) { _, text in controller.setVocabulary(text) }
            } header: {
                Text("Vocabulary")
            } footer: {
                Text("One name or term per line, up to \(DictationVocabulary.maximumTerms). They help the model spell words it rarely hears. The list stays on this Mac.")
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
        .confirmationDialog(
            String(localized: "Install \(pendingInstall?.displayName ?? "")?"),
            isPresented: Binding(get: { pendingInstall != nil }, set: { if !$0 { pendingInstall = nil } })
        ) {
            Button("Download and Install") {
                if let model = pendingInstall { controller.install(model) }
                pendingInstall = nil
            }
            Button("Cancel", role: .cancel) { pendingInstall = nil }
        } message: {
            Text("Saywing downloads about \(pendingInstall.map { downloadSize($0) } ?? "") once from Hugging Face and checks every file. Your recordings and text are never sent; dictation stays on this Mac.")
        }
    }

    /// Installed models switch immediately; missing ones are only downloaded after confirmation.
    private func choose(_ model: DictationModel) {
        if models.isInstalled(model) {
            controller.selectModel(model)
        } else if models.availability[model] == .notInstalled || isFailed(model) {
            pendingInstall = model
        }
    }

    private func isFailed(_ model: DictationModel) -> Bool {
        if case .failed = models.availability[model] { return true }
        return false
    }

    private func downloadSize(_ model: DictationModel) -> String {
        ByteCountFormatter.string(fromByteCount: models.downloadSize(of: model) ?? 0, countStyle: .file)
    }

    @ViewBuilder private func installRow(_ model: DictationModel) -> some View {
        switch models.availability[model] {
        case .installing(let fraction):
            LabeledContent(String(localized: "Installing \(model.displayName)…")) {
                HStack {
                    ProgressView(value: fraction).frame(width: 140)
                        .accessibilityLabel(String(localized: "Download progress"))
                    Button("Cancel") { controller.cancelInstall(model) }
                }
            }
        case .failed(let message):
            LabeledContent(String(localized: "\(model.displayName) not installed")) {
                HStack {
                    Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") { controller.install(model) }
                }
            }
        default:
            EmptyView()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @StateObject private var permissions = PermissionStatus()
    @State private var pendingShortcut: (shortcut: ShortcutConfiguration, queue: Bool)?
    @State private var confirmCommonShortcut = false
    @State private var rejectedKeystroke = false
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
        .onAppear { takeRequestedTab() }
        .onChange(of: model.requestedSettingsTab) { _, _ in takeRequestedTab() }
        // Validation and notices appear without focus moving to them; say them aloud.
        .onChange(of: rejectedKeystroke) { _, rejected in
            if rejected { AccessibilityNotification.Announcement(String(localized: "Use a letter, digit or Space with ⌘, ⌥ or ⌃. Shift is optional.")).post() }
        }
        .onChange(of: model.shortcutNotice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(notice).post() }
        }
        .onChange(of: model.queueShortcutNotice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(notice).post() }
        }
        .alert("Override app commands?", isPresented: $confirmCommonShortcut, presenting: pendingShortcut) { pending in
            Button("Use Shortcut") {
                if pending.queue { model.enqueueQueueShortcutChange(pending.shortcut) }
                else { model.enqueueShortcutChange(pending.shortcut) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("\(pending.shortcut.displayName) may replace a familiar command in other apps while Saywing is running. Use it anyway?")
        }
    }

    private func takeRequestedTab() {
        guard let requested = model.requestedSettingsTab else { return }
        tab = requested
        model.requestedSettingsTab = nil
    }

    private var generalTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
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
                Label("Additional dictation models are downloaded from Hugging Face only when you choose to install one.", systemImage: "arrow.down.circle")
                Label("Screenshots, recognized text and audio are never saved.", systemImage: "externaldrive.badge.xmark")
                Label("Reading never touches the clipboard. Dictation uses it briefly to paste and then restores it.", systemImage: "doc.on.clipboard")
            }
            .fixedSize(horizontal: false, vertical: true)
            Section("Permissions") {
                ForEach(SaywingPermission.allCases) { PermissionRow(permission: $0, status: permissions) }
                if let errorMessage = model.errorMessage {
                    // Colour on the symbol only; the text keeps full contrast.
                    Label { Text(errorMessage) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shortcutsTab: some View {
        Form {
            Section {
                HStack {
                    Text("Read screen region")
                    Spacer()
                    recorder(for: model.shortcutConfiguration, queue: false, identifier: "shortcutRecorder",
                             label: String(localized: "Read screen region"))
                }
                if rejectedKeystroke {
                    Label { Text("Use a letter, digit or Space with ⌘, ⌥ or ⌃. Shift is optional.") } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.callout)
                }
                if !model.canChangeShortcut {
                    Text("Stop the current operation before changing its shortcut.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let notice = model.shortcutNotice {
                    Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shortcutNotice")
                }
                LabeledContent("") {
                    Button("Restore Default") { apply(.default, queue: false) }
                        .disabled(model.shortcutConfiguration == .default)
                }
            } footer: {
                Text("Click the field and press a new combination. Press the shortcut again while Saywing reads to add another region; Escape stops everything.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                DisclosureGroup("Advanced") {
                    HStack {
                        Text("Add to queue")
                        Spacer()
                        recorder(for: model.queueShortcutConfiguration, queue: true, identifier: "queueShortcutRecorder",
                                 label: String(localized: "Add to queue"))
                    }
                    Text("Optional. Pressing the reading shortcut again already adds a region.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let notice = model.queueShortcutNotice { Text(notice).font(.callout) }
                    LabeledContent("") {
                        Button("Restore Default") { apply(.queueDefault, queue: true) }
                            .disabled(model.queueShortcutConfiguration == .queueDefault)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(!model.canChangeShortcut)
    }

    private func recorder(for shortcut: ShortcutConfiguration, queue: Bool, identifier: String, label: String) -> some View {
        ShortcutRecorder(shortcut: shortcut, identifier: identifier, label: label,
                         onRecordingChange: { recording in
                             if recording { rejectedKeystroke = false }
                             model.setRecordingShortcut(recording)
                         },
                         onRecord: { apply($0, queue: queue) },
                         onRejected: { rejectedKeystroke = true })
            .frame(width: 150, height: 24)
    }

    /// Command alone replaces familiar app commands, so it needs confirmation.
    private func apply(_ shortcut: ShortcutConfiguration, queue: Bool) {
        if shortcut.modifiers == UInt32(cmdKey) {
            pendingShortcut = (shortcut, queue)
            confirmCommonShortcut = true
        } else if queue {
            model.enqueueQueueShortcutChange(shortcut)
        } else {
            model.enqueueShortcutChange(shortcut)
        }
    }

}

struct PlaybackControlsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(model.isPaused ? String(localized: "Paused") : model.status.title, systemImage: model.isPaused ? "pause.fill" : "waveform")
                    .font(.headline)
                Spacer()
                Button { model.enqueueStopRequest() } label: { Image(systemName: "stop.fill") }
                    .help("Stop everything and clear the queue")
                    .accessibilityLabel("Stop everything")
            }
            HStack(spacing: 12) {
                Button { model.togglePause() } label: {
                    Label(model.isPaused ? String(localized: "Resume") : String(localized: "Pause"), systemImage: model.isPaused ? "play.fill" : "pause.fill")
                }.disabled(!model.canPause)
                    .accessibilityIdentifier("togglePlaybackPause")
                Button { model.enqueueSkipRequest() } label: { Label("Next", systemImage: "forward.end.fill") }
                    .disabled(!model.canSkipText)
            }
            Picker("Speed", selection: Binding(get: { model.playbackRate }, set: { model.setPlaybackRate($0) })) {
                ForEach(SpeechSpeed.presets, id: \.self) { Text(SpeechSpeed.label($0)).tag($0) }
            }
            Divider()
            HStack {
                Text("Up Next · \(model.queuedTextCount)").font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { model.enqueueAddRequest() } label: { Image(systemName: "plus") }
                    .disabled(!model.canAddToQueue).help("Select another screen region")
                    .accessibilityLabel("Add Screen Region to Queue…")
            }
            if model.queueEntries.isEmpty {
                Text("Press \(model.shortcutConfiguration.displayName) again to add a text.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.queueEntries.enumerated()), id: \.element.id) { index, entry in
                    // Each row is one group named by its text, so "Move up" says which text moves.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.preview).lineLimit(2)
                        HStack {
                            Button("Read Now") { model.playQueueEntry(entry.id) }
                            Spacer()
                            Button { model.moveQueueEntry(entry.id, offset: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(index == 0).accessibilityLabel("Move up")
                            Button { model.moveQueueEntry(entry.id, offset: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(index == model.queuedTextCount - 1).accessibilityLabel("Move down")
                            Button { model.removeQueueEntry(entry.id) } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel("Remove from queue")
                        }.controlSize(.small)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(entry.preview)
                }
            }
            Text("This session only · nothing is saved").font(.callout).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 340)
        .tint(Color("AccentColor"))
        .accessibilityIdentifier("playbackControls")
    }
}

/// Opened from the question mark of a failed reading: the concrete reason and
/// one next step, anchored to the control that failed.
struct ReadingErrorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Can’t read aloud", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .symbolRenderingMode(.multicolor)
            Text(model.errorMessage ?? String(localized: "Reading did not work."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                switch model.errorHelp {
                case let .allow(permission):
                    Button("Open Setup…") {
                        model.closeErrorHelp()
                        model.showSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityHint(Text("\(permission.systemName) is not allowed"))
                case .shortcut:
                    Button("Shortcut Settings…") {
                        model.closeErrorHelp()
                        model.openSettings(.shortcuts)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                case .retry:
                    Button("Try Again") {
                        model.closeErrorHelp()
                        model.enqueueReadRequest()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 320)
        .tint(Color("AccentColor"))
        .accessibilityIdentifier("readingErrorHelp")
    }
}

