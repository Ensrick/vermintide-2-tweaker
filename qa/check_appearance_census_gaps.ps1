# check_appearance_census_gaps.ps1
#
# Drift gate for docs/generated/APPEARANCE_CENSUS_GAPS.generated.md (issue
# 1157). The report is the enumerated issue-660 backlog, expanded from the
# per-mod appearance censuses; a census edited without regenerating the report
# turns the committed backlog into a stale lie, which is the exact failure the
# censuses exist to prevent.
#
# This check owns no logic of its own: it delegates to the generator's -Check
# mode, which regenerates in memory from tools/shared_lib/
# _lib_appearance_descriptor.lua (M.expand_matrix) and compares. Same pattern
# as check_shared_lib_drift.ps1 delegating to sync-shared-libs.ps1.
#
# Exit codes: 0 = report matches the censuses, 2 = drift or a broken generator.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$generator = Join-Path $repoRoot "tools\gen-appearance-gaps\gen-appearance-gaps.ps1"

if (-not (Test-Path -LiteralPath $generator -PathType Leaf)) {
    Write-Host "[check_appearance_census_gaps] ERROR: missing generator: $generator" -ForegroundColor Red
    exit 2
}

if ($SelfTest) {
    & $generator -RepoRoot $repoRoot -SelfTest -Quiet:$Quiet
    exit $LASTEXITCODE
}

& $generator -RepoRoot $repoRoot -Check -Quiet:$Quiet
exit $LASTEXITCODE
