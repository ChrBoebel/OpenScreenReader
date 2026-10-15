import AppKit
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
    func echoWordsLeaveAMixedSegmentWhileMyWordsStay() {
        var transcript = MeetingTranscript()
        let echo = ["Wir", "haben", "die", "Tests", "fertig."].enumerated().map {
            MeetingPiece(text: $0.element, start: Double($0.offset), end: Double($0.offset) + 0.8)
        }
        let mine = ["Danke", ",", "bis", "Freitag."].enumerated().map {
            MeetingPiece(text: $0.element, start: 7 + Double($0.offset), end: 7.8 + Double($0.offset))
        }
        transcript.apply(MeetingRecognition(speaker: .me, start: 0, end: 10, text: "Wir haben die Tests fertig. Danke, bis Freitag.",
                                            isFinal: true, pieces: echo + mine))
        transcript.addEcho(0.1...5.8)
        #expect(transcript.entries.map(\.text) == ["Danke, bis Freitag."])
    }

    @Test
    func repeatedWordRunsLeaveAMixedSegmentWithoutTimings() {
        var transcript = MeetingTranscript()
        transcript.apply(heard(.others, 0, 5, "Wir haben die Tests fertig."))
        transcript.apply(heard(.me, 0, 10, "Wir haben die Tests fertig. Danke, dann plane ich Freitag."))
        let mine = transcript.entries.filter { $0.speaker == .me }.map(\.text)
        #expect(mine == ["Danke, dann plane ich Freitag."])
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
        // The microphone hears the burst 80 ms later.
        #expect(covered(spans, 10.08...10.68) > 0.9)
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-\(UUID()).caf")
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

    /// Real recogniser, real router and echo gate: the others' sentence reaches the
    /// microphone as a quiet echo, then I say something of my own.
    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func speakerEchoDisappearsFromMeWhileMyOwnSentenceStays() async throws {
        guard #available(macOS 26, *) else { return }
        let provider = SystemMeetingRecognizerProvider()
        guard case let .available(locale) = await provider.availability(for: .german) else { return }
        let others = try #require(try speech("Wir haben in dieser Woche die neue Funktion fertiggestellt und alle Tests laufen grün.", voice: "Anna"))
        let mine = try #require(try speech("Danke, dann plane ich den Prototypen für Freitag.", voice: "Eddy (Deutsch (Deutschland))")
            ?? speech("Danke, dann plane ich den Prototypen für Freitag.", voice: "Anna"))
        let rate = 22_050.0
        let gap = [Float](repeating: 0, count: Int(rate))
        let systemTrack = others + gap + [Float](repeating: 0, count: mine.count)
        let echo = delayed(others, by: 0.09, gain: 0.3, rate: rate)
        let micTrack = echo + gap + mine

        let recognizer = try #require(provider.makeRecognizer())
        let results = Results()
        let spans = Spans()
        try await recognizer.start(locale: locale, onResult: { results.add($0) }, onFailure: { _ in })
        let start: UInt64 = 1_000_000_000
        let router = MeetingAudioRouter(startHostTime: start, recognizer: recognizer, onEcho: { spans.add($0) })
        let step = Int(rate / 10)
        for offset in stride(from: 0, to: systemTrack.count, by: step) {
            let end = min(offset + step, systemTrack.count)
            let host = start + MeetingHostClock.hostTicks(forSeconds: Double(offset) / rate)
            router.handle(MeetingAudioChunk(samples: Array(systemTrack[offset..<end]), sampleRate: rate, hostTime: host), from: .others)
            router.handle(MeetingAudioChunk(samples: Array(micTrack[offset..<end]), sampleRate: rate, hostTime: host), from: .me)
        }
        router.stop()
        await recognizer.finish()
        router.drain()

        var transcript = MeetingTranscript()
        results.all.forEach { transcript.apply($0) }
        spans.all.forEach { transcript.addEcho($0) }
        let me = transcript.entries.filter { $0.speaker == .me }.map(\.text).joined(separator: " ")
        let them = transcript.entries.filter { $0.speaker == .others }.map(\.text).joined(separator: " ")
        // Recognition of the synthetic second voice varies; its first and last words are stable.
        #expect(them.localizedCaseInsensitiveContains("Tests"))
        #expect(me.localizedCaseInsensitiveContains("Danke"))
        #expect(me.localizedCaseInsensitiveContains("Freitag"))
        #expect(!me.localizedCaseInsensitiveContains("Woche"))
        #expect(!me.localizedCaseInsensitiveContains("Tests"))
    }

    private func speech(_ text: String, voice: String) throws -> [Float]? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-\(UUID()).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "--file-format=caff", "--data-format=LEF32@22050", "-o", url.path, text]
        say.standardError = FileHandle.nullDevice
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { return nil }
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == 22_050,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }
}

