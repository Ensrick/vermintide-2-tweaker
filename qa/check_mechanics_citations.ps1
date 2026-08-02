# ============================================================================
# check_mechanics_citations.ps1 — provenance lint for docs/MECHANICS.md
# ============================================================================
#
# Scans ONLY the MECHANICS substrate (docs/MECHANICS.md). Enforces that every
# FACTUAL bullet carries a provenance tag, so an uncited mechanic claim cannot
# land. `[unverified]` placeholders are ALLOWED but COUNTED and reported as the
# "known gaps" backlog metric — honest gaps, surfaced not hidden.
#
# Mirrors qa/check_localization.ps1 conventions: same -RepoRoot param, exit
# codes 0 = clean, 1 = warnings only, 2 = errors found. -SelfTest plants faults
# and proves the lint fires.
#
# WHAT COUNTS AS A "FACTUAL BULLET":
#   A markdown list bullet (line whose first non-space char is `-`) that lives
#   under a `## Domain:` heading. Those sections hold the grounded claims. Every
#   such bullet MUST carry exactly one provenance tag (see TAG REGEX below) OR be
#   tagged [unverified].
#
# WHAT IS EXEMPT (framing, not claims):
#   - Bullets OUTSIDE any `## Domain:` section (the intro, the provenance schema,
#     the "Relationship to the rest of the doc tree" list) — these describe the
#     doc itself, not game mechanics.
#   - The "## Known gaps" section's bullets ARE factual-claim-shaped but MUST be
#     [unverified] (they are the explicit backlog); they are linted to REQUIRE
#     [unverified] specifically — a bare claim there is still an ERROR.
#   - Headings, tables (lines starting with `|`), blockquotes (`>`), HTML.
#
# PROVENANCE TAGS (any one satisfies a factual bullet):
#   [src: <path>:<line-or-range>]   gold — decompiled-source-verified
#   [dump: <file>]                  high — in-game runtime dump
#   [memory: <note-name>]           mid  — memory note that itself cites truth
#   [bugclass: ...]                 mid  — carried from docs/BUG_CLASSES.md
#   [user: YYYY-MM-DD]              low  — maintainer stated it
#   [unverified]                    none — explicit honest gap (counted)
#
# SRC RESOLUTION (second, independent check — runs by default)
#   Tag SHAPE alone proves nothing: `[src: totally/made/up.lua:99999]` satisfies
#   the regex above. The resolver opens every `[src: path:line]` in MECHANICS,
#   BUG_CLASSES, WEAPON_APPEARANCE_STANDARD, and CROSS_MOD_ARCHITECTURE and
#   requires the file to exist under the decompiled tree with every cited line
#   in range. CI checks out ONLY this repo, so a missing source tree is a clean,
#   visible SKIP (same convention as check_name_integrity /
#   check_source_provenance); it is BLOCKING wherever the tree is present.
#
# USAGE
#   .\qa\check_mechanics_citations.ps1
#       -RepoRoot <repo>   (default: parent of qa/)
#       -VtSrc <path>      (default: ..\..\Vermintide-2-Source-Code)
#       -Quiet
#       -SelfTest          run the planted-fault self-test and exit
#       -ResolveSrc        run ONLY the [src:] resolver and exit
#       -RequireSource     make a missing decompiled tree an ERROR, not a SKIP
# ============================================================================

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [string]$VtSrc    = (Join-Path $PSScriptRoot "..\..\Vermintide-2-Source-Code"),
    [switch]$Quiet,
    [switch]$SelfTest,
    [switch]$ResolveSrc,
    [switch]$RequireSource
)

