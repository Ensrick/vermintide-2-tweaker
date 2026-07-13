# tools/publish-release/publish-release.ps1
#
# Builds published VMB mods, zips each bundleV2/ directory, generates a manifest.json,
# and pushes the set as a GitHub release on Ensrick/vermintide-2-tweaker. The
# vt2-mod-updater tool consumes the release manifest to deploy bundles into friends' Steam
# Workshop folders.
#
# Usage:
#   .\publish-release.ps1                       # builds all, releases with auto-generated date tag
#   .\publish-release.ps1 -Tag mods-2026-05-21  # explicit tag name
#   .\publish-release.ps1 -SkipBuild            # use existing bundleV2/ outputs (faster iter)
#   .\publish-release.ps1 -DryRun               # build + stage but don't create the GH release
#   .\publish-release.ps1 -Mods weapon_tweaker  # PER-MOD publish (issues #436/#493): stage/upload
#                                               # ONLY the named mods (folder name or ModId);
#                                               # sibling assets + manifest entries stay exactly
#                                               # as last published. This is what ship.ps1 passes.
#
# Two modes (issues #436/#493):
#   * FULL (no -Mods)  - legacy behavior, unchanged: build + stage every inventory mod, write a
#     fresh manifest from live source, `gh release create`. Run it only when the whole working
#     tree is release-clean: it publishes whatever every mod's source builds to RIGHT NOW.
#   * FILTERED (-Mods) - build/stage/upload only the named mods. Sibling manifest entries are
#     carried VERBATIM from the release's existing manifest (version + sha256 of what was
#     ACTUALLY published - a mid-edit sibling can neither fail this publish nor get a mislabeled
#     asset). If the tag's release doesn't exist yet, sibling ZIPS are carried forward from the
#     latest release so the new release stays self-contained (vt2-mod-updater resolves every
#     asset_filename against ONE release). Filtered mode therefore needs network even with
#     -DryRun (it must read the existing manifest), and needs at least one prior full release.
#
# Requires: gh CLI authenticated to github.com (Ensrick); VMBLauncher.exe present at the
# canonical path. Does NOT upload to Steam Workshop — that's still VMBLauncher's job.

