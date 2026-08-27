Set-StrictMode -Version 2.0

$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false, $true)
$script:DefaultMaxEntries = 4096
$script:DefaultMaxPathBytes = 4096
$script:DefaultMaxTotalPathBytes = 1048576
$script:DefaultMaxPathFileBytes = 1048576
$script:GitLocalEnvironmentNames = @(
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_COMMON_DIR',
    'GIT_CONFIG',
    'GIT_CONFIG_COUNT',
    'GIT_CONFIG_PARAMETERS',
    'GIT_DIR',
    'GIT_GRAFT_FILE',
    'GIT_IMPLICIT_WORK_TREE',
    'GIT_INDEX_FILE',
    'GIT_NAMESPACE',
    'GIT_NO_REPLACE_OBJECTS',
    'GIT_OBJECT_DIRECTORY',
    'GIT_PREFIX',
    'GIT_QUARANTINE_PATH',
    'GIT_REPLACE_REF_BASE',
    'GIT_SHALLOW_FILE',
    'GIT_WORK_TREE'
)

function Get-VtLowerSha256FromBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
    } finally {
        $sha.Dispose()
    }
    return ([System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant())
}

function Invoke-VtReadOnlyGit {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $savedEnvironment = @{}
    foreach ($name in $script:GitLocalEnvironmentNames) {
        $environmentPath = "Env:$name"
        $savedEnvironment[$name] = [pscustomobject]@{
            Exists = Test-Path -LiteralPath $environmentPath
            Value = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        if ($savedEnvironment[$name].Exists) {
            Remove-Item -LiteralPath $environmentPath
        }
    }
    $optionalLocksPath = 'Env:GIT_OPTIONAL_LOCKS'
    $previousOptionalLocks = [pscustomobject]@{
        Exists = Test-Path -LiteralPath $optionalLocksPath
        Value = [Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS', 'Process')
    }
    New-Item -Path $optionalLocksPath -Value '0' -Force | Out-Null
    try {
        $output = @(& git -C $RepositoryRoot @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $optionalLocksPath -ErrorAction SilentlyContinue
        if ($previousOptionalLocks.Exists) {
            New-Item -Path $optionalLocksPath -Value $previousOptionalLocks.Value -Force | Out-Null
        }
        foreach ($name in $script:GitLocalEnvironmentNames) {
            $environmentPath = "Env:$name"
            Remove-Item -LiteralPath $environmentPath -ErrorAction SilentlyContinue
            if ($savedEnvironment[$name].Exists) {
                New-Item -Path $environmentPath -Value $savedEnvironment[$name].Value -Force | Out-Null
            }
        }
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $detail = (@($output) -join [Environment]::NewLine).Trim()
        throw "git $($Arguments -join ' ') failed with exit ${exitCode}: $detail"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Lines = @($output | ForEach-Object { [string]$_ })
        Text = (@($output) -join "`n").Trim()
    }
}

function Resolve-VtRepositoryRoot {
    param([Parameter(Mandatory)][string]$RepositoryRoot)

    $fullRoot = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if (-not [System.IO.Directory]::Exists($fullRoot)) {
        throw "repository root does not exist: $fullRoot"
    }
    $rootAttributes = [System.IO.File]::GetAttributes($fullRoot)
    if (($rootAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "repository root must not be a reparse point: $fullRoot"
    }

    $gitRootResult = Invoke-VtReadOnlyGit -RepositoryRoot $fullRoot -Arguments @(
        'rev-parse', '--show-toplevel')
    $gitRoot = [System.IO.Path]::GetFullPath($gitRootResult.Text).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    if (-not [string]::Equals($fullRoot, $gitRoot, $comparison)) {
        throw "RepositoryRoot must be the exact git root; resolved $gitRoot"
    }
    return $fullRoot
}

function Resolve-VtBaseCommit {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BaseCommit
    )

    if ($BaseCommit -notmatch '^[0-9a-fA-F]{40}([0-9a-fA-F]{24})?$') {
        throw 'BaseCommit must be an explicit 40- or 64-character hexadecimal commit ID.'
    }
    $resolved = Invoke-VtReadOnlyGit -RepositoryRoot $RepositoryRoot -Arguments @(
        'rev-parse', '--verify', "$BaseCommit^{commit}")
    $commit = $resolved.Text.ToLowerInvariant()
    if ($commit -notmatch '^[0-9a-f]{40}([0-9a-f]{24})?$') {
        throw "git returned an invalid commit ID: $commit"
    }
    if (-not [string]::Equals($BaseCommit.ToLowerInvariant(), $commit,
            [System.StringComparison]::Ordinal)) {
        throw 'BaseCommit must be the complete object-format commit ID, not a prefix.'
    }
    return $commit
}

function ConvertTo-VtProcessArgument {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($slashes * 2) + 1)))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) {
            [void]$builder.Append(('\' * $slashes))
            $slashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-VtReadOnlyGitBytes {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][ValidateRange(1, 33554432)][int]$MaxOutputBytes
    )

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = 'git'
    $start.Arguments = (@('-C', $RepositoryRoot) + $Arguments |
        ForEach-Object { ConvertTo-VtProcessArgument -Value ([string]$_) }) -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($name in $script:GitLocalEnvironmentNames) {
        [void]$start.EnvironmentVariables.Remove($name)
    }
    $start.EnvironmentVariables['GIT_OPTIONAL_LOCKS'] = '0'

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $memory = New-Object System.IO.MemoryStream
    $started = $false
    try {
        if (-not $process.Start()) { throw 'failed to start git' }
        $started = $true
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $buffer = New-Object byte[] 8192
        while (($read = $process.StandardOutput.BaseStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($memory.Length + $read -gt $MaxOutputBytes) {
                try { $process.Kill() } catch {}
                throw "git path output exceeds the $MaxOutputBytes-byte input bound"
            }
            $memory.Write($buffer, 0, $read)
        }
        $process.WaitForExit()
        $stderr = $stderrTask.Result
        if ($process.ExitCode -ne 0) {
            throw "git $($Arguments -join ' ') failed with exit $($process.ExitCode): $($stderr.Trim())"
        }
        # Unary comma prevents PowerShell from unrolling byte[] into pipeline
        # scalars (and preserves an actual zero-length byte array).
        return ,$memory.ToArray()
    } finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill() } catch {}
            try { $process.WaitForExit() } catch {}
        }
        $memory.Dispose()
        $process.Dispose()
    }
}

