# check_rt_textual_invariants.ps1 - tier-a static gate for the source-text
# invariants that issue #511 removed from the in-game regression suites.
#
# WHY THIS EXISTS
#   Several mods locked bug-class fixes with a `/<mod>_regression_test` check
#   that read the mod's OWN source via `io.open` and grepped for a marker
#   string. The retail Stingray VM registers no `io` library (mods are
#   loadstring'd into the shared _G, mod_manager.lua:375), so every such check
#   threw `attempt to index global 'io' (a nil value)` and FALSE-FAILED on
#   healthy code (issue #511). The runtime half of each check was converted to a
#   load-time marker; the genuinely SOURCE-TEXT half (a literal or absence
#   invariant the running game cannot see) moved here, to a tier-(a) repo QA gate
#   (PROJECT_STANDARDS 2.2b). See qa/CHECKS.md row 59.
#
# WHAT IT DOES
#   Reads a NEEDLE MANIFEST (qa/rt_textual_invariants.psd1) - one entry per
#   invariant: which mod, which repo-relative file, the needle (literal string or
#   regex), polarity (present | absent), the issue it locks, and a note. For each
#   entry it scans the named file and reports PASS/FAIL:
#     * present : FAIL if the needle occurs fewer than minCount times (default 1)
#                 or, when maxCount is set, more than maxCount times.
#     * absent  : FAIL if the needle occurs at all (the invariant's forbidden
#                 pattern came back - e.g. a bare :local_player() re-entered a
#                 file that must never call it).
#   A MISSING FILE is a FAIL: the invariant's file moved or was renamed and the
#   manifest is now stale - that must surface, not silently pass.
#
# This is a BLOCKING source gate (like check_vmf_widget_types /
# check_event_register_signature): no advisory tier. Exit 2 on any FAIL so a
# reworded/deleted invariant blocks the commit until the manifest is updated.
#
# Runs in a few seconds: one literal Select-String-class scan (String.IndexOf) or
# one [regex]::Matches per entry. No per-line Lua parsing.
#
# Exit codes:
#   0 - all invariants hold (or -SelfTest passed)
#   2 - one or more FAILs (reworded/removed needle, or a missing file), or a
#       -SelfTest regression, or a manifest/read error.
#
# Self-test: pass -SelfTest to exercise the pure scan logic against synthetic
# fixture files in a temp dir (present pass, absent fail, missing-file fail,
# minCount, and a comment-excluding regex). Offline, ~1s, no repo dependency.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [string]$ManifestPath = (Join-Path $PSScriptRoot "rt_textual_invariants.psd1"),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# Count occurrences of $needle in $text. Literal uses an ordinal IndexOf sweep
# (no regex metacharacter surprises); non-literal treats $needle as a .NET regex.
function Get-NeedleCount {
    param([string]$Text, [string]$Needle, [bool]$Literal)
    if ([string]::IsNullOrEmpty($Needle)) { return 0 }
    if ($Literal) {
        $count = 0; $idx = 0
        while ($true) {
            $idx = $Text.IndexOf($Needle, $idx, [System.StringComparison]::Ordinal)
            if ($idx -lt 0) { break }
            $count++
            $idx += $Needle.Length
        }
        return $count
    }
    return ([regex]::Matches($Text, $Needle)).Count
}

