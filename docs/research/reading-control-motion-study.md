# Reading control: Superwhisper / Wispr Flow research

Date: 2026-09-05. Status: research followed by owner-authorized native implementation; final subjective design acceptance remains open.

The owner found the first native animation pass too weak and generic and asked for a deeper comparison. Implementation was paused for this study, then authorized in the following request. This document separates documented behavior, visual evidence, interpretation, and proposed parameters. The diagnosis and prototype values below record that research stage, not a description of the subsequently revised code.

## Scope and product lens

OpenScreenReader is a native, local, screen-region-to-speech utility. Its approved identity is Owl Frame, Local Ink, Warm Paper and Voice Mint. Its primary interaction is select → OCR → automatic speech, with immediate complete cancellation. Superwhisper and Wispr Flow are adjacent interaction-quality references: their dictation workflows run in the opposite direction. Their cloud, context, clipboard and history behavior is not a product template for this app.

The design tension is **distinctive and satisfying at the moment of interaction, quiet and trustworthy during sustained reading**. This is not a market-size, pricing or feature-parity study.

## Evidence

### Superwhisper

The official recording-window documentation describes compact and expanded states, controls revealed on hover, and a microphone-responsive waveform. Its mini-recorder illustration was opened and visually inspected: the compact dark shape centers the waveform; the hover state grows into a wider control with a strong end-button. There is very little explanatory text. This is evidence for a changing control surface, not evidence for any particular spring curve or millisecond timing. [Recording Window](https://superwhisper.com/docs/get-started/interface-rec-window)

Its sound settings distinguish recording readiness from processing completion, allow separate effect volume, and allow silence. The sound confirms a transition, rather than decorating every animated frame. [Sound settings](https://superwhisper.com/docs/get-started/settings-sound)

The changelog records a new sound style/options on June 9, mini-mode animation refinements and removal of trailing sound noise on July 6, and further audio cleanup on July 10, 2026. It also records focus, positioning and hover fixes. This supports treating sonic finish and interaction reliability as ongoing product work, not one visual-polish pass. [Changelog](https://superwhisper.com/changelog)

### Wispr Flow

The design team's 2025 article emphasizes an unobtrusive system-level control, responsiveness and continuity with the user's current application. The small bar is a point of availability rather than a conventional main app window. That is a design rationale, not an independent measurement of quality or latency. [Designing a natural and useful voice interface](https://wisprflow.ai/post/designing-a-natural-and-useful-voice-interface)

Current onboarding documentation explicitly connects readiness to a ping or moving white bars; ping and paste sounds depend on the Sound Effects setting. This gives sound a specific operational meaning. [Starting your first dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation)

Current accessibility documentation describes snapping the bar into bottom/left/right zones, reorienting its contents, preserving placement, keyboard focus and reduced-motion support. Transparent non-control areas are documented as click-through elsewhere. These reinforce the importance of physical behavior around the control. [Accessibility](https://docs.wisprflow.ai/articles/3941699399-keyboard-and-screen-reader-accessibility-in-wispr-flow), [Flow Bar behavior](https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop)

### Evidence limitations and contradictions

- The July 2025 design article's persistent-bar description is not proof of today's default: current help pages say new installations may hide it by default.
- A current troubleshooting page attributes docking to Android only, while the current accessibility page and July 9 desktop changelog describe desktop docking. Do not treat all platform details as settled without checking the installed version. [Troubleshooting](https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing), [What's new](https://wisprflow.ai/whats-new)
- Official websites and Superwhisper's mini-recorder illustration were inspected in the browser. A Flow film linked from its media kit was also opened; it is a brand film, not a controlled desktop motion test. Its selected frame does not establish app transition timings. [Media kit](https://wisprflow.ai/media-kit), [Brand film](https://www.youtube.com/watch?v=9KqGpxtsawc)
- The exact original sound timbre has **not** been reliably auditioned here. A playing browser video is not a model-visible audio recording, and promotional soundtracks are not necessarily runtime sounds. No claim about their exact pitch, layers, loudness, attack or decay is made.
- No native competitor application was installed, no account created, no microphone enabled, and no proprietary code or sounds copied. No precise competitor animation constants were measured.

## Why our first pass misses the target

This is an assessment of the current local code, not a competitor claim.

1. The 320 × 64 pt shell barely changes. Most visual activity is confined to a 28 pt icon; the voice curve itself is only 14 pt wide. A 2% scale and 4 pt entry movement do not give the main object a strong transformation.
2. The highlight repeats every 2.8 seconds independently of the actual speech. It communicates activity but not the satisfying causal relationship between sound and movement.
3. Icon + two lines of status + rectangular button reads as a notification. The frame motif is decoration inside the control rather than the thing that forms the control.
4. The two synthesized cues are short sine-based tones with a small overtone. They are functional sketches, not a finished sonic identity or an auditioned sound family.
5. Technical verification is unfinished: native testing exposed a first-show placeholder bug and an AppKit constraint-update exception during rapid state transitions. The placeholder was corrected; the layout exception still reproduced after disabling automatic hosting size constraints. The test run was stopped when the owner redirected the work to research. Do not describe this working tree as release-ready or fully tested.

Relevant code: `OpenScreenReaderApp/ReadingPanelController.swift`, `OpenScreenReaderApp/InterfaceSoundPlayer.swift`. Interrupted run: `/tmp/osr-motion-layout.xcresult`; log `/tmp/osr-motion-layout.log`. Earlier all-green unit results precede the real-host correction and do not establish final-code safety.

## Revised direction: the frame becomes the control

Working concept name: **Reading Lens**. This is not an app rename and not a new app logo.

The rounded selection corners should shape the whole small instrument. During active reading, a broad, responsive mint voice ribbon is the visual center; a plainly recognizable stop square has a permanent 44 pt target. Local Ink supplies a compact solid body, with a fine upper highlight and restrained shadow. No microphone, mascot animation, generic spectrum bars, spinning rainbow or glossy illustration.

Reduce permanent text. Keep a short visible state label in the first iteration; move explanatory help to hover/tooltips without hiding the stop action or accessible labels. It must remain understandable without color, audio or animation.

The following numbers are **proposed prototype starting values**, not measurements of Superwhisper or Wispr Flow:

| Event | Proposed movement | Proposed sound |
|---|---|---|
| Capture completed | The frame opens into a compact control, roughly 64 → 208 pt wide, with a perceptible but single 320–400 ms spring. A stop target is available immediately. | Short rounded “engage” cue, aligned to the visible opening. |
| OCR / preparation | The same body changes internally; lines gather into the voice ribbon. Show honest indeterminate preparation, not fabricated percentage progress. Skip obsolete states when work finishes quickly. | No repeated waiting sounds. |
| Speech begins | The ribbon becomes clearly responsive to actual playback. Start with 8–16 pt excursion across a wider 70–90 pt visual area; relax during pauses. | The voice itself is the confirmation; no cue over the first syllable. |
| Hover / press | Reveal secondary help within the same object. Visibly compress the pressed control, then return crisply; its hit area and screen position do not chase the pointer. | No hover tick. |
| Stop / completion | Silence speech first. Let the ribbon settle, the frame briefly close, then retract over about 180–240 ms. Completion and interruption stay distinguishable. | Optional soft closing cue for natural completion; cancellation silent by default. Audition before deciding defaults. |

The control must not appear in the capture or make the screenshot wait for a flourish. The opening occurs after the captured image is available; no screenshots or text fly across the desktop. Stronger event choreography must not mean constant bouncing during long passages.

### Playback-linked movement

The existing local PCM playback path is a plausible source for a low-rate amplitude envelope. It must follow **rendered** audio, not packets arriving early from synthesis. Send only ephemeral level values to presentation; do not retain audio or change the provider contract into a UI-specific dependency without need. Avoid allocation or SwiftUI updates on the audio render thread. Stop and stale-generation rejection must silence and reset the visual in the same operation. This is a feasibility direction, not an implemented measurement.

### Sonic identity

Audition two original sound families using the same motion sequence:

- **Soft tactile:** a rounded transient, a short warm body and a very short filtered tail. More physical than a sine beep, with no hard click or obvious literal shutter.
- **Clear ceramic:** a soft attack with a small harmonic resonance; brighter but without a sharp glass ping or long bell tail.

These are creative proposals, not descriptions of competitor audio. Use a consistent family for opening, successful completion and attention, with different gestures rather than unrelated alert noises. Tune in context at ordinary system volume. Provide independent effect level and Off; confirm that repetitions do not become tiring. All cues remain local and original. No cloud sound-generation service is required in the runtime.

## Acceptance before another native polish pass

1. A short motion-and-sound prototype at actual desktop size, including immediate stop, rapid repeat, slow preparation and error—not just a still moodboard or magnified icon.
2. Compare two expressive variants using the same text and audio. No undocumented “these are the competitor's exact settings” claim.
3. Evaluate entry impact, continuity, real speech response and the audio/visual ending together. Check ten repetitions as well as the first impression.
4. Keep the approved owl, palette, offline path and complete cancellation. Reduced Motion provides a clear static alternative.
5. Resolve the native constraint-loop regression before adopting the prototype in production code; then repeat real OCR → Supertonic → stop/completion/focus tests and inspect actual presentation.

The design-direction analysis changes the brief from “animate a status card” to “design a small, responsive reading instrument.” It does not establish that merely increasing bounce or volume will achieve the desired feel.

## Implementation follow-up

The first authorized native pass (a hand-drawn 244 × 60 pt "Reading Lens" with selection corners and a thin ribbon, driven by a 16 ms task loop) was rejected by the owner on sight: it did not look premium or feel satisfying. The brief was restated as "super aesthetic, satisfying, high quality, with far more satisfying sounds". The second pass replaces it rather than tuning it:

- **Material instead of flat fill.** A translucent Local Ink island over a system blur, with depth gradient, top highlight, hairline outline and two drawn shadows. Reduce Transparency makes it opaque.
- **A real spring instead of a hand-eased width.** The body opens from a 60 pt dot and closes back into it; the integrator runs on a `CADisplayLink`, not a sleep loop.
- **A glowing ribbon instead of a thin line.** Gradient stroke, halo and radial glow all scale with the rendered speech level; recognition has a travelling light, preparation a swell.
- **Drawn terminal symbols, sliding text, a finish pulse.** Completion and interruption stay distinguishable without colour.
- **A round stop button that compresses and springs back**, with haptic and click feedback, in a fixed 44 pt hit area.
- **A coherent sound family** (strike + harmonic body + tail) at a higher default level with normalised peaks and raised-cosine tails, replacing the three sine sketches.

The window grew to a 376 × 100 pt surface for shadow room; the body is 312 × 60 pt. These remain our choices, not measured competitor constants. No competitor assets, models or network dependencies were added. See [verification](../reading-panel-verification.md) for the actual build, regression and native-flow results. The proposed two-family sound audition and ten-repeat subjective comparison are still the owner's to perform; the opt-in preview export described there exists to make that audition easy.
