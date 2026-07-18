<#
.SYNOPSIS
    Full-rollup port of a *_dev split mod into its public stable sibling: id-normalize
    the Lua source, set the release version, preserve public Workshop identity. DryRun
    by default. Does NOT build/deploy/upload -- run ship.ps1 after, on the ship signal.

.DESCRIPTION
    Mode B of docs/PROMOTION_PROCESS.md. Use ONLY when the user has signed off that the
    WHOLE dev line is release-ready. For a single hotfix, use Mode A (fix dev + public in
    the same session with the same targeted diff) -- do NOT full-rollup for one fix.

    What it does (with -Apply):
      - For each dev Lua file, id-normalize (dev dir/id -> public dir/id) and write to the
        mapped public path (main/_data/_localization renamed; feature modules keep names).
      - Set the public MOD_VERSION to -Version (a clean, no-suffix release string).
      - Leaves itemV2.cfg UNTOUCHED: published_id + visibility are user-dictated identity,
        never copied from dev (the upload gate aborts on a published_id collision).
      - Verifies the public dir is grep-clean of any dev identity afterward.

    What it does NOT do (deliberately, surfaced as warnings for a human):
      - Add dev-only files that have no public equivalent (e.g. _diag_probe.lua) unless
        -IncludeNew. Dev-only diagnostics must not silently land in public.
      - Reintroduce lifecycle/status tags. Every stream is already required to be
        clean by LOCALIZATION_STANDARD section 13 and qa/check_loc_tags.ps1.

.EXAMPLE
    pwsh tools/promote/promote.ps1 -Mod crafting_in_modded                    # DryRun plan
    pwsh tools/promote/promote.ps1 -Mod crafting_in_modded -Apply -Version 0.9.0
