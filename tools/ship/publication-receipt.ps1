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
        [version]$MinimumVersion = ([version]'0.6.0'),
        [switch]$RequireReceiptAuthority,
        [switch]$RequireLocalDeployment
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
    if ($RequireReceiptAuthority -and
        $capabilities -notcontains 'receipt-authority-publication-v1') {
        $problems += 'missing capability receipt-authority-publication-v1'
    }
    if ($RequireLocalDeployment) {
        if ($null -eq $reported -or $reported -lt [version]'0.6.2') {
            $problems += 'receipt local deployment requires approved launcher 0.6.2 or newer'
        }
        if ("$($values.deployment_receipt_schema)" -cne '3') {
            $problems += 'deployment_receipt_schema must be 3'
        }
        if ($capabilities -cnotcontains 'receipt-authority-local-deploy-v1') {
            $problems += 'missing capability receipt-authority-local-deploy-v1'
        }
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
        [Parameter(Mandatory = $true)]$LauncherExecutableLease,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [version]$MinimumVersion = ([version]'0.6.0'),
        [switch]$RequireReceiptAuthority,
        [switch]$RequireLocalDeployment
    )

    $run = Invoke-VmbLauncherProcess `
        -Lease $LauncherExecutableLease `
        -ArgumentList @('capabilities', '--no-banner') `
        -WorkingDirectory $WorkingDirectory
    if ($run.ExitCode -ne 0) {
        throw "capability probe exited $($run.ExitCode): $($run.Lines -join ' | ')"
    }
    $verdict = Test-VmbLauncherPublicationCapabilityOutput `
        -Lines @($run.Lines) -MinimumVersion $MinimumVersion `
        -RequireReceiptAuthority:$RequireReceiptAuthority -RequireLocalDeployment:$RequireLocalDeployment
    if (-not $verdict.Ok) {
        throw "VMBLauncher publication capability probe failed: $($verdict.Problems -join '; '). " +
            'Land/install a launcher with every required publication capability before shipping.'
    }
    $verdict | Add-Member -MemberType NoteProperty `
        -Name ExecutableProof -Value $run.ExecutableProof -Force
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

function Get-PublicationCommitBlobProof {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SourceCommit,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'Publication commit blob proof requires a lowercase full source commit SHA.'
    }
    if ([string]::IsNullOrWhiteSpace($RepoPath) -or
        $RepoPath.Contains('\') -or $RepoPath.StartsWith('/') -or
        @($RepoPath.Split('/')) -contains '..') {
        throw "Publication commit blob path is not canonical: '$RepoPath'."
    }

    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $treeBytes = Invoke-PublicationGitBytes -RepoRoot $root -ArgumentList @(
        'ls-tree', '-z', '--full-tree', $SourceCommit, '--', $RepoPath)
    $records = @([System.Text.Encoding]::UTF8.GetString([byte[]]$treeBytes).Split(
        [char[]]@([char]0),
        [System.StringSplitOptions]::RemoveEmptyEntries))
    if ($records.Count -ne 1 -or
        $records[0] -notmatch '^(100644|100755) blob ([0-9a-f]{40})\t(.+)$' -or
        [string]$matches[3] -cne $RepoPath) {
        throw "Source commit $SourceCommit does not bind exactly one regular blob at '$RepoPath'."
    }
    $blob = [string]$matches[2]
    $bytes = Invoke-PublicationGitBytes -RepoRoot $root -ArgumentList @(
        'cat-file', 'blob', $blob)
    if ((Get-PublicationGitObjectId -Type 'blob' -Bytes ([byte[]]$bytes)) -cne $blob) {
        throw "Git blob bytes do not match object id $blob."
    }
    return [pscustomobject][ordered]@{
        Path = $RepoPath
        GitBlob = $blob
        Bytes = [byte[]]$bytes
        Length = [long]([byte[]]$bytes).Length
        Sha256 = Get-PublicationByteSha256 -Bytes ([byte[]]$bytes)
    }
}

