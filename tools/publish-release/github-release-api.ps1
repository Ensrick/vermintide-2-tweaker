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

function Invoke-GitHubReleaseApiRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Accept = 'application/vnd.github+json',
        [string]$InputPath,
        [string]$ContentType = 'application/octet-stream',
        [string]$OutputPath
    )

    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(30)
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
        if ($InputPath) {
            if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
                throw "Upload input not found: $InputPath"
            }
            $bytes = [System.IO.File]::ReadAllBytes($InputPath)
            $request.Content = New-Object System.Net.Http.ByteArrayContent -ArgumentList (,$bytes)
            $request.Content.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue($ContentType)
        }

        try {
            $response = $client.SendAsync($request).GetAwaiter().GetResult()
            $responseBytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            if ($OutputPath -and [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300) {
                [System.IO.File]::WriteAllBytes($OutputPath, $responseBytes)
            }
            return [pscustomobject]@{
                StatusCode = [int]$response.StatusCode
                Content    = [System.Text.Encoding]::UTF8.GetString($responseBytes)
                Error      = $null
            }
        }
        catch {
            return [pscustomobject]@{
                StatusCode = 0
                Content    = ''
                Error      = $_.Exception.Message
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
    $response = & $Request -Method GET -Uri $uri -Accept 'application/octet-stream' -OutputPath $Destination
    if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300 -or -not (Test-Path -LiteralPath $Destination -PathType Leaf)) {
        throw "Download of release asset '$($Asset.name)' (id $($Asset.id)) failed with HTTP $($response.StatusCode)."
    }
}

function Publish-GitHubReleaseAssetsById {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string[]]$AssetPaths,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    if ("$($Release.id)" -notmatch '^\d+$') { throw 'Resolved release has no numeric id; refusing asset mutation.' }

    # Keep manifest last: consumers must never observe a manifest that points at
    # a replacement zip which has not reached the release yet.
    $seenNames = @{}
    foreach ($path in $AssetPaths) {
        $name = [System.IO.Path]::GetFileName($path)
        if ($seenNames.ContainsKey($name)) { throw "Duplicate requested release asset name: $name" }
        $seenNames[$name] = $true
    }
    $orderedPaths = @($AssetPaths | Where-Object { [System.IO.Path]::GetFileName($_) -ne 'manifest.json' })
    $orderedPaths += @($AssetPaths | Where-Object { [System.IO.Path]::GetFileName($_) -eq 'manifest.json' })
    foreach ($path in $orderedPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release asset input not found: $path" }
        $name = [System.IO.Path]::GetFileName($path)
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
        $contentType = if ($name -eq 'manifest.json') { 'application/json' } else { 'application/zip' }
        $uploaded = & $Request -Method POST -Uri $uploadUri -InputPath $path -ContentType $contentType
        if ($uploaded.StatusCode -lt 200 -or $uploaded.StatusCode -ge 300) {
            throw "Upload of '$name' to release id $($Release.id) failed with HTTP $($uploaded.StatusCode)."
        }
    }
}