function ConvertFrom-VtNulPathBytes {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory)][int]$MaxEntries,
        [Parameter(Mandatory)][int]$MaxPathBytes,
        [Parameter(Mandatory)][long]$MaxTotalPathBytes
    )

    $paths = New-Object 'System.Collections.Generic.List[string]'
    if ($Bytes.Length -eq 0) { return $paths.ToArray() }
    $start = 0
    [long]$total = 0
    for ($index = 0; $index -lt $Bytes.Length; $index++) {
        if ($Bytes[$index] -ne 0) { continue }
        $length = $index - $start
        if ($length -lt 1) { throw 'git returned an empty path record' }
        if ($paths.Count -ge $MaxEntries) { throw "git returned more than $MaxEntries paths" }
        if ($length -gt $MaxPathBytes) { throw "git returned a path longer than $MaxPathBytes UTF-8 bytes" }
        if ($total -gt ($MaxTotalPathBytes - $length)) {
            throw "git path set exceeds the $MaxTotalPathBytes-byte aggregate bound"
        }
        $segment = New-Object byte[] $length
        [System.Array]::Copy($Bytes, $start, $segment, 0, $length)
        $paths.Add($script:Utf8NoBom.GetString($segment))
        $total += $length
        $start = $index + 1
    }
    if ($start -ne $Bytes.Length) { throw 'git path output lacks its final NUL delimiter' }
    return $paths.ToArray()
}

