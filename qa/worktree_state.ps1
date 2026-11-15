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

# Files a gate may scan: tracked plus untracked-but-not-ignored, as full paths
# (WP-T-06). Git-ignored scratch copies of mod trees (`.temp/`, `.claude/`,
# build output) are never returned, so a gate reads the same files in a dirty
# developer checkout as in CI. -Filter is a file-name wildcard ('*.lua');
# -Path limits the listing to repo-relative pathspecs. A deleted tracked file
# is skipped. Outside a Git worktree (a gate's temp fixture folder) the folder
# is walked on disk instead. -AsFileInfo returns [IO.FileInfo] objects for
# callers written against Get-ChildItem.
function Get-QATrackedFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Filter = '*',
        [string[]]$Path = @(),
        [switch]$AsFileInfo
    )

    $resolved = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    $inside = $false
    try {
        $probe = @(Invoke-QAStateGit -RepoRoot $resolved -Arguments @('rev-parse', '--is-inside-work-tree'))
        $inside = ($probe.Count -eq 1 -and $probe[0].Trim() -eq 'true')
    } catch { $inside = $false }

    $paths = [System.Collections.Generic.List[string]]::new()
    if ($inside) {
        $arguments = @('--no-optional-locks', '-c', 'core.quotepath=false', 'ls-files',
            '--cached', '--others', '--exclude-standard', '--')
        if ($Path.Count -gt 0) { $arguments += $Path } else { $arguments += '.' }
        # One ordinal order on every platform (disk enumeration order differs
        # between NTFS, exFAT and ext4); a conflicted path is listed once per
        # stage and a nested repository as 'dir/'.
        $listed = [string[]]@(Invoke-QAStateGit -RepoRoot $resolved -Arguments $arguments)
        [Array]::Sort($listed, [StringComparer]::Ordinal)
        $previous = $null
        foreach ($relative in $listed) {
            if ([string]::IsNullOrEmpty($relative) -or $relative.EndsWith('/') -or $relative -ceq $previous) { continue }
            $previous = $relative
            if ([IO.Path]::GetFileName($relative) -notlike $Filter) { continue }
            $full = [IO.Path]::GetFullPath((Join-Path $resolved $relative))
            if ([IO.File]::Exists($full)) { $paths.Add($full) }
        }
    } else {
        $roots = if ($Path.Count -gt 0) { @($Path | ForEach-Object { Join-Path $resolved $_ }) } else { @($resolved) }
        foreach ($walkRoot in $roots) {
            if (-not (Test-Path -LiteralPath $walkRoot -PathType Container)) { continue }
            # enumeration-ok: fallback for a folder that is not a Git worktree (gate self-test fixtures)
            foreach ($file in @(Get-ChildItem -LiteralPath $walkRoot -Recurse -File -Filter $Filter -ErrorAction SilentlyContinue)) {
                $paths.Add($file.FullName)
            }
        }
    }
    if ($AsFileInfo) { return @($paths | ForEach-Object { [IO.FileInfo]::new($_) }) }
    return @($paths)
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

        # Get-QATrackedFiles (WP-T-06): tracked plus untracked-but-not-ignored
        # files; a git-ignored copy of a mod tree and a deleted tracked file are
        # never returned; a folder outside Git is walked on disk.
        [IO.File]::WriteAllText((Join-Path $temp '.gitignore'), "ignored/`n")
        [IO.Directory]::CreateDirectory((Join-Path $temp 'ignored\mod')) | Out-Null
        [IO.File]::WriteAllText((Join-Path $temp 'ignored\mod\copy.lua'), "x`n")
        [IO.File]::WriteAllText((Join-Path $temp 'new.lua'), "x`n")
        $names = @(Get-QATrackedFiles -RepoRoot $temp | ForEach-Object { [IO.Path]::GetFileName($_) })
        if (($names -join ',') -cne '.gitignore,new.lua,tracked.txt') {
            throw "Get-QATrackedFiles listed '$($names -join ',')' instead of .gitignore,new.lua,tracked.txt"
        }
        $lua = @(Get-QATrackedFiles -RepoRoot $temp -Filter '*.lua' -AsFileInfo)
        if ($lua.Count -ne 1 -or $lua[0].Name -cne 'new.lua' -or $lua[0] -isnot [IO.FileInfo]) {
            throw 'Get-QATrackedFiles -Filter *.lua -AsFileInfo did not return only new.lua as a FileInfo'
        }
        [IO.File]::Delete($tracked)
        if (@(Get-QATrackedFiles -RepoRoot $temp | Where-Object { $_ -like '*tracked.txt' }).Count -ne 0) {
            throw 'Get-QATrackedFiles returned a deleted tracked file'
        }
        $plain = Join-Path ([IO.Path]::GetTempPath()) ('vt2-qa-plain-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory((Join-Path $plain 'sub')) | Out-Null
        try {
            [IO.File]::WriteAllText((Join-Path $plain 'sub\a.lua'), "x`n")
            if (@(Get-QATrackedFiles -RepoRoot $plain -Filter '*.lua').Count -ne 1) {
                throw 'Get-QATrackedFiles did not walk a folder outside Git'
            }
        } finally {
            [IO.Directory]::Delete($plain, $true)
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
