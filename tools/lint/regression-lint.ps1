# tools/lint/regression-lint.ps1
#
# Static regression lint for the vermintide-2-tweaker monorepo. Scans every
# mod's `scripts/` for patterns that have shipped as recurring bugs (see
# CHANGELOGs + memory notes referenced per-check below) and emits file:line
# findings. Refuses to deploy when any check errors.
#
# Per CLAUDE.md (PROJECT_STANDARDS): use this BEFORE every Workshop upload.
# This is read-only — never modifies mod source.
#
# Usage:
#   pwsh -File .\regression-lint.ps1                    # all 16 mods, all checks
#   pwsh -File .\regression-lint.ps1 -Mod weapon_tweaker
#   pwsh -File .\regression-lint.ps1 -Check forward-ref
#   pwsh -File .\regression-lint.ps1 -WarningsAsErrors
#   pwsh -File .\regression-lint.ps1 -Quiet
#   pwsh -File .\regression-lint.ps1 -SelfTest
#
# Exit codes:
#   0 - clean (no errors; warnings only if -WarningsAsErrors not set)
#   1 - errors found, or self-test failed
#
# Constraints (per memory):
#   - Pure PowerShell 7 (no Python, no node, no LuaJIT).
#   - UTF-8 reads via [System.IO.File]::ReadAllText (PS 5.1 mangling).
#   - Must complete all 16 mods in <5s on SSD.

[CmdletBinding()]
param(
    [string]$Mod,
    [string]$Check,
    [switch]$WarningsAsErrors,
    [switch]$Quiet,
    [switch]$SelfTest,
    [string]$RepoRoot
)

$ErrorActionPreference = 'Stop'

# Resolve repo root: default to two dirs up from this script.
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

# ---- mod inventory (kept in sync with publish-release.ps1 / lint-mod.ps1) ----
$Script:KnownMods = @(
    'weapon_tweaker', 'chaos_wastes_tweaker', 'general_tweaker', 'cosmetics_tweaker',
    'dynamic_cosmetic_portraits', 'career_tweaker', 'enemy_tweaker',
    'character_weapon_variants', 'crafting_in_modded', 'la_prefix_patch',
    'event_tweaker', 'modded_progression', 'lobby_tweaker', 'buff_tweaker',
    'material_hijack_patched', 'verminious_dreams_lighting'
)

$Script:AllChecks = @(
    'forward-ref',
    'unescaped-percent',
    'hook-safe-duplicate',
    'unit-actor-zero-index',
    'strict-table-lookup',
    'lua-200-locals',
    'base-class-hook',
    'dropdown-options-reuse'
)

# ============================================================================
# Shared helpers
# ============================================================================

