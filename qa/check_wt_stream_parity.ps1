# Blocking contract gate for the active Weapon Tweaker beta/dev streams.
#
# `weapon_tweaker` is the public gameplay baseline. `weapon_tweaker_dev` keeps
# that baseline plus an explicit tuning/diagnostic overlay. Every inline dev
# overlay is bounded by paired WT_DEV_OVERLAY markers; after those blocks plus
# stream namespace/version identity are removed, all common files must be exact.
# The public tree is separately scanned so dev widgets, commands, and files
# cannot leak back into the beta. The repo-wide #694 localization gate owns
# lifecycle-tag rejection for both streams.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

$WtDevOnlyFiles = @(
    '_wt_longbow_zoom_probe.lua',
    'wt_universal_availability.lua',
    'wt_dev_anim_picker.lua',
    'wt_dev_hold_pose.lua',
    'wt_port_status.lua'
)
$WtPublicCommands = @(
    'brace_to_repeater_dump',
    'brace_to_repeater_skin',
    'dump',
    'dump_actions',
    'dump_weapons',
    'info',
    'sm_probe',
    'verify_wt_availability_sort',
    'verify_wt_loadout_cache',
    'wt_dump_wielded',
    'wt_regression_test'
)

function Normalize-WtLua {
    param([string]$Text, [switch]$Dev)
    $value = $Text.Replace("`r`n", "`n")
    $overlayKind = if ($Dev) { 'DEV' } else { 'PUBLIC' }
    $markerPrefix = "WT_${overlayKind}_OVERLAY"
    $begins = @([regex]::Matches($value, "(?m)^[ \t]*-- ${markerPrefix}_BEGIN:([A-Za-z0-9_-]+)[ \t]*$"))
    $ends = @([regex]::Matches($value, "(?m)^[ \t]*-- ${markerPrefix}_END:([A-Za-z0-9_-]+)[ \t]*$"))
    if ($begins.Count -ne 0 -or $ends.Count -ne 0) {
        if ($begins.Count -ne $ends.Count) { throw "unbalanced $markerPrefix markers" }
        $beginIds = @($begins | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        $endIds = @($ends | ForEach-Object { $_.Groups[1].Value } | Sort-Object)
        if (($beginIds -join "`n") -cne ($endIds -join "`n")) { throw "mismatched $markerPrefix marker ids" }
        if (@($beginIds | Group-Object | Where-Object Count -ne 1).Count -ne 0) { throw "duplicate $markerPrefix marker id" }
        $value = [regex]::Replace($value,
            "(?ms)^[ \t]*-- ${markerPrefix}_BEGIN:([A-Za-z0-9_-]+)[ \t]*\n.*?^[ \t]*-- ${markerPrefix}_END:\1[ \t]*\n?", '')
        if ($value -match "${markerPrefix}_(?:BEGIN|END):") { throw "unconsumed $markerPrefix marker" }
    }
    $value = $value.Replace('scripts/mods/weapon_tweaker_dev/', 'scripts/mods/weapon_tweaker/')
    $value = $value.Replace('weapon_tweaker_dev_data', 'weapon_tweaker_data')
    $value = $value.Replace('weapon_tweaker_dev_localization', 'weapon_tweaker_localization')
    $value = $value.Replace('get_mod("wt_dev")', 'get_mod("wt")')
    $value = [regex]::Replace($value, 'local MOD_VERSION\s*=\s*"[^"]+"', 'local MOD_VERSION = "<STREAM_VERSION>"')
    return $value
}

function Get-WtLuaMap {
    param([string]$Directory, [switch]$Dev)
    $result = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.lua')) {
        $name = $file.Name
        if ($Dev) {
            if ($name -eq 'weapon_tweaker_dev.lua') { $name = 'weapon_tweaker.lua' }
            elseif ($name -eq 'weapon_tweaker_dev_data.lua') { $name = 'weapon_tweaker_data.lua' }
            elseif ($name -eq 'weapon_tweaker_dev_localization.lua') { $name = 'weapon_tweaker_localization.lua' }
        }
        $result[$name] = Normalize-WtLua ([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)) -Dev:$Dev
    }
    return $result
}

