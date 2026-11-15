#requires -Version 7
<#
.SYNOPSIS
  Finds the console log of a rig run (WP-H-02 step 1).

.DESCRIPTION
  run.ps1 starts the game with --default-console-log-path <run folder>\console.log (the switch exists in the
  retail exe; whether it names a file or a folder is [unverified]). In order of preference:
    1. a file at -SwitchPath                                   Source 'switch-file'
    2. a folder at -SwitchPath: its newest *.log since start     Source 'switch-dir'
    3. once -FallbackAfterSeconds have passed since -Started (or at once with 0): the newest console-*.log in the
       rig profile's console_logs folder written since start  Source 'profile-fallback'
  Nothing is written.

.OUTPUTS
  [pscustomobject] Path, Source; or $null when no log is there (yet).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SwitchPath,
    [Parameter(Mandatory)] [string] $ProfileLogDir,
    [Parameter(Mandatory)] [datetime] $Started,
    [datetime] $Now = (Get-Date),
    [int] $FallbackAfterSeconds = 20
)
$ErrorActionPreference = 'Stop'
$since = $Started.AddSeconds(-2)

function Get-Newest([string] $dir, [string] $filter) {
    $newest = $null
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter $filter -ErrorAction SilentlyContinue)) {
        if ($f.LastWriteTime -ge $since -and (-not $newest -or $f.LastWriteTime -gt $newest.LastWriteTime)) { $newest = $f }
    }
    $newest
}

if (Test-Path -LiteralPath $SwitchPath -PathType Leaf) {
    return [pscustomobject]@{ Path = (Resolve-Path -LiteralPath $SwitchPath).Path; Source = 'switch-file' }
}
if (Test-Path -LiteralPath $SwitchPath -PathType Container) {
    $f = Get-Newest $SwitchPath '*.log'
    if ($f) { return [pscustomobject]@{ Path = $f.FullName; Source = 'switch-dir' } }
}
if (($Now - $Started).TotalSeconds -ge $FallbackAfterSeconds) {
    $f = Get-Newest $ProfileLogDir 'console-*.log'
    if ($f) { return [pscustomobject]@{ Path = $f.FullName; Source = 'profile-fallback' } }
}
$null