$ErrorActionPreference = "Stop"

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}
function Log($msg, $color = "DarkGray") { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

# Any one of these tags satisfies a factual bullet. Kept deliberately strict on
# shape so a malformed tag (e.g. `[src ...]` missing the colon) is NOT accepted.
$TagRegex = @(
    '\[src:\s*[^\]]+:[0-9][^\]]*\]'   # [src: path:line] or :line-range
    '\[dump:\s*[^\]]+\]'              # [dump: file]
    '\[memory:\s*[^\]]+\]'            # [memory: note]
    '\[bugclass:\s*[^\]]+\]'          # [bugclass: §N]
    '\[user:\s*[0-9]{4}-[0-9]{2}-[0-9]{2}\]'  # [user: YYYY-MM-DD]
) -join '|'

$UnverifiedRegex = '\[unverified\]'

# ----------------------------------------------------------------------------
# CORE: scan the given markdown text, return @{ errors; unverified; cited;
#       domains } where errors is a list of "line N: ..." strings.
# ----------------------------------------------------------------------------
function Invoke-MechanicsScan {
    param([string]$Text)

    $lines = $Text -split "`r?`n"
    $errors = @()
    $unverifiedCount = 0
    $citedCount = 0
    $domainHits = @{}

    $inDomain = $false       # currently under a `## Domain:` heading
    $inKnownGaps = $false    # currently under the `## Known gaps` heading
    $currentDomain = $null

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1
        $trim = $line.TrimStart()

        # --- section heading transitions ---
        if ($trim -match '^##\s+Domain:\s*(.+?)\s*$') {
            $inDomain = $true
            $inKnownGaps = $false
            $currentDomain = $matches[1]
            $domainHits[$currentDomain] = @{ cited = 0; unverified = 0 }
            continue
        }
        if ($trim -match '^##\s+Known gaps') {
            $inDomain = $false
            $inKnownGaps = $true
            $currentDomain = 'Known gaps'
            $domainHits[$currentDomain] = @{ cited = 0; unverified = 0 }
            continue
        }
        # A level-3+ subheading SUBDIVIDES a Domain (e.g. `### Athanor accessory
        # properties`) and must NOT close the claim-bearing region. Treating it as
        # a terminator silently un-linted every bullet from the subheading to the
        # next `## Domain:` — 16 claims in Inventory / Equipment.
        if ($trim -match '^#{3,6}\s') { continue }

        # any OTHER level-1/2 heading closes the claim-bearing region
        if ($trim -match '^#{1,2}\s') {
            $inDomain = $false
            $inKnownGaps = $false
            $currentDomain = $null
            continue
        }

        # only scan bullets inside a claim-bearing section
        if (-not ($inDomain -or $inKnownGaps)) { continue }

        # a factual bullet: starts with `- ` (markdown list item). Skip table
        # rows (|...), blockquotes (>), and continuation lines (those are folded
        # into the bullet they belong to, so a tag anywhere in the bullet wins —
        # see multi-line handling below).
        if ($trim -notmatch '^-\s+\S') { continue }

        # Fold the bullet's continuation lines (indented, non-bullet) into one
        # logical bullet so a tag at the END of a wrapped bullet still counts.
        $bullet = $line
        $j = $i + 1
        while ($j -lt $lines.Count) {
            $next = $lines[$j]
            $nt = $next.TrimStart()
            if ($nt -eq '') { break }                       # blank ends the bullet
            if ($nt -match '^-\s+\S') { break }             # next bullet
            if ($nt -match '^#{1,6}\s') { break }           # heading
            if ($nt -match '^\|') { break }                 # table
            # indented continuation of THIS bullet
            if ($next -match '^\s') { $bullet += "`n" + $next; $j++; continue }
            break
        }
        $i = $j - 1   # advance the outer loop past the folded continuation

        $hasTag = $bullet -match $TagRegex
        $hasUnverified = $bullet -match $UnverifiedRegex

        # Snippet for error reporting (first 80 chars of the bullet text).
        $snippet = ($bullet -replace '\s+', ' ').Trim()
        if ($snippet.Length -gt 80) { $snippet = $snippet.Substring(0, 80) + '...' }

        if ($inKnownGaps) {
            # Known-gaps bullets MUST be [unverified]. A real tag there is wrong
            # (it would mean it's not a gap), and a bare claim is an ERROR.
            if ($hasUnverified) {
                $unverifiedCount++
                $domainHits[$currentDomain].unverified++
            } elseif ($hasTag) {
                $errors += "line ${lineNo}: bullet in 'Known gaps' carries a real provenance tag but is filed as a gap — move it into a Domain section or drop the [unverified]: '$snippet'"
            } else {
                $errors += "line ${lineNo}: UNCITED claim in 'Known gaps' (must be [unverified]): '$snippet'"
            }
            continue
        }

        # Domain section: must carry a tag OR be explicitly [unverified].
        if ($hasUnverified) {
            $unverifiedCount++
            $domainHits[$currentDomain].unverified++
        } elseif ($hasTag) {
            $citedCount++
            $domainHits[$currentDomain].cited++
        } else {
            $errors += "line ${lineNo}: UNCITED factual bullet (no provenance tag) under '$currentDomain': '$snippet'"
        }
    }

    return @{
        errors      = $errors
        unverified  = $unverifiedCount
        cited       = $citedCount
        domains     = $domainHits
    }
}

