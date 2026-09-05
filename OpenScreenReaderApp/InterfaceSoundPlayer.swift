import AppKit
import AVFoundation
import Foundation

/// One original, deterministic sound family: wood, glass and breath. Every cue
/// has a tactile strike, a harmonic body, a sub layer and a short stereo room.
/// No downloaded samples, no captured audio.
enum InterfaceCue: CaseIterable, Equatable {
    /// The captured frame lands as the control opens.
    case selection
    /// Everything was read.
    case completion
    /// No text or a failure that needs the user's attention.
    case attention
    /// The stop/close control was pressed.
    case tap
    /// The stop/close control was released.
    case release

    static let sampleRate = 44_100
    static let channels = 2

    /// Peak amplitude before the user's effect volume is applied.
    var peak: Float { self == .tap || self == .release ? 0.42 : 0.5 }

    /// Two voicings alternate so the tenth reading does not sound like the first.
    var variantCount: Int { self == .selection || self == .completion ? 2 : 1 }

    var samples: [Float] { render(variant: 0).mono }

    func render(variant: Int) -> CueRendering {
        var voice = CueSynthesizer(sampleRate: Self.sampleRate)
        let alternate = variant % variantCount == 1
        switch self {
        case .selection:
            // "Open": a breath in, a wooden tick with weight, then a rising fourth (or fifth).
            voice.breath(at: 0, duration: 0.16, gain: 0.16)
            voice.strike(at: 0.05, brightness: 2400, decay: 0.004, gain: 0.5)
            voice.sub(at: 0.05, frequency: 88, decay: 0.09, gain: 0.45)
            voice.pluck(at: 0.05, frequency: alternate ? 587.33 : 659.26, decay: 0.2, gain: 0.5)
            voice.pluck(at: 0.135, frequency: alternate ? 880 : 880, decay: 0.32, gain: 0.55, shimmer: true)
            voice.room(wet: 0.34, size: 0.24)
            return voice.render(duration: 0.7, peak: peak, fade: 0.08)
        case .completion:
            // "Done": a plucked major arpeggio landing on a bell with an octave shimmer.
            voice.strike(at: 0, brightness: 1900, decay: 0.003, gain: 0.3)
            voice.sub(at: 0, frequency: 82, decay: 0.16, gain: 0.35)
            voice.pluck(at: 0, frequency: 523.25, decay: 0.24, gain: 0.4)
            voice.pluck(at: 0.09, frequency: alternate ? 698.46 : 659.26, decay: 0.26, gain: 0.4)
            voice.bell(at: 0.18, frequency: 783.99, decay: 0.55, gain: 0.5)
            voice.bell(at: 0.32, frequency: 1567.98, decay: 0.5, gain: 0.14)
            voice.sub(at: 0.18, frequency: 98, decay: 0.3, gain: 0.22)
            voice.room(wet: 0.42, size: 0.32)
            return voice.render(duration: 1.2, peak: peak, fade: 0.1)
        case .attention:
            // "Hm": two muted wooden knocks that fall a minor third. Never a siren.
            voice.strike(at: 0, brightness: 1300, decay: 0.006, gain: 0.42)
            voice.sub(at: 0, frequency: 96, decay: 0.08, gain: 0.4)
            voice.pluck(at: 0, frequency: 587.33, decay: 0.13, gain: 0.4, muted: true)
            voice.strike(at: 0.15, brightness: 1300, decay: 0.006, gain: 0.38)
            voice.sub(at: 0.15, frequency: 80, decay: 0.12, gain: 0.45)
            voice.pluck(at: 0.15, frequency: 466.16, decay: 0.22, gain: 0.4, muted: true)
            voice.room(wet: 0.28, size: 0.2)
            return voice.render(duration: 0.65, peak: peak, fade: 0.08)
        case .tap:
            // Mechanical key down: bright click, low body, no ring.
            voice.strike(at: 0, brightness: 3400, decay: 0.003, gain: 0.55)
            voice.sub(at: 0, frequency: 160, decay: 0.02, gain: 0.5)
            voice.pluck(at: 0, frequency: 1760, decay: 0.012, gain: 0.2, muted: true)
            voice.room(wet: 0.06, size: 0.1)
            return voice.render(duration: 0.08, peak: peak, fade: 0.01)
        case .release:
            // Key up: softer, lower "tock".
            voice.strike(at: 0, brightness: 1800, decay: 0.004, gain: 0.4)
            voice.sub(at: 0, frequency: 120, decay: 0.03, gain: 0.5)
            voice.pluck(at: 0, frequency: 1174.66, decay: 0.014, gain: 0.16, muted: true)
            voice.room(wet: 0.06, size: 0.1)
            return voice.render(duration: 0.1, peak: peak, fade: 0.012)
        }
    }

