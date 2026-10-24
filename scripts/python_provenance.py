#!/usr/bin/env python3
"""Check the provenance record of the bundled CPython interpreter.

Runtime/Portable/python-provenance.json records, for the interpreter pinned in
Runtime/Portable/python.json: the python-build-standalone commit behind the release tag,
the build recipe and the CPython patches as git blob pointers at that commit, the
third-party sources declared there, and the result of comparing each stripped archive
with the full archive of the same release whose license texts the runtime ships.

Offline (unit tests, scripts/build-python-runtime.py): check_pins() rejects a pin that
the record does not describe, so a pin bump must come with new provenance.

Build-time re-check (network to github.com only; nothing is executed from the downloads):

  git clone https://github.com/astral-sh/python-build-standalone /tmp/pbs
  git -C /tmp/pbs checkout <source.commit>
  python3 scripts/python_provenance.py --checkout /tmp/pbs --cache /tmp/pbs-archives

Needs the `zstd` command for the full archives.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import sys
import tarfile
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from portable_runtime import download  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
RECORD = 'Runtime/Portable/python-provenance.json'
PINS = 'Runtime/Portable/python.json'
# Files the release job leaves out of install_only archives (src/release.rs at the recorded commit).
INSTALL_ONLY_DROP_EXTENSIONS = ('_ctypes_test', '_testbuffer', '_testcapi', '_testexternalinspection',
                                '_testimportmultiple', '_testinternalcapi', '_testlimitedcapi',
                                '_testmultiphase', '_testsinglephase')


def check_pins(record, pins):
    """Raise unless the record describes exactly the pinned interpreter archives."""
    if sorted(record['architectures']) != sorted(pins):
        raise ValueError('Interpreter provenance covers %s, pins cover %s; update %s'
                         % (sorted(record['architectures']), sorted(pins), RECORD))
    for architecture, pin in pins.items():
        check_pin(record, architecture, pin)


def check_pin(record, architecture, pin):
    """Raise unless the record describes this architecture's pinned archive."""
    entry = record['architectures'].get(architecture)
    stripped = entry['stripped'] if entry else {}
    expected = (record['release'], record['version'], record['provider'], stripped.get('url'), stripped.get('bytes'), stripped.get('sha256'))
    actual = (pin['release'], pin['version'], pin['provider'], pin['url'], pin['bytes'], pin['sha256'])
    if expected != actual:
        raise ValueError('Interpreter pin for %s is not described by %s; record its provenance first' % (architecture, RECORD))


def load_record():
    record = json.loads((REPO / RECORD).read_text())
    check_pins(record, json.loads((REPO / PINS).read_text()))
    return record


def macho_sections(data):
    """LC_UUID and per-section content hashes of a thin 64-bit Mach-O file, else None."""
    if len(data) < 32 or struct.unpack_from('<I', data)[0] != 0xfeedfacf:
        return None
    count = struct.unpack_from('<I', data, 16)[0]
    offset, uuid, sections = 32, None, {}
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x1b:  # LC_UUID
            uuid = data[offset + 8:offset + 24].hex()
        elif command == 0x19:  # LC_SEGMENT_64
            segment = data[offset + 8:offset + 24].rstrip(b'\0').decode()
            for index in range(struct.unpack_from('<I', data, offset + 64)[0]):
                base = offset + 72 + 80 * index
                name = data[base:base + 16].rstrip(b'\0').decode()
                length, start = struct.unpack_from('<QI', data, base + 40)
                zerofill = (struct.unpack_from('<I', data, base + 64)[0] & 0xff) in (0x1, 0xc, 0x12)
                content = b'' if zerofill or start == 0 else data[start:start + length]
                sections[segment + ',' + name] = '%s:%d' % (hashlib.sha256(content).hexdigest(), length)
        offset += size
    return uuid, sections


def pe_sections(data):
    """Content hashes of PE sections up to VirtualSize (llvm-strip rewrites padding), else None."""
    if data[:2] != b'MZ' or len(data) < 0x40:
        return None
    header = struct.unpack_from('<I', data, 0x3c)[0]
    if data[header:header + 4] != b'PE\0\0':
        return None
    count, optional = struct.unpack_from('<H', data, header + 6)[0], struct.unpack_from('<H', data, header + 20)[0]
    sections = {}
    for index in range(count):
        base = header + 24 + optional + 40 * index
        name = data[base:base + 8].rstrip(b'\0').decode(errors='replace')
        virtual, _, raw, start = struct.unpack_from('<IIII', data, base + 8)
        if not name.startswith(('.debug', '/')):
            sections[name] = hashlib.sha256(data[start:start + min(virtual, raw)]).hexdigest()
    return sections


