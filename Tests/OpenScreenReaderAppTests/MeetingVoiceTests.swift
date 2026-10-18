import Foundation
import Testing
@testable import OpenScreenReader

private func others(_ start: TimeInterval, _ end: TimeInterval, _ text: String, final: Bool = true,
                    words: [(String, TimeInterval, TimeInterval)] = []) -> MeetingRecognition {
    MeetingRecognition(speaker: .others, start: start, end: end, text: text, isFinal: final,
                       pieces: words.map { MeetingPiece(text: $0.0, start: $0.1, end: $0.2) })
}

private func me(_ start: TimeInterval, _ end: TimeInterval, _ text: String) -> MeetingRecognition {
    MeetingRecognition(speaker: .me, start: start, end: end, text: text, isFinal: true)
}

private func voice(_ voice: Int, _ start: TimeInterval, _ end: TimeInterval) -> MeetingVoiceSpan {
    MeetingVoiceSpan(voice: voice, start: start, end: end)
}

@Suite("Meeting voices")
struct MeetingVoiceTests {
    @Test
    func withoutVoicesTheOthersStayOneSpeaker() {
        var transcript = MeetingTranscript()
        transcript.apply(others(0, 2, "Guten Morgen."))
        transcript.apply(me(3, 4, "Hallo."))
        #expect(transcript.entries.map(\.label) == ["Others", "Me"])
        #expect(transcript.entries.map(\.voice) == [nil, nil])
    }

    @Test
    func segmentsGoToTheVoiceThatSpokeMostDuringThem() {
        var transcript = MeetingTranscript()
        transcript.apply(others(0, 4, "Guten Morgen zusammen."))
        transcript.apply(others(5, 8, "Danke, hallo."))
        transcript.addVoice(voice(7, 0.2, 4.1))
        transcript.addVoice(voice(3, 4.9, 8.2))
        #expect(transcript.entries.map(\.label) == ["Speaker 1", "Speaker 2"])
        #expect(transcript.entries.map(\.voice) == [7, 3])
    }

    @Test
    func aChangeOfVoiceInsideOneSegmentSplitsItAtTheWords() {
        var transcript = MeetingTranscript()
        transcript.apply(others(0, 6, "Ist das freigegeben? Ja, seit Dienstag.", words: [
            ("Ist", 0, 0.3), ("das", 0.3, 0.6), ("freigegeben", 0.6, 1.4), ("?", 1.4, 1.5),
            ("Ja", 3, 3.3), (",", 3.3, 3.35), ("seit", 3.4, 3.8), ("Dienstag", 3.8, 4.5), (".", 4.5, 4.55),
        ]))
        transcript.addVoice(voice(0, 0, 1.6))
        transcript.addVoice(voice(1, 2.9, 4.7))
        #expect(transcript.entries.map(\.text) == ["Ist das freigegeben?", "Ja, seit Dienstag."])
        #expect(transcript.entries.map(\.label) == ["Speaker 1", "Speaker 2"])
    }

    @Test
    func wordsBetweenSpansStayWithTheirNeighbours() {
        var transcript = MeetingTranscript()
        transcript.apply(others(0, 4, "Das machen wir so.", words: [
            ("Das", 0, 0.3), ("machen", 0.3, 0.8), ("wir", 2.5, 2.8), ("so", 2.8, 3.2), (".", 3.2, 3.25),
        ]))
        // The diarizer lost the voice for a moment in the middle.
        transcript.addVoice(voice(4, 0, 0.9))
        transcript.addVoice(voice(4, 2.4, 3.4))
        #expect(transcript.entries.map(\.text) == ["Das machen wir so."])
        #expect(transcript.entries.map(\.voice) == [4])
    }

    @Test
    func consecutiveSegmentsOfOneVoiceFormOneTurnAndNumbersFollowFirstWords() {
        var transcript = MeetingTranscript()
        transcript.addVoice(voice(9, 0, 2))
        transcript.addVoice(voice(2, 3, 5))
        transcript.addVoice(voice(2, 5.5, 7))
        transcript.addVoice(voice(9, 8, 10))
        transcript.apply(others(0, 2, "Eins."))
        transcript.apply(others(3, 5, "Zwei."))
        transcript.apply(others(5.5, 7, "Drei."))
        transcript.apply(others(8, 10, "Vier."))
        #expect(transcript.entries.map(\.text) == ["Eins.", "Zwei. Drei.", "Vier."])
        #expect(transcript.entries.map(\.label) == ["Speaker 1", "Speaker 2", "Speaker 1"])
        #expect(transcript.voices.map(\.voice) == [9, 2])
    }

