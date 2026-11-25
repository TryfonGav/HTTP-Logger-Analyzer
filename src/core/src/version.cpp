#include "dipper/version.hpp"

#include "version_config.hpp"

namespace dipper {

std::string_view version() noexcept {
    return DIPPER_VERSION_STRING;
}

} // namespace dipper
