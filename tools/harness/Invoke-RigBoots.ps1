#requires -Version 7
<#
.SYNOPSIS
  Runs a rig plan with "boots" (WP-H-08): one full run per boot, in order, on one rig profile, under one rig lock.

.DESCRIPTION
  run.ps1 hands a plan with boots to this script. Split-BootPlan.ps1 writes one plan per boot under
  <RigRoot>\runs\<stamp>-<name>-<nonce>\boot-<i>\; each boot is then a normal run of -RunScript (run.ps1) with
  -RunDir set to its folder, and every boot after the first gets -KeepProfile, so it starts from the profile (save,
  settings, mod data) the boot before it left. The lock is taken once here and held across all boots; the boots run
  in this process and thread, so each boot's own WaitOne on the same named mutex succeeds (a mutex is re-entrant for
  its owning thread). A boot that exits 3 (refused, or isolation broken) ends the sequence.

  Writes summary.json and summary.md into the run folder, prints the summary, and exits 3 if any boot exited 3, else
  1 if any exited 1, else 2 if any exited 2 or a boot did not run, else 0.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PlanPath,
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $RigRoot,
    [hashtable] $ChildArgs = @{},                   # passed to every boot's run (renderer, driver, slots, ...)
    [string] $RunScript = (Join-Path $PSScriptRoot 'run.ps1'),
    [string] $LockName = 'Global\Vt2RigSingleInstance'
)
$ErrorActionPreference = 'Stop'
$plannedBoots = @(([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PlanPath).Path) | ConvertFrom-Json).boots).Count

$lock = [System.Threading.Mutex]::new($false, $LockName)
if (-not $lock.WaitOne(0)) { Write-Host 'RIG REFUSED: another rig run holds the lock.'; exit 3 }
$nonce = -join ((1..8) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$run = Join-Path $RigRoot "runs\$stamp-$Name-$nonce"
$results = @()
try {
    New-Item -ItemType Directory -Force -Path $run | Out-Null
    Copy-Item -LiteralPath $PlanPath -Destination (Join-Path $run 'plan.json')
    try { $bootPlans = @(& (Join-Path $PSScriptRoot 'Split-BootPlan.ps1') -PlanPath $PlanPath -OutDir $run -Name $Name) }
    catch { Write-Host "RIG REFUSED: boots: $($_.Exception.Message)"; exit 3 }
    foreach ($bp in $bootPlans) {
        Write-Host "boot $($bp.Index) of $($bootPlans.Count): $($bp.Name)"
        $bootArgs = @{} + $ChildArgs
        $bootArgs.Plan = $bp.PlanFile; $bootArgs.Name = $bp.Name; $bootArgs.RunDir = $bp.Dir; $bootArgs.RigRoot = $RigRoot
        if ($bp.Index -gt 1) { $bootArgs.KeepProfile = $true }
        $global:LASTEXITCODE = 0
        $null = & $RunScript @bootArgs
        $code = $LASTEXITCODE
        $child = $null
        $sumFile = Join-Path $bp.Dir 'summary.json'
        if (Test-Path -LiteralPath $sumFile) { $child = Get-Content -LiteralPath $sumFile -Raw | ConvertFrom-Json }
        $results += [ordered]@{
            boot = $bp.Index; name = $bp.Name; exit = $code; folder = "boot-$($bp.Index)"
            isolation = $child.isolation; run_end_seen = $child.run_end_seen; cases = @($child.cases | Where-Object { $_ })
        }
        if ($code -eq 3) { Write-Host "boot $($bp.Index) refused or broke isolation (exit 3); later boots not run"; break }
    }
}
finally { $lock.ReleaseMutex(); $lock.Dispose() }

$codes = @($results | ForEach-Object { $_.exit })
$exit = if ($codes -contains 3) { 3 } elseif ($codes -contains 1) { 1 } elseif ($codes -contains 2 -or $results.Count -lt $plannedBoots) { 2 } else { 0 }
$summary = [ordered]@{ run = "$stamp-$Name-$nonce"; name = $Name; exit = $exit; boots_planned = $plannedBoots; boots = $results }
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $run 'summary.json') -Encoding utf8
$md = @("# Rig run $($summary.run) (boots)", '', "Exit $exit | boots run $($results.Count) of $plannedBoots", '',
    '| Boot | Exit | Isolation | RUN END | Case | Verdict | Detail |', '|---|---|---|---|---|---|---|')
foreach ($b in $results) {
    if (-not $b.cases.Count) { $md += "| $($b.boot) | $($b.exit) | $($b.isolation) | $($b.run_end_seen) | - | - | - |" }
    foreach ($c in $b.cases) { $md += "| $($b.boot) | $($b.exit) | $($b.isolation) | $($b.run_end_seen) | $($c.id) | $($c.verdict) | $($c.detail) |" }
}
$md | Set-Content -LiteralPath (Join-Path $run 'summary.md') -Encoding utf8
$summary | ConvertTo-Json -Depth 8
exit $exit
