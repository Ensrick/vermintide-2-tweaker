# Blocking parity gate for the active Weapon Tweaker beta/dev streams.
#
# `weapon_tweaker` is the canonical feature baseline. The friends-only
# `weapon_tweaker_dev` stream must contain the same shipped Lua runtime after
# normalizing its deliberately separate VMF id, settings namespace, script
# path, entry filenames, version suffix, package identity, Workshop identity,
# visibility, and preview image. No gameplay/runtime exception list exists.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Normalize-WtLua {
    param([string]$Text)
    $value = $Text.Replace("`r`n", "`n")
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
        $result[$name] = Normalize-WtLua ([IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8))
    }
    return $result
}

function Compare-WtLuaMaps {
    param([hashtable]$Public, [hashtable]$Dev)
    $errors = @()
    foreach ($name in @($Public.Keys | Sort-Object)) {
        if (-not $Dev.ContainsKey($name)) { $errors += "dev runtime is missing $name"; continue }
        if ($Public[$name] -cne $Dev[$name]) { $errors += "runtime drift in $name" }
    }
    foreach ($name in @($Dev.Keys | Sort-Object)) {
        if (-not $Public.ContainsKey($name)) { $errors += "undocumented dev-only runtime file $name" }
    }
    return $errors
}

function Invoke-SelfTest {
    $public = @{ 'weapon_tweaker.lua' = Normalize-WtLua 'local mod = get_mod("wt"); local MOD_VERSION = "0.12.264-beta"; mod:dofile("scripts/mods/weapon_tweaker/x")' }
    $dev = @{ 'weapon_tweaker.lua' = Normalize-WtLua 'local mod = get_mod("wt_dev"); local MOD_VERSION = "0.12.265-dev"; mod:dofile("scripts/mods/weapon_tweaker_dev/x")' }
    if (@(Compare-WtLuaMaps $public $dev).Count -ne 0) { throw 'documented stream identity differences were rejected' }
    $dev['weapon_tweaker.lua'] += '; behavior_changed = true'
    if (-not (@(Compare-WtLuaMaps $public $dev) -match 'runtime drift')) { throw 'runtime drift was not detected' }
    $dev = $public.Clone(); $dev['dev_only.lua'] = 'return true'
    if (-not (@(Compare-WtLuaMaps $public $dev) -match 'undocumented dev-only')) { throw 'dev-only runtime file was not detected' }
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
if (-not $Quiet) { Write-Host '[check_wt_stream_parity] OK - dev runtime exactly mirrors public beta; only documented stream identity/presentation differs.' -ForegroundColor Green }
exit 0
