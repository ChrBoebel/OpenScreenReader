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
