# Blocking dual-host provenance gate for issue #1436's Patch 4.6 Hagbane
# slice. Both PowerShell hosts independently validate the complete six-file
# source ledger and source-selection adversaries. With source available (or
# required explicitly), both also perform byte-exact regeneration.

[CmdletBinding()]
param([string]$SourceRepo, [switch]$RequireSource, [switch]$Quiet)

$ErrorActionPreference = 'Stop'
$checkPath = Join-Path $PSScriptRoot 'check_wt_history_patch_4_6_reproducibility.ps1'

foreach ($requiredPath in @($checkPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        Write-Host "[wt-history-patch-4-6-host-matrix] ERROR -- missing $requiredPath" -ForegroundColor Red
        exit 2
    }
}

$resolvedSourceRepo = $null
if ($SourceRepo) {
    if (-not (Test-Path -LiteralPath $SourceRepo -PathType Container)) {
        Write-Host "[wt-history-patch-4-6-host-matrix] ERROR -- source repository unavailable: $SourceRepo" -ForegroundColor Red
        exit 2
    }
    $resolvedSourceRepo = (Resolve-Path -LiteralPath $SourceRepo).Path
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
$pinnedOnly = @()
foreach ($hostEntry in $hosts) {
    if ([string]::IsNullOrWhiteSpace($hostEntry.Path) -or
        -not (Test-Path -LiteralPath $hostEntry.Path -PathType Leaf)) {
        Write-Host ("  [FAIL] {0} host is unavailable" -f $hostEntry.Name) -ForegroundColor Red
        $failed += $hostEntry.Name
        continue
    }

    if (-not $Quiet) {
        Write-Host ("=== {0}: Patch 4.6 history reproduction ===" -f $hostEntry.Name) -ForegroundColor Cyan
    }

    $guardArguments = @('-NoLogo', '-NoProfile', '-NonInteractive',
        '-File', $checkPath, '-SelfTest')
    & $hostEntry.Path @guardArguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host ("  [FAIL] {0} no-fetch/no-lock restoration fixtures (exit {1})" -f
            $hostEntry.Name, $LASTEXITCODE) -ForegroundColor Red
        $failed += $hostEntry.Name
        continue
    }

    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $checkPath)
    if ($Quiet) { $arguments += '-Quiet' }
    if ($resolvedSourceRepo) { $arguments += @('-SourceRepo', $resolvedSourceRepo) }
    if ($RequireSource) { $arguments += '-RequireSource' }
    $checkOutput = @(& $hostEntry.Path @arguments 2>&1)
    $code = $LASTEXITCODE
    $checkText = ($checkOutput | ForEach-Object { [string]$_ }) -join "`n"
    $skipped = $checkText.IndexOf('SKIP', [StringComparison]::Ordinal) -ge 0
    if (-not $Quiet -or $code -ne 0) {
        $checkOutput | ForEach-Object { Write-Host ([string]$_) }
    }
    if ($RequireSource -and $skipped) {
        Write-Host ("  [FAIL] {0} strict source proof reported SKIP" -f
            $hostEntry.Name) -ForegroundColor Red
        $failed += $hostEntry.Name
        continue
    }
    if ($code -eq 0) {
        if ($skipped) { $pinnedOnly += $hostEntry.Name }
        if (-not $Quiet) {
            $mode = if ($skipped) { 'pinned-only' } else { 'source-regenerated' }
            Write-Host ("  [PASS] {0} ({1})" -f $hostEntry.Name, $mode) -ForegroundColor Green
        }
    } else {
        Write-Host ("  [FAIL] {0} (exit {1})" -f $hostEntry.Name, $code) -ForegroundColor Red
        $failed += $hostEntry.Name
    }
}

if ($failed.Count -gt 0) {
    Write-Host ("[wt-history-patch-4-6-host-matrix] FAILED -- {0}" -f ($failed -join ', ')) -ForegroundColor Red
    exit 2
}

if (-not $Quiet -and $pinnedOnly.Count -gt 0) {
    Write-Host ("[wt-history-patch-4-6-host-matrix] OK -- dual-host pinned validation passed; source regeneration visibly skipped for {0}. Use -RequireSource for the strict release proof." -f ($pinnedOnly -join ', ')) -ForegroundColor Yellow
}
elseif (-not $Quiet) {
    Write-Host '[wt-history-patch-4-6-host-matrix] OK -- Patch 4.6 provenance reproduces under both PowerShell hosts.' -ForegroundColor Green
}
exit 0
