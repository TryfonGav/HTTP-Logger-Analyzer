# httplogger-gui: Qt 6 desktop app for beginners (Phase 3).
# Enable with -DHTTPLOGGER_BUILD_GUI=ON once Qt 6 is installed.
find_package(Qt6 REQUIRED COMPONENTS Widgets)
qt_standard_project_setup()

qt_add_executable(httplogger-gui main.cpp)
target_link_libraries(httplogger-gui PRIVATE httplogger::core Qt6::Widgets)
httplogger_set_warnings(httplogger-gui)
