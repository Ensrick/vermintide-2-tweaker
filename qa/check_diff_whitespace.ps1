# check_diff_whitespace.ps1 - reject whitespace defects on every Git diff surface.
#
# Local pre-commit uses -Staged. Hosted pull-request QA passes an explicit
# merge-base range. The default run_all path checks both staged and unstaged
# work plus origin/$GITHUB_BASE_REF...HEAD when GitHub supplies a PR base.
#
# Exit codes: 0 = clean, 2 = whitespace defect, 99 = indeterminate/infrastructure.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Staged,
    [string]$Range,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Invoke-GitDiffCheck {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Surface,
        [Parameter(Mandatory)][string[]]$GitArguments
    )

    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $Root @GitArguments 2>&1)
        $code = $LASTEXITCODE
    }
    catch {
        return [pscustomobject]@{
            Surface = $Surface
            Code = 99
            Output = @("git invocation threw: $_")
        }
    }
    finally {
        $ErrorActionPreference = $priorPreference
    }

    if ($code -eq 0) {
        return [pscustomobject]@{ Surface = $Surface; Code = 0; Output = @() }
    }

    $lines = @($output | ForEach-Object { "$_" } | Where-Object { $_ -ne '' })
    if ($code -gt 2 -or $lines.Count -eq 0) {
        return [pscustomobject]@{
            Surface = $Surface
            Code = 99
            Output = if ($lines.Count -gt 0) {
                @("git diff --check failed with exit ${code}: $($lines -join ' | ')")
            }
            else {
                @("git diff --check failed with exit $code and no diagnostic")
            }
        }
    }
    return [pscustomobject]@{ Surface = $Surface; Code = 2; Output = $lines }
}

function Invoke-DiffWhitespaceAudit {
    param(
        [Parameter(Mandatory)][string]$Root,
        [switch]$OnlyStaged,
        [string]$ExplicitRange,
        [string]$PullRequestBase
    )

    if ($OnlyStaged -and -not [string]::IsNullOrWhiteSpace($ExplicitRange)) {
        return @([pscustomobject]@{
            Surface = 'arguments'
            Code = 99
            Output = @('-Staged and -Range are mutually exclusive')
        })
    }

    if ($OnlyStaged) {
        return @(Invoke-GitDiffCheck -Root $Root -Surface 'staged index' `
            -GitArguments @('diff', '--cached', '--check', '--'))
    }

    if (-not [string]::IsNullOrWhiteSpace($ExplicitRange)) {
        return @(Invoke-GitDiffCheck -Root $Root -Surface "committed range $ExplicitRange" `
            -GitArguments @('diff', '--check', $ExplicitRange, '--'))
    }

    $results = @(
        Invoke-GitDiffCheck -Root $Root -Surface 'unstaged worktree' `
            -GitArguments @('diff', '--check', '--')
        Invoke-GitDiffCheck -Root $Root -Surface 'staged index' `
            -GitArguments @('diff', '--cached', '--check', '--')
    )
    if (-not [string]::IsNullOrWhiteSpace($PullRequestBase)) {
        $prRange = "origin/$PullRequestBase...HEAD"
        $results += Invoke-GitDiffCheck -Root $Root -Surface "pull-request range $prRange" `
            -GitArguments @('diff', '--check', $prRange, '--')
    }
    return @($results)
}

function Invoke-GitFixture {
    param([string]$Root, [string[]]$Arguments)
    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& git -C $Root @Arguments 2>&1)
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $priorPreference
    }
    if ($code -ne 0) {
        throw "fixture git $($Arguments -join ' ') failed ($code): $($output -join [Environment]::NewLine)"
    }
}

function Test-HasCode {
    param([object[]]$Results, [int]$Code)
    return @($Results | Where-Object { $_.Code -eq $Code }).Count -gt 0
}

function Invoke-SelfTest {
    $failures = @()
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-diff-whitespace-{0}" -f ([guid]::NewGuid().ToString('N')))
    try {
        $productionRoot = Split-Path $PSScriptRoot -Parent
        $preCommitText = [System.IO.File]::ReadAllText((Join-Path $productionRoot 'tools/hooks/pre-commit.ps1'))
        $stagedCallAt = $preCommitText.IndexOf('check_diff_whitespace.ps1 -Staged', [System.StringComparison]::Ordinal)
        $extensionFilterAt = $preCommitText.IndexOf('$relevant = @($staged', [System.StringComparison]::Ordinal)
        if ($stagedCallAt -lt 0 -or $extensionFilterAt -lt 0 -or $stagedCallAt -gt $extensionFilterAt) {
            $failures += 'pre-commit does not wire the staged guard before extension filtering'
        }
        $workflowText = [System.IO.File]::ReadAllText((Join-Path $productionRoot '.github/workflows/qa.yml'))
        if ($workflowText -notmatch 'check_diff_whitespace\.ps1 -Range "origin/\$\{\{ github\.base_ref \}\}\.\.\.HEAD"') {
            $failures += 'hosted QA does not wire the explicit pull-request base-to-head range'
        }
        $runAllText = [System.IO.File]::ReadAllText((Join-Path $productionRoot 'qa/run_all.ps1'))
        if ($runAllText -notmatch 'Run-Check "check_diff_whitespace"') {
            $failures += 'run_all does not wire ordinary staged/unstaged coverage'
        }

        [void](New-Item -ItemType Directory -Path $fixture)
        Invoke-GitFixture -Root $fixture -Arguments @('init', '-q')
        Invoke-GitFixture -Root $fixture -Arguments @('config', 'user.email', 'qa@example.invalid')
        Invoke-GitFixture -Root $fixture -Arguments @('config', 'user.name', 'VT2 QA')

        $file = Join-Path $fixture 'fixture.txt'
        [System.IO.File]::WriteAllText($file, "clean`n", (New-Object System.Text.UTF8Encoding($false)))
        Invoke-GitFixture -Root $fixture -Arguments @('add', 'fixture.txt')
        Invoke-GitFixture -Root $fixture -Arguments @('commit', '-q', '-m', 'baseline')

        $clean = Invoke-DiffWhitespaceAudit -Root $fixture
        if (Test-HasCode -Results $clean -Code 2) { $failures += 'clean staged/unstaged surfaces failed' }

        [System.IO.File]::WriteAllText($file, "staged trailing space `n", (New-Object System.Text.UTF8Encoding($false)))
        Invoke-GitFixture -Root $fixture -Arguments @('add', 'fixture.txt')
        $stagedBad = Invoke-DiffWhitespaceAudit -Root $fixture -OnlyStaged
        if (-not (Test-HasCode -Results $stagedBad -Code 2)) { $failures += 'staged-only defect passed' }
        if ((@($stagedBad.Output) -join "`n") -notmatch 'fixture\.txt:1:') {
            $failures += 'staged defect omitted affected path/line'
        }

        Invoke-GitFixture -Root $fixture -Arguments @('commit', '-q', '--no-verify', '-m', 'planted defect')
        $committedBad = Invoke-DiffWhitespaceAudit -Root $fixture -ExplicitRange 'HEAD~1..HEAD'
        if (-not (Test-HasCode -Results $committedBad -Code 2)) { $failures += 'committed-only defect passed' }

        [System.IO.File]::WriteAllText($file, "repaired`n", (New-Object System.Text.UTF8Encoding($false)))
        Invoke-GitFixture -Root $fixture -Arguments @('add', 'fixture.txt')
        Invoke-GitFixture -Root $fixture -Arguments @('commit', '-q', '--no-verify', '-m', 'repair')
        $repaired = Invoke-DiffWhitespaceAudit -Root $fixture -ExplicitRange 'HEAD~1..HEAD'
        if (Test-HasCode -Results $repaired -Code 2) { $failures += 'repair-only committed range failed' }
        $netClean = Invoke-DiffWhitespaceAudit -Root $fixture -ExplicitRange 'HEAD~2..HEAD'
        if (Test-HasCode -Results $netClean -Code 2) { $failures += 'net repaired base-to-head range failed' }

        [System.IO.File]::WriteAllText($file, "unstaged trailing tab`t`n", (New-Object System.Text.UTF8Encoding($false)))
        $unstagedBad = Invoke-DiffWhitespaceAudit -Root $fixture
        if (-not (Test-HasCode -Results $unstagedBad -Code 2)) { $failures += 'ordinary unstaged defect passed' }

        $invalid = Invoke-DiffWhitespaceAudit -Root $fixture -ExplicitRange 'missing-ref...HEAD'
        if (-not (Test-HasCode -Results $invalid -Code 99)) { $failures += 'invalid range was not an infrastructure failure' }
    }
    catch {
        $failures += "fixture crashed: $_"
    }
    finally {
        if (Test-Path -LiteralPath $fixture) {
            Remove-Item -LiteralPath $fixture -Recurse -Force
        }
    }

    if ($failures.Count -gt 0) {
        Write-Host '[check_diff_whitespace] SELF-TEST FAILED' -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
        exit 2
    }
    Write-Host '[check_diff_whitespace] SELF-TEST OK - staged, committed, repaired, unstaged, and failure boundaries pass.' -ForegroundColor Green
    exit 0
}

