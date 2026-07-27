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

# Canonical success never touches the list fallback.
$normalCalls = [System.Collections.Generic.List[string]]::new()
$normalRequest = {
    param($Method, $Uri)
    $normalCalls.Add("$Method $Uri")
    return (New-Issue651FixtureResponse 200 ([pscustomobject]@{ id = 101; tag_name = $tag; assets = @() }))
}.GetNewClosure()
$normal = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $normalRequest
Assert-ReleaseFixture ($normal.State -eq 'Found' -and $normal.Route -eq 'tag' -and $normal.Release.id -eq 101) 'normal tag endpoint resolves release'
Assert-ReleaseFixture ($normalCalls.Count -eq 1 -and $normalCalls[0] -match '/releases/tags/') 'normal lookup does not call list endpoint'

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
    return (New-Issue651FixtureResponse 200 @(
        [pscustomobject]@{ id = 202; tag_name = 'mods-2026-07-15'; assets = @() },
        [pscustomobject]@{ id = 203; tag_name = $tag; assets = @([pscustomobject]@{ id = 901; name = 'manifest.json' }) }
    ))
}.GetNewClosure()
$fallback = Resolve-GitHubReleaseByTag -Repo $repo -Tag $tag -Request $fallbackRequest
Assert-ReleaseFixture ($fallback.State -eq 'Found' -and $fallback.Route -eq 'list-fallback' -and $fallback.Release.id -eq 203) '503 fallback finds exact tag in releases list'
Assert-ReleaseFixture ($fallback.Message -match 'degraded' -and $fallback.TagStatus -eq 503) '503 fallback reports degraded route distinctly'

# Pagination is bounded but can find the exact tag after a full first page.
$pageOne = @()
for ($i = 1; $i -le 100; $i++) { $pageOne += [pscustomobject]@{ id = $i; tag_name = "old-$i"; assets = @() } }
$paginationRequest = {
    param($Method, $Uri)
    if ($Uri -match '/releases/tags/') { return (New-Issue651FixtureResponse 503 $null) }
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

# Asset selection is case-sensitive, unique, and asset-id based for downloads.
$assetRelease = [pscustomobject]@{
    id = 404
    assets = @(
        [pscustomobject]@{ id = 501; name = 'manifest.json'; url = 'https://api.github.com/repos/Owner/Repo/releases/assets/501' },
        [pscustomobject]@{ id = 502; name = 'Manifest.json'; url = 'https://api.github.com/repos/Owner/Repo/releases/assets/502' }
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
    $downloadRequest = {
        param($Method, $Uri, $Accept)
        $downloadUris.Add($Uri)
        return [pscustomobject]@{
            StatusCode = 200
            Content = '{"ok":true}'
            Bytes = [System.Text.Encoding]::UTF8.GetBytes('{"ok":true}')
            Error = $null
        }
    }.GetNewClosure()
    Save-GitHubReleaseAsset -Repo $repo -Asset $selected -Destination $downloadPath -Request $downloadRequest
    Assert-ReleaseFixture ((Test-Path -LiteralPath $downloadPath) -and $downloadUris[0] -match '/releases/assets/501$' -and $downloadUris[0] -notmatch '/tags/') 'asset download uses resolved asset id, never tag route'

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
