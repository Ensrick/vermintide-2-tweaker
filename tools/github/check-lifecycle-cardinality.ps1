# Blocking tracker guard for the live-test queue doctrine.
# Read-only: paginated GraphQL reads, never tracker mutation. Labels are read
# for every open issue; complete comments (including isPinned) only for ready
# issues so pin cardinality is authoritative without scanning irrelevant prose.

[CmdletBinding()]
param(
    [string]$Repository = 'Ensrick/vermintide-2-tweaker',
    [string]$IssuesJsonPath,
    [string]$ReleaseManifestPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/verify/lifecycle_method_policy.ps1')

function Get-LifecycleViolations($Issues, [switch]$RequirePinnedCard, $Contract) {
    $violations = @()
    foreach ($issue in @($Issues)) {
        $decision = Get-VtOpenIssueLifecycleDecision -Issue $issue -RequirePinnedCard:$RequirePinnedCard -Contract $Contract
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

function Invoke-VtGhReadWithRetry {
    param([string[]]$Arguments)
    $raw = $null
    $exitCode = 0
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = & gh @Arguments 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldPreference
        }
        if ($exitCode -eq 0) { return $raw }
        $delaySeconds = Get-VtGraphQlRetryDelaySeconds $attempt
        if ($delaySeconds -le 0 -or -not (Test-VtRetryableGitHubTransportError $raw)) {
            throw "gh $($Arguments -join ' ') failed (exit $exitCode, attempt $attempt/4): $raw"
        }
        Write-Warning "Transient GitHub transport failure (attempt $attempt/4); retrying in $delaySeconds second(s)."
        Start-Sleep -Seconds $delaySeconds
    }
    throw "gh $($Arguments -join ' ') failed (exit $exitCode after 4 attempts): $raw"
}

function Get-VtLatestReleaseManifest {
    param([string]$Repository, [string]$Path)

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Release manifest fixture not found: $Path"
        }
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
    }

    $releaseRaw = Invoke-VtGhReadWithRetry @('api', "repos/$Repository/releases/latest")
    $release = $releaseRaw | ConvertFrom-Json
    $assets = @($release.assets | Where-Object { [string]$_.name -eq 'manifest.json' })
    if ($assets.Count -ne 1) {
        throw "Latest release '$($release.tag_name)' must contain exactly one manifest.json asset; found $($assets.Count)."
    }
    $manifestRaw = Invoke-VtGhReadWithRetry @(
        'api', [string]$assets[0].url,
        '-H', 'Accept: application/octet-stream'
    )
    $manifest = $manifestRaw | ConvertFrom-Json
    if ([string]$manifest.release_tag -ne [string]$release.tag_name) {
        throw "Latest release tag '$($release.tag_name)' does not match manifest release_tag '$($manifest.release_tag)'."
    }
    return $manifest
}

