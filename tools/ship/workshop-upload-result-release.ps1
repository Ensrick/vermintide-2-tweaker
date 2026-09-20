# Issue #1307: append-only persistence and trusted reread for one Workshop
# upload-result candidate.  This owner never deletes or replaces a release
# asset.  The content-qualified name makes an exact replay idempotent while a
# same-name/different-byte collision fails closed.
. (Join-Path $PSScriptRoot 'workshop-upload-result.ps1')
. (Join-Path $PSScriptRoot '../publish-release/github-release-api.ps1')

function Get-VtWorkshopUploadResultBytesSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-VtWorkshopUploadResultBytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )
    if ($Left.LongLength -ne $Right.LongLength) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }
    return $true
}

function ConvertTo-VtWorkshopUploadResultCandidateBytes {
    param(
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)][byte[]]$PublicationReceiptBytes
    )
    $verdict = Test-VtWorkshopUploadResultCandidate $Candidate $PublicationReceiptBytes
    if (-not $verdict.Ok) {
        throw ('Invalid Workshop upload-result candidate: ' + ($verdict.Problems -join '; '))
    }
    $json = $Candidate | ConvertTo-Json -Depth 8 -Compress
    return [Text.UTF8Encoding]::new($false, $true).GetBytes($json)
}

function ConvertFrom-VtWorkshopUploadResultCandidateBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][byte[]]$PublicationReceiptBytes
    )
    try {
        $json = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        # PowerShell 7.5 otherwise promotes ISO-8601 JSON strings to DateTime,
        # destroying the schema's exact string type. Windows PowerShell 5.1
        # has no DateKind switch and already preserves these strings.
        $jsonArgs = @{}
        if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
            $jsonArgs.DateKind = 'String'
        }
        $candidate = $json | ConvertFrom-Json @jsonArgs
    }
    catch { throw "Workshop upload-result asset is not strict UTF-8 JSON: $($_.Exception.Message)" }
    $verdict = Test-VtWorkshopUploadResultCandidate $candidate $PublicationReceiptBytes
    if (-not $verdict.Ok) {
        throw ('Persisted Workshop upload-result candidate is invalid: ' + ($verdict.Problems -join '; '))
    }
    return $candidate
}

function Assert-VtWorkshopUploadResultRelease {
    param(
        [Parameter(Mandatory = $true)]$Resolution,
        [Parameter(Mandatory = $true)][string]$ReleaseTag
    )
    if ($Resolution.State -cne 'Found' -or $null -eq $Resolution.Release) {
        throw "GitHub release '$ReleaseTag' is not uniquely available: $($Resolution.Message)"
    }
    $release = $Resolution.Release
    if ("$($release.id)" -notmatch '^[1-9][0-9]*$' -or "$($release.tag_name)" -cne $ReleaseTag -or
        [bool]$release.draft -or [bool]$release.prerelease) {
        throw "GitHub release '$ReleaseTag' is not an exact published ordinary release."
    }
    return $release
}

function Get-VtAuthenticatedWorkshopUploadResult {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$AssetName,
        [Parameter(Mandatory = $true)][byte[]]$ExpectedBytes,
        [Parameter(Mandatory = $true)][byte[]]$PublicationReceiptBytes,
        [Parameter(Mandatory = $true)][string]$Disposition,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    $asset = Get-GitHubReleaseAsset -Release $Release -Name $AssetName
    if ($null -eq $asset) { throw "Append-only Workshop result asset '$AssetName' is absent after persistence." }
    $actualBytes = Get-GitHubReleaseAssetBytes -Repo $Repo -Asset $asset -Request $Request
    if (-not (Test-VtWorkshopUploadResultBytesEqual $ExpectedBytes $actualBytes)) {
        throw "Append-only Workshop result asset '$AssetName' exists with different bytes."
    }
    $candidate = ConvertFrom-VtWorkshopUploadResultCandidateBytes $actualBytes $PublicationReceiptBytes
    return [pscustomobject][ordered]@{
        Ok = $true
        Authenticated = $true
        MayMutate = $true
        Disposition = $Disposition
        Repository = $Repo
        ReleaseTag = [string]$Release.tag_name
        ReleaseId = [string]$Release.id
        AssetName = $AssetName
        AssetId = [string]$asset.id
        AssetSha256 = Get-VtWorkshopUploadResultBytesSha256 $actualBytes
        Candidate = $candidate
    }
}

function Publish-VtWorkshopUploadResultCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)]$Candidate,
        [Parameter(Mandatory = $true)][byte[]]$PublicationReceiptBytes,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest}
    )
    $bytes = ConvertTo-VtWorkshopUploadResultCandidateBytes $Candidate $PublicationReceiptBytes
    if ($Repo -cne [string]$Candidate.repository -or $ReleaseTag -cne [string]$Candidate.release_tag) {
        throw 'Workshop result destination does not match its bound repository/release tag.'
    }
    $assetName = [string]$Candidate.candidate_asset_name
    $resolution = Resolve-GitHubReleaseByTag -Repo $Repo -Tag $ReleaseTag -Request $Request
    $release = Assert-VtWorkshopUploadResultRelease $resolution $ReleaseTag
    $existing = Get-GitHubReleaseAsset -Release $release -Name $assetName
    if ($null -ne $existing) {
        return Get-VtAuthenticatedWorkshopUploadResult -Repo $Repo -Release $release -AssetName $assetName `
            -ExpectedBytes $bytes -PublicationReceiptBytes $PublicationReceiptBytes `
            -Disposition 'ExistingExact' -Request $Request
    }

    $encodedName = [Uri]::EscapeDataString($assetName)
    $uploadUri = "https://uploads.github.com/repos/$Repo/releases/$($release.id)/assets?name=$encodedName"
    $uploaded = & $Request -Method POST -Uri $uploadUri -InputBytes $bytes -ContentType 'application/json'
    if ($uploaded.StatusCode -ne 201 -and $uploaded.StatusCode -ne 422) {
        throw "Append-only upload of '$assetName' failed with HTTP $($uploaded.StatusCode)."
    }

    # A 422 may be an exact concurrent create or a conflicting object.  Never
    # delete or replace it: the authoritative reread below decides which.
    $after = Resolve-GitHubReleaseByTag -Repo $Repo -Tag $ReleaseTag -Request $Request
    $afterRelease = Assert-VtWorkshopUploadResultRelease $after $ReleaseTag
    if ([string]$afterRelease.id -cne [string]$release.id) {
        throw "GitHub release '$ReleaseTag' changed identity during append-only persistence."
    }
    $disposition = if ($uploaded.StatusCode -eq 201) { 'CreatedAndReread' } else { 'ConcurrentExact' }
    return Get-VtAuthenticatedWorkshopUploadResult -Repo $Repo -Release $afterRelease -AssetName $assetName `
        -ExpectedBytes $bytes -PublicationReceiptBytes $PublicationReceiptBytes `
        -Disposition $disposition -Request $Request
}
