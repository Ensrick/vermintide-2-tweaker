# tools/publish-release/publish-release.ps1
#
# Builds published VMB mods, zips each bundleV2/ directory, generates a manifest.json,
# and pushes the set as a GitHub release on Ensrick/vermintide-2-tweaker. The
# vt2-mod-updater tool consumes the release manifest to deploy bundles into friends' Steam
# Workshop folders.
#
# Internal publication component. Routine releases enter through
# tools\ship\ship.ps1, which supplies exact publication authorization and
# launcher provenance. Direct invocation without that evidence fails closed.
#   .\publish-release.ps1 -LauncherPath <exe> -LauncherSource <source> -LauncherApprovalAnchor <path>
#                                               # exact approved dependency handoff from ship.ps1
#
# Two modes (issues #436/#493):
#   * FULL (no -Mods)  - build-gate every source-commit inventory mod, then stage exact
#     authority-selected bytes and write one complete manifest.
#   * FILTERED (-Mods) - build-gate/stage/upload only the named mods. Sibling manifest entries are
#     carried VERBATIM from the release's existing manifest (version + sha256 of what was
#     ACTUALLY published - a mid-edit sibling can neither fail this publish nor get a mislabeled
#     asset). If the tag's release doesn't exist yet, sibling ZIPS are carried forward from the
#     latest release so the new release stays self-contained (vt2-mod-updater resolves every
#     asset_filename against ONE release). Filtered mode therefore needs network even with
#     -DryRun (it must read the existing manifest), and needs at least one prior full release.
#
# Requires: gh CLI authenticated to github.com (Ensrick); VMBLauncher.exe in an approved
# invoking/configured/primary/env location. Does NOT upload to Steam Workshop - that is
# still VMBLauncher's job.

[CmdletBinding()]
param(
    [string]$Tag,
    [switch]$SkipBuild,
    [switch]$DryRun,
    [string[]]$Mods,
    [string]$PublicationAuthorizationJson,
    [string]$PublicationReceiptOutputPath,
    [hashtable]$SourcePinHandoff,
    [string]$LauncherPath,
    [string]$LauncherSource,
    [string]$LauncherApprovalAnchor,
    [object]$LauncherExecutableLease
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$transactionLeaseHelpers = Join-Path $repoRoot 'tools\ship\transaction-lease.ps1'
if (-not (Test-Path -LiteralPath $transactionLeaseHelpers -PathType Leaf)) {
    throw "Machine transaction lease helpers not found at $transactionLeaseHelpers."
}
. $transactionLeaseHelpers
$launcherPathHelpers = Join-Path $repoRoot 'tools\vmb-launcher-path.ps1'
if (-not (Test-Path -LiteralPath $launcherPathHelpers -PathType Leaf)) {
    throw "Shared VMBLauncher path helpers not found at $launcherPathHelpers."
}
. $launcherPathHelpers
$manifestHelpers = Join-Path $PSScriptRoot 'release-manifest.ps1'
if (-not (Test-Path -LiteralPath $manifestHelpers)) {
    throw "Release-manifest helpers not found at $manifestHelpers."
}
. $manifestHelpers
$publicationAuthorizationHelpers = Join-Path $repoRoot 'tools\ship\publication-authorization.ps1'
if (-not (Test-Path -LiteralPath $publicationAuthorizationHelpers -PathType Leaf)) {
    throw "Publication authorization helpers not found at $publicationAuthorizationHelpers."
}
. $publicationAuthorizationHelpers
$publicationReceiptHelpers = Join-Path $repoRoot 'tools\ship\publication-receipt.ps1'
if (-not (Test-Path -LiteralPath $publicationReceiptHelpers -PathType Leaf)) {
    throw "Publication receipt helpers not found at $publicationReceiptHelpers."
}
. $publicationReceiptHelpers
$publicationSnapshotHelpers = Join-Path $repoRoot 'tools\ship\publication-snapshot.ps1'
if (-not (Test-Path -LiteralPath $publicationSnapshotHelpers -PathType Leaf)) {
    throw "Publication snapshot helpers not found at $publicationSnapshotHelpers."
}
. $publicationSnapshotHelpers
$pinFinalizationHelpers = Join-Path $repoRoot 'tools\ship\exception-pin-finalization.ps1'
. $pinFinalizationHelpers
$githubReleaseHelpers = Join-Path $PSScriptRoot 'github-release-api.ps1'
if (-not (Test-Path -LiteralPath $githubReleaseHelpers)) {
    throw "GitHub release helpers not found at $githubReleaseHelpers."
}
. $githubReleaseHelpers
. (Join-Path $PSScriptRoot 'release-mutation-lock.ps1')
$launcherSettings = Join-Path $env:APPDATA 'VMBLauncher\settings.json'
$configuredProjectRoot = Get-VmbLauncherConfiguredProjectRoot -SettingsPath $launcherSettings
$primaryWorktreeRoot = Get-VmbLauncherPrimaryWorktreeRoot -RepoRoot $repoRoot
$launcherResolution = Resolve-ApprovedVmbLauncherPath `
    -RepoRoot $repoRoot `
    -RequestedPath $LauncherPath `
    -RequestedSource $LauncherSource `
    -RequestedApprovalAnchor $LauncherApprovalAnchor `
    -ConfiguredProjectRoot $configuredProjectRoot `
    -PrimaryWorktreeRoot $primaryWorktreeRoot `
    -EnvironmentPath $env:VT2_SHIP_VMB_LAUNCHER
$launcher = $launcherResolution.Path
$effectiveLauncherLease = $null
$ownsLauncherExecutableLease = $false
$stage = $null
$releaseTransactionLease = $null
try {
if ($null -ne $LauncherExecutableLease) {
    $builderProof = Assert-VmbLauncherExecutableLease `
        -Lease $LauncherExecutableLease `
        -ExpectedRequestedPath $launcherResolution.Path `
        -VerifyContent
    $effectiveLauncherLease = $LauncherExecutableLease
}
else {
    if ($SkipBuild) {
        throw '-SkipBuild requires the live VMBLauncher executable lease from canonical ship.ps1.'
    }
    $effectiveLauncherLease = Enter-VmbLauncherExecutableLease `
        -LauncherPath $launcherResolution.Path -RequireDirectPath
    $ownsLauncherExecutableLease = $true
    $builderProof = Assert-VmbLauncherExecutableLease `
        -Lease $effectiveLauncherLease `
        -ExpectedRequestedPath $launcherResolution.Path `
        -VerifyContent
}
$sourceCommit = Get-ReleaseSourceCommit -RepoRoot $repoRoot
$ghRepo = 'Ensrick/vermintide-2-tweaker'

