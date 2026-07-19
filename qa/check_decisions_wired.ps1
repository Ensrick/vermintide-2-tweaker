# check_decisions_wired.ps1 — cross-checks weapon_tweaker's CROSS_CHARACTER_PORT_DECISIONS.md
# against the three implementation surfaces, so documented-but-unwired ports are
# made VISIBLE and MECHANICAL instead of trusted to memory.
#
# Motivating memory note (2026-05-30): feedback_decisions_must_bake_immediately —
# "Every user port/weapon decision MUST be wired into unlock_map + checkboxes +
#  loc keys IN THE SAME TURN. Documenting in a decisions doc != implementing.
#  User flagged after 50+ documented decisions had no in-game toggles."
#
# The three surfaces (for weapon_tweaker):
#   1. weapon_unlock_map   in wt_unlock_data.lua  (career -> { weapon_key, ... })
#   2. VMF checkboxes      in weapon_tweaker_data.lua          (setting_id = "unlock_<career>_<key>")
#   3. Loc keys            in weapon_tweaker_localization.lua  (unlock_<career>_<key> = { en=... })
#
# THREE-WAY categorization per (receiver, weapon_key) decision:
#   REGRESSION (error) — doc says shipped/confirmed-working, but missing from a
#                        receiver career's unlock_map OR checkbox/loc.
#   PENDING   (info)   — doc says "To ADD" but not yet in unlock_map. The backlog
#                        the memory note targets. Headline metric, not an error.
#   LEAK      (error)  — doc says Skipped/DO-NOT-ADD/Identical/Removed but the key
#                        IS present in that receiver's careers.
#   WIRED     (pass)   — shipped/To-ADD decision fully present on all the
#                        receiver's careers + checkbox + loc. PARTIAL if present
#                        on some-but-not-all careers.
#   ORPHAN    (warn)   — (career, key) in unlock_map with NO decision in the doc.
#   UNCLASSIFIABLE     — doc row whose intended state can't be determined; logged
#                        for the maintainer to normalize the doc (honesty over
#                        false precision — that is the whole point of this gate).
#
# Exit codes (mirrors check_localization.ps1 semantics):
#   0 = clean (no REGRESSION/LEAK; PENDING/orphans/partials OK in the "0" sense?)
#   1 = orphans or partials present (advisory)
#   2 = any REGRESSION or LEAK (actionable defect)
#
# Per the task spec: 0 = no REGRESSION/LEAK, 1 = orphans or partials present,
# 2 = any REGRESSION or LEAK.
#
# See qa/CHECKS.md (row wired by maintainer).

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Receiver -> career-id set. Confirmed against weapon_unlock_map career keys.
# ---------------------------------------------------------------------------
$ReceiverCareers = [ordered]@{
    "Kruber"    = @("es_mercenary", "es_huntsman", "es_knight", "es_questingknight")
    "Bardin"    = @("dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer")
    "Kerillian" = @("we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister")
    # Saltzpyre's ONLY receiver section in the doc is "## Receiver: Saltzpyre
    # (non-WP)" (CROSS_CHARACTER_PORT_DECISIONS.md:395-399), whose every batch is
    # decided for the three non-WP careers ONLY ("x 3 careers" throughout). Warrior
    # Priest (wh_priest) is treated as its own receiver ("## Receiver: Warrior
    # Priest", doc:624) and is handled via $WarriorPriestCareers below. Including
    # wh_priest here double-counted it and fired ~34 false PARTIALs demanding a
    # wh_priest wiring the doc never decided (and which its FORBIDDEN-ranged rule
    # would bar). Keep the general Saltzpyre receiver non-WP-only.
    "Saltzpyre" = @("wh_captain", "wh_bountyhunter", "wh_zealot")
    "Sienna"    = @("bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer")
}
# Warrior Priest is a Saltzpyre career (wh_priest) but the doc treats it as its
# own receiver section. Map its weapons onto wh_priest only.
$WarriorPriestCareers = @("wh_priest")

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# ---------------------------------------------------------------------------
# Resolve a receiver name (free text from a header) to the canonical receiver
# key in $ReceiverCareers, or $null if unknown.
# ---------------------------------------------------------------------------
function Resolve-Receiver([string]$text) {
    if ($text -match '(?i)warrior\s*priest') { return "WarriorPriest" }
    foreach ($r in $ReceiverCareers.Keys) {
        if ($text -match "(?i)\b$r\b") { return $r }
    }
    return $null
}

function Get-CareersForReceiver([string]$receiver) {
    if ($receiver -eq "WarriorPriest") { return $WarriorPriestCareers }
    return $ReceiverCareers[$receiver]
}

