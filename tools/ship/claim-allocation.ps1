# Permanent reservation owner (#724). Loaded by claim.ps1; no live side effects
# on import. Activation is source-owned, never inferred from state-file presence.

function Get-AllocationHash {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-AllocationMod {
    param([string]$Mod)
    if ($Mod -cnotmatch '\A[a-z][a-z0-9_]{0,95}\z') { throw 'Invalid allocation mod identity.' }
}

function Get-AllocationVersion {
    param([string]$Version)
    if ($Version -cnotmatch '\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[A-Za-z]+)?\z') {
        throw 'Allocation version must be canonical three-segment semver.'
    }
    $parts = @([int]::Parse($matches[1]), [int]::Parse($matches[2]), [int]::Parse($matches[3]))
    return [pscustomobject]@{ Number = [version]($parts -join '.'); Suffix = [string]$matches[4] }
}

function Get-AllocationPolicy {
    param([string]$Path, [string]$Mod)
    Assert-AllocationMod $Mod
    # Literal data only; SafeGetValue also avoids PowerShell-7 inherited module
    # search paths hiding Import-PowerShellDataFile in a PS5 child broker.
    if ((Get-Item -LiteralPath $Path).Length -gt 16384) { throw 'Allocation policy exceeds its bound.' }
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
    $statements=@($ast.EndBlock.Statements)
    if ($errors.Count -or $ast.ParamBlock -or $ast.BeginBlock -or $ast.ProcessBlock -or
        $statements.Count -ne 1 -or $statements[0] -isnot [Management.Automation.Language.PipelineAst] -or
        $statements[0].PipelineElements.Count -ne 1 -or
        $statements[0].PipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst] -or
        $statements[0].PipelineElements[0].Expression -isnot [Management.Automation.Language.HashtableAst]) { throw 'Allocation policy must be one literal data table.' }
    $policy = $statements[0].PipelineElements[0].Expression.SafeGetValue()
    if ($policy.Count -ne 2 -or @($policy.Keys) -cnotcontains 'Schema' -or
        @($policy.Keys) -cnotcontains 'EnabledMods' -or $policy.Schema -isnot [int] -or $policy.Schema -ne 1 -or
        $policy.EnabledMods -isnot [Array]) {
        throw 'Invalid allocation activation policy.'
    }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $enabled = $false
    foreach ($row in @($policy.EnabledMods)) {
        if ($row -isnot [string]) { throw 'Invalid allocation policy mod.' }
        Assert-AllocationMod $row
        if (-not $seen.Add($row)) { throw 'Duplicate allocation policy mod.' }
        if ($row -ceq $Mod) { $enabled = $true }
    }
    return $enabled
}

function Assert-AllocationPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.Substring([IO.Path]::GetPathRoot($full).Length).Contains(':')) { throw 'Allocation path refuses alternate streams.' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Allocation path refuses reparse ancestry.' }
        }
        $cursor = [IO.Path]::GetDirectoryName($cursor)
    }
    return $full
}

function Get-AllocationPaths {
    param([string]$ClaimsDir, [string]$Mod)
    Assert-AllocationMod $Mod
    $root = Assert-AllocationPath $ClaimsDir
    if (-not [IO.Directory]::Exists($root)) { throw 'Allocation authority directory must already exist; no automatic initialization.' }
    return @{ Claim = (Join-Path $root "$Mod.claim"); State = (Join-Path $root "$Mod.allocation") }
}

