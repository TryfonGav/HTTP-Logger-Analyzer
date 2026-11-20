<#
.SYNOPSIS
  Creates the labels, milestones, issues and GitHub Projects board for the
  HTTP Logger & Analyzer CCS3900 individual project. PowerShell version of
  setup_github_board.sh (same issues, same behaviour).

.DESCRIPTION
  Requirements: GitHub CLI (gh) 2.40+, logged in with project scope:
      gh auth login
      gh auth refresh -s project
  Works in Windows PowerShell 5.1 and PowerShell 7+.
  Safe to re-run: labels are updated; milestones and issues whose title
  already exists are skipped.

.EXAMPLE
  # Preview (changes nothing)
  powershell -ExecutionPolicy Bypass -File .\scripts\setup_github_board.ps1 TryfonGav/HTTP-Logger-Analyzer -DryRun

.EXAMPLE
  # Real run with milestone dates from the VLE
  powershell -ExecutionPolicy Bypass -File .\scripts\setup_github_board.ps1 TryfonGav/HTTP-Logger-Analyzer -DuePanel 2026-12-18 -DueDemo 2027-03-19
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Repo = $env:REPO,
    [switch]$DryRun,
    [switch]$SkipProject,
    [string]$ProjectTitle = 'HTTP Logger & Analyzer (CCS3900)',
    [string]$DuePortfolio = '',
    [string]$DuePanel = '',
    [string]$DueDemo = '',
    [string]$DueSubmission = '',
    [string]$DueViva = ''
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

# Milestone titles (handbook section 2.2)
$M1 = 'M1 Portfolio (Fall W6)'
$M2 = 'M2 Progress Review Panel (Fall W15)'
$M3 = 'M3 Software Demonstration (Spring W8)'
$M4 = 'M4 Dissertation Submission (Spring W11)'
$M5 = 'M5 Viva (Spring W15)'

# Phase names (project-board single-select field; no commas allowed)
$P0 = 'P0 Project management'
$P1 = 'P1 Foundation'
$P2 = 'P2 Core logging'
$P3 = 'P3 Beginner UI'
$P4 = 'P4 Advanced features'
$P5 = 'P5 Testing & evaluation'
$P6 = 'P6 Dissertation & viva'

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
function Write-Step([string]$m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Warn([string]$m) { Write-Host "warn: $m" -ForegroundColor Yellow }
function Stop-Script([string]$m) { Write-Host "error: $m" -ForegroundColor Red; exit 1 }

# Runs gh with an explicit argument array; returns Ok, Out (stdout), Err (stderr).
function Invoke-Gh([string[]]$A) {
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $out = & gh @A 2> $errFile
        $code = $LASTEXITCODE
        $err = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
    } finally {
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    }
    [pscustomobject]@{
        Ok  = ($code -eq 0)
        Out = ((@($out) | ForEach-Object { "$_" }) -join "`n").Trim()
        Err = ("$err" -replace '\s+', ' ').Trim()
    }
}

function ConvertFrom-GhJson([string]$text) {
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

# -----------------------------------------------------------------------------
# Arguments and pre-flight checks
# -----------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Repo)) {
    Stop-Script 'usage: .\scripts\setup_github_board.ps1 OWNER/REPO   e.g. TryfonGav/HTTP-Logger-Analyzer'
}
# Accept a pasted URL too: https://github.com/OWNER/REPO(.git), git@github.com:OWNER/REPO.git
$Repo = $Repo.Trim() -replace '^https?://', '' -replace '^git@', '' -replace '^(www\.)?github\.com[/:]', ''
$Repo = $Repo -replace '/+$', '' -replace '\.git$', ''
if ($Repo -notmatch '^[^/\s]+/[^/\s]+$') { Stop-Script "repository must look like OWNER/REPO, got '$Repo'" }
$Owner = $Repo.Split('/')[0]

if (-not $DryRun) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Stop-Script 'GitHub CLI not found. Run: winget install --id GitHub.cli   then CLOSE and reopen PowerShell, then: gh auth login'
    }
    if (-not (Invoke-Gh @('auth', 'status')).Ok) {
        Stop-Script 'GitHub CLI is not logged in. Run: gh auth login   (GitHub.com -> HTTPS -> Login with a web browser)'
    }
    $r = Invoke-Gh @('api', "repos/$Repo")
    if (-not $r.Ok) {
        Stop-Script "cannot access https://github.com/$Repo with the account shown by 'gh auth status'. Check the spelling and that you are logged in as $Owner. ($($r.Err))"
    }
    if (-not (ConvertFrom-GhJson $r.Out).has_issues) {
        Stop-Script "Issues are turned off for $Repo. Enable them: repo Settings -> General -> Features -> Issues."
    }
    if (-not $SkipProject -and -not (Invoke-Gh @('project', '--help')).Ok) {
        Write-Warn "this gh version has no 'project' command (needs 2.31+); issues will be created without the board. Update with: winget upgrade --id GitHub.cli"
        $SkipProject = $true
    }
}

$script:Created = 0
$script:Skipped = 0
$script:Failed = 0
$script:ExistingTitles = @()
$script:ProjectNumber = ''
$script:ProjectId = ''
$script:PhaseFieldId = ''
$script:PhaseOptions = @{}

# -----------------------------------------------------------------------------
# Labels
# -----------------------------------------------------------------------------
function Set-Label([string]$Name, [string]$Color, [string]$Description) {
    if ($DryRun) { Write-Host "  label      $Name"; return }
    $r = Invoke-Gh @('label', 'create', $Name, '--repo', $Repo, '--color', $Color, '--description', $Description, '--force')
    if (-not $r.Ok) { Write-Warn "label $Name : $($r.Err)" }
}

# -----------------------------------------------------------------------------
# Milestones
# -----------------------------------------------------------------------------
function New-Milestone([string]$Title, [string]$Due, [string]$Description) {
    if ($DryRun) {
        $suffix = ''; if ($Due) { $suffix = " (due $Due)" }
        Write-Host "  milestone  $Title$suffix"; return
    }
    $existing = Invoke-Gh @('api', "repos/$Repo/milestones?state=all&per_page=100")
    $titles = @(); if ($existing.Ok) { $titles = @((ConvertFrom-GhJson $existing.Out) | ForEach-Object { $_.title }) }
    if ($titles -contains $Title) { Write-Host "  exists     $Title"; return }
    $a = @('api', '-X', 'POST', "repos/$Repo/milestones", '-f', "title=$Title", '-f', "description=$Description")
    if ($Due) {
        if ($Due -notmatch '^\d{4}-\d{2}-\d{2}$') { Stop-Script "due date for '$Title' must be YYYY-MM-DD, got '$Due'" }
        $a += @('-f', "due_on=$($Due)T23:59:59Z")
    }
    $r = Invoke-Gh $a
    if ($r.Ok) { Write-Host "  created    $Title" } else { Stop-Script "could not create milestone '$Title': $($r.Err)" }
}

