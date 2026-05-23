# tools/mod-lint/lint-mod.ps1
#
# Static lint for two recurring VT2 mod bug classes that have cost multiple
# version bumps:
#
#   1. Duplicate VMF hook registration on the same (class, method) pair.
#      VMF silently drops the second mod:hook* registration. Per memory
#      `feedback_vmf_hook_safe_no_chain`. Burned cim v0.7.21, v0.7.23, v0.7.27
#      (see crafting_in_modded/CHANGELOG.md).
#
#   2. Lua forward-reference bug: a closure that captures a `local` name
#      whose `local function NAME` definition appears LATER in the same scope
#      with no earlier `local NAME` forward declaration. The closure resolves
#      the name as a nil global at call time. Per memory
#      `feedback_lua_forward_reference` — CRITICAL, 5+ documented crashes.
#
#   3. Save/restore invariants (added 2026-05-23 after the cim "stale
#      modded_loadout overwrites vanilla restore on next session" user report):
#        3a. `BackendInterfaceItemPlayfab.set_loadout_item` hooks that
#            persist a modded-loadout entry MUST also clear it before saving,
#            otherwise switching back to a vanilla item leaves a stale cim
#            entry that clobbers the next session's restore.
#        3b. Every `mod:set("KEY", ...)` must have a matching `mod:get("KEY")`
#            somewhere in the same file. Catches save-without-load typos
#            that silently lose persistence.
#        3c. Any `mod:hook_safe("BackendManagerPlayFab", "_create_interfaces",
#            ...)` callback that reads from `Managers.backend` must check
#            `Managers.backend ~= nil` first. The hook can fire from a code
#            path where Managers.backend has been torn down (e.g. lobby
#            return) and a bare `Managers.backend:get_interface(...)` crashes.
#      These three are HEURISTIC — they live as WARN by default; pass
#      `-Strict` to promote to error (and block release).
#
# Usage:
#   .\lint-mod.ps1                                    # all VMB mods in the repo
#   .\lint-mod.ps1 -ModPath crafting_in_modded        # single mod
#   .\lint-mod.ps1 -ModPath .\crafting_in_modded -Json # also emit JSON sidecar
#   .\lint-mod.ps1 -Strict                            # heuristic WARN -> ERROR
#
# Exit codes:
#   0 - clean
#   1 - warnings only (forward-ref + save/restore heuristics)
#   2 - errors found (duplicate hooks; with -Strict, also save/restore)
#
# Output:
#   - human-readable PASS/FAIL per mod plus per-finding file:line
#   - optional JSON sidecar at <repo>/.release-stage/mod-lint.json (or -JsonPath)

