# ============================================================================
# gen-appearance-gaps.ps1 - the enumerated 660 appearance backlog
# ============================================================================
#
# WHAT THIS IS
#   Expands every registered appearance census to its full surface x edge
#   matrix and writes the complete list of UNSUPPORTED pairs, with each pair's
#   fallback note, to:
#       docs/generated/APPEARANCE_CENSUS_GAPS.generated.md
#
# WHY IT EXISTS
#   Issue 660's backlog was never enumerated: each mod declared surfaces and
#   lifecycle edges as two independent vectors, so a hole like "husk AT mission
#   transition" could not even be named, let alone counted. Issue 1157 re-keyed
#   the censuses to declare every (surface, edge) PAIR; this generator turns
#   those declarations into the one reviewable list of what is actually missing.
#
# GROUND TRUTH
#   tools/shared_lib/_lib_appearance_descriptor.lua owns the vocabulary
#   (M.CELLS / M.EDGES), the census registry (M.CENSUS_FILES), and the
#   expansion rule (M.expand_matrix). This script reimplements none of it: it
#   drives tools/gen-appearance-gaps/emit-census-gaps.lua under the vendored
#   Lua 5.1 runtime that qa/check_lua_unit_tests.ps1 already uses, then formats
#   the emitted rows. Presentation lives here; truth lives in the censuses.
#
# USAGE
#   pwsh -NoProfile -File tools/gen-appearance-gaps/gen-appearance-gaps.ps1 -GenDate 2026-08-04
#   pwsh -NoProfile -File tools/gen-appearance-gaps/gen-appearance-gaps.ps1 -Check
#   pwsh -NoProfile -File tools/gen-appearance-gaps/gen-appearance-gaps.ps1 -SelfTest
#
#   -GenDate is required when writing: the build environment has no reliable
#   clock, so the generation date is stamped from what the caller passes (same
#   contract as tools/gen-name-map/gen-name-map.ps1).
#   -Check regenerates in memory and compares against the committed file
#   WITHOUT writing, so CI can fail on drift. It reuses the committed file's
#   own Generated: line, so a stale date is never reported as content drift.
#
# EXIT CODES
#   0 = wrote the report (or -Check found no drift)
#   2 = expansion failed, the runtime is missing, or -Check found drift

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$MarkdownPath,
    [string]$GenDate,
    [switch]$Check,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $MarkdownPath) {
    $MarkdownPath = Join-Path $RepoRoot 'docs\generated\APPEARANCE_CENSUS_GAPS.generated.md'
}

$luaExe = Join-Path $RepoRoot 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$emitter = Join-Path $PSScriptRoot 'emit-census-gaps.lua'

function Fail([string]$Message) {
    Write-Host "[gen_appearance_gaps] ERROR -- $Message" -ForegroundColor Red
    exit 2
}

function Get-CensusRows {
    if (-not (Test-Path -LiteralPath $luaExe -PathType Leaf)) {
        Fail "vendored Lua 5.1 runtime is missing: $luaExe"
    }
    if (-not (Test-Path -LiteralPath $emitter -PathType Leaf)) {
        Fail "emitter is missing: $emitter"
    }
    # Native stderr is promoted to a terminating error under Stop; collect it
    # as ordinary output so an expansion failure is reportable, not a crash.
    $saved = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = @(& $luaExe $emitter ($RepoRoot -replace '\\', '/') 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $saved
    }
    if ($code -ne 0) {
        Fail ("census expansion failed (lua exit $code):`n" + ($raw -join "`n"))
    }

    $rows = [System.Collections.Generic.List[psobject]]::new()
    $meta = @{}
    foreach ($line in $raw) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.StartsWith('#')) {
            $parts = $text.Substring(1).Split("`t")
            if ($parts.Count -ge 2) { $meta[$parts[0]] = $parts[1] }
            continue
        }
        $f = $text.Split("`t")
        if ($f.Count -lt 6) { Fail "malformed emitter row: $text" }
        $rows.Add([pscustomobject]@{
            Mod      = $f[0]
            MirrorOf = $f[1]
            Family   = $f[2]
            Surface  = $f[3]
            Edge     = $f[4]
            State    = $f[5]
            Note     = if ($f.Count -ge 7) { $f[6] } else { '' }
        })
    }
    if ($rows.Count -eq 0) { Fail 'emitter produced no rows' }
    return [pscustomobject]@{ Rows = $rows; Meta = $meta }
}

function Escape-Cell([string]$Text) {
    # Markdown table cells cannot carry a bare pipe.
    return ($Text -replace '\|', '\|')
}

