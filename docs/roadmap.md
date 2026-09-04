# Roadmap

## Phase 0 — Foundation

- [x] Establish product vision, UX constraints, privacy principles, architecture hypothesis, and research summary.
- [x] Initialize local Git repository.
- [ ] Choose a coding agent in BB.
- [x] Confirm the pre-signing baseline bundle identifier and minimum macOS version.
- [x] Choose an Xcode application project with unit and UI test targets.
- [x] Choose a native SwiftUI/AppKit macOS implementation with Windows-ready provider boundaries.
- [x] Select a bundled default-model policy for the macOS MVP, subject to the packaging and license gates.

## Phase 1 — Technical spikes

- [x] Native menu bar shell with an automated UI smoke test.
- [ ] Global hotkey registration and conflict handling.
- [ ] Multi-monitor region-selection overlay.
- [ ] Selected-region capture with ScreenCaptureKit/CoreGraphics.
- [ ] Apple Vision OCR for German and English.
- [ ] Local Qwen MLX worker with streamed first chunk.
- [ ] Cancellation from `Esc` through the complete pipeline.
- [ ] Packaged worker and bundled-model signing/notarization experiment.
- [ ] Offline and temporary-file privacy verification.

Each spike needs a small reproducible test or benchmark and a written decision before it becomes production architecture.

## Phase 2 — MVP

- [ ] Integrate hotkey → overlay → screenshot → OCR → TTS → playback.
- [ ] Add sentence segmentation and text normalization.
- [ ] Add menu bar settings for hotkey, voice, speed, and model lifecycle.
- [ ] Add explicit permissions onboarding.
- [ ] Add bundled-model manifest, source/license display, and integrity checks.
- [ ] Add error recovery and worker health monitoring.
- [ ] Add automated unit and integration tests.
- [ ] Validate memory, latency, and energy use on an M4 with 16 GB RAM.

## Phase 3 — First public release

- [ ] Accessibility review and VoiceOver labels.
- [ ] Privacy verification guide.
- [ ] Third-party notices and model license review.
- [ ] Signed and notarized Apple Silicon build.
- [ ] Demo GIF/video and screenshots.
- [ ] GitHub issue templates and contribution guide refinement.
- [ ] Public release only after a manual data-flow and licensing review.

## Later candidates

- repeated capture of the previous region;
- automatic language switching;
- Supertonic low-memory mode;
- sentence or word highlighting;
- custom pronunciation rules;
- optional plugin interface for additional local providers;
- Homebrew Cask.
