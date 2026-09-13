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
# minCount, and a comment-excluding regex) plus the literal-only manifest loader
# (a 600-entry manifest, a one-entry manifest, and five rejected non-data
# shapes). Offline, a few seconds, no repo dependency.

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

# Load the needle manifest as literal data. Import-PowerShellDataFile evaluates
# the whole table in ONE safe-value pass, and that pass has a size ceiling: on
# 2026-09-12 the 316-entry manifest sat exactly at it, so any additional entry,
# even a duplicate of an existing row, failed to parse under PowerShell 7.6 and
# 5.1 (issue #1577). Parse the same restricted grammar with the language parser
# instead: exactly one `@{ entries = @( <hashtable literals> ) }` table, with
# SafeGetValue validating each entry on its own. Nothing is executed.
function Import-NeedleManifest {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        throw ("line {0}: {1}" -f $errors[0].Extent.StartLineNumber, $errors[0].Message)
    }
    $statements = @($ast.EndBlock.Statements)
    if ($ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or $statements.Count -ne 1 -or
        $statements[0] -isnot [System.Management.Automation.Language.PipelineAst] -or
        $statements[0].PipelineElements.Count -ne 1 -or
        $statements[0].PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst] -or
        $statements[0].PipelineElements[0].Expression -isnot [System.Management.Automation.Language.HashtableAst]) {
        throw 'manifest must be exactly one literal data table'
    }
    $pairs = @($statements[0].PipelineElements[0].Expression.KeyValuePairs)
    if ($pairs.Count -ne 1 -or
        $pairs[0].Item1 -isnot [System.Management.Automation.Language.StringConstantExpressionAst] -or
        $pairs[0].Item1.Value -cne 'entries') {
        throw 'manifest table must contain only the entries key'
    }
    $value = $pairs[0].Item2
    $array = $null
    if ($value -is [System.Management.Automation.Language.PipelineAst] -and
        $value.PipelineElements.Count -eq 1 -and
        $value.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $array = $value.PipelineElements[0].Expression
    }
    if ($array -isnot [System.Management.Automation.Language.ArrayExpressionAst]) {
        throw 'manifest entries must be an @( ... ) array of hashtable literals'
    }
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($statement in @($array.SubExpression.Statements)) {
        if ($statement -isnot [System.Management.Automation.Language.PipelineAst] -or
            $statement.PipelineElements.Count -ne 1 -or
            $statement.PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst] -or
            $statement.PipelineElements[0].Expression -isnot [System.Management.Automation.Language.HashtableAst]) {
            throw ("line {0}: every entry must be one hashtable literal" -f $statement.Extent.StartLineNumber)
        }
        try {
            $entries.Add($statement.PipelineElements[0].Expression.SafeGetValue())
        } catch {
            throw ("line {0}: entry is not literal data: {1}" -f $statement.Extent.StartLineNumber, $_.Exception.Message)
        }
    }
    # Emit the rows unwrapped; callers collect them with @(...) so a one-entry
    # manifest is still a one-row array.
    return $entries.ToArray()
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

        # Manifest loader (issue #1577): no whole-table size ceiling, literal data
        # only. 600 rows is well above the 316-row point where the old
        # Import-PowerShellDataFile load broke.
        $row = "    @{ mod='self'; file='fixture_a.lua'; needle='MARK'; literal=`$true; polarity='present'; minCount=2; issueRef='#T7'; note='capacity' }"
        $big = "@{`r`n  entries = @(`r`n" + ((1..600 | ForEach-Object { $row }) -join "`r`n") + "`r`n  )`r`n}`r`n"
        $bigPath = Join-Path $tmp "big.psd1"
        [System.IO.File]::WriteAllText($bigPath, $big, [System.Text.UTF8Encoding]::new($false))
        $bigEntries = @(Import-NeedleManifest -Path $bigPath)
        Assert ($bigEntries.Count -eq 600 -and $bigEntries[599].mod -eq 'self' -and $bigEntries[599].minCount -eq 2) "600-entry manifest loads every row as data"
        $bigRows = Invoke-NeedleScan -Root $tmp -Entries $bigEntries
        Assert (@($bigRows | Where-Object { $_.Status -eq 'PASS' }).Count -eq 600) "600-entry manifest scans every row"

        $single = "@{ entries = @( @{ mod='self'; file='fixture_a.lua'; needle='MARK'; literal=`$true; polarity='present'; issueRef='#T8'; note='one' } ) }"
        $singlePath = Join-Path $tmp "single.psd1"
        [System.IO.File]::WriteAllText($singlePath, $single, [System.Text.UTF8Encoding]::new($false))
        $singleEntries = @(Import-NeedleManifest -Path $singlePath)
        Assert ($singleEntries.Count -eq 1 -and $singleEntries[0].issueRef -eq '#T8' -and $singleEntries[0].literal -eq $true) "single-entry manifest stays a one-row array"

        $rejects = @(
            @{ Name = 'dynamic expression value'; Text = "@{ entries = @( @{ mod='self'; file='x'; needle=(Get-Date); literal=`$true; polarity='present' } ) }" }
            @{ Name = 'extra top-level key'; Text = "@{ entries = @( @{ mod='self'; file='x'; needle='x'; literal=`$true; polarity='present' } ); other = 1 }" }
            @{ Name = 'non-hashtable entry'; Text = "@{ entries = @( 'x' ) }" }
            @{ Name = 'script statement before the table'; Text = "Write-Output 'side effect'`r`n@{ entries = @( @{ mod='self'; file='x'; needle='x'; literal=`$true; polarity='present' } ) }" }
            @{ Name = 'entries not an array expression'; Text = "@{ entries = @{ mod='self'; file='x'; needle='x'; literal=`$true; polarity='present' } }" }
        )
        $k = 0
        foreach ($reject in $rejects) {
            $k++
            $rejectPath = Join-Path $tmp ("reject_{0}.psd1" -f $k)
            [System.IO.File]::WriteAllText($rejectPath, $reject.Text, [System.Text.UTF8Encoding]::new($false))
            $threw = $false
            try { $null = Import-NeedleManifest -Path $rejectPath } catch { $threw = $true }
            Assert $threw ("manifest loader rejects {0}" -f $reject.Name)
        }
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
    $entries = @(Import-NeedleManifest -Path $ManifestPath)
} catch {
    Write-Host "[check_rt_textual_invariants] ERROR -- manifest failed to parse: $_" -ForegroundColor Red
    exit 2
}

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
