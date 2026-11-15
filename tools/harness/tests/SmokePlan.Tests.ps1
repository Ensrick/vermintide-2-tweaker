#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/New-SmokePlan.ps1: the committed smoke-public.json and smoke-dev.json equal a
  fresh generation from tools/mod-inventory.psd1, hold the right rows, and a changed copy is reported as drift.
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
$harness = Split-Path $PSScriptRoot
$generator = Join-Path $harness 'New-SmokePlan.ps1'
$plansDir = Join-Path $harness '..\..\qa\runtime\plans'
$inv = Import-PowerShellDataFile -LiteralPath (Join-Path $harness '..\mod-inventory.psd1')
$pwsh = (Get-Process -Id $PID).Path

$null = & $pwsh -NoProfile -File $generator -Check -Quiet 2>&1
Assert-True ($LASTEXITCODE -eq 0) "committed plans equal a fresh generation (exit $LASTEXITCODE)"

foreach ($case in @(
        @{ File = 'smoke-public.json'; Rows = @($inv.Mods | Where-Object { $_.Public -eq $true }) },
        @{ File = 'smoke-dev.json'; Rows = @($inv.Mods | Where-Object { $_.Stream -in 'dev', 'single' }) })) {
    $plan = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath (Join-Path $plansDir $case.File)).Path) | ConvertFrom-Json
    $ids = @($case.Rows | Where-Object { $_.WorkshopId } | ForEach-Object { [string]$_.WorkshopId })
    Assert-True ($plan.mods[0] -eq '1369573612' -and $plan.expect_mods[0] -eq 'VMF') "$($case.File): VMF first"
    Assert-True ((@($plan.mods | Select-Object -Skip 1) -join ',') -eq ($ids -join ',')) "$($case.File): every row's Workshop id in inventory order ($($ids.Count))"
    Assert-True ($plan.expect_mods.Count -eq $plan.mods.Count) "$($case.File): one expect_mods id per enabled mod"
    Assert-True ($plan.cases.Count -eq 1 -and $plan.cases[0].file -eq '../_rig/smoke_keep.lua') "$($case.File): runs the smoke case"
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-smokeplan-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $null = & $pwsh -NoProfile -File $generator -OutDir $tmp -Quiet 2>&1
    Assert-True ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $tmp 'smoke-dev.json'))) 'generation into another folder works'
    $edited = (Get-Content -LiteralPath (Join-Path $tmp 'smoke-dev.json') -Raw) -replace '"timeout": 600', '"timeout": 900'
    [System.IO.File]::WriteAllText((Join-Path $tmp 'smoke-dev.json'), $edited)
    $out = & $pwsh -NoProfile -File $generator -OutDir $tmp -Check 2>&1
    Assert-True ($LASTEXITCODE -eq 2 -and @($out | Where-Object { "$_" -match 'DRIFT -- smoke-dev.json' }).Count -eq 1) 'a hand edit is reported as drift (exit 2)'
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force }

if ($failures.Count) { Write-Host "[SmokePlan.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[SmokePlan.Tests] OK -- generated smoke plans match the inventory and drift is caught.'
exit 0
