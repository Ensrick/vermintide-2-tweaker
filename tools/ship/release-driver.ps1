# release-driver.ps1 - library behind tools/ship/release.ps1 (WP-P-09).
#
# The journal, the claim-owner session, the gh/git/tool/sleep wrappers, the
# land step (part a) and the nine-step state machine (parts b and c). Every gh and git call goes through Invoke-ReleaseGh /
# Invoke-ReleaseGit and every repository script through Invoke-ReleaseTool and every wait through
# Invoke-ReleaseSleep, so
# qa/check_release_driver.ps1 can replace them. Functions return exit codes;
# only release.ps1 calls `exit`. The driver never calls the launcher,
# `gh release`, the uploader or Steam, never force-pushes and never deletes a
# claim. ASCII only; Windows PowerShell 5.1 and PowerShell 7.

. (Join-Path $PSScriptRoot 'ship-result.ps1')
. (Join-Path $PSScriptRoot 'release-identity.ps1')

# Exit codes of the land step (card WP-P-09 step 3).
$script:ReleaseExit = @{
    Ok = 0
    NotMerged = 10
    Dirty = 11
    CheckFailed = 12
    MasterQaFailed = 13
    Timeout = 14
    GhFailed = 15
    ReadyToLand = 16
}
$script:ReleasePollSeconds = 30
$script:ReleaseTimeoutMinutes = 120

function Invoke-ReleaseGh {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& gh @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = [int]$code; Output = ($output -join "`n") }
}

function Invoke-ReleaseGit {
    param([Parameter(Mandatory)][string[]]$Arguments, [string]$RepoRoot = '')
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if ($RepoRoot) { $output = @(& git -C $RepoRoot @Arguments 2>&1 | ForEach-Object { "$_" }) }
        else { $output = @(& git @Arguments 2>&1 | ForEach-Object { "$_" }) }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = [int]$code; Output = ($output -join "`n") }
}

function Invoke-ReleaseSleep {
    param([int]$Seconds)
    Start-Sleep -Seconds $Seconds
}

function Write-ReleaseLog {
    param([string]$Message)
    Write-Host ("[release] {0}" -f $Message)
}

# ---------------------------------------------------------------------------
# Journal: %APPDATA%\VMBLauncher\ship_runs\release-<mod>.json (or
# $env:VT2_SHIP_RESULT_DIR). One active journal per mod. The journal is a
# record, never the authority: every step re-checks the real state.
# ---------------------------------------------------------------------------
function Get-ReleaseJournalPath {
    param([Parameter(Mandatory)][string]$Mod)
    return (Join-Path (Get-VtShipResultDirectory) ("release-{0}.json" -f $Mod))
}

function Read-ReleaseJournal {
    param([Parameter(Mandatory)][string]$Mod)
    $path = Get-ReleaseJournalPath -Mod $Mod
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $data = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $journal = [ordered]@{}
    foreach ($property in $data.PSObject.Properties) { $journal[$property.Name] = $property.Value }
    $journal.steps = @($journal.steps)
    return $journal
}

function New-ReleaseJournal {
    param([Parameter(Mandatory)][string]$Mod)
    return [ordered]@{
        schema = 1
        mod = $Mod
        session_id = [guid]::NewGuid().ToString()
        version = $null
        cfg_version = $null
        branch = $null
        pr = $null
        merge_commit = $null
        no_land = $false
        steps = @()
    }
}

