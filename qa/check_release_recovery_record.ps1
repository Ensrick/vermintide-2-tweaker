# check_release_recovery_record.ps1 - durable source-exact release recovery proof (#1430).
#
# This is a producer-only contract. It does not select, download, install, or
# restore a release asset. -SelfTest is offline and performs no real mutation.
# ASCII only for Windows PowerShell 5.1 compatibility.

[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1')

function Get-TestSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Write-TestUtf8 {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $parent = Split-Path $Path -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)][string]$FixtureRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git -C $FixtureRoot @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) {
        throw "fixture git $($Arguments -join ' ') failed ($exitCode): $($lines -join ' | ')"
    }
    return ,([string[]]$lines)
}

function Copy-TestObject {
    param([Parameter(Mandatory = $true)]$Value)
    return ($Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}

function Remove-TestDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if (-not $full.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($full) -cnotmatch '^vt2-release-recovery-[0-9a-f]{32}$') {
        throw "Refusing to clean unexpected test directory: $full"
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $full -Force -Recurse -File)) {
        $file.Attributes = [System.IO.FileAttributes]::Normal
        Remove-Item -LiteralPath $file.FullName -Force
    }
    foreach ($directory in @(Get-ChildItem -LiteralPath $full -Force -Recurse -Directory |
        Sort-Object { $_.FullName.Length } -Descending)) {
        Remove-Item -LiteralPath $directory.FullName -Force
    }
    Remove-Item -LiteralPath $full -Force
}

