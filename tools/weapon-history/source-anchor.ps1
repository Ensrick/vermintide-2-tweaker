# Shared reader for tools/weapon-history/current_source_anchor.lua.
# Keep the data in the Lua module so generators and PowerShell gates consume
# one identity. This reader accepts only that module's narrow literal grammar.

function ConvertFrom-WtHistorySourceAnchorLiteral {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Path = '<literal>'
    )

    function Read-OneLiteral([string]$Name, [string]$Pattern) {
        $matches = [regex]::Matches($Text, $Pattern)
        if ($matches.Count -ne 1) {
            throw "Weapon-history source anchor must contain exactly one literal $Name."
        }
        return $matches[0].Groups[1].Value
    }

    $schema = Read-OneLiteral 'schema' '(?m)^\s*schema\s*=\s*([0-9]+),\s*$'
    $canonicalUrl = Read-OneLiteral 'canonical_url' `
        '(?m)^\s*canonical_url\s*=\s*"(https://github\.com/Aussiemon/Vermintide-2-Source-Code)",\s*$'
    $contentRevision = Read-OneLiteral 'content_revision' `
        '(?m)^\s*content_revision\s*=\s*"([0-9a-f]{40})",\s*$'
    $defaultRef = Read-OneLiteral 'default_ref' `
        '(?m)^\s*default_ref\s*=\s*"(refs/heads/[A-Za-z0-9._/-]+)",\s*$'
    $gameVersion = Read-OneLiteral 'game_version' `
        '(?m)^\s*game_version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)",\s*$'
    $observedAt = Read-OneLiteral 'observed_at_utc' `
        '(?m)^\s*observed_at_utc\s*=\s*"([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)",\s*$'
    $observedTip = Read-OneLiteral 'observed_default_tip' `
        '(?m)^\s*observed_default_tip\s*=\s*"([0-9a-f]{40})",\s*$'
    $relation = Read-OneLiteral 'observed_tip_content_relation' `
        '(?m)^\s*observed_tip_content_relation\s*=\s*"(direct_parent|same_commit)",\s*$'
    $metadataLiteral = Read-OneLiteral 'observed_tip_metadata_paths' `
        '(?ms)^\s*observed_tip_metadata_paths\s*=\s*\{(.*?)\},\s*$'

    $metadataPaths = @()
    switch ($schema) {
        '1' {
            if ($relation -cne 'direct_parent') {
                throw 'Weapon-history schema 1 requires a direct_parent tip relation.'
            }
            if ($metadataLiteral -notmatch '^\s*"README\.md"\s*$') {
                throw 'Weapon-history schema 1 requires the README.md metadata gap.'
            }
            if ($contentRevision -ceq $observedTip) {
                throw 'Weapon-history schema 1 semantic revision and observed tip must remain distinct.'
            }
            $metadataPaths = @('README.md')
        }
        '2' {
            if ($relation -cne 'same_commit') {
                throw 'Weapon-history schema 2 requires a same_commit tip relation.'
            }
            if (-not [string]::IsNullOrWhiteSpace($metadataLiteral)) {
                throw 'Weapon-history schema 2 requires an empty metadata gap.'
            }
            if ($contentRevision -cne $observedTip) {
                throw 'Weapon-history schema 2 semantic revision must equal the observed tip.'
            }
        }
        default { throw "Unsupported weapon-history source anchor schema $schema." }
    }
    try {
        $null = [DateTime]::ParseExact($observedAt, 'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal)
    }
    catch { throw "Invalid weapon-history anchor observation time: $observedAt" }

    return [pscustomobject]@{
        Path = $Path
        Schema = [int]$schema
        CanonicalUrl = $canonicalUrl
        ContentRevision = $contentRevision
        DefaultRef = $defaultRef
        GameVersion = $gameVersion
        ObservedAtUtc = $observedAt
        ObservedDefaultTip = $observedTip
        ObservedTipContentRelation = $relation
        ObservedTipMetadataPaths = @($metadataPaths)
    }
}

function Read-WtHistorySourceAnchor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoRoot)

    $path = Join-Path $RepoRoot 'tools\weapon-history\current_source_anchor.lua'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Weapon-history source anchor not found: $path"
    }
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return ConvertFrom-WtHistorySourceAnchorLiteral -Text $text -Path $path
}

function Invoke-WtHistoryReadOnlyGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $priorPreference = $ErrorActionPreference
    $priorNoLazyFetchPresent = Test-Path Env:GIT_NO_LAZY_FETCH
    $priorNoLazyFetch = [Environment]::GetEnvironmentVariable(
        'GIT_NO_LAZY_FETCH', 'Process')
    $priorOptionalLocksPresent = Test-Path Env:GIT_OPTIONAL_LOCKS
    $priorOptionalLocks = [Environment]::GetEnvironmentVariable(
        'GIT_OPTIONAL_LOCKS', 'Process')
    try {
        # Native stderr is expected for missing objects. Keep the probe read-only
        # and classify only its exit code/output under both PS7 and PS5.1.
        # Disable promisor lazy-fetch and optional locking so a partial checkout
        # cannot turn validation into network or object/index mutation.
        $ErrorActionPreference = 'Continue'
        [Environment]::SetEnvironmentVariable('GIT_NO_LAZY_FETCH', '1', 'Process')
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0', 'Process')
        $output = @(& git -C $Repository @Arguments 2>$null)
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = @($output | ForEach-Object { [string]$_ })
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = -1
            Output = @()
        }
    }
    finally {
        if ($priorNoLazyFetchPresent) {
            [Environment]::SetEnvironmentVariable('GIT_NO_LAZY_FETCH',
                $priorNoLazyFetch, 'Process')
        }
        else {
            Remove-Item Env:GIT_NO_LAZY_FETCH -ErrorAction SilentlyContinue
        }
        if ($priorOptionalLocksPresent) {
            [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS',
                $priorOptionalLocks, 'Process')
        }
        else {
            Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue
        }
        $ErrorActionPreference = $priorPreference
    }
}

function Read-WtHistorySourceBlobLedger {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Weapon-history source-blob ledger not found: $Path"
    }

    $requirements = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    $insideLedger = $false
    $foundLedger = $false
    $revision = $null
    foreach ($line in [System.IO.File]::ReadAllLines($Path,
            [System.Text.Encoding]::UTF8)) {
        if (-not $insideLedger) {
            if ($line -match '^\s*source_blobs\s*=\s*\{\s*$') {
                $insideLedger = $true
                $foundLedger = $true
            }
            continue
        }

        if (-not $revision) {
            if ($line -match '^\s*(?:\["([0-9a-f]{40})"\]|([0-9a-f]{40}))\s*=\s*\{\s*$') {
                $revision = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                continue
            }
            if ($line -match '^\s*\},?\s*$') {
                $insideLedger = $false
                break
            }
            if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*--') {
                continue
            }
            throw "Unexpected weapon-history source-blob ledger row: $line"
        }

        if ($line -match '^\s*\["([^"\\]+)"\]\s*=\s*"([0-9a-f]{40})",?\s*$') {
            $sourcePath = $Matches[1]
            $blob = $Matches[2]
            if ($sourcePath.StartsWith('/') -or $sourcePath.Contains('..') -or
                $sourcePath.Contains(':')) {
                throw "Unsafe weapon-history source path in ledger: $sourcePath"
            }
            $key = "$revision`:$sourcePath"
            if ($seen.ContainsKey($key)) {
                throw "Duplicate weapon-history source requirement: $key"
            }
            $seen[$key] = $true
            $requirements.Add([pscustomobject]@{
                    Revision = $revision
                    Path = $sourcePath
                    Blob = $blob
                }) | Out-Null
            continue
        }
        if ($line -match '^\s*\},\s*$') {
            $revision = $null
            continue
        }
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^\s*--') {
            continue
        }
        throw "Unexpected weapon-history source-blob requirement row: $line"
    }

    if (-not $foundLedger -or $insideLedger -or $revision -or
        $requirements.Count -eq 0) {
        throw "Weapon-history source-blob ledger is missing or incomplete: $Path"
    }
    return @($requirements.ToArray())
}

