# check_dev_only_edits.ps1 — guards the dev/stable split (issue #429).
#
# CLAUDE.md NON-NEGOTIABLE #3 + PROMOTION_PROCESS.md: for the five split mods,
# edits go ONLY to the `*_dev/` directory. The unsuffixed STABLE directory is
# write-by-promotion-only. Nothing previously prevented or flagged an accidental
# stable-dir edit — `promotion-status.ps1` detects the REVERSE (fixes stranded
# in dev). This check flags any staged/diffed change that touches a stable split
# dir so it can't slip into a commit or PR.
#
# The five stable directories (NOT their `_dev` twins — those are the intended
# edit surface, and the trailing `/` in the match excludes `<dir>_dev/`):
#   chaos_wastes_tweaker/  crafting_in_modded/  general_tweaker/
#   gui_tweaker/  verminious_dreams_lighting/
#
# LOCAL BYPASS: set env VT2_PROMOTION=1 for a legitimate maintainer promotion.
# CI authorization is narrower: check_promotion_authorization.ps1 validates the
# live PR label/timeline/comment and exports VT2_PROMOTION=1 together with the
# exact semicolon-delimited VT2_PROMOTION_DIRS. Commit trailers are branch-owned
# input and therefore are not an authorization boundary (issue #676).
#
# Change set sources (union):
#   * staged   — `git diff --cached` (what a commit will contain; pre-commit)
#   * unstaged — `git diff` working tree (unless -Staged is passed)
#   * CI PR    — `origin/$GITHUB_BASE_REF...HEAD` when GITHUB_BASE_REF is set
# If git is unavailable or the diff can't be computed, the check exits 0 (it
# never false-blocks on an indeterminate change set).
#
# Exit codes: 0 = clean / bypassed / indeterminate, 2 = a stable-dir edit found.