function Save-ReleaseJournal {
    param([Parameter(Mandatory)]$Journal)
    $path = Get-ReleaseJournalPath -Mod ([string]$Journal.mod)
    [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    $temporary = $path + '.tmp'
    [IO.File]::WriteAllText($temporary, (($Journal | ConvertTo-Json -Depth 6) + "`n"), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Add-ReleaseJournalStep {
    param([Parameter(Mandatory)]$Journal, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Result, [string]$Detail = '')
    $steps = @($Journal.steps)
    $steps += [ordered]@{
        name = $Name
        result = $Result
        detail = $Detail
        at_utc = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    }
    $Journal.steps = $steps
}

# The claim owner is VT2_SHIP_SESSION_ID first (tools/ship/claim.ps1). The
# journal's session id always wins, so every process of one release is the
# same owner even when the caller's environment holds another value.
function Set-ReleaseSession {
    param([Parameter(Mandatory)]$Journal)
    $env:VT2_SHIP_SESSION_ID = [string]$Journal.session_id
}

# ---------------------------------------------------------------------------
# Pull-request body rule: no closing keyword; link issues with `Refs #N`.
# ---------------------------------------------------------------------------
function Test-ReleasePrBody {
    param([AllowEmptyString()][string]$Body)
    return (-not ($Body -match '(?i)\b(close[sd]?|fix(e[sd])?|resolve[sd]?)\s*:?\s+#\d+'))
}

# ---------------------------------------------------------------------------
# Land: wait out UNKNOWN, stop on DIRTY, update a BEHIND branch, wait for a
# green qa-gate with nothing pending, merge with a merge commit, confirm
# MERGED, then wait for the QA run on master at the merge commit.
# -NoLand (several writers merging): never update or merge; a green PR that
# is not merged yet exits 16 (ready to land), and once a merge queue or train
# has merged it the same call continues with the master QA wait.
# ---------------------------------------------------------------------------
function Get-ReleasePrState {
    param([Parameter(Mandatory)][int]$Pr)
    $view = Invoke-ReleaseGh -Arguments @('pr', 'view', [string]$Pr, '--json', 'state,mergeStateStatus,headRefOid,mergeCommit')
    if ($view.ExitCode -ne 0) { return $null }
    return ($view.Output | ConvertFrom-Json)
}

# The push run for the merge commit decides; a nightly run on the same commit
# does not. A PR merged by a merge queue or train has its merge commit off
# master's first-parent line: then the oldest push run whose commit contains
# it (the push that brought it in; `gh run list` is newest first) decides.
function Find-ReleaseMasterRun {
    param([object[]]$Runs, [Parameter(Mandatory)][string]$MergeCommit, [string]$RepoRoot = '')
    $push = @($Runs | Where-Object { $null -ne $_ -and [string]$_.event -ceq 'push' })
    $exact = @($push | Where-Object { [string]$_.headSha -ceq $MergeCommit })
    if ($exact.Count -gt 0) { return $exact[0] }
    if ($push.Count -eq 0) { return $null }
    $null = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('fetch', 'origin', 'master', '--quiet')
    $containing = @($push | Where-Object {
        (Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('merge-base', '--is-ancestor', $MergeCommit, [string]$_.headSha)).ExitCode -eq 0
    })
    if ($containing.Count -gt 0) { return $containing[$containing.Count - 1] }
    return $null
}

function Invoke-ReleaseLand {
    param(
        [Parameter(Mandatory)][int]$Pr,
        [int]$PollSeconds = $script:ReleasePollSeconds,
        [int]$TimeoutMinutes = $script:ReleaseTimeoutMinutes,
        [switch]$NoLand,
        [string]$RepoRoot = ''
    )
    $maxPolls = [Math]::Max(1, [int][Math]::Ceiling(($TimeoutMinutes * 60) / [Math]::Max(1, $PollSeconds)))
    $polls = 0
    $merged = $false
    $requestedMerge = $false
    while (-not $merged) {
        if ($polls -ge $maxPolls) { Write-ReleaseLog "PR #${Pr}: timed out waiting to merge"; return $script:ReleaseExit.Timeout }
        $state = Get-ReleasePrState -Pr $Pr
        if ($null -eq $state) { Write-ReleaseLog "PR #${Pr}: gh pr view failed"; return $script:ReleaseExit.GhFailed }
        if ([string]$state.state -ceq 'MERGED') { $merged = $true; break }
        if ($requestedMerge) { Write-ReleaseLog "PR #${Pr}: merge was requested but the PR is $($state.state)"; return $script:ReleaseExit.NotMerged }
        $status = [string]$state.mergeStateStatus
        if ($status -ceq 'UNKNOWN') { $polls++; Invoke-ReleaseSleep -Seconds $PollSeconds; continue }
        if ($status -ceq 'DIRTY') { Write-ReleaseLog "PR #${Pr}: merge conflict (DIRTY)"; return $script:ReleaseExit.Dirty }
        if ($status -ceq 'BEHIND' -and -not $NoLand) {
            $oldHead = [string]$state.headRefOid
            $update = Invoke-ReleaseGh -Arguments @('pr', 'update-branch', [string]$Pr)
            if ($update.ExitCode -ne 0) { Write-ReleaseLog "PR #${Pr}: update-branch failed: $($update.Output)"; return $script:ReleaseExit.GhFailed }
            Write-ReleaseLog "PR #${Pr}: branch updated; waiting for the new head"
            do {
                $polls++
                if ($polls -ge $maxPolls) { return $script:ReleaseExit.Timeout }
                Invoke-ReleaseSleep -Seconds $PollSeconds
                $state = Get-ReleasePrState -Pr $Pr
                if ($null -eq $state) { return $script:ReleaseExit.GhFailed }
            } while ([string]$state.headRefOid -ceq $oldHead)
            continue
        }
        $checks = Invoke-ReleaseGh -Arguments @('pr', 'checks', [string]$Pr, '--json', 'name,bucket')
        $rows = @()
        if (-not [string]::IsNullOrWhiteSpace($checks.Output)) {
            # ForEach-Object unrolls the array that Windows PowerShell 5.1 ConvertFrom-Json emits as one object.
            try { $rows = @($checks.Output | ConvertFrom-Json | ForEach-Object { $_ }) } catch { $rows = @() }
        }
        $failed = @($rows | Where-Object { @('fail', 'cancel') -ccontains [string]$_.bucket })
        if ($failed.Count -gt 0) {
            Write-ReleaseLog ("PR #{0}: failed check(s): {1}" -f $Pr, (@($failed | ForEach-Object { $_.name }) -join ', '))
            return $script:ReleaseExit.CheckFailed
        }
        $pending = @($rows | Where-Object { [string]$_.bucket -ceq 'pending' })
        $qaGate = @($rows | Where-Object { [string]$_.name -ceq 'qa-gate' -and [string]$_.bucket -ceq 'pass' })
        if ($pending.Count -gt 0 -or $qaGate.Count -ne 1) { $polls++; Invoke-ReleaseSleep -Seconds $PollSeconds; continue }
        if ($NoLand) {
            Write-ReleaseLog "PR #${Pr}: ready to land (qa-gate green). Land it through the merge queue or train, then rerun; the driver resumes once it shows MERGED."
            return $script:ReleaseExit.ReadyToLand
        }
        $merge =Invoke-ReleaseGh -Arguments @('pr', 'merge', [string]$Pr, '--merge', '--delete-branch')
        Write-ReleaseLog "PR #${Pr}: merge requested (exit $($merge.ExitCode))"
        $requestedMerge = $true
    }
    $state = Get-ReleasePrState -Pr $Pr
    $mergeCommit = if ($null -ne $state -and $null -ne $state.mergeCommit) { [string]$state.mergeCommit.oid } else { '' }
    if ($mergeCommit -cnotmatch '^[0-9a-f]{40}$') { Write-ReleaseLog "PR #${Pr}: merged, but no merge commit is reported"; return $script:ReleaseExit.NotMerged }
    Write-ReleaseLog "PR #${Pr}: merged as $mergeCommit; waiting for QA on master"
    $script:ReleaseLastMergeCommit = $mergeCommit
    while ($true) {
        if ($polls -ge $maxPolls) { return $script:ReleaseExit.Timeout }
        $runs = Invoke-ReleaseGh -Arguments @('run', 'list', '--workflow', 'QA', '--branch', 'master', '--limit', '30', '--json', 'headSha,status,conclusion,databaseId,event')
        $run = $null
        if ($runs.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($runs.Output)) {
            $run = Find-ReleaseMasterRun -Runs @($runs.Output | ConvertFrom-Json | ForEach-Object { $_ }) -MergeCommit $mergeCommit -RepoRoot $RepoRoot
        }
        if ($null -ne $run -and [string]$run.status -ceq 'completed') {
            if ([string]$run.conclusion -ceq 'success') { Write-ReleaseLog "master QA passed for $mergeCommit (run $($run.databaseId))"; return $script:ReleaseExit.Ok }
            Write-ReleaseLog "master QA for $mergeCommit concluded $($run.conclusion) (run $($run.databaseId))"
            return $script:ReleaseExit.MasterQaFailed
        }
        $polls++
        Invoke-ReleaseSleep -Seconds $PollSeconds
    }
}

# ---------------------------------------------------------------------------
# Parts (b) and (c): the nine steps. Each step's postcondition is read from
# the real state (claim broker, files, receipts, git, GitHub, ship ledger),
# never from the journal; a step whose postcondition already holds is skipped.
# ---------------------------------------------------------------------------
$script:ReleaseExit.CleanVersionUnconfirmed = 20
$script:ReleaseExit.ClaimStale = 21
$script:ReleaseExit.ClaimOtherOwner = 22
$script:ReleaseExit.StepFailed = 23
$script:ReleaseExit.HeadRetriesExhausted = 24
$script:ReleaseExit.BodyRejected = 25
$script:ReleaseExit.Usage = 2
$script:ReleaseStepNames = @('claim', 'version', 'build', 'commit', 'pull request', 'land', 'sync', 'ship', 'aftercare')
$script:ReleasePinFile = 'tools/verify/live_test_contract_exceptions.psd1'

# Run a repository script in a child PowerShell (claim.ps1, ship.ps1, QA
# checks). Output is echoed and returned. Tests replace this function.
function Invoke-ReleaseTool {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$Script, [string[]]$Arguments = @())
    $hostPath = (Get-Process -Id $PID).Path
    $path = Join-Path $RepoRoot $Script
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $hostPath -NoProfile -File $path @Arguments 2>&1 | ForEach-Object { $text = "$_"; Write-Host $text; $lines.Add($text) }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    return [pscustomobject]@{ ExitCode = [int]$code; Output = (@($lines.ToArray()) -join "`n") }
}

function Get-ReleaseModMainLua([string]$RepoRoot, [string]$Mod) {
    return (Join-Path $RepoRoot ("{0}\scripts\mods\{0}\{0}.lua" -f $Mod))
}

function Get-ReleaseSourceVersion([string]$RepoRoot, [string]$Mod) {
    $lua = Get-ReleaseModMainLua $RepoRoot $Mod
    if (-not (Test-Path -LiteralPath $lua -PathType Leaf)) { return $null }
    $match = [regex]::Match([IO.File]::ReadAllText($lua, [Text.Encoding]::UTF8), 'MOD_VERSION\s*=\s*"([^"]+)"')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}

function Test-ReleaseChangelogMatches([string]$Version, [string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Version)) { return $false }
    return [bool](Test-ReleaseIdentity -SourceVersion $Version -ChangelogText $Text).Ok
}

function Test-ReleasePreReleaseVersion([string]$Version) {
    return ($Version -cmatch '^[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z]')
}

function Get-ReleaseLedgerRecords {
    param([string]$Mod, [string]$Version)
    $ledger = Join-Path (Get-VtShipResultDirectory) 'ledger.jsonl'
    if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) { return @() }
    $records = @()
    foreach ($line in [IO.File]::ReadAllLines($ledger, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json } catch { continue }
        if ([string]$entry.mod -ceq $Mod -and [string]$entry.version -ceq $Version -and [string]$entry.mode -ceq 'ship') { $records += $entry }
    }
    return $records
}

