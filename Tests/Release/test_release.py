import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('release', Path(__file__).resolve().parents[2] / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def test_receipt_rejects_changed_missing_and_escaping_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'runtime'
            root.mkdir()
            asset = root / 'worker.py'
            asset.write_text('original')
            receipt = root / 'installation-receipt.json'
            receipt.write_text(json.dumps({'files': {'worker.py': release.digest(asset)}}))
            release.verify_receipt(root, receipt)
            asset.write_text('tampered')
            with self.assertRaises(ValueError):
                release.verify_receipt(root, receipt)
            outside = Path(temp) / 'outside'
            outside.write_text('original')
            receipt.write_text(json.dumps({'files': {'../outside': release.digest(outside)}}))
            with self.assertRaises(ValueError):
                release.verify_receipt(root, receipt)
            receipt.write_text(json.dumps({'files': {'missing': '0' * 64}}))
            with self.assertRaises((ValueError, FileNotFoundError)):
                release.verify_receipt(root, receipt)

    def test_worker_refresh_verifies_input_and_changes_only_project_sources(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp)
            for root, receipt in release.receipts(app):
                receipt.parent.mkdir(parents=True)
                worker = receipt.parent / 'worker.py'
                worker.write_text('old project worker')
                asset = root / 'model.dat'
                asset.write_text('unchanged model')
                receipt.write_text(json.dumps({'files': {
                    str(worker.relative_to(root)): release.digest(worker),
                    'model.dat': release.digest(asset)}}))
            release.refresh_project_workers(app)
            for root, receipt in release.receipts(app):
                release.verify_receipt(root, receipt)
                self.assertEqual((root / 'model.dat').read_text(), 'unchanged model')
            self.assertEqual((app / 'Contents/Resources/Dictation/worker.py').read_bytes(),
                             (release.REPO / 'Runtime/Dictation/worker.py').read_bytes())
            self.assertEqual((app / 'Contents/Resources/Speech/SupertonicRuntime/worker.py').read_bytes(),
                             (release.REPO / 'Runtime/Supertonic/worker.py').read_bytes())
            speech, speech_receipt = release.receipts(app)[0]
            (speech / 'model.dat').write_text('tampered')
            with self.assertRaises(ValueError): release.refresh_project_workers(app)

    def test_public_endpoints_reject_credentials_and_non_https(self):
        self.assertEqual(release.https_url('https://downloads.example.com/saywing/'), 'https://downloads.example.com/saywing/')
        for url in ['', 'http://example.com', 'https://user:pass@example.com', 'https://example.com?token=secret', 'file:///tmp/feed']:
            with self.assertRaises(ValueError):
                release.https_url(url)

    def test_release_gate_requires_every_completed_review(self):
        with tempfile.TemporaryDirectory() as temp:
            record = Path(temp) / 'approval.json'
            record.write_text(json.dumps({'license_review': True, 'clean_mac': False, 'offline_privacy': True}))
            with self.assertRaises(ValueError):
                release.require_release_approval(record)
            record.write_text(json.dumps({**{key: True for key in release.RELEASE_GATES}, 'scope': {'architecture': 'arm64'}}))
            release.require_release_approval(record)

    def test_owner_beta_exception_only_covers_documented_device_test_gap(self):
        with tempfile.TemporaryDirectory() as temp:
            record = Path(temp) / 'approval.json'
            data = {key: True for key in release.RELEASE_GATES}
            data['clean_mac'] = False
            data['scope'] = {'architecture': 'arm64'}
            exception = {'approved': True, 'channel': 'beta', 'gate': 'clean_mac',
                         'owner_decision': '2026-10-15: publish ARM beta with documented device gaps',
                         'remaining_tests': ['fresh Mac permissions', 'macOS 14 device']}
            data['owner_beta_exception'] = exception
            record.write_text(json.dumps(data))
            release.require_release_approval(record)
            for changes in [{'approved': False}, {'channel': 'stable'}, {'gate': 'license_review'},
                            {'owner_decision': ''}, {'remaining_tests': []}]:
                record.write_text(json.dumps({**data, 'owner_beta_exception': {**exception, **changes}}))
                with self.assertRaises(ValueError): release.require_release_approval(record)
            for gate in ['license_review', 'offline_privacy', 'update_roundtrip']:
                record.write_text(json.dumps({**data, gate: False}))
                with self.assertRaises(ValueError): release.require_release_approval(record)
            record.write_text(json.dumps({**data, 'scope': {'architecture': 'x86_64'}}))
            with self.assertRaises(ValueError): release.require_release_approval(record)

    def test_headless_sparkle_signing_uses_private_file_without_keychain(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp:
            key = Path(temp) / 'sparkle.key'
            key.write_text('test-only-secret')
            key.chmod(0o600)
            args = SimpleNamespace(sparkle_key_file=key, sparkle_account='saywing',
                                   download_url_prefix='https://example.com')
            with patch.object(release, 'run') as run:
                release.generate_feed(Path('/tools'), Path('/publish'), args)
                calls = [call.args for call in run.call_args_list]
                self.assertEqual(len(calls), 2)
                for call in calls:
                    self.assertIn('--ed-key-file', call)
                    self.assertIn(key, call)
                    self.assertNotIn('--account', call)
                    self.assertNotIn('test-only-secret', call)
                self.assertTrue(all(call.kwargs.get('timeout') == 300 for call in run.call_args_list))
            key.chmod(0o644)
            with self.assertRaisesRegex(ValueError, 'private'):
                release.generate_feed(Path('/tools'), Path('/publish'), args)

    def test_intel_requires_its_own_complete_approval(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'approval.json'
            approved = {**{key: True for key in release.RELEASE_GATES}, 'scope': {'architecture': 'arm64'}}
            path.write_text(json.dumps(approved))
            with self.assertRaises(ValueError): release.require_release_approval(path, 'x86_64')
            approved['scope']['architecture'] = 'x86_64'
            path.write_text(json.dumps(approved))
            release.require_release_approval(path, 'x86_64')
            approved['clean_mac'] = False
            path.write_text(json.dumps(approved))
            with self.assertRaises(ValueError): release.require_release_approval(path, 'x86_64')

    def test_version_numbers_are_monotonic_and_path_safe(self):
        release.validate_version('0.1.0', '42')
        for version, build in [('0.1.0', '0'), ('../oops', '3'), ('1.0', 'abc'), ('1.2.3', '1/2')]:
            with self.assertRaises(ValueError):
                release.validate_version(version, build)


if __name__ == '__main__':
    unittest.main()