# ---------------------------------------------------------------------------
# Classify a section header / table-context line into a decision-state bucket.
# Returns one of: SHIPPED, TOADD, SKIP, $null (ambiguous/not-a-decision-section).
# Logs ambiguous-looking headers to $script:ambiguousHeaders.
# ---------------------------------------------------------------------------
function Classify-Section([string]$header) {
    $h = $header
    # SKIP family: Skipped / DO NOT ADD / Identical(s) / Removed / superseded / FORBIDDEN
    if ($h -match '(?i)\b(do\s*not\s*add|skipped|skip\b|identical|removed|superseded|forbidden)') {
        return "SKIP"
    }
    # SHIPPED family: Confirmed working / shipped / already shipped
    if ($h -match '(?i)(confirmed\s*working|already\s*shipped|\bshipped\b)') {
        return "SHIPPED"
    }
    # TOADD family: "To ADD", "To Add to Kruber", "Batch D ADD decisions", "add to Kruber".
    # SKIP is checked first above, so "do not add" never reaches here. (audit 2026-06-07)
    if ($h -match '(?i)(\bto\s*add\b|\badd\s+decisions?\b|\badd\s+to\b)') {
        return "TOADD"
    }
    return $null
}

# ---------------------------------------------------------------------------
# Extract backticked weapon keys from a markdown table cell.
# Keys look like `dr_2h_cog_hammer`, `wh_crossbow`, etc. A cell may carry
# multiple keys (e.g. an es_deus_01 family note) — return all that look like
# real weapon keys (prefix es_/dr_/we_/wh_/bw_ + word chars).
# ---------------------------------------------------------------------------
function Get-KeysFromCell([string]$cell) {
    $keys = [System.Collections.ArrayList]::new()
    foreach ($m in [regex]::Matches($cell, '`([a-z]{2}_[a-z0-9_]+)`')) {
        $k = $m.Groups[1].Value
        if ($k -match '^(es|dr|we|wh|bw)_') { [void]$keys.Add($k) }
    }
    return ,$keys.ToArray()
}

