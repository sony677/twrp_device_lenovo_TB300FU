# TB300FU: USB and encrypted-storage bring-up

## Evidence and limits

This branch is a **preparation**, not a verified decryption solution or a new
flashable image. Device observations are from TB300FU_S101116_251224_ROW.

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

## Integration still required

1. Collect stock service definitions and their ELF dependencies. Preserve the
   exact paths, users/groups, interfaces and startup ordering. Do not invent
   generic Keymaster/TEE service stanzas.
2. Integrate those services as `recovery/root/init.recovery.crypto.rc` and
   include any required libraries, firmware and recovery linker configuration.
   Confirm vendor dynamic partitions mount successfully first.
3. Review permissions and dependencies before setting
   `TB300FU_ENABLE_CRYPTO=true`. The optional profile deliberately fails at
   configuration time until the integration file exists. Its presence alone is
   not validation that the integration is complete.
4. Keep the exact stock userdata encryption descriptors:
   `fileencryption=aes-256-xts:aes-256-cts:v2`,
   `keydirectory=/metadata/vold/metadata_encryption` and `inlinecrypt`.
5. Build, verify the boot header and zImage wrapper, then conduct a separately
   agreed device test. Confirm metadata mapping, F2FS mounting, and credential
   decryption as separate milestones. Never request or log the owner's PIN.

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
```

CI runs Linux configuration tests plus Windows PowerShell 5.1 / PowerShell 7
collector tests, including native argument quoting, timeouts and mocked ADB.
These tests do not replace Android compilation or a real-device decryption test.
