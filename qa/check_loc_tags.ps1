# check_loc_tags.ps1 — dev-build localization STATUS-TAG scan (issue #301).
#
# Doctrine: LOCALIZATION_STANDARD.md § 13 "Dev status tags". Dev builds prefix
# each option-TITLE `en` string with one or more status tags so the user can
# see, in-game, what needs testing. The seven sanctioned tags are:
#   [untested] [Issue N] [working] [diag] [crash] [verify-fix] [needs animations]
# ([Issue ...] may carry multiple numbers: [Issue 501 & 427] / [Issue 501, 427 & 418].)
# Plus two weapon_tweaker-only extensions (§ 13.8), also accepted here:
#   [needs offsets]  and  [needs animations -> <target>]
# — both emitted at load by wt_port_status.lua, not authored in the loc file.
#
# This is a WARNING-ONLY, NON-BLOCKING advisory scan. It reports three things:
#
#   (a) STABLE LEAK — any sanctioned tag present in a STABLE mod directory.
#       Stable (clean-versioned public) builds must strip ALL tags at promotion
#       (§ 13.5). The stable dirs are the unsuffixed siblings of the `_dev`
#       clones: chaos_wastes_tweaker / crafting_in_modded / general_tweaker /
#       gui_tweaker / verminious_dreams_lighting. Known live violation: stable
#       `crafting_in_modded` carries 7 `[untested]` tags (a promotion leak,
#       tracked for cleanup at the next cim promotion) — this check exists to
#       surface exactly that class.
#
#   (b) UNKNOWN VOCAB — a *tag-like* leading bracket group that is NOT one of
#       the seven sanctioned tags (a typo / invented tag). "No invented tags"
#       (§ 13.1). E.g. `[confirmed working]` (should be `[working]`), `[fixed]`,
#       `[issue 5]` (lowercase i — casing matters).
#
#   (c) MUTEX VIOLATION — `[crash]`, `[working]`, `[untested]` are mutually
#       exclusive (§ 13.1); 2+ of them on one option is a contradiction.
#
# HEURISTIC (documented so future edits stay conservative — issue #301 asked
# for a deliberately low false-positive design):
#
#   * We only parse SINGLE-LITERAL entries of the three canonical loc forms:
#         key            = { en = "VALUE" }
#         key            = en("VALUE")
#         loc.key        = { en = "VALUE" }
#     (VALUE is one complete double-quoted literal.) This means dynamic /
#     concatenated strings — ct_dev's runtime `entry.en = "[confirmed working] "
#     .. entry.en` post-process loop, event_tweaker's `en("[" .. id .. "] " ..)`
#     tooltip builder — are NOT captured. Good: those are runtime prepends /
#     tooltip bodies, not authored option titles.
#
#   * From VALUE we read the LEADING RUN of `[...]` bracket groups (each
#     separated by single spaces). Each group is classified:
#       - KNOWN     — one of the seven sanctioned tags (exact case).
#       - TAG-LIKE  — looks like it was MEANT to be a tag but isn't sanctioned:
#                     inner text is lowercase-leading ([a-z][a-z0-9 -]*) OR
#                     starts with "Issue" / "issue". These are flagged (b).
#       - NOT-TAG   — anything else (UPPERCASE-leading category prefixes such as
#                     `[CW]`, `[Big Rebalance]`, `[WARNING]`, `[Hacks]`,
#                     `[Forced Aggro]`). Treated as a legitimate DISPLAY-NAME
#                     prefix; it ENDS the tag run and is left alone.
#     `gut`'s `<...>` angle markers are not square brackets, so they never enter
#     the run at all (no crash, no false positive).
#
#   * STABLE mods are matched by directory NAME against a fixed list (the five
#     unsuffixed `_dev` siblings). The underlying rule is the MOD_VERSION suffix
#     (dev = has -dev/-alpha/-beta/-rc; stable = clean), but the name list is
#     exact, cheap, and matches the doctrine's own enumeration in § 13.5.
#
# Exclusions: `_archive/`, `bundleV2/`, `.build/`, `.temp/`, `_test_fixtures/`,
# upstream source clones, `_*_extract/` snapshots, the frozen legacy `tweaker/`
# mod, and the STALE `weapon_tweaker_dev/` experiment clone (never edited).
#
# Output mirrors qa/check_unpack_safety.ps1 / qa/check_vmf_widget_types.ps1.
#
# Exit codes:
#   0 - clean (no tag issues)
#   1 - one or more advisory WARNINGS (leak / unknown vocab / mutex) — NEVER
#       blocks the gate (wired into run_all.ps1 under -Policy 'Advisory').
#   2 - hard error (a file failed to read). Also non-blocking under Advisory,
#       but distinguishes a broken check from findings.
#
# Self-test: pass `-SelfTest` to run the synthetic fixtures under
# `qa/_test_fixtures/loc_tags_*.lua` and assert finding counts per fixture.
# Self-test exit 0 = wired correctly; exit 2 = regex/heuristic regression.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path

