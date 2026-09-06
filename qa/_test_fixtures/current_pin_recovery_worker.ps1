param(
    [string]$RepoRoot, [string]$InvokingRoot, [string]$FixtureRoot,
    [string]$SourceCommit, [string]$Mode, [string]$MutexName
)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools\ship\transaction-lease.ps1')
. (Join-Path $RepoRoot 'tools\vmb-launcher-path.ps1')
. (Join-Path $RepoRoot 'tools\ship\current-source-pin-recovery.ps1')
$recordPath = Join-Path $FixtureRoot 'owner.json'
$serverPath = Join-Path $FixtureRoot 'server.json'
$lease = $null; $recordBytes = $null; $fileLock = $null
$realEnterRelease = (Get-Command Enter-VtGitHubReleaseMutationMutex).ScriptBlock
function Enter-VtGitHubReleaseMutationMutex { & $realEnterRelease -MutexName ($MutexName + '.Release') }
function Get-VtCardDeploymentManifest {
    param($Repository)
    if ($Repository -cne 'Ensrick/vermintide-2-tweaker') { throw 'Unexpected repository.' }
    [IO.File]::AppendAllText((Join-Path $FixtureRoot 'reads.txt'), "$PID`n")
    if ($Mode -eq 'Unavailable') { throw 'planted-unavailable-manifest' }
    return ([IO.File]::ReadAllText($serverPath) | ConvertFrom-Json)
}
try {
    $lease = Enter-VmbMachineTransactionLease -Action ship -Mod alpha -ProjectRoot $InvokingRoot `
        -RecordPath $recordPath -MutexName $MutexName
    $recordBytes = [IO.File]::ReadAllBytes($recordPath)
    if ($Mode -eq 'LeaseOnly') { exit 0 }
    if ($Mode -in @('CrashBeforeAccept','CrashAfterAccept')) {
        if ($Mode -eq 'CrashAfterAccept') {
            [IO.File]::Copy((Join-Path $FixtureRoot 'new-server.json'), $serverPath, $true)
        }
        [IO.File]::WriteAllText((Join-Path $FixtureRoot 'crash-ready.txt'), [string]$PID)
        # Genuine hard death: neither this fixture finally nor ship finalization
        # runs. Only the independent server fixture retains accepted state.
        [Diagnostics.Process]::GetCurrentProcess().Kill()
        [Threading.Thread]::Sleep([Threading.Timeout]::Infinite)
    }
    if ($Mode -eq 'Borrowed') { $lease.OwnsMutex = $false }
    if ($Mode -eq 'WrongRecord') {
        $wrong = [Text.Encoding]::UTF8.GetString($recordBytes) | ConvertFrom-Json
        $wrong.mod = 'foreign'
        [IO.File]::WriteAllText($recordPath, ($wrong | ConvertTo-Json))
    }
    if ($Mode -eq 'WrongSource') { $SourceCommit = 'a' * 40 }
    if ($Mode -eq 'ReplaceFailure') {
        $primary = Get-VmbLauncherPrimaryWorktreeRoot -RepoRoot $InvokingRoot
        $fileLock = [IO.File]::Open((Join-Path $primary 'tools\verify\live_test_contract_exceptions.psd1'), 'Open', 'Read', 'Read')
    }
    $result = Invoke-VtCurrentSourcePinReconciliation -RepoRoot $InvokingRoot -SourceCommit $SourceCommit -TransactionLease $lease
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'result.json'), ($result | ConvertTo-Json -Depth 8))
    if ($Mode -eq 'CrashAfterPins') {
        [IO.File]::WriteAllText((Join-Path $FixtureRoot 'crash-ready.txt'), [string]$PID)
        [Diagnostics.Process]::GetCurrentProcess().Kill()
        [Threading.Thread]::Sleep([Threading.Timeout]::Infinite)
    }
}
catch {
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'error.txt'), $_.Exception.Message)
    throw
}
finally {
    if ($fileLock) { $fileLock.Dispose() }
    if ($lease) {
        # Restore only the deliberately corrupted test lease/record so the
        # real Exit path can independently authenticate and release ownership.
        if ($Mode -eq 'Borrowed') { $lease.OwnsMutex = $true }
        if ($Mode -eq 'WrongRecord') { [IO.File]::WriteAllBytes($recordPath, $recordBytes) }
        Exit-VmbMachineTransactionLease -Lease $lease
    }
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'finally.txt'), 'completed')
}
exit 0
