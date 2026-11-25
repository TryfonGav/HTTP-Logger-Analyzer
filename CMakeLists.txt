cmake_minimum_required(VERSION 3.25)

# The presets load vcpkg from $VCPKG_ROOT. If that variable is not set, CMake only says
# "Could not find toolchain file: /scripts/buildsystems/vcpkg.cmake", which is confusing.
# This check runs before project() (where the toolchain file is loaded) and explains the fix.
if(DEFINED CMAKE_TOOLCHAIN_FILE AND NOT EXISTS "${CMAKE_TOOLCHAIN_FILE}")
    message(FATAL_ERROR
        "vcpkg was not found (looked for: ${CMAKE_TOOLCHAIN_FILE}).\n"
        "Set the VCPKG_ROOT environment variable to your vcpkg folder, open a new terminal "
        "and run the preset again. See 'Build from source' in README.md.")
endif()

project(dipper
    VERSION 0.1.0
    DESCRIPTION "Dipper: an HTTP traffic recorder and analyzer"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(DIPPER_BUILD_TESTS  "Build unit and integration tests"        ON)
option(DIPPER_BUILD_GUI    "Build the Qt 6 desktop application"       OFF)
option(DIPPER_SANITIZERS   "Enable AddressSanitizer + UBSan (GCC/Clang)" OFF)
option(DIPPER_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(CompilerWarnings)
include(Sanitizers)

add_subdirectory(src/core)
add_subdirectory(src/cli)

if(DIPPER_BUILD_GUI)
    add_subdirectory(src/gui)
endif()

if(DIPPER_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()
