# check_worktree_budget.ps1 - blocking local worktree count/disk budget.
#
# A 2026-07-30 cleanup found 707 registered worktrees and reclaimed at least
# 323.81 GiB. This guard prevents recurrence without deleting anything. It is
# safe in CI: a normal checkout has no secondary worktrees.
#
# Exit codes:
#   0 = within budget
#   1 = advisory finding (large individual tree or stale registration)
#   2 = secondary-worktree count or aggregate-disk budget exceeded

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [ValidateRange(0, 128)][int]$MaxAdditionalWorktrees = 8,
    [ValidateRange(1, 1024)][double]$MaxAdditionalGiB = 12,
    [ValidateRange(1, 1024)][double]$WarnIndividualGiB = 2,
    [switch]$SkipSize,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Get-WorktreeBudgetResult {
    param(
        [object[]]$Worktrees,
        [int]$MaxAdditional,
        [double]$MaxGiB,
        [double]$WarnGiB
    )

    $live = @($Worktrees | Where-Object { $_.Exists })
    $additional = @($live | Where-Object { -not $_.Primary })
    $missing = @($Worktrees | Where-Object { -not $_.Exists })
    $totalBytes = [int64](($additional | Measure-Object -Property Bytes -Sum).Sum)
    $errors = @()
    $warnings = @()

    if ($additional.Count -gt $MaxAdditional) {
        $errors += "secondary worktrees $($additional.Count) exceed limit $MaxAdditional"
    }
    if ($totalBytes -gt [int64]($MaxGiB * 1GB)) {
        $errors += ("secondary worktrees use {0:N2} GiB, exceeding {1:N2} GiB" -f ($totalBytes / 1GB), $MaxGiB)
    }
    foreach ($tree in $additional) {
        if ([int64]$tree.Bytes -gt [int64]($WarnGiB * 1GB)) {
            $warnings += ("large worktree {0}: {1:N2} GiB" -f $tree.Path, ([int64]$tree.Bytes / 1GB))
        }
    }
    foreach ($tree in $missing) {
        $warnings += "stale registration has no directory: $($tree.Path)"
    }

    return [pscustomobject]@{
        Additional = $additional
        Missing = $missing
        TotalBytes = $totalBytes
        Errors = $errors
        Warnings = $warnings
    }
}

function Get-DirectoryBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return [int64]0 }
    $measure = Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum
    if ($null -eq $measure.Sum) { return [int64]0 }
    return [int64]$measure.Sum
}

function Get-GitWorktrees([string]$Root, [switch]$NoSize) {
    $raw = @(& git -C $Root worktree list --porcelain 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git worktree list failed: $($raw -join [Environment]::NewLine)"
    }

    $records = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in ($raw + '')) {
        if ($line -like 'worktree *') {
            if ($null -ne $current) { $records.Add($current) }
            $current = [ordered]@{
                Path = $line.Substring(9)
                Head = ''
                Branch = '(detached)'
            }
        } elseif ($null -ne $current -and $line -like 'HEAD *') {
            $current.Head = $line.Substring(5)
        } elseif ($null -ne $current -and $line -like 'branch *') {
            $current.Branch = $line.Substring(7) -replace '^refs/heads/', ''
        } elseif ($line -eq '' -and $null -ne $current) {
            $records.Add($current)
            $current = $null
        }
    }

    $output = @()
    for ($i = 0; $i -lt $records.Count; $i++) {
        $path = [string]$records[$i].Path
        $exists = Test-Path -LiteralPath $path -PathType Container
        $bytes = if ($exists -and -not $NoSize) { Get-DirectoryBytes $path } else { [int64]0 }
        $dirty = $false
        if ($exists) {
            $status = @(& git -C $path status --porcelain=v1 --untracked-files=all 2>$null)
            $dirty = ($LASTEXITCODE -eq 0 -and $status.Count -gt 0)
        }
        $output += [pscustomobject]@{
            Primary = ($i -eq 0)
            Path = $path
            Branch = [string]$records[$i].Branch
            Head = [string]$records[$i].Head
            Exists = $exists
            Dirty = $dirty
            Bytes = [int64]$bytes
        }
    }
    return $output
}

