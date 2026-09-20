# Issue #1307: pure Workshop upload-result candidate contract.
# The candidate is not authenticated until a future trusted append-only release
# owner stores and rereads its exact bytes. This file performs no I/O writes.
. (Join-Path $PSScriptRoot 'workshop-upload-evidence.ps1')

$script:VtWorkshopResultPurpose='workshop-upload-result-candidate/v1'
$script:VtWorkshopResultFields=@(
    'schema','purpose','authenticated','repository','release_tag','candidate_asset_name',
    'recorded_at_utc','source_commit','mod','mod_id','version','workshop_id',
    'steam_manifest_id','app_id','publication_receipt_asset_name',
    'publication_receipt_sha256','release_asset_name','release_asset_sha256',
    'transaction_evidence_sha256','start_line_sha256','outcome_line_sha256','finish_line_sha256'
)

function Get-VtWorkshopResultPropertyNames($Value) {
    if($Value -is [Collections.IDictionary]){return @($Value.Keys|ForEach-Object{[string]$_})}
    return @($Value.PSObject.Properties|ForEach-Object{[string]$_.Name})
}
function Get-VtWorkshopResultProperty($Value,[string]$Name) {
    if($Value -is [Collections.IDictionary]){
        foreach($key in $Value.Keys){if([string]$key -ceq $Name){return $Value[$key]}}
        return $null
    }
    $property=@($Value.PSObject.Properties|Where-Object{$_.Name -ceq $Name})
    if($property.Count -ne 1){return $null};return $property[0].Value
}
function Get-VtWorkshopResultByteSha256([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()}
    finally{$sha.Dispose()}
}
function ConvertFrom-VtWorkshopPublicationReceiptBytes([byte[]]$Bytes) {
    if($null -eq $Bytes -or $Bytes.Length -eq 0 -or $Bytes.Length -gt 4194304){throw 'publication receipt bytes are empty or oversized'}
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    try{$json=$utf8.GetString($Bytes)}catch{throw 'publication receipt is not strict UTF-8'}
    foreach($field in @('schema','purpose','repository','release_tag','receipt_asset_name','source_commit','mod','version','bundle_files','authorization')){
        $matches=[regex]::Matches($json,'"'+[regex]::Escape($field)+'"\s*:')
        if($matches.Count -ne 1){throw "publication receipt field '$field' is missing, duplicated, escaped, or nested ambiguously"}
    }
    try{$receipt=$json|ConvertFrom-Json -ErrorAction Stop}catch{throw 'publication receipt is not valid JSON'}
    if($null -eq $receipt -or $receipt -is [Array] -or $receipt.schema -ne 3 -or
            $receipt.purpose -cne 'workshop_upload' -or $receipt.repository -cne 'Ensrick/vermintide-2-tweaker' -or
            [string]$receipt.authorization.mode -cne 'hosted_qa'){
        throw 'publication receipt has no trusted schema-3 upload authorization shape'
    }
    foreach($field in @('release_tag','receipt_asset_name','source_commit','mod','version')){
        if($receipt.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($receipt.$field)){throw "publication receipt $field is unavailable"}
    }
    if($receipt.release_tag -cnotmatch '^mods-[0-9]{4}-[0-9]{2}-[0-9]{2}$' -or
            $receipt.receipt_asset_name -cne ('publication-receipt-'+$receipt.mod+'.json') -or
            $receipt.source_commit -cnotmatch '^[0-9a-f]{40}$' -or $receipt.mod -cnotmatch '^[a-z][a-z0-9_]*$' -or
            $receipt.version -cnotmatch '^[0-9]+(?:\.[0-9]+){2,}(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$'){
        throw 'publication receipt coordinates are noncanonical'
    }
    $bundles=@($receipt.bundle_files)
    if($bundles.Count -eq 0 -or $bundles.Count -gt 64){throw 'publication receipt bundle inventory is empty or oversized'}
    $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($bundle in $bundles){
        if($bundle.path -isnot [string] -or $bundle.path -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$' -or
                $bundle.sha256 -isnot [string] -or $bundle.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
                -not$seen.Add($bundle.path)){throw 'publication receipt bundle inventory is malformed or ambiguous'}
    }
    return [pscustomobject]@{Receipt=$receipt;Sha256=(Get-VtWorkshopResultByteSha256 $Bytes);Bytes=$Bytes}
}
function Get-VtWorkshopUploadResultAssetName([string]$Mod,[string]$SourceCommit,[string]$PublicationReceiptSha256) {
    if($Mod -cnotmatch '^[a-z][a-z0-9_]*$' -or $SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
            $PublicationReceiptSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'upload-result asset coordinates are noncanonical'}
    return "workshop-upload-result-$Mod-$SourceCommit-$PublicationReceiptSha256.json"
}

function Test-VtWorkshopUploadResultCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Candidate,[Parameter(Mandatory)][byte[]]$PublicationReceiptBytes)
    $problems=New-Object 'Collections.Generic.List[string]'
    try{$publication=ConvertFrom-VtWorkshopPublicationReceiptBytes $PublicationReceiptBytes}catch{$problems.Add($_.Exception.Message);return [pscustomobject]@{Ok=$false;Problems=$problems.ToArray();Authenticated=$false;MayMutate=$false}}
    $names=@(Get-VtWorkshopResultPropertyNames $Candidate)
    foreach($field in $script:VtWorkshopResultFields){if($names -cnotcontains $field){$problems.Add("missing exact field $field")}}
    foreach($name in $names){if($script:VtWorkshopResultFields -cnotcontains $name){$problems.Add("unexpected field $name")}}
    $v=@{};foreach($field in $script:VtWorkshopResultFields){$v[$field]=Get-VtWorkshopResultProperty $Candidate $field}
    if(($v.schema -isnot [int] -and $v.schema -isnot [long]) -or $v.schema -ne 1){$problems.Add('schema must be integer 1')}
    if($v.purpose -cne $script:VtWorkshopResultPurpose){$problems.Add('purpose mismatch')}
    if($v.authenticated -isnot [bool] -or $v.authenticated){$problems.Add('candidate cannot claim authentication')}
    foreach($field in $script:VtWorkshopResultFields|Where-Object{$_ -notin @('schema','authenticated')}){
        if($v[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($v[$field])){$problems.Add("$field must be one nonempty JSON string")}
    }
    $p=$publication.Receipt
    foreach($pair in @(@('repository','repository'),@('release_tag','release_tag'),@('source_commit','source_commit'),
            @('mod','mod'),@('version','version'),@('publication_receipt_asset_name','receipt_asset_name'))){
        if([string]$v[$pair[0]] -cne [string]$p.($pair[1])){$problems.Add("$($pair[0]) does not match exact publication receipt")}
    }
    if($v.publication_receipt_sha256 -cne $publication.Sha256){$problems.Add('publication receipt digest mismatch')}
    $bundles=@($p.bundle_files|Where-Object{$_.path -ceq $v.release_asset_name})
    if($bundles.Count -ne 1 -or [string]$bundles[0].sha256 -cne [string]$v.release_asset_sha256){$problems.Add('release asset is not the exact publication output')}
    foreach($field in @('workshop_id','steam_manifest_id','app_id')){
        [uint64]$id=0;if($v[$field] -cnotmatch '^[1-9][0-9]*$' -or -not[uint64]::TryParse($v[$field],[ref]$id)){$problems.Add("$field is not a canonical UInt64")}
    }
    if($v.mod_id -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$'){$problems.Add('mod_id is noncanonical')}
    elseif($v.release_asset_name -cne ($v.mod_id+'.zip')){$problems.Add('release asset name does not match mod_id')}
    if($v.app_id -cne '552500'){$problems.Add('app_id is not Vermintide 2')}
    foreach($field in @('publication_receipt_sha256','release_asset_sha256','transaction_evidence_sha256','start_line_sha256','outcome_line_sha256','finish_line_sha256')){
        if($v[$field] -cnotmatch '^[0-9a-f]{64}$'){$problems.Add("$field is not lowercase SHA-256")}
    }
    $expectedAsset=$null;try{$expectedAsset=Get-VtWorkshopUploadResultAssetName $v.mod $v.source_commit $v.publication_receipt_sha256}catch{$problems.Add($_.Exception.Message)}
    if($expectedAsset -and $v.candidate_asset_name -cne $expectedAsset){$problems.Add('candidate asset name mismatch')}
    $time=[datetime]::MinValue
    if(-not[datetime]::TryParseExact($v.recorded_at_utc,'yyyy-MM-ddTHH:mm:ssZ',[cultureinfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,[ref]$time)){$problems.Add('recorded_at_utc is not canonical whole-second UTC')}
    return [pscustomobject]@{Ok=($problems.Count -eq 0);Problems=$problems.ToArray();Authenticated=$false;MayMutate=$false}
}

function New-VtWorkshopUploadResultCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$PublicationReceiptBytes,[Parameter(Mandatory)]$UploadResult,
        [Parameter(Mandatory)][string]$ModId,[Parameter(Mandatory)][string]$ReleaseAssetName,
        [Parameter(Mandatory)][string]$ReleaseAssetSha256,[datetime]$RecordedAtUtc=([datetime]::UtcNow))
    $publication=ConvertFrom-VtWorkshopPublicationReceiptBytes $PublicationReceiptBytes;$p=$publication.Receipt
    if($ModId -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$'){throw 'mod_id is noncanonical'}
    if($UploadResult.Schema -ne 1 -or $UploadResult.Status -cne 'UPLOADED' -or $UploadResult.AppId -cne '552500' -or
            $UploadResult.PublishedId -cnotmatch '^[1-9][0-9]*$' -or $UploadResult.ManifestId -cnotmatch '^[1-9][0-9]*$' -or
            $UploadResult.EvidenceTextSha256 -cnotmatch '^[0-9a-f]{64}$'){throw 'only one validated schema-1 UPLOADED transaction can create a result candidate'}
    $start="Upload starting for workshop item $($UploadResult.PublishedId) by AppID 552500"
    $outcome="Uploaded new content \( ManifestID $($UploadResult.ManifestId) \) for item $($UploadResult.PublishedId)\."
    $finish="Upload finished for workshop item $($UploadResult.PublishedId) : OK"
    if($UploadResult.StartLine -cnotmatch ('^\[[^]]+\] \[AppID 552500\] '+[regex]::Escape($start)+'$') -or
            $UploadResult.OutcomeLine -cnotmatch ('^\[[^]]+\] \[AppID 552500\] '+$outcome+'$') -or
            $UploadResult.FinishLine -cnotmatch ('^\[[^]]+\] \[AppID 552500\] '+[regex]::Escape($finish)+'$')){throw 'validated upload result lines do not bind the selected item and manifest'}
    $recorded=$RecordedAtUtc.ToUniversalTime().AddTicks(-($RecordedAtUtc.ToUniversalTime().Ticks%[TimeSpan]::TicksPerSecond))
    $result=[ordered]@{
        schema=1;purpose=$script:VtWorkshopResultPurpose;authenticated=$false;repository=[string]$p.repository;release_tag=[string]$p.release_tag
        candidate_asset_name=(Get-VtWorkshopUploadResultAssetName $p.mod $p.source_commit $publication.Sha256)
        recorded_at_utc=$recorded.ToString('yyyy-MM-ddTHH:mm:ssZ',[cultureinfo]::InvariantCulture)
        source_commit=[string]$p.source_commit;mod=[string]$p.mod;mod_id=$ModId;version=[string]$p.version
        workshop_id=[string]$UploadResult.PublishedId;steam_manifest_id=[string]$UploadResult.ManifestId;app_id='552500'
        publication_receipt_asset_name=[string]$p.receipt_asset_name;publication_receipt_sha256=$publication.Sha256
        release_asset_name=$ReleaseAssetName;release_asset_sha256=$ReleaseAssetSha256;transaction_evidence_sha256=[string]$UploadResult.EvidenceTextSha256
        start_line_sha256=(Get-VtWorkshopEvidenceSha256 $UploadResult.StartLine);outcome_line_sha256=(Get-VtWorkshopEvidenceSha256 $UploadResult.OutcomeLine)
        finish_line_sha256=(Get-VtWorkshopEvidenceSha256 $UploadResult.FinishLine)
    }
    $verdict=Test-VtWorkshopUploadResultCandidate ([pscustomobject]$result) $PublicationReceiptBytes
    if(-not$verdict.Ok){throw ('invalid upload-result candidate: '+($verdict.Problems -join '; '))}
    return [pscustomobject]$result
}