function Get-VtChangedContentManifestPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BaseCommit,
        [ValidateRange(1, 65536)][int]$MaxEntries = $script:DefaultMaxEntries,
        [ValidateRange(1, 1048576)][int]$MaxPathBytes = $script:DefaultMaxPathBytes,
        [ValidateRange(1, 16777216)][long]$MaxTotalPathBytes = $script:DefaultMaxTotalPathBytes
    )

    $root = Resolve-VtRepositoryRoot -RepositoryRoot $RepositoryRoot
    $commit = Resolve-VtBaseCommit -RepositoryRoot $root -BaseCommit $BaseCommit
    $outputBound = [int][Math]::Min(33554432, $MaxTotalPathBytes + $MaxEntries)
    $changedBytes = Invoke-VtReadOnlyGitBytes -RepositoryRoot $root -Arguments @(
        '-c', 'core.quotepath=false', 'diff', '--no-ext-diff', '--no-renames',
        '--name-only', '-z', $commit, '--') -MaxOutputBytes $outputBound
    $changed = @(ConvertFrom-VtNulPathBytes -Bytes $changedBytes `
        -MaxEntries $MaxEntries -MaxPathBytes $MaxPathBytes `
        -MaxTotalPathBytes $MaxTotalPathBytes)

    [long]$usedBytes = 0
    foreach ($path in $changed) { $usedBytes += $script:Utf8NoBom.GetByteCount($path) }
    $remainingEntries = $MaxEntries - $changed.Count
    $remainingBytes = $MaxTotalPathBytes - $usedBytes
    $untrackedBound = if ($remainingEntries -lt 1 -or $remainingBytes -lt 1) {
        1
    } else {
        [int][Math]::Min(33554432, $remainingBytes + $remainingEntries)
    }
    $untrackedBytes = Invoke-VtReadOnlyGitBytes -RepositoryRoot $root -Arguments @(
        '-c', 'core.quotepath=false', 'ls-files', '--others',
        '--exclude-standard', '-z', '--') -MaxOutputBytes $untrackedBound
    if ($untrackedBytes.Length -gt 0 -and
        ($remainingEntries -lt 1 -or $remainingBytes -lt 1)) {
        throw 'untracked paths exceed the remaining aggregate collector bound'
    }
    $untracked = @(ConvertFrom-VtNulPathBytes -Bytes $untrackedBytes `
        -MaxEntries ([Math]::Max(1, $remainingEntries)) `
        -MaxPathBytes $MaxPathBytes `
        -MaxTotalPathBytes ([Math]::Max(1, $remainingBytes)))
    return @($changed + $untracked)
}

function ConvertTo-VtEncodedPath {
    param([Parameter(Mandatory)][string]$Path)

    $bytes = $script:Utf8NoBom.GetBytes($Path)
    $builder = New-Object System.Text.StringBuilder
    foreach ($value in $bytes) {
        $safe = (
            ($value -ge 0x30 -and $value -le 0x39) -or
            ($value -ge 0x41 -and $value -le 0x5a) -or
            ($value -ge 0x61 -and $value -le 0x7a) -or
            $value -eq 0x2d -or $value -eq 0x2e -or
            $value -eq 0x2f -or $value -eq 0x5f)
        if ($safe) {
            [void]$builder.Append([char]$value)
        } else {
            [void]$builder.Append('%')
            [void]$builder.Append($value.ToString('X2', [System.Globalization.CultureInfo]::InvariantCulture))
        }
    }
    return [pscustomobject]@{
        ByteLength = $bytes.Length
        Encoded = $builder.ToString()
    }
}

function Test-VtPathHasReparseComponent {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$FullPath
    )

    $relative = $FullPath.Substring($RepositoryRoot.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    if ([string]::IsNullOrEmpty($relative)) { return $false }

    $current = $RepositoryRoot
    foreach ($component in $relative.Split(@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar),
        [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $current = Join-Path $current $component
        if ([System.IO.File]::Exists($current) -or [System.IO.Directory]::Exists($current)) {
            $attributes = [System.IO.File]::GetAttributes($current)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                return $true
            }
        }
    }
    return $false
}

function Read-VtContentManifestPathFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PathFile,
        [ValidateRange(1, 65536)][int]$MaxEntries = $script:DefaultMaxEntries,
        [ValidateRange(1, 1048576)][int]$MaxPathBytes = $script:DefaultMaxPathBytes,
        [ValidateRange(1, 16777216)][long]$MaxPathFileBytes = $script:DefaultMaxPathFileBytes
    )

    $fullPath = [System.IO.Path]::GetFullPath($PathFile)
    if (-not [System.IO.File]::Exists($fullPath)) {
        throw "path-list file does not exist: $fullPath"
    }
    $paths = New-Object 'System.Collections.Generic.List[string]'
    $stream = New-Object System.IO.FileStream(
        $fullPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    $reader = $null
    try {
        if ($stream.Length -gt $MaxPathFileBytes) {
            throw "path-list file exceeds the $MaxPathFileBytes-byte input bound"
        }
        # Read at most the declared bound plus one sentinel byte. This keeps a
        # concurrently grown or underreported input from allocating an
        # unbounded line before it is refused.
        $buffer = New-Object byte[] ([int]$MaxPathFileBytes + 1)
        $total = 0
        while ($total -lt $buffer.Length) {
            $read = $stream.Read($buffer, $total, $buffer.Length - $total)
            if ($read -eq 0) { break }
            $total += $read
        }
        if ($total -gt $MaxPathFileBytes) {
            throw "path-list file exceeds the $MaxPathFileBytes-byte input bound"
        }
        $offset = 0
        if ($total -ge 3 -and $buffer[0] -eq 0xef -and $buffer[1] -eq 0xbb -and $buffer[2] -eq 0xbf) {
            $offset = 3
        }
        $text = $script:Utf8NoBom.GetString($buffer, $offset, $total - $offset)
        $reader = New-Object System.IO.StringReader($text)
        while (($line = $reader.ReadLine()) -ne $null) {
            if ($paths.Count -ge $MaxEntries) {
                throw "path-list contains more than $MaxEntries entries"
            }
            if ([string]::IsNullOrEmpty($line)) {
                throw 'path-list contains an empty path'
            }
            if ($script:Utf8NoBom.GetByteCount($line) -gt $MaxPathBytes) {
                throw "path-list contains a path longer than $MaxPathBytes UTF-8 bytes"
            }
            $paths.Add($line)
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $stream.Dispose()
    }
    return $paths.ToArray()
}

function Get-VtFileDigestRecord {
    param([Parameter(Mandatory)][string]$FullPath)

    $stream = New-Object System.IO.FileStream(
        $FullPath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $length = $stream.Length
        $hash = $sha.ComputeHash($stream)
        if ($stream.Position -ne $length) {
            throw "short read while hashing $FullPath"
        }
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
    return [pscustomobject]@{
        Length = [long]$length
        Sha256 = [System.BitConverter]::ToString($hash).Replace('-', '').ToLowerInvariant()
    }
}

function Get-VtReviewerCompatibilityText {
    param([Parameter(Mandatory)][object[]]$Entries)

    $builder = New-Object System.Text.StringBuilder
    foreach ($entry in $Entries) {
        if ($entry.Path.IndexOf('|') -ge 0 -or
            $entry.Path.IndexOf("`r") -ge 0 -or
            $entry.Path.IndexOf("`n") -ge 0) {
            return $null
        }
        if ($entry.Kind -eq 'present') {
            [void]$builder.Append($entry.Path)
            [void]$builder.Append('|')
            [void]$builder.Append(([long]$entry.Length).ToString(
                [System.Globalization.CultureInfo]::InvariantCulture))
            [void]$builder.Append('|')
            [void]$builder.Append($entry.Sha256)
            [void]$builder.Append("`n")
        } else {
            [void]$builder.Append($entry.Path)
            [void]$builder.Append("|deleted`n")
        }
    }
    return $builder.ToString()
}

