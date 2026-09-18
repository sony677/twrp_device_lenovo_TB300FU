#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

required=(
  Android.mk
  AndroidProducts.mk
  BoardConfig.mk
  device.mk
  twrp_TB300FU.mk
  recovery/root/init.recovery.mt6761.rc
  recovery/root/init.recovery.mt8766.rc
  recovery/root/init.recovery.usb.rc
  recovery/root/system/etc/recovery.fstab
  recovery/root/first_stage_ramdisk/fstab.mt6761
  recovery/root/first_stage_ramdisk/fstab.mt8766
)

for path in "${required[@]}"; do
  test -s "$path" || { echo "Missing required file: $path" >&2; exit 1; }
done

grep -q 'BOARD_BOOTIMG_HEADER_VERSION := 2' BoardConfig.mk
grep -q 'BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432' BoardConfig.mk
grep -q 'BOARD_KERNEL_BASE := 0x40000000' BoardConfig.mk
grep -q 'BOARD_RAMDISK_OFFSET := 0x11b00000' BoardConfig.mk
grep -q 'BOARD_DTB_OFFSET := 0x07880000' BoardConfig.mk
grep -q 'TARGET_FORCE_PREBUILT_KERNEL := true' BoardConfig.mk
grep -qx 'BOARD_KERNEL_CMDLINE := bootopt=64S3,32S1,32S1' BoardConfig.mk
grep -q 'BOARD_USES_RECOVERY_AS_BOOT := true' BoardConfig.mk
grep -q 'TW_HAS_NO_RECOVERY_PARTITION := true' BoardConfig.mk
grep -q 'BOARD_SUPER_PARTITION_SIZE := 4823449600' BoardConfig.mk
grep -q '/dev/block/by-name/md_udc' recovery/root/system/etc/recovery.fstab
grep -q 'wait,logical,slotselect' recovery/root/system/etc/recovery.fstab
grep -q 'sys.usb.controller musb-hdrc' recovery/root/init.recovery.usb.rc
grep -q 'PLATFORM_SECURITY_PATCH := 2026-01-01' twrp_TB300FU.mk

if [[ "${1:-}" == "--require-prebuilts" ]]; then
  test -f prebuilt/kernel || { echo "Upload prebuilt/kernel first." >&2; exit 1; }
  test -f prebuilt/dtb.img || { echo "Upload prebuilt/dtb.img first." >&2; exit 1; }

  kernel_size=$(stat -c '%s' prebuilt/kernel)
  dtb_size=$(stat -c '%s' prebuilt/dtb.img)

  [[ "$kernel_size" == "11843144" ]] || {
    echo "Unexpected kernel size: $kernel_size (expected 11843144)." >&2
    exit 1
  }

  read -r kernel_sha _ < <(sha256sum prebuilt/kernel)
  [[ "$kernel_sha" == "bf458fac663e61a4081de1e7826f9d9e836decfbaea342d172376eae62742188" ]] || {
    echo "Unexpected kernel SHA-256: $kernel_sha." >&2
    exit 1
  }

  [[ "$dtb_size" == "120386" ]] || {
    echo "Unexpected DTB size: $dtb_size (expected 120386)." >&2
    exit 1
  }

  read -r dtb_sha _ < <(sha256sum prebuilt/dtb.img)
  [[ "$dtb_sha" == "62f52392b931de231b83f704e6470232070ea447016aff3887b70fa91419eff2" ]] || {
    echo "Unexpected DTB SHA-256: $dtb_sha." >&2
    exit 1
  }
fi

echo "TB300FU device-tree validation passed."
