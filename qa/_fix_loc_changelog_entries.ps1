# Repair broken CHANGELOG entries from _prepend_loc_fix_changelog.ps1.
# The here-string had backtick / curly-brace substitution bugs:
#   - `tools  -> TAB+ools
#   - `enable -> TAB+nable (rendered as ESC+nable in some places)
#   - ${mod}  -> literal text (failed substitution)
# This script rewrites the broken section in each CHANGELOG with a clean
# version using the correct mod name and current MOD_VERSION.
#
# Idempotent: only rewrites when the broken markers are present.

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
    $clPath  = Join-Path $repoRoot "$mod/CHANGELOG.md"
    if (-not (Test-Path $clPath)) { continue }

    $lua = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
    $verM = [regex]::Match($lua, '(?:local\s+|mod\.)MOD_VERSION\s*=\s*"([^"]+)"')
    if (-not $verM.Success) { Write-Host "FAIL ver $mod" -ForegroundColor Red; continue }
    $ver = $verM.Groups[1].Value

    $cl = [System.IO.File]::ReadAllText($clPath, [System.Text.Encoding]::UTF8)

    # Sniff version-header style: prior entries use "## v0.X" or "## 0.X"?
    # Skip OUR entry (it has the standard label) when sniffing; look at the next
    # entry below us. Heuristic: count both styles, pick majority.
    $vCount = ([regex]::Matches($cl, '(?m)^##\s+v\d')).Count
    $plainCount = ([regex]::Matches($cl, '(?m)^##\s+\d')).Count
    $usesV = $vCount -gt $plainCount
    $verHdr = if ($usesV) { "v$ver" } else { $ver }

    # Find the broken entry. Anchor: the "${mod}_localization.lua" literal that
    # only appears in the broken entry (since we'd never write that intentionally).
    $brokenAnchor = '${mod}_localization.lua'
    if (-not $cl.Contains($brokenAnchor)) {
        Write-Host "SKIP $mod -- no broken entry detected (already fixed?)" -ForegroundColor DarkGray
        continue
    }

    # Locate the broken entry boundaries. The entry starts at the "## <ver>-..."
    # header that precedes the broken anchor; ends at the NEXT "## " header.
    $anchorIdx = $cl.IndexOf($brokenAnchor)
    # Find the "## " header preceding the anchor.
    $headersBefore = [regex]::Matches($cl.Substring(0, $anchorIdx), '(?m)^##\s+\S.*$')
    if ($headersBefore.Count -eq 0) { Write-Host "FAIL header-before $mod" -ForegroundColor Red; continue }
    $entryStart = $headersBefore[$headersBefore.Count - 1].Index
    # Find the NEXT "## " after the anchor.
    $afterAnchor = $cl.Substring($anchorIdx)
    $nextHeader = [regex]::Match($afterAnchor, '(?m)^##\s+\S.*$')
    if (-not $nextHeader.Success) { Write-Host "FAIL header-after $mod" -ForegroundColor Red; continue }
    $entryEnd = $anchorIdx + $nextHeader.Index

    $newEntry = "## $verHdr (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test`n`n"
    $newEntry += "### Why`n"
    $newEntry += "User report: ""invalid string format on mouseover for Debug Logging"" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).`n`n"
    $newEntry += "### Changed`n"
    $newEntry += "- ${mod}_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.`n"
    $newEntry += "- ${mod}.lua -- added _rt_register(""localization_format_safe"", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.`n`n"
    $newEntry += "### Notes`n"
    $newEntry += "Repo-wide multi-layer defense landing across all 16 mods in this sweep:`n`n"
    $newEntry += "1. Layer 1 -- 16 mods' loc strings fixed.`n"
    $newEntry += "2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = ""..."" } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).`n"
    $newEntry += "3. Layer 3 -- _rt_register(""localization_format_safe"", ...) runtime check in every mod.`n"
    $newEntry += "4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: ""Run qa/check_localization.ps1 before declaring any localization edit complete.""`n"
    $newEntry += "5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 ""Recurring offender"" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.`n`n"
    $newEntry += "Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).`n`n"
    $newEntry += "### Build`n"
    $newEntry += "VMBLauncher.exe build $mod -- verification only. NOT deployed, NOT uploaded.`n`n"

    $newCl = $cl.Substring(0, $entryStart) + $newEntry + $cl.Substring($entryEnd)

    if ($DryRun) {
        Write-Host ("DRY  {0,-32} {1} (entry chars {2}..{3})" -f $mod, $verHdr, $entryStart, $entryEnd) -ForegroundColor Cyan
    } else {
        [System.IO.File]::WriteAllText($clPath, $newCl, $utf8NoBom)
        Write-Host ("FIX  {0,-32} {1}" -f $mod, $verHdr) -ForegroundColor Green
    }
}
