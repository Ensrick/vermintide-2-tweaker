# ============================================================================
# check_name_integrity.ps1 — localization-integrity validator
# ============================================================================
#
# Standalone (NOT wired into the launcher's blocking upload preflight — by
# design, see report). Mirrors qa/check_localization.ps1 conventions: same
# -RepoRoot param, same loc/data parsers, exit codes 0 = clean, 1 = warnings
# only, 2 = errors found.
#
# THREE CHECKS:
#   (1) ERROR — every `setting_id` in each <mod>_data.lua has a matching loc
#       entry in that mod's <mod>_localization.lua. (The red-tooltip class.)
#   (2) ERROR — every display_name / item_type / description a mod ASSIGNS in
#       its Lua to a LITERAL STRING KEY resolves to a real loc key: the mod's
#       own loc table, OR any mod loc table, OR a known vanilla loc key, OR is
#       a plausible literal English string. Resolves in none -> ERROR.
#       (item_type matters: `Localize(item_data.item_type)` is a real render
#       path per CLAUDE.md.) Dynamic concat assignments (e.g.
#       `display_name = key .. "_name"`) are STRUCTURAL and skipped — they
#       can't be resolved to a single key statically.
#   (3) WARN  — loc keys defined in a mod's <mod>_localization.lua but
#       referenced nowhere in that mod's Lua / data files. (Some are referenced
#       dynamically, so WARN not ERROR.)
#
# Known vanilla loc-key inventory is derived from the decompiled IML +
# career_settings display_name fields (the loc KEYS exist in source even though
# the English strings do not). This lets check #2 accept references like
# item_type = "weapon_skin" or display_name = "information_weapon_skin".
#
# Self-test: -SelfTest plants a missing-loc-entry (proves #1 fires) and an
# unresolvable display_name (proves #2 fires) in a temp mod tree, runs the
# checks against it, and asserts both ERRORs are raised.
#
# USAGE
#   .\qa\check_name_integrity.ps1
#       -RepoRoot <repo>   (default: parent of qa/)
#       -VtSrc    <path>   (default: ..\..\Vermintide-2-Source-Code)
#       -Quiet
#       -SelfTest          run the planted-fault self-test and exit
# ============================================================================

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [string]$VtSrc    = (Join-Path $PSScriptRoot "..\..\Vermintide-2-Source-Code"),
    [switch]$Quiet,
    [switch]$SelfTest,
    [switch]$UpdateBaseline
)

$ErrorActionPreference = "Stop"

function Read-Utf8([string]$p) { return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8) }
function Log($msg, $color = "DarkGray") { if (-not $Quiet) { Write-Host $msg -ForegroundColor $color } }

# ---- ratchet baseline (issue #429) ----
# CI checks out ONLY this repo, so the decompiled Vermintide-2-Source-Code is
# absent and check #2's source-derived vanilla-loc-key resolution is incomplete — which surfaces
# MORE errors in CI than locally (a mod's reference to a real vanilla key looks
# unresolvable). A small committed oracle records source-proven vanilla keys used
# by this repository, while the baseline freezes the remaining no-VtSrc superset so
# the same file covers both environments: locally (VtSrc present) fewer errors
# fire, all a subset of the baseline; in CI the full superset fires and still
# matches. Only NEW errors (a genuinely typo'd/orphan key that resolves in no
# environment) fail the gate. Regenerate ONLY with -UpdateBaseline, which forces
# the no-VtSrc view so the committed baseline always matches CI regardless of
# whether the maintainer has the sibling repo checked out.
$baselinePath = Join-Path $PSScriptRoot "baselines\name_integrity.json"
$vanillaOraclePath = Join-Path $PSScriptRoot "oracles\vanilla_loc_keys.json"

