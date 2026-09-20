# Issue #1307: bounded Steam published-file snapshot used to prove the
# ManifestID around one exact NOCHANGE upload transaction.  This owner is
# read-only, uses no Steam client process, and sends no GitHub credential.

$script:VtWorkshopDetailsUri = 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'
$script:VtWorkshopDetailsMaxBytes = 1048576

function Get-VtWorkshopPublishedFileByteSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-VtWorkshopCanonicalUInt64Text {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string]$Field,
        [switch]$AllowZero
    )
    if ($null -eq $Value) { throw "Steam published-file field '$Field' is missing." }
    $text = [Convert]::ToString($Value, [cultureinfo]::InvariantCulture)
    $pattern = if ($AllowZero) { '^(0|[1-9][0-9]*)$' } else { '^[1-9][0-9]*$' }
    [uint64]$parsed = 0
    if ($text -cnotmatch $pattern -or
            -not [uint64]::TryParse($text, [Globalization.NumberStyles]::None,
                [cultureinfo]::InvariantCulture, [ref]$parsed)) {
        throw "Steam published-file field '$Field' is not a canonical UInt64."
    }
    return $text
}

function Invoke-VtWorkshopPublishedFileRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][byte[]]$InputBytes,
        [string]$ContentType = 'application/x-www-form-urlencoded'
    )
    if ($Uri -cne $script:VtWorkshopDetailsUri) { throw 'Steam published-file request URI drifted.' }
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient -ArgumentList $handler
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $request = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::Post, $Uri)
    # Callers run this owner under StrictMode. Keep disposal fail-closed even
    # when SendAsync throws before assigning a response object.
    $response = $null
    try {
        $request.Headers.UserAgent.ParseAdd('vermintide-2-tweaker-workshop-proof/1.0')
        $cacheControl = New-Object System.Net.Http.Headers.CacheControlHeaderValue
        $cacheControl.NoCache = $true
        $cacheControl.NoStore = $true
        $request.Headers.CacheControl = $cacheControl
        $request.Headers.Pragma.ParseAdd('no-cache')
        $request.Content = New-Object System.Net.Http.ByteArrayContent -ArgumentList (,$InputBytes)
        $request.Content.Headers.ContentType =
            New-Object System.Net.Http.Headers.MediaTypeHeaderValue($ContentType)
        try {
            $response = $client.SendAsync(
                $request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            $declared = $response.Content.Headers.ContentLength
            if ($null -ne $declared -and [long]$declared -gt $script:VtWorkshopDetailsMaxBytes) {
                throw 'Steam published-file response exceeds the one-MiB budget.'
            }
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $memory = New-Object IO.MemoryStream
            try {
                $buffer = New-Object byte[] 8192
                while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    if ($memory.Length + $read -gt $script:VtWorkshopDetailsMaxBytes) {
                        throw 'Steam published-file response exceeds the one-MiB budget.'
                    }
                    $memory.Write($buffer, 0, $read)
                }
                $bytes = $memory.ToArray()
            }
            finally {
                $memory.Dispose()
                $stream.Dispose()
            }
            return [pscustomobject]@{StatusCode=[int]$response.StatusCode;Bytes=$bytes;Error=$null}
        }
        catch {
            return [pscustomobject]@{StatusCode=0;Bytes=[byte[]]@();Error=$_.Exception.Message}
        }
        finally { if ($response) { $response.Dispose() } }
    }
    finally {
        $request.Dispose()
        $client.Dispose()
        $handler.Dispose()
    }
}

function ConvertFrom-VtWorkshopPublishedFileResponse {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$PublishedId,
        [datetime]$ObservedAtUtc = ([datetime]::UtcNow)
    )
    $expectedId = ConvertTo-VtWorkshopCanonicalUInt64Text $PublishedId 'requested publishedfileid'
    if ($Bytes.Length -eq 0 -or $Bytes.Length -gt $script:VtWorkshopDetailsMaxBytes) {
        throw 'Steam published-file response is empty or oversized.'
    }
    try { $json = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes) }
    catch { throw 'Steam published-file response is not strict UTF-8.' }
    foreach ($field in @('response','publishedfiledetails','publishedfileid','consumer_app_id',
            'hcontent_file','time_updated','file_size')) {
        $count = [regex]::Matches($json, '"' + [regex]::Escape($field) + '"\s*:').Count
        if ($count -ne 1) {
            throw "Steam published-file field '$field' is missing or duplicated."
        }
    }
    try { $decoded = $json | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Steam published-file response is not valid JSON.' }
    if ($null -eq $decoded -or $null -eq $decoded.response) {
        throw 'Steam published-file response envelope is unavailable.'
    }
    $responseResult = ConvertTo-VtWorkshopCanonicalUInt64Text $decoded.response.result 'response.result'
    $resultCount = ConvertTo-VtWorkshopCanonicalUInt64Text $decoded.response.resultcount 'response.resultcount'
    $details = @($decoded.response.publishedfiledetails)
    if ($responseResult -cne '1' -or $resultCount -cne '1' -or $details.Count -ne 1) {
        throw 'Steam published-file response did not return one successful detail row.'
    }
    $detail = $details[0]
    $detailResult = ConvertTo-VtWorkshopCanonicalUInt64Text $detail.result 'detail.result'
    $item = ConvertTo-VtWorkshopCanonicalUInt64Text $detail.publishedfileid 'publishedfileid'
    $app = ConvertTo-VtWorkshopCanonicalUInt64Text $detail.consumer_app_id 'consumer_app_id'
    $manifest = ConvertTo-VtWorkshopCanonicalUInt64Text $detail.hcontent_file 'hcontent_file'
    $updated = ConvertTo-VtWorkshopCanonicalUInt64Text $detail.time_updated 'time_updated'
    $size = ConvertTo-VtWorkshopCanonicalUInt64Text $detail.file_size 'file_size' -AllowZero
    if ($detailResult -cne '1' -or $item -cne $expectedId -or $app -cne '552500') {
        throw 'Steam published-file detail row does not match the VT2 Workshop item.'
    }
    $observed = $ObservedAtUtc.ToUniversalTime().AddTicks(
        -($ObservedAtUtc.ToUniversalTime().Ticks % [TimeSpan]::TicksPerSecond))
    $identityText = "publishedfileid=$item`nconsumer_app_id=$app`nhcontent_file=$manifest`ntime_updated=$updated`nfile_size=$size`n"
    $identityBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($identityText)
    return [pscustomobject][ordered]@{
        schema = 1
        purpose = 'steam-published-file-snapshot/v1'
        publishedfileid = $item
        consumer_app_id = $app
        hcontent_file = $manifest
        time_updated = $updated
        file_size = $size
        identity_sha256 = Get-VtWorkshopPublishedFileByteSha256 $identityBytes
        response_sha256 = Get-VtWorkshopPublishedFileByteSha256 $Bytes
        observed_at_utc = $observed.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
    }
}

function Get-VtWorkshopPublishedFileSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$PublishedId,
        [datetime]$ObservedAtUtc = ([datetime]::UtcNow),
        [scriptblock]$Request = ${function:Invoke-VtWorkshopPublishedFileRequest}
    )
    $item = ConvertTo-VtWorkshopCanonicalUInt64Text $PublishedId 'requested publishedfileid'
    $body = [Text.Encoding]::ASCII.GetBytes(
        'itemcount=1&publishedfileids%5B0%5D=' + $item)
    $response = & $Request -Uri $script:VtWorkshopDetailsUri -InputBytes $body `
        -ContentType 'application/x-www-form-urlencoded'
    if ($null -eq $response -or $response.StatusCode -ne 200) {
        $detail = if ($null -ne $response) { [string]$response.Error } else { 'null response' }
        throw "Steam published-file lookup failed (HTTP $($response.StatusCode)): $detail"
    }
    return ConvertFrom-VtWorkshopPublishedFileResponse -Bytes ([byte[]]$response.Bytes) `
        -PublishedId $item -ObservedAtUtc $ObservedAtUtc
}

function Test-VtWorkshopPublishedFileSnapshotPair {
    param(
        [Parameter(Mandatory = $true)]$Before,
        [Parameter(Mandatory = $true)]$After,
        [Parameter(Mandatory = $true)][string]$PublishedId
    )
    $problems = New-Object 'Collections.Generic.List[string]'
    $item = $null
    try { $item = ConvertTo-VtWorkshopCanonicalUInt64Text $PublishedId 'requested publishedfileid' }
    catch { $problems.Add($_.Exception.Message) }
    $fields = @('schema','purpose','publishedfileid','consumer_app_id','hcontent_file',
        'time_updated','file_size','identity_sha256','response_sha256','observed_at_utc')
    foreach ($snapshot in @($Before,$After)) {
        foreach ($field in $fields) {
            if ($null -eq $snapshot.PSObject.Properties[$field]) {
                $problems.Add("snapshot is missing $field")
            }
        }
        if ($snapshot.schema -ne 1 -or $snapshot.purpose -cne 'steam-published-file-snapshot/v1' -or
                [string]$snapshot.publishedfileid -cne [string]$item -or
                [string]$snapshot.consumer_app_id -cne '552500' -or
                [string]$snapshot.hcontent_file -cnotmatch '^[1-9][0-9]*$' -or
                [string]$snapshot.time_updated -cnotmatch '^[1-9][0-9]*$' -or
                [string]$snapshot.file_size -cnotmatch '^(0|[1-9][0-9]*)$' -or
                [string]$snapshot.identity_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
                [string]$snapshot.response_sha256 -cnotmatch '^[0-9a-f]{64}$') {
            $problems.Add('snapshot has a malformed or foreign identity')
        }
    }
    foreach ($field in @('publishedfileid','consumer_app_id','hcontent_file','time_updated',
            'file_size','identity_sha256')) {
        if ([string]$Before.$field -cne [string]$After.$field) {
            $problems.Add("Steam published-file $field changed across the upload")
        }
    }
    [datetime]$beforeTime = [datetime]::MinValue; [datetime]$afterTime = [datetime]::MinValue
    $timeStyle = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetime]::TryParseExact([string]$Before.observed_at_utc, 'yyyy-MM-ddTHH:mm:ssZ',
            [cultureinfo]::InvariantCulture, $timeStyle, [ref]$beforeTime) -or
            -not [datetime]::TryParseExact([string]$After.observed_at_utc, 'yyyy-MM-ddTHH:mm:ssZ',
                [cultureinfo]::InvariantCulture, $timeStyle, [ref]$afterTime) -or
            $afterTime -lt $beforeTime -or ($afterTime - $beforeTime).TotalHours -gt 2) {
        $problems.Add('Steam published-file snapshots have an invalid observation window')
    }
    return [pscustomobject]@{Ok=($problems.Count -eq 0);Problems=$problems.ToArray()}
}
