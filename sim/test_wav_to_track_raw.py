import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "src/user_source/hdl_source/python/wav_to_track_raw.py"
spec = importlib.util.spec_from_file_location("wav_to_track_raw", SCRIPT)
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class TrackConversionTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name) / "source.wav"
        self.source.write_bytes(b"not a real wav")
        self.target = Path(self.directory.name) / "TRACK01.RAW"

    def test_conversion_arguments_and_output(self):
        def fake_run(arguments, **kwargs):
            self.assertEqual(arguments[arguments.index("-map") + 1], "0:a:0")
            self.assertEqual(arguments[arguments.index("-ac") + 1], "1")
            self.assertEqual(arguments[arguments.index("-ar") + 1], "48000")
            self.assertEqual(arguments[arguments.index("-c:a") + 1], "pcm_s16le")
            self.assertEqual(arguments[arguments.index("-f") + 1], "s16le")
            Path(arguments[-1]).write_bytes(b"\x01\x00\xff\x7f")
            return subprocess.CompletedProcess(arguments, 0, "", "")

        with patch.object(converter.shutil, "which", return_value="ffmpeg"), patch.object(converter.subprocess, "run", side_effect=fake_run):
            self.assertEqual(converter.convert(self.source, self.target), 4)
        self.assertEqual(self.target.read_bytes(), b"\x01\x00\xff\x7f")

    def test_missing_ffmpeg(self):
        with patch.object(converter.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "FFmpeg"):
                converter.convert(self.source, self.target)
        self.assertFalse(self.target.exists())

    def test_existing_output_is_preserved(self):
        self.target.write_bytes(b"existing")
        with self.assertRaises(FileExistsError):
            converter.convert(self.source, self.target)
        self.assertEqual(self.target.read_bytes(), b"existing")

    def test_invalid_output_name(self):
        with self.assertRaisesRegex(ValueError, "TRACK01"):
            converter.convert(self.source, self.target.with_name("MUSIC.WAV"))

    def test_decode_error_cleans_partial_output(self):
        def fake_run(arguments, **kwargs):
            Path(arguments[-1]).write_bytes(b"partial")
            return subprocess.CompletedProcess(arguments, 1, "", "unsupported codec")

        with patch.object(converter.shutil, "which", return_value="ffmpeg"), patch.object(converter.subprocess, "run", side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, "unsupported codec"):
                converter.convert(self.source, self.target)
        self.assertFalse(self.target.exists())
        self.assertEqual(list(Path(self.directory.name).glob(".track_raw_*")), [])


if __name__ == "__main__":
    unittest.main()
