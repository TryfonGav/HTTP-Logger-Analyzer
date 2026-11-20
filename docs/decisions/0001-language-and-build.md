# ADR-0001: C++20 with CMake and vcpkg

- **Status:** proposed
- **Date:** YYYY-MM-DD
- **Related issue:** Record key design decisions as ADRs

## Context

The supervisor assigned C++ for the project. The tool must build on Windows, Linux and macOS,
and the supervisor and examiners must be able to build it without manual dependency setup.

## Options considered

| Option | Pros | Cons |
| --- | --- | --- |
| CMake + vcpkg (manifest) | Industry standard; pinned, reproducible dependencies; works with MSVC, GCC, Clang | First dependency build is slow (mitigated by CI cache) |
| CMake + Conan | Similar reproducibility | Extra Python tooling |
| CMake + FetchContent only | No package manager | Long configure times; awkward for C libraries such as SQLite |

## Decision

_Complete after discussing with the supervisor._

## Consequences

_Fill in._
