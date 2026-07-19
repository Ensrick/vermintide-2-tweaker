[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$wocRoot = Join-Path $repoRoot 'weapons_of_chaos'
$errors = New-Object System.Collections.Generic.List[string]

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $errors.Add($Message) }
}

$expectedHashes = [ordered]@{
    'units/woc_skarrik_dual_swords/skarrik_sword_left.fbx' = '1A8D57C6744D22C9CAA80DE26BF62D369D98FFF3FE73B0895B54FC69252068AF'
    'units/woc_skarrik_dual_swords/skarrik_sword_left_3p.fbx' = '1A8D57C6744D22C9CAA80DE26BF62D369D98FFF3FE73B0895B54FC69252068AF'
    'units/woc_skarrik_dual_swords/skarrik_sword_right.fbx' = 'FAD2FF7065C878DE9CEB6BF11750776DD325B958F38BAEBDD3255F63B2C8649E'
    'units/woc_skarrik_dual_swords/skarrik_sword_right_3p.fbx' = 'FAD2FF7065C878DE9CEB6BF11750776DD325B958F38BAEBDD3255F63B2C8649E'
    'textures/woc_skarrik_dual_swords/skarrik_albedo.png' = '787560AE9A4946A6893462DD90AFE46C18CF4D96AB93415CB2F233ECC2F8EDAE'
    'textures/woc_skarrik_dual_swords/skarrik_normal.png' = 'ABD98F341AD6BC56780EF7DE6B05A46DC3FD7C722F8E6B442E970C076DDF183F'
    'textures/woc_skarrik_dual_swords/skarrik_roughness.png' = '7F35651D8AB3113F66A6B08AF8B52D15F2E32A3FFA1C63B83F953DAD7EF9A46E'
    'textures/woc_skarrik_dual_swords/skarrik_metallic.png' = '2BD27D82412B52298439229396FC7EEACB25C1392C9A834448CFBC920D34F52F'
}

foreach ($relative in $expectedHashes.Keys) {
    $path = Join-Path $wocRoot ($relative -replace '/', '\')
    Require (Test-Path -LiteralPath $path -PathType Leaf) "missing authored source: $relative"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        Require ($actual -eq $expectedHashes[$relative]) "authored source drifted: $relative expected=$($expectedHashes[$relative]) actual=$actual"
    }
}

$packagePath = Join-Path $wocRoot 'resource_packages/weapons_of_chaos/weapons_of_chaos.package'
$package = [IO.File]::ReadAllText($packagePath, [Text.Encoding]::UTF8)
$resources = @(
    'units/woc_skarrik_dual_swords/skarrik_swords'
    'units/woc_skarrik_dual_swords/skarrik_sword_left'
    'units/woc_skarrik_dual_swords/skarrik_sword_left_3p'
    'units/woc_skarrik_dual_swords/skarrik_sword_right'
    'units/woc_skarrik_dual_swords/skarrik_sword_right_3p'
    'textures/woc_skarrik_dual_swords/skarrik_albedo'
    'textures/woc_skarrik_dual_swords/skarrik_normal'
    'textures/woc_skarrik_dual_swords/skarrik_roughness'
    'textures/woc_skarrik_dual_swords/skarrik_metallic'
)
foreach ($resource in $resources) {
    Require ($package.Contains('"' + $resource + '"')) "package closure omits $resource"
}

$materialPath = Join-Path $wocRoot 'units/woc_skarrik_dual_swords/skarrik_swords.material'
$material = [IO.File]::ReadAllText($materialPath, [Text.Encoding]::UTF8)
foreach ($texture in @('skarrik_albedo', 'skarrik_normal', 'skarrik_roughness', 'skarrik_metallic')) {
    Require ($material.Contains("textures/woc_skarrik_dual_swords/$texture")) "material omits $texture"
}
Require (-not $material.Contains('EC0DEBBFA142BC2B')) 'material must not bind the native zero-byte texture'

foreach ($hand in @('left', 'right')) {
    foreach ($suffix in @('', '_3p')) {
        $unitPath = Join-Path $wocRoot "units/woc_skarrik_dual_swords/skarrik_sword_${hand}${suffix}.unit"
        $unit = [IO.File]::ReadAllText($unitPath, [Text.Encoding]::UTF8)
        Require ($unit.Contains("skarrik_sword_${hand}_mat = `"units/woc_skarrik_dual_swords/skarrik_swords`"")) "${hand}${suffix} unit has wrong material-slot binding"
        Require ($unit.Contains("skarrik_sword_$hand = {")) "${hand}${suffix} unit has wrong renderable identity"
    }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) { Write-Error $errorMessage }
    throw "[check_woc_skarrik_asset_sources] FAIL - $($errors.Count) error(s)"
}
if (-not $Quiet) {
    Write-Host "[check_woc_skarrik_asset_sources] OK - $($expectedHashes.Count) pinned assets, $($resources.Count) packaged resources, four hand/view units" -ForegroundColor Green
}
