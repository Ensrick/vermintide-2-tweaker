<#
.SYNOPSIS
    Generates all asset files for a new dynamic-cosmetic-portrait entry.

.DESCRIPTION
    Single source of truth for portrait asset generation. Producing assets
    by hand is error-prone (history: v0.1.0/v0.1.1/v0.1.2 each shipped
    portraits with the wrong dimensions or missing alpha). This script
    encodes the correct workflow:

      1. Medium (110x130): copy source PNG verbatim. No resize, no alpha
         change. The hero-select widget renders this at native 110x130.
      2. HUD    (86x108) : bicubic-downscale RGB from the 110x130 source,
         then composite the alpha channel from a reference HUD portrait
         (default: portrait_kruber_mercenary_hat_0001.png). The shaped
         alpha is what cuts the portrait into the hex/shield silhouette
         that fits the in-game frame widget's cutout.
      3. Small  (60x70)  : same as HUD, with the small reference.

    The alpha mask shape is identical for every portrait at a given size
    because it is defined by the in-game frame widget's octagonal cutout,
    NOT by per-portrait content. Borrowing alpha from any working portrait
    yields the correct mask. mercenary_hat_0001 (Estalia) is the canonical
    reference and is always present in the mod.

    (#526) The HUD mask MUST conform to tools/vanilla_hud_alpha_mask_86x108.png
    (the vanilla 84x108 hud-portrait silhouette, consensus of 19 extracted
    vanilla portraits, scaled to 86x108 = the exact rect every hud surface
    draws: unit frames, Tab list, end-of-round score). The pre-#526 mask was
    content-derived (wider than the vanilla window + touched the canvas top),
    so portraits bled outside the octagonal frame on the mission-completion
    score screen. This script now FAILS if a generated HUD png has any
    opaque pixel outside that canonical silhouette.

    Writes the standalone medium .texture/.material files, then rebuilds the
    shared HUD/small atlas and VMF descriptor. Verifies the output and prints
    next steps for wiring the portrait lookup maps and package entries.

.PARAMETER SourcePng
    Path to the 110x130 source PNG (e.g. "Kruber Portrait (Hellequin).png").

.PARAMETER HatKey
    The cosmetic key as returned by CosmeticUtils.get_cosmetic_slot, with
    the character prefix INCLUDED for the in-mod filenames. For example,
    if the cosmetic key is "mercenary_hat_0003" and the character is
    Kruber, pass: "kruber_mercenary_hat_0003"

    See CHARACTER_COSMETIC_CATALOG.md for the cosmetic-key list.

.PARAMETER ReferenceKey
    Optional. The in-mod key whose alpha channel will be borrowed for the
    HUD and small variants. Defaults to "kruber_mercenary_hat_0001"
    (Estalia). Use any key whose HUD/small files are already in the mod
    and verified to display correctly.

.EXAMPLE
    .\tools\add_portrait.ps1 -SourcePng "D:\Game Mods\Vermintide 2 modding\Kruber Portrait (Hellequin).png" -HatKey "kruber_mercenary_hat_1002"

.NOTES
    DO NOT modify this script's resize or alpha-compositing steps without
    reading DEVELOPMENT.md "Adding a new portrait" section AND testing the
    result in-game on at least one HUD widget AND the hero-select screen.
    Both cosmetics_tweaker v0.7.x and dynamic_cosmetic_portraits v0.1.x
    development burned multiple sessions on this exact problem.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePng,

    [Parameter(Mandatory = $true)]
    [string]$HatKey,

    [Parameter(Mandatory = $false)]
    [string]$ReferenceKey = "kruber_mercenary_hat_0001"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# Resolve mod root (the script lives in <mod>/tools/)
$modRoot = Split-Path -Parent $PSScriptRoot
$texDir  = Join-Path $modRoot "gui\1080p\single_textures\custom_portraits"
$matDir  = Join-Path $modRoot "materials\ui"

if (-not (Test-Path $SourcePng))                  { throw "Source PNG not found: $SourcePng" }
if (-not (Test-Path $texDir))                     { throw "Texture dir missing: $texDir" }
if (-not (Test-Path $matDir))                     { throw "Material dir missing: $matDir" }

# Verify source is 110x130 (the canonical authoring size)
$srcImg = New-Object System.Drawing.Bitmap $SourcePng
$srcW = $srcImg.Width; $srcH = $srcImg.Height
$srcImg.Dispose()
if ($srcW -ne 110 -or $srcH -ne 130) {
    throw "Source PNG must be 110x130. Got ${srcW}x${srcH} for: $SourcePng"
}

# Verify reference HUD/small files exist for alpha borrow
$refHUD   = Join-Path $texDir "portrait_$ReferenceKey.png"
$refSmall = Join-Path $texDir "small_portrait_$ReferenceKey.png"
foreach ($p in @($refHUD, $refSmall)) {
    if (-not (Test-Path $p)) { throw "Reference file missing (needed for alpha borrow): $p" }
}

# ---------------- Medium (110x130, no resize, no mask) ----------------
$mediumOut = Join-Path $texDir "medium_portrait_$HatKey.png"
Copy-Item $SourcePng $mediumOut -Force
Write-Output "[medium] $mediumOut (110x130, source verbatim)"

# ---------------- HUD (86x108) and Small (60x70) ----------------
$variants = @(
    @{ Prefix = "";       W = 86; H = 108; Ref = $refHUD;   Label = "HUD"   },
    @{ Prefix = "small_"; W = 60; H = 70;  Ref = $refSmall; Label = "small" }
)
$source = New-Object System.Drawing.Bitmap $SourcePng
foreach ($v in $variants) {
    # Bicubic-downscale RGB
    $resized = New-Object System.Drawing.Bitmap $v.W, $v.H
    $g = [System.Drawing.Graphics]::FromImage($resized)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.DrawImage($source, 0, 0, $v.W, $v.H)
    $g.Dispose()

    # Composite RGB(resized) + Alpha(reference) -> output
    $refBmp = New-Object System.Drawing.Bitmap $v.Ref
    if ($refBmp.Width -ne $v.W -or $refBmp.Height -ne $v.H) {
        $refBmp.Dispose(); $resized.Dispose(); $source.Dispose()
        throw ("Reference file {0} is {1}x{2}, expected {3}x{4}" -f $v.Ref, $refBmp.Width, $refBmp.Height, $v.W, $v.H)
    }
    $output = New-Object System.Drawing.Bitmap $v.W, $v.H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for ($y = 0; $y -lt $v.H; $y++) {
        for ($x = 0; $x -lt $v.W; $x++) {
            $rgb   = $resized.GetPixel($x, $y)
            $alpha = $refBmp.GetPixel($x, $y).A
            $output.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($alpha, $rgb.R, $rgb.G, $rgb.B))
        }
    }
    $outPath = Join-Path $texDir "$($v.Prefix)portrait_$HatKey.png"
    $output.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output ("[{0}] {1} ({2}x{3}, RGB=resized, Alpha={4})" -f $v.Label, $outPath, $v.W, $v.H, (Split-Path -Leaf $v.Ref))

    $resized.Dispose(); $refBmp.Dispose(); $output.Dispose()
}
$source.Dispose()

