import AppKit
import AVFoundation
import Foundation

/// One original, deterministic sound family: a soft tactile strike, a warm
/// harmonic body and a short tail. No downloaded samples, no captured audio.
enum InterfaceCue: CaseIterable, Equatable {
    /// Capture finished, the reading control opens.
    case selection
    /// Everything was read.
    case completion
    /// No text or a failure that needs the user's attention.
    case attention
    /// The stop/close control was pressed.
    case tap

    static let sampleRate = 44_100

    /// Peak amplitude before the user's effect volume is applied.
    var peak: Float { self == .tap ? 0.42 : 0.5 }

    var samples: [Float] {
        var voice = CueSynthesizer(sampleRate: Self.sampleRate)
        switch self {
        case .selection:
            // "Open": a tactile tick with weight, then a rising perfect fourth.
            voice.strike(at: 0, brightness: 2600, decay: 0.004, gain: 0.5)
            voice.thump(at: 0, frequency: 150, decay: 0.05, gain: 0.32)
            voice.note(at: 0, frequency: 659.26, decay: 0.16, gain: 0.42)
            voice.note(at: 0.075, frequency: 880, decay: 0.24, gain: 0.46)
        case .completion:
            // "Done": a quick major arpeggio that lands on a ringing, bell-like fifth.
            voice.strike(at: 0, brightness: 2000, decay: 0.003, gain: 0.3)
            voice.note(at: 0, frequency: 523.25, decay: 0.2, gain: 0.34)
            voice.note(at: 0.09, frequency: 659.26, decay: 0.22, gain: 0.34)
            voice.note(at: 0.18, frequency: 783.99, decay: 0.42, gain: 0.44, shimmer: true)
            voice.thump(at: 0.18, frequency: 196, decay: 0.25, gain: 0.16)
        case .attention:
            // "Hm": two muted wooden knocks that fall a minor third. Never a siren.
            voice.strike(at: 0, brightness: 1400, decay: 0.006, gain: 0.4)
            voice.note(at: 0, frequency: 587.33, decay: 0.12, gain: 0.34, muted: true)
            voice.strike(at: 0.14, brightness: 1400, decay: 0.006, gain: 0.36)
            voice.note(at: 0.14, frequency: 466.16, decay: 0.2, gain: 0.34, muted: true)
            voice.thump(at: 0.14, frequency: 116, decay: 0.12, gain: 0.2)
        case .tap:
            // Mechanical key feel: bright click, low body, no ring.
            voice.strike(at: 0, brightness: 3200, decay: 0.003, gain: 0.55)
            voice.thump(at: 0, frequency: 210, decay: 0.022, gain: 0.5)
            voice.note(at: 0, frequency: 1760, decay: 0.012, gain: 0.2, muted: true)
        }
        let duration = self == .selection ? 0.42 : self == .completion ? 0.76 : self == .attention ? 0.46 : 0.06
        // The tail fades over natural decay, not a cut: 60 ms raised cosine, 8 ms for the tap.
        return voice.render(duration: duration, peak: peak, fade: self == .tap ? 0.008 : 0.06)
    }

    var wavData: Data {
        let pcm = samples
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(Self.sampleRate)); append(UInt32(Self.sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(pcm.count * 2))
        for sample in pcm { append(Int16(sample * Float(Int16.max))) }
        return data
    }
}

/// Additive synthesis with per-partial decay, a short pitch settle on each
/// onset, filtered-noise strikes and pitch-dropping thumps. Fully deterministic.
struct CueSynthesizer {
    let sampleRate: Int
    private var voices: [(start: Int, samples: [Double])] = []

    init(sampleRate: Int) { self.sampleRate = sampleRate }

    private var period: Double { 1 / Double(sampleRate) }

    mutating func note(at start: Double, frequency: Double, decay: Double, gain: Double,
                       muted: Bool = false, shimmer: Bool = false) {
        var partials: [(ratio: Double, gain: Double, decay: Double)] = muted
            ? [(1, 1, 1), (2, 0.12, 0.5), (3, 0.03, 0.4)]
            : [(1, 1, 1), (2, 0.28, 0.6), (3, 0.1, 0.45), (4, 0.045, 0.3)]
        if shimmer { partials += [(2.756, 0.08, 0.5), (5.41, 0.05, 0.35)] }
        let length = Int(decay * 6 * Double(sampleRate))
        var buffer = [Double](repeating: 0, count: length)
        for index in 0..<length {
            let time = Double(index) * period
            // A 1.5 % pitch settle over the first 12 ms keeps the onset organic.
            let cycles = time + 0.015 * 0.012 * (1 - exp(-time / 0.012))
            let attack = time < 0.003 ? 0.5 - 0.5 * cos(.pi * time / 0.003) : 1
            var value = 0.0
            for partial in partials {
                value += sin(2 * .pi * frequency * partial.ratio * cycles) * partial.gain
                    * exp(-time / (decay * partial.decay))
            }
            buffer[index] = value * attack * gain
        }
        voices.append((Int(start * Double(sampleRate)), buffer))
    }

