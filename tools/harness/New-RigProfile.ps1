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
  driver's mods entry when missing), and prepends the plan block (nonce, driver text, case texts, the shared
  helpers of -SharedDir and the driver helper groups of -LibDir as hex).

  WP-H-08 part 3: the plan's "save" picks the save the profile starts from ("owner-copy", the default, or a fixture
  folder under -SaveFixtureDir; qa/runtime/fixtures/saves/README.md), and every profile gets mod developer mode on
  and VMF logging every level to the log file (Set-RigForcedModSettings).

  run.ps1 calls this; tools/harness/tests/Profile.Tests.ps1 calls it against a fixture.

.OUTPUTS
  [pscustomobject] with ProfileRoot, AppData, LocalAppData, Vt2Dir, UserSettings, Save (the save name used, or
  "kept" for -KeepProfile).
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
    [string] $LibDir = '',                            # WP-H-06 tools/harness/driver/lib: every *.lua in it travels too
    [hashtable] $SlotSwaps = @{},                     # WP-H-07: real Workshop id -> rig slot id holding its local build
    [hashtable] $ExpectVersions = @{},                # WP-H-07: VMF mod id -> staged MOD_VERSION the smoke case checks
    [switch] $KeepOwnerMods,                          # no-plan experiments: leave the copied mod list as it is
    [switch] $KeepProfile,                            # WP-H-08 boots: start from the profile the previous boot left
    [string] $SaveFixtureDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\fixtures\saves')   # WP-H-08 plan "save" fixtures
)
$ErrorActionPreference = 'Stop'

function ConvertTo-Hex([string] $text) { -join ([System.Text.Encoding]::UTF8.GetBytes($text) | ForEach-Object { $_.ToString('x2') }) }
function ConvertTo-SjsonString([string] $s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }
function Set-TopLevel([string] $text, [string] $key, [string] $value) {
    $rx = [regex]("(?m)^" + [regex]::Escape($key) + " = .*$")
    if ($rx.IsMatch($text)) { return $rx.Replace($text, "$key = $value", 1) }
    return "$key = $value`n" + $text
}
# A JSON scalar as SJSON text: true/false, a number in invariant form, a quoted string (-RawString: the string as it is).
function ConvertTo-SjsonScalar($value, [switch] $RawString) {
    if ($value -is [bool]) { return $(if ($value) { 'true' } else { 'false' }) }
    if ($value -is [int] -or $value -is [long] -or $value -is [double] -or $value -is [decimal]) { return [System.Convert]::ToString($value, [System.Globalization.CultureInfo]::InvariantCulture) }
    if ($value -is [string]) { return $(if ($RawString) { $value } else { ConvertTo-SjsonString $value }) }
    throw "plan value must be true, false, a number or a string (got $($value.GetType().Name)): $value"
}
function ConvertTo-SjsonKey([string] $name) { if ($name -match '^[A-Za-z_][A-Za-z0-9_]*$') { $name } else { ConvertTo-SjsonString $name } }
# Sets mods_settings.<mod>.<setting> = <value> in the user settings text. The table, the mod's block and the setting are
# matched by indentation (one tab per level, as the game writes the file); an existing value, one line or a multi-line
# table or array, is replaced.
function Set-ModOption([string] $text, [string] $mod, [string] $setting, [string] $value) {
    $tableRx = [regex]'(?ms)^mods_settings = \{\n(.*?)^\}\n'
    if (-not $tableRx.IsMatch($text)) { $text = "mods_settings = {`n}`n" + $text }
    $table = $tableRx.Match($text)
    $body = $table.Groups[1].Value
    $modKey = ConvertTo-SjsonKey $mod
    $modRx = [regex]('(?ms)^\t' + [regex]::Escape($modKey) + ' = \{\n(.*?)^\t\}\n')
    if (-not $modRx.IsMatch($body)) { $body += "`t$modKey = {`n`t}`n" }
    $modBlock = $modRx.Match($body)
    $inner = $modBlock.Groups[1].Value
    $setKey = [regex]::Escape((ConvertTo-SjsonKey $setting))
    $inner = [regex]::Replace($inner, '(?ms)^\t\t' + $setKey + ' = [\[\{]\n.*?^\t\t[\]\}]\n', '')
    $inner = [regex]::Replace($inner, '(?m)^\t\t' + $setKey + ' = .*\n', '')
    $inner += "`t`t$(ConvertTo-SjsonKey $setting) = $value`n"
    $body = $body.Substring(0, $modBlock.Groups[1].Index) + $inner + $body.Substring($modBlock.Groups[1].Index + $modBlock.Groups[1].Length)
    return $text.Substring(0, $table.Groups[1].Index) + $body + $text.Substring($table.Groups[1].Index + $table.Groups[1].Length)
}

