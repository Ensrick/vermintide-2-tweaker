# Fail-closed normalization for explicitly inventoried, non-mod VMB build
# artifacts. ASCII-only for Windows PowerShell 5.1 parsing.

function Initialize-BuildOutputNormalizationNativeMethods {
    if ('VtBuildNormalization.NativeMethods' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace VtBuildNormalization
{
    [StructLayout(LayoutKind.Sequential)]
    public struct ByHandleFileInformation
    {
        public uint FileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct FileDispositionInformation
    {
        [MarshalAs(UnmanagedType.Bool)]
        public bool DeleteFile;
    }

    public static class NativeMethods
    {
        private const uint GENERIC_READ = 0x80000000;
        private const uint DELETE = 0x00010000;
        private const uint FILE_SHARE_READ = 0x00000001;
        private const uint OPEN_EXISTING = 3;
        private const uint FILE_ATTRIBUTE_NORMAL = 0x00000080;
        private const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        private const uint FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000;
        private const int FILE_DISPOSITION_INFO = 4;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string fileName,
            uint desiredAccess,
            uint shareMode,
            IntPtr securityAttributes,
            uint creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetFileInformationByHandle(
            SafeFileHandle file,
            out ByHandleFileInformation information);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetFileInformationByHandle(
            SafeFileHandle file,
            int fileInformationClass,
            ref FileDispositionInformation information,
            uint bufferSize);

        public static SafeFileHandle OpenExactDeleteHandle(string path)
        {
            SafeFileHandle handle = CreateFile(
                path,
                GENERIC_READ | DELETE,
                FILE_SHARE_READ,
                IntPtr.Zero,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN,
                IntPtr.Zero);
            if (handle.IsInvalid)
            {
                int code = Marshal.GetLastWin32Error();
                handle.Dispose();
                throw new Win32Exception(code, "Unable to lock build-output exclusion for exact deletion.");
            }
            return handle;
        }

        public static ByHandleFileInformation GetInformation(SafeFileHandle handle)
        {
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(handle, out information))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to query locked build-output exclusion identity.");
            return information;
        }

        public static void MarkDeleteOnClose(SafeFileHandle handle)
        {
            FileDispositionInformation information = new FileDispositionInformation();
            information.DeleteFile = true;
            if (!SetFileInformationByHandle(
                    handle,
                    FILE_DISPOSITION_INFO,
                    ref information,
                    (uint)Marshal.SizeOf(typeof(FileDispositionInformation))))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to mark locked build-output exclusion for deletion.");
        }
    }
}
'@
}

function Get-BuildOutputFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
}

function Test-BuildOutputPathEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )
    return [string]::Equals(
        (Get-BuildOutputFullPath -Path $Left),
        (Get-BuildOutputFullPath -Path $Right),
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-BuildOutputNormalizationPolicyAlgorithm {
    return 'exact-build-artifact-exclusions-sha256-v1'
}

function Get-BuildOutputNormalizationSha256Hex {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Test-BuildOutputObjectHasProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Object -is [System.Collections.IDictionary]) {
        return $Object.Contains($Name)
    }
    return $null -ne $Object.PSObject.Properties[$Name]
}

function Assert-BuildOutputDirectoryIsNotReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Build-output normalization refuses a reparse-point ${Label}: $Path"
    }
}

function Get-BuildArtifactExclusionErrors {
    param([Parameter(Mandatory = $true)]$ModEntry)

    $errors = @()
    $dir = [string]$ModEntry.Dir
    $rootBundle = [string]$ModEntry.RootBundle
    $seen = @{}

    foreach ($exclusion in @($ModEntry.BuildArtifactExclusions | Where-Object { $null -ne $_ })) {
        $name = [string]$exclusion.Name
        $sha256 = [string]$exclusion.Sha256
        $reason = [string]$exclusion.Reason

        if ($name -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') {
            $errors += "invalid BuildArtifactExclusions name for ${dir}: $name"
            continue
        }
        if ([System.IO.Path]::GetFileName($name) -cne $name) {
            $errors += "BuildArtifactExclusions name is not a leaf for ${dir}: $name"
        }
        if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
            $errors += "invalid BuildArtifactExclusions SHA-256 for ${dir}/$name"
        }
        if ([string]::IsNullOrWhiteSpace($reason)) {
            $errors += "BuildArtifactExclusions reason is empty for ${dir}/$name"
        }
        if ($name -ieq $rootBundle) {
            $errors += "BuildArtifactExclusions cannot name RootBundle for ${dir}: $name"
        }
        if ($seen.ContainsKey($name)) {
            $errors += "duplicate BuildArtifactExclusions name for ${dir}: $name"
        } else {
            $seen[$name] = $true
        }
    }

    return @($errors)
}

