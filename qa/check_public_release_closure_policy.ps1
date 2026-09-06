# #1527 offline policy fixtures. No API calls, issue writes, or live authority.
[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/verify/public_release_closure_policy.ps1')
$script:closureCaseCount = 0

function New-ClosureFixture {
    $public = [pscustomobject]@{
        ModId='wt'; Dir='weapon_tweaker'; Stream='single'; Public=$true; Visibility='public'
        Version='1.2.2-beta'; WorkshopId='3333333333'; SourceCommit=('c' * 40)
        RootBundle='0011223344556677.mod_bundle'; RootBundleSha256=('5' * 64)
        AssetFilename='weapon_tweaker.zip'; AssetSha256=('6' * 64)
        LoadRoutes=@([pscustomobject]@{Marker='[wt:LOAD]'}); ExactBannerRoutes=@()
        CommandRoutes=@(); ReceiptRoutes=@(); MenuSurfaces=@()
    }
    $dev = [pscustomobject]@{
        ModId='wt_dev'; Dir='weapon_tweaker_dev'; Stream='dev'; Public=$false; Visibility='friends_only'
        Version='1.2.3-dev'; WorkshopId='1111111111'; SourceCommit=('a' * 40)
        RootBundle='0123456789abcdef.mod_bundle'; RootBundleSha256=('1' * 64)
        AssetFilename='weapon_tweaker_dev.zip'; AssetSha256=('2' * 64)
        LoadRoutes=@([pscustomobject]@{Marker='[wt:LOAD]'}); ExactBannerRoutes=@()
        CommandRoutes=@(); ReceiptRoutes=@(); MenuSurfaces=@()
    }
    $card = [pscustomobject]@{
        databaseId='10'; createdAt='2026-09-06T08:00:00Z'; updatedAt='2026-09-06T08:00:00Z'; isPinned=$true
        body="## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.2-beta, confirm ``[wt:LOAD]```n**Topology:** Solo`n`n1. Equip Kruber's Mace in the Keep.`n`n**Expected:** The selected weapon behaves normally."
        author=[pscustomobject]@{login='Ensrick'}; authorAssociation='OWNER'
    }
    $evidence = [pscustomobject]@{
        databaseId='20'; createdAt='2026-09-06T09:00:00Z'; updatedAt='2026-09-06T09:00:00Z'; isPinned=$false
        body='Test report and its exact attached-log link; interpretation belongs to the trusted verifier.'
        author=[pscustomobject]@{login='RainReligion'}; authorAssociation='COLLABORATOR'
    }
    $attestation = [pscustomobject]@{
        databaseId='30'; createdAt='2026-09-06T09:21:00Z'; updatedAt='2026-09-06T09:21:00Z'; isPinned=$false
        body=''; author=[pscustomobject]@{login='Ensrick'}; authorAssociation='OWNER'
    }
    $receipt = [ordered]@{
        Schema=1; Repository='Ensrick/vermintide-2-tweaker'; IssueNumber=1527
        ClosedEventId='CE_fixture_1'; ClosedAt='2026-09-06T09:20:00Z'; VerifiedAt='2026-09-06T09:10:00Z'
        VerifierLogin='Ensrick'; VerifierAssociation='OWNER'; CardId='10'
        CardSha256=(Get-VtClosureBodySha256 $card.body); EvidenceId='20'
        EvidenceSha256=(Get-VtClosureBodySha256 $evidence.body); Outcome='public-artifact-verified'
    }
    foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version','SourceCommit',
            'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) { $receipt[$field] = $public.$field }
    $fixture = [pscustomobject]@{
        Issue=[pscustomobject]@{
            Complete=$true; repository='Ensrick/vermintide-2-tweaker'; number=1527; state='CLOSED'
            labels=@([pscustomobject]@{name='public-release'},[pscustomobject]@{name='verify-fix'})
            closedAt='2026-09-06T09:20:00Z'; closureEventId='CE_fixture_1'
        }
        Snapshot=[pscustomobject]@{
            Complete=$true; PinsComplete=$true; ObservedAt='2026-09-06T09:22:00Z'
            Comments=@($card,$evidence,$attestation)
        }
        Authority=[pscustomobject]@{
            Source='deployed-source-contract/v1'; Complete=$true; PolicySourceCommit=('d' * 40)
            Repository='Ensrick/vermintide-2-tweaker'; ClosedEventId='CE_fixture_1'; ClosedAt='2026-09-06T09:20:00Z'
            Authority=[pscustomobject]@{Records=@($public,$dev)}
        }
        Card=$card; Evidence=$evidence; Attestation=$attestation; Receipt=$receipt
    }
    Set-FixtureAttestation $fixture
    return $fixture
}

function Set-FixtureAttestation($Fixture) {
    $Fixture.Attestation.body = '## PUBLIC RELEASE CLOSURE ATTESTATION' + "`n" + '```json' + "`n" +
        ($Fixture.Receipt | ConvertTo-Json -Depth 4 -Compress) + "`n" + '```'
}

function New-ClosureBoundsComment {
    param([string]$Id, [string]$Body)
    return [pscustomobject]@{
        databaseId=$Id; createdAt='2026-09-06T08:30:00Z'; updatedAt='2026-09-06T08:30:00Z'
        isPinned=$false; body=$Body
    }
}

function Assert-ClosureDecision {
    param([string]$Name, $Fixture, [string]$Status, [string]$Reason)
    $decision = Get-VtPublicReleaseClosureDecision -Repository 'Ensrick/vermintide-2-tweaker' `
        -Issue $Fixture.Issue -CommentSnapshot $Fixture.Snapshot -AttestationId '30' `
        -AuthoritySnapshot $Fixture.Authority -EnforceFromUtc '2026-09-06T00:00:00Z'
    if ($decision.Status -cne $Status -or ($Reason -and -not $decision.Reason.StartsWith($Reason))) {
        throw "$Name expected $Status/$Reason; got $($decision.Status)/$($decision.Reason)"
    }
    if ($decision.MayMutate -ne $false -or $decision.Valid -ne ($Status -ceq 'Accepted')) {
        throw "$Name granted mutation or confused acceptance with availability"
    }
    $script:closureCaseCount++
    return $decision
}

try {
    $f = New-ClosureFixture
    $before = $f | ConvertTo-Json -Depth 12 -Compress
    $accepted = Assert-ClosureDecision 'official public beta accepted' $f 'Accepted'
    if (($f | ConvertTo-Json -Depth 12 -Compress) -cne $before) { throw 'policy mutated its input snapshot' }
    $repeat = Assert-ClosureDecision 'duplicate event deterministic' $f 'Accepted'
    if ($repeat.ClosureKey -cne $accepted.ClosureKey -or $repeat.Proof.AttestationSha256 -cne $accepted.Proof.AttestationSha256) {
        throw 'duplicate generation changed its immutable proof identity'
    }
    # Shared strict selector is actually invoked; the ordinary Rain result does
    # not accidentally route through the OPEN invitation-consumption decision.
    $selection = Get-VtLiveTestCardSelection -Comments $f.Snapshot.Comments -RequirePinnedCard -Authority $f.Authority.Authority -EnforceAuthority
    if (-not $selection.Valid) { throw 'fixture did not exercise strict card authority' }

    # Full source authority includes canonical uppercase WOC and pinned legacy
    # records. Neither unrelated identity may strand a modern verified target.
    $f=New-ClosureFixture
    $woc=($f.Authority.Authority.Records[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    $woc.ModId='WOC';$woc.Dir='weapons_of_chaos';$woc.WorkshopId='3753880932'
    $woc.AssetFilename='weapons_of_chaos.zip';$woc.LoadRoutes=@([pscustomobject]@{Marker='[WOC:LOAD]'})
    $f.Authority.Authority.Records += $woc
    $null=Assert-ClosureDecision 'canonical WOC sibling does not strand modern closure' $f 'Accepted'
    $f.Card.body=$f.Card.body.Replace('[wt:LOAD]','[WOC:LOAD]')
    $f.Receipt.CardSha256=Get-VtClosureBodySha256 $f.Card.body
    foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version','SourceCommit',
            'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) { $f.Receipt[$field]=$woc.$field }
    Set-FixtureAttestation $f
    $null=Assert-ClosureDecision 'canonical uppercase WOC is an exact verified target' $f 'Accepted'
    $f.Receipt.ModId='woc';Set-FixtureAttestation $f
    $null=Assert-ClosureDecision 'case-changed WOC attestation is not an alias' $f 'Rejected' 'verified-artifact-not-public-card-target'
    $f=New-ClosureFixture
    $f.Authority.Authority.Records[1].ModId='WT'
    $null=Assert-ClosureDecision 'case-colliding authority records are incomplete' $f 'Unavailable' 'authority-record'

    $legacyPins=Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot '../tools/verify/live_test_contract_exceptions.psd1')
    foreach ($pin in @($legacyPins.LegacySourceTrees)) {
        $f=New-ClosureFixture
        $legacy=($f.Authority.Authority.Records[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
        $legacy.ModId=[string]$pin.ModId;$legacy.Dir=if($pin.ModId -ceq 'ct'){'chaos_wastes_tweaker'}else{'verminious_dreams_lighting'}
        $legacy.Version=[string]$pin.Version;$legacy.WorkshopId='9999999998';$legacy.AssetFilename=$legacy.Dir+'.zip'
        $legacy.SourceCommit=$null
        $legacy | Add-Member -NotePropertyName RootTree -NotePropertyValue ([string]$pin.RootTree)
        $legacy | Add-Member -NotePropertyName ModTree -NotePropertyValue ([string]$pin.ModTree)
        $legacy.LoadRoutes=@([pscustomobject]@{Marker=('['+$legacy.ModId+':LOAD]')})
        $f.Authority.Authority.Records += $legacy
        $null=Assert-ClosureDecision "unrelated pinned legacy $($pin.ModId) retains modern verification" $f 'Accepted'
        foreach ($field in @('RootTree','ModTree')) {
            $original=$legacy.$field;$legacy.$field='../not-a-tree'
            $null=Assert-ClosureDecision "legacy $($pin.ModId) requires immutable $field" $f 'Unavailable' 'authority-record'
            $legacy.$field=$original
        }
        foreach ($badCommit in @('', ' ', 42, 'not-a-commit')) {
            $legacy.SourceCommit=$badCommit
            $null=Assert-ClosureDecision "legacy $($pin.ModId) accepts only literal null, not $badCommit" $f 'Unavailable' 'authority-record'
        }
        $legacy.PSObject.Properties.Remove('SourceCommit')
        $null=Assert-ClosureDecision "legacy $($pin.ModId) cannot omit source identity field" $f 'Unavailable' 'authority-record'
        $legacy | Add-Member -NotePropertyName SourceCommit -NotePropertyValue $null

        $rootName=$legacy.RootBundle;$rootHash=$legacy.RootBundleSha256
        $legacy.RootBundle=$null;$legacy.RootBundleSha256=$null
        $null=Assert-ClosureDecision "legacy $($pin.ModId) may predate root-bundle metadata" $f 'Accepted'
        foreach ($field in @('RootBundle','RootBundleSha256')) {
            foreach ($bad in @('',42,'malformed')) {
                $legacy.$field=$bad
                $null=Assert-ClosureDecision "legacy $($pin.ModId) rejects partial/noncanonical $field" $f 'Unavailable' 'authority-record'
            }
            $legacy.PSObject.Properties.Remove($field)
            $null=Assert-ClosureDecision "legacy $($pin.ModId) cannot omit $field" $f 'Unavailable' 'authority-record'
            $legacy | Add-Member -NotePropertyName $field -NotePropertyValue $null
        }
        $legacy.RootBundle=$rootName
        $null=Assert-ClosureDecision "legacy $($pin.ModId) cannot borrow a root name without a digest" $f 'Unavailable' 'authority-record'
        $legacy.RootBundle=$null;$legacy.RootBundleSha256=$rootHash
        $null=Assert-ClosureDecision "legacy $($pin.ModId) cannot borrow a digest without a root name" $f 'Unavailable' 'authority-record'
        $legacy.RootBundle=$rootName

        # A public legacy sibling never lends public credit to a Dev pass.
        $f.Card.body=$f.Card.body.Replace('v1.2.2-beta','v1.2.3-dev')
        $f.Receipt.CardSha256=Get-VtClosureBodySha256 $f.Card.body
        foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version','SourceCommit',
                'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) { $f.Receipt[$field]=$f.Authority.Authority.Records[1].$field }
        Set-FixtureAttestation $f
        $null=Assert-ClosureDecision "legacy $($pin.ModId) cannot lend public identity to Dev evidence" $f 'Rejected' 'verified-artifact-not-public-card-target'

        $f.Card.body=$f.Card.body.Replace('v1.2.3-dev',('v'+$legacy.Version)).Replace('[wt:LOAD]',('['+$legacy.ModId+':LOAD]'))
        $f.Receipt.CardSha256=Get-VtClosureBodySha256 $f.Card.body
        foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version',
                'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) { $f.Receipt[$field]=$legacy.$field }
        $f.Receipt.SourceCommit=$legacy.RootTree # A tree is not a commit substitute.
        Set-FixtureAttestation $f
        $null=Assert-ClosureDecision "legacy $($pin.ModId) cannot fabricate an attested source commit" $f 'Rejected' 'verified-artifact-source-commit-unavailable'
    }
    $f=New-ClosureFixture
    $f.Authority.Authority.Records[1].RootBundle=$null;$f.Authority.Authority.Records[1].RootBundleSha256=$null
    $null=Assert-ClosureDecision 'modern unrelated source cannot borrow legacy root-metadata exemption' $f 'Unavailable' 'authority-record'

    $cases = @(
        @{Name='non-public no-op';Status='NotApplicable';Reason='not-public';Mutate={param($f) $f.Issue.labels=@()}},
        @{Name='missing issue labels cannot grant no-op';Status='Unavailable';Reason='issue-snapshot';Mutate={param($f) $f.Issue.labels=$null}},
        @{Name='partial issue snapshot';Status='Unavailable';Reason='issue-snapshot';Mutate={param($f) $f.Issue.Complete=$false}},
        @{Name='already reopened no-op';Status='NotApplicable';Reason='issue-not-closed';Mutate={param($f) $f.Issue.state='OPEN'}},
        @{Name='historical #1509 needs migration, not rejection';Status='LegacyReviewRequired';Reason='predates';Mutate={param($f) $f.Issue.number=1509;$f.Issue.closedAt='2026-09-04T12:00:00Z';$f.Snapshot=$null;$f.Authority=$null}},
        @{Name='incomplete comments';Status='Unavailable';Reason='comment-or-pin';Mutate={param($f) $f.Snapshot.Complete=$false}},
        @{Name='incomplete pins';Status='Unavailable';Reason='comment-or-pin';Mutate={param($f) $f.Snapshot.PinsComplete=$false}},
        @{Name='truthy completeness is not proof';Status='Unavailable';Reason='comment-or-pin';Mutate={param($f) $f.Snapshot.Complete='true'}},
        @{Name='missing selected pin state';Status='Unavailable';Reason='card-pin-state';Mutate={param($f) $f.Card.PSObject.Properties.Remove('isPinned')}},
        @{Name='missing card revision metadata';Status='Unavailable';Reason='comment-metadata';Mutate={param($f) $f.Card.updatedAt=$null}},
        @{Name='missing evidence revision metadata';Status='Unavailable';Reason='comment-metadata';Mutate={param($f) $f.Evidence.updatedAt=$null}},
        @{Name='duplicate comment identity';Status='Unavailable';Reason='comment-metadata';Mutate={param($f) $f.Snapshot.Comments += $f.Card}},
        @{Name='unavailable authority';Status='Unavailable';Reason='closure-time';Mutate={param($f) $f.Authority=$null}},
        @{Name='partial authority';Status='Unavailable';Reason='closure-time';Mutate={param($f) $f.Authority.Complete=$false}},
        @{Name='borrowed authority generation';Status='Unavailable';Reason='closure-time';Mutate={param($f) $f.Authority.ClosedEventId='CE_other'}},
        @{Name='untrusted authority provenance';Status='Unavailable';Reason='closure-time';Mutate={param($f) $f.Authority.Source='PASS'}},
        @{Name='partial artifact record';Status='Unavailable';Reason='authority-record';Mutate={param($f) $f.Authority.Authority.Records[0].SourceCommit=$null}},
        @{Name='missing authority routing census';Status='Unavailable';Reason='authority-routes';Mutate={param($f) $f.Authority.Authority.Records[0].LoadRoutes=$null}},
        @{Name='truthy public metadata is not canonical';Status='Unavailable';Reason='authority-record';Mutate={param($f) $f.Authority.Authority.Records[0].Public='true'}},
        @{Name='duplicate authority identity';Status='Unavailable';Reason='authority-record';Mutate={param($f) $f.Authority.Authority.Records += $f.Authority.Authority.Records[0]}},
        @{Name='missing verifier API metadata';Status='Unavailable';Reason='verifier-metadata';Mutate={param($f) $f.Attestation.authorAssociation=$null}},
        @{Name='missing attestation';Status='Rejected';Reason='missing-attestation';Mutate={param($f) $f.Snapshot.Comments=@($f.Card,$f.Evidence)}},
        @{Name='arbitrary PASS prose';Status='Rejected';Reason='malformed-attestation';Mutate={param($f) $f.Attestation.body='PASS, fixed, user-confirmed on public!'}},
        @{Name='untrusted attester';Status='Rejected';Reason='untrusted';Mutate={param($f) $f.Attestation.author.login='outsider'}},
        @{Name='forged trusted association';Status='Rejected';Reason='untrusted';Mutate={param($f) $f.Attestation.authorAssociation='NONE'}},
        @{Name='card edited after attestation';Status='Rejected';Reason='card-or-evidence-body';Mutate={param($f) $f.Card.body += "`nChanged."}},
        @{Name='evidence edited after attestation';Status='Rejected';Reason='card-or-evidence-body';Mutate={param($f) $f.Evidence.body += ' Changed.'}},
        @{Name='card unpinned';Status='Rejected';Reason='invalid-card';Mutate={param($f) $f.Card.isPinned=$false}},
        @{Name='no card';Status='Rejected';Reason='invalid-card';Mutate={param($f) $f.Snapshot.Comments=@($f.Evidence,$f.Attestation)}},
        @{Name='missing evidence';Status='Rejected';Reason='missing-or-aliased';Mutate={param($f) $f.Snapshot.Comments=@($f.Card,$f.Attestation)}},
        @{Name='stale selected build';Status='Rejected';Reason='invalid-card';Mutate={param($f) $f.Card.body=$f.Card.body.Replace('1.2.2-beta','1.1.0-beta')}},
        @{Name='post-close card revision with old body';Status='Rejected';Reason='verification-chronology';Mutate={param($f) $f.Card.updatedAt='2026-09-06T09:20:01Z'}},
        @{Name='evidence revision after observed verification';Status='Rejected';Reason='verification-chronology';Mutate={param($f) $f.Evidence.updatedAt='2026-09-06T09:10:01Z'}},
        @{Name='post-close evidence revision with old body';Status='Rejected';Reason='verification-chronology';Mutate={param($f) $f.Evidence.updatedAt='2026-09-06T09:20:01Z'}},
        @{Name='evidence predates card';Status='Rejected';Reason='verification-chronology';Mutate={param($f) $f.Evidence.createdAt='2026-09-06T07:59:59Z'}},
        @{Name='attestation predates closure generation';Status='Rejected';Reason='verification-chronology';Mutate={param($f) $f.Attestation.createdAt='2026-09-06T09:19:59Z'}},
        @{Name='snapshot predates known comments';Status='Unavailable';Reason='comment-metadata';Mutate={param($f) $f.Snapshot.ObservedAt='2026-09-06T09:20:00Z'}}
    )
    foreach ($case in $cases) {
        $f=New-ClosureFixture
        & $case.Mutate $f
        $null=Assert-ClosureDecision $case.Name $f $case.Status $case.Reason
    }
    foreach ($value in @('false','true',1,[pscustomobject]@{value=$true})) {
        foreach ($flag in @('Issue','Comments','Pins','Authority','Public')) {
            $f=New-ClosureFixture
            switch ($flag) {
                'Issue' { $f.Issue.Complete=$value }
                'Comments' { $f.Snapshot.Complete=$value }
                'Pins' { $f.Snapshot.PinsComplete=$value }
                'Authority' { $f.Authority.Complete=$value }
                'Public' { $f.Authority.Authority.Records[0].Public=$value }
            }
            $null=Assert-ClosureDecision "no truthiness coercion for $flag/$($value.GetType().Name)" $f 'Unavailable'
        }
    }
    foreach ($field in @('ModId','Dir','WorkshopId')) {
        $f=New-ClosureFixture
        $f.Authority.Authority.Records[1].$field=$f.Authority.Authority.Records[0].$field
        $null=Assert-ClosureDecision "duplicate canonical artifact $field" $f 'Unavailable' 'authority-record'
    }
    foreach ($field in @('ModId','Dir','Version','RootBundle','AssetFilename','WorkshopId','SourceCommit','RootBundleSha256','AssetSha256')) {
        $f=New-ClosureFixture
        $f.Authority.Authority.Records[0].$field='../malformed-target'
        $null=Assert-ClosureDecision "malformed canonical artifact $field" $f 'Unavailable' 'authority-record'
    }
    $f=New-ClosureFixture
    $f.Authority.Authority | Add-Member -MemberType ScriptProperty -Name Records -Value { throw 'unreadable authority' } -Force
    $null=Assert-ClosureDecision 'throwing authority accessor is unavailable, not negative evidence' $f 'Unavailable'
    $f=New-ClosureFixture
    $f.Evidence.databaseId='9999999999999999999'
    $null=Assert-ClosureDecision 'overflow comment ID is incomplete API metadata' $f 'Unavailable' 'comment-metadata'
    foreach ($field in @('Repository','IssueNumber','ClosedEventId','ClosedAt','Outcome','CardId','EvidenceId',
            'VerifierLogin','VerifierAssociation','WorkshopId','Dir','Stream','Version','SourceCommit',
            'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) {
        $f=New-ClosureFixture
        $f.Receipt[$field] = switch ($field) {
            'IssueNumber' { 9999 }; 'ClosedAt' { '2026-09-06T09:20:01Z' }
            'CardId' { '11' }; 'EvidenceId' { '21' }; 'WorkshopId' { '9999999999' }
            'SourceCommit' { 'e' * 40 }; 'RootBundleSha256' { 'e' * 64 }; 'AssetSha256' { 'e' * 64 }
            default { 'wrong-value' }
        }
        Set-FixtureAttestation $f
        $null=Assert-ClosureDecision "attestation binds $field" $f 'Rejected'
    }
    $f=New-ClosureFixture
    $f.Card.body=$f.Card.body.Replace('v1.2.2-beta','v1.2.3-dev')
    $f.Receipt.CardSha256=Get-VtClosureBodySha256 $f.Card.body
    Set-FixtureAttestation $f
    $null=Assert-ClosureDecision '#1465 Dev-only evidence cannot close public issue' $f 'Rejected' 'verified-artifact-not-public-card-target'
    $f=New-ClosureFixture
    $f.Card.body=$f.Card.body.Replace('v1.2.2-beta, confirm `[wt:LOAD]`','v1.2.3-dev, confirm `[wt:LOAD]`; v1.2.2-beta, confirm `[wt:LOAD]`')
    $f.Receipt.CardSha256=Get-VtClosureBodySha256 $f.Card.body
    Set-FixtureAttestation $f
    $null=Assert-ClosureDecision 'mixed card explicitly verifies public target' $f 'Accepted'
    foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version','SourceCommit','RootBundle',
            'RootBundleSha256','AssetFilename','AssetSha256')) { $f.Receipt[$field]=$f.Authority.Authority.Records[1].$field }
    Set-FixtureAttestation $f
    $null=Assert-ClosureDecision 'mixed card Dev pass cannot borrow public sibling' $f 'Rejected' 'verified-artifact-not-public-card-target'

    $f=New-ClosureFixture
    $f.Attestation.body=$f.Attestation.body.Replace('"Schema":1','"Schema":1,"Schema":1')
    $null=Assert-ClosureDecision 'duplicate JSON key rejected on both hosts' $f 'Rejected' 'malformed'
    $f=New-ClosureFixture
    $f.Attestation.body=$f.Attestation.body.Replace('"Schema"','"\u0053chema"')
    $null=Assert-ClosureDecision 'escaped JSON field identity rejected' $f 'Rejected' 'malformed'
    $f=New-ClosureFixture
    $f.Receipt.VerifiedAt='2026-09-06T09:20:01Z';Set-FixtureAttestation $f
    $null=Assert-ClosureDecision 'verification must precede closure' $f 'Rejected' 'verification-chronology'
    $f=New-ClosureFixture
    $f.Issue.closureEventId='CE_fixture_2';$f.Authority.ClosedEventId='CE_fixture_2'
    $null=Assert-ClosureDecision 'old receipt cannot authorize another closure generation' $f 'Rejected' 'attestation-scope'
    $f=New-ClosureFixture
    $laterPublication=New-ClosureFixture
    $laterPublication.Authority.Authority.Records[0].Version='1.2.4-beta'
    $null=Assert-ClosureDecision 'frozen accepted closure survives later publication' $f 'Accepted'
    $f.Authority=$laterPublication.Authority
    $null=Assert-ClosureDecision 'current replacement authority cannot impersonate frozen proof' $f 'Rejected' 'invalid-card'
    $f=New-ClosureFixture
    $second=[pscustomobject]@{databaseId='11';createdAt='2026-09-06T08:10:00Z';updatedAt='2026-09-06T08:10:00Z';isPinned=$true;body=$f.Card.body}
    $f.Snapshot.Comments += $second
    $null=Assert-ClosureDecision 'multiple pinned cards rejected' $f 'Rejected' 'invalid-card'
    $f.Card.isPinned=$false
    $null=Assert-ClosureDecision 'old card ID cannot borrow newer pinned card' $f 'Rejected' 'card-or-evidence-body'
    $f.Card.PSObject.Properties.Remove('isPinned')
    $null=Assert-ClosureDecision 'older card missing pin metadata is unavailable, not a false count' $f 'Unavailable' 'card-pin-state'
    $f=New-ClosureFixture
    $f.Attestation.author.login='RainReligion';$f.Attestation.authorAssociation='COLLABORATOR'
    $f.Receipt.VerifierLogin='RainReligion';$f.Receipt.VerifierAssociation='COLLABORATOR';Set-FixtureAttestation $f
    $null=Assert-ClosureDecision 'designated trusted tester may attest' $f 'Accepted'
    $f=New-ClosureFixture
    $f.Issue.number=1509;$f.Receipt.IssueNumber=1509
    $f.Evidence.body='Public General Tweaker still uses its old mod version; the upstream game update fixed both tested outcomes.'
    $f.Receipt.EvidenceSha256=Get-VtClosureBodySha256 $f.Evidence.body;Set-FixtureAttestation $f
    $null=Assert-ClosureDecision 'upstream correction does not require a new mod version' $f 'Accepted'

    # Exercise UTF-8 bytes, not UTF-16 character count. NBSP is legal trailing
    # whitespace in this body grammar and uses two UTF-8 bytes per character.
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    foreach ($unit in @(' ',([string][char]0x00A0))) {
        foreach ($targetBytes in @(16383,16384,16385)) {
            $f=New-ClosureFixture
            $remaining=$targetBytes-$utf8.GetByteCount($f.Attestation.body)
            $unitBytes=$utf8.GetByteCount($unit)
            $f.Attestation.body += ($unit * [int][Math]::Floor($remaining/$unitBytes)) + (' ' * ($remaining % $unitBytes))
            if ($utf8.GetByteCount($f.Attestation.body) -ne $targetBytes) { throw 'invalid attestation boundary fixture' }
            $status=if($targetBytes -le 16384){'Accepted'}else{'Rejected'}
            $reason=if($targetBytes -le 16384){''}else{'malformed-attestation'}
            $null=Assert-ClosureDecision "attestation $unitBytes-byte character boundary $targetBytes" $f $status $reason
        }
    }
    $f=New-ClosureFixture
    $f.Snapshot.Comments=@($f.Card) * 2049
    $null=Assert-ClosureDecision 'oversized comment census stops before reading duplicates' $f 'Unavailable' 'comment-snapshot-bounds-or-time'
    foreach ($bytes in @(1048576,1048577)) {
        $f=New-ClosureFixture
        $f.Snapshot.Comments += New-ClosureBoundsComment '100' ('x' * $bytes)
        $status=if($bytes -le 1048576){'Accepted'}else{'Unavailable'}
        $reason=if($bytes -le 1048576){''}else{'comment-snapshot-too-large'}
        $null=Assert-ClosureDecision "individual comment boundary $bytes" $f $status $reason
    }
    # Reuse one immutable 1 MiB string rather than allocating sixteen copies.
    # At most one additional remainder string is retained for the aggregate edge.
    $chunk='x' * 1048576
    foreach ($extraByte in @(0,1)) {
        $f=New-ClosureFixture
        $initialBytes=0
        foreach($comment in $f.Snapshot.Comments){$initialBytes += $utf8.GetByteCount($comment.body)}
        for($i=0;$i -lt 15;$i++){$f.Snapshot.Comments += New-ClosureBoundsComment ([string](100+$i)) $chunk}
        $remainder=16777216-$initialBytes-(15*1048576)+$extraByte
        $f.Snapshot.Comments += New-ClosureBoundsComment '115' ('x' * $remainder)
        $status=if($extraByte -eq 0){'Accepted'}else{'Unavailable'}
        $reason=if($extraByte -eq 0){''}else{'comment-snapshot-too-large'}
        $null=Assert-ClosureDecision "aggregate comment boundary plus $extraByte" $f $status $reason
    }
    $f=New-ClosureFixture
    $records=New-Object 'Collections.Generic.List[object]'
    foreach($record in $f.Authority.Authority.Records){$records.Add($record)}
    for($i=2;$i -lt 256;$i++) {
        $row=[ordered]@{}
        foreach($property in $f.Authority.Authority.Records[0].PSObject.Properties){$row[$property.Name]=$property.Value}
        $row.ModId="fixture_$i";$row.Dir="fixture_$i";$row.WorkshopId=[string](4000000000L+$i);$row.Version="2.0.$i"
        $records.Add([pscustomobject]$row)
    }
    $f.Authority.Authority.Records=$records.ToArray()
    $null=Assert-ClosureDecision 'authority census boundary 256' $f 'Accepted'
    $f.Authority.Authority.Records += $f.Authority.Authority.Records[0]
    $null=Assert-ClosureDecision 'authority census 257 stops before duplicate validation' $f 'Unavailable' 'closure-time-authority-unavailable'
    foreach($invalid in @(([string][char]0xD800),([string][char]0xDC00))) {
        $threw=$false
        try { $null=Get-VtClosureBodySha256 $invalid } catch { $threw=$true }
        if(-not$threw){throw 'hashing replaced invalid Unicode instead of rejecting it'}
        $script:closureCaseCount++
        foreach($surface in @('Card','Evidence','Attestation','Unrelated')) {
            $f=New-ClosureFixture
            if($surface -ceq 'Unrelated'){$f.Snapshot.Comments += New-ClosureBoundsComment '100' $invalid}
            else{$f.$surface.body += $invalid}
            $null=Assert-ClosureDecision "invalid Unicode contained at $surface" $f 'Unavailable' 'closure-policy-input-or-authority-error'
        }
    }
    if((Get-VtClosureBodySha256 'abc') -cne 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') {
        throw 'UTF-8 body hashing changed the known SHA-256 vector'
    }
    $script:closureCaseCount++
    if (-not $Quiet) { Write-Host "[check_public_release_closure_policy] OK - $script:closureCaseCount deterministic cases; no live mutations." }
    exit 0
} catch {
    Write-Host "[check_public_release_closure_policy] FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
