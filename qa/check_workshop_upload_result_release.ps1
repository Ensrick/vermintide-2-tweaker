[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'tools/ship/workshop-upload-result-release.ps1')
$script:cases = 0
function Check($Value, [string]$Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function Copy-Value($Value) { [Management.Automation.PSSerializer]::Deserialize([Management.Automation.PSSerializer]::Serialize($Value, 12)) }

$commit = '0123456789abcdef0123456789abcdef01234567'
$item = '3712896117'; $manifest = '6852607942336154153'; $zipHash = 'b' * 64
$publication = [ordered]@{
    schema=3; purpose='workshop_upload'; repository='Ensrick/vermintide-2-tweaker'; release_tag='mods-2026-09-20'
    receipt_asset_name='publication-receipt-weapon_tweaker.json'; source_commit=$commit; mod='weapon_tweaker'
    version='0.12.334-beta'; bundle_files=@([ordered]@{path='wt.zip';length=123;sha256=$zipHash;git_blob='a'*40})
    authorization=[ordered]@{mode='hosted_qa'}
}
$publicationBytes = [Text.UTF8Encoding]::new($false).GetBytes(($publication | ConvertTo-Json -Depth 8 -Compress))
$text = "[2026-07-13 11:59:20] [AppID 552500] Upload starting for workshop item $item by AppID 552500`n[2026-07-13 11:59:24] [AppID 552500] Uploaded new content ( ManifestID $manifest ) for item $item.`n[2026-07-13 11:59:54] [AppID 552500] Upload finished for workshop item $item : OK`n"
$startLocal = [datetime]::SpecifyKind(([datetime]'2026-07-13T11:59:20'), [DateTimeKind]::Local)
$endLocal = [datetime]::SpecifyKind(([datetime]'2026-07-13T11:59:55'), [DateTimeKind]::Local)
$upload = ConvertFrom-VtWorkshopUploadTransaction $text $item $startLocal $endLocal
$candidate = New-VtWorkshopUploadResultCandidate $publicationBytes $upload 'wt' 'wt.zip' $zipHash ([datetime]'2026-09-20T12:34:56Z')
$candidateBytes = ConvertTo-VtWorkshopUploadResultCandidateBytes $candidate $publicationBytes
$noChangeText = $text.Replace(
    "Uploaded new content ( ManifestID $manifest ) for item $item.",
    "No content change detected for item $item")
$noChange = ConvertFrom-VtWorkshopUploadTransaction $noChangeText $item $startLocal $endLocal
$steamValue = [ordered]@{response=[ordered]@{result=1;resultcount=1;publishedfiledetails=@([ordered]@{
    publishedfileid=$item;result=1;consumer_app_id=552500;file_size='123'
    hcontent_file=$manifest;time_updated=1789361191
})}}
$steamBytes = [Text.UTF8Encoding]::new($false).GetBytes(
    ($steamValue | ConvertTo-Json -Depth 8 -Compress))
$beforeSnapshot = ConvertFrom-VtWorkshopPublishedFileResponse $steamBytes $item ([datetime]'2026-09-20T12:00:00Z')
$afterSnapshot = ConvertFrom-VtWorkshopPublishedFileResponse $steamBytes $item ([datetime]'2026-09-20T12:01:00Z')
$noChangeCandidate = New-VtWorkshopNoChangeResultCandidate $publicationBytes $noChange 'wt' 'wt.zip' `
    $zipHash $beforeSnapshot $afterSnapshot ([datetime]'2026-09-20T12:34:56Z')
$noChangeBytes = ConvertTo-VtWorkshopUploadResultCandidateBytes $noChangeCandidate $publicationBytes

function New-FakeReleaseState {
    param(
        [byte[]]$ExistingBytes,
        [switch]$Duplicate,
        [switch]$Draft,
        [switch]$UploadRace,
        [switch]$CorruptReread,
        $CandidateObject = $candidate
    )
    $state = @{
        Repo='Ensrick/vermintide-2-tweaker'; Tag='mods-2026-09-20'; ReleaseId='42'; AssetId='81'
        AssetName=[string]$CandidateObject.candidate_asset_name; Bytes=$ExistingBytes; Posts=0; Gets=0
        Duplicate=[bool]$Duplicate; Draft=[bool]$Draft; UploadRace=[bool]$UploadRace; CorruptReread=[bool]$CorruptReread
    }
    $state.Request = {
        param($Method, $Uri, $Accept, $InputPath, [byte[]]$InputBytes, $ExpectedResponseBytes, $ContentType, $OutputPath)
        if ($Method -ceq 'GET' -and $Uri -match '/releases/tags/') {
            $assets = @()
            if ($null -ne $state.Bytes) {
                $asset = [pscustomobject]@{id=$state.AssetId;name=$state.AssetName;size=[long]$state.Bytes.Length;url="https://api.github.com/repos/$($state.Repo)/releases/assets/$($state.AssetId)"}
                $assets += $asset
                if ($state.Duplicate) { $assets += (Copy-Value $asset) }
            }
            $release = [ordered]@{id=$state.ReleaseId;tag_name=$state.Tag;draft=$state.Draft;prerelease=$false;assets=$assets}
            return [pscustomobject]@{StatusCode=200;Content=($release|ConvertTo-Json -Depth 6 -Compress);Bytes=$null;Error=$null}
        }
        if ($Method -ceq 'POST' -and $Uri -match 'uploads\.github\.com') {
            $state.Posts++
            if ($state.UploadRace) {
                $state.Bytes = [byte[]]$InputBytes.Clone()
                return [pscustomobject]@{StatusCode=422;Content='';Bytes=$null;Error=$null}
            }
            $state.Bytes = [byte[]]$InputBytes.Clone()
            return [pscustomobject]@{StatusCode=201;Content='{}';Bytes=$null;Error=$null}
        }
        if ($Method -ceq 'GET' -and $Uri -match '/releases/assets/') {
            $state.Gets++
            $out = [byte[]]$state.Bytes.Clone()
            if ($state.CorruptReread) { $out[0] = $out[0] -bxor 1 }
            return [pscustomobject]@{StatusCode=200;Content='';Bytes=$out;Error=$null}
        }
        return [pscustomobject]@{StatusCode=500;Content='';Bytes=$null;Error='unexpected fake request'}
    }.GetNewClosure()
    return $state
}

$createdState = New-FakeReleaseState
$created = Publish-VtWorkshopUploadResultCandidate $createdState.Repo $createdState.Tag $candidate $publicationBytes $createdState.Request
Check ($created.Ok -and $created.Authenticated -and $created.MayMutate -and $created.Disposition -ceq 'CreatedAndReread') 'created asset did not become authenticated only after reread'
Check ($createdState.Posts -eq 1 -and $createdState.Gets -eq 1 -and $created.AssetName -ceq $candidate.candidate_asset_name) 'created path did not use one append and one trusted reread'
Check ($created.Candidate.authenticated -eq $false -and $created.AssetSha256 -ceq (Get-VtWorkshopUploadResultBytesSha256 $candidateBytes)) 'authentication wrapper rewrote or mis-hashed immutable candidate bytes'

$existingState = New-FakeReleaseState -ExistingBytes $candidateBytes
$existing = Publish-VtWorkshopUploadResultCandidate $existingState.Repo $existingState.Tag $candidate $publicationBytes $existingState.Request
Check ($existing.Disposition -ceq 'ExistingExact' -and $existingState.Posts -eq 0 -and $existingState.Gets -eq 1) 'exact replay was not idempotent and read-only'

$noChangeState = New-FakeReleaseState -CandidateObject $noChangeCandidate
$noChangeAuthority = Publish-VtWorkshopUploadResultCandidate $noChangeState.Repo $noChangeState.Tag `
    $noChangeCandidate $publicationBytes $noChangeState.Request
Check ($noChangeAuthority.Authenticated -and $noChangeAuthority.MayMutate -and
    $noChangeAuthority.Candidate.transaction_status -ceq 'NOCHANGE' -and
    $noChangeAuthority.Candidate.steam_manifest_id -ceq $manifest) `
    'NOCHANGE candidate did not authenticate only after append + exact reread'
Check ($noChangeState.Posts -eq 1 -and $noChangeState.Gets -eq 1 -and
    $noChangeAuthority.AssetSha256 -ceq (Get-VtWorkshopUploadResultBytesSha256 $noChangeBytes)) `
    'NOCHANGE append/reread used the wrong bytes or boundary count'

$inventoryPath = Join-Path ([IO.Path]::GetTempPath()) ('vt2-result-inventory-' + [guid]::NewGuid().ToString('N') + '.psd1')
try {
    [IO.File]::WriteAllText($inventoryPath,
        "@{ Mods = @(@{ Dir = 'weapon_tweaker'; ModId = 'wt'; WorkshopId = '$item' }) }", [Text.UTF8Encoding]::new($false))
    $shipCreatedState = New-FakeReleaseState
    $shipCreated = Publish-VtShipWorkshopUploadProof $shipCreatedState.Repo $shipCreatedState.Tag `
        'weapon_tweaker' $inventoryPath $publicationBytes $upload $shipCreatedState.Request
    $outcomeLocal = [datetime]::SpecifyKind(([datetime]'2026-07-13T11:59:24'), [DateTimeKind]::Unspecified)
    $expectedRecorded = [DateTimeOffset]::new(
        $outcomeLocal, [TimeZoneInfo]::Local.GetUtcOffset($startLocal)).UtcDateTime.ToString(
            'yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
    Check ($shipCreated.Authenticated -and $shipCreated.Disposition -ceq 'CreatedAndReread' -and
        $shipCreated.Candidate.recorded_at_utc -ceq $expectedRecorded) `
        'ship UPLOADED path did not create authenticated deterministic-time authority'

    $bootstrapPublication = Copy-Value $publication
    $bootstrapPublication.purpose = 'workshop_bootstrap'
    $bootstrapBytes = [Text.UTF8Encoding]::new($false).GetBytes(
        ($bootstrapPublication | ConvertTo-Json -Depth 8 -Compress))
    [IO.File]::WriteAllText($inventoryPath,
        "@{ Mods = @(@{ Dir = 'weapon_tweaker'; ModId = 'wt'; WorkshopId = '' }) }", [Text.UTF8Encoding]::new($false))
    $bootstrapState = New-FakeReleaseState
    $bootstrapDigest = Get-VtWorkshopResultByteSha256 $bootstrapBytes
    $bootstrapState.AssetName = Get-VtWorkshopUploadResultAssetName 'weapon_tweaker' $commit $bootstrapDigest
    $bootstrapProof = Publish-VtShipWorkshopUploadProof $bootstrapState.Repo $bootstrapState.Tag `
        'weapon_tweaker' $inventoryPath $bootstrapBytes $upload $bootstrapState.Request
    Check ($bootstrapProof.Authenticated -and $bootstrapProof.Candidate.workshop_id -ceq $item) `
        'first-upload bootstrap did not retain its assigned positive item result'
    [IO.File]::WriteAllText($inventoryPath,
        "@{ Mods = @(@{ Dir = 'weapon_tweaker'; ModId = 'wt'; WorkshopId = '$item' }) }", [Text.UTF8Encoding]::new($false))

    $shipNoChangeState = New-FakeReleaseState -CandidateObject $noChangeCandidate
    $shipNoChange = Publish-VtShipWorkshopUploadProof $shipNoChangeState.Repo $shipNoChangeState.Tag `
        'weapon_tweaker' $inventoryPath $publicationBytes $noChange $shipNoChangeState.Request `
        $beforeSnapshot $afterSnapshot
    Check ($shipNoChange.Authenticated -and $shipNoChange.MayMutate -and
        $shipNoChange.Candidate.steam_manifest_id -ceq $manifest -and
        $shipNoChange.Candidate.transaction_status -ceq 'NOCHANGE') `
        'ship NOCHANGE path did not consume stable Steam snapshot authority'
    Check ($shipNoChangeState.Posts -eq 1 -and $shipNoChangeState.Gets -eq 1) `
        'ship NOCHANGE path did not append and reread exactly once'

    $changedAfter = Copy-Value $afterSnapshot
    $changedAfter.hcontent_file = '999999999999999999'
    $changedState = New-FakeReleaseState -CandidateObject $noChangeCandidate
    $threw = $false
    try {
        $null = Publish-VtShipWorkshopUploadProof $changedState.Repo $changedState.Tag `
            'weapon_tweaker' $inventoryPath $publicationBytes $noChange $changedState.Request `
            $beforeSnapshot $changedAfter
    } catch { $threw = $true }
    Check ($threw -and $changedState.Posts -eq 0 -and $changedState.Gets -eq 0) `
        'changed Steam snapshot reached GitHub mutation'

    $wrongItem = Copy-Value $upload
    $wrongItem.PublishedId = '3712896118'
    $wrongItemState = New-FakeReleaseState
    $threw = $false
    try {
        $null = Publish-VtShipWorkshopUploadProof $wrongItemState.Repo $wrongItemState.Tag `
            'weapon_tweaker' $inventoryPath $publicationBytes $wrongItem $wrongItemState.Request
    } catch { $threw = $true }
    Check ($threw -and $wrongItemState.Posts -eq 0 -and $wrongItemState.Gets -eq 0) `
        'wrong Workshop item crossed the mod-inventory preflight'
} finally {
    if (Test-Path -LiteralPath $inventoryPath) { Remove-Item -LiteralPath $inventoryPath -Force }
}

$raceState = New-FakeReleaseState -UploadRace
$race = Publish-VtWorkshopUploadResultCandidate $raceState.Repo $raceState.Tag $candidate $publicationBytes $raceState.Request
Check ($race.Disposition -ceq 'ConcurrentExact' -and $raceState.Posts -eq 1 -and $raceState.Gets -eq 1) 'exact concurrent create was not authenticated by reread'

foreach ($case in @(
    @{Name='same-name different bytes';State=(New-FakeReleaseState -ExistingBytes ([byte[]](1,2,3)));Posts=0;Gets=1},
    @{Name='duplicate asset metadata';State=(New-FakeReleaseState -ExistingBytes $candidateBytes -Duplicate);Posts=0;Gets=0},
    @{Name='draft release';State=(New-FakeReleaseState -Draft);Posts=0;Gets=0},
    @{Name='corrupt post-upload reread';State=(New-FakeReleaseState -CorruptReread);Posts=1;Gets=1}
)) {
    $threw = $false
    try { $null = Publish-VtWorkshopUploadResultCandidate $case.State.Repo $case.State.Tag $candidate $publicationBytes $case.State.Request } catch { $threw = $true }
    Check $threw ($case.Name + ' did not fail closed')
    Check ($case.State.Posts -eq $case.Posts -and $case.State.Gets -eq $case.Gets) ($case.Name + ' crossed an unexpected mutation/read boundary')
}

$foreignDestination = New-FakeReleaseState
$threw = $false
try { $null = Publish-VtWorkshopUploadResultCandidate 'Other/repo' $foreignDestination.Tag $candidate $publicationBytes $foreignDestination.Request } catch { $threw = $true }
Check ($threw -and $foreignDestination.Posts -eq 0 -and $foreignDestination.Gets -eq 0) 'foreign destination reached release mutation'

$changedPublication = [byte[]]$publicationBytes.Clone(); $changedPublication[$changedPublication.Length-2] = $changedPublication[$changedPublication.Length-2] -bxor 1
$preflightState = New-FakeReleaseState
$threw = $false
try { $null = Publish-VtWorkshopUploadResultCandidate $preflightState.Repo $preflightState.Tag $candidate $changedPublication $preflightState.Request } catch { $threw = $true }
Check ($threw -and $preflightState.Posts -eq 0 -and $preflightState.Gets -eq 0) 'changed preauthorization bytes reached GitHub transport'

$invalidUtf8 = [byte[]](0xC3,0x28)
$threw = $false
try { $null = ConvertFrom-VtWorkshopUploadResultCandidateBytes $invalidUtf8 $publicationBytes } catch { $threw = $true }
Check $threw 'invalid UTF-8 asset bytes were accepted'
$candidateJson = [Text.UTF8Encoding]::new($false, $true).GetString($candidateBytes)
$duplicateJson = $candidateJson.Replace(
    '"steam_manifest_id":"' + $manifest + '"',
    '"steam_manifest_id":"' + $manifest + '","steam_manifest_id":"' + $manifest + '"')
$duplicateBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($duplicateJson)
$threw = $false
try { $null = ConvertFrom-VtWorkshopUploadResultCandidateBytes $duplicateBytes $publicationBytes } catch { $threw = $true }
Check $threw 'duplicate persisted result field was accepted'
$threw = $false
try { $null = ConvertFrom-VtWorkshopUploadResultCandidateBytes (New-Object byte[] 65537) $publicationBytes } catch { $threw = $true }
Check $threw 'oversized persisted result asset was accepted'

if (-not $Quiet) { Write-Host "[check_workshop_upload_result_release] PASS $script:cases assertions; append-only exact-byte reread is authenticated." }
exit 0
