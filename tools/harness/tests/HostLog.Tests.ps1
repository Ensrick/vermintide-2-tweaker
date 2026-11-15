#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/Read-HostLog.ps1 (no game): the default host_forbid_log of the backend write
  shield and the shield-before-first-commit evidence, against made-up log lines in the game's formats.
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
$reader = Join-Path (Split-Path $PSScriptRoot) 'Read-HostLog.ps1'
$nonce = 'abcd1234'
$tab = "`t"
$shield = "00:00:08.500 [Lua] [vt2t:$nonce] SHIELD installed t=8.5 state=StateTitleScreen"
$commit = '00:01:02.000 [Lua] [Backend] _commit_internal "1"'
$saw = "00:01:02.100 [Lua] [vt2t:$nonce] SHIELD saw request=updateHeroAttributes keys=`"keep_decorations`" characters_key=`"characters_data`""
$heroRequest = "00:01:02.200 [Lua] [PlayFabRequestQueue] Enqueuing ExecuteCloudScript request${tab}updateHeroAttributes${tab}7"
$otherRequest = "00:01:02.300 [Lua] [PlayFabRequestQueue] Enqueuing ExecuteCloudScript request${tab}getQuests${tab}8"
$userData = '00:01:03.000 [Curl] POST https://example.playfabapi.com/Client/UpdateUserData'
$ownUserData = "00:01:03.100 [Lua] [vt2t:$nonce] NOTE id=x key=probe value=`"UpdateUserData`""

$clean = & $reader -Text (@($shield, $commit, $saw, $otherRequest, $ownUserData) -join "`r`n") -Nonce $nonce -ShieldOn
Assert-True (@($clean.ForbidHits).Count -eq 0) 'clean log: no forbidden line (driver lines and other requests are allowed)'
Assert-True ($clean.ShieldInstalledBeforeFirstCommit -eq $true) 'clean log: shield installed before the first commit'

$leak = & $reader -Text (@($commit, $shield, $heroRequest, $userData) -join "`n") -Nonce $nonce -ShieldOn
$rules = @($leak.ForbidHits | ForEach-Object { $_.rule })
Assert-True ($rules -contains 'shield: updateHeroAttributes request') 'leak: the game''s updateHeroAttributes request is forbidden'
Assert-True ($rules -contains 'shield: UpdateUserData request') 'leak: an UpdateUserData line is forbidden'
Assert-True (@($leak.ForbidHits | Where-Object { $_.line -eq $heroRequest }).Count -eq 1) 'leak: the hit names the whole log line'
Assert-True ($leak.ShieldInstalledBeforeFirstCommit -eq $false) 'leak: commit before the shield is reported as false'

$caseFold = & $reader -Text "[PlayFabRequestQueue] Enqueuing ExecuteCloudScript request${tab}updateheroattributes${tab}1" -Nonce $nonce -ShieldOn
Assert-True (@($caseFold.ForbidHits).Count -eq 0) 'matching is case-sensitive'

$off = & $reader -Text (@($heroRequest, $userData) -join "`n") -Nonce $nonce
Assert-True (@($off.ForbidHits).Count -eq 0) 'backend_shield false: the two defaults are dropped'
Assert-True ($null -eq $off.ShieldInstalledBeforeFirstCommit) 'no shield line: order unknown'

$noCommit = & $reader -Text $shield -Nonce $nonce -ShieldOn
Assert-True ($noCommit.ShieldInstalledBeforeFirstCommit -eq 'no commit in log') 'no commit in the log is reported as such'

$otherNonce = & $reader -Text ($shield -replace $nonce, 'ffffffff') -Nonce $nonce -ShieldOn
Assert-True ($null -eq $otherNonce.ShieldInstalledBeforeFirstCommit) 'a shield line of another run does not count'

# ---- WP-H-02: plan fields, the five default forbidden lines, allow entries, KEEP READY seconds, banners ----
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$plans = Join-Path (Split-Path (Split-Path $PSScriptRoot)) '..\qa\runtime\plans'
$smokePlan = Join-Path $plans 'smoke-keep.json'
$brokenPlan = Join-Path $plans 'smoke-broken-fixture.json'
$fixNonce = '5a5a5a5a'

