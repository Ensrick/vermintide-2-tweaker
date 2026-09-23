# check_github_release_fallback.ps1 - offline fixtures for issue #651.

[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\publish-release\github-release-api.ps1')

$script:passed = 0
$script:failed = 0
function Assert-ReleaseFixture {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        $script:passed++
        if (-not $Quiet) { Write-Host "  [PASS] $Name" -ForegroundColor Green }
    } else {
        $script:failed++
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
    }
}

function global:New-Issue651FixtureResponse {
    param([int]$StatusCode, $Value)
    $content = if ($null -eq $Value) { '' } else { ConvertTo-Json -InputObject $Value -Depth 8 -Compress }
    return [pscustomobject]@{
        StatusCode = $StatusCode
        Content = $content
        Bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
        Error = $null
    }
}

$repo = 'Owner/Repo'
$tag = 'mods-2026-07-16'

# Transfer budgets keep metadata and small payloads at the established 30 s
# floor, while uploads and downloads share the established size-based curve.
Assert-ReleaseFixture ((Get-GitHubReleaseRequestTimeoutSeconds) -eq 30) 'metadata request keeps 30-second timeout floor'
Assert-ReleaseFixture ((Get-GitHubReleaseRequestTimeoutSeconds -ExpectedResponseBytes 60184623) -eq 230) '60 MB asset download timeout scales from declared size'
$uploadFixtureBytes = [byte[]]::new(8388608)
Assert-ReleaseFixture ((Get-GitHubReleaseRequestTimeoutSeconds -InputBytes $uploadFixtureBytes) -eq 32) 'asset upload timeout keeps existing input-byte scaling'
Assert-ReleaseFixture ((Get-GitHubReleaseRequestTimeoutSeconds -InputBytes $uploadFixtureBytes -ExpectedResponseBytes 10485760) -eq 40) 'request timeout uses larger transfer direction when both sizes are known'
$uploadFixtureBytes = $null
Assert-ReleaseFixture ((Get-GitHubReleaseRequestTimeoutSeconds -ExpectedResponseBytes ([int]::MaxValue)) -eq 3600) 'large valid download timeout retains one-hour cap'

# Canonical success never touches the list fallback. The resolved release's
# asset inventory is refreshed from GET /releases/{id}/assets (2026-09-23).
$normalCalls = [System.Collections.Generic.List[string]]::new()
$normalRequest = {
    param($Method, $Uri)
    $normalCalls.Add("$Method $Uri")
    if ($Uri -match '/releases/101/assets\?per_page=100&page=1$') { return (New-Issue651FixtureResponse 200 @()) }
    return (New-Issue651FixtureResponse 200 ([pscustomobject]@{ id = 101; tag_name = $tag; assets = @() }))
}.GetNewClosure()
$normal = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $normalRequest
Assert-ReleaseFixture ($normal.State -eq 'Found' -and $normal.Route -eq 'tag' -and $normal.Release.id -eq 101) 'normal tag endpoint resolves release'
Assert-ReleaseFixture ($normalCalls.Count -eq 2 -and $normalCalls[0] -match '/releases/tags/' -and
    $normalCalls[1] -match '/releases/101/assets\?per_page=100&page=1$' -and
    -not (($normalCalls -join "`n") -match '/releases\?per_page=')) 'normal lookup refreshes assets by release id and never calls the list endpoint'

# A canonical 404 is confirmed against the list before it authorizes creation.
$notFoundCalls = [System.Collections.Generic.List[string]]::new()
$notFoundRequest = {
    param($Method, $Uri)
    $notFoundCalls.Add("$Method $Uri")
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 404 $null) }
    return (New-Issue651FixtureResponse 200 @())
}.GetNewClosure()
$notFound = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $notFoundRequest
Assert-ReleaseFixture ($notFound.State -eq 'Absent' -and $notFound.Route -eq 'list-fallback' -and $notFoundCalls.Count -eq 2) '404 plus complete list is distinguished as release absent'