function Get-BuildOutputPolicyErrors {
    param([Parameter(Mandatory = $true)]$ModEntry)

    $errors = @()
    $dir = [string]$ModEntry.Dir
    $authority = [string]$ModEntry.BundleAuthority
    if ($authority -cne 'tracked') {
        $errors += "invalid BundleAuthority for ${dir}: '$authority' (expected 'tracked')"
    }
    $errors += @(Get-BuildArtifactExclusionErrors -ModEntry $ModEntry)
    return @($errors)
}

function New-BuildOutputNormalizationPolicyProof {
    [CmdletBinding(DefaultParameterSetName = 'Exclusions')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'ModEntry')]
        $ModEntry,

        [Parameter(ParameterSetName = 'Exclusions')]
        [Alias('BuildArtifactExclusions')]
        [AllowEmptyCollection()]
        [object[]]$Exclusions = @()
    )

    if ($PSCmdlet.ParameterSetName -eq 'ModEntry') {
        $errors = @(Get-BuildOutputPolicyErrors -ModEntry $ModEntry)
        if ($errors.Count -gt 0) {
            throw "Invalid build-output normalization policy proof: $($errors -join '; ')"
        }
        $Exclusions = @($ModEntry.BuildArtifactExclusions | Where-Object { $null -ne $_ })
    }
    else {
        # Reuse the exact exclusion validator. The sentinel root cannot
        # collide with a valid 16-hex bundle filename; real root collisions
        # are checked by the ModEntry parameter set.
        $validationEntry = @{
            Dir = '<normalization-policy-proof>'
            RootBundle = '<not-a-valid-bundle-name>'
            BuildArtifactExclusions = @($Exclusions)
        }
        $errors = @(Get-BuildArtifactExclusionErrors -ModEntry $validationEntry)
        if ($errors.Count -gt 0) {
            throw "Invalid build-output normalization policy proof: $($errors -join '; ')"
        }
    }

    $byFilename = @{}
    $filenames = [string[]]@($Exclusions | ForEach-Object { [string]$_.Name })
    foreach ($exclusion in @($Exclusions)) {
        $filename = [string]$exclusion.Name
        $byFilename[$filename] = [pscustomobject][ordered]@{
            Filename = $filename
            Sha256 = ([string]$exclusion.Sha256).ToLowerInvariant()
        }
    }
    [System.Array]::Sort($filenames, [System.StringComparer]::Ordinal)
    $normalized = @($filenames | ForEach-Object { $byFilename[$_] })

    # The identity deliberately excludes Reason. Prose can improve without
    # invalidating an immutable byte-removal policy; only exact name+hash pairs
    # authorize normalization.
    $builder = New-Object System.Text.StringBuilder
    foreach ($entry in $normalized) {
        [void]$builder.Append([string]$entry.Filename)
        [void]$builder.Append([char]0)
        [void]$builder.Append([string]$entry.Sha256)
        [void]$builder.Append("`n")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    return [pscustomobject][ordered]@{
        Algorithm = Get-BuildOutputNormalizationPolicyAlgorithm
        FingerprintSha256 = Get-BuildOutputNormalizationSha256Hex -Bytes $bytes
        ExcludedOutputs = @($normalized)
    }
}

