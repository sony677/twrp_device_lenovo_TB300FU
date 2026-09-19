#!/usr/bin/env python3
"""Install a fail-closed pre-metadata hook in the reviewed TWRP 12.1 source.

Only a build-tree source file is changed. No device access. Exact anchors make
source drift an error, not a silently incomplete integration.
"""
from pathlib import Path
import argparse

REVIEWED_REVISION = "5c3d206a5eeb3d446bcda8248a405a4b278bab5c"
REPLACEMENTS = [
    (
        '\tif (Decrypt_Data && Decrypt_Data->Is_Encrypted && !Decrypt_Data->Is_Decrypted) {\n\t\tSet_Crypto_State();',
        '''\tif (Decrypt_Data && Decrypt_Data->Is_Encrypted && !Decrypt_Data->Is_Decrypted) {
        // TB300FU_CRYPTO_PRE_METADATA: vendor must precede metadata, not just CE.
        // Keymaster OS/patch binding must reflect installed Android, not TWRP 12.
        auto stock_property = [&](const char* name, const std::string& partition) {
            const auto value = TWFunc::Partition_Property_Get(name, *this, partition, "build.prop");
            if (value.empty() || TWFunc::Property_Override(name, value) != 0) {
                LOGERR("TB300FU: could not load stock crypto property %s; stopping.\\n", name);
                return false;
            }
            return true;
        };
        if (!stock_property("ro.build.version.release", Get_Android_Root_Path()) ||
            !stock_property("ro.build.version.security_patch", Get_Android_Root_Path()) ||
            !stock_property("ro.vendor.build.security_patch", "/vendor") ||
            !stock_property("ro.product.first_api_level", "/vendor")) return;
        if (!Mount_By_Path("/vendor", true) ||
            TWFunc::Exec_Cmd("timeout -s KILL 75 /system/bin/sh /system/bin/tb300fu-crypto-prepare.sh --run > /tmp/tb300fu-crypto.log 2>&1") != 0) {
            LOGERR("TB300FU: crypto preparation failed; see /tmp/tb300fu-crypto.log. No format/repair attempted.\\n");
            return;
        }
\t\tSet_Crypto_State();''',
    ),
    (
        '''\t\tif (Key_Directory_Partition != nullptr)
\t\t\tif (!Key_Directory_Partition->Is_Mounted())
\t\t\t\tMount_By_Path(Decrypt_Data->Key_Directory, false);''',
        '''        // TB300FU_CRYPTO_METADATA_MOUNT: never proceed with an empty key mount.
        if (Key_Directory_Partition == nullptr ||
            !Mount_By_Path(Decrypt_Data->Key_Directory, true)) {
            LOGERR("TB300FU: metadata partition is not mounted; stopping decrypt.\\n");
            return;
        }''',
    ),
    (
        '\t\t\t\tLOGINFO("Unable to decrypt metadata encryption\\n");',
        '''\t\t\t\tLOGINFO("Unable to decrypt metadata encryption\\n");
                // TB300FU_CRYPTO_NO_FDE_FALLBACK: stock is metadata-encrypted FBE.
                return;''',
    ),
    (
        '\tif (Partition != NULL) UnMount_By_Path("/vendor", false);',
        '''    // TB300FU_CRYPTO_KEEP_VENDOR: HALs dlopen libraries and TAs after startup.
    // This changes automatic cleanup only, not the owner's explicit mount UI.
    if (Partition != NULL && android::base::GetProperty("tb300fu.crypto.ready", "0") != "1")
        UnMount_By_Path("/vendor", false);''',
    ),
]


def transform(source):
    if all(source.count(new) == 1 for old, new in REPLACEMENTS):
        return source
    if "TB300FU_CRYPTO_" in source:
        raise ValueError("Partial or modified TB300FU hook; restore reviewed upstream source")
    for old, new in REPLACEMENTS:
        if source.count(old) != 1:
            raise ValueError("Unexpected TWRP source: crypto patch anchor missing or ambiguous")
    for old, new in REPLACEMENTS:
        source = source.replace(old, new, 1)
    return source


def transform_keystore(source):
    trigger = 'on late-init\n    start keystore2\n'
    service = 'service keystore2 /system/bin/keystore2 /tmp/misc/keystore\n'
    gated = service + '    # TB300FU_CRYPTO_KEYSTORE: start after stock OS binding and HALs.\n    disabled\n'
    if source.count(gated) == 1 and trigger not in source:
        return source
    if source.count(trigger) != 1 or source.count(service) != 1 or 'TB300FU_CRYPTO_' in source:
        raise ValueError('Unexpected keystore2 init source; refusing partial crypto integration')
    return source.replace(trigger, '', 1).replace(service, gated, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recovery_source", type=Path)
    args = parser.parse_args()
    path = args.recovery_source / "partitionmanager.cpp"
    keystore = args.recovery_source / "etc/init/keystore2.rc"
    original = path.read_text(encoding="utf-8")
    patched = transform(original)
    original_rc = keystore.read_text(encoding="utf-8")
    patched_rc = transform_keystore(original_rc)
    # Validate both inputs before changing either file.
    if patched != original:
        path.write_text(patched, encoding="utf-8")
    if patched_rc != original_rc:
        keystore.write_text(patched_rc, encoding="utf-8")
    print("TB300FU pre-metadata hook verified (reviewed upstream " + REVIEWED_REVISION + ")")


if __name__ == "__main__":
    main()