function Build-Markdown {
    param($Rows, $Meta, [string]$Date)

    $surfaces = @($Meta['surfaces'].Split(','))
    $edges = @($Meta['edges'].Split(','))
    $mods = @($Rows | ForEach-Object { $_.Mod } | Select-Object -Unique)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Appearance census gaps (generated)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('<!-- GENERATED by tools/gen-appearance-gaps/gen-appearance-gaps.ps1 - do NOT hand-edit. -->')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("Generated: $Date")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine(("Schema: v{0} surface x edge matrix (issue 1157). Vocabulary: {1} surfaces x {2} edges = {3} pairs per family." -f
        $Meta['schema_version'], $surfaces.Count, $edges.Count, ($surfaces.Count * $edges.Count)))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('This is the enumerated issue-660 backlog: every (mod, family, surface, edge)')
    [void]$sb.AppendLine('pair a census declares UNSUPPORTED, with the note explaining why the degrade is')
    [void]$sb.AppendLine('safe and which issue tracks it. An entry here is a DECLARED hole, not a bug')
    [void]$sb.AppendLine('report - the censuses exist so holes are counted instead of rediscovered.')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('`weapon_tweaker_dev` is a byte-parity mirror of `weapon_tweaker`; its rows are the')
    [void]$sb.AppendLine('same backlog counted twice and are excluded from the deduplicated totals below.')
    [void]$sb.AppendLine()

    $unsupported = @($Rows | Where-Object { $_.State -eq 'unsupported' })
    $realRows = @($Rows | Where-Object { -not $_.MirrorOf })
    $realUnsupported = @($realRows | Where-Object { $_.State -eq 'unsupported' })

    [void]$sb.AppendLine('## Totals')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine(("Deduplicated backlog: **{0} unsupported pairs** of {1} declared ({2:N1}%), across {3} families in {4} mods." -f
        $realUnsupported.Count, $realRows.Count,
        (100.0 * $realUnsupported.Count / [Math]::Max(1, $realRows.Count)),
        (@($realRows | ForEach-Object { "$($_.Mod)/$($_.Family)" } | Select-Object -Unique)).Count,
        (@($realRows | ForEach-Object { $_.Mod } | Select-Object -Unique)).Count))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine(("Including the wt_dev mirror: {0} unsupported of {1} declared." -f
        $unsupported.Count, $Rows.Count))
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('### Per mod')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Mod | Families | Pairs | Implemented | Unsupported | Unsupported % |')
    [void]$sb.AppendLine('|---|---:|---:|---:|---:|---:|')
    foreach ($mod in $mods) {
        $modRows = @($Rows | Where-Object { $_.Mod -eq $mod })
        $modUnsup = @($modRows | Where-Object { $_.State -eq 'unsupported' })
        $famCount = (@($modRows | ForEach-Object { $_.Family } | Select-Object -Unique)).Count
        $label = if (($modRows | Select-Object -First 1).MirrorOf) { "$mod (mirror)" } else { $mod }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5:N1}% |' -f
            $label, $famCount, $modRows.Count, ($modRows.Count - $modUnsup.Count), $modUnsup.Count,
            (100.0 * $modUnsup.Count / [Math]::Max(1, $modRows.Count))))
    }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('### Per surface (deduplicated: mirror excluded)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Surface | Pairs | Implemented | Unsupported | Unsupported % |')
    [void]$sb.AppendLine('|---|---:|---:|---:|---:|')
    foreach ($surface in $surfaces) {
        $sRows = @($realRows | Where-Object { $_.Surface -eq $surface })
        $sUnsup = @($sRows | Where-Object { $_.State -eq 'unsupported' })
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4:N1}% |' -f
            $surface, $sRows.Count, ($sRows.Count - $sUnsup.Count), $sUnsup.Count,
            (100.0 * $sUnsup.Count / [Math]::Max(1, $sRows.Count))))
    }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('### Per edge (deduplicated: mirror excluded)')
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('| Edge | Pairs | Implemented | Unsupported | Unsupported % |')
    [void]$sb.AppendLine('|---|---:|---:|---:|---:|')
    foreach ($edge in $edges) {
        $eRows = @($realRows | Where-Object { $_.Edge -eq $edge })
        $eUnsup = @($eRows | Where-Object { $_.State -eq 'unsupported' })
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4:N1}% |' -f
            $edge, $eRows.Count, ($eRows.Count - $eUnsup.Count), $eUnsup.Count,
            (100.0 * $eUnsup.Count / [Math]::Max(1, $eRows.Count))))
    }
    [void]$sb.AppendLine()

    [void]$sb.AppendLine('## Unsupported pairs, grouped by surface then edge')
    [void]$sb.AppendLine()
    foreach ($surface in $surfaces) {
        $sRows = @($unsupported | Where-Object { $_.Surface -eq $surface })
        if ($sRows.Count -eq 0) {
            [void]$sb.AppendLine("### $surface")
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('No unsupported pairs: every family implements this surface at every edge.')
            [void]$sb.AppendLine()
            continue
        }
        [void]$sb.AppendLine(('### {0} ({1} unsupported pairs)' -f $surface, $sRows.Count))
        [void]$sb.AppendLine()
        foreach ($edge in $edges) {
            $eRows = @($sRows | Where-Object { $_.Edge -eq $edge })
            if ($eRows.Count -eq 0) { continue }
            [void]$sb.AppendLine(('#### {0} x {1} ({2})' -f $surface, $edge, $eRows.Count))
            [void]$sb.AppendLine()
            [void]$sb.AppendLine('| Mod | Family | Fallback note |')
            [void]$sb.AppendLine('|---|---|---|')
            foreach ($r in $eRows) {
                [void]$sb.AppendLine(('| {0} | {1} | {2} |' -f
                    (Escape-Cell $r.Mod), (Escape-Cell $r.Family), (Escape-Cell $r.Note)))
            }
            [void]$sb.AppendLine()
        }
    }
    return $sb.ToString() -replace "`r`n", "`n"
}