# -----------------------------------------------------------------------------
# Project board (GitHub Projects v2)
# -----------------------------------------------------------------------------
function Initialize-Project {
    if ($SkipProject) { Write-Step 'Project board skipped (-SkipProject)'; return }
    Write-Step "Project board: $ProjectTitle"
    if ($DryRun) { Write-Host "  project    $ProjectTitle (fields: Phase, Estimate (h), Start date, Target date)"; return }

    $list = Invoke-Gh @('project', 'list', '--owner', $Owner, '--limit', '100', '--format', 'json')
    if (-not $list.Ok) {
        Write-Warn "cannot use GitHub Projects: $($list.Err)"
        Write-Warn "fix: run 'gh auth refresh -s project', then re-run this script (existing issues are skipped)."
        Write-Warn 'continuing WITHOUT the board: labels, milestones and issues will still be created.'
        return
    }
    $match = @((ConvertFrom-GhJson $list.Out).projects | Where-Object { $_.title -eq $ProjectTitle }) | Select-Object -First 1
    if ($match) {
        $script:ProjectNumber = "$($match.number)"
        Write-Host "  exists     project #$script:ProjectNumber"
    } else {
        $c = Invoke-Gh @('project', 'create', '--owner', $Owner, '--title', $ProjectTitle, '--format', 'json')
        if (-not $c.Ok) {
            Write-Warn "could not create the board: $($c.Err)"
            Write-Warn "fix: run 'gh auth refresh -s project', then re-run. Continuing without the board."
            return
        }
        $script:ProjectNumber = "$((ConvertFrom-GhJson $c.Out).number)"
        Write-Host "  created    project #$script:ProjectNumber"
    }
    $script:ProjectId = (ConvertFrom-GhJson (Invoke-Gh @('project', 'view', $script:ProjectNumber, '--owner', $Owner, '--format', 'json')).Out).id
    [void](Invoke-Gh @('project', 'link', $script:ProjectNumber, '--owner', $Owner, '--repo', $Repo))

    $fieldsJson = Invoke-Gh @('project', 'field-list', $script:ProjectNumber, '--owner', $Owner, '--limit', '100', '--format', 'json')
    $names = @((ConvertFrom-GhJson $fieldsJson.Out).fields | ForEach-Object { $_.name })
    if ($names -notcontains 'Phase') {
        [void](Invoke-Gh @('project', 'field-create', $script:ProjectNumber, '--owner', $Owner, '--name', 'Phase',
                '--data-type', 'SINGLE_SELECT', '--single-select-options', (@($P0, $P1, $P2, $P3, $P4, $P5, $P6) -join ',')))
        Write-Host '  created    field Phase'
    }
    if ($names -notcontains 'Estimate (h)') {
        [void](Invoke-Gh @('project', 'field-create', $script:ProjectNumber, '--owner', $Owner, '--name', 'Estimate (h)', '--data-type', 'NUMBER'))
        Write-Host '  created    field Estimate (h)'
    }
    foreach ($f in @('Start date', 'Target date')) {
        if ($names -notcontains $f) {
            [void](Invoke-Gh @('project', 'field-create', $script:ProjectNumber, '--owner', $Owner, '--name', $f, '--data-type', 'DATE'))
            Write-Host "  created    field $f"
        }
    }

    $fields = (ConvertFrom-GhJson (Invoke-Gh @('project', 'field-list', $script:ProjectNumber, '--owner', $Owner, '--limit', '100', '--format', 'json')).Out).fields
    $phase = @($fields | Where-Object { $_.name -eq 'Phase' }) | Select-Object -First 1
    if ($phase) {
        $script:PhaseFieldId = $phase.id
        foreach ($o in @($phase.options)) { $script:PhaseOptions[$o.name] = $o.id }
    }
}

# -----------------------------------------------------------------------------
# Issues
# -----------------------------------------------------------------------------
function Get-ExistingTitles {
    if ($DryRun) { return }
    $r = Invoke-Gh @('issue', 'list', '--repo', $Repo, '--state', 'all', '--limit', '1000', '--json', 'title')
    if ($r.Ok) { $script:ExistingTitles = @((ConvertFrom-GhJson $r.Out) | ForEach-Object { $_.title }) }
}

function New-Issue([string]$Title, [string]$Milestone, [string]$Phase, [string]$Labels, [string]$Body) {
    if ($script:ExistingTitles -contains $Title) { Write-Host "  skip       $Title"; $script:Skipped++; return }
    if ($DryRun) { Write-Host "  issue      [$Phase] $Title"; $script:Created++; return }

    $bodyFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($bodyFile, ($Body -replace "`r`n", "`n"), (New-Object System.Text.UTF8Encoding $false))
        $r = Invoke-Gh @('issue', 'create', '--repo', $Repo, '--title', $Title, '--label', $Labels,
                         '--milestone', $Milestone, '--body-file', $bodyFile)
    } finally {
        Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue
    }
    if (-not $r.Ok) {
        Write-Warn "FAILED: $Title"
        Write-Warn "  gh said: $($r.Err)"
        $script:Failed++; return
    }
    $url = ($r.Out -split "`n")[-1].Trim()
    Write-Host "  created    $Title"
    $script:Created++

    if ($script:ProjectNumber) {
        $add = Invoke-Gh @('project', 'item-add', $script:ProjectNumber, '--owner', $Owner, '--url', $url, '--format', 'json')
        $itemId = $null; if ($add.Ok) { $itemId = (ConvertFrom-GhJson $add.Out).id }
        $optId = $script:PhaseOptions[$Phase]
        if ($itemId -and $optId -and $script:PhaseFieldId) {
            $e = Invoke-Gh @('project', 'item-edit', '--id', $itemId, '--project-id', $script:ProjectId,
                             '--field-id', $script:PhaseFieldId, '--single-select-option-id', $optId)
            if (-not $e.Ok) { Write-Warn "could not set Phase for: $Title" }
        } else {
            Write-Warn "could not add to the board: $Title"
        }
    }
    Start-Sleep -Seconds 1   # stay under GitHub's secondary rate limit for content creation
}

