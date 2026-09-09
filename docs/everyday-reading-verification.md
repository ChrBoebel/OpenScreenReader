# Everyday reading development — 2026-09-09

## Implemented

- Native pause/resume without resetting audio buffers; enqueue/finish cannot restart a paused player. Stop releases paused waits and clears pause. App watchdog is suspended during pause, while bounded worker health checks remain active.
- Explicit capsule control popover: pause/resume, speed, next, add region and session-local queue previews. Stable IDs protect queue edits against stale positions. Remove/move/play-now update preparation; play-now keeps other waiting entries.
- Setup view with permission preflight, explicit requests, runtime availability and a real-region test entry point. Error help links directly to setup. No claim that preflight proves capture or global Escape.
- Explicit soft-hyphen/NBSP cleanup. Common German/English abbreviations, initials and ordinal dates are not split into separate speech requests. Text and numbers are not paraphrased or speculatively expanded.
- Private offline packaging script and bundled-runtime selection. Public distribution is not approved by this experiment.

## Actual checks

- New Swift tests first failed because normalization did not exist; after implementation all 83 app tests passed. An additional idle-stop regression brings the final successful rerun to 84 tests. Permission-dependent tests remain skipped, not passed.
- New worker test first demonstrated incorrect splitting of `Dr.`, `z. B.` and `4. September`; all seven worker tests passed after the fix.
- Real Supertonic long-passage audio at 2× with a three-second pause resumed and completed: 30.218 source seconds, 46 playback callbacks, zero reported underruns/missing frames, maximum queue 7.939 source seconds, clipboard unchanged.
- Real cancellation checks: 11.56 ms synchronous playback stop; 0.10 ms during loading; no late playback callbacks. These counters are not a microphone-based word-fidelity audit.
- Computer Use first timed out, then explicitly reported a locked Mac. No successful GUI launch, queue-popover inspection, permission walkthrough, external-display or full-screen test is claimed. Unlock is required before continuing this verification.
- Release builds passed. Private packaging initially failed closed on absolute build-time pkgconfig links; those unused build metadata files are now excluded. Empty-file handling in the native-file scan was corrected. Neither failed staging copy was installed.
- Bundled CPython 3.12.14 imports NumPy 2.2.6 and ONNX Runtime 1.23.2 from inside the app in isolated mode. After relocating the package, real short-passage speech with a three-second pause at 2× completed without reported underruns and with unchanged clipboard. Both playback/loading cancellation probes then used the bundled runtime: 11.82 ms / 0.06 ms synchronous stop, no late callbacks. Runtime probes run under the application's deny-network/deny-write profile. This is relocation evidence on the development Mac, not a clean-Mac test or a full dependency license audit.

## Remaining gates

- Real installed-app interaction review, keyboard/VoiceOver navigation, vertical-edge popover placement and reduced-motion appearance.
- Human listening review for German/English headings, dates, currencies, abbreviations and mixed-language passages. Hard-hyphen joining and speculative number expansion are intentionally not enabled.
- Clean-Mac offline installation; complete interpreter/native dependency provenance and license-chain review; Developer ID signing and notarization before a public release. The private packaging spike does not satisfy these gates.

No new weights or dependencies were downloaded. No release was published.

## Installed private development artifact

- `/Applications/OpenScreenReader.app` is byte-for-byte equal to the final packaged development build; deep strict signature verification passed. Executable SHA-256: `39387af3e8b56330d3a79995feb16e5f8c3294bdab249f48303048a1293465b3`.
- Its own bundled runtime completed the real short-passage test at 2× with a three-second pause, zero reported underruns and unchanged clipboard. This used the standalone integration probe, not the app GUI.
- `.build/OpenScreenReader-Development-20260909.dmg`: 454,583,398 bytes, SHA-256 `96cb971b83ccdd9b8aeb149cbb46bba5cbc17ca817efb8357cbe517cb79fe227`; `hdiutil verify` passed. It includes the app and an Applications shortcut and is intentionally excluded from Git.
- Previous canonical app moved recoverably to Trash (`OpenScreenReader 18-01-05-960.app`). Four task-owned temporary packaging/relocation directories were removed; the final staging bundle and DMG remain reproducible build artifacts. No user documents or models were deleted.
- The previous GUI process was stopped for replacement. The new app was not launched through a GUI while the Mac remained locked. It must be opened after unlock for the real UI/permission test.
- Git preflight found 25 pre-existing unpublished commits on `main`; no push was performed as part of this delivery. Source work is saved in focused local commits; generated models/runtime binaries/DMG are not committed.
