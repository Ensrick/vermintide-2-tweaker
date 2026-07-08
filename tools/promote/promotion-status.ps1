<#
.SYNOPSIS
    Reports how far each PUBLIC (stable) split-mod trails its *_dev sibling, and
    flags crash/critical fixes that live in dev but have NOT reached public.

.DESCRIPTION
    The dev/stable split (CLAUDE.md "Dev/stable split workflow") runs two Workshop
    items per mod: a friends-only `*_dev` and a public stable. Fixes land in dev and
    are PROMOTED to public by a manual id-normalizing port. The recurring failure mode
    is a fix rotting in dev and never reaching public users (issue #278: the cim
    crafted-CWV CTD fix sat in cim_dev v0.8.51 while public cim v0.8.33 kept crashing).

    This tool makes that visible. For each split pair it:
      1. Prints public vs dev MOD_VERSION.
      2. Normalizes dev source (dev id -> public id, strips MOD_VERSION) and diffs it
         against the public source, per file -> how far public trails dev (magnitude).
      3. Scans the dev CHANGELOG for entries tagged [crash] / 0-critical, extracts their
         issue numbers, and flags any that do NOT appear in the public CHANGELOG:
         a POSSIBLE UNPROMOTED CRASH FIX -- the danger case.

    Read-only. Never writes. Run it before shipping public, and in CI, so a critical
    fix can't silently stay dev-only. Promote with tools/promote/promote.ps1.

.EXAMPLE
    pwsh tools/promote/promotion-status.ps1
    pwsh tools/promote/promotion-status.ps1 -Mod crafting_in_modded