@MainActor
private final class SourceFake: MeetingAudioSource {
    var deliver: (@Sendable (MeetingAudioChunk) -> Void)?
    var starts = 0
    var stops = 0
    var failure: Error?
    func start(deliver: @escaping @Sendable (MeetingAudioChunk) -> Void) throws {
        if let failure { throw failure }
        starts += 1
        self.deliver = deliver
    }
    func stop() { stops += 1; deliver = nil }
}

@MainActor
private final class ProviderFake: MeetingRecognizerProviding {
    var availability: MeetingAvailability = .available(Locale(identifier: "de-DE"))
    var recognizer = RecognizerFake()
    var requestedLanguage: DictationLanguage?
    func availability(for language: DictationLanguage) async -> MeetingAvailability {
        requestedLanguage = language
        return availability
    }
    func makeRecognizer() -> (any MeetingRecognizing)? { recognizer }
}

private final class HostClockFake: @unchecked Sendable {
    var seconds: TimeInterval = 10
    var ticks: UInt64 { MeetingHostClock.hostTicks(forSeconds: seconds) }
}

private final class MeetingSoundsFake: InterfaceSoundPlaying {
    var cues: [InterfaceCue] = []
    func play(_ cue: InterfaceCue) { cues.append(cue) }
    func stop() {}
}

@MainActor
private struct MeetingFixture {
    let controller: MeetingController
    let provider = ProviderFake()
    let microphone = SourceFake()
    let system = SourceFake()
    let clock = HostClockFake()
    let sounds = MeetingSoundsFake()
    let pasteboard = NSPasteboard.withUniqueName()
    let notifications = NotificationCenter()
    var saved: [String] { savedBox.items }
    let savedBox = SavedBox()

    init(systemAvailable: Bool = true) {
        let provider = provider, microphone = microphone, system = system, clock = clock, savedBox = savedBox
        controller = MeetingController(
            provider: provider,
            makeMicrophone: { microphone },
            makeSystemAudio: { systemAvailable ? system : nil },
            language: { .german },
            interfaceSounds: sounds,
            hostClock: { clock.ticks },
            pasteboard: pasteboard,
            notifications: notifications,
            save: { text, _ in savedBox.items.append(text); return true },
            confirmReplacingUnsaved: { false },
            presentsWindow: false)
    }

    func start() async {
        await controller.open()
        controller.confirmConsent()
        await controller.waitUntilSettled()
    }

    func hear(_ recognition: MeetingRecognition) async {
        provider.recognizer.onResult?(recognition)
        await controller.waitUntilSettled()
    }
}

@MainActor
private final class SavedBox { var items: [String] = [] }

@Suite("Meeting transcript lifecycle", .serialized)
@MainActor
struct MeetingControllerTests {
    @Test
    func nothingRecordsBeforeConsentIsConfirmed() async {
        let fixture = MeetingFixture()
        await fixture.controller.open()
        #expect(fixture.controller.phase == .consent)
        #expect(fixture.microphone.starts == 0)
        #expect(fixture.system.starts == 0)
        #expect(fixture.provider.recognizer.startedLocale == nil)
        fixture.controller.discard()
        #expect(fixture.controller.phase == .idle)
        #expect(fixture.microphone.starts == 0)
    }

    @Test
    func unavailableRecognitionSaysWhyAndOffersNoStart() async {
        let fixture = MeetingFixture()
        fixture.provider.availability = .languageMissing("Deutsch")
        await fixture.controller.open()
        guard case .unavailable = fixture.controller.phase else {
            Issue.record("expected unavailable, got \(fixture.controller.phase)")
            return
        }
        fixture.controller.confirmConsent()
        await fixture.controller.waitUntilSettled()
        #expect(fixture.microphone.starts == 0)
    }

