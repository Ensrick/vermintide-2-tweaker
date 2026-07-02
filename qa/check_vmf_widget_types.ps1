# check_vmf_widget_types.ps1 — static scan for invalid VMF widget `type`
# values AND malformed numeric `range` fields in active-mod `*_data.lua` files.
#
# Bug class: VMF's options init (`new_mod`'s `mod_data`) does a strict
# whitelist match on `widget.type`. The canonical type set as of VMF current
# is:
#     group / header / checkbox / dropdown / numeric / keybind
#
# Anything outside this set fails widget validation at mod-load time. VMF
# prints an in-chat error like
#     [MOD][<mod>][ERROR] [VMF Mod Manager] (new_mod) mod options
#     initialization: could not initialize mod's options. ...
# and the mod's ENTIRE options page disappears (not just the offending
# widget). Runtime `mod:get(setting_id)` reads still work, so the user has
# no UI to change settings but the mod itself loads — silent UI death.
#
# SECOND bug class (added 2026-06-29): a `numeric` widget's `range` field must
# be an array of EXACTLY 2 elements `{ min, max }`. A 3-element range — e.g.
# the `{ 0, 3000, 25 }` "step hint" attempt — is NOT silently ignored by VMF;
# it fails the SAME options-init validation with
#     [widget "<id>" (numeric)]: 'range' field must contain an array-like
#     table with 2 elements
# and kills the entire mod's options registration (no `[<mod>:LOAD]`, every
# tweak gone). Burned ct_dev v0.7.188-dev (`starting_coins` range `{0,3000,25}`,
# #164) — the mod was completely dead until v0.7.189-dev reverted it. A numeric
# "step" CANNOT be carried in range[3]; snap in `on_setting_changed` instead.
#
# Burned 2026-05-25: gt v0.2.60-dev shipped with widget #103
# `type = "text_input"` (a non-VMF type the author assumed worked because
# DMF has it), broke gt's entire options menu init on the user's machine.
# The fix is to either pick a valid type or — for genuinely-missing types
# like free-text input — drive the setting via a chat command and store it
# via `mod:set(setting_id, value)` without a widget. See gt's MOTD text
# handling in `general_tweaker_data.lua` for the canonical "no widget, chat
# command instead" pattern.
#
# Detection:
#   - Greps `*_data.lua` files under each active mod's
#     `<mod>/scripts/mods/<mod>/` directory.
#   - Skips `_archive/`, `tweaker/` (legacy SDK), `bundleV2/`, `.build/`,
#     `.temp/`, `_test_fixtures/`, `Vermintide-2-*` / `Darktide-*` reference
#     clones, `_*_extract/` snapshots.
#   - For each `type = "<X>"` occurrence in the code part of each line
#     (single-line `--` comment tails are stripped first), validates `<X>`
#     against the canonical VMF whitelist.
#   - Any non-canonical type is flagged as a hard ERROR. There is NO
#     suppression pragma — invalid widget types are NEVER acceptable.
#
# Output mirrors `qa/check_unpack_safety.ps1`.
#
# Exit codes:
#   0 - all widget types are valid VMF
#   2 - one or more invalid types found (hard fail — no exit 1 / warning tier)
#
# Self-test: pass `-SelfTest` to run the synthetic fixtures under
# `qa/_test_fixtures/widget_type_*.lua` and assert ERROR / PASS verdicts.
# Self-test exit 0 means the check itself is wired correctly; exit 2 means
# a regex / heuristic regression in this script.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path

# ---- canonical VMF widget type whitelist ----
# Verified against VMF source patterns + every active mod's `*_data.lua` in
# this repo. If a future VMF release adds a new type, append it here AND
# update VMF_RECIPES.md "VMF widget type whitelist" section in the same
# commit.
$ValidWidgetTypes = @(
    'group',
    'header',
    'checkbox',
    'dropdown',
    'numeric',
    'keybind'
)
$ValidSet = @{}
foreach ($t in $ValidWidgetTypes) { $ValidSet[$t] = $true }
$ValidTypesDisplay = ($ValidWidgetTypes -join '/')

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# Pre-compiled regex. We don't try to be a full Lua parser; just match
# `type = "<word>"` on the code part of each line. False positives on
# unrelated `type = "foo"` strings outside widget tables are accepted as
# the cost of staying ripgrep-spirited — in practice `_data.lua` files
# only define widget trees, so every `type =` field is a widget type.
$rxWidgetType = [regex]'\btype\s*=\s*"([A-Za-z0-9_]+)"'

