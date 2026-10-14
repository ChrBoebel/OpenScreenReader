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
    name = String(localized: "Test field")
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
        String(localized: "Allow Accessibility to dictate into other apps. The test field already works.")
      )
    }
    guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid()
    else {
      throw DictationError(
        String(localized: "Click in the test field or a text field in another app first."))
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.3)
    guard let field = axElement(axValue(root, kAXFocusedUIElementAttribute)) else {
      throw DictationError(String(localized: "No text field found. Click in a text field first."))
    }
    let subrole = axValue(field, kAXSubroleAttribute) as? String ?? ""
    guard !subrole.lowercased().contains("secure") else {
      throw DictationError(String(localized: "Saywing does not dictate into password fields."))
    }
    let role = axValue(field, kAXRoleAttribute) as? String ?? ""
    guard ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) else {
      throw DictationError(
        String(localized: "This kind of field is not supported yet. Use the test field instead."))
    }
    let value = axValue(field, kAXValueAttribute) as? String
    guard (value?.utf16.count ?? 0) <= 200000 else {
      throw DictationError(String(localized: "This text field is too large for dictation."))
    }
    return InsertionTarget(
      pid: app.processIdentifier, name: app.localizedName ?? String(localized: "Text field"), element: field,
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
  /// The insertion point in screen coordinates, so feedback appears where the
  /// text will land. Only geometry is read, never the field's contents.
  func caretRect() -> CGRect? {
    if let local, let selection {
      guard local.window != nil else { return nil }
      let rect = local.firstRect(forCharacterRange: NSRange(location: selection.location, length: 0), actualRange: nil)
      return rect.isEmpty && rect.origin == .zero ? nil : rect
    }
    guard let element else { return nil }
    AXUIElementSetMessagingTimeout(element, 0.3)
    var bounds: CFTypeRef?
    if let selection {
      var range = CFRange(location: selection.location, length: 0)
      if let value = AXValueCreate(.cfRange, &range),
        AXUIElementCopyParameterizedAttributeValue(
          element, kAXBoundsForRangeParameterizedAttribute as CFString, value, &bounds) == .success,
        let rect = Self.rect(bounds), rect.height > 0
      {
        return Self.screenRect(fromAccessibility: rect)
      }
    }
    // Some apps report no caret bounds; a small field's frame is the next best anchor.
    guard let position = axValue(element, kAXPositionAttribute), let size = axValue(element, kAXSizeAttribute),
      CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero, extent = CGSize.zero
    guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
      AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent), extent.height <= 120
    else { return nil }
    return Self.screenRect(fromAccessibility: CGRect(origin: origin, size: extent))
  }
  private static func rect(_ value: CFTypeRef?) -> CGRect? {
    guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    return AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) ? rect : nil
  }
  /// Accessibility geometry starts at the top left of the primary display.
  private static func screenRect(fromAccessibility rect: CGRect) -> CGRect? {
    guard let primary = NSScreen.screens.first else { return nil }
    return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
  }
  func paste() throws {
    guard isCurrent() else {
      throw DictationError(
        String(localized: "The target changed. The result stays available in the dictation window."))
    }
    if let local {
      local.paste(nil)
      return
    }
    guard let key = HotkeyShortcut.keyCode(for: "v", modifiers: UInt32(cmdKey)),
      let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(key), keyDown: false)
    else { throw DictationError(String(localized: "Paste could not be sent.")) }
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
/// One recording session; the controller only starts, levels, finishes or discards it.
@MainActor
protocol DictationRecording: AnyObject {
  /// The latest input level for the capsule bars, never the audio itself.
  var level: Double { get }
  func start() throws
  func finish() -> AudioPacket
  func cancel()
}
@MainActor
final class MicrophoneRecorder: DictationRecording {
  private let engine = AVAudioEngine()
  let audio = AudioAccumulator()
  private var installed = false
  var level: Double { audio.rms }
  func start() throws {
    let node = engine.inputNode
    let format = node.outputFormat(forBus: 0)
    guard (16000...192000).contains(format.sampleRate), format.channelCount > 0,
      format.channelCount <= 16, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved
    else { throw DictationError(String(localized: "This microphone format is not supported yet.")) }
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

/// Where the dictation capsule appears: just below the insertion point (above
/// it near the bottom of the screen), otherwise where the reading control is docked.
enum DictationCapsulePlacement {
  static func origin(caret: CGRect?, visible: CGRect, docked: CGRect, size: CGSize) -> CGPoint {
    func clamped(_ point: CGPoint) -> CGPoint {
      CGPoint(x: min(max(point.x, visible.minX + 4), visible.maxX - size.width - 4),
              y: min(max(point.y, visible.minY + 4), visible.maxY - size.height - 4))
    }
    guard let caret, visible.contains(CGPoint(x: caret.midX, y: caret.midY)) else {
      return clamped(CGPoint(x: docked.midX - size.width / 2, y: docked.midY - size.height / 2))
    }
    var y = caret.minY - size.height
    if y < visible.minY + 4 { y = caret.maxY }
    return clamped(CGPoint(x: caret.midX - size.width / 2, y: y))
  }
}