# Compile a C# helper for the comment/string blanking — the PowerShell-side
# regex MatchEvaluator + StringBuilder delegate was the dominant runtime
# (1.2s on a 200KB Lua file). Same algorithm, ~30x faster.
if (-not ('VT2LintHelpers' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Text;

public static class VT2LintHelpers {
    // Single-char dispatch: blank to space, preserving newlines and CRs.
    private static void BlankSpan(StringBuilder sb, string src, int start, int end) {
        for (int p = start; p <= end && p < src.Length; p++) {
            char c = src[p];
            if (c == '\n' || c == '\r') sb.Append(c);
            else sb.Append(' ');
        }
    }

    // Strip comments only (long-bracket --[[==[ ... ]==]] and -- ... \n).
    // String literals are preserved verbatim. The strictly-Lua tokenizer
    // logic mirrors the original char-by-char PowerShell version.
    public static string StripComments(string text) {
        var sb = new StringBuilder(text.Length);
        int n = text.Length;
        int i = 0;
        while (i < n) {
            char c = text[i];
            char next = (i + 1 < n) ? text[i + 1] : '\0';

            // --[==[ ... ]==] long comment
            if (c == '-' && next == '-' && i + 2 < n && text[i + 2] == '[') {
                int j = i + 3;
                int eq = 0;
                while (j < n && text[j] == '=') { eq++; j++; }
                if (j < n && text[j] == '[') {
                    int k = j + 1;
                    bool closed = false;
                    int end = n - 1;
                    while (k < n) {
                        if (text[k] == ']') {
                            int m = k + 1;
                            int eq2 = 0;
                            while (m < n && text[m] == '=') { eq2++; m++; }
                            if (eq2 == eq && m < n && text[m] == ']') {
                                closed = true; end = m; break;
                            }
                        }
                        k++;
                    }
                    if (!closed) end = n - 1;
                    BlankSpan(sb, text, i, end);
                    i = end + 1;
                    continue;
                }
            }

            // -- single-line comment
            if (c == '-' && next == '-') {
                while (i < n && text[i] != '\n') { sb.Append(' '); i++; }
                continue;
            }

            // Short string — copy verbatim (handle escapes).
            if (c == '"' || c == '\'') {
                char quote = c;
                sb.Append(c); i++;
                while (i < n) {
                    char cc = text[i];
                    if (cc == '\\') {
                        sb.Append(cc);
                        if (i + 1 < n) { sb.Append(text[i + 1]); i += 2; continue; }
                        else { i++; break; }
                    }
                    if (cc == quote) { sb.Append(cc); i++; break; }
                    if (cc == '\n') { sb.Append(cc); i++; break; }
                    sb.Append(cc); i++;
                }
                continue;
            }

            sb.Append(c); i++;
        }
        return sb.ToString();
    }

    // Blank interior of every short string ("..." / '...') and long-bracket
    // string ([==[ ... ]==]) in already-comment-stripped Lua. Delimiters are
    // kept; interior chars become spaces (newlines preserved).
    public static string BlankStringInteriors(string text) {
        var sb = new StringBuilder(text.Length);
        int n = text.Length;
        int i = 0;
        while (i < n) {
            char c = text[i];

            // Long-bracket string [==[ ... ]==]
            if (c == '[') {
                int j = i + 1;
                int eq = 0;
                while (j < n && text[j] == '=') { eq++; j++; }
                if (j < n && text[j] == '[') {
                    int k = j + 1;
                    bool closed = false;
                    int end = n - 1;
                    while (k < n) {
                        if (text[k] == ']') {
                            int m = k + 1;
                            int eq2 = 0;
                            while (m < n && text[m] == '=') { eq2++; m++; }
                            if (eq2 == eq && m < n && text[m] == ']') {
                                closed = true; end = m; break;
                            }
                        }
                        k++;
                    }
                    if (!closed) end = n - 1;
                    // Keep delimiters, blank interior.
                    sb.Append('[');
                    for (int p = 0; p < eq; p++) sb.Append('=');
                    sb.Append('[');
                    BlankSpan(sb, text, j + 1, end - eq - 1);
                    sb.Append(']');
                    for (int p = 0; p < eq; p++) sb.Append('=');
                    sb.Append(']');
                    i = end + 1;
                    continue;
                }
            }

            // Short string
            if (c == '"' || c == '\'') {
                char quote = c;
                sb.Append(c); i++;
                while (i < n) {
                    char cc = text[i];
                    if (cc == '\\') {
                        // Eat escape pair, emit spaces.
                        sb.Append(' ');
                        if (i + 1 < n) { sb.Append(' '); i += 2; continue; }
                        else { i++; break; }
                    }
                    if (cc == quote) { sb.Append(cc); i++; break; }
                    if (cc == '\n') { sb.Append(cc); i++; break; }
                    sb.Append(' '); i++;
                }
                continue;
            }

            sb.Append(c); i++;
        }
        return sb.ToString();
    }
}
"@
}

function Read-LuaText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# Replaces every block-comment and single-line-comment with whitespace,
# preserving newlines so reported line numbers stay accurate. Short string
# literals are kept intact (we need to scan their contents for the
# unescaped-percent check); long-bracket strings are also kept.
function Strip-LuaComments {
    param([string]$Text)
    return [VT2LintHelpers]::StripComments($Text)
}

# Blank interior of every short string and long-bracket string in already-
# comment-stripped Lua. Newlines preserved. Used for checks that scan code
# patterns (string contents would otherwise produce false positives).
#
# Uses C# helpers compiled once for speed — pure-PowerShell regex delegates
# in this loop were the dominant runtime (1.2s on a 200KB file).
function Blank-LuaStringInteriors {
    param([string]$Text)
    return [VT2LintHelpers]::BlankStringInteriors($Text)
}

function Get-ModLuaFiles {
    param([string]$ModFolder)
    $scriptDir = Join-Path $ModFolder 'scripts'
    if (-not (Test-Path $scriptDir)) { return @() }
    return Get-ChildItem -Path $scriptDir -Recurse -Filter *.lua -File | ForEach-Object { $_.FullName }
}

function To-RelPath {
    param([string]$Path)
    if ($Path.StartsWith($RepoRoot)) {
        return $Path.Substring($RepoRoot.Length).TrimStart('\','/')
    }
    return $Path
}

# Findings carry (Severity, Check, File, Line, Message). Helpers wrap this.
function New-Finding {
    param(
        [ValidateSet('error','warning')] [string]$Severity,
        [string]$Check,
        [string]$File,
        [int]$Line,
        [string]$Message
    )
    return [pscustomobject]@{
        Severity = $Severity
        Check    = $Check
        File     = $File
        Line     = $Line
        Message  = $Message
    }
}

# ============================================================================
# Check 1: forward-ref
# ----------------------------------------------------------------------------
# Lua hoists `local NAME; function NAME(...) end` (forward decl) but NOT
# `local function NAME(...)` — closures defined above the latter see the name
# as a nil global. The mod-lint script has the deepest version of this check.
# Memory: feedback_lua_forward_reference.md.
# ============================================================================
function Invoke-Check-ForwardRef {
    param([string]$File, [string[]]$Lines)

    $findings = @()
    $lines = $Lines

    $localDefs   = @{}   # name -> first def line
    $forwardDecl = @{}   # name -> earliest forward-decl line

    $rxLocalFn1 = [regex]'^\s*local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('
    $rxLocalFn2 = [regex]'^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\('
    $rxForwardDecl = [regex]'^\s*local\s+([A-Za-z_][A-Za-z0-9_,\s]*?)\s*$'

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $m = $rxLocalFn1.Match($line)
        if ($m.Success) {
            $name = $m.Groups[1].Value
            if (-not $localDefs.ContainsKey($name)) { $localDefs[$name] = $i + 1 }
            continue
        }
        $m = $rxLocalFn2.Match($line)
        if ($m.Success) {
            $name = $m.Groups[1].Value
            if (-not $localDefs.ContainsKey($name)) { $localDefs[$name] = $i + 1 }
            continue
        }
        if ($line -notmatch '=' -and $line -notmatch '\bfunction\b') {
            $m = $rxForwardDecl.Match($line)
            if ($m.Success) {
                $namesRaw = $m.Groups[1].Value
                foreach ($n in ($namesRaw -split ',')) {
                    $nn = $n.Trim()
                    if ($nn -match '^[A-Za-z_][A-Za-z0-9_]*$') {
                        if (-not $forwardDecl.ContainsKey($nn)) { $forwardDecl[$nn] = $i + 1 }
                    }
                }
            }
        }
    }

    if ($localDefs.Count -eq 0) { return $findings }

    # Find anonymous-function closures (`function(`) and walk a balanced
    # opens/closes counter to find the closing `end`.
    #
    # Lua block grammar (relevant subset, every opener takes exactly one `end`):
    #   function ... end
    #   if ... then ... [elseif ...] [else] end
    #   for ... do ... end          <-- `do` does NOT open its own block here
    #   while ... do ... end        <-- ditto
    #   repeat ... until            <-- closes with `until`, not `end`
    #   do ... end                  <-- standalone `do` opens a block
    #
    # Naive counts of `do` double-count for/while constructs. Track the
    # most-recent for/while occurrence and consume the next `do` after it
    # as belonging to that construct (not as a block-opener of its own).

    # Pre-tokenize every line ONCE: a list of (opens, closes, kicksPending,
    # consumesPending). `kicksPending` is true if the line ends with a
    # for/while-clause that hasn't seen its `do` yet — we handle that in
    # the rare cross-line case below by tracking carry-over pending state.
    # Simpler: per-line, compute (opens, closes) given an incoming `pending`
    # state; emit outgoing `pending` state.

    $rxAnonFn = [regex]'(^|[^A-Za-z0-9_])function\s*\('
    $tokRx    = [regex]'\b(function|if|while|for|repeat|do|end|until)\b'

    # Per-line precomputed token sequence (array of token-strings); also the
    # column-after-each-token for the start-line skip logic.
    $lineCount = $lines.Count
    $lineTokens  = New-Object 'string[][]' $lineCount
    $lineTokEnds = New-Object 'int[][]'    $lineCount
    for ($i = 0; $i -lt $lineCount; $i++) {
        $ms = $tokRx.Matches($lines[$i])
        $cnt = $ms.Count
        $words = New-Object 'string[]' $cnt
        $ends  = New-Object 'int[]'    $cnt
        for ($j = 0; $j -lt $cnt; $j++) {
            $words[$j] = $ms[$j].Groups[1].Value
            $ends[$j]  = $ms[$j].Index + $ms[$j].Length
        }
        $lineTokens[$i]  = $words
        $lineTokEnds[$i] = $ends
    }

    $closures = New-Object 'System.Collections.Generic.List[object]'
    for ($i = 0; $i -lt $lineCount; $i++) {
        $line = $lines[$i]
        $startMatches = $rxAnonFn.Matches($line)
        if ($startMatches.Count -eq 0) { continue }

        foreach ($sm in $startMatches) {
            $startLine = $i + 1
            $startCol  = $sm.Index + $sm.Length

            # Determine token index at which to begin scanning on the start line
            # (skip everything at or before `function(` itself).
            $skipUpTo = 0
            $ends = $lineTokEnds[$i]
            for ($k = 0; $k -lt $ends.Length; $k++) {
                if ($ends[$k] -le $startCol) { $skipUpTo = $k + 1 } else { break }
            }

            $balance = 1
            $pending = $false

            # Apply remaining tokens on the start line.
            $words = $lineTokens[$i]
            for ($k = $skipUpTo; $k -lt $words.Length; $k++) {
                $w = $words[$k]
                if     ($w -eq 'function') { $balance++ }
                elseif ($w -eq 'if')       { $balance++ }
                elseif ($w -eq 'repeat')   { $balance++ }
                elseif ($w -eq 'for')      { $balance++; $pending = $true }
                elseif ($w -eq 'while')    { $balance++; $pending = $true }
                elseif ($w -eq 'do')       { if ($pending) { $pending = $false } else { $balance++ } }
                elseif ($w -eq 'end')      { $balance-- }
                elseif ($w -eq 'until')    { $balance-- }
            }

            $endLine = $startLine
            $j = $i + 1
            while ($balance -gt 0 -and $j -lt $lineCount) {
                $words = $lineTokens[$j]
                for ($k = 0; $k -lt $words.Length; $k++) {
                    $w = $words[$k]
                    if     ($w -eq 'function') { $balance++ }
                    elseif ($w -eq 'if')       { $balance++ }
                    elseif ($w -eq 'repeat')   { $balance++ }
                    elseif ($w -eq 'for')      { $balance++; $pending = $true }
                    elseif ($w -eq 'while')    { $balance++; $pending = $true }
                    elseif ($w -eq 'do')       { if ($pending) { $pending = $false } else { $balance++ } }
                    elseif ($w -eq 'end')      { $balance-- }
                    elseif ($w -eq 'until')    { $balance-- }
                }
                $endLine = $j + 1
                $j++
            }
            [void]$closures.Add(@{ StartLine = $startLine; EndLine = $endLine })
        }
    }

    if ($closures.Count -eq 0) { return $findings }

    # Build a sorted-by-StartLine closure list for innermost-cover lookup.
    # Force array even when there's only one closure (single-item pipeline
    # unwrap would give a hashtable whose `.Count` reflects key count, not 1).
    $closuresArr = @($closures.ToArray() | Sort-Object { $_.StartLine })

    # For each candidate local-fn name, regex-find every reference in the file
    # (line-by-line). For each ref, find the enclosing closure(s). If any
    # enclosing closure starts before the def line AND no forward decl, flag.
    # We only need to check names that have a def — limit the regex.
    if ($localDefs.Count -eq 0) { return $findings }
    $namePattern = '\b(' + (($localDefs.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
    $rxNames = [regex]$namePattern

    $seen = @{}
    for ($i = 0; $i -lt $lineCount; $i++) {
        $line = $lines[$i]
        $ms = $rxNames.Matches($line)
        if ($ms.Count -eq 0) { continue }
        $lineNo = $i + 1
        foreach ($m in $ms) {
            $name = $m.Groups[1].Value
            $defLine = $localDefs[$name]
            if ($lineNo -ge $defLine) { continue }   # reference appears at-or-below def — fine
            # Find the latest closure (by StartLine) that contains $lineNo.
            # Iterate from highest-StartLine down: first cover wins (= innermost).
            $enclosingStart = -1
            for ($c = $closuresArr.Count - 1; $c -ge 0; $c--) {
                $cl = $closuresArr[$c]
                if ($cl.StartLine -gt $lineNo) { continue }
                if ($cl.EndLine -ge $lineNo) {
                    $enclosingStart = $cl.StartLine
                    break
                }
            }
            if ($enclosingStart -lt 0) { continue }   # reference is at top-level, not in a closure
            if ($enclosingStart -ge $defLine) { continue }   # closure starts at-or-after def
            if ($forwardDecl.ContainsKey($name) -and $forwardDecl[$name] -lt $enclosingStart) { continue }
            $key = "$enclosingStart|$name"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $findings += (New-Finding -Severity 'error' -Check 'forward-ref' `
                -File $File -Line $enclosingStart `
                -Message ("closure references local fn '{0}' defined later at line {1} (no forward decl)" -f $name, $defLine))
        }
    }

    return $findings
}

# ============================================================================
# Check 2: unescaped-percent
# ----------------------------------------------------------------------------
# Localization strings are passed through Localize(), which formats via
# string.format eventually. A literal "%" must be doubled to "%%" or the
# format spec swallows the next char. Past offenders: wt v0.12.63, crt
# v0.2.36, et v0.5.2, gt v0.2.35, ct v0.7.79, lobby_tweaker v0.1.1.
# ============================================================================
function Invoke-Check-UnescapedPercent {
    param([string]$File, [string[]]$Lines)

    $findings = @()
    if ($File -notlike '*_localization.lua') { return $findings }
    $lines = $Lines

    $rxStr = [regex]'"([^"\\]*(?:\\.[^"\\]*)*)"|''([^''\\]*(?:\\.[^''\\]*)*)'''

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($m in $rxStr.Matches($line)) {
            $body = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
            if ($body.Length -eq 0) { continue }
            # Skip strings that are just keys (no spaces, all alphanum/_) — those
            # appear on the left-hand side of an `=` but our regex catches them
            # too. A `%` in such a string would still be a bug, so leave the
            # check in place; we just need to scan body for solitary %.
            for ($p = 0; $p -lt $body.Length; $p++) {
                if ($body[$p] -eq '%') {
                    if ($p + 1 -lt $body.Length -and $body[$p + 1] -eq '%') {
                        $p++   # skip the pair
                        continue
                    }
                    # Single % - emit one finding per string
                    $findings += (New-Finding -Severity 'error' -Check 'unescaped-percent' `
                        -File $File -Line ($i + 1) `
                        -Message ("string '{0}' contains a single '%' — use '%%' to escape (Localize formats via string.format)" -f $body))
                    break
                }
            }
        }
    }

    return $findings
}

# ============================================================================
# Check 3: hook-safe-duplicate
# ----------------------------------------------------------------------------
# VMF silently drops the second mod:hook* on the same (Class, method). Per
# memory feedback_vmf_hook_safe_no_chain.md and reference_ct_husk_hook_shadow_tpe.md.
# Whitelist nearby `-- LINT_OK_REHOOK: <reason>` comments.
# ============================================================================
function Invoke-Check-HookSafeDuplicate {
    param([array]$Files)   # array of @{Path; Raw; Stripped; CommentStripped}

    $findings = @()
    $hooks = @()
    # Class identifier may be quoted "X" or 'X' or a bare identifier (incl. dotted).
    $rxHook = [regex]'\bmod\s*:\s*(hook|hook_safe|hook_origin)\s*\(\s*(?:"([^"]+)"|''([^'']+)''|([A-Za-z_][A-Za-z0-9_.]*))\s*,\s*(?:"([^"]+)"|''([^'']+)'')'

    foreach ($f in $Files) {
        $rawLines = $f.RawLines
        # Use CommentStripped lines (comments blanked, strings PRESERVED) — we need
        # the literal "ClassName"/"method" string contents to match.
        $strippedLines = $f.CommentStrippedLines
        for ($i = 0; $i -lt $strippedLines.Count; $i++) {
            $line = $strippedLines[$i]
            foreach ($h in $rxHook.Matches($line)) {
                $method = if ($h.Groups[5].Success) { $h.Groups[5].Value } else { $h.Groups[6].Value }
                $cls = $null
                if ($h.Groups[2].Success)     { $cls = $h.Groups[2].Value }
                elseif ($h.Groups[3].Success) { $cls = $h.Groups[3].Value }
                elseif ($h.Groups[4].Success) { $cls = $h.Groups[4].Value }
                if (-not $cls) { continue }

                # Whitelist: -- LINT_OK_REHOOK: ... on this or previous 2 lines.
                $hasWhitelist = $false
                for ($w = [Math]::Max(0, $i - 2); $w -le [Math]::Min($rawLines.Count - 1, $i + 1); $w++) {
                    if ($rawLines[$w] -match 'LINT_OK_REHOOK\s*:') {
                        $hasWhitelist = $true; break
                    }
                }
                if ($hasWhitelist) { continue }

                $hooks += [pscustomobject]@{
                    File = $f.Path; Line = $i + 1; Class = $cls; Method = $method
                }
            }
        }
    }

    $grouped = $hooks | Group-Object -Property @{ E={ "$($_.Class)::$($_.Method)" } }
    foreach ($g in $grouped) {
        $unique = $g.Group | Sort-Object File, Line -Unique
        $count = ($unique | Measure-Object).Count
        if ($count -gt 1) {
            foreach ($h in $unique) {
                $sitesList = ($unique | ForEach-Object { ("{0}:{1}" -f (To-RelPath $_.File), $_.Line) }) -join ', '
                $findings += (New-Finding -Severity 'error' -Check 'hook-safe-duplicate' `
                    -File $h.File -Line $h.Line `
                    -Message ("duplicate hook on {0}.{1} ({2} sites: {3}) — VMF silently drops the 2nd; whitelist with '-- LINT_OK_REHOOK: <reason>'" -f $h.Class, $h.Method, $count, $sitesList))
            }
        }
    }

    return $findings
}

# ============================================================================
# Check 4: unit-actor-zero-index
# ----------------------------------------------------------------------------
# Stingray Unit.actor / Unit.num_actors are 1-indexed. `for i = 0` near them
# means we'll either skip the last actor or hit a nil. Memory:
# reference_vt2_unit_actor_one_indexed.md.
# ============================================================================
function Invoke-Check-UnitActorZeroIndex {
    param([string]$File, [string[]]$Lines)

    $findings = @()
    $lines = $Lines

    $rxZeroFor = [regex]'\bfor\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*0\s*,'
    $rxActor   = [regex]'\bUnit\s*\.\s*(actor|num_actors)\b'

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($rxZeroFor.IsMatch($lines[$i])) {
            $lo = [Math]::Max(0, $i - 3)
            $hi = [Math]::Min($lines.Count - 1, $i + 3)
            for ($j = $lo; $j -le $hi; $j++) {
                if ($rxActor.IsMatch($lines[$j])) {
                    $findings += (New-Finding -Severity 'error' -Check 'unit-actor-zero-index' `
                        -File $File -Line ($i + 1) `
                        -Message ("'for i = 0, ...' near Unit.actor / Unit.num_actors (line {0}) — Stingray actor indices are 1-based" -f ($j + 1)))
                    break
                }
            }
        }
    }

    return $findings
}

# ============================================================================
# Check 5: strict-table-lookup
# ----------------------------------------------------------------------------
# BuffTemplates and NetworkLookup.<lookup> install strict __index = error()
# metatables. Membership checks like `if BuffTemplates[name]` outside rawget()
# crash. Memory: reference_vt2_strict_lookup_rawget.md (career_tweaker v0.3.4).
# ============================================================================
function Invoke-Check-StrictTableLookup {
    param([string]$File, [string[]]$Lines)

    $findings = @()
    $lines = $Lines

    $rxBuffLookup = [regex]'\bBuffTemplates\s*\[\s*([^\]]+?)\s*\]'
    $rxNetLookup  = [regex]'\bNetworkLookup\s*\.\s*[A-Za-z_][A-Za-z0-9_]*\s*\[\s*([^\]]+?)\s*\]'

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($m in $rxBuffLookup.Matches($line)) {
            # If the surrounding context is `... = something` (write), skip.
            $idx = $m.Index
            $tail = $line.Substring($idx + $m.Length)
            # If the next non-space char is `=` and NOT `==`, it's a write.
            $afterMatch = $tail -match '^\s*=\s*[^=]'
            if ($afterMatch) { continue }
            # rawget(...) on same or previous line?
            $window = $line
            if ($i -gt 0) { $window = $lines[$i - 1] + "`n" + $window }
            if ($window -match '\brawget\s*\(\s*BuffTemplates') { continue }
            $findings += (New-Finding -Severity 'error' -Check 'strict-table-lookup' `
                -File $File -Line ($i + 1) `
                -Message ("BuffTemplates[$($m.Groups[1].Value)] outside rawget() — strict __index will fatal on missing key"))
        }
        foreach ($m in $rxNetLookup.Matches($line)) {
            $idx = $m.Index
            $tail = $line.Substring($idx + $m.Length)
            $afterMatch = $tail -match '^\s*=\s*[^=]'
            if ($afterMatch) { continue }
            $window = $line
            if ($i -gt 0) { $window = $lines[$i - 1] + "`n" + $window }
            if ($window -match '\brawget\s*\(\s*NetworkLookup') { continue }
            $findings += (New-Finding -Severity 'error' -Check 'strict-table-lookup' `
                -File $File -Line ($i + 1) `
                -Message ("NetworkLookup.<lookup>[$($m.Groups[1].Value)] outside rawget() — strict __index will fatal on missing key"))
        }
    }

    return $findings
}

