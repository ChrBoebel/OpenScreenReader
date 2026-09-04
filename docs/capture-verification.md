# Region capture spike

## Implemented behavior

`⌃⌥R` or the menu action starts selection. A repeated shortcut or Escape closes the overlay. The borderless overlay panels can activate and accept the first mouse event so the first drag is not lost to window activation. A valid drag dismisses all overlay panels before capture starts. The current spike returns to Ready after verifying the image dimensions and releasing the image; it does not yet recognize or speak text.

The selection records display identity, its AppKit point rectangle, backing scale, display geometry, and a topology revision. ScreenCaptureKit receives a display-local **top-left-origin rectangle in logical points**, plus separately calculated output pixel dimensions. Topology changes invalidate selection and pending capture, including changes that restore the same display frames.

The native capture adapter uses Apple's [`SCScreenshotManager.captureImage`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager). It explicitly excludes the current application's windows, disables the cursor and audio, and requests sRGB output. No screenshot file, clipboard write, or network operation is part of this code path. The returned image stays in task-local memory; only its dimensions are published. Actual filesystem/network observation remains a release gate.

Control transitions are serialized independently of the asynchronous capture task. Cancellation revokes the operation and cancels its task. Apple's one-shot capture API may finish later, but cancelled or stale results cannot publish status or dimensions. A ten-second timeout releases the application's active operation even if the system callback is slow.

## Escape and permissions

The selection overlay handles Escape without additional keyboard permissions. After a valid selection, a listen-only event tap is installed only for the active capture. Its callback checks for Escape and retains no keyboard content. It is removed on success, failure, cancellation, or teardown. A health check stops the operation if the tap is disabled, permission disappears, or Secure Input becomes active.

Capture fails with a visible explanation if Input Monitoring or Screen Recording permission is unavailable. The Settings window explains both permissions and offers separate explicit request actions. Merely launching the app or selecting a region does not automatically request a permission.

This is a fail-closed technical spike, **not a passed Gate E**. Minimum/current macOS, Secure Input, permission revocation, sleep/wake, real events with another app focused, physical multi-monitor setups, and end-to-end latency still need validation. OCR, synthesis and playback do not exist yet, so their cancellation behavior cannot be claimed.

## Reproduce checks

With Xcode installed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -destination 'platform=macOS,arch=arm64' test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -configuration Release -destination 'platform=macOS,arch=arm64' build
```

- Unit tests cover coordinate inversion, negative origins, scale, topology invalidation, capture configuration, rapid read requests, permission failure, and rejection of an uncooperative late result after cancellation and restart.
- Native UI tests cover menu invocation, drag completion with either capture success or an explicit permission error, local Escape, repeated global shortcut from Finder, and Settings permission/privacy controls. The permission-error branch is not evidence of successful capture.
- `LiveCaptureTests` invokes the actual ScreenCaptureKit adapter and checks dimensions and clipboard revision when Screen Recording is allowed. Without permission, it checks denial behavior and explicitly skips the successful-capture path. No captured image is attached to the report.
- The live Escape test verifies tap creation and cleanup when Input Monitoring is allowed; it explicitly skips otherwise. It does not prove delivery of a global Escape key event.

## Evidence on 2026-09-04

All times below are local (Europe/Berlin), on macOS 26.6.2, ARM64. Results are in Xcode's local `Logs/Test` directory; no captured image was attached by the live capture test.

- After the owner granted both permissions, Computer Use confirmed the Input Monitoring switch was on. The 22:27:04 run passed both real system tests: ScreenCaptureKit returned the expected dimensions without changing the clipboard, and the Escape tap could start, stop, and restart. This verifies tap availability, **not delivery of a global Escape event**.
- The 22:27:36 full run passed 21 tests and failed two UI tests. The drag failure reproduced twice in isolation; narrowed diagnostics showed the app stayed in Selecting. Replacing the nonactivating panel with a borderless activating panel and accepting the first mouse event resolved that reproduction. The 22:32:06 focused drag run passed through its explicit permission-error branch, not successful capture.
- The global-hotkey test failed intermittently during full runs. Its isolated 22:34:15 rerun passed both start and repeated-hotkey cancellation from Finder. Do not interpret an isolated pass as a completed stability or latency assessment; XCUITest took roughly 35 seconds for this test.
- The final 22:35:23 full run succeeded: 17 app-unit tests and all four UI tests passed, with the two live system tests explicitly skipped because the rebuilt binary lacked effective permissions. The UI drag test passed via denial guidance. Earlier failures remain relevant evidence, not erased by this green run.
- The corrected ARM64 Release build passed. The compiled app icon remains the approved Owl Frame asset.
- SwiftPM's one core test and all 11 executable behavior checks passed.
- Computer Use could inspect macOS permission settings, but attaching directly to the windowless menu-bar app still timed out. Native XCUITest supplied the interaction checks. Test assertion diagnostics are now limited to app-owned status items instead of dumping the Apple menu's private Recent Items.

### Development signing caveat

The Debug app is ad-hoc signed. Its observed designated requirement is tied to a code hash (`codesign -d -r-`), not a stable developer certificate. After the overlay code was rebuilt, both system permission preflights returned false again. A visible Settings switch alone is therefore not evidence that a rebuilt binary has effective access. The post-fix live tests explicitly skipped and the UI capture test exercised denial guidance.

Re-grant permissions to the final Debug app and relaunch it before repeating `LiveCaptureTests` and the successful UI capture path. Do not change the binary between the grant and the test. A sandboxed signing-identity check found no valid code-signing identities; configuring stable development signing remains a separate setup task. No TCC database edits or permission resets are performed by the app or normal test suite.

No model weights were downloaded and no OCR or TTS fallback was added.
