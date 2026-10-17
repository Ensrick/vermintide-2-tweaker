[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'tools/ship/workshop-published-file-snapshot.ps1')
$script:cases = 0
function Check($Value, [string]$Message) { if (-not $Value) { throw $Message }; $script:cases++ }
function Reject([scriptblock]$Action, [string]$Message) {
    $threw = $false
    try { $null = & $Action } catch { $threw = $true }
    Check $threw $Message
}
function Copy-Snapshot($Value) {
    [Management.Automation.PSSerializer]::Deserialize(
        [Management.Automation.PSSerializer]::Serialize($Value, 8))
}

$item = '3712896117'; $manifest = '3147518600098706152'
function New-ResponseBytes {
    param(
        [string]$PublishedId = $item,
        [string]$Manifest = $manifest,
        [string]$App = '552500',
        [string]$Updated = '1789361191',
        [string]$Size = '1341145',
        [int]$Result = 1,
        [int]$ResultCount = 1,
        [object[]]$Rows
    )
    if ($null -eq $Rows) {
        $Rows = @([ordered]@{
            publishedfileid=$PublishedId;result=$Result;consumer_app_id=[long]$App
            file_size=$Size;hcontent_file=$Manifest;time_updated=[long]$Updated
            title='mutable presentation metadata is intentionally ignored';views=99
        })
    }
    $value = [ordered]@{response=[ordered]@{result=$Result;resultcount=$ResultCount;publishedfiledetails=$Rows}}
    return [Text.UTF8Encoding]::new($false).GetBytes(($value | ConvertTo-Json -Depth 8 -Compress))
}

$bytes = New-ResponseBytes
$snapshot = ConvertFrom-VtWorkshopPublishedFileResponse $bytes $item ([datetime]'2026-09-20T12:00:00Z')
Check ($snapshot.publishedfileid -ceq $item -and $snapshot.consumer_app_id -ceq '552500' -and
    $snapshot.hcontent_file -ceq $manifest -and $snapshot.time_updated -ceq '1789361191' -and
    $snapshot.file_size -ceq '1341145') 'valid response lost the selected Steam identity tuple'
Check ($snapshot.identity_sha256 -cmatch '^[0-9a-f]{64}$' -and
    $snapshot.response_sha256 -ceq (Get-VtWorkshopPublishedFileByteSha256 $bytes) -and
    $snapshot.observed_at_utc -ceq '2026-09-20T12:00:00Z') 'valid response lost exact evidence identity'

$script:requestCalls = 0; $script:requestUri = ''; $script:requestBody = ''
$request = {
    param($Uri, [byte[]]$InputBytes, $ContentType)
    $script:requestCalls++; $script:requestUri = $Uri
    $script:requestBody = [Text.Encoding]::ASCII.GetString($InputBytes)
    return [pscustomobject]@{StatusCode=200;Bytes=$bytes;Error=$null}
}
$queried = Get-VtWorkshopPublishedFileSnapshot $item ([datetime]'2026-09-20T12:00:01Z') $request
Check ($script:requestCalls -eq 1 -and $script:requestUri -ceq $script:VtWorkshopDetailsUri -and
    $script:requestBody -ceq "itemcount=1&publishedfileids%5B0%5D=$item" -and
    $queried.hcontent_file -ceq $manifest) 'lookup did not use one exact credential-free request'

$afterBytes = New-ResponseBytes
$after = ConvertFrom-VtWorkshopPublishedFileResponse $afterBytes $item ([datetime]'2026-09-20T12:10:00Z')
Check (Test-VtWorkshopPublishedFileSnapshotPair $snapshot $after $item).Ok `
    'unchanged selected identity was not accepted across the upload window'
$presentationChanged = [Text.UTF8Encoding]::new($false).GetBytes(
    ([ordered]@{response=[ordered]@{result=1;resultcount=1;publishedfiledetails=@([ordered]@{
        publishedfileid=$item;result=1;consumer_app_id=552500;file_size='1341145'
        hcontent_file=$manifest;time_updated=1789361191;title='changed title';views=100
    })}} | ConvertTo-Json -Depth 8 -Compress))
$afterPresentation = ConvertFrom-VtWorkshopPublishedFileResponse $presentationChanged $item ([datetime]'2026-09-20T12:10:00Z')
Check ((Test-VtWorkshopPublishedFileSnapshotPair $snapshot $afterPresentation $item).Ok -and
    $snapshot.response_sha256 -cne $afterPresentation.response_sha256) `
    'unrelated mutable metadata incorrectly invalidated stable content identity'

