# Saywing

<p align="center">
  <img src="docs/brand-identity/assets/saywing-app-icon.png" alt="Saywing Text to Voice app icon" width="160">
</p>

**Vorlesen & Diktieren für macOS.**

**Text hören. Mit der Stimme schreiben.**

*Read aloud & dictate on your Mac. Hear text. Write with your voice.*

Saywing is an open-source macOS menu bar app for local screen reading and dictation. Select a screen region to hear its text, or dictate German and English into a text field with local Whisper Turbo (bundled), or Qwen3-ASR and Whisper Large v3 installed on request. Both flows are integrated in the private development build; public release gates remain open.

Previously OpenScreenReader. The Xcode project/scheme, Swift modules, bundle identifier and existing development-runtime directory retain their technical names so existing settings and installations remain compatible.

See the [approved Saywing identity](docs/brand-identity/BRAND_SYSTEM.md), [visual brand preview](docs/brand-identity/saywing.html), and [branch reconciliation with current verification](docs/branch-integration-verification.md).

> Status: experimental native macOS menu bar app with a configurable global hotkey, region selection, in-memory ScreenCaptureKit capture, local German/English Apple Vision OCR, and automatic local Supertonic 3 speech. The owner selected Supertonic after the German listening comparison; M1 is the initial default voice. The pinned development worker and model are installed separately, not bundled for distribution. Verification and remaining limitations are recorded in the [Supertonic integration notes](docs/research/supertonic-integration.md). Finder-hotkey start tests have been intermittent, and the broader permission/display/layout matrix remains open. No application has been released yet.

## Product promise

**Resumable setup (2026-10-14):** setup saves its current step before opening a permission prompt or System Settings. After an app restart it opens automatically at the next applicable step, checking actual grants again. **Later** keeps progress without reopening automatically; **Finish Setup** clears it. Restart help offers **Restart and Continue** when new access is not yet working. Restoring setup never starts a capture or recording. See [verification and limitations](docs/resumable-setup-verification.md).

**Setup models and shortcuts (2026-10-14):** each activity has Permissions → Model → Shortcuts → Try It. Choose an installed dictation model or explicitly confirm a pinned, verified download directly in setup. Interrupted installs retain the choice and offer a retry without restarting network activity automatically. Configure separate reading and dictation shortcuts and optionally disable Fn gestures; the same preferences appear in Settings. Model/shortcut pages remain available before permission grants. See [verification](docs/setup-models-shortcuts-verification.md).

**Local dictation (2026-10-13):** menu bar → **Set Up & Test…** grants microphone and Accessibility access; **Try Dictation…** opens a test field. Click in the target field, hold **Fn** to dictate and release to insert. **Double-tap Fn** or use **Fn + Space** for hands-free recording; tap Fn again to finish and **Esc** to discard. A short single tap is discarded; a third quick tap cancels. **⌥⇧Space** is the customizable default toggle alternative for keyboards without Fn. Fn control requires Accessibility access; quit other dictation apps that use Fn. Model (Qwen3-ASR / Whisper Turbo), language and clipboard delay live in **Settings → Dictate**; the test window offers a local field, and Debug builds add German/English public demos. Model changes are saved and load automatically, without recording. Finish or discard an active dictation before switching; only one selected model remains loaded and unavailable models fail visibly without fallback. Recording starts only on an explicit action, never on app launch. The selected model prepares automatically on launch and after wake/session reactivation, then stays ready while Saywing is open. No manual model loading is required; cold-start audio stays in RAM. Starting dictation stops reading; starting reading discards dictation. Paste temporarily uses the clipboard and restores all readable formats after 1 s (2 s optional), preserving any newer copy. Changed targets are not pasted into. See [setup, verification and remaining limits](docs/dictation-integration-verification.md) and [pinned runtime/privacy contract](docs/research/qwen-dictation-runtime.md). Quit the independent prototype before starting Saywing, since both use the same shortcut.

