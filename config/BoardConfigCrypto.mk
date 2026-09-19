# TWRP 12.1 enables FBE and metadata decrypt with TW_INCLUDE_CRYPTO.
# The recovery process links libvold; a standalone vold daemon is not required.
# The integration patch must be applied to the reviewed TWRP source first.
ifneq ($(TB300FU_CRYPTO_HOOK_APPLIED),true)
$(error TB300FU crypto hook missing: run scripts/patch-twrp-crypto.py before enabling this experimental profile)
endif
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_LIBRESETPROP := true
TW_USES_VENDOR_LIBS := true
