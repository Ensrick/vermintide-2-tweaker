# Issue #1667: NOCHANGE ManifestID proof for non-public Workshop items.
#
# The public GetPublishedFileDetails endpoint answers a friends-only or private
# item with detail result 9 and only publishedfileid (observed 2026-09-23 for
# gut_dev item 3751024698), so the unchanged pre/post content snapshot pair of
# #1307 can never exist for those items and every re-run of an already uploaded
# bundle failed at ship.ps1. For them the ManifestID comes from the Steam client
# log that already authorizes every UPLOADED ManifestID: the item's last
# complete UPLOADED transaction in the verified pre-upload prefix of the SAME
# retained log file, followed only by complete NOCHANGE transactions and
# server-change lines that name the same manifest. Both public observations must
# positively answer "not visible" for exactly this item, and the mod inventory
# and the hosted release manifest row must both record a non-public visibility.
# Public items keep the content snapshot pair. Nothing here reads the previous
# log, a recent-lines tail, or an earlier release asset.
if (-not (Get-Command ConvertFrom-VtWorkshopPublishedFileResponse -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'workshop-published-file-snapshot.ps1')
}

$script:VtWorkshopNotVisiblePurpose = 'steam-published-file-not-visible/v1'
$script:VtWorkshopNonPublicVisibilities = @('friends_only', 'private')
$script:VtWorkshopNoChangeLogPurpose = 'workshop-nochange-log-result-candidate/v1'
$script:VtWorkshopNoChangeLogFields = @(
    'schema','purpose','authenticated','repository','release_tag','candidate_asset_name',
    'recorded_at_utc','source_commit','mod','mod_id','version','transaction_status',
    'workshop_id','steam_manifest_id','app_id','visibility','publication_receipt_asset_name',
    'publication_receipt_sha256','release_asset_name','release_asset_sha256',
    'transaction_evidence_sha256','start_line_sha256','outcome_line_sha256','finish_line_sha256',
    'prior_start_line_sha256','prior_outcome_line_sha256','prior_finish_line_sha256',
    'prior_chain_sha256','prior_nochange_count','prior_server_confirmations',
    'steam_pre_response_sha256','steam_post_response_sha256'
)

function Get-VtWorkshopLogProofTextSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($Text)
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Test-VtWorkshopLogProofUInt64 {
    param([AllowNull()]$Value, [switch]$AllowZero)
    $pattern = if ($AllowZero) { '\A(0|[1-9][0-9]*)\z' } else { '\A[1-9][0-9]*\z' }
    [uint64]$parsed = 0
    return ($Value -is [string] -and $Value -cmatch $pattern -and
        [uint64]::TryParse($Value, [Globalization.NumberStyles]::None, [cultureinfo]::InvariantCulture, [ref]$parsed))
}

