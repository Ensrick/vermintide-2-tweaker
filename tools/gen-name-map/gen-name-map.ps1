# ============================================================================
# gen-name-map.ps1 — authoritative INTERNAL-key -> in-game DISPLAY-name map
# ============================================================================
#
# WHAT THIS IS
#   Regenerates the single authoritative mapping from internal keys (vanilla
#   weapon/skin/career/breed keys AND mod-created variant/illusion keys) to
#   their in-game English display names, sourced from GROUND TRUTH — never
#   hand-typed. Two outputs:
#       docs/generated/NAME_MAP.generated.json  (machine-authoritative)
#       docs/generated/NAME_MAP.generated.md    (human/Claude-greppable)
#
# WHY IT EXISTS
#   The hand-maintained catalogs (ITEM_LIST.md, WEAPON_CATALOG.md,
#   CHARACTER_COSMETIC_CATALOG.md, _cos_probe.txt) drift, then get trusted while
#   stale -> propagated errors + hallucination. This regenerates from the source
#   tables every time, so drift produces a stable, diffable change rather than a
#   silent lie. The modded-item half (cwv variants, cosmetics custom illusions,
#   wt unlock map) is the centerpiece — that is the maintainer's worst pain.
#
# GROUND-TRUTH SOURCES (verified Phase 0, 2026-05-30):
#   - Vanilla IML keys: <VTSRC>/scripts/settings/equipment/item_master_list*.lua
#                       + <VTSRC>/scripts/settings/dlcs/*/item_master_list_*.lua
#     These carry display_name = "<loc_key>" (a LOC KEY, not English) + item_type
#     + slot_type + can_wield + required_dlc.
#   - Vanilla careers: <VTSRC>/scripts/settings/profiles/career_settings.lua
#                      (display_name is a loc key, e.g. "dr_ironbreaker").
#   - Vanilla breeds:  <VTSRC>/scripts/settings/breeds/*.lua (boss breeds carry a
#                      display name loc key; most fodder breeds carry none).
#   - VANILLA ENGLISH STRINGS ARE NOT IN THE DECOMPILED SOURCE. There is no
#     localization/ dir; the English values live in bundled .package files that
#     were not decompiled to .lua. So for vanilla keys we can resolve
#     key -> loc_key but usually NOT loc_key -> English. Honest handling:
#       * boons: dumps/boon_loc_dump.txt carries real English (source=runtime_dump).
#       * everything else vanilla: display_name=null, unresolved=true,
#         reason="vanilla loc string not in decompiled source". NEVER fabricated.
#   - MOD-created items (FULLY resolvable from repo data — the centerpiece):
#       * cwv  _variant_definitions[].display_name (literal English) in
#         character_weapon_variants.lua (~line 232). Mirrored at runtime into
#         _display_names[item_key.."_name"] (line ~6226) + item_type->display_name
#         (line ~6246), exposed via the _G Localize hook (line ~6259). The
#         commented-out --[[ ]] musket block (~582-602) is SKIPPED.
#       * cosmetics _custom_illusions[].display_name (literal English) in
#         _cos_illusions.lua; mirrored into the mod's localization/runtime tables.
#       * wt  weapon_unlock_map (career -> {weapon_key,...}) in wt_unlock_data.lua
#         (~line 44); loc keys unlock_<career>_<weapon> in weapon_tweaker_localization.lua.
#   - Mod loc tables: <mod>/scripts/mods/<mod>/<mod>_localization.lua
#     return { key = { en = "..." }, ... }.
#
# USAGE
#   .\tools\gen-name-map\gen-name-map.ps1 -GenDate 2026-05-30
#       -RepoRoot   <repo>   (default: two levels up from this script)
#       -VtSrc      <path>   (default: ..\..\..\Vermintide-2-Source-Code)
#       -GenDate    <string> REQUIRED — stamped into the banner (env has no clock)
#       -Quiet               suppress per-phase progress
#
# Exit codes: 0 = generated OK, 2 = fatal (missing source tree / write failure).
# ============================================================================

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot "..\.."),
    [string]$VtSrc    = (Join-Path $PSScriptRoot "..\..\..\Vermintide-2-Source-Code"),
    [Parameter(Mandatory = $true)][string]$GenDate,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
if (-not (Test-Path $VtSrc)) {
    Write-Host "[gen-name-map] FATAL: Vermintide-2-Source-Code not found at $VtSrc" -ForegroundColor Red
    exit 2
}
$vtSrc = (Resolve-Path $VtSrc).Path

function Log($msg, $color = "DarkGray") { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }
function Read-Utf8([string]$p) { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }

# ----------------------------------------------------------------------------
# Entry accumulator. Each entry is the JSON schema row.
#   key, kind, display_name, display_name_source, loc_key, item_type,
#   slot_type, careers, source, required_dlc, unresolved, reason
# Keyed by "<source>::<kind>::<key>" so the same key from two sources both land.
# ----------------------------------------------------------------------------
$script:entries = [ordered]@{}

function Add-Entry {
    param(
        [string]$Key, [string]$Kind, $DisplayName, [string]$DisplayNameSource,
        [string]$LocKey, [string]$ItemType, [string]$SlotType,
        [string[]]$Careers, [string]$Source, [string]$RequiredDlc,
        [bool]$Unresolved = $false, [string]$Reason = $null
    )
    $id = "$Source::$Kind::$Key"
    # First writer wins for a given (source,kind,key). Generation is deterministic
    # because callers run in a fixed order and inputs are sorted before iteration.
    if ($script:entries.Contains($id)) { return }
    $script:entries[$id] = [ordered]@{
        key                 = $Key
        kind                = $Kind
        display_name        = $DisplayName
        display_name_source = $DisplayNameSource
        loc_key             = $LocKey
        item_type           = $ItemType
        slot_type           = $SlotType
        careers             = @($Careers)
        source              = $Source
        required_dlc        = $RequiredDlc
        unresolved          = $Unresolved
        reason              = $Reason
    }
}

