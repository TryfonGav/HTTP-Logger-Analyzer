cmake_minimum_required(VERSION 3.25)

project(httplogger
    VERSION 0.1.0
    DESCRIPTION "HTTP Logger and Analyzer"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(HTTPLOGGER_BUILD_TESTS  "Build unit and integration tests"        ON)
option(HTTPLOGGER_BUILD_GUI    "Build the Qt 6 desktop application"       OFF)
option(HTTPLOGGER_SANITIZERS   "Enable AddressSanitizer + UBSan (GCC/Clang)" OFF)
option(HTTPLOGGER_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CompilerWarnings)
include(Sanitizers)

add_subdirectory(src/core)
add_subdirectory(src/cli)

if(HTTPLOGGER_BUILD_GUI)
    add_subdirectory(src/gui)
endif()

if(HTTPLOGGER_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
