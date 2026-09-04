# OpenScreenReader — Visual Identity Directions

**Status:** Exploratory design brief
**Decision surface:** Compare and select a visual territory before producing final logo assets.
**Brand basis:** `90_SYNTHESIS.md`, modules 10–70, product and privacy documentation.

## Executive recommendation

Start with **Direction A — Frame Friend** and retain **Direction B — Open Signal** as the more restrained alternative.

Frame Friend is the strongest fit because it derives its character directly from the product gesture — selecting a screen region — while a very subtle face makes the utility feel approachable. It can look warm without becoming a mascot, and it avoids implying that OpenScreenReader is a complete assistive screen reader.

## What “Silicon Valley quality” should mean here

The useful part of that aesthetic is not gradients, glass, or “AI sparkles.” It is disciplined reduction:

1. **One ownable idea:** the mark comes from the product interaction rather than a generic technology symbol.
2. **A recognisable silhouette:** the icon remains identifiable in the Dock, menu bar, GitHub avatar, favicon, and 16–32 px contexts.
3. **Few visual ingredients:** one main shape, one supporting detail, one signature colour.
4. **Controlled depth:** subtle material, highlight, and shadow make the macOS icon feel like an object without turning it into a 3D illustration.
5. **A complete system:** icon, wordmark, typography, colours, product UI, website, and motion feel related.
6. **Human specificity:** one deliberate imperfection or friendly cue prevents the identity from feeling like generic AI software.
7. **Restraint:** the interface remains quiet; the expressive colour belongs primarily to the icon, focus state, selection frame, and key brand moments.

Apple’s current Icon Composer supports layered artwork, appearance modes, edge highlights, refraction, translucency, and shadows from one source design.[1] Apple also provides official templates, platform UI kits, SF Pro, and SF Symbols as production resources.[2] The implication is to design a clean layered source mark first and use glass/material effects as finishing, not as the concept itself.

A useful counterexample to generic SaaS branding is Granola’s redesign: the team explicitly wanted a calm but energetic presence, retained one recognisable colour system, and introduced controlled human imperfection through its mark and typography.[3] The principle worth borrowing is **humanity through one specific design decision**, not the visual style itself.

## Brand translation

| Brand requirement | Visual consequence |
|---|---|
| Local and private | Contained composition; no cloud, network, or surveillance imagery |
| Open source | Clear geometry that can be explained, reproduced, and published as vectors |
| Natural voice | Soft rhythm and organic curvature rather than technical equaliser bars |
| Native macOS utility | Compact silhouette, layered depth, excellent small-size rendering |
| Calm and competent | Dark neutral foundation, generous spacing, limited chroma |
| Respectful and friendly | Subtle expression, rounded terminals, no childish mascot styling |
| Not a VoiceOver replacement | Avoid an eye, accessibility-person glyph, or “whole screen” metaphor as the main mark |

## Direction A — Frame Friend (recommended)

### Core idea

Four selection-corner fragments form a quiet face. Two small dots suggest attentive eyes; a single shallow wave suggests both a smile and spoken audio. The face is discovered rather than announced.

### Why it fits

- The outer form comes directly from the region-selection gesture.
- The wave connects selection to listening without adding a second full symbol.
- The restrained face creates sympathy at Dock size.
- The composition describes a focused utility, not a full screenreader.

### App icon

- Deep ink rounded-square base.
- Raised seafoam selection-corner layer.
- Warm-white facial details.
- Very subtle top highlight and bottom shadow.
- Dark, light, and tinted variants should preserve the same silhouette.

### Palette

- **Local Ink:** `#0B1724`
- **Voice Mint:** `#55E0BE`
- **Mint Light:** `#B8F7E7`
- **Warm Paper:** `#F7F4ED`
- **Optional attention accent:** `#FF766B`

### Typography

- Product UI: macOS system font / SF Pro.
- Website and brand text: Geist Sans or Instrument Sans as a shortlist.
- Wordmark: customised sans serif with a softly opened `O` and slightly rounded `R` terminal; avoid a gimmicky all-lowercase treatment unless name testing supports it.

### Risk and mitigation

A visible smile can look childish. Keep the expression nearly neutral, use no cheeks, eyelashes, or cartoon outline, and let the smallest variant reduce to frame plus wave.

## Direction B — Open Signal

### Core idea

An open circular `O` is interrupted by a single voice ripple. The opening doubles as an outward path: visible text becomes sound while remaining contained on the Mac.

### Why it fits

- Most timeless and scalable option.
- Works especially well as a monochrome menu-bar glyph.
- Connects naturally to the project name without spelling out `OSR`.
- Feels professional and infrastructure-like.

### Palette

- **Night:** `#101321`
- **Signal Blue:** `#4B6FFF`
- **Clear Cyan:** `#62D8FF`
- **Cloudless White:** `#F8FAFF`
- **Slate:** `#687086`

### Typography

Geist Sans or SF Pro Display, medium weight, with compact but not tight tracking.

### Risk and mitigation

A ring plus wave can become generic audio branding. The interruption angle and inner negative space must be distinctive and derived from the exact selection-frame geometry used in the product.

## Direction C — Soft Portal

### Core idea

