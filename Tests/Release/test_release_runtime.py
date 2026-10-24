import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'scripts'))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


assembler = load('assemble_release_runtime', REPO / 'scripts/assemble-release-runtime.py')
release = load('release', REPO / 'scripts/release.py')
HF_REVISION = re.compile(r'^https://huggingface\.co/(datasets/)?[^/]+/[^/]+/resolve/[0-9a-f]{40}/')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class InputPinTests(unittest.TestCase):
    def test_every_input_is_https_size_and_sha256_pinned(self):
        for architecture in ['arm64', 'x86_64']:
            with self.subTest(architecture=architecture):
                pins = assembler.input_pins(architecture)
                for name, item in pins.items():
                    self.assertTrue(item['url'].startswith('https://'), name)
                    self.assertRegex(item['sha256'], '^[0-9a-f]{64}$', name)
                    self.assertGreater(item['bytes'], 0, name)
                    if 'huggingface.co' in item['url']:
                        self.assertRegex(item['url'], HF_REVISION, name)
                # Only the bundled default models; optional models stay user-installed.
                self.assertFalse(any('qwen' in item['url'].lower() or 'large-v3/' in item['url'] for item in pins.values()))
                self.assertEqual(len([n for n in pins if n.startswith('speech/')]), 10)
                self.assertEqual(sorted(n for n in pins if n.startswith('demo/')), ['demo/de_de', 'demo/en_us'])

    def test_architecture_selects_the_matching_whisper_backend(self):
        arm, intel = assembler.input_pins('arm64'), assembler.input_pins('x86_64')
        manifest = json.loads((REPO / 'Runtime/Dictation/whisper-turbo-manifest.json').read_text())
        weights = arm['whisper/weights.safetensors']
        self.assertTrue(weights['url'].endswith('/' + manifest['revision'] + '/model.safetensors'))
        self.assertEqual(weights['sha256'], manifest['files'][2]['verified_sha256'])
        self.assertNotIn('whisper-cpp-source', arm)
        self.assertNotIn('whisper/weights.safetensors', intel)
        self.assertIn('ggml/ggml-large-v3-turbo-q5_0.bin', intel)
        self.assertIn('whisper-cpp-source', intel)
        self.assertIn('whisper/LICENSE-OpenAI', intel)
        with self.assertRaises(ValueError):
            assembler.input_pins('ppc')

    def test_speech_files_need_sha256_and_helper_must_match_model_manifest(self):
        manifest = json.loads(assembler.SPEECH_MANIFEST.read_text())
        inputs = json.loads(assembler.RELEASE_INPUTS.read_text())
        with tempfile.TemporaryDirectory() as temp:
            weak = Path(temp) / 'weak.json'
            weak.write_text(json.dumps({**manifest, 'files': [{k: v for k, v in manifest['files'][0].items() if k != 'sha256'}]}))
            with patch.object(assembler, 'SPEECH_MANIFEST', weak), self.assertRaisesRegex(ValueError, 'SHA-256'):
                assembler.speech_pins()
            inputs['supertonic_upstream']['files'][0]['sha256'] = '0' * 64
            changed = Path(temp) / 'inputs.json'
            changed.write_text(json.dumps(inputs))
            with patch.object(assembler, 'RELEASE_INPUTS', changed), self.assertRaisesRegex(ValueError, 'helper'):
                assembler.speech_pins()

    def test_source_archives_are_not_release_inputs(self):
        # They are archived by the publish job and offered in writing, not bundled (ADR 0007).
        for architecture in ['arm64', 'x86_64']:
            self.assertFalse([name for name in assembler.input_pins(architecture) if name.startswith('source/')])

    def test_revisions_must_be_full_commits(self):
        with self.assertRaises(ValueError):
            assembler.hf_url('Supertone/supertonic-3', 'main', 'LICENSE')


