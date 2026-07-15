[CmdletBinding()]
param(
    [string]$SourceRoot = 'C:\Users\danjo\source\repos\_cwv_crowbill_sources',
    [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Blender = 'C:\Program Files\Blender Foundation\Blender 4.4\blender.exe',
    [string]$Magick = 'C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Blender -PathType Leaf)) { throw "Blender not found: $Blender" }
if (-not (Test-Path -LiteralPath $Magick -PathType Leaf)) { throw "ImageMagick not found: $Magick" }

$assets = @(
    @{
        # Player review established that this slimmer Parelaxel model is the
        # intended first Imperial/Kruber presentation, not the Dawi default.
        Id = 'imperial_01'
        Archive = 'dawi_medieval_war_hammer\archive\medieval-war-hammer.zip'
        ArchiveSha256 = 'A90B5FB669AAB55C3FC0C46A21815FC6A4FC573706EFF1B49B144F6B32C107CA'
        Mesh = 'dawi_medieval_war_hammer\source\WarHammerSF.fbx'
        MeshSha256 = 'CC2C8F42A710288846A58FA50FE17AAD923DE41586353380AA01C89141608119'
        TextureRoot = 'dawi_medieval_war_hammer\textures'
        TextureSetSha256 = '6BC6A36BC87A2D0F68953FD9683E2F4D4CF4B2114AB1F6311B0930792AE91627'
        TextureStem = 'WarHammer_Hammer'
        Atlas = $false
    },
    @{
        # Player review established that the heavier soidev model is the
        # intended Dawi/Bardin presentation.
        Id = 'dawi_01'
        Archive = 'imperial_war_hammer\archive\war-hammer.zip'
        ArchiveSha256 = 'A02A997C3E04822C1830597AC3C2457EA5D97AFDBD445F6C30BFDD5EDF565B87'
        Mesh = 'imperial_war_hammer\source\Hammer.fbx'
        MeshSha256 = '68283FD7DFB18F1ECFA96F50A944D5A5E718B74C73A5752B468CD3B5FFB5D8F8'
        TextureRoot = 'imperial_war_hammer\textures'
        TextureSetSha256 = 'CF1D80B947DB37F9464BB3F8F3AFAF63ACD984564F5F4B5771976EFE8B3B90AA'
        Atlas = $true
        AtlasMaterialOrder = 'HammerHead,HammerHandle'
    },
    @{
        Id = 'imperial_02'
        Archive = 'imperial_02_loqual\archive\war-hammer(1).zip'
        ArchiveSha256 = '5741795455E8552114938C1B7B7BAC7BABBF03B2E71076DA1662E06BB53B9C2F'
        Mesh = 'imperial_02_loqual\expanded\source\nested\model\model.dae'
        MeshSha256 = '45643E59FF6B49FFF24A6984BB36B31BB8A8A258DD6141B3DC2DB67CDA7ECACA'
        TextureRoot = 'imperial_02_loqual\expanded\source\nested\model\textures'
        TextureSetSha256 = '31B6CAD4DB7C0E5CA66C02E808CE94917F68E0E88D0F156CA799EE65B428B764'
        Albedo = 'imperial_02_loqual\expanded\source\nested\model\textures\initialShadingGroup_albedo.jpg'
        Normal = 'imperial_02_loqual\expanded\source\nested\model\textures\initialShadingGroup_normal.png'
        Roughness = 'imperial_02_loqual\expanded\source\nested\model\textures\initialShadingGroup_roughness.jpg'
        Metallic = 'imperial_02_loqual\expanded\source\nested\model\textures\initialShadingGroup_metallic.jpg'
        Ao = 'imperial_02_loqual\expanded\source\nested\model\textures\initialShadingGroup_AO.jpg'
        Atlas = $false
    },
    @{
        Id = 'imperial_03'
        Archive = 'imperial_03_medieval_steel\archive\medieval-steel-warhammer.zip'
        ArchiveSha256 = '6B3E6E217936F3E6EBFCA5640F5330047872AF2C28684822D188EBAA5DEB4E38'
        Mesh = 'imperial_03_medieval_steel\expanded\source\nested\model\model.dae'
        MeshSha256 = 'F695D1582CE66FD1CD5E60EC4021770B461A3654A68F49120585E55DE602A382'
        TextureRoot = 'imperial_03_medieval_steel\expanded\source\nested\model\textures'
        TextureSetSha256 = 'E7CA28520B828082A59EE740989A41B22C57A2FF548D335E83C6AAFDE231D3BD'
        Albedo = 'imperial_03_medieval_steel\expanded\source\nested\model\textures\Material.001.01_texture.dds_albedo.jpg'
        Normal = 'imperial_03_medieval_steel\expanded\source\nested\model\textures\Material.001.01_texture.dds_normal.png'
        Roughness = 'imperial_03_medieval_steel\expanded\source\nested\model\textures\Material.001.01_texture.dds_roughness.jpg'
        Metallic = 'imperial_03_medieval_steel\expanded\source\nested\model\textures\Material.001.01_texture.dds_metallic.jpg'
        Ao = 'imperial_03_medieval_steel\expanded\source\nested\model\textures\Material.001.01_texture.dds_AO.jpg'
        Atlas = $false
    },
    @{
        Id = 'imperial_04'
        Archive = 'imperial_04_diablo\archive\warhammer-diablo-ii.zip'
        ArchiveSha256 = 'BDE2DF7A400A16529C83D9474B0ECBD158FB3DBC52B479FEAF4D10777CA0F819'
        Mesh = 'imperial_04_diablo\expanded\source\Warhammer_low.fbx'
        MeshSha256 = '4B844461ED3BC92F44568712E9C0A2BB7441195A668AD601937DD5070EE26421'
        TextureRoot = 'imperial_04_diablo\expanded\textures'
        TextureSetSha256 = 'F61662D220821CF65EC74356202919FF3AA82CC3B3996F17FE1CAD006988E44C'
        Albedo = 'imperial_04_diablo\expanded\textures\lambert1_albedo.jpg'
        Normal = 'imperial_04_diablo\expanded\textures\lambert1_normal.jpg'
        Roughness = 'imperial_04_diablo\expanded\textures\lambert1_roughness.jpg'
        Metallic = 'imperial_04_diablo\expanded\textures\lambert1_metallic.jpg'
        Ao = 'imperial_04_diablo\expanded\textures\lambert1_AO.jpg'
        Atlas = $false
    },
    @{
        Id = 'imperial_05'
        Archive = 'imperial_05_steel\archive\steel-warhammer.zip'
        ArchiveSha256 = '10B7534C8CF4E3C132692D78E2CEE9F7D89AC239615FB8349FF4FB4E93038DD8'
        Mesh = 'imperial_05_steel\expanded\source\nested\model.dae'
        MeshSha256 = 'BE1C897EB14CB6FE9A399B4A6B3247B195E8B4CD4A0052BAA3F53DD435AADDBC'
        TextureRoot = 'imperial_05_steel\expanded\source\nested\textures'
        TextureSetSha256 = '67BC7F20A420563FEA46B5913BBAF2F3D8112BCBCBC3F4561FE6EE20FF641340'
        Albedo = 'imperial_05_steel\expanded\source\nested\textures\Material_texture.dds_albedo.jpg'
        Normal = 'imperial_05_steel\expanded\source\nested\textures\Material_texture.dds_normal.png'
        Roughness = 'imperial_05_steel\expanded\source\nested\textures\Material_texture.dds_roughness.jpg'
        Metallic = 'imperial_05_steel\expanded\source\nested\textures\Material_texture.dds_metallic.jpg'
        Ao = 'imperial_05_steel\expanded\source\nested\textures\Material_texture.dds_AO.jpg'
        Atlas = $false
    }
)

$unitTemplate = @'
materials = {
	crowbill_mat = "units/cwv_crowbill/__ID__/__ID__"
}

renderables = {
	__ID__ = {
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
		filename = "textures/cwv_crowbill/__ID__/__ID_____CHANNEL__"
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

$standardMaterial = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\core\stingray_renderer\shader_import\standard.material'
if (-not (Test-Path -LiteralPath $standardMaterial -PathType Leaf)) { throw "SDK standard material not found: $standardMaterial" }
$materialBase = Get-Content -Raw -LiteralPath $standardMaterial
$materialBase = $materialBase -replace '(?s)textures = \{\s*\}\s*variables = \{.*?\}\s*$', @'
textures = {
	color_map = "textures/cwv_crowbill/__ID__/__ID___albedo"
	normal_map = "textures/cwv_crowbill/__ID__/__ID___normal"
	roughness_map = "textures/cwv_crowbill/__ID__/__ID___roughness"
	metallic_map = "textures/cwv_crowbill/__ID__/__ID___metallic"
	ao_map = "textures/cwv_crowbill/__ID__/__ID___ao"
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
    $archivePath = Join-Path $SourceRoot $asset.Archive
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Source archive missing: $archivePath" }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualHash -ne $asset.ArchiveSha256) {
        throw "Source archive hash mismatch for $($asset.Id): expected $($asset.ArchiveSha256), got $actualHash"
    }
	$meshPath = Join-Path $SourceRoot $asset.Mesh
	$actualMeshHash = (Get-FileHash -LiteralPath $meshPath -Algorithm SHA256).Hash
	if ($actualMeshHash -ne $asset.MeshSha256) {
		throw "Selected mesh hash mismatch for $($asset.Id): expected $($asset.MeshSha256), got $actualMeshHash"
	}
	$textureRecords = Get-ChildItem -LiteralPath (Join-Path $SourceRoot $asset.TextureRoot) -File |
		Sort-Object Name | ForEach-Object { "$($_.Name):$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)" }
	$sha = [Security.Cryptography.SHA256]::Create()
	$textureBytes = [Text.Encoding]::UTF8.GetBytes(($textureRecords -join "`n"))
	$actualTextureSetHash = ([BitConverter]::ToString($sha.ComputeHash($textureBytes))).Replace('-', '')
	if ($actualTextureSetHash -ne $asset.TextureSetSha256) {
		throw "Texture-set hash mismatch for $($asset.Id): expected $($asset.TextureSetSha256), got $actualTextureSetHash"
	}

    $id = $asset.Id
    $unitDir = Join-Path $ModRoot "units\cwv_crowbill\$id"
    $textureDir = Join-Path $ModRoot "textures\cwv_crowbill\$id"
    New-Item -ItemType Directory -Force -Path $unitDir, $textureDir | Out-Null

    $fbx = Join-Path $unitDir "$id.fbx"
    $report = Join-Path $SourceRoot "$id-conversion.json"
    $blenderArguments = @(
        '--background', '--factory-startup', '--python', (Join-Path $PSScriptRoot 'convert_crowbill_mesh.py'), '--',
        '--input', $meshPath,
        '--output', $fbx,
        '--mesh-name', $id,
        '--material-name', 'crowbill_mat',
        '--report', $report
    )
    if ($asset.Atlas) { $blenderArguments += @('--atlas-material-order', $asset.AtlasMaterialOrder) }
    & $Blender @blenderArguments
    if ($LASTEXITCODE -ne 0) { throw "Blender conversion failed for $id" }
    Copy-Item -LiteralPath $fbx -Destination (Join-Path $unitDir "${id}_3p.fbx") -Force

    $unitTemplate.Replace('__ID__', $id).Replace('__SHADOW__', 'false') |
        Set-Content -LiteralPath (Join-Path $unitDir "$id.unit") -Encoding utf8NoBOM
    $unitTemplate.Replace('__ID__', $id).Replace('__SHADOW__', 'true') |
        Set-Content -LiteralPath (Join-Path $unitDir "${id}_3p.unit") -Encoding utf8NoBOM
    $materialBase.Replace('__ID__', $id) |
        Set-Content -LiteralPath (Join-Path $unitDir "$id.material") -Encoding utf8NoBOM

    foreach ($channel in @('albedo', 'normal', 'roughness', 'metallic', 'ao')) {
        $output = Join-Path $textureDir "${id}_$channel.png"
        $directSource = switch ($channel) {
            'albedo' { $asset.Albedo }
            'normal' { $asset.Normal }
            'roughness' { $asset.Roughness }
            'metallic' { $asset.Metallic }
            'ao' { $asset.Ao }
        }
        if ($directSource) {
            & $Magick (Join-Path $SourceRoot $directSource) -resize '2048x2048>' $output
        } elseif ($channel -eq 'ao') {
            & $Magick -size 2048x2048 xc:white $output
        } elseif ($asset.Atlas) {
            $sourceSuffix = switch ($channel) {
                'albedo' { 'BaseColor' }
                'normal' { 'Normal' }
                'roughness' { 'Roughness' }
                'metallic' { 'Metallic' }
            }
            $textureRoot = Join-Path $SourceRoot $asset.TextureRoot
            $head = Join-Path $textureRoot "Hammer_HammerHead_$sourceSuffix.png"
            $handle = Join-Path $textureRoot "Hammer_HammerHandle_$sourceSuffix.png"
            & $Magick $head $handle +append -resize '2048x2048>' $output
        } else {
            $sourceSuffix = switch ($channel) {
                'albedo' { 'BaseColor' }
                'normal' { 'Normal' }
                'roughness' { 'Roughness' }
                'metallic' { 'Metallic' }
            }
            $source = Join-Path (Join-Path $SourceRoot $asset.TextureRoot) "$($asset.TextureStem)_$sourceSuffix.png"
            & $Magick $source -resize '2048x2048>' $output
        }
        if ($LASTEXITCODE -ne 0) { throw "Texture conversion failed: $id $channel" }
        $srgb = if ($channel -eq 'albedo') { 'true' } else { 'false' }
        $textureTemplate.Replace('__ID__', $id).Replace('__CHANNEL__', $channel).Replace('__SRGB__', $srgb) |
            Set-Content -LiteralPath (Join-Path $textureDir "${id}_$channel.texture") -Encoding utf8NoBOM
    }
}

Write-Host "Converted $($assets.Count) approved CC-BY Crowbill assets for issue #604."
