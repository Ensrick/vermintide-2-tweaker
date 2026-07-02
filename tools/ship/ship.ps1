# tools/ship/ship.ps1
#
# CANONICAL one-shot RELEASE path for a single VT2 mod in this monorepo:
#   build + deploy + Workshop upload + GitHub release + hash/upload verification.
#
# Prefer this over hand-chaining `VMBLauncher.exe all <mod>` and
# `tools\publish-release\publish-release.ps1` separately. It runs both, then
# PROVES the deploy and upload actually transferred (the two steps that silently
# lie) so a release can't be quietly skipped.
#
# Usage:
#   .\tools\ship\ship.ps1 -Mod general_tweaker_dev
#   .\tools\ship\ship.ps1 -Mod chaos_wastes_tweaker -AllowPublic        # public Workshop item
#   .\tools\ship\ship.ps1 -Mod gui_tweaker_dev -NoRemote                # skip the PC-B push
#   .\tools\ship\ship.ps1 -Mod gui_tweaker_dev -SkipGitHub              # local ship only, no GH release
#
# WHY THIS SCRIPT EXISTS -- hard-won facts encoded below (do not "simplify" them away):
#
#  * `VMBLauncher.exe all <mod>` = build + deploy + upload. `deploy` is a
#    hash-verified LOCAL copy of `<mod>\bundleV2\*.mod_bundle` + the `.mod` into
#    `...\steamapps\workshop\content\552500\<published_id>\`. `upload` is the
#    ugc_tool push to the Steam Workshop SERVER. Public mods require
#    `--allow-public`; `--no-remote` skips the remote (PC-B) deploy target.
#
#  * ugc_tool prints "Upload finished" and exits 0 EVEN WHEN NOTHING TRANSFERRED.
#    "Upload finished" tells you nothing. The SOURCE OF TRUTH is
#    `C:\Program Files (x86)\Steam\logs\workshop_log.txt`:
#       "Uploaded new content ( ManifestID <N> ) for item <id>"  = real push
#       "No content change detected for item <id>"               = server already had it
#    (acceptable only when the local deploy hashes already match the server bundle).
#
#  * `published_id` lives in `<mod>\itemV2.cfg` as `published_id = <N>L;`.
#
#  * CRITICAL (the session-long trap): Steam re-downloads a SELF-AUTHORED Workshop
#    item ONLY on a FULL STEAM RESTART -- NOT on a game relaunch, and NOT via
#    `deploy` (Steam reconciles the deploy folder back to its cached manifest if the
#    client cache is behind). So after a successful ship the AUTHOR MUST fully exit
#    and restart Steam (tray icon -> Exit, reopen) before launching the game, or the
#    running game keeps serving the old cached bundle. The boxed reminder at the end
#    says exactly this.
#
# Every step fails loudly (red message + non-zero exit) on the first problem.
#
# NOTE: comments + strings are ASCII only -- PowerShell parses .ps1 as Windows-1252
# by default and mangles em-dashes / box-drawing glyphs (memory:
# feedback_ps5_getcontent_utf8). Use '-' and '=' for separators, never Unicode.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Mod,
    [switch]$AllowPublic,
    [switch]$NoRemote,
    [switch]$SkipGitHub
)

$ErrorActionPreference = 'Stop'

function Fail {
    param([string]$Message)
    Write-Host ""
    Write-Host "SHIP FAILED: $Message" -ForegroundColor Red
    # Write-Error for a proper error record, but don't let it throw a second time
    # (global ErrorActionPreference is Stop); the explicit exit is the real signal.
    Write-Error $Message -ErrorAction Continue
    exit 1
}

# ---------------------------------------------------------------------------
# Step 1: resolve paths + parse published_id and MOD_VERSION
# ---------------------------------------------------------------------------
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modDir   = Join-Path $repoRoot $Mod
if (-not (Test-Path $modDir)) { Fail "Mod directory not found: $modDir" }

$cfgPath = Join-Path $modDir 'itemV2.cfg'
if (-not (Test-Path $cfgPath)) { Fail "itemV2.cfg not found: $cfgPath" }
# Read as UTF-8 explicitly -- PS 5.1 Get-Content -Raw uses the system code page.
$cfgTxt = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
if ($cfgTxt -notmatch 'published_id\s*=\s*(\d+)L') {
    Fail "No published_id found in $cfgPath (mod not yet uploaded to Workshop?)"
}
$publishedId = $matches[1]

$luaPath    = Join-Path $modDir "scripts\mods\$Mod\$Mod.lua"
$modVersion = '(unknown)'
# The in-game load line uses the mod's INTERNAL short id (e.g. "gut", "gt", "ct"),
# which is not the directory name. Parse it from the lua's "[<id>:LOAD]" marker so
# the restart-reminder tells the user the exact token to grep for. Fall back to the
# dir name if no marker is present.
$loadTag = $Mod
if (Test-Path $luaPath) {
    $luaTxt = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
    if ($luaTxt -match 'MOD_VERSION\s*=\s*"([^"]+)"') { $modVersion = $matches[1] }
    if ($luaTxt -match '\[(\w+):LOAD\]')              { $loadTag = $matches[1] }
}