[CmdletBinding()]
param(
    [string]$Tag,
    [switch]$SkipBuild,
    [switch]$DryRun,
    [string[]]$Mods
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$launcher = Join-Path $repoRoot 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
if (-not (Test-Path $launcher)) {
    throw "VMBLauncher not found at $launcher. Build it first via tools/vmb-launcher/publish.ps1 -SkipOpen"
}

$ghRepo = 'Ensrick/vermintide-2-tweaker'

# Native gh call whose failure is an expected branch, or whose stdout we want
# captured (issue #489 guard, same as tools/ship/ship.ps1's Invoke-NativeProbe):
# under stream redirection Windows PowerShell 5.1 wraps native stderr into
# ErrorRecords, and with the script-global $ErrorActionPreference = 'Stop' the
# first stderr line (e.g. `gh release view` on a not-yet-created tag) becomes a
# TERMINATING error. Scope EAP to Continue, discard stderr; callers read stdout
# from the return value and the verdict from $LASTEXITCODE.
function Invoke-GhQuiet {
    param([scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { return (& $Command 2>$null) } finally { $ErrorActionPreference = $prev }
}

# Mod inventory: single source of truth at tools/mod-inventory.psd1 (shared with
# tools/mod-lint/lint-mod.ps1 + qa/check_cfg.ps1). Each entry maps to this
# script's expected { Folder, Id, Name } shape. Unpublished mods (no WorkshopId)
# are still listed; the per-mod loop below skips them on the published_id check.
$inventoryPath = Join-Path $repoRoot 'tools\mod-inventory.psd1'
if (-not (Test-Path $inventoryPath)) {
    throw "Mod inventory not found at $inventoryPath. It is the single source of truth for the release set."
}
$inventory = Import-PowerShellDataFile -Path $inventoryPath
# NOTE: this variable must NOT be named $mods -- PowerShell variable names are
# CASE-INSENSITIVE, so $mods would silently OVERWRITE the $Mods parameter (it
# did, on 2026-07-13: every ship's -Mods filter saw 19 inventory hashtables
# instead of the one mod name and the release step aborted).
$releaseSet = @($inventory.Mods | ForEach-Object {
    @{ Folder = $_.Dir; Id = $_.ModId; Name = $_.Name }
})

# ---- Per-mod filter (issues #493 / #436) ----
# -Mods (folder name or ModId, case-insensitive) restricts the build/stage/
# upload set. Siblings are NOT rebuilt, restaged, or re-uploaded: their release
# assets and manifest entries stay exactly as last published. ship.ps1 passes
# the shipped mod here so (a) a sibling's broken working-tree WIP cannot fail a
# single-mod ship (#493) and (b) no sibling zip is ever published carrying a
# version label read from mid-edit live source (#436).
$filterActive = [bool]($Mods -and @($Mods).Count -gt 0)
if ($filterActive) {
    $unknown = @()
    foreach ($name in $Mods) {
        if (-not @($releaseSet | Where-Object { $_.Folder -eq $name -or $_.Id -eq $name })) { $unknown += $name }
    }
    if ($unknown.Count -gt 0) {
        throw "-Mods name(s) not in tools/mod-inventory.psd1: $($unknown -join ', '). Use the folder name (e.g. weapon_tweaker) or the ModId (e.g. wt)."
    }
    $releaseSet = @($releaseSet | Where-Object { ($Mods -contains $_.Folder) -or ($Mods -contains $_.Id) })
    Write-Host "Per-mod filter: staging ONLY $(@($releaseSet | ForEach-Object { $_.Id }) -join ', ') (issues #436/#493)" -ForegroundColor Yellow
}

# ---- Static-analysis lint gate ----
# Catches the two recurring bug classes that have cost multiple version bumps:
#   1. Duplicate VMF hook registration (silently dropped - burns versions on cim)
#   2. Lua forward-reference bugs (cosmetics_tweaker has shipped this 6+ times)
# Exit code 2 = hard fail (duplicate hooks). Exit code 1 = warning only
# (forward-ref candidates). We BLOCK on exit 2 - a release with a known silently-
# dropped hook would push a broken bundle to every friend.
# With -Mods the gate is SCOPED to the filtered mods (issue #493): a sibling's
# mid-edit duplicate-hook error must not block this mod's release; the filtered
# mod itself still hard-fails on exit 2.
# Comments + throw strings are ASCII only - PowerShell parses .ps1 as
# Windows-1252 by default and mangles em-dashes (memory:
# feedback_ps5_getcontent_utf8).
$linter = Join-Path $repoRoot 'tools\mod-lint\lint-mod.ps1'
if (Test-Path $linter) {
    if ($filterActive) {
        foreach ($m in $releaseSet) {
            Write-Host ""
            Write-Host "==> Static-analysis lint ($($m.Folder))" -ForegroundColor Cyan
            & $linter $m.Folder -Json
            $lintExit = $LASTEXITCODE
            if ($lintExit -eq 2) {
                throw "Lint gate FAILED for $($m.Folder) (duplicate VMF hook registration detected). Fix the duplicates above before publishing - VMF silently drops the second hook and the released bundle will be broken."
            }
            if ($lintExit -eq 1) {
                Write-Warning "Lint gate produced warnings for $($m.Folder) (forward-ref candidates). Continuing - these are non-blocking, but verify each helper has an explicit forward declaration if a closure references it before its definition line."
            }
        }
    } else {
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
    }
} else {
    Write-Warning "Linter not found at $linter - skipping pre-release lint gate."
}

$stage = Join-Path $repoRoot '.release-stage'
if (Test-Path $stage) { Get-ChildItem $stage -Recurse | Remove-Item -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

if (-not $Tag) { $Tag = "mods-$(Get-Date -Format yyyy-MM-dd)" }

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

# ---- Base manifest (filtered mode only) ----
# A filtered publish must never emit a manifest that FORGETS sibling mods: the
# vt2-mod-updater treats manifest.json as the complete mod set. Sibling entries
# are carried VERBATIM from the release's existing manifest - the version and
# sha256 of what was ACTUALLY published, never re-read from live source (issue
# #436). Preference order: this tag's own manifest, else the latest release's
# (first ship under a new day's tag). No base manifest -> hard fail.
$baseManifest = $null
$baseTag      = $null
if ($filterActive) {
    $dlDir = Join-Path $stage '.base-manifest'
    New-Item -ItemType Directory -Force -Path $dlDir | Out-Null
    $candidates = @($Tag)
    $latestTag = "$(Invoke-GhQuiet { gh release view --repo $ghRepo --json tagName --jq '.tagName' })".Trim()
    if ($LASTEXITCODE -eq 0 -and $latestTag -and $latestTag -ne $Tag) { $candidates += $latestTag }
    foreach ($cand in $candidates) {
        $mf = Join-Path $dlDir 'manifest.json'
        if (Test-Path $mf) { Remove-Item $mf -Force }
        $null = Invoke-GhQuiet { gh release download $cand --repo $ghRepo --pattern manifest.json --dir $dlDir --clobber }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $mf)) { continue }
        try { $parsed = Get-Content $mf -Raw | ConvertFrom-Json } catch { $parsed = $null }
        if ($parsed -and $parsed.mods) { $baseManifest = $parsed; $baseTag = $cand; break }
    }
    if (-not $baseManifest) {
        throw "-Mods needs an existing release manifest to carry sibling entries (tried: $($candidates -join ', ')). Offline, or no prior release exists? Run a FULL publish-release (no -Mods) once, then retry."
    }
    Write-Host "  base manifest: $baseTag ($(@($baseManifest.mods).Count) entries)" -ForegroundColor DarkGray
}

$manifestMods = @()
$assetPaths   = @()

foreach ($m in $releaseSet) {
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

    # Bundle integrity: lowercase-hex SHA256 of the zip bytes. vt2-mod-updater compares
    # this against the post-download hash before extracting; mismatch refuses the bundle
    # (defends against the ugc_tool "Upload finished" false-success bug + transport
    # corruption). Purely additive — older consumers without verification still function.
    $sha256 = (Get-FileHash -Algorithm SHA256 -Path $zipPath).Hash.ToLowerInvariant()

    $manifestMods += [ordered]@{
        mod_id          = $m.Id
        friendly_name   = $m.Name
        workshop_id     = $workshopId
        version         = $version
        asset_filename  = "$($m.Id).zip"
        sha256          = $sha256
        visibility      = $visibility
    }
    Write-Host "  staged $($m.Id) v$version -> $zipPath (sha256 $($sha256.Substring(0,12))...)"
}

# ---- Filtered mode: merge with the base manifest + plan the release action ----
$releaseExists = $false
$carriedIdSet  = @{}
if ($filterActive) {
    # Merge: staged entries win; every other entry carries over VERBATIM from
    # the base manifest so unfiltered mods keep the version/sha256 of what is
    # actually attached to the release (issue #436 - a sibling's version label
    # must never come from mid-edit live source). Base order is preserved;
    # first-ever-published mods are appended.
    $stagedById = @{}
    foreach ($e in $manifestMods) { $stagedById["$($e.mod_id)"] = $e }
    $restagedCount = 0
    $mergedMods = @()
    foreach ($baseEntry in $baseManifest.mods) {
        $id = "$($baseEntry.mod_id)"
        if ($stagedById.ContainsKey($id)) {
            $mergedMods += $stagedById[$id]
            $stagedById.Remove($id)
            $restagedCount++
        } else {
            $mergedMods += $baseEntry
            $carriedIdSet[$id] = $true
        }
    }
    foreach ($e in $manifestMods) {
        if ($stagedById.ContainsKey("$($e.mod_id)")) { $mergedMods += $e }   # new mod, not in base yet
    }
    $manifestMods = $mergedMods
    Write-Host ""
    Write-Host "Manifest merge: $restagedCount restaged from this run, $($carriedIdSet.Count) carried verbatim from $baseTag (issues #436/#493)." -ForegroundColor Yellow

    # Does the target release exist? Decides clobber-upload vs create (+ asset
    # carry-forward). Probe guarded per issue #489 - never assume the tag exists.
    $null = Invoke-GhQuiet { gh release view $Tag --repo $ghRepo --json name }
    $releaseExists = ($LASTEXITCODE -eq 0)

    if (-not $releaseExists -and -not $DryRun) {
        # Creating a NEW release under a filter: it must still be SELF-CONTAINED
        # (vt2-mod-updater resolves every asset_filename against ONE release), so
        # carry each sibling's zip forward from the base release, byte-identical
        # (sha256-verified against its carried manifest entry). A sibling whose
        # asset is missing from the base release is dropped from the manifest
        # with a warning - a FULL publish restores it.
        Write-Host ""
        Write-Host "==> Release $Tag does not exist yet -- carrying $($carriedIdSet.Count) sibling asset(s) forward from $baseTag" -ForegroundColor Cyan
        $baseAssetNames = @(Invoke-GhQuiet { gh release view $baseTag --repo $ghRepo --json assets --jq '.assets[].name' })
        if ($LASTEXITCODE -ne 0) { throw "carry-forward: could not list assets on base release $baseTag (gh exit $LASTEXITCODE)" }
        $keptMods = @()
        foreach ($entry in $manifestMods) {
            $id = "$($entry.mod_id)"
            if (-not $carriedIdSet.ContainsKey($id)) { $keptMods += $entry; continue }
            $fname = "$($entry.asset_filename)"
            if ($baseAssetNames -notcontains $fname) {
                Write-Warning "carry-forward: $baseTag has no asset '$fname' -- dropping $id from this release's manifest (run a FULL publish-release to restore it)."
                continue
            }
            $zipDest = Join-Path $stage $fname
            if (Test-Path $zipDest) { Remove-Item $zipDest -Force }
            $null = Invoke-GhQuiet { gh release download $baseTag --repo $ghRepo --pattern $fname --dir $stage --clobber }
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $zipDest)) { throw "carry-forward: download of '$fname' from $baseTag failed" }
            $gotHash  = (Get-FileHash -Algorithm SHA256 -Path $zipDest).Hash.ToLowerInvariant()
            $wantHash = "$($entry.sha256)"
            if ($wantHash -and $gotHash -ne $wantHash) {
                throw "carry-forward: '$fname' hash mismatch (manifest $wantHash vs downloaded $gotHash) -- refusing to republish a corrupt asset"
            }
            $assetPaths += $zipDest
            Write-Host "  carried $id v$($entry.version) ($fname, sha256 $($gotHash.Substring(0,12))...)"
            $keptMods += $entry
        }
        $manifestMods = $keptMods
    }
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
    if ($filterActive) {
        if ($releaseExists) {
            Write-Host "DryRun plan: release $Tag exists -- a live run (or ship.ps1) clobber-uploads the staged zip(s) + merged manifest; sibling assets untouched." -ForegroundColor Yellow
        } else {
            Write-Host "DryRun plan: release $Tag absent -- a live run would carry $($carriedIdSet.Count) sibling asset(s) forward from $baseTag and create the release self-contained." -ForegroundColor Yellow
        }
    }
    return
}

if ($filterActive -and $releaseExists) {
    # Filtered update of an existing release: replace ONLY the staged zip(s) +
    # the merged manifest. Sibling assets on the release are never touched.
    Write-Host ""
    Write-Host "==> gh release upload --clobber $Tag ($($assetPaths.Count) asset(s))" -ForegroundColor Cyan
    gh release upload $Tag @assetPaths --clobber --repo $ghRepo
    if ($LASTEXITCODE -ne 0) { throw "gh release upload --clobber failed (exit $LASTEXITCODE)" }
    Write-Host ""
    Write-Host "Release updated: https://github.com/$ghRepo/releases/tag/$Tag" -ForegroundColor Green
    return
}

Write-Host ""
Write-Host "==> gh release create $Tag" -ForegroundColor Cyan
$notes = "Pre-built mod bundles for vt2-mod-updater.`n`nUpdater app: https://github.com/Ensrick/vt2-mod-updater/releases/latest"
gh release create $Tag --repo $ghRepo --title "Mod bundles $Tag" --notes $notes @assetPaths
if ($LASTEXITCODE -ne 0) { throw "gh release create failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Host "Release published: https://github.com/$ghRepo/releases/tag/$Tag" -ForegroundColor Green