    func wavData(variant: Int = 0) -> Data {
        let rendering = render(variant: variant)
        let frames = rendering.left.count
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + frames * 2 * Self.channels))
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(Self.channels))
        append(UInt32(Self.sampleRate)); append(UInt32(Self.sampleRate * 2 * Self.channels))
        append(UInt16(2 * Self.channels)); append(UInt16(16))
        data.append(contentsOf: "data".utf8)
        append(UInt32(frames * 2 * Self.channels))
        for index in 0..<frames {
            append(Int16(rendering.left[index] * Float(Int16.max)))
            append(Int16(rendering.right[index] * Float(Int16.max)))
        }
        return data
    }

    var wavData: Data { wavData(variant: 0) }
}

struct CueRendering: Equatable {
    let left: [Float]
    let right: [Float]
    var mono: [Float] { zip(left, right).map { ($0 + $1) / 2 } }
}

/// Deterministic additive/plucked synthesis with per-partial decay, a short
/// pitch settle on each onset, filtered-noise strikes, pitch-dropping sub hits,
/// a breath swell and a small stereo room built from early reflections and
/// two damped comb lines per channel.
struct CueSynthesizer {
    let sampleRate: Int
    private var voices: [(start: Int, samples: [Double])] = []
    private var wet = 0.0
    private var size = 0.2

    init(sampleRate: Int) { self.sampleRate = sampleRate }

    private var period: Double { 1 / Double(sampleRate) }

    mutating func pluck(at start: Double, frequency: Double, decay: Double, gain: Double,
                        muted: Bool = false, shimmer: Bool = false) {
        // Plucked-string colour: a strong fundamental, quickly fading upper partials, a touch of inharmonic sparkle.
        var partials: [(ratio: Double, gain: Double, decay: Double)] = muted
            ? [(1, 1, 1), (2, 0.14, 0.45), (3, 0.04, 0.35)]
            : [(1, 1, 1), (2, 0.42, 0.5), (3, 0.2, 0.38), (4, 0.09, 0.3), (5, 0.04, 0.25)]
        if shimmer { partials += [(2.02, 0.12, 0.6), (5.41, 0.04, 0.3)] }
        tone(at: start, frequency: frequency, decay: decay, gain: gain, partials: partials, settle: 0.02)
    }

    mutating func bell(at start: Double, frequency: Double, decay: Double, gain: Double) {
        // Slightly inharmonic glass partials with long decay.
        tone(at: start, frequency: frequency, decay: decay, gain: gain,
             partials: [(1, 1, 1), (2.0, 0.35, 0.7), (2.756, 0.2, 0.55), (4.07, 0.08, 0.4), (5.41, 0.05, 0.3)], settle: 0.006)
    }

