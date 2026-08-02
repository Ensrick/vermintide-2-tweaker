# check_pipeline_state.ps1 - the pipeline-state ladder (advisory, read-only).
#
# WHY: "fixed" conflates five distinct states of a change - (1) in source,
# (2) reflected in the CHANGELOG, (3) compiled into bundleV2, (4) uploaded to
# Workshop, (5) actually pulled by the player. A fix stranded on a lower rung
# ("nothing you fixed works": cim #246 [not deployed], mp 0.2.29 uploaded while
# the tester still runs 0.2.28) is invisible until someone reads five surfaces
# by hand. This check prints ONE ladder row per active mod so the gap is obvious.
#
# For every active mod in tools/mod-inventory.psd1 (frozen `tweaker` is already
# excluded there; dev/stable pairs are separate inventory rows and so become
# separate ladder rows), it reports:
#   source MOD_VERSION     - the constant in <dir>/scripts/mods/<dir>/<dir>.lua
#   CHANGELOG version      - the newest `## <version>` header in <dir>/CHANGELOG.md
#   bundle state           - fresh / STALE / none (see HEURISTIC below)
#   last Workshop upload    - newest 'Uploaded new content' OR 'No content change'
#                            timestamp for the cfg published_id in workshop_log.txt
#   ND                     - a [not deployed] marker on any of the top-3 CHANGELOG entry HEADER lines (body prose is historical and never counts)
#   verdict                - IN-SYNC / CHANGELOG-DRIFT / BUNDLE-STALE / UPLOAD-BEHIND
#                            (verdicts combine with '+' when more than one rung is off)
#
# HEURISTICS (stated honestly - this is a mtime/timestamp reasoner, not a hash proof):
#   * BUNDLE-STALE compares the newest bundleV2 file mtime against the newest
#     scripts/ file mtime. A `git checkout`/clone rewrites mtimes to now, so on a
#     FRESH CI checkout every mod looks "fresh" regardless of true state - the
#     bundle rung is only meaningful on the maintainer's live working tree.
#   * UPLOAD-BEHIND compares the last upload timestamp against the newest bundle
#     mtime: a bundle built AFTER the last upload/no-change event is treated as
#     not-yet-uploaded. Same checkout-mtime caveat applies. If the log has no
#     record at all for a built bundle's id, it is treated as never-uploaded.
#   * CHANGELOG-DRIFT is exact-string (CHANGELOG top version != MOD_VERSION); no
#     mtime involved.
#
# ADVISORY: this check ALWAYS exits 0 on a normal run (never blocks the gate); it
# only prints. It runs everywhere including CI, where workshop_log.txt is absent -
# that is detected and the upload column is marked `n/a` (never a failure). Wired
# into run_all.ps1 with -Policy 'Advisory', mirroring check_in_progress. See
# qa/CHECKS.md row 61.
#
# -SelfTest exercises the pure verdict logic on planted fixtures and exits
# non-zero on a regression (auto-discovered by qa/run_selftests.ps1).
#
# Usage:
#   .\qa\check_pipeline_state.ps1
#   .\qa\check_pipeline_state.ps1 -Quiet
#   .\qa\check_pipeline_state.ps1 -WorkshopLog <path>
#   .\qa\check_pipeline_state.ps1 -SelfTest

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [string]$WorkshopLog = "C:\Program Files (x86)\Steam\logs\workshop_log.txt",
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