# Check #2 diagnoses the unresolved localization value; its source path is
# evidence, not identity. Keep the path in diagnostics, but exclude it from the
# ratchet key so a module extraction cannot manufacture a new localization bug.
function Normalize-Sig([string]$s) {
    $normalized = $s.Replace('\', '/')
    if ($normalized -match '^\[check2\]') {
        $normalized = $normalized -replace ' \([^()]+\)(?= resolves in no loc table)', ''
    }
    return $normalized
}

function Load-NameIntegrityBaseline {
    if (-not (Test-Path $baselinePath)) { return @{} }
    try { $j = Get-Content $baselinePath -Raw | ConvertFrom-Json } catch { return @{} }
    $set = @{}
    foreach ($e in $j.errors) { $set[(Normalize-Sig $e)] = $true }
    return $set
}

function Load-CommittedVanillaLocKeys {
    $keys = @{}
    if (-not (Test-Path $vanillaOraclePath)) { return $keys }

    $j = Get-Content $vanillaOraclePath -Raw | ConvertFrom-Json
    if ($j.schema_version -ne 1 -or -not $j.source_commit -or -not $j.keys) {
        throw "Invalid committed vanilla loc-key oracle: $vanillaOraclePath"
    }
    foreach ($entry in $j.keys) {
        $key = [string]$entry.key
        if ($key -notmatch '^[a-z_][a-z0-9_]*$' -or -not $entry.evidence) {
            throw "Invalid committed vanilla loc-key entry: $($entry | ConvertTo-Json -Compress)"
        }
        if ($keys.ContainsKey($key)) { throw "Duplicate committed vanilla loc key: $key" }
        $keys[$key] = $true
    }
    return $keys
}

# --- loc parser (same three patterns as check_localization.ps1) ---
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

# --- data setting_id parser ---
function Parse-DataSettingIds([string]$path) {
    $ids = @{}
    if (-not (Test-Path $path)) { return $ids }
    $text = Read-Utf8 $path
    # Skip concat-fragment setting_ids (`setting_id = "mut_" .. id`) — the full
    # id is built at runtime and its loc entries are dynamic.
    foreach ($m in [regex]::Matches($text, 'setting_id\s*=\s*"([^"]+)"([ \t]*\.\.)?')) {
        if ($m.Groups[2].Success) { continue }
        $ids[$m.Groups[1].Value] = $true
    }
    return $ids
}

# --- known vanilla loc-key inventory (display_name + item_type loc keys from
#     the decompiled IML + careers). These KEYS exist even though their English
#     strings don't, so a mod referencing one IS valid. ---
function Build-VanillaLocKeys([string]$vtSrc) {
    # The English STRINGS for vanilla loc keys are NOT in the decompiled source
    # (they live in undumped .package bundles). But the loc KEYS themselves are
    # referenced all over the settings/UI tables as display_name/description/
    # tooltip/title values. We harvest those quoted snake_case identifiers so
    # check #2 accepts a mod's reference to a real vanilla key (e.g.
    # item_type = "weapon_skin", display_name = "interact_open_inventory_chest").
    # Anything still unmatched after this is the genuinely-suspicious set.
    $keys = @{}
    if (-not (Test-Path $vtSrc)) { return $keys }
    $scanDirs = @(
        (Join-Path $vtSrc 'scripts\settings'),
        (Join-Path $vtSrc 'scripts\ui')
    )
    # Fields whose VALUE is conventionally a loc key.
    $fieldRx = [regex]'(?m)\b(?:display_name|description|tooltip|title|item_type|information_text|text|header|sub_header|name_text|desc)\s*=\s*"([a-z_][a-z0-9_]*)"'
    foreach ($d in $scanDirs) {
        if (-not (Test-Path $d)) { continue }
        foreach ($f in (Get-ChildItem -Path $d -Filter '*.lua' -Recurse -File -ErrorAction SilentlyContinue)) {
            $text = Read-Utf8 $f.FullName
            foreach ($m in $fieldRx.Matches($text)) { $keys[$m.Groups[1].Value] = $true }
        }
    }
    return $keys
}

# --- mod-lua literal display_name/item_type/description assignments (check #2) ---
# Returns array of @{ field; value; isLiteralString } — only STRING-LITERAL
# right-hand sides (skips concat / variable / function forms).
function Parse-AssignedNames([string]$modDir) {
    $out = @()
    $luaFiles = Get-ChildItem -Path (Join-Path $modDir 'scripts') -Filter '*.lua' -Recurse -File -ErrorAction SilentlyContinue
    foreach ($lf in $luaFiles) {
        # skip the loc + data files themselves (they DEFINE, not consume)
        if ($lf.Name -like '*_localization.lua' -or $lf.Name -like '*_data.lua') { continue }
        $text = Read-Utf8 $lf.FullName
        # Check 2 owns values that can reach a player-facing Localize call. Runtime
        # truth-table fixtures sometimes use item-shaped tables only as classifier
        # inputs; require an explicit annotation for those non-rendered rows. Strip
        # comments as well so documentation such as `display_name = "example"`
        # cannot become a false localization failure.
        $text = [regex]::Replace(
            $text,
            '(?m)^.*name-integrity:\s*non-rendered-test-data.*(?:\r?\n|$)',
            ''
        )
        $text = [regex]::Replace($text, '(?s)--\[\[.*?\]\]', '')
        $text = [regex]::Replace($text, '(?m)--[^\r\n]*', '')
        # Capture assignment + a trailing window so we can tell if the string is a
        # CONCAT FRAGMENT (`display_name = "foo_" .. id`). Concat fragments are NOT
        # complete keys and must be skipped — the full key is built at runtime.
        foreach ($m in [regex]::Matches($text, '(?m)\b(display_name|item_type|description)\s*=\s*"([^"]+)"([ \t]*\.\.)?')) {
            if ($m.Groups[3].Success) { continue }   # value is followed by `..` -> concat fragment
            $out += [ordered]@{ field = $m.Groups[1].Value; value = $m.Groups[2].Value; file = $lf.FullName }
        }
    }
    return $out
}

# --- mod-lua + data reference scan (check #3 orphan detection) ---
function Get-ModReferencedTokens([string]$modDir) {
    # Returns @{ exact = hashtable(token->true); fragments = string[] } where
    # `fragments` are string-literal pieces adjacent to a `..` concat operator
    # (e.g. "disable_boon_" in `"disable_boon_" .. boon_id`, or "_tooltip" in
    # `sid .. "_tooltip"`). ct/cim/wt build many setting_ids/loc keys by concat,
    # so a key is "referenced" if a fragment is a prefix or suffix of it.
    $exact = @{}
    $fragments = @{}
    $files = Get-ChildItem -Path (Join-Path $modDir 'scripts') -Include '*.lua' -Recurse -File -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        if ($f.Name -like '*_localization.lua') { continue }  # don't count its own definitions as references
        $text = Read-Utf8 $f.FullName
        foreach ($m in [regex]::Matches($text, '"([A-Za-z_][A-Za-z0-9_]*)"')) { $exact[$m.Groups[1].Value] = $true }
        # concat fragments: "..." ..   AND   .. "..."
        foreach ($m in [regex]::Matches($text, '"([A-Za-z_][A-Za-z0-9_]*)"\s*\.\.')) { $fragments[$m.Groups[1].Value] = $true }
        foreach ($m in [regex]::Matches($text, '\.\.\s*"([A-Za-z_][A-Za-z0-9_]*)"')) { $fragments[$m.Groups[1].Value] = $true }
    }
    return @{ exact = $exact; fragments = @($fragments.Keys) }
}

