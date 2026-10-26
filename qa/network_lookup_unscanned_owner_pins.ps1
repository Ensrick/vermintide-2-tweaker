# Narrow #428 supplemental inventory; NOT a general Lua alias/scope detector.
# Source-only QA. All functions are process-side-effect-free except file reads.
function Get-KnownLookupStrictUtf8Text {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "pinned source missing: $Path" }
    $decoder = New-Object System.Text.UTF8Encoding($false, $true)
    return $decoder.GetString([IO.File]::ReadAllBytes($Path))
}

function Assert-KnownLookupKeys {
    param([Parameter(Mandatory=$true)][hashtable]$Value, [string[]]$Expected, [string]$Context)
    # Dot-property access is unsafe here: a data key named Keys shadows it.
    # Invoke the CLR getter so even Keys/get_Keys/PSBase metadata is inspected.
    $actualKeys = @($Value.get_Keys())
    if ($actualKeys.Count -ne $Expected.Count) { throw "$Context schema fields differ" }
    foreach ($key in $actualKeys) {
        if ($key -isnot [string] -or $key -cnotin $Expected) { throw "$Context unknown schema field: $key" }
    }
}

function Assert-KnownUnscannedLookupOwners {
    param([Parameter(Mandatory=$true)][string]$RepoRoot, [Parameter(Mandatory=$true)][string]$InventoryPath)
    # Safe data-file import rejects executable expressions and duplicate keys.
    # Decode first with throwing UTF-8, independent of PS5's text-file defaults.
    $inventoryText = Get-KnownLookupStrictUtf8Text -Path $InventoryPath
    if ([string]::IsNullOrWhiteSpace($inventoryText)) { throw 'supplemental inventory is empty' }
    $inventory = Import-PowerShellDataFile -LiteralPath $InventoryPath
    if ($inventory -isnot [hashtable]) { throw 'supplemental inventory must be a data table' }
    Assert-KnownLookupKeys -Value $inventory -Expected @('schema','issue','coverage','rows') -Context 'supplemental inventory'
    if ($inventory.schema -isnot [int] -or $inventory.schema -ne 1 -or
            $inventory.issue -isnot [int] -or $inventory.issue -ne 428 -or
            $inventory.coverage -cne 'explicit-source-pins-not-complete-census') {
        throw 'supplemental inventory schema/issue/coverage invalid'
    }
    $expected = @(
        'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_runtime.lua',
        'weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_history_runtime.lua'
    )
    if ($inventory.rows -isnot [array] -or $inventory.rows.Count -ne $expected.Count) {
        throw 'supplemental inventory must declare exactly the two reviewed owners'
    }
    $seen = @{}
    $rows = @()
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        foreach ($row in $inventory.rows) {
            if ($row -isnot [hashtable]) { throw 'supplemental owner row must be a data table' }
            Assert-KnownLookupKeys -Value $row -Expected @('path','axis','count','sha256') -Context 'supplemental owner'
            if ($row.path -isnot [string] -or $row.path -cnotin $expected -or
                    $row.axis -isnot [string] -or $row.axis -cne 'damage_profiles' -or
                    $row.count -isnot [int] -or $row.count -ne 1 -or
                    $row.sha256 -isnot [string] -or $row.sha256 -cnotmatch '^[a-f0-9]{64}$') {
                throw 'supplemental owner path/axis/count/hash invalid'
            }
            if ($seen.ContainsKey($row.path)) { throw "supplemental owner duplicated: $($row.path)" }
            $seen[$row.path] = $true
            $sourcePath = Join-Path $RepoRoot $row.path
            $text = (Get-KnownLookupStrictUtf8Text -Path $sourcePath).Replace("`r`n", "`n")
            $bytes = [Text.Encoding]::UTF8.GetBytes($text)
            $digest = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
            if ($digest -cne $row.sha256) {
                throw "pinned unscanned owner source drift: $($row.path); requires explicit source review, not an automatic pin refresh"
            }
            $rows += [pscustomobject]@{ Path=$row.path; Axis=$row.axis; Count=$row.count; Bytes=$bytes.Length; Sha256=$digest }
        }
    }
    finally { $sha.Dispose() }
    return [pscustomobject]@{ Count=2; Rows=$rows; Complete=$false }
}
