# check_issue_status_labels.ps1 - GitHub issue STATUS-LABEL drift scan.
#
# Doctrine: PROJECT_STANDARDS.md § 11 "Labels". Every issue carries status +
# type + mod. The lifecycle STATUS labels are:
#   not-started        - no fix or diagnostic work attempted yet.
#   diagnostics-armed  - a diagnostic/probe shipped; user repros to capture data.
#   verify-fix         - a code fix shipped; the user tests it in-game solo.
#   verify-fix-coop    - a code fix shipped; needs 2+ testers in-game.
#   Fixed              - user-verified; post-fix pass (hardening/docs/tests) owed.
# When work ships for an issue, the matching status label must be added (and
# not-started removed) in the SAME pass as the CHANGELOG entry (rule #5 /
# CLAUDE.md #13). This check catches the recurring miss where a fix/probe ships
# in the latest CHANGELOG entry but the issue still says not-started / nothing.
# A second pass (issue #498) sweeps ALL open issues for a missing lifecycle
# state entirely - every open issue must carry exactly one of the five.
#
# This is a WARNING-ONLY, NON-BLOCKING advisory scan (wired into run_all.ps1
# under -Policy 'Advisory', exactly like check_loc_tags.ps1). It NEVER fails the
# gate - it exists to nudge, and the maintainer decides each case.
#
# WHAT IT DOES
#   For each active mod, it reads the TOP (most recent) `## <version>` entry of
#   that mod's CHANGELOG.md, extracts every `#<N>` issue reference in that entry,
#   asks GitHub whether issue N is OPEN, and - if OPEN with NEITHER status label
#   - warns: "shipped work referenced in latest CHANGELOG entry but issue has no
#   status label". Only the TOP entry is scanned: a stale label on an OLD entry
#   is out of scope (it would have been labeled when it shipped), and scanning
#   the whole history would re-flag every long-closed reference.
#
# HEURISTIC (documented so future edits stay conservative - deliberately low
# false-positive, matching check_loc_tags.ps1's design intent):
#
#   * LOCALIZATION-SWEEP ENTRIES ARE SKIPPED. A repo-wide loc doctrine pass
#     (LOCALIZATION_STANDARD.md § 13, issue #301) produces a top entry whose
#     header reads e.g. "Localization: applied dev status-tag doctrine (#301)".
#     Those entries are "tags-only change: no runtime/behavior effect" and they
#     reference MANY open issues purely as tag CONTEXT (which feature each tag
#     names), NOT as shipped work. Flagging them would drown the real signal, so
#     a top entry whose header matches the loc-sweep pattern is skipped with a
#     notice. (Its referenced issues were labeled - or intentionally left plain -
#     when their actual fix/probe shipped in an earlier entry.)
#
#   * CONTEXT-MENTIONS STILL SURFACE, BY DESIGN. A real fix entry can also name
#     an issue it did NOT fix ("...latent bug, NOT fixed here, tracked as #322").
#     The check cannot read intent, so such a ref is reported for the maintainer
#     to dismiss. That is the point of an ADVISORY check: surface for review, not
#     auto-decide. Keep this in mind reading the output.
#
#   * FALSE-POSITIVE NUMBERS (footnote "#2", "argument #4", a not-yet-created
#     forward-ref) resolve to a non-existent / unrelated issue; a `gh issue view`
#     that errors for a specific number is skipped silently (only a global gh
#     auth/availability failure short-circuits the whole run).
#
# OFFLINE / UNAUTHENTICATED: if `gh` is not installed or not authenticated, the
# check prints a notice and exits 0. It NEVER fails when it cannot reach GitHub.
#
# Output mirrors qa/check_loc_tags.ps1.
#
# Exit codes:
#   0 - clean (no unlabeled shipped-work refs), OR gh unavailable (never fail offline)
#   1 - one or more advisory WARNINGS - NEVER blocks (Advisory policy in run_all).
#   2 - hard error (a CHANGELOG failed to read, or -SelfTest regression).
#
# Self-test: pass `-SelfTest` to exercise the pure (no-network) parsing logic -
# top-entry extraction, loc-sweep header detection, and `#N` ref harvesting -
# against synthetic fixtures. Exit 0 = parser wired correctly; exit 2 = regression.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path

