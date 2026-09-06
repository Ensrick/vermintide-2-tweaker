# Offline two-process fixtures for the machine-global VMB/Stingray transaction
# lease. No VMB, Stingray, deploy, staging, Workshop, or network action runs.

[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'

function Invoke-MachineTransactionLeaseSelfTest {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $helper = Join-Path $repoRoot 'tools\ship\transaction-lease.ps1'
    . $helper
    . (Join-Path $repoRoot 'qa\_test_fixtures\publication_handoff_fixture.ps1')
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

    function Wait-RecoveryFixtureOwnerExit {
        param(
            [Parameter(Mandatory = $true)][scriptblock]$SignalExit,
            [Parameter(Mandatory = $true)][scriptblock]$WaitForExit,
            [Parameter(Mandatory = $true)][scriptblock]$HasExited,
            [ValidateRange(1, 60000)][int]$SetupTimeoutMilliseconds = 20000
        )
        # This is fixture setup, not a lease-acquisition/recovery budget. A
        # contender must not spend its semantic wait while its supposed dead
        # owner is still starting/terminating (including crash-report latency).
        $null = & $SignalExit
        $finished = & $WaitForExit $SetupTimeoutMilliseconds
        if ($finished -isnot [bool] -or -not $finished) {
            throw 'repeat-recovery fixture owner did not exit within the setup ceiling'
        }
        $exited = & $HasExited
        if ($exited -isnot [bool] -or -not $exited) {
            throw 'repeat-recovery fixture owner exit postcondition failed'
        }
    }

    function Read-FixtureEvidence {
        param(
            [string]$Path,
            [ValidateRange(1, 16384)][int]$Limit = 4096,
            [scriptblock]$OpenReader = {
                param($file)
                New-Object IO.StreamReader([IO.File]::Open($file, [IO.FileMode]::Open,
                    [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)))
            }
        )
        $reader = $null
        try {
            $reader = & $OpenReader $Path
            $buffer = New-Object char[] ($Limit + 1)
            $count = $reader.ReadBlock($buffer, 0, $buffer.Length)
            if ($count -eq 0) { return '' }
            $text = -join $buffer[0..($count - 1)]
            if ($count -gt $Limit) { return $text.Substring(0, $Limit) + '<truncated>' }
            return $text
        }
        catch [IO.FileNotFoundException] { return '' }
        catch [IO.DirectoryNotFoundException] { return '' }
        catch {
            $message = $_.Exception.Message
            return '<unreadable: ' + $message.Substring(0, [Math]::Min(1024, $message.Length)) + '>'
        }
        finally { if ($null -ne $reader) { try { $reader.Dispose() } catch { } } }
    }

    function Wait-FixtureTerminal {
        param(
            [string]$Name,
            [scriptblock]$WaitForExit,
            [scriptblock]$ReadState,
            [scriptblock]$ReadElapsed,
            [long]$DeadlineMilliseconds
        )
        # Both workers share one observation ceiling. This never changes their
        # 5000ms lease wait or turns a semantic failure into a successful test.
        $remaining = [int][Math]::Max(0, $DeadlineMilliseconds - (& $ReadElapsed))
        $waited = $false
        $errorText = ''
        try {
            $result = & $WaitForExit $remaining
            $waited = $result -is [bool] -and $result
            if (-not $waited) { $errorText = 'terminal wait incomplete' }
        }
        catch { $errorText = 'terminal wait error: ' + $_.Exception.Message }
        $observed = & $ReadElapsed
        $state = @{ Pid = 'unavailable'; HasExited = $false; ExitCode = 'unavailable' }
        try { $state = & $ReadState }
        catch { $errorText += '; state read error: ' + $_.Exception.Message }
        $exited = $null -ne $state -and $state.HasExited -is [bool] -and $state.HasExited
        $errorText = $errorText.Substring(0, [Math]::Min(2048, $errorText.Length))
        $exitCode = if ($null -eq $state.ExitCode -or [string]::IsNullOrWhiteSpace([string]$state.ExitCode)) {
            'unavailable'
        } else { [string]$state.ExitCode }
        [pscustomobject]@{
            Complete = $waited -and $exited
            Detail = "$Name pid=$($state.Pid) exited=$($state.HasExited) exit=$exitCode observed_ms=$observed remaining_ms=$remaining wait_complete=$waited error=[$errorText]"
        }
    }

    function Assert-WorkerExitPath {
        param([string]$Marker, [Diagnostics.Process]$Process, [bool]$HardDeath)
        $hardDeathPath = $Marker + '.hard-death'
        $finallyPath = $Marker + '.finally'
        $hardDeathExists = Test-Path -LiteralPath $hardDeathPath
        $finallyExists = Test-Path -LiteralPath $finallyPath
        $expectedPid = [string]$Process.Id
        if ($HardDeath) {
            Assert-Fixture ($hardDeathExists -and -not $finallyExists -and
                (Read-FixtureEvidence $hardDeathPath) -eq $expectedPid) "worker $expectedPid explicitly hard-terminates without running finally"
        }
        else {
            Assert-Fixture (-not $hardDeathExists -and $finallyExists -and
                (Read-FixtureEvidence $finallyPath) -eq $expectedPid) "ordinary worker $expectedPid executes finally without hard termination"
        }
    }

    $script:__transactionPassed = 0
    $children = @()
    try {
        $helperText = [System.IO.File]::ReadAllText($helper, [System.Text.Encoding]::UTF8)
        $workerText = [IO.File]::ReadAllText($worker, [Text.Encoding]::UTF8)
        Assert-Fixture ($workerText.Contains('[Diagnostics.Process]::GetCurrentProcess().Kill()') -and
            [regex]::Matches($workerText, '\.Kill\s*\(').Count -eq 1 -and
            -not $workerText.Contains('::FailFast(') -and
            $workerText.Contains("[IO.File]::WriteAllText(`$MarkerPath + '.finally',")) 'hard-death injection kills only the worker, avoids FailFast, and retains an observable finally control'
        # Exercise only the sequencing policy here, without real delays or
        # additional processes. A slow successful setup is distinct from a
        # live-owner timeout; the latter must never pass the recovery fixture.
        foreach ($case in @('late-exit', 'wait-timeout', 'false-exit', 'wait-throws')) {
            $state = @{ Trace = @(); NextStep = 0; Budget = 0; Elapsed = 0 }
            $errorText = ''
            try {
                Wait-RecoveryFixtureOwnerExit -SignalExit {
                    $state.Trace += 'signal'
                } -WaitForExit {
                    param($budget)
                    $state.Trace += 'wait'
                    $state.Budget = $budget
                    # Model termination beyond a contender's unchanged 5s
                    # wait, but within this independent 20s setup ceiling.
                    $state.Elapsed = 6000
                    if ($case -eq 'wait-throws') { throw 'planted owner wait failure' }
                    return $case -ne 'wait-timeout'
                } -HasExited {
                    $state.Trace += 'exit-postcondition'
                    return $case -ne 'false-exit'
                }
                $state.NextStep++
            }
            catch { $errorText = $_.Exception.Message }
            if ($case -eq 'late-exit') {
                Assert-Fixture ($state.NextStep -eq 1 -and $state.Budget -eq 20000 -and
                    $state.Elapsed -gt 5000 -and $state.Elapsed -lt $state.Budget -and
                    ($state.Trace -join ',') -eq 'signal,wait,exit-postcondition' -and
                    $errorText -eq '') 'late owner termination completes setup before a fresh contender wait begins'
            }
            else {
                $expectedError = switch ($case) {
                    'wait-timeout' { 'setup ceiling' }
                    'false-exit' { 'exit postcondition' }
                    'wait-throws' { 'planted owner wait failure' }
                }
                $expectedTrace = if ($case -eq 'false-exit') { 'signal,wait,exit-postcondition' } else { 'signal,wait' }
                Assert-Fixture ($state.NextStep -eq 0 -and $state.Budget -eq 20000 -and
                    ($state.Trace -join ',') -eq $expectedTrace -and
                    $errorText -match $expectedError) "$case cannot start a recovery contender"
            }
        }
        # Pure observation checks: no workers, sleeps, or timing injection.
        $observation = @{ Elapsed = 0; Budgets = @() }
        $firstTerminal = Wait-FixtureTerminal 'owner' -DeadlineMilliseconds 20000 -ReadElapsed {
            $observation.Elapsed
        } -WaitForExit {
            param($budget)
            $observation.Budgets += $budget
            $observation.Elapsed = 17000
            return $true
        } -ReadState { @{ Pid = 1; HasExited = $true; ExitCode = -1 } }
        $secondTerminal = Wait-FixtureTerminal 'contender' -DeadlineMilliseconds 20000 -ReadElapsed {
            $observation.Elapsed
        } -WaitForExit {
            param($budget)
            $observation.Budgets += $budget
            $observation.Elapsed = 20000
            return $false
        } -ReadState { @{ Pid = 2; HasExited = $false; ExitCode = 'unavailable' } }
        Assert-Fixture ($firstTerminal.Complete -and -not $secondTerminal.Complete -and
            ($observation.Budgets -join ',') -eq '20000,3000' -and
            $firstTerminal.Detail.Contains('exit=-1') -and
            $secondTerminal.Detail.Contains('terminal wait incomplete')) 'terminal evidence preserves failure and shares one aggregate observation ceiling'
        foreach ($case in @('expired', 'wait-throws', 'state-throws', 'false-exit', 'nonboolean-wait')) {
            $observation.Elapsed = 21000
            $terminal = Wait-FixtureTerminal $case -DeadlineMilliseconds 20000 -ReadElapsed {
                $observation.Elapsed
            } -WaitForExit {
                param($budget)
                $observation.Budgets += $budget
                if ($case -eq 'wait-throws') { throw 'planted wait failure' }
                if ($case -eq 'nonboolean-wait') { return 'true' }
                return $case -ne 'expired'
            } -ReadState {
                if ($case -eq 'state-throws') { throw 'planted state failure' }
                @{ Pid = 3; HasExited = $case -ne 'false-exit'; ExitCode = 7 }
            }
            Assert-Fixture (-not $terminal.Complete -and
                $observation.Budgets[-1] -eq 0 -and $terminal.Detail.Contains($case)) "$case retains terminal failure without an unbounded wait"
        }
        $terminal = Wait-FixtureTerminal 'blank-exit' -DeadlineMilliseconds 20000 -ReadElapsed { 0 } `
            -WaitForExit { $true } -ReadState { @{ Pid = 4; HasExited = $true; ExitCode = $null } }
        Assert-Fixture ($terminal.Complete -and $terminal.Detail.Contains('exit=unavailable')) 'unavailable PowerShell exit codes are not rendered as known empty values'
        $readEvidence = @{ Disposed = 0; Requested = 0; Text = 'Refusing abandoned transaction recovery' }
        $fakeReader = New-Object PSObject
        $fakeReader | Add-Member ScriptMethod ReadBlock {
            param($buffer, $offset, $count)
            $readEvidence.Requested = $count
            $take = [Math]::Min($count, $readEvidence.Text.Length)
            $readEvidence.Text.CopyTo(0, $buffer, $offset, $take)
            return $take
        }
        $fakeReader | Add-Member ScriptMethod Dispose { $readEvidence.Disposed++ }
        foreach ($message in @('Refusing abandoned transaction recovery', 'machine mutex held beyond 5000 ms')) {
            $readEvidence.Text = $message
            $captured = Read-FixtureEvidence 'fake' -Limit 64 -OpenReader { $fakeReader }
            Assert-Fixture ($captured -eq $message -and $readEvidence.Requested -eq 65) 'terminal diagnostics retain exact recovery-refusal and timeout evidence'
        }
        $readEvidence.Text = 'x' * 100
        $captured = Read-FixtureEvidence 'fake' -Limit 16 -OpenReader { $fakeReader }
        Assert-Fixture ($captured -eq (('x' * 16) + '<truncated>') -and
            $readEvidence.Requested -eq 17 -and $readEvidence.Disposed -eq 3) 'diagnostic reads are bounded and readers always close'
        $captured = Read-FixtureEvidence 'fake' -OpenReader { throw 'planted unreadable diagnostic' }
        Assert-Fixture ($captured.Contains('planted unreadable diagnostic')) 'diagnostic read errors remain evidence rather than masking the fixture failure'
        $failingReader = New-Object PSObject
        $failingReader | Add-Member ScriptMethod ReadBlock { throw 'planted reader failure' }
        $failingReader | Add-Member ScriptMethod Dispose { $readEvidence.Disposed++ }
        $captured = Read-FixtureEvidence 'fake' -OpenReader { $failingReader }
        Assert-Fixture ($captured.Contains('planted reader failure') -and
            $readEvidence.Disposed -eq 4) 'diagnostic readers close even when an opened stream fails'
        $fixtureText = [IO.File]::ReadAllText($PSCommandPath, [Text.Encoding]::UTF8)
        $repeatBlockStart = $fixtureText.LastIndexOf("`$repeatMutex = 'Global\Ensrick.VMBLauncher.Tests.'")
        $repeatBlockEnd = $fixtureText.LastIndexOf("`$queuedMutex = 'Global\Ensrick.VMBLauncher.Tests.'")
        $repeatBlock = $fixtureText.Substring($repeatBlockStart, $repeatBlockEnd - $repeatBlockStart)
        $keeperOpen = $repeatBlock.IndexOf('[Threading.Mutex]::OpenExisting($repeatMutex)')
        $ownerExit = $repeatBlock.IndexOf('Wait-RecoveryFixtureOwnerExit -SignalExit')
        $firstStart = $repeatBlock.IndexOf('$firstRecovery = Start-Worker')
        $secondStart = $repeatBlock.IndexOf('$secondRecovery = Start-Worker')
        $keeperDispose = $repeatBlock.IndexOf('$repeatKeeper.Dispose()')
        Assert-Fixture ($keeperOpen -ge 0 -and $ownerExit -gt $keeperOpen -and
            $firstStart -gt $ownerExit -and $secondStart -gt $firstStart -and
            $keeperDispose -gt $secondStart -and
            $repeatBlock.Contains('$repeatOwner.WaitForExit($budget)') -and
            $repeatBlock.Contains('$repeatOwner.HasExited')) 'repeat-recovery fixture preserves the mutex and proves owner death before starting either contender'
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
        $publisherReleaseMutex = $publisherText.IndexOf('Enter-VtGitHubReleaseMutationMutex')
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
        Assert-WorkerExitPath $aMarker $a $false

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
        Assert-WorkerExitPath $failureMarker $failure $false
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
        Assert-WorkerExitPath $crashMarker $crash $true
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
        Assert-WorkerExitPath $freshOwnerMarker $freshOwner $true
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
        Assert-WorkerExitPath $sameOwnerMarker $sameOwner $true
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
        $repeatKeeper = $null
        try {
            # Retain a non-owning parent handle across confirmed owner death,
            # so Windows cannot destroy/recreate the abandoned kernel object.
            # This fixture tests repeated recovery refusal, not live contention
            # (the separate queued-owner and timeout fixtures cover that).
            $repeatKeeper = [Threading.Mutex]::OpenExisting($repeatMutex)
            Assert-Fixture ((Test-Path -LiteralPath $repeatRecord) -and (Test-Path -LiteralPath $repeatOwnerMarker)) 'repeat-abandoned fixture leaves a stale durable record'
            Remove-Item -LiteralPath $repeatRecord -Force
            Wait-RecoveryFixtureOwnerExit -SignalExit {
                [IO.File]::WriteAllText($repeatCrash, 'crash')
            } -WaitForExit {
                param($budget)
                $repeatOwner.WaitForExit($budget)
            } -HasExited {
                $repeatOwner.Refresh()
                $repeatOwner.HasExited
            }
            Assert-WorkerExitPath $repeatOwnerMarker $repeatOwner $true

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
            $firstRecovery.WaitForExit()
            $secondRecovery.WaitForExit()
            $firstRecovery.Refresh()
            $secondRecovery.Refresh()
            $firstRecoveryError = Read-WorkerError $firstRecoveryMarker
            $secondRecoveryError = Read-WorkerError $secondRecoveryMarker
            $firstRecoveryMarkerExists = Test-Path -LiteralPath $firstRecoveryMarker
            $secondRecoveryMarkerExists = Test-Path -LiteralPath $secondRecoveryMarker
            $repeatRecordExists = Test-Path -LiteralPath $repeatRecord
            $repeatTerminalState = "first_exit=$($firstRecovery.ExitCode) first_stderr=[$firstRecoveryError] second_exit=$($secondRecovery.ExitCode) second_stderr=[$secondRecoveryError] first_marker=$firstRecoveryMarkerExists second_marker=$secondRecoveryMarkerExists record=$repeatRecordExists"
            Assert-Fixture ($firstRecovery.ExitCode -ne 0 -and
                $firstRecoveryError -match 'Refusing abandoned transaction recovery' -and
                -not $firstRecoveryMarkerExists) "first failed abandoned recovery stays fail-closed before mutation; $repeatTerminalState"
            Assert-Fixture ($secondRecovery.ExitCode -ne 0 -and
                $secondRecoveryError -match 'Refusing abandoned transaction recovery' -and
                -not $secondRecoveryMarkerExists -and
                -not $repeatRecordExists) "second contender still sees abandoned recovery instead of overwriting stale authority; $repeatTerminalState"
        }
        finally {
            if ($null -ne $repeatKeeper) { $repeatKeeper.Dispose() }
        }

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
        $queuedWatch = [Diagnostics.Stopwatch]::StartNew()
        $queuedContender = Start-Worker $queuedMutex $queuedRecord 'deploy' 'mod-b' 5000 $queuedContenderMarker '' '' 'Success' '' $queuedReady
        $children += $queuedContender
        Wait-Marker $queuedReady $queuedContender
        $queuedReadyElapsed = $queuedWatch.ElapsedMilliseconds
        Start-Sleep -Milliseconds 150
        Assert-Fixture (-not (Test-Path -LiteralPath $queuedContenderMarker)) 'pre-existing PowerShell waiter remains blocked before owner death'
        $queuedTriggerElapsed = $queuedWatch.ElapsedMilliseconds
        [IO.File]::WriteAllText($queuedTrigger, 'crash')
        $queuedDeadline = $queuedTriggerElapsed + 20000
        $ownerTerminal = Wait-FixtureTerminal 'owner' -DeadlineMilliseconds $queuedDeadline -ReadElapsed {
            $queuedWatch.ElapsedMilliseconds
        } -WaitForExit { param($budget) $queuedOwner.WaitForExit($budget) } -ReadState {
            $queuedOwner.Refresh()
            @{ Pid = $queuedOwner.Id; HasExited = $queuedOwner.HasExited;
                ExitCode = $(if ($queuedOwner.HasExited) { $queuedOwner.ExitCode } else { 'unavailable' }) }
        }
        $contenderTerminal = Wait-FixtureTerminal 'contender' -DeadlineMilliseconds $queuedDeadline -ReadElapsed {
            $queuedWatch.ElapsedMilliseconds
        } -WaitForExit { param($budget) $queuedContender.WaitForExit($budget) } -ReadState {
            $queuedContender.Refresh()
            @{ Pid = $queuedContender.Id; HasExited = $queuedContender.HasExited;
                ExitCode = $(if ($queuedContender.HasExited) { $queuedContender.ExitCode } else { 'unavailable' }) }
        }
        $queuedError = Read-FixtureEvidence ($queuedContenderMarker + '.stderr.txt')
        $queuedEvidence = "$($ownerTerminal.Detail); $($contenderTerminal.Detail); ready_ms=$queuedReadyElapsed trigger_ms=$queuedTriggerElapsed ready=$(Test-Path -LiteralPath $queuedReady) trigger=$(Test-Path -LiteralPath $queuedTrigger) owner_marker=$(Test-Path -LiteralPath $queuedMarker) contender_marker=$(Test-Path -LiteralPath $queuedContenderMarker) record=$(Test-Path -LiteralPath $queuedRecord)"
        $queuedEvidence += "; owner_stderr=[$(Read-FixtureEvidence ($queuedMarker + '.stderr.txt'))] owner_stdout=[$(Read-FixtureEvidence ($queuedMarker + '.stdout.txt'))] contender_stderr=[$queuedError] contender_stdout=[$(Read-FixtureEvidence ($queuedContenderMarker + '.stdout.txt'))] record_text=[$(Read-FixtureEvidence $queuedRecord)]"
        $queuedEvidence += "; owner_hard_death=$(Test-Path -LiteralPath ($queuedMarker + '.hard-death')) owner_finally=$(Test-Path -LiteralPath ($queuedMarker + '.finally'))"
        Assert-Fixture ($ownerTerminal.Complete -and $contenderTerminal.Complete -and
            (Test-Path -LiteralPath $queuedContenderMarker) -and [string]::IsNullOrWhiteSpace($queuedError)) "pre-existing PowerShell waiter takes abandoned mutex after owner death; $queuedEvidence"
        Assert-WorkerExitPath $queuedMarker $queuedOwner $true

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
        Assert-WorkerExitPath $treeMarker $treeOwner $true

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
        Assert-WorkerExitPath $normalMarker $normalOwner $false

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
        Remove-VtPublicationHandoffFixtureDirectory -Path $temp -ParentRoot ([IO.Path]::GetTempPath()) `
            -LeafPattern '^vt2-transaction-fixture-[0-9a-f]{32}$'
    }
}

if ($SelfTest) { exit (Invoke-MachineTransactionLeaseSelfTest) }
Write-Host '[check_machine_transaction_lease] ERROR -- this check currently supports -SelfTest only.' -ForegroundColor Red
exit 2
