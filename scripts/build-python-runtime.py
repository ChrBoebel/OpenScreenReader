#!/usr/bin/env python3
"""Build a minimal, reproducible CPython runtime for one Saywing worker.

Build-time network only: downloads the pinned python-build-standalone archive
(Runtime/Portable/python.json, SHA-256 verified before extraction) and the
hash-locked wheels of one requirements lock. The app never runs this script and
never downloads or installs Python packages.

  python3 scripts/build-python-runtime.py --runtime dictation --architecture arm64 \\
      --cache .build/runtime-cache --output .build/runtime/dictation-arm64

The output directory is the interpreter root (bin/, lib/) plus
installed-packages.json (SBOM without absolute paths), THIRD-PARTY-NOTICES.txt
and runtime-provenance.json (including the interpreter's python-build-standalone
commit from Runtime/Portable/python-provenance.json).
"""
import argparse
import email.parser
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from portable_runtime import audit, download, extract_python  # noqa: E402
import python_provenance  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
MINIMUM_MACOS = '14.0'
ARCHITECTURES = ('arm64', 'x86_64')
LOCKS = {
    ('dictation', 'arm64'): 'Runtime/Dictation/requirements-lock.txt',
    ('dictation', 'x86_64'): 'Runtime/Dictation/requirements-lock-x86_64.txt',
    ('speech', 'arm64'): 'Runtime/Supertonic/requirements-lock.txt',
    ('speech', 'x86_64'): 'Runtime/Supertonic/requirements-lock.txt',
}
# Never redistributable or unrelated to the workers; their presence fails the build.
FORBIDDEN_NAMES = re.compile(r'^(artifact[-_.]?tool.*|torch|torchgen|functorch|pip|setuptools|wheel)$', re.I)
FORBIDDEN_PARTS = re.compile(r'(^@oai$|^node_modules$)', re.I)
NOTICE_NAME = re.compile(r'^(LICEN[CS]E|COPYING|NOTICE|AUTHORS|COPYRIGHT|THIRD[-_]?PARTY|ThirdPartyNotices)', re.I)
COPYLEFT = re.compile(r'\b(L?GPL|MPL|EPL|CDDL|copyleft)', re.I)
# Interpreter parts that are development tools or GUI toolkits, not worker dependencies.
STRIP_STDLIB = ('test', 'idlelib', 'tkinter', 'turtledemo', 'turtle.py', 'ensurepip', 'lib2to3', 'pydoc_data',
                'config-3.12-darwin', 'site-packages')
KEEP_BIN = ('python3', 'python3.12')
# Upstream CPython component notices (python-build-standalone full-archive license set).
CPYTHON_NOTICES = {'arm64': 'docs/licenses/Python-3.12.15', 'x86_64': 'docs/licenses/Python-3.12.15-Intel'}
# Exact versions whose wheel metadata lacks a (complete) SPDX expression, reviewed against the
# shipped license files. Upgrades fall back to metadata until reviewed again.
REVIEWED_LICENSES = {
    'numpy==2.2.6': 'BSD-3-Clause', 'scipy==1.17.1': 'BSD-3-Clause', 'scipy==1.18.1': 'BSD-3-Clause',
    'safetensors==0.8.0': 'Apache-2.0', 'tokenizers==0.23.3': 'Apache-2.0', 'tiktoken==0.14.0': 'MIT',
    'transformers==5.19.0': 'Apache-2.0', 'onnxruntime==1.23.2': 'MIT', 'charset-normalizer==3.5.2': 'MIT',
    'h11==0.16.0': 'MIT', 'huggingface-hub==2.2.0': 'Apache-2.0', 'mlx==0.32.3': 'MIT', 'mlx-metal==0.32.3': 'MIT AND Apache-2.0',
    'mlx-whisper==0.4.3': 'MIT', 'pyyaml==6.0.3': 'MIT', 'tqdm==4.70.1': 'MPL-2.0 AND MIT',
}
# Wheels that ship no license file: the upstream license text kept in docs/licenses.
SUPPLEMENTAL_LICENSES = {'mlx-whisper==0.4.3': 'docs/licenses/mlx-examples-MIT.txt',
                         'tokenizers==0.23.3': 'docs/licenses/Tokenizers-0.23.3.txt'}
