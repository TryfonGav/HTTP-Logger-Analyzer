# dipper-gui: Qt 6 desktop app for beginners (Phase 3).
# Enable with -DDIPPER_BUILD_GUI=ON once Qt 6 is installed.
find_package(Qt6 REQUIRED COMPONENTS Widgets)
qt_standard_project_setup()

qt_add_executable(dipper-gui main.cpp)
target_link_libraries(dipper-gui PRIVATE dipper::core Qt6::Widgets)
dipper_set_warnings(dipper-gui)
