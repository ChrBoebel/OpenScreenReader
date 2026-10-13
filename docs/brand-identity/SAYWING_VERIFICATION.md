# Saywing implementation verification

**Follow-up:** the branding and capsule work are now integrated in the primary checkout. See [integration, startup diagnosis and private test package](../saywing-integration-verification.md). The isolated-worktree findings below describe the earlier branding-only run.

Date: 2026-10-13, Europe/Berlin. Branch: `codex/saywing-brand` in the attached isolated worktree. The original checkout's existing capsule-control changes were not modified. No commit, push, PR, merge, domain purchase or publication was performed.

## Delivered

- Product/executable/display name Saywing; original bundle ID, module names, preference keys and development runtime location retained.
- Approved Quiet Owl masters copied into the repository; all macOS icon sizes and 22-pt template glyph at 1×/2×/3× exported using the existing native sips workflow.
- Native settings, setup, quit action, menu accessibility/tooltip and green UI palette updated.
- Dictation explicitly marked as a separate experiment, not a functional action in this build.
- Packaging input/output names and Xcode scheme product references updated.
- Canonical brand system, tokens, product vision, README and roadmap updated; earlier brand system archived.
- Local German/English and light/dark brand preview and a local comprehension-test worksheet created. No remote resources, analytics or automatic response persistence.

## Tests and build

1. Updated existing bundle-identity expectations before implementation. The targeted test failed against the original name, as expected.
2. Final native test run: **85 app tests in 6 suites passed**, plus **1 XCTest UI test passed** for the real Settings window.
3. The asset test verifies that `SaywingMenuBar` loads from the built catalog as a template image at 22 × 22 points and decodes successfully.
4. The UI test verifies the named owl image, descriptor, dictation-in-testing label and retained permission/privacy explanations. It attaches a screenshot of the app's Settings window, not the whole desktop.
5. Release build: **BUILD SUCCEEDED**. Built plist confirms name/display name/executable `Saywing` and identifier `com.christopherbobel.OpenScreenReader`. Deep strict verification of the existing ad-hoc signature passed.
6. Packaging Ruby syntax, export shell syntax, both embedded JavaScript syntax checks, local HTML link existence, unique IDs, catalog image references and `git diff --check` passed.
7. Calculated static contrast: Juniper/Porcelain 10.96:1, Pale Leaf/Forest 10.53:1. Leaf/Porcelain 4.37:1; a darker Leaf Text is used for light-mode controls.

Final test result:
`/private/tmp/saywing-build/Logs/Test/Test-OpenScreenReader-2026.10.13_18-33-36-+0200.xcresult`

Final logs: `/private/tmp/saywing-final-tests.log`, `/private/tmp/saywing-release.log`.

Commands used (DEVELOPER_DIR points to the installed Xcode):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/saywing-build \
  -only-testing:OpenScreenReaderAppTests \
  -only-testing:OpenScreenReaderUITests/MenuBarSmokeUITests/testSettingsExplainCapturePrivacyAndPermissionActions test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project OpenScreenReader.xcodeproj -scheme OpenScreenReader \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/saywing-build build
```

## Limits and unresolved checks

- Two earlier Settings UI attempts failed because they required `Saywing, Ready`, while the actual startup status was `Saywing, Error`. The branding test now explicitly opens Settings regardless of pipeline state; it does not claim to fix or validate that startup error. Pipeline/UI tests continue to require their expected states. Full installed-app hotkey/OCR/speech regression remains open.
- Direct native Computer Use attachment timed out. The actual Settings screenshot and successful interaction are from XCTest.
- Browser policy blocked file-URL navigation to the preview. No alternate browsing method was used to bypass that restriction. The HTML was inspected statically and its scripts syntax-checked; responsive rendering, live theme/language interactions and the five-second worksheet flow have not been browser-verified in this turn.
- The Release build uses the existing separately installed development speech runtime. No new self-contained model bundle, clean-Mac test, Developer ID signature, notarization or public release was created.
- Raster assets are implemented; exact vector reconstruction and layered Icon Composer artwork remain pending.
- No real name-test participants have been surveyed. Trademark similarity review, final domain availability/price and any registration remain separate external steps.
- The isolated branding worktree starts at the original checkout's committed HEAD. The uncommitted capsule changes in the original checkout must be integrated during review; they are not included in this build.