foreach ($case in @(
    @{Name='foreign item';Bytes=(New-ResponseBytes -PublishedId '3712896118')},
    @{Name='foreign app';Bytes=(New-ResponseBytes -App '480')},
    @{Name='zero manifest';Bytes=(New-ResponseBytes -Manifest '0')},
    @{Name='overflow manifest';Bytes=(New-ResponseBytes -Manifest '18446744073709551616')},
    @{Name='leading-zero manifest';Bytes=(New-ResponseBytes -Manifest '01')},
    @{Name='failed detail';Bytes=(New-ResponseBytes -Result 9)},
    @{Name='zero details';Bytes=(New-ResponseBytes -ResultCount 0 -Rows @())},
    @{Name='multiple details';Bytes=(New-ResponseBytes -ResultCount 2 -Rows @(
        [ordered]@{publishedfileid=$item;result=1;consumer_app_id=552500;file_size='1';hcontent_file=$manifest;time_updated=1},
        [ordered]@{publishedfileid='3712896118';result=1;consumer_app_id=552500;file_size='1';hcontent_file=$manifest;time_updated=1}
    ))},
    @{Name='invalid UTF-8';Bytes=[byte[]](0xC3,0x28)},
    @{Name='empty';Bytes=[byte[]]@()}
)) {
    Reject { ConvertFrom-VtWorkshopPublishedFileResponse $case.Bytes $item ([datetime]'2026-09-20T12:00:00Z') } `
        ($case.Name + ' response was accepted')
}
$duplicate = [Text.UTF8Encoding]::new($false).GetBytes(
    ([Text.UTF8Encoding]::new($false).GetString($bytes)).Replace(
        '"hcontent_file":"3147518600098706152"',
        '"hcontent_file":"3147518600098706152","hcontent_file":"3147518600098706152"'))
Reject { ConvertFrom-VtWorkshopPublishedFileResponse $duplicate $item ([datetime]'2026-09-20T12:00:00Z') } `
    'duplicated selected field was accepted'
Reject { ConvertFrom-VtWorkshopPublishedFileResponse (New-Object byte[] 1048577) $item ([datetime]'2026-09-20T12:00:00Z') } `
    'oversized response was accepted'

$changed = Copy-Snapshot $after; $changed.hcontent_file = '999999999999999999'
Check (-not (Test-VtWorkshopPublishedFileSnapshotPair $snapshot $changed $item).Ok) `
    'changed manifest was accepted across the upload window'
$changed = Copy-Snapshot $after; $changed.time_updated = '1789361192'
Check (-not (Test-VtWorkshopPublishedFileSnapshotPair $snapshot $changed $item).Ok) `
    'changed update generation was accepted across the upload window'
$changed = Copy-Snapshot $after; $changed.observed_at_utc = '2026-09-20T15:00:01Z'
Check (-not (Test-VtWorkshopPublishedFileSnapshotPair $snapshot $changed $item).Ok) `
    'stale observation window was accepted'
$changed = Copy-Snapshot $after; $changed.observed_at_utc = '2026-09-20T11:59:59Z'
Check (-not (Test-VtWorkshopPublishedFileSnapshotPair $snapshot $changed $item).Ok) `
    'backwards observation window was accepted'

$failedRequest = { [pscustomobject]@{StatusCode=503;Bytes=[byte[]]@();Error='unavailable'} }
Reject { Get-VtWorkshopPublishedFileSnapshot $item ([datetime]'2026-09-20T12:00:00Z') $failedRequest } `
    'failed Steam lookup was accepted'
Reject { Get-VtWorkshopPublishedFileSnapshot '01' ([datetime]'2026-09-20T12:00:00Z') $request } `
    'noncanonical requested item reached transport'

# Issue #1667: the exact 2026-09-23 public answer for friends-only gut_dev item
# 3751024698. The content snapshot rejects it (root cause); the observation owner
# classifies it as a positive not-visible answer for exactly that item.
. (Join-Path $root 'tools/ship/workshop-nochange-log-proof.ps1')
$hiddenItem = '3751024698'
$hiddenBytes = [Text.Encoding]::ASCII.GetBytes(
    '{"response":{"result":1,"resultcount":1,"publishedfiledetails":[{"publishedfileid":"3751024698","result":9}]}}')
$rootCause = $null
try { $null = ConvertFrom-VtWorkshopPublishedFileResponse $hiddenBytes $hiddenItem } catch { $rootCause = $_.Exception.Message }
Check ($rootCause -match "consumer_app_id' is missing") "friends-only answer no longer reproduces the #1667 snapshot failure: $rootCause"
$hidden = ConvertFrom-VtWorkshopPublishedFileObservation $hiddenBytes $hiddenItem ([datetime]'2026-09-23T03:05:40Z')
Check ($hidden.purpose -ceq 'steam-published-file-not-visible/v1' -and $hidden.publishedfileid -ceq $hiddenItem -and
    $hidden.detail_result -ceq '9' -and $hidden.response_sha256 -ceq (Get-VtWorkshopPublishedFileByteSha256 $hiddenBytes) -and
    $hidden.observed_at_utc -ceq '2026-09-23T03:05:40Z') 'friends-only answer was not classified as an exact not-visible observation'
$visible = ConvertFrom-VtWorkshopPublishedFileObservation $bytes $item ([datetime]'2026-09-20T12:00:00Z')
Check ($visible.purpose -ceq 'steam-published-file-snapshot/v1' -and $visible.hcontent_file -ceq $manifest) `
    'visible item lost its content snapshot through the observation owner'
$hiddenText = [Text.Encoding]::ASCII.GetString($hiddenBytes)
foreach ($case in @(
    @{Name='foreign hidden item';Text=$hiddenText.Replace('"3751024698"','"3751024699"')},
    @{Name='other detail result';Text=$hiddenText.Replace('"result":9','"result":2')},
    @{Name='hidden row with content field';Text=$hiddenText.Replace('"result":9','"result":9,"hcontent_file":"1"')},
    @{Name='duplicate hidden item key';Text=$hiddenText.Replace('"publishedfileid":"3751024698"','"publishedfileid":"3751024698","publishedfileid":"3751024698"')},
    @{Name='zero hidden resultcount';Text=$hiddenText.Replace('"resultcount":1','"resultcount":0')},
    @{Name='failed hidden envelope';Text=$hiddenText.Replace('{"result":1,','{"result":2,')},
    @{Name='extra envelope key';Text=$hiddenText.Replace('{"response":','{"extra":0,"response":')}
)) {
    Reject { ConvertFrom-VtWorkshopPublishedFileObservation ([Text.Encoding]::ASCII.GetBytes($case.Text)) $hiddenItem } `
        ($case.Name + ' was accepted as a not-visible observation')
}
$hiddenRequest = { param($Uri, [byte[]]$InputBytes, $ContentType) [pscustomobject]@{StatusCode=200;Bytes=$hiddenBytes;Error=$null} }
$hiddenBefore = Get-VtWorkshopPublishedFileObservation $hiddenItem ([datetime]'2026-09-23T03:05:40Z') $hiddenRequest
$hiddenAfter = Get-VtWorkshopPublishedFileObservation $hiddenItem ([datetime]'2026-09-23T03:06:10Z') $hiddenRequest
Check ((Get-VtWorkshopNoChangeProofBasis $hiddenBefore $hiddenAfter) -ceq 'not-visible' -and
    (Test-VtWorkshopNotVisibleObservationPair $hiddenBefore $hiddenAfter $hiddenItem).Ok) `
    'stable not-visible pair was not accepted across the upload window'
Check ((Get-VtWorkshopNoChangeProofBasis $snapshot $after) -ceq 'snapshot') 'public pair lost its snapshot basis'
Reject { Get-VtWorkshopNoChangeProofBasis $snapshot $hiddenAfter } 'item that turned hidden during the upload kept a proof basis'
Reject { Get-VtWorkshopNoChangeProofBasis $hiddenBefore $after } 'item that turned visible during the upload kept a proof basis'
Check (-not (Test-VtWorkshopNotVisibleObservationPair $hiddenBefore $hiddenAfter '3751024699').Ok) 'foreign not-visible pair accepted'
$staleHidden = Copy-Snapshot $hiddenAfter; $staleHidden.observed_at_utc = '2026-09-23T06:05:41Z'
Check (-not (Test-VtWorkshopNotVisibleObservationPair $hiddenBefore $staleHidden $hiddenItem).Ok) 'stale not-visible window accepted'

if (-not $Quiet) {
    Write-Host "[check_workshop_published_file_snapshot] PASS $script:cases assertions; selected Steam content identity is bounded and read-only."
}
exit 0