# ---------------------------------------------------------------------------
# Pure decision logic (self-testable, no filesystem/log access).
# $State keys: SourceVersion, ChangelogVersion, BundleExists (bool),
#   BundleMtime ([datetime]|$null), SourceMtime ([datetime]|$null),
#   UploadKnown (bool), UploadTime ([datetime]|$null).
# ---------------------------------------------------------------------------
function Get-PipelineVerdict {
    param([hashtable]$State)

    $flags = @()

    # Source-level: CHANGELOG header must match the shipped MOD_VERSION. Only
    # assessed when both are known (a missing surface is reported elsewhere).
    $src = [string]$State.SourceVersion
    $cl  = [string]$State.ChangelogVersion
    if ($src -and $cl -and ($src -ne $cl)) { $flags += 'CHANGELOG-DRIFT' }

    # Bundle rung: no bundle, or a bundle older than the newest source file.
    if (-not $State.BundleExists) {
        $flags += 'BUNDLE-STALE'
    } elseif ($State.BundleMtime -and $State.SourceMtime -and ($State.BundleMtime -lt $State.SourceMtime)) {
        $flags += 'BUNDLE-STALE'
    }

    # Upload rung: only when we actually have a log AND a built bundle to compare
    # against. No log => rung not assessable (CI); handled by the caller as n/a.
    if ($State.UploadKnown -and $State.BundleExists -and $State.BundleMtime) {
        if (-not $State.UploadTime) {
            $flags += 'UPLOAD-BEHIND'          # bundle built but no upload record at all
        } elseif ($State.UploadTime -lt $State.BundleMtime) {
            $flags += 'UPLOAD-BEHIND'          # current bundle postdates the last upload
        }
    }

    if ($flags.Count -eq 0) { return 'IN-SYNC' }

    # Emit in ladder order (source -> bundle -> upload) for a stable string.
    $order = @('CHANGELOG-DRIFT', 'BUNDLE-STALE', 'UPLOAD-BEHIND')
    return (($order | Where-Object { $flags -contains $_ }) -join '+')
}

function Get-ChangelogTopVersion([string]$text) {
    # First `## <version>` header from the top. Tolerates `## 0.1.2-dev (date)`,
    # `## [0.1.2] - date`, `## v0.1.2: ...`. Returns $null if none matches.
    foreach ($line in ($text -split '\r?\n')) {
        if ($line -match '^\s*##\s+\[?v?([0-9][0-9A-Za-z.\-]*)') { return $matches[1] }
    }
    return $null
}

function Test-ChangelogNotDeployed([string]$text, [int]$TopN = 3) {
    # True if any of the top-N CHANGELOG entry HEADER lines (`## ...`) carries a
    # "not deployed" / "not-deployed" lifecycle marker. Header lines ONLY, by
    # ruling 2026-08-02: entry BODIES legitimately contain historical prose like
    # "verification only. NOT deployed, NOT uploaded" (vdl 1.0.5/1.0.6 Build
    # notes) describing what that session did at write time - a later ship
    # covers those changes, so body prose must not flag forever. The lifecycle
    # marker doctrine (PROJECT_STANDARDS section 6.4) puts status tags on the
    # header line, which is the only place this heuristic reads.
    $lines = $text -split '\r?\n'
    $headerIdx = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*##\s+\S') { $headerIdx += $i }
    }
    if ($headerIdx.Count -eq 0) { return $false }
    $limit = [Math]::Min($TopN, $headerIdx.Count)
    for ($e = 0; $e -lt $limit; $e++) {
        if ($lines[$headerIdx[$e]] -match '(?i)not[ -]?deployed') { return $true }
    }
    return $false
}

