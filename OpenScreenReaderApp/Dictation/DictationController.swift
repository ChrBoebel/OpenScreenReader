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
  @Published private(set) var pendingInstallModel: DictationModel?
  private var installSelectionID = UUID()
  @Published private(set) var shortcutConfiguration: ShortcutConfiguration
  @Published private(set) var shortcutNotice: String?
  @Published private(set) var fnEnabled: Bool
  private(set) var shortcutsSuspended = false
  private let shortcutStore: UserDefaultsShortcutStore
  private var instructionLabel = NSTextField(wrappingLabelWithString: "")
  @Published private(set) var language: DictationLanguage
  @Published private(set) var vocabulary: [String]
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
  let models: DictationModelStore
  let worker: any DictationTranscribing
  let gate = GenerationGate()
  var window: NSWindow!, scratch: NSTextView = TabEscapingTextView(), result = NSTextView()
  private var windowNeedsInitialLayout = true
  var titleLabel = NSTextField(labelWithString: String(localized: "Preparing model…"))
  var detailLabel = NSTextField(wrappingLabelWithString: "")
  var permissionLabel = NSTextField(wrappingLabelWithString: "")
  /// Shown only when a result could not be pasted, so it can still be copied.
  let resultSection = NSStackView()
  private let schedulePasteCallback: (Double, DispatchWorkItem) -> Void
  private let interfaceSounds: (any InterfaceSoundPlaying)?
  /// Where this dictation's text will land; the capsule appears next to it.
  private var capsuleAnchor: CGRect?
  var startButton: NSButton!, cancelButton: NSButton!, setupButton: NSButton!
  var demoDE: NSButton?, demoEN: NSButton?
  var panel: DictationStatusPanel!
  let capsule = DictationCapsuleView(frame: CGRect(origin: .zero, size: DictationCapsuleView.surface))
  private var panelGeneration = UUID()
  var record: (any DictationRecording)?, target: InsertionTarget?, request: UUID?
  /// Tests replace the microphone; the app always records through AVAudioEngine.
  var makeRecorder: () -> any DictationRecording = { MicrophoneRecorder() }
  /// Hands-free was requested before the microphone opened (activation is asynchronous).
  private var startsHandsFree = false
  /// The paste was read back early; the result has already sounded and been announced.
  private var insertionConfirmed = false
  private var confirmation: DispatchWorkItem?
  var phase = "loading", latestText = ""
  var recordingTimer: Timer?, recordingStart = Date()
  var timeout: DispatchWorkItem?, panelHide: DispatchWorkItem?,
    restore: DispatchWorkItem?
  var lease: ClipboardLease?
  /// A paste that was sent but not read back when it was discarded. Its clipboard
  /// is restored by the scheduled restore, after the full wait, never earlier: a
  /// slow target app may still be reading the dictated text.
  private(set) var deferredLease: ClipboardLease?
  var shortcutAvailable = true
  var localEscape: Any?
  var smoke = false, smokeIndex = 0, smokeFailures = [String]()
  var smokeClipboard: ClipboardSnapshot?

  init(
    resources: URL? = nil, models: DictationModelStore? = nil,
    worker: any DictationTranscribing = DictationWorker(),
    shortcut: any HotkeyManaging = GlobalHotkeyManager(),
    escape: any HotkeyManaging = GlobalHotkeyManager(),
    preferences: UserDefaults = InterfaceSoundPlayer.defaults, registerHotkey: Bool = true,
    interfaceSounds: (any InterfaceSoundPlaying)? = nil,
    schedulePasteCallback: @escaping (Double, DispatchWorkItem) -> Void = { delay, work in
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
  ) {
    self.interfaceSounds = interfaceSounds
    self.schedulePasteCallback = schedulePasteCallback
    let resources = resources ?? Bundle.main.resourceURL!.appendingPathComponent("Dictation")
    self.resources = resources
    let models = models ?? DictationModelStore(resources: resources)
    self.models = models
    self.worker = worker
    self.shortcut = shortcut
    self.escape = escape
    self.preferences = preferences
    let shortcutStore = UserDefaultsShortcutStore(defaults: preferences, preferenceKey: "dictationShortcut.v1")
    self.shortcutStore = shortcutStore
    self.shortcutConfiguration = shortcutStore.load() ?? .dictationDefault
    self.fnEnabled = preferences.object(forKey: "dictationFnEnabled.v1") as? Bool ?? true
    // A saved choice that is not installed in this build stays saved but is not started.
    let saved = DictationModel(rawValue: preferences.string(forKey: "dictationModel.v1") ?? "")
    self.selectedModel = saved.flatMap { models.isInstalled($0) ? $0 : nil } ?? .standard
    let intent = preferences.string(forKey: "dictationInstallIntent.v1").flatMap(DictationModel.init(rawValue:))
    if let intent, models.isInstalled(intent) {
      self.selectedModel = intent
      preferences.set(intent.rawValue, forKey: "dictationModel.v1")
      preferences.removeObject(forKey: "dictationInstallIntent.v1")
    } else { self.pendingInstallModel = intent }
    self.language = DictationLanguage(rawValue: preferences.integer(forKey: "dictationLanguage.v1")) ?? .automatic
    self.restoresClipboardSlowly = preferences.bool(forKey: "dictationSlowPaste.v1")
    self.vocabulary = DictationVocabulary.parse(
      (preferences.stringArray(forKey: "dictationVocabulary.v1") ?? []).joined(separator: "\n"))
    self.monitorFn = registerHotkey
    super.init()
    buildWindow()
    buildPanel()
    shortcut.onPress = { [weak self] in
      guard let self, !self.shortcutsSuspended else { return }; self.toggle()
    }
    fnShortcuts.onAction = { [weak self] action in self?.handle(action) ?? false }
    if registerHotkey {
      shortcutAvailable =
        shortcut.register(shortcutConfiguration.resolvedShortcut()) == .registered
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
      String(localized: "Ready to dictate"), activationInstructions
    )
    refreshPermissions()
  }
  /// Fn gestures. Holding records until release; a latch keeps recording hands-free.
  @discardableResult
  func handle(_ action: FnDictationGesture.Action) -> Bool {
    guard !shortcutsSuspended, fnEnabled else { return false }
    switch action {
    case .start:
      guard !isActive, ["ready", "loading", "unloaded"].contains(phase) else { return false }
      toggle(handsFree: false)
      return isActive
    case .lock:
      guard isActive else { return false }
      guard phase == "recording" else {
        // The microphone is not open yet; it opens latched, with one cue.
        startsHandsFree = true
        return true
      }
      latchHandsFree()
    case .finish:
      if phase == "recording" { finishRecording() }
      else if isActive { cancel() }
    case .cancel: cancel()
    }
    return true
  }
  private func latchHandsFree() {
    guard !capsule.isHandsFree else { return }
    capsule.setHandsFree(true)
    interfaceSounds?.play(.handsFree)
    detailLabel.stringValue = String(localized: "Recording hands-free. Fn or Fn + Space finishes; Escape discards.")
  }
  func setLanguage(_ value: DictationLanguage) {
    language = value
    preferences.set(value.rawValue, forKey: "dictationLanguage.v1")
  }
  func setVocabulary(_ text: String) {
    vocabulary = DictationVocabulary.parse(text)
    if vocabulary.isEmpty {
      preferences.removeObject(forKey: "dictationVocabulary.v1")
    } else {
      preferences.set(vocabulary, forKey: "dictationVocabulary.v1")
    }
  }
  var activationInstructions: String {
    if fnEnabled {
      return String(localized: "Hold Fn to dictate and release to paste, or use \(shortcutConfiguration.displayName) to start and finish. Escape discards.")
    }
    return String(localized: "Press \(shortcutConfiguration.displayName) to start dictating and press it again to paste. Escape discards.")
  }
  func setFnEnabled(_ enabled: Bool) {
    guard !isActive, canPrepareModel else { return }
    fnEnabled = enabled
    preferences.set(enabled, forKey: "dictationFnEnabled.v1")
    if !enabled { fnShortcuts.stop() }
    instructionLabel.stringValue = activationInstructions
    refreshPermissions()
    if window.isVisible { fitWindow(animate: false) }
  }
  func setShortcutsSuspended(_ suspended: Bool) {
    guard suspended != shortcutsSuspended, !isActive else { return }
    shortcutsSuspended = suspended
    if suspended {
      shortcut.unregister()
      fnShortcuts.stop()
    } else if canPrepareModel {
      shortcutAvailable = shortcut.register(shortcutConfiguration.resolvedShortcut()) == .registered
      refreshPermissions()
    }
  }
  func rejectShortcut(_ message: String) { shortcutNotice = message }
  func changeShortcut(_ configuration: ShortcutConfiguration) {
    guard !isActive, !shortcutsSuspended, canPrepareModel else { return }
    guard configuration.isValid else {
      shortcutNotice = String(localized: "Choose a key and at least Command, Option, or Control. Escape is reserved for cancellation.")
      return
    }
    let result = shortcut.register(configuration.resolvedShortcut())
    guard result == .registered else {
      shortcutNotice = AppModel.registrationErrorMessage(for: result, shortcut: configuration)
      return
    }
    shortcutAvailable = true
    shortcutConfiguration = configuration
    shortcutStore.save(configuration)
    shortcutNotice = String(localized: "Shortcut \(configuration.displayName) is active and saved.")
    instructionLabel.stringValue = activationInstructions
    refreshPermissions()
    if window.isVisible { fitWindow(animate: false) }
  }
  func setRestoresClipboardSlowly(_ value: Bool) {
    restoresClipboardSlowly = value
    preferences.set(value, forKey: "dictationSlowPaste.v1")
  }
  @objc func terminate() { shutdown() }
  func shutdown() {
    isShutDown = true
    installSelectionID = UUID()
    for model in DictationModel.allCases { models.cancelInstall(model) }
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
      activationInstructions)
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
    instructionLabel = label(activationInstructions, secondary: true)
    stack.addArrangedSubview(instructionLabel)
    stack.setCustomSpacing(16, after: stack.arrangedSubviews.last!)
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    stack.addArrangedSubview(titleLabel)
    detailLabel.font = .preferredFont(forTextStyle: .callout)
    detailLabel.textColor = .secondaryLabelColor
    detailLabel.maximumNumberOfLines = 3
    detailLabel.preferredMaxLayoutWidth = Self.windowWidth - 48
    stack.addArrangedSubview(detailLabel)
    permissionLabel.font = .preferredFont(forTextStyle: .callout)
    // Full-contrast text; the warning sign carries the alert, not the colour alone.
    permissionLabel.textColor = .labelColor
    permissionLabel.preferredMaxLayoutWidth = Self.windowWidth - 48
    setupButton = button(String(localized: "Open Setup…"), #selector(openSetup))
    stack.addArrangedSubview(permissionLabel)
    stack.addArrangedSubview(setupButton)
    scratch.setAccessibilityLabel(String(localized: "Dictation test field"))
    let scratchScroll = textArea(scratch, height: 130, editable: true)
    stack.addArrangedSubview(scratchScroll)
    scratchScroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    startButton = button(String(localized: "Record in Test Field"), #selector(startInScratch))
    startButton.keyEquivalent = "\r"
    cancelButton = button(String(localized: "Discard"), #selector(cancelAction))
    var controls: [NSView] = [startButton, cancelButton]
    #if DEBUG
    // Public sample recordings exercise recognition without a microphone; development only.
    demoDE = button("Demo Deutsch", #selector(demoGerman))
    demoEN = button("Demo English", #selector(demoEnglish))
    controls += [demoDE!, demoEN!]
    #endif
    stack.addArrangedSubview(row(controls))
    resultSection.orientation = .vertical
    resultSection.alignment = .leading
    resultSection.spacing = 8
    resultSection.addArrangedSubview(label(String(localized: "Not pasted"), style: .headline))
    let resultScroll = textArea(result, height: 92, editable: false)
    result.setAccessibilityLabel(String(localized: "Last dictation result"))
    resultSection.addArrangedSubview(resultScroll)
    resultScroll.widthAnchor.constraint(equalTo: resultSection.widthAnchor).isActive = true
    resultSection.addArrangedSubview(button(String(localized: "Copy Result"), #selector(copyResult)))
    resultSection.isHidden = true
    stack.addArrangedSubview(resultSection)
    resultSection.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    stack.setCustomSpacing(16, after: resultSection)
    stack.addArrangedSubview(
      label(String(localized: "Audio and text stay only in memory. Up to 60 seconds per recording."),
            style: .callout, secondary: true))
    refreshPermissions()
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
      // Feedback sounds with its visible result, never while the microphone records.
      if phase != "recording" {
        switch presentation {
        case .inserted: interfaceSounds?.play(.completion)
        case .attention, .unconfirmed: interfaceSounds?.play(.attention)
        default: break
        }
        // The capsule never takes focus, so results are announced. Not while
        // recording: the microphone would pick up VoiceOver's speech.
        let urgent = presentation == .attention || presentation == .unconfirmed
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
          .announcement: [title, urgent ? detail : ""].filter { !$0.isEmpty }.joined(separator: ". "),
          .priority: (urgent ? NSAccessibilityPriorityLevel.high : .medium).rawValue,
        ])
      }
      panelHide?.cancel()
      panelGeneration = UUID()
      let anchor = capsuleAnchor
      guard let screen = NSScreen.screens.first(where: { anchor.map($0.frame.intersects) ?? false })
              ?? NSScreen.main ?? NSScreen.screens.first else { return }
      let docked = ReadingPanelPlacement.load(from: InterfaceSoundPlayer.defaults).frame(in: screen.visibleFrame)
      panel.setFrameOrigin(DictationCapsulePlacement.origin(
        caret: anchor, visible: screen.visibleFrame, docked: docked, size: DictationCapsuleView.surface))
      panel.orderFrontRegardless()
      capsule.show()
    }
  }
  /// Shows or hides the unpasted result and keeps the window fitted to it.
  func setResultVisible(_ visible: Bool) {
    guard resultSection.isHidden == visible else { return }
    resultSection.isHidden = !visible
    fitWindow(animate: window.isVisible)
  }
  private func fitWindow(animate: Bool) {
    guard let content = window.contentView, let stack = content.subviews.first as? NSStackView else { return }
    content.layoutSubtreeIfNeeded()
    let frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.windowWidth, height: stack.fittingSize.height + 42))
    // Keep the title bar where it is; the window grows or shrinks downward.
    window.setFrame(NSRect(x: window.frame.minX, y: window.frame.maxY - frame.height, width: frame.width, height: frame.height),
                    display: true, animate: animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
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
    refreshPermissions()
    if !worker.running && request == nil { loadModel() }
    if !window.isVisible { fitWindow(animate: false) }
    // AppKit layout during StateObject construction can re-enter SwiftUI's graph.
    // Fit and center on first presentation; later openings keep the user's position.
    if windowNeedsInitialLayout {
      window.center()
      windowNeedsInitialLayout = false
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.makeFirstResponder(scratch)
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
    worker.start(resources: resources, model: selectedModel, modelRoot: models.modelRoot(for: selectedModel))
  }
  func selectModel(_ model: DictationModel) {
    guard canChangeModel, models.isInstalled(model) else { return }
    installSelectionID = UUID()
    if let pendingInstallModel { models.cancelInstall(pendingInstallModel) }
    pendingInstallModel = nil
    preferences.removeObject(forKey: "dictationInstallIntent.v1")
    guard model != selectedModel else { return }
    modelGeneration = UUID()
    cancel(restart: false)
    worker.stop()
    selectedModel = model
    preferences.set(model.rawValue, forKey: "dictationModel.v1")
    phase = "unloaded"
    loadModel()
  }
  /// Downloads a missing model only on this explicit request, then switches to it.
  @discardableResult
  func install(_ model: DictationModel) -> Task<Void, Never>? {
    guard canChangeModel, models.canDownload(model), !models.isInstalled(model) else { return nil }
    if let pendingInstallModel, pendingInstallModel != model { models.cancelInstall(pendingInstallModel) }
    let selectionID = UUID()
    installSelectionID = selectionID
    pendingInstallModel = model
    preferences.set(model.rawValue, forKey: "dictationInstallIntent.v1")
    preferences.synchronize()
    let download = models.install(model)
    return Task { [weak self] in
      await download.value
      guard !Task.isCancelled, let self, !self.isShutDown, self.installSelectionID == selectionID,
            self.models.isInstalled(model) else { return }
      self.selectModel(model)
    }
  }
  func cancelInstall(_ model: DictationModel) {
    if pendingInstallModel == model {
      installSelectionID = UUID()
      pendingInstallModel = nil
      preferences.removeObject(forKey: "dictationInstallIntent.v1")
    }
    models.cancelInstall(model)
  }
  /// Only problems are shown; granted permissions need no line of their own.
  @objc func refreshPermissions() {
    if monitorFn && fnEnabled && !shortcutsSuspended && canPrepareModel { fnShortcuts.start() }
    var problems: [String] = []
    if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
      problems.append(String(localized: "Microphone not allowed."))
    }
    if !AXIsProcessTrusted() {
      problems.append(String(localized: "Accessibility not allowed, so text can only be pasted into this window."))
    }
    if monitorFn && fnEnabled && !shortcutsSuspended && !fnShortcuts.isAvailable {
      problems.append(String(localized: "Fn is not available; use \(shortcutConfiguration.displayName)."))
    }
    if !shortcutAvailable {
      problems.append(String(localized: "\(shortcutConfiguration.displayName) is in use by another app; choose another shortcut in Settings."))
    }
    permissionLabel.stringValue = problems.isEmpty ? "" : "⚠︎ " + problems.joined(separator: " ")
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
  /// The shortcut and the Record button start hands-free; only a held Fn does not.
  func toggle(internalTarget: InsertionTarget? = nil, handsFree: Bool = true) {
    guard !shortcutsSuspended else { return }
    guard canPrepareModel else { return }
    if phase == "recording" {
      finishRecording()
      return
    }
    if !isActive { capsuleAnchor = nil }
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
      capsuleAnchor = target.caretRect()
      let id = UUID()
      activationID = id
      startsHandsFree = handsFree
      let start: @MainActor () -> Void = { [weak self] in
        guard let self, self.activationID == id else { return }
        self.activationID = nil
        self.startRecording(target: target, handsFree: self.startsHandsFree)
      }
      if let onActivation { onActivation(start) } else { start() }

    } catch {
      cancel(restart: false)
      phase = worker.ready ? "ready" : "unloaded"
      setStatus(String(localized: "Recording did not start"), error.localizedDescription, floating: true)
      hidePanelLater()
    }
  }
  func startRecording(target: InsertionTarget, handsFree: Bool = true) {
    guard canPrepareModel else { return }
    do {
      try begin(target: target)
      if !worker.running { startWorker() }
      guard request != nil else { return }
      let recorder = makeRecorder()
      record = recorder
      let recording = request
      recorder.onInterruption = { [weak self] in
        guard let self, self.request == recording, self.phase == "recording" else { return }
        self.failRecording(DictationError.inputDeviceChanged)
      }
      try recorder.start()
      phase = "recording"
      recordingStart = Date()
      setStatus(
        String(localized: "Recording · 0 s"), String(localized: "Target: \(target.name). Release Fn, or finish hands-free with Fn + Space."), floating: true)
      // The cue sounds with the capsule, as the microphone opens. Already latched,
      // it opens with the latch cue alone instead of two cues on top of each other.
      capsule.setHandsFree(handsFree, animated: false)
      interfaceSounds?.play(handsFree ? .handsFree : .listening)
      if handsFree {
        detailLabel.stringValue = String(localized: "Recording hands-free. Fn or Fn + Space finishes; Escape discards.")
      }
      let id = request
      recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.request == id, self.phase == "recording" else { return }
          let elapsed = Date().timeIntervalSince(self.recordingStart)
          self.capsule.updateRecording(rms: self.record?.level ?? 0)
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
    insertionConfirmed = false
    result.string = ""
    setResultVisible(false)
    request = gate.begin()
    self.target = target
  }
  func finishRecording() {
    guard phase == "recording", let record else { return }
    fnShortcuts.resetGesture()
    recordingTimer?.invalidate()
    recordingTimer = nil
    let audio: AudioPacket
    do { audio = try record.finish() } catch {
      self.record = nil
      failRecording(error)
      return
    }
    self.record = nil
    // After the microphone is closed, so the cue is never part of the recording.
    interfaceSounds?.play(.captured)
    send(audio)
  }
  /// The recording cannot be trusted any more: discard it and say why, visibly.
  private func failRecording(_ error: Error) {
    cancel(restart: false)
    setStatus(String(localized: "Recording stopped"), error.localizedDescription, floating: true)
    hidePanelLater()
  }
  func send(_ audio: AudioPacket) {
    guard let id = request else { return }
    phase = "processing"
    setStatus(
      String(localized: "Recognizing text…"), String(localized: "Everything is processed on this Mac. Escape discards it."),
      floating: true)
    let lang = language.workerValue
    if worker.ready {
      worker.transcribe(audio, id: id, language: lang, vocabulary: vocabulary)
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
      setResultVisible(true)
      setStatus(
        String(localized: "Target changed"),
        String(localized: "The result is in the dictation window. Nothing was pasted automatically."),
        floating: true)
      hidePanelLater()
      if smoke { finishSmoke(error: "target changed") }
      return
    }
    do {
      // A new paste takes its snapshot only after an earlier discarded paste gave the
      // clipboard back; that paste had at least a whole recording's time to land.
      _ = deferredLease?.restore()
      deferredLease = nil
      let transaction = try ClipboardLease.begin(text, on: .general)
      lease = transaction
      // Recheck after taking the clipboard snapshot, before the single paste action.
      try target.paste()
      phase = "pasting"
      setStatus(
        String(localized: "Paste sent"), String(localized: "The clipboard will be restored in a moment."), floating: true)
      // Most fields show the text within a few frames. Reading it back early lets the
      // tick and the completion cue land with the text, not a second later; the
      // clipboard is still restored only after the full wait for slow apps.
      let early = DispatchWorkItem { [weak self] in
        guard let self, self.gate.accepts(id), self.phase == "pasting", target.confirms(text) else { return }
        self.insertionConfirmed = true
        self.setStatus(String(localized: "Pasted"), String(localized: "Ready for the next recording."),
                       floating: true, capsuleState: .inserted)
      }
      confirmation = early
      schedulePasteCallback(0.15, early)
      let work = DispatchWorkItem { [weak self] in
        guard let self else { _ = transaction.restore(); return }
        if self.deferredLease === transaction {
          // Discarded after the paste was sent: only give the clipboard back.
          _ = transaction.restore()
          self.deferredLease = nil
          return
        }
        guard self.gate.accepts(id) else { return }
        let announced = self.insertionConfirmed
        let confirmed = announced || target.confirms(text)
        _ = transaction.restore()
        self.lease = nil
        self.restore = nil
        self.complete()
        self.setResultVisible(!confirmed)
        self.setStatus(
          confirmed ? String(localized: "Pasted") : String(localized: "Paste sent"),
          confirmed
            ? String(localized: "Ready for the next recording.")
            : String(localized: "Please check the target field. Nothing is retried; the result stays in the dictation window."),
          floating: !announced, capsuleState: confirmed ? .inserted : .unconfirmed)
        self.hidePanelLater()
        if self.smoke {
          if !confirmed { self.smokeFailures.append("paste not confirmed") }
          self.smokeIndex += 1
          self.runSmoke()
        }
      }
      restore = work
      schedulePasteCallback(restoresClipboardSlowly ? 2.0 : 1.0, work)
    } catch {
      _ = lease?.restore()
      lease = nil
      complete()
      setResultVisible(true)
      setStatus(String(localized: "Not pasted"), error.localizedDescription, floating: true)
      hidePanelLater()
      if smoke { finishSmoke(error: error.localizedDescription) }
    }
  }
  func complete() {
    fnShortcuts.resetGesture()
    confirmation?.cancel()
    confirmation = nil
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
    // Once Cmd+V is sent, the target may read the clipboard at any moment. Unless the
    // text was already read back in the field, restoring now could paste the previous
    // clipboard (possibly something private) instead; the scheduled restore keeps its wait.
    let pasteInFlight = phase == "pasting" && lease != nil && restore != nil && !insertionConfirmed
    // Discarding is silent, like stopping a reading: a cue still sounding ends now.
    if isActive { interfaceSounds?.stop() }
    activationID = nil
    startsHandsFree = false
    insertionConfirmed = false
    confirmation?.cancel()
    confirmation = nil
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
    if pasteInFlight {
      deferredLease = lease
    } else {
      restore?.cancel()
      _ = lease?.restore()
    }
    restore = nil
    lease = nil
    disarmEscape()
    latestText = ""
    result.string = ""
    setResultVisible(false)
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

/// Tab moves to the next control instead of typing a tab, so keyboard users can
/// leave the test field.
final class TabEscapingTextView: NSTextView {
  override func insertTab(_ sender: Any?) { window?.selectNextKeyView(sender) }
  override func insertBacktab(_ sender: Any?) { window?.selectPreviousKeyView(sender) }
}