#>
[CmdletBinding()]
param(
    # Restrict to one public mod dir name (e.g. crafting_in_modded). Default: all pairs.
    [string]$Mod,
    # Also list every differing file (default: just the count + crash-fix flags).
    [switch]$Detailed,
    # Exit 1 if any crash/critical fix looks dev-only (for CI once CHANGELOGs cite issues
    # on promotion). Default: advisory, always exit 0.
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Split-mod pairs: public dir + id, dev dir + id. (vdl's id == its dir name.)
$pairs = @(
    @{ Pub = 'chaos_wastes_tweaker';        Dev = 'chaos_wastes_tweaker_dev';        PubId = 'ct';                        DevId = 'ct_dev' }
    @{ Pub = 'crafting_in_modded';          Dev = 'crafting_in_modded_dev';          PubId = 'cim';                       DevId = 'cim_dev' }
    @{ Pub = 'general_tweaker';             Dev = 'general_tweaker_dev';             PubId = 'gt';                        DevId = 'gt_dev' }
    @{ Pub = 'gui_tweaker';                 Dev = 'gui_tweaker_dev';                 PubId = 'gut';                       DevId = 'gut_dev' }
    @{ Pub = 'verminious_dreams_lighting';  Dev = 'verminious_dreams_lighting_dev';  PubId = 'verminious_dreams_lighting'; DevId = 'verminious_dreams_lighting_dev' }
)
if ($Mod) { $pairs = $pairs | Where-Object { $_.Pub -eq $Mod -or $_.Dev -eq $Mod } }

function Get-ModVersion([string]$luaPath) {
    if (-not (Test-Path $luaPath)) { return '?' }
    $m = [regex]::Match((Get-Content -Raw $luaPath), 'local\s+MOD_VERSION\s*=\s*"([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value } else { return '?' }
}

# Normalize dev source so only genuine logic differences remain: dev dir/id -> public,
# and drop the MOD_VERSION line (versions always differ by design).
function Normalize([string]$text, $p) {
    $t = $text
    $t = [regex]::Replace($t, "\b" + [regex]::Escape($p.Dev)   + "\b", $p.Pub)
    $t = [regex]::Replace($t, "\b" + [regex]::Escape($p.DevId) + "\b", $p.PubId)
    $t = [regex]::Replace($t, 'local\s+MOD_VERSION\s*=\s*"[^"]*"', 'MOD_VERSION')
    # normalize line endings so CRLF/LF drift is not counted as a change
    return ($t -replace "`r`n", "`n")
}

# Issue numbers from a chunk of CHANGELOG text ("issue 278" or "#278").
function Get-IssueNums([string]$text) {
    [regex]::Matches($text, '(?:issue\s+|#)(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
}

$anyBacklog = $false
foreach ($p in $pairs) {
    $pubDir = Join-Path $repo $p.Pub
    $devDir = Join-Path $repo $p.Dev
    if (-not (Test-Path $devDir)) { continue }

    $pubMain = Join-Path $pubDir "scripts/mods/$($p.Pub)/$($p.Pub).lua"
    $devMain = Join-Path $devDir "scripts/mods/$($p.Dev)/$($p.Dev).lua"
    $pubVer = Get-ModVersion $pubMain
    $devVer = Get-ModVersion $devMain

    Write-Host ""
    Write-Host ("=" * 78)
    Write-Host ("  {0}" -f $p.Pub) -ForegroundColor Cyan
    Write-Host ("  public {0}   <-   dev {1}" -f $pubVer, $devVer)
    Write-Host ("=" * 78)

    # ---- source-truth diff (magnitude public trails dev) ----
    $devLua = Get-ChildItem -Path (Join-Path $devDir "scripts/mods/$($p.Dev)") -Filter *.lua -File -ErrorAction SilentlyContinue
    $differ = @(); $devOnly = @(); $same = 0
    foreach ($f in $devLua) {
        $pubName = $f.Name -replace [regex]::Escape($p.Dev), $p.Pub
        $pubFile = Join-Path $pubDir "scripts/mods/$($p.Pub)/$pubName"
        if (-not (Test-Path $pubFile)) { $devOnly += $pubName; continue }
        $devN = Normalize (Get-Content -Raw $f.FullName) $p
        $pubN = (Get-Content -Raw $pubFile) -replace 'local\s+MOD_VERSION\s*=\s*"[^"]*"', 'MOD_VERSION' -replace "`r`n", "`n"
        if ($devN -eq $pubN) { $same++ }
        else {
            $dn = ($devN -split "`n"); $pn = ($pubN -split "`n")
            $delta = (Compare-Object $pn $dn | Measure-Object).Count
            $differ += [pscustomobject]@{ File = $pubName; Lines = $delta }
        }
    }
    if ($differ.Count -eq 0 -and $devOnly.Count -eq 0) {
        Write-Host "  SOURCE: public is up to date with dev (normalized)." -ForegroundColor Green
    } else {
        Write-Host ("  SOURCE: public trails dev in {0} file(s); {1} identical." -f $differ.Count, $same) -ForegroundColor Yellow
        if ($Detailed) {
            foreach ($d in ($differ | Sort-Object Lines -Descending)) {
                Write-Host ("           {0,-40} ~{1} changed line(s)" -f $d.File, $d.Lines)
            }
            foreach ($o in $devOnly) { Write-Host ("           {0,-40} dev-only (not promoted)" -f $o) -ForegroundColor DarkGray }
        }
    }

    # ---- crash/critical fixes stranded in dev (the danger) ----
    $devCl = Join-Path $devDir 'CHANGELOG.md'
    $pubCl = Join-Path $pubDir 'CHANGELOG.md'
    if ((Test-Path $devCl) -and (Test-Path $pubCl)) {
        # Scan ENTRY HEADERS only (the "## X.Y.Z - issue N: ... [crash]" line) -- the
        # PRIMARY fix of each dev version. Scanning bodies pulls in cross-ref/Refs noise.
        $devEntries = ((Get-Content -Raw $devCl) -split "(?m)^## ")
        $crashIssues = @()
        foreach ($e in $devEntries) {
            $hdr = ($e -split "`n", 2)[0]
            if ($hdr -match '\[crash\]' -or $hdr -match '0-critical') { $crashIssues += Get-IssueNums $hdr }
        }
        $crashIssues = $crashIssues | Sort-Object -Unique
        $pubIssues = Get-IssueNums (Get-Content -Raw $pubCl)
        $unpromoted = $crashIssues | Where-Object { $pubIssues -notcontains $_ }
        if ($unpromoted) {
            $anyBacklog = $true
            Write-Host ("  REVIEW - dev crash/critical fix(es) whose issue is NOT cited in public CHANGELOG: {0}" -f ($unpromoted -join ', ')) -ForegroundColor Yellow
            Write-Host  "     Confirm each reached public. (Cite the issue number in the public CHANGELOG on promotion" -ForegroundColor DarkGray
            Write-Host  "     -- as cim v0.8.34 does for #278 -- and this check becomes exact. Older rollup entries pre-date it.)" -ForegroundColor DarkGray
        } elseif ($crashIssues) {
            Write-Host ("  OK - crash/critical fix issues from dev headers all cited in public CHANGELOG: {0}" -f ($crashIssues -join ', ')) -ForegroundColor Green
        }
    }
}

Write-Host ""
if ($anyBacklog) {
    Write-Host "RESULT: review the flagged dev crash/critical fixes above; confirm each reached public." -ForegroundColor Yellow
    if ($Strict) { exit 1 }
    exit 0
} else {
    Write-Host "RESULT: no unpromoted crash/critical fixes detected." -ForegroundColor Green
    exit 0
}
