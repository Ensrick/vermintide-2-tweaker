# run_all.ps1 — master QA entry point. Runs every check in qa/CHECKS.md.
# Exits non-zero if any check fails.
#
# Usage:
#   .\qa\run_all.ps1              # run everything
#   .\qa\run_all.ps1 -SkipLua     # skip luacheck (e.g. if not installed locally)
#   .\qa\run_all.ps1 -Quick       # cfg + version only (fast)
#   .\qa\run_all.ps1 -FixStale    # auto-banner stale docs

[CmdletBinding()]
param(
    [switch]$SkipLua,
    [switch]$Quick,
    [switch]$FixStale,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repoRoot = Split-Path $here -Parent
$overallExit = 0

function Run-Check([string]$name, [scriptblock]$action) {
    Write-Host "===== $name =====" -ForegroundColor Cyan
    try {
        & $action
        $code = $LASTEXITCODE
    } catch {
        Write-Host "[$name] CRASH: $_" -ForegroundColor Red
        $code = 99
    }
    Write-Host ""
    if ($code -gt $script:overallExit) { $script:overallExit = $code }
    return $code
}

# Always run cfg + version checks (cheap, catch most ship-blockers)
Run-Check "check_cfg"          { & (Join-Path $here "check_cfg.ps1")       -Quiet:$Quiet }
Run-Check "check_versions"     { & (Join-Path $here "check_versions.ps1")  -Quiet:$Quiet }

if ($Quick) {
    Write-Host "Quick mode — skipping localization, stale-docs, file-sizes, luacheck." -ForegroundColor DarkGray
    exit $overallExit
}

Run-Check "check_localization" { & (Join-Path $here "check_localization.ps1") -Quiet:$Quiet }
Run-Check "check_file_sizes"   { & (Join-Path $here "check_file_sizes.ps1")   -Quiet:$Quiet }
Run-Check "check_command_collisions" { & (Join-Path $here "check_command_collisions.ps1") -Quiet:$Quiet }

if ($FixStale) {
    Run-Check "check_stale_docs (FIX)" { & (Join-Path $here "check_stale_docs.ps1") -Fix }
} else {
    Run-Check "check_stale_docs"   { & (Join-Path $here "check_stale_docs.ps1") }
}

if (-not $SkipLua) {
    # Prefer portable bundled binary in tools/luacheck/, fall back to system PATH.
    $portable = Join-Path $repoRoot "tools\luacheck\luacheck.exe"
    $lcExe = $null
    if (Test-Path $portable) {
        $lcExe = $portable
    } else {
        $cmd = Get-Command luacheck -ErrorAction SilentlyContinue
        if ($cmd) { $lcExe = $cmd.Source }
    }

    if ($lcExe) {
        Run-Check "luacheck" {
            Push-Location $repoRoot
            try {
                # --codes shows warning IDs (useful for adding ignores)
                # --formatter plain for grep-friendly output
                # --no-config disables luacheck's own config search; we use .luacheckrc explicitly
                & $lcExe . --codes --formatter plain
            } finally {
                Pop-Location
            }
        }
    } else {
        Write-Host "===== luacheck =====" -ForegroundColor Cyan
        Write-Host "[luacheck] not found locally. Download portable binary:" -ForegroundColor DarkYellow
        Write-Host "  iwr https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe -OutFile tools\luacheck\luacheck.exe" -ForegroundColor DarkYellow
        Write-Host ""
    }
}

# Summary
Write-Host "============================================" -ForegroundColor Cyan
if ($overallExit -eq 0) {
    Write-Host "[run_all] OK — all checks passed." -ForegroundColor Green
} elseif ($overallExit -eq 1) {
    Write-Host "[run_all] OK with WARNINGS." -ForegroundColor Yellow
} else {
    Write-Host "[run_all] FAILED — $($overallExit) errors. Fix before shipping." -ForegroundColor Red
}
exit $overallExit
