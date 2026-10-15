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
