import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('notices', Path(__file__).resolve().parents[2] / 'scripts/bundle_notices.py')
notices = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notices)

class NoticeTests(unittest.TestCase):
    def test_index_contains_exact_license_and_escapes_markup(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'LICENSE-test').write_text('Copyright <author> & contributors')
            result = notices.render_index(root)
            self.assertIn('Copyright &lt;author&gt; &amp; contributors', result)
            self.assertNotIn('<author>', result)
            self.assertIn('LICENSE-test', result)
            self.assertNotIn('<script', result)

    def test_external_symlink_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'resources'; root.mkdir()
            outside = Path(tmp) / 'outside'; outside.write_text('license')
            (root / 'LICENSE-link').symlink_to(outside)
            with self.assertRaises(ValueError): notices.render_index(root)

    def test_empty_inventory_is_not_a_valid_notice_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError): notices.render_index(Path(tmp))

    def test_supplement_hash_mismatch_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'NOTICE').write_text('changed')
            with self.assertRaises(ValueError):
                notices.verify_supplements(root, [{'license_file': 'NOTICE', 'license_sha256': '0' * 64}])

    def test_source_archives_are_verified_before_copy(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); cache = root / 'cache'; cache.mkdir()
            (cache / 'source.tar.gz').write_bytes(b'original')
            records = [{'file': 'source.tar.gz', 'bytes': 8, 'sha256': hashlib.sha256(b'original').hexdigest()}]
            notices.bundle_sources(root / 'resources', cache, records, required=True)
            self.assertEqual((root / 'resources/CorrespondingSource/source.tar.gz').read_bytes(), b'original')
            (cache / 'source.tar.gz').write_bytes(b'tampered')
            with self.assertRaises(ValueError):
                notices.bundle_sources(root / 'other', cache, records, required=True)

    def test_missing_required_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises((ValueError, FileNotFoundError)):
                notices.bundle_sources(root / 'resources', root / 'cache',
                    [{'file': 'source.tar.gz', 'bytes': 1, 'sha256': '0' * 64}], required=True)

    def test_named_supplement_is_visible_in_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'Licenses').mkdir()
            (root / 'Licenses/Flatbuffers-25.12.19.txt').write_text('Exact supplemental terms')
            self.assertIn('Exact supplemental terms', notices.render_index(root))

    def test_incomplete_rust_coverage_blocks_packaging(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                notices.verify_rust_coverage(Path(tmp), {'complete': False, 'binaries': []}, 'arm64')

    def test_changed_rust_binary_blocks_packaging(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'tokenizer.so').write_bytes(b'changed binary')
            proof = {'complete': True, 'binaries': [{'architecture': 'arm64', 'path': 'tokenizer.so', 'unsigned_sha256': 'reviewed'}]}
            with patch.object(notices, 'unsigned_digest', return_value='changed'):
                with self.assertRaises(ValueError): notices.verify_rust_coverage(root, proof, 'arm64')

    def test_rust_provenance_cannot_escape_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            proof = {'complete': True, 'binaries': [{'architecture': 'arm64', 'path': '../outside.so', 'unsigned_sha256': 'reviewed'}]}
            with self.assertRaises(ValueError): notices.verify_rust_coverage(Path(tmp), proof, 'arm64')
