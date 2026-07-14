# tools/ship/ship.ps1
#
# CANONICAL one-shot RELEASE path for a single VT2 mod in this monorepo:
#   build + deploy + Workshop upload + GitHub release + hash/upload verification
#   + GitHub-issue status labeling (verify-fix[-coop] / diagnostics-armed, issue #326).
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
#  * Step 3 releases ONLY the shipped mod to GitHub (issues #436/#493):
#    `publish-release.ps1 -Mods <mod> -SkipBuild`. Sibling zips and manifest
#    entries carry over from the existing release, so a sibling's mid-edit WIP
#    can neither fail this ship nor publish a mislabeled asset. The release-tag
#    probe never assumes the day's tag exists, and it must stay behind
#    Invoke-NativeProbe (issue #489: native stderr + redirection kills PS 5.1).
#
#  * TEST REFRESH (user ruling 2026-07-13): the author tests the hash-verified
#    local deploy directly and does not need to restart Steam. Volunteer testers
#    refresh through the dev collection by unsubscribing/resubscribing. In both
#    cases the newest console log's [<id>:LOAD] version is the final authority.
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
# Pure helpers, hoisted so `-SelfTest` exercises the SAME code the live ship
# runs: the native-probe guard (issue #489) + step 6 labeling (issue #326).
# ---------------------------------------------------------------------------

