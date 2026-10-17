[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'tools/ship/workshop-nochange-result.ps1')
$script:cases = 0
function Check($Value, [string]$Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function Copy-Value($Value) {
    [Management.Automation.PSSerializer]::Deserialize(
        [Management.Automation.PSSerializer]::Serialize($Value, 12))
}
function Reject([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { $null = & $Action } catch { $threw = $true }
    Check $threw $Message
}

$commit = '0123456789abcdef0123456789abcdef01234567'
$item = '3712896117'; $manifest = '3147518600098706152'; $zipHash = 'b' * 64
$publication = [ordered]@{
    schema=3;purpose='workshop_upload';repository='Ensrick/vermintide-2-tweaker'
    release_tag='mods-2026-09-20';receipt_asset_name='publication-receipt-weapon_tweaker.json'
    source_commit=$commit;mod='weapon_tweaker';version='0.12.334-beta'
    bundle_files=@([ordered]@{path='0e89c5285caab001.mod_bundle';length=123;sha256=$zipHash;git_blob='a'*40})
    authorization=[ordered]@{mode='hosted_qa'}
}
$publicationBytes = [Text.UTF8Encoding]::new($false).GetBytes(
    ($publication | ConvertTo-Json -Depth 8 -Compress))
$t0 = [datetime]'2026-09-20T12:00:00'; $t1 = [datetime]'2026-09-20T12:01:00'
$transaction = "[2026-09-20 12:00:10] [AppID 552500] Upload starting for workshop item $item by AppID 552500`n" +
    "[2026-09-20 12:00:20] [AppID 552500] No content change detected for item $item`n" +
    "[2026-09-20 12:00:30] [AppID 552500] Upload finished for workshop item $item : OK`n"
$noChange = ConvertFrom-VtWorkshopUploadTransaction $transaction $item $t0 $t1
$responseValue = [ordered]@{response=[ordered]@{result=1;resultcount=1;publishedfiledetails=@([ordered]@{
    publishedfileid=$item;result=1;consumer_app_id=552500;file_size='1341145'
    hcontent_file=$manifest;time_updated=1789361191;title='presentation can vary'
})}}
$responseBytes = [Text.UTF8Encoding]::new($false).GetBytes(
    ($responseValue | ConvertTo-Json -Depth 8 -Compress))
$before = ConvertFrom-VtWorkshopPublishedFileResponse $responseBytes $item ([datetime]'2026-09-20T12:00:00Z')
$after = ConvertFrom-VtWorkshopPublishedFileResponse $responseBytes $item ([datetime]'2026-09-20T12:01:00Z')
$candidate = New-VtWorkshopNoChangeResultCandidate $publicationBytes $noChange 'wt' 'wt.zip' `
    $zipHash $before $after ([datetime]'2026-09-20T12:00:20Z')
$verdict = Test-VtWorkshopNoChangeResultCandidate $candidate $publicationBytes
Check ($verdict.Ok -and -not $verdict.Authenticated -and -not $verdict.MayMutate) `
    'valid NOCHANGE candidate confused binding with authentication'
Check ($candidate.transaction_status -ceq 'NOCHANGE' -and
    $candidate.workshop_id -ceq $item -and $candidate.steam_manifest_id -ceq $manifest) `
    'NOCHANGE candidate lost transaction or Steam coordinates'
Check ($candidate.steam_snapshot_identity_sha256 -ceq $before.identity_sha256 -and
    $candidate.steam_pre_response_sha256 -ceq $before.response_sha256 -and
    $candidate.steam_post_response_sha256 -ceq $after.response_sha256) `
    'NOCHANGE candidate lost enclosing snapshot evidence'
Check ($candidate.candidate_asset_name -ceq
    "workshop-nochange-result-weapon_tweaker-$commit-$($candidate.publication_receipt_sha256).json") `
    'NOCHANGE candidate asset is not source/preauthorization-qualified'

foreach ($row in @(
    @{Field='authenticated';Value=$true},@{Field='transaction_status';Value='UPLOADED'},
    @{Field='workshop_id';Value='0'},@{Field='steam_manifest_id';Value='other'},
    @{Field='source_commit';Value='f'*40},@{Field='mod_id';Value='other'},
    @{Field='publication_receipt_sha256';Value='d'*64},
    @{Field='candidate_asset_name';Value='../result.json'},
    @{Field='recorded_at_utc';Value='2026-09-20T12:00:20.1Z'},
    @{Field='steam_time_updated';Value='0'},@{Field='steam_file_size';Value='-1'},
    @{Field='steam_snapshot_identity_sha256';Value='bad'},@{Field='app_id';Value='480'}
)) {
    $copy = Copy-Value $candidate; $copy.($row.Field) = $row.Value
    Check (-not (Test-VtWorkshopNoChangeResultCandidate $copy $publicationBytes).Ok) `
        ("tampered $($row.Field) accepted")
}
$copy = Copy-Value $candidate; $copy | Add-Member unexpected 'x'
Check (-not (Test-VtWorkshopNoChangeResultCandidate $copy $publicationBytes).Ok) `
    'unknown NOCHANGE result field accepted'
$copy = Copy-Value $candidate; $copy.PSObject.Properties.Remove('steam_post_response_sha256')
Check (-not (Test-VtWorkshopNoChangeResultCandidate $copy $publicationBytes).Ok) `
    'missing NOCHANGE result field accepted'

$changedReceipt = [byte[]]$publicationBytes.Clone()
$changedReceipt[$changedReceipt.Length - 2] = $changedReceipt[$changedReceipt.Length - 2] -bxor 1
Check (-not (Test-VtWorkshopNoChangeResultCandidate $candidate $changedReceipt).Ok) `
    'changed publication bytes retained NOCHANGE authority'
$changedAfter = Copy-Value $after; $changedAfter.hcontent_file = '999999999999999999'
Reject { New-VtWorkshopNoChangeResultCandidate $publicationBytes $noChange 'wt' 'wt.zip' `
    $zipHash $before $changedAfter ([datetime]'2026-09-20T12:00:20Z') } `
    'changed remote ManifestID minted NOCHANGE authority'
$changedAfter = Copy-Value $after; $changedAfter.time_updated = '1789361192'
Reject { New-VtWorkshopNoChangeResultCandidate $publicationBytes $noChange 'wt' 'wt.zip' `
    $zipHash $before $changedAfter ([datetime]'2026-09-20T12:00:20Z') } `
    'changed remote update generation minted NOCHANGE authority'
$forged = Copy-Value $noChange; $forged.Status = 'UPLOADED'; $forged.ManifestId = $manifest
Reject { New-VtWorkshopNoChangeResultCandidate $publicationBytes $forged 'wt' 'wt.zip' `
    $zipHash $before $after ([datetime]'2026-09-20T12:00:20Z') } `
    'UPLOADED transaction entered the NOCHANGE constructor'
Reject { New-VtWorkshopUploadResultCandidate $publicationBytes $noChange 'wt' 'wt.zip' `
    $zipHash ([datetime]'2026-09-20T12:00:20Z') } `
    'NOCHANGE transaction entered the UPLOADED constructor'

# Issue #1667: friends-only NOCHANGE (gut_dev item 3751024698, 2026-09-23 05:05).
# The public endpoint answers result 9 with only publishedfileid, so the content
# snapshot pair cannot exist; the ManifestID comes from the prior UPLOADED chain.
. (Join-Path $root 'tools/ship/workshop-nochange-log-proof.ps1')
$hid = '3751024698'; $hidManifest = '7244323320533321348'
$hidPublication = [ordered]@{
    schema=3;purpose='workshop_upload';repository='Ensrick/vermintide-2-tweaker'
    release_tag='mods-2026-09-23';receipt_asset_name='publication-receipt-gui_tweaker_dev.json'
    source_commit=$commit;mod='gui_tweaker_dev';version='0.2.357-dev'
    bundle_files=@([ordered]@{path='1f2e3d4c5b6a7980.mod_bundle';length=456;sha256=$zipHash;git_blob='c'*40})
    authorization=[ordered]@{mode='hosted_qa'}
}
$hidPublicationBytes = [Text.UTF8Encoding]::new($false).GetBytes(($hidPublication | ConvertTo-Json -Depth 8 -Compress))
$hidTransaction = "[2026-09-23 05:05:46] [AppID 552500] Upload starting for workshop item $hid by AppID 552500`n" +
    "[2026-09-23 05:05:54] [AppID 552500] No content change detected for item $hid`n" +
    "[2026-09-23 05:05:55] [AppID 552500] Upload finished for workshop item $hid : OK`n"
