LOCAL_PATH := device/lenovo/TB300FU

PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_SHIPPING_API_LEVEL := 31

PRODUCT_PACKAGES += \
    fastbootd

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt6761.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6761.rc \
    $(LOCAL_PATH)/recovery/root/init.recovery.mt8766.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt8766.rc \
    $(LOCAL_PATH)/recovery/root/system/etc/recovery.fstab:$(TARGET_COPY_OUT_RECOVERY)/root/system/etc/recovery.fstab \
    $(LOCAL_PATH)/recovery/root/first_stage_ramdisk/fstab.mt6761:$(TARGET_COPY_OUT_RECOVERY)/root/first_stage_ramdisk/fstab.mt6761 \
    $(LOCAL_PATH)/recovery/root/first_stage_ramdisk/fstab.mt8766:$(TARGET_COPY_OUT_RECOVERY)/root/first_stage_ramdisk/fstab.mt8766

# Experimental profile; services use this tablet's mounted stock vendor.
ifeq ($(TB300FU_ENABLE_CRYPTO),true)
PRODUCT_PACKAGES += tb300fu_crypto_probe
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.crypto.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.crypto.rc \
    $(LOCAL_PATH)/recovery/root/system/bin/tb300fu-crypto-prepare.sh:$(TARGET_COPY_OUT_RECOVERY)/root/system/bin/tb300fu-crypto-prepare.sh
endif
