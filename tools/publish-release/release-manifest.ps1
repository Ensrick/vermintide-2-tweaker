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

function Get-ModSourceChanges {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ModFolder
    )

    # Bundle outputs are generated artifacts, not source changes. Any other
    # tracked/untracked path under the mod makes the commit a baseline rather
    # than an exact source snapshot, and the manifest says so explicitly.
    $lines = @(git -C $RepoRoot status --porcelain --untracked-files=all -- $ModFolder 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not inspect source state for $ModFolder." }
    return @($lines | Where-Object {
        $path = "$_".Substring([Math]::Min(3, "$_".Length)).Replace('\', '/')
        $path -notmatch '(^|/)bundleV2/'
    })
}

function Get-ModSourceState {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$ModFolder
    )

    $sourceChanges = @(Get-ModSourceChanges -RepoRoot $RepoRoot -ModFolder $ModFolder)
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
        if ("$($entry.source_state)" -ne 'clean') { $errors.Add("$prefix.source_state must be clean") }
        if ("$($entry.builder.name)" -ne 'VMBLauncher') { $errors.Add("$prefix.builder.name must be VMBLauncher") }
        if (-not "$($entry.builder.version)".Trim()) { $errors.Add("$prefix.builder.version is required") }

        if ($null -eq $entry.publication_authorization) {
            $errors.Add("$prefix.publication_authorization is required")
        }
        else {
            $authorization = $entry.publication_authorization
            $mode = "$($authorization.mode)"
            if ($mode -ne 'hosted_qa') {
                $errors.Add("$prefix.publication_authorization.mode must be hosted_qa")
            }
            if ("$($authorization.source_commit)" -ne "$($entry.source_commit)") {
                $errors.Add("$prefix.publication_authorization.source_commit must equal entry source_commit")
            }
            if (-not "$($authorization.checked_at_utc)".Trim()) {
                $errors.Add("$prefix.publication_authorization.checked_at_utc is required")
            }
            if (-not "$($authorization.default_branch)".Trim()) {
                $errors.Add("$prefix.publication_authorization.default_branch is required for hosted_qa")
            }
            if ("$($authorization.default_branch_commit)" -ne "$($entry.source_commit)") {
                $errors.Add("$prefix.publication_authorization.default_branch_commit must equal entry source_commit")
            }
            if ("$($authorization.merged_pr_number)" -notmatch '^\d+$') {
                $errors.Add("$prefix.publication_authorization.merged_pr_number must contain digits for hosted_qa")
            }
            if ("$($authorization.qa_check)" -ne 'qa-gate') {
                $errors.Add("$prefix.publication_authorization.qa_check must be qa-gate")
            }
            if (-not "$($authorization.qa_check_url)".Trim()) {
                $errors.Add("$prefix.publication_authorization.qa_check_url is required for hosted_qa")
            }
            if (-not "$($authorization.qa_completed_at_utc)".Trim()) {
                $errors.Add("$prefix.publication_authorization.qa_completed_at_utc is required for hosted_qa")
            }
        }

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
            # A filtered publish stages only RequiredModIds. Carried siblings
            # keep their provenance records verbatim, but their bundle files
            # intentionally are not copied into StageRoot when the target
            # release already exists. Validate bytes only for entries this run
            # actually staged; full publishes pass every mod as required.
            if ($StageRoot -and $mustHaveProvenance) {
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
        if ($StageRoot -and $mustHaveProvenance) {
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

function Test-ReleaseZipSnapshot {
    param(
        [Parameter(Mandatory = $true)][byte[]]$ZipBytes,
        [Parameter(Mandatory = $true)]$ManifestEntry
    )

    $errors = [System.Collections.Generic.List[string]]::new()
    $expected = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::Ordinal)
    foreach ($bundle in @($ManifestEntry.bundle_files)) {
        $name = "$($bundle.filename)"
        $hash = "$($bundle.sha256)"
        if (-not $name -or [System.IO.Path]::GetFileName($name) -cne $name) {
            $errors.Add("manifest bundle filename is not one exact leaf: $name")
            continue
        }
        if ($expected.ContainsKey($name)) {
            $errors.Add("manifest contains duplicate bundle filename: $name")
        }
        else { $expected.Add($name, $hash) }
    }
    $expectedVersion = "$($ManifestEntry.version)"
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $memory = $null
    $archive = $null
    try {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        $memory = New-Object System.IO.MemoryStream (,$ZipBytes)
        $archive = New-Object System.IO.Compression.ZipArchive(
            $memory,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false
        )
        foreach ($entry in @($archive.Entries)) {
            $name = "$($entry.FullName)"
            if (-not $name -or "$($entry.Name)" -cne $name) {
                $errors.Add("zip entry is not one exact leaf filename: $name")
                continue
            }
            if (-not $seen.Add($name)) {
                $errors.Add("zip contains duplicate entry: $name")
                continue
            }
            if ($entry.Length -gt 1073741824) {
                $errors.Add("zip entry exceeds the 1 GiB verification bound: $name")
                continue
            }
            if ($name -ceq 'vt2updater_version.txt') {
                if ($entry.Length -gt 128) {
                    $errors.Add('vt2updater_version.txt exceeds 128 bytes')
                    continue
                }
                $stream = $entry.Open()
                try {
                    $reader = New-Object System.IO.StreamReader(
                        $stream,
                        [System.Text.Encoding]::ASCII,
                        $false,
                        128,
                        $true
                    )
                    try { $actualVersion = $reader.ReadToEnd() }
                    finally { $reader.Dispose() }
                }
                finally { $stream.Dispose() }
                if ($actualVersion -cne $expectedVersion) {
                    $errors.Add("zip updater version '$actualVersion' does not equal manifest version '$expectedVersion'")
                }
                continue
            }
            if (-not $expected.ContainsKey($name)) {
                $errors.Add("zip contains unrepresented entry: $name")
                continue
            }
            $stream = $entry.Open()
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $actualHash = [System.BitConverter]::ToString(
                    $sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
            }
            finally {
                $sha.Dispose()
                $stream.Dispose()
            }
            if ($actualHash -cne "$($expected[$name])") {
                $errors.Add("zip entry hash does not match exact manifest bundle: $name")
            }
        }
    }
    catch {
        $errors.Add("zip snapshot is unreadable: $($_.Exception.Message)")
    }
    finally {
        if ($archive) { $archive.Dispose() }
        elseif ($memory) { $memory.Dispose() }
    }

    foreach ($name in $expected.Keys) {
        if (-not $seen.Contains($name)) {
            $errors.Add("zip is missing exact manifest bundle: $name")
        }
    }
    if (-not $seen.Contains('vt2updater_version.txt')) {
        $errors.Add('zip is missing vt2updater_version.txt')
    }
    return [pscustomobject]@{
        Valid = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}