# ============================================================================
# Check 6: lua-200-locals
# ----------------------------------------------------------------------------
# Lua 5.1 hard cap: 200 locals per function/chunk. Warn at 180, error at 200.
# Memory: reference_vt2_lua_200_locals.md.
# We approximate "top-level chunk" by counting `local NAME` declarations at
# indent depth 0 (start-of-line, no leading whitespace). Cheap and matches
# how the chunk-local cap actually applies to mod main files.
# ============================================================================
function Invoke-Check-Lua200Locals {
    param([string]$File, [string[]]$Lines)

    $findings = @()
    $lines = $Lines

    # Count top-level `local NAME[, NAME2 ...]` declarations.
    # NB: indent depth 0 == start of line, no leading whitespace.
    $rxTopLocal = [regex]'^local\s+([A-Za-z_][A-Za-z0-9_,\s]*?)(?:\s*=|\s+function\b|\s*$)'
    $count = 0
    $lastLine = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $rxTopLocal.Match($lines[$i])
        if ($m.Success) {
            $names = ($m.Groups[1].Value -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*$' }
            $count += ($names | Measure-Object).Count
            $lastLine = $i + 1
        }
    }

    if ($count -ge 200) {
        $findings += (New-Finding -Severity 'error' -Check 'lua-200-locals' `
            -File $File -Line $lastLine `
            -Message ("top-level local count = {0} (>= 200; Lua 5.1 hard cap)" -f $count))
    } elseif ($count -ge 180) {
        $findings += (New-Finding -Severity 'warning' -Check 'lua-200-locals' `
            -File $File -Line $lastLine `
            -Message ("top-level local count = {0} (>= 180; approaching Lua 5.1 cap of 200)" -f $count))
    }

    return $findings
}