$clean = & $reader -LogFile (Join-Path $fixtures 'smoke-clean.console.log') -PlanFile $smokePlan -Nonce $fixNonce
Assert-True (@($clean.ForbidHits).Count -eq 0 -and @($clean.ExpectMisses).Count -eq 0) "clean fixture: no forbidden or missing line ($(@($clean.ForbidHits | ForEach-Object { $_.line }) -join ' | '))"
Assert-True ($clean.KeepReadySeconds -eq 56.2) "clean fixture: KEEP READY 56.2 s after the first log line (got $($clean.KeepReadySeconds))"
Assert-True ($clean.KeepReadyDriverT -eq 33.6) "clean fixture: driver t on KEEP READY (got $($clean.KeepReadyDriverT))"
Assert-True ($clean.LoadedVersions['gt'] -eq '0.2.300-dev') "clean fixture: [gt:LOAD] banner version (got $($clean.LoadedVersions['gt']))"
Assert-True ($clean.ShieldInstalledBeforeFirstCommit -eq $true) 'clean fixture: plan without backend_shield keeps the shield order check'

$broken = & $reader -LogFile (Join-Path $fixtures 'smoke-broken.console.log') -PlanFile $brokenPlan -Nonce $fixNonce
$brokenHit = @($broken.ForbidHits | Where-Object { $_.rule -eq 'default: mod not found in the workshop folder' })
Assert-True ($brokenHit.Count -eq 1 -and $brokenHit[0].line -match 'with id 9000000099 was not found in the workshop folder') 'broken fixture: the missing mod line is forbidden and named'

$pwsh = (Get-Process -Id $PID).Path
$out = & $pwsh -NoProfile -File $reader -LogFile (Join-Path $fixtures 'smoke-broken.console.log') -PlanFile $brokenPlan -Nonce $fixNonce -ExitCode 2>&1
Assert-True ($LASTEXITCODE -eq 1) "broken fixture with -ExitCode: exit 1 (got $LASTEXITCODE)"
Assert-True (@($out | Where-Object { "$_" -match '^FORBIDDEN LOG LINE \(default: mod not found in the workshop folder\): .*9000000099' }).Count -eq 1) 'broken fixture with -ExitCode: the forbidden line is printed'
$null = & $pwsh -NoProfile -File $reader -LogFile (Join-Path $fixtures 'smoke-clean.console.log') -PlanFile $smokePlan -Nonce $fixNonce -ExitCode 2>&1
Assert-True ($LASTEXITCODE -eq 0) "clean fixture with -ExitCode: exit 0 (got $LASTEXITCODE)"

