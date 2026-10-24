# Interpreter provenance: CPython 3.12.15, python-build-standalone 20261013

Checked 2026-10-24. The machine-readable record is
[`Runtime/Portable/python-provenance.json`](../../Runtime/Portable/python-provenance.json).
`python3 scripts/python_provenance.py --checkout <dir> --cache <dir>` re-runs every check
below. It needs network access to github.com while it runs, and it never executes anything it
downloads.

## Source

- **Upstream:** [astral-sh/python-build-standalone](https://github.com/astral-sh/python-build-standalone).
  Its build scripts are MPL-2.0 (`LICENSE`, blob `a612ad98`).
- **Release tag:** `20261013` is a lightweight tag. It points to commit
  **`9e40cba825ca0997a01cab9f60a0b15ffb976af2`**:
  - subject: "Add CPython 3.16 (#1336)";
  - committed 2026-10-14T00:50:25Z;
  - GitHub reports the signature as verified;
  - it is also the release's `target_commitish`.
- **CPython source:** `Python-3.12.15.tar.xz` from python.org, SHA-256 `c2c43219…fd5a`. The
  record holds the full hash, as declared in `pythonbuild/downloads.json`.

## Build recipe

The record lists the recipe files with their git blob SHAs at the commit. The files include
`build.py`, `cpython-unix/build.py`, `cpython-unix/build-cpython.sh`,
`cpython-unix/targets.yml`, `cpython-unix/extension-modules.yml` and
`pythonbuild/downloads.json`. They also include the CI matrix, the release workflow and
`src/release.rs`, which produces the `install_only` and `install_only_stripped` archives.

- **Build host:** both macOS targets are built on the aarch64 macOS CI runner.
  `pythonbuild/utils.py` rejects any other macOS host, and `ci-runners.yaml` has no Intel Mac.
- **x86_64 is cross-compiled.** The full archive confirms this: `--build=aarch64-apple-darwin
  --host=x86_64-apple-darwin … cross_compiling=yes`.
- **Options:** both archives use `pgo+lto` with the macOS 15.0 SDK. The deployment target is
  11.0 on arm64 and 10.15 on x86_64.
- **Stripping:** the release job runs on Ubuntu and makes the stripped archive from the
  install-only archive with `llvm-strip --strip-debug`. It uses `llvm-x86_64-linux`
  23.1.3+20261008.

## CPython patches

There are 69 `cpython-unix/patch-*.patch` files at the commit. **20 of them apply to CPython
3.12.15 on macOS.** We worked this out by reading each `patch -p1` condition in
`build-cpython.sh`. The record keeps each patch's blob SHA, its condition and the line of
`build-cpython.sh` that applies it.

- **Both architectures (19 patches):**
  - `apple-cross-3.12`
  - `cpython-configure-target-triple-musl-3.12`
  - `always-build-python-for-freeze`
  - `write-python-for-build-3.12`
  - `macos-link-extension-modules`
  - `ctypes-callproc`
  - `tkinter-3.12`
  - `ctypes-static-binary`
  - `pgo-print-statistics`
  - `pgo-file-pool`
  - `tkinter-tcl9-thread-detection`
  - `test-embed-prevent-segfault`
  - `cpython-redhat-cert-file`
  - `posixmodule-sys-syscall-header`
  - `posixmodule-syscall-fallback`
  - `python-configure-add-enable-static-libpython-for-interpreter`
  - `python-getpath-backport-3.12`
  - `python-getpath-library`
  - `getpath-use-base_executable-for-executable_dir`
- **x86_64 only (1 patch):** `dont-clear-runshared`. It applies only when cross-compiling.

Two facts in the build confirm this selection:

- Both builds' `CONFIG_ARGS` contain `--enable-static-libpython-for-interpreter`. This option
  exists only because of its patch.
- Only the x86_64 build shows `cross_compiling=yes`.

The build scripts also patch dependency sources inline:

- **libffi:** `build-libffi.sh` changes `src/tramp.c` to use `<limits.h>`. This applies to
  every target.
- **Tcl:** a macOS-only change to `tcl.pc`. Saywing removes Tcl.
- **OpenSSL:** a Linux-only patch that does not apply to these builds.

## Third-party sources

These versions are declared in `downloads.json` at the commit. The record has each URL, size
and SHA-256.

| Component | Version | In the interpreter |
| --- | --- | --- |
| OpenSSL | 3.5.9 | static (`_ssl`, `_hashlib`) |
| SQLite | 3.53.1.0 | static (`_sqlite3`) |
| libffi | 3.8.0 | static (`_ctypes`) |
| xz (liblzma) | 5.8.4 | static (`_lzma`) |
| bzip2 | 1.0.8 | static (`_bz2`) |
| mpdecimal | 4.0.0 | static (`_decimal`) |
| expat | 2.9.0 | static (`pyexpat`) |
| libuuid | 1.0.3 | static (`_uuid`) |
| Tcl/Tk | 9.0.4 | in the archive; removed by `scripts/build-python-runtime.py` |
| pip | 26.2.1 | in the archive; removed by `scripts/build-python-runtime.py` |

The build itself also uses autoconf 2.72, m4 1.4.19, pkgconf 3.0.3, setuptools 84.0.0, zstd
1.5.7 and LLVM 23.1.3. None of them is linked into CPython 3.12.

Some libraries come from macOS itself, not from upstream sources: zlib, libedit,
ncurses/panel, CoreFoundation and SystemConfiguration.

## Consistency of the stripped and full archives

For each architecture we checked these five points:

1. **Checksums.** The pinned stripped archive and the full archive
   (`…-pgo+lto-full.tar.zst`) both match the release's `SHA256SUMS` (SHA-256
   `6f1da4ab…3ebd`). The stripped archive also matches GitHub's asset digest.
