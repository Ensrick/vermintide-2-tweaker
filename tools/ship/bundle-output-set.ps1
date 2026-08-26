# Canonical, fail-closed inventory of one normalized VMB bundleV2 directory.
# This helper is intentionally independent of Git, mod inventory, receipts, and
# release publication. ASCII-only for Windows PowerShell 5.1 parsing.

function Get-VtBundleOutputSetAlgorithm {
    return 'vt2-normalized-bundle-output-set-sha256-v1'
}

function Initialize-VtBundleOutputNativeMethods {
    if ('VtBundleOutput.NativeMethods' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace VtBundleOutput
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

    public static class NativeMethods
    {
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool GetFileInformationByHandle(
            SafeFileHandle file,
            out ByHandleFileInformation information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFileW(
            string fileName,
            uint desiredAccess,
            FileShare shareMode,
            IntPtr securityAttributes,
            FileMode creationDisposition,
            uint flagsAndAttributes,
            IntPtr templateFile);
    }
}
'@
}

function Get-VtBundleOutputHandleProof {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)

    Initialize-VtBundleOutputNativeMethods
    $information = New-Object VtBundleOutput.ByHandleFileInformation
    if (-not [VtBundleOutput.NativeMethods]::GetFileInformationByHandle(
            $Stream.SafeFileHandle,
            [ref]$information)) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw New-Object System.ComponentModel.Win32Exception(
            $errorCode,
            'Unable to bind a bundle output path to its Windows file identity.')
    }

    $length = ([uint64]$information.FileSizeHigh * [uint64]4294967296) +
        [uint64]$information.FileSizeLow
    return [pscustomobject][ordered]@{
        Identity = ('{0:x8}:{1:x8}{2:x8}' -f
            $information.VolumeSerialNumber,
            $information.FileIndexHigh,
            $information.FileIndexLow)
        Length = [long]$length
    }
}

function Get-VtBundleOutputDirectoryHandleProof {
    param([Parameter(Mandatory = $true)][Microsoft.Win32.SafeHandles.SafeFileHandle]$Handle)

    Initialize-VtBundleOutputNativeMethods
    if ($Handle.IsInvalid -or $Handle.IsClosed) {
        throw 'Unable to inspect a closed or invalid bundle output directory handle.'
    }

    $information = New-Object VtBundleOutput.ByHandleFileInformation
    if (-not [VtBundleOutput.NativeMethods]::GetFileInformationByHandle(
            $Handle,
            [ref]$information)) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw New-Object System.ComponentModel.Win32Exception(
            $errorCode,
            'Unable to bind the bundle output directory to its Windows file identity.')
    }

    return [pscustomobject][ordered]@{
        Identity = ('{0:x8}:{1:x8}{2:x8}' -f
            $information.VolumeSerialNumber,
            $information.FileIndexHigh,
            $information.FileIndexLow)
        Attributes = [System.IO.FileAttributes]$information.FileAttributes
    }
}

function Open-VtBundleOutputDirectoryIdentityHandle {
    param([Parameter(Mandatory = $true)][string]$Path)

    Initialize-VtBundleOutputNativeMethods
    $fileReadAttributes = [uint32]0x00000080
    $openDirectoryWithoutFollowingReparse = [uint32]0x02200000
    $shareMode = [System.IO.FileShare]::Read -bor [System.IO.FileShare]::Write
    $handle = [VtBundleOutput.NativeMethods]::CreateFileW(
        $Path,
        $fileReadAttributes,
        $shareMode,
        [System.IntPtr]::Zero,
        [System.IO.FileMode]::Open,
        $openDirectoryWithoutFollowingReparse,
        [System.IntPtr]::Zero)
    if ($null -eq $handle -or $handle.IsInvalid) {
        $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($null -ne $handle) { $handle.Dispose() }
        throw New-Object System.ComponentModel.Win32Exception(
            $errorCode,
            "Unable to open the bundle output directory identity handle: $Path")
    }
    return $handle
}

function Assert-VtBundleOutputDirectoryIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][Microsoft.Win32.SafeHandles.SafeFileHandle]$HeldHandle,
        [Parameter(Mandatory = $true)][string]$ExpectedIdentity
    )

    $heldProof = Get-VtBundleOutputDirectoryHandleProof -Handle $HeldHandle
    if ([string]$heldProof.Identity -cne $ExpectedIdentity -or
        ($heldProof.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
        ($heldProof.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bundle output directory handle changed identity or type during byte capture: $Path"
    }

    $currentHandle = Open-VtBundleOutputDirectoryIdentityHandle -Path $Path
    try { $currentProof = Get-VtBundleOutputDirectoryHandleProof -Handle $currentHandle }
    finally { $currentHandle.Dispose() }
    if ([string]$currentProof.Identity -cne $ExpectedIdentity -or
        ($currentProof.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
        ($currentProof.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bundle output directory path changed identity or type during byte capture: $Path"
    }
}

function Assert-VtBundleOutputCanonicalLeafName {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Context
    )

    if ([string]::IsNullOrEmpty($Name) -or
        [System.IO.Path]::IsPathRooted($Name) -or
        [System.IO.Path]::GetFileName($Name) -cne $Name -or
        $Name -in @('.', '..') -or
        $Name -cne $Name.TrimEnd(' ', '.') -or
        $Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw "$Context must be one canonical Windows leaf filename: '$Name'."
    }

    $stem = [System.IO.Path]::GetFileNameWithoutExtension($Name).ToUpperInvariant()
    if ($stem -in @('CON', 'PRN', 'AUX', 'NUL') -or $stem -match '^(COM|LPT)[1-9]$') {
        throw "$Context uses a reserved Windows device filename: '$Name'."
    }
}

function Get-VtBundleOutputObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if (-not $InputObject.Contains($Name)) {
            throw "Bundle output record is missing required property '$Name'."
        }
        return $InputObject[$Name]
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Bundle output record is missing required property '$Name'."
    }
    return $property.Value
}

function Test-VtBundleOutputObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject.Contains($Name)
    }
    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function Get-VtBundleOutputFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
}

function Test-VtBundleOutputPathEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    return [string]::Equals(
        (Get-VtBundleOutputFullPath -Path $Left),
        (Get-VtBundleOutputFullPath -Path $Right),
        [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-VtBundleOutputExpectedNames {
    param(
        [Parameter(Mandatory = $true)][string]$ExpectedDescriptorName,
        [Parameter(Mandatory = $true)][string]$ExpectedRootBundle
    )

    Assert-VtBundleOutputCanonicalLeafName `
        -Name $ExpectedDescriptorName `
        -Context 'Expected descriptor name'
    Assert-VtBundleOutputCanonicalLeafName `
        -Name $ExpectedRootBundle `
        -Context 'Expected root bundle'

    if ([string]::IsNullOrWhiteSpace($ExpectedDescriptorName) -or
        $ExpectedDescriptorName -cnotmatch '^.+\.mod$') {
        throw "Expected descriptor name must be one exact .mod leaf filename: '$ExpectedDescriptorName'."
    }
    if ($ExpectedRootBundle -cnotmatch '^[0-9a-f]{16}\.mod_bundle$' -or
        [System.IO.Path]::GetFileName($ExpectedRootBundle) -cne $ExpectedRootBundle) {
        throw "Expected root bundle must be one exact lowercase bundle leaf filename: '$ExpectedRootBundle'."
    }
}

function ConvertTo-VtBundleOutputLength {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $length = 0L
    $text = [System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)
    if (-not [long]::TryParse(
            $text,
            [System.Globalization.NumberStyles]::None,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$length) -or $length -lt 0) {
        throw "Bundle output '$Name' has an invalid non-negative byte length: '$text'."
    }
    return $length
}

function Get-VtBundleOutputSha256FromStream {
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        $bytes = $algorithm.ComputeHash($Stream)
        return ([System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant())
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-VtBundleOutputBytesFromStream {
    param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)

    $length = [long]$Stream.Length
    if ($length -lt 0 -or $length -gt [int]::MaxValue) {
        throw "Bundle output byte capture does not support a single file length of $length bytes."
    }

    $bytes = [byte[]]::new([int]$length)
    $Stream.Position = 0
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -le 0) {
            throw "Bundle output stream ended after $offset of $length expected bytes."
        }
        $offset += $read
    }
    if ([long]$Stream.Length -ne $length) {
        throw 'Bundle output stream length changed during byte capture.'
    }
    return ,$bytes
}

function Get-VtBundleOutputSha256FromBytes {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant())
    }
    finally {
        $algorithm.Dispose()
    }
}

