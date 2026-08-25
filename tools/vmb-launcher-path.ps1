# Shared VMBLauncher dependency resolution for ship and release publishing.
#
# Issue #683: a clean linked worktree may intentionally use launcher bytes
# from the configured or primary checkout. Every pipeline phase must resolve
# the same bounded candidate set and must reject a caller-supplied path/source
# pair that does not describe one of those approved machine-local locations.

function Test-VmbLauncherPathEqual {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
    $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
    return [string]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Initialize-VmbLauncherLeaseNativeMethods {
    if ('VmbLauncherLease.NativeMethods' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace VmbLauncherLease
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
        public static extern uint GetFinalPathNameByHandle(
            SafeFileHandle file,
            StringBuilder path,
            uint pathLength,
            uint flags);
    }
}
'@
}

function ConvertFrom-VmbLauncherNativePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path.StartsWith('\\?\UNC\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $Path.Substring(8)
    }
    if ($Path.StartsWith('\\?\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(4)
    }
    return $Path
}

function Get-VmbLauncherHandleIdentity {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)

    Initialize-VmbLauncherLeaseNativeMethods
    $information = New-Object VmbLauncherLease.ByHandleFileInformation
    if (-not [VmbLauncherLease.NativeMethods]::GetFileInformationByHandle(
            $Stream.SafeFileHandle,
            [ref]$information)) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw New-Object System.ComponentModel.Win32Exception(
            $code, 'Unable to query VMBLauncher file identity from its live handle.')
    }

    $capacity = 1024
    while ($true) {
        $builder = New-Object System.Text.StringBuilder $capacity
        $length = [VmbLauncherLease.NativeMethods]::GetFinalPathNameByHandle(
            $Stream.SafeFileHandle, $builder, [uint32]$builder.Capacity, 0)
        if ($length -eq 0) {
            $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw New-Object System.ComponentModel.Win32Exception(
                $code, 'Unable to resolve VMBLauncher canonical path from its live handle.')
        }
        if ($length -lt $builder.Capacity) { break }
        $capacity = [int]$length + 1
    }

    $byteLength = ([uint64]$information.FileSizeHigh * [uint64]4294967296) +
        [uint64]$information.FileSizeLow
    return [pscustomobject][ordered]@{
        canonical_path = [System.IO.Path]::GetFullPath(
            (ConvertFrom-VmbLauncherNativePath -Path $builder.ToString()))
        file_id = ('{0:x8}:{1:x8}{2:x8}' -f
            $information.VolumeSerialNumber,
            $information.FileIndexHigh,
            $information.FileIndexLow)
        length = [long]$byteLength
    }
}

