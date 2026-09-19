#!/system/bin/sh
# Called synchronously before TWRP metadata decrypt, not at Android boot.
# Does not read keys, format storage, provision hardware, or mount userdata.

crypto_prop() { getprop "$1"; }
crypto_setprop() { setprop "$1" "$2"; }
crypto_probe() { timeout -s KILL 2 /system/bin/tb300fu_crypto_probe "$1"; }

crypto_preflight() {
    grep -q ' /vendor .* ro[, ]' /proc/mounts || {
        echo 'Vendor is not mounted read-only'; return 1;
    }
    grep -Fqx 'ro.vendor.build.fingerprint=Lenovo/TB300FU_S/TB300FU:13/TP1A.220624.014/S101116_251224_ROW:user/release-keys' /vendor/build.prop || {
        echo 'Unreviewed vendor fingerprint; refusing HAL startup'; return 1;
    }
    [ "$(crypto_prop ro.hardware.gatekeeper)" = beanpod ] || {
        echo 'Missing stock Gatekeeper selector'; return 1;
    }
    for node in teei_client teei_config tz_vfs ut_keymaster rpmb0 mmcblk0rpmb; do
        [ -c "/dev/$node" ] || { echo "Missing TEE node: $node"; return 1; }
    done
    for executable in /vendor/bin/teei_daemon \
        /vendor/bin/hw/android.hardware.keymaster@4.0-service.beanpod \
        /vendor/bin/hw/android.hardware.gatekeeper@1.0-service; do
        [ -x "$executable" ] || { echo "Missing service: $executable"; return 1; }
        LD_LIBRARY_PATH=/vendor/lib:/vendor/lib/hw:/system/lib \
            timeout -s KILL 3 /system/bin/linker --list "$executable" >/dev/null 2>&1 || {
                echo "Unresolved dependency: $executable"; return 1;
            }
    done
    [ -r /vendor/lib/hw/gatekeeper.beanpod.so ] || return 1
    [ -x /system/bin/keystore2 ] && [ -x /system/bin/tb300fu_crypto_probe ]
}

crypto_wait() {
    kind=$1
    attempts=$2
    while [ "$attempts" -gt 0 ]; do
        if crypto_probe "$kind"; then return 0; fi
        attempts=$((attempts - 1))
        sleep 1
    done
    echo "TIMEOUT: $kind not ready; metadata decrypt will not be attempted"
    return 1
}

crypto_prepare() {
    crypto_setprop tb300fu.crypto.ready 0 || return 1
    crypto_preflight || return 1
    # These services are disabled in init: no automatic early/late class startup.
    crypto_setprop ctl.start teei_daemon || return 1
    attempts=5
    while [ "$(crypto_prop init.svc.teei_daemon)" != running ]; do
        attempts=$((attempts - 1))
        [ "$attempts" -gt 0 ] || { echo 'TEE daemon did not start'; return 1; }
        sleep 1
    done
    # Process existence alone is not readiness: query the registered HAL below.
    crypto_setprop ctl.start vendor.keymaster-4-0-beanpod || return 1
    crypto_wait keymaster 8 || return 1
    crypto_setprop ctl.start vendor.gatekeeper-1-0 || return 1
    crypto_wait gatekeeper 4 || return 1
    crypto_setprop ctl.start keystore2 || return 1
    crypto_wait keystore 6 || return 1
    crypto_setprop tb300fu.crypto.ready 1 || return 1
    echo 'Crypto services ready (this does NOT prove /data is decrypted)'
}

# Sourcing defines functions only, enabling host-side failure/ordering tests.
if [ "${1:-}" = --run ]; then
    crypto_prepare
fi
