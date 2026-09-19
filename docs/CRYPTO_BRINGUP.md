# TB300FU: USB and encrypted-storage bring-up

## Evidence and limits

This branch includes an **experimental crypto integration**, not verified
decryption. Device observations are from TB300FU_S101116_251224_ROW. Building an
image is not proof that Lenovo's proprietary secure-world stack accepts it.

- The corrected ARM zImage boots TWRP; the owner verified touch and orientation.
- ADB worked after selecting `sys.usb.config=adb`. MTP/ADB enumeration has been
  unreliable. Disable MTP using the supported `TW_EXCLUDE_MTP` build flag;
  do not change kernel USB parameters or ConfigFS manually.
- Android mounted `md_udc -> mmcblk0p7` at `/metadata`. The partition named
  `metadata -> mmcblk0p8` is different. Do not substitute it.
- Android mounted F2FS through `/dev/block/mapper/userdata`. Recovery tried the
  encrypted raw `mmcblk0p47` and reported a magic mismatch. This is consistent
  with a missing metadata-decryption mapping; it does not establish corruption.
- Recovery's kernel supports F2FS. Its process list did not include the stock
  Beanpod Keymaster / Microtrust TEE userspace services.
- The current tree did not enable `TW_INCLUDE_CRYPTO`, and used the ineffective
  `TW_INCLUDE_RESETPROP` flag instead of `TW_INCLUDE_LIBRESETPROP`.

TWRP 12.1 links libvold into recovery. A separate running `vold` daemon is
**not** a prerequisite by itself. Its metadata decryption path mounts the key
directory and invokes `fscrypt_mount_metadata_encrypted` before using the
decrypted block device. Merely replacing userdata with a mapper path in fstab
does not create that mapping.

