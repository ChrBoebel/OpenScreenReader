import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var permissionNotice: String?
    @State private var draftShortcut = ShortcutConfiguration.default
    @State private var confirmCommonShortcut = false
    @State private var editingQueueShortcut = false
    @AppStorage(InterfaceSoundPlayer.preferenceKey, store: InterfaceSoundPlayer.defaults)
    private var interfaceSoundsEnabled = true
    @AppStorage(InterfaceSoundPlayer.volumeKey, store: InterfaceSoundPlayer.defaults)
    private var interfaceSoundsVolume = InterfaceSoundPlayer.defaultVolume
    @AppStorage(ReadingPanelPlacement.edgeKey, store: InterfaceSoundPlayer.defaults)
    private var readingPanelEdge = ReadingPanelEdge.bottom.rawValue

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityLabel("Saywing Quiet Owl app logo")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Saywing").font(.title2.weight(.semibold))
                        Text("Vorlesen & Diktieren für macOS.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Text und Stimme") {
                Label("Vorlesen", systemImage: "speaker.wave.2")
                    .font(.headline)
                Text("Bildschirmbereich wählen. Zuhören.")
                Label("Diktieren", systemImage: "mic")
                    .font(.headline)
                Text("Deutsch und Englisch lokal diktieren. Fn halten zum Diktieren, loslassen zum Einfügen. Fn doppelt oder Fn + Leertaste startet freihändig; Fn beendet, Esc verwirft. ⌥⇧Leertaste bleibt als Alternative. Beim Einfügen wird die Zwischenablage kurz benutzt und danach wiederhergestellt.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Diktieren") {
                Button("Diktieren einrichten & testen…") { model.dictation?.showWindow() }
                    .disabled(model.dictation == nil)
                Text("Mikrofon für die Aufnahme; Bedienungshilfen zum Einfügen in andere Apps. Freigaben werden nur auf deinen Klick angefragt. Vorlesen stoppt vor einer Aufnahme.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("General") {
                Button("Set Up & Test…") { model.showSetup() }
                Picker("Reading speed", selection: Binding(get: { model.playbackRate }, set: { model.setPlaybackRate($0) })) {
                    ForEach(SpeechSpeed.presets, id: \.self) { speed in Text(SpeechSpeed.label(speed)).tag(speed) }
                }
                .accessibilityIdentifier("readingSpeed")
                Text("Changes immediately, including during playback. Pitch stays unchanged. Also available in the menu bar under Speed.")
                    .font(.caption).foregroundStyle(.secondary)
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
                Text("Drag the waveform to dock the control at the left, right or bottom edge of the selected screen. Its position is remembered. The stop button stays separate.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Preview & move control") { model.previewReadingPanelPosition() }
                    .disabled(!model.canChangeShortcut)
                    .accessibilityIdentifier("previewReadingPanelPosition")
                Toggle("Interface sounds", isOn: $interfaceSoundsEnabled)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("interfaceSoundsEnabled")
                Slider(value: $interfaceSoundsVolume, in: 0...1) { Text("Effect volume") }
                    .disabled(!interfaceSoundsEnabled)
                    .accessibilityIdentifier("interfaceSoundsVolume")
                Text("Opening, completion, attention and stop-button cues from one original stereo sound family. No sounds over speech or on cancellation. Reduce Motion follows macOS settings.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Status", value: model.status.title)
                LabeledContent("Global shortcut", value: model.shortcutConfiguration.displayName)
                    .accessibilityIdentifier("activeShortcut")
                LabeledContent("Speech model", value: SpeechRuntimeConfiguration(root: LocalSpeechService.developmentRoot).modelName)
                LabeledContent("Voice", value: "Machine-generated · M1 · \(SpeechSpeed.label(model.playbackRate))")
                LabeledContent("Model license", value: "BigScience Open RAIL-M")
                LabeledContent("Speech runtime", value: LocalSpeechService.installationSummary)
                Text("Experimental local runtime. The model stays loaded through the queue and prepares the next text while audio plays. Stop releases it. Not a packaged release.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Keyboard shortcut") {
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
                Text("Choose A–Z, 0–9, or Space with Command, Option, or Control; Shift is optional. Escape always cancels. Changes are saved locally.")
                    .font(.caption)
                Text("Shortcuts can override commands in other apps. Not all conflicts can be detected. Default: ⌥R (Option + R) reads a screen region; press again to add another region.")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.canChangeShortcut {
                    Text("Stop the current operation before changing its shortcut.")
                }
                if let notice = model.shortcutNotice {
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("shortcutNotice")
                }
                LabeledContent("Add to queue", value: model.queueShortcutConfiguration.displayName)
                Text("Press your reading shortcut again to select another region while speech continues. No second shortcut is needed. Up to five waiting texts stay in memory only. Escape or Stop Reading ends everything and empties the queue. Use Next Text in the menu to skip. The additional queue shortcut is optional.")
                    .font(.caption).foregroundStyle(.secondary)
                if let notice = model.queueShortcutNotice { Text(notice).font(.caption) }
            }
            .disabled(!model.canChangeShortcut)

            Section("Privacy") {
                Text("Apple Vision recognizes the selected region locally; Supertonic reads the text on this Mac. Images, text, and audio are not saved. Only character and line counts remain after reading. Reading leaves the clipboard unchanged. Explicit dictation uses the selected local model (Qwen3-ASR or Whisper Turbo) and temporarily pastes through the clipboard, restoring it unless a newer copy exists. Both workers are blocked from network access and file writes. No cloud or substitute voice is used.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Permissions") {
                Text("Screen Recording allows the selected region to be captured. Input Monitoring lets Escape cancel while another app is active; only Escape is checked, and monitoring stops when the operation ends.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Screen Recording…") {
                    let granted = CGRequestScreenCaptureAccess()
                    permissionNotice = granted ? "Screen Recording is allowed. Select a region to retry."
                        : "Enable Saywing under System Settings → Privacy & Security → Screen & System Audio Recording, then reopen the app if requested."
                }
                Button("Allow Input Monitoring…") {
                    let granted = CGRequestListenEventAccess()
                    permissionNotice = granted ? "Input Monitoring is allowed. Select a region to retry."
                        : "Enable Saywing under System Settings → Privacy & Security → Input Monitoring, then reopen the app if requested."
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
        .navigationTitle("Saywing Settings")
        .accessibilityLabel("Saywing settings")
        .onAppear { draftShortcut = editingQueueShortcut ? model.queueShortcutConfiguration : model.shortcutConfiguration }
        .alert("Override app commands?", isPresented: $confirmCommonShortcut) {
            Button("Use Shortcut") { applyDraftShortcut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(draftShortcut.displayName) may replace a familiar command in other apps while Saywing is running. Use it anyway?")
        }
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

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var screenAllowed = false
    @State private var inputAllowed = false
    @State private var notice = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saywing").font(.title2.bold())
                    Text("Vorlesen & Diktieren für macOS.").font(.subheadline)
                }
            }
            Text("Vorlesen einrichten").font(.headline)
            Text("Diktieren ist in Erprobung und in dieser App noch nicht verfügbar.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Zwei Berechtigungen, dann ein echter Vorlesetest. Kein Konto und kein Cloud-Dienst.")
                .foregroundStyle(.secondary)
            permissionRow("1 · Bildschirmaufnahme", allowed: screenAllowed,
                          explanation: "Nur der von dir markierte Bereich wird für die lokale Texterkennung erfasst.") {
                _ = CGRequestScreenCaptureAccess()
                refresh()
                notice = "Aktiviere Saywing in Datenschutz & Sicherheit → Aufnahme von Bildschirm & Systemaudio. Öffne die App danach erneut, falls macOS dazu auffordert."
            }
            permissionRow("2 · Eingabeüberwachung", allowed: inputAllowed,
                          explanation: "Damit Esc auch in anderen Apps sofort stoppt. Keine Tastatureingaben werden gespeichert.") {
                _ = CGRequestListenEventAccess()
                refresh()
                notice = "Aktiviere Saywing in Datenschutz & Sicherheit → Eingabeüberwachung. Verwende die App unter /Applications/Saywing.app, nicht den UI-Tests-Runner."
            }
            Label(LocalSpeechService.installationSummary, systemImage: "waveform")
            Button("Status erneut prüfen") { refresh() }
            Divider()
            Text("3 · Im Alltag testen").font(.headline)
            Text("Öffne einen Text in einer anderen App. Starte die Auswahl, markiere einen Satz und drücke beim Vorlesen Esc. Die Freigaben oben sind Systemprüfungen; erst dieser Test bestätigt den vollständigen Ablauf.")
                .font(.callout)
            Button("Bildschirmbereich auswählen") {
                model.beginSetupCapture()
            }.disabled(!screenAllowed || !inputAllowed || !model.canChangeShortcut)
                .buttonStyle(.borderedProminent)
            if !notice.isEmpty { Text(notice).font(.caption).foregroundStyle(.secondary) }
            if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text(model.isPaused ? "Pausiert" : model.status.title).font(.caption)
                Spacer()
                Button("Einrichtung schließen") { model.finishSetup() }
            }
        }
        .padding(24).frame(width: 480)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        screenAllowed = CGPreflightScreenCaptureAccess()
        inputAllowed = CGPreflightListenEventAccess()
    }
    private func permissionRow(_ title: String, allowed: Bool, explanation: String, request: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title + (allowed ? " · freigegeben" : " · fehlt"), systemImage: allowed ? "checkmark.circle.fill" : "circle")
                .font(.headline)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
            if !allowed { Button("Freigabe anfragen…", action: request) }
        }
    }
}
