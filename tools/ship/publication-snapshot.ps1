# publication-snapshot.ps1 - immutable authority-neutral release byte proof (#1422).
#
# This helper can prove tracked Git blobs or schema-3 receipt-authority bytes.
# It does not itself authorize a consumer. Publication has an independent
# authority gate; deployment, updater, and recovery remain tracked-only.
# ASCII-only for PowerShell 5.1.

$script:VtPublicationSnapshotReceiptHelper = Join-Path $PSScriptRoot 'publication-receipt.ps1'
if (-not (Test-Path -LiteralPath $script:VtPublicationSnapshotReceiptHelper -PathType Leaf)) {
    throw "Publication commit helpers are missing: $script:VtPublicationSnapshotReceiptHelper"
}
. $script:VtPublicationSnapshotReceiptHelper

$script:VtPublicationSnapshotNormalizationHelper = Join-Path $PSScriptRoot 'build-output-normalization.ps1'
if (-not (Test-Path -LiteralPath $script:VtPublicationSnapshotNormalizationHelper -PathType Leaf)) {
    throw "Build normalization helpers are missing: $script:VtPublicationSnapshotNormalizationHelper"
}
. $script:VtPublicationSnapshotNormalizationHelper

$script:VtPublicationSnapshotBuildReceiptHelper = Join-Path $PSScriptRoot 'build-receipt.ps1'
if (-not (Test-Path -LiteralPath $script:VtPublicationSnapshotBuildReceiptHelper -PathType Leaf)) {
    throw "Build receipt helpers are missing: $script:VtPublicationSnapshotBuildReceiptHelper"
}
. $script:VtPublicationSnapshotBuildReceiptHelper

function Get-VtPublicationSnapshotUtf8Text {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Label
    )

    try {
        $encoding = New-Object System.Text.UTF8Encoding($false, $true)
        return $encoding.GetString($Bytes)
    }
    catch {
        throw "$Label is not strict UTF-8: $($_.Exception.Message)"
    }
}

