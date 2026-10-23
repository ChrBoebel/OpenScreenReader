import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('build_python_runtime', REPO / 'scripts/build-python-runtime.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def fake_runtime(root, packages=(('numpy', '2.2.6'),)):
    site = root / 'lib/python3.12/site-packages'
    site.mkdir(parents=True)
    for name, version in packages:
        info = site / f'{name}-{version}.dist-info'
        info.mkdir()
        (info / 'METADATA').write_text(f'Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n')
    (root / 'THIRD-PARTY-NOTICES.txt').write_text('notices')
    inventory = {'runtime': 'dictation', 'python': {'url': 'https://example.invalid/python.tar.gz'},
                 'packages': [{'name': name, 'version': version, 'license_files': [f'lib/python3.12/site-packages/{name}-{version}.dist-info/LICENSE']}
                              for name, version in packages]}
    (root / 'installed-packages.json').write_text(json.dumps(inventory))
    return site


class RuntimeBuildTests(unittest.TestCase):
    def test_every_lock_is_exactly_pinned_hashed_and_free_of_forbidden_packages(self):
        for relative in set(builder.LOCKS.values()):
            pins = builder.read_lock(REPO / relative)
            self.assertTrue(pins, relative)
            for name, version, hashes in pins:
                self.assertTrue(hashes, name)
                self.assertNotIn(builder.canonical(name), ('torch', 'numba', 'llvmlite', 'pillow', 'pandas'))

    def test_lock_rejects_forbidden_unpinned_and_duplicate_entries(self):
        digest = ' --hash=sha256:' + '0' * 64
        with tempfile.TemporaryDirectory() as temp:
            lock = Path(temp) / 'lock.txt'
            for text in ['artifact-tool-v2==2.8.93' + digest, 'artifact_tool==1.0' + digest, 'torch==2.14.1' + digest,
                         'numpy>=2' + digest, 'numpy==2.2.6' + digest + '\nNumPy==2.2.6' + digest]:
                lock.write_text(text + '\n')
                with self.assertRaises(ValueError, msg=text):
                    builder.read_lock(lock)
            lock.write_text('numpy==2.2.6 \\\n    --hash=sha256:' + 'a' * 64 + '\n')
            self.assertEqual(builder.read_lock(lock), [('numpy', '2.2.6', ['a' * 64])])

    def test_forbidden_content_fails_the_build(self):
        for relative in ['lib/python3.12/site-packages/artifact_tool_v2/__init__.py',
                         'lib/python3.12/site-packages/artifact_tool_v2-2.8.93.dist-info/METADATA',
                         'lib/python3.12/site-packages/tool/node_modules/x.js',
                         'lib/python3.12/site-packages/tool/@oai/pkg/index.js',
                         'lib/python3.12/site-packages/torch/__init__.py']:
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                fake_runtime(root)
                (root / relative).parent.mkdir(parents=True, exist_ok=True)
                (root / relative).write_text('')
                with self.assertRaisesRegex(ValueError, 'Forbidden'):
                    builder.check_forbidden(root)
                with self.assertRaisesRegex(ValueError, 'Forbidden'):
                    builder.verify_runtime(root, 'dictation')

    def test_clean_runtime_is_accepted_and_must_match_its_inventory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            site = fake_runtime(root)
            builder.verify_runtime(root, 'dictation')
            with self.assertRaisesRegex(ValueError, 'Not a speech runtime'):
                builder.verify_runtime(root, 'speech')
            committed = root / 'committed.json'
            committed.write_text(json.dumps({'runtime': 'dictation', 'packages': []}))
            with self.assertRaisesRegex(ValueError, 'differs'):
                builder.verify_runtime(root, 'dictation', committed)
            extra = site / 'pillow-12.3.0.dist-info'
            extra.mkdir()
            (extra / 'METADATA').write_text('Name: pillow\nVersion: 12.3.0\n')
            with self.assertRaisesRegex(ValueError, 'extra'):
                builder.verify_runtime(root, 'dictation')

    def test_inventory_rejects_absolute_paths(self):
        for value in ['/Users/someone/.codex/site-packages/numpy', '/opt/python/lib', '~/runtime']:
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'absolute'):
                builder.inventory_text({'packages': [{'license_files': [value]}]})
        builder.inventory_text({'packages': [{'license_files': ['lib/python3.12/LICENSE.txt'],
                                              'source': 'https://pypi.org/project/numpy/2.2.6/'}]})

    def test_committed_dictation_inventory_matches_the_lock_without_local_paths(self):
        text = (REPO / 'Runtime/Dictation/installed-packages.json').read_text()
        inventory = json.loads(builder.inventory_text(json.loads(text)))
        self.assertNotIn('/Users/', text)
        self.assertNotIn('.codex', text)
        self.assertEqual(inventory['runtime'], 'dictation')
        self.assertEqual(inventory['architecture'], 'arm64')
        pins = {builder.canonical(name): version for name, version, _ in builder.read_lock(REPO / 'Runtime/Dictation/requirements-lock.txt')}
        self.assertEqual({builder.canonical(p['name']): p['version'] for p in inventory['packages']}, pins)
        for package in inventory['packages']:
            self.assertFalse(builder.FORBIDDEN_NAMES.match(builder.canonical(package['name'])))
            self.assertTrue(package['license_files'], package['name'])
            self.assertNotIn('UNKNOWN', package['license'])
        # mlx-whisper's hardened-runtime patch is gated on this exact version.
        self.assertEqual(pins['mlx-whisper'], '0.4.3')


if __name__ == '__main__':
    unittest.main()
