#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/Invoke-UgcTool.ps1 with a fake ugc_tool (a batch file in a test-owned temporary
  folder; nothing is published): the modding-EULA prompt is answered with y, an unanswered prompt fails like the
  real tool, and the published id comes from item.cfg or the signed "publisher_id:" line. Exit codes: 0 pass,
  2 failure.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
$invoke = Join-Path (Split-Path $PSScriptRoot) 'Invoke-UgcTool.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-ugctool-tests-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    # Fake tool: asks the EULA question, reads one answer from stdin, prints a signed publisher id when agreed.
    $fake = Join-Path $root 'fake_ugc_tool.cmd'
    Set-Content -LiteralPath $fake -Encoding ascii -Value @(
        '@echo off',
        'echo Vermintide 2 End User License Agreement',
        'echo Do you agree? (y/n)',
        'set answer=',
        'set /p answer=',
        'if /i "%answer%"=="y" (',
        '  echo publisher_id: -454665885',
        '  exit /b 0',
        ')',
        'echo You did not agree to the EULA',
        'exit /b 1'
    )
    $cfg = Join-Path $root 'item.cfg'
    Set-Content -LiteralPath $cfg -Value 'title = "fixture"; visibility = "private";'

    $r = & $invoke -UgcTool $fake -Config $cfg -WorkingDirectory $root 6>$null
    Assert-True ($r.ExitCode -eq 0) "the prompt is answered and the tool exits 0 (got $($r.ExitCode))"
    Assert-True ($r.Answered) 'the EULA prompt was seen and answered'
    Assert-True ($r.PublishedId -eq '3840301411') "the signed publisher_id is read as unsigned (got $($r.PublishedId))"

    Add-Content -LiteralPath $cfg -Value 'published_id = 1234567890L;'
    $r2 = & $invoke -UgcTool $fake -Config $cfg -WorkingDirectory $root 6>$null
    Assert-True ($r2.PublishedId -eq '1234567890') "published_id in item.cfg wins (got $($r2.PublishedId))"

    # Same tool without the prompt text: nothing is answered, the tool sees no y and fails like the real one.
    $silent = Join-Path $root 'silent_ugc_tool.cmd'
    Set-Content -LiteralPath $silent -Encoding ascii -Value @(
        '@echo off',
        'echo some other question',
        'set answer=',
        'set /p answer=',
        'if /i "%answer%"=="y" exit /b 0',
        'echo You did not agree to the EULA',
        'exit /b 1'
    )
    $job = Start-ThreadJob -ScriptBlock { param($i, $t, $c, $w) & $i -UgcTool $t -Config $c -WorkingDirectory $w -TimeoutSeconds 5 6>$null } -ArgumentList $invoke, $silent, $cfg, $root
    $null = Wait-Job $job -Timeout 30
    $r3 = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force
    Assert-True ($null -eq $r3 -or -not $r3.Answered) 'no prompt text, no answer'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($failures.Count) { Write-Host "[UgcTool.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[UgcTool.Tests] OK -- EULA answered, unsigned publisher id, item.cfg id preferred.'
exit 0
