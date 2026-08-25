# Adversarial tests and focused validation for canonical bundleV2 output sets.
# ASCII-only for Windows PowerShell 5.1 parsing.

[CmdletBinding()]
param(
    [string]$BundleDirectory,
    [string]$ExpectedDescriptorName,
    [string]$ExpectedRootBundle,
    [string]$ExpectedDescriptorSha256,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$helperPath = Join-Path $repoRoot 'tools\ship\bundle-output-set.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    Write-Host "[check_bundle_output_set] ERROR -- helper missing: $helperPath" -ForegroundColor Red
    exit 2
}
. $helperPath

function Remove-VtBundleOutputTestTree {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\', '/'))
    $tempPrefix = $tempRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($tempPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean bundle-output fixture outside the temp root: $fullPath"
    }

    function Remove-VtBundleOutputTestEntry {
        param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Entry)

        $Entry.Refresh()
        if (-not $Entry.Exists) { return }
        $isReparse = (($Entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        $isDirectory = (($Entry.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0)
        if ($isReparse) {
            $Entry.Delete()
            return
        }
        if ($isDirectory) {
            foreach ($child in @(([System.IO.DirectoryInfo]$Entry).EnumerateFileSystemInfos())) {
                Remove-VtBundleOutputTestEntry -Entry $child
            }
            ([System.IO.DirectoryInfo]$Entry).Delete()
            return
        }
        $Entry.Attributes = [System.IO.FileAttributes]::Normal
        $Entry.Delete()
    }

    Remove-VtBundleOutputTestEntry -Entry ([System.IO.DirectoryInfo]::new($fullPath))
}

function Write-VtBundleOutputTestFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Copy-VtBundleOutputTestRecords {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    return @($Records | ForEach-Object {
        [pscustomobject][ordered]@{
            Name = [string]$_.Name
            Length = [long]$_.Length
            Sha256 = [string]$_.Sha256
        }
    })
}

function Invoke-VtBundleOutputSetSelfTest {
    $failures = [System.Collections.Generic.List[string]]::new()
    function Assert([bool]$Condition, [string]$Description) {
        if ($Condition) {
            Write-Host "  [PASS] $Description" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $Description" -ForegroundColor Red
            $failures.Add($Description)
        }
    }
    function Assert-Throws([scriptblock]$Action, [string]$Pattern, [string]$Description) {
        $threw = $false
        $message = ''
        try { & $Action | Out-Null }
        catch {
            $threw = $true
            $message = $_.Exception.Message
        }
        $matched = $threw -and $message -match $Pattern
        Assert $matched $Description
        if ($threw -and -not $matched) {
            Write-Host "         unexpected error: $message" -ForegroundColor DarkGray
        }
    }

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) (
        'vt2-bundle-output-set-' + [guid]::NewGuid().ToString('N'))
    $bundleDirectory = Join-Path $temp 'bundleV2'
    $rootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle'
    $secondaryBundle = 'bbbbbbbbbbbbbbbb.mod_bundle'
    $descriptorName = 'example.mod'
    [System.IO.Directory]::CreateDirectory($bundleDirectory) | Out-Null

    try {
        Write-VtBundleOutputTestFile -Path (Join-Path $bundleDirectory $rootBundle) -Text 'root bytes'
        Write-VtBundleOutputTestFile -Path (Join-Path $bundleDirectory $secondaryBundle) -Text 'secondary bytes'
        Write-VtBundleOutputTestFile -Path (Join-Path $bundleDirectory $descriptorName) -Text 'descriptor bytes'

        $physical = Get-VtBundleOutputSet `
            -BundleDirectory $bundleDirectory `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        Assert ($physical.Algorithm -ceq 'vt2-normalized-bundle-output-set-sha256-v1') 'uses the versioned output-set algorithm'
        Assert (($physical.Files.Name -join ',') -ceq "$rootBundle,$secondaryBundle,$descriptorName") 'sorts records with exact ordinal filename order'
        Assert ($physical.Root.Name -ceq $rootBundle) 'binds only the explicitly declared root bundle'
        Assert ($physical.Descriptor.Name -ceq $descriptorName) 'binds the one exact descriptor'
        Assert ($physical.Fingerprint -cmatch '^[0-9a-f]{64}$') 'produces a lowercase SHA-256 fingerprint'

        $singleRecord = Get-VtBundleOutputFileRecord `
            -Path (Join-Path $bundleDirectory $rootBundle) `
            -Name $rootBundle
        Assert (
            $singleRecord.Name -ceq $physical.Root.Name -and
            $singleRecord.Length -eq $physical.Root.Length -and
            $singleRecord.Sha256 -ceq $physical.Root.Sha256
        ) 'single-file record API hashes and measures the exact named path'
        Assert-Throws {
            Get-VtBundleOutputFileRecord `
                -Path (Join-Path $bundleDirectory $rootBundle) `
                -Name $secondaryBundle
        } 'does not exactly match path leaf' 'single-file record API rejects a mismatched logical name'

        $goldenRecords = @(
            [pscustomobject]@{ Name = $descriptorName; Length = 10L; Sha256 = ('e' * 64) },
            [pscustomobject]@{ Name = $secondaryBundle; Length = 2L; Sha256 = ('b' * 64) },
            [pscustomobject]@{ Name = $rootBundle; Length = 1L; Sha256 = ('a' * 64) }
        )
        $golden = New-VtBundleOutputSet `
            -Records $goldenRecords `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        Assert (
            $golden.Fingerprint -ceq 'c9bd51684a85ec90e138608ed5a09f5f86aae384485da2509683da3fa24fc266'
        ) 'fingerprint canonical bytes match the cross-host golden value'

        $reversed = @(Copy-VtBundleOutputTestRecords -Records $physical.Files)
        [System.Array]::Reverse($reversed)
        $reordered = New-VtBundleOutputSet `
            -Records $reversed `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        Assert ($reordered.Fingerprint -ceq $physical.Fingerprint) 'fingerprint is independent of input enumeration order'

        $priorCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
        $priorUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
        try {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $cultureSet = New-VtBundleOutputSet `
                -Records $reversed `
                -ExpectedDescriptorName $descriptorName `
                -ExpectedRootBundle $rootBundle
            Assert ($cultureSet.Fingerprint -ceq $physical.Fingerprint) 'fingerprint is invariant under a non-default process culture'
        }
        finally {
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $priorCulture
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $priorUiCulture
        }

        $sameErrors = @(Compare-VtBundleOutputSets -Expected $physical -Actual $reordered)
        Assert ($sameErrors.Count -eq 0) 'set comparison accepts identical complete output records'

        $changedRecords = @(Copy-VtBundleOutputTestRecords -Records $physical.Files)
        $changedRecords[0].Sha256 = ('f' * 64)
        $changed = New-VtBundleOutputSet `
            -Records $changedRecords `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        $changedErrors = @(Compare-VtBundleOutputSets -Expected $physical -Actual $changed)
        Assert (@($changedErrors -match 'changed SHA-256').Count -eq 1) 'set comparison rejects changed file bytes'

        $missingRecords = @($physical.Files | Where-Object { $_.Name -cne $secondaryBundle })
        $missing = New-VtBundleOutputSet `
            -Records $missingRecords `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        $missingErrors = @(Compare-VtBundleOutputSets -Expected $physical -Actual $missing)
        Assert (@($missingErrors -match 'is missing').Count -eq 1) 'set comparison rejects a missing output file'

        $extraRecords = @(Copy-VtBundleOutputTestRecords -Records $physical.Files)
        $extraRecords += [pscustomobject]@{
            Name = 'cccccccccccccccc.mod_bundle'; Length = 9L; Sha256 = ('c' * 64)
        }
        $extra = New-VtBundleOutputSet `
            -Records $extraRecords `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        $extraErrors = @(Compare-VtBundleOutputSets -Expected $physical -Actual $extra)
        Assert (@($extraErrors -match 'contains unexpected').Count -eq 1) 'set comparison rejects an extra output file'

        $lengthRecords = @(Copy-VtBundleOutputTestRecords -Records $physical.Files)
        $lengthRecords[0].Length++
        $lengthOnly = New-VtBundleOutputSet `
            -Records $lengthRecords `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        Assert (@(Compare-VtBundleOutputSets -Expected $physical -Actual $lengthOnly).Count -eq 1) 'strict comparison rejects changed byte length'
        Assert (@(Compare-VtBundleOutputSets -Expected $physical -Actual $lengthOnly -RequireLength:$false).Count -eq 0) 'legacy manifest comparison can omit byte length explicitly'

        $manifestRecords = @(ConvertTo-VtBundleManifestRecords -OutputSet $physical)
        Assert (($manifestRecords.filename -join ',') -ceq "$rootBundle,$secondaryBundle,$descriptorName") 'manifest projection preserves ordinal complete-set order'
        Assert (
            $manifestRecords.Count -eq 3 -and
            @($manifestRecords[0].PSObject.Properties.Name).Count -eq 2 -and
            $null -ne $manifestRecords[0].filename -and
            $null -ne $manifestRecords[0].sha256
        ) 'manifest projection contains only filename and SHA-256 compatibility fields'

        $descriptorPath = Join-Path $bundleDirectory $descriptorName
        [System.IO.File]::Delete($descriptorPath)
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'missing its exact descriptor' 'physical enumeration rejects a missing descriptor'
        Write-VtBundleOutputTestFile -Path $descriptorPath -Text 'descriptor bytes'

        $wrongDescriptorPath = Join-Path $bundleDirectory 'wrong.mod'
        [System.IO.File]::Move($descriptorPath, $wrongDescriptorPath)
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'unexpected filename' 'physical enumeration rejects a wrong descriptor name'
        [System.IO.File]::Move($wrongDescriptorPath, $descriptorPath)

        $otherDescriptorPath = Join-Path $bundleDirectory 'other.mod'
        Write-VtBundleOutputTestFile -Path $otherDescriptorPath -Text 'other descriptor'
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'unexpected filename' 'physical enumeration rejects an additional descriptor'
        [System.IO.File]::Delete($otherDescriptorPath)

        Assert-Throws {
            Get-VtBundleOutputSet `
                -BundleDirectory $bundleDirectory `
                -ExpectedDescriptorName $descriptorName `
                -ExpectedRootBundle $rootBundle `
                -ExpectedDescriptorSha256 ('0' * 64)
        } 'descriptor SHA-256 mismatch' 'physical enumeration rejects a descriptor hash mismatch'

        foreach ($unsafeName in @(
            'aaaaaaaaaaaaaaaa.mod_bundle.',
            'aaaaaaaaaaaaaaaa.mod_bundle ',
            'nested\aaaaaaaaaaaaaaaa.mod_bundle',
            'aaaaaaaaaaaaaaaa.mod_bundle:stream')) {
            $unsafeRecords = @(Copy-VtBundleOutputTestRecords -Records $physical.Files)
            $unsafeRecords += [pscustomobject]@{ Name = $unsafeName; Length = 1L; Sha256 = ('1' * 64) }
            Assert-Throws {
                New-VtBundleOutputSet `
                    -Records $unsafeRecords `
                    -ExpectedDescriptorName $descriptorName `
                    -ExpectedRootBundle $rootBundle
            } 'canonical Windows leaf filename|unexpected filename' "pure construction rejects unsafe Windows alias '$unsafeName'"
        }

        $duplicateDescriptorRecords = @(Copy-VtBundleOutputTestRecords -Records $physical.Files)
        $duplicateDescriptorRecords += [pscustomobject]@{
            Name = $descriptorName; Length = 1L; Sha256 = ('d' * 64)
        }
        Assert-Throws {
            New-VtBundleOutputSet -Records $duplicateDescriptorRecords -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'duplicate exact filename' 'pure construction rejects a duplicate exact descriptor record'

        $caseTwinRecords = @(Copy-VtBundleOutputTestRecords -Records $physical.Files)
        $caseTwinRecords += [pscustomobject]@{
            Name = 'AAAAAAAAAAAAAAAA.mod_bundle'; Length = 1L; Sha256 = ('a' * 64)
        }
        Assert-Throws {
            New-VtBundleOutputSet -Records $caseTwinRecords -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'case-colliding filenames' 'pure construction rejects case-twin filenames before filesystem assumptions'

        $uppercasePath = Join-Path $bundleDirectory 'CCCCCCCCCCCCCCCC.mod_bundle'
        Write-VtBundleOutputTestFile -Path $uppercasePath -Text 'upper'
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'unexpected filename' 'physical enumeration enforces lowercase bundle filenames'
        [System.IO.File]::Delete($uppercasePath)

        $unexpectedPath = Join-Path $bundleDirectory 'notes.txt'
        Write-VtBundleOutputTestFile -Path $unexpectedPath -Text 'unexpected'
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'unexpected filename' 'physical enumeration rejects an unexpected extension'
        [System.IO.File]::Delete($unexpectedPath)

        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle 'dddddddddddddddd.mod_bundle'
        } 'missing its declared root bundle' 'physical enumeration never infers a substitute root bundle'

        $nestedPath = Join-Path $bundleDirectory 'nested'
        [System.IO.Directory]::CreateDirectory($nestedPath) | Out-Null
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'contains a directory' 'physical enumeration rejects nested directories'
        [System.IO.Directory]::Delete($nestedPath, $false)

        $junctionTarget = Join-Path $temp 'junction-target'
        [System.IO.Directory]::CreateDirectory($junctionTarget) | Out-Null
        $nestedJunction = Join-Path $bundleDirectory 'nested-junction'
        New-Item -ItemType Junction -Path $nestedJunction -Target $junctionTarget -ErrorAction Stop | Out-Null
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $bundleDirectory -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'reparse-point entry' 'physical enumeration rejects a child directory reparse point'
        (Get-Item -LiteralPath $nestedJunction -Force).Delete()

        $rootJunction = Join-Path $temp 'bundle-link'
        New-Item -ItemType Junction -Path $rootJunction -Target $bundleDirectory -ErrorAction Stop | Out-Null
        Assert-Throws {
            Get-VtBundleOutputSet -BundleDirectory $rootJunction -ExpectedDescriptorName $descriptorName -ExpectedRootBundle $rootBundle
        } 'reparse-point directory' 'physical enumeration rejects a reparse-point bundle directory'
        (Get-Item -LiteralPath $rootJunction -Force).Delete()

        $rootPath = Join-Path $bundleDirectory $rootBundle
        $syntheticFileReparse = @([pscustomobject]@{
            Name = $rootBundle
            Kind = 'file'
            IsReparsePoint = $true
            FullName = $rootPath
        })
        Assert-Throws {
            Assert-VtBundleDirectorySnapshotFiles -Snapshot $syntheticFileReparse -BundleDirectory $bundleDirectory
        } 'reparse-point entry' 'snapshot validation rejects a file reparse point without requiring symlink privilege'

        $readHandle = Open-VtBundleOutputReadHandle -Path $rootPath
        $writer = $null
        $writeWasRefused = $false
        try {
            try {
                $writer = [System.IO.File]::Open(
                    $rootPath,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::ReadWrite)
            }
            catch [System.IO.IOException] { $writeWasRefused = $true }
        }
        finally {
            if ($null -ne $writer) { $writer.Dispose() }
            $readHandle.Dispose()
        }
        Assert $writeWasRefused 'held read handle denies concurrent write access while bytes are hashed'

        $replacementPath = Join-Path $bundleDirectory $rootBundle
        $replacementBytes = [System.IO.File]::ReadAllBytes($replacementPath)
        Assert-Throws {
            Get-VtBundleOutputSet `
                -BundleDirectory $bundleDirectory `
                -ExpectedDescriptorName $descriptorName `
                -ExpectedRootBundle $rootBundle `
                -BeforeOpenTestHook {
                    param($ignoredDirectory, $ignoredSnapshot)
                    [System.IO.File]::Delete($replacementPath)
                    [System.IO.File]::WriteAllBytes($replacementPath, $replacementBytes)
                }
        } 'mutation attempt failed closed while held handles were open' 'production enumeration denies a same-name replacement after its held handles open'

        $sameLengthOriginal = [System.IO.File]::ReadAllBytes($replacementPath)
        $sameLengthMutation = [byte[]]$sameLengthOriginal.Clone()
        $sameLengthMutation[0] = [byte]($sameLengthMutation[0] -bxor 1)
        Assert-Throws {
            Get-VtBundleOutputSet `
                -BundleDirectory $bundleDirectory `
                -ExpectedDescriptorName $descriptorName `
                -ExpectedRootBundle $rootBundle `
                -BeforeOpenTestHook {
                    param($ignoredDirectory, $ignoredSnapshot)
                    [System.IO.File]::WriteAllBytes($replacementPath, $sameLengthMutation)
                }
        } 'mutation attempt failed closed while held handles were open' 'production enumeration denies an in-place same-identity same-length rewrite'
        Assert ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($replacementPath)) -ceq
            [Convert]::ToBase64String($sameLengthOriginal)) 'denied same-length rewrite leaves the exact original bytes intact'

        $mutationPath = Join-Path $bundleDirectory 'cccccccccccccccc.mod_bundle'
        Assert-Throws {
            Get-VtBundleOutputSet `
                -BundleDirectory $bundleDirectory `
                -ExpectedDescriptorName $descriptorName `
                -ExpectedRootBundle $rootBundle `
                -BeforeSecondSnapshotTestHook {
                    param($ignoredDirectory, $ignoredRecords)
                    Write-VtBundleOutputTestFile -Path $mutationPath -Text 'appeared between snapshots'
                }
        } 'appeared during enumeration' 'production second snapshot rejects a filename created after hashing'
        [System.IO.File]::Delete($mutationPath)

        $final = Get-VtBundleOutputSet `
            -BundleDirectory $bundleDirectory `
            -ExpectedDescriptorName $descriptorName `
            -ExpectedRootBundle $rootBundle
        Assert (@(Compare-VtBundleOutputSets -Expected $physical -Actual $final).Count -eq 0) 'fixture restoration returns to the identical complete output set'

        if ($failures.Count -gt 0) {
            Write-Host "[check_bundle_output_set] SELF-TEST FAILED -- $($failures.Count) case(s)" -ForegroundColor Red
            return 2
        }
        Write-Host '[check_bundle_output_set] SELF-TEST OK' -ForegroundColor Green
        return 0
    }
    finally {
        Remove-VtBundleOutputTestTree -Path $temp
    }
}

if ($SelfTest) { exit (Invoke-VtBundleOutputSetSelfTest) }

if ([string]::IsNullOrWhiteSpace($BundleDirectory) -or
    [string]::IsNullOrWhiteSpace($ExpectedDescriptorName) -or
    [string]::IsNullOrWhiteSpace($ExpectedRootBundle)) {
    Write-Host '[check_bundle_output_set] ERROR -- pass -BundleDirectory, -ExpectedDescriptorName, and -ExpectedRootBundle, or use -SelfTest.' -ForegroundColor Red
    exit 2
}

try {
    $arguments = @{
        BundleDirectory = $BundleDirectory
        ExpectedDescriptorName = $ExpectedDescriptorName
        ExpectedRootBundle = $ExpectedRootBundle
    }
    if ($PSBoundParameters.ContainsKey('ExpectedDescriptorSha256')) {
        $arguments.ExpectedDescriptorSha256 = $ExpectedDescriptorSha256
    }
    $set = Get-VtBundleOutputSet @arguments
    if (-not $Quiet) {
        Write-Host ("[check_bundle_output_set] OK -- {0} files, fingerprint {1}." -f
            @($set.Files).Count, $set.Fingerprint) -ForegroundColor Green
    }
    exit 0
}
catch {
    Write-Host "[check_bundle_output_set] ERROR -- $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
