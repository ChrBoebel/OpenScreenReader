import AVFoundation
import Foundation
import Testing
@testable import OpenScreenReader

private func heard(_ speaker: MeetingSpeaker, _ start: TimeInterval, _ end: TimeInterval, _ text: String,
                   final: Bool = true) -> MeetingRecognition {
    MeetingRecognition(speaker: speaker, start: start, end: end, text: text, isFinal: final)
}

@Suite("Meeting transcript model")
struct MeetingTranscriptTests {
    @Test
    func volatileTextIsReplacedInPlaceAndClearedByTheFinalText() {
        var transcript = MeetingTranscript()
        transcript.apply(heard(.others, 0, 1, "Guten", final: false))
        transcript.apply(heard(.others, 0, 2, "Guten Morgen zu", final: false))
        #expect(transcript.entries.map(\.pending) == ["Guten Morgen zu"])
        transcript.apply(heard(.others, 0, 2.5, "Guten Morgen zusammen."))
        #expect(transcript.entries.count == 1)
        #expect(transcript.entries[0].text == "Guten Morgen zusammen.")
        #expect(transcript.entries[0].pending.isEmpty)
    }

    @Test
    func turnsFollowTimeAcrossBothSpeakersAndMergeConsecutiveSegments() {
        var transcript = MeetingTranscript()
        transcript.apply(heard(.others, 5, 7, "Und wie siehst du das?"))
        transcript.apply(heard(.me, 0, 2, "Kurzer Stand."))
        transcript.apply(heard(.me, 2.2, 4, "Alles grün."))
        transcript.apply(heard(.me, 8, 9, "Gut", final: false))
        #expect(transcript.entries.map(\.speaker) == [.me, .others, .me])
        #expect(transcript.entries[0].text == "Kurzer Stand. Alles grün.")
        #expect(transcript.entries[2].text.isEmpty)
        #expect(transcript.entries[2].pending == "Gut")
    }

    @Test
    func emptyResultsNeverCreateTurns() {
        var transcript = MeetingTranscript()
        transcript.apply(heard(.me, 0, 1, "  ", final: false))
        transcript.apply(heard(.me, 0, 1, ""))
        #expect(transcript.entries.isEmpty)
        #expect(transcript.isEmpty)
    }

    @Test
    func myTextInsideAnEchoSpanIsHiddenEvenWhenTheSpanArrivesLater() {
        var transcript = MeetingTranscript()
        transcript.apply(heard(.me, 10, 12, "Wir sehen uns morgen"))
        transcript.apply(heard(.me, 20, 22, "Das sage ich selbst"))
        #expect(transcript.entries.map(\.text) == ["Wir sehen uns morgen Das sage ich selbst"])
        transcript.addEcho(9.5...12.5)
        #expect(transcript.entries.map(\.text) == ["Das sage ich selbst"])
    }

    @Test
    func myTextThatRepeatsTheOthersAtTheSameMomentIsHidden() {
        var transcript = MeetingTranscript()
        transcript.apply(heard(.me, 30.4, 33, "dann plane ich den Prototypen"))
        transcript.apply(heard(.others, 30, 32.8, "Dann plane ich den ersten Prototypen."))
        transcript.apply(heard(.me, 31, 31.5, "ja"))
        transcript.apply(heard(.me, 50, 52, "dann plane ich den Prototypen"))
        // A short reply is kept; the same sentence later, without the others, is mine.
        #expect(transcript.entries.map(\.speaker) == [.others, .me])
        #expect(transcript.entries[1].text == "ja dann plane ich den Prototypen")
    }

    @Test
    func echoSpansMergeWhenTheyOverlap() {
        var transcript = MeetingTranscript()
        transcript.addEcho(1...3)
        transcript.addEcho(2.5...4)
        transcript.addEcho(10...11)
        #expect(transcript.echoSpans == [1...4, 10...11])
    }

