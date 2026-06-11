# Prepend a CHANGELOG entry for the 2026-05-25 %APPDATA% loc fix + runtime test
# across all 16 mods. Reads MOD_VERSION from <mod>.lua, matches existing style
# (## 0.X.Y vs ## vX.Y.Z) heuristically.
#
# Idempotent? No -- run once after _bump_loc_fix_versions.ps1.

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
$today = "2026-05-25"

foreach ($mod in $mods) {
    $luaPath = Join-Path $repoRoot "$mod/scripts/mods/$mod/$mod.lua"
    $clPath  = Join-Path $repoRoot "$mod/CHANGELOG.md"
    if (-not (Test-Path $luaPath)) { Write-Host "MISS lua  $mod" -ForegroundColor Yellow; continue }
    if (-not (Test-Path $clPath))  { Write-Host "MISS cl   $mod" -ForegroundColor Yellow; continue }

    $lua = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
    $m = [regex]::Match($lua, '(?:local\s+|mod\.)MOD_VERSION\s*=\s*"([^"]+)"')
    if (-not $m.Success) { Write-Host "FAIL ver  $mod" -ForegroundColor Red; continue }
    $ver = $m.Groups[1].Value

    $cl = [System.IO.File]::ReadAllText($clPath, [System.Text.Encoding]::UTF8)

    # Sniff existing version-header style: do prior entries use "## v0.X" or "## 0.X"?
    $usesV = $cl -match '(?m)^##\s+v\d'
    $verHdr = if ($usesV) { "v$ver" } else { $ver }

    $entry = @"
## $verHdr ($today) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal `%APPDATA%`. Lua's `string.format` reads `%A` as a format directive and raises `invalid option '%A' to 'format'`, surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- `${mod}_localization.lua` -- escaped literal `%` in `enable_debug_logging_tooltip` so VMF's tooltip render path sees `%%APPDATA%%` (renders as `%APPDATA%` to the player). Same wording, just escaped.
- `${mod}.lua` -- added `_rt_register("localization_format_safe", ...)` runtime check. dofiles the loc table and `pcall(string.format, value)` on every entry; surfaces any unescaped `%` via `/<mod_id>_regression_test`. Catches the bug class even when the static check (`qa/check_localization.ps1`) is skipped.

### Notes
- Repo-wide multi-layer defense landing in this commit:
  1. Layer 1 (this entry) -- 16 mods' loc strings fixed.
  2. Layer 2 -- `qa/check_localization.ps1` extended to parse `loc.<key> = { en = "..." }` assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
  3. Layer 3 (this entry) -- `_rt_register("localization_format_safe", ...)` runtime check in every mod.
  4. Layer 4 -- `tools/vmb-launcher/CLAUDE.md` doctrine update: "Run `qa/check_localization.ps1` before declaring any localization edit complete."
  5. Layer 5 -- documentation: `LOCALIZATION_STANDARD.md` S 1 "Recurring offender" worked example, `docs/BUG_CLASSES.md` S 16 new entry, `PROJECT_STANDARDS.md` S 3.6 canonical tooltip text now uses `%%APPDATA%%`.
- Static check (`qa/check_localization.ps1`) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build $mod -- verification only. NOT deployed, NOT uploaded.

"@

    if ($DryRun) {
        Write-Host ("DRY  {0,-32} {1} ({2})" -f $mod, $verHdr, $clPath) -ForegroundColor Cyan
    } else {
        # Skip the title line "# <Mod> Changelog" then prepend.
        $lines = $cl -split "`r?`n"
        $titleEnd = 0
        # Find first ## line index.
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s') { $titleEnd = $i; break }
        }
        if ($titleEnd -eq 0) { Write-Host "FAIL no existing ## in $mod CHANGELOG" -ForegroundColor Red; continue }
        $header  = ($lines[0..($titleEnd - 1)] -join "`n").TrimEnd() + "`n`n"
        $rest    = $lines[$titleEnd..($lines.Count - 1)] -join "`n"
        $newCl   = $header + $entry + $rest
        [System.IO.File]::WriteAllText($clPath, $newCl, $utf8NoBom)
        Write-Host ("PREP {0,-32} {1}" -f $mod, $verHdr) -ForegroundColor Green
    }
}
