# check_stale_docs.ps1 — scans audit/review markdown files, warns about
# docs older than $StaleDays (default 14) without a SUPERSEDED banner.
#
# See qa/CHECKS.md row 49.
# See PROJECT_STANDARDS.md §7.2 for the banner format.
#
# Exit codes: 0 = pass, 1 = warning (staleness -Fix applied, or a banner'd
#             snapshot found outside _archive/ per issue #502), 2 = stale
#             without banner. Advisory in run_all (issue #429) either way.
#
# Scan 2 (issue #502): a doc carrying the snapshot banner
# ("...this snapshot is from...") belongs in _archive/docs/; this flags any that
# do not. Head-only match (first 12 lines) so format docs that quote the banner
# are not false positives; CODE_REVIEW.md is exempt (mandatory canonical doc).
#
# Scan 3 (issue #432): pointer-stub link integrity. A doc HEAD carrying a
# supersession/pointer banner (SUPERSEDED / moved to / merged into) must link an
# owner doc that still exists; this flags a markdown .md link that resolves to no
# file (a dangling stub from a later rename/move). Time-independent, advisory.
#
# Usage:
#   .\check_stale_docs.ps1              # report only
#   .\check_stale_docs.ps1 -Fix         # auto-prepend SUPERSEDED banner to stale docs

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$Fix,
    [int]$StaleDays = 14
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$stale = @()
$today = Get-Date

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Has-SupersededBanner([string]$text) {
    # Per PROJECT_STANDARDS §7.2, banner contains "SUPERSEDED" inside a blockquote
    # within the first 10 lines of the doc. Various decorators tolerated
    # (⚠, **, [!WARNING] blocks, etc.).
    $head = ($text -split "`n" | Select-Object -First 10) -join "`n"
    return ($head -match '(?i)SUPERSEDED')
}

function Get-DocDateHint([string]$text) {
    # Find ALL YYYY-MM-DD patterns in the first 30 lines and return the EARLIEST.
    # Docs often have a title date and later "updated YYYY-MM-DD" notes; we want
    # the oldest because that's the canonical snapshot age.
    $head = ($text -split "`n" | Select-Object -First 30) -join "`n"
    $matches = [regex]::Matches($head, '(\d{4}-\d{2}-\d{2})')
    if ($matches.Count -eq 0) { return $null }
    $earliest = $null
    foreach ($m in $matches) {
        try {
            $dt = [DateTime]::ParseExact($m.Groups[1].Value, 'yyyy-MM-dd', $null)
            if ($null -eq $earliest -or $dt -lt $earliest) { $earliest = $dt }
        } catch { }
    }
    return $earliest
}

function Find-AuditDocs {
    $candidates = @()
    $patterns = @("*AUDIT*.md", "*REVIEW*.md", "POSTMORTEM*.md", "*audit*.md")
    foreach ($pat in $patterns) {
        Get-ChildItem -Path $repoRoot -Filter $pat -Recurse -File -ErrorAction SilentlyContinue `
            | Where-Object {
                $p = $_.FullName
                $p -notlike "*\_archive\*" -and $p -notlike "*\bundleV2\*" -and $p -notlike "*\.build\*" `
                    -and $p -notlike "*\.git\*" -and $p -notlike "*\Vermintide-2-Source-Code\*"
            } | ForEach-Object { $candidates += $_ }
    }
    # Dedupe
    return $candidates | Sort-Object FullName -Unique
}

foreach ($doc in Find-AuditDocs) {
    $text = Read-FileUtf8 $doc.FullName
    $relPath = $doc.FullName.Substring($repoRoot.Length + 1)
    if (-not $Quiet) { Write-Host "Scanning $relPath" -ForegroundColor DarkGray }

    if (Has-SupersededBanner $text) {
        # Already banner'd — skip
        continue
    }

    $docDate = Get-DocDateHint $text
    if (-not $docDate) { $docDate = $doc.LastWriteTime }

    $ageDays = ($today - $docDate).Days
    if ($ageDays -gt $StaleDays) {
        $stale += [PSCustomObject]@{
            Path = $relPath
            FullPath = $doc.FullName
            AgeDays = $ageDays
            DocDate = $docDate.ToString("yyyy-MM-dd")
        }
    }
}