$callerAuthorization = $null
if ([string]::IsNullOrWhiteSpace($PublicationAuthorizationJson)) {
    throw 'PublicationAuthorizationJson correlation evidence is required. It is never trusted without an independent live GitHub authorization query.'
}
else {
    try {
        $callerAuthorization = $PublicationAuthorizationJson | ConvertFrom-Json
    }
    catch {
        throw "Publication authorization evidence is invalid JSON: $($_.Exception.Message)"
    }
    if (-not $callerAuthorization.mode -or -not $callerAuthorization.source_commit -or -not $callerAuthorization.checked_at_utc) {
        throw 'Publication authorization evidence requires mode, source_commit, and checked_at_utc.'
    }
    if ([string]$callerAuthorization.source_commit -ne $sourceCommit) {
        throw "Publication authorization source_commit '$($callerAuthorization.source_commit)' does not equal release source commit '$sourceCommit'."
    }
    if ([string]$callerAuthorization.mode -ne 'hosted_qa') {
        throw "Publication authorization mode must be hosted_qa; '$($callerAuthorization.mode)' cannot authorize publication."
    }

}
$publicationAuthorization = $callerAuthorization
$builderVersion = [string]$builderProof.version
$launcherCapability = Assert-VmbLauncherPublicationCapability `
    -LauncherExecutableLease $effectiveLauncherLease `
    -WorkingDirectory $repoRoot
Write-Host "VMBLauncher dependency: $launcher ($($launcherResolution.Source), version $builderVersion)" -ForegroundColor DarkGray
Write-Host "VMBLauncher publication boundary: schema 3, exact authority proof, locked upload snapshot - PASS" -ForegroundColor DarkGray

