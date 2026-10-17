# Change-set scope for the ordinary-QA weapon-history freshness gate (#1683).
#
# Only weapon_tweaker and weapon_tweaker_dev consume the weapon-history source
# provenance. A reachable canonical ref/tip move therefore blocks ordinary QA
# (pre-commit, hosted QA, ship headless QA) only when the change being checked
# touches a weapon-history input or either WT stream; any other change set gets
# a visible advisory instead. WT and WT Dev BuildOnly/release keep the hard
# gate unchanged (tools/ship/ship.ps1 passes -RequireRemoteFresh, which never
# reaches this scope logic). An indeterminate change set fails closed.
#
# Dot-sourced by check_wt_history_source_freshness.ps1, whose -SelfTest owns
# these fixtures under both supported PowerShell hosts. Windows PowerShell 5.1
# compatible and ASCII-only.

$script:WtHistoryScopePrefixes = @(
    'weapon_tweaker/',
    'weapon_tweaker_dev/',
    'tools/weapon-history/'
)

# Pure classifier: does one repo-relative path feed weapon-history provenance
# or either WT stream? qa/ paths qualify when they name wt_history (the gate,
# this helper, the reproducers, host matrices, fixtures and Lua tests).
function Test-WtHistoryScopePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $norm = $Path.Trim().Replace('\', '/')
    foreach ($prefix in $script:WtHistoryScopePrefixes) {
        if ($norm.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return ($norm.StartsWith('qa/', [StringComparison]::OrdinalIgnoreCase) -and
        $norm.IndexOf('wt_history', [StringComparison]::OrdinalIgnoreCase) -ge 0)
}

# Hosted QA context. Parameters default to the GitHub Actions environment so the
# self-test can pass every value explicitly.
function Get-WtHistoryHostedContext {
    param(
        [string]$GitHubActions = $env:GITHUB_ACTIONS,
        [string]$EventName = $env:GITHUB_EVENT_NAME,
        [string]$EventPath = $env:GITHUB_EVENT_PATH,
        [string]$BaseRef = $env:GITHUB_BASE_REF
    )
    $context = [pscustomobject]@{
        Hosted = ($GitHubActions -ceq 'true')
        EventName = "$EventName"
        BaseRef = "$BaseRef"
        PushBefore = ''
        Error = ''
    }
    if ($context.Hosted -and [string]::IsNullOrEmpty($context.BaseRef) -and
        $context.EventName -ceq 'push') {
        try {
            if ([string]::IsNullOrWhiteSpace($EventPath) -or
                -not [IO.Path]::IsPathRooted($EventPath)) {
                throw 'GITHUB_EVENT_PATH is not an absolute path'
            }
            $payload = [IO.File]::ReadAllText($EventPath) | ConvertFrom-Json
            $context.PushBefore = "$($payload.before)"
        }
        catch { $context.Error = "push event payload unreadable: $($_.Exception.Message)" }
    }
    return $context
}

# Split git -z output into exact paths. Git C-quotes a path holding a double
# quote, backslash or control character even with core.quotepath=false, and a
# quoted path would miss every scope prefix, so path lists are always read
# NUL-separated. PowerShell hands native output over line by line; rejoining
# with LF restores any LF inside a name before the NUL split.
function Split-WtHistoryNulPathList {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Output)
    if ($null -eq $Output -or $Output.Count -eq 0) { return @() }
    return @(($Output -join "`n").Split([char]0) | Where-Object { $_.Length -gt 0 })
}

function Invoke-WtHistoryScopeGit {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$GitArgs,
        [switch]$NulPaths
    )
    # Windows PowerShell 5.1 turns redirected native stderr into error records;
    # under a caller's Stop preference the first one would terminate the probe.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $RepoRoot -c core.quotepath=false @GitArgs 2>$null
        $code = $LASTEXITCODE
    }
    catch {
        $output = @()
        $code = 127
    }
    finally { $ErrorActionPreference = $previous }
    $text = @($output | ForEach-Object { "$_" })
    if ($NulPaths) { $lines = @(Split-WtHistoryNulPathList $text) }
    else { $lines = @($text | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
    return [pscustomobject]@{
        ExitCode = [int]$code
        Lines = $lines
    }
}

function New-WtHistoryChangeSet([bool]$Determinate, [string]$Source, [string[]]$Paths, [string]$Reason) {
    return [pscustomobject]@{
        Determinate = $Determinate
        Source = $Source
        Paths = @($Paths)
        Reason = $Reason
    }
}

# Resolve the change set ordinary QA is checking:
#   -Staged (pre-commit)   the index only
#   otherwise              index + working tree, plus one committed range:
#                          hosted PR      origin/<base>...HEAD
#                          hosted push    <before>...HEAD
#                          anything else  origin/master...HEAD (the branch's
#                                         commits; empty on the default branch)
#                          and, off GitHub Actions, untracked unignored files
# A missing range base, or any git failure, is indeterminate.
function Get-WtHistoryFreshnessChangeSet {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$Staged,
        $Context
    )
    if ($null -eq $Context) { $Context = Get-WtHistoryHostedContext }
    $probe = Invoke-WtHistoryScopeGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--is-inside-work-tree')
    if ($probe.ExitCode -ne 0) {
        return New-WtHistoryChangeSet $false 'none' @() "not a git work tree: $RepoRoot"
    }

    $nameOnly = @('diff', '--name-only', '--no-renames', '-z')
    $queries = New-Object 'System.Collections.Generic.List[object]'
    $queries.Add([pscustomobject]@{ Label = 'staged'; Args = @($nameOnly + '--cached') }) | Out-Null
    if (-not $Staged) {
        $queries.Add([pscustomobject]@{ Label = 'unstaged'; Args = $nameOnly }) | Out-Null
        if (-not [string]::IsNullOrEmpty($Context.BaseRef)) {
            if ($Context.BaseRef -cnotmatch '^[A-Za-z0-9._/-]+$') {
                return New-WtHistoryChangeSet $false 'pr' @() "unsafe PR base ref '$($Context.BaseRef)'"
            }
            $range = "origin/$($Context.BaseRef)...HEAD"
            $queries.Add([pscustomobject]@{ Label = "PR range $range"; Args = @($nameOnly + $range) }) | Out-Null
        }
        elseif ($Context.Hosted -and $Context.EventName -ceq 'push') {
            if ($Context.Error) { return New-WtHistoryChangeSet $false 'push' @() $Context.Error }
            if ($Context.PushBefore -cnotmatch '^[0-9a-f]{40}$' -or $Context.PushBefore -ceq ('0' * 40)) {
                return New-WtHistoryChangeSet $false 'push' @() "push event has no usable 'before' commit ('$($Context.PushBefore)')"
            }
            $range = "$($Context.PushBefore)...HEAD"
            $queries.Add([pscustomobject]@{ Label = "push range $range"; Args = @($nameOnly + $range) }) | Out-Null
        }
        else {
            # Local runs and hosted workflow_dispatch: count the branch's own
            # commits against the default branch (qa.yml checks out with
            # fetch-depth 0, so origin/master exists there too).
            $base = 'refs/remotes/origin/master'
            $baseProbe = Invoke-WtHistoryScopeGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--verify', '--quiet', $base)
            if ($baseProbe.ExitCode -ne 0) {
                return New-WtHistoryChangeSet $false 'branch' @() "no $base to measure the branch's commits against"
            }
            $queries.Add([pscustomobject]@{ Label = 'branch range origin/master...HEAD'; Args = @($nameOnly + "$base...HEAD") }) | Out-Null
        }
        if (-not $Context.Hosted) {
            $queries.Add([pscustomobject]@{ Label = 'untracked'; Args = @('ls-files', '--others', '--exclude-standard', '-z') }) | Out-Null
        }
    }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $labels = @()
    foreach ($query in $queries) {
        $result = Invoke-WtHistoryScopeGit -RepoRoot $RepoRoot -GitArgs $query.Args -NulPaths
        if ($result.ExitCode -ne 0) {
            return New-WtHistoryChangeSet $false $query.Label @() "git $($query.Args -join ' ') exited $($result.ExitCode)"
        }
        foreach ($line in $result.Lines) { [void]$paths.Add($line) }
        $labels += $query.Label
    }
    return New-WtHistoryChangeSet $true ($labels -join ' + ') @($paths) ''
}

