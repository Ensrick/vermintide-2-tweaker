# release-manifest.ps1 - pure helpers for release provenance manifests.
#
# This file never builds, deploys, uploads, or writes Workshop content. The
# canonical builder remains VMBLauncher; these helpers only describe and verify
# the files that VMBLauncher produced.

function Get-ReleaseSourceCommit {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $commit = "$(git -C $RepoRoot rev-parse HEAD 2>$null)".Trim().ToLowerInvariant()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
        throw "Could not resolve a 40-character source commit from $RepoRoot."
    }
    return $commit
}

function Get-ModSourceState {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ModFolder
    )

    # Bundle outputs are generated artifacts, not source changes. Any other
    # tracked/untracked path under the mod makes the commit a baseline rather
    # than an exact source snapshot, and the manifest says so explicitly.
    $lines = @(git -C $RepoRoot status --porcelain --untracked-files=all -- $ModFolder 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect source state for $ModFolder." }
    $sourceChanges = @($lines | Where-Object {
        $path = "$_".Substring([Math]::Min(3, "$_".Length)).Replace('\', '/')
        $path -notmatch '(^|/)bundleV2/'
    })
    if ($sourceChanges.Count -eq 0) { return 'clean' }
    return 'dirty'
}

function Get-VmbLauncherVersion {
    param([Parameter(Mandatory = $true)][string]$LauncherPath)

    if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
        throw "VMBLauncher not found at $LauncherPath."
    }
    $info = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($LauncherPath)
    $version = "$($info.ProductVersion)".Trim()
    if (-not $version) { $version = "$($info.FileVersion)".Trim() }
    if (-not $version) {
        throw "VMBLauncher at $LauncherPath has no ProductVersion or FileVersion metadata."
    }
    return $version
}