Primary implementation references:
- [TWRP Android.mk](https://github.com/TeamWin/android_bootable_recovery/blob/android-12.1/Android.mk)
- [TWRP partition manager](https://github.com/TeamWin/android_bootable_recovery/blob/android-12.1/partitionmanager.cpp)
- [TWRP ConfigFS init](https://github.com/TeamWin/android_bootable_recovery/blob/android-12.1/etc/init.rc)

## Collect the missing stock configuration

Use `scripts/Collect-TB300FU.ps1` from **Windows PowerShell**, with exactly one
TB300FU connected by ADB, or provide `-Serial HGR4G667`. It works in Android or
recovery. If vendor is unavailable in recovery, collect in normal Android.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Collect-TB300FU.ps1 -Serial HGR4G667
```

The script creates a new timestamped Downloads directory and prints its location.
Share `vendor-services.txt`, `vendor-dependencies.txt`, `vendor-fstab.txt`,
`vendor-manifest.txt`, `vendor-inventory.txt`, and `vendor-access.txt`.
It reads firmware configuration and process/mount information only:
no encryption-key files, credentials, personal files, or raw partitions.
It never mounts, repairs, formats, flashes, reboots or starts/stops services.

A missing file/command is recorded rather than hidden; `EXIT_CODE=124` is a
timeout. Existing output folders are never overwritten. The script rejects
multiple devices without an explicit serial, unsupported ADB states, and a
non-TB300FU model. Do not use `adb wait-for-device` to wait indefinitely.

## Experimental integration

The stock firmware evidence has now been collected from a temporary read-only
vendor mount. See [the September 19 evidence review](VENDOR_EVIDENCE_20260919.md).
No need to repeat the unavailable-vendor capture. The default profile still has
crypto disabled. The experimental profile implements this sequence:

1. Before metadata decryption, load installed Android's version/patch properties,
   including first API level. Stock system/vendor patches were confirmed as
   **2026-01-05**, release **13**; TWRP originally reported 12.
2. Mount stock vendor using TWRP's dynamic-partition handling. Keep it mounted
   during automatic cleanup while HALs are active. Do not flash vendor, switch
   slots or package proprietary blobs. Explicit user unmount is not overridden.
3. Check the exact firmware fingerprint, read-only vendor mount, device nodes,
   ELF dependencies and `ro.hardware.gatekeeper=beanpod`.
4. Start stock TEE with its exact UUID arguments, then Beanpod Keymaster 4.0
   and Gatekeeper. Use the checked ARM32 library paths and stock users/groups.
   Services are disabled until requested, with no automatic crash-restart loops.
5. `tb300fu_crypto_probe` verifies registered Keymaster with hardware-backed
   `getHardwareInfo`, Gatekeeper registration and the keystore2 Binder service.
   Individual probes and the whole preparation have timeouts. Keystore2 uses
   TWRP's temporary `/tmp/misc/keystore`, not Android's persistent database.
6. Only then use standard TWRP/libvold metadata decrypt with `needs_encrypt=false`
   and `should_format=false`, using **md_udc / p7**, then mapped F2FS and FBE.
   Failed preparation/mount stops this path. Failed metadata decrypt does not
   fall back to legacy FDE, which is inappropriate for this stock FBE device.

No provisioning, keybox check, persistent-directory creation, THH loading,
manual mapping with secret keys, PIN arguments, formatting or raw userdata
repair is added. Whether THH or persistent TEE paths are needed remains a
hardware-test question. Proprietary HALs may access secure storage during actual
operation; normal TWRP/libvold may upgrade key blobs. This is **not** a read-only
forensic recovery. Prepare personal-file backups in Android before any test.

### Build and acceptance

`scripts/patch-twrp-crypto.py` adds a synchronous pre-metadata hook to reviewed
TWRP source `5c3d206a5eeb3d446bcda8248a405a4b278bab5c`. It rejects changed or
partly patched source. Upstream's `twrp.mount_to_decrypt=1` comes **after** the
metadata stage, so using only that property would start the HALs too late.

The workflow selects crypto on `codex/adb-crypto-preparation`, or with its
`crypto` dispatch input. It applies the hook before exporting
`TB300FU_ENABLE_CRYPTO=true` and `TB300FU_CRYPTO_HOOK_APPLIED=true` for lunch.
The distinct output is `twrp-TB300FU-S101116-crypto-experimental.img`.
The **32 MiB** boot limit is enforced; oversized images must not be truncated.
This kernel supports **gzip only**, not LZ4/XZ/LZMA ramdisks.

Hardware acceptance remains pending. After a separately agreed device test,
collect `/tmp/tb300fu-crypto.log` and recovery.log. Confirm metadata mapping,
mounted F2FS, then files unlocked using a credential entered **on the tablet**.
`tb300fu.crypto.ready=1` means services responded, not that storage decrypted.
Verify normal Android boot afterwards. Do not change USB sysfs for these tests.

## Offline evaluator

`scripts/Analyze-TB300FU.ps1` reads only seven allowlisted text files from a
collector output directory. It does not invoke ADB, execute `commands.json`,
mount partitions, start services, change files, or attempt decryption.

```powershell
.\scripts\Analyze-TB300FU.ps1 -ReportDirectory 'C:\path\to\TB300FU-diagnostico'
.\scripts\Analyze-TB300FU.ps1 -ReportDirectory 'C:\path\to\TB300FU-diagnostico' -AsJson
```

It distinguishes missing evidence from missing runtime components, does not
mistake kernel TEE threads for userspace services, and flags the wrong p8
metadata source. A timeout is unknown, not proof that a mount or service is
absent. A working mapper or mounted F2FS is not proof that credential-encrypted
files are accessible. `DecryptionVerified` remains false because this tool
does not test credentials or read user data. This is an evaluator, not a repair.

## Safety

Do **not** format /data, /metadata, md_udc or the partition named metadata.
Do not run filesystem repair on encrypted raw userdata. Do not delete keys or
change slots to work around this error. Never publish partition/key backups.

Normal Android boot and existing files must remain intact. Stop if that changes;
do not infer that a failing recovery mount means the user's data is lost.

## Tests

```sh
bash scripts/validate-tree.sh --require-prebuilts
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

```powershell
.\tests\Test-Collector.ps1
.\tests\Test-Analyzer.ps1
```

CI runs Linux configuration tests plus Windows PowerShell 5.1 / PowerShell 7
collector tests, including native argument quoting, timeouts and mocked ADB.
These tests do not replace Android compilation or a real-device decryption test.
