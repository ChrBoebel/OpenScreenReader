#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd -P)
source_archive=${1:?pinned source archive required}
build_dir=${2:?build directory required}
arch=${3:?architecture required}
case "$arch" in arm64|x86_64) ;; *) exit 2;; esac
mkdir -p "$build_dir"
source_dir="$build_dir/verified-source"
python3 - "$repo_dir" "$source_archive" "$source_dir" <<'VERIFY'
import json, pathlib, sys, tarfile
repo, archive, output = map(pathlib.Path, sys.argv[1:])
sys.path.insert(0, str(repo / 'scripts'))
from portable_runtime import verify_file, safe_path, digest
pin = json.loads((repo / 'Runtime/Portable/whisper-cpp-source.json').read_text())
verify_file(archive, pin)
output.mkdir(exist_ok=False)
with tarfile.open(archive) as tar:
    for member in tar.getmembers():
        parts = pathlib.Path(member.name).parts[1:]
        if not parts: continue
        member.name = str(pathlib.Path(*parts))
        safe_path(output, member.name)
        if not (member.isfile() or member.isdir()): raise ValueError('Unsupported source archive member')
        tar.extract(member, output)
if digest(output / 'LICENSE') != pin['license_sha256']: raise ValueError('Source license differs from pin')
VERIFY
cmake -S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=OFF -DGGML_NATIVE=OFF \
  -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=OFF
cmake --build "$build_dir" --config Release -j 4
xcrun clang++ -std=c++17 -arch "$arch" -mmacosx-version-min=14.0 -dynamiclib \
  -I "$source_dir/include" -I "$source_dir/ggml/include" \
  "$repo_dir/Runtime/WhisperCpp/bridge.cpp" \
  "$build_dir/src/libwhisper.a" "$build_dir/ggml/src/libggml.a" \
  "$build_dir/ggml/src/libggml-cpu.a" "$build_dir/ggml/src/ggml-blas/libggml-blas.a" \
  "$build_dir/ggml/src/libggml-base.a" -framework Accelerate -framework Foundation \
  -Wl,-install_name,@loader_path/libsaywing-whisper.dylib \
  -o "$build_dir/libsaywing-whisper.dylib"

python3 - "$repo_dir" "$build_dir/libsaywing-whisper.dylib" "$arch" <<'PROVENANCE'
import json, pathlib, sys
repo, binary = map(pathlib.Path, sys.argv[1:3])
sys.path.insert(0, str(repo / 'scripts'))
from portable_runtime import digest, audit
audit(binary, sys.argv[3])
binary.with_suffix('.provenance.json').write_text(json.dumps({
    'source': json.loads((repo / 'Runtime/Portable/whisper-cpp-source.json').read_text()),
    'bridge_sha256': digest(repo / 'Runtime/WhisperCpp/bridge.cpp'),
    'build_script_sha256': digest(repo / 'scripts/build-whisper-cpp.sh'),
    'binary_sha256': digest(binary), 'architecture': sys.argv[3], 'minimum_macos': '14.0'
}, indent=2) + '\n')
PROVENANCE
