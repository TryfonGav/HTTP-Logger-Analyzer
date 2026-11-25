#include "dipper/version.hpp"

#include <iostream>
#include <string_view>

int main(int argc, char* argv[]) {
    if (argc > 1 && std::string_view{argv[1]} == "--version") {
        std::cout << "dipper " << dipper::version() << '\n';
        return 0;
    }

    std::cout << "dipper " << dipper::version() << "\n"
              << "Usage: dipper --version\n"
              << "(capture, list and export subcommands arrive in Phase 2)\n";
    return 0;
}