def compare_trees(stripped, install):
    """Every stripped file equals its full-archive file, or is the same binary minus debug data."""
    identical, macho, pe, problems = 0, [], [], []
    files = sorted(p for p in stripped.rglob('*') if p.is_file() and not p.is_symlink())
    for path in files:
        relative = path.relative_to(stripped).as_posix()
        other = install / relative
        if not other.is_file():
            problems.append('missing in full archive: ' + relative)
            continue
        a, b = path.read_bytes(), other.read_bytes()
        if a == b:
            identical += 1
            continue
        ma, mb = macho_sections(a), macho_sections(b)
        if ma and mb:
            kept = {k: v for k, v in mb[1].items() if not k.startswith('__DWARF')}
            same = [k for k in kept if not k.startswith('__LINKEDIT')]
            if ma[0] and ma[0] == mb[0] and sorted(ma[1]) == sorted(kept) and all(ma[1][k] == kept[k] for k in same):
                macho.append({'path': relative, 'lc_uuid': ma[0]})
                continue
        elif pe_sections(a) is not None and pe_sections(a) == pe_sections(b):
            pe.append(relative)
            continue
        problems.append('content differs: ' + relative)
    links = sorted(p for p in stripped.rglob('*') if p.is_symlink())
    for link in links:
        other = install / link.relative_to(stripped)
        if not other.is_symlink() or other.readlink() != link.readlink():
            problems.append('symlink differs: ' + link.relative_to(stripped).as_posix())
    return {'stripped_files': len(files), 'byte_identical': identical, 'symlinks': len(links),
            'macho': macho, 'pe': pe, 'problems': sorted(problems)}


def unexplained_full_only(stripped, install, metadata):
    """Files only in the full archive that src/release.rs does not drop on purpose."""
    stdlib = metadata['python_paths']['stdlib'].removeprefix('install/')
    tests = [stdlib + '/' + name.replace('.', '/') + '/' for name in metadata['python_stdlib_test_packages']]
    dropped = {entry['shared_lib'].removeprefix('install/') for name, variants in metadata['build_info']['extensions'].items()
               if name in INSTALL_ONLY_DROP_EXTENSIONS for entry in variants if entry.get('shared_lib')}
    have = {p.relative_to(stripped).as_posix() for p in stripped.rglob('*') if p.is_file() or p.is_symlink()}
    result = []
    for path in sorted(install.rglob('*')):
        relative = path.relative_to(install).as_posix()
        if not (path.is_file() or path.is_symlink()) or relative in have or relative in dropped:
            continue
        if ('/libpython' in '/' + relative and relative.endswith('.a')) or any(relative.startswith(t) for t in tests):
            continue
        result.append(relative)
    return result


def git(checkout, *args):
    return subprocess.run(['git', '-C', str(checkout), *args], capture_output=True, text=True, check=True).stdout.strip()


def extract(archive, target):
    target.mkdir(parents=True)
    if archive.read_bytes()[:4] == b'\x28\xb5\x2f\xfd':  # zstd frame
        plain = target.with_suffix('.tar')
        with plain.open('wb') as out:
            subprocess.run(['zstd', '-dc', str(archive)], stdout=out, check=True)
        archive = plain
    with tarfile.open(archive) as tar:
        tar.extractall(target, filter='data')
    return target / 'python'