# ---------------------------------------------------------------------------
# Parse the decisions markdown into a list of decision records:
#   @{ Receiver=; Key=; State=SHIPPED|TOADD|SKIP; Source="<file>:<line>"; Header= }
# Only the FIRST backticked key in a "Source weapon" cell is the join key — but
# tables vary; we take the first real-looking weapon key in the row's FIRST
# non-empty cell. If a row's first cell has no key, we scan the whole row and,
# if exactly one key is present, use it; if multiple, the first; if none, skip.
# ---------------------------------------------------------------------------
function Parse-Decisions([string]$path) {
    $lines = (Read-FileUtf8 $path) -split "`r?`n"
    $decisions = @()
    $currentReceiver = $null
    $currentState = $null
    $currentHeader = $null
    # audit 2026-06-07: a "> **SUPERSEDED ...**" blockquote retires the SKIP table
    # directly below it (the rows are kept for history only). This flag suppresses
    # that one table so its retired skips don't fire as false LEAKs.
    $supersededNextSkip = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1

        # --- "> **SUPERSEDED ...**" blockquote -> the SKIP table immediately below
        #     is retained-for-history, not an active decision.
        if ($line -match '^\s*>\s*\*\*SUPERSEDED') {
            $supersededNextSkip = $true
            continue
        }

        # --- Top-level receiver section: "## Receiver: Kruber"
        if ($line -match '^\s*##\s+Receiver:\s*(.+?)\s*$') {
            $rec = Resolve-Receiver $matches[1]
            $currentReceiver = $rec
            $currentState = $null
            $currentHeader = $line.Trim()
            continue
        }

        # --- Any other top-level "##" section that is NOT a receiver resets context,
        #     so prose tables under a different "## ..." heading (e.g. "## Bake status")
        #     aren't scanned as decision rows still attributed to the previous receiver.
        #     (audit 2026-06-07: 3 Sienna "Bake status" rows were mis-scanned this way.)
        if ($line -match '^\s*##\s+' -and $line -notmatch '^\s*###') {
            $currentReceiver = $null
            $currentState = $null
            $currentHeader = $line.Trim()
            continue
        }

        # --- Sub-section header (### ...). Two shapes:
        #     "### Bardin weapons -> Kruber"  / "### Kruber -> Kerillian"  => receiver is the AFTER side
        #     "### Confirmed working / shipped"  / "### To ADD ..."        => state only
        if ($line -match '^\s*###\s+(.+?)\s*$') {
            $hdr = $matches[1]
            $currentHeader = $line.Trim()
            # Arrow form sets receiver = the target (right of arrow). Doc uses
            # the literal arrow char; also tolerate ASCII "->".
            if ($hdr -match '(.+?)\s*(?:→|->)\s*(.+)') {
                $rhs = $matches[2]
                $rec = Resolve-Receiver $rhs
                if ($rec) { $currentReceiver = $rec }
            }
            # "Bardin weapons -> Kruber" already handled above; "X weapons to Kruber"
            # without arrow: detect "to <Receiver>" trailing.
            elseif ($hdr -match '(?i)\bto\s+(Kruber|Bardin|Kerillian|Saltzpyre|Sienna|Warrior\s*Priest)\b') {
                $rec = Resolve-Receiver $matches[1]
                if ($rec) { $currentReceiver = $rec }
            }
            # State from the header (To ADD / Skipped / shipped etc.)
            $st = Classify-Section $hdr
            $currentState = $st
            continue
        }

        # --- Bold pseudo-headers used as table captions:
        #     "**To ADD to Kruber + animation target:**"
        #     "**Identicals - DO NOT ADD:**"
        #     "**Identicals / superseded - DO NOT ADD:**"
        #     "**Pending decision:**"
        if ($line -match '^\s*\*\*(.+?)\*\*\s*:?\s*$') {
            $cap = $matches[1]
            $currentHeader = $line.Trim()
            # A bold caption ALWAYS introduces a fresh table context. Set the state to
            # its classification -- INCLUDING $null when it doesn't classify -- so a
            # prior "**... SKIP ...**" caption never silently bleeds into a following
            # "**Batch X ADD decisions:**" table. (audit 2026-06-07: the stale-SKIP
            # carryover here produced 36 false LEAKs and the spurious exit 2.)
            $currentState = Classify-Section $cap
            # A SKIP table directly under a "> **SUPERSEDED**" banner is retired
            # history — route it to a non-actionable SUPERSEDED state so its rows are
            # ignored (the keys were later re-added by the superseding section).
            if ($currentState -eq "SKIP" -and $supersededNextSkip) {
                $currentState = "SUPERSEDED"
            }
            $supersededNextSkip = $false
            # A bold caption may also carry an explicit receiver ("To ADD to Kruber")
            if ($cap -match '(?i)\bto\s+(Kruber|Bardin|Kerillian|Saltzpyre|Sienna|Warrior\s*Priest)\b') {
                $rec = Resolve-Receiver $matches[1]
                if ($rec) { $currentReceiver = $rec }
            }
            continue
        }

        # --- Inline "Removed" bullet lines (e.g. "- WH Hammer (`wh_1h_hammer`) - REMOVED")
        if ($line -match '^\s*[-*]\s' -and $line -match '(?i)\bremoved\b') {
            $keys = Get-KeysFromCell $line
            if ($currentReceiver -and $keys.Count -ge 1) {
                $decisions += [pscustomobject]@{
                    Receiver = $currentReceiver
                    Key      = $keys[0]
                    State    = "SKIP"
                    Source   = "{0}:{1}" -f (Split-Path $path -Leaf), $lineNo
                    Header   = "(inline REMOVED bullet)"
                    Raw      = $line.Trim()
                }
            }
            continue
        }

        # --- Markdown table data row: starts with "|", contains backticked key(s).
        #     Skip the header row ("| Source weapon | ... |") and the separator
        #     ("|---|---|").
        if ($line -match '^\s*\|') {
            if ($line -match '^\s*\|[\s:|-]+\|?\s*$') { continue }  # separator row
            $cells = $line.Trim().Trim('|') -split '\|'
            # Header row heuristic: no backticks AND contains words like "Source"/"Target"
            $rowHasKey = $line -match '`[a-z]{2}_'
            if (-not $rowHasKey) { continue }

            # Determine the join key. Prefer the first cell with a key.
            $joinKey = $null
            $allKeysInRow = @()
            foreach ($c in $cells) {
                $ks = Get-KeysFromCell $c
                $allKeysInRow += $ks
                if (-not $joinKey -and $ks.Count -ge 1) { $joinKey = $ks[0] }
            }

            if (-not $currentReceiver) {
                # A keyed table row outside any receiver context — log it.
                $script:noReceiverRows += ("{0}:{1}  {2}" -f (Split-Path $path -Leaf), $lineNo, $line.Trim())
                continue
            }
            # Rows in a SUPERSEDED (retired) SKIP table are history — ignore. (audit 2026-06-07)
            if ($currentState -eq "SUPERSEDED") { continue }
            # An "already present ... natively / no new entry needed" skip asserts the
            # key is INTENTIONALLY already in the unlock_map (native/pre-existing); its
            # presence is correct, not a leak. (audit 2026-06-07)
            if ($currentState -eq "SKIP" -and $line -match '(?i)\balready\s+present\b') { continue }
            if (-not $currentState) {
                # Keyed row under an unclassifiable section header — UNCLASSIFIABLE.
                if ($joinKey) {
                    $script:unclassifiable += [pscustomobject]@{
                        Receiver = $currentReceiver
                        Key      = $joinKey
                        Source   = "{0}:{1}" -f (Split-Path $path -Leaf), $lineNo
                        Header   = $currentHeader
                        Reason   = "table row under a section with no resolvable decision-state"
                    }
                }
                continue
            }
            if ($joinKey) {
                $decisions += [pscustomobject]@{
                    Receiver = $currentReceiver
                    Key      = $joinKey
                    State    = $currentState
                    Source   = "{0}:{1}" -f (Split-Path $path -Leaf), $lineNo
                    Header   = $currentHeader
                    Raw      = $line.Trim()
                }
            }
        }
    }
    return $decisions
}