function Get-VmbLauncherStreamSha256 {
    param([Parameter(Mandatory = $true)][System.IO.FileStream]$Stream)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        return ([System.BitConverter]::ToString($sha.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-VmbLauncherPathIdentity {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
    try { return Get-VmbLauncherHandleIdentity -Stream $stream }
    finally { $stream.Dispose() }
}

function Enter-VmbLauncherExecutableLease {
    param(
        [Parameter(Mandatory = $true)][string]$LauncherPath,
        [switch]$RequireDirectPath
    )

    Assert-VmbLauncherFile -Path $LauncherPath -Context 'VMBLauncher executable lease'
    if ($RequireDirectPath) {
        $null = Assert-VmbLauncherDirectPath -Path $LauncherPath -Context 'VMBLauncher executable lease'
    }
    $requested = [System.IO.Path]::GetFullPath($LauncherPath)
    $stream = [System.IO.File]::Open(
        $requested,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    try {
        $identityBefore = Get-VmbLauncherHandleIdentity -Stream $stream
        $sha256 = Get-VmbLauncherStreamSha256 -Stream $stream
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($identityBefore.canonical_path)
        $version = "$($info.ProductVersion)".Trim()
        if (-not $version) { $version = "$($info.FileVersion)".Trim() }
        if (-not $version) {
            throw "VMBLauncher at $requested has no ProductVersion or FileVersion metadata."
        }
        $identityAfter = Get-VmbLauncherHandleIdentity -Stream $stream
        if ($identityBefore.file_id -cne $identityAfter.file_id -or
            $identityBefore.length -ne $identityAfter.length -or
            -not (Test-VmbLauncherPathEqual $identityBefore.canonical_path $identityAfter.canonical_path)) {
            throw 'VMBLauncher executable identity changed while its lease proof was captured.'
        }
        $pathIdentity = Get-VmbLauncherPathIdentity -Path $requested
        if ($pathIdentity.file_id -cne $identityBefore.file_id) {
            throw 'VMBLauncher requested path no longer resolves to its held executable handle.'
        }
        if ($RequireDirectPath) {
            $null = Assert-VmbLauncherDirectPath -Path $requested -Context 'VMBLauncher executable lease'
        }

        return [pscustomobject][ordered]@{
            Proof = [pscustomobject][ordered]@{
                schema = 1
                requested_path = $requested
                canonical_path = [string]$identityBefore.canonical_path
                file_id = [string]$identityBefore.file_id
                length = [long]$identityBefore.length
                sha256 = $sha256
                version = $version
            }
            Stream = $stream
            Disposed = $false
        }
    }
    catch {
        $stream.Dispose()
        throw
    }
}

function Assert-VmbLauncherExecutableLease {
    param(
        [Parameter(Mandatory = $true)]$Lease,
        [string]$ExpectedRequestedPath,
        [switch]$VerifyContent
    )

    if ($null -eq $Lease -or $Lease.Disposed -or
        $Lease.Stream -isnot [System.IO.FileStream] -or
        -not $Lease.Stream.CanRead -or $Lease.Stream.SafeFileHandle.IsClosed -or
        $Lease.Stream.SafeFileHandle.IsInvalid) {
        throw 'VMBLauncher executable lease is missing, disposed, or unreadable.'
    }
    $proof = $Lease.Proof
    $allowed = @(
        'schema', 'requested_path', 'canonical_path', 'file_id',
        'length', 'sha256', 'version')
    $present = @($proof.PSObject.Properties | ForEach-Object { [string]$_.Name })
    if ($null -eq $proof -or $present.Count -ne $allowed.Count -or
        @($allowed | Where-Object { $present -cnotcontains $_ }).Count -gt 0 -or
        $proof.schema -isnot [int] -or [int]$proof.schema -ne 1 -or
        $proof.requested_path -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string]$proof.requested_path) -or
        $proof.canonical_path -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string]$proof.canonical_path) -or
        $proof.file_id -isnot [string] -or
        [string]$proof.file_id -cnotmatch '^[0-9a-f]{8}:[0-9a-f]{16}$' -or
        $proof.length -isnot [long] -or [long]$proof.length -le 0 -or
        $proof.sha256 -isnot [string] -or
        [string]$proof.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $proof.version -isnot [string] -or
        [string]::IsNullOrWhiteSpace([string]$proof.version)) {
        throw 'VMBLauncher executable lease proof is malformed or non-canonical.'
    }
    if ($ExpectedRequestedPath -and
        -not (Test-VmbLauncherPathEqual $proof.requested_path $ExpectedRequestedPath)) {
        throw 'VMBLauncher executable lease requested path differs from the approved path.'
    }

    $held = Get-VmbLauncherHandleIdentity -Stream $Lease.Stream
    if ($held.file_id -cne [string]$proof.file_id -or
        $held.length -ne [long]$proof.length -or
        -not (Test-VmbLauncherPathEqual $held.canonical_path $proof.canonical_path)) {
        throw 'VMBLauncher live handle identity differs from its lease proof.'
    }
    foreach ($path in @([string]$proof.requested_path, [string]$proof.canonical_path)) {
        $pathIdentity = Get-VmbLauncherPathIdentity -Path $path
        if ($pathIdentity.file_id -cne [string]$proof.file_id -or
            $pathIdentity.length -ne [long]$proof.length) {
            throw "VMBLauncher path no longer resolves to its leased executable: $path"
        }
    }
    if ($VerifyContent) {
        $actualSha = Get-VmbLauncherStreamSha256 -Stream $Lease.Stream
        $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo([string]$proof.canonical_path)
        $actualVersion = "$($info.ProductVersion)".Trim()
        if (-not $actualVersion) { $actualVersion = "$($info.FileVersion)".Trim() }
        if ($actualSha -cne [string]$proof.sha256 -or
            $actualVersion -cne [string]$proof.version) {
            throw 'VMBLauncher executable content or version differs from its lease proof.'
        }
    }
    return $proof
}