$false404Request = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 404 $null) }
    if ($Uri -match '/releases/151/assets\?') { return (New-Issue651FixtureResponse 200 @()) }
    return (New-Issue651FixtureResponse 200 @([pscustomobject]@{ id = 151; tag_name = $tag; assets = @() }))
}.GetNewClosure()
$false404 = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $false404Request
Assert-ReleaseFixture ($false404.State -eq 'Found' -and $false404.Release.id -eq 151) 'list exact match prevents duplicate release after route-specific 404'

# A transient 503 falls back to the list and matches tag_name exactly.
$fallbackCalls = [System.Collections.Generic.List[string]]::new()
$fallbackRequest = {
    param($Method, $Uri)
    $fallbackCalls.Add("$Method $Uri")
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 503 $null) }
    if ($Uri -match '/releases/203/assets\?') {
        return (New-Issue651FixtureResponse 200 @([pscustomobject]@{ id = 901; name = 'manifest.json'; size = 1 }))
    }
    return (New-Issue651FixtureResponse 200 @(
        [pscustomobject]@{ id = 202; tag_name = 'mods-2026-07-15'; assets = @() },
        [pscustomobject]@{ id = 203; tag_name = $tag; assets = @([pscustomobject]@{ id = 901; name = 'manifest.json' }) }
    ))
}.GetNewClosure()
$fallback = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $fallbackRequest
Assert-ReleaseFixture ($fallback.State -eq 'Found' -and $fallback.Route -eq 'list-fallback' -and $fallback.Release.id -eq 203) '503 fallback finds exact tag in releases list'
Assert-ReleaseFixture ($fallback.AssetInventory -eq 'release-id' -and @($fallback.Release.assets).Count -eq 1 -and $fallback.Release.assets[0].id -eq 901) 'list-fallback release also refreshes its asset inventory by release id'
Assert-ReleaseFixture ($fallback.Message -match 'degraded' -and $fallback.TagStatus -eq 503) '503 fallback reports degraded route distinctly'

# Pagination is bounded but can find the exact tag after a full first page.
$pageOne = @()
for ($i = 1; $i -le 100; $i++) { $pageOne += [pscustomobject]@{ id = $i; tag_name = "old-$i"; assets = @() } }
$paginationRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 503 $null) }
    if ($Uri -match '/releases/303/assets\?') { return (New-Issue651FixtureResponse 200 @()) }
    if ($Uri -match 'page=1(?:&|$)') { return (New-Issue651FixtureResponse 200 $pageOne) }
    return (New-Issue651FixtureResponse 200 @([pscustomobject]@{ id = 303; tag_name = $tag; assets = @() }))
}.GetNewClosure()
$paged = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $paginationRequest -MaxPages 3 -PerPage 100
Assert-ReleaseFixture ($paged.State -eq 'Found' -and $paged.PagesScanned -eq 2 -and $paged.Release.id -eq 303) 'bounded pagination reaches later exact match'

# A complete short page with no exact match is absent; full-page exhaustion is
# unavailable because the release may exist beyond the bound.
$emptyRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 503 $null) }
    return (New-Issue651FixtureResponse 200 @())
}.GetNewClosure()
$noTag = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $emptyRequest
Assert-ReleaseFixture ($noTag.State -eq 'Absent' -and $noTag.Route -eq 'list-fallback') 'complete fallback list distinguishes absent tag'

$fullPagesRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 503 $null) }
    return (New-Issue651FixtureResponse 200 @(
        [pscustomobject]@{ id = 1; tag_name = 'other-a'; assets = @() },
        [pscustomobject]@{ id = 2; tag_name = 'other-b'; assets = @() }
    ))
}.GetNewClosure()
$exhausted = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $fullPagesRequest -MaxPages 2 -PerPage 2
Assert-ReleaseFixture ($exhausted.State -eq 'Unavailable' -and $exhausted.PagesScanned -eq 2) 'pagination exhaustion never claims release absent'

$ambiguousRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 503 $null) }
    return (New-Issue651FixtureResponse 200 @(
        [pscustomobject]@{ id = 1; tag_name = $tag; assets = @() },
        [pscustomobject]@{ id = 2; tag_name = $tag; assets = @() }
    ))
}.GetNewClosure()
$ambiguous = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $ambiguousRequest
Assert-ReleaseFixture ($ambiguous.State -eq 'Unavailable' -and $ambiguous.Message -match 'multiple exact') 'ambiguous exact matches block mutation'

# 2026-09-23 shape: the tag route embeds manifest.json as ghost asset id
# 583157616 (HTTP 404 on read, download, and delete) while
# GET /releases/394315644/assets serves the live id 583314449. Resolution must
# replace the embedded inventory so downloads and clobbers use the live id.
$ghostCalls = [System.Collections.Generic.List[string]]::new()
$ghostManifestBytes = [System.Text.Encoding]::UTF8.GetBytes('{"mods":[{"mod_id":"gut_dev","version":"0.2.357-dev"}]}')
$ghostRequest = {
    param($Method, $Uri, $Accept)
    $ghostCalls.Add("$Method $Uri")
    if ($Uri -match '/releases/tags/') {
        return (New-Issue651FixtureResponse 200 ([pscustomobject]@{
            id = 394315644; tag_name = $tag
            assets = @([pscustomobject]@{ id = 583157616; name = 'manifest.json'; size = 75000; url = 'https://api.github.com/repos/Owner/Repo/releases/assets/583157616' })
        }))
    }
    if ($Uri -match '/releases/394315644/assets\?per_page=100&page=1$') {
        return (New-Issue651FixtureResponse 200 @(
            [pscustomobject]@{ id = 583314449; name = 'manifest.json'; size = $ghostManifestBytes.LongLength; url = 'https://api.github.com/repos/Owner/Repo/releases/assets/583314449' }
        ))
    }
    if ($Uri -match '/releases/assets/583157616$') { return (New-Issue651FixtureResponse 404 $null) }
    if ($Uri -match '/releases/assets/583314449$') {
        return [pscustomobject]@{ StatusCode = 200; Content = ''; Bytes = $ghostManifestBytes; Error = $null }
    }
    return (New-Issue651FixtureResponse 500 $null)
}.GetNewClosure()
$ghost = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $ghostRequest
Assert-ReleaseFixture ($ghost.State -eq 'Found' -and $ghost.AssetInventory -eq 'release-id' -and
    @($ghost.Release.assets).Count -eq 1 -and $ghost.Release.assets[0].id -eq 583314449) 'stale embedded ghost asset is replaced by the release-id assets inventory'
$ghostAsset = Get-GitHubReleaseAsset -Release $ghost.Release -Name 'manifest.json'
$ghostError = $null
$ghostBytes = $null
try { $ghostBytes = Get-GitHubReleaseAssetBytes -Repo $repo -Asset $ghostAsset -Request $ghostRequest }
catch { $ghostError = $_.Exception.Message }
Assert-ReleaseFixture ($null -eq $ghostError -and $ghostAsset.id -eq 583314449 -and
    $null -ne $ghostBytes -and [System.Text.Encoding]::UTF8.GetString($ghostBytes) -match 'gut_dev') "manifest download uses the live asset id, never the 404 ghost id [$ghostError]"
Assert-ReleaseFixture (-not (($ghostCalls -join "`n") -match '/releases/assets/583157616')) 'ghost asset id is never requested'

