# build-receipt.ps1 - deterministic BuildOnly source/root binding for issue #1278.
#
# BuildOnly is allowed to consume a dirty development tree. The receipt records
# both the exact working bytes Stingray consumed and the Git blobs that `git add`
# will commit for every runtime-relevant mod input, plus the generated canonical
# root bundle blob and SHA-256. It contains no timestamp or commit id, so the
# same source/root pair produces identical bytes.
#
# This file is dot-sourced by ship.ps1 and qa/check_build_receipts.ps1. Keep it
# ASCII-only and compatible with Windows PowerShell 5.1.

$script:VtBuildReceiptFileName = '.build-receipt.json'

function Invoke-VtBuildGitCapture {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [hashtable]$Environment = @{}
    )

    if ($Environment.Count -gt 0) {
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = 'git'
        $gitArguments = @('-C', $RepoRoot) + @($Arguments)
        $start.Arguments = (($gitArguments | ForEach-Object {
            ConvertTo-VtBuildWindowsArgument -Value ([string]$_)
        }) -join ' ')
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        foreach ($name in @($Environment.Keys)) {
            $start.EnvironmentVariables[[string]$name] = [string]$Environment[$name]
        }
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $start
        try {
            if (-not $process.Start()) { throw 'Could not start isolated git capture.' }
            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                throw "git $($Arguments -join ' ') failed ($($process.ExitCode)): $stderr"
            }
            $normalized = $stdout.Replace("`r`n", "`n").TrimEnd("`r", "`n")
            if (-not $normalized) { return ,([string[]]@()) }
            return ,([string[]]@($normalized -split "`n"))
        }
        finally {
            $process.Dispose()
        }
    }

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git -C $RepoRoot @Arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed ($exitCode): $($lines -join ' | ')"
    }
    return ,([string[]]$lines)
}

function Get-VtBuildReceiptInventoryEntry {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $inventoryPath = Join-Path $RepoRoot 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Build receipt inventory is missing: $inventoryPath"
    }
    $inventory = Import-PowerShellDataFile -Path $inventoryPath
    $matches = @($inventory.Mods | Where-Object { [string]$_.Dir -ceq $Mod })
    if ($matches.Count -ne 1) {
        throw "Build receipt could not resolve exactly one inventory entry for '$Mod'."
    }
    $entry = $matches[0]
    if ([string]$entry.RootBundle -cnotmatch '^[0-9a-f]{16}\.mod_bundle$') {
        throw "Build receipt inventory has an invalid RootBundle for '$Mod': $($entry.RootBundle)"
    }
    return $entry
}

function Get-VtBuildReceiptPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )
    return (Join-Path (Join-Path $RepoRoot $Mod) $script:VtBuildReceiptFileName)
}

function Test-VtBuildReceiptRelevantPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $rel = $RelativePath.Replace('\', '/')
    while ($rel.StartsWith('./', [System.StringComparison]::Ordinal)) { $rel = $rel.Substring(2) }
    $rel = $rel.TrimStart('/')
    # This is intentionally an allow-by-default provenance boundary. VMB passes
    # the whole mod as Stingray's --source-dir, and a package can refer to files
    # with arbitrary names/extensions. Only the exact self-referential receipt
    # and the generated bundle output tree are proven non-inputs here.
    if (-not $rel -or $rel -eq $script:VtBuildReceiptFileName) { return $false }
    if ($rel -match '^bundleV2/') { return $false }
    return $true
}

function Get-VtBuildSha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-VtBuildFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

function Remove-VtBuildTemporaryDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedPrefix
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    $resolved = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $tempParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ([System.IO.Path]::GetDirectoryName($resolved) -cne $tempParent -or
            -not [System.IO.Path]::GetFileName($resolved).StartsWith(
                $ExpectedPrefix, [System.StringComparison]::Ordinal)) {
        throw "Refusing to remove unexpected BuildOnly temporary directory: $resolved"
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $resolved -Recurse -Force -File)) {
        [System.IO.File]::SetAttributes($file.FullName, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::Delete($file.FullName)
    }
    foreach ($directory in @(Get-ChildItem -LiteralPath $resolved -Recurse -Force -Directory |
            Sort-Object { $_.FullName.Length } -Descending)) {
        [System.IO.Directory]::Delete($directory.FullName, $false)
    }
    [System.IO.Directory]::Delete($resolved, $false)
}