    @Test
    func exportListsSpeakerTimeAndTextWithoutHiddenEcho() {
        var transcript = MeetingTranscript()
        transcript.apply(heard(.me, 3, 5, "Kurzer Stand."))
        transcript.apply(heard(.others, 65, 70, "Danke."))
        transcript.apply(heard(.me, 66, 68, "Danke"))
        transcript.addEcho(65...70)
        #expect(transcript.exportText(title: "Meeting") == """
            # Meeting

            **Me** · 00:00:03
            Kurzer Stand.

            **Others** · 00:01:05
            Danke.

            """)
    }

    @Test
    func clockFormatsElapsedAndTimestamps() {
        #expect(MeetingClock.elapsed(59) == "0:59")
        #expect(MeetingClock.elapsed(3_725) == "1:02:05")
        #expect(MeetingClock.timestamp(65) == "00:01:05")
    }
}

@Suite("Meeting audio timeline")
struct MeetingTimelineTests {
    @Test
    func continuousChunksStayGaplessDespiteDeliveryJitter() {
        var timeline = MeetingTimeline()
        #expect(timeline.place(at: 0.30, duration: 0.1) == 0.30)
        #expect(abs(timeline.place(at: 0.43, duration: 0.1) - 0.40) < 1e-9)
        #expect(abs(timeline.place(at: 0.48, duration: 0.1) - 0.50) < 1e-9)
    }

    @Test
    func analyzerStampsAreWholeSamplesThatNeverOverlap() {
        var timeline = MeetingFrameTimeline(rate: 16_000)
        var previousEnd: Int64 = 0
        for (index, frames) in [1_600, 1_599, 1_601, 1_600, 1_598].enumerated() {
            let start = timeline.place(at: 100 + Double(index) * 0.1 + 0.0004, frames: frames)
            #expect(index == 0 || start == previousEnd)
            previousEnd = start + Int64(frames)
        }
        #expect(timeline.place(at: 200, frames: 10) == 3_200_000)
    }

    @Test
    func aRealGapJumpsAheadAndTimeNeverRunsBackwards() {
        var timeline = MeetingTimeline()
        _ = timeline.place(at: 1, duration: 0.1)
        #expect(timeline.place(at: 3, duration: 0.1) == 3)
        #expect(abs(timeline.place(at: 2, duration: 0.1) - 3.1) < 1e-9)
    }
}

/// Deterministic speech-like test signals: noise shaped by a 4 Hz syllable envelope.
private struct SignalSource {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func noise() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float(Int64(bitPattern: state >> 11) % 2_000_001) / 1_000_000 - 1
    }
    mutating func speech(seconds: Double, rate: Double = 8_000, level: Float = 0.2) -> [Float] {
        (0..<Int(seconds * rate)).map { index in
            let envelope = Float(0.55 + 0.45 * sin(2 * Double.pi * 4 * Double(index) / rate))
            return noise() * level * envelope
        }
    }
}

private func delayed(_ signal: [Float], by seconds: Double, gain: Float, rate: Double = 8_000) -> [Float] {
    let shift = Int(seconds * rate)
    return (0..<signal.count).map { $0 >= shift ? signal[$0 - shift] * gain : 0 }
}

/// Feeds both tracks in 100 ms chunks, as the audio callbacks would.
private func feed(_ gate: EchoGate, system: [Float], mic: [Float], from start: TimeInterval = 0,
                  rate: Double = 8_000) -> [ClosedRange<TimeInterval>] {
    let chunk = Int(rate / 10)
    var spans: [ClosedRange<TimeInterval>] = []
    for offset in stride(from: 0, to: min(system.count, mic.count), by: chunk) {
        let end = min(offset + chunk, system.count, mic.count)
        let time = start + Double(offset) / rate
        spans += gate.append(Array(system[offset..<end]), at: time, track: .others)
        spans += gate.append(Array(mic[offset..<end]), at: time, track: .me)
    }
    return spans
}

private func covered(_ spans: [ClosedRange<TimeInterval>], _ range: ClosedRange<TimeInterval>) -> Double {
    var transcript = MeetingTranscript()
    spans.forEach { transcript.addEcho($0) }
    let total = transcript.echoSpans.reduce(0.0) {
        $0 + max(0, min($1.upperBound, range.upperBound) - max($1.lowerBound, range.lowerBound))
    }
    return total / (range.upperBound - range.lowerBound)
}

@Suite("Meeting echo gate")
struct EchoGateTests {
    @Test
    func speakerEchoInTheMicrophoneIsFoundWithItsDelayFromTheStart() {
        var source = SignalSource(seed: 1)
        let system = source.speech(seconds: 8)
        var noise = SignalSource(seed: 2)
        let mic = zip(delayed(system, by: 0.12, gain: 0.3), noise.speech(seconds: 8, level: 0.004)).map { $0 + $1 }
        let gate = EchoGate()
        let spans = feed(gate, system: system, mic: mic)
        #expect(covered(spans, 0.5...8) > 0.9)
        #expect(spans.map(\.lowerBound).min() ?? 99 <= 0.5)
        #expect(abs((gate.lockedLag ?? 0) - 0.12) < 0.01)
    }

    @Test
    func myOwnVoiceWhileOthersSpeakIsNotAnEcho() {
        var others = SignalSource(seed: 3)
        var me = SignalSource(seed: 4)
        let spans = feed(EchoGate(), system: others.speech(seconds: 8), mic: me.speech(seconds: 8))
        #expect(spans.isEmpty)
    }

    @Test
    func silenceFromOtherAppsNeverMarksAnEcho() {
        var me = SignalSource(seed: 5)
        let spans = feed(EchoGate(), system: [Float](repeating: 0, count: 64_000), mic: me.speech(seconds: 8))
        #expect(spans.isEmpty)
    }

    @Test
    func aShortEchoAfterTheDelayIsKnownIsMarkedWithoutWaiting() {
        var source = SignalSource(seed: 6)
        let gate = EchoGate()
        let first = source.speech(seconds: 6)
        _ = feed(gate, system: first, mic: delayed(first, by: 0.08, gain: 0.25))
        let quiet = [Float](repeating: 0, count: 32_000)
        // Windows still overlapping the earlier echo may report it; nothing starts in the silence.
        #expect(feed(gate, system: quiet, mic: quiet, from: 6).allSatisfy { $0.lowerBound < 6 })
        let burst = source.speech(seconds: 0.6) + [Float](repeating: 0, count: 11_200)
        let spans = feed(gate, system: burst, mic: delayed(burst, by: 0.08, gain: 0.25), from: 10)
        #expect(covered(spans, 10...10.6) > 0.9)
    }
}

@Suite("Meeting audio sources")
struct MeetingAudioTests {
    @Test
    func deinterleavedStereoBecomesOneMonoTrack() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        buffer.frameLength = 3
        let channels = try #require(buffer.floatChannelData)
        for (index, (left, right)) in [(Float(1), Float(0)), (0.5, 0.5), (-1, 1)].enumerated() {
            channels[0][index] = left
            channels[1][index] = right
        }
        let mono = MeetingAudioMixdown.mono(buffer.audioBufferList, frames: 3, format: format.streamDescription.pointee)
        #expect(mono == [0.5, 0.5, 0])
    }

    @Test
    func interleavedTapAudioBecomesOneMonoTrack() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        let samples = try #require(buffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self))
        for (index, value) in [Float(0.2), 0.4, -0.6, -0.2].enumerated() { samples[index] = value }
        let mono = try #require(MeetingAudioMixdown.mono(buffer.audioBufferList, frames: 2, format: format.streamDescription.pointee))
        #expect(mono.map { ($0 * 10).rounded() / 10 } == [0.3, -0.4])
    }

    @Test
    func integerAudioIsRejectedInsteadOfMisread() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        #expect(MeetingAudioMixdown.mono(buffer.audioBufferList, frames: 4, format: format.streamDescription.pointee) == nil)
    }

    @Test
    func hostTimeConvertsToSeconds() {
        let second = MeetingHostClock.hostTicks(forSeconds: 1)
        #expect(abs(MeetingHostClock.seconds(second * 3) - 3) < 1e-6)
    }
}

private final class RecognizerFake: MeetingRecognizing, @unchecked Sendable {
    private let lock = NSLock()
    private var _appended: [(speaker: MeetingSpeaker, time: TimeInterval, frames: Int)] = []
    var appended: [(speaker: MeetingSpeaker, time: TimeInterval, frames: Int)] { lock.withLock { _appended } }
    var startedLocale: Locale?
    var finished = false
    var cancelled = false
    var startError: Error?
    var onResult: (@Sendable (MeetingRecognition) -> Void)?
    var onFailure: (@Sendable (String) -> Void)?
    var finalOnFinish: MeetingRecognition?

    func start(locale: Locale, onResult: @escaping @Sendable (MeetingRecognition) -> Void,
               onFailure: @escaping @Sendable (String) -> Void) async throws {
        if let startError { throw startError }
        startedLocale = locale
        self.onResult = onResult
        self.onFailure = onFailure
    }
    func append(_ chunk: MeetingAudioChunk, at time: TimeInterval, speaker: MeetingSpeaker) {
        lock.withLock { _appended.append((speaker, time, chunk.samples.count)) }
    }
    func finish() async {
        finished = true
        if let finalOnFinish { onResult?(finalOnFinish) }
    }
    func cancel() async { cancelled = true }
}

@Suite("Meeting audio routing")
struct MeetingRouterTests {
    private let start: UInt64 = 1_000_000_000

    private func chunk(_ samples: [Float], rate: Double = 48_000, after seconds: TimeInterval) -> MeetingAudioChunk {
        MeetingAudioChunk(samples: samples, sampleRate: rate, hostTime: start + MeetingHostClock.hostTicks(forSeconds: seconds))
    }

    @Test
    func chunksLandOnTheMeetingTimelineAndReachTheRecognizer() {
        let recognizer = RecognizerFake()
        let router = MeetingAudioRouter(startHostTime: start, recognizer: recognizer, onEcho: { _ in })
        router.handle(chunk([Float](repeating: 0.1, count: 4_800), after: 1), from: .me)
        router.handle(chunk([Float](repeating: 0.1, count: 4_800), after: 1.11), from: .me)
        router.handle(chunk([Float](repeating: 0, count: 480), after: 0.5), from: .others)
        let times = recognizer.appended.map { ($0.speaker, ($0.time * 100).rounded() / 100) }
        #expect(times.map(\.0) == [.me, .me, .others])
        #expect(times.map(\.1) == [1, 1.1, 0.5])
    }

    @Test
    func echoAtTheDevicesSampleRateIsReportedAfterResampling() async {
        var source = SignalSource(seed: 7)
        let system = source.speech(seconds: 6, rate: 48_000)
        let mic = delayed(system, by: 0.1, gain: 0.3, rate: 48_000)
        let found = Spans()
        let router = MeetingAudioRouter(startHostTime: start, recognizer: RecognizerFake(), onEcho: { found.add($0) })
        for offset in stride(from: 0, to: system.count, by: 4_800) {
            let time = Double(offset) / 48_000
            router.handle(chunk(Array(system[offset..<offset + 4_800]), after: time), from: .others)
            router.handle(chunk(Array(mic[offset..<offset + 4_800]), after: time), from: .me)
        }
        router.drain()
        #expect(!found.all.isEmpty)
    }

    @Test
    func stoppedRoutingDropsLateAudio() {
        let recognizer = RecognizerFake()
        let router = MeetingAudioRouter(startHostTime: start, recognizer: recognizer, onEcho: { _ in })
        router.stop()
        router.handle(chunk([0.2, 0.2], after: 1), from: .me)
        #expect(recognizer.appended.isEmpty)
    }

    @Test
    func silenceAndSoundAreTrackedPerTrack() {
        let router = MeetingAudioRouter(startHostTime: start, recognizer: RecognizerFake(), onEcho: { _ in })
        router.handle(chunk([Float](repeating: 0, count: 4_800), after: 2), from: .others)
        router.handle(chunk([Float](repeating: 0.05, count: 4_800), after: 3), from: .me)
        let state = router.state
        #expect(state.lastSignal[.others] == nil)
        #expect(state.lastSound[.me] != nil)
        #expect(state.level[.me] ?? 0 > 0.04)
    }
}

private final class Spans: @unchecked Sendable {
    private let lock = NSLock()
    private var spans: [ClosedRange<TimeInterval>] = []
    func add(_ more: [ClosedRange<TimeInterval>]) { lock.withLock { spans += more } }
    var all: [ClosedRange<TimeInterval>] { lock.withLock { spans } }
}

private final class Results: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [MeetingRecognition] = []
    func add(_ item: MeetingRecognition) { lock.withLock { items.append(item) } }
    var all: [MeetingRecognition] { lock.withLock { items } }
}

/// Runs Apple's on-device recogniser for real when this Mac has it and German installed.
@Suite("Meeting recognition on this Mac", .serialized)
struct AppleMeetingRecognizerTests {
    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func germanSpeechLandsOnTheMeetingTimeline() async throws {
        guard #available(macOS 26, *) else { return }
        let provider = SystemMeetingRecognizerProvider()
        guard case let .available(locale) = await provider.availability(for: .german) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-\(UUID()).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Anna", "-o", url.path, "Guten Morgen zusammen. Kurzer Stand zum Projekt."]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { return }
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let rate = file.processingFormat.sampleRate

        let recognizer = try #require(provider.makeRecognizer())
        let results = Results()
        try await recognizer.start(locale: locale, onResult: { results.add($0) }, onFailure: { _ in })
        let step = Int(rate / 10)
        for offset in stride(from: 0, to: samples.count, by: step) {
            let piece = Array(samples[offset..<min(offset + step, samples.count)])
            recognizer.append(MeetingAudioChunk(samples: piece, sampleRate: rate, hostTime: 0),
                              at: 100 + Double(offset) / rate, speaker: .others)
        }
        await recognizer.finish()
        let finals = results.all.filter(\.isFinal)
        let text = finals.map(\.text).joined(separator: " ")
        #expect(text.localizedCaseInsensitiveContains("Morgen"))
        #expect(finals.allSatisfy { $0.speaker == .others && $0.start >= 99.9 })
    }
}
