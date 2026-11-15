# release.ps1 - resumable release driver (WP-P-09).
#
#   -Action land   -Pr <n>    wait, update a behind branch, merge on a green
#                             qa-gate, then wait for QA on master at the merge
#   -Action status -Mod <m>   print the release journal as JSON
#   -Action start  -Mod <m> -Branch <b> -ChangelogFile <f> -CommitMessageFile <f>
#                  -PrTitle <t> -PrBodyFile <f>
#                  claim, version, build, commit, pull request
#   -Action finish -Mod <m> [-AllowPublic] [-NoRemote] [-ConfirmVersion <v>]
#                  land, sync, ship, aftercare
#   -Action run    all nine steps; -DryRun prints each step as done or pending
#
# Every step checks its postcondition against the real state first and is
# skipped when it already holds, so any action can be rerun after an
# interruption. The journal (release-<mod>.json beside the ship ledger) keeps
# the session id, so every process of one release is the same claim owner.
#
# Exit codes of land: 0 ok, 10 not merged, 11 merge conflict (DIRTY), 12 a
# failed check, 13 master QA not success, 14 timed out, 15 gh failed.
# Other exits: 2 usage, 20 clean version without -ConfirmVersion (D-P-04),
# 21 claim stale, 22 claim held by another session (never re-claimed),
# 23 a step failed, 24 the head moved three times, 25 PR body has a closing keyword.
# The driver calls claim.ps1 and ship.ps1 only; it never calls the launcher,
# `gh release`, the uploader or Steam. ASCII only; PS 5.1 and 7.

[CmdletBinding()]
param(
    [ValidateSet('land', 'start', 'finish', 'run', 'status')][string]$Action = 'status',
    [string]$Mod = '',
    [int]$Pr = 0,
    [string]$Branch = '',
    [string]$ChangelogFile = '',
    [string]$PrTitle = '',
    [string]$PrBodyFile = '',
    [string]$CommitMessageFile = '',
    [switch]$AllowPublic,
    [switch]$NoRemote,
    [string]$ConfirmVersion = '',
    [switch]$DryRun,
    [int]$PollSeconds = 30,
    [int]$TimeoutMinutes = 120,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'release-driver.ps1')

if ($SelfTest) {
    & (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'qa\check_release_driver.ps1') -SelfTest
    exit $LASTEXITCODE
}

switch ($Action) {
    'land' {
        if ($Pr -le 0) { Write-Host '[release] -Action land needs -Pr <number>.' -ForegroundColor Red; exit 2 }
        if (-not [string]::IsNullOrWhiteSpace($Mod)) {
            $journal = Read-ReleaseJournal -Mod $Mod
            if ($null -ne $journal) { Set-ReleaseSession -Journal $journal }
        }
        if ($DryRun) { Write-Host "[release] land PR #${Pr}: pending (dry run, nothing changed)"; exit 0 }
        $code = Invoke-ReleaseLand -Pr $Pr -PollSeconds $PollSeconds -TimeoutMinutes $TimeoutMinutes
        if (-not [string]::IsNullOrWhiteSpace($Mod)) {
            $journal = Read-ReleaseJournal -Mod $Mod
            if ($null -ne $journal) {
                if ($code -eq 0) { $journal.merge_commit = $script:ReleaseLastMergeCommit }
                Add-ReleaseJournalStep -Journal $journal -Name 'land' -Result $(if ($code -eq 0) { 'done' } else { "exit $code" }) -Detail "PR #$Pr"
                Save-ReleaseJournal -Journal $journal
            }
        }
        exit $code
    }
    'status' {
        if ([string]::IsNullOrWhiteSpace($Mod)) { Write-Host '[release] -Action status needs -Mod <folder>.' -ForegroundColor Red; exit 2 }
        $journal = Read-ReleaseJournal -Mod $Mod
        if ($null -eq $journal) { Write-Host ('{"mod":"' + $Mod + '","journal":null}'); exit 0 }
        $journal | ConvertTo-Json -Depth 6
        exit 0
    }
    default {
        if ([string]::IsNullOrWhiteSpace($Mod)) { Write-Host "[release] -Action $Action needs -Mod <folder>." -ForegroundColor Red; exit 2 }
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $Mod) -PathType Container)) { Write-Host "[release] mod folder not found: $Mod" -ForegroundColor Red; exit 2 }
        if (-not $DryRun -and (Test-ReleasePrimaryCheckout -RepoRoot $repoRoot)) {
            Write-Host '[release] refusing to run in the shared primary checkout; use a worktree from tools/worktrees/worktree.ps1.' -ForegroundColor Red
            exit 2
        }
        $journal = Read-ReleaseJournal -Mod $Mod
        if ($null -eq $journal) { $journal = New-ReleaseJournal -Mod $Mod }
        if ($Branch) {
            if ($journal.branch -and [string]$journal.branch -cne $Branch) {
                Write-Host "[release] the active journal for $Mod uses branch $($journal.branch); one active journal per mod." -ForegroundColor Red
                exit 2
            }
            $journal.branch = $Branch
        }
        if (-not $DryRun -and $Action -ne 'finish' -and [string]::IsNullOrWhiteSpace([string]$journal.branch)) { Write-Host '[release] -Branch is required to start a release.' -ForegroundColor Red; exit 2 }
        if ($Pr -gt 0) { $journal.pr = $Pr }
        Set-ReleaseSession -Journal $journal
        $options = [pscustomobject]@{
            ChangelogFile = $ChangelogFile; CommitMessageFile = $CommitMessageFile; PrTitle = $PrTitle; PrBodyFile = $PrBodyFile
            AllowPublic = [bool]$AllowPublic; NoRemote = [bool]$NoRemote; ConfirmVersion = $ConfirmVersion; DryRun = [bool]$DryRun
            PollSeconds = $PollSeconds; TimeoutMinutes = $TimeoutMinutes
        }
        $steps = switch ($Action) {
            'start' { @('claim', 'version', 'build', 'commit', 'pull request') }
            'finish' { @('land', 'sync', 'ship', 'aftercare') }
            default { @($script:ReleaseStepNames) }
        }
        $code = Invoke-ReleaseSteps -Steps $steps -Journal $journal -RepoRoot $repoRoot -Options $options
        Write-Host ("[release] {0} {1}: exit {2}" -f $Action, $Mod, $code)
        exit $code
    }
}
