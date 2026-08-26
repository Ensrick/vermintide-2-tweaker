# release-manifest.ps1 - pure helpers for release provenance manifests.
#
# This file never builds, deploys, uploads, or writes Workshop content. The
# canonical builder remains VMBLauncher; these helpers only describe and verify
# the files that VMBLauncher produced.

$launcherPathHelpers = Join-Path $PSScriptRoot '..\vmb-launcher-path.ps1'
if (-not (Test-Path -LiteralPath $launcherPathHelpers -PathType Leaf)) {
    throw "Shared VMBLauncher helpers not found: $launcherPathHelpers"
}
. $launcherPathHelpers

$bundleOutputSetHelpers = Join-Path $PSScriptRoot '..\ship\bundle-output-set.ps1'
if (-not (Test-Path -LiteralPath $bundleOutputSetHelpers -PathType Leaf)) {
    throw "Shared bundle-output set helpers not found: $bundleOutputSetHelpers"
}
. $bundleOutputSetHelpers

$recoveryRecordHelpers = Join-Path $PSScriptRoot 'recovery-record.ps1'
if (-not (Test-Path -LiteralPath $recoveryRecordHelpers -PathType Leaf)) {
    throw "Release recovery-record helpers not found: $recoveryRecordHelpers"
}
. $recoveryRecordHelpers

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

function New-BundleFileRecords {
    param(
        [Parameter(Mandatory = $true)][string]$BundleDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedDescriptorName,
        [Parameter(Mandatory = $true)][string]$ExpectedRootBundle,
        [string]$ExpectedDescriptorSha256
    )

    $arguments = @{
        BundleDirectory = $BundleDirectory
        ExpectedDescriptorName = $ExpectedDescriptorName
        ExpectedRootBundle = $ExpectedRootBundle
    }
    if ($PSBoundParameters.ContainsKey('ExpectedDescriptorSha256')) {
        $arguments.ExpectedDescriptorSha256 = $ExpectedDescriptorSha256
    }
    $outputSet = Get-VtBundleOutputSet @arguments
    return @(ConvertTo-VtBundleManifestRecords -OutputSet $outputSet)
}

function Get-ReleaseManifestBundleFileRecords {
    param([Parameter(Mandatory = $true)]$ManifestEntry)

    # PowerShell can preserve an absent JSON property as one null pipeline
    # value when it is wrapped directly with @(...). Normalize here so an
    # historical pre-transition entry with no bundle_files is unambiguously
    # empty, while every present record remains available for strict binding.
    return @($ManifestEntry.bundle_files | Where-Object { $null -ne $_ })
}

function Get-ReleaseZipSnapshotBindingMode {
    param(
        [Parameter(Mandatory = $true)]$ManifestEntry,
        [bool]$IsStaged,
        [bool]$IsCarried
    )

    $records = @(Get-ReleaseManifestBundleFileRecords -ManifestEntry $ManifestEntry)
    if ($records.Count -gt 0) { return 'exact_bundle_files' }
    if ($IsCarried -and -not $IsStaged) { return 'legacy_carried_whole_zip' }
    return 'invalid_missing_bundle_files'
}