function Get-NewestMtime([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $maxT = $null
    foreach ($f in (Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue)) {
        if ($null -eq $maxT -or $f.LastWriteTime -gt $maxT) { $maxT = $f.LastWriteTime }
    }
    return $maxT
}

function Get-PublishedIdFromCfg([string]$cfgPath) {
    if (-not (Test-Path -LiteralPath $cfgPath)) { return $null }
    $t = Read-FileUtf8 $cfgPath
    if ($t -match 'published_id\s*=\s*(\d+)L?\s*;') { return $matches[1] }
    return $null
}

function Read-LogLinesShared([string]$path) {
    # Steam holds workshop_log.txt open for writing, so File.ReadAllLines throws a
    # sharing violation. Open with FileShare.ReadWrite to read it live.
    $lines = @()
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try {
            while (($line = $sr.ReadLine()) -ne $null) { $lines += $line }
        } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
    return $lines
}

function Get-UploadMapFromLog([string]$logPath) {
    # id (string) -> @{ Time = [datetime]; Kind = 'upload'|'nochange' }.
    # The log is chronological, so the LAST matching line for an id wins.
    $map = @{}
    if (-not (Test-Path -LiteralPath $logPath)) { return $map }
    foreach ($line in (Read-LogLinesShared $logPath)) {
        $id = $null; $kind = $null
        if ($line -match 'Uploaded new content .* for item (\d+)') {
            $id = $matches[1]; $kind = 'upload'
        } elseif ($line -match 'No content change detected for item (\d+)') {
            $id = $matches[1]; $kind = 'nochange'
        } else {
            continue
        }
        if ($line -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
            try {
                $ts = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
            } catch {
                continue
            }
            $map[$id] = @{ Time = $ts; Kind = $kind }
        }
    }
    return $map
}

# ---------------------------------------------------------------------------
# Self-test: pure verdict logic on planted fixtures.
# ---------------------------------------------------------------------------
if ($SelfTest) {
    $old    = [datetime]'2026-01-01T00:00:00'
    $new    = [datetime]'2026-06-01T00:00:00'
    $newest = [datetime]'2026-07-01T00:00:00'
    $fail = @()

    function _expect($label, $expected, $state) {
        $got = Get-PipelineVerdict $state
        if ($got -ne $expected) { $script:fail += "${label}: expected '$expected' got '$got'" }
    }

    _expect 'in-sync' 'IN-SYNC' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '1.0.0-dev'
        BundleExists = $true; BundleMtime = $new; SourceMtime = $old
        UploadKnown = $true; UploadTime = $newest }

    _expect 'changelog-drift' 'CHANGELOG-DRIFT' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '0.9.9-dev'
        BundleExists = $true; BundleMtime = $new; SourceMtime = $old
        UploadKnown = $true; UploadTime = $newest }

    _expect 'no-bundle' 'BUNDLE-STALE' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '1.0.0-dev'
        BundleExists = $false; BundleMtime = $null; SourceMtime = $old
        UploadKnown = $true; UploadTime = $newest }

    _expect 'stale-bundle' 'BUNDLE-STALE' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '1.0.0-dev'
        BundleExists = $true; BundleMtime = $old; SourceMtime = $new
        UploadKnown = $true; UploadTime = $newest }

    _expect 'upload-behind' 'UPLOAD-BEHIND' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '1.0.0-dev'
        BundleExists = $true; BundleMtime = $new; SourceMtime = $old
        UploadKnown = $true; UploadTime = $old }

    _expect 'upload-unknown-is-not-behind' 'IN-SYNC' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '1.0.0-dev'
        BundleExists = $true; BundleMtime = $new; SourceMtime = $old
        UploadKnown = $false; UploadTime = $null }

    _expect 'no-upload-record-is-behind' 'UPLOAD-BEHIND' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '1.0.0-dev'
        BundleExists = $true; BundleMtime = $new; SourceMtime = $old
        UploadKnown = $true; UploadTime = $null }

    _expect 'combined' 'CHANGELOG-DRIFT+UPLOAD-BEHIND' @{
        SourceVersion = '1.0.0-dev'; ChangelogVersion = '0.9-dev'
        BundleExists = $true; BundleMtime = $new; SourceMtime = $old
        UploadKnown = $true; UploadTime = $old }

    # Parser fixtures.
    if ((Get-ChangelogTopVersion "# Title`n`n## 0.12.274-beta (2026-07-17) - x`n") -ne '0.12.274-beta') { $fail += 'changelog-parse: paren form' }
    if ((Get-ChangelogTopVersion "## [0.8.92] - 2026-07-17`n") -ne '0.8.92') { $fail += 'changelog-parse: bracket form' }
    if ((Get-ChangelogTopVersion "## v1.2.3-dev: notes`n") -ne '1.2.3-dev') { $fail += 'changelog-parse: v-prefix form' }
    if (-not (Test-ChangelogNotDeployed "## 0.3.74-dev - x [diagnostics-armed; not deployed]`n- body`n## 0.3.73-dev`n")) { $fail += 'nd-parse: header marker missed' }
    if (Test-ChangelogNotDeployed "## 0.3.74-dev - shipped`n- body`n## 0.3.73-dev`n") { $fail += 'nd-parse: false positive' }
    # Marker only in the 4th entry must NOT flag (top-3 window).
    if (Test-ChangelogNotDeployed "## a`n## b`n## c`n## d [not deployed]`n" 3) { $fail += 'nd-parse: 4th-entry leaked into top-3' }
    # Historical body prose ("verification only. NOT deployed, NOT uploaded" in a
    # Build subsection) must NOT flag - only header-line lifecycle markers count.
    if (Test-ChangelogNotDeployed "## 1.0.6 (2026-05-25) - tidy`n### Build`nVMBLauncher.exe build x -- verification only. NOT deployed, NOT uploaded.`n## 1.0.5`n") { $fail += 'nd-parse: body prose false positive' }

    if ($fail.Count -eq 0) {
        Write-Host "[check_pipeline_state -SelfTest] OK - verdict + parser fixtures pass." -ForegroundColor Green
        exit 0
    }
    Write-Host "[check_pipeline_state -SelfTest] FAIL:" -ForegroundColor Red
    foreach ($f in $fail) { Write-Host "  X $f" -ForegroundColor Red }
    exit 2
}

