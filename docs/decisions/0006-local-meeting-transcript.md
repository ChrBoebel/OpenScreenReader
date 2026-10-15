# ADR 0006: Local meeting transcript

- Status: accepted
- Date: 2026-10-15
- Decision: project owner ("okey baue es"), on the proposal from the Wispr Flow analysis and the on-device measurements of the same day.

## Context

Wispr Flow's Notetaker records meetings without a bot: it captures the microphone and the system audio as two separate tracks. It streams both to its own servers, where Soniox, its own model or OpenAI transcribe them, and summarises the meeting in the cloud.

Saywing's promise is the opposite: everything stays on the Mac. On macOS 26, Apple's `SpeechAnalyzer`/`SpeechTranscriber` runs on the device. On the owner's Mac, measured with a 53.8 s synthetic German recording:

- It transcribed German 60–110× faster than real time.
- With `.volatileResults` and `.fastResults` it delivered live text less than about 1 s behind the audio.

The brand synthesis lists a "transcription archive" and a "summarizer" as non-goals.

## Decision

1. **A narrow exception for a meeting transcript.** It is a single live transcript of a meeting the user explicitly starts. There is no archive, no history and no summary.
2. **Two tracks.**
   - The microphone is labelled "Me".
   - The system audio of every other app, captured with a private Core Audio process tap that excludes Saywing itself, is labelled "Others".
3. **Recognition.** Apple's on-device `SpeechTranscriber` handles recognition, one instance per track, on macOS 26 or later, and only for locales that are already installed.
   - Saywing never asks the system to download speech assets.
   - On older systems the feature is unavailable.
   - The Whisper worker stays reserved for dictation.
4. **Consent before every start.** A consent step precedes each start. It offers a copyable notice for the meeting chat and reminds the user that recording other people requires their consent. Saywing never starts a meeting transcript automatically and never posts into other apps.
5. **Nothing on disk.**
   - Audio stays in bounded memory and is discarded as it is recognised.
   - The transcript stays in memory until the user discards it, starts a new one or quits.
   - It is written to disk only through an explicit save dialog. Copying happens only on an explicit click.
6. **Echo handling.** On speakers, the microphone also hears the other participants. A local gate cross-correlates both tracks. It hides "Me" segments that coincide with an echo, or that repeat an "Others" segment from the same moment.
7. **Limits.**
   - The transcript stops itself after 2 hours, with a warning 5 minutes before.
   - It also stops after 10 minutes without sound on both tracks.
   - Sleep, a session switch and quitting end it cleanly and keep the transcript.
   - Escape, reading and dictation do not end it. Only its own Stop does.
8. **Permission.** System audio capture asks for macOS's system audio recording permission the first time a transcript starts. This uses `NSAudioCaptureUsageDescription`; no private TCC API is used. A denied permission delivers silence, so the live window tells the user when nothing arrives from other apps.

## Consequences

- No new network path, model weights or third-party code. Core Audio taps and the Speech framework are system APIs.
- Recording legality (for example § 201 StGB, GDPR) remains the user's responsibility. A legal review is a release gate before publication; this ADR is not legal advice.
- The following are out of scope until separately decided:
  - Whisper refinement with the user vocabulary after a meeting
  - summaries (Apple Foundation Models)
  - speaker diarisation
  - meeting detection
  - mixed-language meetings

## Validation gates

- A real call over speakers and over headphones on the signed build:
  - permission prompt
  - echo duplicates
  - word errors on real speech
  - CPU and memory over 60 minutes
- A file-system check that no audio is written during a session.
