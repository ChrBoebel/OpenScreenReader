# Saywing dictation capsule — 2026-10-13

The native dictation status surface now shares the reading capsule's Forest/Pale Leaf palette, translucent HUD material, rounded 44-pt body, nine bars and existing 44-pt controls. Recording has a separate microphone symbol and monospaced elapsed/maximum duration. Cancel and finish/paste have distinct actions. No additional recording sounds are emitted.

Only the existing lock-protected microphone RMS scalar reaches the view. Silence maps to flat bars, levels are finite/bounded, and updates outside recording are ignored. Processing has fixed-height points with traveling brightness, rather than a fake microphone waveform or percent. Reduced Motion disables continuous motion; Reduce Transparency produces an opaque backing; Increase Contrast strengthens the edge. Hidden panels invalidate the animation clock. No microphone, model, clipboard, target-validation or shortcut behavior was replaced.

The nonactivating panel keeps the original text-field focus. Active work is never auto-dismissed by a repeated shortcut or an older hide timer. Terminal close dismisses the panel without discarding the retained result. A checkmark appears only after verified insertion; unverified paste retains “Einfügen ausgelöst / Bitte Zielfeld prüfen.” Attention states offer the full detail as help/tooltip and open the setup window when clicked or through an accessibility action.

## Verification

- New capsule tests first failed to compile against the missing implementation.
- First focused completed run: **22 tests passed** (capsule + existing dictation lifecycle).
- Final complete app run: **123 Swift Testing tests in 9 suites passed**. Includes a further controller regression for retained results, cancellation and obsolete hide work.
- Two permission-dependent XCTest cases were skipped: Input Monitoring and Screen Recording were not granted to the test host. They are not counted as verified live paths.
- Native Release build: **BUILD SUCCEEDED**.
- Seven native view-only PNG renders were reviewed, including recording, processing, verified/unverified insertion and attention. Their levels are synthetic specimens, not live microphone evidence.
- `git diff --check` passed.

Local logs: `/tmp/saywing-brand-{red,tests,full-tests,release}.log`. Tests/derived data: `/tmp/saywing-brand-build`. Native render outputs: `/tmp/saywing-dictation-renders`.

## Installation and remaining checks

The update reuses the existing installed Speech and Dictation resources, after deep strict signature verification, without downloading or replacing weights. The new executable and application resources come from the Release build. A source-hash inventory is bundled as `Contents/Resources/LOCAL-BUILD.json`. The prior app is retained in ignored `.build/saywing-brand/previous/Saywing.app`.

Physical Fn/microphone operation, VoiceOver speech, all display/Space combinations and reduced-motion system-setting walkthrough remain manual checks. Native renders and deterministic tests do not establish those paths. This remains a private ad-hoc development build.

Installed `/Applications/Saywing.app` passed deep strict signature and signed Audio Input entitlement checks. Its bundled Swift source hashes match the workspace. The app starts with the saved Whisper Turbo selection; microphone and Accessibility grants remain available.

The installed public-sample self-test recognized and inserted both German and English samples. On the first run it reported `clipboard_restored: false` without a recognition/paste failure. A repeat without concurrent UI observation reported both demos completed, no failures and `clipboard_restored: true`; the exact cause of the first mismatch is not established. All 15 separate private-clipboard/core checks also passed. An additional external snapshot watcher timed out because its resource-date polling cached the old report timestamp; it is not counted as independent verification. The final native UI visibly displayed “Beispieltests erfolgreich.” Synthetic test contents were cleared, the setup window closed, and Saywing left running. No live microphone recording was made.


## Compact revision requested by the owner

The owner rejected the 360 × 44-pt text/timer surface. It is replaced by a constant **120 × 28-pt** pill: small X on the left, nine input bars in the center, small stop square on the right. All visible text fields and the elapsed-time presentation were removed. Separate 32 × 44-pt pointer targets extend into transparent vertical padding; they never overlap. Terminal icons and processing dots use the same fixed body. The 60-second recording limit remains in the controller.

Research used Wispr's [Flow Bar documentation](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop) and [hands-free instructions](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free). The official historical Flow Bar GIF linked by its launch changelog was also viewed in the browser. These establish the small floating visual and cancel/finish semantics, not exact current pixel dimensions. No Wispr code or assets were copied into the app.

The new no-text/fixed-size test first failed against the prior implementation. After implementation **24 focused capsule and dictation lifecycle tests passed**, including retained results, stale hide work, finite audio levels, focus policy and distinct controls. Seven native state renders were generated and recording/processing visually inspected. Logs: `/tmp/saywing-mini-{red,tests,release}.log`; renders: `/tmp/saywing-mini-renders`.

Compact revision Release build succeeded; installed deep strict signature verification and Audio Input entitlement checks passed. Installed source hashes match the workspace. The larger version is preserved at ignored `.build/saywing-brand/previous-large-capsule/Saywing.app`.

The compact installed build completed both public-sample insertions and retained microphone/Accessibility access, but its self-test again reported `clipboard_restored: false`. This repeats the earlier intermittent clipboard-snapshot comparison issue; its cause remains unresolved, and this run is not called a complete self-test pass. No clipboard implementation was changed in the compact revision. The native UI confirmed the inserted sample; test contents were cleared and the app left running. Physical microphone/Fn verification remains open.
