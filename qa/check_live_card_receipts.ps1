# #1102: finite historical receipts through the real planner and installed loop.
# Fixture records are complete selections from one deployment-bound index, not
# a scanner replacement. No GitHub, build, claim, or source mutation is allowed.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference='Stop'

function Invoke-VtCurrentReceiptTests {
    param([string]$FixturePath, [string]$RefreshSource, [string]$Only)
    $fixtureRaw=[IO.File]::ReadAllBytes($FixturePath)
    $hasher=[Security.Cryptography.SHA256]::Create()
    try { $hash=([BitConverter]::ToString($hasher.ComputeHash($fixtureRaw))).Replace('-','').ToLowerInvariant() }
    finally { $hasher.Dispose() }
    if ($hash -cne '5e2a6b32b5b09c354dd9a511b3141966df5364f7519a240bf22ab8c09a9a6712') { throw 'Required exact historical receipt fixture drift' }
    $f=[Text.Encoding]::UTF8.GetString($fixtureRaw)|ConvertFrom-Json
    if ($f.schema -ne 1 -or $f.cards.Count -ne 8 -or $f.authority.Records.Count -ne 7) { throw 'Required historical receipt fixture shape' }
    $authority=$f.authority
    $target=@($authority.Records|Where-Object {$_.ModId -ceq 'wt_dev'})[0]
    $planArgs=@{PublishedId='3748824853';NewVersion='0.12.340-dev';LoadTag='wt';NewManifest='6107819185100829061';SharedLoadTag=$true;StreamIdentity='Tweaker: Weapons Dev';SiblingPublishedIds=@('3712896117');SiblingStreamIdentities=@('Tweaker: Weapons');ArtifactTarget=$target;ArtifactTargets=@($authority.Records)}
    $failures=New-Object 'System.Collections.Generic.List[string]'
    $passes=New-Object 'System.Collections.Generic.List[string]'
    function Assert-Receipt($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
    function Case([string]$Name,[scriptblock]$Body) {
        if ($Only -and $Name -cne $Only) { return }
        try { & $Body; $passes.Add($Name); Write-Host ('[PASS] '+$Name) }
        catch { $failures.Add($Name+': '+$_.Exception.Message); Write-Host ('[FAIL] '+$Name+': '+$_) }
    }
    foreach ($row in $f.cards) {
        Case ('historical-'+$row.issue) {
            $p=Get-VtCardRefreshPlan -Body $row.old_body @planArgs
            Assert-Receipt ($p.Status -ceq 'refresh' -and $p.NewBody -ceq $row.expected_body) ('exact historical candidate: '+$p.Status+' '+$p.Reason)
            $decision=Get-VtRefreshedCardAuthorityDecision -Body $p.NewBody -Authority $authority
            Assert-Receipt $decision.Valid ('real final guard: '+($decision.Errors -join ','))
            $again=Get-VtCardRefreshPlan -Body $p.NewBody @planArgs
            Assert-Receipt ($again.Status -ceq 'current' -and $again.NewBody -ceq $p.NewBody) 'idempotence'
        }
    }
    $card=@($f.cards|Where-Object {$_.issue -eq 290})[0]
    $mixed=@($f.cards|Where-Object {$_.issue -eq 321})[0]
    Case 'typed-review-detects-independent-version' {
        $p=Get-VtCardCurrentArtifactReview -Card $card.old_body -Targets $authority.Records
        Assert-Receipt ($p.Status -ceq 'stale' -and $p.NewCard -ceq $card.expected_body -and @($p.Claims|Where-Object {$_.Field -ceq 'version'}).Count -eq 1) 'typed version must be a real claim'
    }
    Case 'allstream-independent-receipt-version' {
        $streams=@($authority.Records|ForEach-Object {
            [pscustomobject]@{ModId=$_.ModId;Directory=$_.Dir;PublishedId=$_.WorkshopId;LoadTag=($_.LoadRoutes[0].Marker -replace '^\[|:LOAD\]$','');Identity=$_.FriendlyName;Version=$_.Version;SourceCommit=$_.SourceCommit;RootBundle=$_.RootBundle;RootBundleSha256=$_.RootBundleSha256;AssetFilename=$_.AssetFilename;AssetSha256=$_.AssetSha256}
        })
        $p=Get-VtAllStreamReconcilePlan -Body $card.old_body -Streams $streams
        Assert-Receipt ($p.Status -ceq 'refresh' -and $p.NewBody -ceq $card.expected_body) 'shared reviewer must also cover all-stream receipt version'
    }
    Case 'absent-version-and-untyped-provenance-unchanged' {
        $body=$card.expected_body.Replace('`v0.12.340-dev`, Workshop','Workshop')+"`n**Evidence:** old v0.12.339-dev. `n**Feature provenance:** v0.12.339-dev; item 3748824853, manifest 4278357008422959585.`n"
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'current' -and $p.NewBody -ceq $body) 'absent/untyped/historical text must remain exact'
    }
    Case 'mixed-build-stale-refuses-receipt-only' {
        $body=$mixed.old_body.Replace('0.12.340-dev','0.12.338-dev')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable' -and $null -eq $p.NewBody) 'stale mixed Build must not acquire receipt-only permission'
    }
    Case 'mixed-no-context-refuses' {
        $argsCopy=@{}+$planArgs; $argsCopy.Remove('ArtifactTargets'); $argsCopy.Remove('ArtifactTarget')
        $p=Get-VtCardRefreshPlan -Body $mixed.old_body @argsCopy
        Assert-Receipt ($p.Status -ceq 'unparseable') 'missing publishing context must retain old refusal'
    }
    Case 'independent-version-no-full-context-refuses' {
        $argsCopy=@{}+$planArgs; $argsCopy.Remove('ArtifactTargets')
        $p=Get-VtCardRefreshPlan -Body $card.old_body @argsCopy
        Assert-Receipt ($p.Status -ceq 'unparseable' -and $null -eq $p.NewBody) 'one owner row is not the full publishing context'
    }
    Case 'mixed-incomplete-context-refuses' {
        $argsCopy=@{}+$planArgs; $owner=$target|ConvertTo-Json -Depth 100|ConvertFrom-Json; $owner.AssetSha256=$null; $argsCopy.ArtifactTarget=$owner
        $p=Get-VtCardRefreshPlan -Body $mixed.old_body @argsCopy
        Assert-Receipt ($p.Status -ceq 'unparseable' -and $null -eq $p.NewBody) 'incomplete publisher context must fail closed'
    }
    Case 'mixed-conflicting-context-refuses' {
        $argsCopy=@{}+$planArgs; $argsCopy.NewVersion='0.12.341-dev'
        $p=Get-VtCardRefreshPlan -Body $mixed.old_body @argsCopy
        Assert-Receipt ($p.Status -ceq 'unparseable') 'publisher version must agree with full record'
    }
    Case 'malformed-matching-publisher-context-refuses' {
        $records=$authority.Records|ConvertTo-Json -Depth 100|ConvertFrom-Json
        $owner=@($records|Where-Object {$_.ModId -ceq 'wt_dev'})[0];$owner.SourceCommit='not-a-git-object'
        $argsCopy=@{}+$planArgs;$argsCopy.ArtifactTargets=@($records);$argsCopy.ArtifactTarget=$owner
        $p=Get-VtCardRefreshPlan -Body $mixed.old_body @argsCopy
        Assert-Receipt ($p.Status -ceq 'unparseable') 'matching malformed owner/record is not complete authority'
    }
    Case 'mixed-missing-routes-refuses' {
        $records=$authority.Records|ConvertTo-Json -Depth 100|ConvertFrom-Json
        @($records|Where-Object {$_.ModId -ceq 'wt_dev'})[0].LoadRoutes=@()
        $argsCopy=@{}+$planArgs; $argsCopy.ArtifactTargets=@($records)
        $p=Get-VtCardRefreshPlan -Body $mixed.old_body @argsCopy
        Assert-Receipt ($p.Status -ceq 'unparseable') 'record identity without actual Build routes cannot authorize'
    }
    Case 'typed-owner-conflict-refuses' {
        $body=$card.old_body.Replace('Current WT receipt','Current Weapon Tweaker receipt')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable') 'exact public qualifier and Dev item must conflict'
    }
    Case 'typed-two-items-refuses' {
        $body=$card.old_body.Replace('manifest `6107819185100829061`','manifest `6107819185100829061`, item `3712896117`')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable') 'two receipt owners cannot acquire single-owner edits'
    }
    Case 'typed-two-versions-refuses' {
        $body=$card.old_body.Replace('`v0.12.339-dev`, Workshop','`v0.12.339-dev` or `v0.12.338-dev`, Workshop')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable') 'conflicting receipt versions must not be swept'
    }
    Case 'typed-unknown-qualifier-without-item-refuses' {
        $body=$card.old_body.Replace('Current WT receipt','Current Unknown Stream receipt').Replace('Workshop item `3748824853`, ','')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable') 'unknown qualifier cannot inherit implicit singleton ownership'
    }
    Case 'shared-runtime-qualifier-without-item-refuses' {
        $body=$card.old_body.Replace('Workshop item `3748824853`, manifest `6107819185100829061`, ','')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable') 'shared runtime tag alone is not an exact stream owner'
    }
    Case 'typed-duplicate-manifest-refuses' {
        $body=$mixed.old_body.Replace('ManifestID `4278357008422959585`','ManifestID `4278357008422959585`; manifest `333333333333333333`')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable') 'multiple manifest tokens on one receipt must not be guessed'
    }
    Case 'sibling-stale-version-refuses' {
        $body=$mixed.old_body.Replace('Tweaker: Weapons public Workshop','Tweaker: Weapons public v0.12.338-beta Workshop')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable') 'publisher must never rewrite stale sibling receipt'
    }
    Case 'unqualified-sole-build-owner-allowed' {
        $body=$card.old_body.Replace('Current WT receipt','Current receipt').Replace('Workshop item `3748824853`, manifest `6107819185100829061`, ','')
        $expected=$body.Replace('`v0.12.339-dev`','`v0.12.340-dev`')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'refresh' -and $p.NewBody -ceq $expected) 'genuine sole Build owner should retain unqualified allowance'
    }
    Case 'current-crlf-byte-shape' {
        $body=$card.expected_body.Replace("`n","`r`n")
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'current' -and $p.NewBody -ceq $body) 'current CRLF shape must be exact'
    }
    Case 'reviewer-unclaimed-owner-edit-refuses' {
        $original=${function:Get-VtCardCurrentArtifactReview}
        try {
            function Get-VtCardCurrentArtifactReview {param($Card,$Targets)
                $r=& $original -Card $Card -Targets $Targets
                $r.Status='stale';$r.NewCard=$r.NewCard.Replace('0.12.340-dev`, Workshop','0.12.340-dev` unauthorized, Workshop');$r.Claims=@()
                return $r
            }
            $p=Get-VtCardRefreshPlan -Body $card.expected_body @planArgs
            Assert-Receipt ($p.Status -ceq 'unparseable' -and $p.Reason -ceq 'publishing-artifact-edit-ownership-unproven') 'changed owned line still needs actual claim ledger'
        }
        finally { Set-Item Function:Get-VtCardCurrentArtifactReview -Value $original }
    }
    # Exact counterfactual from the independent R1 owner-conflict probe.
    $foreignReceiptBody=@'