# ============================================================================
# Check 7: base-class-hook
# ----------------------------------------------------------------------------
# VT2's MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer) copies
# parent methods at class-definition time. Hooks on HeroPreviewer never fire
# on the actual keep inventory instance. Memory:
# feedback_vt2_class_hook_derived.md.
# ============================================================================
function Invoke-Check-BaseClassHook {
    param([array]$Files)   # array of @{Path; Raw; Stripped; CommentStripped}

    $findings = @()
    $rxHero = [regex]'\bmod\s*:\s*(hook|hook_safe|hook_origin)\s*\(\s*"HeroPreviewer"\s*,\s*"(equip_item|_spawn_item|spawn_units)"'
    $rxMWP  = [regex]'\bmod\s*:\s*(hook|hook_safe|hook_origin)\s*\(\s*"MenuWorldPreviewer"\s*,\s*"(equip_item|_spawn_item|spawn_units)"'

    # Collect (method -> {HeroSites, MWPSites}) across all files in the mod.
    $heroSites = @{}   # method -> list of @{File;Line}
    $mwpMethods = @{}  # method -> $true

    foreach ($f in $Files) {
        # CommentStripped lines preserve string contents (we match on literal class/method names).
        $lines = $f.CommentStrippedLines
        for ($i = 0; $i -lt $lines.Count; $i++) {
            foreach ($m in $rxHero.Matches($lines[$i])) {
                $method = $m.Groups[2].Value
                if (-not $heroSites.ContainsKey($method)) { $heroSites[$method] = @() }
                $heroSites[$method] += @{ File = $f.Path; Line = $i + 1 }
            }
            foreach ($m in $rxMWP.Matches($lines[$i])) {
                $mwpMethods[$m.Groups[2].Value] = $true
            }
        }
    }

    foreach ($method in $heroSites.Keys) {
        if (-not $mwpMethods.ContainsKey($method)) {
            foreach ($site in $heroSites[$method]) {
                $findings += (New-Finding -Severity 'warning' -Check 'base-class-hook' `
                    -File $site.File -Line $site.Line `
                    -Message ("hooks HeroPreviewer.{0} but not MenuWorldPreviewer.{0} — class() copies methods at boot; hooks on base never fire on derived" -f $method))
            }
        }
    }

    return $findings
}

