import Accelerate
import Foundation

/// Finds stretches where the microphone only hears the other participants through
/// the speakers. Both tracks arrive at 8 kHz on the shared meeting timeline; every
/// half second the last two seconds are cross-correlated. A strong peak at a delay
/// that keeps repeating is an echo: the room's path from speaker to microphone does
/// not move during a call. Once that delay is known, a single matching analysis is
/// enough, so short replies of the others are caught too. Spans cover only the
/// moments the others actually made sound, shifted by that delay plus a short
/// reverberation tail, so words of mine right after theirs stay mine.
///
/// Not thread-safe: the meeting pipeline calls it from one serial queue.
final class EchoGate {
  struct Configuration: Sendable {
    var sampleRate: Double = 8_000
    /// About two seconds per analysis.
    var window = 16_384
    /// A new analysis every half second.
    var hop = 4_000
    var energyFloor: Float = 0.003
    /// Normalised cross-correlation needed to call two windows related. Unrelated
    /// speech stays below 0.05; the starting value awaits calibration on real calls.
    var scoreFloor: Float = 0.2
    /// The microphone usually hears the speakers 20–300 ms later; timestamps of the
    /// two devices may be off by a little in either direction.
    var lagRange: ClosedRange<Double> = -0.2...0.6
    var lagTolerance: Double = 0.02
    /// Correlated analyses within `lagTolerance` needed among the last `history`.
    var agreeing = 5
    var history = 8
    /// Echo keeps ringing in the room for a moment after the others stop.
    var tail: TimeInterval = 0.5
    /// How long a found delay is trusted without new evidence.
    var lockMemory: TimeInterval = 30
  }

  private struct Analysis {
    let start: TimeInterval
    let end: TimeInterval
    let correlated: Bool
    let lag: TimeInterval
  }

  private struct Ring {
    private var buffer: [Float]
    private(set) var end = 0

    init(capacity: Int) { buffer = [Float](repeating: 0, count: capacity) }

    mutating func write(_ samples: [Float], at start: Int) {
      let capacity = buffer.count
      if start > end {
        let gap = min(start - end, capacity)
        for offset in 0..<gap { buffer[(start - gap + offset) % capacity] = 0 }
      }
      for (offset, sample) in samples.enumerated() { buffer[(start + offset) % capacity] = sample }
      end = max(end, start + samples.count)
    }

    func read(endingAt last: Int, count: Int) -> [Float] {
      let capacity = buffer.count
      return (0..<count).map { buffer[(last - count + $0) % capacity] }
    }
  }

  let configuration: Configuration
  /// The speaker-to-microphone delay of the current room, once found.
  private(set) var lockedLag: TimeInterval?
  private var lockedAt: TimeInterval = 0
  private var microphone: Ring
  private var system: Ring
  private var analysed = 0
  private var recent: [Analysis] = []
  /// When the others made sound, on the meeting timeline (the last minute).
  private var activity: [ClosedRange<TimeInterval>] = []
  private let size: Int
  private let forward: vDSP.DFT<Float>
  private let inverse: vDSP.DFT<Float>

  init(configuration: Configuration = Configuration()) {
    self.configuration = configuration
    let span = configuration.window
      + Int(configuration.lagRange.upperBound * configuration.sampleRate)
      + Int(-configuration.lagRange.lowerBound * configuration.sampleRate)
    var size = 1
    while size < span { size <<= 1 }
    self.size = size
    microphone = Ring(capacity: configuration.window * 2)
    system = Ring(capacity: configuration.window * 2)
    forward = vDSP.DFT(count: size, direction: .forward, transformType: .complexComplex, ofType: Float.self)!
    inverse = vDSP.DFT(count: size, direction: .inverse, transformType: .complexComplex, ofType: Float.self)!
  }

  /// Adds 8 kHz mono samples that begin at `time` seconds on the meeting timeline.
  /// Returns new echo spans, possibly reaching back to where the echo began.
  func append(_ samples: [Float], at time: TimeInterval, track: MeetingSpeaker) -> [ClosedRange<TimeInterval>] {
    let start = Int((time * configuration.sampleRate).rounded())
    switch track {
    case .me: microphone.write(samples, at: start)
    case .others:
      system.write(samples, at: start)
      if !samples.isEmpty, vDSP.rootMeanSquare(samples) >= configuration.energyFloor {
        noteActivity(time...(time + Double(samples.count) / configuration.sampleRate))
      }
    }
    let available = min(microphone.end, system.end)
    guard available >= configuration.window, available - analysed >= configuration.hop else { return [] }
    analysed = available
    return analyse(endingAt: available)
  }

