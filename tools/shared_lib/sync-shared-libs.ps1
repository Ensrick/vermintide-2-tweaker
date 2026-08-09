# Copies canonical _lib_*.lua sources into standalone mod bundles, or verifies
# that every declared consumer is byte-for-byte identical. Issue #428.
#
# Coverage runs BOTH directions (issue #1159). Exact-byte comparison only sees
# files the manifest names, so an undeclared copy is invisible to it: a mod tree
# can carry a _lib_*.lua nobody registered and drift from canonical forever
# while the gate stays green. Two census scans close that hole - every
# _lib_*.lua in a mod tree must be a declared consumer, and every canonical
# _lib_*.lua in tools/shared_lib must be a declared Source.
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

# Trees that are not this repository's mod source: hidden tool-owned checkouts
# (.git, .claude/worktrees, .codex/worktrees), build output, and archives.
function Test-ExcludedLibraryScanPath([string]$relativePath) {
    return [regex]::IsMatch($relativePath, '(?i)(?:^|/)(?:\.[^/]+|_archive|bundleV2)/')
}

function Get-RepositoryLibraryCopies([string]$Root) {
    # Prune hidden top-level directories before recursing so a large .git or a
    # sibling agent worktree container is never walked.
    $searchRoots = @(
        Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue `
            | Where-Object { -not $_.Name.StartsWith('.') }
    )
    $found = @()
    foreach ($searchRoot in $searchRoots) {
        foreach ($file in @(Get-ChildItem -LiteralPath $searchRoot.FullName -Filter '_lib_*.lua' -Recurse -File -ErrorAction SilentlyContinue)) {
            $relative = $file.FullName.Substring($Root.Length + 1).Replace('\', '/')
            if (Test-ExcludedLibraryScanPath $relative) { continue }
            $found += $relative
        }
    }
    return @($found)
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Write-Host "[shared-lib] ERROR: missing manifest: $manifestPath" -ForegroundColor Red
    exit 2
}
$manifest = Import-PowerShellDataFile -Path $manifestPath
$errors = @()
$declaredSources = @{}
$declaredConsumers = @{}
foreach ($entry in @($manifest.Libraries)) {
    $sourceName = [string]$entry.Source
    if (-not $sourceName.StartsWith("_lib_") -or -not $sourceName.EndsWith(".lua") -or
        $sourceName -ne [System.IO.Path]::GetFileName($sourceName)) {
        $errors += "invalid canonical source name '$sourceName' (expected a leaf _lib_*.lua name)"
        continue
    }
    $declaredSources[$sourceName.ToLowerInvariant()] = $true
    $sourcePath = Join-Path $libraryRoot $sourceName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        $errors += "missing canonical source: tools/shared_lib/$sourceName"
        continue
    }
    $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
    # A tools-only canonical library declares Consumers = @(); guard the null
    # and blank forms so an empty list never reads as one unnamed consumer.
    $consumers = @(@($entry.Consumers) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    foreach ($relativePath in $consumers) {
        $relativePath = ([string]$relativePath).Replace('\', '/')
        $declaredConsumers[$relativePath.ToLowerInvariant()] = $true
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
        $bytesEqual = $sourceBytes.Length -eq $destinationBytes.Length
        if ($bytesEqual) {
            for ($i = 0; $i -lt $sourceBytes.Length; $i++) {
                if ($sourceBytes[$i] -ne $destinationBytes[$i]) {
                    $bytesEqual = $false
                    break
                }
            }
        }
        if (-not $bytesEqual) {
            $errors += "drift: $relativePath differs from tools/shared_lib/$sourceName (run sync-shared-libs.ps1 -Apply)"
        } elseif (-not $Quiet) {
            Write-Host "[shared-lib] exact: $relativePath" -ForegroundColor DarkGray
        }
    }
}

# Census both directions: a copy the manifest never named is never compared, so
# absence from the manifest - not difference from canonical - is the failure.
foreach ($relativePath in @(Get-RepositoryLibraryCopies $repoRoot | Sort-Object)) {
    if ($relativePath.StartsWith('tools/shared_lib/', [System.StringComparison]::OrdinalIgnoreCase)) {
        $leaf = [System.IO.Path]::GetFileName($relativePath)
        if (-not $declaredSources.ContainsKey($leaf.ToLowerInvariant())) {
            $errors += "unmanifested canonical library: $relativePath (add a Libraries entry naming Source = '$leaf'; use Consumers = @() when nothing bundles a copy)"
        }
        continue
    }
    if (-not $declaredConsumers.ContainsKey($relativePath.ToLowerInvariant())) {
        $errors += "undeclared copy: $relativePath is not a manifest consumer, so no gate compares it against canonical (declare it under its canonical Source in tools/shared_lib/manifest.psd1)"
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