function Test-WtHistorySourceCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][object[]]$Requirements
    )

    if (-not (Test-Path -LiteralPath $Candidate -PathType Container)) {
        return [pscustomobject]@{ Valid = $false; Path = $Candidate; Reason = 'path is absent' }
    }
    $gitMarker = Join-Path $Candidate '.git'
    if (-not (Test-Path -LiteralPath $gitMarker)) {
        return [pscustomobject]@{ Valid = $false; Path = $Candidate; Reason = '.git is absent' }
    }

    $resolved = (Resolve-Path -LiteralPath $Candidate).Path
    $rows = @($Requirements)
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            Valid = $false; Path = $resolved; Reason = 'required object ledger is empty'
        }
    }

    $revisions = @($rows | ForEach-Object { [string]$_.Revision } |
        Sort-Object -Unique)
    foreach ($requiredRevision in $revisions) {
        if ($requiredRevision -notmatch '^[0-9a-f]{40}$') {
            return [pscustomobject]@{
                Valid = $false; Path = $resolved
                Reason = "invalid required revision $requiredRevision"
            }
        }
        $commitProbe = Invoke-WtHistoryReadOnlyGit -Repository $resolved `
            -Arguments @('cat-file', '-e', "$requiredRevision`^{commit}")
        if ($commitProbe.ExitCode -ne 0) {
            return [pscustomobject]@{
                Valid = $false; Path = $resolved
                Reason = "missing required commit $requiredRevision"
            }
        }
    }

    foreach ($row in $rows) {
        $requiredRevision = [string]$row.Revision
        $requiredPath = [string]$row.Path
        $requiredBlob = [string]$row.Blob
        if ($requiredPath -notmatch '^[A-Za-z0-9._/-]+$' -or
            $requiredPath.StartsWith('/') -or $requiredPath.Contains('..') -or
            $requiredBlob -notmatch '^[0-9a-f]{40}$') {
            return [pscustomobject]@{
                Valid = $false; Path = $resolved
                Reason = "invalid required commit:path/blob row for $requiredRevision`:$requiredPath"
            }
        }

        $objectName = "$requiredRevision`:$requiredPath"
        $pathProbe = Invoke-WtHistoryReadOnlyGit -Repository $resolved `
            -Arguments @('rev-parse', '--verify', $objectName)
        $resolvedObjects = @($pathProbe.Output | Where-Object {
                $_ -match '^[0-9a-f]{40}$'
            })
        if ($pathProbe.ExitCode -ne 0 -or $resolvedObjects.Count -ne 1) {
            return [pscustomobject]@{
                Valid = $false; Path = $resolved
                Reason = "missing required object $objectName"
            }
        }
        if ($resolvedObjects[0] -cne $requiredBlob) {
            return [pscustomobject]@{
                Valid = $false; Path = $resolved
                Reason = "blob mismatch for $objectName expected=$requiredBlob actual=$($resolvedObjects[0])"
            }
        }
        $blobProbe = Invoke-WtHistoryReadOnlyGit -Repository $resolved `
            -Arguments @('cat-file', '-e', "$requiredBlob`^{blob}")
        if ($blobProbe.ExitCode -ne 0) {
            return [pscustomobject]@{
                Valid = $false; Path = $resolved
                Reason = "required blob is unavailable: $requiredBlob ($objectName)"
            }
        }
    }

    return [pscustomobject]@{ Valid = $true; Path = $resolved; Reason = 'complete' }
}

function Find-WtHistorySourceRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$Explicit,
        [Parameter(Mandatory)][object[]]$Requirements
    )

    $candidates = @()
    if ($Explicit) {
        # An explicit checkout is an exact request, not permission to silently
        # fall through to another machine-local source tree.
        $candidates = @($Explicit)
    }
    else {
        if ($env:VT2_SOURCE_REPO) { $candidates += $env:VT2_SOURCE_REPO }
        $candidates += (Join-Path (Split-Path $Root -Parent) 'Vermintide-2-Source-Code')
        try {
            $commonProbe = Invoke-WtHistoryReadOnlyGit -Repository $Root `
                -Arguments @('rev-parse', '--git-common-dir')
            if ($commonProbe.ExitCode -eq 0 -and $commonProbe.Output.Count -eq 1) {
                $common = $commonProbe.Output[0]
                if (-not [IO.Path]::IsPathRooted($common)) {
                    $common = Join-Path $Root $common
                }
                $mainRoot = Split-Path ([IO.Path]::GetFullPath($common)) -Parent
                $candidates += (Join-Path (Split-Path $mainRoot -Parent) `
                    'Vermintide-2-Source-Code')
            }
        }
        catch {
            # Candidate absence is classified below.
        }
    }

    $rejections = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($candidates | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_)
            } | Select-Object -Unique)) {
        $result = Test-WtHistorySourceCandidate -Candidate $candidate `
            -Requirements $Requirements
        if ($result.Valid) {
            return [pscustomobject]@{
                Path = $result.Path
                Rejections = @($rejections.ToArray())
            }
        }
        $rejections.Add("$($result.Path) ($($result.Reason))") | Out-Null
    }

    return [pscustomobject]@{
        Path = $null
        Rejections = @($rejections.ToArray())
    }
}