[CmdletBinding()]
param(
    [string]$ModPath,
    [string]$JsonPath,
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# ---- mod inventory (kept in sync with publish-release.ps1) ----
$KnownMods = @(
    'weapon_tweaker', 'chaos_wastes_tweaker', 'general_tweaker', 'cosmetics_tweaker',
    'dynamic_cosmetic_portraits', 'career_tweaker', 'enemy_tweaker',
    'character_weapon_variants', 'crafting_in_modded', 'la_prefix_patch',
    'event_tweaker', 'modded_progression', 'lobby_tweaker', 'buff_tweaker',
    'material_hijack_patched', 'verminious_dreams_lighting'
)

function Read-LuaText {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

# ---- comment & string stripping (line-aware) ----
# Replaces every block-comment and single-line-comment with spaces but PRESERVES
# newlines so reported line numbers stay accurate. String literals are replaced
# with empty quoted strings of the same length where possible so the lexer
# downstream still sees them as strings without false-matching tokens inside.
# Convenience wrapper: just strip comments, keep all strings intact. Used by the
# hook-detection pass where string contents (the class/method names) are
# load-bearing.
function Strip-LuaComments {
    param([string]$Text)
    return Strip-LuaCommentsAndStrings -Text $Text -KeepStrings
}

function Strip-LuaCommentsAndStrings {
    param([string]$Text, [switch]$KeepStrings)

    $chars = $Text.ToCharArray()
    $n = $chars.Length
    $out = New-Object 'System.Text.StringBuilder' $n
    $i = 0
    while ($i -lt $n) {
        $c = $chars[$i]
        $next = if ($i + 1 -lt $n) { $chars[$i + 1] } else { [char]0 }

        # --[[ ... ]] or --[==[ ... ]==] long comment
        if ($c -eq '-' -and $next -eq '-' -and ($i + 2 -lt $n) -and $chars[$i + 2] -eq '[') {
            # detect long-bracket level: --[ {=} [
            $j = $i + 3
            $eq = 0
            while ($j -lt $n -and $chars[$j] -eq '=') { $eq++; $j++ }
            if ($j -lt $n -and $chars[$j] -eq '[') {
                # find closing ] {eq} ]
                $k = $j + 1
                $closed = $false
                while ($k -lt $n) {
                    if ($chars[$k] -eq ']') {
                        $m = $k + 1
                        $eq2 = 0
                        while ($m -lt $n -and $chars[$m] -eq '=') { $eq2++; $m++ }
                        if ($eq2 -eq $eq -and $m -lt $n -and $chars[$m] -eq ']') {
                            $closed = $true
                            $end = $m
                            break
                        }
                    }
                    $k++
                }
                if (-not $closed) { $end = $n - 1 }
                # replace [i..end] with whitespace (preserve \n)
                for ($p = $i; $p -le $end; $p++) {
                    if ($chars[$p] -eq "`n") { [void]$out.Append("`n") } else { [void]$out.Append(' ') }
                }
                $i = $end + 1
                continue
            }
            # else fall through to single-line comment
        }

        # -- single-line comment
        if ($c -eq '-' -and $next -eq '-') {
            while ($i -lt $n -and $chars[$i] -ne "`n") {
                [void]$out.Append(' ')
                $i++
            }
            continue
        }

        # long string [[ ... ]] / [==[ ... ]==]
        if ($c -eq '[') {
            $j = $i + 1
            $eq = 0
            while ($j -lt $n -and $chars[$j] -eq '=') { $eq++; $j++ }
            if ($j -lt $n -and $chars[$j] -eq '[') {
                $k = $j + 1
                $closed = $false
                while ($k -lt $n) {
                    if ($chars[$k] -eq ']') {
                        $m = $k + 1
                        $eq2 = 0
                        while ($m -lt $n -and $chars[$m] -eq '=') { $eq2++; $m++ }
                        if ($eq2 -eq $eq -and $m -lt $n -and $chars[$m] -eq ']') {
                            $closed = $true; $end = $m; break
                        }
                    }
                    $k++
                }
                if (-not $closed) { $end = $n - 1 }
                # Keep delimiters; either preserve interior (-KeepStrings) or
                # blank it (preserving newlines).
                [void]$out.Append('[')
                for ($p = 0; $p -lt $eq; $p++) { [void]$out.Append('=') }
                [void]$out.Append('[')
                for ($p = $j + 1; $p -lt $end - $eq; $p++) {
                    if ($KeepStrings) {
                        [void]$out.Append($chars[$p])
                    } elseif ($chars[$p] -eq "`n") {
                        [void]$out.Append("`n")
                    } else {
                        [void]$out.Append(' ')
                    }
                }
                [void]$out.Append(']')
                for ($p = 0; $p -lt $eq; $p++) { [void]$out.Append('=') }
                [void]$out.Append(']')
                $i = $end + 1
                continue
            }
        }

        # short strings: "..." and '...'
        # Default: blank the interior so string-literal keywords (e.g. "use while
        # a menu is open" containing the Lua keyword `while`) don't false-trigger
        # our keyword counter. With -KeepStrings: preserve interiors verbatim so
        # the hook-detection regex can still read class/method names.
        if ($c -eq '"' -or $c -eq "'") {
            $quote = $c
            [void]$out.Append($c)
            $i++
            while ($i -lt $n) {
                $cc = $chars[$i]
                if ($cc -eq '\') {
                    if ($KeepStrings) { [void]$out.Append($cc) } else { [void]$out.Append(' ') }
                    if ($i + 1 -lt $n) {
                        $nxt = $chars[$i + 1]
                        if ($KeepStrings) {
                            [void]$out.Append($nxt)
                        } elseif ($nxt -eq "`n") {
                            [void]$out.Append("`n")
                        } else {
                            [void]$out.Append(' ')
                        }
                        $i += 2
                        continue
                    } else {
                        $i++
                        break
                    }
                }
                if ($cc -eq $quote) {
                    [void]$out.Append($cc)
                    $i++
                    break
                }
                if ($cc -eq "`n") {
                    # unterminated short string at EOL — Lua error, but keep going
                    [void]$out.Append("`n")
                    $i++
                    break
                }
                if ($KeepStrings) { [void]$out.Append($cc) } else { [void]$out.Append(' ') }
                $i++
            }
            continue
        }

        [void]$out.Append($c)
        $i++
    }

    return $out.ToString()
}

# ---- collect all .lua files for a mod ----
function Get-ModLuaFiles {
    param([string]$ModFolder)
    $script = Join-Path $ModFolder 'scripts'
    if (-not (Test-Path $script)) { return @() }
    return Get-ChildItem -Path $script -Recurse -Filter *.lua -File | ForEach-Object { $_.FullName }
}

# ---- parse `local _foo = { "A", "B", "C" }` literal table arrays into a map ----
# Returns a hashtable: short-name -> @('A','B','C')
function Get-LiteralStringTables {
    param([string]$Text)

    $map = @{}
    # Match: local NAME = { ... }   where ... is a comma-separated list of "string"|'string'
    # Multiline-friendly.
    $rx = [regex]'(?ms)\blocal\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*((?:(?:"[^"]*"|''[^'']*'')\s*,?\s*)+)\}'
    foreach ($m in $rx.Matches($Text)) {
        $name = $m.Groups[1].Value
        $body = $m.Groups[2].Value
        $strings = @()
        foreach ($sm in ([regex]'"([^"]*)"|''([^'']*)''').Matches($body)) {
            if ($sm.Groups[1].Success) { $strings += $sm.Groups[1].Value }
            elseif ($sm.Groups[2].Success) { $strings += $sm.Groups[2].Value }
        }
        if ($strings.Count -gt 0) { $map[$name] = $strings }
    }
    return $map
}

# ---- find every mod:hook[_safe|_origin] registration ----
# Yields rows: @{ File; Line; Class; Method; ClassRaw; SourceLine }
function Find-HookRegistrations {
    param(
        [string]$File,
        [string]$Text,
        [hashtable]$LiteralTables
    )

    $rows = @()
    $lines = $Text -split "`r?`n"

    # Track per-line `for _, klass in ipairs({...}) do` or `for _, klass in ipairs(_LITERAL_NAME) do`
    # We model loops as: a line that opens a loop sets a "current iter var -> @(string-list)" mapping
    # that remains active until a `for ... in ipairs(other) do` overwrites it. This is approximate but
    # adequate for the simple flat loops these mods use.
    $iterVarToList = @{}

    # Forms accepted:
    #   for _, NAME in ipairs({ "A","B" }) do
    #   for _, NAME in ipairs(_LIT_NAME) do
    #   for _, NAME in pairs({...}) do
    $rxForLiteral = [regex]'\bfor\s+[A-Za-z_][A-Za-z0-9_]*\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\s+i?pairs\s*\(\s*\{\s*((?:(?:"[^"]*"|''[^'']*'')\s*,?\s*)+)\s*\}\s*\)\s+do'
    $rxForNamed   = [regex]'\bfor\s+[A-Za-z_][A-Za-z0-9_]*\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s+in\s+i?pairs\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s+do'

    # Hook call. Class arg: "STR" | 'STR' | IDENT  ; Method arg: "STR" | 'STR'
    $rxHook = [regex]'\bmod\s*:\s*(hook|hook_safe|hook_origin)\s*\(\s*(?:"([^"]+)"|''([^'']+)''|([A-Za-z_][A-Za-z0-9_.]*))\s*,\s*(?:"([^"]+)"|''([^'']+)'')'

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Update loop context (process first literal table match, then named).
        $mLit = $rxForLiteral.Match($line)
        if ($mLit.Success) {
            $iterVar = $mLit.Groups[1].Value
            $body    = $mLit.Groups[2].Value
            $strings = @()
            foreach ($sm in ([regex]'"([^"]*)"|''([^'']*)''').Matches($body)) {
                if ($sm.Groups[1].Success) { $strings += $sm.Groups[1].Value }
                elseif ($sm.Groups[2].Success) { $strings += $sm.Groups[2].Value }
            }
            $iterVarToList[$iterVar] = $strings
        } else {
            $mNamed = $rxForNamed.Match($line)
            if ($mNamed.Success) {
                $iterVar = $mNamed.Groups[1].Value
                $listName = $mNamed.Groups[2].Value
                if ($LiteralTables.ContainsKey($listName)) {
                    $iterVarToList[$iterVar] = $LiteralTables[$listName]
                } else {
                    # unknown — clear so we don't false-attribute
                    $iterVarToList.Remove($iterVar) | Out-Null
                }
            }
        }

        # Find hooks on this line.
        foreach ($h in $rxHook.Matches($line)) {
            $method = if ($h.Groups[5].Success) { $h.Groups[5].Value } else { $h.Groups[6].Value }
            $classRaw = $null
            $classCandidates = @()
            if ($h.Groups[2].Success) {
                $classRaw = $h.Groups[2].Value
                $classCandidates = @($classRaw)
            } elseif ($h.Groups[3].Success) {
                $classRaw = $h.Groups[3].Value
                $classCandidates = @($classRaw)
            } elseif ($h.Groups[4].Success) {
                $classRaw = $h.Groups[4].Value
                # Loop iter var?
                if ($iterVarToList.ContainsKey($classRaw)) {
                    $classCandidates = $iterVarToList[$classRaw]
                } else {
                    # Identifier: dotted (e.g. items_interface, BackendUtils, _G).
                    # We keep them — same identifier hooked twice on same method is still a probable
                    # duplicate. The classRaw IS the key.
                    $classCandidates = @($classRaw)
                }
            }

            foreach ($cls in $classCandidates) {
                $rows += [pscustomobject]@{
                    File       = $File
                    Line       = $i + 1
                    Class      = $cls
                    Method     = $method
                    ClassRaw   = $classRaw
                    SourceLine = $line.Trim()
                }
            }
        }
    }

    return ,$rows
}

# ---- pattern 1 ----
function Find-DuplicateHooks {
    param([array]$AllHooks)

    $groups = $AllHooks | Group-Object -Property @{ E={ "$($_.Class)::$($_.Method)" } }
    $dupes = @()
    foreach ($g in $groups) {
        if ($g.Count -gt 1) {
            # Dedupe within the SAME (file,line) — happens when a single mod:hook line is matched twice
            # by regex backtracking, or when the same literal table contains a duplicate string.
            $unique = $g.Group | Sort-Object File, Line -Unique
            if (($unique | Measure-Object).Count -gt 1) {
                $dupes += [pscustomobject]@{
                    Key        = $g.Name
                    Class      = $g.Group[0].Class
                    Method     = $g.Group[0].Method
                    Locations  = $unique
                }
            }
        }
    }
    return ,$dupes
}

# ---- pattern 2: forward-reference ----
# Build the per-file inventory:
#   * local-fn defs: `local function NAME(` or `local NAME = function(`  -> { Name; DefLine }
#   * forward decls: `local NAME` (no `=`, no `function`) at start-of-statement -> { Name; DeclLine }
#   * closure starts: each `function(...)` whose opening line we record.
#     We use a coarse closure scan: every `function(` on a line that ALSO contains
#     `mod:hook` / `mod:hook_safe` / `mod:hook_origin` or a table-assignment style
#     `= function(` becomes a closure to scan. Body extracted by balanced-`end` walker.
#
# For each closure, we walk its body and find bare-word identifier references
# (a token preceded by non-identifier and NOT followed by `(` is still a reference —
# but we focus on identifier appearances of any kind). For each identifier in the
# closure that matches one of the file's local-fn names, flag iff:
#   * closure-start-line < def-line, AND
#   * no `local NAME` forward decl appears strictly above the closure-start-line.

function Find-ForwardRefIssues {
    param(
        [string]$File,
        [string]$RawText,    # for line numbers (original-with-comments)
        [string]$StripText   # comment-stripped (for matching closures + references)
    )

    $lines = $StripText -split "`r?`n"
    $findings = @()

    # 1) Collect local-function definitions and forward declarations.
    $localDefs   = @{}   # name -> first def line
    $forwardDecl = @{}   # name -> earliest forward-decl line

    # `local function NAME(` — module-level only (column 0). Indented declarations
    # live inside another function and are scoped there; the closure-extent walker
    # treats them as references rather than top-level defs.
    $rxLocalFn1 = [regex]'^local\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('
    # `local NAME = function(` — same column-0 rule.
    $rxLocalFn2 = [regex]'^local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\('
    # `local NAME[, NAME2 ...]` with NO `=` and NO `function` (pure forward decl)
    $rxForwardDecl = [regex]'^local\s+([A-Za-z_][A-Za-z0-9_,\s]*?)\s*$'

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
        # forward decl only if no `=` on the line at all
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

    if ($localDefs.Count -eq 0) { return ,$findings }

    # 2) Locate closure-body extents. For each `function(` (anonymous) anywhere
    # in the file, scan forward counting block-openers vs `end` to find the
    # matching `end`. Lua block-openers that consume an `end`: function, do, if,
    # while, for. `repeat` consumes `until` (not `end`). Single-line `then ...
    # end` etc. all participate. We scan the comment-stripped text for accuracy.

    $closures = @()   # list of @{ StartLine; EndLine }

    # `function(` (anonymous) — preceded by '=' or ',' or '(' or '{' typically.
    # We accept any `function(` not preceded by a name-character (i.e. not `function foo(`).
    $rxAnonFn = [regex]'(^|[^A-Za-z0-9_])function\s*\('

    # Pre-tokenize lines into "open keywords" / "end" counts, ignoring identifiers
    # that aren't whole words.
    # IMPORTANT: `do` is omitted from openers because in this codebase `do` always
    # appears as the back half of `for ... do` / `while ... do`, where the `end`
    # closes the FOR/WHILE rather than the `do`. Counting `do` as an opener would
    # double-count those loops and inflate closure-body extents past the real
    # `end)`. Bare `do ... end` blocks are not used in any VMB mod in this repo
    # (verified empty grep at scaffold time); if they're added later, swap to a
    # proper Lua lexer. Same logic for `then` — implicit, not standalone.
    $openWordRx  = [regex]'\b(function|if|while|for|repeat)\b'
    $closeWordRx = [regex]'\b(end|until)\b'

    # Find each anonymous function start position, then walk forward.
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $startMatches = $rxAnonFn.Matches($line)
        foreach ($sm in $startMatches) {
            # Avoid double-counting `local function NAME(` (which has IDENT before 'function')
            # — already handled by ^|[^A-Za-z0-9_] but `function` itself is a word, so
            # `local function foo(` would NOT match because 'l function' has 'l' which is alnum.
            # Wait — 'local function foo(' has 'e' before 'function'. We DO want to skip that.
            # The pattern `function\s*\(` only matches when there's `(` directly after function — i.e.
            # NOT `function NAME(`. So `function foo(` is excluded. Good.
            $startLine = $i + 1

            # Walk forward from this match counting opens-1 (we just opened a function) until balance hits 0.
            $balance = 1
            # Start position immediately after the `function(` opener — scan rest of THIS line first.
            $startCol = $sm.Index + $sm.Length  # after `function(`
            $tail = $line.Substring([Math]::Min($startCol, $line.Length))
            $opens  = $openWordRx.Matches($tail).Count
            $closes = $closeWordRx.Matches($tail).Count
            $balance += $opens
            $balance -= $closes

            $endLine = $startLine
            $j = $i + 1
            while ($balance -gt 0 -and $j -lt $lines.Count) {
                $opens  = $openWordRx.Matches($lines[$j]).Count
                $closes = $closeWordRx.Matches($lines[$j]).Count
                $balance += $opens
                $balance -= $closes
                $endLine = $j + 1
                $j++
            }
            $closures += @{ StartLine = $startLine; EndLine = $endLine }
        }
    }

    if ($closures.Count -eq 0) { return ,$findings }

    # 3) For each closure, find references to a local-fn name and check forward-ref rule.
    # We aggregate findings by (file, missing-name) — one entry per local-fn that lacks
    # a forward decl and has at least one earlier-line closure reference. The "earliest
    # referencing closure" is reported as the witness site. This keeps the output
    # actionable: the fix is one `local NAME` line near the top.
    # Word identifier NOT preceded by `.` or `:` (those are table/method accesses,
    # not bare-name references — they don't bind to the local upvalue).
    $idRx = [regex]'(?<![.:A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\b'

    $nameToWitness = @{}   # name -> earliest closure-start line that references it

    foreach ($c in $closures) {
        $start = $c.StartLine
        $end   = $c.EndLine
        if ($end -le $start) { continue }
        $sb = New-Object 'System.Text.StringBuilder'
        for ($k = $start - 1; $k -lt $end -and $k -lt $lines.Count; $k++) {
            [void]$sb.AppendLine($lines[$k])
        }
        $body = $sb.ToString()
        $matches = $idRx.Matches($body)
        foreach ($m in $matches) {
            $name = $m.Groups[1].Value
            if (-not $localDefs.ContainsKey($name)) { continue }
            $defLine = $localDefs[$name]
            if ($start -ge $defLine) { continue }
            if ($forwardDecl.ContainsKey($name) -and $forwardDecl[$name] -lt $start) { continue }

            if (-not $nameToWitness.ContainsKey($name) -or $start -lt $nameToWitness[$name]) {
                $nameToWitness[$name] = $start
            }
        }
    }

    foreach ($name in $nameToWitness.Keys) {
        $findings += [pscustomobject]@{
            File          = $File
            Name          = $name
            DefLine       = $localDefs[$name]
            FirstUseLine  = $nameToWitness[$name]
        }
    }

    return ,$findings
}