# Every filtered ship updates the same daily release and its shared manifest.
# Per-mod claims do not serialize two DIFFERENT mods, so without this machine-
# global transaction lock both publishers can read the same base manifest and
# the later writer silently erases the earlier mod's new entry. Hold the lock
# across lookup, carry-forward, immutable snapshot capture, and release-ID
# mutation. An abandoned mutex is safe to take over because the next run reads
# GitHub again rather than trusting predecessor state.
$releaseTransactionMod = if (@($Mods).Count -eq 1) { "$($Mods[0])" } else { $null }
$releaseTransactionLease = Enter-VmbMachineTransactionLease `
    -Action 'publish-release' `
    -Mod $releaseTransactionMod `
    -ProjectRoot $repoRoot
$releaseMutationMutex = $null
$releaseMutationLockHeld = $false
try {
    $releaseMutationMutex = Enter-VtGitHubReleaseMutationMutex
    $releaseMutationLockHeld = $true
    Write-Host 'GitHub release mutation lock: acquired' -ForegroundColor DarkGray

# The release set is source-commit data. A mutable worktree inventory must not
# select another root bundle or weaken authority while the release continues to
# claim source_commit.
$inventory = Get-PublicationCommitInventory `
    -RepoRoot $repoRoot `
    -SourceCommit $sourceCommit
# NOTE: this variable must NOT be named $mods -- PowerShell variable names are
# CASE-INSENSITIVE, so $mods would silently OVERWRITE the $Mods parameter (it
# did, on 2026-07-13: every ship's -Mods filter saw 19 inventory hashtables
# instead of the one mod name and the release step aborted).
$releaseSet = @($inventory.Mods | ForEach-Object {
    $entryAuthority = Assert-VtBundleAuthorityEntry -Entry $_
    if ([string]$_.RootBundle -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') {
        throw "Source-commit inventory RootBundle for '$($_.Dir)' is invalid: '$($_.RootBundle)'."
    }
    [ordered]@{
        Folder = $_.Dir
        Id = $_.ModId
        Name = $_.Name
        RootBundle = $_.RootBundle
        DescriptorName = "$($_.Dir).mod"
        BundleAuthority = $entryAuthority
    }
})

# ---- Per-mod filter (issues #493 / #436) ----
# -Mods (folder name or ModId, case-insensitive) restricts the build/stage/
# upload set. Siblings are NOT rebuilt, restaged, or re-uploaded: their release
# assets and manifest entries stay exactly as last published. ship.ps1 passes
# the shipped mod here so (a) a sibling's broken working-tree WIP cannot fail a
# single-mod ship (#493) and (b) no sibling zip is ever published carrying a
# version label read from mid-edit live source (#436).
$filterActive = [bool]($Mods -and @($Mods).Count -gt 0)
if ($filterActive) {
    $unknown = @()
    foreach ($name in $Mods) {
        if (-not @($releaseSet | Where-Object { $_.Folder -eq $name -or $_.Id -eq $name })) { $unknown += $name }
    }
    if ($unknown.Count -gt 0) {
        throw "-Mods name(s) not in tools/mod-inventory.psd1: $($unknown -join ', '). Use the folder name (e.g. weapon_tweaker) or the ModId (e.g. wt)."
    }
    $releaseSet = @($releaseSet | Where-Object { ($Mods -contains $_.Folder) -or ($Mods -contains $_.Id) })
    Write-Host "Per-mod filter: staging ONLY $(@($releaseSet | ForEach-Object { $_.Id }) -join ', ') (issues #436/#493)" -ForegroundColor Yellow
}
if ($PublicationReceiptOutputPath -and @($releaseSet).Count -ne 1) {
    throw '-PublicationReceiptOutputPath requires an exact one-mod filtered publication.'
}
if (@($releaseSet | Where-Object { [string]$_.BundleAuthority -ceq 'receipt' }).Count -gt 0 -and
    @($launcherCapability.Capabilities) -notcontains 'receipt-authority-publication-v1') {
    throw 'VMBLauncher lacks receipt-authority-publication-v1; no release lookup or mutation is permitted.'
}

# ---- Static-analysis lint gate ----
# Catches the two recurring bug classes that have cost multiple version bumps:
#   1. Duplicate VMF hook registration (silently dropped - burns versions on cim)
#   2. Lua forward-reference bugs (cosmetics_tweaker has shipped this 6+ times)
# Exit code 2 = hard fail (duplicate hooks). Exit code 1 = warning only
# (forward-ref candidates). We BLOCK on exit 2 - a release with a known silently-
# dropped hook would push a broken bundle to every friend.
# With -Mods the gate is SCOPED to the filtered mods (issue #493): a sibling's
# mid-edit duplicate-hook error must not block this mod's release; the filtered
# mod itself still hard-fails on exit 2.
# Comments + throw strings are ASCII only - PowerShell parses .ps1 as
# Windows-1252 by default and mangles em-dashes (memory:
# feedback_ps5_getcontent_utf8).
$levelBudgetGate = Join-Path $repoRoot 'qa\check_level_lookup_budget.ps1'
if (Test-Path $levelBudgetGate) {
    Write-Host ""
    Write-Host "==> CT network level-key budget" -ForegroundColor Cyan
    & $levelBudgetGate
    if ($LASTEXITCODE -ne 0) {
        throw "Release blocked: CT adventure LevelSettings/NetworkLookup additions exceed the fixed weight_array budget or duplicate aliases consume network keys."
    }
} else {
    throw "Release blocked: required level-key budget gate is missing at $levelBudgetGate"
}

$linter = Join-Path $repoRoot 'tools\mod-lint\lint-mod.ps1'
if (Test-Path $linter) {
    if ($filterActive) {
        foreach ($m in $releaseSet) {
            Write-Host ""
            Write-Host "==> Static-analysis lint ($($m.Folder))" -ForegroundColor Cyan
            & $linter $m.Folder -Json
            $lintExit = $LASTEXITCODE
            if ($lintExit -eq 2) {
                throw "Lint gate FAILED for $($m.Folder) (duplicate VMF hook registration detected). Fix the duplicates above before publishing - VMF silently drops the second hook and the released bundle will be broken."
            }
            if ($lintExit -eq 1) {
                Write-Warning "Lint gate produced warnings for $($m.Folder) (forward-ref candidates). Continuing - these are non-blocking, but verify each helper has an explicit forward declaration if a closure references it before its definition line."
            }
        }
    } else {
        Write-Host ""
        Write-Host "==> Static-analysis lint (tools/mod-lint/lint-mod.ps1)" -ForegroundColor Cyan
        & $linter -Json
        $lintExit = $LASTEXITCODE
        if ($lintExit -eq 2) {
            throw "Lint gate FAILED (duplicate VMF hook registration detected). Fix the duplicates above before publishing - VMF silently drops the second hook and the released bundle will be broken."
        }
        if ($lintExit -eq 1) {
            Write-Warning "Lint gate produced warnings (forward-ref candidates). Continuing - these are non-blocking, but verify each helper has an explicit forward declaration if a closure references it before its definition line."
        }
    }
} else {
    Write-Warning "Linter not found at $linter - skipping pre-release lint gate."
}

function Assert-PublicationStagePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetDirectoryName($full) -cne $root -or
        [System.IO.Path]::GetFileName($full) -cnotmatch '^\.release-stage-[0-9a-f]{32}$') {
        throw "Publication stage path is not a unique direct child of RepoRoot: $full"
    }
    foreach ($candidate in @($root, $full)) {
        if (Test-Path -LiteralPath $candidate) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Publication refuses a reparse-point stage ancestor: $candidate"
            }
        }
    }
    return $full
}

function Remove-PublicationStageDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepoRoot
    )

    $full = Assert-PublicationStagePath -Path $Path -RepoRoot $RepoRoot
    if (-not (Test-Path -LiteralPath $full)) { return }
    $rootItem = Get-Item -LiteralPath $full -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to clean a reparse-point publication stage: $full"
    }
    $entries = @(Get-ChildItem -LiteralPath $full -Recurse -Force)
    if (@($entries | Where-Object {
            ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        }).Count -gt 0) {
        throw "Refusing to clean a publication stage containing a reparse point: $full"
    }
    foreach ($file in @($entries | Where-Object { -not $_.PSIsContainer })) {
        $file.Attributes = [System.IO.FileAttributes]::Normal
        $file.Delete()
    }
    foreach ($directory in @($entries | Where-Object { $_.PSIsContainer } |
            Sort-Object { $_.FullName.Length } -Descending)) {
        $directory.Delete()
    }
    $rootItem.Delete()
}

$stage = Join-Path $repoRoot ('.release-stage-' + [guid]::NewGuid().ToString('N'))
$stage = Assert-PublicationStagePath -Path $stage -RepoRoot $repoRoot
if (Test-Path -LiteralPath $stage) {
    throw "Unique publication stage unexpectedly already exists: $stage"
}
[System.IO.Directory]::CreateDirectory($stage) | Out-Null
$stage = Assert-PublicationStagePath -Path $stage -RepoRoot $repoRoot

if (-not $Tag) { $Tag = "mods-$(Get-Date -Format yyyy-MM-dd)" }

function Get-ByteSha256 {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Read-GitHubReleaseManifest {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$DownloadDirectory
    )
    $manifestAsset = Get-GitHubReleaseAsset -Release $Release -Name 'manifest.json'
    if (-not $manifestAsset) { return $null }
    $manifestBytes = Get-GitHubReleaseAssetBytes -Repo $ghRepo -Asset $manifestAsset
    try { $parsed = [System.Text.Encoding]::UTF8.GetString($manifestBytes) | ConvertFrom-Json } catch { return $null }
    if (-not $parsed -or -not $parsed.mods) { return $null }
    return [pscustomobject]@{ Manifest = $parsed; Release = $Release }
}

# ---- Base manifest (filtered mode only) ----
# A filtered publish must never emit a manifest that FORGETS sibling mods: the
# vt2-mod-updater treats manifest.json as the complete mod set. Sibling entries
# are carried VERBATIM from the release's existing manifest - the version and
# sha256 of what was ACTUALLY published, never re-read from live source (issue
# #436). Preference order: this tag's own manifest, else the latest release's
# (first ship under a new day's tag). No base manifest -> hard fail.
$baseManifest = $null
$baseTag      = $null
$baseRelease  = $null
$targetRelease = $null
$targetReleaseResult = $null
$releaseExists = $false
if ($filterActive) {
    $dlDir = Join-Path $stage '.base-manifest'
    New-Item -ItemType Directory -Force -Path $dlDir | Out-Null

    $targetReleaseResult = Resolve-GitHubReleaseByTag -Repo $ghRepo -Tag $Tag
    Write-Host "  release lookup: $($targetReleaseResult.Message)" -ForegroundColor DarkGray
    if ($targetReleaseResult.State -eq 'Unavailable') {
        throw "Release lookup unavailable: $($targetReleaseResult.Message). Refusing to create or mutate a release while existence is uncertain."
    }
    $releaseExists = ($targetReleaseResult.State -eq 'Found')
    if ($releaseExists) { $targetRelease = $targetReleaseResult.Release }

    $candidateReleases = @()
    $loadedBase = $null
    if ($targetRelease) {
        $candidateReleases += $targetRelease
        $loadedBase = Read-GitHubReleaseManifest -Release $targetRelease -DownloadDirectory $dlDir
    }
    # Existing target releases normally supply their own base manifest. Query
    # the latest list entry only when the target is absent or lacks a usable
    # manifest, so a separate list outage cannot break the healthy tag route.
    if (-not $loadedBase) {
        $latestRelease = Get-GitHubLatestReleaseFromList -Repo $ghRepo
        if ($latestRelease -and (-not $targetRelease -or "$($latestRelease.id)" -ne "$($targetRelease.id)")) {
            $candidateReleases += $latestRelease
            $loadedBase = Read-GitHubReleaseManifest -Release $latestRelease -DownloadDirectory $dlDir
        }
    }
    if ($loadedBase) {
        $baseManifest = $loadedBase.Manifest
        $baseRelease = $loadedBase.Release
        $baseTag = "$($baseRelease.tag_name)"
    }
    if (-not $baseManifest) {
        $triedTags = @($candidateReleases | ForEach-Object { $_.tag_name })
        throw "-Mods needs an existing release manifest to carry sibling entries (tried: $($triedTags -join ', ')). No duplicate release was created. Run a FULL publish-release (no -Mods) once, then retry."
    }
    Write-Host "  base manifest: $baseTag ($(@($baseManifest.mods).Count) entries)" -ForegroundColor DarkGray
}

$manifestMods = @()
$assetPaths   = @()
$stagedIds    = @()
$receiptInputs = @()

foreach ($m in $releaseSet) {
    $commitSnapshot = $null
    if ([string]$m.BundleAuthority -ceq 'tracked') {
        # Preserve the established tracked contract: select immutable Git
        # bytes before a build process can touch the working tree.
        $commitSnapshot = Get-VtPublicationSnapshot `
            -RepoRoot $repoRoot `
            -SourceCommit $sourceCommit `
            -Mod $m.Folder `
            -ExpectedBuilderVersion $builderVersion
    }

    if (-not $SkipBuild) {
        Write-Host ""
        Write-Host "==> Building $($m.Folder)" -ForegroundColor Cyan
        $buildArguments = @('build', $m.Folder)
        if ([string]$m.BundleAuthority -ceq 'receipt') { $buildArguments += '--clean' }
        $buildRun = Invoke-VmbLauncherProcess `
            -Lease $effectiveLauncherLease `
            -ArgumentList $buildArguments `
            -WorkingDirectory $repoRoot `
            -ReplayOutput
        if ($buildRun.ExitCode -ne 0) {
            throw "Build failed for $($m.Folder) (exit $($buildRun.ExitCode))"
        }
        if ([string]$m.BundleAuthority -ceq 'receipt') {
            $null = Invoke-BuildOutputNormalization `
                -RepoRoot $repoRoot -Mod $m.Folder
        }
    }

    if ([string]$m.BundleAuthority -ceq 'receipt') {
        # Receipt authority has no committed bundleV2 bytes. Capture only after
        # the clean, normalized build, then detach the restrictive-handle bytes
        # proven by the committed schema-3 receipt.
        $commitSnapshot = Get-VtPublicationSnapshot `
            -RepoRoot $repoRoot `
            -SourceCommit $sourceCommit `
            -Mod $m.Folder `
            -ExpectedBuilderVersion $builderVersion
    }
    $expectedByteSource = if ([string]$m.BundleAuthority -ceq 'tracked') {
        'git_commit_blobs'
    } else {
        'materialized_restrictive_handles'
    }
    if ([string]$commitSnapshot.BundleAuthority -cne [string]$m.BundleAuthority -or
        [string]$commitSnapshot.AuthorityProof.Authority -cne [string]$m.BundleAuthority -or
        [string]$commitSnapshot.AuthorityProof.ByteSource -cne $expectedByteSource -or
        [string]$commitSnapshot.AuthorityProof.SourceCommit -cne $sourceCommit -or
        [string]$commitSnapshot.AuthorityProof.RootBundle -cne [string]$m.RootBundle) {
        throw "Release publisher requires a coherent '$($m.BundleAuthority)' immutable snapshot for $($m.Folder)."
    }
    $commitOutputSet = $commitSnapshot.OutputSet
    $version = "$($commitSnapshot.Version)"
    $workshopId = "$($commitSnapshot.PublishedId)"
    $visibility = "$($commitSnapshot.Visibility)"

    if (-not $workshopId) {
        if ($PublicationReceiptOutputPath -or $filterActive) {
            throw "Source-commit itemV2.cfg for '$($m.Folder)' has no published_id."
        }
        Write-Warning "Skipping $($m.Folder): no published_id (unpublished mod)"
        continue
    }
    if ($workshopId -eq '0' -and [string]$m.BundleAuthority -ceq 'receipt') {
        throw 'Receipt authority does not support first-upload bootstrap; use the reviewed tracked bootstrap lane first.'
    }
    if ($workshopId -eq '0' -and -not $PublicationReceiptOutputPath) {
        throw "published_id=0 is accepted only for a one-mod canonical first-upload receipt handoff."
    }
    if (-not $version) {
        Write-Warning "$($m.Folder) has no MOD_VERSION; falling back to '$Tag'"
        $version = $Tag
    }

    # Stage only detached immutable snapshot bytes. For tracked authority these
    # are source-commit blobs; for receipt authority they are the exact
    # restrictive-handle bytes proven against the committed schema-3 receipt.
    $modStage = Join-Path $stage $m.Id
    New-Item -ItemType Directory -Force -Path $modStage | Out-Null
    foreach ($bundle in @($commitSnapshot.BundleFiles)) {
        $relative = "$($bundle.Path)".Replace('/', '\')
        $destination = [System.IO.Path]::GetFullPath((Join-Path $modStage $relative))
        $stagePrefix = [System.IO.Path]::GetFullPath($modStage).TrimEnd('\') + '\'
        if (-not $destination.StartsWith($stagePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Commit bundle path escapes release staging: $($bundle.Path)"
        }
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
        [System.IO.File]::WriteAllBytes($destination, [byte[]]$bundle.Bytes)
    }
    # Provenance hashes describe VMBLauncher's canonical post-policy output,
    # before the updater sidecar is added. Enumerate and validate that exact
    # normalized set first; the updater sidecar is release metadata, not a VMB
    # output, and must never be filtered out of a looser filesystem scan.
    $stagedOutputSet = Get-VtBundleOutputSet `
        -BundleDirectory $modStage `
        -ExpectedDescriptorName $m.DescriptorName `
        -ExpectedRootBundle $m.RootBundle `
        -ExpectedDescriptorSha256 ([string]$commitSnapshot.SourceDescriptor.Sha256)
    $stagedComparison = @(Compare-VtBundleOutputSets `
        -Expected $commitOutputSet `
        -Actual $stagedOutputSet `
        -ExpectedLabel 'immutable authority output' `
        -ActualLabel 'staged output' `
        -RequireLength $true)
    if ($stagedComparison.Count -gt 0) {
        throw "Release staging differs from immutable authority output: $($stagedComparison -join '; ')"
    }
    $bundleFiles = @(ConvertTo-VtBundleManifestRecords -OutputSet $commitOutputSet)
    Set-Content -Path (Join-Path $modStage 'vt2updater_version.txt') -Value $version -Encoding ascii -NoNewline

    $zipPath = Join-Path $stage "$($m.Id).zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    $zipBytes = New-ReleaseZipBytesFromImmutableOutput `
        -OutputSet $commitOutputSet `
        -BundleFiles @($commitSnapshot.BundleFiles) `
        -Version $version
    [System.IO.File]::WriteAllBytes($zipPath, [byte[]]$zipBytes)
    $assetPaths += $zipPath

    # Bundle integrity: lowercase-hex SHA256 of the zip bytes. vt2-mod-updater compares
    # this against the post-download hash before extracting; mismatch refuses the bundle
    # (defends against the ugc_tool "Upload finished" false-success bug + transport
    # corruption). Purely additive — older consumers without verification still function.
    $sha256 = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()

    $sourceState = 'clean'
    $recoveryReceiptProof = Get-VtReleaseRecoveryBuildReceiptProof `
        -RepoRoot $repoRoot `
        -SourceCommit $sourceCommit `
        -Mod $m.Folder `
        -PublicationSnapshot $commitSnapshot `
        -ExpectedBuilderVersion $builderVersion
    $manifestEntry = [ordered]@{
        mod_id          = $m.Id
        friendly_name   = $m.Name
        workshop_id     = $workshopId
        version         = $version
        asset_filename  = "$($m.Id).zip"
        sha256          = $sha256
        visibility      = $visibility
        source_commit   = $sourceCommit
        source_state    = $sourceState
        bundle_authority = $m.BundleAuthority
        builder         = [ordered]@{
            name    = 'VMBLauncher'
            version = $builderVersion
        }
        root_bundle     = $m.RootBundle
        descriptor_name = $m.DescriptorName
        bundle_files    = $bundleFiles
    }
    if ($workshopId -ne '0' -and $recoveryReceiptProof.Available) {
        $manifestEntry['recovery'] = New-VtReleaseRecoveryRecord `
            -Repository $ghRepo `
            -ReleaseTag $Tag `
            -ModFolder $m.Folder `
            -ModId $m.Id `
            -WorkshopId $workshopId `
            -Version $version `
            -AssetFilename "$($m.Id).zip" `
            -AssetBytes $zipBytes `
            -BuilderVersion $builderVersion `
            -PublicationSnapshot $commitSnapshot `
            -BuildReceiptProof $recoveryReceiptProof
    }
    $manifestEntry['publication_authorization'] = $publicationAuthorization
    $manifestMods += $manifestEntry
    $stagedIds += $m.Id
    $receiptInputs += [pscustomobject]@{
        Folder = $m.Folder
        ModId = $m.Id
        Version = $version
        PublicationSnapshot = $commitSnapshot
    }
    Write-Host "  staged $($m.Id) v$version -> $zipPath (sha256 $($sha256.Substring(0,12))...)"
}

# ---- Filtered mode: merge with the base manifest + plan the release action ----
$carriedIdSet  = @{}
if ($filterActive) {
    # Merge: staged entries win; every other entry carries over VERBATIM from
    # the base manifest so unfiltered mods keep the version/sha256 of what is
    # actually attached to the release (issue #436 - a sibling's version label
    # must never come from mid-edit live source). Base order is preserved;
    # first-ever-published mods are appended.
    $stagedById = @{}
    foreach ($e in $manifestMods) { $stagedById["$($e.mod_id)"] = $e }
    $restagedCount = 0
    $mergedMods = @()
    foreach ($baseEntry in $baseManifest.mods) {
        $id = "$($baseEntry.mod_id)"
        if ($stagedById.ContainsKey($id)) {
            $mergedMods += $stagedById[$id]
            $stagedById.Remove($id)
            $restagedCount++
        } else {
            $mergedMods += $baseEntry
            $carriedIdSet[$id] = $true
        }
    }
    foreach ($e in $manifestMods) {
        if ($stagedById.ContainsKey("$($e.mod_id)")) { $mergedMods += $e }   # new mod, not in base yet
    }
    $manifestMods = $mergedMods
    Write-Host ""
    Write-Host "Manifest merge: $restagedCount restaged from this run, $($carriedIdSet.Count) carried verbatim from $baseTag (issues #436/#493)." -ForegroundColor Yellow

    if (-not $releaseExists -and -not $DryRun) {
        # Creating a NEW release under a filter: it must still be SELF-CONTAINED
        # (vt2-mod-updater resolves every asset_filename against ONE release), so
        # carry each sibling's zip forward from the base release, byte-identical
        # (sha256-verified against its carried manifest entry). A sibling whose
        # asset is missing from the base release is dropped from the manifest
        # with a warning - a FULL publish restores it.
        Write-Host ""
        Write-Host "==> Release $Tag does not exist yet -- carrying $($carriedIdSet.Count) sibling asset(s) forward from $baseTag" -ForegroundColor Cyan
        $baseAssetNames = @($baseRelease.assets | ForEach-Object { $_.name })
        $keptMods = @()
        foreach ($entry in $manifestMods) {
            $id = "$($entry.mod_id)"
            if (-not $carriedIdSet.ContainsKey($id)) { $keptMods += $entry; continue }
            $fname = "$($entry.asset_filename)"
            if ($baseAssetNames -notcontains $fname) {
                Write-Warning "carry-forward: $baseTag has no asset '$fname' -- dropping $id from this release's manifest (run a FULL publish-release to restore it)."
                continue
            }
            $zipDest = Join-Path $stage $fname
            if (Test-Path $zipDest) { Remove-Item $zipDest -Force }
            $baseAsset = Get-GitHubReleaseAsset -Release $baseRelease -Name $fname
            $zipBytes = Get-GitHubReleaseAssetBytes -Repo $ghRepo -Asset $baseAsset
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $gotHash = [System.BitConverter]::ToString($sha.ComputeHash($zipBytes)).Replace('-', '').ToLowerInvariant()
            }
            finally { $sha.Dispose() }
            $wantHash = "$($entry.sha256)"
            if ($wantHash -and $gotHash -ne $wantHash) {
                throw "carry-forward: '$fname' hash mismatch (manifest $wantHash vs downloaded $gotHash) -- refusing to republish a corrupt asset"
            }
            [System.IO.File]::WriteAllBytes($zipDest, $zipBytes)
            $assetPaths += $zipDest
            Write-Host "  carried $id v$($entry.version) ($fname, sha256 $($gotHash.Substring(0,12))...)"
            $keptMods += $entry
        }
        $manifestMods = $keptMods
    }
}

$manifest = [ordered]@{
    manifest_schema = 2
    release_tag  = $Tag
    published_at = (Get-Date).ToUniversalTime().ToString('o')
    mods         = $manifestMods
}
$manifestPath = Join-Path $stage 'manifest.json'
$manifestBytes = ConvertTo-VtReleaseManifestBytes -Manifest $manifest
[System.IO.File]::WriteAllBytes($manifestPath, [byte[]]$manifestBytes)
$assetPaths += $manifestPath

# Block before any GitHub mutation if a newly staged entry cannot be mapped to
# its source baseline, VMBLauncher version, or exact bundle bytes. Filtered
# releases may carry older sibling entries without provenance until each is
# rebuilt; the validator reports those explicitly without breaking transition.
$manifestVerdict = Test-ReleaseManifest -Manifest $manifest -RequiredModIds $stagedIds -StageRoot $stage
foreach ($warning in $manifestVerdict.Warnings) { Write-Warning "Release manifest: $warning" }
if (-not $manifestVerdict.Valid) {
    throw "Release manifest validation failed:`n - $($manifestVerdict.Errors -join "`n - ")"
}
Write-Host "Release manifest validation: PASS ($($stagedIds.Count) newly staged provenance entr$(if ($stagedIds.Count -eq 1) { 'y' } else { 'ies' }))." -ForegroundColor Green

# All lint, immutable staging, base-manifest lookup, and carry-forward
# downloads are complete. Re-query authority only now, immediately before
# constructing the hosted receipt and mutating the release. Local HEAD/index/
# worktree are deliberately not re-read: the immutable publication snapshots
# already own every new release and receipt byte.
$liveAuthorization = Get-LivePublicationAuthorization -Repo $ghRepo -SourceCommit $sourceCommit
if (-not $liveAuthorization.Ok) {
    throw "Last-moment independent publication authorization FAILED: $($liveAuthorization.Message)"
}
$correlation = Test-PublicationEvidenceMatchesLive `
    -CallerEvidence $callerAuthorization `
    -LiveEvidence $liveAuthorization.Evidence
if (-not $correlation.Ok) {
    throw "Caller publication authorization was rejected at the mutation boundary: $($correlation.Message)"
}
$publicationAuthorization = $liveAuthorization.Evidence

foreach ($receiptInput in $receiptInputs) {
    $entry = @($manifestMods | Where-Object { "$($_.mod_id)" -eq "$($receiptInput.ModId)" })
    if ($entry.Count -ne 1) {
        throw "Could not bind final authorization to exact manifest entry '$($receiptInput.ModId)'."
    }
    $entry[0]['publication_authorization'] = $publicationAuthorization
}
$manifest.published_at = (Get-Date).ToUniversalTime().ToString('o')
$manifestBytes = ConvertTo-VtReleaseManifestBytes -Manifest $manifest
[System.IO.File]::WriteAllBytes($manifestPath, $manifestBytes)

$finalManifestVerdict = Test-ReleaseManifest -Manifest $manifest -RequiredModIds $stagedIds -StageRoot $stage
if (-not $finalManifestVerdict.Valid) {
    throw "Final release manifest validation failed:`n - $($finalManifestVerdict.Errors -join "`n - ")"
}

$receiptOutputAssetName = $null
$expectedAssetHashes = @{ 'manifest.json' = (Get-ByteSha256 -Bytes $manifestBytes) }
foreach ($receiptInput in $receiptInputs) {
    # Receipt coordinates are a cross-language security boundary. Use the
    # canonical lowercase source folder, never a manifest/display ModId such as
    # WOC, so PowerShell and VMBLauncher's case-sensitive gate agree exactly.
    $assetName = Get-WorkshopPublicationReceiptAssetName -Mod $receiptInput.Folder
    $receiptPath = Join-Path $stage $assetName
    $receipt = New-WorkshopPublicationReceipt `
        -RepoRoot $repoRoot `
        -Repository $ghRepo `
        -ReleaseTag $Tag `
        -ReceiptAssetName $assetName `
        -Mod $receiptInput.Folder `
        -Version $receiptInput.Version `
        -Owner (Get-CanonicalShipOwnerId -RepoRoot $repoRoot) `
        -SourceCommit $sourceCommit `
        -PublicationSnapshot $receiptInput.PublicationSnapshot `
        -AuthorizationEvidence $publicationAuthorization
    $receiptJson = $receipt | ConvertTo-Json -Depth 12
    $receiptBytes = [System.Text.Encoding]::UTF8.GetBytes($receiptJson)
    [System.IO.File]::WriteAllBytes($receiptPath, $receiptBytes)
    $expectedAssetHashes[$assetName] = Get-ByteSha256 -Bytes $receiptBytes
    $assetPaths += $receiptPath
    if ($PublicationReceiptOutputPath) { $receiptOutputAssetName = $assetName }
}

# Freeze all local release inputs into immutable byte arrays. From this point
# onward GitHub mutation and the launcher handoff never reopen zip, manifest, or
# receipt paths. Revalidate every snapshot against the in-memory manifest/receipt
# objects so a same-user path replacement before this read fails closed.
$assetSnapshots = @(New-GitHubReleaseAssetSnapshots -AssetPaths $assetPaths)
foreach ($snapshot in $assetSnapshots) {
    $snapshotName = "$($snapshot.Name)"
    $expectedHash = if ($expectedAssetHashes.ContainsKey($snapshotName)) {
        "$($expectedAssetHashes[$snapshotName])"
    } else { '' }
    if ($expectedHash -and "$($snapshot.Sha256)" -ne $expectedHash) {
        throw "Release asset '$snapshotName' changed before immutable snapshot capture."
    }
    if ($snapshotName -like '*.zip') {
        $entries = @($manifest.mods | Where-Object { "$($_.asset_filename)" -ceq $snapshotName })
        if ($entries.Count -ne 1 -or "$($entries[0].sha256)" -ne "$($snapshot.Sha256)") {
            throw "Zip snapshot '$snapshotName' does not match the final manifest SHA-256."
        }
        $entryId = "$($entries[0].mod_id)"
        $bindingMode = Get-ReleaseZipSnapshotBindingMode `
            -ManifestEntry $entries[0] `
            -IsStaged ($stagedIds -contains $entryId) `
            -IsCarried ($carriedIdSet.ContainsKey($entryId))
        if ($bindingMode -eq 'exact_bundle_files') {
            $zipBinding = Test-ReleaseZipSnapshot `
                -ZipBytes ([byte[]]$snapshot.Bytes) `
                -ManifestEntry $entries[0]
            if (-not $zipBinding.Valid) {
                throw "Zip snapshot '$snapshotName' is not bound to exact authority-selected bundle bytes:`n - $($zipBinding.Errors -join "`n - ")"
            }
        }
        elseif ($bindingMode -ne 'legacy_carried_whole_zip') {
            throw "Zip snapshot '$snapshotName' lacks authority-selected bundle records and is not an unchanged historical carry."
        }
    }
}

