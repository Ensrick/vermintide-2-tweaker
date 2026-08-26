# check_publication_snapshot.ps1 - immutable authority-neutral byte fixtures (#1422).
#
# Offline only. The fixture proves tracked Git bytes remain unchanged and that
# receipt authority can return only exact schema-3-bound materialized bytes.
# ASCII-only for Windows PowerShell 5.1 parsing.

[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\ship\publication-snapshot.ps1')
. (Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1')

if (-not $SelfTest) {
    Write-Host '[check_publication_snapshot] Use -SelfTest for offline fixtures.'
    exit 0
}

$script:passed = 0

function Confirm-VtPublicationSnapshotCase {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not $Condition) { throw "Fixture assertion failed: $Label" }
    $script:passed++
    Write-Host "  [PASS] $Label" -ForegroundColor Green
}

function Confirm-VtPublicationSnapshotFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [string]$Pattern
    )

    $message = ''
    try { & $Action | Out-Null }
    catch { $message = [string]$_.Exception.Message }
    if ([string]::IsNullOrWhiteSpace($message)) {
        throw "Fixture assertion failed: $Label did not fail"
    }
    if (-not [string]::IsNullOrWhiteSpace($Pattern) -and $message -notmatch $Pattern) {
        throw "Fixture assertion failed: $Label failed unexpectedly: $message"
    }
    $script:passed++
    Write-Host "  [PASS] $Label" -ForegroundColor Green
}

function Test-VtPublicationSnapshotBytesEqual {
    param(
        [AllowEmptyCollection()][byte[]]$Left,
        [AllowEmptyCollection()][byte[]]$Right
    )

    if ($null -eq $Left -or $null -eq $Right -or $Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Write-VtPublicationSnapshotText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $Path,
        $Text,
        (New-Object System.Text.UTF8Encoding($false)))
}

function Write-VtPublicationSnapshotBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [System.IO.Directory]::CreateDirectory($parent) | Out-Null
    }
    [System.IO.File]::WriteAllBytes($Path, $Bytes)
}

function Get-VtPublicationSnapshotInventoryText {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('tracked', 'receipt')][string]$Authority,
        [Parameter(Mandatory = $true)][string]$RootBundle
    )

    return @"
