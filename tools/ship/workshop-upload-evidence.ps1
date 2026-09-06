# Read-only, bounded evidence for one canonical launcher upload. The machine
# transaction lease supplies cooperative serialization; plaintext Steam logs do
# not supply an authenticated receipt, process nonce, or durable content tuple.
if (-not (Get-Command Get-VtBundleOutputHandleProof -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'bundle-output-set.ps1')
}

function Assert-VtWorkshopEvidenceId {
    param([string]$Value)
    [uint64]$number = 0
    if ($Value -cnotmatch '\A[1-9][0-9]*\z' -or
        -not [uint64]::TryParse($Value, [ref]$number)) {
        throw 'Workshop evidence requires a canonical positive UInt64 ID.'
    }
}

function Open-VtWorkshopEvidenceStream {
    param([string]$Path)
    # Buffer size 1 prevents a second continuity read from using cached bytes.
    return [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete),
        1, [System.IO.FileOptions]::None)
}

function Get-VtWorkshopEvidencePrefix {
    param([System.IO.FileStream]$Stream, [long]$Count)
    if ($Count -lt 0 -or $Count -gt 16777216) { throw 'Workshop log prefix exceeds the 16 MiB evidence budget.' }
    $null = $Stream.Seek(0, [System.IO.SeekOrigin]::Begin)
    $hash = [System.Security.Cryptography.SHA256]::Create()
    try {
        $buffer = [byte[]]::new(65536)
        $remaining = $Count
        $last = -1
        while ($remaining -gt 0) {
            $read = $Stream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $remaining))
            if ($read -le 0) { throw 'Workshop log was truncated during prefix verification.' }
            $null = $hash.TransformBlock($buffer, 0, $read, $buffer, 0)
            $last = [int]$buffer[$read - 1]
            $remaining -= $read
        }
        $null = $hash.TransformFinalBlock([byte[]]::new(0), 0, 0)
        return [pscustomobject]@{ Digest = [Convert]::ToBase64String($hash.Hash); Last = $last }
    }
    finally { $hash.Dispose() }
}

function Start-VtWorkshopUploadEvidence {
    param([Parameter(Mandatory)][string]$Path)
    $stream = Open-VtWorkshopEvidenceStream -Path $Path
    try {
        $proof = Get-VtBundleOutputHandleProof -Stream $stream
        $prefix = Get-VtWorkshopEvidencePrefix -Stream $stream -Count $proof.Length
        if ($proof.Length -gt 0 -and $prefix.Last -ne 10) {
            throw 'Workshop evidence boundary is not a complete log line.'
        }
        $after = Get-VtBundleOutputHandleProof -Stream $stream
        if ($after.Identity -cne $proof.Identity -or $after.Length -ne $proof.Length) {
            throw 'Workshop log changed during boundary capture.'
        }
        $pathStream = Open-VtWorkshopEvidenceStream -Path $Path
        try {
            $pathProof = Get-VtBundleOutputHandleProof -Stream $pathStream
            if ($pathProof.Identity -cne $proof.Identity -or $pathProof.Length -ne $proof.Length) {
                throw 'Workshop log rotated during boundary capture.'
            }
        }
        finally { $pathStream.Dispose() }
        return [pscustomobject]@{
            Path = [System.IO.Path]::GetFullPath($Path); Stream = $stream
            Identity = $proof.Identity; Boundary = $proof.Length; Prefix = $prefix.Digest
            StartedAt = [datetime]::Now
        }
    }
    catch { $stream.Dispose(); throw }
}

function Read-VtWorkshopEvidenceAppend {
    param([System.IO.FileStream]$Stream, [long]$Boundary, [long]$End)
    $count = $End - $Boundary
    if ($count -le 0 -or $count -gt 1048576) { throw 'Workshop append is empty, truncated, or exceeds the 1 MiB evidence budget.' }
    $bytes = [byte[]]::new([int]$count)
    $null = $Stream.Seek($Boundary, [System.IO.SeekOrigin]::Begin)
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -le 0) { throw 'Workshop log was truncated during append verification.' }
        $offset += $read
    }
    if ($bytes[$bytes.Length - 1] -ne 10) { throw 'Workshop append ends with an incomplete log line.' }
    return ,$bytes
}

