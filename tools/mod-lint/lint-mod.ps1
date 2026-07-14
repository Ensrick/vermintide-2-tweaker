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
#   3. Late-local-shadows-global (added 2026-05-23 after ct GUID
#      4c5d2157-e5ee-45fd-8f49-ecdcd2e7ade3 chest-of-trials crash):
#      a top-level `local NAME = ...` declared LATE in the file while closures
#      earlier in the file reference `NAME`. Lua scope is LEXICAL: every earlier
#      reference resolved as `_G.NAME` (typically nil) at closure-capture time,
#      NOT the late local. Symptom is silent until the closure runs.
#
#      The ct fix: `local DORMANT_BOON_RARITY = {}` was declared at L4707 to
#      "no-op" the dormant-boon path, but the `generate_random_power_ups` hook
#      at L880 and `_should_strip` at L1144 — both lexically ABOVE the local —
#      resolved to nil `_G.DORMANT_BOON_RARITY` and crashed first chest spawn.
#      Fix replaced the local with an explicit `_G.DORMANT_BOON_RARITY = ...`
#      at the top of the file. This check guards against the regression.
#
#      Heuristic: only flag UPPERCASE_SNAKE names (data tables, not functions —
#      functions use snake_case and are covered by the existing forward-ref
#      check). Default WARN; promoted to error under -Strict.
#
#   5. Network-bound engine field mutation (added 2026-05-23 after two ct
#      crashes in the same bug class):
#        v0.7.80-alpha  — ct_meta_ammo set `stat_buff = "max_overcharge"`,
#                         exceeded the engine's overcharge network cap (~60),
#                         crashed Sienna + Bardin drakefire users.
#        v0.7.100-dev   — ct_meta_ammo directly mutated `energy_ext._max_energy`,
#                         exceeded the engine's max_energy network cap (~60),
#                         crashed on Necromancer bot.
#      The engine's `.network_config` binary has hardcoded ints for these
#      fields; mods that exceed the cap crash via fassert in vanilla code,
#      typically from a buff_extension / inventory rpc handler the mod
#      doesn't touch. Always clamp on the way in.
#
#      HEURISTIC REFINED 2026-05-29: the rule now flags WIDENING writes ONLY,
#      and no longer fires on the two recurring false positives. Pattern B
#      (stat_buff = "max_*" string literal) is REMOVED entirely.
#
#      WHAT FIRES (Pattern A — dangerous WIDENING field assignment):
#         <ident>._max_(overcharge|energy|ammo|charge|health|stamina|push_power) = <rhs>
#      e.g. `self._max_health = big`, `ext._max_ammo = ext._max_ammo * 2`.
#
#      WHAT NO LONGER FIRES:
#        (a) `stat_buff = "max_health"` / `"max_ammo"` etc. — buff-TEMPLATE
#            string literals in data tables, resolved by the engine's own
#            (network-safe) buff system; never a raw field write. The old
#            Pattern B false-positived on crt's two `stat_buff = "max_health"`
#            data entries. Pattern B removed.
#        (b) Downward safety CLAMPS — recognised as SAFE so the load-bearing
#            ct:7831 clamp survives:
#              * `<target> = math.min(...)` / `math.max(..., math.min(...))`
#              * guarded clamp: assignment whose line (or the line just above)
#                compares the SAME field with `> CONST`, e.g.
#                  `if self._max_ammo > 9999 then self._max_ammo = 9999 end`.
#            Canonical safe case: chaos_wastes_tweaker.lua:7831 (a CW boon
#            widened `_max_ammo` past the NetworkConstants ceiling and crashed
#            the host; this clamp is the FIX).
#
#      Fires as WARNING (exit 1); promoted to error (exit 2) under -Strict.
#      Further exclusions: comments / nearby `-- LINT_OK_NETBOUND` annotation /
#      `==` equality comparison / read access.
#
#   4. Save/restore invariants (added 2026-05-23 after the cim "stale
#      modded_loadout overwrites vanilla restore on next session" user report):
#        4a. `BackendInterfaceItemPlayfab.set_loadout_item` hooks that
#            persist a modded-loadout entry MUST also clear it before saving,
#            otherwise switching back to a vanilla item leaves a stale cim
#            entry that clobbers the next session's restore.
#        4b. Every `mod:set("KEY", ...)` must have a matching `mod:get("KEY")`
#            somewhere in the same file. Catches save-without-load typos
#            that silently lose persistence.
#        4c. Any `mod:hook_safe("BackendManagerPlayFab", "_create_interfaces",
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
#   .\lint-mod.ps1 -SelfTest                          # verify the linter itself
#
# Exit codes:
#   0 - clean
#   1 - warnings only (forward-ref + late-local + save/restore + network-bound)
#   2 - errors found (duplicate hooks; with -Strict, also late-local + save/restore + network-bound)
#
# Output:
#   - human-readable PASS/FAIL per mod plus per-finding file:line
#   - optional JSON sidecar at <repo>/.release-stage/mod-lint.json (or -JsonPath)

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ModPath,

    # NAMED-ONLY (no Position) on purpose. Issue #214: this used to be the second
    # positional parameter, so `lint-mod.ps1 a.lua b.lua` bound b.lua to $JsonPath
    # and the JSON report OVERWROTE b.lua (destroyed a gt_dev source file on
    # 2026-07-01). It must now be passed as `-JsonPath <file.json>`; a stray second
    # positional arg errors loudly ("positional parameter cannot be found")
    # instead of clobbering a file.
    [Parameter()]
    [string]$JsonPath,

    [switch]$Json,
    [switch]$Quiet,
    [switch]$Strict,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# ---- mod inventory (single source of truth: tools/mod-inventory.psd1) ----
