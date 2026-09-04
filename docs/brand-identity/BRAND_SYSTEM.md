# OpenScreenReader Brand System

**Status:** Approved direction
**Decision date:** 2026-09-04
**Canonical app-logo artwork:** [`assets/open-screen-reader-app-icon.png`](assets/open-screen-reader-app-icon.png)

## Decision

The original **Owl Frame** concept is the selected OpenScreenReader app logo. Later owl and text-to-wave explorations remain in `animal-concepts/` as design history, but they are not approved brand assets.

The selected mark is a clearly recognisable owl built from the product's region-selection geometry. Its almond-shaped eyes, light central beak, forehead arches, and contained lower voice curve are essential recognition anchors. The result should feel calm, capable, friendly, and distinctly macOS-native without becoming a cartoon mascot.

## Source of truth

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

## Typography and shape language

- Product UI: system font / SF Pro through native macOS APIs.
- Brand and website shortlist: Geist Sans or Instrument Sans; final choice remains open.
- Rounded or subtly tapered terminals; friendly but not pill-like corner radii.
- Reuse the logo's selection-corner geometry in the region-selection overlay.
- Motion, if used, should be one soft travelling pulse—not a permanent equaliser.

## Production handoff

Before shipping, reconstruct the selected PNG as auditable vector geometry and layered Icon Composer artwork. The production package should include:

1. layered macOS app icon with appearance variants;
2. flat one- and two-colour brand marks;
3. monochrome menu-bar glyph;
4. export set and asset-catalog entries for the actual app target;
5. documented clear space, minimum sizes, colour tokens, and export procedure.

No app target or `AppIcon.appiconset` currently exists in the repository, so the selected logo is documented and canonicalised here but is not yet wired into an application bundle.