# ---- sanctioned tag vocabulary (§ 13.1, § 13.8) ----
# Exact lowercase tags (case-sensitive). [Issue N] is validated separately by
# format because it carries numbers. `needs offsets` and the `needs animations
# -> <target>` variant are the two weapon_tweaker-only extensions (§ 13.8):
# emitted at load by wt_port_status.lua (not authored in the static loc file),
# but accepted here so a stray/normalized static occurrence is never mis-flagged.
$KnownExactTags = @('untested', 'working', 'diag', 'crash', 'verify-fix', 'needs animations', 'needs offsets')
$KnownExactSet = @{}
foreach ($t in $KnownExactTags) { $KnownExactSet[$t] = $true }

# The three mutually-exclusive tags (§ 13.1).
$MutexTags = @('crash', 'working', 'untested')

# ---- stable mod dirs (§ 13.5) — the unsuffixed siblings of the _dev clones ----
$StableModDirs = @(
    'chaos_wastes_tweaker',
    'crafting_in_modded',
    'general_tweaker',
    'gui_tweaker',
    'verminious_dreams_lighting'
)
$StableSet = @{}
foreach ($d in $StableModDirs) { $StableSet[$d] = $true }

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# ---- per-line loc-entry regexes ----
# Each loc entry in this repo is authored on a single line. We anchor on a
# bareword (or `loc.`-prefixed) key so dynamic assignments like `entry.en = ...`
# and indexed assignments like `loc[key .. "_tooltip"] = ...` are NOT matched.
# The value must be ONE complete double-quoted literal (handles \" escapes).
$rxFormA = [regex]'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"'
$rxFormB = [regex]'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*en\s*\(\s*"((?:[^"\\]|\\.)*)"\s*\)'
$rxFormC = [regex]'^\s*loc\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"'
# Multi-line table form (crafting_in_modded style):
#     key = {
#         en = "VALUE",
#     },
# A `key = {` (or `loc.key = {`) line that does NOT close on itself opens a
# pending key; the following bare `en = "VALUE"` line binds to it.
$rxKeyOpen    = [regex]'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*(--.*)?$'
$rxLocKeyOpen = [regex]'^\s*loc\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*(--.*)?$'
$rxBareEn     = [regex]'^\s*en\s*=\s*"((?:[^"\\]|\\.)*)"'

# Sanctioned [Issue ...] format (§ 13.2): capital-I "Issue ", then a number list
# joined by ',' / '&' (spaces optional).
$rxIssueKnown = [regex]'^Issue \d+(\s*[,&]\s*\d+)*$'
# weapon_tweaker-only variant (§ 13.8): `needs animations <arrow> <target>`,
# e.g. "needs animations -> Greathammer" (the emitter uses a U+2192 arrow). The
# base `needs animations` is already in $KnownExactTags; this accepts any
# suffix after it (the arrow + mapped target) WITHOUT matching the arrow byte,
# so the source file stays pure ASCII. A typo like `needs animation` (no 's')
# still falls through to the UNKNOWN path.
$rxNeedsAnimVariant = [regex]'^needs animations(\s.*)?$'
# "meant to be a tag" shapes: lowercase-leading, or (mis-cased) Issue-leading.
$rxLowerTag   = [regex]'^[a-z][a-z0-9 \-]*$'
$rxIssueLike  = [regex]'^[Ii]ssue\b'

