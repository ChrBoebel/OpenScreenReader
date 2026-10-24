# Changelog

Notable changes to Saywing (formerly OpenScreenReader). Dates are when the change was integrated during development. Version numbers will be added with public releases.

## [Unreleased]

- **Repository renamed to `ChrBoebel/saywing`.** Old `ChrBoebel/OpenScreenReader` links redirect. Technical identifiers keep the OpenScreenReader name for compatibility.
- **README overhaul.** Read aloud and dictation lead, followed by privacy, an honest install status, requirements and an FAQ (including how Saywing differs from Speak Selection). Test gaps moved into a collapsible status section, and the runtime build description now points to the one-command assembly from public sources.
- **Docs wording.** The privacy requirements and roadmap describe decisions in neutral project language with their dates. The issue chooser links to Discussions for questions and ideas.

## 2026-10-15

- **Meeting transcript (macOS 26+).** An explicitly started, consented live transcript of the microphone ("Me") and other apps' audio ("Others"). It uses a private Core Audio tap and Apple's on-device `SpeechTranscriber`. Local echo suppression keeps your speakers' playback out of your side. Audio is never saved; the text stays in memory until Copy, Save or Discard. The transcript stops after 2 hours, after 10 silent minutes, on sleep, or on Stop. See [ADR 0006](docs/decisions/0006-local-meeting-transcript.md).
- Intel (x86_64) builds: reading with Supertonic 3, dictation with Whisper Turbo through whisper.cpp.

## 2026-10-14

- **Whisper large-v3-turbo is the bundled default dictation model.** Qwen3-ASR and Whisper Large v3 are installed only after the user explicitly confirms a download from a pinned Hugging Face revision, with every file SHA-256-verified before use. An optional local vocabulary was added.
- **Guided, resumable setup.** The setup flow shows one decision per page: permissions, model and shortcuts, then a real reading or dictation test. Progress survives an app restart, and restoring setup never starts a capture or recording.
- **Shared capsule.** Reading and dictation share one compact capsule. The reading capsule is 136 × 28 pt; the dictation capsule is 120 × 28 pt with separate discard and finish targets. Hover reveals Pause/Resume and the options; the same controls are available from the menu and to VoiceOver.
- **Selection gestures** like ⌘⇧4 (Space to move, Shift to lock an edge, Option to grow around the start point). A click reads the paragraph under the pointer.
- **Dictation sounds and hands-free mode.** Short local cues mark the microphone opening, hands-free latching and closing. Discarding is silent.
- **Localization.** All interface text is in string catalogs with complete English and German translations; `scripts/check-localization.py` verifies coverage.
- **Updates.** Sparkle 2.10.0 integration with disableable update checks, native update UI and protection against relaunching during an active operation. Developer ID signing and notarization scripts were added.
- Docking of the reading control with projected momentum and springs.

## 2026-10-13

- **Renamed to Saywing** with a new app icon, menu bar glyph and palette. Technical identifiers keep the OpenScreenReader name for compatibility.
- **Local dictation.** German and English dictation into the focused text field, using push-to-talk on Fn, hands-free mode, Escape to discard, and clipboard paste with ownership-checked restoration. The model prepares automatically on launch without opening the microphone.

## 2026-09-09

- Live pitch-preserving reading speed from 0.75× to 2×.
- Bounded queue: repeating the reading shortcut adds another region without interrupting playback. The queue can be edited (reorder, remove, play now) from the capsule's options.
- Pause/Resume, and a warm model session that prepares the next queued text while the current one plays.
- First-use setup with permission preflight and a real region test.

## 2026-09-05

- Supertonic 3 (voice M1) selected as the default local voice after a German listening comparison. It runs as a sandboxed local ONNX worker. Qwen3-TTS remains a comparison experiment only, never a fallback.
- Floating reading-status panel with full-pipeline Stop.

## 2026-09-04

- Project foundation: native SwiftUI/AppKit menu bar app, configurable global hotkey, multi-display region selection, in-memory ScreenCaptureKit capture and local Apple Vision OCR for German and English.