# --- postconditions -------------------------------------------------------
function Test-ReleaseStepDone {
    param([Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)]$Journal, [Parameter(Mandatory)][string]$RepoRoot)
    $mod = [string]$Journal.mod
    $version = [string]$Journal.version
    switch ($Step) {
        'claim' {
            if ([string]::IsNullOrWhiteSpace($version)) { return 'pending' }
            $verify = Invoke-ReleaseTool -RepoRoot $RepoRoot -Script 'tools\ship\claim.ps1' -Arguments @('-Mod', $mod, '-Verify', '-ExpectedVersion', $version, '-Quiet')
            switch ($verify.ExitCode) { 0 { return 'done' } 5 { return 'stale' } 6 { return 'other-owner' } default { return 'pending' } }
        }
        'version' {
            if ([string]::IsNullOrWhiteSpace($version)) { return 'pending' }
            if ((Get-ReleaseSourceVersion $RepoRoot $mod) -cne $version) { return 'pending' }
            $changelog = Join-Path $RepoRoot "$mod\CHANGELOG.md"
            if (-not (Test-Path -LiteralPath $changelog -PathType Leaf)) { return 'pending' }
            if (-not (Test-ReleaseChangelogMatches $version ([IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8)))) { return 'pending' }
            $cfg = Join-Path $RepoRoot "$mod\itemV2.cfg"
            if ((Test-Path -LiteralPath $cfg) -and -not ([IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8)).Contains(" v$version")) { return 'pending' }
            $check = Invoke-ReleaseTool -RepoRoot $RepoRoot -Script 'qa\check_versions.ps1' -Arguments @('-Quiet')
            if ($check.ExitCode -ge 2) { return 'pending' }
            return 'done'
        }
        'build' {
            if ((Test-ReleaseStepDone -Step 'version' -Journal $Journal -RepoRoot $RepoRoot) -cne 'done') { return 'pending' }
            $receipts = Invoke-ReleaseTool -RepoRoot $RepoRoot -Script 'qa\check_build_receipts.ps1' -Arguments @('-Mod', $mod, '-Quiet')
            if ($receipts.ExitCode -eq 0) { return 'done' }
            return 'pending'
        }
        'commit' {
            if ((Get-ReleaseSourceVersion $RepoRoot $mod) -cne $version) { return 'pending' }
            $status = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('status', '--porcelain', '--', $mod)
            if ($status.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($status.Output)) { return 'done' }
            return 'pending'
        }
        'pull request' {
            if ([string]::IsNullOrWhiteSpace([string]$Journal.branch)) { return 'pending' }
            $view = Invoke-ReleaseGh -Arguments @('pr', 'view', [string]$Journal.branch, '--json', 'number')
            if ($view.ExitCode -eq 0 -and $view.Output -match '"number"\s*:\s*([0-9]+)') { return 'done' }
            return 'pending'
        }
        'land' {
            if ($null -eq $Journal.pr -or [int]$Journal.pr -le 0) { return 'pending' }
            $state = Get-ReleasePrState -Pr ([int]$Journal.pr)
            if ($null -ne $state -and [string]$state.state -ceq 'MERGED' -and -not [string]::IsNullOrWhiteSpace([string]$Journal.merge_commit)) { return 'done' }
            return 'pending'
        }
        'sync' {
            # A dry run changes nothing, not even remote-tracking refs.
            if (-not $script:ReleaseDryRun) { $null = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('fetch', 'origin', 'master', '--quiet') }
            $head = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('rev-parse', 'HEAD')
            $live = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('rev-parse', 'origin/master')
            $status = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('status', '--porcelain')
            if ($head.ExitCode -eq 0 -and $live.ExitCode -eq 0 -and $head.Output.Trim() -ceq $live.Output.Trim() -and [string]::IsNullOrWhiteSpace($status.Output)) { return 'done' }
            return 'pending'
        }
        'ship' {
            if ([string]::IsNullOrWhiteSpace($version)) { return 'pending' }
            if (@(Get-ReleaseLedgerRecords -Mod $mod -Version $version | Where-Object { [string]$_.status -ceq 'ok' }).Count -gt 0) { return 'done' }
            return 'pending'
        }
        'aftercare' {
            $status = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('status', '--porcelain', '--', $script:ReleasePinFile)
            if ([string]::IsNullOrWhiteSpace($status.Output)) { return 'done' }
            return 'pending'
        }
    }
    return 'pending'
}