# Previously a hand-maintained literal that drifted: it listed RETIRED
# `lobby_tweaker` / `material_hijack_patched` and OMITTED all four `*_dev`
# clones (so a duplicate-hook in a dev tree went unscanned). Now sourced from
# the shared .psd1 so mod-lint, publish-release, and check_cfg can't diverge.
# Missing inventory is fatal: a fallback list recreates the drift this file was
# introduced to eliminate.
$inventoryPath = Join-Path $repoRoot 'tools\mod-inventory.psd1'
if (Test-Path $inventoryPath) {
    $inventory = Import-PowerShellDataFile -Path $inventoryPath
    $KnownMods = @($inventory.Mods | ForEach-Object { $_.Dir })
} else {
    Write-Host "[lint-mod] ERROR - canonical tools/mod-inventory.psd1 is missing." -ForegroundColor Red
    exit 2
}

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

# ---- pattern 3: late-local-shadows-global ----
# Catches the v0.7.99-dev ct DORMANT_BOON_RARITY scope bug (GUID
# 4c5d2157-e5ee-45fd-8f49-ecdcd2e7ade3): a top-level `local NAME = ...`
# declared LATE in the file while closures EARLIER in the file reference
# `NAME`. Lua local scope is lexical — those earlier references resolve to
# `_G.NAME` (often nil), not the late local.
#
# We restrict the check to ALL_CAPS_SNAKE names (`^local NAME = ...`) for two
# reasons:
#   * Convention in this repo: ALL_CAPS_SNAKE is reserved for module-level
#     data tables (DORMANT_BOON_RARITY, CT_TRAIT_BOONS, etc.); functions use
#     lowercase_snake. Snake-case functions are already covered by the
#     existing `Find-ForwardRefIssues` check (different mechanism but same
#     class of bug).
#   * The user's spec calls out this exact heuristic to keep false-positive
#     rate low. A future generalization would need to distinguish locals
#     holding non-function values from forward-declared function locals.
#
# Algorithm:
#   1. Single pass over comment-stripped lines (strings blanked too — don't
#      want to false-match an ALL_CAPS name appearing inside a string body).
#   2. Collect every column-0 `^local NAME = <not '(' or 'function'>` where
#      NAME matches `^[A-Z_][A-Z0-9_]*$`. Skip `local function NAME` and
#      `local NAME = function(` (those are the forward-ref check's domain).
#      Record (Name, DeclLine).
#   3. For each (Name, DeclLine), scan lines 1..DeclLine-1 for a word-bounded
#      reference to `NAME` that is NOT preceded by `.` or `:` (table-field
#      access — those bind to a table member, not the closure upvalue).
#      Skip the matching line ITSELF if it is also a `local NAME` /
#      `NAME =` declaration site for the same name.
#   4. If any earlier reference is found, emit a finding pointing at both
#      sites (file:earlier-line + file:decl-line + closure-or-toplevel
#      sub-class).
#
# False-positive guards:
#   * Comments are stripped (preserving newlines) — won't match a name
#     inside a `-- description: DORMANT_BOON_RARITY ...` comment.
#   * String literals are blanked — won't match `error("DORMANT_BOON_RARITY
#     is not set")`.
#   * Re-declaration / assignment lines (`local NAME = ...` or `NAME =` at
#     column 0 with whitespace prefix) are excluded so we don't flag the
#     declaration itself as a reference.
#   * Table-field accesses (`obj.NAME`, `obj:NAME`) are excluded.
#
# Output rows: @{ File; Name; DeclLine; FirstUseLine; InClosure }
#   - InClosure $true  -> high risk (closure captures _G.NAME at definition
#                         time; runs after the line that creates the local).
#   - InClosure $false -> top-level executable code; even worse (literally
#                         runs before the late local is defined).
function Find-LateLocalShadowing {
    param(
        [string]$File,
        [string]$StripText   # comment-stripped AND string-interior-blanked
    )

    $findings = @()
    $lines = $StripText -split "`r?`n"

    # 1) Collect top-level late ALL_CAPS_SNAKE locals (data tables).
    # Require column-0 `local NAME =` followed by anything except `(` or
    # `function` (so we skip both `local NAME = function(` and the
    # unusual `local NAME = (function() ... end)()` IIFE form, which
    # behaves like a function declaration for our purposes).
    $rxLateLocal = [regex]'^local\s+([A-Z_][A-Z0-9_]*)\s*=\s*([^(]|f(?!unction\b)|fu(?!nction\b))'

    $lateLocals = @{}   # name -> first DeclLine
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = $rxLateLocal.Match($lines[$i])
        if ($m.Success) {
            $name = $m.Groups[1].Value
            if (-not $lateLocals.ContainsKey($name)) {
                $lateLocals[$name] = $i + 1
            }
        }
    }

    if ($lateLocals.Count -eq 0) { return ,$findings }

    # 2) Locate every function-body extent so we can classify each earlier
    # reference as "inside a function body" (high risk — captures the free
    # variable at definition time, which is _G.NAME because the local
    # doesn't exist yet) vs "at top-level executable code" (also wrong —
    # executes immediately at load, before the late local exists).
    #
    # We track BOTH:
    #   * anonymous closures: `function(`
    #   * named function definitions: `function <name>(` and `local function <name>(`
    # because the upvalue-capture semantics are the same — a named-function
    # body defined ABOVE the late local sees the free reference as a global,
    # exactly like an anonymous closure does. The ct pre-fix bug had
    # `local function _should_strip(name)` AND a `mod:hook` anonymous
    # closure — both bound to _G.DORMANT_BOON_RARITY.
    $rxFnStart   = [regex]'(^|[^A-Za-z0-9_])function\b\s*(?:[A-Za-z_][A-Za-z0-9_.:]*\s*)?\('
    $openWordRx  = [regex]'\b(function|if|while|for|repeat)\b'
    $closeWordRx = [regex]'\b(end|until)\b'

    $closures = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        foreach ($sm in $rxFnStart.Matches($line)) {
            $startLine = $i + 1
            $balance = 1
            $startCol = $sm.Index + $sm.Length
            $tail = $line.Substring([Math]::Min($startCol, $line.Length))
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
            $closures += @{ StartLine = $startLine; EndLine = $endLine }
        }
    }

    # 3) For each late local, find the EARLIEST reference above DeclLine.
    # Word-boundary identifier match, excluding `.NAME` / `:NAME` (table
    # access) — same regex as Find-ForwardRefIssues uses.
    $idCache = @{}  # name -> regex
    foreach ($name in $lateLocals.Keys) {
        $idCache[$name] = [regex]("(?<![.:A-Za-z0-9_])$([regex]::Escape($name))\b")
    }

    # Also need to skip lines that are themselves a `local NAME =` or
    # `NAME =` (assignment) for the same name — those don't constitute
    # a "use" of the upvalue, they create / overwrite it.
    $rxDeclLine = @{}
    foreach ($name in $lateLocals.Keys) {
        $esc = [regex]::Escape($name)
        # Either: `local <name> = ...` (any indent) OR `<name> = ...`
        # (any indent), where `<name>` is the standalone identifier.
        $rxDeclLine[$name] = [regex]("^\s*(local\s+)?$esc\s*=")
    }

    foreach ($name in $lateLocals.Keys) {
        $declLine = $lateLocals[$name]
        $idRx     = $idCache[$name]
        $declRx   = $rxDeclLine[$name]

        $witnessLine = 0
        $witnessInClosure = $false
        for ($i = 0; $i -lt ($declLine - 1) -and $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            if (-not $idRx.IsMatch($line)) { continue }
            if ($declRx.IsMatch($line)) { continue }   # re-decl / assignment line, not a use

            $lineNo = $i + 1
            $inClosure = $false
            foreach ($c in $closures) {
                if ($lineNo -ge $c.StartLine -and $lineNo -le $c.EndLine) {
                    $inClosure = $true
                    break
                }
            }
            $witnessLine = $lineNo
            $witnessInClosure = $inClosure
            break  # earliest wins
        }

        if ($witnessLine -gt 0) {
            $findings += [pscustomobject]@{
                File         = $File
                Name         = $name
                DeclLine     = $declLine
                FirstUseLine = $witnessLine
                InClosure    = $witnessInClosure
            }
        }
    }

    return ,$findings
}

