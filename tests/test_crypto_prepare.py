"""Exercise service ordering and fail-closed behavior without touching a device."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "recovery/root/system/bin/tb300fu-crypto-prepare.sh"
SH = os.environ.get("TEST_SH", "sh")


class PrepareTests(unittest.TestCase):
    def run_prepare(self, failure="", ready=""):
        self.assertTrue(SCRIPT.is_file(), "crypto preparation implementation is missing")
        harness = r'''
            . "$1"
            crypto_preflight() { echo PREFLIGHT; [ "$FAIL" != preflight ]; }
            crypto_prop() { [ "$1" != init.svc.teei_daemon ] || echo running; }
            crypto_setprop() { echo "PROP $1 $2"; }
            crypto_probe() { echo "PROBE $1"; [ "$FAIL" != "$1" ]; }
            sleep() { :; }
            crypto_prepare
        '''
        env = dict(os.environ, FAIL=failure)
        result = subprocess.run([SH, "-c", harness, "test", SCRIPT.as_posix()],
                                env=env, capture_output=True, text=True, timeout=10)
        return result

    def test_success_waits_for_hal_before_keystore(self):
        result = self.run_prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = result.stdout
        self.assertLess(events.index("PREFLIGHT"), events.index("ctl.start teei_daemon"))
        self.assertLess(events.index("ctl.start teei_daemon"), events.index("ctl.start vendor.keymaster"))
        self.assertLess(events.index("PROBE keymaster"), events.index("ctl.start keystore2"))
        self.assertLess(events.index("PROBE keystore"), events.index("tb300fu.crypto.ready 1"))

    def test_preflight_failure_starts_nothing(self):
        result = self.run_prepare("preflight")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("ctl.start", result.stdout)
        self.assertNotIn("tb300fu.crypto.ready 1", result.stdout)

    def test_keymaster_timeout_prevents_keystore_and_ready(self):
        result = self.run_prepare("keymaster")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("ctl.start keystore2", result.stdout)
        self.assertNotIn("tb300fu.crypto.ready 1", result.stdout)
        self.assertLessEqual(result.stdout.count("PROBE keymaster"), 10)

    def test_gatekeeper_failure_does_not_claim_readiness(self):
        result = self.run_prepare("gatekeeper")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("tb300fu.crypto.ready 1", result.stdout)

    def test_keystore_failure_does_not_claim_readiness(self):
        result = self.run_prepare("keystore")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("tb300fu.crypto.ready 1", result.stdout)


if __name__ == "__main__":
    unittest.main()
