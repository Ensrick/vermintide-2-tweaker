# check_content_manifest.ps1 - issue #1435 canonical immutable-review evidence.

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$SelfTest,
    [string]$VmbSnapshotRoot,
    [string]$UpdaterSnapshotRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $repoRoot 'tools\review\content-manifest.psm1'
Import-Module $modulePath -Force

$failures = New-Object 'System.Collections.Generic.List[string]'
$gitLocalEnvironmentNames = @(
    'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_COMMON_DIR', 'GIT_CONFIG',
    'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS', 'GIT_DIR', 'GIT_GRAFT_FILE',
    'GIT_IMPLICIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_NAMESPACE',
    'GIT_NO_REPLACE_OBJECTS', 'GIT_OBJECT_DIRECTORY', 'GIT_PREFIX',
    'GIT_QUARANTINE_PATH', 'GIT_REPLACE_REF_BASE', 'GIT_SHALLOW_FILE',
    'GIT_WORK_TREE')
function Assert-True([bool]$Condition, [string]$Description) {
    if (-not $Condition) { $failures.Add($Description) }
}
function Assert-Throws([scriptblock]$Action, [string]$Description) {
    $threw = $false
    try { & $Action } catch { $threw = $true }
    if (-not $threw) { $failures.Add($Description) }
}
function Assert-ThrowsLike([scriptblock]$Action, [string]$Pattern, [string]$Description) {
    try {
        & $Action
        $failures.Add($Description)
    } catch {
        if ($_.Exception.Message -notmatch $Pattern) {
            $failures.Add("$Description (unexpected error: $($_.Exception.Message))")
        }
    }
}
function Test-ByteArrayEqual([byte[]]$Left, [byte[]]$Right) {
    if ($Left.Length -ne $Right.Length) { return $false }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) { return $false }
    }
    return $true
}
function Get-LowerSha256([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}
function Invoke-TestGit([string]$Root, [string[]]$Arguments) {
    $saved = @{}
    foreach ($name in $gitLocalEnvironmentNames) {
        $environmentPath = "Env:$name"
        $saved[$name] = [pscustomobject]@{
            Exists = Test-Path -LiteralPath $environmentPath
            Value = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        if ($saved[$name].Exists) {
            Remove-Item -LiteralPath $environmentPath
        }
    }
    try {
        $output = @(& git -C $Root @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        foreach ($name in $gitLocalEnvironmentNames) {
            $environmentPath = "Env:$name"
            Remove-Item -LiteralPath $environmentPath -ErrorAction SilentlyContinue
            if ($saved[$name].Exists) {
                New-Item -Path $environmentPath -Value $saved[$name].Value -Force | Out-Null
            }
        }
    }
    if ($exitCode -ne 0) {
        throw "test git $($Arguments -join ' ') failed: $(@($output) -join '; ')"
    }
    return (@($output) -join "`n").Trim()
}
function Remove-TestTree([string]$Root) {
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    if (-not $fullRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($fullRoot) -notlike 'vt2-content-manifest-*') {
        throw "refusing to remove non-fixture path: $fullRoot"
    }
    if (-not [System.IO.Directory]::Exists($fullRoot)) { return }
    Get-ChildItem -LiteralPath $fullRoot -Recurse -File -Force |
        ForEach-Object {
            [System.IO.File]::SetAttributes($_.FullName, [System.IO.FileAttributes]::Normal)
            [System.IO.File]::Delete($_.FullName)
        }
    Get-ChildItem -LiteralPath $fullRoot -Recurse -Directory -Force |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            [System.IO.File]::SetAttributes($_.FullName, [System.IO.FileAttributes]::Directory)
            [System.IO.Directory]::Delete($_.FullName, $false)
        }
    [System.IO.Directory]::Delete($fullRoot, $false)
}

function Get-ExternalSnapshotPaths([string]$Root) {
    $head = Invoke-TestGit $Root @('rev-parse', 'HEAD')
    return @(Get-VtChangedContentManifestPaths -RepositoryRoot $Root -BaseCommit $head)
}

function Invoke-ContentManifestCli([string[]]$Arguments) {
    $hostPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $hostPath -NoLogo -NoProfile -File (
            Join-Path $repoRoot 'tools\review\content-manifest.ps1') @Arguments 2>$null | Out-Null
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Test-ExternalSnapshot(
    [string]$Root,
    [string]$ExpectedBase,
    [string]$ExpectedCompatibilitySha,
    [string]$Name
) {
    if (-not $Root) { return }
    if (-not [System.IO.Directory]::Exists($Root)) {
        $failures.Add("$Name snapshot root is missing: $Root")
        return
    }
    $head = Invoke-TestGit $Root @('rev-parse', 'HEAD')
    Assert-True ($head -eq $ExpectedBase) "$Name snapshot base drifted"
    $paths = @(Get-ExternalSnapshotPaths $Root)
    try {
        $result = New-VtContentManifest -RepositoryRoot $Root -BaseCommit $head -Paths $paths
        Assert-True (
            $result.ReviewerCompatibilitySha256 -eq $ExpectedCompatibilitySha
        ) "$Name frozen reviewer digest did not reproduce"
    } catch {
        $failures.Add("$Name frozen snapshot could not be read: $($_.Exception.Message)")
    }
}

function Test-ReviewerRecordFixture(
    [string]$FixturePath,
    [string]$ExpectedSha,
    [string]$Name
) {
    if (-not [System.IO.File]::Exists($FixturePath)) {
        $failures.Add("$Name reviewer record fixture is missing")
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($FixturePath)
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $text = $utf8.GetString($bytes) }
    catch {
        $failures.Add("$Name reviewer record fixture is not strict UTF-8")
        return
    }
    Assert-True ($text.IndexOf("`r") -lt 0) "$Name reviewer record fixture contains CR"
    Assert-True ($text.EndsWith("`n")) "$Name reviewer record fixture lacks final LF"
    Assert-True ((Get-LowerSha256 $bytes) -eq $ExpectedSha) "$Name reviewer record digest drifted"

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @($text.Split("`n") | Where-Object { $_ -ne '' })) {
        if ($line -notmatch '^([^|]+)\|([0-9]+)\|([0-9a-f]{64})$') {
            $failures.Add("$Name reviewer record has malformed row: $line")
            return
        }
        $paths.Add($Matches[1])
        $entries.Add([pscustomobject]@{
            Kind = 'present'
            Path = $Matches[1]
            Length = [long]$Matches[2]
            Sha256 = $Matches[3]
        })
    }
    $sorted = [string[]]$paths.ToArray().Clone()
    [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)
    Assert-True (($paths.ToArray() -join "`n") -ceq ($sorted -join "`n")) "$Name reviewer rows are not ordinal-sorted"
    $rebuilt = Get-VtReviewerCompatibilityText -Entries $entries.ToArray()
    Assert-True ($rebuilt -ceq $text) "$Name reviewer rows do not round-trip through the canonical serializer"
}

function Test-FrozenByteSetFixture(
    [string]$ZipPath,
    [string]$RecordPath,
    [string]$ExpectedZipSha,
    [string]$ExpectedCompatibilitySha,
    [string]$Name
) {
    if (-not [System.IO.File]::Exists($ZipPath) -or
        -not [System.IO.File]::Exists($RecordPath)) {
        $failures.Add("$Name frozen byte fixture is missing")
        return
    }
    Assert-True (
        (Get-LowerSha256 ([System.IO.File]::ReadAllBytes($ZipPath))) -eq $ExpectedZipSha
    ) "$Name frozen ZIP bytes drifted"

    $expectedPaths = New-Object 'System.Collections.Generic.HashSet[string]' (
        [System.StringComparer]::Ordinal)
    foreach ($line in [System.IO.File]::ReadAllLines($RecordPath)) {
        $parts = $line.Split('|')
        if ($parts.Count -ne 3 -or -not $expectedPaths.Add($parts[0])) {
            $failures.Add("$Name frozen record paths are malformed or duplicated")
            return
        }
    }

    $fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
        'vt2-content-manifest-frozen-' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $archive = $null
    try {
        try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop }
        catch {
            if ($null -eq ('System.IO.Compression.ZipFile' -as [type])) { throw }
        }
        $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' (
            [System.StringComparer]::Ordinal)
        $rootPrefix = [System.IO.Path]::GetFullPath($fixtureRoot).TrimEnd(
            [System.IO.Path]::DirectorySeparatorChar,
            [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        foreach ($entry in $archive.Entries) {
            $path = $entry.FullName.Replace('\', '/')
            if (-not $expectedPaths.Contains($path) -or -not $seen.Add($path)) {
                throw "$Name ZIP has an unexpected or duplicate entry: $path"
            }
            $destination = [System.IO.Path]::GetFullPath((Join-Path $fixtureRoot (
                $path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))))
            if (-not $destination.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "$Name ZIP entry resolves outside its fixture root: $path"
            }
            $parent = [System.IO.Path]::GetDirectoryName($destination)
            [System.IO.Directory]::CreateDirectory($parent) | Out-Null
            $input = $entry.Open()
            $output = New-Object System.IO.FileStream(
                $destination,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None)
            try { $input.CopyTo($output) }
            finally {
                $output.Dispose()
                $input.Dispose()
            }
        }
        Assert-True ($seen.Count -eq $expectedPaths.Count) "$Name ZIP entry census differs from its record"
        $archive.Dispose()
        $archive = $null

        Invoke-TestGit $fixtureRoot @('init', '--quiet') | Out-Null
        Invoke-TestGit $fixtureRoot @('config', 'user.email', 'qa@example.invalid') | Out-Null
        Invoke-TestGit $fixtureRoot @('config', 'user.name', 'VT2 QA') | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $fixtureRoot '.fixture-base'), [byte[]](0x31))
        Invoke-TestGit $fixtureRoot @('add', '.fixture-base') | Out-Null
        Invoke-TestGit $fixtureRoot @('commit', '--quiet', '-m', 'fixture base') | Out-Null
        $base = Invoke-TestGit $fixtureRoot @('rev-parse', 'HEAD')
        $manifest = New-VtContentManifest -RepositoryRoot $fixtureRoot `
            -BaseCommit $base -Paths ([string[]]$expectedPaths)
        Assert-True (
            $manifest.ReviewerCompatibilitySha256 -eq $ExpectedCompatibilitySha
        ) "$Name actual frozen byte set did not reproduce its reviewer-corrected ordinal digest"
    } catch {
        $failures.Add("$Name frozen byte fixture failed: $($_.Exception.Message)")
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
        Remove-TestTree $fixtureRoot
    }
}

function Invoke-SelfTest {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) (
        'vt2-content-manifest-' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($temp) | Out-Null
    $oldAuthorDate = $env:GIT_AUTHOR_DATE
    $oldCommitterDate = $env:GIT_COMMITTER_DATE
    $oldCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
    $oldUiCulture = [System.Threading.Thread]::CurrentThread.CurrentUICulture
    try {
        Invoke-TestGit $temp @('init', '--quiet') | Out-Null
        Invoke-TestGit $temp @('config', 'user.email', 'qa@example.invalid') | Out-Null
        Invoke-TestGit $temp @('config', 'user.name', 'VT2 QA') | Out-Null
        $env:GIT_AUTHOR_DATE = '2026-08-27T00:00:00Z'
        $env:GIT_COMMITTER_DATE = '2026-08-27T00:00:00Z'

        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $unicodeName = 'unicod' + [char]0x00e9 + '-' + [char]0x00e4 + '.txt'
        $umlautName = [char]0x00e4 + 'ther.txt'
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'plain.txt'), $utf8.GetBytes('alpha'))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'space name.txt'), $utf8.GetBytes("line1`r`nline2`r`n"))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'unicode-ae.txt'), $utf8.GetBytes('placeholder'))
        [System.IO.File]::Move((Join-Path $temp 'unicode-ae.txt'), (Join-Path $temp $unicodeName))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'empty.bin'), [byte[]]@())
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'delete me.txt'), $utf8.GetBytes('old'))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'zeta.txt'), $utf8.GetBytes('z'))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'Alpha-upper.txt'), $utf8.GetBytes('upper'))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'alpha-lower-other.txt'), $utf8.GetBytes('lower'))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'aether.txt'), $utf8.GetBytes('a'))
        [System.IO.File]::Move((Join-Path $temp 'aether.txt'), (Join-Path $temp $umlautName))
        Invoke-TestGit $temp @('add', '--all') | Out-Null
        Invoke-TestGit $temp @('commit', '--quiet', '-m', 'base') | Out-Null
        $base = Invoke-TestGit $temp @('rev-parse', 'HEAD')

        [System.IO.File]::Delete((Join-Path $temp 'delete me.txt'))
        [System.IO.File]::WriteAllBytes((Join-Path $temp $unicodeName), $utf8.GetBytes('changed unicode'))
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'new untracked.txt'), $utf8.GetBytes('new'))
        $paths = @(
            'plain.txt', 'space name.txt', $unicodeName, 'empty.bin',
            'delete me.txt', 'new untracked.txt', 'zeta.txt', $umlautName,
            'Alpha-upper.txt', 'alpha-lower-other.txt')

        $byCulture = @{}
        foreach ($cultureName in @('en-US', 'tr-TR', 'invariant')) {
            $culture = if ($cultureName -eq 'invariant') {
                [System.Globalization.CultureInfo]::InvariantCulture
            } else {
                [System.Globalization.CultureInfo]::GetCultureInfo($cultureName)
            }
            [System.Threading.Thread]::CurrentThread.CurrentCulture = $culture
            [System.Threading.Thread]::CurrentThread.CurrentUICulture = $culture
            $byCulture[$cultureName] = New-VtContentManifest `
                -RepositoryRoot $temp -BaseCommit $base -Paths $paths
        }
        $baseline = $byCulture['en-US']
        Assert-True (
            (Test-ByteArrayEqual $baseline.ManifestBytes $byCulture['tr-TR'].ManifestBytes) -and
            (Test-ByteArrayEqual $baseline.ManifestBytes $byCulture['invariant'].ManifestBytes)
        ) 'manifest bytes depend on current culture'
        Assert-True (
            $baseline.AggregateSha256 -eq $byCulture['tr-TR'].AggregateSha256 -and
            $baseline.AggregateSha256 -eq $byCulture['invariant'].AggregateSha256
        ) 'aggregate digest depends on current culture'

        $orderedPaths = @($baseline.Entries | ForEach-Object { $_.Path })
        Assert-True (
            [array]::IndexOf($orderedPaths, 'zeta.txt') -lt [array]::IndexOf($orderedPaths, $umlautName)
        ) 'Unicode ordering is not ordinal'
        Assert-True (
            [array]::IndexOf($orderedPaths, 'Alpha-upper.txt') -lt
                [array]::IndexOf($orderedPaths, 'alpha-lower-other.txt')
        ) 'uppercase/lowercase path ordering is not ordinal'
        $ordinalFixture = [string[]]@('zeta.txt', $umlautName)
        $cultureFixture = [string[]]@('zeta.txt', $umlautName)
        [System.Array]::Sort($ordinalFixture, [System.StringComparer]::Ordinal)
        [System.Array]::Sort($cultureFixture, [System.StringComparer]::Create(
            [System.Globalization.CultureInfo]::GetCultureInfo('en-US'), $false))
        Assert-True (
            ($ordinalFixture -join "`n") -ne ($cultureFixture -join "`n")
        ) 'culture-sort exposure fixture does not differ from ordinal sorting'

        Assert-True ($baseline.ManifestText.IndexOf("`r") -lt 0) 'manifest contains CR bytes'
        Assert-True ($baseline.ManifestText.EndsWith("`n")) 'manifest lacks its final LF'
        Assert-True (-not (
            $baseline.ManifestBytes.Length -ge 3 -and
            $baseline.ManifestBytes[0] -eq 0xef -and
            $baseline.ManifestBytes[1] -eq 0xbb -and
            $baseline.ManifestBytes[2] -eq 0xbf
        )) 'manifest contains a UTF-8 BOM'
        Assert-True ($baseline.ManifestText -match 'space%20name\.txt') 'space path is not encoded unambiguously'
        Assert-True ($baseline.ManifestText -match 'unicod%C3%A9-%C3%A4\.txt') 'Unicode path is not encoded as UTF-8 bytes'
        Assert-True (@($baseline.Entries | Where-Object Kind -eq 'deleted').Count -eq 1) 'deletion state is not represented exactly once'
        Assert-True (@($baseline.Entries | Where-Object Kind -eq 'present').Count -eq 9) 'present state census is incorrect'
        $spaceEntry = @($baseline.Entries | Where-Object Path -ceq 'space name.txt')[0]
        $emptyEntry = @($baseline.Entries | Where-Object Path -ceq 'empty.bin')[0]
        $untrackedEntry = @($baseline.Entries | Where-Object Path -ceq 'new untracked.txt')[0]
        Assert-True (
            $spaceEntry.Kind -eq 'present' -and $spaceEntry.Length -eq 14 -and
            $spaceEntry.Sha256 -eq (Get-LowerSha256 ($utf8.GetBytes("line1`r`nline2`r`n")))
        ) 'CRLF file bytes were normalized or hashed incorrectly'
        Assert-True (
            $emptyEntry.Kind -eq 'present' -and $emptyEntry.Length -eq 0 -and
            $emptyEntry.Sha256 -eq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        ) 'empty file record is not the exact zero-byte SHA-256 identity'
        Assert-True (
            $untrackedEntry.Kind -eq 'present' -and $untrackedEntry.Length -eq 3 -and
            $untrackedEntry.Sha256 -eq (Get-LowerSha256 ($utf8.GetBytes('new')))
        ) 'untracked file is not represented as an exact present record'

        $collectedPaths = @(Get-VtChangedContentManifestPaths `
            -RepositoryRoot $temp -BaseCommit $base)
        Assert-True ($collectedPaths -ccontains $unicodeName) 'binary-safe collector lost a changed Unicode path'
        Assert-True ($collectedPaths -ccontains 'delete me.txt') 'binary-safe collector lost a deletion'
        Assert-True ($collectedPaths -ccontains 'new untracked.txt') 'binary-safe collector lost an untracked path'
        $trackedPathByteBound =
            $utf8.GetByteCount($unicodeName) + $utf8.GetByteCount('delete me.txt')
        Assert-ThrowsLike {
            Get-VtChangedContentManifestPaths -RepositoryRoot $temp -BaseCommit $base `
                -MaxTotalPathBytes $trackedPathByteBound | Out-Null
        } 'input bound|aggregate collector bound' 'collector accepted an untracked path after tracked paths exhausted the aggregate bound'
        [System.IO.File]::Delete((Join-Path $temp 'new untracked.txt'))
        try {
            $trackedOnlyPaths = @(Get-VtChangedContentManifestPaths `
                -RepositoryRoot $temp -BaseCommit $base)
            Assert-True (
                $trackedOnlyPaths -ccontains $unicodeName -and
                $trackedOnlyPaths -ccontains 'delete me.txt' -and
                $trackedOnlyPaths -cnotcontains 'new untracked.txt'
            ) 'collector did not preserve a real zero-length untracked byte stream'
        } finally {
            [System.IO.File]::WriteAllBytes((Join-Path $temp 'new untracked.txt'), $utf8.GetBytes('new'))
        }
        $savedGitEnvironment = @{}
        foreach ($name in $gitLocalEnvironmentNames) {
            $savedGitEnvironment[$name] = [pscustomobject]@{
                Exists = Test-Path -LiteralPath "Env:$name"
                Value = [Environment]::GetEnvironmentVariable($name, 'Process')
            }
        }
        try {
            [Environment]::SetEnvironmentVariable(
                'GIT_DIR', (Join-Path $temp 'foreign-does-not-exist.git'), 'Process')
            [Environment]::SetEnvironmentVariable(
                'GIT_WORK_TREE', $repoRoot, 'Process')
            [Environment]::SetEnvironmentVariable(
                'GIT_INDEX_FILE', (Join-Path $temp 'foreign-index'), 'Process')
            [Environment]::SetEnvironmentVariable('GIT_PREFIX', 'foreign/', 'Process')
            New-Item -Path Env:GIT_CONFIG -Value '' -Force | Out-Null
            New-Item -Path Env:GIT_CONFIG_COUNT -Value '' -Force | Out-Null
            $pollutedManifest = New-VtContentManifest `
                -RepositoryRoot $temp -BaseCommit $base -Paths @('plain.txt')
            $pollutedCollector = @(Get-VtChangedContentManifestPaths `
                -RepositoryRoot $temp -BaseCommit $base)
            Assert-True (
                $pollutedManifest.RepositoryRoot -eq $temp -and
                $pollutedCollector -ccontains $unicodeName -and
                [Environment]::GetEnvironmentVariable('GIT_DIR', 'Process') -eq
                    (Join-Path $temp 'foreign-does-not-exist.git')
            ) 'manifest Git subprocesses did not isolate and restore a hook-polluted environment'
        } finally {
            foreach ($name in $gitLocalEnvironmentNames) {
                $environmentPath = "Env:$name"
                Remove-Item -LiteralPath $environmentPath -ErrorAction SilentlyContinue
                if ($savedGitEnvironment[$name].Exists) {
                    New-Item -Path $environmentPath `
                        -Value $savedGitEnvironment[$name].Value -Force | Out-Null
                }
            }
        }
        $collectedResult = New-VtContentManifest `
            -RepositoryRoot $temp -BaseCommit $base -Paths $collectedPaths
        $collectorOutput = Join-Path ([System.IO.Path]::GetTempPath()) (
            'vt2-content-manifest-collected-' + [guid]::NewGuid().ToString('N'))
        try {
            $collectorExit = Invoke-ContentManifestCli @(
                '-RepositoryRoot', $temp,
                '-BaseCommit', $base,
                '-ChangedSinceBase',
                '-ManifestOut', $collectorOutput)
            Assert-True ($collectorExit -eq 0) 'CLI changed-set collector failed'
            Assert-True (
                [System.IO.File]::Exists($collectorOutput) -and
                (Test-ByteArrayEqual ([System.IO.File]::ReadAllBytes($collectorOutput)) $collectedResult.ManifestBytes)
            ) 'CLI changed-set bytes differ from direct binary-safe collection'
        } finally {
            if ([System.IO.File]::Exists($collectorOutput)) { [System.IO.File]::Delete($collectorOutput) }
        }

        [System.IO.File]::WriteAllBytes((Join-Path $temp 'plain.txt'), $utf8.GetBytes('alphb'))
        $byteChanged = New-VtContentManifest -RepositoryRoot $temp -BaseCommit $base -Paths $paths
        Assert-True ($byteChanged.AggregateSha256 -ne $baseline.AggregateSha256) 'one-byte change did not change aggregate digest'
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'plain.txt'), $utf8.GetBytes('alpha-longer'))
        $lengthChanged = New-VtContentManifest -RepositoryRoot $temp -BaseCommit $base -Paths $paths
        Assert-True ($lengthChanged.AggregateSha256 -ne $baseline.AggregateSha256) 'length change did not change aggregate digest'
        [System.IO.File]::WriteAllBytes((Join-Path $temp 'plain.txt'), $utf8.GetBytes('alpha'))

        [System.IO.File]::WriteAllBytes((Join-Path $temp 'moved.txt'), $utf8.GetBytes('alpha'))
        $movedPaths = @($paths | Where-Object { $_ -ne 'plain.txt' }) + @('moved.txt')
        $pathChanged = New-VtContentManifest -RepositoryRoot $temp -BaseCommit $base -Paths $movedPaths
        Assert-True ($pathChanged.AggregateSha256 -ne $baseline.AggregateSha256) 'path change did not change aggregate digest'

        [System.IO.File]::WriteAllBytes((Join-Path $temp 'base-marker.txt'), $utf8.GetBytes('base two'))
        Invoke-TestGit $temp @('add', 'base-marker.txt') | Out-Null
        $env:GIT_AUTHOR_DATE = '2026-08-27T00:01:00Z'
        $env:GIT_COMMITTER_DATE = '2026-08-27T00:01:00Z'
        Invoke-TestGit $temp @('commit', '--quiet', '-m', 'base two') | Out-Null
        $baseTwo = Invoke-TestGit $temp @('rev-parse', 'HEAD')
        $baseChanged = New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths $paths
        Assert-True ($baseChanged.AggregateSha256 -ne $baseline.AggregateSha256) 'base commit change did not change aggregate digest'

        [System.IO.File]::WriteAllBytes((Join-Path $temp 'delete me.txt'), $utf8.GetBytes('old'))
        $deletionChanged = New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths $paths
        Assert-True ($deletionChanged.AggregateSha256 -ne $baseChanged.AggregateSha256) 'deletion-state change did not change aggregate digest'
        [System.IO.File]::Delete((Join-Path $temp 'delete me.txt'))

        Assert-Throws {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths @('plain.txt', 'plain.txt') | Out-Null
        } 'duplicate path was accepted'
        Assert-Throws {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths @('plain.txt', 'PLAIN.txt') | Out-Null
        } 'case-colliding path was accepted'
        Assert-Throws {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths @('..\outside.txt') | Out-Null
        } 'out-of-root path was accepted'
        Assert-Throws {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths @('unknown-missing.txt') | Out-Null
        } 'unknown missing path was accepted as a deletion'
        Assert-ThrowsLike {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo `
                -Paths @('plain.txt', ('x' * 33)) -MaxPathBytes 32 | Out-Null
        } 'exceeds 32 UTF-8 bytes' 'overlong direct path was not rejected before path processing'
        Assert-ThrowsLike {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo `
                -Paths @('plain.txt', 'space name.txt') -MaxTotalPathBytes 10 | Out-Null
        } 'aggregate bound' 'aggregate direct-path byte bound was not enforced'
        if ($env:OS -eq 'Windows_NT') {
            Assert-ThrowsLike {
                New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo `
                    -Paths @('plain.txt:manifest-fixture') | Out-Null
            } 'alternate data stream' 'NTFS alternate-data-stream path was accepted'
        }
        $locked = New-Object System.IO.FileStream(
            (Join-Path $temp 'plain.txt'),
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None)
        try {
            Assert-ThrowsLike {
                New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo `
                    -Paths @('plain.txt', 'unknown-missing.txt') | Out-Null
            } 'unknown-missing\.txt' 'late invalid path did not fail before hashing an earlier locked file'
        } finally {
            $locked.Dispose()
        }
        Assert-Throws {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit 'HEAD' -Paths @('plain.txt') | Out-Null
        } 'symbolic base ref was accepted in place of an explicit commit ID'
        $sha256Temp = Join-Path ([System.IO.Path]::GetTempPath()) (
            'vt2-content-manifest-sha256-' + [guid]::NewGuid().ToString('N'))
        try {
            [System.IO.Directory]::CreateDirectory($sha256Temp) | Out-Null
            $sha256Supported = $true
            try {
                Invoke-TestGit $sha256Temp @('init', '--quiet', '--object-format=sha256') | Out-Null
            } catch {
                if ($_.Exception.Message -match 'unknown option|unknown hash algorithm|not supported') {
                    $sha256Supported = $false
                } else {
                    throw
                }
            }
            if ($sha256Supported) {
                Invoke-TestGit $sha256Temp @('config', 'user.email', 'qa@example.invalid') | Out-Null
                Invoke-TestGit $sha256Temp @('config', 'user.name', 'VT2 QA') | Out-Null
                [System.IO.File]::WriteAllBytes((Join-Path $sha256Temp 'item.txt'), $utf8.GetBytes('sha256'))
                Invoke-TestGit $sha256Temp @('add', 'item.txt') | Out-Null
                Invoke-TestGit $sha256Temp @('commit', '--quiet', '-m', 'sha256 base') | Out-Null
                $shaBase = Invoke-TestGit $sha256Temp @('rev-parse', 'HEAD')
                Assert-True ($shaBase.Length -eq 64) 'SHA-256 fixture did not produce a full 64-character commit ID'
                $shaFull = New-VtContentManifest `
                    -RepositoryRoot $sha256Temp -BaseCommit $shaBase -Paths @('item.txt')
                Assert-True ($shaFull.BaseCommit -eq $shaBase) 'full SHA-256 base commit was rejected or changed'
                Assert-ThrowsLike {
                    New-VtContentManifest -RepositoryRoot $sha256Temp `
                        -BaseCommit ($shaBase.Substring(0, 40)) -Paths @('item.txt') | Out-Null
                } 'complete object-format commit ID' '40-hex SHA-256 commit prefix was accepted as a full base commit'
            }
        } finally {
            if ([System.IO.Directory]::Exists($sha256Temp)) { Remove-TestTree $sha256Temp }
        }
        $tooMany = @()
        for ($i = 0; $i -lt 17; $i++) { $tooMany += "path-$i.txt" }
        Assert-Throws {
            New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths $tooMany -MaxEntries 16 | Out-Null
        } 'over-bound path set was accepted'

        $statusBeforeCli = Invoke-TestGit $temp @('status', '--porcelain=v1')
        $forbiddenOutput = Join-Path $temp 'forbidden.manifest'
        $forbiddenExit = Invoke-ContentManifestCli @(
            '-RepositoryRoot', $temp,
            '-BaseCommit', $baseTwo,
            '-Path', 'plain.txt',
            '-ManifestOut', $forbiddenOutput)
        Assert-True ($forbiddenExit -eq 2) 'CLI accepted a repository-internal output path'
        Assert-True (-not [System.IO.File]::Exists($forbiddenOutput)) 'CLI modified the reviewed repository'

        if ($env:OS -eq 'Windows_NT') {
            $junctionRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
                'vt2-content-manifest-junction-' + [guid]::NewGuid().ToString('N'))
            $aliasedOutput = Join-Path $junctionRoot 'aliased.manifest'
            $physicalOutput = Join-Path $temp 'aliased.manifest'
            try {
                New-Item -ItemType Junction -Path $junctionRoot -Target $temp -ErrorAction Stop | Out-Null
                $aliasedExit = Invoke-ContentManifestCli @(
                    '-RepositoryRoot', $temp,
                    '-BaseCommit', $baseTwo,
                    '-Path', 'plain.txt',
                    '-ManifestOut', $aliasedOutput)
                Assert-True ($aliasedExit -eq 2) 'CLI accepted a reparse-aliased output path'
                Assert-True (-not [System.IO.File]::Exists($physicalOutput)) 'CLI wrote through a reparse point into the reviewed repository'
            } finally {
                if ([System.IO.Directory]::Exists($junctionRoot)) {
                    [System.IO.Directory]::Delete($junctionRoot, $false)
                }
                if ([System.IO.File]::Exists($physicalOutput)) {
                    [System.IO.File]::Delete($physicalOutput)
                }
            }
        }

        $outsideOutput = Join-Path ([System.IO.Path]::GetTempPath()) (
            'vt2-content-manifest-output-' + [guid]::NewGuid().ToString('N'))
        try {
            $outsideExit = Invoke-ContentManifestCli @(
                '-RepositoryRoot', $temp,
                '-BaseCommit', $baseTwo,
                '-Path', 'plain.txt',
                '-ManifestOut', $outsideOutput)
            Assert-True ($outsideExit -eq 0) 'CLI could not emit an external canonical manifest'
            $single = New-VtContentManifest -RepositoryRoot $temp -BaseCommit $baseTwo -Paths @('plain.txt')
            Assert-True (
                [System.IO.File]::Exists($outsideOutput) -and
                (Test-ByteArrayEqual ([System.IO.File]::ReadAllBytes($outsideOutput)) $single.ManifestBytes)
            ) 'CLI external manifest bytes differ from the canonical module result'
            $firstOutputBytes = [System.IO.File]::ReadAllBytes($outsideOutput)
            $overwriteExit = Invoke-ContentManifestCli @(
                '-RepositoryRoot', $temp,
                '-BaseCommit', $baseTwo,
                '-Path', 'plain.txt',
                '-ManifestOut', $outsideOutput)
            Assert-True ($overwriteExit -eq 2) 'CLI overwrote an existing evidence file'
            Assert-True (
                Test-ByteArrayEqual ([System.IO.File]::ReadAllBytes($outsideOutput)) $firstOutputBytes
            ) 'failed overwrite changed existing evidence bytes'
        } finally {
            if ([System.IO.File]::Exists($outsideOutput)) { [System.IO.File]::Delete($outsideOutput) }
        }
        $statusAfterCli = Invoke-TestGit $temp @('status', '--porcelain=v1')
        Assert-True ($statusBeforeCli -ceq $statusAfterCli) 'CLI changed repository or index state'

        $pathList = Join-Path ([System.IO.Path]::GetTempPath()) (
            'vt2-content-manifest-paths-' + [guid]::NewGuid().ToString('N') + '.txt')
        try {
            [System.IO.File]::WriteAllBytes($pathList, $utf8.GetBytes("plain.txt`n$unicodeName`n"))
            $readPaths = @(Read-VtContentManifestPathFile -PathFile $pathList)
            Assert-True ($readPaths.Count -eq 2) 'bounded UTF-8 path-list reader lost entries'
            Assert-Throws {
                Read-VtContentManifestPathFile -PathFile $pathList -MaxPathFileBytes 8 | Out-Null
            } 'over-bound path-list file was accepted'
        } finally {
            if ([System.IO.File]::Exists($pathList)) { [System.IO.File]::Delete($pathList) }
        }

        $recordRoot = Join-Path $PSScriptRoot 'fixtures\content_manifest'
        Test-ReviewerRecordFixture `
            -FixturePath (Join-Path $recordRoot 'vmb-1429.records') `
            -ExpectedSha '29507cb7610d0eec4d4e1ade4c7309c99f07e4176553060634325f9c48950cbd' `
            -Name 'VMBLauncher #1429'
        Test-ReviewerRecordFixture `
            -FixturePath (Join-Path $recordRoot 'updater-1430.records') `
            -ExpectedSha '02643fd76b5005599fade40078bee44a67d94fc41bd9dded48671d8fcf5c3704' `
            -Name 'updater #1430 canonical correction'
        Test-FrozenByteSetFixture `
            -ZipPath (Join-Path $recordRoot 'vmb-1429.zip') `
            -RecordPath (Join-Path $recordRoot 'vmb-1429.records') `
            -ExpectedZipSha '90fd3cab463d46e9b6f3094ae4cb641d9b150e4a085d9285fad32cde949866c6' `
            -ExpectedCompatibilitySha '29507cb7610d0eec4d4e1ade4c7309c99f07e4176553060634325f9c48950cbd' `
            -Name 'VMBLauncher #1429'
        Test-FrozenByteSetFixture `
            -ZipPath (Join-Path $recordRoot 'updater-1430.zip') `
            -RecordPath (Join-Path $recordRoot 'updater-1430.records') `
            -ExpectedZipSha '039d10ee492d19b82edaed64929805b8dd5d0ebd9fef71caa014518e306ad721' `
            -ExpectedCompatibilitySha '02643fd76b5005599fade40078bee44a67d94fc41bd9dded48671d8fcf5c3704' `
            -Name 'updater #1430 canonical correction'

        Test-ExternalSnapshot `
            -Root $VmbSnapshotRoot `
            -ExpectedBase 'f83745546f876005ee6af8d966b19da01a887421' `
            -ExpectedCompatibilitySha '29507cb7610d0eec4d4e1ade4c7309c99f07e4176553060634325f9c48950cbd' `
            -Name 'VMBLauncher #1429'
        Test-ExternalSnapshot `
            -Root $UpdaterSnapshotRoot `
            -ExpectedBase 'cb450a270619bfe02cef492df631f88261c45c89' `
            -ExpectedCompatibilitySha '02643fd76b5005599fade40078bee44a67d94fc41bd9dded48671d8fcf5c3704' `
            -Name 'updater #1430'
    } finally {
        [System.Threading.Thread]::CurrentThread.CurrentCulture = $oldCulture
        [System.Threading.Thread]::CurrentThread.CurrentUICulture = $oldUiCulture
        $env:GIT_AUTHOR_DATE = $oldAuthorDate
        $env:GIT_COMMITTER_DATE = $oldCommitterDate
        Remove-TestTree $temp
    }
}

Invoke-SelfTest
if ($failures.Count -gt 0) {
    Write-Host "[check_content_manifest] ERRORS -- $($failures.Count) fixture(s) failed" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) {
    Write-Host '[check_content_manifest] OK -- canonical cross-culture manifest contract passed.' -ForegroundColor Green
}
exit 0
