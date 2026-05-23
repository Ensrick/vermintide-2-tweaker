# check_file_sizes.ps1 — flags Lua files exceeding PROJECT_STANDARDS §2.1 limits.
# Target: 1500 lines per file. Hard limit: 2500 lines.
#
# See qa/CHECKS.md row 52.
#
# Exit codes: 0 = all within target, 1 = some over target (warn), 2 = over hard limit.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [int]$Target = 1500,
    [int]$HardLimit = 2500,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
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

foreach ($lua in Find-ModLuas) {
    $lineCount = (Get-Content $lua.FullName | Measure-Object -Line).Lines
    $relPath = $lua.FullName.Substring($repoRoot.Length + 1)
    if (-not $Quiet) { Write-Host "  $relPath -- $lineCount lines" -ForegroundColor DarkGray }
    if ($lineCount -gt $HardLimit) {
        $overHard += [PSCustomObject]@{ Path = $relPath; Lines = $lineCount }
    } elseif ($lineCount -gt $Target) {
        $overTarget += [PSCustomObject]@{ Path = $relPath; Lines = $lineCount }
    }
}

# Report
Write-Host ""
if ($overTarget.Count -eq 0 -and $overHard.Count -eq 0) {
    Write-Host "[check_file_sizes] OK — all Lua files within target ($Target lines)." -ForegroundColor Green
    exit 0
}

if ($overTarget.Count -gt 0) {
    Write-Host "[check_file_sizes] WARNINGS — files over $Target-line target (split when natural boundary appears):" -ForegroundColor Yellow
    foreach ($f in $overTarget | Sort-Object -Property Lines -Descending) {
        Write-Host "  ! $($f.Path) — $($f.Lines) lines" -ForegroundColor Yellow
    }
}
if ($overHard.Count -gt 0) {
    Write-Host "[check_file_sizes] ERRORS — files over $HardLimit-line HARD limit (split required):" -ForegroundColor Red
    foreach ($f in $overHard | Sort-Object -Property Lines -Descending) {
        Write-Host "  X $($f.Path) — $($f.Lines) lines" -ForegroundColor Red
    }
    exit 2
}
exit 1
