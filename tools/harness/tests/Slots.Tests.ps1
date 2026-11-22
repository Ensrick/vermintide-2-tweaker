#requires -Version 7
<#
.SYNOPSIS
  Offline test of the rig slots (WP-H-07), no game and no real Workshop folder: everything runs against a fake
  steamapps folder in a test-owned temporary directory.

.DESCRIPTION
  Asserts: Get-RigSlot.ps1 refuses unlisted, empty, real-mod and bootstrap ids; stage-build.ps1 -NoBuild stages
  a mod's bundleV2 into a fake slot and writes a slot.json that verifies, and refuses a real mod's id without
  writing; Test-RigSlot.ps1 catches a changed file and an extra .mod; run.ps1 refuses (exit 3) a plan whose
  slot no longer matches its slot.json, before any other preflight step (the fake steamapps has no game, so it
  could not start one anyway); New-RigProfile.ps1 puts the slot at the real id's place, disables the real id and
  writes expect_versions. Exit codes: 0 pass, 2 failure.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
function Get-DirState([string] $dir) { (@(Get-ChildItem -LiteralPath $dir -File | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" })) -join ';' }

$harness = Split-Path $PSScriptRoot
$pwsh = (Get-Process -Id $PID).Path
$mod = 'verminious_dreams_lighting_dev'
$realId = '3733366748'
$slotId = '9100000001'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-slots-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $steamApps = Join-Path $root 'steamapps'
    $workshop = Join-Path $steamApps 'workshop\content\552500'
    $slotDir = Join-Path $workshop $slotId
    $realDir = Join-Path $workshop $realId
    New-Item -ItemType Directory -Force -Path $slotDir, $realDir | Out-Null
    Set-Content -LiteralPath (Join-Path $slotDir 'vt2_rig_slot.mod') -Value 'placeholder'
    Set-Content -LiteralPath (Join-Path $realDir "$mod.mod") -Value 'real published content'
    $realBefore = Get-DirState $realDir
    $slots = Join-Path $root 'slots.psd1'
    Set-Content -LiteralPath $slots -Value "@{ Slots = @(
    @{ Slot = 1; Id = '$slotId'; Title = 'VT2 Rig Slot 1' }
    @{ Slot = 2; Id = ''; Title = 'VT2 Rig Slot 2' }
    @{ Slot = 3; Id = '$realId'; Title = 'misconfigured: a real mod id' }
    @{ Slot = 4; Id = '3839345856'; Title = 'misconfigured: the bootstrap' }
) }"

    # ---- Get-RigSlot ----
    $ok = & (Join-Path $harness 'Get-RigSlot.ps1') -Slot 1 -Workshop $workshop -SlotsFile $slots
    Assert-True ($ok.Id -eq $slotId -and $ok.Dir -eq $slotDir) 'slot 1 resolves to its folder'
    foreach ($bad in @(@{ Slot = 2; Why = 'no Workshop id yet' }, @{ Slot = 3; Why = "real mod's Workshop id" }, @{ Slot = 4; Why = 'rig bootstrap' }, @{ Slot = 9; Why = 'not listed' })) {
        $msg = $null
        try { $null = & (Join-Path $harness 'Get-RigSlot.ps1') -Slot $bad.Slot -Workshop $workshop -SlotsFile $slots } catch { $msg = $_.Exception.Message }
        Assert-True ($msg -and $msg.Contains($bad.Why)) "slot $($bad.Slot) refused: $msg"
    }

    # ---- stage-build ----
    $out = & $pwsh -NoProfile -File (Join-Path $harness 'stage-build.ps1') -Mod $mod -Slot 3 -NoBuild -SteamApps $steamApps -SlotsFile $slots 2>&1
    Assert-True ($LASTEXITCODE -eq 2 -and ($out -join ' ') -match 'STAGE REFUSED') "staging into a real mod's id is refused (exit $LASTEXITCODE)"
    Assert-True ((Get-DirState $realDir) -ceq $realBefore) 'the real folder is untouched by the refusal'
    $out = & $pwsh -NoProfile -File (Join-Path $harness 'stage-build.ps1') -Mod 'not_a_mod' -Slot 1 -NoBuild -SteamApps $steamApps -SlotsFile $slots 2>&1
    Assert-True ($LASTEXITCODE -eq 2) 'a folder that is not an inventory mod is refused'
    $out = & $pwsh -NoProfile -File (Join-Path $harness 'stage-build.ps1') -Mod $mod -Slot 1 -NoBuild -SteamApps $steamApps -SlotsFile $slots 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "stage-build -NoBuild stages into the fake slot (exit $LASTEXITCODE): $($out -join ' ')"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $slotDir 'vt2_rig_slot.mod'))) 'the placeholder content was replaced'
    Assert-True (Test-Path -LiteralPath (Join-Path $slotDir "$mod.mod")) 'the mod descriptor is in the slot'
    $info = [System.IO.File]::ReadAllText((Join-Path $slotDir 'slot.json')) | ConvertFrom-Json
    Assert-True ($info.mod -eq $mod -and $info.slot_id -eq $slotId -and $info.real_id -eq $realId -and $info.commit -match '^[0-9a-f]{40}$' -and $info.version) "slot.json records mod, ids, commit and version ($($info.version))"
    Assert-True ((Get-DirState $realDir) -ceq $realBefore) 'the real folder is untouched by staging'

    # ---- Test-RigSlot ----
    $good = & (Join-Path $harness 'Test-RigSlot.ps1') -SlotDir $slotDir -Mod $mod
    Assert-True ($good.Ok) "the staged slot verifies ($($good.Problems -join '; '))"
    $wrong = & (Join-Path $harness 'Test-RigSlot.ps1') -SlotDir $slotDir -Mod 'general_tweaker_dev'
    Assert-True (-not $wrong.Ok -and ($wrong.Problems -join ' ') -match 'not ''general_tweaker_dev''') 'a slot holding another mod is reported'
    $bundle = @(Get-ChildItem -LiteralPath $slotDir -Filter '*.mod_bundle')[0]
    $saved = [System.IO.File]::ReadAllBytes($bundle.FullName)
    [System.IO.File]::WriteAllBytes($bundle.FullName, [byte[]]($saved + [byte]0))
    $changed = & (Join-Path $harness 'Test-RigSlot.ps1') -SlotDir $slotDir -Mod $mod
    Assert-True (-not $changed.Ok -and ($changed.Problems -join ' ') -match "hash mismatch: $([regex]::Escape($bundle.Name))") 'a changed staged file is a hash mismatch'

    # ---- run.ps1 refuses before anything else ----
    $planDir = Join-Path $root 'plans'
    New-Item -ItemType Directory -Force -Path $planDir | Out-Null
    $plan = Join-Path $planDir 'slot.json'
    Set-Content -LiteralPath $plan -Value ('{ "name": "slot-test", "mods": ["1369573612", "' + $realId + '"], "local_builds": [ { "mod": "' + $mod + '", "slot": 1 } ], "cases": [] }')
    $out = & $pwsh -NoProfile -File (Join-Path $harness 'run.ps1') -Plan $plan -SteamApps $steamApps -SlotsFile $slots -RigRoot (Join-Path $root 'rig') 2>&1
    $text = $out -join ' '
    Assert-True ($LASTEXITCODE -eq 3) "run.ps1 refuses a slot that does not match slot.json (exit $LASTEXITCODE)"
    Assert-True ($text -match 'RIG REFUSED: local_builds: slot 1 \(9100000001\) for verminious_dreams_lighting_dev does not match its slot\.json: hash mismatch') "the refusal names the slot and the mismatch: $text"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'rig'))) 'nothing was written under the rig root'
    [System.IO.File]::WriteAllBytes($bundle.FullName, $saved)
    Set-Content -LiteralPath (Join-Path $slotDir 'extra.mod') -Value 'x'
    $extra = & (Join-Path $harness 'Test-RigSlot.ps1') -SlotDir $slotDir -Mod $mod
    Assert-True (-not $extra.Ok -and ($extra.Problems -join ' ') -match 'file not in slot.json: extra.mod') 'an extra .mod file is reported'

    # ---- New-RigProfile puts the slot at the real id's place ----
    $owner = Join-Path $root 'owner'
    New-Item -ItemType Directory -Force -Path $owner | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\user_settings.config') -Destination (Join-Path $owner 'user_settings.config')
    Set-Content -LiteralPath (Join-Path $planDir 'case.lua') -Value 'return { run = function(T) end }'
    $plan2 = Join-Path $planDir 'swap.json'
    Set-Content -LiteralPath $plan2 -Value '{ "name": "swap", "mods": ["1369573612", "3733367409"], "cases": [ { "id": "c", "file": "case.lua" } ] }'
    $driver = Join-Path $root 'driver.lua'; Set-Content -LiteralPath $driver -Value 'return {}'
    $prof = & (Join-Path $harness 'New-RigProfile.ps1') -RealProfile $owner -ProfileRoot (Join-Path $root 'profile') -PlanPath $plan2 -Nonce 'abcd1234' -DriverFile $driver `
        -SlotSwaps @{ '3733367409' = $slotId } -ExpectVersions @{ gt_dev = '9.9.9-marker' }
    $cfg = [System.IO.File]::ReadAllText($prof.UserSettings)
    $entries = @([regex]::Matches($cfg, '(?m)^\t\tenabled = (true|false)\n\t\tid = "(\d+)"') | ForEach-Object { [pscustomobject]@{ On = $_.Groups[1].Value; Id = $_.Groups[2].Value } })
    $ids = @($entries | ForEach-Object Id)
    Assert-True (@($ids | Where-Object { $_ -eq $slotId }).Count -eq 1) 'the slot has exactly one entry'
    Assert-True ($ids.IndexOf($slotId) -eq $ids.IndexOf('3733367409') - 1) 'the slot entry sits right before the real entry'
    Assert-True (($entries | Where-Object Id -eq $slotId).On -eq 'true' -and ($entries | Where-Object Id -eq '3733367409').On -eq 'false') 'the slot is enabled and the real id disabled'
    Assert-True ($cfg -match "(?m)^\texpect_versions = \{\n\t\tgt_dev = `"9\.9\.9-marker`"\n\t\}$") 'expect_versions reach the plan block'

    # ---- real entries: multi-line BBCode descriptions (lead runs 20261115-165452/-165827: the slot went to the end) ----
    # fixtures\user_settings.real-entries.config holds four entries copied from a real user_settings.config
    # (descriptions shortened, author_id and url replaced); their descriptions span lines that do not start with tabs.
    $driverId = '3839345856'   # New-RigProfile.ps1 default -DriverId: the rig bootstrap
    $realFixture = Join-Path $PSScriptRoot 'fixtures\user_settings.real-entries.config'
    Copy-Item -LiteralPath $realFixture -Destination (Join-Path $owner 'user_settings.config') -Force
    $before = [System.IO.File]::ReadAllText($realFixture) -replace "`r`n", "`n"
    $orderBefore = @([regex]::Matches($before, '(?m)^\t\tid = "(\d+)"$') | ForEach-Object { $_.Groups[1].Value })
    $plan3 = Join-Path $planDir 'swap-real.json'
    Set-Content -LiteralPath $plan3 -Value '{ "name": "swap-real", "mods": ["1369573612", "3716869446", "3712896117"], "cases": [ { "id": "c", "file": "case.lua" } ] }'
    $prof3 = & (Join-Path $harness 'New-RigProfile.ps1') -RealProfile $owner -ProfileRoot (Join-Path $root 'profile3') -PlanPath $plan3 -Nonce 'abcd1235' -DriverFile $driver `
        -SlotSwaps @{ '3716869446' = $slotId }
    $cfg3 = [System.IO.File]::ReadAllText($prof3.UserSettings)
    $order3 = @([regex]::Matches($cfg3, '(?m)^\t\tid = "(\d+)"$') | ForEach-Object { $_.Groups[1].Value })
    $on3 = @{}; foreach ($m in [regex]::Matches($cfg3, '(?m)^\t\tenabled = (true|false)\n\t\tid = "(\d+)"$')) { $on3[$m.Groups[2].Value] = $m.Groups[1].Value }
    Assert-True (@($order3 | Where-Object { $_ -eq $slotId }).Count -eq 1) "real entries: the slot has exactly one entry ($($order3 -join ','))"
    Assert-True ($order3.IndexOf($slotId) -eq $order3.IndexOf('3716869446') - 1) 'real entries: the slot sits right before the real entry, not at the end'
    $withoutSlotAndDriver = @($order3 | Where-Object { $_ -ne $slotId -and $_ -ne $driverId })
    Assert-True (($withoutSlotAndDriver -join ',') -eq ($orderBefore -join ',')) "real entries: every other entry keeps its place ($($withoutSlotAndDriver -join ','))"
    Assert-True ($order3[-1] -eq $driverId) 'real entries: only the driver is appended, last'
    Assert-True ($on3[$slotId] -eq 'true' -and $on3['3716869446'] -eq 'false') 'real entries: the slot is enabled and the real id ends disabled'
    Assert-True ($on3['1369573612'] -eq 'true' -and $on3['3712896117'] -eq 'true' -and $on3['3733366851'] -eq 'false') 'real entries: plan mods on, others off'
    Assert-True ($cfg3 -notmatch "Rig plan mod $slotId") 'real entries: no appended placeholder entry for the slot'
    $slotEntry = [regex]::Match($cfg3, '(?s)\n\t\{\n(?:(?!\n\t\}).)*?\n\t\tid = "' + $slotId + '"\n.*?\n\t\}\n')
    Assert-True ($slotEntry.Success -and $slotEntry.Value -match '\[b\]Features\[/b\]' -and $slotEntry.Value -match "(?m)^\t\tname = `"VT2 Rig Slot \(local build of 3716869446\)`"$") 'real entries: the slot entry is a full copy of the real one (description kept, name marked)'
    $threw = $null
    try {
        & (Join-Path $harness 'New-RigProfile.ps1') -RealProfile $owner -ProfileRoot (Join-Path $root 'profile4') -PlanPath $plan3 -Nonce 'abcd1236' -DriverFile $driver `
            -SlotSwaps @{ '3999999999' = $slotId } | Out-Null
    }
    catch { $threw = $_.Exception.Message }
    Assert-True ($threw -match 'real mod 3999999999 has no entry') "a slot for a real id with no entry throws instead of appending ($threw)"
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($failures.Count) { Write-Host "[Slots.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[Slots.Tests] OK -- slot refusals, staging, slot.json checks, run.ps1 refusal and the profile swap passed.'
exit 0
