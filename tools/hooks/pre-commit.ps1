# tools/hooks/pre-commit.ps1
#
# Actual body of the local pre-commit hook. Invoked via the bash shim that
# `tools/install-hooks.ps1` writes to `.git/hooks/pre-commit`.
#
# Behavior:
#   0. Run `qa/check_diff_whitespace.ps1 -Staged` on EVERY non-empty commit.
#      This inspects the exact index patch, including docs/assets ignored by the
#      later extension filter, and blocks trailing whitespace / EOF damage.
#   1. Run `qa/check_dev_only_edits.ps1 -Staged` on EVERY non-empty commit
#      (issue #429): block a staged edit to a split-mod STABLE dir (edit the
#      *_dev twin; stable is write-by-promotion-only, CLAUDE.md NON-NEG #3).
#      Runs before the docs-skip filter because a stable CHANGELOG edit is
#      still a stable edit. Instant. Bypass a real promotion with env
#      VT2_PROMOTION=1.
#   2. Run `qa/check_release_bundle_atomicity.ps1 -Staged` on EVERY non-empty
#      commit. Runtime/version/config/newest-release deltas without the exact
#      owning root bundle are rejected before a source-only commit can land.
#   3. Run `qa/check_build_receipts.ps1 -Staged` on EVERY non-empty commit.
#      Exact staged runtime inputs and the root bundle must match the BuildOnly
#      receipt; any source edit after BuildOnly is rejected until rebuilt.
#   Then read `git diff --cached --name-only`. If no staged file matches
#      `*.lua`, `*.cfg`, `*.ps1`, or `*.mod`, skip the remaining gates — pure
#      docs / asset commits don't need them.
#   4. Run `qa/run_all.ps1 -Quick -SkipLua` (the -Quick always-run set: cfg +
#      published-ids + version + unpack + widget-type + event-register +
#      cross-mod-deps; skips slow luacheck and the full-pass scans CI runs).
#      Any non-zero exit blocks the commit.
#   5. Run `tools/mod-lint/lint-mod.ps1`. Exit 2 (duplicate-hook errors)
#      blocks the commit; exit 1 (warnings — forward-ref / late-local /
#      save-restore / network-bound) prints the warning but continues.
#   6. Run `qa/check_hook_test_coverage.ps1 -Staged` (issue #429) WARN-ONLY:
#      a staged mod:hook / NetworkLookup-write add with no regression marker is
#      surfaced but never blocks (we gather signal first). Escape: a
#      `-- hook-test: <check>` comment on the added line.
#   7. Run `qa/check_native_resource_safety.ps1 -Staged` and BLOCK a new
#      particle/material/Gui/package native boundary without an exact qa/ token.
#
# Bypass on a single commit with `git commit --no-verify`. See
# PROJECT_STANDARDS.md § 8 for the escape-hatch convention.
#
# Issue: https://github.com/Ensrick/vermintide-2-tweaker/issues/29

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Resolve repo root via git so this works whether the hook is invoked from
# .git/hooks/pre-commit (cwd = repo root, as git arranges it) or by hand.
try {
    $repoRoot = (& git rev-parse --show-toplevel) 2>$null
    if (-not $repoRoot) { throw "not a git repo" }
    $repoRoot = $repoRoot.Trim()
} catch {
    Write-Host "[pre-commit] could not determine git repo root; skipping." -ForegroundColor DarkYellow
    exit 0
}

# --- Step 1: filter on staged files ----------------------------------------
# We only care about commits that touch lua source, cfg, hook scripts, or
# .mod entry points. Anything else (markdown, png, bundle binaries) is
# either out of scope for these checks or already covered by CI on push.
$relevantExts = @('.lua', '.cfg', '.ps1', '.mod')
$staged = & git diff --cached --name-only --diff-filter=ACMR 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[pre-commit] git diff failed; skipping." -ForegroundColor DarkYellow
    exit 0
}
if (-not $staged) {
    # Empty stage (e.g. amending a committed-message-only change). Nothing
    # to check; let git decide whether the commit itself is valid.
    exit 0
}

