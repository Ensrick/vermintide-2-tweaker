# Optional ordinary-QA / required release freshness gate for weapon-history
# source provenance. It reads the canonical remote with git ls-remote only:
# no fetch, no FETCH_HEAD write, and no mutation of a source checkout.
# Ordinary QA (no -RequireRemoteFresh) blocks a reachable ref/tip move only when
# the checked change set touches weapon-history inputs or a WT stream; any other
# change set gets a visible advisory (exit 1). See wt_history_freshness_scope.ps1
# and issue #1683. -Staged scopes that change set to the index (pre-commit).
# SELFTEST-OWNER: run_wt_history_source_host_matrix.ps1

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateRange(1000, 60000)][int]$TimeoutMilliseconds = 15000,
    [switch]$RequireRemoteFresh,
    [switch]$Offline,
    [switch]$Staged,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$anchorHelpers = Join-Path $RepoRoot 'tools\weapon-history\source-anchor.ps1'
if (-not (Test-Path -LiteralPath $anchorHelpers -PathType Leaf)) {
    throw "Weapon-history anchor helpers not found: $anchorHelpers"
}
. $anchorHelpers
$scopeHelpers = Join-Path $PSScriptRoot 'wt_history_freshness_scope.ps1'
if (-not (Test-Path -LiteralPath $scopeHelpers -PathType Leaf)) {
    throw "Weapon-history freshness scope helpers not found: $scopeHelpers"
}
. $scopeHelpers

function New-FreshnessResult([string]$State, [string]$Message, [bool]$Moved = $false) {
    return [pscustomobject]@{ State = $State; Message = $Message; Moved = $Moved }
}

