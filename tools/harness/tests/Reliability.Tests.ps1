#requires -Version 7
<#
.SYNOPSIS
  Offline tests of the rig's reliability layer (WP-H-09), with no game.

.DESCRIPTION
  - Get-RunVerdicts.ps1 on canned console logs, through the same evidence-line extraction run.ps1 uses: every
    verdict kind (PASS, FAIL, ERROR, TIMEOUT, INCONCLUSIVE, CRASH), a crash that cut the log short (verdicts from the
    progress checkpoint), host stops (stalled, low RAM, host time limit) and the exit codes.
  - Remove-OldRuns.ps1 on a temporary runs folder: the newest N and the report-named folders stay, a folder holding a
    junction is skipped and its target untouched, other folders are never touched, -WhatIf removes nothing.
  - Repeat-Plan.ps1 and Invoke-OrderCheck.ps1 with a stand-in for run.ps1 (never the game).
  - run.ps1's lock queue and busy-process refusal on a private lock name and a fake Steam library. Every one of
    these runs is refused before launch (a free-RAM floor no machine meets, no bootstrap in the fake library and a
    zero-byte exe), so nothing can start.
  Exit codes: 0 pass, 2 failure. The temporary folder is removed at the end.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
$harness = Split-Path $PSScriptRoot
$verdicts = Join-Path $harness 'Get-RunVerdicts.ps1'
$pwsh = (Get-Process -Id $PID).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-reliability-tests-' + [guid]::NewGuid().ToString('N'))