## CURRENT LIVE TEST

**Build/banner:** Character Weapon Variants v0.1.555-dev; confirm `[cwv:LOAD] v0.1.555-dev`
**Current WT receipt:** Character Weapon Variants `v0.1.554-dev`, Workshop item `3716869446`, manifest `4232052305510707863`, root bundle SHA-256 `3febc34ed25f52f3b79fea27e592c43353e965dff9d90b120b299e53cba49314`.
**Topology:** Solo

1. Run `/cwv_regression_test` and retain the log.

**Expected:** The command reports no new failures.
'@
    $foreignReceiptBody=$foreignReceiptBody.Replace("`r`n","`n")+"`n"
    Case 'r2-shared-runtime-foreign-item-refuses' {
        $owner=@($authority.Records|Where-Object {$_.ModId -ceq 'character_weapon_variants'})[0]
        $line=@($foreignReceiptBody -split "`n"|Where-Object {$_.StartsWith('**Current ')})[0]
        $info=Get-VtCardArtifactLineInfo -Line $line
        $targets=@($authority.Records|ForEach-Object {ConvertTo-VtCardArtifactTarget $_})
        $qualified=@(Get-VtCardReceiptQualifierTargets -LineInfo $info -Targets $targets)
        $review=Get-VtCardCurrentArtifactReview -Card $foreignReceiptBody -Targets $authority.Records
        $plan=Get-VtCardRefreshPlan -Body $foreignReceiptBody -PublishedId $owner.WorkshopId -NewVersion $owner.Version `
            -LoadTag cwv -NewManifest 4232052305510707863 -ArtifactTarget $owner -ArtifactTargets $authority.Records
        Assert-Receipt ($qualified.Count -eq 2 -and @($qualified|Where-Object {$_.ModId -cin @('wt','wt_dev')}).Count -eq 2) 'foreign item must retain actual shared WT conflict owners'
        Assert-Receipt ($review.Status -ceq 'unparseable' -and $plan.Status -ceq 'unparseable' -and $null -eq $plan.NewBody) 'exact foreign-item receipt must not become a CWV repair'
    }
    Case 'r2-final-guard-full-read-conflict' {
        $body=$foreignReceiptBody.Replace('v0.1.554-dev','v0.1.555-dev')
        $decision=Get-VtRefreshedCardAuthorityDecision -Body $body -Authority $authority
        Assert-Receipt (-not $decision.Valid -and @($decision.Errors|Where-Object {$_ -like 'current-artifact-version-owner-conflict:*'}).Count -eq 1) 'real final guard must read shared WT owners beyond selected CWV Build'
    }
    Case 'r2-genuine-wt-dev-item-selected-write' {
        $review=Get-VtCardCurrentArtifactReview -Card $card.old_body -Targets $authority.Records
        $p=Get-VtCardRefreshPlan -Body $card.old_body @planArgs
        Assert-Receipt ($review.Status -ceq 'stale' -and @($review.Claims|Where-Object {$_.Field -ceq 'version' -and $_.Target -ceq 'wt_dev'}).Count -eq 1) 'actual WT Dev item must still disambiguate shared marker'
        Assert-Receipt ($p.Status -ceq 'refresh' -and $p.NewBody -ceq $card.expected_body) 'publisher may change only its exact frozen receipt token'
        Assert-Receipt (Get-VtRefreshedCardAuthorityDecision -Body $p.NewBody -Authority $authority).Valid 'real final guard must retain genuine WT Dev positive'
    }
    Case 'r2-full-read-does-not-widen-command-targets' {
        $body=$foreignReceiptBody.Replace('Current WT receipt','Current Character Weapon Variants receipt').Replace('v0.1.554-dev','v0.1.555-dev')
        Assert-Receipt (Get-VtRefreshedCardAuthorityDecision -Body $body -Authority $authority).Valid 'genuine selected CWV card healthy control'
        $body=$body.Replace('/cwv_regression_test','/wt_regression_test')
        $decision=Get-VtRefreshedCardAuthorityDecision -Body $body -Authority $authority
        Assert-Receipt (-not $decision.Valid -and @($decision.Errors|Where-Object {$_ -match 'command'}).Count -gt 0) 'full artifact read context cannot authorize a nonselected WT command'
    }
    Case 'r2-publisher-still-cannot-repair-sibling' {
        $body=$mixed.old_body.Replace('Tweaker: Weapons public Workshop','Tweaker: Weapons public v0.12.338-beta Workshop')
        $p=Get-VtCardRefreshPlan -Body $body @planArgs
        Assert-Receipt ($p.Status -ceq 'unparseable' -and $null -eq $p.NewBody -and $p.Reason -like 'sibling-current-artifact-drift:*') 'WT Dev publisher cannot acquire stale public receipt edit authority'
    }

    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($RefreshSource,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Actual refresher source parse failure' }
    $loops=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Variable.Extent.Text -ceq '$issueNumber' -and $n.Condition.Extent.Text -ceq '$readyIssues'},$true))
    if ($loops.Count -ne 1) { throw 'Actual installed per-issue loop is not unique' }
    function Invoke-InstalledReceiptLoop([switch]$InvalidStep) {
        $writes=New-Object 'System.Collections.Generic.List[object]'
        $bodies=@{}; foreach($r in $f.cards) {$bodies[[int]$r.issue]=[string]$r.old_body}
        if ($InvalidStep) { $bodies[290]=$bodies[290].Replace('/wt_regression_test','/invented_unregistered_command') }
        function Get-VtIssueStateAndComments {
            param($Owner,$Name,$Number)
            return [pscustomobject]@{State='OPEN';Comments=@([pscustomobject]@{id=('IC_1102_'+$Number);databaseId=$Number;body=$bodies[[int]$Number];isPinned=$true})}
        }
        function Update-VtIssueComment {param($CommentNodeId,$NewBody) $writes.Add([pscustomobject]@{id=$CommentNodeId;body=$NewBody})}
        function Invoke-VtRefreshGraphQl { throw 'No GraphQL route allowed in receipt regression' }
        $readyIssues=if($InvalidStep){@(290)}else{@($f.cards.issue)}
        $repoOwner='offline';$repoName='fixture';$ReconcileAllStreams=$false;$DryRun=$false
        $PublishedId=$planArgs.PublishedId;$NewVersion=$planArgs.NewVersion;$LoadTag=$planArgs.LoadTag;$NewManifest=$planArgs.NewManifest
        $StreamIdentity=$planArgs.StreamIdentity;$sharedLoadTag=$true;$siblingPublishedIds=$planArgs.SiblingPublishedIds;$siblingStreamIdentities=$planArgs.SiblingStreamIdentities
        $sourceAuthority=$authority;$liveTestAuthority=$authority;$currentArtifactTarget=$target;$displayVersion='v0.12.340-dev'
        $summary=@{refreshed=0;current=0;'skipped-unparseable'=0;'skipped-closed'=0;failed=0};$cardsSeen=0;$issuesExamined=0;$exitCode=0
        $null=Invoke-Expression $loops[0].Extent.Text
        return [pscustomobject]@{writes=@($writes.ToArray());summary=$summary;exit=$exitCode}
    }
    Case 'actual-installed-loop-eight-owned-writes' {
        $r=Invoke-InstalledReceiptLoop
        Assert-Receipt ($r.exit -eq 0 -and $r.summary.refreshed -eq 8 -and $r.writes.Count -eq 8) 'actual loop must publish each exact candidate once'
        foreach($row in $f.cards) {
            $write=@($r.writes|Where-Object {$_.id -ceq ('IC_1102_'+$row.issue)})
            Assert-Receipt ($write.Count -eq 1 -and $write[0].body -ceq $row.expected_body) 'complete installed mutation body mismatch'
        }
    }
    Case 'actual-installed-loop-real-guard-denies-invented-step' {
        $r=Invoke-InstalledReceiptLoop -InvalidStep
        Assert-Receipt ($r.exit -eq 1 -and $r.summary.'skipped-unparseable' -eq 1 -and $r.writes.Count -eq 0) 'real final authority must block invented command before mutation'
    }
    if ($Only -and $passes.Count+$failures.Count -ne 1) { throw 'Focused case selection was not exact' }
    return [pscustomobject]@{Passed=$passes.Count;Failed=$failures.Count;Errors=@($failures.ToArray())}
}

try {
    $repoRoot=Split-Path -Parent $PSScriptRoot
    . (Join-Path $repoRoot 'tools/verify/lifecycle_method_policy.ps1')
    . (Join-Path $repoRoot 'tools/ship/load-tag-resolution.ps1')
    $source=[IO.File]::ReadAllText((Join-Path $repoRoot 'tools/ship/refresh-cards.ps1'))
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    if ($errors.Count) { throw 'Actual refresher source parse failure' }
    foreach($statement in $ast.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.FunctionDefinitionAst] -and $statement.Name -ne 'Invoke-RefreshCardsSelfTest') { Invoke-Expression $statement.Extent.Text }
        elseif ($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -cin @('$script:VtSemverPattern','$script:VtAnchorTagPattern')) { Invoke-Expression $statement.Extent.Text }
    }
    $result=Invoke-VtCurrentReceiptTests -FixturePath (Join-Path $PSScriptRoot 'fixtures/live_card_receipts/dev340_historical.json') -RefreshSource $source
    $result|ConvertTo-Json -Depth 5
    if ($result.Failed) { exit 2 }
    Write-Host '[check_live_card_receipts -SelfTest] OK'
    exit 0
}
catch { Write-Host ('[check_live_card_receipts] ERROR: '+$_); exit 2 }