# The assets endpoint pages at 100 rows; a full first page must not truncate.
$pagedAssetsPageOne = @()
for ($i = 1; $i -le 100; $i++) { $pagedAssetsPageOne += [pscustomobject]@{ id = 700000 + $i; name = "mod$i.zip"; size = 1 } }
$pagedAssetsRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 200 ([pscustomobject]@{ id = 505; tag_name = $tag; assets = @() })) }
    if ($Uri -match '/releases/505/assets\?per_page=100&page=1$') { return (New-Issue651FixtureResponse 200 $pagedAssetsPageOne) }
    if ($Uri -match '/releases/505/assets\?per_page=100&page=2$') {
        return (New-Issue651FixtureResponse 200 @([pscustomobject]@{ id = 700101; name = 'manifest.json'; size = 2 }))
    }
    return (New-Issue651FixtureResponse 500 $null)
}.GetNewClosure()
$pagedAssets = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $pagedAssetsRequest
Assert-ReleaseFixture ($pagedAssets.State -eq 'Found' -and @($pagedAssets.Release.assets).Count -eq 101 -and
    (Get-GitHubReleaseAsset -Release $pagedAssets.Release -Name 'manifest.json').id -eq 700101) 'asset inventory refresh paginates past a full first page'

# A failed refresh keeps the embedded array (offline fakes that only serve the
# tag route keep working) and warns exactly once per script.
$script:GitHubReleaseAssetInventoryWarned = $false
$degradedAssetsRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') {
        return (New-Issue651FixtureResponse 200 ([pscustomobject]@{
            id = 606; tag_name = $tag; assets = @([pscustomobject]@{ id = 61; name = 'manifest.json'; size = 2 })
        }))
    }
    return (New-Issue651FixtureResponse 503 $null)
}.GetNewClosure()
$degradedWarningsFirst = @()
$degraded = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $degradedAssetsRequest `
    -WarningVariable degradedWarningsFirst -WarningAction SilentlyContinue
$degradedWarningsSecond = @()
$null = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $degradedAssetsRequest `
    -WarningVariable degradedWarningsSecond -WarningAction SilentlyContinue
Assert-ReleaseFixture ($degraded.State -eq 'Found' -and $degraded.AssetInventory -eq 'embedded' -and
    @($degraded.Release.assets).Count -eq 1 -and $degraded.Release.assets[0].id -eq 61 -and
    $degraded.Message -match 'HTTP 503; embedded asset inventory retained') 'assets endpoint outage falls back to the embedded array'
Assert-ReleaseFixture (@($degradedWarningsFirst).Count -eq 1 -and @($degradedWarningsSecond).Count -eq 0 -and
    "$($degradedWarningsFirst[0])" -match 'embedded asset array') 'embedded-array fallback warns exactly once'

# The latest-release list entry (base-manifest fallback) refreshes the same way.
$latestRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases\?per_page=') {
        return (New-Issue651FixtureResponse 200 @([pscustomobject]@{
            id = 808; tag_name = 'mods-2026-07-15'; draft = $false; prerelease = $false
            assets = @([pscustomobject]@{ id = 583157616; name = 'manifest.json'; size = 1 })
        }))
    }
    if ($Uri -match '/releases/808/assets\?') {
        return (New-Issue651FixtureResponse 200 @([pscustomobject]@{ id = 583314449; name = 'manifest.json'; size = 1 }))
    }
    return (New-Issue651FixtureResponse 500 $null)
}.GetNewClosure()
$latest = Get-GitHubLatestReleaseFromList -Repo $repo -Request $latestRequest
Assert-ReleaseFixture ($latest.id -eq 808 -and @($latest.assets).Count -eq 1 -and $latest.assets[0].id -eq 583314449) 'latest-release list entry refreshes its asset inventory by release id'

