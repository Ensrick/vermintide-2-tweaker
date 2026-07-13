# check_promotion.ps1 - BLOCKING dev-to-stable promotion gate (issue #327).
#
# Doctrine: docs/PROMOTION_PROCESS.md + LOCALIZATION_STANDARD.md section 13.5.
# Both 2026-07-04-era promotions each leaked a different checklist step to
# PUBLIC subscribers (stable cim shipped 7 [untested] loc tags; stable ct went
# out suffixed 0.7.130-beta without a named clean version). The advisory scans
# (check_loc_tags.ps1) had warned for weeks without forcing the fix - promotion
# needs a RED gate. ship.ps1 invokes this check BLOCKING whenever the shipped
# mod is one of the five STABLE split dirs.
#
# Checks (all hard failures):
#   (a) TAG LEAK      - any sanctioned dev status tag (section 13.1 vocabulary)
#                       leading an authored en-string in the stable dir's
#                       *_localization.lua. Stable never carries dev tags
#                       (section 13.5 strip step; CLAUDE.md non-negotiable 11).
#   (b) SUFFIX        - stable MOD_VERSION carries a pre-release suffix.
#                       OVERRIDE: a user-NAMED suffixed public version is
#                       legitimate (issue #328 ruling, e.g. ct 0.7.130-beta
#                       public beta) - ship it with $env:VT2_SUFFIX_OK = '1'.
#   (c) MONOTONIC     - stable MOD_VERSION must equal the top CHANGELOG entry
#                       version (catches a forgotten bump/entry) and the top
#                       entry must be strictly greater than the previous one
#                       (catches a version that did not increase over the last
#                       shipped stable).
#
# Not this gate's job: crash fixes stranded in dev (promotion-status.ps1
# -Strict), dev-identity strings in stable source (promote.ps1's post-port
# grep), cfg id collisions (check_published_ids.ps1).
#
# Exit codes: 0 = pass / not applicable; 1 = gate FAILED (blocks the ship);
#             2 = self-test regression.
#
# Usage:
#   pwsh qa/check_promotion.ps1 -Mod crafting_in_modded
#   pwsh qa/check_promotion.ps1 -SelfTest

[CmdletBinding()]
param(
    # Stable split-mod DIRECTORY name (e.g. crafting_in_modded). Anything not in
    # the stable set passes trivially (gate not applicable).
    [string]$Mod,
    # Repo root override (self-test fixtures). Default: parent of qa/.
    [string]$RepoRoot,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }

# The five unsuffixed _dev siblings (section 13.5 enumeration; keep in sync with
# tools/promote/promote.ps1 and qa/check_loc_tags.ps1).
$StableSplitDirs = @(
    'chaos_wastes_tweaker'
    'crafting_in_modded'
    'general_tweaker'
    'gui_tweaker'
    'verminious_dreams_lighting'
)

# Section 13.1 sanctioned vocabulary (exact case) + the wt-only 13.8 extensions.
# [Issue N]-form tags are matched by pattern below.
$SanctionedTags = @('untested', 'working', 'diag', 'crash', 'verify-fix', 'needs animations', 'needs offsets')

function Get-LeadingTagLeaks([string]$luaText, [string]$fileLabel) {
    # Same conservative single-literal heuristic as check_loc_tags.ps1: only
    # authored `en = "..."` / `en("...")` literals, only the LEADING bracket
    # run. An uppercase-leading display prefix ([CW], [Big Rebalance]) is not
    # a tag and ends the run.
    $leaks = @()
    $lineNo = 0
    foreach ($line in ($luaText -split "`n")) {
        $lineNo++
        $m = [regex]::Match($line, 'en\s*(?:=\s*|\()\s*"((?:[^"\\]|\\.)*)"')
        if (-not $m.Success) { continue }
        $value = $m.Groups[1].Value
        while ($value -match '^\[([^\]]+)\]\s*') {
            $inner = $matches[1]
            $rest  = $value.Substring($matches[0].Length)
            $isSanctioned = ($SanctionedTags -contains $inner) -or
                            ($inner -match '^Issue \d') -or
                            ($inner -match '^needs animations ->')
            if ($isSanctioned) {
                $leaks += ('{0}:{1}  [{2}]' -f $fileLabel, $lineNo, $inner)
            } elseif ($inner -notmatch '^[a-z]') {
                break  # display prefix ends the run
            }
            $value = $rest
        }
    }
    return $leaks
}