# ---- pattern 3: save/restore invariants ----
# Three heuristics added 2026-05-23 to catch the cim "stale modded_loadout
# overwrites vanilla restore" bug class. All three operate per-file on the
# comments-stripped text (short-string interiors preserved so class names and
# settings keys are still readable).
#
# Output rows:
#   @{ File; Line; Kind; Detail }
# where Kind in:
#   set_loadout_no_clear     - 3a: set_loadout_item hook saves without clearing
#   set_without_get          - 3b: mod:set("KEY", ...) with no mod:get("KEY") in file
#   create_interfaces_unguarded - 3c: _create_interfaces hook reads Managers.backend
#                                  without nil check
function Find-SaveRestoreIssues {
    param(
        [string]$File,
        [string]$Text   # comments-stripped, strings KEPT
    )

    $findings = @()
    $lines = $Text -split "`r?`n"

    # --- 3a: set_loadout_item hook clear-before-save invariant ---
    # Find every `mod:hook[_safe|_origin]("BackendInterfaceItemPlayfab", "set_loadout_item", function(...) ... end)`
    # and inspect the body for `_modded_loadout[...] = nil` (clear) AND
    # `_modded_loadout[...] = item_id` (save). If only save, flag.
    $rxHookStart = [regex]'\bmod\s*:\s*(?:hook|hook_safe|hook_origin)\s*\(\s*"BackendInterfaceItemPlayfab"\s*,\s*"set_loadout_item"\s*,\s*function\s*\('
    # The body's interesting tokens: any assignment to a `_modded_loadout[...]`
    # subscript chain. We accept any LHS that starts with `_modded_loadout[`.
    $rxClear = [regex]'_modded_loadout\s*\[[^\]]+\](?:\s*\[[^\]]+\])*\s*=\s*nil\b'
    $rxSave  = [regex]'_modded_loadout\s*\[[^\]]+\](?:\s*\[[^\]]+\])*\s*=\s*(?!nil\b)[A-Za-z_]'

    # Same opener-counting strategy as Find-ForwardRefIssues so we can extract
    # the full body of the hook callback.
    $openWordRx  = [regex]'\b(function|if|while|for|repeat)\b'
    $closeWordRx = [regex]'\b(end|until)\b'

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $rxHookStart.Match($lines[$i])
        if (-not $m.Success) { continue }

        $startLine = $i + 1
        # Walk from immediately after `function(` to find the matching `end`.
        $balance = 1
        $tail = $lines[$i].Substring([Math]::Min($m.Index + $m.Length, $lines[$i].Length))
        $balance += $openWordRx.Matches($tail).Count
        $balance -= $closeWordRx.Matches($tail).Count

        $endLine = $startLine
        $j = $i + 1
        while ($balance -gt 0 -and $j -lt $lines.Count) {
            $balance += $openWordRx.Matches($lines[$j]).Count
            $balance -= $closeWordRx.Matches($lines[$j]).Count
            $endLine = $j + 1
            $j++
        }

        # Concatenate body for token search.
        $sb = New-Object 'System.Text.StringBuilder'
        for ($k = $startLine - 1; $k -lt $endLine -and $k -lt $lines.Count; $k++) {
            [void]$sb.AppendLine($lines[$k])
        }
        $body = $sb.ToString()

        $hasSave  = $rxSave.IsMatch($body)
        $hasClear = $rxClear.IsMatch($body)
        if ($hasSave -and -not $hasClear) {
            $findings += [pscustomobject]@{
                File   = $File
                Line   = $startLine
                Kind   = 'set_loadout_no_clear'
                Detail = "set_loadout_item hook saves to _modded_loadout but never assigns nil -- stale entries will overwrite vanilla restore"
            }
        }
    }

    # --- 3b: mod:set("KEY", ...) without matching mod:get("KEY") in same file ---
    # Heuristic. False-positive guard: if the file ALSO contains any
    # `mod:get(<non-literal>)` form (variable-keyed read — e.g. a wrapper like
    # `effective_setting(name)` that does `return mod:get(name)`), assume keys
    # are read dynamically and suppress the warning for the whole file. The
    # cost is we miss true bugs in files that mix literal and variable-keyed
    # reads, but the alternative — false-positive flooding chaos_wastes_tweaker
    # — drowns the signal.
    $rxSet         = [regex]'\bmod\s*:\s*set\s*\(\s*"([^"]+)"'
    $rxGetLiteral  = [regex]'\bmod\s*:\s*get\s*\(\s*"([^"]+)"'
    $rxGetDynamic  = [regex]'\bmod\s*:\s*get\s*\(\s*(?!")[^,)]+\)'
    $setKeys = @{}
    $getKeys = @{}
    $dynamicGet = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($sm in $rxSet.Matches($lines[$i])) {
            $k = $sm.Groups[1].Value
            if (-not $setKeys.ContainsKey($k)) { $setKeys[$k] = $i + 1 }
        }
        foreach ($gm in $rxGetLiteral.Matches($lines[$i])) {
            $k = $gm.Groups[1].Value
            $getKeys[$k] = $true
        }
        if (-not $dynamicGet -and $rxGetDynamic.IsMatch($lines[$i])) {
            $dynamicGet = $true
        }
    }
    if (-not $dynamicGet) {
        foreach ($k in $setKeys.Keys) {
            if (-not $getKeys.ContainsKey($k)) {
                $findings += [pscustomobject]@{
                    File   = $File
                    Line   = $setKeys[$k]
                    Kind   = 'set_without_get'
                    Detail = "mod:set(`"$k`", ...) has no matching mod:get(`"$k`") in this file"
                }
            }
        }
    }

    # --- 3c: _create_interfaces hook reads Managers.backend without guard ---
    $rxCI = [regex]'\bmod\s*:\s*(?:hook|hook_safe|hook_origin)\s*\(\s*"BackendManagerPlayFab"\s*,\s*"_create_interfaces"\s*,\s*function\s*\('
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $rxCI.Match($lines[$i])
        if (-not $m.Success) { continue }

        $startLine = $i + 1
        $balance = 1
        $tail = $lines[$i].Substring([Math]::Min($m.Index + $m.Length, $lines[$i].Length))
        $balance += $openWordRx.Matches($tail).Count
        $balance -= $closeWordRx.Matches($tail).Count
        $endLine = $startLine
        $j = $i + 1
        while ($balance -gt 0 -and $j -lt $lines.Count) {
            $balance += $openWordRx.Matches($lines[$j]).Count
            $balance -= $closeWordRx.Matches($lines[$j]).Count
            $endLine = $j + 1
            $j++
        }
        $sb = New-Object 'System.Text.StringBuilder'
        for ($k = $startLine - 1; $k -lt $endLine -and $k -lt $lines.Count; $k++) {
            [void]$sb.AppendLine($lines[$k])
        }
        $body = $sb.ToString()

        # Body must contain `Managers.backend` somewhere (the access we care about)
        if ($body -notmatch '\bManagers\s*\.\s*backend\b') { continue }
        # Accept ANY guard form:
        #   Managers.backend and ...
        #   Managers.backend ~= nil
        #   if Managers.backend then
        #   if not Managers.backend then return end
        #   local x = Managers and Managers.backend
        $guarded =
            ($body -match 'Managers\s*\.\s*backend\s+and\b') -or
            ($body -match 'Managers\s*\.\s*backend\s*~=\s*nil') -or
            ($body -match 'if\s+Managers\s*\.\s*backend\b') -or
            ($body -match 'if\s+not\s+Managers\s*\.\s*backend\b') -or
            ($body -match 'Managers\s+and\s+Managers\s*\.\s*backend')

        if (-not $guarded) {
            $findings += [pscustomobject]@{
                File   = $File
                Line   = $startLine
                Kind   = 'create_interfaces_unguarded'
                Detail = "_create_interfaces hook reads Managers.backend without nil-check guard"
            }
        }
    }

    return ,$findings
}

