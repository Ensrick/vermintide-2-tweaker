# Root-exit/output-drain adversary for the weapon-history freshness gate. The
# parent records a long-lived child's exact identity, then exits without
# waiting. The child inherits the parent's redirected standard handles so the
# caller must bound output draining to the network deadline. ASCII only for
# Windows PowerShell 5.1.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ChildPidPath)

$ErrorActionPreference = 'Stop'
$hostPath = (Get-Process -Id $PID).Path
if (-not $hostPath -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
    throw 'current PowerShell executable is unavailable'
}

$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = $hostPath
$start.Arguments = '-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"'
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$child = New-Object System.Diagnostics.Process
$child.StartInfo = $start
try {
    if (-not $child.Start()) { throw 'output-holding child did not start' }
    $childIdentity = ([string]$child.Id) + "`r`n" +
        ([string][long]$child.StartTime.ToFileTimeUtc()) + "`r`n"
    [IO.File]::WriteAllText($ChildPidPath, $childIdentity,
        [Text.Encoding]::ASCII)
}
finally { $child.Dispose() }
