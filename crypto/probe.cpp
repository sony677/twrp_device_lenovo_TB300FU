// Readiness checks only: no credentials, key generation, deletion or provisioning.
#include <android/hardware/gatekeeper/1.0/IGatekeeper.h>
#include <android/hardware/keymaster/4.0/IKeymasterDevice.h>
#include <binder/IServiceManager.h>
#include <utils/String16.h>
#include <cstdio>
#include <cstring>

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    if (std::strcmp(argv[1], "keymaster") == 0) {
        using namespace android::hardware::keymaster::V4_0;
        auto service = IKeymasterDevice::tryGetService();
        if (service == nullptr) return 1;
        bool hardware = false;
        auto result = service->getHardwareInfo(
            [&](SecurityLevel level, const auto&, const auto&) {
                hardware = level == SecurityLevel::TRUSTED_ENVIRONMENT;
            });
        if (!result.isOk() || !hardware) return 1;
    } else if (std::strcmp(argv[1], "gatekeeper") == 0) {
        using android::hardware::gatekeeper::V1_0::IGatekeeper;
        if (IGatekeeper::tryGetService() == nullptr) return 1;
    } else if (std::strcmp(argv[1], "keystore") == 0) {
        auto manager = android::defaultServiceManager();
        if (manager == nullptr || manager->checkService(android::String16(
                "android.system.keystore2.IKeystoreService/default")) == nullptr) return 1;
    } else {
        return 2;
    }
    std::printf("%s: ready\n", argv[1]);
    return 0;
}