function ConvertTo-VmbLauncherWindowsArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-VmbLauncherProcess {
    param(
        [Parameter(Mandatory = $true)]$Lease,
        [Parameter(Mandatory = $true)][string[]]$ArgumentList,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [switch]$ReplayOutput
    )

    $proofBefore = Assert-VmbLauncherExecutableLease -Lease $Lease -VerifyContent
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = [string]$proofBefore.canonical_path
    $startInfo.Arguments = (($ArgumentList | ForEach-Object {
        ConvertTo-VmbLauncherWindowsArgument -Value ([string]$_)
    }) -join ' ')
    $startInfo.WorkingDirectory = [System.IO.Path]::GetFullPath($WorkingDirectory)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw "Failed to start leased headless VMBLauncher: $($proofBefore.canonical_path)"
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $proofAfter = Assert-VmbLauncherExecutableLease -Lease $Lease -VerifyContent
        $lines = @()
        if (-not [string]::IsNullOrEmpty($stdout)) {
            $lines += @($stdout -split "`r?`n" | Where-Object { $_ -ne '' })
        }
        if (-not [string]::IsNullOrEmpty($stderr)) {
            $lines += @($stderr -split "`r?`n" | Where-Object { $_ -ne '' })
        }
        if ($ReplayOutput) { $lines | ForEach-Object { Write-Host $_ } }
        return [pscustomobject][ordered]@{
            ExitCode = $process.ExitCode
            Lines = @($lines)
            ExecutableProof = $proofAfter
        }
    }
    finally { $process.Dispose() }
}

function Exit-VmbLauncherExecutableLease {
    param($Lease)
    if ($null -eq $Lease -or $Lease.Disposed) { return }
    try {
        if ($Lease.Stream -is [System.IDisposable]) { $Lease.Stream.Dispose() }
    }
    finally { $Lease.Disposed = $true }
}

function Get-VmbLauncherVersion {
    param([Parameter(Mandatory = $true)][string]$LauncherPath)

    $lease = Enter-VmbLauncherExecutableLease -LauncherPath $LauncherPath
    try {
        return [string](Assert-VmbLauncherExecutableLease -Lease $lease -VerifyContent).version
    }
    finally { Exit-VmbLauncherExecutableLease -Lease $lease }
}

function Get-VmbLauncherConfiguredProjectRoot {
    param([string]$SettingsPath)
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return $null }
    try {
        $settings = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        throw "VMBLauncher settings are not valid JSON: $SettingsPath ($($_.Exception.Message))"
    }
    if ($null -eq $settings -or [string]::IsNullOrWhiteSpace([string]$settings.ProjectRoot)) { return $null }
    return [System.IO.Path]::GetFullPath([string]$settings.ProjectRoot)
}

# Return the primary checkout that owns a linked worktree's shared git common
# directory. This root supplies dependencies only; callers remain responsible
# for binding build source to the invoking checkout.
function Get-VmbLauncherPrimaryWorktreeRoot {
    param([string]$RepoRoot)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git -C $RepoRoot rev-parse --path-format=absolute --git-common-dir 2>$null |
            ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0 -or $lines.Count -eq 0) { return $null }
    $common = ([string]$lines[-1]).Trim()
    if ([string]::IsNullOrWhiteSpace($common)) { return $null }
    $common = [System.IO.Path]::GetFullPath($common).TrimEnd('\', '/')
    if ([System.IO.Path]::GetFileName($common) -ine '.git') { return $null }
    $candidate = Split-Path $common -Parent
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { return $null }
    return $candidate
}

function Get-ApprovedVmbLauncherCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$ConfiguredProjectRoot,
        [string]$PrimaryWorktreeRoot,
        [string]$EnvironmentPath
    )

    $relative = 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
    $raw = @()
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentPath)) {
        $raw += [pscustomobject]@{ Path = $EnvironmentPath; Source = 'VT2_SHIP_VMB_LAUNCHER'; ApprovalAnchor = $EnvironmentPath }
    }
    $raw += [pscustomobject]@{ Path = (Join-Path $RepoRoot $relative); Source = 'invoking worktree'; ApprovalAnchor = $RepoRoot }
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredProjectRoot)) {
        $raw += [pscustomobject]@{ Path = (Join-Path $ConfiguredProjectRoot $relative); Source = 'VMBLauncher configured ProjectRoot'; ApprovalAnchor = $ConfiguredProjectRoot }
    }
    if (-not [string]::IsNullOrWhiteSpace($PrimaryWorktreeRoot)) {
        $raw += [pscustomobject]@{ Path = (Join-Path $PrimaryWorktreeRoot $relative); Source = 'primary git worktree'; ApprovalAnchor = $PrimaryWorktreeRoot }
    }

    $seen = @{}
    $result = @()
    foreach ($candidate in $raw) {
        $full = [System.IO.Path]::GetFullPath([string]$candidate.Path)
        $anchor = [System.IO.Path]::GetFullPath([string]$candidate.ApprovalAnchor)
        $key = "$($candidate.Source)|$($full.ToLowerInvariant())|$($anchor.ToLowerInvariant())"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $result += [pscustomobject]@{ Path = $full; Source = [string]$candidate.Source; ApprovalAnchor = $anchor }
    }
    return $result
}

function Assert-VmbLauncherFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Context
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Context points to a missing file: $Path"
    }
    if ((Get-Item -LiteralPath $Path).Length -le 0) {
        throw "$Context points to an empty file: $Path"
    }
}

function Assert-VmbLauncherDirectPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ([string]::IsNullOrWhiteSpace($root)) {
        throw "$Context has no rooted filesystem identity: $full"
    }
    $relative = $full.Substring($root.Length)
    $current = $root
    foreach ($segment in @($relative.Split(
                [char[]]@([char]'\', [char]'/'),
                [System.StringSplitOptions]::RemoveEmptyEntries))) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) {
            throw "$Context path component is missing: $current"
        }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Context refuses a reparse-point path component: $current"
        }
    }
    return $full
}

function Resolve-ApprovedVmbLauncherPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$RequestedPath,
        [string]$RequestedSource,
        [string]$RequestedApprovalAnchor,
        [string]$ConfiguredProjectRoot,
        [string]$PrimaryWorktreeRoot,
        [string]$EnvironmentPath
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath) -and
            (-not [string]::IsNullOrWhiteSpace($RequestedSource) -or
             -not [string]::IsNullOrWhiteSpace($RequestedApprovalAnchor))) {
        throw 'VMBLauncher source/provenance was supplied without a launcher path.'
    }

    $relative = 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'

    # A canonical ship passes the approval snapshot that produced its selected
    # path. Revalidate that immutable handoff instead of rereading the mutable
    # global ProjectRoot, which another concurrent ship may temporarily bind.
    if (-not [string]::IsNullOrWhiteSpace($RequestedApprovalAnchor)) {
        if ([string]::IsNullOrWhiteSpace($RequestedSource)) {
            throw 'VMBLauncher approval anchor was supplied without its source/provenance.'
        }
        $requestedFull = [System.IO.Path]::GetFullPath($RequestedPath)
        $anchorFull = [System.IO.Path]::GetFullPath($RequestedApprovalAnchor)
        $expectedPath = $null
        switch -CaseSensitive ($RequestedSource) {
            'VT2_SHIP_VMB_LAUNCHER' {
                $expectedPath = $anchorFull
            }
            'invoking worktree' {
                if (-not (Test-VmbLauncherPathEqual $anchorFull $RepoRoot)) {
                    throw "VMBLauncher source/provenance mismatch: invoking-worktree anchor '$anchorFull' is not '$RepoRoot'."
                }
                $expectedPath = Join-Path $anchorFull $relative
            }
            'VMBLauncher configured ProjectRoot' {
                if (-not (Test-Path -LiteralPath $anchorFull -PathType Container)) {
                    throw "VMBLauncher configured ProjectRoot approval anchor is missing: $anchorFull"
                }
                $expectedPath = Join-Path $anchorFull $relative
            }
            'primary git worktree' {
                if ([string]::IsNullOrWhiteSpace($PrimaryWorktreeRoot) -or
                        -not (Test-VmbLauncherPathEqual $anchorFull $PrimaryWorktreeRoot)) {
                    throw "VMBLauncher source/provenance mismatch: primary-worktree anchor '$anchorFull' is not '$PrimaryWorktreeRoot'."
                }
                $expectedPath = Join-Path $anchorFull $relative
            }
            default {
                throw "Unknown VMBLauncher source/provenance: '$RequestedSource'."
            }
        }
        if (-not (Test-VmbLauncherPathEqual $requestedFull $expectedPath)) {
            throw ("VMBLauncher source/provenance mismatch: path '$requestedFull' does not match " +
                   "source '$RequestedSource' at approval anchor '$anchorFull'.")
        }
        Assert-VmbLauncherFile -Path $requestedFull -Context 'Requested VMBLauncher path'
        $null = Assert-VmbLauncherDirectPath -Path $requestedFull -Context 'Requested VMBLauncher path'
        return [pscustomobject]@{
            Path = $requestedFull
            Source = $RequestedSource
            ApprovalAnchor = $anchorFull
        }
    }

    $candidates = @(Get-ApprovedVmbLauncherCandidates `
        -RepoRoot $RepoRoot `
        -ConfiguredProjectRoot $ConfiguredProjectRoot `
        -PrimaryWorktreeRoot $PrimaryWorktreeRoot `
        -EnvironmentPath $EnvironmentPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $requestedFull = [System.IO.Path]::GetFullPath($RequestedPath)
        $pathMatches = @($candidates | Where-Object {
            Test-VmbLauncherPathEqual $_.Path $requestedFull
        })
        if ($pathMatches.Count -eq 0) {
            throw ("Requested VMBLauncher path is not an approved machine-local candidate: $requestedFull. " +
                   "Approved candidates: $(@($candidates | ForEach-Object { $_.Path }) -join '; ')")
        }

        $selected = $null
        if (-not [string]::IsNullOrWhiteSpace($RequestedSource)) {
            $selected = @($pathMatches | Where-Object {
                [string]::Equals($_.Source, $RequestedSource, [System.StringComparison]::Ordinal)
            }) | Select-Object -First 1
            if ($null -eq $selected) {
                throw ("VMBLauncher source/provenance mismatch for '$requestedFull': requested " +
                       "'$RequestedSource', approved as $(@($pathMatches | ForEach-Object { $_.Source }) -join ', ').")
            }
        } else {
            $selected = $pathMatches[0]
        }
        Assert-VmbLauncherFile -Path $selected.Path -Context 'Requested VMBLauncher path'
        $null = Assert-VmbLauncherDirectPath -Path $selected.Path -Context 'Requested VMBLauncher path'
        return $selected
    }

    # An environment override is an explicit operator choice. If it is set but
    # invalid, fail instead of silently falling back to another executable.
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentPath)) {
        $environmentCandidate = @($candidates | Where-Object { $_.Source -eq 'VT2_SHIP_VMB_LAUNCHER' }) |
            Select-Object -First 1
        Assert-VmbLauncherFile -Path $environmentCandidate.Path -Context 'VT2_SHIP_VMB_LAUNCHER'
        $null = Assert-VmbLauncherDirectPath -Path $environmentCandidate.Path -Context 'VT2_SHIP_VMB_LAUNCHER'
        return $environmentCandidate
    }

    $attempted = @()
    foreach ($candidate in $candidates) {
        $attempted += $candidate.Path
        if ((Test-Path -LiteralPath $candidate.Path -PathType Leaf) -and
                (Get-Item -LiteralPath $candidate.Path).Length -gt 0) {
            $null = Assert-VmbLauncherDirectPath -Path $candidate.Path -Context 'Approved VMBLauncher path'
            return $candidate
        }
    }
    throw ("VMBLauncher.exe was not found in any approved machine-local location: " +
           ($attempted -join '; ') +
           ". Set VT2_SHIP_VMB_LAUNCHER to the published executable or publish it in the primary/configured worktree.")
}