function Invoke-SelfTest {
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('vt2-release-recovery-' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($fixture) | Out-Null
    $failures = [System.Collections.Generic.List[string]]::new()

    function Assert([bool]$Condition, [string]$Description) {
        if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
        else {
            Write-Host "  [FAIL] $Description" -ForegroundColor Red
            $failures.Add($Description)
        }
    }

    try {
        $mod = 'modx'
        $modId = 'mx'
        $workshopId = '1234567890'
        $version = '1.2.3-dev'
        $builderVersion = '9.8.7+fixture'
        $rootBundle = '0123456789abcdef.mod_bundle'
        $sidecarBundle = 'fedcba9876543210.mod_bundle'
        $descriptorName = 'modx.mod'

        Write-TestUtf8 -Path (Join-Path $fixture '.gitattributes') -Text "* -text`n"
        Write-TestUtf8 -Path (Join-Path $fixture '.gitignore') -Text "# fixture`n"
        Write-TestUtf8 -Path (Join-Path $fixture 'tools\mod-inventory.psd1') -Text @"
@{
    Mods = @(
        @{
            Dir = 'modx'; ModId = 'mx'; WorkshopId = '1234567890';
            Visibility = 'friends_only'; Stream = 'dev'; Public = `$false;
            Name = 'Recovery Fixture'; BundleAuthority = 'tracked';
            RootBundle = '0123456789abcdef.mod_bundle';
            BuildArtifactExclusions = @()
        }
    )
}
"@
        Write-TestUtf8 -Path (Join-Path $fixture 'modx\itemV2.cfg') -Text @"
published_id = 1234567890L
visibility = "friends_only"
preview = "item_preview.png"
"@
        Write-TestUtf8 -Path (Join-Path $fixture 'modx\modx.mod') -Text "fixture descriptor`n"
        Write-TestUtf8 -Path (Join-Path $fixture 'modx\scripts\mods\modx\modx.lua') -Text @"
local MOD_VERSION = "1.2.3-dev"
return MOD_VERSION
"@
        [System.IO.File]::WriteAllBytes(
            (Join-Path $fixture 'modx\item_preview.png'),
            [byte[]](137, 80, 78, 71, 13, 10, 26, 10))
        [System.IO.Directory]::CreateDirectory((Join-Path $fixture 'modx\bundleV2')) | Out-Null
        [System.IO.File]::WriteAllBytes(
            (Join-Path $fixture "modx\bundleV2\$rootBundle"),
            [byte[]](1, 3, 3, 7, 9, 11, 13, 17))
        [System.IO.File]::WriteAllBytes(
            (Join-Path $fixture "modx\bundleV2\$sidecarBundle"),
            [byte[]](2, 4, 6, 8, 10, 12, 14, 16))
        [System.IO.File]::WriteAllBytes(
            (Join-Path $fixture "modx\bundleV2\$descriptorName"),
            [System.IO.File]::ReadAllBytes((Join-Path $fixture 'modx\modx.mod')))

        $null = & git init $fixture 2>&1
        if ($LASTEXITCODE -ne 0) { throw 'fixture git init failed' }
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('config', 'user.name', 'Recovery Test')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('config', 'user.email', 'recovery@example.invalid')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('config', 'commit.gpgsign', 'false')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('add', '--all')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('commit', '-m', 'fixture source')
        $commitWithoutReceipt = [string](@(Invoke-TestGit -FixtureRoot $fixture -Arguments @('rev-parse', 'HEAD'))[-1]).Trim()

        $snapshotWithoutReceipt = Get-VtPublicationSnapshot `
            -RepoRoot $fixture -SourceCommit $commitWithoutReceipt -Mod $mod
        $legacyMissing = Get-VtReleaseRecoveryBuildReceiptProof `
            -RepoRoot $fixture -SourceCommit $commitWithoutReceipt -Mod $mod `
            -PublicationSnapshot $snapshotWithoutReceipt -ExpectedBuilderVersion $builderVersion
        Assert (
            -not $legacyMissing.Available -and
            [string]$legacyMissing.Status -ceq 'legacy_missing_build_receipt'
        ) 'classifies a tracked commit without a receipt as explicit legacy, never source-exact'

        $sourceMap = Get-VtBuildCommitSourceMap `
            -RepoRoot $fixture -Mod $mod -Commit $commitWithoutReceipt
        $inventoryContext = Get-VtPublicationSnapshotInventoryContext `
            -RepoRoot $fixture -SourceCommit $commitWithoutReceipt -Mod $mod
        $normalizationPolicy = New-BuildOutputNormalizationPolicyProof `
            -ModEntry $inventoryContext.Entry
        $receipt = New-VtBuildReceipt `
            -Mod $mod `
            -SourceMap $sourceMap `
            -OutputSet $snapshotWithoutReceipt.OutputSet `
            -BuilderVersion $builderVersion `
            -NormalizationPolicy $normalizationPolicy
        Write-TestUtf8 `
            -Path (Join-Path $fixture 'modx\.build-receipt.json') `
            -Text (ConvertTo-VtBuildReceiptJson -Receipt $receipt)
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('add', 'modx/.build-receipt.json')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('commit', '-m', 'schema 3 receipt')
        $sourceCommit = [string](@(Invoke-TestGit -FixtureRoot $fixture -Arguments @('rev-parse', 'HEAD'))[-1]).Trim()

        $snapshot = Get-VtPublicationSnapshot `
            -RepoRoot $fixture -SourceCommit $sourceCommit -Mod $mod
        $receiptProof = Get-VtReleaseRecoveryBuildReceiptProof `
            -RepoRoot $fixture -SourceCommit $sourceCommit -Mod $mod `
            -PublicationSnapshot $snapshot -ExpectedBuilderVersion $builderVersion
        Assert (
            $receiptProof.Available -and
            [string]$receiptProof.Status -ceq 'source_exact_schema_3'
        ) 'accepts only the exact committed schema-3 source/output/builder/policy receipt'

        $zipBytes = New-ReleaseZipBytesFromImmutableOutput `
            -OutputSet $snapshot.OutputSet `
            -BundleFiles @($snapshot.BundleFiles) `
            -Version $version
        $zipSha = Get-TestSha256 -Bytes $zipBytes
        $record = New-VtReleaseRecoveryRecord `
            -Repository 'Ensrick/vermintide-2-tweaker' `
            -ReleaseTag 'mods-test' `
            -ModFolder $mod `
            -ModId $modId `
            -WorkshopId $workshopId `
            -Version $version `
            -AssetFilename 'mx.zip' `
            -AssetBytes $zipBytes `
            -BuilderVersion $builderVersion `
            -PublicationSnapshot $snapshot `
            -BuildReceiptProof $receiptProof
        $bundleFiles = @($snapshot.OutputSet.Files | ForEach-Object {
            [ordered]@{ filename = [string]$_.Name; sha256 = [string]$_.Sha256 }
        })
        $entry = [ordered]@{
            mod_id = $modId; friendly_name = 'Recovery Fixture'; workshop_id = $workshopId
            version = $version; asset_filename = 'mx.zip'; sha256 = $zipSha
            visibility = 'friends_only'; source_commit = $sourceCommit; source_state = 'clean'
            bundle_authority = 'tracked'
            builder = [ordered]@{ name = 'VMBLauncher'; version = $builderVersion }
            root_bundle = $rootBundle; descriptor_name = $descriptorName
            bundle_files = $bundleFiles; recovery = $record
            publication_authorization = [ordered]@{
                mode = 'hosted_qa'; source_commit = $sourceCommit
                checked_at_utc = '2026-08-26T00:00:00Z'; default_branch = 'master'
                default_branch_commit = $sourceCommit; merged_pr_number = 1430
                qa_check = 'qa-gate'; qa_check_url = 'https://example.invalid/1430'
                qa_completed_at_utc = '2026-08-26T00:00:00Z'
            }
        }
        $manifest = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'
            published_at = '2026-08-26T00:00:00Z'; mods = @($entry)
        }

        $recordVerdict = Test-VtReleaseRecoveryRecord `
            -Record $record -ManifestEntry $entry -ManifestReleaseTag 'mods-test' `
            -RequireManifestReleaseTag
        Assert $recordVerdict.Valid 'validates the complete source-exact recovery record'
        $manifestVerdict = Test-ReleaseManifest `
            -Manifest $manifest -RequiredModIds @($modId)
        Assert (
            $manifestVerdict.Valid -and $manifestVerdict.Warnings.Count -eq 0
        ) 'newly staged entry with exact recovery proof validates without legacy warnings'
        $detachedAuthorityManifest = Copy-TestObject -Value $manifest
        $detachedAuthorityManifest.mods[0].PSObject.Properties.Remove('bundle_authority')
        Assert (-not (Test-ReleaseManifest `
            -Manifest $detachedAuthorityManifest -RequiredModIds @($modId)).Valid
        ) 'manifest cannot detach a recovery record from its declared authority'
        $carriedManifest = Copy-TestObject -Value $manifest
        $carriedManifest.release_tag = 'mods-next-day'
        $carriedVerdict = Test-ReleaseManifest -Manifest $carriedManifest
        $restagedVerdict = Test-ReleaseManifest `
            -Manifest $carriedManifest -RequiredModIds @($modId)
        Assert (
            $carriedVerdict.Valid -and -not $restagedVerdict.Valid
        ) 'verbatim carry retains its original asset tag while a newly staged row must bind the current tag'
        $zipVerdict = Test-ReleaseZipSnapshot -ZipBytes $zipBytes -ManifestEntry $entry
        Assert (
            $zipVerdict.Valid -and
            [long]$record.asset.length -eq [long]$zipBytes.LongLength -and
            [string]$record.asset.sha256 -ceq $zipSha
        ) 'record immutable asset length/hash and strict inner ZIP map bind the same bytes'
        Assert (
            @($record.output.files).Count -eq @($snapshot.OutputSet.Files).Count -and
            [string]$record.output.fingerprint_sha256 -ceq [string]$snapshot.OutputSet.Fingerprint
        ) 'record carries the complete canonical output map and fingerprint'

        [System.IO.File]::WriteAllBytes(
            (Join-Path $fixture "modx\bundleV2\$rootBundle"),
            [byte[]](99, 98, 97))
        $snapshotAfterMutation = Get-VtPublicationSnapshot `
            -RepoRoot $fixture -SourceCommit $sourceCommit -Mod $mod
        $proofAfterMutation = Get-VtReleaseRecoveryBuildReceiptProof `
            -RepoRoot $fixture -SourceCommit $sourceCommit -Mod $mod `
            -PublicationSnapshot $snapshotAfterMutation -ExpectedBuilderVersion $builderVersion
        $zipAfterMutation = New-ReleaseZipBytesFromImmutableOutput `
            -OutputSet $snapshotAfterMutation.OutputSet `
            -BundleFiles @($snapshotAfterMutation.BundleFiles) `
            -Version $version
        $recordAfterMutation = New-VtReleaseRecoveryRecord `
            -Repository 'Ensrick/vermintide-2-tweaker' -ReleaseTag 'mods-test' `
            -ModFolder $mod -ModId $modId -WorkshopId $workshopId -Version $version `
            -AssetFilename 'mx.zip' -AssetBytes $zipAfterMutation `
            -BuilderVersion $builderVersion -PublicationSnapshot $snapshotAfterMutation `
            -BuildReceiptProof $proofAfterMutation
        Assert (
            (Get-TestSha256 -Bytes $zipAfterMutation) -ceq $zipSha -and
            ($recordAfterMutation | ConvertTo-Json -Depth 20 -Compress) -ceq
                ($record | ConvertTo-Json -Depth 20 -Compress)
        ) 'working-tree replacement cannot alter a commit-qualified recovery record or ZIP'

        function Assert-RecoveryReject {
            param([Parameter(Mandatory = $true)][string]$Description,
                [Parameter(Mandatory = $true)][scriptblock]$Mutate)
            $candidate = Copy-TestObject -Value $record
            & $Mutate $candidate
            try {
                $verdict = Test-VtReleaseRecoveryRecord `
                    -Record $candidate -ManifestEntry $entry -ManifestReleaseTag 'mods-test' `
                    -RequireManifestReleaseTag
                Assert (-not $verdict.Valid) $Description
            }
            catch {
                Assert $false "$Description (validator threw: $($_.Exception.Message))"
            }
        }

        Assert-RecoveryReject 'rejects unsupported recovery fields' {
            param($value); $value | Add-Member -NotePropertyName forged -NotePropertyValue $true
        }
        Assert-RecoveryReject 'rejects a different immutable release tag' {
            param($value); $value.release.tag = 'mods-other'
        }
        Assert-RecoveryReject 'rejects a different Workshop identity' {
            param($value); $value.workshop_id = '9999999999'
        }
        Assert-RecoveryReject 'rejects a malformed asset length without throwing' {
            param($value); $value.asset.length = '999999999999999999999999999999'
        }
        $crossModAssetRecord = Copy-TestObject -Value $record
        $crossModAssetEntry = Copy-TestObject -Value $entry
        $crossModAssetRecord.asset.filename = 'other_valid_mod.zip'
        $crossModAssetEntry.asset_filename = 'other_valid_mod.zip'
        $crossModAssetVerdict = Test-VtReleaseRecoveryRecord `
            -Record $crossModAssetRecord -ManifestEntry $crossModAssetEntry `
            -ManifestReleaseTag 'mods-test' -RequireManifestReleaseTag
        Assert (-not $crossModAssetVerdict.Valid) `
            'rejects a self-consistent canonical ZIP name that is not the exact mod-id asset'
        Assert-RecoveryReject 'rejects a different asset hash' {
            param($value); $value.asset.sha256 = ('0' * 64)
        }
        Assert-RecoveryReject 'rejects a different source commit' {
            param($value); $value.source.commit = ('f' * 40)
        }
        Assert-RecoveryReject 'rejects a different builder provenance' {
            param($value); $value.builder.version = 'other-builder'
        }
        Assert-RecoveryReject 'rejects a different canonical root' {
            param($value); $value.root_bundle = 'fedcba9876543210.mod_bundle'
        }
        Assert-RecoveryReject 'rejects a different descriptor proof' {
            param($value); $value.descriptor.sha256 = ('1' * 64)
        }
        Assert-RecoveryReject 'rejects an incomplete output map' {
            param($value); $value.output.files = @($value.output.files | Select-Object -Skip 1)
        }
        Assert-RecoveryReject 'rejects a changed output length/fingerprint pair' {
            param($value); $value.output.files[0].length = [long]$value.output.files[0].length + 1
        }
        Assert-RecoveryReject 'rejects noncanonical output order' {
            param($value); $value.output.files = @($value.output.files | Sort-Object filename -Descending)
        }
        $caseDetachedManifestEntry = Copy-TestObject -Value $entry
        $caseDetachedManifestRow = @($caseDetachedManifestEntry.bundle_files | Where-Object {
            [string]$_.filename -ceq $sidecarBundle
        })
        $caseDetachedManifestRow[0].filename = $sidecarBundle.ToUpperInvariant()
        $caseDetachedVerdict = Test-VtReleaseRecoveryRecord `
            -Record $record -ManifestEntry $caseDetachedManifestEntry `
            -ManifestReleaseTag 'mods-test' -RequireManifestReleaseTag
        Assert (-not $caseDetachedVerdict.Valid) `
            'rejects a case-only parent-manifest detachment on a non-root output filename'
        Assert-RecoveryReject 'rejects tracked output without its exact Git blob' {
            param($value); $value.output.files[0].git_blob = ''
        }
        Assert-RecoveryReject 'rejects a detached build-receipt output proof' {
            param($value); $value.build_receipt.output_fingerprint_sha256 = ('2' * 64)
        }
        Assert-RecoveryReject 'rejects a different build-receipt source algorithm' {
            param($value); $value.build_receipt.source_algorithm = 'legacy-source-map-v1'
        }
        Assert-RecoveryReject 'rejects a changed normalization proof' {
            param($value); $value.build_receipt.normalization_policy.fingerprint_sha256 = ('3' * 64)
        }
        Assert-RecoveryReject 'rejects a null normalization exclusion collection' {
            param($value); $value.build_receipt.normalization_policy.excluded_outputs = $null
        }
        Assert-RecoveryReject 'rejects a missing nested receipt object without throwing' {
            param($value); $value.build_receipt = $null
        }

        $mismatchedSnapshot = Copy-TestObject -Value $snapshot
        $mismatchedSnapshot.OutputSet.Fingerprint = ('4' * 64)
        $mismatchedSnapshot.AuthorityProof.OutputFingerprintSha256 = ('4' * 64)
        $constructorRejected = $false
        try {
            $null = New-VtReleaseRecoveryRecord `
                -Repository 'Ensrick/vermintide-2-tweaker' -ReleaseTag 'mods-test' `
                -ModFolder $mod -ModId $modId -WorkshopId $workshopId -Version $version `
                -AssetFilename 'mx.zip' -AssetBytes $zipBytes `
                -BuilderVersion $builderVersion -PublicationSnapshot $mismatchedSnapshot `
                -BuildReceiptProof $receiptProof
        }
        catch { $constructorRejected = $true }
        Assert $constructorRejected 'constructor rejects a coherently mutated snapshot detached from its receipt'
        $wrongModIdRejected = $false
        try {
            $null = New-VtReleaseRecoveryRecord `
                -Repository 'Ensrick/vermintide-2-tweaker' -ReleaseTag 'mods-test' `
                -ModFolder $mod -ModId 'wrong' -WorkshopId $workshopId -Version $version `
                -AssetFilename 'mx.zip' -AssetBytes $zipBytes `
                -BuilderVersion $builderVersion -PublicationSnapshot $snapshot `
                -BuildReceiptProof $receiptProof
        }
        catch { $wrongModIdRejected = $true }
        Assert $wrongModIdRejected 'constructor binds the manifest mod id to exact source inventory'
        $wrongAssetNameRejected = $false
        try {
            $null = New-VtReleaseRecoveryRecord `
                -Repository 'Ensrick/vermintide-2-tweaker' -ReleaseTag 'mods-test' `
                -ModFolder $mod -ModId $modId -WorkshopId $workshopId -Version $version `
                -AssetFilename 'other_valid_mod.zip' -AssetBytes $zipBytes `
                -BuilderVersion $builderVersion -PublicationSnapshot $snapshot `
                -BuildReceiptProof $receiptProof
        }
        catch { $wrongAssetNameRejected = $true }
        Assert $wrongAssetNameRejected `
            'constructor rejects a canonical ZIP leaf that is not the exact mod-id asset'

        $legacyTrackedEntry = Copy-TestObject -Value $entry
        $legacyTrackedEntry.PSObject.Properties.Remove('recovery')
        $legacyTrackedManifest = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'
            published_at = '2026-08-26T00:00:00Z'; mods = @($legacyTrackedEntry)
        }
        $legacyStagedVerdict = Test-ReleaseManifest `
            -Manifest $legacyTrackedManifest -RequiredModIds @($modId)
        Assert (
            $legacyStagedVerdict.Valid -and
            $legacyStagedVerdict.Warnings.Count -eq 1 -and
            [string]$legacyStagedVerdict.Warnings[0] -match 'explicit legacy recovery path'
        ) 'preserves a staged tracked legacy entry with one explicit recovery warning'
        $legacyCarriedVerdict = Test-ReleaseManifest -Manifest $legacyTrackedManifest
        Assert (
            $legacyCarriedVerdict.Valid -and $legacyCarriedVerdict.Warnings.Count -eq 0
        ) 'preserves an unchanged carried legacy entry without rewriting history'
        $legacyTrackedEntry.bundle_authority = 'receipt'
        $receiptWithoutRecord = Test-ReleaseManifest `
            -Manifest $legacyTrackedManifest -RequiredModIds @($modId)
        Assert (-not $receiptWithoutRecord.Valid) 'receipt authority fails closed without a durable recovery record'

        $schema2Receipt = Copy-TestObject -Value $receipt
        $schema2Receipt.schema = 2
        Write-TestUtf8 `
            -Path (Join-Path $fixture 'modx\.build-receipt.json') `
            -Text (ConvertTo-VtBuildReceiptJson -Receipt $schema2Receipt)
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('add', 'modx/.build-receipt.json')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('commit', '-m', 'legacy schema 2 receipt')
        $schema2Commit = [string](@(Invoke-TestGit -FixtureRoot $fixture -Arguments @('rev-parse', 'HEAD'))[-1]).Trim()
        $schema2Snapshot = Get-VtPublicationSnapshot `
            -RepoRoot $fixture -SourceCommit $schema2Commit -Mod $mod
        $legacySchema = Get-VtReleaseRecoveryBuildReceiptProof `
            -RepoRoot $fixture -SourceCommit $schema2Commit -Mod $mod `
            -PublicationSnapshot $schema2Snapshot -ExpectedBuilderVersion $builderVersion
        Assert (
            -not $legacySchema.Available -and
            [string]$legacySchema.Status -ceq 'legacy_build_receipt_schema'
        ) 'classifies a tracked schema-2 receipt as explicit legacy, never source-exact'

        $unsupportedReceipt = Copy-TestObject -Value $receipt
        $unsupportedReceipt.schema = 1
        Write-TestUtf8 `
            -Path (Join-Path $fixture 'modx\.build-receipt.json') `
            -Text (ConvertTo-VtBuildReceiptJson -Receipt $unsupportedReceipt)
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('add', 'modx/.build-receipt.json')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('commit', '-m', 'unsupported receipt')
        $unsupportedCommit = [string](@(Invoke-TestGit `
            -FixtureRoot $fixture -Arguments @('rev-parse', 'HEAD'))[-1]).Trim()
        $unsupportedSnapshot = Get-VtPublicationSnapshot `
            -RepoRoot $fixture -SourceCommit $unsupportedCommit -Mod $mod
        $unsupportedRejected = $false
        try {
            $null = Get-VtReleaseRecoveryBuildReceiptProof `
                -RepoRoot $fixture -SourceCommit $unsupportedCommit -Mod $mod `
                -PublicationSnapshot $unsupportedSnapshot -ExpectedBuilderVersion $builderVersion
        }
        catch { $unsupportedRejected = $true }
        Assert $unsupportedRejected 'unsupported receipt schemas fail closed instead of inheriting legacy status'

        Write-TestUtf8 -Path (Join-Path $fixture 'tools\mod-inventory.psd1') -Text @"
@{
    Mods = @(
        @{
            Dir = 'modx'; ModId = 'mx'; WorkshopId = '1234567890';
            Visibility = 'friends_only'; Stream = 'dev'; Public = `$false;
            Name = 'Recovery Fixture'; BundleAuthority = 'receipt';
            RootBundle = '0123456789abcdef.mod_bundle';
            BuildArtifactExclusions = @()
        }
    )
}
"@
        Write-TestUtf8 -Path (Join-Path $fixture '.gitignore') -Text "# fixture`n/modx/bundleV2/`n"
        Write-TestUtf8 `
            -Path (Join-Path $fixture 'modx\.build-receipt.json') `
            -Text (ConvertTo-VtBuildReceiptJson -Receipt $receipt)
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @(
            'add', '.gitignore', 'tools/mod-inventory.psd1', 'modx/.build-receipt.json')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @(
            'rm', '-f', '--', "modx/bundleV2/$rootBundle", "modx/bundleV2/$sidecarBundle",
            "modx/bundleV2/$descriptorName")
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @(
            'commit', '-m', 'receipt authority fixture')
        $receiptCommit = [string](@(Invoke-TestGit `
            -FixtureRoot $fixture -Arguments @('rev-parse', 'HEAD'))[-1]).Trim()
        [System.IO.Directory]::CreateDirectory((Join-Path $fixture 'modx\bundleV2')) | Out-Null
        foreach ($bundle in @($snapshot.BundleFiles)) {
            [System.IO.File]::WriteAllBytes(
                (Join-Path $fixture ("modx\bundleV2\" + [string]$bundle.Path)),
                [byte[]]$bundle.Bytes)
        }
        $receiptSnapshot = Get-VtPublicationSnapshot `
            -RepoRoot $fixture -SourceCommit $receiptCommit -Mod $mod `
            -ExpectedBuilderVersion $builderVersion
        $receiptAuthorityProof = Get-VtReleaseRecoveryBuildReceiptProof `
            -RepoRoot $fixture -SourceCommit $receiptCommit -Mod $mod `
            -PublicationSnapshot $receiptSnapshot -ExpectedBuilderVersion $builderVersion
        $receiptZipBytes = New-ReleaseZipBytesFromImmutableOutput `
            -OutputSet $receiptSnapshot.OutputSet `
            -BundleFiles @($receiptSnapshot.BundleFiles) `
            -Version $version
        $receiptRecord = New-VtReleaseRecoveryRecord `
            -Repository 'Ensrick/vermintide-2-tweaker' -ReleaseTag 'mods-test' `
            -ModFolder $mod -ModId $modId -WorkshopId $workshopId -Version $version `
            -AssetFilename 'mx.zip' -AssetBytes $receiptZipBytes `
            -BuilderVersion $builderVersion -PublicationSnapshot $receiptSnapshot `
            -BuildReceiptProof $receiptAuthorityProof
        $receiptEntry = Copy-TestObject -Value $entry
        $receiptEntry.source_commit = $receiptCommit
        $receiptEntry.source_state = 'clean'
        $receiptEntry.bundle_authority = 'receipt'
        $receiptEntry.sha256 = Get-TestSha256 -Bytes $receiptZipBytes
        $receiptEntry.publication_authorization.source_commit = $receiptCommit
        $receiptEntry.publication_authorization.default_branch_commit = $receiptCommit
        $receiptEntry.recovery = $receiptRecord
        $receiptManifest = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'
            published_at = '2026-08-26T00:00:00Z'; mods = @($receiptEntry)
        }
        $receiptRecordVerdict = Test-VtReleaseRecoveryRecord `
            -Record $receiptRecord -ManifestEntry $receiptEntry `
            -ManifestReleaseTag 'mods-test' -RequireManifestReleaseTag
        $receiptManifestVerdict = Test-ReleaseManifest `
            -Manifest $receiptManifest -RequiredModIds @($modId)
        Assert (
            $receiptRecordVerdict.Valid -and $receiptManifestVerdict.Valid -and
            $receiptManifestVerdict.Warnings.Count -eq 0 -and
            @($receiptRecord.output.files | Where-Object {
                -not [string]::IsNullOrEmpty([string]$_.git_blob)
            }).Count -eq 0
        ) 'receipt authority emits the same source-exact record without fabricating output Git blobs'

        if ($failures.Count -gt 0) {
            Write-Host "[check_release_recovery_record] SELF-TEST FAILED -- $($failures.Count) case(s)" -ForegroundColor Red
            return 2
        }
        Write-Host '[check_release_recovery_record] SELF-TEST OK' -ForegroundColor Green
        return 0
    }
    finally { Remove-TestDirectory -Path $fixture }
}

if ($SelfTest) { exit (Invoke-SelfTest) }
Write-Host '[check_release_recovery_record] ERROR -- pass -SelfTest.' -ForegroundColor Red
exit 2
