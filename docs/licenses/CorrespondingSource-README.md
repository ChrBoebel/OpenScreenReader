# Included source and local modifications

The CorrespondingSource folder contains the original archives listed in sources.json.
Each record includes its source URL, exact size and SHA-256. availability.json reports
how many are actually included. The archives are distributed with the application;
no network connection is needed to inspect them. Extract them into a separate working
directory, not into the installed app. The original license files remain with each
source and are also presented in the offline license index.

SoundFile loads libsndfile dynamically from
Dictation/Python/lib/python3.12/site-packages/_soundfile_data/libsndfile_arm64.dylib
in the ARM bundle. libsndfile itself includes the codec versions recorded in
sources.json. The three libsndfile-* build-control files are unchanged upstream
files. To reproduce their layout, rename libsndfile-mac_build.sh to mac_build.sh,
libsndfile-darwin.cmake to darwin.cmake, and keep all seven source archives beside
them. Read the script and each project's build instructions before building.
The original script downloads its inputs; use the included, hash-verified archives
for an offline adaptation. Its archive extraction commands have not been validated
on the current toolchain. A separate libsndfile 1.2.2 rebuild with external/MPEG codecs disabled was
validated in a complete local app copy: SoundFile loaded the changed library,
a WAV roundtrip and all twelve default-model dictation checks passed. This does
not certify exact reconstruction of the original all-codec binary.

The vendored autocommand 2.2.2 Python source is under
Dictation/Python/lib/python3.12/site-packages/setuptools/_vendor/autocommand.
Its six Python files match the included original source archive byte for byte.
The corresponding LGPLv3 and GPLv3 texts are in the license index. The certifi and
tqdm sources and potentially included MPL/CDDL Rust-crate sources are supplied too.
Some Cargo lock entries are build-only or target-specific; including their sources
and notices does not mean that all of them are linked into the macOS executable.

Saywing imposes no additional prohibition on modifying these libraries for your own
use or reverse engineering to debug such modifications. Their original licenses
continue to govern them independently of Saywing's Apache-2.0 source license and
Supertonic's model terms. A modified copy will no longer carry the original valid
Developer ID seal. Preserve an original copy and make changes in a development copy.
Changing a library also changes the runtime receipt; a locally modified build must
regenerate its receipt and sign its changed nested code and app. This is an integrity
mechanism, not a restriction on the modification rights granted by the licenses.
The project's release/signing scripts document these steps; the official signing
key is not required to build a locally signed development copy.

## Tested ARM library replacement procedure

This example deliberately disables optional codecs to make the replacement observable.
It was exercised on a complete build-8 app copy. It requires Xcode command-line tools,
CMake and Python 3; no original signing key is needed. The complete release license
review remains separate from this technical proof.

1. Copy Saywing.app to a new local development directory. Keep the original app intact.
   On APFS, `/bin/cp -c -R /path/to/Saywing.app /new/path/Saywing-local.app` avoids
   duplicating model storage. The destination must not already exist.
2. Verify the included libsndfile-1.2.2.tar.xz against sources.json and extract it
   outside the app. The tested CMake configuration, from that working directory, is:

```sh
cmake -S libsndfile-1.2.2 -B sndfile-build \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DBUILD_SHARED_LIBS=ON -DENABLE_EXTERNAL_LIBS=OFF -DENABLE_MPEG=OFF \
  -DBUILD_PROGRAMS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTING=OFF
cmake --build sndfile-build --parallel 4
```

3. In the development app only, replace
   Contents/Resources/Dictation/Python/lib/python3.12/site-packages/_soundfile_data/libsndfile_arm64.dylib
   with sndfile-build/libsndfile.1.0.37.dylib. Re-sign that library and
   Contents/Resources/Dictation/Python/bin/python3.12 using
   `codesign --force --sign - --options 0x0 PATH` for each file. Disabling hardened
   runtime on this local loader permits the modified ad-hoc library to load.
4. In Contents/Resources/Dictation/installation-receipt.json, replace only the two
   corresponding entries in `files` with SHA-256 hashes of the newly signed files.
   Verify every other receipt entry against the unchanged file; never repair an
   unexplained mismatch. The names are relative to the Dictation directory.
5. Export the original app entitlements to a local plist using
   `codesign -d --entitlements :- /path/to/original/Saywing.app > local-entitlements.plist`.
   Re-seal the development app with
   `codesign --force --sign - --options 0x0 --entitlements local-entitlements.plist /new/path/Saywing-local.app`.
   Verify using `codesign --verify --deep --strict /new/path/Saywing-local.app`.
   This is a locally signed development copy, not an Apple-notarized distribution.
6. Use its bundled Python with `-I -B` to import soundfile: version must remain
   1.2.2, while `FLAC` must be absent from `soundfile.available_formats()` for this
   deliberately changed build. The recorded test also encoded/decoded float WAV
   in memory, then exercised public German/English fixtures through the app's
   sandboxed Whisper Turbo worker (all 12 integration checks passed).

Both runtime receipts and the complete app seal passed. A launch with `--uitesting`
stayed alive for five seconds without microphone capture, hotkeys or update checks.
That launch does not constitute a GUI dictation or fresh-device permission test.
The original all-codec binary was not reproduced bit for bit.