# Sets <key> = <value> inside a top-level table (one tab of indentation, as the game writes the file); a missing table
# is created with $Defaults (lines of "key = value") and the key.
function Set-TopLevelTableKey([string] $text, [string] $table, [string] $key, [string] $value, [string[]] $Defaults = @()) {
    $rx = [regex]('(?ms)^' + [regex]::Escape($table) + ' = \{\n(.*?)^\}\n')
    if (-not $rx.IsMatch($text)) {
        $lines = @($Defaults | Where-Object { $_ -notmatch ('^' + [regex]::Escape($key) + ' = ') }) + "$key = $value"
        return "$table = {`n" + (($lines | ForEach-Object { "`t$_`n" }) -join '') + "}`n" + $text
    }
    $m = $rx.Match($text)
    $inner = [regex]::Replace($m.Groups[1].Value, '(?m)^\t' + [regex]::Escape($key) + ' = .*\n', '')
    $inner += "`t$key = $value`n"
    return $text.Substring(0, $m.Groups[1].Index) + $inner + $text.Substring($m.Groups[1].Index + $m.Groups[1].Length)
}
# WP-H-08 step 4: what every rig profile forces.
# - The game's mod manager reads the top-level mod_settings table once at start; its developer_mode switch defaults to
#   false (Vermintide-2-Source-Code/scripts/managers/mod/mod_manager.lua:11-15, read at :50-52 and :120).
# - VMF keeps its own developer_mode and copies it into that table when it changes
#   (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/vmf_options.lua:27-56, 175-181, 216-219).
# - VMF's logging: with logging_mode "custom" each output_mode_<level> is 0 off, 1 log, 2 chat, 3 both
#   (vmf_options.lua:57-123; modules/core/logging.lua:136-152, odd values reach the log). The defaults keep
#   echo/error/warning at 3 and info at 1 and turn debug off; the rig keeps them and sends debug to the log too.
$RigForcedModManager = [ordered]@{ developer_mode = 'true' }
$RigForcedVmf = [ordered]@{
    developer_mode = 'true'; logging_mode = '"custom"'
    output_mode_echo = '3'; output_mode_error = '3'; output_mode_warning = '3'; output_mode_info = '1'; output_mode_debug = '1'
}
function Set-RigForcedModSettings([string] $text) {
    foreach ($k in $RigForcedModManager.Keys) {
        $text = Set-TopLevelTableKey $text 'mod_settings' $k $RigForcedModManager[$k] -Defaults @('developer_mode = false', 'log_level = 1', 'toposort = false')
    }
    foreach ($k in $RigForcedVmf.Keys) { $text = Set-ModOption $text 'VMF' $k $RigForcedVmf[$k] }
    return $text
}

$planObj = $null
if ($PlanPath) {
    $PlanPath = (Resolve-Path -LiteralPath $PlanPath).Path
    $planObj = [System.IO.File]::ReadAllText($PlanPath) | ConvertFrom-Json
    # WP-H-08: "modset" fills mods and expect_mods from tools/harness/modsets.psd1 (run.ps1 resolves it the same way)
    $planObj = & (Join-Path $PSScriptRoot 'Resolve-RigPlan.ps1') -Plan $planObj
    if (-not $Nonce) { throw 'A plan needs -Nonce.' }
    if (-not $DriverFile -or -not (Test-Path -LiteralPath $DriverFile -PathType Leaf)) { throw "Driver file not found: $DriverFile" }
}