# ---- the status-label lifecycle (§ 11; user rules 2026-07-11/12) ----
# verify-fix (solo-verifiable fix) | verify-fix-coop (needs 2+ testers) |
# diagnostics-armed (probe) | Fixed (user-verified; post-fix pass owed).
# not-started marks zero work; it does NOT count as a worked status here.
$StatusLabels = @('verify-fix', 'verify-fix-coop', 'diagnostics-armed', 'Fixed')
$LifecycleLabels = $StatusLabels + @('not-started')

# ---- active mods whose CHANGELOG.md is authored newest-first ----
# Mirrors the ship-doctrine "active mods" set: the single-stream mods + the five
# `_dev` clones. Excludes weapon_tweaker_dev (STALE clone), the frozen legacy
# `tweaker`, retired buff_tweaker/_archive, and the unsuffixed stable dirs of the
# five split mods (their in-flight CHANGELOG lives in the `_dev` sibling).
$ActiveMods = @(
    'weapon_tweaker',
    'cosmetics_tweaker',
    'character_weapon_variants',
    'weapons_of_chaos',
    'chaos_wastes_tweaker_dev',
    'crafting_in_modded_dev',
    'general_tweaker_dev',
    'gui_tweaker_dev',
    'verminious_dreams_lighting_dev',
    'event_tweaker',
    'career_tweaker',
    'enemy_tweaker',
    'modded_progression',
    'dynamic_cosmetic_portraits'
)

# ---- localization-sweep header detector (see HEURISTIC above) ----
# A top-entry header matching any of these is a tags-only loc pass; its issue
# refs are tag CONTEXT, not shipped work, so the entry is skipped.
$rxLocSweep = [regex]'(?i)(localization|loc sweep|status-tag doctrine|menu wording|localization audit|loc audit)'

$rxVerHeader = [regex]'^\s*##\s+\S'
$rxIssueRef  = [regex]'#(\d+)'

# Extract the TOP `## <version>` entry (header line through the line before the
# next `## ` header) from a CHANGELOG's full text. Returns @{ Header; Body } or
# $null if the file has no `## ` header at all.
function Get-TopEntry {
    param([string]$Text)
    $lines = $Text -split "`r?`n"
    $first = -1; $second = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($rxVerHeader.IsMatch($lines[$i])) {
            if ($first -lt 0) { $first = $i }
            elseif ($second -lt 0) { $second = $i; break }
        }
    }
    if ($first -lt 0) { return $null }
    $endExclusive = if ($second -ge 0) { $second } else { $lines.Count }
    $header = $lines[$first].Trim()
    $body   = ($lines[$first..($endExclusive - 1)] -join "`n")
    return @{ Header = $header; Body = $body }
}

# Unique, sorted issue numbers referenced anywhere in a text block.
function Get-IssueRefs {
    param([string]$Text)
    $set = @{}
    foreach ($m in $rxIssueRef.Matches($Text)) { $set[[int]$m.Groups[1].Value] = $true }
    return @($set.Keys | Sort-Object)
}

function Test-IsLocSweep {
    param([string]$Header)
    return $rxLocSweep.IsMatch($Header)
}

# ---- gh helpers (network) ----
function Test-GhReady {
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) { return $false }
    & gh auth status 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Returns @{ State = 'OPEN'|'CLOSED'; Labels = @(...) } or $null when the issue
# can't be resolved (non-existent number, transient error) - caller skips it.
function Get-IssueMeta {
    param([int]$Number)
    $json = & gh issue view $Number --json state,labels 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return $null }
    try {
        $o = $json | ConvertFrom-Json
        $labels = @()
        if ($o.labels) { $labels = @($o.labels | ForEach-Object { $_.name }) }
        return @{ State = $o.state; Labels = $labels }
    } catch { return $null }
}

