# build-receipt.ps1 - deterministic BuildOnly provenance binding (#1278, #1400).
#
# BuildOnly is allowed to consume a dirty development tree. The receipt records
# the exact source bytes Stingray consumed, the complete normalized bundleV2
# output identity, the VMBLauncher version, and the exact normalization policy.
# It contains no timestamp or commit id, so the same build proof is deterministic.
#
# This file is dot-sourced by ship.ps1 and qa/check_build_receipts.ps1. Keep it
# ASCII-only and compatible with Windows PowerShell 5.1.

$script:VtBuildReceiptFileName = '.build-receipt.json'
$script:VtBuildReceiptBuilderName = 'VMBLauncher'
$script:VtBuildReceiptAuthorityHelperPath = Join-Path $PSScriptRoot 'bundle-authority.ps1'
if (-not (Test-Path -LiteralPath $script:VtBuildReceiptAuthorityHelperPath -PathType Leaf)) {
    throw "Build receipt authority helpers are missing: $script:VtBuildReceiptAuthorityHelperPath"
}
. $script:VtBuildReceiptAuthorityHelperPath
$script:VtBuildReceiptOutputHelperPath = Join-Path $PSScriptRoot 'bundle-output-set.ps1'
if (-not (Test-Path -LiteralPath $script:VtBuildReceiptOutputHelperPath -PathType Leaf)) {
    throw "Build receipt output-set helpers are missing: $script:VtBuildReceiptOutputHelperPath"
}
. $script:VtBuildReceiptOutputHelperPath

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

