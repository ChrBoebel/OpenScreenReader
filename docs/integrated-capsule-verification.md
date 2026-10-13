# Hover capsule controls — 2026-09-22

## Scope

The owner rejected the wider, permanently visible options iteration and selected
the hover alternative: waveform and Stop at rest, Pause/Resume and options in the
waveform's place on hover. No detached badge or hover resizing.

- Active body: 136 × 44 pt; nine waveform bars retain their 3.5 pt gaps.
- Pause and options: separate 40 × 44 pt hit targets, warm-white glyphs, no resting
  button background. Stop retains its independent 44 × 44 pt target.
- Side layouts keep glyphs upright and prefer inward-facing popovers.
- Five-point pointer movement on either secondary button drags instead of clicking.
  State transitions and cancellation suppress pending clicks.
- Controls remain revealed while the popover is open. The menu's Playback Controls
  entry and VoiceOver custom actions do not depend on hovering. Opening from these
  paths synchronously reveals the settled capsule's popover anchor.
- Preparation disables Pause; normal terminal states hide secondary buttons.
  Error help remains visible. No extra sounds, provider, pipeline, network,
  persistence or permission changes.

## Verification

1. The new compact/hover assertions first failed against the permanent-options
   implementation. Final run: **89 Swift tests in six suites passed**.
2. Two permission-dependent XCTest cases explicitly **skipped**: Screen Recording
   and Input Monitoring were unavailable for the rebuilt test host. These are not
   successful live OCR/Esc tests.
3. Coverage includes stable hover geometry, hidden controls' hit testing, separate
   targets, synthetic responder click/drag routing, cancellation during a press,
   pause/resume labels, popover retention, accessibility action handlers, queue
   count, terminal visibility, inward edges and controller drag/placement lifecycle.
4. The opt-in renderer produced 21 actual native-view images: three edges × rest,
   hover, paused, queued, preparing, failed and finished. Representative rest,
   hover, pause, queue and error output across all edges was visually inspected.
   These are app-only view renders, not live desktop screenshots or mockups.
5. Release build and `codesign --verify --deep --strict` passed. This is not
   notarization or a distribution release.

Local evidence, outside Git:

- `/tmp/osr-hover-red.log`
- `/tmp/osr-hover-final.log`
- `/tmp/osr-hover-release.log`
- `/tmp/osr-hover-renders/`

## Remaining gaps

Computer Use retried the exact rebuilt Debug app and returned
`Computer Use server error -10005: timeoutReached`. The previous iteration's native
drag/dock UI test also stopped before its body with an automation-mode timeout.
No live end-to-end, real pointer or VoiceOver audition success is claimed.

Still verify actual hover entry/exit, clicks and drags, popover opening from the
menu and VoiceOver, keyboard focus, accessibility display preferences, full-screen
Spaces and external monitors when live automation is available.

The installed `/Applications/OpenScreenReader.app` was not replaced. No permissions
were changed. Changes remain on `codex/integrated-capsule-controls`, without commit,
push or PR.
