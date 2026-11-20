# libdipper_core: capture, parsing, storage, analysis and export.
# Has no GUI dependency, so the CLI, the Qt app and the tests all link the same code.
add_library(dipper_core
    src/version.cpp
    src/http_transaction.cpp
    # Phase 2+: add sources under src/capture, src/parser, src/storage, src/analyzer, src/export
)
add_library(dipper::core ALIAS dipper_core)

target_include_directories(dipper_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>)

configure_file(src/version_config.hpp.in
    ${CMAKE_CURRENT_BINARY_DIR}/generated/version_config.hpp @ONLY)
target_include_directories(dipper_core PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/generated)

dipper_set_warnings(dipper_core)
dipper_enable_sanitizers(dipper_core)
dipper_enable_coverage(dipper_core)

# Phase 2: link third-party libraries from vcpkg, e.g.
# find_package(asio CONFIG REQUIRED)
# find_package(llhttp CONFIG REQUIRED)
# find_package(unofficial-sqlite3 CONFIG REQUIRED)
# target_link_libraries(dipper_core PUBLIC asio::asio llhttp::llhttp_static unofficial::sqlite3::sqlite3)
