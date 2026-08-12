# check_file_sizes.ps1 — flags Lua files exceeding PROJECT_STANDARDS §2.1 limits.
# Target: 1500 lines per file. Hard limit: 2500 lines.
#
# See qa/CHECKS.md row 52.
#
# RATCHET BASELINE (issue #429): the hard-limit (2500) violations are FROZEN in
# qa/baselines/file_sizes.json. A file already in the baseline only fails if it
# GROWS beyond its frozen line count; a file NOT in the baseline that crosses the
# hard limit fails immediately. This lets the gate BLOCK on regressions without
# being permanently red on the 9 known-oversized files (which are tracked for
# refactor in PROJECT_STANDARDS §11, not fixable per-session). Regenerate the
# baseline ONLY with -UpdateBaseline (never automatic). Target-tier overages
# (1500–2500) remain plain non-baselined warnings.
#
# Exit codes: 0 = all within target (or only frozen/baselined hard overages),
#             1 = some over target (warn), 2 = NEW hard-limit offender or a
#                 baselined file grew beyond its frozen count.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [int]$Target = 1500,
    [int]$HardLimit = 2500,
    [switch]$Quiet,
    [switch]$UpdateBaseline,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$baselinePath = Join-Path $PSScriptRoot "baselines\file_sizes.json"
$overTarget = @()
$overHard = @()

function Test-GeneratedPureDataLua([string]$path) {
    # PROJECT_STANDARDS section 2.1 exempts pure data.  Recognize only the
    # narrow generator contract: an explicit DO NOT HAND-EDIT banner followed
    # by a top-level table return.  Generated logic remains subject to the
    # normal limit, while catalogues such as Character Dialogue's 34k stable
    # event rows do not require an artificial code-module split.
    $head = @(Get-Content -LiteralPath $path -TotalCount 10 -ErrorAction Stop)
    if ($head.Count -eq 0 -or $head[0] -notmatch 'AUTO-GENERATED.+DO NOT HAND-EDIT') {
        return $false
    }
    return [bool]($head | Where-Object { $_ -match '^\s*return\s*\{' } | Select-Object -First 1)
}

