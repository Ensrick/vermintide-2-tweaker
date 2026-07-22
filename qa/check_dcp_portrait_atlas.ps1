# check_dcp_portrait_atlas.ps1 - deterministic source/atlas alpha gate (#526).

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$modRoot = Join-Path $repoRoot 'dynamic_cosmetic_portraits'
$sourceDir = Join-Path $modRoot 'gui\1080p\single_textures\custom_portraits'
$maskPath = Join-Path $modRoot 'tools\vanilla_hud_alpha_mask_86x108.png'
$atlasPath = Join-Path $modRoot 'textures\dynamic_cosmetic_portraits\dcp_portrait_atlas.png'
$descriptorPath = Join-Path $modRoot 'materials\dynamic_cosmetic_portraits\dcp_portrait_atlas.lua'
$atlasSize = 512
$errors = New-Object System.Collections.Generic.List[string]

foreach ($path in @($sourceDir, $maskPath, $atlasPath, $descriptorPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        $errors.Add("Missing required DCP atlas input: $path")
    }
}
if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "[dcp_portrait_atlas] ERROR -- $_" -ForegroundColor Red }
    exit 2
}

$descriptor = Get-Content -LiteralPath $descriptorPath -Raw
$pattern = '(?ms)^\s{4}([a-z0-9_]+) = \{\s+size = \{\s*(\d+),\s*(\d+)\s*\},\s+uv00 = \{\s*([0-9.]+),\s*([0-9.]+)\s*\},\s+uv11 = \{\s*([0-9.]+),\s*([0-9.]+)\s*\},'
$matches = [regex]::Matches($descriptor, $pattern)
if ($matches.Count -ne 24) {
    $errors.Add("Atlas descriptor has $($matches.Count) sprites; expected 24.")
}

$atlas = New-Object System.Drawing.Bitmap $atlasPath
$mask = New-Object System.Drawing.Bitmap $maskPath
try {
    if ($atlas.Width -ne $atlasSize -or $atlas.Height -ne $atlasSize) {
        $errors.Add("Atlas is $($atlas.Width)x$($atlas.Height); expected ${atlasSize}x${atlasSize}.")
    }
    if ($mask.Width -ne 86 -or $mask.Height -ne 108) {
        $errors.Add("Canonical HUD mask is $($mask.Width)x$($mask.Height); expected 86x108.")
    }

    foreach ($match in $matches) {
        $name = $match.Groups[1].Value
        $width = [int]$match.Groups[2].Value
        $height = [int]$match.Groups[3].Value
        $x = [int][Math]::Round(([double]$match.Groups[4].Value) * $atlasSize)
        $y = [int][Math]::Round(([double]$match.Groups[5].Value) * $atlasSize)
        $x1 = [int][Math]::Round(([double]$match.Groups[6].Value) * $atlasSize)
        $y1 = [int][Math]::Round(([double]$match.Groups[7].Value) * $atlasSize)
        $sourcePath = Join-Path $sourceDir "$name.png"
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            $errors.Add("Descriptor sprite has no source PNG: $name")
            continue
        }
        if ($x1 - $x -ne $width -or $y1 - $y -ne $height) {
            $errors.Add("Descriptor UV span does not match size for $name.")
            continue
        }

        $source = New-Object System.Drawing.Bitmap $sourcePath
        try {
            if ($source.Width -ne $width -or $source.Height -ne $height) {
                $errors.Add("Source dimensions do not match descriptor for $name.")
                continue
            }
            $mismatch = 0
            for ($py = 0; $py -lt $height; $py++) {
                for ($px = 0; $px -lt $width; $px++) {
                    if ($source.GetPixel($px, $py).ToArgb() -ne $atlas.GetPixel($x + $px, $y + $py).ToArgb()) {
                        $mismatch++
                    }
                    if ($width -eq 86 -and
                        $source.GetPixel($px, $py).A -ne $mask.GetPixel($px, $py).R) {
                        $errors.Add("HUD alpha differs from canonical mask for $name at ($px,$py).")
                        $py = $height
                        break
                    }
                }
            }
            if ($mismatch -gt 0) {
                $errors.Add("Atlas differs from source for $name at $mismatch pixel(s).")
            }
        }
        finally {
            $source.Dispose()
        }
    }
}
finally {
    $mask.Dispose()
    $atlas.Dispose()
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "[dcp_portrait_atlas] ERROR -- $_" -ForegroundColor Red }
    exit 2
}

if (-not $Quiet) {
    Write-Host '[dcp_portrait_atlas] OK -- 24 sprites are pixel-exact; all HUD alpha matches the canonical mask.' -ForegroundColor Green
}
exit 0
