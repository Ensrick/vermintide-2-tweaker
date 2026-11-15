#requires -Version 7
<#
.SYNOPSIS
  Builds the rig's isolated game profile: copies the owner's save and settings in, never back, and writes the
  run plan into the copy of user_settings.config.

.DESCRIPTION
  Reads (never writes) the owner's profile folder. Writes only under -ProfileRoot:
    <ProfileRoot>\AppData\Roaming\Fatshark\Vermintide 2\  save_data.sav, save_data.old, launcher.config (copies),
                                                         shader_cache.pipe_lib (copied once), user_settings.config
    <ProfileRoot>\AppData\Local\
  In the copied user_settings.config it forces a windowed 1280x720 silent 30 fps game, removes the plan, results
  and progress blocks of any earlier run, enables only the plan's mods plus the driver bootstrap (adding the
  driver's mods entry when missing), and prepends the plan block (nonce, driver text, case texts and the shared
  helpers of -SharedDir as hex).

  run.ps1 calls this; tools/harness/tests/Profile.Tests.ps1 calls it against a fixture.

.OUTPUTS
  [pscustomobject] with ProfileRoot, AppData, LocalAppData, Vt2Dir, UserSettings.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $RealProfile,     # the owner's %APPDATA%\Fatshark\Vermintide 2 (read only)
    [Parameter(Mandatory)] [string] $ProfileRoot,     # becomes the child-only USERPROFILE
    [string] $PlanPath = '',                          # plan JSON; empty for a no-plan experiment
    [string] $Nonce = '',
    [string] $DriverFile = '',
    [string] $DriverId = '3839345856',
    [string] $SharedDir = '',                         # qa/runtime/_shared: every *.lua in it travels with the plan
    [hashtable] $SlotSwaps = @{},                     # WP-H-07: real Workshop id -> rig slot id holding its local build
    [hashtable] $ExpectVersions = @{},                # WP-H-07: VMF mod id -> staged MOD_VERSION the smoke case checks
    [switch] $KeepOwnerMods                           # no-plan experiments: leave the copied mod list as it is
)
$ErrorActionPreference = 'Stop'

function ConvertTo-Hex([string] $text) { -join ([System.Text.Encoding]::UTF8.GetBytes($text) | ForEach-Object { $_.ToString('x2') }) }
function ConvertTo-SjsonString([string] $s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }
function Set-TopLevel([string] $text, [string] $key, [string] $value) {
    $rx = [regex]("(?m)^" + [regex]::Escape($key) + " = .*$")
    if ($rx.IsMatch($text)) { return $rx.Replace($text, "$key = $value", 1) }
    return "$key = $value`n" + $text
}

$planObj = $null
if ($PlanPath) {
    $PlanPath = (Resolve-Path -LiteralPath $PlanPath).Path
    $planObj = [System.IO.File]::ReadAllText($PlanPath) | ConvertFrom-Json
    if (-not $Nonce) { throw 'A plan needs -Nonce.' }
    if (-not $DriverFile -or -not (Test-Path -LiteralPath $DriverFile -PathType Leaf)) { throw "Driver file not found: $DriverFile" }
}

$rigAppData = Join-Path $ProfileRoot 'AppData\Roaming'
$rigLocal = Join-Path $ProfileRoot 'AppData\Local'
$rigVt2 = Join-Path $rigAppData 'Fatshark\Vermintide 2'
New-Item -ItemType Directory -Force -Path $rigVt2, $rigLocal, (Join-Path $rigVt2 'console_logs') | Out-Null
foreach ($f in 'save_data.sav', 'save_data.old', 'launcher.config') {
    $src = Join-Path $RealProfile $f
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $rigVt2 $f) -Force }
}
$shader = Join-Path $rigVt2 'shader_cache.pipe_lib'
if (-not (Test-Path -LiteralPath $shader) -and (Test-Path -LiteralPath (Join-Path $RealProfile 'shader_cache.pipe_lib'))) {
    Copy-Item -LiteralPath (Join-Path $RealProfile 'shader_cache.pipe_lib') -Destination $shader
}

