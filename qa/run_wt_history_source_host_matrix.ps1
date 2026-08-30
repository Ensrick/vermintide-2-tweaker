# Blocking dual-host owner for the generic weapon-history source guards.
# Patch-specific matrices own only their patch evidence; this matrix runs the
# shared remote-freshness and incomplete-checkout adversaries exactly once per
# supported PowerShell host during full QA (issue #540).

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$freshnessPath = Join-Path $PSScriptRoot 'check_wt_history_source_freshness.ps1'
$sourceCheckoutPath = Join-Path $PSScriptRoot 'check_wt_history_source_checkout.ps1'

foreach ($requiredPath in @($freshnessPath, $sourceCheckoutPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        Write-Host "[wt-history-source-host-matrix] ERROR -- missing $requiredPath" -ForegroundColor Red
        exit 2
    }
}

$hosts = @(
    [pscustomobject]@{
        Name = 'PowerShell 7'
        Path = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    }
    [pscustomobject]@{
        Name = 'Windows PowerShell 5.1'
        Path = if ($env:SystemRoot) {
            Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        } else {
            $null
        }
    }
)

$failed = @()
foreach ($hostEntry in $hosts) {
    if ([string]::IsNullOrWhiteSpace($hostEntry.Path) -or
        -not (Test-Path -LiteralPath $hostEntry.Path -PathType Leaf)) {
        Write-Host ("  [FAIL] {0} host is unavailable" -f $hostEntry.Name) -ForegroundColor Red
        $failed += $hostEntry.Name
        continue
    }

    if (-not $Quiet) {
        Write-Host ("=== {0}: shared weapon-history source guards ===" -f
            $hostEntry.Name) -ForegroundColor Cyan
    }

    $freshnessArguments = @('-NoLogo', '-NoProfile', '-NonInteractive',
        '-File', $freshnessPath, '-SelfTest')
    & $hostEntry.Path @freshnessArguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("  [FAIL] {0} freshness fixtures (exit {1})" -f
            $hostEntry.Name, $LASTEXITCODE) -ForegroundColor Red
        $failed += $hostEntry.Name
        continue
    }

    $sourceCheckoutArguments = @('-NoLogo', '-NoProfile', '-NonInteractive',
        '-File', $sourceCheckoutPath, '-SelfTest')
    & $hostEntry.Path @sourceCheckoutArguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("  [FAIL] {0} source-checkout fixtures (exit {1})" -f
            $hostEntry.Name, $LASTEXITCODE) -ForegroundColor Red
        $failed += $hostEntry.Name
        continue
    }

    if (-not $Quiet) {
        Write-Host ("  [PASS] {0}" -f $hostEntry.Name) -ForegroundColor Green
    }
}

if ($failed.Count -gt 0) {
    Write-Host ("[wt-history-source-host-matrix] FAILED -- {0}" -f
        ($failed -join ', ')) -ForegroundColor Red
    exit 2
}

if (-not $Quiet) {
    Write-Host '[wt-history-source-host-matrix] OK -- generic source guards pass once under both PowerShell hosts.' -ForegroundColor Green
}
exit 0
