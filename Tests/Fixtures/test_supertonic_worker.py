"""Protocol/segmentation checks without model or network access."""
import importlib.util
import io
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "worker", Path(__file__).resolve().parents[2] / "Runtime/Supertonic/worker.py"
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerChecks(unittest.TestCase):
    def request(self, value):
        return worker.read_request(io.BytesIO(json.dumps(value).encode() + b"\n"))

    def test_accepts_only_bounded_text_and_explicit_supported_language(self):
        self.assertEqual(self.request({"text": "Guten Morgen.", "language": "de"}),
                         ("Guten Morgen.", "de"))
        for value in ({}, {"text": ""}, {"text": " "}, {"text": 5},
                      {"text": "x" * 8001, "language": "de"},
                      {"text": "Hello", "language": "auto"},
                      {"text": "Hello", "language": "en", "voice": "F1"}):
            with self.subTest(value=str(value)[:40]), self.assertRaises(ValueError):
                self.request(value)

    def test_rejects_oversized_or_unterminated_wire_request(self):
        for data in (b"x" * 64002, b'{"text":"Hello","language":"en"}'):
            with self.assertRaises(ValueError):
                worker.read_request(io.BytesIO(data))

    def test_segments_are_bounded_and_preserve_words(self):
        text = "Guten Morgen. " + "Wörter und Bücher " * 60 + "Ende!"
        parts = worker.segments(text)
        self.assertEqual(parts[0], "Guten Morgen.")
        self.assertTrue(all(0 < len(part) <= 240 for part in parts))
        self.assertEqual(" ".join(parts).split(), text.split())
        self.assertEqual("".join(worker.segments("x" * 700)), "x" * 700)

    def test_packets_are_structured_and_ack_is_required(self):
        output = io.BytesIO()
        worker.send(output, {"kind": "ready", "sampleRate": 44100})
        self.assertEqual(json.loads(output.getvalue()), {"kind": "ready", "sampleRate": 44100})
        worker.await_ack(io.BytesIO(b"next\n"))
        for data in (b"", b"no\n", b"nextxx\n"):
            with self.assertRaises(ValueError):
                worker.await_ack(io.BytesIO(data))


if __name__ == "__main__":
    unittest.main()