function New-VtContentManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$BaseCommit,
        [Parameter(Mandatory)][string[]]$Paths,
        [ValidateRange(1, 65536)][int]$MaxEntries = $script:DefaultMaxEntries,
        [ValidateRange(1, 1048576)][int]$MaxPathBytes = $script:DefaultMaxPathBytes,
        [ValidateRange(1, 16777216)][long]$MaxTotalPathBytes = $script:DefaultMaxTotalPathBytes
    )

    # Bounds and the complete lexical path set are validated before any file is
    # opened or hashed. This ordering is part of issue #1435's safety contract.
    if ($null -eq $Paths -or $Paths.Count -lt 1) {
        throw 'at least one repository-relative path is required'
    }
    if ($Paths.Count -gt $MaxEntries) {
        throw "path set contains $($Paths.Count) entries; maximum is $MaxEntries"
    }

    # Reject oversized direct input before Replace/Split/percent-encoding can
    # allocate from it. The caller's strings already exist, but every further
    # allocation remains behind explicit per-path and aggregate byte bounds.
    [long]$totalPathBytes = 0
    foreach ($inputPath in $Paths) {
        if ($null -eq $inputPath -or $inputPath.Length -eq 0) {
            throw 'path set contains an empty path'
        }
        if ($inputPath.Length -gt $MaxPathBytes) {
            throw "path exceeds $MaxPathBytes UTF-8 bytes"
        }
        if ([string]::IsNullOrWhiteSpace($inputPath)) {
            throw 'path set contains an empty path'
        }
        $byteCount = $script:Utf8NoBom.GetByteCount($inputPath)
        if ($byteCount -gt $MaxPathBytes) {
            throw "path exceeds $MaxPathBytes UTF-8 bytes"
        }
        if ($totalPathBytes -gt ($MaxTotalPathBytes - $byteCount)) {
            throw "path set exceeds the $MaxTotalPathBytes-byte aggregate bound"
        }
        $totalPathBytes += $byteCount
    }

    $root = Resolve-VtRepositoryRoot -RepositoryRoot $RepositoryRoot
    $commit = Resolve-VtBaseCommit -RepositoryRoot $root -BaseCommit $BaseCommit
    $comparison = if ($env:OS -eq 'Windows_NT') {
        [System.StringComparison]::OrdinalIgnoreCase
    } else {
        [System.StringComparison]::Ordinal
    }
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $exactPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $foldedPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $plan = New-Object 'System.Collections.Generic.List[object]'

    foreach ($inputPath in $Paths) {
        if ([System.IO.Path]::IsPathRooted($inputPath) -or $inputPath -match '^[A-Za-z]:') {
            throw "path must be repository-relative: $inputPath"
        }
        $normalized = $inputPath.Replace('\', '/')
        if ($normalized.IndexOf(':') -ge 0) {
            throw "path contains a colon and could name an NTFS alternate data stream: $inputPath"
        }
        $components = $normalized.Split('/')
        if ($components.Count -lt 1 -or @($components | Where-Object {
                $_ -eq '' -or $_ -eq '.' -or $_ -eq '..'
            }).Count -gt 0) {
            throw "path contains an empty, dot, or parent component: $inputPath"
        }
        $encoded = ConvertTo-VtEncodedPath -Path $normalized
        if ($encoded.ByteLength -gt $MaxPathBytes) {
            throw "path exceeds $MaxPathBytes UTF-8 bytes: $inputPath"
        }
        if (-not $exactPaths.Add($normalized)) {
            throw "duplicate path: $normalized"
        }
        if (-not $foldedPaths.Add($normalized)) {
            throw "case-colliding path: $normalized"
        }

        $platformRelative = $normalized.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $root $platformRelative))
        if (-not $fullPath.StartsWith($rootPrefix, $comparison)) {
            throw "path resolves outside the repository: $inputPath"
        }
        if (Test-VtPathHasReparseComponent -RepositoryRoot $root -FullPath $fullPath) {
            throw "path traverses a reparse point: $normalized"
        }
        $plan.Add([pscustomobject]@{
            Path = $normalized
            FullPath = $fullPath
            PathByteLength = $encoded.ByteLength
            EncodedPath = $encoded.Encoded
        })
    }

    # Resolve present/deleted state for every validated path before hashing any
    # present file. Unknown missing paths fail closed rather than masquerading
    # as deletions.
    foreach ($candidate in $plan) {
        if ([System.IO.Directory]::Exists($candidate.FullPath)) {
            throw "path names a directory, not a file: $($candidate.Path)"
        }
        if ([System.IO.File]::Exists($candidate.FullPath)) {
            Add-Member -InputObject $candidate -NotePropertyName Kind -NotePropertyValue 'present'
            continue
        }
        $object = Invoke-VtReadOnlyGit -RepositoryRoot $root -Arguments @(
            'cat-file', '-t', "$commit`:$($candidate.Path)") -AllowFailure
        if ($object.ExitCode -ne 0 -or $object.Text -ne 'blob') {
            throw "missing path is not a base-commit blob and cannot be recorded as a deletion: $($candidate.Path)"
        }
        Add-Member -InputObject $candidate -NotePropertyName Kind -NotePropertyValue 'deleted'
    }

    $orderedPaths = [string[]]@($plan | ForEach-Object { $_.Path })
    [System.Array]::Sort($orderedPaths, [System.StringComparer]::Ordinal)
    $byPath = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::Ordinal)
    foreach ($candidate in $plan) { $byPath.Add($candidate.Path, $candidate) }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($path in $orderedPaths) {
        $candidate = $byPath[$path]
        if ($candidate.Kind -eq 'present') {
            $digest = Get-VtFileDigestRecord -FullPath $candidate.FullPath
            $entries.Add([pscustomobject]@{
                Kind = 'present'
                Path = $candidate.Path
                PathByteLength = [int]$candidate.PathByteLength
                EncodedPath = $candidate.EncodedPath
                Length = [long]$digest.Length
                Sha256 = $digest.Sha256
            })
        } else {
            $entries.Add([pscustomobject]@{
                Kind = 'deleted'
                Path = $candidate.Path
                PathByteLength = [int]$candidate.PathByteLength
                EncodedPath = $candidate.EncodedPath
                Length = $null
                Sha256 = $null
            })
        }
    }

    $manifest = New-Object System.Text.StringBuilder
    [void]$manifest.Append("VT2-CONTENT-MANIFEST|1`n")
    [void]$manifest.Append("BASE|$($commit.Length)|$commit`n")
    [void]$manifest.Append("COUNT|$($entries.Count)`n")
    foreach ($entry in $entries) {
        if ($entry.Kind -eq 'present') {
            [void]$manifest.Append("P|$($entry.PathByteLength)|$($entry.EncodedPath)|$($entry.Length)|$($entry.Sha256)`n")
        } else {
            [void]$manifest.Append("D|$($entry.PathByteLength)|$($entry.EncodedPath)`n")
        }
    }
    $manifestText = $manifest.ToString()
    $manifestBytes = $script:Utf8NoBom.GetBytes($manifestText)
    $manifestSha = Get-VtLowerSha256FromBytes -Bytes $manifestBytes

    $compatibilityText = Get-VtReviewerCompatibilityText -Entries $entries.ToArray()
    $compatibilitySha = $null
    if ($null -ne $compatibilityText) {
        $compatibilitySha = Get-VtLowerSha256FromBytes -Bytes (
            $script:Utf8NoBom.GetBytes($compatibilityText))
    }

    return [pscustomobject]@{
        Schema = 1
        RepositoryRoot = $root
        BaseCommit = $commit
        EntryCount = $entries.Count
        Entries = $entries.ToArray()
        ManifestText = $manifestText
        ManifestBytes = $manifestBytes
        AggregateSha256 = $manifestSha
        ReviewerCompatibilityText = $compatibilityText
        ReviewerCompatibilitySha256 = $compatibilitySha
    }
}

Export-ModuleMember -Function @(
    'New-VtContentManifest',
    'Read-VtContentManifestPathFile',
    'Get-VtChangedContentManifestPaths',
    'Get-VtReviewerCompatibilityText'
)