# Apply the change-set scope to one Test-WtHistoryRemoteProbe result. Only an
# optional (non-release) moved ref/tip is ever downgraded, and only to the
# 'advisory' state when the change set is determinate and touches nothing in
# scope. Pass, skip, malformed/ambiguous and required results are unchanged.
function Resolve-WtHistoryFreshnessOutcome {
    param(
        [Parameter(Mandatory)]$Result,
        $ChangeSet,
        [switch]$Required
    )
    $moved = $Result.PSObject.Properties['Moved'] -and [bool]$Result.Moved
    if ($Result.State -cne 'fail' -or -not $moved -or $Required) { return $Result }
    $reanchor = 'Re-anchor tools/weapon-history/current_source_anchor.lua to the moved tip (the #1682 transaction)'
    if ($null -eq $ChangeSet -or -not $ChangeSet.Determinate) {
        $reason = if ($null -eq $ChangeSet) { 'no change set' } else { $ChangeSet.Reason }
        return [pscustomobject]@{
            State = 'fail'; Moved = $true
            Message = "$($Result.Message); the change set could not be resolved ($reason), so ordinary QA fails closed. $reanchor (#1683)."
        }
    }
    $hits = @($ChangeSet.Paths | Where-Object { Test-WtHistoryScopePath $_ } | Sort-Object)
    if ($hits.Count -gt 0) {
        $shown = @($hits[0..([Math]::Min(3, $hits.Count) - 1)]) -join ', '
        if ($hits.Count -gt 3) { $shown += ", +$($hits.Count - 3) more" }
        return [pscustomobject]@{
            State = 'fail'; Moved = $true
            Message = "$($Result.Message); the $($ChangeSet.Source) change set touches weapon-history inputs or a WT stream ($shown), so ordinary QA fails closed. $reanchor first (#1683)."
        }
    }
    return [pscustomobject]@{
        State = 'advisory'; Moved = $true
        Message = "$($Result.Message); the $($ChangeSet.Source) change set ($($ChangeSet.Paths.Count) path(s)) touches no weapon-history input or WT stream, so this ordinary QA run continues. $reanchor before any WT or WT Dev BuildOnly/release, which still fails closed (#1683)."
    }
}

