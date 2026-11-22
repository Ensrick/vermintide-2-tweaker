#requires -Version 7
<#
.SYNOPSIS
  Turns one rig run's evidence into its case table and exit code (WP-H-09): PASS, FAIL, ERROR, TIMEOUT,
  INCONCLUSIVE and CRASH.

.DESCRIPTION
  run.ps1 calls this after the game is gone; tools/harness/tests/Verdicts.Tests.ps1 calls it with canned evidence.
  Nothing here reads the game or the disk.

  - A case's verdict is its "CASE END" evidence line (the driver's PASS, FAIL, ERROR, TIMEOUT or INCONCLUSIVE).
  - The console log is buffered, so a process that dies loses the log's tail (H.md proven fact 6). Finished verdicts
    missing from the log are taken from the driver's last progress checkpoint (-ProgressVerdicts,
    "<id>=<VERDICT>;..."); their detail says so.
  - The running case is the last "CASE BEGIN" without a "CASE END", else the checkpoint's -ProgressCurrent.
  - When the run did not reach "RUN END":
      * the game crashed (-Crashed: a new crash dump, or the process exited by itself): the running case is CRASH;
      * the rig stopped it (-HostStop): host-timeout makes the running case TIMEOUT; stalled, low-ram,
        visible-window or stopped-on-pattern make it INCONCLUSIVE;
      * every plan case after it that has no verdict is INCONCLUSIVE, naming why it never ran.
  - Exit code: 1 when any case is FAIL (only FAIL says the product is wrong; it stays a FAIL even if the run broke
    off later), 0 when the run reached RUN END and every plan case is PASS, else 2.

.OUTPUTS
  [pscustomobject] Cases (ordered dictionaries: id, verdict, asserts, failed, seconds, detail, source), Running (the
  case id that was running when the run broke off, or $null), State ("complete", "crashed", a -HostStop value, or
  "incomplete"), Exit (0, 1 or 2).
#>
[CmdletBinding()]
param(
    [string[]] $Lines = @(),              # evidence lines without the "[vt2t:<nonce>] " tag
    [string[]] $PlanCaseIds = @(),        # the plan's case ids in plan order
    [bool] $RunEnd = $false,
    [bool] $Crashed = $false,
    [string] $CrashDetail = '',
    [ValidateSet('', 'host-timeout', 'stalled', 'low-ram', 'visible-window', 'stopped-on-pattern')] [string] $HostStop = '',
    [string] $HostStopDetail = '',
    [string] $ProgressCurrent = '',
    [string] $ProgressVerdicts = ''
)
$ErrorActionPreference = 'Stop'

$byId = [ordered]@{}
$begun = [System.Collections.Generic.List[string]]::new()
foreach ($l in $Lines) {
    if ($l -match '^CASE BEGIN id=(\S+)') { $begun.Add($Matches[1]) }
    elseif ($l -match '^CASE END id=(\S+) verdict=(\S+) asserts=(\d+) failed=(\d+) t=([\d\.]+)(?: detail="(.*)")?') {
        $byId[$Matches[1]] = [ordered]@{ id = $Matches[1]; verdict = $Matches[2]; asserts = [int]$Matches[3]; failed = [int]$Matches[4]; seconds = [double]$Matches[5]; detail = $Matches[6]; source = 'log' }
    }
}
foreach ($pair in @($ProgressVerdicts -split ';' | Where-Object { $_ })) {
    $id, $v = $pair -split '=', 2
    if ($id -and $v -and -not $byId.Contains($id)) {
        $byId[$id] = [ordered]@{ id = $id; verdict = $v; asserts = $null; failed = $null; seconds = $null; detail = 'from the last progress checkpoint; the log tail was lost'; source = 'progress' }
    }
}

$running = $null
for ($i = $begun.Count - 1; $i -ge 0; $i--) { if (-not $byId.Contains($begun[$i])) { $running = $begun[$i]; break } }
if (-not $running -and $ProgressCurrent -and -not $byId.Contains($ProgressCurrent)) { $running = $ProgressCurrent }

$state = if ($RunEnd) { 'complete' } elseif ($Crashed) { 'crashed' } elseif ($HostStop) { $HostStop } else { 'incomplete' }
$why = switch ($state) {
    'crashed' { 'the game crashed' + $(if ($CrashDetail) { " ($CrashDetail)" } else { '' }) }
    'host-timeout' { 'the host time limit ended the run' + $(if ($HostStopDetail) { " ($HostStopDetail)" } else { '' }) }
    'stalled' { 'the run stalled' + $(if ($HostStopDetail) { " ($HostStopDetail)" } else { '' }) }
    'low-ram' { 'free RAM fell below the floor' + $(if ($HostStopDetail) { " ($HostStopDetail)" } else { '' }) }
    'visible-window' { 'a game window reached the user desktop' }
    'stopped-on-pattern' { 'the run was stopped on a log pattern' }
    default { 'the run ended without RUN END' }
}

$ids = [System.Collections.Generic.List[string]]::new()
foreach ($id in $PlanCaseIds) { if ($id -and -not $ids.Contains($id)) { $ids.Add($id) } }
foreach ($id in $byId.Keys) { if (-not $ids.Contains($id)) { $ids.Add($id) } }
if ($running -and -not $ids.Contains($running)) { $ids.Add($running) }

$cases = @()
foreach ($id in $ids) {
    if ($byId.Contains($id)) { $cases += $byId[$id]; continue }
    $row = [ordered]@{ id = $id; verdict = 'INCONCLUSIVE'; asserts = $null; failed = $null; seconds = $null; detail = $null; source = 'rig' }
    if ($RunEnd) { $row.detail = 'the driver reported no verdict for this case' }
    elseif ($id -eq $running) {
        if ($state -eq 'crashed') { $row.verdict = 'CRASH'; $row.detail = "$why while this case ran" }
        elseif ($state -eq 'host-timeout') { $row.verdict = 'TIMEOUT'; $row.detail = "$why while this case ran" }
        else { $row.detail = "$why while this case ran" }
    }
    else { $row.detail = "not run: $why" + $(if ($running) { " during $running" } else { ' before this case' }) }
    $cases += $row
}

$verdicts = @($cases | ForEach-Object { $_.verdict })
$exit = 2
if ($verdicts -contains 'FAIL') { $exit = 1 }
elseif ($RunEnd -and $cases.Count -gt 0 -and @($verdicts | Where-Object { $_ -ne 'PASS' }).Count -eq 0) { $exit = 0 }

[pscustomobject]@{ Cases = $cases; Running = $running; State = $state; Exit = $exit }
