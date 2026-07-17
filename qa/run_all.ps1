# run_all.ps1 - master QA entry point. Runs every check in qa/CHECKS.md.
# Exits non-zero if any check fails.
#
# Usage:
#   .\qa\run_all.ps1              # run everything
#   .\qa\run_all.ps1 -SkipLua     # skip luacheck (e.g. if not installed locally)
#   .\qa\run_all.ps1 -Quick       # cheap static checks + Lua units (fast)
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
Run-Check "check_mod_inventory"               { & (Join-Path $here "check_mod_inventory.ps1")               -Quiet:$Quiet }
Run-Check "check_published_ids"               { & (Join-Path $here "check_published_ids.ps1") }               -Policy 'Blocking'
Run-Check "check_versions"                    { & (Join-Path $here "check_versions.ps1")                    -Quiet:$Quiet }
Run-Check "check_unpack_safety"               { & (Join-Path $here "check_unpack_safety.ps1")               -Quiet:$Quiet }
Run-Check "check_vmf_widget_types"            { & (Join-Path $here "check_vmf_widget_types.ps1")            -Quiet:$Quiet }
Run-Check "check_event_register_signature"    { & (Join-Path $here "check_event_register_signature.ps1")    -Quiet:$Quiet }
Run-Check "check_ci_hardening"                { & (Join-Path $here "check_ci_hardening.ps1")                -Quiet:$Quiet }
Run-Check "check_cross_mod_deps"              { & (Join-Path $here "check_cross_mod_deps.ps1")              -Quiet:$Quiet }
Run-Check "check_shared_lib_drift"            { & (Join-Path $here "check_shared_lib_drift.ps1")            -Quiet:$Quiet }
Run-Check "check_wt_stream_parity"            { & (Join-Path $here "check_wt_stream_parity.ps1")            -Quiet:$Quiet }
Run-Check "check_dofile_package_coverage"      { & (Join-Path $here "check_dofile_package_coverage.ps1")      -Quiet:$Quiet }
Run-Check "check_custom_unit_bundle_reachability" { & (Join-Path $here "check_custom_unit_bundle_reachability.ps1") -Quiet:$Quiet }
Run-Check "check_appearance_contracts"          { & (Join-Path $here "check_appearance_contracts.ps1")          -Quiet:$Quiet }
Run-Check "check_level_lookup_budget"          { & (Join-Path $here "check_level_lookup_budget.ps1")          -Quiet:$Quiet }
Run-Check "check_retired_big_rebalance"        { & (Join-Path $here "check_retired_big_rebalance.ps1")        -Quiet:$Quiet }
# The branch census is a committed, report-only snapshot. CI clones do not
# carry the maintainer's local agent/* refs, so this offline gate validates
# schema, age, generator hash, and exact automatic-disposition proofs without
# attempting to regenerate or infer from an incomplete CI ref inventory.
Run-Check "check_branch_reconciliation_census" { & (Join-Path $here "check_branch_reconciliation_census.ps1") -Quiet:$Quiet }
Run-Check "check_in_progress"                 { & (Join-Path $here "check_in_progress.ps1")                 -Quiet:$Quiet } -Policy 'Advisory'
# Pure Lua transformations run under the pinned, offline Lua 5.1 host runtime.
# Keep this before the Quick return: it is deliberately part of both fast local
# feedback and the full CI gate (issue #544).
Run-Check "lua_unit_tests"                    { & (Join-Path $here "check_lua_unit_tests.ps1")               -Quiet:$Quiet }

if ($Quick) {
    Write-Host "Quick mode - Lua units passed; skipping localization, stale-docs, file-sizes, luacheck." -ForegroundColor DarkGray
    Write-Summary
    exit $script:blockingExit
}