# ============================================================================
# Check 8: dropdown-options-reuse
# ----------------------------------------------------------------------------
# VMF dropdown options tables can be mutated at runtime (e.g. localization
# refresh). Reusing the same _OPTIONS table across widgets means a mutation
# bleeds across widgets. Memory: feedback_vmf_dropdown_options_mutated.md
# (enemy_tweaker v0.4.x).
# ============================================================================
function Invoke-Check-DropdownOptionsReuse {
    param([array]$Files)   # only checks <mod>.lua main file

    $findings = @()
    foreach ($f in $Files) {
        # Limit to the main <mod>.lua (not _data, _backend, _localization, etc.)
        $leaf = Split-Path -Leaf $f.Path
        if ($leaf -match '_(data|backend|localization|big_rebalance|big_rebalance_defs|loc).*\.lua$') { continue }
        if ($leaf -notmatch '\.lua$') { continue }

        $lines = $f.StrippedLines

        # find `local _<NAME>_OPTIONS = {` declarations
        $rxDecl = [regex]'^\s*local\s+(_[A-Za-z_][A-Za-z0-9_]*_OPTIONS)\s*='
        $optionNames = @{}
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $m = $rxDecl.Match($lines[$i])
            if ($m.Success) {
                $optionNames[$m.Groups[1].Value] = $i + 1
            }
        }

        if ($optionNames.Count -eq 0) { continue }

        # Find usages: `options = <NAME>`
        foreach ($name in $optionNames.Keys) {
            $rxUse = [regex]('\boptions\s*=\s*' + [regex]::Escape($name) + '\b')
            $useSites = @()
            for ($i = 0; $i -lt $lines.Count; $i++) {
                foreach ($u in $rxUse.Matches($lines[$i])) {
                    $useSites += @{ File = $f.Path; Line = $i + 1 }
                }
            }
            if ($useSites.Count -gt 1) {
                foreach ($site in $useSites) {
                    $sitesList = ($useSites | ForEach-Object { ("{0}:{1}" -f (To-RelPath $_.File), $_.Line) }) -join ', '
                    $findings += (New-Finding -Severity 'warning' -Check 'dropdown-options-reuse' `
                        -File $site.File -Line $site.Line `
                        -Message ("$name used by $($useSites.Count) widgets ($sitesList) — shared options table can desync if any widget mutates it"))
                }
            }
        }
    }

    return $findings
}