$rigAppData = Join-Path $ProfileRoot 'AppData\Roaming'
$rigLocal = Join-Path $ProfileRoot 'AppData\Local'
$rigVt2 = Join-Path $rigAppData 'Fatshark\Vermintide 2'
New-Item -ItemType Directory -Force -Path $rigVt2, $rigLocal, (Join-Path $rigVt2 'console_logs') | Out-Null
# -KeepProfile (a later boot of a plan with boots): the save and settings the previous boot left in the rig profile
# are the starting point; nothing is copied from the owner's profile again.
# WP-H-08 plan "save": "owner-copy" (default) copies the owner's save files; any other name is a fixture folder
# <SaveFixtureDir>\<name>\ whose fixture.json lists every save file it holds with its SHA-256 (README.md there says what
# a save contains). The rig profile's own save files are removed first, so "fresh" (no files) starts with no save.
$saveFiles = 'save_data.sav', 'save_data.old'
$saveName = 'owner-copy'
if ($planObj -and $planObj.PSObject.Properties['save'] -and -not [string]::IsNullOrWhiteSpace([string]$planObj.save)) { $saveName = [string]$planObj.save }
$fixture = $null
if ($saveName -ne 'owner-copy' -and -not $KeepProfile) {
    if ($saveName -notmatch '^[a-z0-9][a-z0-9_-]{0,47}$') { throw "plan save '$saveName' is not a fixture name (lower case letters, digits, '-' and '_')" }
    $fixtureDir = Join-Path $SaveFixtureDir $saveName
    $manifestPath = Join-Path $fixtureDir 'fixture.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "plan save '$saveName': no fixture at $fixtureDir (fixture.json missing)" }
    $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $listed = @{}
    foreach ($entry in @($manifest.files | Where-Object { $_ })) {
        $fileName = [string]$entry.name
        if ($saveFiles -notcontains $fileName) { throw "plan save '$saveName': fixture.json lists '$fileName'; a fixture holds only $($saveFiles -join ', ')" }
        $path = Join-Path $fixtureDir $fileName
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "plan save '$saveName': listed file $fileName is missing" }
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ne ([string]$entry.sha256).ToUpperInvariant()) { throw "plan save '$saveName': $fileName has SHA-256 $hash, fixture.json says $($entry.sha256)" }
        $listed[$fileName] = $path
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $fixtureDir -File)) {
        if ($f.Name -notin 'fixture.json', 'README.md' -and -not $listed.ContainsKey($f.Name)) { throw "plan save '$saveName': $($f.Name) is in the fixture folder but not listed in fixture.json" }
    }
    $fixture = $listed
}
if ($KeepProfile) {
    if (-not (Test-Path -LiteralPath (Join-Path $rigVt2 'user_settings.config') -PathType Leaf)) { throw "KeepProfile: no rig profile to keep under $rigVt2" }
    $saveName = 'kept'
}
else {
    $src = Join-Path $RealProfile 'launcher.config'
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $rigVt2 'launcher.config') -Force }
    foreach ($f in $saveFiles) {
        $dst = Join-Path $rigVt2 $f
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force }
        $from = if ($fixture) { $fixture[$f] } else { Join-Path $RealProfile $f }
        if ($from -and (Test-Path -LiteralPath $from -PathType Leaf)) { Copy-Item -LiteralPath $from -Destination $dst -Force }
    }
}
$shader = Join-Path $rigVt2 'shader_cache.pipe_lib'
if (-not (Test-Path -LiteralPath $shader) -and (Test-Path -LiteralPath (Join-Path $RealProfile 'shader_cache.pipe_lib'))) {
    Copy-Item -LiteralPath (Join-Path $RealProfile 'shader_cache.pipe_lib') -Destination $shader
}

