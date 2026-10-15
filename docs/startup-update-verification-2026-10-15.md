# Update check at launch — 2026-10-15

Owner request: check for updates immediately at app startup and show available updates.

`AppUpdateController` now starts Sparkle and immediately calls
`checkForUpdatesInBackground()` in the same main-runloop turn, only when the effective
`automaticallyChecksForUpdates` preference is enabled. No setting is overwritten.
This follows Sparkle's [startup API contract](https://sparkle-project.org/documentation/programmatic-setup/#api-expectations).
The existing four-hour schedule, signed feed/archive checks, user-confirmed installation,
no-profile policy and busy-operation guards remain in place. No new timer or async task is added.

## Verification

- Test-first failure: the new app tests failed to compile before the startup seam existed.
- All 193 app tests passed, including startup call order, opt-out resolved during startup,
  and no update call after a failed initialization.
- Release builds passed for arm64 and x86_64 with macOS deployment target 14.0.
- An isolated AppKit probe compiled the actual controller against the pinned Sparkle.
  Its own bundle ID/preferences prevent changes to the installed Saywing app.
  It uses the real signed production feed and sets the last-check timestamp to the
  current time immediately before starting the controller.
- Automatic checks enabled, older probe version: a fresh check occurred, an available
  update was reported, and exactly one native window was visible after 12 seconds.
- Automatic checks disabled: updater configured, timestamp unchanged, no update offered.
- A probe version newer than the feed: a fresh check occurred, no update offered and
  no native window visible. No downloads or installations were performed.

Machine-readable results: [startup-update-verification-2026-10-15.json](startup-update-verification-2026-10-15.json).
Raw local harness and logs are in `.build/startup-update-verification/` (not committed).
The Computer Use screenshot attempt timed out; window visibility was instead checked
inside the actual AppKit process. This is not a claim of a complete installed-app
walkthrough or a native Intel device test. No public release has been made for this change.
