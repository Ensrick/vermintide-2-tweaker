# Fail-closed normalization for explicitly inventoried, non-mod VMB build
# artifacts. ASCII-only for Windows PowerShell 5.1 parsing.

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
    $errors = @(Get-BuildArtifactExclusionErrors -ModEntry $entry)
    if ($errors.Count -gt 0) {
        throw "Invalid build-output normalization policy: $($errors -join '; ')"
    }
    return $entry
}

function Invoke-BuildOutputNormalization {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $entry = Get-ModBuildArtifactPolicy -RepoRoot $RepoRoot -Mod $Mod
    $exclusions = @($entry.BuildArtifactExclusions | Where-Object { $null -ne $_ })
    $result = [ordered]@{
        Mod = $Mod
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

    foreach ($exclusion in $exclusions) {
        $name = [string]$exclusion.Name
        $expectedSha256 = ([string]$exclusion.Sha256).ToLowerInvariant()
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

        $actualSha256 = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualSha256 -cne $expectedSha256) {
            throw ("Build-output normalization REFUSED changed bytes for {0}/{1}: expected SHA-256 {2}, got {3}. " +
                "The file was left untouched for inspection." -f $Mod, $name, $expectedSha256, $actualSha256)
        }

        Remove-Item -LiteralPath $candidate -Force
        if (Test-Path -LiteralPath $candidate) {
            throw "Build-output normalization could not remove exact known sidecar: $candidate"
        }
        $result.Removed++
        $result.RemovedNames += $name
        Write-Host "  build normalization: removed exact known SDK tool-only sidecar $Mod/$name" -ForegroundColor Yellow
    }

    return [pscustomobject]$result
}
