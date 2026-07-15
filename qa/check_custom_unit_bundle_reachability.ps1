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
function Get-BundleResourceIds([string]$BundlePath, [string]$Extension) {
    $cacheKey = "$BundlePath|$Extension"
    if ($bundleListCache.ContainsKey($cacheKey)) { return $bundleListCache[$cacheKey] }
    $ids = @{}
    foreach ($line in Invoke-Unpacker @('list', $BundlePath)) {
        $match = [regex]::Match($line, "(?i)^([0-9a-f]{16})\.$([regex]::Escape($Extension))\b")
        if ($match.Success) { $ids[$match.Groups[1].Value.ToUpperInvariant()] = $true }
    }
    $bundleListCache[$cacheKey] = $ids
    return $ids
}

function Get-BundleUnitIds([string]$BundlePath) {
    return Get-BundleResourceIds $BundlePath 'unit'
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
    $rootPackageIds = @{}
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
        foreach ($id in (Get-BundleResourceIds $bundle 'package').Keys) { $rootPackageIds[$id] = $true }
    }

    foreach ($unitFile in $unitFiles) {
        $relative = $unitFile.FullName.Substring($modRoot.Length + 1) -replace '\\', '/'
        $resourcePath = $relative.Substring(0, $relative.Length - '.unit'.Length)
        $unitHash = Get-Murmur64 $resourcePath
        $checkedUnits++
        if (-not $rootUnitIds[$unitHash]) {
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
            continue
        }

        # A sibling package is an authored promise that PackageManager may load
        # the unit path directly (the exact boundary used by hero previews).
        # Prove both the root forwarding resource and the standalone package's
        # unit/material dependency closure; a successful shader compile alone
        # is insufficient because engine async package fatals bypass Lua.
        $sidecarPackage = [IO.Path]::ChangeExtension($unitFile.FullName, '.package')
        if (Test-Path -LiteralPath $sidecarPackage -PathType Leaf) {
            if (-not $rootPackageIds[$unitHash]) {
                $errors.Add("$($entry.Dir): $resourcePath has a sidecar .package but [$unitHash.package] is absent from every explicit root bundle")
                continue
            }
            $standalone = Join-Path $bundleRoot ($unitHash.ToLowerInvariant() + '.mod_bundle')
            if (-not (Test-Path -LiteralPath $standalone -PathType Leaf)) {
                $errors.Add("$($entry.Dir): $resourcePath sidecar package has no compiled $($unitHash.ToLowerInvariant()).mod_bundle")
                continue
            }
            if (-not (Get-BundleUnitIds $standalone)[$unitHash]) {
                $errors.Add("$($entry.Dir): $resourcePath standalone package omits its unit [$unitHash.unit]")
            }
            $unitText = [IO.File]::ReadAllText($unitFile.FullName, [Text.Encoding]::UTF8)
            foreach ($materialMatch in [regex]::Matches($unitText, '(?m)^\s*\w+\s*=\s*"([^"]+)"\s*$')) {
                $materialPath = $materialMatch.Groups[1].Value
                if ($materialPath -notmatch '/encarmine_(?:armored|cloth)$') { continue }
                $materialHash = Get-Murmur64 $materialPath
                if (-not (Get-BundleResourceIds $standalone 'material')[$materialHash]) {
                    $errors.Add("$($entry.Dir): $resourcePath standalone package omits material $materialPath [$materialHash.material]")
                }
                $materialSource = Join-Path $modRoot (($materialPath -replace '/', '\') + '.material')
                if (Test-Path -LiteralPath $materialSource -PathType Leaf) {
                    $materialText = [IO.File]::ReadAllText($materialSource, [Text.Encoding]::UTF8)
                    foreach ($textureMatch in [regex]::Matches($materialText, '"(textures/[^"]+)"')) {
                        $texturePath = $textureMatch.Groups[1].Value
                        $textureHash = Get-Murmur64 $texturePath
                        if (-not (Get-BundleResourceIds $standalone 'texture')[$textureHash]) {
                            $errors.Add("$($entry.Dir): $resourcePath standalone package omits texture $texturePath [$textureHash.texture]")
                        }
                    }
                }
            }

            if ($resourcePath -eq 'units/cosmetics_tweaker/encarmine_hat/encarmine_hat') {
                $expectedAssets = [ordered]@{
                    'encarmine_armored_diffuse.png'  = 'AD7400CD51D729DB526763946B8F468BC057E62A743B4A38B7D7472C010E62EE'
                    # RGB remains the reviewed charcoal recolor; alpha now
                    # matches Laurel byte-for-byte instead of the failed
                    # binary cutout workaround (#612 response revision 5).
                    'encarmine_cloth_diffuse.png'    = 'DE3C8B8B19211CDA4FF7199E0055CE702BB09A61EFBB23B7CB47A37BDBA316B3'
                    'encarmine_armored_normal.png'   = '8FEB4D44EEB5C0551E752741F650264D4AA1224528910FCDF598186E89EF423D'
                    'encarmine_armored_combined.png' = '0714FCF0C7FD21CB35E8B857427E92C103AFE8ABB830308A2346F9E593C297B7'
                    'encarmine_armored_metallic.png' = '9928C49EBB8B594A79DAEC75DE96AA78CE147DB2C87F167CA15C48B76902E294'
                    'encarmine_armored_ao.png'       = 'F8D79D0EBAC612B92E59408E8B5037846C8DB3DC64241F7C0CDBC902FA33A29D'
                    'encarmine_armored_roughness.png' = '1FCF3B0DD914F6AEE2368F2C6D1B53BBE2AF7025956DF690F13335E196123A3C'
                    'encarmine_cloth_normal.png'     = '7433488E5AEC2277FD0860D67FC834A9EA1450EAAEDE8A15867681F78E47B189'
                    'encarmine_cloth_combined.png'   = 'FBEAD3279C4D420DDC75BA665EF112DC4110A82386F71F96BD3372BAF47C5045'
                    'encarmine_cloth_metallic.png'   = 'A28F725A1ED300A12BAF2E2BB79DE9F73C77E6E7ECB576E935555D414938E689'
                    'encarmine_cloth_ao.png'         = 'DE6C3ABD1352D70308FAB3ECE0651E2BCBC28DCB6B63B3B026D9748313719301'
                    'encarmine_cloth_roughness.png'  = 'C552743A5354FF8AD649FDB2666867DBA7B91AF2777998121002EE314570BECF'
                }
                $textureRoot = Join-Path $modRoot 'textures\cosmetics_tweaker\encarmine_hat'
                foreach ($asset in $expectedAssets.GetEnumerator()) {
                    $assetPath = Join-Path $textureRoot $asset.Key
                    if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
                        $errors.Add("$($entry.Dir): Encarmine source asset missing: $($asset.Key)")
                        continue
                    }
                    $actualSha = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash
                    if ($actualSha -ne $asset.Value) {
                        $errors.Add("$($entry.Dir): Encarmine source asset hash drifted: $($asset.Key) expected=$($asset.Value) actual=$actualSha")
                    }
                }
                $fbxPath = Join-Path $modRoot 'units\cosmetics_tweaker\encarmine_hat\encarmine_hat.fbx'
                $expectedFbxSha = '7F4CD4FCC517AF914B4E555EAC29B8D9E989269B9059E22F0CBA86A1B83DD932'
                if (-not (Test-Path -LiteralPath $fbxPath -PathType Leaf)) {
                    $errors.Add("$($entry.Dir): Encarmine authored FBX missing")
                } else {
                    $actualFbxSha = (Get-FileHash -LiteralPath $fbxPath -Algorithm SHA256).Hash
                    if ($actualFbxSha -ne $expectedFbxSha) {
                        $errors.Add("$($entry.Dir): Encarmine authored FBX drifted expected=$expectedFbxSha actual=$actualFbxSha")
                    }
                    $fbxAscii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($fbxPath))
                    foreach ($marker in @('Deformer', 'encarmine_hat_armature', 'j_feather_01_dynamic', 'j_feather_06_dynamic')) {
                        if (-not $fbxAscii.Contains($marker)) {
                            $errors.Add("$($entry.Dir): Encarmine authored FBX lost rig marker: $marker")
                        }
                    }
                }

                $bonesPath = Join-Path $modRoot 'units\cosmetics_tweaker\encarmine_hat\encarmine_hat.bones'
                $expectedBonesSha = 'A75E6EACBC6AD2B39A2069C17EB7CF48938191AED4714F564F391F62B6099B6A'
                if (-not (Test-Path -LiteralPath $bonesPath -PathType Leaf)) {
                    $errors.Add("$($entry.Dir): Encarmine source bones missing")
                } elseif ((Get-FileHash -LiteralPath $bonesPath -Algorithm SHA256).Hash -ne $expectedBonesSha) {
                    $errors.Add("$($entry.Dir): Encarmine source bones drifted")
                }

                $clothMaterialPath = Join-Path $modRoot 'units\cosmetics_tweaker\encarmine_hat\encarmine_cloth.material'
                if (Test-Path -LiteralPath $clothMaterialPath -PathType Leaf) {
                    $clothMaterial = [IO.File]::ReadAllText($clothMaterialPath, [Text.Encoding]::UTF8)
                    if ($clothMaterial -notmatch 'use_opacity_map\s*=\s*\{\s*type\s*=\s*"scalar"\s*value\s*=\s*1\s*\}') {
                        $errors.Add("$($entry.Dir): Encarmine cloth material no longer consumes diffuse alpha")
                    }
                    $clothTexturePath = Join-Path $textureRoot 'encarmine_cloth_diffuse.texture'
                    $clothTexture = [IO.File]::ReadAllText($clothTexturePath, [Text.Encoding]::UTF8)
                    if ($clothTexture -notmatch 'enable_cut_alpha_threshold\s*=\s*false') {
                        $errors.Add("$($entry.Dir): Encarmine cloth texture no longer preserves Laurel fractional alpha")
                    }
                }
            }
        }
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
