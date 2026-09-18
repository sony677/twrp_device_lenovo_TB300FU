# TWRP device tree for Lenovo TB300FU

Experimental TWRP 12.1 bring-up for the Lenovo Tab M8 (4th Gen), model **TB300FU**.

> [!WARNING]
> This tree is not yet confirmed bootable. Do not flash a generated image unless you have the exact stock `boot.img`, an unlocked bootloader, working fastboot access, and a tested recovery procedure.

## Verified target

- Device: `TB300FU` / board `tc422_wifi`
- Platform: MediaTek `mt6761` / hardware `mt8766`
- Architecture: ARM32 (`armeabi-v7a`)
- Firmware: `TB300FU_S101116_251224_ROW`
- Fingerprint: `Lenovo/TB300FU_S/TB300FU:13/TP1A.220624.014/S101116_251224_ROW:user/release-keys`
- Boot header: v2, page size 2048
- Boot partition: 32 MiB, A/B, recovery-as-boot
- Dynamic partitions: `system`, `vendor`, `product`
- Virtual A/B enabled
- Display: 800x1280, 240 dpi
- Touch: FocalTech `fts_ts` / `mtk-tpd`
- Metadata block: `/dev/block/by-name/md_udc`
- `vendor_boot_a/b` exist but are zero-filled on the inspected firmware

## Current scope

The first milestone is intentionally small:

1. Build a correctly packed `boot.img`.
2. Boot the TWRP interface.
3. Verify display, touch, buttons, ADB and slot handling.
4. Verify dynamic-partition discovery and fastbootd.
5. Add FBE/metadata decryption only after the base recovery is stable.

Credential decryption is **not implemented or claimed** in this initial tree. The stock firmware uses metadata encryption, inline encryption and a Microtrust/Beanpod TEE stack.

## Required local prebuilts

Binary firmware files are intentionally not committed by the initial scaffold. Before running the build workflow, add:

- `prebuilt/kernel` — 11,824,113 bytes, extracted from the exact stock `boot.img` with `magiskboot unpack -n`
- `prebuilt/dtb.img` — 120,386 bytes, extracted from the same image

The GitHub workflow rejects missing or incorrectly sized prebuilts before starting the Android source sync.

## Build

Run the **Build TWRP boot image** workflow manually from the Actions tab. It syncs the TWRP 12.1 minimal manifest, places this repository at `device/lenovo/TB300FU`, builds `bootimage`, adds an unsigned AVB hash footer for the 32 MiB boot partition, and uploads the result as an artifact.

## Recovery path

Keep the exact stock image available:

```powershell
fastboot getvar current-slot
fastboot flash boot_b .\image\boot.img
fastboot reboot
```

Replace `boot_b` with the slot reported by fastboot. Never flash `preloader`, `lk`, `tee`, `nvram`, `nvdata` or `seccfg` during TWRP bring-up.

## Status

- [x] Stock boot header and addresses documented
- [x] Stock ramdisk/fstab inspected
- [x] Kernel and DTB extracted
- [x] A/B and dynamic-partition layout documented
- [ ] Text tree validated by GitHub Actions
- [ ] TWRP image compiled
- [ ] Image flashed to the active test slot
- [ ] UI/display verified
- [ ] Touch/buttons verified
- [ ] ADB verified in recovery
- [ ] Dynamic partitions verified
- [ ] Data decryption implemented
