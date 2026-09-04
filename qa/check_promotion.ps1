# check_promotion.ps1 - BLOCKING dev-to-stable promotion gate (issue #327).
#
# Doctrine: docs/PROMOTION_PROCESS.md + LOCALIZATION_STANDARD.md section 13.
# Both 2026-07-04-era promotions each leaked a different checklist step to
# PUBLIC subscribers (stable cim shipped 7 [untested] loc tags; stable ct went
# out suffixed 0.7.130-beta without a named clean version). The advisory scans
# promotion needs a defense-in-depth RED gate. The repo-wide #694 check now blocks
# this metadata in every stream; ship.ps1 also invokes this check for STABLE dirs.
#
# Checks (all hard failures):
#   (a) TAG LEAK      - any forbidden lifecycle/status tag (section 13.1 vocabulary)
#                       leading an authored en-string in the stable dir's
#                       *_localization.lua. No active stream carries these tags
#                       (CLAUDE.md non-negotiable 11).
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
    # PR-relative paths used only to distinguish documentation maintenance from
    # an actual stable release mutation. The check fails closed when omitted.
    [string[]]$ChangedPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PSScriptRoot 'promotion_version_reader.ps1')

# The five unsuffixed _dev siblings (keep in sync with
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

function Test-DocumentationOnlyStableChange([string]$modName, [string[]]$paths) {
    if (-not $paths -or $paths.Count -eq 0) { return $false }

    $prefix = "$modName/"
    $owned = @(
        $paths |
            ForEach-Object { "$_".Replace('\', '/') } |
            Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }
    )
    if ($owned.Count -eq 0) { return $false }

    foreach ($path in $owned) {
        $leaf = [System.IO.Path]::GetFileName($path)
        if (-not $leaf.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase) -or
            $leaf.Equals('CHANGELOG.md', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

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
    try {
        $modVersion = Get-CanonicalPromotionModVersion -Text $luaTxt -SourceLabel $luaPath
    } catch {
        $fails += "invalid MOD_VERSION authority in ${luaPath}: $($_.Exception.Message)"
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
        $hdrs = [regex]::Matches(
            $clTxt,
            '(?m)^##\s+v?(?<version>\d+\.\d+\.\d+(?:-[A-Za-z0-9.+-]+)?)(?=\s|$)'
        )
        if ($hdrs.Count -eq 0) {
            $fails += "no version headers in $clPath (cannot verify monotonicity)"
        } else {
            $topVersion = $hdrs[0].Groups['version'].Value
            $topBase = ($topVersion -split '-')[0]
            $verBase = ($modVersion -split '-')[0]
            if ($modVersion -cne $topVersion) {
                $fails += "CHANGELOG MISMATCH: MOD_VERSION $modVersion vs top CHANGELOG entry $topVersion (the full version, including suffix, must match; CLAUDE.md non-negotiable 5)."
            }
            if ($hdrs.Count -ge 2) {
                $prevBase = ($hdrs[1].Groups['version'].Value -split '-')[0]
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
    function Set-MainLua([string]$root, [string]$modName, [string]$text) {
        $path = Join-Path $root "$modName\scripts\mods\$modName\$modName.lua"
        [System.IO.File]::WriteAllText($path, $text)
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

        Set-MainLua $fx $mod "-- local MOD_VERSION = `"9.9.9-beta`"`nlocal bait = [=[local MOD_VERSION = `"9.9.8-beta`"]=]`nmod.MOD_VERSION = `"9.9.7-beta`"`nlocal MOD_VERSION = `"0.8.34`""
        Assert ((Invoke-PromotionGate $fx $mod).Count -eq 0)                                    'shared lexical reader ignores comment, long-string, and member decoys'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nMOD_VERSION = `"0.8.35`""
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'MOD_VERSION reassignment fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nMOD_VERSION, x = `"0.8.35`", 1"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'multiple-assignment MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal x, MOD_VERSION = 1, `"0.8.35`""
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'multiple-local MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`nlocal t={run=function() local y=1; MOD_VERSION=`"0.8.35`" end}; t.run()"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'table-owned closure MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal t = {}`nMOD_VERSION, (t).x = `"0.8.35`", 1"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'parenthesized-lvalue MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal function f() return {} end`nMOD_VERSION, f().x = `"0.8.35`", 1"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'call-result-lvalue MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nfunction MOD_VERSION() end"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'function MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal function MOD_VERSION() end"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'local function MOD_VERSION shadow fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal function f(x, MOD_VERSION) return x end"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'named-function parameter MOD_VERSION shadow fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal f = function(x, MOD_VERSION) return x end"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'anonymous-function parameter MOD_VERSION shadow fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal x, MOD_VERSION"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'initializer-free local MOD_VERSION shadow fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nfor x, MOD_VERSION in pairs({}) do return x end"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'generic-for MOD_VERSION shadow fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`n::again:: MOD_VERSION=`"0.8.35`""
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'label-adjacent immediate MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`nlocal t={}`n::again:: MOD_VERSION,(t).x=`"0.8.35`",1"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'label-adjacent parenthesized-lvalue rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`nlocal function f() return {} end`n::again:: MOD_VERSION,f().x=`"0.8.35`",1"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'label-adjacent call-result-lvalue rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`nlocal t={}`n::again:: t.x,MOD_VERSION,(t).y=1,`"0.8.35`",2"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'label-adjacent middle-slot rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`n::again:: function MOD_VERSION() end"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'label-adjacent function MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`n::again:: local x,MOD_VERSION"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'label-adjacent local MOD_VERSION shadow fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`nlocal t={run=function() ::again:: MOD_VERSION=`"0.8.35`" end}; t.run()"
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'label-adjacent closure MOD_VERSION rebinding fails closed'

        Set-MainLua $fx $mod "local MOD_VERSION=`"0.8.34`"`nlocal mod={}`n::again:: mod.MOD_VERSION=`"member`""
        Assert ((Invoke-PromotionGate $fx $mod).Count -eq 0) 'label-adjacent member assignment remains unrelated'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal a = { MOD_VERSION, `"x`" }`nlocal b = string.format(`"%s:%s`", MOD_VERSION, `"x`")`nlocal c, d = MOD_VERSION, `"x`""
        Assert ((Invoke-PromotionGate $fx $mod).Count -eq 0)                                    'ordinary comma-separated MOD_VERSION reads remain valid'

        Set-MainLua $fx $mod "local MOD_VERSION = `"0.8.34`"`nlocal MOD_VERSION = `"0.8.34`""
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'invalid MOD_VERSION authority').Count -eq 1) 'duplicate canonical MOD_VERSION fails closed'

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

        New-Fixture $fx '0.8.35-evil' 'Clean' @('0.8.35-beta', '0.8.34') | Out-Null
        Set-MainLua $fx $mod "-- MOD_VERSION = `"0.8.35-beta`"`nlocal MOD_VERSION = `"0.8.35-evil`""
        $env:VT2_SUFFIX_OK = '1'
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'CHANGELOG MISMATCH').Count -eq 1)      'full suffix must exactly match top CHANGELOG version'

        New-Fixture $fx '0.8.35-evil' 'Clean' @('0.8.35-evil', '0.8.34') | Out-Null
        Set-MainLua $fx $mod "-- MOD_VERSION = `"0.8.35-beta`"`nlocal MOD_VERSION = `"0.8.35-evil`""
        Assert ((Invoke-PromotionGate $fx $mod).Count -eq 0)                                    'authorization and gate resolve the same real full version'
        $env:VT2_SUFFIX_OK = $null

        New-Fixture $fx '0.8.34' 'Clean' @('0.8.34', '0.8.35') | Out-Null
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'NOT MONOTONIC').Count -eq 1)          'non-increasing version fails (c)'

        New-Fixture $fx '0.8.36' 'Clean' @('0.8.34', '0.8.33') | Out-Null
        Assert (@((Invoke-PromotionGate $fx $mod) -match 'CHANGELOG MISMATCH').Count -eq 1)     'MOD_VERSION != top entry fails (c)'

        Assert ((Invoke-PromotionGate $fx 'weapon_tweaker').Count -eq 0)                        'non-stable mod is not applicable'
        Assert (Test-DocumentationOnlyStableChange $mod @(
            'crafting_in_modded/REGRESSION_CHECKLIST.md',
            'docs/PORTABLE_SETUP.md'
        ))                                                                                     'stable markdown maintenance is not a release'
        Assert (-not (Test-DocumentationOnlyStableChange $mod @(
            'crafting_in_modded/REGRESSION_CHECKLIST.md',
            'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua'
        )))                                                                                    'stable runtime change still requires release gate'
        Assert (-not (Test-DocumentationOnlyStableChange $mod @(
            'crafting_in_modded/CHANGELOG.md'
        )))                                                                                    'stable changelog change still requires release gate'
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

if (Test-DocumentationOnlyStableChange $Mod $ChangedPath) {
    Write-Host "[check_promotion] PASS - '$Mod' changes documentation only; no stable release invariants changed." -ForegroundColor Green
    exit 0
}

$failures = Invoke-PromotionGate $RepoRoot $Mod
if ($failures.Count -eq 0) {
    Write-Host "[check_promotion] PASS - '$Mod' clears the promotion gate (issue #327)." -ForegroundColor Green
    exit 0
}
Write-Host "[check_promotion] FAILED - $($failures.Count) finding(s) block this stable ship (issue #327):" -ForegroundColor Red
foreach ($f in $failures) { Write-Host "  ! $f" -ForegroundColor Red }
exit 1