function New-VtBundleOutputFingerprint {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append((Get-VtBundleOutputSetAlgorithm))
    [void]$builder.Append("`n")
    foreach ($record in @($Records)) {
        [void]$builder.Append([string]$record.Name)
        [void]$builder.Append([char]0)
        [void]$builder.Append(([long]$record.Length).ToString([System.Globalization.CultureInfo]::InvariantCulture))
        [void]$builder.Append([char]0)
        [void]$builder.Append([string]$record.Sha256)
        [void]$builder.Append("`n")
    }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes($builder.ToString())
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant())
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-VtBundleOutputFileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ([System.IO.Path]::GetFileName($Name) -cne $Name) {
        throw "Bundle output record name must be a leaf filename: '$Name'."
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ([string]$item.Name -cne $Name) {
        throw "Bundle output record name '$Name' does not exactly match path leaf '$($item.Name)'."
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bundle output refuses a reparse-point file: $Path"
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
        throw "Bundle output record is not a file: $Path"
    }

    $stream = [System.IO.File]::Open(
        $item.FullName,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    try {
        $current = Get-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($current.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
            throw "Bundle output file changed type while it was opened: $($item.FullName)"
        }
        $length = [long]$stream.Length
        $sha256 = Get-VtBundleOutputSha256FromStream -Stream $stream
        return [pscustomobject][ordered]@{
            Name = $Name
            Length = $length
            Sha256 = $sha256
        }
    }
    finally {
        $stream.Dispose()
    }
}

function New-VtBundleOutputSet {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$ExpectedDescriptorName,
        [Parameter(Mandatory = $true)][string]$ExpectedRootBundle,
        [string]$ExpectedDescriptorSha256
    )

    Assert-VtBundleOutputExpectedNames `
        -ExpectedDescriptorName $ExpectedDescriptorName `
        -ExpectedRootBundle $ExpectedRootBundle

    if ($PSBoundParameters.ContainsKey('ExpectedDescriptorSha256') -and
        $ExpectedDescriptorSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Expected descriptor SHA-256 must be exactly 64 lowercase hexadecimal characters.'
    }

    $byName = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::Ordinal)
    $byNameIgnoreCase = [System.Collections.Generic.Dictionary[string,string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($inputRecord in @($Records)) {
        if ($null -eq $inputRecord) {
            throw 'Bundle output records cannot contain null entries.'
        }

        $name = [string](Get-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'Name')
        Assert-VtBundleOutputCanonicalLeafName -Name $name -Context 'Bundle output name'
        if ($byName.ContainsKey($name)) {
            throw "Bundle output contains a duplicate exact filename: '$name'."
        }
        if ($byNameIgnoreCase.ContainsKey($name)) {
            throw ("Bundle output contains case-colliding filenames: '{0}' and '{1}'." -f
                $byNameIgnoreCase[$name], $name)
        }

        $lengthValue = Get-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'Length'
        $length = ConvertTo-VtBundleOutputLength -Value $lengthValue -Name $name
        $sha256 = [string](Get-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'Sha256')
        if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Bundle output '$name' SHA-256 must be exactly 64 lowercase hexadecimal characters."
        }

        if ($name -cne $ExpectedDescriptorName -and
            $name -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') {
            throw "Bundle output contains an unexpected filename: '$name'."
        }

        $record = [pscustomobject][ordered]@{
            Name = $name
            Length = [long]$length
            Sha256 = $sha256
        }
        $byName.Add($name, $record)
        $byNameIgnoreCase.Add($name, $name)
    }

    if (-not $byName.ContainsKey($ExpectedDescriptorName)) {
        throw "Bundle output is missing its exact descriptor: '$ExpectedDescriptorName'."
    }
    if (-not $byName.ContainsKey($ExpectedRootBundle)) {
        throw "Bundle output is missing its declared root bundle: '$ExpectedRootBundle'."
    }

    $descriptor = $byName[$ExpectedDescriptorName]
    if ($PSBoundParameters.ContainsKey('ExpectedDescriptorSha256') -and
        $descriptor.Sha256 -cne $ExpectedDescriptorSha256) {
        throw ("Bundle output descriptor SHA-256 mismatch for '{0}': expected {1}, got {2}." -f
            $ExpectedDescriptorName, $ExpectedDescriptorSha256, $descriptor.Sha256)
    }

    [string[]]$names = @($byName.Keys)
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    $orderedRecords = @()
    foreach ($name in $names) { $orderedRecords += $byName[$name] }

    return [pscustomobject][ordered]@{
        Algorithm = Get-VtBundleOutputSetAlgorithm
        Fingerprint = New-VtBundleOutputFingerprint -Records $orderedRecords
        Files = @($orderedRecords)
        Root = $byName[$ExpectedRootBundle]
        Descriptor = $descriptor
    }
}

