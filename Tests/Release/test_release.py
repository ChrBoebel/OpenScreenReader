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
            record.write_text(json.dumps({key: True for key in release.RELEASE_GATES}))
            release.require_release_approval(record)

    def test_version_numbers_are_monotonic_and_path_safe(self):
        release.validate_version('0.1.0', '42')
        for version, build in [('0.1.0', '0'), ('../oops', '3'), ('1.0', 'abc'), ('1.2.3', '1/2')]:
            with self.assertRaises(ValueError):
                release.validate_version(version, build)


if __name__ == '__main__':
    unittest.main()
