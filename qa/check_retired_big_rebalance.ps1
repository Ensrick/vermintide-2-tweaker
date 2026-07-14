# Issue #321: Big Rebalance's shared owner (`bt`) is retired. Keep every old
# consumer surface hidden and unloaded until a separately reviewed replacement
# architecture exists. Historical implementations may remain in long comments.
[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$errors = [System.Collections.Generic.List[string]]::new()

function Active-Lua([string]$relativePath) {
    $text = Get-Content (Join-Path $root $relativePath) -Raw
    # Strip Lua long comments (--[=[ ... ]=]) and ordinary line comments. The
    # retired widget catalogs intentionally remain in long comments as migration
    # history; only executable source is part of this gate.
    $text = [regex]::Replace($text, '(?s)--\[(=*)\[.*?\]\1\]', '')
    # Consume an optional CR before the multiline end anchor. Without it,
    # CRLF files retain every full-line comment and can false-positive on a
    # historical commented-out require.
    return [regex]::Replace($text, '(?m)--[^\r\n]*\r?$', '')
}

$widgetFiles = @(
    @{ Path='weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_data.lua'; Prefix='br_' },
    @{ Path='weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev_data.lua'; Prefix='br_' },
    @{ Path='enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_data.lua'; Prefix='br_' },
    @{ Path='career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua'; Prefix='cbr_' },
    @{ Path='chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker_data.lua'; Prefix='br_' },
    @{ Path='chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua'; Prefix='br_' }
)
foreach ($spec in $widgetFiles) {
    $active = Active-Lua $spec.Path
    if ($active -match ('["'']' + [regex]::Escape($spec.Prefix))) {
        $errors.Add("active retired widget in $($spec.Path) (prefix $($spec.Prefix))")
    }
}

$entrypoints = @(
    'weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua',
    'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua',
    'enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua',
    'enemy_tweaker/scripts/mods/enemy_tweaker/_et_fingerprint.lua',
    'enemy_tweaker/scripts/mods/enemy_tweaker/_et_lifecycle.lua',
    'career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua',
    'chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua',
    'chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua'
)
foreach ($path in $entrypoints) {
    $active = Active-Lua $path
    if ($active -match '(?:dofile|require)\s*\(?[^\r\n]*big_rebalance') {
        $errors.Add("retired Big Rebalance module loaded by $path")
    }
}

foreach ($cfg in @(
    'weapon_tweaker/itemV2.cfg', 'weapon_tweaker_dev/itemV2.cfg',
    'enemy_tweaker/itemV2.cfg', 'career_tweaker/itemV2.cfg',
    'chaos_wastes_tweaker/itemV2.cfg', 'chaos_wastes_tweaker_dev/itemV2.cfg'
)) {
    if ((Get-Content (Join-Path $root $cfg) -Raw) -match '(?i)Big Rebalance') {
        $errors.Add("Workshop description advertises retired Big Rebalance: $cfg")
    }
}

if ($errors.Count -gt 0) {
    Write-Host "[check_retired_big_rebalance] ERRORS ($($errors.Count)):" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) { Write-Host "[check_retired_big_rebalance] OK - BR widgets hidden, modules unloaded, descriptions honest." -ForegroundColor Green }
exit 0