# ---- self-test (pure parsing, no network) ----
function Invoke-SelfTest {
    $pass = $true
    function Assert($cond, $desc) {
        $verdict = if ($cond) { 'PASS' } else { 'FAIL' }
        $colour  = if ($cond) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $desc) -ForegroundColor $colour
        if (-not $cond) { $script:__stpass = $false }
    }
    $script:__stpass = $true

    $fixReal = @"
## 0.7.222-dev (2026-07-04) - #294 (crash) FIXED: non-resident pickup CTD

- **#294 (crash) FIXED.** blah blah. Separate latent bug tracked as #322.

## 0.7.221-dev (2026-07-04) - Localization: applied dev status-tag doctrine (#301)

- loc pass referencing #288 and #299 as tag context.
"@
    $top = Get-TopEntry $fixReal
    Assert ($null -ne $top) "top-entry found in a normal changelog"
    Assert ($top.Header -like '*0.7.222-dev*') "top header is the newest version (0.7.222, not 0.7.221)"
    $refs = Get-IssueRefs $top.Body
    Assert (($refs -contains 294) -and ($refs -contains 322)) "top-entry refs harvest #294 + #322"
    Assert (-not ($refs -contains 288)) "refs do NOT bleed into the SECOND (0.7.221) entry (#288 excluded)"
    Assert (-not (Test-IsLocSweep $top.Header)) "a real fix header is NOT flagged as a loc sweep"

    $fixLoc = @"
## 0.12.204-dev (2026-07-04) - Localization: applied dev status-tag doctrine (#301)

- tagged everything; references #74 #108 #131 as tag context.
"@
    $topL = Get-TopEntry $fixLoc
    Assert (Test-IsLocSweep $topL.Header) "a loc-doctrine header IS flagged as a loc sweep (skipped)"

    $noHdr = "just a title line`nno version headers here"
    Assert ($null -eq (Get-TopEntry $noHdr)) "a changelog with no ## header returns null (no crash)"

    Write-Host ""
    if ($script:__stpass) {
        Write-Host "[check_issue_status_labels -SelfTest] OK -- parser logic intact." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[check_issue_status_labels -SelfTest] FAILED -- parsing regression." -ForegroundColor Red
        return 2
    }
}

# ---- main ----
Write-Host "=== check_issue_status_labels ===" -ForegroundColor Cyan

if ($SelfTest) { exit (Invoke-SelfTest) }

if (-not (Test-GhReady)) {
    Write-Host "[check_issue_status_labels] gh not installed or not authenticated - skipping (offline, non-blocking)." -ForegroundColor DarkYellow
    exit 0
}

