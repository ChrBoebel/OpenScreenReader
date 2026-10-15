import AVFoundation
import Foundation

/// Recognises both tracks of a meeting. `append` is called from audio threads.
protocol MeetingRecognizing: AnyObject, Sendable {
  func start(
    locale: Locale, onResult: @escaping @Sendable (MeetingRecognition) -> Void,
    onFailure: @escaping @Sendable (String) -> Void) async throws
  /// A chunk of one track, already placed on the meeting timeline.
  func append(_ chunk: MeetingAudioChunk, at time: TimeInterval, speaker: MeetingSpeaker)
  /// Ends the input and waits until the last results are final.
  func finish() async
  func cancel() async
}

/// Routes chunks from both sources: onto one timeline, into the recogniser, and,
/// resampled to 8 kHz on its own queue, into the echo gate. It keeps only levels and
/// timestamps for the live window; audio is passed on and dropped.
final class MeetingAudioRouter: @unchecked Sendable {
  struct State: Sendable {
    var level: [MeetingSpeaker: Double] = [:]
    /// Last time a track carried audible sound, on the meeting timeline.
    var lastSound: [MeetingSpeaker: TimeInterval] = [:]
    /// Last time a track carried any non-zero sample. A denied system audio
    /// permission delivers exact zeros forever.
    var lastSignal: [MeetingSpeaker: TimeInterval] = [:]
  }

  private let startHostTime: UInt64
  private let recognizer: any MeetingRecognizing
  private let onEcho: @Sendable ([ClosedRange<TimeInterval>]) -> Void
  private let lock = NSLock()
  private var timelines: [MeetingSpeaker: MeetingTimeline] = [:]
  private var current = State()
  private var active = true
  private let gateQueue = DispatchQueue(label: "Saywing.meeting.echo-gate", qos: .utility)
  private let gate = EchoGate()
  private var converters: [MeetingSpeaker: AVAudioConverter] = [:]
  private let gateFormat = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!

  init(
    startHostTime: UInt64, recognizer: any MeetingRecognizing,
    onEcho: @escaping @Sendable ([ClosedRange<TimeInterval>]) -> Void
  ) {
    self.startHostTime = startHostTime
    self.recognizer = recognizer
    self.onEcho = onEcho
  }

  var state: State { lock.withLock { current } }

  func handle(_ chunk: MeetingAudioChunk, from speaker: MeetingSpeaker) {
    guard !chunk.samples.isEmpty, chunk.sampleRate > 0 else { return }
    let offset = chunk.hostTime >= startHostTime ? MeetingHostClock.seconds(chunk.hostTime - startHostTime) : 0
    let duration = Double(chunk.samples.count) / chunk.sampleRate
    let rms = sqrt(chunk.samples.reduce(0) { $0 + Double($1 * $1) } / Double(chunk.samples.count))
    let signal = chunk.samples.contains { $0 != 0 }
    let time: TimeInterval? = lock.withLock {
      guard active else { return nil }
      var timeline = timelines[speaker] ?? MeetingTimeline()
      let time = timeline.place(at: offset, duration: duration)
      timelines[speaker] = timeline
      current.level[speaker] = rms
      if rms >= 0.002 { current.lastSound[speaker] = time + duration }
      if signal { current.lastSignal[speaker] = time + duration }
      return time
    }
    guard let time else { return }
    recognizer.append(chunk, at: time, speaker: speaker)
    gateQueue.async { [self] in
      guard let samples = resample(chunk, for: speaker) else { return }
      let spans = gate.append(samples, at: time, track: speaker)
      if !spans.isEmpty { onEcho(spans) }
    }
  }

  /// Late chunks after this are ignored.
  func stop() { lock.withLock { active = false } }

  /// Waits until queued echo analysis has run; for tests and an orderly stop.
  func drain() { gateQueue.sync {} }

  private func resample(_ chunk: MeetingAudioChunk, for speaker: MeetingSpeaker) -> [Float]? {
    if chunk.sampleRate == gateFormat.sampleRate { return chunk.samples }
    if converters[speaker]?.inputFormat.sampleRate != chunk.sampleRate {
      converters[speaker] = AVAudioFormat(standardFormatWithSampleRate: chunk.sampleRate, channels: 1)
        .flatMap { AVAudioConverter(from: $0, to: gateFormat) }
    }
    guard let converter = converters[speaker],
      let output = MeetingResampler.convert(chunk.samples, with: converter),
      let data = output.floatChannelData
    else { return nil }
    return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
  }
}
