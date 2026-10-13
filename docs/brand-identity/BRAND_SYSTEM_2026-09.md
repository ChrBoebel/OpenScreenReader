> Historical record, superseded by [Saywing / Quiet Owl](BRAND_SYSTEM.md) on 2026-10-13.

# OpenScreenReader Brand System

**Status:** Approved direction
**Decision date:** 2026-09-04
**Canonical app-logo artwork:** [`assets/open-screen-reader-app-icon.png`](assets/open-screen-reader-app-icon.png)

## Decision

The original **Owl Frame** concept is the selected OpenScreenReader app logo. Later owl and text-to-wave explorations remain in `animal-concepts/` as design history, but they are not approved brand assets.

The selected mark is a clearly recognisable owl built from the product's region-selection geometry. Its almond-shaped eyes, light central beak, forehead arches, and contained lower voice curve are essential recognition anchors. The result should feel calm, capable, friendly, and distinctly macOS-native without becoming a cartoon mascot.

## Source of truth

- **Product name:** `OpenScreenReader` (no approved rename).
- **Current concise claim:** `Select. Listen. Stay private.` as used in the README. Alternative lines in the brandbook remain proposals.
- **Canonical approved raster:** `docs/brand-identity/assets/open-screen-reader-app-icon.png`
- **Machine-readable tokens:** `docs/brand-identity/assets/brand-tokens.json`
- **Original concept file:** `docs/brand-identity/animal-concepts/01-owl-frame.png`
- **Explorations:** `docs/brand-identity/animal-concepts/owl-round-2/`, `owl-round-3/`, and `owl-b-refinements/`
- **Current limitation:** the approved artwork is a generated RGB PNG, not yet a production vector or layered Icon Composer source.

Do not silently replace the canonical artwork with an exploration. A future redraw may improve geometry and rendering, but it must preserve the selected silhouette and the four recognition anchors above and requires an explicit design decision.

## Core palette

The palette values below are normative. Colours sampled from the rendered PNG may differ slightly because it contains shading and material effects.

| Token | Hex | Primary role |
|---|---|---|
| **Local Ink** | `#0B1724` | Dark foundation, primary text, dark icon base |
| **Voice Mint** | `#55E0BE` | Owl/frame mark, selection state, primary brand accent |
| **Mint Light** | `#B8F7E7` | Soft highlight, secondary tint, light-detail support |
| **Warm Paper** | `#F7F4ED` | Beak and eye details, light canvas, warm neutral |

### Contrast guardrails

Measured WCAG contrast ratios:

- Local Ink / Voice Mint: **11.01:1**
- Local Ink / Mint Light: **15.05:1**
- Local Ink / Warm Paper: **16.45:1**
- Voice Mint / Warm Paper: **1.49:1**

Therefore:

- Use Local Ink with Voice Mint, Mint Light, or Warm Paper for high-contrast foreground/background pairings.
- Do **not** use Voice Mint as body text, thin UI text, or an essential low-area indicator on Warm Paper.
- On light surfaces, use Local Ink for text and reserve Voice Mint for larger accents, focus/selection states, and non-text brand moments.
- Do not communicate state through colour alone.

## Icon usage

### App icon

- Use the complete Owl Frame artwork for the Dock, application bundle, release pages, and primary product avatar.
- Preserve generous optical padding around the owl.
- Preserve the Deep Ink/Local Ink base, mint owl geometry, light eye/beak details, and restrained material depth.
- Do not add text, badges, sparkles, microphones, headphones, speech bubbles, or extra equaliser bars.
- Do not stretch, rotate, recolour piecemeal, redraw the eyes as circles, or make the expression more cartoon-like.

### Small sizes and menu bar

The full raster artwork is not the final menu-bar glyph. Produce and test a separate monochrome derivative before implementation. It should retain the selection-frame silhouette and owl recognition without relying on colour or fine facial detail.

Required production tests: `16`, `20`, `32`, `64`, `128`, `256`, `512`, and `1024` px; light and dark appearance; monochrome; increased contrast; and reduced transparency.

### Product UI

- Region selection and primary focus moments: Voice Mint against sufficiently dark surroundings.
- Quiet surfaces and primary typography: Local Ink or system semantic colours.
- Light brand canvas: Warm Paper rather than pure white where brand styling is appropriate.
- Decorative highlight only: Mint Light.
- Use macOS semantic colours for standard controls and states instead of forcing brand colours into every interface element.

### Reading-control motion and sound, 2026-09-05

