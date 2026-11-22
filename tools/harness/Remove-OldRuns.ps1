#requires -Version 7
<#
.SYNOPSIS
  Run-folder retention (WP-H-09 step 5): keeps the newest -Keep rig run folders and every folder a report names,
  and deletes the older ones.

.DESCRIPTION
  Looks only at the direct children of -RunsDir whose name is a run name (<yyyyMMdd-HHmmss>-<name>-<8 hex nonce>,
  as run.ps1 and Invoke-RigBoots.ps1 make them); anything else there is never touched. Newest first by the time stamp
  in the name. A folder is also kept when its name appears in any file under -ReportsDir
  (qa/runtime/reports), or when it is one of -Protect.

  A folder that is itself a junction or symbolic link, or holds one anywhere inside, is skipped and reported, never
  followed (global rule 1). Each deletion is one explicit path; the list is printed before anything is removed, and
  -WhatIf only prints it.

.OUTPUTS
  [pscustomobject] Kept, Removed, Skipped (folder names), Referenced (kept because a report names them).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RunsDir,
    [int] $Keep = 30,
    [string] $ReportsDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\reports'),
    [string[]] $Protect = @(),
    [switch] $WhatIf,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$result = [pscustomobject]@{ Kept = @(); Removed = @(); Skipped = @(); Referenced = @() }
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
    if ($i -lt $Keep -or $protected -contains $r.Name) { $result.Kept += $r.Name; continue }
    if ($reportText -and $reportText.Contains($r.Name)) { $result.Kept += $r.Name; $result.Referenced += $r.Name; continue }
    $isLink = [bool]($r.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    $innerLinks = @()
    if (-not $isLink) { $innerLinks = @(Get-ChildItem -LiteralPath $r.FullName -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue) }
    if ($isLink -or $innerLinks.Count) { $result.Skipped += $r.Name; continue }
    $doomed += $r
}

if ($doomed.Count -and -not $Quiet) {
    Write-Host "rig run retention: keeping $($result.Kept.Count) (newest $Keep, $($result.Referenced.Count) named in reports), removing $($doomed.Count):"
    foreach ($d in $doomed) { Write-Host "  $($d.FullName)" }
}
foreach ($s in $result.Skipped) { if (-not $Quiet) { Write-Host "  skipped (holds a junction or link): $s" } }
foreach ($d in $doomed) {
    if (-not $WhatIf) { Remove-Item -LiteralPath $d.FullName -Recurse -Force }
    $result.Removed += $d.Name
}
$result
