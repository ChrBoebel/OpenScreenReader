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
  runtime. This archive does not cover them. Any copyleft libraries they contained need a
  separate check.
- This ADR is not legal advice, and it does not close the license review. That review stays
  open in the release approvals (see [ADR 0003](0003-bundled-default-model.md)).

## References

- `docs/licenses/CorrespondingSource-README.md`: the offer and the replacement and relinking
  procedure, tested on 2026-10-24.
- `docs/licenses/native-corresponding-sources.json`: the source records.
- `scripts/bundle_notices.py`, `scripts/publish-release.py`,
  [docs/release-and-updates.md](../release-and-updates.md).
