#requires -Version 7
<#
.SYNOPSIS
  Applies a rig plan's "modset" (WP-H-08): returns the plan with its mods and expect_mods filled from
  tools/harness/modsets.psd1.

.DESCRIPTION
  run.ps1 and New-RigProfile.ps1 both read a plan through this, so they agree on its mod list.
  "modset": "<name>" sets mods to the set's Workshop ids (VMF first), followed by any plan "mods" the set does not
  hold (in plan order), and sets expect_mods to the set's VMF mod ids, followed by the plan's own expect_mods
  entries the set does not list. A plan without modset is returned unchanged. An unknown set name throws.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [object] $Plan,
    [string] $ModSetsFile = (Join-Path $PSScriptRoot 'modsets.psd1')
)
$ErrorActionPreference = 'Stop'
if (-not $Plan.PSObject.Properties['modset'] -or [string]::IsNullOrWhiteSpace([string]$Plan.modset)) { return $Plan }

$name = [string]$Plan.modset
$sets = (Import-PowerShellDataFile -LiteralPath $ModSetsFile).Sets
if (-not $sets.ContainsKey($name)) {
    throw "plan modset '$name' is not in $ModSetsFile (sets: $((@($sets.Keys) | Sort-Object) -join ', '))"
}
$set = $sets[$name]

$mods = [System.Collections.Generic.List[string]]::new()
foreach ($id in @($set.WorkshopIds) + @($Plan.mods | Where-Object { $_ })) { if (-not $mods.Contains([string]$id)) { $mods.Add([string]$id) } }
$expect = [System.Collections.Generic.List[string]]::new()
$own = if ($Plan.PSObject.Properties['expect_mods']) { @($Plan.expect_mods | Where-Object { $_ }) } else { @() }
foreach ($id in @($set.ModIds) + $own) { if (-not $expect.Contains([string]$id)) { $expect.Add([string]$id) } }

$Plan | Add-Member -NotePropertyName mods -NotePropertyValue $mods.ToArray() -Force
$Plan | Add-Member -NotePropertyName expect_mods -NotePropertyValue $expect.ToArray() -Force
$Plan
