#!/usr/bin/env bash
# =============================================================================
# setup_github_board.sh
# Creates the labels, milestones, issues and GitHub Projects (v2) board for the
# HTTP Logger & Analyzer CCS3900 individual project.
#
# Requirements : GitHub CLI (gh) 2.40+, logged in with project scope:
#                  gh auth login
#                  gh auth refresh -s project
# Usage        : ./scripts/setup_github_board.sh OWNER/REPO
# Options (environment variables):
#   DRY_RUN=1            print what would happen, change nothing
#   TIME_BUDGET=N        stop cleanly after N seconds (re-run to continue)
#   SKIP_PROJECT=1       create labels, milestones, issues only (no board)
#   PROJECT_TITLE="..."  board name (default below)
#   DUE_PORTFOLIO=YYYY-MM-DD  DUE_PANEL=...  DUE_DEMO=...  DUE_SUBMISSION=...  DUE_VIVA=...
#                        milestone due dates; copy them from the VLE (handbook dates are provisional)
# Safe to re-run: labels are updated, existing milestones and issues (same title) are skipped.
# Works with the bash 3.2 that ships with macOS.
# =============================================================================
set -euo pipefail

REPO="${1:-${REPO:-}}"
PROJECT_TITLE="${PROJECT_TITLE:-HTTP Logger & Analyzer (CCS3900)}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_PROJECT="${SKIP_PROJECT:-0}"

DUE_PORTFOLIO="${DUE_PORTFOLIO:-}"
DUE_PANEL="${DUE_PANEL:-}"
DUE_DEMO="${DUE_DEMO:-}"
DUE_SUBMISSION="${DUE_SUBMISSION:-}"
DUE_VIVA="${DUE_VIVA:-}"

# Milestone titles (handbook section 2.2)
M1="M1 Portfolio (Fall W6)"
M2="M2 Progress Review Panel (Fall W15)"
M3="M3 Software Demonstration (Spring W8)"
M4="M4 Dissertation Submission (Spring W11)"
M5="M5 Viva (Spring W15)"

# Phase names (project-board single-select field; no commas allowed)
P0="P0 Project management"
P1="P1 Foundation"
P2="P2 Core logging"
P3="P3 Beginner UI"
P4="P4 Advanced features"
P5="P5 Testing & evaluation"
P6="P6 Dissertation & viva"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
dry()  { [ "$DRY_RUN" = "1" ]; }
# has_line HAYSTACK NEEDLE: exact whole-line match (here-string, so no SIGPIPE under pipefail)
has_line() { grep -Fxq -- "$2" <<<"$1"; }

