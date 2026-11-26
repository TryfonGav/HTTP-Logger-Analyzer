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
    unit/test_http_parser.cpp
    unit/test_proxy_request.cpp
)
target_link_libraries(dipper_unit_tests PRIVATE dipper::core GTest::gtest_main)
dipper_enable_sanitizers(dipper_unit_tests)
dipper_enable_coverage(dipper_unit_tests)
# gtest_add_tests finds the tests by reading the TEST(...) lines in the source files.
# We do not use gtest_discover_tests: it runs the test program and asks GoogleTest to write a
# JSON list into the build folder, and GoogleTest cannot open files whose path contains
# non-ASCII letters on Windows (for example a Greek "Desktop" folder), which breaks the build.
# The tests run from this folder (tests/) so they can open fixtures by a short relative path,
# e.g. "fixtures/http/request_get.http", which also avoids non-ASCII absolute paths.
gtest_add_tests(TARGET dipper_unit_tests WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

# Integration tests: a test client, the real proxy and a local test server, all on 127.0.0.1.
add_executable(dipper_integration_tests
    integration/test_server.cpp
    integration/test_proxy.cpp
)
target_link_libraries(dipper_integration_tests PRIVATE dipper::core GTest::gtest_main)
dipper_enable_sanitizers(dipper_integration_tests)
dipper_enable_coverage(dipper_integration_tests)
gtest_add_tests(TARGET dipper_integration_tests
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    TEST_LIST integrationTests)
# Networking tests could hang if something goes wrong, so CTest stops any that run too long.
set_tests_properties(${integrationTests} PROPERTIES TIMEOUT 60)

# Phase 5: add fuzz/ targets (libFuzzer, Clang only)
