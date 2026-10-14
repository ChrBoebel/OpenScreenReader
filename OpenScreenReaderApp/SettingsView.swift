import AppKit
import Carbon.HIToolbox
import SwiftUI

enum SettingsTab: Hashable { case general, reading, dictation, shortcuts, privacy }

/// Shared by Setup and Settings: a download always starts with explicit consent.
struct DictationModelSelection: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var models: DictationModelStore
    @State private var pendingInstall: DictationModel?
    @State private var showAlternatives: Bool

    init(controller: DictationController) {
        self.controller = controller
        self.models = controller.models
        _showAlternatives = State(initialValue: controller.selectedModel != .standard || controller.pendingInstallModel != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The model turns your speech into text on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
            modelRow(.standard)
            DisclosureGroup("Other Models", isExpanded: $showAlternatives) {
                VStack(alignment: .leading, spacing: 14) {
                    modelRow(.qwen)
                    Divider()
                    modelRow(.whisperLargeV3)
                }.padding(.top, 10)
            }.padding(.leading, 24)
            Text(controller.statusText).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .confirmationDialog(String(localized: "Install \(pendingInstall?.displayName ?? "")?"),
            isPresented: Binding(get: { pendingInstall != nil }, set: { if !$0 { pendingInstall = nil } })) {
                Button("Download and Install") {
                    if let pendingInstall { controller.install(pendingInstall) }
                    pendingInstall = nil
                }
                Button("Cancel", role: .cancel) { pendingInstall = nil }
            } message: {
                if let model = pendingInstall {
                    Text("Download \(size(model)) from Hugging Face (\(models.downloadSource(of: model) ?? "")). Every file is checked before use. Recordings and text stay on your Mac.")
                }
            }
    }

    private func size(_ model: DictationModel) -> String {
        models.downloadSize(of: model).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            ?? String(localized: "Size unavailable")
    }

    @ViewBuilder private func modelRow(_ model: DictationModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.displayName).font(.body.weight(.medium))
                    if models.isBundled(model) { Text("Included with Saywing").font(.callout).foregroundStyle(.secondary) }
                    else if models.isInstalled(model) { Text("Installed").font(.callout).foregroundStyle(.secondary) }
                    else if models.canDownload(model) { Text(size(model)).font(.callout).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 12)
                if models.isInstalled(model) {
                    if controller.selectedModel == model && controller.pendingInstallModel == nil {
                        Label("Selected", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Button("Use Model") { controller.selectModel(model) }
                            .disabled(!controller.canChangeModel)
                            .accessibilityIdentifier("use-\(model.rawValue)")
                    }
                } else if models.availability[model]?.isInstalling != true && models.canDownload(model) {
                    Button("Download…") { pendingInstall = model }
                        .disabled(!controller.canChangeModel)
                        .accessibilityIdentifier("download-\(model.rawValue)")
                }
            }
            if !models.isInstalled(model) && !models.canDownload(model) {
                Text("This build is missing model resources. Reinstall Saywing to restore them.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DictationInstallStatus(controller: controller, model: model)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.displayName)
    }
}

struct DictationInstallStatus: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var models: DictationModelStore
    let model: DictationModel
    init(controller: DictationController, model: DictationModel) {
        self.controller = controller; self.models = controller.models; self.model = model
    }
    var body: some View {
        switch models.availability[model] {
        case .installing(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading \(model.displayName)…").font(.callout)
                HStack {
                    ProgressView(value: fraction).accessibilityLabel("Download progress")
                    Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit().font(.callout)
                    Button("Cancel") { controller.cancelInstall(model) }
                }
            }
        case .verifying:
            HStack {
                ProgressView().controlSize(.small)
                Text("Checking model files…").font(.callout)
                Spacer()
                Button("Cancel") { controller.cancelInstall(model) }
            }
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        case .notInstalled where controller.pendingInstallModel == model:
            Text("The download was interrupted. Choose Download to try again.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        default: EmptyView()
        }
    }
}

struct DictationSettingsSection: View {
    @ObservedObject var controller: DictationController
    var body: some View {
        Form {
            Section("Model") { DictationModelSelection(controller: controller) }
            Section {
                Picker("Language", selection: Binding(get: { controller.language }, set: { controller.setLanguage($0) })) {
                    ForEach(DictationLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("dictationLanguage")
                Toggle("Wait 2 seconds before restoring the clipboard", isOn: Binding(
                    get: { controller.restoresClipboardSlowly }, set: { controller.setRestoresClipboardSlowly($0) }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("dictationSlowPaste")
            } footer: {
                Text("The model loads automatically and stays ready while Saywing is open. Turn on the longer wait if an app pastes your previous clipboard instead of the dictation.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Text(controller.activationInstructions).fixedSize(horizontal: false, vertical: true)
                Button("Try Dictation…") { controller.showWindow() }
            }
        }.formStyle(.grouped).fixedSize(horizontal: false, vertical: true)
    }
}

/// The same native keystroke fields in Setup and Settings; no second set of preferences.
struct ActivationShortcutsView: View {
    @ObservedObject var model: AppModel
    @State private var rejected = false
    @State private var pending: ShortcutConfiguration?
    @State private var pendingDictation = false
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            shortcutRow(title: String(localized: "Read screen region"), configuration: model.shortcutConfiguration,
                        dictation: false, identifier: "shortcutRecorder")
            if let notice = model.shortcutNotice { Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true) }
            if let dictation = model.dictation {
                shortcutRow(title: String(localized: "Start or finish dictation"), configuration: dictation.shortcutConfiguration,
                            dictation: true, identifier: "dictationShortcutRecorder")
                if let notice = dictation.shortcutNotice { Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true) }
                Toggle("Also dictate with Fn", isOn: Binding(get: { dictation.fnEnabled }, set: { dictation.setFnEnabled($0) }))
                    .toggleStyle(.checkbox).accessibilityIdentifier("dictationFnEnabled")
                if dictation.fnEnabled {
                    Text("Hold Fn to speak and release to paste. Press Fn twice for hands-free dictation.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Click a shortcut field and press your combination. Escape cancels the change; activation shortcuts are paused while you choose.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if rejected {
                Text("Use a letter, digit or Space with ⌘, ⌥ or ⌃. Shift is optional.")
                    .font(.callout).foregroundStyle(.orange)
            }
            Text("Escape always stops reading or discards dictation.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .disabled(!model.canChangeShortcut)
        .onDisappear { model.setRecordingShortcut(false) }
        .alert("Override app commands?", isPresented: $confirm) {
            Button("Use Shortcut") { if let pending { apply(pending, dictation: pendingDictation) } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("\(pending?.displayName ?? "") may replace a familiar command in other apps while Saywing is running. Use it anyway?")
        }
    }
    private func shortcutRow(title: String, configuration: ShortcutConfiguration, dictation: Bool, identifier: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 10)
            ShortcutRecorder(shortcut: configuration, identifier: identifier,
                onRecordingChange: { recording in rejected = false; model.setRecordingShortcut(recording) },
                onRecord: { value in
                    if value.modifiers == UInt32(cmdKey) { pending = value; pendingDictation = dictation; confirm = true }
                    else { apply(value, dictation: dictation) }
                }, onRejected: { rejected = true })
                .frame(width: 150, height: 24).accessibilityLabel(title)
            Button { apply(dictation ? .dictationDefault : .default, dictation: dictation) } label: {
                Image(systemName: "arrow.counterclockwise")
            }.help("Restore Default").accessibilityLabel(String(localized: "Restore Default") + " · " + title)
                .disabled(configuration == (dictation ? .dictationDefault : .default))
        }
    }
    private func apply(_ value: ShortcutConfiguration, dictation: Bool) {
        if dictation { model.enqueueDictationShortcutChange(value) }
        else { model.enqueueShortcutChange(value) }
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

    private var generalTab: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("Saywing text-to-voice app logo")
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
            Section { ActivationShortcutsView(model: model) }
            Section {
                DisclosureGroup("Advanced") {
                    HStack {
                        Text("Add to queue")
                        Spacer()
                        recorder(for: model.queueShortcutConfiguration, queue: true, identifier: "queueShortcutRecorder")
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

    private func recorder(for shortcut: ShortcutConfiguration, queue: Bool, identifier: String) -> some View {
        ShortcutRecorder(shortcut: shortcut, identifier: identifier,
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
                Spacer()
                Button { model.enqueueAddRequest() } label: { Image(systemName: "plus") }
                    .disabled(!model.canAddToQueue).help("Select another screen region")
            }
            if model.queueEntries.isEmpty {
                Text("Press \(model.shortcutConfiguration.displayName) again to add a text.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.queueEntries.enumerated()), id: \.element.id) { index, entry in
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
                }
            }
            Text("This session only · nothing is saved").font(.callout).foregroundStyle(.secondary)
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
    @ObservedObject private var progress: SetupProgress
    @ObservedObject private var permissions: PermissionStatus
    @State private var restartHelpExpanded = false

    init(model: AppModel) {
        self.model = model
        self.progress = model.setupProgress
        self.permissions = model.setupPermissions
    }

    private var heading: String {
        switch progress.step {
        case .screenRecording: String(localized: "Read text from your screen")
        case .inputMonitoring: String(localized: "Stop reading with Escape")
        case .readingTest: String(localized: "Try reading aloud")
        case .microphone: String(localized: "Use your microphone")
        case .accessibility: String(localized: "Dictate into other apps")
        case .dictationTest: String(localized: "Try dictation")
        case .readingModel: String(localized: "Your reading voice")
        case .dictationModel: String(localized: "Dictation on your Mac")
        case .readingShortcuts, .dictationShortcuts: String(localized: "Choose your shortcuts")
        }
    }

    static var windowHeight: CGFloat { min(640, (NSScreen.main?.visibleFrame.height ?? 720) - 80) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set Up Saywing").font(.title2.weight(.semibold))
                    Text("Your progress is saved, including when Saywing restarts.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Picker("Activity", selection: Binding(get: { progress.step.isDictation }, set: { dictation in
                    if dictation { progress.continueToDictation(granted: permissions.granted) }
                    else { progress.showReading(granted: permissions.granted) }
                })) {
                    Text("Read Aloud").tag(false)
                    Text("Dictate").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
                    .accessibilityIdentifier("setupActivity")
                Spacer()
                Text("Entirely on this Mac").font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(0..<4) { index in
                    Button { progress.visit(stage: index) } label: {
                        VStack(spacing: 5) {
                            Text(stageTitle(index)).font(.callout.weight(progress.step.stage == index ? .semibold : .regular))
                            Capsule().fill(progress.step.stage == index ? Color.accentColor : Color.clear).frame(height: 2)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(progress.step.stage == index ? .isSelected : [])
                        .accessibilityIdentifier("setupStage-\(index)")
                }
            }

            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(heading).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("setupCurrentStep")
                        .accessibilityAddTraits(.isHeader)

                    if let permission = progress.step.permission {
                        PermissionRow(permission: permission, status: permissions) {
                            progress.prepareForPermission(permission)
                        }
                        if progress.waitingFor == permission {
                            Label("Allow access in System Settings, then return here. Saywing checks automatically.",
                                  systemImage: "arrow.up.forward.app")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if permission == .screenRecording || permission == .inputMonitoring {
                            Text("If macOS asks you to quit and reopen Saywing, you will continue here afterward.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if permission == .inputMonitoring {
                            Button("Skip for Now") { progress.skipOptionalPermission() }
                            Text("Without Input Monitoring, Escape stops reading only while Saywing is in front. The stop button always works.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if progress.step.stage == 1 {
                        if progress.step.isDictation, let dictation = model.dictation {
                            DictationModelSelection(controller: dictation)
                        } else if progress.step.isDictation {
                            Text("Dictation is not available in this build.")
                        } else {
                            Label("Supertonic 3 · M1", systemImage: "waveform")
                            Text("The reading voice is separate from the dictation model.")
                                .font(.callout).foregroundStyle(.secondary)
                            Text(LocalSpeechService.installationSummary)
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    } else if progress.step.stage == 2 {
                        ActivationShortcutsView(model: model)
                    } else if progress.step == .readingTest {
                        Text("Open some text in another app, then select a sentence. Press Escape while it reads.")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Select Screen Region") { model.beginSetupCapture() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!permissions.canTestReading || !model.canChangeShortcut)
                                .accessibilityIdentifier("setupReadingTest")
                            Text(model.shortcutConfiguration.displayName).foregroundStyle(.secondary)
                        }
                        if !permissions.isGranted(.inputMonitoring) {
                            Text("Without Input Monitoring, Escape stops reading only while Saywing is in front. The stop button always works.")
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Label(LocalSpeechService.installationSummary, systemImage: "waveform")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        if let dictation = model.dictation {
                            LabeledContent("Model", value: dictation.selectedModel.displayName)
                            Text(dictation.activationInstructions).fixedSize(horizontal: false, vertical: true)
                            if let pending = dictation.pendingInstallModel {
                                Text("Waiting for \(pending.displayName). You can return to Model to change your choice.")
                                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Button("Try Dictation…") { model.dictation?.showWindow() }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canTryDictation)
                            .accessibilityIdentifier("setupDictationTest")
                    }

                    if progress.step.stage == 3 && (progress.step.isDictation
                        ? permissions.isGranted(.microphone) && permissions.isGranted(.accessibility)
                        : permissions.canTestReading) {
                        Label("Access is allowed. Use the test to check that everything works.", systemImage: "checkmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if progress.offersRestartHelp || model.errorMessage != nil {
                        DisclosureGroup("Already allowed access, but it still does not work?", isExpanded: $restartHelpExpanded) {
                              VStack(alignment: .leading, spacing: 10) {
                                Text("macOS may need Saywing to restart before new access takes effect. You will continue at this step.")
                                    .font(.callout).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Restart and Continue") { model.restartSetup() }
                                    .disabled(!model.canRestartSetup || model.isRestartingSetup)
                                    .accessibilityIdentifier("setupRestart")
                                if !model.canRestartSetup {
                                    Text("Finish or stop the current activity before restarting.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                            }.padding(.top, 6)
                        }
                    }
                    if let error = model.setupRestartError ?? model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if progress.step.stage != 1, let dictation = model.dictation, let pending = dictation.pendingInstallModel {
                        VStack(alignment: .leading, spacing: 6) {
                            DictationInstallStatus(controller: dictation, model: pending)
                            Button("Show Model") { progress.continueToDictation(granted: permissions.granted); progress.visit(stage: 1) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
            Divider()
            HStack {
                Button("Later") { model.deferSetup() }
                    .accessibilityIdentifier("setupLater")
                if progress.step.permission != nil {
                    Button("Check Again") {
                        permissions.refresh()
                        model.dictation?.refreshPermissions()
                    }
                }
                Spacer()
                if progress.step.stage > 0 {
                    Button("Back") { progress.back() }.accessibilityIdentifier("setupBack")
                }
                if progress.step.stage == 1 || progress.step.stage == 2 {
                    Button("Continue") { progress.advance(granted: permissions.granted) }
                        .keyboardShortcut(.defaultAction).accessibilityIdentifier("setupContinue")
                } else if let permission = progress.step.permission, permissions.isGranted(permission) {
                    Button("Continue") { progress.refresh(granted: permissions.granted) }
                        .keyboardShortcut(.defaultAction)
                } else if progress.step == .readingTest {
                    Button("Finish Setup") { model.finishSetup() }
                    Button("Set Up Dictation") { progress.continueToDictation(granted: permissions.granted) }
                        .keyboardShortcut(.defaultAction)
                } else if progress.step == .dictationTest {
                    Button("Finish Setup") { model.finishSetup() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: Self.windowHeight)
        .onReceive(permissions.$granted) { granted in
            progress.refresh(granted: granted)
            model.dictation?.refreshPermissions()
        }
        .onChange(of: progress.step) { _, _ in
            restartHelpExpanded = false
            model.setRecordingShortcut(false)
        }
    }
    private var canTryDictation: Bool {
        guard let dictation = model.dictation else { return false }
        return permissions.canTestDictation && permissions.isGranted(.accessibility)
            && dictation.pendingInstallModel == nil && dictation.models.isInstalled(dictation.selectedModel)
            && model.canChangeShortcut
    }
    private func stageTitle(_ index: Int) -> String {
        switch index {
        case 0: String(localized: "Permissions")
        case 1: String(localized: "Model")
        case 2: String(localized: "Shortcuts")
        default: String(localized: "Try It")
        }
    }
}