# ---------------- Standalone medium .texture and .material files ----------------
# HUD/small variants are compiled through dcp_portrait_atlas (#526). Creating
# standalone metadata for those variants would make it easier to accidentally
# register them through VMF's Gui.bitmap fallback again.
foreach ($prefix in @("medium_")) {
    $texName = "$($prefix)portrait_$HatKey"
    $texPath = "gui/1080p/single_textures/custom_portraits/$texName"
    # Medium portraits use the proven visible standalone Gui shader. The
    # incompatible masked-gradient standalone experiment made cutout portraits
    # fully transparent; HUD/small now follow vanilla through the private atlas.
    $shader = "gui:DIFFUSE_MAP"

    $textureContent = @"
common = {
	input = {
		filename = "$texPath"
	}
	output = {
		apply_processing = true
		category = ""
		cut_alpha_threshold = 0.5
		enable_cut_alpha_threshold = false
		format = "DXT5"
		mipmap_filter = "kaiser"
		mipmap_filter_wrap_mode = "mirror"
		mipmap_keep_original = false
		mipmap_num_largest_steps_to_discard = 0
		mipmap_num_smallest_steps_to_discard = 0
		srgb = true
		streamable = false
	}
}
"@
    [System.IO.File]::WriteAllText((Join-Path $texDir "$texName.texture"), $textureContent)

    $materialContent = @"
$texName = {
	material_contexts = {
		surface_material = ""
	}

	shader = "$shader"

	textures = {
		diffuse_map = "$texPath"
	}

	variables = {
	}
}
"@
    [System.IO.File]::WriteAllText((Join-Path $matDir "$texName.material"), $materialContent)
    Write-Output "[meta] $texName.{texture,material}"
}

