# Configurable shortcut verification

## Saved shortcut choice — 2026-10-13

The owner explicitly chose Command-Shift-Y (⌘⇧Y) again after confirming that
Option-R opens selection. Startup now honors every valid saved shortcut,
including the former default; it no longer rewrites Command-Shift-Y to Option-R.
The default for an empty preference remains Option-R.

The saved-choice regression failed before the fix (both the active configuration
and stored value were overwritten). After the fix, that regression and the
shortcut persistence/conflict test passed (2 tests). The Release build passed.
The installed app accepted and saved ⌘⇧Y through Settings and still displayed
`Ready ⌘⇧Y` after relaunch with the corrected executable. Screen Recording,
Input Monitoring, and Accessibility were renewed and confirmed by the app.
Microphone approval was reset for the new development signature and requested
again; consent remains in the system dialog for the owner. Physical delivery of
⌘⇧Y and an end-to-end OCR/speech run were not newly verified in this change.

## Selection focus correction — 2026-10-13

The current default is Option-R (⌥R). The selection overlay now uses nonactivating
panels, remains visible when another app is active, and gives keyboard focus to
the panel under the pointer without activating Saywing's Settings or dictation
windows. Escape still cancels through the selection view; cancellation closes
every selection panel.

The native panel regression failed before the correction (activating style and
`hidesOnDeactivate == true`) and passed afterward. The 115-test app run had one
queue-timeout test fail under the full run; that test and the panel regression
both passed in an isolated rerun (2 tests). The Release build passed. These
checks do not by themselves establish end-to-end OCR/speech success. The owner
then physically pressed Option-R and confirmed that the region selection appears.
During UI investigation, opening the separate setup window
also produced an AppKit constraints crash; that remains a separate issue.

The corrected Release executable was installed in `/Applications/Saywing.app`
with the existing model resources retained; signature and Audio Input entitlement
verification passed. After replacing stale TCC entries, the running app confirmed
Screen Recording, Input Monitoring, and Accessibility access. The old Microphone
entry still had a mismatched code requirement; its app-specific approval was reset
and requested again. The system permission dialog is blocked from Computer Use,
so final microphone consent remains for the owner. No recording was started.

## Behavior

The menu bar's Settings window offers Command, Shift, Option, and Control checkboxes plus a key picker (A–Z, 0–9, Space). At least Command, Option, or Control is required. Escape stays reserved for cancellation. Apply registers and saves the choice; Restore Default selects ⌘⇧Y. During selection, capture, or recognition, both the UI and model reject changes so the active cancellation shortcut cannot disappear.

Only the logical key and modifier mask are stored in the versioned `readingShortcut.v1` UserDefaults entry. Malformed or unsupported saved configurations load as the default. The UI does not record keyboard input or use the clipboard. App-unit tests inject memory stores; native UI tests use unique preference suites through a Debug-only launch environment override, leaving the user's actual preference untouched.

Carbon registration is exclusive. A replacement is acquired before the old registration is released; a failure keeps the old binding and saved preference. Each registration receives a unique event ID, checked both during event dispatch and before the queued callback to reject stale events. Normal menu commands and services cannot all be detected; the UI discloses this limitation and confirms Command-only choices. The default overlaps macOS's Make Sticky service.

Key lookup uses the keyboard layout at registration and its Command mapping, but excludes Shift/Option character transformations: choosing Option-R means the R key, not the alternate character produced by Option-R. After changing layouts, apply the shortcut again or restart the app. Dynamic layout tracking, function keys, punctuation keys, and a complete system-reserved shortcut matrix are not included in this slice.

## Development checks, 2026-09-05

- The initial test-first build failed on the not-yet-implemented configuration/store/model API. After implementation, the focused interaction suite passed.
- Unit checks cover valid/invalid configurations, persistence and malformed data, startup restoration/recovery, change rejection during selection and OCR, German/US Y placement, Option-letter and Shift-digit mapping, and failed changes preserving the previous configuration.
- A real Carbon test registers competing shortcuts in the native test host: a conflicting replacement is rejected, the old shortcut remains occupied, and a successful replacement releases the old shortcut. This is an actual OS registration test, not a mocked result.
- The first full UI run exposed ambiguous test selectors for Settings in the normal app menu versus the status menu. After scoping the selector, the custom shortcut test passed: choose ⌘⇧J, save, relaunch, confirm persistence, start selection from Finder, cancel with repeated ⌘⇧J, restore ⌘⇧Y (49.990 seconds, including XCTest overhead).
- The warning test then exposed a second selector ambiguity between the sheet's Cancel button and its Touch Bar counterpart. Its selector now targets the sheet specifically. These were test-query failures, not successful checks of those entire runs.
- ARM64 Release build passed with Hardened Runtime unchanged. Debug builds reuse the approved local certificate; no permission changes, paid developer membership, model downloads, or runtime network dependencies are introduced.
- The final full run at **00:12:24** passed all **44 tests** (36 Swift Testing tests, two live system tests, six native UI tests), with zero failures/skips. Parameterized cases expand this to 47 executed cases in Xcode's device summary. Custom shortcut persistence/start/cancel/default restoration passed in 50.137 seconds, the default Finder shortcut in 35.169 seconds, and invalid-selection/confirmation cancellation in 10.965 seconds. These durations include XCTest overhead, not measured product latency.
- `swift test` passed its one core test; the executable core behavior check passed all 11 cases. `git diff --check` passed. The Debug designated requirement still references the same local certificate, and the Release signature still contains `runtime`.
- Direct Computer Use attachment to the exact Debug app timed out again. The attempted normal Settings keystroke could not be sent because that attachment was not active; the bundle identifier was also ambiguous between Debug and Release. No GUI state was inferred from those failures. The native UI suite provides the interaction evidence; an additional Computer Use screenshot inspection remains unverified.

These checks do not constitute a full VoiceOver audit, cancellation-latency measurement, or proof across all keyboard layouts, secure-input contexts, and third-party shortcut managers. Prior Finder-test intermittency remains part of the project verification history.
