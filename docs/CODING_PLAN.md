# Dipper — step-by-step coding plan

Written 2026-11-26. Steps are in build order: each one depends on the ones above it.
Every step follows the same workflow: plan → student OK → branch `feat/<n>-<name>` from fresh
`main` → small commits + GoogleTest tests → PR description → stop.

## Where things stand (handover for the next session)

Last updated 2026-11-26, end of session 4.

- **Project name is Dipper.** Namespace `dipper`, headers in `src/core/include/dipper/`,
  CMake options `DIPPER_*`, targets `dipper_core` (alias `dipper::core`), `dipper` (CLI),
  `dipper_unit_tests`, session files `*.dipper`. GitHub repo still `HTTP-Logger-Analyzer`.
- **#12 merged** (PR #78, squash `a92e116`). **#16 merged** (PR #79). The PR #78 description
  on GitHub contains some pasted chat text; the student may clean it up.
- **#20 done locally** on `feat/20-http-parser` (3 commits on top of `a92e116`, not pushed):
  `HttpParser` on llhttp, 17 CRLF fixtures in `tests/fixtures/http/`, 26 tests (41 total
  pass on MSVC `dev` + `ci`), ARCHITECTURE §3 "Parser". PR description is in the session
  scratchpad (`pr-20.md`); the student pushes and opens the PR. Linux CI not yet seen:
  watch GCC/Clang `-Wconversion`/`-Wsign-conversion` and ASan results.
- **Next: #21 forward proxy** (only after the student says go). Design in the Phase 2 table
  below; it will call `HttpParser` and needs approval to add Asio (already in `vcpkg.json`)
  and spdlog.
- **Ruleset "Main Branch Rules" (id 28120243)** targets `main` only: PR, green checks,
  no force-push, linear history → merge with "Squash and merge" or "Rebase and merge".
- **Local branches:** `feat/12-code-quality` and `feat/16-data-model` are merged — ask before
  deleting them.
- **Local clang-tidy** crashes at the Greek repo path. Workaround: copy the files, `.clang-tidy`
  and any needed headers (e.g. `llhttp.h` from `build/dev/vcpkg_installed/x64-windows/include`)
  to an ASCII scratch folder and run `clang-tidy file.cpp -- --driver-mode=cl /std:c++20 /EHsc
  /Isrc/include /imsvc ext` inside the VS Build Tools environment.
- **PowerShell 5.1 breaks `git commit -m` messages containing double quotes**; commit with
  `git commit -F <file>` instead.
- **Never commit** `.gitignore` (local AI-journal line) or `docs/ai-journal/AI_JOURNAL.md`.
  This file (`docs/CODING_PLAN.md`) is also uncommitted unless the student decides otherwise.
  `git switch` fails while `.gitignore` is modified: `git stash push -- .gitignore`, switch,
  `git stash pop`.

## Phase 1 — Foundation (M2)

| Step | Issue | What | Status |
|---|---|---|---|
| 1 | #12 | clang-format, clang-tidy, coverage | Merged (PR #78) |
| 2 | #16 | `HttpTransaction` data model + Dipper rename | Merged (PR #79) |

## #20 plan (approved: llhttp + 10 MiB cap; implemented on `feat/20-http-parser`)

- `src/core/include/dipper/http_parser.hpp`, `src/core/src/http_parser.cpp`: `enum class
  ParserMode { Requests, Responses }` and `class HttpParser` wrapping llhttp. One parser per
  direction of a connection. llhttp callbacks are private static member functions (no
  lambdas); set `parser_.data = this` at the start of every `feed()`.
  ```cpp
  explicit HttpParser(ParserMode mode, std::int64_t maxBodyBytes = kDefaultMaxBodyBytes);
  bool feed(const char* data, std::size_t size); // false = not valid HTTP
  bool finish();                     // connection closed: ends read-until-close bodies
  void setNextResponseIsForHead();   // HEAD responses: headers, no body (reset after a >=200 response)
  bool hasError() const;  const std::string& errorMessage() const;
  bool isUpgraded() const;           // CONNECT / Upgrade (HPE_PAUSED_UPGRADE): stop; tunnel is #22
  std::vector<HttpRequest> takeRequests();
  std::vector<HttpResponse> takeResponses();
  ```
- Callbacks append (llhttp may split URL/header pieces across `feed` calls); use llhttp 9's
  `on_header_field_complete` / `on_header_value_complete` to finish each header. Chunked
  framing is removed by llhttp, so `body` holds decoded bytes. After `maxBodyBytes` stop
  storing body bytes but keep counting `bodySize`. Errors: llhttp errno name + reason;
  parser stays failed.
- `src/core/CMakeLists.txt`: `find_package(llhttp CONFIG REQUIRED)`,
  `target_link_libraries(dipper_core PUBLIC llhttp::llhttp_static)` (PUBLIC: header includes
  `llhttp.h`).
- Fixtures: `tests/fixtures/http/*.http` with real CRLF; new `.gitattributes` line
  `tests/fixtures/http/*.http -text` (student has `core.autocrlf=true`). `tests/CMakeLists.txt`:
  `gtest_add_tests(... WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})` so tests open
  `fixtures/http/x.http` by relative path (Greek-path workaround).
- ~20 tests: GET (repeated + mixed-case headers), POST Content-Length, chunked POST,
  keep-alive (two `feed` calls), pipelined (one buffer), CONNECT → upgraded; response 200,
  chunked, read-until-close + `finish()`, 204/304, HEAD; every fixture fed one byte at a time
  equals all-at-once; body cap; malformed request line / header / chunk size / status line /
  truncated-then-`finish()` → error, no crash.
