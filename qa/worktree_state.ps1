# worktree_state.ps1 - exact Git-visible worktree snapshots for QA purity.
#
# Owned by: qa/run_all.ps1. This helper does not mutate the repository. It
# fingerprints tracked/index state plus the names and contents of every
# non-ignored untracked file, so QA can prove that it preserves even an
# intentionally dirty developer worktree (#546).

function Invoke-QAStateGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) (
        'vt2-qa-git-stderr-' + [Guid]::NewGuid().ToString('N'))
    $previousErrorAction = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 turns native stderr into ErrorRecord objects;
        # do not let a successful Git warning become a terminating exception.
        $ErrorActionPreference = 'Continue'
        $output = @(& git -C $RepoRoot @Arguments 2> $stderrPath)
        $exitCode = $LASTEXITCODE
        $stderr = if ([IO.File]::Exists($stderrPath)) {
            [IO.File]::ReadAllText($stderrPath).Trim()
        } else { '' }
    } finally {
        $ErrorActionPreference = $previousErrorAction
        if ([IO.File]::Exists($stderrPath)) { [IO.File]::Delete($stderrPath) }
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed (exit $exitCode): $stderr"
    }
    return @($output | ForEach-Object { [string]$_ })
}

function Get-QAWorktreeState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $resolved = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    $inside = @(Invoke-QAStateGit -RepoRoot $resolved -Arguments @(
        'rev-parse', '--is-inside-work-tree'))
    if ($inside.Count -ne 1 -or $inside[0].Trim() -ne 'true') {
        throw "not a Git worktree: $resolved"
    }

    $status = @(Invoke-QAStateGit -RepoRoot $resolved -Arguments @(
        '-c', 'core.quotepath=false', 'status', '--porcelain=v1',
        '--untracked-files=all'))
    $indexDiff = @(Invoke-QAStateGit -RepoRoot $resolved -Arguments @(
        '-c', 'core.quotepath=false', 'diff', '--cached', '--binary',
        '--no-ext-diff', '--no-textconv', '--'))
    $worktreeDiff = @(Invoke-QAStateGit -RepoRoot $resolved -Arguments @(
        '-c', 'core.quotepath=false', 'diff', '--binary', '--no-ext-diff',
        '--no-textconv', '--'))
    $untracked = @(Invoke-QAStateGit -RepoRoot $resolved -Arguments @(
        '-c', 'core.quotepath=false', 'ls-files', '--others',
        '--exclude-standard') | Sort-Object)

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add('status')
    foreach ($line in $status) { $parts.Add($line) }
    $parts.Add('index-diff')
    foreach ($line in $indexDiff) { $parts.Add($line) }
    $parts.Add('worktree-diff')
    foreach ($line in $worktreeDiff) { $parts.Add($line) }
    $parts.Add('untracked-content')
    $untrackedRows = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $untracked) {
        $hash = @(Invoke-QAStateGit -RepoRoot $resolved -Arguments @(
            'hash-object', '--no-filters', '--', $path))
        if ($hash.Count -ne 1 -or $hash[0] -notmatch '^[0-9a-f]{40,64}$') {
            throw "could not hash untracked path: $path"
        }
        $row = "$path=$($hash[0])"
        $untrackedRows.Add($row)
        $parts.Add($row)
    }

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $parts))
        $digest = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }

    return [pscustomobject]@{
        Fingerprint = $digest
        Status = @($status)
        Untracked = @($untrackedRows)
        IndexDiffLines = $indexDiff.Count
        WorktreeDiffLines = $worktreeDiff.Count
    }
}

function Test-QAWorktreeStateEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After
    )
    return [string]$Before.Fingerprint -ceq [string]$After.Fingerprint
}

