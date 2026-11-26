# libdipper_core: capture, parsing, storage, analysis and export.
# Has no GUI dependency, so the CLI, the Qt app and the tests all link the same code.
add_library(dipper_core
    src/version.cpp
    src/http_transaction.cpp
    src/http_parser.cpp
    src/proxy_request.cpp
    src/proxy_server.cpp
    src/socket_wait.cpp
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

# llhttp (from vcpkg) does the low-level HTTP/1.x parsing for HttpParser. PUBLIC because
# dipper/http_parser.hpp includes llhttp.h, so everything that uses the header needs it too.
find_package(llhttp CONFIG REQUIRED)
target_link_libraries(dipper_core PUBLIC llhttp::llhttp_static)

# Asio (standalone, header-only) does the networking for the proxy. PUBLIC because
# dipper/proxy_server.hpp uses Asio socket types. spdlog writes the log lines; only our .cpp
# files use it, so it is PRIVATE.
find_package(asio CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
target_link_libraries(dipper_core PUBLIC asio::asio PRIVATE spdlog::spdlog)
# Turns off Asio's old (deprecated) functions. With them off, calls that report errors through an
# error_code argument return nothing, so there is no ignored return value to warn about.
target_compile_definitions(dipper_core PUBLIC ASIO_NO_DEPRECATED)
if(WIN32)
    # Asio needs to know the oldest Windows version to support; 0x0A00 is Windows 10.
    target_compile_definitions(dipper_core PUBLIC _WIN32_WINNT=0x0A00)
endif()

# Later in Phase 2: unofficial::sqlite3::sqlite3 (#25).
