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
SOURCE_CACHE = REPO / '.build/license-corresponding-source'
MH_MAGIC_64 = (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe')
FAT_MAGIC = (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf')
MH_DYLIB = 6
# GNU toolchain runtime libraries (LGPL / GPL with the GCC exception). Every copy must be
# declared by a corresponding-source record and stay a separate, replaceable dylib.
GNU_RUNTIME = ('libquadmath', 'libgfortran', 'libgcc_s', 'libstdc++', 'libgomp', 'libatomic', 'libssp')


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


def for_architecture(records, architecture):
    return [item for item in records if architecture in item.get('architectures', ['arm64', 'x86_64'])]


def macho_filetype(path):
    """Mach-O file type; for universal files, every slice must have the same type."""
    with path.open('rb') as stream:
        header = stream.read(8)
        if header[:4] in FAT_MAGIC:
            offset_size = 8 if header[:4] == FAT_MAGIC[1] else 4
            count = int.from_bytes(header[4:8], 'big')
            types = set()
            for index in range(count):
                stream.seek(8 + index * (12 + 2 * offset_size + 4 * (offset_size == 8)) + 8)
                offset = int.from_bytes(stream.read(offset_size), 'big')
                stream.seek(offset)
                slice_header = stream.read(16)
                types.add(int.from_bytes(slice_header[12:16], 'little') if slice_header[:4] in MH_MAGIC_64 else None)
            return types.pop() if len(types) == 1 else None
        stream.seek(0)
        header = stream.read(16)
    return int.from_bytes(header[12:16], 'little') if header[:4] in MH_MAGIC_64 else None


def verify_copyleft_libraries(resources, records):
    """Return {library name: [relative paths]} after checking each is a separate dylib."""
    declared = {name for item in records for name in item.get('dynamic_libraries', [])}
    found = {}
    for path in sorted(resources.rglob('*')):
        if not path.name.startswith(GNU_RUNTIME) or not ('.dylib' in path.name or path.suffix in ('.so', '.a')):
            continue
        relative = str(path.relative_to(resources))
        if path.suffix == '.a':
            raise ValueError('Static GNU runtime archive must not be bundled: ' + relative)
        if path.is_symlink():
            if not path.resolve(strict=True).is_relative_to(resources.resolve()):
                raise ValueError('GNU runtime library escapes bundle: ' + relative)
            continue
        if path.name not in declared:
            raise ValueError('Undeclared GNU runtime library (add its corresponding source): ' + relative)
        if macho_filetype(path) != MH_DYLIB:
            raise ValueError('GNU runtime library is not a separate dynamic library: ' + relative)
        found.setdefault(path.name, []).append(relative)
    missing = sorted(declared - set(found))
    if missing:
        raise ValueError('Declared GNU runtime libraries are missing; update their record: ' + ', '.join(missing))
    return found


def copyleft_section(records, found):
    """License, replaceability and source-availability statement for the GNU libraries."""
    rows = []
    for item in records:
        if not item.get('dynamic_libraries'):
            continue
        paths = [path for name in item['dynamic_libraries'] for path in found.get(name, [])]
        sources = [record for record in records if record.get('component') == item['component']]
        rows.append('<h3>' + escape(item['component']) + '</h3><p>License: ' + escape(item['license']) + '.</p>'
                    '<p>Separate dynamic libraries in this app, unmodified from their upstream package:</p><ul>'
                    + ''.join('<li><code>' + escape(path) + '</code></li>' for path in paths) + '</ul><p>'
                    + escape(item.get('binary_origin', '')) + '</p><p>Complete corresponding source:</p><ul>'
                    + ''.join('<li><code>CorrespondingSource/' + escape(record['file']) + '</code>, ' + str(record['bytes'])
                              + ' bytes, SHA-256 <code>' + escape(record['sha256']) + '</code>, from '
                              + escape(record['url']) + '</li>' for record in sources) + '</ul>')
    if not rows:
        return ''
    return ('<h2>GNU libraries: license, replacement and source</h2>'
            '<p>The libraries below are licensed under the GNU Lesser General Public License version 2.1 or later, '
            'or the GNU General Public License version 3 or later with the GCC Runtime Library Exception 3.1. '
            'Their complete license texts are under Licenses/GCC-13.4.0 below. They are loaded at run time as '
            'separate files, so you may replace them with a modified or compatible version as described in '
            'CorrespondingSource/README.md. Saywing imposes no additional restriction on modifying them for your '
            'own use or on reverse engineering for debugging such modifications.</p>'
            '<p>The complete corresponding source is distributed with this app in the CorrespondingSource folder; '
            'availability.json shows whether this copy includes every archive. If a copy you received lacks any of '
            'them, the exact files are available from the addresses below (verify the SHA-256), and the Saywing '
            'maintainers will provide them on request through the project repository for at least three years '
            'after the last distribution of this version.</p>' + ''.join(rows))


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


def render_index(resources, copyleft=''):
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
''' + copyleft + '''
<h2>Original license texts and notices</h2>
<p>This document is available offline. The paths identify the original notices inside this app. An inventory does not certify that all distribution obligations have been fulfilled.</p>
''' + '\n'.join(sections) + '</html>\n'


def bundle_sources(resources, cache, records, required=False):
    destination = resources / 'CorrespondingSource'
    inputs = []
    names = {item['file'] for item in records}
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
    # Archives of components that are no longer shipped must not linger from an input app.
    for path in destination.iterdir():
        if path.name not in names | {'sources.json', 'availability.json', 'README.md'}:
            shutil.rmtree(path) if path.is_dir() and not path.is_symlink() else path.unlink()
    for source, target in inputs:
        if source.resolve() != target.resolve():
            shutil.copy2(source, target)
    (destination / 'sources.json').write_text(json.dumps(records, indent=2) + '\n')
    (destination / 'availability.json').write_text(json.dumps({'included': len(inputs), 'expected': len(records)}, indent=2) + '\n')


def fetch_sources(cache, records):
    """Build time only: download missing corresponding sources and verify size and SHA-256."""
    cache.mkdir(parents=True, exist_ok=True)
    for item in records:
        target = cache / Path(item['file']).name
        if not target.is_file():
            partial = target.with_name(target.name + '.partial')
            subprocess.run(['/usr/bin/curl', '--fail', '--location', '--silent', '--show-error', '--proto', '=https',
                            '--output', str(partial), item['url']], check=True)
            partial.rename(target)
        if target.stat().st_size != item['bytes'] or hashlib.sha256(target.read_bytes()).hexdigest() != item['sha256']:
            target.unlink()
            raise ValueError('Corresponding source hash/size mismatch: ' + item['file'])
        print('Verified', item['file'], flush=True)


def bundle_notices(resources, require_sources=False):
    sources = REPO / 'docs/licenses'
    portable = resources / 'portable-runtime.json'
    architecture = json.loads(portable.read_text())['architecture'] if portable.exists() else 'arm64'
    source_records = for_architecture(json.loads((sources / 'native-corresponding-sources.json').read_text()), architecture)
    gnu_libraries = verify_copyleft_libraries(resources, source_records)
    bundle_sources(resources, SOURCE_CACHE, source_records, required=require_sources)
    shutil.copy2(sources / 'CorrespondingSource-README.md', resources / 'CorrespondingSource/README.md')
    records = json.loads((sources / 'portable-supplement-sources.json').read_text())
    rust_proof = json.loads((sources / 'rust-license-coverage.json').read_text())
    verify_rust_coverage(resources, rust_proof, architecture)
    records = for_architecture(records, architecture)
    verify_supplements(sources, records)
    target = resources / 'Licenses'
    target.mkdir(exist_ok=True)
    shutil.copy2(sources / 'rust-license-coverage.json', target / 'rust-license-coverage.json')
    if any(item['architecture'] == architecture for item in rust_proof['binaries']):
        shutil.copytree(sources / 'RustBuild', target / 'RustBuild', dirs_exist_ok=True)
    for name in ['Supertonic-3-Open-RAIL-M.txt'] + [item['license_file'] for item in records]:
        (target / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(sources / name, target / name)
    (target / 'supplement-sources.json').write_text(json.dumps(records, indent=2) + '\n')
    (target / 'RUNTIME-NOTES.txt').write_text(
        'Current portable runtime: CPython 3.12.15; architecture: ' + architecture + '.\n'
        'Minimum macOS target: 14.0. This is not proof of execution on every supported Mac.\n'
        'Dictation backend: ' + ('MLX Whisper Turbo 4-bit.' if architecture == 'arm64' else 'whisper.cpp with Whisper Turbo GGML.') + '\n'
        'Both worker runtimes are built by scripts/build-python-runtime.py from hash-locked inputs.\n'
        'Their installed-packages.json and THIRD-PARTY-NOTICES.txt inside the app list the exact\n'
        'packages, vendored native libraries and license texts; the model manifests identify the\n'
        'bundled models.\n')

    # Exact originals remain in place; the readable index is generated before signing.
    (resources / 'THIRD-PARTY-NOTICES.html').write_text(
        render_index(resources, copyleft_section(source_records, gnu_libraries)), encoding='utf-8')
    inventory = [{'path': str(p.relative_to(resources)), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                 for p in notice_files(resources)]
    (target / 'notice-inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    return len(inventory)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('resources', type=Path, nargs='?')
    parser.add_argument('--fetch-sources', action='store_true',
                        help='Download and verify every corresponding-source archive into .build/license-corresponding-source')
    parser.add_argument('--require-sources', action='store_true', help='Fail unless every corresponding source is bundled')
    args = parser.parse_args()
    if not args.resources and not args.fetch_sources:
        parser.error('resources or --fetch-sources is required')
    if args.fetch_sources:
        fetch_sources(SOURCE_CACHE, json.loads((REPO / 'docs/licenses/native-corresponding-sources.json').read_text()))
    if args.resources:
        print('Bundled notice files:', bundle_notices(args.resources.resolve(strict=True), require_sources=args.require_sources))