# run_selftests exercises the -SelfTest of every self-test-capable script
# (all fixture-based, offline, ~1s total). A self-test regression means a QA
# check's own logic is broken - the gate must not trust a broken check, so
# this is Standard policy (its exit 2 BLOCKS). Full pass only, not -Quick.
Run-Check "run_selftests"      { & (Join-Path $here "run_selftests.ps1")      -Quiet:$Quiet }
Run-Check "check_localization" { & (Join-Path $here "check_localization.ps1") -Quiet:$Quiet }
# check_loc_tags is advisory-only (dev status-tag doctrine, issue #301): it
# surfaces stable-tag leaks, unknown-vocab tags, and mutex combos, but must
# NEVER fail the gate (it exists to flag a pre-existing leak in stable cim).
# Pinned Advisory so no exit code it returns ever blocks. See qa/CHECKS.md row 19e.
Run-Check "check_loc_tags"     { & (Join-Path $here "check_loc_tags.ps1")     -Quiet:$Quiet } -Policy 'Advisory'
# check_issue_status_labels is advisory-only (GitHub issue status-label doctrine,
# PROJECT_STANDARDS.md § 11): it warns when the latest CHANGELOG entry references
# an open issue that carries neither verify-fix nor diagnostics-armed (a shipped
# fix/probe whose status label was forgotten). Pinned Advisory so no exit code it
# returns ever blocks; it also self-exits 0 when gh is offline/unauthenticated.
# See qa/CHECKS.md row 19f.
Run-Check "check_issue_status_labels" { & (Join-Path $here "check_issue_status_labels.ps1") -Quiet:$Quiet } -Policy 'Advisory'
# check_issue_tag_sync is advisory-only (issue #326 part 2): the whole-surface
# loc-tag <-> GitHub-label sync guard. Warns on stale [Issue N] tags (closed /
# non-existent issues, LOCALIZATION_STANDARD § 13.4), [verify-fix]/[diag] tags
# whose issue lacks the matching status label, and vice versa. Complements
# check_issue_status_labels (which only reads each mod's TOP CHANGELOG entry).
# Pinned Advisory; self-exits 0 when gh is offline/unauthenticated.
# See qa/CHECKS.md row 19g.
Run-Check "check_issue_tag_sync" { & (Join-Path $here "check_issue_tag_sync.ps1") -Quiet:$Quiet } -Policy 'Advisory'
Run-Check "check_file_sizes"   { & (Join-Path $here "check_file_sizes.ps1")   -Quiet:$Quiet }
Run-Check "check_command_collisions" { & (Join-Path $here "check_command_collisions.ps1") -Quiet:$Quiet }
Run-Check "check_decisions_wired" { & (Join-Path $here "check_decisions_wired.ps1") -Quiet:$Quiet }
Run-Check "check_name_integrity"  { & (Join-Path $here "check_name_integrity.ps1")  -Quiet:$Quiet }
Run-Check "check_mechanics_citations" { & (Join-Path $here "check_mechanics_citations.ps1") -Quiet:$Quiet }
# check_source_provenance always validates the committed manifest. When the
# optional sibling decompile exists it also pins HEAD/game version and verifies
# one stable symbol anchor per docs/engine subsystem. CI has no proprietary/local
# source checkout, so absence is an explicit clean SKIP rather than a false fail.
Run-Check "check_source_provenance" { & (Join-Path $here "check_source_provenance.ps1") -Quiet:$Quiet }
# check_rt_textual_invariants is a Standard (blocking) source gate (issue #516):
# the source-text invariants that issue #511 moved OUT of the in-game rt suites
# (the retail Stingray VM has no `io`, so a source self-grep threw + false-failed).
# It scans qa/rt_textual_invariants.psd1 - each entry is a literal/regex that must
# be PRESENT (a fix's marker) or ABSENT (a forbidden pattern), plus a missing-file
# FAIL. Exit 2 on any FAIL blocks the gate so a reworded/removed invariant surfaces.
# See qa/CHECKS.md row 59.
Run-Check "check_rt_textual_invariants" { & (Join-Path $here "check_rt_textual_invariants.ps1") -Quiet:$Quiet }
# check_dev_only_edits guards the dev/stable split (issue #429): any staged/diffed
# change to one of the five split-mod STABLE dirs is an ERROR (edit the *_dev twin;
# stable is write-by-promotion-only). Standard policy (exit 2 blocks). Bypass a
# legitimate promotion with env VT2_PROMOTION=1. Runs the broad staged+unstaged
# (and, in CI PRs, GITHUB_BASE_REF) view; pre-commit runs the -Staged variant.
Run-Check "check_dev_only_edits" { & (Join-Path $here "check_dev_only_edits.ps1") -Quiet:$Quiet }

# check_logging is Advisory (issue #429): logging-hygiene scan encoding
# PROJECT_STANDARDS § 3.6 + BUG_CLASSES § 17 — (a) mod:echo in a § 3.6 "NEVER"
# context (module-load banner / on_setting_changed / on_enabled|on_disabled /
# hook body), (b) mod:info|warning in a per-frame update() body, (c) mod:warning
# in a dbg/alert helper (the Issue #240 chat-spam class). Nonzero by design —
# this gathers signal, so it must NEVER block. Escapes: -- allow-echo /
# -- allow-perframe / -- allow-warn-chat. See qa/CHECKS.md rows 58a/58b/58c.
Run-Check "check_logging" { & (Join-Path $here "check_logging.ps1") -Quiet:$Quiet } -Policy 'Advisory'

# check_hook_test_coverage is Advisory (issue #429): if the diff (HEAD~1..HEAD by
# default, or origin/<base>...HEAD in a CI PR) ADDS a mod:hook / mod:hook_safe or
# a NetworkLookup write in a mod's lua, it must ship a regression marker — a
# `_rt_register(` addition, a `-- hook-test: <check>` comment, or a pre-existing
# suite. Warn-only here and in pre-commit (we gather signal first). Self-exits 0
# on an indeterminate diff. See qa/CHECKS.md row 24a.
Run-Check "check_hook_test_coverage" { & (Join-Path $here "check_hook_test_coverage.ps1") -Quiet:$Quiet } -Policy 'Advisory'

# check_stale_docs is Advisory (issue #429): staleness is TIME-based (a doc goes
# stale at $StaleDays=14 with no edit), so it can't be baselined sensibly and must not
# hard-block a commit/CI run on calendar drift — exactly the "gate that blocks on
# noise -> sessions learn --no-verify" anti-pattern this file's header warns
# against. This formalizes the old CI `continue-on-error` treatment ("stale audit
# docs are warnings, not blockers"). Remediation is `run_all.ps1 -FixStale`.
if ($FixStale) {
    Run-Check "check_stale_docs (FIX)" { & (Join-Path $here "check_stale_docs.ps1") -Fix } -Policy 'Advisory'
} else {
    Run-Check "check_stale_docs"   { & (Join-Path $here "check_stale_docs.ps1") } -Policy 'Advisory'
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
        # luacheck is pinned Advisory (issue #429): the ~415-warning baseline is
        # driven down over time, not per-commit (CWV bare-globals cleanup tracked
        # in PROJECT_STANDARDS §11). Making it Advisory REPORTS the full report as
        # a non-blocking notice — the explicit, policy-engine version of the old
        # CI `|| true`. Flip back to Standard once the baseline is clean.
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
        } -Policy 'Advisory'
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
