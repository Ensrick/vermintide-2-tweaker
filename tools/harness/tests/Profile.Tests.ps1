#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/New-RigProfile.ps1 (no game) against a fixture user_settings.config.

.DESCRIPTION
  Builds a rig profile from a fake owner profile in a test-owned temporary folder and asserts: the plan block
  parses back (nonce, name, driver text and case texts decode from hex), only the plan's mod ids and the driver
  are enabled, the driver's mods entry exists exactly once (also on a second build from a copy that already has
  it), the plan, results and progress blocks of an earlier run are gone, the forced window and sound settings are
  applied, the save is copied, and the fake owner files are unchanged. The temporary folder is removed at the end.
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
function ConvertFrom-Hex([string] $hex) { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromHexString($hex)) }
function Read-PlanBlocks([string] $cfg) {
    $found = @()
    foreach ($b in [regex]::Matches($cfg, '(?ms)^vt2_rig_plan = \{\n(.*?)^\}\n')) {
        $body = $b.Groups[1].Value
        $plan = [ordered]@{
            nonce  = [regex]::Match($body, '(?m)^\tnonce = "([^"]*)"$').Groups[1].Value
            name   = [regex]::Match($body, '(?m)^\tname = "([^"]*)"$').Groups[1].Value
            driver = ConvertFrom-Hex ([regex]::Match($body, '(?m)^\tdriver_hex = "([0-9a-f]*)"$').Groups[1].Value)
            quit   = [regex]::IsMatch($body, '(?m)^\tquit = true$')
            shield_off = [regex]::IsMatch($body, '(?m)^\tbackend_shield = false$')
            expect_mods = @([regex]::Matches([regex]::Match($body, '(?ms)^\texpect_mods = \[\n(.*?)^\t\]\n').Groups[1].Value, '(?m)^\t\t"([^"]*)"$') | ForEach-Object { $_.Groups[1].Value })
            cases  = @()
            shared = @()
        }
        foreach ($c in [regex]::Matches($body, '(?ms)^\t\t\{\n\t\t\tid = "([^"]*)"\n\t\t\tarena = "([^"]*)"\n\t\t\thex = "([0-9a-f]*)"\n\t\t\}')) {
            $plan.cases += [ordered]@{ id = $c.Groups[1].Value; arena = $c.Groups[2].Value; source = ConvertFrom-Hex $c.Groups[3].Value }
        }
        $sharedBlock = [regex]::Match($body, '(?ms)^\tshared = \[\n(.*?)^\t\]\n')
        if ($sharedBlock.Success) {
            foreach ($s in [regex]::Matches($sharedBlock.Groups[1].Value, '(?ms)^\t\t\{\n\t\t\tid = "([^"]*)"\n\t\t\thex = "([0-9a-f]*)"\n\t\t\}')) {
                $plan.shared += [ordered]@{ id = $s.Groups[1].Value; source = ConvertFrom-Hex $s.Groups[2].Value }
            }
        }
        $found += $plan
    }
    , $found
}
function Get-Enabled([string] $cfg) {
    $map = [ordered]@{}
    foreach ($m in [regex]::Matches($cfg, '(?m)^\t\tenabled = (true|false)\n\t\tid = "(\d+)"')) { $map[$m.Groups[2].Value] = $m.Groups[1].Value }
    $map
}
function Get-Sha([string] $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }

$harness = Split-Path $PSScriptRoot
$builder = Join-Path $harness 'New-RigProfile.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures\user_settings.config'
$driverId = '3839345856'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-profile-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $real = Join-Path $root 'owner'
    $planDir = Join-Path $root 'plan'
    New-Item -ItemType Directory -Force -Path $real, $planDir | Out-Null
    Copy-Item -LiteralPath $fixture -Destination (Join-Path $real 'user_settings.config')
    [System.IO.File]::WriteAllBytes((Join-Path $real 'save_data.sav'), [byte[]](1..64))
    [System.IO.File]::WriteAllText((Join-Path $real 'launcher.config'), "fixture = true`n")
    $ownerBefore = @{}; foreach ($f in 'user_settings.config', 'save_data.sav', 'launcher.config') { $ownerBefore[$f] = Get-Sha (Join-Path $real $f) }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $caseA = "return { issue = 0, run = function(T) T.expect(true, `"quoted `"`"label`"`" `") end }`n"
    $caseB = "-- non-ASCII text survives the hex round trip: " + [char]0x00FC + [char]0x00DF + "`nreturn { run = function(T) T.step('b') end }`n"
    [System.IO.File]::WriteAllText((Join-Path $planDir 'case_a.lua'), $caseA, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $planDir 'case_b.lua'), $caseB, $utf8)
    $driverText = "-- fixture driver`nlocal plan, nonce = ...`nreturn {}`n"
    $driverFile = Join-Path $root 'driver.lua'
    [System.IO.File]::WriteAllText($driverFile, $driverText, $utf8)
    $planJson = '{ "name": "profile-test", "mods": ["1369573612", "9000000099"], "expect_mods": ["VMF", "gt_dev"], "timeout": 120, "settle": 2,' +
        ' "cases": [ { "id": "a", "arena": "keep", "file": "case_a.lua" }, { "id": "b", "arena": "mission:military", "file": "case_b.lua" } ] }'
    $planPath = Join-Path $planDir 'plan.json'
    [System.IO.File]::WriteAllText($planPath, $planJson, $utf8)
    $sharedDir = Join-Path $root 'shared'
    New-Item -ItemType Directory -Force -Path $sharedDir | Out-Null
    $sharedA = "local OM = {}`nreturn OM`n"
    $sharedB = "return { helper = true }`n"
    [System.IO.File]::WriteAllText((Join-Path $sharedDir 'official_mirror.lua'), $sharedA, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $sharedDir 'another_helper.lua'), $sharedB, $utf8)
    [System.IO.File]::WriteAllText((Join-Path $sharedDir 'notes.txt'), "not a helper`n", $utf8)

    # ---- first build: the copied settings have no driver entry and carry an earlier run's blocks ----
    $profileRoot = Join-Path $root 'rig\profile'
    $out = & $builder -RealProfile $real -ProfileRoot $profileRoot -PlanPath $planPath -Nonce '1234abcd' -DriverFile $driverFile -DriverId $driverId -SharedDir $sharedDir
    Assert-True (Test-Path -LiteralPath $out.UserSettings -PathType Leaf) 'profile user_settings.config written'
    Assert-True ($out.Vt2Dir -eq (Join-Path $profileRoot 'AppData\Roaming\Fatshark\Vermintide 2')) 'profile folder layout under the rig profile root'
    $cfg = [System.IO.File]::ReadAllText($out.UserSettings)

    $plans = Read-PlanBlocks $cfg
    Assert-True ($plans.Count -eq 1) "exactly one plan block (got $($plans.Count))"
    $p = $plans[0]
    Assert-True ($p.nonce -eq '1234abcd') 'plan block nonce parses back'
    Assert-True ($p.name -eq 'profile-test') 'plan block name parses back'
    Assert-True ($p.quit) 'plan block asks the driver to quit'
    Assert-True ($p.driver -ceq $driverText) 'driver text decodes from driver_hex unchanged'
    Assert-True ($p.cases.Count -eq 2) "two cases in the plan block (got $($p.cases.Count))"
    Assert-True ($p.cases[0].id -eq 'a' -and $p.cases[0].arena -eq 'keep' -and $p.cases[0].source -ceq $caseA) 'case a parses back with its text'
    Assert-True ($p.cases[1].id -eq 'b' -and $p.cases[1].arena -eq 'mission:military' -and $p.cases[1].source -ceq $caseB) 'case b parses back with its text (UTF-8)'
    Assert-True (-not $p.shield_off) 'backend shield left on by default'
    Assert-True ($p.shared.Count -eq 2) "two shared helpers in the plan block, the .txt file ignored (got $($p.shared.Count))"
    Assert-True ($p.shared[0].id -eq 'another_helper' -and $p.shared[0].source -ceq $sharedB) 'shared helper another_helper parses back with its text'
    Assert-True ($p.shared[1].id -eq 'official_mirror' -and $p.shared[1].source -ceq $sharedA) 'shared helper official_mirror parses back with its text'
    Assert-True ($cfg -notmatch 'earlier-run') "earlier run's plan block removed"
    Assert-True ($cfg -notmatch '(?m)^vt2_rig_results = ') "earlier run's vt2_rig_results removed"
    Assert-True ($cfg -notmatch '(?m)^vt2_rig_progress = ') "earlier run's vt2_rig_progress removed"

    $enabled = Get-Enabled $cfg
    Assert-True ($enabled['1369573612'] -eq 'true') 'plan mod 1369573612 enabled'
    Assert-True ($enabled[$driverId] -eq 'true') 'driver bootstrap enabled'
    Assert-True ($enabled['3733367409'] -eq 'false') 'mod outside the plan (was enabled) disabled'
    Assert-True ($enabled['1111111111'] -eq 'false') 'mod outside the plan (was disabled) stays disabled'
    Assert-True ($enabled['9000000099'] -eq 'true') 'plan mod missing from the copied list gets an entry, enabled'
    Assert-True (@($enabled.Keys | Where-Object { $enabled[$_] -eq 'true' }).Count -eq 3) 'only the plan mods and the driver are enabled'
    Assert-True ([regex]::Matches($cfg, '(?m)^\t\tid = "' + $driverId + '"$').Count -eq 1) 'driver entry exists once after the first build'
    Assert-True ([regex]::Matches($cfg, '(?m)^\t\tid = "9000000099"$').Count -eq 1) 'added plan mod entry exists once'
    $order = @($enabled.Keys)
    Assert-True ($order.IndexOf('9000000099') -lt $order.IndexOf($driverId) -and $order[0] -eq '1369573612') 'added plan mods come before the driver; VMF stays first'
    Assert-True (($p.expect_mods -join ',') -eq 'VMF,gt_dev') "expect_mods parse back from the plan block (got $($p.expect_mods -join ','))"

    Assert-True ($cfg -match '(?m)^max_fps = 30$') 'max_fps forced to 30'
    Assert-True ($cfg -match '(?m)^fullscreen = false$' -and $cfg -match '(?m)^borderless_fullscreen = false$') 'windowed mode forced'
    Assert-True ($cfg -match '(?m)^master_bus_volume = 0$') 'sound muted'
    Assert-True ($cfg -match "(?m)^screen_resolution = \[\n\t1280\n\t720\n\]") 'resolution forced to 1280x720'
    Assert-True ((Get-Sha (Join-Path $out.Vt2Dir 'save_data.sav')) -eq $ownerBefore['save_data.sav']) 'save copied into the rig profile'

    # ---- second build: the copied settings already hold the driver entry, a plan and fresh results ----
    $stale = $cfg + "vt2_rig_results = {`n`tnonce = `"1234abcd`"`n}`nvt2_rig_progress = {`n`tnonce = `"1234abcd`"`n}`n"
    [System.IO.File]::WriteAllText((Join-Path $real 'user_settings.config'), $stale, $utf8)
    $ownerBefore['user_settings.config'] = Get-Sha (Join-Path $real 'user_settings.config')
    $out2 = & $builder -RealProfile $real -ProfileRoot $profileRoot -PlanPath $planPath -Nonce '5678ef01' -DriverFile $driverFile -DriverId $driverId
    $cfg2 = [System.IO.File]::ReadAllText($out2.UserSettings)
    $plans2 = Read-PlanBlocks $cfg2
    Assert-True ($plans2.Count -eq 1 -and $plans2[0].nonce -eq '5678ef01') 'second build: one plan block with the new nonce'
    Assert-True ([regex]::Matches($cfg2, '(?m)^\t\tid = "' + $driverId + '"$').Count -eq 1) 'second build: driver entry still exists once'
    Assert-True ($cfg2 -notmatch '(?m)^vt2_rig_results = ' -and $cfg2 -notmatch '(?m)^vt2_rig_progress = ') 'second build: results and progress from the earlier run removed'
    Assert-True ($plans2[0].shared.Count -eq 0) 'second build without -SharedDir: no shared block'

    # ---- third build: a plan that switches the shield off says so in the plan block ----
    $offPath = Join-Path $planDir 'plan-off.json'
    [System.IO.File]::WriteAllText($offPath, ($planJson.TrimEnd('}') + ', "backend_shield": false, "backend_shield_reason": "commit test" }'), $utf8)
    $out3 = & $builder -RealProfile $real -ProfileRoot $profileRoot -PlanPath $offPath -Nonce '9999aaaa' -DriverFile $driverFile -DriverId $driverId -SharedDir $sharedDir
    $plans3 = Read-PlanBlocks ([System.IO.File]::ReadAllText($out3.UserSettings))
    Assert-True ($plans3.Count -eq 1 -and $plans3[0].shield_off) 'backend_shield false reaches the plan block'

    # ---- WP-H-08: modset, options and settings values ----
    $real2 = Join-Path $root 'owner2'
    New-Item -ItemType Directory -Force -Path $real2 | Out-Null
    $cfgWithSettings = ([System.IO.File]::ReadAllText($fixture) -replace "`r`n", "`n") + "mods_settings = {`n`t`"Spaced Mod`" = {`n`t`tkeep_me = 1`n`t}`n`tVMF = {`n`t`tdeveloper_mode = false`n`t`tlist_value = [`n`t`t`t`"a`"`n`t`t]`n`t`tlogging_mode = `"default`"`n`t}`n}`nuse_pc_menu_layout = false`n"
    [System.IO.File]::WriteAllText((Join-Path $real2 'user_settings.config'), $cfgWithSettings, $utf8)
    $sets = (Import-PowerShellDataFile -LiteralPath (Join-Path $harness 'modsets.psd1')).Sets
    $setName = 'character_weapon_variants'
    $optPlan = Join-Path $planDir 'plan-options.json'
    [System.IO.File]::WriteAllText($optPlan, ('{ "name": "options-test", "modset": "' + $setName + '", "mods": ["9000000099"], "timeout": 60,' +
            ' "settings": { "use_pc_menu_layout": true, "max_fps": 60, "raw_text": "30" },' +
            ' "options": { "VMF": { "developer_mode": true, "list_value": "now a string", "vt2_rig_marker": 2.5 }, "Spaced Mod": { "added": "x \"q\"" }, "gt_dev": { "fresh_mod_block": false } },' +
            ' "cases": [ { "id": "a", "arena": "keep", "file": "case_a.lua" } ] }'), $utf8)
    $out4 = & $builder -RealProfile $real2 -ProfileRoot (Join-Path $root 'rig\profile4') -PlanPath $optPlan -Nonce '4444bbbb' -DriverFile $driverFile -DriverId $driverId
    $cfg4 = [System.IO.File]::ReadAllText($out4.UserSettings)
    $enabled4 = Get-Enabled $cfg4
    $setIds = @($sets[$setName].WorkshopIds)
    Assert-True ((@($setIds | Where-Object { $enabled4[$_] -ne 'true' })).Count -eq 0 -and $enabled4['9000000099'] -eq 'true') "modset: every id of set $setName plus the plan's extra mod is enabled"
    $p4 = (Read-PlanBlocks $cfg4)[0]
    Assert-True (($p4.expect_mods -join ',') -eq (@($sets[$setName].ModIds) -join ',')) "modset: expect_mods come from the set ($($p4.expect_mods -join ','))"
    $resolved = & (Join-Path $harness 'Resolve-RigPlan.ps1') -Plan ([System.IO.File]::ReadAllText($optPlan) | ConvertFrom-Json)
    Assert-True (($resolved.mods -join ',') -eq ((@($setIds) + '9000000099') -join ',')) 'Resolve-RigPlan: set ids first (VMF first), then plan mods the set lacks'
    $unknown = $null
    try { & (Join-Path $harness 'Resolve-RigPlan.ps1') -Plan ('{ "modset": "no-such-set" }' | ConvertFrom-Json) | Out-Null } catch { $unknown = $_.Exception.Message }
    Assert-True ($unknown -match "modset 'no-such-set' is not in") 'an unknown modset throws'
    Assert-True ($cfg4 -match '(?m)^use_pc_menu_layout = true$') 'settings: a JSON true is written as SJSON true'
    Assert-True ($cfg4 -match '(?m)^max_fps = 60$' -and $cfg4 -match '(?m)^raw_text = 30$') 'settings: a number as a number, a string as raw text'
    $vmfBlock = [regex]::Match($cfg4, '(?ms)^\tVMF = \{\n(.*?)^\t\}\n').Groups[1].Value
    Assert-True ($vmfBlock -match '(?m)^\t\tdeveloper_mode = true$' -and $vmfBlock -notmatch 'developer_mode = false') 'options: an existing value is replaced'
    Assert-True ($vmfBlock -match '(?m)^\t\tlist_value = "now a string"$' -and $vmfBlock -notmatch '"a"') 'options: an existing multi-line array is replaced whole'
    Assert-True ($vmfBlock -match '(?m)^\t\tvt2_rig_marker = 2\.5$' -and $vmfBlock -match '(?m)^\t\tlogging_mode = "default"$') 'options: a new value is added and other values stay'
    Assert-True ($cfg4 -match '(?ms)^\t"Spaced Mod" = \{\n\t\tkeep_me = 1\n\t\tadded = "x \\"q\\""\n\t\}') 'options: a quoted mod name and an escaped string'
    Assert-True ($cfg4 -match '(?ms)^\tgt_dev = \{\n\t\tfresh_mod_block = false\n\t\}') 'options: a mod without a block gets one'
    Assert-True ([regex]::Matches($cfg4, '(?m)^mods_settings = \{$').Count -eq 1) 'options: still one mods_settings table'

    foreach ($f in $ownerBefore.Keys) { Assert-True ((Get-Sha (Join-Path $real $f)) -eq $ownerBefore[$f]) "owner file unchanged: $f" }
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

if ($failures.Count) { Write-Host "[Profile.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[Profile.Tests] OK -- plan block, mod list, driver entry, stale blocks and isolation checks passed.'
exit 0