function ConvertFrom-VtWorkshopNotVisibleResponse {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$PublishedId,
        [datetime]$ObservedAtUtc = ([datetime]::UtcNow)
    )
    $item = ConvertTo-VtWorkshopCanonicalUInt64Text $PublishedId 'requested publishedfileid'
    if ($Bytes.Length -eq 0 -or $Bytes.Length -gt $script:VtWorkshopDetailsMaxBytes) {
        throw 'Steam published-file response is empty or oversized.'
    }
    try { $json = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes) }
    catch { throw 'Steam published-file response is not strict UTF-8.' }
    # The exact observed shape has six keys: response, result, resultcount,
    # publishedfiledetails, publishedfileid, result. Any content field means the
    # item is visible and must take the snapshot path instead.
    if ([regex]::Matches($json, '"[^"\\]*"\s*:').Count -ne 6 -or
            [regex]::Matches($json, '"result"\s*:').Count -ne 2 -or
            [regex]::Matches($json, '"publishedfileid"\s*:').Count -ne 1) {
        throw 'Steam published-file response is not the exact two-field not-visible shape.'
    }
    try { $decoded = $json | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Steam published-file response is not valid JSON.' }
    $envelope = if ($null -ne $decoded) { $decoded.response } else { $null }
    # Wrap outside the if: an if-statement unrolls a one-row array, and Windows
    # PowerShell 5.1 [pscustomobject] has no intrinsic Count.
    $details = @(if ($null -ne $envelope) { $envelope.publishedfiledetails })
    if ($null -eq $envelope -or $details.Count -ne 1 -or
            ((@($details[0].PSObject.Properties.Name) | Sort-Object) -join ',') -cne 'publishedfileid,result') {
        throw 'Steam published-file response is not the exact two-field not-visible shape.'
    }
    $responseResult = ConvertTo-VtWorkshopCanonicalUInt64Text $envelope.result 'response.result'
    $resultCount = ConvertTo-VtWorkshopCanonicalUInt64Text $envelope.resultcount 'response.resultcount'
    $detailResult = ConvertTo-VtWorkshopCanonicalUInt64Text $details[0].result 'detail.result'
    $detailItem = ConvertTo-VtWorkshopCanonicalUInt64Text $details[0].publishedfileid 'publishedfileid'
    if ($responseResult -cne '1' -or $resultCount -cne '1' -or $detailResult -cne '9' -or $detailItem -cne $item) {
        throw 'Steam published-file response is not a not-visible answer for the requested item.'
    }
    $observed = $ObservedAtUtc.ToUniversalTime().AddTicks(
        -($ObservedAtUtc.ToUniversalTime().Ticks % [TimeSpan]::TicksPerSecond))
    return [pscustomobject][ordered]@{
        schema = 1
        purpose = $script:VtWorkshopNotVisiblePurpose
        publishedfileid = $item
        detail_result = '9'
        response_sha256 = Get-VtWorkshopPublishedFileByteSha256 $Bytes
        observed_at_utc = $observed.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
    }
}

function ConvertFrom-VtWorkshopPublishedFileObservation {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$PublishedId,
        [datetime]$ObservedAtUtc = ([datetime]::UtcNow)
    )
    try { return ConvertFrom-VtWorkshopPublishedFileResponse -Bytes $Bytes -PublishedId $PublishedId -ObservedAtUtc $ObservedAtUtc }
    catch { $snapshotError = $_.Exception.Message }
    try { return ConvertFrom-VtWorkshopNotVisibleResponse -Bytes $Bytes -PublishedId $PublishedId -ObservedAtUtc $ObservedAtUtc }
    catch {
        throw "Steam published-file response is neither a VT2 content snapshot ($snapshotError) nor an exact not-visible answer ($($_.Exception.Message))."
    }
}

function Get-VtWorkshopPublishedFileObservation {
    param(
        [Parameter(Mandatory = $true)][string]$PublishedId,
        [datetime]$ObservedAtUtc = ([datetime]::UtcNow),
        [scriptblock]$Request = ${function:Invoke-VtWorkshopPublishedFileRequest}
    )
    $item = ConvertTo-VtWorkshopCanonicalUInt64Text $PublishedId 'requested publishedfileid'
    $body = [Text.Encoding]::ASCII.GetBytes('itemcount=1&publishedfileids%5B0%5D=' + $item)
    $response = & $Request -Uri $script:VtWorkshopDetailsUri -InputBytes $body `
        -ContentType 'application/x-www-form-urlencoded'
    if ($null -eq $response -or $response.StatusCode -ne 200) {
        $detail = if ($null -ne $response) { [string]$response.Error } else { 'null response' }
        throw "Steam published-file lookup failed (HTTP $($response.StatusCode)): $detail"
    }
    return ConvertFrom-VtWorkshopPublishedFileObservation -Bytes ([byte[]]$response.Bytes) `
        -PublishedId $item -ObservedAtUtc $ObservedAtUtc
}

