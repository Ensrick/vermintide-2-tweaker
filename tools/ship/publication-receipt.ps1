# tools/ship/publication-receipt.ps1
#
# Builds the short-lived receipt that publish-release hosts as an exact GitHub
# release asset. VMBLauncher accepts the local copy only when it independently
# downloads the byte-identical hosted asset immediately before ugc_tool.
#
# ASCII only for Windows PowerShell 5.1 compatibility.

function Test-VmbLauncherPublicationCapabilityOutput {
    param(
        [string[]]$Lines,
        [version]$MinimumVersion = ([version]'0.6.0')
    )

    $values = @{}
    foreach ($line in @($Lines)) {
        if ("$line" -match '^([a-z_]+)=(.*)$') {
            $values[$matches[1]] = $matches[2].Trim()
        }
    }
    $reported = $null
    try { $reported = [version]"$($values.version)" } catch { }
    $capabilities = @("$($values.capabilities)" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $problems = @()
    if ("$($values.capability_schema)" -ne '1') { $problems += 'capability_schema must be 1' }
    if ($null -eq $reported -or $reported -lt $MinimumVersion) {
        $problems += "launcher version must be at least $MinimumVersion"
    }
    if ("$($values.publication_receipt_schema)" -ne '3') {
        $problems += 'publication_receipt_schema must be 3'
    }
    foreach ($required in @(
        'hosted-publication-receipt-v3',
        'locked-upload-snapshot-v1',
        'git-commit-blob-snapshot-v1',
        'constrained-first-upload-bootstrap-v1',
        'machine-transaction-lease-v1',
        'crash-safe-upload-acl-journal-v1'
    )) {
        if ($capabilities -notcontains $required) { $problems += "missing capability $required" }
    }
    return [pscustomobject]@{
        Ok = ($problems.Count -eq 0)
        Version = $reported
        Capabilities = $capabilities
        Problems = $problems
    }
}

function Assert-VmbLauncherPublicationCapability {
    param(
        [string]$LauncherPath,
        [version]$MinimumVersion = ([version]'0.6.0')
    )

    if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
        throw "VMBLauncher publication capability probe cannot find $LauncherPath."
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $LauncherPath
    $psi.Arguments = 'capabilities --no-banner'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'process did not start' }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "capability probe exited $($process.ExitCode): $($stderr.Trim())"
        }
    }
    finally { $process.Dispose() }
    $verdict = Test-VmbLauncherPublicationCapabilityOutput `
        -Lines @($stdout -split "`r?`n") -MinimumVersion $MinimumVersion
    if (-not $verdict.Ok) {
        throw "VMBLauncher publication capability probe failed: $($verdict.Problems -join '; '). " +
            'Land/install launcher 0.6.0 before the monorepo publication guard.'
    }
    return $verdict
}

function Get-CanonicalShipOwnerId {
    param([string]$RepoRoot)

    if ($env:VT2_SHIP_SESSION_ID) { return "explicit:$($env:VT2_SHIP_SESSION_ID)" }
    if ($env:CLAUDE_SESSION_ID)   { return "claude:$($env:CLAUDE_SESSION_ID)" }
    if ($env:CODEX_THREAD_ID)     { return "codex:$($env:CODEX_THREAD_ID)" }

    if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
        throw 'Cannot derive publication-receipt owner without RepoRoot.'
    }
    $normalized = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/').ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalized))
    }
    finally {
        $sha.Dispose()
    }
    $hex = [System.BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
    return "worktree:$($hex.Substring(0, 16))"
}

function ConvertTo-PublicationNativeArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-PublicationGitBytes {
    param(
        [string]$RepoRoot,
        [string[]]$ArgumentList
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git'
    $allArguments = @('-C', $RepoRoot) + @($ArgumentList)
    $startInfo.Arguments = (($allArguments | ForEach-Object {
        ConvertTo-PublicationNativeArgument ([string]$_)
    }) -join ' ')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $output = New-Object System.IO.MemoryStream
    try {
        if (-not $process.Start()) { throw 'git process did not start' }
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($output)
        $process.WaitForExit()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "git $($ArgumentList -join ' ') failed (exit $($process.ExitCode)): $($stderr.Trim())"
        }
        return ,([byte[]]$output.ToArray())
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function Get-PublicationByteSha256 {
    param([byte[]]$Bytes)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-PublicationGitObjectId {
    param([string]$Type, [byte[]]$Bytes)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    try {
        $header = [System.Text.Encoding]::ASCII.GetBytes("$Type $($Bytes.LongLength)`0")
        [void]$sha1.TransformBlock($header, 0, $header.Length, $null, 0)
        [void]$sha1.TransformFinalBlock($Bytes, 0, $Bytes.Length)
        return [System.BitConverter]::ToString($sha1.Hash).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha1.Dispose() }
}

