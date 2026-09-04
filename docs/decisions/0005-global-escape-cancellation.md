# ADR 0005: Global Escape cancellation permission gate

- Status: Provisional pending Gate E
- Date: 2026-09-04

## Context

The product requires both `Esc` and the repeated global hotkey to cancel selection, OCR, synthesis, queued audio, and playback. During selection the overlay can receive `Esc` locally. After the overlay closes, another application normally owns keyboard focus, so observing bare `Esc` may require Input Monitoring or Accessibility permission and may be affected by macOS Secure Input.

## Proposed decision

- The repeated configured hotkey is always a global cancellation path.
- A bare-`Esc` monitor exists only while a generation is active and is removed immediately after cancellation or completion.
- The monitor recognizes only `Esc`; it never stores, logs, or forwards other keyboard input.
- The app requests no broader permission unless Gate E proves it technically necessary for the stated behavior.

## Gate E

On the minimum and current supported macOS releases, test selection, OCR, synthesis, and playback while another app has focus for:

- permission not requested;
- permission granted, denied, and later revoked;
- app relaunch and sleep/wake;
- Secure Input active;
- cleanup after success, error, and cancellation.

If reliable global `Esc` requires a permission whose UX or privacy cost is unacceptable, the owner must explicitly revise the product invariant. Implementation must not silently claim global `Esc` while supporting it only during overlay focus.
