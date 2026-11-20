# Software requirements specification

> Status: **template**: complete in the Phase 1 issue "Write requirements specification".

## 1. Purpose and scope

## 2. Personas

| Persona | Background | Goal | Success looks like |
| --- | --- | --- | --- |
| Beginner | e.g. student, junior web developer | See what their browser/app sends and receives | First request captured within _N_ minutes, no docs needed |
| Power user | e.g. QA engineer, backend developer, security tester | Find, filter and analyse traffic fast; automate | Common task done with keyboard/CLI only |

## 3. User stories

| ID | As a… | I want… | So that… | MoSCoW | Acceptance test |
| --- | --- | --- | --- | --- | --- |
| US-01 | beginner | | | Must | |

## 4. Functional requirements

| ID | Requirement | Priority | Source (story) | Verified by |
| --- | --- | --- | --- | --- |
| FR-01 | | Must | US-01 | test name / manual check |

## 5. Non-functional requirements

| ID | Category | Requirement (measurable) | Verified by |
| --- | --- | --- | --- |
| NFR-01 | Usability | | Usability study |
| NFR-02 | Performance | | Benchmark |
| NFR-03 | Portability | | CI matrix |
| NFR-04 | Security / privacy | | Review + tests |

## 6. Constraints

- C++20 (assigned by supervisor); builds with CMake on Windows, Linux, macOS.
- Ethics: only own or authorised traffic; user study only after ethics approval.

## 7. Out of scope
