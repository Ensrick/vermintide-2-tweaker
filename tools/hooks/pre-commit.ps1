# tools/hooks/pre-commit.ps1
#
# Actual body of the local pre-commit hook. Invoked via the bash shim that
# `tools/install-hooks.ps1` writes to `.git/hooks/pre-commit`.
#
# Behavior:
#   1. Read `git diff --cached --name-only`. If no staged file matches
#      `*.lua`, `*.cfg`, `*.ps1`, or `*.mod`, skip — pure docs / asset commits
#      don't need the QA gates.
#   2. Run `qa/run_all.ps1 -Quick -SkipLua` (cfg + version checks; skips slow
#      luacheck and stale-doc / file-size / localization scans which CI runs).
#      Any non-zero exit blocks the commit.
#   3. Run `tools/mod-lint/lint-mod.ps1`. Exit 2 (duplicate-hook errors)
#      blocks the commit; exit 1 (warnings — forward-ref / late-local /
#      save-restore / network-bound) prints the warning but continues.
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

$relevant = @($staged | Where-Object {
    $ext = [System.IO.Path]::GetExtension($_).ToLowerInvariant()
    $relevantExts -contains $ext
})

if ($relevant.Count -eq 0) {
    Write-Host "[pre-commit] no .lua / .cfg / .ps1 / .mod files staged; skipping QA gates." -ForegroundColor DarkGray
    exit 0
}

Write-Host "[pre-commit] $($relevant.Count) relevant file(s) staged; running local QA gates." -ForegroundColor Cyan

# --- Step 2: qa/run_all.ps1 -Quick -SkipLua --------------------------------
$qaScript = Join-Path $repoRoot 'qa\run_all.ps1'
if (-not (Test-Path $qaScript)) {
    Write-Host "[pre-commit] missing $qaScript -- cannot verify; aborting commit." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[pre-commit] step 1/2: qa/run_all.ps1 -Quick -SkipLua" -ForegroundColor Cyan
$qaOutput = & pwsh -NoProfile -File $qaScript -Quick -SkipLua 2>&1
$qaExit = $LASTEXITCODE
$qaOutput | ForEach-Object { Write-Host $_ }

if ($qaExit -ne 0) {
    Write-Host ""
    Write-Host "Pre-commit blocked by qa/run_all (exit $qaExit)." -ForegroundColor Red
    Write-Host "Fix the issues above, re-stage, and re-commit. Bypass with --no-verify (PROJECT_STANDARDS § 8)." -ForegroundColor Yellow
    exit 1
}

# --- Step 3: tools/mod-lint/lint-mod.ps1 -----------------------------------
$lintScript = Join-Path $repoRoot 'tools\mod-lint\lint-mod.ps1'
if (-not (Test-Path $lintScript)) {
    Write-Host "[pre-commit] missing $lintScript -- skipping lint step." -ForegroundColor DarkYellow
    exit 0
}

Write-Host ""
Write-Host "[pre-commit] step 2/2: tools/mod-lint/lint-mod.ps1" -ForegroundColor Cyan
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

Write-Host ""
Write-Host "[pre-commit] OK — all local QA gates passed." -ForegroundColor Green
exit 0
