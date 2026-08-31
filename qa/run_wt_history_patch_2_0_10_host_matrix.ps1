# Dual-host provenance gate for issue #1436's Patch 2.0.10 slice.
[CmdletBinding()]
param([string]$SourceRepo, [switch]$RequireSource, [switch]$Quiet)
$ErrorActionPreference = 'Stop'
$check = Join-Path $PSScriptRoot 'check_wt_history_patch_2_0_10_reproducibility.ps1'
$hosts = @(
    [pscustomobject]@{ Name = 'PowerShell 7'; Path = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source },
    [pscustomobject]@{ Name = 'Windows PowerShell 5.1'; Path = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
)
$failed = @()
foreach ($hostEntry in $hosts) {
    if (-not $hostEntry.Path -or -not (Test-Path -LiteralPath $hostEntry.Path -PathType Leaf)) {
        $failed += $hostEntry.Name
        continue
    }
    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $check)
    if ($Quiet) { $arguments += '-Quiet' }
    if ($SourceRepo) { $arguments += @('-SourceRepo', $SourceRepo) }
    if ($RequireSource) { $arguments += '-RequireSource' }
    $output = @(& $hostEntry.Path @arguments 2>&1)
    $code = $LASTEXITCODE
    if (-not $Quiet -or $code) { $output | ForEach-Object { Write-Host ([string]$_) } }
    if ($code) { $failed += $hostEntry.Name }
}
if ($failed.Count) {
    Write-Host "[wt-history-patch-2-0-10-host-matrix] FAILED -- $($failed -join ', ')" -ForegroundColor Red
    exit 2
}
if (-not $Quiet) {
    Write-Host '[wt-history-patch-2-0-10-host-matrix] OK -- exact provenance passed under both PowerShell hosts.' -ForegroundColor Green
}
exit 0