if ($SelfTest) {
    # Prove the drift comparison actually fires: generate, mutate one byte of
    # the in-memory text, and confirm the comparator rejects it.
    $data = Get-CensusRows
    $a = Build-Markdown -Rows $data.Rows -Meta $data.Meta -Date '2026-01-01'
    $b = Build-Markdown -Rows $data.Rows -Meta $data.Meta -Date '2026-01-01'
    if ($a -cne $b) {
        Write-Host '[gen_appearance_gaps self-test] FAIL: generation is not deterministic' -ForegroundColor Red
        exit 2
    }
    if ($a -ceq ($a + 'x')) {
        Write-Host '[gen_appearance_gaps self-test] FAIL: comparator accepts mutated text' -ForegroundColor Red
        exit 2
    }
    if ($a -notmatch '## Unsupported pairs, grouped by surface then edge') {
        Write-Host '[gen_appearance_gaps self-test] FAIL: report body missing' -ForegroundColor Red
        exit 2
    }
    if (-not $Quiet) { Write-Host '[gen_appearance_gaps self-test] PASS' -ForegroundColor Green }
    exit 0
}

$data = Get-CensusRows

if ($Check) {
    if (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) {
        Fail "generated report is missing: $MarkdownPath (run this script with -GenDate)"
    }
    $committed = ([IO.File]::ReadAllText($MarkdownPath, [Text.Encoding]::UTF8)) -replace "`r`n", "`n"
    # Reuse the committed date so a stale stamp is not reported as content drift.
    $date = if ($committed -match '(?m)^Generated:\s*(.+)$') { $Matches[1].Trim() } else { 'unknown' }
    $expected = Build-Markdown -Rows $data.Rows -Meta $data.Meta -Date $date
    if ($committed -cne $expected) {
        Fail "$MarkdownPath is stale - regenerate with -GenDate <date>"
    }
    if (-not $Quiet) {
        Write-Host '[gen_appearance_gaps] OK -- generated report matches the censuses.' -ForegroundColor Green
    }
    exit 0
}

if (-not $GenDate) { Fail '-GenDate is required when writing (the build env has no reliable clock)' }

$markdown = Build-Markdown -Rows $data.Rows -Meta $data.Meta -Date $GenDate
$dir = Split-Path $MarkdownPath -Parent
if (-not (Test-Path -LiteralPath $dir)) { [void][IO.Directory]::CreateDirectory($dir) }
[IO.File]::WriteAllText($MarkdownPath, $markdown, [Text.UTF8Encoding]::new($false))

if (-not $Quiet) {
    $unsup = @($data.Rows | Where-Object { $_.State -eq 'unsupported' -and -not $_.MirrorOf }).Count
    $total = @($data.Rows | Where-Object { -not $_.MirrorOf }).Count
    Write-Host ("[gen_appearance_gaps] OK -- {0} unsupported of {1} declared pairs -> {2}" -f
        $unsup, $total, $MarkdownPath) -ForegroundColor Green
}
exit 0