Two earlier passes were rejected by the owner: a restrained notification-style card and a hand-drawn "Reading Lens" frame. A third, island-style pass with title text was then reset again after the owner pointed at Wispr Flow's text-free bar and asked for a control that communicates through animation, colour and sound and is "super aesthetic". See [the research brief](../research/reading-control-motion-study.md) and [native verification](../reading-panel-verification.md). Final subjective acceptance remains the owner's call. The canonical Owl Frame artwork and palette remain approved.

**Owner-approved exceptions to the shape rules below:** the reading control is a **capsule** (fully round ends) and its voice is a row of **rounded bars**. The bars are not a frequency equaliser: they follow one travelling wave driven by the rendered speech level. These exceptions apply to this control only, not to icons, the app logo or other surfaces.

The control is a text-free capsule 44 pt tall over a system blur, tinted deeper than Local Ink so mint reads as light. Nine Voice Mint bars are the living centre; their colour rises with height from dimmed mint through Voice Mint to Mint Light with a near-white core. After capture the selection frame collapses as a mint ghost into a glowing dot and springs open into the capsule, with the opening sound landing on the same beat. Recognition shows a travelling light, preparation lets the bars rise one by one. Terminal states draw a mint check, a paper stop square or a warm amber attention ring; amber is an attention accent only. Text appears only as an Esc keycap on hover and as two words for attention states; accessibility labels and VoiceOver announcements always carry the full status. The round 44 pt stop control compresses on press and springs back with haptic, key-down and key-up sounds. Reduce Motion, Reduce Transparency and Increase Contrast each have a defined static or opaque alternative.

Sound is one original stereo family of **wood and water**, chosen after a research pass on satisfying interface sound (short, warm and simple for frequent cues, richer only for rewards, physical models rather than beeps): marimba-style bars with 1 : 4 : 10 partials, water drops as entrained-bubble chirps, a low log-drum thud and a small synthetic room. Opening (thud, two rising bars, one drop at landing), completion (a quiet deep root and three rising drops, deliberately the most restrained reward), attention (two muted falling knocks), key down and key up; opening and completion alternate between two voicings. Volume and Off are independent of speech; cancellation itself is silent and no cue overlays speech. This does not approve earlier text-to-wave app-logo explorations or copying competitor artwork/audio.

## Typography and shape language

- Product UI: system font / SF Pro through native macOS APIs.
- Brand and website shortlist: Geist Sans or Instrument Sans; final choice remains open.
- Rounded or subtly tapered terminals; friendly but not pill-like corner radii. Sole exception: the reading control capsule (see above).
- Reuse the logo's selection-corner geometry in the region-selection overlay.
- Motion should communicate an event or actual playback: one opening gesture and a level-driven voice, not an arbitrary permanent equaliser.

## Production handoff

Before shipping, reconstruct the selected PNG as auditable vector geometry and layered Icon Composer artwork. The production package should include:

1. layered macOS app icon with appearance variants;
2. flat one- and two-colour brand marks;
3. monochrome menu-bar glyph;
4. export set and asset-catalog entries for the actual app target;
5. documented clear space, minimum sizes, colour tokens, and export procedure.

The native app target now includes `OpenScreenReaderApp/Assets.xcassets/AppIcon.appiconset`. Run `sh scripts/export-app-icon.sh` to reproduce its raster sizes from the canonical approved PNG. These are size exports only; the original geometry, colours, and padding are preserved. The app bundle uses `AppIcon`. Layered Icon Composer artwork, appearance variants, the monochrome menu-bar derivative, and the complete production appearance/accessibility matrix remain pending.

The Settings header displays the installed app icon, product name, current concise claim, and version. `CFBundleName` and `CFBundleDisplayName` both use the existing `OpenScreenReader` product name. The bundle identifier is unchanged so this branding adjustment does not create a new app identity for macOS permissions. The menu bar continues using semantic status symbols until a separate approved monochrome mark is available; the full-colour raster is not used as a tiny menu-bar glyph.

### Implementation verification, 2026-09-05

The new bundle-identity test first failed because `CFBundleDisplayName` was absent and passed after adding it. The 00:18:04 full run passed all 37 app-unit tests, both live permission tests, and the native Settings test, including the named logo image and claim. Three other UI tests failed: the two Finder shortcut checks did not see the overlay, and the drag check encountered an XCTest non-finite-coordinate exception. The total was 42 passed, three failed, zero skipped; it is not a clean full regression result. Release build and plist validation passed. Computer Use attachment to the exact Debug app timed out, so no additional live screenshot inspection is claimed.

In the targeted no-rebuild rerun, the custom shortcut/persistence test passed (51.611 seconds), and the drag test passed (9.595 seconds). The default-shortcut test reached its repeated-cancellation check but failed to observe Stopped. This leaves shortcut UI reliability unresolved; it does not invalidate or replace the earlier full-run failures, and no cause is inferred solely from the branding change.
