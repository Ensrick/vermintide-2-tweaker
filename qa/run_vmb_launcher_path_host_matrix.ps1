# run_vmb_launcher_path_host_matrix.ps1
#
# Blocking host-compatibility gate for issue #683. The ship/release tooling must
# remain valid in both PowerShell hosts used by the repository: PowerShell 7
# (the main CI gate) and Windows PowerShell 5.1 (the release launcher host).

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$checkPath = Join-Path $PSScriptRoot 'check_vmb_launcher_path.ps1'

if (-not (Test-Path -LiteralPath $checkPath -PathType Leaf)) {
    Write-Host "[vmb-launcher-host-matrix] ERROR -- missing $checkPath" -ForegroundColor Red
    exit 2
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
        Write-Host ("=== {0}: check_vmb_launcher_path ===" -f $hostEntry.Name) -ForegroundColor Cyan
    }

    & $hostEntry.Path -NoLogo -NoProfile -NonInteractive -File $checkPath -SelfTest
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        Write-Host ("  [PASS] {0}" -f $hostEntry.Name) -ForegroundColor Green
    } else {
        Write-Host ("  [FAIL] {0} (exit {1})" -f $hostEntry.Name, $code) -ForegroundColor Red
        $failed += $hostEntry.Name
    }
}

if ($failed.Count -gt 0) {
    Write-Host ("[vmb-launcher-host-matrix] FAILED -- {0}" -f ($failed -join ', ')) -ForegroundColor Red
    exit 2
}

Write-Host '[vmb-launcher-host-matrix] OK -- launcher provenance contracts pass in both PowerShell hosts.' -ForegroundColor Green
exit 0
