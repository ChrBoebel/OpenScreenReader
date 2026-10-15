import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

scripts = Path(__file__).resolve().parents[2] / 'scripts'
sys.path.insert(0, str(scripts))
spec = importlib.util.spec_from_file_location('prepare_release_ci', scripts / 'prepare-release-ci.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)

class RuntimeExtractionTests(unittest.TestCase):
    def test_dmg_validates_ticket_and_always_unmounts_after_copy_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp); archive = base / 'runtime.dmg'; archive.touch()
            calls = []
            def run(*args, **kwargs):
                calls.append(tuple(str(a) for a in args))
                if args[:2] == ('hdiutil', 'attach'):
                    (base / 'runtime-mount/Saywing.app').mkdir()
                if args[0] == '/usr/bin/ditto': raise RuntimeError('copy failed')
            with patch.object(ci, 'run', side_effect=run):
                with self.assertRaisesRegex(RuntimeError, 'copy failed'):
                    ci.extract_runtime(archive, base / 'saywing-runtime', 'dmg')
            self.assertEqual(calls[0][:3], ('xcrun', 'stapler', 'validate'))
            self.assertIn('-readonly', calls[1]); self.assertIn('-nobrowse', calls[1])
            self.assertEqual(calls[-1][:2], ('hdiutil', 'detach'))

    def test_zip_compatibility_and_unknown_format_rejection(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            with patch.object(ci, 'run') as run:
                ci.extract_runtime(base / 'runtime.zip', base / 'output', 'zip')
                self.assertEqual(run.call_args.args[:4], ('/usr/bin/ditto', '-x', '-k', base / 'runtime.zip'))
                run.reset_mock()
                with self.assertRaises(ValueError): ci.extract_runtime(base / 'runtime', base / 'output', 'exe')
                run.assert_not_called()