# ============================================================================
# SRC RESOLVER — every `[src: path:line]` must point at a real file and a real
# line. Parses the WHOLE text (not line-by-line): tags legitimately wrap across
# lines, and a line-based matcher silently misses those.
#
# Payload grammar actually in use in the substrate:
#   path.lua:12            single ref
#   path.lua:12-40         range
#   path.lua:12,40-55      comma list of lines/ranges
#   a.lua:1; b.lua:2       `;`-separated multi-ref
#   a.lua:1; :99           bare `:NNN` continuation, inherits the previous path
#   path.lua:7500 (label)  trailing parenthetical note, stripped
# Backticks are stripped (BUG_CLASSES-style `[src: \`foo.lua:1\`]`).
# Schema placeholders (`<path>`, `file:line`) are documentation, not claims.
# ============================================================================
function Invoke-SrcResolve {
    param([string]$Text, [string]$SourceRoot)

    $problems = @()
    $refCount = 0

    foreach ($m in [regex]::Matches($Text, '\[src:\s*([^\]]+)\]')) {
        # doc line number = newlines before the match + 1
        $docLine = ($Text.Substring(0, $m.Index) -split "`n").Count
        $payload = (($m.Groups[1].Value -replace '`', '') -replace '\s+', ' ').Trim()
        $lastPath = $null

        foreach ($part in ($payload -split ';')) {
            $part = $part.Trim()
            if ($part -eq '') { continue }
            # drop a trailing "(note)" label
            $clean = ($part -replace '\s*\(.*?\)\s*$', '').Trim()
            # schema placeholders in the doc header are not citations
            if ($clean -match '[<>]' -or $clean -eq 'file:line') { continue }

            if     ($clean -match '^(?<p>[^:]+\.lua):(?<l>[0-9][0-9,\-]*)$') { $p = $matches['p']; $l = $matches['l']; $lastPath = $p }
            elseif ($clean -match '^:(?<l>[0-9][0-9,\-]*)$')                 { $p = $lastPath;    $l = $matches['l'] }
            elseif ($clean -match '^(?<p>[^:]+\.lua)$')                      { $p = $matches['p']; $l = '';           $lastPath = $p }
            else {
                $problems += "line ${docLine}: UNPARSEABLE [src:] payload '$clean' (expected path.lua:LINE[-RANGE][,...])"
                continue
            }

            if (-not $p) {
                $problems += "line ${docLine}: bare ':$l' continuation with no preceding path in the same tag"
                continue
            }

            $refCount++
            $full = Join-Path $SourceRoot ($p -replace '/', '\')
            if (-not (Test-Path -LiteralPath $full)) {
                $problems += "line ${docLine}: FILE NOT FOUND '$p' (cited :$l)"
                continue
            }
            $max = ([System.IO.File]::ReadAllLines($full)).Count
            $bad = @()
            foreach ($tok in ($l -split ',')) {
                if ($tok -eq '') { continue }
                foreach ($n in ($tok -split '-')) {
                    if ($n -match '^[0-9]+$' -and [int]$n -gt $max) { $bad += $n }
                }
            }
            if ($bad.Count -gt 0) {
                $problems += ("line ${docLine}: LINE OUT OF RANGE in '$p' (file has $max lines): " + ($bad -join ','))
            }
        }
    }

    return @{ problems = $problems; refs = $refCount }
}

# ============================================================================
# SELF-TEST — plant an uncited claim (ERROR), an [unverified] (counted), and a
# properly cited claim (pass); assert each behaves correctly.
# ============================================================================
function Invoke-SelfTest {
    Write-Host "[check_mechanics_citations] SELF-TEST" -ForegroundColor Cyan

    $fixture = @"
# MECHANICS (self-test fixture)

Intro prose bullet that should be EXEMPT (outside any Domain section):
- This is framing, not a mechanic claim, and must NOT error.

## Domain: Self-test

- Properly cited claim about a thing. [src: scripts/foo/bar.lua:42]
- A claim carried from a memory note. [memory: reference_self_test]
- A planted UNCITED claim that must ERROR because it has no tag at all.
- An explicit honest gap that is allowed but counted. [unverified]

### A subheading that must NOT disable the lint

- A planted UNCITED claim under a SUBHEADING that must ERROR.
- A cited claim under a subheading. [src: scripts/foo/baz.lua:7]

## Known gaps

- A known gap that is correctly filed. [unverified]
- A planted UNCITED claim in known-gaps that must ERROR.
"@

    $res = Invoke-MechanicsScan -Text $fixture

    $uncitedFired = ($res.errors | Where-Object { $_ -match 'planted UNCITED claim that must ERROR because it has no tag' }).Count -gt 0
    $knownGapUncitedFired = ($res.errors | Where-Object { $_ -match "UNCITED claim in 'Known gaps'" }).Count -gt 0
    $citedDidNotError = ($res.errors | Where-Object { $_ -match 'scripts/foo/bar.lua' }).Count -eq 0
    $exemptDidNotError = ($res.errors | Where-Object { $_ -match 'framing, not a mechanic' }).Count -eq 0
    # A `###` subheading must SUBDIVIDE a Domain, not silently end the linted region.
    $subheadingUncitedFired = ($res.errors | Where-Object { $_ -match 'UNCITED claim under a SUBHEADING' }).Count -gt 0
    $subheadingCitedDidNotError = ($res.errors | Where-Object { $_ -match 'scripts/foo/baz.lua' }).Count -eq 0
    # 2 [unverified] expected (one Domain, one Known gaps)
    $unverifiedCounted = ($res.unverified -eq 2)
    # exactly the 3 planted uncited bullets should error (Domain, subheading, Known gaps)
    $exactlyTwoErrors = ($res.errors.Count -eq 3)

    function Write-SelfTestResult([string]$label, [bool]$passed, [string]$suffix) {
        $result = if ($passed) { 'PASS' } else { 'FAIL' }
        $color = if ($passed) { 'Green' } else { 'Red' }
        Write-Host ("{0}{1}{2}" -f $label, $result, $suffix) -ForegroundColor $color
    }

    Write-Host ""
    Write-SelfTestResult "  Uncited Domain claim -> ERROR:          " $uncitedFired ""
    Write-SelfTestResult "  Uncited Known-gaps claim -> ERROR:      " $knownGapUncitedFired ""
    Write-SelfTestResult "  Cited [src] claim -> no error:          " $citedDidNotError ""
    Write-SelfTestResult "  Exempt framing bullet -> no error:      " $exemptDidNotError ""
    Write-SelfTestResult "  Uncited under '###' subheading -> ERROR:" $subheadingUncitedFired ""
    Write-SelfTestResult "  Cited under '###' subheading -> no err: " $subheadingCitedDidNotError ""
    Write-SelfTestResult "  [unverified] counted (expected 2):      " $unverifiedCounted (" (got {0})" -f $res.unverified)
    Write-SelfTestResult "  Exactly 3 errors (no over/under-fire):  " $exactlyTwoErrors (" (got {0})" -f $res.errors.Count)
    Write-Host ""
    Write-Host "  Raised errors:" -ForegroundColor DarkGray
    foreach ($e in $res.errors) { Write-Host "    - $e" -ForegroundColor DarkGray }

    $allPass = $uncitedFired -and $knownGapUncitedFired -and $citedDidNotError -and $exemptDidNotError -and $subheadingUncitedFired -and $subheadingCitedDidNotError -and $unverifiedCounted -and $exactlyTwoErrors
    if ($allPass) {
        Write-Host "[check_mechanics_citations] SELF-TEST PASSED" -ForegroundColor Green
        return 0
    } else {
        Write-Host "[check_mechanics_citations] SELF-TEST FAILED" -ForegroundColor Red
        return 2
    }
}

# ============================================================================
# MAIN
# ============================================================================
if ($SelfTest) { exit (Invoke-SelfTest) }

$repoRoot = (Resolve-Path $RepoRoot).Path
$mechPath = Join-Path $repoRoot "docs\MECHANICS.md"
$sourceDocuments = [ordered]@{
    'docs/MECHANICS.md'                  = $mechPath
    'docs/BUG_CLASSES.md'                = (Join-Path $repoRoot 'docs\BUG_CLASSES.md')
    'docs/WEAPON_APPEARANCE_STANDARD.md' = (Join-Path $repoRoot 'docs\WEAPON_APPEARANCE_STANDARD.md')
    'docs/CROSS_MOD_ARCHITECTURE.md'      = (Join-Path $repoRoot 'docs\CROSS_MOD_ARCHITECTURE.md')
}

foreach ($doc in $sourceDocuments.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $doc.Value)) {
        Write-Host "[check_mechanics_citations] FATAL: source-citation document not found at $($doc.Value)" -ForegroundColor Red
        exit 2
    }
}

