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
  - `libquadmath.0.dylib`: GNU Lesser General Public License 2.1 or later,
    distributed under the GNU Lesser General Public License 3 (see below);
  - `libgfortran.5.dylib` and `libgcc_s.1.1.dylib`: GNU General Public License 3
    or later with the GCC Runtime Library Exception 3.1.
- Eigen, compiled into ONNX Runtime 1.23.2 (`libonnxruntime.1.23.2.dylib`):
  Mozilla Public License 2.0.

The license texts are inside the app (`Contents/Resources/Licenses`,
`THIRD-PARTY-NOTICES.html`). Sources for the other copyleft components of these
builds (libsndfile and its codecs, autocommand, certifi, tqdm and the listed
Rust crates) are already inside the app in `Contents/Resources/CorrespondingSource`.

## Corresponding source

The corresponding source is available here. Each file is publicly downloadable,
without an account and free of charge, from the Saywing download server, the same
place that serves the beta DMGs. The upstream address is a second source for the
same bytes.

| File | Bytes | SHA-256 | License |
|---|---:|---|---|
| `gcc-13.4.0.tar.xz` | 88,530,720 | `9c4ce6dbb040568fdc545588ac03c5cbc95a8dbf0c7aa490170843afb59ca8f5` | LGPL-2.1-or-later, distributed under LGPL-3.0 (libquadmath); GPL-3.0-or-later WITH GCC-exception-3.1 (libgfortran, libgcc_s) |
| `homebrew-gcc-13.4.0.diff` | 590,233 | `60b22ae7f5f78b41e12c51d8c6e99ba933a7e124454fe8cdbff7200505167949` | GPL-3.0-or-later (GCC source patch) |
| `homebrew-gcc@13-97eefa4d.rb` | 9,826 | `125f8b253d9582949359a6b30eb366fbd1f34599545731c972a29904391400f5` | BSD-2-Clause (build-control file: the Homebrew gcc@13 formula in effect when the SciPy 1.17.1 wheels were built) |
| `eigen-1d8b82b0740839c0de7f1242a3585e3390ff5f33.zip` | 4,075,744 | `6a60d76351f97132669daeeb721d6bf14b008101883ad2d687a3201c5c461eb0` | MPL-2.0 |

Download addresses:

| File | Saywing download server | Upstream |
|---|---|---|
| `gcc-13.4.0.tar.xz` | [download](https://www.christopherboebel.com/downloads/saywing/corresponding-source/sha256/9c4ce6dbb040568fdc545588ac03c5cbc95a8dbf0c7aa490170843afb59ca8f5/gcc-13.4.0.tar.xz) | [ftp.gnu.org](https://ftp.gnu.org/gnu/gcc/gcc-13.4.0/gcc-13.4.0.tar.xz) |
| `homebrew-gcc-13.4.0.diff` | [download](https://www.christopherboebel.com/downloads/saywing/corresponding-source/sha256/60b22ae7f5f78b41e12c51d8c6e99ba933a7e124454fe8cdbff7200505167949/homebrew-gcc-13.4.0.diff) | [GitHub](https://raw.githubusercontent.com/Homebrew/homebrew-core/1cf441a09f572566b1b7c4695a4d169d1177248a/Patches/gcc/gcc-13.4.0.diff) |
| `homebrew-gcc@13-97eefa4d.rb` | [download](https://www.christopherboebel.com/downloads/saywing/corresponding-source/sha256/125f8b253d9582949359a6b30eb366fbd1f34599545731c972a29904391400f5/homebrew-gcc@13-97eefa4d.rb) | [GitHub](https://raw.githubusercontent.com/Homebrew/homebrew-core/97eefa4d24602abaca62e3b6dd11c1d46dfb4be2/Formula/g/gcc@13.rb) |
| `eigen-1d8b82b0740839c0de7f1242a3585e3390ff5f33.zip` | [download](https://www.christopherboebel.com/downloads/saywing/corresponding-source/sha256/6a60d76351f97132669daeeb721d6bf14b008101883ad2d687a3201c5c461eb0/eigen-1d8b82b0740839c0de7f1242a3585e3390ff5f33.zip) | [GitHub](https://github.com/eigen-mirror/eigen/archive/1d8b82b0740839c0de7f1242a3585e3390ff5f33/eigen-1d8b82b0740839c0de7f1242a3585e3390ff5f33.zip) |

These addresses cover both the Apple Silicon and the Intel build.

These are the same records as in
[`native-corresponding-sources.json`](native-corresponding-sources.json). Verify
a download with `shasum -a 256 <file>`.

## libquadmath license

libquadmath is licensed under the GNU LGPL version 2.1 or (at your option) any
later version; the Saywing maintainers distribute it under the GNU LGPL version 3
(which incorporates the GNU GPL version 3), effective for all Saywing builds
including 0.1.17. The texts are
[`GCC-13.4.0/COPYING3.LIB`](GCC-13.4.0/COPYING3.LIB) (LGPL 3, unchanged from the
GCC 13.4.0 source archive) and [`GCC-13.4.0/COPYING3`](GCC-13.4.0/COPYING3)
(GPL 3).

## Written offer

In addition, the written offer remains: for at least three years after we last
distributed these builds, the Saywing maintainers will give any third party, on
request, a complete machine-readable copy of the corresponding source listed
above: free of charge as a download, or on a physical medium for no more than
the cost of physically performing that distribution. Ask through the
[repository issue tracker](https://github.com/ChrBoebel/saywing/issues) and name
version 0.1.17, build 117 and your Mac architecture.

The replacement and relinking procedure for `libquadmath` is described in
[`CorrespondingSource-README.md`](CorrespondingSource-README.md).