function New-VtBuildSourceMap {
    param([Parameter(Mandatory = $true)][object[]]$Entries)

    $unsorted = @()
    $seen = @{}
    foreach ($entry in @($Entries)) {
        $path = ([string]$entry.Path).Replace('\', '/')
        $blob = ([string]$entry.GitBlob).ToLowerInvariant()
        $buildSha = ([string]$entry.BuildSha256).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($path) -or $path.StartsWith('/') -or
                $path -match '(^|/)\.\.(/|$)' -or -not (Test-VtBuildReceiptRelevantPath -RelativePath $path)) {
            throw "Build receipt source map contains an invalid or non-runtime path: '$path'."
        }
        if ($blob -cnotmatch '^[0-9a-f]{40,64}$') {
            throw "Build receipt source map contains an invalid Git blob for '$path': '$blob'."
        }
        if ($buildSha -cnotmatch '^[0-9a-f]{64}$') {
            throw "Build receipt source map contains an invalid build-byte SHA-256 for '$path': '$buildSha'."
        }
        if ($seen.ContainsKey($path)) {
            throw "Build receipt source map contains duplicate path '$path'."
        }
        $seen[$path] = $true
        $unsorted += [pscustomobject][ordered]@{
            Path = $path
            GitBlob = $blob
            BuildSha256 = $buildSha
        }
    }

    # The receipt is a cross-host build artifact. Use ordinal ordering so the
    # source fingerprint cannot vary with the machine's current culture.
    $orderedPaths = [string[]]@($unsorted | ForEach-Object { $_.Path })
    [System.Array]::Sort($orderedPaths, [System.StringComparer]::Ordinal)
    $byPath = @{}
    foreach ($entry in $unsorted) { $byPath[$entry.Path] = $entry }
    $normalized = @($orderedPaths | ForEach-Object {
        [pscustomobject][ordered]@{
            Path = $_
            GitBlob = $byPath[$_].GitBlob
            BuildSha256 = $byPath[$_].BuildSha256
        }
    })

    $builder = New-Object System.Text.StringBuilder
    foreach ($entry in $normalized) {
        [void]$builder.Append($entry.Path)
        [void]$builder.Append([char]0)
        [void]$builder.Append($entry.GitBlob)
        [void]$builder.Append([char]0)
        [void]$builder.Append($entry.BuildSha256)
        [void]$builder.Append("`n")
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    return [pscustomobject]@{
        Files = @($normalized)
        Fingerprint = Get-VtBuildSha256Hex -Bytes $bytes
    }
}

function Get-VtBuildWorkingSourceMap {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $modRoot = Join-Path $RepoRoot $Mod
    if (-not (Test-Path -LiteralPath $modRoot -PathType Container)) {
        throw "Build receipt mod directory is missing: $modRoot"
    }
    $repoPrefix = "$Mod/"
    $paths = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Arguments @(
        '-c', 'core.quotepath=false', 'ls-files', '--cached', '--others',
        '--exclude-standard', '--', $Mod)
    # Git-ignored files can still be visible to VMB. Include every relevant
    # ignored file so a machine-local input cannot silently influence a root
    # that is later paired with a smaller committed source map.
    $ignoredPaths = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Arguments @(
        '-c', 'core.quotepath=false', 'ls-files', '--others', '--ignored',
        '--exclude-standard', '--', $Mod)
    $paths = @($paths) + @($ignoredPaths)
    $entries = @()
    $objectsPathOutput = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot `
        -Arguments @('rev-parse', '--git-path', 'objects')
    if ($objectsPathOutput.Count -ne 1) { throw 'Cannot resolve the repository Git object directory.' }
    $objectsPath = $objectsPathOutput[0].Trim()
    if (-not [System.IO.Path]::IsPathRooted($objectsPath)) {
        $objectsPath = Join-Path $RepoRoot $objectsPath
    }
    $repositoryObjects = [System.IO.Path]::GetFullPath($objectsPath)
    if (-not (Test-Path -LiteralPath $repositoryObjects -PathType Container)) {
        throw "Repository Git object directory is missing: $repositoryObjects"
    }
    $temporaryObjects = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("vt2-build-receipt-objects-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($temporaryObjects) | Out-Null
    $objectEnvironment = @{
        GIT_OBJECT_DIRECTORY = $temporaryObjects
        GIT_ALTERNATE_OBJECT_DIRECTORIES = $repositoryObjects
    }
    try {
      foreach ($rawPath in @($paths | Sort-Object -Unique)) {
        $repoPath = ([string]$rawPath).Replace('\', '/')
        if (-not $repoPath.StartsWith($repoPrefix, [System.StringComparison]::Ordinal)) {
            throw "Cannot parse working BuildOnly source path: $rawPath"
        }
        $relative = $repoPath.Substring($repoPrefix.Length)
        if (-not (Test-VtBuildReceiptRelevantPath -RelativePath $relative)) { continue }
        $fullPath = Join-Path $RepoRoot ($repoPath.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $fullPath)) {
            # A tracked working-tree deletion is absent from the build input.
            continue
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Build receipt runtime input is not a file: $repoPath"
        }
        $item = Get-Item -LiteralPath $fullPath -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Build receipt refuses reparse-point runtime input: $repoPath"
        }
        # Git's path-aware hash is the clean-filtered blob that `git add` will
        # commit. The raw SHA-256 is what Stingray actually reads. Hash raw bytes
        # on both sides of the Git probe so an internally torn snapshot fails.
        $rawShaBefore = Get-VtBuildFileSha256 -Path $fullPath
        # Write only into an isolated temporary object store: `cat-file
        # --filters` needs an addressable blob, while read-only QA must not add
        # loose objects to the repository merely by validating provenance.
        $hash = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Environment $objectEnvironment `
            -Arguments @('hash-object', '-w', "--path=$repoPath", '--', $fullPath)
        if ($hash.Count -ne 1) { throw "Cannot hash runtime input '$repoPath'." }
        $rawShaAfter = Get-VtBuildFileSha256 -Path $fullPath
        if ($rawShaBefore -cne $rawShaAfter) {
            throw "Runtime input changed while its BuildOnly snapshot was being read: $repoPath"
        }
        $checkoutSha = Get-VtBuildCheckoutSha256 `
            -RepoRoot $RepoRoot -RepoPath $repoPath -GitBlob $hash[0].Trim() `
            -Environment $objectEnvironment
        $entries += [pscustomobject]@{
            Path = $relative
            GitBlob = $hash[0].Trim()
            BuildSha256 = $rawShaAfter
            CheckoutSha256 = $checkoutSha
        }
      }
    }
    finally {
        Remove-VtBuildTemporaryDirectory -Path $temporaryObjects `
            -ExpectedPrefix 'vt2-build-receipt-objects-'
    }
    $map = New-VtBuildSourceMap -Entries $entries
    $reproducibilityProblems = @($entries | Where-Object {
        [string]$_.BuildSha256 -cne [string]$_.CheckoutSha256
    } | ForEach-Object {
        "raw build bytes cannot be reproduced from the Git-clean blob: $($_.Path)"
    })
    $map | Add-Member -MemberType NoteProperty -Name ReproducibilityProblems `
        -Value ([string[]]$reproducibilityProblems)
    return $map
}

function Test-VtBuildWorkingSourceReproducibility {
    param([Parameter(Mandatory = $true)]$SourceMap)

    $problems = @()
    if ($null -ne $SourceMap.PSObject.Properties['ReproducibilityProblems']) {
        $problems = @($SourceMap.ReproducibilityProblems)
    }
    return [pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = @($problems) }
}

function New-VtBuildMaterializationContext {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$Commit
    )

    $root = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("vt2-build-receipt-checkout-" + [guid]::NewGuid().ToString('N'))
    $workTree = Join-Path $root 'worktree'
    $indexPath = Join-Path $root 'index'
    [System.IO.Directory]::CreateDirectory($workTree) | Out-Null
    try {
        if ($Commit) {
            $environment = @{ GIT_INDEX_FILE = $indexPath; GIT_WORK_TREE = $workTree }
            $null = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Environment $environment `
                -Arguments @('read-tree', $Commit)
        }
        else {
            $indexOutput = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot `
                -Arguments @('rev-parse', '--git-path', 'index')
            if ($indexOutput.Count -ne 1) { throw 'Cannot resolve the repository Git index.' }
            $sourceIndex = $indexOutput[0].Trim()
            if (-not [System.IO.Path]::IsPathRooted($sourceIndex)) {
                $sourceIndex = Join-Path $RepoRoot $sourceIndex
            }
            if (-not (Test-Path -LiteralPath $sourceIndex -PathType Leaf)) {
                throw "Repository Git index is missing: $sourceIndex"
            }
            [System.IO.File]::Copy($sourceIndex, $indexPath, $false)
            $environment = @{ GIT_INDEX_FILE = $indexPath; GIT_WORK_TREE = $workTree }
        }
        return [pscustomobject]@{
            Root = $root
            WorkTree = $workTree
            Environment = $environment
        }
    }
    catch {
        Remove-VtBuildTemporaryDirectory -Path $root `
            -ExpectedPrefix 'vt2-build-receipt-checkout-'
        throw
    }
}