function Invoke-PromotionGate([string]$repo, [string]$modName) {
    # Returns a list of failure strings; empty = pass.
    $fails = @()

    if ($StableSplitDirs -notcontains $modName) {
        Write-Host "[check_promotion] '$modName' is not a stable split dir - gate not applicable." -ForegroundColor DarkGray
        return $fails
    }

    $modDir = Join-Path $repo $modName
    $luaPath = Join-Path $modDir "scripts\mods\$modName\$modName.lua"
    if (-not (Test-Path $luaPath)) {
        $fails += "main lua not found: $luaPath"
        return $fails
    }
    $luaTxt = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
    if ($luaTxt -match 'local\s+MOD_VERSION\s*=\s*"([^"]+)"') {
        $modVersion = $matches[1]
    } else {
        $fails += "no MOD_VERSION in $luaPath"
        return $fails
    }

    # -- (a) tag leaks in every *_localization.lua under the stable mod source --
    $srcDir = Join-Path $modDir "scripts\mods\$modName"
    foreach ($locFile in (Get-ChildItem -Path $srcDir -Filter '*_localization.lua' -File -ErrorAction SilentlyContinue)) {
        $locTxt = [System.IO.File]::ReadAllText($locFile.FullName, [System.Text.Encoding]::UTF8)
        foreach ($leak in (Get-LeadingTagLeaks $locTxt "$modName\$($locFile.Name)")) {
            $fails += "TAG LEAK (13.5 strip step skipped): $leak"
        }
    }

    # -- (b) pre-release suffix on the stable MOD_VERSION --
    if ($modVersion -match '-') {
        if ($env:VT2_SUFFIX_OK -eq '1') {
            Write-Host "[check_promotion] SUFFIX OVERRIDE: '$modVersion' allowed via VT2_SUFFIX_OK=1 (user-named suffixed public version, issue #328 ruling)." -ForegroundColor Yellow
        } else {
            $fails += "SUFFIX: stable MOD_VERSION '$modVersion' carries a pre-release suffix (6.5 step 2). If the USER named this suffixed public version, re-run with VT2_SUFFIX_OK=1."
        }
    }

    # -- (c) monotonic vs the stable CHANGELOG --
    $clPath = Join-Path $modDir 'CHANGELOG.md'
    if (-not (Test-Path $clPath)) {
        $fails += "no CHANGELOG.md in $modDir (cannot verify version monotonicity)"
    } else {
        $clTxt = [System.IO.File]::ReadAllText($clPath, [System.Text.Encoding]::UTF8)
        $hdrs = [regex]::Matches($clTxt, '(?m)^##\s+v?(\d+\.\d+\.\d+)(-[A-Za-z0-9.]+)?\b')
        if ($hdrs.Count -eq 0) {
            $fails += "no version headers in $clPath (cannot verify monotonicity)"
        } else {
            $topBase = $hdrs[0].Groups[1].Value
            $verBase = ($modVersion -split '-')[0]
            if ($verBase -ne $topBase) {
                $fails += "CHANGELOG MISMATCH: MOD_VERSION $modVersion vs top CHANGELOG entry $topBase (bump + entry land together, CLAUDE.md non-negotiable 5)."
            }
            if ($hdrs.Count -ge 2) {
                $prevBase = $hdrs[1].Groups[1].Value
                if ([System.Version]$topBase -le [System.Version]$prevBase) {
                    $fails += "NOT MONOTONIC: top CHANGELOG version $topBase does not increase over previous $prevBase."
                }
            }
        }
    }

    return $fails
}