# Third-party native libraries vendored inside wheels (by file name prefix).
VENDORED_LICENSES = {
    'libgfortran': ('GPL-3.0-or-later WITH GCC-exception-3.1', 'https://gcc.gnu.org/git/?p=gcc.git;a=tree;f=libgfortran'),
    'libgcc_s': ('GPL-3.0-or-later WITH GCC-exception-3.1', 'https://gcc.gnu.org/git/?p=gcc.git;a=tree;f=libgcc'),
    'libquadmath': ('LGPL-2.1-or-later', 'https://gcc.gnu.org/git/?p=gcc.git;a=tree;f=libquadmath'),
}


def canonical(name):
    return re.sub(r'[-_.]+', '-', name).lower()


def sha256(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read_lock(path):
    """Return [(name, version, [hashes])] from a pip hash-locked requirements file."""
    pins, text = [], re.sub(r'\\\n', ' ', path.read_text())
    for line in text.splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r'([A-Za-z0-9][A-Za-z0-9._-]*)==([A-Za-z0-9.+!-]+)((?:\s+--hash=sha256:[0-9a-f]{64})*)', line)
        if not match:
            raise ValueError('Expected exact name==version pins with sha256 hashes: ' + line)
        pins.append((match[1], match[2], re.findall(r'sha256:([0-9a-f]{64})', match[3])))
    names = [canonical(name) for name, _, _ in pins]
    if len(names) != len(set(names)):
        raise ValueError('Duplicate pin in ' + path.name)
    for name in names:
        if FORBIDDEN_NAMES.match(name):
            raise ValueError('Forbidden package in lock: ' + name)
    return pins


def lock_header(runtime, architectures):
    return ('# Saywing ' + runtime + ' worker runtime: CPython 3.12 for macOS ' + MINIMUM_MACOS + '+ ('
            + ', '.join(architectures) + ').\n'
            '# Only packages the worker imports; installed with pip --require-hashes --no-deps\n'
            '# --only-binary :all:. Edit pins here, then refresh hashes with\n'
            '#   python3 scripts/build-python-runtime.py --runtime ' + runtime + ' --update-hashes --cache DIR\n')


def pip(*args):
    subprocess.run([sys.executable, '-m', 'pip', '--disable-pip-version-check', '--no-input', *args], check=True)


def target_args(architecture):
    # Explicit tags: pip must not pick wheels for the build host's newer macOS.
    return ['--platform', 'macosx_' + MINIMUM_MACOS.replace('.', '_') + '_' + architecture,
            '--python-version', '3.12', '--implementation', 'cp', '--abi', 'cp312',
            '--only-binary', ':all:', '--no-deps']


def wheelhouse(cache, architecture):
    path = cache / 'wheels' / architecture
    path.mkdir(parents=True, exist_ok=True)
    return path


def fetch_wheels(lock, architecture, cache):
    house = wheelhouse(cache, architecture)
    pip('download', '--require-hashes', '--cache-dir', str(cache / 'pip'), '--dest', str(house),
        *target_args(architecture), '-r', str(lock))
    return house


def wheel_for(house, name, version):
    matches = [p for p in house.glob('*.whl')
               if canonical(p.name.split('-')[0]) == canonical(name) and p.name.split('-')[1] == version]
    if len(matches) != 1:
        raise ValueError('Expected one downloaded wheel for %s %s, found %d' % (name, version, len(matches)))
    return matches[0]


def update_hashes(runtime, cache):
    """Resolve the pinned versions to macOS 14 wheels and rewrite their hashes."""
    by_file = {}
    for (kind, architecture), relative in LOCKS.items():
        if kind == runtime:
            by_file.setdefault(relative, []).append(architecture)
    for relative, architectures in by_file.items():
        path = REPO / relative
        pins = read_lock(path)
        hashes = {canonical(name): set() for name, _, _ in pins}
        with tempfile.TemporaryDirectory() as temp:
            unhashed = Path(temp) / 'pins.txt'
            unhashed.write_text(''.join(name + '==' + version + '\n' for name, version, _ in pins))
            for architecture in architectures:
                house = Path(temp) / architecture
                pip('download', '--cache-dir', str(cache / 'pip'), '--dest', str(house),
                    *target_args(architecture), '-r', str(unhashed))
                for name, version, _ in pins:
                    hashes[canonical(name)].add(sha256(wheel_for(house, name, version)))
        body = ''.join(name + '==' + version + ''.join(' \\\n    --hash=sha256:' + h for h in sorted(hashes[canonical(name)])) + '\n'
                       for name, version, _ in sorted(pins, key=lambda pin: canonical(pin[0])))
        path.write_text(lock_header(runtime, architectures) + body)
        print('Updated', relative, 'with', len(pins), 'pins', flush=True)


