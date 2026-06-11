# Bump PATCH segment of MOD_VERSION across all 16 mods for the 2026-05-25
# %APPDATA% loc fix + localization_format_safe runtime test landing.
#
# Idempotent? No -- bumps EVERY time. Run once.
#
# Per PROJECT_STANDARDS: 3-segment semver, bump PATCH, preserve -dev/-alpha suffix.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path

$mods = @(
    "buff_tweaker", "career_tweaker", "chaos_wastes_tweaker",
    "character_weapon_variants", "cosmetics_tweaker", "crafting_in_modded",
    "dynamic_cosmetic_portraits", "enemy_tweaker", "event_tweaker",
    "general_tweaker", "gui_tweaker", "lobby_tweaker",
    "modded_progression", "verminious_dreams_lighting", "weapon_tweaker"
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($mod in $mods) {
    $luaPath = Join-Path $repoRoot "$mod/scripts/mods/$mod/$mod.lua"
    if (-not (Test-Path $luaPath)) {
        Write-Host "MISS $mod" -ForegroundColor Yellow
        continue
    }
    $text = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)

    # Match either: local MOD_VERSION = "X.Y.Z[-track]"   or   mod.MOD_VERSION = "X.Y.Z[-track]"
    $pattern = '((?:local\s+|mod\.)MOD_VERSION\s*=\s*")(\d+)\.(\d+)\.(\d+)((?:-[A-Za-z0-9_]+)?)(")'
    $m = [regex]::Match($text, $pattern)
    if (-not $m.Success) {
        Write-Host "FAIL $mod -- no MOD_VERSION assignment found" -ForegroundColor Red
        continue
    }
    $prefix  = $m.Groups[1].Value
    $major   = [int]$m.Groups[2].Value
    $minor   = [int]$m.Groups[3].Value
    $patch   = [int]$m.Groups[4].Value
    $track   = $m.Groups[5].Value
    $newPatch = $patch + 1
    $oldVer = "$major.$minor.$patch$track"
    $newVer = "$major.$minor.$newPatch$track"
    $newText = $text.Substring(0, $m.Index) + $prefix + "$major.$minor.$newPatch$track" + '"' + $text.Substring($m.Index + $m.Length)

    if ($DryRun) {
        Write-Host ("DRY  {0,-32} {1} -> {2}" -f $mod, $oldVer, $newVer) -ForegroundColor Cyan
    } else {
        [System.IO.File]::WriteAllText($luaPath, $newText, $utf8NoBom)
        Write-Host ("BUMP {0,-32} {1} -> {2}" -f $mod, $oldVer, $newVer) -ForegroundColor Green
    }
}
