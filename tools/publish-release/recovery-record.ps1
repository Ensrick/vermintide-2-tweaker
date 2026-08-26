# recovery-record.ps1 - durable source-exact release recovery metadata (#1430).
#
# A recovery record is an additive manifest child built only from the immutable
# publication snapshot and its exact committed schema-3 build receipt. It does
# not restore files and does not select a GitHub release. Older entries without
# this record remain explicitly legacy; consumers must never call them
# source-exact.
#
# ASCII only for Windows PowerShell 5.1 compatibility.

$recoverySnapshotHelpers = Join-Path $PSScriptRoot '..\ship\publication-snapshot.ps1'
if (-not (Test-Path -LiteralPath $recoverySnapshotHelpers -PathType Leaf)) {
    throw "Publication snapshot helpers not found: $recoverySnapshotHelpers"
}
. $recoverySnapshotHelpers

function Test-VtReleaseRecoveryHasProperty {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -is [System.Collections.IDictionary]) {
        return $Value.Contains($Name)
    }
    return $null -ne $Value.PSObject.Properties[$Name]
}

function Get-VtReleaseRecoveryPropertySetProblems {
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $problems = @()
    if ($null -eq $Value) { return @("$Label is null") }
    $actual = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($Value -is [System.Collections.IDictionary]) {
        $actual = @($Value.Keys | ForEach-Object { [string]$_ })
    }
    foreach ($name in $Expected) {
        if ($actual -cnotcontains $name) { $problems += "$Label is missing '$name'" }
    }
    foreach ($name in $actual) {
        if ($Expected -cnotcontains $name) { $problems += "$Label has unsupported field '$name'" }
    }
    return @($problems)
}

