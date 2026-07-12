# tools/ship/ship.ps1
#
# CANONICAL one-shot RELEASE path for a single VT2 mod in this monorepo:
#   build + deploy + Workshop upload + GitHub release + hash/upload verification
#   + GitHub-issue status labeling (verify-fix / diagnostics-armed, issue #326).
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
    [string]$Mod,
    [switch]$AllowPublic,
    [switch]$NoRemote,
    [switch]$SkipGitHub,
    [switch]$SelfTest
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
# Pure helpers for step 6 (issue status labeling, issue #326). Hoisted out of
# the step so `-SelfTest` exercises the SAME code the live ship runs.
# ---------------------------------------------------------------------------

# Dev-stream = MOD_VERSION carries a release-track suffix. Only dev-stream
# ships auto-label; a clean stable promotion re-ships already-labeled work.
function Test-DevStreamVersion {
    param([string]$Version)
    return [bool]($Version -match '-(dev|alpha|beta|rc)\b')
}

# Top `## ` entry of a newest-first CHANGELOG. Returns @{ Header; Entry } or
# $null when the file has no version header at all.
function Get-TopChangelogEntry {
    param([string[]]$Lines)
    $first = -1; $second = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*##\s+\S') {
            if ($first -lt 0) { $first = $i } else { $second = $i; break }
        }
    }
    if ($first -lt 0) { return $null }
    $endEx = if ($second -ge 0) { $second } else { $Lines.Count }
    return @{
        Header = $Lines[$first].Trim()
        Entry  = ($Lines[$first..($endEx - 1)] -join "`n")
    }
}

# Decide what (if anything) to label from a shipped entry. Returns
# @{ Skip = $null|'loc-sweep'|'no-refs'; Label = 'verify-fix'|'diagnostics-armed'; Refs = @(int...) }.
#   * loc-sweep headers are skipped: their #N refs are tag CONTEXT, not
#     shipped work (same heuristic as qa/check_issue_status_labels.ps1).
#   * Label choice is ENTRY-level via header markers; a mixed fix+probe entry
#     gets one label for all refs -- the caller prints it for hand-correction.
function Get-ShipLabelPlan {
    param([string]$Header, [string]$Entry)
    if ($Header -match '(?i)(localization|loc sweep|status-tag doctrine|menu wording|localization audit|loc audit)') {
        return @{ Skip = 'loc-sweep'; Label = $null; Refs = @() }
    }
    $label = if ($Header -match '(?i)\[diag\]|diagnostic|probe|instrument') { 'diagnostics-armed' } else { 'verify-fix' }
    $numSet = @{}
    foreach ($m in [regex]::Matches($Entry, '#(\d+)')) { $numSet[[int]$m.Groups[1].Value] = $true }
    $refs = @($numSet.Keys | Sort-Object)
    if ($refs.Count -eq 0) { return @{ Skip = 'no-refs'; Label = $label; Refs = @() } }
    return @{ Skip = $null; Label = $label; Refs = $refs }
}

