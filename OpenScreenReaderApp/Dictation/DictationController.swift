import AVFoundation
import AppKit
import Carbon
import Combine

@MainActor
final class DictationStatusPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
  override func orderOut(_ sender: Any?) {
    (contentView as? DictationCapsuleView)?.stopAnimating()
    super.orderOut(sender)
  }
}
@MainActor
final class DictationController: NSObject, ObservableObject {
  @Published private(set) var statusText = "Diktieren bereit"
  var onActivation: ((@escaping @MainActor () -> Void) -> Void)?
  var isActive: Bool { request != nil || activationID != nil }
  private var activationID: UUID?
  private var modelGeneration = UUID()
  private(set) var selectedModel: DictationModel
  private let shortcut: any HotkeyManaging
  private let escape: any HotkeyManaging
  private let preferences: UserDefaults
  private let fnShortcuts = FnDictationShortcuts()
  private let monitorFn: Bool
  private var pendingAudio: AudioPacket?
  private var isShutDown = false
  private var isSleeping = false
  private var isSessionInactive = false
  private var canPrepareModel: Bool { !isShutDown && !isSleeping && !isSessionInactive }

  let resources: URL
  let worker: any DictationTranscribing
  let gate = GenerationGate()
  var window: NSWindow!, scratch = NSTextView(), result = NSTextView()
  var titleLabel = NSTextField(labelWithString: "Modell wird vorbereitet …")
  var detailLabel = NSTextField(wrappingLabelWithString: "")
  var permissionLabel = NSTextField(wrappingLabelWithString: "")
  var language = NSPopUpButton(), pasteDelay = NSPopUpButton(), modelPicker = NSPopUpButton()
  var startButton: NSButton!, cancelButton: NSButton!, demoDE: NSButton!, demoEN: NSButton!
  var panel: DictationStatusPanel!
  let capsule = DictationCapsuleView(frame: CGRect(origin: .zero, size: DictationCapsuleView.surface))
  private var panelGeneration = UUID()
  var record: MicrophoneRecorder?, target: InsertionTarget?, request: UUID?
  var phase = "loading", latestText = ""
  var recordingTimer: Timer?, recordingStart = Date()
  var timeout: DispatchWorkItem?, panelHide: DispatchWorkItem?,
    restore: DispatchWorkItem?
  var lease: ClipboardLease?
  var shortcutAvailable = true
  var localEscape: Any?
  var smoke = false, smokeIndex = 0, smokeFailures = [String]()
  var smokeClipboard: ClipboardSnapshot?

