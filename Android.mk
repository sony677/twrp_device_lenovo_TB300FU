LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),TB300FU)
include $(call all-makefiles-under,$(LOCAL_PATH))
endif
