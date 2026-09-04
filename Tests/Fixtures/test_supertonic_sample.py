"""Export safety checks; these do not substitute for actual model synthesis."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

import numpy as np

spec = importlib.util.spec_from_file_location(
    "sample", Path(__file__).resolve().parents[2] / "scripts/compare-supertonic.py"
)
sample = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sample)


class SampleChecks(unittest.TestCase):
    def test_rejects_invalid_audio(self):
        for audio in ([], [float("nan")], [float("inf")], [0.0], [[0.5]]):
            with self.subTest(audio=audio), self.assertRaises(ValueError):
                sample.pcm16(np.array(audio), 44100)

    def test_clamps_without_voice_specific_gain(self):
        result = sample.pcm16(np.array([-2.0, -0.5, 0, 0.5, 2.0]), 44100)
        self.assertEqual(np.frombuffer(result, dtype="<i2").tolist(),
                         [-32767, -16384, 0, 16384, 32767])

    def test_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "sample.wav"
            sample.write_wav(path, b"\x01\x00", 44100)
            original = path.read_bytes()
            with self.assertRaises(FileExistsError):
                sample.write_wav(path, b"\x02\x00", 44100)
            self.assertEqual(path.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