# ---- mod-level scan ----
function Lint-Mod {
    param([string]$ModFolder)

    $modName = Split-Path -Leaf $ModFolder
    $files = Get-ModLuaFiles -ModFolder $ModFolder
    $hooks       = New-Object System.Collections.Generic.List[object]
    $forwardRefs = New-Object System.Collections.Generic.List[object]
    $saveRestore = New-Object System.Collections.Generic.List[object]

    foreach ($f in $files) {
        $raw = Read-LuaText -Path $f
        # `stripped` = comments removed AND short-string interiors blanked. Keeps
        # line numbers stable. Used for closure/balance scans where Lua keywords
        # inside string literals would otherwise inflate counts.
        $stripped = Strip-LuaCommentsAndStrings -Text $raw
        # `commentsOnly` = comments removed BUT short strings preserved. Used for
        # hook detection so class/method literals are still readable.
        $commentsOnly = Strip-LuaComments -Text $raw
        $literalTables = Get-LiteralStringTables -Text $commentsOnly
        $hookRows = Find-HookRegistrations -File $f -Text $commentsOnly -LiteralTables $literalTables
        foreach ($r in $hookRows) { [void]$hooks.Add($r) }
        $fwds = Find-ForwardRefIssues -File $f -RawText $raw -StripText $stripped
        foreach ($r in $fwds) { [void]$forwardRefs.Add($r) }
        $sr = Find-SaveRestoreIssues -File $f -Text $commentsOnly
        foreach ($r in $sr) { [void]$saveRestore.Add($r) }
    }

    $dupes = Find-DuplicateHooks -AllHooks $hooks.ToArray()

    return [pscustomobject]@{
        ModName      = $modName
        ModFolder    = $ModFolder
        FileCount    = $files.Count
        HookCount    = $hooks.Count
        Duplicates   = $dupes
        ForwardRefs  = $forwardRefs.ToArray()
        SaveRestore  = $saveRestore.ToArray()
    }
}

