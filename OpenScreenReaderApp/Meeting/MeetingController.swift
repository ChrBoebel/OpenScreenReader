import AppKit
import Combine
import Foundation
import SwiftUI

/// One meeting transcript at a time: consent, live recognition of "Me" and
/// "Others", stop, then copy, save or discard. Independent of reading and
/// dictation; only its own Stop, its limits, sleep and quitting end a recording.
@MainActor
final class MeetingController: ObservableObject {
  enum Phase: Equatable {
    case idle
    /// Waiting for the user to confirm that everyone is informed.
    case consent
    case unavailable(String)
    case starting, live, stopping
    case finished
  }

  struct Limits {
    var maximumDuration: TimeInterval = 2 * 3600
    var warningLead: TimeInterval = 5 * 60
    var silence: TimeInterval = 10 * 60
    var systemAudioGrace: TimeInterval = 20
  }

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var transcript = MeetingTranscript()
  @Published private(set) var elapsed: TimeInterval = 0
  @Published private(set) var levels: [MeetingSpeaker: Double] = [:]
  @Published private(set) var notice: String?
  /// No non-zero sample from other apps yet: the system audio permission is the likely cause.
  @Published private(set) var systemAudioMissing = false
  @Published private(set) var hasUnsavedText = false
  private(set) var startedAt: Date?

  var isRecording: Bool { phase == .starting || phase == .live || phase == .stopping }

  /// The sentence offered for the meeting chat; copied only on request.
  static var consentNotice: String {
    String(localized: "I'm transcribing this meeting locally on my Mac with Saywing. No audio is saved or uploaded.")
  }

  private let provider: any MeetingRecognizerProviding
  private let makeMicrophone: @MainActor () -> any MeetingAudioSource
  private let makeSystemAudio: @MainActor () -> (any MeetingAudioSource)?
  private let language: @MainActor () -> DictationLanguage
  private let interfaceSounds: (any InterfaceSoundPlaying)?
  private let hostClock: () -> UInt64
  private let limits: Limits
  private let pasteboard: NSPasteboard
  private let saveExport: @MainActor (MeetingExport, String) -> Bool
  private let confirmLosingUnsaved: @MainActor (LossReason) -> Bool

  /// Why unsaved text would be lost; the alert names the action.
  enum LossReason: Equatable { case newTranscript, discard }
  private let presentsWindow: Bool
  private let gate = GenerationGate()
  private var generation: UUID?
  private var recognizer: (any MeetingRecognizing)?
  private var router: MeetingAudioRouter?
  private var microphone: (any MeetingAudioSource)?
  private var system: (any MeetingAudioSource)?
  private var startHost: UInt64 = 0
  private var warned = false
  private var ticker: Task<Void, Never>?
  private var lifecycle: Task<Void, Never>?
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var window: NSWindow?