A text line passes through a translucent local “window” and emerges as a soft wave. Two offset planes create a premium macOS material effect.

### Why it fits

- Expresses the entire transformation from screen text to voice.
- Offers the richest motion language for a landing page and onboarding.
- Can look exceptionally polished in Icon Composer.

### Palette

- **Midnight Violet:** `#171329`
- **Electric Iris:** `#8B7CFF`
- **Aqua:** `#60E2D0`
- **Lavender Mist:** `#E9E5FF`
- **Near White:** `#FAF9FC`

### Risk and mitigation

This direction is the most trend-dependent and can resemble generic AI products. Keep the base symbol flat and unmistakable before adding translucency; do not use sparkles, nebulae, or excessive gradients.

## Direction D — Reading Buddy

### Core idea

Three short text lines form a compact page-like glyph. Two endpoints behave like eyes, while the bottom line curves very slightly into a listening smile.

### Why it fits

- Most immediately approachable.
- Clearly connected to reading and text.
- Friendly for education, neurodiversity, and everyday productivity contexts without making medical claims.

### Palette

- **Warm Charcoal:** `#24221F`
- **Living Coral:** `#FF786A`
- **Apricot:** `#FFC58E`
- **Cream:** `#FFF7EB`
- **Soft Brown:** `#7A6558`

### Risk and mitigation

It can drift toward a children’s reading app. Use geometric proportions, a restrained expression, and editorial typography rather than illustrative mascot styling.

## Direction E — Local Lens

### Core idea

A single rounded selection bracket wraps around one organic sound curve. The negative space implies an ear without literally drawing one.

### Why it fits

- Strong focus on local containment and attentive listening.
- Calm, accessibility-aware, and credible.
- Works in one colour and at very small sizes.

### Palette

- **Forest Ink:** `#10201E`
- **Civic Green:** `#2DBB8A`
- **Soft Lime:** `#B8EC98`
- **Mineral:** `#DDE7E3`
- **Canvas:** `#F5F7F3`

### Risk and mitigation

An ear-like shape can make the product appear medical or hearing-specific. Keep it abstract and pair public messaging with “screen-to-speech utility,” not “hearing assistance.”

## Recommended system

### Logo architecture

Produce three related assets, not one universal file:

1. **App icon:** layered macOS object with controlled depth.
2. **Brand mark:** flat one- or two-colour SVG for GitHub, website, README, and press use.
3. **Wordmark:** symbol plus `OpenScreenReader`; never shrink the full wordmark into the menu bar or favicon.

### Type system

- **In-app UI:** SF Pro through the native macOS system APIs.
- **Marketing headings:** Geist Sans or Instrument Sans, pending final licensing and rendering checks.
- **Body copy and docs:** Inter or the system stack.
- **Technical labels/code:** Geist Mono or SF Mono.

Avoid ultra-light weights, narrow futuristic fonts, and monospaced body copy. “Modern” should come from spacing, hierarchy, and precision rather than novelty letterforms.

### Shape language

- Corner radius: friendly but not pill-like.
- Stroke endings: rounded or subtly tapered.
- Product selection frame: use the same corner geometry as the logo.
- Sound motion: one soft pulse or travelling wave; never a permanently animated equaliser.
- Illustration: close crops of real macOS UI and selection interactions, with private content replaced by explicit demo text.

### Product and repository usage

- **macOS Dock:** full layered icon.
- **Menu bar:** single-colour micro-glyph derived from the mark; no face details smaller than their tested threshold.
- **Selection overlay:** Voice Mint or Signal Blue at accessible contrast, with a neutral translucent fill.
- **GitHub avatar:** flat mark on a solid background with extra optical padding.
- **README:** horizontal lockup plus one product screenshot; avoid a large marketing hero inside technical documentation.
- **Landing page:** quiet near-white or near-black canvas, one accent colour, short product demonstration, and direct privacy statements.
- **Social preview:** mark, product name, and the claim “Select any text. Hear it naturally. Keep it local.”

## Evaluation gates before choosing

Each finalist should pass all of these tests:

- Recognisable at `16`, `20`, `32`, `64`, and `128` px.
- Works in monochrome.
- Works on light and dark backgrounds.
- Reads as selection/listening without a paragraph of explanation.
- Does not resemble an existing major app when shown without the wordmark.
- Does not imply cloud upload, surveillance, or a complete screenreader.
- Has a practical menu-bar derivative.
- Can be rebuilt as clean vectors and as Icon Composer layers.
- Meets contrast and reduced-transparency expectations in the product UI.

## Proposed next decision

Select one of these routes:

- **A — Frame Friend:** best balance of product specificity, warmth, and memorability.
- **B — Open Signal:** safest premium/minimal direction.
- **A/B hybrid:** Frame Friend for the app icon, with its face removed for the corporate mark and menu-bar glyph.

The A/B hybrid is the recommended path: it preserves the sympathetic Dock presence the user wants while keeping technical and repository contexts calm and professional.

## Sources

[1] https://developer.apple.com/icon-composer — Icon Composer
[2] https://developer.apple.com/design/resources — Apple Design Resources
[3] https://www.granola.ai/blog/a-new-look-for-granola — Granola: Meet the new look