function Test-WtHistoryRemoteProbe {
    param(
        [Parameter(Mandatory)]$Anchor,
        [Parameter(Mandatory)]$Probe,
        [switch]$Required
    )

    if ($Probe.TimedOut -or $Probe.ExitCode -ne 0) {
        $terminationUnproven = $Probe.PSObject.Properties['TerminationProven'] -and
            -not [bool]$Probe.TerminationProven
        $detail = if ($Probe.TimedOut -and $terminationUnproven) {
            $suffix = if ($Probe.PSObject.Properties['TerminationError'] -and
                $Probe.TerminationError) { ": $($Probe.TerminationError)" } else { '' }
            "remote probe timed out; child termination could not be proven$suffix"
        }
        elseif ($Probe.TimedOut) { 'remote probe timed out after bounded termination' }
        elseif ($terminationUnproven) {
            "git ls-remote failed and child termination could not be proven"
        }
        else { "git ls-remote exited $($Probe.ExitCode)" }
        if ($Required) {
            return New-FreshnessResult 'fail' "$detail; required release freshness is unavailable"
        }
        return New-FreshnessResult 'skip' "$detail; pinned offline provenance remains enforced"
    }

    $lines = @([regex]::Split([string]$Probe.Stdout, "\r?\n") |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $symrefs = @($lines | Where-Object {
        $_ -match '^ref:\s+(refs/heads/[A-Za-z0-9._/-]+)\s+HEAD$'
    })
    $tips = @($lines | Where-Object { $_ -match '^([0-9a-f]{40})\s+HEAD$' })
    if ($symrefs.Count -ne 1 -or $tips.Count -ne 1 -or $lines.Count -ne 2) {
        return New-FreshnessResult 'fail' 'canonical remote returned malformed or ambiguous HEAD identity'
    }
    $null = $symrefs[0] -match '^ref:\s+(refs/heads/[A-Za-z0-9._/-]+)\s+HEAD$'
    $remoteRef = $Matches[1]
    $null = $tips[0] -match '^([0-9a-f]{40})\s+HEAD$'
    $remoteTip = $Matches[1]
    if ($remoteRef -cne $Anchor.DefaultRef) {
        return New-FreshnessResult 'fail' `
            "canonical default ref moved: pinned=$($Anchor.DefaultRef) remote=$remoteRef" $true
    }
    if ($remoteTip -cne $Anchor.ObservedDefaultTip) {
        return New-FreshnessResult 'fail' `
            "canonical default tip moved: pinned=$($Anchor.ObservedDefaultTip) remote=$remoteTip" $true
    }
    return New-FreshnessResult 'pass' `
        "canonical default tip matches $remoteTip (semantic $($Anchor.GameVersion) content $($Anchor.ContentRevision))"
}

function New-WtHistoryTaskkillStartInfo {
    param([Parameter(Mandatory)][int]$TargetPid)

    if ($TargetPid -le 0) { throw "invalid taskkill target PID: $TargetPid" }
    if ([string]::IsNullOrWhiteSpace($env:SystemRoot)) {
        throw 'SystemRoot is unavailable; cannot resolve trusted taskkill.exe'
    }
    $taskkillPath = Join-Path $env:SystemRoot 'System32\taskkill.exe'
    if (-not (Test-Path -LiteralPath $taskkillPath -PathType Leaf)) {
        throw "trusted taskkill.exe is unavailable: $taskkillPath"
    }

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $taskkillPath
    $start.Arguments = "/PID $TargetPid /T /F"
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    return $start
}

function Get-WtHistoryProcessIdentityState {
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][long]$StartTimeFileTimeUtc
    )

    if ($ProcessId -le 0 -or $StartTimeFileTimeUtc -le 0) {
        return 'unavailable'
    }

    $observed = $null
    try {
        $observed = [System.Diagnostics.Process]::GetProcessById($ProcessId)
        if ($observed.HasExited) { return 'gone' }
        $observedStart = [long]$observed.StartTime.ToFileTimeUtc()
        if ($observedStart -ne $StartTimeFileTimeUtc) { return 'reused' }
        if ($observed.HasExited) { return 'gone' }
        return 'alive'
    }
    catch [System.ArgumentException] {
        return 'gone'
    }
    catch [System.InvalidOperationException] {
        # The exact process can exit between GetProcessById/HasExited/StartTime.
        return 'gone'
    }
    catch {
        # Access denial or an unknown observation failure cannot prove absence.
        return 'unavailable'
    }
    finally {
        if ($observed) { $observed.Dispose() }
    }
}

function New-WtHistoryProbeDeadlinePlan {
    param([ValidateRange(1000, 60000)][int]$TimeoutMilliseconds)

    # The production default keeps eleven seconds for the network probe, then
    # gives taskkill three seconds and one final second to either contain a
    # timed-out helper or prove the successfully killed root is gone. Those two
    # proof outcomes are mutually exclusive, so they share one final bucket.
    $terminationMilliseconds = [Math]::Min(4000,
        [int][Math]::Floor($TimeoutMilliseconds * 3.0 / 4.0))
    $postProofMilliseconds = [Math]::Min(1000,
        [Math]::Max(250,
            [int][Math]::Ceiling($terminationMilliseconds / 4.0)))
    $networkMilliseconds = $TimeoutMilliseconds - $terminationMilliseconds
    $taskkillMilliseconds = $terminationMilliseconds - $postProofMilliseconds

    return [pscustomobject]@{
        TotalMilliseconds = $TimeoutMilliseconds
        NetworkMilliseconds = $networkMilliseconds
        TaskkillMilliseconds = $taskkillMilliseconds
        PostProofMilliseconds = $postProofMilliseconds
        NetworkDeadlineMilliseconds = $networkMilliseconds
        TaskkillDeadlineMilliseconds = $networkMilliseconds + $taskkillMilliseconds
        TotalDeadlineMilliseconds = $TimeoutMilliseconds
    }
}

function Get-WtHistoryDeadlineRemainingMilliseconds {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Clock,
        [ValidateRange(0, 60000)][int]$DeadlineMilliseconds,
        $Timing
    )

    # Ceiling makes every wait conservative: fractional elapsed milliseconds
    # are charged before asking the OS to wait again.
    $elapsedMilliseconds = if ($Timing -and
        $Timing.PSObject.Properties['GetElapsedMilliseconds']) {
        $getElapsed = $Timing.GetElapsedMilliseconds
        [int][Math]::Ceiling([double](& $getElapsed))
    } else {
        [int][Math]::Ceiling($Clock.Elapsed.TotalMilliseconds)
    }
    if ($elapsedMilliseconds -lt 0) {
        throw 'injected elapsed milliseconds cannot be negative'
    }
    return [Math]::Max(0, $DeadlineMilliseconds - $elapsedMilliseconds)
}

function Invoke-WtHistoryProcessWait {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [ValidateRange(1, 60000)][int]$Milliseconds,
        [Parameter(Mandatory)][string]$Phase,
        $Timing
    )

    if ($Timing -and $Timing.PSObject.Properties['WaitForExit']) {
        $waitForExit = $Timing.WaitForExit
        return [bool](& $waitForExit $Process $Milliseconds $Phase)
    }
    return [bool]$Process.WaitForExit($Milliseconds)
}

function Invoke-WtHistoryTaskWait {
    param(
        [Parameter(Mandatory)][System.Threading.Tasks.Task]$Task,
        [ValidateRange(0, 60000)][int]$Milliseconds,
        [Parameter(Mandatory)][string]$Phase,
        $Timing
    )

    if ($Timing -and $Timing.PSObject.Properties['WaitForTask']) {
        $waitForTask = $Timing.WaitForTask
        return [bool](& $waitForTask $Task $Milliseconds $Phase)
    }
    return [bool]$Task.Wait($Milliseconds)
}

function Invoke-WtHistoryProcessKill {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][string]$Phase,
        $Timing
    )

    if ($Timing -and $Timing.PSObject.Properties['ObserveKill']) {
        $observeKill = $Timing.ObserveKill
        & $observeKill $Process $Phase
    }
    $Process.Kill()
}

function Invoke-WtHistoryBoundedTaskkill {
    param(
        [Parameter(Mandatory)][int]$TargetPid,
        [Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Clock,
        [ValidateRange(0, 60000)][int]$TaskkillDeadlineMilliseconds,
        [ValidateRange(0, 60000)][int]$TotalDeadlineMilliseconds,
        [System.Diagnostics.ProcessStartInfo]$StartInfoOverride,
        $Timing
    )

    $helper = New-Object System.Diagnostics.Process
    $started = $false
    $helperPid = -1
    [long]$helperStartTimeFileTimeUtc = -1
    try {
        if ($TaskkillDeadlineMilliseconds -gt $TotalDeadlineMilliseconds) {
            throw 'taskkill deadline exceeds the total probe deadline'
        }
        $runRemaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $Clock -DeadlineMilliseconds $TaskkillDeadlineMilliseconds `
            -Timing $Timing
        if ($runRemaining -le 0) {
            return [pscustomobject]@{
                Succeeded = $false
                ExitCode = -1
                TimedOut = $true
                TerminationProven = $true
                Error = 'no bounded budget remains for process-tree taskkill'
                ProcessId = -1
                StartTimeFileTimeUtc = -1
            }
        }

        $helper.StartInfo = if ($StartInfoOverride) {
            $StartInfoOverride
        } else {
            New-WtHistoryTaskkillStartInfo -TargetPid $TargetPid
        }
        if (-not $helper.Start()) { throw 'taskkill helper did not start' }
        $started = $true
        $helperPid = $helper.Id
        $helperStartTimeFileTimeUtc = [long]$helper.StartTime.ToFileTimeUtc()
        $stdoutTask = $helper.StandardOutput.ReadToEndAsync()
        $stderrTask = $helper.StandardError.ReadToEndAsync()

        # Helper start time is charged to its absolute phase deadline. The
        # final shared bucket remains available only for containment if this
        # helper misses that deadline.
        $runRemaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $Clock -DeadlineMilliseconds $TaskkillDeadlineMilliseconds `
            -Timing $Timing
        $helperExited = if ($helper.HasExited) { $true }
        elseif ($runRemaining -gt 0) {
            Invoke-WtHistoryProcessWait -Process $helper `
                -Milliseconds $runRemaining -Phase 'taskkill-action' `
                -Timing $Timing
        }
        else { $helper.HasExited }
        if (-not $helperExited) {
            $killError = ''
            try {
                if (-not $helper.HasExited) {
                    Invoke-WtHistoryProcessKill -Process $helper `
                        -Phase 'taskkill-helper-timeout' -Timing $Timing
                }
            }
            catch { $killError = $_.Exception.Message }

            $remaining = Get-WtHistoryDeadlineRemainingMilliseconds `
                -Clock $Clock -DeadlineMilliseconds $TotalDeadlineMilliseconds `
                -Timing $Timing
            $helperProven = $false
            try {
                $helperProven = if ($helper.HasExited) { $true }
                elseif ($remaining -gt 0) {
                    Invoke-WtHistoryProcessWait -Process $helper `
                        -Milliseconds $remaining -Phase 'taskkill-containment' `
                        -Timing $Timing
                }
                else { $helper.HasExited }
            }
            catch {
                if (-not $killError) { $killError = $_.Exception.Message }
            }
            $detail = 'taskkill helper timed out'
            if (-not $helperProven) { $detail += '; helper termination unproven' }
            if ($killError) { $detail += ": $killError" }
            return [pscustomobject]@{
                Succeeded = $false
                ExitCode = -1
                TimedOut = $true
                TerminationProven = [bool]$helperProven
                Error = $detail
                ProcessId = $helperPid
                StartTimeFileTimeUtc = $helperStartTimeFileTimeUtc
            }
        }

        $remaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $Clock -DeadlineMilliseconds $TaskkillDeadlineMilliseconds `
            -Timing $Timing
        $stdoutComplete = Invoke-WtHistoryTaskWait -Task $stdoutTask `
            -Milliseconds $remaining -Phase 'taskkill-output-stdout' `
            -Timing $Timing
        $remaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $Clock -DeadlineMilliseconds $TaskkillDeadlineMilliseconds `
            -Timing $Timing
        $stderrComplete = Invoke-WtHistoryTaskWait -Task $stderrTask `
            -Milliseconds $remaining -Phase 'taskkill-output-stderr' `
            -Timing $Timing
        if (-not $stdoutComplete -or -not $stderrComplete) {
            return [pscustomobject]@{
                Succeeded = $false
                ExitCode = $helper.ExitCode
                TimedOut = $true
                TerminationProven = $true
                Error = 'taskkill helper output drain exceeded its total budget'
                ProcessId = $helperPid
                StartTimeFileTimeUtc = $helperStartTimeFileTimeUtc
            }
        }

        $stdout = [string]$stdoutTask.Result
        $stderr = [string]$stderrTask.Result
        if ($helper.ExitCode -ne 0) {
            $detailParts = @($stderr.Trim(), $stdout.Trim()) |
                Where-Object { $_ }
            $detail = $detailParts -join '; '
            if ($detail.Length -gt 512) { $detail = $detail.Substring(0, 512) }
            return [pscustomobject]@{
                Succeeded = $false
                ExitCode = $helper.ExitCode
                TimedOut = $false
                TerminationProven = $true
                Error = "taskkill helper exited $($helper.ExitCode): $detail"
                ProcessId = $helperPid
                StartTimeFileTimeUtc = $helperStartTimeFileTimeUtc
            }
        }
        return [pscustomobject]@{
            Succeeded = $true
            ExitCode = 0
            TimedOut = $false
            TerminationProven = $true
            Error = ''
            ProcessId = $helperPid
            StartTimeFileTimeUtc = $helperStartTimeFileTimeUtc
        }
    }
    catch {
        $helperProven = -not $started
        if ($started) {
            try {
                if (-not $helper.HasExited) {
                    Invoke-WtHistoryProcessKill -Process $helper `
                        -Phase 'taskkill-helper-exception' -Timing $Timing
                }
                $remaining = Get-WtHistoryDeadlineRemainingMilliseconds `
                    -Clock $Clock -DeadlineMilliseconds $TotalDeadlineMilliseconds `
                    -Timing $Timing
                $helperProven = if ($helper.HasExited) { $true }
                elseif ($remaining -gt 0) {
                    Invoke-WtHistoryProcessWait -Process $helper `
                        -Milliseconds $remaining `
                        -Phase 'taskkill-exception-containment' -Timing $Timing
                }
                else { $helper.HasExited }
            }
            catch { $helperProven = $false }
        }
        return [pscustomobject]@{
            Succeeded = $false
            ExitCode = -1
            TimedOut = $false
            TerminationProven = [bool]$helperProven
            Error = "taskkill helper failed: $($_.Exception.Message)"
            ProcessId = $helperPid
            StartTimeFileTimeUtc = $helperStartTimeFileTimeUtc
        }
    }
    finally {
        $helper.Dispose()
    }
}

function Stop-WtHistoryProbeProcess {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)][System.Diagnostics.Stopwatch]$Clock,
        [ValidateRange(0, 60000)][int]$TaskkillDeadlineMilliseconds,
        [ValidateRange(0, 60000)][int]$TotalDeadlineMilliseconds,
        [System.Diagnostics.ProcessStartInfo]$TaskkillStartInfoOverride,
        [switch]$ForceTaskkill,
        $Timing
    )

    $treeKillAttempted = $false
    $treeKillMethodName = ''
    $taskkillResult = $null
    try {
        if ($Process.HasExited) {
            return [pscustomobject]@{
                Proven = $false
                Error = 'target root exited before process-tree termination could be proven'
                TreeKillAttempted = $false
                TreeKillMethod = ''
                TaskkillProcessId = -1
                TaskkillStartTimeFileTimeUtc = -1
                TaskkillTerminationProven = $true
                TaskkillTimedOut = $false
                TaskkillExitCode = -1
            }
        }
    }
    catch {
        return [pscustomobject]@{
            Proven = $false; Error = $_.Exception.Message; TreeKillAttempted = $false
            TreeKillMethod = ''; TaskkillProcessId = -1
            TaskkillStartTimeFileTimeUtc = -1
            TaskkillTerminationProven = $true; TaskkillTimedOut = $false
            TaskkillExitCode = -1
        }
    }

    $treeKillMethod = @($Process.GetType().GetMethods() | Where-Object {
            $_.Name -ceq 'Kill' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType -eq [bool]
        } | Select-Object -First 1)
    if (-not $ForceTaskkill -and $treeKillMethod.Count -eq 1) {
        try {
            $treeKillAttempted = $true
            $treeKillMethodName = 'Process.Kill(true)'
            $treeKillMethod[0].Invoke($Process, [object[]]@($true)) | Out-Null
        }
        catch {
            return [pscustomobject]@{
                Proven = $false
                Error = "Process.Kill(true) failed: $($_.Exception.Message)"
                TreeKillAttempted = $true
                TreeKillMethod = $treeKillMethodName
                TaskkillProcessId = -1
                TaskkillStartTimeFileTimeUtc = -1
                TaskkillTerminationProven = $true
                TaskkillTimedOut = $false
                TaskkillExitCode = -1
            }
        }
    }
    else {
        # Windows PowerShell 5.1 has only Process.Kill(), which cannot prove
        # descendant termination. Use the trusted system taskkill with /T /F,
        # capture its result, and keep its execution plus conditional helper
        # containment inside the caller's one absolute deadline.
        $treeKillAttempted = $true
        $treeKillMethodName = 'taskkill.exe /T /F'
        $taskkillResult = Invoke-WtHistoryBoundedTaskkill `
            -TargetPid $Process.Id -Clock $Clock `
            -TaskkillDeadlineMilliseconds $TaskkillDeadlineMilliseconds `
            -TotalDeadlineMilliseconds $TotalDeadlineMilliseconds `
            -StartInfoOverride $TaskkillStartInfoOverride -Timing $Timing
        if (-not $taskkillResult.Succeeded) {
            return [pscustomobject]@{
                Proven = $false
                Error = [string]$taskkillResult.Error
                TreeKillAttempted = $true
                TreeKillMethod = $treeKillMethodName
                TaskkillProcessId = [int]$taskkillResult.ProcessId
                TaskkillStartTimeFileTimeUtc = [long]$taskkillResult.StartTimeFileTimeUtc
                TaskkillTerminationProven = [bool]$taskkillResult.TerminationProven
                TaskkillTimedOut = [bool]$taskkillResult.TimedOut
                TaskkillExitCode = [int]$taskkillResult.ExitCode
            }
        }
    }

    try {
        # A successful action may donate unused taskkill time to root proof;
        # the total deadline never moves. A timed-out helper instead consumes
        # the same remaining interval for its own containment and returns
        # without attempting root proof.
        $remaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $Clock -DeadlineMilliseconds $TotalDeadlineMilliseconds `
            -Timing $Timing
        $proven = if ($Process.HasExited) { $true }
        elseif ($remaining -gt 0) {
            Invoke-WtHistoryProcessWait -Process $Process `
                -Milliseconds $remaining -Phase 'root-proof' -Timing $Timing
        } else { $Process.HasExited }
        return [pscustomobject]@{
            Proven = [bool]$proven
            Error = if ($proven) { '' } else { 'bounded post-tree-kill wait expired' }
            TreeKillAttempted = $treeKillAttempted
            TreeKillMethod = $treeKillMethodName
            TaskkillProcessId = if ($taskkillResult) {
                [int]$taskkillResult.ProcessId
            } else { -1 }
            TaskkillStartTimeFileTimeUtc = if ($taskkillResult) {
                [long]$taskkillResult.StartTimeFileTimeUtc
            } else { -1 }
            TaskkillTerminationProven = if ($taskkillResult) {
                [bool]$taskkillResult.TerminationProven
            } else { $true }
            TaskkillTimedOut = if ($taskkillResult) {
                [bool]$taskkillResult.TimedOut
            } else { $false }
            TaskkillExitCode = if ($taskkillResult) {
                [int]$taskkillResult.ExitCode
            } else { -1 }
        }
    }
    catch {
        return [pscustomobject]@{
            Proven = $false
            Error = $_.Exception.Message
            TreeKillAttempted = $treeKillAttempted
            TreeKillMethod = $treeKillMethodName
            TaskkillProcessId = if ($taskkillResult) {
                [int]$taskkillResult.ProcessId
            } else { -1 }
            TaskkillStartTimeFileTimeUtc = if ($taskkillResult) {
                [long]$taskkillResult.StartTimeFileTimeUtc
            } else { -1 }
            TaskkillTerminationProven = if ($taskkillResult) {
                [bool]$taskkillResult.TerminationProven
            } else { $true }
            TaskkillTimedOut = if ($taskkillResult) {
                [bool]$taskkillResult.TimedOut
            } else { $false }
            TaskkillExitCode = if ($taskkillResult) {
                [int]$taskkillResult.ExitCode
            } else { -1 }
        }
    }
}

function Invoke-WtHistoryBoundedProcessProbe {
    param(
        [Parameter(Mandatory)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [ValidateRange(1000, 60000)][int]$TimeoutMs,
        [System.Diagnostics.ProcessStartInfo]$TaskkillStartInfoOverride,
        [switch]$ForceTaskkill,
        $Timing
    )

    # One monotonic stopwatch owns the advertised total budget. Every phase
    # waits only to an absolute deadline, so process startup and prior work are
    # charged before another bounded wait begins.
    $plan = New-WtHistoryProbeDeadlinePlan -TimeoutMilliseconds $TimeoutMs
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $StartInfo
    $started = $false
    $processId = -1
    [long]$processStartTimeFileTimeUtc = -1
    try {
        if (-not $process.Start()) { throw 'probe process did not start' }
        $started = $true
        $processId = $process.Id
        $processStartTimeFileTimeUtc = [long]$process.StartTime.ToFileTimeUtc()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $networkRemaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $clock `
            -DeadlineMilliseconds $plan.NetworkDeadlineMilliseconds `
            -Timing $Timing
        $processExited = if ($process.HasExited) { $true }
        elseif ($networkRemaining -gt 0) {
            Invoke-WtHistoryProcessWait -Process $process `
                -Milliseconds $networkRemaining -Phase 'network-probe' `
                -Timing $Timing
        }
        else { $process.HasExited }
        if (-not $processExited) {
            $termination = Stop-WtHistoryProbeProcess -Process $process `
                -Clock $clock `
                -TaskkillDeadlineMilliseconds $plan.TaskkillDeadlineMilliseconds `
                -TotalDeadlineMilliseconds $plan.TotalDeadlineMilliseconds `
                -TaskkillStartInfoOverride $TaskkillStartInfoOverride `
                -ForceTaskkill:$ForceTaskkill -Timing $Timing
            return [pscustomobject]@{
                ExitCode = -1
                Stdout = ''
                Stderr = ''
                TimedOut = $true
                TerminationProven = [bool]$termination.Proven
                TerminationError = [string]$termination.Error
                KillAttempted = $true
                TreeKillAttempted = [bool]$termination.TreeKillAttempted
                TreeKillMethod = [string]$termination.TreeKillMethod
                TaskkillProcessId = [int]$termination.TaskkillProcessId
                TaskkillStartTimeFileTimeUtc = [long]$termination.TaskkillStartTimeFileTimeUtc
                TaskkillTerminationProven = [bool]$termination.TaskkillTerminationProven
                TaskkillTimedOut = [bool]$termination.TaskkillTimedOut
                TaskkillExitCode = [int]$termination.TaskkillExitCode
                ProcessId = $processId
                ProcessStartTimeFileTimeUtc = $processStartTimeFileTimeUtc
            }
        }

        $remaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $clock -DeadlineMilliseconds $plan.NetworkDeadlineMilliseconds `
            -Timing $Timing
        $stdoutComplete = Invoke-WtHistoryTaskWait -Task $stdoutTask `
            -Milliseconds $remaining -Phase 'network-output-stdout' `
            -Timing $Timing
        $remaining = Get-WtHistoryDeadlineRemainingMilliseconds `
            -Clock $clock -DeadlineMilliseconds $plan.NetworkDeadlineMilliseconds `
            -Timing $Timing
        $stderrComplete = Invoke-WtHistoryTaskWait -Task $stderrTask `
            -Milliseconds $remaining -Phase 'network-output-stderr' `
            -Timing $Timing
        if (-not $stdoutComplete -or -not $stderrComplete) {
            return [pscustomobject]@{
                ExitCode = -1
                Stdout = ''
                Stderr = 'bounded output drain expired'
                TimedOut = $true
                TerminationProven = $false
                TerminationError = 'output drain expired after root exit; descendant termination unproven'
                KillAttempted = $false
                TreeKillAttempted = $false
                TreeKillMethod = ''
                TaskkillProcessId = -1
                TaskkillStartTimeFileTimeUtc = -1
                TaskkillTerminationProven = $true
                TaskkillTimedOut = $false
                TaskkillExitCode = -1
                ProcessId = $processId
                ProcessStartTimeFileTimeUtc = $processStartTimeFileTimeUtc
            }
        }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout = [string]$stdoutTask.Result
            Stderr = [string]$stderrTask.Result
            TimedOut = $false
            TerminationProven = $true
            TerminationError = ''
            KillAttempted = $false
            TreeKillAttempted = $false
            TreeKillMethod = ''
            TaskkillProcessId = -1
            TaskkillStartTimeFileTimeUtc = -1
            TaskkillTerminationProven = $true
            TaskkillTimedOut = $false
            TaskkillExitCode = -1
            ProcessId = $processId
            ProcessStartTimeFileTimeUtc = $processStartTimeFileTimeUtc
        }
    }
    catch {
        $termination = [pscustomobject]@{
            Proven = (-not $started)
            Error = ''
            TreeKillAttempted = $false
            TreeKillMethod = ''
            TaskkillProcessId = -1
            TaskkillStartTimeFileTimeUtc = -1
            TaskkillTerminationProven = $true
            TaskkillTimedOut = $false
            TaskkillExitCode = -1
        }
        if ($started) {
            $termination = Stop-WtHistoryProbeProcess -Process $process `
                -Clock $clock `
                -TaskkillDeadlineMilliseconds $plan.TaskkillDeadlineMilliseconds `
                -TotalDeadlineMilliseconds $plan.TotalDeadlineMilliseconds `
                -TaskkillStartInfoOverride $TaskkillStartInfoOverride `
                -ForceTaskkill:$ForceTaskkill -Timing $Timing
        }
        return [pscustomobject]@{
            ExitCode = -1
            Stdout = ''
            Stderr = $_.Exception.Message
            TimedOut = $false
            TerminationProven = [bool]$termination.Proven
            TerminationError = [string]$termination.Error
            KillAttempted = [bool]$started
            TreeKillAttempted = [bool]$termination.TreeKillAttempted
            TreeKillMethod = [string]$termination.TreeKillMethod
            TaskkillProcessId = [int]$termination.TaskkillProcessId
            TaskkillStartTimeFileTimeUtc = [long]$termination.TaskkillStartTimeFileTimeUtc
            TaskkillTerminationProven = [bool]$termination.TaskkillTerminationProven
            TaskkillTimedOut = [bool]$termination.TaskkillTimedOut
            TaskkillExitCode = [int]$termination.TaskkillExitCode
            ProcessId = $processId
            ProcessStartTimeFileTimeUtc = $processStartTimeFileTimeUtc
        }
    }
    finally {
        $clock.Stop()
        $process.Dispose()
    }
}

function Invoke-WtHistoryRemoteProbe {
    param([Parameter(Mandatory)]$Anchor, [int]$TimeoutMs)

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = 'git'
    $start.Arguments = 'ls-remote --symref "' + $Anchor.CanonicalUrl + '" HEAD'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    return Invoke-WtHistoryBoundedProcessProbe -StartInfo $start -TimeoutMs $TimeoutMs
}

function Invoke-FreshnessSelfTest {
    $failures = New-Object 'System.Collections.Generic.List[string]'
    $latencyDiagnostics = New-Object 'System.Collections.Generic.List[string]'
    $fixtureIdentities = New-Object 'System.Collections.Generic.List[object]'
    $helperIdentities = New-Object 'System.Collections.Generic.List[object]'
    $fixturePidPaths = New-Object 'System.Collections.Generic.List[string]'
    $anchor = [pscustomobject]@{
        DefaultRef = 'refs/heads/master'
        ObservedDefaultTip = ('a' * 40)
        ContentRevision = ('b' * 40)
        GameVersion = '9.9.9'
    }
    function Assert-State([string]$Name, $Probe, [bool]$Required, [string]$Expected) {
        $result = Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $Probe -Required:$Required
        if ($result.State -cne $Expected) {
            $failures.Add("$Name expected=$Expected actual=$($result.State): $($result.Message)") |
                Out-Null
        }
    }
    function Get-OrdinalOccurrenceCount([string]$Text, [string]$Needle) {
        if ([string]::IsNullOrEmpty($Needle)) { throw 'occurrence needle is empty' }
        $count = 0
        $offset = 0
        while ($offset -lt $Text.Length) {
            $hit = $Text.IndexOf($Needle, $offset, [StringComparison]::Ordinal)
            if ($hit -lt 0) { break }
            $count++
            $offset = $hit + $Needle.Length
        }
        return $count
    }
    function Add-LatencyDiagnostic([string]$Name, [long]$Elapsed, [long]$Allowance) {
        if ($Elapsed -gt $Allowance) {
            $latencyDiagnostics.Add("$Name scheduler/OS latency exceeded the non-contract observation threshold: elapsed=${Elapsed}ms threshold=${Allowance}ms") | Out-Null
        }
    }
    function Get-RealTaskkillFixtureOutcome($Termination) {
        if ($null -eq $Termination) {
            return [pscustomobject]@{
                Kind = 'invalid'
                Reason = 'missing termination result'
            }
        }
        $requiredTypes = [ordered]@{
            Proven = [bool]
            Error = [string]
            TreeKillAttempted = [bool]
            TreeKillMethod = [string]
            TaskkillProcessId = [int]
            TaskkillStartTimeFileTimeUtc = [long]
            TaskkillTerminationProven = [bool]
            TaskkillTimedOut = [bool]
            TaskkillExitCode = [int]
        }
        foreach ($name in $requiredTypes.Keys) {
            $property = $Termination.PSObject.Properties[$name]
            if (-not $property) {
                return [pscustomobject]@{
                    Kind = 'invalid'
                    Reason = "missing $name"
                }
            }
            if (-not $requiredTypes[$name].IsInstanceOfType($property.Value)) {
                $actualType = if ($null -eq $property.Value) {
                    '<null>'
                } else {
                    $property.Value.GetType().FullName
                }
                return [pscustomobject]@{
                    Kind = 'invalid'
                    Reason = "$name has type $actualType"
                }
            }
        }

        if (-not $Termination.TreeKillAttempted -or
            $Termination.TreeKillMethod -cne 'taskkill.exe /T /F' -or
            $Termination.TaskkillProcessId -le 0 -or
            $Termination.TaskkillStartTimeFileTimeUtc -le 0 -or
            -not $Termination.TaskkillTerminationProven) {
            return [pscustomobject]@{
                Kind = 'invalid'
                Reason = 'taskkill method/helper identity/containment is not exact'
            }
        }
        if ($Termination.Proven -and $Termination.Error -ceq '' -and
            -not $Termination.TaskkillTimedOut -and
            $Termination.TaskkillExitCode -eq 0) {
            return [pscustomobject]@{ Kind = 'success'; Reason = '' }
        }
        if (-not $Termination.Proven -and
            $Termination.Error -ceq 'taskkill helper timed out' -and
            $Termination.TaskkillTimedOut -and
            $Termination.TaskkillExitCode -eq -1) {
            return [pscustomobject]@{
                Kind = 'scheduler-timeout'
                Reason = 'deadline expired after exact helper containment'
            }
        }
        return [pscustomobject]@{
            Kind = 'invalid'
            Reason = 'outcome is neither exact success nor exact contained deadline timeout'
        }
    }

    # The production helper constructor is tested without starting a process:
    # only the trusted system binary and exact noninteractive /T /F contract
    # may reach the real Windows PowerShell 5.1 taskkill integration fixtures.
    try {
        $taskkillTargetPid = 424242
        $taskkillStartInfo = New-WtHistoryTaskkillStartInfo `
            -TargetPid $taskkillTargetPid
        $expectedTaskkillPath = Join-Path $env:SystemRoot `
            'System32\taskkill.exe'
        if ($taskkillStartInfo.FileName -cne $expectedTaskkillPath -or
            $taskkillStartInfo.Arguments -cne
                "/PID $taskkillTargetPid /T /F" -or
            $taskkillStartInfo.UseShellExecute -ne $false -or
            $taskkillStartInfo.CreateNoWindow -ne $true -or
            $taskkillStartInfo.RedirectStandardOutput -ne $true -or
            $taskkillStartInfo.RedirectStandardError -ne $true) {
            $failures.Add("trusted taskkill start-info contract drifted: $($taskkillStartInfo | Out-String)") | Out-Null
        }
    }
    catch {
        $failures.Add("trusted taskkill start-info fixture failed: $($_.Exception.Message)") |
            Out-Null
    }

    # Pin the only two accepted real-taskkill result shapes. In particular,
    # nonzero, malformed, or helper-unproven outcomes remain failures even
    # though the final fixture cleanup can still contain their target safely.
    $syntheticTaskkillSuccess = [pscustomobject]@{
        Proven = $true
        Error = ''
        TreeKillAttempted = $true
        TreeKillMethod = 'taskkill.exe /T /F'
        TaskkillProcessId = [int]101
        TaskkillStartTimeFileTimeUtc = [long]202
        TaskkillTerminationProven = $true
        TaskkillTimedOut = $false
        TaskkillExitCode = [int]0
    }
    $syntheticTaskkillTimeout = [pscustomobject]@{
        Proven = $false
        Error = 'taskkill helper timed out'
        TreeKillAttempted = $true
        TreeKillMethod = 'taskkill.exe /T /F'
        TaskkillProcessId = [int]303
        TaskkillStartTimeFileTimeUtc = [long]404
        TaskkillTerminationProven = $true
        TaskkillTimedOut = $true
        TaskkillExitCode = [int]-1
    }
    if ((Get-RealTaskkillFixtureOutcome $syntheticTaskkillSuccess).Kind -cne
            'success' -or
        (Get-RealTaskkillFixtureOutcome $syntheticTaskkillTimeout).Kind -cne
            'scheduler-timeout') {
        $failures.Add('real-taskkill classifier rejected an exact accepted outcome') |
            Out-Null
    }
    $syntheticNonzero = $syntheticTaskkillSuccess.PSObject.Copy()
    $syntheticNonzero.TaskkillExitCode = [int]7
    $syntheticUnproven = $syntheticTaskkillTimeout.PSObject.Copy()
    $syntheticUnproven.TaskkillTerminationProven = $false
    $syntheticNull = $syntheticTaskkillSuccess.PSObject.Copy()
    $syntheticNull.Error = $null
    $syntheticMissing = [pscustomobject]@{
        Proven = $true
        Error = ''
        TreeKillAttempted = $true
        TreeKillMethod = 'taskkill.exe /T /F'
        TaskkillProcessId = [int]505
        TaskkillStartTimeFileTimeUtc = [long]606
        TaskkillTerminationProven = $true
        TaskkillTimedOut = $false
    }
    foreach ($invalidTaskkillCase in @(
            [pscustomobject]@{ Name = 'nonzero'; Value = $syntheticNonzero }
            [pscustomobject]@{ Name = 'helper-unproven'; Value = $syntheticUnproven }
            [pscustomobject]@{ Name = 'null-valued'; Value = $syntheticNull }
            [pscustomobject]@{ Name = 'malformed'; Value = $syntheticMissing }
            [pscustomobject]@{ Name = 'missing-result'; Value = $null }
        )) {
        $outcome = Get-RealTaskkillFixtureOutcome $invalidTaskkillCase.Value
        if ($outcome.Kind -cne 'invalid') {
            $failures.Add("real-taskkill classifier accepted $($invalidTaskkillCase.Name): $($outcome | Out-String)") | Out-Null
        }
    }

    # The canonical schema now represents a same-commit content/tip identity,
    # while old release receipts still need the strict schema-1 reader.
    try {
        $schema2Text = @"
return {
    canonical_url = "https://github.com/Aussiemon/Vermintide-2-Source-Code",
    content_revision = "$('a' * 40)",
    default_ref = "refs/heads/master",
    game_version = "6.12.1",
    observed_at_utc = "2026-09-03T22:09:45Z",
    observed_default_tip = "$('a' * 40)",
    observed_tip_content_relation = "same_commit",
    observed_tip_metadata_paths = {},
    schema = 2,
}
"@
        $schema1Text = @"
return {
    canonical_url = "https://github.com/Aussiemon/Vermintide-2-Source-Code",
    content_revision = "$('b' * 40)",
    default_ref = "refs/heads/master",
    game_version = "6.12.0",
    observed_at_utc = "2026-08-28T23:45:18Z",
    observed_default_tip = "$('c' * 40)",
    observed_tip_content_relation = "direct_parent",
    observed_tip_metadata_paths = { "README.md" },
    schema = 1,
}
"@
        $parsedSchema2 = ConvertFrom-WtHistorySourceAnchorLiteral -Text $schema2Text
        if ($parsedSchema2.Schema -ne 2 -or
            $parsedSchema2.ObservedTipContentRelation -cne 'same_commit' -or
            $parsedSchema2.ContentRevision -cne $parsedSchema2.ObservedDefaultTip -or
            @($parsedSchema2.ObservedTipMetadataPaths).Count -ne 0) {
            $failures.Add('canonical schema-2 same-commit anchor did not parse exactly') | Out-Null
        }
        $parsedSchema1 = ConvertFrom-WtHistorySourceAnchorLiteral -Text $schema1Text
        if ($parsedSchema1.Schema -ne 1 -or
            $parsedSchema1.ObservedTipContentRelation -cne 'direct_parent' -or
            $parsedSchema1.ContentRevision -ceq $parsedSchema1.ObservedDefaultTip -or
            @($parsedSchema1.ObservedTipMetadataPaths).Count -ne 1 -or
            $parsedSchema1.ObservedTipMetadataPaths[0] -cne 'README.md') {
            $failures.Add('legacy schema-1 direct-parent anchor compatibility failed') | Out-Null
        }

        foreach ($invalid in @(
                $schema2Text.Replace('observed_tip_metadata_paths = {},',
                    'observed_tip_metadata_paths = { "README.md" },'),
                $schema2Text.Replace('observed_tip_content_relation = "same_commit",',
                    'observed_tip_content_relation = "direct_parent",'),
                $schema2Text.Replace('content_revision = "' + ('a' * 40) + '",',
                    'content_revision = "' + ('b' * 40) + '",'),
                $schema1Text.Replace('observed_default_tip = "' + ('c' * 40) + '",',
                    'observed_default_tip = "' + ('b' * 40) + '",'),
                $schema1Text.Replace('observed_tip_content_relation = "direct_parent",',
                    'observed_tip_content_relation = "same_commit",'),
                $schema1Text.Replace(
                    'observed_tip_metadata_paths = { "README.md" },',
                    'observed_tip_metadata_paths = {},'),
                $schema1Text.Replace('"README.md"', '"readme.md"'),
                $schema1Text.Replace('"README.md"', '"CHANGELOG.md"')
            )) {
            $rejected = $false
            try { $null = ConvertFrom-WtHistorySourceAnchorLiteral -Text $invalid }
            catch { $rejected = $true }
            if (-not $rejected) {
                $failures.Add('cross-schema source-anchor fixture was accepted') | Out-Null
            }
        }
    }
    catch {
        $failures.Add("source-anchor schema compatibility fixture failed: $($_.Exception.Message)") |
            Out-Null
    }

    # Generic source guards have one full-QA owner. This fixture fails if a
    # patch matrix reintroduces either expensive dual-host self-test or if the
    # shared owner is multiplied/removed. It also pins the production wait seam:
    # direct Process/Task waits belong only in the two injectable wrappers.
    try {
        $resolvedRepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
        $runAllText = [IO.File]::ReadAllText((Join-Path $resolvedRepoRoot 'qa\run_all.ps1'))
        $sharedMatrixPath = Join-Path $resolvedRepoRoot `
            'qa\run_wt_history_source_host_matrix.ps1'
        $sharedMatrixText = [IO.File]::ReadAllText($sharedMatrixPath)
        $runSelfTestsText = [IO.File]::ReadAllText((Join-Path $resolvedRepoRoot `
            'qa\run_selftests.ps1'))
        $sourceText = [IO.File]::ReadAllText($PSCommandPath)
        $checkoutText = [IO.File]::ReadAllText((Join-Path $resolvedRepoRoot `
            'qa\check_wt_history_source_checkout.ps1'))
        $ownerMarker = '# SELFTEST-' +
            'OWNER: run_wt_history_source_host_matrix.ps1'

        if ((Get-OrdinalOccurrenceCount $runAllText `
                'run_wt_history_source_host_matrix.ps1') -ne 1) {
            $failures.Add('full QA must invoke the shared source host matrix exactly once') | Out-Null
        }
        # Issue #1683: pre-commit scopes the ordinary freshness gate to the
        # index; run_all must forward that scope, and release mode must stay
        # outside the change-set downgrade.
        $preCommitText = [IO.File]::ReadAllText((Join-Path $resolvedRepoRoot `
            'tools\hooks\pre-commit.ps1'))
        if ((Get-OrdinalOccurrenceCount $runAllText `
                'check_wt_history_source_freshness.ps1") -Staged:$Staged') -ne 1 -or
            (Get-OrdinalOccurrenceCount $preCommitText `
                '-File $qaScript -Quick -SkipLua -Staged') -ne 1) {
            $failures.Add('pre-commit must pass -Staged and run_all must forward it to the freshness gate') | Out-Null
        }
        # The main body must hand every probe result to the self-tested
        # decision function with its real switches and exit with its code.
        $mainOffset = $sourceText.IndexOf("`nif (`$SelfTest) { Invoke-FreshnessSelfTest }",
            [StringComparison]::Ordinal)
        $mainText = if ($mainOffset -ge 0) { $sourceText.Substring($mainOffset) } else { '' }
        foreach ($wiring in @(
                '$decision = Invoke-WtHistoryFreshnessDecision -Result $result -RepoRoot $root -Staged:$Staged -RequireRemoteFresh:$RequireRemoteFresh -Quiet:$Quiet',
                'if ($decision.ExitCode -ge 2) { throw $decision.Message }',
                'if ($decision.Print) { Write-Host $decision.Line -ForegroundColor $decision.Color }',
                'exit $decision.ExitCode')) {
            if ((Get-OrdinalOccurrenceCount $mainText $wiring) -ne 1) {
                $failures.Add("the main body must contain exactly once: $wiring") | Out-Null
            }
        }
        if ((Get-OrdinalOccurrenceCount $mainText 'Resolve-WtHistoryFreshnessOutcome') -ne 0 -or
            (Get-OrdinalOccurrenceCount $mainText 'Get-WtHistoryFreshnessChangeSet') -ne 0) {
            $failures.Add('the main body must not bypass Invoke-WtHistoryFreshnessDecision') | Out-Null
        }
        if ((Get-OrdinalOccurrenceCount $sharedMatrixText `
                '& $hostEntry.Path @freshnessArguments') -ne 1 -or
            (Get-OrdinalOccurrenceCount $sharedMatrixText `
                '& $hostEntry.Path @sourceCheckoutArguments') -ne 1) {
            $failures.Add('shared source host matrix must invoke each generic self-test once inside its host loop') | Out-Null
        }
        if ((Get-OrdinalOccurrenceCount $sourceText $ownerMarker) -ne 1 -or
            (Get-OrdinalOccurrenceCount $checkoutText $ownerMarker) -ne 1 -or
            $runSelfTestsText.IndexOf('SELFTEST-OWNER:',
                [StringComparison]::Ordinal) -lt 0) {
            $failures.Add('generic source self-tests are not exclusively delegated out of run_selftests') | Out-Null
        }

        $patchMatrices = @(Get-ChildItem (Join-Path $resolvedRepoRoot `
                'qa\run_wt_history_patch_*_host_matrix.ps1') -File)
        if ($patchMatrices.Count -lt 1) {
            $failures.Add('no patch-specific weapon-history host matrices were found') | Out-Null
        }
        foreach ($patchMatrix in $patchMatrices) {
            $patchText = [IO.File]::ReadAllText($patchMatrix.FullName)
            if ($patchText.IndexOf('check_wt_history_source_freshness.ps1',
                    [StringComparison]::Ordinal) -ge 0 -or
                $patchText.IndexOf('check_wt_history_source_checkout.ps1',
                    [StringComparison]::Ordinal) -ge 0) {
                $failures.Add("patch-specific matrix owns a generic source self-test: $($patchMatrix.Name)") | Out-Null
            }
        }

        $selfTestOffset = $sourceText.IndexOf('function Invoke-FreshnessSelfTest',
            [StringComparison]::Ordinal)
        if ($selfTestOffset -lt 0) {
            $failures.Add('freshness self-test boundary is missing') | Out-Null
        } else {
            $productionText = $sourceText.Substring(0, $selfTestOffset)
            if ((Get-OrdinalOccurrenceCount $productionText '.WaitForExit(') -ne 1 -or
                (Get-OrdinalOccurrenceCount $productionText '.Wait(') -ne 1) {
                $failures.Add('production waits bypass or multiply the injectable deadline wrappers') | Out-Null
            }
        }
    }
    catch {
        $failures.Add("shared-matrix/wait wiring fixture crashed: $($_.Exception.Message)") | Out-Null
    }
    function New-HostCommandStartInfo([string]$Command) {
        $hostPath = (Get-Process -Id $PID).Path
        if (-not $hostPath -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
            throw 'current PowerShell executable is unavailable'
        }
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = $hostPath
        $start.Arguments = '-NoLogo -NoProfile -NonInteractive -Command "' +
            $Command + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        return $start
    }
    function New-NestedHangingStartInfo([string]$ChildPidPath) {
        $hostPath = (Get-Process -Id $PID).Path
        if (-not $hostPath -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
            throw 'current PowerShell executable is unavailable'
        }
        $fixtureScript = Join-Path $PSScriptRoot `
            'fixtures\wt_history\hanging_process_tree.ps1'
        if (-not (Test-Path -LiteralPath $fixtureScript -PathType Leaf)) {
            throw "nested process fixture is unavailable: $fixtureScript"
        }
        if ($fixtureScript.Contains('"') -or $ChildPidPath.Contains('"')) {
            throw 'nested process fixture paths cannot contain a quote'
        }
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = $hostPath
        $start.Arguments = '-NoLogo -NoProfile -NonInteractive -File "' +
            $fixtureScript + '" -ChildPidPath "' + $ChildPidPath + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        return $start
    }
    function New-ExitingParentStartInfo([string]$ChildPidPath) {
        $hostPath = (Get-Process -Id $PID).Path
        if (-not $hostPath -or -not (Test-Path -LiteralPath $hostPath -PathType Leaf)) {
            throw 'current PowerShell executable is unavailable'
        }
        $fixtureScript = Join-Path $PSScriptRoot `
            'fixtures\wt_history\exiting_parent_process_tree.ps1'
        if (-not (Test-Path -LiteralPath $fixtureScript -PathType Leaf)) {
            throw "root-exit process fixture is unavailable: $fixtureScript"
        }
        if ($fixtureScript.Contains('"') -or $ChildPidPath.Contains('"')) {
            throw 'root-exit process fixture paths cannot contain a quote'
        }
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = $hostPath
        $start.Arguments = '-NoLogo -NoProfile -NonInteractive -File "' +
            $fixtureScript + '" -ChildPidPath "' + $ChildPidPath + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        return $start
    }
    function New-FixturePidPath {
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $path = Join-Path $tempRoot `
            ('wt1436-process-tree-' + [guid]::NewGuid().ToString('N') + '.pid')
        if (-not ([IO.Path]::GetFullPath($path)).StartsWith($tempRoot,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'nested fixture PID path escaped the temp root'
        }
        $fixturePidPaths.Add($path) | Out-Null
        return $path
    }
    function Register-FixtureIdentity(
        $Collection,
        [string]$Label,
        [int]$ProcessId,
        [long]$StartTimeFileTimeUtc
    ) {
        if ($ProcessId -le 0 -or $StartTimeFileTimeUtc -le 0) {
            $failures.Add("$Label identity is unavailable: PID=$ProcessId start=$StartTimeFileTimeUtc") |
                Out-Null
            return $null
        }
        $identity = [pscustomobject]@{
            Label = $Label
            ProcessId = $ProcessId
            StartTimeFileTimeUtc = $StartTimeFileTimeUtc
        }
        $Collection.Add($identity) | Out-Null
        return $identity
    }
    function Read-FixtureChildIdentity([string]$Path) {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        while ($clock.ElapsedMilliseconds -lt 5000 -and
            -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Start-Sleep -Milliseconds 25
        }
        $clock.Stop()
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $lines = @([regex]::Split([IO.File]::ReadAllText($Path).Trim(), "\r?\n"))
        [int]$parsedPid = 0
        [long]$parsedStart = 0
        if ($lines.Count -ne 2 -or
            -not [int]::TryParse($lines[0], [ref]$parsedPid) -or
            -not [long]::TryParse($lines[1], [ref]$parsedStart) -or
            $parsedPid -le 0 -or $parsedStart -le 0) {
            return $null
        }
        return [pscustomobject]@{
            ProcessId = $parsedPid
            StartTimeFileTimeUtc = $parsedStart
        }
    }
    function Stop-FixtureProcess {
        param(
            [Parameter(Mandatory)][int]$FixturePid,
            [Parameter(Mandatory)][long]$ExpectedStartTimeFileTimeUtc,
            [scriptblock]$HandleBindingProbe
        )

        if ($FixturePid -le 0 -or $ExpectedStartTimeFileTimeUtc -le 0) {
            return $false
        }

        $fixture = $null
        $boundHandle = $null
        $handleRefAdded = $false
        try {
            try {
                $fixture = [System.Diagnostics.Process]::GetProcessById($FixturePid)
            }
            catch [System.ArgumentException] { return $true }
            catch { return $false }

            # Process.GetProcessById(), HasExited, and StartTime do not retain a
            # process handle on Windows PowerShell 5.1. Bind SafeHandle before
            # checking identity so Kill()/WaitForExit() operate on that exact
            # process object even if its numeric PID is reused meanwhile.
            try {
                $boundHandle = $fixture.SafeHandle
                if (-not $boundHandle -or $boundHandle.IsInvalid -or
                    $boundHandle.IsClosed) {
                    return $false
                }
                $boundHandle.DangerousAddRef([ref]$handleRefAdded)
                if (-not $handleRefAdded) { return $false }
            }
            catch { return $false }

            if ($fixture.HasExited) { return $true }
            if ([long]$fixture.StartTime.ToFileTimeUtc() -ne
                $ExpectedStartTimeFileTimeUtc) {
                # The original process is gone and this PID belongs to a new
                # process. Never kill the reused identity during cleanup.
                return $true
            }
            if ($HandleBindingProbe) {
                try {
                    $bindingAccepted = & $HandleBindingProbe $fixture `
                        $boundHandle $handleRefAdded
                    if (-not [bool]$bindingAccepted) { return $false }
                }
                catch { return $false }
            }
            try { $fixture.Kill() } catch { return $false }
            return [bool]$fixture.WaitForExit(2000)
        }
        catch [System.InvalidOperationException] {
            try { return [bool]$fixture.HasExited }
            catch { return $false }
        }
        catch { return $false }
        finally {
            if ($handleRefAdded -and $boundHandle) {
                try { $boundHandle.DangerousRelease() } catch { }
            }
            if ($fixture) { $fixture.Dispose() }
        }
    }
    function Start-PreparedNestedFixture([string]$Label) {
        $pidPath = New-FixturePidPath
        $fixtureProcess = New-Object System.Diagnostics.Process
        try {
            $fixtureProcess.StartInfo = New-NestedHangingStartInfo $pidPath
            if (-not $fixtureProcess.Start()) {
                throw "$Label parent did not start"
            }
            $parentIdentity = Register-FixtureIdentity $fixtureIdentities `
                "$Label parent" $fixtureProcess.Id `
                ([long]$fixtureProcess.StartTime.ToFileTimeUtc())
            $childRecordedIdentity = Read-FixtureChildIdentity $pidPath
            if (-not $childRecordedIdentity) {
                throw "$Label descendant identity was not recorded"
            }
            $childIdentity = Register-FixtureIdentity $fixtureIdentities `
                "$Label descendant" `
                ([int]$childRecordedIdentity.ProcessId) `
                ([long]$childRecordedIdentity.StartTimeFileTimeUtc)
            if (-not $parentIdentity -or -not $childIdentity) {
                throw "$Label exact process identities are unavailable"
            }
            return [pscustomobject]@{
                Process = $fixtureProcess
                ParentIdentity = $parentIdentity
                ChildIdentity = $childIdentity
            }
        }
        catch {
            $fixtureProcess.Dispose()
            throw
        }
    }
    function Assert-ExactIdentityState(
        [string]$Context,
        $Identity,
        [string[]]$AllowedStates
    ) {
        if (-not $Identity) {
            $failures.Add("$Context identity is unavailable") | Out-Null
            return
        }
        $state = Get-WtHistoryProcessIdentityState `
            -ProcessId $Identity.ProcessId `
            -StartTimeFileTimeUtc $Identity.StartTimeFileTimeUtc
        if ($AllowedStates -cnotcontains $state) {
            $failures.Add("$Context identity state=$state expected=$($AllowedStates -join '/')") |
                Out-Null
        }
    }
    function Assert-RealTaskkillFixtureOutcome(
        [string]$Context,
        $Termination,
        $ParentIdentity,
        $ChildIdentity,
        $HelperIdentity,
        [long]$ElapsedMilliseconds
    ) {
        $outcome = Get-RealTaskkillFixtureOutcome $Termination
        if ($outcome.Kind -ceq 'invalid') {
            $failures.Add("$Context returned an invalid taskkill outcome ($($outcome.Reason)): $($Termination | Out-String)") | Out-Null
            return
        }
        if (-not $HelperIdentity) {
            $failures.Add("$Context did not expose the exact taskkill helper identity") |
                Out-Null
            return
        }

        $targetStates = if ($outcome.Kind -ceq 'success') {
            @('gone', 'reused')
        } else { @('alive') }
        Assert-ExactIdentityState "$Context parent" $ParentIdentity $targetStates
        Assert-ExactIdentityState "$Context descendant" $ChildIdentity $targetStates
        Assert-ExactIdentityState "$Context helper" $HelperIdentity `
            @('gone', 'reused')

        if ($outcome.Kind -ceq 'scheduler-timeout') {
            $latencyDiagnostics.Add("$Context accepted the exact fail-closed scheduler-latency branch: elapsed=${ElapsedMilliseconds}ms helper_contained=true targets_retained=true") | Out-Null
        }
    }
    $exact = [pscustomobject]@{
        ExitCode = 0; TimedOut = $false
        Stdout = "ref: refs/heads/master`tHEAD`n$('a' * 40)`tHEAD`n"
    }
    Assert-State 'exact' $exact $true 'pass'
    $lag = [pscustomobject]@{
        ExitCode = 0; TimedOut = $false
        Stdout = "ref: refs/heads/master`tHEAD`n$('c' * 40)`tHEAD`n"
    }
    Assert-State 'lag' $lag $false 'fail'
    $branch = [pscustomobject]@{
        ExitCode = 0; TimedOut = $false
        Stdout = "ref: refs/heads/main`tHEAD`n$('a' * 40)`tHEAD`n"
    }
    Assert-State 'branch move' $branch $true 'fail'
    $malformed = [pscustomobject]@{
        ExitCode = 0; TimedOut = $false; Stdout = "$('a' * 40)`tHEAD`n"
    }
    Assert-State 'malformed' $malformed $false 'fail'
    $ambiguous = [pscustomobject]@{
        ExitCode = 0; TimedOut = $false
        Stdout = "ref: refs/heads/master`tHEAD`n$('a' * 40)`tHEAD`n$('a' * 40)`tHEAD`n"
    }
    Assert-State 'ambiguous' $ambiguous $false 'fail'
    $timeout = [pscustomobject]@{
        ExitCode = -1; TimedOut = $true; Stdout = ''; TerminationProven = $true
    }
    Assert-State 'optional timeout' $timeout $false 'skip'
    Assert-State 'required timeout' $timeout $true 'fail'
    $unavailable = [pscustomobject]@{ ExitCode = 128; TimedOut = $false; Stdout = '' }
    Assert-State 'optional unavailable' $unavailable $false 'skip'
    Assert-State 'required unavailable' $unavailable $true 'fail'

    # Issue #1683: a moved ref/tip blocks ordinary QA only for a change set
    # that touches weapon-history inputs or a WT stream; any other determinate
    # change set is a visible advisory. Release (-Required) mode is unchanged.
    function Assert-Scoped([string]$Name, $Result, $ChangeSet, [bool]$Required, [string]$Expected) {
        $outcome = Resolve-WtHistoryFreshnessOutcome -Result $Result `
            -ChangeSet $ChangeSet -Required:$Required
        if ($outcome.State -cne $Expected) {
            $failures.Add("scope: $Name expected=$Expected actual=$($outcome.State): $($outcome.Message)") |
                Out-Null
        }
        return $outcome
    }
    try {
        foreach ($movedCase in @(
                @{ Name = 'lag'; Probe = $lag; Moved = $true }
                @{ Name = 'branch move'; Probe = $branch; Moved = $true }
                @{ Name = 'malformed'; Probe = $malformed; Moved = $false }
                @{ Name = 'exact'; Probe = $exact; Moved = $false })) {
            $probeResult = Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $movedCase.Probe
            if ([bool]$probeResult.Moved -ne $movedCase.Moved) {
                $failures.Add("scope: $($movedCase.Name) Moved flag expected=$($movedCase.Moved)") | Out-Null
            }
        }
        foreach ($path in @(
                'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua',
                'weapon_tweaker_dev/weapon_tweaker_dev.mod',
                'Weapon_Tweaker\scripts\fixture.lua',
                'tools/weapon-history/current_source_anchor.lua',
                'qa/check_wt_history_source_freshness.ps1',
                'qa/wt_history_freshness_scope.ps1',
                'qa/lua/tests/test_wt_history_runtime.lua',
                'qa/fixtures/wt_history/hanging_process_tree.ps1')) {
            if (-not (Test-WtHistoryScopePath $path)) {
                $failures.Add("scope: '$path' must be in weapon-history scope") | Out-Null
            }
        }
        foreach ($path in @(
                'gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev.lua',
                'weapon_tweaker_extra/fixture.lua',
                'docs/weapon_tweaker/notes.md',
                'character_weapon_variants/fixture.lua',
                'qa/run_all.ps1',
                'tools/ship/ship.ps1',
                'tools/hooks/pre-commit.ps1',
                '')) {
            if (Test-WtHistoryScopePath $path) {
                $failures.Add("scope: '$path' must be outside weapon-history scope") | Out-Null
            }
        }
        # Path lists are read with -z: git C-quotes a name holding a double
        # quote, so a quoted line would miss the weapon_tweaker/ prefix.
        $nul = [string][char]0
        $split = @(Split-WtHistoryNulPathList @("weapon_tweaker/a`"b.lua${nul}gui_tweaker_dev/x.lua$nul"))
        if ($split.Count -ne 2 -or $split[0] -cne 'weapon_tweaker/a"b.lua' -or
            -not (Test-WtHistoryScopePath $split[0]) -or (Test-WtHistoryScopePath $split[1])) {
            $failures.Add("scope: NUL path split mis-parsed a quoted name: $($split -join ' | ')") | Out-Null
        }
        $splitLf = @(Split-WtHistoryNulPathList @('weapon_tweaker/line', "break.lua$nul"))
        if ($splitLf.Count -ne 1 -or $splitLf[0] -cne "weapon_tweaker/line`nbreak.lua") {
            $failures.Add('scope: NUL path split must keep an LF inside one name') | Out-Null
        }
        if (@(Split-WtHistoryNulPathList @()).Count -ne 0) {
            $failures.Add('scope: NUL path split of empty output must be empty') | Out-Null
        }

        $lagResult = Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $lag
        $nonWtSet = New-WtHistoryChangeSet $true 'staged' @('gui_tweaker_dev/fixture.lua', 'qa/run_all.ps1') ''
        $wtSet = New-WtHistoryChangeSet $true 'staged' @('gui_tweaker_dev/fixture.lua', 'weapon_tweaker_dev/fixture.lua') ''
        $emptySet = New-WtHistoryChangeSet $true 'staged' @() ''
        $unknownSet = New-WtHistoryChangeSet $false 'pr' @() 'fixture range unavailable'
        $advisory = Assert-Scoped 'moved tip + non-WT diff' $lagResult $nonWtSet $false 'advisory'
        if ($advisory.Message.IndexOf(('c' * 40), [StringComparison]::Ordinal) -lt 0 -or
            $advisory.Message.IndexOf('#1682', [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("scope: advisory must name the moved tip and the #1682 re-anchor: $($advisory.Message)") |
                Out-Null
        }
        $null = Assert-Scoped 'moved tip + empty diff' $lagResult $emptySet $false 'advisory'
        $blocked = Assert-Scoped 'moved tip + WT diff' $lagResult $wtSet $false 'fail'
        if ($blocked.Message.IndexOf('weapon_tweaker_dev/fixture.lua', [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("scope: WT block must name the in-scope path: $($blocked.Message)") | Out-Null
        }
        $null = Assert-Scoped 'moved tip + indeterminate diff' $lagResult $unknownSet $false 'fail'
        $null = Assert-Scoped 'moved tip + no change set' $lagResult $null $false 'fail'
        $null = Assert-Scoped 'required moved tip + non-WT diff' $lagResult $nonWtSet $true 'fail'
        $null = Assert-Scoped 'moved ref + non-WT diff' `
            (Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $branch) $nonWtSet $false 'advisory'
        $null = Assert-Scoped 'malformed + non-WT diff' `
            (Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $malformed) $nonWtSet $false 'fail'
        $null = Assert-Scoped 'exact + WT diff' `
            (Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $exact) $wtSet $false 'pass'
        $null = Assert-Scoped 'optional unavailable + WT diff' `
            (Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $unavailable) $wtSet $false 'skip'

        # The main body's printed line and exit code come from the same
        # decision function; unmoved results never consult a change set.
        $noRepo = Join-Path ([IO.Path]::GetTempPath()) ('vt2-wt-history-no-repo-' + [guid]::NewGuid().ToString('N'))
        foreach ($exitCase in @(
                @{ Name = 'exact'; Probe = $exact; Quiet = $true; State = 'pass'; Exit = 0; Print = $false }
                @{ Name = 'exact verbose'; Probe = $exact; Quiet = $false; State = 'pass'; Exit = 0; Print = $true }
                @{ Name = 'optional unavailable'; Probe = $unavailable; Quiet = $true; State = 'skip'; Exit = 0; Print = $true }
                @{ Name = 'malformed'; Probe = $malformed; Quiet = $true; State = 'fail'; Exit = 2; Print = $true })) {
            $decision = Invoke-WtHistoryFreshnessDecision -RepoRoot $noRepo -Quiet:$exitCase.Quiet `
                -Result (Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $exitCase.Probe)
            if ($decision.State -cne $exitCase.State -or $decision.ExitCode -ne $exitCase.Exit -or
                $decision.Print -ne $exitCase.Print) {
                $failures.Add("decision: $($exitCase.Name) expected=$($exitCase.State)/$($exitCase.Exit)/print=$($exitCase.Print) actual=$($decision.State)/$($decision.ExitCode)/print=$($decision.Print)") |
                    Out-Null
            }
        }
    }
    catch {
        $failures.Add("scope decision fixture crashed: $($_.Exception.Message)") | Out-Null
    }

    # The main-body decision over real git change sets: staged index
    # (pre-commit), local index + working tree + branch commits + untracked
    # files, hosted PR, push and workflow_dispatch ranges, and release mode.
    $scopeRepo = Join-Path ([IO.Path]::GetTempPath()) `
        ('vt2-wt-history-scope-' + [guid]::NewGuid().ToString('N'))
    try {
        [void][IO.Directory]::CreateDirectory($scopeRepo)
        function Invoke-ScopeFixtureGit([string[]]$GitArgs) {
            $gitResult = Invoke-WtHistoryScopeGit -RepoRoot $scopeRepo -GitArgs $GitArgs
            if ($gitResult.ExitCode -ne 0) {
                throw "fixture git $($GitArgs -join ' ') exited $($gitResult.ExitCode)"
            }
            return $gitResult
        }
        function Write-ScopeFixtureFile([string]$Relative, [string]$Text) {
            $full = Join-Path $scopeRepo $Relative
            [void][IO.Directory]::CreateDirectory((Split-Path $full -Parent))
            [IO.File]::WriteAllText($full, $Text)
        }
        $fixtureCommit = @('-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
            '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', 'fixture')
        function Remove-ScopeFixtureFile([string]$Relative) {
            [IO.File]::Delete((Join-Path $scopeRepo $Relative))
        }
        # Drive the exact main-body decision (moved tip, -Quiet as run_all
        # passes it) and pin state, exit code and the printed line.
        function Assert-ScopedRepo([string]$Name, [bool]$StagedOnly, $Context, [string]$Expected,
                [bool]$Release = $false) {
            $decision = Invoke-WtHistoryFreshnessDecision -Result $lagResult -RepoRoot $scopeRepo `
                -Staged:$StagedOnly -RequireRemoteFresh:$Release -Quiet -Context $Context
            $expectedExit = if ($Expected -ceq 'advisory') { 1 } else { 2 }
            $expectedLine = if ($Expected -ceq 'advisory') { 'ADVISORY' } else { 'ERROR' }
            if ($decision.State -cne $Expected -or $decision.ExitCode -ne $expectedExit -or
                -not $decision.Print -or -not $decision.Line.StartsWith(
                    "[check_wt_history_source_freshness] $expectedLine - ", [StringComparison]::Ordinal)) {
                $failures.Add("scope: repo $Name expected=$Expected/exit $expectedExit actual=$($decision.State)/exit $($decision.ExitCode): $($decision.Line)") |
                    Out-Null
            }
        }
        $localContext = Get-WtHistoryHostedContext -GitHubActions '' -EventName '' -EventPath '' -BaseRef ''

        $null = Invoke-ScopeFixtureGit @('init', '-q')
        Write-ScopeFixtureFile 'weapon_tweaker/fixture.lua' "return 1`n"
        Write-ScopeFixtureFile 'gui_tweaker_dev/fixture.lua' "return 1`n"
        $null = Invoke-ScopeFixtureGit @('add', '-A')
        $null = Invoke-ScopeFixtureGit $fixtureCommit
        $baseSha = (Invoke-ScopeFixtureGit @('rev-parse', 'HEAD')).Lines[0].Trim()
        $null = Invoke-ScopeFixtureGit @('update-ref', 'refs/remotes/origin/master', $baseSha)

        Write-ScopeFixtureFile 'gui_tweaker_dev/fixture.lua' "return 2`n"
        $null = Invoke-ScopeFixtureGit @('add', '--', 'gui_tweaker_dev/fixture.lua')
        Assert-ScopedRepo 'staged non-WT' $true $localContext 'advisory'
        Assert-ScopedRepo 'release staged non-WT' $true $localContext 'fail' $true
        Write-ScopeFixtureFile 'weapon_tweaker/fixture.lua' "return 2`n"
        Assert-ScopedRepo 'staged non-WT beside unstaged WT (pre-commit)' $true $localContext 'advisory'
        Assert-ScopedRepo 'staged non-WT beside unstaged WT (local union)' $false $localContext 'fail'
        $null = Invoke-ScopeFixtureGit @('add', '--', 'weapon_tweaker/fixture.lua')
        Assert-ScopedRepo 'staged WT' $true $localContext 'fail'
        $null = Invoke-ScopeFixtureGit @('reset', '-q', '--hard')
        [void][IO.Directory]::CreateDirectory((Join-Path $scopeRepo 'moved'))
        $null = Invoke-ScopeFixtureGit @('mv', 'weapon_tweaker/fixture.lua', 'moved/fixture.lua')
        Assert-ScopedRepo 'staged rename out of WT' $true $localContext 'fail'
        $null = Invoke-ScopeFixtureGit @('reset', '-q', '--hard')
        Assert-ScopedRepo 'clean local tree' $false $localContext 'advisory'
        # Untracked unignored files count in a local union run (not the index).
        Write-ScopeFixtureFile 'weapon_tweaker/untracked_fixture.lua' "return 1`n"
        Assert-ScopedRepo 'untracked WT (local union)' $false $localContext 'fail'
        Assert-ScopedRepo 'untracked WT (pre-commit)' $true $localContext 'advisory'
        Remove-ScopeFixtureFile 'weapon_tweaker/untracked_fixture.lua'
        Write-ScopeFixtureFile '.git\info\exclude' "*.ignored`n"
        Write-ScopeFixtureFile 'weapon_tweaker/scratch.ignored' "x`n"
        Write-ScopeFixtureFile 'gui_tweaker_dev/untracked_fixture.lua' "return 1`n"
        Assert-ScopedRepo 'ignored WT + untracked non-WT (local union)' $false $localContext 'advisory'
        Remove-ScopeFixtureFile 'weapon_tweaker/scratch.ignored'
        Remove-ScopeFixtureFile 'gui_tweaker_dev/untracked_fixture.lua'

        $eventPath = Join-Path $scopeRepo '.git\fixture-event.json'
        [IO.File]::WriteAllText($eventPath, '{"before":"' + $baseSha + '"}')
        $prContext = Get-WtHistoryHostedContext -GitHubActions 'true' -EventName 'pull_request' `
            -EventPath $eventPath -BaseRef 'master'
        $pushContext = Get-WtHistoryHostedContext -GitHubActions 'true' -EventName 'push' `
            -EventPath $eventPath -BaseRef ''
        if ($pushContext.PushBefore -cne $baseSha) {
            $failures.Add("scope: push context did not read 'before' from the event payload") | Out-Null
        }
        Write-ScopeFixtureFile 'gui_tweaker_dev/fixture.lua' "return 3`n"
        $null = Invoke-ScopeFixtureGit @('add', '-A')
        $null = Invoke-ScopeFixtureGit $fixtureCommit
        $dispatchContext = Get-WtHistoryHostedContext -GitHubActions 'true' -EventName 'workflow_dispatch' `
            -EventPath '' -BaseRef ''
        Assert-ScopedRepo 'PR range non-WT' $false $prContext 'advisory'
        Assert-ScopedRepo 'push range non-WT' $false $pushContext 'advisory'
        Assert-ScopedRepo 'branch commit non-WT (local)' $false $localContext 'advisory'
        Assert-ScopedRepo 'branch commit non-WT (dispatch)' $false $dispatchContext 'advisory'
        Write-ScopeFixtureFile 'weapon_tweaker/fixture.lua' "return 3`n"
        $null = Invoke-ScopeFixtureGit @('add', '-A')
        $null = Invoke-ScopeFixtureGit $fixtureCommit
        Assert-ScopedRepo 'PR range WT' $false $prContext 'fail'
        Assert-ScopedRepo 'push range WT' $false $pushContext 'fail'
        Assert-ScopedRepo 'branch commit WT on a clean tree (local)' $false $localContext 'fail'
        Assert-ScopedRepo 'branch commit WT (dispatch)' $false $dispatchContext 'fail'
        Assert-ScopedRepo 'branch commit WT (pre-commit, index only)' $true $localContext 'advisory'

        Assert-ScopedRepo 'PR range with missing base' $false `
            (Get-WtHistoryHostedContext -GitHubActions 'true' -EventName 'pull_request' `
                -EventPath '' -BaseRef 'fixture-missing-base') 'fail'
        [IO.File]::WriteAllText($eventPath, '{"before":"' + ('0' * 40) + '"}')
        Assert-ScopedRepo 'push range with zero before' $false `
            (Get-WtHistoryHostedContext -GitHubActions 'true' -EventName 'push' `
                -EventPath $eventPath -BaseRef '') 'fail'
        Assert-ScopedRepo 'push range with relative event path' $false `
            (Get-WtHistoryHostedContext -GitHubActions 'true' -EventName 'push' `
                -EventPath 'fixture-event.json' -BaseRef '') 'fail'
        $headSha = (Invoke-ScopeFixtureGit @('rev-parse', 'HEAD')).Lines[0].Trim()
        $null = Invoke-ScopeFixtureGit @('update-ref', 'refs/remotes/origin/master', $headSha)
        Assert-ScopedRepo 'dispatch at the default-branch tip' $false $dispatchContext 'advisory'
        Assert-ScopedRepo 'local at origin/master' $false $localContext 'advisory'
        $null = Invoke-ScopeFixtureGit @('update-ref', '-d', 'refs/remotes/origin/master')
        Assert-ScopedRepo 'local without origin/master' $false $localContext 'fail'
        Assert-ScopedRepo 'dispatch without origin/master' $false $dispatchContext 'fail'

        # A committed WT name that git C-quotes (a double quote: Windows refuses
        # it in the index, but a fetched tree can carry it) must stay in scope,
        # which only the -z path lists guarantee. HEAD gains that one file;
        # the index keeps the old tree, so the staged diff lists just it.
        function New-ScopeFixtureTree([object[]]$Entries) {
            # Raw sorted tree entries: "<mode> <name>" NUL <20-byte id>.
            $bytes = New-Object 'System.Collections.Generic.List[byte]'
            foreach ($entry in $Entries) {
                $bytes.AddRange([Text.Encoding]::ASCII.GetBytes("$($entry.Mode) $($entry.Name)"))
                $bytes.Add([byte]0)
                for ($i = 0; $i -lt 40; $i += 2) { $bytes.Add([Convert]::ToByte($entry.Sha.Substring($i, 2), 16)) }
            }
            $treeFile = Join-Path $scopeRepo '.git\fixture-tree.bin'
            [IO.File]::WriteAllBytes($treeFile, $bytes.ToArray())
            return (Invoke-ScopeFixtureGit @('hash-object', '-w', '-t', 'tree', $treeFile)).Lines[0].Trim()
        }
        $blob = (Invoke-ScopeFixtureGit @('rev-parse', 'HEAD:weapon_tweaker/fixture.lua')).Lines[0].Trim()
        $guiTree = (Invoke-ScopeFixtureGit @('rev-parse', 'HEAD:gui_tweaker_dev')).Lines[0].Trim()
        $wtTree = New-ScopeFixtureTree @(
            @{ Mode = '100644'; Name = 'fixture.lua'; Sha = $blob }
            @{ Mode = '100644'; Name = 'q"uote.lua'; Sha = $blob })
        $rootTree = New-ScopeFixtureTree @(
            @{ Mode = '40000'; Name = 'gui_tweaker_dev'; Sha = $guiTree }
            @{ Mode = '40000'; Name = 'weapon_tweaker'; Sha = $wtTree })
        $quotedSha = (Invoke-ScopeFixtureGit @('-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid',
                'commit-tree', $rootTree, '-p', 'HEAD', '-m', 'quoted')).Lines[0].Trim()
        $null = Invoke-ScopeFixtureGit @('update-ref', 'HEAD', $quotedSha)
        Assert-ScopedRepo 'committed C-quoted WT name (index vs HEAD)' $true $localContext 'fail'

        $missingRepoSet = Get-WtHistoryFreshnessChangeSet -RepoRoot (Join-Path $scopeRepo 'missing') `
            -Staged -Context $localContext
        $null = Assert-Scoped 'missing work tree' $lagResult $missingRepoSet $false 'fail'
    }
    catch {
        $failures.Add("scope git fixture crashed: $($_.Exception.Message)") | Out-Null
    }
    finally {
        if ($scopeRepo.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path $scopeRepo -Leaf).StartsWith('vt2-wt-history-scope-', [StringComparison]::Ordinal) -and
            (Test-Path -LiteralPath $scopeRepo)) {
            Remove-Item -LiteralPath $scopeRepo -Recurse -Force
        }
    }

    $deadlineCases = @(
        [pscustomobject]@{ Total = 1000; Network = 250; Taskkill = 500; Post = 250 }
        [pscustomobject]@{ Total = 2666; Network = 667; Taskkill = 1499; Post = 500 }
        [pscustomobject]@{ Total = 2667; Network = 667; Taskkill = 1500; Post = 500 }
        [pscustomobject]@{ Total = 3000; Network = 750; Taskkill = 1687; Post = 563 }
        [pscustomobject]@{ Total = 5333; Network = 1334; Taskkill = 2999; Post = 1000 }
        [pscustomobject]@{ Total = 5334; Network = 1334; Taskkill = 3000; Post = 1000 }
        [pscustomobject]@{ Total = 15000; Network = 11000; Taskkill = 3000; Post = 1000 }
        [pscustomobject]@{ Total = 60000; Network = 56000; Taskkill = 3000; Post = 1000 }
    )
    foreach ($expected in $deadlineCases) {
        $plan = New-WtHistoryProbeDeadlinePlan `
            -TimeoutMilliseconds $expected.Total
        $sum = [int]$plan.NetworkMilliseconds +
            [int]$plan.TaskkillMilliseconds +
            [int]$plan.PostProofMilliseconds
        if ([int]$plan.TotalMilliseconds -ne $expected.Total -or
            [int]$plan.NetworkMilliseconds -ne $expected.Network -or
            [int]$plan.TaskkillMilliseconds -ne $expected.Taskkill -or
            [int]$plan.PostProofMilliseconds -ne $expected.Post -or
            [int]$plan.NetworkDeadlineMilliseconds -ne $expected.Network -or
            [int]$plan.TaskkillDeadlineMilliseconds -ne
                ($expected.Network + $expected.Taskkill) -or
            [int]$plan.TotalDeadlineMilliseconds -ne $expected.Total -or
            $sum -ne $expected.Total -or
            $plan.NetworkMilliseconds -le 0 -or
            $plan.TaskkillMilliseconds -le 0 -or
            $plan.PostProofMilliseconds -le 0 -or
            $plan.NetworkDeadlineMilliseconds -ge
                $plan.TaskkillDeadlineMilliseconds -or
            $plan.TaskkillDeadlineMilliseconds -ge
                $plan.TotalDeadlineMilliseconds) {
            $failures.Add("deadline allocation mismatch for $($expected.Total)ms: $($plan | Out-String)") |
                Out-Null
        }
    }
    $previousPlan = $null
    for ($totalMilliseconds = 1000; $totalMilliseconds -le 60000;
        $totalMilliseconds++) {
        $plan = New-WtHistoryProbeDeadlinePlan `
            -TimeoutMilliseconds $totalMilliseconds
        $sum = [int]$plan.NetworkMilliseconds +
            [int]$plan.TaskkillMilliseconds +
            [int]$plan.PostProofMilliseconds
        $invalid = $sum -ne $totalMilliseconds -or
            $plan.NetworkMilliseconds -le 0 -or
            $plan.TaskkillMilliseconds -le 0 -or
            $plan.PostProofMilliseconds -le 0 -or
            $plan.NetworkDeadlineMilliseconds -ge
                $plan.TaskkillDeadlineMilliseconds -or
            $plan.TaskkillDeadlineMilliseconds -ge
                $plan.TotalDeadlineMilliseconds
        if ($previousPlan) {
            $invalid = $invalid -or
                $plan.NetworkMilliseconds -lt
                    $previousPlan.NetworkMilliseconds -or
                $plan.TaskkillMilliseconds -lt
                    $previousPlan.TaskkillMilliseconds -or
                $plan.PostProofMilliseconds -lt
                    $previousPlan.PostProofMilliseconds -or
                $plan.TaskkillDeadlineMilliseconds -lt
                    $previousPlan.TaskkillDeadlineMilliseconds
        }
        if ($invalid) {
            $failures.Add("deadline allocation invariant failed at ${totalMilliseconds}ms: $($plan | Out-String)") |
                Out-Null
            break
        }
        $previousPlan = $plan
    }

    try {
        # Deterministic model of the hosted-runner race: a dead helper's PID is
        # immediately occupied by another live process. The old PID-only
        # Get-Process assertion necessarily called this an orphan. Exact
        # PID+start-time identity must recognize the replacement while still
        # recognizing the same live identity.
        $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
        try {
            $currentStart = [long]$currentProcess.StartTime.ToFileTimeUtc()
            $sameState = Get-WtHistoryProcessIdentityState `
                -ProcessId $currentProcess.Id `
                -StartTimeFileTimeUtc $currentStart
            $differentStart = if ($currentStart -gt 1) {
                $currentStart - 1
            } else { $currentStart + 1 }
            $reusedState = Get-WtHistoryProcessIdentityState `
                -ProcessId $currentProcess.Id `
                -StartTimeFileTimeUtc $differentStart
            if ($sameState -cne 'alive' -or $reusedState -cne 'reused') {
                $failures.Add("PID-reuse identity fixture failed: same=$sameState reused=$reusedState") | Out-Null
            }
        }
        finally { $currentProcess.Dispose() }

        # Deadline arithmetic is deterministic even when the host resumes well
        # after the advertised total. These values pin every phase boundary and
        # prove that a 5763ms scheduler resume cannot authorize another wait.
        $remainingCases = @(
            [pscustomobject]@{ Elapsed = 0; Deadline = 750; Expected = 750 }
            [pscustomobject]@{ Elapsed = 749; Deadline = 750; Expected = 1 }
            [pscustomobject]@{ Elapsed = 750; Deadline = 750; Expected = 0 }
            [pscustomobject]@{ Elapsed = 750; Deadline = 2437; Expected = 1687 }
            [pscustomobject]@{ Elapsed = 2436; Deadline = 2437; Expected = 1 }
            [pscustomobject]@{ Elapsed = 2437; Deadline = 2437; Expected = 0 }
            [pscustomobject]@{ Elapsed = 2437; Deadline = 3000; Expected = 563 }
            [pscustomobject]@{ Elapsed = 2999; Deadline = 3000; Expected = 1 }
            [pscustomobject]@{ Elapsed = 3000; Deadline = 3000; Expected = 0 }
            [pscustomobject]@{ Elapsed = 5763; Deadline = 3000; Expected = 0 }
        )
        $injectedClock = [System.Diagnostics.Stopwatch]::StartNew()
        $injectedClock.Stop()
        foreach ($remainingCase in $remainingCases) {
            $elapsedValue = [long]$remainingCase.Elapsed
            $elapsedTiming = [pscustomobject]@{
                GetElapsedMilliseconds = ({ return $elapsedValue }.GetNewClosure())
            }
            $actualRemaining = Get-WtHistoryDeadlineRemainingMilliseconds `
                -Clock $injectedClock `
                -DeadlineMilliseconds ([int]$remainingCase.Deadline) `
                -Timing $elapsedTiming
            if ($actualRemaining -ne [int]$remainingCase.Expected) {
                $failures.Add("injected deadline mismatch: elapsed=$elapsedValue deadline=$($remainingCase.Deadline) expected=$($remainingCase.Expected) actual=$actualRemaining") | Out-Null
            }
        }

        # Reproduce the hosted 5763ms resume without asking the OS scheduler to
        # honor a wall-clock ceiling. The virtual wait returns at each programmed
        # phase, jumps past the total deadline during the helper action, and
        # records every later wait/containment decision made by production code.
        $virtualTimingState = @{
            Elapsed = [long]0
            Waits = New-Object 'System.Collections.Generic.List[object]'
            Kills = New-Object 'System.Collections.Generic.List[string]'
        }
        $virtualTiming = [pscustomobject]@{
            GetElapsedMilliseconds = ({
                return [long]$virtualTimingState.Elapsed
            }.GetNewClosure())
            WaitForExit = ({
                param($Process, [int]$Milliseconds, [string]$Phase)
                $virtualTimingState.Waits.Add([pscustomobject]@{
                        Phase = $Phase
                        Milliseconds = $Milliseconds
                    }) | Out-Null
                if ($Phase -ceq 'network-probe') {
                    $virtualTimingState.Elapsed = [long]750
                    return $false
                }
                if ($Phase -ceq 'taskkill-action') {
                    $virtualTimingState.Elapsed = [long]5763
                    return $false
                }
                throw "unexpected virtual process wait: $Phase/${Milliseconds}ms"
            }.GetNewClosure())
            WaitForTask = ({
                param($Task, [int]$Milliseconds, [string]$Phase)
                throw "unexpected virtual task wait: $Phase/${Milliseconds}ms"
            }.GetNewClosure())
            ObserveKill = ({
                param($Process, [string]$Phase)
                $virtualTimingState.Kills.Add($Phase) | Out-Null
            }.GetNewClosure())
        }
        $virtualResume = Invoke-WtHistoryBoundedProcessProbe `
            -StartInfo (New-HostCommandStartInfo 'Start-Sleep -Seconds 30') `
            -TimeoutMs 3000 -ForceTaskkill `
            -TaskkillStartInfoOverride `
                (New-HostCommandStartInfo 'Start-Sleep -Seconds 30') `
            -Timing $virtualTiming
        $virtualTargetIdentity = Register-FixtureIdentity $fixtureIdentities `
            'virtual-resume target' ([int]$virtualResume.ProcessId) `
            ([long]$virtualResume.ProcessStartTimeFileTimeUtc)
        $virtualHelperIdentity = $null
        if ($virtualResume.TaskkillProcessId -gt 0) {
            $virtualHelperIdentity = Register-FixtureIdentity $helperIdentities `
                'virtual-resume helper' ([int]$virtualResume.TaskkillProcessId) `
                ([long]$virtualResume.TaskkillStartTimeFileTimeUtc)
        }
        $virtualWaits = @($virtualTimingState.Waits.ToArray())
        $virtualKills = @($virtualTimingState.Kills.ToArray())
        if ($virtualWaits.Count -ne 2 -or
            $virtualWaits[0].Phase -cne 'network-probe' -or
            $virtualWaits[0].Milliseconds -ne 750 -or
            $virtualWaits[1].Phase -cne 'taskkill-action' -or
            $virtualWaits[1].Milliseconds -ne 1687 -or
            $virtualKills.Count -ne 1 -or
            $virtualKills[0] -cne 'taskkill-helper-timeout' -or
            -not $virtualResume.TimedOut -or
            -not $virtualResume.KillAttempted -or
            -not $virtualResume.TreeKillAttempted -or
            -not $virtualResume.TaskkillTimedOut -or
            $virtualResume.TerminationProven -or
            $virtualResume.TerminationError.IndexOf('timed out',
                [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("5763ms virtual resume added a wait, skipped containment, or did not fail closed: waits=$($virtualWaits | Out-String) kills=$($virtualKills -join ',') result=$($virtualResume | Out-String)") | Out-Null
        }
        Assert-ExactIdentityState 'virtual-resume target' `
            $virtualTargetIdentity @('alive')
        if (-not $virtualHelperIdentity) {
            $failures.Add('5763ms virtual resume did not expose helper identity') | Out-Null
        }

        # Exercise the cleanup function itself against a retained live decoy.
        # A mismatched start time must be treated as a reused PID and preserve
        # that process; the same exact identity must remain observable as alive
        # until an intentional exact-identity cleanup terminates it.
        $decoyProcess = New-Object System.Diagnostics.Process
        $decoyStarted = $false
        $decoyIdentity = $null
        try {
            $decoyProcess.StartInfo = New-HostCommandStartInfo `
                'Start-Sleep -Seconds 30'
            if (-not $decoyProcess.Start()) {
                throw 'PID-reuse decoy did not start'
            }
            $decoyStarted = $true
            $decoyIdentity = Register-FixtureIdentity $fixtureIdentities `
                'PID-reuse decoy' $decoyProcess.Id `
                ([long]$decoyProcess.StartTime.ToFileTimeUtc())
            if ($decoyIdentity) {
                $decoyStart = [long]$decoyIdentity.StartTimeFileTimeUtc
                $unavailableStop = Stop-FixtureProcess `
                    -FixturePid $decoyIdentity.ProcessId `
                    -ExpectedStartTimeFileTimeUtc 0
                $afterUnavailableState = Get-WtHistoryProcessIdentityState `
                    -ProcessId $decoyIdentity.ProcessId `
                    -StartTimeFileTimeUtc $decoyStart
                if ($unavailableStop -or $afterUnavailableState -cne 'alive') {
                    $failures.Add("identity-free cleanup did not fail closed and preserve the live decoy: result=$unavailableStop state=$afterUnavailableState") | Out-Null
                }

                $mismatchedStart = if ($decoyStart -gt 1) {
                    $decoyStart - 1
                } else { $decoyStart + 1 }
                $mismatchedStop = Stop-FixtureProcess `
                    -FixturePid $decoyIdentity.ProcessId `
                    -ExpectedStartTimeFileTimeUtc $mismatchedStart
                $afterMismatchState = Get-WtHistoryProcessIdentityState `
                    -ProcessId $decoyIdentity.ProcessId `
                    -StartTimeFileTimeUtc $decoyStart
                if (-not $mismatchedStop -or $afterMismatchState -cne 'alive') {
                    $failures.Add("mismatched cleanup did not preserve the live decoy: result=$mismatchedStop state=$afterMismatchState") | Out-Null
                }

                $beforeExactStopState = Get-WtHistoryProcessIdentityState `
                    -ProcessId $decoyIdentity.ProcessId `
                    -StartTimeFileTimeUtc $decoyStart
                $handleBindingEvidence = @{
                    Called = $false
                    Bound = $false
                }
                $handleBindingProbe = {
                    param($ObservedProcess, $RetainedHandle, $HandleRefAdded)

                    $handleBindingEvidence['Called'] = $true
                    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
                    $haveHandleField = $ObservedProcess.GetType().GetField(
                        'haveProcessHandle', $flags)
                    if (-not $haveHandleField) {
                        $haveHandleField = $ObservedProcess.GetType().GetField(
                            '_haveProcessHandle', $flags)
                    }
                    $storedHandleField = $ObservedProcess.GetType().GetField(
                        'm_processHandle', $flags)
                    if (-not $storedHandleField) {
                        $storedHandleField = $ObservedProcess.GetType().GetField(
                            '_processHandle', $flags)
                    }
                    $storedHandle = if ($storedHandleField) {
                        $storedHandleField.GetValue($ObservedProcess)
                    } else { $null }
                    $sameNativeHandle = $storedHandle -and $RetainedHandle -and
                        -not $storedHandle.IsInvalid -and
                        -not $storedHandle.IsClosed -and
                        -not $RetainedHandle.IsInvalid -and
                        -not $RetainedHandle.IsClosed -and
                        $storedHandle.DangerousGetHandle() -eq
                            $RetainedHandle.DangerousGetHandle()
                    $bound = $haveHandleField -and
                        [bool]$haveHandleField.GetValue($ObservedProcess) -and
                        [bool]$HandleRefAdded -and $sameNativeHandle
                    $handleBindingEvidence['Bound'] = [bool]$bound
                    return [bool]$bound
                }.GetNewClosure()
                $exactStop = Stop-FixtureProcess `
                    -FixturePid $decoyIdentity.ProcessId `
                    -ExpectedStartTimeFileTimeUtc $decoyStart `
                    -HandleBindingProbe $handleBindingProbe
                $afterExactStopState = Get-WtHistoryProcessIdentityState `
                    -ProcessId $decoyIdentity.ProcessId `
                    -StartTimeFileTimeUtc $decoyStart
                if ($beforeExactStopState -cne 'alive' -or -not $exactStop -or
                    -not $handleBindingEvidence['Called'] -or
                    -not $handleBindingEvidence['Bound'] -or
                    @('gone', 'reused') -cnotcontains $afterExactStopState) {
                    $failures.Add("handle-bound exact cleanup did not terminate only the intended decoy identity: before=$beforeExactStopState result=$exactStop probeCalled=$($handleBindingEvidence['Called']) handleBound=$($handleBindingEvidence['Bound']) after=$afterExactStopState") | Out-Null
                }
            }
        }
        finally {
            if ($decoyStarted -and -not $decoyIdentity) {
                # If identity capture itself failed, the exact Process handle is
                # still safe to contain; never fall back to a bare PID lookup.
                try {
                    if (-not $decoyProcess.HasExited) {
                        $decoyProcess.Kill()
                        $null = $decoyProcess.WaitForExit(2000)
                    }
                }
                catch { }
            }
            $decoyProcess.Dispose()
        }

        $treeKillSupported = @([System.Diagnostics.Process].GetMethods() |
            Where-Object {
                $_.Name -ceq 'Kill' -and $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType -eq [bool]
            }).Count -gt 0
        $expectedTreeMethod = if ($treeKillSupported) {
            'Process.Kill(true)'
        } else { 'taskkill.exe /T /F' }

        # A root may exit while a descendant retains its redirected handles.
        # Output draining is network work and must fail closed at that phase's
        # deadline instead of consuming the taskkill and proof allocations.
        #
        # Precondition: the fixture root (a full PowerShell host that spawns a
        # second host, records its identity, then exits) must be gone before
        # the network deadline, or the probe takes the kill path instead of
        # the drain path. The deadline plan caps the termination allocation at
        # four seconds, so every millisecond above that is network budget: an
        # 8000ms probe gives the root a 4000ms window. The former 5000ms probe
        # left 1250ms; a hosted Windows PowerShell 5.1 runner needed ~1300ms
        # (#1648: taskkill started 1288ms after root start, then reported the
        # root as already gone), so the drain branch was never reached.
        $outputPlan = New-WtHistoryProbeDeadlinePlan -TimeoutMilliseconds 8000
        $outputPidPath = New-FixturePidPath
        $outputClock = [System.Diagnostics.Stopwatch]::StartNew()
        $outputProbe = Invoke-WtHistoryBoundedProcessProbe `
            -StartInfo (New-ExitingParentStartInfo $outputPidPath) `
            -TimeoutMs $outputPlan.TotalMilliseconds
        $outputClock.Stop()
        $outputParentIdentity = Register-FixtureIdentity $fixtureIdentities `
            'output-drain exited parent' ([int]$outputProbe.ProcessId) `
            ([long]$outputProbe.ProcessStartTimeFileTimeUtc)
        $outputChildRecordedIdentity = Read-FixtureChildIdentity $outputPidPath
        $outputChildIdentity = if ($outputChildRecordedIdentity) {
            Register-FixtureIdentity $fixtureIdentities `
                'output-drain live descendant' `
                ([int]$outputChildRecordedIdentity.ProcessId) `
                ([long]$outputChildRecordedIdentity.StartTimeFileTimeUtc)
        } else {
            $failures.Add('output-drain descendant identity was not recorded') | Out-Null
            $null
        }
        if ($outputProbe.KillAttempted) {
            # The kill path means the root was still alive at the network
            # deadline: a fixture precondition failure (slow host), not a
            # drain defect. Name it so the two cannot be confused again.
            $failures.Add("root-exit output drain fixture root did not exit inside the $($outputPlan.NetworkMilliseconds)ms network deadline, so the kill path ran instead of the drain path: elapsed=$($outputClock.ElapsedMilliseconds) result=$($outputProbe | Out-String)") | Out-Null
        }
        elseif (-not $outputProbe.TimedOut -or $outputProbe.TerminationProven -or
            $outputProbe.Stderr -cne 'bounded output drain expired') {
            $failures.Add("root-exit output drain did not stop at its network deadline: elapsed=$($outputClock.ElapsedMilliseconds) result=$($outputProbe | Out-String)") | Out-Null
        }
        elseif ($outputClock.ElapsedMilliseconds -lt
            ($outputPlan.NetworkMilliseconds - 50)) {
            # The descendant holds the handles for 30s, so a drain that
            # returns before the deadline (beyond timer granularity) did not
            # wait for it.
            $failures.Add("root-exit output drain returned before its $($outputPlan.NetworkMilliseconds)ms network deadline: elapsed=$($outputClock.ElapsedMilliseconds) result=$($outputProbe | Out-String)") | Out-Null
        }
        Add-LatencyDiagnostic 'root-exit output drain' `
            $outputClock.ElapsedMilliseconds ($outputPlan.NetworkMilliseconds + 1000)
        Assert-State 'optional root-exit output drain' $outputProbe $false 'skip'
        Assert-State 'required root-exit output drain' $outputProbe $true 'fail'
        Assert-ExactIdentityState 'output-drain exited parent' `
            $outputParentIdentity @('gone', 'reused')
        Assert-ExactIdentityState 'output-drain live descendant' `
            $outputChildIdentity @('alive')

        # Prove the exact three-second termination allocation against a nested
        # tree that is ready before the monotonic deadline begins. One real run
        # per host retains exact parent/descendant cleanup coverage; programmed
        # wait budgets are proven by the injected fixtures above.
        $threeSecondPlan = New-WtHistoryProbeDeadlinePlan -TimeoutMilliseconds 3000
        $realIterations = 1
        for ($iteration = 1; $iteration -le $realIterations; $iteration++) {
            $realLabel = "3s real tree $iteration"
            $realFixture = Start-PreparedNestedFixture $realLabel
            $realClock = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                Start-Sleep -Milliseconds $threeSecondPlan.NetworkMilliseconds
                $realTermination = Stop-WtHistoryProbeProcess `
                    -Process $realFixture.Process -Clock $realClock `
                    -TaskkillDeadlineMilliseconds `
                        $threeSecondPlan.TaskkillDeadlineMilliseconds `
                    -TotalDeadlineMilliseconds `
                        $threeSecondPlan.TotalDeadlineMilliseconds
            }
            finally {
                $realClock.Stop()
                $realFixture.Process.Dispose()
            }
            $realHelperIdentity = $null
            if ($realTermination.TaskkillProcessId -gt 0) {
                $realHelperIdentity = Register-FixtureIdentity $helperIdentities `
                    "$realLabel taskkill helper" `
                    ([int]$realTermination.TaskkillProcessId) `
                    ([long]$realTermination.TaskkillStartTimeFileTimeUtc)
            }
            Add-LatencyDiagnostic $realLabel $realClock.ElapsedMilliseconds 4000
            if ($treeKillSupported) {
                if (-not $realTermination.Proven -or
                    -not $realTermination.TreeKillAttempted -or
                    $realTermination.TreeKillMethod -cne $expectedTreeMethod) {
                    $failures.Add("$realLabel was not terminated with bounded Process.Kill(true) proof: $($realTermination | Out-String)") | Out-Null
                }
                Assert-ExactIdentityState "$realLabel parent" `
                    $realFixture.ParentIdentity @('gone', 'reused')
                Assert-ExactIdentityState "$realLabel descendant" `
                    $realFixture.ChildIdentity @('gone', 'reused')
            }
            else {
                Assert-RealTaskkillFixtureOutcome $realLabel $realTermination `
                    $realFixture.ParentIdentity $realFixture.ChildIdentity `
                    $realHelperIdentity $realClock.ElapsedMilliseconds
            }
        }

        # One production-default PS5 case starts the trusted taskkill directly
        # at an injected 12.5s elapsed point. This preserves the former 1.5s
        # action-budget boundary without a PowerShell wrapper whose taskkill
        # grandchild could escape helper containment if the wrapper timed out.
        if (-not $treeKillSupported) {
            $defaultPlan = New-WtHistoryProbeDeadlinePlan `
                -TimeoutMilliseconds 15000
            $defaultFixture = Start-PreparedNestedFixture '15s delayed real tree'
            $defaultClock = New-Object System.Diagnostics.Stopwatch
            $defaultTimingState = @{
                BaseElapsed = [long]12500
                Clock = $defaultClock
            }
            $defaultTiming = [pscustomobject]@{
                GetElapsedMilliseconds = ({
                    return [long]$defaultTimingState.BaseElapsed +
                        [long][Math]::Ceiling(
                            $defaultTimingState.Clock.Elapsed.TotalMilliseconds)
                }.GetNewClosure())
            }
            $defaultActionBudget = `
                Get-WtHistoryDeadlineRemainingMilliseconds `
                    -Clock $defaultClock `
                    -DeadlineMilliseconds `
                        $defaultPlan.TaskkillDeadlineMilliseconds `
                    -Timing $defaultTiming
            if ($defaultActionBudget -ne 1500) {
                $failures.Add("15s delayed real taskkill action budget drifted: expected=1500ms actual=${defaultActionBudget}ms") | Out-Null
            }
            $defaultClock.Start()
            try {
                $defaultTermination = Stop-WtHistoryProbeProcess `
                    -Process $defaultFixture.Process -Clock $defaultClock `
                    -TaskkillDeadlineMilliseconds `
                        $defaultPlan.TaskkillDeadlineMilliseconds `
                    -TotalDeadlineMilliseconds `
                        $defaultPlan.TotalDeadlineMilliseconds `
                    -ForceTaskkill -Timing $defaultTiming
            }
            finally {
                $defaultClock.Stop()
                $defaultFixture.Process.Dispose()
            }
            $defaultHelperIdentity = $null
            if ($defaultTermination.TaskkillProcessId -gt 0) {
                $defaultHelperIdentity = Register-FixtureIdentity $helperIdentities `
                    '15s delayed real taskkill helper' `
                    ([int]$defaultTermination.TaskkillProcessId) `
                    ([long]$defaultTermination.TaskkillStartTimeFileTimeUtc)
            }
            Add-LatencyDiagnostic '15s delayed real taskkill' `
                $defaultClock.ElapsedMilliseconds 4000
            Assert-RealTaskkillFixtureOutcome `
                '15s delayed real taskkill' $defaultTermination `
                $defaultFixture.ParentIdentity $defaultFixture.ChildIdentity `
                $defaultHelperIdentity $defaultClock.ElapsedMilliseconds
        }

        # An already-expired action deadline must refuse to launch any helper.
        $refusalClock = [System.Diagnostics.Stopwatch]::StartNew()
        Start-Sleep -Milliseconds 25
        $refusal = Invoke-WtHistoryBoundedTaskkill -TargetPid $PID `
            -Clock $refusalClock -TaskkillDeadlineMilliseconds 10 `
            -TotalDeadlineMilliseconds 100 `
            -StartInfoOverride (New-HostCommandStartInfo 'Start-Sleep -Seconds 30')
        $refusalClock.Stop()
        if ($refusal.Succeeded -or -not $refusal.TimedOut -or
            -not $refusal.TerminationProven -or $refusal.ProcessId -ne -1 -or
            $refusal.Error -cne 'no bounded budget remains for process-tree taskkill') {
            $failures.Add("expired taskkill deadline did not refuse before helper launch: $($refusal | Out-String)") | Out-Null
        }

        function New-FiniteHelperTiming([hashtable]$State) {
            # These cases test programmed deadlines, not host scheduling. One
            # separate setup ceiling synchronizes the real helper and BOTH
            # output tasks. Never spend a simulated 1687ms as an OS deadline,
            # restart the setup clock per wait, or report an incomplete task as
            # ready (production reads .Result only after this returns true).
            $State.ReadinessClock = [System.Diagnostics.Stopwatch]::StartNew()
            $waitReady = ({
                param($Waitable, [string]$Kind, [string]$Phase)
                $elapsed = if ($State.ContainsKey('ReadinessElapsed')) {
                    & $State.ReadinessElapsed
                } else { $State.ReadinessClock.Elapsed.TotalMilliseconds }
                $remaining = [Math]::Max(0, 10000 - [int][Math]::Ceiling($elapsed))
                if ($remaining -le 0) {
                    throw "finite-helper fixture readiness expired before $Phase"
                }
                $ready = if ($State.ContainsKey('ReadinessWait')) {
                    & $State.ReadinessWait $Waitable $Kind $remaining
                } elseif ($Kind -ceq 'process') {
                    $Waitable.WaitForExit($remaining)
                } else { $Waitable.Wait($remaining) }
                if (-not $ready) {
                    throw "finite-helper fixture readiness incomplete at $Phase"
                }
                return $true
            }.GetNewClosure())
            return [pscustomobject]@{
                GetElapsedMilliseconds = ({ return [long]$State.Elapsed }.GetNewClosure())
                WaitForExit = ({
                    param($Process, [int]$Milliseconds, [string]$Phase)
                    if (@('network-probe', 'taskkill-action', 'root-proof') -cnotcontains $Phase) { throw "unexpected finite-helper process wait: $Phase/${Milliseconds}ms" }
                    $expected = switch ($Phase) { 'network-probe' { 750 }; 'taskkill-action' { 1687 }; 'root-proof' { 2250 } }
                    if ($Milliseconds -ne $expected) { throw "wrong finite-helper programmed budget: $Phase/${Milliseconds}ms expected=${expected}ms" }
                    $State.Trace += "|process:$Phase=$Milliseconds"
                    if ($Phase -ceq 'network-probe') { $State.Elapsed = [long]750; return $false }
                    if ($Phase -ceq 'taskkill-action') {
                        [IO.File]::WriteAllText($State.ReleasePath, 'go')
                        return [bool](& $waitReady $Process 'process' $Phase)
                    }
                    $State.Elapsed = [long]2438; if (-not $Process.HasExited) { $Process.Kill() }
                    return [bool](& $waitReady $Process 'process' $Phase)
                }.GetNewClosure())
                WaitForTask = ({
                    param($Task, [int]$Milliseconds, [string]$Phase)
                    if (@('taskkill-output-stdout', 'taskkill-output-stderr') -cnotcontains $Phase) { throw "unexpected finite-helper task wait: $Phase/${Milliseconds}ms" }
                    if ($Milliseconds -ne 1687) { throw "wrong finite-helper programmed budget: $Phase/${Milliseconds}ms expected=1687ms" }
                    $State.Trace += "|task:$Phase=$Milliseconds"
                    return [bool](& $waitReady $Task 'task' $Phase)
                }.GetNewClosure())
            }
        }

        # An injected scheduler delay may exceed the virtual action slice;
        # actual synchronization still consumes ONE independent setup budget.
        $readyTrace = New-Object 'System.Collections.Generic.List[int]'
        $readyState = @{ Elapsed = [long]750; Trace = ''; ReleasePath = New-FixturePidPath; ReadyElapsed = [long]5763 }
        $readyState.ReadinessElapsed = ({ return $readyState.ReadyElapsed }.GetNewClosure())
        $readyState.ReadinessWait = ({
            param($Waitable, $Kind, [int]$Milliseconds)
            $readyTrace.Add($Milliseconds)
            if ($Kind -ceq 'process') { $readyState.ReadyElapsed = [long]7000 }
            else { $readyState.ReadyElapsed = [long]10000 }
            return $true
        }.GetNewClosure())
        $readyTiming = New-FiniteHelperTiming $readyState
        $readyProcessWait = $readyTiming.WaitForExit
        $readyTaskWait = $readyTiming.WaitForTask
        $null = & $readyProcessWait $null 1687 'taskkill-action'
        $null = & $readyTaskWait $null 1687 'taskkill-output-stdout'
        $expiredRejected = $false
        try { $null = & $readyTaskWait $null 1687 'taskkill-output-stderr' }
        catch { $expiredRejected = $_.Exception.Message -like '*readiness expired*' }
        if (-not $expiredRejected -or ($readyTrace -join ',') -cne '4237,3000') {
            $failures.Add("finite-helper setup restarted or charged virtual time: waits=$($readyTrace -join ',') expiredRejected=$expiredRejected") | Out-Null
        }
        foreach ($invalidWait in @(
                @{ Kind = 'task'; Phase = 'taskkill-output-stdout'; Budget = 1686; Message = '*wrong finite-helper programmed budget*' }
                @{ Kind = 'task'; Phase = 'network-output-stdout'; Budget = 1687; Message = '*unexpected finite-helper task wait*' }
                @{ Kind = 'process'; Phase = 'taskkill-action'; Budget = 1686; Message = '*wrong finite-helper programmed budget*' }
                @{ Kind = 'process'; Phase = 'taskkill-containment'; Budget = 1687; Message = '*unexpected finite-helper process wait*' }
            )) {
            $rejected = $false
            $invalidCallback = if ($invalidWait.Kind -ceq 'task') { $readyTaskWait } else { $readyProcessWait }
            try { $null = & $invalidCallback $null $invalidWait.Budget $invalidWait.Phase }
            catch { $rejected = $_.Exception.Message -like $invalidWait.Message }
            if (-not $rejected) { $failures.Add('finite-helper callback accepted an invalid phase/budget') | Out-Null }
        }
        # A genuinely incomplete task must throw, not return a fake successful
        # wait that lets the caller block forever on Task.Result.
        $pendingTask = New-Object 'System.Threading.Tasks.TaskCompletionSource[string]'
        $stalledState = @{ Elapsed = [long]750; Trace = ''; ReadinessElapsed = { return 9999 } }
        $stalledTiming = New-FiniteHelperTiming $stalledState
        $stalledTaskWait = $stalledTiming.WaitForTask
        $stallRejected = $false
        try { $null = & $stalledTaskWait $pendingTask.Task 1687 'taskkill-output-stdout' }
        catch { $stallRejected = $_.Exception.Message -like '*readiness incomplete*' }
        if (-not $stallRejected -or $pendingTask.Task.IsCompleted) {
            $failures.Add('finite-helper incomplete task escaped as ready before Result readback') | Out-Null
        }
        $stalledState.ReleasePath = New-FixturePidPath
        $stalledState.ReadinessWait = { return $false }
        $stalledProcessWait = $stalledTiming.WaitForExit
        $processStallRejected = $false
        try { $null = & $stalledProcessWait $null 1687 'taskkill-action' }
        catch { $processStallRejected = $_.Exception.Message -like '*readiness incomplete*' }
        if (-not $processStallRejected) {
            $failures.Add('finite-helper incomplete process escaped as ready') | Out-Null
        }

        # Inject time to prove helper action budget donation without moving the total deadline.
        $donationTimingState = @{ Elapsed = [long]750; Trace = ''; ReleasePath = New-FixturePidPath }
        $donationProcess = New-Object System.Diagnostics.Process
        try {
            $donationProcess.StartInfo = New-HostCommandStartInfo 'Start-Sleep -Seconds 30'
            if (-not $donationProcess.Start()) {
                throw 'unused-taskkill donation target did not start'
            }
            $donationIdentity = Register-FixtureIdentity $fixtureIdentities `
                'unused-taskkill donation target' $donationProcess.Id `
                ([long]$donationProcess.StartTime.ToFileTimeUtc())
            $donationTermination = Stop-WtHistoryProbeProcess `
                -Process $donationProcess -Clock $injectedClock `
                -TaskkillDeadlineMilliseconds `
                    $threeSecondPlan.TaskkillDeadlineMilliseconds `
                -TotalDeadlineMilliseconds `
                    $threeSecondPlan.TotalDeadlineMilliseconds `
                -ForceTaskkill -TaskkillStartInfoOverride `
                    (New-HostCommandStartInfo ("while (-not [IO.File]::Exists('" + $donationTimingState.ReleasePath.Replace("'", "''") + "')) { Start-Sleep -Milliseconds 10 }; exit 0")) `
                -Timing (New-FiniteHelperTiming $donationTimingState)
        }
        finally { $donationProcess.Dispose() }
        $donationHelperIdentity = $null
        if ($donationTermination.TaskkillProcessId -gt 0) {
            $donationHelperIdentity = Register-FixtureIdentity $helperIdentities `
                'unused-taskkill donation helper' `
                ([int]$donationTermination.TaskkillProcessId) `
                ([long]$donationTermination.TaskkillStartTimeFileTimeUtc)
        }
        if (-not $donationTermination.Proven -or
            $donationTermination.TaskkillExitCode -ne 0 -or
            $donationTimingState.Trace -cne '|process:taskkill-action=1687|task:taskkill-output-stdout=1687|task:taskkill-output-stderr=1687|process:root-proof=2250' -or
            $donationTimingState.Elapsed -ne 2438) {
            $failures.Add("unused taskkill time was not donated within the immutable total deadline: trace=$($donationTimingState.Trace) elapsed=$($donationTimingState.Elapsed) result=$($donationTermination | Out-String)") | Out-Null
        }
        Assert-ExactIdentityState 'unused-taskkill donation target' `
            $donationIdentity @('gone', 'reused')
        if ($donationHelperIdentity) {
            Assert-ExactIdentityState 'unused-taskkill donation helper' `
                $donationHelperIdentity @('gone', 'reused')
        }

        # Hold virtual time steady to prove fail-closed exit-7 capture independent of startup.
        $failureTimingState = @{ Elapsed = [long]0; Trace = ''; ReleasePath = New-FixturePidPath }
        $taskkillFailure = Invoke-WtHistoryBoundedProcessProbe `
            -StartInfo (New-HostCommandStartInfo 'Start-Sleep -Seconds 30') `
            -TimeoutMs 3000 -ForceTaskkill `
            -TaskkillStartInfoOverride `
                (New-HostCommandStartInfo ("while (-not [IO.File]::Exists('" + $failureTimingState.ReleasePath.Replace("'", "''") + "')) { Start-Sleep -Milliseconds 10 }; exit 7")) `
            -Timing (New-FiniteHelperTiming $failureTimingState)
        $failureParentIdentity = Register-FixtureIdentity $fixtureIdentities `
            'failed-taskkill target' ([int]$taskkillFailure.ProcessId) `
            ([long]$taskkillFailure.ProcessStartTimeFileTimeUtc)
        $failureHelperIdentity = $null
        if ($taskkillFailure.TaskkillProcessId -gt 0) {
            $failureHelperIdentity = Register-FixtureIdentity $helperIdentities `
                'failed taskkill helper' `
                ([int]$taskkillFailure.TaskkillProcessId) `
                ([long]$taskkillFailure.TaskkillStartTimeFileTimeUtc)
        }
        if (-not $taskkillFailure.TimedOut -or
            $taskkillFailure.TerminationProven -or
            $taskkillFailure.TaskkillExitCode -ne 7 -or
            $taskkillFailure.TaskkillTimedOut -or
            -not $taskkillFailure.TaskkillTerminationProven -or
            $failureTimingState.Trace -cne '|process:network-probe=750|process:taskkill-action=1687|task:taskkill-output-stdout=1687|task:taskkill-output-stderr=1687' -or
            $taskkillFailure.TerminationError.IndexOf('exited 7',
                [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("injected taskkill failure was not captured and fail-closed: $($taskkillFailure | Out-String)") | Out-Null
        }
        Assert-State 'optional taskkill failure' $taskkillFailure $false 'skip'
        Assert-State 'required taskkill failure' $taskkillFailure $true 'fail'
        Assert-ExactIdentityState 'failed-taskkill target' `
            $failureParentIdentity @('alive')
        if ($failureHelperIdentity) {
            Assert-ExactIdentityState 'failed taskkill helper' `
                $failureHelperIdentity @('gone', 'reused')
        }

        # A setup failure is not an accepted termination outcome. Exercise the
        # real production catch/identity path after helper exit but before any
        # output Result read, then retain both identities for final cleanup.
        $setupFailureState = @{ Elapsed = [long]0; Trace = ''; ReleasePath = New-FixturePidPath }
        $setupFailureState.ReadinessWait = {
            param($Waitable, $Kind, [int]$Milliseconds)
            if ($Kind -ceq 'task') { return $false }
            return [bool]$Waitable.WaitForExit($Milliseconds)
        }
        $setupFailure = Invoke-WtHistoryBoundedProcessProbe `
            -StartInfo (New-HostCommandStartInfo 'Start-Sleep -Seconds 30') `
            -TimeoutMs 3000 -ForceTaskkill `
            -TaskkillStartInfoOverride `
                (New-HostCommandStartInfo ("while (-not [IO.File]::Exists('" + $setupFailureState.ReleasePath.Replace("'", "''") + "')) { Start-Sleep -Milliseconds 10 }; exit 7")) `
            -Timing (New-FiniteHelperTiming $setupFailureState)
        $setupParentIdentity = Register-FixtureIdentity $fixtureIdentities `
            'setup-failed taskkill target' ([int]$setupFailure.ProcessId) `
            ([long]$setupFailure.ProcessStartTimeFileTimeUtc)
        $setupHelperIdentity = Register-FixtureIdentity $helperIdentities `
            'setup-failed taskkill helper' ([int]$setupFailure.TaskkillProcessId) `
            ([long]$setupFailure.TaskkillStartTimeFileTimeUtc)
        if (-not $setupFailure.TimedOut -or $setupFailure.TerminationProven -or
            -not $setupFailure.TaskkillTerminationProven -or
            $setupFailure.TerminationError -notlike '*readiness incomplete at taskkill-output-stdout*' -or
            $setupFailureState.Trace -cne '|process:network-probe=750|process:taskkill-action=1687|task:taskkill-output-stdout=1687') {
            $failures.Add("finite-helper setup failure escaped or reached output/root proof: $($setupFailure | Out-String)") | Out-Null
        }
        Assert-State 'optional setup failure' $setupFailure $false 'skip'
        Assert-State 'required setup failure' $setupFailure $true 'fail'
        Assert-ExactIdentityState 'setup-failed taskkill target' $setupParentIdentity @('alive')
        Assert-ExactIdentityState 'setup-failed taskkill helper' $setupHelperIdentity @('gone', 'reused')

        # Keep one real Windows PowerShell 5.1 hanging-helper containment case
        # for exact PID/start cleanup and orphan detection. PS7 exercises the
        # same forced-taskkill path through the deterministic 5763ms fixture.
        if (-not $treeKillSupported) {
            $helperTimeoutClock = [System.Diagnostics.Stopwatch]::StartNew()
            $taskkillTimeout = Invoke-WtHistoryBoundedProcessProbe `
                -StartInfo (New-HostCommandStartInfo 'Start-Sleep -Seconds 30') `
                -TimeoutMs 3000 -ForceTaskkill `
                -TaskkillStartInfoOverride `
                    (New-HostCommandStartInfo 'Start-Sleep -Seconds 30')
            $helperTimeoutClock.Stop()
            $timeoutParentIdentity = Register-FixtureIdentity $fixtureIdentities `
                'timed-out-taskkill target' ([int]$taskkillTimeout.ProcessId) `
                ([long]$taskkillTimeout.ProcessStartTimeFileTimeUtc)
            $timeoutHelperIdentity = $null
            if ($taskkillTimeout.TaskkillProcessId -gt 0) {
                $timeoutHelperIdentity = Register-FixtureIdentity $helperIdentities `
                    'timed-out taskkill helper' `
                    ([int]$taskkillTimeout.TaskkillProcessId) `
                    ([long]$taskkillTimeout.TaskkillStartTimeFileTimeUtc)
            }
            if (-not $taskkillTimeout.TimedOut -or
                $taskkillTimeout.TerminationProven -or
                -not $taskkillTimeout.TaskkillTimedOut -or
                -not $taskkillTimeout.TaskkillTerminationProven -or
                $taskkillTimeout.TerminationError.IndexOf('timed out',
                    [StringComparison]::Ordinal) -lt 0 -or
                $helperTimeoutClock.ElapsedMilliseconds -lt
                    ($threeSecondPlan.TaskkillDeadlineMilliseconds - 100)) {
                $failures.Add("taskkill helper timeout was not contained and fail-closed: $($taskkillTimeout | Out-String)") | Out-Null
            }
            Add-LatencyDiagnostic 'real PS5.1 hanging taskkill helper' `
                $helperTimeoutClock.ElapsedMilliseconds 4000
            Assert-State 'optional taskkill timeout' $taskkillTimeout $false 'skip'
            Assert-State 'required taskkill timeout' $taskkillTimeout $true 'fail'
            Assert-ExactIdentityState 'timed-out-taskkill target' `
                $timeoutParentIdentity @('alive')
            if ($timeoutHelperIdentity) {
                Assert-ExactIdentityState 'timed-out taskkill helper' `
                    $timeoutHelperIdentity @('gone', 'reused')
            } else {
                $failures.Add('timed-out taskkill helper identity is unavailable') | Out-Null
            }
        }
    }
    catch {
        $failures.Add("real process fixture crashed: $($_.Exception.Message) at $($_.ScriptStackTrace)") | Out-Null
    }
    finally {
        foreach ($identity in $fixtureIdentities.ToArray()) {
            $fixturePid = [int]$identity.ProcessId
            $fixtureStart = [long]$identity.StartTimeFileTimeUtc
            $fixtureState = Get-WtHistoryProcessIdentityState `
                -ProcessId $fixturePid `
                -StartTimeFileTimeUtc $fixtureStart
            if ($fixtureState -ceq 'alive' -and
                -not (Stop-FixtureProcess -FixturePid $fixturePid `
                    -ExpectedStartTimeFileTimeUtc $fixtureStart)) {
                $failures.Add("$($identity.Label) cleanup could not prove exact-identity termination: PID $fixturePid") | Out-Null
            }
            elseif ($fixtureState -ceq 'unavailable') {
                $failures.Add("$($identity.Label) identity was unavailable during cleanup: PID $fixturePid") | Out-Null
            }
            $afterState = Get-WtHistoryProcessIdentityState `
                -ProcessId $fixturePid `
                -StartTimeFileTimeUtc $fixtureStart
            if (@('gone', 'reused') -cnotcontains $afterState) {
                $failures.Add("$($identity.Label) remained live or unobservable after cleanup: PID $fixturePid state=$afterState") | Out-Null
            }
        }
        foreach ($helperIdentity in $helperIdentities.ToArray()) {
            $helperPid = [int]$helperIdentity.ProcessId
            $helperStart = [long]$helperIdentity.StartTimeFileTimeUtc
            $helperState = Get-WtHistoryProcessIdentityState `
                -ProcessId $helperPid -StartTimeFileTimeUtc $helperStart
            if ($helperState -ceq 'alive' -and
                -not (Stop-FixtureProcess -FixturePid $helperPid `
                    -ExpectedStartTimeFileTimeUtc $helperStart)) {
                $failures.Add("taskkill helper cleanup could not prove termination: PID $helperPid") | Out-Null
            }
            elseif ($helperState -ceq 'unavailable') {
                $failures.Add("taskkill helper identity was unavailable during cleanup: PID $helperPid") | Out-Null
            }
            $afterState = Get-WtHistoryProcessIdentityState `
                -ProcessId $helperPid -StartTimeFileTimeUtc $helperStart
            if (@('gone', 'reused') -cnotcontains $afterState) {
                $failures.Add("taskkill helper remained live or unobservable after cleanup: PID $helperPid state=$afterState") | Out-Null
            }
        }
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        foreach ($pidPath in @($fixturePidPaths)) {
            $fullPidPath = [IO.Path]::GetFullPath($pidPath)
            if ($fullPidPath.StartsWith($tempRoot,
                    [StringComparison]::OrdinalIgnoreCase) -and
                (Test-Path -LiteralPath $fullPidPath -PathType Leaf)) {
                Remove-Item -LiteralPath $fullPidPath -Force
            }
        }
    }

    if ($latencyDiagnostics.Count -gt 0) {
        $latencyDiagnostics | ForEach-Object {
            Write-Host "  [DIAG] $_" -ForegroundColor DarkYellow
        }
    }
    if ($failures.Count -gt 0) {
        Write-Host '[check_wt_history_source_freshness:selftest] FAILED' -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        exit 2
    }
    Write-Host '[check_wt_history_source_freshness:selftest] OK - schema-2/current and schema-1/legacy anchors, injected programmed-wait deadlines, exact process containment, shared-matrix ownership, change-set scoped moved-tip advisories (#1683), and no-orphan cleanup pass.' -ForegroundColor Green
    exit 0
}

if ($SelfTest) { Invoke-FreshnessSelfTest }

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $anchor = Read-WtHistorySourceAnchor -RepoRoot $root
    if ($Offline) {
        if ($RequireRemoteFresh) {
            throw '-Offline cannot satisfy -RequireRemoteFresh'
        }
        Write-Host '[check_wt_history_source_freshness] SKIP - explicit offline mode; pinned provenance remains enforced.' -ForegroundColor Yellow
        exit 0
    }
    $probe = Invoke-WtHistoryRemoteProbe -Anchor $anchor -TimeoutMs $TimeoutMilliseconds
    $result = Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $probe `
        -Required:$RequireRemoteFresh
    # Issue #1683: only WT streams consume this provenance, so ordinary QA
    # scopes a moved ref/tip to the checked change set. The self-test drives
    # this same decision function over real git fixtures.
    $decision = Invoke-WtHistoryFreshnessDecision -Result $result -RepoRoot $root -Staged:$Staged -RequireRemoteFresh:$RequireRemoteFresh -Quiet:$Quiet
    if ($decision.ExitCode -ge 2) { throw $decision.Message }
    if ($decision.Print) { Write-Host $decision.Line -ForegroundColor $decision.Color }
    exit $decision.ExitCode
}
catch {
    Write-Host "[check_wt_history_source_freshness] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