$text = Read-FileUtf8 $mechPath

# ---- [src:] resolution (blocking where the decompiled tree is present) ----
# Returns: 0 clean, 1 skipped (no source tree), 2 unresolved citations.
function Invoke-SrcResolveReport {
    param([string]$Text, [string]$SourceRoot, [string]$DocumentLabel)

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        $msg = "[check_mechanics_citations] decompiled source not at $SourceRoot"
        if ($RequireSource) {
            Write-Host "$msg — -RequireSource given, so this is an ERROR." -ForegroundColor Red
            return 2
        }
        Write-Host "$msg — SKIPPING [src:] resolution (expected in CI; this repo is checked out alone)." -ForegroundColor Yellow
        return 1
    }

    $r = Invoke-SrcResolve -Text $Text -SourceRoot $SourceRoot
    if ($r.problems.Count -gt 0) {
        Write-Host ("[check_mechanics_citations] ERRORS ({0}) in {1} — unresolvable [src:] citations:" -f $r.problems.Count, $DocumentLabel) -ForegroundColor Red
        foreach ($p in $r.problems) { Write-Host "  X $p" -ForegroundColor Red }
        Write-Host ""
        Write-Host "  A [src:] tag must open. Fix the path/line, or downgrade the claim to [unverified]." -ForegroundColor Red
        return 2
    }
    Write-Host ("[src:] resolution ({0}): {1}/{1} refs resolve against the decompiled tree" -f $DocumentLabel, $r.refs) -ForegroundColor Green
    return 0
}