# Single-line `range = { ... }` capture. `range` is a numeric-widget-only
# field and MUST hold exactly 2 elements. We count top-level comma-separated
# items inside the braces; the data files always write ranges on one line as
# simple `{ num, num }` literals, so a naive comma split is exact here.
# Multi-line range tables aren't used in these files (and would be unusual);
# we only validate single-line ranges, consistent with this script's
# line-oriented philosophy.
$rxRange = [regex]'\brange\s*=\s*\{([^}]*)\}'

# ---- file collection ----
function Get-ScanFiles {
    param([string]$Root)
    # Active mods follow `<mod>/scripts/mods/<mod>/<mod>_data.lua`. Scope
    # to that suffix to skip everything else (vanilla source dumps, the
    # legacy `tweaker/` SDK mod, archived snapshots, the bundleV2 build
    # output, etc.).
    #
    # NOTE on path exclusions: the repo root itself is `vermintide-2-tweaker`,
    # which contains the substring `vermintide-2-`. We can't use a blanket
    # `*\Vermintide-2-*` glob (case-insensitive) to skip the upstream source
    # clone because that would also match every file under the active repo.
    # Use the specific upstream folder names instead.
    Get-ChildItem -Path $Root -Filter "*_data.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $isUnderMod = $p -match "\\scripts\\mods\\"
            $notExcluded = $p -notlike "*\_archive\*" `
                       -and $p -notlike "*\bundleV2\*" `
                       -and $p -notlike "*\.build\*" `
                       -and $p -notlike "*\.temp\*" `
                       -and $p -notlike "*\_tmp\*" `
                       -and $p -notlike "*\.spawn_tweaks_ref\*" `
                       -and $p -notlike "*\tweaker\*" `
                       -and $p -notlike "*\_test_fixtures\*" `
                       -and $p -notlike "*\sample_*\*" `
                       -and $p -notlike "*\Vermintide-2-Source-Code\*" `
                       -and $p -notlike "*\Darktide-Source-Code\*" `
                       -and $p -notlike "*\_*_extract\*"
            return $isUnderMod -and $notExcluded
        }
}

# ---- per-file scan ----
# Returns an array of error rows: @{ File; Line; Type; Text }
function Scan-File {
    param([string]$Path)
    $errors = @()
    try {
        $text = Read-FileUtf8 $Path
    } catch {
        throw "I/O failure reading ${Path}: $_"
    }

    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Strip the trailing line comment so `type = "..."` appearing in a
        # doc comment doesn't trip the check (e.g. the warning comment we
        # left in gt's data file at the site of the original burn).
        # Naive split — we accept false positives in long-bracket strings
        # since `_data.lua` files don't use them.
        $codePart = $line
        $commentIdx = $line.IndexOf('--')
        if ($commentIdx -ge 0) { $codePart = $line.Substring(0, $commentIdx) }

        # --- 1) invalid widget type ---
        $matches = $rxWidgetType.Matches($codePart)
        foreach ($m in $matches) {
            $typeName = $m.Groups[1].Value
            if (-not $ValidSet.ContainsKey($typeName)) {
                $errors += [pscustomobject]@{
                    Kind = "type"
                    File = $Path
                    Line = $i + 1
                    Type = $typeName
                    Text = $line.Trim()
                }
            }
        }

        # --- 2) malformed numeric `range` (must be exactly 2 elements) ---
        $rangeMatches = $rxRange.Matches($codePart)
        foreach ($rm in $rangeMatches) {
            $inner = $rm.Groups[1].Value.Trim()
            if ($inner -eq "") { continue }   # `range = {}` — not our class; leave to runtime
            # Count top-level comma-separated elements (range literals are flat).
            $elems = @($inner -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
            if ($elems.Count -ne 2) {
                $errors += [pscustomobject]@{
                    Kind  = "range"
                    File  = $Path
                    Line  = $i + 1
                    Type  = "range[$($elems.Count)]"
                    Text  = $line.Trim()
                }
            }
        }
    }
    return ,$errors
}

# ---- self-test ----
# Drives the synthetic fixtures under `qa/_test_fixtures/widget_type_*.lua`
# and asserts a specific verdict per fixture. Run with `-SelfTest`; bypasses
# the normal scan. Exit 0 = self-test passed, 2 = self-test failed
# (regex / heuristic regression).
function Invoke-SelfTest {
    $fixDir = Join-Path $PSScriptRoot "_test_fixtures"
    if (-not (Test-Path $fixDir)) {
        Write-Host "[check_vmf_widget_types -SelfTest] FAIL: $fixDir does not exist." -ForegroundColor Red
        return 2
    }

    $cases = @(
        @{ Path = "widget_type_bad.lua";  ExpectedError = $true;  Desc = "type=`"text_input`" (invalid VMF type)" },
        @{ Path = "widget_type_good.lua"; ExpectedError = $false; Desc = "valid types + valid 2-element range" },
        @{ Path = "widget_range_bad.lua"; ExpectedError = $true;  Desc = "numeric range { 0, 3000, 25 } (3 elements — fatal)" }
    )

    $allPass = $true
    foreach ($c in $cases) {
        $f = Join-Path $fixDir $c.Path
        if (-not (Test-Path $f)) {
            Write-Host "  X $($c.Path): missing fixture file" -ForegroundColor Red
            $allPass = $false
            continue
        }
        $e = Scan-File -Path $f
        $gotError = ($e.Count -gt 0)
        $verdict = if ($gotError -eq $c.ExpectedError) { "PASS" } else { "FAIL" }
        $colour = if ($verdict -eq "PASS") { "Green" } else { "Red" }
        Write-Host "  [$verdict] $($c.Path) -- $($c.Desc) (error=$gotError, expected=$($c.ExpectedError))" -ForegroundColor $colour
        if ($verdict -eq "FAIL") { $allPass = $false }
    }

    Write-Host ""
    if ($allPass) {
        Write-Host "[check_vmf_widget_types -SelfTest] OK -- all $($cases.Count) fixture verdicts match." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[check_vmf_widget_types -SelfTest] FAILED -- regex / heuristic regression. Inspect fixtures + Scan-File." -ForegroundColor Red
        return 2
    }
}

