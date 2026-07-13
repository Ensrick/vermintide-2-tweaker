# check_localization.ps1 — validates VMF localization tables across all mods.
# Catches: unescaped %, referenced-but-undefined keys, missing mod_description.
#
# See qa/CHECKS.md rows 2, 17, 18, 19.
#
# Exit codes: 0 = pass, 1 = warnings only, 2 = errors found.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot ".." }
$repoRoot = (Resolve-Path $RepoRoot).Path
$errors = @()
$warnings = @()

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Find-LocFiles {
    Get-ChildItem -Path $repoRoot -Filter "*_localization.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $p -notlike "*\_archive\*" -and $p -notlike "*\bundleV2\*" -and $p -notlike "*\.build\*" `
                -and $p -notlike "*\.temp\*" -and $p -notlike "*\.spawn_tweaks_ref\*" `
                -and $p -notlike "*\tweaker\*" -and $p -notlike "*\sample_*\*"
        }
}

function Find-DataFiles {
    Get-ChildItem -Path $repoRoot -Filter "*_data.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $p -notlike "*\_archive\*" -and $p -notlike "*\bundleV2\*" -and $p -notlike "*\.build\*" `
                -and $p -notlike "*\.temp\*" -and $p -notlike "*\.spawn_tweaks_ref\*" `
                -and $p -notlike "*\tweaker\*" -and $p -notlike "*\sample_*\*"
        }
}

function Get-ModDirForFile([string]$filePath) {
    # File is at <repo>/<mod>/scripts/mods/<mod>/<mod>_localization.lua
    # Walk up 3 levels to <mod>
    $dir = Split-Path $filePath -Parent
    for ($i = 0; $i -lt 3; $i++) { $dir = Split-Path $dir -Parent }
    return $dir
}

# Parse a localization.lua file into a hashtable of { key = string-value }.
# Lenient parser. Two patterns common in this repo:
#   key = { en = "value" }       -- standard VMF
#   key = en("value")            -- helper-function style (event_tweaker)
function Parse-LocFile([string]$path) {
    $text = Read-FileUtf8 $path
    $result = @{}

    # Pattern 1: key = { en = "value" }
    $regex1 = '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"\s*[,}]'
    foreach ($m in [regex]::Matches($text, $regex1)) {
        $result[$m.Groups[1].Value] = $m.Groups[2].Value
    }

    # Pattern 2: key = en("value")
    $regex2 = '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*en\s*\(\s*"((?:[^"\\]|\\.)*)"\s*\)'
    foreach ($m in [regex]::Matches($text, $regex2)) {
        $result[$m.Groups[1].Value] = $m.Groups[2].Value
    }

    # Pattern 3: loc.<key> = { en = "value" }   -- chaos_wastes_tweaker assignment style
    $regex3 = '(?m)^\s*loc\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"\s*[,}]'
    foreach ($m in [regex]::Matches($text, $regex3)) {
        $result[$m.Groups[1].Value] = $m.Groups[2].Value
    }

    return $result
}

# Parse a data.lua file to find all `setting_id`, `tooltip`, `category_id` references.
function Parse-DataFile([string]$path) {
    $text = Read-FileUtf8 $path
    $refs = @{}
    # Match: setting_id = "foo", tooltip = "foo_tooltip", category_id = "foo"
    $patterns = @(
        'setting_id\s*=\s*"([^"]+)"',
        'tooltip\s*=\s*"([^"]+)"',
        'category_id\s*=\s*"([^"]+)"'
    )
    foreach ($p in $patterns) {
        foreach ($m in [regex]::Matches($text, $p)) {
            $refs[$m.Groups[1].Value] = $true
        }
    }
    return $refs
}

# Bug #2: detect unescaped % in localization values. VMF's mod:localize runs EVERY
# string through string.format (safe_string_format, vmf/modules/core/localization.lua),
# so a literal % must be doubled to %%. A lone % that does NOT start a valid Lua format
# directive (e.g. "% C", "5%", "100% done") raises "invalid option to 'format'", which
# breaks the VMF options view / shows a red error tooltip. Runtime twin: the
# `localization_format_safe` regression test (/gt_regression_test).
#
# Rule: flag any % that is neither `%%` nor the start of a valid directive
# (optional flags/width/precision + a conversion char). The previous version wrongly
# treated "% " (percent-space) as safe and let gt ship
# gt_adventure_save_trait_chance = "...Grenadier % Chance" -> crash (2026-06-30).
function Find-UnescapedPercent([hashtable]$loc, [string]$file) {
    $bad = @()
    # A valid single directive after '%': optional flags/width/precision + conversion char.
    $directive = '[-+ #0]*[0-9]*(?:\.[0-9]+)?[diouxXeEfgGqscaA]'
    foreach ($k in $loc.Keys) {
        $v = $loc[$k]
        # Strip escaped literals (%%) FIRST, then any remaining % must start a valid
        # directive -- otherwise it's a lone/misplaced % that string.format rejects.
        # (Evaluating each % independently would wrongly flag the 2nd % of a valid %%.)
        $stripped = $v -replace '%%', ''
        # A percent immediately after a digit is a literal percentage in our loc
        # surface, even when the following word begins with a conversion letter.
        # Without this first branch, "10% chance" is misread as the directive
        # "% c" because space is a legal numeric flag and c is a conversion.
        # Use Regex.IsMatch for case-sensitive conversion matching. PowerShell's
        # -match is case-insensitive and would accept invalid "% C" as "% c".
        if ($stripped -match '\d%' -or [regex]::IsMatch($stripped, ('%(?!' + $directive + ')'))) {
            $bad += "$($file): key '$k' has an unescaped % (double it to %%): '$v'"
        }
    }
    return $bad
}

function Invoke-SelfTest {
    $fixtures = @{
        literal_after_digit = '10% chance'
        literal_word        = 'Grenadier % Chance'
        escaped_literal     = '10%% chance'
        formatted_percent   = 'Chance: %d%%'
        formatted_string    = 'Career: %s'
    }
    $bad = @(Find-UnescapedPercent $fixtures '<fixture>')
    function Assert([bool]$condition, [string]$description) {
        $verdict = if ($condition) { 'PASS' } else { 'FAIL' }
        $colour = if ($condition) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $description) -ForegroundColor $colour
        if (-not $condition) { $script:LocalizationSelfTestPass = $false }
    }

    $script:LocalizationSelfTestPass = $true
    Assert (($bad | Where-Object { $_ -match "key 'literal_after_digit'" }).Count -eq 1) 'detects planted 10% chance case (issue #346)'
    Assert (($bad | Where-Object { $_ -match "key 'literal_word'" }).Count -eq 1) 'detects percent-space literal'
    Assert (($bad | Where-Object { $_ -match "key 'escaped_literal'" }).Count -eq 0) 'accepts escaped literal percent'
    Assert (($bad | Where-Object { $_ -match "key 'formatted_percent'" }).Count -eq 0) 'accepts directive plus escaped percent'
    Assert (($bad | Where-Object { $_ -match "key 'formatted_string'" }).Count -eq 0) 'accepts string directive'
    Assert ($bad.Count -eq 2) 'reports only the two unsafe fixtures'

    if ($script:LocalizationSelfTestPass) {
        Write-Host "[check_localization -SelfTest] OK -- percent detection intact." -ForegroundColor Green
        return 0
    }
    Write-Host "[check_localization -SelfTest] FAILED -- percent detection regression." -ForegroundColor Red
    return 2
}

if ($SelfTest) { exit (Invoke-SelfTest) }

# Group by mod
$modFiles = @{}
foreach ($locFile in Find-LocFiles) {
    $modDir = Get-ModDirForFile $locFile.FullName
    $modName = Split-Path $modDir -Leaf
    if (-not $modFiles.ContainsKey($modName)) { $modFiles[$modName] = @{ loc = $null; data = $null } }
    $modFiles[$modName].loc = $locFile.FullName
}
foreach ($dataFile in Find-DataFiles) {
    $modDir = Get-ModDirForFile $dataFile.FullName
    $modName = Split-Path $modDir -Leaf
    if (-not $modFiles.ContainsKey($modName)) { $modFiles[$modName] = @{ loc = $null; data = $null } }
    $modFiles[$modName].data = $dataFile.FullName
}

foreach ($modName in $modFiles.Keys | Sort-Object) {
    $entry = $modFiles[$modName]
    if (-not $Quiet) { Write-Host "Checking $modName localization" -ForegroundColor DarkGray }

    if (-not $entry.loc) {
        $warnings += "${modName}: no localization file (*_localization.lua) found"
        continue
    }
    if (-not $entry.data) {
        $warnings += "${modName}: no data file (*_data.lua) found -- can't cross-reference"
        # Still check for unescaped %
        $loc = Parse-LocFile $entry.loc
        $errors += (Find-UnescapedPercent $loc $entry.loc)
        continue
    }

    $loc = Parse-LocFile $entry.loc
    $data = Parse-DataFile $entry.data

    # Row #19: required key mod_description
    if (-not $loc.ContainsKey("mod_description")) {
        $warnings += "${modName}: missing required loc key 'mod_description'"
    }

    # Row #2: unescaped %
    $errors += (Find-UnescapedPercent $loc $entry.loc)

    # Row #17: referenced-but-undefined keys
    # data refs a key X, loc must define X (and optionally X_tooltip, X_description)
    foreach ($key in $data.Keys) {
        if (-not $loc.ContainsKey($key)) {
            # Skip keys that look like values, not loc references
            # (e.g. setting_id values that are setting ids, not display strings)
            # Loc keys for VMF setting_id are auto-resolved by VMF (it expects key to be defined).
            $warnings += "${modName}: data.lua references '$key' but no loc entry"
        }
    }
}

# Report
Write-Host ""
if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "[check_localization] OK -- all mod localization tables are consistent." -ForegroundColor Green
    exit 0
}

if ($warnings.Count -gt 0) {
    Write-Host "[check_localization] WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
    foreach ($w in $warnings | Select-Object -First 50) { Write-Host "  ! $w" -ForegroundColor Yellow }
    if ($warnings.Count -gt 50) { Write-Host "  ... ($($warnings.Count - 50) more)" -ForegroundColor Yellow }
}
if ($errors.Count -gt 0) {
    Write-Host "[check_localization] ERRORS ($($errors.Count)):" -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "  X $e" -ForegroundColor Red }
    exit 2
}
exit 1
