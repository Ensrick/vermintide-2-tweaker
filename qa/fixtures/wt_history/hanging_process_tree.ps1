# Real nested process fixture for the weapon-history freshness timeout gate.
# The parent records its direct child's PID and UTC start-time identity, then
# both remain alive until the caller proves process-tree termination. ASCII
# only for Windows PowerShell 5.1.

[CmdletBinding()]
param([Parameter(Mandatory)][string]$ChildPidPath)

$ErrorActionPreference = 'Stop'
$hostPath = (Get-Process -Id $PID).Path
if (-not $hostPath -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
    throw 'current PowerShell executable is unavailable'
}

$child = Start-Process -FilePath $hostPath `
    -ArgumentList @('-NoLogo', '-NoProfile', '-NonInteractive', '-Command',
        'Start-Sleep -Seconds 30') `
    -PassThru -WindowStyle Hidden
try {
    $childIdentity = ([string]$child.Id) + "`r`n" +
        ([string][long]$child.StartTime.ToFileTimeUtc()) + "`r`n"
    [IO.File]::WriteAllText($ChildPidPath, $childIdentity,
        [Text.Encoding]::ASCII)
    Start-Sleep -Seconds 30
}
finally {
    try {
        if (-not $child.HasExited) {
            $child.Kill()
            $null = $child.WaitForExit(2000)
        }
    }
    catch { }
    $child.Dispose()
}
