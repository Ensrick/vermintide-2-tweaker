#requires -Version 7
<#
.SYNOPSIS
  Run-folder retention (WP-H-09 step 5), opt-in: with -Retain <N> the newest N rig run folders, every folder a report
  names and every -Protect folder stay whole; each older one is reduced to its small evidence files under
  <RunsDir>\_archive\<run>\ and its bulky files are deleted.

.DESCRIPTION
  Nothing is pruned unless the caller passes -Retain (run.ps1 and Invoke-RigBoots.ps1 pass it only when they are given
  -Retain themselves). Lead decision 2026-11-22: run ids are quoted as acceptance evidence in the program ledger and
  PR bodies, so no run disappears by default, and a pruned run keeps its verdict record.

  Looks only at the direct children of -RunsDir whose name is a run name (<yyyyMMdd-HHmmss>-<name>-<8 hex nonce>, as
  run.ps1 and Invoke-RigBoots.ps1 make them); anything else there (including _archive) is never touched. Newest first
  by the time stamp in the name. A folder is kept whole when its name appears in any file under -ReportsDir
  (qa/runtime/reports, for example cited-runs.md), or when it is one of -Protect.

  Pruning one run: every file named in -KeepFiles, at any depth (a boot's boot-<i>\summary.json, an order check's
  alone-<id>\summary.json), is copied to <RunsDir>\_archive\<run>\ at the same relative path; each copy is checked
  for its length; only then is the run folder removed. Everything else (console logs, crash dumps, settings copies,
  stills, staged files) goes with it. A folder that is itself a junction or symbolic link, or holds one anywhere
  inside, is skipped and reported, never followed (global rule 1). The list is printed before anything is removed;
  -WhatIf only prints it.

.OUTPUTS
  [pscustomobject] Kept, Removed (pruned to the archive), Skipped (folder names), Referenced (kept whole because a
  report names them), Archived (archive file paths written).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RunsDir,
    [Parameter(Mandatory)] [int] $Retain,
    [string] $ReportsDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\reports'),
    [string[]] $Protect = @(),
    [string[]] $KeepFiles = @('summary.json', 'summary.md', 'sweep.json', 'evidence.txt', 'plan.json'),
    [switch] $WhatIf,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$result = [pscustomobject]@{ Kept = @(); Removed = @(); Skipped = @(); Referenced = @(); Archived = @() }
if ($Retain -lt 1) { throw "-Retain must be 1 or more (got $Retain); leave it out to prune nothing" }
if (-not (Test-Path -LiteralPath $RunsDir -PathType Container)) { return $result }

$runName = '^\d{8}-\d{6}-.+-[0-9a-f]{8}$'
$runs = @(Get-ChildItem -LiteralPath $RunsDir -Directory -Force | Where-Object { $_.Name -match $runName } | Sort-Object Name -Descending)

$reportText = ''
if ($ReportsDir -and (Test-Path -LiteralPath $ReportsDir -PathType Container)) {
    $reportText = (@(Get-ChildItem -LiteralPath $ReportsDir -File -Recurse -Force | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n")
}
$protected = @($Protect | Where-Object { $_ } | ForEach-Object { Split-Path -Leaf $_ })

$doomed = @()
for ($i = 0; $i -lt $runs.Count; $i++) {
    $r = $runs[$i]
    if ($i -lt $Retain -or $protected -contains $r.Name) { $result.Kept += $r.Name; continue }
    if ($reportText -and $reportText.Contains($r.Name)) { $result.Kept += $r.Name; $result.Referenced += $r.Name; continue }
    $isLink = [bool]($r.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    $innerLinks = @()
    if (-not $isLink) { $innerLinks = @(Get-ChildItem -LiteralPath $r.FullName -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue) }
    if ($isLink -or $innerLinks.Count) { $result.Skipped += $r.Name; continue }
    $doomed += $r
}

if ($doomed.Count -and -not $Quiet) {
    Write-Host "rig run retention: $($result.Kept.Count) kept whole (newest $Retain, $($result.Referenced.Count) named in reports), $($doomed.Count) pruned to $(Join-Path $RunsDir '_archive') (kept: $($KeepFiles -join ', ')):"
    foreach ($d in $doomed) { Write-Host "  $($d.FullName)" }
}
foreach ($s in $result.Skipped) { if (-not $Quiet) { Write-Host "  skipped (holds a junction or link): $s" } }
foreach ($d in $doomed) {
    if ($WhatIf) { $result.Removed += $d.Name; continue }
    $archive = Join-Path (Join-Path $RunsDir '_archive') $d.Name
    $keep = @(Get-ChildItem -LiteralPath $d.FullName -File -Recurse -Force | Where-Object { $KeepFiles -contains $_.Name })
    $copied = $true
    foreach ($f in $keep) {
        $rel = [System.IO.Path]::GetRelativePath($d.FullName, $f.FullName)
        $dest = Join-Path $archive $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        if ((Get-Item -LiteralPath $dest).Length -ne $f.Length) { $copied = $false }
        $result.Archived += $dest
    }
    # a run with nothing to keep still gets its archive folder, so the run id stays findable
    New-Item -ItemType Directory -Force -Path $archive | Out-Null
    if (-not $copied) { $result.Skipped += $d.Name; if (-not $Quiet) { Write-Host "  not removed (an archive copy does not match): $($d.Name)" }; continue }
    Remove-Item -LiteralPath $d.FullName -Recurse -Force
    $result.Removed += $d.Name
}
$result