function Assert-VtBuildReceiptInventoryEntry {
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    if ([string]$Entry.Dir -cne $Mod) {
        throw "Build receipt inventory entry '$($Entry.Dir)' is not '$Mod'."
    }
    $authorityErrors = @(Get-VtBundleAuthorityEntryErrors -Entry $Entry)
    if ($authorityErrors.Count -gt 0) {
        throw "Build receipt inventory entry for '$Mod' is invalid: $($authorityErrors -join '; ')"
    }
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
    Assert-VtBuildReceiptInventoryEntry -Entry $entry -Mod $Mod
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
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes
    )

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
    $temporaryObjects = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("vt2-build-receipt-objects-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($temporaryObjects) | Out-Null
    # Never expose the repository object store as an alternate. Git may
    # "freshen" an already-present loose object in an alternate when
    # `hash-object -w` sees the same OID, which makes a nominally read-only
    # provenance check mutate repository metadata. The temporary store owns
    # every addressable clean-filtered blob needed by `cat-file --filters`.
    $objectEnvironment = @{
        GIT_OBJECT_DIRECTORY = $temporaryObjects
        GIT_ALTERNATE_OBJECT_DIRECTORIES = ''
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
        # or freshen loose objects in the repository merely by validating
        # provenance.
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

function Get-VtBuildGitBlobLength {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$GitBlob
    )

    if ($GitBlob -cnotmatch '^[0-9a-f]{40,64}$') { throw "Invalid Git blob id: $GitBlob" }
    $lines = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot `
        -Arguments @('cat-file', '-s', $GitBlob)
    if ($lines.Count -ne 1 -or [string]$lines[0] -cnotmatch '^\d+$') {
        throw "Cannot resolve Git blob length: $GitBlob"
    }
    try { return [System.Convert]::ToInt64($lines[0]) }
    catch { throw "Git blob length is outside Int64 range: $GitBlob ($($lines[0]))" }
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

function Get-VtBuildDescriptorSourceProof {
    param(
        [Parameter(Mandatory = $true)]$SourceMap,
        [Parameter(Mandatory = $true)][string]$Mod
    )

    $sourcePath = "$Mod.mod"
    $matches = @($SourceMap.Files | Where-Object { [string]$_.Path -ceq $sourcePath })
    if ($matches.Count -ne 1) {
        throw "Build receipt source map must contain exactly one descriptor source '$sourcePath'."
    }
    $sha256 = ([string]$matches[0].BuildSha256).ToLowerInvariant()
    if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw "Build receipt descriptor source has an invalid build SHA-256: $sourcePath"
    }
    return [pscustomobject]@{ Path = $sourcePath; Sha256 = $sha256 }
}

function Get-VtBuildWorkingOutputSet {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$SourceMap,
        $InventoryEntry
    )

    if ($null -eq $InventoryEntry) {
        $InventoryEntry = Get-VtBuildReceiptInventoryEntry -RepoRoot $RepoRoot -Mod $Mod
    }
    Assert-VtBuildReceiptInventoryEntry -Entry $InventoryEntry -Mod $Mod
    $descriptor = Get-VtBuildDescriptorSourceProof -SourceMap $SourceMap -Mod $Mod
    $bundleDirectory = Join-Path (Join-Path $RepoRoot $Mod) 'bundleV2'
    return Get-VtBundleOutputSet -BundleDirectory $bundleDirectory `
        -ExpectedDescriptorName "$Mod.mod" `
        -ExpectedRootBundle ([string]$InventoryEntry.RootBundle) `
        -ExpectedDescriptorSha256 $descriptor.Sha256
}

function Get-VtBuildIndexOutputSet {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$SourceMap,
        $InventoryEntry
    )

    if ($null -eq $InventoryEntry) {
        $InventoryEntry = Get-VtBuildReceiptInventoryEntry -RepoRoot $RepoRoot -Mod $Mod
    }
    Assert-VtBuildReceiptInventoryEntry -Entry $InventoryEntry -Mod $Mod
    $descriptor = Get-VtBuildDescriptorSourceProof -SourceMap $SourceMap -Mod $Mod
    $prefix = "$Mod/bundleV2/"
    $lines = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Arguments @(
        '-c', 'core.quotepath=false', 'ls-files', '--stage', '--', "$Mod/bundleV2")
    $records = @()
    foreach ($line in $lines) {
        if ($line -notmatch '^(?<mode>\d+) (?<blob>[0-9a-fA-F]{40,64}) (?<stage>\d+)\t(?<path>.+)$') {
            throw "Cannot parse staged BuildOnly output entry: $line"
        }
        if ($matches['stage'] -ne '0') {
            throw "Build receipt refuses unmerged staged output: $($matches['path']) (stage $($matches['stage']))."
        }
        if ($matches['mode'] -notin @('100644', '100755')) {
            throw "Build receipt refuses non-regular staged output: $($matches['path']) (mode $($matches['mode']))."
        }
        $repoPath = $matches['path'].Replace('\', '/')
        if (-not $repoPath.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            throw "Cannot parse staged BuildOnly output path: $repoPath"
        }
        $name = $repoPath.Substring($prefix.Length)
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('/')) {
            throw "Build receipt output must be a direct bundleV2 file: $repoPath"
        }
        $blob = $matches['blob'].ToLowerInvariant()
        $records += [pscustomobject]@{
            Name = $name
            Length = Get-VtBuildGitBlobLength -RepoRoot $RepoRoot -GitBlob $blob
            Sha256 = Get-VtBuildGitBlobSha256 -RepoRoot $RepoRoot -GitBlob $blob
        }
    }
    return New-VtBundleOutputSet -Records $records `
        -ExpectedDescriptorName "$Mod.mod" `
        -ExpectedRootBundle ([string]$InventoryEntry.RootBundle) `
        -ExpectedDescriptorSha256 $descriptor.Sha256
}

function Get-VtBuildCommitOutputSet {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)]$SourceMap,
        $InventoryEntry
    )

    if ($null -eq $InventoryEntry) {
        $InventoryEntry = Get-VtBuildReceiptInventoryEntry -RepoRoot $RepoRoot -Mod $Mod
    }
    Assert-VtBuildReceiptInventoryEntry -Entry $InventoryEntry -Mod $Mod
    $descriptor = Get-VtBuildDescriptorSourceProof -SourceMap $SourceMap -Mod $Mod
    $prefix = "$Mod/bundleV2/"
    $lines = Invoke-VtBuildGitCapture -RepoRoot $RepoRoot -Arguments @(
        '-c', 'core.quotepath=false', 'ls-tree', '-r', $Commit, '--', "$Mod/bundleV2")
    $records = @()
    foreach ($line in $lines) {
        if ($line -notmatch '^(?<mode>\d+) (?<type>\S+) (?<blob>[0-9a-fA-F]{40,64})\t(?<path>.+)$') {
            throw "Cannot parse committed BuildOnly output entry: $line"
        }
        if ($matches['type'] -cne 'blob' -or $matches['mode'] -notin @('100644', '100755')) {
            throw "Build receipt refuses non-regular committed output: $($matches['path']) (mode $($matches['mode']) type $($matches['type']))."
        }
        $repoPath = $matches['path'].Replace('\', '/')
        if (-not $repoPath.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            throw "Cannot parse committed BuildOnly output path: $repoPath"
        }
        $name = $repoPath.Substring($prefix.Length)
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('/')) {
            throw "Build receipt output must be a direct bundleV2 file: $repoPath"
        }
        $blob = $matches['blob'].ToLowerInvariant()
        $records += [pscustomobject]@{
            Name = $name
            Length = Get-VtBuildGitBlobLength -RepoRoot $RepoRoot -GitBlob $blob
            Sha256 = Get-VtBuildGitBlobSha256 -RepoRoot $RepoRoot -GitBlob $blob
        }
    }
    return New-VtBundleOutputSet -Records $records `
        -ExpectedDescriptorName "$Mod.mod" `
        -ExpectedRootBundle ([string]$InventoryEntry.RootBundle) `
        -ExpectedDescriptorSha256 $descriptor.Sha256
}

function Get-VtBuildNormalizationPolicyFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ExcludedOutputs
    )

    $builder = New-Object System.Text.StringBuilder
    foreach ($entry in @($ExcludedOutputs)) {
        [void]$builder.Append([string]$entry.filename)
        [void]$builder.Append([char]0)
        [void]$builder.Append([string]$entry.sha256)
        [void]$builder.Append("`n")
    }
    return Get-VtBuildSha256Hex -Bytes ([System.Text.Encoding]::UTF8.GetBytes($builder.ToString()))
}

function ConvertTo-VtBuildNormalizationPolicyRecord {
    param(
        [Parameter(Mandatory = $true)]$Policy,
        [switch]$Serialized
    )

    if ($Serialized) {
        $algorithm = [string]$Policy.algorithm
        $fingerprint = [string]$Policy.fingerprint_sha256
        $excluded = @($Policy.excluded_outputs)
    }
    else {
        foreach ($required in @('Algorithm', 'FingerprintSha256', 'ExcludedOutputs')) {
            if ($null -eq $Policy.PSObject.Properties[$required]) {
                throw "Build receipt normalization policy lacks canonical '$required'."
            }
        }
        $algorithm = [string]$Policy.Algorithm
        $fingerprint = [string]$Policy.FingerprintSha256
        $excluded = @($Policy.ExcludedOutputs)
    }
    if ($algorithm -cne 'exact-build-artifact-exclusions-sha256-v1') {
        throw "Build receipt normalization policy has an unsupported algorithm: '$algorithm'."
    }
    if ($fingerprint -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Build receipt normalization policy fingerprint is not lowercase SHA-256.'
    }

    $seen = @{}
    $byName = @{}
    foreach ($entry in $excluded) {
        $name = if ($Serialized) { [string]$entry.filename } else { [string]$entry.Filename }
        $sha256 = if ($Serialized) { [string]$entry.sha256 } else { [string]$entry.Sha256 }
        if ([string]::IsNullOrWhiteSpace($name) -or
                [System.IO.Path]::GetFileName($name) -cne $name) {
            throw "Build receipt normalization policy has an invalid excluded output: '$name'."
        }
        if ($sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw "Build receipt normalization policy has an invalid SHA-256 for '$name'."
        }
        if ($seen.ContainsKey($name)) {
            throw "Build receipt normalization policy has duplicate excluded output '$name'."
        }
        $seen[$name] = $true
        $byName[$name] = $sha256
    }
    $names = [string[]]@($byName.Keys)
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    $normalized = @($names | ForEach-Object {
        [pscustomobject][ordered]@{ filename = $_; sha256 = $byName[$_] }
    })
    $computedFingerprint = Get-VtBuildNormalizationPolicyFingerprint -ExcludedOutputs $normalized
    if ($fingerprint -cne $computedFingerprint) {
        throw 'Build receipt normalization policy fingerprint does not match excluded outputs.'
    }
    return [pscustomobject][ordered]@{
        algorithm = $algorithm
        fingerprint_sha256 = $fingerprint
        excluded_outputs = @($normalized)
    }
}

