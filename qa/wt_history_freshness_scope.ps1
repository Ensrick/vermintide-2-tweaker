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

function Invoke-WtHistoryScopeGit {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string[]]$GitArgs)
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
    return [pscustomobject]@{
        ExitCode = [int]$code
        Lines = @($output | ForEach-Object { "$_" } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
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
#   otherwise              index + working tree, plus the hosted PR range
#                          (origin/<base>...HEAD) or push range (<before>...HEAD)
# A hosted run without a resolvable range, or any git failure, is indeterminate.
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

    $queries = New-Object 'System.Collections.Generic.List[object]'
    $queries.Add([pscustomobject]@{ Label = 'staged'; Args = @('diff', '--cached', '--name-only', '--no-renames') }) | Out-Null
    if (-not $Staged) {
        $queries.Add([pscustomobject]@{ Label = 'unstaged'; Args = @('diff', '--name-only', '--no-renames') }) | Out-Null
        if (-not [string]::IsNullOrEmpty($Context.BaseRef)) {
            if ($Context.BaseRef -cnotmatch '^[A-Za-z0-9._/-]+$') {
                return New-WtHistoryChangeSet $false 'pr' @() "unsafe PR base ref '$($Context.BaseRef)'"
            }
            $range = "origin/$($Context.BaseRef)...HEAD"
            $queries.Add([pscustomobject]@{ Label = "PR range $range"; Args = @('diff', '--name-only', '--no-renames', $range) }) | Out-Null
        }
        elseif ($Context.Hosted -and $Context.EventName -ceq 'push') {
            if ($Context.Error) { return New-WtHistoryChangeSet $false 'push' @() $Context.Error }
            if ($Context.PushBefore -cnotmatch '^[0-9a-f]{40}$' -or $Context.PushBefore -ceq ('0' * 40)) {
                return New-WtHistoryChangeSet $false 'push' @() "push event has no usable 'before' commit ('$($Context.PushBefore)')"
            }
            $range = "$($Context.PushBefore)...HEAD"
            $queries.Add([pscustomobject]@{ Label = "push range $range"; Args = @('diff', '--name-only', '--no-renames', $range) }) | Out-Null
        }
        elseif ($Context.Hosted) {
            return New-WtHistoryChangeSet $false 'hosted' @() "hosted '$($Context.EventName)' run has no PR or push range"
        }
    }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $labels = @()
    foreach ($query in $queries) {
        $result = Invoke-WtHistoryScopeGit -RepoRoot $RepoRoot -GitArgs $query.Args
        if ($result.ExitCode -ne 0) {
            return New-WtHistoryChangeSet $false $query.Label @() "git $($query.Args -join ' ') exited $($result.ExitCode)"
        }
        foreach ($line in $result.Lines) { [void]$paths.Add($line.Trim()) }
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