# Classify a single bracket-group inner text.
#   'KNOWN'   -> sanctioned tag
#   'UNKNOWN' -> tag-like but not sanctioned (flag as unknown vocab)
#   'NOTTAG'  -> legitimate display-name prefix; ends the tag run
function Classify-Tag([string]$inner) {
    $t = $inner.Trim()
    if ($KnownExactSet.ContainsKey($t))      { return 'KNOWN' }
    if ($rxIssueKnown.IsMatch($t))           { return 'KNOWN' }
    if ($rxNeedsAnimVariant.IsMatch($t))     { return 'KNOWN' }   # wt-only `needs animations -> <target>`
    if ($rxLowerTag.IsMatch($t) -or $rxIssueLike.IsMatch($t)) { return 'UNKNOWN' }
    return 'NOTTAG'
}

# Parse the LEADING RUN of bracket groups from a value string.
# Returns @{ Known = @(inner...); Unknown = @(inner...) }.
# Stops at the first NOT-TAG bracket group or the first non-bracket token.
function Get-LeadingTagRun([string]$s) {
    $known = @()
    $unknown = @()
    $i = 0
    $n = $s.Length
    while ($i -lt $n) {
        # Skip spaces between (or before) tags. Mutex-cluster labels like
        # "[untested]     (A) Foo" carry 4+ spaces before the "(A)"; that's fine
        # — after the tag run we hit "(" and stop.
        while ($i -lt $n -and $s[$i] -eq ' ') { $i++ }
        if ($i -ge $n -or $s[$i] -ne '[') { break }
        $close = $s.IndexOf(']', $i)
        if ($close -lt 0) { break }
        $inner = $s.Substring($i + 1, $close - $i - 1)
        $cls = Classify-Tag $inner
        if ($cls -eq 'KNOWN') {
            $known += $inner.Trim()
            $i = $close + 1
        } elseif ($cls -eq 'UNKNOWN') {
            $unknown += $inner.Trim()
            $i = $close + 1
        } else {
            break   # NOT-TAG: display name begins here
        }
    }
    return @{ Known = $known; Unknown = $unknown }
}

# ---- file collection ----
function Get-ScanFiles {
    param([string]$Root)
    Get-ChildItem -Path $Root -Filter "*_localization.lua" -Recurse -File -ErrorAction SilentlyContinue `
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
                       -and $p -notlike "*\weapon_tweaker_dev\*" `
                       -and $p -notlike "*\_test_fixtures\*" `
                       -and $p -notlike "*\sample_*\*" `
                       -and $p -notlike "*\Vermintide-2-Source-Code\*" `
                       -and $p -notlike "*\Darktide-Source-Code\*" `
                       -and $p -notlike "*\_*_extract\*"
            return $isUnderMod -and $notExcluded
        }
}

# Mod dir = 3 levels up from <mod>/scripts/mods/<mod>/<mod>_localization.lua.
function Get-ModDirName([string]$filePath) {
    $dir = Split-Path $filePath -Parent
    for ($i = 0; $i -lt 3; $i++) { $dir = Split-Path $dir -Parent }
    return (Split-Path $dir -Leaf)
}

