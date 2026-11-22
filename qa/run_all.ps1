# run_all.ps1 - master QA entry point. Runs every check in qa/CHECKS.md.
# Exits non-zero if any check fails.
#
# Usage:
#   .\qa\run_all.ps1              # run everything
#   .\qa\run_all.ps1 -SkipLua     # skip luacheck (e.g. if not installed locally)
#   .\qa\run_all.ps1 -Quick       # cheap static checks + Lua units (fast)
#   .\qa\run_all.ps1 -FixStale    # auto-banner stale docs
#   .\qa\run_all.ps1 -Quick -SkipLua -Staged   # pre-commit: change-set-scoped
#                                 # checks read only the index (issue #1683)
#   .\qa\run_all.ps1 -Full        # also run the change-set-scoped pipeline
#                                 # suites when nothing in their scope changed

[CmdletBinding()]
param(
    [switch]$SkipLua,
    [switch]$Quick,
    [switch]$Staged,
    [switch]$Full,
    [switch]$FixStale,
    [switch]$SkipBundleAtomicity,
    [switch]$SkipBuildReceipts,
    [switch]$SkipCustomUnitBundleReachability,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$repoRoot = Split-Path $here -Parent
. (Join-Path $here 'worktree_state.ps1')
# Gate semantics (2026-07-01): a check's exit 1 = advisory WARNINGS, which are
# REPORTED but never fail the gate; exit >=2 = ERRORS, which fail the gate. This
# is what stops pre-existing advisory warnings (e.g. bare-unpack in stable
# files and stale sentinels) from blocking unrelated commits and
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
$script:infrastructureFailures = @()

function Run-Check {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$name,
        [Parameter(Mandatory, Position = 1)][scriptblock]$action,
        [ValidateSet('Standard', 'Blocking', 'Advisory')][string]$Policy = 'Standard'
    )
    Write-Host "===== $name =====" -ForegroundColor Cyan
    $executionFailed = $false
    $global:LASTEXITCODE = 0
    try {
        & $action
        $code = $LASTEXITCODE
    } catch {
        Write-Host "[$name] CRASH: $_" -ForegroundColor Red
        $executionFailed = $true
        $code = 99
    }
    Write-Host ""

    # Codes 90-99 are reserved for a check that could not execute reliably.
    # Policy controls a check's legitimate findings; it must never turn a
    # parser, missing-host, or tool crash into an advisory success.
    if ($executionFailed -or $code -ge 90) {
        Write-Host "[$name] INFRASTRUCTURE FAILURE (exit $code) - blocking regardless of policy." -ForegroundColor Red
        $script:infrastructureFailures += "$name (exit $code)"
        if ($code -gt $script:blockingExit) { $script:blockingExit = $code }
        return
    }

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
    if ($script:infrastructureFailures.Count -gt 0) {
        Write-Host "INFRASTRUCTURE FAILURES (blocking) - $($script:infrastructureFailures.Count):" -ForegroundColor Red
        foreach ($failure in $script:infrastructureFailures) { Write-Host "  X $failure" -ForegroundColor Red }
    }
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

# WP-P-06: change-set scope for the suites that test pipeline tooling rather
# than the change. A scoped check runs when -Full is set, when the change set is
# missing or indeterminate, or when any changed path starts with one of its
# prefixes (ordinal, case-insensitive, '/' separators). Never scope
# lua_unit_tests, check_lua_parse, check_published_ids, check_versions,
# check_build_receipts, check_release_bundle_atomicity or lint-mod.
$script:qaChangeSet = $null
# A '!' entry excludes a subtree from the scope. qa/runtime/ holds rig cases:
# no run_selftests target or self-test fixture reads that folder (grep,
# WP-P-06 stage B), so a rig-case-only change does not rerun every self-test.
# qa/lua/tests/ stays in scope: check_logging -SelfTest scans
# qa/lua/tests/test_gut_spawn_weapon_recovery.lua.
$script:qaScopeSelftests = @('qa/', 'tools/', '.github/', '!qa/runtime/')
# run_bundle_output_set_host_matrix runs the -SelfTest of the nine checks it
# lists under both hosts; those checks load tools/ship/ and
# tools/publish-release/ helpers and qa/_test_fixtures/.
$script:qaScopeBundleOutputSet = @(
    'tools/ship/', 'tools/mod-inventory.psd1', 'tools/publish-release/',
    'qa/check_bundle_output_set.ps1', 'qa/run_bundle_output_set_host_matrix.ps1',
    'qa/check_bundle_authority.ps1', 'qa/check_build_output_normalization.ps1',
    'qa/check_build_receipts.ps1', 'qa/check_publication_snapshot.ps1',
    'qa/check_publication_receipt.ps1', 'qa/check_local_deployment_receipt.ps1',
    'qa/check_release_recovery_record.ps1', 'qa/check_workshop_upload_evidence.ps1',
    'qa/_test_fixtures/'
)
# The source host matrix runs check_wt_history_source_freshness -SelfTest
# (its SELFTEST-OWNER), which also reads qa/run_all.ps1, qa/run_selftests.ps1,
# tools/hooks/pre-commit.ps1 and the change-set helper and its fixtures.
$script:qaScopeWtHistory = @(
    'tools/weapon-history/', 'weapon_tweaker/', 'weapon_tweaker_dev/',
    'qa/check_wt_history', 'qa/run_wt_history',
    'qa/wt_history_freshness_scope.ps1', 'qa/fixtures/wt_history/',
    'qa/run_all.ps1', 'qa/run_selftests.ps1', 'tools/hooks/pre-commit.ps1'
)
# WP-H-13: rig test scripts and plans, the stub and checker they are read with,
# and the checker's fixtures. WP-H-06: the helper table and the driver it is checked against.
$script:qaScopeRuntimeScripts = @(
    'qa/runtime/', 'qa/check_runtime_scripts.ps1', 'qa/_test_fixtures/runtime_scripts/',
    'tools/harness/API.md', 'tools/harness/driver/'
)
function Test-QaScope {
    param(
        [Parameter(Mandatory, Position = 0)][string[]]$Prefixes,
        $ChangeSet = $script:qaChangeSet,
        [bool]$FullRun = [bool]$Full
    )
    if ($FullRun) { return $true }
    if ($null -eq $ChangeSet -or -not [bool]$ChangeSet.Determinate) { return $true }
    $include = @($Prefixes | Where-Object { -not $_.StartsWith('!') })
    $exclude = @($Prefixes | Where-Object { $_.StartsWith('!') } | ForEach-Object { $_.Substring(1) })
    foreach ($path in @($ChangeSet.Paths)) {
        if ([string]::IsNullOrWhiteSpace([string]$path)) { continue }
        $norm = ([string]$path).Trim().Replace('\', '/')
        $excluded = $false
        foreach ($prefix in $exclude) {
            if ($norm.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $excluded = $true; break }
        }
        if ($excluded) { continue }
        foreach ($prefix in $include) {
            if ($norm.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
    }
    return $false
}

function Run-ScopedCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string[]]$Prefixes,
        [Parameter(Mandatory, Position = 1)][string]$name,
        [Parameter(Mandatory, Position = 2)][scriptblock]$action,
        [ValidateSet('Standard', 'Blocking', 'Advisory')][string]$Policy = 'Standard'
    )
    if (Test-QaScope $Prefixes) {
        Run-Check $name $action -Policy $Policy
        return
    }
    Write-Host "===== $name =====" -ForegroundColor Cyan
    $scopeText = (@($Prefixes | Where-Object { -not $_.StartsWith('!') }) -join ', ')
    $scopeExcluded = @($Prefixes | Where-Object { $_.StartsWith('!') } | ForEach-Object { $_.Substring(1) })
    if ($scopeExcluded.Count -gt 0) { $scopeText += ' (not ' + ($scopeExcluded -join ', ') + ')' }
    Write-Host ("SKIP (scope): no changed path under {0}" -f $scopeText) -ForegroundColor DarkYellow
    Write-Host ""
}

# WP-P-06 step 7: run one check script on a thread job while the main thread
# runs another; Complete-QaParallelCheck replays its captured output under its
# own header and applies the normal Run-Check policy to its exit code. A job
# crash surfaces as a Run-Check crash (blocking infrastructure failure).
function Test-QaParallelAvailable {
    return [bool](Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)
}

function Start-QaParallelCheck {
    param([Parameter(Mandatory)][string]$Script, [bool]$BeQuiet = $false)
    return Start-ThreadJob -ArgumentList $Script, $BeQuiet, (Get-Location).Path -ScriptBlock {
        param([string]$CheckScript, [bool]$CheckQuiet, [string]$Location)
        Set-Location -LiteralPath $Location
        $global:LASTEXITCODE = 0
        $lines = @(& $CheckScript -Quiet:$CheckQuiet *>&1 | ForEach-Object { "$_" })
        [pscustomobject]@{ Lines = $lines; ExitCode = [int]$global:LASTEXITCODE }
    }
}

function Complete-QaParallelCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Job,
        [ValidateSet('Standard', 'Blocking', 'Advisory')][string]$Policy = 'Standard'
    )
    $script:parallelResult = $null
    $script:parallelError = $null
    try {
        $script:parallelResult = @(Receive-Job -Job $Job -Wait -ErrorAction Stop) | Select-Object -Last 1
        if ($null -eq $script:parallelResult) { $script:parallelError = "thread job for $Name returned no result" }
    } catch {
        $script:parallelError = "thread job for ${Name} failed: $($_.Exception.Message)"
    } finally {
        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue
    }
    Run-Check $Name {
        if ($null -ne $script:parallelError) { throw $script:parallelError }
        foreach ($line in @($script:parallelResult.Lines)) { Write-Host $line }
        $global:LASTEXITCODE = [int]$script:parallelResult.ExitCode
    } -Policy $Policy
}

