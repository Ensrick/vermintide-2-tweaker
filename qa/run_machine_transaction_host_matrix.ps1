# Run the offline machine-transaction fixtures under both supported hosts.
$ErrorActionPreference = 'Stop'
$check = Join-Path $PSScriptRoot 'check_machine_transaction_lease.ps1'
$hosts = @()
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
$windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
if ($pwsh) { $hosts += $pwsh.Source }
if ($windowsPowerShell) { $hosts += $windowsPowerShell.Source }
if ($hosts.Count -eq 0) { throw 'No PowerShell host found.' }
foreach ($hostEntry in @($hosts | Select-Object -Unique)) {
    Write-Host "[machine-transaction-host-matrix] $hostEntry" -ForegroundColor Cyan
    & $hostEntry -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $check -SelfTest
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Host '[machine-transaction-host-matrix] PASS' -ForegroundColor Green