# Offline self-test of the step-6 logic (qa-script convention: exit 0 = OK,
# exit 2 = regression). Runnable standalone (`ship.ps1 -SelfTest`) and via
# qa/run_selftests.ps1. Network/gh interaction is NOT covered here -- that
# path prints every decision at live-ship time for hand-correction.
function Invoke-ShipSelfTest {
    $script:__stpass = $true
    function Assert($cond, $desc) {
        $verdict = if ($cond) { 'PASS' } else { 'FAIL' }
        $colour  = if ($cond) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $desc) -ForegroundColor $colour
        if (-not $cond) { $script:__stpass = $false }
    }

    Assert (Test-DevStreamVersion '0.7.225-dev')  "dev suffix ships labels (0.7.225-dev)"
    Assert (Test-DevStreamVersion '0.2.1-beta')   "beta suffix ships labels (0.2.1-beta)"
    Assert (-not (Test-DevStreamVersion '1.0.0')) "clean stable version does NOT auto-label (1.0.0)"
    Assert (-not (Test-DevStreamVersion '(unknown)')) "unknown version does NOT auto-label"

    $cl = @(
        '# Changelog',
        '',
        '## 0.7.222-dev (2026-07-04) - #294 (crash) FIXED: non-resident pickup CTD',
        '',
        '- **#294 (crash) FIXED.** Details. Separate latent bug tracked as #322.',
        '',
        '## 0.7.221-dev (2026-07-04) - older entry referencing #288',
        '',
        '- old work on #288.'
    )
    $top = Get-TopChangelogEntry -Lines $cl
    Assert ($null -ne $top) "top entry found in a normal changelog"
    Assert ($top.Header -like '*0.7.222-dev*') "top header is the NEWEST version"
    Assert ($top.Entry -notmatch '#288') "entry text does not bleed into the second entry"
    Assert ($null -eq (Get-TopChangelogEntry -Lines @('no headers', 'here'))) "changelog without '## ' headers returns null"

    $plan = Get-ShipLabelPlan -Header $top.Header -Entry $top.Entry
    Assert ($null -eq $plan.Skip) "fix entry is not skipped"
    Assert ($plan.Label -eq 'verify-fix') "fix entry labels verify-fix"
    Assert (($plan.Refs -join ',') -eq '294,322') "refs harvested, deduped, sorted (294,322)"

    $planD = Get-ShipLabelPlan -Header '## 0.7.225-dev - #144 retire trace, add [ct:vaul] probe' -Entry 'probe work for #144'
    Assert ($planD.Label -eq 'diagnostics-armed') "probe-marker header labels diagnostics-armed"

    $planL = Get-ShipLabelPlan -Header '## 0.12.204-dev - Localization: applied dev status-tag doctrine (#301)' -Entry 'refs #74 #108 as tag context'
    Assert ($planL.Skip -eq 'loc-sweep') "loc-sweep header is skipped"

    $planN = Get-ShipLabelPlan -Header '## 0.1.2-dev - housekeeping' -Entry 'no issue references here'
    Assert ($planN.Skip -eq 'no-refs') "entry without #N refs is a no-op"

    Write-Host ""
    if ($script:__stpass) {
        Write-Host "[ship.ps1 -SelfTest] OK -- step-6 labeling logic intact." -ForegroundColor Green
        return 0
    } else {
        Write-Host "[ship.ps1 -SelfTest] FAILED -- labeling-logic regression." -ForegroundColor Red
        return 2
    }
}

if ($SelfTest) { exit (Invoke-ShipSelfTest) }
if (-not $Mod) { Fail "Usage: ship.ps1 -Mod <name> [-AllowPublic] [-NoRemote] [-SkipGitHub]  (or ship.ps1 -SelfTest)" }

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