# ---- per-text scan ----
# Returns an array of finding rows: @{ Kind; Line; Key; Value; Detail }.
# Kind in { leak, unknown, mutex }. $IsStable drives the leak check.
function Scan-Text {
    param([string]$Text, [bool]$IsStable)
    $rows = @()
    $lines = $Text -split "`r?`n"
    $pendingKey = $null   # multi-line table form: key seen, awaiting its `en =` line
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $key = $null; $val = $null

        # 1) single-line forms: key = { en = "V" } / key = en("V") / loc.key = { en = "V" }
        $m = $rxFormA.Match($line)
        if (-not $m.Success) { $m = $rxFormB.Match($line) }
        if (-not $m.Success) { $m = $rxFormC.Match($line) }
        if ($m.Success) {
            $key = $m.Groups[1].Value
            $val = $m.Groups[2].Value
            $pendingKey = $null
        } else {
            # 2) multi-line table open: `key = {` (or `loc.key = {`) -> remember key.
            $ko = $rxKeyOpen.Match($line)
            if (-not $ko.Success) { $ko = $rxLocKeyOpen.Match($line) }
            if ($ko.Success) { $pendingKey = $ko.Groups[1].Value; continue }
            # 3) bare `en = "V"` line inside a pending table -> bind to pending key.
            $be = $rxBareEn.Match($line)
            if ($be.Success -and $pendingKey) {
                $key = $pendingKey
                $val = $be.Groups[1].Value
                $pendingKey = $null
            } else {
                continue
            }
        }

        # Fast bail: only strings that start (after optional spaces) with '[' can
        # carry a leading tag run.
        if ($val -notmatch '^\s*\[') { continue }

        $run = Get-LeadingTagRun $val
        $known = $run.Known
        $unknown = $run.Unknown

        if ($known.Count -eq 0 -and $unknown.Count -eq 0) { continue }

        # (a) stable leak — any sanctioned tag in a stable dir.
        if ($IsStable -and $known.Count -gt 0) {
            $rows += [pscustomobject]@{
                Kind = 'leak'; Line = $i + 1; Key = $key; Value = $val
                Detail = "sanctioned tag(s) [" + ($known -join '] [') + "] in a STABLE build (must be stripped at promotion)"
            }
        }

        # (b) unknown vocab — tag-like leading group not in the sanctioned set.
        if ($unknown.Count -gt 0) {
            $rows += [pscustomobject]@{
                Kind = 'unknown'; Line = $i + 1; Key = $key; Value = $val
                Detail = "unknown tag vocabulary [" + ($unknown -join '] [') + "] (not one of the 7 sanctioned tags)"
            }
        }

        # (c) mutex — 2+ of [crash]/[working]/[untested].
        $mx = @($known | Where-Object { $MutexTags -ccontains $_ } | Select-Object -Unique)
        if ($mx.Count -ge 2) {
            $rows += [pscustomobject]@{
                Kind = 'mutex'; Line = $i + 1; Key = $key; Value = $val
                Detail = "mutually-exclusive tags combined: [" + ($mx -join '] [') + "]"
            }
        }
    }
    return ,$rows
}

function Scan-File {
    param([string]$Path, [bool]$IsStable)
    $text = Read-FileUtf8 $Path
    return (Scan-Text -Text $text -IsStable $IsStable)
}

# ---- self-test ----
function Invoke-SelfTest {
    $fixDir = Join-Path $PSScriptRoot "_test_fixtures"
    if (-not (Test-Path $fixDir)) {
        Write-Host "[check_loc_tags -SelfTest] FAIL: $fixDir does not exist." -ForegroundColor Red
        return 2
    }

    # Each case: fixture + IsStable + expected finding counts per Kind.
    $cases = @(
        @{ Path = "loc_tags_dev_ok.lua";     IsStable = $false; Leak = 0; Unknown = 0; Mutex = 0;
           Desc = "dev build, all-valid tags + uppercase prefix + angle marker" },
        @{ Path = "loc_tags_dev_ok.lua";     IsStable = $true;  Leak = 12; Unknown = 0; Mutex = 0;
           Desc = "same file scanned as STABLE -> every sanctioned-tag entry (incl. wt-only + [Issue 321]) is a leak" },
        @{ Path = "loc_tags_unknown.lua";    IsStable = $false; Leak = 0; Unknown = 4; Mutex = 2;
           Desc = "dev build, unknown-vocab typos + mutex combos; uppercase prefixes ignored" }
    )

    $allPass = $true
    foreach ($c in $cases) {
        $f = Join-Path $fixDir $c.Path
        if (-not (Test-Path $f)) {
            Write-Host "  X $($c.Path): missing fixture file" -ForegroundColor Red
            $allPass = $false; continue
        }
        $rows = @(Scan-File -Path $f -IsStable $c.IsStable)
        $leak    = @($rows | Where-Object { $_.Kind -eq 'leak' }).Count
        $unknown = @($rows | Where-Object { $_.Kind -eq 'unknown' }).Count
        $mutex   = @($rows | Where-Object { $_.Kind -eq 'mutex' }).Count
        $ok = ($leak -eq $c.Leak) -and ($unknown -eq $c.Unknown) -and ($mutex -eq $c.Mutex)
        $verdict = if ($ok) { "PASS" } else { "FAIL" }
        $colour = if ($ok) { "Green" } else { "Red" }
        Write-Host ("  [{0}] {1} (stable={2}) -- {3}" -f $verdict, $c.Path, $c.IsStable, $c.Desc) -ForegroundColor $colour
        Write-Host ("        leak={0}/{1} unknown={2}/{3} mutex={4}/{5}" -f $leak, $c.Leak, $unknown, $c.Unknown, $mutex, $c.Mutex) -ForegroundColor DarkGray
        if (-not $ok) { $allPass = $false }
    }

    Write-Host ""
    if ($allPass) {
        Write-Host "[check_loc_tags -SelfTest] OK -- all $($cases.Count) fixture verdicts match." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[check_loc_tags -SelfTest] FAILED -- regex / heuristic regression. Inspect fixtures + Scan-Text." -ForegroundColor Red
        return 2
    }
}

