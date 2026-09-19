import importlib.util
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("checks", ROOT / "scripts/check-config.py")
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)

class ConfigTests(unittest.TestCase):
    def setUp(self):
        self.fstab = (ROOT / checks.FSTABS[0]).read_text()

    def test_current_tree(self):
        self.assertTrue(checks.check_tree(ROOT))

    def test_wrong_metadata_partition_rejected(self):
        with self.assertRaises(ValueError):
            checks.check_fstab(self.fstab.replace("/by-name/md_udc", "/by-name/metadata"))

    def test_missing_key_directory_rejected(self):
        with self.assertRaises(ValueError):
            checks.check_fstab(self.fstab.replace(",keydirectory=/metadata/vold/metadata_encryption", ""))

    def test_hardcoded_mapper_rejected(self):
        with self.assertRaises(ValueError):
            checks.check_fstab(self.fstab.replace("/by-name/userdata", "/mapper/userdata"))

    def test_crypto_profile_fails_before_build_without_source_hook(self):
        result = subprocess.run(
            ["make", "-f", "tests/read-board.mk", "DEVICE_PATH=.", "TB300FU_ENABLE_CRYPTO=true"],
            cwd=ROOT, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("crypto hook missing", result.stderr)

    def test_experimental_crypto_profile_enables_crypto_with_hook(self):
        result = subprocess.run(
            ["make", "-f", "tests/read-board.mk", "DEVICE_PATH=.", "TB300FU_ENABLE_CRYPTO=true",
             "TB300FU_CRYPTO_HOOK_APPLIED=true"], cwd=ROOT, text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.strip(), "mtp_excluded=true crypto=true")

    def test_default_profile_keeps_crypto_gated_and_adb_only(self):
        result = subprocess.run(["make", "-f", "tests/read-board.mk", "DEVICE_PATH=.", "TB300FU_ENABLE_CRYPTO=false"],
                                cwd=ROOT, text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.strip(), "mtp_excluded=true crypto=")

if __name__ == "__main__":
    unittest.main()
