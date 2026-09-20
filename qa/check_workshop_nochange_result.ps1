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
    bundle_files=@([ordered]@{path='wt.zip';length=123;sha256=$zipHash;git_blob='a'*40})
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
    @{Field='release_asset_sha256';Value='c'*64},@{Field='publication_receipt_sha256';Value='d'*64},
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

if (-not $Quiet) {
    Write-Host "[check_workshop_nochange_result] PASS $script:cases assertions; NOCHANGE authority requires stable enclosing Steam snapshots."
}
exit 0
