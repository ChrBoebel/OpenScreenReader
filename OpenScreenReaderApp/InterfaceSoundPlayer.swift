import AppKit
import AVFoundation
import Foundation

/// One original, deterministic sound family: wood and water. Marimba-style bars
/// with 1 : 4 : 10 partials give weight and warmth, entrained-bubble water drops
/// give the bright, satisfying moments, a low log-drum thud sits underneath and a
/// small stereo room ties it together. No downloaded samples, no captured audio.
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
            // Landing: a log-drum thud, two rising marimba bars and one water drop on the second.
            voice.thud(at: 0, frequency: 100, decay: 0.12, gain: 0.55)
            voice.bar(at: 0, frequency: alternate ? 220 : 196, decay: 0.45, gain: 0.7, hardness: 0.55)
            voice.bar(at: 0.085, frequency: alternate ? 293.66 : 261.63, decay: 0.6, gain: 0.75, hardness: 0.45)
            voice.drop(at: 0.085, frequency: alternate ? 800 : 720, rise: 1.5, decay: 0.06, gain: 0.5, seed: 5)
            voice.room(wet: 0.32, size: 0.4)
            return voice.render(duration: 0.9, peak: peak, fade: 0.08)
        case .completion:
            // Done: a deep marimba root, a cascade of five rising water drops, a closing bar.
            voice.thud(at: 0, frequency: 80, decay: 0.18, gain: 0.45)
            voice.bar(at: 0, frequency: 130.81, decay: 1.0, gain: 0.6, hardness: 0.3)
            let drops: [Double] = alternate ? [349.23, 440, 523.25, 698.46, 880] : [330, 440, 550, 660, 880]
            for (index, frequency) in drops.enumerated() {
                voice.drop(at: 0.05 + Double(index) * 0.085, frequency: frequency, rise: 1.45, decay: 0.09,
                           gain: 0.55 - Double(index) * 0.04, seed: 40 + index)
            }
            voice.bar(at: 0.47, frequency: alternate ? 349.23 : 261.63, decay: 0.8, gain: 0.5, hardness: 0.35)
            voice.room(wet: 0.45, size: 0.55)
            return voice.render(duration: 1.5, peak: peak, fade: 0.1)
        case .attention:
            // Hm: two muted wooden knocks that fall a major third, with a little weight. Never a siren.
            voice.bar(at: 0, frequency: 293.66, decay: 0.12, gain: 0.8, hardness: 0.6)
            voice.thud(at: 0, frequency: 90, decay: 0.09, gain: 0.3)
            voice.bar(at: 0.16, frequency: 233.08, decay: 0.2, gain: 0.8, hardness: 0.55)
            voice.thud(at: 0.16, frequency: 75, decay: 0.11, gain: 0.35)
            voice.room(wet: 0.25, size: 0.3)
            return voice.render(duration: 0.8, peak: peak, fade: 0.08)
        case .tap:
            // Key down: a hard, tiny wooden tick with a low body.
            voice.bar(at: 0, frequency: 1100, decay: 0.012, gain: 0.9, hardness: 0.9, partials: [(1, 1, 1), (2.6, 0.5, 0.4)])
            voice.thud(at: 0, frequency: 150, decay: 0.02, gain: 0.6)
            voice.room(wet: 0.08, size: 0.12)
            return voice.render(duration: 0.12, peak: peak, fade: 0.01)
        case .release:
            // Key up: a softer wooden tock with a tiny drop.
            voice.bar(at: 0, frequency: 720, decay: 0.02, gain: 0.8, hardness: 0.6, partials: [(1, 1, 1), (2.6, 0.3, 0.4)])
            voice.drop(at: 0, frequency: 950, rise: 1.5, decay: 0.03, gain: 0.5, seed: 12)
            voice.room(wet: 0.08, size: 0.12)
            return voice.render(duration: 0.16, peak: peak, fade: 0.012)
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

/// Deterministic physical-flavoured synthesis: marimba bars (tuned 1 : 4 : 10
/// partials whose upper modes vanish in milliseconds), water drops (an entrained
/// bubble whose pitch rises as it shrinks, plus a splash), log-drum thuds with a
/// pitch drop, and a small stereo room built from early reflections and two
/// damped comb lines per channel.
struct CueSynthesizer {
    typealias Partial = (ratio: Double, gain: Double, decay: Double)
    static let marimba: [Partial] = [(1, 1, 1), (3.93, 0.5, 0.12), (9.9, 0.22, 0.05), (14.2, 0.06, 0.03)]