function Initialize-VtBuildMaterializationAttributes {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $paths = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Environment $Context.Environment `
        -Arguments @('-c', 'core.quotepath=false', 'ls-files')
    foreach ($path in @($paths | Where-Object {
        $_ -ceq '.gitattributes' -or
        ($_ -match ('^' + [regex]::Escape($Mod) + '/(?:.*/)?\.gitattributes$'))
    })) {
        $null = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Environment $Context.Environment `
            -Arguments @('checkout-index', '--force', "--prefix=$($Context.WorkTree.Replace('\', '/'))/", '--', $path)
    }
}

function Get-VtBuildMaterializedFileSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][string]$RepoPath
    )

    $null = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Environment $Context.Environment `
        -Arguments @('checkout-index', '--force', "--prefix=$($Context.WorkTree.Replace('\', '/'))/", '--', $RepoPath)
    $fullPath = Join-Path $Context.WorkTree ($RepoPath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Git did not materialize staged/committed runtime input: $RepoPath"
    }
    $item = Get-Item -LiteralPath $fullPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Git materialized a reparse-point runtime input: $RepoPath"
    }
    return Get-VtBuildFileSha256 -Path $fullPath
}

function Remove-VtBuildMaterializationContext {
    param([Parameter(Mandatory = $true)]$Context)
    if ($Context -and (Test-Path -LiteralPath $Context.Root -PathType Container)) {
        Remove-VtBuildTemporaryDirectory -Path ([string]$Context.Root) `
            -ExpectedPrefix 'vt2-build-receipt-checkout-'
    }
}

