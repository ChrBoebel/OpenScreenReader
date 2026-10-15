"""Protocol/segmentation checks without model or network access."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    "worker", Path(__file__).resolve().parents[2] / "Runtime/Supertonic/worker.py"
)
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerChecks(unittest.TestCase):
    def test_intel_model_uses_bounded_nonspinning_cpu_sessions(self):
        helper = Mock()
        helper.load_onnx_all.return_value = ("duration", "text", "vector", "vocoder")
        for cores, expected in [(2, 2), (16, 4), (None, 1)]:
            with patch.object(worker.platform, "machine", return_value="x86_64"), patch.object(worker.os, "cpu_count", return_value=cores):
                worker.load_speech_model(helper, Path("/model"))
            options = helper.ort.SessionOptions.return_value
            self.assertEqual(options.intra_op_num_threads, expected)
            self.assertEqual(options.add_session_config_entry.call_args_list[-2:], [
                unittest.mock.call("session.intra_op.allow_spinning", "0"),
                unittest.mock.call("session.inter_op.allow_spinning", "0"),
            ])
            self.assertEqual(helper.load_onnx_all.call_args.args, ("/model/onnx", options, ["CPUExecutionProvider"]))
        helper.load_text_to_speech.assert_not_called()

    def test_arm_preserves_existing_model_loading(self):
        helper = Mock()
        with patch.object(worker.platform, "machine", return_value="arm64"):
            self.assertIs(worker.load_speech_model(helper, Path("/model")), helper.load_text_to_speech.return_value)
        helper.load_text_to_speech.assert_called_once_with("/model/onnx", use_gpu=False)
        helper.load_onnx_all.assert_not_called()

    def test_abbreviations_dates_and_paragraphs_keep_their_context(self):
        text = "Dr. Weber liest z. B. am 4. September 42,50 Euro vor. Danach endet der Text."
        self.assertEqual(worker.segments(text), [
            "Dr. Weber liest z. B. am 4. September 42,50 Euro vor.", "Danach endet der Text."])
        self.assertEqual(worker.segments("Heading\n\nParagraph with e.g. AB-123 and 12.50 EUR."),
                         ["Heading", "Paragraph with e.g. AB-123 and 12.50 EUR."])

    def test_session_reuses_model_and_tags_each_text_without_history(self):
        import numpy as np
        tts = Mock(sample_rate=44100, return_value=(np.full((1, 441), 0.1), [0.01]))
        helper = Mock()
        helper.load_text_to_speech.return_value = tts
        request = lambda identity: json.dumps({"text": "Hallo.", "language": "de", "id": identity}).encode() + b"\n"
        source = io.BytesIO(request("first") + b"next\n" + request("second") + b"next\n")
        output = io.BytesIO()
        with patch.object(worker, "load_verified_helper", return_value=helper), patch.object(worker, "load_speech_model", return_value=tts) as load:
            worker.run(source, output, Path("/unused-test-model"), session=True)
        self.assertEqual(load.call_count, 1)
        self.assertEqual(helper.load_voice_style.call_count, 1)
        self.assertEqual(tts.call_count, 2)
        packets = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([p["kind"] for p in packets], ["ready", "audio", "end"] * 2)
        self.assertEqual([p["id"] for p in packets], ["first"] * 3 + ["second"] * 3)
        self.assertTrue(all(p["protocol"] == 2 for p in packets))

    def test_session_requests_require_ids_and_allow_clean_eof(self):
        request = {"text": "Hallo", "language": "de", "id": "job-1"}
        self.assertEqual(worker.read_request(io.BytesIO(json.dumps(request).encode() + b"\n"), session=True),
                         ("Hallo", "de", "job-1"))
        self.assertIsNone(worker.read_request(io.BytesIO(), session=True))
        for identity in (None, "", "x" * 65, 3):
            request["id"] = identity
            with self.assertRaises(ValueError):
                worker.read_request(io.BytesIO(json.dumps(request).encode() + b"\n"), session=True)

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
