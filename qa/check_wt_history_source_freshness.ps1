# Optional ordinary-QA / required release freshness gate for weapon-history
# source provenance. It reads the canonical remote with git ls-remote only:
# no fetch, no FETCH_HEAD write, and no mutation of a source checkout.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [ValidateRange(1000, 60000)][int]$TimeoutMilliseconds = 15000,
    [switch]$RequireRemoteFresh,
    [switch]$Offline,
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

function New-FreshnessResult([string]$State, [string]$Message) {
    return [pscustomobject]@{ State = $State; Message = $Message }
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
            "canonical default ref moved: pinned=$($Anchor.DefaultRef) remote=$remoteRef"
    }
    if ($remoteTip -cne $Anchor.ObservedDefaultTip) {
        return New-FreshnessResult 'fail' `
            "canonical default tip moved: pinned=$($Anchor.ObservedDefaultTip) remote=$remoteTip"
    }
    return New-FreshnessResult 'pass' `
        "canonical default tip matches $remoteTip (semantic 6.12.0 content $($Anchor.ContentRevision))"
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

function Invoke-WtHistoryBoundedTaskkill {
    param(
        [Parameter(Mandatory)][int]$TargetPid,
        [ValidateRange(1, 60000)][int]$TimeoutMilliseconds,
        [System.Diagnostics.ProcessStartInfo]$StartInfoOverride
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $helper = New-Object System.Diagnostics.Process
    $started = $false
    $helperPid = -1
    [long]$helperStartTimeFileTimeUtc = -1
    try {
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

        # The helper's own containment belongs to this same total budget.
        $containmentReserve = [Math]::Min(250,
            [Math]::Max(50, [int][Math]::Ceiling($TimeoutMilliseconds / 4.0)))
        if ($containmentReserve -ge $TimeoutMilliseconds) {
            $containmentReserve = $TimeoutMilliseconds - 1
        }
        $runBudget = $TimeoutMilliseconds - $containmentReserve
        if (-not $helper.WaitForExit($runBudget)) {
            $killError = ''
            try {
                if (-not $helper.HasExited) { $helper.Kill() }
            }
            catch { $killError = $_.Exception.Message }

            $remaining = [Math]::Max(0,
                $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
            $helperProven = $false
            try {
                $helperProven = if ($helper.HasExited) { $true }
                elseif ($remaining -gt 0) { $helper.WaitForExit($remaining) }
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

        $remaining = [Math]::Max(0,
            $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
        $stdoutComplete = $stdoutTask.Wait($remaining)
        $remaining = [Math]::Max(0,
            $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
        $stderrComplete = $stderrTask.Wait($remaining)
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
                if (-not $helper.HasExited) { $helper.Kill() }
                $remaining = [Math]::Max(0,
                    $TimeoutMilliseconds - [int]$clock.ElapsedMilliseconds)
                $helperProven = if ($helper.HasExited) { $true }
                elseif ($remaining -gt 0) { $helper.WaitForExit($remaining) }
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
        $clock.Stop()
        $helper.Dispose()
    }
}

function Stop-WtHistoryProbeProcess {
    param(
        [Parameter(Mandatory)][System.Diagnostics.Process]$Process,
        [ValidateRange(0, 60000)][int]$WaitMilliseconds,
        [System.Diagnostics.ProcessStartInfo]$TaskkillStartInfoOverride,
        [switch]$ForceTaskkill
    )

    $clock = [System.Diagnostics.Stopwatch]::StartNew()
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
        # capture its result, and keep its execution/containment inside the
        # caller's remaining total budget.
        $treeKillAttempted = $true
        $treeKillMethodName = 'taskkill.exe /T /F'
        $rootProofReserve = [Math]::Min(250,
            [Math]::Max(50, [int][Math]::Ceiling($WaitMilliseconds / 4.0)))
        if ($rootProofReserve -ge $WaitMilliseconds) {
            $rootProofReserve = [Math]::Max(0, $WaitMilliseconds - 1)
        }
        $taskkillBudget = $WaitMilliseconds - $rootProofReserve
        if ($taskkillBudget -le 0) {
            return [pscustomobject]@{
                Proven = $false
                Error = 'no bounded budget remains for process-tree taskkill'
                TreeKillAttempted = $true
                TreeKillMethod = $treeKillMethodName
                TaskkillProcessId = -1
                TaskkillStartTimeFileTimeUtc = -1
                TaskkillTerminationProven = $true
                TaskkillTimedOut = $false
                TaskkillExitCode = -1
            }
        }
        $taskkillResult = Invoke-WtHistoryBoundedTaskkill `
            -TargetPid $Process.Id -TimeoutMilliseconds $taskkillBudget `
            -StartInfoOverride $TaskkillStartInfoOverride
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
        $remaining = [Math]::Max(0,
            $WaitMilliseconds - [int]$clock.ElapsedMilliseconds)
        $proven = if ($Process.HasExited) { $true }
        elseif ($remaining -gt 0) {
            $Process.WaitForExit($remaining)
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
    finally { $clock.Stop() }
}

function Invoke-WtHistoryBoundedProcessProbe {
    param(
        [Parameter(Mandatory)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [ValidateRange(1000, 60000)][int]$TimeoutMs,
        [System.Diagnostics.ProcessStartInfo]$TaskkillStartInfoOverride,
        [switch]$ForceTaskkill
    )

    # Reserve a bounded slice of the caller's advertised total budget for
    # termination proof. Execution + kill + post-kill wait never requests more
    # than TimeoutMs; there is no parameterless WaitForExit or Task.Result wait.
    $terminationBudget = [Math]::Min(2000,
        [Math]::Max(1000, [int][Math]::Ceiling($TimeoutMs / 5.0)))
    if ($terminationBudget -ge $TimeoutMs) {
        $terminationBudget = [int][Math]::Floor($TimeoutMs / 2.0)
    }
    $executionBudget = $TimeoutMs - $terminationBudget
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
        if (-not $process.WaitForExit($executionBudget)) {
            $remaining = [Math]::Max(0, $TimeoutMs - [int]$clock.ElapsedMilliseconds)
            $termination = Stop-WtHistoryProbeProcess -Process $process `
                -WaitMilliseconds $remaining `
                -TaskkillStartInfoOverride $TaskkillStartInfoOverride `
                -ForceTaskkill:$ForceTaskkill
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

        $remaining = [Math]::Max(0, $TimeoutMs - [int]$clock.ElapsedMilliseconds)
        $stdoutComplete = $stdoutTask.Wait($remaining)
        $remaining = [Math]::Max(0, $TimeoutMs - [int]$clock.ElapsedMilliseconds)
        $stderrComplete = $stderrTask.Wait($remaining)
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
            $remaining = [Math]::Max(0, $TimeoutMs - [int]$clock.ElapsedMilliseconds)
            $termination = Stop-WtHistoryProbeProcess -Process $process `
                -WaitMilliseconds $remaining `
                -TaskkillStartInfoOverride $TaskkillStartInfoOverride `
                -ForceTaskkill:$ForceTaskkill
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
    $fixtureIdentities = New-Object 'System.Collections.Generic.List[object]'
    $helperIdentities = New-Object 'System.Collections.Generic.List[object]'
    $fixturePidPaths = New-Object 'System.Collections.Generic.List[string]'
    $anchor = [pscustomobject]@{
        DefaultRef = 'refs/heads/master'
        ObservedDefaultTip = ('a' * 40)
        ContentRevision = ('b' * 40)
    }
    function Assert-State([string]$Name, $Probe, [bool]$Required, [string]$Expected) {
        $result = Test-WtHistoryRemoteProbe -Anchor $anchor -Probe $Probe -Required:$Required
        if ($result.State -cne $Expected) {
            $failures.Add("$Name expected=$Expected actual=$($result.State): $($result.Message)") |
                Out-Null
        }
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
        while ($clock.ElapsedMilliseconds -lt 1000 -and
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

        $realPidPath = New-FixturePidPath
        $realClock = [System.Diagnostics.Stopwatch]::StartNew()
        $realTimeout = Invoke-WtHistoryBoundedProcessProbe `
            -StartInfo (New-NestedHangingStartInfo $realPidPath) -TimeoutMs 3000
        $realClock.Stop()
        $realParentIdentity = Register-FixtureIdentity $fixtureIdentities `
            'real nested parent' ([int]$realTimeout.ProcessId) `
            ([long]$realTimeout.ProcessStartTimeFileTimeUtc)
        $realChildRecordedIdentity = Read-FixtureChildIdentity $realPidPath
        $realChildIdentity = if ($realChildRecordedIdentity) {
            Register-FixtureIdentity $fixtureIdentities `
                'real nested descendant' `
                ([int]$realChildRecordedIdentity.ProcessId) `
                ([long]$realChildRecordedIdentity.StartTimeFileTimeUtc)
        } else {
            $failures.Add('real nested descendant identity was not recorded') | Out-Null
            $null
        }
        $realHelperIdentity = $null
        if ($realTimeout.TaskkillProcessId -gt 0) {
            $realHelperIdentity = Register-FixtureIdentity $helperIdentities `
                'real taskkill helper' ([int]$realTimeout.TaskkillProcessId) `
                ([long]$realTimeout.TaskkillStartTimeFileTimeUtc)
        }
        if (-not $realTimeout.TimedOut -or -not $realTimeout.KillAttempted -or
            -not $realTimeout.TreeKillAttempted -or
            -not $realTimeout.TerminationProven -or -not $realChildIdentity) {
            $failures.Add("real nested process tree was not terminated with bounded proof: $($realTimeout | Out-String)") | Out-Null
        }
        if ($realClock.ElapsedMilliseconds -gt 5000) {
            $failures.Add("real nested-tree timeout exceeded its bounded wall allowance: $($realClock.ElapsedMilliseconds)ms") | Out-Null
        }
        $expectedTreeMethod = if ($treeKillSupported) {
            'Process.Kill(true)'
        } else { 'taskkill.exe /T /F' }
        if ($realTimeout.TreeKillMethod -cne $expectedTreeMethod) {
            $failures.Add("real nested tree used wrong termination method: expected=$expectedTreeMethod actual=$($realTimeout.TreeKillMethod)") | Out-Null
        }
        if (-not $treeKillSupported -and
            ($realTimeout.TaskkillExitCode -ne 0 -or
                $realTimeout.TaskkillTimedOut -or
                -not $realTimeout.TaskkillTerminationProven)) {
            $failures.Add("PS5 taskkill result was not captured as an exact success: $($realTimeout | Out-String)") | Out-Null
        }
        foreach ($identity in @($realParentIdentity, $realChildIdentity)) {
            if (-not $identity) { continue }
            $identityState = Get-WtHistoryProcessIdentityState `
                -ProcessId $identity.ProcessId `
                -StartTimeFileTimeUtc $identity.StartTimeFileTimeUtc
            if (@('gone', 'reused') -cnotcontains $identityState) {
                $failures.Add("$($identity.Label) identity is not proven gone: PID $($identity.ProcessId) state=$identityState") | Out-Null
            }
        }
        if ($realHelperIdentity) {
            $realHelperState = Get-WtHistoryProcessIdentityState `
                -ProcessId $realHelperIdentity.ProcessId `
                -StartTimeFileTimeUtc $realHelperIdentity.StartTimeFileTimeUtc
            if (@('gone', 'reused') -cnotcontains $realHelperState) {
                $failures.Add("real taskkill helper identity is not proven gone: PID $($realHelperIdentity.ProcessId) state=$realHelperState") | Out-Null
            }
        }

        $failurePidPath = New-FixturePidPath
        $failureClock = [System.Diagnostics.Stopwatch]::StartNew()
        $taskkillFailure = Invoke-WtHistoryBoundedProcessProbe `
            -StartInfo (New-NestedHangingStartInfo $failurePidPath) `
            -TimeoutMs 3000 -ForceTaskkill `
            -TaskkillStartInfoOverride (New-HostCommandStartInfo 'exit 7')
        $failureClock.Stop()
        $failureParentIdentity = Register-FixtureIdentity $fixtureIdentities `
            'failed-taskkill nested parent' ([int]$taskkillFailure.ProcessId) `
            ([long]$taskkillFailure.ProcessStartTimeFileTimeUtc)
        $failureChildRecordedIdentity = Read-FixtureChildIdentity $failurePidPath
        $failureChildIdentity = if ($failureChildRecordedIdentity) {
            Register-FixtureIdentity $fixtureIdentities `
                'failed-taskkill nested descendant' `
                ([int]$failureChildRecordedIdentity.ProcessId) `
                ([long]$failureChildRecordedIdentity.StartTimeFileTimeUtc)
        } else {
            $failures.Add('failed-taskkill nested descendant identity was not recorded') | Out-Null
            $null
        }
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
            $taskkillFailure.TerminationError.IndexOf('exited 7',
                [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("injected taskkill failure was not captured and fail-closed: $($taskkillFailure | Out-String)") | Out-Null
        }
        if ($failureClock.ElapsedMilliseconds -gt 5000) {
            $failures.Add("injected taskkill failure exceeded its bounded wall allowance: $($failureClock.ElapsedMilliseconds)ms") | Out-Null
        }
        Assert-State 'optional taskkill failure' $taskkillFailure $false 'skip'
        Assert-State 'required taskkill failure' $taskkillFailure $true 'fail'
        foreach ($identity in @($failureParentIdentity, $failureChildIdentity)) {
            if (-not $identity) { continue }
            $identityState = Get-WtHistoryProcessIdentityState `
                -ProcessId $identity.ProcessId `
                -StartTimeFileTimeUtc $identity.StartTimeFileTimeUtc
            if ($identityState -cne 'alive') {
                $failures.Add("$($identity.Label) was not retained alive for exact-identity cleanup: PID $($identity.ProcessId) state=$identityState") | Out-Null
            }
        }
        if ($failureHelperIdentity) {
            $failureHelperState = Get-WtHistoryProcessIdentityState `
                -ProcessId $failureHelperIdentity.ProcessId `
                -StartTimeFileTimeUtc $failureHelperIdentity.StartTimeFileTimeUtc
            if (@('gone', 'reused') -cnotcontains $failureHelperState) {
                $failures.Add("failed taskkill helper identity is not proven gone: PID $($failureHelperIdentity.ProcessId) state=$failureHelperState") | Out-Null
            }
        }

        $timeoutPidPath = New-FixturePidPath
        $helperTimeoutClock = [System.Diagnostics.Stopwatch]::StartNew()
        $taskkillTimeout = Invoke-WtHistoryBoundedProcessProbe `
            -StartInfo (New-NestedHangingStartInfo $timeoutPidPath) `
            -TimeoutMs 3000 -ForceTaskkill `
            -TaskkillStartInfoOverride `
                (New-HostCommandStartInfo 'Start-Sleep -Seconds 30')
        $helperTimeoutClock.Stop()
        $timeoutParentIdentity = Register-FixtureIdentity $fixtureIdentities `
            'timed-out-taskkill nested parent' ([int]$taskkillTimeout.ProcessId) `
            ([long]$taskkillTimeout.ProcessStartTimeFileTimeUtc)
        $timeoutChildRecordedIdentity = Read-FixtureChildIdentity $timeoutPidPath
        $timeoutChildIdentity = if ($timeoutChildRecordedIdentity) {
            Register-FixtureIdentity $fixtureIdentities `
                'timed-out-taskkill nested descendant' `
                ([int]$timeoutChildRecordedIdentity.ProcessId) `
                ([long]$timeoutChildRecordedIdentity.StartTimeFileTimeUtc)
        } else {
            $failures.Add('timed-out-taskkill nested descendant identity was not recorded') | Out-Null
            $null
        }
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
                [StringComparison]::Ordinal) -lt 0) {
            $failures.Add("taskkill helper timeout was not bounded, contained, and fail-closed: $($taskkillTimeout | Out-String)") | Out-Null
        }
        if ($helperTimeoutClock.ElapsedMilliseconds -gt 5000) {
            $failures.Add("taskkill helper timeout exceeded its bounded wall allowance: $($helperTimeoutClock.ElapsedMilliseconds)ms") | Out-Null
        }
        Assert-State 'optional taskkill timeout' $taskkillTimeout $false 'skip'
        Assert-State 'required taskkill timeout' $taskkillTimeout $true 'fail'
        foreach ($identity in @($timeoutParentIdentity, $timeoutChildIdentity)) {
            if (-not $identity) { continue }
            $identityState = Get-WtHistoryProcessIdentityState `
                -ProcessId $identity.ProcessId `
                -StartTimeFileTimeUtc $identity.StartTimeFileTimeUtc
            if ($identityState -cne 'alive') {
                $failures.Add("$($identity.Label) was not retained alive for exact-identity cleanup: PID $($identity.ProcessId) state=$identityState") | Out-Null
            }
        }
        $timeoutHelperState = if ($timeoutHelperIdentity) {
            Get-WtHistoryProcessIdentityState `
                -ProcessId $timeoutHelperIdentity.ProcessId `
                -StartTimeFileTimeUtc $timeoutHelperIdentity.StartTimeFileTimeUtc
        } else { 'unavailable' }
        if (@('gone', 'reused') -cnotcontains $timeoutHelperState) {
            $failures.Add("timed-out taskkill helper identity is not proven gone: PID $($taskkillTimeout.TaskkillProcessId) state=$timeoutHelperState") | Out-Null
        }
    }
    catch {
        $failures.Add("real process fixture crashed: $($_.Exception.Message)") | Out-Null
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

    if ($failures.Count -gt 0) {
        Write-Host '[check_wt_history_source_freshness:selftest] FAILED' -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        exit 2
    }
    Write-Host '[check_wt_history_source_freshness:selftest] OK - identity policies, handle-bound PID-reuse-safe nested-tree termination, bounded taskkill failure/timeout containment, and no-orphan cleanup pass.' -ForegroundColor Green
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
    if ($result.State -ceq 'fail') { throw $result.Message }
    if (-not $Quiet -or $result.State -ceq 'skip') {
        $color = if ($result.State -ceq 'pass') { 'Green' } else { 'Yellow' }
        Write-Host "[check_wt_history_source_freshness] $($result.State.ToUpperInvariant()) - $($result.Message)" -ForegroundColor $color
    }
    exit 0
}
catch {
    Write-Host "[check_wt_history_source_freshness] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
