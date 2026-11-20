#include "httplogger/version.hpp"

#include <iostream>
#include <string_view>

// clang-tidy warns that std::cout could in theory throw an exception out of main. In practice it
// does not (we never turn on stream exceptions), and even a try/catch could not fully silence the
// warning because printing the error message could throw too. So we accept it here.
// NOLINTNEXTLINE(bugprone-exception-escape)
int main(int argc, char* argv[]) {
    if (argc > 1 && std::string_view{argv[1]} == "--version") {
        std::cout << "httplog " << httplogger::version() << '\n';
        return 0;
    }

    std::cout << "httplog " << httplogger::version() << "\n"
              << "Usage: httplog --version\n"
              << "(capture, list and export subcommands arrive in Phase 2)\n";
    return 0;
}