function Compare-WtLuaMaps {
    param([hashtable]$Public, [hashtable]$Dev)
    $errors = @()
    foreach ($name in @($Public.Keys | Sort-Object)) {
        if (-not $Dev.ContainsKey($name)) { $errors += "dev runtime is missing $name"; continue }
        if ($Public[$name] -cne $Dev[$name]) {
            $publicLines = @($Public[$name].Split("`n"))
            $devLines = @($Dev[$name].Split("`n"))
            $limit = [Math]::Min($publicLines.Count, $devLines.Count)
            $line = 0
            while ($line -lt $limit -and $publicLines[$line] -ceq $devLines[$line]) { $line++ }
            $errors += "gameplay drift outside a marked dev overlay in ${name}:$($line + 1) public='$($publicLines[$line])' dev='$($devLines[$line])'"
        }
    }
    foreach ($name in @($Dev.Keys | Sort-Object)) {
        if (-not $Public.ContainsKey($name) -and $WtDevOnlyFiles -notcontains $name) {
            $errors += "undocumented dev-only runtime file $name"
        }
    }
    return $errors
}

function Remove-LuaComments {
    param([string]$Text)
    $value = $Text
    $value = [regex]::Replace($value, '--\[==\[(?s:.*?)\]==\]', '')
    $value = [regex]::Replace($value, '--\[\[(?s:.*?)\]\]', '')
    $value = [regex]::Replace($value, '(?m)--[^\r\n]*\r?$', '')
    return $value
}

function Get-WtActiveLua {
    param([string]$Directory)
    $parts = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Filter '*.lua' | Sort-Object Name)) {
        $parts += Remove-LuaComments ([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8))
    }
    return ($parts -join "`n")
}

function Test-WtPublicSurface {
    param([string]$PublicLua)
    $errors = @()
    foreach ($name in $WtDevOnlyFiles) {
        if (Test-Path -LiteralPath (Join-Path $PublicLua $name)) {
            $errors += "public beta contains dev-only file $name"
        }
    }

    $active = Get-WtActiveLua $PublicLua
    $forbidden = @(
        @{ Name = 'dev animation picker'; Pattern = '\bwt_dev_anim_picker\b|\benable_dev_anim_picker\b' },
        @{ Name = 'dev hold-pose tuner'; Pattern = '\bwt_dev_hold_pose\b|\bwt_dev_hp_[A-Za-z0-9_]+' },
        @{ Name = 'dev port-status owner'; Pattern = '\bwt_port_status\b' },
        @{ Name = 'issue-specific live probe'; Pattern = '\b_wt290_diag\b|\[wt:290\]|\b_wt316_zoom_probe\b|\[wt:316\]|\b_wt_longbow_zoom_probe\b' },
        @{ Name = 'dev-only command'; Pattern = 'mod:command\(\s*"(?:animlog|force1p|force3p|wt_coverage|wt_audit_[^"]+)"' },
        @{ Name = 'dev menu label'; Pattern = 'Dev:\s' }
    )
    foreach ($rule in $forbidden) {
        if ($active -match $rule.Pattern) { $errors += "public beta active Lua contains $($rule.Name)" }
    }

    $commands = @([regex]::Matches($active, 'mod:command\(\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    foreach ($command in $commands) {
        if ($WtPublicCommands -notcontains $command) { $errors += "public beta command is not read-only allowlisted: /$command" }
    }
    foreach ($command in $WtPublicCommands) {
        if ($commands -notcontains $command) { $errors += "documented public support command missing: /$command" }
    }

    $dataPath = Join-Path $PublicLua 'weapon_tweaker_data.lua'
    $locPath = Join-Path $PublicLua 'weapon_tweaker_localization.lua'
    $data = Remove-LuaComments ([IO.File]::ReadAllText($dataPath, [Text.Encoding]::UTF8))
    $loc = Remove-LuaComments ([IO.File]::ReadAllText($locPath, [Text.Encoding]::UTF8))
    $locKeys = @{}
    foreach ($match in [regex]::Matches($loc, '(?m)^\s*([A-Za-z][A-Za-z0-9_]*)\s*=')) { $locKeys[$match.Groups[1].Value] = $true }
    foreach ($match in [regex]::Matches($loc, '\bloc\.([A-Za-z][A-Za-z0-9_]*)\s*=')) { $locKeys[$match.Groups[1].Value] = $true }
    $settingIds = @([regex]::Matches($data, 'setting_id\s*=\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    foreach ($settingId in $settingIds) {
        if (-not $locKeys.ContainsKey($settingId)) { $errors += "visible public setting lacks localization owner: $settingId" }
    }
    return $errors
}

function Test-WtDevOverlay {
    param([string]$DevLua)
    $errors = @()
    foreach ($name in $WtDevOnlyFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $DevLua $name) -PathType Leaf)) {
            $errors += "friends-only dev overlay is missing $name"
        }
    }
    $active = Get-WtActiveLua $DevLua
    foreach ($required in @('enable_dev_anim_picker', 'wt_dev_hp_', 'wt_dev_anim_picker', 'wt_dev_hold_pose', 'wt_port_status')) {
        if ($active -notmatch [regex]::Escape($required)) { $errors += "friends-only dev overlay is missing symbol $required" }
    }
    return $errors
}