function Get-PublicationCommitInventory {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$SourceCommit
    )

    $proof = Get-PublicationCommitBlobProof `
        -RepoRoot $RepoRoot `
        -SourceCommit $SourceCommit `
        -RepoPath 'tools/mod-inventory.psd1'
    $text = [System.Text.Encoding]::UTF8.GetString([byte[]]$proof.Bytes)
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        $text, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        throw "Source-commit mod inventory is not valid PowerShell data: $($parseErrors[0].Message)"
    }
    $rootHash = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.HashtableAst]
    }, $false)
    if ($null -eq $rootHash) {
        throw 'Source-commit mod inventory has no root hashtable.'
    }
    foreach ($token in @($tokens)) {
        if ($token.Kind -in @(
                [System.Management.Automation.Language.TokenKind]::NewLine,
                [System.Management.Automation.Language.TokenKind]::Comment,
                [System.Management.Automation.Language.TokenKind]::EndOfInput)) {
            continue
        }
        if ($token.Extent.StartOffset -lt $rootHash.Extent.StartOffset -or
            $token.Extent.EndOffset -gt $rootHash.Extent.EndOffset) {
            throw 'Source-commit mod inventory contains executable content outside its root data hashtable.'
        }
    }
    try { $inventory = $rootHash.SafeGetValue() }
    catch { throw "Source-commit mod inventory is not a constant data file: $($_.Exception.Message)" }
    if ($inventory -isnot [System.Collections.IDictionary] -or
        -not $inventory.Contains('Mods')) {
        throw 'Source-commit mod inventory lacks a Mods collection.'
    }
    return $inventory
}

function Get-PublicationCommitSnapshot {
    param(
        [string]$RepoRoot,
        [string]$SourceCommit,
        [string]$Mod,
        [switch]$AllowEmptyBundleFiles
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
    $sourceDescriptor = & $readBlob "$Mod/$Mod.mod"

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
    if ($bundles.Count -eq 0 -and -not $AllowEmptyBundleFiles) {
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
        SourceDescriptor = $sourceDescriptor
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
        [Parameter(Mandatory = $true)][object]$PublicationSnapshot,
        [object]$AuthorizationEvidence,
        [datetime]$IssuedAtUtc = ([datetime]::UtcNow),
        [timespan]$Lifetime = ([timespan]::FromMinutes(5)),
        [switch]$LocalDeployment
    )

    if ($Lifetime.TotalSeconds -le 0 -or $Lifetime.TotalMinutes -gt 5) {
        throw 'Workshop publication receipt lifetime must be greater than zero and no longer than five minutes.'
    }
    if ($Repository -ne 'Ensrick/vermintide-2-tweaker') {
        throw "Workshop publication receipt repository must be Ensrick/vermintide-2-tweaker."
    }
    $assetPrefix = if ($LocalDeployment) { 'deployment-receipt-' } else { 'publication-receipt-' }
    if ([string]::IsNullOrWhiteSpace($ReleaseTag) -or
        $ReceiptAssetName -cnotmatch ('\A' + $assetPrefix + '[a-z0-9_-]+\.json\z')) {
        throw 'Workshop publication receipt requires an exact release tag and canonical asset name.'
    }
    if ($LocalDeployment -and ($Mod -cnotmatch '\A[a-z][a-z0-9_]*\z' -or
        $ReceiptAssetName -cne "deployment-receipt-$Mod.json" -or
        $ReleaseTag -cnotmatch '\Amods-[0-9]{4}-[0-9]{2}-[0-9]{2}\z')) {
        throw 'Local deployment requires exact canonical mod/asset/release coordinates.'
    }
    if (-not $AuthorizationEvidence -or [string]$AuthorizationEvidence.mode -ne 'hosted_qa') {
        throw 'Workshop publication receipt requires independently queried hosted_qa evidence.'
    }
    $root = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
    $commitInventory = Get-PublicationCommitInventory `
        -RepoRoot $root `
        -SourceCommit $SourceCommit.ToLowerInvariant()
    $commitEntries = @($commitInventory.Mods | Where-Object { [string]$_.Dir -ceq $Mod })
    if ($commitEntries.Count -ne 1) {
        throw "Workshop publication receipt requires exactly one source-commit inventory entry for '$Mod'."
    }
    $authority = [string]$commitEntries[0].BundleAuthority
    if (@('tracked', 'receipt') -cnotcontains $authority) {
        throw "Workshop publication receipt refuses unsupported BundleAuthority '$authority' for '$Mod'."
    }
    $snapshot = $PublicationSnapshot
    $sourceCommitLower = $SourceCommit.ToLowerInvariant()
    if ([string]$snapshot.SourceCommit -cne $sourceCommitLower -or
        [string]$snapshot.BundleAuthority -cne $authority) {
        throw "Workshop publication snapshot authority does not match source commit $sourceCommitLower for '$Mod'."
    }
    $authorityProof = $snapshot.AuthorityProof
    if ($null -eq $authorityProof -or
        [string]$authorityProof.Authority -cne $authority -or
        [string]$authorityProof.SourceCommit -cne $sourceCommitLower -or
        [string]$authorityProof.RootBundle -cne [string]$commitEntries[0].RootBundle -or
        [string]$authorityProof.InventoryGitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$authorityProof.IgnoreGitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$authorityProof.OutputAlgorithm -eq '' -or
        [string]$authorityProof.OutputFingerprintSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw "Workshop publication snapshot lacks a coherent '$authority' authority proof for '$Mod'."
    }
    if ([string]$snapshot.ItemCfg.GitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
        [string]$snapshot.SourceDescriptor.GitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
        @($snapshot.BundleFiles).Count -eq 0 -or
        ([bool]$snapshot.PreviewFile.Present -and
         [string]$snapshot.PreviewFile.GitBlob -cnotmatch '^[0-9a-f]{40,64}$')) {
        throw "Workshop publication receipt requires exact source-commit proof and a non-empty output map for '$Mod'."
    }
    if ($null -eq $snapshot.OutputSet -or
        [string]$snapshot.OutputSet.Algorithm -cne [string]$authorityProof.OutputAlgorithm -or
        [string]$snapshot.OutputSet.Fingerprint -cne [string]$authorityProof.OutputFingerprintSha256 -or
        @($snapshot.OutputSet.Files).Count -ne @($snapshot.BundleFiles).Count) {
        throw "Workshop publication snapshot output map does not match its authority proof for '$Mod'."
    }
    $seenOutputNames = @{}
    foreach ($bundleFile in @($snapshot.BundleFiles)) {
        $path = [string]$bundleFile.Path
        if ([string]::IsNullOrWhiteSpace($path) -or $seenOutputNames.ContainsKey($path)) {
            throw "Workshop publication snapshot contains a missing, duplicate, or case-colliding output name for '$Mod'."
        }
        $seenOutputNames[$path] = $true
        $outputMatches = @($snapshot.OutputSet.Files | Where-Object { [string]$_.Name -ceq $path })
        if ($outputMatches.Count -ne 1 -or
            [long]$outputMatches[0].Length -ne [long]$bundleFile.Length -or
            [string]$outputMatches[0].Sha256 -cne [string]$bundleFile.Sha256) {
            throw "Workshop publication snapshot output '$path' differs from its complete output map."
        }
    }
    if ($authority -ceq 'tracked') {
        if ([string]$authorityProof.ByteSource -cne 'git_commit_blobs' -or
            @($snapshot.BundleFiles | Where-Object {
                [string]$_.GitBlob -cnotmatch '^[0-9a-f]{40,64}$'
            }).Count -gt 0) {
            throw "Tracked Workshop publication requires an exact Git blob for every selected '$Mod' output byte."
        }
    }
    else {
        if ([string]$authorityProof.ByteSource -cne 'materialized_restrictive_handles' -or
            [string]$authorityProof.BuildReceiptGitBlob -cnotmatch '^[0-9a-f]{40,64}$' -or
            [string]$authorityProof.BuildReceiptSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            [int]$authorityProof.ReceiptSchema -ne 3 -or
            [string]$authorityProof.SourceFingerprintSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            [string]$authorityProof.BuilderName -cne 'VMBLauncher' -or
            [string]::IsNullOrWhiteSpace([string]$authorityProof.BuilderVersion) -or
            [string]$authorityProof.NormalizationPolicyAlgorithm -eq '' -or
            [string]$authorityProof.NormalizationPolicyFingerprintSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            @($snapshot.BundleFiles | Where-Object {
                -not [string]::IsNullOrEmpty([string]$_.GitBlob)
            }).Count -gt 0) {
            throw "Receipt-authority Workshop publication lacks its exact committed build/source/output proof for '$Mod'."
        }
    }
    if ([string]::IsNullOrWhiteSpace("$($snapshot.PublishedId)")) {
        throw "Source-commit itemV2.cfg for '$Mod' has no published_id."
    }
    if ($authority -ceq 'receipt' -and "$($snapshot.PublishedId)" -eq '0') {
        throw 'Receipt authority does not support first-upload bootstrap.'
    }
    if ($LocalDeployment) {
        [uint64]$deploymentId = 0
        if ($authority -cne 'receipt' -or "$($snapshot.PublishedId)" -cnotmatch '\A[1-9][0-9]*\z' -or
            -not [uint64]::TryParse("$($snapshot.PublishedId)", [ref]$deploymentId)) {
            throw 'Local deployment receipt requires receipt authority and a positive canonical Workshop ID.'
        }
    }
    if ("$($snapshot.Version)" -ne "$Version") {
        throw "Receipt version '$Version' does not match source-commit MOD_VERSION '$($snapshot.Version)'."
    }
    $issued = $IssuedAtUtc.ToUniversalTime()
    $expires = $issued.Add($Lifetime)

    $result = [ordered]@{
        schema = 3
        purpose = if ($LocalDeployment) {
            'local_deploy'
        } elseif ("$($snapshot.PublishedId)" -eq '0') {
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
        source_commit = $sourceCommitLower
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
    if ($authority -ceq 'receipt') {
        $result['bundle_authority'] = 'receipt'
        $result['bundle_authority_proof'] = [ordered]@{
            authority = [string]$authorityProof.Authority
            source_commit = [string]$authorityProof.SourceCommit
            inventory_git_blob = [string]$authorityProof.InventoryGitBlob
            ignore_git_blob = [string]$authorityProof.IgnoreGitBlob
            root_bundle = [string]$authorityProof.RootBundle
            byte_source = [string]$authorityProof.ByteSource
            build_receipt_path = "$Mod/.build-receipt.json"
            build_receipt_git_blob = [string]$authorityProof.BuildReceiptGitBlob
            build_receipt_sha256 = [string]$authorityProof.BuildReceiptSha256
            receipt_schema = [int]$authorityProof.ReceiptSchema
            source_fingerprint_sha256 = [string]$authorityProof.SourceFingerprintSha256
            output_algorithm = [string]$authorityProof.OutputAlgorithm
            output_fingerprint_sha256 = [string]$authorityProof.OutputFingerprintSha256
            builder_name = [string]$authorityProof.BuilderName
            builder_version = [string]$authorityProof.BuilderVersion
            normalization_policy_algorithm = [string]$authorityProof.NormalizationPolicyAlgorithm
            normalization_policy_fingerprint_sha256 = [string]$authorityProof.NormalizationPolicyFingerprintSha256
        }
    }
    return $result
}
