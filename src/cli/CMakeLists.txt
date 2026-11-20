# httplog: command-line front end for power users and scripting.
add_executable(httplog main.cpp)
target_link_libraries(httplog PRIVATE httplogger::core)
httplogger_set_warnings(httplog)
httplogger_enable_sanitizers(httplog)

# Phase 2: find_package(CLI11 CONFIG REQUIRED) and link CLI11::CLI11
