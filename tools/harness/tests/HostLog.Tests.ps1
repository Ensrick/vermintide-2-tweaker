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

if ($failures.Count) { Write-Host "[HostLog.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[HostLog.Tests] OK -- forbidden-line defaults and shield order checks passed.'
exit 0
