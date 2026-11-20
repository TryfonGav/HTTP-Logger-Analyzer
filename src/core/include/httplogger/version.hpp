#pragma once

#include <string_view>

namespace httplogger {

/// Semantic version of the library, e.g. "0.1.0".
[[nodiscard]] std::string_view version() noexcept;

} // namespace httplogger
