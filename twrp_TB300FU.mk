$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
$(call inherit-product, device/lenovo/TB300FU/device.mk)

PRODUCT_DEVICE := TB300FU
PRODUCT_NAME := twrp_TB300FU
PRODUCT_BRAND := Lenovo
PRODUCT_MODEL := Lenovo Tab M8 (4th Gen)
PRODUCT_MANUFACTURER := Lenovo
PRODUCT_RELEASE_NAME := TB300FU

PRODUCT_BUILD_PROP_OVERRIDES += \
    TARGET_DEVICE=TB300FU \
    PRODUCT_NAME=TB300FU_S
