#!/usr/bin/env python3
"""Attach already installed, pinned dictation assets to a private Saywing build. No downloads."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

def sha256(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('resources', type=Path, help='Existing verified Qwen runtime with Python/ and Model/')
parser.add_argument('--whisper-model', type=Path, required=True, help='Verified pinned Whisper Turbo model directory')
parser.add_argument('--speech-from', type=Path, help='Reuse verified self-contained Speech resources from an existing app')
parser.add_argument('--development-only', required=True, action='store_true')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
app, source = args.app.resolve(strict=True), args.resources.resolve(strict=True)
if app.name != 'Saywing.app' or not (app/'Contents/MacOS/Saywing').is_file():
    raise SystemExit('Expected a built Saywing.app')
target = app/'Contents/Resources/Dictation'
if target.exists():
    raise SystemExit('Refusing to replace an existing dictation runtime; use a fresh build')
manifest = json.loads((repo/'Runtime/Dictation/model-manifest.json').read_text())
whisper_manifest = json.loads((repo/'Runtime/Dictation/whisper-turbo-manifest.json').read_text())
whisper_source = args.whisper_model.resolve(strict=True)
for item in whisper_manifest['files']:
    asset = (whisper_source/item['rfilename']).resolve(strict=True)
    if not asset.is_relative_to(whisper_source):
        raise SystemExit('Whisper path escapes source')
    with asset.open('rb') as f:
        digest = sha256(f)
    if asset.stat().st_size != item['size'] or digest != item['verified_sha256']:
        raise SystemExit('Pinned Whisper model verification failed')
if not all((whisper_source/name).is_file() for name in ['LICENSE-OpenAI', 'LICENSE-Apache-2.0']):
    raise SystemExit('Missing Whisper model license notice')
for item in manifest['files']:
    if item['rfilename'].startswith('.'):
        continue
    asset = (source/'Model'/item['rfilename']).resolve(strict=True)
    if not asset.is_relative_to((source/'Model').resolve()):
        raise SystemExit('Model path escapes source')
    with asset.open('rb') as f:
        digest = sha256(f)
    if asset.stat().st_size != item['size'] or digest != item['verified_sha256']:
        raise SystemExit('Pinned model verification failed')
if not (source/'Python/lib/python3.12/LICENSE.txt').is_file():
    raise SystemExit('Missing CPython license')
for component in ['Python', 'Model', 'Demos']:
    for path in (source/component).rglob('*'):
        if 'pkgconfig' in path.parts or path.name == 'python3.1':
            continue  # Build-time metadata/manual alias from the interpreter toolchain.
        if path.is_symlink() and not path.resolve(strict=True).is_relative_to(source):
            raise SystemExit('External symlink in source runtime')
if args.speech_from:
    speech_app = args.speech_from.resolve(strict=True)
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(speech_app)],check=True)
    speech_source = speech_app/'Contents/Resources/Speech'
    speech_target = app/'Contents/Resources/Speech'
    if speech_target.exists():
        raise SystemExit('Refusing to replace existing Speech resources')
    receipt = json.loads((speech_source/'SupertonicRuntime/installation-receipt.json').read_text())
    speech_manifest = json.loads((repo/'docs/research/supertonic-comparison-manifest.json').read_text())
    if receipt['model_revision'] != speech_manifest['revision']:
        raise SystemExit('Unexpected speech model revision')
    for relative, expected in receipt['files'].items():
        path = (speech_source/relative).resolve(strict=True)
        if not path.is_relative_to(speech_source):
            raise SystemExit('Speech receipt escapes source')
        with path.open('rb') as f:
            if sha256(f) != expected:
                raise SystemExit('Bundled speech receipt mismatch: '+relative)
    if (speech_source/'SupertonicRuntime/worker.py').read_bytes() != (repo/'Runtime/Supertonic/worker.py').read_bytes():
        raise SystemExit('Bundled speech worker differs from project')
    shutil.copytree(speech_source,speech_target,symlinks=True)
    for name in ['LICENSE-Saywing','DEVELOPMENT-PREVIEW.txt']:
        asset = speech_app/'Contents/Resources'/name
        if asset.is_file():
            shutil.copy2(asset,app/'Contents/Resources'/name)
target.mkdir(parents=True)
for component in ['Python', 'Model', 'Demos']:
    shutil.copytree(source/component, target/component, symlinks=True,
                    ignore=shutil.ignore_patterns('__pycache__', '*.pyc', 'pkgconfig', 'python3.1'))
(target/'WhisperTurbo').mkdir()
for item in whisper_manifest['files']:
    shutil.copy2(whisper_source/item['rfilename'], target/'WhisperTurbo'/item['rfilename'])
for name in ['worker.py', 'worker.sb', 'model-manifest.json', 'whisper-turbo-manifest.json', 'requirements-lock.txt', 'installed-packages.json']:
    shutil.copy2(repo/'Runtime/Dictation'/name, target/name)
(target/'RuntimeCache/dynamo').mkdir(parents=True)
shutil.copy2(repo/'docs/research/qwen-dictation-runtime.md', target/'MODEL-AND-RUNTIME-NOTICES.md')
shutil.copy2(repo/'docs/research/whisper-turbo-dictation.md', target/'WHISPER-TURBO-NOTICES.md')
macho = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
         b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
inventory = {}
for path in sorted(target.rglob('*')):
    if path.is_symlink():
        if not path.resolve(strict=True).is_relative_to(target):
            raise SystemExit('External or broken bundle symlink')
        continue
    if not path.is_file():
        continue
    with path.open('rb') as f:
        native = f.read(4) in macho
    if native:
        subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(path)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with path.open('rb') as f:
        inventory[str(path.relative_to(target))] = sha256(f)
(target/'installation-receipt.json').write_text(json.dumps({
    'purpose': 'Private local integration build; not notarized or approved for redistribution',
    'model_revision': manifest['revision'], 'whisper_revision': whisper_manifest['revision'],
    'files': inventory}, indent=2)+'\n')
subprocess.run(['/usr/bin/codesign','--force','--sign','-','--options','runtime','--entitlements',str(repo/'OpenScreenReaderApp/Saywing.entitlements'),str(app)],check=True)
subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(app)],check=True)
subprocess.run([sys.executable, str(repo/'scripts/verify-app-permissions.py'), str(app)], check=True)
print('PRIVATE SAYWING BUILD WITH DICTATION:',app)
