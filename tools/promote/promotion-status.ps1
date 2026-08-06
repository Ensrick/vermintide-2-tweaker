<#
.SYNOPSIS
    Reports how far each PUBLIC (stable) split-mod trails its *_dev sibling and
    loudly inventories dev issue references that have NOT reached public.

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
      3. Scans dev CHANGELOG entry headers for issue numbers and loudly inventories
         every reference absent from the public CHANGELOG, bound to the exact dev and
         public versions. The [crash] / 0-critical subset remains the -Strict gate.

    Read-only. Never writes. Run it before shipping public, and in CI, so a critical
    fix can't silently stay dev-only. Promote with tools/promote/promote.ps1.

.EXAMPLE
    pwsh tools/promote/promotion-status.ps1
    pwsh tools/promote/promotion-status.ps1 -Mod crafting_in_modded
    pwsh tools/promote/promotion-status.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    # Restrict to one public mod dir name (e.g. crafting_in_modded). Default: all pairs.
    [string]$Mod,
    # Also list every differing file (default: just the count + crash-fix flags).
    [switch]$Detailed,
    # Exit 1 if any crash/critical fix looks dev-only (for CI once CHANGELOGs cite issues
    # on promotion). Default: advisory, always exit 0.
    [switch]$Strict,
    # Pure, offline parser/report tests. Discovered explicitly by qa/run_selftests.ps1.
    [switch]$SelfTest
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

function Get-EntryHeaders([string]$text) {
    return @([regex]::Matches($text, '(?m)^##[ \t]+(?<header>[^\r\n]+)') | ForEach-Object {
        $_.Groups['header'].Value
    })
}

function Get-HeaderIssueNums([string]$text, [switch]$CriticalOnly) {
    $issues = @()
    foreach ($header in @(Get-EntryHeaders $text)) {
        if ($CriticalOnly -and $header -notmatch '\[crash\]' -and $header -notmatch '0-critical') {
            continue
        }
        $issues += @(Get-IssueNums $header)
    }
    return @($issues | Sort-Object -Unique)
}

function Get-StrandedIssueNums([string]$devText, [string]$pubText, [switch]$CriticalOnly) {
    $devIssues = @(Get-HeaderIssueNums $devText -CriticalOnly:$CriticalOnly)
    $publicIssues = @(Get-IssueNums $pubText)
    return @($devIssues | Where-Object { $publicIssues -notcontains $_ } | Sort-Object -Unique)
}

function Invoke-PromotionStatusSelfTest {
    $failed = @()
    $dev = @'
# Demo
## 0.2.3-dev - issue 139 bot leash fix
Details mention #999 but the body is not a release identity.
## 0.2.2-dev - issue 278 client crash [crash] [0-critical]
## 0.2.1-dev - no issue reference
'@
    $pub = @'
# Demo stable
## 0.2.1 - client crash
Promoted from issue 278.
'@

    $all = @(Get-StrandedIssueNums $dev $pub)
    if ($all.Count -ne 1 -or $all[0] -ne 139) {
        $failed += "all-issue report expected only #139; got $($all -join ',')"
    }
    $critical = @(Get-StrandedIssueNums $dev $pub -CriticalOnly)
    if ($critical.Count -ne 0) {
        $failed += "critical report should accept stable body citation for #278; got $($critical -join ',')"
    }
    $missingCritical = @(Get-StrandedIssueNums $dev '# no stable citation' -CriticalOnly)
    if ($missingCritical.Count -ne 1 -or $missingCritical[0] -ne 278) {
        $failed += "critical report expected planted #278; got $($missingCritical -join ',')"
    }
    $headers = @(Get-EntryHeaders $dev)
    if ($headers.Count -ne 3) {
        $failed += "header parser included prose/body content; expected 3, got $($headers.Count)"
    }

    if ($failed.Count -gt 0) {
        Write-Host '[promotion-status:selftest] FAILED' -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        return 2
    }
    Write-Host '[promotion-status:selftest] OK - broad advisory, critical strict, body citation, and header-boundary fixtures pass.' -ForegroundColor Green
    return 0
}

if ($SelfTest) { exit (Invoke-PromotionStatusSelfTest) }

$anyBacklog = $false
$reviewCount = 0
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
        $devText = Get-Content -Raw $devCl
        $pubText = Get-Content -Raw $pubCl
        $stranded = @(Get-StrandedIssueNums $devText $pubText)
        $unpromotedCritical = @(Get-StrandedIssueNums $devText $pubText -CriticalOnly)
        if ($stranded.Count -gt 0) {
            $reviewCount += $stranded.Count
            Write-Host ''
            Write-Host '  !!!!!!!!!!!!!!!!!!!!! STRANDED-FIX REVIEW !!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Yellow
            Write-Host ("  public {0} <- dev {1}: {2} dev issue reference(s) lack a public CHANGELOG citation" -f $pubVer, $devVer, $stranded.Count) -ForegroundColor Yellow
            Write-Host ("  REVIEW ISSUES: #{0}" -f ($stranded -join ', #')) -ForegroundColor Yellow
            Write-Host '  Promotion remains user-triggered; confirm scope before copying any dev work.' -ForegroundColor DarkGray
            Write-Host '  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!' -ForegroundColor Yellow
        }
        if ($unpromotedCritical.Count -gt 0) {
            $anyBacklog = $true
            Write-Host ("  CRITICAL REVIEW - dev crash/critical fix(es) whose issue is NOT cited in public CHANGELOG: {0}" -f ($unpromotedCritical -join ', ')) -ForegroundColor Red
            Write-Host  "     Confirm each reached public. (Cite the issue number in the public CHANGELOG on promotion" -ForegroundColor DarkGray
            Write-Host  "     -- as cim v0.8.34 does for #278 -- and this check becomes exact. Older rollup entries pre-date it.)" -ForegroundColor DarkGray
        } else {
            $criticalIssues = @(Get-HeaderIssueNums $devText -CriticalOnly)
            if ($criticalIssues.Count -gt 0) {
                Write-Host ("  OK - crash/critical fix issues from dev headers all cited in public CHANGELOG: {0}" -f ($criticalIssues -join ', ')) -ForegroundColor Green
            }
        }
    }
}

Write-Host ""
if ($anyBacklog) {
    Write-Host "RESULT: $reviewCount dev issue reference(s) need promotion review; crash/critical backlog is present." -ForegroundColor Red
    if ($Strict) { exit 1 }
    exit 0
} elseif ($reviewCount -gt 0) {
    Write-Host "RESULT: $reviewCount dev issue reference(s) need promotion review; no uncited crash/critical header was detected." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "RESULT: no dev issue references are missing from public CHANGELOGs." -ForegroundColor Green
    exit 0
}
