# dipper: command-line front end for power users and scripting.
add_executable(dipper main.cpp)
target_link_libraries(dipper PRIVATE dipper::core)
dipper_set_warnings(dipper)
dipper_enable_sanitizers(dipper)
dipper_enable_coverage(dipper)

# Phase 2: find_package(CLI11 CONFIG REQUIRED) and link CLI11::CLI11
