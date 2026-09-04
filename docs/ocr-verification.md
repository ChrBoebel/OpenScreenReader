# Local OCR implementation and verification

## Implemented slice

`⌘⇧Y` → drag one display-local region → in-memory ScreenCaptureKit image → Apple Vision → Ready with character/line counts. A blank result reports “No readable text found. Select a clearer region.” There is no speech provider, preview/history window, automatic clipboard write, or runtime download. The app deliberately retains only counts, not recognized content, until the speech integration is implemented.

`VisionOCRService` conforms to an injectable `TextRecognizing` interface. It uses [`VNRecognizeTextRequest`](https://developer.apple.com/documentation/vision/vnrecognizetextrequest) revision 3, accurate recognition, and explicit `de-DE`/`en-US` languages after checking system support. Language correction and automatic language detection are disabled to avoid extra rewriting of identifiers and amounts. OCR itself can still make recognition errors; this is not a guarantee of verbatim fidelity.

Recognition executes on a serial user-initiated background queue. Each operation gets a new request; a lock-protected cancellation bridge forwards task cancellation to [`VNRequest.cancel()`](https://developer.apple.com/documentation/vision/vnrequest/cancel()). Checks before and after Vision prevent cancelled output delivery. Cancellation is best-effort at the framework level; the app independently revokes the operation generation so delayed results cannot change current status. Queued work checks cancellation before performing OCR.

The Escape monitor stays active through capture and OCR. Esc, repeated hotkey, monitor unavailability, or a fifteen-second total timeout cancel both tasks. Errors shown by the app contain fixed guidance, never Vision diagnostic payloads or recognized text. The image, observations and text remain task-local and are released when that work unwinds; no instantaneous framework memory-erasure guarantee is made.

`OCRResult` preserves Vision observation order and line breaks, trims outer whitespace, and drops empty lines. It does not dehyphenate, paraphrase, reorder columns, normalize numbers, or segment sentences. Complex layouts and a fidelity-first text/segmentation layer remain future Step 5 work.

## Reproduce

Use the [optional local signing workflow](../CONTRIBUTING.md#optional-stable-local-debug-signing) to keep the same certificate on Debug rebuilds. Build before granting permissions, then use `test-without-building` when validating the exact permission-enabled binary.

- `OCRTests`: real Vision recognition on CoreText-rendered synthetic images (no fixture image files), blank image, explicit request configuration, preservation of line breaks/codes/hyphens, already-cancelled task, cancellation before request installation, and forwarding cancellation to an installed request.
- `InteractionTests`: automatic capture-to-OCR handoff, metadata-only completion, blank feedback, sanitized failure, Esc and repeated-hotkey cancellation during suspended OCR, stale results after restart, timeout, and monitor-unavailable failure. Fakes intentionally ignore cancellation so the generation guard is exercised.
- `LiveCaptureTests`: real capture dimensions/unchanged clipboard and real Escape-tap availability/cleanup. These must pass without skips for permission-enabled evidence.
- Native UI tests: drag to OCR-result or permission guidance, menu/local Esc, settings disclosures, and the global Finder shortcut. The drag test allows an empty result because arbitrary desktop content is not a deterministic text fixture. It is not a golden-text end-to-end assertion.

Only synthetic known text is asserted in the real OCR fixture test. The app/tests do not explicitly attach OCR input images or recognized user text to reports or print them. Xcode's own UI-test diagnostics may capture the desktop on failures; that is separate from the application's runtime storage policy.

## Evidence on 2026-09-04

Environment: development Mac, ARM64, macOS 26.6.2, Xcode 26.6; times Europe/Berlin. Result bundles remain in the local Xcode `Logs/Test` directory.

- The initial service test run failed to compile because the new OCR types did not yet exist. After implementation, the 23:40:48 run passed all five initial OCR tests. Vision returned the exact expected synthetic German/English lines including “Straße”, “Grüße”, `AB-123`, `42,50 EUR`, and `04.09.2026`, with unchanged clipboard revision.
- Integration tests first failed against the unconnected pipeline. The connected 23:42:31 run passed 26 Swift Testing tests and both real system tests, without new permission grants after rebuilding.
- The final 23:43:38 full run passed 29 Swift Testing tests (including parameterized cancellation/failure scenarios), both live system tests without skips, and three native UI tests: drag-to-OCR completion, menu/local Escape, and settings. The pre-existing intermittent Finder-hotkey test failed. This is **not an entirely green full suite**.
- The isolated 23:45:29 Finder-hotkey rerun passed on the unchanged OCR build (46.449 seconds). It does not resolve the full-suite intermittency or establish acceptable latency.
- ARM64 Release build succeeded with Hardened Runtime still enabled. SwiftPM's core test and all eleven executable behavior checks passed. Xcode emitted its existing “No AppIntents.framework dependency found” metadata-extraction warning.
- Computer Use was attempted on the exact Debug app but attachment to this windowless menu-bar app timed out again. Native XCUITest supplied the interaction evidence; a direct Computer Use OCR flow is not claimed.

Remaining checks: fix the intermittent global-hotkey test/behavior, golden-text screen-to-OCR end-to-end fixtures, complex columns/tables, small/rotated/low-contrast text, URLs/email and broader font/layout coverage, minimum-macOS and multi-display matrix, physical Esc during in-flight OCR with latency measurements, external filesystem/network observation, segmentation and speech. No model weights or runtime dependencies were downloaded.