**Shared capsule update (2026-10-14):** the reading surface is 136 × 28 pt inside its existing 136 × 44 pt interaction area; dictation remains 120 × 28 pt with separate discard and finish targets. At rest it shows only the waveform and Stop; hovering crossfades the waveform to Pause/Resume and **··· / +N**, without changing size or moving Stop. Controls remain visible while their popover is open. Menu bar **Playback Controls…** and VoiceOver custom actions provide access without hovering. Side-docked glyphs stay upright and their popover opens toward the desktop. This replaces the rejected wider, permanently visible options design. See [verification](docs/integrated-capsule-verification.md).

**Everyday controls (development):** hover over the capsule and click **··· / +N** for Pause/Resume, speed, Next and the queue. Queue rows can be moved up/down, removed, or played immediately. Text beginnings appear only in this explicitly opened view and remain session-local. Escape/Stop still clears everything, including paused or prepared audio. **Set Up & Test…** explains permissions, checks macOS preflight and starts a real screen-region test; an error capsule's **?** button opens this help directly. See [current verification and remaining gates](docs/everyday-reading-verification.md).

Default shortcut: **⌥R (Option + R)** starts region selection. Press it again during speech or voice preparation to select another region and queue its text without interrupting playback. While a selection/capture/OCR is already in progress, repeats do not duplicate or cancel it. **Escape**, the capsule's stop button, or **Stop Reading** in the menu stops everything. To change the shortcut, open **Settings… → Shortcuts**, click the shortcut field and press the new combination; **Escape** cancels recording. The choice takes effect immediately and is saved locally across restarts. Global shortcuts pause while the field records. **Restore Default** returns to ⌥R. Changes are blocked during an active operation.

Supported keys are A–Z, 0–9, and Space, combined with Command, Option, or Control; Shift is optional. Failed registration leaves the previous shortcut active and does not save the rejected choice. System-wide registrations are checked through Carbon, but ordinary app commands and services cannot all be detected: Command-only choices require confirmation, and the previous default ⌘⇧Y overlapped macOS’s “Make Sticky” service. All saved choices, including ⌘⇧Y, are preserved on restart. Keys are resolved from the current keyboard layout when registered; restart the app or record the shortcut again after changing layouts.

**Reading speed:** choose 0.75×, 1×, 1.25×, 1.5×, 1.75× or 2× in **Settings → Read Aloud → Speed** or the menu bar's **Speed** submenu. Changes apply during playback and are remembered locally. A native time/pitch unit changes rate with pitch fixed at zero; Supertonic still generates its normal-speed voice. Faster starting rates increase the pre-roll to preserve about one second of playback headroom. The fixed PCM limit is eight seconds of source audio (about 1.35 MiB), retaining up to four seconds of look-ahead at 2×.

**Queue another text:** press **the same reading shortcut again** while preparing or speaking, or use **Add Screen Region to Queue…** in the menu. Drag another region; the existing speech continues while OCR prepares it. Up to five waiting texts (8,000 characters each) are read in order. On hover, the capsule's **+N** control shows the number waiting; **Next Text** in the menu skips the current text. If speech ends while a new region is being selected/recognized, the app waits. Escape or an explicit Stop control stops everything and clears all pending text. There is no history, automatic clipboard write, or queue persistence across app restarts. The previous **⌘⌥⇧Y** shortcut remains an optional additional alias, configurable under **Settings → Shortcuts → Advanced**; it is no longer needed for this workflow. See [speed and queue verification](docs/speed-and-queue-verification.md).

**Selecting text (2026-10-14):** drag over text as with ⌘⇧4. Hold **Space** to move the selection, **Shift** to lock the edge that did not move first, **Option** to grow it from the starting point. A **click** without dragging reads only the paragraph under the pointer; Saywing recognizes a bounded area around it and discards the rest immediately. A short hint explains this for the first five selections.

**Language:** Saywing follows the macOS language. Source strings are English with a complete German catalog; `scripts/check-localization.py` verifies coverage.

