# Offline two-process fixtures for the machine-global VMB/Stingray transaction
# lease. No VMB, Stingray, deploy, staging, Workshop, or network action runs.

[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'

function Invoke-MachineTransactionLeaseSelfTest {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $helper = Join-Path $repoRoot 'tools\ship\transaction-lease.ps1'
    . $helper
    $worker = Join-Path $PSScriptRoot '_test_fixtures\machine_transaction_worker.ps1'
    $hostPath = (Get-Process -Id $PID).Path
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-transaction-fixture-' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($temp) | Out-Null
    $passed = 0

    function Assert-Fixture([bool]$Condition, [string]$Message) {
        if (-not $Condition) { throw "fixture failed: $Message" }
        $script:__transactionPassed++
    }

    function Start-Worker {
        param(
            [string]$Semaphore,
            [string]$Record,
            [string]$Action,
            [string]$Mod,
            [int]$Timeout,
            [string]$Marker,
            [string]$Release,
            [string]$Artifact,
            [string]$Mode = 'Success',
            [string]$RequireDeadPids = '',
            [string]$ReadyPath = ''
        )
        $arguments = @(
            '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', $worker,
            '-HelperPath', $helper,
            '-SemaphoreName', $Semaphore,
            '-RecordPath', $Record,
            '-Action', $Action,
            '-Mod', $Mod,
            '-ProjectRoot', $repoRoot,
            '-TimeoutMilliseconds', "$Timeout",
            '-MarkerPath', $Marker,
            '-Mode', $Mode
        )
        if ($Release) { $arguments += @('-ReleasePath', $Release) }
        if ($Artifact) { $arguments += @('-ArtifactPath', $Artifact) }
        if ($RequireDeadPids) { $arguments += @('-RequireDeadPidsPath', $RequireDeadPids) }
        if ($ReadyPath) { $arguments += @('-ReadyPath', $ReadyPath) }
        $stdout = $Marker + '.stdout.txt'
        $stderr = $Marker + '.stderr.txt'
        return Start-Process -FilePath $hostPath -ArgumentList $arguments -PassThru `
            -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    }

    function Wait-Marker([string]$Path, [System.Diagnostics.Process]$Process) {
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $Path)) {
            if ($Process.HasExited) {
                $err = if (Test-Path ($Path + '.stderr.txt')) { [System.IO.File]::ReadAllText($Path + '.stderr.txt') } else { '' }
                throw "worker exited $($Process.ExitCode) before marker '$Path': $err"
            }
            if ([DateTime]::UtcNow -gt $deadline) { throw "timeout waiting for marker '$Path'" }
            Start-Sleep -Milliseconds 25
        }
    }

    function Read-WorkerError([string]$Marker) {
        $path = $Marker + '.stderr.txt'
        if (-not (Test-Path -LiteralPath $path)) { return '' }
        return [System.IO.File]::ReadAllText($path)
    }

    $script:__transactionPassed = 0
    $children = @()
    try {
        $helperText = [System.IO.File]::ReadAllText($helper, [System.Text.Encoding]::UTF8)
        Assert-Fixture ($helperText.Contains("'Global\Ensrick.VMBLauncher.Transaction.v1'")) 'production mutex uses the machine-global namespace'
        Assert-Fixture ($helperText.Contains('[System.IO.FileOptions]::WriteThrough') -and $helperText.Contains('$stream.Flush($true)')) 'owner record is flushed durably before the transaction proceeds'
        $shipText = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'tools\ship\ship.ps1'), [System.Text.Encoding]::UTF8)
        $publisherText = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'tools\publish-release\publish-release.ps1'), [System.Text.Encoding]::UTF8)
        $reproText = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'qa\check_release_reproducibility.ps1'), [System.Text.Encoding]::UTF8)
        $shipEnter = $shipText.LastIndexOf('Enter-VmbMachineTransactionLease')
        $shipLauncher = $shipText.LastIndexOf('Invoke-ShipLauncherNoWindow -LauncherExecutableLease $launcherExecutableLease')
        $shipExit = $shipText.LastIndexOf('Exit-VmbMachineTransactionLease -Lease $transactionLease')
        $shipClaimRelease = $shipText.LastIndexOf('& $claimScript -Mod $Mod -Release -Quiet')
        Assert-Fixture ($shipEnter -ge 0 -and $shipEnter -lt $shipLauncher -and $shipExit -gt $shipClaimRelease) 'ship owns one continuous lease across launcher actions, parity, release, upload proof, cards, and claim finalization'
        $publisherEnter = $publisherText.IndexOf('Enter-VmbMachineTransactionLease')
        $publisherReleaseMutex = $publisherText.IndexOf("'Global\VT2_GitHubReleaseMutation'")
        $publisherBuild = $publisherText.IndexOf('$buildRun = Invoke-VmbLauncherProcess')
        Assert-Fixture ($publisherEnter -ge 0 -and $publisherEnter -lt $publisherReleaseMutex -and $publisherEnter -lt $publisherBuild) 'standalone publisher takes transaction before release mutex and optional launcher build'
        Assert-Fixture ($reproText.IndexOf('Enter-VmbMachineTransactionLease') -lt $reproText.IndexOf('$buildRun = Invoke-VmbLauncherProcess')) 'reproducibility caller takes transaction before leased launcher build'
        $publisherStageCleanup = $publisherText.LastIndexOf('Remove-PublicationStageDirectory -Path $stage')
        $publisherLauncherExit = $publisherText.LastIndexOf('Exit-VmbLauncherExecutableLease -Lease $effectiveLauncherLease')
        $publisherTransactionExit = $publisherText.LastIndexOf('Exit-VmbMachineTransactionLease -Lease $releaseTransactionLease')
        Assert-Fixture ($publisherStageCleanup -ge 0 -and
            $publisherLauncherExit -gt $publisherStageCleanup -and
            $publisherTransactionExit -gt $publisherLauncherExit) 'standalone publisher cleans its stage and releases its owned executable before the machine transaction'
        $reproTempCleanup = $reproText.LastIndexOf('Remove-Item -LiteralPath $tempSettings -Force')
        $reproLauncherExit = $reproText.LastIndexOf('Exit-VmbLauncherExecutableLease -Lease $launcherLease')
        $reproTransactionExit = $reproText.LastIndexOf('Exit-VmbMachineTransactionLease -Lease $rebuildTransactionLease')
        Assert-Fixture ($reproTempCleanup -ge 0 -and
            $reproLauncherExit -gt $reproTempCleanup -and
            $reproTransactionExit -gt $reproLauncherExit) 'reproducibility caller cleans temporary state and releases its executable before the machine transaction'

        # A normally emptied Job has ActiveProcesses=0 but no end-of-job time
        # limit and therefore is not a signalled synchronization object. Keep a
        # handle open so ERROR_FILE_NOT_FOUND cannot accidentally satisfy this
        # regression; recovery must use accounting data and return promptly.
        $oldTestMode = [Environment]::GetEnvironmentVariable('VMBLAUNCHER_TRANSACTION_TEST_MODE', 'Process')
        $emptyJob = [IntPtr]::Zero
        try {
            [Environment]::SetEnvironmentVariable('VMBLAUNCHER_TRANSACTION_TEST_MODE', '1', 'Process')
            $emptyJobName = 'Global\Ensrick.VMBLauncher.Transaction.Process.fixture.' + [guid]::NewGuid().ToString('N')
            $emptyJob = [VmbTransactionProcessTreeGuard]::CreateOrdinarilyEmptiedJobForTest($emptyJobName)
            $emptyWatch = [Diagnostics.Stopwatch]::StartNew()
            [VmbTransactionProcessTreeGuard]::WaitForDrained($emptyJobName, 2000)
            Assert-Fixture ($emptyWatch.ElapsedMilliseconds -lt 1000) 'ordinary zero-active Job recovery uses accounting instead of unsupported Job signalling semantics'
        }
        finally {
            [VmbTransactionProcessTreeGuard]::CloseTestJob($emptyJob)
            [Environment]::SetEnvironmentVariable('VMBLAUNCHER_TRANSACTION_TEST_MODE', $oldTestMode, 'Process')
        }

        $scopeRecord = Join-Path $temp 'same-process-scope.json'
        $scopeMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $oldRecordEnvironment = [Environment]::GetEnvironmentVariable('VMBLAUNCHER_TRANSACTION_RECORD_PATH', 'Process')
        $scopeLease = Enter-VmbMachineTransactionLease -Action 'scope-owner' -Mod 'mod-a' `
            -ProjectRoot $repoRoot -MutexName $scopeMutex -RecordPath $scopeRecord
        try {
            Assert-Fixture ([IO.Path]::GetFullPath($env:VMBLAUNCHER_TRANSACTION_RECORD_PATH) -eq [IO.Path]::GetFullPath($scopeRecord)) 'custom owner record path is exported to launcher children'
            $wrongModRejected = $false
            try {
                $null = Enter-VmbMachineTransactionLease -Action 'nested-wrong-mod' -Mod 'mod-b' `
                    -ProjectRoot $repoRoot -MutexName $scopeMutex -RecordPath $scopeRecord
            }
            catch { $wrongModRejected = $_.Exception.Message -match 'record identity|project root' }
            Assert-Fixture $wrongModRejected 'same-process nested scope rejects a different mod'
        }
        finally { Exit-VmbMachineTransactionLease -Lease $scopeLease }
        Assert-Fixture ([Environment]::GetEnvironmentVariable('VMBLAUNCHER_TRANSACTION_RECORD_PATH', 'Process') -eq $oldRecordEnvironment) 'custom owner record environment is restored after release'

        # Normal release authenticates and deletes its record while still
        # holding the mutex. A deletion failure re-abandons without leaving a
        # blocked owner thread in this long-lived host.
        $deleteRecord = Join-Path $temp 'delete-failure-owner.json'
        $deleteMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $deleteLease = Enter-VmbMachineTransactionLease -Action 'delete-failure' -Mod 'mod-a' `
            -ProjectRoot $repoRoot -MutexName $deleteMutex -RecordPath $deleteRecord
        $deleteBaselineThreads = [VmbTransactionMutexHolder]::ActiveThreadCount - 1
        $recordLock = New-Object IO.FileStream($deleteRecord, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $deleteFailure = ''
        try { Exit-VmbMachineTransactionLease -Lease $deleteLease }
        catch { $deleteFailure = $_.Exception.Message }
        finally { $recordLock.Dispose() }
        Assert-Fixture ($deleteFailure -match 'CRITICAL' -and
            [VmbTransactionMutexHolder]::ActiveThreadCount -eq $deleteBaselineThreads) 'record deletion failure re-abandons with no owner-thread residue'
        $deleteRetryError = ''
        try { $null = Enter-VmbMachineTransactionLease -Action 'delete-retry' -Mod 'mod-a' -ProjectRoot $repoRoot -TimeoutMilliseconds 1000 -MutexName $deleteMutex -RecordPath $deleteRecord }
        catch { $deleteRetryError = $_.Exception.Message }
        Assert-Fixture ($deleteRetryError -match 'Refusing abandoned transaction recovery' -and
            [VmbTransactionMutexHolder]::ActiveThreadCount -eq $deleteBaselineThreads) 'retry cannot bypass failed record deletion'

        # BuildOnly A remains owner through a planted parity pause. BuildOnly B
        # for a different mod times out before touching its fake artifact.
        $sem = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $record = Join-Path $temp 'owner.json'
        $aMarker = Join-Path $temp 'a.marker'
        $aRelease = Join-Path $temp 'a.release'
        $artifact = Join-Path $temp 'artifact.bin'
        $a = Start-Worker $sem $record 'build-only' 'mod-a' 5000 $aMarker $aRelease $artifact 'Wait'
        $children += $a
        Wait-Marker $aMarker $a
        $before = (Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash

        $bMarker = Join-Path $temp 'b.marker'
        $b = Start-Worker $sem $record 'build-only' 'mod-b' 150 $bMarker '' $artifact 'Success'
        $children += $b
        $b.WaitForExit()
        $b.Refresh()
        Assert-Fixture ((Read-WorkerError $bMarker) -match 'machine mutex') 'BuildOnly-vs-BuildOnly contender reports timeout'
        Assert-Fixture (-not (Test-Path -LiteralPath $bMarker)) 'timed-out contender performs no fake mutation'
        Assert-Fixture (((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash) -eq $before) 'artifact hash remains stable throughout owner parity window'

        [System.IO.File]::WriteAllText($aRelease, 'release')
        $a.WaitForExit()
        $a.Refresh()
        $aError = Read-WorkerError $aMarker
        Assert-Fixture ((Test-Path -LiteralPath $aMarker) -and [string]::IsNullOrWhiteSpace($aError)) "first BuildOnly owner releases normally (exit $($a.ExitCode): $aError)"

        $retryMarker = Join-Path $temp 'retry.marker'
        $retry = Start-Worker $sem $record 'build-only' 'mod-b' 2000 $retryMarker '' $artifact 'Success'
        $children += $retry
        $retry.WaitForExit()
        $retry.Refresh()
        Assert-Fixture ((Test-Path -LiteralPath $retryMarker) -and [string]::IsNullOrWhiteSpace((Read-WorkerError $retryMarker))) 'timed-out contender succeeds on retry after release'

        # Exercise all conflicting action pair labels against the same primitive.
        foreach ($pair in @(@('build-only','deploy'), @('build-only','upload'), @('ship','ship'))) {
            $pairSem = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
            $pairRecord = Join-Path $temp (($pair -join '-') + '.json')
            $ownerMarker = Join-Path $temp (($pair -join '-') + '.owner')
            $release = $ownerMarker + '.release'
            $owner = Start-Worker $pairSem $pairRecord $pair[0] 'mod-a' 3000 $ownerMarker $release '' 'Wait'
            $children += $owner
            Wait-Marker $ownerMarker $owner
            $contenderMarker = Join-Path $temp (($pair -join '-') + '.contender')
            $contender = Start-Worker $pairSem $pairRecord $pair[1] 'mod-b' 125 $contenderMarker '' '' 'Success'
            $children += $contender
            $contender.WaitForExit()
            $contender.Refresh()
            Assert-Fixture ((Read-WorkerError $contenderMarker) -match 'machine mutex' -and -not (Test-Path -LiteralPath $contenderMarker)) "$($pair[0])-vs-$($pair[1]) is serialized before mutation"
            [System.IO.File]::WriteAllText($release, 'release')
            $owner.WaitForExit()
            $owner.Refresh()
        }

        # finally releases after an ordinary failure.
        $failureSem = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $failureRecord = Join-Path $temp 'failure.json'
        $failureMarker = Join-Path $temp 'failure.marker'
        $failure = Start-Worker $failureSem $failureRecord 'deploy' 'mod-a' 1000 $failureMarker '' '' 'Throw'
        $children += $failure
        $failure.WaitForExit()
        $failure.Refresh()
        Assert-Fixture ((Read-WorkerError $failureMarker) -match 'planted transaction failure') 'planted failure is observable'
        $afterFailureMarker = Join-Path $temp 'after-failure.marker'
        $afterFailure = Start-Worker $failureSem $failureRecord 'upload' 'mod-b' 1000 $afterFailureMarker '' '' 'Success'
        $children += $afterFailure
        $afterFailure.WaitForExit()
        $afterFailure.Refresh()
        Assert-Fixture ((Test-Path -LiteralPath $afterFailureMarker) -and [string]::IsNullOrWhiteSpace((Read-WorkerError $afterFailureMarker))) 'next process acquires after failure cleanup'

        # A hard process death skips finally. The named Mutex becomes abandoned;
        # the successor authenticates the stale record, proves the recorded Job
        # has drained by accounting, then replaces the record and proceeds.
        $crashSem = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $crashRecord = Join-Path $temp 'crash.json'
        $crashMarker = Join-Path $temp 'crash.marker'
        $crash = Start-Worker $crashSem $crashRecord 'build-only' 'mod-a' 1000 $crashMarker '' '' 'Crash'
        $children += $crash
        $crash.WaitForExit()
        $crash.Refresh()
        Assert-Fixture ((Test-Path -LiteralPath $crashRecord) -and (Test-Path -LiteralPath $crashMarker)) 'hard crash leaves only a stale diagnostic owner record'
        $afterCrashMarker = Join-Path $temp 'after-crash.marker'
        $afterCrash = Start-Worker $crashSem $crashRecord 'ship' 'mod-b' 1000 $afterCrashMarker '' '' 'Success'
        $children += $afterCrash
        $afterCrash.WaitForExit()
        $afterCrash.Refresh()
        Assert-Fixture ((Test-Path -LiteralPath $afterCrashMarker) -and [string]::IsNullOrWhiteSpace((Read-WorkerError $afterCrashMarker))) 'next process recovers after hard owner death'

        # The sole mutex handle is gone before this later contender starts, so
        # Windows can recreate a fresh non-abandoned named object. The durable
        # record must still gate mutation.
        $freshMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $freshRecord = Join-Path $temp 'fresh-object-owner.json'
        $freshOwnerMarker = Join-Path $temp 'fresh-object-owner.marker'
        $freshOwner = Start-Worker $freshMutex $freshRecord 'ship' 'mod-a' 1000 $freshOwnerMarker '' '' 'Crash'
        $children += $freshOwner
        $freshOwner.WaitForExit()
        [IO.File]::WriteAllText($freshRecord, '{ malformed durable authority')
        $freshLaterMarker = Join-Path $temp 'fresh-object-later.marker'
        $freshLater = Start-Worker $freshMutex $freshRecord 'deploy' 'mod-b' 1000 $freshLaterMarker '' '' 'Success'
        $children += $freshLater
        $freshLater.WaitForExit()
        Assert-Fixture ((Read-WorkerError $freshLaterMarker) -match 'Refusing prior transaction recovery' -and
            -not (Test-Path -LiteralPath $freshLaterMarker)) 'fresh mutex object still honors malformed durable authority before mutation'

        # A long-lived PowerShell/GUI host must not retain a blocked owner
        # thread when recovery itself fails. Preserve the kernel object with a
        # non-owning handle, then retry twice in this same process.
        $sameMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $sameRecord = Join-Path $temp 'same-process-abandoned-owner.json'
        $sameOwnerMarker = Join-Path $temp 'same-process-abandoned-owner.marker'
        $sameCrash = Join-Path $temp 'same-process-abandoned-owner.crash'
        $sameOwner = Start-Worker $sameMutex $sameRecord 'ship' 'mod-a' 5000 $sameOwnerMarker $sameCrash '' 'Crash'
        $children += $sameOwner
        Wait-Marker $sameOwnerMarker $sameOwner
        $sameKeeper = [Threading.Mutex]::OpenExisting($sameMutex)
        Remove-Item -LiteralPath $sameRecord -Force
        [IO.File]::WriteAllText($sameCrash, 'crash')
        $sameOwner.WaitForExit()
        $baselineThreads = [VmbTransactionMutexHolder]::ActiveThreadCount
        $sameFirstError = ''
        try { $null = Enter-VmbMachineTransactionLease -Action 'same-first' -Mod 'mod-b' -ProjectRoot $temp -TimeoutMilliseconds 1000 -MutexName $sameMutex -RecordPath $sameRecord }
        catch { $sameFirstError = $_.Exception.Message }
        Assert-Fixture ($sameFirstError -match 'Refusing abandoned transaction recovery' -and
            [VmbTransactionMutexHolder]::ActiveThreadCount -eq $baselineThreads) 'first same-process recovery failure abandons without owner-thread residue'
        $sameSecondError = ''
        try { $null = Enter-VmbMachineTransactionLease -Action 'same-second' -Mod 'mod-c' -ProjectRoot $temp -TimeoutMilliseconds 1000 -MutexName $sameMutex -RecordPath $sameRecord }
        catch { $sameSecondError = $_.Exception.Message }
        Assert-Fixture ($sameSecondError -match 'Refusing abandoned transaction recovery' -and
            [VmbTransactionMutexHolder]::ActiveThreadCount -eq $baselineThreads -and
            -not (Test-Path -LiteralPath $sameRecord)) 'second same-process attempt remains fail-closed without a leaked thread'
        $sameKeeper.Dispose()

        # Recovery failure must not normalize an abandoned mutex. Plant a dead
        # owner, remove its durable record, and prove two independent contenders
        # both fail at the abandoned-recovery gate without writing a marker.
        $repeatMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $repeatRecord = Join-Path $temp 'repeat-abandoned-owner.json'
        $repeatOwnerMarker = Join-Path $temp 'repeat-abandoned-owner.marker'
        $repeatCrash = Join-Path $temp 'repeat-abandoned-owner.crash'
        $repeatOwner = Start-Worker $repeatMutex $repeatRecord 'ship' 'mod-a' 5000 $repeatOwnerMarker $repeatCrash '' 'Crash'
        $children += $repeatOwner
        Wait-Marker $repeatOwnerMarker $repeatOwner
        Assert-Fixture ((Test-Path -LiteralPath $repeatRecord) -and (Test-Path -LiteralPath $repeatOwnerMarker)) 'repeat-abandoned fixture leaves a stale durable record'
        Remove-Item -LiteralPath $repeatRecord -Force

        $firstRecoveryMarker = Join-Path $temp 'repeat-abandoned-first.marker'
        $firstReady = $firstRecoveryMarker + '.ready'
        $firstRecovery = Start-Worker $repeatMutex $repeatRecord 'deploy' 'mod-b' 5000 $firstRecoveryMarker '' '' 'Success' '' $firstReady
        $children += $firstRecovery
        $secondRecoveryMarker = Join-Path $temp 'repeat-abandoned-second.marker'
        $secondReady = $secondRecoveryMarker + '.ready'
        $secondRecovery = Start-Worker $repeatMutex $repeatRecord 'upload' 'mod-c' 5000 $secondRecoveryMarker '' '' 'Success' '' $secondReady
        $children += $secondRecovery
        Wait-Marker $firstReady $firstRecovery
        Wait-Marker $secondReady $secondRecovery
        Start-Sleep -Milliseconds 150
        Assert-Fixture (-not (Test-Path -LiteralPath $firstRecoveryMarker) -and
            -not (Test-Path -LiteralPath $secondRecoveryMarker)) 'both recovery contenders queue behind the live owner before mutation'
        [IO.File]::WriteAllText($repeatCrash, 'crash')
        $repeatOwner.WaitForExit()
        $firstRecovery.WaitForExit()
        $secondRecovery.WaitForExit()
        $firstRecovery.Refresh()
        $secondRecovery.Refresh()
        Assert-Fixture ((Read-WorkerError $firstRecoveryMarker) -match 'Refusing abandoned transaction recovery' -and
            -not (Test-Path -LiteralPath $firstRecoveryMarker)) 'first failed abandoned recovery stays fail-closed before mutation'
        Assert-Fixture ((Read-WorkerError $secondRecoveryMarker) -match 'Refusing abandoned transaction recovery' -and
            -not (Test-Path -LiteralPath $secondRecoveryMarker) -and
            -not (Test-Path -LiteralPath $repeatRecord)) 'second contender still sees abandoned recovery instead of overwriting stale authority'

        # Queue the contender before owner death: abandoned Mutex ownership
        # must transfer instead of preserving a permanently unavailable count.
        $queuedMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $queuedRecord = Join-Path $temp 'queued-owner.json'
        $queuedMarker = Join-Path $temp 'queued-owner.marker'
        $queuedTrigger = Join-Path $temp 'queued-owner.crash'
        $queuedOwner = Start-Worker $queuedMutex $queuedRecord 'ship' 'mod-a' 3000 $queuedMarker $queuedTrigger '' 'Crash'
        $children += $queuedOwner
        Wait-Marker $queuedMarker $queuedOwner
        $queuedContenderMarker = Join-Path $temp 'queued-contender.marker'
        $queuedReady = $queuedContenderMarker + '.ready'
        $queuedContender = Start-Worker $queuedMutex $queuedRecord 'deploy' 'mod-b' 5000 $queuedContenderMarker '' '' 'Success' '' $queuedReady
        $children += $queuedContender
        Wait-Marker $queuedReady $queuedContender
        Start-Sleep -Milliseconds 150
        Assert-Fixture (-not (Test-Path -LiteralPath $queuedContenderMarker)) 'pre-existing PowerShell waiter remains blocked before owner death'
        [IO.File]::WriteAllText($queuedTrigger, 'crash')
        $queuedOwner.WaitForExit()
        $queuedContender.WaitForExit()
        Assert-Fixture ((Test-Path -LiteralPath $queuedContenderMarker) -and [string]::IsNullOrWhiteSpace((Read-WorkerError $queuedContenderMarker))) 'pre-existing PowerShell waiter takes abandoned mutex after owner death'

        # The wrapper itself owns a process-lifetime KILL_ON_JOB_CLOSE job.
        # Its child and grandchild must both be dead before the waiting
        # contender is allowed to write its mutation marker.
        $treeMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $treeRecord = Join-Path $temp 'tree-owner.json'
        $treeMarker = Join-Path $temp 'tree-owner.marker'
        $treeTrigger = Join-Path $temp 'tree-owner.crash'
        $treePids = Join-Path $temp 'tree-pids.txt'
        $treeOwner = Start-Worker $treeMutex $treeRecord 'ship' 'mod-a' 3000 $treeMarker $treeTrigger $treePids 'CrashWithChild'
        $children += $treeOwner
        Wait-Marker $treeMarker $treeOwner
        $treeContenderMarker = Join-Path $temp 'tree-contender.marker'
        $treeContender = Start-Worker $treeMutex $treeRecord 'deploy' 'mod-b' 5000 $treeContenderMarker '' '' 'Success' $treePids
        $children += $treeContender
        Start-Sleep -Milliseconds 150
        [IO.File]::WriteAllText($treeTrigger, 'crash')
        $treeOwner.WaitForExit()
        $treeContender.WaitForExit()
        Assert-Fixture ((Test-Path -LiteralPath $treeContenderMarker) -and [string]::IsNullOrWhiteSpace((Read-WorkerError $treeContenderMarker))) 'wrapper child/grandchild are dead before contender mutation begins'

        $normalMutex = 'Global\Ensrick.VMBLauncher.Tests.' + [guid]::NewGuid().ToString('N')
        $normalRecord = Join-Path $temp 'normal-owner.json'
        $normalMarker = Join-Path $temp 'normal-owner.marker'
        $normalRelease = Join-Path $temp 'normal-owner.release'
        $normalPids = Join-Path $temp 'normal-pids.txt'
        $normalOwner = Start-Worker $normalMutex $normalRecord 'ship' 'mod-a' 3000 $normalMarker $normalRelease $normalPids 'SuccessWithResidue'
        $children += $normalOwner
        Wait-Marker $normalMarker $normalOwner
        $normalContenderMarker = Join-Path $temp 'normal-contender.marker'
        $normalContender = Start-Worker $normalMutex $normalRecord 'deploy' 'mod-b' 5000 $normalContenderMarker '' '' 'Success' $normalPids
        $children += $normalContender
        Start-Sleep -Milliseconds 150
        Assert-Fixture (-not (Test-Path -LiteralPath $normalContenderMarker)) 'normal contender waits while owner has lingering descendant'
        [IO.File]::WriteAllText($normalRelease, 'release')
        $normalOwner.WaitForExit()
        $normalContender.WaitForExit()
        Assert-Fixture ((Test-Path -LiteralPath $normalContenderMarker) -and [string]::IsNullOrWhiteSpace((Read-WorkerError $normalContenderMarker))) 'normal release drains lingering child/grandchild before contender mutation'

        Write-Host "[check_machine_transaction_lease -SelfTest] PASS $script:__transactionPassed assertions ($($PSVersionTable.PSVersion))" -ForegroundColor Green
        return 0
    }
    catch {
        Write-Host "[check_machine_transaction_lease -SelfTest] FAILED: $($_.Exception.Message) $($_.ScriptStackTrace)" -ForegroundColor Red
        return 2
    }
    finally {
        foreach ($child in $children) {
            try { if (-not $child.HasExited) { $child.Kill() } } catch { }
            try { $child.Dispose() } catch { }
        }
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
}

if ($SelfTest) { exit (Invoke-MachineTransactionLeaseSelfTest) }
Write-Host '[check_machine_transaction_lease] ERROR -- this check currently supports -SelfTest only.' -ForegroundColor Red
exit 2