- Short parser paragraph in ARCHITECTURE.md. Not in #20: content-encoding (#27), timings
  (#23), tunnel bytes (#22), header size limit (revisit with fuzzing, #59).

## Phase 2 — Core logging → v0.1.0 (M2)

| Step | Issue | What to build | Done when |
|---|---|---|---|
| 3 | #20 | **HTTP parser** on llhttp: feed bytes, get finished requests/responses as structs | Fixtures pass: GET, POST, chunked, keep-alive, pipelined, malformed → error (never crash). Fixtures use relative paths |
| 4 | #21 | **Forward proxy**: blocking Asio, one thread per connection, `127.0.0.1:8080` (configurable). Read request → connect server → forward → stream response back in fixed-size chunks → build `HttpTransaction` → callback + spdlog line. CONNECT → 501 for now | Integration test: client → proxy → local test server. Failures (DNS, refused, timeout) produce a transaction with an error. Update ARCHITECTURE §6 + draft ADR |
| 5 | #22 | **HTTPS CONNECT tunnel**: reply 200, copy bytes both ways, record host/port only | Test through a local TLS server |
| 6 | #23 | **Timings**: DNS, connect, TTFB, total with `steady_clock` | Tests with a deliberately slow local server |
| 7 | #24 | **Capture pipeline**: `mutex` + `condition_variable` + `deque` queue from proxy threads to one writer thread | Many threads push, nothing lost; clean stop/flush |
| 8 | #25 | **SQLite store**: schema, WAL, body size cap, `saveTransaction` / `loadTransaction` | Round-trip test: save → load → equal |
| 9 | #26 | **Query API**: filter by host / status / method / time, paging | Unit test per filter |
| 10 | #28 | **Export** HAR 1.2 / JSON / CSV | HAR opens in browser DevTools; CSV escaping tests |
| 11 | #29 | **CLI v1**: `dipper capture`, `dipper list`, `dipper export` | Manual check + tests |
| 12 | #31 | **End-to-end tests** in CI: proxy → store → export | Green on all 3 OSes |
| 13 | #32 | **Release v0.1.0** | Tag, release notes, binaries |
| — | #27, #30 | Body decoding (gzip/deflate, content type); config file | "Should" priority — may move after v0.1 |

## Phase 3 — Beginner GUI (M3)

| Step | Issue | What |
|---|---|---|
| 14 | #33 | Qt 6 window shell linked to the core library |
| 15 | #35 | Start/stop button; proxy on a background thread → GUI via queued signal |
| 16 | #36 | Live request table, colour-coded by status |
| 17 | #37 | Detail panel: headers, body, timings |
| 18 | #41 | Save / open sessions (reuse SQLite files) |
| 19 | #38 | Search + quick filters (uses query API from step 9) |
| 20 | #34 | First-run wizard with "capture is working" check |
| 21 | #40, #39, #42 | Empty/loading/error states; plain-language glossary; accessibility |
| 22 | #43 | Beginner quick-start guide |

## Phase 4 — Power-user features → v0.9 (M3)

| Step | Issue | What |
|---|---|---|
| 23 | #44 | **Filter language**: tokenizer → parser → `Filter` struct → `matches()`. Heavy tests |
| 24 | #45 | **Analytics**: p50/p95/p99, status mix, top hosts — pure functions first, then charts |
| 25 | #54 | Headless CLI analysis (reuses steps 23–24) |
| 26 | #51 | HAR import (reverse of export, `CaptureMode::Import`) |
| 27 | #50, #49 | Edit & resend; side-by-side diff |
| 28 | #48, #53, #52 | Alert rules; saved filters/views; shortcuts + command palette |
| 29 | #46 | **HTTPS interception** with a local CA |
| 30 | #47 | Passive capture via Npcap/libpcap ("could") |
| 31 | #56 | HTTP/2 — investigation only (stretch) |
| 32 | #55 → #57 | Profile & optimise → release v0.9 |

## Phase 5 — Evaluation, code parts (M4)

#58 coverage target → #59 fuzz parser + filter language (libFuzzer, Clang/Linux) →
#60 benchmarks → #64 security & privacy review → #65 fixes from the Software Demonstration.

## Not coding — student's own work

#13, #14 research · #15 SRS · #17–#19 architecture / ADRs / test strategy (Claude may draft
technical docs for the student to rewrite) · #61–#63 evaluation and studies · all of
Phase 6 (dissertation, video, viva). Claude does not write the portfolio, dissertation,
literature review or meeting logs.

## Decisions to make early

1. **M2 is overloaded** (#20–#32). Suggested v0.1.0 core: #20–#26, #28, #29, #31, #32;
   move #27 and #30 later if needed.
2. **New dependencies need approval when reached:** llhttp, Asio, SQLite, spdlog (planned);
   a JSON library and maybe zlib; later Qt 6, OpenSSL, Npcap.
3. **Two things can't stay fully "simple style":**
   - Qt requires some inheritance (`QMainWindow`, `QAbstractTableModel`) — keep it minimal.
   - HTTPS interception (#46) needs per-host certificate generation and TLS on both sides —
     the hardest step in the plan.
4. **Passive capture (#47)** needs its own TCP reassembly — suggest cutting it unless ahead
   of schedule.

## Coding rules (reminder)

Plain C++20 a first-year student can explain at the viva: structs, free functions,
`std::string` / `vector` / `map`, functions under ~40 lines, a "why" comment on every
non-obvious block. No templates, clever one-liners, operator overloading, inheritance
hierarchies, nested lambdas, coroutines or Asio async. Networking is blocking Asio with one
`std::thread` per connection. GoogleTest tests for all new core logic. After each issue: a
short viva explanation (what, why this design, alternatives rejected, what to study).
