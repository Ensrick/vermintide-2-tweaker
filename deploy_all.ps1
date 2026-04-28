param(
    [string[]]$Mods = @("chaos_wastes_tweaker", "weapon_tweaker", "general_tweaker")
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$workshopBase = "C:\Program Files (x86)\Steam\steamapps\workshop\content\552500"

# Map mod names to their Workshop IDs
$workshopIds = @{
    "chaos_wastes_tweaker" = "3712929235"
    "weapon_tweaker"       = "3712896117"
    "general_tweaker"      = "3713619122"
    "cosmetics_tweaker"    = "3715714222"
    "career_tweaker"       = $null  # TBD
}

function Deploy-ToDir($sourceDir, $targetDir) {
    # Copy .mod files as-is
    Get-ChildItem $sourceDir -Filter "*.mod" | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $targetDir $_.Name) -Force
    }
    # Copy bundle files (no extension) with .mod_bundle suffix
    Get-ChildItem $sourceDir -File | Where-Object { $_.Extension -eq '' } | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $targetDir ($_.Name + '.mod_bundle')) -Force
    }
}

foreach ($mod in $Mods) {
    $out = Join-Path $root "$mod\.build\OUT"

    if (-not (Test-Path $out)) {
        throw "Build output not found for $mod at $out"
    }

    $workshopId = $workshopIds[$mod]
    if (-not $workshopId) {
        Write-Host "Skipping $mod - no Workshop ID configured"
        continue
    }

    $workshopDir = Join-Path $workshopBase $workshopId
    if (-not (Test-Path $workshopDir)) {
        Write-Host "WARNING: Workshop folder $workshopDir does not exist - is the mod subscribed?"
        continue
    }

    # Deploy to Workshop folder (for hot reload / dev)
    Deploy-ToDir $out $workshopDir

    # Also update upload/content (for Workshop uploads)
    $uploadContent = Join-Path $root "$mod\upload\content"
    New-Item -ItemType Directory -Force -Path $uploadContent | Out-Null
    Deploy-ToDir $out $uploadContent

    Write-Host "Deployed $mod -> Workshop ($workshopId) + upload/content"
    Get-ChildItem $workshopDir | ForEach-Object { Write-Host "  $($_.Name)  ($($_.Length) bytes)" }
}
