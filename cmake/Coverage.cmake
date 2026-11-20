# Adds code-coverage instrumentation when HTTPLOGGER_COVERAGE=ON (GCC/Clang only).
# Running the tests then writes .gcda files next to the object files, and gcovr turns them into
# a report (see the "Coverage" section of CONTRIBUTING.md). MSVC has no --coverage flag; there
# coverage would need a different tool, so we only measure it on Linux in CI.
if(HTTPLOGGER_COVERAGE AND MSVC)
    message(WARNING "HTTPLOGGER_COVERAGE is ignored with MSVC: coverage needs GCC or Clang "
                    "(it runs in the Linux CI job).")
endif()

function(httplogger_enable_coverage target)
    if(HTTPLOGGER_COVERAGE AND NOT MSVC)
        # -O0 keeps every source line in the binary, so the report matches the code you read.
        target_compile_options(${target} PRIVATE --coverage -O0 -g)
        target_link_options(${target} PRIVATE --coverage)
    endif()
endfunction()
