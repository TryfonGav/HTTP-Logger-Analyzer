# libhttplogger_core: capture, parsing, storage, analysis and export.
# Has no GUI dependency, so the CLI, the Qt app and the tests all link the same code.
add_library(httplogger_core
    src/version.cpp
    # Phase 2+: add sources under src/capture, src/parser, src/storage, src/analyzer, src/export
)
add_library(httplogger::core ALIAS httplogger_core)

target_include_directories(httplogger_core PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>)

configure_file(src/version_config.hpp.in
    ${CMAKE_CURRENT_BINARY_DIR}/generated/version_config.hpp @ONLY)
target_include_directories(httplogger_core PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/generated)

httplogger_set_warnings(httplogger_core)
httplogger_enable_sanitizers(httplogger_core)

# Phase 2: link third-party libraries from vcpkg, e.g.
# find_package(asio CONFIG REQUIRED)
# find_package(llhttp CONFIG REQUIRED)
# find_package(unofficial-sqlite3 CONFIG REQUIRED)
# target_link_libraries(httplogger_core PUBLIC asio::asio llhttp::llhttp_static unofficial::sqlite3::sqlite3)
