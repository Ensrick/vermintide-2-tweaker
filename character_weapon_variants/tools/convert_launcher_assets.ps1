[CmdletBinding()]
param(
    # Extracted source payload (output.fbx + the three PBR PNGs). The raw archive
    # and this expanded payload are user-supplied and stay OUTSIDE the repo.
    [string]$SourceDir = 'C:\Users\danjo\source\repos\_cwv_launcher_sources',
    # Optional: the untouched original archive, verified by SHA-256 before any
    # derived resource is produced. Never modified or deleted by this script.
    [string]$Archive = 'C:\Users\danjo\Downloads\fa676a4e-4636-40d5-a240-9398ec289edb.zip',
    [string]$ArchiveSha256 = 'CC1230D2FEAE0FCBFFA3FE099A3C0ECB2EE58BA4B84A6B716EF341208D3C6A76',
    [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Blender = 'C:\Program Files\Blender Foundation\Blender 4.4\blender.exe',
    [string]$Magick = 'C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe',
    [int]$TargetTris = 12000,
    [switch]$SkipMesh
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Blender -PathType Leaf)) { throw "Blender not found: $Blender" }
if (-not (Test-Path -LiteralPath $Magick -PathType Leaf)) { throw "ImageMagick not found: $Magick" }

# Provenance guard: the user-supplied archive carries no author/title/source/
# license metadata, so its SHA-256 is the only stable identity. Verify it if the
# archive is present; do not silently derive from an unverified/renamed download.
if (Test-Path -LiteralPath $Archive -PathType Leaf) {
    $actual = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
    if ($actual -ne $ArchiveSha256) {
        throw "Source archive hash mismatch: expected $ArchiveSha256, got $actual"
    }
    Write-Host "Verified user-supplied archive SHA-256 $ArchiveSha256"
} else {
    Write-Warning "Original archive not found at $Archive; proceeding from extracted $SourceDir only."
}

$id = 'launcher_01'
$fbxSource = Join-Path $SourceDir 'output.fbx'
$albedoSource = Join-Path $SourceDir 'texture_pbr_20250901.png'
$normalSource = Join-Path $SourceDir 'texture_pbr_20250901_normal.png'
# Packed glTF metallicRoughness map: R = constant pad, G = roughness, B = metallic.
$packedSource = Join-Path $SourceDir 'texture_pbr_20250901_metallic-texture_pbr_20250901_roughness.png'
foreach ($f in @($fbxSource, $albedoSource, $normalSource, $packedSource)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "Missing source file: $f" }
}

$unitDir = Join-Path $ModRoot "units\cwv_launcher\$id"
$textureDir = Join-Path $ModRoot "textures\cwv_launcher\$id"
New-Item -ItemType Directory -Force -Path $unitDir, $textureDir | Out-Null

# --- Mesh: decimate + normalize + Stingray-safe material collapse (1P + _3p) ---
$fbx = Join-Path $unitDir "$id.fbx"
if (-not $SkipMesh) {
    $report = Join-Path $SourceDir "$id-conversion.json"
    & $Blender --background --factory-startup --python (Join-Path $PSScriptRoot 'convert_launcher_mesh.py') -- `
        --input $fbxSource --output $fbx --mesh-name $id --material-name 'launcher_mat' `
        --target-tris $TargetTris --report $report
    if ($LASTEXITCODE -ne 0) { throw "Blender conversion failed for $id" }
}
if (-not (Test-Path -LiteralPath $fbx -PathType Leaf)) { throw "Expected mesh missing: $fbx (run without -SkipMesh)" }
Copy-Item -LiteralPath $fbx -Destination (Join-Path $unitDir "${id}_3p.fbx") -Force

# --- Unit files: borrow the engine standard material through a short slot name ---
$unitTemplate = @'
materials = {
	launcher_mat = "units/cwv_launcher/__ID__/__ID__"
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
$unitTemplate.Replace('__ID__', $id).Replace('__SHADOW__', 'false') |
    Set-Content -LiteralPath (Join-Path $unitDir "$id.unit") -Encoding utf8NoBOM
$unitTemplate.Replace('__ID__', $id).Replace('__SHADOW__', 'true') |
    Set-Content -LiteralPath (Join-Path $unitDir "${id}_3p.unit") -Encoding utf8NoBOM

# --- Material: full copy of the SDK standard material rebound to our channels ---
$standardMaterial = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\core\stingray_renderer\shader_import\standard.material'
if (-not (Test-Path -LiteralPath $standardMaterial -PathType Leaf)) { throw "SDK standard material not found: $standardMaterial" }
$materialBase = Get-Content -Raw -LiteralPath $standardMaterial
$materialBase = $materialBase -replace '(?s)textures = \{\s*\}\s*variables = \{.*?\}\s*$', @'
textures = {
	color_map = "textures/cwv_launcher/__ID__/__ID___albedo"
	normal_map = "textures/cwv_launcher/__ID__/__ID___normal"
	roughness_map = "textures/cwv_launcher/__ID__/__ID___roughness"
	metallic_map = "textures/cwv_launcher/__ID__/__ID___metallic"
	ao_map = "textures/cwv_launcher/__ID__/__ID___ao"
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
$materialBase.Replace('__ID__', $id) |
    Set-Content -LiteralPath (Join-Path $unitDir "$id.material") -Encoding utf8NoBOM

# --- Textures: unpack the packed glTF map, cap at 2048, emit PNG + .texture ---
$textureTemplate = @'
common = {
	input = {
		filename = "textures/cwv_launcher/__ID__/__ID_____CHANNEL__"
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

foreach ($channel in @('albedo', 'normal', 'roughness', 'metallic', 'ao')) {
    $output = Join-Path $textureDir "${id}_$channel.png"
    switch ($channel) {
        'albedo'    { & $Magick $albedoSource -resize '2048x2048>' -alpha off $output }
        'normal'    { & $Magick $normalSource -resize '2048x2048>' -alpha off $output }
        'roughness' { & $Magick $packedSource -channel G -separate -resize '2048x2048>' $output }
        'metallic'  { & $Magick $packedSource -channel B -separate -resize '2048x2048>' $output }
        'ao'        { & $Magick -size 2048x2048 xc:white $output }
    }
    if ($LASTEXITCODE -ne 0) { throw "Texture conversion failed: $id $channel" }
    $srgb = if ($channel -eq 'albedo') { 'true' } else { 'false' }
    $textureTemplate.Replace('__ID__', $id).Replace('__CHANNEL__', $channel).Replace('__SRGB__', $srgb) |
        Set-Content -LiteralPath (Join-Path $textureDir "${id}_$channel.texture") -Encoding utf8NoBOM
}

Write-Host "Converted user-supplied Outrider launcher asset '$id' for issue #627."
