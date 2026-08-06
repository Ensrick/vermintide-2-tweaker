# run_selftests.ps1 - runs the -SelfTest of every self-test-capable script.
#
# WHY: 9+ qa checks and tools/ship/ship.ps1 carry a `-SelfTest` switch (pure,
# offline fixture tests of their parsing/decision logic), but until 2026-07-05
# NOTHING ran them automatically - a regression in a check's heuristics could
# ship silently and the check would keep "passing" while scanning garbage.
# This runner is the repo's unit-test entry point: wired into run_all.ps1
# (full pass, not -Quick) and CI (.github/workflows/qa.yml).
#
# DISCOVERY: any qa/check_*.ps1 whose param block declares `[switch]$SelfTest`
# is picked up automatically - a new check with a self-test needs no wiring
# here. Out-of-tree release/GitHub policy tools are added explicitly.
#
# Self-tests are OFFLINE by convention (no gh/network) so this runner is safe
# in CI and never flakes on connectivity.
#
# Exit codes (run_all Standard policy: >=2 blocks):
#   0 - every self-test passed
#   2 - one or more self-tests FAILED (a QA-tooling regression is genuine
#       breakage: the gate must not trust a broken check) or failed to run.

[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repoRoot = Split-Path $here -Parent

Write-Host "=== run_selftests ===" -ForegroundColor Cyan

# Auto-discover qa checks with a -SelfTest switch, plus known out-of-tree scripts.
$targets = @(
    Get-ChildItem (Join-Path $here 'check_*.ps1') -File `
        | Where-Object { Select-String -Path $_.FullName -Pattern '\[switch\]\$SelfTest' -Quiet } `
        | ForEach-Object { $_.FullName }
)
$shipPs1 = Join-Path $repoRoot 'tools\ship\ship.ps1'
if (Test-Path $shipPs1) { $targets += $shipPs1 }
$claimPs1 = Join-Path $repoRoot 'tools\ship\claim.ps1'
if (Test-Path $claimPs1) { $targets += $claimPs1 }
$refreshCardsPs1 = Join-Path $repoRoot 'tools\ship\refresh-cards.ps1'
if (Test-Path $refreshCardsPs1) { $targets += $refreshCardsPs1 }
$protectMasterPs1 = Join-Path $repoRoot 'tools\github\protect-master.ps1'
if (Test-Path $protectMasterPs1) { $targets += $protectMasterPs1 }
$openIssueAuditPs1 = Join-Path $repoRoot 'tools\github\audit-open-issues.ps1'
if (Test-Path $openIssueAuditPs1) { $targets += $openIssueAuditPs1 }
$branchCensusPs1 = Join-Path $repoRoot 'tools\github\branch-reconciliation-census.ps1'
if (Test-Path $branchCensusPs1) { $targets += $branchCensusPs1 }
$worktreeLifecyclePs1 = Join-Path $repoRoot 'tools\worktrees\worktree.ps1'
if (Test-Path $worktreeLifecyclePs1) { $targets += $worktreeLifecyclePs1 }
$promotionStatusPs1 = Join-Path $repoRoot 'tools\promote\promotion-status.ps1'
if (Test-Path $promotionStatusPs1) { $targets += $promotionStatusPs1 }

$failed = @()
foreach ($t in $targets) {
    $name = Split-Path $t -Leaf
    $out = $null
    try {
        # Capture ALL streams incl. Information (Write-Host) via *>&1 - plain
        # 2>&1 lets Write-Host leak to the console and the pass gets noisy.
        # Replayed only on failure. No Select-Object in the pipeline
        # (pipeline-stop kills child scripts - memory:
        # ps_select_first_kills_ship_pipeline).
        $out = & $t -SelfTest *>&1
        $code = $LASTEXITCODE
    } catch {
        $out = @("CRASH: $_")
        $code = 99
    }
    if ($code -eq 0) {
        Write-Host ("  [PASS] {0}" -f $name) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0} (exit {1})" -f $name, $code) -ForegroundColor Red
        if ($out) { $out | ForEach-Object { Write-Host ("      {0}" -f $_) -ForegroundColor DarkGray } }
        $failed += $name
    }
}

Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host ("[run_selftests] OK -- all {0} self-tests passed." -f $targets.Count) -ForegroundColor Green
    exit 0
}
Write-Host ("[run_selftests] FAILED -- {0}/{1} self-test(s) regressed: {2}" -f $failed.Count, $targets.Count, ($failed -join ', ')) -ForegroundColor Red
exit 2
