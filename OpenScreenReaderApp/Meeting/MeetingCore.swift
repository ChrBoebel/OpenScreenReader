import Foundation

/// Who a line belongs to: the microphone is "Me", every other app's sound is "Others".
enum MeetingSpeaker: String, CaseIterable, Sendable {
  case me, others

  var label: String {
    switch self {
    case .me: String(localized: "Me")
    case .others: String(localized: "Others")
    }
  }
}

/// One recognition result, in seconds since the transcript started.
struct MeetingRecognition: Equatable, Sendable {
  let speaker: MeetingSpeaker
  let start: TimeInterval
  let end: TimeInterval
  let text: String
  let isFinal: Bool
}

/// A turn as shown: consecutive segments of one speaker, final text first and the
/// still-changing tail separately so it can be drawn quieter.
struct MeetingTranscriptEntry: Identifiable, Equatable {
  let speaker: MeetingSpeaker
  let start: TimeInterval
  let text: String
  let pending: String
  var id: String { "\(speaker.rawValue)-\(start)" }
}

/// The live transcript. It lives only in memory; nothing here touches disk.
struct MeetingTranscript: Equatable {
  private(set) var finals: [MeetingRecognition] = []
  private(set) var volatile: [MeetingSpeaker: MeetingRecognition] = [:]
  private(set) var echoSpans: [ClosedRange<TimeInterval>] = []

  /// Volatile results replace each other; a final result replaces them all.
  mutating func apply(_ recognition: MeetingRecognition) {
    let text = recognition.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard recognition.isFinal else {
      volatile[recognition.speaker] = text.isEmpty ? nil : recognition
      return
    }
    volatile[recognition.speaker] = nil
    guard !text.isEmpty else { return }
    let cleaned = MeetingRecognition(
      speaker: recognition.speaker, start: recognition.start, end: recognition.end, text: text,
      isFinal: true)
    let index = finals.firstIndex { $0.start > cleaned.start } ?? finals.endIndex
    finals.insert(cleaned, at: index)
  }

  /// Marks a stretch where the microphone only heard the others through the speakers.
  mutating func addEcho(_ span: ClosedRange<TimeInterval>) {
    var merged = span
    var kept: [ClosedRange<TimeInterval>] = []
    for existing in echoSpans {
      if existing.overlaps(merged) {
        merged = min(existing.lowerBound, merged.lowerBound)...max(existing.upperBound, merged.upperBound)
      } else {
        kept.append(existing)
      }
    }
    kept.append(merged)
    echoSpans = kept.sorted { $0.lowerBound < $1.lowerBound }
  }

  var isEmpty: Bool { entries.isEmpty }

  /// Visible turns in time order, without "Me" segments that were only an echo.
  var entries: [MeetingTranscriptEntry] {
    let items = (finals + volatile.values.sorted { $0.speaker.rawValue < $1.speaker.rawValue })
      .filter { !hides($0) }
      .sorted { $0.start < $1.start }
    var turns: [(speaker: MeetingSpeaker, start: TimeInterval, text: [String], pending: [String])] = []
    for item in items {
      if turns.last?.speaker != item.speaker {
        turns.append((item.speaker, item.start, [], []))
      }
      if item.isFinal { turns[turns.count - 1].text.append(item.text) } else { turns[turns.count - 1].pending.append(item.text) }
    }
    return turns.map {
      MeetingTranscriptEntry(
        speaker: $0.speaker, start: $0.start, text: $0.text.joined(separator: " "),
        pending: $0.pending.joined(separator: " "))
    }
  }

  /// Markdown for an explicit Copy or Save: speaker, time since start, text.
  func exportText(title: String) -> String {
    var lines = ["# \(title)", ""]
    for entry in entries {
      let text = [entry.text, entry.pending].filter { !$0.isEmpty }.joined(separator: " ")
      lines.append("**\(entry.speaker.label)** · \(MeetingClock.timestamp(entry.start))")
      lines.append(text)
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }

  private func hides(_ item: MeetingRecognition) -> Bool {
    guard item.speaker == .me else { return false }
    return echoFraction(of: item) >= 0.5 || repeatsOthers(item)
  }

  private func echoFraction(of item: MeetingRecognition) -> Double {
    let duration = max(item.end - item.start, 0.1)
    let covered = echoSpans.reduce(0.0) { sum, span in
      sum + max(0, min(span.upperBound, item.end) - max(span.lowerBound, item.start))
    }
    return covered / duration
  }

  /// Speaker bleed recognised twice: three or more words, nearly all of them in an
  /// "Others" segment from the same moment. Short replies like "ja" stay mine.
  private func repeatsOthers(_ item: MeetingRecognition) -> Bool {
    let words = Self.words(item.text)
    guard words.count >= 3 else { return false }
    return finals.contains { other in
      guard other.speaker == .others, other.start - 1.5 <= item.end, item.start <= other.end + 1.5 else {
        return false
      }
      let shared = words.intersection(Self.words(other.text)).count
      return Double(shared) / Double(words.count) >= 0.6
    }
  }

  private static func words(_ text: String) -> Set<String> {
    Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
  }
}

enum MeetingClock {
  /// "0:59" or "1:02:05" for the live header.
  static func elapsed(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
  }

  /// "00:01:05" next to each turn in an export.
  static func timestamp(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
  }
}

/// Places audio chunks on one gapless timeline per track. Delivery jitter of a few
/// milliseconds is absorbed; a real gap (a device change, a stall) jumps ahead.
/// Time never runs backwards, so recognition ranges stay comparable across tracks.
struct MeetingTimeline {
  private(set) var next: TimeInterval?
  var tolerance: TimeInterval = 0.05

  mutating func place(at time: TimeInterval, duration: TimeInterval) -> TimeInterval {
    let start: TimeInterval
    if let next {
      start = time > next + tolerance ? time : next
    } else {
      start = max(0, time)
    }
    next = start + duration
    return start
  }
}
