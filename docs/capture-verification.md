# Region capture spike

## Implemented behavior

`⌘⇧Y` or the menu action starts selection. A repeated shortcut or Escape closes the overlay. The borderless overlay panels can activate and accept the first mouse event so the first drag is not lost to window activation. A valid drag dismisses all overlay panels before capture starts. The image is passed to [local Vision OCR](ocr-verification.md), then the app returns to Ready with character/line counts or an empty-result message. It does not yet speak text.

The owner explicitly chose Command-Shift-Y after being informed of the overlap with the “Make Sticky” macOS service. No system shortcut setting is changed. Carbon key codes are resolved from the current keyboard layout at app startup, so German Y (physical ANSI Z) and US Y both work. Restart after changing keyboard layouts; live reconfiguration is not implemented. Earlier evidence below used the previous Control-Option-R shortcut.

The selection records display identity, its AppKit point rectangle, backing scale, display geometry, and a topology revision. ScreenCaptureKit receives a display-local **top-left-origin rectangle in logical points**, plus separately calculated output pixel dimensions. Topology changes invalidate selection and pending capture, including changes that restore the same display frames.

The native capture adapter uses Apple's [`SCScreenshotManager.captureImage`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager). It explicitly excludes the current application's windows, disables the cursor and audio, and requests sRGB output. No screenshot file, clipboard write, or network operation is part of this code path. The returned image stays in task-local memory; only its dimensions are published. Actual filesystem/network observation remains a release gate.

Control transitions are serialized independently of the asynchronous capture and recognition tasks. Cancellation revokes the operation and cancels both tasks. Apple's one-shot capture API may finish later, but cancelled or stale results cannot publish status, dimensions, or OCR counts. A fifteen-second timeout covers capture plus OCR, releasing the application's active operation even if a system callback is slow.

## Escape and permissions

The selection overlay handles Escape without additional keyboard permissions. After a valid selection, a listen-only event tap is installed for capture and remains active through OCR. Its callback checks for Escape and retains no keyboard content. It is removed on success, failure, cancellation, or teardown. A health check stops the operation if the tap is disabled, permission disappears, or Secure Input becomes active.

Capture fails with a visible explanation if Input Monitoring or Screen Recording permission is unavailable. The Settings window explains both permissions and offers separate explicit request actions. Merely launching the app or selecting a region does not automatically request a permission.

This is a fail-closed technical spike, **not a passed Gate E**. Minimum/current macOS, Secure Input, permission revocation, sleep/wake, physical multi-monitor setups, and end-to-end latency still need broader validation. A manual global Escape-delivery probe passed with another app focused (see below); this is not an end-to-end latency measurement. OCR cancellation has deterministic integration coverage; synthesis and playback do not exist yet.

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

### Opt-in global Escape delivery check

The separate `OpenScreenReaderManualChecks` scheme selects only `testGlobalEscapeDeliveryWhileAnotherAppIsActive` and enables it explicitly. The ordinary scheme excludes this interactive test; direct invocation without the opt-in environment flag also skips it. Normal tests never wait for manual keyboard input.

Build the test first, then grant Input Monitoring to that exact Debug app if necessary:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReaderManualChecks \
  -destination 'platform=macOS,arch=arm64' build-for-testing

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReaderManualChecks \
  -destination 'platform=macOS,arch=arm64' test-without-building
