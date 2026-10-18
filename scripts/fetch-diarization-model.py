#!/usr/bin/env python3
"""Download the pinned LS-EEND diarisation model for a Saywing build and verify every file.

Build-time only: the app itself never downloads it. Files come from the revision in
Runtime/Diarization/ls-eend-manifest.json and must match its sizes and SHA-256 digests;
anything else is deleted and the script fails."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import urllib.request

repo = Path(__file__).resolve().parents[1]
manifest = json.loads((repo/'Runtime/Diarization/ls-eend-manifest.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('target', type=Path, help='Directory that receives the variant folder (for example .build/models/ls-eend)')
parser.add_argument('--variant', default=manifest['bundled_variant'], choices=sorted(manifest['variants']))
args = parser.parse_args()

def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

target = args.target.resolve()
for item in manifest['variants'][args.variant]['files']:
    path = (target/item['rfilename']).resolve()
    if not path.is_relative_to(target):
        raise SystemExit('Manifest path escapes target')
    if path.is_file() and path.stat().st_size == item['size'] and sha256(path) == item['verified_sha256']:
        continue
    path.parent.mkdir(parents=True, exist_ok=True)
    url = f"https://huggingface.co/{manifest['repo']}/resolve/{manifest['revision']}/{item['rfilename']}"
    print('Downloading', item['rfilename'], file=sys.stderr)
    with urllib.request.urlopen(url) as response, path.open('wb') as out:
        while chunk := response.read(1024 * 1024):
            out.write(chunk)
    if path.stat().st_size != item['size'] or sha256(path) != item['verified_sha256']:
        path.unlink()
        raise SystemExit('Verification failed: ' + item['rfilename'])
print(target/manifest['variants'][args.variant]['directory'])