# ----------------------------------------------------------------------------
# PARSER: mod _localization.lua  ->  hashtable key -> English ({ en = "..." })
# Mirrors qa/check_localization.ps1's three patterns (standard, en(), loc.key=).
# ----------------------------------------------------------------------------
function Parse-LocFile([string]$path) {
    $result = @{}
    if (-not (Test-Path $path)) { return $result }
    $text = Read-Utf8 $path
    $rx1 = '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"\s*[,}]'
    foreach ($m in [regex]::Matches($text, $rx1)) { $result[$m.Groups[1].Value] = $m.Groups[2].Value }
    $rx2 = '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*en\s*\(\s*"((?:[^"\\]|\\.)*)"\s*\)'
    foreach ($m in [regex]::Matches($text, $rx2)) { $result[$m.Groups[1].Value] = $m.Groups[2].Value }
    $rx3 = '(?m)^\s*loc\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"((?:[^"\\]|\\.)*)"\s*[,}]'
    foreach ($m in [regex]::Matches($text, $rx3)) { $result[$m.Groups[1].Value] = $m.Groups[2].Value }
    return $result
}

# ----------------------------------------------------------------------------
# PARSER: boon English dump  ->  hashtable boon_key -> English
# Format: key<TAB>English<TAB>description  (dumps/boon_loc_dump.txt)
# ----------------------------------------------------------------------------
function Parse-BoonDump([string]$path) {
    $result = @{}
    if (-not (Test-Path $path)) { return $result }
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line -match '^\s*$') { continue }
        $parts = $line -split "`t"
        if ($parts.Count -ge 2 -and $parts[0].Trim()) { $result[$parts[0].Trim()] = $parts[1].Trim() }
    }
    return $result
}

# ----------------------------------------------------------------------------
# PARSER: in-game name dump (Phase 1 — gt_dev `gt_auto_name_dump`).
# Two on-disk shapes are accepted, same tab-separated <loc_key>\t<English>
# payload either way:
#   (a) Plain dump file (a sync step landed it): lines are `<loc_key>\t<English>`
#       exactly like dumps/boon_loc_dump.txt (English in column 2; a 3rd column,
#       if present, is ignored).
#   (b) Console log: gt emits `... [gt:name_dump] <loc_key>\t<English>` lines
#       (the engine prefixes a timestamp/level tag). We grep for the marker,
#       take everything AFTER it, then split on the first tab. BEGIN/END marker
#       lines (`[gt:name_dump] BEGIN build=...`) are skipped.
# Returns @{ pairs = @{loc_key->English}; build = <build id or $null> }.
# ----------------------------------------------------------------------------
function Parse-NameDump([string]$path) {
    $pairs = @{}
    $build = $null
    if (-not (Test-Path $path)) { return @{ pairs = $pairs; build = $build } }
    $marker = '[gt:name_dump]'
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line -match '^\s*$') { continue }
        $payload = $null
        $idx = $line.IndexOf($marker)
        if ($idx -ge 0) {
            # console-log shape: take text after the marker
            $payload = $line.Substring($idx + $marker.Length).TrimStart()
        }
        elseif ($line.Contains("`t")) {
            # plain-file shape: the whole line is the payload
            $payload = $line
        }
        else { continue }
        # BEGIN/END provenance markers — capture build id, don't treat as a pair.
        $bm = [regex]::Match($payload, '^(?:BEGIN|END)\s+build=(\S+)')
        if ($bm.Success) { if (-not $build) { $build = $bm.Groups[1].Value }; continue }
        $parts = $payload -split "`t"
        if ($parts.Count -ge 2 -and $parts[0].Trim()) {
            $k = $parts[0].Trim()
            # First writer wins (a console log may contain multiple dumps across
            # sessions; the file is read top-to-bottom so the oldest line for a
            # given key wins — but identical builds emit identical English, so
            # this is deterministic regardless).
            if (-not $pairs.ContainsKey($k)) { $pairs[$k] = $parts[1].Trim() }
        }
    }
    return @{ pairs = $pairs; build = $build }
}

# ----------------------------------------------------------------------------
# DISCOVERY: find the freshest in-game name dump with NO flags, in priority
# order. Returns @{ path = <file>; pairs = @{...}; build = <id>; kind = <str> }
# or $null if none found anywhere (graceful fallback — vanilla stays unresolved).
#   1. repo dumps/name_loc_dump.txt        (a sync step landed a plain file)
#   2. Fatshark user-dir dumps/name_loc_dump.txt  (if a future file-write path
#      is ever unlocked; harmless to probe today)
#   3. newest console_logs/*.log containing [gt:name_dump] lines
# ----------------------------------------------------------------------------
function Find-NameDump([string]$repoRoot) {
    # (1) repo plain file
    $repoDump = Join-Path $repoRoot 'dumps\name_loc_dump.txt'
    if (Test-Path $repoDump) {
        $d = Parse-NameDump $repoDump
        if ($d.pairs.Count -gt 0) { return @{ path = $repoDump; pairs = $d.pairs; build = $d.build; kind = 'repo_file' } }
    }

    # Fatshark user dir root: %APPDATA%\Fatshark\Vermintide 2
    $appdata = $env:APPDATA
    $fatshark = if ($appdata) { Join-Path $appdata 'Fatshark\Vermintide 2' } else { $null }

    # (2) Fatshark user-dir plain file
    if ($fatshark) {
        $userDump = Join-Path $fatshark 'dumps\name_loc_dump.txt'
        if (Test-Path $userDump) {
            $d = Parse-NameDump $userDump
            if ($d.pairs.Count -gt 0) { return @{ path = $userDump; pairs = $d.pairs; build = $d.build; kind = 'user_file' } }
        }
    }

    # (3) newest console log carrying [gt:name_dump] lines
    if ($fatshark) {
        $logDir = Join-Path $fatshark 'console_logs'
        if (Test-Path $logDir) {
            $logs = Get-ChildItem -Path $logDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending
            foreach ($lg in $logs) {
                # Cheap pre-check before a full parse: does the file mention the marker?
                $hasMarker = $false
                try {
                    foreach ($line in [System.IO.File]::ReadLines($lg.FullName)) {
                        if ($line.Contains('[gt:name_dump]')) { $hasMarker = $true; break }
                    }
                } catch { continue }
                if (-not $hasMarker) { continue }
                $d = Parse-NameDump $lg.FullName
                if ($d.pairs.Count -gt 0) { return @{ path = $lg.FullName; pairs = $d.pairs; build = $d.build; kind = 'console_log' } }
            }
        }
    }

    return $null
}

