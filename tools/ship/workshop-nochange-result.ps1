# Issue #1307: pure NOCHANGE result candidate.  A ManifestID is accepted only
# when one exact bounded no-change transaction is enclosed by unchanged Steam
# published-file snapshots.  Authentication still requires append + reread.
. (Join-Path $PSScriptRoot 'workshop-upload-result.ps1')
. (Join-Path $PSScriptRoot 'workshop-published-file-snapshot.ps1')

$script:VtWorkshopNoChangePurpose = 'workshop-nochange-result-candidate/v1'
$script:VtWorkshopNoChangeFields = @(
    'schema','purpose','authenticated','repository','release_tag','candidate_asset_name',
    'recorded_at_utc','source_commit','mod','mod_id','version','transaction_status',
    'workshop_id','steam_manifest_id','app_id','publication_receipt_asset_name',
    'publication_receipt_sha256','release_asset_name','release_asset_sha256',
    'transaction_evidence_sha256','start_line_sha256','outcome_line_sha256','finish_line_sha256',
    'steam_time_updated','steam_file_size','steam_snapshot_identity_sha256',
    'steam_pre_response_sha256','steam_post_response_sha256'
)

function Get-VtWorkshopNoChangeResultAssetName {
    param(
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)][string]$SourceCommit,
        [Parameter(Mandatory = $true)][string]$PublicationReceiptSha256
    )
    if ($Mod -cnotmatch '^[a-z][a-z0-9_]*$' -or $SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
            $PublicationReceiptSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'no-change result asset coordinates are noncanonical'
    }
    return "workshop-nochange-result-$Mod-$SourceCommit-$PublicationReceiptSha256.json"
}

function Test-VtWorkshopNoChangeResultCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)][byte[]]$PublicationReceiptBytes
    )
    $problems = New-Object 'Collections.Generic.List[string]'
    try { $publication = ConvertFrom-VtWorkshopPublicationReceiptBytes $PublicationReceiptBytes }
    catch {
        $problems.Add($_.Exception.Message)
        return [pscustomobject]@{Ok=$false;Problems=$problems.ToArray();Authenticated=$false;MayMutate=$false}
    }
    $names = @(Get-VtWorkshopResultPropertyNames $Candidate)
    foreach ($field in $script:VtWorkshopNoChangeFields) {
        if ($names -cnotcontains $field) { $problems.Add("missing exact field $field") }
    }
    foreach ($name in $names) {
        if ($script:VtWorkshopNoChangeFields -cnotcontains $name) { $problems.Add("unexpected field $name") }
    }
    $v = @{}
    foreach ($field in $script:VtWorkshopNoChangeFields) {
        $v[$field] = Get-VtWorkshopResultProperty $Candidate $field
    }
    if (($v.schema -isnot [int] -and $v.schema -isnot [long]) -or $v.schema -ne 1) {
        $problems.Add('schema must be integer 1')
    }
    if ($v.purpose -cne $script:VtWorkshopNoChangePurpose) { $problems.Add('purpose mismatch') }
    if ($v.authenticated -isnot [bool] -or $v.authenticated) {
        $problems.Add('candidate cannot claim authentication')
    }
    foreach ($field in $script:VtWorkshopNoChangeFields | Where-Object { $_ -notin @('schema','authenticated') }) {
        if ($v[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($v[$field])) {
            $problems.Add("$field must be one nonempty JSON string")
        }
    }
    $receipt = $publication.Receipt
    foreach ($pair in @(
        @('repository','repository'),@('release_tag','release_tag'),@('source_commit','source_commit'),
        @('mod','mod'),@('version','version'),@('publication_receipt_asset_name','receipt_asset_name')
    )) {
        if ([string]$v[$pair[0]] -cne [string]$receipt.($pair[1])) {
            $problems.Add("$($pair[0]) does not match exact publication receipt")
        }
    }
    if ($v.publication_receipt_sha256 -cne $publication.Sha256) {
        $problems.Add('publication receipt digest mismatch')
    }
    # bundle_files lists staged Workshop bundles, never the GitHub release zip; the zip name is bound to
    # mod_id above and its digest to the hosted release manifest by the release owner (#1307 follow-up).
    if ($v.release_asset_sha256 -cnotmatch '^[0-9a-f]{64}$') {
        $problems.Add('release asset digest is noncanonical')
    }
    foreach ($field in @('workshop_id','steam_manifest_id','app_id','steam_time_updated')) {
        [uint64]$id = 0
        if ($v[$field] -cnotmatch '^[1-9][0-9]*$' -or
                -not [uint64]::TryParse($v[$field], [Globalization.NumberStyles]::None,
                    [cultureinfo]::InvariantCulture, [ref]$id)) {
            $problems.Add("$field is not a canonical positive UInt64")
        }
    }
    [uint64]$size = 0
    if ($v.steam_file_size -cnotmatch '^(0|[1-9][0-9]*)$' -or
            -not [uint64]::TryParse($v.steam_file_size, [Globalization.NumberStyles]::None,
                [cultureinfo]::InvariantCulture, [ref]$size)) {
        $problems.Add('steam_file_size is not a canonical UInt64')
    }
    if ($v.mod_id -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$') { $problems.Add('mod_id is noncanonical') }
    elseif ($v.release_asset_name -cne ($v.mod_id + '.zip')) {
        $problems.Add('release asset name does not match mod_id')
    }
    if ($v.app_id -cne '552500') { $problems.Add('app_id is not Vermintide 2') }
    if ($v.transaction_status -cne 'NOCHANGE') { $problems.Add('transaction_status is not NOCHANGE') }
    foreach ($field in @(
        'publication_receipt_sha256','release_asset_sha256','transaction_evidence_sha256',
        'start_line_sha256','outcome_line_sha256','finish_line_sha256',
        'steam_snapshot_identity_sha256','steam_pre_response_sha256','steam_post_response_sha256'
    )) {
        if ($v[$field] -cnotmatch '^[0-9a-f]{64}$') { $problems.Add("$field is not lowercase SHA-256") }
    }
    $expectedAsset = $null
    try {
        $expectedAsset = Get-VtWorkshopNoChangeResultAssetName $v.mod $v.source_commit `
            $v.publication_receipt_sha256
    }
    catch { $problems.Add($_.Exception.Message) }
    if ($expectedAsset -and $v.candidate_asset_name -cne $expectedAsset) {
        $problems.Add('candidate asset name mismatch')
    }
    [datetime]$time = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($v.recorded_at_utc, 'yyyy-MM-ddTHH:mm:ssZ',
            [cultureinfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$time)) {
        $problems.Add('recorded_at_utc is not canonical whole-second UTC')
    }
    return [pscustomobject]@{
        Ok=($problems.Count -eq 0);Problems=$problems.ToArray();Authenticated=$false;MayMutate=$false
    }
}

function New-VtWorkshopNoChangeResultCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$PublicationReceiptBytes,
        [Parameter(Mandatory = $true)]$UploadResult,
        [Parameter(Mandatory = $true)][string]$ModId,
        [Parameter(Mandatory = $true)][string]$ReleaseAssetName,
        [Parameter(Mandatory = $true)][string]$ReleaseAssetSha256,
        [Parameter(Mandatory = $true)]$BeforeSnapshot,
        [Parameter(Mandatory = $true)]$AfterSnapshot,
        [datetime]$RecordedAtUtc = ([datetime]::UtcNow)
    )
    $publication = ConvertFrom-VtWorkshopPublicationReceiptBytes $PublicationReceiptBytes
    $receipt = $publication.Receipt
    if ($ModId -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$') { throw 'mod_id is noncanonical' }
    if ($UploadResult.Schema -ne 1 -or $UploadResult.Status -cne 'NOCHANGE' -or
            $UploadResult.AppId -cne '552500' -or
            $UploadResult.PublishedId -cnotmatch '^[1-9][0-9]*$' -or
            $null -ne $UploadResult.ManifestId -or
            $UploadResult.EvidenceTextSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'only one validated schema-1 NOCHANGE transaction can create a no-change result candidate'
    }
    $pair = Test-VtWorkshopPublishedFileSnapshotPair $BeforeSnapshot $AfterSnapshot `
        $UploadResult.PublishedId
    if (-not $pair.Ok) {
        throw ('Steam published-file snapshot pair is not stable: ' + ($pair.Problems -join '; '))
    }
    $item = [string]$UploadResult.PublishedId
    $start = "Upload starting for workshop item $item by AppID 552500"
    $outcome = "No content change detected for item $item"
    $finish = "Upload finished for workshop item $item : OK"
    if ($UploadResult.StartLine -cnotmatch ('^\[[^]]+\] \[AppID 552500\] ' + [regex]::Escape($start) + '$') -or
            $UploadResult.OutcomeLine -cnotmatch ('^\[[^]]+\] \[AppID 552500\] ' + [regex]::Escape($outcome) + '$') -or
            $UploadResult.FinishLine -cnotmatch ('^\[[^]]+\] \[AppID 552500\] ' + [regex]::Escape($finish) + '$')) {
        throw 'validated NOCHANGE result lines do not bind the selected item'
    }
    $recorded = $RecordedAtUtc.ToUniversalTime().AddTicks(
        -($RecordedAtUtc.ToUniversalTime().Ticks % [TimeSpan]::TicksPerSecond))
    $candidate = [ordered]@{
        schema=1;purpose=$script:VtWorkshopNoChangePurpose;authenticated=$false
        repository=[string]$receipt.repository;release_tag=[string]$receipt.release_tag
        candidate_asset_name=(Get-VtWorkshopNoChangeResultAssetName $receipt.mod $receipt.source_commit $publication.Sha256)
        recorded_at_utc=$recorded.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        source_commit=[string]$receipt.source_commit;mod=[string]$receipt.mod;mod_id=$ModId
        version=[string]$receipt.version;transaction_status='NOCHANGE';workshop_id=$item
        steam_manifest_id=[string]$BeforeSnapshot.hcontent_file;app_id='552500'
        publication_receipt_asset_name=[string]$receipt.receipt_asset_name
        publication_receipt_sha256=$publication.Sha256;release_asset_name=$ReleaseAssetName
        release_asset_sha256=$ReleaseAssetSha256
        transaction_evidence_sha256=[string]$UploadResult.EvidenceTextSha256
        start_line_sha256=(Get-VtWorkshopEvidenceSha256 $UploadResult.StartLine)
        outcome_line_sha256=(Get-VtWorkshopEvidenceSha256 $UploadResult.OutcomeLine)
        finish_line_sha256=(Get-VtWorkshopEvidenceSha256 $UploadResult.FinishLine)
        steam_time_updated=[string]$BeforeSnapshot.time_updated
        steam_file_size=[string]$BeforeSnapshot.file_size
        steam_snapshot_identity_sha256=[string]$BeforeSnapshot.identity_sha256
        steam_pre_response_sha256=[string]$BeforeSnapshot.response_sha256
        steam_post_response_sha256=[string]$AfterSnapshot.response_sha256
    }
    $value = [pscustomobject]$candidate
    $verdict = Test-VtWorkshopNoChangeResultCandidate $value $PublicationReceiptBytes
    if (-not $verdict.Ok) {
        throw ('invalid no-change result candidate: ' + ($verdict.Problems -join '; '))
    }
    return $value
}