$hidNoChange = ConvertFrom-VtWorkshopUploadTransaction $hidTransaction $hid ([datetime]'2026-09-23T05:05:40') ([datetime]'2026-09-23T05:06:00')
$hidPrefix = "[2026-09-23 03:17:11] [AppID 552500] Upload starting for workshop item $hid by AppID 552500`n" +
    "[2026-09-23 03:17:20] [AppID 552500] Uploaded new content ( ManifestID $hidManifest ) for item $hid.`n" +
    "[2026-09-23 03:17:20] [AppID 552500] Upload finished for workshop item $hid : OK`n"
$hidNoChange | Add-Member -NotePropertyName PriorContent -NotePropertyValue ([pscustomobject]@{
    Ok=$true;Error=$null;Proof=(Get-VtWorkshopPriorContentTransaction -Text $hidPrefix -PublishedId $hid)})
$hiddenBytes = [Text.Encoding]::ASCII.GetBytes(
    '{"response":{"result":1,"resultcount":1,"publishedfiledetails":[{"publishedfileid":"3751024698","result":9}]}}')
$hidBefore = ConvertFrom-VtWorkshopPublishedFileObservation $hiddenBytes $hid ([datetime]'2026-09-23T03:05:40Z')
$hidAfter = ConvertFrom-VtWorkshopPublishedFileObservation $hiddenBytes $hid ([datetime]'2026-09-23T03:06:01Z')
Reject { New-VtWorkshopNoChangeResultCandidate $hidPublicationBytes $hidNoChange 'gut_dev' 'gut_dev.zip' `
    $zipHash $hidBefore $hidAfter ([datetime]'2026-09-23T03:05:54Z') } `
    'not-visible observations entered the public content-snapshot constructor'
$hidCandidate = New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $hidNoChange 'gut_dev' 'gut_dev.zip' `
    $zipHash 'friends_only' $hidBefore $hidAfter ([datetime]'2026-09-23T03:05:54Z')
$hidVerdict = Test-VtWorkshopNoChangeLogResultCandidate $hidCandidate $hidPublicationBytes
Check ($hidVerdict.Ok -and -not $hidVerdict.Authenticated -and -not $hidVerdict.MayMutate) `
    "valid friends-only NOCHANGE candidate failed or claimed authentication: $($hidVerdict.Problems -join '; ')"
Check ($hidCandidate.purpose -ceq 'workshop-nochange-log-result-candidate/v1' -and $hidCandidate.steam_manifest_id -ceq $hidManifest -and
    $hidCandidate.workshop_id -ceq $hid -and $hidCandidate.visibility -ceq 'friends_only' -and
    $hidCandidate.prior_nochange_count -ceq '0' -and $hidCandidate.prior_server_confirmations -ceq '0' -and
    $hidCandidate.steam_pre_response_sha256 -ceq $hidBefore.response_sha256 -and
    $hidCandidate.candidate_asset_name -ceq (Get-VtWorkshopNoChangeResultAssetName 'gui_tweaker_dev' $commit $hidCandidate.publication_receipt_sha256)) `
    'friends-only NOCHANGE candidate lost the prior UPLOADED manifest or its coordinates'
foreach ($row in @(
    @{Field='visibility';Value='public'},@{Field='steam_manifest_id';Value='0'},@{Field='prior_chain_sha256';Value='bad'},
    @{Field='prior_nochange_count';Value='-1'},@{Field='transaction_status';Value='UPLOADED'},@{Field='authenticated';Value=$true},
    @{Field='candidate_asset_name';Value='../result.json'},@{Field='app_id';Value='480'}
)) {
    $copy = Copy-Value $hidCandidate; $copy.($row.Field) = $row.Value
    Check (-not (Test-VtWorkshopNoChangeLogResultCandidate $copy $hidPublicationBytes).Ok) ("tampered friends-only $($row.Field) accepted")
}
$copy = Copy-Value $hidCandidate; $copy | Add-Member unexpected 'x'
Check (-not (Test-VtWorkshopNoChangeLogResultCandidate $copy $hidPublicationBytes).Ok) 'unknown friends-only field accepted'
$copy = Copy-Value $hidCandidate; $copy.PSObject.Properties.Remove('prior_chain_sha256')
Check (-not (Test-VtWorkshopNoChangeLogResultCandidate $copy $hidPublicationBytes).Ok) 'missing friends-only field accepted'
Reject { New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $hidNoChange 'gut_dev' 'gut_dev.zip' `
    $zipHash 'public' $hidBefore $hidAfter } 'public visibility entered the log-bound constructor'