# The whole decision the gate's main body applies to one probe result, so the
# self-test drives the same path end to end: resolve the change set lazily (an
# optional moved ref/tip only), apply the scope, then map the final state to the
# printed line and the process exit code (pass/skip 0, advisory 1, fail 2).
function Invoke-WtHistoryFreshnessDecision {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$Staged,
        [switch]$RequireRemoteFresh,
        [switch]$Quiet,
        $Context
    )
    $outcome = $Result
    $moved = $Result.PSObject.Properties['Moved'] -and [bool]$Result.Moved
    if ($Result.State -ceq 'fail' -and $moved -and -not $RequireRemoteFresh) {
        $changeSet = Get-WtHistoryFreshnessChangeSet -RepoRoot $RepoRoot -Staged:$Staged -Context $Context
        $outcome = Resolve-WtHistoryFreshnessOutcome -Result $Result -ChangeSet $changeSet `
            -Required:$RequireRemoteFresh
    }
    $state = "$($outcome.State)"
    if ($state -ceq 'pass') { $code = 0; $color = 'Green' }
    elseif ($state -ceq 'skip') { $code = 0; $color = 'Yellow' }
    elseif ($state -ceq 'advisory') { $code = 1; $color = 'Yellow' }
    else { $code = 2; $color = 'Red' }
    $label = if ($code -eq 2) { 'ERROR' } else { $state.ToUpperInvariant() }
    return [pscustomobject]@{
        State = $state
        Message = "$($outcome.Message)"
        ExitCode = $code
        Print = ($code -ne 0 -or $state -ceq 'skip' -or -not $Quiet)
        Line = "[check_wt_history_source_freshness] $label - $($outcome.Message)"
        Color = $color
    }
}
