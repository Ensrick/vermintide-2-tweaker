# Canonical-ship-only receipt LOCAL deployment producer. No CLI, build, upload,
# manifest/pin mutation, remote deployment, or updater/recovery authorization.
. (Join-Path $PSScriptRoot 'publication-receipt.ps1')
. (Join-Path $PSScriptRoot 'publication-snapshot.ps1')
. (Join-Path $PSScriptRoot 'publication-authorization.ps1')
. (Join-Path $PSScriptRoot 'current-source-pin-recovery.ps1')
. (Join-Path $PSScriptRoot '..\publish-release\github-release-api.ps1')

function Assert-VtLocalDeploymentProducerOwner {
    param([string]$RepoRoot, [string]$Mod, [string]$SourceCommit, [string]$Version,
        [Parameter(Mandatory)]$TransactionLease)
    # Reuse the existing native lease/record/PID-start/job proof, not a new
    # caller-authored authorization flag. This helper performs no pin work.
    Assert-VtSourcePinRecoveryOwner -RepoRoot $RepoRoot -TransactionLease $TransactionLease
    if ($Mod -cnotmatch '\A[a-z][a-z0-9_]*\z' -or $TransactionLease.Mod -cne $Mod -or
        $SourceCommit -cnotmatch '\A[0-9a-f]{40}\z') {
        throw 'Local deployment receipt lost its exact ship mod/source identity.'
    }
    if ((Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse','HEAD') -Description 'Local deploy source HEAD') -cne $SourceCommit -or
        (Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('status','--porcelain','--untracked-files=all') -Description 'Local deploy clean source')) {
        throw 'Local deployment receipt requires clean exact reviewed source.'
    }
    & (Join-Path $PSScriptRoot 'claim.ps1') -Mod $Mod -Verify -ExpectedVersion $Version -RepoRoot $RepoRoot -Quiet
    if ($LASTEXITCODE -ne 0) { throw 'Local deployment receipt requires the exact live machine-global owner/version claim.' }
}

function Assert-VtLocalDeploymentRelease {
    param([Parameter(Mandatory)]$Release, [string]$ExpectedTag, [string]$ExpectedId,
        [Parameter(Mandatory)][string]$AssetName, [switch]$RequireAsset)
    if ($Release.id -isnot [long] -and $Release.id -isnot [int]) { throw 'Local deployment release ID must be an integer.' }
    if ($Release.id -le 0 -or [string]$Release.tag_name -cnotmatch '\Amods-[0-9]{4}-[0-9]{2}-[0-9]{2}\z' -or
        $Release.draft -isnot [bool] -or $Release.draft -or
        $Release.prerelease -isnot [bool] -or $Release.prerelease) {
        throw 'Local deployment requires an existing published canonical release.'
    }
    if (($ExpectedTag -and [string]$Release.tag_name -cne $ExpectedTag) -or
        ($ExpectedId -and [string]$Release.id -cne $ExpectedId)) {
        throw 'Local deployment release identity changed.'
    }
    $candidates = @($Release.assets | Where-Object { [string]$_.name -ieq $AssetName })
    if ($candidates.Count -gt 1 -or ($RequireAsset -and $candidates.Count -ne 1) -or
        ($candidates.Count -eq 1 -and [string]$candidates[0].name -cne $AssetName)) {
        throw 'Local deployment receipt asset is missing, duplicate, or case-aliased.'
    }
    if ($candidates.Count -eq 1) {
        $asset = $candidates[0]
        if (($asset.id -isnot [int] -and $asset.id -isnot [long]) -or $asset.id -le 0 -or
            ($asset.size -isnot [int] -and $asset.size -isnot [long]) -or $asset.size -lt 0 -or $asset.size -gt 1048576) {
            throw 'Local deployment receipt asset has invalid bounded metadata.'
        }
        # Do not trust an asset URL supplied by the response; the API helper
        # receives only the canonical fixed-repository coordinates below.
        return [pscustomobject]@{ id = $asset.id; name = $AssetName; size = $asset.size }
    }
    return $null
}

function New-VtHostedLocalDeploymentReceipt {
    [CmdletBinding()]
    param([string]$RepoRoot, [string]$Mod, [string]$Version, [string]$SourceCommit,
        [string]$PublishedId, [string]$ExpectedBuilderVersion,
        [Parameter(Mandatory)]$TransactionLease,
        [scriptblock]$Request = ${function:Invoke-GitHubReleaseApiRequest})
    Assert-VtLocalDeploymentProducerOwner -RepoRoot $RepoRoot -Mod $Mod -SourceCommit $SourceCommit -Version $Version -TransactionLease $TransactionLease
    $mutex = Enter-VtGitHubReleaseMutationMutex
    $primaryFailure = $null
    try {
        Assert-VtLocalDeploymentProducerOwner -RepoRoot $RepoRoot -Mod $Mod -SourceCommit $SourceCommit -Version $Version -TransactionLease $TransactionLease
        $snapshot = Get-VtPublicationSnapshot -RepoRoot $RepoRoot -SourceCommit $SourceCommit -Mod $Mod -ExpectedBuilderVersion $ExpectedBuilderVersion
        if ($snapshot.BundleAuthority -cne 'receipt' -or [string]$snapshot.PublishedId -cne $PublishedId) {
            throw 'Local deployment snapshot is not the exact receipt-authority target.'
        }
        $repo = 'Ensrick/vermintide-2-tweaker'
        $assetName = "deployment-receipt-$Mod.json"
        $response = & $Request -Method GET -Uri "https://api.github.com/repos/$repo/releases/latest"
        if ($response.StatusCode -ne 200) { throw 'No existing published release is available for a local deployment receipt.' }
        $release = ConvertFrom-GitHubReleaseJson -Response $response -Context 'local deployment receipt container'
        $null = Assert-VtLocalDeploymentRelease -Release $release -AssetName $assetName
        $authorization = Get-LivePublicationAuthorization -Repo $repo -SourceCommit $SourceCommit
        if (-not $authorization.Ok) { throw "Local deployment live authorization failed: $($authorization.Message)" }
        Assert-VtLocalDeploymentProducerOwner -RepoRoot $RepoRoot -Mod $Mod -SourceCommit $SourceCommit -Version $Version -TransactionLease $TransactionLease
        $receipt = New-WorkshopPublicationReceipt -RepoRoot $RepoRoot -Repository $repo -ReleaseTag $release.tag_name `
            -ReceiptAssetName $assetName -Mod $Mod -Version $Version -Owner (Get-CanonicalShipOwnerId -RepoRoot $RepoRoot) `
            -SourceCommit $SourceCommit -PublicationSnapshot $snapshot -AuthorizationEvidence $authorization.Evidence -LocalDeployment
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($receipt | ConvertTo-Json -Depth 12))
        if ($bytes.Length -gt 1048576) { throw 'Local deployment receipt exceeds the 1 MiB bound.' }
        $assetSnapshot = [pscustomobject]@{ Name = $assetName; Bytes = $bytes; ContentType = 'application/json' }
        # Exactly one scoped asset: no new release, draft publication, manifest,
        # zip, recovery tuple, or source-pin handoff is constructed here.
        $null = Publish-GitHubReleaseAssetsById -Repo $repo -Release $release -AssetSnapshots @($assetSnapshot) -Request $Request
        $tag = [Uri]::EscapeDataString([string]$release.tag_name)
        $readbackResponse = & $Request -Method GET -Uri "https://api.github.com/repos/$repo/releases/tags/$tag"
        if ($readbackResponse.StatusCode -ne 200) { throw 'Local deployment receipt release readback failed.' }
        $readbackRelease = ConvertFrom-GitHubReleaseJson -Response $readbackResponse -Context 'local deployment receipt readback'
        $asset = Assert-VtLocalDeploymentRelease -Release $readbackRelease -ExpectedTag $release.tag_name -ExpectedId ([string]$release.id) -AssetName $assetName -RequireAsset
        $hostedBytes = [byte[]](Get-GitHubReleaseAssetBytes -Repo $repo -Asset $asset -Request $Request)
        if ([Convert]::ToBase64String($hostedBytes) -cne [Convert]::ToBase64String($bytes)) { throw 'Hosted local deployment receipt bytes differ from the immutable candidate.' }
        $expires = [datetimeoffset]::ParseExact([string]$receipt.expires_at_utc, 'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal)
        if ([datetimeoffset]::UtcNow -ge $expires) { throw 'Local deployment receipt expired during hosting.' }
        return [pscustomobject]@{ Bytes = $bytes; Receipt = $receipt; Snapshot = $snapshot }
    }
    catch { $primaryFailure = $_; throw }
    finally {
        $cleanupFailure = $null
        try { $mutex.ReleaseMutex() } catch { $cleanupFailure = $_ }
        try { $mutex.Dispose() } catch { if ($null -eq $cleanupFailure) { $cleanupFailure = $_ } }
        if ($null -ne $cleanupFailure) {
            if ($null -eq $primaryFailure) { throw $cleanupFailure }
            # Cleanup always runs; an observer cannot mask the original error.
            try { Write-Warning "Local deployment receipt cleanup also failed: $($cleanupFailure.Exception.Message)" -WarningAction Continue } catch { }
        }
    }
}

function Write-VtLocalDeploymentReceiptHandoff {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    if ($Bytes.Length -eq 0 -or $Bytes.Length -gt 1048576) { throw 'Local deployment receipt handoff bytes are missing or oversized.' }
    $path = Join-Path ([IO.Path]::GetTempPath()) ('vt2-local-deployment-receipt-' + [guid]::NewGuid().ToString('N') + '.json')
    $stream = [IO.FileStream]::new($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
    catch { $stream.Dispose(); [IO.File]::Delete($path); throw }
    finally { $stream.Dispose() }
    return $path
}

function Assert-VtReceiptLocalDeploymentOutput {
    param([Parameter(Mandatory)]$Snapshot, [string]$DeployDirectory, [string]$Mod)
    if ($Snapshot.BundleAuthority -cne 'receipt' -or $null -eq $Snapshot.OutputSet -or
        [IO.Path]::GetFileName([IO.Path]::GetFullPath($DeployDirectory).TrimEnd('\','/')) -cne [string]$Snapshot.PublishedId) {
        throw 'Receipt local deployment verification requires the committed target and exact expected output set.'
    }
    $actual = Get-VtBundleOutputSet -BundleDirectory $DeployDirectory -ExpectedDescriptorName "$Mod.mod" `
        -ExpectedRootBundle $Snapshot.AuthorityProof.RootBundle -ExpectedDescriptorSha256 $Snapshot.SourceDescriptor.Sha256
    $problems = @(Compare-VtBundleOutputSets -Expected $Snapshot.OutputSet -Actual $actual -RequireLength $true `
        -ExpectedLabel 'committed local deployment output' -ActualLabel 'local Workshop target')
    if ($problems.Count) { throw ($problems -join '; ') }
    return [pscustomobject]@{ Count = @($actual.Files).Count; Fingerprint = $actual.Fingerprint }
}
