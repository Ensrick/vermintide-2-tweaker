# Blocking tracker guard for the live-test queue doctrine.
# Read-only: paginated GraphQL reads, never tracker mutation. Labels are read
# for every open issue; complete comments (including isPinned) only for ready
# issues so pin cardinality is authoritative without scanning irrelevant prose.

[CmdletBinding()]
param(
    [string]$Repository = 'Ensrick/vermintide-2-tweaker',
    [string]$IssuesJsonPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/verify/lifecycle_method_policy.ps1')

function Get-LifecycleViolations($Issues, [switch]$RequirePinnedCard) {
    $violations = @()
    foreach ($issue in @($Issues)) {
        $decision = Get-VtOpenIssueLifecycleDecision -Issue $issue -RequirePinnedCard:$RequirePinnedCard
        if (-not $decision.Valid) {
            $violations += [PSCustomObject][ordered]@{
                number = [int]$issue.number
                title = [string]$issue.title
                labels = @($decision.Labels)
                errors = @($decision.Errors)
            }
        }
    }
    return @($violations)
}

function New-TestCard([string]$Topology = 'Solo', [string]$Steps = '1. Equip Kruber''s Mace in the Keep.', [string]$SoloStatus = '') {
    $soloLine = if ($SoloStatus) { "`n**Solo status:** $SoloStatus" } else { '' }
    return "## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.3-dev, confirm ``[wt:LOAD]```n**Topology:** $Topology$soloLine`n`n$Steps`n`n**Expected:** The selected weapon behaves normally."
}

function New-TestComment([string]$Body, [bool]$IsPinned = $true, [string]$CreatedAt = '2026-07-21T00:00:00Z') {
    return [pscustomobject]@{ body=$Body; createdAt=$CreatedAt; isPinned=$IsPinned }
}

function Test-VtRetryableGitHubTransportError([string]$Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) { return $false }
    return [bool]($Message -match '(?is)(tls:|x509:|connection (?:reset|refused)|unexpected EOF|i/o timeout|context deadline exceeded|HTTP\s+(?:408|429|5\d\d)|status code\s+(?:408|429|5\d\d)|(?:502|503|504)\s+(?:Bad Gateway|Service Unavailable|Gateway Timeout))')
}

function Get-VtGraphQlRetryDelaySeconds([int]$FailedAttempt) {
    switch ($FailedAttempt) {
        1 { return 2 }
        2 { return 5 }
        3 { return 10 }
        default { return 0 }
    }
}

