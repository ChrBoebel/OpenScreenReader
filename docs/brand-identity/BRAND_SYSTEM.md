# Saywing brand system

Current identity, approved on 2026-10-14: direction **"Text to Voice"**. Horizontal text lines turn into vertical speech bars. The palette is Ink Navy, Paper, Petrol and Apricot.

## Name and language

| | English | German |
|---|---|---|
| Name | Saywing | Saywing |
| Descriptor | Read aloud & dictate on your Mac. | Vorlesen & Diktieren für macOS. |
| Tagline | Hear text. Write with your voice. | Text hören. Mit der Stimme schreiben. |
| Action 1 | Read aloud: select a screen region, then listen. | Vorlesen: Bildschirmbereich wählen, zuhören. |
| Action 2 | Dictate: speak, then insert the text. | Diktieren: sprechen, Text einfügen. |

Saywing is one native menu bar app and one brand with two explicitly chosen actions. Always write **Saywing**, never "SayWing". On first contact, show the name together with its descriptor.

Privacy is a product property, so describe it accurately:

- There is no cloud OCR, TTS or ASR, no account, no telemetry and no persistent content history.
- Reading never writes to the clipboard. Dictation uses the clipboard briefly to paste, and newer copies take precedence over the restore.
- Saywing never records on launch.
- Do not promise compatibility with every text field, or release readiness the project has not verified.

## Mark and assets

- [Flat mark](assets/saywing-logo.png): the text-to-voice mark in solid Ink Navy on a transparent background.
- [App icon](assets/saywing-app-icon.png): a Paper-colored mark on an Ink Navy icon surface, with the right speech bar in Petrol.
- [Menu bar template](assets/saywing-menubar.png): a monochrome alpha template of the same mark.
- [Machine-readable tokens](assets/brand-tokens.json).

The mark shows two short horizontal text lines above a longer bottom line. The bottom line bends softly upward on the right into a short speech bar, next to one tall and one medium vertical bar. Strokes have even weight and round ends, with open spaces between them. The mark has no owl, no microphone and no ornament. It may be used in one color; in the app icon, only the right bar is accented in Petrol. Speaker and microphone symbols still explain the individual actions, always together with text.

`sh scripts/export-app-icon.sh` generates the app icon sizes and the 22 pt menu bar templates (1×, 2× and 3×) from these masters. The masters are transparent rasters, not vectors. Exact vector masters and an Icon Composer layer stack are planned improvements.

## Color and type

| Token | Value | Use |
|---|---|---|
| Ink Navy | `#172B3A` | Logo, wordmark and dark brand surfaces |
| Paper | `#F4F2EC` | Warm light background and inverse text |
| Petrol | `#266D79` | Right icon bar, controls on light surfaces |
| Apricot | `#E4B78F` | Sparing decorative accent; notices and errors on dark surfaces |
| Deep Navy | `#0E1D28` | Dark reading and dictation capsule |
| Pale Petrol | `#8BCAD1` | Accessible activity bars and controls on dark surfaces |
| Paper Light | `#DDEFEF` | Light capsule accents |

The last three colors are derived from the first four so that native controls stay legible. The color values are the binding UI tokens; the raster icons contain material gradients.

Computed contrast ratios:

| Pair | Ratio |
|---|---|
| Ink Navy on Paper | 13.00:1 |
| Petrol on Paper | 5.29:1 |
| Pale Petrol on Deep Navy | 9.36:1 |
| Pale Petrol on Ink Navy | 7.95:1 |
| Apricot on Deep Navy | 9.36:1 |
| Apricot on Paper | 1.64:1 |

Apricot on Paper is decorative only: never use it for text or as the only outline of a control. Never convey state by color alone. Over arbitrary screen content, no single frame color guarantees contrast, so dimming and selection geometry still matter.

Type: the app uses the native macOS system font, and no fonts are loaded externally. Keep clear space of at least one bar width around the visible mark. For small sizes, use the exported menu bar template.

## Native implementation

- The build product is **Saywing.app** with the executable **Saywing**.
- The bundle identifier, preference keys, the `Application Support/OpenScreenReader` directory, the Xcode project, the scheme and the Swift modules keep their technical OpenScreenReader names for compatibility.
- The menu bar shows a template glyph in the system-chosen light or dark color. Its tooltip and accessible name include the current state.
- The reading and dictation capsules share the Navy/Petrol palette, surface and motion rules, while each keeps its own actions and accessible descriptions. Apricot is reserved for notices and errors.

## Capsules

The capsules share these properties:

- **Material:** a Deep Navy gradient with a fine light Petrol edge and a muted shadow.
- **Height:** 28 pt.
- **Level meter:** nine rounded 2.5 pt bars with 3 pt spacing. They follow the actual playback or microphone level with time-based attack and decay, and lie flat in silence.
- **Waiting state:** while preparing or recognizing, only the brightness of flat dots moves.
- **Appearance:** a 140 ms fade with a critically damped scale from 96 to 100 percent. With Reduce Motion, only the fade remains and the meter is static. Reduce Transparency and Increase Contrast make the surface opaque.
- **No content:** a capsule never shows recognized or dictated text, and has no timer.

**Reading capsule:** 136 × 28 pt visible, inside a 136 × 44 pt interaction area.

- At rest it shows the waveform and Stop. On hover, the waveform crossfades to Pause/Resume and the options control. The capsule does not resize and Stop does not move.
- It docks at the bottom, left or right edge. Side positions use an upright vertical layout, and their popover opens toward the screen.
- The menu and VoiceOver provide every control without hover.

**Dictation capsule:** 120 × 28 pt.

- A small cross on the left discards the dictation. The level bars sit in the middle. A small square on the right, inside a softly lit circle, finishes recording and starts recognition and insertion.
- The two hit targets are separate, non-overlapping 32 × 44 pt areas.
- The capsule never takes focus from the target text field.
- Hands-free recording shows only on the finish control: it fills with Pale Petrol and latches once with a critically damped motion.

## Sound

Interface sounds come from a short wood-and-water family:

- **Dictation:** microphone on (C4), hands-free latched (G4) and microphone off (G3, muted, without water). Discarding is silent.
- **Character:** frequent sounds stay short, warm and plain. Water and room are reserved for completion.
- **Settings:** the sounds can be configured in Settings.

## Voice and tone

Calm, direct and concrete. Explain the action and its result. Do not promise unproven productivity gains, autonomous recording, automatic sending, universal compatibility, or invent user testimonials.

## Still to validate

- **Name comprehension** has not been tested with real participants.
- **Trademark and domain checks** have not been done: a trademark similarity review and the choice of a domain are still open. A preliminary search is not legal clearance.
