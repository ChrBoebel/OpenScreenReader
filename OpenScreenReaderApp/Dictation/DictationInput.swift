import AVFoundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

func axValue(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
  var value: CFTypeRef?
  return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func axElement(_ value: CFTypeRef?) -> AXUIElement? {
  guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
  return unsafeDowncast(value, to: AXUIElement.self)
}
func selectedRange(_ element: AXUIElement) -> NSRange? {
  guard let value = axValue(element, kAXSelectedTextRangeAttribute),
    CFGetTypeID(value) == AXValueGetTypeID()
  else { return nil }
  var range = CFRange()
  guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) else {
    return nil
  }
  return NSRange(location: range.location, length: range.length)
}
@MainActor
final class InsertionTarget {
  let pid: pid_t
  let name: String
  private let local: NSTextView?
  private let element: AXUIElement?
  private let window: AXUIElement?
  private let original: String?
  private let selection: NSRange?
  init(local: NSTextView) {
    pid = getpid()
    name = "Testfeld"
    self.local = local
    element = nil
    window = nil
    original = local.string
    selection = local.selectedRange()
  }
  private init(
    pid: pid_t, name: String, element: AXUIElement, window: AXUIElement?, original: String?,
    selection: NSRange?
  ) {
    self.pid = pid
    self.name = name
    self.element = element
    self.window = window
    self.original = original
    self.selection = selection
    local = nil
  }
  static func capture(scratch: NSTextView) throws -> InsertionTarget {
    if scratch.window?.isKeyWindow == true,
      scratch.window?.firstResponder === scratch
    {
      return InsertionTarget(local: scratch)
    }
    guard AXIsProcessTrusted() else {
      throw DictationError(
        "Für andere Apps bitte Bedienungshilfen freigeben. Das eigene Testfeld funktioniert bereits."
      )
    }
    guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid()
    else {
      throw DictationError(
        "Bitte zuerst in das Testfeld oder ein Textfeld einer anderen App klicken.")
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.3)
    guard let field = axElement(axValue(root, kAXFocusedUIElementAttribute)) else {
      throw DictationError("Kein Textfeld erkannt. Bitte ein Textfeld auswählen.")
    }
    let subrole = axValue(field, kAXSubroleAttribute) as? String ?? ""
    guard !subrole.lowercased().contains("secure") else {
      throw DictationError("In Passwortfelder wird nicht diktiert.")
    }
    let role = axValue(field, kAXRoleAttribute) as? String ?? ""
    guard ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else {
      throw DictationError(
        "Dieses Feld wird noch nicht erkannt. Bitte das eigene Testfeld verwenden.")
    }
    let value = axValue(field, kAXValueAttribute) as? String
    guard (value?.utf16.count ?? 0) <= 200000 else {
      throw DictationError("Das Ziel ist für diesen Diktierfenster zu groß.")
    }
    return InsertionTarget(
      pid: app.processIdentifier, name: app.localizedName ?? "Textfeld", element: field,
      window: axElement(axValue(root, kAXFocusedWindowAttribute)), original: value,
      selection: selectedRange(field))
  }
  func isCurrent() -> Bool {
    // The scratch field is an explicit in-process destination: paste is sent to
    // this NSTextView, never to the foreground app. It can finish in the background.
    if let local {
      return local.window?.firstResponder === local && local.string == original
        && local.selectedRange() == selection
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
    guard let element else { return false }
    let role = axValue(element, kAXRoleAttribute) as? String ?? ""
    let subrole = axValue(element, kAXSubroleAttribute) as? String ?? ""
    guard ["AXTextField", "AXTextArea", "AXComboBox"].contains(role),
      !subrole.lowercased().contains("secure")
    else { return false }
    let root = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(root, 0.3)
    guard let focused = axElement(axValue(root, kAXFocusedUIElementAttribute)),
      CFEqual(focused, element)
    else { return false }
    if let window {
      guard let focusedWindow = axElement(axValue(root, kAXFocusedWindowAttribute)),
        CFEqual(window, focusedWindow)
      else { return false }
    }
    if let original, axValue(element, kAXValueAttribute) as? String != original { return false }
    if let selection, selectedRange(element) != selection { return false }
    return true
  }
  func paste() throws {
    guard isCurrent() else {
      throw DictationError(
        "Das Ziel hat sich geändert. Das Ergebnis bleibt im Diktierfenster verfügbar.")
    }
    if let local {
      local.paste(nil)
      return
    }
    guard let key = HotkeyShortcut.keyCode(for: "v", modifiers: UInt32(cmdKey)),
      let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false)
    else { throw DictationError("Einfügen konnte nicht ausgelöst werden.") }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.postToPid(pid)
    up.postToPid(pid)
  }
  func confirms(_ text: String) -> Bool {
    guard let original, let selection, selection.location <= original.utf16.count,
      selection.length <= original.utf16.count - selection.location
    else { return false }
    let expected = (original as NSString).replacingCharacters(in: selection, with: text)
    let actual = local?.string ?? element.flatMap { axValue($0, kAXValueAttribute) as? String }
    return actual == expected
  }
}
@MainActor
final class MicrophoneRecorder {
  private let engine = AVAudioEngine()
  let audio = AudioAccumulator()
  private var installed = false
  func start() throws {
    let node = engine.inputNode
    let format = node.outputFormat(forBus: 0)
    guard (16000...192000).contains(format.sampleRate), format.channelCount > 0,
      format.channelCount <= 16, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved
    else { throw DictationError("Dieses Mikrofonformat wird noch nicht unterstützt.") }
    audio.start(sampleRate: format.sampleRate)
    node.installTap(onBus: 0, bufferSize: 2048, format: format, block: makeInputTap())
    installed = true
    do {
      engine.prepare()
      try engine.start()
    } catch {
      cancel()
      throw error
    }
  }
  func makeInputTap() -> AVAudioNodeTapBlock {
    Self.makeInputTap(audio: audio)
  }
  // AVAudioEngine invokes this on its audio queue, never the MainActor. Create
  // the callback outside actor isolation and capture only the locked accumulator.
  // Consume PCM synchronously: AVAudioEngine owns the buffer's lifetime.
  nonisolated private static func makeInputTap(audio: AudioAccumulator) -> AVAudioNodeTapBlock {
    { @Sendable [audio] buffer, _ in
      guard let channels = buffer.floatChannelData else { return }
      let n = Int(buffer.frameLength)
      let count = Int(buffer.format.channelCount)
      var mono = [Float](repeating: 0, count: n)
      for frame in 0..<n {
        var sum: Float = 0
        for channel in 0..<count { sum += channels[channel][frame] }
        mono[frame] = sum / Float(count)
      }
      audio.append(mono)
    }
  }
  func finish() -> AudioPacket {
    if installed {
      engine.inputNode.removeTap(onBus: 0)
      installed = false
    }
    engine.stop()
    return audio.finish()
  }
  func cancel() {
    if installed {
      engine.inputNode.removeTap(onBus: 0)
      installed = false
    }
    engine.stop()
    audio.cancel()
  }
}
