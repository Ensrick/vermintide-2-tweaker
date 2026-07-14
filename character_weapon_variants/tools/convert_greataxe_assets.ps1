[CmdletBinding()]
param(
    [string]$SourceRoot = 'C:\Users\danjo\source\repos\_cwv_greataxe_sources',
    [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Blender = 'C:\Program Files\Blender Foundation\Blender 4.4\blender.exe',
    [string]$Magick = 'C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Blender)) { throw "Blender not found: $Blender" }
if (-not (Test-Path -LiteralPath $Magick)) { throw "ImageMagick not found: $Magick" }

$assets = @(
    @{ Id='01'; Mesh='01_battle_axe\source\LowPoly3.fbx'; Tex='01_battle_axe\textures'; Albedo='LowPoly3_DefaultMaterial_BaseColor.png'; Normal='LowPoly3_DefaultMaterial_Normal.png'; Roughness='LowPoly3_DefaultMaterial_Roughness.png'; Metallic='LowPoly3_DefaultMaterial_Metallic.png'; Ao=$null },
    @{ Id='02'; Mesh='02_viking_war_axe\source\WarAxe_HighRes.fbx'; Tex='02_viking_war_axe\textures'; Albedo='lambert1_Base_Color.jpg'; Normal='lambert1_Normal_DirectX.jpg'; Roughness='lambert1_Roughness.jpg'; Metallic='lambert1_Metallic.jpg'; Ao='lambert1_Mixed_AO.jpg' },
    @{ Id='03'; Mesh='03_viking_axe_wilhelm\source\model\axe_low_poly.OBJ'; Tex='03_viking_axe_wilhelm\textures'; Albedo='axe_[Albedo].jpg'; Normal='axe_[Normal].jpg'; Roughness='axe_[Gloss].jpg'; Metallic='axe_[Specular].jpg'; Ao=$null; InvertRoughness=$true; GreyMetallic=$true },
    @{ Id='04'; Mesh='04_viking_axe_abby\source\extracted\model\model.dae'; Tex='04_viking_axe_abby\textures'; Albedo='Axe_low_lambert1_BaseColor.png'; Normal='Axe_low_lambert1_Normal.png'; Roughness='Axe_low_lambert1_Roughness.png'; Metallic='Axe_low_lambert1_Metallic.png'; Ao='lambert1_ambient_occlusion.png' },
    @{ Id='05'; Mesh='05_axe_taylor\source\model\Axe_Mesh.FBX'; Tex='05_axe_taylor\textures'; Albedo='Axe_Diffuse.jpeg'; Normal='Axe_Normal.jpeg'; Roughness='Axe_Gloss.jpeg'; Metallic='Axe_Specular.jpeg'; Ao=$null; InvertRoughness=$true; GreyMetallic=$true }
)

$unitTemplate = @'
materials = {
	axe_mat = "units/cwv_es_greataxe/axe___ID__/axe___ID__"
}

renderables = {
	axe___ID__ = {
		always_keep = false
		culling = "bounding_volume"
		generate_uv_unwrap = false
		occluder = false
		shadow_caster = __SHADOW__
		surface_queries = false
		viewport_visible = true
	}
}
'@

$textureTemplate = @'
common = {
	input = {
		filename = "textures/cwv_es_greataxe/axe___ID__/axe___ID_____CHANNEL__"
	}
	output = {
		apply_processing = true
		cut_alpha_threshold = 0.5
		enable_cut_alpha_threshold = false
		format = "DXT5"
		mipmap_filter = "kaiser"
		mipmap_filter_wrap_mode = "mirror"
		mipmap_keep_original = false
		mipmap_num_largest_steps_to_discard = 0
		mipmap_num_smallest_steps_to_discard = 0
		srgb = __SRGB__
	}
}
'@

$assetPackageTemplate = @'
unit = [
	"units/cwv_es_greataxe/axe___ID__/axe___ID__"
	"units/cwv_es_greataxe/axe___ID__/axe___ID___3p"
]
texture = [ "textures/cwv_es_greataxe/axe___ID__/*" ]
material = [ "units/cwv_es_greataxe/axe___ID__/axe___ID__" ]
'@

$forwardPackageTemplate = @'
package = [ "units/cwv_es_greataxe/axe___ID__/axe___ID___assets" ]
'@

$standardMaterial = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\core\stingray_renderer\shader_import\standard.material'
if (-not (Test-Path -LiteralPath $standardMaterial)) { throw "SDK standard material not found: $standardMaterial" }
$materialBase = Get-Content -Raw -LiteralPath $standardMaterial
$materialBase = $materialBase -replace '(?s)textures = \{\s*\}\s*variables = \{.*?\}\s*$', @'
textures = {
	color_map = "textures/cwv_es_greataxe/axe___ID__/axe___ID___albedo"
	normal_map = "textures/cwv_es_greataxe/axe___ID__/axe___ID___normal"
	roughness_map = "textures/cwv_es_greataxe/axe___ID__/axe___ID___roughness"
	metallic_map = "textures/cwv_es_greataxe/axe___ID__/axe___ID___metallic"
	ao_map = "textures/cwv_es_greataxe/axe___ID__/axe___ID___ao"
}
variables = {
	use_color_map = { type = "scalar" value = 1 }
	use_normal_map = { type = "scalar" value = 1 }
	use_roughness_map = { type = "scalar" value = 1 }
	use_metallic_map = { type = "scalar" value = 1 }
	use_ao_map = { type = "scalar" value = 1 }
	emissive_intensity = { type = "scalar" value = 0 }
}
'@

foreach ($asset in $assets) {
    $id = $asset.Id
    $unitDir = Join-Path $ModRoot "units\cwv_es_greataxe\axe_$id"
    $textureDir = Join-Path $ModRoot "textures\cwv_es_greataxe\axe_$id"
    New-Item -ItemType Directory -Force -Path $unitDir, $textureDir | Out-Null

    $fbx = Join-Path $unitDir "axe_$id.fbx"
    $report = Join-Path $SourceRoot "axe_$id-conversion.json"
    & $Blender --background --factory-startup --python (Join-Path $PSScriptRoot 'convert_greataxe_mesh.py') -- `
        --input (Join-Path $SourceRoot $asset.Mesh) --output $fbx --mesh-name "axe_$id" --material-name axe_mat --report $report
    if ($LASTEXITCODE -ne 0) { throw "Blender conversion failed for axe_$id" }
    Copy-Item -LiteralPath $fbx -Destination (Join-Path $unitDir "axe_${id}_3p.fbx") -Force

    $unit1p = $unitTemplate.Replace('__ID__', $id).Replace('__SHADOW__', 'false')
    $unit3p = $unitTemplate.Replace('__ID__', $id).Replace('__SHADOW__', 'true')
    $assetPackage = $assetPackageTemplate.Replace('__ID__', $id)
    $forwardPackage = $forwardPackageTemplate.Replace('__ID__', $id)
    $material = $materialBase.Replace('__ID__', $id)
    $unit1p | Set-Content -LiteralPath (Join-Path $unitDir "axe_$id.unit") -Encoding utf8NoBOM
    $unit3p | Set-Content -LiteralPath (Join-Path $unitDir "axe_${id}_3p.unit") -Encoding utf8NoBOM
    $assetPackage | Set-Content -LiteralPath (Join-Path $unitDir "axe_${id}_assets.package") -Encoding utf8NoBOM
    $forwardPackage | Set-Content -LiteralPath (Join-Path $unitDir "axe_$id.package") -Encoding utf8NoBOM
    $forwardPackage | Set-Content -LiteralPath (Join-Path $unitDir "axe_${id}_3p.package") -Encoding utf8NoBOM
    $material | Set-Content -LiteralPath (Join-Path $unitDir "axe_$id.material") -Encoding utf8NoBOM

    $channels = @('albedo','normal','roughness','metallic','ao')
    foreach ($channel in $channels) {
        $outPng = Join-Path $textureDir "axe_${id}_$channel.png"
        $sourceName = switch ($channel) {
            'albedo' { $asset.Albedo }
            'normal' { $asset.Normal }
            'roughness' { $asset.Roughness }
            'metallic' { $asset.Metallic }
            'ao' { $asset.Ao }
        }

        if ($sourceName) {
            $arguments = @((Join-Path (Join-Path $SourceRoot $asset.Tex) $sourceName), '-resize', '2048x2048>')
            if ($channel -eq 'roughness' -and $asset.InvertRoughness) { $arguments += '-negate' }
            if ($channel -eq 'metallic' -and $asset.GreyMetallic) { $arguments += '-colorspace'; $arguments += 'Gray' }
            $arguments += $outPng
            & $Magick @arguments
        } else {
            & $Magick -size 2048x2048 xc:white $outPng
        }
        if ($LASTEXITCODE -ne 0) { throw "Texture conversion failed: axe_$id $channel" }

        $srgb = if ($channel -eq 'albedo') { 'true' } else { 'false' }
        $textureDefinition = $textureTemplate.Replace('__ID__', $id).Replace('__CHANNEL__', $channel).Replace('__SRGB__', $srgb)
        $textureDefinition | Set-Content -LiteralPath (Join-Path $textureDir "axe_${id}_$channel.texture") -Encoding utf8NoBOM
    }
}

Write-Host "Converted $($assets.Count) licensed Greataxe illusion assets for issue #597."
