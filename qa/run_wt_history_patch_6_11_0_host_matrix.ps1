# Blocking dual-host provenance gate for issue #1436's Patch 6.11.0 Kruber
# Longbow and shared one-handed Hammer/Mace slices. Both supported PowerShell
# hosts independently validate all three source files, five template guards,
# and byte-exact catalog reproduction.

[CmdletBinding()]
param(
    [string]$SourceRepo,
    [switch]$RequireSource,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$checkPath = Join-Path $PSScriptRoot `
    'check_wt_history_patch_6_11_0_reproducibility.ps1'
if (-not (Test-Path -LiteralPath $checkPath -PathType Leaf)) {
    Write-Host "[wt-history-patch-6-11-0-host-matrix] ERROR -- missing $checkPath" -ForegroundColor Red
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
            Join-Path $env:SystemRoot `
                'System32\WindowsPowerShell\v1.0\powershell.exe'
        }
        else { $null }
    }
)

$failed = @()
foreach ($hostEntry in $hosts) {
    if ([string]::IsNullOrWhiteSpace($hostEntry.Path) -or
        -not (Test-Path -LiteralPath $hostEntry.Path -PathType Leaf)) {
        Write-Host ("  [FAIL] {0} host is unavailable" -f $hostEntry.Name) `
            -ForegroundColor Red
        $failed += $hostEntry.Name
        continue
    }
    if (-not $Quiet) {
        Write-Host ("=== {0}: Patch 6.11.0 history reproduction ===" -f `
            $hostEntry.Name) -ForegroundColor Cyan
    }
    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File',
        $checkPath)
    if ($SourceRepo) { $arguments += @('-SourceRepo', $SourceRepo) }
    if ($RequireSource) { $arguments += '-RequireSource' }
    if ($Quiet) { $arguments += '-Quiet' }
    & $hostEntry.Path @arguments
    $code = $LASTEXITCODE
    if ($code -eq 0) {
        if (-not $Quiet) {
            Write-Host ("  [PASS] {0}" -f $hostEntry.Name) `
                -ForegroundColor Green
        }
    }
    else {
        Write-Host ("  [FAIL] {0} (exit {1})" -f $hostEntry.Name, $code) `
            -ForegroundColor Red
        $failed += $hostEntry.Name
    }
}

if ($failed.Count -gt 0) {
    Write-Host ("[wt-history-patch-6-11-0-host-matrix] FAILED -- {0}" -f `
        ($failed -join ', ')) -ForegroundColor Red
    exit 2
}
if (-not $Quiet) {
    Write-Host '[wt-history-patch-6-11-0-host-matrix] OK -- Patch 6.11.0 provenance reproduces under both PowerShell hosts.' -ForegroundColor Green
}
exit 0
