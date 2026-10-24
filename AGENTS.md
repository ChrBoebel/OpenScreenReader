# Saywing (OpenScreenReader) agent guidance

Guidance for coding agents and human contributors working in this repository. Dated "project decisions" record when a maintainer approved a behavior; they remain binding until a later decision supersedes them.

## Read first

Before changing code or architecture, read:

1. `README.md`
2. `docs/product-vision.md`
3. `docs/ux-requirements.md`
4. `docs/architecture.md`
5. `docs/privacy.md`
6. `docs/research/market-and-tts-findings.md`
7. `docs/roadmap.md`

## Product invariants

- Native macOS menu bar experience.
- Hotkey → drag region → local OCR → automatic local speech.
- `Esc` and explicit Stop controls cancel the complete active pipeline immediately. By project decision (2026-09-09), repeating the primary hotkey adds another region to the queue during speech/preparation, without interrupting playback. Repeats during an existing selection/capture/OCR do not duplicate or cancel it.
- No cloud OCR, cloud TTS, silent fallback, account, or default telemetry.
- No persistent screenshot, OCR text, audio history, or automatic clipboard write during reading. Project decision (2026-10-13): explicitly started local dictation may paste through the clipboard and restore it only while still owned; newer copies must win.
- Whisper large-v3-turbo (pinned 4-bit MLX conversion) is the default local German/English dictation model by project decision (2026-10-14); Qwen3-ASR-0.6B (approved 2026-10-13) stays selectable, never an automatic fallback. These ASR decisions are separate from Qwen3-TTS. An optional user vocabulary is stored only in local preferences. No recording on launch and no automatic runtime network/downloads. Project decision (2026-10-14): builds bundle only Whisper Turbo; Qwen3-ASR and Whisper Large v3 may be downloaded only after the user explicitly confirms an install, from the pinned Hugging Face revision, with every file SHA-256-verified against the bundled manifest before use. Project decision (2026-10-14): transparent, disableable Sparkle update checks and user-confirmed signed app updates are also approved; no content upload or telemetry. No other runtime network access.
- Supertonic 3 is the default TTS model by project decision (2026-09-05, after a listening comparison); architecture must remain provider-based. Qwen is comparison-only, never an automatic fallback. Supertonic's OpenRAIL-M and upstream maintenance risks remain release gates.
- The official macOS MVP should include its pinned, verified default model without committing weights to Git; packaging and the complete license chain must pass a release gate first.
- Project decision (2026-10-15, [ADR 0006](docs/decisions/0006-local-meeting-transcript.md)): an explicitly started, consented local meeting transcript may capture the microphone and the system audio of other apps (private Core Audio tap excluding Saywing) and recognise both with Apple's on-device `SpeechTranscriber` on macOS 26+ for already-installed locales only. No audio on disk, no transcript history, no automatic start, no speech-asset download, no summary; the transcript leaves memory only through an explicit Copy or Save.
- The project is not a complete replacement for VoiceOver.

## Engineering rules

- Gather context and trace symbols before editing.
- Use focused changes; avoid speculative abstractions and unrelated refactors.
- Use test-driven development for observable behavior.
- Every asynchronous operation needs explicit cancellation and stale-result protection.
- Treat privacy requirements as testable behavior, not documentation only.
- Do not add a network dependency to the runtime path without an explicit project decision by the maintainers.
- Do not add, download, or redistribute model weights without documenting source, exact version, size, hash when available, and license.
- Do not copy code from repositories without verifying an explicit compatible license.
- GPL code requires an explicit project-level licensing decision before integration; architecture inspiration alone is acceptable, code copying is not. SciPy's GCC runtime libraries are covered by [ADR 0007](docs/decisions/0007-gcc-runtime-libraries.md).
- Keep secrets and credentials out of the repository.
- Do not add AI/agent authorship to source headers, commits, changelogs, or project metadata.
- Do not commit, push, create remotes, or publish releases unless explicitly requested.
- Use a focused feature branch and a pull request targeting `main`; see `CONTRIBUTING.md`. Do not commit or push directly to `main`. Leave PRs open for review and merge only when a maintainer explicitly approves. Do not rewrite already published history.

## Verification expectations

Before reporting a task complete:

- run the relevant tests;
- run the build for affected targets;
- exercise user-visible flows when possible;
- report actual outputs and remaining gaps;
- never substitute mocked or fabricated execution results for a blocked real path.

## Early architecture discipline

The proposed Python/MLX worker is a hypothesis, not a fixed commitment. Validate packaging, signing, cancellation, memory, startup time, and offline operation before establishing it as production architecture.
