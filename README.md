# TWRP device tree for Lenovo TB300FU

Experimental TWRP 12.1 for Lenovo Tab M8 (4th Gen), **TB300FU**.

> [!WARNING]
> This is a bring-up tree, not a production recovery. Data decryption is not
> implemented/verified. Do not format storage to work around a failed mount.
> Keep the exact stock boot image and a tested fastboot recovery path.

## Target and observed status

- Firmware: `TB300FU_S101116_251224_ROW`, Android 13, shipping API 31.
- ARM32, platform `mt6761`, hardware `mt8766`, board `tc422_wifi`.
- Boot header v2, page size 2048, boot partition 32 MiB, A/B recovery-as-boot.
- Dynamic partitions: system, vendor and product; virtual A/B.
- Display: 800x1280, 240 dpi.
- Owner verified TWRP UI, touch and correct orientation with the corrected
  zImage build, and normal Android boot with subsequent builds.
- Recovery ADB was verified in **ADB-only** mode. This branch excludes MTP to
  preserve that mode; this configuration change still needs a fresh build and
  a device test.
- /data is not mounted/decrypted in recovery. Android can mount it.
- /metadata uses **/dev/block/by-name/md_udc (p7)**, not the distinct partition
  named metadata (p8).

See [the diagnostic and integration plan](docs/CRYPTO_BRINGUP.md) and
[scripts/Collect-TB300FU.ps1](scripts/Collect-TB300FU.ps1).

## Required prebuilts

The repository includes the exact stock kernel and DTB. Preserve their bytes:

| File | Size | SHA-256 |
| --- | ---: | --- |
| prebuilt/kernel | 11,843,144 | bf458fac663e61a4081de1e7826f9d9e836decfbaea342d172376eae62742188 |
| prebuilt/dtb.img | 120,386 | 62f52392b931de231b83f704e6470232070ea447016aff3887b70fa91419eff2 |

The kernel must contain the ARM **zImage wrapper**. The 11,824,113-byte gzip
payload emitted by magiskboot unpack is not a substitute. The earlier build #5
used that incomplete payload and failed to boot; it is not a recommended artifact.

## Build and validation

The **Build TWRP boot image** workflow syncs the TWRP 12.1 minimal manifest,
installs this tree at `device/lenovo/TB300FU`, builds bootimage, adds an unsigned
AVB hash footer for the 32 MiB boot partition and uploads an artifact.
A successful build does not prove device compatibility.

The separate **Check USB and crypto preparation** workflow tests configuration
invariants and the read-only collector. It does not produce a flashable image.
Crypto remains gated off until exact stock services/dependencies are integrated;
enabling the optional profile without that integration produces an explicit error.

## Recovery precautions

Keep the original `image/boot.img` for this exact firmware:
SHA-256 `ddb66c682298c5c3360718c76e3cd343174499679c97a6232daeadf16a65bc4b`.

Verify the current slot before any explicitly planned flash. Do not flash the
inactive slot or alter preloader, lk, tee, nvram, nvdata, seccfg, super, userdata,
or metadata as a workaround for recovery decryption. Do not relock the bootloader
with a custom boot image.

## Remaining work

- Rebuild and device-test automatic ADB-only startup.
- Integrate stock Beanpod/Microtrust services and dependencies.
- Verify metadata decryption, then file/credential decryption.
- Verify dynamic partition operations, fastbootd, external SD and MTP separately.