# -NoLand is remembered in the journal: a rerun without the switch still
# leaves the merge to the merge queue or train.
function Test-ReleaseNoLand {
    param([Parameter(Mandatory)]$Journal, $Options)
    return ([bool]$Journal.no_land -or ($null -ne $Options -and [bool]$Options.NoLand))
}

# --- actions -----------------------------------------------------------------
function Invoke-ReleaseStep {
    param([Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)]$Journal, [Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$Options)
    $mod = [string]$Journal.mod
    switch ($Step) {
        'claim' {
            $claim = Invoke-ReleaseTool -RepoRoot $RepoRoot -Script 'tools\ship\claim.ps1' -Arguments @('-Mod', $mod)
            if ($claim.ExitCode -ne 0) { Write-ReleaseLog "claim.ps1 exited $($claim.ExitCode)"; return $script:ReleaseExit.StepFailed }
            $match = [regex]::Match($claim.Output, 'Allocated version:\s*(\S+)')
            if (-not $match.Success) { Write-ReleaseLog 'claim.ps1 printed no allocated version'; return $script:ReleaseExit.StepFailed }
            $Journal.version = $match.Groups[1].Value
            return 0
        }
        'version' {
            $new = [string]$Journal.version
            $lua = Get-ReleaseModMainLua $RepoRoot $mod
            $old = Get-ReleaseSourceVersion $RepoRoot $mod
            if ($null -eq $old) { Write-ReleaseLog "no MOD_VERSION in $lua"; return $script:ReleaseExit.StepFailed }
            $utf8 = New-Object Text.UTF8Encoding($false)
            # The version itemV2.cfg names is recorded before anything is written,
            # so an interrupted step still finds it on the rerun.
            if ([string]::IsNullOrWhiteSpace([string]$Journal.cfg_version)) {
                $Journal.cfg_version = $old
                Save-ReleaseJournal -Journal $Journal
            }
            if ($old -cne $new) {
                $text = [IO.File]::ReadAllText($lua, [Text.Encoding]::UTF8)
                $pattern = 'MOD_VERSION(\s*=\s*)"' + [regex]::Escape($old) + '"'
                if ([regex]::Matches($text, $pattern).Count -ne 1) { Write-ReleaseLog 'MOD_VERSION is not assigned exactly once'; return $script:ReleaseExit.StepFailed }
                [IO.File]::WriteAllText($lua, [regex]::Replace($text, $pattern, ('MOD_VERSION$1"' + $new + '"')), $utf8)
            }
            $cfg = Join-Path $RepoRoot "$mod\itemV2.cfg"
            if (Test-Path -LiteralPath $cfg -PathType Leaf) {
                $cfgText = [IO.File]::ReadAllText($cfg, [Text.Encoding]::UTF8)
                $cfgOld = [string]$Journal.cfg_version
                if ($cfgOld -cne $new -and $cfgText.Contains(" v$cfgOld")) {
                    [IO.File]::WriteAllText($cfg, $cfgText.Replace(" v$cfgOld", " v$new"), $utf8)
                }
            }
            $changelog = Join-Path $RepoRoot "$mod\CHANGELOG.md"
            $changelogText = if (Test-Path -LiteralPath $changelog) { [IO.File]::ReadAllText($changelog, [Text.Encoding]::UTF8) } else { '' }
            if (-not (Test-ReleaseChangelogMatches $new $changelogText)) {
                if ([string]::IsNullOrWhiteSpace([string]$Options.ChangelogFile) -or -not (Test-Path -LiteralPath $Options.ChangelogFile -PathType Leaf)) {
                    Write-ReleaseLog 'the version step needs -ChangelogFile (an entry with the {VERSION} token)'; return $script:ReleaseExit.Usage
                }
                $entry = ([IO.File]::ReadAllText($Options.ChangelogFile, [Text.Encoding]::UTF8)).Replace('{VERSION}', $new).TrimEnd() + "`n`n"
                $at = [regex]::Match($changelogText, '(?m)^## ')
                $changelogText = if ($at.Success) { $changelogText.Insert($at.Index, $entry) } else { $changelogText + "`n" + $entry }
                [IO.File]::WriteAllText($changelog, $changelogText, $utf8)
            }
            return 0
        }
        'build' {
            $build = Invoke-ReleaseTool -RepoRoot $RepoRoot -Script 'tools\ship\ship.ps1' -Arguments @('-Mod', $mod, '-BuildOnly')
            if ($build.ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            return 0
        }
        'commit' {
            if ([string]::IsNullOrWhiteSpace([string]$Options.CommitMessageFile) -or -not (Test-Path -LiteralPath $Options.CommitMessageFile -PathType Leaf)) {
                Write-ReleaseLog 'the commit step needs -CommitMessageFile'; return $script:ReleaseExit.Usage
            }
            $current = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('branch', '--show-current')
            if ($current.Output.Trim() -cne [string]$Journal.branch) {
                $switch = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('switch', '-c', [string]$Journal.branch)
                if ($switch.ExitCode -ne 0) { $switch = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('switch', [string]$Journal.branch) }
                if ($switch.ExitCode -ne 0) { Write-ReleaseLog "cannot switch to $($Journal.branch)"; return $script:ReleaseExit.StepFailed }
            }
            $add = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('add', '--', $mod)
            if ($add.ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            $name = (Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('config', '--global', 'user.name')).Output.Trim()
            $email = (Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('config', '--global', 'user.email')).Output.Trim()
            $commit = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('-c', "user.name=$name", '-c', "user.email=$email", 'commit', '-F', [string]$Options.CommitMessageFile)
            if ($commit.ExitCode -ne 0) { Write-ReleaseLog "git commit exited $($commit.ExitCode)"; return $script:ReleaseExit.StepFailed }
            return 0
        }
        'pull request' {
            $body = if ($Options.PrBodyFile -and (Test-Path -LiteralPath $Options.PrBodyFile -PathType Leaf)) { [IO.File]::ReadAllText($Options.PrBodyFile, [Text.Encoding]::UTF8) } else { $null }
            if ($null -eq $body -or [string]::IsNullOrWhiteSpace([string]$Options.PrTitle)) { Write-ReleaseLog 'the pull-request step needs -PrTitle and -PrBodyFile'; return $script:ReleaseExit.Usage }
            if (-not (Test-ReleasePrBody -Body $body)) { Write-ReleaseLog 'the pull-request body uses a closing keyword; write Refs #N'; return $script:ReleaseExit.BodyRejected }
            $push = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('push', '-u', 'origin', [string]$Journal.branch)
            if ($push.ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            $create = Invoke-ReleaseGh -Arguments @('pr', 'create', '--base', 'master', '--head', [string]$Journal.branch, '--title', [string]$Options.PrTitle, '--body-file', [string]$Options.PrBodyFile)
            if ($create.ExitCode -ne 0) { Write-ReleaseLog "gh pr create failed: $($create.Output)"; return $script:ReleaseExit.StepFailed }
            return 0
        }
        'land' {
            $code = Invoke-ReleaseLand -Pr ([int]$Journal.pr) -PollSeconds ([int]$Options.PollSeconds) -TimeoutMinutes ([int]$Options.TimeoutMinutes) -NoLand:(Test-ReleaseNoLand -Journal $Journal -Options $Options) -RepoRoot $RepoRoot
            if ($code -eq 0) { $Journal.merge_commit = $script:ReleaseLastMergeCommit }
            return $code
        }
        'sync' {
            $fetch = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('fetch', 'origin', 'master', '--quiet')
            if ($fetch.ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            $checkout = Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('checkout', '--detach', 'origin/master')
            if ($checkout.ExitCode -ne 0) { Write-ReleaseLog "cannot put the worktree on origin/master: $($checkout.Output)"; return $script:ReleaseExit.StepFailed }
            return 0
        }
        'ship' {
            $arguments = @('-Mod', $mod)
            if ($Options.AllowPublic) { $arguments += '-AllowPublic' }
            if ($Options.NoRemote) { $arguments += '-NoRemote' }
            $ship = Invoke-ReleaseTool -RepoRoot $RepoRoot -Script 'tools\ship\ship.ps1' -Arguments $arguments
            if ($ship.ExitCode -eq 0) { return 0 }
            return $script:ReleaseExit.StepFailed
        }
        'aftercare' {
            $pinBranch = "pins/$mod-$($Journal.version)"
            foreach ($call in @(@('switch', '-c', $pinBranch), @('add', '--', $script:ReleasePinFile))) {
                if ((Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments $call).ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            }
            $message = Join-Path ([IO.Path]::GetTempPath()) ("vt2-pins-{0}.txt" -f [guid]::NewGuid().ToString('N'))
            try {
                [IO.File]::WriteAllText($message, "chore: source pins after $mod $($Journal.version)`n", (New-Object Text.UTF8Encoding($false)))
                $name = (Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('config', '--global', 'user.name')).Output.Trim()
                $email = (Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('config', '--global', 'user.email')).Output.Trim()
                if ((Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('-c', "user.name=$name", '-c', "user.email=$email", 'commit', '-F', $message, '--', $script:ReleasePinFile)).ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            } finally { Remove-Item -LiteralPath $message -Force -ErrorAction SilentlyContinue }
            if ((Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('push', '-u', 'origin', $pinBranch)).ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            $create = Invoke-ReleaseGh -Arguments @('pr', 'create', '--base', 'master', '--head', $pinBranch, '--title', "chore: source pins after $mod $($Journal.version)", '--body', "Pin file left by the $mod $($Journal.version) ship. Refs #1328")
            if ($create.ExitCode -ne 0) { return $script:ReleaseExit.StepFailed }
            $number = [regex]::Match($create.Output, '/pull/([0-9]+)')
            if (-not $number.Success) { return $script:ReleaseExit.StepFailed }
            return (Invoke-ReleaseLand -Pr ([int]$number.Groups[1].Value) -PollSeconds ([int]$Options.PollSeconds) -TimeoutMinutes ([int]$Options.TimeoutMinutes) -NoLand:(Test-ReleaseNoLand -Journal $Journal -Options $Options) -RepoRoot $RepoRoot)
        }
    }
    return $script:ReleaseExit.StepFailed
}

# Run the given steps in order. A step whose postcondition holds is skipped.
function Invoke-ReleaseSteps {
    param([Parameter(Mandatory)][string[]]$Steps, [Parameter(Mandatory)]$Journal, [Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$Options)
    $script:ReleaseDryRun = [bool]$Options.DryRun
    foreach ($step in $Steps) {
        $state = Test-ReleaseStepDone -Step $step -Journal $Journal -RepoRoot $RepoRoot
        if ($state -ceq 'stale') { Write-ReleaseLog 'the claim is stale (verify exit 5): report it; the driver never re-claims'; return $script:ReleaseExit.ClaimStale }
        if ($state -ceq 'other-owner') { Write-ReleaseLog 'the claim belongs to another session (verify exit 6): report it; the driver never re-claims'; return $script:ReleaseExit.ClaimOtherOwner }
        if ($state -ceq 'done') {
            if ($Options.DryRun) { Write-Host ("[release] {0}: done" -f $step) } else { Write-ReleaseLog "${step}: done, skipped" }
            if ($step -ceq 'pull request' -and ($null -eq $Journal.pr -or [int]$Journal.pr -le 0)) {
                $view = Invoke-ReleaseGh -Arguments @('pr', 'view', [string]$Journal.branch, '--json', 'number')
                $m = [regex]::Match($view.Output, '"number"\s*:\s*([0-9]+)'); if ($m.Success) { $Journal.pr = [int]$m.Groups[1].Value }
            }
            continue
        }
        if ($Options.DryRun) { Write-Host ("[release] {0}: pending" -f $step); continue }
        if ($step -ceq 'ship' -and -not (Test-ReleasePreReleaseVersion ([string]$Journal.version)) -and [string]$Options.ConfirmVersion -cne [string]$Journal.version) {
            Write-ReleaseLog "version $($Journal.version) has no pre-release suffix: pass -ConfirmVersion $($Journal.version) (D-P-04)"
            return $script:ReleaseExit.CleanVersionUnconfirmed
        }
        Write-ReleaseLog "${step}: running"
        if ($step -ceq 'ship') {
            $code = 0
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                $code = Invoke-ReleaseStep -Step 'ship' -Journal $Journal -RepoRoot $RepoRoot -Options $Options
                if ((Test-ReleaseStepDone -Step 'ship' -Journal $Journal -RepoRoot $RepoRoot) -ceq 'done') { $code = 0; break }
                $last = @(Get-ReleaseLedgerRecords -Mod ([string]$Journal.mod) -Version ([string]$Journal.version)) | Select-Object -Last 1
                if ($null -eq $last -or [string]$last.message -notmatch 'is not live .*HEAD') { break }
                Write-ReleaseLog "ship attempt ${attempt}: the commit is not the live head; syncing and retrying"
                $code = $script:ReleaseExit.HeadRetriesExhausted
                if ((Invoke-ReleaseStep -Step 'sync' -Journal $Journal -RepoRoot $RepoRoot -Options $Options) -ne 0) { $code = $script:ReleaseExit.StepFailed; break }
            }
            if ($code -eq 0 -and (Test-ReleaseStepDone -Step 'ship' -Journal $Journal -RepoRoot $RepoRoot) -cne 'done') { $code = $script:ReleaseExit.StepFailed }
        } else {
            $code = Invoke-ReleaseStep -Step $step -Journal $Journal -RepoRoot $RepoRoot -Options $Options
            if ($code -eq 0 -and $step -ceq 'pull request') {
                $view = Invoke-ReleaseGh -Arguments @('pr', 'view', [string]$Journal.branch, '--json', 'number')
                $m = [regex]::Match($view.Output, '"number"\s*:\s*([0-9]+)'); if ($m.Success) { $Journal.pr = [int]$m.Groups[1].Value }
            }
            if ($code -eq 0 -and (Test-ReleaseStepDone -Step $step -Journal $Journal -RepoRoot $RepoRoot) -cne 'done') {
                Write-ReleaseLog "${step}: finished, but its postcondition does not hold"
                $code = $script:ReleaseExit.StepFailed
            }
        }
        Add-ReleaseJournalStep -Journal $Journal -Name $step -Result $(if ($code -eq 0) { 'done' } else { "exit $code" })
        Save-ReleaseJournal -Journal $Journal
        if ($code -ne 0) { return $code }
    }
    return 0
}

# The shared primary checkout is read-only for agents: its git dir is the common dir.
function Test-ReleasePrimaryCheckout {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $gitDir = (Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('rev-parse', '--absolute-git-dir')).Output.Trim()
    $common = (Invoke-ReleaseGit -RepoRoot $RepoRoot -Arguments @('rev-parse', '--path-format=absolute', '--git-common-dir')).Output.Trim()
    if ([string]::IsNullOrWhiteSpace($gitDir) -or [string]::IsNullOrWhiteSpace($common)) { return $true }
    return ([IO.Path]::GetFullPath($gitDir).TrimEnd('\', '/') -ieq [IO.Path]::GetFullPath($common).TrimEnd('\', '/'))
}
