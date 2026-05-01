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
    "career_tweaker"       = "3716286199"
    "enemy_tweaker"        = "3716780252"
    "character_weapon_variants" = "3716869446"
}

function Deploy-SdkOut($sourceDir, $targetDir) {
    # SDK layout: extensionless bundle files; rename to .mod_bundle on copy
    Get-ChildItem $sourceDir -Filter "*.mod" | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $targetDir $_.Name) -Force
    }
    Get-ChildItem $sourceDir -File | Where-Object { $_.Extension -eq '' } | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $targetDir ($_.Name + '.mod_bundle')) -Force
    }
}

function Deploy-VmbOut($sourceDir, $targetDir) {
    # VMB layout: bundleV2/ already contains *.mod_bundle and *.mod with correct names
    Get-ChildItem $sourceDir -File | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $targetDir $_.Name) -Force
    }
}

function Clean-StaleBundles($targetDir) {
    # Remove old *.mod and *.mod_bundle so a renamed .mod or new bundle hash
    # doesn't sit alongside the old one (would cause duplicate new_mod() registration).
    Get-ChildItem $targetDir -File -Filter "*.mod" -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem $targetDir -File -Filter "*.mod_bundle" -ErrorAction SilentlyContinue | Remove-Item -Force
}

foreach ($mod in $Mods) {
    $vmbOut = Join-Path $root "$mod\bundleV2"
    $sdkOut = Join-Path $root "$mod\.build\OUT"

    if (Test-Path $vmbOut) {
        $out = $vmbOut
        $layout = "vmb"
    } elseif (Test-Path $sdkOut) {
        $out = $sdkOut
        $layout = "sdk"
    } else {
        throw "Build output not found for $mod (looked for $vmbOut and $sdkOut)"
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
    Clean-StaleBundles $workshopDir
    if ($layout -eq "vmb") { Deploy-VmbOut $out $workshopDir } else { Deploy-SdkOut $out $workshopDir }

    if ($layout -eq "sdk") {
        # SDK pipeline keeps an upload/content/ staging dir for ugc_tool uploads
        $uploadContent = Join-Path $root "$mod\upload\content"
        New-Item -ItemType Directory -Force -Path $uploadContent | Out-Null
        Clean-StaleBundles $uploadContent
        Deploy-SdkOut $out $uploadContent
    }
    # VMB pipeline uses bundleV2/ directly with itemV2.cfg's content="bundleV2"; no staging needed.

    Write-Host "Deployed $mod ($layout) -> Workshop ($workshopId)"
    Get-ChildItem $workshopDir | ForEach-Object { Write-Host "  $($_.Name)  ($($_.Length) bytes)" }
}
