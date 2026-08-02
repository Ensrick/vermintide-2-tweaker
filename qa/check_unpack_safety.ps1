# check_unpack_safety.ps1 — static scan for unsafe unpack() call sites in
# active-mod Lua files.
#
# Bug class: Lua 5.1's `#table` is undefined for arrays with nil holes — it
# does a binary boundary search over the array part, so for `{1, nil, 2, nil, 3}`
# the result could be 1, 3, or 5 depending on the implementation. `unpack(t, i)`
# without an explicit `j` arg defaults to `j = #t` and therefore truncates
# non-deterministically when the array carries nils after position `i`.
#
# Correct pattern: capture the real count via `select("#", ...)` from the source
# variadic and pass `j` explicitly:
#     local results = { ... }
#     local n = select("#", ...)
#     return unpack(results, 1, n)
#
# See VMF_RECIPES.md § 2a, CLAUDE.md "engine quirks" bullet, PROJECT_STANDARDS
# § 9.9, weapon_tweaker/_safe_hook.lua header.
#
# Burned in weapon_tweaker v0.12.77 / .78 (2026-05-25) — three version bumps
# through v0.12.79 finally landed on `unpack(results, 2, n)`. Issue #36.
#
# Detection:
#   - Greps `*.lua` files under each active mod's `scripts/` directory.
#   - Skips `tweaker/` (legacy / frozen), `_archive/`, `_*_extract/`,
#     `Vermintide-2-*` reference clones, `bundleV2/`, `.build/`, `.temp/`.
#   - Skips `unpack(` that appears only inside a `--[[ ... ]]` block comment
#     (tracks open/close across lines, incl. `--[=[ ... ]=]` long brackets) or
#     inside a string literal (interiors blanked before matching). This kills
#     the two documented false-positive classes (Issue #51): prose in
#     `_safe_hook.lua`'s docstring, and `unpack(args)` inside a marker/error
#     string. Genuine `unpack()` outside comments/strings is unaffected.
#   - For each remaining line containing `unpack(`:
#       * 1-arg form `unpack(t)`          -> suspicious
#       * 2-arg form `unpack(t, i)`       -> suspicious
#       * 3-arg form `unpack(t, i, n)`    -> PASS (explicit `j`)
#   - For each suspicious hit, scan the ~5 lines above for a `select("#", ...)`
#     capture (indicating the author knew about the gotcha) and the same line
#     for an inline `-- unpack-safe` pragma or any of these audit annotations:
#       -- single-return
#       -- no nil holes
#       -- safe
#       -- audited
#       -- defensible-as-is
#   - Otherwise emit a WARN row.
#
# Output mirrors `qa/check_versions.ps1` / `qa/check_cfg.ps1`.
#
# Exit codes:
#   0 - all call sites either explicit-j or annotated
#   1 - one or more WARNings emitted
#   2 - hard error (file read failure, unexpected I/O, etc.)
#
# Self-test: pass `-SelfTest` to run the synthetic fixtures under
# `qa/_test_fixtures/` and assert WARN / PASS verdicts. Self-test exit 0
# means the check itself is wired correctly; failures point at regressions
# in this script's regex / context heuristics.

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

# Pre-compiled regexes — pulled out of the hot loop.
# We don't try to be a full Lua parser. The arg-count heuristic relies on
# matching `unpack(<arg>[, <arg>[, <arg>]])` where each <arg> is a
# non-comma, non-paren-containing token. That misses unpack calls whose
# args contain nested parens / commas (e.g. `unpack(t, f(x), n)`), but
# every burn-history site in this repo uses simple arg forms; we accept
# the false-negative on exotic expressions in exchange for keeping the
# regex sane.
$rxUnpackAny     = [regex]'\bunpack\s*\('
# Match (and consume) the full call up to the closing paren that's at the
# same nesting level — but only for arg lists with NO nested parens. We
# match a balanced trivial form: `unpack(<a>[, <b>[, <c>]])` where each
# <a>/<b>/<c> contains neither `,` nor `(` nor `)`.
$rxUnpack1Arg    = [regex]'\bunpack\s*\(\s*[^,()]+\s*\)'
$rxUnpack2Arg    = [regex]'\bunpack\s*\(\s*[^,()]+\s*,\s*[^,()]+\s*\)'
$rxUnpack3Arg    = [regex]'\bunpack\s*\(\s*[^,()]+\s*,\s*[^,()]+\s*,\s*[^,()]+\s*\)'
$rxSelectHash    = [regex]'\bselect\s*\(\s*"#"'
# Annotations that suppress the warning. All accepted on the same line as
# the unpack call (inline) OR on the line directly above (own-line comment).
# The `-- unpack-safe` pragma is the canonical hard-override; the others are
# softer audit annotations carried over from PROJECT_STANDARDS § 9.9.
$rxSafePragma    = [regex]'--\s*(unpack-safe|single-return|no\s+nil\s+holes|safe\b|audited|defensible-as-is)'

