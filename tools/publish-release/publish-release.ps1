# tools/publish-release/publish-release.ps1
#
# Builds every published VMB mod, zips each bundleV2/ directory, generates a manifest.json,
# and pushes the whole set as a GitHub release on Ensrick/vermintide-2-tweaker. The
# vt2-mod-updater tool consumes the release manifest to deploy bundles into friends' Steam
# Workshop folders.
#
# Usage:
#   .\publish-release.ps1                       # builds all, releases with auto-generated date tag
#   .\publish-release.ps1 -Tag mods-2026-05-21  # explicit tag name
#   .\publish-release.ps1 -SkipBuild            # use existing bundleV2/ outputs (faster iter)
#   .\publish-release.ps1 -DryRun               # build + stage but don't create the GH release
#
# Requires: gh CLI authenticated to github.com (Ensrick); VMBLauncher.exe present at the
# canonical path. Does NOT upload to Steam Workshop — that's still VMBLauncher's job.

[CmdletBinding()]
param(
    [string]$Tag,
    [switch]$SkipBuild,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$launcher = Join-Path $repoRoot 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
if (-not (Test-Path $launcher)) {
    throw "VMBLauncher not found at $launcher. Build it first via tools/vmb-launcher/publish.ps1 -SkipOpen"
}

# ---- Static-analysis lint gate ----
# Catches the two recurring bug classes that have cost multiple version bumps:
#   1. Duplicate VMF hook registration (silently dropped - burns versions on cim)
#   2. Lua forward-reference bugs (cosmetics_tweaker has shipped this 6+ times)
# Exit code 2 = hard fail (duplicate hooks). Exit code 1 = warning only
# (forward-ref candidates). We BLOCK on exit 2 - a release with a known silently-
# dropped hook would push a broken bundle to every friend.
# Comments + throw strings are ASCII only - PowerShell parses .ps1 as
# Windows-1252 by default and mangles em-dashes (memory:
# feedback_ps5_getcontent_utf8).
$linter = Join-Path $repoRoot 'tools\mod-lint\lint-mod.ps1'
if (Test-Path $linter) {
    Write-Host ""
    Write-Host "==> Static-analysis lint (tools/mod-lint/lint-mod.ps1)" -ForegroundColor Cyan
    & $linter -Json
    $lintExit = $LASTEXITCODE
    if ($lintExit -eq 2) {
        throw "Lint gate FAILED (duplicate VMF hook registration detected). Fix the duplicates above before publishing - VMF silently drops the second hook and the released bundle will be broken."
    }
    if ($lintExit -eq 1) {
        Write-Warning "Lint gate produced warnings (forward-ref candidates). Continuing - these are non-blocking, but verify each helper has an explicit forward declaration if a closure references it before its definition line."
    }
} else {
    Write-Warning "Linter not found at $linter - skipping pre-release lint gate."
}

$stage = Join-Path $repoRoot '.release-stage'
if (Test-Path $stage) { Get-ChildItem $stage -Recurse | Remove-Item -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

if (-not $Tag) { $Tag = "mods-$(Get-Date -Format yyyy-MM-dd)" }

# Mod inventory: (folder, mod_id, friendly_name).
# Material_hijack_patched has no MOD_VERSION variable — pulled from cfg description as fallback.
# 2026-05-21: modded_progression added after first-time Workshop publish (ID 3730422873, private).
$mods = @(
    @{ Folder='weapon_tweaker';             Id='wt';                            Name='Weapon Tweaker' }
    @{ Folder='chaos_wastes_tweaker';       Id='ct';                            Name='Chaos Wastes Tweaker' }
    @{ Folder='general_tweaker';            Id='gt';                            Name='General Tweaker' }
    @{ Folder='cosmetics_tweaker';          Id='cosmetics_tweaker';             Name='Cosmetics Tweaker' }
    @{ Folder='dynamic_cosmetic_portraits'; Id='dynamic_cosmetic_portraits';    Name='Dynamic Cosmetic Portraits' }
    @{ Folder='career_tweaker';             Id='crt';                           Name='Career Tweaker' }
    @{ Folder='enemy_tweaker';              Id='enemy_tweaker';                 Name='Enemy Tweaker' }
    @{ Folder='character_weapon_variants';  Id='character_weapon_variants';     Name='Character Weapon Variants' }
    @{ Folder='crafting_in_modded';         Id='cim';                           Name='Crafting In Modded' }
    @{ Folder='la_prefix_patch';            Id='la_prefix_patch';               Name="LA Prefix Patch" }
    @{ Folder='event_tweaker';              Id='event_tweaker';                 Name='Event Tweaker' }
    @{ Folder='modded_progression';         Id='modded_progression';            Name='Modded Progression' }
    @{ Folder='lobby_tweaker';              Id='lobby_tweaker';                 Name='Lobby Tweaker' }
    @{ Folder='buff_tweaker';               Id='bt';                            Name='Buff Tweaker' }
    @{ Folder='verminious_dreams_lighting'; Id='verminious_dreams_lighting';    Name='Verminious Dreams Lighting' }
)

function Read-ModVersion {
    param([string]$ModFolderPath, [string]$FolderName, [string]$ModId)
    # ModFolderPath = absolute path to the mod directory.
    # FolderName    = bare folder name (e.g. "cosmetics_tweaker"); also matches the lua filename.
    $luaPath = Join-Path $ModFolderPath "scripts\mods\$FolderName\$FolderName.lua"
    if (Test-Path $luaPath) {
        $txt = [System.IO.File]::ReadAllText($luaPath, [System.Text.Encoding]::UTF8)
        if ($txt -match 'MOD_VERSION\s*=\s*"([^"]+)"') { return $matches[1] }
    }
    return ''
}

function Read-WorkshopId {
    param([string]$ModFolder)
    $cfg = Join-Path $ModFolder 'itemV2.cfg'
    if (-not (Test-Path $cfg)) { return '' }
    $txt = [System.IO.File]::ReadAllText($cfg, [System.Text.Encoding]::UTF8)
    if ($txt -match 'published_id\s*=\s*(\d+)L') { return $matches[1] }
    return ''
}

function Read-Visibility {
    param([string]$ModFolder)
    $cfg = Join-Path $ModFolder 'itemV2.cfg'
    if (-not (Test-Path $cfg)) { return '' }
    $txt = [System.IO.File]::ReadAllText($cfg, [System.Text.Encoding]::UTF8)
    if ($txt -match 'visibility\s*=\s*"([^"]+)"') { return $matches[1] }
    return ''
}

$manifestMods = @()
$assetPaths   = @()

foreach ($m in $mods) {
    $modPath  = Join-Path $repoRoot $m.Folder
    if (-not (Test-Path $modPath)) {
        Write-Warning "Skipping $($m.Folder): folder missing"
        continue
    }

    $version    = Read-ModVersion -ModFolderPath $modPath -FolderName $m.Folder -ModId $m.Id
    $workshopId = Read-WorkshopId -ModFolder $modPath
    $visibility = Read-Visibility -ModFolder $modPath

    if (-not $workshopId) {
        Write-Warning "Skipping $($m.Folder): no published_id (unpublished mod)"
        continue
    }
    if (-not $version) {
        Write-Warning "$($m.Folder) has no MOD_VERSION; falling back to '$Tag'"
        $version = $Tag
    }

    if (-not $SkipBuild) {
        Write-Host ""
        Write-Host "==> Building $($m.Folder)" -ForegroundColor Cyan
        & $launcher build $m.Folder
        if ($LASTEXITCODE -ne 0) { throw "Build failed for $($m.Folder) (exit $LASTEXITCODE)" }
    }

    $bundleDir = Join-Path $modPath 'bundleV2'
    if (-not (Test-Path $bundleDir)) {
        throw "Bundle output missing for $($m.Folder) at $bundleDir"
    }

    # Stage: copy bundleV2/* into <stage>/<mod_id>/, write version sidecar, zip.
    $modStage = Join-Path $stage $m.Id
    New-Item -ItemType Directory -Force -Path $modStage | Out-Null
    Copy-Item (Join-Path $bundleDir '*') $modStage -Recurse -Force
    Set-Content -Path (Join-Path $modStage 'vt2updater_version.txt') -Value $version -Encoding ascii -NoNewline

    $zipPath = Join-Path $stage "$($m.Id).zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $modStage '*') -DestinationPath $zipPath -Force
    $assetPaths += $zipPath

    $manifestMods += [ordered]@{
        mod_id          = $m.Id
        friendly_name   = $m.Name
        workshop_id     = $workshopId
        version         = $version
        asset_filename  = "$($m.Id).zip"
        visibility      = $visibility
    }
    Write-Host "  staged $($m.Id) v$version -> $zipPath"
}

$manifest = [ordered]@{
    release_tag  = $Tag
    published_at = (Get-Date).ToUniversalTime().ToString('o')
    mods         = $manifestMods
}
$manifestPath = Join-Path $stage 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding utf8
$assetPaths += $manifestPath

Write-Host ""
Write-Host "Manifest:" -ForegroundColor Green
Get-Content $manifestPath

if ($DryRun) {
    Write-Host ""
    Write-Host "DryRun: skipping gh release create. Assets staged at $stage" -ForegroundColor Yellow
    return
}

Write-Host ""
Write-Host "==> gh release create $Tag" -ForegroundColor Cyan
$notes = "Pre-built mod bundles for vt2-mod-updater.`n`nUpdater app: https://github.com/Ensrick/vt2-mod-updater/releases/latest"
gh release create $Tag --repo Ensrick/vermintide-2-tweaker --title "Mod bundles $Tag" --notes $notes @assetPaths
if ($LASTEXITCODE -ne 0) { throw "gh release create failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Release published: https://github.com/Ensrick/vermintide-2-tweaker/releases/tag/$Tag" -ForegroundColor Green