# ---------- canned logs ----------
$nonce = 'c0ffee01'
function Get-Lines([string] $log) { @([regex]::Matches(($log -replace "`r`n", "`n"), '(?m)^.*\[vt2t:' + $nonce + '\] (.*)$') | ForEach-Object { $_.Groups[1].Value.TrimEnd() }) }
function New-Log([string[]] $evidence) {
    $out = @('00:00:01.000 [Lua] [Application] engine noise', "00:00:02.000 [Lua] [vt2t:0badf00d] CASE END id=a verdict=FAIL asserts=1 failed=1 t=0.1 detail=`"another run's line`"")
    $i = 3
    foreach ($e in $evidence) { $out += ('00:00:{0:00}.000 [Lua] [vt2t:{1}] {2}' -f $i, $nonce, $e); $out += ('00:00:{0:00}.500 [Lua] [Mod] noise between lines' -f $i); $i++ }
    $out -join "`n"
}
function Invoke-Verdicts([string[]] $evidence, [string[]] $ids, [hashtable] $more = @{}) {
    $a = @{ Lines = [string[]](Get-Lines (New-Log $evidence)); PlanCaseIds = $ids } + $more
    & $verdicts @a
}
function V($r, [string] $id) { @($r.Cases | Where-Object { $_.id -eq $id })[0] }
$begin = 'RUN BEGIN driver=0.4.11 plan="canned" cases=3 arenas="keep" realm=modded'
$end = 'RUN END reason="plan complete" cases=3'

$r = Invoke-Verdicts @($begin, 'CASE BEGIN id=a', 'CASE END id=a verdict=PASS asserts=2 failed=0 t=0.4', $end) @('a') @{ RunEnd = $true }
Assert-True ($r.Exit -eq 0 -and (V $r 'a').verdict -eq 'PASS' -and $r.State -eq 'complete' -and $r.Cases.Count -eq 1) 'PASS: one passing case, RUN END, exit 0; the other nonce''s line is ignored'

$r = Invoke-Verdicts @($begin, 'CASE END id=a verdict=PASS asserts=1 failed=0 t=0.1', 'CASE END id=b verdict=FAIL asserts=2 failed=1 t=0.2 detail="planted failure"', 'CASE END id=c verdict=PASS asserts=1 failed=0 t=0.1', $end) @('a', 'b', 'c') @{ RunEnd = $true }
Assert-True ($r.Exit -eq 1 -and (V $r 'b').verdict -eq 'FAIL' -and (V $r 'b').detail -eq 'planted failure' -and (V $r 'b').failed -eq 1) 'FAIL: the failed case and its detail, exit 1'

$r = Invoke-Verdicts @($begin, 'CASE END id=a verdict=ERROR asserts=0 failed=0 t=0.0 detail="case:a:3: boom"', $end) @('a') @{ RunEnd = $true }
Assert-True ($r.Exit -eq 2 -and (V $r 'a').verdict -eq 'ERROR') 'ERROR: a script error is exit 2, not a FAIL'

$r = Invoke-Verdicts @($begin, 'CASE END id=a verdict=TIMEOUT asserts=1 failed=0 t=30.0 detail="exceeded 30 s"', $end) @('a') @{ RunEnd = $true }
Assert-True ($r.Exit -eq 2 -and (V $r 'a').verdict -eq 'TIMEOUT') 'TIMEOUT: the driver''s case timeout is exit 2'

$r = Invoke-Verdicts @($begin, 'CASE END id=a verdict=INCONCLUSIVE asserts=0 failed=0 t=0.1 detail="local hero alive"', $end) @('a', 'b') @{ RunEnd = $true }
Assert-True ($r.Exit -eq 2 -and (V $r 'a').verdict -eq 'INCONCLUSIVE' -and (V $r 'b').verdict -eq 'INCONCLUSIVE' -and (V $r 'b').detail -match 'no verdict') 'INCONCLUSIVE: a precondition, and a plan case the driver never reported, are exit 2'

$r = Invoke-Verdicts @($begin, 'CASE END id=a verdict=PASS asserts=1 failed=0 t=0.1', 'CASE BEGIN id=b issue=0 arena=keep level=inn_level') @('a', 'b', 'c') @{ Crashed = $true; CrashDetail = 'crash dump crash_dump-1.dmp' }
Assert-True ($r.Exit -eq 2 -and $r.State -eq 'crashed' -and $r.Running -eq 'b' -and (V $r 'a').verdict -eq 'PASS' -and (V $r 'b').verdict -eq 'CRASH' -and (V $r 'b').detail -match 'crash_dump-1\.dmp' -and (V $r 'c').verdict -eq 'INCONCLUSIVE' -and (V $r 'c').detail -match 'not run: the game crashed .* during b') 'CRASH: the running case is CRASH, the later ones INCONCLUSIVE naming it, finished ones keep their verdict'

$r = Invoke-Verdicts @($begin, 'CASE BEGIN id=a issue=0 arena=keep level=inn_level') @('a', 'b', 'c', 'd') @{ Crashed = $true; ProgressCurrent = 'c'; ProgressVerdicts = 'a=PASS;b=FAIL' }
Assert-True ((V $r 'a').verdict -eq 'PASS' -and (V $r 'a').source -eq 'progress' -and (V $r 'b').verdict -eq 'FAIL' -and (V $r 'c').verdict -eq 'CRASH' -and (V $r 'd').verdict -eq 'INCONCLUSIVE' -and $r.Exit -eq 1) 'a crash that cut the log: finished verdicts come from the progress checkpoint, its running case is CRASH, the FAIL still counts (exit 1)'

$r = Invoke-Verdicts @($begin) @('a', 'b') @{ Crashed = $true; CrashDetail = 'process EXITED code=1 without RUN END' }
Assert-True ($null -eq $r.Running -and (V $r 'a').verdict -eq 'INCONCLUSIVE' -and (V $r 'a').detail -match 'before this case' -and (V $r 'b').verdict -eq 'INCONCLUSIVE') 'a crash before any case: every case INCONCLUSIVE, none CRASH'

$r = Invoke-Verdicts @($begin, 'CASE BEGIN id=a issue=0 arena=keep level=inn_level') @('a', 'b') @{ HostStop = 'stalled'; HostStopDetail = 'no progress checkpoint for 61 s in phase RUN, limit 60 s' }
Assert-True ($r.State -eq 'stalled' -and (V $r 'a').verdict -eq 'INCONCLUSIVE' -and (V $r 'a').detail -match 'stalled .*61 s' -and (V $r 'b').detail -match 'not run: the run stalled' -and $r.Exit -eq 2) 'stalled: the running case and the rest INCONCLUSIVE, exit 2'

$r = Invoke-Verdicts @($begin, 'CASE BEGIN id=a issue=0 arena=keep level=inn_level') @('a') @{ HostStop = 'low-ram'; HostStopDetail = '2.5 GiB free, floor 3 GiB' }
Assert-True ($r.State -eq 'low-ram' -and (V $r 'a').verdict -eq 'INCONCLUSIVE' -and (V $r 'a').detail -match 'free RAM') 'low RAM: INCONCLUSIVE'

$r = Invoke-Verdicts @($begin, 'CASE BEGIN id=a issue=0 arena=keep level=inn_level') @('a', 'b') @{ HostStop = 'host-timeout'; HostStopDetail = '540 s' }
Assert-True ((V $r 'a').verdict -eq 'TIMEOUT' -and (V $r 'a').detail -match 'host time limit' -and (V $r 'b').verdict -eq 'INCONCLUSIVE') 'host time limit: the running case is TIMEOUT, the rest INCONCLUSIVE'

$r = Invoke-Verdicts @($begin, 'CASE END id=a verdict=PASS asserts=1 failed=0 t=0.1') @('a') @{ HostStop = 'stalled' }
Assert-True ($r.Exit -eq 2 -and (V $r 'a').verdict -eq 'PASS') 'every case PASS but no RUN END is still exit 2'

$kinds = @('PASS', 'FAIL', 'ERROR', 'TIMEOUT', 'INCONCLUSIVE', 'CRASH')
Assert-True ($true) "verdict kinds covered: $($kinds -join ', ')"

try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    # ---------- Remove-OldRuns.ps1 ----------
    $runs = Join-Path $root 'rig\runs'
    New-Item -ItemType Directory -Force -Path $runs | Out-Null
    $names = @()
    for ($i = 1; $i -le 8; $i++) { $n = ('2026111{0}-0{0}0000-smoke-keep-{1:x8}' -f ($i % 10), (0xabc000 + $i)); $names += $n; New-Item -ItemType Directory -Force -Path (Join-Path $runs $n) | Out-Null; Set-Content -LiteralPath (Join-Path $runs "$n\summary.json") -Value '{}' }
    $sorted = @($names | Sort-Object -Descending)
    $oldest = $sorted[-1]; $secondOldest = $sorted[-2]; $linked = $sorted[-3]
    $reports = Join-Path $root 'reports'
    New-Item -ItemType Directory -Force -Path $reports | Out-Null
    Set-Content -LiteralPath (Join-Path $reports 'report.md') -Value "evidence: runs/$secondOldest/summary.json"
    $target = Join-Path $root 'precious'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Set-Content -LiteralPath (Join-Path $target 'keep.txt') -Value 'must survive'
    New-Item -ItemType Junction -Path (Join-Path $runs "$linked\link") -Target $target | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $runs 'not-a-run'), (Join-Path $runs 'profile') | Out-Null
    $dry = & (Join-Path $harness 'Remove-OldRuns.ps1') -RunsDir $runs -Keep 4 -ReportsDir $reports -WhatIf -Quiet
    Assert-True (@(Get-ChildItem -LiteralPath $runs -Directory).Count -eq 10 -and $dry.Removed.Count -eq 2) "retention -WhatIf lists what it would remove and removes nothing (would remove $($dry.Removed -join ', '))"
    $ret = & (Join-Path $harness 'Remove-OldRuns.ps1') -RunsDir $runs -Keep 4 -ReportsDir $reports -Protect (Join-Path $runs $sorted[4]) -Quiet
    $left = @(Get-ChildItem -LiteralPath $runs -Directory | ForEach-Object Name)
    Assert-True ((@($sorted[0..3] | Where-Object { $left -notcontains $_ })).Count -eq 0) 'retention keeps the newest N'
    Assert-True ($left -contains $sorted[4]) 'retention keeps a -Protect folder'
    Assert-True ($left -contains $secondOldest -and $ret.Referenced -contains $secondOldest) 'retention keeps a folder a report names'
    Assert-True ($left -contains $linked -and $ret.Skipped -contains $linked -and (Test-Path -LiteralPath (Join-Path $target 'keep.txt'))) 'retention skips a folder holding a junction; the junction target is untouched'
    Assert-True ($left -notcontains $oldest -and $ret.Removed -contains $oldest) 'retention removes an old, unnamed run folder'
    Assert-True ($left -contains 'not-a-run' -and $left -contains 'profile') 'retention never touches a folder that is not a run'
    Remove-Item -LiteralPath (Join-Path $runs "$linked\link") -Force

    # ---------- a stand-in for run.ps1 (never the game) ----------
    $fake = Join-Path $root 'fake-run.ps1'
    Set-Content -LiteralPath $fake -Value @'