# ---- file collection ----
function Get-ScanFiles {
    param([string]$Root)
    # Active mods follow `<mod>/scripts/...` layout. We scope to that
    # subtree to skip both top-level scaffolding lua and unrelated repos
    # (Vermintide-2-Source-Code, Darktide-Source-Code, extracted-mod dumps).
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

# ---- per-file scan ----
# Returns an array of warning rows: @{ File; Line; Text }
function Scan-File {
    param([string]$Path)
    $warnings = @()
    try {
        $text = Read-FileUtf8 $Path
    } catch {
        throw "I/O failure reading ${Path}: $_"
    }
    if (-not $rxUnpackAny.IsMatch($text)) { return ,$warnings }   # fast bail

    $lines = $text -split "`r?`n"
    $inBlock = $false          # inside a --[[ ... ]] (or --[=[ ... ]=]) block comment
    $blockCloser = ""          # the ]=*] token that closes the currently-open block
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $work = $line          # portion of the line that is still live code

        # ---- (0) resume from an already-open block comment ----
        # Lines fully inside a --[[ ... ]] docstring carry no live code (this is
        # the _safe_hook.lua false-positive class: prose that mentions unpack()).
        if ($inBlock) {
            $ci = $work.IndexOf($blockCloser)
            if ($ci -lt 0) { continue }                          # whole line still inside the block
            $work = $work.Substring($ci + $blockCloser.Length)   # code resumes after the closer
            $inBlock = $false
            $blockCloser = ""
        }

        # ---- (1) strip line comment / detect an opening block comment ----
        # Find the first `--`. If it begins a long-bracket block (`--[[`, `--[=[`,
        # ...) that does NOT close on this same line, enter block mode. Either way
        # only the code BEFORE the `--` is live on this line.
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
                    $inBlock = $true            # block runs onto a later line
                    $blockCloser = $closer
                }
            }
        }

        # ---- (2) blank string-literal interiors ----
        # A `unpack(` inside a quoted string (e.g. an error/marker message like
        # "...reverted to bare unpack(args)...") is not a real call. Replace
        # double- then single-quoted spans with empty strings before matching;
        # genuine unpack() outside any string is untouched.
        $codePart = [regex]::Replace($codePart, '"[^"]*"', '""')
        $codePart = [regex]::Replace($codePart, "'[^']*'", "''")

        if (-not $rxUnpackAny.IsMatch($codePart)) { continue }

        # Strip 3-arg matches first (which fully consume their substring).
        # What's left is the 1-arg / 2-arg candidate region. If nothing
        # remains after stripping 3-arg forms, the line is clean.
        $residual = $rxUnpack3Arg.Replace($codePart, '')
        if (-not $rxUnpackAny.IsMatch($residual)) { continue }

        # At this point the line has at least one bare `unpack(` (1 or 2
        # arg form) that wasn't a 3-arg call. We classify per match for the
        # diagnostic; flagging the line once is enough — the human reading
        # the WARN will see the offending text.

        # ---- suppression checks ----
        # 1) Inline pragma on the same line (annotation appears anywhere in
        #    the FULL line, including the comment tail we stripped above).
        if ($rxSafePragma.IsMatch($line)) { continue }

        # 2) Own-line comment immediately above (within 1 line) carrying the
        #    pragma — pattern e.g.
        #         -- unpack-safe: vanilla returns at most 1 value
        #         return unpack(results)
        if ($i -gt 0 -and $rxSafePragma.IsMatch($lines[$i - 1])) { continue }

        # 3) Nearby select("#", ...) capture within ~5 lines above. The
        #    author has clearly counted the real arity and is passing it
        #    somewhere (most often as `j` in the unpack call's nested
        #    expression that our coarse regex missed).
        $lo = [Math]::Max(0, $i - 5)
        $hasSelect = $false
        for ($k = $lo; $k -lt $i; $k++) {
            if ($rxSelectHash.IsMatch($lines[$k])) { $hasSelect = $true; break }
        }
        if ($hasSelect) { continue }

        $warnings += [pscustomobject]@{
            File = $Path
            Line = $i + 1
            Text = $line.Trim()
        }
    }
    return ,$warnings
}