function Confirm-QAWorktreePurity {
    if ($FixStale) {
        Write-Host "[worktree-purity] SKIP - -FixStale explicitly authorizes documentation edits." -ForegroundColor DarkYellow
        return
    }
    try {
        $after = Get-QAWorktreeState -RepoRoot $repoRoot
    } catch {
        Write-Host "[worktree-purity] INFRASTRUCTURE FAILURE: $_" -ForegroundColor Red
        $script:infrastructureFailures += 'worktree-purity (snapshot failed)'
        if ($script:blockingExit -lt 99) { $script:blockingExit = 99 }
        return
    }
    if (Test-QAWorktreeStateEqual $script:worktreeBefore $after) {
        Write-Host "[worktree-purity] OK - QA preserved the exact Git-visible worktree state." -ForegroundColor Green
        return
    }

    Write-Host "[worktree-purity] ERROR - QA mutated the Git-visible worktree." -ForegroundColor Red
    Write-Host "  before=$($script:worktreeBefore.Fingerprint) after=$($after.Fingerprint)" -ForegroundColor Red
    $beforeStatus = if ($script:worktreeBefore.Status.Count) {
        $script:worktreeBefore.Status -join '; '
    } else { '<clean>' }
    $afterStatus = if ($after.Status.Count) { $after.Status -join '; ' } else { '<clean>' }
    Write-Host "  status before: $beforeStatus" -ForegroundColor Red
    Write-Host "  status after:  $afterStatus" -ForegroundColor Red
    if ($script:blockingExit -lt 2) { $script:blockingExit = 2 }
}