$defaultLines = [ordered]@{
    'default: <<Script Error>>'                     = '01:00:00.000 [Lua] <<Script Error>>scripts/x.lua:1: attempt to index nil<</Script Error>>'
    'default: Lua Stack'                            = '01:00:00.000 [Lua] <<Lua Stack>>'
    'default: mod not found in the workshop folder' = '01:00:00.000 [Lua] [ModManager][warning] Mod "x" with id 1 was not found in the workshop folder.'
    'default: Syntax error in .mod file'            = '01:00:00.000 [Lua] [ModManager][error] Syntax error in .mod file. Mod "x" with id 1 skipped.'
    'default: Failed to run callback'               = '01:00:00.000 [Lua] [ModManager][error] Failed to run callback "update" for mod "x" with id 1. Disabling callbacks until reload.'
}
foreach ($rule in $defaultLines.Keys) {
    $r = & $reader -Text $defaultLines[$rule] -Nonce $nonce -Defaults
    Assert-True (@($r.ForbidHits | Where-Object { $_.rule -eq $rule }).Count -eq 1) "default forbids: $rule"
    $own = & $reader -Text ("01:00:00.000 [Lua] [vt2t:$nonce] NOTE id=x key=k value=`"" + $defaultLines[$rule] + '"') -Nonce $nonce -Defaults
    Assert-True (@($own.ForbidHits).Count -eq 0) "default skips the driver's own lines: $rule"
}
$noDefaults = & $reader -Text $defaultLines['default: Lua Stack'] -Nonce $nonce
Assert-True (@($noDefaults.ForbidHits).Count -eq 0) 'without -Defaults or a plan (no-plan experiment) nothing is forbidden'

$allowed = & $reader -Text $defaultLines['default: Lua Stack'] -Nonce $nonce -Defaults -Allow @([pscustomobject]@{ pattern = '<<Lua Stack>>'; reason = 'fixture: proven benign' })
Assert-True (@($allowed.ForbidHits).Count -eq 0 -and @($allowed.Allowed).Count -eq 1 -and $allowed.Allowed[0].reason -eq 'fixture: proven benign') 'host_allow_log with a reason excuses the line and records the reason'
$noReason = & $reader -Text $defaultLines['default: Lua Stack'] -Nonce $nonce -Defaults -Allow @([pscustomobject]@{ pattern = '<<Lua Stack>>'; reason = '' })
Assert-True (@($noReason.ForbidHits).Count -eq 1 -and @($noReason.AllowErrors).Count -eq 1) 'host_allow_log without a reason is ignored and reported'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-hostlog-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $planFields = Join-Path $tmp 'plan.json'
    [System.IO.File]::WriteAllText($planFields, '{ "name": "t", "backend_shield": false, "backend_shield_reason": "test", "host_expect_log": ["\\[gt:LOAD\\] v", "never logged line"], "host_forbid_log": ["SHIELD saw request=getQuests"] }')
    $text = (Get-Content -LiteralPath (Join-Path $fixtures 'smoke-clean.console.log') -Raw) + "03:40:00.000 [Lua] [vt2t:$fixNonce] SHIELD saw request=getQuests case=-`n$heroRequest`n"
    $p = & $reader -Text $text -PlanFile $planFields -Nonce $fixNonce
    Assert-True (@($p.ExpectMisses).Count -eq 1 -and $p.ExpectMisses[0] -eq 'never logged line') 'host_expect_log: only the absent pattern is missing'
    Assert-True (@($p.ForbidHits | Where-Object { $_.rule -eq 'plan: SHIELD saw request=getQuests' }).Count -eq 1) 'host_forbid_log of the plan also reads the driver lines'
    Assert-True (@($p.ForbidHits | Where-Object { $_.rule -like 'shield:*' }).Count -eq 0) 'backend_shield false in the plan drops only the shield defaults'
}
finally { Remove-Item -LiteralPath $tmp -Recurse -Force }

# ---- WP-H-04: level loads ----
$loadText = @(
    "01:00:00.000 [Lua] [vt2t:$nonce] LOAD arena=mission:military level=military from=inn_level",
    "01:01:10.000 [Lua] [vt2t:$nonce] LEVEL READY level=military t=120.4 load_seconds=62.5",
    "01:02:00.000 [Lua] [vt2t:$nonce] LOAD FAILED arena=mission:nowhere err=`"x`"",
    "01:03:00.000 [Lua] [vt2t:$nonce] LEVEL READY level=inn_level t=230.0 load_seconds=48.1"
) -join "`n"
$loads = @((& $reader -Text $loadText -Nonce $nonce).LevelLoads)
Assert-True ($loads.Count -eq 3) "three level loads recorded (got $($loads.Count))"
Assert-True ($loads[0].level -eq 'military' -and $loads[0].seconds -eq 62.5) 'mission load seconds'
Assert-True ($loads[1].level -eq 'mission:nowhere' -and $loads[1].failed -eq 'FAILED') 'failed load recorded with its arena'
Assert-True ($loads[2].level -eq 'inn_level' -and $loads[2].seconds -eq 48.1) 'return-to-keep load seconds'

if ($failures.Count) { Write-Host "[HostLog.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[HostLog.Tests] OK -- forbidden and expected lines, allow entries, shield order, KEEP READY seconds and banners checked.'
exit 0