  private func analyse(endingAt last: Int) -> [ClosedRange<TimeInterval>] {
    let rate = configuration.sampleRate
    let window = configuration.window
    let start = Double(last - window) / rate
    let end = Double(last) / rate
    let found = correlation(
      system: system.read(endingAt: last, count: window),
      microphone: microphone.read(endingAt: last, count: window))
    let analysis = Analysis(
      start: start, end: end, correlated: (found?.score ?? 0) >= configuration.scoreFloor, lag: found?.lag ?? 0)
    recent.append(analysis)
    if recent.count > configuration.history { recent.removeFirst(recent.count - configuration.history) }
    guard analysis.correlated else { return [] }

    let tolerance = configuration.lagTolerance
    if let locked = lockedLag, end - lockedAt <= configuration.lockMemory, abs(analysis.lag - locked) <= tolerance {
      lockedAt = end
      return echo(in: start...end, lag: analysis.lag)
    }
    let agreeing = recent.filter { $0.correlated && abs($0.lag - analysis.lag) <= tolerance }
    guard agreeing.count >= configuration.agreeing else { return [] }
    let lags = agreeing.map(\.lag).sorted()
    lockedLag = lags[lags.count / 2]
    lockedAt = end
    return agreeing.flatMap { echo(in: $0.start...$0.end, lag: $0.lag) }
  }

  /// The others' sound inside a correlated window, as the microphone heard it.
  private func echo(in window: ClosedRange<TimeInterval>, lag: TimeInterval) -> [ClosedRange<TimeInterval>] {
    activity.compactMap { sound in
      guard sound.overlaps(window) else { return nil }
      let from = max(sound.lowerBound, window.lowerBound) + lag
      let to = min(sound.upperBound, window.upperBound) + lag + configuration.tail
      return max(0, from)...max(0, to)
    }
  }

  private func noteActivity(_ span: ClosedRange<TimeInterval>) {
    if let last = activity.last, span.lowerBound <= last.upperBound + 0.05 {
      activity[activity.count - 1] = last.lowerBound...max(last.upperBound, span.upperBound)
    } else {
      activity.append(span)
    }
    let horizon = span.upperBound - 60
    activity.removeAll { $0.upperBound < horizon }
  }

  /// Strongest normalised correlation of the microphone against the system track,
  /// over the allowed delays (positive: the microphone hears it later).
  private func correlation(system x: [Float], microphone y: [Float]) -> (score: Float, lag: TimeInterval)? {
    let x = vDSP.add(-vDSP.mean(x), x)
    let y = vDSP.add(-vDSP.mean(y), y)
    let count = Float(x.count)
    guard vDSP.rootMeanSquare(x) >= configuration.energyFloor,
      vDSP.rootMeanSquare(y) >= configuration.energyFloor
    else { return nil }
    let norm = sqrt(vDSP.sumOfSquares(x) * vDSP.sumOfSquares(y))
    guard norm > 0, count > 0 else { return nil }

    let zeros = [Float](repeating: 0, count: size)
    let padding = [Float](repeating: 0, count: size - x.count)
    let first = forward.transform(inputReal: x + padding, inputImaginary: zeros)
    let second = forward.transform(inputReal: y + padding, inputImaginary: zeros)
    // conj(X) · Y gives Σ x[n] · y[n + k] after the inverse transform.
    let real = vDSP.add(vDSP.multiply(first.real, second.real), vDSP.multiply(first.imaginary, second.imaginary))
    let imaginary = vDSP.subtract(
      vDSP.multiply(first.real, second.imaginary), vDSP.multiply(first.imaginary, second.real))
    let lagged = inverse.transform(inputReal: real, inputImaginary: imaginary).real

    let rate = configuration.sampleRate
    let lowest = Int((configuration.lagRange.lowerBound * rate).rounded())
    let highest = Int((configuration.lagRange.upperBound * rate).rounded())
    var best: (score: Float, lag: Int) = (0, 0)
    for lag in lowest...highest {
      let value = abs(lagged[lag >= 0 ? lag : size + lag]) / (Float(size) * norm)
      if value > best.score { best = (value, lag) }
    }
    return (best.score, Double(best.lag) / rate)
  }
}