class DownloadVerificationTests(unittest.TestCase):
    def test_fetch_keeps_only_verified_bytes_without_network(self):
        good, bad = b'pinned bytes', b'tampered bytes'
        pins = {'a': assembler.pin('a', 'https://example.invalid/a', len(good), sha256(good)),
                'b': assembler.pin('b', 'https://example.invalid/b', len(bad), sha256(b'expected bytes'))}
        served = {'https://example.invalid/a': good, 'https://example.invalid/b': bad}

        def curl(command, check):
            Path(command[command.index('--output') + 1]).write_bytes(served[command[-1]])
            for flag in ['--fail', '--proto', '--proto-redir']:
                self.assertIn(flag, command)
        with tempfile.TemporaryDirectory() as temp, patch.object(assembler.portable.subprocess, 'run', side_effect=curl):
            cache = Path(temp)
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                assembler.fetch(pins, cache)
            self.assertEqual((cache / sha256(good)).read_bytes(), good)
            self.assertEqual(sorted(p.name for p in cache.iterdir()), [sha256(good)])
            # A cached entry is re-verified on every use.
            (cache / sha256(good)).write_bytes(b'changed in cache')
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                assembler.fetch({'a': pins['a']}, cache)

    def test_pins_reject_plain_http_and_incomplete_hashes(self):
        with self.assertRaises(ValueError):
            assembler.pin('x', 'http://example.invalid/x', 1, '0' * 64)
        with self.assertRaises(ValueError):
            assembler.pin('x', 'https://example.invalid/x', 1, 'abc')


class DemoExtractionTests(unittest.TestCase):
    def archive(self, path, members):
        with tarfile.open(path, 'w:gz') as tar:
            for name, data in members.items():
                info = tarfile.TarInfo(name)
                if data is None:
                    info.type, info.linkname = tarfile.SYMTYPE, '/etc/passwd'
                    tar.addfile(info)
                else:
                    info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))

    def manifest(self, temp, clips):
        path = Path(temp) / 'demo-manifest.json'
        path.write_text(json.dumps(clips))
        return path

    def test_only_the_pinned_members_are_extracted_and_verified(self):
        german, english = b'RIFF-de', b'RIFF-en'
        clips = [{'id': 'de_de-1.wav', 'file': 'Deutsch.wav', 'source_member': 'test/1.wav', 'bytes': len(german), 'sha256': sha256(german)},
                 {'id': 'en_us-2.wav', 'file': 'English.wav', 'source_member': 'test/2.wav', 'bytes': len(english), 'sha256': sha256(english)}]
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.archive(base / 'de.tar.gz', {'test/0.wav': b'other', 'test/1.wav': german})
            self.archive(base / 'en.tar.gz', {'./test/2.wav': english})
            manifest = self.manifest(temp, clips)
            with patch.object(assembler, 'DEMO_MANIFEST', manifest):
                assembler.extract_demos({'de_de': base / 'de.tar.gz', 'en_us': base / 'en.tar.gz'}, base / 'Demos')
            self.assertEqual((base / 'Demos/Deutsch.wav').read_bytes(), german)
            self.assertEqual((base / 'Demos/English.wav').read_bytes(), english)
            self.assertEqual(json.loads((base / 'Demos/manifest.json').read_text()), clips)
            self.assertEqual(sorted(p.name for p in (base / 'Demos').iterdir()), ['Deutsch.wav', 'English.wav', 'manifest.json'])

    def test_changed_missing_or_linked_members_fail(self):
        clip = {'id': 'de_de-1.wav', 'file': 'Deutsch.wav', 'source_member': 'test/1.wav', 'bytes': 3, 'sha256': sha256(b'abc')}
        cases = {'differs': {'test/1.wav': b'abd'}, 'missing': {'test/9.wav': b'abc'}, 'regular file': {'test/1.wav': None}}
        for message, members in cases.items():
            with self.subTest(message), tempfile.TemporaryDirectory() as temp:
                base = Path(temp)
                self.archive(base / 'de.tar.gz', members)
                with patch.object(assembler, 'DEMO_MANIFEST', self.manifest(temp, [clip])), self.assertRaisesRegex(ValueError, message):
                    assembler.extract_demos({'de_de': base / 'de.tar.gz'}, base / 'Demos')
                self.assertFalse((base / 'Demos/Deutsch.wav').exists())

    def test_committed_demo_manifest_names_two_fleurs_test_clips(self):
        clips = json.loads(assembler.DEMO_MANIFEST.read_text())
        archives = json.loads(assembler.RELEASE_INPUTS.read_text())['demo_audio']['archives']
        self.assertEqual([c['file'] for c in clips], ['Deutsch.wav', 'English.wav'])
        for clip in clips:
            self.assertIn(clip['id'].split('-', 1)[0], archives)
            self.assertRegex(clip['sha256'], '^[0-9a-f]{64}$')

    def test_fleurs_attribution_matches_the_release_bundler(self):
        self.assertIn(assembler.FLEURS_ATTRIBUTION, (REPO / 'scripts/bundle-dictation-runtime.py').read_text())