Reject { New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $hidNoChange 'gut_dev' 'gut_dev.zip' `
    $zipHash 'friends_only' $before $after } 'content snapshots entered the log-bound constructor'
$noPrior = Copy-Value $hidNoChange; $noPrior.PSObject.Properties.Remove('PriorContent')
Reject { New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $noPrior 'gut_dev' 'gut_dev.zip' `
    $zipHash 'friends_only' $hidBefore $hidAfter } 'friends-only NOCHANGE without a prior chain minted a ManifestID'
$failedPrior = Copy-Value $hidNoChange; $failedPrior.PriorContent = [pscustomobject]@{Ok=$false;Proof=$null;Error='no complete UPLOADED'}
Reject { New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $failedPrior 'gut_dev' 'gut_dev.zip' `
    $zipHash 'friends_only' $hidBefore $hidAfter } 'unavailable prior chain minted a ManifestID'
foreach ($tamper in @(
    @{Name='manifest';Apply={ param($p) $p.ManifestId = '1444642237709131676' }},
    @{Name='foreign item';Apply={ param($p) $p.PublishedId = '3751024699' }},
    @{Name='chain digest';Apply={ param($p) $p.ChainSha256 = 'a' * 64 }},
    # Finish line, chain line, and chain digest move together, so only the
    # "prior upload finished before this NOCHANGE started" guard can reject it.
    @{Name='later prior upload';Apply={ param($p)
        $late = $p.FinishLine.Replace('03:17:20', '05:06:00')
        $lines = @(@($p.ChainLines) | ForEach-Object { if ([string]$_ -ceq $p.FinishLine) { $late } else { [string]$_ } })
        $p.FinishLine = $late; $p.ChainLines = $lines
        $p.ChainSha256 = Get-VtWorkshopLogProofTextSha256 (($lines -join "`n") + "`n") }}
)) {
    $tampered = Copy-Value $hidNoChange; & $tamper.Apply $tampered.PriorContent.Proof
    Reject { New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $tampered 'gut_dev' 'gut_dev.zip' `
        $zipHash 'friends_only' $hidBefore $hidAfter } ("tampered prior chain $($tamper.Name) minted a ManifestID")
}
# A same-manifest server-change line inside the prior UPLOADED transaction is
# allowed by the parser, so the candidate must bind the same lines around it.
$hidLines = @($hidPrefix.TrimEnd("`n").Split([char]10))
$hidServer = "[2026-09-23 03:17:20] [AppID 552500] Detected workshop change (latest from server) : changed cached item $hid, new manifest $hidManifest"
$interleaved = Copy-Value $hidNoChange
$interleaved.PriorContent.Proof = Get-VtWorkshopPriorContentTransaction -PublishedId $hid -Text (
    ((@($hidLines[0], $hidLines[1], $hidServer, $hidLines[2])) -join "`n") + "`n")
