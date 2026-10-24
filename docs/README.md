# Saywing documentation

## Using Saywing

- [Privacy](privacy.md) — privacy principles and testable requirements: network access, storage, permissions, worker sandbox, dictation and meeting transcripts.
- [Roadmap](roadmap.md) — what is integrated, which release gates are still open, and later candidates.

## How it works

- [Architecture](architecture.md) — system overview, native app, speech process, model delivery, cancellation, dictation and meeting transcript.
- [Architecture decisions](decisions/README.md) — architecture decision records (ADRs) with their context and consequences.

## Building and releasing

- [Runtime build](runtime-build.md) — how the bundled Python worker runtimes are built reproducibly from pinned, hash-verified inputs.
- [Development packaging](development-packaging.md) — local development packaging of a self-contained app; not a release.
- [Distribution and updates](release-and-updates.md) — signing, notarization, packaging, publishing, Sparkle updates and the remaining public-release gates.
- [Release approval records](../release/) — machine-readable gates checked before a build may be published.

## Design and research

Background material that informed the product; it is not user documentation.

- [Product vision](product-vision.md) — vision, positioning, target audiences, deliberate boundaries and MVP success criteria.
- [UX requirements](ux-requirements.md) — primary flow, reading panel, performance and text-fidelity targets, setup, dictation and meeting transcript.
- [Brand system](brand-identity/BRAND_SYSTEM.md) — the current Saywing name, mark, color, type, sound and voice.
- Research:
  - [Market and local TTS findings](research/market-and-tts-findings.md) — market summary and local text-to-speech model evaluation (2026-09-04).
  - [Speech integration readiness](research/tts-integration-readiness.md) — initial Qwen3-TTS investigation and data-only download (2026-09-05).
  - [Native Qwen development runtime](research/swift-runtime-evaluation.md) — local Swift/MLX Qwen3-TTS experiment and its measurements.
  - [German listening comparison](research/german-voice-comparison.md) — Qwen3-TTS voice comparison of Serena, Ryan and Aiden.
  - [Supertonic 3 listening experiment](research/supertonic-listening-comparison.md) — isolated comparison sample of the alternative Supertonic 3 model.
  - [Supertonic 3 integration](research/supertonic-integration.md) — selection of Supertonic 3 as the default voice and its integration and verification.
  - [Local Qwen dictation runtime](research/qwen-dictation-runtime.md) — Qwen3-ASR dictation integration, pinned assets and clipboard handling.
  - [Local Whisper Turbo dictation](research/whisper-turbo-dictation.md) — Whisper Turbo as a selectable dictation model and its packaged provenance.
  - [Local Whisper Large v3 dictation](research/whisper-large-v3-dictation.md) — Whisper Large v3 (8-bit) as an optional, user-installed dictation model.
  - [Whisper Hardened Runtime correction](research/whisper-hardened-runtime-patch.md) — packaging fix for the Whisper worker under a Developer ID-signed Hardened Runtime.

## Licenses

- [Third-party licenses](licenses/README.md) — license texts and notices for third-party software, models and voices included in builds.