function Invoke-WithAllocationLock {
    param([string]$ClaimPath, [scriptblock]$Action, [int]$TimeoutMilliseconds = 10000)
    # New brokers serialize across Windows sessions; same-session old brokers
    # also serialize via the old Local lock. Older cross-session writers do NOT
    # share Global: exact held claim handles below provide their exclusion.
    # No machine/release lock is acquired here; this bounded leaf lock may be
    # nested beneath those owners, and is always released before returning.
    $name = (Get-ClaimMutationMutexName $ClaimPath).Replace('Local\', 'Global\')
    $mutex = New-Object Threading.Mutex($false, $name)
    $held = $false
    try {
        try { $held = $mutex.WaitOne($TimeoutMilliseconds) }
        catch [Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { throw 'Timed out acquiring permanent allocation lock.' }
        return Invoke-WithClaimMutationLock -Path $ClaimPath -TimeoutMilliseconds $TimeoutMilliseconds -Action $Action
    }
    finally { if ($held) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}

function Open-AllocationClaim {
    param([string]$Path)
    $null = Assert-AllocationPath $Path
    if (-not [IO.File]::Exists($Path)) {
        if (Test-Path -LiteralPath $Path) { throw 'Claim is not a regular file.' }
        return $null
    }
    # Reuse the existing handle-owned exact deletion implementation. Never
    # compare bytes then Remove-Item: old brokers in other sessions can race it.
    . (Join-Path $PSScriptRoot 'build-output-normalization.ps1')
    Initialize-BuildOutputNormalizationNativeMethods
    $handle = [VtBuildNormalization.NativeMethods]::OpenExactDeleteHandle($Path)
    $stream = $null
    try {
        $info = [VtBuildNormalization.NativeMethods]::GetInformation($handle)
        if (($info.FileAttributes -band 0x410) -ne 0 -or $info.NumberOfLinks -ne 1 -or $info.FileSizeHigh -ne 0 -or
            $info.FileSizeLow -lt 1 -or $info.FileSizeLow -gt 8192) { throw 'Claim is not a bounded single-link regular file.' }
        $stream = New-Object IO.FileStream($handle, [IO.FileAccess]::Read)
        $bytes = New-Object byte[] ([int]$info.FileSizeLow)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $n = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($n -eq 0) { throw 'Claim read ended early.' }; $offset += $n
        }
        $raw = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
        $claim = ConvertFrom-AllocationClaim $raw
        return [pscustomobject]@{ Stream = $stream; Handle = $handle; Raw = $raw; Hash = (Get-AllocationHash $bytes); Claim = $claim }
    }
    catch { if ($stream) { $stream.Dispose() } else { $handle.Dispose() }; throw }
}

function ConvertFrom-AllocationClaim {
    param([string]$Raw)
    $lines = $Raw -split "`n"
    if ($lines.Count -ne 5 -or $lines[0] -cne '# VT2 ship/version claim -- see tools/ship/CLAIMS.md') { throw 'Claim wire is not canonical.' }
    $names = @('mod', 'version', 'session', 'created')
    $map = @{}
    for ($i = 0; $i -lt 4; $i++) {
        $prefix = $names[$i] + ' = '
        if (-not $lines[$i+1].StartsWith($prefix, [StringComparison]::Ordinal)) { throw 'Claim wire fields are not canonical.' }
        $value = $lines[$i+1].Substring($prefix.Length)
        if ($value -cnotmatch '\A[^\s\x00-\x1f\x7f][^\x00-\x1f\x7f]{0,1023}\z' -or $value.Trim() -cne $value) { throw 'Invalid claim field.' }
        $map[$names[$i]] = $value
    }
    Assert-AllocationMod $map.mod
    $null = Get-AllocationVersion $map.version
    $time = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($map.created, 'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$time)) { throw 'Invalid claim timestamp.' }
    return [pscustomobject]@{ Mod=$map.mod; Version=$map.version; Session=$map.session; CreatedUtc=$time; Raw=$Raw }
}

function Format-AllocationState {
    param([string]$Mod, [string]$Floor, [string]$Status, [string]$ClaimRaw, [string]$Review)
    Assert-AllocationMod $Mod
    $v = Get-AllocationVersion $Floor
    if ($v.Suffix) { throw 'Allocation floor must be numeric, without a release suffix.' }
    if ($Status -cnotin @('empty','active','released')) { throw 'Invalid allocation state.' }
    if ($Review -cnotmatch '\Ahttps://github\.com/Ensrick/vermintide-2-tweaker/(issues|pull)/[1-9][0-9]*(#issuecomment-[1-9][0-9]*)?\z') { throw 'Explicit reviewed migration reference is required.' }
    $hash = '-'; $data = '-'
    if ($Status -ceq 'empty') { if ($ClaimRaw) { throw 'Empty state cannot bind a claim.' } }
    else {
        $claim = ConvertFrom-AllocationClaim $ClaimRaw
        if ($claim.Mod -cne $Mod -or (Get-AllocationVersion $claim.Version).Number -gt $v.Number) { throw 'Reservation exceeds or mismatches allocation floor.' }
        $bytes = [Text.Encoding]::UTF8.GetBytes($ClaimRaw)
        $hash = Get-AllocationHash $bytes; $data = [Convert]::ToBase64String($bytes)
    }
    return @('VT2-ALLOCATION|1', "mod=$Mod", "floor=$Floor", "status=$Status", "claim_sha256=$hash", "claim_base64=$data", "review=$Review", '') -join "`n"
}

function Read-AllocationState {
    param([string]$Path, [string]$Mod)
    $null = Assert-AllocationPath $Path
    if (-not [IO.File]::Exists($Path)) { throw 'Permanent allocation history is missing; explicit reviewed initialization is required.' }
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        . (Join-Path $PSScriptRoot 'build-output-normalization.ps1')
        Initialize-BuildOutputNormalizationNativeMethods
        $info = [VtBuildNormalization.NativeMethods]::GetInformation($stream.SafeFileHandle)
        if (($info.FileAttributes -band 0x410) -ne 0 -or $info.NumberOfLinks -ne 1) { throw 'Allocation state is not a single-link regular file.' }
        if ($stream.Length -gt 16384 -or $stream.Length -eq 0) { throw 'Invalid allocation state size.' }
        $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false,$true)), $false)
        try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    $lines = $raw -split "`n"
    if ($lines.Count -ne 8 -or $lines[0] -cne 'VT2-ALLOCATION|1' -or $lines[7] -cne '') { throw 'Corrupt allocation state framing.' }
    $names = @('mod','floor','status','claim_sha256','claim_base64','review'); $map = @{}
    for ($i=0; $i -lt 6; $i++) {
        $prefix = $names[$i] + '='
        if (-not $lines[$i+1].StartsWith($prefix,[StringComparison]::Ordinal)) { throw 'Corrupt allocation state fields.' }
        $map[$names[$i]] = $lines[$i+1].Substring($prefix.Length)
    }
    if ($map.mod -cne $Mod) { throw 'Foreign allocation state.' }
    $claimRaw = ''
    if ($map.status -cne 'empty') { $claimRaw = (New-Object Text.UTF8Encoding($false,$true)).GetString([Convert]::FromBase64String($map.claim_base64)) }
    $canonical = Format-AllocationState $Mod $map.floor $map.status $claimRaw $map.review
    if ($canonical -cne $raw) { throw 'Corrupt/noncanonical allocation state or reservation hash.' }
    return @{ Mod=$Mod; Floor=$map.floor; Status=$map.status; ClaimRaw=$claimRaw; ClaimHash=$map.claim_sha256; Review=$map.review; Raw=$raw }
}

