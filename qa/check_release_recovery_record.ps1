# check_release_recovery_record.ps1 - durable source-exact release recovery proof (#1430).
#
# This is a producer-only contract. It does not select, download, install, or
# restore a release asset. -SelfTest is offline and performs no real mutation.
# ASCII only for Windows PowerShell 5.1 compatibility.

[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$UpdateFixtures,
    [switch]$SelfTestPresentEmptyEnvironment
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1')
$producerFixtureRoot = Join-Path $repoRoot 'qa\fixtures\recovery_manifests'
$gitLocalEnvironmentNames = @(
    'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_COMMON_DIR', 'GIT_CONFIG',
    'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS', 'GIT_DIR', 'GIT_GRAFT_FILE',
    'GIT_IMPLICIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_NAMESPACE',
    'GIT_NO_REPLACE_OBJECTS', 'GIT_OBJECT_DIRECTORY', 'GIT_PREFIX',
    'GIT_QUARANTINE_PATH', 'GIT_REPLACE_REF_BASE', 'GIT_SHALLOW_FILE',
    'GIT_WORK_TREE')

# Windows PowerShell 5.1's Env: provider and .NET Framework environment setter
# both collapse a present-empty process variable into an absent variable. Use
# the native API so fixture isolation can preserve all three caller states:
# absent, present-empty, and present-nonempty.
if (-not ('Vt2ReleaseRecoveryProcessEnvironment' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class Vt2ReleaseRecoveryProcessEnvironment
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetEnvironmentVariableW(string name, string value);

    public static void SetValue(string name, string value)
    {
        if (!SetEnvironmentVariableW(name, value ?? String.Empty))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }

    public static void Remove(string name)
    {
        if (!SetEnvironmentVariableW(name, null))
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
}

function Get-ProcessEnvironmentState {
    param([Parameter(Mandatory = $true)][string]$Name)
    $environment = [Environment]::GetEnvironmentVariables('Process')
    $exists = [bool]$environment.Contains($Name)
    return [pscustomobject]@{
        Exists = $exists
        Value = if ($exists) { [string]$environment[$Name] } else { $null }
    }
}

function Set-ProcessEnvironmentValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value
    )
    [Vt2ReleaseRecoveryProcessEnvironment]::SetValue($Name, $Value)
}

function Remove-ProcessEnvironmentValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    [Vt2ReleaseRecoveryProcessEnvironment]::Remove($Name)
}

function Restore-ProcessEnvironmentState {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$State
    )
    if ([bool]$State.Exists) {
        Set-ProcessEnvironmentValue -Name $Name -Value ([string]$State.Value)
    } else {
        Remove-ProcessEnvironmentValue -Name $Name
    }
}

function Restore-ProcessEnvironmentStates {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names,
        [Parameter(Mandatory = $true)]$States
    )
    $restoreErrors = New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $Names) {
        try {
            Restore-ProcessEnvironmentState -Name $name -State $States[$name]
        }
        catch {
            $restoreErrors.Add("$name`: $($_.Exception.Message)")
        }
    }
    if ($restoreErrors.Count -gt 0) {
        throw "process environment restoration failed: $($restoreErrors -join ' | ')"
    }
}

function Test-ProcessEnvironmentStateEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Expected
    )
    $actual = Get-ProcessEnvironmentState -Name $Name
    if ([bool]$actual.Exists -ne [bool]$Expected.Exists) { return $false }
    if ($actual.Exists -and [string]$actual.Value -cne [string]$Expected.Value) {
        return $false
    }
    return $true
}

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
    $savedEnvironment = @{}
    foreach ($name in $gitLocalEnvironmentNames) {
        $savedEnvironment[$name] = Get-ProcessEnvironmentState -Name $name
    }
    $previousPreference = $ErrorActionPreference
    try {
        foreach ($name in $gitLocalEnvironmentNames) {
            Remove-ProcessEnvironmentValue -Name $name
        }
        $ErrorActionPreference = 'Continue'
        $lines = @(& git -C $FixtureRoot @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
        Restore-ProcessEnvironmentStates `
            -Names $gitLocalEnvironmentNames -States $savedEnvironment
    }
    if ($exitCode -ne 0) {
        throw "fixture git $($Arguments -join ' ') failed ($exitCode): $($lines -join ' | ')"
    }
    return ,([string[]]$lines)
}

function Test-ByteArrayEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $false }
    }
    return $true
}

function Get-FirstByteDifferenceIndex {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )
    $limit = [Math]::Min($Left.Length, $Right.Length)
    for ($index = 0; $index -lt $limit; $index++) {
        if ($Left[$index] -ne $Right[$index]) { return $index }
    }
    if ($Left.Length -ne $Right.Length) { return $limit }
    return -1
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
    param([switch]$WriteFixtures)

    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) `
        ('vt2-release-recovery-' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($fixture) | Out-Null
    $failures = [System.Collections.Generic.List[string]]::new()
    $fixedCommitDate = '2026-08-26T00:00:00Z'
    $fixedGitEnvironmentValues = [ordered]@{
        GIT_AUTHOR_DATE = $fixedCommitDate
        GIT_COMMITTER_DATE = $fixedCommitDate
        GIT_AUTHOR_NAME = 'Recovery Test'
        GIT_AUTHOR_EMAIL = 'recovery@example.invalid'
        GIT_COMMITTER_NAME = 'Recovery Test'
        GIT_COMMITTER_EMAIL = 'recovery@example.invalid'
    }
    $hostileIdentityValues = [ordered]@{
        GIT_AUTHOR_NAME = 'Polluted Fixture Author'
        GIT_AUTHOR_EMAIL = 'polluted-author@example.invalid'
        GIT_COMMITTER_NAME = 'Polluted Fixture Committer'
        GIT_COMMITTER_EMAIL = 'polluted-committer@example.invalid'
    }
    $controlledGitEnvironmentNames = @($fixedGitEnvironmentValues.Keys) + @('GIT_DEFAULT_HASH')
    $savedCallerGitEnvironment = @{}
    foreach ($name in $controlledGitEnvironmentNames) {
        $savedCallerGitEnvironment[$name] = Get-ProcessEnvironmentState -Name $name
    }
    $savedGitDeterminismEnvironment = @{}
    $determinismSnapshotReady = $false
    $pollutedEnvironmentRestoredExactly = $false

    function Assert([bool]$Condition, [string]$Description) {
        if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
        else {
            Write-Host "  [FAIL] $Description" -ForegroundColor Red
            $failures.Add($Description)
        }
    }

    try {
        # Plant process-level values that would override repository config and
        # Git's default object format. Setup is inside the restoration
        # transaction so a native setter failure cannot strand a partial state.
        foreach ($name in $hostileIdentityValues.Keys) {
            Set-ProcessEnvironmentValue `
                -Name $name -Value ([string]$hostileIdentityValues[$name])
        }
        Set-ProcessEnvironmentValue -Name 'GIT_DEFAULT_HASH' -Value 'sha256'
        $pollutedEnvironment = [Environment]::GetEnvironmentVariables('Process')
        $pollutedIdentityApplied = $true
        foreach ($name in $hostileIdentityValues.Keys) {
            if (-not $pollutedEnvironment.Contains($name) -or
                [string]$pollutedEnvironment[$name] -cne [string]$hostileIdentityValues[$name]) {
                $pollutedIdentityApplied = $false
            }
        }
        $hostileDefaultHashApplied = (
            $pollutedEnvironment.Contains('GIT_DEFAULT_HASH') -and
            [string]$pollutedEnvironment['GIT_DEFAULT_HASH'] -ceq 'sha256')
        foreach ($name in $controlledGitEnvironmentNames) {
            $savedGitDeterminismEnvironment[$name] = `
                Get-ProcessEnvironmentState -Name $name
        }
        $determinismSnapshotReady = $true

        foreach ($name in $fixedGitEnvironmentValues.Keys) {
            Set-ProcessEnvironmentValue `
                -Name $name -Value ([string]$fixedGitEnvironmentValues[$name])
        }

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

        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @(
            '-c', 'init.templateDir=', 'init', '--quiet', '--object-format=sha1')
        $fixtureObjectFormat = [string](@(Invoke-TestGit `
            -FixtureRoot $fixture `
            -Arguments @('rev-parse', '--show-object-format'))[-1]).Trim()
        Assert (
            $hostileDefaultHashApplied -and $fixtureObjectFormat -ceq 'sha1'
        ) 'fixture pins SHA-1 despite hostile GIT_DEFAULT_HASH=sha256'
        $gitEnvironmentTestNames = @(
            'GIT_CONFIG_COUNT', 'GIT_NAMESPACE', 'GIT_GRAFT_FILE')
        $savedGitEnvironmentTestState = @{}
        foreach ($name in $gitEnvironmentTestNames) {
            $savedGitEnvironmentTestState[$name] = `
                Get-ProcessEnvironmentState -Name $name
        }
        try {
            foreach ($name in $gitEnvironmentTestNames) {
                Remove-ProcessEnvironmentValue -Name $name
            }
            Set-ProcessEnvironmentValue `
                -Name 'GIT_CONFIG_COUNT' -Value 'not-an-integer'
            Set-ProcessEnvironmentValue -Name 'GIT_NAMESPACE' -Value ''
            $insideWorkTree = [string](@(Invoke-TestGit `
                -FixtureRoot $fixture `
                -Arguments @('rev-parse', '--is-inside-work-tree'))[-1]).Trim()
            $postGitEnvironment = [Environment]::GetEnvironmentVariables('Process')
            Assert (
                $insideWorkTree -ceq 'true' -and
                $postGitEnvironment.Contains('GIT_CONFIG_COUNT') -and
                [string]$postGitEnvironment['GIT_CONFIG_COUNT'] -ceq 'not-an-integer' -and
                $postGitEnvironment.Contains('GIT_NAMESPACE') -and
                [string]$postGitEnvironment['GIT_NAMESPACE'] -ceq '' -and
                -not $postGitEnvironment.Contains('GIT_GRAFT_FILE')
            ) 'fixture Git restores exact nonempty, present-empty, and absent states'
        }
        finally {
            Restore-ProcessEnvironmentStates `
                -Names $gitEnvironmentTestNames `
                -States $savedGitEnvironmentTestState
        }
        $emptyHooksPath = Join-Path $fixture '.git\vt2-empty-hooks'
        [System.IO.Directory]::CreateDirectory($emptyHooksPath) | Out-Null
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @(
            'config', 'core.hooksPath', $emptyHooksPath)
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('config', 'user.name', 'Recovery Test')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('config', 'user.email', 'recovery@example.invalid')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('config', 'commit.gpgsign', 'false')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('config', 'core.autocrlf', 'false')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('add', '--all')
        $null = Invoke-TestGit -FixtureRoot $fixture -Arguments @('commit', '-m', 'fixture source')
        $commitWithoutReceipt = [string](@(Invoke-TestGit -FixtureRoot $fixture -Arguments @('rev-parse', 'HEAD'))[-1]).Trim()
        $commitIdentity = [string](@(Invoke-TestGit `
            -FixtureRoot $fixture `
            -Arguments @('show', '-s', '--format=%an|%ae|%cn|%ce', 'HEAD'))[-1]).Trim()
        Assert (
            $pollutedIdentityApplied -and
            $commitIdentity -ceq 'Recovery Test|recovery@example.invalid|Recovery Test|recovery@example.invalid'
        ) 'polluted process identity cannot alter deterministic fixture commit metadata'

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
                qa_check = 'qa-gate'
                qa_check_url = 'https://github.com/Ensrick/vermintide-2-tweaker/actions/runs/1430'
                qa_completed_at_utc = '2026-08-26T00:00:00Z'
            }
        }
        $manifest = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'
            published_at = '2026-08-26T00:00:00.0000000Z'; mods = @($entry)
        }
        $trackedManifestBytes = ConvertTo-VtReleaseManifestBytes -Manifest $manifest

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
            published_at = '2026-08-26T00:00:00.0000000Z'; mods = @($legacyTrackedEntry)
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
            published_at = '2026-08-26T00:00:00.0000000Z'; mods = @($receiptEntry)
        }
        $receiptManifestBytes = ConvertTo-VtReleaseManifestBytes -Manifest $receiptManifest
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

        $fixtureSpecifications = @(
            [pscustomobject]@{
                Name = 'producer-tracked-manifest.json'
                Bytes = [byte[]]$trackedManifestBytes
                ExpectedSha256 = 'c367667af8ddf00c08d8b78f2fb5f8b791dc6b7897109f06316835d41a527dc6'
            },
            [pscustomobject]@{
                Name = 'producer-tracked.zip'
                Bytes = [byte[]]$zipBytes
                ExpectedSha256 = '7d1f642208d5851b8cfa748e4207093c24de70a2a6377b2473b1b1996d86b4e0'
            },
            [pscustomobject]@{
                Name = 'producer-receipt-manifest.json'
                Bytes = [byte[]]$receiptManifestBytes
                ExpectedSha256 = '812f656096f178fecfcb59e2a74b37811b046ab187516b0df8b65cc1e43981ec'
            },
            [pscustomobject]@{
                Name = 'producer-receipt.zip'
                Bytes = [byte[]]$receiptZipBytes
                ExpectedSha256 = '7d1f642208d5851b8cfa748e4207093c24de70a2a6377b2473b1b1996d86b4e0'
            }
        )
        if ($WriteFixtures) {
            if ($failures.Count -gt 0) {
                Assert $false 'refuses to update producer fixtures after an earlier contract failure'
            } else {
                if (-not (Test-Path -LiteralPath $producerFixtureRoot -PathType Container)) {
                    [System.IO.Directory]::CreateDirectory($producerFixtureRoot) | Out-Null
                }
                foreach ($specification in $fixtureSpecifications) {
                    $fixturePath = Join-Path $producerFixtureRoot $specification.Name
                    [System.IO.File]::WriteAllBytes(
                        $fixturePath,
                        [byte[]]$specification.Bytes)
                    Write-Host (
                        '[check_release_recovery_record] updated {0} bytes={1} sha256={2}' -f
                        $specification.Name,
                        ([byte[]]$specification.Bytes).LongLength,
                        (Get-TestSha256 -Bytes ([byte[]]$specification.Bytes)))
                }
            }
        }
        foreach ($specification in $fixtureSpecifications) {
            $fixturePath = Join-Path $producerFixtureRoot $specification.Name
            $fixtureExists = Test-Path -LiteralPath $fixturePath -PathType Leaf
            Assert $fixtureExists "checked-in producer fixture exists: $($specification.Name)"
            if (-not $fixtureExists) { continue }

            $generatedBytes = [byte[]]$specification.Bytes
            $checkedInBytes = [System.IO.File]::ReadAllBytes($fixturePath)
            $bytesMatch = Test-ByteArrayEqual -Left $generatedBytes -Right $checkedInBytes
            Assert $bytesMatch `
                "producer fixture is byte-exact: $($specification.Name)"
            if (-not $bytesMatch) {
                $differenceIndex = Get-FirstByteDifferenceIndex `
                    -Left $generatedBytes -Right $checkedInBytes
                Write-Host (
                    '[check_release_recovery_record] mismatch {0} generated_bytes={1} generated_sha256={2} checked_bytes={3} first_difference={4}' -f
                    $specification.Name,
                    $generatedBytes.LongLength,
                    (Get-TestSha256 -Bytes $generatedBytes),
                    $checkedInBytes.LongLength,
                    $differenceIndex) -ForegroundColor Red
            }
            $checkedInSha256 = Get-TestSha256 -Bytes $checkedInBytes
            Assert ($checkedInSha256 -ceq [string]$specification.ExpectedSha256) `
                "producer fixture hash is frozen: $($specification.Name)"
            Write-Host (
                '[check_release_recovery_record] fixture {0} bytes={1} sha256={2}' -f
                $specification.Name,
                $checkedInBytes.LongLength,
                $checkedInSha256)
        }

    }
    finally {
        $determinismRestoreException = $null
        if ($determinismSnapshotReady) {
            try {
                Restore-ProcessEnvironmentStates `
                    -Names $controlledGitEnvironmentNames `
                    -States $savedGitDeterminismEnvironment
                $restoredPollutedEnvironment = `
                    [Environment]::GetEnvironmentVariables('Process')
                $pollutedEnvironmentRestoredExactly = $true
                foreach ($name in $controlledGitEnvironmentNames) {
                    $existsAfter = $restoredPollutedEnvironment.Contains($name)
                    if ($existsAfter -ne [bool]$savedGitDeterminismEnvironment[$name].Exists) {
                        $pollutedEnvironmentRestoredExactly = $false
                    } elseif ($existsAfter -and
                        [string]$restoredPollutedEnvironment[$name] -cne
                            [string]$savedGitDeterminismEnvironment[$name].Value) {
                        $pollutedEnvironmentRestoredExactly = $false
                    }
                }
            }
            catch { $determinismRestoreException = $_.Exception }
        }
        try {
            Restore-ProcessEnvironmentStates `
                -Names $controlledGitEnvironmentNames `
                -States $savedCallerGitEnvironment
        }
        finally {
            Remove-TestDirectory -Path $fixture
        }
        if ($null -ne $determinismRestoreException) {
            throw $determinismRestoreException
        }
    }

    Assert $pollutedEnvironmentRestoredExactly `
        'fixture restores exact polluted identity, date, and default-hash input state'
    $restoredEnvironment = [Environment]::GetEnvironmentVariables('Process')
    $environmentRestoredExactly = $true
    foreach ($name in $controlledGitEnvironmentNames) {
        $existsAfter = $restoredEnvironment.Contains($name)
        if ($existsAfter -ne [bool]$savedCallerGitEnvironment[$name].Exists) {
            $environmentRestoredExactly = $false
        } elseif ($existsAfter -and
            [string]$restoredEnvironment[$name] -cne
                [string]$savedCallerGitEnvironment[$name].Value) {
            $environmentRestoredExactly = $false
        }
    }
    Assert $environmentRestoredExactly `
        'self-test restores exact caller identity, date, and default-hash environment state'

    if ($failures.Count -gt 0) {
        Write-Host "[check_release_recovery_record] SELF-TEST FAILED -- $($failures.Count) case(s)" -ForegroundColor Red
        return 2
    }
    Write-Host '[check_release_recovery_record] SELF-TEST OK' -ForegroundColor Green
    return 0
}

function Invoke-PresentEmptyEnvironmentSelfTest {
    param([switch]$WriteFixtures)

    $name = 'GIT_AUTHOR_EMAIL'
    $savedState = Get-ProcessEnvironmentState -Name $name
    $planted = $false
    $survived = $false
    $innerResult = 2
    try {
        Set-ProcessEnvironmentValue -Name $name -Value ''
        $plantedState = Get-ProcessEnvironmentState -Name $name
        $planted = $plantedState.Exists -and [string]$plantedState.Value -ceq ''
        if ($planted) {
            Write-Host '  [PASS] adversarial caller variable is present-empty before self-test' -ForegroundColor Green
            $innerResult = Invoke-SelfTest -WriteFixtures:$WriteFixtures
            $survivedState = Get-ProcessEnvironmentState -Name $name
            $survived = $survivedState.Exists -and [string]$survivedState.Value -ceq ''
        } else {
            Write-Host '  [FAIL] native process API did not create a present-empty variable' -ForegroundColor Red
        }
    }
    finally {
        Restore-ProcessEnvironmentState -Name $name -State $savedState
    }

    if ($survived) {
        Write-Host '  [PASS] adversarial caller present-empty state survived exact restoration' -ForegroundColor Green
    } else {
        Write-Host '  [FAIL] adversarial caller present-empty state did not survive exact restoration' -ForegroundColor Red
    }
    $wrapperRestored = Test-ProcessEnvironmentStateEqual `
        -Name $name -Expected $savedState
    if ($wrapperRestored) {
        Write-Host '  [PASS] adversarial wrapper restored its original caller state' -ForegroundColor Green
    } else {
        Write-Host '  [FAIL] adversarial wrapper did not restore its original caller state' -ForegroundColor Red
    }
    if ($planted -and $survived -and $wrapperRestored -and $innerResult -eq 0) {
        Write-Host '[check_release_recovery_record] PRESENT-EMPTY SELF-TEST OK' -ForegroundColor Green
        return 0
    }
    Write-Host '[check_release_recovery_record] PRESENT-EMPTY SELF-TEST FAILED' -ForegroundColor Red
    return 2
}

if ($UpdateFixtures -and -not $SelfTest) {
    Write-Host '[check_release_recovery_record] ERROR -- -UpdateFixtures requires -SelfTest.' -ForegroundColor Red
    exit 2
}
if ($SelfTestPresentEmptyEnvironment -and -not $SelfTest) {
    Write-Host '[check_release_recovery_record] ERROR -- -SelfTestPresentEmptyEnvironment requires -SelfTest.' -ForegroundColor Red
    exit 2
}
if ($SelfTestPresentEmptyEnvironment) {
    exit (Invoke-PresentEmptyEnvironmentSelfTest -WriteFixtures:$UpdateFixtures)
}
if ($SelfTest) { exit (Invoke-SelfTest -WriteFixtures:$UpdateFixtures) }
Write-Host '[check_release_recovery_record] ERROR -- pass -SelfTest.' -ForegroundColor Red
exit 2