  init(
    resources: URL? = nil, worker: any DictationTranscribing = DictationWorker(),
    shortcut: any HotkeyManaging = GlobalHotkeyManager(),
    escape: any HotkeyManaging = GlobalHotkeyManager(),
    preferences: UserDefaults = .standard, registerHotkey: Bool = true
  ) {
    self.resources = resources ?? Bundle.main.resourceURL!.appendingPathComponent("Dictation")
    self.worker = worker
    self.shortcut = shortcut
    self.escape = escape
    self.preferences = preferences
    self.selectedModel = DictationModel(rawValue: preferences.string(forKey: "dictationModel.v1") ?? "") ?? .qwen
    self.monitorFn = registerHotkey
    super.init()
    buildWindow()
    buildPanel()
    language.selectItem(at: max(0, min(2, preferences.integer(forKey: "dictationLanguage.v1"))))
    pasteDelay.selectItem(at: preferences.bool(forKey: "dictationSlowPaste.v1") ? 1 : 0)
    language.target = self
    language.action = #selector(savePreferences)
    pasteDelay.target = self
    pasteDelay.action = #selector(savePreferences)
    modelPicker.target = self
    modelPicker.action = #selector(changeModel)
    shortcut.onPress = { [weak self] in self?.toggle() }
    fnShortcuts.onAction = { [weak self] action in
      guard let self else { return false }
      switch action {
      case .start:
        guard !self.isActive, ["ready", "loading", "unloaded"].contains(self.phase) else { return false }
        self.toggle()
        return self.isActive
      case .lock:
        guard self.isActive else { return false }
        if self.phase == "recording" {
          self.detailLabel.stringValue = "Freihändig aufnehmen. Fn oder Fn + Leertaste beendet; Esc verwirft."
        }
      case .finish:
        if self.phase == "recording" { self.finishRecording() }
        else if self.isActive { self.cancel() }
      case .cancel: self.cancel()
      }
      return true
    }
    if registerHotkey {
      shortcutAvailable =
        shortcut.register(ShortcutConfiguration.dictationDefault.resolvedShortcut()) == .registered
    }
    localEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let isEscape = event.keyCode == 53
      let handled = MainActor.assumeIsolated {
        if isEscape, self?.isActive == true {
          self?.cancel()
          return true
        }
        return false
      }
      return handled ? nil : event
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(refreshPermissions),
      name: NSApplication.didBecomeActiveNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(screenLockedOrSleeping), name: NSWorkspace.willSleepNotification,
      object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(screenLockedOrSleeping),
      name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
      NSWorkspace.shared.notificationCenter.addObserver(
        self, selector: #selector(screenBecameAvailable), name: name, object: nil)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(terminate), name: NSApplication.willTerminateNotification,
      object: nil)
    phase = "unloaded"
    setStatus(
      "Bereit zum Diktieren", "Fn halten zum Diktieren; Fn doppelt für freihändig. Das Modell lädt automatisch."
    )
    refreshPermissions()
  }
  @objc func savePreferences() {
    preferences.set(language.indexOfSelectedItem, forKey: "dictationLanguage.v1")
    preferences.set(pasteDelay.indexOfSelectedItem == 1, forKey: "dictationSlowPaste.v1")
  }
  @objc func terminate() { shutdown() }
  func shutdown() {
    isShutDown = true
    modelGeneration = UUID()
    fnShortcuts.stop()
    cancel(restart: false)
    worker.stop()
    shortcut.unregister()
    escape.unregister()
    if let localEscape { NSEvent.removeMonitor(localEscape) }
    localEscape = nil
    panelHide?.cancel()
    panel?.orderOut(nil)
  }
  func cancelForReading() {
    if isActive { cancel(restart: false) }
    // Idle or warming ASR can stay available while TTS reads. Active inference
    // is still stopped synchronously by cancel above.
    phase = worker.ready ? "ready" : worker.running ? "loading" : "unloaded"
    setStatus(
      "Bereit zum Diktieren",
      "Fn startet die nächste Aufnahme und beendet vorher das Vorlesen.")
    panel?.orderOut(nil)
  }
  @objc func screenLockedOrSleeping(_ note: Notification) {
    // Switching apps while recording is allowed; insertion still validates the original target.
    if note.name == NSWorkspace.willSleepNotification
      || note.name == NSWorkspace.sessionDidResignActiveNotification
    {
      fnShortcuts.stop()
      if note.name == NSWorkspace.willSleepNotification { isSleeping = true }
      if note.name == NSWorkspace.sessionDidResignActiveNotification { isSessionInactive = true }
      cancel(restart: false)
      worker.stop()
      phase = "unloaded"
      setStatus("Diktieren pausiert", "Das Modell wird beim Zurückkehren automatisch vorbereitet.")
    }
  }
  @objc func screenBecameAvailable(_ note: Notification) {
    if note.name == NSWorkspace.didWakeNotification { isSleeping = false }
    if note.name == NSWorkspace.sessionDidBecomeActiveNotification { isSessionInactive = false }
    loadModel()
    refreshPermissions()
  }
  func label(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
    let v = NSTextField(wrappingLabelWithString: text)
    v.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    return v
  }
  func button(_ title: String, _ action: Selector) -> NSButton {
    let b = NSButton(title: title, target: self, action: action)
    b.bezelStyle = .rounded
    return b
  }
  func row(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.spacing = 8
    return s
  }
  func textArea(_ view: NSTextView, height: CGFloat, editable: Bool) -> NSScrollView {
    view.isEditable = editable
    view.isSelectable = true
    view.isRichText = false
    view.font = .systemFont(ofSize: 15)
    view.textContainerInset = NSSize(width: 10, height: 10)
    view.isAutomaticQuoteSubstitutionEnabled = false
    view.isAutomaticDashSubstitutionEnabled = false
    view.isAutomaticTextReplacementEnabled = false
    view.isAutomaticSpellingCorrectionEnabled = false
    view.isHorizontallyResizable = false
    view.isVerticallyResizable = true
    view.textContainer?.widthTracksTextView = true
    let scroll = NSScrollView()
    scroll.borderType = .bezelBorder
    scroll.hasVerticalScroller = true
    scroll.documentView = view
    view.frame = NSRect(x: 0, y: 0, width: 570, height: height)
    scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    return scroll
  }
  func buildWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 680, height: 740),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "Saywing · Diktieren"
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    window.center()
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 11
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(
        lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -18),
    ])
    stack.addArrangedSubview(label("Mit der Stimme schreiben.", size: 25, bold: true))
    stack.addArrangedSubview(label("Deutsch & English · Lokal auf deinem Mac", size: 13))
    stack.addArrangedSubview(
      label(
        "Fn halten: diktieren. Loslassen: einfügen. Fn doppelt oder Fn + Leertaste: freihändig.\nFn erneut: beenden. Esc: verwerfen. Ohne Fn: ⌥⇧Leertaste startet / beendet.\nZuerst ins gewünschte Textfeld klicken. Wispr Flow und andere Fn-Diktier-Apps beenden."
      ))
    titleLabel.font = .boldSystemFont(ofSize: 17)
    stack.addArrangedSubview(titleLabel)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.maximumNumberOfLines = 3
    stack.addArrangedSubview(detailLabel)
    language.addItems(withTitles: ["Automatisch (DE / EN)", "Deutsch", "English"])
    pasteDelay.addItems(withTitles: ["Zwischenablage: 1 s", "Zwischenablage: 2 s"])
    language.setAccessibilityLabel("Erkennungssprache")
    modelPicker.addItems(withTitles: DictationModel.allCases.map(\.displayName))
    modelPicker.selectItem(withTitle: selectedModel.displayName)
    modelPicker.setAccessibilityLabel("Diktiermodell")
    pasteDelay.setAccessibilityLabel("Zeit bis zur Wiederherstellung der Zwischenablage")
    stack.addArrangedSubview(
      row([modelPicker, language, pasteDelay]))
    permissionLabel.font = .systemFont(ofSize: 11)
    stack.addArrangedSubview(permissionLabel)
    stack.addArrangedSubview(
      row([
        button("Mikrofon freigeben", #selector(requestMic)),
        button("Bedienungshilfen …", #selector(requestAX)),
      ]))
    stack.addArrangedSubview(label("Testfeld", size: 14, bold: true))
    scratch.setAccessibilityLabel("Diktier-Testfeld")
    let scratchScroll = textArea(scratch, height: 130, editable: true)
    stack.addArrangedSubview(scratchScroll)
    scratchScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    startButton = button("Aufnahme im Testfeld", #selector(startInScratch))
    cancelButton = button("Verwerfen · Esc", #selector(cancelAction))
    demoDE = button("Demo Deutsch", #selector(demoGerman))
    demoEN = button("Demo English", #selector(demoEnglish))
    stack.addArrangedSubview(row([startButton, cancelButton, demoDE, demoEN]))
    stack.addArrangedSubview(
      label("Letztes Ergebnis · nur bis zum Verwerfen oder Beenden", size: 12, bold: true))
    let resultScroll = textArea(result, height: 92, editable: false)
    result.setAccessibilityLabel("Letztes Diktierergebnis")
    stack.addArrangedSubview(resultScroll)
    resultScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.addArrangedSubview(
      row([
        button("Ergebnis kopieren", #selector(copyResult)),
        button("Felder leeren", #selector(clearFields)),
      ]))
    let footer = label(
      "Audio und Text bleiben im Arbeitsspeicher. Beim Einfügen wird die Zwischenablage kurz benutzt und danach wiederhergestellt. Eine neue Kopie von dir hat Vorrang. Maximal 60 Sekunden pro Aufnahme.",
      size: 11)
    footer.textColor = .secondaryLabelColor
    stack.addArrangedSubview(footer)
    refreshPermissions()
  }
  func buildPanel() {
    panel = DictationStatusPanel(
      contentRect: CGRect(origin: .zero, size: DictationCapsuleView.surface),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.contentView = capsule
    capsule.onFinish = { [weak self] in self?.finishRecording() }
    capsule.onDismiss = { [weak self] in
      guard let self else { return }
      if self.isActive { self.cancel() } else { self.panel.orderOut(nil) }
    }
    capsule.onDetails = { [weak self] in self?.showWindow() }
  }
  func setStatus(_ title: String, _ detail: String = "", floating: Bool = false,
                 capsuleState: DictationCapsuleState? = nil) {
    titleLabel.stringValue = title
    detailLabel.stringValue = detail
    let presentation = capsuleState ?? (phase == "recording" ? .recording
      : phase == "processing" ? .processing : phase == "pasting" ? .pasting
      : floating ? .attention : .idle)
    capsule.present(presentation, title: title, detail: detail)
    startButton?.title = phase == "recording" ? "Beenden & einfügen" : "Aufnahme im Testfeld"
    let busy = ["recording", "processing", "pasting"].contains(phase)
    modelPicker.isEnabled = !isActive
    startButton?.isEnabled = ["ready", "unloaded", "loading", "recording"].contains(phase)
    demoDE?.isEnabled = worker.ready && phase == "ready"
    demoEN?.isEnabled = demoDE?.isEnabled ?? false
    cancelButton?.isEnabled = busy
    statusText = title
    if floating {
      panelHide?.cancel()
      panelGeneration = UUID()
      guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
      panel.setFrameOrigin(
        NSPoint(x: screen.visibleFrame.midX - DictationCapsuleView.surface.width / 2, y: screen.visibleFrame.minY + 8))
      panel.orderFrontRegardless()
      capsule.show()
    }
  }
  func hidePanelLater() {
    // Repeated shortcuts must not dismiss an active recording/recognition.
    guard !isActive else { return }
    panelHide?.cancel()
    let generation = panelGeneration
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.panelGeneration == generation, !self.isActive else { return }
      self.panel.orderOut(nil)
    }
    panelHide = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
  }
  @objc func showWindow() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeFirstResponder(scratch)
    refreshPermissions()
    if !worker.running && request == nil { loadModel() }
  }
  func loadModel() {
    guard canPrepareModel, request == nil, !worker.running else { return }
    phase = "loading"
    setStatus(
      "Diktieren wird vorbereitet …",
      "\(selectedModel.displayName) lädt automatisch und bleibt bereit, solange Saywing geöffnet ist.")
    startWorker()
  }
  private func startWorker() {
    let generation = UUID()
    modelGeneration = generation
    worker.onMessage = { [weak self] message in
      guard let self, self.modelGeneration == generation else { return }
      self.receive(message)
    }
    worker.start(resources: resources, model: selectedModel)
  }
  @objc func changeModel() {
    guard let choice = DictationModel.allCases.first(where: { $0.displayName == modelPicker.titleOfSelectedItem }) else { return }
    selectModel(choice)
  }
  func selectModel(_ model: DictationModel) {
    guard !isActive, canPrepareModel else {
      modelPicker.selectItem(withTitle: selectedModel.displayName)
      return
    }
    guard model != selectedModel else { return }
    modelGeneration = UUID()
    cancel(restart: false)
    worker.stop()
    selectedModel = model
    preferences.set(model.rawValue, forKey: "dictationModel.v1")
    modelPicker.selectItem(withTitle: model.displayName)
    phase = "unloaded"
    loadModel()
  }
  @objc func requestMic() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
        DispatchQueue.main.async { self?.refreshPermissions() }
      }
    case .denied, .restricted:
      NSWorkspace.shared.open(
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    default: refreshPermissions()
    }
  }
  @objc func requestAX() {
    let options =
      ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    refreshPermissions()
  }
  @objc func refreshPermissions() {
    if monitorFn && canPrepareModel { fnShortcuts.start() }
    permissionLabel.stringValue =
      "Mikrofon: \(AVCaptureDevice.authorizationStatus(for:.audio) == .authorized ? "freigegeben":"noch nicht freigegeben") · Andere Apps: \(AXIsProcessTrusted() ? "freigegeben":"Bedienungshilfen erforderlich")"
      + (monitorFn && !fnShortcuts.isAvailable ? " · Fn nicht aktiv; ⌥⇧Leertaste verwenden." : "")
      + (shortcutAvailable ? "" : " · Hotkey belegt; bitte Testfeld-Taste verwenden.")
  }
  func armEscape() throws {
    escape.onPress = { [weak self] in self?.cancel() }
    guard
      escape.register(HotkeyShortcut(keyCode: 53, carbonModifiers: 0, displayName: "Escape"))
        == .registered
    else {
      throw DictationError(
        "Escape ist belegt. Aufnahme wurde nicht gestartet; bitte die andere Diktier-App beenden.")
    }
  }
  func disarmEscape() { escape.unregister() }
  @objc func startInScratch() {
    if phase == "recording" {
      finishRecording()
      return
    }
    showWindow()
    toggle(internalTarget: InsertionTarget(local: scratch))
  }
  func toggle(internalTarget: InsertionTarget? = nil) {
    guard canPrepareModel else { return }
    if phase == "recording" {
      finishRecording()
      return
    }
    guard ["ready", "unloaded", "loading"].contains(phase), activationID == nil else {
      setStatus(
        phase == "processing" ? "Text wird erkannt …" : "Modell noch nicht bereit",
        phase == "processing"
          ? "Esc verwirft diesen Auftrag." : "Der aktuelle Vorgang läuft noch. Esc verwirft ihn.",
        floating: true)
      hidePanelLater()
      return
    }
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      setStatus(
        "Mikrofon freigeben",
        "Im Diktierfenster auf „Mikrofon freigeben“ klicken und danach die Aufnahme erneut starten.",
        floating: true)
      hidePanelLater()
      return
    }
    do {
      let target = try internalTarget ?? InsertionTarget.capture(scratch: scratch)
      let id = UUID()
      activationID = id
      let start: @MainActor () -> Void = { [weak self] in
        guard let self, self.activationID == id else { return }
        self.activationID = nil
        self.startRecording(target: target)
      }
      if let onActivation { onActivation(start) } else { start() }

    } catch {
      cancel(restart: false)
      phase = worker.ready ? "ready" : "unloaded"
      setStatus("Aufnahme nicht gestartet", error.localizedDescription, floating: true)
      hidePanelLater()
    }
  }
  func startRecording(target: InsertionTarget) {
    guard canPrepareModel else { return }
    do {
      try begin(target: target)
      if !worker.running { startWorker() }
      guard request != nil else { return }
      let recorder = MicrophoneRecorder()
      record = recorder
      try recorder.start()
      phase = "recording"
      recordingStart = Date()
      setStatus(
        "Aufnahme · 0 s", "Ziel: \(target.name). Fn loslassen oder freihändig mit Fn + Leertaste beenden.", floating: true)
      let id = request
      recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.request == id, self.phase == "recording" else { return }
          let elapsed = Date().timeIntervalSince(self.recordingStart)
          self.capsule.updateRecording(rms: self.record?.audio.rms ?? 0)
          self.titleLabel.stringValue = "Aufnahme · \(Int(elapsed)) / 60 s"
          if elapsed >= 60 { self.finishRecording() }
        }
      }
    } catch {
      cancel(restart: false)
      setStatus("Aufnahme nicht gestartet", error.localizedDescription, floating: true)
      hidePanelLater()
    }
  }
  func begin(target: InsertionTarget) throws {
    try armEscape()
    latestText = ""
    result.string = ""
    request = gate.begin()
    self.target = target
  }
  func finishRecording() {
    guard phase == "recording", let record else { return }
    fnShortcuts.resetGesture()
    recordingTimer?.invalidate()
    recordingTimer = nil
    let audio = record.finish()
    self.record = nil
    send(audio)
  }
  func send(_ audio: AudioPacket) {
    guard let id = request else { return }
    phase = "processing"
    setStatus(
      "Text wird erkannt …", "Alles wird lokal verarbeitet. Esc verwirft den Auftrag.",
      floating: true)
    let lang =
      language.indexOfSelectedItem == 1
      ? "German" : language.indexOfSelectedItem == 2 ? "English" : nil
    if worker.ready {
      worker.transcribe(audio, id: id, language: lang)
    } else {
      pendingAudio = audio
    }
    timeout?.cancel()
    let timer = DispatchWorkItem { [weak self] in
      guard let self, self.gate.accepts(id) else { return }
      self.cancel()
      self.setStatus(
        "Zeitlimit erreicht", "Der Auftrag wurde verworfen. Du kannst ein neues Diktat starten.",
        floating: true)
    }
    timeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: timer)
  }
  func receive(_ message: DictationWorkerMessage) {
    guard canPrepareModel else { return }
    switch message.type {
    case "ready":
      if phase == "recording" { return }
      if let audio = pendingAudio, request != nil {
        pendingAudio = nil
        send(audio)
        return
      }
      phase = "ready"
      setStatus(
        "Bereit", "In ein Textfeld klicken und Fn halten – oder hier das Testfeld nutzen."
      )
      if smoke { runSmoke() }
    case "fatal":
      let detail = message.message ?? "Lokaler Sprachprozess nicht verfügbar."
      cancel(restart: false)
      worker.stop()
      phase = "unloaded"
      setStatus("Modell nicht verfügbar", detail, floating: true)
      if smoke { finishSmoke(error: detail) }
    case "result", "error":
      guard let raw = message.id, let id = UUID(uuidString: raw), gate.accepts(id),
        phase == "processing"
      else { return }
      timeout?.cancel()
      timeout = nil
      if message.type == "error" {
        complete()
        setStatus(
          "Erkennung fehlgeschlagen", message.message ?? "Bitte erneut versuchen.", floating: true)
        if smoke { finishSmoke(error: "worker error") }
        return
      }
      let text = message.text ?? ""
      latestText = text
      result.string = text
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        complete()
        setStatus("Keine Sprache erkannt", "Es wurde nichts eingefügt.", floating: true)
        hidePanelLater()
        if smoke { finishSmoke(error: "empty transcription") }
        return
      }
      insert(text, id: id)
    default: break
    }
  }
  func insert(_ text: String, id: UUID) {
    guard gate.accepts(id), let target, target.isCurrent() else {
      complete()
      setStatus(
        "Ziel hat sich geändert",
        "Das Ergebnis steht im Diktierfenster. Es wurde nichts automatisch eingefügt.",
        floating: true)
      hidePanelLater()
      if smoke { finishSmoke(error: "target changed") }
      return
    }
    do {
      let transaction = try ClipboardLease.begin(text, on: .general)
      lease = transaction
      // Recheck after taking the clipboard snapshot, before the single paste action.
      try target.paste()
      phase = "pasting"
      setStatus(
        "Einfügen ausgelöst", "Die Zwischenablage wird gleich wiederhergestellt.", floating: true)
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.gate.accepts(id) else { return }
        let confirmed = target.confirms(text)
        _ = transaction.restore()
        self.lease = nil
        self.restore = nil
        self.complete()
        self.setStatus(
          confirmed ? "Eingefügt" : "Einfügen ausgelöst",
          confirmed
            ? "Bereit für die nächste Aufnahme."
            : "Bitte das Zielfeld prüfen. Keine automatische Wiederholung; das Ergebnis bleibt im Diktierfenster.",
          floating: true, capsuleState: confirmed ? .inserted : .unconfirmed)
        self.hidePanelLater()
        if self.smoke {
          if !confirmed { self.smokeFailures.append("paste not confirmed") }
          self.smokeIndex += 1
          self.runSmoke()
        }
      }
      restore = work
      DispatchQueue.main.asyncAfter(
        deadline: .now() + (pasteDelay.indexOfSelectedItem == 0 ? 1.0 : 2.0), execute: work)
    } catch {
      _ = lease?.restore()
      lease = nil
      complete()
      setStatus("Nicht eingefügt", error.localizedDescription, floating: true)
      hidePanelLater()
      if smoke { finishSmoke(error: error.localizedDescription) }
    }
  }
  func complete() {
    fnShortcuts.resetGesture()
    gate.cancel()
    request = nil
    target = nil
    disarmEscape()
    phase = worker.ready ? "ready" : "unloaded"
  }
  @objc func cancelAction() { cancel() }
  func cancel(restart: Bool = true) {
    fnShortcuts.resetGesture()
    let wasProcessing = phase == "processing"
    activationID = nil
    pendingAudio = nil
    gate.cancel()
    request = nil
    target = nil
    timeout?.cancel()
    timeout = nil
    recordingTimer?.invalidate()
    recordingTimer = nil
    record?.cancel()
    record = nil
    restore?.cancel()
    restore = nil
    _ = lease?.restore()
    lease = nil
    disarmEscape()
    latestText = ""
    result.string = ""
    if wasProcessing || !worker.ready { worker.stop() }
    phase = worker.ready ? "ready" : "unloaded"
    setStatus("Verworfen", "Die Aufnahme und das Ergebnis wurden verworfen.", floating: false)
    panel?.orderOut(nil)
    if restart { loadModel() }
  }
  @objc func copyResult() {
    guard !isActive, !latestText.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(latestText, forType: .string)
    setStatus(
      "Ergebnis kopiert", "Diese ausdrücklich angeforderte Kopie bleibt in der Zwischenablage.")
  }
  @objc func clearFields() {
    cancel()
    scratch.string = ""
    window.makeFirstResponder(scratch)
  }
  @objc func demoGerman() { demo("Deutsch") }
  @objc func demoEnglish() { demo("English") }
  func demo(_ name: String) {
    guard worker.ready, phase == "ready" else { return }
    showWindow()
    do {
      let file = try AVAudioFile(forReading: resources.appendingPathComponent("Demos/\(name).wav"))
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
      else { throw DictationError("Hörprobe konnte nicht gelesen werden.") }
      try file.read(into: buffer)
      guard let channels = buffer.floatChannelData else {
        throw DictationError("Ungültige Hörprobe.")
      }
      let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
      try begin(target: InsertionTarget(local: scratch))
      send(AudioPacket(samples: samples, rate: buffer.format.sampleRate))
    } catch {
      setStatus("Hörprobe nicht verfügbar", error.localizedDescription)
      if smoke { finishSmoke(error: "demo failed") }
    }
  }
  func startSmoke() {
    smoke = true
    showWindow()
    if worker.ready { runSmoke() }
  }
  func runSmoke() {
    guard smoke else { return }
    if smokeClipboard == nil { smokeClipboard = try? ClipboardSnapshot.capture(.general) }
    if smokeIndex < 2 {
      scratch.string = "Anfang MARKER ENDE"
      scratch.setSelectedRange((scratch.string as NSString).range(of: "MARKER"))
      demo(smokeIndex == 0 ? "Deutsch" : "English")
    } else {
      finishSmoke(error: nil)
    }
  }
  func finishSmoke(error: String?) {
    guard smoke else { return }
    smoke = false
    if let error { smokeFailures.append(error) }
    let unchanged = (try? ClipboardSnapshot.capture(.general)) == smokeClipboard
    let report: [String: Any] = [
      "demos_completed": smokeIndex, "clipboard_restored": unchanged, "failures": smokeFailures,
      "accessibility_trusted": AXIsProcessTrusted(), "shortcut_registered": shortcutAvailable,
      "microphone_permission": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
    ]
    // Explicit test-mode report contains booleans/status only, never clipboard or microphone content.
    if let data = try? JSONSerialization.data(
      withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    {
      try? data.write(
        to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(
          "dictation-smoke-result.json"))
    }
    smokeClipboard = nil
    setStatus(
      smokeFailures.isEmpty && unchanged
        ? "Beispieltests erfolgreich" : "Prüfung braucht Aufmerksamkeit",
      "Zwei öffentliche Hörproben testen Erkennung, Einfügen und Wiederherstellung. Dein Mikrofon wurde dabei nicht verwendet."
    )
  }
}