    mutating func thump(at start: Double, frequency: Double, decay: Double, gain: Double) {
        let length = Int(decay * 6 * Double(sampleRate))
        var buffer = [Double](repeating: 0, count: length)
        var phase = 0.0
        for index in 0..<length {
            let time = Double(index) * period
            let instantaneous = frequency * (1 + 0.6 * exp(-time / (decay * 0.35)))
            phase += 2 * .pi * instantaneous * period
            let attack = time < 0.001 ? time / 0.001 : 1
            buffer[index] = sin(phase) * exp(-time / decay) * attack * gain
        }
        voices.append((Int(start * Double(sampleRate)), buffer))
    }

    mutating func strike(at start: Double, brightness: Double, decay: Double, gain: Double) {
        let length = Int(decay * 8 * Double(sampleRate))
        var buffer = [Double](repeating: 0, count: length)
        var seed: UInt32 = 0x2545_F491
        var low = 0.0, lower = 0.0
        let quick = 1 - exp(-2 * .pi * brightness * period)
        let slow = 1 - exp(-2 * .pi * brightness * 0.25 * period)
        for index in 0..<length {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            low += (white - low) * quick
            lower += (white - lower) * slow
            let time = Double(index) * period
            let attack = time < 0.0005 ? time / 0.0005 : 1
            buffer[index] = (low - lower) * exp(-time / decay) * attack * gain * 2.2
        }
        voices.append((Int(start * Double(sampleRate)), buffer))
    }

    func render(duration: Double, peak: Float, fade: Double) -> [Float] {
        let count = Int(duration * Double(sampleRate))
        var mix = [Double](repeating: 0, count: count)
        for voice in voices {
            for (offset, value) in voice.samples.enumerated() where voice.start + offset < count {
                mix[voice.start + offset] += value
            }
        }
        // Gentle saturation for warmth, then a deterministic peak normalisation.
        for index in mix.indices { mix[index] = tanh(mix[index] * 1.25) }
        let loudest = max(mix.map { abs($0) }.max() ?? 1, 1e-6)
        let scale = Double(peak) / loudest
        let fadeCount = min(count, Int(fade * Double(sampleRate)))
        return mix.enumerated().map { index, value in
            let remaining = Double(count - 1 - index) / Double(fadeCount)
            let tail = index >= count - fadeCount ? 0.5 - 0.5 * cos(.pi * remaining) : 1
            return index == 0 ? 0 : Float(value * scale * tail)
        }
    }
}

@MainActor
protocol InterfaceSoundPlaying: AnyObject {
    func play(_ cue: InterfaceCue)
    func stop()
}

@MainActor
final class InterfaceSoundPlayer: InterfaceSoundPlaying {
    static let preferenceKey = "interfaceSoundsEnabled.v1"
    static let volumeKey = "interfaceSoundsVolume.v1"
    static let defaultVolume = 0.6
    static var defaults: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["OSR_SHORTCUT_TEST_SUITE"],
           suite.hasPrefix("com.christopherbobel.OpenScreenReader.uitests."),
           let defaults = UserDefaults(suiteName: suite) { return defaults }
        #endif
        return .standard
    }
    private let preferences: UserDefaults
    private var players: [InterfaceCue: AVAudioPlayer] = [:]
    private var current: AVAudioPlayer?

    init(defaults: UserDefaults = InterfaceSoundPlayer.defaults) {
        preferences = defaults
        // Failure is silent: interface sounds never block OCR, speech or cancellation.
        for cue in InterfaceCue.allCases {
            guard let player = try? AVAudioPlayer(data: cue.wavData) else { continue }
            player.prepareToPlay()
            players[cue] = player
        }
    }
    isolated deinit { stop() }

    func play(_ cue: InterfaceCue) {
        // A tap is a control click: it never interrupts a cue and a cancellation never cuts it off.
        if cue != .tap { stop() }
        guard preferences.object(forKey: Self.preferenceKey) as? Bool ?? true,
              let player = players[cue] else { return }
        let volume = preferences.object(forKey: Self.volumeKey) as? Double ?? Self.defaultVolume
        player.stop()
        player.currentTime = 0
        player.volume = Float(volume.isFinite ? min(1, max(0, volume)) : Self.defaultVolume) * (cue == .tap ? 0.85 : 1)
        player.play()
        if cue != .tap { current = player }
    }

    func stop() { current?.stop(); current = nil }
}
