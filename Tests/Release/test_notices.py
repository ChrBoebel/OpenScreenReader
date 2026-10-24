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


def macho(filetype):
    return b'\xcf\xfa\xed\xfe' + (0x0100000c).to_bytes(4, 'little') + b'\0' * 4 + filetype.to_bytes(4, 'little') + b'\0' * 16


GCC_RECORD = {'file': 'gcc.tar.xz', 'url': 'https://example.org/gcc.tar.xz', 'bytes': 1, 'sha256': '0' * 64,
              'component': 'GCC runtime', 'license': 'LGPL-2.1-or-later', 'dynamic_libraries': ['libquadmath.0.dylib'],
              'license_texts': ['Licenses/GCC/COPYING.LIB']}
MPL_RECORD = {'file': 'eigen.zip', 'url': 'https://example.org/eigen.zip', 'bytes': 2, 'sha256': '1' * 64,
              'component': 'Eigen', 'license': 'MPL-2.0', 'license_texts': ['Speech/ThirdPartyNotices.txt']}


class CopyleftLibraryTests(unittest.TestCase):
    def resources(self, tmp, name='libquadmath.0.dylib', content=None):
        root = Path(tmp)
        library = root / 'Dictation/Python/lib/python3.12/site-packages/scipy/.dylibs' / name
        library.parent.mkdir(parents=True)
        library.write_bytes(macho(6) if content is None else content)
        return root

    def test_declared_separate_dylib_is_accepted_and_located(self):
        with tempfile.TemporaryDirectory() as tmp:
            found = notices.verify_copyleft_libraries(self.resources(tmp), [GCC_RECORD])
            self.assertEqual(found, {'libquadmath.0.dylib': ['Dictation/Python/lib/python3.12/site-packages/scipy/.dylibs/libquadmath.0.dylib']})

    def test_universal_dylib_is_a_separate_library(self):
        slice_offset = 4096
        fat = (b'\xca\xfe\xba\xbe' + (1).to_bytes(4, 'big') + (0x0100000c).to_bytes(4, 'big') + b'\0' * 4
               + slice_offset.to_bytes(4, 'big') + (32).to_bytes(4, 'big') + (14).to_bytes(4, 'big'))
        content = fat.ljust(slice_offset, b'\0') + macho(6)
        with tempfile.TemporaryDirectory() as tmp:
            notices.verify_copyleft_libraries(self.resources(tmp, content=content), [GCC_RECORD])

    def test_undeclared_gnu_runtime_library_blocks_packaging(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'Undeclared'):
                notices.verify_copyleft_libraries(self.resources(tmp, 'libgfortran.5.dylib'), [GCC_RECORD])

    def test_library_that_is_not_a_dylib_blocks_packaging(self):
        for content in [macho(8), b'not mach-o']:
            with tempfile.TemporaryDirectory() as tmp:
                with self.assertRaisesRegex(ValueError, 'separate dynamic library'):
                    notices.verify_copyleft_libraries(self.resources(tmp, content=content), [GCC_RECORD])

    def test_static_gnu_archive_blocks_packaging(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'Static'):
                notices.verify_copyleft_libraries(self.resources(tmp, 'libquadmath.a', b'!<arch>\n'), [GCC_RECORD])

    def test_missing_declared_library_means_the_record_is_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'missing'):
                notices.verify_copyleft_libraries(Path(tmp), [GCC_RECORD])

    def test_source_offer_names_license_replacement_and_exact_pointers(self):
        section = notices.source_section([GCC_RECORD, MPL_RECORD], {'libquadmath.0.dylib': ['Dictation/libquadmath.0.dylib']})
        for text in ['Lesser General Public License version 2.1', 'replace them', 'reverse engineering',
                     'Dictation/libquadmath.0.dylib', 'gcc.tar.xz', '0' * 64, 'https://example.org/gcc.tar.xz',
                     # Written offer: duration from distribution, any third party, cost cap, contact without e-mail.
                     'at least three years from the date', 'any third party', 'no more than the cost',
                     notices.SOURCE_REQUESTS, 'Mozilla Public License 2.0', 'Eigen', 'https://example.org/eigen.zip',
                     '1' * 64, 'not included in this app']:
            self.assertIn(text, section)
        self.assertNotIn('CorrespondingSource/gcc.tar.xz', section)
        self.assertNotIn('@', section)  # No personal e-mail address in the offer.
        self.assertEqual(notices.source_section([], {}), '')


