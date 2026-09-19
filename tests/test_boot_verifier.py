"""Exercise real boot/CPIO parsing; never connect to or alter a tablet."""
import gzip
import importlib.util
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/verify-crypto-image.py"


def cpio(entries):
    result = bytearray()
    for index, (name, data, mode) in enumerate(entries + [("TRAILER!!!", b"", 0)]):
        name = name.encode() + b"\0"
        fields = [index, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(name), 0]
        result.extend(b"070701" + b"".join(("%08x" % n).encode() for n in fields))
        result.extend(name)
        result.extend(b"\0" * (-len(result) % 4))
        result.extend(data)
        result.extend(b"\0" * (-len(result) % 4))
    return bytes(result)


def elf_arm():
    data = bytearray(52)
    data[:7] = b"\x7fELF\x01\x01\x01"
    struct.pack_into("<HH", data, 16, 3, 40)
    return bytes(data)


def ramdisk_entries():
    # Minimal independent fixture; runtime execution is NOT claimed by this check.
    return [
        ("system/bin/recovery", elf_arm() + b"TB300FU: crypto preparation failed", 0o100755),
        ("system/bin/tb300fu_crypto_probe", elf_arm(), 0o100755),
        ("system/bin/keystore2", elf_arm(), 0o100755),
        ("system/bin/tb300fu-crypto-prepare.sh", b"#!/system/bin/sh\ncrypto_prepare() { :; }\n", 0o100644),
        ("init.recovery.crypto.rc", b"service teei_daemon /vendor/bin/teei_daemon\n    disabled\n", 0o100644),
        ("init.recovery.mt8766.rc", b"import /init.recovery.crypto.rc\n", 0o100644),
        ("system/etc/init/keystore2.rc", b"service keystore2 /system/bin/keystore2 /tmp/misc/keystore\n    disabled\n", 0o100644),
        ("system/etc/recovery.fstab", b"/metadata ext4 /dev/block/by-name/md_udc\n/data f2fs /dev/block/by-name/userdata flags=keydirectory=/metadata/vold/metadata_encryption\n", 0o100644),
    ]


def boot_image(entries=None):
    kernel = (ROOT / "prebuilt/kernel").read_bytes()
    dtb = (ROOT / "prebuilt/dtb.img").read_bytes()
    packed = gzip.compress(cpio(ramdisk_entries() if entries is None else entries), mtime=0)
    header = bytearray(2048)
    header[:8] = b"ANDROID!"
    struct.pack_into("<10I", header, 8, len(kernel), 0x40008000, len(packed),
                     0x51b00000, 0, 0, 0x47880000, 2048, 2, 0x180001a1)
    command = b"bootopt=64S3,32S1,32S1 buildvariant=eng"
    header[64:64 + len(command)] = command
    struct.pack_into("<IQIIQ", header, 1632, 0, 0, 1660, len(dtb), 0x47880000)
    result = header
    for blob in (kernel, packed, dtb):
        result.extend(blob)
        result.extend(b"\0" * (-len(result) % 2048))
    return result + bytes(33554432 - len(result))


class BootVerifierTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), "offline crypto image verifier is missing")
        spec = importlib.util.spec_from_file_location("boot_verify", SCRIPT)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def test_accepts_structural_candidate_without_claiming_decryption(self):
        report = self.module.verify(boot_image())
        self.assertEqual(report["kernel_size"], 11843144)
        self.assertEqual(report["dtb_size"], 120386)
        self.assertIs(report["decryption_verified"], False)

    def test_rejects_corrupted_kernel_even_with_correct_header_size(self):
        image = boot_image()
        image[2048 + 64] ^= 1
        with self.assertRaisesRegex(ValueError, "kernel"):
            self.module.verify(image)

    def test_rejects_wrong_boot_geometry(self):
        for offset, wrong in [(12, 0x8000), (20, 0x11b00000), (36, 4096), (40, 3)]:
            with self.subTest(offset=offset):
                image = boot_image()
                struct.pack_into("<I", image, offset, wrong)
                with self.assertRaises(ValueError):
                    self.module.verify(image)

    def test_rejects_truncated_or_oversized_release_image(self):
        image = boot_image()
        for bad in (image[:-1], image + b"\0"):
            with self.assertRaisesRegex(ValueError, "32 MiB"):
                self.module.verify(bad)

    def test_rejects_old_recovery_without_compiled_hook(self):
        entries = ramdisk_entries()
        entries[0] = (entries[0][0], elf_arm(), entries[0][2])
        with self.assertRaisesRegex(ValueError, "hook"):
            self.module.verify(boot_image(entries))

    def test_rejects_missing_crypto_probe(self):
        entries = [entry for entry in ramdisk_entries() if entry[0] != "system/bin/tb300fu_crypto_probe"]
        with self.assertRaisesRegex(ValueError, "tb300fu_crypto_probe"):
            self.module.verify(boot_image(entries))

    def test_rejects_wrong_metadata_partition(self):
        entries = [(n, d.replace(b"by-name/md_udc", b"by-name/metadata"), m)
                   for n, d, m in ramdisk_entries()]
        with self.assertRaisesRegex(ValueError, "md_udc"):
            self.module.verify(boot_image(entries))

    def test_rejects_early_keystore_start(self):
        entries = [(n, d + b"\non late-init\n    start keystore2\n" if n.endswith("keystore2.rc") else d, m)
                   for n, d, m in ramdisk_entries()]
        with self.assertRaisesRegex(ValueError, "keystore2"):
            self.module.verify(boot_image(entries))

    def test_rejects_duplicate_cpio_entries(self):
        entries = ramdisk_entries()
        entries.append(entries[0])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.module.verify(boot_image(entries))

    def test_rejects_archive_without_trailer(self):
        with self.assertRaisesRegex(ValueError, "CPIO"):
            self.module.parse_cpio(cpio(ramdisk_entries())[:-120])

    def test_rejects_expanding_ramdisk_above_bound(self):
        packed = gzip.compress(b"a" * 1025)
        with self.assertRaisesRegex(ValueError, "limit"):
            self.module.unpack_gzip(packed, limit=1024)


if __name__ == "__main__":
    unittest.main()
