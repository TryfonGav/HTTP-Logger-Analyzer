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

add_executable(httplogger_unit_tests
    unit/test_version.cpp
)
target_link_libraries(httplogger_unit_tests PRIVATE httplogger::core GTest::gtest_main)
httplogger_enable_sanitizers(httplogger_unit_tests)
gtest_discover_tests(httplogger_unit_tests)

# Phase 2: add integration/ tests (proxy + local test server end to end)
# Phase 5: add fuzz/ targets (libFuzzer, Clang only)
