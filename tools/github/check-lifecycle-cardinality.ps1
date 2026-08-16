# Blocking tracker guard for the live-test queue doctrine.
# Read-only: paginated GraphQL reads, never tracker mutation. Labels are read
# for every open issue; complete comments (including isPinned) only for ready
# issues so pin cardinality is authoritative without scanning irrelevant prose.

[CmdletBinding()]
param(
    [string]$Repository = 'Ensrick/vermintide-2-tweaker',
    [string]$IssuesJsonPath,
    [string]$DeploymentManifestPath,
    [switch]$EnforceAuthority,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/verify/lifecycle_method_policy.ps1')

# One decision pass serves both the blocking verdict and the report-only
# authority findings. Evaluating each issue twice doubled the card-policy
# phase for no new information, which the #750 timing evidence would then
# have reported as an inflated policy budget.
function Get-LifecycleDecisionReport($Issues, [switch]$RequirePinnedCard, $Authority, [switch]$EnforceAuthority) {
    $violations = @()
    $findings = @()
    foreach ($issue in @($Issues)) {
        $decision = Get-VtOpenIssueLifecycleDecision -Issue $issue -RequirePinnedCard:$RequirePinnedCard -Authority $Authority -EnforceAuthority:$EnforceAuthority
        if (-not $decision.Valid) {
            $violations += [PSCustomObject][ordered]@{
                number = [int]$issue.number
                title = [string]$issue.title
                labels = @($decision.Labels)
                errors = @($decision.Errors)
            }
        }
        if ($decision.Ready -and @($decision.Advisories).Count -gt 0) {
            $findings += [pscustomobject][ordered]@{
                number = [int]$issue.number
                title = [string]$issue.title
                advisories = @($decision.Advisories)
            }
        }
    }
    return [pscustomobject]@{ Violations=@($violations); AuthorityFindings=@($findings) }
}

function Get-LifecycleViolations($Issues, [switch]$RequirePinnedCard, $Authority, [switch]$EnforceAuthority) {
    $report = Get-LifecycleDecisionReport -Issues $Issues -RequirePinnedCard:$RequirePinnedCard -Authority $Authority -EnforceAuthority:$EnforceAuthority
    return @($report.Violations)
}

function Get-LifecycleAuthorityFindings($Issues, [switch]$RequirePinnedCard, $Authority, [switch]$EnforceAuthority) {
    $report = Get-LifecycleDecisionReport -Issues $Issues -RequirePinnedCard:$RequirePinnedCard -Authority $Authority -EnforceAuthority:$EnforceAuthority
    return @($report.AuthorityFindings)
}

function Get-VtLifecycleAuthorityContext {
    param(
        [string]$RepoRoot,
        [string]$Repository,
        [string]$DeploymentManifestPath,
        [switch]$EnforceAuthority
    )
    # The deployment-manifest fetch and the deployed-source index are the two
    # network/git phases of authority acquisition, so they are measured here
    # and surfaced to the caller's #750 timing line rather than re-fetched
    # outside this function just to be timed.
    $manifestSeconds = $null
    $sourceSeconds = $null
    $phaseTimer = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $deploymentManifest = Get-VtCardDeploymentManifest -Repository $Repository -ManifestJsonPath $DeploymentManifestPath
        $manifestSeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds)
        $phaseTimer.Restart()
        $sourceAuthority = Get-VtCardSourceAuthority -RepoRoot $RepoRoot -DeploymentManifest $deploymentManifest
        $sourceSeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds)
        return [pscustomobject]@{
            Authority = New-VtLiveTestCardAuthority -Source $sourceAuthority -DeploymentManifest $deploymentManifest
            Error = $null
            ManifestSeconds = [int]$manifestSeconds
            SourceSeconds = [int]$sourceSeconds
        }
    }
    catch {
        if ($EnforceAuthority) { throw }
        if ($null -eq $manifestSeconds) { $manifestSeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds) }
        elseif ($null -eq $sourceSeconds) { $sourceSeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds) }
        return [pscustomobject]@{
            Authority = $null
            Error = $_.Exception.Message
            ManifestSeconds = [int]$manifestSeconds
            SourceSeconds = [int]$sourceSeconds
        }
    }
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
    Invoke-VtDeployedSourceContractSelfTest
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

    # Planted authoritative-card fixtures. These are deliberately separate
    # from the structural lifecycle fixtures above so the old parser tests do
    # not silently become coupled to a made-up release.
    $authority = [pscustomobject]@{
        Records = @(
            [pscustomobject]@{
                ModId='wt_dev'; Version='1.2.3-dev'; WorkshopId='1111111111'
                LoadRoutes=@([pscustomobject]@{Marker='[wt:LOAD]'})
                ExactBannerRoutes=@([pscustomobject]@{Tag='[wt]'})
                CommandRoutes=@(
                    [pscustomobject]@{Command='/gt_regression_test'},
                    [pscustomobject]@{Command='/other_probe'}
                )
                ReceiptRoutes=@(
                    [pscustomobject]@{Marker='[gt:probe]';Signature='[gt:probe] result=%s';Bound=$true;ActionCommands=@('/gt_regression_test')},
                    [pscustomobject]@{Marker='[gt:probe]';Signature='[gt:probe] other=%s';Bound=$false;ActionCommands=@('/gt_regression_test')},
                    [pscustomobject]@{Marker='[gt:unbounded]';Signature='[gt:unbounded] tick=%d';Bound=$false},
                    [pscustomobject]@{Marker='[gt:gap]';Signature='[gt:gap] RECEIVER-GAP skin=%s';Bound=$true},
                    [pscustomobject]@{Marker='[gt:gap]';Signature='[gt:gap] RECEIVER-GAP +%d more';Bound=$true},
                    [pscustomobject]@{Marker='[gt:vague]';Signature='[gt:vague] event started id=%s';Bound=$true},
                    [pscustomobject]@{Marker='[gt:vague]';Signature='[gt:vague] event stopped id=%s';Bound=$true},
                    [pscustomobject]@{Marker='[gt:single]';Signature='[gt:single] status=%s finite=true';Bound=$true}
                )
                MenuSurfaces=@('Registered Pickup Diagnostics')
            },
            [pscustomobject]@{
                ModId='ct_dev'; Version='2.3.4-dev'; WorkshopId='2222222222'
                LoadRoutes=@([pscustomobject]@{Marker='[ct:LOAD]'})
                ExactBannerRoutes=@([pscustomobject]@{Tag='[ct]'})
                CommandRoutes=@([pscustomobject]@{Command='/ct_probe'})
                ReceiptRoutes=@([pscustomobject]@{Marker='[ct:only]';Signature='[ct:only] result=%s';Bound=$true})
                MenuSurfaces=@('Chest Diagnostics')
            }
        )
    }
    $contractCard = "## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.3-dev, confirm ``[wt:LOAD]```n**Topology:** Solo`n`n1. Run ``/gt_regression_test`` in chat.`n`n**Expected:** One bounded ``[gt:probe] result=ok`` receipt appears.`n`n**Workshop:** item ``1111111111``, manifest ``9000000001``."
    function Assert-Contract([string]$Name, [string]$Card, [bool]$Valid, [string]$Error) {
        $selection = Get-VtLiveTestCardSelection -Comments @([pscustomobject]@{body=$Card}) -Authority $authority -EnforceAuthority
        if ($selection.Valid -ne $Valid) { throw "$Name validity mismatch: $($selection.Errors -join ', ')" }
        if ($Error -and @($selection.Errors | Where-Object { $_ -like $Error }).Count -eq 0) {
            throw "$Name missing expected error '$Error': $($selection.Errors -join ', ')"
        }
    }
    Assert-Contract 'authoritative valid card' $contractCard $true $null
    Assert-Contract 'source-backed exact banner' ($contractCard.Replace('v1.2.3-dev, confirm `[wt:LOAD]`', 'exact banner: `[wt] v1.2.3-dev loaded`')) $true $null
    Assert-Contract 'nonexistent marker' ($contractCard.Replace('[wt:LOAD]', '[career_tweaker:LOAD]')) $false 'build-identity-not-deployed:*'
    Assert-Contract 'stale deployed version' ($contractCard.Replace('v1.2.3-dev', 'v1.2.2-dev')) $false 'build-identity-not-deployed:*'
    Assert-Contract 'stray semantic version' ($contractCard.Replace('confirm `[wt:LOAD]`','confirm `[wt:LOAD]`; unrelated v9.9.9-dev')) $false 'build-identity-not-parsable'
    Assert-Contract 'command lacks exact backticks' ($contractCard.Replace('`/gt_regression_test`', '/gt_regression_test')) $false 'command-not-exactly-backticked:*'
    Assert-Contract 'unknown exact command' ($contractCard.Replace('/gt_regression_test', '/invented_probe')) $false 'command-not-source-registered:*'
    Assert-Contract 'receipt cannot borrow unrelated registered command' ($contractCard.Replace('/gt_regression_test', '/other_probe')) $false 'diagnostic-evidence-action-command-mismatch:*'
    Assert-Contract 'wrong-case command is not exact' ($contractCard.Replace('/gt_regression_test', '/GT_REGRESSION_TEST')) $false 'command-not-source-registered:*'
    Assert-Contract 'invented friendly diagnostic' ($contractCard.Replace('Run `/gt_regression_test` in chat.', 'Run **Closed-Chest Pickup Diagnostics**.')) $false 'diagnostic-surface-not-source-registered:*'
    Assert-Contract 'click invented diagnostic' ($contractCard.Replace('Run `/gt_regression_test` in chat.', 'Click **Closed-Chest Pickup Diagnostics**.')) $false 'diagnostic-surface-not-source-registered:*'
    Assert-Contract 'select unbolded invented diagnostic' ($contractCard.Replace('Run `/gt_regression_test` in chat.', 'Select Closed-Chest Pickup Diagnostics.')) $false 'diagnostic-surface-not-source-registered:*'
    Assert-Contract 'valid command cannot hide invented diagnostic' ($contractCard.Replace('Run `/gt_regression_test` in chat.', 'Run `/gt_regression_test`, then click **Closed-Chest Pickup Diagnostics**.')) $false 'diagnostic-surface-not-source-registered:*'
    $registeredMenuCard=$contractCard.Replace('Run `/gt_regression_test` in chat.', 'Run **Registered Pickup Diagnostics**.').Replace('[gt:probe] result=ok','[gt:single] status=ok finite=true')
    Assert-Contract 'registered menu diagnostic with independent receipt' $registeredMenuCard $true $null
    Assert-Contract 'command-owned receipt still requires its command' ($contractCard.Replace('Run `/gt_regression_test` in chat.', 'Run **Registered Pickup Diagnostics**.')) $false 'diagnostic-evidence-action-command-mismatch:*'
    Assert-Contract 'payload coordinates may be omitted together' ($contractCard -replace '(?m)^\*\*Workshop:\*\*.+$','') $true $null
    Assert-Contract 'Workshop item without ManifestID is incomplete' ($contractCard.Replace(', manifest `9000000001`','')) $false 'workshop-item-without-manifest:*'
    Assert-Contract 'ManifestID without Workshop item is incomplete' ($contractCard.Replace('item `1111111111`, ','Manifest identity ')) $false 'manifest-without-workshop-item:*'
    Assert-Contract 'same target distinct manifests' ($contractCard + "`nWorkshop item ``1111111111``, ManifestID ``9000000002``.") $false 'distinct-manifests-for-workshop-item:*'
    Assert-Contract 'same target duplicate manifest' ($contractCard + "`nWorkshop item ``1111111111``, ManifestID ``9000000001``.") $false 'duplicate-workshop-manifest-pair:*'
    Assert-Contract 'selected WT build cannot cite CT item' ($contractCard.Replace('1111111111','2222222222').Replace('9000000001','8000000001')) $false 'workshop-item-not-selected-build:*'
    Assert-Contract 'single paired manifest remains advisory' ($contractCard.Replace('9000000001','9999999999')) $true $null
    $multiTarget = $contractCard.Replace('v1.2.3-dev, confirm `[wt:LOAD]`', 'v1.2.3-dev, confirm `[wt:LOAD]`; v2.3.4-dev, confirm `[ct:LOAD]`') + "`nWorkshop item ``2222222222``, manifest ``8000000001``."
    Assert-Contract 'distinct manifests for distinct targets' $multiTarget $true $null
    Assert-Contract 'second selected build may omit payload coordinates' ($multiTarget -replace '(?m)^Workshop item `2222222222`.+$','') $true $null
    Assert-Contract 'second selected build item-only coordinate is rejected' (($multiTarget -replace '(?m)^Workshop item `2222222222`.+$','Workshop item `2222222222`.')) $false 'workshop-item-without-manifest:*'
    Assert-Contract 'conflicting trailing manifest' ($contractCard + "`nManifestID ``7000000001``.") $false 'distinct-manifests-for-workshop-item:*'
    Assert-Contract 'non-printf diagnostic evidence' ($contractCard.Replace('[gt:probe]', '[gt:debug-only]')) $false 'diagnostic-evidence-not-in-selected-build:*'
    Assert-Contract 'other selected-record evidence cannot leak' ($contractCard.Replace('[gt:probe]', '[ct:only]')) $false 'diagnostic-evidence-not-in-selected-build:*'
    Assert-Contract 'marker-only evidence cannot hide an unbounded sibling' ($contractCard.Replace('[gt:probe] result=ok','[gt:probe]')) $false 'diagnostic-evidence-not-bounded:*'
    Assert-Contract 'generic repeat inherits one exact route cited elsewhere' ($contractCard.Replace('receipt appears.','receipt appears; the `[gt:probe]` line appears once.')) $true $null
    Assert-Contract 'qualified generic repeat inherits one exact route cited elsewhere' ($contractCard.Replace('receipt appears.','receipt appears; the `[gt:probe]` injection line appears once.')) $true $null
    Assert-Contract 'qualified marker-wide row accepts one finite deployed route' ($contractCard.Replace('[gt:probe] result=ok','[gt:single] smoke-bomb diagnostic row')) $true $null
    Assert-Contract 'sentence after marker-only span is not a route discriminator' ($contractCard.Replace('One bounded `[gt:probe] result=ok` receipt appears.','The bounded source receipt begins `[gt:single]`. This is only a local gate.')) $true $null
    Assert-Contract 'qualified marker-wide row still exposes an unbounded sibling' ($contractCard.Replace('[gt:probe] result=ok','[gt:probe] smoke-bomb diagnostic row')) $false 'diagnostic-evidence-not-bounded:*'
    Assert-Contract 'generic warning cannot borrow an exact sibling route' ($contractCard.Replace('receipt appears.','receipt appears; no `[gt:probe]` warnings appear.')) $false 'diagnostic-evidence-not-bounded:*'
    Assert-Contract 'authored literal prefix selects a bounded route subgroup' ($contractCard.Replace('[gt:probe] result=ok','[gt:gap] RECEIVER-GAP')) $true $null
    Assert-Contract 'vague shared prefix stays ambiguous' ($contractCard.Replace('[gt:probe] result=ok','[gt:vague] event')) $false 'diagnostic-evidence-signature-ambiguous:*'
    Assert-Contract 'invented suffix cannot borrow a marker sibling' ($contractCard.Replace('[gt:probe] result=ok','[gt:probe] invented=ok')) $false 'diagnostic-evidence-signature-not-source-registered:*'
    Assert-Contract 'card prose cannot bless unbounded printf evidence' ($contractCard.Replace('One bounded `[gt:probe] result=ok` receipt appears.', 'Exactly one bounded `[gt:unbounded] tick=1` receipt appears.')) $false 'diagnostic-evidence-not-bounded:*'
    $nativeChat = $contractCard.Replace('One bounded `[gt:probe] result=ok` receipt appears.', 'A `[ct:chat-warning]` notice may appear; it is not a log line and its absence proves nothing, so do not use it as a pass condition.')
    Assert-Contract 'explicit native-chat exception' $nativeChat $true $null
    $contradictoryNativeChat = $contractCard.Replace('One bounded `[gt:probe] result=ok` receipt appears.', 'The `[ct:chat-warning]` notice must appear; it is not a log line and its absence proves nothing, so do not use it as a pass condition.')
    Assert-Contract 'native-chat disclaimer cannot suppress a positive evidence requirement' $contradictoryNativeChat $false 'diagnostic-evidence-not-in-selected-build:*'
    $nativeChatLeak = $contractCard.Replace('One bounded `[gt:probe] result=ok` receipt appears.', 'A `[ct:chat-warning]` notice may appear; it is not a log line and its absence proves nothing, so do not use it as a pass condition; `[bad:pass] must appear` must appear.')
    Assert-Contract 'native-chat exception is marker scoped' $nativeChatLeak $false 'diagnostic-evidence-not-in-selected-build:*'
    $auditOnlySelection=Get-VtLiveTestCardSelection -Comments @([pscustomobject]@{body=$contractCard.Replace('/gt_regression_test','/invented_probe')}) -Authority $authority
    if(-not$auditOnlySelection.Valid -or $auditOnlySelection.AuthorityErrors -notcontains 'command-not-source-registered:/invented_probe' -or $auditOnlySelection.Advisories -notcontains 'command-not-source-registered:/invented_probe'){
        throw 'report-only rollout failed to preserve a legacy card while exposing its strict authority defect'
    }
    $ambiguousAuthority=[pscustomobject]@{Records=@($authority.Records + [pscustomobject]@{
        ModId='wt_clone';Version='1.2.3-dev';WorkshopId='3333333333'
        LoadRoutes=@([pscustomobject]@{Marker='[wt:LOAD]'});ExactBannerRoutes=@();CommandRoutes=@();ReceiptRoutes=@();MenuSurfaces=@()
    })}
    $ambiguousSelection=Get-VtLiveTestCardSelection -Comments @([pscustomobject]@{body=$contractCard}) -Authority $ambiguousAuthority -EnforceAuthority
    if($ambiguousSelection.Errors -notcontains 'build-identity-ambiguous:[wt:LOAD]@1.2.3-dev'){throw 'ambiguous build identity was accepted'}

    $missingManifestPath=Join-Path ([IO.Path]::GetTempPath()) ('vt-missing-manifest-'+[guid]::NewGuid().ToString('N')+'.json')
    $reportOnlyContext=Get-VtLifecycleAuthorityContext -RepoRoot $repoRoot -Repository 'fixture/fixture' -DeploymentManifestPath $missingManifestPath
    if($reportOnlyContext.Authority -or [string]::IsNullOrWhiteSpace([string]$reportOnlyContext.Error)){
        throw 'report-only authority acquisition did not preserve blocking lifecycle evaluation on authority failure'
    }
    $strictThrew=$false
    try{Get-VtLifecycleAuthorityContext -RepoRoot $repoRoot -Repository 'fixture/fixture' -DeploymentManifestPath $missingManifestPath -EnforceAuthority|Out-Null}catch{$strictThrew=$true}
    if(-not$strictThrew){throw 'strict authority acquisition failed open'}

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
# Authority acquisition subsumes the former release-manifest and deployed-
# contract phases: it fetches the deployment manifest once and indexes the
# deployed source from it. It reports both phase durations so the timing
# line below keeps naming the same four phases without a second fetch.
$authorityContext = Get-VtLifecycleAuthorityContext -RepoRoot $repoRoot -Repository $Repository `
    -DeploymentManifestPath $DeploymentManifestPath -EnforceAuthority:$EnforceAuthority
$manifestSeconds = [int]$authorityContext.ManifestSeconds
$contractSeconds = [int]$authorityContext.SourceSeconds
$authority = $authorityContext.Authority
$authorityLoadError = $authorityContext.Error
if ($authorityLoadError) {
    Write-Host "[check-lifecycle-cardinality] AUTHORITY REPORT-ONLY UNAVAILABLE: $authorityLoadError"
}
$phaseTimer.Restart()
$decisionReport = Get-LifecycleDecisionReport -Issues $issues -RequirePinnedCard -Authority $authority -EnforceAuthority:$EnforceAuthority
$violations = @($decisionReport.Violations)
$authorityFindings = @($decisionReport.AuthorityFindings)
$policySeconds = [int][math]::Round($phaseTimer.Elapsed.TotalSeconds)
Write-Host "[check-lifecycle-cardinality] timing: open-issues=${openIssueSeconds}s release-manifest=${manifestSeconds}s deployed-contract=${contractSeconds}s card-policy=${policySeconds}s total=$([int][math]::Round($totalTimer.Elapsed.TotalSeconds))s"
if($authorityFindings.Count -gt 0){
    $mode=if($EnforceAuthority){'STRICT PREVIEW'}else{'REPORT-ONLY ROLLOUT'}
    Write-Host "[check-lifecycle-cardinality] AUTHORITY ${mode}: $($authorityFindings.Count) open issue(s) have deployed-card findings:"
    foreach($finding in $authorityFindings){
        Write-Host "  - issue #$($finding.number) - $($finding.advisories -join ', ') - '$($finding.title)'"
    }
}
if ($violations.Count -eq 0) {
    $suffix=if(-not$EnforceAuthority -and ($authorityFindings.Count -gt 0 -or $authorityLoadError)){' Strict deployed-source findings are report-only during the documented rollout.'}else{''}
    Write-Host "[check-lifecycle-cardinality] OK: all $($issues.Count) open issues satisfy blocking lifecycle and live-test queue doctrine.$suffix"
    exit 0
}

Write-Host "[check-lifecycle-cardinality] FAIL: $($violations.Count) open issue(s) violate tracker doctrine:"
foreach ($violation in $violations) {
    $message = "issue #$($violation.number) [$($violation.labels -join ', ')] - $($violation.errors -join ', ') - '$($violation.title)'"
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::error::$message" }
    Write-Host "  - $message"
}
Write-Host '[check-lifecycle-cardinality] Required: exactly one of not-started/diagnostics-armed/verify-fix. Ready states require exactly one pinned exact CURRENT LIVE TEST card, and it must be the newest exact card. Fixed and verify-fix-coop are invalid while open. Pass -EnforceAuthority only after the report-only backlog is repaired.'
exit 1