# ---------------------------------------------------------------------------
# Preflight (issue #344): refuse to ship while ANY itemV2.cfg carries a wrong or
# colliding published_id. An upload with a crossed id HIJACKS another mod's
# Workshop item (2026-07-05: gut_dev's cfg transiently carried ct_dev's id and
# the ship pushed gut content onto ct_dev's item). Same check the pre-commit
# gate runs, moved to BEFORE ugc_tool ever sees a cfg.
# ---------------------------------------------------------------------------
$idCheck = Join-Path $repoRoot 'qa\check_published_ids.ps1'
if (Test-Path $idCheck) {
    & $idCheck
    if ($LASTEXITCODE -ne 0) {
        Fail "check_published_ids FAILED -- fix the cfg id(s) above before shipping. A crossed id hijacks another mod's Workshop item (issue #344)."
    }
}

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
# Mid-ship id-stomp detector (issue #344): in the 2026-07-05 incident the cfg
# was CORRECT when this script read it (the banner printed the canonical id)
# and a foreign id was written into it DURING the launcher window, so ugc_tool
# uploaded to the wrong Workshop item while the ship summary looked clean.
# Re-read the cfg and compare against the ship-start id; scream if it moved.
# ---------------------------------------------------------------------------
$cfgTxtAfter = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
if ($cfgTxtAfter -match 'published_id\s*=\s*(\d+)L' -and $matches[1] -ne $publishedId) {
    Fail ("published_id CHANGED mid-ship: read $publishedId at ship start, cfg now carries $($matches[1]). " +
          "ugc_tool may have uploaded to the WRONG Workshop item -- check workshop_log.txt for BOTH ids " +
          "and re-verify both items' content before doing anything else (issue #344).")
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
# Step 6: STATUS-LABEL the shipped issues (issue #326 mechanization)
# ---------------------------------------------------------------------------
# Doctrine (PROJECT_STANDARDS section 11): when a fix or probe ships, the
# matching status label (verify-fix / diagnostics-armed) goes on the issue in
# the SAME pass. This step mechanizes it: harvest every #N referenced in the
# CHANGELOG entry just shipped and add the label via gh. Heuristics, printed
# per issue so the user can correct a misjudgment by hand:
#   * Dev-stream ships only (-dev/-alpha/-beta/-rc suffix). A clean stable
#     promotion re-ships work that was labeled when its dev build shipped.
#   * Loc-sweep entries (header matches the localization-doctrine pattern) are
#     skipped: their #N refs are tag CONTEXT, not shipped work (same heuristic
#     as qa/check_issue_status_labels.ps1).
#   * Label choice is ENTRY-level: a header carrying a [diag] / diagnostic /
#     probe / instrument marker = instrumentation-only ship -> diagnostics-armed;
#     anything else -> verify-fix. A MIXED entry (fix for one issue, probe for
#     another) gets one label for all refs -- correct the odd one out by hand.
#   * CLOSED and non-existent numbers are skipped (footnote "#2"-style false
#     positives resolve to nothing).
# This step NEVER fails the ship -- the upload already succeeded. Any labeling
# problem is a yellow warning for manual follow-up.
Write-Host ""
Write-Host "==> Status-labeling shipped issues (PROJECT_STANDARDS section 11 / issue #326)" -ForegroundColor Cyan
$labelSummary = @()
try {
    $ghRepo = 'Ensrick/vermintide-2-tweaker'
    if ($modVersion -eq '(unknown)') {
        Write-Host "  WARNING: MOD_VERSION unknown -- cannot tell dev from stable; label the shipped issues by hand." -ForegroundColor Yellow
        $labelSummary += 'SKIPPED (version unknown) -- label by hand'
    }
    elseif (-not (Test-DevStreamVersion $modVersion)) {
        Write-Host "  clean-version (stable) ship -- skipping: labels were applied when the dev build shipped." -ForegroundColor DarkGray
        $labelSummary += 'skipped (stable promotion)'
    }
    else {
        $ghReady = $false
        if (Get-Command gh -ErrorAction SilentlyContinue) {
            & gh auth status 2>&1 | Out-Null
            $ghReady = ($LASTEXITCODE -eq 0)
        }
        $clPath = Join-Path $modDir 'CHANGELOG.md'
        if (-not $ghReady) {
            Write-Host "  WARNING: gh not installed/authenticated -- label the shipped issues by hand (verify-fix / diagnostics-armed)." -ForegroundColor Yellow
            $labelSummary += 'SKIPPED (gh unavailable) -- label by hand'
        }
        elseif (-not (Test-Path $clPath)) {
            Write-Host "  WARNING: no CHANGELOG.md at $clPath -- nothing to parse; label by hand if this ship fixed an issue." -ForegroundColor Yellow
            $labelSummary += 'SKIPPED (no CHANGELOG.md)'
        }
        else {
            # Top `## ` entry = the entry being shipped (CHANGELOGs are newest-first).
            $clLines = [System.IO.File]::ReadAllText($clPath, [System.Text.Encoding]::UTF8) -split "`r?`n"
            $top = Get-TopChangelogEntry -Lines $clLines
            if (-not $top) {
                Write-Host "  WARNING: no '## ' entry in CHANGELOG.md -- nothing to label." -ForegroundColor Yellow
                $labelSummary += 'SKIPPED (no CHANGELOG entry)'
            }
            else {
                $clHeader = $top.Header
                $plan = Get-ShipLabelPlan -Header $top.Header -Entry $top.Entry
                if ($plan.Skip -eq 'loc-sweep') {
                    Write-Host "  loc-sweep entry ($clHeader) -- its refs are tag context, not shipped work; skipping." -ForegroundColor DarkGray
                    $labelSummary += 'skipped (loc-sweep entry)'
                }
                else {
                    $statusLabel = $plan.Label
                    $issueRefs = $plan.Refs
                    if ($plan.Skip -eq 'no-refs') {
                        Write-Host "  no #N refs in the shipped entry ($clHeader) -- nothing to label." -ForegroundColor DarkGray
                        $labelSummary += 'no issue refs in entry'
                    }
                    else {
                        Write-Host "  entry : $clHeader"
                        Write-Host "  label : $statusLabel (entry-level heuristic -- correct by hand if the entry is mixed fix+diag)"
                        foreach ($n in $issueRefs) {
                            $json = & gh issue view $n --repo $ghRepo --json state,labels 2>$null
                            $meta = $null
                            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($json)) {
                                try { $meta = $json | ConvertFrom-Json } catch { $meta = $null }
                            }
                            if (-not $meta) {
                                Write-Host ("  - #{0}: not an issue (footnote / PR / typo) -- skipped" -f $n) -ForegroundColor DarkGray
                                continue
                            }
                            if ($meta.state -ne 'OPEN') {
                                Write-Host ("  - #{0}: {1} -- skipped" -f $n, $meta.state) -ForegroundColor DarkGray
                                continue
                            }
                            $existing = @()
                            if ($meta.labels) { $existing = @($meta.labels | ForEach-Object { $_.name }) }
                            if ($existing -contains $statusLabel) {
                                Write-Host ("  - #{0}: already carries '{1}'" -f $n, $statusLabel) -ForegroundColor DarkGray
                                $labelSummary += ("#{0} already {1}" -f $n, $statusLabel)
                                continue
                            }
                            # Never downgrade a stronger status: verify-fix-coop (2+ testers,
                            # user rule 2026-07-11) supersedes verify-fix; Fixed (user-verified,
                            # post-fix pass owed) supersedes both. PROJECT_STANDARDS section 11.
                            $stronger = @('verify-fix-coop', 'Fixed') | Where-Object { $existing -contains $_ }
                            if ($stronger) {
                                Write-Host ("  - #{0}: carries '{1}' (supersedes '{2}') -- not downgrading" -f $n, ($stronger -join "', '"), $statusLabel) -ForegroundColor DarkGray
                                $labelSummary += ("#{0} kept {1}" -f $n, ($stronger -join '+'))
                                continue
                            }
                            & gh issue edit $n --repo $ghRepo --add-label $statusLabel 2>$null | Out-Null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Host ("  + #{0}: added '{1}'" -f $n, $statusLabel) -ForegroundColor Green
                                $labelSummary += ("#{0} +{1}" -f $n, $statusLabel)
                            } else {
                                Write-Host ("  ! #{0}: gh issue edit failed -- add '{1}' by hand" -f $n, $statusLabel) -ForegroundColor Yellow
                                $labelSummary += ("#{0} FAILED -- add {1} by hand" -f $n, $statusLabel)
                            }
                        }
                    }
                }
            }
        }
    }
}
catch {
    Write-Host "  WARNING: status-labeling step errored ($($_.Exception.Message)) -- label the shipped issues by hand." -ForegroundColor Yellow
    $labelSummary += 'ERRORED -- label by hand'
}

# ---------------------------------------------------------------------------
# Step 7: success summary
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
$labelsHuman = if ($labelSummary.Count -gt 0) { $labelSummary -join '; ' } else { 'none' }
Write-Host ("  Labels       : {0}" -f $labelsHuman)
Write-Host "======================================================" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 8: LOUD reminder -- restart Steam or the author keeps running old code
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