Write-Host ""
# Independently derive the narrow handoff identity from this publisher's
# source-qualified staged row, not from caller intent or a receipt file. This
# remains unarmed through DryRun, HTTP ambiguity and unpublished drafts.
$publisherPinContext = $null
if ($null -ne $SourcePinHandoff) {
    if ($receiptInputs.Count -ne 1) { throw 'Source-pin handoff requires exactly one staged mod.' }
    $pinInput = $receiptInputs[0]
    $pinRows = @($manifestMods | Where-Object { [string]$_.mod_id -ceq [string]$pinInput.ModId })
    if ($pinRows.Count -ne 1 -or [string]$pinRows[0].source_commit -cne $sourceCommit -or
        [string]$pinRows[0].version -cne [string]$pinInput.Version) {
        throw 'Source-pin handoff has no exact publisher-owned staged manifest entry.'
    }
    if ([string]$pinRows[0].workshop_id -cne '0') {
        $pinTree = @(git -C $repoRoot rev-parse "$sourceCommit`:$($pinInput.Folder)/scripts/mods" 2>$null)
        if ($LASTEXITCODE -ne 0 -or $pinTree.Count -ne 1) { throw 'Publisher cannot resolve the source-qualified pin tree.' }
        $publisherPinContext = New-VtPublishedPinContext -RepoRoot $repoRoot -Mod $pinInput.Folder -ModId $pinInput.ModId `
            -SourceCommit $sourceCommit -ModTree ([string]$pinTree[0]).Trim() -Version $pinInput.Version `
            -PublishedId ([string]$pinRows[0].workshop_id) -ReleaseTag $Tag
    }
    Assert-VtPinPublicationHandoff -Handoff $SourcePinHandoff -ExpectedJson $publisherPinContext
}

