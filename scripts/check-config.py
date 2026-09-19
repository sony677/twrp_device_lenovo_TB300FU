#!/usr/bin/env python3
"""Check the reviewed TB300FU layout before any image build."""
from pathlib import Path
import sys

DATA_OPTIONS = {
    "fileencryption=aes-256-xts:aes-256-cts:v2",
    "keydirectory=/metadata/vold/metadata_encryption",
}
FSTABS = [
    "recovery/root/system/etc/recovery.fstab",
    "recovery/root/first_stage_ramdisk/fstab.mt6761",
    "recovery/root/first_stage_ramdisk/fstab.mt8766",
]

def check_fstab(text):
    rows = {}
    for line in text.splitlines():
        line = line.partition("#")[0].strip()
        if not line:
            continue
        columns = line.split()
        if len(columns) != 5:
            raise ValueError("fstab must have exactly five columns")
        if columns[1] in rows:
            raise ValueError("duplicate mount point: " + columns[1])
        rows[columns[1]] = columns
    metadata = rows["/metadata"]
    data = rows["/data"]
    if metadata[0] != "/dev/block/by-name/md_udc" or metadata[2] != "ext4":
        raise ValueError("/metadata must use the stock md_udc (p7), not metadata (p8)")
    if data[0] != "/dev/block/by-name/userdata" or data[2] != "f2fs":
        raise ValueError("use the physical userdata source; crypto creates the mapper at runtime")
    if "inlinecrypt" not in data[3].split(","):
        raise ValueError("stock inlinecrypt option is missing")
    if not DATA_OPTIONS.issubset(set(data[4].split(","))):
        raise ValueError("stock encryption descriptors are missing or changed")

def check_tree(root):
    for path in FSTABS:
        try:
            check_fstab((root / path).read_text())
        except (ValueError, KeyError) as error:
            raise ValueError(f"{path}: {error}") from error
    board = "\n".join(line.partition("#")[0].strip()
                      for line in (root / "BoardConfig.mk").read_text().splitlines())
    for flag in ("TW_EXCLUDE_MTP := true", "TW_INCLUDE_LIBRESETPROP := true"):
        if flag not in board:
            raise ValueError("required supported TWRP flag missing: " + flag)
    for obsolete in ("TW_HAS_MTP :=", "TW_INCLUDE_RESETPROP :="):
        if obsolete in board:
            raise ValueError("ineffective TWRP flag: " + obsolete)
    if "TB300FU_ENABLE_CRYPTO ?= false" not in board:
        raise ValueError("crypto must remain gated until exact vendor services are integrated")
    return True

if __name__ == "__main__":
    try:
        check_tree(Path(__file__).resolve().parents[1])
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
    print("Stock encryption descriptors and supported TWRP flags verified.")