Implementation checks and remaining limitations are recorded in [Shortcut verification](docs/shortcut-verification.md) and the [Apple design refinements](docs/apple-design-refinements-verification.md).

**Switching from OpenScreenReader:** quit the old app before launching Saywing. Both versions use the same exclusive global shortcut; running both can show **Error** at startup. After quitting the other copy, relaunch Saywing or record the same combination again under **Settings → Shortcuts**. Existing preferences and the local speech runtime are retained. See [integration and test results](docs/saywing-integration-verification.md).

**Prepared transitions:** the model stays loaded for the reading session. Once the current text's synthesis is complete, the same worker prepares up to eight source seconds of the next queued text while current audio is still playing. Only one successor is prepared; it is never played early or saved to disk. A prepared handoff includes a short 120 ms separation. Late additions may still need synthesis time. Escape/Stop discards all prepared audio and releases the worker. See [warm queue verification](docs/warm-queue-verification.md).

With the development runtime installed, selecting text starts speech automatically. The menu shows **Preparing voice**, then **Speaking**; Escape or **Stop Reading** cancels. Settings shows Supertonic 3, its machine-generated M1 voice, model license, and local runtime availability. Selections are limited to 8,000 characters; no Qwen, cloud, or system voice is substituted on failure. See [runtime installation and verification](docs/research/supertonic-integration.md). Screenshots are released after OCR; text and audio are retained only for the active reading, without history or automatic clipboard writes.

A small floating reading panel appears after capture on the selected display. Choose **Bottom, Left or Right** in Settings → **Control position**, or drag its waveform to dock at the nearest edge. Side positions use an upright vertical layout. The edge and relative offset are remembered locally; **Preview & move control** lets you position it without OCR or speech. Dragging never activates the separate stop/close button or takes keyboard focus. Its stop button cancels the whole operation. Completed/stopped feedback disappears automatically; empty-text and error notices remain until dismissed or a new selection starts. The panel contains status only, never the selected text. See [panel behavior and verification](docs/reading-panel-verification.md).

The reading and dictation controls share a compact deep navy capsule, rounded pale petrol bars, a subtle light edge and a circular primary stop control. Nine bars follow the actual playback or microphone level, with the same time-based attack/decay and a quiet brightness cycle while preparing or recognizing. Both appear with a short fade and critically damped scale transition; no text or timer appears in the dictation bar. After screen capture, the selection frame still travels to the reading control to explain the spatial connection. Hover reveals reading pause/options without resizing. VoiceOver describes every state; Reduce Motion, Reduce Transparency and Increase Contrast follow macOS. The original local interface sounds remain configurable. See the [design review and native verification](docs/brand-identity/APPLE_DESIGN_REVIEW.md).

- Press a global keyboard shortcut.
- Drag a rectangle over any visible text.
- Recognize it locally with Apple Vision.
- Start natural speech automatically with a local TTS model.
- Repeat the same shortcut to queue more text; stop immediately with `Esc` or the stop button.

The official macOS release is intended to include its default local speech model. After installation, OCR and speech synthesis should work without an internet connection or a separate model setup step. Screenshots, recognized text, and generated audio should remain in memory by default.

## Why this project?

Existing tools generally offer either fast local screen OCR with macOS system voices or natural cloud speech. Saywing explores the missing combination:

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
- no automatic clipboard writes during reading; explicitly started dictation temporarily pastes and restores the clipboard while preserving newer copies;
- no persistent screenshot, OCR-text, or audio history;
- clear disclosure of every required macOS permission and network request.

The MVP runtime should make no network request. Downloading the signed application from the project website is outside the application runtime.

See [docs/privacy.md](docs/privacy.md) for the enforceable requirements.

## License

The project code and documentation are licensed under the [Apache License 2.0](LICENSE). Model weights, voices, runtimes, and third-party assets retain their own licenses and must be documented separately before distribution.