# ---- main ----
Write-Host "=== check_vmf_widget_types ===" -ForegroundColor Cyan

if ($SelfTest) {
    $code = Invoke-SelfTest
    exit $code
}

$allErrors = @()
$hardError = $false

$files = @(Get-ScanFiles -Root $repoRoot)
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
    # Extract mod id from the path `<mod>/scripts/mods/<mod>/<mod>_data.lua`.
    $modId = "?"
    if ($rel -match '^([^\\/]+)[\\/]scripts[\\/]mods[\\/]') {
        $modId = $Matches[1]
    }
    if (-not $Quiet) { Write-Host "Checking $modId data file ($rel)" -ForegroundColor DarkGray }
    try {
        $rows = Scan-File -Path $f.FullName
    } catch {
        Write-Host ("  X {0}: {1}" -f $rel, $_) -ForegroundColor Red
        $hardError = $true
        continue
    }
    if ($rows.Count -gt 0) {
        foreach ($r in $rows) { $allErrors += $r }
    }
}

Write-Host ""
if ($hardError) {
    Write-Host "[check_vmf_widget_types] ERROR -- one or more files failed to scan." -ForegroundColor Red
    exit 2
}

if ($allErrors.Count -eq 0) {
    Write-Host "[check_vmf_widget_types] OK -- all widget types are valid VMF; all numeric ranges have 2 elements." -ForegroundColor Green
    exit 0
}

Write-Host "[check_vmf_widget_types] ERRORS: $($allErrors.Count)" -ForegroundColor Red
foreach ($e in $allErrors) {
    $rel = $e.File
    if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
    if ($e.Kind -eq "range") {
        Write-Host ("  X {0}:{1} -- numeric 'range' has {2} elements; VMF requires EXACTLY 2 {{ min, max }} (a step in range[3] is fatal, not ignored)" -f $rel, $e.Line, $e.Type) -ForegroundColor Red
    } else {
        Write-Host ("  X {0}:{1} -- invalid type '{2}' (valid: {3})" -f $rel, $e.Line, $e.Type, $ValidTypesDisplay) -ForegroundColor Red
    }
    Write-Host ("      $($e.Text)") -ForegroundColor DarkRed
}
exit 2