# ----------------------------------------------------------------------------
# PARSER: vanilla IML files. Extracts, per ItemMasterList.<key> = { ... } block:
#   display_name (loc key), item_type, slot_type, can_wield list, required_dlc.
# Robust to: minification is N/A (these are pretty-printed), nested tables
# (can_wield), commented `--` lines (stripped), both `ItemMasterList.key = {`
# and `ItemMasterList["key"] = {` and `ItemMasterList[#"..."]` forms.
# Block boundary: from the assignment's opening `{` to its matching `}` via
# brace-depth counting on the comment-stripped text.
# ----------------------------------------------------------------------------
function Strip-LuaComments([string]$text) {
    # Remove --[[ ... ]] block comments (non-greedy) then -- line comments.
    # Keep it simple: this is data-table source, not code with string literals
    # containing "--". Good enough + deterministic for these files.
    $text = [regex]::Replace($text, '(?s)--\[\[.*?\]\]', '')
    $text = [regex]::Replace($text, '(?m)--[^\r\n]*', '')
    return $text
}

function Get-MatchingBraceBlock([string]$text, [int]$openIdx) {
    # $openIdx points at the '{'. Return substring through its matching '}'.
    $depth = 0
    for ($i = $openIdx; $i -lt $text.Length; $i++) {
        $c = $text[$i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { return $text.Substring($openIdx, $i - $openIdx + 1) } }
    }
    return $text.Substring($openIdx)  # unbalanced; return tail
}