# Native-command probe whose FAILURE is an expected branch (issue #489).
# Under stream redirection (agent-driven ships run `ship.ps1 ... 2>&1` / `*>`),
# Windows PowerShell 5.1 wraps native stderr into ErrorRecords, and with the
# script-global $ErrorActionPreference = 'Stop' the FIRST stderr line (e.g.
# `gh release view` on a tag that does not exist yet -- "release not found")
# becomes a TERMINATING error that kills the ship mid-run. pwsh 7.2+ does not
# have the trap, but ships must survive both hosts. So: scope EAP to Continue
# for the call, discard stderr, and let the EXIT CODE be the only signal.
# Never assume a release tag exists -- probe with this and branch on the code.
function Invoke-NativeProbe {
    param([scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Command 2>$null | Out-Null } finally { $ErrorActionPreference = $prev }
    return $LASTEXITCODE
}

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
# @{ Skip; Label; Refs; Coop; CoopRequired }. `CoopRequired` is the explicit
# changelog intent; `Coop` is only the legacy heuristic/reminder.
#   * loc-sweep headers are skipped: their #N refs are tag CONTEXT, not
#     shipped work (same heuristic as qa/check_issue_status_labels.ps1).
#   * Explicit [docs] / [tooling] headers are skipped because those issues are
#     verified and closed autonomously, never routed to human in-game testing.
#   * Label choice is ENTRY-level via header markers; a mixed fix+probe entry
#     gets one label for all refs -- the caller prints it for hand-correction.
#   * Explicit `[verify-fix-coop]` selects that lifecycle label. Explicit
#     `[coop-required]` adds the orthogonal qualifier to diagnostics-armed.
#     The Coop smell remains a reminder when neither explicit marker is present.
function Get-ShipLabelPlan {
    param([string]$Header, [string]$Entry)
    if ($Header -match '(?i)(localization|loc sweep|status-tag doctrine|menu wording|localization audit|loc audit)') {
        return @{ Skip = 'loc-sweep'; Label = $null; Refs = @(); Coop = $false; CoopRequired = $false }
    }
    if ($Header -match '(?i)\[(docs|documentation|tooling)\]') {
        return @{ Skip = 'non-runtime'; Label = $null; Refs = @(); Coop = $false; CoopRequired = $false }
    }
    $coopRequired = [bool]($Header -match '(?i)\[(verify-fix-coop|coop-required)\]')
    $diagnostic = [bool]($Header -match '(?i)\[diag\]|diagnostic|probe|instrument')
    $label = if ($diagnostic) { 'diagnostics-armed' } elseif ($Header -match '(?i)\[verify-fix-coop\]') { 'verify-fix-coop' } else { 'verify-fix' }
    $coop = [bool]($Entry -match '(?i)(host *[/+] *(1 *)?client|non-\w+ +peer|husk|hot.join|2\+? *(player|tester|people)|two player|both peers|client CTD|CTDs? +a +client|desync|wire.safe|send.queue)')
    $numSet = @{}
    foreach ($m in [regex]::Matches($Entry, '#(\d+)')) { $numSet[[int]$m.Groups[1].Value] = $true }
    $refs = @($numSet.Keys | Sort-Object)
    if ($refs.Count -eq 0) { return @{ Skip = 'no-refs'; Label = $label; Refs = @(); Coop = $coop; CoopRequired = $coopRequired } }
    return @{ Skip = $null; Label = $label; Refs = $refs; Coop = $coop; CoopRequired = $coopRequired }
}

$LifecycleLabels = @('not-started', 'verify-fix', 'verify-fix-coop', 'diagnostics-armed', 'Fixed')

# Return the one lifecycle label that should survive and every competing label
# to remove in the same `gh issue edit` invocation. Fixed always wins; an
# existing coop verification is never downgraded by an unmarked later ship.
function Get-LifecycleEditPlan {
    param([string[]]$Existing, [string]$Requested)
    $target = if ($Existing -contains 'Fixed') { 'Fixed' }
              elseif ($Requested -eq 'verify-fix' -and $Existing -contains 'verify-fix-coop') { 'verify-fix-coop' }
              else { $Requested }
    $remove = @($Existing | Where-Object { $LifecycleLabels -contains $_ -and $_ -ne $target } | Select-Object -Unique)
    return @{ Target = $target; Remove = $remove; Add = -not ($Existing -contains $target) }
}

# Offline self-test of the step-6 logic + the issue-#489 native-probe guard
# (qa-script convention: exit 0 = OK, exit 2 = regression). Runnable standalone
# (`ship.ps1 -SelfTest`) and via qa/run_selftests.ps1. Network/gh interaction
# is NOT covered here -- that path prints every decision at live-ship time for
# hand-correction.
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

    $planC = Get-ShipLabelPlan -Header '## 0.7.226-dev - #586 [verify-fix-coop] peer fix' -Entry 'host/client work for #586'
    Assert ($planC.Label -eq 'verify-fix-coop') "explicit coop marker labels verify-fix-coop"
    Assert ($planC.CoopRequired) "explicit coop marker records coop verification intent"

    $planDC = Get-ShipLabelPlan -Header '## 0.7.227-dev - #600 [diag] [coop-required] wire probe' -Entry 'probe #600'
    Assert ($planDC.Label -eq 'diagnostics-armed') "coop diagnostic keeps diagnostics-armed as its lifecycle"
    Assert ($planDC.CoopRequired) "coop diagnostic requests the orthogonal coop-required qualifier"

    $planSmell = Get-ShipLabelPlan -Header '## 0.7.228-dev - #601 peer fix' -Entry 'host/client fix for #601'
    Assert ($planSmell.Label -eq 'verify-fix') "coop-smelling prose alone does not silently change lifecycle intent"
    Assert ($planSmell.Coop -and -not $planSmell.CoopRequired) "coop smell remains a review reminder"

    $life = Get-LifecycleEditPlan -Existing @('bug', 'not-started', 'verify-fix') -Requested 'verify-fix-coop'
    Assert ($life.Target -eq 'verify-fix-coop') "explicit coop request becomes the sole lifecycle target"
    Assert (($life.Remove -join ',') -eq 'not-started,verify-fix') "coop transition removes all competing lifecycle labels"
    Assert ($life.Add) "missing lifecycle target is added"

    $keepCoop = Get-LifecycleEditPlan -Existing @('verify-fix', 'verify-fix-coop', 'not-started') -Requested 'verify-fix'
    Assert ($keepCoop.Target -eq 'verify-fix-coop') "plain ship never downgrades existing coop verification"
    Assert (($keepCoop.Remove -join ',') -eq 'verify-fix,not-started') "stronger lifecycle cleanup still restores cardinality one"

    $keepFixed = Get-LifecycleEditPlan -Existing @('Fixed', 'verify-fix', 'diagnostics-armed') -Requested 'verify-fix-coop'
    Assert ($keepFixed.Target -eq 'Fixed') "verified Fixed lifecycle is never downgraded"
    Assert (($keepFixed.Remove -join ',') -eq 'verify-fix,diagnostics-armed') "Fixed cleanup removes stale competing lifecycle labels"

    $planL = Get-ShipLabelPlan -Header '## 0.12.204-dev - Localization: applied dev status-tag doctrine (#301)' -Entry 'refs #74 #108 as tag context'
    Assert ($planL.Skip -eq 'loc-sweep') "loc-sweep header is skipped"

    $planT = Get-ShipLabelPlan -Header '## 0.1.3-dev - #602 [tooling] release check' -Entry 'tool-only work #602'
    Assert ($planT.Skip -eq 'non-runtime') "explicit tooling/docs work is never sent to human verification"

    $planN = Get-ShipLabelPlan -Header '## 0.1.2-dev - housekeeping' -Entry 'no issue references here'
    Assert ($planN.Skip -eq 'no-refs') "entry without #N refs is a no-op"

    # Issue #489: the native-probe guard. A native command that writes stderr
    # and exits nonzero (the `gh release view <missing tag>` shape) must NOT
    # throw under EAP=Stop -- on PS 5.1 with redirected streams the unguarded
    # `2>&1 | Out-Null` pattern raised a terminating NativeCommandError and
    # killed the ship mid-run. The exit code must come through faithfully.
    $probeThrew = $false; $probeCode = $null
    try { $probeCode = Invoke-NativeProbe { cmd /c "echo probe-stderr 1>&2 & exit 7" } }
    catch { $probeThrew = $true }
    Assert (-not $probeThrew) "native probe does not throw on stderr + nonzero exit (issue #489)"
    Assert ($probeCode -eq 7) "native probe propagates the failure exit code (7)"
    Assert ((Invoke-NativeProbe { cmd /c "exit 0" }) -eq 0) "native probe returns 0 on success"
    Assert ($ErrorActionPreference -eq 'Stop') "native probe restores ErrorActionPreference to Stop"

    # Issues #436/#493 interface contract + the 2026-07-13 param-stomp incident:
    # step 3 passes `-Mods $Mod` to publish-release.ps1, so that script MUST
    # declare the [string[]]$Mods parameter -- and must never assign to a
    # case-insensitive twin: PowerShell variable names are CASE-INSENSITIVE, so
    # an inventory assignment to $mods silently OVERWRITES the $Mods parameter
    # (live failure 2026-07-13: the filter validator saw 19 inventory hashtables
    # instead of the single shipped mod name and the release step aborted).
    $pubPath = Join-Path $PSScriptRoot '..\publish-release\publish-release.ps1'
    $pubTxt = if (Test-Path $pubPath) { [System.IO.File]::ReadAllText($pubPath, [System.Text.Encoding]::UTF8) } else { '' }
    Assert ($pubTxt -match '(?m)^\s*\[string\[\]\]\$Mods\b') "publish-release.ps1 declares [string[]]`$Mods (issues #436/#493)"
    Assert (-not ($pubTxt -cmatch '(?m)^\s*\$mods\s*=')) "publish-release.ps1 never assigns lowercase `$mods (param-stomp guard, 2026-07-13)"

    # Issue #591: this is an ordering invariant, not merely a documentation
    # promise. Both offline gates must execute before the launcher can perform
    # its first build/deploy/upload action.
    $selfTxt = [System.IO.File]::ReadAllText($PSCommandPath, [System.Text.Encoding]::UTF8)
    $quickPos = $selfTxt.IndexOf('& $quickGate -Quick -SkipLua -Quiet')
    $lintPos = $selfTxt.IndexOf('& $modLint $Mod -Quiet')
    $launcherPos = $selfTxt.IndexOf('& $launcher @launcherArgs')
    Assert ($quickPos -ge 0) "ship source invokes the fast headless QA gate (issue #591)"
    Assert ($lintPos -ge 0) "ship source invokes target-mod lint (issue #591)"
    Assert ($launcherPos -ge 0 -and $quickPos -lt $launcherPos -and $lintPos -lt $launcherPos) "both headless gates precede launcher build/deploy/upload"

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

# ---------------------------------------------------------------------------
# Promotion red gate (issue #327): shipping one of the five STABLE split dirs
# must pass qa/check_promotion.ps1 BLOCKING (no dev status tags in the stable
# localization, no unsanctioned pre-release suffix, version monotonic vs the
# stable CHANGELOG). Advisory scans warned for weeks while two promotions each
# leaked a checklist step to public subscribers - hence a hard gate. A
# user-NAMED suffixed public version (issue #328 ruling) ships with
# $env:VT2_SUFFIX_OK = '1'.
# ---------------------------------------------------------------------------
$promoGate = Join-Path $repoRoot 'qa\check_promotion.ps1'
$stableSplitDirs = @('chaos_wastes_tweaker', 'crafting_in_modded', 'general_tweaker', 'gui_tweaker', 'verminious_dreams_lighting')
if (($stableSplitDirs -contains $Mod) -and (Test-Path $promoGate)) {
    & $promoGate -Mod $Mod
    if ($LASTEXITCODE -ne 0) {
        Fail "check_promotion FAILED -- this stable/public target did not clear the promotion gate (issue #327). Fix the findings above (or VT2_SUFFIX_OK=1 for a user-named suffixed public version) and re-ship."
    }
}

$launcher = Join-Path $repoRoot 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
if (-not (Test-Path $launcher)) {
    Fail "VMBLauncher not found at $launcher. Build it first: tools\vmb-launcher\publish.ps1 -SkipOpen"
}

# ---------------------------------------------------------------------------
# Headless red gate (issues #590/#591): exercise the same fast, host-runnable
# QA tier used by local development before the launcher is allowed to build,
# deploy, or upload anything.  Previously most QA ran only at commit/CI time,
# so a direct ship could put a statically-invalid build on Workshop first.
#
# -Quick includes pure Lua 5.1 unit tests; -SkipLua skips only the slow advisory
# luacheck pass.  Target lint keeps its established severity ladder: duplicate
# hook errors block, heuristic warnings remain visible but non-blocking.
# ---------------------------------------------------------------------------
$quickGate = Join-Path $repoRoot 'qa\run_all.ps1'
if (-not (Test-Path $quickGate)) {
    Fail "Headless QA gate not found: $quickGate"
}

Write-Host ""
Write-Host "==> Headless preflight (fast QA + Lua 5.1 units)" -ForegroundColor Cyan
& $quickGate -Quick -SkipLua -Quiet
if ($LASTEXITCODE -ne 0) {
    Fail "Headless QA FAILED -- no build, deploy, or upload was attempted (issue #591)."
}

$modLint = Join-Path $repoRoot 'tools\mod-lint\lint-mod.ps1'
if (-not (Test-Path $modLint)) {
    Fail "Target-mod lint gate not found: $modLint"
}

Write-Host ""
Write-Host "==> Target-mod preflight lint ($Mod)" -ForegroundColor Cyan
& $modLint $Mod -Quiet
$modLintExit = $LASTEXITCODE
if ($modLintExit -ge 2) {
    Fail "Target-mod lint FAILED -- no build, deploy, or upload was attempted (issue #591)."
}
if ($modLintExit -eq 1) {
    Write-Host "Target-mod lint reported advisory warnings; shipping may continue." -ForegroundColor Yellow
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
    Write-Host "==> GitHub release (tag $tag) -- THIS mod only (issues #436/#493)" -ForegroundColor Cyan

    # Per-mod release (issues #436/#493): pass -Mods $Mod so publish-release
    # stages ONLY this mod's zip and carries every sibling's manifest entry over
    # from the release's existing manifest. Rebuilding/restaging all 18+ mods
    # here let any sibling's mid-edit WIP fail THIS ship (#493) and published
    # sibling zips whose version label was never actually shipped (#436).
    # -SkipBuild because step 2's `VMBLauncher all` built this bundle seconds
    # ago -- re-building here would race mid-ship source edits; the GitHub asset
    # must be byte-identical to the bundle that just went to the Workshop.
    #
    # `gh release create` (inside publish-release.ps1) FAILS if the tag already
    # exists. Detect that up front: if the release exists, stage assets via -DryRun
    # (which skips the create) and clobber-upload them instead. The probe goes
    # through Invoke-NativeProbe (issue #489): a missing release writes to native
    # stderr, which under redirection + EAP=Stop used to KILL the ship on PS 5.1.
    $releaseExists = ((Invoke-NativeProbe { gh release view $tag --repo Ensrick/vermintide-2-tweaker --json name }) -eq 0)

    try {
        if ($releaseExists) {
            Write-Host "    release $tag exists -- staging $Mod (-Mods -SkipBuild -DryRun) then 'gh release upload --clobber'" -ForegroundColor Yellow
            & $pubScript -Tag $tag -Mods $Mod -SkipBuild -DryRun
            $stage  = Join-Path $repoRoot '.release-stage'
            $assets = @(Get-ChildItem (Join-Path $stage '*.zip') -ErrorAction Stop | ForEach-Object { $_.FullName })
            $manifest = Join-Path $stage 'manifest.json'
            if (Test-Path $manifest) { $assets += $manifest }
            if ($assets.Count -eq 0) { Fail "publish-release.ps1 -DryRun staged no assets at $stage" }
            & gh release upload $tag @assets --clobber --repo Ensrick/vermintide-2-tweaker
            if ($LASTEXITCODE -ne 0) { Fail "gh release upload --clobber failed for tag $tag (exit $LASTEXITCODE)" }
        }
        else {
            # First ship under this tag: publish-release creates the release,
            # carrying sibling zips forward from the latest release untouched
            # (the vt2-mod-updater resolves every asset against ONE release).
            & $pubScript -Tag $tag -Mods $Mod -SkipBuild
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
# matching status label (verify-fix[-coop] / diagnostics-armed) goes on the issue in
# the SAME pass. This step mechanizes it: harvest every #N referenced in the
# CHANGELOG entry just shipped and add the label via gh. Heuristics, printed
# per issue so the user can correct a misjudgment by hand:
#   * Dev-stream ships only (-dev/-alpha/-beta/-rc suffix). A clean stable
#     promotion re-ships work that was labeled when its dev build shipped.
#   * Loc-sweep entries (header matches the localization-doctrine pattern) are
#     skipped: their #N refs are tag CONTEXT, not shipped work (same heuristic
#     as qa/check_issue_status_labels.ps1).
#   * [docs] / [tooling] entries are skipped: those issues are autonomously
#     verified and closed, never assigned a human-verification lifecycle.
#   * Label choice is ENTRY-level: a header carrying a [diag] / diagnostic /
#     probe / instrument marker = instrumentation-only ship -> diagnostics-armed;
#     explicit [verify-fix-coop] -> verify-fix-coop; anything else -> verify-fix.
#     Explicit [coop-required] adds that non-lifecycle qualifier to diagnostics.
#     A MIXED entry (fix for one issue, probe for
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
            # Probe guard (issue #489): an unauthenticated gh writes to stderr,
            # which under redirection + EAP=Stop threw on PS 5.1 and skipped
            # labeling with a misleading "gh unavailable" warning.
            $ghReady = ((Invoke-NativeProbe { gh auth status }) -eq 0)
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
                if ($plan.Skip -in @('loc-sweep', 'non-runtime')) {
                    $reason = if ($plan.Skip -eq 'loc-sweep') { 'its refs are tag context, not shipped work' } else { 'docs/tooling work is verified and closed autonomously' }
                    Write-Host "  $($plan.Skip) entry ($clHeader) -- $reason; skipping." -ForegroundColor DarkGray
                    $labelSummary += "skipped ($($plan.Skip) entry)"
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
                        Write-Host "  label : $statusLabel (entry-level intent -- correct by hand if the entry is mixed fix+diag)"
                        if ($statusLabel -eq 'diagnostics-armed' -and $plan.CoopRequired) {
                            # Idempotently ensure the repository-level qualifier exists before
                            # issue edits use it. This is not a lifecycle label.
                            & gh label create 'coop-required' --repo $ghRepo --color 'D93F0B' --description 'Testing or diagnostics requires 2+ players' --force 2>$null | Out-Null
                            if ($LASTEXITCODE -ne 0) {
                                Write-Host "  WARNING: could not create/update 'coop-required'; issue edits may need manual follow-up." -ForegroundColor Yellow
                            }
                        }
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
                            $edit = Get-LifecycleEditPlan -Existing $existing -Requested $statusLabel
                            $removeLabels = @($edit.Remove)
                            # coop-required is meaningful for armed diagnostics only.
                            $wantCoopQualifier = ($edit.Target -eq 'diagnostics-armed' -and $plan.CoopRequired)
                            if (-not $wantCoopQualifier -and $existing -contains 'coop-required') { $removeLabels += 'coop-required' }
                            $editArgs = @()
                            if ($edit.Add) { $editArgs += @('--add-label', $edit.Target) }
                            if ($wantCoopQualifier -and -not ($existing -contains 'coop-required')) { $editArgs += @('--add-label', 'coop-required') }
                            foreach ($labelToRemove in ($removeLabels | Select-Object -Unique)) { $editArgs += @('--remove-label', $labelToRemove) }
                            $editOk = $true
                            if ($editArgs.Count -gt 0) {
                                & gh issue edit $n --repo $ghRepo @editArgs 2>$null | Out-Null
                                $editOk = ($LASTEXITCODE -eq 0)
                            }
                            if ($editOk) {
                                $qualifierText = if ($wantCoopQualifier) { " + 'coop-required'" } else { '' }
                                Write-Host ("  + #{0}: lifecycle '{1}'{2}; competing lifecycle labels removed" -f $n, $edit.Target, $qualifierText) -ForegroundColor Green
                                Write-Host ("      REMINDER: #{0} needs a test-method comment (how to test + expected result) or the label is invalid (user rule 2026-07-12, PROJECT_STANDARDS s11)." -f $n) -ForegroundColor Yellow
                                if ($edit.Target -eq 'verify-fix' -and $plan.Coop -and -not $plan.CoopRequired) {
                                    Write-Host ("      COOP? entry smells like a 2+-tester verification. Mark the changelog header [verify-fix-coop] and correct this issue before assigning testers." -f $n) -ForegroundColor Magenta
                                    $labelSummary += ("#{0} +{1} (CHECK COOP + test comment)" -f $n, $edit.Target)
                                    continue
                                }
                                $labelSummary += ("#{0} ->{1}{2} (needs test comment)" -f $n, $edit.Target, $(if ($wantCoopQualifier) { '+coop-required' } else { '' }))
                            } else {
                                Write-Host ("  ! #{0}: gh issue edit failed -- set sole lifecycle '{1}' by hand" -f $n, $edit.Target) -ForegroundColor Yellow
                                $labelSummary += ("#{0} FAILED -- set {1} by hand" -f $n, $edit.Target)
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
# Step 8: test refresh + loaded-version reminder
# ---------------------------------------------------------------------------
$bar = ('=' * 72)
Write-Host ""
Write-Host $bar -ForegroundColor Yellow
Write-Host "  TEST BUILD READY" -ForegroundColor Yellow
Write-Host $bar -ForegroundColor Yellow
Write-Host "  Author/PC-A: test the hash-verified local deploy; no Steam restart" -ForegroundColor Yellow
Write-Host "  is required. Volunteer testers: unsubscribe/resubscribe through" -ForegroundColor Yellow
Write-Host "  the dev collection to refresh the Workshop build." -ForegroundColor Yellow
Write-Host "" -ForegroundColor Yellow
Write-Host "    Confirm the running build via the NEWEST log under" -ForegroundColor Yellow
Write-Host "       %APPDATA%\Fatshark\Vermintide 2\console_logs\" -ForegroundColor Yellow
Write-Host ("    look for:  [{0}:LOAD] v{1}" -f $loadTag, $modVersion) -ForegroundColor Yellow
Write-Host $bar -ForegroundColor Yellow

exit 0
