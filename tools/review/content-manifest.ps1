[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$BaseCommit,
    [string[]]$Path,
    [string]$PathFile,
    [switch]$ChangedSinceBase,
    [string]$ManifestOut,
    [switch]$DigestOnly,
    [ValidateRange(1, 65536)][int]$MaxEntries = 4096,
    [ValidateRange(1, 1048576)][int]$MaxPathBytes = 4096,
    [ValidateRange(1, 16777216)][long]$MaxTotalPathBytes = 1048576,
    [ValidateRange(1, 16777216)][long]$MaxPathFileBytes = 1048576
)

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'content-manifest.psm1'

function Test-VtExistingPathHasReparseComponent {
    param([Parameter(Mandatory)][string]$FullPath)

    $current = [System.IO.DirectoryInfo]::new($FullPath)
    while ($null -ne $current) {
        if ($current.Exists -and
            (($current.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)) {
            return $true
        }
        $current = $current.Parent
    }
    return $false
}

try {
    Import-Module $modulePath -Force
    $pathModeCount = 0
    if ($null -ne $Path -and $Path.Count -gt 0) { $pathModeCount++ }
    if (-not [string]::IsNullOrEmpty($PathFile)) { $pathModeCount++ }
    if ($ChangedSinceBase) { $pathModeCount++ }
    if ($pathModeCount -ne 1) {
        throw 'Pass exactly one of -Path, -PathFile, or -ChangedSinceBase.'
    }

    $paths = if ($ChangedSinceBase) {
        @(Get-VtChangedContentManifestPaths `
            -RepositoryRoot $RepositoryRoot `
            -BaseCommit $BaseCommit `
            -MaxEntries $MaxEntries `
            -MaxPathBytes $MaxPathBytes `
            -MaxTotalPathBytes $MaxTotalPathBytes)
    } elseif ($PathFile) {
        @(Read-VtContentManifestPathFile `
            -PathFile $PathFile `
            -MaxEntries $MaxEntries `
            -MaxPathBytes $MaxPathBytes `
            -MaxPathFileBytes $MaxPathFileBytes)
    } else {
        @($Path)
    }

    $outputPath = $null
    if ($ManifestOut) {
        $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar)
        $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
        $outputPath = [System.IO.Path]::GetFullPath($ManifestOut)
        $comparison = if ($env:OS -eq 'Windows_NT') {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }
        if ($outputPath.StartsWith($rootPrefix, $comparison) -or
            [string]::Equals($outputPath, $root, $comparison)) {
            throw 'ManifestOut must be outside RepositoryRoot; the tool never modifies the reviewed repository.'
        }
        $outputParent = [System.IO.Path]::GetDirectoryName($outputPath)
        if (-not [System.IO.Directory]::Exists($outputParent)) {
            throw "ManifestOut parent directory does not exist: $outputParent"
        }
        if (Test-VtExistingPathHasReparseComponent -FullPath $outputParent) {
            throw 'ManifestOut must not traverse a reparse point; its physical target cannot be proven outside RepositoryRoot.'
        }
    }

    $result = New-VtContentManifest `
        -RepositoryRoot $RepositoryRoot `
        -BaseCommit $BaseCommit `
        -Paths $paths `
        -MaxEntries $MaxEntries `
        -MaxPathBytes $MaxPathBytes `
        -MaxTotalPathBytes $MaxTotalPathBytes

    if ($DigestOnly) {
        [Console]::Out.WriteLine("aggregate_sha256=$($result.AggregateSha256)")
        if ($result.ReviewerCompatibilitySha256) {
            [Console]::Out.WriteLine("reviewer_compatibility_sha256=$($result.ReviewerCompatibilitySha256)")
        }
        [Console]::Out.WriteLine("entries=$($result.EntryCount)")
        exit 0
    }

    if ($outputPath) {
        $output = New-Object System.IO.FileStream(
            $outputPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None)
        try {
            $output.Write($result.ManifestBytes, 0, $result.ManifestBytes.Length)
            $output.Flush($true)
        } finally {
            $output.Dispose()
        }
        [Console]::Out.WriteLine("aggregate_sha256=$($result.AggregateSha256)")
        if ($result.ReviewerCompatibilitySha256) {
            [Console]::Out.WriteLine("reviewer_compatibility_sha256=$($result.ReviewerCompatibilitySha256)")
        }
        [Console]::Out.WriteLine("entries=$($result.EntryCount)")
        [Console]::Out.WriteLine("manifest=$outputPath")
        exit 0
    }

    [Console]::Error.WriteLine(
        "[content-manifest] aggregate_sha256=$($result.AggregateSha256) entries=$($result.EntryCount)")
    if ($result.ReviewerCompatibilitySha256) {
        [Console]::Error.WriteLine(
            "[content-manifest] reviewer_compatibility_sha256=$($result.ReviewerCompatibilitySha256)")
    }
    $stdout = [Console]::OpenStandardOutput()
    $stdout.Write($result.ManifestBytes, 0, $result.ManifestBytes.Length)
    $stdout.Flush()
    exit 0
} catch {
    [Console]::Error.WriteLine("[content-manifest] ERROR -- $($_.Exception.Message)")
    exit 2
}