function Get-BuildOutputNormalizationPolicyDetails {
    param(
        [AllowEmptyCollection()]
        [object[]]$Exclusions = @()
    )

    $proof = New-BuildOutputNormalizationPolicyProof -Exclusions @($Exclusions)
    $byFilename = @{}
    foreach ($exclusion in @($Exclusions)) {
        $byFilename[[string]$exclusion.Name] = $exclusion
    }
    return @($proof.ExcludedOutputs | ForEach-Object {
        $source = $byFilename[[string]$_.Filename]
        [pscustomobject][ordered]@{
            Filename = [string]$_.Filename
            Sha256 = [string]$_.Sha256
            Reason = [string]$source.Reason
        }
    })
}

function Get-BuildOutputNormalizationPolicyProofValidation {
    param(
        [Parameter(Mandatory = $true)]$Proof,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $problems = @()
    $canonical = $null
    if ($null -eq $Proof) {
        return [pscustomobject]@{
            Problems = @("$Label normalization policy proof is null")
            Canonical = $null
        }
    }

    $algorithm = [string]$Proof.Algorithm
    $expectedAlgorithm = Get-BuildOutputNormalizationPolicyAlgorithm
    if ($algorithm -cne $expectedAlgorithm) {
        $problems += "$Label normalization policy algorithm '$algorithm' is not '$expectedAlgorithm'"
    }

    $fingerprint = [string]$Proof.FingerprintSha256
    if ($fingerprint -cnotmatch '^[0-9a-f]{64}$') {
        $problems += "$Label normalization policy fingerprint is not lowercase SHA-256"
    }

    $hasOutputs = Test-BuildOutputObjectHasProperty -Object $Proof -Name 'ExcludedOutputs'
    if (-not $hasOutputs -or $null -eq $Proof.ExcludedOutputs) {
        $problems += "$Label normalization policy ExcludedOutputs is missing"
    }
    else {
        $identityInputs = @()
        $structuralErrors = @()
        foreach ($entry in @($Proof.ExcludedOutputs)) {
            $filename = [string]$entry.Filename
            $sha256 = [string]$entry.Sha256
            if ($filename -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') {
                $structuralErrors += "$Label normalization policy filename is invalid: $filename"
            }
            if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
                $structuralErrors += "$Label normalization policy SHA-256 is invalid for ${filename}: $sha256"
            }
            $identityInputs += [pscustomobject]@{
                Name = $filename
                Sha256 = $sha256
                Reason = 'proof identity validation'
            }
        }
        if ($structuralErrors.Count -gt 1) {
            $sortedStructuralErrors = [string[]]@($structuralErrors)
            [System.Array]::Sort($sortedStructuralErrors, [System.StringComparer]::Ordinal)
            $structuralErrors = @($sortedStructuralErrors)
        }
        $problems += @($structuralErrors)
        if ($structuralErrors.Count -eq 0) {
            try {
                $canonical = New-BuildOutputNormalizationPolicyProof -Exclusions @($identityInputs)
                $actualOutputs = @($Proof.ExcludedOutputs)
                $canonicalOutputs = @($canonical.ExcludedOutputs)
                for ($index = 0; $index -lt $canonicalOutputs.Count; $index++) {
                    if ([string]$actualOutputs[$index].Filename -cne [string]$canonicalOutputs[$index].Filename -or
                            [string]$actualOutputs[$index].Sha256 -cne [string]$canonicalOutputs[$index].Sha256) {
                        $problems += "$Label normalization policy exclusions are not in canonical ordinal order"
                        break
                    }
                }
                if ($fingerprint -match '^[0-9a-f]{64}$' -and
                        $fingerprint -cne [string]$canonical.FingerprintSha256) {
                    $problems += "$Label normalization policy fingerprint does not match ExcludedOutputs"
                }
            }
            catch {
                $problems += "$Label normalization policy ExcludedOutputs is invalid: $($_.Exception.Message)"
            }
        }
    }

    return [pscustomobject]@{ Problems = @($problems); Canonical = $canonical }
}

function Compare-BuildOutputNormalizationPolicyProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual
    )

    $expectedValidation = Get-BuildOutputNormalizationPolicyProofValidation -Proof $Expected -Label 'expected'
    $actualValidation = Get-BuildOutputNormalizationPolicyProofValidation -Proof $Actual -Label 'actual'
    $problems = @($expectedValidation.Problems) + @($actualValidation.Problems)

    if ($null -ne $expectedValidation.Canonical -and $null -ne $actualValidation.Canonical) {
        $expectedByName = @{}
        $actualByName = @{}
        foreach ($entry in @($expectedValidation.Canonical.ExcludedOutputs)) {
            $expectedByName[[string]$entry.Filename] = $entry
        }
        foreach ($entry in @($actualValidation.Canonical.ExcludedOutputs)) {
            $actualByName[[string]$entry.Filename] = $entry
        }
        foreach ($entry in @($expectedValidation.Canonical.ExcludedOutputs)) {
            $filename = [string]$entry.Filename
            if (-not $actualByName.ContainsKey($filename)) {
                $problems += "normalization policy exclusion removed: $filename"
            }
            elseif ([string]$entry.Sha256 -cne [string]$actualByName[$filename].Sha256) {
                $problems += "normalization policy exclusion SHA-256 changed: $filename"
            }
        }
        foreach ($entry in @($actualValidation.Canonical.ExcludedOutputs)) {
            $filename = [string]$entry.Filename
            if (-not $expectedByName.ContainsKey($filename)) {
                $problems += "normalization policy exclusion added: $filename"
            }
        }
        $hasEntryProblem = @($problems | Where-Object {
            $_ -like 'normalization policy exclusion removed:*' -or
            $_ -like 'normalization policy exclusion added:*' -or
            $_ -like 'normalization policy exclusion SHA-256 changed:*'
        }).Count -gt 0
        if (-not $hasEntryProblem -and
                [string]$Expected.FingerprintSha256 -cne [string]$Actual.FingerprintSha256) {
            $problems += 'normalization policy fingerprint changed without an exclusion-level difference'
        }
    }

    return [pscustomobject][ordered]@{
        Ok = ($problems.Count -eq 0)
        Problems = @($problems)
    }
}

function Get-ModBuildArtifactPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $inventoryPath = Join-Path $RepoRoot 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Build-output normalization inventory is missing: $inventoryPath"
    }

    $inventory = Import-PowerShellDataFile -Path $inventoryPath
    $entries = @($inventory.Mods | Where-Object { [string]$_.Dir -eq $Mod })
    if ($entries.Count -ne 1) {
        throw "Build-output normalization could not resolve one inventory entry for '$Mod'."
    }

    $entry = $entries[0]
    $errors = @(Get-BuildOutputPolicyErrors -ModEntry $entry)
    if ($errors.Count -gt 0) {
        throw "Invalid build-output normalization policy: $($errors -join '; ')"
    }
    return $entry
}

function Get-ModBuildOutputNormalizationPolicyProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $entry = Get-ModBuildArtifactPolicy -RepoRoot $RepoRoot -Mod $Mod
    return New-BuildOutputNormalizationPolicyProof -ModEntry $entry
}