# --- Step 0: exact staged whitespace guard (every staged commit) ------------
$whitespaceScript = Join-Path $repoRoot 'qa\check_diff_whitespace.ps1'
if (-not (Test-Path -LiteralPath $whitespaceScript -PathType Leaf)) {
    Write-Host "[pre-commit] missing $whitespaceScript -- cannot verify; aborting commit." -ForegroundColor Red
    exit 1
}
Write-Host "[pre-commit] step 0/7: qa/check_diff_whitespace.ps1 -Staged" -ForegroundColor Cyan
$whitespaceOut = & pwsh -NoProfile -File $whitespaceScript -Staged 2>&1
$whitespaceExit = $LASTEXITCODE
$whitespaceOut | ForEach-Object { Write-Host $_ }
if ($whitespaceExit -ne 0) {
    Write-Host ""
    Write-Host "Pre-commit blocked by check_diff_whitespace (exit $whitespaceExit)." -ForegroundColor Red
    Write-Host "Fix the staged paths above and re-stage them; the guard never edits files." -ForegroundColor Yellow
    exit 1
}

# --- Step 1: dev/stable split guard (runs on EVERY staged commit) -----------
# Guards CLAUDE.md NON-NEG #3 before the docs-skip filter, so a stable-dir
# CHANGELOG/doc edit is caught too. Instant (git diff + path match).
$devOnlyScript = Join-Path $repoRoot 'qa\check_dev_only_edits.ps1'
if (Test-Path $devOnlyScript) {
    Write-Host "[pre-commit] step 1/7: qa/check_dev_only_edits.ps1 -Staged" -ForegroundColor Cyan
    $devOut = & pwsh -NoProfile -File $devOnlyScript -Staged 2>&1
    $devExit = $LASTEXITCODE
    $devOut | ForEach-Object { Write-Host $_ }
    if ($devExit -ge 2) {
        Write-Host ""
        Write-Host "Pre-commit blocked by check_dev_only_edits (exit $devExit -- split-mod STABLE dir edited)." -ForegroundColor Red
        Write-Host "Move the change to the matching *_dev/ dir, or set VT2_PROMOTION=1 for a real promotion. Bypass with --no-verify (PROJECT_STANDARDS § 8)." -ForegroundColor Yellow
        exit 1
    }
}

# --- Step 2: source/root-bundle atomicity guard (every staged commit) -------
# This must run before the extension filter: a newest CHANGELOG release header
# or itemV2.cfg delta is itself release intent, while a generated root bundle
# has no extension that the ordinary source gate would otherwise select.
$atomicityScript = Join-Path $repoRoot 'qa\check_release_bundle_atomicity.ps1'
if (Test-Path $atomicityScript) {
    Write-Host "[pre-commit] step 2/7: qa/check_release_bundle_atomicity.ps1 -Staged" -ForegroundColor Cyan
    $atomicityOut = & pwsh -NoProfile -File $atomicityScript -Staged 2>&1
    $atomicityExit = $LASTEXITCODE
    $atomicityOut | ForEach-Object { Write-Host $_ }
    if ($atomicityExit -ge 2) {
        Write-Host ""
        Write-Host "Pre-commit blocked by check_release_bundle_atomicity (exit $atomicityExit)." -ForegroundColor Red
        Write-Host "Commit the exact VMB root bundle with the releasable source, or split this into a docs/tests-only change." -ForegroundColor Yellow
        exit 1
    }
}

# --- Step 3: exact BuildOnly source/root receipt (every staged commit) ------
$buildReceiptScript = Join-Path $repoRoot 'qa\check_build_receipts.ps1'
if (-not (Test-Path -LiteralPath $buildReceiptScript -PathType Leaf)) {
    Write-Host "[pre-commit] missing $buildReceiptScript -- cannot verify BuildOnly provenance; aborting commit." -ForegroundColor Red
    exit 1
}
Write-Host "[pre-commit] step 3/7: qa/check_build_receipts.ps1 -Staged" -ForegroundColor Cyan
$buildReceiptOut = & pwsh -NoProfile -File $buildReceiptScript -Staged 2>&1
$buildReceiptExit = $LASTEXITCODE
$buildReceiptOut | ForEach-Object { Write-Host $_ }
if ($buildReceiptExit -ne 0) {
    Write-Host ""
    Write-Host "Pre-commit blocked by check_build_receipts (exit $buildReceiptExit)." -ForegroundColor Red
    Write-Host "Re-run ship.ps1 -Mod <name> -BuildOnly after the final source edit, then stage source, root, and receipt together." -ForegroundColor Yellow
    exit 1
}

$relevant = @($staged | Where-Object {
    $ext = [System.IO.Path]::GetExtension($_).ToLowerInvariant()
    $relevantExts -contains $ext
})