function Get-ModDirForLocFile([string]$filePath) {
    $dir = Split-Path $filePath -Parent
    for ($i = 0; $i -lt 3; $i++) { $dir = Split-Path $dir -Parent }
    return $dir
}

# ============================================================================
# CORE: run all three checks against a set of mod dirs. Returns @{errors;warnings}.
# ============================================================================
# Load the generated NAME_MAP as an additional "known resolvable" oracle. The
# generator parses each mod's RUNTIME name-registration tables (cwv
# _display_names, cosmetics _custom_loc, etc.) that a static loc-file scan can't
# see. So a value that maps to a generated key/loc_key/item_type — or is a
# <known_key>_name / _skin_name / _description derivative — is genuinely
# resolvable at runtime, not a typo. Returns @{ exact=hashtable; keys=string[] }.
function Load-GeneratedOracle([string]$repoRoot) {
    $exact = @{}; $modKeys = @{}
    $p = Join-Path $repoRoot 'docs\generated\NAME_MAP.generated.json'
    if (-not (Test-Path $p)) { return @{ exact = $exact; keys = @() } }
    try { $j = Get-Content $p -Raw | ConvertFrom-Json } catch { return @{ exact = $exact; keys = @() } }
    foreach ($e in $j.entries) {
        if ($e.source -eq 'vanilla') { continue }   # only mod-registered runtime names count here
        if ($e.loc_key)   { $exact[$e.loc_key] = $true }
        if ($e.item_type) { $exact[$e.item_type] = $true }
        if ($e.key)       { $modKeys[$e.key] = $true }
    }
    return @{ exact = $exact; keys = @($modKeys.Keys) }
}