function Invoke-SelfTest {
    Invoke-VtDeployedSourceContractSelfTest
    $contract = [pscustomobject]@{
        Entries = @(
            [pscustomobject]@{ Directory='weapon_tweaker_dev'; ModId='wt_dev'; WorkshopId='3748824853'; Version='1.2.3-dev'; LoadTags=@('wt'); Commands=@('wt_probe'); PrintfReceipts=@('[wt:probe]') },
            [pscustomobject]@{ Directory='weapons_of_chaos'; ModId='WOC'; WorkshopId='3753880932'; Version='0.1.42-dev'; LoadTags=@('WOC'); Commands=@('woc_pose_reset'); PrintfReceipts=@('[WOC:633]') }
        )
        Commands = @('woc_pose_reset', 'gt_regression_test', 'scrub_official_loadouts')
        PrintfReceipts = @('[wt:probe]')
    }
    $validSolo = New-TestCard
    $validExactBanner = "## CURRENT LIVE TEST`n`n**Build/banner:** exact banner: [WOC] v0.1.42-dev loaded`n**Topology:** Solo`n`n1. Equip the Blightreaper in the Keep.`n`n**Expected:** The Blightreaper remains visible."
    $unlabeledExactBanner = "## CURRENT LIVE TEST`n`n**Build/banner:** [WOC] v0.1.42-dev loaded`n**Topology:** Solo`n`n1. Equip the Blightreaper in the Keep.`n`n**Expected:** The Blightreaper remains visible."
    $unversionedExactBanner = "## CURRENT LIVE TEST`n`n**Build/banner:** v0.1.42-dev, exact banner: [WOC] loaded`n**Topology:** Solo`n`n1. Equip the Blightreaper in the Keep.`n`n**Expected:** The Blightreaper remains visible."
    $validSlashCommand = New-TestCard -Steps '1. Run `/wt_probe` in chat and read the visible result.'
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
        ) },
        [pscustomobject]@{ number=22; title='undeployed build'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment ($validSolo -replace '1\.2\.3-dev', '1.2.4-dev'))) },
        [pscustomobject]@{ number=23; title='invented command'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment (New-TestCard -Steps '1. Run `/invented_probe` in chat.'))) },
        [pscustomobject]@{ number=24; title='contradictory receipt'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment ($validSolo + "`n**Workshop:** item ``3748824853``, manifest ``111111111`` `n**Current deployed floor:** item ``3748824853``, ManifestID ``222222222``"))) },
        [pscustomobject]@{ number=25; title='printf receipt'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment ((New-TestCard -Steps '1. Run `/wt_probe` in chat.') -replace 'The selected weapon behaves normally\.', 'The log contains `[wt:probe]` once.'))) },
        [pscustomobject]@{ number=26; title='non-printf receipt'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment ((New-TestCard -Steps '1. Run `/wt_probe` in chat.') -replace 'The selected weapon behaves normally\.', 'The log contains `[wt:missing]` once.'))) },
        [pscustomobject]@{ number=27; title='wrong workshop binding'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment ($validSolo -replace 'confirm `\[wt:LOAD\]`', 'confirm `[wt:LOAD]`; Workshop item `3753880932`'))) },
        [pscustomobject]@{ number=28; title='ordered multi-mod receipts'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment ((($validSolo -replace '(?m)(^\*\*Build/banner:\*\*.+)$', '$1; exact banner: [WOC] v0.1.42-dev loaded')) + "`n**Workshop receipts:** Weapon Tweaker item ``3748824853``, ManifestID ``999999999``; Weapons of Chaos item ``3753880932``, ManifestID ``111111111``"))) },
        [pscustomobject]@{ number=29; title='historical receipt note ignored'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment (((New-TestCard -Steps '1. Run `/wt_probe` in chat.') -replace 'The selected weapon behaves normally\.', 'The log contains `[wt:probe]` once.') + "`n`nNote: the retired tag was `[wt:not_real]`."))) },
        [pscustomobject]@{ number=30; title='unbound sibling version'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment ($validSolo -replace 'confirm `\[wt:LOAD\]`', 'confirm `[wt:LOAD]`; public mirror v1.2.2-beta'))) },
        [pscustomobject]@{ number=31; title='cross-build command'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment ((New-TestCard -Steps '1. Run `/woc_pose_reset` in chat.') -replace 'The selected weapon behaves normally\.', 'The log contains `[wt:probe]` once.'))) },
        [pscustomobject]@{ number=32; title='missing diagnostic receipt prefix'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment ((New-TestCard -Steps '1. Run `/wt_probe` in chat.') -replace 'The selected weapon behaves normally\.', 'Inspect the log for the diagnostic result.'))) },
        [pscustomobject]@{ number=33; title='cross-build receipt'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment ((New-TestCard -Steps '1. Run `/wt_probe` in chat.') -replace 'The selected weapon behaves normally\.', 'The log contains `[WOC:633]` once.'))) },
        [pscustomobject]@{ number=34; title='wrong separate Workshop binding'; labels=@(@{name='verify-fix'}); comments=@((New-TestComment ($validSolo + "`n**Workshop:** item ``3753880932``"))) },
        [pscustomobject]@{ number=35; title='continued expected receipt'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment (((New-TestCard -Steps '1. Run `/wt_probe` in chat.') -replace 'The selected weapon behaves normally\.', 'The visible probe completes.') + "`n`nThe log contains `[wt:probe]` once.`n`nDeployed floor: old `[wt:missing]`."))) },
        [pscustomobject]@{ number=36; title='negative log assertion'; labels=@(@{name='diagnostics-armed'}); comments=@((New-TestComment ((New-TestCard -Steps '1. Inspect the visible overlay.') -replace 'The selected weapon behaves normally\.', 'The overlay remains stable without log spam.'))) }
    )
    $violations = @(Get-LifecycleViolations -Issues $fixture -RequirePinnedCard -Contract $contract)
    $bad = @($violations.number | Sort-Object)
    if (($bad -join ',') -ne '4,5,6,7,9,10,11,12,13,15,16,18,19,21,22,23,24,26,27,30,31,32,33,34') { throw "unexpected violations: $($bad -join ',')" }
    foreach ($ok in 1,2,3,8,14,17,20,25,28,29,35,36) {
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
    if (@($violations | Where-Object number -eq 22)[0].errors -notcontains 'live-card-undeployed-build-wt-1.2.4-dev') { throw 'deployed build gate missing' }
    if (@($violations | Where-Object number -eq 23)[0].errors -notcontains 'live-card-unregistered-command-invented_probe') { throw 'registered command gate missing' }
    if (@($violations | Where-Object number -eq 24)[0].errors -notcontains 'live-card-contradictory-manifest-ids-3748824853') { throw 'manifest contradiction gate missing' }
    if (@($violations | Where-Object number -eq 26)[0].errors -notcontains 'live-card-requested-receipt-not-printf-wt:missing') { throw 'printf receipt gate missing' }
    if (@($violations | Where-Object number -eq 27)[0].errors -notcontains 'live-card-workshop-item-not-bound-to-build-3753880932') { throw 'Workshop/build binding gate missing' }
    if (@($violations | Where-Object number -eq 30)[0].errors -notcontains 'live-card-unbound-build-version-1.2.2-beta') { throw 'unbound build-version gate missing' }
    if (@($violations | Where-Object number -eq 31)[0].errors -notcontains 'live-card-unregistered-command-woc_pose_reset') { throw 'cross-build command gate missing' }
    if (@($violations | Where-Object number -eq 32)[0].errors -notcontains 'live-card-diagnostic-log-evidence-prefix-missing') { throw 'missing diagnostic receipt prefix gate missing' }
    if (@($violations | Where-Object number -eq 33)[0].errors -notcontains 'live-card-requested-receipt-not-printf-WOC:633') { throw 'cross-build receipt gate missing' }
    if (@($violations | Where-Object number -eq 34)[0].errors -notcontains 'live-card-workshop-item-not-bound-to-build-3753880932') { throw 'separate Workshop/build binding gate missing' }

    # IssuesJsonPath uses the same ConvertFrom-Json shape as this round-trip.
    # Keep isPinned in the serialized fixture so offline policy tests remain
    # capable of proving both true and false pin states.
    # Windows PowerShell 5.1 preserves a top-level JSON array as one nested
    # pipeline object, while PowerShell 7 enumerates it. Round-trip each issue
    # independently so the policy receives the same shape on both runtimes.
    $jsonFixture = @($fixture | ForEach-Object { $_ | ConvertTo-Json -Depth 8 | ConvertFrom-Json })
    $jsonBad = @((Get-LifecycleViolations -Issues $jsonFixture -RequirePinnedCard -Contract $contract).number | Sort-Object)
    if (($jsonBad -join ',') -ne ($bad -join ',')) { throw "JSON fixture drift: $($jsonBad -join ',')" }
    if (-not (Test-VtRetryableGitHubTransportError 'tls: failed to verify certificate: x509: certificate signed by unknown authority')) { throw 'TLS trust failure must be retryable' }
    if (-not (Test-VtRetryableGitHubTransportError 'HTTP 503: Service Unavailable')) { throw 'GitHub 503 must be retryable' }
    if (Test-VtRetryableGitHubTransportError 'HTTP 401: Bad credentials') { throw 'authentication failure must fail immediately' }
    if (Test-VtRetryableGitHubTransportError 'GraphQL: Field does not exist') { throw 'permanent GraphQL error must fail immediately' }
    if (((1..5 | ForEach-Object { Get-VtGraphQlRetryDelaySeconds $_ }) -join ',') -ne '2,5,10,0,0') { throw 'retry schedule must remain bounded to three retries' }
    $batchSpec = New-VtIssueCommentBatchQuerySpec -Owner 'owner' -Name 'repo' -Numbers @(579, 750) -AfterByNumber @{ '579'='cursor-579' }
    if ($batchSpec.Query -notmatch [regex]::Escape('issue0: issue(number: $number0)')) { throw 'comment batch must alias the first issue' }
    if ($batchSpec.Query -notmatch [regex]::Escape('issue1: issue(number: $number1)')) { throw 'comment batch must alias the second issue' }
    if ([int]$batchSpec.Variables.number0 -ne 579 -or [string]$batchSpec.Variables.after0 -ne 'cursor-579') { throw 'comment batch must retain the first issue cursor' }
    if ([int]$batchSpec.Variables.number1 -ne 750 -or $null -ne $batchSpec.Variables.after1) { throw 'comment batch must leave a first-page cursor null' }
    if ([int]$batchSpec.AliasToNumber.issue0 -ne 579 -or [int]$batchSpec.AliasToNumber.issue1 -ne 750) { throw 'comment batch aliases must map back to exact issues' }
    $batchCapRejected = $false
    try { New-VtIssueCommentBatchQuerySpec -Owner 'owner' -Name 'repo' -Numbers @(1..21) | Out-Null } catch { $batchCapRejected = $true }
    if (-not $batchCapRejected) { throw 'comment batch must reject more than 20 issues' }
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
        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = & gh @arguments 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $oldPreference
        }
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