# ---- mod path resolution ----
function Resolve-ModFolders {
    param([string]$ModPathArg)

    if (-not $ModPathArg) {
        $folders = @()
        foreach ($m in $KnownMods) {
            $p = Join-Path $repoRoot $m
            if (Test-Path $p) { $folders += (Resolve-Path $p).Path }
        }
        return $folders
    }

    # Treat as either absolute, repo-relative, or bare mod name
    if (Test-Path $ModPathArg) {
        return @( (Resolve-Path $ModPathArg).Path )
    }
    $rel = Join-Path $repoRoot $ModPathArg
    if (Test-Path $rel) {
        return @( (Resolve-Path $rel).Path )
    }
    throw "Mod path not found: $ModPathArg"
}

# ---- output ----
function Emit-Report {
    param([array]$Reports, [bool]$Quiet, [bool]$Strict)

    $exit = 0
    $totalDupes = 0
    $totalFwd   = 0
    $totalSR    = 0

    foreach ($r in $Reports) {
        $hasDupes = $r.Duplicates.Count -gt 0
        $hasFwd   = $r.ForwardRefs.Count -gt 0
        $hasSR    = $r.SaveRestore.Count -gt 0
        $totalDupes += $r.Duplicates.Count
        $totalFwd   += $r.ForwardRefs.Count
        $totalSR    += $r.SaveRestore.Count

        # Severity ladder:
        #   duplicates           -> always ERROR (exit 2)
        #   forward-refs         -> WARN (exit 1), or ERROR (exit 2) under -Strict
        #   save/restore         -> WARN (exit 1), or ERROR (exit 2) under -Strict
        if ($hasDupes) {
            $status = 'FAIL'; $color = 'Red'; $exit = [Math]::Max($exit, 2)
        } elseif (($hasFwd -or $hasSR) -and $Strict) {
            $status = 'FAIL'; $color = 'Red'; $exit = [Math]::Max($exit, 2)
        } elseif ($hasFwd -or $hasSR) {
            $status = 'WARN'; $color = 'Yellow'; if ($exit -lt 1) { $exit = 1 }
        } else {
            $status = 'PASS'; $color = 'Green'
        }

        Write-Host ("[{0}] {1}  ({2} files, {3} hooks)" -f $status, $r.ModName, $r.FileCount, $r.HookCount) -ForegroundColor $color

        if ($hasDupes) {
            foreach ($d in $r.Duplicates) {
                Write-Host ("  DUPLICATE HOOK: {0}.{1}" -f $d.Class, $d.Method) -ForegroundColor Red
                foreach ($loc in $d.Locations) {
                    $rel = $loc.File
                    if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                    Write-Host ("    {0}:{1}  {2}" -f $rel, $loc.Line, $loc.SourceLine)
                }
            }
        }
        if ($hasFwd) {
            foreach ($f in $r.ForwardRefs) {
                $rel = $f.File
                if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                Write-Host ("  FORWARD-REF: '{0}' defined {1}:{2}, first used at line {3} (no forward decl)" -f $f.Name, $rel, $f.DefLine, $f.FirstUseLine) -ForegroundColor Yellow
            }
        }
        if ($hasSR) {
            $srColor = if ($Strict) { 'Red' } else { 'Yellow' }
            $srTag   = if ($Strict) { 'SAVE-RESTORE' } else { 'SAVE-RESTORE (warn)' }
            foreach ($s in $r.SaveRestore) {
                $rel = $s.File
                if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                Write-Host ("  {0} [{1}] {2}:{3}  {4}" -f $srTag, $s.Kind, $rel, $s.Line, $s.Detail) -ForegroundColor $srColor
            }
        }
    }

    Write-Host ""
    $sev = if ($Strict) { 'error(s)' } else { 'warning(s)' }
    Write-Host ("Summary: {0} mod(s) scanned, {1} duplicate-hook error(s), {2} forward-ref warning(s), {3} save/restore {4}" -f $Reports.Count, $totalDupes, $totalFwd, $totalSR, $sev)
    if ($Strict -and ($totalFwd -gt 0 -or $totalSR -gt 0)) {
        Write-Host "(-Strict: forward-ref + save/restore findings promoted to error level)" -ForegroundColor DarkGray
    }
    return $exit
}

