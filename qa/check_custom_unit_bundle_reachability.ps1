# check_custom_unit_bundle_reachability.ps1
#
# A compiled .mod_bundle existing beside a mod does not make its resources
# resident. VMF initially loads only the package roots declared by the mod's
# source .mod file. Custom weapon units which live only in an unrooted sibling
# bundle therefore pass source/package checks but crash asynchronous UI package
# loading with `Resource '#ID[...]' was not found`.
#
# This gate hashes every authored custom .unit, lists the compiled bundles for
# each explicit .mod package root, and requires the corresponding UNIT resource
# to be present in at least one root bundle. Nested forwarding bundles do not
# count: the requested unit must actually be resident from a runtime load root.

[CmdletBinding()]
param(
    [switch]$Quiet,
    [string]$Unpacker = $env:VT2_BUNDLE_UNPACKER,
    [string]$CompressionDictionary = $env:VT2_COMPRESSION_DICTIONARY
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$errors = New-Object System.Collections.Generic.List[string]

function Find-FirstFile([string[]]$Candidates) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

if (-not $Unpacker) {
    $Unpacker = Find-FirstFile @(
        'C:\Tools\vt2_bundle_unpacker\target\release\unpacker.exe',
        (Join-Path $repoRoot 'tools\vt2_bundle_unpacker\target\release\unpacker.exe')
    )
}
if (-not $CompressionDictionary) {
    $CompressionDictionary = Find-FirstFile @(
        'C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\bundle\compression.dictionary',
        'C:\Program Files\Steam\steamapps\common\Warhammer Vermintide 2\bundle\compression.dictionary'
    )
}

if (-not $Unpacker -or -not (Test-Path -LiteralPath $Unpacker -PathType Leaf)) {
    if (-not $Quiet) {
        Write-Host '[check_custom_unit_bundle_reachability] SKIP - VT2 bundle unpacker unavailable (set VT2_BUNDLE_UNPACKER).' -ForegroundColor DarkYellow
    }
    exit 0
}
if (-not $CompressionDictionary -or -not (Test-Path -LiteralPath $CompressionDictionary -PathType Leaf)) {
    if (-not $Quiet) {
        Write-Host '[check_custom_unit_bundle_reachability] SKIP - VT2 compression.dictionary unavailable (set VT2_COMPRESSION_DICTIONARY).' -ForegroundColor DarkYellow
    }
    exit 0
}

function Invoke-Unpacker([string[]]$Arguments) {
    $output = @(& $Unpacker --dict NUL --zstd-dict $CompressionDictionary @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "bundle unpacker failed ($LASTEXITCODE): $($output -join ' ')"
    }
    return @($output | ForEach-Object {
        ([string]$_) -replace "`e\[[0-?]*[ -/]*[@-~]", ''
    })
}

$hashCache = @{}
function Get-Murmur64([string]$ResourcePath) {
    if ($hashCache.ContainsKey($ResourcePath)) { return $hashCache[$ResourcePath] }
    $lines = Invoke-Unpacker @('murmur', 'hash', $ResourcePath)
    $match = [regex]::Match(($lines -join ' '), '(?i)\b[0-9a-f]{16}\b')
    if (-not $match.Success) { throw "no Murmur64 result for $ResourcePath" }
    $value = $match.Value.ToUpperInvariant()
    $hashCache[$ResourcePath] = $value
    return $value
}

$bundleListCache = @{}
function Get-BundleUnitIds([string]$BundlePath) {
    if ($bundleListCache.ContainsKey($BundlePath)) { return $bundleListCache[$BundlePath] }
    $ids = @{}
    foreach ($line in Invoke-Unpacker @('list', $BundlePath)) {
        $match = [regex]::Match($line, '(?i)^([0-9a-f]{16})\.unit\b')
        if ($match.Success) { $ids[$match.Groups[1].Value.ToUpperInvariant()] = $true }
    }
    $bundleListCache[$BundlePath] = $ids
    return $ids
}

function Get-ModPackageRoots([string]$ModSourcePath) {
    $text = [System.IO.File]::ReadAllText($ModSourcePath, [System.Text.Encoding]::UTF8)
    $block = [regex]::Match($text, '(?s)\bpackages\s*=\s*\{(.*?)\}')
    if (-not $block.Success) { return @() }
    return @([regex]::Matches($block.Groups[1].Value, '["'']([^"'']+)["'']') |
        ForEach-Object { $_.Groups[1].Value })
}

$inventoryPath = Join-Path $repoRoot 'tools\mod-inventory.psd1'
$inventory = Import-PowerShellDataFile $inventoryPath
$checkedUnits = 0

foreach ($entry in $inventory.Mods) {
    $modRoot = Join-Path $repoRoot $entry.Dir
    $unitsRoot = Join-Path $modRoot 'units'
    if (-not (Test-Path -LiteralPath $unitsRoot -PathType Container)) { continue }

    $unitFiles = @(Get-ChildItem -LiteralPath $unitsRoot -Recurse -File -Filter '*.unit')
    if ($unitFiles.Count -eq 0) { continue }

    $modSource = Join-Path $modRoot ($entry.Dir + '.mod')
    $bundleRoot = Join-Path $modRoot 'bundleV2'
    if (-not (Test-Path -LiteralPath $modSource -PathType Leaf)) {
        $errors.Add("$($entry.Dir): source .mod file missing: $modSource")
        continue
    }

    $roots = @(Get-ModPackageRoots $modSource)
    if ($roots.Count -eq 0) {
        $errors.Add("$($entry.Dir): .mod declares no package roots")
        continue
    }

    $rootUnitIds = @{}
    $rootBundleNames = New-Object System.Collections.Generic.List[string]
    foreach ($root in $roots) {
        $rootHash = Get-Murmur64 $root
        $bundle = Join-Path $bundleRoot ($rootHash.ToLowerInvariant() + '.mod_bundle')
        if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
            $errors.Add("$($entry.Dir): package root $root has no compiled bundle $([IO.Path]::GetFileName($bundle))")
            continue
        }
        $rootBundleNames.Add([IO.Path]::GetFileName($bundle))
        foreach ($id in (Get-BundleUnitIds $bundle).Keys) { $rootUnitIds[$id] = $true }
    }

    foreach ($unitFile in $unitFiles) {
        $relative = $unitFile.FullName.Substring($modRoot.Length + 1) -replace '\\', '/'
        $resourcePath = $relative.Substring(0, $relative.Length - '.unit'.Length)
        $unitHash = Get-Murmur64 $resourcePath
        $checkedUnits++
        if ($rootUnitIds[$unitHash]) { continue }

        $owners = New-Object System.Collections.Generic.List[string]
        foreach ($bundle in Get-ChildItem -LiteralPath $bundleRoot -File -Filter '*.mod_bundle') {
            if ($rootBundleNames.Contains($bundle.Name)) { continue }
            if ((Get-BundleUnitIds $bundle.FullName)[$unitHash]) { $owners.Add($bundle.Name) }
        }
        $ownerText = if ($owners.Count -gt 0) {
            'compiled only in unrooted bundle(s): ' + ($owners -join ', ')
        } else {
            'absent from every compiled bundle'
        }
        $errors.Add("$($entry.Dir): $resourcePath [$unitHash.unit] is not resident from any explicit .mod package root; $ownerText")
    }
}

if ($errors.Count -gt 0) {
    Write-Host "[check_custom_unit_bundle_reachability] FAIL - $($errors.Count) unreachable custom unit resource(s)" -ForegroundColor Red
    foreach ($errorText in $errors) { Write-Host "  ERROR: $errorText" -ForegroundColor Red }
    exit 2
}

if (-not $Quiet) {
    Write-Host "[check_custom_unit_bundle_reachability] OK - $checkedUnits custom unit resource(s) are resident from explicit .mod package roots" -ForegroundColor Green
}
exit 0