# Pass 1: harvest (mod, issue) candidates from each active mod's TOP entry.
$candidates = @()   # rows: @{ Mod; Ver; Issue }
$hardError = $false
foreach ($m in $ActiveMods) {
    $cl = Join-Path $repoRoot "$m\CHANGELOG.md"
    if (-not (Test-Path $cl)) {
        if (-not $Quiet) { Write-Host "Skipping $m - no CHANGELOG.md" -ForegroundColor DarkGray }
        continue
    }
    try {
        $text = [System.IO.File]::ReadAllText($cl, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Host ("  X {0}: {1}" -f $m, $_) -ForegroundColor Red
        $hardError = $true
        continue
    }
    $top = Get-TopEntry $text
    if (-not $top) {
        if (-not $Quiet) { Write-Host "Skipping $m - no '## ' entry" -ForegroundColor DarkGray }
        continue
    }
    if (Test-IsLocSweep $top.Header) {
        if (-not $Quiet) { Write-Host "Skipping $m - top entry is a localization sweep ($($top.Header))" -ForegroundColor DarkGray }
        continue
    }
    $refs = Get-IssueRefs $top.Body
    if (-not $Quiet) { Write-Host "Scanning $m - $($top.Header) - refs: $($refs -join ', ')" -ForegroundColor DarkGray }
    foreach ($n in $refs) {
        $candidates += [pscustomobject]@{ Mod = $m; Ver = $top.Header; Issue = $n }
    }
}

# Pass 2: resolve each unique issue once, then flag OPEN + no-status refs.
$metaCache = @{}
$findings = @()
foreach ($c in ($candidates | Sort-Object Issue, Mod)) {
    if (-not $metaCache.ContainsKey($c.Issue)) {
        $metaCache[$c.Issue] = Get-IssueMeta -Number $c.Issue
    }
    $meta = $metaCache[$c.Issue]
    if (-not $meta) { continue }                       # non-existent / unresolved number
    if ($meta.State -ne 'OPEN') { continue }           # only open issues matter
    $hasStatus = @($meta.Labels | Where-Object { $StatusLabels -contains $_ }).Count -gt 0
    if (-not $hasStatus) {
        $findings += [pscustomobject]@{ Issue = $c.Issue; Mod = $c.Mod; Ver = $c.Ver; Labels = ($meta.Labels -join ',') }
    }
}

# Pass 3 (issue #498): EVERY open issue must carry a lifecycle state - one of
# the four worked statuses or not-started. Zero lifecycle labels = drift.
$stateless = @()
$openJson = & gh issue list --state open --limit 400 --json number,labels 2>$null
if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($openJson)) {
    try {
        foreach ($o in ($openJson | ConvertFrom-Json)) {
            $lbls = @()
            if ($o.labels) { $lbls = @($o.labels | ForEach-Object { $_.name }) }
            if (-not ($lbls | Where-Object { $LifecycleLabels -contains $_ })) {
                $stateless += [pscustomobject]@{ Issue = $o.number; Labels = ($lbls -join ',') }
            }
        }
    } catch {}
}

Write-Host ""
if ($hardError) {
    Write-Host "[check_issue_status_labels] ERROR -- a CHANGELOG failed to read." -ForegroundColor Red
    exit 2
}

if ($findings.Count -eq 0 -and $stateless.Count -eq 0) {
    Write-Host "[check_issue_status_labels] OK -- CHANGELOG-referenced issues carry status labels; every open issue carries a lifecycle state." -ForegroundColor Green
    exit 0
}

if ($stateless.Count -gt 0) {
    Write-Host ("[check_issue_status_labels] {0} open issue(s) carry NO lifecycle state (not-started / diagnostics-armed / verify-fix / verify-fix-coop / Fixed):" -f $stateless.Count) -ForegroundColor Yellow
    foreach ($s in ($stateless | Sort-Object Issue)) {
        $lbl = if ($s.Labels) { $s.Labels } else { '(no labels)' }
        Write-Host ("  ! #{0} [{1}]" -f $s.Issue, $lbl) -ForegroundColor Yellow
    }
}

if ($findings.Count -eq 0) { exit 1 }

Write-Host ("[check_issue_status_labels] WARNINGS: {0} -- advisory, non-blocking." -f $findings.Count) -ForegroundColor Yellow
Write-Host "  -- shipped work referenced in latest CHANGELOG entry but issue has no status label (verify-fix / diagnostics-armed):" -ForegroundColor Yellow
foreach ($f in ($findings | Sort-Object Issue)) {
    $lbl = if ($f.Labels) { $f.Labels } else { '(no labels)' }
    Write-Host ("  ! #{0} [{1}] referenced in {2} ({3})" -f $f.Issue, $lbl, $f.Mod, $f.Ver) -ForegroundColor Yellow
}
Write-Host "  Review each: add verify-fix (a fix shipped) or diagnostics-armed (a probe shipped), or leave unlabeled if the entry only MENTIONS the issue (tracked-not-fixed / context)." -ForegroundColor DarkYellow
exit 1