# Evaluate every manifest entry against the source tree under $Root. Returns a
# list of result rows: @{ Mod; File; Needle; Polarity; Issue; Status; Detail }.
# Status is 'PASS' or 'FAIL'. Pure (no host writes) so the self-test can reuse it.
function Invoke-NeedleScan {
    param([string]$Root, [object[]]$Entries)
    $rows = @()
    foreach ($e in $Entries) {
        $literal   = if ($null -ne $e.literal) { [bool]$e.literal } else { $true }
        $polarity  = "$($e.polarity)".ToLower()
        $minCount  = if ($null -ne $e.minCount) { [int]$e.minCount } else { 1 }
        $maxCount  = if ($null -ne $e.maxCount) { [int]$e.maxCount } else { $null }
        $relFile   = "$($e.file)"
        $full      = Join-Path $Root ($relFile -replace '/', [System.IO.Path]::DirectorySeparatorChar)

        $row = [ordered]@{
            Mod = "$($e.mod)"; File = $relFile; Needle = "$($e.needle)"
            Polarity = $polarity; Issue = "$($e.issueRef)"; Status = 'FAIL'; Detail = ''
        }

        if (-not (Test-Path -LiteralPath $full)) {
            $row.Detail = "file not found (moved/renamed - update the manifest)"
            $rows += [pscustomobject]$row
            continue
        }

        $text = Read-FileUtf8 $full
        $count = Get-NeedleCount -Text $text -Needle $row.Needle -Literal $literal

        if ($polarity -eq 'absent') {
            if ($count -eq 0) {
                $row.Status = 'PASS'; $row.Detail = "forbidden pattern absent"
            } else {
                $row.Detail = "forbidden pattern present $count time(s) - invariant broken"
            }
        } elseif ($polarity -eq 'present') {
            if ($count -lt $minCount) {
                $row.Detail = "found $count, need >= $minCount (needle reworded or removed)"
            } elseif ($null -ne $maxCount -and $count -gt $maxCount) {
                $row.Detail = "found $count, allow <= $maxCount (singleton/count invariant broken)"
            } else {
                $row.Status = 'PASS'
                $row.Detail = if ($null -ne $maxCount) { "found $count (in [$minCount..$maxCount])" } else { "found $count (>= $minCount)" }
            }
        } else {
            $row.Detail = "unknown polarity '$polarity' (want present|absent) - fix the manifest"
        }
        $rows += [pscustomobject]$row
    }
    return $rows
}

function Write-Rows {
    param([object[]]$Rows, [switch]$OnlyFail)
    foreach ($r in $Rows) {
        if ($OnlyFail -and $r.Status -eq 'PASS') { continue }
        $colour = if ($r.Status -eq 'PASS') { 'DarkGray' } else { 'Red' }
        $mark   = if ($r.Status -eq 'PASS') { '  .' } else { '  X' }
        $iss    = if ($r.Issue) { " $($r.Issue)" } else { '' }
        Write-Host ("{0} [{1}] {2} ({3}){4}: {5}" -f $mark, $r.Status, $r.Mod, $r.Polarity, $iss, $r.Detail) -ForegroundColor $colour
        Write-Host ("        {0}  needle: {1}" -f $r.File, $r.Needle) -ForegroundColor $colour
    }
}

