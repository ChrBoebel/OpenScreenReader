#!/usr/bin/env python3
"""Assemble private, architecture-specific resources from pinned inputs; never downloads or signs."""
import argparse
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
from portable_runtime import audit, digest
from release import REPO, receipts, verify_receipt, verify_speech_model


def copy(source, target):
    shutil.copytree(source, target, symlinks=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))


def verify_runtime(root, name, arch):
    expected = json.loads((REPO / 'Runtime/Portable' / f'{name}-{arch}.json').read_text())
    actual = json.loads((root / 'runtime-provenance.json').read_text())
    if actual['lock'] != expected:
        raise ValueError('Runtime provenance differs from the pinned lock')
    # Recheck binaries after copying; provenance alone is not execution evidence.
    audit(root, arch)


def receipt(root, destination):
    inventory = {}
    for path in sorted(root.rglob('*')):
        if path == destination or path.is_symlink() or not path.is_file(): continue
        inventory[str(path.relative_to(root))] = digest(path)
    destination.write_text(json.dumps({'purpose': 'Private compatibility candidate; not approved for redistribution',
                                       'files': inventory}, indent=2) + '\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source-app', type=Path, required=True, help='Receipt-verified legacy app supplying models, demos and notices')
    p.add_argument('--speech-python', type=Path, required=True)
    p.add_argument('--dictation-python', type=Path, required=True)
    p.add_argument('--architecture', choices=['arm64', 'x86_64'], required=True)
    p.add_argument('--cpp-library', type=Path)
    p.add_argument('--cpp-model', type=Path)
    p.add_argument('--output', type=Path, required=True, help='New Resources directory')
    a = p.parse_args()
    if a.output.exists(): raise ValueError('Refusing existing resources')
    if a.architecture == 'x86_64' and (not a.cpp_library or not a.cpp_model):
        raise ValueError('Intel requires a pinned GGML model and whisper.cpp bridge')
    source = a.source_app.resolve(strict=True)
    for root, path in receipts(source): verify_receipt(root, path)
    verify_speech_model(source)
    verify_runtime(a.speech_python, 'speech', a.architecture)
    verify_runtime(a.dictation_python, 'dictation', a.architecture)
    old = source / 'Contents/Resources'
    out = a.output.resolve(); out.mkdir(parents=True)
    speech = out / 'Speech'; speech.mkdir()
    copy(old / 'Speech/DevelopmentModels', speech / 'DevelopmentModels')
    runtime = speech / 'SupertonicRuntime'; runtime.mkdir()
    copy(old / 'Speech/SupertonicRuntime/upstream', runtime / 'upstream')
    copy(a.speech_python, runtime / 'python')
    shutil.copy2(REPO / 'Runtime/Supertonic/worker.py', runtime / 'worker.py')
    shutil.copy2(REPO / 'docs/research/supertonic-comparison-manifest.json', runtime / 'model-manifest.json')
    d = out / 'Dictation'; d.mkdir()
    copy(a.dictation_python, d / 'Python')
    copy(old / 'Dictation/Demos', d / 'Demos')
    copy(old / 'Dictation/Licenses', d / 'Licenses')
    for name in ['worker.py', 'worker.sb', 'model-manifest.json', 'whisper-large-v3-manifest.json']:
        shutil.copy2(REPO / 'Runtime/Dictation' / name, d / name)
    for path in (old / 'Dictation').glob('*NOTICES.md'): shutil.copy2(path, d / path.name)
    if a.architecture == 'arm64':
        copy(old / 'Dictation/WhisperTurbo', d / 'WhisperTurbo')
        shutil.copy2(REPO / 'Runtime/Dictation/whisper-turbo-manifest.json', d / 'whisper-turbo-manifest.json')
        backends = {key: 'mlx' for key in ['whisper-turbo', 'whisper-large-v3', 'qwen3-asr']}
        subprocess.run([sys.executable, REPO / 'scripts/patch-dictation-runtime.py', d], check=True)
        (d / 'RuntimeCache/dynamo').mkdir(parents=True)
    else:
        manifest = json.loads((REPO / 'Runtime/Portable/whisper-turbo-cpp-manifest.json').read_text())
        pin = manifest['files'][0]
        if a.cpp_model.stat().st_size != pin['size'] or digest(a.cpp_model) != pin['verified_sha256']:
            raise ValueError('GGML model differs from pin')
        (d / 'WhisperTurbo').mkdir(); shutil.copy2(a.cpp_model, d / 'WhisperTurbo' / pin['rfilename'])
        shutil.copy2(d / 'Licenses/LICENSE-OpenAI', d / 'WhisperTurbo/LICENSE-OpenAI')
        shutil.copy2(REPO / 'Runtime/Portable/whisper-turbo-cpp-manifest.json', d / 'whisper-turbo-manifest.json')
        cpp = d / 'WhisperCpp'; cpp.mkdir()
        shutil.copy2(a.cpp_library, cpp / 'libsaywing-whisper.dylib')
        for name in ['LICENSE-whisper.cpp', 'whisper-cpp-source.json']: shutil.copy2(REPO / 'Runtime/Portable' / name, cpp / name)
        proof = json.loads(a.cpp_library.with_suffix('.provenance.json').read_text())
        if proof['binary_sha256'] != digest(a.cpp_library) or proof['source'] != json.loads((cpp / 'whisper-cpp-source.json').read_text()):
            raise ValueError('Whisper bridge build provenance mismatch')
        shutil.copy2(a.cpp_library.with_suffix('.provenance.json'), cpp / 'build-provenance.json')
        backends = {'whisper-turbo': 'whisper.cpp'}
    (d / 'runtime-backends.json').write_text(json.dumps(backends, indent=2) + '\n')
    # Verify the selected model using the worker's actual verifier.
    spec = importlib.util.spec_from_file_location('worker', d / 'worker.py')
    worker = importlib.util.module_from_spec(spec); spec.loader.exec_module(worker)
    worker.verify_model(d, 'whisper-turbo')
    for name in ['LICENSE-Saywing', 'DEVELOPMENT-PREVIEW.txt']:
        shutil.copy2(old / name, out / name)
    (out / 'portable-runtime.json').write_text(json.dumps({'architecture': a.architecture, 'minimum_macos': '14.0',
        'status': 'private; requires real macOS 14 and native Intel validation'}, indent=2) + '\n')
    native = audit(out, a.architecture)
    (out / 'native-audit.json').write_text(json.dumps(native, indent=2) + '\n')
    receipt(speech, runtime / 'installation-receipt.json')
    receipt(d, d / 'installation-receipt.json')
    print('Assembled private resources:', out)

if __name__ == '__main__': main()
