# Contributing and coding conventions

> Draft: to be rewritten by the author.

## Coding style

The code is meant to be easy to read and to explain line by line, so it stays deliberately plain.

- **Plain building blocks:** simple `struct`s and classes, free functions, `std::string`,
  `std::vector`, `std::map`, and ordinary `if` / `for` / `while`.
- **Avoid:** templates and metaprogramming, operator overloading, inheritance hierarchies,
  nested lambdas, `auto` where the type is not obvious, concepts, ranges pipelines, coroutines
  and clever one-liners. Use `std::unique_ptr` only when it is really needed.
- **Short functions:** under about 40 lines, each doing one job.
- **Blocking code:** networking uses Asio's synchronous API with one `std::thread` per
  connection, not the asynchronous model.
- **Naming:** types in `PascalCase` (`HttpTransaction`), functions and variables in `camelCase`
  (`parseRequestLine`, `findHeader`), namespace `httplogger`, files in `snake_case`
  (`test_version.cpp`).
- **Comments:** above every block whose purpose is not obvious, a plain-English comment saying
  *why* it is there, not only what it does.
- **Errors:** fail with a clear message that says what went wrong and, where possible, how to
  fix it. Malformed input must never crash the program.
- **Tests:** every piece of new core logic gets GoogleTest tests in `tests/`.

Formatting is defined by [`.clang-format`](.clang-format) (4 spaces, 100 columns). The
clang-tidy checks are in [`.clang-tidy`](.clang-tidy), with a comment explaining each choice.

## Checking your code before a commit

[`scripts/hooks/pre-commit`](scripts/hooks/pre-commit) runs clang-format and clang-tidy on the
C++ files you are committing and stops the commit if either finds a problem. Turn it on once
per clone:

```bash
git config core.hooksPath scripts/hooks
```

- **clang-format** checks the staged version of each file and prints the command that fixes it.
- **clang-tidy** needs a configured `dev` build (`cmake --preset dev`), because it reads
  `build/dev/compile_commands.json`. Warnings stop the commit.
- To skip the hook for a single commit: `git commit --no-verify` (use rarely; CI still checks
  formatting).

The hook finds the tools through the `CLANG_FORMAT` and `CLANG_TIDY` environment variables, or
on `PATH`.

**Windows:** Visual Studio ships both tools in `VC\Tools\Llvm\bin` (component "C++ Clang tools
for Windows"). Point the variables at them once, for example:

```powershell
$llvm = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\Llvm\bin"
[Environment]::SetEnvironmentVariable("CLANG_FORMAT", "$llvm\clang-format.exe", "User")
[Environment]::SetEnvironmentVariable("CLANG_TIDY", "$llvm\clang-tidy.exe", "User")
```

clang-tidy finds the MSVC standard headers only in a terminal where the compiler is set up
("x64 Native Tools Command Prompt" or "Developer PowerShell" of the Visual Studio installation
that has the C++ workload). In any other terminal the hook skips clang-tidy and says so.

**Linux (Ubuntu 24.04):** `sudo apt install clang-format-18 clang-tidy-18`.

**Version note:** CI checks formatting with clang-format **18**. Other versions occasionally
format code differently, so the hook prints a warning when yours is not 18; if CI's format check
fails although the hook passed, that difference is the reason.

## Coverage

Coverage is measured with GCC and [gcovr](https://gcovr.com/) on Linux. MSVC has no
`--coverage` flag, so the `coverage` preset does nothing there apart from a warning.

```bash
cmake --preset coverage && cmake --build --preset coverage && ctest --preset coverage
mkdir -p build/coverage/report
gcovr --root . --filter src/core/ --html-details build/coverage/report/index.html build/coverage
```

Every CI run also does this in the "Linux GCC + coverage" job and uploads the report as the
**coverage-report** artifact (open the run on GitHub, then *Artifacts* at the bottom). The target
in the [test plan](docs/testing/TEST_PLAN.md) is not enforced yet.

## Branches, commits and pull requests

- One branch per issue: `feat/<issue-number>-<short-name>` (for example `feat/12-code-quality`).
- Small commits whose message says what changed and why.
- Pull requests use the [template](.github/pull_request_template.md) and contain
  `Closes #<issue-number>`. CI must be green before merging.
- Never commit captured traffic, real credentials or private keys.
