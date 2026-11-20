#include "httplogger/version.hpp"

#include <algorithm>
#include <gtest/gtest.h>

TEST(Version, IsSemanticVersion) {
    const auto v = httplogger::version();
    ASSERT_FALSE(v.empty());
    // MAJOR.MINOR.PATCH -> exactly two dots
    EXPECT_EQ(std::count(v.begin(), v.end(), '.'), 2);
}
