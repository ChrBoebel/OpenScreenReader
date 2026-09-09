# OpenScreenReader

<p align="center">
  <img src="docs/brand-identity/assets/open-screen-reader-app-icon.png" alt="OpenScreenReader owl app logo" width="160">
</p>

**Select. Listen. Stay private.**

OpenScreenReader is a planned open-source macOS menu bar app that reads any visible text aloud with natural, fully local AI voices.

> Status: experimental native macOS menu bar app with a configurable global hotkey, region selection, in-memory ScreenCaptureKit capture, local German/English Apple Vision OCR, and automatic local Supertonic 3 speech. The owner selected Supertonic after the German listening comparison; M1 is the initial default voice. The pinned development worker and model are installed separately, not bundled for distribution. Verification and remaining limitations are recorded in the [Supertonic integration notes](docs/research/supertonic-integration.md). Finder-hotkey start tests have been intermittent, and the broader permission/display/layout matrix remains open. No application has been released yet.

## Product promise

**Everyday controls (development):** click the capsule's **··· / +N** button for Pause/Resume, speed, Next and the queue. Queue rows can be moved up/down, removed, or played immediately. Text beginnings appear only in this explicitly opened view and remain session-local. Escape/Stop still clears everything, including paused or prepared audio. **Set Up & Test…** explains permissions, checks macOS preflight and starts a real screen-region test; an error capsule's **?** button opens this help directly. See [current verification and remaining gates](docs/everyday-reading-verification.md).

Default shortcut: **⌘⇧Y (Command + Shift + Y)** starts region selection. Press it again during speech or voice preparation to select another region and queue its text without interrupting playback. While a selection/capture/OCR is already in progress, repeats do not duplicate or cancel it. **Escape**, the capsule's stop button, or **Stop Reading** in the menu stops everything. To change the shortcut, open the menu bar icon → **Settings… → Keyboard shortcut → Read / Add to queue**, choose modifiers and a key, then **Apply Shortcut**. The choice takes effect immediately and is saved locally across restarts. **Restore Default** returns to ⌘⇧Y. Changes are blocked during an active operation.

Supported keys are A–Z, 0–9, and Space, combined with Command, Option, or Control; Shift is optional. Failed registration leaves the previous shortcut active and does not save the rejected choice. System-wide registrations are checked through Carbon, but ordinary app commands and services cannot all be detected: Command-only choices require confirmation, and the default overlaps macOS’s “Make Sticky” service. Keys are resolved from the current keyboard layout when registered; restart the app or apply the shortcut again after changing layouts.

**Reading speed:** choose 0.75×, 1×, 1.25×, 1.5×, 1.75× or 2× in Settings → **Reading speed** or the menu bar's **Speed** submenu. Changes apply during playback and are remembered locally. A native time/pitch unit changes rate with pitch fixed at zero; Supertonic still generates its normal-speed voice. Faster starting rates increase the pre-roll to preserve about one second of playback headroom. The fixed PCM limit is eight seconds of source audio (about 1.35 MiB), retaining up to four seconds of look-ahead at 2×.

**Queue another text:** press **the same reading shortcut again** while preparing or speaking, or use **Add Screen Region to Queue…** in the menu. Drag another region; the existing speech continues while OCR prepares it. Up to five waiting texts (8,000 characters each) are read in order. The capsule's **+N** badge shows the number waiting; **Next Text** in the menu skips the current text. If speech ends while a new region is being selected/recognized, the app waits. Escape or an explicit Stop control stops everything and clears all pending text. There is no history, automatic clipboard write, or queue persistence across app restarts. The previous **⌘⌥⇧Y** shortcut remains an optional additional alias, configurable under **Additional queue shortcut**; it is no longer needed for this workflow. See [speed and queue verification](docs/speed-and-queue-verification.md).

Implementation checks and remaining limitations are recorded in [Shortcut verification](docs/shortcut-verification.md).

**Prepared transitions:** the model stays loaded for the reading session. Once the current text's synthesis is complete, the same worker prepares up to eight source seconds of the next queued text while current audio is still playing. Only one successor is prepared; it is never played early or saved to disk. A prepared handoff includes a short 120 ms separation. Late additions may still need synthesis time. Escape/Stop discards all prepared audio and releases the worker. See [warm queue verification](docs/warm-queue-verification.md).

With the development runtime installed, selecting text starts speech automatically. The menu shows **Preparing voice**, then **Speaking**; Escape or **Stop Reading** cancels. Settings shows Supertonic 3, its machine-generated M1 voice, model license, and local runtime availability. Selections are limited to 8,000 characters; no Qwen, cloud, or system voice is substituted on failure. See [runtime installation and verification](docs/research/supertonic-integration.md). Screenshots are released after OCR; text and audio are retained only for the active reading, without history or automatic clipboard writes.

A small floating reading panel appears after capture on the selected display. Choose **Bottom, Left or Right** in Settings → **Control position**, or drag its waveform to dock at the nearest edge. Side positions use an upright vertical layout. The edge and relative offset are remembered locally; **Preview & move control** lets you position it without OCR or speech. Dragging never activates the separate stop/close button or takes keyboard focus. Its stop button cancels the whole operation. Completed/stopped feedback disappears automatically; empty-text and error notices remain until dismissed or a new selection starts. The panel contains status only, never the selected text. See [panel behavior and verification](docs/reading-panel-verification.md).

The reading control is a small text-free capsule. After capture, the selection frame visibly collapses into a glowing dot at the saved edge of the display and springs open into the capsule; the opening sound lands with it. Nine Voice Mint bars answer the rendered speech level, brighten towards Mint Light at their peaks and pass a light along the row on each syllable. Recognition shows a travelling light, preparation lets the bars rise one by one, and finished, stopped and attention states draw their own symbol. Hover reveals an Esc keycap; attention states show two words for a moment. The round 44 pt stop button compresses on press with haptic, click and release feedback. VoiceOver hears every state change. Everything follows macOS Reduce Motion, Reduce Transparency and Increase Contrast. Five original, locally synthesized stereo cues (opening, completion, attention, key down, key up) share one wood-and-water sound family (marimba bars, water drops, a low thud, a small room); while the voice is prepared the bars breathe and a drop ripples through them; volume and Off live in Settings → **Interface sounds**. Cancellation itself is silent and cues stop before speech.

- Press a global keyboard shortcut.
- Drag a rectangle over any visible text.
- Recognize it locally with Apple Vision.
- Start natural speech automatically with a local TTS model.
- Repeat the same shortcut to queue more text; stop immediately with `Esc` or the stop button.

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