function Get-VtWorkshopNoChangeProofBasis {
    # 'snapshot' = both observations carry VT2 content identity (public path);
    # 'not-visible' = both positively report the item as not publicly visible.
    param([Parameter(Mandatory = $true)]$Before, [Parameter(Mandatory = $true)]$After)
    $purposes = @([string]$Before.purpose, [string]$After.purpose)
    if ($purposes[0] -ceq 'steam-published-file-snapshot/v1' -and $purposes[1] -ceq $purposes[0]) { return 'snapshot' }
    if ($purposes[0] -ceq $script:VtWorkshopNotVisiblePurpose -and $purposes[1] -ceq $purposes[0]) { return 'not-visible' }
    throw "Steam published-file observations disagree across the upload ($($purposes -join ' -> ')); visibility or evidence shape changed."
}

function Test-VtWorkshopNotVisibleObservationPair {
    param(
        [Parameter(Mandatory = $true)]$Before,
        [Parameter(Mandatory = $true)]$After,
        [Parameter(Mandatory = $true)][string]$PublishedId
    )
    $problems = New-Object 'Collections.Generic.List[string]'
    foreach ($observation in @($Before, $After)) {
        $names = (@($observation.PSObject.Properties.Name) | Sort-Object) -join ','
        if ($names -cne 'detail_result,observed_at_utc,publishedfileid,purpose,response_sha256,schema' -or
                $observation.schema -ne 1 -or [string]$observation.purpose -cne $script:VtWorkshopNotVisiblePurpose -or
                [string]$observation.publishedfileid -cne $PublishedId -or [string]$observation.detail_result -cne '9' -or
                [string]$observation.response_sha256 -cnotmatch '\A[0-9a-f]{64}\z') {
            $problems.Add('not-visible observation is malformed or names a foreign item')
        }
    }
    [datetime]$beforeTime = [datetime]::MinValue; [datetime]$afterTime = [datetime]::MinValue
    $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetime]::TryParseExact([string]$Before.observed_at_utc, 'yyyy-MM-ddTHH:mm:ssZ',
            [cultureinfo]::InvariantCulture, $style, [ref]$beforeTime) -or
            -not [datetime]::TryParseExact([string]$After.observed_at_utc, 'yyyy-MM-ddTHH:mm:ssZ',
                [cultureinfo]::InvariantCulture, $style, [ref]$afterTime) -or
            $afterTime -lt $beforeTime -or ($afterTime - $beforeTime).TotalHours -gt 2) {
        $problems.Add('not-visible observations have an invalid observation window')
    }
    return [pscustomobject]@{Ok=($problems.Count -eq 0);Problems=$problems.ToArray()}
}

