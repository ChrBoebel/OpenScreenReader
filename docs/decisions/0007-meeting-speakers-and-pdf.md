# ADR 0007: Telling meeting speakers apart, and PDF export

- Status: accepted. Runtime integration is pending a build permission (see "Open").
- Date: 2026-10-18
- Decision: project owner ("okey setze das bitte um"), on the proposal in the same thread: tell the voices of the other participants apart locally, let the user name them, and export the transcript as PDF.
- Extends: [ADR 0006](0006-local-meeting-transcript.md). That ADR listed speaker diarisation as out of scope until separately decided. This ADR is that decision.

## Context

A meeting transcript has two tracks:

- the microphone, labelled "Me";
- the system audio of every other app, labelled "Others".

Everybody on the other side of a call therefore ends up as "Others". Meeting apps mix all remote participants into one stream before it reaches the Mac. Participant names are only available through a bot, a vendor SDK, or by reading the app's user interface through the accessibility API. Wispr Flow does the last of these; it is fragile and app-specific.

Apple's `SpeechTranscriber` does not tell speakers apart.

The "Others" track is clean digital audio from the meeting app, without room reverb. That is a good case for acoustic speaker diarisation. "Me" is already known and is not diarised.

## Decision

1. **Diarise only the "Others" track, live, on the device.**
   - The model is LS-EEND, a streaming end-to-end diarisation model, as CoreML exports. It needs no separate embedding or clustering step and tracks up to 10 speakers at 10 Hz.
   - The runtime is FluidAudio's `LSEENDDiarizer`.
   - Voices are shown as "Speaker 1", "Speaker 2" and so on, numbered in the order they first speak.
2. **No audio kept for diarisation.**
   - The audio is fed in as it arrives and discarded, like the recogniser's input.
   - An offline pass after Stop (pyannote Community-1) would need the whole track in memory: about 230–460 MB for two hours. It was rejected for that reason.
3. **Names come only from the user.**
   - A click on a speaker label renames that voice in every turn and in the export.
   - Two voices can be merged when the model split one person.
   - Names and merges live only in memory with the transcript.
4. **No voice profiles.**
   - Saywing never stores speaker embeddings or attractors.
   - It never recognises a person across meetings and never tries to identify anyone.
   - Model state dies with the transcript.
5. **Assignment.**
   - Recognised words carry audio time ranges. Each word of "Others" goes to the voice that spoke most during it.
   - A change of voice starts a new turn.
   - Words without a voice stay "Others".
6. **Fallback.** If the model is missing or fails, the transcript works as before with "Others". The window says once that voices are not told apart.
7. **PDF export.**
   - Save offers PDF (first), Markdown and plain text.
   - The PDF is laid out on A4 with Core Text.
   - It is tagged (heading and paragraphs) so screen readers can follow it.
   - Its document info holds only the title and "Saywing".
   - Writing still happens only through the explicit save panel.

## Model and code

| Item | Value |
|---|---|
| Model | LS-EEND, variant chosen by measurement (see Open), 100 ms step |
| Source | `FluidInference/ls-eend-coreml`, revision `28ce1b1f8ef186729df63b3886fbaae7bc10c4a1`, folder `optimized/<variant>/100ms/` |
| Upstream | [Audio-WestlakeU/FS-EEND](https://github.com/Audio-WestlakeU/FS-EEND), Di Liang & Xiaofei Li, IEEE TASLP 2025 |
| License | MIT (export and upstream). The fine-tuning datasets (AMI, CALLHOME, DIHARD II/III) keep their own terms; see release gate. |
| Size | 44.4 MB per variant (`weights/weight.bin`) plus about 0.2 MB of graph and metadata |
| Hashes | Every file is pinned in `Runtime/Diarization/ls-eend-manifest.json` with size and SHA-256 |
| Runtime code | [FluidAudio](https://github.com/FluidInference/FluidAudio), Apache-2.0, only the `Diarizer` trait (no TTS, no prebuilt NeMo binary). Pin: see Open. |
| Delivery | Bundled in the app; never downloaded at runtime. Weights are not committed to Git. |

## Consequences

- One new third-party Swift package and one bundled model (about 45 MB). No new network path: the model is loaded from the app bundle with `LSEENDModel(modelURL:)`. FluidAudio's download helpers are never called.
- Diarisation costs CPU next to the two speech transcribers. It must be measured in the 60-minute gate of ADR 0006.
- The project's own LS-EEND documentation states recordings up to one hour. Transcripts may run two hours; the second hour must be checked in the gate.
- Speaker voices are biometric data under GDPR Art. 9 as soon as they are used to identify someone. Saywing does not identify anyone, keeps nothing, and the user names voices by hand. This belongs in the legal review that ADR 0006 already makes a release gate.

## Open

- **FluidAudio build permission.** The released v0.17.7 does not yet have the `Diarizer` trait; it arrived on `main` with #990. Building FluidAudio code (commit `2d6c42ca5f3accc0faf9fee9e0fff5b9b2cf6042`) was blocked in the agent session and needs the owner's explicit go. The choice is between that commit with only `Diarizer`, v0.17.7 with every subsystem, or waiting for the next release.
- **Variant.** AMI (meetings, up to 4 speakers), CALLHOME (calls, up to 7) or DIHARD III (general, up to 10). Choose by measuring on recorded multi-speaker calls.

## Validation gates

- Real calls with 2, 3 and 5 remote participants:
  - wrongly attributed words;
  - voices split or merged;
  - latency of labels.
- CPU and memory over 60 and 120 minutes with both transcribers running.
- A file-system check that no audio or model state is written during a session.
- License chain of the bundled variant, including its training datasets, before a public release.
