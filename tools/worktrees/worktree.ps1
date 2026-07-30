# worktree.ps1 - the approved VT2 linked-worktree lifecycle.
#
# Create enforces the repository count budget and defaults outside source/repos.
# Close refuses source changes and protects ambiguous ignored files. The only
# force removal it performs is a clean registered worktree whose ignored files
# all match the narrow generated/machine-local allowlist below.

[CmdletBinding()]
param(
    [ValidateSet('Audit', 'Create', 'Close')]
    [string]$Action,
    [string]$RepoRoot,
    [string]$Name,
    [string]$TargetPath,
    [string]$Branch,
    [string]$BaseRef = 'origin/master',
    [ValidateRange(0, 128)][int]$MaxAdditionalWorktrees = 8,
    [ValidateRange(1, 1024)][double]$MaxAdditionalGiB = 12,
    [switch]$DeleteMergedBranch,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([string]$At, [string[]]$GitArgs, [switch]$AllowFailure)
    $output = @(& git -C $At @GitArgs 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($GitArgs -join ' ') failed ($code): $($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ Code = $code; Output = $output }
}

function Get-RegisteredWorktrees([string]$Root) {
    $raw = (Invoke-Git $Root @('worktree', 'list', '--porcelain')).Output
    return @($raw | Where-Object { $_ -like 'worktree *' } | ForEach-Object {
        [System.IO.Path]::GetFullPath($_.Substring(9))
    })
}

function Test-DisposableIgnoredPath([string]$RelativePath) {
    $path = $RelativePath.Replace('\', '/')
    $patterns = @(
        '(^|/)\.build/',
        '(^|/)\.release-stage/',
        '(^|/)\.temp/',
        '(^|/)upload/content/',
        '^tools/vmb-launcher/',
        '^\.vmbrc$',
        '(^|/)__pycache__/',
        '\.lua\.processed$',
        '^\.in_progress/(?!README\.md$)',
        '^\.ship_claims/.*\.claim$',
        '(^|/)_pc_b_logs/',
        '(^|/)\.pcb_latest\.log$',
        '(^|/)pcb-log\.log$'
    )
    foreach ($pattern in $patterns) {
        if ($path -match $pattern) { return $true }
    }
    return $false
}

function Test-IsPathInsideDirectory([string]$CandidatePath, [string]$DirectoryPath) {
    $candidate = [System.IO.Path]::GetFullPath($CandidatePath)
    $directory = [System.IO.Path]::GetFullPath($DirectoryPath).TrimEnd([char[]]@('\', '/'))
    $prefix = $directory + [System.IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

if ($SelfTest) {
    $failures = @()
    if (-not (Test-IsPathInsideDirectory 'C:\repo\wt\tools\worktrees\worktree.ps1' 'C:\repo\wt')) {
        $failures += 'script inside target was not detected'
    }
    if (Test-IsPathInsideDirectory 'C:\repo\wt-other\worktree.ps1' 'C:\repo\wt') {
        $failures += 'sibling path was misclassified as inside target'
    }
    if (Test-IsPathInsideDirectory 'C:\repo\wt' 'C:\repo\wt') {
        $failures += 'directory itself was misclassified as a child file'
    }
    if ($failures.Count -gt 0) {
        Write-Host '[worktree -SelfTest] FAILED' -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        exit 2
    }
    Write-Host '[worktree -SelfTest] OK - self-close and sibling path boundaries pass.' -ForegroundColor Green
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Action)) { throw 'Specify -Action Audit, Create, or Close.' }
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Join-Path $PSScriptRoot '..\..' }

$resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$budgetCheck = Join-Path $resolvedRoot 'qa\check_worktree_budget.ps1'
if (-not (Test-Path -LiteralPath $budgetCheck -PathType Leaf)) {
    throw "Missing worktree budget check: $budgetCheck"
}

if ($Action -eq 'Audit') {
    & $budgetCheck -RepoRoot $resolvedRoot -MaxAdditionalWorktrees $MaxAdditionalWorktrees -MaxAdditionalGiB $MaxAdditionalGiB
    exit $LASTEXITCODE
}

$registered = @(Get-RegisteredWorktrees $resolvedRoot)
if ($registered.Count -eq 0) { throw 'Git reported no primary worktree.' }
$primary = $registered[0]

if ($Action -eq 'Create') {
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -notmatch '^[a-z0-9][a-z0-9._-]{0,47}$') {
        throw 'Create requires -Name using 1-48 lowercase letters, digits, dots, underscores, or hyphens.'
    }
    & $budgetCheck -RepoRoot $resolvedRoot -MaxAdditionalWorktrees $MaxAdditionalWorktrees -MaxAdditionalGiB $MaxAdditionalGiB -Quiet
    if ($LASTEXITCODE -ge 2) {
        throw 'Refusing creation while the existing worktree fleet is already over budget.'
    }

    $additionalCount = [Math]::Max(0, $registered.Count - 1)
    if ($additionalCount -ge $MaxAdditionalWorktrees) {
        throw "Refusing worktree ${Name}: $additionalCount secondary worktrees already meet the limit $MaxAdditionalWorktrees."
    }

    if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "agent/$Name" }
    $branchProbe = Invoke-Git $resolvedRoot @('show-ref', '--verify', '--quiet', "refs/heads/$Branch") -AllowFailure
    if ($branchProbe.Code -eq 0) { throw "Local branch already exists: $Branch" }

    if ([string]::IsNullOrWhiteSpace($TargetPath)) {
        $TargetPath = Join-Path ([System.IO.Path]::GetTempPath()) "vt2-$Name"
    }
    $fullTarget = [System.IO.Path]::GetFullPath($TargetPath)
    if (Test-Path -LiteralPath $fullTarget) { throw "Target already exists: $fullTarget" }

    Invoke-Git $resolvedRoot @('worktree', 'add', '-b', $Branch, $fullTarget, $BaseRef) | Out-Null
    & $budgetCheck -RepoRoot $resolvedRoot -MaxAdditionalWorktrees $MaxAdditionalWorktrees -MaxAdditionalGiB $MaxAdditionalGiB -Quiet
    if ($LASTEXITCODE -ge 2) {
        Invoke-Git $resolvedRoot @('worktree', 'remove', '--', $fullTarget) | Out-Null
        Invoke-Git $resolvedRoot @('branch', '-D', $Branch) | Out-Null
        throw 'New worktree would exceed the disk budget; creation was rolled back.'
    }
    Write-Host "[worktree] Created $fullTarget on $Branch from $BaseRef." -ForegroundColor Green
    Write-Host "[worktree] Close in the same session: .\tools\worktrees\worktree.ps1 -Action Close -TargetPath `"$fullTarget`"" -ForegroundColor Cyan
    exit 0
}

if ([string]::IsNullOrWhiteSpace($TargetPath)) { throw 'Close requires -TargetPath.' }
$fullTarget = [System.IO.Path]::GetFullPath($TargetPath)
if ($fullTarget -eq $primary) { throw "Refusing to close the primary worktree: $primary" }
if ($registered -notcontains $fullTarget) { throw "Target is not a registered worktree: $fullTarget" }
if (-not (Test-Path -LiteralPath $fullTarget -PathType Container)) {
    throw "Registered worktree directory is missing; run git worktree prune after investigating: $fullTarget"
}
if (Test-IsPathInsideDirectory $PSCommandPath $fullTarget) {
    throw "Refusing self-close on Windows. Run this command from the primary checkout and pass -TargetPath `"$fullTarget`"."
}

$status = (Invoke-Git $fullTarget @('status', '--porcelain=v1', '--untracked-files=all')).Output
if ($status.Count -gt 0) {
    Write-Host '[worktree] Refusing close: commit or otherwise preserve these changes first.' -ForegroundColor Red
    $status | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 2
}

$ignored = (Invoke-Git $fullTarget @('ls-files', '--others', '--ignored', '--exclude-standard')).Output
$protectedIgnored = @($ignored | Where-Object { -not (Test-DisposableIgnoredPath $_) })
if ($protectedIgnored.Count -gt 0) {
    Write-Host '[worktree] Refusing close: ignored files outside the generated-file allowlist require manual review/archive.' -ForegroundColor Red
    $protectedIgnored | Select-Object -First 50 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    if ($protectedIgnored.Count -gt 50) { Write-Host "  ... and $($protectedIgnored.Count - 50) more" -ForegroundColor Red }
    exit 2
}

$branchName = (Invoke-Git $fullTarget @('branch', '--show-current')).Output | Select-Object -First 1
$removeArgs = @('worktree', 'remove')
if ($ignored.Count -gt 0) { $removeArgs += '--force' }
$removeArgs += @('--', $fullTarget)
Invoke-Git $resolvedRoot $removeArgs | Out-Null
Invoke-Git $resolvedRoot @('worktree', 'prune') | Out-Null

if (Test-Path -LiteralPath $fullTarget) {
    throw "Git unregistered the worktree but left a residual directory; inspect it manually: $fullTarget"
}

if ($DeleteMergedBranch -and -not [string]::IsNullOrWhiteSpace($branchName)) {
    $merged = Invoke-Git $resolvedRoot @('merge-base', '--is-ancestor', "refs/heads/$branchName", 'origin/master') -AllowFailure
    if ($merged.Code -ne 0) {
        throw "Worktree closed, but branch '$branchName' is not merged into origin/master; branch retained."
    }
    Invoke-Git $resolvedRoot @('branch', '-d', $branchName) | Out-Null
    Write-Host "[worktree] Closed $fullTarget and deleted merged branch $branchName." -ForegroundColor Green
} else {
    Write-Host "[worktree] Closed $fullTarget. Branch retained: $branchName" -ForegroundColor Green
}
