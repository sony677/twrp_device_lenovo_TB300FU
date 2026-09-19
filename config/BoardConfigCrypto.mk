# TWRP 12.1 enables FBE and metadata decrypt with TW_INCLUDE_CRYPTO.
# The recovery process links libvold; a standalone vold daemon is not required.
# Do not enable this profile until the stock HAL service definitions and their
# dependencies have been collected and integrated.
ifeq ($(wildcard $(DEVICE_PATH)/recovery/root/init.recovery.crypto.rc),)
$(error TB300FU crypto integration incomplete: collect stock vendor evidence with scripts/Collect-TB300FU.ps1 and integrate init.recovery.crypto.rc first)
endif
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_LIBRESETPROP := true