```

After `ESCAPE CHECK READY`, focus another app with no sensitive dialog open and press Escape within 45 seconds. The test uses the real `EscapeMonitor`, requires another process to be foreground when its callback runs, and tears the monitor down on delivery, error, or timeout. Missing permission or an unavailable tap is a failure in this deliberately requested check, not a successful skip. It logs no keyboard content, screenshot, or foreground app identity.

This is a monitor-delivery probe, not a measurement of end-to-end cancellation latency and not an OCR/TTS integration test. Keep the deterministic cancelled-capture/stale-result tests as separate evidence.

## Evidence on 2026-09-04

All times below are local (Europe/Berlin), on macOS 26.6.2, ARM64. Results are in Xcode's local `Logs/Test` directory; no captured image was attached by the live capture test.

- After the owner granted both permissions, Computer Use confirmed the Input Monitoring switch was on. The 22:27:04 run passed both real system tests: ScreenCaptureKit returned the expected dimensions without changing the clipboard, and the Escape tap could start, stop, and restart. This verifies tap availability, **not delivery of a global Escape event**.
- The 22:27:36 full run passed 21 tests and failed two UI tests. The drag failure reproduced twice in isolation; narrowed diagnostics showed the app stayed in Selecting. Replacing the nonactivating panel with a borderless activating panel and accepting the first mouse event resolved that reproduction. The 22:32:06 focused drag run passed through its explicit permission-error branch, not successful capture.
- The global-hotkey test failed intermittently during full runs. Its isolated 22:34:15 rerun passed both start and repeated-hotkey cancellation from Finder. Do not interpret an isolated pass as a completed stability or latency assessment; XCUITest took roughly 35 seconds for this test.
- The 22:35:23 full run succeeded: 17 app-unit tests and all four UI tests passed, with the two live system tests explicitly skipped because the rebuilt binary lacked effective permissions. The UI drag test passed via denial guidance. Earlier failures remain relevant evidence, not erased by this green run.
- After the permission recovery described below, the final 22:44:06 `test-without-building` run passed all 23 tests with zero failures and zero skips: 17 app-unit tests, both live system tests, and all four native UI tests. The drag test reached Ready and verified “Region captured locally. No image was saved.”; it did not take the permission-error branch. Menu/local Escape, global shortcut start/repeated cancellation from Finder, and Settings controls passed. Global Escape delivery after selection remains unverified.
- The corrected ARM64 Release build passed. The compiled app icon remains the approved Owl Frame asset.
- SwiftPM's one core test and all 11 executable behavior checks passed.
- Computer Use could inspect macOS permission settings, but attaching directly to the windowless menu-bar app still timed out. Native XCUITest supplied the interaction checks. Test assertion diagnostics are now limited to app-owned status items instead of dumping the Apple menu's private Recent Items.

### Development signing caveat

The Debug app is ad-hoc signed. Its observed designated requirement is tied to a code hash (`codesign -d -r-`), not a stable developer certificate. After the overlay code was rebuilt, both system permission preflights returned false again. A visible Settings switch alone is therefore not evidence that a rebuilt binary has effective access. The post-fix live tests explicitly skipped and the UI capture test exercised denial guidance.

In this development session, toggling the existing entries off/on was insufficient: the 22:39:48 live run still skipped both tests. The owner then removed only OpenScreenReader's entries from both permission lists, re-added the exact Debug app, and enabled it. The 22:43:39 `test-without-building` run passed both live tests on the corrected binary. Its designated code hash remained `4f8a97d3ebc14cfa44cb8166f2f6a7f481c26ecd`.

For a permission-enabled rerun, grant access to the exact final Debug app and relaunch it, then use `test-without-building` in place of `test` in the command above. Do not change the binary between the grant and the test. If an ad-hoc rebuild leaves enabled but ineffective entries, removing and re-adding only those entries is a manual recovery step, not an automatic test action. A sandboxed signing-identity check found no valid code-signing identities; configuring stable development signing remains a separate setup task. No TCC database edits or permission resets are performed by the app or normal test suite.

No model weights were downloaded and no OCR or TTS fallback was added.

### Follow-up input probe on 2026-09-04

The new manual-check scheme built successfully. Its 22:48:09 live run failed before receiving keyboard input because the rebuilt app lacked effective Input Monitoring. The rebuild changed the designated code hash from `4f8a97d3ebc14cfa44cb8166f2f6a7f481c26ecd` to `48dfd90464680d4a048bc8ac48487d1a0c8b3ed7`, despite no app-source edits. An unsandboxed read-only signing-identity check also found zero valid identities. Global Escape delivery remains unverified; stable local development signing requires an owner-approved setup before further permission-enabled iterations.

The 22:49:32 normal-suite run excluded the interactive check as intended: 20 tests passed, two permission-dependent live tests skipped, and the existing Finder-hotkey test failed while expecting the initial overlay. This is not a clean regression run; the previously observed intermittent hotkey behavior still needs investigation. The new test and both scheme files compiled/parsed successfully; no production app-source changes, permission changes, or signing-key creation were made in this follow-up.

The isolated 22:51:00 Finder-hotkey rerun passed without rebuilding (35.228 seconds). This confirms a successful individual run but does not resolve the full-suite failure.

### Self-signed Debug launch correction on 2026-09-04

With the owner's approval, a local self-signed Code Signing identity was created in the login keychain. The private key was not exported and no certificate-trust or system-wide security settings were changed. The first explicitly certificate-signed build passed code-signature verification but failed at launch: the 23:10:58 UI run encountered a DYLD rejection of `OpenScreenReader.debug.dylib`. Hardened Runtime's library validation requires an Apple Team ID, which this local identity does not have. The blocked test run was interrupted; it was not a successful UI check.

The correction disables Hardened Runtime **only in the app's Debug configuration**. Release remains enabled. The optional repeatable signing commands are in [CONTRIBUTING.md](../CONTRIBUTING.md#optional-stable-local-debug-signing); the repository defaults remain ad-hoc and no personal signing identity is committed.

- Debug `build-for-testing` succeeded with the approved local certificate. `codesign --verify --strict` succeeded with normal login-keychain access (the sandboxed check could not resolve trust). The app now has a certificate-based designated requirement and signature flags `0x0`, without the runtime flag.
- The focused 23:21:24 UI run passed launch, menu actions, selection-overlay appearance, and local Escape cancellation (one test, 8.563 seconds). This is the successful regression check for the startup failure.
- The 23:21:58 full run passed 17 app-unit tests and three UI tests, failed the already-observed Finder-hotkey test, and skipped both live system tests because neither permission was effective for the newly signed test host. The drag UI test passed through permission-error guidance, **not actual capture**.
- The isolated 23:23:30 Finder-hotkey run passed start and repeated-shortcut cancellation (36.982 seconds). Full-suite intermittency remains unresolved.
- The ARM64 Release build succeeded; its actual signature still has the hardened-runtime flag (`0x10002`, ad-hoc plus runtime).
- Direct Computer Use attachment to the windowless Debug app again timed out. Computer Use could inspect the Screen Recording settings and confirmed an enabled OpenScreenReader entry despite the failed live preflight. No permission switches or file-picker contents were changed/read during this correction.

Next, the owner must grant access to the exact newly signed Debug app and relaunch it, then rerun the permission-dependent tests without rebuilding. Permission persistence across genuine rebuilds and global Escape delivery after selection remain unverified. The correction does not implement OCR/TTS, establish public distribution signing, or pass Gate E.

### Permission recovery and physical Escape follow-up

After the owner re-added the certificate-signed Debug app, the 23:28:31 run passed both live system tests with no skips. The 23:28:51 UI run passed the actual successful drag-to-capture branch. The 23:29:19 and 23:31:59 manual Escape probes timed out while coordinating the user's input; they do not establish a functional failure without a confirmed key event during the test window.

The 23:37:52 manual probe then **passed**: the owner pressed Escape while another app was foreground, and the real `EscapeMonitor` delivered the event. The test's 12.157-second duration includes waiting for human input; it is not cancellation latency. Subsequent OCR builds retained the same certificate-based designated requirement and passed both live permission tests without another grant. This is evidence on this Mac with this identity, not a guarantee across OS upgrades, certificate replacement, or other machines. See [OCR verification](ocr-verification.md) for the updated pipeline.

### Command-Shift-Y verification, 2026-09-04/05

- The owner requested and approved `⌘⇧Y`, including its overlap with the “Make Sticky” service. A read-only layout check identified the active German layout; no system shortcut or input-source settings were changed.
- The initial narrowly filtered test command selected zero tests, so it was not regression evidence. The subsequent 23:58:44 run did execute the layout tests and exposed a case-matching error: Command-Shift translates to lowercase `y` in both German and US layouts. Case-insensitive letter matching corrected it without changing the required Command/Shift modifiers.
- The full 23:59:43 run passed 31 Swift Testing tests, both real permission-dependent system tests, and all four native UI tests, without skips or failures. German Y resolves to key code 6 and US Y to 16. The Finder test passed selection start and repeated-shortcut cancellation (35.686 seconds). One green run does not establish that the previously observed UI-test intermittency is permanently resolved.
- The ARM64 Release build succeeded after midnight on September 5. The normal local certificate was reused for Debug; neither permission needed another grant.
- Computer Use attachment to the menu-bar-only app again timed out. The app was nevertheless started and its exact Debug process was confirmed; native XCUITest provided the global shortcut evidence. Changing keyboard layouts while the app is running still requires restarting the app to resolve the new physical Y key.

### Configurable shortcut follow-up, 2026-09-05

The fixed shortcut has been replaced with locally saved settings and conflict-safe reconfiguration. ⌘⇧Y remains the default, and the selected shortcut continues to start/cancel the same pipeline. See [Shortcut verification](shortcut-verification.md) for the new registration, persistence, and native UI checks; the broader capture/permission gates above remain separate.