# ---------------------------------------------------------------------------
# Live run.
# ---------------------------------------------------------------------------
$repoRoot = (Resolve-Path $RepoRoot).Path
$inventoryPath = Join-Path $repoRoot 'tools\mod-inventory.psd1'
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    Write-Host "[check_pipeline_state] tools/mod-inventory.psd1 missing - cannot enumerate mods." -ForegroundColor DarkYellow
    exit 0
}
$inventory = Import-PowerShellDataFile -Path $inventoryPath
$mods = @($inventory.Mods)

$uploadKnown = Test-Path -LiteralPath $WorkshopLog
$uploadMap = @{}
if ($uploadKnown) { $uploadMap = Get-UploadMapFromLog $WorkshopLog }

$rows = @()
foreach ($m in $mods) {
    $dir = [string]$m.Dir
    $modRoot = Join-Path $repoRoot $dir

    # Source MOD_VERSION.
    $mainLua = Join-Path $modRoot "scripts\mods\$dir\$dir.lua"
    $sourceVer = $null
    if (Test-Path -LiteralPath $mainLua) {
        $lt = Read-FileUtf8 $mainLua
        if ($lt -match 'MOD_VERSION\s*=\s*"([^"]+)"') { $sourceVer = $matches[1] }
    }

    # CHANGELOG top version + [not deployed] marker in the top-3 entries.
    $clPath = Join-Path $modRoot 'CHANGELOG.md'
    $clVer = $null; $notDeployed = $false
    if (Test-Path -LiteralPath $clPath) {
        $ct = Read-FileUtf8 $clPath
        $clVer = Get-ChangelogTopVersion $ct
        $notDeployed = Test-ChangelogNotDeployed $ct 3
    }

    # Newest source mtime (scripts/) vs newest bundle mtime.
    $srcMtime = Get-NewestMtime (Join-Path $modRoot 'scripts')
    $bundleDir = Join-Path $modRoot 'bundleV2'
    $bundleExists = $false; $bundleMtime = $null
    if (Test-Path -LiteralPath $bundleDir) {
        $bundleMtime = Get-NewestMtime $bundleDir
        if ($bundleMtime) { $bundleExists = $true }
    }

    # Last Workshop upload for this mod's published_id.
    $pubId = Get-PublishedIdFromCfg (Join-Path $modRoot 'itemV2.cfg')
    if (-not $pubId) { $pubId = [string]$m.WorkshopId }
    $uploadTime = $null; $uploadKind = $null
    if ($uploadKnown -and $pubId -and $uploadMap.ContainsKey($pubId)) {
        $uploadTime = $uploadMap[$pubId].Time
        $uploadKind = $uploadMap[$pubId].Kind
    }

    $verdict = Get-PipelineVerdict @{
        SourceVersion    = $sourceVer
        ChangelogVersion = $clVer
        BundleExists     = $bundleExists
        BundleMtime      = $bundleMtime
        SourceMtime      = $srcMtime
        UploadKnown      = $uploadKnown
        UploadTime       = $uploadTime
    }

    $rows += [pscustomobject]@{
        Dir          = $dir
        Stream       = [string]$m.Stream
        SourceVer    = $sourceVer
        ChangelogVer = $clVer
        BundleExists = $bundleExists
        BundleMtime  = $bundleMtime
        SourceMtime  = $srcMtime
        UploadTime   = $uploadTime
        UploadKind   = $uploadKind
        PubId        = $pubId
        NotDeployed  = $notDeployed
        Verdict      = $verdict
    }
}

