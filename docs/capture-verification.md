# Region capture spike

## Implemented behavior

`⌃⌥R` or the menu action starts selection. A repeated shortcut or Escape closes the overlay. A valid drag dismisses all overlay panels before capture starts. The current spike returns to Ready after verifying the image dimensions and releasing the image; it does not yet recognize or speak text.

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

- On macOS 26.6.2, the final app-unit run passed 17 tests with zero failures; two live system tests were skipped because the test host lacked Screen Recording and Input Monitoring.
- The three interaction UI tests passed. The new Settings test initially failed because two menu entries shared its title; after scoping it to the status item, its focused rerun passed.
- The ARM64 Release build passed with a compiled `AppIcon.icns` and the correct bundle icon metadata.
- Computer Use observed the live selection overlay. Attaching to a windowless app remained unreliable. It opened macOS permission settings, but changing the permission list required the owner's password confirmation. Actual permission-enabled capture remains unverified until that interaction completes.

No model weights were downloaded and no OCR or TTS fallback was added.