param([string] $Plan, [string] $RunDir, [string] $RigRoot, [switch] $NoOrderCheck, [double] $Wait, [string] $Renderer)
$p = [System.IO.File]::ReadAllText($Plan) | ConvertFrom-Json
$counter = Join-Path $RigRoot 'count.txt'
$n = 1 + [int]((Get-Content -LiteralPath $counter -ErrorAction SilentlyContinue) ?? 0)
Set-Content -LiteralPath $counter -Value $n
Add-Content -LiteralPath (Join-Path $RigRoot 'calls.txt') -Value "run $n noorder=$([bool]$NoOrderCheck) wait=$Wait renderer=$Renderer cases=$(@($p.cases).Count) arenas=$([bool]$p.PSObject.Properties['arenas']) name=$($p.name) file=$($p.cases[0].file) resolves=$(Test-Path -LiteralPath (Join-Path $RunDir $p.cases[0].file))"
$flaky = @($p.flaky_runs) -contains $n
$cases = @($p.cases | ForEach-Object { [ordered]@{ id = $_.id; verdict = $(if ($_.id -eq 'b' -and ($flaky -or $p.b_fails)) { 'FAIL' } else { 'PASS' }); detail = '' } })
$iso = if (@($p.broken_runs) -contains $n) { 'BROKEN' } else { 'OK' }
[ordered]@{ isolation = $iso; cases = $cases } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RunDir 'summary.json')
exit $(if (@($cases | Where-Object { $_.verdict -eq 'FAIL' }).Count) { 1 } else { 0 })
'@
    $planDir = Join-Path $root 'plans'
    New-Item -ItemType Directory -Force -Path (Join-Path $planDir 'cases') | Out-Null
    Set-Content -LiteralPath (Join-Path $planDir 'cases\b.lua') -Value 'return {}'

    # ---------- Repeat-Plan.ps1 ----------
    function Invoke-Repeat([string] $planJson, [int] $count) {
        $rig = Join-Path $root ('rig-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $rig | Out-Null
        $pf = Join-Path $planDir ('repeat-' + [guid]::NewGuid().ToString('N') + '.json')
        Set-Content -LiteralPath $pf -Value $planJson
        $q = Join-Path $rig 'quarantine.txt'
        Set-Content -LiteralPath $q -Value '# header'
        $null = & $pwsh -NoProfile -Command "& '$(Join-Path $harness 'Repeat-Plan.ps1')' -Plan '$pf' -Count $count -RunScript '$fake' -RigRoot '$rig' -QuarantineFile '$q' -Wait 5 -ChildArgs @{ Renderer = 'dx11' }; exit `$LASTEXITCODE"
        $code = $LASTEXITCODE
        $rep = Get-ChildItem -LiteralPath (Join-Path $rig 'repeats') -Directory | Select-Object -First 1 | ForEach-Object { Get-Content -LiteralPath (Join-Path $_.FullName 'repeat.json') -Raw | ConvertFrom-Json }
        [pscustomobject]@{ Exit = $code; Repeat = $rep; Calls = @(Get-Content -LiteralPath (Join-Path $rig 'calls.txt')); Quarantine = @(Get-Content -LiteralPath $q) }
    }
    $same = Invoke-Repeat '{ "name": "steady", "cases": [ { "id": "a", "file": "cases/b.lua" }, { "id": "b", "file": "cases/b.lua" } ] }' 3
    Assert-True ($same.Exit -eq 0 -and $same.Repeat.identical -and $same.Repeat.isolation_ok_every_run -and $same.Calls.Count -eq 3) "repeat: three identical tables, isolation OK, exit 0 (exit $($same.Exit))"
    Assert-True (@($same.Calls | Where-Object { $_ -notmatch 'noorder=True wait=5 renderer=dx11' }).Count -eq 0) 'repeat: every run gets -NoOrderCheck, -Wait and the child arguments'
    Assert-True ($same.Quarantine.Count -eq 1) 'repeat: nothing quarantined when the tables agree'
    $flaky = Invoke-Repeat '{ "name": "flaky", "flaky_runs": [2], "cases": [ { "id": "a", "file": "cases/b.lua" }, { "id": "b", "file": "cases/b.lua" } ] }' 3
    Assert-True ($flaky.Exit -eq 1 -and -not $flaky.Repeat.identical -and @($flaky.Repeat.differing).Count -eq 1 -and $flaky.Repeat.differing[0].id -eq 'b' -and $flaky.Repeat.differing[0].verdicts -eq 'PASS,FAIL,PASS') "repeat: a case that differs is named with each run's verdict (exit $($flaky.Exit))"
    Assert-True ($flaky.Quarantine.Count -eq 2 -and $flaky.Quarantine[1] -match "^flaky`tb`tPASS,FAIL,PASS`t\d{4}-\d\d-\d\d$") "repeat: the differing case is appended to the quarantine file ($($flaky.Quarantine[-1]))"
    $broken = Invoke-Repeat '{ "name": "iso", "broken_runs": [2], "cases": [ { "id": "a", "file": "cases/b.lua" } ] }' 2
    Assert-True ($broken.Exit -eq 1 -and -not $broken.Repeat.isolation_ok_every_run) 'repeat: one run with broken isolation fails the repeat'
    $bootsPlan = Join-Path $planDir 'boots.json'
    Set-Content -LiteralPath $bootsPlan -Value '{ "name": "b", "boots": [ { "cases": [] } ] }'
    $null = & $pwsh -NoProfile -Command "& '$(Join-Path $harness 'Repeat-Plan.ps1')' -Plan '$bootsPlan' -Count 2 -RunScript '$fake' -RigRoot '$(Join-Path $root 'rig-boots')'; exit `$LASTEXITCODE"
    Assert-True ($LASTEXITCODE -eq 3) 'repeat: a plan with boots is refused (exit 3)'

    # ---------- Invoke-OrderCheck.ps1 ----------
    $rigO = Join-Path $root 'rig-order'
    $runO = Join-Path $rigO 'runs\20261122-000000-order-deadbeef'
    New-Item -ItemType Directory -Force -Path $runO | Out-Null
    $orderPlan = Join-Path $planDir 'order.json'
    Set-Content -LiteralPath $orderPlan -Value '{ "name": "order", "arenas": ["keep", "mission:military"], "modset": "x", "options": { "VMF": { "a": 1 } }, "cases": [ { "id": "a", "arena": "keep", "file": "cases/b.lua" }, { "id": "b", "arena": "mission:military", "file": "cases/b.lua" } ] }'
    $rows = @(& (Join-Path $harness 'Invoke-OrderCheck.ps1') -PlanPath $orderPlan -RunDir $runO -CaseIds @('b', 'zz') -RigRoot $rigO -RunScript $fake -ChildArgs @{ Renderer = 'dx11' })
    $callsO = @(Get-Content -LiteralPath (Join-Path $rigO 'calls.txt'))
    Assert-True ($rows.Count -eq 2 -and $rows[0].id -eq 'b' -and $rows[0].alone_verdict -eq 'PASS' -and $rows[0].order_dependent -and $rows[0].folder -eq 'alone-b') 'order check: a FAIL that passes alone is order-dependent'
    Assert-True ($callsO.Count -eq 1 -and $callsO[0] -match 'noorder=True .*renderer=dx11 cases=1 arenas=False name=order-alone file=\S+b\.lua resolves=True') "order check: one re-run with only that case, no arenas, the case file relative to its folder, -NoOrderCheck ($($callsO[0]))"
    $alone = Get-Content -LiteralPath (Join-Path $runO 'alone-b\alone-plan.json') -Raw | ConvertFrom-Json
    Assert-True ($alone.modset -eq 'x' -and $alone.options.VMF.a -eq 1 -and $alone.cases[0].arena -eq 'mission:military') 'order check: the re-run keeps the plan''s mod set, options and the case''s arena'
    Assert-True ($null -eq $rows[1].alone_verdict -and -not $rows[1].order_dependent -and $callsO.Count -eq 1) 'order check: an id the plan does not have is not run'
    Set-Content -LiteralPath $orderPlan -Value '{ "name": "order2", "b_fails": true, "cases": [ { "id": "a", "file": "cases/b.lua" }, { "id": "b", "file": "cases/b.lua" } ] }'
    $rows2 = @(& (Join-Path $harness 'Invoke-OrderCheck.ps1') -PlanPath $orderPlan -RunDir $runO -CaseIds @('b') -RigRoot $rigO -RunScript $fake)
    Assert-True ($rows2[0].alone_verdict -eq 'FAIL' -and -not $rows2[0].order_dependent) 'order check: a FAIL that also fails alone is not order-dependent'

    # ---------- run.ps1: lock queue and busy processes (refused before launch every time) ----------
    $steam = Join-Path $root 'steamapps'
    New-Item -ItemType Directory -Force -Path (Join-Path $steam 'common\Warhammer Vermintide 2\binaries_dx12'), (Join-Path $steam 'workshop\content\552500') | Out-Null
    Set-Content -LiteralPath (Join-Path $steam 'appmanifest_552500.acf') -Value "`"AppState`"`n{`n`t`"StateFlags`"`t`t`"4`"`n}"
    Set-Content -LiteralPath (Join-Path $steam 'common\Warhammer Vermintide 2\binaries_dx12\vermintide2_dx12.exe') -Value ''
    $runPlan = Join-Path $planDir 'queue.json'
    Set-Content -LiteralPath $runPlan -Value '{ "name": "queue-test", "mods": ["1369573612"], "cases": [ { "id": "a", "arena": "keep", "file": "cases/b.lua" } ] }'
    $lockName = 'Local\Vt2RigQueueTest-' + [guid]::NewGuid().ToString('N')
    $idle = Join-Path $root 'busy-none.txt'
    Set-Content -LiteralPath $idle -Value '# nothing busy'
    $runPs1 = Join-Path $harness 'run.ps1'
    function Invoke-Run([double] $wait, [string] $busyFile) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $out = & $pwsh -NoProfile -File $runPs1 -Plan $runPlan -SteamApps $steam -RigRoot (Join-Path $root 'rig-run') -LockName $lockName -Wait $wait -BusyProcessesFile $busyFile -MinFreeGiB 100000 2>&1
        [pscustomobject]@{ Exit = $LASTEXITCODE; Text = ($out -join ' '); Seconds = $sw.Elapsed.TotalSeconds }
    }
    $holder = Start-Process -FilePath $pwsh -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-Command', "`$m = [System.Threading.Mutex]::new(`$false, '$lockName'); [void]`$m.WaitOne(); Set-Content -LiteralPath '$(Join-Path $root 'held.txt')' -Value held; Start-Sleep -Seconds 60")
    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath (Join-Path $root 'held.txt')) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    $now = Invoke-Run 0 $idle
    Assert-True ($now.Exit -eq 3 -and $now.Text -match 'RIG REFUSED: another rig run holds the lock\.' -and $now.Text -notmatch 'waited') "queue: -Wait 0 refuses at once while the lock is held ($($now.Text))"
    $waited = Invoke-Run 0.05 $idle
    Assert-True ($waited.Exit -eq 3 -and $waited.Text -match 'waiting up to 0\.05 min' -and $waited.Text -match 'holds the lock \(waited 0\.05 min\)' -and $waited.Seconds -ge 2.5) "queue: -Wait 0.05 waits about 3 s, then refuses ($([math]::Round($waited.Seconds, 1)) s: $($waited.Text))"
    Stop-Process -Id $holder.Id -Force; $holder.WaitForExit()
    $free = Invoke-Run 0.5 $idle
    Assert-True ($free.Exit -eq 3 -and $free.Text -match 'RIG REFUSED: (Free RAM below 100000 GiB|A Vermintide process is already running|Steam is not running)' -and $free.Text -notmatch 'holds the lock') "queue: once the holder is gone the lock is taken (an abandoned lock counts) and the checks under it run ($($free.Text))"
    $busyFile = Join-Path $root 'busy-pwsh.txt'
    Set-Content -LiteralPath $busyFile -Value "# the test's own shell counts as busy`npwsh.exe"
    $busy = Invoke-Run 0 $busyFile
    Assert-True ($busy.Exit -eq 3 -and $busy.Text -match 'RIG REFUSED: (A busy process is running \(pwsh pid \d+|A Vermintide process is already running)') "busy-processes.txt: a listed process refuses the start ($($busy.Text))"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'rig-run\profile'))) 'run.ps1 never built a profile in these refused runs'
    $listed = @([System.IO.File]::ReadAllLines((Join-Path $harness 'busy-processes.txt')) | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ })
    Assert-True ($listed -contains 'vermintide2_dx12' -and $listed.Count -ge 3) "the committed busy-processes.txt lists the game ($($listed.Count) names)"
}
finally {
    if (Test-Path -LiteralPath $root) {
        Get-ChildItem -LiteralPath $root -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

if ($failures.Count) { Write-Host "[Reliability.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[Reliability.Tests] OK -- verdict kinds from canned logs, retention, repeat, order check, lock queue and busy processes checked.'
exit 0