function Get-PublicationCommitSnapshot {
    param(
        [string]$RepoRoot,
        [string]$SourceCommit,
        [string]$Mod
    )

    if ("$SourceCommit" -notmatch '^[0-9a-f]{40}$') {
        throw 'Publication receipt requires a lowercase full source commit SHA.'
    }
    if ("$Mod" -notmatch '^[a-z0-9_]+$') {
        throw 'Publication receipt mod name is not canonical.'
    }
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $null = Invoke-PublicationGitBytes -RepoRoot $root -ArgumentList @(
        'cat-file', '-e', "$SourceCommit^{commit}"
    )
    $commitBytes = Invoke-PublicationGitBytes -RepoRoot $root -ArgumentList @(
        'cat-file', 'commit', $SourceCommit
    )
    if ((Get-PublicationGitObjectId -Type 'commit' -Bytes ([byte[]]$commitBytes)) -ne $SourceCommit) {
        throw 'Local source commit object bytes do not match source_commit.'
    }
    $treeBytes = Invoke-PublicationGitBytes -RepoRoot $root -ArgumentList @(
        'ls-tree', '-r', '-z', '--full-tree', $SourceCommit, '--', $Mod
    )
    $tree = @{}
    $treeText = [System.Text.Encoding]::UTF8.GetString([byte[]]$treeBytes)
    foreach ($record in @($treeText.Split(
        [char[]]@([char]0),
        [System.StringSplitOptions]::RemoveEmptyEntries))) {
        if ($record -notmatch '^(\d+) (blob|tree) ([0-9a-f]{40})\t(.+)$') {
            throw "Publication source commit returned malformed git ls-tree output: $($record -replace "`t", '<TAB>')"
        }
        $path = "$($matches[4])"
        if ($tree.ContainsKey($path)) { throw "Duplicate git tree path: $path" }
        $tree[$path] = [pscustomobject]@{
            Mode = "$($matches[1])"
            Type = "$($matches[2])"
            Blob = "$($matches[3])"
            Path = $path
        }
    }
    $readBlob = {
        param([string]$RepoPath)
        if (-not $tree.ContainsKey($RepoPath)) {
            throw "Source commit $SourceCommit is missing required blob '$RepoPath'."
        }
        $entry = $tree[$RepoPath]
        if ("$($entry.Type)" -ne 'blob' -or
            @('100644', '100755') -notcontains "$($entry.Mode)") {
            throw "Source commit path '$RepoPath' is not a regular git blob."
        }
        $bytes = Invoke-PublicationGitBytes -RepoRoot $root -ArgumentList @(
            'cat-file', 'blob', "$($entry.Blob)"
        )
        if ((Get-PublicationGitObjectId -Type 'blob' -Bytes ([byte[]]$bytes)) -ne "$($entry.Blob)") {
            throw "Git blob bytes do not match object id $($entry.Blob)."
        }
        return [pscustomobject]@{
            Path = $RepoPath
            GitBlob = "$($entry.Blob)"
            Bytes = [byte[]]$bytes
            Length = [long]([byte[]]$bytes).Length
            Sha256 = Get-PublicationByteSha256 -Bytes ([byte[]]$bytes)
        }
    }

    $cfgPath = "$Mod/itemV2.cfg"
    $cfg = & $readBlob $cfgPath
    $cfgText = [System.Text.Encoding]::UTF8.GetString([byte[]]$cfg.Bytes)

    $bundlePrefix = "$Mod/bundleV2/"
    $bundles = @()
    foreach ($repoPath in @($tree.Keys | Where-Object {
        "$_".StartsWith($bundlePrefix, [System.StringComparison]::Ordinal)
    } | Sort-Object)) {
        $proof = & $readBlob "$repoPath"
        $bundles += [pscustomobject]@{
            Path = "$repoPath".Substring($bundlePrefix.Length)
            GitBlob = $proof.GitBlob
            Bytes = [byte[]]$proof.Bytes
            Length = $proof.Length
            Sha256 = $proof.Sha256
        }
    }
    if ($bundles.Count -eq 0) {
        throw "Source commit $SourceCommit contains no bundleV2 blobs for $Mod."
    }

    $configured = ''
    $previewMatch = [regex]::Match($cfgText, '(?i)\bpreview\s*=\s*"((?:[^"\\]|\\.)*)"')
    if ($previewMatch.Success) {
        $configured = $previewMatch.Groups[1].Value.Replace('\"', '"').Replace('\\', '\').Replace('\n', "`n").Replace('\t', "`t")
    }
    $configuredIsSafeLeaf = $configured -and
        -not [System.IO.Path]::IsPathRooted($configured) -and
        [System.IO.Path]::GetFileName($configured) -ceq $configured -and
        $configured -ne '.' -and $configured -ne '..'
    if ($configuredIsSafeLeaf) {
        $configuredIsSafeLeaf =
            $configured.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0 -and
            $configured -ceq $configured.TrimEnd(' ', '.')
    }
    if ($configuredIsSafeLeaf) {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($configured).ToUpperInvariant()
        $configuredIsSafeLeaf = @('CON', 'PRN', 'AUX', 'NUL') -notcontains $stem -and
            $stem -notmatch '^(COM|LPT)[1-9]$'
    }
    $previewName = ''
    if ($configuredIsSafeLeaf -and $tree.ContainsKey("$Mod/$configured")) {
        $previewName = $configured
    }
    else {
        foreach ($candidate in @('item_preview.png', 'preview.jpg', 'preview.png')) {
            if ($tree.ContainsKey("$Mod/$candidate")) {
                $previewName = $candidate
                break
            }
        }
    }
    if (-not $previewName) { $previewName = 'item_preview.png' }
    $previewRepoPath = "$Mod/$previewName"
    $preview = if ($tree.ContainsKey($previewRepoPath)) {
        $proof = & $readBlob $previewRepoPath
        [pscustomobject]@{
            Path = $previewName
            Present = $true
            GitBlob = $proof.GitBlob
            Bytes = [byte[]]$proof.Bytes
            Length = $proof.Length
            Sha256 = $proof.Sha256
        }
    }
    else {
        [pscustomobject]@{
            Path = $previewName
            Present = $false
            GitBlob = ''
            Bytes = [byte[]]@()
            Length = [long]0
            Sha256 = ''
        }
    }

    $luaPath = "$Mod/scripts/mods/$Mod/$Mod.lua"
    $lua = & $readBlob $luaPath
    $luaText = [System.Text.Encoding]::UTF8.GetString([byte[]]$lua.Bytes)
    $versionMatch = [regex]::Match($luaText, 'MOD_VERSION\s*=\s*"([^"]+)"')
    if (-not $versionMatch.Success) {
        throw "Source commit blob '$luaPath' has no MOD_VERSION."
    }
    $idMatch = [regex]::Match($cfgText, 'published_id\s*=\s*(\d+)L?')
    $visibilityMatch = [regex]::Match($cfgText, '(?i)\bvisibility\s*=\s*"((?:[^"\\]|\\.)*)"')
    $publishedId = if ($idMatch.Success) { $idMatch.Groups[1].Value } else { '' }
    $visibility = if ($visibilityMatch.Success) { $visibilityMatch.Groups[1].Value } else { 'private' }

    return [pscustomobject]@{
        SourceCommit = $SourceCommit
        ItemCfg = $cfg
        ItemCfgText = $cfgText
        BundleFiles = $bundles
        PreviewFile = $preview
        Version = $versionMatch.Groups[1].Value
        PublishedId = $publishedId
        Visibility = $visibility
    }
}

function Get-PublicationBundleProof {
    param([string]$RepoRoot, [string]$SourceCommit, [string]$Mod)
    $snapshot = Get-PublicationCommitSnapshot -RepoRoot $RepoRoot -SourceCommit $SourceCommit -Mod $Mod
    return @($snapshot.BundleFiles | ForEach-Object {
        [ordered]@{
            path = $_.Path
            length = [long]$_.Length
            sha256 = $_.Sha256
            git_blob = $_.GitBlob
        }
    })
}

function Get-PublicationPreviewProof {
    param([string]$RepoRoot, [string]$SourceCommit, [string]$Mod)
    $snapshot = Get-PublicationCommitSnapshot -RepoRoot $RepoRoot -SourceCommit $SourceCommit -Mod $Mod
    return [ordered]@{
        path = $snapshot.PreviewFile.Path
        present = [bool]$snapshot.PreviewFile.Present
        length = [long]$snapshot.PreviewFile.Length
        sha256 = $snapshot.PreviewFile.Sha256
        git_blob = $snapshot.PreviewFile.GitBlob
    }
}

function Get-WorkshopPublicationReceiptAssetName {
    param([string]$Mod)

    $slug = "$Mod".Trim()
    if ([string]::IsNullOrWhiteSpace($slug) -or
        $slug -cnotmatch '^[a-z0-9][a-z0-9_-]*$') {
        throw "Workshop publication receipt mod slug must be canonical lowercase, got '$Mod'."
    }
    return "publication-receipt-$slug.json"
}

function New-WorkshopPublicationReceipt {
    param(
        [string]$RepoRoot,
        [string]$Repository,
        [string]$ReleaseTag,
        [string]$ReceiptAssetName,
        [string]$Mod,
        [string]$Version,
        [string]$Owner,
        [string]$SourceCommit,
        [object]$AuthorizationEvidence,
        [datetime]$IssuedAtUtc = ([datetime]::UtcNow),
        [timespan]$Lifetime = ([timespan]::FromMinutes(5))
    )

    if ($Lifetime.TotalSeconds -le 0 -or $Lifetime.TotalMinutes -gt 5) {
        throw 'Workshop publication receipt lifetime must be greater than zero and no longer than five minutes.'
    }
    if ($Repository -ne 'Ensrick/vermintide-2-tweaker') {
        throw "Workshop publication receipt repository must be Ensrick/vermintide-2-tweaker."
    }
    if ([string]::IsNullOrWhiteSpace($ReleaseTag) -or
        $ReceiptAssetName -cnotmatch '^publication-receipt-[a-z0-9_-]+\.json$') {
        throw 'Workshop publication receipt requires an exact release tag and canonical asset name.'
    }
    if (-not $AuthorizationEvidence -or [string]$AuthorizationEvidence.mode -ne 'hosted_qa') {
        throw 'Workshop publication receipt requires independently queried hosted_qa evidence.'
    }
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $snapshot = Get-PublicationCommitSnapshot `
        -RepoRoot $root -SourceCommit $SourceCommit.ToLowerInvariant() -Mod $Mod
    if ([string]::IsNullOrWhiteSpace("$($snapshot.PublishedId)")) {
        throw "Source-commit itemV2.cfg for '$Mod' has no published_id."
    }
    if ("$($snapshot.Version)" -ne "$Version") {
        throw "Receipt version '$Version' does not match source-commit MOD_VERSION '$($snapshot.Version)'."
    }
    $issued = $IssuedAtUtc.ToUniversalTime()
    $expires = $issued.Add($Lifetime)

    return [ordered]@{
        schema = 3
        purpose = if ("$($snapshot.PublishedId)" -eq '0') {
            'workshop_bootstrap'
        } else {
            'workshop_upload'
        }
        nonce = [guid]::NewGuid().ToString('N')
        issued_at_utc = $issued.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        expires_at_utc = $expires.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        repository = $Repository
        release_tag = $ReleaseTag
        receipt_asset_name = $ReceiptAssetName
        source_root = $root
        source_commit = $SourceCommit.ToLowerInvariant()
        mod = $Mod
        version = $Version
        owner = $Owner
        item_cfg_sha256 = $snapshot.ItemCfg.Sha256
        item_cfg_git_blob = $snapshot.ItemCfg.GitBlob
        bundle_files = @($snapshot.BundleFiles | ForEach-Object {
            [ordered]@{
                path = $_.Path
                length = [long]$_.Length
                sha256 = $_.Sha256
                git_blob = $_.GitBlob
            }
        })
        preview_file = [ordered]@{
            path = $snapshot.PreviewFile.Path
            present = [bool]$snapshot.PreviewFile.Present
            length = [long]$snapshot.PreviewFile.Length
            sha256 = $snapshot.PreviewFile.Sha256
            git_blob = $snapshot.PreviewFile.GitBlob
        }
        authorization = $AuthorizationEvidence
    }
}
