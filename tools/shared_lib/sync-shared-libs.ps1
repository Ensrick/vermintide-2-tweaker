# Copies canonical _lib_*.lua sources into standalone mod bundles, or verifies
# that every declared consumer is byte-for-byte identical. Issue #428.
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot "..\.."),
    [switch]$Apply,
    [switch]$Quiet
)
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$libraryRoot = Join-Path $repoRoot "tools\shared_lib"
$manifestPath = Join-Path $libraryRoot "manifest.psd1"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host "[shared-lib] ERROR: missing manifest: $manifestPath" -ForegroundColor Red
    exit 2
}
$manifest = Import-PowerShellDataFile -Path $manifestPath
$errors = @()
foreach ($entry in @($manifest.Libraries)) {
    $sourceName = [string]$entry.Source
    if (-not $sourceName.StartsWith("_lib_") -or -not $sourceName.EndsWith(".lua") -or
        $sourceName -ne [System.IO.Path]::GetFileName($sourceName)) {
        $errors += "invalid canonical source name '$sourceName' (expected a leaf _lib_*.lua name)"
        continue
    }
    $sourcePath = Join-Path $libraryRoot $sourceName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $errors += "missing canonical source: tools/shared_lib/$sourceName"
        continue
    }
    $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    foreach ($relativePath in @($entry.Consumers)) {
        $relativePath = [string]$relativePath
        $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $relativePath))
        $rootPrefix = $repoRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if (-not $destinationPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $errors += "consumer escapes repository root: $relativePath"
            continue
        }
        if ($Apply) {
            $parent = Split-Path $destinationPath -Parent
            if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                $errors += "consumer directory does not exist: $relativePath"
                continue
            }
            [System.IO.File]::WriteAllBytes($destinationPath, $sourceBytes)
            if (-not $Quiet) { Write-Host "[shared-lib] synced $relativePath" -ForegroundColor Green }
            continue
        }
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            $errors += "missing consumer copy: $relativePath (run tools/shared_lib/sync-shared-libs.ps1 -Apply)"
            continue
        }
        $destinationBytes = [System.IO.File]::ReadAllBytes($destinationPath)
        if ($sourceBytes.Length -ne $destinationBytes.Length -or
            -not [System.Linq.Enumerable]::SequenceEqual[byte]($sourceBytes, $destinationBytes)) {
            $errors += "drift: $relativePath differs from tools/shared_lib/$sourceName (run sync-shared-libs.ps1 -Apply)"
        } elseif (-not $Quiet) {
            Write-Host "[shared-lib] exact: $relativePath" -ForegroundColor DarkGray
        }
    }
}
if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "[shared-lib] ERROR: $message" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) {
    $verb = if ($Apply) { "sync complete" } else { "all copies are byte-for-byte exact" }
    Write-Host "[shared-lib] OK -- $verb." -ForegroundColor Green
}
exit 0