# ============================================================================
# Mod-level orchestration
# ============================================================================

function Lint-Mod {
    param(
        [string]$ModFolder,
        [string[]]$EnabledChecks
    )

    $modName = Split-Path -Leaf $ModFolder
    $files = Get-ModLuaFiles -ModFolder $ModFolder
    $findings = @()

    if ($files.Count -eq 0) {
        return [pscustomobject]@{ ModName = $modName; Findings = $findings; FileCount = 0 }
    }

    # Read + strip every file once. We compute both:
    #   CommentStripped — comments blanked, string contents PRESERVED (needed
    #     for the unescaped-percent check + hook-class/method string matching).
    #   Stripped        — comments AND string contents both blanked (needed
    #     for code-pattern checks where strings would cause false positives).
    # Lines are also pre-split (avoids re-splitting per check).
    $fileObjs = foreach ($p in $files) {
        $raw = Read-LuaText -Path $p
        $commentStripped = Strip-LuaComments -Text $raw
        $stripped = Blank-LuaStringInteriors -Text $commentStripped
        [pscustomobject]@{
            Path                 = $p
            Raw                  = $raw
            Stripped             = $stripped
            CommentStripped      = $commentStripped
            StrippedLines        = $stripped -split "`r?`n"
            CommentStrippedLines = $commentStripped -split "`r?`n"
            RawLines             = $raw -split "`r?`n"
        }
    }

    # Per-file checks
    foreach ($f in $fileObjs) {
        if ($EnabledChecks -contains 'forward-ref') {
            $findings += Invoke-Check-ForwardRef -File $f.Path -Lines $f.StrippedLines
        }
        if ($EnabledChecks -contains 'unescaped-percent') {
            $findings += Invoke-Check-UnescapedPercent -File $f.Path -Lines $f.CommentStrippedLines
        }
        if ($EnabledChecks -contains 'unit-actor-zero-index') {
            $findings += Invoke-Check-UnitActorZeroIndex -File $f.Path -Lines $f.StrippedLines
        }
        if ($EnabledChecks -contains 'strict-table-lookup') {
            $findings += Invoke-Check-StrictTableLookup -File $f.Path -Lines $f.StrippedLines
        }
        if ($EnabledChecks -contains 'lua-200-locals') {
            $findings += Invoke-Check-Lua200Locals -File $f.Path -Lines $f.StrippedLines
        }
    }

    # Mod-level (cross-file) checks
    if ($EnabledChecks -contains 'hook-safe-duplicate') {
        $findings += Invoke-Check-HookSafeDuplicate -Files $fileObjs
    }
    if ($EnabledChecks -contains 'base-class-hook') {
        $findings += Invoke-Check-BaseClassHook -Files $fileObjs
    }
    if ($EnabledChecks -contains 'dropdown-options-reuse') {
        $findings += Invoke-Check-DropdownOptionsReuse -Files $fileObjs
    }

    return [pscustomobject]@{
        ModName   = $modName
        Findings  = $findings
        FileCount = $files.Count
    }
}

function Resolve-ModFolders {
    param([string]$ModArg)
    if (-not $ModArg) {
        $folders = @()
        foreach ($m in $Script:KnownMods) {
            $p = Join-Path $RepoRoot $m
            if (Test-Path (Join-Path $p 'itemV2.cfg')) { $folders += (Resolve-Path $p).Path }
        }
        return $folders
    }
    if (Test-Path $ModArg) { return @( (Resolve-Path $ModArg).Path ) }
    $rel = Join-Path $RepoRoot $ModArg
    if (Test-Path $rel) { return @( (Resolve-Path $rel).Path ) }
    throw "Mod not found: $ModArg"
}