function New-BundleFileRecords {
    param([Parameter(Mandatory = $true)][string]$BundleDirectory)

    if (-not (Test-Path -LiteralPath $BundleDirectory -PathType Container)) {
        throw "Bundle directory not found: $BundleDirectory"
    }
    $directories = @(Get-ChildItem -LiteralPath $BundleDirectory -Directory)
    if ($directories.Count -gt 0) {
        throw "Bundle directory contains nested directories that cannot be represented by leaf filenames: $BundleDirectory"
    }
    $files = @(Get-ChildItem -LiteralPath $BundleDirectory -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw "Bundle directory is empty: $BundleDirectory" }
    return @($files | ForEach-Object {
        [ordered]@{
            filename = $_.Name
            sha256   = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    })
}

function Test-ReleaseManifest {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [string[]]$RequiredModIds = @(),
        [string]$StageRoot
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $required = @{}
    foreach ($id in @($RequiredModIds)) { $required["$id"] = $true }

    if ("$($Manifest.manifest_schema)" -ne '2') { $errors.Add('manifest_schema must be 2') }
    if (-not "$($Manifest.release_tag)".Trim()) { $errors.Add('release_tag is required') }
    if (-not "$($Manifest.published_at)".Trim()) { $errors.Add('published_at is required') }

    $entries = @($Manifest.mods)
    if ($entries.Count -eq 0) { $errors.Add('mods must contain at least one entry') }
    $seenIds = @{}
    foreach ($entry in $entries) {
        $id = "$($entry.mod_id)"
        $prefix = if ($id) { "mods[$id]" } else { 'mods[?]' }
        if (-not $id) { $errors.Add("$prefix.mod_id is required"); continue }
        if ($seenIds.ContainsKey($id)) { $errors.Add("duplicate mod_id: $id") } else { $seenIds[$id] = $true }
        if ("$($entry.workshop_id)" -notmatch '^\d+$') { $errors.Add("$prefix.workshop_id must contain digits only") }
        if (-not "$($entry.version)".Trim()) { $errors.Add("$prefix.version is required") }
        if (-not "$($entry.asset_filename)".Trim()) { $errors.Add("$prefix.asset_filename is required") }
        if ("$($entry.sha256)" -notmatch '^[0-9a-f]{64}$') { $errors.Add("$prefix.sha256 must be lowercase SHA-256") }

        $hasProvenance = "$($entry.source_commit)" -or $null -ne $entry.builder -or $null -ne $entry.bundle_files
        $mustHaveProvenance = $required.ContainsKey($id)
        if (-not $hasProvenance) {
            if ($mustHaveProvenance) { $errors.Add("$prefix is newly staged and must include release provenance") }
            else { $warnings.Add("$prefix is a carried pre-transition entry without release provenance") }
            continue
        }

        if ("$($entry.source_commit)" -notmatch '^[0-9a-f]{40}$') { $errors.Add("$prefix.source_commit must be a lowercase 40-character Git commit") }
        if ("$($entry.source_state)" -notmatch '^(clean|dirty)$') { $errors.Add("$prefix.source_state must be clean or dirty") }
        if ("$($entry.builder.name)" -ne 'VMBLauncher') { $errors.Add("$prefix.builder.name must be VMBLauncher") }
        if (-not "$($entry.builder.version)".Trim()) { $errors.Add("$prefix.builder.version is required") }

        $bundleFiles = @($entry.bundle_files)
        if ($bundleFiles.Count -eq 0) { $errors.Add("$prefix.bundle_files must not be empty"); continue }
        $seenNames = @{}
        $hasModBundle = $false
        $hasDescriptor = $false
        foreach ($bundle in $bundleFiles) {
            $name = "$($bundle.filename)"
            $bundlePrefix = "$prefix.bundle_files[$name]"
            if (-not $name -or [System.IO.Path]::GetFileName($name) -ne $name) { $errors.Add("$bundlePrefix.filename must be a leaf filename") }
            if ($seenNames.ContainsKey($name)) { $errors.Add("$prefix has duplicate bundle filename: $name") } else { $seenNames[$name] = $true }
            if ($name -like '*.mod_bundle') { $hasModBundle = $true }
            if ($name -like '*.mod') { $hasDescriptor = $true }
            $wantHash = "$($bundle.sha256)"
            if ($wantHash -notmatch '^[0-9a-f]{64}$') { $errors.Add("$bundlePrefix.sha256 must be lowercase SHA-256"); continue }
            if ($StageRoot) {
                $stagedPath = Join-Path (Join-Path $StageRoot $id) $name
                if (-not (Test-Path -LiteralPath $stagedPath -PathType Leaf)) {
                    $errors.Add("$bundlePrefix is missing from staged files: $stagedPath")
                } else {
                    $gotHash = (Get-FileHash -LiteralPath $stagedPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($gotHash -ne $wantHash) { $errors.Add("$bundlePrefix hash mismatch: manifest $wantHash, staged $gotHash") }
                }
            }
        }
        if (-not $hasModBundle) { $errors.Add("$prefix.bundle_files must include at least one .mod_bundle") }
        if (-not $hasDescriptor) { $errors.Add("$prefix.bundle_files must include the .mod descriptor") }
        if ($StageRoot) {
            $stagedDir = Join-Path $StageRoot $id
            if (Test-Path -LiteralPath $stagedDir -PathType Container) {
                $actualNames = @(Get-ChildItem -LiteralPath $stagedDir -File | Where-Object {
                    $_.Name -ne 'vt2updater_version.txt'
                } | ForEach-Object { $_.Name })
                foreach ($actualName in $actualNames) {
                    if (-not $seenNames.ContainsKey($actualName)) {
                        $errors.Add("$prefix staged output is not listed in bundle_files: $actualName")
                    }
                }
                $nestedDirs = @(Get-ChildItem -LiteralPath $stagedDir -Directory)
                if ($nestedDirs.Count -gt 0) { $errors.Add("$prefix staged output contains unrepresented nested directories") }
            }
        }
    }

    foreach ($id in $required.Keys) {
        if (-not $seenIds.ContainsKey($id)) { $errors.Add("required staged mod is absent from manifest: $id") }
    }
    return [pscustomobject]@{
        Valid    = ($errors.Count -eq 0)
        Errors   = @($errors)
        Warnings = @($warnings)
    }
}
