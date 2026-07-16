# Proves #613's authored resources and #637's relic policy are compiled into
# WOC's runtime root and,
# after shipping, that the inspected build is the one installed from Workshop.
[CmdletBinding()]
param(
    [string]$BundleRoot,
    [string]$WorkshopRoot = 'C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3753880932',
    [switch]$SkipWorkshop,
    [string]$Unpacker = $env:VT2_BUNDLE_UNPACKER,
    [string]$CompressionDictionary = $env:VT2_COMPRESSION_DICTIONARY
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not $BundleRoot) { $BundleRoot = Join-Path $repoRoot 'weapons_of_chaos\bundleV2' }
if (-not $Unpacker) { $Unpacker = 'C:\Users\danjo\source\repos\vt2_bundle_unpacker\target\release\unpacker.exe' }
if (-not $CompressionDictionary) { $CompressionDictionary = 'C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\bundle\compression.dictionary' }
function Fail([string]$Message) { throw "[check_woc_blightreaper_bundle_contract] $Message" }
foreach ($path in @($Unpacker, $CompressionDictionary)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "tool input missing: $path" }
}
$rootBundle = Join-Path $BundleRoot 'dcea08518941f940.mod_bundle'
if (-not (Test-Path -LiteralPath $rootBundle -PathType Leaf)) { Fail "root bundle missing: $rootBundle" }
$iconSource = Join-Path $repoRoot 'weapons_of_chaos\gui\1080p\single_textures\weapons_of_chaos\icon_wpn_blightreaper.png'
$expectedIconSha256 = '07A59F76D0ECED0B42F143EF47B7D8EC87E1E542E14901E05CCE4E6C94F7A910'
if (-not (Test-Path -LiteralPath $iconSource -PathType Leaf)) { Fail "authored icon source missing: $iconSource" }
$actualIconSha256 = (Get-FileHash -LiteralPath $iconSource -Algorithm SHA256).Hash
if ($actualIconSha256 -ne $expectedIconSha256) {
    Fail "authored icon source drifted: expected=$expectedIconSha256 actual=$actualIconSha256"
}
$cursedSource = Join-Path $repoRoot 'weapons_of_chaos\gui\1080p\single_textures\weapons_of_chaos\icon_bg_cursed.png'
$expectedCursedSha256 = '497DC8CC0A00870ED407334F2DEBA82F945144404156DA93BB936A93E9C3ACE4'
if (-not (Test-Path -LiteralPath $cursedSource -PathType Leaf)) { Fail "Cursed rarity source missing: $cursedSource" }
$actualCursedSha256 = (Get-FileHash -LiteralPath $cursedSource -Algorithm SHA256).Hash
if ($actualCursedSha256 -ne $expectedCursedSha256) {
    Fail "Cursed rarity source drifted: expected=$expectedCursedSha256 actual=$actualCursedSha256"
}
$listing = @(& $Unpacker --dict NUL --zstd-dict $CompressionDictionary list $rootBundle 2>&1)
if ($LASTEXITCODE -ne 0) { Fail "unpacker failed: $($listing -join ' ')" }
$text = $listing -join "`n"
$required = [ordered]@{
    '99D57F229E554C63.unit'     = '1P unit'
    '82C10015C2C03BED.unit'     = '3P unit'
    '99D57F229E554C63.material' = 'authored material'
    '41355064E953AF6D.lua'       = 'shared appearance primitive'
    'E4C641E0BD963F8B.lua'       = 'appearance policy'
    '6E2356C79259A523.lua'       = 'preview consumers'
    '23C6E7C1A71A2157.lua'       = 'unique relic policy'
    '1C2ACC8620933DF0.lua'       = 'inventory icon renderer policy'
    '4FF265AF5A4F674D.material'  = 'authored inventory icon material'
    '2F41525708BE414A.texture'   = 'authored inventory icon texture'
    '85FFE5B17B07C852.lua'       = 'elf Sword moveset and non-elf animation remaps'
    '18F18F2FBAFE534B.lua'       = 'fixed normal and Chaos Wastes power policy'
    'D69ADFDA94A46689.lua'       = 'Cursed rarity registration'
    'E7CC3CDF46733B5D.material'  = 'Cursed rarity background material'
    '39B0D0569925E305.texture'   = 'Cursed rarity background texture'
}
foreach ($resource in $required.Keys) {
    if ($text -notmatch "(?im)^$([regex]::Escape($resource))\b") { Fail "compiled root missing $($required[$resource]) ($resource)" }
}
$matched = 0
if (-not $SkipWorkshop) {
    if (-not (Test-Path -LiteralPath $WorkshopRoot -PathType Container)) { Fail "Workshop folder missing: $WorkshopRoot" }
    foreach ($source in Get-ChildItem -LiteralPath $BundleRoot -File) {
        $deployed = Join-Path $WorkshopRoot $source.Name
        if (-not (Test-Path -LiteralPath $deployed -PathType Leaf)) { Fail "Workshop file missing: $($source.Name)" }
        if ((Get-FileHash $source.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $deployed -Algorithm SHA256).Hash) { Fail "Workshop hash mismatch: $($source.Name)" }
        $matched++
    }
}
$status = if ($SkipWorkshop) { 'skipped' } else { "$matched file(s) exact" }
Write-Host "[check_woc_blightreaper_bundle_contract] OK - 15 compiled resources, Workshop=$status"
