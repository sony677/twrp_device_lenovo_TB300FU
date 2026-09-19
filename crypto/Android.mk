LOCAL_PATH := $(call my-dir)
ifeq ($(TB300FU_ENABLE_CRYPTO),true)
include $(CLEAR_VARS)
LOCAL_MODULE := tb300fu_crypto_probe
LOCAL_SRC_FILES := probe.cpp
LOCAL_CFLAGS := -Wall -Wextra -Werror
LOCAL_SHARED_LIBRARIES := libbinder libutils libhidlbase liblog \
    android.hardware.keymaster@4.0 android.hardware.gatekeeper@1.0
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_PATH := $(TARGET_RECOVERY_ROOT_OUT)/system/bin
include $(BUILD_EXECUTABLE)
endif