def strip_interpreter(python):
    for path in (python / 'bin').iterdir():
        if path.name not in KEEP_BIN:
            path.unlink()
    for name in ('include', 'share', 'lib/pkgconfig'):
        shutil.rmtree(python / name, ignore_errors=True)
    lib = python / 'lib'
    for path in lib.iterdir():
        # Tcl/Tk exist only for tkinter, which the workers never import.
        if re.match(r'^(tcl|tk|itcl|thread|libtcl|libtk)', path.name):
            shutil.rmtree(path) if path.is_dir() and not path.is_symlink() else path.unlink()
    stdlib = lib / 'python3.12'
    for name in STRIP_STDLIB:
        path = stdlib / name
        if path.is_dir() and not path.is_symlink():
            shutil.rmtree(path)
        elif path.exists():
            path.unlink()
    # tkinter is removed above; dbm is unused by the workers.
    for pattern in ('_tkinter*', '_dbm*'):
        for path in (stdlib / 'lib-dynload').glob(pattern):
            path.unlink()
    (stdlib / 'site-packages').mkdir()


def prune(root):
    # Bytecode is not shipped (workers run with -B). Package test directories stay:
    # SciPy 1.17 imports numpy._core.tests at runtime.
    for path in sorted(root.rglob('*'), key=lambda p: -len(p.parts)):
        if path.is_dir() and not path.is_symlink() and path.name == '__pycache__':
            shutil.rmtree(path)
        elif path.is_file() and path.suffix in ('.pyc', '.pyo'):
            path.unlink()


def check_forbidden(root):
    """Fail on content that must never ship (OpenAI-internal tooling, Node trees, torch, pip)."""
    for path in root.rglob('*'):
        if any(FORBIDDEN_PARTS.match(part) for part in path.relative_to(root).parts):
            raise ValueError('Forbidden runtime content: ' + str(path.relative_to(root)))
    for site in root.glob('lib/python*/site-packages'):
        for path in site.iterdir():
            name = path.name.split('-')[0] if path.suffix == '.dist-info' else path.name.removesuffix('.py')
            if FORBIDDEN_NAMES.match(canonical(name)):
                raise ValueError('Forbidden package: ' + path.name)


def installed_distributions(site):
    installed = {}
    for info in site.glob('*.dist-info'):
        metadata = email.parser.Parser().parsestr((info / 'METADATA').read_text(encoding='utf-8'))
        installed[canonical(metadata['Name'])] = (metadata, info)
    return installed


def check_installed(installed, expected):
    """expected: {canonical name: version}; the installed set must match exactly."""
    if set(installed) != set(expected):
        raise ValueError('Installed packages differ from lock: extra %s, missing %s'
                         % (sorted(set(installed) - set(expected)), sorted(set(expected) - set(installed))))
    for name, (metadata, _) in installed.items():
        if metadata['Version'] != expected[name]:
            raise ValueError('Installed version differs from lock: ' + name)


def verify_runtime(python, runtime, committed=None):
    """Check a built runtime before bundling; returns its inventory text."""
    check_forbidden(python)
    inventory = json.loads((python / 'installed-packages.json').read_text())
    if inventory.get('runtime') != runtime or not (python / 'THIRD-PARTY-NOTICES.txt').is_file():
        raise ValueError('Not a ' + runtime + ' runtime from scripts/build-python-runtime.py')
    text = inventory_text(inventory)
    check_installed(installed_distributions(python / 'lib/python3.12/site-packages'),
                    {canonical(p['name']): p['version'] for p in inventory['packages']})
    if committed is not None and json.loads(committed.read_text()) != inventory:
        raise ValueError('Runtime inventory differs from ' + committed.name + '; rebuild or commit the regenerated inventory')
    return text


def license_of(metadata):
    reviewed = REVIEWED_LICENSES.get(canonical(metadata['Name']) + '==' + metadata['Version'])
    if reviewed:
        return reviewed, 'Reviewed against shipped license files'
    expression = metadata.get('License-Expression')
    if expression:
        return expression.strip(), 'License-Expression'
    text = (metadata.get('License') or '').strip()
    if text and '\n' not in text and len(text) <= 80:
        return text, 'License'
    classifiers = [c.split('::')[-1].strip() for c in metadata.get_all('Classifier') or [] if c.startswith('License ::')]
    if classifiers:
        return ' AND '.join(classifiers), 'Classifier'
    if text:
        return 'See license files', 'License (full text)'
    return 'UNKNOWN - review required', 'none'