function Write-AllocationState {
    param([string]$Path, [AllowNull()][string]$ExpectedRaw, [string]$Raw)
    # Caller holds Global allocation lock. Old brokers never write this file.
    # Compare/readback is drift detection, NOT a filesystem CAS claim.
    $null = Assert-AllocationPath $Path
    $pending = $Path + '.' + [guid]::NewGuid().ToString('N') + '.pending'
    $bytes = [Text.Encoding]::UTF8.GetBytes($Raw)
    $stream = [IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    try {
        if ($null -eq $ExpectedRaw -or $ExpectedRaw -eq '') {
            [IO.File]::Move($pending,$Path) # CREATE_NEW semantics; never overwrite unknown history.
        } else {
            if ([IO.File]::ReadAllText($Path) -cne $ExpectedRaw) { throw 'Allocation history changed outside its Global owner.' }
            [IO.File]::Replace($pending,$Path,[NullString]::Value)
        }
        if ([IO.File]::ReadAllText($Path) -cne $Raw) { throw 'Allocation state readback failed.' }
    } finally { if ([IO.File]::Exists($pending)) { [IO.File]::Delete($pending) } }
}

function Initialize-PermanentAllocation {
    param([string]$ClaimsDir,[string]$Mod,[string]$RepoRoot,[string]$ReviewedFloor,[string]$ExpectedClaimSha256,[string]$ReviewReference)
    $paths = Get-AllocationPaths $ClaimsDir $Mod
    if ($ExpectedClaimSha256 -cnotmatch '\A(absent|[0-9a-f]{64})\z') { throw 'Initialization requires exact claim SHA-256 or literal absent.' }
    return Invoke-WithAllocationLock $paths.Claim {
        if (Test-Path -LiteralPath $paths.State) { throw 'Allocation history already exists; initialization cannot reset it.' }
        $floor = Get-AllocationVersion $ReviewedFloor
        if ($floor.Suffix -or $floor.Number -lt (Get-AllocationVersion (Get-ClaimModVersion $RepoRoot $Mod)).Number) { throw 'Reviewed floor is below current source.' }
        $locked = Open-AllocationClaim $paths.Claim
        try {
            $actual = if ($locked) { $locked.Hash } else { 'absent' }
            if ($actual -cne $ExpectedClaimSha256) { throw 'Claim changed since migration review; no allocation state was initialized.' }
            $status = if ($locked) { 'active' } else { 'empty' }
            $raw = if ($locked) { $locked.Raw } else { '' }
            $state = Format-AllocationState $Mod $ReviewedFloor $status $raw $ReviewReference
            Write-AllocationState $paths.State $null $state
            if (-not $locked -and (Test-Path -LiteralPath $paths.Claim)) { throw 'An old writer created a claim during initialization; floor retained, reconciliation required.' }
            # Existing claim stays byte-exact, including an old stale timestamp.
            return @{ Initialized=$true; Adopted=($null -ne $locked); Floor=$ReviewedFloor }
        } finally { if ($locked) { $locked.Stream.Dispose() } }
    }
}

function Invoke-PermanentClaim {
    param([ValidateSet('Acquire','Release','Verify')][string]$Operation,[string]$ClaimsDir,[string]$Mod,[string]$RepoRoot,
        [string]$Session,[string]$ExpectedVersion,[datetime]$NowUtc,[double]$StaleHours=24)
    if ([string]::IsNullOrWhiteSpace($Session)) { throw 'Permanent claim requires an exact owner.' }
    $paths = Get-AllocationPaths $ClaimsDir $Mod
    return Invoke-WithAllocationLock $paths.Claim {
        $state = Read-AllocationState $paths.State $Mod
        $locked = Open-AllocationClaim $paths.Claim
        try {
            if ($locked -and ($state.Status -ceq 'empty' -or $locked.Raw -cne $state.ClaimRaw -or $locked.Hash -cne $state.ClaimHash)) {
                throw 'Unbound/changed old-broker claim; explicit reconciliation required.'
            }
            $existing = if ($locked) { $locked.Claim } else { $null }
            if ($Operation -ceq 'Verify') {
                if (-not $existing) { return @{State='absent';Claim=$null} }
                if ($state.Status -cne 'active') { throw 'Released reservation cannot authorize a ship.' }
                if (Test-ClaimStale $existing.CreatedUtc $NowUtc $StaleHours) { return @{State='stale';Claim=$existing} }
                if ($existing.Version -cne $ExpectedVersion) { return @{State='mismatch';Claim=$existing} }
                if ($existing.Session -cne $Session) { return @{State='owner_mismatch';Claim=$existing} }
                return @{State='ok';Claim=$existing}
            }
            if ($Operation -ceq 'Release' -and $existing -and $existing.Session -cne $Session) {
                return @{Ok=$false;Removed=$false;CrossSession=$true;Held=$existing;Message='foreign owner'}
            }
            $stale = $existing -and (Test-ClaimStale $existing.CreatedUtc $NowUtc $StaleHours)
            if ($Operation -ceq 'Acquire' -and $existing -and $state.Status -ceq 'active' -and -not $stale) {
                return @{Ok=($existing.Session -ceq $Session);Acquired=$false;Version=$existing.Version;Held=$existing;
                    ClaimPath=$paths.Claim;BrokeStale=$false;Message='live reservation already held'}
            }
            # Retire before deleting. The same exact handle prevents replacement
            # by an old writer between proof, retirement and delete-on-close.
            if ($state.Status -ceq 'active') {
                $retired = Format-AllocationState $Mod $state.Floor 'released' $state.ClaimRaw $state.Review
                Write-AllocationState $paths.State $state.Raw $retired
                $state = Read-AllocationState $paths.State $Mod
            }
            if ($locked) {
                [VtBuildNormalization.NativeMethods]::MarkDeleteOnClose($locked.Handle)
                $locked.Stream.Dispose(); $locked = $null
            }
            if ($Operation -ceq 'Release') { return @{Ok=$true;Removed=($null -ne $existing);CrossSession=$false;Held=$existing;Message='released; version remains burned'} }
            $source = Get-AllocationVersion (Get-ClaimModVersion $RepoRoot $Mod)
            $floor = (Get-AllocationVersion $state.Floor).Number
            $basis = if ($source.Number -gt $floor) { $source.Number } else { $floor }
            if ($basis.Build -eq [int]::MaxValue) { throw 'Allocation patch exhausted.' }
            $next = '{0}.{1}.{2}' -f $basis.Major,$basis.Minor,($basis.Build+1)
            $version = $next + $source.Suffix
            $claimRaw = Format-ClaimContent $Mod $version $Session $NowUtc
            $reservation = Format-AllocationState $Mod $next 'active' $claimRaw $state.Review
            # Burn first. Failure/crash after here can waste a number, never
            # authorize reusing it. No stale timestamp renewal is implemented.
            Write-AllocationState $paths.State $state.Raw $reservation
            $stream = [IO.File]::Open($paths.Claim,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try {
                $bytes = [Text.Encoding]::UTF8.GetBytes($claimRaw)
                $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true)
            } finally { $stream.Dispose() }
            $locked = Open-AllocationClaim $paths.Claim
            if (-not $locked -or $locked.Raw -cne $claimRaw) { throw 'Claim changed after allocation; floor retained, reconciliation required.' }
            return @{Ok=$true;Acquired=$true;Version=$version;Held=$null;ClaimPath=$paths.Claim;BrokeStale=[bool]$stale;Message='claimed above permanent floor'}
        } finally { if ($locked) { $locked.Stream.Dispose() } }
    }
}
