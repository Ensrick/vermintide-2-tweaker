# check_logging.ps1 — static logging-hygiene scan for active-mod Lua files.
#
# Encodes PROJECT_STANDARDS.md § 3.6 (Debug logging + "Chat-echo policy" matrix)
# and docs/BUG_CLASSES.md § 17 (chat-echo spam + Variant B, Issue #240). Three
# advisory sub-checks (each with a false-positive-safe suppression path) plus
# two hard contracts (the retired debug key and the global printf):
#
#   (a) ECHO       — a `mod:echo(` call in one of the § 3.6 / BUG_CLASSES § 17
#       "NEVER" contexts, i.e. the sites those docs say to audit against the
#       chat-echo matrix: (1) module-load top-level (not inside any function) that
#       is NOT the dev/alpha/beta/0.x banner (`mod:echo(... MOD_VERSION ...)`);
#       (2) an `on_setting_changed` / `on_enabled` / `on_disabled` lifecycle body;
#       (3) a hook callback body (`mod:hook`/`mod:hook_safe` inline `function`).
#       Echoes inside ordinary functions and `mod:command`/keybind handler bodies
#       are NOT flagged — § 3.6 sanctions user-invoked replies, and a static tool
#       cannot trace a reply routed through a private helper without a call graph;
#       flagging them all buries the signal. This favors precision (some routine
#       echoes in ordinary helpers are missed — a safe false negative). Several
#       § 3.6 rows are legitimately OK inside these contexts (a high-impact
#       `on_setting_changed` toggle, an `on_disabled` documented-limitation
#       notice, ct's "Granted N boons" hook reply) — annotate those with an inline
#       `-- allow-echo: <reason>` (same line or line directly above).
#
#   (b) PER-FRAME  — a `mod:info(` / `mod:warning(` call inside a per-frame
#       callback (`function update`, `mod.update`, `X.update`/`X:update`, or an
#       inline `mod:hook*(..., "update", function...)`). These fire every frame;
#       gate behind a state-change guard or move out of the hot path. Suppress an
#       intentional throttled/one-shot site with `-- allow-perframe: <reason>`.
#
#   (c) WARN-CHAT  — a `mod:warning(` call inside a debug/alert HELPER
#       (`_dbg_alert`, `_spawn_dbg_alert`, a `dbg`/`alert`-named helper — NOT a
#       `chat`-named one). This is the Issue #240 class: `mod:warning` is BELIEVED
#       log-only but VMF `logging.lua` defaults `warning` to mode 3
#       (`send_to_chat = mode >= 2`), so a "log-only alert" helper spams chat. The
#       sanctioned form is pcall-guarded raw `printf` (et v0.7.25-dev, #240).
#       Genuine failure-path `mod:warning` (in ordinary guards, `_safe`, etc.) is
#       NOT flagged — chat visibility is arguably wanted there. Suppress an
#       intentional in-helper chat warning with `-- allow-warn-chat: <reason>`.
#
#   (d) RETIRED-DEBUG-KEY — executable `get`/`set` calls or a widget
#       `setting_id` for `enable_debug_logging`. Comments and historical prose
#       are allowed; production execution is a hard #169 regression. There is
#       NO inline escape comment for this category: the only tolerated site is
#       the exact General Tweaker STABLE promotion debt pinned in
#       $legacyRetiredDebugKeyDebt below.
#
#   (e) PRINTF-MUTATION — a runtime write to the global/environment `printf`
#       in any active mod tree (`_G.printf =`, `_G["printf"] =`,
#       `rawset(_G, "printf", ...)`, `mod:hook*(_G, "printf", ...)`, any
#       `setfenv(`, ambient `getfenv()`/`getfenv(0)`, `getfenv(...).printf =`).
#       Issue #1637: the deployed-source authority
#       (tools/verify/live_test_source_authority.ps1,
#       Test-VtLuaMutatesGlobalPrintf) rejects any DEPLOYED mod that mutates
#       global printf, record-wide and fail-closed, because raw printf evidence
#       for every mod becomes untrustworthy; gut_dev 0.2.353-dev shipped such a
#       swap inside an in-game regression proof and nothing offline caught it,
#       so every lifecycle guard, card refresh and ship label step failed
#       repo-wide until the next release. Hard error, NO inline escape and no
#       floor: the offline Lua harness under qa/lua (never deployed, outside
#       this scan scope) is the only place a printf swap may live.
#
# Existing hygiene debt is advisory by result: ordinary findings exit 1, which
# Standard policy reports without blocking. Three contracts are blocking:
# Issue #427's warn-chat floor (any warning-backed diagnostic helper outside the
# exact three public stable-stream promotion debts exits 2), Issue #169's
# retired-key floor (any executable retired-key site outside the exact one
# General Tweaker stable promotion debt exits 2) and Issue #1637's printf
# floor (any runtime write to global/environment printf exits 2).
#
# Detection scope mirrors check_unpack_safety.ps1: `*.lua` under each active mod's
# `scripts/` subtree; skips tweaker/ (legacy), _archive, *_extract, bundleV2,
# reference clones, fixtures. Comment- and string-blanking (block comments incl.
# --[=[ ]=], quoted spans) runs before keyword/call matching so keywords in prose
# or literals never count. Scope membership uses a per-line Lua block-depth
# counter (function/if/for/while/do vs end) with per-kind "floors" and a function-
# nesting counter (module-top = no function open); it is a heuristic, not a
# parser, but it is validated against the live repo (vdl's ~100 command echoes
# report clean).
#
# Exit codes:
#   0 - no findings
#   1 - one or more advisory findings (echo / per-frame / warn-chat)
#   2 - hard error, self-test failure, new #427 warn-chat regression, a #169
#       retired-key site outside the pinned General Tweaker stable debt, or any
#       #1637 runtime write to global/environment printf
#
# Self-test: `-SelfTest` runs the synthetic fixtures under qa/_test_fixtures/ and
# asserts per-category finding counts. Auto-discovered by qa/run_selftests.ps1.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest,
    [switch]$WarnChatRegression
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot ".." }
# Get-Item expands an 8.3 short-name root (and, under PowerShell 7, restores the
# on-disk casing) so enumerated file paths share the root prefix that the floor
# tables and relative-path reports strip. Prefix tests below are case-insensitive.
$repoRoot = (Get-Item -LiteralPath (Resolve-Path $RepoRoot).Path).FullName

# Issue #427 migration floor. These are the three public stable-stream helpers
# whose dev twins are already console-only; they may disappear through an
# authorized promotion, but no new warning-backed diagnostic helper may enter
# any stream. Keying on both relative path and source text means an additional
# helper in one of these files is not silently grandfathered.
$legacyWarnChatDebt = @{
    'chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua|mod:warning("[ct:dbg] " .. fmt, ...)' = $true
    'general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua|mod:warning("[gt:dbg] " .. fmt, ...)' = $true
    'verminious_dreams_lighting/scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting.lua|mod:warning("[vdl:dbg] " .. fmt, ...)' = $true
}

# Issue #169 retired-key floor. Exactly one executable site of the retired
# per-mod `enable_debug_logging` key is tolerated: General Tweaker STABLE's
# `_dbg_on` predicate in _gt_debug_probes.lua. Its dev twin already carries the
# VMF-native predicate (`logging_mode == "custom"` and `output_mode_debug > 0`).
# The stable swap is a runtime-source change, so it rides the next
# user-authorized General Tweaker stable promotion, never a tooling PR (stable
# directories are read-only outside promotion). Keyed on relative path AND
# exact source text, so a rewritten line or a second site in that file is not
# grandfathered. Each floor key tolerates ONE occurrence, so a duplicated copy
# of the pinned line is rejected too. Delete this entry when the promotion
# lands; removal is clean.
$legacyRetiredDebugKeyDebt = @{
    'general_tweaker/scripts/mods/general_tweaker/_gt_debug_probes.lua|return mod:get("enable_debug_logging") == true' = $true
}

