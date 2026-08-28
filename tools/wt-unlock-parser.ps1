# Shared, source-only parser for Weapon Tweaker's documented weapon-key
# registry and weapon_unlock_map. Both QA and generated documentation consume
# this exact grammar so a symbolic data refactor cannot silently disappear from
# one tooling surface.

function Read-VtWtUtf8 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Remove-VtWtLuaComments {
    param([Parameter(Mandatory = $true)][string]$Text)
    $withoutBlocks = [regex]::Replace(
        $Text,
        '--\[\[.*?\]\]',
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    return [regex]::Replace($withoutBlocks, '--[^\r\n]*', '')
}

function Get-VtWtDocumentedKeyRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowMissing
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) { return [ordered]@{} }
        throw "Weapon-key registry not found: $Path"
    }

    $text = Remove-VtWtLuaComments -Text (Read-VtWtUtf8 -Path $Path)
    $tableMatch = [regex]::Match(
        $text,
        'return\s*\{(.*)\}\s*$',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $tableMatch.Success) {
        throw "Weapon-key registry must be one return { ... } table: $Path"
    }

    $registry = [ordered]@{}
    $valueOwners = @{}
    $assignmentPattern = '^([A-Z][A-Z0-9_]*)\s*=\s*"([a-z]{2}_[a-z0-9_]+)"\s*,?$'

    foreach ($line in ($tableMatch.Groups[1].Value -split '\r?\n')) {
        $trimmed = $line.Trim()
        if (-not $trimmed) { continue }
        $match = [regex]::Match($trimmed, $assignmentPattern)
        if (-not $match.Success) {
            throw "Malformed documented weapon-key declaration '$trimmed' in $Path"
        }
        $symbol = $match.Groups[1].Value
        $weaponKey = $match.Groups[2].Value
        if ($registry.Contains($symbol)) {
            throw "Duplicate documented weapon-key symbol '$symbol' in $Path"
        }
        if ($valueOwners.ContainsKey($weaponKey)) {
            throw "Documented weapon key '$weaponKey' is assigned to both '$($valueOwners[$weaponKey])' and '$symbol' in $Path"
        }
        $registry[$symbol] = $weaponKey
        $valueOwners[$weaponKey] = $symbol
    }

    if ($registry.Count -eq 0) {
        throw "Weapon-key registry contains no valid SYMBOL = `"engine_key`" rows: $Path"
    }
    return $registry
}

function Resolve-VtWtWeaponToken {
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $literal = [regex]::Match($Token, '^"([a-z]{2}_[a-z0-9_]+)"$')
    if ($literal.Success) { return $literal.Groups[1].Value }

    $symbol = [regex]::Match($Token, '^W\.([A-Za-z_][A-Za-z0-9_]*)$')
    if (-not $symbol.Success) {
        throw "Unsupported weapon-key token '$Token' in $Context"
    }
    $name = $symbol.Groups[1].Value
    if (-not $Registry.Contains($name)) {
        throw "Unknown documented weapon-key symbol 'W.$name' in $Context"
    }
    return $Registry[$name]
}

function Get-VtWtWeaponTokens {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)]$Registry,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $keys = @()
    foreach ($part in ($Text -split ',')) {
        $token = $part.Trim()
        if (-not $token) { continue }
        $keys += Resolve-VtWtWeaponToken -Token $token -Registry $Registry -Context $Context
    }
    return $keys
}

function Get-VtWtUnlockMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UnlockPath,
        [string]$RegistryPath = (Join-Path (Split-Path -Parent $UnlockPath) 'wt_documented_keys.lua')
    )

    $text = Remove-VtWtLuaComments -Text (Read-VtWtUtf8 -Path $UnlockPath)
    $hasSymbols = $text -match '(?<![A-Za-z0-9_])W\.[A-Za-z_]'
    $registry = Get-VtWtDocumentedKeyRegistry -Path $RegistryPath -AllowMissing:(-not $hasSymbols)
    $map = [ordered]@{}

    if ($text -match '(?<![A-Za-z0-9_])W\s*\[') {
        throw "Unsupported bracket access on documented weapon-key registry W in $UnlockPath"
    }
    foreach ($symbolMatch in [regex]::Matches($text, '(?<![A-Za-z0-9_])W\.([A-Za-z_][A-Za-z0-9_]*)')) {
        $symbol = $symbolMatch.Groups[1].Value
        if (-not $registry.Contains($symbol)) {
            throw "Unknown documented weapon-key symbol 'W.$symbol' in $UnlockPath"
        }
    }

    $startMatch = [regex]::Match($text, 'weapon_unlock_map\s*=\s*\{')
    if (-not $startMatch.Success) {
        throw "weapon_unlock_map table not found in $UnlockPath"
    }

    $idx = $startMatch.Index + $startMatch.Length
    $depth = 1
    $builder = New-Object System.Text.StringBuilder
    while ($idx -lt $text.Length -and $depth -gt 0) {
        $ch = $text[$idx]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) { break }
        }
        [void]$builder.Append($ch)
        $idx++
    }
    if ($depth -ne 0) {
        throw "Unterminated weapon_unlock_map table in $UnlockPath"
    }

    $block = $builder.ToString()
    foreach ($match in [regex]::Matches($block, '([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{([^{}]*)\}')) {
        $career = $match.Groups[1].Value
        if ($map.Contains($career)) {
            throw "Duplicate weapon_unlock_map career '$career' in $UnlockPath"
        }
        $context = "weapon_unlock_map.$career in $UnlockPath"
        $map[$career] = @(Get-VtWtWeaponTokens -Text $match.Groups[2].Value -Registry $registry -Context $context)
    }
    if ($map.Count -eq 0) {
        throw "weapon_unlock_map contains no career rows in $UnlockPath"
    }

    # Apply the exact idempotent append and removal idioms used by
    # wt_unlock_data.lua so tooling observes the returned DATA graph, not a
    # stale pre-mutation declaration.
    $receiverLoops = [regex]::Matches(
        $text,
        'for\s+_,\s*career\s+in\s+ipairs\s*\(\s*\{([^}]*)\}\s*\)\s*do',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    for ($loopIndex = 0; $loopIndex -lt $receiverLoops.Count; $loopIndex++) {
        $loop = $receiverLoops[$loopIndex]
        $bodyStart = $loop.Index + $loop.Length
        $bodyEnd = if ($loopIndex + 1 -lt $receiverLoops.Count) {
            $receiverLoops[$loopIndex + 1].Index
        } else {
            $text.Length
        }
        $loopBody = $text.Substring($bodyStart, $bodyEnd - $bodyStart)

        $careers = @()
        foreach ($careerMatch in [regex]::Matches($loop.Groups[1].Value, '"([^"]+)"')) {
            $careers += $careerMatch.Groups[1].Value
        }

        if ($loopBody -match 'table\.insert\s*\(\s*weapons\s*,') {
            throw "Unsupported table.insert mutation of weapon_unlock_map in $UnlockPath"
        }

        $appendPrefix = 'weapons\s*\[\s*#weapons\s*\+\s*1\s*\]\s*='
        $appendPattern = $appendPrefix + '\s*("[^"]+"|W\.[A-Za-z_][A-Za-z0-9_]*)'
        $appendCount = [regex]::Matches($loopBody, $appendPrefix).Count
        $appendMatches = [regex]::Matches($loopBody, $appendPattern)
        if ($appendMatches.Count -ne $appendCount) {
            throw "Unsupported post-table weapon-key append in $UnlockPath"
        }
        foreach ($appendMatch in $appendMatches) {
            $addedKey = Resolve-VtWtWeaponToken `
                -Token $appendMatch.Groups[1].Value `
                -Registry $registry `
                -Context "post-table addition in $UnlockPath"
            foreach ($career in $careers) {
                if (-not $map.Contains($career)) { continue }
                if (@($map[$career]) -notcontains $addedKey) {
                    $map[$career] = @($map[$career]) + $addedKey
                }
            }
        }

        if ($loopBody -notmatch 'table\.remove\s*\(\s*weapons\s*,') { continue }

        $removedKeys = @()
        $comparisonPattern = 'weapons\s*\[\s*i\s*\]\s*==\s*("[^"]+"|W\.[A-Za-z_][A-Za-z0-9_]*)'
        $comparisonCount = [regex]::Matches($loopBody, 'weapons\s*\[\s*i\s*\]\s*==').Count
        $keyMatches = [regex]::Matches($loopBody, $comparisonPattern)
        if ($keyMatches.Count -ne $comparisonCount) {
            throw "Unsupported post-table weapon-key comparison in $UnlockPath"
        }
        foreach ($keyMatch in $keyMatches) {
            $removedKeys += Resolve-VtWtWeaponToken `
                -Token $keyMatch.Groups[1].Value `
                -Registry $registry `
                -Context "post-table removal in $UnlockPath"
        }

        foreach ($career in $careers) {
            if (-not $map.Contains($career)) { continue }
            $map[$career] = @($map[$career] | Where-Object { $removedKeys -notcontains $_ })
        }
    }

    return $map
}
