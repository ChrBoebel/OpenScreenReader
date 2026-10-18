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
  /// The text in timed pieces (words, as the recogniser splits them), when known.
  var pieces: [MeetingPiece] = []
}

struct MeetingPiece: Equatable, Sendable {
  let text: String
  let start: TimeInterval
  let end: TimeInterval
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
      isFinal: true, pieces: recognition.pieces)
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

  /// Visible turns in time order. "Me" loses what was only the others through the
  /// speakers: whole segments inside an echo, words timed inside one, and runs of
  /// three or more words the others said at the same moment.
  var entries: [MeetingTranscriptEntry] {
    let items = (finals + volatile.values.sorted { $0.speaker.rawValue < $1.speaker.rawValue })
      .compactMap { item in visibleText(of: item).map { (item: item, text: $0) } }
      .sorted { $0.item.start < $1.item.start }
    var turns: [(speaker: MeetingSpeaker, start: TimeInterval, text: [String], pending: [String])] = []
    for (item, text) in items {
      if turns.last?.speaker != item.speaker {
        turns.append((item.speaker, item.start, [], []))
      }
      if item.isFinal { turns[turns.count - 1].text.append(text) } else { turns[turns.count - 1].pending.append(text) }
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

  private func visibleText(of item: MeetingRecognition) -> String? {
    guard item.speaker == .me else { return item.text }
    var text = item.text
    if !item.pieces.isEmpty {
      let kept = item.pieces.filter { !inEcho(($0.start + $0.end) / 2) }
      if kept.count < item.pieces.count {
        // Punctuation may come as its own piece; it attaches to the word before.
        text = kept.map(\.text).joined(separator: " ")
          .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
      }
    } else if echoFraction(of: item) >= 0.8 {
      return nil
    }
    let kept = withoutRepeatedRuns(Self.tokens(text), of: othersText(near: item))
    let result = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    return result.contains(where: { $0.isLetter || $0.isNumber }) ? result : nil
  }

  private func inEcho(_ time: TimeInterval) -> Bool {
    echoSpans.contains { $0.contains(time) }
  }

  private func echoFraction(of item: MeetingRecognition) -> Double {
    let duration = max(item.end - item.start, 0.1)
    let covered = echoSpans.reduce(0.0) { sum, span in
      sum + max(0, min(span.upperBound, item.end) - max(span.lowerBound, item.start))
    }
    return covered / duration
  }

  private func othersText(near item: MeetingRecognition) -> [String] {
    finals.filter { $0.speaker == .others && $0.start - 1.5 <= item.end && item.start <= $0.end + 1.5 }
      .flatMap { Self.tokens($0.text) }
  }

  /// Drops runs of three or more consecutive words that also appear, in order, in
  /// what the others said at the same moment. Single shared words ("ja", "und")
  /// stay: they are as likely mine.
  private func withoutRepeatedRuns(_ mine: [String], of others: [String]) -> [String] {
    guard mine.count >= 3, others.count >= 3 else { return mine }
    let a = mine.map(Self.normalized)
    let b = others.map(Self.normalized)
    var length = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
    for i in stride(from: a.count - 1, through: 0, by: -1) {
      for j in stride(from: b.count - 1, through: 0, by: -1) {
        length[i][j] = !a[i].isEmpty && a[i] == b[j]
          ? length[i + 1][j + 1] + 1 : max(length[i + 1][j], length[i][j + 1])
      }
    }
    var matched = Array(repeating: false, count: a.count)
    var (i, j) = (0, 0)
    while i < a.count, j < b.count {
      if !a[i].isEmpty, a[i] == b[j] {
        matched[i] = true
        i += 1
        j += 1
      } else if length[i + 1][j] >= length[i][j + 1] {
        i += 1
      } else {
        j += 1
      }
    }
    var drop = Array(repeating: false, count: a.count)
    var runStart = 0
    for index in 0...a.count {
      if index < a.count, matched[index] { continue }
      if index - runStart >= 3 { (runStart..<index).forEach { drop[$0] = true } }
      runStart = index + 1
    }
    return mine.enumerated().filter { !drop[$0.offset] }.map(\.element)
  }

  private static func tokens(_ text: String) -> [String] {
    text.split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func normalized(_ token: String) -> String {
    String(token.lowercased().filter { $0.isLetter || $0.isNumber })
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

/// The same rule in whole samples, for Apple's analyzer: it rejects input whose
/// stamp overlaps or precedes earlier input by even one tick.
struct MeetingFrameTimeline {
  let rate: Double
  private(set) var next: Int64?

  mutating func place(at time: TimeInterval, frames: Int) -> Int64 {
    let wanted = Int64((max(0, time) * rate).rounded())
    let tolerance = Int64(rate * 0.05)
    let start = next.map { wanted > $0 + tolerance ? wanted : $0 } ?? wanted
    next = start + Int64(frames)
    return start
  }
}