# ---------------------------------------------------------------------------
# Parse weapon_unlock_map from a Lua file. Returns a hashtable:
#   { career_id = @(weapon_key, ...) }
# Robust against multi-line entries, trailing commas, and -- comments.
# ---------------------------------------------------------------------------
function Parse-UnlockMap([string]$path) {
    $text = Read-FileUtf8 $path
    $map = @{}

    # Strip -- line comments FIRST so the docstring's prose mention of
    # "weapon_unlock_map = {...}" doesn't get matched as the real table, and so
    # commented-out careers/keys aren't parsed. (Block comments --[[ ]] are
    # handled crudely: drop everything up to the `return {`.)
    $text = [regex]::Replace($text, '--\[\[.*?\]\]', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $text = [regex]::Replace($text, '--[^\r\n]*', '')

    # Isolate the weapon_unlock_map = { ... } block by brace matching.
    $startMatch = [regex]::Match($text, 'weapon_unlock_map\s*=\s*\{')
    if (-not $startMatch.Success) { return $map }
    $idx = $startMatch.Index + $startMatch.Length
    $depth = 1
    $sb = New-Object System.Text.StringBuilder
    while ($idx -lt $text.Length -and $depth -gt 0) {
        $ch = $text[$idx]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { break } }
        [void]$sb.Append($ch)
        $idx++
    }
    $block = $sb.ToString()

    # Strip -- line comments so commented careers/keys don't get parsed.
    $block = [regex]::Replace($block, '--[^\r\n]*', '')

    # Match: career_id = { "k1", "k2", ... }   (the inner braces don't nest here)
    foreach ($m in [regex]::Matches($block, '([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{([^{}]*)\}')) {
        $career = $m.Groups[1].Value
        $body = $m.Groups[2].Value
        $keys = @()
        foreach ($km in [regex]::Matches($body, '"([^"]+)"')) {
            $keys += $km.Groups[1].Value
        }
        $map[$career] = $keys
    }
    return $map
}

# ---------------------------------------------------------------------------
# Parse the set of unlock_<career>_<key> setting_ids present in *_data.lua.
# ---------------------------------------------------------------------------
function Parse-CheckboxSet([string]$path) {
    $text = Read-FileUtf8 $path
    $set = @{}
    foreach ($m in [regex]::Matches($text, 'setting_id\s*=\s*"(unlock_[A-Za-z0-9_]+)"')) {
        $set[$m.Groups[1].Value] = $true
    }
    return $set
}

# ---------------------------------------------------------------------------
# Parse the set of unlock_<career>_<key> loc keys present in *_localization.lua.
# ---------------------------------------------------------------------------
function Parse-LocSet([string]$path) {
    $text = Read-FileUtf8 $path
    $set = @{}
    foreach ($m in [regex]::Matches($text, '(?m)^\s*(unlock_[A-Za-z0-9_]+)\s*=')) {
        $set[$m.Groups[1].Value] = $true
    }
    return $set
}

