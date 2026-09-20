[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference='Stop';$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'tools/ship/workshop-upload-result.ps1')
$script:cases=0
function Check($Value,[string]$Message){if(-not$Value){throw $Message};$script:cases++}
function Copy-Result($Value){[Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($Value,12))}

$commit='0123456789abcdef0123456789abcdef01234567';$item='3712896117';$manifest='6852607942336154153';$zipHash='b'*64
$publication=[ordered]@{schema=3;purpose='workshop_upload';repository='Ensrick/vermintide-2-tweaker';release_tag='mods-2026-09-20';receipt_asset_name='publication-receipt-weapon_tweaker.json';source_commit=$commit;mod='weapon_tweaker';version='0.12.334-beta';bundle_files=@([ordered]@{path='wt.zip';length=123;sha256=$zipHash;git_blob='a'*40});authorization=[ordered]@{mode='hosted_qa'}}
$publicationBytes=[Text.UTF8Encoding]::new($false).GetBytes(($publication|ConvertTo-Json -Depth 8 -Compress))
$t0=[datetime]'2026-07-13T11:59:20';$t1=[datetime]'2026-07-13T11:59:55'
$text="[2026-07-13 11:59:20] [AppID 552500] Upload starting for workshop item $item by AppID 552500`n[2026-07-13 11:59:24] [AppID 552500] Uploaded new content ( ManifestID $manifest ) for item $item.`n[2026-07-13 11:59:54] [AppID 552500] Upload finished for workshop item $item : OK`n"
$upload=ConvertFrom-VtWorkshopUploadTransaction $text $item $t0 $t1
$candidate=New-VtWorkshopUploadResultCandidate $publicationBytes $upload 'wt' 'wt.zip' $zipHash ([datetime]'2026-09-20T12:34:56Z')
$verdict=Test-VtWorkshopUploadResultCandidate $candidate $publicationBytes
Check ($verdict.Ok -and -not$verdict.Authenticated -and -not$verdict.MayMutate) 'valid candidate confused binding with authentication'
Check ($candidate.recorded_at_utc -ceq '2026-09-20T12:34:56Z' -and $candidate.workshop_id -ceq $item -and $candidate.steam_manifest_id -ceq $manifest) 'constructor lost exact result coordinates'
Check ($candidate.candidate_asset_name -ceq ("workshop-upload-result-weapon_tweaker-$commit-$($candidate.publication_receipt_sha256).json")) 'asset identity is not source/preauthorization-qualified'
$bootstrapPublication=Copy-Result $publication;$bootstrapPublication.purpose='workshop_bootstrap'
$bootstrapBytes=[Text.UTF8Encoding]::new($false).GetBytes(($bootstrapPublication|ConvertTo-Json -Depth 8 -Compress))
$bootstrapCandidate=New-VtWorkshopUploadResultCandidate $bootstrapBytes $upload 'wt' 'wt.zip' $zipHash ([datetime]'2026-09-20T12:34:56Z')
Check (Test-VtWorkshopUploadResultCandidate $bootstrapCandidate $bootstrapBytes).Ok 'first-upload bootstrap receipt cannot retain its assigned-item upload result'
foreach($row in @(@{Field='authenticated';Value=$true},@{Field='workshop_id';Value='0'},@{Field='steam_manifest_id';Value='other'},@{Field='source_commit';Value='f'*40},@{Field='mod_id';Value='other'},@{Field='release_asset_sha256';Value='c'*64},@{Field='publication_receipt_sha256';Value='d'*64},@{Field='candidate_asset_name';Value='../receipt.json'},@{Field='recorded_at_utc';Value='2026-09-20T12:34:56.1Z'},@{Field='app_id';Value='480'})){
    $copy=Copy-Result $candidate;$copy.($row.Field)=$row.Value
    Check (-not(Test-VtWorkshopUploadResultCandidate $copy $publicationBytes).Ok) ("tampered "+$row.Field+' accepted')
}
$copy=Copy-Result $candidate;$copy|Add-Member unexpected 'x';Check (-not(Test-VtWorkshopUploadResultCandidate $copy $publicationBytes).Ok) 'unknown result field accepted'
$copy=Copy-Result $candidate;$copy.PSObject.Properties.Remove('transaction_evidence_sha256');Check (-not(Test-VtWorkshopUploadResultCandidate $copy $publicationBytes).Ok) 'missing result field accepted'
$changed=[byte[]]$publicationBytes.Clone();$changed[$changed.Length-2]=$changed[$changed.Length-2]-bxor 1;Check (-not(Test-VtWorkshopUploadResultCandidate $candidate $changed).Ok) 'changed publication bytes retained authority'
$foreign=Copy-Result $publication;$foreign.bundle_files[0].sha256='c'*64;$foreignBytes=[Text.UTF8Encoding]::new($false).GetBytes(($foreign|ConvertTo-Json -Depth 8 -Compress));Check (-not(Test-VtWorkshopUploadResultCandidate $candidate $foreignBytes).Ok) 'coherently changed publication receipt retained authority'
$nochange=ConvertFrom-VtWorkshopUploadTransaction ($text.Replace("Uploaded new content ( ManifestID $manifest ) for item $item.","No content change detected for item $item")) $item $t0 $t1
$threw=$false;try{$null=New-VtWorkshopUploadResultCandidate $publicationBytes $nochange 'wt' 'wt.zip' $zipHash}catch{$threw=$true};Check $threw 'NOCHANGE minted ManifestID authority'
$forged=Copy-Result $upload;$forged.ManifestId='9999999999999999999';$threw=$false;try{$null=New-VtWorkshopUploadResultCandidate $publicationBytes $forged 'wt' 'wt.zip' $zipHash}catch{$threw=$true};Check $threw 'result object borrowed a different manifest than its exact line'
$threw=$false;try{$null=New-VtWorkshopUploadResultCandidate $publicationBytes $upload '../wt' 'wt.zip' $zipHash}catch{$threw=$true};Check $threw 'constructor accepted a path-like mod_id'
if(-not$Quiet){Write-Host "[check_workshop_upload_result] PASS $script:cases assertions; candidate remains unauthenticated and read-only."};exit 0