# Issue #727 reviewed-intent floor. These are not ignored by a broad path or
# message pattern: each row binds one relative file, category, exact trimmed
# source line, and maximum occurrence count. Removal is clean; changed text,
# another file, or an occurrence above the reviewed count becomes advisory
# again. Runtime defects (CT's routine bot-boon echo and the three #427 stable
# warning helpers) are deliberately absent and remain visible below.
$approvedLoggingIntent = @{}
function Add-ApprovedLoggingIntent {
    param([string]$Path,[string]$Category,[string]$Text,[int]$Count,[string]$Reason)
    $key=$Path.ToLowerInvariant().Replace('\','/')+'|'+$Category+'|'+$Text
    if($approvedLoggingIntent.ContainsKey($key)){throw "Duplicate approved logging-intent key: $key"}
    if($Count -lt 1 -or [string]::IsNullOrWhiteSpace($Reason)){throw "Invalid approved logging-intent row: $key"}
    $approvedLoggingIntent[$key]=[pscustomobject]@{Count=$Count;Reason=$Reason}
}
Add-ApprovedLoggingIntent 'career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua' 'echo' 'mod:echo("[crt] Balance reworks reverted. Buff registrations and hooks need a game restart for a fully clean vanilla state.")' 1 'High-impact disable limitation; the player must restart for a clean vanilla state.'
Add-ApprovedLoggingIntent 'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua' 'echo' 'mod:echo("[cosmetics_tweaker] LA variant ''%s'' missing from your local LA install. Peer''s cosmetic won''t render. Enable Loremaster''s Armoury in launcher + restart, or update LA.",' 1 'Actionable compatibility failure shown once for the missing peer cosmetic asset.'
Add-ApprovedLoggingIntent 'cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua' 'echo' 'mod:echo("Cannot apply illusion — requires DLC you don''t own.")' 1 'Immediate response to a rejected player illusion action.'
Add-ApprovedLoggingIntent 'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua' 'echo' 'mod:echo("Crafted & saved: " .. tostring(Localize(_name)) .. " [" .. tostring(weapon_data.rarity) .. "]" .. _result_text)' 1 'Immediate confirmation of a player-requested craft.'
Add-ApprovedLoggingIntent 'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua' 'echo' 'mod:echo("[cim] No accessory edits to craft (Apply auto-runs on bubble click)")' 1 'Immediate explanation for a player-requested no-op craft.'
Add-ApprovedLoggingIntent 'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua' 'echo' 'mod:echo("[cim] Craft: no selected item")' 1 'Immediate explanation for a rejected player craft.'
Add-ApprovedLoggingIntent 'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua' 'echo' 'mod:echo("[cim] Crafted new " .. tostring(slot_name and slot_name:gsub("^slot_", "") or "item")' 1 'Immediate confirmation of a player-requested craft.'
Add-ApprovedLoggingIntent 'crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua' 'echo' 'mod:echo("Crafted & saved: " .. tostring(Localize(_name)) .. " [" .. tostring(weapon_data.rarity) .. "]" .. _result_text)' 1 'Immediate confirmation of a player-requested craft.'
Add-ApprovedLoggingIntent 'general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua' 'echo' 'mod:echo("AI toggle: " .. err)' 1 'Immediate failure response to a player AI-toggle request.'
Add-ApprovedLoggingIntent 'general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua' 'echo' 'mod:echo("AI " .. (want_bot and "ON" or "OFF") .. " (requested from host).")' 1 'Immediate success response to a player AI-toggle request.'
Add-ApprovedLoggingIntent 'general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua' 'echo' 'mod:echo("[gt] Disable does not fully unwind active mutations. Restart the game for a clean vanilla state.")' 1 'High-impact disable limitation; the player must restart for a clean vanilla state.'
foreach($stream in @('gui_tweaker','gui_tweaker_dev')){
    Add-ApprovedLoggingIntent "$stream/scripts/mods/$stream/_ba_compendium_tabs.lua" 'echo' 'mod:echo("Compendium not ready (inject module didn''t load).")' 1 'Immediate response to a player opening an unavailable compendium.'
    Add-ApprovedLoggingIntent "$stream/scripts/mods/$stream/_gut_mission_inventory.lua" 'echo' 'mod:echo("The customize gear icon is disabled mid-mission unless Tweaker: Cosmetics is loaded. (Crafting in Modded users: use the Crafting tab / bench for illusions and re-rolls.)")' 1 'Immediate guidance after a player invokes the disabled mission customization action.'
}
foreach($stream in @('weapon_tweaker','weapon_tweaker_dev')){
    Add-ApprovedLoggingIntent "$stream/scripts/mods/$stream/_wt_anim_remap.lua" 'echo' 'mod:echo("--- " .. tostring(s_key or s_tmpl) .. " ---")' 1 'Explicit animation-log mode emits a player-readable section header.'
    Add-ApprovedLoggingIntent "$stream/scripts/mods/$stream/_wt_anim_remap.lua" 'echo' 'mod:echo(msg)' 5 'Explicit animation-log mode emits the requested remap trace; occurrence count is bounded.'
    Add-ApprovedLoggingIntent "$stream/scripts/mods/$stream/weapon_tweaker_backend.lua" 'perframe' 'mod:info("[wt:368] deferred final availability + career-action reconciliation applied")' 1 'Per-frame owner clears its one-shot sentinel before this message.'
    Add-ApprovedLoggingIntent "$stream/scripts/mods/$stream/weapon_tweaker_backend.lua" 'perframe' 'mod:info("[wt:593/597] CWV ownership transition active=%s axe_shield_ready=%s greataxe_ready=%s; native fallbacks reconciled",' 1 'Per-frame owner emits only after a three-axis ownership transition.'
}

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# ---- pre-compiled regexes ----
$rxEcho      = [regex]'\bmod:echo\s*\('
$rxInfo      = [regex]'\bmod:info\s*\('
$rxWarning   = [regex]'\bmod:warning\s*\('
$rxModVer    = [regex]'\bMOD_VERSION\b'
$rxHookAny   = [regex]'\bmod:hook\w*\s*\('
$rxHookUpd   = [regex]'\bmod:hook\w*\s*\([^)]*["'']update["'']'
# A mod:warning whose message literal opens with a debug tag ("[cosmetics:dbg] ...",
# "[dbg] ..."). #427: helper-shaped detection alone missed direct prefix-tagged
# warnings in sibling modules (cosmetics_tweaker\_la_okri.lua carried two for five
# audit passes). The author's own :dbg tag is the intent signal -- it is a
# diagnostic, so it must not reach chat, whatever scope it sits in.
$rxWarnDbgTag = [regex]'\bmod:warning\s*\(\s*["'']\s*\[[A-Za-z_][\w\-]*:dbg\]|\bmod:warning\s*\(\s*["'']\s*\[dbg\]'
# Colon calls pass the key first; Lua's equivalent dot call passes an explicit
# self first. Cover direct identifier/member-path receivers without attempting
# general Lua expression evaluation or constant folding of computed keys. Lua
# also permits a lone string argument without parentheses. The @-delimited
# marker cannot occur in valid executable Lua; prose containing it is blanked.
$rxRetiredDebugCall = [regex]'(?ms)(?:[:\.]\s*[gs]et\s*(?:\(\s*)?|\.\s*[gs]et\s*\(\s*[A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*\s*,\s*)@VT_RETIRED_DEBUG_KEY@'
# A widget names the key with a bare field (`setting_id = ...`) or the equivalent
# bracketed string field (`["setting_id"] = ...`).
$rxRetiredDebugWidget = [regex]'(?ms)(?:\bsetting_id|\[\s*@VT_SETTING_ID_KEY@\s*\])\s*=\s*@VT_RETIRED_DEBUG_KEY@'
# Lexical spans for this hard category only; keep the advisory scope scanner
# unchanged. Long brackets and escaped quotes must not turn historical prose
# into executable code (or hide a real call later on the same line).
$rxRetiredLuaSpans = [regex]'(?s)--\[(=*)\[.*?\]\1\]|--[^\r\n]*|\[(=*)\[.*?\]\2\]|"(?:\\.|[^"\\])*"|''(?:\\.|[^''\\])*'''

function Get-RetiredDebugKeyCode {
    param([string]$Source)
    return $rxRetiredLuaSpans.Replace($Source, [System.Text.RegularExpressions.MatchEvaluator]{
        param($Match)
        $value = $Match.Value
        # Lua skips one line break directly after a long-bracket opener
        # (llex.c read_long_string), so `[[<newline>key]]` is the same literal.
        # A sentinel keeps the span's line breaks so reported lines stay exact.
        $breaks = [regex]::Replace($value, '[^\r\n]', '')
        if ($value -ceq '"enable_debug_logging"' -or $value -ceq "'enable_debug_logging'" -or
            $value -cmatch '\A\[(=*)\[(?:\r\n|\n\r|\n|\r)?enable_debug_logging\]\1\]\z') {
            return '@VT_RETIRED_DEBUG_KEY@' + $breaks
        }
        if ($value -ceq '"setting_id"' -or $value -ceq "'setting_id'" -or
            $value -cmatch '\A\[(=*)\[(?:\r\n|\n\r|\n|\r)?setting_id\]\1\]\z') {
            return '@VT_SETTING_ID_KEY@' + $breaks
        }
        return [regex]::Replace($value, '[^\r\n]', ' ')
    })
}

# Issue #1637: a runtime write to the global/environment printf. Detected on the
# same comment/string-normalized source as the retired key, with the "printf"
# literal kept as a sentinel so `rawset(_G, "printf", ...)` and `_G["printf"] =`
# survive string blanking. The shapes mirror the deployed-source authority's
# Test-VtLuaMutatesGlobalPrintf plus the VMF hook spelling: `_G.printf =` /
# `_ENV.printf =` / `_G["printf"] =`, `rawset(_G|_ENV|getfenv(...), "printf", ...)`,
# `mod:hook*(_G|_ENV, "printf", ...)`, any `setfenv(` / `debug.setfenv(` /
# `pcall(setfenv, ...)`, ambient `getfenv()` / `getfenv(0)`, and
# `getfenv(...).printf =` / `getfenv(...)["printf"] =`. Reads (`rawget`),
# `pcall(printf, ...)` calls, comparisons, table fields (`{ printf = printf }`)
# and `getfenv(<function>)` stay legal, exactly as the authority treats them.
$rxPrintfBail = [regex]'printf|setfenv|getfenv'
$rxPrintfMutation = [regex]('(?ms)(?:' +
    '\b(?:_G|_ENV)\s*\.\s*printf\s*=(?!=)' + '|' +
    '\b(?:_G|_ENV)\s*\[\s*@VT_PRINTF_KEY@\s*\]\s*=(?!=)' + '|' +
    '\brawset\s*\(\s*(?:_G|_ENV|getfenv\s*\([^()]*\))\s*,\s*@VT_PRINTF_KEY@\s*,' + '|' +
    '\bmod\s*:\s*hook\w*\s*\(\s*(?:_G|_ENV)\s*,\s*@VT_PRINTF_KEY@' + '|' +
    '\b(?:debug\s*\.\s*)?setfenv\s*\(' + '|' +
    '\bpcall\s*\(\s*setfenv\s*,' + '|' +
    '\bgetfenv\s*\(\s*(?:0\s*)?\)' + '|' +
    '\bgetfenv\s*\([^()]*\)\s*(?:\.\s*printf|\[\s*@VT_PRINTF_KEY@\s*\])\s*=(?!=)' +
    ')')

function Get-PrintfMutationCode {
    param([string]$Source)
    return $rxRetiredLuaSpans.Replace($Source, [System.Text.RegularExpressions.MatchEvaluator]{
        param($Match)
        $value = $Match.Value
        $breaks = [regex]::Replace($value, '[^\r\n]', '')
        if ($value -ceq '"printf"' -or $value -ceq "'printf'" -or
            $value -cmatch '\A\[(=*)\[(?:\r\n|\n\r|\n|\r)?printf\]\1\]\z') {
            return '@VT_PRINTF_KEY@' + $breaks
        }
        return [regex]::Replace($value, '[^\r\n]', ' ')
    })
}

# escape comments (accepted on the flagged line OR the line directly above)
$rxAllowEcho = [regex]'--\s*allow-echo\s*:'
$rxAllowFrame= [regex]'--\s*allow-perframe\s*:'
$rxAllowWarn = [regex]'--\s*allow-warn-chat\s*:'

# function-definition name extraction (first match wins)
$rxDefLocal  = [regex]'\blocal\s+function\s+([A-Za-z_][\w]*)'
$rxDefNamed  = [regex]'\bfunction\s+([A-Za-z_][\w\.:]*)\s*\('
$rxDefAssign = [regex]'([A-Za-z_][\w\.:]*)\s*=\s*function\b'

# scope classifiers (applied to an extracted function name)
$rxLifecycle  = [regex]'(?i)(^|[\.:])(on_setting_changed|on_enabled|on_disabled)$'
$rxUpdateName = [regex]'(?i)(^|[\.:])update$'
$rxAlertName  = [regex]'(?i)(dbg|alert|log_only|warn_log|diag)'
$rxChatName   = [regex]'(?i)chat'

# block-depth token counters (run on comment/string-stripped code)
$rxTokFunction = [regex]'\bfunction\b'
$rxTokIf       = [regex]'\bif\b'
$rxTokFor      = [regex]'\bfor\b'
$rxTokWhile    = [regex]'\bwhile\b'
$rxTokDo       = [regex]'\bdo\b'
$rxTokEnd      = [regex]'\bend\b'

# ---- file collection (mirrors check_unpack_safety.ps1) ----
function Get-ScanFiles {
    param([string]$Root)
    Get-ChildItem -Path $Root -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $isActive = $p -match "\\scripts\\"
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
                       -and $p -notlike "*\_*_extract\*" `
                       -and $p -notlike "*\.claude\*"
            return $isActive -and $notExcluded
        }
}

# Strip a line's comment tail + string interiors, tracking multi-line block
# comments. Returns @{ Code = <code-only text>; InBlock; BlockCloser }. Same
# state machine as check_unpack_safety.ps1's Scan-File loop.
function Get-CodePart {
    param([string]$Line, [bool]$InBlock, [string]$BlockCloser)
    $work = $Line
    if ($InBlock) {
        $ci = $work.IndexOf($BlockCloser)
        if ($ci -lt 0) { return @{ Code = ""; InBlock = $true; BlockCloser = $BlockCloser } }
        $work = $work.Substring($ci + $BlockCloser.Length)
        $InBlock = $false
        $BlockCloser = ""
    }
    # Blank string-literal interiors FIRST, before splitting on `--`. A string may
    # itself contain `--` (e.g. "...intercept while popup already up -- skipping..."):
    # splitting on that `--` first would truncate the string mid-literal, leaving an
    # unterminated (un-blanked) span whose keywords (`while`, `if`, `end`, …) leak
    # into the block-depth counter and desync every scope below it.
    $work = [regex]::Replace($work, '"[^"]*"', '""')
    $work = [regex]::Replace($work, "'[^']*'", "''")

    $codePart = $work
    $cIdx = $work.IndexOf('--')
    if ($cIdx -ge 0) {
        $codePart = $work.Substring(0, $cIdx)
        $rest = $work.Substring($cIdx + 2)
        $open = [regex]::Match($rest, '^(=*)\[')
        if ($open.Success) {
            $closer = "]" + $open.Groups[1].Value + "]"
            $afterOpen = $rest.Substring($open.Length)
            if ($afterOpen.IndexOf($closer) -lt 0) {
                $InBlock = $true
                $BlockCloser = $closer
            }
        }
    }
    return @{ Code = $codePart; InBlock = $InBlock; BlockCloser = $BlockCloser }
}

function Get-FuncName {
    param([string]$Code)
    $m = $rxDefLocal.Match($Code);  if ($m.Success) { return $m.Groups[1].Value }
    $m = $rxDefNamed.Match($Code);  if ($m.Success) { return $m.Groups[1].Value }
    $m = $rxDefAssign.Match($Code); if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Does this stripped line open a function scope? (any of the three def forms, or
# an inline callback such as `mod:command(...)`/`mod:hook(...)` with `function`)
function Test-OpensFunction {
    param([string]$Code)
    return $rxTokFunction.IsMatch($Code)
}

function Get-Delta {
    param([string]$Code)
    $open = $rxTokFunction.Matches($Code).Count `
          + $rxTokIf.Matches($Code).Count `
          + $rxTokFor.Matches($Code).Count `
          + $rxTokWhile.Matches($Code).Count
    # bare `do` block opener — but the `do` on a for/while line is that loop's
    # `do` (already counted via for/while), so only count `do` when the line has
    # neither for nor while.
    if (-not ($rxTokFor.IsMatch($Code) -or $rxTokWhile.IsMatch($Code))) {
        $open += $rxTokDo.Matches($Code).Count
    }
    $close = $rxTokEnd.Matches($Code).Count
    return ($open - $close)
}

# ---- per-file scan ----
# Returns an array of finding rows: @{ File; Line; Category; Text }.
function Scan-LoggingFile {
    param([string]$Path)
    $findings = @()
    try {
        $text = Read-FileUtf8 $Path
    } catch {
        throw "I/O failure reading ${Path}: $_"
    }
    # (e) Issue #1637 printf-mutation runs first, on its own predicate: it is
    #     independent of the echo/per-frame census and must never be skipped by
    #     the fast bail below. A write may span lines, so the whole
    #     comment/string-normalized source is scanned, like the retired key.
    if ($rxPrintfBail.IsMatch($text)) {
        $printfCode = Get-PrintfMutationCode -Source $text
        $printfLines = $null
        foreach ($match in @($rxPrintfMutation.Matches($printfCode))) {
            if ($null -eq $printfLines) { $printfLines = $text -split "`r?`n" }
            $line = 1 + [regex]::Matches($printfCode.Substring(0, $match.Index), "`n").Count
            $textAtLine = if ($line -le $printfLines.Count) { $printfLines[$line - 1].Trim() } else { '' }
            $findings += [pscustomobject]@{ File = $Path; Line = $line; Category = 'printf-mutation'; Text = $textAtLine }
        }
    }
    # fast bail — nothing else to scan
    if (-not ($rxEcho.IsMatch($text) -or $rxInfo.IsMatch($text) -or $rxWarning.IsMatch($text) `
            -or $text.Contains('enable_debug_logging'))) {
        return ,$findings
    }

    $lines = $text -split "`r?`n"
    $depth = 0
    $neverFloor  = $null      # innermost § 3.6 "NEVER" echo scope (lifecycle / hook body)
    $updateFloor = $null      # innermost per-frame (update) scope
    $alertFloor  = $null      # innermost dbg/alert helper scope
    $inBlock = $false
    $blockCloser = ""

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $raw = $lines[$i]
        $prev = if ($i -gt 0) { $lines[$i - 1] } else { "" }

        $strip = Get-CodePart -Line $raw -InBlock $inBlock -BlockCloser $blockCloser
        $code = $strip.Code
        $inBlock = $strip.InBlock
        $blockCloser = $strip.BlockCloser
        if ([string]::IsNullOrEmpty($code)) { continue }

        $depthBefore = $depth

        # ---- scope-open detection (set floors at depthBefore, shallowest wins) ----
        $funcName   = Get-FuncName -Code $code
        $opensFunc  = Test-OpensFunction -Code $code
        # NEVER echo scope: an on_setting_changed/on_enabled/on_disabled body, or
        # a hook callback body (inline `mod:hook*(...) function`).
        $isLifecycle = $funcName -and $rxLifecycle.IsMatch($funcName)
        $isHookBody  = $opensFunc -and $rxHookAny.IsMatch($code)
        $isUpdate    = ($funcName -and $rxUpdateName.IsMatch($funcName)) -or $rxHookUpd.IsMatch($code)
        $isAlert     = $funcName -and $rxAlertName.IsMatch($funcName) -and -not $rxChatName.IsMatch($funcName)

        if (($isLifecycle -or $isHookBody) -and $null -eq $neverFloor) { $neverFloor = $depthBefore }
        if ($isUpdate -and $null -eq $updateFloor) { $updateFloor = $depthBefore }
        if ($isAlert  -and $null -eq $alertFloor)  { $alertFloor  = $depthBefore }

        # ---- violation detection (uses floor state AFTER opens, BEFORE close) ----
        # (a) echo in a NEVER context: module-load top-level (depth 0, not the
        #     MOD_VERSION dev banner), or inside a lifecycle / hook-body scope.
        if ($rxEcho.IsMatch($code)) {
            $inNever = ($null -ne $neverFloor) -or ($depthBefore -eq 0)
            $suppressed = (-not $inNever) `
                -or $rxModVer.IsMatch($code) `
                -or $rxAllowEcho.IsMatch($raw) -or $rxAllowEcho.IsMatch($prev)
            if (-not $suppressed) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'echo'; Text = $raw.Trim() }
            }
        }
        # (b) per-frame info/warning
        if ($null -ne $updateFloor -and ($rxInfo.IsMatch($code) -or $rxWarning.IsMatch($code))) {
            if (-not ($rxAllowFrame.IsMatch($raw) -or $rxAllowFrame.IsMatch($prev))) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'perframe'; Text = $raw.Trim() }
            }
        }
        # (c) warning inside a dbg/alert helper (Issue #240 class). Skip if the
        #     same line was already flagged per-frame to avoid double-reporting.
        if ($null -ne $alertFloor -and $rxWarning.IsMatch($code) -and $null -eq $updateFloor) {
            if (-not ($rxAllowWarn.IsMatch($raw) -or $rxAllowWarn.IsMatch($prev))) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'warn-chat'; Text = $raw.Trim() }
            }
        }
        # (d) self-tagged debug warning ("[<mod>:dbg] ...") ANYWHERE, not just inside a
        #     helper -- the (c) rule only sees helper-shaped sites. Skip when (b) or (c)
        #     already flagged this line so a site is never counted twice.
        # `$code` has string interiors blanked (see Get-CodePart), so the tag is only
        # visible in `$raw`; require the CALL in $code so a commented-out line is inert.
        if ($rxWarning.IsMatch($code) -and $rxWarnDbgTag.IsMatch($raw) -and ($null -eq $alertFloor) -and ($null -eq $updateFloor)) {
            if (-not ($rxAllowWarn.IsMatch($raw) -or $rxAllowWarn.IsMatch($prev))) {
                $findings += [pscustomobject]@{ File = $Path; Line = $i + 1; Category = 'warn-chat'; Text = $raw.Trim() }
            }
        }
        # ---- apply block-depth delta, then close any scope that has ended ----
        $depth += (Get-Delta -Code $code)
        if ($depth -lt 0) { $depth = 0 }   # never underflow on a stray/miscounted end
        if ($null -ne $neverFloor  -and $depth -le $neverFloor)  { $neverFloor  = $null }
        if ($null -ne $updateFloor -and $depth -le $updateFloor) { $updateFloor = $null }
        if ($null -ne $alertFloor  -and $depth -le $alertFloor)  { $alertFloor  = $null }
    }

    # Executable resurrection of the retired per-mod key may place the call,
    # literal, and closing delimiter on separate lines. Scan the complete
    # comment/string-normalized source so formatting cannot evade the guard.
    $retiredCode = Get-RetiredDebugKeyCode -Source $text
    foreach ($match in @($rxRetiredDebugCall.Matches($retiredCode)) + @($rxRetiredDebugWidget.Matches($retiredCode))) {
        $line = 1 + [regex]::Matches($retiredCode.Substring(0, $match.Index), "`n").Count
        $textAtLine = if ($line -le $lines.Count) { $lines[$line - 1].Trim() } else { '' }
        $findings += [pscustomobject]@{ File = $Path; Line = $line; Category = 'retired-debug-key'; Text = $textAtLine }
    }
    return ,$findings
}

# Derive a mod short-name from a scan path: the directory segment before \scripts\.
function Get-ModName {
    param([string]$Path, [string]$Root)
    $rel = $Path
    if ($rel.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($Root.Length).TrimStart('\','/') }
    $rel = $rel.Replace('\','/')
    $idx = $rel.IndexOf('/scripts/')
    if ($idx -gt 0) { return $rel.Substring(0, $idx) }
    return ($rel -split '/')[0]
}

# Rows of one category whose `<relative path>|<exact trimmed source text>` key is
# absent from the given monotonic floor table. Paths compare case-insensitively
# (forward slashes); text is exact, so a rewritten line loses its grandfathering.
# The root prefix is stripped case-insensitively too: Windows may enumerate a
# directory with different casing than the caller's -RepoRoot/$PSScriptRoot,
# and a case-sensitive prefix test would turn pinned debt into a false exit 2.
function Get-RowsOutsideFloor {
    param([object[]]$Rows, [string]$Root, [string]$Category, [hashtable]$Floor)
    $unexpected = @()
    $tolerated = @{}
    foreach ($row in @($Rows | Where-Object { $_.Category -eq $Category })) {
        $rel = $row.File
        if ($rel.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($Root.Length).TrimStart('\','/') }
        $rel = $rel.Replace('\','/').ToLowerInvariant()
        $key = $rel + '|' + $row.Text.Trim()
        # One tolerated occurrence per floor key: a duplicate of a pinned line
        # is new debt, not the grandfathered site.
        if ($Floor.ContainsKey($key) -and -not $tolerated.ContainsKey($key)) {
            $tolerated[$key] = $true
        } else {
            $unexpected += $row
        }
    }
    return $unexpected
}

function Get-UnexpectedWarnChatRows {
    param([object[]]$Rows, [string]$Root)
    return Get-RowsOutsideFloor -Rows $Rows -Root $Root -Category 'warn-chat' -Floor $legacyWarnChatDebt
}

function Get-UnexpectedRetiredDebugKeyRows {
    param([object[]]$Rows, [string]$Root)
    return Get-RowsOutsideFloor -Rows $Rows -Root $Root -Category 'retired-debug-key' -Floor $legacyRetiredDebugKeyDebt
}

function Get-UnapprovedLoggingIntentRows {
    param([object[]]$Rows,[string]$Root)
    $seen=@{};$unapproved=@()
    foreach($row in @($Rows)){
        if($row.Category -notin @('echo','perframe')){$unapproved+=$row;continue}
        $rel=$row.File
        if($rel.StartsWith($Root,[StringComparison]::OrdinalIgnoreCase)){$rel=$rel.Substring($Root.Length).TrimStart('\','/')}
        $key=$rel.ToLowerInvariant().Replace('\','/')+'|'+$row.Category+'|'+$row.Text.Trim()
        $count=if($seen.ContainsKey($key)){$seen[$key]+1}else{1};$seen[$key]=$count
        if(-not$approvedLoggingIntent.ContainsKey($key) -or $count -gt $approvedLoggingIntent[$key].Count){$unapproved+=$row}
    }
    return $unapproved
}

# ---- self-test ----
function Invoke-SelfTest {
    $fixDir = Join-Path $PSScriptRoot "_test_fixtures"
    if (-not (Test-Path $fixDir)) {
        Write-Host "[check_logging -SelfTest] FAIL: $fixDir does not exist." -ForegroundColor Red
        return 2
    }
    # Expected finding counts per category per fixture.
    $cases = @(
        @{ Path = "logging_echo_bad.lua";     Echo = 2; Frame = 0; Warn = 0; Retired = 0; Printf = 0; Desc = "hook-body + on_setting_changed echo flagged; command / dev-banner / annotated echo suppressed" },
        @{ Path = "logging_perframe_bad.lua"; Echo = 0; Frame = 2; Warn = 0; Retired = 0; Printf = 0; Desc = "mod:info + mod:warning in update() flagged; annotated one suppressed" },
        @{ Path = "logging_warn_helper_bad.lua"; Echo = 0; Frame = 0; Warn = 1; Retired = 0; Printf = 0; Desc = "mod:warning in _dbg_alert flagged; genuine-guard warning + annotated one suppressed" },
        @{ Path = "logging_warn_dbgtag_bad.lua"; Echo = 0; Frame = 0; Warn = 1; Retired = 0; Printf = 0; Desc = "self-tagged [x:dbg] mod:warning outside any helper flagged; annotated one + untagged player-facing warning suppressed" },
        @{ Path = "logging_string_dash.lua";  Echo = 1; Frame = 0; Warn = 0; Retired = 0; Printf = 0; Desc = "`--`-in-string with a `while` keyword must not desync scope; command echoes stay clean" },
        @{ Path = "logging_retired_debug_key.lua"; Echo = 0; Frame = 0; Warn = 0; Retired = 17; Printf = 0; Desc = "direct literal reads/writes/widgets, including no-parentheses, explicit-self dot, leading-break long-literal and bracketed-field shapes, fail; comments, quoted prose and safe identifiers remain legal" },
        @{ Path = "logging_printf_mutation_bad.lua"; Echo = 0; Frame = 0; Warn = 0; Retired = 0; Printf = 17; Desc = "direct/bracketed global assignment, rawset (single-line, multi-line, through getfenv), VMF hook on _G, setfenv/debug.setfenv/pcall(setfenv), ambient getfenv()/getfenv(0) and getfenv(n) field writes fail; prose, comments, rawget reads, pcall(printf) calls, comparisons, table fields and getfenv(<function>) remain legal" },
        @{ Path = "logging_clean.lua";        Echo = 0; Frame = 0; Warn = 0; Retired = 0; Printf = 0; Desc = "all sanctioned forms — zero findings" }
    )
    $allPass = $true
    foreach ($c in $cases) {
        $f = Join-Path $fixDir $c.Path
        if (-not (Test-Path $f)) {
            Write-Host "  X $($c.Path): missing fixture file" -ForegroundColor Red
            $allPass = $false
            continue
        }
        $rows = Scan-LoggingFile -Path $f
        $ge = @($rows | Where-Object { $_.Category -eq 'echo' }).Count
        $gf = @($rows | Where-Object { $_.Category -eq 'perframe' }).Count
        $gw = @($rows | Where-Object { $_.Category -eq 'warn-chat' }).Count
        $gr = @($rows | Where-Object { $_.Category -eq 'retired-debug-key' }).Count
        $gp = @($rows | Where-Object { $_.Category -eq 'printf-mutation' }).Count
        $ok = ($ge -eq $c.Echo) -and ($gf -eq $c.Frame) -and ($gw -eq $c.Warn) -and ($gr -eq $c.Retired) -and ($gp -eq $c.Printf)
        $verdict = if ($ok) { "PASS" } else { "FAIL" }
        $colour  = if ($ok) { "Green" } else { "Red" }
        Write-Host ("  [{0}] {1} -- echo={2}/{3} frame={4}/{5} warn={6}/{7} retired={8}/{9} printf={10}/{11}" -f `
            $verdict, $c.Path, $ge, $c.Echo, $gf, $c.Frame, $gw, $c.Warn, $gr, $c.Retired, $gp, $c.Printf) -ForegroundColor $colour
        if (-not $ok) { Write-Host "        $($c.Desc)" -ForegroundColor DarkYellow; $allPass = $false }
    }

    # #1637 shapes asserted independently, so a false positive cannot cancel a
    # missed write and make the aggregate fixture count look correct.
    $printfScan = Scan-LoggingFile -Path (Join-Path $fixDir 'logging_printf_mutation_bad.lua')
    $printfRows = @($printfScan | Where-Object { $_.Category -eq 'printf-mutation' })
    foreach ($case in @(
        @{ Name = 'direct _G.printf assignment'; Ok = (@($printfRows | Where-Object { $_.Text -ceq '_G.printf = function() end' }).Count -eq 1) },
        @{ Name = 'bracketed long-literal printf key'; Ok = (@($printfRows | Where-Object { $_.Text -ceq '_G[ [[printf]] ] = real_printf' }).Count -eq 1) },
        @{ Name = 'multi-line rawset reports its first line'; Ok = (@($printfRows | Where-Object { $_.Text -ceq 'rawset(' }).Count -eq 1) },
        @{ Name = 'rawset through getfenv'; Ok = (@($printfRows | Where-Object { $_.Text -ceq 'rawset(getfenv(1), "printf", real_printf)' }).Count -eq 1) },
        @{ Name = 'VMF hook on the global table'; Ok = (@($printfRows | Where-Object { $_.Text -ceq 'mod:hook(_G, "printf", function(func, ...) end)' }).Count -eq 1) },
        @{ Name = 'pcall(setfenv, ...) spelling'; Ok = (@($printfRows | Where-Object { $_.Text -ceq 'pcall(setfenv, chunk, env)' }).Count -eq 1) },
        @{ Name = 'ambient getfenv() and getfenv(0)'; Ok = (@($printfRows | Where-Object { $_.Text -ceq 'local ambient = getfenv()' -or $_.Text -ceq 'local main_thread = getfenv(0)' }).Count -eq 2) },
        @{ Name = 'getfenv(<function>) read stays legal'; Ok = (@($printfRows | Where-Object { $_.Text -like '*getfenv(some_function)*' }).Count -eq 0) },
        @{ Name = 'rawget read and pcall(printf) call stay legal'; Ok = (@($printfRows | Where-Object { $_.Text -like '*rawget(_G, "printf")*' -or $_.Text -like 'pcall(printf,*' }).Count -eq 0) },
        @{ Name = 'table field printf = printf stays legal'; Ok = (@($printfRows | Where-Object { $_.Text -like '*{ printf = printf }*' }).Count -eq 0) },
        @{ Name = 'comparison _G.printf == nil stays legal'; Ok = (@($printfRows | Where-Object { $_.Text -like 'if _G.printf*' }).Count -eq 0) }
    )) {
        Write-Host ("  [{0}] #1637 {1}" -f $(if ($case.Ok) { 'PASS' } else { 'FAIL' }), $case.Name)
        if (-not $case.Ok) { $allPass = $false }
    }

    # The one place a printf swap may live is the offline Lua harness under
    # qa/lua, which is outside the active-mod scan scope. Prove BOTH halves: a
    # scope regression must not start failing the harness, and a detector
    # regression must not stop seeing the exact shape gut_dev 0.2.353-dev
    # shipped (the harness keeps that shape on purpose). The deployed recovery
    # module itself must scan clean; its absence is a failure, not a skip.
    $harnessPath = Join-Path $repoRoot 'qa\lua\tests\test_gut_spawn_weapon_recovery.lua'
    $recoveryPath = Join-Path $repoRoot 'gui_tweaker_dev\scripts\mods\gui_tweaker_dev\_gut_spawn_weapon_recovery.lua'
    $harnessOutOfScope = @(Get-ScanFiles -Root $repoRoot | Where-Object { $_.FullName -like '*\qa\lua\*' }).Count -eq 0
    $harnessShapeSeen = $false
    if (Test-Path $harnessPath) {
        $harnessScan = Scan-LoggingFile -Path $harnessPath
        $harnessShapeSeen = @($harnessScan | Where-Object { $_.Category -eq 'printf-mutation' -and $_.Text -like 'rawset(_G, "printf", *' }).Count -ge 1
    }
    $recoveryClean = $false
    if (Test-Path $recoveryPath) {
        $recoveryScan = Scan-LoggingFile -Path $recoveryPath
        $recoveryClean = @($recoveryScan | Where-Object { $_.Category -eq 'printf-mutation' }).Count -eq 0
    }
    $printfScopeOk = $harnessOutOfScope -and $harnessShapeSeen -and $recoveryClean
    Write-Host ("  [{0}] #1637 scope -- qa/lua harness outside scan scope={1}; its printf swap detected when scanned directly={2}; deployed gut_dev recovery module clean={3}" -f $(if ($printfScopeOk) { 'PASS' } else { 'FAIL' }), $harnessOutOfScope, $harnessShapeSeen, $recoveryClean) -ForegroundColor $(if ($printfScopeOk) { 'Green' } else { 'Red' })
    if (-not $printfScopeOk) { $allPass = $false }

    # The #427 floor is monotonic: the exact three stable-stream debts are
    # tolerated until promotion, their removal is clean, and either a new path
    # or a second warning helper in a grandfathered file is blocking.
    $knownPath = Join-Path $repoRoot 'general_tweaker\scripts\mods\general_tweaker\general_tweaker.lua'
    $known = [pscustomobject]@{ File = $knownPath; Line = 49; Category = 'warn-chat'; Text = 'mod:warning("[gt:dbg] " .. fmt, ...)' }
    $newText = [pscustomobject]@{ File = $knownPath; Line = 50; Category = 'warn-chat'; Text = 'mod:warning("[gt:new-diagnostic] " .. fmt, ...)' }
    $newPath = [pscustomobject]@{ File = (Join-Path $repoRoot 'event_tweaker\scripts\mods\event_tweaker\event_tweaker.lua'); Line = 20; Category = 'warn-chat'; Text = 'mod:warning("[event:dbg] " .. fmt, ...)' }
    $floorOk = (@(Get-UnexpectedWarnChatRows -Rows @($known) -Root $repoRoot).Count -eq 0) `
        -and (@(Get-UnexpectedWarnChatRows -Rows @() -Root $repoRoot).Count -eq 0) `
        -and (@(Get-UnexpectedWarnChatRows -Rows @($known, $newText, $newPath) -Root $repoRoot).Count -eq 2)
    Write-Host ("  [{0}] warn-chat migration floor -- exact legacy accepted; removal accepted; new sites rejected" -f $(if ($floorOk) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($floorOk) { 'Green' } else { 'Red' })
    if (-not $floorOk) { $allPass = $false }

    # Assert the new shapes independently: a false positive must not cancel a
    # missed literal call and make the aggregate fixture count look correct.
    # Scan-LoggingFile returns its row array wrapped (`return ,$findings`), so
    # assign it before piping; piping the call directly would hand Where-Object
    # the whole array as ONE object and turn exact counts into presence tests.
    $literalScan = Scan-LoggingFile -Path (Join-Path $fixDir 'logging_retired_debug_key.lua')
    $literalRows = @($literalScan | Where-Object { $_.Category -eq 'retired-debug-key' })
    $shortLiteralOk = @($literalRows | Where-Object { $_.Text -ceq 'mod:get "enable_debug_logging"' }).Count -eq 1
    $longLiteralOk = @($literalRows | Where-Object { $_.Text -ceq 'mod:get [=[enable_debug_logging]=]' }).Count -eq 1
    $safeIdentifierOk = @($literalRows | Where-Object { $_.Text -ceq 'return mod:get(__VT_RETIRED_DEBUG_KEY__)' }).Count -eq 0
    $leadingBreakOk = @($literalRows | Where-Object { $_.Text -ceq 'mod:get([[' }).Count -eq 1
    $bracketWidgetOk = @($literalRows | Where-Object { $_.Text -ceq '["setting_id"] = "enable_debug_logging",' }).Count -eq 1
    $lineAfterBreakOk = @($literalRows | Where-Object { $_.Text -ceq 'mod:set([==[' }).Count -eq 1
    foreach ($case in @(
        @{ Name = 'short literal call without parentheses'; Ok = $shortLiteralOk },
        @{ Name = 'long literal call without parentheses'; Ok = $longLiteralOk },
        @{ Name = 'legal marker-shaped identifier is not a retired key'; Ok = $safeIdentifierOk },
        @{ Name = 'long literal with a skipped leading line break'; Ok = $leadingBreakOk },
        @{ Name = 'bracketed string setting_id widget field'; Ok = $bracketWidgetOk },
        @{ Name = 'line numbers stay exact after a multi-line literal'; Ok = $lineAfterBreakOk }
    )) {
        Write-Host ("  [{0}] {1}" -f $(if ($case.Ok) { 'PASS' } else { 'FAIL' }), $case.Name)
        if (-not $case.Ok) { $allPass = $false }
    }

    # The #169 floor is monotonic the same way: the exact General Tweaker STABLE
    # `_dbg_on` read is tolerated until its authorized promotion, its removal is
    # clean, and a rewritten line or any other path (the dev twin included) is
    # blocking.
    $gtProbesPath = Join-Path $repoRoot 'general_tweaker\scripts\mods\general_tweaker\_gt_debug_probes.lua'
    $pinnedRetiredText = 'return mod:get("enable_debug_logging") == true'
    $knownRetired   = [pscustomobject]@{ File = $gtProbesPath; Line = 91; Category = 'retired-debug-key'; Text = $pinnedRetiredText }
    $retiredNewText = [pscustomobject]@{ File = $gtProbesPath; Line = 92; Category = 'retired-debug-key'; Text = 'mod:set("enable_debug_logging", false)' }
    $retiredNewPath = [pscustomobject]@{ File = (Join-Path $repoRoot 'general_tweaker_dev\scripts\mods\general_tweaker_dev\_gt_debug_probes.lua'); Line = 91; Category = 'retired-debug-key'; Text = $pinnedRetiredText }
    $knownRetiredOtherCase = [pscustomobject]@{ File = $gtProbesPath.ToUpperInvariant(); Line = 91; Category = 'retired-debug-key'; Text = $pinnedRetiredText }
    $knownRetiredDuplicate = [pscustomobject]@{ File = $gtProbesPath; Line = 95; Category = 'retired-debug-key'; Text = $pinnedRetiredText }
    $retiredFloorOk = (@(Get-UnexpectedRetiredDebugKeyRows -Rows @($knownRetired) -Root $repoRoot).Count -eq 0) `
        -and (@(Get-UnexpectedRetiredDebugKeyRows -Rows @($knownRetiredOtherCase) -Root $repoRoot).Count -eq 0) `
        -and (@(Get-UnexpectedRetiredDebugKeyRows -Rows @() -Root $repoRoot).Count -eq 0) `
        -and (@(Get-UnexpectedRetiredDebugKeyRows -Rows @($knownRetired, $knownRetiredDuplicate) -Root $repoRoot).Count -eq 1) `
        -and (@(Get-UnexpectedRetiredDebugKeyRows -Rows @($knownRetired, $retiredNewText, $retiredNewPath) -Root $repoRoot).Count -eq 2)
    Write-Host ("  [{0}] retired-debug-key floor (#169) -- exact GT stable debt accepted once (any root casing); removal accepted; duplicate, rewritten line + dev twin rejected" -f $(if ($retiredFloorOk) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($retiredFloorOk) { 'Green' } else { 'Red' })
    if (-not $retiredFloorOk) { $allPass = $false }

    $intentPath=Join-Path $repoRoot 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_anim_remap.lua'
    $intent=[pscustomobject]@{File=$intentPath;Line=899;Category='echo';Text='mod:echo(msg)'}
    $intentRows=@($intent,$intent,$intent,$intent,$intent)
    $intentOk=@(Get-UnapprovedLoggingIntentRows -Rows $intentRows -Root $repoRoot).Count -eq 0
    $overflowOk=@(Get-UnapprovedLoggingIntentRows -Rows @($intentRows+$intent) -Root $repoRoot).Count -eq 1
    $changed=[pscustomobject]@{File=$intentPath;Line=899;Category='echo';Text='mod:echo(other_msg)'}
    $changedOk=@(Get-UnapprovedLoggingIntentRows -Rows @($changed) -Root $repoRoot).Count -eq 1
    $intentFloorOk=$intentOk -and $overflowOk -and $changedOk
    Write-Host ("  [{0}] #727 reviewed intent -- exact count accepted; overflow/text drift reported" -f $(if($intentFloorOk){'PASS'}else{'FAIL'})) -ForegroundColor $(if($intentFloorOk){'Green'}else{'Red'})
    if(-not$intentFloorOk){$allPass=$false}

    # Live-source proof: the real scanner (sentinel + multiline pass) must see
    # every executable retired-key site in the pinned stable file, and every one
    # it sees must be inside the floor. While the exact pinned read is still in
    # source the scanner must report exactly that one tolerated site, so a
    # detection regression cannot pass as a silent zero; after the promotion
    # removes it, zero sites are required. The file being absent is a self-test
    # failure, not a skip, so a moved file cannot silently void the proof.
    $liveOk = $false
    $liveTolerated = -1
    $liveUnexpected = -1
    if (Test-Path $gtProbesPath) {
        $liveScan = Scan-LoggingFile -Path $gtProbesPath
        $liveRows = @($liveScan | Where-Object { $_.Category -eq 'retired-debug-key' })
        $liveUnexpected = @(Get-UnexpectedRetiredDebugKeyRows -Rows $liveRows -Root $repoRoot).Count
        $liveTolerated = $liveRows.Count - $liveUnexpected
        $pinnedStillPresent = @((Read-FileUtf8 $gtProbesPath) -split "`r?`n" | Where-Object { $_.Trim() -ceq $pinnedRetiredText }).Count -gt 0
        $expectedTolerated = if ($pinnedStillPresent) { 1 } else { 0 }
        $liveOk = ($liveUnexpected -eq 0 -and $liveTolerated -eq $expectedTolerated)
    }
    Write-Host ("  [{0}] live GT stable _gt_debug_probes.lua -- retired-key sites tolerated={1} unexpected={2}" -f $(if ($liveOk) { 'PASS' } else { 'FAIL' }), $liveTolerated, $liveUnexpected) -ForegroundColor $(if ($liveOk) { 'Green' } else { 'Red' })
    if (-not $liveOk) { $allPass = $false }
    Write-Host ""
    if ($allPass) {
        Write-Host "[check_logging -SelfTest] OK -- all $($cases.Count) fixture verdicts match." -ForegroundColor Green
        return 0
    }
    Write-Host "[check_logging -SelfTest] FAILED -- heuristic/scope regression. Inspect fixtures + Scan-LoggingFile." -ForegroundColor Red
    return 2
}

# ---- main ----
Write-Host "=== check_logging ===" -ForegroundColor Cyan

if ($SelfTest) { exit (Invoke-SelfTest) }

# The issue-specific gate does not need the echo/per-frame census. Pre-filter to
# files that contain a live `mod:warning` token, then reuse the exact same scoped
# scanner for warn-chat classification. This keeps pre-commit/targeted runs fast
# without introducing a second, weaker parser.
if ($WarnChatRegression) {
    $warnRows = @()
    $hardError = $false
    foreach ($f in @(Get-ScanFiles -Root $repoRoot)) {
        try {
            $text = Read-FileUtf8 $f.FullName
            if (-not $rxWarning.IsMatch($text)) { continue }
            $rows = Scan-LoggingFile -Path $f.FullName
            foreach ($row in $rows) {
                if ($row.Category -eq 'warn-chat') { $warnRows += $row }
            }
        } catch {
            Write-Host ("  X {0}: {1}" -f $f.FullName, $_) -ForegroundColor Red
            $hardError = $true
        }
    }
    if ($hardError) {
        Write-Host "[check_logging -WarnChatRegression] ERROR -- one or more candidate files failed to scan." -ForegroundColor Red
        exit 2
    }
    $unexpected = @(Get-UnexpectedWarnChatRows -Rows $warnRows -Root $repoRoot)
    if ($unexpected.Count -gt 0) {
        Write-Host "[check_logging -WarnChatRegression] FAILED -- $($unexpected.Count) new warning-backed diagnostic helper(s)." -ForegroundColor Red
        foreach ($row in $unexpected) {
            $rel = $row.File
            if ($rel.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
            Write-Host ("  ! {0}:{1}`n      {2}" -f $rel, $row.Line, $row.Text) -ForegroundColor Red
        }
        exit 2
    }
    Write-Host "[check_logging -WarnChatRegression] OK -- no new warning-backed diagnostic helpers; legacy stable promotion debt remaining=$($warnRows.Count)." -ForegroundColor Green
    exit 0
}

$all = @()
$hardError = $false
$files = @(Get-ScanFiles -Root $repoRoot)
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
    if (-not $Quiet) { Write-Host "Checking $rel" -ForegroundColor DarkGray }
    try {
        $rows = Scan-LoggingFile -Path $f.FullName
    } catch {
        Write-Host ("  X {0}: {1}" -f $rel, $_) -ForegroundColor Red
        $hardError = $true
        continue
    }
    foreach ($r in $rows) { $all += $r }
}

Write-Host ""
if ($hardError) {
    Write-Host "[check_logging] ERROR -- one or more files failed to scan." -ForegroundColor Red
    exit 2
}

$warnRows = @($all | Where-Object { $_.Category -eq 'warn-chat' })
$retiredRows = @($all | Where-Object { $_.Category -eq 'retired-debug-key' })
$unexpectedRetiredRows = @(Get-UnexpectedRetiredDebugKeyRows -Rows $retiredRows -Root $repoRoot)
if ($unexpectedRetiredRows.Count -gt 0) {
    Write-Host "[check_logging] FAILED -- $($unexpectedRetiredRows.Count) executable retired debug-key site(s) outside the #169 General Tweaker stable promotion debt." -ForegroundColor Red
    foreach ($row in $unexpectedRetiredRows) {
        $rel = $row.File
        if ($rel.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
        Write-Host ("  ! {0}:{1}`n      {2}" -f $rel, $row.Line, $row.Text) -ForegroundColor Red
    }
    exit 2
}
if ($retiredRows.Count -gt 0) {
    Write-Host "[check_logging] #169 retired-key floor: $($retiredRows.Count) pinned General Tweaker stable site tolerated until its user-authorized promotion." -ForegroundColor DarkYellow
} else {
    Write-Host '[check_logging] #169 retired-key floor: zero executable sites.' -ForegroundColor DarkGreen
}
$printfRows = @($all | Where-Object { $_.Category -eq 'printf-mutation' })
if ($printfRows.Count -gt 0) {
    Write-Host "[check_logging] FAILED -- $($printfRows.Count) runtime write(s) to global/environment printf (#1637): the deployed-source authority rejects the whole deployed record of any mod that mutates raw printf; keep printf swaps in the offline qa/lua harness only." -ForegroundColor Red
    foreach ($row in $printfRows) {
        $rel = $row.File
        if ($rel.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
        Write-Host ("  ! {0}:{1}`n      {2}" -f $rel, $row.Line, $row.Text) -ForegroundColor Red
    }
    exit 2
}
Write-Host '[check_logging] #1637 printf-mutation floor: zero sites.' -ForegroundColor DarkGreen
# Tolerated floor rows are promotion debt, not advisory hygiene findings; keep
# them out of the echo/per-frame/warn-chat census below.
$all = @($all | Where-Object { $_.Category -notin @('retired-debug-key', 'printf-mutation') })
$unexpectedWarnRows = @(Get-UnexpectedWarnChatRows -Rows $warnRows -Root $repoRoot)
if ($unexpectedWarnRows.Count -gt 0) {
    Write-Host "[check_logging] FAILED -- $($unexpectedWarnRows.Count) new warning-backed diagnostic helper(s) exceed the #427 migration floor." -ForegroundColor Red
    foreach ($row in $unexpectedWarnRows) {
        $rel = $row.File
        if ($rel.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
        Write-Host ("  ! {0}:{1}`n      {2}" -f $rel, $row.Line, $row.Text) -ForegroundColor Red
    }
    exit 2
}

$beforeIntentCount=$all.Count
$all=@(Get-UnapprovedLoggingIntentRows -Rows $all -Root $repoRoot)
$approvedIntentCount=$beforeIntentCount-$all.Count
if($approvedIntentCount -gt 0){
    Write-Host "[check_logging] #727 reviewed intent: $approvedIntentCount exact echo/per-frame site(s) classified; source/count drift reappears." -ForegroundColor DarkGreen
}

if ($all.Count -eq 0) {
    Write-Host "[check_logging] OK -- no logging-hygiene findings." -ForegroundColor Green
    exit 0
}

# ---- report: counts per mod, then file:line detail per category ----
$byMod = $all | Group-Object { Get-ModName -Path $_.File -Root $repoRoot } | Sort-Object Name
Write-Host "[check_logging] ADVISORY findings: $($all.Count) (echo=$(@($all | Where-Object Category -eq 'echo').Count), per-frame=$(@($all | Where-Object Category -eq 'perframe').Count), warn-chat=$(@($all | Where-Object Category -eq 'warn-chat').Count))" -ForegroundColor Yellow
Write-Host ""
Write-Host "Per-mod counts:" -ForegroundColor Yellow
foreach ($g in $byMod) {
    $e = @($g.Group | Where-Object Category -eq 'echo').Count
    $p = @($g.Group | Where-Object Category -eq 'perframe').Count
    $w = @($g.Group | Where-Object Category -eq 'warn-chat').Count
    Write-Host ("  {0,-32} total={1,-3} echo={2} per-frame={3} warn-chat={4}" -f $g.Name, $g.Count, $e, $p, $w) -ForegroundColor Yellow
}
Write-Host ""

$labels = @{
    'echo'      = "mod:echo outside the § 3.6 chat-echo allowances (route routine diagnostics through _dbg log-only; annotate a legit reply with -- allow-echo: <reason>)"
    'perframe'  = "mod:info/mod:warning inside a per-frame update() body (gate on a state change or move off the hot path; annotate with -- allow-perframe: <reason>)"
    'warn-chat' = "mod:warning inside a dbg/alert helper posts to CHAT under VMF defaults (Issue #240; use pcall-guarded printf for log-only; annotate an intentional chat alert with -- allow-warn-chat: <reason>)"
}
foreach ($cat in @('echo','perframe','warn-chat')) {
    $rows = @($all | Where-Object Category -eq $cat)
    if ($rows.Count -eq 0) { continue }
    Write-Host "[$cat] $($labels[$cat])" -ForegroundColor Yellow
    foreach ($r in $rows) {
        $rel = $r.File
        if ($rel.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
        Write-Host ("  ! {0}:{1}" -f $rel, $r.Line) -ForegroundColor Yellow
        Write-Host ("      $($r.Text)") -ForegroundColor DarkYellow
    }
    Write-Host ""
}
exit 1
