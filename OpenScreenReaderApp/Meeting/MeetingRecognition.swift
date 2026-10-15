import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Whether a meeting transcript can start on this Mac, and in which language.
enum MeetingAvailability: Equatable, Sendable {
  case available(Locale)
  /// Needs macOS 26 and a Mac that supports Apple's on-device transcriber.
  case unsupportedSystem
  /// The language's speech assets are not installed; Saywing never downloads them.
  case languageMissing(String)
}

/// Creates recognisers and answers availability; replaced by a fake in tests.
@MainActor
protocol MeetingRecognizerProviding: AnyObject {
  func availability(for language: DictationLanguage) async -> MeetingAvailability
  func makeRecognizer() -> (any MeetingRecognizing)?
}

@MainActor
final class SystemMeetingRecognizerProvider: MeetingRecognizerProviding {
  func availability(for language: DictationLanguage) async -> MeetingAvailability {
    guard #available(macOS 26, *), SpeechTranscriber.isAvailable else { return .unsupportedSystem }
    let wanted = Self.locale(for: language)
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
      return .languageMissing(Self.name(of: wanted))
    }
    let installed = await SpeechTranscriber.installedLocales
    guard installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
      return .languageMissing(Self.name(of: locale))
    }
    return .available(locale)
  }

  func makeRecognizer() -> (any MeetingRecognizing)? {
    guard #available(macOS 26, *) else { return nil }
    return AppleMeetingRecognizer()
  }

  /// One language per transcript: the dictation choice, or the system language
  /// when it is German or English, otherwise English.
  static func locale(for language: DictationLanguage, system: Locale = .current) -> Locale {
    switch language {
    case .german: Locale(identifier: "de-DE")
    case .english: Locale(identifier: "en-US")
    case .automatic:
      system.language.languageCode?.identifier == "de" ? Locale(identifier: "de-DE") : Locale(identifier: "en-US")
    }
  }

  private static func name(of locale: Locale) -> String {
    Locale.current.localizedString(forLanguageCode: locale.language.languageCode?.identifier ?? "") ?? locale.identifier
  }
}

/// Apple's on-device `SpeechTranscriber`, one analyzer per track. Audio is converted
/// to the analyzer's format and stamped with its meeting-timeline position, so result
/// ranges of both tracks share one clock.
@available(macOS 26, *)
final class AppleMeetingRecognizer: MeetingRecognizing, @unchecked Sendable {
  private struct Track {
    let analyzer: SpeechAnalyzer
    let input: AsyncStream<AnalyzerInput>.Continuation
    let format: AVAudioFormat
    var converter: AVAudioConverter?
    var timeline: MeetingFrameTimeline
    let results: Task<Void, Never>
  }

  private let lock = NSLock()
  private var tracks: [MeetingSpeaker: Track] = [:]

  func start(
    locale: Locale, onResult: @escaping @Sendable (MeetingRecognition) -> Void,
    onFailure: @escaping @Sendable (String) -> Void
  ) async throws {
    // Tells the system Saywing uses this already installed language, so it keeps
    // the assets. Reserving downloads nothing; only an installation request would.
    _ = try? await AssetInventory.reserve(locale: locale)
    for speaker in MeetingSpeaker.allCases {
      let transcriber = SpeechTranscriber(
        locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults, .fastResults],
        attributeOptions: [])
      guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
        throw MeetingError(String(localized: "Speech recognition is not available on this Mac."))
      }
      let analyzer = SpeechAnalyzer(modules: [transcriber])
      let (stream, input) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(256))
      let results = Task {
        do {
          for try await result in transcriber.results {
            onResult(
              MeetingRecognition(
                speaker: speaker, start: result.range.start.seconds, end: result.range.end.seconds,
                text: String(result.text.characters), isFinal: result.isFinal))
          }
        } catch is CancellationError {
        } catch {
          onFailure(error.localizedDescription)
        }
      }
      try await analyzer.start(inputSequence: stream)
      lock.withLock {
        tracks[speaker] = Track(
          analyzer: analyzer, input: input, format: format, converter: nil,
          timeline: MeetingFrameTimeline(rate: format.sampleRate), results: results)
      }
    }
  }

  func append(_ chunk: MeetingAudioChunk, at time: TimeInterval, speaker: MeetingSpeaker) {
    lock.withLock {
      guard var track = tracks[speaker],
        let source = AVAudioFormat(standardFormatWithSampleRate: chunk.sampleRate, channels: 1),
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(chunk.samples.count))
      else { return }
      buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
      chunk.samples.withUnsafeBufferPointer { samples in
        buffer.floatChannelData?[0].update(from: samples.baseAddress!, count: samples.count)
      }
      if track.converter?.inputFormat.sampleRate != chunk.sampleRate {
        track.converter = AVAudioConverter(from: source, to: track.format)
      }
      guard let converter = track.converter else { return }
      let capacity = AVAudioFrameCount(Double(chunk.samples.count) * track.format.sampleRate / chunk.sampleRate) + 64
      guard let output = AVAudioPCMBuffer(pcmFormat: track.format, frameCapacity: capacity) else { return }
      var supplied = false
      var error: NSError?
      converter.convert(to: output, error: &error) { _, status in
        if supplied {
          status.pointee = .noDataNow
          return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
      }
      guard error == nil, output.frameLength > 0 else { return }
      // The analyzer rejects any overlap, and the resampler's output length varies a
      // little per call: stamp whole samples at the analyzer's own rate.
      let start = track.timeline.place(at: time, frames: Int(output.frameLength))
      tracks[speaker] = track
      track.input.yield(
        AnalyzerInput(buffer: output, bufferStartTime: CMTime(value: start, timescale: CMTimeScale(track.format.sampleRate))))
    }
  }

  func finish() async {
    let current = lock.withLock { tracks }
    for track in current.values { track.input.finish() }
    for track in current.values {
      let analyzer = track.analyzer
      let results = track.results
      // An analyzer that never received audio (a failed system tap) does not finish
      // on its own, and a failed input loop must not leave Stop waiting either.
      let heard = track.timeline.next != nil
      let finished =
        heard
        ? await MeetingDeadline.run(seconds: 10) {
          try? await analyzer.finalizeAndFinishThroughEndOfInput()
          await results.value
        } : false
      if !finished {
        results.cancel()
        _ = await MeetingDeadline.run(seconds: 2) { await analyzer.cancelAndFinishNow() }
      }
    }
    lock.withLock { tracks = [:] }
  }

  func cancel() async {
    let current = lock.withLock {
      let current = tracks
      tracks = [:]
      return current
    }
    for track in current.values {
      let analyzer = track.analyzer
      track.input.finish()
      track.results.cancel()
      _ = await MeetingDeadline.run(seconds: 2) { await analyzer.cancelAndFinishNow() }
    }
  }
}

enum MeetingDeadline {
  /// Runs `operation` and reports whether it finished within `seconds`. The
  /// operation keeps running after the deadline; the caller decides how to cut it off.
  static func run(seconds: Double, _ operation: @escaping @Sendable () async -> Void) async -> Bool {
    let decision = Decision()
    return await withCheckedContinuation { continuation in
      Task {
        await operation()
        if decision.claim() { continuation.resume(returning: true) }
      }
      Task {
        try? await Task.sleep(for: .seconds(seconds))
        if decision.claim() { continuation.resume(returning: false) }
      }
    }
  }

  private final class Decision: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func claim() -> Bool {
      lock.withLock {
        defer { taken = true }
        return !taken
      }
    }
  }
}