function Invoke-SelfTest {
    $validSolo = New-TestCard
    $validExactBanner = "## CURRENT LIVE TEST`n`n**Build/banner:** exact banner: [WOC] v0.1.42-dev loaded`n**Topology:** Solo`n`n1. Equip the Blightreaper in the Keep.`n`n**Expected:** The Blightreaper remains visible."
    $unlabeledExactBanner = "## CURRENT LIVE TEST`n`n**Build/banner:** [WOC] v0.1.42-dev loaded`n**Topology:** Solo`n`n1. Equip the Blightreaper in the Keep.`n`n**Expected:** The Blightreaper remains visible."
    $unversionedExactBanner = "## CURRENT LIVE TEST`n`n**Build/banner:** v0.1.42-dev, exact banner: [WOC] loaded`n**Topology:** Solo`n`n1. Equip the Blightreaper in the Keep.`n`n**Expected:** The Blightreaper remains visible."
    $validSlashCommand = New-TestCard -Steps "1. Run ``/woc_pose_reset`` in chat.`n2. Run ``/gt_regression_test`` when it finishes.`n3. Run ``/scrub_official_loadouts`` and read the result."
    $validCoop = New-TestCard -Topology 'Co-op (host and one client)' -SoloStatus 'Passed; remote rendering remains.' -Steps "1. Host equips Kruber's Mace.`n2. The joining player observes it."
    $fixture = @(
        [pscustomobject]@{ number=1; title='waiting'; labels=@(@{name='not-started'}); comments=@() },
        [pscustomobject]@{ number=2; title='solo ready'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment $validSolo)) },
        [pscustomobject]@{ number=3; title='coop ready'; labels=@(@{name='diagnostics-armed'},@{name='coop-required'}); comments=@((New-TestComment $validCoop)) },
        [pscustomobject]@{ number=4; title='bare'; labels=@(); comments=@() },
        [pscustomobject]@{ number=5; title='old coop'; labels=@(@{name='verify-fix-coop'}); comments=@((New-TestComment $validCoop)) },
        [pscustomobject]@{ number=6; title='open fixed'; labels=@(@{name='not-started'},@{name='Fixed'}); comments=@() },
        [pscustomobject]@{ number=7; title='blocked ready'; labels=@(@{name='blocked'},@{name='verify-fix'}); comments=@((New-TestComment $validSolo)) },
        [pscustomobject]@{ number=8; title='blocked waiting'; labels=@(@{name='blocked'},@{name='not-started'}); comments=@() },
        [pscustomobject]@{ number=9; title='coop skipped solo'; labels=@(@{name='verify-fix'},@{name='coop-required'}); comments=@((New-TestComment (New-TestCard -Topology 'Co-op'))) },
        [pscustomobject]@{ number=10; title='internal key'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment (New-TestCard -Steps '1. Equip em_mace.'))) },
        [pscustomobject]@{ number=11; title='stale older valid'; labels=@(@{name='verify-fix'}); comments=@(
            (New-TestComment $validSolo $false '2026-07-21T00:00:00Z'),
            (New-TestComment "## CURRENT LIVE TEST`n**Topology:** Solo`n1. Equip Kruber's Mace.`n**Expected:** Works." $true '2026-07-22T00:00:00Z')
        ) },
        [pscustomobject]@{ number=12; title='coop nonready'; labels=@(@{name='not-started'},@{name='coop-required'}); comments=@() },
        [pscustomobject]@{ number=13; title='timestamp newest wins'; labels=@(@{name='verify-fix'}); comments=@(
            (New-TestComment "## CURRENT LIVE TEST`n**Topology:** Solo`n1. Equip Kruber's Mace.`n**Expected:** Works." $true '2026-07-22T00:00:00Z'),
            (New-TestComment $validSolo $false '2026-07-21T00:00:00Z')
        ) },
        [pscustomobject]@{ number=14; title='versioned exact banner'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment $validExactBanner)) },
        [pscustomobject]@{ number=15; title='unlabeled exact banner'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment $unlabeledExactBanner)) },
        [pscustomobject]@{ number=16; title='unversioned exact banner'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment $unversionedExactBanner)) },
        [pscustomobject]@{ number=17; title='backticked slash command'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment $validSlashCommand)) },
        [pscustomobject]@{ number=18; title='newest exact card unpinned'; labels=@(@{name='verify-fix'}); comments=@(
            (New-TestComment $validSolo $true '2026-07-21T00:00:00Z'),
            (New-TestComment $validSolo $false '2026-07-22T00:00:00Z')
        ) },
        [pscustomobject]@{ number=19; title='two pinned exact cards'; labels=@(@{name='verify-fix'}); comments=@(
            (New-TestComment $validSolo $true '2026-07-21T00:00:00Z'),
            (New-TestComment $validSolo $true '2026-07-22T00:00:00Z')
        ) },
        [pscustomobject]@{ number=20; title='only newest exact card pinned'; labels=@(@{name='verify-fix'}); comments=@(
            (New-TestComment $validSolo $false '2026-07-21T00:00:00Z'),
            (New-TestComment $validSolo $true '2026-07-22T00:00:00Z')
        ) },
        [pscustomobject]@{ number=21; title='pin state unavailable'; labels=@(@{name='verify-fix'}); comments=@(
            [pscustomobject]@{body=$validSolo; createdAt='2026-07-22T00:00:00Z'}
        ) }
    )
    $violations = @(Get-LifecycleViolations -Issues $fixture -RequirePinnedCard)
    $bad = @($violations.number | Sort-Object)
    if (($bad -join ',') -ne '4,5,6,7,9,10,11,12,13,15,16,18,19,21') { throw "unexpected violations: $($bad -join ',')" }
    foreach ($ok in 1,2,3,8,14,17,20) {
        if ($bad -contains $ok) { throw "valid fixture #$ok rejected" }
    }
    $coop = @($violations | Where-Object number -eq 9)[0]
    if ($coop.errors -notcontains 'live-card-coop-before-solo-passed-or-exhausted') { throw 'solo-first co-op gate missing' }
    $internal = @($violations | Where-Object number -eq 10)[0]
    if ($internal.errors -notcontains 'live-card-internal-key-in-player-steps') { throw 'internal key gate missing' }
    $unpinned = @($violations | Where-Object number -eq 18)[0]
    if ($unpinned.errors -notcontains 'live-card-current-live-test-card-not-pinned') { throw 'selected-card pin gate missing' }
    $doublePinned = @($violations | Where-Object number -eq 19)[0]
    if ($doublePinned.errors -notcontains 'live-card-pinned-current-live-test-card-count-2') { throw 'one-pinned-card cardinality gate missing' }
    $unknownPin = @($violations | Where-Object number -eq 21)[0]
    if ($unknownPin.errors -notcontains 'live-card-current-live-test-card-pin-state-unavailable') { throw 'unknown pin-state gate missing' }

    # IssuesJsonPath uses the same ConvertFrom-Json shape as this round-trip.
    # Keep isPinned in the serialized fixture so offline policy tests remain
    # capable of proving both true and false pin states.
    # Windows PowerShell 5.1 preserves a top-level JSON array as one nested
    # pipeline object, while PowerShell 7 enumerates it. Round-trip each issue
    # independently so the policy receives the same shape on both runtimes.
    $jsonFixture = @($fixture | ForEach-Object { $_ | ConvertTo-Json -Depth 8 | ConvertFrom-Json })
    $jsonBad = @((Get-LifecycleViolations -Issues $jsonFixture -RequirePinnedCard).number | Sort-Object)
    if (($jsonBad -join ',') -ne ($bad -join ',')) { throw "JSON fixture drift: $($jsonBad -join ',')" }
    if (-not (Test-VtRetryableGitHubTransportError 'tls: failed to verify certificate: x509: certificate signed by unknown authority')) { throw 'TLS trust failure must be retryable' }
    if (-not (Test-VtRetryableGitHubTransportError 'HTTP 503: Service Unavailable')) { throw 'GitHub 503 must be retryable' }
    if (Test-VtRetryableGitHubTransportError 'HTTP 401: Bad credentials') { throw 'authentication failure must fail immediately' }
    if (Test-VtRetryableGitHubTransportError 'GraphQL: Field does not exist') { throw 'permanent GraphQL error must fail immediately' }
    if (((1..5 | ForEach-Object { Get-VtGraphQlRetryDelaySeconds $_ }) -join ',') -ne '2,5,10,0,0') { throw 'retry schedule must remain bounded to three retries' }
    Write-Host '[check-lifecycle-cardinality -SelfTest] OK'
}

