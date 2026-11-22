#requires -Version 7
<#
.SYNOPSIS
  Order check (WP-H-09 step 7): re-runs each FAIL case of a plan once alone, in a fresh boot, before the FAIL is
  reported.

.DESCRIPTION
  run.ps1 calls this after a run of a plan with more than one case ended with a FAIL. For each failed case id it
  writes <RunDir>\alone-<id>\alone-plan.json: the plan as it is (mods, modset, options, settings, save, local builds,
  host log lists) with only that case and no "arenas" (the driver derives them from the case), the case file given
  relative to that folder. It then runs -RunScript (run.ps1) with -RunDir set to that folder and -NoOrderCheck, so
  the re-run never re-runs. Only the case's own verdict counts: a host log expectation the plan made for its other
  cases may fail the re-run's exit code without saying anything about this case.

  A case that passes alone is order-dependent: something an earlier case did made it fail. The FAIL still stands in
  the plan's run; run.ps1 notes both verdicts.

.OUTPUTS
  One [ordered] row per case id: id, alone_verdict (PASS, FAIL, ..., or $null when the re-run gave none),
  order_dependent, exit, folder.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PlanPath,
    [Parameter(Mandatory)] [string] $RunDir,
    [Parameter(Mandatory)] [string[]] $CaseIds,
    [Parameter(Mandatory)] [string] $RigRoot,
    [string] $RunScript = (Join-Path $PSScriptRoot 'run.ps1'),
    [hashtable] $ChildArgs = @{}
)
$ErrorActionPreference = 'Stop'
$planPath = (Resolve-Path -LiteralPath $PlanPath).Path
$planDir = Split-Path $planPath

foreach ($id in $CaseIds) {
    $plan = [System.IO.File]::ReadAllText($planPath) | ConvertFrom-Json
    $case = @($plan.cases | Where-Object { $_.id -eq $id })
    $folderName = 'alone-' + ($id -replace '[^A-Za-z0-9_.-]', '_')
    $dir = Join-Path $RunDir $folderName
    if (-not $case.Count) {
        [ordered]@{ id = $id; alone_verdict = $null; order_dependent = $false; exit = $null; folder = $folderName }
        continue
    }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $one = $case[0] | Select-Object *
    $caseFile = [System.IO.Path]::GetFullPath((Join-Path $planDir ([string]$one.file)))
    $one.file = [System.IO.Path]::GetRelativePath($dir, $caseFile) -replace '\\', '/'
    $plan.cases = @($one)
    if ($plan.PSObject.Properties['arenas']) { $plan.PSObject.Properties.Remove('arenas') }
    $plan | Add-Member -NotePropertyName name -NotePropertyValue "$(if ($plan.PSObject.Properties['name']) { $plan.name } else { 'plan' })-alone" -Force
    $alonePlan = Join-Path $dir 'alone-plan.json'   # run.ps1 copies the plan it runs to plan.json there
    $plan | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $alonePlan -Encoding utf8

    $runArgs = @{} + $ChildArgs
    $runArgs.Plan = $alonePlan; $runArgs.RunDir = $dir; $runArgs.RigRoot = $RigRoot; $runArgs.NoOrderCheck = $true
    Write-Host "order check: $id alone ($folderName)"
    $global:LASTEXITCODE = 0
    $null = & $RunScript @runArgs
    $code = $LASTEXITCODE
    $sumFile = Join-Path $dir 'summary.json'
    $verdict = $null
    if (Test-Path -LiteralPath $sumFile) {
        $s = Get-Content -LiteralPath $sumFile -Raw | ConvertFrom-Json
        $row = @($s.cases | Where-Object { $_ -and $_.id -eq $id })
        if ($row.Count) { $verdict = [string]$row[0].verdict }
    }
    [ordered]@{ id = $id; alone_verdict = $verdict; order_dependent = ($verdict -eq 'PASS'); exit = $code; folder = $folderName }
}