[CmdletBinding()]
param(
    [switch]$Staged,     # restrict to staged changes only (pre-commit uses this)
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

$STABLE_DIRS = @(
    'chaos_wastes_tweaker',
    'crafting_in_modded',
    'general_tweaker',
    'gui_tweaker',
    'verminious_dreams_lighting'
)

# Pure classifier (unit-tested by -SelfTest): given repo-relative paths, return
# the ones that touch a stable split dir. Excludes the `_dev` twins.
function Get-StableDirHits {
    param([string[]]$Paths)
    $hits = @()
    foreach ($p in $Paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $norm = $p.Replace('\', '/')
        foreach ($d in $STABLE_DIRS) {
            if ($norm -eq $d -or $norm.StartsWith("$d/")) { $hits += $norm; break }
        }
    }
    return @($hits | Sort-Object -Unique)
}

function Get-AuthorizedPromotionDirs {
    param([string]$Raw)
    $dirs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($value in @("$Raw" -split ';')) {
        $dir = "$value".Trim().TrimEnd('/', '\')
        if ($STABLE_DIRS -contains $dir) { [void]$dirs.Add($dir) }
    }
    return $dirs
}

function Invoke-GitLines {
    param([string[]]$GitArgs)
    try {
        $out = & git @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        return @($out | Where-Object { $_ -and $_.Trim() })
    } catch {
        return @()
    }
}

function Get-ChangedFiles {
    # Not a git repo? Can't determine a change set — don't false-block.
    $null = & git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }

    $set = New-Object System.Collections.Generic.HashSet[string]
    foreach ($f in (Invoke-GitLines @('diff', '--cached', '--name-only', '--diff-filter=ACMR'))) { [void]$set.Add($f) }
    if (-not $Staged) {
        foreach ($f in (Invoke-GitLines @('diff', '--name-only', '--diff-filter=ACMR'))) { [void]$set.Add($f) }
    }
    # CI pull_request: diff the incoming branch against its merge base with the
    # target. Best-effort — a shallow checkout that lacks the base ref just
    # yields nothing (never a false block).
    $base = $env:GITHUB_BASE_REF
    if (-not $Staged -and $base) {
        foreach ($f in (Invoke-GitLines @('diff', '--name-only', '--diff-filter=ACMR', "origin/$base...HEAD"))) { [void]$set.Add($f) }
    }
    return @($set)
}

# ---- self-test: pure classifier, no git ----
function Invoke-SelfTest {
    Write-Host "[check_dev_only_edits] SELF-TEST" -ForegroundColor Cyan
    $paths = @(
        'chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua', # STABLE -> hit
        'gui_tweaker/CHANGELOG.md',                                                          # STABLE -> hit
        'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/x.lua',              # dev twin -> NO hit
        'general_tweaker_dev/general_tweaker_dev.lua',                                        # dev twin -> NO hit
        'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua',                     # single-stream -> NO hit
        'qa/check_dev_only_edits.ps1'                                                         # tooling -> NO hit
    )
    $hits = Get-StableDirHits -Paths $paths
    $expected = @(
        'chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua',
        'gui_tweaker/CHANGELOG.md'
    )
    $hitStable   = ($hits -contains $expected[0]) -and ($hits -contains $expected[1])
    $countRight  = $hits.Count -eq 2
    $noDevTwin   = -not ($hits | Where-Object { $_ -like '*_dev/*' })
    $noSingle    = -not ($hits | Where-Object { $_ -like 'weapon_tweaker/*' })

    $authorized = Get-AuthorizedPromotionDirs -Raw 'crafting_in_modded;gui_tweaker;not_a_mod'
    $exactAuth = $authorized.Count -eq 2 -and $authorized.Contains('crafting_in_modded') -and $authorized.Contains('gui_tweaker')

    Write-Host ("  stable-dir edits flagged:        {0}" -f ($hitStable ? 'PASS' : 'FAIL')) -ForegroundColor ($hitStable ? 'Green' : 'Red')
    Write-Host ("  exactly the 2 stable hits:       {0}" -f ($countRight ? 'PASS' : 'FAIL')) -ForegroundColor ($countRight ? 'Green' : 'Red')
    Write-Host ("  `_dev` twins NOT flagged:         {0}" -f ($noDevTwin ? 'PASS' : 'FAIL')) -ForegroundColor ($noDevTwin ? 'Green' : 'Red')
    Write-Host ("  single-stream mod NOT flagged:   {0}" -f ($noSingle ? 'PASS' : 'FAIL')) -ForegroundColor ($noSingle ? 'Green' : 'Red')
    Write-Host ("  trusted promotion dirs exact:   {0}" -f ($exactAuth ? 'PASS' : 'FAIL')) -ForegroundColor ($exactAuth ? 'Green' : 'Red')

    if ($hitStable -and $countRight -and $noDevTwin -and $noSingle -and $exactAuth) {
        Write-Host "[check_dev_only_edits] SELF-TEST PASSED" -ForegroundColor Green
        return 0
    }
    Write-Host "[check_dev_only_edits] SELF-TEST FAILED (hits: $($hits -join ', '))" -ForegroundColor Red
    return 2
}

# ---- main ----
if ($SelfTest) { exit (Invoke-SelfTest) }

if ($env:VT2_PROMOTION -eq '1' -and -not $env:GITHUB_ACTIONS) {
    Write-Host "[check_dev_only_edits] VT2_PROMOTION=1 — stable-dir edits allowed (promotion pass). Skipping." -ForegroundColor DarkYellow
    exit 0
}

$changed = Get-ChangedFiles
if ($null -eq $changed) {
    if (-not $Quiet) { Write-Host "[check_dev_only_edits] not a git work tree / change set indeterminate — skipping." -ForegroundColor DarkGray }
    exit 0
}

$hits = Get-StableDirHits -Paths $changed
if ($hits.Count -eq 0) {
    Write-Host "[check_dev_only_edits] OK — no edits to split-mod stable directories." -ForegroundColor Green
    exit 0
}

# Trusted CI promotion sanction (issue #676). The authorization check binds
# these dirs to the exact live PR head and current stable versions first.
if ($env:GITHUB_ACTIONS -and $env:VT2_PROMOTION -eq '1') {
    $sanctioned = Get-AuthorizedPromotionDirs -Raw $env:VT2_PROMOTION_DIRS
    $unsanctioned = @($hits | Where-Object { -not $sanctioned.Contains(($_ -split '/')[0]) })
    if ($sanctioned.Count -gt 0 -and $unsanctioned.Count -eq 0) {
        Write-Host "[check_dev_only_edits] stable-dir edits covered by trusted authorization: $($sanctioned -join ', ') — promotion PR. Skipping." -ForegroundColor DarkYellow
        exit 0
    }
    if ($sanctioned.Count -gt 0) {
        Write-Host "[check_dev_only_edits] trusted authorization covers $($sanctioned -join ', ') but OTHER stable dirs are also edited:" -ForegroundColor Red
        $hits = $unsanctioned
    }
}

Write-Host "[check_dev_only_edits] ERRORS — changes touch split-mod STABLE directories (edit the `*_dev/` twin instead; stable is write-by-promotion-only):" -ForegroundColor Red
foreach ($h in $hits) { Write-Host "  X $h" -ForegroundColor Red }
Write-Host "  Fix: move the change to the matching `*_dev/` directory. Local promotion: VT2_PROMOTION=1. CI promotion: maintainer approval per docs/PROMOTION_PROCESS.md." -ForegroundColor Yellow
exit 2