function Get-VtReleaseRecoveryOptionalCommitBlobProof {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SourceCommit,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Recovery receipt lookup requires a lowercase full source commit SHA.'
    }
    if ([string]::IsNullOrWhiteSpace($RepoPath) -or
        $RepoPath.Contains('\') -or $RepoPath.StartsWith('/') -or
        @($RepoPath.Split('/')) -contains '..') {
        throw "Recovery receipt path is not canonical: '$RepoPath'."
    }
    $treeBytes = Invoke-PublicationGitBytes -RepoRoot $RepoRoot -ArgumentList @(
        'ls-tree', '-z', '--full-tree', $SourceCommit, '--', $RepoPath)
    $records = @([System.Text.Encoding]::UTF8.GetString([byte[]]$treeBytes).Split(
        [char[]]@([char]0),
        [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($records.Count -eq 0) { return $null }
    if ($records.Count -ne 1) {
        throw "Source commit $SourceCommit returned multiple recovery receipt paths for '$RepoPath'."
    }
    return Get-PublicationCommitBlobProof `
        -RepoRoot $RepoRoot -SourceCommit $SourceCommit -RepoPath $RepoPath
}

function Get-VtReleaseRecoveryBuildReceiptProof {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SourceCommit,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$PublicationSnapshot,
        [Parameter(Mandatory = $true)][string]$ExpectedBuilderVersion
    )

    if ([string]$PublicationSnapshot.SourceCommit -cne $SourceCommit -or
        [string]$PublicationSnapshot.AuthorityProof.SourceCommit -cne $SourceCommit) {
        throw "Recovery proof snapshot does not belong to source commit $SourceCommit."
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedBuilderVersion)) {
        throw 'Recovery proof requires the exact non-empty builder version.'
    }

    $receiptPath = "$Mod/.build-receipt.json"
    $receiptBlob = Get-VtReleaseRecoveryOptionalCommitBlobProof `
        -RepoRoot $RepoRoot -SourceCommit $SourceCommit -RepoPath $receiptPath
    if ($null -eq $receiptBlob) {
        if ([string]$PublicationSnapshot.BundleAuthority -ceq 'receipt') {
            throw "Receipt authority cannot publish without a committed schema-3 recovery receipt for '$Mod'."
        }
        return [pscustomobject][ordered]@{
            Available = $false
            Status = 'legacy_missing_build_receipt'
            Reason = "source commit has no $receiptPath"
        }
    }

    $receiptText = Get-VtPublicationSnapshotUtf8Text `
        -Bytes ([byte[]]$receiptBlob.Bytes) `
        -Label "Source-commit recovery receipt '$receiptPath'"
    $receipt = ConvertFrom-VtBuildReceiptJson -Json $receiptText
    $receiptSchema = [string]$receipt.schema
    if ($receiptSchema -ceq '2') {
        if ([string]$PublicationSnapshot.BundleAuthority -ceq 'receipt') {
            throw "Receipt authority recovery requires schema 3, got schema 2 for '$Mod'."
        }
        return [pscustomobject][ordered]@{
            Available = $false
            Status = 'legacy_build_receipt_schema'
            Reason = 'source commit carries legacy build receipt schema 2, not schema 3'
        }
    }
    if ($receiptSchema -cne '3') {
        throw "Recovery proof refuses unsupported or missing build receipt schema '$receiptSchema' for '$Mod'."
    }

    $context = Get-VtPublicationSnapshotInventoryContext `
        -RepoRoot $RepoRoot -SourceCommit $SourceCommit -Mod $Mod
    if ([string]$context.Authority -cne [string]$PublicationSnapshot.BundleAuthority -or
        [string]$context.InventoryProof.GitBlob -cne [string]$PublicationSnapshot.AuthorityProof.InventoryGitBlob -or
        [string]$context.IgnoreProof.GitBlob -cne [string]$PublicationSnapshot.AuthorityProof.IgnoreGitBlob -or
        [string]$context.Entry.WorkshopId -cne [string]$PublicationSnapshot.PublishedId) {
        throw "Recovery proof snapshot identity/authority differs from source-commit inventory/ignore proof for '$Mod'."
    }
    $normalizationPolicy = New-BuildOutputNormalizationPolicyProof -ModEntry $context.Entry
    $sourceMap = Get-VtBuildCommitSourceMap `
        -RepoRoot $RepoRoot -Mod $Mod -Commit $SourceCommit
    $verdict = Test-VtBuildReceiptProof `
        -Receipt $receipt `
        -ExpectedMod $Mod `
        -SourceMap $sourceMap `
        -OutputSet $PublicationSnapshot.OutputSet `
        -NormalizationPolicy $normalizationPolicy `
        -ExpectedBuilderVersion $ExpectedBuilderVersion `
        -MinimumSchema 3
    if (-not $verdict.Ok) {
        throw "Source-commit schema-3 recovery receipt is not exact for '$Mod': $(@($verdict.Problems) -join '; ')"
    }
    if ([string]$receipt.output_fingerprint_sha256 -cne [string]$PublicationSnapshot.OutputSet.Fingerprint -or
        [string]$receipt.output_algorithm -cne [string]$PublicationSnapshot.OutputSet.Algorithm -or
        [string]$receipt.root_bundle -cne [string]$PublicationSnapshot.AuthorityProof.RootBundle -or
        [string]$receipt.descriptor.filename -cne [string]$PublicationSnapshot.OutputSet.Descriptor.Name -or
        [string]$receipt.descriptor.sha256 -cne [string]$PublicationSnapshot.SourceDescriptor.Sha256) {
        throw "Source-commit schema-3 recovery receipt disagrees with the immutable publication snapshot for '$Mod'."
    }

    return [pscustomobject][ordered]@{
        Available = $true
        Status = 'source_exact_schema_3'
        Reason = ''
        Mod = $Mod
        ModId = [string]$context.Entry.ModId
        WorkshopId = [string]$context.Entry.WorkshopId
        SourceCommit = $SourceCommit
        BundleAuthority = [string]$context.Authority
        InventoryGitBlob = [string]$context.InventoryProof.GitBlob
        IgnoreGitBlob = [string]$context.IgnoreProof.GitBlob
        Path = $receiptPath
        GitBlob = [string]$receiptBlob.GitBlob
        Sha256 = [string]$receiptBlob.Sha256
        Schema = 3
        SourceAlgorithm = [string]$receipt.source_algorithm
        SourceFingerprintSha256 = [string]$receipt.source_fingerprint_sha256
        RootBundle = [string]$receipt.root_bundle
        DescriptorName = [string]$receipt.descriptor.filename
        DescriptorSha256 = [string]$receipt.descriptor.sha256
        OutputAlgorithm = [string]$receipt.output_algorithm
        OutputFingerprintSha256 = [string]$receipt.output_fingerprint_sha256
        BuilderName = [string]$receipt.builder.name
        BuilderVersion = [string]$receipt.builder.version
        NormalizationPolicy = [pscustomobject][ordered]@{
            Algorithm = [string]$receipt.normalization_policy.algorithm
            FingerprintSha256 = [string]$receipt.normalization_policy.fingerprint_sha256
            ExcludedOutputs = @($receipt.normalization_policy.excluded_outputs | ForEach-Object {
                [pscustomobject][ordered]@{
                    Filename = [string]$_.filename
                    Sha256 = [string]$_.sha256
                }
            })
        }
    }
}

function New-VtReleaseRecoveryRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$ReleaseTag,
        [Parameter(Mandatory = $true)][string]$ModFolder,
        [Parameter(Mandatory = $true)][string]$ModId,
        [Parameter(Mandatory = $true)][string]$WorkshopId,
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$AssetFilename,
        [Parameter(Mandatory = $true)][byte[]]$AssetBytes,
        [Parameter(Mandatory = $true)][string]$BuilderVersion,
        [Parameter(Mandatory = $true)]$PublicationSnapshot,
        [Parameter(Mandatory = $true)]$BuildReceiptProof
    )

    if ($Repository -cne 'Ensrick/vermintide-2-tweaker') {
        throw 'Recovery record repository must be Ensrick/vermintide-2-tweaker.'
    }
    if ($ReleaseTag -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw "Recovery record release tag is not canonical: '$ReleaseTag'."
    }
    if ($ModFolder -cnotmatch '^[a-z0-9][a-z0-9_]*$' -or
        $ModId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
        throw 'Recovery record mod folder or id is not canonical.'
    }
    if ($WorkshopId -cnotmatch '^[1-9][0-9]*$') {
        throw 'Recovery record requires an allocated positive Workshop id.'
    }
    if ([string]::IsNullOrWhiteSpace($Version) -or $Version -cne $Version.Trim()) {
        throw 'Recovery record version is empty or non-canonical.'
    }
    $assetLength = [long]$AssetBytes.LongLength
    $assetSha256 = if ($assetLength -gt 0) {
        Get-PublicationByteSha256 -Bytes $AssetBytes
    } else { '' }
    if ([System.IO.Path]::GetFileName($AssetFilename) -cne $AssetFilename -or
        $AssetFilename -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$' -or
        $AssetFilename -cne "$ModId.zip" -or
        $assetLength -le 0 -or $assetSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Recovery record asset coordinate must be the exact <mod_id>.zip leaf, with valid length and SHA-256.'
    }
    if (-not $BuildReceiptProof.Available -or
        [string]$BuildReceiptProof.Status -cne 'source_exact_schema_3') {
        throw 'Recovery record requires an exact committed schema-3 build receipt proof.'
    }

    $snapshot = $PublicationSnapshot
    $authority = [string]$snapshot.BundleAuthority
    $byteSource = if ($authority -ceq 'tracked') { 'git_commit_blobs' }
        elseif ($authority -ceq 'receipt') { 'materialized_restrictive_handles' }
        else { throw "Recovery record refuses unsupported bundle authority '$authority'." }
    if ([string]$snapshot.AuthorityProof.Authority -cne $authority -or
        [string]$snapshot.AuthorityProof.ByteSource -cne $byteSource -or
        [string]$snapshot.AuthorityProof.SourceCommit -cne [string]$snapshot.SourceCommit -or
        [string]$snapshot.AuthorityProof.OutputAlgorithm -cne [string]$snapshot.OutputSet.Algorithm -or
        [string]$snapshot.AuthorityProof.OutputFingerprintSha256 -cne [string]$snapshot.OutputSet.Fingerprint) {
        throw 'Recovery record snapshot authority proof is internally inconsistent.'
    }
    if ([string]$snapshot.PublishedId -cne $WorkshopId -or
        [string]$snapshot.Version -cne $Version -or
        [string]$BuildReceiptProof.Mod -cne $ModFolder -or
        [string]$BuildReceiptProof.ModId -cne $ModId -or
        [string]$BuildReceiptProof.WorkshopId -cne $WorkshopId -or
        [string]$BuildReceiptProof.SourceCommit -cne [string]$snapshot.SourceCommit -or
        [string]$BuildReceiptProof.BundleAuthority -cne $authority -or
        [string]$BuildReceiptProof.InventoryGitBlob -cne [string]$snapshot.AuthorityProof.InventoryGitBlob -or
        [string]$BuildReceiptProof.IgnoreGitBlob -cne [string]$snapshot.AuthorityProof.IgnoreGitBlob -or
        [string]$BuildReceiptProof.RootBundle -cne [string]$snapshot.AuthorityProof.RootBundle -or
        [string]$BuildReceiptProof.DescriptorName -cne [string]$snapshot.OutputSet.Descriptor.Name -or
        [string]$BuildReceiptProof.DescriptorSha256 -cne [string]$snapshot.OutputSet.Descriptor.Sha256 -or
        [string]$BuildReceiptProof.OutputAlgorithm -cne [string]$snapshot.OutputSet.Algorithm -or
        [string]$BuildReceiptProof.OutputFingerprintSha256 -cne [string]$snapshot.OutputSet.Fingerprint -or
        [string]$BuildReceiptProof.BuilderName -cne 'VMBLauncher' -or
        [string]$BuildReceiptProof.BuilderVersion -cne $BuilderVersion) {
        throw 'Recovery record identity or builder differs from the immutable snapshot/receipt.'
    }
    if ([string]$snapshot.ItemCfg.GitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$snapshot.ItemCfg.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$snapshot.SourceDescriptor.GitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$snapshot.SourceDescriptor.Sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$snapshot.AuthorityProof.InventoryGitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$snapshot.AuthorityProof.IgnoreGitBlob -cnotmatch '^[0-9a-f]{40,64}$') {
        throw 'Recovery record snapshot lacks exact source-commit blob proof.'
    }

    $outputFiles = @()
    foreach ($record in @($snapshot.OutputSet.Files)) {
        $matches = @($snapshot.BundleFiles | Where-Object { [string]$_.Path -ceq [string]$record.Name })
        if ($matches.Count -ne 1 -or
            [long]$matches[0].Length -ne [long]$record.Length -or
            [string]$matches[0].Sha256 -cne [string]$record.Sha256) {
            throw "Recovery record output '$($record.Name)' lacks one immutable byte proof."
        }
        $gitBlob = [string]$matches[0].GitBlob
        if (($authority -ceq 'tracked' -and $gitBlob -cnotmatch '^[0-9a-f]{40,64}$') -or
            ($authority -ceq 'receipt' -and -not [string]::IsNullOrEmpty($gitBlob))) {
            throw "Recovery record output '$($record.Name)' has an invalid authority-specific Git blob."
        }
        $outputFiles += [ordered]@{
            filename = [string]$record.Name
            length = [long]$record.Length
            sha256 = [string]$record.Sha256
            git_blob = $gitBlob
        }
    }
    if ($outputFiles.Count -eq 0 -or $outputFiles.Count -ne @($snapshot.BundleFiles).Count) {
        throw 'Recovery record requires one complete non-empty output map.'
    }

    return [ordered]@{
        schema = 1
        release = [ordered]@{
            repository = $Repository
            tag = $ReleaseTag
        }
        mod_folder = $ModFolder
        mod_id = $ModId
        workshop_id = $WorkshopId
        version = $Version
        asset = [ordered]@{
            filename = $AssetFilename
            length = $assetLength
            sha256 = $assetSha256
        }
        source = [ordered]@{
            commit = [string]$snapshot.SourceCommit
            state = 'clean'
            item_cfg_sha256 = [string]$snapshot.ItemCfg.Sha256
            item_cfg_git_blob = [string]$snapshot.ItemCfg.GitBlob
        }
        builder = [ordered]@{
            name = 'VMBLauncher'
            version = $BuilderVersion
        }
        bundle_authority = $authority
        authority_proof = [ordered]@{
            byte_source = $byteSource
            inventory_git_blob = [string]$snapshot.AuthorityProof.InventoryGitBlob
            ignore_git_blob = [string]$snapshot.AuthorityProof.IgnoreGitBlob
        }
        root_bundle = [string]$snapshot.AuthorityProof.RootBundle
        descriptor = [ordered]@{
            filename = [string]$snapshot.OutputSet.Descriptor.Name
            sha256 = [string]$snapshot.SourceDescriptor.Sha256
            git_blob = [string]$snapshot.SourceDescriptor.GitBlob
        }
        output = [ordered]@{
            algorithm = [string]$snapshot.OutputSet.Algorithm
            fingerprint_sha256 = [string]$snapshot.OutputSet.Fingerprint
            files = $outputFiles
        }
        build_receipt = [ordered]@{
            path = [string]$BuildReceiptProof.Path
            schema = 3
            git_blob = [string]$BuildReceiptProof.GitBlob
            sha256 = [string]$BuildReceiptProof.Sha256
            source_algorithm = [string]$BuildReceiptProof.SourceAlgorithm
            source_fingerprint_sha256 = [string]$BuildReceiptProof.SourceFingerprintSha256
            root_bundle = [string]$BuildReceiptProof.RootBundle
            descriptor_name = [string]$BuildReceiptProof.DescriptorName
            descriptor_sha256 = [string]$BuildReceiptProof.DescriptorSha256
            output_algorithm = [string]$BuildReceiptProof.OutputAlgorithm
            output_fingerprint_sha256 = [string]$BuildReceiptProof.OutputFingerprintSha256
            builder_name = [string]$BuildReceiptProof.BuilderName
            builder_version = [string]$BuildReceiptProof.BuilderVersion
            normalization_policy = [ordered]@{
                algorithm = [string]$BuildReceiptProof.NormalizationPolicy.Algorithm
                fingerprint_sha256 = [string]$BuildReceiptProof.NormalizationPolicy.FingerprintSha256
                excluded_outputs = @($BuildReceiptProof.NormalizationPolicy.ExcludedOutputs | ForEach-Object {
                    [ordered]@{
                        filename = [string]$_.Filename
                        sha256 = [string]$_.Sha256
                    }
                })
            }
        }
    }
}

function Test-VtReleaseRecoveryRecord {
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $true)]$ManifestEntry,
        [Parameter(Mandatory = $true)][string]$ManifestReleaseTag,
        [switch]$RequireManifestReleaseTag
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($problem in @(Get-VtReleaseRecoveryPropertySetProblems -Value $Record -Label 'recovery' -Expected @(
        'schema', 'release', 'mod_folder', 'mod_id', 'workshop_id', 'version', 'asset',
        'source', 'builder', 'bundle_authority', 'authority_proof', 'root_bundle',
        'descriptor', 'output', 'build_receipt'))) { $errors.Add($problem) }
    foreach ($definition in @(
        [pscustomobject]@{ Value = $Record.release; Label = 'recovery.release'; Names = @('repository', 'tag') },
        [pscustomobject]@{ Value = $Record.asset; Label = 'recovery.asset'; Names = @('filename', 'length', 'sha256') },
        [pscustomobject]@{ Value = $Record.source; Label = 'recovery.source'; Names = @('commit', 'state', 'item_cfg_sha256', 'item_cfg_git_blob') },
        [pscustomobject]@{ Value = $Record.builder; Label = 'recovery.builder'; Names = @('name', 'version') },
        [pscustomobject]@{ Value = $Record.authority_proof; Label = 'recovery.authority_proof'; Names = @('byte_source', 'inventory_git_blob', 'ignore_git_blob') },
        [pscustomobject]@{ Value = $Record.descriptor; Label = 'recovery.descriptor'; Names = @('filename', 'sha256', 'git_blob') },
        [pscustomobject]@{ Value = $Record.output; Label = 'recovery.output'; Names = @('algorithm', 'fingerprint_sha256', 'files') },
        [pscustomobject]@{ Value = $Record.build_receipt; Label = 'recovery.build_receipt'; Names = @('path', 'schema', 'git_blob', 'sha256', 'source_algorithm', 'source_fingerprint_sha256', 'root_bundle', 'descriptor_name', 'descriptor_sha256', 'output_algorithm', 'output_fingerprint_sha256', 'builder_name', 'builder_version', 'normalization_policy') },
        [pscustomobject]@{ Value = $Record.build_receipt.normalization_policy; Label = 'recovery.build_receipt.normalization_policy'; Names = @('algorithm', 'fingerprint_sha256', 'excluded_outputs') }
    )) {
        foreach ($problem in @(Get-VtReleaseRecoveryPropertySetProblems `
            -Value $definition.Value -Expected $definition.Names -Label $definition.Label)) {
            $errors.Add($problem)
        }
    }

    if ([string]$Record.schema -cne '1') { $errors.Add('recovery.schema must be 1') }
    if ([string]$Record.release.repository -cne 'Ensrick/vermintide-2-tweaker') { $errors.Add('recovery.release.repository is invalid') }
    if ([string]$Record.release.tag -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        $errors.Add('recovery.release.tag is not canonical')
    }
    elseif ($RequireManifestReleaseTag -and
        [string]$Record.release.tag -cne $ManifestReleaseTag) {
        $errors.Add('newly staged recovery.release.tag differs from manifest release_tag')
    }
    if ([string]$Record.mod_folder -cnotmatch '^[a-z0-9][a-z0-9_]*$') { $errors.Add('recovery.mod_folder is not canonical') }
    if ([string]$Record.mod_id -cne [string]$ManifestEntry.mod_id) { $errors.Add('recovery.mod_id differs from manifest entry') }
    if ([string]$Record.workshop_id -cne [string]$ManifestEntry.workshop_id -or
        [string]$Record.workshop_id -cnotmatch '^[1-9][0-9]*$') { $errors.Add('recovery.workshop_id differs or is invalid') }
    if ([string]$Record.version -cne [string]$ManifestEntry.version) { $errors.Add('recovery.version differs from manifest entry') }
    if ([string]$Record.asset.filename -cne "$($Record.mod_id).zip" -or
        [string]$Record.asset.filename -cne [string]$ManifestEntry.asset_filename -or
        [System.IO.Path]::GetFileName([string]$Record.asset.filename) -cne [string]$Record.asset.filename) { $errors.Add('recovery.asset.filename differs or is not a leaf') }
    $assetLengthText = [string]$Record.asset.length
    $assetLength = 0L
    $assetLengthValid = $assetLengthText -cmatch '^[1-9][0-9]*$' -and
        [long]::TryParse($assetLengthText, [ref]$assetLength)
    if (-not $assetLengthValid -or $assetLength -le 0) {
        $errors.Add('recovery.asset.length must be a positive integer')
    }
    if ([string]$Record.asset.sha256 -cne [string]$ManifestEntry.sha256 -or
        [string]$Record.asset.sha256 -cnotmatch '^[0-9a-f]{64}$') { $errors.Add('recovery.asset.sha256 differs or is invalid') }
    if ([string]$Record.source.commit -cne [string]$ManifestEntry.source_commit -or
        [string]$Record.source.commit -cnotmatch '^[0-9a-f]{40}$') { $errors.Add('recovery.source.commit differs or is invalid') }
    if ([string]$Record.source.state -cne 'clean' -or
        [string]$Record.source.state -cne [string]$ManifestEntry.source_state) { $errors.Add('recovery.source.state must equal clean manifest source_state') }
    if ([string]$Record.source.item_cfg_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Record.source.item_cfg_git_blob -cnotmatch '^[0-9a-f]{40,64}$') { $errors.Add('recovery item cfg proof is invalid') }
    if ([string]$Record.builder.name -cne 'VMBLauncher' -or
        [string]$Record.builder.name -cne [string]$ManifestEntry.builder.name -or
        [string]$Record.builder.version -cne [string]$ManifestEntry.builder.version -or
        [string]::IsNullOrWhiteSpace([string]$Record.builder.version)) { $errors.Add('recovery.builder differs or is invalid') }

    $authority = [string]$Record.bundle_authority
    $expectedByteSource = if ($authority -ceq 'tracked') { 'git_commit_blobs' }
        elseif ($authority -ceq 'receipt') { 'materialized_restrictive_handles' }
        else { ''; $errors.Add("recovery.bundle_authority is unsupported: '$authority'") }
    if ([string]$Record.authority_proof.byte_source -cne $expectedByteSource) { $errors.Add('recovery authority byte source is invalid') }
    if ([string]$Record.authority_proof.inventory_git_blob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$Record.authority_proof.ignore_git_blob -cnotmatch '^[0-9a-f]{40,64}$') { $errors.Add('recovery authority Git blob proof is invalid') }
    if ([string]$Record.root_bundle -cne [string]$ManifestEntry.root_bundle -or
        [string]$Record.root_bundle -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') { $errors.Add('recovery.root_bundle differs or is invalid') }
    if ([string]$Record.descriptor.filename -cne [string]$ManifestEntry.descriptor_name -or
        [string]$Record.descriptor.filename -cne "$($Record.mod_folder).mod" -or
        [string]$Record.descriptor.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Record.descriptor.git_blob -cnotmatch '^[0-9a-f]{40,64}$') { $errors.Add('recovery.descriptor proof differs or is invalid') }

    $outputRows = @($Record.output.files | Where-Object { $null -ne $_ })
    $manifestRows = @($ManifestEntry.bundle_files | Where-Object { $null -ne $_ })
    if ($outputRows.Count -eq 0 -or $outputRows.Count -ne $manifestRows.Count) {
        $errors.Add('recovery output count differs from manifest bundle_files')
    }
    $outputRecords = @()
    foreach ($row in $outputRows) {
        foreach ($problem in @(Get-VtReleaseRecoveryPropertySetProblems -Value $row -Label 'recovery.output.files[]' -Expected @('filename', 'length', 'sha256', 'git_blob'))) { $errors.Add($problem) }
        $name = [string]$row.filename
        $manifestMatches = @($manifestRows | Where-Object {
            [string]$_.filename -ceq $name
        })
        if ($manifestMatches.Count -ne 1 -or
            [string]$manifestMatches[0].sha256 -cne [string]$row.sha256) {
            $errors.Add("recovery output '$name' differs from manifest bundle_files")
        }
        $rowLengthText = [string]$row.length
        $rowLength = 0L
        $rowLengthValid = $rowLengthText -cmatch '^[1-9][0-9]*$' -and
            [long]::TryParse($rowLengthText, [ref]$rowLength)
        if (-not $rowLengthValid -or [string]$row.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            $errors.Add("recovery output '$name' has invalid length or SHA-256")
        }
        if (($authority -ceq 'tracked' -and [string]$row.git_blob -cnotmatch '^[0-9a-f]{40,64}$') -or
            ($authority -ceq 'receipt' -and -not [string]::IsNullOrEmpty([string]$row.git_blob))) {
            $errors.Add("recovery output '$name' has invalid authority-specific Git blob")
        }
        $outputRecords += [pscustomobject]@{
            Name = $name
            Length = if ($rowLengthValid) { $rowLength } else { 0L }
            Sha256 = [string]$row.sha256
        }
    }
    try {
        $canonicalOutput = New-VtBundleOutputSet `
            -Records $outputRecords `
            -ExpectedDescriptorName ([string]$Record.descriptor.filename) `
            -ExpectedRootBundle ([string]$Record.root_bundle) `
            -ExpectedDescriptorSha256 ([string]$Record.descriptor.sha256)
        if ([string]$Record.output.algorithm -cne [string]$canonicalOutput.Algorithm -or
            [string]$Record.output.fingerprint_sha256 -cne [string]$canonicalOutput.Fingerprint) {
            $errors.Add('recovery output algorithm or fingerprint is not canonical')
        }
        $canonicalRows = @($canonicalOutput.Files)
        for ($index = 0; $index -lt [Math]::Min($canonicalRows.Count, $outputRows.Count); $index++) {
            if ([string]$outputRows[$index].filename -cne [string]$canonicalRows[$index].Name) {
                $errors.Add('recovery output files are not in canonical ordinal order')
                break
            }
        }
    }
    catch { $errors.Add("recovery output map is invalid: $($_.Exception.Message)") }

    $buildReceipt = $Record.build_receipt
    if ([string]$buildReceipt.path -cne "$($Record.mod_folder)/.build-receipt.json" -or
        [string]$buildReceipt.schema -cne '3' -or
        [string]$buildReceipt.git_blob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$buildReceipt.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$buildReceipt.source_algorithm -cne 'git-blob-build-byte-map-sha256-v2' -or
        [string]$buildReceipt.source_fingerprint_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$buildReceipt.root_bundle -cne [string]$Record.root_bundle -or
        [string]$buildReceipt.descriptor_name -cne [string]$Record.descriptor.filename -or
        [string]$buildReceipt.descriptor_sha256 -cne [string]$Record.descriptor.sha256 -or
        [string]$buildReceipt.output_algorithm -cne [string]$Record.output.algorithm -or
        [string]$buildReceipt.output_fingerprint_sha256 -cne [string]$Record.output.fingerprint_sha256 -or
        [string]$buildReceipt.builder_name -cne [string]$Record.builder.name -or
        [string]$buildReceipt.builder_version -cne [string]$Record.builder.version) {
        $errors.Add('recovery build receipt proof is invalid or differs from the record builder')
    }
    $policy = $buildReceipt.normalization_policy
    if ($null -eq $policy.excluded_outputs) {
        $errors.Add('recovery.build_receipt.normalization_policy.excluded_outputs is null')
    }
    foreach ($excluded in @($policy.excluded_outputs | Where-Object { $null -ne $_ })) {
        foreach ($problem in @(Get-VtReleaseRecoveryPropertySetProblems `
            -Value $excluded `
            -Label 'recovery.build_receipt.normalization_policy.excluded_outputs[]' `
            -Expected @('filename', 'sha256'))) {
            $errors.Add($problem)
        }
    }
    $serializedPolicy = [pscustomobject]@{
        Algorithm = [string]$policy.algorithm
        FingerprintSha256 = [string]$policy.fingerprint_sha256
        ExcludedOutputs = @($policy.excluded_outputs | ForEach-Object {
            [pscustomobject]@{ Filename = [string]$_.filename; Sha256 = [string]$_.sha256 }
        })
    }
    $policyVerdict = Get-BuildOutputNormalizationPolicyProofValidation `
        -Proof $serializedPolicy -Label 'recovery'
    foreach ($problem in @($policyVerdict.Problems)) { $errors.Add($problem) }

    return [pscustomobject][ordered]@{
        Valid = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}
