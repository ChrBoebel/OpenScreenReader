# Saywing branch reconciliation — 2026-10-14

The owner authorized meaningful commits, a push of the integrated feature branch, and an open pull request targeting `main`. No merge or application release is authorized by this work.

## Preservation of the older branding worktree

The older `codex/saywing-brand` worktree and the integration branch started from `545045b`. Its 44 modified/new files were compared with the primary checkout: 28 were byte-identical, 16 had subsequent integration/design changes, and none was missing.

Commit `14aa9fe` preserves all 44 original branding files byte-for-byte, including the generated logo/icon masters, native asset exports, naming research, historical brand specification, product renaming and UI changes. Their contents were verified against a SHA-256 inventory before and after the commit. This reconstruction staged the older snapshot without replacing any current working files. The old worktree itself remains unchanged and has not been removed, reset or archived.

Commit `2d0006b` adds the pinned offline Qwen3-ASR / Whisper Turbo worker, model/runtime manifests, protocol/integration tests and source/license documentation. The subsequent app integration commit contains the current native dictation lifecycle, Fn controls, focus/cancellation handling, compact reading/dictation surfaces and current verification documents.

Local pre-commit archives of the 76 integrated files and 44 branding files also exist in ignored `.build/pr-integration-2026-10-14/`. These local archives are an additional recovery aid; the commits preserve the source history on the feature branch. Model weights, dependency binaries and installed-app backups remain outside Git.

## Verification of the integrated tree

- Full native app test rerun: **128 Swift Testing tests in 9 suites passed**. Two permission-dependent XCTest checks explicitly skipped: Screen Recording and Input Monitoring were not granted to the test host.
- Initial app run overlapped real ASR inference. `queueCaptureTimeoutDoesNotInterruptSpeechOrAcceptItsLateResult` failed while establishing its initial speech state with a 120-ms operation timeout; no first speech call occurred. The complete rerun without concurrent model inference passed, without changing the test or app. This timing sensitivity remains a test reliability issue, not a claimed fix.
- `scripts/verify-dictation.sh` against the installed self-contained Dictation resources: **15 private-pasteboard/core checks**, **10 Python protocol tests**, and **10 real model checks per provider** passed. Both Qwen3-ASR and Whisper Turbo handled public German/English fixtures, explicit language choice, silence, invalid samples, process cancellation, denied network access and denied file writes.
- The six installed worker/protocol/manifest files matched the repository byte-for-byte before accepting these model checks as evidence for this branch.
- Native **Release build succeeded**.
- **Two native XCTest UI flows passed**: menu/status actions with selection and Escape cancellation, and bottom/left/right docking with persistent placement and the independent Stop target. The UI runner recovered from foreground-window interruptions; neither test was skipped.
- Outgoing file inventory and credential-pattern review found no model weights, audio recordings, credentials or captured screen content. New binary files are approved brand assets. `git diff --check` passed.

Commands used Xcode at `/Applications/Xcode.app/Contents/Developer`. Local logs: `/tmp/saywing-pr-app-tests.log`, `/tmp/saywing-pr-app-tests-isolated.log`, `/tmp/saywing-pr-dictation-tests.log`, `/tmp/saywing-pr-release.log` and `/tmp/saywing-pr-ui-tests.log`. Temporary logs are not repository artifacts.

## Remaining gates

This is a development-source integration, not a distributable app release. Live microphone/Fn use, broader target-app and display/Spaces coverage, clean-Mac packaging, full transitive licensing/provenance and notarization remain open. The previously intermittent clipboard-restoration result in the integrated demo self-test is not resolved by passing the private-pasteboard tests; see [the capsule verification history](dictation-capsule-verification.md). No model downloads or microphone recording were used for this reconciliation.
