# Saywing roadmap

## Brand and product direction — 2026-10-13

- [x] Owner selected Saywing, Quiet Owl, and “Vorlesen & Diktieren für macOS”.
- [x] Update native product name, app icon, template menu glyph, UI palette and current brand documentation.
- [ ] Validate name comprehension with real participants; no results are implied by the naming decision.
- [ ] Complete trademark similarity review and confirm desired domain with a registrar.
- [x] Owner approved Qwen3-ASR dictation integration with clipboard restore (2026-10-13); implemented in the private app build.
- [x] Whisper Turbo becomes the default dictation model with an optional local vocabulary (owner decision 2026-10-14); [measurement and gaps](dictation-vocabulary-verification.md).
- [ ] Complete dictation target-app matrix, real microphone/Hotkey walkthrough in the integrated bundle, clean-Mac packaging and distribution gates.

## Current delivery — 2026-09-09

- [x] Live pitch-preserving speed (0.75–2×), bounded FIFO queue and same-shortcut additions.
- [x] Warm model session and bounded preparation of the next queued text.
- [x] Pause/resume with bounded audio backpressure and stop while paused.
- [x] On-demand capsule controls: speed, next text, queue preview, remove, move and play now; previews remain RAM-only.
- [x] First-use setup view with permission preflight, explicit requests and a real-region test entry point. Preflight is not presented as an end-to-end success.
- [x] Conservative soft-hyphen/spacing repair and abbreviation/ordinal-aware speech segmentation.
- [ ] Subjective German/English listening review of numbers, headings and abbreviations; no automatic speculative number expansion.
- [ ] Complete real UI regression: installed build, queue editing while speaking/paused, all three panel edges, full screen/Spaces and external display. Computer Use currently blocked by the locked Mac.
- [x] Private self-contained packaging spike: model/runtime bundled, isolated imports, relocated real speech/pause/cancellation and deep signature verification. Public release and clean-Mac validation remain separately gated below.

Details and current evidence: [everyday reading verification](everyday-reading-verification.md).

## Phase 0 — Foundation

- [x] Establish product vision, UX constraints, privacy principles, architecture hypothesis, and research summary.
- [x] Initialize local Git repository.
- [x] Confirm the pre-signing baseline bundle identifier and minimum macOS version.
- [x] Choose an Xcode application project with unit and UI test targets.
- [x] Choose a native SwiftUI/AppKit macOS implementation with Windows-ready provider boundaries.
- [x] Select a bundled default-model policy for the macOS MVP, subject to the packaging and license gates.

## Phase 1 — Technical spikes

- [x] Native menu bar shell with an automated UI smoke test.
- [x] Configurable global hotkey registration, local preference persistence, and transactional conflict handling. Broader layout/system-shortcut coverage remains experimental.
- [x] Implement multi-monitor region-selection overlay; broad physical display/Space verification remains open.
- [x] Implement selected-region capture with ScreenCaptureKit; permission-dependent tests remain separate gates.
- [x] Basic Apple Vision OCR for German and English ([verification and remaining layout checks](ocr-verification.md)).
- [x] Development-only native Qwen MLX worker with streamed first chunk ([pinned runtime and real checks](research/swift-runtime-evaluation.md)); warm performance and release packaging remain open.
- [x] Select Supertonic 3 as default after owner listening comparison and implement a local ONNX development worker; [integration and verification](research/supertonic-integration.md). Qwen remains comparison-only, not a fallback.
- [x] Cancellation from `Esc` and explicit Stop controls; broader device/layout stress coverage remains open. Historical repeated-shortcut cancellation was superseded by same-shortcut queueing on 2026-09-09.
- [ ] Packaged worker and bundled-model signing/notarization experiment.
- [ ] Offline and temporary-file privacy verification.

Each spike needs a small reproducible test or benchmark and a written decision before it becomes production architecture.

## Phase 2 — MVP

- [ ] Production-ready hotkey → overlay → screenshot → OCR → TTS → playback (development integration works; distribution, broader reliability, and performance gates remain).
- [x] Add bounded sentence segmentation and conservative text normalization; text-fidelity listening matrix remains open.
- [x] Add menu bar settings for the hotkey, including restore-default and conflict feedback.
- [x] Add a small branded reading-status panel with full-pipeline stop, without taking focus; [verification and remaining display/accessibility checks](reading-panel-verification.md).
- [x] Add speed settings and session-bounded model lifecycle.
- [ ] Add voice selection after listening review.
- [x] Add explicit permissions onboarding; real installed-app walkthrough remains to be verified.
- [x] Guided one-decision-per-page setup with in-window reading test, System Settings hint and just-in-time setup (2026-10-14); [verification and open manual checks](guided-setup-verification.md).
- [ ] Add bundled-model manifest, source/license display, and integrity checks.
- [x] Add worker packet watchdogs, fail-closed cleanup and direct setup/error help; broader recovery stress tests remain open.
- [x] Add automated unit and integration tests; do not equate skipped permission/UI paths with success.
- [ ] Validate memory, latency, and energy use on an M4 with 16 GB RAM.

## Phase 3 — First public release

- [ ] Accessibility review and VoiceOver labels. Code audit and fixes done on 2026-10-14 ([verification](guided-setup-verification.md#rückmeldung-am-ort-des-geschehens)); a live VoiceOver/keyboard walkthrough remains open.
- [ ] Privacy verification guide.
- [ ] Third-party notices and model license review.
- [ ] Signed and notarized Apple Silicon build.
- [ ] Demo GIF/video and screenshots.
- [ ] GitHub issue templates and contribution guide refinement.
- [ ] Public release only after a manual data-flow and licensing review.

## Later candidates

- repeated capture of the previous region;
- automatic language switching;
- additional local providers, if justified by listening tests;
- sentence or word highlighting;
- custom pronunciation rules;
- optional plugin interface for additional local providers;
- Homebrew Cask.
