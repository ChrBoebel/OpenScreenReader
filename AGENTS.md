# OpenScreenReader agent guidance

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
- `Esc` and explicit Stop controls cancel the complete active pipeline immediately. By the owner's 2026-09-09 decision, repeating the primary hotkey adds another region to the queue during speech/preparation, without interrupting playback. Repeats during an existing selection/capture/OCR do not duplicate or cancel it.
- No cloud OCR, cloud TTS, silent fallback, account, or default telemetry.
- No persistent screenshot, OCR text, audio history, or automatic clipboard write during reading. Owner decision 2026-10-13: explicitly started local dictation may paste through the clipboard and restore it only while still owned; newer copies must win.
- Qwen3-ASR-0.6B is the owner-approved local German/English dictation model (2026-10-13); this ASR decision is separate from Qwen3-TTS. No recording on launch and no automatic runtime network/downloads. Owner decision 2026-10-14: builds bundle Whisper Turbo as the default dictation model; Qwen3-ASR and Whisper Large v3 may be downloaded only after the user explicitly confirms an install, from the pinned Hugging Face revision, with every file SHA-256-verified against the bundled manifest before use. No other runtime network access.
- Supertonic 3 is the default TTS model by the owner's 2026-09-05 listening decision; architecture must remain provider-based. Qwen is comparison-only, never an automatic fallback. Supertonic's OpenRAIL-M and upstream maintenance risks remain release gates.
- The official macOS MVP should include its pinned, verified default model without committing weights to Git; packaging and the complete license chain must pass a release gate first.
- The project is not a complete replacement for VoiceOver.

## Engineering rules

- Gather context and trace symbols before editing.
- Use focused changes; avoid speculative abstractions and unrelated refactors.
- Use test-driven development for observable behavior.
- Every asynchronous operation needs explicit cancellation and stale-result protection.
- Treat privacy requirements as testable behavior, not documentation only.
- Do not add a network dependency to the runtime path without explicit project-owner approval.
- Do not add, download, or redistribute model weights without documenting source, exact version, size, hash when available, and license.
- Do not copy code from repositories without verifying an explicit compatible license.
- GPL code requires an explicit project-level licensing decision before integration; architecture inspiration alone is acceptable, code copying is not.
- Keep secrets and credentials out of the repository.
- Do not add AI/agent authorship to source headers, commits, changelogs, or project metadata.
- Do not commit, push, create remotes, or publish releases unless explicitly requested.
- For authorized changes, use a focused `codex/` feature branch and a pull request targeting `main`. Do not commit or push directly to `main`; the earlier direct-push workflow is superseded by the owner's PR-workflow decision. Leave PRs open for review and merge only when explicitly requested. Do not rewrite already published history.

## Verification expectations

Before reporting a task complete:

- run the relevant tests;
- run the build for affected targets;
- exercise user-visible flows when possible;
- report actual outputs and remaining gaps;
- never substitute mocked or fabricated execution results for a blocked real path.

## Early architecture discipline

The proposed Python/MLX worker is a hypothesis, not a fixed commitment. Validate packaging, signing, cancellation, memory, startup time, and offline operation before establishing it as production architecture.
