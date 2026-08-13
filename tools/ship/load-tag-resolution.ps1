# tools/ship/load-tag-resolution.ps1
#
# Shared, offline runtime LOAD-tag discovery for canonical shipping and the
# post-upload CURRENT LIVE TEST card inventory. The literal marker in the main
# Lua file is authoritative when present. Otherwise every root-level *.lua file
# participates; one unique helper-owned marker wins, conflicts fail closed, and
# a caller-provided fallback is considered only when no literal marker exists.
# Keep this file byte-ASCII: ship tooling runs under Windows PowerShell 5.1.

function Get-VtLiteralLoadTags {
    param([AllowNull()][string[]]$Texts)

    $tags = @()
    foreach ($text in @($Texts)) {
        if ([string]::IsNullOrEmpty($text)) { continue }
        foreach ($match in [regex]::Matches($text, '\[([A-Za-z][A-Za-z0-9_-]*):LOAD\]')) {
            $tag = $match.Groups[1].Value
            # Runtime/card anchors are literal and case-sensitive. Do not fold
            # [cim:LOAD] and [CIM:LOAD] into one guessed spelling.
            if (-not ($tags -ccontains $tag)) { $tags += $tag }
        }
    }

    return @($tags)
}

function New-VtLoadTagResolution {
    param(
        [bool]$Success,
        [string]$LoadTag,
        [string]$Source,
        [string]$Reason,
        [string[]]$Candidates
    )

    return [pscustomobject]@{
        Success = $Success
        LoadTag = $LoadTag
        Source = $Source
        Reason = $Reason
        Candidates = @($Candidates)
    }
}

function Resolve-VtLoadTag {
    param(
        [AllowNull()][string]$MainLuaText,
        [AllowNull()][string[]]$LuaTexts,
        [AllowNull()][string]$FallbackTag
    )

    $mainTags = @(Get-VtLiteralLoadTags -Texts @($MainLuaText))
    if ($mainTags.Count -gt 1) {
        return New-VtLoadTagResolution -Success $false -Source 'main-conflict' `
            -Reason ('main Lua contains conflicting literal LOAD tags: ' + ($mainTags -join ', ')) `
            -Candidates $mainTags
    }
    if ($mainTags.Count -eq 1) {
        return New-VtLoadTagResolution -Success $true -LoadTag $mainTags[0] `
            -Source 'main' -Reason 'resolved from the main Lua marker' -Candidates $mainTags
    }

    $rootTags = @(Get-VtLiteralLoadTags -Texts $LuaTexts)
    if ($rootTags.Count -gt 1) {
        return New-VtLoadTagResolution -Success $false -Source 'root-conflict' `
            -Reason ('Lua root contains conflicting literal LOAD tags: ' + ($rootTags -join ', ')) `
            -Candidates $rootTags
    }
    if ($rootTags.Count -eq 1) {
        return New-VtLoadTagResolution -Success $true -LoadTag $rootTags[0] `
            -Source 'lua-root' -Reason 'resolved from the only root Lua marker' -Candidates $rootTags
    }

    if (-not [string]::IsNullOrWhiteSpace($FallbackTag)) {
        return New-VtLoadTagResolution -Success $true -LoadTag $FallbackTag `
            -Source 'fallback' -Reason 'no literal LOAD marker exists; caller fallback used' -Candidates @()
    }

    return New-VtLoadTagResolution -Success $false -Source 'missing' `
        -Reason 'no literal LOAD marker exists and no fallback was supplied' -Candidates @()
}

function Get-VtLoadTagResolution {
    param(
        [string]$MainLuaPath,
        [string]$LuaRoot,
        [AllowNull()][string]$FallbackTag
    )

    $mainLuaText = $null
    if (Test-Path -LiteralPath $MainLuaPath -PathType Leaf) {
        $mainLuaText = [System.IO.File]::ReadAllText($MainLuaPath, [System.Text.Encoding]::UTF8)
    }

    $luaTexts = @()
    if (Test-Path -LiteralPath $LuaRoot -PathType Container) {
        # Compiled inputs can carry the Windows Hidden attribute. They remain
        # part of the authored root and must participate in conflict detection.
        foreach ($luaFile in @(Get-ChildItem -LiteralPath $LuaRoot -Filter '*.lua' -File -Force | Sort-Object FullName)) {
            $luaTexts += [System.IO.File]::ReadAllText($luaFile.FullName, [System.Text.Encoding]::UTF8)
        }
    }

    return Resolve-VtLoadTag -MainLuaText $mainLuaText -LuaTexts $luaTexts -FallbackTag $FallbackTag
}
