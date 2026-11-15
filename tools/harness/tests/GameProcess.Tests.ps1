#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/GameProcess.cs (no game): starts cmd.exe on a private desktop with two
  child-only environment variables and checks exit code, windows and the parent environment.

.DESCRIPTION
  The child runs  cmd.exe /c <check both variables> exit 7 , so exit code 7 proves the child saw both
  child-only variables. Asserts: exit code 7, the desktop name is a private Vt2Rig-* desktop, no window of the
  job reached the user's desktop while it ran, and the parent's process and user environment are unchanged.
  Exit codes: 0 pass, 2 failure.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
function Get-EnvSnapshot {
    $map = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($e in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) { $map[[string]$e.Key] = [string]$e.Value }
    ($map.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
}

$source = Join-Path (Split-Path $PSScriptRoot) 'GameProcess.cs'
if (-not ('Vt2GameProcess' -as [type])) { Add-Type -Path $source }

$names = 'VT2_RIG_TEST_ALPHA', 'VT2_RIG_TEST_BETA'
foreach ($n in $names) {
    if ([System.Environment]::GetEnvironmentVariable($n)) { Write-Host "[GameProcess.Tests] ERROR -- $n is already set in the parent." -ForegroundColor Red; exit 2 }
}
$userBefore = @{}; foreach ($n in $names) { $userBefore[$n] = [System.Environment]::GetEnvironmentVariable($n, 'User') }
$parentBefore = Get-EnvSnapshot

$cmd = Join-Path ([System.Environment]::SystemDirectory) 'cmd.exe'
$arguments = '/c if "%VT2_RIG_TEST_ALPHA%"=="alpha" if "%VT2_RIG_TEST_BETA%"=="beta" exit 7'
$childEnv = @{ VT2_RIG_TEST_ALPHA = 'alpha'; VT2_RIG_TEST_BETA = 'beta' }
$windows = [System.Collections.Generic.List[string]]::new()
$proc = $null
try {
    $proc = [Vt2GameProcess]::Start($cmd, $arguments, ([System.Environment]::SystemDirectory), $childEnv, $true)
    Assert-True ($proc.DesktopName -like 'Vt2Rig-*') "child runs on a private desktop ($($proc.DesktopName))"
    $deadline = (Get-Date).AddSeconds(30)
    while (-not $proc.WaitForExit(50)) {
        foreach ($w in $proc.WindowsOnUserDesktop()) { $windows.Add($w) }
        if ((Get-Date) -ge $deadline) { $proc.Kill(); break }
    }
    foreach ($w in $proc.WindowsOnUserDesktop()) { $windows.Add($w) }
    $code = $proc.ExitCode
    Assert-True ($code -eq 7) "exit code is 7, so the child saw both child-only variables (got $code)"
    Assert-True ($windows.Count -eq 0) "no window on the user desktop ($($windows -join '; '))"
}
finally {
    if ($proc) { $proc.Dispose() }
}

Assert-True ((Get-EnvSnapshot) -ceq $parentBefore) 'parent process environment unchanged'
foreach ($n in $names) {
    Assert-True ($null -eq [System.Environment]::GetEnvironmentVariable($n)) "$n absent from the parent"
    Assert-True ([System.Environment]::GetEnvironmentVariable($n, 'User') -eq $userBefore[$n]) "$n not written to the user environment"
}

if ($failures.Count) { Write-Host "[GameProcess.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[GameProcess.Tests] OK -- private desktop, child-only environment, exit code and window checks passed.'
exit 0
