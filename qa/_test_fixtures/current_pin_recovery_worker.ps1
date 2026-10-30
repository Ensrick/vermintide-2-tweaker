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
# #1777 mutation controls stay wholly inside this disposable worker. Compile
# and exact-preimage installation are outside the policy catch; they cannot
# masquerade as a normal refusal or kill a control through setup failure.
if ($Mode -like 'Mutant*') {
    $mutations = @(
        @{Mode='MutantReceipt';Function='New-VtReviewedRouteTransitionProofs';Before='if ($receiptHash -cne [string]$declaration.CandidateReceiptSha256)';After='if ($false)'},
        @{Mode='MutantPair';Function='Assert-VtReviewedRouteTransitionRows';Before='$trees -cnotcontains $FromTree -or $trees -cnotcontains $ToTree';After='$false'},
        @{Mode='MutantAncestry';Function='New-VtReviewedRouteTransitionProofs';Before='$null = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @(''merge-base'',''--is-ancestor'',$from,$SourceCommit) -Description ''Transition same-history ancestor''';After='$null = $null'},
        @{Mode='MutantMembership';Function='Get-VtExceptionPinRepointPlan';Before='$transition -and @($transition.FromTree,$transition.ToTree) -ccontains $DeployedTree';After='$transition -and $true'}
    )
    $mutation = @($mutations | Where-Object { $_.Mode -ceq $Mode })
    if ($mutation.Count -ne 1) { throw 'Unknown private transition mutant.' }
    $mutation = $mutation[0]
    $definition = Get-Command $mutation.Function -CommandType Function -ErrorAction Stop
    $body = $definition.ScriptBlock.ToString()
    if ([regex]::Matches($body,[regex]::Escape($mutation.Before)).Count -ne 1) { throw 'Transition mutant preimage is not unique.' }
    # Re-created blocks lack their defining file's automatic PSScriptRoot.
    # Preserve ONLY that original dependency root; never copy the algorithm.
    if ($body.Contains('$PSScriptRoot')) {
        $originalRoot = Split-Path -Parent $definition.ScriptBlock.File
        if ([string]::IsNullOrWhiteSpace($originalRoot)) { throw 'Transition mutant lost its defining source file.' }
        $body = $body.Replace('$PSScriptRoot',("'" + $originalRoot.Replace("'","''") + "'"))
    }
    $replacement = [scriptblock]::Create($body.Replace($mutation.Before,$mutation.After))
    Set-Item -Path ('Function:' + $mutation.Function) -Value $replacement
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'mutant-installed.txt'),$Mode)
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
    if ($Mode -eq 'TransitionFinalize') {
        # A private unit fixture for the existing original-owner finalizer seam;
        # never a real publication receipt or standalone production entry point.
        $tree = Get-VtGitScalar -RepoRoot $InvokingRoot -Arguments @('rev-parse',($SourceCommit + ':alpha/scripts/mods')) -Description 'Fixture published tree'
        $json = New-VtPublishedPinContext -RepoRoot $InvokingRoot -Mod alpha -ModId alpha -SourceCommit $SourceCommit -ModTree $tree -Version '0.1.4-dev' -PublishedId '123' -ReleaseTag 'mods-2026-09-06'
        $result = Invoke-VtPublishedPinFinalization -PublicationJson $json -TransactionLease $lease
    }
    else {
        $result = Invoke-VtCurrentSourcePinReconciliation -RepoRoot $InvokingRoot -SourceCommit $SourceCommit -TransactionLease $lease
    }
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