def record_files(info):
    record = info / 'RECORD'
    files = []
    for line in record.read_text(encoding='utf-8').splitlines():
        relative = line.rsplit(',', 2)[0].strip('"')
        if relative and not relative.startswith('..') and not Path(relative).is_absolute():
            files.append(relative)
    return files


def vendored_license(path):
    for prefix, (license_value, source) in VENDORED_LICENSES.items():
        if Path(path).name.startswith(prefix):
            return {'path': path, 'license': license_value, 'source': source}
    return {'path': path, 'license': 'Same as package'}


def package_entry(name, metadata, info, python, wheel_digest):
    site = python / 'lib/python3.12/site-packages'
    files = [f for f in record_files(info) if (site / f).is_file()]
    notices = ['lib/python3.12/site-packages/' + f for f in sorted(files)
               if NOTICE_NAME.match(Path(f).name) and Path(f).suffix.lower() not in ('.py', '.pyi', '.so', '.html', '.json')]
    supplement = SUPPLEMENTAL_LICENSES.get(name + '==' + metadata['Version'])
    if supplement:
        target = python / 'licenses' / ('LICENSE-' + name + '.txt')
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(REPO / supplement, target)
        notices.append(str(target.relative_to(python)))
    native = sorted('lib/python3.12/site-packages/' + f for f in files if f.endswith('.dylib'))
    license_value, source = license_of(metadata)
    return {'name': metadata['Name'], 'version': metadata['Version'], 'license': license_value,
            'license_source': source, 'license_files': notices,
            'vendored_native_libraries': [vendored_license(path) for path in native],
            'wheel_sha256': wheel_digest, 'source': 'https://pypi.org/project/%s/%s/' % (canonical(name), metadata['Version'])}


def interpreter_provenance(pin, architecture):
    """The python-build-standalone build behind the pinned archive (fails if unrecorded)."""
    record = json.loads((REPO / python_provenance.RECORD).read_text())
    python_provenance.check_pin(record, architecture, pin)
    full = record['architectures'][architecture]['full']
    return {'record': python_provenance.RECORD, 'source_repository': record['source']['repository'],
            'source_commit': record['source']['commit'], 'full_archive_url': full['url'],
            'full_archive_sha256': full['sha256']}


def copy_cpython_notices(python, architecture):
    files = ['lib/python3.12/LICENSE.txt']
    target = python / 'licenses/cpython'
    target.mkdir(parents=True)
    for source in sorted((REPO / CPYTHON_NOTICES[architecture]).glob('LICENSE.*.txt')):
        shutil.copyfile(source, target / source.name)
        files.append(str((target / source.name).relative_to(python)))
    return files


def write_notices(python, runtime, architecture, sbom):
    lines = ['Saywing ' + runtime + ' runtime (' + architecture + ') - third-party notices', '=' * 72, '',
             'This runtime contains CPython and only the Python packages listed below, each under its own',
             'license. License texts follow unchanged, copied from each installed distribution (or, where a',
             'wheel ships none, from the upstream project). Machine-readable inventory: installed-packages.json.',
             'Packages are installed unmodified from their published wheels except where a patch record',
             '(for example WHISPER-HARDENED-RUNTIME-PATCH.json) documents a change.', '',
             'Copyleft-licensed components and source availability', '-' * 52]
    copyleft = [p for p in sbom['packages'] if COPYLEFT.search(p['license'])]
    vendored = [(p, lib) for p in sbom['packages'] for lib in p['vendored_native_libraries'] if COPYLEFT.search(lib['license'])]
    for package in copyleft:
        lines.append('- %s %s (%s): the complete source of this exact version is published at %s.'
                     % (package['name'], package['version'], package['license'], package['source']))
    for package, lib in vendored:
        lines.append('- %s (%s), shipped unmodified as a separate dynamic library inside %s %s: source at %s; '
                     'the license text is part of the %s license file below. The library may be replaced by a '
                     'compatible build.' % (lib['path'], lib['license'], package['name'], package['version'],
                                            lib['source'], package['name']))
    if not copyleft and not vendored:
        lines.append('- None.')
    removed = 'Tcl/Tk (tkinter), dbm, ensurepip/pip, the test suite and development tools were removed.'
    python_info = sbom['python']
    lines += ['', '=' * 72, 'CPython %s (python-build-standalone %s) - %s' % (python_info['version'], python_info['release'], python_info['license']),
              python_info['url'], 'Archive SHA-256: ' + python_info['sha256'], removed,
              'Bundled component licenses follow the CPython license.', '=' * 72]
    for relative in python_info['license_files']:
        lines += ['', '--- ' + relative + ' ---', (python / relative).read_text(encoding='utf-8', errors='replace').rstrip()]
    lines.append('')
    for package in sbom['packages']:
        lines += ['=' * 72, '%s %s - %s' % (package['name'], package['version'], package['license']), package['source'], '=' * 72]
        for relative in package['license_files']:
            lines += ['', '--- ' + relative + ' ---', (python / relative).read_text(encoding='utf-8', errors='replace').rstrip()]
        lines.append('')
    (python / 'THIRD-PARTY-NOTICES.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')


