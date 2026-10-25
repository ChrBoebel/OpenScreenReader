# ADR 0007: GCC runtime libraries and the written source offer

- Status: accepted
- Date: 2026-10-24
- Decision: project maintainer.

## Context

The dictation runtime installs SciPy from its hash-pinned macOS wheels (1.18.1 on Apple
Silicon, 1.17.1 on Intel). Those wheels vendor three GCC 13.4.0 runtime libraries in
`scipy/.dylibs/`. SciPy built them with Homebrew `gcc@13`:

- `libgfortran.5.dylib` and `libgcc_s.1.1.dylib`: GPL-3.0-or-later WITH GCC-exception-3.1;
- `libquadmath.0.dylib`: LGPL-2.1-or-later.

`AGENTS.md` requires an explicit project-level licensing decision before GPL code is
integrated.

The obligations that apply when these libraries are distributed:

- LGPL-2.1 §6 requires that users can replace the library. It also requires the source to be
  provided in one of the ways §6 lists, for example with a written offer valid for at least
  three years at no more than the cost of distribution (§6(c)).
- For the GCC libraries, the conservative reading is GPL-3.0 §6(b): a written offer to any
  third party.
- MPL-2.0 §3.2(a) requires telling recipients how to obtain the source code form of Eigen and
  tqdm. Eigen is compiled into ONNX Runtime; tqdm is a Python package in the dictation runtime.