#>
[CmdletBinding()]
param(
    # Public mod dir name (e.g. crafting_in_modded). Its *_dev sibling is the source.
    [Parameter(Mandatory)] [string]$Mod,
    # Clean release version for public (no -dev suffix). Required with -Apply.
    [string]$Version,
    # Actually write. Without it, prints the plan and changes nothing.
    [switch]$Apply,
    # Also copy dev-only files that have no public equivalent (default: warn + skip).
    [switch]$IncludeNew
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$map = @{
    'chaos_wastes_tweaker'        = @{ Dev = 'chaos_wastes_tweaker_dev';       PubId = 'ct';  DevId = 'ct_dev' }
    'crafting_in_modded'          = @{ Dev = 'crafting_in_modded_dev';         PubId = 'cim'; DevId = 'cim_dev' }
    'general_tweaker'             = @{ Dev = 'general_tweaker_dev';            PubId = 'gt';  DevId = 'gt_dev' }
    'gui_tweaker'                 = @{ Dev = 'gui_tweaker_dev';               PubId = 'gut'; DevId = 'gut_dev' }
    'verminious_dreams_lighting'  = @{ Dev = 'verminious_dreams_lighting_dev'; PubId = 'verminious_dreams_lighting'; DevId = 'verminious_dreams_lighting_dev' }
}
if (-not $map.ContainsKey($Mod)) { throw "Unknown split mod '$Mod'. Known: $($map.Keys -join ', ')" }
$p = $map[$Mod]
$pubDir = Join-Path $repo $Mod
$devDir = Join-Path $repo $p.Dev
if (-not (Test-Path $devDir)) { throw "Dev dir not found: $devDir" }
if ($Apply -and -not $Version) { throw "-Apply requires -Version (a clean, no-suffix release string)." }
if ($Version -and $Version -match '-') { throw "-Version must be a clean release string with NO -dev/-alpha/-beta suffix." }

$devSrc = Join-Path $devDir "scripts/mods/$($p.Dev)"
$pubSrc = Join-Path $pubDir "scripts/mods/$Mod"

function Convert-Id([string]$text) {
    # Longest-first explicit replacements (issue 684 defect 1): '_' is a word char,
    # so a bare \b<dev>\b never matches inside <dev>_data / <dev>_localization
    # (the require/dofile module names) and those sites leaked into stable
    # unconverted. Replace the known suffixed forms first, then the bare ids.
    # Any exotic suffix the list does not know is caught by the grep-clean
    # verify below (defect 2 fix) and surfaced for a human.
    $replacements = @(
        @{ From = $p.Dev   + '_data';         To = $Mod     + '_data' }
        @{ From = $p.Dev   + '_localization'; To = $Mod     + '_localization' }
        @{ From = $p.Dev;                     To = $Mod }
        @{ From = $p.DevId + '_data';         To = $p.PubId + '_data' }
        @{ From = $p.DevId + '_localization'; To = $p.PubId + '_localization' }
        @{ From = $p.DevId;                   To = $p.PubId }
    )
    foreach ($r in $replacements) {
        $text = [regex]::Replace($text, "\b" + [regex]::Escape($r.From) + "\b", $r.To)
    }
    return $text
}

$mode = if ($Apply) { "APPLY" } else { "DRY-RUN (no changes written)" }
Write-Host ""
Write-Host ("Promote  {0}  ->  {1}   [{2}]" -f $p.Dev, $Mod, $mode) -ForegroundColor Cyan
if ($Version) { Write-Host ("  target public version: {0}" -f $Version) }
Write-Host ""

$devFiles = Get-ChildItem -Path $devSrc -Filter *.lua -File
$update = @(); $new = @()
foreach ($f in $devFiles) {
    $pubName = $f.Name -replace [regex]::Escape($p.Dev), $Mod
    $pubPath = Join-Path $pubSrc $pubName
    if (Test-Path $pubPath) { $update += @{ Dev = $f; PubName = $pubName; PubPath = $pubPath } }
    else                    { $new    += @{ Dev = $f; PubName = $pubName; PubPath = $pubPath } }
}

Write-Host ("UPDATE {0} existing public file(s):" -f $update.Count) -ForegroundColor Yellow
foreach ($u in $update) { Write-Host ("   {0}  ->  {1}" -f $u.Dev.Name, $u.PubName) }
if ($new.Count) {
    Write-Host ("NEW-IN-DEV {0} file(s) with no public equivalent:" -f $new.Count) -ForegroundColor Yellow
    foreach ($n in $new) {
        $tag = if ($IncludeNew) { "will ADD" } else { "SKIP (pass -IncludeNew to add; verify it is not a dev-only diagnostic)" }
        Write-Host ("   {0}  ->  {1}   [{2}]" -f $n.Dev.Name, $n.PubName, $tag) -ForegroundColor DarkGray
    }
}

if (-not $Apply) {
    Write-Host ""
    Write-Host "DryRun only. Re-run with -Apply -Version <x.y.z> to write. Then review the public" -ForegroundColor DarkGray
    Write-Host "CHANGELOG + _localization dev tags, and ship on the fresh ship signal." -ForegroundColor DarkGray
    exit 0
}

# ---- APPLY ----
$written = 0
foreach ($u in $update) {
    $out = Convert-Id (Get-Content -Raw $u.Dev.FullName)
    Set-Content -Path $u.PubPath -Value $out -NoNewline -Encoding utf8
    $written++
}
if ($IncludeNew) {
    foreach ($n in $new) {
        $out = Convert-Id (Get-Content -Raw $n.Dev.FullName)
        Set-Content -Path $n.PubPath -Value $out -NoNewline -Encoding utf8
        $written++
    }
}

# Set the public MOD_VERSION.
$mainLua = Join-Path $pubSrc "$Mod.lua"
if (Test-Path $mainLua) {
    $mc = Get-Content -Raw $mainLua
    $mc = [regex]::Replace($mc, 'local\s+MOD_VERSION\s*=\s*"[^"]*"', "local MOD_VERSION = `"$Version`"")
    Set-Content -Path $mainLua -Value $mc -NoNewline -Encoding utf8
}

# Verify grep-clean of dev identity. NO -SimpleMatch: the pattern is a regex
# alternation of two pre-escaped literals; -SimpleMatch made the '|' literal, so
# the verify matched nothing and always reported clean (issue 684 defect 2).
$leak = Select-String -Path (Join-Path $pubSrc '*.lua') -Pattern ([regex]::Escape($p.Dev) + '|' + [regex]::Escape($p.DevId)) -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("Wrote {0} public file(s); set MOD_VERSION = {1}." -f $written, $Version) -ForegroundColor Green
if ($leak) {
    Write-Host "!! DEV IDENTITY LEAK -- public source still references the dev id:" -ForegroundColor Red
    # No Select-Object -First here: it stops the upstream pipeline and has killed
    # outer pipelines before (memory: ship.ps1). Slice the collected array instead.
    $leakArr = @($leak)
    $show = if ($leakArr.Count -gt 20) { $leakArr[0..19] } else { $leakArr }
    foreach ($l in $show) { Write-Host ("   {0}:{1}" -f $l.Filename, $l.LineNumber) -ForegroundColor Red }
    if ($leakArr.Count -gt 20) { Write-Host ("   ... and {0} more" -f ($leakArr.Count - 20)) -ForegroundColor Red }
    Write-Host "   Resolve before building (e.g. an id embedded with a suffix the normalizer does not know)." -ForegroundColor Red
    exit 1
}
Write-Host "grep-clean: no dev identity in public source." -ForegroundColor Green
Write-Host ""
Write-Host "NEXT (manual, deliberate):" -ForegroundColor Cyan
Write-Host "  1. Write the public CHANGELOG entry -- CITE the issue number(s) for any crash fix."
Write-Host "  2. Run qa/check_loc_tags.ps1: player-facing lifecycle metadata is forbidden in every stream."
Write-Host "  3. Confirm itemV2.cfg identity (published_id, visibility) is unchanged."
Write-Host "  4. promotion-status.ps1 -Mod $Mod   (crash issues should read OK)."
Write-Host "  5. On the fresh ship signal:  ship.ps1 -Mod $Mod -AllowPublic"
exit 0
