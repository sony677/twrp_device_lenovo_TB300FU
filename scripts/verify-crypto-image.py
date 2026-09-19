#!/usr/bin/env python3
"""Read-only TB300FU experimental boot-image gate. Does not flash or decrypt.

Checks structure and packaged integration, NOT runtime HAL compatibility,
AVB trust/authenticity, or successful decryption. No archive files are extracted.
"""
import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import stat
import struct
import sys


def require(condition, message):
    if not condition:
        raise ValueError(message)


def align(number, size):
    return (number + size - 1) // size * size


def unpack_gzip(data, limit=128 * 1024 * 1024):
    require(data[:2] == b"\x1f\x8b", "stock kernel requires a gzip ramdisk")
    with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
        unpacked = stream.read(limit + 1)
    require(len(unpacked) <= limit, "ramdisk exceeds decompression limit")
    return unpacked


def parse_cpio(data):
    entries = {}
    offset = 0
    while offset + 110 <= len(data):
        require(data[offset:offset + 6] == b"070701", "unsupported CPIO header")
        fields = [int(data[offset + 6 + i * 8:offset + 14 + i * 8], 16) for i in range(13)]
        mode, size, name_size = fields[1], fields[6], fields[11]
        name_start = offset + 110
        require(0 < name_size <= 4096 and name_start + name_size <= len(data), "invalid CPIO name")
        raw_name = data[name_start:name_start + name_size]
        require(raw_name[-1] == 0, "CPIO name is not terminated")
        name = raw_name[:-1].decode("utf-8")
        start = align(name_start + name_size, 4)
        end = start + size
        require(end <= len(data), "truncated CPIO content")
        offset = align(end, 4)
        if name == "TRAILER!!!":
            require(size == 0 and not any(data[offset:]), "unexpected data after CPIO trailer")
            return entries
        while name.startswith("./"):
            name = name[2:]
        require(not name.startswith("/") and ".." not in name.split("/"), "invalid CPIO path")
        require(name not in entries, "duplicate CPIO path: " + name)
        entries[name] = (mode, data[start:end])
    raise ValueError("CPIO trailer missing or truncated")


def verify(image):
    require(len(image) == 33554432, "release image must be exactly 32 MiB")
    require(image[:8] == b"ANDROID!", "invalid boot image magic")
    u32 = lambda offset: struct.unpack_from("<I", image, offset)[0]
    for offset, expected, field in (
        (8, 11843144, "kernel size"), (12, 0x40008000, "kernel address"),
        (20, 0x51b00000, "ramdisk address"), (24, 0, "second size"),
        (32, 0x47880000, "tags address"), (36, 2048, "page size"),
        (40, 2, "header version"), (44, 0x180001a1, "OS/patch version"),
        (1632, 0, "recovery DTBO size"), (1644, 1660, "header size"),
        (1648, 120386, "DTB size"),
    ):
        require(u32(offset) == expected, "wrong " + field)
    require(struct.unpack_from("<Q", image, 1652)[0] == 0x47880000, "wrong DTB address")
    kernel_size, ramdisk_size, dtb_size = u32(8), u32(16), u32(1648)
    ramdisk_offset = 2048 + align(kernel_size, 2048)
    dtb_offset = ramdisk_offset + align(ramdisk_size, 2048)
    require(ramdisk_size > 0 and dtb_offset + dtb_size <= len(image), "boot sections exceed image bounds")
    kernel = image[2048:2048 + kernel_size]
    require(hashlib.sha256(kernel).hexdigest() ==
            "bf458fac663e61a4081de1e7826f9d9e836decfbaea342d172376eae62742188", "wrong stock zImage kernel hash")
    dtb = image[dtb_offset:dtb_offset + dtb_size]
    require(hashlib.sha256(dtb).hexdigest() ==
            "62f52392b931de231b83f704e6470232070ea447016aff3887b70fa91419eff2", "wrong stock DTB hash")
    command = (image[64:576].split(b"\0")[0] + b" " + image[608:1632].split(b"\0")[0]).decode("ascii").split()
    require("bootopt=64S3,32S1,32S1" in command, "missing stock boot options")
    require(not any(s.startswith("twrpfastboot=") for s in command), "forced fastboot/recovery cmdline")
    require([s for s in command if s.startswith("buildvariant=")] == ["buildvariant=eng"], "wrong or duplicate buildvariant")
    entries = parse_cpio(unpack_gzip(image[ramdisk_offset:ramdisk_offset + ramdisk_size]))

    def file(name, executable=False):
        require(name in entries, "missing packaged file: " + name)
        mode, content = entries[name]
        require(stat.S_ISREG(mode) and content, "not a nonempty regular file: " + name)
        if executable:
            require(mode & 0o111 and len(content) >= 52 and content[:7] == b"\x7fELF\x01\x01\x01" and
                    struct.unpack_from("<H", content, 18)[0] == 40, "not an executable ARM32 ELF: " + name)
        return content

    recovery = file("system/bin/recovery", executable=True)
    require(b"TB300FU: crypto preparation failed" in recovery, "compiled pre-metadata hook missing")
    file("system/bin/tb300fu_crypto_probe", executable=True)
    file("system/bin/keystore2", executable=True)
    file("system/bin/tb300fu-crypto-prepare.sh")
    file("init.recovery.crypto.rc")
    require(b"import /init.recovery.crypto.rc" in file("init.recovery.mt8766.rc"), "crypto init import missing")
    keystore = file("system/etc/init/keystore2.rc").decode("utf-8")
    require("/tmp/misc/keystore" in keystore and re.search(r"^\s+disabled\s*$", keystore, re.M) and
            not re.search(r"^\s*(?:start|restart|exec_start)\s+keystore2\b", keystore, re.M),
            "keystore2 must use temporary storage and deferred startup")
    fstab = file("system/etc/recovery.fstab").decode("utf-8")
    rows = [line.split() for line in fstab.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    metadata_rows = [row for row in rows if "/metadata" in row[:2]]
    require(len(metadata_rows) == 1 and "/dev/block/by-name/md_udc" in metadata_rows[0],
            "metadata must use md_udc, not the unrelated metadata partition")
    data_rows = [row for row in rows if "/data" in row[:2]]
    require(len(data_rows) == 1 and "f2fs" in data_rows[0] and
            "keydirectory=/metadata/vold/metadata_encryption" in " ".join(data_rows[0]), "missing F2FS metadata key-directory configuration")
    return {"image_sha256": hashlib.sha256(image).hexdigest(), "kernel_size": kernel_size,
            "ramdisk_size": ramdisk_size, "dtb_size": dtb_size, "ramdisk_entries": len(entries),
            "packaged_crypto_checks": "passed", "decryption_verified": False,
            "warning": "Structural checks only; no runtime, AVB authenticity or device decryption verified."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    args = parser.parse_args()
    try:
        require(args.image.stat().st_size == 33554432, "release image must be exactly 32 MiB")
        print(json.dumps(verify(args.image.read_bytes()), indent=2))
        return 0
    except (OSError, ValueError, EOFError, struct.error) as error:
        print("REJECTED: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
