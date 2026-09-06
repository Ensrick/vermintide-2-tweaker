# Actual collector + strict policy, with only authenticated GraphQL transport
# replaced. No live GitHub, filesystem fixtures, workflow or issue mutations.
[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../tools/github/public-release-closure-collector.ps1')
$script:collectorCases=0

function Copy-CollectorFixture($Value) {
    return [Management.Automation.PSSerializer]::Deserialize(
        [Management.Automation.PSSerializer]::Serialize($Value, 15))
}

function New-CollectorFixture {
    $record=[pscustomobject]@{
        ModId='wt'; Dir='weapon_tweaker'; Stream='single'; Public=$true; Visibility='public'
        Version='1.2.2-beta'; WorkshopId='3333333333'; SourceCommit=('c'*40)
        RootBundle='0011223344556677.mod_bundle'; RootBundleSha256=('5'*64)
        AssetFilename='weapon_tweaker.zip'; AssetSha256=('6'*64)
        LoadRoutes=@([pscustomobject]@{Marker='[wt:LOAD]'}); ExactBannerRoutes=@()
        CommandRoutes=@(); ReceiptRoutes=@(); MenuSurfaces=@()
    }
    $card=[pscustomobject]@{
        databaseId=10; createdAt='2026-09-06T08:00:00Z'; updatedAt='2026-09-06T08:00:00Z'; isPinned=$true
        body="## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.2-beta, confirm ``[wt:LOAD]```n**Topology:** Solo`n`n1. Equip Kruber's Mace in the Keep.`n`n**Expected:** The selected weapon behaves normally."
        author=[pscustomobject]@{login='Ensrick'}; authorAssociation='OWNER'
    }
    $evidence=[pscustomobject]@{
        databaseId=20; createdAt='2026-09-06T09:00:00Z'; updatedAt='2026-09-06T09:00:00Z'; isPinned=$false
        body='The human report; its interpretation belongs to the authenticated verifier.'
        author=[pscustomobject]@{login='ordinary-player'}; authorAssociation='NONE'
    }
    $attestation=[pscustomobject]@{
        databaseId=30; createdAt='2026-09-06T09:21:00Z'; updatedAt='2026-09-06T09:21:00Z'; isPinned=$false
        body=''; author=[pscustomobject]@{login='Ensrick'}; authorAssociation='OWNER'
    }
    $receipt=[ordered]@{
        Schema=1; Repository='Ensrick/vermintide-2-tweaker'; IssueNumber=1527
        ClosedEventId='CE_fixture_1'; ClosedAt='2026-09-06T09:20:00Z'; VerifiedAt='2026-09-06T09:10:00Z'
        VerifierLogin='Ensrick'; VerifierAssociation='OWNER'; CardId='10'; CardSha256=(Get-VtClosureBodySha256 $card.body)
        EvidenceId='20'; EvidenceSha256=(Get-VtClosureBodySha256 $evidence.body); Outcome='public-artifact-verified'
    }
    foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version','SourceCommit',
            'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) { $receipt[$field]=$record.$field }
    $issue=[pscustomobject]@{
        id='I_fixture_1527'; number=1527; state='CLOSED'; updatedAt='2026-09-06T09:21:00Z'; closedAt='2026-09-06T09:20:00Z'
        labels=[pscustomobject]@{ nodes=@([pscustomobject]@{name='public-release'}); totalCount=1
            pageInfo=[pscustomobject]@{hasNextPage=$false;endCursor=$null} }
        timelineItems=[pscustomobject]@{totalCount=1; nodes=@([pscustomobject]@{
            __typename='ClosedEvent'; id='CE_fixture_1'; createdAt='2026-09-06T09:20:00Z'})}
        comments=[pscustomobject]@{totalCount=3; nodes=@($card,$evidence,$attestation)
            pageInfo=[pscustomobject]@{hasNextPage=$false;endCursor=$null}}
    }
    $fixture=[pscustomobject]@{
        Response=[pscustomobject]@{data=[pscustomobject]@{repository=[pscustomobject]@{
            nameWithOwner='Ensrick/vermintide-2-tweaker';issue=$issue}}}
        Authority=[pscustomobject]@{
            Source='deployed-source-contract/v1';Complete=$true;Repository='Ensrick/vermintide-2-tweaker'
            ClosedEventId='CE_fixture_1';ClosedAt='2026-09-06T09:20:00Z';PolicySourceCommit=('d'*40)
            Authority=[pscustomobject]@{Records=@($record)}
        }
        Card=$card;Evidence=$evidence;Attestation=$attestation;Receipt=$receipt
        Mutate=$null;PageSize=2;AttestationId='30';Enforce='2026-09-06T00:00:00Z'
    }
    Set-CollectorAttestation $fixture
    return $fixture
}

function Set-CollectorAttestation($Fixture) {
    $Fixture.Attestation.body='## PUBLIC RELEASE CLOSURE ATTESTATION'+"`n"+'```json'+"`n"+
        ($Fixture.Receipt | ConvertTo-Json -Depth 4 -Compress)+"`n"+'```'
}

function Invoke-CollectorFixture {
    param($Fixture, [string]$Expected='Accepted', [string]$Reason='', [string]$Name='fixture')
    $before=[Management.Automation.PSSerializer]::Serialize($Fixture.Response,15)
    $calls=New-Object 'Collections.Generic.List[object]'
    $state=[pscustomobject]@{Pass=0;Calls=0;NextCursor=$null;FirstPageNulls=0;Continuations=0}
    $request={
        param($Query,$Variables)
        if ($Query -cnotmatch '^query\(' -or $Query -match '(?i)\bmutation\b' -or
                $Variables.owner -cne 'Ensrick' -or $Variables.name -cne 'vermintide-2-tweaker' -or
                $Variables.number -cne 1527 -or $Variables.Keys.Count -ne 4) { throw 'unsafe or wrong request' }
        foreach ($field in @('authorAssociation','isPinned','updatedAt','closedAt','nameWithOwner',
                'CLOSED_EVENT','REOPENED_EVENT','totalCount')) {
            if (-not $Query.Contains($field)) { throw "missing real query field $field" }
        }
        $calls.Add((Copy-CollectorFixture $Variables));$state.Calls++
        if ($null -eq $state.NextCursor) {
            if ($null -ne $Variables.after) { throw 'first page requires literal null, not an empty-string cursor' }
            $state.FirstPageNulls++;$state.Pass++;$offset=0
        }
        else {
            if ($Variables.after -isnot [string] -or $Variables.after -cne $state.NextCursor -or
                    $Variables.after -cnotmatch '^after-([0-9]+)$') { throw 'unexpected cursor' }
            $state.Continuations++
            $offset=[int]$Matches[1]
        }
        $response=Copy-CollectorFixture $Fixture.Response
        $all=@($response.data.repository.issue.comments.nodes)
        $end=[Math]::Min($all.Count,$offset+$Fixture.PageSize)
        $page=@();for ($i=$offset;$i -lt $end;$i++) { $page+=,$all[$i] }
        $connection=$response.data.repository.issue.comments
        $connection.nodes=$page;$connection.pageInfo.hasNextPage=($end -lt $all.Count)
        $connection.pageInfo.endCursor=if($end -lt $all.Count){'after-'+$end}else{$null}
        if ($Fixture.Mutate) { & $Fixture.Mutate $response $state $Variables }
        $state.NextCursor=if ($connection.pageInfo.hasNextPage) { $connection.pageInfo.endCursor } else { $null }
        return $response
    }
    $result=Get-VtGitHubPublicReleaseClosureAudit -Repository 'Ensrick/vermintide-2-tweaker' `
        -IssueNumber 1527 -Request $request -AttestationId $Fixture.AttestationId `
        -AuthoritySnapshot $Fixture.Authority -EnforceFromUtc $Fixture.Enforce
    if ($result.Decision.Status -cne $Expected -or ($Reason -and -not $result.Decision.Reason.StartsWith($Reason))) {
        throw "$Name expected $Expected/$Reason, got $($result.Decision.Status)/$($result.Decision.Reason)"
    }
    if ($result.MayMutate -isnot [bool] -or $result.MayMutate -or $result.Decision.MayMutate -isnot [bool] -or
            $result.Decision.MayMutate -or $result.Decision.Valid -ne ($Expected -ceq 'Accepted')) {
        throw "$Name granted mutation or confused validity"
    }
    if ($result.Collection.RequestCount -ne $calls.Count -or $calls.Count -gt 44 -or
            $before -cne [Management.Automation.PSSerializer]::Serialize($Fixture.Response,15)) {
        throw "$Name mutated transport input or lost bounded request accounting"
    }
    if ($Expected -ceq 'Accepted' -and ($state.FirstPageNulls -ne 2 -or
            $state.Continuations -ne $calls.Count-2)) {
        throw "$Name did not use literal null for both first pages and exact continuation cursors"
    }
    $script:collectorCases++
    return $result
}

$f=New-CollectorFixture
$accepted=Invoke-CollectorFixture $f
if ($accepted.Collection.RequestCount -ne 4 -or $accepted.Issue.closureEventId -cne 'CE_fixture_1' -or
        $accepted.Decision.Proof.EvidenceSha256 -cne $f.Receipt.EvidenceSha256 -or
        $accepted.CommentSnapshot.Comments[0].databaseId -isnot [string]) { throw 'actual page normalization or policy proof was skipped' }
$repeat=Invoke-CollectorFixture $f
if ($repeat.Decision.ClosureKey -cne $accepted.Decision.ClosureKey) { throw 'duplicate read changed closure identity' }
$f=New-CollectorFixture;$f.PageSize=100;$null=Invoke-CollectorFixture $f
$f=New-CollectorFixture;$f.Authority=$null
$null=Invoke-CollectorFixture $f Unavailable 'closure-time-authority-unavailable' 'no invented current authority'
$f=New-CollectorFixture;$f.Authority.ClosedEventId='CE_older'
$null=Invoke-CollectorFixture $f Unavailable 'closure-time-authority-unavailable' 'wrong retained generation'
$f=New-CollectorFixture;$f.Enforce='2026-09-07T00:00:00Z';$f.Authority=$null
$null=Invoke-CollectorFixture $f LegacyReviewRequired '' 'historical #1509 not reversed'
$f=New-CollectorFixture;$f.Response.data.repository.issue.labels.nodes=@();$f.Response.data.repository.issue.labels.totalCount=0
$null=Invoke-CollectorFixture $f NotApplicable 'not-public-release'
$f=New-CollectorFixture;$i=$f.Response.data.repository.issue;$i.state='OPEN';$i.closedAt=$null
$i.timelineItems.nodes[0].__typename='ReopenedEvent'
$null=Invoke-CollectorFixture $f NotApplicable 'issue-not-closed'
$f=New-CollectorFixture;$i=$f.Response.data.repository.issue;$i.state='OPEN';$i.closedAt=$null
$i.timelineItems.nodes=@();$i.timelineItems.totalCount=0
$null=Invoke-CollectorFixture $f NotApplicable 'issue-not-closed'

foreach ($case in @(
    @{Name='wrong repository';Mutate={param($r) $r.data.repository.nameWithOwner='Elsewhere/project'};Reason='github-envelope'},
    @{Name='missing repository';Mutate={param($r) $r.data.repository=$null};Reason='github-envelope'},
    @{Name='partial GraphQL response';Mutate={param($r) $r|Add-Member errors @([pscustomobject]@{message='partial'})};Reason='github-envelope'},
    @{Name='transport failure';Mutate={throw 'untrusted body must not escape into result'};Reason='github-request'},
    @{Name='wrong issue';Mutate={param($r) $r.data.repository.issue.number=42};Reason='issue-identity'},
    @{Name='string issue number';Mutate={param($r) $r.data.repository.issue.number='1527'};Reason='issue-identity'},
    @{Name='missing update time';Mutate={param($r) $r.data.repository.issue.updatedAt=$null};Reason='issue-identity'},
    @{Name='partial labels';Mutate={param($r) $r.data.repository.issue.labels.pageInfo.hasNextPage=$true};Reason='labels-incomplete'},
    @{Name='label count mismatch';Mutate={param($r) $r.data.repository.issue.labels.totalCount=2};Reason='labels-incomplete'},
    @{Name='duplicate labels';Mutate={param($r) $i=$r.data.repository.issue;$i.labels.nodes+=,$i.labels.nodes[0];$i.labels.totalCount=2};Reason='labels-invalid'},
    @{Name='too many labels';Mutate={param($r) $r.data.repository.issue.labels.totalCount=101};Reason='labels-incomplete'},
    @{Name='missing closure';Mutate={param($r) $r.data.repository.issue.timelineItems.nodes=@()};Reason='closure-tail-incomplete'},
    @{Name='wrong closure type';Mutate={param($r) $r.data.repository.issue.timelineItems.nodes[0].__typename='ReopenedEvent'};Reason='closure-generation'},
    @{Name='wrong closure time';Mutate={param($r) $r.data.repository.issue.timelineItems.nodes[0].createdAt='2026-09-06T09:19:00Z'};Reason='closure-generation'},
    @{Name='missing closure identity';Mutate={param($r) $r.data.repository.issue.timelineItems.nodes[0].id=$null};Reason='closure-tail-invalid'},
    @{Name='missing nullable closedAt';Mutate={param($r) $r.data.repository.issue.PSObject.Properties.Remove('closedAt')};Reason='issue-identity'},
    @{Name='extra closure tail';Mutate={param($r) $r.data.repository.issue.timelineItems.nodes+=,$r.data.repository.issue.timelineItems.nodes[0]};Reason='closure-tail-incomplete'},
    @{Name='too many comments';Mutate={param($r) $r.data.repository.issue.comments.totalCount=2049};Reason='comments-connection'},
    @{Name='string comment total';Mutate={param($r) $r.data.repository.issue.comments.totalCount='3'};Reason='comments-connection'},
    @{Name='oversized page';Mutate={param($r) $r.data.repository.issue.comments.nodes=@($r.data.repository.issue.comments.nodes[0])*101};Reason='comments-connection'},
    @{Name='truncated comments';Mutate={param($r) $r.data.repository.issue.comments.pageInfo.hasNextPage=$false};Reason='comments-truncated'},
    @{Name='missing cursor';Mutate={param($r) $r.data.repository.issue.comments.pageInfo.endCursor=$null};Reason='pagination-no-progress'},
    @{Name='empty next page';Mutate={param($r) $r.data.repository.issue.comments.nodes=@()};Reason='pagination-no-progress'},
    @{Name='duplicate ID';Mutate={param($r) $r.data.repository.issue.comments.nodes[1].databaseId=10};Reason='comment-metadata'},
    @{Name='fractional ID';Mutate={param($r) $r.data.repository.issue.comments.nodes[0].databaseId=10.5};Reason='comment-metadata'},
    @{Name='missing author association';Mutate={param($r) $r.data.repository.issue.comments.nodes[0].authorAssociation=$null};Reason='comment-metadata'},
    @{Name='missing author property';Mutate={param($r) $r.data.repository.issue.comments.nodes[0].PSObject.Properties.Remove('author')};Reason='comment-metadata'},
    @{Name='malformed author object';Mutate={param($r) $r.data.repository.issue.comments.nodes[0].author=[pscustomobject]@{}};Reason='comment-author'},
    @{Name='invalid revision chronology';Mutate={param($r) $r.data.repository.issue.comments.nodes[0].updatedAt='2026-09-05T00:00:00Z'};Reason='comment-metadata'},
    @{Name='invalid Unicode';Mutate={param($r) $r.data.repository.issue.comments.nodes[0].body=[string][char]0xd800};Reason='invalid-or-unavailable'},
    @{Name='body bound';Mutate={param($r) $r.data.repository.issue.comments.nodes[0].body='x'*1048577};Reason='comment-byte'},
    @{Name='future issue';Mutate={param($r) $r.data.repository.issue.updatedAt='2099-01-01T00:00:00Z'};Reason='future-issue'}
)) {
    $f=New-CollectorFixture;$f.Mutate=$case.Mutate
    $null=Invoke-CollectorFixture $f Unavailable ('closure-collector:'+$case.Reason) $case.Name
}
foreach ($value in @('false','true',0,1,[pscustomobject]@{value=$true},$null)) {
    foreach ($axis in @('pin','pagination','labels')) {
        $f=New-CollectorFixture
        $f.Mutate={param($r)
            if ($axis -eq 'pin') { $r.data.repository.issue.comments.nodes[0].isPinned=$value }
            elseif ($axis -eq 'labels') { $r.data.repository.issue.labels.pageInfo.hasNextPage=$value }
            else { $r.data.repository.issue.comments.pageInfo.hasNextPage=$value }
        }
        $null=Invoke-CollectorFixture $f Unavailable 'closure-collector:' "strict Boolean $axis"
    }
}
foreach ($axis in @('generation','label','count','body','revision','pin','association','author')) {
    $f=New-CollectorFixture
    $f.Mutate={param($r,$state)
        if ($state.Pass -ne 2) { return }
        $i=$r.data.repository.issue
        switch ($axis) {
            generation { $i.timelineItems.nodes[0].id='CE_fixture_2' }
            label { $i.labels.nodes[0].name='other' }
            count { $i.timelineItems.totalCount=3 }
            body { $i.comments.nodes[0].body+=' edited' }
            revision { $i.comments.nodes[0].updatedAt='2026-09-06T09:21:30Z' }
            pin { $i.comments.nodes[0].isPinned=-not $i.comments.nodes[0].isPinned }
            association { $i.comments.nodes[0].authorAssociation='NONE' }
            author { $i.comments.nodes[0].author.login='other' }
        }
    }
    $null=Invoke-CollectorFixture $f Unavailable 'closure-collector:' "second-pass $axis race"
}
$f=New-CollectorFixture
$f.Mutate={param($r,$state) if($state.Calls -eq 2){$r.data.repository.issue.updatedAt='2026-09-06T09:22:00Z'}}
$null=Invoke-CollectorFixture $f Unavailable 'closure-collector:issue-changed-during-pagination' 'pagination race'
$f=New-CollectorFixture;$f.Attestation.body='PASS verified official';$null=Invoke-CollectorFixture $f Rejected 'malformed-attestation'
$f=New-CollectorFixture;$f.Attestation.author.login='attacker';$null=Invoke-CollectorFixture $f Rejected 'untrusted-or-mismatched'
$f=New-CollectorFixture;$f.Attestation.authorAssociation='NONE';$null=Invoke-CollectorFixture $f Rejected 'untrusted-or-mismatched'
$f=New-CollectorFixture;$f.Attestation.author=$null;$null=Invoke-CollectorFixture $f Unavailable 'verifier-metadata-unavailable'
$f=New-CollectorFixture;$f.Evidence.author=$null;$null=Invoke-CollectorFixture $f Accepted '' 'deleted evidence author is not the verifier'
$f=New-CollectorFixture;$f.Card.body+=' edit';$null=Invoke-CollectorFixture $f Rejected 'card-or-evidence-body-mismatch'
$f=New-CollectorFixture;$f.Evidence.updatedAt='2026-09-06T09:15:00Z';$null=Invoke-CollectorFixture $f Rejected 'verification-chronology'
$f=New-CollectorFixture;$f.AttestationId='99';$null=Invoke-CollectorFixture $f Rejected 'missing-attestation'
$f=New-CollectorFixture;$f.Authority.Authority.Records[0].Public=$false
$null=Invoke-CollectorFixture $f Rejected 'verified-artifact-not-public' 'Dev evidence cannot close #1465'
$f=New-CollectorFixture;$f.Authority.Authority.Records[0].Public='true'
$null=Invoke-CollectorFixture $f Unavailable 'authority-record-incomplete' 'transport cannot coerce Public'
$f=New-CollectorFixture;$f.Card.isPinned=$false
$null=Invoke-CollectorFixture $f Rejected 'invalid-card:' 'later unpin is read-only, not reopen authority'
$f=New-CollectorFixture;$f.Receipt.ClosedEventId='CE_old';Set-CollectorAttestation $f
$null=Invoke-CollectorFixture $f Rejected 'attestation-scope' 'old closure attestation cannot borrow new generation'
$f=New-CollectorFixture;$f.Receipt.Version='1.2.1-beta';Set-CollectorAttestation $f
$null=Invoke-CollectorFixture $f Rejected 'verified-artifact-mismatch:Version' 'typed version unchanged'
$f=New-CollectorFixture;$f.Receipt.Stream='dev';Set-CollectorAttestation $f
$null=Invoke-CollectorFixture $f Rejected 'verified-artifact-mismatch:Stream' 'typed stream unchanged'
$f=New-CollectorFixture;$f.PageSize=100
$f.Mutate={param($r)
    $i=$r.data.repository.issue;$comment=$i.comments.nodes[0];$list=@()
    for($n=0;$n -lt 17;$n++) {
        $copy=Copy-CollectorFixture $comment;$copy.databaseId=1000+$n;$copy.body='x'*1048576;$list+=,$copy
    }
    $i.comments.nodes=$list;$i.comments.totalCount=17;$i.comments.pageInfo.hasNextPage=$false
}
$null=Invoke-CollectorFixture $f Unavailable 'closure-collector:comment-byte' 'aggregate body bound'
$f=New-CollectorFixture
$f.Mutate={param($r,$state)
    $i=$r.data.repository.issue;$i.comments.totalCount=2048
    $i.comments.nodes=@($i.comments.nodes[0]);$i.comments.nodes[0].databaseId=1000+$state.Calls
    $i.comments.pageInfo.hasNextPage=$true;$i.comments.pageInfo.endCursor='after-0'
}
$null=Invoke-CollectorFixture $f Unavailable 'closure-collector:pagination-no-progress' 'repeated cursor'
$f=New-CollectorFixture
$f.Mutate={param($r,$state)
    $i=$r.data.repository.issue;$i.comments.totalCount=2048
    $i.comments.nodes=@($i.comments.nodes[0]);$i.comments.nodes[0].databaseId=1000+$state.Calls
    $i.comments.pageInfo.hasNextPage=$true;$i.comments.pageInfo.endCursor='after-0'+('0'*$state.Calls)
}
$bounded=Invoke-CollectorFixture $f Unavailable 'closure-collector:request-budget' 'bounded dishonest short pages'
if ($bounded.Collection.RequestCount -ne 44) { throw 'request ceiling not exercised exactly' }
if (-not $Quiet) { Write-Host "[check_public_release_closure_collector] PASS $script:collectorCases cases; read-only collector and actual strict policy" }
# In-process QA must not inherit an unrelated native command's failure status.
exit 0
