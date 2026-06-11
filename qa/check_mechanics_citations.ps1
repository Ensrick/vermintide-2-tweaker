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
# USAGE
#   .\qa\check_mechanics_citations.ps1
#       -RepoRoot <repo>   (default: parent of qa/)
#       -Quiet
#       -SelfTest          run the planted-fault self-test and exit
# ============================================================================

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
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
        # any OTHER heading (## / ###) closes the claim-bearing region
        if ($trim -match '^#{1,6}\s') {
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

## Known gaps

- A known gap that is correctly filed. [unverified]
- A planted UNCITED claim in known-gaps that must ERROR.
"@

    $res = Invoke-MechanicsScan -Text $fixture

    $uncitedFired = ($res.errors | Where-Object { $_ -match 'planted UNCITED claim that must ERROR because it has no tag' }).Count -gt 0
    $knownGapUncitedFired = ($res.errors | Where-Object { $_ -match "UNCITED claim in 'Known gaps'" }).Count -gt 0
    $citedDidNotError = ($res.errors | Where-Object { $_ -match 'scripts/foo/bar.lua' }).Count -eq 0
    $exemptDidNotError = ($res.errors | Where-Object { $_ -match 'framing, not a mechanic' }).Count -eq 0
    # 2 [unverified] expected (one Domain, one Known gaps)
    $unverifiedCounted = ($res.unverified -eq 2)
    # exactly the 2 planted uncited bullets should error
    $exactlyTwoErrors = ($res.errors.Count -eq 2)

    Write-Host ""
    Write-Host ("  Uncited Domain claim -> ERROR:          {0}" -f ($uncitedFired ? 'PASS' : 'FAIL')) -ForegroundColor ($uncitedFired ? 'Green' : 'Red')
    Write-Host ("  Uncited Known-gaps claim -> ERROR:      {0}" -f ($knownGapUncitedFired ? 'PASS' : 'FAIL')) -ForegroundColor ($knownGapUncitedFired ? 'Green' : 'Red')
    Write-Host ("  Cited [src] claim -> no error:          {0}" -f ($citedDidNotError ? 'PASS' : 'FAIL')) -ForegroundColor ($citedDidNotError ? 'Green' : 'Red')
    Write-Host ("  Exempt framing bullet -> no error:      {0}" -f ($exemptDidNotError ? 'PASS' : 'FAIL')) -ForegroundColor ($exemptDidNotError ? 'Green' : 'Red')
    Write-Host ("  [unverified] counted (expected 2):      {0} (got {1})" -f (($unverifiedCounted ? 'PASS' : 'FAIL'), $res.unverified)) -ForegroundColor ($unverifiedCounted ? 'Green' : 'Red')
    Write-Host ("  Exactly 2 errors (no over/under-fire):  {0} (got {1})" -f (($exactlyTwoErrors ? 'PASS' : 'FAIL'), $res.errors.Count)) -ForegroundColor ($exactlyTwoErrors ? 'Green' : 'Red')
    Write-Host ""
    Write-Host "  Raised errors:" -ForegroundColor DarkGray
    foreach ($e in $res.errors) { Write-Host "    - $e" -ForegroundColor DarkGray }

    $allPass = $uncitedFired -and $knownGapUncitedFired -and $citedDidNotError -and $exemptDidNotError -and $unverifiedCounted -and $exactlyTwoErrors
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

if (-not (Test-Path $mechPath)) {
    Write-Host "[check_mechanics_citations] FATAL: substrate not found at $mechPath" -ForegroundColor Red
    exit 2
}

$text = Read-FileUtf8 $mechPath
$res = Invoke-MechanicsScan -Text $text

# ---- Report ----
Write-Host ""
Write-Host "============ check_mechanics_citations ============" -ForegroundColor Cyan
Write-Host ("Cited factual bullets:   {0}" -f $res.cited) -ForegroundColor Green
Write-Host ("Known gaps [unverified]: {0}" -f $res.unverified) -ForegroundColor Yellow
Write-Host ("Uncited (ERROR):         {0}" -f $res.errors.Count) -ForegroundColor ($res.errors.Count -gt 0 ? 'Red' : 'Green')
Write-Host ""

if (-not $Quiet -and $res.domains.Count -gt 0) {
    Write-Host "Per-domain breakdown (cited / unverified):" -ForegroundColor DarkGray
    foreach ($d in ($res.domains.Keys | Sort-Object)) {
        $h = $res.domains[$d]
        Write-Host ("  {0,-32} {1} / {2}" -f $d, $h.cited, $h.unverified) -ForegroundColor DarkGray
    }
    Write-Host ""
}

if ($res.errors.Count -gt 0) {
    Write-Host "[check_mechanics_citations] ERRORS ($($res.errors.Count)) — uncited mechanic claims:" -ForegroundColor Red
    foreach ($e in $res.errors) { Write-Host "  X $e" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Every factual bullet MUST carry a provenance tag, or be [unverified]." -ForegroundColor Red
    Write-Host "  Do NOT fill a gap from model knowledge — cite source, dump, memory, or write [unverified]." -ForegroundColor Red
    exit 2
}

if ($res.unverified -gt 0) {
    Write-Host "[check_mechanics_citations] OK — all factual bullets cited. $($res.unverified) honest gap(s) remain ([unverified] backlog)." -ForegroundColor Yellow
    exit 0
}

Write-Host "[check_mechanics_citations] OK — all factual bullets cited; no [unverified] gaps." -ForegroundColor Green
exit 0