# ============================================================================
# Reporting
# ============================================================================

function Emit-Report {
    param(
        [array]$Reports,
        [bool]$QuietFlag,
        [bool]$WarnAsErr
    )

    $totalErrors = 0
    $totalWarns  = 0

    if (-not $QuietFlag) {
        Write-Host ("regression-lint: scanning {0} mod(s)" -f $Reports.Count)
    }

    foreach ($r in $Reports) {
        $errs  = @($r.Findings | Where-Object { $_.Severity -eq 'error' })
        $warns = @($r.Findings | Where-Object { $_.Severity -eq 'warning' })
        $totalErrors += $errs.Count
        $totalWarns  += $warns.Count

        if (-not $QuietFlag -or $errs.Count -gt 0 -or $warns.Count -gt 0) {
            Write-Host ""
            Write-Host ("[mod] {0}" -f $r.ModName) -ForegroundColor Cyan
        }

        if ($r.Findings.Count -eq 0) {
            if (-not $QuietFlag) { Write-Host "  OK" -ForegroundColor Green }
            continue
        }

        # Sort: errors first, then warnings, then by check name, then by line.
        $sorted = $r.Findings | Sort-Object @{E={ if ($_.Severity -eq 'error') { 0 } else { 1 } }}, Check, File, Line
        foreach ($f in $sorted) {
            $color = if ($f.Severity -eq 'error') { 'Red' } else { 'Yellow' }
            $rel = To-RelPath $f.File
            $line = ("  {0}: {1}:{2} -- {3}" -f $f.Check, $rel, $f.Line, $f.Message)
            Write-Host $line -ForegroundColor $color
        }
    }

    Write-Host ""
    $summary = ("{0} error(s), {1} warning(s)" -f $totalErrors, $totalWarns)
    $sColor = if ($totalErrors -gt 0) { 'Red' }
              elseif ($totalWarns -gt 0 -and $WarnAsErr) { 'Red' }
              elseif ($totalWarns -gt 0) { 'Yellow' }
              else { 'Green' }
    Write-Host $summary -ForegroundColor $sColor

    if ($totalErrors -gt 0) { return 1 }
    if ($WarnAsErr -and $totalWarns -gt 0) { return 1 }
    return 0
}

# ============================================================================
# Self-test
# ============================================================================

function Invoke-SelfTest {
    Write-Host "regression-lint: running self-test"

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rl-selftest-" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null

    # Use a typed list so nested functions can mutate it in-place (nested-fn
    # scope can't reassign `$results = ...` in the parent).
    $results = New-Object 'System.Collections.Generic.List[object]'

    function Make-Mod {
        param([string]$Name)
        $modRoot = Join-Path $tmp $Name
        New-Item -ItemType Directory -Force -Path $modRoot | Out-Null
        # itemV2.cfg presence (so Resolve-ModFolders accepts it if scoped by Mod)
        Set-Content -Path (Join-Path $modRoot 'itemV2.cfg') -Value '' -Encoding utf8
        $scriptDir = Join-Path $modRoot "scripts\mods\$Name"
        New-Item -ItemType Directory -Force -Path $scriptDir | Out-Null
        return @{ Root = $modRoot; ScriptDir = $scriptDir }
    }

    function Write-Bad {
        param([string]$Path, [string]$Content)
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::UTF8)
    }

    function Lint-One {
        param([string]$Folder, [string[]]$Checks)
        $report = Lint-Mod -ModFolder $Folder -EnabledChecks $Checks
        return $report.Findings
    }

    function Has-Finding {
        param([array]$F, [string]$Check)
        return ($F | Where-Object { $_.Check -eq $Check }).Count -gt 0
    }

    function Record {
        param([string]$Name, [bool]$Pass, [string]$Detail)
        $results.Add(@{ Name = $Name; Pass = $Pass; Detail = $Detail })
        $color = if ($Pass) { 'Green' } else { 'Red' }
        $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
        Write-Host ("  [{0}] {1} {2}" -f $tag, $Name, $Detail) -ForegroundColor $color
    }

    # ---- forward-ref ----
    $m = Make-Mod -Name 'st_forward_ref'
    # closure captures `helper` at line 1, helper defined later — should fire.
    Write-Bad -Path (Join-Path $m.ScriptDir 'bad.lua') -Content @'
local f = function() return helper(1) end
local function helper(x) return x + 1 end
'@
    $found = Lint-One -Folder $m.Root -Checks @('forward-ref')
    Record -Name 'forward-ref fires on captured-before-defined' -Pass (Has-Finding -F $found -Check 'forward-ref') -Detail ""

    $m = Make-Mod -Name 'st_forward_ref_ok'
    Write-Bad -Path (Join-Path $m.ScriptDir 'good.lua') -Content @'
local helper
local f = function() return helper(1) end
function helper(x) return x + 1 end
'@
    $found = Lint-One -Folder $m.Root -Checks @('forward-ref')
    Record -Name 'forward-ref clean with forward decl' -Pass (-not (Has-Finding -F $found -Check 'forward-ref')) -Detail ""

    # ---- unescaped-percent ----
    $m = Make-Mod -Name 'st_pct'
    Write-Bad -Path (Join-Path $m.ScriptDir 'st_pct_localization.lua') -Content @'
return {
    bad = { en = "+50%" },
}
'@
    $found = Lint-One -Folder $m.Root -Checks @('unescaped-percent')
    Record -Name 'unescaped-percent fires on "+50%"' -Pass (Has-Finding -F $found -Check 'unescaped-percent') -Detail ""

    $m = Make-Mod -Name 'st_pct_ok'
    Write-Bad -Path (Join-Path $m.ScriptDir 'st_pct_ok_localization.lua') -Content @'
return {
    good = { en = "+50%% damage" },
}
'@
    $found = Lint-One -Folder $m.Root -Checks @('unescaped-percent')
    Record -Name 'unescaped-percent clean on "+50%%"' -Pass (-not (Has-Finding -F $found -Check 'unescaped-percent')) -Detail ""

    # ---- hook-safe-duplicate ----
    $m = Make-Mod -Name 'st_dup'
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content @'
mod:hook("Foo", "bar", function() end)
'@
    Write-Bad -Path (Join-Path $m.ScriptDir 'b.lua') -Content @'
