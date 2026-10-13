import AppKit

enum DictationModel: String, CaseIterable, Sendable {
  case qwen = "qwen3-asr"
  case whisperTurbo = "whisper-turbo"

  var displayName: String {
    switch self {
    case .qwen: "Qwen3-ASR"
    case .whisperTurbo: "Whisper Turbo"
    }
  }
}

struct DictationError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
  init(_ message: String) { self.message = message }
}
@MainActor
final class GenerationGate {
  private var current: UUID?
  func begin() -> UUID {
    let id = UUID()
    current = id
    return id
  }
  func cancel() { current = nil }
  func accepts(_ id: UUID) -> Bool { current == id }
}
@MainActor
struct ClipboardSnapshot: Equatable {
  let items: [[String: Data]]
  static func capture(_ board: NSPasteboard, limit: Int = 16 * 1024 * 1024) throws -> Self {
    let count = board.changeCount
    var size = 0
    var result = [[String: Data]]()
    for item in board.pasteboardItems ?? [] {
      var types = [String: Data]()
      for type in item.types {
        guard let data = item.data(forType: type) else {
          throw DictationError(
            "Die Zwischenablage enthält nicht sicher wiederherstellbare Daten. Bitte das Ergebnis manuell kopieren."
          )
        }
        size += data.count
        guard size <= limit else {
          throw DictationError(
            "Die Zwischenablage ist größer als 16 MB. Sie bleibt unverändert; das Ergebnis kann manuell kopiert werden."
          )
        }
        types[type.rawValue] = data
      }
      result.append(types)
    }
    guard board.changeCount == count else {
      throw DictationError("Zwischenablage hat sich geändert. Bitte erneut versuchen.")
    }
    return Self(items: result)
  }
  func write(to board: NSPasteboard) -> Bool {
    let objects = items.map { types -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in types { item.setData(data, forType: .init(type)) }
      return item
    }
    board.clearContents()
    return objects.isEmpty || board.writeObjects(objects)
  }
}
@MainActor
final class ClipboardLease {
  private let board: NSPasteboard
  private var original: ClipboardSnapshot?
  private let ownedCount: Int
  private let marker: String
  private static let markerType = NSPasteboard.PasteboardType("local.qwen.dictation.transient")
  private init(board: NSPasteboard, original: ClipboardSnapshot, ownedCount: Int, marker: String) {
    self.board = board
    self.original = original
    self.ownedCount = ownedCount
    self.marker = marker
  }
  static func begin(_ text: String, on board: NSPasteboard) throws -> ClipboardLease {
    let count = board.changeCount
    let original = try ClipboardSnapshot.capture(board)
    let marker = UUID().uuidString
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setString(marker, forType: markerType)
    item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    guard board.changeCount == count else {
      throw DictationError("Zwischenablage wurde während der Vorbereitung geändert.")
    }
    board.clearContents()
    guard board.writeObjects([item]) else {
      _ = original.write(to: board)
      throw DictationError("Zwischenablage konnte nicht vorbereitet werden.")
    }
    return ClipboardLease(
      board: board, original: original, ownedCount: board.changeCount, marker: marker)
  }
  @discardableResult func restore() -> Bool {
    guard let saved = original else { return false }
    original = nil
    guard board.changeCount == ownedCount, board.string(forType: Self.markerType) == marker else {
      return false
    }
    return saved.write(to: board)
  }
}
struct AudioPacket: Sendable {
  let samples: [Float]
  let rate: Double
}
final class AudioAccumulator: @unchecked Sendable {
  private let lock = NSLock()
  private var samples = [Float]()
  private var rate = 16000.0
  private var active = false
  private var level: Double = 0
  func start(sampleRate: Double) {
    lock.lock()
    defer { lock.unlock() }
    samples = []
    rate = sampleRate
    active = true
    level = 0
  }
  func append(_ chunk: [Float]) {
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }
    let remaining = max(0, Int(rate * 60) - samples.count)
    samples.append(contentsOf: chunk.prefix(remaining))
    level = chunk.isEmpty ? 0 : sqrt(chunk.reduce(0) { $0 + Double($1 * $1) } / Double(chunk.count))
  }
  var rms: Double {
    lock.lock()
    defer { lock.unlock() }
    return level
  }
  func finish() -> AudioPacket {
    lock.lock()
    defer { lock.unlock() }
    active = false
    let out = AudioPacket(samples: samples, rate: rate)
    samples = []
    level = 0
    return out
  }
  func cancel() {
    lock.lock()
    defer { lock.unlock() }
    active = false
    samples = []
    level = 0
  }
}
