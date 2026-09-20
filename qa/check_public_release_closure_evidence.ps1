# #1527 retained-evidence candidate/action planner. Offline and mutation-free.
[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'tools/verify/public_release_closure_evidence.ps1')
. (Join-Path $root 'tools/github/public-release-closure-collector.ps1')

$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'check_public_release_closure_collector.ps1'),[ref]$null,[ref]$null)
$wanted=@('Copy-CollectorFixture','New-CollectorFixture','Set-CollectorAttestation','Invoke-CollectorFixture')
$functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)|Where-Object{$_.Name -cin $wanted})
if($functions.Count -ne 4){throw 'collector fixture declarations changed'}
foreach($function in $functions){. ([scriptblock]::Create($function.Extent.Text))}
$script:cases=0
function Assert-Evidence($Condition,[string]$Message){if(-not$Condition){throw $Message};$script:cases++}

try {
    $f=New-CollectorFixture;$audit=Invoke-CollectorFixture $f
    $candidate=New-VtPublicReleaseClosureEvidenceCandidate $audit $f.Authority
    $check=Test-VtPublicReleaseClosureEvidenceCandidate $candidate
    Assert-Evidence ($check.Valid -and -not$check.Authenticated -and -not$check.MayMutate) 'valid candidate confused integrity with authentication'
    $repeat=New-VtPublicReleaseClosureEvidenceCandidate $audit $f.Authority
    Assert-Evidence ($candidate.Digest -ceq $repeat.Digest) 'identical evidence was not deterministic'
    $plan=Get-VtPublicReleaseClosureActionPlan $audit $candidate
    Assert-Evidence ($plan.Disposition -ceq 'Accepted' -and $plan.Action -ceq 'observe-only' -and -not$plan.MayMutate -and
        -not$plan.EvidenceAuthenticated -and $plan.EvidenceCandidateValid) 'accepted candidate granted mutation/authentication or wrong disposition'
    $plan2=Get-VtPublicReleaseClosureActionPlan $audit $repeat
    Assert-Evidence ($plan.IntentKey -ceq $plan2.IntentKey) 'duplicate generation changed action intent'

    $tampered=[Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($candidate,20))
    $tampered.Payload.CommentSnapshot.Comments[1].body+=' altered'
    Assert-Evidence (-not(Test-VtPublicReleaseClosureEvidenceCandidate $tampered).Valid) 'body tamper retained candidate integrity'
    $tampered=[Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($candidate,20))
    $tampered.Payload.AuthoritySnapshot.Authority.Records[0].Version='9.9.9'
    Assert-Evidence (-not(Test-VtPublicReleaseClosureEvidenceCandidate $tampered).Valid) 'authority tamper retained candidate integrity'

    $f=New-CollectorFixture;$f.AttestationId='99'
    $pendingAudit=Invoke-CollectorFixture $f Rejected 'missing-attestation'
    $pendingCandidate=New-VtPublicReleaseClosureEvidenceCandidate $pendingAudit $f.Authority
    $pending=Get-VtPublicReleaseClosureActionPlan $pendingAudit $pendingCandidate
    Assert-Evidence ($pending.Disposition -ceq 'Pending' -and $pending.RequiredNext -ceq 'record-structured-attestation-for-this-closure-generation' -and
        $pending.Action -ceq 'observe-only') 'missing attestation was treated as a proven bad closure'

    $withinGrace=Copy-CollectorFixture $pendingAudit
    $withinGrace.CommentSnapshot.ObservedAt='2026-09-06T09:20:59Z'
    $openWindow=Get-VtPublicReleaseClosureActionPlan $withinGrace $null -AttestationGraceSeconds 60
    Assert-Evidence ($openWindow.Disposition -ceq 'Pending' -and $openWindow.DeadlineState -ceq 'open' -and
        $openWindow.DeadlineAt -ceq '2026-09-06T09:21:00.0000000Z' -and -not$openWindow.MayMutate) `
        'explicit grace window did not preserve a pre-deadline pending closure'
    $atDeadline=Copy-CollectorFixture $pendingAudit
    $atDeadline.CommentSnapshot.ObservedAt='2026-09-06T09:21:00Z'
    $expired=Get-VtPublicReleaseClosureActionPlan $atDeadline $null -AttestationGraceSeconds 60
    Assert-Evidence ($expired.Disposition -ceq 'Rejected' -and $expired.DeadlineState -ceq 'expired' -and
        $expired.EffectiveReason -ceq 'missing-attestation-after-grace' -and
        $expired.RequiredNext -ceq 'persist-authenticated-deadline-rejection-before-any-reopen' -and
        $expired.Action -ceq 'observe-only' -and -not$expired.MayMutate) `
        'deadline expiry either stayed pending or granted mutation authority'
    Assert-Evidence ($openWindow.IntentKey -cne $expired.IntentKey) `
        'deadline transition did not create a distinct durable action intent'
    $badWindow=Copy-CollectorFixture $pendingAudit
    $badWindow.CommentSnapshot.ObservedAt='2026-09-06T09:19:59Z'
    $unavailable=Get-VtPublicReleaseClosureActionPlan $badWindow $null -AttestationGraceSeconds 60
    Assert-Evidence ($unavailable.Disposition -ceq 'Unavailable' -and
        $unavailable.DeadlineState -ceq 'unavailable' -and -not$unavailable.MayMutate) `
        'pre-closure observation became a deadline rejection'
    $overflowWindow=Copy-CollectorFixture $pendingAudit
    $overflowWindow.Issue.closedAt='9999-12-31T23:59:59Z'
    $overflowWindow.CommentSnapshot.ObservedAt='9999-12-31T23:59:59Z'
    $overflow=Get-VtPublicReleaseClosureActionPlan $overflowWindow $null -AttestationGraceSeconds 60
    Assert-Evidence ($overflow.Disposition -ceq 'Unavailable' -and
        $overflow.DeadlineState -ceq 'unavailable' -and -not$overflow.MayMutate) `
        'overflowing deadline escaped containment or became a rejection'

    $acceptedWithGrace=Get-VtPublicReleaseClosureActionPlan $audit $candidate -AttestationGraceSeconds 60
    Assert-Evidence ($acceptedWithGrace.Disposition -ceq 'Accepted' -and
        $acceptedWithGrace.DeadlineState -ceq 'not-evaluated' -and
        $null -eq $acceptedWithGrace.AttestationGraceSeconds -and
        $acceptedWithGrace.Action -ceq 'observe-only') `
        'grace evaluation changed an accepted attestation into rejection or action'
    foreach($invalidGrace in @(0,604801)){
        $threw=$false
        try{$null=Get-VtPublicReleaseClosureActionPlan $pendingAudit $null -AttestationGraceSeconds $invalidGrace}catch{$threw=$true}
        Assert-Evidence $threw "out-of-contract grace value $invalidGrace was accepted"
    }

    $f=New-CollectorFixture;$f.Attestation.body='PASS'
    $rejectedAudit=Invoke-CollectorFixture $f Rejected 'malformed-attestation'
    $rejected=Get-VtPublicReleaseClosureActionPlan $rejectedAudit
    Assert-Evidence ($rejected.Disposition -ceq 'Rejected' -and $rejected.Action -ceq 'observe-only') 'bound rejection granted action'

    $f=New-CollectorFixture;$f.Response.data.repository.issue.state='OPEN'
    $f.Response.data.repository.issue.closedAt=$null
    $f.Response.data.repository.issue.timelineItems.totalCount=2
    $f.Response.data.repository.issue.timelineItems.nodes=@([pscustomobject]@{__typename='ReopenedEvent';id='RE_fixture';createdAt='2026-09-06T09:30:00Z'})
    $openAudit=Invoke-CollectorFixture $f NotApplicable 'issue-not-closed'
    $open=Get-VtPublicReleaseClosureActionPlan $openAudit
    Assert-Evidence ($open.Disposition -ceq 'NotApplicable' -and $open.RequiredNext -ceq 'none') 'reopened issue was actionable'

    $f=New-CollectorFixture;$f.Response.data.repository.issue.timelineItems.nodes[0].id='CE_fixture_2'
    $f.Response.data.repository.issue.closedAt='2026-09-06T10:00:00Z'
    $f.Response.data.repository.issue.updatedAt='2026-09-06T10:01:00Z'
    $f.Response.data.repository.issue.timelineItems.nodes[0].createdAt='2026-09-06T10:00:00Z'
    $f.Attestation.createdAt='2026-09-06T10:01:00Z';$f.Attestation.updatedAt='2026-09-06T10:01:00Z'
    $f.Authority.ClosedEventId='CE_fixture_2';$f.Authority.ClosedAt='2026-09-06T10:00:00Z'
    $newAudit=Invoke-CollectorFixture $f Rejected 'attestation-scope'
    $newCandidate=New-VtPublicReleaseClosureEvidenceCandidate $newAudit $f.Authority
    Assert-Evidence ($newCandidate.Digest -cne $candidate.Digest -and
        (Get-VtPublicReleaseClosureActionPlan $newAudit $newCandidate).IntentKey -cne $plan.IntentKey) 'new closure generation borrowed prior intent'

    foreach($invalid in @(([string][char]0xD800),([string][char]0xDC00))){
        $threw=$false;try{$null=Get-VtClosureCanonicalSha256 ([ordered]@{Value=$invalid})}catch{$threw=$true}
        Assert-Evidence $threw 'invalid Unicode was normalized during canonical hashing'
    }
    Assert-Evidence ((Get-VtClosureCanonicalSha256 ([ordered]@{b=2;a=1})) -ceq
        (Get-VtClosureCanonicalSha256 ([ordered]@{a=1;b=2}))) 'object property order changed canonical digest'
    if(-not$Quiet){Write-Host "[check_public_release_closure_evidence] PASS $script:cases assertions; candidates are integrity-only and plans are observe-only."}
    exit 0
} catch {
    Write-Host "[check_public_release_closure_evidence] FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