Write-Host "Manifest:" -ForegroundColor Green
Get-Content $manifestPath

if ($DryRun) {
    Write-Host ""
    Write-Host "DryRun: skipping gh release create. Assets staged at $stage" -ForegroundColor Yellow
    if ($filterActive) {
        if ($releaseExists) {
            Write-Host "DryRun plan: release $Tag exists -- a live run (or ship.ps1) clobber-uploads the staged zip(s) + merged manifest; sibling assets untouched." -ForegroundColor Yellow
        } else {
            Write-Host "DryRun plan: release $Tag absent -- a live run would carry $($carriedIdSet.Count) sibling asset(s) forward from $baseTag and create the release self-contained." -ForegroundColor Yellow
        }
    }
    return
}

function Copy-PublicationReceiptOutput {
    if (-not $PublicationReceiptOutputPath) { return }
    $receiptSnapshot = @($assetSnapshots | Where-Object { "$($_.Name)" -ceq "$receiptOutputAssetName" })
    if (-not $receiptOutputAssetName -or $receiptSnapshot.Count -ne 1) {
        throw 'The hosted publication receipt was not available for the canonical ship handoff.'
    }
    [System.IO.File]::WriteAllBytes($PublicationReceiptOutputPath, [byte[]]$receiptSnapshot[0].Bytes)
}