# ---- main ----
Write-Host "=== check_loc_tags ===" -ForegroundColor Cyan

if ($SelfTest) {
    exit (Invoke-SelfTest)
}

$allRows = @()
$hardError = $false

$files = @(Get-ScanFiles -Root $repoRoot)
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\', '/')
    $modName = Get-ModDirName $f.FullName
    $isStable = $StableSet.ContainsKey($modName)
    if (-not $Quiet) {
        $tag = if ($isStable) { "STABLE" } else { "dev" }
        Write-Host "Checking $modName ($tag) — $rel" -ForegroundColor DarkGray
    }
    try {
        $rows = @(Scan-File -Path $f.FullName -IsStable $isStable)
    } catch {
        Write-Host ("  X {0}: {1}" -f $rel, $_) -ForegroundColor Red
        $hardError = $true
        continue
    }
    foreach ($r in $rows) {
        $allRows += ($r | Add-Member -NotePropertyName Mod -NotePropertyValue $modName -PassThru `
                          | Add-Member -NotePropertyName Rel -NotePropertyValue $rel -PassThru)
    }
}

Write-Host ""
if ($hardError) {
    Write-Host "[check_loc_tags] ERROR -- one or more files failed to scan." -ForegroundColor Red
    exit 2
}

if ($allRows.Count -eq 0) {
    Write-Host "[check_loc_tags] OK -- no dev status-tag issues (no stable leaks, unknown vocab, or mutex combos)." -ForegroundColor Green
    exit 0
}

$leaks    = @($allRows | Where-Object { $_.Kind -eq 'leak' })
$unknowns = @($allRows | Where-Object { $_.Kind -eq 'unknown' })
$mutexes  = @($allRows | Where-Object { $_.Kind -eq 'mutex' })

Write-Host ("[check_loc_tags] WARNINGS: {0} (stable leak: {1}, unknown vocab: {2}, mutex: {3}) -- advisory, non-blocking." `
    -f $allRows.Count, $leaks.Count, $unknowns.Count, $mutexes.Count) -ForegroundColor Yellow

if ($leaks.Count -gt 0) {
    Write-Host "  -- STABLE LEAK (tags must be stripped at promotion; LOCALIZATION_STANDARD.md § 13.5):" -ForegroundColor Yellow
    foreach ($r in $leaks) {
        Write-Host ("  ! {0}:{1}  {2}  {3}" -f $r.Rel, $r.Line, $r.Key, $r.Detail) -ForegroundColor Yellow
    }
}
if ($unknowns.Count -gt 0) {
    Write-Host "  -- UNKNOWN VOCAB (typo / invented tag; § 13.1 'No invented tags'):" -ForegroundColor Yellow
    foreach ($r in $unknowns) {
        Write-Host ("  ! {0}:{1}  {2}  {3}" -f $r.Rel, $r.Line, $r.Key, $r.Detail) -ForegroundColor Yellow
    }
}
if ($mutexes.Count -gt 0) {
    Write-Host "  -- MUTEX (crash/working/untested are mutually exclusive; § 13.1):" -ForegroundColor Yellow
    foreach ($r in $mutexes) {
        Write-Host ("  ! {0}:{1}  {2}  {3}" -f $r.Rel, $r.Line, $r.Key, $r.Detail) -ForegroundColor Yellow
    }
}
exit 1
