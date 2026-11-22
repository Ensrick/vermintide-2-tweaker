#requires -Version 7
<#
.SYNOPSIS
  Offline tests of WP-H-11 (no game, no GitHub): Publish-Evidence.ps1 on a recorded run folder, New-RuntimeIndex.ps1,
  Invoke-NightlyRun.ps1's refusals and patch-day path, and the disabled nightly task definition.

.DESCRIPTION
  - Publish-Evidence.ps1 on tools/harness/tests/fixtures/evidence-run (a recorded run: summary.json, plan.json,
    evidence.txt) with a test index and quarantine list: the comment text for issue 80 equals
    fixtures/evidence-run/expected-80.md exactly; -Post -WhatIf lists the issue it would close and why each other stays
    open; -Post without -WhatIf is refused while the closure gate demands "user-confirmed" (a stand-in gate file, so
    gh is never reached).
  - New-RuntimeIndex.ps1: generates the index of the real qa/runtime into a temporary file; -Check passes on it and
    fails when an entry is missing; the committed qa/runtime/index.json is current.
  - Invoke-NightlyRun.ps1 with pretend idle time and processes (-IdleMinutesOverride, -ProcessOverride) and a fake
    Steam library: refuses an active owner, a listed game and any Steam game; -WhatIf on a patch day puts smoke plans
    first, notes the missing canary and lists evidence older than the current build. It never runs a plan here.
  - Register-NightlyTask.ps1 -OutFile: the filled XML parses, is disabled, starts pythonw (never a console), has no
    placeholder left. Nothing is registered.
  Exit codes: 0 pass, 2 failure.
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
$repo = (Resolve-Path -LiteralPath (Join-Path $harness '..\..')).Path
$fixture = Join-Path $PSScriptRoot 'fixtures\evidence-run'
$pwsh = (Get-Process -Id $PID).Path
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-evidence-tests-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    # ---------- Publish-Evidence.ps1 ----------
    $run = Join-Path $root 'run'
    Copy-Item -LiteralPath $fixture -Destination $run -Recurse
    Remove-Item -LiteralPath (Join-Path $run 'expected-80.md')
    $index = Join-Path $root 'index.json'
    Set-Content -LiteralPath $index -Value @'
{ "issues": {
  "80": [ { "script": "qa/runtime/cim/issue_80_cim_commit_callback.lua", "class": "R" }, { "script": "qa/runtime/cim/issue_80_cim_standard_bench_opens.lua", "class": "R" } ],
  "402": [ { "script": "qa/runtime/cim/issue_402_career_commit_scrub.lua", "class": "R" }, { "script": "qa/runtime/cwv/issue_402_career_commit_scrub.lua", "class": "R" } ],
  "430": [ { "script": "qa/runtime/event_tweaker/issue_430_join_lock.lua", "class": "R" } ],
  "1654": [ { "script": "qa/runtime/cim/issue_1654_store_backup.lua", "class": "R" }, { "script": "qa/runtime/cim/issue_1654_both_restored.lua", "class": "R" } ]
} }
'@
    $quarantine = Join-Path $root 'quarantine.txt'
    Set-Content -LiteralPath $quarantine -Value "# test`ncim-cases`tissue_430_join_lock`tPASS,FAIL`t2026-11-22"
    $gate = Join-Path $root 'gate.ps1'
    Set-Content -LiteralPath $gate -Value '$x = $commentBody -match ''(?im)^Verification:\s*user-confirmed\s*$'''
    $common = @{ Run = $run; RepoRoot = $repo; IndexFile = $index; QuarantineFile = $quarantine; CurrentBuild = '25901688'; GateFile = $gate; Quiet = $true }
    $rows = @(& (Join-Path $harness 'Publish-Evidence.ps1') @common)
    $r80 = @($rows | Where-Object { $_.issue -eq 80 })[0]
    $expected = [System.IO.File]::ReadAllText((Join-Path $fixture 'expected-80.md')) -replace "`r`n", "`n"
    $written = [System.IO.File]::ReadAllText((Join-Path $run 'evidence\80.md')) -replace "`r`n", "`n"
    Assert-True ($r80 -and $r80.close -and $r80.reasons.Count -eq 0) "issue 80: both listed scripts passed, would close ($($r80.reasons -join '; '))"
    Assert-True ($written.StartsWith($expected.TrimEnd("`n") + "`n")) "evidence\80.md starts with the exact comment text of expected-80.md:`n$written"
    Assert-True ($written -match '(?m)^Would close: yes$' -and $written -match 'commit source: harness checkout') 'evidence\80.md carries the facts block after the comment'
    $r402 = @($rows | Where-Object { $_.issue -eq 402 })[0]
    Assert-True ($r402 -and -not $r402.close -and ($r402.reasons -join ';') -match 'case issue_402_career_commit_scrub is INCONCLUSIVE' -and ($r402.reasons -join ';') -match 'listed script qa/runtime/cwv/issue_402_career_commit_scrub.lua did not run') "issue 402 stays open: an INCONCLUSIVE case and a listed script that did not run ($($r402.reasons -join '; '))"
    $r430 = @($rows | Where-Object { $_.issue -eq 430 })[0]
    Assert-True ($r430 -and -not $r430.close -and ($r430.reasons -join ';') -match 'quarantined') 'issue 430 stays open: its case is quarantined'
    $r1654 = @($rows | Where-Object { $_.issue -eq 1654 })[0]
    Assert-True ($r1654 -and -not $r1654.close -and ($r1654.reasons -join ';') -match 'issue_1654_both_restored.lua did not run') 'issue 1654 stays open: its second-boot script is not in this run'
    $old = @(& (Join-Path $harness 'Publish-Evidence.ps1') @common -CurrentBuild '99999999')
    Assert-True ((@($old | Where-Object { $_.issue -eq 80 })[0].reasons -join ';') -match 'older than the current game build \(run on 25901688, current 99999999\)') 'a run on an older game build never closes'
    $whatIf = & $pwsh -NoProfile -Command "& '$(Join-Path $harness 'Publish-Evidence.ps1')' -Run '$run' -RepoRoot '$repo' -IndexFile '$index' -QuarantineFile '$quarantine' -CurrentBuild 25901688 -GateFile '$gate' -Post -WhatIf | Out-Null" 2>&1
    $wtext = $whatIf -join "`n"
    Assert-True ($wtext -match '(?m)^would close #80: every listed script passed' -and $wtext -match '(?m)^#402 stays open: ' -and $wtext -match '(?m)^#430 stays open: case issue_430_join_lock is quarantined' -and $wtext -match '(?m)^would comment on #1654') "-Post -WhatIf lists what it would close and why the others stay open:`n$wtext"
    $posted = & $pwsh -NoProfile -Command "& '$(Join-Path $harness 'Publish-Evidence.ps1')' -Run '$run' -RepoRoot '$repo' -IndexFile '$index' -QuarantineFile '$quarantine' -CurrentBuild 25901688 -GateFile '$gate' -Post | Out-Null; exit `$LASTEXITCODE" 2>&1
    Assert-True ($LASTEXITCODE -eq 3 -and ($posted -join ' ') -match 'PUBLISH REFUSED: the pull-request gate still demands') "-Post is refused while the gate demands user-confirmed (WP-G-01): $($posted -join ' ')"

    # ---------- New-RuntimeIndex.ps1 ----------
    $tmpIndex = Join-Path $root 'gen-index.json'
    $null = & (Join-Path $harness 'New-RuntimeIndex.ps1') -RepoRoot $repo -OutFile $tmpIndex -Quiet
    $gen = [System.IO.File]::ReadAllText($tmpIndex) | ConvertFrom-Json
    Assert-True ($gen.issues.PSObject.Properties['402'] -and @($gen.issues.'402').Count -ge 4 -and @($gen.issues.'80').Count -ge 2) "the generated index groups scripts by issue (402: $(@($gen.issues.'402').Count) scripts)"
    Assert-True (-not $gen.issues.PSObject.Properties['0']) 'scripts with issue 0 are not listed'
    & $pwsh -NoProfile -File (Join-Path $harness 'New-RuntimeIndex.ps1') -RepoRoot $repo -OutFile $tmpIndex -Check -Quiet
    Assert-True ($LASTEXITCODE -eq 0) '-Check passes on a current index'
    $dropped = [System.IO.File]::ReadAllText($tmpIndex) -replace '(?s)"80": \[.*?\],\s*', ''
    [System.IO.File]::WriteAllText($tmpIndex, $dropped)
    & $pwsh -NoProfile -File (Join-Path $harness 'New-RuntimeIndex.ps1') -RepoRoot $repo -OutFile $tmpIndex -Check -Quiet
    Assert-True ($LASTEXITCODE -eq 1) '-Check fails when an issue-closing script has no entry'
    & $pwsh -NoProfile -File (Join-Path $harness 'New-RuntimeIndex.ps1') -RepoRoot $repo -Check -Quiet
    Assert-True ($LASTEXITCODE -eq 0) 'the committed qa/runtime/index.json is current'

    # ---------- Invoke-NightlyRun.ps1 (never runs a plan here) ----------
    $steam = Join-Path $root 'steamapps'
    New-Item -ItemType Directory -Force -Path (Join-Path $steam 'common\Some Game') | Out-Null
    Set-Content -LiteralPath (Join-Path $steam 'appmanifest_552500.acf') -Value "`"AppState`"`n{`n`t`"buildid`"`t`t`"26000001`"`n}"
    $rig = Join-Path $root 'rig'
    function Invoke-Nightly([double] $idle, [string[]] $procs, [switch] $WhatIfRun) {
        $a = @{ RigRoot = $rig; SteamApps = $steam; IdleMinutesOverride = $idle; ProcessOverride = $procs; ReportDir = (Join-Path $root 'reports'); RunScript = (Join-Path $root 'no-such-run.ps1') }
        if ($WhatIfRun) { $a.WhatIf = $true }
        $out = & (Join-Path $harness 'Invoke-NightlyRun.ps1') @a 6>&1 2>&1
        [pscustomobject]@{ Text = ($out -join "`n"); Code = $LASTEXITCODE }
    }
    $active = Invoke-Nightly 5 @()
    Assert-True ($active.Text -match 'nightly refused: the owner is active \(last input 5 min ago, need 30\)' -and -not (Test-Path -LiteralPath (Join-Path $root 'reports'))) "an active owner refuses the night, no report: $($active.Text)"
    $listed = Invoke-Nightly 60 @('SkyrimSE|C:\Games\SkyrimSE.exe')
    Assert-True ($listed.Text -match 'nightly refused: a busy process runs \(SkyrimSE; busy-processes.txt\)') "a listed game refuses: $($listed.Text)"
    $game = Invoke-Nightly 60 @("Spider-Man3|$(Join-Path $steam 'common\Some Game\Spider-Man3.exe')")
    Assert-True ($game.Text -match 'nightly refused: a Steam game runs \(Spider-Man3\)') "any process from steamapps\common refuses: $($game.Text)"
    Assert-True ((Get-Content -LiteralPath (Join-Path $rig 'nightly.log')).Count -eq 3) 'every refusal is one line in nightly.log'
    New-Item -ItemType Directory -Force -Path (Join-Path $rig 'runs\20261120-000000-cim-cases-0000abcd\evidence') | Out-Null
    Set-Content -LiteralPath (Join-Path $rig 'runs\20261120-000000-cim-cases-0000abcd\evidence\80.md') -Value "Verification: x`nAssertions: 3 passed, 0 failed. Game build 25901688.`n"
    Set-Content -LiteralPath (Join-Path $rig 'nightly-state.json') -Value '{ "last_build": "25901688" }'
    $patch = Invoke-Nightly 60 @() -WhatIfRun
    $t = $patch.Text
    Assert-True ($t -match 'Game build: 26000001 \(last nightly: 25901688\) - patch day') "patch day is detected from the build id: $t"
    Assert-True ($t -match 'qa/check_patch_day.ps1 is not in this checkout yet \(WP-T-04\)|Canary: would run') 'patch day: the canary is run first, or its absence is said'
    Assert-True ($t -match 'Evidence older than the current game build \(1\):' -and $t -match 'cim-cases-0000abcd\\evidence\\80.md \(game build 25901688\)') 'patch day: stored evidence of the old build is listed'
    $iSmoke = $t.IndexOf('| smoke-public.json'); $iSweep = $t.IndexOf('| sweep-public.json')
    Assert-True ($iSmoke -ge 0 -and $iSweep -gt $iSmoke) 'patch day: smoke plans before the sweeps'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'reports'))) '-WhatIf writes no report and runs no plan'

    # ---------- Register-NightlyTask.ps1 -OutFile (registers nothing) ----------
    $fakePythonW = Join-Path $root 'pythonw.exe'
    Set-Content -LiteralPath $fakePythonW -Value ''
    $taskXml = Join-Path $root 'task.xml'
    $null = & (Join-Path $harness 'nightly\Register-NightlyTask.ps1') -RigRoot $rig -PythonW $fakePythonW -OutFile $taskXml 6>$null
    [xml]$x = [System.IO.File]::ReadAllText($taskXml)
    $ns = [System.Xml.XmlNamespaceManager]::new($x.NameTable); $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
    Assert-True ($x.SelectSingleNode('/t:Task/t:Settings/t:Enabled', $ns).InnerText -eq 'false') 'the task definition is disabled'
    $command = $x.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Command', $ns).InnerText
    $arguments = $x.SelectSingleNode('/t:Task/t:Actions/t:Exec/t:Arguments', $ns).InnerText
    Assert-True ($command -eq $fakePythonW -and $arguments -match 'nightly_launch\.pyw' -and $command -notmatch 'pwsh|powershell|cmd') "the task starts pythonw with the windowless launcher ($command $arguments)"
    Assert-True ($x.SelectSingleNode('/t:Task/t:Principals/t:Principal/t:LogonType', $ns).InnerText -eq 'InteractiveToken' -and [System.IO.File]::ReadAllText($taskXml) -notmatch '\{\{') 'runs only while the owner is logged on; no placeholder left'
}
finally { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } }

if ($failures.Count) { Write-Host "[Evidence.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[Evidence.Tests] OK -- evidence comment, closing rules, -Post refusal, runtime index, nightly refusals and patch day, disabled task definition checked.'
exit 0
