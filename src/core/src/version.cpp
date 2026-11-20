#include "httplogger/version.hpp"

#include "version_config.hpp"

namespace httplogger {

std::string_view version() noexcept {
    return HTTPLOGGER_VERSION_STRING;
}

} // namespace httplogger