function Invoke-VtGraphQl {
    param([string]$Query, [hashtable]$Variables)

    $arguments = @('api', 'graphql', '-f', "query=$Query")
    foreach ($name in @($Variables.Keys | Sort-Object)) {
        $value = $Variables[$name]
        if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { continue }
        $flag = if ($value -is [int] -or $value -is [long] -or $value -is [bool]) { '-F' } else { '-f' }
        $arguments += @($flag, "$name=$value")
    }

    $raw = $null
    $exitCode = 0
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $raw = & gh @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) { break }

        $delaySeconds = Get-VtGraphQlRetryDelaySeconds $attempt
        if ($delaySeconds -le 0 -or -not (Test-VtRetryableGitHubTransportError $raw)) {
            throw "gh api graphql failed (exit $exitCode, attempt $attempt/4): $raw"
        }
        Write-Warning "Transient GitHub GraphQL transport failure (attempt $attempt/4); retrying in $delaySeconds second(s)."
        Start-Sleep -Seconds $delaySeconds
    }
    if ($exitCode -ne 0) { throw "gh api graphql failed (exit $exitCode after 4 attempts): $raw" }
    $payload = $raw | ConvertFrom-Json
    if ($payload.errors) {
        $messages = @($payload.errors | ForEach-Object { $_.message }) -join '; '
        throw "GitHub GraphQL returned errors: $messages"
    }
    return $payload.data
}