mod:hook_safe("Foo", "bar", function() end)
'@
    $found = Lint-One -Folder $m.Root -Checks @('hook-safe-duplicate')
    Record -Name 'hook-safe-duplicate fires across files' -Pass (Has-Finding -F $found -Check 'hook-safe-duplicate') -Detail ""

    $m = Make-Mod -Name 'st_dup_whitelisted'
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content @'
mod:hook("Foo", "bar", function() end)
-- LINT_OK_REHOOK: intentional override per test
mod:hook_safe("Foo", "bar", function() end)
'@
    $found = Lint-One -Folder $m.Root -Checks @('hook-safe-duplicate')
    Record -Name 'hook-safe-duplicate respects LINT_OK_REHOOK' -Pass (-not (Has-Finding -F $found -Check 'hook-safe-duplicate')) -Detail ""

    # ---- unit-actor-zero-index ----
    $m = Make-Mod -Name 'st_actor'
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content @'
local n = Unit.num_actors(unit)
for i = 0, n - 1 do
    local a = Unit.actor(unit, i)
end
'@
    $found = Lint-One -Folder $m.Root -Checks @('unit-actor-zero-index')
    Record -Name 'unit-actor-zero-index fires' -Pass (Has-Finding -F $found -Check 'unit-actor-zero-index') -Detail ""

    # ---- strict-table-lookup ----
    $m = Make-Mod -Name 'st_strict'
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content @'
if BuffTemplates[name] then
    do_thing()
end
'@
    $found = Lint-One -Folder $m.Root -Checks @('strict-table-lookup')
    Record -Name 'strict-table-lookup fires on BuffTemplates[name]' -Pass (Has-Finding -F $found -Check 'strict-table-lookup') -Detail ""

    $m = Make-Mod -Name 'st_strict_ok'
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content @'
if rawget(BuffTemplates, name) then
    do_thing()
end
'@
    $found = Lint-One -Folder $m.Root -Checks @('strict-table-lookup')
    Record -Name 'strict-table-lookup clean with rawget' -Pass (-not (Has-Finding -F $found -Check 'strict-table-lookup')) -Detail ""

    # ---- lua-200-locals ----
    $m = Make-Mod -Name 'st_locals'
    $sb = New-Object System.Text.StringBuilder
    for ($k = 1; $k -le 205; $k++) { [void]$sb.AppendLine("local v$k = $k") }
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content $sb.ToString()
    $found = Lint-One -Folder $m.Root -Checks @('lua-200-locals')
    Record -Name 'lua-200-locals fires at 205 declarations' -Pass (Has-Finding -F $found -Check 'lua-200-locals') -Detail ""

    # ---- base-class-hook ----
    $m = Make-Mod -Name 'st_base'
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content @'
mod:hook("HeroPreviewer", "equip_item", function() end)
'@
    $found = Lint-One -Folder $m.Root -Checks @('base-class-hook')
    Record -Name 'base-class-hook fires on HeroPreviewer.equip_item' -Pass (Has-Finding -F $found -Check 'base-class-hook') -Detail ""

    $m = Make-Mod -Name 'st_base_ok'
    Write-Bad -Path (Join-Path $m.ScriptDir 'a.lua') -Content @'
mod:hook("HeroPreviewer", "equip_item", function() end)
mod:hook("MenuWorldPreviewer", "equip_item", function() end)
'@
    $found = Lint-One -Folder $m.Root -Checks @('base-class-hook')
    Record -Name 'base-class-hook clean when both hooked' -Pass (-not (Has-Finding -F $found -Check 'base-class-hook')) -Detail ""

    # ---- dropdown-options-reuse ----
    $m = Make-Mod -Name 'st_dropdown'
    # Must be the main <mod>.lua to be inspected (not _data, _localization, etc.)
    Write-Bad -Path (Join-Path $m.ScriptDir 'st_dropdown.lua') -Content @'
local _DIFFICULTY_OPTIONS = { "easy", "hard" }
return {
    { setting_id = "a", options = _DIFFICULTY_OPTIONS },
    { setting_id = "b", options = _DIFFICULTY_OPTIONS },
}
'@
    $found = Lint-One -Folder $m.Root -Checks @('dropdown-options-reuse')
    Record -Name 'dropdown-options-reuse fires on 2 widgets' -Pass (Has-Finding -F $found -Check 'dropdown-options-reuse') -Detail ""

    # ---- cleanup ----
    Remove-Item -Recurse -Force -Path $tmp -ErrorAction SilentlyContinue

    $failed = @($results | Where-Object { -not $_.Pass })
    $passed = @($results | Where-Object { $_.Pass })
    Write-Host ""
    if ($failed.Count -eq 0) {
        Write-Host ("self-test PASS ({0}/{1})" -f $passed.Count, $results.Count) -ForegroundColor Green
        return 0
    } else {
        Write-Host ("self-test FAIL ({0}/{1} failed)" -f $failed.Count, $results.Count) -ForegroundColor Red
        foreach ($f in $failed) { Write-Host ("  - {0}" -f $f.Name) -ForegroundColor Red }
        return 1
    }
}

# ============================================================================
# Main
# ============================================================================

if ($SelfTest) {
    exit (Invoke-SelfTest)
}

# Validate -Check
$enabled = $Script:AllChecks
if ($Check) {
    if ($Script:AllChecks -notcontains $Check) {
        Write-Host "Unknown -Check '$Check'. Valid: $($Script:AllChecks -join ', ')" -ForegroundColor Red
        exit 1
    }
    $enabled = @($Check)
}

$modFolders = Resolve-ModFolders -ModArg $Mod
$reports = @()
foreach ($f in $modFolders) {
    $reports += Lint-Mod -ModFolder $f -EnabledChecks $enabled
}

$exitCode = Emit-Report -Reports $reports -QuietFlag:$Quiet -WarnAsErr:$WarningsAsErrors
exit $exitCode
