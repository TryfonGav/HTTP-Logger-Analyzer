# Test plan

> Status: **template**: complete in the Phase 1 issue "Define the testing strategy".

| Level | Tool | What it covers | When it runs |
| --- | --- | --- | --- |
| Unit | GoogleTest | Parser, model, filter language, store queries | Every push (CI) |
| Integration | GoogleTest + local test server | Proxy → store end to end | Every push (CI) |
| Fuzz | libFuzzer (Clang) | HTTP parser robustness | Nightly / before releases |
| Performance | Google Benchmark + load script | Throughput, added latency, memory | Before panel, demo, submission |
| Usability | Task-based study + SUS questionnaire | Beginner setup, power-user workflows | Phase 5, after ethics approval |
| Acceptance | Traceability matrix (SRS) | Every Must requirement | Before submission |

## Coverage target

_e.g. ≥ 80 % line coverage of `src/core` (gcovr report)._

## Traceability

| Requirement | Test(s) | Result |
| --- | --- | --- |
| FR-01 | | |