class AssemblyTests(unittest.TestCase):
    def fake_python(self, root, runtime='speech', architecture='arm64'):
        (root / 'bin').mkdir(parents=True)
        (root / 'bin/python3').write_bytes(b'interpreter')
        (root / 'THIRD-PARTY-NOTICES.txt').write_text('notices\n')
        (root / 'installed-packages.json').write_text(json.dumps({
            'runtime': runtime, 'architecture': architecture, 'lock': 'Runtime/Supertonic/requirements-lock.txt',
            'packages': [{'name': 'numpy', 'version': '2.2.6'}]}))
        return root

    def test_speech_receipt_covers_runtime_worker_helper_and_model(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            python = self.fake_python(base / 'python')
            fetched = {}
            for name in [n for n in assembler.speech_pins()]:
                fetched[name] = base / 'downloads' / name
                fetched[name].parent.mkdir(parents=True, exist_ok=True)
                fetched[name].write_bytes(name.encode())
            resources = base / 'Resources'
            assembler.assemble_speech(resources, python, fetched, public=True)
            speech = resources / 'Speech'
            receipt_path = speech / 'SupertonicRuntime/installation-receipt.json'
            receipt = release.verify_receipt(speech, receipt_path)
            for relative in ['SupertonicRuntime/worker.py', 'SupertonicRuntime/upstream/helper.py', 'SupertonicRuntime/python/bin/python3',
                             'SupertonicRuntime/model-manifest.json', 'DevelopmentModels/supertonic-3-3cadd1ee/onnx/vocoder.onnx']:
                self.assertIn(relative, receipt['files'])
            self.assertEqual(receipt['model_revision'], json.loads(assembler.SPEECH_MANIFEST.read_text())['revision'])
            self.assertEqual(receipt['purpose'], assembler.PUBLIC_PURPOSE)
            (speech / 'SupertonicRuntime/upstream/helper.py').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                release.verify_receipt(speech, receipt_path)

    def test_speech_runtime_with_forbidden_content_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            python = self.fake_python(base / 'python')
            (python / 'lib/python3.12/site-packages/torch').mkdir(parents=True)
            with self.assertRaisesRegex(ValueError, 'Forbidden'):
                assembler.assemble_speech(base / 'Resources', python, {}, public=True)
            self.assertFalse((base / 'Resources').exists())

    def test_intel_bridge_must_match_its_build_provenance(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            self.fake_python(base / 'inputs/Python', 'dictation', 'x86_64')
            bridge = base / 'libsaywing-whisper.dylib'
            bridge.write_bytes(b'bridge')
            source = json.loads(assembler.WHISPER_CPP_SOURCE.read_text())
            for proof in [{'binary_sha256': '0' * 64, 'source': source, 'architecture': 'x86_64'},
                          {'binary_sha256': sha256(b'bridge'), 'source': {**source, 'revision': 'other'}, 'architecture': 'x86_64'},
                          {'binary_sha256': sha256(b'bridge'), 'source': source, 'architecture': 'arm64'}]:
                with self.subTest(proof=proof):
                    bridge.with_suffix('.provenance.json').write_text(json.dumps(proof))
                    with patch.object(assembler.builder, 'verify_runtime', return_value='{}'), \
                         self.assertRaisesRegex(ValueError, 'provenance'):
                        assembler.assemble_dictation_x86_64(base / 'Resources', base / 'inputs', {}, bridge, public=True)
                    self.assertFalse((base / 'Resources/Dictation').exists())

    def test_existing_output_or_work_directory_is_refused_before_downloading(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(assembler, 'fetch') as fetch:
            base = Path(temp)
            (base / 'Saywing.app').mkdir()
            with self.assertRaises(ValueError):
                assembler.assemble('arm64', base / 'cache', base / 'Saywing.app', base / 'work', True)
            (base / 'work').mkdir()
            with self.assertRaises(ValueError):
                assembler.assemble('arm64', base / 'cache', base / 'new/Saywing.app', base / 'work', True)
            with self.assertRaises(ValueError):
                assembler.assemble('arm64', base / 'cache', base / 'Other.app', base / 'fresh', True)
            fetch.assert_not_called()


if __name__ == '__main__':
    unittest.main()
