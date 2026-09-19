import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/patch-twrp-crypto.py"


class CryptoPatchTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "pre-metadata hook patcher is missing")
        spec = importlib.util.spec_from_file_location("crypto_patch", SCRIPT)
        self.patch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.patch)

    def fixture(self):
        return "\n".join(old for old, new in self.patch.REPLACEMENTS)

    def test_hook_runs_before_metadata_key_mount_and_decrypt(self):
        output = self.patch.transform(self.fixture())
        self.assertLess(output.index("tb300fu-crypto-prepare.sh --run"),
                        output.index("Key_Directory_Partition ="))
        self.assertIn('return;', output.split('Key_Directory_Partition =')[0])

    def test_source_drift_and_partial_patches_fail_closed(self):
        with self.assertRaises(ValueError):
            self.patch.transform("unsupported upstream source")
        old, new = self.patch.REPLACEMENTS[0]
        with self.assertRaises(ValueError):
            self.patch.transform(self.fixture().replace(old, new))

    def test_idempotent_complete_patch(self):
        output = self.patch.transform(self.fixture())
        self.assertEqual(output, self.patch.transform(output))

    def test_duplicate_anchor_fails(self):
        with self.assertRaises(ValueError):
            self.patch.transform(self.fixture() + self.patch.REPLACEMENTS[0][0])

    def test_vendor_preserved_only_when_hals_ready(self):
        output = self.patch.transform(self.fixture())
        self.assertIn('GetProperty("tb300fu.crypto.ready", "0") != "1"', output)

    def test_stock_os_binding_precedes_keymaster_startup(self):
        output = self.patch.transform(self.fixture())
        self.assertLess(output.index('stock_property("ro.build.version.security_patch"'),
                        output.index('tb300fu-crypto-prepare.sh --run'))
        self.assertIn('stock_property("ro.vendor.build.security_patch", "/vendor")', output)

    def test_keystore_does_not_autostart_before_stock_properties(self):
        source = 'on late-init\n    start keystore2\n\nservice keystore2 /system/bin/keystore2 /tmp/misc/keystore\n    class early_hal\n'
        output = self.patch.transform_keystore(source)
        self.assertNotIn('start keystore2', output)
        self.assertIn('    disabled\n', output)
        self.assertIn('/tmp/misc/keystore', output)
        self.assertEqual(output, self.patch.transform_keystore(output))


if __name__ == "__main__":
    unittest.main()