function Get-Field([string]$block, [string]$field) {
    $m = [regex]::Match($block, "(?m)^\s*$field\s*=\s*`"((?:[^`"\\]|\\.)*)`"")
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Get-CanWield([string]$block) {
    # can_wield = { "a", "b", } — grab the FIRST such list in the block (top-level).
    $m = [regex]::Match($block, '(?s)can_wield\s*=\s*\{(.*?)\}')
    if (-not $m.Success) { return @() }
    $inner = $m.Groups[1].Value
    $list = @()
    foreach ($qm in [regex]::Matches($inner, '"([^"]+)"')) { $list += $qm.Groups[1].Value }
    return $list
}

function Parse-ImlFile([string]$path, [string]$requiredDlcDefault) {
    # Returns array of entries: @{ key; display_name(=loc); item_type; slot_type; can_wield; required_dlc }
    $out = @()
    if (-not (Test-Path $path)) { return $out }
    $raw = Read-Utf8 $path
    $text = Strip-LuaComments $raw
    # Find every `ItemMasterList.<key> = {` or `ItemMasterList["<key>"] = {`
    $assignRx = [regex]'(?m)^\s*ItemMasterList(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[\s*"([^"]+)"\s*\])\s*=\s*\{'
    foreach ($m in $assignRx.Matches($text)) {
        $key = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        $openIdx = $text.IndexOf('{', $m.Index)
        if ($openIdx -lt 0) { continue }
        $block = Get-MatchingBraceBlock $text $openIdx
        $out += [ordered]@{
            key          = $key
            loc_key      = (Get-Field $block 'display_name')
            item_type    = (Get-Field $block 'item_type')
            slot_type    = (Get-Field $block 'slot_type')
            can_wield    = (Get-CanWield $block)
            required_dlc = (Get-Field $block 'required_dlc')
        }
    }
    return $out
}

# ----------------------------------------------------------------------------
# PARSER: career_settings.lua  ->  array of @{ key; loc_key; required_dlc }
# CareerSettings.<key> = { ... display_name = "<loc>" ... }
# ----------------------------------------------------------------------------
function Get-Depth1Children([string]$listBlock) {
    # Given a block whose outermost { } is a table literal, return the substrings
    # of each direct (depth-1) child `{ ... }`.
    $children = @()
    $depth = 0; $start = -1
    for ($i = 0; $i -lt $listBlock.Length; $i++) {
        $c = $listBlock[$i]
        if ($c -eq '{') { $depth++; if ($depth -eq 2) { $start = $i } }
        elseif ($c -eq '}') { if ($depth -eq 2 -and $start -ge 0) { $children += $listBlock.Substring($start, $i - $start + 1); $start = -1 }; $depth-- }
    }
    return $children
}

function Parse-CareerSettings([string]$path) {
    # Handles BOTH forms:
    #   (a) base file: CareerSettings = { dr_ironbreaker = { ... }, es_huntsman = { ... } }
    #   (b) DLC files: CareerSettings.es_questingknight = { ... }
    $out = @()
    if (-not (Test-Path $path)) { return $out }
    $text = Strip-LuaComments (Read-Utf8 $path)

    # (a) nested table literal — match the immediate child key preceding each
    #     depth-1 child block.
    $tblM = [regex]::Match($text, '(?m)^\s*CareerSettings\s*=\s*\{')
    if ($tblM.Success) {
        $openIdx = $text.IndexOf('{', $tblM.Index)
        $tblBlock = Get-MatchingBraceBlock $text $openIdx
        # Re-walk to capture (childKey, childBlock) pairs: childKey is the
        # identifier immediately before the depth-2 opening brace.
        $depth = 0; $start = -1
        for ($i = 0; $i -lt $tblBlock.Length; $i++) {
            $c = $tblBlock[$i]
            if ($c -eq '{') {
                $depth++
                if ($depth -eq 2) {
                    $start = $i
                    # find key: backtrack over "<ws>=<ws>" then grab identifier
                    $pre = $tblBlock.Substring(0, $i)
                    $km = [regex]::Match($pre, '([A-Za-z_][A-Za-z0-9_]*)\s*=\s*$')
                    $childKey = if ($km.Success) { $km.Groups[1].Value } else { $null }
                }
            }
            elseif ($c -eq '}') {
                if ($depth -eq 2 -and $start -ge 0) {
                    $block = $tblBlock.Substring($start, $i - $start + 1)
                    if ($childKey) {
                        $out += [ordered]@{ key = $childKey; loc_key = (Get-Field $block 'display_name'); required_dlc = (Get-Field $block 'required_dlc') }
                    }
                    $start = -1
                }
                $depth--
            }
        }
    }

    # (b) CareerSettings.<key> = { ... } assignment form (DLC files).
    $assignRx = [regex]'(?m)^\s*CareerSettings\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{'
    foreach ($m in $assignRx.Matches($text)) {
        $key = $m.Groups[1].Value
        $openIdx = $text.IndexOf('{', $m.Index)
        if ($openIdx -lt 0) { continue }
        $block = Get-MatchingBraceBlock $text $openIdx
        $out += [ordered]@{ key = $key; loc_key = (Get-Field $block 'display_name'); required_dlc = (Get-Field $block 'required_dlc') }
    }
    return $out
}

# ----------------------------------------------------------------------------
# PARSER: breed files. Most carry a `display_name` loc key inside `local
# breed_data = { ... }` or `Breeds.<key> = { ... }`. We collect any
# display_name loc key keyed by the breed name we can find. Fodder breeds with
# no display name are skipped (we only emit breeds we can key + tag).
# ----------------------------------------------------------------------------
function Parse-BreedFiles([string]$breedsDir) {
    # PHASE-0 FINDING: VT2 breeds in the decompiled source carry NO usable
    # display-name loc key. `display_name` exists only on the training dummy;
    # `custom_health_bar_name` is a function, not a string; and the English
    # enemy names live in undumped .package bundles. So we enumerate every
    # `Breeds.<key>` (and the `local breed_data` name where present) as the key
    # inventory, with loc_key = the breed key itself (VT2 convention) and
    # unresolved=true. This gives breed-key coverage without fabricating names.
    $out = @()
    if (-not (Test-Path $breedsDir)) { return $out }
    $seen = @{}
    foreach ($f in (Get-ChildItem -Path $breedsDir -Filter '*.lua' -File)) {
        $text = Strip-LuaComments (Read-Utf8 $f.FullName)
        foreach ($am in [regex]::Matches($text, '(?m)Breeds\.([A-Za-z_][A-Za-z0-9_]*)\s*=')) {
            $key = $am.Groups[1].Value
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            # If a real display_name loc key IS present (training dummy), keep it;
            # else the breed key is its own conventional loc key.
            $dn = Get-Field $text 'display_name'
            $out += [ordered]@{ key = $key; loc_key = ($dn ? $dn : $key); file = $f.Name }
        }
    }
    return $out
}

# ============================================================================
# LOAD ENGLISH SOURCES (mod loc tables + boon dump)
# ============================================================================
Log "[1/6] Loading mod localization tables + boon dump..."

# Mod loc tables, keyed by mod_id. We key by directory name (matches loc-file mod dir).
$modLoc = @{}   # modDir -> hashtable(loc key -> English)
$locFiles = Get-ChildItem -Path $repoRoot -Filter '*_localization.lua' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $p = $_.FullName
        $p -notlike '*\_archive\*' -and $p -notlike '*\bundleV2\*' -and $p -notlike '*\.build\*' `
            -and $p -notlike '*\.temp\*' -and $p -notlike '*\tweaker\*' -and $p -notlike '*\sample_*\*'
    }
foreach ($lf in $locFiles) {
    # <repo>/<mod>/scripts/mods/<mod>/<mod>_localization.lua -> mod dir = 3 up
    $d = Split-Path $lf.FullName -Parent
    for ($i = 0; $i -lt 3; $i++) { $d = Split-Path $d -Parent }
    $modDir = Split-Path $d -Leaf
    if (-not $modLoc.ContainsKey($modDir)) { $modLoc[$modDir] = @{} }
    $parsed = Parse-LocFile $lf.FullName
    foreach ($k in $parsed.Keys) { $modLoc[$modDir][$k] = $parsed[$k] }
}

# Aggregate ALL mod-loc keys into one English lookup (for cross-mod resolution
# in the validator-style "resolves anywhere" checks; the generator prefers the
# owning mod's table first).
$allModLoc = @{}
foreach ($md in $modLoc.Keys) { foreach ($k in $modLoc[$md].Keys) { $allModLoc[$k] = $modLoc[$md][$k] } }

$boonEng = Parse-BoonDump (Join-Path $repoRoot 'dumps\boon_loc_dump.txt')
Log "      mod loc files: $($locFiles.Count); boon English entries: $($boonEng.Count)"

# In-game name dump (Phase 1 — gt_dev gt_auto_name_dump). Discovered with no
# flags; $null when none exists anywhere (graceful fallback — vanilla stays
# unresolved exactly as before). Ingested AFTER all entries are accumulated.
$nameDump = Find-NameDump $repoRoot
if ($nameDump) {
    Log "      name dump: $($nameDump.pairs.Count) loc_key->English from $($nameDump.kind) ($($nameDump.path)); build=$($nameDump.build)"
} else {
    Log "      name dump: none found (vanilla names stay unresolved)"
}

# ============================================================================
# VANILLA ITEMS (IML across base equipment + per-DLC)
# ============================================================================
Log "[2/6] Parsing vanilla item_master_list across base + DLC files..."

$imlFiles = @()
$imlFiles += Get-ChildItem -Path (Join-Path $vtSrc 'scripts\settings\equipment') -Filter 'item_master_list*.lua' -File -ErrorAction SilentlyContinue
$dlcRoot = Join-Path $vtSrc 'scripts\settings\dlcs'
if (Test-Path $dlcRoot) {
    $imlFiles += Get-ChildItem -Path $dlcRoot -Filter 'item_master_list_*.lua' -Recurse -File -ErrorAction SilentlyContinue
}

# Map item_type -> kind bucket for the map's `kind` column.
function Map-Kind([string]$itemType, [string]$slotType) {
    # PHASE-0 FINDING: vanilla weapon IML entries set item_type to the weapon
    # FAMILY KEY (e.g. "bw_1h_crowbill"), not "melee"/"ranged". So bucket by
    # slot_type, which IS the reliable categorizer (melee/ranged/hat/skin/
    # weapon_skin/frame/...). item_type is preserved verbatim in its own column.
    switch -Regex ($slotType) {
        '^(melee|ranged)$'            { return 'weapon' }
        '^hat$'                       { return 'hat' }
        '^skin$'                      { return 'skin' }
        '^frame$'                     { return 'frame' }
        '^weapon_skin$'               { return 'weapon_skin' }
        '^weapon_pose(_bundle)?$'     { return 'weapon_pose' }
        '^(necklace|ring|trinket)$'   { return 'trinket' }
        '^(bundle|cosmetic_bundle)$'  { return 'bundle' }
        '^deed$'                      { return 'deed' }
        '^(crafting_material|chips|loot_chest|healthkit|potion|grenade)$' { return $slotType }
        default {
            # Fall back to item_type for entries with no/odd slot_type, but
            # collapse the weapon-family-key case into 'weapon' when item_type
            # looks like a <char>_<...> weapon family rather than a real type.
            if ($itemType -match '^(melee|ranged)$') { return 'weapon' }
            if ($itemType -in @('skin','hat','frame','weapon_skin','career','breed')) { return $itemType }
            if (-not $slotType -and -not $itemType) { return 'item' }
            # weapon family key (es_1h_sword, bw_staff_beam, ...) -> weapon
            if ($itemType -match '^(es|wh|dr|bw|we)_') { return 'weapon' }
            if ($slotType) { return $slotType }
            return ($itemType ? $itemType : 'item')
        }
    }
}

$vanillaCount = 0
$imlSeen = @{}   # dedupe by key across IML files (first file wins; base before DLC by sort)
foreach ($f in ($imlFiles | Sort-Object FullName)) {
    foreach ($e in (Parse-ImlFile $f.FullName)) {
        if ($imlSeen.ContainsKey($e.key)) { continue }
        $imlSeen[$e.key] = $true
        $kind = Map-Kind $e.item_type $e.slot_type
        # Resolve English: vanilla loc strings are NOT in the decompiled source.
        # Try mod loc (some mods define vanilla-key overrides) and boon dump as
        # last-resort; otherwise unresolved=true. NEVER fabricate.
        $eng = $null; $src = $null; $unres = $false; $reason = $null
        if ($e.loc_key -and $allModLoc.ContainsKey($e.loc_key)) {
            $eng = $allModLoc[$e.loc_key]; $src = 'mod_loc'
        }
        elseif ($e.loc_key -and $boonEng.ContainsKey($e.loc_key)) {
            $eng = $boonEng[$e.loc_key]; $src = 'runtime_dump'
        }
        else {
            $unres = $true
            $reason = 'vanilla loc string not in decompiled source'
        }
        Add-Entry -Key $e.key -Kind $kind -DisplayName $eng -DisplayNameSource $src `
            -LocKey $e.loc_key -ItemType $e.item_type -SlotType $e.slot_type `
            -Careers $e.can_wield -Source 'vanilla' -RequiredDlc $e.required_dlc `
            -Unresolved $unres -Reason $reason
        $vanillaCount++
    }
}
Log "      vanilla IML keys: $vanillaCount (from $($imlFiles.Count) files)"

# ============================================================================
# VANILLA CAREERS
# ============================================================================
Log "[3/6] Parsing vanilla careers + breeds..."
$careerCount = 0
$careerFiles = @((Join-Path $vtSrc 'scripts\settings\profiles\career_settings.lua'))
$careerFiles += (Get-ChildItem -Path $dlcRoot -Filter 'career_settings*.lua' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
$careerSeen = @{}
foreach ($cf in $careerFiles) {
    foreach ($c in (Parse-CareerSettings $cf)) {
        if ($careerSeen.ContainsKey($c.key)) { continue }
        $careerSeen[$c.key] = $true
        $eng = $null; $src = $null; $unres = $true; $reason = 'vanilla loc string not in decompiled source'
        if ($c.loc_key -and $allModLoc.ContainsKey($c.loc_key)) { $eng = $allModLoc[$c.loc_key]; $src = 'mod_loc'; $unres = $false; $reason = $null }
        Add-Entry -Key $c.key -Kind 'career' -DisplayName $eng -DisplayNameSource $src `
            -LocKey $c.loc_key -ItemType 'career' -SlotType $null -Careers @() `
            -Source 'vanilla' -RequiredDlc $c.required_dlc -Unresolved $unres -Reason $reason
        $careerCount++
    }
}

# VANILLA BREEDS (boss breeds carry display names; fodder usually don't)
$breedCount = 0
foreach ($b in (Parse-BreedFiles (Join-Path $vtSrc 'scripts\settings\breeds'))) {
    $eng = $null; $src = $null; $unres = $true; $reason = 'vanilla loc string not in decompiled source'
    if ($b.loc_key -and $allModLoc.ContainsKey($b.loc_key)) { $eng = $allModLoc[$b.loc_key]; $src = 'mod_loc'; $unres = $false; $reason = $null }
    Add-Entry -Key $b.key -Kind 'breed' -DisplayName $eng -DisplayNameSource $src `
        -LocKey $b.loc_key -ItemType 'breed' -SlotType $null -Careers @() `
        -Source 'vanilla' -RequiredDlc $null -Unresolved $unres -Reason $reason
    $breedCount++
}
Log "      vanilla careers: $careerCount; breeds with display name: $breedCount"

# ============================================================================
# MOD-CREATED: CWV _variant_definitions (THE CENTERPIECE)
# ============================================================================
Log "[4/6] Parsing cwv _variant_definitions (mod-created variants)..."
$cwvCount = 0
$cwvFile = Join-Path $repoRoot 'character_weapon_variants\scripts\mods\character_weapon_variants\character_weapon_variants.lua'
if (Test-Path $cwvFile) {
    $cwvText = Read-Utf8 $cwvFile
    # Isolate the `local _variant_definitions = { ... }` block so we don't pick
    # up item_key strings elsewhere. Then within it, skip --[[ ]] commented
    # entries (the musket block) by stripping block comments FIRST.
    $vdStart = [regex]::Match($cwvText, 'local\s+_variant_definitions\s*=\s*\{')
    if ($vdStart.Success) {
        $openIdx = $cwvText.IndexOf('{', $vdStart.Index)
        $vdBlockRaw = Get-MatchingBraceBlock $cwvText $openIdx
        # Strip block comments (removes the --[[ musket ]] entry) but KEEP line
        # comments here — the inline `-- "Old Musket"` notes don't carry fields.
        $vdBlock = [regex]::Replace($vdBlockRaw, '(?s)--\[\[.*?\]\]', '')
        # Each entry is a top-level `{ ... }` inside the list. Walk brace depth to
        # split into entry blocks (depth 1 children of the list).
        $entryBlocks = @()
        $depth = 0; $entryStart = -1
        for ($i = 0; $i -lt $vdBlock.Length; $i++) {
            $c = $vdBlock[$i]
            if ($c -eq '{') { $depth++; if ($depth -eq 2) { $entryStart = $i } }
            elseif ($c -eq '}') { if ($depth -eq 2 -and $entryStart -ge 0) { $entryBlocks += $vdBlock.Substring($entryStart, $i - $entryStart + 1); $entryStart = -1 }; $depth-- }
        }
        foreach ($eb in $entryBlocks) {
            $itemKey = Get-Field $eb 'item_key'
            if (-not $itemKey) { continue }   # not a variant entry (e.g. stray table)
            $disp    = Get-Field $eb 'display_name'      # literal English
            $base    = Get-Field $eb 'base_weapon'
            $itemTy  = Get-Field $eb 'item_type'
            $careers = Get-CanWield $eb                  # cwv uses `careers = { ... }`
            if (-not $careers -or $careers.Count -eq 0) {
                # cwv uses `careers =` not `can_wield =`; grab that list explicitly.
                $cm = [regex]::Match($eb, '(?s)careers\s*=\s*\{(.*?)\}')
                if ($cm.Success) { $careers = @(); foreach ($qm in [regex]::Matches($cm.Groups[1].Value, '"([^"]+)"')) { $careers += $qm.Groups[1].Value } }
            }
            $skinOnly = ($eb -match '(?m)^\s*skin_only\s*=\s*true')
            $kind = if ($skinOnly) { 'cwv_skin_only' } else { 'cwv_variant' }
            # Authoritative resolution: literal display_name from the def table.
            # This is what _display_names[item_key.."_name"] is set to + what the
            # Localize hook returns. If somehow absent, fall back to the mod loc
            # key <item_key>_name; else unresolved.
            $eng = $disp; $dsrc = 'literal'; $unres = $false; $reason = $null
            if (-not $eng) {
                $lk = "$($itemKey)_name"
                if ($modLoc.ContainsKey('character_weapon_variants') -and $modLoc['character_weapon_variants'].ContainsKey($lk)) {
                    $eng = $modLoc['character_weapon_variants'][$lk]; $dsrc = 'mod_loc'
                } else { $unres = $true; $dsrc = $null; $reason = 'cwv variant has no literal display_name and no <key>_name loc entry' }
            }
            Add-Entry -Key $itemKey -Kind $kind -DisplayName $eng -DisplayNameSource $dsrc `
                -LocKey "$($itemKey)_name" -ItemType ($itemTy ? $itemTy : $base) -SlotType $null `
                -Careers $careers -Source 'character_weapon_variants' -RequiredDlc $null `
                -Unresolved $unres -Reason $reason
            $cwvCount++
        }
    }
}
Log "      cwv variant entries: $cwvCount"

# ============================================================================
# MOD-CREATED: cosmetics_tweaker _custom_illusions
# ============================================================================
Log "[5/6] Parsing cosmetics_tweaker _custom_illusions..."
$cosCount = 0
$cosFile = Join-Path $repoRoot 'cosmetics_tweaker\scripts\mods\cosmetics_tweaker\_cos_illusions.lua'
if (Test-Path $cosFile) {
    $cosText = Read-Utf8 $cosFile
    $ciStart = [regex]::Match($cosText, 'local\s+_custom_illusions\s*=\s*\{')
    if ($ciStart.Success) {
        $openIdx = $cosText.IndexOf('{', $ciStart.Index)
        $ciBlockRaw = Get-MatchingBraceBlock $cosText $openIdx
        $ciBlock = [regex]::Replace($ciBlockRaw, '(?s)--\[\[.*?\]\]', '')
        $entryBlocks = @()
        $depth = 0; $entryStart = -1
        for ($i = 0; $i -lt $ciBlock.Length; $i++) {
            $c = $ciBlock[$i]
            if ($c -eq '{') { $depth++; if ($depth -eq 2) { $entryStart = $i } }
            elseif ($c -eq '}') { if ($depth -eq 2 -and $entryStart -ge 0) { $entryBlocks += $ciBlock.Substring($entryStart, $i - $entryStart + 1); $entryStart = -1 }; $depth-- }
        }
        foreach ($eb in $entryBlocks) {
            $skinKey = Get-Field $eb 'skin_key'
            if (-not $skinKey) { continue }
            $disp    = Get-Field $eb 'display_name'   # literal English
            $matchW  = Get-Field $eb 'matching_weapon'
            $careers = @()
            $cm = [regex]::Match($eb, '(?s)can_wield\s*=\s*\{(.*?)\}')
            if ($cm.Success) { foreach ($qm in [regex]::Matches($cm.Groups[1].Value, '"([^"]+)"')) { $careers += $qm.Groups[1].Value } }
            $eng = $disp; $dsrc = 'literal'; $unres = $false; $reason = $null
            if (-not $eng) {
                $lk = "$($skinKey)_name"
                if ($modLoc.ContainsKey('cosmetics_tweaker') -and $modLoc['cosmetics_tweaker'].ContainsKey($lk)) {
                    $eng = $modLoc['cosmetics_tweaker'][$lk]; $dsrc = 'mod_loc'
                } else { $unres = $true; $dsrc = $null; $reason = 'custom illusion has no literal display_name and no <key>_name loc entry' }
            }
            Add-Entry -Key $skinKey -Kind 'custom_illusion' -DisplayName $eng -DisplayNameSource $dsrc `
                -LocKey "$($skinKey)_name" -ItemType 'weapon_skin' -SlotType 'weapon_skin' `
                -Careers $careers -Source 'cosmetics_tweaker' -RequiredDlc $null `
                -Unresolved $unres -Reason $reason
            $cosCount++
        }
    }
}
Log "      cosmetics custom illusions: $cosCount"

# ============================================================================
# MOD-CREATED: wt weapon_unlock_map (career -> weapon_key access toggles)
# loc keys: unlock_<career>_<weapon> in weapon_tweaker_localization.lua
# These are ACCESS entries (a vanilla weapon made wieldable by another career),
# not new items. kind = wt_unlock; key = "<career>::<weapon>".
# ============================================================================
Log "[6/6] Parsing wt weapon_unlock_map..."
$wtCount = 0
$wtUnlockFile = Join-Path $repoRoot 'weapon_tweaker\scripts\mods\weapon_tweaker\wt_unlock_data.lua'
if (Test-Path $wtUnlockFile) {
    $wtText = Strip-LuaComments (Read-Utf8 $wtUnlockFile)
    $mapM = [regex]::Match($wtText, 'weapon_unlock_map\s*=\s*\{')
    if ($mapM.Success) {
        $openIdx = $wtText.IndexOf('{', $mapM.Index)
        $mapBlock = Get-MatchingBraceBlock $wtText $openIdx
        # Each career line: <career> = { "wk1", "wk2", ... }
        foreach ($cm in [regex]::Matches($mapBlock, '(?m)^\s*([a-z_]+)\s*=\s*\{([^}]*)\}')) {
            $career = $cm.Groups[1].Value
            $weapons = @()
            foreach ($qm in [regex]::Matches($cm.Groups[2].Value, '"([^"]+)"')) { $weapons += $qm.Groups[1].Value }
            foreach ($wk in $weapons) {
                $lk = "unlock_${career}_${wk}"
                $eng = $null; $dsrc = $null; $unres = $true; $reason = 'no unlock_<career>_<weapon> loc entry in weapon_tweaker_localization.lua'
                if ($modLoc.ContainsKey('weapon_tweaker') -and $modLoc['weapon_tweaker'].ContainsKey($lk)) {
                    $eng = $modLoc['weapon_tweaker'][$lk]; $dsrc = 'mod_loc'; $unres = $false; $reason = $null
                }
                Add-Entry -Key "$career::$wk" -Kind 'wt_unlock' -DisplayName $eng -DisplayNameSource $dsrc `
                    -LocKey $lk -ItemType 'weapon_access' -SlotType $null -Careers @($career) `
                    -Source 'weapon_tweaker' -RequiredDlc $null -Unresolved $unres -Reason $reason
                $wtCount++
            }
        }
    }
}
Log "      wt unlock entries: $wtCount"

# ============================================================================
# INGEST IN-GAME NAME DUMP — fill unresolved vanilla entries (Phase 2)
# ============================================================================
# For each entry still `unresolved` whose loc_key the dump knows, fill the
# English + tag display_name_source = "game_dump". Mod-resolved entries are
# never touched (we only fill `unresolved` rows), so the dump can never
# override a literal/mod_loc value. NEVER fabricates — a missing loc_key stays
# unresolved. Idempotent: re-running with the same dump produces identical out.
$gameDumpResolved = 0
if ($nameDump -and $nameDump.pairs.Count -gt 0) {
    foreach ($id in @($script:entries.Keys)) {
        $e = $script:entries[$id]
        if (-not $e.unresolved) { continue }
        $lk = $e.loc_key
        if ($lk -and $nameDump.pairs.ContainsKey($lk)) {
            $e.display_name        = $nameDump.pairs[$lk]
            $e.display_name_source = 'game_dump'
            $e.unresolved          = $false
            $e.reason              = $null
            $gameDumpResolved++
        }
    }
    Log "      ingested name dump: $gameDumpResolved previously-unresolved entries filled (source=game_dump)"
}

# ============================================================================
# EMIT — deterministic sorted ordering for stable diffs
# ============================================================================
Log "Writing outputs..." "Cyan"

# Convert ordered-dictionary rows to PSCustomObjects so Sort/Group can read the
# fields as properties (Group-Object/Sort-Object do NOT treat hashtable keys as
# properties — without this, everything groups into one empty bucket).
$rows = $script:entries.Values | ForEach-Object { [pscustomobject]$_ }
$sorted = $rows | Sort-Object source, kind, key

$outDir = Join-Path $repoRoot 'docs\generated'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# ---- JSON ----
$unresolvedTotalPre = ($sorted | Where-Object { $_.unresolved }).Count
$jsonObj = [ordered]@{
    _banner       = "GENERATED — do not edit; run tools/gen-name-map/gen-name-map.ps1"
    _generated    = $GenDate
    _source       = "vanilla decompile + mod definition tables (see gen-name-map.ps1 header for provenance)"
    _entry_count  = $sorted.Count
    _name_dump    = if ($nameDump) {
        [ordered]@{
            found              = $true
            path               = $nameDump.path
            kind               = $nameDump.kind
            game_build         = $nameDump.build
            pairs_in_dump      = $nameDump.pairs.Count
            vanilla_resolved   = $gameDumpResolved
            vanilla_unresolved = $unresolvedTotalPre
        }
    } else {
        [ordered]@{ found = $false; note = "no in-game name dump found; vanilla strings stay unresolved" }
    }
    entries       = @($sorted)
}
$jsonPath = Join-Path $outDir 'NAME_MAP.generated.json'
$json = $jsonObj | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding $false))

# ---- Markdown ----
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("<!-- GENERATED — do not edit; run tools/gen-name-map/gen-name-map.ps1 -->")
[void]$sb.AppendLine("# Authoritative Name Map (key -> in-game display name)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Generated:** $GenDate &nbsp;|&nbsp; **Entries:** $($sorted.Count)")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("> This file is REGENERATED from ground truth (vanilla decompile + each mod's own")
[void]$sb.AppendLine("> definition tables). **Grep this instead of trusting the legacy hand-maintained**")
[void]$sb.AppendLine("> **catalogs** (ITEM_LIST.md / WEAPON_CATALOG.md / CHARACTER_COSMETIC_CATALOG.md /")
[void]$sb.AppendLine('> _cos_probe.txt). Regenerate: `tools/gen-name-map/gen-name-map.ps1 -GenDate <date>`.')
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Display-name provenance: **literal** = mod hard-coded the English string;")
[void]$sb.AppendLine('**mod_loc** = resolved via the mod''s `_localization.lua`; **runtime_dump** = from')
[void]$sb.AppendLine('`dumps/boon_loc_dump.txt`; **game_dump** = from the in-game name dump (gt_dev')
[void]$sb.AppendLine('`gt_auto_name_dump`, emitted to the console log on keep entry). Entries marked')
[void]$sb.AppendLine("**(unresolved)** have NO trustworthy English source (vanilla strings live in undumped")
[void]$sb.AppendLine(".package bundles) — they are listed honestly with their loc key, never fabricated.")
[void]$sb.AppendLine("")
if ($nameDump) {
    [void]$sb.AppendLine("**Name dump:** ingested $($nameDump.pairs.Count) loc_key->English from ``$($nameDump.kind)`` (game build ``$($nameDump.build)``); filled **$gameDumpResolved** previously-unresolved vanilla entries; **$unresolvedTotalPre** still unresolved. Source: ``$($nameDump.path)``")
} else {
    [void]$sb.AppendLine("**Name dump:** none found — vanilla strings stay unresolved (run gt_dev's ``/gt_dump_names`` in-game, or let ``gt_auto_name_dump`` fire on keep entry, then regenerate).")
}
[void]$sb.AppendLine("")

# group by source then kind
$bySource = $sorted | Group-Object source | Sort-Object Name
foreach ($sg in $bySource) {
    [void]$sb.AppendLine("## source: $($sg.Name)")
    [void]$sb.AppendLine("")
    $byKind = $sg.Group | Group-Object kind | Sort-Object Name
    foreach ($kg in $byKind) {
        $unresN = ($kg.Group | Where-Object { $_.unresolved }).Count
        [void]$sb.AppendLine("### kind: $($kg.Name) ($($kg.Group.Count) entries, $unresN unresolved)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| key | display name | item_type | careers | provenance |")
        [void]$sb.AppendLine("|-----|--------------|-----------|---------|------------|")
        foreach ($e in ($kg.Group | Sort-Object key)) {
            $dn = if ($e.unresolved) { "_(unresolved: $($e.loc_key))_" } else { $e.display_name -replace '\|', '\|' }
            $ca = if ($e.careers -and $e.careers.Count) { ($e.careers -join ', ') } else { '' }
            $prov = if ($e.unresolved) { 'unresolved' } else { $e.display_name_source }
            $it = if ($e.item_type) { $e.item_type } else { '' }
            $dlc = if ($e.required_dlc) { " _(dlc:$($e.required_dlc))_" } else { '' }
            [void]$sb.AppendLine("| ``$($e.key)`` | $dn$dlc | $it | $ca | $prov |")
        }
        [void]$sb.AppendLine("")
    }
}
$mdPath = Join-Path $outDir 'NAME_MAP.generated.md'
[System.IO.File]::WriteAllText($mdPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $false))

# ---- Summary ----
$unresolvedTotal = ($sorted | Where-Object { $_.unresolved }).Count
$resolvedTotal = $sorted.Count - $unresolvedTotal
Log ""
Write-Host "[gen-name-map] OK — wrote $($sorted.Count) entries ($resolvedTotal resolved, $unresolvedTotal unresolved)." -ForegroundColor Green
Write-Host "  JSON: $jsonPath" -ForegroundColor Gray
Write-Host "  MD:   $mdPath" -ForegroundColor Gray
# Per-source/kind breakdown
$sorted | Group-Object source | Sort-Object Name | ForEach-Object {
    $s = $_.Name; $res = ($_.Group | Where-Object { -not $_.unresolved }).Count
    Write-Host ("  {0,-26} {1,5} entries ({2} resolved)" -f $s, $_.Group.Count, $res) -ForegroundColor Gray
}
exit 0