function Get-VtGitHubIssueComments {
    param([string]$Owner, [string]$Name, [int]$Number)

    $query = @'
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      comments(first: 100, after: $after) {
        nodes { body createdAt isPinned }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
'@
    $comments = @()
    $after = $null
    do {
        $data = Invoke-VtGraphQl -Query $query -Variables @{ owner=$Owner; name=$Name; number=$Number; after=$after }
        if (-not $data.repository.issue) { throw "GitHub issue #$Number was not found." }
        $connection = $data.repository.issue.comments
        $comments += @($connection.nodes)
        $after = if ($connection.pageInfo.hasNextPage) { [string]$connection.pageInfo.endCursor } else { $null }
    } while ($after)
    return @($comments)
}

function Get-VtGitHubOpenIssues {
    param([string]$Repository)

    if ($Repository -notmatch '^([^/]+)/([^/]+)$') { throw "Repository must be OWNER/NAME, got '$Repository'." }
    $owner = $Matches[1]
    $name = $Matches[2]
    $query = @'
query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $after, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes {
        number
        title
        labels(first: 100) { totalCount nodes { name } }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}
'@
    $issues = @()
    $after = $null
    do {
        $data = Invoke-VtGraphQl -Query $query -Variables @{ owner=$owner; name=$name; after=$after }
        if (-not $data.repository) { throw "GitHub repository '$Repository' was not found." }
        $connection = $data.repository.issues
        foreach ($node in @($connection.nodes)) {
            if ([int]$node.labels.totalCount -gt 100) { throw "Issue #$($node.number) has more than 100 labels; refusing a partial lifecycle read." }
            $labelNodes = @($node.labels.nodes)
            $labelNames = @($labelNodes | ForEach-Object { [string]$_.name })
            $comments = @()
            if (@($labelNames | Where-Object { $script:VtReadyLifecycleLabels -contains $_ }).Count -gt 0) {
                $comments = @(Get-VtGitHubIssueComments -Owner $owner -Name $name -Number ([int]$node.number))
            }
            $issues += [pscustomobject]@{
                number = [int]$node.number
                title = [string]$node.title
                labels = $labelNodes
                comments = $comments
            }
        }
        $after = if ($connection.pageInfo.hasNextPage) { [string]$connection.pageInfo.endCursor } else { $null }
    } while ($after)
    return @($issues)
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }

if ($IssuesJsonPath) {
    $json = Get-Content -LiteralPath $IssuesJsonPath -Raw
}
else {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is required.' }
    $issues = @(Get-VtGitHubOpenIssues -Repository $Repository)
}

if ($IssuesJsonPath) { $issues = @($json | ConvertFrom-Json) }
$violations = @(Get-LifecycleViolations -Issues $issues -RequirePinnedCard)
if ($violations.Count -eq 0) {
    Write-Host "[check-lifecycle-cardinality] OK: all $($issues.Count) open issues satisfy lifecycle and live-test queue doctrine."
    exit 0
}

Write-Host "[check-lifecycle-cardinality] FAIL: $($violations.Count) open issue(s) violate tracker doctrine:"
foreach ($violation in $violations) {
    $message = "issue #$($violation.number) [$($violation.labels -join ', ')] - $($violation.errors -join ', ') - '$($violation.title)'"
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::error::$message" }
    Write-Host "  - $message"
}
Write-Host '[check-lifecycle-cardinality] Required: exactly one of not-started/diagnostics-armed/verify-fix. Ready states require exactly one pinned exact CURRENT LIVE TEST card, and it must be the newest exact card. Fixed and verify-fix-coop are invalid while open.'
exit 1