    @Test
    func voicesArrivingAfterTheTextStillAssignIt() {
        var transcript = MeetingTranscript()
        transcript.apply(others(0, 2, "Hallo", final: false))
        #expect(transcript.entries.map(\.label) == ["Others"])
        transcript.addVoice(voice(1, 0, 2))
        #expect(transcript.entries.map(\.label) == ["Speaker 1"])
        #expect(transcript.entries.map(\.pending) == ["Hallo"])
    }

    @Test
    func aNameReplacesTheNumberEverywhereAndAnEmptyNameRestoresIt() {
        var transcript = MeetingTranscript()
        transcript.addVoice(voice(5, 0, 2))
        transcript.addVoice(voice(6, 3, 5))
        transcript.addVoice(voice(5, 6, 8))
        transcript.apply(others(0, 2, "A."))
        transcript.apply(others(3, 5, "B."))
        transcript.apply(others(6, 8, "C."))
        transcript.rename(voice: 5, to: "  Anna ")
        #expect(transcript.entries.map(\.label) == ["Anna", "Speaker 2", "Anna"])
        #expect(transcript.voices.map(\.label) == ["Anna", "Speaker 2"])
        transcript.rename(voice: 5, to: " ")
        #expect(transcript.entries.map(\.label) == ["Speaker 1", "Speaker 2", "Speaker 1"])
    }

    @Test
    func mergingJoinsTurnsAndKeepsTheTargetsNameAndNumber() {
        var transcript = MeetingTranscript()
        transcript.addVoice(voice(0, 0, 2))
        transcript.addVoice(voice(1, 3, 5))
        transcript.addVoice(voice(2, 6, 8))
        transcript.apply(others(0, 2, "A."))
        transcript.apply(others(3, 5, "B."))
        transcript.apply(others(6, 8, "C."))
        transcript.rename(voice: 0, to: "Anna")
        transcript.merge(voice: 1, into: 0)
        #expect(transcript.entries.map(\.text) == ["A. B.", "C."])
        #expect(transcript.entries.map(\.label) == ["Anna", "Speaker 3"])
        #expect(transcript.voices.map(\.voice) == [0, 2])
        // A voice merged into one that is merged later follows along.
        transcript.merge(voice: 0, into: 2)
        #expect(transcript.entries.map(\.label) == ["Speaker 3"])
        #expect(transcript.entries.map(\.text) == ["A. B. C."])
    }

    @Test
    func mergingIntoItselfOrInACircleChangesNothing() {
        var transcript = MeetingTranscript()
        transcript.addVoice(voice(0, 0, 2))
        transcript.addVoice(voice(1, 3, 5))
        transcript.apply(others(0, 2, "A."))
        transcript.apply(others(3, 5, "B."))
        transcript.merge(voice: 0, into: 0)
        transcript.merge(voice: 0, into: 1)
        transcript.merge(voice: 1, into: 0)
        #expect(transcript.entries.map(\.text) == ["A. B."])
        #expect(transcript.entries.map(\.voice) == [1])
    }

    @Test
    func myOwnTextNeverTakesAVoice() {
        var transcript = MeetingTranscript()
        transcript.addVoice(voice(0, 0, 5))
        transcript.apply(me(1, 2, "Ich rede."))
        #expect(transcript.entries.map(\.label) == ["Me"])
        #expect(transcript.voices.isEmpty)
    }

    @Test
    func exportUsesTheNames() {
        var transcript = MeetingTranscript()
        transcript.addVoice(voice(3, 0, 2))
        transcript.apply(others(0, 2, "Hallo."))
        transcript.apply(me(3, 4, "Hi."))
        transcript.rename(voice: 3, to: "Ben")
        let export = MeetingExport(transcript: transcript, title: "T", duration: 4)
        #expect(export.turns.map(\.speaker) == ["Ben", "Me"])
        #expect(export.speakers == ["Ben", "Me"])
    }

    @Test
    func longSpansAreSplitSoLookupsStayLocal() {
        var transcript = MeetingTranscript()
        transcript.addVoice(voice(0, 0, 95))
        #expect(transcript.voiceSpans.count == 4)
        #expect(transcript.voiceSpans.allSatisfy { $0.end - $0.start <= 30 })
        transcript.apply(others(80, 82, "Spaet im Monolog."))
        #expect(transcript.entries.map(\.voice) == [0])
    }
}
