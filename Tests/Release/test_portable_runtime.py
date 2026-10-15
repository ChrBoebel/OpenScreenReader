import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('portable', Path(__file__).resolve().parents[2] / 'scripts/portable_runtime.py')
portable = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portable)

class PortableRuntimeTests(unittest.TestCase):
    def test_minimum_os_is_not_inferred_from_wheel_name(self):
        load = 'cmd LC_BUILD_VERSION\nplatform 1\nminos 26.2\nsdk 26.5\n'
        with self.assertRaisesRegex(ValueError, '26.2'):
            portable.validate_load_commands(load, '14.0')
        portable.validate_load_commands(load.replace('26.2', '14.0'), '14.0')

    def test_missing_sdk_rejects_libraries_that_fail_hardened_loading(self):
        for sdk in ['n/a', '0.0', '10.8']:
            with self.assertRaisesRegex(ValueError, 'SDK'):
                portable.validate_load_commands('cmd LC_BUILD_VERSION\nplatform 1\nminos 14.0\nsdk '+sdk+'\n', '14.0')

    def test_legacy_minimum_version_and_every_fat_slice_are_checked(self):
        load = 'cmd LC_VERSION_MIN_MACOSX\nversion 13.0\nsdk 14.0\n'
        portable.validate_load_commands(load, '14.0')
        with self.assertRaises(ValueError):
            portable.validate_load_commands(load + 'cmd LC_BUILD_VERSION\nplatform 1\nminos 15.0\n', '14.0')

    def test_external_load_dependency_fails_but_library_id_is_allowed(self):
        portable.validate_load_commands('cmd LC_ID_DYLIB\nname /build/lib.dylib (offset 24)\n', '14.0')
        with self.assertRaisesRegex(ValueError, 'External'):
            portable.validate_load_commands('cmd LC_LOAD_DYLIB\nname /opt/homebrew/lib/test.dylib (offset 24)\n', '14.0')

    def test_wheel_cannot_escape_target(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); z=root/'bad.whl'
            with zipfile.ZipFile(z,'w') as f: f.writestr('../outside','bad')
            with self.assertRaises(ValueError): portable.install_wheel(z,root/'site')
            self.assertFalse((root/'outside').exists())

    def test_wheel_keeps_licenses_and_relocates_purelib(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); z=root/'ok.whl'
            with zipfile.ZipFile(z,'w') as f:
                f.writestr('demo.data/purelib/demo.py','pass')
                f.writestr('demo.dist-info/licenses/LICENSE','notice')
                f.writestr('demo.data/scripts/command','unused')
            portable.install_wheel(z,root/'site')
            self.assertTrue((root/'site/demo.py').is_file())
            self.assertEqual((root/'site/demo.dist-info/licenses/LICENSE').read_text(),'notice')
            self.assertFalse((root/'site/demo.data/scripts/command').exists())

    def test_download_cache_rejects_changed_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'file';path.write_bytes(b'wrong')
            with self.assertRaises(ValueError): portable.verify_file(path,{'sha256':'0'*64,'bytes':5})
