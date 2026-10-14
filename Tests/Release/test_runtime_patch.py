import ast
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('patch_runtime', Path(__file__).resolve().parents[2] / 'scripts/patch-dictation-runtime.py')
patch_runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch_runtime)

class RuntimePatchTests(unittest.TestCase):
    def test_word_timing_import_is_only_executed_when_explicitly_used(self):
        source = (b'from .timing import add_word_timestamps\n'
                  b'def transcribe(word_timestamps):\n'
                  b'                if word_timestamps:\n'
                  b'                    add_word_timestamps()\n')
        result = patch_runtime.defer_timing_import(source)
        tree = ast.parse(result)
        self.assertFalse(any(isinstance(node, ast.ImportFrom) for node in tree.body))
        branch = tree.body[0].body[0]
        self.assertIsInstance(branch, ast.If)
        self.assertIsInstance(branch.body[0], ast.ImportFrom)
        self.assertEqual(branch.body[0].module, 'timing')
        self.assertEqual(sum(isinstance(node, ast.ImportFrom) for node in ast.walk(tree)), 1)

    def test_unknown_or_already_changed_source_cannot_be_blindly_rewritten(self):
        for source in [b'new upstream code', b'from .timing import add_word_timestamps\n']:
            with self.assertRaises(ValueError):
                patch_runtime.defer_timing_import(source)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / 'Python/lib/python3.12/site-packages/mlx_whisper/transcribe.py'
            source.parent.mkdir(parents=True)
            source.write_bytes(b'unknown upstream code')
            with self.assertRaises(ValueError):
                patch_runtime.patch(root)
            self.assertEqual(source.read_bytes(), b'unknown upstream code')
