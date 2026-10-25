#!/usr/bin/env python3
"""Copy the verified LS-EEND voice model into a built Saywing.app. No downloads.

Every file must match Runtime/Diarization/ls-eend-manifest.json. Run it before the step
that signs the app (bundle-dictation-runtime.py or release.py signing), because it
changes the bundle's resources."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

repo = Path(__file__).resolve().parents[1]
manifest = json.loads((repo/'Runtime/Diarization/ls-eend-manifest.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('models', type=Path, help='Directory filled by scripts/fetch-diarization-model.py')
parser.add_argument('--variant', default=manifest['bundled_variant'], choices=sorted(manifest['variants']))
args = parser.parse_args()

app, models = args.app.resolve(strict=True), args.models.resolve(strict=True)
if app.name != 'Saywing.app' or not (app/'Contents/MacOS/Saywing').is_file():
    raise SystemExit('Expected a built Saywing.app')
variant = manifest['variants'][args.variant]
source = (models/variant['directory']).resolve(strict=True)
for item in variant['files']:
    path = (models/item['rfilename']).resolve(strict=True)
    if not path.is_relative_to(source):
        raise SystemExit('Model path escapes source')
    if path.stat().st_size != item['size'] or hashlib.sha256(path.read_bytes()).hexdigest() != item['verified_sha256']:
        raise SystemExit('Pinned voice model verification failed: ' + item['rfilename'])
target = app/'Contents/Resources/Diarization'
if target.exists():
    raise SystemExit('Refusing to replace an existing voice model; use a fresh build')
target.mkdir(parents=True)
shutil.copytree(source, target/Path(variant['directory']).name)
shutil.copy2(repo/'Runtime/Diarization/ls-eend-manifest.json', target/'ls-eend-manifest.json')
shutil.copy2(repo/'Runtime/Diarization/LICENSE-LS-EEND.txt', target/'LICENSE-LS-EEND.txt')
print('VOICE MODEL BUNDLED:', target/Path(variant['directory']).name)