function New-VtIssueCommentBatchQuerySpec {
    param(
        [string]$Owner,
        [string]$Name,
        [int[]]$Numbers,
        [hashtable]$AfterByNumber = @{}
    )

    $ordered = @($Numbers | Select-Object -Unique)
    if ($ordered.Count -eq 0) { throw 'Comment batch requires at least one issue number.' }
    if ($ordered.Count -gt 20) { throw "Comment batch is capped at 20 issues; got $($ordered.Count)." }

    $declarations = @('$owner: String!', '$name: String!')
    $fields = @()
    $variables = @{ owner=$Owner; name=$Name }
    $aliasToNumber = @{}
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $number = [int]$ordered[$i]
        if ($number -le 0) { throw "Invalid issue number in comment batch: $number." }
        $numberVar = "number$i"
        $afterVar = "after$i"
        $alias = "issue$i"
        $declarations += ('$' + $numberVar + ': Int!')
        $declarations += ('$' + $afterVar + ': String')
        $fields += @"
    ${alias}: issue(number: `$$numberVar) {
      number
      comments(first: 100, after: `$$afterVar) {
        nodes { body createdAt isPinned }
        pageInfo { hasNextPage endCursor }
      }
    }
"@
        $variables[$numberVar] = $number
        $key = [string]$number
        $variables[$afterVar] = if ($AfterByNumber.ContainsKey($key)) { [string]$AfterByNumber[$key] } else { $null }
        $aliasToNumber[$alias] = $number
    }

    $query = "query($($declarations -join ', ')) {`n  repository(owner: `$owner, name: `$name) {`n$($fields -join '')  }`n}"
    return [pscustomobject][ordered]@{
        Query = $query
        Variables = $variables
        AliasToNumber = $aliasToNumber
    }
}