function Get-VtBuildNormalizationOutputProblems {
    param(
        [Parameter(Mandatory = $true)]$OutputSet,
        [Parameter(Mandatory = $true)]$PolicyRecord,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $outputNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($file in @($OutputSet.Files)) {
        $name = if ($null -ne $file.PSObject.Properties['Name']) {
            [string]$file.Name
        }
        else {
            [string]$file.filename
        }
        [void]$outputNames.Add($name)
    }

    $problems = @()
    foreach ($excluded in @($PolicyRecord.excluded_outputs)) {
        $name = [string]$excluded.filename
        if ($outputNames.Contains($name)) {
            $problems += "$Label normalization policy excluded output remains in the complete output set: $name"
        }
    }
    return @($problems)
}

function New-VtBuildReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$Mod,
        [Parameter(Mandatory = $true)]$SourceMap,
        [Parameter(Mandatory = $true)]$OutputSet,
        [Parameter(Mandatory = $true)][string]$BuilderVersion,
        [Parameter(Mandatory = $true)]$NormalizationPolicy
    )

    if ([string]::IsNullOrWhiteSpace($BuilderVersion) -or $BuilderVersion -cne $BuilderVersion.Trim()) {
        throw 'Build receipt builder version must be a non-empty exact string.'
    }
    $canonicalSourceMap = New-VtBuildSourceMap -Entries @($SourceMap.Files)
    if ([string]$SourceMap.Fingerprint -cne [string]$canonicalSourceMap.Fingerprint) {
        throw 'Build receipt source fingerprint does not match its source files.'
    }
    $descriptorSource = Get-VtBuildDescriptorSourceProof -SourceMap $canonicalSourceMap -Mod $Mod
    if ([string]$OutputSet.Descriptor.Name -cne "$Mod.mod") {
        throw "Build receipt output descriptor '$($OutputSet.Descriptor.Name)' is not '$Mod.mod'."
    }
    if ([string]$OutputSet.Descriptor.Sha256 -cne $descriptorSource.Sha256) {
        throw "Build receipt output descriptor differs from source descriptor: $($descriptorSource.Path)"
    }
    if ([string]$OutputSet.Algorithm -cnotmatch '^[a-z0-9][a-z0-9._-]*$' -or
            [string]$OutputSet.Fingerprint -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Build receipt output set has an invalid algorithm or fingerprint.'
    }
    $canonicalOutputSet = New-VtBundleOutputSet -Records @($OutputSet.Files) `
        -ExpectedDescriptorName "$Mod.mod" `
        -ExpectedRootBundle ([string]$OutputSet.Root.Name) `
        -ExpectedDescriptorSha256 $descriptorSource.Sha256
    if ([string]$OutputSet.Algorithm -cne [string]$canonicalOutputSet.Algorithm -or
            [string]$OutputSet.Fingerprint -cne [string]$canonicalOutputSet.Fingerprint -or
            [string]$OutputSet.Root.Sha256 -cne [string]$canonicalOutputSet.Root.Sha256 -or
            [string]$OutputSet.Descriptor.Sha256 -cne [string]$canonicalOutputSet.Descriptor.Sha256) {
        throw 'Build receipt output-set identity does not match its files.'
    }

    $normalization = ConvertTo-VtBuildNormalizationPolicyRecord -Policy $NormalizationPolicy
    $normalizationProblems = @(Get-VtBuildNormalizationOutputProblems `
        -OutputSet $canonicalOutputSet `
        -PolicyRecord $normalization `
        -Label 'Build receipt')
    if ($normalizationProblems.Count -gt 0) {
        throw ($normalizationProblems -join '; ')
    }

    $sourceFiles = @($canonicalSourceMap.Files | ForEach-Object {
        [pscustomobject][ordered]@{
            path = [string]$_.Path
            git_blob = ([string]$_.GitBlob).ToLowerInvariant()
            build_sha256 = ([string]$_.BuildSha256).ToLowerInvariant()
        }
    })
    $outputFiles = @($canonicalOutputSet.Files | ForEach-Object {
        [pscustomobject][ordered]@{
            filename = [string]$_.Name
            length = [long]$_.Length
            sha256 = ([string]$_.Sha256).ToLowerInvariant()
        }
    })
    return [pscustomobject][ordered]@{
        schema = 3
        mod = $Mod
        source_algorithm = 'git-blob-build-byte-map-sha256-v2'
        source_fingerprint_sha256 = ([string]$canonicalSourceMap.Fingerprint).ToLowerInvariant()
        source_files = $sourceFiles
        output_algorithm = [string]$canonicalOutputSet.Algorithm
        output_fingerprint_sha256 = ([string]$canonicalOutputSet.Fingerprint).ToLowerInvariant()
        output_files = @($outputFiles)
        root_bundle = [string]$canonicalOutputSet.Root.Name
        root_bundle_sha256 = ([string]$canonicalOutputSet.Root.Sha256).ToLowerInvariant()
        descriptor = [pscustomobject][ordered]@{
            filename = [string]$canonicalOutputSet.Descriptor.Name
            source_path = [string]$descriptorSource.Path
            sha256 = ([string]$canonicalOutputSet.Descriptor.Sha256).ToLowerInvariant()
        }
        builder = [pscustomobject][ordered]@{
            name = $script:VtBuildReceiptBuilderName
            version = $BuilderVersion
        }
        normalization_policy = $normalization
    }
}

