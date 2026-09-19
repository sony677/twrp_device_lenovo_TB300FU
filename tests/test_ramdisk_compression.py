import gzip
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/compress-ramdisk.py"


class RamdiskCompressionTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "verified gzip compressor is missing")
        spec = importlib.util.spec_from_file_location("ramdisk_compression", SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_cli_preserves_binary_input_without_stdout_diagnostics(self):
        raw = bytes(range(256)) * 4 + b"\r\n\0ramdisk\xff\xfe"
        result = subprocess.run([sys.executable, str(SCRIPT)], input=raw, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.startswith(b"\x1f\x8b"))
        self.assertEqual(gzip.decompress(result.stdout), raw)
        self.assertIn(b"cpio_sha256=", result.stderr)

    def test_repeated_runs_are_identical(self):
        raw = b"unchanged archive, unchanged gzip" * 100
        first, second = io.BytesIO(), io.BytesIO()
        self.module.compress_stream(io.BytesIO(raw), first, io.StringIO())
        self.module.compress_stream(io.BytesIO(raw), second, io.StringIO())
        self.assertEqual(first.getvalue(), second.getvalue())

    def test_never_increases_size_over_level_nine_gzip(self):
        raw = bytes(range(256)) * 10
        output = io.BytesIO()
        self.module.compress_stream(io.BytesIO(raw), output, io.StringIO())
        self.assertLessEqual(len(output.getvalue()), len(gzip.compress(raw, compresslevel=9, mtime=0)))

    def test_corrupt_compressor_result_is_not_written(self):
        output = io.BytesIO()
        with patch.object(self.module.zopfli.gzip, "compress", return_value=gzip.compress(b"wrong")):
            with self.assertRaisesRegex(ValueError, "round-trip"):
                self.module.compress_stream(io.BytesIO(b"original" * 100), output, io.StringIO())
        self.assertEqual(output.getvalue(), b"")

    def test_size_bound_fails_before_output(self):
        output = io.BytesIO()
        with self.assertRaisesRegex(ValueError, "limit"):
            self.module.compress_stream(io.BytesIO(b"a" * 17), output, io.StringIO(), limit=16)
        self.assertEqual(output.getvalue(), b"")

    def test_larger_zopfli_result_falls_back_to_gzip(self):
        raw = b"data" * 100
        larger = gzip.compress(raw, compresslevel=0, mtime=0)
        output, report = io.BytesIO(), io.StringIO()
        with patch.object(self.module.zopfli.gzip, "compress", return_value=larger):
            self.module.compress_stream(io.BytesIO(raw), output, report)
        self.assertEqual(gzip.decompress(output.getvalue()), raw)
        self.assertLess(len(output.getvalue()), len(larger))
        self.assertIn("selected=gzip9", report.getvalue())


if __name__ == "__main__":
    unittest.main()