# ---- render ----
function Fmt-Time($t) { if ($t) { return $t.ToString('yyyy-MM-dd HH:mm') } else { return '' } }

$fmt = "{0,-31} {1,-6} {2,-14} {3,-14} {4,-6} {5,-16} {6,-3} {7}"
if (-not $Quiet) {
    Write-Host "[check_pipeline_state] pipeline-state ladder (advisory; mtime/timestamp heuristics - see header)" -ForegroundColor Cyan
    if (-not $uploadKnown) {
        Write-Host "  workshop_log.txt not found at '$WorkshopLog' - upload column is n/a (no failure)." -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host ($fmt -f 'MOD', 'STREAM', 'SOURCE', 'CHANGELOG', 'BUNDLE', 'LAST UPLOAD', 'ND', 'VERDICT') -ForegroundColor DarkGray
    Write-Host ($fmt -f ('-' * 31), '------', '------------', '------------', '------', '---------------', '---', '-------') -ForegroundColor DarkGray
}

$alarming = @()
foreach ($r in $rows) {
    $bundleCol = if (-not $r.BundleExists) { 'none' }
                 elseif ($r.SourceMtime -and $r.BundleMtime -and ($r.BundleMtime -lt $r.SourceMtime)) { 'STALE' }
                 else { 'fresh' }
    $uploadCol = if (-not $uploadKnown) { 'n/a' }
                 elseif ($r.UploadTime) { (Fmt-Time $r.UploadTime) + $(if ($r.UploadKind -eq 'nochange') { '*' } else { '' }) }
                 else { 'none' }
    $ndCol = if ($r.NotDeployed) { 'ND' } else { '' }
    $srcCol = if ($r.SourceVer) { $r.SourceVer } else { '?' }
    $clCol = if ($r.ChangelogVer) { $r.ChangelogVer } else { '?' }

    $line = $fmt -f $r.Dir, $r.Stream, $srcCol, $clCol, $bundleCol, $uploadCol, $ndCol, $r.Verdict
    $color = if ($r.Verdict -eq 'IN-SYNC') { 'Green' }
             elseif ($r.Verdict -like '*UPLOAD-BEHIND*') { 'Red' }
             else { 'Yellow' }
    if (-not $Quiet) { Write-Host $line -ForegroundColor $color }

    if ($r.Verdict -ne 'IN-SYNC') { $alarming += "$($r.Dir): $($r.Verdict) (source=$srcCol changelog=$clCol bundle=$bundleCol upload=$uploadCol)" }
}

# ---- summary ----
Write-Host ""
$ndRows = @($rows | Where-Object { $_.NotDeployed })
if ($alarming.Count -eq 0 -and $ndRows.Count -eq 0) {
    Write-Host "[check_pipeline_state] OK - all $($rows.Count) mods IN-SYNC; no [not deployed] markers." -ForegroundColor Green
} else {
    if ($alarming.Count -gt 0) {
        Write-Host "[check_pipeline_state] LADDER GAPS ($($alarming.Count)):" -ForegroundColor Yellow
        foreach ($a in $alarming) { Write-Host "  ! $a" -ForegroundColor Yellow }
    }
    if ($ndRows.Count -gt 0) {
        Write-Host "[check_pipeline_state] [not deployed] markers in top-3 CHANGELOG entries ($($ndRows.Count)):" -ForegroundColor Yellow
        foreach ($n in $ndRows) { Write-Host "  ! $($n.Dir): newest CHANGELOG entries still tagged [not deployed]" -ForegroundColor Yellow }
    }
    Write-Host ""
    Write-Host "[check_pipeline_state] advisory only - never blocks the gate. Read the ladder above." -ForegroundColor DarkGray
}

exit 0