$cfgSource = if ($KeepProfile) { Join-Path $rigVt2 'user_settings.config' } else { Join-Path $RealProfile 'user_settings.config' }
$cfg = [System.IO.File]::ReadAllText($cfgSource) -replace "`r`n", "`n"
$forced = [ordered]@{ borderless_fullscreen = 'false'; fullscreen = 'false'; max_fps = '30'; master_bus_volume = '0' }
# plan "settings": top-level user settings; a JSON boolean or number is written as SJSON (true, 30), a string as it
# is (raw SJSON text, e.g. "30")
if ($planObj -and $planObj.settings) { foreach ($p in $planObj.settings.PSObject.Properties) { $forced[$p.Name] = ConvertTo-SjsonScalar $p.Value -RawString } }
foreach ($k in $forced.Keys) { $cfg = Set-TopLevel $cfg $k $forced[$k] }
$cfg = [regex]::Replace($cfg, '(?ms)^screen_resolution = \[.*?^\]', "screen_resolution = [`n`t1280`n`t720`n]", 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_plan = \{.*?^\}\n', '', 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_results = \{.*?^\}\n', '', 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_progress = \{.*?^\}\n', '', 1)
# WP-H-08 plan "options": { "<VMF mod id>": { "<setting>": <value> } } goes into the top-level mods_settings table,
# which VMF reads once when it loads (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:10).
if ($planObj -and $planObj.PSObject.Properties['options'] -and $planObj.options) {
    foreach ($modProp in $planObj.options.PSObject.Properties) {
        foreach ($setProp in $modProp.Value.PSObject.Properties) { $cfg = Set-ModOption $cfg $modProp.Name $setProp.Name (ConvertTo-SjsonScalar $setProp.Value) }
    }
}
# WP-H-08 step 4, after the plan's options so they always hold: mod developer mode on, every VMF log level to the log file.
$cfg = Set-RigForcedModSettings $cfg

if ($planObj -or -not $KeepOwnerMods) {
    $wanted = @(); if ($planObj -and $planObj.mods) { $wanted = @($planObj.mods | ForEach-Object { [string]$_ }) }
    if ($planObj) { $wanted += $DriverId }
    # WP-H-07 local builds: the slot takes the real mod's place in the load order (a copy of the real entry with the
    # slot id, inserted right before it) and the real id is left disabled. An entry is bracketed from the "\t{" line
    # before its "\t\tid" line to the first "\t}" line after it: a real entry's description is free text over many
    # lines that need not start with tabs (BBCode, blank lines), so no line pattern may be assumed in between. The
    # fields after id are one-line values and tab-indented arrays, so the first "\t}" after id closes the entry.
    if ($planObj -and $SlotSwaps.Count) {
        $findEntry = {
            param([string] $text, [string] $id)
            $idLine = [regex]::Match($text, '(?m)^\t\tid = "' + $id + '"$')
            if (-not $idLine.Success) { return $null }
            $open = $text.LastIndexOf("`n`t{`n", $idLine.Index)
            $close = $text.IndexOf("`n`t}`n", $idLine.Index)
            $array = [regex]::Match($text, '(?m)^mods = \[$')
            if ($open -lt 0 -or $close -lt 0 -or -not $array.Success -or $open -lt $array.Index) {
                throw "mod entry $id found but not bracketed by tab-{ and tab-} lines inside the mods array"
            }
            $start = $open + 1
            $end = $close + 4
            [pscustomobject]@{ Index = $start; Length = $end - $start; Value = $text.Substring($start, $end - $start) }
        }
        foreach ($real in @($SlotSwaps.Keys)) {
            $slotId = [string]$SlotSwaps[$real]
            if ($real -notmatch '^\d+$' -or $slotId -notmatch '^\d+$') { throw "slot swap ids must be Workshop numbers: $real -> $slotId" }
            # an entry the owner's list already holds for the slot item goes (it would load at its own place)
            while ($null -ne ($old = & $findEntry $cfg $slotId)) { $cfg = $cfg.Remove($old.Index, $old.Length) }
            $m = & $findEntry $cfg $real
            if ($null -eq $m) {
                throw "slot swap: the real mod $real has no entry in the copied user_settings.config, so slot $slotId has no load position to take (subscribe the real mod, or drop it from local_builds)"
            }
            $copy = $m.Value -replace ('(?m)^\t\tid = "' + $real + '"$'), "`t`tid = `"$slotId`""
            $copy = $copy -replace '(?m)^\t\tname = "[^"\n]*"$', "`t`tname = `"VT2 Rig Slot (local build of $real)`""
            $cfg = $cfg.Insert($m.Index, $copy)
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
    # shared helpers (WP-H-14): the driver compiles each into a table; cases get them with T.shared(<file name>).
    # driver helper groups (WP-H-06): each returns install(T, ctx); the driver installs them into every case's T.
    foreach ($list in @(@{ Key = 'shared'; Dir = $SharedDir }, @{ Key = 'libs'; Dir = $LibDir })) {
        $files = @()
        if ($list.Dir -and (Test-Path -LiteralPath $list.Dir -PathType Container)) {
            $files = @(Get-ChildItem -LiteralPath $list.Dir -File -Filter '*.lua' | Sort-Object Name)
        }
        if ($files.Count) {
            [void]$sb.Append("`t$($list.Key) = [`n")
            foreach ($f in $files) {
                $src = [System.IO.File]::ReadAllText($f.FullName)
                [void]$sb.Append("`t`t{`n`t`t`tid = $(ConvertTo-SjsonString $f.BaseName)`n`t`t`thex = `"$(ConvertTo-Hex $src)`"`n`t`t}`n")
            }
            [void]$sb.Append("`t]`n")
        }
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
    Save         = $saveName
}