function Invoke-SelfTest {
    $public = @{ 'weapon_tweaker.lua' = Normalize-WtLua 'local mod = get_mod("wt"); local MOD_VERSION = "0.12.264-beta"; mod:dofile("scripts/mods/weapon_tweaker/x")' }
    $dev = @{ 'weapon_tweaker.lua' = Normalize-WtLua 'local mod = get_mod("wt_dev"); local MOD_VERSION = "0.12.265-dev"; mod:dofile("scripts/mods/weapon_tweaker_dev/x")' }
    if (@(Compare-WtLuaMaps $public $dev).Count -ne 0) { throw 'documented stream identity differences were rejected' }
    $public['shared.lua'] = 'return { value = 1 }'
    $dev['shared.lua'] = 'return { value = 2 }'
    if (-not (@(Compare-WtLuaMaps $public $dev) -match 'gameplay drift')) { throw 'runtime drift was not detected' }
    $dev = $public.Clone(); $dev['unexpected_dev_only.lua'] = 'return true'
    if (-not (@(Compare-WtLuaMaps $public $dev) -match 'undocumented dev-only')) { throw 'dev-only runtime file was not detected' }
    $dev = $public.Clone(); $dev['wt_dev_anim_picker.lua'] = 'return true'
    if (@(Compare-WtLuaMaps $public $dev).Count -ne 0) { throw 'documented dev-only file was rejected' }
    $marked = "return { value = 1 }`n-- WT_DEV_OVERLAY_BEGIN:self-test`nmod:info('dev')`n-- WT_DEV_OVERLAY_END:self-test`n"
    $normalized = Normalize-WtLua $marked -Dev
    if ($normalized -cne "return { value = 1 }`n") { throw 'marked dev overlay was not removed exactly' }
    $publicMarked = "return { value = 1 }`n-- WT_PUBLIC_OVERLAY_BEGIN:self-test`nreturn { public = true }`n-- WT_PUBLIC_OVERLAY_END:self-test`n"
    if ((Normalize-WtLua $publicMarked) -cne "return { value = 1 }`n") { throw 'marked public overlay was not removed exactly' }
    try { $null = Normalize-WtLua "-- WT_DEV_OVERLAY_BEGIN:broken`nreturn true`n" -Dev; throw 'unclosed dev overlay was accepted' }
    catch { if ($_.Exception.Message -notmatch 'unbalanced') { throw } }
    Write-Host '[check_wt_stream_parity -SelfTest] OK'
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path $RepoRoot).Path
$publicRoot = Join-Path $root 'weapon_tweaker'
$devRoot = Join-Path $root 'weapon_tweaker_dev'
$publicLua = Join-Path $publicRoot 'scripts\mods\weapon_tweaker'
$devLua = Join-Path $devRoot 'scripts\mods\weapon_tweaker_dev'
$errors = @()

foreach ($required in @($publicLua, $devLua)) {
    if (-not (Test-Path -LiteralPath $required -PathType Container)) { $errors += "missing runtime directory: $required" }
}