$interleavedCandidate = New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $interleaved 'gut_dev' 'gut_dev.zip' `
    $zipHash 'friends_only' $hidBefore $hidAfter ([datetime]'2026-09-23T03:05:54Z')
Check ($interleavedCandidate.steam_manifest_id -ceq $hidManifest -and $interleavedCandidate.prior_server_confirmations -ceq '1' -and
    $interleavedCandidate.prior_outcome_line_sha256 -ceq (Get-VtWorkshopLogProofTextSha256 $hidLines[1]) -and
    $interleavedCandidate.prior_finish_line_sha256 -ceq (Get-VtWorkshopLogProofTextSha256 $hidLines[2])) `
    'same-manifest server line inside the prior UPLOADED transaction shifted the bound lines'
$foreignHidden = Copy-Value $hidAfter; $foreignHidden.publishedfileid = '3751024699'
Reject { New-VtWorkshopNoChangeLogResultCandidate $hidPublicationBytes $hidNoChange 'gut_dev' 'gut_dev.zip' `
    $zipHash 'friends_only' $hidBefore $foreignHidden } 'foreign not-visible observation minted a ManifestID'

if (-not $Quiet) {
    Write-Host "[check_workshop_nochange_result] PASS $script:cases assertions; NOCHANGE authority requires stable enclosing Steam snapshots."
}
exit 0
