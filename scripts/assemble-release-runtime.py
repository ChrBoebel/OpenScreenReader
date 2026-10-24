#!/usr/bin/env python3
"""Assemble the runtime input for scripts/release.py from pinned public sources.

Build-time network only. Every input is pinned in the repository and verified
(size and SHA-256) before it is used:

- CPython and wheels: scripts/build-python-runtime.py (Runtime/Portable/python.json, the locks);
- Supertonic 3 model: docs/research/supertonic-comparison-manifest.json (Hugging Face revision);
- Supertonic helper/license and FLEURS demo archives: Runtime/Portable/release-inputs.json;
- Whisper Turbo: Runtime/Dictation/whisper-turbo-manifest.json (MLX, arm64) or
  Runtime/Portable/whisper-turbo-cpp-manifest.json plus whisper-cpp-source.json (Intel);
- corresponding sources: docs/licenses/native-corresponding-sources.json.

  python3 scripts/assemble-release-runtime.py --architecture arm64 --public-release \\
      --cache .build/runtime-cache --output .build/runtime-arm64/Saywing.app

The output is a new Saywing.app containing only Contents/Resources (Speech/,
Dictation/, portable-runtime.json, CorrespondingSource/ and notices). Pass it to
scripts/release.py --runtime-app. Nothing here signs, notarizes or publishes.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

SCRIPTS = Path(__file__).resolve().parent
REPO = SCRIPTS.parent
sys.path.insert(0, str(SCRIPTS))
import portable_runtime as portable  # noqa: E402

HF = 'https://huggingface.co'
SPEECH_MANIFEST = REPO / 'docs/research/supertonic-comparison-manifest.json'
RELEASE_INPUTS = REPO / 'Runtime/Portable/release-inputs.json'
DEMO_MANIFEST = REPO / 'Runtime/Dictation/demo-manifest.json'
CORRESPONDING_SOURCES = REPO / 'docs/licenses/native-corresponding-sources.json'
WHISPER_CPP_SOURCE = REPO / 'Runtime/Portable/whisper-cpp-source.json'
PUBLIC_PURPOSE = 'Saywing release build; components are redistributed under the licenses in THIRD-PARTY-NOTICES.txt'
DEVELOPMENT_PURPOSE = 'Local development build; not notarized'
# Same text as scripts/bundle-dictation-runtime.py (checked by Tests/Release).
FLEURS_ATTRIBUTION = """Demo audio (Dictation/Demos)
============================
Deutsch.wav and English.wav are unchanged recordings from Google FLEURS
(https://huggingface.co/datasets/google/fleurs, revision 70bb2e84b976b7e960aa89f1c648e09c59f894dd),
(c) Google, licensed under Creative Commons Attribution 4.0 International
(https://creativecommons.org/licenses/by/4.0/). Original IDs, transcripts, sizes and
SHA-256 hashes are listed in Demos/manifest.json.
"""
DICTATION_NOTICES = {'whisper-turbo-dictation.md': 'WHISPER-TURBO-NOTICES.md',
                     'whisper-large-v3-dictation.md': 'WHISPER-LARGE-V3-NOTICES.md',
                     'qwen-dictation-runtime.md': 'MODEL-AND-RUNTIME-NOTICES.md'}


def load_script(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


builder = load_script('build_python_runtime', SCRIPTS / 'build-python-runtime.py')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def hf_url(repository, revision, path, dataset=False):
    if len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
        raise ValueError('Hugging Face inputs must be pinned to a full commit revision')
    return '%s/%s%s/resolve/%s/%s' % (HF, 'datasets/' if dataset else '', repository, revision, path)


def pin(filename, url, size, sha256):
    if not url.startswith('https://') or not isinstance(size, int) or size <= 0 \
            or len(sha256) != 64 or any(c not in '0123456789abcdef' for c in sha256):
        raise ValueError('Incomplete pin: ' + filename)
    return {'filename': filename, 'url': url, 'bytes': size, 'sha256': sha256}


def speech_pins():
    manifest = read_json(SPEECH_MANIFEST)
    pins = {}
    for entry in manifest['files']:
        if 'sha256' not in entry:
            raise ValueError('Speech model file needs a SHA-256 pin: ' + entry['path'])
        pins['speech/' + entry['path']] = pin(entry['path'], hf_url(manifest['repository'], manifest['revision'], entry['path']),
                                              entry['bytes'], entry['sha256'])
    upstream = read_json(RELEASE_INPUTS)['supertonic_upstream']
    source = manifest['runtime_source']
    if upstream['repository'] != source['repository'] or upstream['revision'] != source['revision']:
        raise ValueError('Supertonic helper pins disagree with the model manifest')
    for entry in upstream['files']:
        url = 'https://raw.githubusercontent.com/%s/%s/%s' % (
            upstream['repository'].removeprefix('https://github.com/'), upstream['revision'], entry['source'])
        pins['upstream/' + entry['path']] = pin(entry['path'], url, entry['bytes'], entry['sha256'])
    helper = pins['upstream/helper.py']
    if (helper['bytes'], helper['sha256']) != (source['bytes'], source['sha256']):
        raise ValueError('Supertonic helper pin differs from the model manifest')
    return pins


def whisper_pins(architecture):
    turbo = read_json(REPO / 'Runtime/Dictation/whisper-turbo-manifest.json')
    pins = {}
    for entry in turbo['files']:
        url = entry.get('source') or hf_url(turbo['repo'], turbo['revision'], entry.get('source_filename', entry['rfilename']))
        if architecture == 'arm64' or entry['rfilename'].startswith('LICENSE'):
            pins['whisper/' + entry['rfilename']] = pin(entry['rfilename'], url, entry['size'], entry['verified_sha256'])
    if architecture == 'x86_64':
        cpp = read_json(REPO / 'Runtime/Portable/whisper-turbo-cpp-manifest.json')
        for entry in cpp['files']:
            pins['ggml/' + entry['rfilename']] = pin(entry['rfilename'], hf_url(cpp['repo'], cpp['revision'], entry['rfilename']),
                                                     entry['size'], entry['verified_sha256'])
        source = read_json(WHISPER_CPP_SOURCE)
        pins['whisper-cpp-source'] = pin('whisper.cpp-' + source['version'] + '.tar.gz', source['url'], source['bytes'], source['sha256'])
    return pins


def demo_pins():
    demo = read_json(RELEASE_INPUTS)['demo_audio']
    return {'demo/' + locale: pin(locale + '-' + Path(item['path']).name, hf_url(demo['dataset'], demo['revision'], item['path'], dataset=True),
                                  item['bytes'], item['sha256'])
            for locale, item in demo['archives'].items()}


def corresponding_source_pins():
    pins = {}
    for record in read_json(CORRESPONDING_SOURCES):
        if Path(record['file']).name != record['file']:
            raise ValueError('Invalid corresponding-source filename')
        pins['source/' + record['file']] = pin(record['file'], record['url'], record['bytes'], record['sha256'])
    return pins


def input_pins(architecture):
    if architecture not in builder.ARCHITECTURES:
        raise ValueError('Unsupported architecture')
    return {**speech_pins(), **whisper_pins(architecture), **demo_pins(), **corresponding_source_pins()}


def fetch(pins, cache):
    """Download (or reuse from the content-addressed cache) and verify every pin."""
    return {name: portable.download(item, cache) for name, item in sorted(pins.items())}


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def read_member(archive, name):
    # The archive itself was verified against its pin before this is called.
    with tarfile.open(archive, 'r:gz') as tar:
        for member in tar:
            if member.name.removeprefix('./') == name:
                if not member.isfile():
                    raise ValueError('Demo member is not a regular file: ' + name)
                return tar.extractfile(member).read()
    raise ValueError('Demo member missing: ' + name)


def extract_demos(archives, target):
    """archives: {locale: verified archive path}. Writes the clips and their manifest."""
    target.mkdir(parents=True)
    for clip in read_json(DEMO_MANIFEST):
        name = clip['file']
        if Path(name).name != name or not name.endswith('.wav'):
            raise ValueError('Invalid demo filename')
        data = read_member(archives[clip['id'].split('-', 1)[0]], clip['source_member'])
        if len(data) != clip['bytes'] or sha256_bytes(data) != clip['sha256']:
            raise ValueError('Demo clip differs from its pin: ' + name)
        (target / name).write_bytes(data)
    shutil.copyfile(DEMO_MANIFEST, target / 'manifest.json')


def copy_file(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def copy_tree(source, target):
    shutil.copytree(source, target, symlinks=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))


def write_receipt(root, receipt, **fields):
    files = {}
    for path in sorted(root.rglob('*')):
        if path == receipt or path.is_symlink() or not path.is_file():
            continue
        files[str(path.relative_to(root))] = portable.digest(path)
    if not files:
        raise ValueError('Empty runtime receipt')
    receipt.write_text(json.dumps({**fields, 'files': files}, indent=2) + '\n')


def assemble_speech(resources, python, fetched, public):
    manifest = read_json(SPEECH_MANIFEST)
    builder.check_forbidden(python)
    speech = resources / 'Speech'
    runtime = speech / 'SupertonicRuntime'
    model = speech / 'DevelopmentModels' / ('supertonic-3-' + manifest['revision'][:8])
    copy_tree(python, runtime / 'python')
    copy_file(REPO / 'Runtime/Supertonic/worker.py', runtime / 'worker.py')
    copy_file(SPEECH_MANIFEST, runtime / 'model-manifest.json')
    for name, path in fetched.items():
        if name.startswith('upstream/'):
            copy_file(path, runtime / name)
        elif name.startswith('speech/'):
            copy_file(path, model / name.removeprefix('speech/'))
    inventory = read_json(python / 'installed-packages.json')
    write_receipt(speech, runtime / 'installation-receipt.json',
                  purpose=PUBLIC_PURPOSE if public else DEVELOPMENT_PURPOSE,
                  model_revision=manifest['revision'], source_revision=manifest['runtime_source']['revision'],
                  runtime_lock=inventory['lock'],
                  packages=['%s==%s' % (p['name'], p['version']) for p in inventory['packages']])


def stage_whisper_turbo(fetched, target):
    target.mkdir(parents=True)
    for name, path in fetched.items():
        if name.startswith('whisper/'):
            copy_file(path, target / name.removeprefix('whisper/'))
    return target


def assemble_dictation_arm64(resources, inputs, whisper, public, work):
    """Run the release bundler (scripts/bundle-dictation-runtime.py) on a staging bundle.

    The bundler verifies the runtime against Runtime/Dictation/installed-packages.json,
    applies the hardened-runtime patch and writes the receipt. It only creates
    Contents/Resources/Dictation; the placeholder executable satisfies its app check
    and is never copied into the release.
    """
    stage = work / 'bundle/Saywing.app'
    (stage / 'Contents/MacOS').mkdir(parents=True)
    (stage / 'Contents/MacOS/Saywing').write_text('Staging placeholder for scripts/bundle-dictation-runtime.py\n')
    run(sys.executable, SCRIPTS / 'bundle-dictation-runtime.py', stage, inputs, '--whisper-model', whisper,
        '--public-release' if public else '--development-only', '--defer-app-signing')
    shutil.move(str(stage / 'Contents/Resources/Dictation'), str(resources / 'Dictation'))


def build_whisper_cpp(archive, build):
    run('/bin/bash', SCRIPTS / 'build-whisper-cpp.sh', archive, build, 'x86_64')
    return build / 'libsaywing-whisper.dylib'


def assemble_dictation_x86_64(resources, inputs, fetched, bridge, public):
    python = inputs / 'Python'
    inventory = builder.verify_runtime(python, 'dictation')
    if read_json(python / 'installed-packages.json')['architecture'] != 'x86_64':
        raise ValueError('Intel dictation needs an x86_64 runtime')
    cpp_manifest = REPO / 'Runtime/Portable/whisper-turbo-cpp-manifest.json'
    proof_path = bridge.with_suffix('.provenance.json')
    proof = read_json(proof_path)
    if proof['binary_sha256'] != portable.digest(bridge) or proof['source'] != read_json(WHISPER_CPP_SOURCE) \
            or proof['architecture'] != 'x86_64':
        raise ValueError('Whisper bridge build provenance mismatch')
    d = resources / 'Dictation'
    copy_tree(python, d / 'Python')
    copy_tree(inputs / 'Demos', d / 'Demos')
    for name in ['LICENSE-OpenAI', 'LICENSE-Apache-2.0']:
        copy_file(fetched['whisper/' + name], d / 'Licenses' / name)
    for name in ['worker.py', 'worker.sb', 'model-manifest.json', 'whisper-large-v3-manifest.json', 'requirements-lock-x86_64.txt']:
        copy_file(REPO / 'Runtime/Dictation' / name, d / name)
    copy_file(cpp_manifest, d / 'whisper-turbo-manifest.json')
    for name, path in fetched.items():
        if name.startswith('ggml/'):
            copy_file(path, d / 'WhisperTurbo' / name.removeprefix('ggml/'))
    copy_file(fetched['whisper/LICENSE-OpenAI'], d / 'WhisperTurbo/LICENSE-OpenAI')
    copy_file(bridge, d / 'WhisperCpp/libsaywing-whisper.dylib')
    copy_file(REPO / 'Runtime/Portable/LICENSE-whisper.cpp', d / 'WhisperCpp/LICENSE-whisper.cpp')
    copy_file(WHISPER_CPP_SOURCE, d / 'WhisperCpp/whisper-cpp-source.json')
    copy_file(proof_path, d / 'WhisperCpp/build-provenance.json')
    # Only Whisper Turbo has an Intel backend; the app hides the other models.
    (d / 'runtime-backends.json').write_text(json.dumps({'whisper-turbo': 'whisper.cpp'}, indent=2) + '\n')
    for source, target in DICTATION_NOTICES.items():
        copy_file(REPO / 'docs/research' / source, d / target)
    (d / 'installed-packages.json').write_text(inventory)
    (d / 'THIRD-PARTY-NOTICES.txt').write_text(
        (python / 'THIRD-PARTY-NOTICES.txt').read_text(encoding='utf-8') + '\n' + FLEURS_ATTRIBUTION, encoding='utf-8')
    worker = load_script('dictation_worker', REPO / 'Runtime/Dictation/worker.py')
    worker.verify_model(d, 'whisper-turbo')
    write_receipt(d, d / 'installation-receipt.json', purpose=PUBLIC_PURPOSE if public else DEVELOPMENT_PURPOSE,
                  bundled_models={'whisper-turbo-manifest.json': read_json(cpp_manifest)['revision']})


def finish(resources, architecture, fetched):
    (resources / 'portable-runtime.json').write_text(json.dumps({
        'architecture': architecture, 'minimum_macos': builder.MINIMUM_MACOS,
        'status': 'Built from pinned public inputs (docs/runtime-build.md); clean macOS 14 and native Intel tests remain release gates',
    }, indent=2) + '\n')
    copy_file(REPO / 'LICENSE', resources / 'LICENSE-Saywing')
    # scripts/release.py removes this notice for approved public releases and rewrites it otherwise.
    (resources / 'DEVELOPMENT-PREVIEW.txt').write_text('Runtime input assembled by scripts/assemble-release-runtime.py.\n')
    for name, path in fetched.items():
        if name.startswith('source/'):
            copy_file(path, resources / 'CorrespondingSource' / name.removeprefix('source/'))
    portable.audit(resources, architecture, builder.MINIMUM_MACOS)


def assemble(architecture, cache, output, work, public):
    if output.name != 'Saywing.app' or output.exists():
        raise ValueError('Output must be a new Saywing.app path')
    if work.exists():
        raise ValueError('Refusing existing work directory')
    fetched = fetch(input_pins(architecture), cache)  # every download is verified before anything is built
    inputs = work / 'dictation-inputs'
    builder.build('speech', architecture, work / 'speech-python', cache)
    builder.build('dictation', architecture, inputs / 'Python', cache)
    extract_demos({name.removeprefix('demo/'): path for name, path in fetched.items() if name.startswith('demo/')},
                  inputs / 'Demos')
    app = work / 'Saywing.app'
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True)
    assemble_speech(resources, work / 'speech-python', fetched, public)
    if architecture == 'arm64':
        assemble_dictation_arm64(resources, inputs, stage_whisper_turbo(fetched, work / 'WhisperTurbo'), public, work)
    else:
        bridge = build_whisper_cpp(fetched['whisper-cpp-source'], work / 'whisper-cpp')
        assemble_dictation_x86_64(resources, inputs, fetched, bridge, public)
    finish(resources, architecture, fetched)
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(app), str(output))
    shutil.rmtree(work)
    print('Assembled %s runtime input: %s' % (architecture, output), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--architecture', choices=builder.ARCHITECTURES, required=True)
    parser.add_argument('--cache', type=Path, required=True, help='Content-addressed download cache; entries are re-verified on use')
    parser.add_argument('--output', type=Path, required=True, help='New Saywing.app path')
    parser.add_argument('--work', type=Path, help='New scratch directory (default: beside the output); removed on success')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--public-release', action='store_true', help='Input to a signed, notarized public release')
    mode.add_argument('--development-only', action='store_true', help='Local or candidate build')
    args = parser.parse_args()
    output = args.output.resolve()
    work = (args.work or output.parent / 'saywing-runtime-work').resolve()
    assemble(args.architecture, args.cache.resolve(), output, work, args.public_release)


if __name__ == '__main__':
    main()
