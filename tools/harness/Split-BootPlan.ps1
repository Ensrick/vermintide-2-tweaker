#requires -Version 7
<#
.SYNOPSIS
  Splits a rig plan with "boots" into one single-boot plan per boot (WP-H-08: several boots on one kept profile).

.DESCRIPTION
  A plan's "boots" is a list of objects. Boot i's plan is the plan's own fields (everything but "boots"), with the
  boot's fields on top: a boot gives its "cases" (required) and may give its own "mods", "modset", "expect_mods",
  "options", "settings", "arenas", "timeout" or "sweep" (a different mod set per boot); "modset": "" drops the plan's
  set for that boot. Its name is "<name>-boot<i>". Case file paths are rewritten relative to the boot plan's folder,
  so New-RigProfile.ps1 finds them as before; a case file on another drive than the run folder is refused.

  Writes <OutDir>\boot-<i>\boot.plan.json and returns one object per boot: Index, Dir, PlanFile, Name.
  run.ps1 runs boot 1 on a fresh copy of the owner's profile and every later boot on the profile the boot before
  it left (New-RigProfile.ps1 -KeepProfile).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PlanPath,
    [Parameter(Mandatory)] [string] $OutDir,
    [string] $Name = ''
)
$ErrorActionPreference = 'Stop'
$PlanPath = (Resolve-Path -LiteralPath $PlanPath).Path
$planDir = Split-Path $PlanPath
$raw = [System.IO.File]::ReadAllText($PlanPath) | ConvertFrom-Json
if (-not $raw.PSObject.Properties['boots'] -or @($raw.boots).Count -lt 1) { throw "plan $PlanPath has no boots" }
if ($raw.PSObject.Properties['cases'] -and @($raw.cases).Count) { throw 'a plan with boots lists its cases under each boot, not at the top' }
if (-not $Name) { $Name = [string]$raw.name }

$boots = @($raw.boots)
$out = @()
for ($i = 0; $i -lt $boots.Count; $i++) {
    $boot = $boots[$i]
    $n = $i + 1
    if (-not $boot.PSObject.Properties['cases'] -or @($boot.cases).Count -lt 1) { throw "boot $n has no cases" }
    $dir = Join-Path $OutDir "boot-$n"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $plan = [ordered]@{}
    foreach ($p in $raw.PSObject.Properties) { if ($p.Name -ne 'boots') { $plan[$p.Name] = $p.Value } }
    foreach ($p in $boot.PSObject.Properties) { $plan[$p.Name] = $p.Value }
    $plan['name'] = "$Name-boot$n"
    $plan['boot'] = [ordered]@{ index = $n; of = $boots.Count; plan = $PlanPath }

    $cases = @()
    foreach ($c in @($boot.cases)) {
        $abs = [System.IO.Path]::GetFullPath((Join-Path $planDir ([string]$c.file)))
        if (-not (Test-Path -LiteralPath $abs -PathType Leaf)) { throw "boot ${n}: case file not found: $abs" }
        $rel = [System.IO.Path]::GetRelativePath($dir, $abs)
        if ([System.IO.Path]::IsPathRooted($rel)) { throw "boot ${n}: case file $abs is on another drive than the run folder $dir" }
        $copy = [ordered]@{}
        foreach ($p in $c.PSObject.Properties) { $copy[$p.Name] = $p.Value }
        $copy['file'] = $rel
        $cases += $copy
    }
    $plan['cases'] = $cases

    $file = Join-Path $dir 'boot.plan.json'
    [System.IO.File]::WriteAllText($file, ($plan | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    $out += [pscustomobject]@{ Index = $n; Dir = $dir; PlanFile = $file; Name = $plan['name'] }
}
$out
