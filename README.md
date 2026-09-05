# OpenScreenReader

<p align="center">
  <img src="docs/brand-identity/assets/open-screen-reader-app-icon.png" alt="OpenScreenReader owl app logo" width="160">
</p>

**Select. Listen. Stay private.**

OpenScreenReader is a planned open-source macOS menu bar app that reads any visible text aloud with natural, fully local AI voices.

> Status: experimental native macOS menu bar app with a configurable global hotkey, region selection, in-memory ScreenCaptureKit capture, local German/English Apple Vision OCR, and automatic local Supertonic 3 speech. The owner selected Supertonic after the German listening comparison; M1 is the initial default voice. The pinned development worker and model are installed separately, not bundled for distribution. Verification and remaining limitations are recorded in the [Supertonic integration notes](docs/research/supertonic-integration.md). Finder-hotkey start tests have been intermittent, and the broader permission/display/layout matrix remains open. No application has been released yet.

## Product promise

Default shortcut: **⌘⇧Y (Command + Shift + Y)** starts region selection; pressing the selected shortcut again or Escape cancels. To change it, open the menu bar icon → **Settings… → Keyboard shortcut**, choose modifiers and a key, then **Apply Shortcut**. The choice takes effect immediately and is saved locally across restarts. **Restore Default** returns to ⌘⇧Y. Changes are blocked during an active operation so its cancellation shortcut remains available.

Supported keys are A–Z, 0–9, and Space, combined with Command, Option, or Control; Shift is optional. Failed registration leaves the previous shortcut active and does not save the rejected choice. System-wide registrations are checked through Carbon, but ordinary app commands and services cannot all be detected: Command-only choices require confirmation, and the default overlaps macOS’s “Make Sticky” service. Keys are resolved from the current keyboard layout when registered; restart the app or apply the shortcut again after changing layouts.

Implementation checks and remaining limitations are recorded in [Shortcut verification](docs/shortcut-verification.md).

With the development runtime installed, selecting text starts speech automatically. The menu shows **Preparing voice**, then **Speaking**; Escape, the repeated shortcut, or **Stop Reading** cancels. Settings shows Supertonic 3, its machine-generated M1 voice, model license, and local runtime availability. Selections are limited to 8,000 characters; no Qwen, cloud, or system voice is substituted on failure. See [runtime installation and verification](docs/research/supertonic-integration.md). Screenshots are released after OCR; text and audio are retained only for the active reading, without history or automatic clipboard writes.

A small floating reading panel appears after capture, at the bottom of the selected display. It shows recognition, preparation, and playback without taking keyboard focus. Its stop button cancels the whole operation. Completed/stopped feedback disappears automatically; empty-text and error notices remain until dismissed or a new selection starts. The panel contains status only, never the selected text. See [panel behavior and verification](docs/reading-panel-verification.md).

The reading control is a small text-free capsule. After capture, the selection frame visibly collapses into a glowing dot at the bottom of the display and springs open into the capsule; the opening sound lands with it. Nine Voice Mint bars answer the rendered speech level, brighten towards Mint Light at their peaks and pass a light along the row on each syllable. Recognition shows a travelling light, preparation lets the bars rise one by one, and finished, stopped and attention states draw their own symbol. Hover reveals an Esc keycap; attention states show two words for a moment. The round 44 pt stop button compresses on press with haptic, click and release feedback. VoiceOver hears every state change. Everything follows macOS Reduce Motion, Reduce Transparency and Increase Contrast. Five original, locally synthesized stereo cues (opening, completion, attention, key down, key up) share one wood-glass-breath sound family with a small synthetic room; volume and Off live in Settings → **Interface sounds**. Cancellation itself is silent and cues stop before speech.

- Press a global keyboard shortcut.
- Drag a rectangle over any visible text.
- Recognize it locally with Apple Vision.
- Start natural speech automatically with a local TTS model.
- Stop immediately with `Esc` or the same shortcut.

The official macOS release is intended to include its default local speech model. After installation, OCR and speech synthesis should work without an internet connection or a separate model setup step. Screenshots, recognized text, and generated audio should remain in memory by default.

## Why this project?

Existing tools generally offer either fast local screen OCR with macOS system voices or natural cloud speech. OpenScreenReader explores the missing combination:

- TextSniper-like one-gesture UX;
- modern on-device neural speech;
- transparent, auditable privacy through open source.

## Planned technology

- SwiftUI and AppKit
- ScreenCaptureKit/CoreGraphics
- Apple Vision (`VNRecognizeTextRequest`)
- Supertonic 3 local ONNX worker as the selected default
- Native 44.1 kHz playback; M1, normal speed, eight denoising steps
- Qwen3-TTS Swift/MLX retained as a comparison experiment, not a fallback

The bundled model and runtime will be pinned, hashed, license-audited, and injected into release builds without committing model weights to Git.

The implementation architecture is provisional and must be validated with focused technical spikes before the full MVP is built.

Supertonic weights/stock voices use BigScience Open RAIL-M, not the project's Apache-2.0 license. Upstream has announced the end of development/support. License obligations, maintainability, and packaging remain explicit release gates; see [source and license record](docs/research/supertonic-listening-comparison.md).

## Documentation

- [Product vision](docs/product-vision.md)
- [UX requirements](docs/ux-requirements.md)
- [Proposed architecture](docs/architecture.md)
- [Privacy principles](docs/privacy.md)
- [Research summary](docs/research/market-and-tts-findings.md)
- [Roadmap](docs/roadmap.md)
- [Architecture decisions](docs/decisions/)
- [Capture implementation and verification](docs/capture-verification.md)
- [Local OCR implementation and verification](docs/ocr-verification.md)
- [Approved brand system](docs/brand-identity/BRAND_SYSTEM.md)
- [Contributing](CONTRIBUTING.md)

## Privacy principles

The official build should have:

- no account requirement;
- no cloud OCR or cloud TTS;
- no telemetry by default;
- no automatic clipboard writes;
- no persistent screenshot, OCR-text, or audio history;
- clear disclosure of every required macOS permission and network request.

The MVP runtime should make no network request. Downloading the signed application from the project website is outside the application runtime.

See [docs/privacy.md](docs/privacy.md) for the enforceable requirements.

## License

The project code and documentation are licensed under the [Apache License 2.0](LICENSE). Model weights, voices, runtimes, and third-party assets retain their own licenses and must be documented separately before distribution.