def verify(record, checkout, cache):
    failures = []

    def expect(condition, message):
        if not condition:
            failures.append(message)

    source = record['source']
    tag = subprocess.run(['git', 'ls-remote', source['repository'], source['tag']], capture_output=True, text=True,
                         check=True).stdout.split()
    expect(tag[:1] == [source['commit']], 'tag %s does not resolve to %s' % (source['tag'], source['commit']))
    expect(git(checkout, 'rev-parse', 'HEAD') == source['commit'], 'checkout is not at the recorded commit')
    script = (checkout / 'cpython-unix/build-cpython.sh').read_text().splitlines()
    for entry in record['recipe']['files'] + record['cpython_patches']['applied'] + [source['build_scripts_license']]:
        expect(git(checkout, 'rev-parse', 'HEAD:' + entry['path']) == entry['blob'], 'blob differs: ' + entry['path'])
    for patch in record['cpython_patches']['applied']:
        name = Path(patch['path']).name.replace('-3.12.patch', '-${PYTHON_MAJMIN_VERSION}.patch') \
            if 'getpath-backport' in patch['path'] else Path(patch['path']).name
        for line in patch['build_cpython_sh_lines']:
            expect('patch -p1 -i' in script[line - 1] and name in script[line - 1],
                   'build-cpython.sh:%d does not apply %s' % (line, patch['path']))
    downloads = json.loads((checkout / 'pythonbuild/downloads.json').read_text())
    for item in record['third_party_sources']:
        declared = downloads.get(item['name'], {})
        expect((declared.get('url'), declared.get('sha256'), declared.get('size')) == (item['url'], item['sha256'], item['bytes']),
               'downloads.json differs for ' + item['name'])
    sums_path = download(dict(source['sha256sums'], filename='SHA256SUMS'), cache)
    sums = dict(reversed(line.split()) for line in sums_path.read_text().splitlines() if line.strip())
    report = {}
    with tempfile.TemporaryDirectory(dir=cache) as temp:
        for architecture, entry in record['architectures'].items():
            for kind in ('stripped', 'full'):
                name = entry[kind]['url'].rsplit('/', 1)[1].replace('%2B', '+')
                expect(sums.get(name) == entry[kind]['sha256'], 'SHA256SUMS differs for ' + name)
            stripped = extract(download(dict(entry['stripped'], filename=architecture + ' stripped'), cache),
                               Path(temp) / (architecture + '-stripped'))
            full = extract(download(dict(entry['full'], filename=architecture + ' full'), cache), Path(temp) / (architecture + '-full'))
            metadata = json.loads((full / 'PYTHON.json').read_text())
            checks = entry['consistency']
            expect({k: metadata[k] for k in checks['full_python_json']} == checks['full_python_json'], architecture + ': PYTHON.json differs')
            expect(metadata['target_triple'] == entry['target_triple'], architecture + ': target differs')
            config = metadata['python_config_vars']
            expect(config['BUILD_GNU_TYPE'] == entry['build_triple'], architecture + ': build triple differs')
            expect(checks['sysconfig_build_directory'] in config['CONFIG_ARGS'], architecture + ': build directory differs')
            patchlevel = (stripped / 'include/python3.12/patchlevel.h').read_text()
            expect('#define PY_VERSION              "%s"' % record['version'] in patchlevel, architecture + ': stripped version differs')
            data = sorted((stripped / 'lib/python3.12').glob('_sysconfigdata_*.py'))
            expect(len(data) == 1 and data[0].read_bytes() == (full / 'install/lib/python3.12' / data[0].name).read_bytes(),
                   architecture + ': _sysconfigdata differs')
            if data:
                variables = ast.literal_eval(data[0].read_text().split('build_time_vars = ', 1)[1])
                expect(variables['HOST_GNU_TYPE'] == entry['target_triple'], architecture + ': stripped host triple differs')
            licenses = entry['licenses']
            expect(sorted(p.name for p in (full / 'licenses').iterdir()) == licenses['full_archive_files'], architecture + ': license list differs')
            for name in licenses['shipped_files']:
                expect((REPO / licenses['notice_directory'] / name).read_bytes() == (full / 'licenses' / name).read_bytes(),
                       architecture + ': shipped license differs from full archive: ' + name)
            result = compare_trees(stripped, full / 'install')
            expect(result['problems'] == [], architecture + ': ' + '; '.join(result['problems']))
            expect(result['macho'] == checks['mach_o_debug_stripped_same_lc_uuid_and_sections'], architecture + ': Mach-O set differs')
            expect(result['byte_identical'] == checks['byte_identical_files'], architecture + ': identical file count differs')
            extra = unexplained_full_only(stripped, full / 'install', metadata)
            expect(not extra, architecture + ': unexplained full-only files: ' + ', '.join(extra[:5]))
            report[architecture] = {k: result[k] for k in ('stripped_files', 'byte_identical', 'symlinks')} | {
                'macho_same_uuid_and_sections': len(result['macho']), 'pe_same_sections': len(result['pe'])}
    return failures, report


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--checkout', type=Path, required=True, help='python-build-standalone checkout at the recorded commit')
    parser.add_argument('--cache', type=Path, required=True, help='Download cache (archives are re-verified on use)')
    args = parser.parse_args()
    failures, report = verify(load_record(), args.checkout.resolve(), args.cache.resolve())
    print(json.dumps(report, indent=2))
    if failures:
        sys.exit('Interpreter provenance check failed:\n- ' + '\n- '.join(failures))
    print('Interpreter provenance verified for', ', '.join(sorted(report)))


if __name__ == '__main__':
    main()