# ---------------------------------------------------------------------------
# Self-test: synthetic fixture repo in %TEMP%. Files are created and removed
# individually (no recursive deletes - repo rule).
# ---------------------------------------------------------------------------
function Invoke-GateSelfTest {
    $script:t = 0; $script:p = 0
    function New-Fixture([string]$root, [string]$modVersion, [string]$locLine, [string[]]$clVersions) {
        $mod = 'crafting_in_modded'
        $src = Join-Path $root "$mod\scripts\mods\$mod"
        New-Item -ItemType Directory -Force -Path $src | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $src "$mod.lua"), "local MOD_VERSION = `"$modVersion`"`n")
        [System.IO.File]::WriteAllText((Join-Path $src ($mod + '_localization.lua')), "return {`n    some_key = { en = `"$locLine`" },`n}`n")
        $cl = "# Fixture Changelog`n`n"
        foreach ($v in $clVersions) { $cl += "## $v (2026-01-01) -- entry`n`nbody`n`n" }
        [System.IO.File]::WriteAllText((Join-Path $root "$mod\CHANGELOG.md"), $cl)
        return $mod
    }
    function Assert([bool]$cond, [string]$name) {
        $script:t++
        if ($cond) { $script:p++; Write-Host "  ok  $name" -ForegroundColor Green }
        else       { Write-Host "  FAIL $name" -ForegroundColor Red }
    }

    $fx = Join-Path ([System.IO.Path]::GetTempPath()) ("check_promotion_selftest_" + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $fx | Out-Null
    $saved = $env:VT2_SUFFIX_OK
    try {
        $env:VT2_SUFFIX_OK = $null
        $mod = New-Fixture $fx '0.8.34' 'Clean Option Title' @('0.8.34', '0.8.33')
        Assert ((Invoke-PromotionGate $fx $mod).Count -eq 0)                                    'clean stable passes'

        New-Fixture $fx '0.8.34' '[untested] Leaked Option' @('0.8.34', '0.8.33') | Out-Null
        $f = Invoke-PromotionGate $fx $mod
        Assert (@($f | Where-Object { $_ -match 'TAG LEAK' }).Count -eq 1)                      'loc tag leak fails (a)'

        New-Fixture $fx '0.8.34' '[Issue 278] Leaked Issue Tag' @('0.8.34', '0.8.33') | Out-Null
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'TAG LEAK').Count -eq 1)               '[Issue N] leak fails (a)'

        New-Fixture $fx '0.8.34' '[CW] Display Prefix Is Fine' @('0.8.34', '0.8.33') | Out-Null
        Assert ((Invoke-PromotionGate $fx $mod).Count -eq 0)                                    'display prefix is not a tag'

        New-Fixture $fx '0.8.35-dev' 'Clean' @('0.8.35-dev', '0.8.34') | Out-Null
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'SUFFIX').Count -eq 1)                 'pre-release suffix fails (b)'

        $env:VT2_SUFFIX_OK = '1'
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'SUFFIX').Count -eq 0)                 'VT2_SUFFIX_OK=1 overrides (b)'
        $env:VT2_SUFFIX_OK = $null

        New-Fixture $fx '0.8.34' 'Clean' @('0.8.34', '0.8.35') | Out-Null
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'NOT MONOTONIC').Count -eq 1)          'non-increasing version fails (c)'

        New-Fixture $fx '0.8.36' 'Clean' @('0.8.34', '0.8.33') | Out-Null
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'CHANGELOG MISMATCH').Count -eq 1)     'MOD_VERSION != top entry fails (c)'

        Assert ((Invoke-PromotionGate $fx 'weapon_tweaker').Count -eq 0)                        'non-stable mod is not applicable'
    } finally {
        $env:VT2_SUFFIX_OK = $saved
        # Individual-path cleanup only (repo rule: no recursive deletes).
        $mod = 'crafting_in_modded'
        $src = Join-Path $fx "$mod\scripts\mods\$mod"
        foreach ($f2 in @((Join-Path $src "$mod.lua"), (Join-Path $src ($mod + '_localization.lua')), (Join-Path $fx "$mod\CHANGELOG.md"))) {
            if (Test-Path $f2) { Remove-Item -LiteralPath $f2 }
        }
        foreach ($d in @($src, (Join-Path $fx "$mod\scripts\mods"), (Join-Path $fx "$mod\scripts"), (Join-Path $fx $mod), $fx)) {
            if (Test-Path $d) { Remove-Item -LiteralPath $d }
        }
    }

    Write-Host ""
    if (($script:t -gt 0) -and ($script:p -eq $script:t)) { Write-Host "[check_promotion -SelfTest] PASS $($script:p)/$($script:t)" -ForegroundColor Green; return 0 }
    Write-Host "[check_promotion -SelfTest] FAILED $($script:p)/$($script:t)" -ForegroundColor Red; return 2
}

if ($SelfTest) { exit (Invoke-GateSelfTest) }
if (-not $Mod) {
    Write-Host "Usage: check_promotion.ps1 -Mod <stable split dir>  (or -SelfTest)" -ForegroundColor Yellow
    exit 1
}

$failures = Invoke-PromotionGate $RepoRoot $Mod
if ($failures.Count -eq 0) {
    Write-Host "[check_promotion] PASS - '$Mod' clears the promotion gate (issue #327)." -ForegroundColor Green
    exit 0
}
Write-Host "[check_promotion] FAILED - $($failures.Count) finding(s) block this stable ship (issue #327):" -ForegroundColor Red
foreach ($f in $failures) { Write-Host "  ! $f" -ForegroundColor Red }
exit 1