2. **Metadata.** The full archive's `python/PYTHON.json` says `python_version` 3.12.15, the
   expected target triple and `build_options` `pgo+lto`. The stripped archive's
   `patchlevel.h` says 3.12.15.
3. **Build configuration.** `_sysconfigdata__darwin_darwin.py` is byte-identical in both
   archives. It contains the build's unique temporary directory (`/tmp/tmpzqwka42i` on arm64,
   `/tmp/tmp3ywem0la` on x86_64) and the same host and build triples.
4. **Files.**

   | | arm64 | x86_64 |
   | --- | --- | --- |
   | Files in the stripped archive | 1653 | 1650 |
   | Byte-identical with `python/install/` in the full archive | 1636 | 1633 |
   | Symlinks, all identical | 10 | 10 |
   | Mach-O binaries with the same `LC_UUID` and section contents | 11 | 11 |
   | Windows launcher stubs in pip with the same section contents | 6 | 6 |

   - The 11 Mach-O binaries per architecture include `python3.12` and
     `libpython3.12.dylib`. Their `__LINKEDIT` and `__DWARF` data, which debug stripping
     changes, are not compared.
   - The Windows launcher stubs are compared up to each section's virtual size.
   - Files that only the full archive has are exactly what `src/release.rs` drops: the test
     packages, the test extension modules and the static `libpython3.12.a`.
   - No difference is unexplained.
5. **Licenses.** Every license file that Saywing ships is byte-identical to the file of the
   same name in the full archive's `python/licenses/`:
   - `docs/licenses/Python-3.12.15/` for arm64 (14 files);
   - `docs/licenses/Python-3.12.15-Intel/` for x86_64 (19 files).

   The full archives of both architectures contain the same 19 files. These are also identical
   to the `LICENSE.*.txt` files at the repository root of the recorded commit.

So each pinned stripped archive and its full archive come from the same build.

## Findings to note

- The Intel notice directory ships all 19 upstream license files. Five of them are for
  components that the macOS build does not contain: Berkeley DB, libX11, libXau, libxcb and
  Tix. The arm64 directory ships only the 14 macOS-relevant files.
- The upstream `PYTHON.json` lists `LICENSE.zlib-ng.txt` for `zlib`, `binascii` and
  `_sqlite3`, but the full archive does not contain that file. On macOS, zlib is the system
  library, so neither zlib nor zlib-ng code is bundled.
- The `ncurses` and `libedit` license texts describe upstream builds. On macOS, the
  interpreter links the system libraries instead.

## Pin updates

`Tests/Release/test_python_provenance.py` fails if `Runtime/Portable/python.json` changes
without a matching record. `scripts/build-python-runtime.py` refuses to build in that case. It
writes the recorded commit and the full-archive hash into each runtime's
`runtime-provenance.json`.

A new pin needs all of the following:

- the new tag's commit;
- the recipe and patch blobs;
- a new reading of the patch conditions;
- the dependency list;
- the `scripts/python_provenance.py` check.
