# Included source and local modifications

The CorrespondingSource folder contains the original archives listed in sources.json.
Each record gives its source URL, exact size and SHA-256. availability.json reports
how many are included in this copy; public releases are built only when all are.
The archives are distributed with the application, so no network connection is
needed to inspect them. Extract them into a separate working directory, not into
the installed app. The license texts are in the Licenses folder and in the offline
license index (THIRD-PARTY-NOTICES.html).

## GNU runtime libraries (LGPL-2.1 / GPL-3.0 with the GCC Runtime Library Exception)

SciPy ships three GCC 13.4.0 runtime libraries as separate dynamic libraries, unmodified
from its published wheels:

- `libquadmath.0.dylib`: GNU LGPL 2.1 or later (Licenses/GCC-13.4.0/libquadmath/COPYING.LIB);
- `libgfortran.5.dylib` and `libgcc_s.1.1.dylib`: GNU GPL 3 or later with the GCC Runtime
  Library Exception 3.1 (Licenses/GCC-13.4.0/COPYING3 and COPYING.RUNTIME).

They are in `Dictation/Python/lib/python3.12/site-packages/scipy/.dylibs/` and are loaded
at run time through `@loader_path` (libgfortran loads libquadmath and libgcc_s; SciPy's
ODR module loads libgfortran). No Saywing code and no other library links them statically.

SciPy built them with Homebrew's gcc@13 13.4.0 (recorded as the Fortran compiler in
`scipy/__config__.py`). Their complete corresponding source is:

- `gcc-13.4.0.tar.xz`: the GNU release archive (libquadmath/, libgfortran/, libgcc/);
- `homebrew-gcc-13.4.0.diff`: the Darwin and Apple Silicon patch Homebrew applies before
  building (from https://github.com/iains/gcc-13-branch). It applies to the archive
  unchanged with `patch -p1`;
- `homebrew-gcc@13-97eefa4d.rb` and `homebrew-gcc@13-cd5d1cfa.rb`: the Homebrew build
  recipes in effect before the two SciPy builds. They differ only in packaging details,
  not in source or patch. The exact Homebrew bottle that SciPy's build machine used is not
  recorded in the wheels.

Saywing imposes no additional restriction on modifying these libraries for your own use,
or on reverse engineering to debug such modifications. Their licenses continue to apply
independently of Saywing's Apache-2.0 license and of Supertonic's model terms.

### Tested libquadmath replacement (Apple Silicon)

This was tested on 2026-10-24 with Homebrew GCC 16.1.0 as the compiler and the included
GCC 13.4.0 source plus the Homebrew patch. No Saywing signing key is needed.

1. Verify `gcc-13.4.0.tar.xz` and `homebrew-gcc-13.4.0.diff` against sources.json, extract
   the archive in a working directory and run `patch -p1 < homebrew-gcc-13.4.0.diff` in
   `gcc-13.4.0`.
2. Build only libquadmath with a GCC that supports `__float128` on your Mac (Apple clang
   does not):

```sh
mkdir qm-build && cd qm-build
export MACOSX_DEPLOYMENT_TARGET=14.0
../gcc-13.4.0/libquadmath/configure --host=aarch64-apple-darwin24 --build=aarch64-apple-darwin24 \
  --disable-multilib --enable-shared --disable-static CC=gcc-16
make
# libtool's piecewise link drops private symbols on macOS; link the built objects directly:
gcc-16 -dynamiclib -nodefaultrpaths -o libquadmath.0.dylib math/.libs/*.o printf/.libs/*.o strtod/.libs/*.o \
  -install_name @rpath/libquadmath.0.dylib -compatibility_version 1 -current_version 1.0 -lm
```

   The result exported the same 107 symbols as the shipped library.
3. In a copy of the runtime (never in the installed app), replace
   `lib/python3.12/site-packages/scipy/.dylibs/libquadmath.0.dylib`, restore its install
   name with `install_name_tool -id /DLC/scipy/.dylibs/libquadmath.0.dylib` and sign it
   ad hoc with `codesign --force --sign - PATH`.
4. With `DYLD_PRINT_LIBRARIES=1`, the runtime's `python3 -I -B` imported `scipy.odr`,
   which loaded the replaced library (a different Mach-O UUID from the original), and an
   orthogonal-distance regression fit returned the expected coefficients.

To use a replaced library in a complete app copy:

5. Copy Saywing.app to a new directory; keep the original intact. On APFS,
   `/bin/cp -c -R Saywing.app /new/path/Saywing-local.app` avoids duplicating model data.
6. Replace the library as in step 3. Re-sign it and
   `Contents/Resources/Dictation/Python/bin/python3.12` with
   `codesign --force --sign - --options 0x0 PATH`. Without hardened runtime, this local
   interpreter can load the ad hoc signed library.
7. In `Contents/Resources/Dictation/installation-receipt.json`, replace only the entries of
   the two changed files with their new SHA-256. Verify every other entry against the
   unchanged file; never repair an unexplained mismatch.
8. Export the original entitlements with
   `codesign -d --entitlements :- /path/to/Saywing.app > local-entitlements.plist`, re-seal
   with `codesign --force --sign - --options 0x0 --entitlements local-entitlements.plist
   /new/path/Saywing-local.app` and check `codesign --verify --deep --strict`.
   This is a locally signed development copy, not a notarized distribution.

Steps 5 to 8 are the receipt and re-seal procedure that was exercised with a complete app
copy in October 2026 for an earlier replaceable library. The libquadmath test above ran
against a copy of the runtime, not against a re-sealed app.

## Other included sources

- `eigen-1d8b82b0740839c0de7f1242a3585e3390ff5f33.zip`: Eigen (MPL-2.0), compiled into
  `libonnxruntime.1.23.2.dylib` of the speech runtime. This is the exact archive that ONNX
  Runtime 1.23.2 pins in `cmake/deps.txt`.
- `tqdm-4.70.1.tar.gz`: tqdm, which contains MPL-2.0 files.
- `tokenizers-0.23.3.tar.gz`, `safetensors-0.8.0.tar.gz`, `tiktoken-0.14.0.tar.gz`: the
  original sources of the bundled Rust extensions. Their dependency locks, observed crate
  versions and a rebuild recipe are in Licenses/RustBuild. Some lock entries are build-only
  or target-specific; their notices are included conservatively.

A modified copy no longer carries the original Developer ID seal. Changing a library also
changes the runtime receipt; a locally modified build must refresh its receipt and sign
its changed code and the app. This protects integrity; it does not restrict the
modification rights the licenses grant.
