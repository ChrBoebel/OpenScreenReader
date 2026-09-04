# ADR 0001: Native Swift macOS application

- Status: Accepted
- Date: 2026-09-04

## Context

The product is a macOS menu bar utility whose difficult boundaries are system-level: global input, transient multi-display overlays, region capture, Vision OCR, AVFoundation playback, permissions, accessibility, signing, and notarization. A possible Windows version remains a later product phase.

## Decision

Build the macOS application with Swift 6, SwiftUI, and AppKit:

- SwiftUI for the menu bar, settings, and ordinary controls;
- AppKit for overlay windows and global event handling;
- ScreenCaptureKit for selected-region capture;
- Vision for local OCR;
- AVFoundation for streamed playback.

Use an Xcode application project with unit and UI test targets. Introduce local Swift packages only when a proven module boundary benefits independent testing.

Platform-neutral behavior belongs in protocols, value types, JSON fixtures, and the versioned worker wire format. AppKit, Vision, and MLX types must not cross those boundaries.

## Consequences

- The macOS product can follow native permission, accessibility, windowing, and distribution behavior directly.
- A later Windows app will need a separate native shell and platform adapters.
- Text rules, protocol fixtures, model identity, and observable behavior can still be shared.
- Choosing Swift does not commit the project to an embedded Swift MLX runtime; the TTS process boundary remains provisional.

## Validation

This decision is revisited only if a native shell cannot pass the selection, cancellation, packaging, or clean-install gates in the construction plan.