function Get-VtPublicationSnapshotInventoryContext {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SourceCommit,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $proof = Get-PublicationCommitBlobProof `
        -RepoRoot $RepoRoot `
        -SourceCommit $SourceCommit `
        -RepoPath 'tools/mod-inventory.psd1'
    $inventory = Get-PublicationCommitInventory `
        -RepoRoot $RepoRoot `
        -SourceCommit $SourceCommit
    $matches = @($inventory.Mods | Where-Object { [string]$_.Dir -ceq $Mod })
    if ($matches.Count -ne 1) {
        throw "Publication snapshot could not resolve exactly one source-commit inventory entry for '$Mod'."
    }
    $entry = $matches[0]
    Assert-VtBuildReceiptInventoryEntry -Entry $entry -Mod $Mod
    $authority = Assert-VtBundleAuthorityEntry -Entry $entry

    $ignoreProof = Get-PublicationCommitBlobProof `
        -RepoRoot $RepoRoot `
        -SourceCommit $SourceCommit `
        -RepoPath '.gitignore'
    $ignoreText = Get-VtPublicationSnapshotUtf8Text `
        -Bytes ([byte[]]$ignoreProof.Bytes) `
        -Label 'Source-commit .gitignore'
    $ignoreProblems = @(Get-VtBundleAuthorityIgnoreStateErrors `
        -Mod $Mod `
        -Authority $authority `
        -GitIgnoreText $ignoreText)
    if ($ignoreProblems.Count -gt 0) {
        throw "Source-commit bundle authority ignore state is invalid for '$Mod': $($ignoreProblems -join '; ')"
    }

    return [pscustomobject][ordered]@{
        Entry = $entry
        Authority = $authority
        InventoryProof = $proof
        IgnoreProof = $ignoreProof
    }
}

function New-VtPublicationSnapshotResult {
    param(
        [Parameter(Mandatory = $true)]$CommitSnapshot,
        [Parameter(Mandatory = $true)]$OutputSet,
        [Parameter(Mandatory = $true)][object[]]$BundleFiles,
        [Parameter(Mandatory = $true)][string]$BundleAuthority,
        [Parameter(Mandatory = $true)]$AuthorityProof
    )

    return [pscustomobject][ordered]@{
        SourceCommit = $CommitSnapshot.SourceCommit
        ItemCfg = $CommitSnapshot.ItemCfg
        ItemCfgText = $CommitSnapshot.ItemCfgText
        SourceDescriptor = $CommitSnapshot.SourceDescriptor
        BundleFiles = @($BundleFiles)
        PreviewFile = $CommitSnapshot.PreviewFile
        Version = $CommitSnapshot.Version
        PublishedId = $CommitSnapshot.PublishedId
        Visibility = $CommitSnapshot.Visibility
        OutputSet = $OutputSet
        BundleAuthority = $BundleAuthority
        AuthorityProof = $AuthorityProof
    }
}

function Assert-VtPublicationSnapshotReceiptVerdict {
    param(
        [Parameter(Mandatory = $true)]$Verdict,
        [Parameter(Mandatory = $true)][string]$Phase
    )

    if (-not $Verdict.Ok) {
        throw "Receipt-authority publication snapshot failed $Phase validation: $(@($Verdict.Problems) -join '; ')"
    }
}

function Get-VtPublicationSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SourceCommit,
        [Parameter(Mandatory = $true)][string]$Mod,
        [string]$ExpectedBuilderVersion
    )

    if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Publication snapshot requires a lowercase full source commit SHA.'
    }
    if ($Mod -cnotmatch '^[a-z0-9][a-z0-9_]*$') {
        throw "Publication snapshot mod name is not canonical: '$Mod'."
    }
    if ($PSBoundParameters.ContainsKey('ExpectedBuilderVersion') -and
        ([string]::IsNullOrWhiteSpace($ExpectedBuilderVersion) -or
         $ExpectedBuilderVersion -cne $ExpectedBuilderVersion.Trim())) {
        throw 'Publication snapshot builder version must be a non-empty exact string when supplied.'
    }

    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $rootItem = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
        ($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Publication snapshot repository root must be a non-reparse directory: $root"
    }

    $context = Get-VtPublicationSnapshotInventoryContext `
        -RepoRoot $root `
        -SourceCommit $SourceCommit `
        -Mod $Mod
    $entry = $context.Entry
    $authority = [string]$context.Authority
    $commitSnapshot = Get-PublicationCommitSnapshot `
        -RepoRoot $root `
        -SourceCommit $SourceCommit `
        -Mod $Mod `
        -AllowEmptyBundleFiles

    if ($authority -ceq 'tracked') {
        if (@($commitSnapshot.BundleFiles).Count -eq 0) {
            throw "Tracked publication snapshot contains no source-commit bundleV2 blobs for '$Mod'."
        }
        $records = @($commitSnapshot.BundleFiles | ForEach-Object {
            [pscustomobject][ordered]@{
                Name = [string]$_.Path
                Length = [long]$_.Length
                Sha256 = [string]$_.Sha256
            }
        })
        $outputSet = New-VtBundleOutputSet `
            -Records $records `
            -ExpectedDescriptorName "$Mod.mod" `
            -ExpectedRootBundle ([string]$entry.RootBundle) `
            -ExpectedDescriptorSha256 ([string]$commitSnapshot.SourceDescriptor.Sha256)

        foreach ($bundle in @($commitSnapshot.BundleFiles)) {
            $bytes = [byte[]]$bundle.Bytes
            if ([long]$bytes.LongLength -ne [long]$bundle.Length -or
                (Get-PublicationByteSha256 -Bytes $bytes) -cne [string]$bundle.Sha256) {
                throw "Tracked publication snapshot byte proof changed for '$($bundle.Path)'."
            }
            if ([string]$bundle.GitBlob -cnotmatch '^[0-9a-f]{40,64}$') {
                throw "Tracked publication snapshot lacks an exact Git blob for '$($bundle.Path)'."
            }
        }

        $proof = [pscustomobject][ordered]@{
            Authority = 'tracked'
            SourceCommit = $SourceCommit
            InventoryGitBlob = [string]$context.InventoryProof.GitBlob
            IgnoreGitBlob = [string]$context.IgnoreProof.GitBlob
            RootBundle = [string]$entry.RootBundle
            ByteSource = 'git_commit_blobs'
            BuildReceiptGitBlob = ''
            BuildReceiptSha256 = ''
            ReceiptSchema = 0
            SourceFingerprintSha256 = ''
            OutputAlgorithm = [string]$outputSet.Algorithm
            OutputFingerprintSha256 = [string]$outputSet.Fingerprint
            BuilderName = ''
            BuilderVersion = ''
            NormalizationPolicyAlgorithm = ''
            NormalizationPolicyFingerprintSha256 = ''
        }
        return New-VtPublicationSnapshotResult `
            -CommitSnapshot $commitSnapshot `
            -OutputSet $outputSet `
            -BundleFiles @($commitSnapshot.BundleFiles) `
            -BundleAuthority $authority `
            -AuthorityProof $proof
    }

    if ($authority -cne 'receipt') {
        throw "Publication snapshot refuses unsupported bundle authority '$authority'."
    }
    if (@($commitSnapshot.BundleFiles).Count -ne 0) {
        throw "Receipt-authority publication snapshot forbids source-commit bundleV2 blobs for '$Mod'."
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedBuilderVersion)) {
        throw 'Receipt-authority publication snapshot requires the exact expected builder version.'
    }

    $receiptPath = "$Mod/.build-receipt.json"
    $receiptBlob = Get-PublicationCommitBlobProof `
        -RepoRoot $root `
        -SourceCommit $SourceCommit `
        -RepoPath $receiptPath
    $receiptText = Get-VtPublicationSnapshotUtf8Text `
        -Bytes ([byte[]]$receiptBlob.Bytes) `
        -Label "Source-commit build receipt '$receiptPath'"
    $receipt = ConvertFrom-VtBuildReceiptJson -Json $receiptText
    if ([string]$receipt.root_bundle -cne [string]$entry.RootBundle) {
        throw "Receipt root '$($receipt.root_bundle)' is not source-commit inventory root '$($entry.RootBundle)'."
    }

    $sourceMap = Get-VtBuildCommitSourceMap `
        -RepoRoot $root `
        -Mod $Mod `
        -Commit $SourceCommit
    $declaredOutputSet = Get-VtBuildReceiptDeclaredOutputSet `
        -Receipt $receipt `
        -ExpectedMod $Mod
    $normalizationPolicy = New-BuildOutputNormalizationPolicyProof -ModEntry $entry
    $declaredVerdict = Test-VtBuildReceiptProof `
        -Receipt $receipt `
        -ExpectedMod $Mod `
        -SourceMap $sourceMap `
        -OutputSet $declaredOutputSet `
        -NormalizationPolicy $normalizationPolicy `
        -ExpectedBuilderVersion $ExpectedBuilderVersion `
        -MinimumSchema 3
    Assert-VtPublicationSnapshotReceiptVerdict `
        -Verdict $declaredVerdict `
        -Phase 'declared-output'

    $descriptorSource = Get-VtBuildDescriptorSourceProof -SourceMap $sourceMap -Mod $Mod
    $materializedDirectory = [System.IO.Path]::GetFullPath(
        (Join-Path (Join-Path $root $Mod) 'bundleV2'))
    if (-not (Test-Path -LiteralPath $materializedDirectory -PathType Container)) {
        throw "Receipt-authority materialized output directory is missing: $materializedDirectory"
    }

    $byteSnapshot = Get-VtBundleOutputByteSnapshot `
        -BundleDirectory $materializedDirectory `
        -ExpectedDescriptorName "$Mod.mod" `
        -ExpectedRootBundle ([string]$entry.RootBundle) `
        -ExpectedDescriptorSha256 ([string]$descriptorSource.Sha256)
    $capturedVerdict = Test-VtBuildReceiptProof `
        -Receipt $receipt `
        -ExpectedMod $Mod `
        -SourceMap $sourceMap `
        -OutputSet $byteSnapshot.OutputSet `
        -NormalizationPolicy $normalizationPolicy `
        -ExpectedBuilderVersion $ExpectedBuilderVersion `
        -MinimumSchema 3
    Assert-VtPublicationSnapshotReceiptVerdict `
        -Verdict $capturedVerdict `
        -Phase 'captured-byte'

    $bundleFiles = @()
    $byteArrays = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in @($byteSnapshot.Files)) {
        $bytes = [byte[]]$file.Bytes
        if ([long]$bytes.LongLength -ne [long]$file.Length -or
            (Get-PublicationByteSha256 -Bytes $bytes) -cne [string]$file.Sha256) {
            throw "Receipt-authority detached byte proof changed for '$($file.Name)'."
        }
        foreach ($prior in $byteArrays) {
            if ([object]::ReferenceEquals($prior, $bytes)) {
                throw 'Receipt-authority byte capture aliased two output buffers.'
            }
        }
        $byteArrays.Add($bytes)
        $bundleFiles += [pscustomobject][ordered]@{
            Path = [string]$file.Name
            GitBlob = ''
            Bytes = $bytes
            Length = [long]$file.Length
            Sha256 = [string]$file.Sha256
        }
    }

    $proof = [pscustomobject][ordered]@{
        Authority = 'receipt'
        SourceCommit = $SourceCommit
        InventoryGitBlob = [string]$context.InventoryProof.GitBlob
        IgnoreGitBlob = [string]$context.IgnoreProof.GitBlob
        RootBundle = [string]$entry.RootBundle
        ByteSource = 'materialized_restrictive_handles'
        BuildReceiptGitBlob = [string]$receiptBlob.GitBlob
        BuildReceiptSha256 = [string]$receiptBlob.Sha256
        ReceiptSchema = [int]$receipt.schema
        SourceFingerprintSha256 = [string]$receipt.source_fingerprint_sha256
        OutputAlgorithm = [string]$byteSnapshot.OutputSet.Algorithm
        OutputFingerprintSha256 = [string]$byteSnapshot.OutputSet.Fingerprint
        BuilderName = [string]$receipt.builder.name
        BuilderVersion = [string]$receipt.builder.version
        NormalizationPolicyAlgorithm = [string]$receipt.normalization_policy.algorithm
        NormalizationPolicyFingerprintSha256 = [string]$receipt.normalization_policy.fingerprint_sha256
    }
    return New-VtPublicationSnapshotResult `
        -CommitSnapshot $commitSnapshot `
        -OutputSet $byteSnapshot.OutputSet `
        -BundleFiles $bundleFiles `
        -BundleAuthority $authority `
        -AuthorityProof $proof
}