function Test-RepositoryInternalWorktreePath([string]$path) {
    # Agent tools may create complete linked checkouts beneath a hidden
    # repository-owned worktree container. Those checkouts are not source in
    # this repository and must never be counted or frozen into its baseline.
    # Match the convention structurally so .claude/worktrees, .git/worktrees,
    # .codex/worktrees, and a top-level .worktrees directory are all covered.
    $normalized = $path.Replace('\', '/')
    return [regex]::IsMatch(
        $normalized,
        '(?i)(?:^|/)(?:\.[^/]+/worktrees|\.worktrees)(?:/|$)'
    )
}

function Test-ModLuaCandidate([System.IO.FileInfo]$file) {
    $p = $file.FullName
    if (Test-RepositoryInternalWorktreePath $p) { return $false }
    return $p -notlike "*\_archive\*" `
        -and $p -notlike "*\bundleV2\*" `
        -and $p -notlike "*\.build\*" `
        -and $p -notlike "*\.temp\*" `
        -and $p -notlike "*\.spawn_tweaks_ref\*" `
        -and $p -notlike "*\tweaker\*" `
        -and $p -notlike "*\sample_*\*" `
        -and $p -notlike "*\Vermintide-2-Source-Code\*" `
        -and $p -notlike "*\misc-vermintide-mods\*" `
        -and $p -notlike "*\_big_rebalance_extract\*" `
        -and $p -notlike "*.lua.processed" `
        -and $file.Name -notmatch "^_cosmetic_unlocks" `
        -and $file.Name -notmatch "_localization\.lua$" `
        -and $file.Name -notmatch "^item_master_list_" `
        -and -not (Test-GeneratedPureDataLua $file.FullName)
}

function Find-ModLuas {
    Get-ChildItem -Path $repoRoot -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object { Test-ModLuaCandidate $_ }
}

# Baseline keys are repo-relative paths with forward slashes (cross-platform,
# JSON-friendly). Normalize any runtime path to that form before comparison.
function Normalize-RelPath([string]$p) { return $p.Replace('\', '/') }

function Load-Baseline {
    if (-not (Test-Path $baselinePath)) { return @{} }
    try { $j = Get-Content $baselinePath -Raw | ConvertFrom-Json } catch { return @{} }
    $map = @{}
    if ($j.files) {
        foreach ($prop in $j.files.PSObject.Properties) { $map[$prop.Name] = [int]$prop.Value }
    }
    return $map
}

function Invoke-SelfTest {
    $script:FileSizeSelfTestPass = $true
    function Assert([bool]$condition, [string]$description) {
        $verdict = if ($condition) { 'PASS' } else { 'FAIL' }
        $colour = if ($condition) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $description) -ForegroundColor $colour
        if (-not $condition) { $script:FileSizeSelfTestPass = $false }
    }

    $canonicalRel = 'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'
    $canonicalPath = Join-Path $repoRoot ($canonicalRel.Replace('/', '\'))
    $canonicalFile = Get-Item -LiteralPath $canonicalPath -ErrorAction Stop
    $clonedSuffix = 'career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua'

    Assert (Test-RepositoryInternalWorktreePath ".claude/worktrees/agent-a/$clonedSuffix") 'ignores Claude nested worktree checkout'
    Assert (Test-RepositoryInternalWorktreePath ".codex/worktrees/task-a/$clonedSuffix") 'ignores equivalent hidden-tool worktree checkout'
    Assert (Test-RepositoryInternalWorktreePath ".git/worktrees/task-a/gitdir") 'ignores Git repository-internal worktree metadata'
    Assert (Test-RepositoryInternalWorktreePath ".worktrees/task-a/$clonedSuffix") 'ignores conventional top-level hidden worktree checkout'
    Assert (-not (Test-RepositoryInternalWorktreePath $canonicalRel)) 'does not classify canonical module as worktree metadata'
    Assert (Test-ModLuaCandidate $canonicalFile) 'canonical oversized module remains in scan candidates'
    $canonicalLines = (Get-Content -LiteralPath $canonicalPath | Measure-Object -Line).Lines
    Assert ($canonicalLines -gt $HardLimit) 'canonical fixture still exercises hard-limit enforcement'

    $baseline = Load-Baseline
    $internalBaselineKeys = @($baseline.Keys | Where-Object { Test-RepositoryInternalWorktreePath $_ })
    Assert ($baseline.Count -eq 4) 'baseline contains exactly the 4 remaining canonical oversized modules'
    Assert ($internalBaselineKeys.Count -eq 0) 'baseline contains no nested-worktree entries'
    Assert ($baseline.ContainsKey($canonicalRel)) 'baseline retains a canonical oversized module'
    Assert (-not $baseline.ContainsKey('career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua')) 'completed Career decomposition is removed from frozen debt'
    # A file that drops back under the hard limit leaves the frozen set entirely:
    # it can no longer be "frozen at" anything, and check_decomposition_contracts
    # owns its ratchet from then on. cim_dev crossed back under at 0.8.120-dev.
    Assert (-not $baseline.ContainsKey('crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua')) 'cim_dev decomposition below the hard limit is removed from frozen debt'
    # The wt mirror pair crossed back under together at 0.12.301-beta / 0.12.302-dev.
    # Both stream entries leave the frozen set in the same slice, because the gate
    # that binds them (check_wt_stream_parity) forbids one stream decomposing alone.
    Assert (-not $baseline.ContainsKey('weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua')) 'wt decomposition below the hard limit is removed from frozen debt'
    Assert (-not $baseline.ContainsKey('weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua')) 'wt_dev mirror decomposition below the hard limit is removed from frozen debt'

    if ($script:FileSizeSelfTestPass) {
        Write-Host '[check_file_sizes -SelfTest] OK -- worktree exclusion and canonical enforcement intact.' -ForegroundColor Green
        return 0
    }
    Write-Host '[check_file_sizes -SelfTest] FAILED -- worktree exclusion or canonical enforcement regressed.' -ForegroundColor Red
    return 2
}

if ($SelfTest) { exit (Invoke-SelfTest) }

foreach ($lua in Find-ModLuas) {
    $lineCount = (Get-Content $lua.FullName | Measure-Object -Line).Lines
    $relPath = $lua.FullName.Substring($repoRoot.Length + 1)
    if (-not $Quiet) { Write-Host "  $relPath -- $lineCount lines" -ForegroundColor DarkGray }
    if ($lineCount -gt $HardLimit) {
        $overHard += [PSCustomObject]@{ Path = $relPath; Rel = (Normalize-RelPath $relPath); Lines = $lineCount }
    } elseif ($lineCount -gt $Target) {
        $overTarget += [PSCustomObject]@{ Path = $relPath; Lines = $lineCount }
    }
}

# --- -UpdateBaseline: freeze the CURRENT over-hard set and exit (explicit only) ---
if ($UpdateBaseline) {
    $files = [ordered]@{}
    foreach ($f in ($overHard | Sort-Object -Property Rel)) { $files[$f.Rel] = $f.Lines }
    $payload = [ordered]@{
        '_comment'  = "Frozen file-size violations (Lua files over the $HardLimit-line hard limit). Regenerate ONLY with check_file_sizes.ps1 -UpdateBaseline. A baselined file fails only if it GROWS beyond its frozen count; any non-baselined file crossing the hard limit fails immediately. Issue #429 / PROJECT_STANDARDS §11."
        'hard_limit' = $HardLimit
        'generated'  = (Get-Date).ToString('yyyy-MM-dd')
        'files'      = $files
    }
    $dir = Split-Path $baselinePath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $baselinePath -Encoding utf8
    Write-Host "[check_file_sizes] baseline UPDATED: $($files.Count) file(s) frozen -> $baselinePath" -ForegroundColor Cyan
    foreach ($k in $files.Keys) { Write-Host ("  frozen  {0} -- {1} lines" -f $k, $files[$k]) -ForegroundColor DarkGray }
    exit 0
}

$baseline = Load-Baseline

# Classify hard-limit files against the baseline.
$newOffenders = @()   # not in baseline -> ERROR
$grown        = @()   # in baseline but grew beyond frozen count -> ERROR
$frozen       = @()   # in baseline, at or below frozen count -> non-blocking
foreach ($f in $overHard) {
    if ($baseline.ContainsKey($f.Rel)) {
        if ($f.Lines -gt $baseline[$f.Rel]) {
            $grown += [PSCustomObject]@{ Path = $f.Path; Lines = $f.Lines; Baseline = $baseline[$f.Rel] }
        } else {
            $frozen += $f
        }
    } else {
        $newOffenders += $f
    }
}

# Report
Write-Host ""
if ($frozen.Count -gt 0) {
    Write-Host "[check_file_sizes] $($frozen.Count) file(s) over the $HardLimit-line hard limit are BASELINED (frozen in qa/baselines/file_sizes.json); non-blocking until they grow. (baselined: $($frozen.Count))" -ForegroundColor DarkCyan
}

if ($overTarget.Count -gt 0) {
    Write-Host "[check_file_sizes] WARNINGS — files over $Target-line target (split when natural boundary appears):" -ForegroundColor Yellow
    foreach ($f in $overTarget | Sort-Object -Property Lines -Descending) {
        Write-Host "  ! $($f.Path) — $($f.Lines) lines" -ForegroundColor Yellow
    }
}

if ($newOffenders.Count -gt 0 -or $grown.Count -gt 0) {
    Write-Host "[check_file_sizes] ERRORS — hard-limit regressions (split required, or add to baseline via -UpdateBaseline only with maintainer sign-off):" -ForegroundColor Red
    foreach ($f in $newOffenders | Sort-Object -Property Lines -Descending) {
        Write-Host "  X NEW over hard limit: $($f.Path) — $($f.Lines) lines (limit $HardLimit)" -ForegroundColor Red
    }
    foreach ($f in $grown | Sort-Object -Property Lines -Descending) {
        Write-Host "  X GREW beyond baseline: $($f.Path) — $($f.Lines) lines (was frozen at $($f.Baseline))" -ForegroundColor Red
    }
    exit 2
}

if ($overTarget.Count -gt 0) { exit 1 }

Write-Host "[check_file_sizes] OK — no new hard-limit offenders; all other files within target ($Target lines)." -ForegroundColor Green
exit 0