function Get-VtBundleDirectorySnapshot {
    param(
        [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$DirectoryInfo,
        [object]$HeldHandles
    )

    $records = @()
    $byName = [System.Collections.Generic.Dictionary[string,bool]]::new(
        [System.StringComparer]::Ordinal)
    $byNameIgnoreCase = [System.Collections.Generic.Dictionary[string,string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($item in @($DirectoryInfo.EnumerateFileSystemInfos())) {
        $name = [string]$item.Name
        if ($byName.ContainsKey($name)) {
            throw "Bundle output directory contains a duplicate exact filename: '$name'."
        }
        if ($byNameIgnoreCase.ContainsKey($name)) {
            throw ("Bundle output directory contains case-colliding entries: '{0}' and '{1}'." -f
                $byNameIgnoreCase[$name], $name)
        }
        $byName.Add($name, $true)
        $byNameIgnoreCase.Add($name, $name)

        $isDirectory = (($item.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0)
        $isReparsePoint = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        $identity = $null
        if (-not $isDirectory -and -not $isReparsePoint) {
            $identityStream = if ($null -ne $HeldHandles) {
                Open-VtBundleOutputReadHandle -Path $item.FullName
            } else {
                Open-VtBundleOutputIdentityHandle -Path $item.FullName
            }
            try {
                $identity = Get-VtBundleOutputHandleProof -Stream $identityStream
                if ($null -ne $HeldHandles) {
                    $HeldHandles.Add([pscustomobject]@{
                        Name = $name
                        Path = [string]$item.FullName
                        Stream = $identityStream
                        Identity = [string]$identity.Identity
                        Length = [long]$identity.Length
                    })
                    $identityStream = $null
                }
            }
            finally {
                if ($null -ne $identityStream) { $identityStream.Dispose() }
            }
        }
        $records += [pscustomobject][ordered]@{
            Name = $name
            Kind = if ($isDirectory) { 'directory' } else { 'file' }
            IsReparsePoint = $isReparsePoint
            FullName = [string]$item.FullName
            Identity = if ($null -ne $identity) { [string]$identity.Identity } else { '' }
            Length = if ($null -ne $identity) { [long]$identity.Length } else { [long]-1 }
        }
    }

    return @($records)
}

function Assert-VtBundleDirectorySnapshotFiles {
    param(
        [Parameter(Mandatory = $true)][object[]]$Snapshot,
        [Parameter(Mandatory = $true)][string]$BundleDirectory,
        [string]$ExpectedDescriptorName
    )

    foreach ($entry in @($Snapshot)) {
        if ([bool]$entry.IsReparsePoint) {
            throw "Bundle output directory contains a reparse-point entry: '$($entry.Name)'."
        }
        if ([string]$entry.Kind -cne 'file') {
            throw "Bundle output directory contains a directory instead of an immediate file: '$($entry.Name)'."
        }
        $fullPath = Get-VtBundleOutputFullPath -Path ([string]$entry.FullName)
        $parent = [System.IO.Path]::GetDirectoryName($fullPath)
        if (-not (Test-VtBundleOutputPathEqual -Left $parent -Right $BundleDirectory)) {
            throw "Bundle output entry escaped its directory: '$($entry.Name)'."
        }
        if ([System.IO.Path]::GetFileName($fullPath) -cne [string]$entry.Name) {
            throw "Bundle output entry name does not match its direct path: '$($entry.Name)'."
        }
        if ($PSBoundParameters.ContainsKey('ExpectedDescriptorName') -and
            [string]$entry.Name -cne $ExpectedDescriptorName -and
            [string]$entry.Name -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') {
            throw "Bundle output contains an unexpected filename: '$($entry.Name)'."
        }
    }
}

function Compare-VtBundleDirectorySnapshots {
    param(
        [Parameter(Mandatory = $true)][object[]]$Before,
        [Parameter(Mandatory = $true)][object[]]$After
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $beforeMap = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::Ordinal)
    $afterMap = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::Ordinal)

    foreach ($entry in @($Before)) {
        $name = [string]$entry.Name
        if ($beforeMap.ContainsKey($name)) {
            $errors.Add("duplicate entry in first directory snapshot: '$name'")
        } else {
            $beforeMap.Add($name, $entry)
        }
    }
    foreach ($entry in @($After)) {
        $name = [string]$entry.Name
        if ($afterMap.ContainsKey($name)) {
            $errors.Add("duplicate entry in second directory snapshot: '$name'")
        } else {
            $afterMap.Add($name, $entry)
        }
    }

    [string[]]$beforeNames = @($beforeMap.Keys)
    [System.Array]::Sort($beforeNames, [System.StringComparer]::Ordinal)
    foreach ($name in $beforeNames) {
        if (-not $afterMap.ContainsKey($name)) {
            $errors.Add("entry disappeared during enumeration: '$name'")
            continue
        }
        $left = $beforeMap[$name]
        $right = $afterMap[$name]
        if ([string]$left.Kind -cne [string]$right.Kind -or
            [bool]$left.IsReparsePoint -ne [bool]$right.IsReparsePoint) {
            $errors.Add("entry changed type during enumeration: '$name'")
            continue
        }
        if ([string]$left.Kind -ceq 'file' -and
            ([string]$left.Identity -cne [string]$right.Identity -or
             [long]$left.Length -ne [long]$right.Length)) {
            $errors.Add("entry changed file identity or length during enumeration: '$name'")
        }
    }

    [string[]]$afterNames = @($afterMap.Keys)
    [System.Array]::Sort($afterNames, [System.StringComparer]::Ordinal)
    foreach ($name in $afterNames) {
        if (-not $beforeMap.ContainsKey($name)) {
            $errors.Add("entry appeared during enumeration: '$name'")
        }
    }

    return @($errors)
}

function Open-VtBundleOutputReadHandle {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
}

function Open-VtBundleOutputIdentityHandle {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
}

function Get-VtBundleOutputSet {
    param(
        [Parameter(Mandatory = $true)][string]$BundleDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedDescriptorName,
        [Parameter(Mandatory = $true)][string]$ExpectedRootBundle,
        [string]$ExpectedDescriptorSha256,
        [scriptblock]$BeforeOpenTestHook,
        [scriptblock]$BeforeSecondSnapshotTestHook
    )

    Assert-VtBundleOutputExpectedNames `
        -ExpectedDescriptorName $ExpectedDescriptorName `
        -ExpectedRootBundle $ExpectedRootBundle

    $directoryItem = Get-Item -LiteralPath $BundleDirectory -Force -ErrorAction Stop
    if (($directoryItem.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
        throw "Bundle output path is not a directory: $BundleDirectory"
    }
    if (($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bundle output refuses a reparse-point directory: $BundleDirectory"
    }
    $bundleFullPath = Get-VtBundleOutputFullPath -Path $directoryItem.FullName

    $handles = New-Object 'System.Collections.Generic.List[object]'
    try {
        # Acquire every restrictive read handle as the first directory snapshot
        # is created. Those handles deny writes, deletes, renames, and replacement
        # until the complete set has been hashed and the final path snapshot has
        # been reconciled.
        $before = @(Get-VtBundleDirectorySnapshot `
            -DirectoryInfo $directoryItem `
            -HeldHandles $handles)
        Assert-VtBundleDirectorySnapshotFiles -Snapshot $before `
            -BundleDirectory $bundleFullPath `
            -ExpectedDescriptorName $ExpectedDescriptorName

        if ($null -ne $BeforeOpenTestHook) {
            try {
                & $BeforeOpenTestHook $bundleFullPath @($before)
            }
            catch {
                throw "Bundle output mutation attempt failed closed while held handles were open: $($_.Exception.Message)"
            }
        }

        $records = @()
        foreach ($handle in $handles) {
            $length = [long]$handle.Stream.Length
            $sha256 = Get-VtBundleOutputSha256FromStream -Stream $handle.Stream
            $records += [pscustomobject][ordered]@{
                Name = [string]$handle.Name
                Length = $length
                Sha256 = $sha256
            }
        }

        if ($null -ne $BeforeSecondSnapshotTestHook) {
            & $BeforeSecondSnapshotTestHook $bundleFullPath @($records)
        }

        $directoryItem.Refresh()
        if (-not $directoryItem.Exists -or
            ($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Bundle output directory changed type during enumeration: $BundleDirectory"
        }

        $afterDirectory = Get-Item -LiteralPath $bundleFullPath -Force -ErrorAction Stop
        $after = @(Get-VtBundleDirectorySnapshot -DirectoryInfo $afterDirectory)
        Assert-VtBundleDirectorySnapshotFiles -Snapshot $after `
            -BundleDirectory $bundleFullPath `
            -ExpectedDescriptorName $ExpectedDescriptorName
        $snapshotErrors = @(Compare-VtBundleDirectorySnapshots -Before $before -After $after)
        if ($snapshotErrors.Count -gt 0) {
            throw "Bundle output directory changed during enumeration: $($snapshotErrors -join '; ')"
        }

        foreach ($handle in $handles) {
            $current = Get-Item -LiteralPath ([string]$handle.Path) -Force -ErrorAction Stop
            $currentStream = Open-VtBundleOutputIdentityHandle -Path ([string]$handle.Path)
            try { $currentProof = Get-VtBundleOutputHandleProof -Stream $currentStream }
            finally { $currentStream.Dispose() }
            if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($current.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
                [long]$current.Length -ne [long]$handle.Stream.Length -or
                [string]$currentProof.Identity -cne [string]$handle.Identity -or
                [long]$currentProof.Length -ne [long]$handle.Length) {
                throw "Bundle output entry changed after hashing: '$($handle.Name)'."
            }
        }

        $setArguments = @{
            Records = $records
            ExpectedDescriptorName = $ExpectedDescriptorName
            ExpectedRootBundle = $ExpectedRootBundle
        }
        if ($PSBoundParameters.ContainsKey('ExpectedDescriptorSha256')) {
            $setArguments.ExpectedDescriptorSha256 = $ExpectedDescriptorSha256
        }
        return New-VtBundleOutputSet @setArguments
    }
    finally {
        foreach ($handle in $handles) {
            if ($null -ne $handle.Stream) { $handle.Stream.Dispose() }
        }
    }
}

function Get-VtBundleOutputByteSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$BundleDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedDescriptorName,
        [Parameter(Mandatory = $true)][string]$ExpectedRootBundle,
        [string]$ExpectedDescriptorSha256,
        [scriptblock]$BeforeOpenTestHook,
        [scriptblock]$BeforeSecondSnapshotTestHook
    )

    Assert-VtBundleOutputExpectedNames `
        -ExpectedDescriptorName $ExpectedDescriptorName `
        -ExpectedRootBundle $ExpectedRootBundle

    $directoryItem = Get-Item -LiteralPath $BundleDirectory -Force -ErrorAction Stop
    if (($directoryItem.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
        throw "Bundle output path is not a directory: $BundleDirectory"
    }
    if (($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Bundle output refuses a reparse-point directory: $BundleDirectory"
    }
    $bundleFullPath = Get-VtBundleOutputFullPath -Path $directoryItem.FullName

    $directoryHandle = $null
    $handles = New-Object 'System.Collections.Generic.List[object]'
    try {
        # Bind the directory itself, then acquire every restrictive file handle
        # during the first snapshot. File handles deny writes, deletes, renames,
        # and replacements until all bytes and both path snapshots are proven.
        $directoryHandle = Open-VtBundleOutputDirectoryIdentityHandle -Path $bundleFullPath
        $directoryProof = Get-VtBundleOutputDirectoryHandleProof -Handle $directoryHandle
        if (($directoryProof.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
            ($directoryProof.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Bundle output directory changed type before byte capture: $BundleDirectory"
        }
        $directoryIdentity = [string]$directoryProof.Identity
        Assert-VtBundleOutputDirectoryIdentity `
            -Path $bundleFullPath `
            -HeldHandle $directoryHandle `
            -ExpectedIdentity $directoryIdentity

        $before = @(Get-VtBundleDirectorySnapshot `
            -DirectoryInfo $directoryItem `
            -HeldHandles $handles)
        Assert-VtBundleDirectorySnapshotFiles -Snapshot $before `
            -BundleDirectory $bundleFullPath `
            -ExpectedDescriptorName $ExpectedDescriptorName
        Assert-VtBundleOutputDirectoryIdentity `
            -Path $bundleFullPath `
            -HeldHandle $directoryHandle `
            -ExpectedIdentity $directoryIdentity

        if ($null -ne $BeforeOpenTestHook) {
            try {
                & $BeforeOpenTestHook $bundleFullPath @($before)
            }
            catch {
                throw "Bundle output mutation attempt failed closed while held handles were open: $($_.Exception.Message)"
            }
        }

        $capturedByName = [System.Collections.Generic.Dictionary[string,object]]::new(
            [System.StringComparer]::Ordinal)
        $setRecords = @()
        foreach ($handle in $handles) {
            $bytes = [byte[]](Get-VtBundleOutputBytesFromStream -Stream $handle.Stream)
            $length = [long]$bytes.LongLength
            $heldProof = Get-VtBundleOutputHandleProof -Stream $handle.Stream
            if ($length -ne [long]$handle.Length -or
                [long]$heldProof.Length -ne [long]$handle.Length -or
                [string]$heldProof.Identity -cne [string]$handle.Identity) {
                throw "Bundle output entry changed during byte capture: '$($handle.Name)'."
            }
            $sha256 = Get-VtBundleOutputSha256FromBytes -Bytes $bytes
            $capture = [pscustomobject][ordered]@{
                Name = [string]$handle.Name
                Length = $length
                Sha256 = $sha256
                Bytes = $bytes
            }
            $capturedByName.Add([string]$handle.Name, $capture)
            $setRecords += [pscustomobject][ordered]@{
                Name = [string]$handle.Name
                Length = $length
                Sha256 = $sha256
            }
        }

        if ($null -ne $BeforeSecondSnapshotTestHook) {
            & $BeforeSecondSnapshotTestHook $bundleFullPath @($setRecords)
        }

        # Build the detached return object before the final disk revalidation so
        # the last successful operations before handle release are identity and
        # complete-directory checks, not additional byte transformations.
        $setArguments = @{
            Records = $setRecords
            ExpectedDescriptorName = $ExpectedDescriptorName
            ExpectedRootBundle = $ExpectedRootBundle
        }
        if ($PSBoundParameters.ContainsKey('ExpectedDescriptorSha256')) {
            $setArguments.ExpectedDescriptorSha256 = $ExpectedDescriptorSha256
        }
        $outputSet = New-VtBundleOutputSet @setArguments

        $files = @()
        $seenByteArrays = [System.Collections.Generic.HashSet[object]]::new()
        foreach ($setRecord in @($outputSet.Files)) {
            $name = [string]$setRecord.Name
            if (-not $capturedByName.ContainsKey($name)) {
                throw "Bundle output byte capture lost canonical record '$name'."
            }
            $capture = $capturedByName[$name]
            if ([long]$capture.Length -ne [long]$setRecord.Length -or
                [string]$capture.Sha256 -cne [string]$setRecord.Sha256) {
                throw "Bundle output byte capture disagrees with canonical record '$name'."
            }
            if (-not $seenByteArrays.Add([object]$capture.Bytes)) {
                throw "Bundle output byte capture reused a byte array for '$name'."
            }
            $files += [pscustomobject][ordered]@{
                Name = $name
                Length = [long]$capture.Length
                Sha256 = [string]$capture.Sha256
                Bytes = [byte[]]$capture.Bytes
            }
        }
        $result = [pscustomobject][ordered]@{
            OutputSet = $outputSet
            Files = @($files)
        }

        $directoryItem.Refresh()
        if (-not $directoryItem.Exists -or
            ($directoryItem.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
            ($directoryItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Bundle output directory changed type during byte capture: $BundleDirectory"
        }

        foreach ($handle in $handles) {
            $heldProof = Get-VtBundleOutputHandleProof -Stream $handle.Stream
            $current = Get-Item -LiteralPath ([string]$handle.Path) -Force -ErrorAction Stop
            $currentStream = Open-VtBundleOutputIdentityHandle -Path ([string]$handle.Path)
            try { $currentProof = Get-VtBundleOutputHandleProof -Stream $currentStream }
            finally { $currentStream.Dispose() }
            $currentParent = [System.IO.Path]::GetDirectoryName(
                (Get-VtBundleOutputFullPath -Path ([string]$current.FullName)))
            if (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                ($current.Attributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
                [string]$current.Name -cne [string]$handle.Name -or
                -not (Test-VtBundleOutputPathEqual -Left $currentParent -Right $bundleFullPath) -or
                [long]$current.Length -ne [long]$handle.Length -or
                [string]$heldProof.Identity -cne [string]$handle.Identity -or
                [long]$heldProof.Length -ne [long]$handle.Length -or
                [string]$currentProof.Identity -cne [string]$handle.Identity -or
                [long]$currentProof.Length -ne [long]$handle.Length) {
                throw "Bundle output entry changed after byte capture: '$($handle.Name)'."
            }
        }

        $afterDirectory = Get-Item -LiteralPath $bundleFullPath -Force -ErrorAction Stop
        $after = @(Get-VtBundleDirectorySnapshot -DirectoryInfo $afterDirectory)
        Assert-VtBundleDirectorySnapshotFiles -Snapshot $after `
            -BundleDirectory $bundleFullPath `
            -ExpectedDescriptorName $ExpectedDescriptorName
        $snapshotErrors = @(Compare-VtBundleDirectorySnapshots -Before $before -After $after)
        if ($snapshotErrors.Count -gt 0) {
            throw "Bundle output directory changed during byte capture: $($snapshotErrors -join '; ')"
        }
        Assert-VtBundleOutputDirectoryIdentity `
            -Path $bundleFullPath `
            -HeldHandle $directoryHandle `
            -ExpectedIdentity $directoryIdentity
        return $result
    }
    finally {
        foreach ($handle in $handles) {
            if ($null -ne $handle.Stream) { $handle.Stream.Dispose() }
        }
        if ($null -ne $directoryHandle) { $directoryHandle.Dispose() }
    }
}

function ConvertTo-VtBundleComparableRecords {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][bool]$RequireLength
    )

    if (Test-VtBundleOutputObjectProperty -InputObject $Value -Name 'Files') {
        $inputRecords = @((Get-VtBundleOutputObjectProperty -InputObject $Value -Name 'Files'))
    } else {
        $inputRecords = @($Value)
    }

    $records = @()
    $byName = [System.Collections.Generic.Dictionary[string,bool]]::new(
        [System.StringComparer]::Ordinal)
    $byNameIgnoreCase = [System.Collections.Generic.Dictionary[string,string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($inputRecord in $inputRecords) {
        if ($null -eq $inputRecord) { throw 'comparable records cannot contain null entries' }
        $nameProperty = if (Test-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'Name') {
            'Name'
        } elseif (Test-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'filename') {
            'filename'
        } else {
            throw 'comparable record is missing Name or filename'
        }
        $name = [string](Get-VtBundleOutputObjectProperty -InputObject $inputRecord -Name $nameProperty)
        if ([string]::IsNullOrEmpty($name)) { throw 'comparable record has an empty filename' }
        if ($byName.ContainsKey($name)) { throw "duplicate comparable filename: '$name'" }
        if ($byNameIgnoreCase.ContainsKey($name)) {
            throw ("case-colliding comparable filenames: '{0}' and '{1}'" -f
                $byNameIgnoreCase[$name], $name)
        }
        $byName.Add($name, $true)
        $byNameIgnoreCase.Add($name, $name)

        $shaProperty = if (Test-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'Sha256') {
            'Sha256'
        } elseif (Test-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'sha256') {
            'sha256'
        } else {
            throw "comparable record '$name' is missing Sha256 or sha256"
        }
        $sha256 = [string](Get-VtBundleOutputObjectProperty -InputObject $inputRecord -Name $shaProperty)
        if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "comparable record '$name' has an invalid lowercase SHA-256"
        }

        $length = $null
        if ($RequireLength) {
            if (-not (Test-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'Length')) {
                throw "comparable record '$name' is missing Length"
            }
            $length = ConvertTo-VtBundleOutputLength `
                -Value (Get-VtBundleOutputObjectProperty -InputObject $inputRecord -Name 'Length') `
                -Name $name
        }

        $records += [pscustomobject][ordered]@{
            Name = $name
            Length = $length
            Sha256 = $sha256
        }
    }
    return @($records)
}

function Compare-VtBundleOutputSets {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual,
        [string]$ExpectedLabel = 'expected bundle output',
        [string]$ActualLabel = 'actual bundle output',
        [bool]$RequireLength = $true
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    try {
        $expectedRecords = @(ConvertTo-VtBundleComparableRecords -Value $Expected -RequireLength $RequireLength)
    } catch {
        $errors.Add("${ExpectedLabel} is invalid: $($_.Exception.Message)")
        return @($errors)
    }
    try {
        $actualRecords = @(ConvertTo-VtBundleComparableRecords -Value $Actual -RequireLength $RequireLength)
    } catch {
        $errors.Add("${ActualLabel} is invalid: $($_.Exception.Message)")
        return @($errors)
    }

    $expectedMap = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::Ordinal)
    $actualMap = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($record in $expectedRecords) { $expectedMap.Add([string]$record.Name, $record) }
    foreach ($record in $actualRecords) { $actualMap.Add([string]$record.Name, $record) }

    [string[]]$expectedNames = @($expectedMap.Keys)
    [System.Array]::Sort($expectedNames, [System.StringComparer]::Ordinal)
    foreach ($name in $expectedNames) {
        if (-not $actualMap.ContainsKey($name)) {
            $errors.Add("${ActualLabel} is missing '$name' from ${ExpectedLabel}")
            continue
        }
        $expectedRecord = $expectedMap[$name]
        $actualRecord = $actualMap[$name]
        if ([string]$expectedRecord.Sha256 -cne [string]$actualRecord.Sha256) {
            $errors.Add("${ActualLabel} has changed SHA-256 bytes for '$name'")
        }
        if ($RequireLength -and [long]$expectedRecord.Length -ne [long]$actualRecord.Length) {
            $errors.Add("${ActualLabel} has changed byte length for '$name'")
        }
    }

    [string[]]$actualNames = @($actualMap.Keys)
    [System.Array]::Sort($actualNames, [System.StringComparer]::Ordinal)
    foreach ($name in $actualNames) {
        if (-not $expectedMap.ContainsKey($name)) {
            $errors.Add("${ActualLabel} contains unexpected '$name' not present in ${ExpectedLabel}")
        }
    }

    return @($errors)
}

function ConvertTo-VtBundleManifestRecords {
    param([Parameter(Mandatory = $true)]$OutputSet)

    if (-not (Test-VtBundleOutputObjectProperty -InputObject $OutputSet -Name 'Files')) {
        throw 'Bundle manifest projection requires an output set with Files.'
    }
    $records = @(ConvertTo-VtBundleComparableRecords -Value $OutputSet -RequireLength $true)
    if ($records.Count -eq 0) {
        throw 'Bundle manifest projection refuses an empty output set.'
    }
    [string[]]$names = @($records | ForEach-Object { [string]$_.Name })
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    $byName = [System.Collections.Generic.Dictionary[string,object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($record in $records) { $byName.Add([string]$record.Name, $record) }

    return @($names | ForEach-Object {
        [pscustomobject][ordered]@{
            filename = [string]$byName[$_].Name
            sha256 = [string]$byName[$_].Sha256
        }
    })
}
