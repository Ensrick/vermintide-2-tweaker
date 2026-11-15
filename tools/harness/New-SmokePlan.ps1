#requires -Version 7
<#
.SYNOPSIS
  Generates the full-set smoke plans from tools/mod-inventory.psd1 (WP-H-02 step 4) so they cannot drift.

.DESCRIPTION
  qa/runtime/plans/smoke-public.json: every inventory row with Public = $true.
  qa/runtime/plans/smoke-dev.json:    every row with Stream 'dev' or 'single'.
  qa/runtime/plans/sweep-public.json and sweep-dev.json (WP-H-03): the same mod sets, then the regression sweep
  case qa/runtime/_rig/sweep_regression.lua with "sweep": true, so run.ps1 writes sweep.json and fails on a FAIL row.
  A sweep loads one of a 'single' row and its '<Dir>_dev' twin: sweep-dev keeps the single row (weapon_tweaker), and
  sweep-<twin ModId without underscores>.json (sweep-wtdev.json) loads the twin (weapon_tweaker_dev) in its place.
  Each plan enables the Vermintide Mod Framework (Workshop folder 1369573612, VMF id "VMF") first, then the rows'
  WorkshopId values in inventory order, and lists "VMF" plus the rows' ModId values under expect_mods, which the
  smoke case qa/runtime/_rig/smoke_keep.lua asserts are loaded. Rows without a WorkshopId are skipped with a
  warning. Other dependencies: More Items Library is embedded in cosmetics_tweaker (_moreitemslibrary_embedded.lua),
  which both sets contain; no other Workshop dependency is recorded in the inventory.

  -Check compares the committed plans with a fresh generation and exits 2 on any difference (nothing written).
  Exit codes: 0 written or up to date, 2 drift or error.
#>
[CmdletBinding()]
param(
    [string] $Inventory = (Join-Path $PSScriptRoot '..\mod-inventory.psd1'),
    [string] $OutDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\plans'),
    [switch] $Check,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$vmfWorkshopId = '1369573612'
$inv = Import-PowerShellDataFile -LiteralPath $Inventory

function New-Plan([string] $name, [object[]] $rows, [string] $what, [switch] $Sweep) {
    $mods = [System.Collections.Generic.List[string]]::new(); $mods.Add($vmfWorkshopId)
    $expect = [System.Collections.Generic.List[string]]::new(); $expect.Add('VMF')
    foreach ($r in $rows) {
        if ([string]::IsNullOrWhiteSpace([string]$r.WorkshopId)) { Write-Warning "$($r.Dir): no WorkshopId, left out of $name"; continue }
        $mods.Add([string]$r.WorkshopId); $expect.Add([string]$r.ModId)
    }
    $plan = [ordered]@{
        name         = $name
        generated_by = "tools/harness/New-SmokePlan.ps1 from tools/mod-inventory.psd1 ($what); do not edit by hand"
        mods         = $mods.ToArray()
        expect_mods  = $expect.ToArray()
        timeout      = $(if ($Sweep) { 900 } else { 600 })
        cases        = @([ordered]@{ id = 'smoke-keep'; arena = 'keep'; file = '../_rig/smoke_keep.lua' })
    }
    if ($Sweep) {
        $plan.sweep = $true
        $plan.cases += [ordered]@{ id = 'sweep-regression'; arena = 'keep'; file = '../_rig/sweep_regression.lua' }
    }
    $plan
}

$devRows = @($inv.Mods | Where-Object { $_.Stream -in 'dev', 'single' })

# A 'single' row and its '<Dir>_dev' twin (weapon_tweaker and weapon_tweaker_dev) write the same game data and
# register the same chat command, so with both loaded the twin's suite never runs and their data collide
# (qa/runtime/reports/sweep-2026-11-15.md, cause A). A sweep loads one of them: sweep-dev keeps the single row, and
# each twin gets its own sweep-<ModId without underscores>.json with the twin in the single row's place.
$twins = @(foreach ($r in $devRows) {
        if ($r.Stream -ne 'single') { continue }
        $twin = @($devRows | Where-Object { $_.Stream -eq 'dev' -and $_.Dir -eq ($r.Dir + '_dev') })
        if ($twin.Count) { [pscustomobject]@{ Single = $r; Twin = $twin[0] } }
    })
$twinDirs = @($twins | ForEach-Object { $_.Twin.Dir })
$sweepDevRows = @($devRows | Where-Object { $twinDirs -notcontains $_.Dir })
$sweepDevWhat = "rows with Stream 'dev' or 'single'" + $(if ($twins.Count) { ', without ' + (($twins | ForEach-Object { "$($_.Twin.Dir) (its single twin $($_.Single.Dir) loads)" }) -join ', ') } else { '' })

$plans = [ordered]@{
    'smoke-public.json' = New-Plan 'smoke-public' @($inv.Mods | Where-Object { $_.Public -eq $true }) 'rows with Public = $true'
    'smoke-dev.json'    = New-Plan 'smoke-dev' $devRows "rows with Stream 'dev' or 'single'"
    'sweep-public.json' = New-Plan 'sweep-public' @($inv.Mods | Where-Object { $_.Public -eq $true }) 'rows with Public = $true' -Sweep
    'sweep-dev.json'    = New-Plan 'sweep-dev' $sweepDevRows $sweepDevWhat -Sweep
}
foreach ($t in $twins) {
    $name = 'sweep-' + ($t.Twin.ModId -replace '_', '')
    $rows = @($sweepDevRows | ForEach-Object { if ($_.Dir -eq $t.Single.Dir) { $t.Twin } else { $_ } })
    $plans["$name.json"] = New-Plan $name $rows "the sweep-dev rows with $($t.Twin.Dir) in place of its single twin $($t.Single.Dir)" -Sweep
}

$drift = 0
foreach ($file in $plans.Keys) {
    $text = (($plans[$file] | ConvertTo-Json -Depth 6) -replace "`r`n", "`n") + "`n"
    $path = Join-Path $OutDir $file
    if ($Check) {
        $current = if (Test-Path -LiteralPath $path -PathType Leaf) { [System.IO.File]::ReadAllText($path) -replace "`r`n", "`n" } else { $null }
        if ($current -cne $text) { $drift++; Write-Host "[smoke_plans] DRIFT -- $file differs from a fresh generation; run tools/harness/New-SmokePlan.ps1" -ForegroundColor Red }
        elseif (-not $Quiet) { Write-Host "[smoke_plans] OK -- $file is up to date" }
    }
    else {
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
        if (-not $Quiet) { Write-Host "[smoke_plans] wrote $file ($($plans[$file].mods.Count) mods)" }
    }
}
if ($drift) { exit 2 }
exit 0