# ---- self-test ----
# Drives the synthetic fixtures under `qa/_test_fixtures/` and asserts a
# specific verdict per fixture. Run with `-SelfTest`; bypasses the normal
# scan. Exit 0 = self-test passed, 2 = self-test failed (regex/heuristic
# regression).
function Invoke-SelfTest {
    $fixDir = Join-Path $PSScriptRoot "_test_fixtures"
    if (-not (Test-Path $fixDir)) {
        Write-Host "[check_unpack_safety -SelfTest] FAIL: $fixDir does not exist." -ForegroundColor Red
        return 2
    }

    $cases = @(
        @{ Path = "unpack_bad.lua";          ExpectedWarn = $true;  Desc = "bare unpack(t) without annotation" },
        @{ Path = "unpack_good.lua";         ExpectedWarn = $false; Desc = "unpack(t, 1, n) with explicit j" },
        @{ Path = "unpack_annotated.lua";    ExpectedWarn = $false; Desc = "unpack(t) -- single-return: ok" },
        @{ Path = "unpack_blockcomment.lua"; ExpectedWarn = $false; Desc = "unpack() only inside a --[[ ]] block comment" },
        @{ Path = "unpack_instring.lua";     ExpectedWarn = $false; Desc = "unpack( only inside a string literal" }
    )

    $allPass = $true
    foreach ($c in $cases) {
        $f = Join-Path $fixDir $c.Path
        if (-not (Test-Path $f)) {
            Write-Host "  X $($c.Path): missing fixture file" -ForegroundColor Red
            $allPass = $false
            continue
        }
        $w = Scan-File -Path $f
        $gotWarn = ($w.Count -gt 0)
        $verdict = if ($gotWarn -eq $c.ExpectedWarn) { "PASS" } else { "FAIL" }
        $colour = if ($verdict -eq "PASS") { "Green" } else { "Red" }
        Write-Host "  [$verdict] $($c.Path) -- $($c.Desc) (warn=$gotWarn, expected=$($c.ExpectedWarn))" -ForegroundColor $colour
        if ($verdict -eq "FAIL") { $allPass = $false }
    }

    Write-Host ""
    if ($allPass) {
        Write-Host "[check_unpack_safety -SelfTest] OK -- all $($cases.Count) fixture verdicts match." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[check_unpack_safety -SelfTest] FAILED -- regex / heuristic regression. Inspect fixtures + Scan-File." -ForegroundColor Red
        return 2
    }
}

# ---- main ----
Write-Host "=== check_unpack_safety ===" -ForegroundColor Cyan

if ($SelfTest) {
    $code = Invoke-SelfTest
    exit $code
}

$allWarnings = @()
$hardError   = $false

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
        foreach ($r in $rows) { $allWarnings += $r }
    }
}

Write-Host ""
if ($hardError) {
    Write-Host "[check_unpack_safety] ERROR -- one or more files failed to scan." -ForegroundColor Red
    exit 2
}

if ($allWarnings.Count -eq 0) {
    Write-Host "[check_unpack_safety] OK -- all unpack call sites either explicit-j or annotated." -ForegroundColor Green
    exit 0
}

Write-Host "[check_unpack_safety] WARNINGS: $($allWarnings.Count)" -ForegroundColor Yellow
foreach ($w in $allWarnings) {
    $rel = $w.File
    if ($rel.StartsWith($repoRoot)) { $rel = $rel.Substring($repoRoot.Length).TrimStart('\','/') }
    Write-Host ("  ! {0}:{1}: WARN: bare unpack(t) without explicit j arg -- potential nil-hole truncation (VMF_RECIPES.md § 2a)" -f $rel, $w.Line) -ForegroundColor Yellow
    Write-Host ("      $($w.Text)") -ForegroundColor DarkYellow
}
exit 1