@{
    Mods = @(
        @{
            Dir = 'modx'
            ModId = 'modx'
            WorkshopId = '1234567890'
            Visibility = 'private'
            Stream = 'single'
            Public = `$false
            Name = 'Mod X'
            BundleAuthority = '$Authority'
            RootBundle = '$RootBundle'
            BuildArtifactExclusions = @()
        }
    )
}
"@
}

function Invoke-VtPublicationSnapshotGit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    return @(Invoke-VtBuildGitCapture -RepoRoot $Root -Arguments $Arguments)
}

function Get-VtPublicationSnapshotHead {
    param([Parameter(Mandatory = $true)][string]$Root)

    $lines = @(Invoke-VtPublicationSnapshotGit -Root $Root -Arguments @('rev-parse', 'HEAD'))
    if ($lines.Count -eq 0 -or [string]$lines[-1] -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Fixture could not resolve a lowercase full HEAD commit.'
    }
    return ([string]$lines[-1]).Trim()
}

function Save-VtPublicationSnapshotCommit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Message
    )

    Invoke-VtPublicationSnapshotGit -Root $Root -Arguments @('commit', '--quiet', '-m', $Message) | Out-Null
    return Get-VtPublicationSnapshotHead -Root $Root
}

function Reset-VtPublicationSnapshotFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    Invoke-VtPublicationSnapshotGit -Root $Root -Arguments @('reset', '--hard', '--quiet', $Commit) | Out-Null
}

function Restore-VtPublicationSnapshotOutputs {
    param(
        [Parameter(Mandatory = $true)][string]$BundleDirectory,
        [Parameter(Mandatory = $true)]$OutputBytes
    )

    [System.IO.Directory]::CreateDirectory($BundleDirectory) | Out-Null
    foreach ($entry in @(Get-ChildItem -LiteralPath $BundleDirectory -Force -ErrorAction Stop)) {
        if (($entry.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
            Remove-Item -LiteralPath $entry.FullName -Recurse -Force
        }
        elseif (-not $OutputBytes.ContainsKey([string]$entry.Name)) {
            Remove-Item -LiteralPath $entry.FullName -Force
        }
    }
    foreach ($name in @($OutputBytes.Keys)) {
        Write-VtPublicationSnapshotBytes `
            -Path (Join-Path $BundleDirectory ([string]$name)) `
            -Bytes ([byte[]]$OutputBytes[$name])
    }
}

function Copy-VtPublicationSnapshotReceipt {
    param([Parameter(Mandatory = $true)]$Receipt)

    return ConvertFrom-VtBuildReceiptJson -Json (ConvertTo-VtBuildReceiptJson -Receipt $Receipt)
}

function New-VtPublicationSnapshotMutationCommit {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$BaseCommit,
        [Parameter(Mandatory = $true)][string]$BundleDirectory,
        [Parameter(Mandatory = $true)]$OutputBytes,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][scriptblock]$Mutation
    )

    Reset-VtPublicationSnapshotFixture -Root $Root -Commit $BaseCommit
    Restore-VtPublicationSnapshotOutputs `
        -BundleDirectory $BundleDirectory `
        -OutputBytes $OutputBytes
    & $Mutation
    Invoke-VtPublicationSnapshotGit -Root $Root -Arguments @('add', '-A', '--', '.') | Out-Null
    return Save-VtPublicationSnapshotCommit -Root $Root -Message $Message
}

function Remove-VtPublicationSnapshotFixtureTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $prefix = $temp + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($full) -cnotmatch '^vt2-publication-snapshot-[0-9a-f]{32}$') {
        throw "Fixture cleanup refused unsafe path: $full"
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $full -Recurse -Force -File)) {
        Remove-Item -LiteralPath $file.FullName -Force
    }
    $directories = @(Get-ChildItem -LiteralPath $full -Recurse -Force -Directory |
        Sort-Object { $_.FullName.Length } -Descending)
    foreach ($directory in $directories) {
        Remove-Item -LiteralPath $directory.FullName -Force
    }
    Remove-Item -LiteralPath $full -Force
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ("vt2-publication-snapshot-{0}" -f ([guid]::NewGuid().ToString('N')))
$mod = 'modx'
$rootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle'
$sideBundle = 'bbbbbbbbbbbbbbbb.mod_bundle'
$extraBundle = 'cccccccccccccccc.mod_bundle'
$otherRoot = 'dddddddddddddddd.mod_bundle'
$builderVersion = '9.8.7-fixture'
$modDirectory = Join-Path $fixtureRoot $mod
$bundleDirectory = Join-Path $modDirectory 'bundleV2'
$inventoryPath = Join-Path $fixtureRoot 'tools\mod-inventory.psd1'
$ignorePath = Join-Path $fixtureRoot '.gitignore'
$attributesPath = Join-Path $fixtureRoot '.gitattributes'
$receiptPath = Join-Path $modDirectory '.build-receipt.json'
$luaPath = Join-Path $modDirectory 'scripts\mods\modx\modx.lua'
$previewPath = Join-Path $modDirectory 'item_preview.png'
$rootPath = Join-Path $bundleDirectory $rootBundle
$sidePath = Join-Path $bundleDirectory $sideBundle
$sourceDescriptorPath = Join-Path $modDirectory 'modx.mod'
$descriptorBytes = [System.Text.Encoding]::UTF8.GetBytes("fixture descriptor`n")
$outputBytes = @{
    $rootBundle = [byte[]](1, 3, 3, 7, 9, 11, 13, 17)
    $sideBundle = [byte[]](2, 4, 6, 8, 10, 12)
    'modx.mod' = [byte[]]$descriptorBytes
}

try {
    [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    Write-VtPublicationSnapshotText -Path $attributesPath -Text "* -text`n"
    Write-VtPublicationSnapshotText -Path $ignorePath -Text "# fixture`n"
    Write-VtPublicationSnapshotText -Path $inventoryPath `
        -Text (Get-VtPublicationSnapshotInventoryText -Authority tracked -RootBundle $rootBundle)
    Write-VtPublicationSnapshotText -Path (Join-Path $modDirectory 'itemV2.cfg') -Text @"
published_id = 1234567890L;
visibility = "private";
preview = "item_preview.png";
"@
    Write-VtPublicationSnapshotText -Path $luaPath -Text "local MOD_VERSION = `"1.2.3-fixture`"`n"
    Write-VtPublicationSnapshotBytes -Path $sourceDescriptorPath -Bytes $descriptorBytes
    Write-VtPublicationSnapshotBytes -Path $previewPath `
        -Bytes ([byte[]](137, 80, 78, 71, 13, 10, 26, 10))
    Restore-VtPublicationSnapshotOutputs `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes

    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('init', '--quiet') | Out-Null
    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('config', 'user.email', 'fixture@example.invalid') | Out-Null
    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('config', 'user.name', 'Publication Snapshot Fixture') | Out-Null
    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('add', '--', '.') | Out-Null
    $trackedCommit = Save-VtPublicationSnapshotCommit -Root $fixtureRoot -Message 'tracked baseline'

    $legacyTracked = Get-PublicationCommitSnapshot `
        -RepoRoot $fixtureRoot `
        -SourceCommit $trackedCommit `
        -Mod $mod
    $trackedSnapshot = Get-VtPublicationSnapshot `
        -RepoRoot $fixtureRoot `
        -SourceCommit $trackedCommit `
        -Mod $mod
    Confirm-VtPublicationSnapshotCase `
        -Condition ($trackedSnapshot.BundleAuthority -ceq 'tracked' -and
            $trackedSnapshot.AuthorityProof.Authority -ceq 'tracked' -and
            $trackedSnapshot.AuthorityProof.ByteSource -ceq 'git_commit_blobs' -and
            $trackedSnapshot.AuthorityProof.SourceCommit -ceq $trackedCommit -and
            $trackedSnapshot.AuthorityProof.RootBundle -ceq $rootBundle) `
        -Label 'tracked snapshot carries coherent commit-qualified authority proof'
    Confirm-VtPublicationSnapshotCase `
        -Condition ($trackedSnapshot.SourceCommit -ceq $legacyTracked.SourceCommit -and
            $trackedSnapshot.ItemCfgText -ceq $legacyTracked.ItemCfgText -and
            $trackedSnapshot.Version -ceq $legacyTracked.Version -and
            $trackedSnapshot.PublishedId -ceq $legacyTracked.PublishedId -and
            $trackedSnapshot.Visibility -ceq $legacyTracked.Visibility -and
            @($trackedSnapshot.BundleFiles).Count -eq @($legacyTracked.BundleFiles).Count) `
        -Label 'tracked snapshot preserves the legacy publication scalar contract'

    $trackedRowsEqual = $true
    for ($index = 0; $index -lt @($legacyTracked.BundleFiles).Count; $index++) {
        $legacyRow = @($legacyTracked.BundleFiles)[$index]
        $newRow = @($trackedSnapshot.BundleFiles)[$index]
        if ([string]$newRow.Path -cne [string]$legacyRow.Path -or
            [string]$newRow.GitBlob -cne [string]$legacyRow.GitBlob -or
            [long]$newRow.Length -ne [long]$legacyRow.Length -or
            [string]$newRow.Sha256 -cne [string]$legacyRow.Sha256 -or
            -not (Test-VtPublicationSnapshotBytesEqual `
                -Left ([byte[]]$newRow.Bytes) `
                -Right ([byte[]]$legacyRow.Bytes))) {
            $trackedRowsEqual = $false
            break
        }
    }
    Confirm-VtPublicationSnapshotCase `
        -Condition $trackedRowsEqual `
        -Label 'tracked snapshot preserves every legacy path, Git blob, hash, length, and byte'

    $legacyRecords = @($legacyTracked.BundleFiles | ForEach-Object {
        [pscustomobject][ordered]@{
            Name = [string]$_.Path
            Length = [long]$_.Length
            Sha256 = [string]$_.Sha256
        }
    })
    $legacyOutputSet = New-VtBundleOutputSet `
        -Records $legacyRecords `
        -ExpectedDescriptorName 'modx.mod' `
        -ExpectedRootBundle $rootBundle `
        -ExpectedDescriptorSha256 ([string]$legacyTracked.SourceDescriptor.Sha256)
    $legacyZip = [byte[]](New-ReleaseZipBytesFromImmutableOutput `
        -OutputSet $legacyOutputSet `
        -BundleFiles @($legacyTracked.BundleFiles) `
        -Version ([string]$legacyTracked.Version))
    $snapshotZip = [byte[]](New-ReleaseZipBytesFromImmutableOutput `
        -OutputSet $trackedSnapshot.OutputSet `
        -BundleFiles @($trackedSnapshot.BundleFiles) `
        -Version ([string]$trackedSnapshot.Version))
    Confirm-VtPublicationSnapshotCase `
        -Condition (Test-VtPublicationSnapshotBytesEqual -Left $legacyZip -Right $snapshotZip) `
        -Label 'tracked authority-neutral routing preserves deterministic release ZIP bytes'

    Write-VtPublicationSnapshotText -Path $inventoryPath `
        -Text (Get-VtPublicationSnapshotInventoryText -Authority receipt -RootBundle $otherRoot)
    Write-VtPublicationSnapshotText -Path $ignorePath -Text "# dirty`n/modx/bundleV2/`n"
    Write-VtPublicationSnapshotBytes -Path $rootPath -Bytes ([byte[]](17, 13, 11, 9, 7, 3, 3, 1))
    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('add', '-f', '--', 'tools/mod-inventory.psd1', '.gitignore', "modx/bundleV2/$rootBundle") | Out-Null
    $differentHead = Save-VtPublicationSnapshotCommit -Root $fixtureRoot -Message 'unrelated mutable HEAD'
    Write-VtPublicationSnapshotText -Path $inventoryPath `
        -Text (Get-VtPublicationSnapshotInventoryText -Authority receipt -RootBundle $rootBundle)
    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('add', '--', 'tools/mod-inventory.psd1') | Out-Null
    Write-VtPublicationSnapshotBytes -Path $previewPath -Bytes ([byte[]](1, 2, 3, 4, 5, 6, 7, 8))
    $dirtyIsolation = Get-VtPublicationSnapshot `
        -RepoRoot $fixtureRoot `
        -SourceCommit $trackedCommit `
        -Mod $mod
    $dirtyRoot = @($dirtyIsolation.BundleFiles | Where-Object { [string]$_.Path -ceq $rootBundle })[0]
    $goldenRoot = @($trackedSnapshot.BundleFiles | Where-Object { [string]$_.Path -ceq $rootBundle })[0]
    Confirm-VtPublicationSnapshotCase `
        -Condition ($differentHead -cne $trackedCommit -and
            (Get-VtPublicationSnapshotHead -Root $fixtureRoot) -ceq $differentHead -and
            [string]$dirtyIsolation.BundleAuthority -ceq 'tracked' -and
            [string]$dirtyRoot.GitBlob -ceq [string]$goldenRoot.GitBlob -and
            (Test-VtPublicationSnapshotBytesEqual `
                -Left ([byte[]]$dirtyRoot.Bytes) `
                -Right ([byte[]]$goldenRoot.Bytes)) -and
            [string]$dirtyIsolation.PreviewFile.GitBlob -ceq [string]$trackedSnapshot.PreviewFile.GitBlob -and
            (Test-VtPublicationSnapshotBytesEqual `
                -Left ([byte[]]$dirtyIsolation.PreviewFile.Bytes) `
                -Right ([byte[]]$trackedSnapshot.PreviewFile.Bytes))) `
        -Label 'tracked snapshot ignores different HEAD plus dirty index and working-tree drift'
    Reset-VtPublicationSnapshotFixture -Root $fixtureRoot -Commit $trackedCommit

    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('rm', '-r', '--quiet', '--', 'modx/bundleV2') | Out-Null
    $trackedEmptyCommit = Save-VtPublicationSnapshotCommit -Root $fixtureRoot -Message 'tracked empty adversary'
    Confirm-VtPublicationSnapshotFailure `
        -Label 'tracked authority rejects a commit with no bundle outputs' `
        -Pattern 'Tracked publication snapshot contains no source-commit bundleV2 blobs' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $trackedEmptyCommit `
                -Mod $mod
        }
    Reset-VtPublicationSnapshotFixture -Root $fixtureRoot -Commit $trackedCommit
    Restore-VtPublicationSnapshotOutputs `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes

    $trackedEntry = @{
        Dir = $mod
        BundleAuthority = 'tracked'
        RootBundle = $rootBundle
        BuildArtifactExclusions = @()
    }
    $sourceMap = Get-VtBuildCommitSourceMap `
        -RepoRoot $fixtureRoot `
        -Mod $mod `
        -Commit $trackedCommit
    $workingOutputSet = Get-VtBundleOutputSet `
        -BundleDirectory $bundleDirectory `
        -ExpectedDescriptorName 'modx.mod' `
        -ExpectedRootBundle $rootBundle `
        -ExpectedDescriptorSha256 (Get-PublicationByteSha256 -Bytes $descriptorBytes)
    $normalizationPolicy = New-BuildOutputNormalizationPolicyProof -ModEntry $trackedEntry
    $receipt = New-VtBuildReceipt `
        -Mod $mod `
        -SourceMap $sourceMap `
        -OutputSet $workingOutputSet `
        -BuilderVersion $builderVersion `
        -NormalizationPolicy $normalizationPolicy
    Write-VtPublicationSnapshotText -Path $receiptPath `
        -Text (ConvertTo-VtBuildReceiptJson -Receipt $receipt)
    Write-VtPublicationSnapshotText -Path $inventoryPath `
        -Text (Get-VtPublicationSnapshotInventoryText -Authority receipt -RootBundle $rootBundle)
    Write-VtPublicationSnapshotText -Path $ignorePath -Text "# fixture`n/modx/bundleV2/`n"
    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('rm', '-r', '--cached', '--quiet', '--', 'modx/bundleV2') | Out-Null
    Invoke-VtPublicationSnapshotGit -Root $fixtureRoot -Arguments @('add', '--', '.gitignore', 'tools/mod-inventory.psd1', 'modx/.build-receipt.json') | Out-Null
    $receiptCommit = Save-VtPublicationSnapshotCommit -Root $fixtureRoot -Message 'receipt authority baseline'

    $trackedNames = @(Invoke-VtPublicationSnapshotGit -Root $fixtureRoot `
        -Arguments @('ls-tree', '-r', '--name-only', $receiptCommit, '--', 'modx/bundleV2') |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    Confirm-VtPublicationSnapshotCase `
        -Condition ($trackedNames.Count -eq 0) `
        -Label 'receipt fixture commit contains zero tracked bundle outputs'

    $receiptSnapshot = Get-VtPublicationSnapshot `
        -RepoRoot $fixtureRoot `
        -SourceCommit $receiptCommit `
        -Mod $mod `
        -ExpectedBuilderVersion $builderVersion
    $receiptProofNames = @($receiptSnapshot.AuthorityProof.PSObject.Properties | ForEach-Object { [string]$_.Name })
    $expectedProofNames = @(
        'Authority', 'SourceCommit', 'InventoryGitBlob', 'IgnoreGitBlob', 'RootBundle',
        'ByteSource', 'BuildReceiptGitBlob', 'BuildReceiptSha256', 'ReceiptSchema',
        'SourceFingerprintSha256', 'OutputAlgorithm', 'OutputFingerprintSha256',
        'BuilderName', 'BuilderVersion', 'NormalizationPolicyAlgorithm',
        'NormalizationPolicyFingerprintSha256')
    Confirm-VtPublicationSnapshotCase `
        -Condition ($receiptSnapshot.BundleAuthority -ceq 'receipt' -and
            $receiptSnapshot.AuthorityProof.Authority -ceq 'receipt' -and
            $receiptSnapshot.AuthorityProof.ByteSource -ceq 'materialized_restrictive_handles' -and
            $receiptSnapshot.AuthorityProof.SourceCommit -ceq $receiptCommit -and
            $receiptSnapshot.AuthorityProof.RootBundle -ceq $rootBundle -and
            [int]$receiptSnapshot.AuthorityProof.ReceiptSchema -eq 3 -and
            $receiptSnapshot.AuthorityProof.BuilderName -ceq 'VMBLauncher' -and
            $receiptSnapshot.AuthorityProof.BuilderVersion -ceq $builderVersion -and
            ($receiptProofNames -join [char]0) -ceq ($expectedProofNames -join [char]0)) `
        -Label 'receipt snapshot returns the exact authority-proof schema and identities'
    Confirm-VtPublicationSnapshotCase `
        -Condition ([string]$receiptSnapshot.OutputSet.Fingerprint -ceq [string]$workingOutputSet.Fingerprint -and
            [string]$receiptSnapshot.AuthorityProof.OutputFingerprintSha256 -ceq [string]$workingOutputSet.Fingerprint -and
            @($receiptSnapshot.BundleFiles).Count -eq @($workingOutputSet.Files).Count -and
            @($receiptSnapshot.BundleFiles | Where-Object { [string]$_.GitBlob -cne '' }).Count -eq 0) `
        -Label 'receipt snapshot binds the complete canonical output map without Git blob claims'

    $receiptBytesExact = $true
    foreach ($file in @($receiptSnapshot.BundleFiles)) {
        $name = [string]$file.Path
        if (-not $outputBytes.ContainsKey($name) -or
            [long]$file.Length -ne [long]([byte[]]$outputBytes[$name]).LongLength -or
            [string]$file.Sha256 -cne (Get-PublicationByteSha256 -Bytes ([byte[]]$outputBytes[$name])) -or
            -not (Test-VtPublicationSnapshotBytesEqual `
                -Left ([byte[]]$file.Bytes) `
                -Right ([byte[]]$outputBytes[$name]))) {
            $receiptBytesExact = $false
            break
        }
    }
    Confirm-VtPublicationSnapshotCase `
        -Condition $receiptBytesExact `
        -Label 'receipt snapshot returns exact held-handle bytes, lengths, and hashes'

    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt authority requires an exact expected builder version' `
        -Pattern 'requires the exact expected builder version' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $receiptCommit `
                -Mod $mod
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'Workshop publication receipt remains tracked-authority-only' `
        -Pattern 'requires exactly one tracked source-commit inventory entry' `
        -Action {
            New-WorkshopPublicationReceipt `
                -RepoRoot $fixtureRoot `
                -Repository 'Ensrick/vermintide-2-tweaker' `
                -ReleaseTag 'mods-fixture' `
                -ReceiptAssetName 'publication-receipt-modx.json' `
                -Mod $mod `
                -Version '1.2.3-fixture' `
                -Owner 'fixture:owner' `
                -SourceCommit $receiptCommit `
                -AuthorizationEvidence ([pscustomobject]@{ mode = 'hosted_qa' })
        }

    $detachedRoot = @($receiptSnapshot.BundleFiles | Where-Object { [string]$_.Path -ceq $rootBundle })[0]
    $detachedBytes = [byte[]]$detachedRoot.Bytes.Clone()
    $wrongRootBytes = [byte[]]$outputBytes[$rootBundle].Clone()
    $wrongRootBytes[0] = [byte]($wrongRootBytes[0] -bxor 0xff)
    Write-VtPublicationSnapshotBytes -Path $rootPath -Bytes $wrongRootBytes
    Confirm-VtPublicationSnapshotCase `
        -Condition (Test-VtPublicationSnapshotBytesEqual `
            -Left ([byte[]]$detachedRoot.Bytes) `
            -Right $detachedBytes) `
        -Label 'returned receipt bytes remain detached after materialized disk mutation'
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects same-size wrong materialized bytes' `
        -Pattern 'captured-byte validation|differs from receipt|changed' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $receiptCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }
    Restore-VtPublicationSnapshotOutputs `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes

    Remove-Item -LiteralPath $sidePath -Force
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects a missing materialized output' `
        -Pattern 'captured-byte validation|removed|missing|differs' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $receiptCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }
    Restore-VtPublicationSnapshotOutputs `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes

    Write-VtPublicationSnapshotBytes `
        -Path (Join-Path $bundleDirectory $extraBundle) `
        -Bytes ([byte[]](21, 22, 23, 24))
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects an extra materialized output' `
        -Pattern 'captured-byte validation|added|extra|differs' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $receiptCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }
    Restore-VtPublicationSnapshotOutputs `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes

    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects builder-version drift' `
        -Pattern 'builder version' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $receiptCommit `
                -Mod $mod `
                -ExpectedBuilderVersion '9.8.8-drift'
        }

    $rootDriftCommit = New-VtPublicationSnapshotMutationCommit `
        -Root $fixtureRoot `
        -BaseCommit $receiptCommit `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes `
        -Message 'root drift adversary' `
        -Mutation {
            Write-VtPublicationSnapshotText -Path $inventoryPath `
                -Text (Get-VtPublicationSnapshotInventoryText -Authority receipt -RootBundle $otherRoot)
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects inventory-root drift' `
        -Pattern 'Receipt root.*is not source-commit inventory root' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $rootDriftCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }

    $sourceDriftCommit = New-VtPublicationSnapshotMutationCommit `
        -Root $fixtureRoot `
        -BaseCommit $receiptCommit `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes `
        -Message 'source drift adversary' `
        -Mutation {
            Write-VtPublicationSnapshotText -Path $luaPath `
                -Text "local MOD_VERSION = `"1.2.4-source-drift`"`n"
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects committed source drift' `
        -Pattern 'source bytes changed after receipt|source fingerprint|source added|source removed' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $sourceDriftCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }

    $outputDriftCommit = New-VtPublicationSnapshotMutationCommit `
        -Root $fixtureRoot `
        -BaseCommit $receiptCommit `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes `
        -Message 'receipt output drift adversary' `
        -Mutation {
            $changed = Copy-VtPublicationSnapshotReceipt -Receipt $receipt
            $changed.output_files[0].sha256 = ('f' * 64)
            Write-VtPublicationSnapshotText -Path $receiptPath `
                -Text (ConvertTo-VtBuildReceiptJson -Receipt $changed)
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects receipt output-map drift' `
        -Pattern 'declared-output validation|output fingerprint|root SHA-256|descriptor' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $outputDriftCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }

    $schemaTwoCommit = New-VtPublicationSnapshotMutationCommit `
        -Root $fixtureRoot `
        -BaseCommit $receiptCommit `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes `
        -Message 'schema two adversary' `
        -Mutation {
            $schemaTwo = Copy-VtPublicationSnapshotReceipt -Receipt $receipt
            $schemaTwo.schema = 2
            Write-VtPublicationSnapshotText -Path $receiptPath `
                -Text (ConvertTo-VtBuildReceiptJson -Receipt $schemaTwo)
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects schema 2 authority' `
        -Pattern 'below required minimum schema 3|schema 2 validation' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $schemaTwoCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }

    $malformedCommit = New-VtPublicationSnapshotMutationCommit `
        -Root $fixtureRoot `
        -BaseCommit $receiptCommit `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes `
        -Message 'malformed receipt adversary' `
        -Mutation {
            Write-VtPublicationSnapshotText -Path $receiptPath -Text "{ definitely-not-json`n"
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects malformed receipt JSON' `
        -Pattern 'Build receipt is not valid JSON' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $malformedCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }

    $missingIgnoreCommit = New-VtPublicationSnapshotMutationCommit `
        -Root $fixtureRoot `
        -BaseCommit $receiptCommit `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes `
        -Message 'missing ignore adversary' `
        -Mutation {
            Write-VtPublicationSnapshotText -Path $ignorePath -Text "# fixture`n"
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt snapshot rejects a missing exact scoped ignore rule' `
        -Pattern 'requires exactly one scoped ignore rule' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $missingIgnoreCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }

    $trackedLeftoverCommit = New-VtPublicationSnapshotMutationCommit `
        -Root $fixtureRoot `
        -BaseCommit $receiptCommit `
        -BundleDirectory $bundleDirectory `
        -OutputBytes $outputBytes `
        -Message 'tracked leftover adversary' `
        -Mutation {
            Invoke-VtPublicationSnapshotGit -Root $fixtureRoot `
                -Arguments @('add', '-f', '--', "modx/bundleV2/$rootBundle") | Out-Null
        }
    Confirm-VtPublicationSnapshotFailure `
        -Label 'receipt authority rejects a tracked bundle leftover' `
        -Pattern 'forbids source-commit bundleV2 blobs' `
        -Action {
            Get-VtPublicationSnapshot `
                -RepoRoot $fixtureRoot `
                -SourceCommit $trackedLeftoverCommit `
                -Mod $mod `
                -ExpectedBuilderVersion $builderVersion
        }

    Write-Host "[check_publication_snapshot] OK -- $script:passed offline fixtures passed." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[check_publication_snapshot] FAILED -- $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
finally {
    Remove-VtPublicationSnapshotFixtureTree -Path $fixtureRoot
}