function Get-VtBuildIndexSourceMap {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $repoPrefix = "$Mod/"
    $materialization = New-VtBuildMaterializationContext -RepoRoot $RepoRoot
    try {
      Initialize-VtBuildMaterializationAttributes -RepoRoot $RepoRoot `
          -Context $materialization -Mod $Mod
      $lines = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Environment $materialization.Environment `
          -Arguments @('-c', 'core.quotepath=false', 'ls-files', '--stage', '--', $Mod)
      $entries = @()
      foreach ($line in $lines) {
        if ($line -notmatch '^(?<mode>\d+) (?<blob>[0-9a-fA-F]{40,64}) (?<stage>\d+)\t(?<path>.+)$') {
            throw "Cannot parse staged BuildOnly source entry: $line"
        }
        if ($matches['stage'] -ne '0') {
            throw "Build receipt refuses unmerged index entry: $($matches['path']) (stage $($matches['stage']))."
        }
        $repoPath = $matches['path'].Replace('\', '/')
        if (-not $repoPath.StartsWith($repoPrefix, [System.StringComparison]::Ordinal)) {
            throw "Cannot parse staged BuildOnly source path: $($matches['path'])"
        }
        $relative = $repoPath.Substring($repoPrefix.Length)
        if (Test-VtBuildReceiptRelevantPath -RelativePath $relative) {
            if ($matches['mode'] -notin @('100644', '100755')) {
                throw "Build receipt refuses non-regular staged runtime input: $repoPath (mode $($matches['mode']))."
            }
            $blob = $matches['blob'].ToLowerInvariant()
            $entries += [pscustomobject]@{
                Path = $relative
                GitBlob = $blob
                BuildSha256 = Get-VtBuildMaterializedFileSha256 `
                    -RepoRoot $RepoRoot -Context $materialization -RepoPath $repoPath
            }
        }
      }
      return New-VtBuildSourceMap -Entries $entries
    }
    finally {
        Remove-VtBuildMaterializationContext -Context $materialization
    }
}

function Get-VtBuildCommitSourceMap {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    $repoPrefix = "$Mod/"
    $materialization = New-VtBuildMaterializationContext -RepoRoot $RepoRoot -Commit $Commit
    try {
      Initialize-VtBuildMaterializationAttributes -RepoRoot $RepoRoot `
          -Context $materialization -Mod $Mod
      $lines = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Environment $materialization.Environment `
          -Arguments @('-c', 'core.quotepath=false', 'ls-files', '--stage', '--', $Mod)
      $entries = @()
      foreach ($line in $lines) {
        if ($line -notmatch '^(?<mode>\d+) (?<blob>[0-9a-fA-F]{40,64}) (?<stage>\d+)\t(?<path>.+)$') {
            throw "Cannot parse committed BuildOnly source entry: $line"
        }
        if ($matches['stage'] -ne '0') {
            throw "Build receipt refuses unmerged committed entry: $($matches['path'])."
        }
        $repoPath = $matches['path'].Replace('\', '/')
        if (-not $repoPath.StartsWith($repoPrefix, [System.StringComparison]::Ordinal)) {
            throw "Cannot parse committed BuildOnly source path: $($matches['path'])"
        }
        $relative = $repoPath.Substring($repoPrefix.Length)
        if (Test-VtBuildReceiptRelevantPath -RelativePath $relative) {
            if ($matches['mode'] -notin @('100644', '100755')) {
                throw "Build receipt refuses non-regular committed runtime input: $repoPath (mode $($matches['mode']))."
            }
            $blob = $matches['blob'].ToLowerInvariant()
            $entries += [pscustomobject]@{
                Path = $relative
                GitBlob = $blob
                BuildSha256 = Get-VtBuildMaterializedFileSha256 `
                    -RepoRoot $RepoRoot -Context $materialization -RepoPath $repoPath
            }
        }
      }
      return New-VtBuildSourceMap -Entries $entries
    }
    finally {
        Remove-VtBuildMaterializationContext -Context $materialization
    }
}

function Compare-VtBuildSourceMaps {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual
    )

    $problems = @()
    $expectedByPath = @{}
    $actualByPath = @{}
    foreach ($entry in @($Expected.Files)) { $expectedByPath[[string]$entry.Path] = $entry }
    foreach ($entry in @($Actual.Files)) { $actualByPath[[string]$entry.Path] = $entry }
    foreach ($path in @($expectedByPath.Keys | Sort-Object)) {
        if (-not $actualByPath.ContainsKey($path)) {
            $problems += "source removed after receipt: $path"
        }
        else {
            $expectedEntry = $expectedByPath[$path]
            $actualEntry = $actualByPath[$path]
            if ([string]$expectedEntry.GitBlob -cne [string]$actualEntry.GitBlob) {
                $problems += "source bytes changed after receipt (Git-clean blob): $path"
            }
            if ([string]$expectedEntry.BuildSha256 -cne [string]$actualEntry.BuildSha256) {
                $problems += "source bytes changed after receipt (raw build bytes): $path"
            }
        }
    }
    foreach ($path in @($actualByPath.Keys | Sort-Object)) {
        if (-not $expectedByPath.ContainsKey($path)) {
            $problems += "source added after receipt: $path"
        }
    }
    if ([string]$Expected.Fingerprint -cne [string]$Actual.Fingerprint -and $problems.Count -eq 0) {
        $problems += 'source fingerprint changed without a path-level difference'
    }
    return [pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = @($problems) }
}