function Get-VtWorkshopPriorContentTransaction {
    # Pure parser over the verified pre-upload log prefix. Returns the item's
    # last complete UPLOADED transaction when every later event naming the item
    # is a complete NOCHANGE transaction or a server-change line for the same
    # manifest. Anything else after it fails closed.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$PublishedId
    )
    if (-not (Test-VtWorkshopLogProofUInt64 $PublishedId)) { throw 'Prior-content proof requires a canonical positive UInt64 item ID.' }
    $id = $PublishedId
    $mention = '(?:workshop item|for item|cached item)\s+[+-]?0*' + $id + '(?![0-9])'
    $events = New-Object 'Collections.Generic.List[object]'
    foreach ($raw in $Text.Split([char]10)) {
        $line = if ($raw.EndsWith("`r")) { $raw.Substring(0, $raw.Length - 1) } else { $raw }
        if ($line -notmatch $mention) { continue }
        $kind = 'other'; $manifest = $null; $stamp = $null
        if ($line.Length -le 8192 -and -not $line.Contains("`r") -and
                $line -cmatch '\A\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\] \[AppID 552500\] (.*)\z') {
            $stampText = $matches[1]; $message = $matches[2]
            [datetime]$parsedStamp = [datetime]::MinValue
            if ([datetime]::TryParseExact($stampText, 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None, [ref]$parsedStamp)) {
                $stamp = $parsedStamp
                if ($message -ceq "Upload starting for workshop item $id by AppID 552500") { $kind = 'start' }
                elseif ($message -cmatch ('\AUploaded new content \( ManifestID ([1-9][0-9]*) \) for item ' + $id + '\.\z') -and
                        (Test-VtWorkshopLogProofUInt64 $matches[1])) { $kind = 'uploaded'; $manifest = $matches[1] }
                elseif ($message -ceq "No content change detected for item $id") { $kind = 'nochange' }
                elseif ($message -ceq "Upload finished for workshop item $id : OK") { $kind = 'finish-ok' }
                elseif ($message -cmatch ('\ADetected workshop change \(latest from server\) : changed cached item ' + $id + ', new manifest ([1-9][0-9]*)\z') -and
                        (Test-VtWorkshopLogProofUInt64 $matches[1])) { $kind = 'server-manifest'; $manifest = $matches[1] }
            }
        }
        $events.Add([pscustomobject]@{Kind=$kind;Line=$line;Manifest=$manifest;Stamp=$stamp})
    }
    $content = @(for ($k = 0; $k -lt $events.Count; $k++) { if ($events[$k].Kind -cne 'server-manifest') { $k } })
    $j = $content.Count; $noChange = 0; $found = $null; $triple = $null
    while ($j -gt 0) {
        $last = $events[$content[$j - 1]]
        if ($j -ge 3) {
            $a = $events[$content[$j - 3]]; $b = $events[$content[$j - 2]]
            if ($a.Kind -ceq 'start' -and $last.Kind -ceq 'finish-ok') {
                if ($b.Kind -ceq 'nochange') { $noChange++; $j -= 3; continue }
                if ($b.Kind -ceq 'uploaded') { $found = $content[$j - 3]; $triple = @($a, $b, $last); break }
            }
        }
        throw "Item event after the last complete UPLOADED transaction is not a complete NOCHANGE transaction: $($last.Line)"
    }
    if ($null -eq $found) { throw "Retained Steam log has no complete UPLOADED transaction for item $id." }
    # The chain keeps raw order (server-change lines included) for the ordering,
    # server-manifest, and digest checks; the bound lines are the found triple,
    # so a same-manifest server line inside the transaction cannot shift them.
    $chain = @($events | Select-Object -Skip $found)
    $upload = $triple[1].Manifest; $confirmations = 0; $previous = $chain[0].Stamp
    foreach ($event in $chain) {
        if ($null -eq $event.Stamp -or $event.Stamp -lt $previous) { throw "Prior-content chain is out of order: $($event.Line)" }
        $previous = $event.Stamp
        if ($event.Kind -ceq 'server-manifest') {
            if ($event.Manifest -cne $upload) { throw "Steam reported server manifest $($event.Manifest) after uploaded manifest $upload for item $id." }
            $confirmations++
        }
    }
    $chainLines = @($chain | ForEach-Object { [string]$_.Line })
    return [pscustomobject][ordered]@{
        Schema = 1; PublishedId = $id; ManifestId = $upload
        StartLine = $triple[0].Line; OutcomeLine = $triple[1].Line; FinishLine = $triple[2].Line
        NoChangeCount = $noChange; ServerConfirmations = $confirmations; ChainLines = $chainLines
        ChainSha256 = Get-VtWorkshopLogProofTextSha256 (($chainLines -join "`n") + "`n")
    }
}

function Get-VtWorkshopEvidencePriorContent {
    # Reads the exact pre-upload prefix through the retained observer stream,
    # proves it is the captured prefix by digest, and never throws: a missing
    # prior proof only makes a later non-public NOCHANGE fail closed.
    param(
        [Parameter(Mandatory = $true)][IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)]$Capture,
        [Parameter(Mandatory = $true)][string]$PublishedId
    )
    try {
        $count = [long]$Capture.Boundary
        if ($count -le 0 -or $count -gt 16777216) { throw 'Workshop log prefix is empty or exceeds the 16 MiB evidence budget.' }
        $bytes = [byte[]]::new([int]$count)
        $null = $Stream.Seek(0, [IO.SeekOrigin]::Begin)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw 'Workshop log was truncated during prior-content verification.' }
            $offset += $read
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = [Convert]::ToBase64String($sha.ComputeHash($bytes)) } finally { $sha.Dispose() }
        if ($digest -cne [string]$Capture.Prefix) { throw 'Workshop log prefix changed before prior-content verification.' }
        # Item events are ASCII and grammar-checked; replacement characters from
        # unrelated non-UTF-8 bytes can never complete an item grammar.
        $text = [Text.UTF8Encoding]::new($false, $false).GetString($bytes)
        $proof = Get-VtWorkshopPriorContentTransaction -Text $text -PublishedId $PublishedId
        return [pscustomobject]@{Ok=$true;Proof=$proof;Error=$null}
    }
    catch { return [pscustomobject]@{Ok=$false;Proof=$null;Error=$_.Exception.Message} }
}

