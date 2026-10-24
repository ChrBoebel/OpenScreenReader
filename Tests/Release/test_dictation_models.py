import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('dictation_models', Path(__file__).resolve().parents[2] / 'scripts/dictation_models.py')
models = importlib.util.module_from_spec(spec)
spec.loader.exec_module(models)
REPO = Path(__file__).resolve().parents[2]


def entry(name, data, **extra):
    return {'rfilename': name, 'size': len(data), 'verified_sha256': hashlib.sha256(data).hexdigest(), **extra}


class QwenModelBundleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.model, self.licenses = root / 'Model', root / 'Licenses'
        self.model.mkdir(); self.licenses.mkdir()
        (self.model / 'config.json').write_bytes(b'{}')
        (self.model / '.gitattributes').write_bytes(b'*.safetensors lfs')
        (self.model / 'VERIFIED.json').write_bytes(b'local verification note')
        (self.licenses / 'LICENSE-Apache-2.0').write_bytes(b'Apache License 2.0')
        self.manifest = {'files': [
            {'rfilename': '.gitattributes', 'size': 17},
            entry('config.json', b'{}'),
            entry('LICENSE-Apache-2.0', b'Apache License 2.0', source='https://www.apache.org/licenses/LICENSE-2.0.txt')]}
        self.target = root / 'Bundle/Model'
        self.target.parent.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def test_only_manifest_files_are_copied_and_licenses_come_from_the_bundle(self):
        copied = models.copy_model(self.manifest, self.model, self.licenses, self.target)
        self.assertEqual(copied, ['config.json', 'LICENSE-Apache-2.0'])
        self.assertEqual(sorted(path.name for path in self.target.iterdir()), ['LICENSE-Apache-2.0', 'config.json'])
        self.assertEqual((self.target / 'LICENSE-Apache-2.0').read_bytes(), b'Apache License 2.0')

    def test_license_entry_is_not_required_in_the_model_directory(self):
        self.assertFalse((self.model / 'LICENSE-Apache-2.0').exists())
        models.model_plan(self.manifest, self.model, self.licenses)

    def test_missing_or_changed_bundled_license_is_rejected(self):
        (self.licenses / 'LICENSE-Apache-2.0').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'verification failed'):
            models.model_plan(self.manifest, self.model, self.licenses)
        (self.licenses / 'LICENSE-Apache-2.0').unlink()
        with self.assertRaises(FileNotFoundError):
            models.model_plan(self.manifest, self.model, self.licenses)

    def test_license_in_model_directory_does_not_replace_the_bundled_text(self):
        (self.model / 'LICENSE-Apache-2.0').write_bytes(b'Apache License 2.0')
        (self.licenses / 'LICENSE-Apache-2.0').unlink()
        with self.assertRaises(FileNotFoundError):
            models.model_plan(self.manifest, self.model, self.licenses)

    def test_changed_model_file_and_escaping_paths_are_rejected(self):
        (self.model / 'config.json').write_bytes(b'{"changed": 1}')
        with self.assertRaisesRegex(ValueError, 'verification failed'):
            models.model_plan(self.manifest, self.model, self.licenses)
        for name in ['../outside', '/etc/passwd']:
            with self.assertRaisesRegex(ValueError, 'escapes'):
                models.model_plan({'files': [entry(name, b'x')]}, self.model, self.licenses)
        with self.assertRaisesRegex(ValueError, 'escapes'):
            models.model_plan({'files': [entry('sub/LICENSE', b'x', source='https://example.org')]}, self.model, self.licenses)

    def test_existing_target_is_never_merged(self):
        self.target.mkdir()
        with self.assertRaises(FileExistsError):
            models.copy_model(self.manifest, self.model, self.licenses, self.target)

    def test_repository_manifest_entries_are_installable(self):
        manifest = json.loads((REPO / 'Runtime/Dictation/model-manifest.json').read_text())
        for item in manifest['files']:
            if 'source' in item:
                self.assertIn(item['rfilename'], ['LICENSE-OpenAI', 'LICENSE-Apache-2.0'])
            if item.get('verified_sha256'):
                self.assertRegex(item['verified_sha256'], '^[0-9a-f]{64}$')


if __name__ == '__main__':
    unittest.main()