$launcher = Join-Path $repoRoot 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
if (-not (Test-Path $launcher)) {
    Fail "VMBLauncher not found at $launcher. Build it first: tools\vmb-launcher\publish.ps1 -SkipOpen"
}

$workshopRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\552500'
$deployDir    = Join-Path $workshopRoot $publishedId
$workshopLog  = 'C:\Program Files (x86)\Steam\logs\workshop_log.txt'

Write-Host ""
Write-Host "==> Shipping $Mod  (v$modVersion, published_id $publishedId)" -ForegroundColor Cyan
Write-Host "    repo root : $repoRoot"
Write-Host "    deploy dir: $deployDir"
if ($AllowPublic) { Write-Host "    --allow-public : ON (public Workshop item)" -ForegroundColor Yellow }
if ($NoRemote)    { Write-Host "    --no-remote    : ON (skipping PC-B push)" }

# ---------------------------------------------------------------------------
# Step 2: build + deploy + upload via VMBLauncher
# ---------------------------------------------------------------------------
$launcherArgs = @('all', $Mod)
if ($AllowPublic) { $launcherArgs += '--allow-public' }
if ($NoRemote)    { $launcherArgs += '--no-remote' }

Write-Host ""
Write-Host "==> VMBLauncher $($launcherArgs -join ' ')" -ForegroundColor Cyan
# Do NOT pipe the launcher's output through Select-Object/head -- that trips the
# PowerShell broken-pipe quirk that reports $LASTEXITCODE = -1 on a clean exit
# (see tools/vmb-launcher/CLAUDE.md). Let it stream straight to the console.
& $launcher @launcherArgs
$launcherExit = $LASTEXITCODE
if ($launcherExit -ne 0) {
    Fail "VMBLauncher 'all $Mod' exited $launcherExit (build/deploy/upload failed -- see output above)."
}

# ---------------------------------------------------------------------------
# Step 3: GitHub release (vt2-mod-updater consumers) unless -SkipGitHub
# ---------------------------------------------------------------------------
$githubStatus = 'SKIPPED'
if (-not $SkipGitHub) {
    $tag       = "mods-$(Get-Date -Format yyyy-MM-dd)"
    $pubScript = Join-Path $repoRoot 'tools\publish-release\publish-release.ps1'
    if (-not (Test-Path $pubScript)) { Fail "publish-release.ps1 not found at $pubScript" }

    Write-Host ""
    Write-Host "==> GitHub release (tag $tag)" -ForegroundColor Cyan

    # `gh release create` (inside publish-release.ps1) FAILS if the tag already
    # exists. Detect that up front: if the release exists, stage assets via -DryRun
    # (which skips the create) and clobber-upload them instead.
    & gh release view $tag --repo Ensrick/vermintide-2-tweaker 2>&1 | Out-Null
    $releaseExists = ($LASTEXITCODE -eq 0)

    try {
        if ($releaseExists) {
            Write-Host "    release $tag exists -- staging assets (-DryRun) then 'gh release upload --clobber'" -ForegroundColor Yellow
            & $pubScript -Tag $tag -DryRun
            $stage  = Join-Path $repoRoot '.release-stage'
            $assets = @(Get-ChildItem (Join-Path $stage '*.zip') -ErrorAction Stop | ForEach-Object { $_.FullName })
            $manifest = Join-Path $stage 'manifest.json'
            if (Test-Path $manifest) { $assets += $manifest }
            if ($assets.Count -eq 0) { Fail "publish-release.ps1 -DryRun staged no assets at $stage" }
            & gh release upload $tag @assets --clobber --repo Ensrick/vermintide-2-tweaker
            if ($LASTEXITCODE -ne 0) { Fail "gh release upload --clobber failed for tag $tag (exit $LASTEXITCODE)" }
        }
        else {
            & $pubScript -Tag $tag
        }
    }
    catch {
        Fail "publish-release.ps1 failed: $($_.Exception.Message)"
    }
    $githubStatus = "OK ($tag)"
}

# ---------------------------------------------------------------------------
# Step 4: VERIFY DEPLOY -- SHA256-compare every bundleV2 file to the deploy folder
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Verifying deploy (SHA256 bundleV2 vs Workshop content folder)" -ForegroundColor Cyan
$bundleDir = Join-Path $modDir 'bundleV2'
if (-not (Test-Path $bundleDir)) { Fail "bundleV2 missing at $bundleDir (build did not produce output)" }
if (-not (Test-Path $deployDir)) {
    Fail "Deploy folder missing: $deployDir -- are you SUBSCRIBED to this mod on Workshop? (deploy can't create it)"
}