    @Test
    func consentStartsRecognitionThenBothSourcesWithTheDictationLanguage() async {
        let fixture = MeetingFixture()
        await fixture.start()
        #expect(fixture.controller.phase == .live)
        #expect(fixture.provider.requestedLanguage == .german)
        #expect(fixture.provider.recognizer.startedLocale?.identifier == "de-DE")
        #expect(fixture.microphone.starts == 1)
        #expect(fixture.system.starts == 1)
        #expect(fixture.sounds.cues == [.listening])
        #expect(fixture.controller.isRecording)
    }

    @Test
    func audioFromBothSourcesReachesTheRecognizer() async {
        let fixture = MeetingFixture()
        await fixture.start()
        fixture.microphone.deliver?(MeetingAudioChunk(samples: [0.1, 0.1], sampleRate: 16_000, hostTime: fixture.clock.ticks))
        fixture.system.deliver?(MeetingAudioChunk(samples: [0.1, 0.1], sampleRate: 16_000, hostTime: fixture.clock.ticks))
        #expect(fixture.provider.recognizer.appended.map(\.speaker) == [.me, .others])
    }

    @Test
    func resultsFillTheTranscriptAndStopKeepsIt() async {
        let fixture = MeetingFixture()
        await fixture.start()
        await fixture.hear(heard(.others, 1, 2, "Guten Morgen."))
        fixture.provider.recognizer.finalOnFinish = heard(.me, 3, 4, "Hallo.")
        fixture.controller.stop()
        await fixture.controller.waitUntilSettled()
        #expect(fixture.controller.phase == .finished)
        #expect(fixture.microphone.stops >= 1)
        #expect(fixture.system.stops >= 1)
        #expect(fixture.provider.recognizer.finished)
        #expect(fixture.controller.transcript.entries.map(\.text) == ["Guten Morgen.", "Hallo."])
        #expect(fixture.sounds.cues == [.listening, .captured])
    }

    @Test
    func discardedTranscriptsIgnoreLateResults() async {
        let fixture = MeetingFixture()
        await fixture.start()
        fixture.controller.discard()
        await fixture.controller.waitUntilSettled()
        #expect(fixture.provider.recognizer.cancelled)
        await fixture.hear(heard(.others, 1, 2, "Zu spaet."))
        #expect(fixture.controller.transcript.isEmpty)
        #expect(fixture.controller.phase == .idle)
    }

    @Test
    func copyAndSaveHappenOnlyOnRequest() async {
        let fixture = MeetingFixture()
        await fixture.start()
        await fixture.hear(heard(.others, 1, 2, "Guten Morgen."))
        fixture.controller.stop()
        await fixture.controller.waitUntilSettled()
        #expect(fixture.pasteboard.string(forType: .string) == nil)
        #expect(fixture.saved.isEmpty)
        fixture.controller.copy()
        #expect(fixture.pasteboard.string(forType: .string)?.contains("Guten Morgen.") == true)
        fixture.controller.save()
        #expect(fixture.saved.count == 1)
        #expect(fixture.controller.hasUnsavedText == false)
    }

    @Test
    func aNewTranscriptNeverSilentlyReplacesAnUnsavedOne() async {
        let fixture = MeetingFixture()
        await fixture.start()
        await fixture.hear(heard(.others, 1, 2, "Wichtig."))
        fixture.controller.stop()
        await fixture.controller.waitUntilSettled()
        await fixture.controller.startNew()
        #expect(fixture.controller.phase == .finished)
        #expect(!fixture.controller.transcript.isEmpty)
    }

    @Test
    func sleepEndsTheRecordingButKeepsTheTranscript() async {
        let fixture = MeetingFixture()
        await fixture.start()
        await fixture.hear(heard(.me, 1, 2, "Bis gleich."))
        fixture.notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        await fixture.controller.waitUntilSettled()
        #expect(fixture.controller.phase == .finished)
        #expect(fixture.controller.transcript.entries.map(\.text) == ["Bis gleich."])
    }

