import importlib.util
import gzip
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/patch-ramdisk-build.py"
RULE = ('$(recovery_ramdisk): $(recovery_uncompressed_ramdisk) $(COMPRESSION_COMMAND_DEPS)\n'
        '\t@echo ----- Making compressed recovery ramdisk ------\n'
        '\t$(COMPRESSION_COMMAND) < $(recovery_uncompressed_ramdisk) > $@\n')


class RamdiskBuildPatchTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "recovery compression integration missing")
        spec = importlib.util.spec_from_file_location("ramdisk_build_patch", SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_only_recovery_recipe_changes_and_repeat_is_idempotent(self):
        original = 'COMPRESSION_COMMAND := $(MINIGZIP)\n' + RULE + '# other image recipes\n'
        result = self.module.patch_text(original, '/tmp/env/bin/python3', '/tmp/tree/compress.py')
        self.assertIn('COMPRESSION_COMMAND := $(MINIGZIP)\n', result)
        self.assertIn('/usr/bin/timeout 20m /tmp/env/bin/python3 /tmp/tree/compress.py < $(recovery_uncompressed_ramdisk) > $@', result)
        self.assertTrue(result.endswith('# other image recipes\n'))
        self.assertEqual(self.module.patch_text(result, '/tmp/env/bin/python3', '/tmp/tree/compress.py'), result)

    def test_missing_or_duplicate_recipe_rejected(self):
        for text in ('unreviewed recipe', RULE + RULE):
            with self.subTest(text=text):
                with self.assertRaises(ValueError):
                    self.module.patch_text(text, '/tmp/python', '/tmp/script')

    def test_make_expansion_or_relative_path_rejected(self):
        for path in ('relative/python', '/tmp/$(shell false)', '/tmp/python\nunsafe'):
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    self.module.patch_text(RULE, path, '/tmp/script')

    @unittest.skipUnless(sys.platform == 'linux' and shutil.which('make'), 'requires Linux make')
    def test_patched_make_recipe_runs_real_encoder(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            raw = bytes(range(256)) * 10
            (root / 'ramdisk.cpio').write_bytes(raw)
            variables = ('recovery_ramdisk := ramdisk.img\n'
                         'recovery_uncompressed_ramdisk := ramdisk.cpio\n'
                         'COMPRESSION_COMMAND := false\n')
            (root / 'Makefile').write_text(self.module.patch_text(
                variables + RULE, sys.executable, str(ROOT / 'scripts/compress-ramdisk.py')))
            result = subprocess.run(['make', '-f', 'Makefile'], cwd=root,
                                    capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(gzip.decompress((root / 'ramdisk.img').read_bytes()), raw)
            self.assertIn(b'cpio_sha256=', result.stderr)


class CompactProfileTests(unittest.TestCase):
    def test_optional_tools_excluded_only_in_experimental_profile(self):
        crypto = (ROOT / 'config/BoardConfigCrypto.mk').read_text()
        default = (ROOT / 'BoardConfig.mk').read_text()
        for flag in ('TW_EXCLUDE_BASH', 'TW_EXCLUDE_NANO', 'TW_EXCLUDE_ZIP'):
            self.assertIn(flag + ' := true', crypto)
            self.assertNotIn(flag + ' := true', default)
        self.assertIn('TW_INCLUDE_CRYPTO := true', crypto)
        self.assertIn('BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432', default)


if __name__ == '__main__':
    unittest.main()
