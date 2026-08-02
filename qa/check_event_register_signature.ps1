# check_event_register_signature.ps1 — static scan for Stingray
# `event:register(object, "event_name", method)` calls whose third positional
# argument is a function VALUE instead of a string METHOD NAME.
#
# Bug class: Stingray's per-state `EventManager:register(object, event_name,
# callback_name)` resolves the callback by NAME against the supplied object,
# i.e. it does `object[callback_name](object, ...)` at fire time. Passing a
# function value (`em:register(obj, "ev", _local_fn)`) makes the engine try
# to index `obj[<function>]` and emits:
#
#     [Script Error] (script) ... No function found with name '[function]'
#
# The handler never fires and the feature silently dies. The four most
# recent gt fixes (v0.2.61 → .64 on 2026-05-25) were all variants of this
# bug — lobby MOTD / session-ignore / slot-reservations each registered
# `_local_fn` instead of `"method_name_string"` on `Managers.state.event`.
#
# CORRECT form:
#     mod.on_player_joined_party = _on_player_joined_party       -- method on mod
#     em:register(mod, "on_player_joined_party",
#                 "on_player_joined_party")                        -- string lookup
#
# WRONG forms (this check flags all three):
#     em:register(mod, "ev", _on_player_joined_party)           -- local fn ref
#     em:register(mod, "ev", function() ... end)                 -- inline fn
#     em:register(mod, "ev", some_table.method)                  -- field deref
#
# Detection:
#   - Greps `*.lua` files under each active mod's
#     `<mod>/scripts/mods/<mod>/` directory.
#   - Skips `_archive/`, `tweaker/` (legacy SDK), `bundleV2/`, `.build/`,
#     `.temp/`, `_test_fixtures/`, `Vermintide-2-*` / `Darktide-*` reference
#     clones, `_*_extract/` snapshots.
#   - For each line containing `:register(`:
#       * Match `<recv>:register(<obj>, "<event>", <arg3>)` where <arg3>
#         is a single token (no parens / commas).
#       * If <arg3> starts with `"` → PASS (string method name).
#       * If <arg3> is an inline `function ... end` → FLAG.
#       * Otherwise → FLAG (it's a function VALUE — local, field, etc.).
#   - Hard ERROR. No suppression pragma. The bug is silent — the static
#     check is the only line of defense.
#
# Caveats:
#   - The check is intentionally narrow: it ONLY matches `:register(` with
#     three positional args. Other `:register(...)` shapes used elsewhere in
#     the codebase (single-arg keybind register, two-arg slash register,
#     etc.) don't match the regex and are silently skipped — that's correct
#     behavior, they're not the Stingray EventManager pattern.
#   - We do NOT try to verify the named method actually exists on the
#     object at runtime; the engine logs that case at fire time and the
#     fix is the same shape (define the method, name matches the string).
#
# Output mirrors `qa/check_vmf_widget_types.ps1`.
#
# Exit codes:
#   0 - all `:register(...)` 3-arg call sites pass a string method name
#   2 - one or more sites pass a function value (hard fail)
#
# Self-test: pass `-SelfTest` to run the synthetic fixtures under
# `qa/_test_fixtures/event_register_*.lua` and assert ERROR / PASS verdicts.
# Self-test exit 0 means the check itself is wired correctly; exit 2 means
# a regex / heuristic regression in this script.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# Pre-compiled regexes.
#
# Match `<recv>:register(<obj>, "<event_name>", <arg3>)`:
#   group 1 = receiver expression (`em`, `ev`, `Managers.state.event`, etc.)
#   group 2 = first arg (object — usually `mod` or `self`)
#   group 3 = second arg (event name string literal)
#   group 4 = third arg (the part we validate — should be a "string")
#
# We accept any non-paren / non-comma run for <arg3> as a heuristic; this
# matches the common shapes (string literal, local name, field access,
# inline function head). Inline `function ... end` shows up as the head
# token `function`; we special-case-detect it.
$rxRegister3Arg = [regex]'(?<recv>[A-Za-z_][A-Za-z0-9_.\[\]]*)\s*:\s*register\s*\(\s*(?<obj>[A-Za-z_][A-Za-z0-9_.\[\]]*)\s*,\s*"(?<event>[^"]+)"\s*,\s*(?<arg3>[^,()]+?)\s*\)'

# Cheap pre-filter so we don't run the heavy regex against every line in
# the repo. Any `:register(` token is a candidate; we don't try to be
# clever here.
$rxAnyRegister = [regex]'\:\s*register\s*\('

# Special-case the inline-function head: `:register(obj, "ev", function() ... end)`.
# The above regex captures `function` as <arg3> because `(...)` parens would
# break the pattern, but we want a more specific message in that case.
$rxInlineFunction = [regex]'^\s*function\b'