function ConvertFrom-VtWorkshopUploadTransaction {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$PublishedId, [datetime]$StartedAt, [datetime]$EndedAt)
    Assert-VtWorkshopEvidenceId -Value $PublishedId
    if ($EndedAt -lt $StartedAt) { throw 'Workshop evidence clock moved backwards.' }
    $start = $StartedAt.AddTicks(-($StartedAt.Ticks % [TimeSpan]::TicksPerSecond))
    $end = $EndedAt.AddTicks(-($EndedAt.Ticks % [TimeSpan]::TicksPerSecond))
    if ($Text.Length -gt 1048576 -or -not $Text.EndsWith("`n")) { throw 'Workshop transaction text is incomplete or oversized.' }
    $state = 0
    $status = $null
    $manifest = $null
    $outcomeLine = $null
    $finishLine = $null
    $previousTime = $start
    foreach ($raw in $Text.Split([char]10)) {
        $line = if ($raw.EndsWith("`r")) { $raw.Substring(0, $raw.Length - 1) } else { $raw }
        if ($line.Length -gt 8192) { throw 'Workshop log line exceeds the 8 KiB evidence budget.' }
        # Unrelated interleaving is allowed, but an event naming this exact item
        # must satisfy the closed grammar. Substrings/ManifestIDs are not item IDs.
        if ($line -notmatch ('(?:workshop item|for item)\s+[+-]?0*' + $PublishedId + '(?![0-9])')) { continue }
        if ($line.Contains("`r") -or $line -cnotmatch '\A\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\] \[AppID 552500\] (.*)\z') {
            throw 'Malformed or wrong-AppID Workshop event for the target item.'
        }
        $stampText = $matches[1]
        $message = $matches[2]
        try { $stamp = [datetime]::ParseExact($stampText, 'yyyy-MM-dd HH:mm:ss', [cultureinfo]::InvariantCulture) }
        catch { throw 'Malformed Workshop event timestamp.' }
        if ($stamp -lt $start -or $stamp -gt $end -or $stamp -lt $previousTime) {
            throw 'Workshop event is outside the observed upload interval or out of order.'
        }
        $previousTime = $stamp
        if ($message -ceq "Upload starting for workshop item $PublishedId by AppID 552500") {
            if ($state -ne 0) { throw 'Duplicate or retried Workshop upload start.' }
            $state = 1
        }
        elseif ($message -cmatch ('\AUploaded new content \( ManifestID ([1-9][0-9]*) \) for item ' + $PublishedId + '\.\z')) {
            if ($state -ne 1) { throw 'Duplicate or out-of-order Workshop content outcome.' }
            $manifest = $matches[1]
            Assert-VtWorkshopEvidenceId -Value $manifest
            $status = 'UPLOADED'; $outcomeLine = $line; $state = 2
        }
        elseif ($message -ceq "No content change detected for item $PublishedId") {
            if ($state -ne 1) { throw 'Duplicate or mixed Workshop content outcomes.' }
            $status = 'NOCHANGE'; $outcomeLine = $line; $state = 2
        }
        elseif ($message -ceq "Upload finished for workshop item $PublishedId : OK") {
            if ($state -ne 2) { throw 'Workshop finish has no unique preceding content outcome.' }
            $finishLine = $line; $state = 3
        }
        else { throw 'Workshop target event is malformed or reports an unsuccessful upload.' }
    }
    if ($state -ne 3) { throw 'No complete unique start/content/finish-OK Workshop transaction.' }
    return [pscustomobject]@{ Status = $status; ManifestId = $manifest; PublishedId = $PublishedId; OutcomeLine = $outcomeLine; FinishLine = $finishLine }
}

function Complete-VtWorkshopUploadEvidence {
    param([Parameter(Mandatory)]$Capture, [string]$PublishedId, [datetime]$EndedAt)
    $stream = $Capture.Stream
    $proof = Get-VtBundleOutputHandleProof -Stream $stream
    if ($proof.Identity -cne $Capture.Identity -or $proof.Length -lt $Capture.Boundary) { throw 'Workshop log identity changed or was truncated.' }
    $prefix = Get-VtWorkshopEvidencePrefix -Stream $stream -Count $Capture.Boundary
    if ($prefix.Digest -cne $Capture.Prefix) { throw 'Workshop log prefix was rewritten or truncated and regrown.' }
    $bytes = Read-VtWorkshopEvidenceAppend -Stream $stream -Boundary $Capture.Boundary -End $proof.Length
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $result = ConvertFrom-VtWorkshopUploadTransaction -Text $text -PublishedId $PublishedId -StartedAt $Capture.StartedAt -EndedAt $EndedAt
    # Repeat uncached bounded reads before accepting; rotation is permitted by
    # the observer's sharing flags but never supplies evidence for this attempt.
    $prefixAgain = Get-VtWorkshopEvidencePrefix -Stream $stream -Count $Capture.Boundary
    $bytesAgain = Read-VtWorkshopEvidenceAppend -Stream $stream -Boundary $Capture.Boundary -End $proof.Length
    if ($prefixAgain.Digest -cne $Capture.Prefix -or [Convert]::ToBase64String($bytes) -cne [Convert]::ToBase64String($bytesAgain)) {
        throw 'Workshop evidence changed during verification.'
    }
    $pathStream = Open-VtWorkshopEvidenceStream -Path $Capture.Path
    try {
        $current = Get-VtBundleOutputHandleProof -Stream $pathStream
        if ($current.Identity -cne $Capture.Identity -or $current.Length -ne $proof.Length) { throw 'Workshop log rotated or changed during verification.' }
    }
    finally { $pathStream.Dispose() }
    return $result
}

function Invoke-VtWorkshopUploadEvidence {
    param([string]$Path, [string]$PublishedId,
        [Parameter(Mandatory)][scriptblock]$UploadAction,
        [scriptblock]$ResolveBootstrapId)
    $bootstrap = $PublishedId -ceq '0'
    if (-not $bootstrap) { Assert-VtWorkshopEvidenceId -Value $PublishedId }
    if ($bootstrap -and -not $ResolveBootstrapId) { throw 'Bootstrap upload requires an explicit assigned-ID resolver.' }
    if (-not $bootstrap -and $ResolveBootstrapId) { throw 'Assigned-ID resolver is only valid for bootstrap.' }
    $capture = Start-VtWorkshopUploadEvidence -Path $Path
    try {
        $null = & $UploadAction
        $ended = [datetime]::Now
        if ($bootstrap) { $PublishedId = [string](& $ResolveBootstrapId) }
        Assert-VtWorkshopEvidenceId -Value $PublishedId
        return Complete-VtWorkshopUploadEvidence -Capture $capture -PublishedId $PublishedId -EndedAt $ended
    }
    finally { $capture.Stream.Dispose() }
}
