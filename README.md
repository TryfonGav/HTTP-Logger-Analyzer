# HTTP Logger & Analyzer

![CI](https://github.com/TryfonGav/HTTP-Logger-Analyzer/actions/workflows/ci.yml/badge.svg)

A cross-platform C++20 tool that records HTTP traffic and helps you understand it. Beginners
can start monitoring in a few clicks. Power users get a filter language, analytics, HTTPS
interception and a scriptable CLI.

> CCS3900 Individual Project, BSc Computer Science, CITY College, University of York Europe Campus, 2026–2027.
> Student: Tryfon Gavrilis.

---

## Features

| For beginners | For power users |
| --- | --- |
| First-run setup wizard (proxy port, browser setup, "capture is working" check) | Filter query language, e.g. `status:>=400 host:*.api.example.com time:>500ms` |
| One-click Start / Stop capture | Analytics: status mix, latency p50/p95/p99, top hosts |
| Live request table, colour-coded by status | Opt-in HTTPS interception with a local CA |
| Plain-language explanations of status codes and headers | Passive capture from a network interface (libpcap/Npcap) |
| Save and reopen sessions | Alert rules, request diff, edit and resend |
| Export to HAR / JSON / CSV | Headless CLI with JSON output for scripts |

_Status: planned features are tracked on the [project board](../../projects)._

## Screenshots

_Added in Phase 3._

## Quick start (users)

1. Download the latest release for your OS from [Releases](../../releases).
2. Run **HTTP Logger**; the setup wizard sets the proxy port (default `8080`).
3. Point your browser at the proxy, then open any website: requests appear live.

## Build from source

**Prerequisites:** a C++20 compiler (GCC 12+, Clang 15+ or MSVC 2022), CMake 3.25+, Ninja,
Git and [vcpkg](https://github.com/microsoft/vcpkg) with `VCPKG_ROOT` set. Qt 6 only for the GUI.
Dependency versions are pinned by `builtin-baseline` in `vcpkg.json`, so everyone gets the same ones.

### One-time setup on Windows

1. Install Visual Studio 2022 (Community or Build Tools) with the **Desktop development with C++**
   workload, plus [CMake](https://cmake.org/download/) and Git.
2. Install Ninja: `winget install --id Ninja-build.Ninja -e`
3. Install vcpkg and point `VCPKG_ROOT` at it (PowerShell):
   ```powershell
   git clone https://github.com/microsoft/vcpkg C:\vcpkg
   C:\vcpkg\bootstrap-vcpkg.bat -disableMetrics
   [Environment]::SetEnvironmentVariable("VCPKG_ROOT", "C:\vcpkg", "User")
   ```
   If you already have vcpkg, run `git pull` and `bootstrap-vcpkg.bat` in it instead: it must be
   at least as new as the `builtin-baseline` commit.
4. Open a **new** "x64 Native Tools Command Prompt for VS 2022" or "Developer PowerShell for
   VS 2022" from the Start menu (this puts the MSVC compiler on `PATH`) and build from there.

### One-time setup on Linux (Ubuntu 24.04)

```bash
sudo apt install build-essential cmake ninja-build git curl zip unzip tar pkg-config
git clone https://github.com/microsoft/vcpkg ~/vcpkg && ~/vcpkg/bootstrap-vcpkg.sh -disableMetrics
echo 'export VCPKG_ROOT="$HOME/vcpkg"' >> ~/.bashrc && source ~/.bashrc
```

### Build and test

```bash
cmake --preset dev          # configure (vcpkg builds dependencies on first run: 10-30 min)
cmake --build --preset dev  # build
ctest --preset dev          # run tests
./build/dev/src/cli/httplog --version
```

If configure stops with "vcpkg was not found", `VCPKG_ROOT` is not set in that terminal.

| Preset | Use |
| --- | --- |
| `dev` | Debug build for daily work |
| `asan` | Debug with AddressSanitizer + UBSan |
| `gui` | Debug including the Qt 6 app (`-DCMAKE_PREFIX_PATH=<Qt dir>`) |
| `release` | Optimised build |

## Usage

```bash
httplog capture --port 8080            # start the proxy and log to a session file
httplog list --filter "status:>=400"   # query a saved session
httplog export --format har -o out.har # export for browser DevTools
```
_CLI arrives in Phase 2; the commands above are the target interface._

## Repository layout

```
src/core/     libhttplogger_core: capture, parser, storage, analyzer, export (no GUI dependency)
src/cli/      httplog command-line tool
src/gui/      Qt 6 desktop app
tests/        unit, integration, fuzz tests and fixtures
bench/        performance benchmarks
docs/         requirements, architecture, ADRs, testing, evaluation, user guide, AI journal
project/      meeting-log mirror and planning material
scripts/      setup_github_board.sh and developer helpers
```

## Documentation

- [Architecture](docs/architecture/ARCHITECTURE.md)
- [Requirements (SRS)](docs/requirements/SRS.md)
- [Architecture decision records](docs/decisions/)
- [Test plan](docs/testing/TEST_PLAN.md)
- [User guide](docs/user-guide/)
- [AI journal](docs/ai-journal/AI_JOURNAL.md)

## Responsible use

Capture only traffic you own or are authorised to inspect. HTTPS interception is off by
default and must be enabled explicitly. Captured sessions can contain personal data and
credentials, so never commit them to a repository (they are git-ignored).

## Academic integrity

AI assistance is permitted for this project under an agreement with the supervisor, on the
condition that every use is recorded in [docs/ai-journal/AI_JOURNAL.md](docs/ai-journal/AI_JOURNAL.md).

## License

_To be decided with the supervisor (note: Qt Charts is GPLv3 under the open-source licence)._
