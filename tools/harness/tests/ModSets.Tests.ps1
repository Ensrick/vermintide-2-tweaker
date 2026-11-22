#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/New-ModSets.ps1 (WP-H-08): the committed modsets.psd1 equals a fresh generation from
  tools/mod-inventory.psd1, the named sets hold the right rows, and a hand edit is reported as drift.
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
$generator = Join-Path $harness 'New-ModSets.ps1'
$inv = Import-PowerShellDataFile -LiteralPath (Join-Path $harness '..\mod-inventory.psd1')
$pwsh = (Get-Process -Id $PID).Path

$null = & $pwsh -NoProfile -File $generator -Check -Quiet 2>&1
Assert-True ($LASTEXITCODE -eq 0) "committed modsets.psd1 equals a fresh generation (exit $LASTEXITCODE)"

$sets = (Import-PowerShellDataFile -LiteralPath (Join-Path $harness 'modsets.psd1')).Sets
foreach ($name in $sets.Keys) {
    $s = $sets[$name]
    Assert-True ($s.WorkshopIds[0] -eq '1369573612' -and $s.ModIds[0] -eq 'VMF' -and $s.WorkshopIds.Count -eq $s.ModIds.Count) "${name}: VMF first, one mod id per Workshop id"
}
$byDir = @{}; foreach ($r in $inv.Mods) { $byDir[$r.Dir] = $r }
$publicIds = @($inv.Mods | Where-Object { $_.Public -eq $true } | ForEach-Object { [string]$_.WorkshopId })
Assert-True ((@($sets['public-all'].WorkshopIds | Select-Object -Skip 1) -join ',') -eq ($publicIds -join ',')) 'public-all: every Public row in inventory order'
foreach ($name in 'dev-all', 'dev-all-wtdev', 'no-mp') {
    Assert-True (-not ($sets[$name].ModIds -contains 'wt' -and $sets[$name].ModIds -contains 'wt_dev')) "${name}: not both Weapon Tweaker streams"
}
Assert-True ($sets['dev-all'].ModIds -contains 'wt' -and $sets['dev-all-wtdev'].ModIds -contains 'wt_dev') 'dev-all loads wt, dev-all-wtdev loads wt_dev'
Assert-True ((@($sets['dev-all'].ModIds | Where-Object { $_ -ne 'wt' }) -join ',') -eq (@($sets['dev-all-wtdev'].ModIds | Where-Object { $_ -ne 'wt_dev' }) -join ',')) 'the two dev sets differ only in the Weapon Tweaker stream'
Assert-True ($sets['no-mp'].ModIds -notcontains 'mp' -and $sets['no-mp'].ModIds -contains 'cosmetics_tweaker') 'no-mp: no Modded Progression, cosmetics_tweaker (More Items Library) kept'
Assert-True ((@($sets['dev-all'].ModIds | Where-Object { $_ -ne 'mp' }) -join ',') -eq ($sets['no-mp'].ModIds -join ',')) 'no-mp is dev-all without mp'
foreach ($dir in 'character_weapon_variants', 'weapons_of_chaos', 'crafting_in_modded', 'crafting_in_modded_dev') {
    $ids = @($sets[$dir].ModIds)
    Assert-True ($ids.Count -eq 3 -and $ids[1] -eq 'cosmetics_tweaker' -and $ids[2] -eq $byDir[$dir].ModId) "${dir}: VMF, cosmetics_tweaker (More Items Library), then the mod"
}
foreach ($dir in 'general_tweaker_dev', 'modded_progression', 'cosmetics_tweaker') {
    Assert-True ((@($sets[$dir].ModIds) -join ',') -eq ('VMF,' + $byDir[$dir].ModId)) "${dir}: the mod alone"
}
Assert-True (@($inv.Mods | Where-Object { -not $sets.ContainsKey($_.Dir) }).Count -eq 0) 'one set per inventory row'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-modsets-tests-' + [guid]::NewGuid().ToString('N') + '.psd1')
try {
    $null = & $pwsh -NoProfile -File $generator -OutFile $tmp -Quiet 2>&1
    $edited = [System.IO.File]::ReadAllText($tmp) -replace "'3730422873', ", ''
    [System.IO.File]::WriteAllText($tmp, $edited)
    $out = & $pwsh -NoProfile -File $generator -OutFile $tmp -Check 2>&1
    Assert-True ($LASTEXITCODE -eq 2 -and @($out | Where-Object { "$_" -match 'DRIFT' }).Count -eq 1) 'a hand edit is reported as drift (exit 2)'
}
finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }

if ($failures.Count) { Write-Host "[ModSets.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[ModSets.Tests] OK -- generated mod sets match the inventory and drift is caught.'
exit 0