# Report (staleness scan)
Write-Host ""
$exitCode = 0
if ($stale.Count -eq 0) {
    Write-Host "[check_stale_docs] OK — no audit/review markdowns are stale (>$StaleDays days without banner)." -ForegroundColor Green
} else {
    Write-Host "[check_stale_docs] $($stale.Count) stale doc(s) without SUPERSEDED banner:" -ForegroundColor Yellow
    foreach ($s in $stale) {
        Write-Host "  ! $($s.Path) — $($s.AgeDays) days old (dated $($s.DocDate))" -ForegroundColor Yellow
    }

    if ($Fix) {
        Write-Host ""
        Write-Host "Applying SUPERSEDED banners (..-Fix mode)..." -ForegroundColor Cyan
        foreach ($s in $stale) {
            $banner = @"
> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from $($s.DocDate) ($($s.AgeDays) days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to ``_archive/audits/$($s.DocDate)/``.

"@
            $text = Read-FileUtf8 $s.FullPath
            $new = $banner + $text
            [System.IO.File]::WriteAllText($s.FullPath, $new, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  ✓ Banner added: $($s.Path)" -ForegroundColor Green
        }
        $exitCode = 1
    } else {
        Write-Host ""
        Write-Host "Run with -Fix to auto-prepend banners. Or manually update each doc per PROJECT_STANDARDS §7.2." -ForegroundColor DarkYellow
        $exitCode = 2
    }
}

# --- Banner-placement scan (issue #502) -----------------------------------
# Inverse of the staleness scan above: that one flags UN-banner'd stale docs;
# this one flags docs that DO carry the snapshot banner ("...this snapshot is
# from...") but still sit OUTSIDE _archive/. Once a doc is banner'd as a
# point-in-time snapshot it belongs in _archive/docs/ (a stub stays at the old
# path only where inbound links exist). Match is restricted to the doc HEAD
# (first 12 lines) so prose that merely QUOTES the banner format
# (PROJECT_STANDARDS.md section 7.2) is not a false positive. CODE_REVIEW.md is
# exempt: PROJECT_STANDARDS section 7.1 makes it a mandatory per-mod canonical
# doc, so a staleness banner there means "refresh due", not "archive me".
$misplaced = @()
Get-ChildItem -Path $repoRoot -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue `
    | Where-Object {
        $p = $_.FullName
        $p -notlike "*\_archive\*" -and $p -notlike "*\bundleV2\*" -and $p -notlike "*\.build\*" `
            -and $p -notlike "*\.git\*" -and $p -notlike "*\Vermintide-2-Source-Code\*" `
            -and $_.Name -ne "CODE_REVIEW.md"
    } | ForEach-Object {
        $mtext = Read-FileUtf8 $_.FullName
        $mhead = ($mtext -split "`n" | Select-Object -First 12) -join "`n"
        if ($mhead -match "this snapshot is from") {
            $misplaced += $_.FullName.Substring($repoRoot.Length + 1)
        }
    }

# Drop gitignored candidates: the repo treats **/AUDIT_*.md (and similar) as
# ephemeral local docs (.gitignore), and an untracked file cannot be archived
# via `git mv`, so flagging it is not actionable. Only surface TRACKED docs a
# maintainer can actually move. Degrade gracefully if git is unavailable.
if ($misplaced.Count -gt 0 -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $tracked = @()
    foreach ($rel in $misplaced) {
        & git -C $repoRoot check-ignore -q -- "$rel" 2>$null
        if ($LASTEXITCODE -ne 0) { $tracked += $rel }   # exit != 0 => NOT ignored
    }
    $misplaced = @($tracked)
}

if ($misplaced.Count -gt 0) {
    Write-Host ""
    Write-Host "[check_stale_docs] $($misplaced.Count) doc(s) carry a SUPERSEDED snapshot banner OUTSIDE _archive/ (issue #502 - move to _archive/docs/):" -ForegroundColor Yellow
    foreach ($m in ($misplaced | Sort-Object)) {
        Write-Host "  ! $m" -ForegroundColor Yellow
    }
    Write-Host "  git mv each to _archive/docs/<mirrored path>; leave a 2-line pointer stub only where inbound links exist." -ForegroundColor DarkYellow
    if ($exitCode -lt 1) { $exitCode = 1 }
}

# --- Pointer-stub link-integrity scan (issue #432) -------------------------
# The #432 consolidation left ~15 pointer stubs (TODO/WORK_ITEMS/TESTING_STATUS/
# WEAPONS + the root topic docs moved under docs/) whose whole job is to keep an
# old path resolvable via a "moved to / merged into / SUPERSEDED" banner linking
# the new owner doc. If an owner doc is later renamed or moved without updating
# the stub, the stub silently dangles - the exact rot the consolidation ended.
# This flags any supersession/pointer banner in a doc HEAD whose markdown link
# target (a .md path) resolves to no file, checked relative to BOTH the stub's
# own directory and the repo root. Zero calendar dependence, so no staleness
# noise; ADVISORY only (PROJECT_STANDARDS section 7.11).
$dangling = @()
Get-ChildItem -Path $repoRoot -Filter "*.md" -Recurse -File -ErrorAction SilentlyContinue `
    | Where-Object {
        $p = $_.FullName
        $p -notlike "*\_archive\*" -and $p -notlike "*\bundleV2\*" -and $p -notlike "*\.build\*" `
            -and $p -notlike "*\.git\*" -and $p -notlike "*\Vermintide-2-Source-Code\*"
    } | ForEach-Object {
        $doc = $_
        $content = Read-FileUtf8 $doc.FullName
        $head = (($content -split "`n") | Select-Object -First 10) -join "`n"
        if ($head -notmatch '(?i)SUPERSEDED|moved to|merged into') { return }
        foreach ($lm in [regex]::Matches($head, '\]\(([^)]+?\.md)(#[^)]*)?\)')) {
            $target = $lm.Groups[1].Value
            if ($target -match '^https?://') { continue }
            $fromDir = Join-Path $doc.DirectoryName $target
            $fromRoot = Join-Path $repoRoot $target
            if (-not (Test-Path -LiteralPath $fromDir) -and -not (Test-Path -LiteralPath $fromRoot)) {
                $dangling += [PSCustomObject]@{
                    Path = $doc.FullName.Substring($repoRoot.Length + 1)
                    Target = $target
                }
            }
        }
    }

if ($dangling.Count -gt 0) {
    Write-Host ""
    Write-Host "[check_stale_docs] $($dangling.Count) pointer stub(s) linking a MISSING owner doc (issue #432 - fix the link or restore the target):" -ForegroundColor Yellow
    foreach ($d in ($dangling | Sort-Object Path)) {
        Write-Host "  ! $($d.Path) -> $($d.Target)" -ForegroundColor Yellow
    }
    if ($exitCode -lt 1) { $exitCode = 1 }
}

exit $exitCode