function Invoke-QAWorktreeStateSelfTest {
    [CmdletBinding()]
    param()

    $temp = Join-Path ([IO.Path]::GetTempPath()) (
        'vt2-qa-worktree-state-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temp) | Out-Null
    try {
        Invoke-QAStateGit -RepoRoot $temp -Arguments @('init', '-q') | Out-Null
        $tracked = Join-Path $temp 'tracked.txt'
        [IO.File]::WriteAllText($tracked, "baseline`n")
        Invoke-QAStateGit -RepoRoot $temp -Arguments @('add', '--', 'tracked.txt') | Out-Null
        Invoke-QAStateGit -RepoRoot $temp -Arguments @(
            '-c', 'user.name=QA Fixture', '-c', 'user.email=qa@example.invalid',
            'commit', '-q', '-m', 'fixture') | Out-Null

        $clean = Get-QAWorktreeState -RepoRoot $temp
        $cleanAgain = Get-QAWorktreeState -RepoRoot $temp
        if (-not (Test-QAWorktreeStateEqual $clean $cleanAgain)) {
            throw 'identical clean snapshots differ'
        }

        $scratch = Join-Path $temp 'scratch.txt'
        [IO.File]::WriteAllText($scratch, "one`n")
        $untrackedOne = Get-QAWorktreeState -RepoRoot $temp
        [IO.File]::WriteAllText($scratch, "two`n")
        $untrackedTwo = Get-QAWorktreeState -RepoRoot $temp
        if ((Test-QAWorktreeStateEqual $clean $untrackedOne) -or
                (Test-QAWorktreeStateEqual $untrackedOne $untrackedTwo)) {
            throw 'untracked name/content mutation was not detected'
        }
        [IO.File]::Delete($scratch)

        # Preserve the same final worktree bytes and the same MM status while
        # changing only the staged intermediate content. A combined HEAD diff
        # plus porcelain status cannot distinguish this case.
        [IO.File]::WriteAllText($tracked, "staged-one`n")
        Invoke-QAStateGit -RepoRoot $temp -Arguments @(
            'add', '--', 'tracked.txt') | Out-Null
        [IO.File]::WriteAllText($tracked, "worktree`n")
        $indexOne = Get-QAWorktreeState -RepoRoot $temp
        [IO.File]::WriteAllText($tracked, "staged-two`n")
        Invoke-QAStateGit -RepoRoot $temp -Arguments @(
            'add', '--', 'tracked.txt') | Out-Null
        [IO.File]::WriteAllText($tracked, "worktree`n")
        $indexTwo = Get-QAWorktreeState -RepoRoot $temp
        if (Test-QAWorktreeStateEqual $indexOne $indexTwo) {
            throw 'index-only content mutation was not detected'
        }
        Invoke-QAStateGit -RepoRoot $temp -Arguments @(
            'reset', '-q', 'HEAD', '--', 'tracked.txt') | Out-Null

        [IO.File]::WriteAllText($tracked, "changed`n")
        $trackedChanged = Get-QAWorktreeState -RepoRoot $temp
        if (Test-QAWorktreeStateEqual $clean $trackedChanged) {
            throw 'tracked content mutation was not detected'
        }
        [IO.File]::WriteAllText($tracked, "baseline`n")
        $restored = Get-QAWorktreeState -RepoRoot $temp
        if (-not (Test-QAWorktreeStateEqual $clean $restored)) {
            throw 'restored worktree did not return to its original fingerprint'
        }
    } finally {
        if ([IO.Directory]::Exists($temp)) {
            # Git may create read-only loose-object files on Windows. Normalize
            # only this GUID-scoped fixture tree before removing it so cleanup
            # is reliable under both Windows PowerShell 5.1 and PowerShell 7.
            foreach ($path in [IO.Directory]::EnumerateFiles(
                    $temp, '*', [IO.SearchOption]::AllDirectories)) {
                [IO.File]::SetAttributes($path, [IO.FileAttributes]::Normal)
            }
            [IO.Directory]::Delete($temp, $true)
        }
    }
}
