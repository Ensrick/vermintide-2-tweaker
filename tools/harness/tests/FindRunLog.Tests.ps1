#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/Find-RunLog.ps1 (no game): the --default-console-log-path file, a folder of that
  name, and the 20-second fallback to the profile's console_logs folder. Exit codes: 0 pass, 2 failure.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
$finder = Join-Path (Split-Path $PSScriptRoot) 'Find-RunLog.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-findlog-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $run = Join-Path $root 'run'; $profileLogs = Join-Path $root 'profile\console_logs'
    New-Item -ItemType Directory -Force -Path $run, $profileLogs | Out-Null
    $switch = Join-Path $run 'console.log'
    $started = (Get-Date).AddSeconds(-1)

    $none = & $finder -SwitchPath $switch -ProfileLogDir $profileLogs -Started $started -Now $started.AddSeconds(5)
    Assert-True ($null -eq $none) 'nothing yet: no log'

    $old = Join-Path $profileLogs 'console-2026-01-01-00.00.00-old.log'
    Set-Content -LiteralPath $old -Value 'earlier run'
    (Get-Item -LiteralPath $old).LastWriteTime = $started.AddHours(-1)
    $profileLog = Join-Path $profileLogs 'console-2026-11-15-03.38.58-new.log'
    Set-Content -LiteralPath $profileLog -Value 'this run'

    $early = & $finder -SwitchPath $switch -ProfileLogDir $profileLogs -Started $started -Now $started.AddSeconds(5)
    Assert-True ($null -eq $early) 'before 20 s the profile log is not taken yet'
    $fallback = & $finder -SwitchPath $switch -ProfileLogDir $profileLogs -Started $started -Now $started.AddSeconds(21)
    Assert-True ($fallback -and $fallback.Source -eq 'profile-fallback' -and $fallback.Path -eq $profileLog) "after 20 s: the newest profile log of this run ($($fallback.Path))"
    $atEnd = & $finder -SwitchPath $switch -ProfileLogDir $profileLogs -Started $started -FallbackAfterSeconds 0
    Assert-True ($atEnd -and $atEnd.Source -eq 'profile-fallback') 'at collection (fallback 0) the profile log is taken at once'

    Set-Content -LiteralPath $switch -Value 'switch log'
    $file = & $finder -SwitchPath $switch -ProfileLogDir $profileLogs -Started $started -Now $started.AddSeconds(2)
    Assert-True ($file -and $file.Source -eq 'switch-file' -and $file.Path -eq (Resolve-Path -LiteralPath $switch).Path) 'the switch file wins as soon as it exists'

    Remove-Item -LiteralPath $switch
    New-Item -ItemType Directory -Path $switch | Out-Null
    $inDir = Join-Path $switch 'console-2026-11-15-03.38.58.log'
    Set-Content -LiteralPath $inDir -Value 'switch folder log'
    $dir = & $finder -SwitchPath $switch -ProfileLogDir $profileLogs -Started $started -Now $started.AddSeconds(2)
    Assert-True ($dir -and $dir.Source -eq 'switch-dir' -and $dir.Path -eq $inDir) 'a folder at the switch path: its newest log of this run'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($failures.Count) { Write-Host "[FindRunLog.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[FindRunLog.Tests] OK -- switch file, switch folder and 20 s profile fallback checked.'
exit 0