    let sampleRate: Int
    private var voices: [(start: Int, samples: [Double])] = []
    private var wet = 0.0
    private var size = 0.2

    init(sampleRate: Int) { self.sampleRate = sampleRate }

    private var period: Double { 1 / Double(sampleRate) }

    mutating func bar(at start: Double, frequency: Double, decay: Double, gain: Double, hardness: Double,
                      partials: [Partial] = CueSynthesizer.marimba) {
        let length = max(Int(0.02 * Double(sampleRate)), Int(decay * 6 * Double(sampleRate)))
        var buffer = [Double](repeating: 0, count: length)
        let contact = filteredNoise(count: length, seed: UInt32(frequency), low: 300, high: 2500 + hardness * 3000)
        for index in 0..<length {
            let time = Double(index) * period
            let attack = time < 0.0012 ? 0.5 - 0.5 * cos(.pi * time / 0.0012) : 1
            var value = 0.0
            for partial in partials {
                let weight = partial.ratio > 1 ? hardness : 1
                value += sin(2 * .pi * frequency * partial.ratio * time) * partial.gain * weight
                    * exp(-time / (decay * partial.decay))
            }
            buffer[index] = (value * attack + contact[index] * exp(-time / 0.003) * 0.8 * hardness) * gain
        }
        voices.append((Int(start * Double(sampleRate)), buffer))
    }

    mutating func drop(at start: Double, frequency: Double, rise: Double, decay: Double, gain: Double, seed: Int) {
        let length = max(Int(0.05 * Double(sampleRate)), Int(decay * 6 * Double(sampleRate)))
        var buffer = [Double](repeating: 0, count: length)
        let splash = filteredNoise(count: length, seed: UInt32(100 + seed), low: 1500, high: 7000)
        var phase = 0.0
        for index in 0..<length {
            let time = Double(index) * period
            let instantaneous = frequency * (1 + (rise - 1) * (1 - exp(-time / 0.025)))
            phase += 2 * .pi * instantaneous * period
            let attack = time < 0.0004 ? time / 0.0004 : 1
            buffer[index] = (sin(phase) * exp(-time / decay) * attack + splash[index] * exp(-time / 0.004) * 0.35) * gain
        }
        voices.append((Int(start * Double(sampleRate)), buffer))
    }

    mutating func thud(at start: Double, frequency: Double, decay: Double, gain: Double) {
        let length = max(Int(0.02 * Double(sampleRate)), Int(decay * 6 * Double(sampleRate)))
        var buffer = [Double](repeating: 0, count: length)
        let knock = filteredNoise(count: length, seed: 3, low: 0, high: 900)
        var phase = 0.0
        for index in 0..<length {
            let time = Double(index) * period
            let instantaneous = frequency * (1 + 0.9 * exp(-time / 0.04))
            phase += 2 * .pi * instantaneous * period
            let attack = time < 0.001 ? time / 0.001 : 1
            buffer[index] = (sin(phase) * exp(-time / decay) * attack + knock[index] * exp(-time / 0.006) * 0.9) * gain
        }
        voices.append((Int(start * Double(sampleRate)), buffer))
    }

    /// Band-limited deterministic noise: the difference of two one-pole low-passes.
    private func filteredNoise(count: Int, seed: UInt32, low: Double, high: Double) -> [Double] {
        var buffer = [Double](repeating: 0, count: count)
        var state = seed &* 2_654_435_761 &+ 0x9E37_79B9
        var upper = 0.0, lower = 0.0
        let quick = 1 - exp(-2 * .pi * high * period)
        let slow = low > 0 ? 1 - exp(-2 * .pi * low * period) : 1
        for index in 0..<count {
            state = state &* 1_664_525 &+ 1_013_904_223
            let white = Double(state >> 8) / Double(1 << 24) * 2 - 1
            upper += (white - upper) * quick
            if low > 0 { lower += (white - lower) * slow } else { lower = 0 }
            buffer[index] = upper - lower
        }
        return buffer
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
        for index in dry.indices { dry[index] = tanh(dry[index] * 1.2) }
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
                damped += (delayed - damped) * 0.3
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