function Invoke-AllSrcResolveReports {
    param([System.Collections.IDictionary]$Documents, [string]$SourceRoot)

    $failed = $false
    foreach ($doc in $Documents.GetEnumerator()) {
        $docText = Read-FileUtf8 $doc.Value
        $rc = Invoke-SrcResolveReport -Text $docText -SourceRoot $SourceRoot -DocumentLabel $doc.Key
        if ($rc -eq 2) { $failed = $true }
    }
    return $(if ($failed) { 2 } else { 0 })
}

if ($ResolveSrc) {
    $srcRc = Invoke-AllSrcResolveReports -Documents $sourceDocuments -SourceRoot $VtSrc
    exit ($(if ($srcRc -eq 2) { 2 } else { 0 }))
}

$res = Invoke-MechanicsScan -Text $text

# ---- Report ----
Write-Host ""
Write-Host "============ check_mechanics_citations ============" -ForegroundColor Cyan
Write-Host ("Cited factual bullets:   {0}" -f $res.cited) -ForegroundColor Green
Write-Host ("Known gaps [unverified]: {0}" -f $res.unverified) -ForegroundColor Yellow
$errorColor = if ($res.errors.Count -gt 0) { 'Red' } else { 'Green' }
Write-Host ("Uncited (ERROR):         {0}" -f $res.errors.Count) -ForegroundColor $errorColor
Write-Host ""

if (-not $Quiet -and $res.domains.Count -gt 0) {
    Write-Host "Per-domain breakdown (cited / unverified):" -ForegroundColor DarkGray
    foreach ($d in ($res.domains.Keys | Sort-Object)) {
        $h = $res.domains[$d]
        Write-Host ("  {0,-32} {1} / {2}" -f $d, $h.cited, $h.unverified) -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Tag SHAPE and tag RESOLUTION are independent failures; report both before exiting.
$srcRc = Invoke-AllSrcResolveReports -Documents $sourceDocuments -SourceRoot $VtSrc
Write-Host ""

if ($res.errors.Count -gt 0) {
    Write-Host "[check_mechanics_citations] ERRORS ($($res.errors.Count)) — uncited mechanic claims:" -ForegroundColor Red
    foreach ($e in $res.errors) { Write-Host "  X $e" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Every factual bullet MUST carry a provenance tag, or be [unverified]." -ForegroundColor Red
    Write-Host "  Do NOT fill a gap from model knowledge — cite source, dump, memory, or write [unverified]." -ForegroundColor Red
    exit 2
}

if ($srcRc -eq 2) {
    Write-Host "[check_mechanics_citations] FAILED — every MECHANICS bullet is tagged, but a [src:] citation does not resolve in the checked documentation set." -ForegroundColor Red
    exit 2
}

if ($res.unverified -gt 0) {
    Write-Host "[check_mechanics_citations] OK — all factual bullets cited. $($res.unverified) honest gap(s) remain ([unverified] backlog)." -ForegroundColor Yellow
    exit 0
}

Write-Host "[check_mechanics_citations] OK — all factual bullets cited; no [unverified] gaps." -ForegroundColor Green
exit 0
