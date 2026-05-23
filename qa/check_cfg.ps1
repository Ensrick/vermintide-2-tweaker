# check_cfg.ps1 — validates every itemV2.cfg in the repo.
# Catches: tags=[] (ugc_tool 0x2 error), missing preview file, accidental public
# visibility, missing bug-reporting block, missing BMC link.
#
# See qa/CHECKS.md rows 8-14 for the bug classes this addresses.
#
# Exit codes: 0 = pass, 1 = warnings only, 2 = errors found.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$errors = @()
$warnings = @()

# Per-mod expected visibility (PROJECT_STANDARDS §workshop, memory entries).
# Anything not listed here defaults to friends_only — if you upload it with
# public, you better have authorized it.
$expectedVisibility = @{
    "chaos_wastes_tweaker"        = "public"
    "crafting_in_modded"          = "public"
    "general_tweaker"             = "public"
    "verminious_dreams_lighting"  = "public"
    "modded_progression"          = "private"
    # everything else: friends_only
}

$bmcSvg = "buy-me-coffee-icon.svg"
$bugReportMarker = "github.com/Ensrick/vermintide-2-tweaker/issues"

function Get-CfgFiles {
    Get-ChildItem -Path $repoRoot -Filter "itemV2.cfg" -Recurse -File `
        -ErrorAction SilentlyContinue `
        | Where-Object { $_.FullName -notlike "*\_archive\*" `
                    -and $_.FullName -notlike "*\bundleV2\*" `
                    -and $_.FullName -notlike "*\.build\*" `
                    -and $_.FullName -notlike "*\.temp\*" `
                    -and $_.FullName -notlike "*\_tmp\*" `
                    -and $_.FullName -notlike "*\.git\*" }
}

function Read-CfgText([string]$path) {
    # Per memory feedback_ps5_getcontent_utf8.md: Get-Content -Raw defaults to
    # Windows-1252 on PS5.1. Use .NET API for UTF-8 safety.
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

foreach ($cfgFile in Get-CfgFiles) {
    $modName = Split-Path (Split-Path $cfgFile.FullName -Parent) -Leaf
    $cfgText = Read-CfgText $cfgFile.FullName
    if (-not $Quiet) { Write-Host "Checking $modName/itemV2.cfg" -ForegroundColor DarkGray }

    # Row #8: tags = [] causes ugc_tool 0x2 first-upload error
    if ($cfgText -match 'tags\s*=\s*\[\s*\]') {
        $errors += "${modName}/itemV2.cfg: tags = [ ] present — drop it (causes ugc_tool 0x2)"
    }

    # Row #9: preview file referenced must exist
    if ($cfgText -match 'preview\s*=\s*"([^"]+)"') {
        $previewPath = Join-Path (Split-Path $cfgFile.FullName -Parent) $matches[1]
        if (-not (Test-Path $previewPath)) {
            $errors += "${modName}/itemV2.cfg: preview file '$($matches[1])' does not exist"
        }
    } else {
        $errors += "${modName}/itemV2.cfg: no preview= field"
    }

    # Row #12: visibility must match expected
    if ($cfgText -match 'visibility\s*=\s*"([^"]+)"') {
        $actualVis = $matches[1]
        $expectedVis = $expectedVisibility[$modName]
        if (-not $expectedVis) { $expectedVis = "friends_only" }
        if ($actualVis -ne $expectedVis) {
            $errors += "${modName}/itemV2.cfg: visibility='$actualVis' but expected '$expectedVis' (per qa/check_cfg.ps1 whitelist)"
        }
    }

    # Row #13: description must include bug-reporting block (post-2026-05-22 convention)
    if ($cfgText -notmatch [regex]::Escape($bugReportMarker)) {
        $warnings += "${modName}/itemV2.cfg: description doesn't mention GitHub issues URL (PROJECT_STANDARDS §7 — bug-reporting block missing)"
    }

    # Row #14: BMC link must be intact (per user direction, BMC SVG block stays)
    if ($cfgText -notmatch [regex]::Escape($bmcSvg)) {
        $warnings += "${modName}/itemV2.cfg: BMC SVG link missing (reference_bmc_button.md)"
    }

    # Sanity: title must exist
    if ($cfgText -notmatch 'title\s*=\s*"[^"]+"') {
        $errors += "${modName}/itemV2.cfg: no title= field"
    }

    # Sanity: published_id should be a long literal
    if ($cfgText -notmatch 'published_id\s*=\s*\d+L') {
        $warnings += "${modName}/itemV2.cfg: published_id missing or malformed (expected NNNL)"
    }
}

# Report
Write-Host ""
if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "[check_cfg] OK — all cfgs pass." -ForegroundColor Green
    exit 0
}

if ($warnings.Count -gt 0) {
    Write-Host "[check_cfg] WARNINGS:" -ForegroundColor Yellow
    foreach ($w in $warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
}
if ($errors.Count -gt 0) {
    Write-Host "[check_cfg] ERRORS:" -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "  X $e" -ForegroundColor Red }
    exit 2
}
exit 1
