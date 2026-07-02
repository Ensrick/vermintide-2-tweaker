# run_all.ps1 - master QA entry point. Runs every check in qa/CHECKS.md.
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
# Gate semantics (2026-07-01): a check's exit 1 = advisory WARNINGS, which are
# REPORTED but never fail the gate; exit >=2 = ERRORS, which fail the gate. This
# is what stops pre-existing advisory warnings (e.g. bare-unpack in stable
# files, cfg title drift, stale sentinels) from blocking unrelated commits and
# training sessions to bypass the pre-commit hook with --no-verify.
#
# Two checks break the 0/1/2 convention and are pinned via -Policy:
#   * check_published_ids signals a real collision through exit 1, so it uses
#     Policy 'Blocking' (any non-zero from it is a hard error).
#   * check_in_progress is advisory coordination only ("Never blocks - just
#     surfaces awareness", per CLAUDE.md), so it uses Policy 'Advisory' (no exit
#     code it returns ever fails the gate).
# Everything else keeps the standard 0/1/2 convention.
$script:blockingExit = 0        # ERRORS (and Blocking-policy failures) raise this; it is the gate's exit code
$script:warnings     = @()      # advisory notices, surfaced loudly in the summary

function Run-Check {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$name,
        [Parameter(Mandatory, Position = 1)][scriptblock]$action,
        [ValidateSet('Standard', 'Blocking', 'Advisory')][string]$Policy = 'Standard'
    )
    Write-Host "===== $name =====" -ForegroundColor Cyan
    try {
        & $action
        $code = $LASTEXITCODE
    } catch {
        Write-Host "[$name] CRASH: $_" -ForegroundColor Red
        $code = 99
    }
    Write-Host ""

    switch ($Policy) {
        'Advisory' {
            # Never fails the gate; surface any non-zero as an advisory notice.
            if ($code -ne 0) {
                Write-Host "[$name] advisory notice (exit $code) - non-blocking." -ForegroundColor DarkYellow
                $script:warnings += "$name (advisory, exit $code)"
            }
        }
        'Blocking' {
            # Signals real errors via exit 1; any non-zero is a hard failure.
            if ($code -ge 1 -and $code -gt $script:blockingExit) { $script:blockingExit = $code }
        }
        default {
            # Standard 0/1/2: exit 1 = warnings (report, do not block); >=2 = errors (block).
            if ($code -ge 2) {
                if ($code -gt $script:blockingExit) { $script:blockingExit = $code }
            } elseif ($code -eq 1) {
                $script:warnings += "$name (exit 1)"
            }
        }
    }
}

function Write-Summary {
    Write-Host "============================================" -ForegroundColor Cyan
    if ($script:warnings.Count -gt 0) {
        Write-Host "WARNINGS (non-blocking) - $($script:warnings.Count):" -ForegroundColor Yellow
        foreach ($w in $script:warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
    }
    if ($script:blockingExit -eq 0) {
        if ($script:warnings.Count -gt 0) {
            Write-Host "[run_all] OK with WARNINGS - advisory only, gate passes." -ForegroundColor Yellow
        } else {
            Write-Host "[run_all] OK - all checks passed." -ForegroundColor Green
        }
    } else {
        Write-Host "[run_all] FAILED - blocking errors (exit $($script:blockingExit)). Fix before shipping." -ForegroundColor Red
    }
}

# Always run cfg + version + unpack-safety + widget-type checks (cheap, catch
# most ship-blockers).
# check_unpack_safety runs in Quick mode -- ripgrep-level scan, sub-2-second on
# the full repo, and the bug class it catches (Lua 5.1 nil-hole truncation in
# unpack(t, i)) burned weapon_tweaker v0.12.77/.78/.79 on 2026-05-25. Issue #36.
# check_vmf_widget_types runs in Quick mode -- same ripgrep spirit. Catches
# invalid VMF widget `type` values (e.g. `text_input`, `slider`, `string`)
# that break a mod's entire options init at load time. Burned gt v0.2.60-dev
# on 2026-05-25 (widget #103 type="text_input"). Hard-fail (exit 2) on any
# non-canonical type -- no warning tier, no suppression pragma.
# check_event_register_signature runs in Quick mode -- flags Stingray
# `event:register(obj, "ev", FN_VALUE)` where the 3rd arg should be a string
# method name. Engine logs "No function found with name '[function]'" and
# the handler never fires. Burned gt v0.2.61 -> .64 on 2026-05-25 (four
# separate fixes for the same bug class across lobby MOTD / session-ignore
# / slot-reservations). Hard-fail (exit 2). No suppression pragma.
Run-Check "check_cfg"                         { & (Join-Path $here "check_cfg.ps1")                         -Quiet:$Quiet }
Run-Check "check_published_ids"               { & (Join-Path $here "check_published_ids.ps1") }               -Policy 'Blocking'
Run-Check "check_versions"                    { & (Join-Path $here "check_versions.ps1")                    -Quiet:$Quiet }
Run-Check "check_unpack_safety"               { & (Join-Path $here "check_unpack_safety.ps1")               -Quiet:$Quiet }
Run-Check "check_vmf_widget_types"            { & (Join-Path $here "check_vmf_widget_types.ps1")            -Quiet:$Quiet }
Run-Check "check_event_register_signature"    { & (Join-Path $here "check_event_register_signature.ps1")    -Quiet:$Quiet }
Run-Check "check_cross_mod_deps"              { & (Join-Path $here "check_cross_mod_deps.ps1")              -Quiet:$Quiet }
Run-Check "check_in_progress"                 { & (Join-Path $here "check_in_progress.ps1")                 -Quiet:$Quiet } -Policy 'Advisory'

if ($Quick) {
    Write-Host "Quick mode - skipping localization, stale-docs, file-sizes, luacheck." -ForegroundColor DarkGray
    Write-Summary
    exit $script:blockingExit
}

Run-Check "check_localization" { & (Join-Path $here "check_localization.ps1") -Quiet:$Quiet }
Run-Check "check_file_sizes"   { & (Join-Path $here "check_file_sizes.ps1")   -Quiet:$Quiet }
Run-Check "check_command_collisions" { & (Join-Path $here "check_command_collisions.ps1") -Quiet:$Quiet }
Run-Check "check_decisions_wired" { & (Join-Path $here "check_decisions_wired.ps1") -Quiet:$Quiet }
Run-Check "check_name_integrity"  { & (Join-Path $here "check_name_integrity.ps1")  -Quiet:$Quiet }
Run-Check "check_mechanics_citations" { & (Join-Path $here "check_mechanics_citations.ps1") -Quiet:$Quiet }

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
Write-Summary
exit $script:blockingExit