function New-ReleaseZipBytesFromImmutableOutput {
    param(
        [Parameter(Mandatory = $true)]$OutputSet,
        [Parameter(Mandatory = $true)][object[]]$BundleFiles,
        [Parameter(Mandatory = $true)][string]$Version
    )

    if ([string]::IsNullOrWhiteSpace($Version) -or
            $Version -cne $Version.Trim() -or
            [System.Text.Encoding]::ASCII.GetByteCount($Version) -gt 128) {
        throw 'Release updater version is empty, non-canonical, or exceeds 128 ASCII bytes.'
    }

    $proofs = New-Object 'System.Collections.Generic.Dictionary[string,object]' `
        ([System.StringComparer]::Ordinal)
    foreach ($bundle in @($BundleFiles)) {
        $name = [string]$bundle.Path
        if (-not $name -or [System.IO.Path]::GetFileName($name) -cne $name) {
            throw "Immutable release bundle path is not one exact leaf: $name"
        }
        if ($proofs.ContainsKey($name)) {
            throw "Immutable release bundle proof is duplicated: $name"
        }
        $bytes = [byte[]]$bundle.Bytes
        if ($null -eq $bytes -or [long]$bytes.Length -ne [long]$bundle.Length) {
            throw "Immutable release bundle byte length differs from its proof: $name"
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actualHash = [System.BitConverter]::ToString(
                $sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
        if ($actualHash -cne [string]$bundle.Sha256) {
            throw "Immutable release bundle bytes differ from their SHA-256 proof: $name"
        }
        $proofs.Add($name, $bundle)
    }

    $outputFiles = @($OutputSet.Files)
    if ($outputFiles.Count -ne $proofs.Count) {
        throw 'Immutable release bundle proof count differs from the canonical output set.'
    }
    foreach ($record in $outputFiles) {
        $name = [string]$record.Name
        if (-not $proofs.ContainsKey($name)) {
            throw "Canonical output is missing immutable release bytes: $name"
        }
        $proof = $proofs[$name]
        if ([long]$proof.Length -ne [long]$record.Length -or
                [string]$proof.Sha256 -cne [string]$record.Sha256) {
            throw "Immutable release proof differs from the canonical output record: $name"
        }
    }

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    $memory = New-Object System.IO.MemoryStream
    $archive = $null
    try {
        $archive = New-Object System.IO.Compression.ZipArchive(
            $memory,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $true
        )
        $fixedTimestamp = [System.DateTimeOffset]::new(
            1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)
        foreach ($record in $outputFiles) {
            $name = [string]$record.Name
            $entry = $archive.CreateEntry(
                $name, [System.IO.Compression.CompressionLevel]::Optimal)
            $entry.LastWriteTime = $fixedTimestamp
            $stream = $entry.Open()
            try {
                $bytes = [byte[]]$proofs[$name].Bytes
                $stream.Write($bytes, 0, $bytes.Length)
            }
            finally { $stream.Dispose() }
        }
        $versionEntry = $archive.CreateEntry(
            'vt2updater_version.txt',
            [System.IO.Compression.CompressionLevel]::Optimal)
        $versionEntry.LastWriteTime = $fixedTimestamp
        $versionStream = $versionEntry.Open()
        try {
            $versionBytes = [System.Text.Encoding]::ASCII.GetBytes($Version)
            $versionStream.Write($versionBytes, 0, $versionBytes.Length)
        }
        finally { $versionStream.Dispose() }
        $archive.Dispose()
        $archive = $null
        return [byte[]]$memory.ToArray()
    }
    finally {
        if ($archive) { $archive.Dispose() }
        $memory.Dispose()
    }
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
        if ("$($entry.source_state)" -ne 'clean') {
            if ($mustHaveProvenance) { $errors.Add("$prefix.source_state must be clean") }
            else { $warnings.Add("$prefix carries historical non-clean source_state '$($entry.source_state)'") }
        }
        if ("$($entry.builder.name)" -ne 'VMBLauncher') { $errors.Add("$prefix.builder.name must be VMBLauncher") }
        if (-not "$($entry.builder.version)".Trim()) { $errors.Add("$prefix.builder.version is required") }

        $declaredAuthority = [string]$entry.bundle_authority
        if (-not [string]::IsNullOrWhiteSpace($declaredAuthority) -and
            @('tracked', 'receipt') -cnotcontains $declaredAuthority) {
            $errors.Add("$prefix.bundle_authority must be tracked or receipt when present")
        }

        if ($null -eq $entry.publication_authorization) {
            if ($mustHaveProvenance) { $errors.Add("$prefix.publication_authorization is required") }
            else { $warnings.Add("$prefix is a carried pre-authorization entry without publication_authorization") }
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

        $bundleFiles = @(Get-ReleaseManifestBundleFileRecords -ManifestEntry $entry)
        if ($bundleFiles.Count -eq 0) { $errors.Add("$prefix.bundle_files must not be empty"); continue }
        $seenNames = @{}
        $manifestOutputRecords = @()
        foreach ($bundle in $bundleFiles) {
            $name = "$($bundle.filename)"
            $bundlePrefix = "$prefix.bundle_files[$name]"
            if (-not $name -or [System.IO.Path]::GetFileName($name) -ne $name) { $errors.Add("$bundlePrefix.filename must be a leaf filename") }
            if ($seenNames.ContainsKey($name)) { $errors.Add("$prefix has duplicate bundle filename: $name") } else { $seenNames[$name] = $true }
            $wantHash = "$($bundle.sha256)"
            if ($wantHash -notmatch '^[0-9a-f]{64}$') { $errors.Add("$bundlePrefix.sha256 must be lowercase SHA-256"); continue }
            $manifestOutputRecords += [pscustomobject]@{
                Name = $name
                Length = 0L
                Sha256 = $wantHash
            }
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
        $rootBundle = [string]$entry.root_bundle
        $descriptorName = [string]$entry.descriptor_name
        $hasExactCoordinates = -not [string]::IsNullOrWhiteSpace($rootBundle) -or
            -not [string]::IsNullOrWhiteSpace($descriptorName)
        if ($mustHaveProvenance -and -not $hasExactCoordinates) {
            $errors.Add("$prefix must bind root_bundle and descriptor_name")
        }
        if ($hasExactCoordinates) {
            if ([string]::IsNullOrWhiteSpace($rootBundle) -or
                [string]::IsNullOrWhiteSpace($descriptorName)) {
                $errors.Add("$prefix root_bundle and descriptor_name must be supplied together")
            }
            else {
                try {
                    $descriptorRows = @($manifestOutputRecords | Where-Object {
                        [string]$_.Name -ceq $descriptorName
                    })
                    if ($descriptorRows.Count -ne 1) {
                        throw "manifest does not contain exactly one declared descriptor '$descriptorName'"
                    }
                    $null = New-VtBundleOutputSet `
                        -Records $manifestOutputRecords `
                        -ExpectedDescriptorName $descriptorName `
                        -ExpectedRootBundle $rootBundle `
                        -ExpectedDescriptorSha256 ([string]$descriptorRows[0].Sha256)
                }
                catch {
                    $errors.Add("$prefix bundle_files are not one canonical output set: $($_.Exception.Message)")
                }
            }
        }
        else {
            # Historical carried entries predate exact root/descriptor
            # coordinates. Preserve their transition allowance without defining
            # a second, weaker classifier for newly staged outputs.
            if (@($bundleFiles | Where-Object { "$($_.filename)" -like '*.mod_bundle' }).Count -eq 0) {
                $errors.Add("$prefix.bundle_files must include at least one .mod_bundle")
            }
            if (@($bundleFiles | Where-Object { "$($_.filename)" -like '*.mod' }).Count -eq 0) {
                $errors.Add("$prefix.bundle_files must include the .mod descriptor")
            }
        }
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

        $hasRecoveryRecord = Test-VtReleaseRecoveryHasProperty -Value $entry -Name 'recovery'
        if (-not $hasRecoveryRecord -or $null -eq $entry.recovery) {
            if ($declaredAuthority -ceq 'receipt') {
                $errors.Add("$prefix receipt authority requires a durable source-exact recovery record")
            }
            elseif ($mustHaveProvenance) {
                $warnings.Add("$prefix is newly staged without a source-exact recovery record; it remains on the explicit legacy recovery path")
            }
        }
        else {
            if ([string]::IsNullOrWhiteSpace($declaredAuthority)) {
                $errors.Add("$prefix.bundle_authority is required with a recovery record")
            }
            $recoveryVerdict = Test-VtReleaseRecoveryRecord `
                -Record $entry.recovery `
                -ManifestEntry $entry `
                -ManifestReleaseTag ([string]$Manifest.release_tag) `
                -RequireManifestReleaseTag:$mustHaveProvenance
            foreach ($problem in @($recoveryVerdict.Errors)) {
                $errors.Add("$prefix.$problem")
            }
            if (-not [string]::IsNullOrWhiteSpace($declaredAuthority) -and
                [string]$entry.recovery.bundle_authority -cne $declaredAuthority) {
                $errors.Add("$prefix recovery bundle authority differs from manifest entry")
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
    foreach ($bundle in @(Get-ReleaseManifestBundleFileRecords -ManifestEntry $ManifestEntry)) {
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