if ($relevant.Count -eq 0) {
    Write-Host "[pre-commit] no .lua / .cfg / .ps1 / .mod files staged; skipping QA gates." -ForegroundColor DarkGray
    exit 0
}

Write-Host "[pre-commit] $($relevant.Count) relevant file(s) staged; running local QA gates." -ForegroundColor Cyan

# --- Step 4: qa/run_all.ps1 -Quick -SkipLua --------------------------------
$qaScript = Join-Path $repoRoot 'qa\run_all.ps1'
if (-not (Test-Path $qaScript)) {
    Write-Host "[pre-commit] missing $qaScript -- cannot verify; aborting commit." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[pre-commit] step 4/7: qa/run_all.ps1 -Quick -SkipLua" -ForegroundColor Cyan
$qaOutput = & pwsh -NoProfile -File $qaScript -Quick -SkipLua 2>&1
$qaExit = $LASTEXITCODE
$qaOutput | ForEach-Object { Write-Host $_ }

if ($qaExit -ne 0) {
    Write-Host ""
    Write-Host "Pre-commit blocked by qa/run_all (exit $qaExit)." -ForegroundColor Red
    Write-Host "Fix the issues above, re-stage, and re-commit. Bypass with --no-verify (PROJECT_STANDARDS § 8)." -ForegroundColor Yellow
    exit 1
}

# --- Step 5: tools/mod-lint/lint-mod.ps1 -----------------------------------
$lintScript = Join-Path $repoRoot 'tools\mod-lint\lint-mod.ps1'
if (-not (Test-Path $lintScript)) {
    Write-Host "[pre-commit] missing $lintScript -- skipping lint step." -ForegroundColor DarkYellow
    exit 0
}

Write-Host ""
Write-Host "[pre-commit] step 5/7: tools/mod-lint/lint-mod.ps1" -ForegroundColor Cyan
$lintOutput = & pwsh -NoProfile -File $lintScript 2>&1
$lintExit = $LASTEXITCODE
$lintOutput | ForEach-Object { Write-Host $_ }

if ($lintExit -ge 2) {
    Write-Host ""
    Write-Host "Pre-commit blocked by mod-lint (exit $lintExit -- duplicate hooks)." -ForegroundColor Red
    Write-Host "Fix the duplicate hook registration(s) above. Bypass with --no-verify (PROJECT_STANDARDS § 8)." -ForegroundColor Yellow
    exit 1
}

if ($lintExit -eq 1) {
    Write-Host ""
    Write-Host "[pre-commit] mod-lint reported warnings (exit 1) — commit allowed but please review." -ForegroundColor Yellow
}

# --- Step 6: hook-test coverage (WARN-ONLY, issue #429) --------------------
# If the staged diff adds a mod:hook / mod:hook_safe or a NetworkLookup write in
# a mod's lua without a regression marker, surface it — but NEVER block (we're
# gathering signal first). Escape with a `-- hook-test: <check>` comment.
$hookCovScript = Join-Path $repoRoot 'qa\check_hook_test_coverage.ps1'
if (Test-Path $hookCovScript) {
    Write-Host ""
    Write-Host "[pre-commit] step 6/7: qa/check_hook_test_coverage.ps1 -Staged (advisory)" -ForegroundColor Cyan
    $covOut = & pwsh -NoProfile -File $hookCovScript -Staged 2>&1
    $covOut | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -eq 1) {
        Write-Host "[pre-commit] hook-test coverage advisory (exit 1) — commit allowed; add an _rt_register or -- hook-test: comment." -ForegroundColor Yellow
    }
}

# --- Step 7: native resource boundary coverage (BLOCKING) -----------------
$nativeResourceScript = Join-Path $repoRoot 'qa\check_native_resource_safety.ps1'
if (Test-Path $nativeResourceScript) {
    Write-Host ""
    Write-Host "[pre-commit] step 7/7: qa/check_native_resource_safety.ps1 -Staged" -ForegroundColor Cyan
    $nativeOut = & pwsh -NoProfile -File $nativeResourceScript -Staged 2>&1
    $nativeExit = $LASTEXITCODE
    $nativeOut | ForEach-Object { Write-Host $_ }
    if ($nativeExit -ne 0) {
        Write-Host "[pre-commit] blocked: a new native resource boundary lacks linked qa/ evidence." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "[pre-commit] OK — all local QA gates passed." -ForegroundColor Green
exit 0