$cfg = [System.IO.File]::ReadAllText((Join-Path $RealProfile 'user_settings.config')) -replace "`r`n", "`n"
$forced = [ordered]@{ borderless_fullscreen = 'false'; fullscreen = 'false'; max_fps = '30'; master_bus_volume = '0' }
if ($planObj -and $planObj.settings) { foreach ($p in $planObj.settings.PSObject.Properties) { $forced[$p.Name] = [string]$p.Value } }
foreach ($k in $forced.Keys) { $cfg = Set-TopLevel $cfg $k $forced[$k] }
$cfg = [regex]::Replace($cfg, '(?ms)^screen_resolution = \[.*?^\]', "screen_resolution = [`n`t1280`n`t720`n]", 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_plan = \{.*?^\}\n', '', 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_results = \{.*?^\}\n', '', 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_progress = \{.*?^\}\n', '', 1)

if ($planObj -or -not $KeepOwnerMods) {
    $wanted = @(); if ($planObj -and $planObj.mods) { $wanted = @($planObj.mods | ForEach-Object { [string]$_ }) }
    if ($planObj) { $wanted += $DriverId }
    # WP-H-07 local builds: the slot takes the real mod's place in the load order (a copy of the real entry with the
    # slot id, inserted right before it) and the real id is left disabled.
    if ($planObj -and $SlotSwaps.Count) {
        $entryOf = { param([string] $id) '(?m)^\t\{\n(?:\t\t[^\n]*\n)*?\t\tid = "' + $id + '"\n(?:\t\t[^\n]*\n)*?\t\}\n' }
        foreach ($real in @($SlotSwaps.Keys)) {
            $slotId = [string]$SlotSwaps[$real]
            if ($real -notmatch '^\d+$' -or $slotId -notmatch '^\d+$') { throw "slot swap ids must be Workshop numbers: $real -> $slotId" }
            $cfg = [regex]::Replace($cfg, (& $entryOf $slotId), '')
            $m = [regex]::Match($cfg, (& $entryOf $real))
            if ($m.Success) {
                $copy = $m.Value -replace ('(?m)^\t\tid = "' + $real + '"$'), "`t`tid = `"$slotId`""
                $copy = $copy -replace '(?m)^\t\tname = "[^"]*"$', "`t`tname = `"VT2 Rig Slot (local build of $real)`""
                $cfg = $cfg.Insert($m.Index, $copy)
            }
        }
        $wanted = @($wanted | ForEach-Object { if ($SlotSwaps.ContainsKey($_)) { [string]$SlotSwaps[$_] } else { $_ } })
    }
    # Every plan mod and the driver need an entry in the mods array; add one at the end when missing (plan mods
    # first, the driver last). The game reports an entry whose folder Steam does not list as "was not found in
    # the workshop folder" (mod_manager.lua:297), which Read-HostLog.ps1 forbids by default (WP-H-02).
    if ($planObj) {
        foreach ($id in $wanted) {
            if ($id -notmatch '^\d+$') { throw "mod id must be a Workshop folder number: $id" }
            if ($cfg -match ('(?m)^\t\tid = "' + $id + '"$')) { continue }
            $label = if ($id -eq $DriverId) { 'VT2 Rig Driver' } else { "Rig plan mod $id" }
            $entry = "`t{`n`t`tauthor = `"rig`"`n`t`tauthor_id = 0`n`t`tbanned = false`n`t`tdependency_error = `"`"`n`t`tdescription = `"`"`n`t`tdownload_pending = false`n`t`tdownloading = false`n`t`tenabled = true`n`t`tid = `"$id`"`n`t`tinstalled = true`n`t`tlast_updated = `"1/1/2026 12:00:00 AM`"`n`t`tname = `"$label`"`n`t`tnum_children = 0`n`t`tout_of_date = false`n`t`tsanctioned = false`n`t`tsubscribed = true`n`t}`n"
            $m = [regex]::Match($cfg, '(?ms)^mods = \[\n.*?^\]')
            if (-not $m.Success) { throw 'mods array not found in user_settings.config' }
            $insertAt = $m.Index + $m.Length - 1
            $cfg = $cfg.Substring(0, $insertAt) + $entry + $cfg.Substring($insertAt)
        }
    }
    $cfg = [regex]::Replace($cfg, '(?m)^(\t\t)enabled = (true|false)(\n\t\tid = "(\d+)")', {
            param($m)
            $on = if ($wanted -contains $m.Groups[4].Value) { 'true' } else { 'false' }
            $m.Groups[1].Value + "enabled = $on" + $m.Groups[3].Value
        })
    # order: the game loads in array order. VMF stays first and the driver is last, which the insert above
    # guarantees, so the plan's own order does not need to be applied.
}

if ($planObj) {
    $planDir = Split-Path $PlanPath
    $driverSource = [System.IO.File]::ReadAllText($DriverFile)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("vt2_rig_plan = {`n")
    [void]$sb.Append("`tnonce = `"$Nonce`"`n`tname = $(ConvertTo-SjsonString $planObj.name)`n")
    [void]$sb.Append("`ttimeout = $([int]($planObj.timeout ?? 600))`n`tsettle = $([int]($planObj.settle ?? 4))`n`tquit = true`n")
    if ($planObj.PSObject.Properties['backend_shield'] -and $planObj.backend_shield -eq $false) { [void]$sb.Append("`tbackend_shield = false`n") }
    if ($planObj.arenas) { [void]$sb.Append("`tarenas = [`n"); foreach ($a in $planObj.arenas) { [void]$sb.Append("`t`t$(ConvertTo-SjsonString $a)`n") }; [void]$sb.Append("`t]`n") }
    # WP-H-02: the smoke case asserts every one of these VMF mod ids is loaded
    if ($planObj.PSObject.Properties['expect_mods'] -and $planObj.expect_mods) { [void]$sb.Append("`texpect_mods = [`n"); foreach ($e in $planObj.expect_mods) { [void]$sb.Append("`t`t$(ConvertTo-SjsonString ([string]$e))`n") }; [void]$sb.Append("`t]`n") }
    # WP-H-07: the staged versions of local builds, keyed by VMF mod id
    if ($ExpectVersions.Count) {
        [void]$sb.Append("`texpect_versions = {`n")
        foreach ($k in ($ExpectVersions.Keys | Sort-Object)) {
            if ($k -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "expect_versions key is not a mod id: $k" }
            [void]$sb.Append("`t`t$k = $(ConvertTo-SjsonString ([string]$ExpectVersions[$k]))`n")
        }
        [void]$sb.Append("`t}`n")
    }
    [void]$sb.Append("`tdriver_hex = `"$(ConvertTo-Hex $driverSource)`"`n")
    [void]$sb.Append("`tcases = [`n")
    foreach ($c in $planObj.cases) {
        $file = Join-Path $planDir $c.file
        if (-not (Test-Path -LiteralPath $file)) { throw "Case file not found: $file" }
        $src = [System.IO.File]::ReadAllText($file)
        [void]$sb.Append("`t`t{`n`t`t`tid = $(ConvertTo-SjsonString $c.id)`n`t`t`tarena = $(ConvertTo-SjsonString ($c.arena ?? 'keep'))`n`t`t`thex = `"$(ConvertTo-Hex $src)`"`n`t`t}`n")
    }
    [void]$sb.Append("`t]`n")
    # shared helpers (WP-H-14): the driver compiles each into a table; cases get them with T.shared(<file name>)
    $sharedFiles = @()
    if ($SharedDir -and (Test-Path -LiteralPath $SharedDir -PathType Container)) {
        $sharedFiles = @(Get-ChildItem -LiteralPath $SharedDir -File -Filter '*.lua' | Sort-Object Name)
    }
    if ($sharedFiles.Count) {
        [void]$sb.Append("`tshared = [`n")
        foreach ($f in $sharedFiles) {
            $src = [System.IO.File]::ReadAllText($f.FullName)
            [void]$sb.Append("`t`t{`n`t`t`tid = $(ConvertTo-SjsonString $f.BaseName)`n`t`t`thex = `"$(ConvertTo-Hex $src)`"`n`t`t}`n")
        }
        [void]$sb.Append("`t]`n")
    }
    [void]$sb.Append("}`n")
    $cfg = $sb.ToString() + $cfg
}
$userSettings = Join-Path $rigVt2 'user_settings.config'
[System.IO.File]::WriteAllText($userSettings, $cfg, [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    ProfileRoot  = $ProfileRoot
    AppData      = $rigAppData
    LocalAppData = $rigLocal
    Vt2Dir       = $rigVt2
    UserSettings = $userSettings
}
