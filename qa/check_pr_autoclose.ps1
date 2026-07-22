# Blocks GitHub auto-closing issue references until the issue carries a trusted
# user-verification closure receipt. Issue #750 / regression evidence PR #969.
# ASCII-only for Windows PowerShell 5.1.

[CmdletBinding()]
param(
    [string]$Body,
    [string]$BodyPath,
    [string]$EventPath,
    [string]$Repository,
    [int]$PullRequestNumber,
    [switch]$PostMergeAudit,
    [switch]$Repair,
    [string[]]$TrustedVerifier = @('Ensrick', 'RainReligion'),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$script:ClosingPattern = [regex]::new(
    '(?i)(?<![A-Za-z0-9_])(?<keyword>close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved)[ \t]*(?::[ \t]*)?(?<reference>#(?<local>\d+)|(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)#(?<cross>\d+)|https://github\.com/(?<urlowner>[A-Za-z0-9_.-]+)/(?<urlrepo>[A-Za-z0-9_.-]+)/issues/(?<urlnum>\d+))',
    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
)

function Get-AutoCloseReferences {
    param([AllowNull()][string]$Text, [string]$DefaultRepository)
    $result = @()
    if ([string]::IsNullOrEmpty($Text)) { return $result }
    foreach ($match in $script:ClosingPattern.Matches($Text)) {
        $targetRepository = $DefaultRepository
        $number = 0
        if ($match.Groups['local'].Success) {
            $number = [int]$match.Groups['local'].Value
        } elseif ($match.Groups['cross'].Success) {
            $targetRepository = "$($match.Groups['owner'].Value)/$($match.Groups['repo'].Value)"
            $number = [int]$match.Groups['cross'].Value
        } else {
            $targetRepository = "$($match.Groups['urlowner'].Value)/$($match.Groups['urlrepo'].Value)"
            $number = [int]$match.Groups['urlnum'].Value
        }
        $result += [pscustomobject]@{
            Keyword = $match.Groups['keyword'].Value
            Reference = $match.Groups['reference'].Value
            Repository = $targetRepository
            Number = $number
            Text = $match.Value
        }
    }
    return @($result)
}

function Test-TrustedClosureReceipt {
    param([object[]]$Comments, [string[]]$TrustedLogins, [int]$PrNumber)
    foreach ($comment in @($Comments)) {
        $login = "$($comment.user.login)"
        $association = "$($comment.author_association)"
        $commentBody = "$($comment.body)"
        $trustedLogin = @($TrustedLogins | Where-Object { $_ -and $_.Equals($login, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        $trustedAssociation = $association -in @('OWNER', 'MEMBER', 'COLLABORATOR')
        $hasHeading = $commentBody -match '(?im)^## CLOSURE AUTHORIZATION\s*$'
        $hasVerification = $commentBody -match '(?im)^Verification:\s*user-confirmed\s*$'
        $boundToPr = $PrNumber -gt 0 -and $commentBody -match "(?im)^Authorized PR:\s*#$PrNumber\s*$"
        if ($trustedLogin -and $trustedAssociation -and $hasHeading -and $hasVerification -and $boundToPr) { return $true }
    }
    return $false
}

function Invoke-GhJson {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & gh @Arguments 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    if ($code -ne 0) { throw "gh failed (exit $code): gh $($Arguments -join ' ')" }
    $text = $output -join "`n"
    if (-not $text) { return @() }
    return @($text | ConvertFrom-Json)
}

function Get-IssueComments {
    param([string]$TargetRepository, [int]$IssueNumber)
    return @(Invoke-GhJson @('api', '--paginate', '--slurp', "repos/$TargetRepository/issues/$IssueNumber/comments?per_page=100"))
}

function Repair-PrematureClosure {
    param([string]$TargetRepository, [int]$IssueNumber, [int]$PrNumber)
    $issue = @(Invoke-GhJson @('api', "repos/$TargetRepository/issues/$IssueNumber"))[0]
    if ("$($issue.state)" -ne 'closed') { return $false }
    if ($TargetRepository -ne $Repository) { throw "cannot safely reopen cross-repository issue $TargetRepository#$IssueNumber" }
    $null = Invoke-GhJson @('api', '--method', 'PATCH', "repos/$TargetRepository/issues/$IssueNumber", '-f', 'state=open')
    $comment = "PR #$PrNumber used an auto-closing keyword without a prior trusted closure authorization. Issue #750's post-merge guard reopened this issue; restore the documented lifecycle before further work."
    $null = Invoke-GhJson @('api', '--method', 'POST', "repos/$TargetRepository/issues/$IssueNumber/comments", '-f', "body=$comment")
    return $true
}

function Invoke-SelfTest {
    $keywords = @('close', 'closes', 'closed', 'fix', 'fixes', 'fixed', 'resolve', 'resolves', 'resolved')
    $cases = @()
    foreach ($keyword in $keywords) {
        $cases += "$keyword #12"
        $cases += "$($keyword.ToUpperInvariant()): #12"
        $cases += "$([cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($keyword)) owner/repo#12"
    }
    foreach ($case in $cases) {
        $found = @(Get-AutoCloseReferences $case 'owner/repo')
        if ($found.Count -ne 1 -or $found[0].Number -ne 12) { throw "supported keyword/case was missed: $case" }
    }
    foreach ($case in @(
        'Refs #12', 'References #12', 'prefixfixes #12', 'fixed text without a reference',
        'fixes issue 12', 'close-ish #12', 'resolved owner repo #12', '#12 fixes the regression'
    )) {
        if (@(Get-AutoCloseReferences $case 'owner/repo').Count -ne 0) { throw "false positive: $case" }
    }
    $url = @(Get-AutoCloseReferences 'Resolves https://github.com/other/project/issues/42' 'owner/repo')
    if ($url.Count -ne 1 -or $url[0].Repository -ne 'other/project' -or $url[0].Number -ne 42) { throw 'full issue URL was not parsed' }
    $comments = @([pscustomobject]@{
        user = [pscustomobject]@{ login = 'Ensrick' }
        author_association = 'OWNER'
        body = "## CLOSURE AUTHORIZATION`nVerification: user-confirmed`nAuthorized PR: #123"
    })
    if (-not (Test-TrustedClosureReceipt $comments @('Ensrick') 123)) { throw 'trusted receipt was rejected' }
    if (Test-TrustedClosureReceipt $comments @('Ensrick') 124) { throw 'receipt was not bound to the pull request' }
    $comments[0].body = "## CLOSURE AUTHORIZATION`nVerification: build-passed"
    if (Test-TrustedClosureReceipt $comments @('Ensrick') 123) { throw 'non-user verification was accepted' }
    $comments[0].body = "## CLOSURE AUTHORIZATION`nVerification: user-confirmed`nAuthorized PR: #123"
    $comments[0].user.login = 'untrusted'
    if (Test-TrustedClosureReceipt $comments @('Ensrick') 123) { throw 'untrusted author was accepted' }
    Write-Host "[check_pr_autoclose -SelfTest] OK - $($cases.Count) keyword/case fixtures plus reference, receipt, and false-positive fixtures passed."
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$event = $null
if (-not $EventPath -and $env:GITHUB_EVENT_PATH) { $EventPath = $env:GITHUB_EVENT_PATH }
if ($EventPath) {
    if (-not (Test-Path -LiteralPath $EventPath)) {
        Write-Host "[check_pr_autoclose] ERROR - event path is unavailable: $EventPath" -ForegroundColor Red
        exit 2
    }
    $event = Get-Content -LiteralPath $EventPath -Raw | ConvertFrom-Json
    if ($env:GITHUB_ACTIONS -eq 'true' -and $env:GITHUB_EVENT_NAME -in @('pull_request', 'pull_request_target') -and -not $event.pull_request) {
        Write-Host '[check_pr_autoclose] ERROR - pull-request CI event is missing pull_request metadata.' -ForegroundColor Red
        exit 2
    }
    if (-not $Repository) { $Repository = "$($event.repository.full_name)" }
    if (-not $PullRequestNumber -and $event.pull_request.number) { $PullRequestNumber = [int]$event.pull_request.number }
    if (-not $PSBoundParameters.ContainsKey('Body') -and $event.pull_request) { $Body = "$($event.pull_request.body)" }
    if ($PostMergeAudit -and (-not $event.pull_request.merged)) {
        if (-not $Quiet) { Write-Host '[check_pr_autoclose] SKIP - closed pull request was not merged.' -ForegroundColor DarkGray }
        exit 0
    }
}
if ($BodyPath) {
    if (-not (Test-Path -LiteralPath $BodyPath)) {
        Write-Host "[check_pr_autoclose] ERROR - body path is unavailable: $BodyPath" -ForegroundColor Red
        exit 2
    }
    $Body = Get-Content -LiteralPath $BodyPath -Raw
}
if (-not $PSBoundParameters.ContainsKey('Body') -and -not $event) {
    if ($env:GITHUB_ACTIONS -eq 'true') {
        Write-Host '[check_pr_autoclose] ERROR - GitHub CI supplied no pull-request body context.' -ForegroundColor Red
        exit 2
    }
    if (-not $Quiet) { Write-Host '[check_pr_autoclose] SKIP - local run has no PR body; pass -Body or -BodyPath. Hosted PR CI and post-merge audit remain authoritative.' -ForegroundColor DarkGray }
    exit 0
}
if (-not $Repository) {
    Write-Host '[check_pr_autoclose] ERROR - repository identity is required to validate issue-local authorization.' -ForegroundColor Red
    exit 2
}

$references = @(Get-AutoCloseReferences $Body $Repository)
if ($references.Count -eq 0) {
    if (-not $Quiet) { Write-Host '[check_pr_autoclose] OK - no GitHub auto-closing issue references; use Refs #N.' -ForegroundColor Green }
    exit 0
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue) -or -not $env:GH_TOKEN) {
    Write-Host '[check_pr_autoclose] ERROR - auto-closing references found, but trusted issue receipts cannot be validated without gh and GH_TOKEN.' -ForegroundColor Red
    exit 2
}

$violations = @()
foreach ($reference in $references) {
    $comments = @(Get-IssueComments $reference.Repository $reference.Number)
    if (-not (Test-TrustedClosureReceipt $comments $TrustedVerifier $PullRequestNumber)) { $violations += $reference }
}

if ($violations.Count -eq 0) {
    if (-not $Quiet) { Write-Host "[check_pr_autoclose] OK - $($references.Count) auto-closing reference(s) carry trusted user-verification closure receipts." -ForegroundColor Green }
    exit 0
}

foreach ($violation in $violations) {
    Write-Host "[check_pr_autoclose] ERROR - '$($violation.Text)' targets $($violation.Repository)#$($violation.Number) without a trusted closure receipt. Use 'Refs #N'." -ForegroundColor Red
}
if ($PostMergeAudit -and $Repair) {
    foreach ($violation in $violations) {
        if (Repair-PrematureClosure $violation.Repository $violation.Number $PullRequestNumber) {
            Write-Host "[check_pr_autoclose] RECOVERED - reopened $($violation.Repository)#$($violation.Number)." -ForegroundColor Yellow
        }
    }
    exit 0
}
exit 2