# ---- pattern 4: save/restore invariants ----
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

# ---- pattern 5: network-bound engine field WIDENING ----
# Catches the v0.7.100-dev (`energy_ext._max_energy = ...`) ct crash. The engine
# `.network_config` binary has hardcoded ints for these fields and fasserts when
# a peer observes a value outside the bound, so a mod that RAISES (widens) the
# cap crashes. The rule flags WIDENING field assignments ONLY.
#
# Heuristic refined 2026-05-29 to eliminate two recurring false positives while
# preserving real widening detection. See the module header comment for the full
# rationale + burn citations.
#
# Single regex pass:
#   Pattern A — direct field assignment
#     <ident>._max_(overcharge|energy|ammo|charge|health|stamina|push_power)
#       \s*=\s*<rhs>
#
# (Former "Pattern B" — `stat_buff = "max_*"` string literal — has been REMOVED.
# A buff-template stat_buff key is a data-table string resolved by the engine's
# own network-safe buff system, NOT a raw field write; it false-positived on
# crt's two `stat_buff = "max_health"` entries.)
#
# Exclusions (treat as SAFE — do NOT flag):
#   - Comments / strings — handled because the input is already comment-stripped.
#   - `-- LINT_OK_NETBOUND: <reason>` annotation on the SAME line or up to
#     2 lines ABOVE — manual escape hatch for audited sites.
#   - `==` equality comparison (negative lookahead on `=`) — read, not write.
#   - DOWNWARD CLAMP idioms (the FIX for the crash, must never be flagged):
#       (i)  RHS passes through math.min(...) / math.max(..., math.min(...)).
#       (ii) GUARDED clamp — the assignment line, or a line up to 2 above it,
#            compares the SAME `_max_<field>` with `> CONST` / `>= CONST`
#            (e.g. `if self._max_ammo > 9999 then self._max_ammo = 9999 end`).
#            This is the canonical chaos_wastes_tweaker.lua:7831 safe case.
#
# Output rows:
#   @{ File; Line; Kind; Field; Detail }
# where Kind:
#   netbound_assign  - dangerous WIDENING mutation of a network-bounded field
function Find-NetworkBoundMutation {
    param(
        [string]$File,
        [string]$RawText,    # pre-strip — used to detect comment annotations
        [string]$Text        # comments-stripped, short strings KEPT
    )

    $findings = @()
    $lines    = $Text -split "`r?`n"
    $rawLines = $RawText -split "`r?`n"

    # Pattern A: `<ident>._max_<field> = <rhs>` — require NOT `==`. The negative
    # lookahead `=(?!=)` rejects equality comparisons.
    $rxAssign     = [regex]'\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*_max_(overcharge|energy|ammo|charge|health|stamina|push_power)\b\s*=(?!=)\s*(.*)$'
    # Suppression annotation: `-- LINT_OK_NETBOUND[:...]` anywhere in a raw line.
    $rxAnnotation = [regex]'--\s*LINT_OK_NETBOUND\b'
    # math.min/max clamp heuristic on the RHS.
    $rxClamp      = [regex]'\bmath\s*\.\s*min\s*\('

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Pattern A: direct field assignment.
        foreach ($m in $rxAssign.Matches($line)) {
            $ident = $m.Groups[1].Value
            $fieldSuffix = $m.Groups[2].Value
            $field = '_max_' + $fieldSuffix
            $rhs   = $m.Groups[3].Value

            # Suppression: LINT_OK_NETBOUND on same line or up to 2 lines above.
            $annotated = $false
            $lo = [Math]::Max(0, $i - 2)
            for ($k = $lo; $k -le $i -and $k -lt $rawLines.Count; $k++) {
                if ($rxAnnotation.IsMatch($rawLines[$k])) { $annotated = $true; break }
            }
            if ($annotated) { continue }

            # Clamp suppression (i): RHS contains math.min(...). Tolerant —
            # accepts `math.min(x, 60)`, `math.max(1, math.min(x, 60))`, etc.
            if ($rxClamp.IsMatch($rhs)) { continue }

            # Clamp suppression (ii): GUARDED downward clamp. The assignment is
            # safe if the SAME `_max_<field>` is compared with `> CONST` /
            # `>= CONST` on this line or up to 2 lines above (the `if X > CAP
            # then X = CAP end` idiom — ct:7831). We match the field SUFFIX so
            # the guard `self._max_ammo > 9999` protects `self._max_ammo = 9999`
            # regardless of the receiver identifier.
            $rxGuard = [regex]("_max_" + [regex]::Escape($fieldSuffix) + '\b\s*>=?\s*[-\d]')
            $guarded = $false
            for ($k = $lo; $k -le $i -and $k -lt $lines.Count; $k++) {
                if ($rxGuard.IsMatch($lines[$k])) { $guarded = $true; break }
            }
            if ($guarded) { continue }

            $findings += [pscustomobject]@{
                File   = $File
                Line   = $i + 1
                Kind   = 'netbound_assign'
                Field  = "$ident.$field"
                Detail = "WIDENING write to network-bounded engine field $field; raising this cap crashes peers via fassert. Clamp downward (math.min / `if X > CAP then X = CAP`) or use the consumption-side stat_buff. See chaos_wastes_tweaker v0.7.100-dev CHANGELOG + ct:7831 clamp."
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
    $lateLocals  = New-Object System.Collections.Generic.List[object]
    $saveRestore = New-Object System.Collections.Generic.List[object]
    $netBound    = New-Object System.Collections.Generic.List[object]

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
        $lls = Find-LateLocalShadowing -File $f -StripText $stripped
        foreach ($r in $lls) { [void]$lateLocals.Add($r) }
        $sr = Find-SaveRestoreIssues -File $f -Text $commentsOnly
        foreach ($r in $sr) { [void]$saveRestore.Add($r) }
        # Network-bound mutation needs comments-stripped (so commented-out
        # patterns don't fire) but raw for LINT_OK_NETBOUND annotation detect.
        $nbm = Find-NetworkBoundMutation -File $f -RawText $raw -Text $commentsOnly
        foreach ($r in $nbm) { [void]$netBound.Add($r) }
    }

    $dupes = Find-DuplicateHooks -AllHooks $hooks.ToArray()

    return [pscustomobject]@{
        ModName      = $modName
        ModFolder    = $ModFolder
        FileCount    = $files.Count
        HookCount    = $hooks.Count
        Duplicates   = $dupes
        ForwardRefs  = $forwardRefs.ToArray()
        LateLocals   = $lateLocals.ToArray()
        SaveRestore  = $saveRestore.ToArray()
        NetBound     = $netBound.ToArray()
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
    $totalLL    = 0
    $totalSR    = 0
    $totalNB    = 0

    foreach ($r in $Reports) {
        $hasDupes = $r.Duplicates.Count -gt 0
        $hasFwd   = $r.ForwardRefs.Count -gt 0
        $hasLL    = $r.LateLocals.Count -gt 0
        $hasSR    = $r.SaveRestore.Count -gt 0
        $hasNB    = $r.NetBound.Count -gt 0
        $totalDupes += $r.Duplicates.Count
        $totalFwd   += $r.ForwardRefs.Count
        $totalLL    += $r.LateLocals.Count
        $totalSR    += $r.SaveRestore.Count
        $totalNB    += $r.NetBound.Count

        # Severity ladder:
        #   duplicates                 -> always ERROR (exit 2)
        #   forward-refs               -> WARN (exit 1), or ERROR under -Strict
        #   late-local-shadows-global  -> WARN (exit 1), or ERROR under -Strict
        #   save/restore               -> WARN (exit 1), or ERROR under -Strict
        #   network-bound mutation     -> WARN (exit 1), or ERROR under -Strict
        if ($hasDupes) {
            $status = 'FAIL'; $color = 'Red'; $exit = [Math]::Max($exit, 2)
        } elseif (($hasFwd -or $hasLL -or $hasSR -or $hasNB) -and $Strict) {
            $status = 'FAIL'; $color = 'Red'; $exit = [Math]::Max($exit, 2)
        } elseif ($hasFwd -or $hasLL -or $hasSR -or $hasNB) {
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
        if ($hasLL) {
            $llColor = if ($Strict) { 'Red' } else { 'Yellow' }
            foreach ($l in $r.LateLocals) {
                $rel = $l.File
                if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                $ctxt = if ($l.InClosure) { 'function body' } else { 'top-level code' }
                Write-Host ("  LATE-LOCAL-SHADOWS-GLOBAL: '{0}' referenced from {1} at {2}:{3} but declared at line {4} (earlier ref resolves to _G.{0}, not the local)" -f $l.Name, $ctxt, $rel, $l.FirstUseLine, $l.DeclLine) -ForegroundColor $llColor
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
        if ($hasNB) {
            $nbColor = if ($Strict) { 'Red' } else { 'Yellow' }
            $nbTag   = if ($Strict) { 'NETWORK-BOUND-MUTATION' } else { 'NETWORK-BOUND-MUTATION (warn)' }
            foreach ($n in $r.NetBound) {
                $rel = $n.File
                if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                Write-Host ("  {0} [{1}] {2}:{3}  {4}" -f $nbTag, $n.Kind, $rel, $n.Line, $n.Detail) -ForegroundColor $nbColor
            }
        }
    }

    Write-Host ""
    $sev = if ($Strict) { 'error(s)' } else { 'warning(s)' }
    Write-Host ("Summary: {0} mod(s) scanned, {1} duplicate-hook error(s), {2} forward-ref warning(s), {3} late-local warning(s), {4} save/restore + {5} network-bound {6}" -f $Reports.Count, $totalDupes, $totalFwd, $totalLL, $totalSR, $totalNB, $sev)
    if ($Strict -and ($totalFwd -gt 0 -or $totalLL -gt 0 -or $totalSR -gt 0 -or $totalNB -gt 0)) {
        Write-Host "(-Strict: forward-ref + late-local + save/restore + network-bound findings promoted to error level)" -ForegroundColor DarkGray
    }
    return $exit
}

# ---- self-test ----
# Synthesizes in-memory fixtures and runs the Find-LateLocalShadowing detector
# against each. Other checks (duplicate-hooks, forward-ref) already have file-
# system fixtures under test_fixtures/; this self-test is scoped to the new
# late-local check the harness can't easily express on disk (we'd need a
# multi-thousand-line bad mod to keep the scope realistic).
function Invoke-LateLocalSelfTest {
    Write-Host "lint-mod: running self-test for late-local-shadows-global"

    $results = New-Object 'System.Collections.Generic.List[object]'

    function _Record {
        param([string]$Name, [bool]$Pass, [string]$Detail)
        $results.Add(@{ Name = $Name; Pass = $Pass; Detail = $Detail })
        $tag = if ($Pass) { 'PASS' } else { 'FAIL' }
        $col = if ($Pass) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1} {2}" -f $tag, $Name, $Detail) -ForegroundColor $col
    }

    function _Run {
        param([string]$Source)
        # Mimic Lint-Mod's per-file prep without touching disk.
        $stripped = Strip-LuaCommentsAndStrings -Text $Source
        return Find-LateLocalShadowing -File '(memory)' -StripText $stripped
    }

    # --- Bad fixture: closure at L10 references MY_TABLE, late local at L100 ---
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('local mod = get_mod("st_late_local")')                  # L1
    [void]$sb.AppendLine('')                                                       # L2
    [void]$sb.AppendLine('-- closure references MY_TABLE before declaration')     # L3
    [void]$sb.AppendLine('mod:hook("Foo", "bar", function(func, self)')           # L4
    [void]$sb.AppendLine('    for k, v in pairs(MY_TABLE) do')                    # L5
    [void]$sb.AppendLine('        print(k, v)')                                    # L6
    [void]$sb.AppendLine('    end')                                                # L7
    [void]$sb.AppendLine('    return func(self)')                                  # L8
    [void]$sb.AppendLine('end)')                                                   # L9
    # Pad to ~L100 so we're testing the actual "late" case.
    for ($k = 10; $k -lt 100; $k++) { [void]$sb.AppendLine('-- filler ' + $k) }
    [void]$sb.AppendLine('local MY_TABLE = {')                                     # L100
    [void]$sb.AppendLine('    foo = "bar",')                                       # L101
    [void]$sb.AppendLine('}')                                                      # L102
    $found = _Run -Source $sb.ToString()
    $hit = @($found | Where-Object { $_.Name -eq 'MY_TABLE' })
    $hitInClosure = $hit.Count -eq 1 -and $hit[0].InClosure -eq $true
    $detail = if ($hit.Count -eq 1) { "decl=$($hit[0].DeclLine) ref=$($hit[0].FirstUseLine) closure=$($hit[0].InClosure)" } else { "no finding" }
    _Record -Name 'bad: late-decl after closure ref' -Pass ($hit.Count -eq 1) -Detail $detail
    _Record -Name 'bad: classified as closure ref' -Pass $hitInClosure -Detail ""

    # --- Good fixture: local declared at L10, closure at L100 references it ---
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('local mod = get_mod("st_late_local_ok")')               # L1
    for ($k = 2; $k -le 9; $k++) { [void]$sb.AppendLine('-- filler ' + $k) }      # L2-L9
    [void]$sb.AppendLine('local MY_TABLE = { foo = "bar" }')                       # L10
    for ($k = 11; $k -lt 100; $k++) { [void]$sb.AppendLine('-- filler ' + $k) }
    [void]$sb.AppendLine('mod:hook("Foo", "bar", function(func, self)')           # L100
    [void]$sb.AppendLine('    return MY_TABLE.foo')                                # L101
    [void]$sb.AppendLine('end)')                                                   # L102
    $found = _Run -Source $sb.ToString()
    $hit = @($found | Where-Object { $_.Name -eq 'MY_TABLE' })
    $detail = if ($hit.Count -eq 0) { "" } else { "false positive on line $($hit[0].FirstUseLine)" }
    _Record -Name 'good: early-decl + late closure ref' -Pass ($hit.Count -eq 0) -Detail $detail

    # --- Good fixture: forward-declared local-function pattern is fine ---
    # `local foo; function foo() end` is the canonical Lua forward-decl. Our
    # check is restricted to ALL_CAPS names, so a lowercase function shouldn't
    # be flagged. We still verify by writing it that way to lock in the
    # contract.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('local mod = get_mod("st_forward_decl_ok")')             # L1
    [void]$sb.AppendLine('local foo')                                              # L2 (forward decl)
    [void]$sb.AppendLine('mod:hook("Foo", "bar", function(func, self)')           # L3
    [void]$sb.AppendLine('    return foo(self)')                                   # L4 - refs foo
    [void]$sb.AppendLine('end)')                                                   # L5
    [void]$sb.AppendLine('function foo(x) return x end')                           # L6
    $found = _Run -Source $sb.ToString()
    $hit = @($found | Where-Object { $_.Name -eq 'foo' })
    _Record -Name 'good: lowercase forward-declared fn (not in scope)' `
        -Pass ($hit.Count -eq 0) -Detail ""

    # --- Bad fixture: top-level executable code references late local ---
    # Different from the closure case — this would crash immediately at load,
    # not just at first closure invocation. Still reportable.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('local mod = get_mod("st_late_local_toplevel")')         # L1
    [void]$sb.AppendLine('')                                                       # L2
    [void]$sb.AppendLine('-- top-level executable use of MY_DATA')                 # L3
    [void]$sb.AppendLine('for k, v in pairs(MY_DATA) do print(k) end')             # L4
    for ($k = 5; $k -lt 50; $k++) { [void]$sb.AppendLine('-- filler ' + $k) }
    [void]$sb.AppendLine('local MY_DATA = { a = 1 }')                              # L50
    $found = _Run -Source $sb.ToString()
    $hit = @($found | Where-Object { $_.Name -eq 'MY_DATA' })
    $hitTopLevel = $hit.Count -eq 1 -and $hit[0].InClosure -eq $false
    $detail = if ($hit.Count -eq 1) { "decl=$($hit[0].DeclLine) ref=$($hit[0].FirstUseLine) closure=$($hit[0].InClosure)" } else { "no finding" }
    _Record -Name 'bad: top-level pre-decl ref' -Pass $hitTopLevel -Detail $detail

    # --- Good fixture: comment / string mention of NAME before decl ---
    # Refs inside comments and string literals must NOT trigger.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('local mod = get_mod("st_late_local_comment")')          # L1
    [void]$sb.AppendLine('-- This file uses MY_TABLE for X reasons')               # L2
    [void]$sb.AppendLine('local foo = "uses MY_TABLE internally"')                 # L3
    [void]$sb.AppendLine('local bar = function() return 1 end')                    # L4
    [void]$sb.AppendLine('local MY_TABLE = {}')                                    # L5
    $found = _Run -Source $sb.ToString()
    $hit = @($found | Where-Object { $_.Name -eq 'MY_TABLE' })
    $detail = if ($hit.Count -eq 0) { "" } else { "false positive on line $($hit[0].FirstUseLine)" }
    _Record -Name 'good: comment/string mention does not trigger' -Pass ($hit.Count -eq 0) -Detail $detail

    # --- Good fixture: table-field access (obj.NAME) does not trigger ---
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('local mod = get_mod("st_late_local_field")')            # L1
    [void]$sb.AppendLine('local function f(obj)')                                  # L2
    [void]$sb.AppendLine('    return obj.MY_TABLE')                                # L3 - field access
    [void]$sb.AppendLine('end')                                                    # L4
    [void]$sb.AppendLine('local MY_TABLE = {}')                                    # L5
    $found = _Run -Source $sb.ToString()
    $hit = @($found | Where-Object { $_.Name -eq 'MY_TABLE' })
    $detail = if ($hit.Count -eq 0) { "" } else { "false positive on line $($hit[0].FirstUseLine)" }
    _Record -Name 'good: obj.NAME field-access does not trigger' -Pass ($hit.Count -eq 0) -Detail $detail

    # --- Network-bound mutation fixtures (Pattern A + B + escape hatches) ---
    Write-Host ""
    Write-Host "lint-mod: running self-test for network-bound-mutation"

    function _RunNB {
        param([string]$Source)
        $commentsOnly = Strip-LuaComments -Text $Source
        return Find-NetworkBoundMutation -File '(memory)' -RawText $Source -Text $commentsOnly
    }

    # Bad: direct field assignment, no clamp.
    $src = @"
local ext = something()
ext._max_overcharge = 80
"@
    $found = _RunNB -Source $src
    $hit = @($found | Where-Object { $_.Kind -eq 'netbound_assign' })
    $detail = if ($hit.Count -eq 1) { "field=$($hit[0].Field) line=$($hit[0].Line)" } else { "no finding ($($found.Count) total)" }
    _Record -Name 'bad: ext._max_overcharge = 80 (no clamp)' -Pass ($hit.Count -eq 1) -Detail $detail

    # Bad: widening via multiply (ext._max_ammo = ext._max_ammo * 2).
    $src = @"
local ext = something()
ext._max_ammo = ext._max_ammo * 2
"@
    $found = _RunNB -Source $src
    $hit = @($found | Where-Object { $_.Kind -eq 'netbound_assign' })
    _Record -Name 'bad: ext._max_ammo = ext._max_ammo * 2 (widening)' -Pass ($hit.Count -eq 1) -Detail $(if ($hit.Count -eq 1) { "field=$($hit[0].Field) line=$($hit[0].Line)" } else { "no finding" })

    # Good (FALSE-POSITIVE REGRESSION GUARD a): stat_buff = "max_*" data-table
    # string literal must NOT fire (Pattern B removed 2026-05-29). Mirrors crt's
    # two career_tweaker_balance/big_rebalance `stat_buff = "max_health"` entries.
    $src = @"
local t = {
    { stat_buff = "max_overcharge", multiplier = 0.05 },
    { stat_buff = "max_health",     bonus = 30 },
}
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: stat_buff = "max_*" data literal does NOT fire' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp $($found[0].Kind) on line $($found[0].Line)" })

    # Good (FALSE-POSITIVE REGRESSION GUARD b): guarded downward clamp — the
    # canonical chaos_wastes_tweaker.lua:7831 safe case. `if X > CAP then X = CAP end`.
    $src = @"
local self = something()
if type(self._max_ammo) == "number" and self._max_ammo > 9999 then
    self._max_ammo = 9999
end
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: guarded > CONST clamp (ct:7831) does NOT fire' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp $($found[0].Kind) on line $($found[0].Line)" })

    # Good: math.min clamp detected.
    $src = @"
local ext = something()
ext._max_overcharge = math.min(new_val, 60)
"@
    $found = _RunNB -Source $src
    $detail = if ($found.Count -eq 0) { "" } else { "false positive on line $($found[0].Line) ($($found[0].Kind))" }
    _Record -Name 'good: math.min clamp suppresses warning' -Pass ($found.Count -eq 0) -Detail $detail

    # Good: math.max(x, math.min(...)) nested clamp.
    $src = @"
local ext = something()
ext._max_energy = math.max(1, math.min(new_val, 60))
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: math.max + math.min nested clamp' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp on line $($found[0].Line)" })

    # Good: LINT_OK_NETBOUND annotation on same line.
    $src = @"
local ext = something()
ext._max_overcharge = X  -- LINT_OK_NETBOUND: vanilla path
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: LINT_OK_NETBOUND escape on same line' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp on line $($found[0].Line)" })

    # Good: LINT_OK_NETBOUND annotation 2 lines above.
    $src = @"
-- LINT_OK_NETBOUND: applied before vanilla cap check, see ct v0.7.42
do
    ext._max_overcharge = X
end
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: LINT_OK_NETBOUND escape 2 lines above' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp on line $($found[0].Line)" })

    # Good: total_ammo stat_buff (vanilla-supported, no network bound).
    $src = @'
local t = {
    { stat_buff = "total_ammo", multiplier = 0.5 },
}
'@
    $found = _RunNB -Source $src
    _Record -Name 'good: stat_buff = "total_ammo" (vanilla-supported)' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp $($found[0].Kind) on line $($found[0].Line)" })

    # Good: read access (local x = ext._max_overcharge) does NOT trigger.
    $src = @"
local ext = something()
local x = ext._max_overcharge
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: read access does not trigger' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp on line $($found[0].Line)" })

    # Good: equality comparison (ext._max_overcharge == 60) does NOT trigger.
    $src = @"
local ext = something()
if ext._max_overcharge == 60 then return end
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: == comparison does not trigger' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp on line $($found[0].Line)" })

    # Good: commented-out line does NOT trigger.
    $src = @"
-- ext._max_overcharge = 80
local y = 1
"@
    $found = _RunNB -Source $src
    _Record -Name 'good: commented-out line does not trigger' -Pass ($found.Count -eq 0) -Detail $(if ($found.Count -eq 0) { "" } else { "fp on line $($found[0].Line)" })

    # --- Summary ---
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

if ($SelfTest) {
    exit (Invoke-LateLocalSelfTest)
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
    # Issue #214 safety net (belt-and-suspenders on top of the named-only param):
    # never overwrite an EXISTING file that is not a .json report. A typo'd
    # -JsonPath target (e.g. a .lua source path) must fail loudly rather than
    # destroy the file. A path that does not exist yet, or already ends in .json,
    # is allowed (overwriting a prior .json report is intended).
    if ((Test-Path -LiteralPath $jsonOut -PathType Leaf) -and
        ([System.IO.Path]::GetExtension($jsonOut).ToLowerInvariant() -ne '.json')) {
        throw "Refusing to write the lint JSON report over existing non-.json file '$jsonOut'. Pass -JsonPath a path ending in .json, or omit it to use the default .release-stage/mod-lint.json."
    }
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
                    late_locals = @(
                        foreach ($ll in $r.LateLocals) {
                            $rel = $ll.File
                            if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                            [ordered]@{ file = $rel; name = $ll.Name; decl_line = $ll.DeclLine; first_use_line = $ll.FirstUseLine; in_closure = [bool]$ll.InClosure }
                        }
                    )
                    save_restore = @(
                        foreach ($sr in $r.SaveRestore) {
                            $rel = $sr.File
                            if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                            [ordered]@{ file = $rel; line = $sr.Line; kind = $sr.Kind; detail = $sr.Detail }
                        }
                    )
                    network_bound = @(
                        foreach ($nb in $r.NetBound) {
                            $rel = $nb.File
                            if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
                            [ordered]@{ file = $rel; line = $nb.Line; kind = $nb.Kind; field = $nb.Field; detail = $nb.Detail }
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
