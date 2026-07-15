# check_encarmine_bundle_contract.ps1
#
# Proves that the exact Encarmine source inputs and the resources required by
# the Laurel material-instance override are present in the compiled Cosmetics
# root bundle. Optionally proves the locally deployed Workshop folder is the
# exact build that was inspected.

[CmdletBinding()]
param(
    [string]$BundleRoot,
    [string]$WorkshopRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3715714222',
    [switch]$SkipWorkshop,
    [string]$Unpacker = $env:VT2_BUNDLE_UNPACKER,
    [string]$CompressionDictionary = $env:VT2_COMPRESSION_DICTIONARY
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $BundleRoot) { $BundleRoot = Join-Path $repoRoot 'cosmetics_tweaker\bundleV2' }
if (-not $Unpacker) {
    $Unpacker = 'C:\Users\danjo\source\repos\vt2_bundle_unpacker\target\release\unpacker.exe'
}
if (-not $CompressionDictionary) {
    $CompressionDictionary = 'C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\bundle\compression.dictionary'
}

function Fail([string]$Message) { throw "[check_encarmine_bundle_contract] $Message" }
function Assert-Hash([string]$RelativePath, [string]$Expected) {
    $path = Join-Path $repoRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "missing source: $RelativePath" }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) { Fail "source hash drift: $RelativePath expected=$Expected actual=$actual" }
}

Assert-Hash 'cosmetics_tweaker\textures\cosmetics_tweaker\encarmine_hat\encarmine_armored_diffuse.png' `
    '1E3A23798DF61BDC940C9E1D3CD42607078118A487420E02345D4C59B30912E7'
Assert-Hash 'cosmetics_tweaker\textures\cosmetics_tweaker\encarmine_hat\encarmine_cloth_diffuse.png' `
    'B5925708AB95BEFF7B800FCAD717F308BCFB173E8069343D3AADE83FC282954D'
Assert-Hash 'cosmetics_tweaker\gui\1080p\single_textures\cosmetics_tweaker\icon_knight_hat_0006_encarmine.png' `
    '70FE445CDF3741CEA8CA00C967BB827DA6196BB605DE6CC2F9D2B458C0ED2097'

$luaPath = Join-Path $repoRoot 'cosmetics_tweaker\scripts\mods\cosmetics_tweaker\_cos_custom_hats.lua'
$lua = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
foreach ($needle in @(
    'units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07',
    'resource = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_base"',
    'resource = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_feather"',
    '[1] = { geometry_index = 7, role = "armor",  material_slot = "1903313B" }',
    '[3] = { geometry_index = 5, role = "armor",  material_slot = "1903313B" }',
    '[4] = { geometry_index = 4, role = "plume",  material_slot = "BD15BFF9" }',
    '[6] = { geometry_index = 2, role = "plume",  material_slot = "BD15BFF9" }',
    'armor_mesh_indices = mesh_indices_for("armor")',
    'plume_mesh_indices = mesh_indices_for("plume")',
    'texture_map_c0ba2942',
    'texture_map_59cd86b9',
    'texture_map_b788717c'
)) {
    if (-not $lua.Contains($needle)) { Fail "runtime Laurel contract missing: $needle" }
}

if (-not (Test-Path -LiteralPath $Unpacker -PathType Leaf)) { Fail "unpacker unavailable: $Unpacker" }
if (-not (Test-Path -LiteralPath $CompressionDictionary -PathType Leaf)) { Fail "compression dictionary unavailable: $CompressionDictionary" }
$rootBundle = Join-Path $BundleRoot '6448e4de51a26af1.mod_bundle'
if (-not (Test-Path -LiteralPath $rootBundle -PathType Leaf)) { Fail "compiled root bundle missing: $rootBundle" }
$listing = @(& $Unpacker --dict NUL --zstd-dict $CompressionDictionary list $rootBundle 2>&1)
if ($LASTEXITCODE -ne 0) { Fail "unpacker failed: $($listing -join ' ')" }
$text = $listing -join "`n"
$required = [ordered]@{
    '07D37F422A5333F9.lua'      = 'Encarmine runtime module'
    '992E17286E91C526.texture'  = 'armor diffuse'
    '0C7D5EA6955CC241.texture'  = 'plume diffuse'
    '1DDB087A8393A744.texture'  = 'armor normal'
    '9F9CF27A3ABD2216.texture'  = 'plume normal'
    'A79A397AF4C94007.texture'  = 'armor combined'
    '648E22FF8FB70C3F.texture'  = 'plume combined'
    'F51738255112D557.material' = 'inventory icon material'
    '1986122112C61D4A.texture'  = 'inventory icon texture'
}
foreach ($resource in $required.Keys) {
    if ($text -notmatch "(?im)^$([regex]::Escape($resource))\b") {
        Fail "compiled root bundle missing $($required[$resource]) ($resource)"
    }
}

$matched = 0
if (-not $SkipWorkshop) {
    if (-not (Test-Path -LiteralPath $WorkshopRoot -PathType Container)) { Fail "Workshop folder missing: $WorkshopRoot" }
    foreach ($source in Get-ChildItem -LiteralPath $BundleRoot -File) {
        $deployed = Join-Path $WorkshopRoot $source.Name
        if (-not (Test-Path -LiteralPath $deployed -PathType Leaf)) { Fail "Workshop file missing: $($source.Name)" }
        $sourceHash = (Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash
        $deployedHash = (Get-FileHash -LiteralPath $deployed -Algorithm SHA256).Hash
        if ($sourceHash -ne $deployedHash) { Fail "Workshop hash mismatch: $($source.Name)" }
        $matched++
    }
}

$workshopStatus = if ($SkipWorkshop) { 'skipped' } else { "$matched file(s) exact" }
Write-Host "[check_encarmine_bundle_contract] OK - exact authored inputs, 9 compiled resources, Workshop=$workshopStatus"
