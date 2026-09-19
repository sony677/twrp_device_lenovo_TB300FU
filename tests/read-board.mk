include BoardConfig.mk
.PHONY: inspect
inspect:
	@printf 'mtp_excluded=%s crypto=%s\n' '$(TW_EXCLUDE_MTP)' '$(TW_INCLUDE_CRYPTO)'
