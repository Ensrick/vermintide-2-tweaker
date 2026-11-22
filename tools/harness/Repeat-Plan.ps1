#requires -Version 7
<#
.SYNOPSIS
  Repeatability check (WP-H-09 step 6): runs one plan -Count times and compares the verdict tables.

.DESCRIPTION
  Each run is a normal run.ps1 run (-RunScript) into <RigRoot>\repeats\<stamp>-<name>\run-<i>\, one after the other,
  with -NoOrderCheck so a FAIL does not add runs of its own. A run waits up to -Wait minutes for the rig lock.
  The verdict table of a run is its case ids with their verdicts, in order.

  Writes repeat.json and repeat.md into the repeat folder. A case whose verdict differs between runs is appended to
  -QuarantineFile (qa/runtime/quarantine.txt) as "<plan name><TAB><case id><TAB><verdicts><TAB><date>" unless that
  plan and case are already listed; quarantined cases must not close issues until fixed.

  Exit: 0 when every run produced the same table and kept the owner's profile isolated, 1 when tables differ or an
  isolation check failed, 2 when a run produced no summary, 3 when the plan cannot be repeated (a plan with
  "boots", which keeps its own run folders).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Plan,
    [int] $Count = 10,
    [double] $Wait = 30,                                  # minutes each run may wait for the rig lock
    [string] $RunScript = (Join-Path $PSScriptRoot 'run.ps1'),
    [string] $RigRoot = (Join-Path $env:LOCALAPPDATA 'vt2-harness'),
    [string] $QuarantineFile = (Join-Path $PSScriptRoot '..\..\qa\runtime\quarantine.txt'),
    [hashtable] $ChildArgs = @{}                          # passed to every run (renderer, driver, steamapps, ...)
)
$ErrorActionPreference = 'Stop'
$planPath = (Resolve-Path -LiteralPath $Plan).Path
$planObj = [System.IO.File]::ReadAllText($planPath) | ConvertFrom-Json
if ($planObj.PSObject.Properties['boots'] -and $planObj.boots) { Write-Host 'REPEAT REFUSED: a plan with boots cannot be repeated by this script.'; exit 3 }
$name = if ($planObj.name) { [string]$planObj.name } else { [System.IO.Path]::GetFileNameWithoutExtension($planPath) }
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$dir = Join-Path $RigRoot "repeats\$stamp-$name"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$runs = @()
for ($i = 1; $i -le $Count; $i++) {
    $runDir = Join-Path $dir "run-$i"
    New-Item -ItemType Directory -Force -Path $runDir | Out-Null
    $runArgs = @{} + $ChildArgs
    $runArgs.Plan = $planPath; $runArgs.RunDir = $runDir; $runArgs.RigRoot = $RigRoot; $runArgs.NoOrderCheck = $true; $runArgs.Wait = $Wait
    Write-Host "repeat $i of ${Count}: $name"
    $global:LASTEXITCODE = 0
    $null = & $RunScript @runArgs
    $code = $LASTEXITCODE
    $sumFile = Join-Path $runDir 'summary.json'
    $s = if (Test-Path -LiteralPath $sumFile) { Get-Content -LiteralPath $sumFile -Raw | ConvertFrom-Json } else { $null }
    $table = if ($s) { (@($s.cases | Where-Object { $_ } | ForEach-Object { "$($_.id)=$($_.verdict)" })) -join ';' } else { $null }
    $runs += [ordered]@{ index = $i; exit = $code; folder = "run-$i"; isolation = $s.isolation; table = $table; cases = @($s.cases | Where-Object { $_ }) }
}

$missing = @($runs | Where-Object { $null -eq $_.table })
$tables = @($runs | Where-Object { $null -ne $_.table } | ForEach-Object { $_.table } | Sort-Object -Unique)
$isolationOk = @($runs | Where-Object { $_.isolation -ne 'OK' }).Count -eq 0
$identical = ($missing.Count -eq 0 -and $tables.Count -eq 1)

# per case: the verdict of every run, in run order
$caseIds = [System.Collections.Generic.List[string]]::new()
foreach ($r in $runs) { foreach ($c in $r.cases) { if (-not $caseIds.Contains([string]$c.id)) { $caseIds.Add([string]$c.id) } } }
$differing = @()
foreach ($id in $caseIds) {
    $seen = @($runs | ForEach-Object { $c = @($_.cases | Where-Object { $_.id -eq $id }); if ($c.Count) { [string]$c[0].verdict } else { '-' } })
    if (@($seen | Sort-Object -Unique).Count -gt 1) { $differing += [ordered]@{ id = $id; verdicts = ($seen -join ',') } }
}

$quarantined = @()
if ($differing.Count -and $QuarantineFile) {
    $existing = if (Test-Path -LiteralPath $QuarantineFile) { [System.IO.File]::ReadAllLines($QuarantineFile) } else { @() }
    $add = @()
    foreach ($d in $differing) {
        $already = @($existing | Where-Object { $_ -match ('^' + [regex]::Escape($name) + '\t' + [regex]::Escape($d.id) + '\t') })
        if (-not $already.Count) { $add += "$name`t$($d.id)`t$($d.verdicts)`t$((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))"; $quarantined += $d.id }
    }
    if ($add.Count) { [System.IO.File]::AppendAllLines($QuarantineFile, [string[]]$add) }
}

$exit = if ($missing.Count) { 2 } elseif (-not $identical -or -not $isolationOk) { 1 } else { 0 }
$summary = [ordered]@{
    plan = $planPath; name = $name; count = $Count; identical = $identical; isolation_ok_every_run = $isolationOk; exit = $exit
    tables = $tables; differing = $differing; quarantined = $quarantined; runs = @($runs | ForEach-Object { [ordered]@{ index = $_.index; exit = $_.exit; folder = $_.folder; isolation = $_.isolation; table = $_.table } })
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $dir 'repeat.json') -Encoding utf8
$md = @("# Repeat $stamp-$name", '', "Runs $Count | identical tables: $identical | isolation OK every run: $isolationOk | exit $exit", '', '| Run | Exit | Isolation | Verdict table |', '|---|---|---|---|')
foreach ($r in $runs) { $md += "| $($r.index) | $($r.exit) | $($r.isolation) | $($r.table) |" }
foreach ($d in $differing) { $md += "Differing: $($d.id) ($($d.verdicts))$(if ($quarantined -contains $d.id) { ' -> quarantined' } else { ' (already in quarantine)' })" }
$md | Set-Content -LiteralPath (Join-Path $dir 'repeat.md') -Encoding utf8
$summary | ConvertTo-Json -Depth 6
exit $exit