function ConvertTo-VtBuildReceiptJson {
    param([Parameter(Mandatory = $true)]$Receipt)
    # Pretty-print indentation differs between Windows PowerShell 5.1 and
    # PowerShell 7. Compressed ordered JSON is byte-identical on both hosts.
    $json = $Receipt | ConvertTo-Json -Depth 12 -Compress
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

function Get-VtBuildReceiptDeclaredOutputSet {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedMod
    )

    $records = @($Receipt.output_files | ForEach-Object {
        [pscustomobject]@{
            Name = [string]$_.filename
            Length = $_.length
            Sha256 = [string]$_.sha256
        }
    })
    return New-VtBundleOutputSet -Records $records `
        -ExpectedDescriptorName "$ExpectedMod.mod" `
        -ExpectedRootBundle ([string]$Receipt.root_bundle) `
        -ExpectedDescriptorSha256 ([string]$Receipt.descriptor.sha256)
}

function Get-VtBuildReceiptPropertyProblems {
    param(
        $Value,
        [Parameter(Mandatory = $true)][string[]]$Allowed,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$RequireAll
    )

    if ($null -eq $Value) { return @("$Label is missing") }
    $present = @($Value.PSObject.Properties | ForEach-Object { [string]$_.Name })
    $problems = @()
    foreach ($name in $present) {
        if ($Allowed -cnotcontains $name) { $problems += "$Label has unknown property '$name'" }
    }
    if ($RequireAll) {
        foreach ($name in $Allowed) {
            if ($present -cnotcontains $name) { $problems += "$Label lacks required property '$name'" }
        }
    }
    return @($problems)
}

function Compare-VtBuildNormalizationPolicyRecords {
    param(
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Actual
    )

    $problems = @()
    if ([string]$Expected.algorithm -cne [string]$Actual.algorithm) {
        $problems += "normalization policy algorithm differs from receipt: $($Actual.algorithm)"
    }
    if ([string]$Expected.fingerprint_sha256 -cne [string]$Actual.fingerprint_sha256) {
        $problems += 'normalization policy fingerprint differs from receipt'
    }
    $expectedRows = @($Expected.excluded_outputs)
    $actualRows = @($Actual.excluded_outputs)
    if ($expectedRows.Count -ne $actualRows.Count) {
        $problems += "normalization policy excluded-output count differs from receipt: expected $($expectedRows.Count), got $($actualRows.Count)"
    }
    $count = [Math]::Min($expectedRows.Count, $actualRows.Count)
    for ($index = 0; $index -lt $count; $index++) {
        if ([string]$expectedRows[$index].filename -cne [string]$actualRows[$index].filename -or
                [string]$expectedRows[$index].sha256 -cne [string]$actualRows[$index].sha256) {
            $problems += "normalization policy excluded output differs from receipt at index $index"
        }
    }
    return [pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = @($problems) }
}

function Test-VtBuildReceiptJsonInteger {
    param($Value, [switch]$NonNegative)

    if ($null -eq $Value) { return $false }
    $integerTypes = @(
        'System.Byte', 'System.SByte', 'System.Int16', 'System.UInt16',
        'System.Int32', 'System.UInt32', 'System.Int64')
    if ($integerTypes -cnotcontains $Value.GetType().FullName) { return $false }
    try { $converted = [System.Convert]::ToInt64($Value) }
    catch { return $false }
    if ($NonNegative -and $converted -lt 0) { return $false }
    return $true
}

function Test-VtBuildReceiptProof {
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedMod,
        [Parameter(Mandatory = $true)]$SourceMap,
        $RootProof,
        $OutputSet,
        $NormalizationPolicy,
        [string]$ExpectedBuilderVersion,
        [ValidateSet(2, 3)][int]$MinimumSchema = 2
    )

    $problems = @()
    $schema = $null
    if (Test-VtBuildReceiptJsonInteger -Value $Receipt.schema -NonNegative) {
        try { $schema = [System.Convert]::ToInt32($Receipt.schema) } catch { }
    }
    else {
        $problems += 'receipt schema must be a JSON integer'
    }
    if ($schema -eq 1) {
        $problems += 'legacy receipt schema 1 lacks exact raw build-byte proof; rerun BuildOnly'
    }
    elseif ($schema -notin @(2, 3)) { $problems += "unsupported receipt schema '$($Receipt.schema)'" }
    if ($null -ne $schema -and $schema -lt $MinimumSchema) {
        $problems += "receipt schema $schema is below required minimum schema $MinimumSchema; rerun BuildOnly"
    }
    if ([string]$Receipt.mod -cne $ExpectedMod) { $problems += "receipt mod '$($Receipt.mod)' is not '$ExpectedMod'" }
    if ([string]$Receipt.source_algorithm -cne 'git-blob-build-byte-map-sha256-v2') {
        $problems += "unsupported source algorithm '$($Receipt.source_algorithm)'"
    }
    if ([string]$Receipt.source_fingerprint_sha256 -cnotmatch '^[0-9a-f]{64}$') {
        $problems += 'receipt source fingerprint is not lowercase SHA-256'
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

    if ($schema -eq 2) {
        if ($null -eq $RootProof) {
            $problems += 'schema 2 validation requires a canonical root proof'
        }
        else {
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
        }
    }
    elseif ($schema -eq 3) {
        $problems += @(Get-VtBuildReceiptPropertyProblems -Value $Receipt -Label 'schema 3 receipt' `
            -RequireAll -Allowed @(
                'schema', 'mod', 'source_algorithm', 'source_fingerprint_sha256', 'source_files',
                'output_algorithm', 'output_fingerprint_sha256', 'output_files', 'root_bundle',
                'root_bundle_sha256', 'descriptor', 'builder', 'normalization_policy'))
        foreach ($sourceFile in @($Receipt.source_files)) {
            $problems += @(Get-VtBuildReceiptPropertyProblems -Value $sourceFile `
                -Label 'schema 3 source file' -RequireAll `
                -Allowed @('path', 'git_blob', 'build_sha256'))
            if ([string]$sourceFile.git_blob -cnotmatch '^[0-9a-f]{40,64}$') {
                $problems += "schema 3 source file Git blob is invalid: $($sourceFile.path)"
            }
            if ([string]$sourceFile.build_sha256 -cnotmatch '^[0-9a-f]{64}$') {
                $problems += "schema 3 source file build SHA-256 is invalid: $($sourceFile.path)"
            }
        }
        if ([string]$Receipt.output_algorithm -cnotmatch '^[a-z0-9][a-z0-9._-]*$') {
            $problems += "receipt output algorithm is invalid: '$($Receipt.output_algorithm)'"
        }
        if ([string]$Receipt.output_fingerprint_sha256 -cnotmatch '^[0-9a-f]{64}$') {
            $problems += 'receipt output fingerprint is not lowercase SHA-256'
        }
        if ([string]$Receipt.root_bundle_sha256 -cnotmatch '^[0-9a-f]{64}$') {
            $problems += 'receipt root SHA-256 is invalid'
        }

        try {
            if ($null -ne $receiptMap) {
                $receiptSourcePaths = @($Receipt.source_files | ForEach-Object { [string]$_.path })
                $canonicalSourcePaths = @($receiptMap.Files | ForEach-Object { [string]$_.Path })
                if (($receiptSourcePaths -join [char]0) -cne ($canonicalSourcePaths -join [char]0)) {
                    $problems += 'receipt source_files are not in canonical ordinal order'
                }
            }
            $problems += @(Get-VtBuildReceiptPropertyProblems -Value $Receipt.descriptor `
                -Label 'schema 3 descriptor' -RequireAll -Allowed @('filename', 'source_path', 'sha256'))
            $problems += @(Get-VtBuildReceiptPropertyProblems -Value $Receipt.builder `
                -Label 'schema 3 builder' -RequireAll -Allowed @('name', 'version'))
            $problems += @(Get-VtBuildReceiptPropertyProblems -Value $Receipt.normalization_policy `
                -Label 'schema 3 normalization policy' -RequireAll `
                -Allowed @('algorithm', 'fingerprint_sha256', 'excluded_outputs'))
            foreach ($excluded in @($Receipt.normalization_policy.excluded_outputs)) {
                $problems += @(Get-VtBuildReceiptPropertyProblems -Value $excluded `
                    -Label 'schema 3 excluded output' -RequireAll -Allowed @('filename', 'sha256'))
            }
            if ([string]$Receipt.descriptor.filename -cne "$ExpectedMod.mod") {
                $problems += "receipt descriptor '$($Receipt.descriptor.filename)' is not '$ExpectedMod.mod'"
            }
            if ([string]$Receipt.descriptor.source_path -cne "$ExpectedMod.mod") {
                $problems += "receipt descriptor source '$($Receipt.descriptor.source_path)' is not '$ExpectedMod.mod'"
            }
            if ([string]$Receipt.descriptor.sha256 -cnotmatch '^[0-9a-f]{64}$') {
                $problems += 'receipt descriptor SHA-256 is invalid'
            }
            $descriptorSource = Get-VtBuildDescriptorSourceProof -SourceMap $SourceMap -Mod $ExpectedMod
            if ([string]$Receipt.descriptor.sha256 -cne $descriptorSource.Sha256) {
                $problems += "receipt descriptor differs from source descriptor: $($descriptorSource.Path)"
            }

            $receiptOutputRecords = @()
            foreach ($entry in @($Receipt.output_files)) {
                $problems += @(Get-VtBuildReceiptPropertyProblems -Value $entry `
                    -Label 'schema 3 output file' -RequireAll -Allowed @('filename', 'length', 'sha256'))
                if (-not (Test-VtBuildReceiptJsonInteger -Value $entry.length -NonNegative)) {
                    throw "Build receipt output length must be a non-negative JSON integer for '$($entry.filename)'."
                }
                $length = [System.Convert]::ToInt64($entry.length)
                if ([string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$') {
                    throw "Build receipt output SHA-256 is invalid for '$($entry.filename)'."
                }
                $receiptOutputRecords += [pscustomobject]@{
                    Name = [string]$entry.filename
                    Length = $length
                    Sha256 = [string]$entry.sha256
                }
            }
            if ($null -eq $Receipt.output_files -or $receiptOutputRecords.Count -eq 0) {
                throw 'Build receipt output_files map is missing or empty.'
            }
            $receiptOutput = New-VtBundleOutputSet -Records $receiptOutputRecords `
                -ExpectedDescriptorName ([string]$Receipt.descriptor.filename) `
                -ExpectedRootBundle ([string]$Receipt.root_bundle) `
                -ExpectedDescriptorSha256 ([string]$Receipt.descriptor.sha256)
            if ([string]$Receipt.output_algorithm -cne [string]$receiptOutput.Algorithm) {
                $problems += 'receipt output algorithm does not match its output_files map'
            }
            if ([string]$Receipt.output_fingerprint_sha256 -cne [string]$receiptOutput.Fingerprint) {
                $problems += 'receipt output fingerprint does not match its output_files map'
            }
            if ([string]$Receipt.root_bundle_sha256 -cne [string]$receiptOutput.Root.Sha256) {
                $problems += "receipt root SHA-256 does not match its output_files map: $($Receipt.root_bundle)"
            }
            $receiptOutputNames = @($Receipt.output_files | ForEach-Object { [string]$_.filename })
            $canonicalOutputNames = @($receiptOutput.Files | ForEach-Object { [string]$_.Name })
            if (($receiptOutputNames -join [char]0) -cne ($canonicalOutputNames -join [char]0)) {
                $problems += 'receipt output_files are not in canonical ordinal order'
            }
            if ($null -eq $OutputSet) {
                $problems += 'schema 3 validation requires a complete output set'
            }
            else {
                if ([string]$OutputSet.Algorithm -cne [string]$receiptOutput.Algorithm) {
                    $problems += 'current output algorithm differs from receipt'
                }
                if ([string]$OutputSet.Fingerprint -cne [string]$receiptOutput.Fingerprint) {
                    $problems += 'current output fingerprint differs from receipt'
                }
                if ([string]$OutputSet.Root.Name -cne [string]$receiptOutput.Root.Name -or
                        [string]$OutputSet.Root.Sha256 -cne [string]$receiptOutput.Root.Sha256) {
                    $problems += 'current root bundle identity differs from receipt'
                }
                if ([string]$OutputSet.Descriptor.Name -cne [string]$receiptOutput.Descriptor.Name -or
                        [string]$OutputSet.Descriptor.Sha256 -cne [string]$receiptOutput.Descriptor.Sha256) {
                    $problems += 'current descriptor identity differs from receipt'
                }
                $comparisonProblems = @(Compare-VtBundleOutputSets -Expected $receiptOutput -Actual $OutputSet `
                    -ExpectedLabel 'receipt output' -ActualLabel 'current output' -RequireLength $true
                )
                if ($comparisonProblems.Count -gt 0) { $problems += @($comparisonProblems) }
            }

            if ([string]$Receipt.builder.name -cne $script:VtBuildReceiptBuilderName) {
                $problems += "receipt builder '$($Receipt.builder.name)' is not '$script:VtBuildReceiptBuilderName'"
            }
            $builderVersion = [string]$Receipt.builder.version
            if ([string]::IsNullOrWhiteSpace($builderVersion) -or $builderVersion -cne $builderVersion.Trim()) {
                $problems += 'receipt builder version is empty or non-canonical'
            }
            elseif (-not [string]::IsNullOrWhiteSpace($ExpectedBuilderVersion) -and
                    $builderVersion -cne $ExpectedBuilderVersion) {
                $problems += "receipt builder version '$builderVersion' is not expected version '$ExpectedBuilderVersion'"
            }

            $receiptPolicy = ConvertTo-VtBuildNormalizationPolicyRecord `
                -Policy $Receipt.normalization_policy -Serialized
            $problems += @(Get-VtBuildNormalizationOutputProblems `
                -OutputSet $receiptOutput `
                -PolicyRecord $receiptPolicy `
                -Label 'Receipt')
            $receiptPolicyNames = @($Receipt.normalization_policy.excluded_outputs | ForEach-Object {
                [string]$_.filename
            })
            $normalizedPolicyNames = @($receiptPolicy.excluded_outputs | ForEach-Object {
                [string]$_.filename
            })
            if (($receiptPolicyNames -join [char]0) -cne ($normalizedPolicyNames -join [char]0)) {
                $problems += 'receipt normalization policy exclusions are not in canonical ordinal order'
            }
            if ($null -eq $NormalizationPolicy) {
                $problems += 'schema 3 validation requires the current normalization policy proof'
            }
            else {
                $currentPolicy = ConvertTo-VtBuildNormalizationPolicyRecord -Policy $NormalizationPolicy
                if ($null -ne $OutputSet) {
                    $problems += @(Get-VtBuildNormalizationOutputProblems `
                        -OutputSet $OutputSet `
                        -PolicyRecord $currentPolicy `
                        -Label 'Current')
                }
                $policyComparison = Compare-VtBuildNormalizationPolicyRecords `
                    -Expected $receiptPolicy -Actual $currentPolicy
                if (-not $policyComparison.Ok) { $problems += @($policyComparison.Problems) }
            }
        }
        catch {
            $problems += $_.Exception.Message
        }
    }
    return [pscustomobject]@{ Ok = ($problems.Count -eq 0); Problems = @($problems) }
}