    @Test
    func theTimeLimitWarnsAndThenStops() async {
        let fixture = MeetingFixture()
        await fixture.start()
        // Keep talking, so only the time limit applies.
        let talk = { fixture.microphone.deliver?(MeetingAudioChunk(samples: [Float](repeating: 0.1, count: 160), sampleRate: 16_000, hostTime: fixture.clock.ticks)) }
        fixture.clock.seconds += 2 * 3600 - 299
        talk()
        fixture.controller.tick()
        #expect(fixture.controller.notice != nil)
        #expect(fixture.controller.phase == .live)
        fixture.clock.seconds += 300
        talk()
        fixture.controller.tick()
        await fixture.controller.waitUntilSettled()
        #expect(fixture.controller.phase == .finished)
    }

    @Test
    func tenSilentMinutesStopTheRecording() async {
        let fixture = MeetingFixture()
        await fixture.start()
        fixture.clock.seconds += 599
        fixture.controller.tick()
        #expect(fixture.controller.phase == .live)
        fixture.clock.seconds += 2
        fixture.controller.tick()
        await fixture.controller.waitUntilSettled()
        #expect(fixture.controller.phase == .finished)
    }

    @Test
    func silentSystemAudioPointsToThePermission() async {
        let fixture = MeetingFixture()
        await fixture.start()
        fixture.clock.seconds += 21
        fixture.system.deliver?(MeetingAudioChunk(samples: [0, 0], sampleRate: 16_000, hostTime: fixture.clock.ticks))
        fixture.controller.tick()
        #expect(fixture.controller.systemAudioMissing)
        fixture.system.deliver?(MeetingAudioChunk(samples: [0.2, 0.1], sampleRate: 16_000, hostTime: fixture.clock.ticks))
        fixture.controller.tick()
        #expect(!fixture.controller.systemAudioMissing)
    }

    @Test
    func withoutSystemAudioTheMicrophoneStillTranscribesWithANotice() async {
        let fixture = MeetingFixture(systemAvailable: false)
        await fixture.start()
        #expect(fixture.controller.phase == .live)
        #expect(fixture.microphone.starts == 1)
        #expect(fixture.controller.notice != nil)
    }

    @Test
    func aFailingMicrophoneEndsTheStartCleanly() async {
        let fixture = MeetingFixture()
        fixture.microphone.failure = MeetingError("Mic busy")
        await fixture.start()
        #expect(fixture.controller.phase == .consent)
        #expect(fixture.controller.notice == "Mic busy")
        #expect(fixture.provider.recognizer.cancelled)
        #expect(fixture.system.starts == 0 || fixture.system.stops >= 1)
    }
}

private final class MeetingHotkeyFake: HotkeyManaging {
    var onPress: (() -> Void)?
    func register(_ shortcut: HotkeyShortcut) -> HotkeyRegistration { .registered }
    func unregister() {}
}

@Suite("Meeting transcript in the app", .serialized)
@MainActor
struct MeetingAppTests {
    @Test
    func aRunningTranscriptShowsItsOwnMenuBarShapeAndHoldsUpdates() async {
        let fixture = MeetingFixture()
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: MeetingHotkeyFake(),
                             meeting: fixture.controller)
        #expect(model.menuBarIndicator == .idle)
        #expect(model.canChangeShortcut)
        await fixture.start()
        #expect(model.menuBarIndicator == .recording)
        #expect(model.isBusyForUpdates)
        fixture.controller.stop()
        await fixture.controller.waitUntilSettled()
        #expect(model.menuBarIndicator == .idle)
        #expect(!model.isBusyForUpdates)
    }

    @Test
    func readingAndDictationLeaveARunningTranscriptAlone() async {
        let fixture = MeetingFixture()
        let model = AppModel(shortcutStore: MemoryShortcutStore(), hotkeyManager: MeetingHotkeyFake(),
                             meeting: fixture.controller)
        await fixture.start()
        model.enqueueStopRequest()
        await model.waitForInteractionToSettle()
        #expect(fixture.controller.phase == .live)
        #expect(fixture.microphone.stops == 0)
    }
}
