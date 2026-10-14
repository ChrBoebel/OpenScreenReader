# Dictation window startup correction — 2026-10-14

Installing main `155c790` reproduced a production startup abort both normally and
with `--dictation-setup`. The crash reports point to
`DictationController.buildWindow()` forcing AppKit layout during the SwiftUI
`StateObject` initializer. AttributeGraph aborts when that layout re-enters its
active update. Unit-test hosts disable the production dictation controller, so
passing those tests alone did not establish that production startup works.

The local correction keeps controller construction free of explicit window
layout. The first `showWindow()` fits and centers the window; later openings keep
the user's window position. It does not start recording, alter permissions or
change models, shortcuts or persistence.

The new regression initially failed because the content was already fitted
(654 pt rather than its initial 600 pt). After the correction, all **149 tests
in 10 suites passed**, including initial sizing, first presentation, position
preservation on reopen and no microphone recording. Two permission-dependent
XCTest checks remain skipped for the test host.

Before this correction, the refreshed package also passed 15 dictation core
checks, 10 Python protocol tests and 10 real offline model checks per provider.
The installed runtime now includes the current main worker with localizable
message codes. All 36,390 pre-existing runtime receipt hashes were verified
before reuse; model weights were not downloaded or changed.

This correction is local on `codex/fix-dictation-startup-layout`, based on main
`155c790`; it has not been committed or pushed. Installation and final startup
results are recorded in the ignored local installation receipt.

Final local verification: corrected Release build, deep strict signature and
Audio Input entitlement checks passed. `/Applications/Saywing.app` starts and the
new German setup window visibly reports Ready. Its signed executable and all 38
app-source/resource inventory entries match the staged build and workspace.
The updated worker matches the repository. The latest crash report remains the
uncorrected main startup. The new ad-hoc identity reports all four macOS privacy
permissions as not granted; setup is left open for the owner to renew them.
No live microphone recording or new permission grant was performed. The previous
working app remains in `.build/main-install-155c790/previous/Saywing.app`.