function Invoke-BuildOutputNormalization {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod,
        [scriptblock]$BeforeDeleteTestHook
    )

    $entry = Get-ModBuildArtifactPolicy -RepoRoot $RepoRoot -Mod $Mod
    $exclusions = @($entry.BuildArtifactExclusions | Where-Object { $null -ne $_ })
    $policy = New-BuildOutputNormalizationPolicyProof -ModEntry $entry
    $policyDetails = @(Get-BuildOutputNormalizationPolicyDetails -Exclusions $exclusions)
    $result = [ordered]@{
        Mod = $Mod
        BundleAuthority = [string]$entry.BundleAuthority
        Policy = $policy
        PolicyDetails = @($policyDetails)
        Removed = 0
        Absent = 0
        RemovedNames = @()
    }
    if ($exclusions.Count -eq 0) {
        return [pscustomobject]$result
    }

    $repoDirectory = Get-BuildOutputFullPath -Path (Resolve-Path -LiteralPath $RepoRoot).Path
    $modDirectory = Get-BuildOutputFullPath -Path (Join-Path $repoDirectory $Mod)
    if (-not (Test-BuildOutputPathEqual -Left ([System.IO.Path]::GetDirectoryName($modDirectory)) -Right $repoDirectory)) {
        throw "Build-output normalization mod directory escaped RepoRoot: $modDirectory"
    }
    if (-not (Test-Path -LiteralPath $modDirectory -PathType Container)) {
        throw "Build-output normalization mod directory is missing: $modDirectory"
    }
    Assert-BuildOutputDirectoryIsNotReparsePoint -Path $modDirectory -Label 'mod directory'

    $bundleDirectory = Join-Path $modDirectory 'bundleV2'
    if (-not (Test-Path -LiteralPath $bundleDirectory -PathType Container)) {
        throw "Build-output normalization bundle directory is missing: $bundleDirectory"
    }
    Assert-BuildOutputDirectoryIsNotReparsePoint -Path $bundleDirectory -Label 'bundleV2 directory'
    $bundleRoot = Get-BuildOutputFullPath -Path (Resolve-Path -LiteralPath $bundleDirectory).Path
    if (-not (Test-BuildOutputPathEqual -Left ([System.IO.Path]::GetDirectoryName($bundleRoot)) -Right $modDirectory)) {
        throw "Build-output normalization bundleV2 escaped the inventoried mod directory: $bundleRoot"
    }

    foreach ($exclusion in $policyDetails) {
        $name = [string]$exclusion.Filename
        $expectedSha256 = [string]$exclusion.Sha256
        $candidate = Get-BuildOutputFullPath -Path (Join-Path $bundleRoot $name)
        $candidateParent = [System.IO.Path]::GetDirectoryName($candidate)
        if (-not (Test-BuildOutputPathEqual -Left $candidateParent -Right $bundleRoot)) {
            throw "Build-output normalization target escaped bundleV2: $candidate"
        }

        if (-not (Test-Path -LiteralPath $candidate)) {
            $result.Absent++
            Write-Host "  build normalization: $Mod/$name not emitted (canonical absence)" -ForegroundColor DarkGray
            continue
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Build-output normalization target is not a file: $candidate"
        }
        $candidateItem = Get-Item -LiteralPath $candidate -Force
        if (($candidateItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Build-output normalization refuses a reparse-point target: $candidate"
        }

        Initialize-BuildOutputNormalizationNativeMethods
        $nativeHandle = [VtBuildNormalization.NativeMethods]::OpenExactDeleteHandle($candidate)
        $candidateStream = $null
        try {
            $candidateStream = New-Object System.IO.FileStream(
                $nativeHandle,
                [System.IO.FileAccess]::Read,
                4096,
                $false)
            $nativeHandle = $null
            $handleInfo = [VtBuildNormalization.NativeMethods]::GetInformation(
                $candidateStream.SafeFileHandle)
            if (($handleInfo.FileAttributes -band [uint32][System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Build-output normalization refuses a raced reparse-point target: $candidate"
            }
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $candidateStream.Position = 0
                $actualSha256 = [System.BitConverter]::ToString(
                    $sha.ComputeHash($candidateStream)).Replace('-', '').ToLowerInvariant()
            }
            finally { $sha.Dispose() }
            if ($actualSha256 -cne $expectedSha256) {
                throw ("Build-output normalization REFUSED changed bytes for {0}/{1}: expected SHA-256 {2}, got {3}. " +
                    "The file was left untouched for inspection." -f $Mod, $name, $expectedSha256, $actualSha256)
            }
            if ($BeforeDeleteTestHook) { & $BeforeDeleteTestHook $candidate }
            [VtBuildNormalization.NativeMethods]::MarkDeleteOnClose(
                $candidateStream.SafeFileHandle)
        }
        finally {
            if ($candidateStream) { $candidateStream.Dispose() }
            elseif ($nativeHandle) { $nativeHandle.Dispose() }
        }
        if (Test-Path -LiteralPath $candidate) {
            throw "Build-output normalization removed its approved object but the path was reused: $candidate"
        }
        $result.Removed++
        $result.RemovedNames += $name
        Write-Host "  build normalization: removed exact known SDK tool-only sidecar $Mod/$name" -ForegroundColor Yellow
    }

    return [pscustomobject]$result
}