# Asset selection is case-sensitive, unique, and asset-id based for downloads.
$downloadFixtureBytes = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')
$assetRelease = [pscustomobject]@{
    id = 404
    assets = @(
        [pscustomobject]@{ id = 501; name = 'manifest.json'; url = 'https://api.github.com/repos/Owner/Repo/releases/assets/501'; size = $downloadFixtureBytes.LongLength },
        [pscustomobject]@{ id = 502; name = 'Manifest.json'; url = 'https://api.github.com/repos/Owner/Repo/releases/assets/502'; size = 0 }
    )
}
$selected = Get-GitHubReleaseAsset -Release $assetRelease -Name 'manifest.json'
Assert-ReleaseFixture ($selected.id -eq 501) 'asset lookup uses exact case-sensitive name'
Assert-ReleaseFixture ($null -eq (Get-GitHubReleaseAsset -Release $assetRelease -Name 'missing.zip')) 'missing asset lookup returns null'

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-release-651-" + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempRoot)
try {
    $downloadPath = Join-Path $tempRoot 'manifest.json'
    $downloadUris = [System.Collections.Generic.List[string]]::new()
    $downloadExpectedSizes = [System.Collections.Generic.List[long]]::new()
    $downloadRequest = {
        param($Method, $Uri, $Accept)
        $downloadUris.Add($Uri)
        # Keep the original three-parameter fixture signature: optional request
        # hints remain compatible and arrive in the ordinary extra-argument bag.
        if ($args.Count -eq 2 -and $args[0] -eq '-ExpectedResponseBytes') {
            $downloadExpectedSizes.Add([long]$args[1])
        }
        return [pscustomobject]@{
            StatusCode = 200
            Content = '{"ok":true}'
            Bytes = $downloadFixtureBytes
            Error = $null
        }
    }.GetNewClosure()
    Save-GitHubReleaseAsset -Repo $repo -Asset $selected -Destination $downloadPath -Request $downloadRequest
    Assert-ReleaseFixture ((Test-Path -LiteralPath $downloadPath) -and $downloadUris[0] -match '/releases/assets/501$' -and $downloadUris[0] -notmatch '/tags/') 'asset download uses resolved asset id, never tag route'
    Assert-ReleaseFixture ($downloadExpectedSizes.Count -eq 1 -and $downloadExpectedSizes[0] -eq $downloadFixtureBytes.LongLength) 'asset download forwards trusted metadata size without breaking injected fixture'

    $invalidSizeCases = @(
        [pscustomobject]@{ Label = 'malformed'; Value = 'sixty-megabytes'; Pattern = 'non-negative integer' },
        [pscustomobject]@{ Label = 'negative'; Value = -1; Pattern = 'non-negative integer' },
        [pscustomobject]@{ Label = 'excessive'; Value = ([long][int]::MaxValue + [long]1); Pattern = 'exceeds the supported' }
    )
    foreach ($case in $invalidSizeCases) {
        $invalidCalls = [System.Collections.Generic.List[string]]::new()
        $invalidRequest = {
            param($Method, $Uri, $Accept)
            $invalidCalls.Add("$Method $Uri")
            return (New-Issue651FixtureResponse 200 $null)
        }.GetNewClosure()
        $invalidAsset = [pscustomobject]@{
            id = 590
            name = "$($case.Label).zip"
            url = 'https://api.github.com/repos/Owner/Repo/releases/assets/590'
            size = $case.Value
        }
        $invalidError = $null
        try { $null = Get-GitHubReleaseAssetBytes -Repo $repo -Asset $invalidAsset -Request $invalidRequest }
        catch { $invalidError = $_.Exception.Message }
        Assert-ReleaseFixture ($invalidError -match $case.Pattern -and $invalidCalls.Count -eq 0) "$($case.Label) asset size fails closed before request"
    }

    $missingSizeCalls = [System.Collections.Generic.List[string]]::new()
    $missingSizeRequest = {
        param($Method, $Uri, $Accept)
        $missingSizeCalls.Add("$Method $Uri")
        return (New-Issue651FixtureResponse 200 $null)
    }.GetNewClosure()
    $missingSizeAsset = [pscustomobject]@{ id = 591; name = 'missing-size.zip' }
    $missingSizeError = $null
    try { $null = Get-GitHubReleaseAssetBytes -Repo $repo -Asset $missingSizeAsset -Request $missingSizeRequest }
    catch { $missingSizeError = $_.Exception.Message }
    Assert-ReleaseFixture ($missingSizeError -match 'size is missing' -and $missingSizeCalls.Count -eq 0) 'missing asset size fails closed before request'

    $lengthMismatchAsset = [pscustomobject]@{ id = 592; name = 'truncated.zip'; size = 4 }
    $lengthMismatchRequest = {
        param($Method, $Uri, $Accept)
        return [pscustomobject]@{ StatusCode = 200; Content = ''; Bytes = [byte[]](1, 2, 3); Error = $null }
    }
    $lengthMismatchError = $null
    try { $null = Get-GitHubReleaseAssetBytes -Repo $repo -Asset $lengthMismatchAsset -Request $lengthMismatchRequest }
    catch { $lengthMismatchError = $_.Exception.Message }
    Assert-ReleaseFixture ($lengthMismatchError -match 'returned 3 bytes.*declared 4') 'downloaded bytes must match trusted metadata size'

    $transportFailureAsset = [pscustomobject]@{ id = 593; name = 'timeout.zip'; size = 4 }
    $transportFailureRequest = {
        param($Method, $Uri, $Accept)
        return [pscustomobject]@{
            StatusCode = 0
            Content = ''
            Bytes = [byte[]]@()
            Error = "request canceled`r`nBearer fixture-secret"
        }
    }
    $transportFailureError = $null
    try { $null = Get-GitHubReleaseAssetBytes -Repo $repo -Asset $transportFailureAsset -Request $transportFailureRequest }
    catch { $transportFailureError = $_.Exception.Message }
    Assert-ReleaseFixture ($transportFailureError -match 'HTTP 0: request canceled Bearer \[REDACTED\]' -and
        $transportFailureError -notmatch 'fixture-secret') 'HTTP 0 surfaces bounded transport detail without bearer token'

    $zipPath = Join-Path $tempRoot 'WOC.zip'
    $manifestPath = Join-Path $tempRoot 'manifest.json'
    $receiptPath = Join-Path $tempRoot 'publication-receipt-modx.json'
    [System.IO.File]::WriteAllBytes($zipPath, [byte[]](1, 2, 3))
    [System.IO.File]::WriteAllBytes($manifestPath, [System.Text.Encoding]::UTF8.GetBytes('{}'))
    $receiptOriginal = [System.Text.Encoding]::UTF8.GetBytes('{"schema":2}')
    [System.IO.File]::WriteAllBytes($receiptPath, $receiptOriginal)
    $receiptSha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $receiptOriginalHash = [System.BitConverter]::ToString($receiptSha.ComputeHash($receiptOriginal)).Replace('-', '').ToLowerInvariant()
    }
    finally { $receiptSha.Dispose() }
    $mutationCalls = [System.Collections.Generic.List[string]]::new()
    $uploadedHashes = @{}
    $pathsMutated = $false
    $mutationRequest = {
        param($Method, $Uri, [byte[]]$InputBytes, $ContentType)
        $mutationCalls.Add("$Method $Uri")
        if (-not $pathsMutated -and $Method -eq 'DELETE') {
            $pathsMutated = $true
            [System.IO.File]::WriteAllBytes($zipPath, [byte[]](9, 9, 9))
            [System.IO.File]::WriteAllBytes($manifestPath, [System.Text.Encoding]::UTF8.GetBytes('{"mutated":true}'))
            [System.IO.File]::WriteAllBytes($receiptPath, [System.Text.Encoding]::UTF8.GetBytes('{"schema":999}'))
        }
        if ($Method -eq 'POST') {
            $name = [System.Uri]::UnescapeDataString(($Uri -split 'name=')[-1])
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $uploadedHashes[$name] = [System.BitConverter]::ToString($sha.ComputeHash($InputBytes)).Replace('-', '').ToLowerInvariant()
            }
            finally { $sha.Dispose() }
        }
        $status = if ($Method -eq 'DELETE') { 204 } else { 201 }
        return (New-Issue651FixtureResponse $status $null)
    }.GetNewClosure()
    $mutationRelease = [pscustomobject]@{
        id = 777
        assets = @(
            [pscustomobject]@{ id = 601; name = 'WOC.zip' },
            [pscustomobject]@{ id = 602; name = 'manifest.json' },
            [pscustomobject]@{ id = 603; name = 'publication-receipt-modx.json' }
        )
    }
    $null = Publish-GitHubReleaseAssetsById -Repo $repo -Release $mutationRelease `
        -AssetPaths @($manifestPath, $zipPath, $receiptPath) -Request $mutationRequest
    $joinedMutations = $mutationCalls -join "`n"
    Assert-ReleaseFixture ($mutationCalls.Count -eq 6 -and $joinedMutations -match 'DELETE .*/assets/601' -and $joinedMutations -match 'POST .*/releases/777/assets\?name=WOC.zip') 'clobber replaces only exact requested asset by release id'
    Assert-ReleaseFixture ($joinedMutations -match 'DELETE .*/assets/603' -and $joinedMutations -match 'POST .*/releases/777/assets\?name=publication-receipt-modx.json') 'receipt replacement uses the exact release asset id'
    Assert-ReleaseFixture ($mutationCalls[4] -match 'DELETE .*/assets/602' -and $mutationCalls[5] -match 'POST .*/releases/777/assets\?name=manifest.json') 'manifest upload is forced after replacement zip and receipt'
    Assert-ReleaseFixture (-not (($mutationCalls -join "`n") -match '/releases/tags/')) 'release-id mutation never reuses broken tag route'
    Assert-ReleaseFixture ($uploadedHashes['WOC.zip'] -eq '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81') 'zip upload uses immutable pre-mutation bytes'
    Assert-ReleaseFixture ($uploadedHashes['publication-receipt-modx.json'] -eq $receiptOriginalHash) 'receipt upload uses immutable pre-mutation bytes'
    Assert-ReleaseFixture ($uploadedHashes['manifest.json'] -eq '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a') 'manifest upload uses immutable pre-mutation bytes'

    $draftCalls = [System.Collections.Generic.List[string]]::new()
    $draftRequest = {
        param($Method, $Uri, [byte[]]$InputBytes, $ContentType)
        $body = if ($null -ne $InputBytes) { [System.Text.Encoding]::UTF8.GetString($InputBytes) } else { '' }
        $draftCalls.Add("$Method $Uri $body")
        if ($Method -eq 'POST') {
            return (New-Issue651FixtureResponse 201 ([pscustomobject]@{
                id = 888; tag_name = $tag; draft = $true; assets = @()
            }))
        }
        return (New-Issue651FixtureResponse 200 ([pscustomobject]@{
            id = 888; tag_name = $tag; draft = $false; assets = @()
        }))
    }.GetNewClosure()
    $draft = New-GitHubDraftRelease -Repo $repo -Tag $tag -Title 'fixture' -Notes 'fixture notes' -Request $draftRequest
    $published = Publish-GitHubDraftRelease -Repo $repo -Release $draft -Request $draftRequest
    Assert-ReleaseFixture ($draft.id -eq 888 -and $draft.draft) 'new release is created as an exact draft before asset upload'
    Assert-ReleaseFixture ($published.id -eq 888 -and -not $published.draft -and
        $draftCalls[1] -match '^PATCH .*releases/888 .*"draft":false') 'draft is published by exact release id only after uploads'
}
finally {
    Get-ChildItem -LiteralPath $tempRoot -File -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot }
}

if ($script:failed -gt 0) {
    Write-Host "[check_github_release_fallback] FAILED -- $script:failed fixture(s) failed." -ForegroundColor Red
    exit 2
}
if (-not $Quiet) { Write-Host "[check_github_release_fallback] OK -- $script:passed offline fixtures passed." -ForegroundColor Green }
exit 0