# ---- self-test (pure scan logic against synthetic fixtures) ----
function Invoke-SelfTest {
    $script:__ok = $true
    function Assert($cond, $desc) {
        $verdict = if ($cond) { 'PASS' } else { 'FAIL' }
        $colour  = if ($cond) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $desc) -ForegroundColor $colour
        if (-not $cond) { $script:__ok = $false }
    }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("rt_ti_selftest_" + [System.Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        # Fixture A: real code line plus a COMMENT that names a forbidden token
        # (mirrors the gt _gt_debug_highlights.lua case: the file documents the
        # "no bare :local_player()" invariant in a comment, so a naive absence
        # literal would false-fail; a comment-excluding regex must still pass).
        $fa = @"
local function safe() return mod:local_player_safe() end
-- invariant: no bare :local_player() call may re-enter this file
local twice = "MARK" .. "MARK"
local n = FOO[bar]
"@
        [System.IO.File]::WriteAllText((Join-Path $tmp "fixture_a.lua"), $fa, [System.Text.UTF8Encoding]::new($false))

        $entries = @(
            @{ mod='self'; file='fixture_a.lua'; needle='local_player_safe'; literal=$true; polarity='present'; issueRef='#T1'; note='present passes' }
            @{ mod='self'; file='fixture_a.lua'; needle='MARK'; literal=$true; polarity='present'; minCount=2; issueRef='#T2'; note='minCount passes' }
            @{ mod='self'; file='fixture_a.lua'; needle='MARK'; literal=$true; polarity='present'; minCount=3; issueRef='#T3'; note='minCount fails (only 2)' }
            @{ mod='self'; file='fixture_a.lua'; needle='(?m)^(?!\s*--).*:local_player\(\)'; literal=$false; polarity='absent'; issueRef='#T4'; note='comment-excluded absence passes' }
            @{ mod='self'; file='fixture_a.lua'; needle=':local_player()'; literal=$true; polarity='absent'; issueRef='#T5'; note='naive absence FAILS on the comment' }
            @{ mod='self'; file='does_not_exist.lua'; needle='whatever'; literal=$true; polarity='present'; issueRef='#T6'; note='missing file FAILS' }
        )
        $rows = Invoke-NeedleScan -Root $tmp -Entries $entries

        Assert ($rows[0].Status -eq 'PASS') "present needle that exists -> PASS"
        Assert ($rows[1].Status -eq 'PASS') "minCount=2 with 2 occurrences -> PASS"
        Assert ($rows[2].Status -eq 'FAIL') "minCount=3 with 2 occurrences -> FAIL"
        Assert ($rows[3].Status -eq 'PASS') "comment-excluding absence regex -> PASS (comment ignored)"
        Assert ($rows[4].Status -eq 'FAIL') "naive literal absence -> FAIL (matches the comment)"
        Assert ($rows[5].Status -eq 'FAIL') "missing file -> FAIL"
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ""
    if ($script:__ok) {
        Write-Host "[check_rt_textual_invariants -SelfTest] OK -- scan logic intact." -ForegroundColor Green
        return 0
    }
    Write-Host "[check_rt_textual_invariants -SelfTest] FAILED -- scan-logic regression." -ForegroundColor Red
    return 2
}

# ---- main ----
Write-Host "=== check_rt_textual_invariants ===" -ForegroundColor Cyan

if ($SelfTest) { exit (Invoke-SelfTest) }

$repoRoot = (Resolve-Path $RepoRoot).Path

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    Write-Host "[check_rt_textual_invariants] ERROR -- manifest not found: $ManifestPath" -ForegroundColor Red
    exit 2
}

try {
    $manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
} catch {
    Write-Host "[check_rt_textual_invariants] ERROR -- manifest failed to parse: $_" -ForegroundColor Red
    exit 2
}

$entries = @($manifest.entries)
if ($entries.Count -eq 0) {
    Write-Host "[check_rt_textual_invariants] ERROR -- manifest has no entries." -ForegroundColor Red
    exit 2
}

$rows = Invoke-NeedleScan -Root $repoRoot -Entries $entries
$fails = @($rows | Where-Object { $_.Status -eq 'FAIL' })

if (-not $Quiet) {
    Write-Rows -Rows $rows
} else {
    Write-Rows -Rows $rows -OnlyFail
}

# Per-mod tally
$byMod = $rows | Group-Object Mod | Sort-Object Name
Write-Host ""
Write-Host "Coverage by mod:" -ForegroundColor DarkGray
foreach ($g in $byMod) {
    $gf = @($g.Group | Where-Object { $_.Status -eq 'FAIL' }).Count
    $col = if ($gf -gt 0) { 'Red' } else { 'DarkGray' }
    Write-Host ("  {0}: {1} needle(s), {2} fail" -f $g.Name, $g.Count, $gf) -ForegroundColor $col
}

Write-Host ""
if ($fails.Count -eq 0) {
    Write-Host ("[check_rt_textual_invariants] OK -- all {0} source-text invariants hold." -f $rows.Count) -ForegroundColor Green
    exit 0
}

Write-Host ("[check_rt_textual_invariants] FAIL -- {0}/{1} invariant(s) broken (reworded needle, removed pattern, or moved file). Fix the source or update qa/rt_textual_invariants.psd1." -f $fails.Count, $rows.Count) -ForegroundColor Red
exit 2
