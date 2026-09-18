DEVICE_PATH := device/lenovo/TB300FU

# Temporary bring-up allowances. Tighten these after the first successful build.
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# Architecture: the stock userspace and kernel are ARM32.
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a53
TARGET_USES_64_BIT_BINDER := true
TARGET_SUPPORTS_32_BIT_APPS := true
TARGET_SUPPORTS_64_BIT_APPS := false

# Platform / bootloader identity.
TARGET_BOARD_PLATFORM := mt6761
TARGET_BOARD_NAME := tc422_wifi
TARGET_BOOTLOADER_BOARD_NAME := tc422_wifi
TARGET_NO_BOOTLOADER := true
TARGET_OTA_ASSERT_DEVICE := TB300FU,TB300FU_S,tc422_wifi

# Stock kernel and DTB extracted from TB300FU_S101116_251224_ROW.
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
TARGET_FORCE_PREBUILT_KERNEL := true
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb.img
BOARD_KERNEL_IMAGE_NAME := kernel
TARGET_KERNEL_ARCH := arm
TARGET_KERNEL_HEADER_ARCH := arm

# Stock boot.img header v2 geometry.
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x11b00000
BOARD_KERNEL_TAGS_OFFSET := 0x07880000
BOARD_DTB_OFFSET := 0x07880000
BOARD_KERNEL_PAGESIZE := 2048
# The TWRP build appends buildvariant=eng. Do not force recovery on normal boot.
BOARD_KERNEL_CMDLINE := bootopt=64S3,32S1,32S1
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)

# Partition sizes.
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_FLASH_BLOCK_SIZE := 131072

# Recovery lives in boot; there is no recovery partition.
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += boot
AB_OTA_PARTITIONS += dtbo
AB_OTA_PARTITIONS += system
AB_OTA_PARTITIONS += vendor
AB_OTA_PARTITIONS += product
AB_OTA_PARTITIONS += vbmeta
AB_OTA_PARTITIONS += vbmeta_system
AB_OTA_PARTITIONS += vbmeta_vendor
BOARD_USES_RECOVERY_AS_BOOT := true
TARGET_NO_RECOVERY := true
TW_HAS_NO_RECOVERY_PARTITION := true

# Dynamic partitions. super is 0x11f800000 bytes in the stock scatter.
BOARD_SUPER_PARTITION_SIZE := 4823449600
BOARD_SUPER_PARTITION_GROUPS := main
BOARD_MAIN_SIZE := 4819255296
BOARD_MAIN_PARTITION_LIST := system vendor product
BOARD_BUILD_SUPER_IMAGE_BY_DEFAULT := false

# System-as-root and separated output trees.
# This prevents recovery HAL files from creating recovery/root/vendor before
# the base ramdisk installs its /vendor symlink.
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_PRODUCT := product

# Filesystems.
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USES_METADATA_PARTITION := true
BOARD_ROOT_EXTRA_FOLDERS += metadata
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

# Recovery UI and MediaTek bring-up.
BOARD_USES_MTK_HARDWARE := true
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TW_THEME := portrait_hdpi
TW_DEFAULT_LANGUAGE := en
TW_EXTRA_LANGUAGES := false
TW_NO_SCREEN_BLANK := true
TW_SCREEN_BLANK_ON_BOOT := false
TW_HAS_MTP := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
# Keep fastbootd support, but omit twrpfastboot=1 so normal boot can reach Android.
TW_NO_FASTBOOT_BOOT := true
TW_INCLUDE_FASTBOOTD := true
TW_INCLUDE_LPDUMP := true
TW_INCLUDE_LPTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_TWRPAPP := false
TW_PREPARE_DATA_MEDIA_EARLY := true
RECOVERY_SDCARD_ON_DATA := true
TW_INTERNAL_STORAGE_PATH := "/data/media/0"
TW_INTERNAL_STORAGE_MOUNT_POINT := "data"
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true

# AVB footer is added explicitly by the build workflow with algorithm NONE.
BOARD_AVB_ENABLE := false

# Initial bring-up deliberately excludes credential/FBE decryption.
# Add the Microtrust/Beanpod services and crypto flags only after UI/ADB is stable.