if ($errors.Count -eq 0) {
    $errors += @(Compare-WtLuaMaps (Get-WtLuaMap $publicLua) (Get-WtLuaMap $devLua -Dev))
    $errors += @(Test-WtPublicSurface $publicLua)
    $errors += @(Test-WtDevOverlay $devLua)
}

$publicCfg = [IO.File]::ReadAllText((Join-Path $publicRoot 'itemV2.cfg'), [Text.Encoding]::UTF8)
$devCfg = [IO.File]::ReadAllText((Join-Path $devRoot 'itemV2.cfg'), [Text.Encoding]::UTF8)
if ($publicCfg -notmatch 'visibility\s*=\s*"public"') { $errors += 'public WT visibility is not public' }
if ($publicCfg -notmatch 'published_id\s*=\s*3712896117L') { $errors += 'public WT Workshop id drifted from 3712896117' }
if ($devCfg -notmatch 'visibility\s*=\s*"friends_only"') { $errors += 'dev WT visibility is not friends_only' }
if ($devCfg -notmatch 'published_id\s*=\s*3748824853L') { $errors += 'dev WT Workshop id drifted from 3748824853' }
$publicVersion = if ($publicCfg -match 'title\s*=\s*"Tweaker: Weapons v(\d+)\.(\d+)\.(\d+)-beta"') { @([int]$matches[1], [int]$matches[2], [int]$matches[3]) } else { $null }
$devVersion = if ($devCfg -match 'title\s*=\s*"Tweaker: Weapons v(\d+)\.(\d+)\.(\d+)-dev"') { @([int]$matches[1], [int]$matches[2], [int]$matches[3]) } else { $null }
if (-not $publicVersion) { $errors += 'public WT cfg does not carry a three-segment -beta version' }
if (-not $devVersion) { $errors += 'dev WT cfg does not carry a three-segment -dev version' }
if ($publicVersion -and $devVersion -and (($publicVersion[0] -ne $devVersion[0]) -or ($publicVersion[1] -ne $devVersion[1]) -or (($publicVersion[2] + 1) -ne $devVersion[2]))) {
    $errors += 'dev WT version must be exactly one patch ahead of its mirrored public beta baseline'
}

$publicMod = [IO.File]::ReadAllText((Join-Path $publicRoot 'weapon_tweaker.mod'), [Text.Encoding]::UTF8)
$devMod = [IO.File]::ReadAllText((Join-Path $devRoot 'weapon_tweaker_dev.mod'), [Text.Encoding]::UTF8)
$normalizedDevMod = $devMod.Replace('weapon_tweaker_dev', 'weapon_tweaker').Replace('new_mod("wt_dev"', 'new_mod("wt"')
if ($publicMod.Replace("`r`n", "`n") -cne $normalizedDevMod.Replace("`r`n", "`n")) { $errors += 'VMF manifest differs beyond documented stream identity' }

$publicPackage = [IO.File]::ReadAllText((Join-Path $publicRoot 'resource_packages\weapon_tweaker\weapon_tweaker.package'), [Text.Encoding]::UTF8)
$devPackage = [IO.File]::ReadAllText((Join-Path $devRoot 'resource_packages\weapon_tweaker_dev\weapon_tweaker_dev.package'), [Text.Encoding]::UTF8)
$normalizedDevPackage = $devPackage.Replace('weapon_tweaker_dev', 'weapon_tweaker')
if ($publicPackage.Replace("`r`n", "`n") -cne $normalizedDevPackage.Replace("`r`n", "`n")) { $errors += 'resource package differs beyond documented stream identity' }

# preview.jpg and CHANGELOG.md are intentionally excluded: each Workshop stream
# has independent presentation/history. Bundle outputs are derived artifacts.
if ($errors.Count -gt 0) {
    Write-Host '[check_wt_stream_parity] ERRORS:' -ForegroundColor Red
    foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) { Write-Host '[check_wt_stream_parity] OK - public beta is dev-surface clean; shared gameplay files match; friends-only overlay is present.' -ForegroundColor Green }
exit 0
