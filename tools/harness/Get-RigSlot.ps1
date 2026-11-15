#requires -Version 7
<#
.SYNOPSIS
  Resolves one rig slot (WP-H-07) from tools/harness/slots.psd1 and refuses anything that is not a rig slot.

.DESCRIPTION
  Throws when the slot number is not listed, its Id is still empty, the Id is not a Workshop number, or the Id is
  a real mod's Workshop id (tools/mod-inventory.psd1) or the rig bootstrap (3839345856). Nothing is written.

.OUTPUTS
  [pscustomobject] Slot, Id, Title, Dir (<workshop>\<Id>; may not exist yet).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [int] $Slot,
    [Parameter(Mandatory)] [string] $Workshop,
    [string] $SlotsFile = (Join-Path $PSScriptRoot 'slots.psd1'),
    [string] $Inventory = (Join-Path $PSScriptRoot '..\mod-inventory.psd1'),
    [string] $BootstrapId = '3839345856'
)
$ErrorActionPreference = 'Stop'
$table = Import-PowerShellDataFile -LiteralPath $SlotsFile
$row = @($table.Slots | Where-Object { [int]$_.Slot -eq $Slot })
if ($row.Count -ne 1) { throw "slot $Slot is not listed in $SlotsFile" }
$id = [string]$row[0].Id
if (-not $id) { throw "slot $Slot has no Workshop id yet (create it with tools/harness/New-RigSlotItems.ps1)" }
if ($id -notmatch '^\d+$') { throw "slot $Slot id is not a Workshop number: $id" }
$real = @((Import-PowerShellDataFile -LiteralPath $Inventory).Mods | ForEach-Object { [string]$_.WorkshopId })
if ($real -contains $id) { throw "slot $Slot id $id is a real mod's Workshop id; refusing" }
if ($id -eq $BootstrapId) { throw "slot $Slot id $id is the rig bootstrap; refusing" }
$ids = @($table.Slots | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
if (@($ids | Where-Object { $_ -eq $id }).Count -ne 1) { throw "slot id $id is listed more than once in $SlotsFile" }
[pscustomobject]@{ Slot = $Slot; Id = $id; Title = [string]$row[0].Title; Dir = (Join-Path $Workshop $id) }
