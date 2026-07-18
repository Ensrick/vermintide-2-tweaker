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
#   .\publish-release.ps1 -LauncherPath <exe> -LauncherSource <source> -LauncherApprovalAnchor <path>
#                                               # exact approved dependency handoff from ship.ps1
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
# Requires: gh CLI authenticated to github.com (Ensrick); VMBLauncher.exe in an approved
# invoking/configured/primary/env location. Does NOT upload to Steam Workshop - that is
# still VMBLauncher's job.

[CmdletBinding()]
param(
    [string]$Tag,
    [switch]$SkipBuild,
    [switch]$DryRun,
    [string[]]$Mods,
    [string]$LauncherPath,
    [string]$LauncherSource,
    [string]$LauncherApprovalAnchor
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$launcherPathHelpers = Join-Path $repoRoot 'tools\vmb-launcher-path.ps1'
if (-not (Test-Path -LiteralPath $launcherPathHelpers -PathType Leaf)) {
    throw "Shared VMBLauncher path helpers not found at $launcherPathHelpers."
}
. $launcherPathHelpers
$manifestHelpers = Join-Path $PSScriptRoot 'release-manifest.ps1'
if (-not (Test-Path -LiteralPath $manifestHelpers)) {
    throw "Release-manifest helpers not found at $manifestHelpers."
}
. $manifestHelpers
$githubReleaseHelpers = Join-Path $PSScriptRoot 'github-release-api.ps1'
if (-not (Test-Path -LiteralPath $githubReleaseHelpers)) {
    throw "GitHub release helpers not found at $githubReleaseHelpers."
}
. $githubReleaseHelpers
$launcherSettings = Join-Path $env:APPDATA 'VMBLauncher\settings.json'
$configuredProjectRoot = Get-VmbLauncherConfiguredProjectRoot -SettingsPath $launcherSettings
$primaryWorktreeRoot = Get-VmbLauncherPrimaryWorktreeRoot -RepoRoot $repoRoot
$launcherResolution = Resolve-ApprovedVmbLauncherPath `
    -RepoRoot $repoRoot `
    -RequestedPath $LauncherPath `
    -RequestedSource $LauncherSource `
    -RequestedApprovalAnchor $LauncherApprovalAnchor `
    -ConfiguredProjectRoot $configuredProjectRoot `
    -PrimaryWorktreeRoot $primaryWorktreeRoot `
    -EnvironmentPath $env:VT2_SHIP_VMB_LAUNCHER
$launcher = $launcherResolution.Path
$sourceCommit = Get-ReleaseSourceCommit -RepoRoot $repoRoot
$builderVersion = Get-VmbLauncherVersion -LauncherPath $launcher
Write-Host "VMBLauncher dependency: $launcher ($($launcherResolution.Source), version $builderVersion)" -ForegroundColor DarkGray

$ghRepo = 'Ensrick/vermintide-2-tweaker'

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
$levelBudgetGate = Join-Path $repoRoot 'qa\check_level_lookup_budget.ps1'
if (Test-Path $levelBudgetGate) {
    Write-Host ""
    Write-Host "==> CT network level-key budget" -ForegroundColor Cyan
    & $levelBudgetGate
    if ($LASTEXITCODE -ne 0) {
        throw "Release blocked: CT adventure LevelSettings/NetworkLookup additions exceed the fixed weight_array budget or duplicate aliases consume network keys."
    }
} else {
    throw "Release blocked: required level-key budget gate is missing at $levelBudgetGate"
}

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

function Read-GitHubReleaseManifest {
    param(
        [Parameter(Mandatory = $true)]$Release,
        [Parameter(Mandatory = $true)][string]$DownloadDirectory
    )
    $manifestAsset = Get-GitHubReleaseAsset -Release $Release -Name 'manifest.json'
    if (-not $manifestAsset) { return $null }
    $manifestFile = Join-Path $DownloadDirectory 'manifest.json'
    if (Test-Path -LiteralPath $manifestFile) { Remove-Item -LiteralPath $manifestFile }
    Save-GitHubReleaseAsset -Repo $ghRepo -Asset $manifestAsset -Destination $manifestFile
    try { $parsed = Get-Content $manifestFile -Raw | ConvertFrom-Json } catch { return $null }
    if (-not $parsed -or -not $parsed.mods) { return $null }
    return [pscustomobject]@{ Manifest = $parsed; Release = $Release }
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
$baseRelease  = $null
$targetRelease = $null
$targetReleaseResult = $null
$releaseExists = $false
if ($filterActive) {
    $dlDir = Join-Path $stage '.base-manifest'
    New-Item -ItemType Directory -Force -Path $dlDir | Out-Null

    $targetReleaseResult = Resolve-GitHubReleaseByTag -Repo $ghRepo -Tag $Tag
    Write-Host "  release lookup: $($targetReleaseResult.Message)" -ForegroundColor DarkGray
    if ($targetReleaseResult.State -eq 'Unavailable') {
        throw "Release lookup unavailable: $($targetReleaseResult.Message). Refusing to create or mutate a release while existence is uncertain."
    }
    $releaseExists = ($targetReleaseResult.State -eq 'Found')
    if ($releaseExists) { $targetRelease = $targetReleaseResult.Release }

    $candidateReleases = @()
    $loadedBase = $null
    if ($targetRelease) {
        $candidateReleases += $targetRelease
        $loadedBase = Read-GitHubReleaseManifest -Release $targetRelease -DownloadDirectory $dlDir
    }
    # Existing target releases normally supply their own base manifest. Query
    # the latest list entry only when the target is absent or lacks a usable
    # manifest, so a separate list outage cannot break the healthy tag route.
    if (-not $loadedBase) {
        $latestRelease = Get-GitHubLatestReleaseFromList -Repo $ghRepo
        if ($latestRelease -and (-not $targetRelease -or "$($latestRelease.id)" -ne "$($targetRelease.id)")) {
            $candidateReleases += $latestRelease
            $loadedBase = Read-GitHubReleaseManifest -Release $latestRelease -DownloadDirectory $dlDir
        }
    }
    if ($loadedBase) {
        $baseManifest = $loadedBase.Manifest
        $baseRelease = $loadedBase.Release
        $baseTag = "$($baseRelease.tag_name)"
    }
    if (-not $baseManifest) {
        $triedTags = @($candidateReleases | ForEach-Object { $_.tag_name })
        throw "-Mods needs an existing release manifest to carry sibling entries (tried: $($triedTags -join ', ')). No duplicate release was created. Run a FULL publish-release (no -Mods) once, then retry."
    }
    Write-Host "  base manifest: $baseTag ($(@($baseManifest.mods).Count) entries)" -ForegroundColor DarkGray
}

$manifestMods = @()
$assetPaths   = @()
$stagedIds    = @()

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

    # Provenance hashes describe VMBLauncher's raw output, before the updater
    # sidecar is added. Hash the copied staging files so the manifest verifies
    # the exact bytes that will enter the release zip.
    $bundleFiles = @(New-BundleFileRecords -BundleDirectory $modStage | Where-Object {
        $_.filename -ne 'vt2updater_version.txt'
    })

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
        source_commit   = $sourceCommit
        source_state    = (Get-ModSourceState -RepoRoot $repoRoot -ModFolder $m.Folder)
        builder         = [ordered]@{
            name    = 'VMBLauncher'
            version = $builderVersion
        }
        bundle_files    = $bundleFiles
    }
    $stagedIds += $m.Id
    Write-Host "  staged $($m.Id) v$version -> $zipPath (sha256 $($sha256.Substring(0,12))...)"
}

# ---- Filtered mode: merge with the base manifest + plan the release action ----
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

    if (-not $releaseExists -and -not $DryRun) {
        # Creating a NEW release under a filter: it must still be SELF-CONTAINED
        # (vt2-mod-updater resolves every asset_filename against ONE release), so
        # carry each sibling's zip forward from the base release, byte-identical
        # (sha256-verified against its carried manifest entry). A sibling whose
        # asset is missing from the base release is dropped from the manifest
        # with a warning - a FULL publish restores it.
        Write-Host ""
        Write-Host "==> Release $Tag does not exist yet -- carrying $($carriedIdSet.Count) sibling asset(s) forward from $baseTag" -ForegroundColor Cyan
        $baseAssetNames = @($baseRelease.assets | ForEach-Object { $_.name })
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
            $baseAsset = Get-GitHubReleaseAsset -Release $baseRelease -Name $fname
            Save-GitHubReleaseAsset -Repo $ghRepo -Asset $baseAsset -Destination $zipDest
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
    manifest_schema = 2
    release_tag  = $Tag
    published_at = (Get-Date).ToUniversalTime().ToString('o')
    mods         = $manifestMods
}
$manifestPath = Join-Path $stage 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding utf8
$assetPaths += $manifestPath

# Block before any GitHub mutation if a newly staged entry cannot be mapped to
# its source baseline, VMBLauncher version, or exact bundle bytes. Filtered
# releases may carry older sibling entries without provenance until each is
# rebuilt; the validator reports those explicitly without breaking transition.
$manifestVerdict = Test-ReleaseManifest -Manifest $manifest -RequiredModIds $stagedIds -StageRoot $stage
foreach ($warning in $manifestVerdict.Warnings) { Write-Warning "Release manifest: $warning" }
if (-not $manifestVerdict.Valid) {
    throw "Release manifest validation failed:`n - $($manifestVerdict.Errors -join "`n - ")"
}
Write-Host "Release manifest validation: PASS ($($stagedIds.Count) newly staged provenance entr$(if ($stagedIds.Count -eq 1) { 'y' } else { 'ies' }))." -ForegroundColor Green

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
    Write-Host "==> GitHub release-id upload/clobber $($targetRelease.id) ($($assetPaths.Count) asset(s))" -ForegroundColor Cyan
    Publish-GitHubReleaseAssetsById -Repo $ghRepo -Release $targetRelease -AssetPaths $assetPaths
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
