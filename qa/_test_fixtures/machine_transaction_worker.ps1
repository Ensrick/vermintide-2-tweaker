param(
    [Parameter(Mandatory = $true)][string]$HelperPath,
    [Parameter(Mandatory = $true)][string]$SemaphoreName,
    [Parameter(Mandatory = $true)][string]$RecordPath,
    [Parameter(Mandatory = $true)][string]$Action,
    [Parameter(Mandatory = $true)][string]$Mod,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds,
    [Parameter(Mandatory = $true)][string]$MarkerPath,
    [string]$ReleasePath,
    [string]$ArtifactPath,
    [string]$RequireDeadPidsPath,
    [string]$ReadyPath,
    [ValidateSet('Success', 'Wait', 'Throw', 'Crash', 'CrashWithChild', 'SuccessWithResidue')][string]$Mode = 'Success'
)

$ErrorActionPreference = 'Stop'
. $HelperPath
$hostPath = (Get-Process -Id $PID).Path

$lease = $null
try {
    if ($ReadyPath) { [System.IO.File]::WriteAllText($ReadyPath, 'entering') }
    $lease = Enter-VmbMachineTransactionLease `
        -Action $Action `
        -Mod $Mod `
        -ProjectRoot $ProjectRoot `
        -TimeoutMilliseconds $TimeoutMilliseconds `
        -SemaphoreName $SemaphoreName `
        -RecordPath $RecordPath
    if ($Mode -in @('CrashWithChild', 'SuccessWithResidue')) {
        $sleepCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('Start-Sleep -Seconds 30'))
        $childScript = @"
`$self = [Diagnostics.Process]::GetCurrentProcess().Path
`$grandchild = Start-Process -FilePath `$self -ArgumentList '-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand','$sleepCommand' -PassThru -WindowStyle Hidden
[IO.File]::WriteAllText('$($ArtifactPath.Replace("'", "''"))', "`$PID,`$(`$grandchild.Id)")
Start-Sleep -Seconds 30
"@
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        $child = Start-Process -FilePath $hostPath -ArgumentList @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded) `
            -PassThru -WindowStyle Hidden
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $ArtifactPath)) {
            if ($child.HasExited) { throw 'contained helper exited before PID marker' }
            if ([DateTime]::UtcNow -gt $deadline) { throw 'contained helper PID marker timeout' }
            Start-Sleep -Milliseconds 20
        }
    }
    elseif ($ArtifactPath) {
        [System.IO.File]::WriteAllText($ArtifactPath, "$Action/$Mod")
    }
    if ($RequireDeadPidsPath) {
        foreach ($candidate in ([IO.File]::ReadAllText($RequireDeadPidsPath) -split ',')) {
            try {
                $live = [Diagnostics.Process]::GetProcessById([int]$candidate)
                try { if (-not $live.HasExited) { throw "descendant PID $candidate still live when contender entered" } }
                finally { $live.Dispose() }
            }
            catch [System.ArgumentException] { }
        }
    }
    [System.IO.File]::WriteAllText($MarkerPath, 'acquired')
    if ($Mode -eq 'Throw') { throw 'planted transaction failure' }
    if ($Mode -in @('Crash', 'CrashWithChild')) {
        if ($ReleasePath) {
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            while (-not (Test-Path -LiteralPath $ReleasePath)) {
                if ([DateTime]::UtcNow -gt $deadline) { throw 'fixture crash trigger timeout' }
                Start-Sleep -Milliseconds 25
            }
        }
        [Environment]::FailFast('planted transaction crash')
    }
    if ($Mode -in @('Wait', 'SuccessWithResidue')) {
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        while (-not (Test-Path -LiteralPath $ReleasePath)) {
            if ([DateTime]::UtcNow -gt $deadline) { throw 'fixture release timeout' }
            Start-Sleep -Milliseconds 25
        }
    }
}
finally {
    if ($null -ne $lease) { Exit-VmbMachineTransactionLease -Lease $lease }
}
