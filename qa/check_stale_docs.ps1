# check_stale_docs.ps1 — scans audit/review markdown files, warns about
# 30+ day-old docs without a SUPERSEDED banner.
#
# See qa/CHECKS.md row 49.
# See PROJECT_STANDARDS.md §7.2 for the banner format.
#
# Exit codes: 0 = pass, 1 = stale-but-OK warning, 2 = stale without banner.
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

# Report
Write-Host ""
if ($stale.Count -eq 0) {
    Write-Host "[check_stale_docs] OK — no audit/review markdowns are stale (>$StaleDays days without banner)." -ForegroundColor Green
    exit 0
}

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
    exit 1
}

Write-Host ""
Write-Host "Run with -Fix to auto-prepend banners. Or manually update each doc per PROJECT_STANDARDS §7.2." -ForegroundColor DarkYellow
exit 2
