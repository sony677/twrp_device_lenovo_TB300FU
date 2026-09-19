# TB300FU vendor evidence — 2026-09-19

## Result and limits

The uploaded collector reports recorded `VENDOR_UNAVAILABLE`. Their empty vendor
service/dependency outputs did **not** establish that Lenovo omitted those HALs.
A subsequent diagnostic session accessed the installed vendor filesystem and
collected the missing firmware definitions. Decryption is still **not fixed**,
no new Android image was built here, and no device flash was performed.

The system-debugging review separates three stages: metadata block mapping,
mounting decrypted F2FS, and unlocking credential-encrypted files. None of these
can be inferred from USB connectivity or successful ELF dependency resolution.

## Read-only firmware inspection

The current `_b` slot had logical `vendor_b -> /dev/block/dm-2`. It was mounted
temporarily using `mount -t ext4 -o ro,noload` and `/proc/mounts` confirmed
`ro,...,norecovery`. Vendor fingerprint matched `S101116_251224_ROW`, Android 13;
the vendor VNDK version was 31. The exact read-only collector was then rerun.
After collection, `/vendor` was unmounted normally and its absence was checked
in `/proc/mounts`. `/data` and `/metadata` were not mounted by this investigation.
ADB remained in `recovery`, `sys.usb.config=adb`, TWRP `3.7.1_12-0`.

The private local report folder is `diagnostico_vendor_ro_20260919` under the
firmware's `extraido_dispositivo` directory. Raw reports, device identifiers,
proprietary binaries, keys and partition contents are not committed here.

## Confirmed runtime gap

- The kernel advertises F2FS support.
- No decrypted `mapper/userdata` exists in the captured recovery session.
- Neither `/data` nor `/metadata` was mounted in that session.
- The recovery fstab's metadata source `md_udc -> mmcblk0p7` matches stock.
  `metadata -> mmcblk0p8` is a different partition, not a correction.
- The stock userdata descriptors include `inlinecrypt`,
  `fileencryption=aes-256-xts:aes-256-cts:v2` and
  `keydirectory=/metadata/vold/metadata_encryption`.
- Userspace `teei_daemon`, Beanpod Keymaster and Gatekeeper were not running.
  Kernel `teei_*` threads are not substitutes for those services.
- The currently installed bring-up image predates the gated crypto integration.
  Enabling flags alone will not supply service ordering, permissions or storage
  dependencies. A separate `vold` process is not required by TWRP's libvold path.

The prior raw F2FS magic mismatch is consistent with missing metadata decryption.
It is not evidence sufficient to diagnose corruption or justify formatting.

## Exact firmware service identities

| Stock service | Executable | User / groups | Stock class |
| --- | --- | --- | --- |
| `teei_daemon` | `/vendor/bin/teei_daemon` | system / system | core; disabled, explicitly started on fs |
| `vendor.keymaster-4-0-beanpod` | `/vendor/bin/hw/android.hardware.keymaster@4.0-service.beanpod` | system / system drmrpc | early_hal |
| `vendor.gatekeeper-1-0` | `/vendor/bin/hw/android.hardware.gatekeeper@1.0-service` | system / system | hal |
| `thh-2-0` | `/vendor/bin/hw/vendor.microtrust.hardware.thh@2.0-service` | system / system | late_start |

Gatekeeper declares `android.hardware.gatekeeper@1.0::IGatekeeper default`.
`microtrust.rc` supplies a long, device-specific list of `-r`/`-t` arguments to
TEE, device-node ownership, and persistent-storage setup. It must not be replaced
with a guessed bare service stanza. Nor should the entire stock rc be imported:
it also creates/chowns persistent directories, handles framework restart and
key provisioning. Attestation/keybox provisioning is outside this diagnostic.
THH is inventoried; its necessity for initial metadata decryption is unproven.

## Linker check, without starting HALs

For the four executables above, this diagnostic was run with a 10-second timeout:

```sh
LD_LIBRARY_PATH=/vendor/lib:/vendor/lib/hw:/system/lib timeout 10 /system/bin/linker --list /vendor/bin/teei_daemon
```

Each executable returned exit code 0 with resolved dependencies using those
explicit search paths. TEE resolved `libteei_daemon_vfs` from vendor; Keymaster
resolved `libTEECommon` and stock keymaster libraries from vendor, using recovery
libraries such as libcutils/libhidlbase where appropriate.

This verifies loader dependency resolution in the inspected image, **not** HAL
registration, secure-world initialization, runtime dlopen dependencies or
decryption. It does not configure the eventual init service environment.
The Android 12 linker list mode skips program constructors and execution:
[linker main](https://github.com/aosp-mirror/platform_bionic/blob/android12-release/linker/linker_main.cpp),
[constructor guard](https://github.com/aosp-mirror/platform_bionic/blob/android12-release/linker/linker_soinfo.cpp).

## Follow-up integration

The experimental profile is now implemented; see `CRYPTO_BRINGUP.md` for the
pre-metadata hook and remaining hardware acceptance criteria. Additional
read-only inspection confirmed Gatekeeper's `beanpod` selector and matching
HAL library, release 13, system/vendor patch 2026-01-05, `CONFIG_DM_DEFAULT_KEY=y`
and gzip-only ramdisk support. Gatekeeper's linker-list check also succeeded.
The vendor THH TA directory exists; its contents and encryption keys were not
read. Temporary read-only mounts were removed normally; no crypto HAL was
started on the live device during preparation.

Earlier checklist, retained as hardware-review criteria:

1. Add reviewed service definitions, permissions and exact TEE arguments in a
   gated recovery integration; determine which persistent paths are genuinely
   needed before starting the proprietary daemon. Do not grant broad access or
   create/provision keys as a workaround.
2. Keep vendor mounted for crypto startup and supply the tested ARM32 library
   search paths per service. Verify dynamic HAL loads and HIDL registration.
3. Enable/build TWRP's crypto support only with that integration available.
   Check the 32 MiB boot limit, header v2 geometry, exact stock zImage and DTB.
4. Agree on a separate device test with stock boot recovery available. Check
   metadata mapping first, then F2FS, then owner-entered credential decryption.
   Never copy keys, request a PIN, format userdata/metadata, or repair raw
   encrypted blocks.

The offline evaluator and configuration tests do not satisfy these hardware
acceptance criteria. Crypto remains disabled by default; the separate
experimental build is not a verified fix.