function Invoke-IntegrityChecks {
    param([string]$repoRoot, [hashtable]$vanillaKeys, [string[]]$onlyMods = $null, [hashtable]$oracle = $null)

    $errors = @(); $warnings = @()
    if (-not $oracle) { $oracle = @{ exact = @{}; keys = @() } }

    $locFiles = Get-ChildItem -Path $repoRoot -Filter '*_localization.lua' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $p = $_.FullName
            $p -notlike '*\_archive\*' -and $p -notlike '*\bundleV2\*' -and $p -notlike '*\.build\*' `
                -and $p -notlike '*\.temp\*' -and $p -notlike '*\tweaker\*' -and $p -notlike '*\sample_*\*'
        }

    # aggregate all mod loc keys (for cross-mod resolution in check #2)
    $allModLocKeys = @{}
    $modLocMap = @{}    # modName -> @{ locPath; locKeys(hashtable) }
    foreach ($lf in $locFiles) {
        $modDir = Get-ModDirForLocFile $lf.FullName
        $modName = Split-Path $modDir -Leaf
        $parsed = Parse-LocFile $lf.FullName
        $modLocMap[$modName] = @{ dir = $modDir; locPath = $lf.FullName; keys = $parsed }
        foreach ($k in $parsed.Keys) { $allModLocKeys[$k] = $true }
    }

    foreach ($modName in ($modLocMap.Keys | Sort-Object)) {
        if ($onlyMods -and ($modName -notin $onlyMods)) { continue }
        $entry = $modLocMap[$modName]
        $modDir = $entry.dir
        $loc = $entry.keys
        Log "Checking $modName"

        # ---- CHECK 1: every setting_id has a loc entry (ERROR) ----
        $dataFile = Get-ChildItem -Path (Join-Path $modDir 'scripts') -Filter '*_data.lua' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($dataFile) {
            $ids = Parse-DataSettingIds $dataFile.FullName
            foreach ($id in ($ids.Keys | Sort-Object)) {
                if (-not $loc.ContainsKey($id)) {
                    $errors += "[check1] ${modName}: setting_id '$id' in $($dataFile.Name) has NO loc entry in $(Split-Path $entry.locPath -Leaf)"
                }
            }
        }

        # ---- CHECK 2: assigned literal display_name/item_type/description resolves (ERROR) ----
        foreach ($a in (Parse-AssignedNames $modDir)) {
            $v = $a.value
            $resolves =
                $loc.ContainsKey($v) -or `
                $allModLocKeys.ContainsKey($v) -or `
                $vanillaKeys.ContainsKey($v) -or `
                $oracle.exact.ContainsKey($v)
            # Runtime-registered name derivatives: <known mod key>_name /
            # _skin_name / _description, or the bare key used as item_type.
            if (-not $resolves) {
                foreach ($mk in $oracle.keys) {
                    if ($v -eq $mk -or $v -eq "${mk}_name" -or $v -eq "${mk}_skin_name" -or $v -eq "${mk}_description") { $resolves = $true; break }
                }
            }
            if (-not $resolves) {
                # A value containing a space / uppercase / punctuation is a literal
                # English display string (mods hard-code these), which is VALID.
                # NOTE: -cmatch (case-SENSITIVE) — plain -match treats A-Z as
                # case-insensitive in PowerShell, which would wrongly accept any
                # lowercase loc-key-shaped value as "English".
                $looksLikeLiteralEnglish = ($v -cmatch '[ A-Z&]')
                if (-not $looksLikeLiteralEnglish) {
                    $rel = $a.file.Substring($modDir.Length).TrimStart('\')
                    $errors += "[check2] ${modName}: $($a.field) = `"$v`" ($rel) resolves in no loc table (mod/any-mod/vanilla) and is not a literal English string"
                }
            }
        }

        # ---- CHECK 3: orphan loc keys (WARN) ----
        $refsObj = Get-ModReferencedTokens $modDir
        $refs = $refsObj.exact
        $frags = $refsObj.fragments
        foreach ($k in ($loc.Keys | Sort-Object)) {
            # VMF auto-references: setting_id keys + their _tooltip/_description
            # siblings are consumed by VMF implicitly. A loc key is referenced if
            # it appears as a quoted token, its suffix-stripped base does, OR it
            # is built by string concat (a collected fragment is its prefix/suffix).
            if ($refs.ContainsKey($k)) { continue }
            # suffix-stripped base (foo_tooltip / foo_description / foo_name -> foo)
            $base = $k -replace '_(tooltip|description|name|skin_name)$', ''
            if ($refs.ContainsKey($base)) { continue }
            if ($k -eq 'mod_description' -or $k -eq 'mod_name') { continue }  # VMF reserved
            # concat-built: a fragment is a prefix or suffix of this key (and the
            # base, to cover `prefix .. id .. "_tooltip"`).
            $builtByConcat = $false
            foreach ($fr in $frags) {
                if ($fr.Length -lt 4) { continue }   # ignore tiny fragments to avoid noise
                if ($k.StartsWith($fr) -or $k.EndsWith($fr) -or $base.StartsWith($fr) -or $base.EndsWith($fr)) { $builtByConcat = $true; break }
            }
            if ($builtByConcat) { continue }
            $warnings += "[check3] ${modName}: loc key '$k' defined in $(Split-Path $entry.locPath -Leaf) but referenced nowhere in mod Lua/data (may be dynamic)"
        }
    }

    return @{ errors = $errors; warnings = $warnings }
}

# ============================================================================
# SELF-TEST — plant faults, prove checks 1 + 2 fire
# ============================================================================
function Invoke-SelfTest {
    Write-Host "[check_name_integrity] SELF-TEST" -ForegroundColor Cyan
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nameint_selftest_" + [guid]::NewGuid().ToString("N").Substring(0,8))
    $modName = 'selftest_mod'
    $scriptsDir = Join-Path $tmp "$modName\scripts\mods\$modName"
    New-Item -ItemType Directory -Force -Path $scriptsDir | Out-Null
    try {
        # _localization.lua — deliberately MISSING the 'planted_missing_setting' key,
        # and missing the planted unresolvable display_name's key.
        $loc = @"
return {
    mod_description = { en = "Self-test mod." },
    present_setting = { en = "Present Setting" },
}
"@
        [System.IO.File]::WriteAllText((Join-Path $scriptsDir "${modName}_localization.lua"), $loc, (New-Object System.Text.UTF8Encoding $false))

        # _data.lua — references 'planted_missing_setting' that has NO loc entry (fires CHECK 1).
        $data = @"
return {
    name = "selftest_mod",
    settings = {
        widgets = {
            { setting_id = "present_setting", type = "checkbox", default_value = true },
            { setting_id = "planted_missing_setting", type = "checkbox", default_value = true },
        },
    },
}
"@
        [System.IO.File]::WriteAllText((Join-Path $scriptsDir "${modName}_data.lua"), $data, (New-Object System.Text.UTF8Encoding $false))

        # main lua — assigns a display_name to an unresolvable, non-literal-English key (fires CHECK 2).
        $main = @"
local entry = {}
entry.display_name = "planted_unresolvable_locless_key"
entry.item_type = "weapon_skin"  -- vanilla loc key, should NOT error
entry.description = "planted_annotated_fixture_key" -- name-integrity: non-rendered-test-data
-- display_name = "planted_commented_example_key"
"@
        [System.IO.File]::WriteAllText((Join-Path $scriptsDir "${modName}.lua"), $main, (New-Object System.Text.UTF8Encoding $false))

        $committedKeys = Load-CommittedVanillaLocKeys
        $vanillaKeys = @{ weapon_skin = $true }   # minimal vanilla key set for the test
        foreach ($key in $committedKeys.Keys) { $vanillaKeys[$key] = $true }
        $res = Invoke-IntegrityChecks -repoRoot $tmp -vanillaKeys $vanillaKeys -onlyMods @($modName)

        $check1Fired = ($res.errors | Where-Object { $_ -match '\[check1\].*planted_missing_setting' }).Count -gt 0
        $check2Fired = ($res.errors | Where-Object { $_ -match '\[check2\].*planted_unresolvable_locless_key' }).Count -gt 0
        $check2FalsePos = ($res.errors | Where-Object { $_ -match '\[check2\].*weapon_skin' }).Count -gt 0
        $annotatedFalsePos = ($res.errors | Where-Object { $_ -match 'planted_annotated_fixture_key|planted_commented_example_key' }).Count -gt 0
        $movedCheck2MatchesBaseline = (Normalize-Sig '[check2] selftest_mod: display_name = "same_key" (scripts/mods/selftest_mod/old.lua) resolves in no loc table (mod/any-mod/vanilla) and is not a literal English string') -eq `
            (Normalize-Sig '[check2] selftest_mod: display_name = "same_key" (scripts/mods/selftest_mod/new.lua) resolves in no loc table (mod/any-mod/vanilla) and is not a literal English string')
        $offlineOracleComplete = @(
            'return_to_game_button_name',
            'options_menu_button_name',
            'quit_menu_button_name'
        ) | ForEach-Object { $committedKeys.ContainsKey($_) } | Where-Object { -not $_ } | Measure-Object | Select-Object -ExpandProperty Count

        function Write-SelfTestResult([string]$label, [bool]$passed) {
            $result = if ($passed) { 'PASS' } else { 'FAIL' }
            $color = if ($passed) { 'Green' } else { 'Red' }
            Write-Host ("{0}{1}" -f $label, $result) -ForegroundColor $color
        }

        Write-Host ""
        Write-SelfTestResult "  CHECK 1 (missing setting_id loc entry) fired:        " $check1Fired
        Write-SelfTestResult "  CHECK 2 (unresolvable display_name) fired:           " $check2Fired
        Write-SelfTestResult "  CHECK 2 did NOT false-positive on vanilla item_type: " (-not $check2FalsePos)
        Write-SelfTestResult "  CHECK 2 ignores annotated fixtures and comments:       " (-not $annotatedFalsePos)
        Write-SelfTestResult "  Offline vanilla oracle has source-proven menu keys:    " ($offlineOracleComplete -eq 0)
        Write-SelfTestResult "  CHECK 2 ratchet survives source-file moves:             " $movedCheck2MatchesBaseline
        Write-Host ""
        Write-Host "  Raised errors:" -ForegroundColor DarkGray
        foreach ($e in $res.errors) { Write-Host "    - $e" -ForegroundColor DarkGray }

        if ($check1Fired -and $check2Fired -and -not $check2FalsePos -and -not $annotatedFalsePos -and $offlineOracleComplete -eq 0 -and $movedCheck2MatchesBaseline) {
            Write-Host "[check_name_integrity] SELF-TEST PASSED" -ForegroundColor Green
            return 0
        } else {
            Write-Host "[check_name_integrity] SELF-TEST FAILED" -ForegroundColor Red
            return 2
        }
    }
    finally {
        # single-path cleanup per repo safety rule (no -Recurse -Force on broad paths);
        # this is a self-created temp tree under the OS temp dir.
        if (Test-Path $tmp) { [System.IO.Directory]::Delete($tmp, $true) }
    }
}

# ============================================================================
# MAIN
# ============================================================================
if ($SelfTest) { exit (Invoke-SelfTest) }

$repoRoot = (Resolve-Path $RepoRoot).Path

# The oracle (docs/generated/NAME_MAP.generated.json) is committed, so it loads
# identically in CI and locally — always use it.
$oracle = Load-GeneratedOracle $repoRoot
if ($oracle.keys.Count -gt 0) { Log "Loaded $($oracle.keys.Count) mod keys from NAME_MAP.generated.json as runtime-name oracle." }
else { Log "NOTE: docs/generated/NAME_MAP.generated.json not found — runtime-registered mod names (cwv/cosmetics) may over-report in check #2. Run gen-name-map.ps1 first." "Yellow" }

# --- -UpdateBaseline: freeze the no-VtSrc SUPERSET and exit (explicit only) ---
# We retain the committed source-proven oracle but omit the optional source tree,
# so the baseline is the CI-matching superset on every maintainer machine.
$committedVanillaKeys = Load-CommittedVanillaLocKeys
Log "Loaded $($committedVanillaKeys.Count) source-proven vanilla loc keys from the committed offline oracle."
if ($UpdateBaseline) {
    $res = Invoke-IntegrityChecks -repoRoot $repoRoot -vanillaKeys $committedVanillaKeys -oracle $oracle
    $sigs = @($res.errors | ForEach-Object { Normalize-Sig $_ } | Sort-Object -Unique)
    $payload = [ordered]@{
        '_comment' = "Frozen check_name_integrity ERRORS. Generated in the no-decompiled-source (CI) view — the SUPERSET — so it matches both CI and local runs. Regenerate ONLY with check_name_integrity.ps1 -UpdateBaseline. The gate fails only on NEW errors (keys that resolve in NO environment). Issue #429."
        'generated' = (Get-Date).ToString('yyyy-MM-dd')
        'errors'   = $sigs
    }
    $dir = Split-Path $baselinePath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $baselinePath -Encoding utf8
    Write-Host "[check_name_integrity] baseline UPDATED: $($sigs.Count) error(s) frozen -> $baselinePath" -ForegroundColor Cyan
    foreach ($s in $sigs) { Write-Host "  frozen  $s" -ForegroundColor DarkGray }
    exit 0
}

$vanillaKeys = @{}
foreach ($key in $committedVanillaKeys.Keys) { $vanillaKeys[$key] = $true }
if (Test-Path $VtSrc) {
    $sourceVanillaKeys = Build-VanillaLocKeys (Resolve-Path $VtSrc).Path
    foreach ($key in $sourceVanillaKeys.Keys) { $vanillaKeys[$key] = $true }
    Log "Loaded $($vanillaKeys.Count) known vanilla loc keys for check #2 resolution (committed + source checkout)."
} else {
    Log "WARNING: Vermintide-2-Source-Code not at $VtSrc — using the committed vanilla-key oracle plus the frozen no-source baseline." "Yellow"
}

$result = Invoke-IntegrityChecks -repoRoot $repoRoot -vanillaKeys $vanillaKeys -oracle $oracle

# Always evaluate the blocking ratchet in the same source-less view as CI. The
# committed oracle remains active, so source-proven keys stay resolved in both
# environments while optional source-only discoveries cannot hide baseline drift.
$ratchetErrors = $result.errors
if (Test-Path $VtSrc) {
    $ratchetResult = Invoke-IntegrityChecks -repoRoot $repoRoot -vanillaKeys $committedVanillaKeys -oracle $oracle
    $ratchetErrors = $ratchetResult.errors
}

# Split errors against the frozen baseline: only NEW errors block.
$baseline = Load-NameIntegrityBaseline
$newErrors = @()
$baselinedCount = 0
foreach ($e in $ratchetErrors) {
    if ($baseline.ContainsKey((Normalize-Sig $e))) { $baselinedCount++ } else { $newErrors += $e }
}

Write-Host ""
if ($baselinedCount -gt 0) {
    Write-Host "[check_name_integrity] $baselinedCount pre-existing error(s) are BASELINED (frozen in qa/baselines/name_integrity.json); non-blocking. (baselined: $baselinedCount)" -ForegroundColor DarkCyan
}
if ($result.warnings.Count -gt 0) {
    Write-Host "[check_name_integrity] WARNINGS ($($result.warnings.Count)):" -ForegroundColor Yellow
    foreach ($w in $result.warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
}
if ($newErrors.Count -gt 0) {
    Write-Host "[check_name_integrity] NEW ERRORS ($($newErrors.Count)) — not in baseline; fix, or regenerate the baseline with -UpdateBaseline only after maintainer triage:" -ForegroundColor Red
    foreach ($e in $newErrors) { Write-Host "  X $e" -ForegroundColor Red }
    exit 2
}
if ($result.warnings.Count -gt 0) { exit 1 }
Write-Host "[check_name_integrity] OK — no new integrity errors (baselined: $baselinedCount)." -ForegroundColor Green
exit 0