    private mutating func tone(at start: Double, frequency: Double, decay: Double, gain: Double,
                               partials: [(ratio: Double, gain: Double, decay: Double)], settle: Double) {
        let length = Int(decay * 6 * Double(sampleRate))
        var buffer = [Double](repeating: 0, count: length)
        for index in 0..<length {
            let time = Double(index) * period
            let cycles = time + settle * 0.012 * (1 - exp(-time / 0.012))
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

    mutating func sub(at start: Double, frequency: Double, decay: Double, gain: Double) {
        let length = Int(decay * 6 * Double(sampleRate))
        var buffer = [Double](repeating: 0, count: length)
        var phase = 0.0
        for index in 0..<length {
            let time = Double(index) * period
            let instantaneous = frequency * (1 + 0.9 * exp(-time / (decay * 0.3)))
            phase += 2 * .pi * instantaneous * period
            let attack = time < 0.0015 ? time / 0.0015 : 1
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

    mutating func breath(at start: Double, duration: Double, gain: Double) {
        // A soft band-limited noise swell, like a small inhale before speaking.
        let length = Int(duration * Double(sampleRate))
        var buffer = [Double](repeating: 0, count: length)
        var seed: UInt32 = 0x9E37_79B9
        var low = 0.0, lower = 0.0
        let quick = 1 - exp(-2 * .pi * 1400 * period)
        let slow = 1 - exp(-2 * .pi * 500 * period)
        for index in 0..<length {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            low += (white - low) * quick
            lower += (white - lower) * slow
            let t = Double(index) / Double(length)
            let envelope = pow(sin(t * .pi), 1.6)
            buffer[index] = (low - lower) * envelope * gain * 2.5
        }
        voices.append((Int(start * Double(sampleRate)), buffer))
    }

    mutating func room(wet: Double, size: Double) {
        self.wet = wet
        self.size = size
    }

    func render(duration: Double, peak: Float, fade: Double) -> CueRendering {
        let count = Int(duration * Double(sampleRate))
        var dry = [Double](repeating: 0, count: count)
        for voice in voices {
            for (offset, value) in voice.samples.enumerated() where voice.start + offset < count {
                dry[voice.start + offset] += value
            }
        }
        for index in dry.indices { dry[index] = tanh(dry[index] * 1.25) }
        var left = dry
        var right = dry
        if wet > 0 {
            // Mirrored reflection patterns keep the image centred while decorrelating the sides.
            let leftRoom = reverb(dry, reflections: [(0.009, 0.6), (0.023, 0.35), (0.041, 0.3), (0.053, 0.2)], combs: [0.0297, 0.0389])
            let rightRoom = reverb(dry, reflections: [(0.014, 0.6), (0.019, 0.35), (0.035, 0.3), (0.061, 0.2)], combs: [0.0331, 0.0421])
            for index in 0..<count {
                left[index] += leftRoom[index] * wet
                right[index] += rightRoom[index] * wet
            }
        }
        // Deterministic peak normalisation across both channels, then a raised-cosine tail.
        let loudest = max(zip(left, right).map { max(abs($0), abs($1)) }.max() ?? 1, 1e-6)
        let scale = Double(peak) / loudest
        let fadeCount = min(count, Int(fade * Double(sampleRate)))
        func finish(_ channel: [Double]) -> [Float] {
            channel.enumerated().map { index, value in
                let remaining = Double(count - 1 - index) / Double(max(1, fadeCount))
                let tail = index >= count - fadeCount ? 0.5 - 0.5 * cos(.pi * remaining) : 1
                return index == 0 ? 0 : Float(value * scale * tail)
            }
        }
        return CueRendering(left: finish(left), right: finish(right))
    }

    private func reverb(_ input: [Double], reflections: [(delay: Double, gain: Double)], combs: [Double]) -> [Double] {
        let count = input.count
        var output = [Double](repeating: 0, count: count)
        for reflection in reflections {
            let delay = Int(reflection.delay * Double(sampleRate))
            for index in delay..<count { output[index] += input[index - delay] * reflection.gain }
        }
        // Two damped feedback combs give the tail; `size` sets how long it rings.
        let feedback = 0.45 + size * 0.9
        for comb in combs {
            let delay = Int(comb * Double(sampleRate))
            var line = [Double](repeating: 0, count: count)
            var damped = 0.0
            for index in 0..<count {
                let delayed = index >= delay ? line[index - delay] : 0
                damped += (delayed - damped) * 0.35
                line[index] = input[index] * 0.5 + damped * feedback
                output[index] += line[index] * 0.6
            }
        }
        return output
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
    static let defaultVolume = 0.7
    static var defaults: UserDefaults {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["OSR_SHORTCUT_TEST_SUITE"],
           suite.hasPrefix("com.christopherbobel.OpenScreenReader.uitests."),
           let defaults = UserDefaults(suiteName: suite) { return defaults }
        #endif
        return .standard
    }
    private let preferences: UserDefaults
    private var players: [InterfaceCue: [AVAudioPlayer]] = [:]
    private var turns: [InterfaceCue: Int] = [:]
    private var current: AVAudioPlayer?

    init(defaults: UserDefaults = InterfaceSoundPlayer.defaults) {
        preferences = defaults
        // Failure is silent: interface sounds never block OCR, speech or cancellation.
        for cue in InterfaceCue.allCases {
            players[cue] = (0..<cue.variantCount).compactMap { variant in
                guard let player = try? AVAudioPlayer(data: cue.wavData(variant: variant)) else { return nil }
                player.prepareToPlay()
                return player
            }
        }
    }
    isolated deinit { stop() }

    func play(_ cue: InterfaceCue) {
        // Key clicks never interrupt a cue, and a cancellation never cuts them off.
        let isClick = cue == .tap || cue == .release
        if !isClick { stop() }
        guard preferences.object(forKey: Self.preferenceKey) as? Bool ?? true,
              let variants = players[cue], !variants.isEmpty else { return }
        let turn = turns[cue, default: 0]
        turns[cue] = turn + 1
        let player = variants[turn % variants.count]
        let volume = preferences.object(forKey: Self.volumeKey) as? Double ?? Self.defaultVolume
        player.stop()
        player.currentTime = 0
        player.volume = Float(volume.isFinite ? min(1, max(0, volume)) : Self.defaultVolume) * (isClick ? 0.8 : 1)
        player.play()
        if !isClick { current = player }
    }

    func stop() { current?.stop(); current = nil }
}
