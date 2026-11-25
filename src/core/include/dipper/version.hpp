#pragma once

#include <string_view>

namespace dipper {

/// Semantic version of the library, e.g. "0.1.0".
[[nodiscard]] std::string_view version() noexcept;

} // namespace dipper
