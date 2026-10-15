#!/usr/bin/env python3
"""Retain and expose exact bundled notices; this inventory is not a legal approval."""
import argparse
import hashlib
from html import escape
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]


def verify_supplements(directory, records):
    for record in records:
        path = (directory / record['license_file']).resolve(strict=True)
        if not path.is_relative_to(directory.resolve()):
            raise ValueError('License supplement escapes directory')
        if hashlib.sha256(path.read_bytes()).hexdigest() != record['license_sha256']:
            raise ValueError('License supplement hash mismatch: ' + record['license_file'])



def unsigned_digest(path):
    # Developer ID signing changes the seal, not the reviewed native code.
    # Normalize a temporary copy so re-signing does not invalidate provenance.
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / path.name
        shutil.copy2(path, copy)
        subprocess.run(['/usr/bin/codesign', '--remove-signature', str(copy)], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return hashlib.sha256(copy.read_bytes()).hexdigest()


def verify_rust_coverage(resources, proof, architecture):
    if not proof.get('complete') or architecture not in ('arm64', 'x86_64'):
        raise ValueError('Rust license coverage is incomplete or architecture is unknown')
    records = [item for item in proof['binaries'] if item['architecture'] == architecture]
    if architecture == 'arm64' and not records:
        raise ValueError('ARM Rust binary provenance is missing')
    known = set()
    for item in records:
        relative = Path(item['path'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Rust provenance escapes bundle')
        path = resources / relative
        if not path.is_file() or not path.resolve().is_relative_to(resources.resolve()):
            raise ValueError('Rust provenance is missing or escapes bundle')
        if unsigned_digest(path) != item['unsigned_sha256']:
            raise ValueError('Rust binary differs from license-reviewed source: ' + item['path'])
        known.add(path.resolve())
    for path in resources.rglob('*'):
        if path.is_file() and path.suffix in ('.so', '.dylib') and path.resolve() not in known:
            if b'/rustc/' in path.read_bytes():
                raise ValueError('Unreviewed Rust library: ' + str(path.relative_to(resources)))


def notice_files(resources):
    for path in sorted(resources.rglob('*')):
        if not path.is_file():
            continue
        name = path.name.upper()
        supplemental = path.is_relative_to(resources / 'Licenses') and path.suffix.lower() in ('.txt', '.md', '.rst')
        if not supplemental and not name.startswith(('LICENSE', 'LICENCE', 'COPYING', 'NOTICE', 'THIRDPARTYNOTICE', 'COPYRIGHT', 'AUTHORS')):
            continue
        if not path.resolve().is_relative_to(resources.resolve()):
            raise ValueError('Notice escapes resource directory')
        # Source code named licenses.py is not a license document.
        if path.suffix.lower() in ('.py', '.pyc', '.so', '.dylib', '.json', '.html'):
            continue
        yield path


def render_index(resources):
    sections = []
    for path in notice_files(resources):
        content = path.read_text(encoding='utf-8')
        sections.append('<details><summary>' + escape(str(path.relative_to(resources)))
                        + '</summary><pre>' + escape(content) + '</pre></details>')
    if not sections:
        raise ValueError('No license notices found')
    return '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<title>Saywing — Licenses &amp; Model Terms</title>
<style>body{font:17px system-ui;max-width:900px;margin:48px auto;padding:0 24px;line-height:1.6}summary{cursor:pointer;overflow-wrap:anywhere}details{margin:16px 0}pre{white-space:pre-wrap;overflow-wrap:anywhere;font:14px ui-monospace}h1{line-height:1.2}</style>
<h1>Licenses &amp; Model Terms</h1>
<p>Saywing source code is licensed under Apache-2.0. Third-party code, models and voices retain their own licenses below.</p>
<h2>Supertonic 3</h2>
<p>Use and redistribution of the bundled Supertonic 3 model and voice are governed by the BigScience Open RAIL-M license, including paragraph 5 and Attachment A (use restrictions). These terms apply to the model and its derivatives, not to unrelated Saywing source code or other components. The complete unchanged license is included below.</p>
<p>Für die Nutzung und Weitergabe des mitgelieferten Supertonic-3-Modells und seiner Stimme gilt die BigScience Open RAIL-M-Lizenz einschließlich Absatz 5 und Anhang A (Nutzungsbeschränkungen). Diese Bedingungen gelten für das Modell und seine Ableitungen, nicht für unabhängigen Saywing-Quellcode oder andere Komponenten. Der vollständige unveränderte Lizenztext folgt unten.</p>
<h2>Corresponding source</h2>
<p>The CorrespondingSource folder beside this document contains the available original native-library sources and build instructions. Its availability.json records inclusion; sources.json records exact URLs, sizes and hashes. This does not change the license of Saywing or other components.</p>
<h2>Original license texts and notices</h2>
<p>This document is available offline. The paths identify the original notices inside this app. An inventory does not certify that all distribution obligations have been fulfilled.</p>
''' + '\n'.join(sections) + '</html>\n'


def bundle_sources(resources, cache, records, required=False):
    destination = resources / 'CorrespondingSource'
    inputs = []
    for item in records:
        name = item['file']
        if Path(name).name != name or name in ('', '.', '..'):
            raise ValueError('Invalid corresponding-source filename')
        source = destination / name if (destination / name).is_file() else cache / name
        if not source.is_file():
            if required:
                raise FileNotFoundError('Missing corresponding source: ' + name)
            continue
        if source.is_symlink() or source.stat().st_size != item['bytes'] or hashlib.sha256(source.read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Corresponding source hash/size mismatch: ' + name)
        inputs.append((source, destination / name))
    destination.mkdir(parents=True, exist_ok=True)
    for source, target in inputs:
        if source.resolve() != target.resolve():
            shutil.copy2(source, target)
    (destination / 'sources.json').write_text(json.dumps(records, indent=2) + '\n')
    (destination / 'availability.json').write_text(json.dumps({'included': len(inputs), 'expected': len(records)}, indent=2) + '\n')


def bundle_notices(resources, require_sources=False):
    sources = REPO / 'docs/licenses'
    source_records = json.loads((sources / 'native-corresponding-sources.json').read_text())
    bundle_sources(resources, REPO / '.build/license-corresponding-source', source_records, required=require_sources)
    shutil.copy2(sources / 'CorrespondingSource-README.md', resources / 'CorrespondingSource/README.md')
    records = json.loads((sources / 'portable-supplement-sources.json').read_text())
    portable = resources / 'portable-runtime.json'
    architecture = json.loads(portable.read_text())['architecture'] if portable.exists() else 'arm64'
    rust_proof = json.loads((sources / 'rust-license-coverage.json').read_text())
    verify_rust_coverage(resources, rust_proof, architecture)
    records = [item for item in records if architecture in item.get('architectures', ['arm64', 'x86_64'])]
    verify_supplements(sources, records)
    target = resources / 'Licenses'
    target.mkdir(exist_ok=True)
    shutil.copy2(sources / 'rust-license-coverage.json', target / 'rust-license-coverage.json')
    shutil.copytree(sources / 'RustBuild', target / 'RustBuild', dirs_exist_ok=True)
    for name in ['Supertonic-3-Open-RAIL-M.txt'] + [item['license_file'] for item in records]:
        (target / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(sources / name, target / name)
    (target / 'supplement-sources.json').write_text(json.dumps(records, indent=2) + '\n')
    (target / 'RUNTIME-NOTES.txt').write_text(
        'Current portable runtime: CPython 3.12.15; architecture: ' + architecture + '.\n'
        'Minimum macOS target: 14.0. This is not proof of execution on every supported Mac.\n'
        'Dictation backend: ' + ('MLX Whisper Turbo 4-bit.' if architecture == 'arm64' else 'whisper.cpp with Whisper Turbo GGML.') + '\n'
        'The original development notices retained inside Dictation describe historical inputs,\n'
        'including Python 3.12.14 and MLX-only experiments. They are not the inventory of this\n'
        'portable build. The current runtime-provenance.json, runtime-backends.json and model\n'
        'manifests inside the app identify the actual bundled versions and selected backend.\n')

    # Exact originals remain in place; the readable index is generated before signing.
    (resources / 'THIRD-PARTY-NOTICES.html').write_text(render_index(resources), encoding='utf-8')
    inventory = [{'path': str(p.relative_to(resources)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                 for p in notice_files(resources)]
    (target / 'notice-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    return len(inventory)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('resources', type=Path)
    args = parser.parse_args()
    print('Bundled notice files:', bundle_notices(args.resources.resolve(strict=True)))
