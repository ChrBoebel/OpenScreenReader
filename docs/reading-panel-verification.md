# Reading status panel

Implemented on 2026-09-05 following the owner's approval of a compact, branded reading control.

## Behavior and design

- `AppModel` supplies status only through `ReadingStatusPresenting`. No screenshot, selected text, audio, or arbitrary diagnostic payload enters the panel.
- The panel stays hidden during selection and capture. Recognition, preparation and playback appear in a 320 × 64 pt nonactivating AppKit panel on the selected display, 20 pt above the bottom of its visible frame. Missing displays hide the panel instead of moving it to an unrelated screen.
- A 44 × 44 pt button cancels the same full pipeline as Escape and the repeated hotkey. Its callback is scoped to its operation; stale buttons cannot cancel a newer selection. Presentation generations also invalidate old dismissal timers.
- Completed and stopped states disappear after 1.4 seconds. Empty-text and error notices stay until explicitly dismissed or a new selection starts. Errors direct users to the existing menu details; no extra confirmation is introduced before speech.
- The approved Local Ink, Warm Paper and Voice Mint tokens, system typography, restrained 16 pt corners, and semantic SF Symbols implement the brand direction. The approved owl artwork and menu-bar glyph are unchanged. Only the speaker pulses, and Reduce Motion disables that pulse. The surface is opaque; increased contrast strengthens its border.
- The panel is neither key nor main, does not activate the app, and accepts the first stop click while another app is foreground. It joins Spaces and can accompany full-screen apps. ScreenCaptureKit already excludes all windows belonging to OpenScreenReader; hiding before capture is the primary presentation rule, not a reliance on window-sharing flags.

## Verification record

Environment: development Mac, macOS 26.6.2, Xcode 26.6, arm64 Debug with the existing local signing identity and existing capture/input permissions. No permissions or model files were changed.

- TDD red: the added interaction tests first failed to compile because `ReadingPanelState` and `ReadingStatusPresenting` did not exist.
- Initial green: 52 Swift Testing app tests and both live permission tests passed. Core: one Swift Testing test and all 11 behavior checks passed.
- Unit coverage includes hidden-before-capture behavior, selected display routing, loading/playback cancellation, rejection of old stop callbacks, completion/empty/error states, timer invalidation, nonactivation, disappearing terminal states, unknown displays and negative-origin display geometry.
- Initial native run: real OCR → Supertonic → global Escape and repeated-shortcut cancellation passed. The stop-click test failed because an `NSPanel` is exposed as a dialog, not a normal window. The content now has an explicit accessibility group for inspection.
- Second stop-click run reached the panel but failed because XCTest reported a non-finite application-root frame. The test now anchors its click to the observed fixture text element and asserts finite coordinates. These were test-harness failures, not passed stop-click results.
- An early screenshot omitted the panel because of its window-sharing flag. That flag was removed: the panel contains only public status, while the app's own capture continues excluding the entire app.
- Computer Use attachment to the exact Debug app returned `timeoutReached` (-10005). Native UI automation is separately authorized by the owner; no successful Computer Use session is claimed.
- Final-code Debug app tests: 52 Swift Testing tests and both live permission tests passed again. Release build passed; the only build warning was the existing skipped App Intents metadata extraction.
- The final-code combined UI run passed Escape, repeated-shortcut and stop-button cancellation, including foreground preservation during playback and after the stop click. Natural completion reached Ready and hid the panel but failed its final foreground-app assertion once. An earlier isolated completion run had passed; this combined run is **not** an all-green result.
- The exported final-code screenshot was visually inspected: the entire panel renders at 640 × 128 Retina pixels with readable, unclipped labels, mint speaker, opaque dark foundation and a 44 pt stop target. No screenshot or selected text is displayed in the panel.
- Two isolated natural-completion repetitions then passed (29.800 s and 29.484 s, zero skips), including Ready, hidden panel and retained fixture focus. The test now names the actual foreground application on assertion failure. The earlier intermittent foreground assertion has not been attributed to a proven cause; it remains recorded rather than erased by the rerun.

Local result bundles for this session: `/tmp/osr-panel-final.xcresult` (52 app tests + 2 live permission checks passed; 3/4 UI flows passed), `/tmp/osr-panel-completion-recheck.xcresult` (2/2 isolated completion repetitions passed). These are temporary development artifacts, not product history or committed screenshots. No full physical-display/accessibility regression is claimed.

## Remaining coverage

Physical multi-monitor/Dock arrangements, switching Spaces/full-screen apps, a hands-on VoiceOver walkthrough, and the complete reduced-motion/increased-contrast appearance matrix still need device-level checks. Geometry tests and accessibility labels do not substitute for those checks. Existing shortcut-layout reliability and release packaging/signing gates remain unchanged.
