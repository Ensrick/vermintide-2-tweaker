# check_level_lookup_budget.ps1
# Blocks CT adventure-catalog growth that would exceed VT2's fixed
# weight_array network capacity before a build can be published (issue #590).

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$sourcePath = Join-Path $repoRoot 'chaos_wastes_tweaker_dev\scripts\mods\chaos_wastes_tweaker_dev\_adventure_pool.lua'

# Source/build facts for the 2026-03-25 yearly-events executable. The startup
# log captures 582 entries before CT mutates NetworkLookup.level_keys; the
# engine's global.network_config weight_array max_size is 1024. Update the
# baseline when a game update changes CT's `Lobby hash shim installed` count.
$vanillaLevelKeys = 582
$weightArrayMaxSize = 1024

if (-not (Test-Path -LiteralPath $sourcePath)) {
    Write-Host "[check_level_lookup_budget] ERROR - missing $sourcePath" -ForegroundColor Red
    exit 2
}

$source = [System.IO.File]::ReadAllText($sourcePath, [System.Text.Encoding]::UTF8)
$campaign = [regex]::Match($source, '(?s)_M\.MISSION_GROUPS\s*=\s*\{(.*?)\r?\n\}\r?\n\r?\n-- Annual')
$events = [regex]::Match($source, '(?s)_M\.EVENT_MISSIONS\s*=\s*\{(.*?)\r?\n\}\r?\n\r?\n_M\.ADVENTURE_SETTING_PREFIX')
$themes = [regex]::Match($source, 'local\s+ALL_THEMES\s*=\s*\{([^\r\n]+)\}')

if (-not $campaign.Success -or -not $events.Success -or -not $themes.Success) {
    Write-Host '[check_level_lookup_budget] ERROR - could not parse CT mission/theme catalogs.' -ForegroundColor Red
    exit 2
}

$missionPattern = '\{\s*key\s*=\s*"[^\"]+"'
$missionCount = [regex]::Matches($campaign.Groups[1].Value, $missionPattern).Count +
    [regex]::Matches($events.Groups[1].Value, $missionPattern).Count
$themeCount = [regex]::Matches($themes.Groups[1].Value, '"[^\"]+"').Count
$projected = $vanillaLevelKeys + ($missionCount * $themeCount)
$errors = [System.Collections.Generic.List[string]]::new()

if ($missionCount -le 0 -or $themeCount -le 0) {
    $errors.Add("invalid parsed counts: missions=$missionCount themes=$themeCount")
}
if ($projected -gt $weightArrayMaxSize) {
    $errors.Add("static catalog projects $projected level keys, above weight_array max_size $weightArrayMaxSize")
}

# Pool-floor duplicates are graph choices, not real levels. They must collapse
# through vanilla LEVEL_ALIAS and must never consume NetworkLookup/LevelSettings
# entries of their own. This is what turned the crashing 1,026 count into 792.
if ($source -notmatch 'config\.LEVEL_ALIAS\[alias_perm\]\s*=\s*original_perm') {
    $errors.Add('duplicate permutations are not mapped through config.LEVEL_ALIAS')
}
if ($source -match 'register_network_lookup_key\s*\(\s*alias_perm\s*\)') {
    $errors.Add('duplicate alias permutations are still registered in NetworkLookup.level_keys')
}
if ($source -match 'LevelSettings\s*\[\s*alias_perm\s*\]\s*=') {
    $errors.Add('duplicate alias permutations are still cloned into LevelSettings')
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) {
        Write-Host "[check_level_lookup_budget] ERROR - $message" -ForegroundColor Red
    }
    exit 2
}

if (-not $Quiet) {
    $headroom = $weightArrayMaxSize - $projected
    Write-Host "[check_level_lookup_budget] OK - $vanillaLevelKeys vanilla + $missionCount missions x $themeCount themes = $projected/$weightArrayMaxSize ($headroom headroom); duplicate aliases cost 0 keys."
}
exit 0