function Get-VtGitHubIssueCommentsBatch {
    param([string]$Owner, [string]$Name, [int[]]$Numbers)

    $ordered = @($Numbers | Select-Object -Unique)
    $commentsByNumber = @{}
    foreach ($number in $ordered) { $commentsByNumber[[string]$number] = @() }

    for ($offset = 0; $offset -lt $ordered.Count; $offset += 20) {
        $last = [Math]::Min($offset + 19, $ordered.Count - 1)
        $pending = @($ordered[$offset..$last])
        $afterByNumber = @{}
        while ($pending.Count -gt 0) {
            $spec = New-VtIssueCommentBatchQuerySpec -Owner $Owner -Name $Name -Numbers $pending -AfterByNumber $afterByNumber
            $data = Invoke-VtGraphQl -Query $spec.Query -Variables $spec.Variables
            if (-not $data.repository) { throw "GitHub repository '$Owner/$Name' was not found." }

            $next = @()
            foreach ($alias in @($spec.AliasToNumber.Keys)) {
                $number = [int]$spec.AliasToNumber[$alias]
                $issue = $data.repository.$alias
                if (-not $issue -or [int]$issue.number -ne $number) {
                    throw "GitHub issue #$number was not found or was returned under the wrong batch alias."
                }
                $connection = $issue.comments
                $key = [string]$number
                $commentsByNumber[$key] = @($commentsByNumber[$key]) + @($connection.nodes)
                if ($connection.pageInfo.hasNextPage) {
                    $cursor = [string]$connection.pageInfo.endCursor
                    if ([string]::IsNullOrWhiteSpace($cursor)) {
                        throw "GitHub issue #$number reported another comments page without an end cursor."
                    }
                    $afterByNumber[$key] = $cursor
                    $next += $number
                }
                else {
                    [void]$afterByNumber.Remove($key)
                }
            }
            $pending = @($next)
        }
    }
    return $commentsByNumber
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
    $issueNodes = @()
    $after = $null
    do {
        $data = Invoke-VtGraphQl -Query $query -Variables @{ owner=$owner; name=$name; after=$after }
        if (-not $data.repository) { throw "GitHub repository '$Repository' was not found." }
        $connection = $data.repository.issues
        $issueNodes += @($connection.nodes)
        $after = if ($connection.pageInfo.hasNextPage) { [string]$connection.pageInfo.endCursor } else { $null }
    } while ($after)

    $readyNumbers = @()
    foreach ($node in $issueNodes) {
        if ([int]$node.labels.totalCount -gt 100) { throw "Issue #$($node.number) has more than 100 labels; refusing a partial lifecycle read." }
        $labelNames = @($node.labels.nodes | ForEach-Object { [string]$_.name })
        if (@($labelNames | Where-Object { $script:VtReadyLifecycleLabels -contains $_ }).Count -gt 0) {
            $readyNumbers += [int]$node.number
        }
    }
    $commentsByNumber = Get-VtGitHubIssueCommentsBatch -Owner $owner -Name $name -Numbers $readyNumbers

    $issues = @()
    foreach ($node in $issueNodes) {
        $number = [int]$node.number
        $key = [string]$number
        $issues += [pscustomobject]@{
            number = $number
            title = [string]$node.title
            labels = @($node.labels.nodes)
            comments = if ($commentsByNumber.ContainsKey($key)) { @($commentsByNumber[$key]) } else { @() }
        }
    }
    return @($issues)
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }

# Per-phase wall-clock evidence against the workflow's five-minute ceiling.
# The 2026-08-13/15 scheduled cancellations (#750) were unattributable because
# the guard printed nothing between the offline fixtures and the final verdict;
# a cancelled run now shows exactly which phase consumed the budget.
$totalTimer = [System.Diagnostics.Stopwatch]::StartNew()
$phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()

if ($IssuesJsonPath) {
    $json = Get-Content -LiteralPath $IssuesJsonPath -Raw
}
else {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is required.' }
    $issues = @(Get-VtGitHubOpenIssues -Repository $Repository)
}

if ($IssuesJsonPath) { $issues = @($json | ConvertFrom-Json) }
$openIssueSeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds)
$phaseTimer.Restart()
$releaseManifest = Get-VtLatestReleaseManifest -Repository $Repository -Path $ReleaseManifestPath
$manifestSeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds)
$phaseTimer.Restart()
$contract = Get-VtDeployedSourceContract -RepoRoot $repoRoot -ReleaseManifest $releaseManifest
$contractSeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds)
$phaseTimer.Restart()
$violations = @(Get-LifecycleViolations -Issues $issues -RequirePinnedCard -Contract $contract)
$policySeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds)
Write-Host "[check-lifecycle-cardinality] timing: open-issues=${openIssueSeconds}s release-manifest=${manifestSeconds}s deployed-contract=${contractSeconds}s card-policy=${policySeconds}s total=$([int][math]::Round($totalTimer.Elapsed.TotalSeconds))s"
if ($violations.Count -eq 0) {
    Write-Host "[check-lifecycle-cardinality] OK: all $($issues.Count) open issues satisfy lifecycle and live-test queue doctrine against deployed release $($contract.ReleaseTag)."
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
