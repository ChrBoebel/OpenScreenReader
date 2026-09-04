# ADR 0004: Initial macOS platform baseline

- Status: Accepted as a pre-signing baseline
- Date: 2026-09-04

## Decision

- Bundle identifier: `com.christopherbobel.OpenScreenReader`.
- Minimum deployment target: macOS 14.0.
- Architecture: Apple Silicon (`arm64`) only for the first validated release.
- Initial supported validation class: an M-series Mac with 16 GB RAM.
- Project layout: Xcode macOS application with unit and UI test targets.
- Distribution: Developer ID-signed, hardened, notarized, and stapled self-contained DMG from the project website.
- Multi-display selection: the overlay appears on every active display and a drag may begin on any display, but one MVP selection is constrained to the display where the drag began.

## Rationale

macOS 14 provides the modern ScreenCaptureKit screenshot path while keeping the first implementation focused. The only measured Qwen baseline currently documented by the project is an M4 with 16 GB RAM, so broader hardware support must be earned through packaged-build tests rather than claimed in advance.

Constraining one selection to its start display avoids pretending that one display-local ScreenCaptureKit source rectangle can represent pixels from multiple displays. Cross-display stitching remains possible later behind the same capture contract.

## Validation and change policy

- Test the oldest supported and current macOS releases before public distribution.
- Test weaker M-series and 8 GB machines before expanding support claims.
- Revisit the deployment target if an essential API or runtime requires a newer OS.
- The bundle identifier may change only before the first signed build and permission-onboarding test; afterward it is stable because macOS permissions and signatures identify the app through it.
