# check_file_sizes.ps1 — flags Lua files exceeding PROJECT_STANDARDS §2.1 limits.
# Target: 1500 lines per file. Hard limit: 2500 lines.
#
# See qa/CHECKS.md row 52.
#
# RATCHET BASELINE (issue #429): the hard-limit (2500) violations are FROZEN in
# qa/baselines/file_sizes.json. A file already in the baseline only fails if it
# GROWS beyond its frozen line count; a file NOT in the baseline that crosses the
# hard limit fails immediately. This lets the gate BLOCK on regressions without
# being permanently red on the 13 known-oversized files (which are tracked for
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
    [switch]$UpdateBaseline
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$baselinePath = Join-Path $PSScriptRoot "baselines\file_sizes.json"
$overTarget = @()
$overHard = @()

function Find-ModLuas {
    Get-ChildItem -Path $repoRoot -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $p -notlike "*\_archive\*" `
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
                -and $_.Name -notmatch "^_cosmetic_unlocks" `
                -and $_.Name -notmatch "_localization\.lua$" `
                -and $_.Name -notmatch "^item_master_list_"
        }
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