function ConvertTo-VtBuildWindowsArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Get-VtBuildGitOutputSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Description,
        [hashtable]$Environment = @{}
    )

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = 'git'
    $gitArguments = @('-C', $RepoRoot) + @($Arguments)
    $start.Arguments = (($gitArguments | ForEach-Object {
        ConvertTo-VtBuildWindowsArgument -Value ([string]$_)
    }) -join ' ')
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($name in @($Environment.Keys)) {
        $start.EnvironmentVariables[[string]$name] = [string]$Environment[$name]
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        if (-not $process.Start()) { throw "Could not start git for $Description." }
        $hash = $sha.ComputeHash($process.StandardOutput.BaseStream)
        $errorText = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "git failed while hashing $Description ($($process.ExitCode)): $errorText"
        }
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
        $process.Dispose()
    }
}

function Get-VtBuildGitBlobSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$GitBlob
    )

    if ($GitBlob -cnotmatch '^[0-9a-f]{40,64}$') { throw "Invalid Git blob id: $GitBlob" }
    return Get-VtBuildGitOutputSha256 -RepoRoot $RepoRoot `
        -Arguments @('cat-file', 'blob', $GitBlob) -Description "Git blob $GitBlob"
}

function Get-VtBuildCheckoutSha256 {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter(Mandatory = $true)][string]$GitBlob,
        [hashtable]$Environment = @{}
    )

    if ($GitBlob -cnotmatch '^[0-9a-f]{40,64}$') { throw "Invalid Git blob id: $GitBlob" }
    $path = $RepoPath.Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($path) -or $path.StartsWith('/') -or $path -match '(^|/)\.\.(/|$)') {
        throw "Invalid checkout-materialization path: $RepoPath"
    }
    # `cat-file --filters --path` applies the same checkout/smudge conversion as
    # Git uses to materialize the staged or committed blob into the working tree.
    # Its SHA-256 therefore proves that the raw bytes recorded at BuildOnly time
    # can actually be reproduced after the receipt is committed and checked out.
    return Get-VtBuildGitOutputSha256 -RepoRoot $RepoRoot `
        -Arguments @('cat-file', '--filters', "--path=$path", $GitBlob) `
        -Description "checkout bytes for $path" -Environment $Environment
}

function Get-VtBuildWorkingRootProof {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $entry = Get-VtBuildReceiptInventoryEntry -RepoRoot $RepoRoot -Mod $Mod
    $name = [string]$entry.RootBundle
    $repoPath = "$Mod/bundleV2/$name"
    $fullPath = Join-Path $RepoRoot ($repoPath.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Build receipt root bundle is missing: $repoPath"
    }
    $item = Get-Item -LiteralPath $fullPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Build receipt refuses reparse-point root bundle: $repoPath"
    }
    $rawShaBefore = Get-VtBuildFileSha256 -Path $fullPath
    $blob = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Arguments @(
        'hash-object', "--path=$repoPath", '--', $fullPath)
    if ($blob.Count -ne 1) { throw "Cannot hash BuildOnly root bundle '$repoPath'." }
    $rawShaAfter = Get-VtBuildFileSha256 -Path $fullPath
    if ($rawShaBefore -cne $rawShaAfter) {
        throw "Canonical root changed while its BuildOnly proof was being read: $repoPath"
    }
    return [pscustomobject]@{
        Name = $name
        GitBlob = $blob[0].Trim().ToLowerInvariant()
        Sha256 = $rawShaAfter
    }
}

function Get-VtBuildIndexRootProof {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $entry = Get-VtBuildReceiptInventoryEntry -RepoRoot $RepoRoot -Mod $Mod
    $name = [string]$entry.RootBundle
    $repoPath = "$Mod/bundleV2/$name"
    $lines = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Arguments @(
        '-c', 'core.quotepath=false', 'ls-files', '--stage', '--', $repoPath)
    if ($lines.Count -ne 1 -or
            $lines[0] -notmatch '^\d+ (?<blob>[0-9a-fA-F]{40,64}) 0\t(?<path>.+)$' -or
            $matches['path'].Replace('\', '/') -cne $repoPath) {
        throw "Build receipt cannot resolve staged canonical root bundle: $repoPath"
    }
    $blob = $matches['blob'].ToLowerInvariant()
    return [pscustomobject]@{
        Name = $name
        GitBlob = $blob
        Sha256 = Get-VtBuildGitBlobSha256 -RepoRoot $RepoRoot -GitBlob $blob
    }
}

function Get-VtBuildCommitRootProof {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)][string]$Commit
    )

    $entry = Get-VtBuildReceiptInventoryEntry -RepoRoot $RepoRoot -Mod $Mod
    $name = [string]$entry.RootBundle
    $repoPath = "$Mod/bundleV2/$name"
    $lines = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Arguments @(
        '-c', 'core.quotepath=false', 'ls-tree', $Commit, '--', $repoPath)
    if ($lines.Count -ne 1 -or
            $lines[0] -notmatch '^\d+ blob (?<blob>[0-9a-fA-F]{40,64})\t(?<path>.+)$' -or
            $matches['path'].Replace('\', '/') -cne $repoPath) {
        throw "Build receipt cannot resolve committed canonical root bundle: ${Commit}:$repoPath"
    }
    $blob = $matches['blob'].ToLowerInvariant()
    return [pscustomobject]@{
        Name = $name
        GitBlob = $blob
        Sha256 = Get-VtBuildGitBlobSha256 -RepoRoot $RepoRoot -GitBlob $blob
    }
}

function New-VtBuildReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$SourceMap,
        [Parameter(Mandatory = $true)]$RootProof
    )

    $sourceFiles = @($SourceMap.Files | ForEach-Object {
        [pscustomobject][ordered]@{
            path = [string]$_.Path
            git_blob = ([string]$_.GitBlob).ToLowerInvariant()
            build_sha256 = ([string]$_.BuildSha256).ToLowerInvariant()
        }
    })
    return [pscustomobject][ordered]@{
        schema = 2
        mod = $Mod
        source_algorithm = 'git-blob-build-byte-map-sha256-v2'
        source_fingerprint_sha256 = ([string]$SourceMap.Fingerprint).ToLowerInvariant()
        source_files = $sourceFiles
        root_bundle = [string]$RootProof.Name
        root_bundle_git_blob = ([string]$RootProof.GitBlob).ToLowerInvariant()
        root_bundle_sha256 = ([string]$RootProof.Sha256).ToLowerInvariant()
    }
}

function ConvertTo-VtBuildReceiptJson {
    param([Parameter(Mandatory = $true)]$Receipt)
    # Pretty-print indentation differs between Windows PowerShell 5.1 and
    # PowerShell 7. Compressed ordered JSON is byte-identical on both hosts.
    $json = $Receipt | ConvertTo-Json -Depth 6 -Compress
    return (($json -replace "`r`n", "`n").TrimEnd([char[]]@("`r", "`n")) + "`n")
}

function Write-VtBuildReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$Receipt
    )

    $path = Get-VtBuildReceiptPath -RepoRoot $RepoRoot -Mod $Mod
    $json = ConvertTo-VtBuildReceiptJson -Receipt $Receipt
    [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

function ConvertFrom-VtBuildReceiptJson {
    param([Parameter(Mandatory = $true)][string]$Json)
    try {
        return ($Json | ConvertFrom-Json)
    }
    catch {
        throw "Build receipt is not valid JSON: $($_.Exception.Message)"
    }
}

function Test-VtBuildReceiptProof {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedMod,
        [Parameter(Mandatory = $true)]$SourceMap,
        [Parameter(Mandatory = $true)]$RootProof
    )

    $problems = @()
    $schema = $null
    try { $schema = [System.Convert]::ToInt32($Receipt.schema) } catch { }
    if ($schema -eq 1) {
        $problems += 'legacy receipt schema 1 lacks exact raw build-byte proof; rerun BuildOnly'
    }
    elseif ($schema -ne 2) { $problems += "unsupported receipt schema '$($Receipt.schema)'" }
    if ([string]$Receipt.mod -cne $ExpectedMod) { $problems += "receipt mod '$($Receipt.mod)' is not '$ExpectedMod'" }
    if ([string]$Receipt.source_algorithm -cne 'git-blob-build-byte-map-sha256-v2') {
        $problems += "unsupported source algorithm '$($Receipt.source_algorithm)'"
    }
    if ([string]$Receipt.source_fingerprint_sha256 -cnotmatch '^[0-9a-f]{64}$') {
        $problems += 'receipt source fingerprint is not lowercase SHA-256'
    }
    if ([string]$Receipt.root_bundle -cne [string]$RootProof.Name) {
        $problems += "receipt root '$($Receipt.root_bundle)' is not canonical root '$($RootProof.Name)'"
    }
    if ([string]$Receipt.root_bundle_git_blob -cnotmatch '^[0-9a-f]{40,64}$') {
        $problems += 'receipt root Git blob is invalid'
    }
    elseif ([string]$Receipt.root_bundle_git_blob -cne [string]$RootProof.GitBlob) {
        $problems += "root bundle Git blob differs from receipt: $($RootProof.Name)"
    }
    if ([string]$Receipt.root_bundle_sha256 -cnotmatch '^[0-9a-f]{64}$') {
        $problems += 'receipt root SHA-256 is invalid'
    }
    elseif ([string]$Receipt.root_bundle_sha256 -cne [string]$RootProof.Sha256) {
        $problems += "root bundle SHA-256 differs from receipt: $($RootProof.Name)"
    }

    try {
        $workingReproducibility = Test-VtBuildWorkingSourceReproducibility -SourceMap $SourceMap
        if (-not $workingReproducibility.Ok) {
            $problems += @($workingReproducibility.Problems)
        }
        $receiptEntries = @($Receipt.source_files | ForEach-Object {
            [pscustomobject]@{
                Path = [string]$_.path
                GitBlob = [string]$_.git_blob
                BuildSha256 = [string]$_.build_sha256
            }
        })
        if ($null -eq $Receipt.source_files -or $receiptEntries.Count -eq 0) {
            throw 'Build receipt source_files map is missing or empty.'
        }
        $receiptMap = New-VtBuildSourceMap -Entries $receiptEntries
        if ([string]$Receipt.source_fingerprint_sha256 -cne [string]$receiptMap.Fingerprint) {
            $problems += 'receipt source fingerprint does not match its source_files map'
        }
        $mapComparison = Compare-VtBuildSourceMaps -Expected $receiptMap -Actual $SourceMap
        if (-not $mapComparison.Ok) { $problems += @($mapComparison.Problems) }
    }
    catch {
        $problems += $_.Exception.Message
    }
    return [pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = @($problems) }
}
