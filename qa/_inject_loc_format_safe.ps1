# One-shot helper to inject the localization_format_safe _rt_register check into
# every active mod's main lua file. Layer 3 of the 2026-05-25 %APPDATA% bug fix.
#
# Idempotent: skips files that already contain "localization_format_safe".
# Run from repo root: pwsh -NoProfile -File qa/_inject_loc_format_safe.ps1

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

function New-Snippet([string]$modDir) {
    return @"

_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/$modDir/$($modDir)_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)
"@
}

foreach ($mod in $mods) {
    $luaPath = Join-Path $repoRoot "$mod/scripts/mods/$mod/$mod.lua"
    if (-not (Test-Path $luaPath)) {
        Write-Host "MISS  $mod -- no main lua at $luaPath" -ForegroundColor Yellow
        continue
    }
    $text = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
    if ($text -match 'localization_format_safe') {
        Write-Host "SKIP  $mod -- already has localization_format_safe" -ForegroundColor DarkGray
        continue
    }

    # Find ALL "_rt_register(" call start lines, then the matching "end)" that
    # closes the LAST one. Anchor on regex within the file content.
    $rtMatches = [regex]::Matches($text, '(?m)^_rt_register\(')
    if ($rtMatches.Count -eq 0) {
        Write-Host "MISS  $mod -- no _rt_register calls found" -ForegroundColor Yellow
        continue
    }
    $lastRtStart = $rtMatches[$rtMatches.Count - 1].Index
    # From the last _rt_register start, find the next "^end)$" (a line that is
    # just "end)" optionally with trailing whitespace) -- that closes the call.
    $tail = $text.Substring($lastRtStart)
    $endMatch = [regex]::Match($tail, '(?m)^end\)\s*$')
    if (-not $endMatch.Success) {
        Write-Host "FAIL  $mod -- could not locate closing 'end)' for last _rt_register" -ForegroundColor Red
        continue
    }
    # Absolute index of the end-of-line for that "end)" line.
    $endLineEnd = $lastRtStart + $endMatch.Index + $endMatch.Length

    $snippet = New-Snippet $mod
    # Inject right after the closing "end)" line.
    $newText = $text.Substring(0, $endLineEnd) + "`n" + $snippet + $text.Substring($endLineEnd)

    if ($DryRun) {
        Write-Host "DRY   $mod -- would insert at offset $endLineEnd" -ForegroundColor Cyan
    } else {
        [System.IO.File]::WriteAllText($luaPath, $newText, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "WROTE $mod -- inserted localization_format_safe" -ForegroundColor Green
    }
}
