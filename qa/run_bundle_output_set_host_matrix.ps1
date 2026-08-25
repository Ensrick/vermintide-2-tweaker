# Blocking dual-host gate for the canonical bundle-output set primitive.
# ASCII-only for Windows PowerShell 5.1 parsing.

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$checks = @(
    [pscustomobject]@{ Name = 'check_bundle_output_set'; Path = (Join-Path $PSScriptRoot 'check_bundle_output_set.ps1') }
    [pscustomobject]@{ Name = 'check_build_output_normalization'; Path = (Join-Path $PSScriptRoot 'check_build_output_normalization.ps1') }
    [pscustomobject]@{ Name = 'check_build_receipts'; Path = (Join-Path $PSScriptRoot 'check_build_receipts.ps1') }
)
foreach ($check in $checks) {
    if (-not (Test-Path -LiteralPath $check.Path -PathType Leaf)) {
        Write-Host "[bundle-output-set-host-matrix] ERROR -- missing $($check.Path)" -ForegroundColor Red
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

    foreach ($check in $checks) {
        if (-not $Quiet) {
            Write-Host ("=== {0}: {1} ===" -f $hostEntry.Name, $check.Name) -ForegroundColor Cyan
        }
        $hostArguments = @('-NoLogo', '-NoProfile', '-NonInteractive')
        if ([System.IO.Path]::GetFileName($hostEntry.Path) -ieq 'powershell.exe') {
            $hostArguments += @('-ExecutionPolicy', 'Bypass')
        }
        $hostArguments += @('-File', $check.Path, '-SelfTest')

        & $hostEntry.Path @hostArguments
        $code = $LASTEXITCODE
        $caseName = "$($hostEntry.Name)/$($check.Name)"
        if ($code -eq 0) {
            Write-Host ("  [PASS] {0}" -f $caseName) -ForegroundColor Green
        } else {
            Write-Host ("  [FAIL] {0} (exit {1})" -f $caseName, $code) -ForegroundColor Red
            $failed += $caseName
        }
    }
}

if ($failed.Count -gt 0) {
    Write-Host ("[bundle-output-set-host-matrix] FAILED -- {0}" -f ($failed -join ', ')) -ForegroundColor Red
    exit 2
}

Write-Host '[bundle-output-set-host-matrix] OK -- output-set, normalization, and receipt contracts pass in both PowerShell hosts.' -ForegroundColor Green
exit 0