$mismatches = @()
$checked    = 0
foreach ($f in Get-ChildItem $bundleDir -File) {
    $target = Join-Path $deployDir $f.Name
    if (-not (Test-Path $target)) {
        $mismatches += "  $($f.Name): MISSING in deploy folder"
        continue
    }
    $srcHash = (Get-FileHash -Algorithm SHA256 -Path $f.FullName).Hash
    $dstHash = (Get-FileHash -Algorithm SHA256 -Path $target).Hash
    $checked++
    if ($srcHash -ne $dstHash) {
        $mismatches += "  $($f.Name): src $($srcHash.Substring(0,12)).. != deploy $($dstHash.Substring(0,12)).."
    }
}

$deployOk = ($mismatches.Count -eq 0)
if (-not $deployOk) {
    Write-Host "  DEPLOY HASH MISMATCH (Steam likely reconciled the folder back to a cached manifest):" -ForegroundColor Red
    $mismatches | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Fail "Deploy verification failed: $($mismatches.Count) file(s) differ between $bundleDir and $deployDir."
}
Write-Host "  OK -- $checked file(s) hash-match the deploy folder." -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 5: VERIFY UPLOAD -- scan recent workshop_log.txt for this published_id
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Verifying upload (workshop_log.txt)" -ForegroundColor Cyan
$uploadStatus = 'NONE'   # NONE | UPLOADED | NOCHANGE
$matchedLine  = ''
if (-not (Test-Path $workshopLog)) {
    Fail "workshop_log.txt not found at $workshopLog -- cannot confirm the upload transferred."
}
$cutoff = (Get-Date).AddMinutes(-5)
$tail   = Get-Content $workshopLog -Tail 40
foreach ($line in $tail) {
    if ($line -notmatch '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') { continue }
    $ts = $null
    try { $ts = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null) } catch { continue }
    if ($ts -lt $cutoff) { continue }
    if ($line -notmatch [regex]::Escape($publishedId)) { continue }
    if ($line -match 'Uploaded new content') {
        $uploadStatus = 'UPLOADED'; $matchedLine = $line   # strongest signal -- keep scanning, UPLOADED wins
    }
    elseif ($line -match 'No content change' -and $uploadStatus -ne 'UPLOADED') {
        $uploadStatus = 'NOCHANGE'; $matchedLine = $line
    }
}

switch ($uploadStatus) {
    'UPLOADED' {
        Write-Host "  OK -- new content pushed to Workshop." -ForegroundColor Green
        Write-Host "    $matchedLine"
    }
    'NOCHANGE' {
        # Acceptable ONLY because step 4 already proved the deploy hashes match the
        # server bundle (step 4 hard-fails otherwise, so we can't reach here stale).
        if (-not $deployOk) {
            Fail "workshop_log shows 'No content change' but deploy hashes did NOT match -- bundle is stale/divergent."
        }
        Write-Host "  OK -- server already had this exact bundle (no-op upload; deploy hashes matched)." -ForegroundColor Green
        Write-Host "    $matchedLine"
    }
    default {
        Fail "No fresh (<5 min) workshop_log line for item $publishedId. Upload may not have transferred -- inspect $workshopLog."
    }
}

# ---------------------------------------------------------------------------
# Step 6: success summary
# ---------------------------------------------------------------------------
$uploadHuman = if ($uploadStatus -eq 'UPLOADED') { 'Uploaded new content' } else { 'No content change (server up to date)' }
Write-Host ""
Write-Host "==================== SHIP SUCCESS ====================" -ForegroundColor Green
Write-Host ("  Mod          : {0}" -f $Mod)
Write-Host ("  Version      : v{0}" -f $modVersion)
Write-Host ("  Published ID : {0}" -f $publishedId)
Write-Host ("  Deploy hash  : OK ({0} file(s) match)" -f $checked)
Write-Host ("  Upload       : {0}" -f $uploadHuman)
Write-Host ("  GitHub       : {0}" -f $githubStatus)
Write-Host "======================================================" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 7: LOUD reminder -- restart Steam or the author keeps running old code
# ---------------------------------------------------------------------------
$bar = ('=' * 72)
Write-Host ""
Write-Host $bar -ForegroundColor Yellow
Write-Host "  ACTION REQUIRED BEFORE YOU TEST IN-GAME" -ForegroundColor Yellow
Write-Host $bar -ForegroundColor Yellow
Write-Host "  Steam re-downloads a SELF-AUTHORED Workshop item ONLY on a FULL" -ForegroundColor Yellow
Write-Host "  STEAM RESTART. A game relaunch does NOT pull it, and the local" -ForegroundColor Yellow
Write-Host "  deploy gets reconciled away if Steam's cache is behind." -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow
Write-Host "    1. Steam tray icon -> Exit (fully quit Steam, not just the game)" -ForegroundColor Yellow
Write-Host "    2. Reopen Steam, then launch Vermintide 2" -ForegroundColor Yellow
Write-Host "    3. Confirm the running build via the NEWEST log under" -ForegroundColor Yellow
Write-Host "       %APPDATA%\Fatshark\Vermintide 2\console_logs\" -ForegroundColor Yellow
Write-Host ("       look for:  [{0}:LOAD] v{1}" -f $loadTag, $modVersion) -ForegroundColor Yellow
Write-Host $bar -ForegroundColor Yellow

exit 0