function Invoke-PolicySelfTest {
    $failures = @()

    $script:blockingExit = 0
    $script:warnings = @()
    $script:infrastructureFailures = @()
    Run-Check "fixture-advisory-warning" { $global:LASTEXITCODE = 1 } -Policy 'Advisory'
    Run-Check "fixture-advisory-malformed" { $global:LASTEXITCODE = 2 } -Policy 'Advisory'
    if ($script:blockingExit -ne 0 -or $script:warnings.Count -ne 2 -or $script:infrastructureFailures.Count -ne 0) {
        $failures += "legitimate advisory exit 1/2 did not remain non-blocking"
    }

    $script:blockingExit = 0
    $script:warnings = @()
    $script:infrastructureFailures = @()
    Run-Check "fixture-advisory-crash" { throw "planted parser/host failure" } -Policy 'Advisory'
    if ($script:blockingExit -ne 99 -or $script:warnings.Count -ne 0 -or $script:infrastructureFailures.Count -ne 1) {
        $failures += "caught advisory execution failure was not blocking"
    }

    $script:blockingExit = 0
    $script:warnings = @()
    $script:infrastructureFailures = @()
    Run-Check "fixture-advisory-tool-exit" { $global:LASTEXITCODE = 99 } -Policy 'Advisory'
    if ($script:blockingExit -ne 99 -or $script:warnings.Count -ne 0 -or $script:infrastructureFailures.Count -ne 1) {
        $failures += "reserved tool-failure exit was flattened by advisory policy"
    }

    # #1759: execute the actual Quick notice with real policy/summary functions.
    # Select only that statement, never run the normal QA gate to test wording.
    $tokens = $null; $parseErrors = $null
    $source = [IO.File]::ReadAllText($PSCommandPath)
    $ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    $quickBlocks = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.IfStatementAst] -and
        $_.Clauses[0].Item1.Extent.Text -ceq '$Quick'
    })
    $notice = @()
    if (@($parseErrors).Count -eq 0 -and $quickBlocks.Count -eq 1) {
        $notice = @($quickBlocks[0].Clauses[0].Item2.Statements | Where-Object {
            $_.Extent.Text.StartsWith('Write-Host "Quick mode - ')
        })
    }
    if ($notice.Count -ne 1) {
        $failures += 'one actual Quick completion notice was not found'
    } else {
        $writeNotice = [scriptblock]::Create($notice[0].Extent.Text)
        foreach ($fixture in @(
            @{ Name = 'passed'; Code = 0; Expected = 0; Summary = '[run_all] OK - all checks passed.' },
            @{ Name = 'failed'; Code = 2; Expected = 2; Summary = '[run_all] FAILED - blocking errors (exit 2).' },
            @{ Name = 'skipped'; Code = 0; Expected = 0; Summary = '[run_all] OK - all checks passed.' },
            @{ Name = 'infrastructure'; Code = 99; Expected = 99; Summary = '[run_all] FAILED - blocking errors (exit 99).' }
        )) {
            $script:blockingExit = 0; $script:warnings = @(); $script:infrastructureFailures = @()
            $output = & {
                Run-Check 'lua-output-fixture' {
                    if ($fixture.Name -ceq 'infrastructure') { throw 'planted Lua host failure' }
                    if ($fixture.Name -ceq 'skipped') { Write-Host '[lua-output-fixture] SKIP - private fixture' }
                    $global:LASTEXITCODE = $fixture.Code
                }
                & $writeNotice
                Write-Summary
            } 6>&1 | Out-String
            if ($script:blockingExit -ne $fixture.Expected -or
                    -not $output.Contains('Quick mode - selected checks finished;') -or
                    $output.Contains('Lua syntax and units passed') -or
                    -not $output.Contains($fixture.Summary) -or
                    ($fixture.Name -ceq 'skipped' -and -not $output.Contains('SKIP - private fixture'))) {
                $failures += "Quick notice/real gate verdict disagrees for $($fixture.Name)"
            } else {
                Write-Host "[quick-summary:selftest] PASS $($fixture.Name)" -ForegroundColor Green
            }
        }
    }

    # WP-P-06: Test-QaScope with the production run_selftests prefixes.
    $selftestScope = $script:qaScopeSelftests
    $modOnlyPath = 'general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua'
    foreach ($scopeFixture in @(
        @{ Name = 'mod-only change skips run_selftests'; Determinate = $true; Paths = @($modOnlyPath); Full = $false; Expected = $false },
        @{ Name = 'tools/ship/claim.ps1 runs run_selftests'; Determinate = $true; Paths = @('tools/ship/claim.ps1'); Full = $false; Expected = $true },
        @{ Name = 'indeterminate change set runs run_selftests'; Determinate = $false; Paths = @(); Full = $false; Expected = $true },
        @{ Name = '-Full runs run_selftests'; Determinate = $true; Paths = @($modOnlyPath); Full = $true; Expected = $true },
        @{ Name = 'qa/runtime rig case only skips run_selftests'; Determinate = $true; Paths = @('qa/runtime/cim/issue_402_career_commit_scrub.lua', $modOnlyPath); Full = $false; Expected = $false },
        @{ Name = 'qa/lua/tests change runs run_selftests'; Determinate = $true; Paths = @('qa/runtime/cim/x.lua', 'qa/lua/tests/test_x.lua'); Full = $false; Expected = $true }
    )) {
        $scopeChangeSet = [pscustomobject]@{ Determinate = $scopeFixture.Determinate; Paths = $scopeFixture.Paths }
        $scopeActual = Test-QaScope $selftestScope -ChangeSet $scopeChangeSet -FullRun $scopeFixture.Full
        if ($scopeActual -ne $scopeFixture.Expected) {
            $failures += "qa scope fixture failed: $($scopeFixture.Name) (got $scopeActual)"
        } else {
            Write-Host "[qa-scope:selftest] PASS $($scopeFixture.Name)" -ForegroundColor Green
        }
    }

    # WP-P-06 step 7: a thread-job check keeps its output and its exit-code
    # policy, and a crash inside the job is still an infrastructure failure.
    if (Test-QaParallelAvailable) {
        $parallelDir = Join-Path ([IO.Path]::GetTempPath()) ('vt2-run-all-parallel-' + [guid]::NewGuid().ToString('N'))
        try {
            [void][IO.Directory]::CreateDirectory($parallelDir)
            foreach ($parallelFixture in @(
                @{ Name = 'error'; Body = "Write-Host 'fixture-parallel-line'`nexit 2"; Expected = 2; Infra = 0; Line = $true },
                @{ Name = 'warning'; Body = "Write-Host 'fixture-parallel-line'`nexit 1"; Expected = 0; Infra = 0; Line = $true },
                @{ Name = 'crash'; Body = "throw 'planted thread-job failure'"; Expected = 99; Infra = 1; Line = $false }
            )) {
                $fixtureScript = Join-Path $parallelDir ("fixture-{0}.ps1" -f $parallelFixture.Name)
                [IO.File]::WriteAllText($fixtureScript, "param([switch]`$Quiet)`n" + $parallelFixture.Body + "`n")
                $script:blockingExit = 0; $script:warnings = @(); $script:infrastructureFailures = @()
                $parallelOutput = & {
                    $job = Start-QaParallelCheck -Script $fixtureScript
                    Complete-QaParallelCheck -Name ("parallel-fixture-" + $parallelFixture.Name) -Job $job
                } 6>&1 | Out-String
                $lineOk = (-not $parallelFixture.Line) -or $parallelOutput.Contains('fixture-parallel-line')
                if ($script:blockingExit -ne $parallelFixture.Expected -or
                        $script:infrastructureFailures.Count -ne $parallelFixture.Infra -or -not $lineOk) {
                    $failures += "parallel check fixture '$($parallelFixture.Name)' gave exit $($script:blockingExit)"
                } else {
                    Write-Host "[qa-parallel:selftest] PASS $($parallelFixture.Name)" -ForegroundColor Green
                }
            }
        } finally {
            if (Test-Path -LiteralPath $parallelDir) { Remove-Item -LiteralPath $parallelDir -Recurse -Force }
        }
    } else {
        Write-Host '[qa-parallel:selftest] SKIP - Start-ThreadJob is unavailable in this host; checks run in order.' -ForegroundColor DarkYellow
    }

    try {
        Invoke-QAWorktreeStateSelfTest
    } catch {
        $failures += "worktree-purity fixture failed: $_"
    }

    if ($failures.Count -gt 0) {
        Write-Host "[run_all:selftest] FAILED" -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
        exit 2
    }

    Write-Host "[run_all:selftest] PASS - policy and worktree-purity fixtures passed." -ForegroundColor Green
    exit 0
}