if ($filterActive -and $releaseExists) {
    # Filtered update of an existing release: replace ONLY the staged zip(s) +
    # the merged manifest. Sibling assets on the release are never touched.
    Assert-VtPublishedReleaseIdentity -Release $targetRelease -Tag $Tag
    Write-Host ""
    Write-Host "==> GitHub release-id upload/clobber $($targetRelease.id) ($($assetPaths.Count) asset(s))" -ForegroundColor Cyan
    $null = Publish-GitHubReleaseAssetsById -Repo $ghRepo -Release $targetRelease -AssetSnapshots $assetSnapshots
    if ($null -ne $SourcePinHandoff) { $SourcePinHandoff.PublishedJson = $publisherPinContext }
    Copy-PublicationReceiptOutput
    Write-Host ""
    Write-Host "Release updated: https://github.com/$ghRepo/releases/tag/$Tag" -ForegroundColor Green
    return
}

Write-Host ""
Write-Host "==> GitHub draft release create $Tag" -ForegroundColor Cyan
$notes = "Pre-built mod bundles for vt2-mod-updater.`n`nUpdater app: https://github.com/Ensrick/vt2-mod-updater/releases/latest"
$newRelease = New-GitHubDraftRelease -Repo $ghRepo -Tag $Tag -Title "Mod bundles $Tag" -Notes $notes
$null = Publish-GitHubReleaseAssetsById -Repo $ghRepo -Release $newRelease -AssetSnapshots $assetSnapshots
$publishedRelease = Publish-GitHubDraftRelease -Repo $ghRepo -Release $newRelease
Assert-VtPublishedReleaseIdentity -Release $publishedRelease -Tag $Tag
if ($null -ne $SourcePinHandoff) { $SourcePinHandoff.PublishedJson = $publisherPinContext }
Copy-PublicationReceiptOutput

Write-Host ""
Write-Host "Release published: https://github.com/$ghRepo/releases/tag/$Tag" -ForegroundColor Green
}
finally {
    if ($releaseMutationLockHeld -and $releaseMutationMutex) {
        try { $releaseMutationMutex.ReleaseMutex() }
        catch { Write-Warning "Could not release the GitHub release mutation mutex: $($_.Exception.Message)" }
    }
    if ($releaseMutationMutex) { $releaseMutationMutex.Dispose() }
}
}
finally {
    try {
        try {
            if ($stage -and -not $DryRun -and (Test-Path -LiteralPath $stage)) {
                try { Remove-PublicationStageDirectory -Path $stage -RepoRoot $repoRoot }
                catch { Write-Warning "Could not safely clean unique publication stage '$stage': $($_.Exception.Message)" }
            }
        }
        finally {
            if ($ownsLauncherExecutableLease -and $null -ne $effectiveLauncherLease) {
                Exit-VmbLauncherExecutableLease -Lease $effectiveLauncherLease
            }
        }
    }
    finally {
        if ($null -ne $releaseTransactionLease) {
            Exit-VmbMachineTransactionLease -Lease $releaseTransactionLease
        }
    }
}