function Test-VtWorkshopNoChangeLogResultCandidate {
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
    foreach ($field in $script:VtWorkshopNoChangeLogFields) { if ($names -cnotcontains $field) { $problems.Add("missing exact field $field") } }
    foreach ($name in $names) { if ($script:VtWorkshopNoChangeLogFields -cnotcontains $name) { $problems.Add("unexpected field $name") } }
    $v = @{}
    foreach ($field in $script:VtWorkshopNoChangeLogFields) { $v[$field] = Get-VtWorkshopResultProperty $Candidate $field }
    if (($v.schema -isnot [int] -and $v.schema -isnot [long]) -or $v.schema -ne 1) { $problems.Add('schema must be integer 1') }
    if ($v.purpose -cne $script:VtWorkshopNoChangeLogPurpose) { $problems.Add('purpose mismatch') }
    if ($v.authenticated -isnot [bool] -or $v.authenticated) { $problems.Add('candidate cannot claim authentication') }
    foreach ($field in $script:VtWorkshopNoChangeLogFields | Where-Object { $_ -notin @('schema','authenticated') }) {
        if ($v[$field] -isnot [string] -or [string]::IsNullOrWhiteSpace($v[$field])) { $problems.Add("$field must be one nonempty JSON string") }
    }
    $receipt = $publication.Receipt
    foreach ($pair in @(@('repository','repository'),@('release_tag','release_tag'),@('source_commit','source_commit'),
            @('mod','mod'),@('version','version'),@('publication_receipt_asset_name','receipt_asset_name'))) {
        if ([string]$v[$pair[0]] -cne [string]$receipt.($pair[1])) { $problems.Add("$($pair[0]) does not match exact publication receipt") }
    }
    if ($v.publication_receipt_sha256 -cne $publication.Sha256) { $problems.Add('publication receipt digest mismatch') }
    foreach ($field in @('workshop_id','steam_manifest_id','app_id')) {
        if (-not (Test-VtWorkshopLogProofUInt64 $v[$field])) { $problems.Add("$field is not a canonical positive UInt64") }
    }
    foreach ($field in @('prior_nochange_count','prior_server_confirmations')) {
        if (-not (Test-VtWorkshopLogProofUInt64 $v[$field] -AllowZero)) { $problems.Add("$field is not a canonical UInt64") }
    }
    if ($v.mod_id -cnotmatch '\A[A-Za-z][A-Za-z0-9_]*\z') { $problems.Add('mod_id is noncanonical') }
    elseif ($v.release_asset_name -cne ($v.mod_id + '.zip')) { $problems.Add('release asset name does not match mod_id') }
    if ($v.app_id -cne '552500') { $problems.Add('app_id is not Vermintide 2') }
    if ($v.transaction_status -cne 'NOCHANGE') { $problems.Add('transaction_status is not NOCHANGE') }
    if ($script:VtWorkshopNonPublicVisibilities -cnotcontains [string]$v.visibility) { $problems.Add('visibility is not friends_only or private') }
    foreach ($field in @('publication_receipt_sha256','release_asset_sha256','transaction_evidence_sha256',
            'start_line_sha256','outcome_line_sha256','finish_line_sha256','prior_start_line_sha256',
            'prior_outcome_line_sha256','prior_finish_line_sha256','prior_chain_sha256',
            'steam_pre_response_sha256','steam_post_response_sha256')) {
        if ($v[$field] -cnotmatch '\A[0-9a-f]{64}\z') { $problems.Add("$field is not lowercase SHA-256") }
    }
    $expectedAsset = $null
    try { $expectedAsset = Get-VtWorkshopNoChangeResultAssetName $v.mod $v.source_commit $v.publication_receipt_sha256 }
    catch { $problems.Add($_.Exception.Message) }
    if ($expectedAsset -and $v.candidate_asset_name -cne $expectedAsset) { $problems.Add('candidate asset name mismatch') }
    [datetime]$time = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($v.recorded_at_utc, 'yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$time)) {
        $problems.Add('recorded_at_utc is not canonical whole-second UTC')
    }
    return [pscustomobject]@{Ok=($problems.Count -eq 0);Problems=$problems.ToArray();Authenticated=$false;MayMutate=$false}
}

function New-VtWorkshopNoChangeLogResultCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$PublicationReceiptBytes,
        [Parameter(Mandatory = $true)]$UploadResult,
        [Parameter(Mandatory = $true)][string]$ModId,
        [Parameter(Mandatory = $true)][string]$ReleaseAssetName,
        [Parameter(Mandatory = $true)][string]$ReleaseAssetSha256,
        [Parameter(Mandatory = $true)][string]$Visibility,
        [Parameter(Mandatory = $true)]$BeforeObservation,
        [Parameter(Mandatory = $true)]$AfterObservation,
        [datetime]$RecordedAtUtc = ([datetime]::UtcNow)
    )
    $publication = ConvertFrom-VtWorkshopPublicationReceiptBytes $PublicationReceiptBytes
    $receipt = $publication.Receipt
    if ($UploadResult.Schema -ne 1 -or $UploadResult.Status -cne 'NOCHANGE' -or $UploadResult.AppId -cne '552500' -or
            -not (Test-VtWorkshopLogProofUInt64 ([string]$UploadResult.PublishedId)) -or $null -ne $UploadResult.ManifestId -or
            [string]$UploadResult.EvidenceTextSha256 -cnotmatch '\A[0-9a-f]{64}\z') {
        throw 'only one validated schema-1 NOCHANGE transaction can create a log-bound no-change candidate'
    }
    $item = [string]$UploadResult.PublishedId
    if ($script:VtWorkshopNonPublicVisibilities -cnotcontains $Visibility) {
        throw "log-bound NOCHANGE proof is only for friends_only or private items, not '$Visibility'"
    }
    $pair = Test-VtWorkshopNotVisibleObservationPair $BeforeObservation $AfterObservation $item
    if (-not $pair.Ok) { throw ('Steam not-visible observation pair is not stable: ' + ($pair.Problems -join '; ')) }
    $envelope = '^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\] \[AppID 552500\] '
    $start = [regex]::Escape("Upload starting for workshop item $item by AppID 552500")
    $finish = [regex]::Escape("Upload finished for workshop item $item : OK")
    if ([string]$UploadResult.StartLine -cnotmatch ($envelope + $start + '$') -or
            [string]$UploadResult.OutcomeLine -cnotmatch ($envelope + [regex]::Escape("No content change detected for item $item") + '$') -or
            [string]$UploadResult.FinishLine -cnotmatch ($envelope + $finish + '$')) {
        throw 'validated NOCHANGE result lines do not bind the selected item'
    }
    $currentStart = ([regex]::Match([string]$UploadResult.StartLine, $envelope)).Groups[1].Value
    $priorContent = $UploadResult.PSObject.Properties['PriorContent']
    if ($null -eq $priorContent -or $null -eq $priorContent.Value -or -not $priorContent.Value.Ok) {
        $why = if ($null -ne $priorContent -and $null -ne $priorContent.Value) { [string]$priorContent.Value.Error } else { 'no prior-content evidence was captured' }
        throw "non-public NOCHANGE has no prior UPLOADED proof in the verified Steam log prefix: $why"
    }
    $prior = $priorContent.Value.Proof
    $manifest = [string]$prior.ManifestId
    $chainLines = @($prior.ChainLines)
    # Bind the transaction lines among the chain's non-server lines, so a
    # same-manifest server-change line inside the UPLOADED transaction is allowed.
    $serverLine = $envelope + [regex]::Escape("Detected workshop change (latest from server) : changed cached item $item, new manifest $manifest") + '$'
    $contentLines = @($chainLines | Where-Object { [string]$_ -cnotmatch $serverLine })
    if ($prior.Schema -ne 1 -or [string]$prior.PublishedId -cne $item -or -not (Test-VtWorkshopLogProofUInt64 $manifest) -or
            $contentLines.Count -lt 3 -or [string]$contentLines[1] -cne [string]$prior.OutcomeLine -or
            [string]$contentLines[2] -cne [string]$prior.FinishLine -or [string]$contentLines[0] -cne [string]$prior.StartLine -or
            [string]$prior.StartLine -cnotmatch ($envelope + $start + '$') -or
            [string]$prior.OutcomeLine -cnotmatch ($envelope + [regex]::Escape("Uploaded new content ( ManifestID $manifest ) for item $item.") + '$') -or
            [string]$prior.FinishLine -cnotmatch ($envelope + $finish + '$') -or
            ([regex]::Match([string]$prior.FinishLine, $envelope)).Groups[1].Value -gt $currentStart -or
            [string]$prior.ChainSha256 -cne (Get-VtWorkshopLogProofTextSha256 (($chainLines -join "`n") + "`n")) -or
            [string]$chainLines[0] -cne [string]$prior.StartLine) {
        throw 'prior UPLOADED proof does not bind the selected item, manifest, and chain'
    }
    $recorded = $RecordedAtUtc.ToUniversalTime().AddTicks(-($RecordedAtUtc.ToUniversalTime().Ticks % [TimeSpan]::TicksPerSecond))
    $value = [pscustomobject][ordered]@{
        schema=1;purpose=$script:VtWorkshopNoChangeLogPurpose;authenticated=$false
        repository=[string]$receipt.repository;release_tag=[string]$receipt.release_tag
        candidate_asset_name=(Get-VtWorkshopNoChangeResultAssetName $receipt.mod $receipt.source_commit $publication.Sha256)
        recorded_at_utc=$recorded.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        source_commit=[string]$receipt.source_commit;mod=[string]$receipt.mod;mod_id=$ModId
        version=[string]$receipt.version;transaction_status='NOCHANGE';workshop_id=$item
        steam_manifest_id=$manifest;app_id='552500';visibility=$Visibility
        publication_receipt_asset_name=[string]$receipt.receipt_asset_name
        publication_receipt_sha256=$publication.Sha256;release_asset_name=$ReleaseAssetName
        release_asset_sha256=$ReleaseAssetSha256
        transaction_evidence_sha256=[string]$UploadResult.EvidenceTextSha256
        start_line_sha256=(Get-VtWorkshopLogProofTextSha256 $UploadResult.StartLine)
        outcome_line_sha256=(Get-VtWorkshopLogProofTextSha256 $UploadResult.OutcomeLine)
        finish_line_sha256=(Get-VtWorkshopLogProofTextSha256 $UploadResult.FinishLine)
        prior_start_line_sha256=(Get-VtWorkshopLogProofTextSha256 $prior.StartLine)
        prior_outcome_line_sha256=(Get-VtWorkshopLogProofTextSha256 $prior.OutcomeLine)
        prior_finish_line_sha256=(Get-VtWorkshopLogProofTextSha256 $prior.FinishLine)
        prior_chain_sha256=[string]$prior.ChainSha256
        prior_nochange_count=[string][int]$prior.NoChangeCount
        prior_server_confirmations=[string][int]$prior.ServerConfirmations
        steam_pre_response_sha256=[string]$BeforeObservation.response_sha256
        steam_post_response_sha256=[string]$AfterObservation.response_sha256
    }
    $verdict = Test-VtWorkshopNoChangeLogResultCandidate $value $PublicationReceiptBytes
    if (-not $verdict.Ok) { throw ('invalid log-bound no-change candidate: ' + ($verdict.Problems -join '; ')) }
    return $value
}
