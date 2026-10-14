# Text to Voice — verification, 2026-10-14

## Owner decision and scope

The owner selected concept B, **Text wird Stimme**, and the colors from its reference board: Ink Navy `#172B3A`, Paper `#F4F2EC`, Petrol `#266D79` and Apricot `#E4B78F`. The previous Quiet Owl artwork and rules are archived. The name Saywing and technical bundle identity stay unchanged.

Transparent raster masters replace the brand mark, app icon and menu template. AppKit uses the menu mark's alpha with the system foreground. The export script produces app icon sizes 16–1024 px and menu templates 22/44/66 px. Generated material shading is approximate; exact UI values are in `assets/brand-tokens.json`. These are raster assets, not vector masters. The built-in image generation tool produced the artwork; [final edit prompts](assets/text-to-voice-prompts.json) are retained.

The native controls use deep navy and pale petrol. Apricot is decorative on light surfaces and identifies attention states on dark surfaces. The HTML preview uses the current icon without an enclosing light panel. Its dictation descriptions now reflect the integrated private development build. No model, network, recording, clipboard, cancellation or persistence behavior changes.

## Integration with current main

The focused feature branch starts at `9e23b55`. It retains the guided setup, model installation, vocabulary and hands-free dictation changes already merged into main. The hands-free finish button uses the new palette while keeping its emphasis behavior. The current accessibility decision to hide the decorative settings logo is retained, as is its existing UI-test expectation. The selection outline uses the same pale petrol token as the other controls.

## Verification

- Xcode app-test target: Swift Testing reports **178 tests in 12 suites passed**. The opt-in live model download test is disabled; two permission-dependent XCTest checks are explicitly skipped because the test host has no Input Monitoring or Screen Recording grant. These skips are not counted as successful live permission checks.
- Xcode Release app build: **BUILD SUCCEEDED**.
- `python3 scripts/check-localization.py`: **Localization check passed**.
- Asset catalog validation: each referenced image exists, has the expected pixel dimensions and contains alpha.
- `sh -n scripts/export-app-icon.sh` and `git diff --check`: passed.

Commands use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`, project `OpenScreenReader.xcodeproj`, scheme `OpenScreenReader`, destination `platform=macOS`, and derived data `/private/tmp/saywing-brand-pr-build`. App tests use `-configuration Debug -only-testing:OpenScreenReaderAppTests test`; production compilation uses `-configuration Release build`. Local logs: `/private/tmp/saywing-brand-pr-tests-final.log` and `/private/tmp/saywing-brand-pr-release.log`.

Before the main integration, the same artwork/palette was inspected in native General settings. The HTML preview was checked in light and dark themes, German and English, at desktop and mobile widths; the read/dictate explanation toggle worked and the mobile page had no horizontal overflow. The final removal of the light icon panel was visually confirmed. Captured UI screenshots remain local and are not included in this PR.

## Limits and separate installation

An earlier settings UI-test attempt failed before its assertions because XCTest timed out enabling automation mode. No successful full UI-automation run is claimed here. The final PR verification does not exercise a live microphone, physical Fn key or end-to-end OCR/speech path. Exact vector masters, wider display/permission testing and public release gates remain open.

Before this PR was prepared, the owner separately requested a private installation of the branding workspace. That package passed signature/entitlement checks, 15 core checks, 12 Python tests and 10 offline checks for each of its three existing dictation models. It was installed at `/Applications/Saywing.app`, with its predecessor backed up in the original workspace's ignored `.build/text-to-voice-install-20261014/previous/` directory. Those packaging results apply to that installation, not to the later main integration. Source merge does not rebuild, reinstall, notarize or publish the app.
