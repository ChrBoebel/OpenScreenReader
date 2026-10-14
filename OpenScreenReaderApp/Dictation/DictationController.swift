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
  @Published private(set) var statusText = String(localized: "Ready to dictate")
  var onActivation: ((@escaping @MainActor () -> Void) -> Void)?
  var isActive: Bool { request != nil || activationID != nil }
  private var activationID: UUID?
  private var modelGeneration = UUID()
  @Published private(set) var selectedModel: DictationModel
  @Published private(set) var language: DictationLanguage
  /// Two seconds instead of one before the clipboard is restored, for slow target apps.
  @Published private(set) var restoresClipboardSlowly: Bool
  var canChangeModel: Bool { !isActive && canPrepareModel }
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
  var titleLabel = NSTextField(labelWithString: String(localized: "Preparing model…"))
  var detailLabel = NSTextField(wrappingLabelWithString: "")
  var permissionLabel = NSTextField(wrappingLabelWithString: "")
  var startButton: NSButton!, cancelButton: NSButton!, setupButton: NSButton!
  var demoDE: NSButton?, demoEN: NSButton?
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
    self.selectedModel = DictationModel(rawValue: preferences.string(forKey: "dictationModel.v1") ?? "") ?? .whisperTurbo
    self.language = DictationLanguage(rawValue: preferences.integer(forKey: "dictationLanguage.v1")) ?? .automatic
    self.restoresClipboardSlowly = preferences.bool(forKey: "dictationSlowPaste.v1")
    self.monitorFn = registerHotkey
    super.init()
    buildWindow()
    buildPanel()
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
          self.detailLabel.stringValue = String(localized: "Recording hands-free. Fn or Fn + Space finishes; Escape discards.")
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
      String(localized: "Ready to dictate"), String(localized: "Hold Fn to dictate, or press Fn twice for hands-free. The model loads automatically.")
    )
    refreshPermissions()
  }
  func setLanguage(_ value: DictationLanguage) {
    language = value
    preferences.set(value.rawValue, forKey: "dictationLanguage.v1")
  }
  func setRestoresClipboardSlowly(_ value: Bool) {
    restoresClipboardSlowly = value
    preferences.set(value, forKey: "dictationSlowPaste.v1")
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
      String(localized: "Ready to dictate"),
      String(localized: "Fn starts the next recording and stops reading first."))
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
      setStatus(String(localized: "Dictation paused"), String(localized: "The model is prepared again when you return."))
    }
  }
  @objc func screenBecameAvailable(_ note: Notification) {
    if note.name == NSWorkspace.didWakeNotification { isSleeping = false }
    if note.name == NSWorkspace.sessionDidBecomeActiveNotification { isSessionInactive = false }
    loadModel()
    refreshPermissions()
  }
  static let windowWidth: CGFloat = 560
  /// System text styles keep the hierarchy consistent with Settings and Setup.
  func label(_ text: String, style: NSFont.TextStyle = .body, secondary: Bool = false) -> NSTextField {
    let v = NSTextField(wrappingLabelWithString: text)
    v.font = .preferredFont(forTextStyle: style)
    v.preferredMaxLayoutWidth = Self.windowWidth - 48
    if secondary { v.textColor = .secondaryLabelColor }
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
    view.font = .preferredFont(forTextStyle: .body)
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
    view.frame = NSRect(x: 0, y: 0, width: Self.windowWidth - 48, height: height)
    scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
    return scroll
  }
  func buildWindow() {
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: 600),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = String(localized: "Try Dictation")
    window.isReleasedWhenClosed = false
    window.isRestorable = false
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    window.contentView!.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(
        lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20),
    ])
    stack.addArrangedSubview(label(String(localized: "Write with your voice"), style: .title1))
    stack.addArrangedSubview(
      label(String(localized: "Click in the test field, hold Fn while you speak and release to paste. Press Fn twice for hands-free dictation and Fn again to finish. Escape discards. Without Fn, use ⌥⇧Space."),
            secondary: true))
    stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    stack.addArrangedSubview(titleLabel)
    detailLabel.font = .preferredFont(forTextStyle: .callout)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.maximumNumberOfLines = 3
    detailLabel.preferredMaxLayoutWidth = Self.windowWidth - 48
    stack.addArrangedSubview(detailLabel)
    permissionLabel.font = .preferredFont(forTextStyle: .callout)
    permissionLabel.textColor = .systemOrange
    permissionLabel.preferredMaxLayoutWidth = Self.windowWidth - 48
    setupButton = button(String(localized: "Open Setup…"), #selector(openSetup))
    stack.addArrangedSubview(permissionLabel)
    stack.addArrangedSubview(setupButton)
    scratch.setAccessibilityLabel(String(localized: "Dictation test field"))
    let scratchScroll = textArea(scratch, height: 130, editable: true)
    stack.addArrangedSubview(scratchScroll)
    scratchScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    startButton = button(String(localized: "Record in Test Field"), #selector(startInScratch))
    cancelButton = button(String(localized: "Discard"), #selector(cancelAction))
    var controls: [NSView] = [startButton, cancelButton]
    #if DEBUG
    // Public sample recordings exercise recognition without a microphone; development only.
    demoDE = button("Demo Deutsch", #selector(demoGerman))
    demoEN = button("Demo English", #selector(demoEnglish))
    controls += [demoDE!, demoEN!]
    #endif
    stack.addArrangedSubview(row(controls))
    stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
    stack.addArrangedSubview(label(String(localized: "Last Result"), style: .headline))
    let resultScroll = textArea(result, height: 92, editable: false)
    result.setAccessibilityLabel(String(localized: "Last dictation result"))
    stack.addArrangedSubview(resultScroll)
    resultScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.addArrangedSubview(
      row([
        button(String(localized: "Copy Result"), #selector(copyResult)),
        button(String(localized: "Clear"), #selector(clearFields)),
        button(String(localized: "Dictation Settings…"), #selector(openDictationSettings)),
      ]))
    stack.addArrangedSubview(
      label(String(localized: "Audio and text stay in memory until you discard them or quit. Pasting briefly uses the clipboard and then restores it, unless you copied something newer. Up to 60 seconds per recording."),
            style: .callout, secondary: true))
    refreshPermissions()
    window.contentView!.layoutSubtreeIfNeeded()
    window.setContentSize(NSSize(width: Self.windowWidth, height: stack.fittingSize.height + 42))
    window.center()
  }
  var onOpenSetup: (() -> Void)?
  @objc func openSetup() { onOpenSetup?() }
  @objc func openDictationSettings() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
    startButton?.title = phase == "recording" ? String(localized: "Finish & Paste") : String(localized: "Record in Test Field")
    let busy = ["recording", "processing", "pasting"].contains(phase)
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
      String(localized: "Preparing dictation…"),
      String(localized: "\(selectedModel.displayName) loads automatically and stays ready while Saywing is open."))
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
  func selectModel(_ model: DictationModel) {
    guard canChangeModel, model != selectedModel else { return }
    modelGeneration = UUID()
    cancel(restart: false)
    worker.stop()
    selectedModel = model
    preferences.set(model.rawValue, forKey: "dictationModel.v1")
    phase = "unloaded"
    loadModel()
  }
  /// Only problems are shown; granted permissions need no line of their own.
  @objc func refreshPermissions() {
    if monitorFn && canPrepareModel { fnShortcuts.start() }
    var problems: [String] = []
    if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
      problems.append(String(localized: "Microphone not allowed."))
    }
    if !AXIsProcessTrusted() {
      problems.append(String(localized: "Accessibility not allowed, so text can only be pasted into this window."))
    }
    if monitorFn && !fnShortcuts.isAvailable {
      problems.append(String(localized: "Fn is not available; use ⌥⇧Space."))
    }
    if !shortcutAvailable {
      problems.append(String(localized: "⌥⇧Space is in use by another app; use the Record button."))
    }
    permissionLabel.stringValue = problems.joined(separator: " ")
    permissionLabel.isHidden = problems.isEmpty
    setupButton?.isHidden = problems.isEmpty
  }
  func armEscape() throws {
    escape.onPress = { [weak self] in self?.cancel() }
    guard
      escape.register(HotkeyShortcut(keyCode: 53, carbonModifiers: 0, displayName: "Escape"))
        == .registered
    else {
      throw DictationError(
        String(localized: "Escape is in use by another app. Recording did not start; quit the other dictation app."))
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
        phase == "processing" ? String(localized: "Recognizing text…") : String(localized: "Model not ready yet"),
        phase == "processing"
          ? String(localized: "Escape discards this dictation.") : String(localized: "The current dictation is still running. Escape discards it."),
        floating: true)
      hidePanelLater()
      return
    }
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      setStatus(
        String(localized: "Allow the microphone"),
        String(localized: "Allow the microphone in Setup, then start recording again."),
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
      setStatus(String(localized: "Recording did not start"), error.localizedDescription, floating: true)
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
        String(localized: "Recording · 0 s"), String(localized: "Target: \(target.name). Release Fn, or finish hands-free with Fn + Space."), floating: true)
      let id = request
      recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.request == id, self.phase == "recording" else { return }
          let elapsed = Date().timeIntervalSince(self.recordingStart)
          self.capsule.updateRecording(rms: self.record?.audio.rms ?? 0)
          self.titleLabel.stringValue = String(localized: "Recording · \(Int(elapsed)) / 60 s")
          if elapsed >= 60 { self.finishRecording() }
        }
      }
    } catch {
      cancel(restart: false)
      setStatus(String(localized: "Recording did not start"), error.localizedDescription, floating: true)
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
      String(localized: "Recognizing text…"), String(localized: "Everything is processed on this Mac. Escape discards it."),
      floating: true)
    let lang = language.workerValue
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
        String(localized: "Time limit reached"), String(localized: "The dictation was discarded. You can start a new one."),
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
        String(localized: "Ready"), String(localized: "Click in a text field and hold Fn, or use the test field here.")
      )
      if smoke { runSmoke() }
    case "fatal":
      let detail = message.localizedDetail ?? String(localized: "The local dictation process is not available.")
      cancel(restart: false)
      worker.stop()
      phase = "unloaded"
      setStatus(String(localized: "Model not available"), detail, floating: true)
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
          String(localized: "Recognition failed"), message.localizedDetail ?? String(localized: "Please try again."), floating: true)
        if smoke { finishSmoke(error: "worker error") }
        return
      }
      let text = message.text ?? ""
      latestText = text
      result.string = text
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        complete()
        setStatus(String(localized: "No speech recognized"), String(localized: "Nothing was pasted."), floating: true)
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
        String(localized: "Target changed"),
        String(localized: "The result is in the dictation window. Nothing was pasted automatically."),
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
        String(localized: "Paste sent"), String(localized: "The clipboard will be restored in a moment."), floating: true)
      let work = DispatchWorkItem { [weak self] in
        guard let self, self.gate.accepts(id) else { return }
        let confirmed = target.confirms(text)
        _ = transaction.restore()
        self.lease = nil
        self.restore = nil
        self.complete()
        self.setStatus(
          confirmed ? String(localized: "Pasted") : String(localized: "Paste sent"),
          confirmed
            ? String(localized: "Ready for the next recording.")
            : String(localized: "Please check the target field. Nothing is retried; the result stays in the dictation window."),
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
        deadline: .now() + (restoresClipboardSlowly ? 2.0 : 1.0), execute: work)
    } catch {
      _ = lease?.restore()
      lease = nil
      complete()
      setStatus(String(localized: "Not pasted"), error.localizedDescription, floating: true)
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
    setStatus(String(localized: "Discarded"), String(localized: "The recording and its result were discarded."), floating: false)
    panel?.orderOut(nil)
    if restart { loadModel() }
  }
  @objc func copyResult() {
    guard !isActive, !latestText.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(latestText, forType: .string)
    setStatus(
      String(localized: "Result copied"), String(localized: "The copy you asked for stays on the clipboard."))
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
      else { throw DictationError(String(localized: "The sample recording could not be read.")) }
      try file.read(into: buffer)
      guard let channels = buffer.floatChannelData else {
        throw DictationError(String(localized: "The sample recording is invalid."))
      }
      let samples = Array(UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
      try begin(target: InsertionTarget(local: scratch))
      send(AudioPacket(samples: samples, rate: buffer.format.sampleRate))
    } catch {
      setStatus(String(localized: "Sample recording not available"), error.localizedDescription)
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
        ? String(localized: "Sample checks passed") : String(localized: "Check needs attention"),
      String(localized: "Two public sample recordings tested recognition, pasting and restoring. Your microphone was not used.")
    )
  }
}