if ($SelfTest) {
    $fixtures = @(
        [pscustomobject]@{ Primary = $true; Path = 'C:\repo'; Exists = $true; Bytes = 20GB },
        [pscustomobject]@{ Primary = $false; Path = 'C:\wt-a'; Exists = $true; Bytes = 1GB },
        [pscustomobject]@{ Primary = $false; Path = 'C:\wt-b'; Exists = $true; Bytes = 2GB }
    )
    $failures = @()
    $ok = Get-WorktreeBudgetResult $fixtures 2 4 3
    if ($ok.Errors.Count -ne 0) { $failures += 'under-budget fixture failed' }
    if ($ok.TotalBytes -ne 3GB) { $failures += 'primary bytes leaked into secondary total' }

    $countExceeded = Get-WorktreeBudgetResult $fixtures 1 4 3
    if ($countExceeded.Errors.Count -ne 1 -or $countExceeded.Errors[0] -notmatch 'exceed limit') {
        $failures += 'count limit not enforced'
    }

    $bytesExceeded = Get-WorktreeBudgetResult $fixtures 2 2.5 3
    if ($bytesExceeded.Errors.Count -ne 1 -or $bytesExceeded.Errors[0] -notmatch 'exceeding') {
        $failures += 'disk limit not enforced'
    }

    $largeAndMissing = @(
        $fixtures[0],
        [pscustomobject]@{ Primary = $false; Path = 'C:\wt-large'; Exists = $true; Bytes = 4GB },
        [pscustomobject]@{ Primary = $false; Path = 'C:\wt-gone'; Exists = $false; Bytes = 0 }
    )
    $warn = Get-WorktreeBudgetResult $largeAndMissing 2 8 2
    if ($warn.Warnings.Count -ne 2) { $failures += 'large/missing warnings not reported' }

    if ($failures.Count -gt 0) {
        Write-Host '[check_worktree_budget -SelfTest] FAILED' -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        exit 2
    }
    Write-Host '[check_worktree_budget -SelfTest] OK - count, disk, primary exclusion, and warnings pass.' -ForegroundColor Green
    exit 0
}

try {
    $resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    $worktrees = @(Get-GitWorktrees $resolvedRoot -NoSize:$SkipSize)
    $result = Get-WorktreeBudgetResult $worktrees $MaxAdditionalWorktrees $MaxAdditionalGiB $WarnIndividualGiB
} catch {
    Write-Host "[check_worktree_budget] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 90
}

if (-not $Quiet -or $result.Errors.Count -gt 0 -or $result.Warnings.Count -gt 0) {
    $rows = @($worktrees | Where-Object { -not $_.Primary } | Sort-Object Bytes -Descending | ForEach-Object {
        [pscustomobject]@{
            GiB = if ($SkipSize) { 'n/a' } else { '{0:N2}' -f ($_.Bytes / 1GB) }
            State = if (-not $_.Exists) { 'MISSING' } elseif ($_.Dirty) { 'dirty' } else { 'clean' }
            Branch = $_.Branch
            Path = $_.Path
        }
    })
    if ($rows.Count -gt 0) { $rows | Format-Table -AutoSize | Out-Host }
}

foreach ($warning in $result.Warnings) {
    Write-Host "[check_worktree_budget] WARNING - $warning" -ForegroundColor Yellow
}
foreach ($budgetError in $result.Errors) {
    Write-Host "[check_worktree_budget] ERROR - $budgetError" -ForegroundColor Red
}

if ($result.Errors.Count -gt 0) {
    Write-Host '[check_worktree_budget] Close finished worktrees with tools/worktrees/worktree.ps1 -Action Close.' -ForegroundColor Red
    exit 2
}
if ($result.Warnings.Count -gt 0) { exit 1 }

if (-not $Quiet) {
    $sizeText = if ($SkipSize) { 'size scan skipped' } else { '{0:N2}/{1:N2} GiB' -f ($result.TotalBytes / 1GB), $MaxAdditionalGiB }
    Write-Host "[check_worktree_budget] OK - $($result.Additional.Count)/$MaxAdditionalWorktrees secondary worktrees, $sizeText." -ForegroundColor Green
}
exit 0