# ---- main ----
$modFolders = Resolve-ModFolders -ModPathArg $ModPath
$reports = @()
foreach ($f in $modFolders) {
    $reports += Lint-Mod -ModFolder $f
}

$exitCode = Emit-Report -Reports $reports -Quiet:$Quiet -Strict:$Strict

if ($Json -or $JsonPath) {
    $jsonOut = if ($JsonPath) { $JsonPath } else { Join-Path $repoRoot '.release-stage\mod-lint.json' }
    $parent = Split-Path -Parent $jsonOut
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $payload = [ordered]@{
        scanned_at = (Get-Date).ToUniversalTime().ToString('o')
        exit_code  = $exitCode
        strict     = [bool]$Strict
        mods = @(
            foreach ($r in $reports) {
                [ordered]@{
                    mod          = $r.ModName
                    files        = $r.FileCount
                    hooks        = $r.HookCount
                    duplicates   = @(
                        foreach ($d in $r.Duplicates) {
                            [ordered]@{
                                class    = $d.Class
                                method   = $d.Method
                                sites    = @(
                                    foreach ($loc in $d.Locations) {
                                        $rel = $loc.File
                                        if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                                        [ordered]@{ file = $rel; line = $loc.Line; source = $loc.SourceLine }
                                    }
                                )
                            }
                        }
                    )
                    forward_refs = @(
                        foreach ($fw in $r.ForwardRefs) {
                            $rel = $fw.File
                            if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                            [ordered]@{ file = $rel; name = $fw.Name; def_line = $fw.DefLine; first_use_line = $fw.FirstUseLine }
                        }
                    )
                    save_restore = @(
                        foreach ($sr in $r.SaveRestore) {
                            $rel = $sr.File
                            if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                            [ordered]@{ file = $rel; line = $sr.Line; kind = $sr.Kind; detail = $sr.Detail }
                        }
                    )
                }
            }
        )
    }
    $payload | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonOut -Encoding utf8
    Write-Host "JSON report: $jsonOut"
}

exit $exitCode