[ -n "$REPO" ] || die "usage: $0 OWNER/REPO   e.g. $0 TryfonGav/HTTP-Logger-Analyzer"
# Accept a pasted URL too: https://github.com/OWNER/REPO(.git), git@github.com:OWNER/REPO.git
REPO="${REPO#https://}"; REPO="${REPO#http://}"; REPO="${REPO#git@}"
REPO="${REPO#github.com/}"; REPO="${REPO#github.com:}"; REPO="${REPO#www.github.com/}"
REPO="${REPO%/}"; REPO="${REPO%.git}"
case "$REPO" in */*/*|/*|*/) die "repository must look like OWNER/REPO, got '$REPO'";; */*) ;; *) die "repository must look like OWNER/REPO, got '$REPO'";; esac
OWNER="${REPO%%/*}"

if ! dry; then
  command -v gh >/dev/null 2>&1 || die "GitHub CLI not found. Install it from https://cli.github.com, open a NEW terminal, then run: gh auth login"
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is not logged in. Run: gh auth login   (choose GitHub.com, HTTPS, login with a web browser)"
  gh repo view "$REPO" >/dev/null 2>&1 || die "cannot access https://github.com/$REPO with the account shown by 'gh auth status'. Check the spelling and that you are logged in as $OWNER."
  [ "$(gh api "repos/$REPO" --jq '.has_issues')" = "true" ] \
    || die "Issues are turned off for $REPO. Enable them: repo Settings -> General -> Features -> Issues."
  if [ "$SKIP_PROJECT" != "1" ] && ! gh project --help >/dev/null 2>&1; then
    warn "this gh version has no 'project' command (needs 2.31+); issues will be created without the board. Update gh to get the board."
    SKIP_PROJECT=1
  fi
fi

CREATED=0
SKIPPED=0
FAILED=0
STOPPED=0   # issues not attempted because TIME_BUDGET (seconds) ran out
EXISTING_TITLES=""
PROJECT_NUMBER=""
PROJECT_ID=""
PHASE_FIELD_ID=""
PHASE_OPTIONS=""   # lines of "name<TAB>id"

# -----------------------------------------------------------------------------
# Labels
# -----------------------------------------------------------------------------
label() { # name color description
  if dry; then echo "  label  $1"; return; fi
  gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
}

create_labels() {
  log "Labels"
  label "phase:0-management"     "BFD4F2" "Supervision, meeting logs, AI journal, admin"
  label "phase:1-foundation"     "C5DEF5" "Repo, build, CI, requirements, architecture"
  label "phase:2-core-logging"   "1D76DB" "Capture, parsing, storage, CLI"
  label "phase:3-beginner-ui"    "0E8A16" "Qt GUI and onboarding for newcomers"
  label "phase:4-advanced"       "5319E7" "Power-user and analysis features"
  label "phase:5-evaluation"     "FBCA04" "Testing, benchmarks, usability study"
  label "phase:6-dissertation"   "D93F0B" "Write-up, demo, submission, viva"

  label "type:feature"  "A2EEEF" "New functionality"
  label "type:research" "D4C5F9" "Reading, tool comparison, investigation"
  label "type:design"   "F9D0C4" "Analysis, specification or design artefact"
  label "type:docs"     "0075CA" "Documentation or dissertation writing"
  label "type:test"     "BFDADC" "Tests, benchmarks, evaluation"
  label "type:infra"    "EDEDED" "Build, CI, tooling"
  label "type:admin"    "E4E669" "Handbook process: meetings, submissions"
  label "type:bug"      "D73A4A" "Something is broken"

  label "area:capture"  "C2E0C6" "Proxy, pcap, HAR import"
  label "area:parser"   "C2E0C6" "HTTP parsing and reassembly"
  label "area:storage"  "C2E0C6" "SQLite session store"
  label "area:analyzer" "C2E0C6" "Stats, filters, rules"
  label "area:gui"      "C2E0C6" "Qt desktop app"
  label "area:cli"      "C2E0C6" "httplog command-line tool"
  label "area:build"    "C2E0C6" "CMake, vcpkg, CI"

  label "priority:must"   "B60205" "MoSCoW: Must have"
  label "priority:should" "FF9F1C" "MoSCoW: Should have"
  label "priority:could"  "C5DEF5" "MoSCoW: Could have (stretch)"

  label "handbook-deliverable" "000000" "Required or assessed by the CCS3900 handbook"
  label "ai-assisted"          "FEF2C0" "AI tool used; entry in docs/ai-journal/AI_JOURNAL.md"
  label "ethics"               "FFFFFF" "Personal data, consent or ethics approval involved"
}

# -----------------------------------------------------------------------------
# Milestones
# -----------------------------------------------------------------------------
milestone() { # title due(YYYY-MM-DD or empty) description
  local title="$1" due="$2" desc="$3"
  if dry; then echo "  milestone  $title ${due:+(due $due)}"; return; fi
  local existing
  existing="$(gh api "repos/$REPO/milestones?state=all&per_page=100" --jq '.[].title')"
  if has_line "$existing" "$title"; then
    echo "  exists     $title"; return
  fi
  if [ -n "$due" ]; then
    gh api -X POST "repos/$REPO/milestones" -f title="$title" -f description="$desc" \
      -f due_on="${due}T23:59:59Z" >/dev/null
  else
    gh api -X POST "repos/$REPO/milestones" -f title="$title" -f description="$desc" >/dev/null
  fi
  echo "  created    $title"
}

create_milestones() {
  log "Milestones"
  milestone "$M1" "$DUE_PORTFOLIO"  "Handbook 2.2.1: project portfolio to supervisor (10%)."
  milestone "$M2" "$DUE_PANEL"      "Handbook 2.2.2: 15-minute progress review panel (10%). Core logging working; detailed plan to submission."
  milestone "$M3" "$DUE_DEMO"       "Handbook 2.2.3: software demonstration to academic staff. Product nearing completion."
  milestone "$M4" "$DUE_SUBMISSION" "Handbook 2.2.4: dissertation, source code, 6-minute video, TurnItIn (60% with viva)."
  milestone "$M5" "$DUE_VIVA"       "Handbook 2.2.5: viva (oral examination), physical presence required."
}

# -----------------------------------------------------------------------------
# Project board (GitHub Projects v2)
# -----------------------------------------------------------------------------
setup_project() {
  [ "$SKIP_PROJECT" = "1" ] && { log "Project board skipped (SKIP_PROJECT=1)"; return; }
  log "Project board: $PROJECT_TITLE"
  if dry; then
    echo "  project    $PROJECT_TITLE (fields: Phase, Estimate (h), Start date, Target date)"
    return
  fi

  local list
  if ! list="$(gh project list --owner "$OWNER" --limit 100 --format json \
        --jq ".projects[] | select(.title == \"$PROJECT_TITLE\") | .number" 2>&1)"; then
    warn "cannot use GitHub Projects: $list"
    warn "fix: run 'gh auth refresh -s project', then re-run this script (existing issues are skipped)."
    warn "continuing WITHOUT the board: labels, milestones and issues will still be created."
    PROJECT_NUMBER=""; return 0
  fi
  PROJECT_NUMBER="$(head -n1 <<<"$list")"
  if [ -z "$PROJECT_NUMBER" ]; then
    if ! PROJECT_NUMBER="$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json --jq '.number' 2>&1)"; then
      warn "could not create the board: $PROJECT_NUMBER"
      warn "fix: run 'gh auth refresh -s project', then re-run. Continuing without the board."
      PROJECT_NUMBER=""; return 0
    fi
    echo "  created    project #$PROJECT_NUMBER"
  else
    echo "  exists     project #$PROJECT_NUMBER"
  fi
  PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json --jq '.id')"
  gh project link "$PROJECT_NUMBER" --owner "$OWNER" --repo "$REPO" >/dev/null 2>&1 || true

  local fields
  fields="$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json --jq '.fields[].name')"
  if ! has_line "$fields" "Phase"; then
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Phase" --data-type SINGLE_SELECT \
      --single-select-options "$P0,$P1,$P2,$P3,$P4,$P5,$P6" >/dev/null
    echo "  created    field Phase"
  fi
  if ! has_line "$fields" "Estimate (h)"; then
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Estimate (h)" --data-type NUMBER >/dev/null
    echo "  created    field Estimate (h)"
  fi
  local f
  for f in "Start date" "Target date"; do
    if ! has_line "$fields" "$f"; then
      gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "$f" --data-type DATE >/dev/null
      echo "  created    field $f"
    fi
  done

  PHASE_FIELD_ID="$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json \
    --jq '.fields[] | select(.name == "Phase") | .id')"
  PHASE_OPTIONS="$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json \
    --jq '.fields[] | select(.name == "Phase") | .options[] | "\(.name)\t\(.id)"')"
}

phase_option_id() { awk -F '\t' -v n="$1" '$1 == n { print $2 }' <<<"$PHASE_OPTIONS"; }

# -----------------------------------------------------------------------------
# Issues
# -----------------------------------------------------------------------------
load_existing_titles() {
  dry && return
  EXISTING_TITLES="$(gh issue list --repo "$REPO" --state all --limit 1000 --json title --jq '.[].title')"
}

# issue "Title" "Milestone" "Phase" "label1,label2"  <<'EOF' ...body... EOF
issue() {
  local title="$1" ms="$2" phase="$3" labels="$4" body url item opt
  body="$(cat)"
  if [ -n "${TIME_BUDGET:-}" ] && [ "$SECONDS" -ge "$TIME_BUDGET" ]; then
    STOPPED=$((STOPPED + 1)); return
  fi
  if has_line "$EXISTING_TITLES" "$title"; then
    echo "  skip       $title"; SKIPPED=$((SKIPPED + 1)); return
  fi
  if dry; then
    echo "  issue      [$phase] $title"; CREATED=$((CREATED + 1)); return
  fi

  if ! url="$(gh issue create --repo "$REPO" --title "$title" \
          --label "$labels" --milestone "$ms" --body-file - <<<"$body" 2>&1)"; then
    warn "FAILED: $title"
    warn "  gh said: $url"
    FAILED=$((FAILED + 1)); return 0
  fi
  url="$(tail -n1 <<<"$url")"
  echo "  created    $title"
  CREATED=$((CREATED + 1))

  if [ -n "$PROJECT_NUMBER" ]; then
    item="$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$url" --format json --jq '.id' 2>/dev/null || true)"
    opt="$(phase_option_id "$phase")"
    if [ -n "$item" ] && [ -n "$opt" ] && [ -n "$PHASE_FIELD_ID" ]; then
      gh project item-edit --id "$item" --project-id "$PROJECT_ID" \
        --field-id "$PHASE_FIELD_ID" --single-select-option-id "$opt" >/dev/null 2>&1 \
        || warn "could not set Phase for: $title"
    else
      warn "could not add to the board: $title"
    fi
  fi
  sleep 1   # stay under GitHub's secondary rate limit for content creation
}

# =============================================================================
# PHASE 0 - Project management & handbook compliance
# =============================================================================
phase0() {
log "Phase 0: Project management & handbook compliance"

issue "Submit the project portfolio" "$M1" "$P0" "phase:0-management,type:admin,handbook-deliverable,priority:must" <<'EOF'
Complete the department's **Individual Project Portfolio** template and send it to the supervisor (handbook 2.2.1; assessed 10%, criteria in 3.2).

## Acceptance criteria
- [ ] Title page: dissertation title, name, date
- [ ] Abstract
- [ ] Short description of the project (200-300 words)
- [ ] Rationale / motivation: who benefits, why it is interesting (200-300 words)
- [ ] Aim, clearly and briefly stated (50 words maximum)
- [ ] Background issues involved (~150 words)
- [ ] How the project fits the Computer Science track (150 words maximum; handbook 1.4)
- [ ] Other things the supervisor requested:
  - [ ] Plan of action for the rest of the semester with a GANTT chart (export the board's Roadmap view)
  - [ ] A past dissertation assessment
- [ ] Viability discussed with the supervisor after submission

_Assessed on: clarity of rationale/aim, coherence of objectives, relevant areas for investigation, realism of the plan, past dissertation assessment._
EOF

issue "Give the supervisor access to the repo and a shared Drive folder" "$M1" "$P0" "phase:0-management,type:admin,priority:must" <<'EOF'
Handbook 1.7: store work in a shared cloud folder and use a Git service for source code. You are solely responsible for not losing your work.

## Acceptance criteria
- [ ] Supervisor added as a collaborator (read access) on this repository
- [ ] Shared Google Drive folder created for portfolio, dissertation drafts, meeting notes
- [ ] Folder link recorded in the README (private section) or the meeting log
EOF

issue "Schedule recurring bi-weekly supervisor meetings" "$M1" "$P0" "phase:0-management,type:admin,handbook-deliverable,priority:must" <<'EOF'
Handbook 1.6: students arrange bi-weekly meetings as recurring events, not ad hoc.

## Acceptance criteria
- [ ] Recurring calendar series agreed with the supervisor for the teaching weeks of both semesters
- [ ] The three formal supervision meetings (after the portfolio, before the demo, before submission) are on the calendar once the supervisor sets them
EOF

issue "Keep meeting logs after every supervisor meeting" "$M5" "$P0" "phase:0-management,type:admin,handbook-deliverable,priority:must" <<'EOF'
Meeting logs are **20%** of the module (handbook 3.1). A minimum of **5 logged meetings** is required for the component to be marked.

## Acceptance criteria
- [ ] Official Google Form (VLE link) submitted the same day as every meeting
- [ ] Mirror note added in `project/meetings/YYYY-MM-DD.md` using the template
- [ ] Every action from a meeting is an issue or a comment on an existing issue
- [ ] At least 5 logged meetings by submission (tick as you go): 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 [ ]

_Assessed on: engagement and regularity, progress against the plan, reflective quality of entries, ownership and initiative._
EOF

issue "Confirm the AI-use agreement in writing and start the AI journal" "$M1" "$P0" "phase:0-management,type:admin,handbook-deliverable,priority:must,ai-assisted" <<'EOF'
The printed handbook (1.9) prohibits generative AI and requires a signed declaration. The supervisor allows AI use if an AI journal is kept, so the permission must be documented.

## Acceptance criteria
- [ ] Written confirmation (email) of the AI-use agreement saved in the shared Drive folder
- [ ] Asked the supervisor how the submission declaration should read given the agreement
- [ ] `docs/ai-journal/AI_JOURNAL.md` reviewed; first entry (repository planning) completed
- [ ] PR template AI checkbox used on every PR from now on
EOF

issue "Check ethics requirements for traffic capture and the user study" "$M2" "$P0" "phase:0-management,type:admin,ethics,priority:must" <<'EOF'
Handbook 1.8: research involving human participants or personal data needs ethics approval; BCS Code of Conduct applies.

## Acceptance criteria
- [ ] Discussed with the supervisor: capture limited to own devices / test environments; no third-party traffic
- [ ] Attended the ethics training session
- [ ] Ethics application for the Phase 5 usability study submitted (consent form, information sheet, anonymised data handling)
- [ ] Approval received **before** recruiting any participant
EOF

issue "Maintain the project plan and GANTT chart" "$M2" "$P0" "phase:0-management,type:admin,priority:should" <<'EOF'
The plan is assessed in the portfolio (realism) and the progress panel (progress against the plan).

## Acceptance criteria
- [ ] Every open issue has a milestone, Phase and Estimate (h)
- [ ] Roadmap view configured on the board (grouped by Phase, by milestone)
- [ ] Plan re-baselined after each formal meeting; slips noted in the meeting log
- [ ] Total estimate checked against the 400-hour workload (handbook 1.5, at least 15 h per week)
EOF

issue "Prepare the Progress Review Panel presentation" "$M2" "$P0" "phase:0-management,type:admin,handbook-deliverable,priority:must" <<'EOF'
Handbook 2.2.2 / 3.3: ~15-minute panel with 2-3 staff members (10%).

## Acceptance criteria
- [ ] Slides: project, progress against the portfolio plan, honest self-evaluation
- [ ] Detailed plan up to the dissertation submission date
- [ ] Short live demo of capture -> store -> list (Phase 2 build)
- [ ] Rehearsed to 15 minutes; likely questions listed with answers

_Assessed on: progress against the plan, quality of work to date, clarity and self-awareness of remaining work._
EOF
}

# =============================================================================
# PHASE 1 - Foundation
# =============================================================================
phase1() {
log "Phase 1: Foundation"

issue "Initialise the repository from the starter scaffold" "$M2" "$P1" "phase:1-foundation,type:infra,area:build,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Scaffold committed to `main`; README owner/repo badge URL updated
- [ ] Branch protection on `main`: pull request required, CI must pass
- [ ] Licence decided with the supervisor (consider Qt's GPL/LGPL terms) and added
- [ ] Repository description and topics set
EOF

issue "Configure the CMake build with presets and vcpkg" "$M2" "$P1" "phase:1-foundation,type:infra,area:build,priority:must" <<'EOF'
## Acceptance criteria
- [ ] `cmake --preset dev && cmake --build --preset dev && ctest --preset dev` succeeds on your machine
- [ ] vcpkg manifest installs all Phase 2 dependencies (asio, llhttp, sqlite3[fts5], nlohmann-json, cli11, spdlog, zlib, brotli, gtest)
- [ ] `builtin-baseline` pinned in `vcpkg.json` for reproducible versions
- [ ] Build instructions in README verified from a clean clone
EOF

issue "Set up continuous integration with GitHub Actions" "$M2" "$P1" "phase:1-foundation,type:infra,area:build,priority:must" <<'EOF'
## Acceptance criteria
- [ ] CI builds and tests on Linux GCC, Linux Clang + ASan/UBSan and Windows MSVC
- [ ] vcpkg binary cache keeps a warm build under ~10 minutes
- [ ] clang-format check job passes
- [ ] CI badge in README is green
EOF

issue "Add code-quality tooling (clang-format, clang-tidy, coverage)" "$M2" "$P1" "phase:1-foundation,type:infra,area:build,priority:should" <<'EOF'
## Acceptance criteria
- [ ] clang-format and clang-tidy run locally (IDE or pre-commit hook)
- [ ] Coverage build (gcovr) produces an HTML report as a CI artifact
- [ ] Coding conventions summarised in `docs/architecture/ARCHITECTURE.md` or a CONTRIBUTING note
EOF

issue "Review existing HTTP logging and analysis tools" "$M2" "$P1" "phase:1-foundation,type:research,priority:must" <<'EOF'
Feeds dissertation Chapter 2 (literature review, 10%) and the evaluation comparison.

## Acceptance criteria
- [ ] At least 6 tools compared, e.g. Wireshark, Fiddler, mitmproxy, Charles, HTTP Toolkit, browser DevTools
- [ ] Comparison table: setup effort, beginner friendliness, power features, platforms, licence, HTTPS handling
- [ ] Gap identified that this project addresses (beginner-friendly *and* powerful)
- [ ] Sources recorded in IEEE style (handbook Appendix A)
EOF

issue "Review background theory: HTTP, proxies, TLS, packet capture" "$M2" "$P1" "phase:1-foundation,type:research,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Notes on HTTP/1.1 message format (RFC 9110/9112), chunked encoding, keep-alive
- [ ] Notes on forward proxies, CONNECT tunnelling, TLS interception and its ethics
- [ ] Notes on libpcap capture and TCP stream reassembly
- [ ] Usability principles relevant to beginner tooling (e.g. Nielsen heuristics, SUS)
- [ ] All sources in IEEE style, ready for Chapter 2
EOF

issue "Write the requirements specification" "$M2" "$P1" "phase:1-foundation,type:design,priority:must" <<'EOF'
Complete `docs/requirements/SRS.md`.

## Acceptance criteria
- [ ] Two personas: beginner and power user
- [ ] User stories with MoSCoW priority and acceptance tests
- [ ] Functional requirements traced to stories
- [ ] Measurable non-functional requirements (setup time, throughput, added latency, max session size, platforms)
- [ ] Reviewed with the supervisor
EOF

issue "Design the HTTP transaction data model" "$M2" "$P1" "phase:1-foundation,type:design,area:parser,priority:must" <<'EOF'
## Acceptance criteria
- [ ] `HttpTransaction`, `Headers`, `Timings` types in `src/core/include/httplogger/`
- [ ] Covers request, response, sizes, timings, connection info, capture mode, errors
- [ ] Unit tests for construction and invariants
- [ ] Documented in ARCHITECTURE.md section 5
EOF

issue "Write the architecture document" "$M2" "$P1" "phase:1-foundation,type:design,priority:must" <<'EOF'
## Acceptance criteria
- [ ] `docs/architecture/ARCHITECTURE.md` complete: context, components, request sequence, data model, threading, storage, security
- [ ] Quality-attribute targets copied from the SRS
- [ ] Diagrams render on GitHub (Mermaid)
- [ ] Reviewed with the supervisor
EOF

issue "Record key design decisions as ADRs" "$M2" "$P1" "phase:1-foundation,type:design,type:docs,priority:must" <<'EOF'
ADRs let you justify every choice at the viva (handbook 3.5).

## Acceptance criteria
- [ ] ADR-0001 C++20 + CMake + vcpkg (decision filled in)
- [ ] ADR-0002 proxy capture first, passive capture later
- [ ] ADR-0003 SQLite as the session store
- [ ] ADR-0004 Qt 6 Widgets for the GUI (vs Dear ImGui, web UI)
- [ ] ADR-0005 threading model
EOF

issue "Define the testing strategy" "$M2" "$P1" "phase:1-foundation,type:design,type:test,priority:must" <<'EOF'
## Acceptance criteria
- [ ] `docs/testing/TEST_PLAN.md` covers unit, integration, fuzz, performance, usability, acceptance
- [ ] Coverage target agreed
- [ ] Traceability matrix started from the SRS
EOF
}

# =============================================================================
# PHASE 2 - Core logging
# =============================================================================
phase2() {
log "Phase 2: Core logging"

issue "Implement the HTTP/1.1 parser on llhttp" "$M2" "$P2" "phase:2-core-logging,type:feature,area:parser,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Parses requests and responses incl. chunked bodies, keep-alive and pipelined messages
- [ ] Malformed input returns an error, never crashes
- [ ] Unit tests use fixtures in `tests/fixtures/`
EOF

issue "Implement the HTTP forward proxy with Asio" "$M2" "$P2" "phase:2-core-logging,type:feature,area:capture,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Listens on `127.0.0.1:<port>` (default 8080, configurable)
- [ ] Forwards all methods and streams bodies without buffering whole responses
- [ ] Handles concurrent connections and keep-alive
- [ ] Upstream errors (DNS, refused, timeout) are logged as failed transactions
- [ ] Integration test: client -> proxy -> local test server
EOF

issue "Support HTTPS CONNECT tunnelling without decryption" "$M2" "$P2" "phase:2-core-logging,type:feature,area:capture,priority:must" <<'EOF'
## Acceptance criteria
- [ ] CONNECT requests are tunnelled transparently
- [ ] Each tunnel is logged with host, port, bytes in/out and duration
- [ ] Browsing HTTPS sites through the proxy works normally
EOF

issue "Record timing metrics for each transaction" "$M2" "$P2" "phase:2-core-logging,type:feature,area:capture,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Start, DNS, connect, time to first byte and total recorded per transaction
- [ ] Monotonic clock used; values tested against a server with known delays
EOF

issue "Build the thread-safe capture pipeline" "$M2" "$P2" "phase:2-core-logging,type:feature,area:capture,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Producer/consumer queue between network threads and the store writer
- [ ] No lost transactions under a load test; back-pressure behaviour documented
- [ ] Clean shutdown flushes pending transactions
- [ ] Passes under ThreadSanitizer or ASan in CI
EOF

issue "Implement the SQLite session store" "$M2" "$P2" "phase:2-core-logging,type:feature,area:storage,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Schema with versioned migrations; WAL mode
- [ ] Batched inserts; indexes on time, host, status, method
- [ ] Bodies stored up to a configurable size cap
- [ ] One `.httplog` file per session; reopening restores it
- [ ] Unit tests on a temporary database
EOF

issue "Implement the query API for stored transactions" "$M2" "$P2" "phase:2-core-logging,type:feature,area:storage,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Filter by method, status/status class, host, path substring, time range
- [ ] Paged results with stable ordering
- [ ] Full-text search over URLs and text bodies (FTS5)
- [ ] Tests for each filter and their combinations
EOF

issue "Decode compressed bodies and detect content types" "$M2" "$P2" "phase:2-core-logging,type:feature,area:parser,priority:should" <<'EOF'
## Acceptance criteria
- [ ] gzip, deflate and br decoded for display; raw bytes kept
- [ ] Content type detected from headers, falling back to sniffing
- [ ] Decompression bomb protection (size limit)
EOF

issue "Export sessions to HAR 1.2, JSON and CSV" "$M2" "$P2" "phase:2-core-logging,type:feature,area:storage,priority:must" <<'EOF'
## Acceptance criteria
- [ ] HAR output validates against the HAR 1.2 spec and opens in Chrome/Firefox DevTools
- [ ] JSON and CSV exports of the current filter result
- [ ] Round-trip test: export -> parse -> compare
EOF

issue "Build CLI v1: capture, list and export" "$M2" "$P2" "phase:2-core-logging,type:feature,area:cli,priority:must" <<'EOF'
## Acceptance criteria
- [ ] `httplog capture --port N [--out file]` with live one-line-per-request output
- [ ] `httplog list <session> [--filter ...]` and `httplog export <session> --format har|json|csv`
- [ ] `--help` for every subcommand; meaningful exit codes
- [ ] CLI tests for argument handling
EOF

issue "Add a configuration file with zero-config defaults" "$M2" "$P2" "phase:2-core-logging,type:feature,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Works with no config file at all (beginner path)
- [ ] JSON config in the user's config directory: port, body size cap, storage folder, ignored hosts
- [ ] Invalid config produces a clear message naming the bad key
EOF

issue "Write the end-to-end integration test suite" "$M2" "$P2" "phase:2-core-logging,type:test,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Local test server (cpp-httplib) started by the tests
- [ ] Scenarios: GET, POST with body, chunked response, redirect, 404/500, upstream down, CONNECT
- [ ] Runs in CI on all platforms
EOF

issue "Release v0.1.0 for the Progress Review Panel" "$M2" "$P2" "phase:2-core-logging,type:infra,handbook-deliverable,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Tag `v0.1.0`; release notes list completed issues
- [ ] Demo script for the panel: start capture, browse, list, export HAR
EOF
}

# =============================================================================
# PHASE 3 - Beginner UI
# =============================================================================
phase3() {
log "Phase 3: Beginner UI"

issue "Create the Qt 6 application shell" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Main window with menu, toolbar and status bar; links `httplogger::core`
- [ ] GUI build enabled in CI on at least one platform
- [ ] Capture runs off the GUI thread; live events arrive via queued signals
EOF

issue "Build the first-run setup wizard" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Wizard chooses a free port, explains browser/system proxy setup per OS with screenshots
- [ ] "Test connection" step confirms the first request was captured
- [ ] Can be re-opened from the Help menu
- [ ] Target: a new user captures their first request within the time set in the SRS (measured in Phase 5)
EOF

issue "Add one-click start/stop capture with a status indicator" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Single Start/Stop button with keyboard shortcut
- [ ] Status bar shows state, port and request count
- [ ] Port-in-use and permission errors explained in plain language with a fix
EOF

issue "Build the live request table" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] `QAbstractTableModel` over the store: method, status, host, path, size, duration, time
- [ ] Status colour-coded by class (2xx/3xx/4xx/5xx) with a text label as well (not colour alone)
- [ ] Auto-scroll that pauses when the user scrolls up
- [ ] Remains responsive at the session size set in the SRS
EOF

issue "Build the request detail panel" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Tabs: Overview, Request headers, Response headers, Body, Timing
- [ ] Body viewer pretty-prints JSON/XML/HTML and previews images
- [ ] Timing tab shows a waterfall of DNS/connect/TTFB/download
- [ ] Copy as cURL
EOF

issue "Add simple search and quick filters" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Search box over URL and host
- [ ] One-click filters: Errors (4xx/5xx), Slow requests, by method, by domain
- [ ] Clear-all-filters control; active filters always visible
EOF

issue "Add plain-language explanations and a glossary" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Tooltips explain status codes and common headers in one sentence each
- [ ] In-app glossary (proxy, header, status code, latency, HTTPS, ...)
- [ ] Explanations can be turned off by power users
EOF

issue "Design empty, loading and error states" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Empty session shows the next step (start capture / run wizard)
- [ ] No-results filter state offers to clear filters
- [ ] Every error message says what happened and how to fix it
EOF

issue "Save and open capture sessions" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Save / Save As / Open for `.httplog` files; recent-files menu
- [ ] Unsaved-session prompt on exit
- [ ] Export menu reuses the core HAR/JSON/CSV exporters
EOF

issue "Make the GUI accessible and keyboard-friendly" "$M3" "$P3" "phase:3-beginner-ui,type:feature,area:gui,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Logical tab order and visible focus everywhere
- [ ] Light and dark themes; respects the OS font size
- [ ] Screen-reader names on controls (Qt accessibility)
EOF

issue "Write the beginner quick-start guide" "$M3" "$P3" "phase:3-beginner-ui,type:docs,priority:should" <<'EOF'
## Acceptance criteria
- [ ] `docs/user-guide/quick-start.md` with screenshots: install, wizard, first capture, find an error, export
- [ ] Linked from the app's Help menu and the README
EOF
}

# =============================================================================
# PHASE 4 - Advanced features
# =============================================================================
phase4() {
log "Phase 4: Advanced features"

issue "Implement the filter query language" "$M3" "$P4" "phase:4-advanced,type:feature,area:analyzer,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Grammar documented, e.g. `status:>=400 host:*.example.com method:POST time:>500ms body:"token"`
- [ ] Supports AND/OR/NOT and parentheses
- [ ] Parser with clear error positions; compiled to SQL against the store
- [ ] Shared by GUI (advanced filter bar with autocomplete) and CLI
- [ ] Unit tests, including fuzzed inputs
EOF

issue "Build the analytics dashboard" "$M3" "$P4" "phase:4-advanced,type:feature,area:analyzer,area:gui,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Requests over time, status-class mix, top hosts, latency p50/p95/p99
- [ ] Charts follow the active filter
- [ ] Statistics computed in core (tested) and reused by the CLI
EOF

issue "Add opt-in HTTPS interception with a local CA" "$M3" "$P4" "phase:4-advanced,type:feature,area:capture,ethics,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Off by default; enabling shows a clear warning and explanation
- [ ] Generates a local CA (OpenSSL 3); private key stored with user-only permissions
- [ ] Per-host certificates generated and cached
- [ ] Guided CA install/uninstall instructions per OS
- [ ] Per-host exclusion list (e.g. banking, certificate-pinned apps)
- [ ] Decrypted traffic clearly marked in the UI
EOF

issue "Add passive capture mode with libpcap or Npcap" "$M3" "$P4" "phase:4-advanced,type:feature,area:capture,priority:could" <<'EOF'
## Acceptance criteria
- [ ] Interface selection; BPF filter for configured ports
- [ ] TCP stream reassembly feeding the existing HTTP parser
- [ ] Privilege requirements documented per OS
- [ ] Tested against recorded pcap fixtures
EOF

issue "Build the alert rule engine" "$M3" "$P4" "phase:4-advanced,type:feature,area:analyzer,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Rules written in the filter language plus thresholds (e.g. 5xx rate > N/min, latency > X ms)
- [ ] Matching transactions highlighted; desktop notification optional
- [ ] Rules saved in config; unit tests for evaluation
EOF

issue "Compare two transactions side by side" "$M3" "$P4" "phase:4-advanced,type:feature,area:gui,priority:could" <<'EOF'
## Acceptance criteria
- [ ] Select two rows -> diff of headers and bodies with changes highlighted
EOF

issue "Edit and resend a request" "$M3" "$P4" "phase:4-advanced,type:feature,area:capture,area:gui,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Open any request in an editor (method, URL, headers, body) and resend it
- [ ] Response captured as a new transaction linked to the original
EOF

issue "Import HAR files for analysis" "$M3" "$P4" "phase:4-advanced,type:feature,area:capture,priority:should" <<'EOF'
## Acceptance criteria
- [ ] HAR files exported from browser DevTools open as a session
- [ ] Unsupported fields reported, not silently dropped
EOF

issue "Add keyboard shortcuts and a command palette" "$M3" "$P4" "phase:4-advanced,type:feature,area:gui,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Shortcuts for capture, search, filter, next/previous error, export
- [ ] Command palette (Ctrl/Cmd+K) lists every action
- [ ] Shortcut reference in the user guide
EOF

issue "Save filters, views and presets" "$M3" "$P4" "phase:4-advanced,type:feature,area:gui,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Save and name filter queries and column layouts
- [ ] Built-in presets for beginners (e.g. "Only errors", "API calls", "Slow pages")
EOF

issue "Add headless analysis to the CLI" "$M3" "$P4" "phase:4-advanced,type:feature,area:cli,priority:should" <<'EOF'
## Acceptance criteria
- [ ] `httplog analyze <session> [--filter ...]` prints the same statistics as the dashboard
- [ ] `--json` output on every read command for scripting
- [ ] Reads/writes stdin/stdout where it makes sense (pipe-friendly)
EOF

issue "Profile and optimise performance" "$M3" "$P4" "phase:4-advanced,type:test,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Profiled under load (perf / VTune / Instruments); hotspots recorded
- [ ] Non-functional targets from the SRS met, or the gap explained
- [ ] Before/after numbers committed to `docs/evaluation/`
EOF

issue "Investigate HTTP/2 support (stretch)" "$M3" "$P4" "phase:4-advanced,type:research,area:parser,priority:could" <<'EOF'
## Acceptance criteria
- [ ] Short investigation (e.g. nghttp2) with effort estimate
- [ ] ADR: implement now, or record as future work in the dissertation
EOF

issue "Release v0.9 for the Software Demonstration" "$M3" "$P4" "phase:4-advanced,type:infra,handbook-deliverable,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Tag `v0.9.0` with installable builds for your demo platform
- [ ] Core flows work end to end: wizard -> capture -> filter -> analyse -> export
EOF
}

# =============================================================================
# PHASE 5 - Testing & evaluation
# =============================================================================
phase5() {
log "Phase 5: Testing & evaluation"

issue "Reach the unit-test coverage target" "$M4" "$P5" "phase:5-evaluation,type:test,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Coverage of `src/core` meets the target in TEST_PLAN.md
- [ ] Report saved to `docs/testing/` for the testing chapter
EOF

issue "Fuzz-test the HTTP parser and filter language" "$M4" "$P5" "phase:5-evaluation,type:test,area:parser,priority:should" <<'EOF'
## Acceptance criteria
- [ ] libFuzzer targets for the parser and the filter-language parser
- [ ] At least 1 hour per target with no crashes; corpus committed
- [ ] Any crash found becomes a regression test
EOF

issue "Run performance and load benchmarks" "$M4" "$P5" "phase:5-evaluation,type:test,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Throughput (req/s), added latency (p50/p95) and memory at large session sizes measured
- [ ] Method documented (hardware, load tool, repetitions) so results are reproducible
- [ ] Results and charts in `docs/evaluation/`
EOF

issue "Compare the tool against existing tools" "$M4" "$P5" "phase:5-evaluation,type:test,type:research,priority:must" <<'EOF'
Handbook 3.4 (Evaluation): results must be related to other people's results.

## Acceptance criteria
- [ ] Same tasks/benchmarks run with 2-3 tools from the Phase 1 review
- [ ] Feature, setup-time and performance comparison table
- [ ] Strengths and weaknesses written up honestly
EOF

issue "Run the usability study with beginners and power users" "$M4" "$P5" "phase:5-evaluation,type:test,ethics,priority:must" <<'EOF'
**Blocked until ethics approval is received.**

## Acceptance criteria
- [ ] Task script for both personas (e.g. first capture; find the slowest failing API call)
- [ ] Measures: task success, time to first capture, SUS questionnaire, comments
- [ ] Signed consent from every participant; data anonymised
- [ ] Results analysed and stored in `docs/evaluation/`
EOF

issue "Complete acceptance testing against the requirements" "$M4" "$P5" "phase:5-evaluation,type:test,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Every Must requirement in the SRS has a passing test or recorded evidence
- [ ] Traceability matrix complete; unmet requirements explained
EOF

issue "Review security and privacy" "$M4" "$P5" "phase:5-evaluation,type:test,ethics,priority:should" <<'EOF'
## Acceptance criteria
- [ ] Proxy binds to localhost by default; remote access requires explicit opt-in
- [ ] CA key handling, temp files and session files reviewed
- [ ] Dependency versions checked for known vulnerabilities
EOF

issue "Fix issues raised at the Software Demonstration" "$M4" "$P5" "phase:5-evaluation,type:bug,priority:must" <<'EOF'
## Acceptance criteria
- [ ] Every piece of demo feedback recorded as an issue
- [ ] Must-fix items closed before the dissertation freeze
EOF
}

# =============================================================================
# PHASE 6 - Demo, dissertation & viva
# =============================================================================
phase6() {
log "Phase 6: Demo, dissertation & viva"

issue "Prepare and give the Software Demonstration" "$M3" "$P6" "phase:6-dissertation,type:admin,handbook-deliverable,priority:must" <<'EOF'
Handbook 2.2.3: not assessed, but feedback covers progress, oral communication and the portfolio's aim/objectives.

## Acceptance criteria
- [ ] Demo script covering beginner and power-user flows, with prepared sample traffic
- [ ] Backup recording in case of network problems
- [ ] Feedback written up as issues
EOF

issue "Agree the dissertation plan with the supervisor" "$M4" "$P6" "phase:6-dissertation,type:docs,handbook-deliverable,priority:must" <<'EOF'
Handbook 4.3: do this early, ideally at the start of the Spring semester.

## Acceptance criteria
- [ ] Chapter and section outline with 1-2 sentences per section
- [ ] Department template chosen (Word or LaTeX, handbook 4.2)
- [ ] Plan agreed in a supervisor meeting (logged)
EOF

issue "Draft Chapter 2: background and literature review" "$M4" "$P6" "phase:6-dissertation,type:docs,priority:must" <<'EOF'
Can be written first (handbook 4.3). Assessed under Literature review and use of resources (10%).

## Acceptance criteria
- [ ] Synthesis, not a list: related tools, HTTP/proxy/TLS theory, usability
- [ ] Concludes with points relevant to this project
- [ ] All sources cited in IEEE style
EOF

issue "Draft the main chapters: requirements, design, implementation, testing" "$M4" "$P6" "phase:6-dissertation,type:docs,priority:must" <<'EOF'
Assessed under Problem-solving process (15%) and Products (30%).

## Acceptance criteria
- [ ] Software process chosen and justified; evidence it was followed (board, PRs, CI history)
- [ ] Requirements, design (with diagrams), implementation (relevant snippets only) and testing chapters drafted
- [ ] Figures, tables and equations numbered by chapter (Fig. 3.1 ...)
EOF

issue "Draft the introduction, evaluation and conclusions" "$M4" "$P6" "phase:6-dissertation,type:docs,priority:must" <<'EOF'
Assessed under Problem description/aim/objectives (10%) and Evaluation (20%).

## Acceptance criteria
- [ ] Introduction states motivation, aim and objectives clearly
- [ ] Evaluation: results, objectives met or not (with reasons), strengths/weaknesses, comparison with other tools, process evaluation
- [ ] Conclusions (2-3 pages) with future work
- [ ] Abstract 150-250 words
EOF

issue "Send the full draft to the supervisor for feedback" "$M4" "$P6" "phase:6-dissertation,type:docs,handbook-deliverable,priority:must" <<'EOF'
Feedback normally takes 10-15 working days, and the same work can be submitted for feedback only once (handbook 1.6).

## Acceptance criteria
- [ ] Complete draft sent at least 3 weeks before the submission deadline
- [ ] Feedback logged and turned into issues
EOF

issue "Check formatting, references and the formatting checklist" "$M4" "$P6" "phase:6-dissertation,type:docs,handbook-deliverable,priority:must" <<'EOF'
Handbook section 4. Clarity of communication is 15%.

## Acceptance criteria
- [ ] Main body at most 10,000 words / 50 pages (excluding preamble, references, appendices)
- [ ] 12-pt Times New Roman, single spacing, 6-pt paragraph spacing, 30 mm margins
- [ ] Right-aligned chapter header and page-number footer; roman numerals in the preamble; A-1 style appendix numbering
- [ ] Preamble: title page, abstract, declaration, acknowledgements, ToC, list of figures, list of tables
- [ ] IEEE references in citation order; every source cited in the text
- [ ] Formal language, passive voice, no contractions; spell-checked and proofread
- [ ] Report Formatting Checklist (Student Corner) completed
EOF

issue "Record the 6-minute project video" "$M4" "$P6" "phase:6-dissertation,type:docs,handbook-deliverable,priority:must" <<'EOF'
Handbook 2.2.4.

## Acceptance criteria
- [ ] Part (a): 3-minute software demonstration
- [ ] Part (b): 3-minute code walkthrough (important parts and structure)
- [ ] Total no more than 6 minutes; .mp4 or .avi
EOF

issue "Submit the final dissertation package" "$M4" "$P6" "phase:6-dissertation,type:admin,handbook-deliverable,priority:must" <<'EOF'
Handbook 2.2.4. Missing the deadline is an automatic fail (3.8); extensions must be requested at least 3 weeks before (3.7.1).

## Acceptance criteria
- [ ] Two spiral-bound, double-sided printed copies to the Course Administrator
- [ ] Google Form: dissertation PDF, source files (.docx/.tex), video
- [ ] Source code submitted; repository tagged `v1.0.0`
- [ ] Dissertation uploaded to TurnItIn
- [ ] AI journal complete and declaration worded as agreed with the supervisor
EOF

issue "Prepare for the viva" "$M5" "$P6" "phase:6-dissertation,type:admin,handbook-deliverable,priority:must" <<'EOF'
Handbook 2.2.5 / 3.5: ~30 minutes, physical presence required; the outcome can raise or lower the dissertation mark.

## Acceptance criteria
- [ ] Live demo rehearsed on the machine you will bring (plus a recorded backup)
- [ ] Every key decision explained from the ADRs, with nuance beyond the written report
- [ ] Shortcuts, limitations and future improvements listed honestly
- [ ] Able to explain any part of the code and any AI-assisted part recorded in the AI journal
- [ ] Mock viva with a peer or the supervisor
EOF
}

# =============================================================================
# Main
# =============================================================================
main() {
  dry && log "DRY RUN: nothing will be changed"
  log "Repository: $REPO"
  create_labels
  create_milestones
  setup_project
  load_existing_titles
  phase0; phase1; phase2; phase3; phase4; phase5; phase6

  if dry; then
    log "Dry run finished: $CREATED issue(s) would be created."
  else
    log "Done: $CREATED issue(s) created, $SKIPPED skipped (already existed), $FAILED failed."
    [ "$FAILED" -gt 0 ] && warn "re-run the same command to retry the failed issues (created ones are skipped)."
    [ "$STOPPED" -gt 0 ] && warn "time budget reached: $STOPPED issue(s) not attempted yet. Re-run to continue."
  fi
  if [ -n "$PROJECT_NUMBER" ] && ! dry; then
    cat <<EOF

Next steps on the board (GitHub's CLI cannot create views, so do these once in the web UI):
  1. Open https://github.com/users/$OWNER/projects/$PROJECT_NUMBER  (or /orgs/$OWNER/... for an organisation)
  2. Board view: group columns by Status (Todo, In Progress, Done).
  3. Table view: group by Phase; show Milestone, Labels, Estimate (h).
  4. Roadmap view: bars from Start date -> Target date, milestones as markers;
     screenshot it as the GANTT chart for the portfolio and the panel.
  5. Workflows: enable "Item closed -> Done" and "Pull request merged -> Done".
  6. Fill in Estimate (h), Start date and Target date on every issue (your own estimates).
EOF
  fi
}

main "$@"