# ---------------- Verify output ----------------
# (#526) HUD silhouette conformance: no opaque pixel outside the canonical
# vanilla hud mask, or the portrait bleeds outside the octagonal frame on
# the mission-completion score screen (and every other 86x108 hud surface).
$canonicalMask = Join-Path $PSScriptRoot "vanilla_hud_alpha_mask_86x108.png"
if (-not (Test-Path $canonicalMask)) {
    throw "Canonical mask missing (needed for silhouette conformance check): $canonicalMask"
}
$maskBmp = New-Object System.Drawing.Bitmap $canonicalMask
$hudBmp  = New-Object System.Drawing.Bitmap (Join-Path $texDir "portrait_$HatKey.png")
$bleed = 0
for ($y = 0; $y -lt 108; $y++) {
    for ($x = 0; $x -lt 86; $x++) {
        if ($hudBmp.GetPixel($x, $y).A -ge 128 -and $maskBmp.GetPixel($x, $y).R -lt 128) { $bleed++ }
    }
}
$maskBmp.Dispose(); $hudBmp.Dispose()
if ($bleed -gt 0) {
    throw "HUD portrait has $bleed opaque pixel(s) outside the canonical vanilla silhouette (frame bleed, #526). Fix the reference alpha (borrow from a conformant portrait) and re-run."
}
Write-Output "[ok] HUD silhouette conformance: 0 opaque pixels outside vanilla_hud_alpha_mask_86x108.png"

Write-Output ""
Write-Output "Verification (alpha at corners):"
foreach ($prefix in @("", "medium_", "small_")) {
    $p = Join-Path $texDir "$($prefix)portrait_$HatKey.png"
    $img = New-Object System.Drawing.Bitmap $p
    $tl = $img.GetPixel(0, 0).A
    $tr = $img.GetPixel($img.Width - 1, 0).A
    $bl = $img.GetPixel(0, $img.Height - 1).A
    $cn = $img.GetPixel([int]($img.Width / 2), [int]($img.Height / 2)).A
    $expected = if ($prefix -eq "medium_") { "TL=A>=240, corners ~opaque, center=A255" } else { "TL=A0, TR=A0, BL=A0, center=A255" }
    $actual = "TL=A$tl TR=A$tr BL=A$bl center=A$cn"
    $okSign = "?"
    if ($prefix -eq "medium_") { $okSign = if ($tl -ge 240 -and $cn -eq 255) { "OK" } else { "WARN" } }
    else                       { $okSign = if ($tl -eq 0 -and $tr -eq 0 -and $bl -eq 0 -and $cn -eq 255) { "OK" } else { "WARN" } }
    Write-Output ("  [$okSign] $($prefix)portrait_$HatKey.png ($($img.Width)x$($img.Height)): $actual  | expected: $expected")
    $img.Dispose()
}

Write-Output ""
& (Join-Path $PSScriptRoot "rebuild_portrait_atlas.ps1")

Write-Output ""
Write-Output "Asset files created and portrait atlas rebuilt. NEXT STEPS (manual):"
Write-Output "  1. dynamic_cosmetic_portraits.lua"
Write-Output "       - Add the medium path to _PORTRAIT_STANDALONE_MATERIALS"
Write-Output "       - Add entry to _hat_portrait_map or _skin_portrait_map"
Write-Output "  2. dynamic_cosmetic_portraits_data.lua"
Write-Output "       - Add only the medium name to _texture_names"
Write-Output "  3. resource_packages/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.package"
Write-Output "       - Add only the medium material + texture paths"
Write-Output "  4. Bump MOD_VERSION in dynamic_cosmetic_portraits.lua"
Write-Output "  5. Use the repository's serialized ship lane for build/deploy/upload"
