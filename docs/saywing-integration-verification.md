# Saywing integration and startup diagnosis — 2026-10-13

## Integrated working copy

The uncommitted Saywing changes from `codex/saywing-brand` were merged into the primary checkout on `codex/integrated-capsule-controls`, based on their common HEAD `545045b`. No commit, push, remote merge, installation replacement or publication was performed. The branding worktree remains intact. Both original diffs and modified/untracked files were saved under `/private/tmp/saywing-integration-snapshot` before merging.

The combined app includes the approved Saywing name, Quiet Owl icons, green palette, settings and packaging names, plus the existing 136 × 44 pt hover capsule, Pause/Resume, queue controls, side docking, menu access and VoiceOver actions. README conflicts were resolved by keeping both the new palette and hover behavior; the current brand system now documents the integrated interaction. Dictation remains a separate prototype, not a functional action in this app.

## Startup error

The installed `/Applications/OpenScreenReader.app` was still running (PID 76260) and owned the exclusive default shortcut. A standalone probe compiled from the actual `GlobalHotkeyManager.swift` reported `Default ⌘⇧Y: conflict`. After stopping only that verified old process, the same probe reported `Default ⌘⇧Y: registered`.

The combined UI test subsequently found `Saywing, Ready`. The startup failure was a shortcut conflict between app copies. Preferences were not reset. The conflict message now explains how to quit another Saywing/OpenScreenReader copy and retry **Apply Shortcut** in Settings, or choose another combination. Existing retry behavior is covered with real Carbon registration: a second manager owns a shortcut, AppModel starts in Error, the owner releases it, and applying the unchanged combination restores Ready and clears the error.

## Verification

- New regression/assertions ran red before the message change: 91 Swift tests, three expected assertion failures about the missing guidance. An earlier function-filter attempt selected zero tests and is not counted as validation.
- Final run: **91 Swift tests in six suites passed**; Xcode reported **TEST SUCCEEDED**. Two live XCTest checks explicitly skipped because the rebuilt host lacks Screen Recording/Input Monitoring access. No successful permission-dependent capture is claimed.
- **Release BUILD SUCCEEDED**. Product, executable and display name are Saywing; bundle ID remains `com.christopherbobel.OpenScreenReader`.
- 21 native view renders cover bottom/left/right placement and seven states. Bottom rest/hover and right pause were visually inspected with the integrated palette.
- The first broader UI run observed Ready, then failed global-key delivery and menu traversal. Computer Use later explicitly reported that the Mac was locked and automatic unlocking was paused. The blocked UI run was interrupted. No complete live menu/hotkey/selection/VoiceOver flow is claimed for this turn; manual unlock was requested.
- Real local audio with a fixed public test sentence completed with pause/resume, zero underruns and unchanged clipboard. Cancellation during playback and model loading passed with no late chunks.
- `git diff --check`, packaging Ruby syntax and merged-source inspection passed. Existing capsule logic is preserved; its source differs only by palette, app naming and the improved conflict guidance, plus the new regression test.

Final test result: `/private/tmp/saywing-integrated-build/Logs/Test/Test-OpenScreenReader-2026.10.13_18-48-10-+0200.xcresult`.

## Private test package

The development packager correctly refused the external runtime because `venv/bin/python` no longer matched its installation receipt. No check was disabled and that receipt was not changed. Instead, the already installed private app's **bundled** Speech resources were independently verified against all **3,976 receipt entries** and all **10 pinned model files** (Supertonic 3 revision `3cadd1ee6394adea1bd021217a0e650ede09a323`, 398,969,192 bytes, BigScience Open RAIL-M). The worker matches the current source and all symlinks stay inside Speech. Existing runtime licenses and notices are retained. No model or dependency download occurred.

Those verified bundled resources were copied into the new Release app, which was signed ad hoc. **Deep strict codesign verification passed.** This is a private local test build, not Developer ID signing, notarization, redistribution clearance or a clean-Mac verification.