if ($SelfTest) { Invoke-PolicySelfTest }

if (-not $FixStale) {
    try {
        $script:worktreeBefore = Get-QAWorktreeState -RepoRoot $repoRoot
    } catch {
        Write-Host "[worktree-purity] INFRASTRUCTURE FAILURE before QA: $_" -ForegroundColor Red
        exit 99
    }
}

# WP-P-06: resolve the change set once (index + working tree + the hosted
# PR/push range or origin/master...HEAD, plus untracked files off Actions).
# Any failure leaves it indeterminate, and then every scoped check runs.
try {
    . (Join-Path $here 'wt_history_freshness_scope.ps1')
    $script:qaChangeSet = Get-WtHistoryFreshnessChangeSet -RepoRoot $repoRoot -Staged:$Staged
} catch {
    Write-Host "[qa-scope] change set unavailable: $_" -ForegroundColor DarkYellow
    $script:qaChangeSet = $null
}
if (-not $Quiet) {
    if ($Full) {
        Write-Host "[qa-scope] -Full: every scoped check runs." -ForegroundColor DarkGray
    } elseif ($null -eq $script:qaChangeSet -or -not $script:qaChangeSet.Determinate) {
        $scopeReason = if ($null -eq $script:qaChangeSet) { 'no change set' } else { $script:qaChangeSet.Reason }
        Write-Host "[qa-scope] change set indeterminate ($scopeReason): every scoped check runs." -ForegroundColor DarkGray
    } else {
        Write-Host ("[qa-scope] change set from {0}: {1} path(s)." -f $script:qaChangeSet.Source, @($script:qaChangeSet.Paths).Count) -ForegroundColor DarkGray
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
# Issue #1174: cover both ordinary unstaged work and any staged index patch.
# In hosted PR QA the check also resolves origin/$GITHUB_BASE_REF...HEAD; the
# workflow invokes that exact range explicitly before this policy-engine pass.
Run-Check "check_diff_whitespace"             { & (Join-Path $here "check_diff_whitespace.ps1")             -Quiet:$Quiet }
# MP1684: validate actual staged/working (and hosted HEAD) source before build.
Run-Check "check_mp_login_source_contract"     { & (Join-Path $here "check_mp_login_source_contract.ps1")     -Staged:$Staged -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1435: immutable-review evidence must be culture-independent and
# reproducible under the same repository-owned manifest grammar.
Run-Check "check_content_manifest"            { & (Join-Path $here "check_content_manifest.ps1")            -SelfTest -Quiet:$Quiet }
# Weapon-history source freshness is opportunistic in ordinary QA: unreachable
# network is a visible skip. A reachable ref/tip mismatch blocks only when the
# checked change set (-Staged: the index; otherwise index + working tree + the
# hosted PR/push range or the origin/master...HEAD branch range, plus untracked
# files off GitHub Actions) touches weapon-history inputs or a WT stream; any other
# change set gets a visible advisory (exit 1), so a game patch no longer freezes
# every mod (issue #1683). The canonical WT BuildOnly/release path separately
# requires exact remote freshness (ship.ps1 -RequireRemoteFresh).
Run-Check "check_wt_history_source_freshness" { & (Join-Path $here "check_wt_history_source_freshness.ps1") -Staged:$Staged -Quiet:$Quiet }
# Issue #1278: every newly generated canonical root carries a deterministic
# receipt binding it to the exact dirty source snapshot that will be committed.
# BuildOnly skips the stale pre-build receipt, then writes and validates the new
# one before returning. Ordinary local/hosted QA remains fail-closed.
# WP-P-06 step 7: where Start-ThreadJob exists (PowerShell 7) the check is
# started next to lua_unit_tests below, so exactly those two overlap, and is
# reported right after it. Without thread jobs it runs here, as before.
$script:receiptJob = $null
if (-not $SkipBuildReceipts -and -not (Test-QaParallelAvailable)) {
    Run-Check "check_build_receipts"           { & (Join-Path $here "check_build_receipts.ps1")               -Quiet:$Quiet }
}
elseif ($SkipBuildReceipts -and -not $Quiet) {
    Write-Host "===== check_build_receipts =====" -ForegroundColor Cyan
    Write-Host "[check_build_receipts] SKIP - build-only pipeline fingerprints, generates, then validates the exact receipt." -ForegroundColor DarkYellow
    Write-Host ""
}
# Issue #1412: exact tracked/receipt inventory authority, zero-tracked-output
# receipt state, and typed bidirectional transitions are a cheap blocking gate.
Run-Check "check_bundle_authority"            { & (Join-Path $here "check_bundle_authority.ps1")              -Quiet:$Quiet }
# Issue #724: runtime/version/config/newest-release deltas must carry the
# owning mod's exact root bundle in the same diff. This is diff-scoped and
# blocking; docs/tests-only and bundle-only reconciliation changes pass.
if (-not $SkipBundleAtomicity) {
    Run-Check "check_release_bundle_atomicity" { & (Join-Path $here "check_release_bundle_atomicity.ps1") -Quiet:$Quiet }
}
elseif (-not $Quiet) {
    Write-Host "===== check_release_bundle_atomicity =====" -ForegroundColor Cyan
    Write-Host "[check_release_bundle_atomicity] SKIP - build-only pipeline generates the required bundle, then runs this gate." -ForegroundColor DarkYellow
    Write-Host ""
}
Run-Check "check_mod_descriptor_line_endings" { & (Join-Path $here "check_mod_descriptor_line_endings.ps1") -Quiet:$Quiet }
Run-Check "check_unpack_safety"               { & (Join-Path $here "check_unpack_safety.ps1")               -Quiet:$Quiet }
Run-Check "check_vmf_widget_types"            { & (Join-Path $here "check_vmf_widget_types.ps1")            -Quiet:$Quiet }
Run-Check "check_event_register_signature"    { & (Join-Path $here "check_event_register_signature.ps1")    -Quiet:$Quiet }
Run-Check "check_loc_description_titles"      { & (Join-Path $here "check_loc_description_titles.ps1")      -Quiet:$Quiet }
Run-Check "check_ci_hardening"                { & (Join-Path $here "check_ci_hardening.ps1")                -Quiet:$Quiet }
Run-Check "check_publication_doctrine"         { & (Join-Path $here "check_publication_doctrine.ps1")         -Quiet:$Quiet }
# WP-G-04: one verification spec per issue under qa/specs/ (format in
# qa/specs/README.md). Offline, no GitHub; "0 specs" until specs are added.
Run-Check "check_verify_specs" { & (Join-Path $here "check_verify_specs.ps1") -Quiet:$Quiet }
Run-Check "check_local_deployment_receipt"     { & (Join-Path $here "check_local_deployment_receipt.ps1")     -Quiet:$Quiet }
Run-Check "check_workshop_upload_evidence"     { & (Join-Path $here "check_workshop_upload_evidence.ps1")     -Quiet:$Quiet }
Run-Check "check_workshop_upload_result"       { & (Join-Path $here "check_workshop_upload_result.ps1")        -Quiet:$Quiet }
Run-Check "check_workshop_published_file_snapshot" { & (Join-Path $here "check_workshop_published_file_snapshot.ps1") -Quiet:$Quiet }
Run-Check "check_workshop_nochange_result"      { & (Join-Path $here "check_workshop_nochange_result.ps1")      -Quiet:$Quiet }
Run-Check "check_workshop_upload_result_release" { & (Join-Path $here "check_workshop_upload_result_release.ps1") -Quiet:$Quiet }
Run-Check "check_ps51_compatibility"          { & (Join-Path $here "check_ps51_compatibility.ps1")          -Quiet:$Quiet }
Run-Check "check_pr_autoclose"                { & (Join-Path $here "check_pr_autoclose.ps1")                -Quiet:$Quiet }
Run-Check "check_public_release_closure_policy" { & (Join-Path $here "check_public_release_closure_policy.ps1") -Quiet:$Quiet }
Run-Check "check_public_release_closure_collector" { & (Join-Path $here "check_public_release_closure_collector.ps1") -Quiet:$Quiet }
Run-Check "check_public_release_closure_transport" { & (Join-Path $here "check_public_release_closure_transport.ps1") -Quiet:$Quiet }
Run-Check "check_public_release_closure_evidence" { & (Join-Path $here "check_public_release_closure_evidence.ps1") -Quiet:$Quiet }
Run-Check "check_cross_mod_deps"              { & (Join-Path $here "check_cross_mod_deps.ps1")              -Quiet:$Quiet }
Run-Check "check_pusfume_compatibility"       { & (Join-Path $here "check_pusfume_compatibility.ps1")       -Quiet:$Quiet }
Run-Check "check_shared_lib_drift"            { & (Join-Path $here "check_shared_lib_drift.ps1")            -Quiet:$Quiet }
Run-Check "check_network_lookup_append_budget" { & (Join-Path $here "check_network_lookup_append_budget.ps1") -Quiet:$Quiet }
Run-Check "check_wt_stream_parity"            { & (Join-Path $here "check_wt_stream_parity.ps1")            -Quiet:$Quiet }
Run-Check "check_dofile_package_coverage"      { & (Join-Path $here "check_dofile_package_coverage.ps1")      -Quiet:$Quiet }
# Issue #499: every production *probe* / _diag_* root must have a reviewed
# owner, arming mode, receipt identity, and finite evidence bound. The offline
# registry is also consumed by the hosted lifecycle guard for issue liveness.
Run-Check "check_diagnostic_ownership"         { & (Join-Path $here "check_diagnostic_ownership.ps1")         -Quiet:$Quiet }
Run-Check "check_dcp_portrait_atlas"           { & (Join-Path $here "check_dcp_portrait_atlas.ps1")           -Quiet:$Quiet }
Run-Check "check_cwv_old_musket_asset_contract" { & (Join-Path $here "check_cwv_old_musket_asset_contract.ps1") -Quiet:$Quiet }
if (-not $SkipCustomUnitBundleReachability) {
    Run-Check "check_cwv_old_musket_compiled_contract" { & (Join-Path $here "check_cwv_old_musket_compiled_contract.ps1") -Quiet:$Quiet }
}
elseif (-not $Quiet) {
    Write-Host "===== check_cwv_old_musket_compiled_contract =====" -ForegroundColor Cyan
    Write-Host "[check_cwv_old_musket_compiled_contract] SKIP - build-only pipeline compiles the Old Musket units, then runs this gate." -ForegroundColor DarkYellow
    Write-Host ""
}
Run-Check "check_woc_skarrik_asset_sources"    { & (Join-Path $here "check_woc_skarrik_asset_sources.ps1")    -Quiet:$Quiet }
Run-Check "check_woc_skarrik_halberd_sources" { & (Join-Path $here "check_woc_skarrik_halberd_sources.ps1") -Quiet:$Quiet }
if (-not $SkipCustomUnitBundleReachability) {
    Run-Check "check_custom_unit_bundle_reachability" { & (Join-Path $here "check_custom_unit_bundle_reachability.ps1") -Quiet:$Quiet }
}
elseif (-not $Quiet) {
    Write-Host "===== check_custom_unit_bundle_reachability =====" -ForegroundColor Cyan
    Write-Host "[check_custom_unit_bundle_reachability] SKIP - build-only pipeline compiles new unit resources, then runs this gate." -ForegroundColor DarkYellow
    Write-Host ""
}
Run-Check "check_custom_unit_gate_reporting" { & (Join-Path $here "check_custom_unit_gate_reporting.ps1") -Quiet:$Quiet }
Run-Check "check_appearance_contracts"          { & (Join-Path $here "check_appearance_contracts.ps1")          -Quiet:$Quiet }
# The enumerated 660 backlog is regenerated from the censuses, so a census edit
# without a regenerate leaves a committed report that lies about the gap count.
Run-Check "check_appearance_census_gaps"        { & (Join-Path $here "check_appearance_census_gaps.ps1")        -Quiet:$Quiet }
Run-Check "check_native_resource_contracts"     { & (Join-Path $here "check_native_resource_contracts.ps1")     -Quiet:$Quiet }
Run-Check "check_decomposition_contracts"       { & (Join-Path $here "check_decomposition_contracts.ps1")       -Quiet:$Quiet }
Run-Check "check_level_lookup_budget"          { & (Join-Path $here "check_level_lookup_budget.ps1")          -Quiet:$Quiet }
Run-Check "check_retired_big_rebalance"        { & (Join-Path $here "check_retired_big_rebalance.ps1")        -Quiet:$Quiet }
# The branch census is a committed, report-only snapshot. CI clones do not
# carry the maintainer's local agent/* refs, so this offline gate validates
# schema, age, generator hash, and exact automatic-disposition proofs without
# attempting to regenerate or infer from an incomplete CI ref inventory.
# Advisory: a stale generated census must not fail unrelated pull requests.
Run-Check "check_branch_reconciliation_census" { & (Join-Path $here "check_branch_reconciliation_census.ps1") -Quiet:$Quiet } -Policy 'Advisory'
Run-Check "check_in_progress"                 { & (Join-Path $here "check_in_progress.ps1")                 -Quiet:$Quiet } -Policy 'Advisory'
# Blocking local-capacity guard. CI has no secondary worktrees, while maintainer
# sessions fail closed before agent checkouts can grow without bound.
Run-Check "check_worktree_budget"             { & (Join-Path $here "check_worktree_budget.ps1")             -Quiet:$Quiet }
# check_pipeline_state is advisory-only: the pipeline-state ladder (source ->
# CHANGELOG -> bundle -> upload) surfaces stranded fixes ([not deployed] entries,
# uploaded-but-user-on-older-version). It ALWAYS exits 0 and reads workshop_log.txt
# when present (marks the upload column n/a in CI where it is absent), so it can
# never fail the gate - pinned Advisory like check_in_progress. See CHECKS.md row 61.
Run-Check "check_pipeline_state"              { & (Join-Path $here "check_pipeline_state.ps1")              -Quiet:$Quiet } -Policy 'Advisory'
# Issue #1223: parse every active mod source with Luacheck's LuaJIT-compatible
# grammar. This is independent of the advisory full Luacheck pass and remains
# active under -Quick -SkipLua so a syntax error cannot reach a commit or ship.
Run-Check "check_lua_parse"                    { & (Join-Path $here "check_lua_parse.ps1")                    -Quiet:$Quiet }
# Pure Lua transformations run under the pinned, offline Lua 5.1 host runtime.
# Keep this before the Quick return: it is deliberately part of both fast local
# feedback and the full CI gate (issue #544).
# WP-P-06 step 7: check_build_receipts (deferred above) overlaps this check on
# a thread job and is replayed under its own header right after it. Optional
# git index locks are off while both run, so neither refreshes the index.
if (-not $SkipBuildReceipts -and (Test-QaParallelAvailable)) {
    $previousOptionalLocks = $env:GIT_OPTIONAL_LOCKS
    try {
        $env:GIT_OPTIONAL_LOCKS = '0'
        $script:receiptJob = Start-QaParallelCheck -Script (Join-Path $here "check_build_receipts.ps1") -BeQuiet ([bool]$Quiet)
        Run-Check "lua_unit_tests"                    { & (Join-Path $here "check_lua_unit_tests.ps1")               -Quiet:$Quiet }
        Complete-QaParallelCheck -Name "check_build_receipts" -Job $script:receiptJob
    } finally {
        if ($null -eq $previousOptionalLocks) { Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue }
        else { $env:GIT_OPTIONAL_LOCKS = $previousOptionalLocks }
    }
}
else {
    Run-Check "lua_unit_tests"                    { & (Join-Path $here "check_lua_unit_tests.ps1")               -Quiet:$Quiet }
}
# WP-H-13: a malformed rig test script or plan fails here in seconds, not in a
# rig run. Blocking, scoped to qa/runtime/** (and its own checker and fixtures).
Run-ScopedCheck $script:qaScopeRuntimeScripts "check_runtime_scripts" { & (Join-Path $here "check_runtime_scripts.ps1") -Quiet:$Quiet } -Policy 'Blocking'

if ($Quick) {
    Write-Host "Quick mode - selected checks finished; skipping localization, stale-docs, file-sizes, advisory luacheck." -ForegroundColor DarkGray
    Confirm-QAWorktreePurity
    Write-Summary
    exit $script:blockingExit
}

# run_selftests exercises the -SelfTest of every self-test-capable script
# (all fixture-based, offline, ~1s total). A self-test regression means a QA
# check's own logic is broken - the gate must not trust a broken check, so
# this is Standard policy (its exit 2 BLOCKS). Full pass only, not -Quick.
# WP-P-06: scoped to changes under qa/, tools/ or .github/ (or -Full).
Run-ScopedCheck $script:qaScopeSelftests "run_selftests" { & (Join-Path $here "run_selftests.ps1") -Quiet:$Quiet }
# The deployed-source live-test contract self-test reads real mod source
# (tools/verify/ct_official_receipt_routes_contract.ps1 pins
# chaos_wastes_tweaker receipt lines), so a product change must still run it
# when run_selftests is out of scope. Inside run_selftests it already runs.
if (-not (Test-QaScope $script:qaScopeSelftests)) {
    Run-Check "check_live_test_contract" { & (Join-Path $here "check_live_test_contract.ps1") -SelfTest }
}
# The launcher resolver is a release boundary shared by pwsh 7 and Windows
# PowerShell 5.1. Dynamic self-test discovery above covers the current host;
# this dedicated blocking matrix makes both hosts mandatory in every full QA
# run, including hosted CI. See CHECKS row 60g / issue #683.
Run-Check "vmb_launcher_path_host_matrix" { & (Join-Path $here "run_vmb_launcher_path_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1400: the complete generated-output fingerprint is a release boundary
# shared by PowerShell 7 and Windows PowerShell 5.1. Keep its canonical ordinal
# byte contract mandatory whenever its inputs change (WP-P-06 scope, or -Full).
Run-ScopedCheck $script:qaScopeBundleOutputSet "bundle_output_set_host_matrix" { & (Join-Path $here "run_bundle_output_set_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# WP-P-06: the fourteen weapon-history checks below run only when a path in
# $script:qaScopeWtHistory changed (or -Full, or an indeterminate change set).
# Issue #1436: prove the offline evidence ledger and generated Patch 5.2
# catalog are pinned; regenerate byte-exactly when the source checkout exists.
Run-ScopedCheck $script:qaScopeWtHistory "check_wt_history_reproducibility" { & (Join-Path $here "check_wt_history_reproducibility.ps1") -Quiet:$Quiet }
# Issue #540: generic remote-freshness and incomplete-source adversaries have
# one dual-host owner. Patch-specific matrices must not multiply these fixtures.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_source_host_matrix" { & (Join-Path $here "run_wt_history_source_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Patch 2.0.6 projects the source-adjacent Handgun penetration
# boundary onto both current gameplay-identical clones. Reproduce the exact
# three-leaf evidence and six-operation catalog under both PowerShell hosts.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_2_0_6_host_matrix" { & (Join-Path $here "run_wt_history_patch_2_0_6_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Patch 2.0.9.1 repaired the Halberd push-follow-up overhead.
# Reproduce its complete 20-leaf chain projection, current guards, and exact
# transactional restoration under both supported PowerShell hosts.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_2_0_9_1_host_matrix" { & (Join-Path $here "run_wt_history_patch_2_0_9_1_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Patch 2.0.10 exchanges the two Sword-and-Dagger heavy-profile
# melee-boost values. Reproduce two private current-schema profiles and their
# four explicit, atomic hand routes under both supported PowerShell hosts.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_2_0_10_host_matrix" { & (Join-Path $here "run_wt_history_patch_2_0_10_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Patch 3.1's Blunderbuss selector is a one-leaf bounded delta,
# not a complete 3.0 baseline. Reproduce the exact adjacent/current evidence,
# current-only Versus exclusion, and completeness ledger on both hosts.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_3_1_host_matrix" { & (Join-Path $here "run_wt_history_patch_3_1_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Patch 3.2's Kerillian One-Handed Axe boundary uses an older
# fallback-global source shape. Reproduce the adjacent/current evidence under
# both PowerShell hosts and prove immutable evaluations cannot alias.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_3_2_host_matrix" { & (Join-Path $here "run_wt_history_patch_3_2_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: reproduce Patch 6.0's bounded two-shield scalar slice and
# Fireball private-profile leaf from the adjacent and current source anchors.
Run-ScopedCheck $script:qaScopeWtHistory "check_wt_history_patch_6_0_reproducibility" { & (Join-Path $here "check_wt_history_patch_6_0_reproducibility.ps1") -Quiet:$Quiet }
# Issue #1436: reproduce the source-adjacent Patch 4.6 Hagbane finesse-DoT
# profiles and current routes under both supported PowerShell hosts while
# pinning the excluded Ricochet/refactor rows and source-selection adversaries.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_4_6_host_matrix" { & (Join-Path $here "run_wt_history_patch_4_6_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Patch 6.6's Deepwood Staff lift duration crosses weapon and
# vortex runtime roots. Reproduce its adjacent/current evidence and catalog
# under both supported PowerShell hosts before accepting either stream.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_6_6_host_matrix" { & (Join-Path $here "run_wt_history_patch_6_6_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: independently select Patch 6.8's Kerillian Greatsword change
# from the adjacent 6.7.2 -> 6.8.1 boundary, rehydrate its current guard, and
# reproduce both evidence lanes and the generated catalog from immutable source.
Run-ScopedCheck $script:qaScopeWtHistory "check_wt_history_patch_6_8_reproducibility" { & (Join-Path $here "check_wt_history_patch_6_8_reproducibility.ps1") -Quiet:$Quiet }
# Issue #1436: Patch 6.11.0 reduced Kruber Longbow automatic-zoom delay on
# both source-evaluated templates. Reproduce the atomic two-route boundary and
# exact current guards under both supported PowerShell hosts.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_6_11_0_host_matrix" { & (Join-Path $here "run_wt_history_patch_6_11_0_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Hotfix 6.11.2 reverted Sienna Dagger H2 and Axe & Falchion
# H1/H2 damage-profile routes. Reproduce the exact three-route boundary,
# native profile lookups, current guards, and catalogs under both PS hosts.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_6_11_2_host_matrix" { & (Join-Path $here "run_wt_history_patch_6_11_2_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
# Issue #1436: Patch 4.1.1's Masterwork Pistol boolean boundary requires both
# evaluators to preserve a present false current guard. Reproduce it under both
# supported PowerShell hosts, including the adversarial source-checkout fixture.
Run-ScopedCheck $script:qaScopeWtHistory "wt_history_patch_4_1_1_host_matrix" { & (Join-Path $here "run_wt_history_patch_4_1_1_host_matrix.ps1") -Quiet:$Quiet } -Policy 'Blocking'
Run-Check "check_localization" { & (Join-Path $here "check_localization.ps1") -Quiet:$Quiet }
# Player-facing lifecycle/issue metadata is forbidden in every active stream.
# This is a blocking repository-wide gate; GitHub labels/changelogs remain the
# source of truth for verification state. See LOCALIZATION_STANDARD section 13.
Run-Check "check_loc_tags"     { & (Join-Path $here "check_loc_tags.ps1")     -Quiet:$Quiet }
# check_issue_status_labels is advisory-only (GitHub issue status-label doctrine,
# PROJECT_STANDARDS.md section 11): it warns when the latest CHANGELOG entry references
# an open issue that carries neither verify-fix nor diagnostics-armed (a shipped
# fix/probe whose status label was forgotten). Pinned Advisory so no exit code it
# returns ever blocks; it also self-exits 0 when gh is offline/unauthenticated.
# See qa/CHECKS.md row 19f.
Run-Check "check_issue_status_labels" { & (Join-Path $here "check_issue_status_labels.ps1") -Quiet:$Quiet } -Policy 'Advisory'
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

# check_logging uses Standard 0/1/2 policy (issues #429/#427/#169): logging-hygiene scan encoding
# PROJECT_STANDARDS section 3.6 + BUG_CLASSES section 17 - (a) mod:echo in a section 3.6 "NEVER"
# context (module-load banner / on_setting_changed / on_enabled|on_disabled /
# hook body), (b) mod:info|warning in a per-frame update() body, (c) mod:warning
# in a dbg/alert helper (the Issue #240 chat-spam class), (d) executable use of
# the retired enable_debug_logging key. Nonzero by design - ordinary findings
# remain exit 1 warnings, while infrastructure failure, a new
# `_dbg_alert -> mod:warning` route, or a retired-key site outside the pinned
# GT stable promotion debt exits 2 and blocks. Escapes: -- allow-echo /
# -- allow-perframe / -- allow-warn-chat (none for (d)). See qa/CHECKS.md rows 58a-58e.
Run-Check "check_logging" { & (Join-Path $here "check_logging.ps1") -Quiet:$Quiet }

# check_hook_test_coverage is Advisory (issue #429): if the diff (HEAD~1..HEAD by
# default, or origin/<base>...HEAD in a CI PR) ADDS a mod:hook / mod:hook_safe or
# a NetworkLookup write in a mod's lua, it must ship a regression marker - a
# `_rt_register(` addition, a `-- hook-test: <check>` comment, or a pre-existing
# suite. Warn-only here and in pre-commit (we gather signal first). Self-exits 0
# on an indeterminate diff. See qa/CHECKS.md row 24a.
Run-Check "check_hook_test_coverage" { & (Join-Path $here "check_hook_test_coverage.ps1") -Quiet:$Quiet } -Policy 'Advisory'

# Native particle/material/Gui/package calls can terminate below Lua, so every
# newly added boundary must carry a stable resource-safety token linked to qa/.
# Unlike the broad hook-coverage advisory, this is a blocking change-time gate.
Run-Check "check_native_resource_safety" { & (Join-Path $here "check_native_resource_safety.ps1") -Quiet:$Quiet }

# check_stale_docs is Advisory (issue #429): staleness is TIME-based (a doc goes
# stale at $StaleDays=14 with no edit), so it can't be baselined sensibly and must not
# hard-block a commit/CI run on calendar drift - exactly the "gate that blocks on
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
        # in PROJECT_STANDARDS section 11). Making it Advisory REPORTS the full report as
        # a non-blocking notice - the explicit, policy-engine version of the old
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
Confirm-QAWorktreePurity
Write-Summary
exit $script:blockingExit