The previous release flow (PR #25) put every source archive inside the app. On Apple Silicon
that was about 94 MB, of which the GCC 13.4.0 tarball was 88.5 MB. Every download and every
full Sparkle update carried those archives.

## Decision

1. **Bundling accepted.** Saywing may ship `libgfortran`, `libgcc_s` and `libquadmath` from
   SciPy's wheels, with these conditions:
   - They stay unmodified, separate, replaceable dynamic libraries loaded at run time.
   - Nothing links them statically.
   - No Saywing code links them.

   `scripts/bundle_notices.py` enforces this. It fails on an undeclared or missing GNU
   runtime library, on a static archive, and on a library that is not a Mach-O dylib. This
   decision covers only these three libraries. Any other GPL or LGPL code still needs its own
   decision.
2. **No source archives in the app.** The app ships a written offer and exact pointers
   instead:
   - `Contents/Resources/CorrespondingSource/sources.json` gives every source file with its
     upstream URL, size, SHA-256, component and license.
   - `CorrespondingSource/README.md` contains the offer and the tested libquadmath
     replacement and relinking procedure.
   - `THIRD-PARTY-NOTICES.html` repeats the offer and the pointers.

   The offer:
   - It is valid for at least three years from the date on which the maintainers
     distributed the respective build. If the maintainers offer updates or support for that
     build for longer, it stays valid for that time too.
   - It is made to any third party.
   - It is fulfilled free of charge as a download, or on request on a physical medium for no
     more than the cost of physically performing the distribution.
   - Requests go through the repository issue tracker, or through the contact on the
     maintainer's GitHub profile. The offer names no personal e-mail address and no postal
     address.

   The license texts stay in the app: GPL-3.0, the GCC Runtime Library Exception, LGPL-2.1
   and the MPL-2.0 texts. `bundle_notices.py` fails if a source archive is inside the app, if
   a pointer lacks an HTTPS URL, size, SHA-256 or license, or if a copyleft record's license
   text is not shipped as a notice.
3. **The project keeps the sources.** Before any release file is uploaded, the `publish` job
   (`scripts/publish-release.py`) archives every source file that the signed app points to.
   - `release-result.json` carries the app's `sources.json`.
   - The job verifies that list against the repository.
   - It reuses files that are already archived. It downloads missing files, checks size and
     SHA-256, and stores them with conditional, immutable writes.

   Storage layout, in the existing private release bucket:
   - files: `<storage prefix>/corresponding-source/sha256/<sha256>/<file>`;
   - per-build manifest: `<storage prefix>/corresponding-source/builds/<build>.json`.

   No public website route serves this prefix. The objects are kept for at least three years
   after the respective build was last distributed. No lifecycle rule may expire them.

## Consequences

- The app is about 94 MB (90 MiB) smaller. On the Apple Silicon stand-in app,
  `CorrespondingSource/` shrank from 91,972 KiB to 16 KiB.
- The maintainers commit to answering source requests for the offer period. They must keep
  the archived objects and must not move the contact without updating the offer text.
- Forks that distribute their own builds make their own offer. They also need their own
  archive and contact.
- The first publication after a source pin changes needs the upstream hosts to be
  reachable. If they are not, publication stops before anything is uploaded.
- Builds published before this decision (the 2026-10-15 betas) were made with an earlier
  runtime. This archive does not cover them; see the addendum below.
- This ADR is not legal advice, and it does not close the license review. That review stays
  open in the release approvals (see [ADR 0003](0003-bundled-default-model.md)).

## Addendum 2026-10-25: the 2026-10-15 beta builds

The betas 0.1.17 (build 117) for Apple Silicon and Intel were published on 2026-10-15,
before this decision. The served DMGs were checked on 2026-10-25:

- Apple Silicon: `Saywing-0.1.17-117.dmg`, 1,407,098,966 bytes, SHA-256
  `7da384ef685368a86430459988ff430ce142179af8d944d44a806ef193dbe743` (equal to the served
  `latest.json`); code seal valid. It contains SciPy 1.17.1 with `libquadmath.0`,
  `libgfortran.5` and `libgcc_s.1.1` in `scipy/.dylibs/`, ONNX Runtime 1.23.2, and 20 source
  records in `CorrespondingSource/`. No file name or text file contains `artifact_tool` or
  `@oai/`, and there is no `node_modules`: the prototype runtime of the private builds 1–5
  is not in this beta.
- Intel: `x86_64/Saywing-0.1.17-117.dmg`, 1,125,227,296 bytes, SHA-256
  `d23157c58825da6ca6db0acc8586da5ddd5e6f57ec468fc8e4781eeb274e99e2` (equal to the served
  `latest.json`); code seal valid. Same findings: SciPy 1.17.1 with the same three GNU
  libraries, ONNX Runtime 1.23.2, 20 source records, no `artifact_tool`, `@oai` or
  `node_modules`.
- Neither DMG has the `Licenses` folder or `SUPERTONIC-MODEL-TERMS.md`; inside the app they
  carry only the Open RAIL-M license text. That gap belongs to the model-terms review
  ([ADR 0003](0003-bundled-default-model.md)).

What they lacked: a source, offer or pointer for SciPy 1.17.1's GNU runtime libraries
(`libquadmath`, `libgfortran`, `libgcc_s`) and for Eigen, which is compiled into ONNX
Runtime 1.23.2. Their license texts were shipped. The sources of the other copyleft
components (libsndfile and its codecs, autocommand, certifi, tqdm and the listed Rust
crates) were inside the app.

Decision: this offer is extended to those builds.

- [`docs/licenses/beta-0.1.17-corresponding-source.md`](../licenses/beta-0.1.17-corresponding-source.md)
  lists the four source files with upstream URL, size and SHA-256 (all re-verified on
  2026-10-25) and the written offer for at least three years after the betas were last
  distributed.
- The maintainer archives these four files under
  `<storage prefix>/corresponding-source/builds/117.json` like any published build, and
  links the notice from the website download page while the betas stay online. Both steps
  happen outside the repository.
- The betas are replaced by a clean build from the current pipeline once the license review
  closes.

Open for the legal review: whether a retroactive offer is sufficient for LGPL-2.1, whose
paragraph 8 ends rights without a cure period, and whether GPL-3.0 paragraph 6(d)
(equivalent access from the same place) rather than an offer alone applies to downloads.
Both questions also apply to the offer for future builds above.

## References

- `docs/licenses/CorrespondingSource-README.md`: the offer and the replacement and relinking
  procedure, tested on 2026-10-24.
- `docs/licenses/native-corresponding-sources.json`: the source records.
- `scripts/bundle_notices.py`, `scripts/publish-release.py`,
  [docs/release-and-updates.md](../release-and-updates.md).