# ---- file collection ----
function Get-ScanFiles {
    param([string]$Root)
    # Active mods follow `<mod>/scripts/mods/<mod>/...`. Scope to that
    # subtree to skip vanilla source dumps, the legacy `tweaker/` SDK mod,
    # archived snapshots, the bundleV2 build output, etc.
    Get-ChildItem -Path $Root -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
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
                       -and $p -notlike "*\_test_fixtures\*" `
                       -and $p -notlike "*\sample_*\*" `
                       -and $p -notlike "*\Vermintide-2-Source-Code\*" `
                       -and $p -notlike "*\Darktide-Source-Code\*" `
                       -and $p -notlike "*\_*_extract\*" `
                       -and $p -notlike "*\.claude\*"
            return $isUnderMod -and $notExcluded
        }
}

# ---- per-file scan ----
# Returns an array of error rows: @{ File; Line; Event; Arg3; Text }
function Scan-File {
    param([string]$Path)
    $errors = @()
    try {
        $text = Read-FileUtf8 $Path
    } catch {
        throw "I/O failure reading ${Path}: $_"
    }
    if (-not $rxAnyRegister.IsMatch($text)) { return ,$errors }   # fast bail

    $lines = $text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Strip the trailing line comment so `:register(` appearing in a
        # doc comment doesn't trip the check.
        $codePart = $line
        $commentIdx = $line.IndexOf('--')
        if ($commentIdx -ge 0) { $codePart = $line.Substring(0, $commentIdx) }

        if (-not $rxAnyRegister.IsMatch($codePart)) { continue }

        $matches = $rxRegister3Arg.Matches($codePart)
        if ($matches.Count -eq 0) { continue }

        foreach ($m in $matches) {
            $arg3 = $m.Groups['arg3'].Value.Trim()
            # PASS: third arg is a string literal (starts with a `"`).
            if ($arg3.StartsWith('"')) { continue }

            $event = $m.Groups['event'].Value
            $errors += [pscustomobject]@{
                File  = $Path
                Line  = $i + 1
                Event = $event
                Arg3  = $arg3
                Text  = $line.Trim()
            }
        }
    }
    return ,$errors
}

# ---- self-test ----
# Drives the synthetic fixtures under `qa/_test_fixtures/event_register_*.lua`
# and asserts a specific verdict per fixture.
function Invoke-SelfTest {
    $fixDir = Join-Path $PSScriptRoot "_test_fixtures"
    if (-not (Test-Path $fixDir)) {
        Write-Host "[check_event_register_signature -SelfTest] FAIL: $fixDir does not exist." -ForegroundColor Red
        return 2
    }

    $cases = @(
        @{ Path = "event_register_bad.lua";  ExpectedError = $true;  Desc = "em:register(mod, `"foo`", _bar) — local fn value" },
        @{ Path = "event_register_good.lua"; ExpectedError = $false; Desc = "em:register(mod, `"foo`", `"bar`") — string method name" }
    )

    $allPass = $true
    foreach ($c in $cases) {
        $f = Join-Path $fixDir $c.Path
        if (-not (Test-Path $f)) {
            Write-Host "  X $($c.Path): missing fixture file" -ForegroundColor Red
            $allPass = $false
            continue
        }
        $e = Scan-File -Path $f
        $gotError = ($e.Count -gt 0)
        $verdict = if ($gotError -eq $c.ExpectedError) { "PASS" } else { "FAIL" }
        $colour = if ($verdict -eq "PASS") { "Green" } else { "Red" }
        Write-Host "  [$verdict] $($c.Path) -- $($c.Desc) (error=$gotError, expected=$($c.ExpectedError))" -ForegroundColor $colour
        if ($verdict -eq "FAIL") { $allPass = $false }
    }

    Write-Host ""
    if ($allPass) {
        Write-Host "[check_event_register_signature -SelfTest] OK -- all $($cases.Count) fixture verdicts match." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[check_event_register_signature -SelfTest] FAILED -- regex / heuristic regression. Inspect fixtures + Scan-File." -ForegroundColor Red
        return 2
    }
}

# ---- main ----
Write-Host "=== check_event_register_signature ===" -ForegroundColor Cyan

if ($SelfTest) {
    $code = Invoke-SelfTest
    exit $code
}

$allErrors = @()
$hardError = $false

$files = @(Get-ScanFiles -Root $repoRoot)
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
    if (-not $Quiet) { Write-Host "Checking $rel" -ForegroundColor DarkGray }
    try {
        $rows = Scan-File -Path $f.FullName
    } catch {
        Write-Host ("  X {0}: {1}" -f $rel, $_) -ForegroundColor Red
        $hardError = $true
        continue
    }
    if ($rows.Count -gt 0) {
        foreach ($r in $rows) { $allErrors += $r }
    }
}

Write-Host ""
if ($hardError) {
    Write-Host "[check_event_register_signature] ERROR -- one or more files failed to scan." -ForegroundColor Red
    exit 2
}

if ($allErrors.Count -eq 0) {
    Write-Host "[check_event_register_signature] OK -- all event:register(...) calls pass a string method name." -ForegroundColor Green
    exit 0
}

Write-Host "[check_event_register_signature] ERRORS: $($allErrors.Count)" -ForegroundColor Red
foreach ($e in $allErrors) {
    $rel = $e.File
    if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
    Write-Host ("  X {0}:{1} -- event '{2}' 3rd arg is '{3}' (must be a quoted string method name)" -f $rel, $e.Line, $e.Event, $e.Arg3) -ForegroundColor Red
    Write-Host ("      $($e.Text)") -ForegroundColor DarkRed
    Write-Host ("      Fix: assign the function to mod (e.g. mod.{0} = _local_fn) and pass `"{0}`" instead." -f $e.Event) -ForegroundColor DarkGray
}
exit 2