class SourcePointerTests(unittest.TestCase):
    def test_source_archives_inside_the_app_are_rejected(self):
        for relative in ['CorrespondingSource/gcc.tar.xz', 'CorrespondingSource/other.tar.gz', 'Dictation/gcc.tar.xz']:
            with self.subTest(relative=relative), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp); (root / relative).parent.mkdir(parents=True)
                (root / relative).write_bytes(b'archive')
                with self.assertRaisesRegex(ValueError, 'must not be bundled'):
                    notices.reject_bundled_sources(root, [GCC_RECORD])

    def test_pointer_documents_are_the_only_corresponding_source_files(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            notices.write_source_pointers(root, [GCC_RECORD, MPL_RECORD])
            folder = root / 'CorrespondingSource'
            self.assertEqual(sorted(path.name for path in folder.iterdir()), ['README.md', 'sources.json'])
            self.assertEqual(json.loads((folder / 'sources.json').read_text()), [GCC_RECORD, MPL_RECORD])
            self.assertIn('written offer', (folder / 'README.md').read_text().lower())
            notices.reject_bundled_sources(root, [GCC_RECORD, MPL_RECORD])  # Pointers alone are accepted.

    def test_records_need_exact_pointers_and_copyleft_license_texts(self):
        notices.validate_source_records([GCC_RECORD, MPL_RECORD])
        for change in [{'url': 'http://example.org/gcc.tar.xz'}, {'sha256': 'abc'}, {'bytes': 0},
                       {'file': '../gcc.tar.xz'}, {'license': ''}, {'license_texts': []}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                notices.validate_source_records([{**GCC_RECORD, **change}])
        mit = {key: value for key, value in MPL_RECORD.items() if key != 'license_texts'}
        notices.validate_source_records([{**mit, 'license': 'MIT'}])  # Only copyleft records must point to texts.

    def test_copyleft_license_texts_must_ship_as_notices(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaisesRegex(ValueError, 'license text'):
                notices.verify_license_texts(root, [GCC_RECORD])
            (root / 'Licenses/GCC').mkdir(parents=True)
            (root / 'Licenses/GCC/COPYING.LIB').write_text('GNU LESSER GENERAL PUBLIC LICENSE')
            notices.verify_license_texts(root, [GCC_RECORD])
            with self.assertRaises(ValueError):
                notices.verify_license_texts(root, [{**GCC_RECORD, 'license_texts': ['../outside/COPYING']}])

    def test_release_bundle_ships_offer_pointers_and_license_texts_but_no_archives(self):
        import json
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'portable-runtime.json').write_text(json.dumps({'architecture': 'x86_64'}))
            dylibs = root / 'Dictation/Python/lib/python3.12/site-packages/scipy/.dylibs'
            dylibs.mkdir(parents=True)
            for name in ['libquadmath.0.dylib', 'libgfortran.5.dylib', 'libgcc_s.1.1.dylib']:
                (dylibs / name).write_bytes(macho(6))
            onnx = root / 'Speech/SupertonicRuntime/python/lib/python3.12/site-packages/onnxruntime/ThirdPartyNotices.txt'
            onnx.parent.mkdir(parents=True)
            onnx.write_text('Eigen\nMozilla Public License Version 2.0\n')
            notices.bundle_notices(root)
            records = notices.corresponding_sources('x86_64')
            self.assertEqual(json.loads((root / 'CorrespondingSource/sources.json').read_text()), records)
            self.assertEqual(sorted(path.name for path in (root / 'CorrespondingSource').iterdir()), ['README.md', 'sources.json'])
            for name in [record['file'] for record in records]:
                self.assertFalse(list(root.rglob(name)), name)
            index = (root / 'THIRD-PARTY-NOTICES.html').read_text()
            for text in ['at least three years', 'gcc-13.4.0.tar.xz', 'https://ftp.gnu.org/gnu/gcc/gcc-13.4.0/gcc-13.4.0.tar.xz',
                         'GCC RUNTIME LIBRARY EXCEPTION', 'GNU LESSER GENERAL PUBLIC LICENSE', 'Mozilla Public License']:
                self.assertIn(text, index)
            self.assertTrue((root / 'Licenses/GCC-13.4.0/COPYING.RUNTIME').is_file())
            # A stale archive from an older runtime input fails the release instead of shipping.
            (root / 'CorrespondingSource/gcc-13.4.0.tar.xz').write_bytes(b'archive')
            with self.assertRaisesRegex(ValueError, 'must not be bundled'):
                notices.bundle_notices(root)

    def test_fetched_source_with_wrong_hash_is_discarded(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp); (cache / 'gcc.tar.xz').write_bytes(b'x')
            with self.assertRaisesRegex(ValueError, 'mismatch'):
                notices.fetch_sources(cache, [GCC_RECORD])
            self.assertFalse((cache / 'gcc.tar.xz').exists())


class CommittedLicenseRecordTests(unittest.TestCase):
    licenses = notices.REPO / 'docs/licenses'

    def test_corresponding_source_records_are_exact_and_cover_every_gnu_library(self):
        import json
        records = json.loads((self.licenses / 'native-corresponding-sources.json').read_text())
        names = [item['file'] for item in records]
        self.assertEqual(len(names), len(set(names)))
        for item in records:
            self.assertEqual(Path(item['file']).name, item['file'])
            self.assertTrue(item['url'].startswith('https://'), item['file'])
            self.assertGreater(item['bytes'], 0)
            self.assertRegex(item['sha256'], '^[0-9a-f]{64}$')
        notices.validate_source_records(records)
        for item in records:
            for text in item.get('license_texts', []):
                if text.startswith('Licenses/'):
                    self.assertTrue((self.licenses / text.removeprefix('Licenses/')).is_file(), text)
        libraries = {name for item in records for name in item.get('dynamic_libraries', [])}
        self.assertEqual(libraries, {'libquadmath.0.dylib', 'libgfortran.5.dylib', 'libgcc_s.1.1.dylib'})
        self.assertIn('gcc-13.4.0.tar.xz', names)
        for removed in ['libsndfile', 'autocommand', 'certifi', 'hf_xet', 'libogg', 'flac', 'lame', 'mpg123', 'opus', 'vorbis']:
            self.assertFalse([name for name in names if removed in name], removed)

    def test_license_supplements_match_their_recorded_hashes(self):
        import json
        records = json.loads((self.licenses / 'portable-supplement-sources.json').read_text())
        notices.verify_supplements(self.licenses, records)
        files = {item['license_file'] for item in records}
        self.assertIn('GCC-13.4.0/libquadmath/COPYING.LIB', files)
        self.assertIn('GNU LESSER GENERAL PUBLIC LICENSE', (self.licenses / 'GCC-13.4.0/libquadmath/COPYING.LIB').read_text())
        self.assertFalse([path for path in files if 'hf-xet' in path or path.startswith('Native-codecs/')])

    def test_rust_coverage_matches_the_shipped_extensions(self):
        import json
        coverage = json.loads((self.licenses / 'rust-license-coverage.json').read_text())
        self.assertEqual(sorted(item['component'] for item in coverage['binaries']), ['safetensors', 'tiktoken', 'tokenizers'])
        self.assertEqual(sorted(coverage['components']), ['safetensors', 'tiktoken', 'tokenizers'])
        rust = {path.name for path in (self.licenses / 'Rust').iterdir()}
        for component in coverage['components'].values():
            self.assertTrue((self.licenses / component['standard_library_notices']).is_dir())
            for package in component['active_packages']:
                if not package['workspace']:
                    self.assertIn(package['name'] + '-' + package['version'], rust)
        for path in self.licenses.rglob('*.json'):
            self.assertNotIn('/Users/', path.read_text(), path)


class UnsignedDigestTests(unittest.TestCase):
    @unittest.skipUnless(Path('/usr/bin/cc').exists() and Path('/usr/bin/codesign').exists(), 'needs Xcode command-line tools')
    def test_linker_signed_and_resigned_copies_normalize_to_the_same_digest(self):
        import shutil, subprocess
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp); (root / 'lib.c').write_text('int answer(void) { return 42; }\n')
            library = root / 'liblinker.dylib'
            subprocess.run(['/usr/bin/cc', '-dynamiclib', '-o', str(library), str(root / 'lib.c')], check=True,
                           capture_output=True)
            resigned = root / 'libresigned.dylib'
            shutil.copy2(library, resigned)
            subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(resigned)], check=True, capture_output=True)
            self.assertNotEqual(library.read_bytes(), resigned.read_bytes())
            self.assertEqual(notices.unsigned_digest(library), notices.unsigned_digest(resigned))