# ---------------------------------------------------------------------------
# Staleness advisory for the checker-consumed decisions doc.
#
# This checker reads CROSS_CHARACTER_PORT_DECISIONS.md as GROUND TRUTH for which
# cross-character ports are live work. When a rescinded row is left in the doc it
# is trusted as real work for as long as nobody re-verifies it (that is exactly
# how stale rescinded rows read as live work for weeks). The doc carries a
#   checker-consumed: verified-current YYYY-MM-DD
# header line stamped when it was last reconciled against the three wiring
# surfaces. Warn (ADVISORY ONLY - never touches the exit code) when that date is
# missing, unparseable, or older than $MaxAgeDays so the maintainer re-verifies
# and re-stamps it. Silent when the header is present and fresh.
# ---------------------------------------------------------------------------
function Test-CheckerConsumedFreshness {
    param([string]$Path, [int]$MaxAgeDays = 30)
    $leaf = Split-Path $Path -Leaf
    $text = Read-FileUtf8 $Path
    $m = [regex]::Match($text, 'checker-consumed:\s*verified-current\s+(\d{4}-\d{2}-\d{2})')
    if (-not $m.Success) {
        Write-Host ("[check_decisions_wired] STALENESS WARNING (advisory): {0} has no 'checker-consumed: verified-current YYYY-MM-DD' header. This checker trusts the doc as ground truth; add the header once you have re-verified the rows." -f $leaf) -ForegroundColor Yellow
        return
    }
    $stamp = [datetime]::MinValue
    $ok = [datetime]::TryParseExact($m.Groups[1].Value, 'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None, [ref]$stamp)
    if (-not $ok) {
        Write-Host ("[check_decisions_wired] STALENESS WARNING (advisory): {0} has an unparseable checker-consumed date '{1}' (want YYYY-MM-DD)." -f $leaf, $m.Groups[1].Value) -ForegroundColor Yellow
        return
    }
    $ageDays = [int]([datetime]::UtcNow.Date - $stamp.Date).TotalDays
    if ($ageDays -gt $MaxAgeDays) {
        Write-Host ("[check_decisions_wired] STALENESS WARNING (advisory): {0} was last verified-current {1} ({2} days ago, > {3}). Re-verify the decisions against unlock_map + checkboxes + loc and bump the header date." -f $leaf, $m.Groups[1].Value, $ageDays, $MaxAgeDays) -ForegroundColor Yellow
    }
}

# ===========================================================================
#  SELF-TEST — planted fixtures verify REGRESSION + LEAK fire.
# ===========================================================================
function Invoke-SelfTest {
    Write-Host "===== check_decisions_wired SELF-TEST =====" -ForegroundColor Cyan
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cdw_selftest_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $docPath = Join-Path $tmp "DECISIONS.md"
        $mapPath = Join-Path $tmp "unlock.lua"
        $dataPath = Join-Path $tmp "data.lua"
        $locPath = Join-Path $tmp "loc.lua"

        # Doc: one SHIPPED key (planted missing from map -> REGRESSION),
        #      one SKIP key (planted present in map -> LEAK).
        @'
## Receiver: Kruber

### Confirmed working / shipped

| Source weapon (key) | Target (3P) | Notes |
|---|---|---|
| Planted Shipped (`dr_planted_shipped`) | whatever | should be wired but is NOT |

### Skipped - identical to Kruber natives

| Skipped | Identical to |
|---|---|
| Planted Skip (`dr_planted_skip`) | something |
'@ | Set-Content -Path $docPath -Encoding UTF8

        # Map: dr_planted_skip present (LEAK), dr_planted_shipped absent (REGRESSION).
        @'
return {
    weapon_unlock_map = {
        es_mercenary      = { "dr_planted_skip" },
        es_huntsman       = { "dr_planted_skip" },
        es_knight         = { "dr_planted_skip" },
        es_questingknight = { "dr_planted_skip" },
    },
}
'@ | Set-Content -Path $mapPath -Encoding UTF8

        '-- no checkboxes' | Set-Content -Path $dataPath -Encoding UTF8
        'return {}' | Set-Content -Path $locPath -Encoding UTF8

        $result = Invoke-DecisionsCheck -DocPath $docPath -MapPath $mapPath -DataPath $dataPath -LocPath $locPath -Quiet
        $regHit = $result.Regressions | Where-Object { $_.Key -eq "dr_planted_shipped" }
        $leakHit = $result.Leaks | Where-Object { $_.Key -eq "dr_planted_skip" }

        $pass = $true
        if ($regHit) { Write-Host "  PASS: REGRESSION fired for planted shipped-but-missing key (dr_planted_shipped)" -ForegroundColor Green }
        else { Write-Host "  FAIL: REGRESSION did NOT fire for dr_planted_shipped" -ForegroundColor Red; $pass = $false }

        if ($leakHit) { Write-Host "  PASS: LEAK fired for planted skip-but-present key (dr_planted_skip)" -ForegroundColor Green }
        else { Write-Host "  FAIL: LEAK did NOT fire for dr_planted_skip" -ForegroundColor Red; $pass = $false }

        if ($pass) { Write-Host "[self-test] OK" -ForegroundColor Green; return 0 }
        else { Write-Host "[self-test] FAILED" -ForegroundColor Red; return 2 }
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ===========================================================================
#  CORE — given the four file paths, run the cross-check and return a result
#  object. Reused by both the live run and the self-test (with mock paths).
# ===========================================================================
function Invoke-DecisionsCheck {
    param(
        [string]$DocPath,
        [string]$MapPath,
        [string]$DataPath,
        [string]$LocPath,
        [switch]$Quiet
    )

    $script:ambiguousHeaders = @()
    $script:noReceiverRows = @()
    $script:unclassifiable = @()

    $decisions = Parse-Decisions $DocPath
    $unlockMap = Parse-UnlockMap $MapPath
    $checkboxes = Parse-CheckboxSet $DataPath
    $locKeys = Parse-LocSet $LocPath

    # Build a quick lookup: career -> { key -> $true }
    $mapLookup = @{}
    foreach ($career in $unlockMap.Keys) {
        $h = @{}
        foreach ($k in $unlockMap[$career]) { $h[$k] = $true }
        $mapLookup[$career] = $h
    }

    $regressions = @()
    $leaks = @()
    $pending = @()
    $wired = @()
    $partials = @()

    # Collapse duplicate decisions (same receiver+key+state appears in multiple
    # batch tables). Keep first occurrence's Source. Conflicting states for the
    # same (receiver,key) -> UNCLASSIFIABLE.
    $byRK = @{}
    foreach ($d in $decisions) {
        $rk = "$($d.Receiver)|$($d.Key)"
        if (-not $byRK.ContainsKey($rk)) {
            $byRK[$rk] = @($d)
        } else {
            $byRK[$rk] += $d
        }
    }

    $finalDecisions = @()
    foreach ($rk in $byRK.Keys) {
        $group = $byRK[$rk]
        $states = $group | Select-Object -ExpandProperty State -Unique
        if ($states.Count -gt 1) {
            # Conflict: same (receiver,key) classified differently in two sections.
            # SHIPPED+TOADD is reconcilable (both "should be present") -> treat as
            # the stronger SHIPPED. SKIP vs anything-present is a genuine conflict.
            $hasSkip = $states -contains "SKIP"
            $hasPresent = ($states -contains "SHIPPED") -or ($states -contains "TOADD")
            if ($hasSkip -and $hasPresent) {
                $script:unclassifiable += [pscustomobject]@{
                    Receiver = $group[0].Receiver
                    Key      = $group[0].Key
                    Source   = ($group | ForEach-Object { $_.Source }) -join ", "
                    Header   = "(conflicting sections)"
                    Reason   = "doc classifies this both as present (shipped/to-add) AND skip/identical/removed"
                }
                continue
            }
            # SHIPPED + TOADD -> prefer SHIPPED
            $chosen = $group | Where-Object { $_.State -eq "SHIPPED" } | Select-Object -First 1
            if (-not $chosen) { $chosen = $group[0] }
            $finalDecisions += $chosen
        } else {
            $finalDecisions += $group[0]
        }
    }

    # Track which (career,key) pairs are "accounted for" by a decision (for orphan detection).
    $accounted = @{}

    foreach ($d in $finalDecisions) {
        $careers = Get-CareersForReceiver $d.Receiver
        if (-not $careers) { continue }
        $key = $d.Key

        # Mark accounted.
        foreach ($c in $careers) { $accounted["$c|$key"] = $true }

        if ($d.State -eq "SKIP") {
            # LEAK if present in ANY of the receiver's careers.
            $present = @()
            foreach ($c in $careers) {
                if ($mapLookup.ContainsKey($c) -and $mapLookup[$c].ContainsKey($key)) { $present += $c }
            }
            if ($present.Count -gt 0) {
                $leaks += [pscustomobject]@{
                    Receiver = $d.Receiver; Key = $key; Careers = $present
                    Source = $d.Source; Detail = "marked Skip/Identical/Removed but present in unlock_map"
                }
            }
            continue
        }

        # SHIPPED or TOADD: should be present on ALL the receiver's careers + checkbox + loc.
        $missingMap = @()
        $missingCb = @()
        $missingLoc = @()
        foreach ($c in $careers) {
            $inMap = $mapLookup.ContainsKey($c) -and $mapLookup[$c].ContainsKey($key)
            $cbId = "unlock_${c}_${key}"
            $inCb = $checkboxes.ContainsKey($cbId)
            $inLoc = $locKeys.ContainsKey($cbId)
            if (-not $inMap) { $missingMap += $c }
            if (-not $inCb) { $missingCb += $c }
            if (-not $inLoc) { $missingLoc += $c }
        }

        $anyPresent = ($missingMap.Count -lt $careers.Count)
        $fullyWired = ($missingMap.Count -eq 0 -and $missingCb.Count -eq 0 -and $missingLoc.Count -eq 0)

        if ($d.State -eq "SHIPPED") {
            if ($fullyWired) {
                $wired += [pscustomobject]@{ Receiver = $d.Receiver; Key = $key; State = "SHIPPED"; Source = $d.Source }
            } else {
                $regressions += [pscustomobject]@{
                    Receiver = $d.Receiver; Key = $key; Source = $d.Source
                    MissingMap = $missingMap; MissingCheckbox = $missingCb; MissingLoc = $missingLoc
                }
            }
        } else {
            # TOADD
            if ($fullyWired) {
                $wired += [pscustomobject]@{ Receiver = $d.Receiver; Key = $key; State = "TOADD"; Source = $d.Source }
            } elseif ($anyPresent) {
                # Partially wired To-ADD: some careers wired, others not.
                $partials += [pscustomobject]@{
                    Receiver = $d.Receiver; Key = $key; Source = $d.Source
                    MissingMap = $missingMap; MissingCheckbox = $missingCb; MissingLoc = $missingLoc
                }
            } else {
                # Not present at all -> PENDING backlog.
                $pending += [pscustomobject]@{ Receiver = $d.Receiver; Key = $key; Source = $d.Source }
            }
        }
    }

    # ORPHANS: a genuine CROSS-CHARACTER (career,key) in unlock_map that no
    # decision accounts for — the reverse drift (undocumented port).
    #
    # We deliberately EXCLUDE same-character self-wields: a career's prefix
    # (es_/dr_/we_/wh_/bw_) matching the weapon key's prefix means the weapon is
    # that character's own native (or a same-character variant). The decisions
    # doc only tracks cross-CHARACTER ports, so same-character entries in the map
    # are baseline and would otherwise drown the orphan list (373 false hits).
    $charPrefixRe = '^(es|dr|we|wh|bw)_'
    $orphans = @()
    foreach ($career in $unlockMap.Keys) {
        $cm = [regex]::Match($career, $charPrefixRe)
        $careerChar = if ($cm.Success) { $cm.Groups[1].Value } else { $null }
        foreach ($key in $unlockMap[$career]) {
            $km = [regex]::Match($key, $charPrefixRe)
            $keyChar = if ($km.Success) { $km.Groups[1].Value } else { $null }
            # Same-character native -> not a cross-character port -> skip.
            if ($careerChar -and $keyChar -and $careerChar -eq $keyChar) { continue }
            if (-not $accounted.ContainsKey("$career|$key")) {
                $orphans += [pscustomobject]@{ Career = $career; Key = $key }
            }
        }
    }

    return [pscustomobject]@{
        Regressions      = $regressions
        Leaks            = $leaks
        Pending          = $pending
        Wired            = $wired
        Partials         = $partials
        Orphans          = $orphans
        Unclassifiable   = $script:unclassifiable
        NoReceiverRows   = $script:noReceiverRows
        DecisionCount    = $finalDecisions.Count
        UnlockMap        = $unlockMap
    }
}

# ===========================================================================
#  MAIN
# ===========================================================================
if ($SelfTest) {
    exit (Invoke-SelfTest)
}

$repoRoot = (Resolve-Path $RepoRoot).Path
$wtBase = Join-Path $repoRoot "weapon_tweaker"
$docPath = Join-Path $wtBase "CROSS_CHARACTER_PORT_DECISIONS.md"
$mapPath = Join-Path $wtBase "scripts\mods\weapon_tweaker\wt_unlock_data.lua"
$dataPath = Join-Path $wtBase "scripts\mods\weapon_tweaker\weapon_tweaker_data.lua"
$locPath = Join-Path $wtBase "scripts\mods\weapon_tweaker\weapon_tweaker_localization.lua"

foreach ($p in @($docPath, $mapPath, $dataPath, $locPath)) {
    if (-not (Test-Path $p)) {
        Write-Host "[check_decisions_wired] FATAL: required file not found: $p" -ForegroundColor Red
        exit 2
    }
}

# Advisory only - prints a warning if the decisions doc's checker-consumed header
# is missing/stale; never changes the exit code below.
Test-CheckerConsumedFreshness -Path $docPath

$r = Invoke-DecisionsCheck -DocPath $docPath -MapPath $mapPath -DataPath $dataPath -LocPath $locPath -Quiet:$Quiet

# ---- Report ----
Write-Host ""
Write-Host "================ check_decisions_wired ================" -ForegroundColor Cyan
Write-Host ("Decisions parsed:   {0}" -f $r.DecisionCount)
Write-Host ("  WIRED (pass):     {0}" -f $r.Wired.Count) -ForegroundColor Green
Write-Host ("  PENDING (backlog):{0}" -f $r.Pending.Count) -ForegroundColor Yellow
Write-Host ("  PARTIAL:          {0}" -f $r.Partials.Count) -ForegroundColor Yellow
Write-Host ("  REGRESSION:       {0}" -f $r.Regressions.Count) -ForegroundColor Red
Write-Host ("  LEAK:             {0}" -f $r.Leaks.Count) -ForegroundColor Red
Write-Host ("  ORPHAN:           {0}" -f $r.Orphans.Count) -ForegroundColor Yellow
Write-Host ("  UNCLASSIFIABLE:   {0}" -f $r.Unclassifiable.Count) -ForegroundColor Magenta
Write-Host ""

if ($r.Regressions.Count -gt 0) {
    Write-Host "REGRESSIONS (doc says shipped/confirmed-working, but NOT fully wired):" -ForegroundColor Red
    foreach ($x in $r.Regressions | Sort-Object Receiver, Key) {
        Write-Host ("  X [{0}] {1}   ({2})" -f $x.Receiver, $x.Key, $x.Source) -ForegroundColor Red
        if ($x.MissingMap.Count)      { Write-Host ("      missing from unlock_map: {0}" -f ($x.MissingMap -join ", ")) -ForegroundColor Red }
        if ($x.MissingCheckbox.Count) { Write-Host ("      missing checkbox:        {0}" -f ($x.MissingCheckbox -join ", ")) -ForegroundColor Red }
        if ($x.MissingLoc.Count)      { Write-Host ("      missing loc key:         {0}" -f ($x.MissingLoc -join ", ")) -ForegroundColor Red }
    }
    Write-Host ""
}

if ($r.Leaks.Count -gt 0) {
    Write-Host "LEAKS (doc says Skip/Identical/Removed, but PRESENT in unlock_map):" -ForegroundColor Red
    foreach ($x in $r.Leaks | Sort-Object Receiver, Key) {
        Write-Host ("  X [{0}] {1}   present in: {2}   ({3})" -f $x.Receiver, $x.Key, ($x.Careers -join ", "), $x.Source) -ForegroundColor Red
    }
    Write-Host ""
}

if ($r.Partials.Count -gt 0) {
    Write-Host "PARTIAL (decided, wired on SOME but not all of the receiver's careers):" -ForegroundColor Yellow
    foreach ($x in $r.Partials | Sort-Object Receiver, Key) {
        Write-Host ("  ! [{0}] {1}   ({2})" -f $x.Receiver, $x.Key, $x.Source) -ForegroundColor Yellow
        if ($x.MissingMap.Count)      { Write-Host ("      missing from unlock_map: {0}" -f ($x.MissingMap -join ", ")) -ForegroundColor Yellow }
        if ($x.MissingCheckbox.Count) { Write-Host ("      missing checkbox:        {0}" -f ($x.MissingCheckbox -join ", ")) -ForegroundColor Yellow }
        if ($x.MissingLoc.Count)      { Write-Host ("      missing loc key:         {0}" -f ($x.MissingLoc -join ", ")) -ForegroundColor Yellow }
    }
    Write-Host ""
}

if ($r.Pending.Count -gt 0) {
    Write-Host ("PENDING BACKLOG ({0} documented decisions NOT yet wired anywhere):" -f $r.Pending.Count) -ForegroundColor Yellow
    foreach ($x in $r.Pending | Sort-Object Receiver, Key) {
        Write-Host ("  - [{0}] {1}   ({2})" -f $x.Receiver, $x.Key, $x.Source) -ForegroundColor DarkYellow
    }
    Write-Host ""
}

if ($r.Orphans.Count -gt 0) {
    Write-Host ("ORPHANS ({0} unlock_map entries with NO decision in the doc):" -f $r.Orphans.Count) -ForegroundColor Yellow
    foreach ($x in $r.Orphans | Sort-Object Career, Key) {
        Write-Host ("  ? {0}  /  {1}" -f $x.Career, $x.Key) -ForegroundColor DarkYellow
    }
    Write-Host ""
}

if ($r.Unclassifiable.Count -gt 0) {
    Write-Host "UNCLASSIFIABLE - doc needs clarification (NOT bucketed; maintainer to normalize):" -ForegroundColor Magenta
    foreach ($x in $r.Unclassifiable | Sort-Object Receiver, Key) {
        Write-Host ("  ~ [{0}] {1}   ({2})  -- {3}" -f $x.Receiver, $x.Key, $x.Source, $x.Reason) -ForegroundColor Magenta
        if ($x.Header) { Write-Host ("      under header: {0}" -f $x.Header) -ForegroundColor DarkGray }
    }
    Write-Host ""
}

if ($r.NoReceiverRows.Count -gt 0 -and -not $Quiet) {
    Write-Host "NOTE - keyed table rows seen outside any receiver context (ignored):" -ForegroundColor DarkGray
    foreach ($x in $r.NoReceiverRows) { Write-Host ("  . {0}" -f $x) -ForegroundColor DarkGray }
    Write-Host ""
}

# ---- Exit code ----
if ($r.Regressions.Count -gt 0 -or $r.Leaks.Count -gt 0) {
    Write-Host "[check_decisions_wired] ERRORS - REGRESSION/LEAK present. Fix before relying on the decisions doc as ground truth." -ForegroundColor Red
    exit 2
}
if ($r.Orphans.Count -gt 0 -or $r.Partials.Count -gt 0) {
    Write-Host "[check_decisions_wired] WARNINGS - orphans/partials present (advisory). PENDING backlog is the headline metric." -ForegroundColor Yellow
    exit 1
}
Write-Host "[check_decisions_wired] OK - no regressions or leaks." -ForegroundColor Green
exit 0
