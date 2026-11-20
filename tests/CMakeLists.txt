# Tests use GoogleTest. With vcpkg the package is found directly;
# without vcpkg it is downloaded once via FetchContent.
find_package(GTest CONFIG QUIET)
if(NOT GTest_FOUND)
    include(FetchContent)
    FetchContent_Declare(googletest
        URL https://github.com/google/googletest/archive/refs/tags/v1.15.2.tar.gz
        DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
    set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
    FetchContent_MakeAvailable(googletest)
endif()

include(GoogleTest)

add_executable(dipper_unit_tests
    unit/test_version.cpp
    unit/test_http_transaction.cpp
)
target_link_libraries(dipper_unit_tests PRIVATE dipper::core GTest::gtest_main)
dipper_enable_sanitizers(dipper_unit_tests)
dipper_enable_coverage(dipper_unit_tests)
# gtest_add_tests finds the tests by reading the TEST(...) lines in the source files.
# We do not use gtest_discover_tests: it runs the test program and asks GoogleTest to write a
# JSON list into the build folder, and GoogleTest cannot open files whose path contains
# non-ASCII letters on Windows (for example a Greek "Desktop" folder), which breaks the build.
gtest_add_tests(TARGET dipper_unit_tests)

# Phase 2: add integration/ tests (proxy + local test server end to end)
# Phase 5: add fuzz/ targets (libFuzzer, Clang only)