  init(
    provider: any MeetingRecognizerProviding = SystemMeetingRecognizerProvider(),
    makeMicrophone: @escaping @MainActor () -> any MeetingAudioSource = { MeetingMicrophoneSource() },
    makeSystemAudio: @escaping @MainActor () -> (any MeetingAudioSource)? = {
      if #available(macOS 14.2, *) { SystemAudioTapSource() } else { nil }
    },
    language: @escaping @MainActor () -> DictationLanguage = {
      DictationLanguage(rawValue: UserDefaults.standard.integer(forKey: "dictationLanguage.v1")) ?? .automatic
    },
    interfaceSounds: (any InterfaceSoundPlaying)? = nil,
    hostClock: @escaping () -> UInt64 = { MeetingHostClock.now },
    limits: Limits = Limits(),
    pasteboard: NSPasteboard = .general,
    notifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
    appNotifications: NotificationCenter = .default,
    save: @escaping @MainActor (MeetingExport, String) -> Bool = MeetingController.saveWithPanel,
    confirmLosingUnsaved: @escaping @MainActor (LossReason) -> Bool = MeetingController.confirmWithAlert,
    presentsWindow: Bool = true
  ) {
    self.provider = provider
    self.makeMicrophone = makeMicrophone
    self.makeSystemAudio = makeSystemAudio
    self.language = language
    self.interfaceSounds = interfaceSounds
    self.hostClock = hostClock
    self.limits = limits
    self.pasteboard = pasteboard
    self.saveExport = save
    self.confirmLosingUnsaved = confirmLosingUnsaved
    self.presentsWindow = presentsWindow
    for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
      observe(name, on: notifications) { $0.stop() }
    }
    observe(NSApplication.willTerminateNotification, on: appNotifications) { $0.shutdown() }
  }

  isolated deinit {
    for (center, observer) in observers { center.removeObserver(observer) }
    shutdown()
  }

  private func observe(_ name: Notification.Name, on center: NotificationCenter, _ action: @escaping @MainActor (MeetingController) -> Void) {
    let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        action(self)
      }
    }
    observers.append((center, observer))
  }

  // MARK: Flow

  /// The menu entry: shows the running or finished transcript, otherwise the consent step.
  func open() async {
    showWindow()
    guard phase == .idle || phase == .consent || isUnavailable else { return }
    notice = nil
    switch await provider.availability(for: language()) {
    case .available: phase = .consent
    case .unsupportedSystem:
      phase = .unavailable(String(localized: "Meeting transcripts need macOS 26 or later, with on-device speech recognition."))
    case let .languageMissing(name):
      phase = .unavailable(String(localized: "Speech recognition for \(name) is not installed on this Mac. Saywing does not download it."))
    }
  }

  /// Replaces a finished transcript, after asking if it was never copied or saved.
  func startNew() async {
    guard phase == .finished else { return await open() }
    guard !hasUnsavedText || confirmLosingUnsaved(.newTranscript) else { return }
    resetTranscript()
    phase = .idle
    await open()
  }

  func confirmConsent() {
    guard phase == .consent else { return }
    let id = gate.begin()
    generation = id
    resetTranscript()
    phase = .starting
    lifecycle = Task { [weak self] in await self?.begin(id) }
  }

  private func begin(_ id: UUID) async {
    guard case let .available(locale) = await provider.availability(for: language()),
      let recognizer = provider.makeRecognizer()
    else { return fail(id, String(localized: "Speech recognition is not available on this Mac.")) }
    self.recognizer = recognizer
    do {
      try await recognizer.start(
        locale: locale,
        onResult: { [weak self] result in Task { @MainActor in self?.receive(result, id) } },
        onFailure: { [weak self] message in Task { @MainActor in self?.recognitionFailed(message, id) } })
    } catch {
      return fail(id, error.localizedDescription)
    }
    guard gate.accepts(id), phase == .starting else {
      await recognizer.cancel()
      return
    }
    startHost = hostClock()
    let router = MeetingAudioRouter(startHostTime: startHost, recognizer: recognizer) { [weak self] spans in
      Task { @MainActor in self?.addEcho(spans, id) }
    }
    self.router = router
    let microphone = makeMicrophone()
    self.microphone = microphone
    do {
      try microphone.start { [router] in router.handle($0, from: .me) }
    } catch {
      return fail(id, error.localizedDescription)
    }
    if let system = makeSystemAudio() {
      self.system = system
      do {
        try system.start { [router] in router.handle($0, from: .others) }
      } catch {
        self.system = nil
        notice = String(localized: "Other apps can't be heard: \(error.localizedDescription) Only your microphone is transcribed.")
      }
    } else {
      notice = String(localized: "Other apps can't be heard on this macOS version. Only your microphone is transcribed.")
    }
    startedAt = Date()
    phase = .live
    interfaceSounds?.play(.listening)
    // Five updates a second keep the level bars moving with the voices; the
    // limits are checked on the same beat.
    ticker = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(200))
        self?.tick()
      }
    }
  }

  /// Ends the recording and lets the recogniser finalise; the transcript stays.
  func stop(_ reason: String? = nil) {
    guard phase == .live || phase == .starting, let id = generation else { return }
    if let reason { notice = reason }
    let wasLive = phase == .live
    phase = .stopping
    systemAudioMissing = false
    stopSources()
    if wasLive { interfaceSounds?.play(.captured) }
    let recognizer = recognizer
    let previous = lifecycle
    lifecycle = Task { [weak self] in
      await previous?.value
      await recognizer?.finish()
      self?.router?.drain()
      guard let self, self.gate.accepts(id) else { return }
      self.recognizer = nil
      self.levels = [:]
      self.phase = .finished
    }
  }

  /// The Discard button: text that was neither copied nor saved is the only thing
  /// lost for good, so only then does it ask.
  func requestDiscard() {
    guard !hasUnsavedText || confirmLosingUnsaved(.discard) else { return }
    discard()
  }

  /// Throws everything away, including a running recording, and closes the window.
  func discard() {
    gate.cancel()
    generation = nil
    stopSources()
    let recognizer = recognizer
    self.recognizer = nil
    let previous = lifecycle
    lifecycle = Task {
      await previous?.value
      await recognizer?.cancel()
    }
    resetTranscript()
    notice = nil
    phase = .idle
    window?.close()
  }

  /// Quitting: release the devices immediately; the transcript dies with the process.
  func shutdown() {
    gate.cancel()
    stopSources()
    if let recognizer { Task { await recognizer.cancel() } }
    recognizer = nil
  }

  /// Returns whether something was copied, so the window can confirm it.
  @discardableResult func copy() -> Bool {
    guard !transcript.isEmpty else { return false }
    pasteboard.clearContents()
    pasteboard.setString(export.markdown, forType: .string)
    hasUnsavedText = false
    return true
  }

  /// Returns whether the file was written; a cancelled panel is not a save.
  @discardableResult func save() -> Bool {
    guard !transcript.isEmpty, saveExport(export, fileName) else { return false }
    hasUnsavedText = false
    return true
  }

  /// Copies the chat notice only because the user asked for it.
  func copyConsentNotice() {
    pasteboard.clearContents()
    pasteboard.setString(Self.consentNotice, forType: .string)
  }

  /// For tests: waits for start/stop work and the main-actor hops of results.
  func waitUntilSettled() async {
    await lifecycle?.value
    for _ in 0..<20 { await Task.yield() }
    await lifecycle?.value
  }

  // MARK: Live updates

  func tick() {
    guard phase == .live, let router else { return }
    elapsed = MeetingHostClock.seconds(hostClock() &- startHost)
    let state = router.state
    levels = state.level
    systemAudioMissing = system != nil && elapsed >= limits.systemAudioGrace && state.lastSignal[.others] == nil
    if elapsed >= limits.maximumDuration {
      return stop(String(localized: "The transcript stopped after 2 hours."))
    }
    let lastSound = state.lastSound.values.max() ?? 0
    if elapsed - lastSound >= limits.silence {
      return stop(String(localized: "The transcript stopped after 10 minutes without sound."))
    }
    if !warned, elapsed >= limits.maximumDuration - limits.warningLead {
      warned = true
      notice = String(localized: "The transcript stops in 5 minutes.")
    }
  }

  private func receive(_ result: MeetingRecognition, _ id: UUID) {
    guard gate.accepts(id) else { return }
    transcript.apply(result)
    if result.isFinal, !result.text.trimmingCharacters(in: .whitespaces).isEmpty { hasUnsavedText = true }
  }

  private func addEcho(_ spans: [ClosedRange<TimeInterval>], _ id: UUID) {
    guard gate.accepts(id) else { return }
    spans.forEach { transcript.addEcho($0) }
  }

  private func recognitionFailed(_ message: String, _ id: UUID) {
    guard gate.accepts(id) else { return }
    stop(String(localized: "Speech recognition stopped: \(message)"))
  }

  private func fail(_ id: UUID, _ message: String) {
    guard gate.accepts(id) else { return }
    stopSources()
    let recognizer = recognizer
    self.recognizer = nil
    Task { await recognizer?.cancel() }
    notice = message
    phase = transcript.isEmpty ? .consent : .finished
  }

  private func stopSources() {
    ticker?.cancel()
    ticker = nil
    microphone?.stop()
    system?.stop()
    router?.stop()
    microphone = nil
    system = nil
  }

  private func resetTranscript() {
    transcript = MeetingTranscript()
    hasUnsavedText = false
    elapsed = 0
    levels = [:]
    warned = false
    systemAudioMissing = false
    startedAt = nil
    router = nil
  }

  private var isUnavailable: Bool {
    if case .unavailable = phase { return true }
    return false
  }

  // MARK: Export

  private var title: String {
    let date = (startedAt ?? Date()).formatted(date: .abbreviated, time: .shortened)
    return String(localized: "Meeting transcript, \(date)")
  }

  /// The transcript as Copy and Save hand it on.
  var export: MeetingExport { MeetingExport(transcript: transcript, title: title, duration: elapsed) }

  /// Without an extension: the save panel adds the one of the chosen format.
  private var fileName: String {
    let date = (startedAt ?? Date()).formatted(.iso8601.year().month().day())
    return String(localized: "Meeting transcript \(date)")
  }

  /// The system save panel with a format menu, PDF first. Nothing is remembered
  /// between saves: the transcript adds no preference keys.
  static func saveWithPanel(_ export: MeetingExport, _ name: String) -> Bool {
    let panel = NSSavePanel()
    let chooser = MeetingFormatChooser(panel: panel, baseName: name)
    panel.accessoryView = chooser.view
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    guard panel.runModal() == .OK, let url = panel.url else { return false }
    do {
      try export.data(as: chooser.format).write(to: url, options: .atomic)
      return true
    } catch {
      NSAlert(error: error).runModal()
      return false
    }
  }

  static func confirmWithAlert(_ reason: LossReason) -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .warning
    switch reason {
    case .newTranscript:
      alert.messageText = String(localized: "Replace the unsaved transcript?")
      alert.addButton(withTitle: String(localized: "Start New Transcript"))
    case .discard:
      alert.messageText = String(localized: "Discard the unsaved transcript?")
      alert.addButton(withTitle: String(localized: "Discard"))
      alert.buttons.first?.hasDestructiveAction = true
    }
    alert.informativeText = String(localized: "It was neither copied nor saved and will be lost.")
    alert.addButton(withTitle: String(localized: "Cancel"))
    return alert.runModal() == .alertFirstButtonReturn
  }

  // MARK: Window

  func showWindow() {
    guard presentsWindow else { return }
    if window == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
        styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
      window.title = String(localized: "Meeting Transcript")
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 380, height: 360)
      window.contentViewController = NSHostingController(rootView: MeetingView(controller: self))
      // No frame autosave: the transcript adds no preference keys.
      window.center()
      self.window = window
    }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }
}

/// The "Format" menu below the save panel; switching it changes the file type and
/// the extension of the name being typed.
@MainActor
private final class MeetingFormatChooser: NSObject {
  private weak var panel: NSSavePanel?
  private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
  let view: NSView
  private(set) var format: MeetingExportFormat = .pdf

  init(panel: NSSavePanel, baseName: String) {
    self.panel = panel
    let label = NSTextField(labelWithString: String(localized: "Format:"))
    let stack = NSStackView(views: [label, popup])
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
    view = stack
    super.init()
    popup.addItems(withTitles: MeetingExportFormat.allCases.map(\.title))
    popup.target = self
    popup.action = #selector(changed)
    popup.setAccessibilityLabel(String(localized: "Format"))
    panel.allowedContentTypes = [format.contentType]
    panel.nameFieldStringValue = format.fileName(base: baseName)
  }

  @objc private func changed() {
    guard let panel, MeetingExportFormat.allCases.indices.contains(popup.indexOfSelectedItem) else { return }
    format = MeetingExportFormat.allCases[popup.indexOfSelectedItem]
    let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
    panel.allowedContentTypes = [format.contentType]
    panel.nameFieldStringValue = format.fileName(base: base)
  }
}