# =============================================================================
# Data
# =============================================================================
$LabelList = @(
    ,@('phase:0-management', 'BFD4F2', 'Supervision, meeting logs, AI journal, admin')
    ,@('phase:1-foundation', 'C5DEF5', 'Repo, build, CI, requirements, architecture')
    ,@('phase:2-core-logging', '1D76DB', 'Capture, parsing, storage, CLI')
    ,@('phase:3-beginner-ui', '0E8A16', 'Qt GUI and onboarding for newcomers')
    ,@('phase:4-advanced', '5319E7', 'Power-user and analysis features')
    ,@('phase:5-evaluation', 'FBCA04', 'Testing, benchmarks, usability study')
    ,@('phase:6-dissertation', 'D93F0B', 'Write-up, demo, submission, viva')
    ,@('type:feature', 'A2EEEF', 'New functionality')
    ,@('type:research', 'D4C5F9', 'Reading, tool comparison, investigation')
    ,@('type:design', 'F9D0C4', 'Analysis, specification or design artefact')
    ,@('type:docs', '0075CA', 'Documentation or dissertation writing')
    ,@('type:test', 'BFDADC', 'Tests, benchmarks, evaluation')
    ,@('type:infra', 'EDEDED', 'Build, CI, tooling')
    ,@('type:admin', 'E4E669', 'Handbook process: meetings, submissions')
    ,@('type:bug', 'D73A4A', 'Something is broken')
    ,@('area:capture', 'C2E0C6', 'Proxy, pcap, HAR import')
    ,@('area:parser', 'C2E0C6', 'HTTP parsing and reassembly')
    ,@('area:storage', 'C2E0C6', 'SQLite session store')
    ,@('area:analyzer', 'C2E0C6', 'Stats, filters, rules')
    ,@('area:gui', 'C2E0C6', 'Qt desktop app')
    ,@('area:cli', 'C2E0C6', 'httplog command-line tool')
    ,@('area:build', 'C2E0C6', 'CMake, vcpkg, CI')
    ,@('priority:must', 'B60205', 'MoSCoW: Must have')
    ,@('priority:should', 'FF9F1C', 'MoSCoW: Should have')
    ,@('priority:could', 'C5DEF5', 'MoSCoW: Could have (stretch)')
    ,@('handbook-deliverable', '000000', 'Required or assessed by the CCS3900 handbook')
    ,@('ai-assisted', 'FEF2C0', 'AI tool used; entry in docs/ai-journal/AI_JOURNAL.md')
    ,@('ethics', 'FFFFFF', 'Personal data, consent or ethics approval involved')
)

