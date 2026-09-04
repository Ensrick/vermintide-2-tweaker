# github-release-api.ps1 - release lookup and asset I/O without tag-route coupling.
#
# GitHub's release-by-tag endpoint can fail independently of the releases-list
# and release-asset endpoints (issue #651).  Keep all fallback decisions here so
# callers cannot turn a degraded endpoint into a false "release absent" result.

function Get-GitHubReleaseToken {
    if ($script:GitHubReleaseToken) { return $script:GitHubReleaseToken }

    $token = "$env:GH_TOKEN".Trim()
    if (-not $token) { $token = "$env:GITHUB_TOKEN".Trim() }
    if (-not $token) {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { $token = "$(& gh auth token 2>$null)".Trim() }
        finally { $ErrorActionPreference = $previousPreference }
    }
    if (-not $token) {
        throw 'GitHub API token unavailable. Set GH_TOKEN/GITHUB_TOKEN or authenticate gh.'
    }
    $script:GitHubReleaseToken = $token
    return $token
}

function ConvertTo-GitHubReleaseTransferByteCount {
    param(
        [AllowNull()][AllowEmptyString()]$Value,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ($null -eq $Value) { throw "$Context is missing." }
    $text = [Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    if ($text -notmatch '^(0|[1-9][0-9]*)$') {
        throw "$Context must be a non-negative integer byte count."
    }
    try {
        $bytes = [long]::Parse(
            $text,
            [System.Globalization.NumberStyles]::None,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch {
        throw "$Context must be a non-negative integer byte count."
    }
    # This client buffers each response into one byte array before its immutable
    # hash verification, so metadata outside its signed 32-bit support boundary
    # must fail closed before any network request.
    if ($bytes -gt [int]::MaxValue) {
        throw "$Context exceeds the supported release-asset maximum of $([int]::MaxValue) bytes."
    }
    return $bytes
}

function ConvertTo-GitHubReleaseSafeErrorText {
    param([AllowNull()][AllowEmptyString()]$Value)

    $text = [Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture).Trim()
    if (-not $text) { return '' }
    foreach ($secret in @($script:GitHubReleaseToken, $env:GH_TOKEN, $env:GITHUB_TOKEN)) {
        if ($null -ne $secret -and "$secret".Length -ge 8) {
            $text = $text.Replace("$secret", '[REDACTED]')
        }
    }
    $text = $text -replace '(?i)\bBearer\s+\S+', 'Bearer [REDACTED]'
    $text = ($text -replace '[\r\n]+', ' ').Trim()
    if ($text.Length -gt 512) { $text = $text.Substring(0, 512) + '...' }
    return $text
}

function Get-GitHubReleaseRequestTimeoutSeconds {
    param(
        [byte[]]$InputBytes,
        [AllowNull()][AllowEmptyString()]$ExpectedResponseBytes
    )

    $hasExpectedResponseBytes = $PSBoundParameters.ContainsKey('ExpectedResponseBytes')
    $transferBytes = [long]0
    if ($null -ne $InputBytes) {
        $transferBytes = [long]$InputBytes.LongLength
    }
    if ($hasExpectedResponseBytes) {
        $responseBytes = ConvertTo-GitHubReleaseTransferByteCount `
            -Value $ExpectedResponseBytes -Context 'ExpectedResponseBytes'
        if ($responseBytes -gt $transferBytes) { $transferBytes = $responseBytes }
    }

    # 30 s floor for metadata, then one second per 256 KiB (about 2 Mbit/s
    # of headroom), capped at one hour.
    $timeoutSeconds = [Math]::Ceiling($transferBytes / 262144.0)
    if ($timeoutSeconds -lt 30) { $timeoutSeconds = 30 }
    if ($timeoutSeconds -gt 3600) { $timeoutSeconds = 3600 }
    return [int]$timeoutSeconds
}

function Invoke-GitHubReleaseApiRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Accept = 'application/vnd.github+json',
        [string]$InputPath,
        [byte[]]$InputBytes,
        [AllowNull()][AllowEmptyString()]$ExpectedResponseBytes,
        [string]$ContentType = 'application/octet-stream',
        [string]$OutputPath
    )

    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    # The timeout is set below, once transfer size is known. A flat 30 s is
    # right for metadata calls but silently truncates large transfers: a 75 MB
    # upload cancelled mid-POST on 2026-08-06, then a 60 MB carry-forward GET
    # cancelled twice on 2026-09-03 because upload-only sizing left downloads
    # at the floor. Both surfaced as HTTP 0 before Workshop mutation.
    $request = New-Object System.Net.Http.HttpRequestMessage(
        [System.Net.Http.HttpMethod]::new($Method.ToUpperInvariant()),
        $Uri
    )
    try {
        $request.Headers.UserAgent.ParseAdd('vermintide-2-tweaker-release-tooling/1.0')
        $request.Headers.Accept.ParseAdd($Accept)
        $request.Headers.Add('X-GitHub-Api-Version', '2022-11-28')
        $request.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue(
            'Bearer',
            (Get-GitHubReleaseToken)
        )
        if ($InputPath -and $null -ne $InputBytes) {
            throw 'Specify either InputPath or InputBytes, not both.'
        }
        if ($InputPath) {
            if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
                throw "Upload input not found: $InputPath"
            }
            $InputBytes = [System.IO.File]::ReadAllBytes($InputPath)
        }
        if ($null -ne $InputBytes) {
            $request.Content = New-Object System.Net.Http.ByteArrayContent -ArgumentList (,$InputBytes)
            $request.Content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue($ContentType)
        }

        if ($PSBoundParameters.ContainsKey('ExpectedResponseBytes') -and
            $Method.ToUpperInvariant() -ne 'GET') {
            throw 'ExpectedResponseBytes is valid only for GET requests.'
        }
        $timeoutArguments = @{}
        if ($null -ne $InputBytes) { $timeoutArguments.InputBytes = $InputBytes }
        if ($PSBoundParameters.ContainsKey('ExpectedResponseBytes')) {
            $timeoutArguments.ExpectedResponseBytes = $ExpectedResponseBytes
        }
        # HttpClient.Timeout must be assigned before the first send, which has
        # not happened yet on this per-call client. Uploads use their immutable
        # input bytes; asset downloads use the trusted release metadata size.
        $timeoutSeconds = Get-GitHubReleaseRequestTimeoutSeconds @timeoutArguments
        $client.Timeout = [TimeSpan]::FromSeconds($timeoutSeconds)

        try {
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            $responseBytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            if ($OutputPath -and [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300) {
                [System.IO.File]::WriteAllBytes($OutputPath, $responseBytes)
            }
            return [pscustomobject]@{
                StatusCode = [int]$response.StatusCode
                Content    = [System.Text.Encoding]::UTF8.GetString($responseBytes)
                Bytes      = $responseBytes
                Error      = $null
            }
        }
        catch {
            return [pscustomobject]@{
                StatusCode = 0
                Content    = ''
                Bytes      = [byte[]]@()
                Error      = ConvertTo-GitHubReleaseSafeErrorText -Value $_.Exception.Message
            }
        }
        finally {
            if ($response) { $response.Dispose() }
        }
    }
    finally {
        $request.Dispose()
        $client.Dispose()
    }
}

function ConvertFrom-GitHubReleaseJson {
    param(
        [Parameter(Mandatory = $true)]$Response,
        [Parameter(Mandatory = $true)][string]$Context
    )
    try { return ($Response.Content | ConvertFrom-Json) }
    catch { throw "$Context returned invalid JSON (HTTP $($Response.StatusCode)): $($_.Exception.Message)" }
}

function Test-GitHubTransientStatus {
    param([int]$StatusCode)
    return ($StatusCode -eq 0 -or $StatusCode -eq 408 -or $StatusCode -eq 429 -or ($StatusCode -ge 500 -and $StatusCode -le 599))
}

function Resolve-GitHubReleaseByTag {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest},
        [ValidateRange(1, 20)][int]$MaxPages = 5,
        [ValidateRange(1, 100)][int]$PerPage = 100
    )

    $encodedTag = [System.Uri]::EscapeDataString($Tag)
    $tagUri = "https://api.github.com/repos/$Repo/releases/tags/$encodedTag"
    $tagResponse = & $Request -Method GET -Uri $tagUri
    if ($tagResponse.StatusCode -ge 200 -and $tagResponse.StatusCode -lt 300) {
        $release = ConvertFrom-GitHubReleaseJson -Response $tagResponse -Context "release tag '$Tag'"
        if ("$($release.tag_name)" -cne $Tag) {
            return [pscustomobject]@{
                State = 'Unavailable'; Release = $null; Route = 'tag'; TagStatus = $tagResponse.StatusCode
                PagesScanned = 0; Message = "Tag endpoint returned '$($release.tag_name)' for exact tag '$Tag'."
            }
        }
        return [pscustomobject]@{
            State = 'Found'; Release = $release; Route = 'tag'; TagStatus = $tagResponse.StatusCode
            PagesScanned = 0; Message = "release '$Tag' resolved by canonical tag endpoint"
        }
    }

    # Confirm a 404 through the bounded list too.  A route-specific false 404
    # must not authorize creation of a duplicate release that the list can see.
    if ($tagResponse.StatusCode -ne 404 -and -not (Test-GitHubTransientStatus -StatusCode $tagResponse.StatusCode)) {
        return [pscustomobject]@{
            State = 'Unavailable'; Release = $null; Route = 'tag'; TagStatus = $tagResponse.StatusCode
            PagesScanned = 0; Message = "release tag lookup failed with non-transient HTTP $($tagResponse.StatusCode)"
        }
    }

    $tagFailure = if ($tagResponse.StatusCode -eq 404) {
        'tag endpoint reported 404'
    } else {
        "tag endpoint degraded (HTTP $($tagResponse.StatusCode))"
    }
    $matches = @()
    for ($page = 1; $page -le $MaxPages; $page++) {
        $listUri = "https://api.github.com/repos/$Repo/releases?per_page=$PerPage&page=$page"
        $listResponse = & $Request -Method GET -Uri $listUri
        if ($listResponse.StatusCode -lt 200 -or $listResponse.StatusCode -ge 300) {
            return [pscustomobject]@{
                State = 'Unavailable'; Release = $null; Route = 'list-fallback'; TagStatus = $tagResponse.StatusCode
                PagesScanned = ($page - 1); Message = "$tagFailure; releases list failed with HTTP $($listResponse.StatusCode)"
            }
        }
        $pageItems = @(ConvertFrom-GitHubReleaseJson -Response $listResponse -Context "releases list page $page")
        $matches += @($pageItems | Where-Object { "$($_.tag_name)" -ceq $Tag })
        if ($matches.Count -gt 1) {
            return [pscustomobject]@{
                State = 'Unavailable'; Release = $null; Route = 'list-fallback'; TagStatus = $tagResponse.StatusCode
                PagesScanned = $page; Message = "releases list returned multiple exact matches for '$Tag'; refusing ambiguous mutation"
            }
        }
        if ($matches.Count -eq 1) {
            return [pscustomobject]@{
                State = 'Found'; Release = $matches[0]; Route = 'list-fallback'; TagStatus = $tagResponse.StatusCode
                PagesScanned = $page; Message = "$tagFailure; exact tag resolved from releases list page $page"
            }
        }
        if ($pageItems.Count -lt $PerPage) {
            return [pscustomobject]@{
                State = 'Absent'; Release = $null; Route = 'list-fallback'; TagStatus = $tagResponse.StatusCode
                PagesScanned = $page; Message = "$tagFailure; '$Tag' is absent from the complete releases list"
            }
        }
    }

    return [pscustomobject]@{
        State = 'Unavailable'; Release = $null; Route = 'list-fallback'; TagStatus = $tagResponse.StatusCode
        PagesScanned = $MaxPages; Message = "$tagFailure; bounded list lookup exhausted $MaxPages full page(s) without an exact match"
    }
}

function Get-GitHubLatestReleaseFromList {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest},
        [ValidateRange(1, 100)][int]$PerPage = 100
    )
    $uri = "https://api.github.com/repos/$Repo/releases?per_page=$PerPage&page=1"
    $response = & $Request -Method GET -Uri $uri
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Could not list releases for $Repo (HTTP $($response.StatusCode))."
    }
    $releases = @(ConvertFrom-GitHubReleaseJson -Response $response -Context 'latest releases list')
    $latest = @($releases | Where-Object { -not $_.draft -and -not $_.prerelease } | Select-Object -First 1)
    if ($latest.Count -eq 0) { return $null }
    return $latest[0]
}

function Get-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $found = @($Release.assets | Where-Object { "$($_.name)" -ceq $Name })
    if ($found.Count -gt 1) {
        throw "Release $($Release.id) contains multiple exact assets named '$Name'; refusing ambiguous selection."
    }
    if ($found.Count -eq 0) { return $null }
    return $found[0]
}

function Save-GitHubReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)]$Asset,
        [Parameter(Mandatory = $true)][string]$Destination,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    if ("$($Asset.id)" -notmatch '^\d+$') { throw "Asset '$($Asset.name)' has no numeric release asset id." }
    $uri = if ("$($Asset.url)" -match '/releases/assets/\d+$') {
        "$($Asset.url)"
    } else {
        "https://api.github.com/repos/$Repo/releases/assets/$($Asset.id)"
    }
    $bytes = Get-GitHubReleaseAssetBytes -Repo $Repo -Asset $Asset -Request $Request
    [System.IO.File]::WriteAllBytes($Destination, $bytes)
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "Could not persist downloaded release asset '$($Asset.name)' (id $($Asset.id))."
    }
}

function Get-GitHubReleaseAssetBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)]$Asset,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    if ("$($Asset.id)" -notmatch '^\d+$') { throw "Asset '$($Asset.name)' has no numeric release asset id." }
    $sizeProperty = $Asset.PSObject.Properties['size']
    $expectedBytes = ConvertTo-GitHubReleaseTransferByteCount `
        -Value $(if ($null -ne $sizeProperty) { $sizeProperty.Value } else { $null }) `
        -Context "Release asset '$($Asset.name)' (id $($Asset.id)) size"
    $uri = if ("$($Asset.url)" -match '/releases/assets/\d+$') {
        "$($Asset.url)"
    } else {
        "https://api.github.com/repos/$Repo/releases/assets/$($Asset.id)"
    }
    $response = & $Request -Method GET -Uri $uri -Accept 'application/octet-stream' `
        -ExpectedResponseBytes $expectedBytes
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        $errorText = ConvertTo-GitHubReleaseSafeErrorText -Value $response.Error
        $errorSuffix = if ($response.StatusCode -eq 0 -and $errorText) { ": $errorText" } else { '' }
        throw "Download of release asset '$($Asset.name)' (id $($Asset.id)) failed with HTTP $($response.StatusCode)$errorSuffix."
    }
    $bytes = if ($null -ne $response.Bytes) {
        [byte[]]$response.Bytes
    } else {
        [System.Text.Encoding]::UTF8.GetBytes([string]$response.Content)
    }
    if ([long]$bytes.LongLength -ne $expectedBytes) {
        throw "Download of release asset '$($Asset.name)' (id $($Asset.id)) returned $($bytes.LongLength) bytes; release metadata declared $expectedBytes."
    }
    return $bytes
}

function New-GitHubReleaseAssetSnapshots {
    param([Parameter(Mandatory = $true)][string[]]$AssetPaths)

    $seenNames = @{}
    $snapshots = @()
    foreach ($path in $AssetPaths) {
        $name = [System.IO.Path]::GetFileName($path)
        if ($seenNames.ContainsKey($name)) { throw "Duplicate requested release asset name: $name" }
        $seenNames[$name] = $true
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Release asset input not found: $path"
        }
        # Read once. Every later validation, upload, and receipt handoff uses
        # this immutable byte array rather than reopening a mutable path.
        $bytes = [System.IO.File]::ReadAllBytes($path)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
        $snapshots += [pscustomobject]@{
            Name = $name
            SourcePath = [System.IO.Path]::GetFullPath($path)
            Bytes = $bytes
            Length = [long]$bytes.Length
            Sha256 = $hash
            ContentType = if ($name -eq 'manifest.json' -or $name -like 'publication-receipt-*.json') {
                'application/json'
            } else {
                'application/zip'
            }
        }
    }
    return @($snapshots | Sort-Object @{ Expression = { if ($_.Name -eq 'manifest.json') { 1 } else { 0 } } }, Name)
}

function New-GitHubDraftRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Tag,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Notes,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    $payload = [ordered]@{
        tag_name = $Tag
        name = $Title
        body = $Notes
        draft = $true
        prerelease = $false
    } | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $response = & $Request -Method POST -Uri "https://api.github.com/repos/$Repo/releases" `
        -InputBytes $bytes -ContentType 'application/json'
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Could not create draft release '$Tag' (HTTP $($response.StatusCode))."
    }
    $release = ConvertFrom-GitHubReleaseJson -Response $response -Context "draft release '$Tag'"
    if ("$($release.id)" -notmatch '^\d+$' -or "$($release.tag_name)" -cne $Tag -or -not $release.draft) {
        throw "GitHub returned an invalid draft release identity for '$Tag'."
    }
    return $release
}

function Publish-GitHubDraftRelease {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)]$Release,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    if ("$($Release.id)" -notmatch '^\d+$' -or -not $Release.draft) {
        throw 'Only an exact draft release id can be published.'
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"draft":false}')
    $response = & $Request -Method PATCH `
        -Uri "https://api.github.com/repos/$Repo/releases/$($Release.id)" `
        -InputBytes $bytes -ContentType 'application/json'
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
        throw "Could not publish draft release id $($Release.id) (HTTP $($response.StatusCode))."
    }
    $published = ConvertFrom-GitHubReleaseJson -Response $response -Context "published release $($Release.id)"
    if ("$($published.id)" -ne "$($Release.id)" -or $published.draft) {
        throw "GitHub did not confirm publication of release id $($Release.id)."
    }
    return $published
}

function Publish-GitHubReleaseAssetsById {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)]$Release,
        [string[]]$AssetPaths,
        [object[]]$AssetSnapshots,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    if ("$($Release.id)" -notmatch '^\d+$') { throw 'Resolved release has no numeric id; refusing asset mutation.' }
    if (($AssetPaths -and $AssetSnapshots) -or (-not $AssetPaths -and -not $AssetSnapshots)) {
        throw 'Specify exactly one of AssetPaths or AssetSnapshots.'
    }
    $snapshots = if ($AssetSnapshots) { @($AssetSnapshots) } else {
        @(New-GitHubReleaseAssetSnapshots -AssetPaths $AssetPaths)
    }

    # Keep manifest last: consumers must never observe a manifest that points at
    # a replacement zip which has not reached the release yet.
    $seenNames = @{}
    foreach ($snapshot in $snapshots) {
        $name = "$($snapshot.Name)"
        if ($seenNames.ContainsKey($name)) { throw "Duplicate requested release asset name: $name" }
        $seenNames[$name] = $true
    }
    $orderedSnapshots = @($snapshots | Where-Object { $_.Name -ne 'manifest.json' })
    $orderedSnapshots += @($snapshots | Where-Object { $_.Name -eq 'manifest.json' })
    foreach ($snapshot in $orderedSnapshots) {
        $name = "$($snapshot.Name)"
        $existing = Get-GitHubReleaseAsset -Release $Release -Name $name
        if ($existing) {
            $deleteUri = "https://api.github.com/repos/$Repo/releases/assets/$($existing.id)"
            $deleted = & $Request -Method DELETE -Uri $deleteUri
            if ($deleted.StatusCode -lt 200 -or $deleted.StatusCode -ge 300) {
                throw "Could not clobber '$name': delete of asset id $($existing.id) failed with HTTP $($deleted.StatusCode)."
            }
        }

        $encodedName = [System.Uri]::EscapeDataString($name)
        $uploadUri = "https://uploads.github.com/repos/$Repo/releases/$($Release.id)/assets?name=$encodedName"
        $uploaded = & $Request -Method POST -Uri $uploadUri `
            -InputBytes ([byte[]]$snapshot.Bytes) -ContentType "$($snapshot.ContentType)"
        if ($uploaded.StatusCode -lt 200 -or $uploaded.StatusCode -ge 300) {
            throw "Upload of '$name' to release id $($Release.id) failed with HTTP $($uploaded.StatusCode)."
        }
    }
    return $orderedSnapshots
}
