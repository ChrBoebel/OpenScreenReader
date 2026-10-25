# Source code for Saywing 0.1.17 (build 117), published 15 October 2026

The Saywing 0.1.17 beta builds (build 117, Apple Silicon and Intel) were
published on 15 October 2026, before the written source offer of
[ADR 0007](../decisions/0007-gcc-runtime-libraries.md) existed. They did not
include this notice when they were first published. We publish it now to
complete their license information.

## Components

These beta builds contain:

- GNU runtime libraries shipped unmodified as separate dynamic libraries inside
  the SciPy 1.17.1 wheel (`scipy/.dylibs/`):
  - `libquadmath.0.dylib`: GNU Lesser General Public License 2.1 or later;
  - `libgfortran.5.dylib` and `libgcc_s.1.1.dylib`: GNU General Public License 3
    or later with the GCC Runtime Library Exception 3.1.
- Eigen, compiled into ONNX Runtime 1.23.2 (`libonnxruntime.1.23.2.dylib`):
  Mozilla Public License 2.0.

The license texts are inside the app (`Contents/Resources/Licenses`,
`THIRD-PARTY-NOTICES.html`). Sources for the other copyleft components of these
builds (libsndfile and its codecs, autocommand, certifi, tqdm and the listed
Rust crates) are already inside the app in `Contents/Resources/CorrespondingSource`.

## Corresponding source

| File | Bytes | SHA-256 | License |
|---|---:|---|---|
| [`gcc-13.4.0.tar.xz`](https://ftp.gnu.org/gnu/gcc/gcc-13.4.0/gcc-13.4.0.tar.xz) | 88,530,720 | `9c4ce6dbb040568fdc545588ac03c5cbc95a8dbf0c7aa490170843afb59ca8f5` | LGPL-2.1-or-later (libquadmath); GPL-3.0-or-later WITH GCC-exception-3.1 (libgfortran, libgcc_s) |
| [`homebrew-gcc-13.4.0.diff`](https://raw.githubusercontent.com/Homebrew/homebrew-core/1cf441a09f572566b1b7c4695a4d169d1177248a/Patches/gcc/gcc-13.4.0.diff) | 590,233 | `60b22ae7f5f78b41e12c51d8c6e99ba933a7e124454fe8cdbff7200505167949` | GPL-3.0-or-later (GCC source patch) |
| [`homebrew-gcc@13-97eefa4d.rb`](https://raw.githubusercontent.com/Homebrew/homebrew-core/97eefa4d24602abaca62e3b6dd11c1d46dfb4be2/Formula/g/gcc@13.rb) | 9,826 | `125f8b253d9582949359a6b30eb366fbd1f34599545731c972a29904391400f5` | BSD-2-Clause (build-control file: the Homebrew gcc@13 formula in effect when the SciPy 1.17.1 wheels were built) |
| [`eigen-1d8b82b0740839c0de7f1242a3585e3390ff5f33.zip`](https://github.com/eigen-mirror/eigen/archive/1d8b82b0740839c0de7f1242a3585e3390ff5f33/eigen-1d8b82b0740839c0de7f1242a3585e3390ff5f33.zip) | 4,075,744 | `6a60d76351f97132669daeeb721d6bf14b008101883ad2d687a3201c5c461eb0` | MPL-2.0 |

These are the same records as in
[`native-corresponding-sources.json`](native-corresponding-sources.json). Verify
a download with `shasum -a 256 <file>`.

## Written offer

For at least three years after we last distributed these builds, the Saywing
maintainers will give any third party, on request, a complete machine-readable
copy of the corresponding source listed above: free of charge as a download, or
on a physical medium for no more than the cost of physically performing that
distribution. Ask through the
[repository issue tracker](https://github.com/ChrBoebel/saywing/issues) and name
version 0.1.17, build 117 and your Mac architecture.

The replacement and relinking procedure for `libquadmath` is described in
[`CorrespondingSource-README.md`](CorrespondingSource-README.md).