$Issues = @(
    [pscustomobject]@{ Title = 'Submit the project portfolio'; Milestone = $M1; Phase = $P0; Labels = 'phase:0-management,type:admin,handbook-deliverable,priority:must'; Body = @'
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
'@ }
    [pscustomobject]@{ Title = 'Give the supervisor access to the repo and a shared Drive folder'; Milestone = $M1; Phase = $P0; Labels = 'phase:0-management,type:admin,priority:must'; Body = @'
Handbook 1.7: store work in a shared cloud folder and use a Git service for source code. You are solely responsible for not losing your work.

## Acceptance criteria
- [ ] Supervisor added as a collaborator (read access) on this repository
- [ ] Shared Google Drive folder created for portfolio, dissertation drafts, meeting notes
- [ ] Folder link recorded in the README (private section) or the meeting log
'@ }
    [pscustomobject]@{ Title = 'Schedule recurring bi-weekly supervisor meetings'; Milestone = $M1; Phase = $P0; Labels = 'phase:0-management,type:admin,handbook-deliverable,priority:must'; Body = @'
Handbook 1.6: students arrange bi-weekly meetings as recurring events, not ad hoc.

## Acceptance criteria
- [ ] Recurring calendar series agreed with the supervisor for the teaching weeks of both semesters
- [ ] The three formal supervision meetings (after the portfolio, before the demo, before submission) are on the calendar once the supervisor sets them
'@ }
    [pscustomobject]@{ Title = 'Keep meeting logs after every supervisor meeting'; Milestone = $M5; Phase = $P0; Labels = 'phase:0-management,type:admin,handbook-deliverable,priority:must'; Body = @'
Meeting logs are **20%** of the module (handbook 3.1). A minimum of **5 logged meetings** is required for the component to be marked.

## Acceptance criteria
- [ ] Official Google Form (VLE link) submitted the same day as every meeting
- [ ] Mirror note added in `project/meetings/YYYY-MM-DD.md` using the template
- [ ] Every action from a meeting is an issue or a comment on an existing issue
- [ ] At least 5 logged meetings by submission (tick as you go): 1 [ ] 2 [ ] 3 [ ] 4 [ ] 5 [ ]

_Assessed on: engagement and regularity, progress against the plan, reflective quality of entries, ownership and initiative._
'@ }
    [pscustomobject]@{ Title = 'Confirm the AI-use agreement in writing and start the AI journal'; Milestone = $M1; Phase = $P0; Labels = 'phase:0-management,type:admin,handbook-deliverable,priority:must,ai-assisted'; Body = @'
The printed handbook (1.9) prohibits generative AI and requires a signed declaration. The supervisor allows AI use if an AI journal is kept, so the permission must be documented.

## Acceptance criteria
- [ ] Written confirmation (email) of the AI-use agreement saved in the shared Drive folder
- [ ] Asked the supervisor how the submission declaration should read given the agreement
- [ ] `docs/ai-journal/AI_JOURNAL.md` reviewed; first entry (repository planning) completed
- [ ] PR template AI checkbox used on every PR from now on
'@ }
    [pscustomobject]@{ Title = 'Check ethics requirements for traffic capture and the user study'; Milestone = $M2; Phase = $P0; Labels = 'phase:0-management,type:admin,ethics,priority:must'; Body = @'
Handbook 1.8: research involving human participants or personal data needs ethics approval; BCS Code of Conduct applies.

## Acceptance criteria
- [ ] Discussed with the supervisor: capture limited to own devices / test environments; no third-party traffic
- [ ] Attended the ethics training session
- [ ] Ethics application for the Phase 5 usability study submitted (consent form, information sheet, anonymised data handling)
- [ ] Approval received **before** recruiting any participant
'@ }
    [pscustomobject]@{ Title = 'Maintain the project plan and GANTT chart'; Milestone = $M2; Phase = $P0; Labels = 'phase:0-management,type:admin,priority:should'; Body = @'
The plan is assessed in the portfolio (realism) and the progress panel (progress against the plan).

## Acceptance criteria
- [ ] Every open issue has a milestone, Phase and Estimate (h)
- [ ] Roadmap view configured on the board (grouped by Phase, by milestone)
- [ ] Plan re-baselined after each formal meeting; slips noted in the meeting log
- [ ] Total estimate checked against the 400-hour workload (handbook 1.5, at least 15 h per week)
'@ }
    [pscustomobject]@{ Title = 'Prepare the Progress Review Panel presentation'; Milestone = $M2; Phase = $P0; Labels = 'phase:0-management,type:admin,handbook-deliverable,priority:must'; Body = @'
Handbook 2.2.2 / 3.3: ~15-minute panel with 2-3 staff members (10%).

## Acceptance criteria
- [ ] Slides: project, progress against the portfolio plan, honest self-evaluation
- [ ] Detailed plan up to the dissertation submission date
- [ ] Short live demo of capture -> store -> list (Phase 2 build)
- [ ] Rehearsed to 15 minutes; likely questions listed with answers

_Assessed on: progress against the plan, quality of work to date, clarity and self-awareness of remaining work._
'@ }
    [pscustomobject]@{ Title = 'Initialise the repository from the starter scaffold'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:infra,area:build,priority:must'; Body = @'
## Acceptance criteria
- [ ] Scaffold committed to `main`; README owner/repo badge URL updated
- [ ] Branch protection on `main`: pull request required, CI must pass
- [ ] Licence decided with the supervisor (consider Qt's GPL/LGPL terms) and added
- [ ] Repository description and topics set
'@ }
    [pscustomobject]@{ Title = 'Configure the CMake build with presets and vcpkg'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:infra,area:build,priority:must'; Body = @'
## Acceptance criteria
- [ ] `cmake --preset dev && cmake --build --preset dev && ctest --preset dev` succeeds on your machine
- [ ] vcpkg manifest installs all Phase 2 dependencies (asio, llhttp, sqlite3[fts5], nlohmann-json, cli11, spdlog, zlib, brotli, gtest)
- [ ] `builtin-baseline` pinned in `vcpkg.json` for reproducible versions
- [ ] Build instructions in README verified from a clean clone
'@ }
    [pscustomobject]@{ Title = 'Set up continuous integration with GitHub Actions'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:infra,area:build,priority:must'; Body = @'
## Acceptance criteria
- [ ] CI builds and tests on Linux GCC, Linux Clang + ASan/UBSan and Windows MSVC
- [ ] vcpkg binary cache keeps a warm build under ~10 minutes
- [ ] clang-format check job passes
- [ ] CI badge in README is green
'@ }
    [pscustomobject]@{ Title = 'Add code-quality tooling (clang-format, clang-tidy, coverage)'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:infra,area:build,priority:should'; Body = @'
## Acceptance criteria
- [ ] clang-format and clang-tidy run locally (IDE or pre-commit hook)
- [ ] Coverage build (gcovr) produces an HTML report as a CI artifact
- [ ] Coding conventions summarised in `docs/architecture/ARCHITECTURE.md` or a CONTRIBUTING note
'@ }
    [pscustomobject]@{ Title = 'Review existing HTTP logging and analysis tools'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:research,priority:must'; Body = @'
Feeds dissertation Chapter 2 (literature review, 10%) and the evaluation comparison.

## Acceptance criteria
- [ ] At least 6 tools compared, e.g. Wireshark, Fiddler, mitmproxy, Charles, HTTP Toolkit, browser DevTools
- [ ] Comparison table: setup effort, beginner friendliness, power features, platforms, licence, HTTPS handling
- [ ] Gap identified that this project addresses (beginner-friendly *and* powerful)
- [ ] Sources recorded in IEEE style (handbook Appendix A)
'@ }
    [pscustomobject]@{ Title = 'Review background theory: HTTP, proxies, TLS, packet capture'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:research,priority:must'; Body = @'
## Acceptance criteria
- [ ] Notes on HTTP/1.1 message format (RFC 9110/9112), chunked encoding, keep-alive
- [ ] Notes on forward proxies, CONNECT tunnelling, TLS interception and its ethics
- [ ] Notes on libpcap capture and TCP stream reassembly
- [ ] Usability principles relevant to beginner tooling (e.g. Nielsen heuristics, SUS)
- [ ] All sources in IEEE style, ready for Chapter 2
'@ }
    [pscustomobject]@{ Title = 'Write the requirements specification'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:design,priority:must'; Body = @'
Complete `docs/requirements/SRS.md`.

## Acceptance criteria
- [ ] Two personas: beginner and power user
- [ ] User stories with MoSCoW priority and acceptance tests
- [ ] Functional requirements traced to stories
- [ ] Measurable non-functional requirements (setup time, throughput, added latency, max session size, platforms)
- [ ] Reviewed with the supervisor
'@ }
    [pscustomobject]@{ Title = 'Design the HTTP transaction data model'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:design,area:parser,priority:must'; Body = @'
## Acceptance criteria
- [ ] `HttpTransaction`, `Headers`, `Timings` types in `src/core/include/httplogger/`
- [ ] Covers request, response, sizes, timings, connection info, capture mode, errors
- [ ] Unit tests for construction and invariants
- [ ] Documented in ARCHITECTURE.md section 5
'@ }
    [pscustomobject]@{ Title = 'Write the architecture document'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:design,priority:must'; Body = @'
## Acceptance criteria
- [ ] `docs/architecture/ARCHITECTURE.md` complete: context, components, request sequence, data model, threading, storage, security
- [ ] Quality-attribute targets copied from the SRS
- [ ] Diagrams render on GitHub (Mermaid)
- [ ] Reviewed with the supervisor
'@ }
    [pscustomobject]@{ Title = 'Record key design decisions as ADRs'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:design,type:docs,priority:must'; Body = @'
ADRs let you justify every choice at the viva (handbook 3.5).

## Acceptance criteria
- [ ] ADR-0001 C++20 + CMake + vcpkg (decision filled in)
- [ ] ADR-0002 proxy capture first, passive capture later
- [ ] ADR-0003 SQLite as the session store
- [ ] ADR-0004 Qt 6 Widgets for the GUI (vs Dear ImGui, web UI)
- [ ] ADR-0005 threading model
'@ }
    [pscustomobject]@{ Title = 'Define the testing strategy'; Milestone = $M2; Phase = $P1; Labels = 'phase:1-foundation,type:design,type:test,priority:must'; Body = @'
## Acceptance criteria
- [ ] `docs/testing/TEST_PLAN.md` covers unit, integration, fuzz, performance, usability, acceptance
- [ ] Coverage target agreed
- [ ] Traceability matrix started from the SRS
'@ }
    [pscustomobject]@{ Title = 'Implement the HTTP/1.1 parser on llhttp'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:parser,priority:must'; Body = @'
## Acceptance criteria
- [ ] Parses requests and responses incl. chunked bodies, keep-alive and pipelined messages
- [ ] Malformed input returns an error, never crashes
- [ ] Unit tests use fixtures in `tests/fixtures/`
'@ }
    [pscustomobject]@{ Title = 'Implement the HTTP forward proxy with Asio'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:capture,priority:must'; Body = @'
## Acceptance criteria
- [ ] Listens on `127.0.0.1:<port>` (default 8080, configurable)
- [ ] Forwards all methods and streams bodies without buffering whole responses
- [ ] Handles concurrent connections and keep-alive
- [ ] Upstream errors (DNS, refused, timeout) are logged as failed transactions
- [ ] Integration test: client -> proxy -> local test server
'@ }
    [pscustomobject]@{ Title = 'Support HTTPS CONNECT tunnelling without decryption'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:capture,priority:must'; Body = @'
## Acceptance criteria
- [ ] CONNECT requests are tunnelled transparently
- [ ] Each tunnel is logged with host, port, bytes in/out and duration
- [ ] Browsing HTTPS sites through the proxy works normally
'@ }
    [pscustomobject]@{ Title = 'Record timing metrics for each transaction'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:capture,priority:must'; Body = @'
## Acceptance criteria
- [ ] Start, DNS, connect, time to first byte and total recorded per transaction
- [ ] Monotonic clock used; values tested against a server with known delays
'@ }
    [pscustomobject]@{ Title = 'Build the thread-safe capture pipeline'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:capture,priority:must'; Body = @'
## Acceptance criteria
- [ ] Producer/consumer queue between network threads and the store writer
- [ ] No lost transactions under a load test; back-pressure behaviour documented
- [ ] Clean shutdown flushes pending transactions
- [ ] Passes under ThreadSanitizer or ASan in CI
'@ }
    [pscustomobject]@{ Title = 'Implement the SQLite session store'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:storage,priority:must'; Body = @'
## Acceptance criteria
- [ ] Schema with versioned migrations; WAL mode
- [ ] Batched inserts; indexes on time, host, status, method
- [ ] Bodies stored up to a configurable size cap
- [ ] One `.httplog` file per session; reopening restores it
- [ ] Unit tests on a temporary database
'@ }
    [pscustomobject]@{ Title = 'Implement the query API for stored transactions'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:storage,priority:must'; Body = @'
## Acceptance criteria
- [ ] Filter by method, status/status class, host, path substring, time range
- [ ] Paged results with stable ordering
- [ ] Full-text search over URLs and text bodies (FTS5)
- [ ] Tests for each filter and their combinations
'@ }
    [pscustomobject]@{ Title = 'Decode compressed bodies and detect content types'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:parser,priority:should'; Body = @'
## Acceptance criteria
- [ ] gzip, deflate and br decoded for display; raw bytes kept
- [ ] Content type detected from headers, falling back to sniffing
- [ ] Decompression bomb protection (size limit)
'@ }
    [pscustomobject]@{ Title = 'Export sessions to HAR 1.2, JSON and CSV'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:storage,priority:must'; Body = @'
## Acceptance criteria
- [ ] HAR output validates against the HAR 1.2 spec and opens in Chrome/Firefox DevTools
- [ ] JSON and CSV exports of the current filter result
- [ ] Round-trip test: export -> parse -> compare
'@ }
    [pscustomobject]@{ Title = 'Build CLI v1: capture, list and export'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,area:cli,priority:must'; Body = @'
## Acceptance criteria
- [ ] `httplog capture --port N [--out file]` with live one-line-per-request output
- [ ] `httplog list <session> [--filter ...]` and `httplog export <session> --format har|json|csv`
- [ ] `--help` for every subcommand; meaningful exit codes
- [ ] CLI tests for argument handling
'@ }
    [pscustomobject]@{ Title = 'Add a configuration file with zero-config defaults'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:feature,priority:should'; Body = @'
## Acceptance criteria
- [ ] Works with no config file at all (beginner path)
- [ ] JSON config in the user's config directory: port, body size cap, storage folder, ignored hosts
- [ ] Invalid config produces a clear message naming the bad key
'@ }
    [pscustomobject]@{ Title = 'Write the end-to-end integration test suite'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:test,priority:must'; Body = @'
## Acceptance criteria
- [ ] Local test server (cpp-httplib) started by the tests
- [ ] Scenarios: GET, POST with body, chunked response, redirect, 404/500, upstream down, CONNECT
- [ ] Runs in CI on all platforms
'@ }
    [pscustomobject]@{ Title = 'Release v0.1.0 for the Progress Review Panel'; Milestone = $M2; Phase = $P2; Labels = 'phase:2-core-logging,type:infra,handbook-deliverable,priority:must'; Body = @'
## Acceptance criteria
- [ ] Tag `v0.1.0`; release notes list completed issues
- [ ] Demo script for the panel: start capture, browse, list, export HAR
'@ }
    [pscustomobject]@{ Title = 'Create the Qt 6 application shell'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] Main window with menu, toolbar and status bar; links `httplogger::core`
- [ ] GUI build enabled in CI on at least one platform
- [ ] Capture runs off the GUI thread; live events arrive via queued signals
'@ }
    [pscustomobject]@{ Title = 'Build the first-run setup wizard'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] Wizard chooses a free port, explains browser/system proxy setup per OS with screenshots
- [ ] "Test connection" step confirms the first request was captured
- [ ] Can be re-opened from the Help menu
- [ ] Target: a new user captures their first request within the time set in the SRS (measured in Phase 5)
'@ }
    [pscustomobject]@{ Title = 'Add one-click start/stop capture with a status indicator'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] Single Start/Stop button with keyboard shortcut
- [ ] Status bar shows state, port and request count
- [ ] Port-in-use and permission errors explained in plain language with a fix
'@ }
    [pscustomobject]@{ Title = 'Build the live request table'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] `QAbstractTableModel` over the store: method, status, host, path, size, duration, time
- [ ] Status colour-coded by class (2xx/3xx/4xx/5xx) with a text label as well (not colour alone)
- [ ] Auto-scroll that pauses when the user scrolls up
- [ ] Remains responsive at the session size set in the SRS
'@ }
    [pscustomobject]@{ Title = 'Build the request detail panel'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] Tabs: Overview, Request headers, Response headers, Body, Timing
- [ ] Body viewer pretty-prints JSON/XML/HTML and previews images
- [ ] Timing tab shows a waterfall of DNS/connect/TTFB/download
- [ ] Copy as cURL
'@ }
    [pscustomobject]@{ Title = 'Add simple search and quick filters'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] Search box over URL and host
- [ ] One-click filters: Errors (4xx/5xx), Slow requests, by method, by domain
- [ ] Clear-all-filters control; active filters always visible
'@ }
    [pscustomobject]@{ Title = 'Add plain-language explanations and a glossary'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:should'; Body = @'
## Acceptance criteria
- [ ] Tooltips explain status codes and common headers in one sentence each
- [ ] In-app glossary (proxy, header, status code, latency, HTTPS, ...)
- [ ] Explanations can be turned off by power users
'@ }
    [pscustomobject]@{ Title = 'Design empty, loading and error states'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:should'; Body = @'
## Acceptance criteria
- [ ] Empty session shows the next step (start capture / run wizard)
- [ ] No-results filter state offers to clear filters
- [ ] Every error message says what happened and how to fix it
'@ }
    [pscustomobject]@{ Title = 'Save and open capture sessions'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] Save / Save As / Open for `.httplog` files; recent-files menu
- [ ] Unsaved-session prompt on exit
- [ ] Export menu reuses the core HAR/JSON/CSV exporters
'@ }
    [pscustomobject]@{ Title = 'Make the GUI accessible and keyboard-friendly'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:feature,area:gui,priority:should'; Body = @'
## Acceptance criteria
- [ ] Logical tab order and visible focus everywhere
- [ ] Light and dark themes; respects the OS font size
- [ ] Screen-reader names on controls (Qt accessibility)
'@ }
    [pscustomobject]@{ Title = 'Write the beginner quick-start guide'; Milestone = $M3; Phase = $P3; Labels = 'phase:3-beginner-ui,type:docs,priority:should'; Body = @'
## Acceptance criteria
- [ ] `docs/user-guide/quick-start.md` with screenshots: install, wizard, first capture, find an error, export
- [ ] Linked from the app's Help menu and the README
'@ }
    [pscustomobject]@{ Title = 'Implement the filter query language'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:analyzer,priority:must'; Body = @'
## Acceptance criteria
- [ ] Grammar documented, e.g. `status:>=400 host:*.example.com method:POST time:>500ms body:"token"`
- [ ] Supports AND/OR/NOT and parentheses
- [ ] Parser with clear error positions; compiled to SQL against the store
- [ ] Shared by GUI (advanced filter bar with autocomplete) and CLI
- [ ] Unit tests, including fuzzed inputs
'@ }
    [pscustomobject]@{ Title = 'Build the analytics dashboard'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:analyzer,area:gui,priority:must'; Body = @'
## Acceptance criteria
- [ ] Requests over time, status-class mix, top hosts, latency p50/p95/p99
- [ ] Charts follow the active filter
- [ ] Statistics computed in core (tested) and reused by the CLI
'@ }
    [pscustomobject]@{ Title = 'Add opt-in HTTPS interception with a local CA'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:capture,ethics,priority:should'; Body = @'
## Acceptance criteria
- [ ] Off by default; enabling shows a clear warning and explanation
- [ ] Generates a local CA (OpenSSL 3); private key stored with user-only permissions
- [ ] Per-host certificates generated and cached
- [ ] Guided CA install/uninstall instructions per OS
- [ ] Per-host exclusion list (e.g. banking, certificate-pinned apps)
- [ ] Decrypted traffic clearly marked in the UI
'@ }
    [pscustomobject]@{ Title = 'Add passive capture mode with libpcap or Npcap'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:capture,priority:could'; Body = @'
## Acceptance criteria
- [ ] Interface selection; BPF filter for configured ports
- [ ] TCP stream reassembly feeding the existing HTTP parser
- [ ] Privilege requirements documented per OS
- [ ] Tested against recorded pcap fixtures
'@ }
    [pscustomobject]@{ Title = 'Build the alert rule engine'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:analyzer,priority:should'; Body = @'
## Acceptance criteria
- [ ] Rules written in the filter language plus thresholds (e.g. 5xx rate > N/min, latency > X ms)
- [ ] Matching transactions highlighted; desktop notification optional
- [ ] Rules saved in config; unit tests for evaluation
'@ }
    [pscustomobject]@{ Title = 'Compare two transactions side by side'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:gui,priority:could'; Body = @'
## Acceptance criteria
- [ ] Select two rows -> diff of headers and bodies with changes highlighted
'@ }
    [pscustomobject]@{ Title = 'Edit and resend a request'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:capture,area:gui,priority:should'; Body = @'
## Acceptance criteria
- [ ] Open any request in an editor (method, URL, headers, body) and resend it
- [ ] Response captured as a new transaction linked to the original
'@ }
    [pscustomobject]@{ Title = 'Import HAR files for analysis'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:capture,priority:should'; Body = @'
## Acceptance criteria
- [ ] HAR files exported from browser DevTools open as a session
- [ ] Unsupported fields reported, not silently dropped
'@ }
    [pscustomobject]@{ Title = 'Add keyboard shortcuts and a command palette'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:gui,priority:should'; Body = @'
## Acceptance criteria
- [ ] Shortcuts for capture, search, filter, next/previous error, export
- [ ] Command palette (Ctrl/Cmd+K) lists every action
- [ ] Shortcut reference in the user guide
'@ }
    [pscustomobject]@{ Title = 'Save filters, views and presets'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:gui,priority:should'; Body = @'
## Acceptance criteria
- [ ] Save and name filter queries and column layouts
- [ ] Built-in presets for beginners (e.g. "Only errors", "API calls", "Slow pages")
'@ }
    [pscustomobject]@{ Title = 'Add headless analysis to the CLI'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:feature,area:cli,priority:should'; Body = @'
## Acceptance criteria
- [ ] `httplog analyze <session> [--filter ...]` prints the same statistics as the dashboard
- [ ] `--json` output on every read command for scripting
- [ ] Reads/writes stdin/stdout where it makes sense (pipe-friendly)
'@ }
    [pscustomobject]@{ Title = 'Profile and optimise performance'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:test,priority:must'; Body = @'
## Acceptance criteria
- [ ] Profiled under load (perf / VTune / Instruments); hotspots recorded
- [ ] Non-functional targets from the SRS met, or the gap explained
- [ ] Before/after numbers committed to `docs/evaluation/`
'@ }
    [pscustomobject]@{ Title = 'Investigate HTTP/2 support (stretch)'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:research,area:parser,priority:could'; Body = @'
## Acceptance criteria
- [ ] Short investigation (e.g. nghttp2) with effort estimate
- [ ] ADR: implement now, or record as future work in the dissertation
'@ }
    [pscustomobject]@{ Title = 'Release v0.9 for the Software Demonstration'; Milestone = $M3; Phase = $P4; Labels = 'phase:4-advanced,type:infra,handbook-deliverable,priority:must'; Body = @'
## Acceptance criteria
- [ ] Tag `v0.9.0` with installable builds for your demo platform
- [ ] Core flows work end to end: wizard -> capture -> filter -> analyse -> export
'@ }
    [pscustomobject]@{ Title = 'Reach the unit-test coverage target'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:test,priority:must'; Body = @'
## Acceptance criteria
- [ ] Coverage of `src/core` meets the target in TEST_PLAN.md
- [ ] Report saved to `docs/testing/` for the testing chapter
'@ }
    [pscustomobject]@{ Title = 'Fuzz-test the HTTP parser and filter language'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:test,area:parser,priority:should'; Body = @'
## Acceptance criteria
- [ ] libFuzzer targets for the parser and the filter-language parser
- [ ] At least 1 hour per target with no crashes; corpus committed
- [ ] Any crash found becomes a regression test
'@ }
    [pscustomobject]@{ Title = 'Run performance and load benchmarks'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:test,priority:must'; Body = @'
## Acceptance criteria
- [ ] Throughput (req/s), added latency (p50/p95) and memory at large session sizes measured
- [ ] Method documented (hardware, load tool, repetitions) so results are reproducible
- [ ] Results and charts in `docs/evaluation/`
'@ }
    [pscustomobject]@{ Title = 'Compare the tool against existing tools'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:test,type:research,priority:must'; Body = @'
Handbook 3.4 (Evaluation): results must be related to other people's results.

## Acceptance criteria
- [ ] Same tasks/benchmarks run with 2-3 tools from the Phase 1 review
- [ ] Feature, setup-time and performance comparison table
- [ ] Strengths and weaknesses written up honestly
'@ }
    [pscustomobject]@{ Title = 'Run the usability study with beginners and power users'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:test,ethics,priority:must'; Body = @'
**Blocked until ethics approval is received.**

## Acceptance criteria
- [ ] Task script for both personas (e.g. first capture; find the slowest failing API call)
- [ ] Measures: task success, time to first capture, SUS questionnaire, comments
- [ ] Signed consent from every participant; data anonymised
- [ ] Results analysed and stored in `docs/evaluation/`
'@ }
    [pscustomobject]@{ Title = 'Complete acceptance testing against the requirements'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:test,priority:must'; Body = @'
## Acceptance criteria
- [ ] Every Must requirement in the SRS has a passing test or recorded evidence
- [ ] Traceability matrix complete; unmet requirements explained
'@ }
    [pscustomobject]@{ Title = 'Review security and privacy'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:test,ethics,priority:should'; Body = @'
## Acceptance criteria
- [ ] Proxy binds to localhost by default; remote access requires explicit opt-in
- [ ] CA key handling, temp files and session files reviewed
- [ ] Dependency versions checked for known vulnerabilities
'@ }
    [pscustomobject]@{ Title = 'Fix issues raised at the Software Demonstration'; Milestone = $M4; Phase = $P5; Labels = 'phase:5-evaluation,type:bug,priority:must'; Body = @'
## Acceptance criteria
- [ ] Every piece of demo feedback recorded as an issue
- [ ] Must-fix items closed before the dissertation freeze
'@ }
    [pscustomobject]@{ Title = 'Prepare and give the Software Demonstration'; Milestone = $M3; Phase = $P6; Labels = 'phase:6-dissertation,type:admin,handbook-deliverable,priority:must'; Body = @'
Handbook 2.2.3: not assessed, but feedback covers progress, oral communication and the portfolio's aim/objectives.

## Acceptance criteria
- [ ] Demo script covering beginner and power-user flows, with prepared sample traffic
- [ ] Backup recording in case of network problems
- [ ] Feedback written up as issues
'@ }
    [pscustomobject]@{ Title = 'Agree the dissertation plan with the supervisor'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:docs,handbook-deliverable,priority:must'; Body = @'
Handbook 4.3: do this early, ideally at the start of the Spring semester.

## Acceptance criteria
- [ ] Chapter and section outline with 1-2 sentences per section
- [ ] Department template chosen (Word or LaTeX, handbook 4.2)
- [ ] Plan agreed in a supervisor meeting (logged)
'@ }
    [pscustomobject]@{ Title = 'Draft Chapter 2: background and literature review'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:docs,priority:must'; Body = @'
Can be written first (handbook 4.3). Assessed under Literature review and use of resources (10%).

## Acceptance criteria
- [ ] Synthesis, not a list: related tools, HTTP/proxy/TLS theory, usability
- [ ] Concludes with points relevant to this project
- [ ] All sources cited in IEEE style
'@ }
    [pscustomobject]@{ Title = 'Draft the main chapters: requirements, design, implementation, testing'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:docs,priority:must'; Body = @'
Assessed under Problem-solving process (15%) and Products (30%).

## Acceptance criteria
- [ ] Software process chosen and justified; evidence it was followed (board, PRs, CI history)
- [ ] Requirements, design (with diagrams), implementation (relevant snippets only) and testing chapters drafted
- [ ] Figures, tables and equations numbered by chapter (Fig. 3.1 ...)
'@ }
    [pscustomobject]@{ Title = 'Draft the introduction, evaluation and conclusions'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:docs,priority:must'; Body = @'
Assessed under Problem description/aim/objectives (10%) and Evaluation (20%).

## Acceptance criteria
- [ ] Introduction states motivation, aim and objectives clearly
- [ ] Evaluation: results, objectives met or not (with reasons), strengths/weaknesses, comparison with other tools, process evaluation
- [ ] Conclusions (2-3 pages) with future work
- [ ] Abstract 150-250 words
'@ }
    [pscustomobject]@{ Title = 'Send the full draft to the supervisor for feedback'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:docs,handbook-deliverable,priority:must'; Body = @'
Feedback normally takes 10-15 working days, and the same work can be submitted for feedback only once (handbook 1.6).

## Acceptance criteria
- [ ] Complete draft sent at least 3 weeks before the submission deadline
- [ ] Feedback logged and turned into issues
'@ }
    [pscustomobject]@{ Title = 'Check formatting, references and the formatting checklist'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:docs,handbook-deliverable,priority:must'; Body = @'
Handbook section 4. Clarity of communication is 15%.

## Acceptance criteria
- [ ] Main body at most 10,000 words / 50 pages (excluding preamble, references, appendices)
- [ ] 12-pt Times New Roman, single spacing, 6-pt paragraph spacing, 30 mm margins
- [ ] Right-aligned chapter header and page-number footer; roman numerals in the preamble; A-1 style appendix numbering
- [ ] Preamble: title page, abstract, declaration, acknowledgements, ToC, list of figures, list of tables
- [ ] IEEE references in citation order; every source cited in the text
- [ ] Formal language, passive voice, no contractions; spell-checked and proofread
- [ ] Report Formatting Checklist (Student Corner) completed
'@ }
    [pscustomobject]@{ Title = 'Record the 6-minute project video'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:docs,handbook-deliverable,priority:must'; Body = @'
Handbook 2.2.4.

## Acceptance criteria
- [ ] Part (a): 3-minute software demonstration
- [ ] Part (b): 3-minute code walkthrough (important parts and structure)
- [ ] Total no more than 6 minutes; .mp4 or .avi
'@ }
    [pscustomobject]@{ Title = 'Submit the final dissertation package'; Milestone = $M4; Phase = $P6; Labels = 'phase:6-dissertation,type:admin,handbook-deliverable,priority:must'; Body = @'
Handbook 2.2.4. Missing the deadline is an automatic fail (3.8); extensions must be requested at least 3 weeks before (3.7.1).

## Acceptance criteria
- [ ] Two spiral-bound, double-sided printed copies to the Course Administrator
- [ ] Google Form: dissertation PDF, source files (.docx/.tex), video
- [ ] Source code submitted; repository tagged `v1.0.0`
- [ ] Dissertation uploaded to TurnItIn
- [ ] AI journal complete and declaration worded as agreed with the supervisor
'@ }
    [pscustomobject]@{ Title = 'Prepare for the viva'; Milestone = $M5; Phase = $P6; Labels = 'phase:6-dissertation,type:admin,handbook-deliverable,priority:must'; Body = @'
Handbook 2.2.5 / 3.5: ~30 minutes, physical presence required; the outcome can raise or lower the dissertation mark.

## Acceptance criteria
- [ ] Live demo rehearsed on the machine you will bring (plus a recorded backup)
- [ ] Every key decision explained from the ADRs, with nuance beyond the written report
- [ ] Shortcuts, limitations and future improvements listed honestly
- [ ] Able to explain any part of the code and any AI-assisted part recorded in the AI journal
- [ ] Mock viva with a peer or the supervisor
'@ }
)

# =============================================================================
# Main
# =============================================================================
if ($DryRun) { Write-Step 'DRY RUN: nothing will be changed' }
Write-Step "Repository: $Repo"

Write-Step 'Labels'
foreach ($l in $LabelList) { Set-Label $l[0] $l[1] $l[2] }

Write-Step 'Milestones'
New-Milestone $M1 $DuePortfolio  'Handbook 2.2.1: project portfolio to supervisor (10%).'
New-Milestone $M2 $DuePanel      'Handbook 2.2.2: 15-minute progress review panel (10%). Core logging working; detailed plan to submission.'
New-Milestone $M3 $DueDemo       'Handbook 2.2.3: software demonstration to academic staff. Product nearing completion.'
New-Milestone $M4 $DueSubmission 'Handbook 2.2.4: dissertation, source code, 6-minute video, TurnItIn (60% with viva).'
New-Milestone $M5 $DueViva       'Handbook 2.2.5: viva (oral examination), physical presence required.'

Initialize-Project
Get-ExistingTitles

$currentPhase = ''
foreach ($i in $Issues) {
    if ($i.Phase -ne $currentPhase) { $currentPhase = $i.Phase; Write-Step "Phase $currentPhase" }
    New-Issue $i.Title $i.Milestone $i.Phase $i.Labels $i.Body
}

if ($DryRun) {
    Write-Step "Dry run finished: $script:Created issue(s) would be created."
} else {
    Write-Step "Done: $script:Created issue(s) created, $script:Skipped skipped (already existed), $script:Failed failed."
    if ($script:Failed -gt 0) { Write-Warn 're-run the same command to retry the failed issues (created ones are skipped).' }
}
if ($script:ProjectNumber -and -not $DryRun) {
    Write-Host @"

Next steps on the board (GitHub's CLI cannot create views, so do these once in the web UI):
  1. Open https://github.com/users/$Owner/projects/$($script:ProjectNumber)
  2. Board view: group columns by Status (Todo, In Progress, Done).
  3. Table view: group by Phase; show Milestone, Labels, Estimate (h).
  4. Roadmap view: bars from Start date -> Target date, milestones as markers;
     screenshot it as the GANTT chart for the portfolio and the panel.
  5. Workflows: enable "Item closed -> Done" and "Pull request merged -> Done".
  6. Fill in Estimate (h), Start date and Target date on every issue (your own estimates).
"@
}