def inventory_text(sbom):
    text = json.dumps(sbom, indent=2) + '\n'
    for value in re.findall(r'"((?:[^"\\]|\\.)*)"', text):
        if value.startswith(('/', '~')) or re.match(r'^[A-Za-z]:\\', value) or '/Users/' in value:
            raise ValueError('Inventory must not contain absolute paths: ' + value)
    return text


def build(runtime, architecture, output, cache):
    lock = REPO / LOCKS[(runtime, architecture)]
    pins = read_lock(lock)
    if any(not hashes for _, _, hashes in pins):
        raise ValueError('Every pin needs a hash; run --update-hashes first')
    if output.exists():
        raise ValueError('Refusing existing output')
    pin = json.loads((REPO / 'Runtime/Portable/python.json').read_text())[architecture]
    interpreter = interpreter_provenance(pin, architecture)
    archive = download(pin, cache)
    house = fetch_wheels(lock, architecture, cache)
    staging = output.with_name(output.name + '.staging')
    if staging.exists():
        raise ValueError('Refusing existing staging directory')
    staging.mkdir(parents=True)
    python = extract_python(archive, staging)
    strip_interpreter(python)
    site = python / 'lib/python3.12/site-packages'
    pip('install', '--no-index', '--find-links', str(house), '--require-hashes', '--no-compile',
        '--target', str(site), *target_args(architecture), '-r', str(lock))
    shutil.rmtree(site / 'bin', ignore_errors=True)  # console entry points are development tools
    prune(python)
    check_forbidden(python)
    installed = installed_distributions(site)
    check_installed(installed, {canonical(name): version for name, version, _ in pins})
    digests = {canonical(name): sha256(wheel_for(house, name, version)) for name, version, _ in pins}
    sbom = {'format': 'saywing-runtime-inventory/1', 'runtime': runtime, 'architecture': architecture,
            'minimum_macos': MINIMUM_MACOS, 'lock': LOCKS[(runtime, architecture)],
            'python': {'name': 'CPython', 'version': pin['version'], 'release': pin['release'], 'license': 'PSF-2.0',
                       'provider': pin['provider'], 'url': pin['url'], 'sha256': pin['sha256'],
                       'license_files': copy_cpython_notices(python, architecture)},
            'packages': [package_entry(name, metadata, info, python, digests[name])
                         for name, (metadata, info) in sorted(installed.items())]}
    missing = [p['name'] for p in sbom['packages'] if not p['license_files']]
    if missing:
        raise ValueError('No license text for: ' + ', '.join(missing))
    (python / 'installed-packages.json').write_text(inventory_text(sbom))
    write_notices(python, runtime, architecture, sbom)
    native = audit(python, architecture, MINIMUM_MACOS)
    (python / 'runtime-provenance.json').write_text(json.dumps({
        'runtime': runtime, 'architecture': architecture, 'lock': LOCKS[(runtime, architecture)],
        'lock_sha256': sha256(lock), 'python': pin, 'python_provenance': interpreter,
        'pip': subprocess.run([sys.executable, '-m', 'pip', '--version'], capture_output=True, text=True, check=True).stdout.split(' from ')[0],
        'native_audit': native}, indent=2) + '\n')
    python.rename(output)
    staging.rmdir()
    print('Built minimal %s runtime (%s): %s' % (runtime, architecture, output), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--runtime', choices=['dictation', 'speech'], required=True)
    parser.add_argument('--architecture', choices=ARCHITECTURES)
    parser.add_argument('--cache', type=Path, required=True, help='Download cache (archives are re-verified on use)')
    parser.add_argument('--output', type=Path, help='New runtime directory')
    parser.add_argument('--update-hashes', action='store_true', help='Refresh lock hashes for the pinned versions')
    args = parser.parse_args()
    cache = args.cache.resolve()
    if args.update_hashes:
        update_hashes(args.runtime, cache)
        return
    if not args.architecture or not args.output:
        parser.error('--architecture and --output are required to build')
    build(args.runtime, args.architecture, args.output.resolve(), cache)


if __name__ == '__main__':
    main()