At its final relocated path, the bundled runtime passed real playback with pause/resume (3.9999 s audio, zero underruns), playback cancellation (11.856 ms synchronous stop) and loading cancellation (0.04875 ms), with no late chunks and unchanged clipboard. These timings measure the local stop call, not a cross-process acknowledgement. The old Bash wrapper stopped after its successful first probe due to empty-array handling; the two cancellation probes were run directly, and all three modes were then rerun successfully against the final bundled resources.

The final app is `saywing-integrated/Saywing.app` in this task's visualization directory. It has not replaced `/Applications/OpenScreenReader.app`. Quit other copies before launching it. macOS permissions may need to be granted manually for this rebuilt app; security settings were not modified.

Evidence: `/private/tmp/saywing-integrated-{final-tests,release,assembly,bundled-speech}.log`; native renders in `/private/tmp/saywing-integrated-renders/`; assembly recipe `/private/tmp/assemble-saywing-test.py`.

## Unlocked UI follow-up — 2026-10-13, 19:07

After the owner manually unlocked the Mac, these four real XCTest UI checks passed across the initial and focused rerun:

- Ready status, menu actions, region selection and Escape cancellation.
- Settings: Saywing owl/name, descriptor, prototype status and retained privacy/permission explanations; actual settings-window screenshot captured and inspected.
- Global ⌘⇧Y from Finder; repeating the shortcut preserves the existing selection; Escape cancels.
- Dragging the control left/right/bottom, upright Stop target, closing it, restoring its saved position after relaunch and selecting Left in Settings.

The first dock run exposed two test assumptions, not production-code changes. An independent native AppKit probe confirmed that a 44 × 44 pt borderless NSButton reports a 46 × 46 pt accessibility frame with a one-point expansion per side. The UI check now verifies the minimum accessible target in both dimensions; native view tests still assert exact 44 × 44 geometry. The position-menu query was scoped to its observed picker to avoid duplicate AX matches for Left. The focused dock rerun completed with one test, zero failures and TEST SUCCEEDED.

Initial run (three UI tests passed; dock assertion failed): `/private/tmp/saywing-integrated-build/Logs/Test/Test-OpenScreenReader-2026.10.13_19-04-02-+0200.xcresult`.
Final dock rerun: `/private/tmp/saywing-integrated-build/Logs/Test/Test-OpenScreenReader-2026.10.13_19-06-48-+0200.xcresult`.

The previously built private Saywing.app was opened through Finder, and the running executable was verified at its exact final artifact path; no old OpenScreenReader process was running. Only tests and verification documentation changed in this follow-up, so the delivered app binary did not need replacement. Direct Computer Use attachment to the menu-only app still timed out; the successful UI interactions and screenshot above are XCTest evidence.

Remaining limits: this follow-up does not establish a fresh permission-dependent screen-capture → OCR → speech run, live hover/pause/queue interaction during speech, or a VoiceOver audition. These retain the earlier unit/native-render/audio-probe coverage and require their actual live checks separately. No macOS privacy settings were changed.

## Installation follow-up — 2026-10-13, 19:14

At the owner's request, the latest integrated working copy was rebuilt successfully in Release and installed as `/Applications/Saywing.app`. The prepared and installed executable hashes match. A `Contents/Resources/LOCAL-BUILD.json` records the build time, branch, committed base and hashes of 39 project source/resource inputs, including the uncommitted changes. App version remains 0.1.0; this is the current private development build, not a new public release.

Before installation, all 3,976 bundled runtime receipt entries and 10 pinned model files were rechecked. Deep strict signature verification passed before and after installation. The old `/Applications/OpenScreenReader.app` was moved intact to the task artifact's `Backups/OpenScreenReader-before-Saywing.app-backup`; its signature also verifies. It can be restored by moving it back and restoring the `.app` suffix. No preferences, model contents or macOS permission settings were changed.

Finder opened the installed app, and the actual running executable was verified as `/Applications/Saywing.app/Contents/MacOS/Saywing`, with no second OpenScreenReader/Saywing process. A real playback probe against `/Applications/Saywing.app/Contents/Resources/Speech` passed with pause/resume, zero underruns and unchanged clipboard. The full permission-dependent OCR path retains the earlier stated limits. Installation evidence is saved alongside the task's verification artifacts.