if ($SelfTest) { Invoke-SelfTest }

if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
try {
    $resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    $inside = @(& git -C $resolvedRoot rev-parse --is-inside-work-tree 2>$null)
    if ($LASTEXITCODE -ne 0 -or "$inside".Trim() -ne 'true') { throw 'not a Git worktree' }
}
catch {
    Write-Host "[check_diff_whitespace] INFRASTRUCTURE FAILURE - cannot resolve Git worktree: $_" -ForegroundColor Red
    exit 99
}

$results = Invoke-DiffWhitespaceAudit -Root $resolvedRoot -OnlyStaged:$Staged `
    -ExplicitRange $Range -PullRequestBase $env:GITHUB_BASE_REF
$bad = @($results | Where-Object { $_.Code -ne 0 })
if ($bad.Count -gt 0) {
    $exitCode = if (@($bad | Where-Object { $_.Code -eq 99 }).Count -gt 0) { 99 } else { 2 }
    foreach ($result in $bad) {
        $kind = if ($result.Code -eq 99) { 'INFRASTRUCTURE FAILURE' } else { 'ERROR' }
        Write-Host "[check_diff_whitespace] $kind - $($result.Surface)" -ForegroundColor Red
        foreach ($line in @($result.Output)) { Write-Host "  $line" -ForegroundColor Red }
    }
    Write-Host '[check_diff_whitespace] Fix the listed whitespace; this check never edits files.' -ForegroundColor Yellow
    exit $exitCode
}

if (-not $Quiet) {
    $surfaces = @($results | ForEach-Object { $_.Surface }) -join ', '
    Write-Host "[check_diff_whitespace] OK - $surfaces clean." -ForegroundColor Green
}
exit 0
