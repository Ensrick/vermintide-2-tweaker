# check_loc_description_titles.ps1 -- block tooltip/description bodies that
# restate their own localized title (#222).
#
# VMF and Mod Tweaker already render the option title as the popup/header. The
# localized tooltip/description body must start with behavior, not repeat the
# title again. This catches simple sibling pairs:
#   setting_id              = { en = "Title" }
#   setting_id_tooltip      = { en = "Title: body..." }  # ERROR
#   setting_id_description  = { en = "Title body..." }   # ERROR
#
# Exit codes: 0 clean, 2 violation/tool failure. Findings are blocking.

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

# Split stable streams are write-by-promotion-only. These exact legacy GUT
# stable strings are frozen debt until the cleaned gui_tweaker_dev copy is
# verified and promoted; exact text matching prevents new debt from slipping in.
$script:stableBodyDebt = @{
    'gui_tweaker/scripts/mods/gui_tweaker/gui_tweaker_localization.lua' = @(
        'hide_levels_tooltip = { en = "Hide player levels." },',
        'hide_frames_tooltip = { en = "Hide portrait frames." },'
    )
}

function Test-StableBodyDebt([string]$Relative, [string]$Key) {
    $relativeKey = $Relative.Replace('\', '/')
    $allowed = $script:stableBodyDebt[$relativeKey]
    return $null -ne $allowed -and ($allowed | Where-Object { $_ -match "^\s*$([regex]::Escape($Key))\s*=" }).Count -gt 0
}

function Get-ActiveLocalizationFiles {
    foreach ($dir in Get-ChildItem $repoRoot -Directory) {
        if ($dir.Name -eq 'tweaker' -or $dir.Name.StartsWith('_')) { continue }
        $scripts = Join-Path $dir.FullName 'scripts\mods'
        if (Test-Path $scripts) {
            Get-ChildItem $scripts -Recurse -File -Filter '*_localization.lua'
        }
    }
}

function ConvertFrom-LuaEscapedString([string]$Value) {
    return $Value.Replace('\"', '"').Replace('\\', '\')
}

function Normalize-ComparisonText([string]$Value) {
    if ($null -eq $Value) { return '' }
    $normalized = [regex]::Replace($Value, '^\s*\[[^\]]+\]\s*', '')
    $normalized = [regex]::Replace($normalized, '\([^)]*\)', '')
    $normalized = [regex]::Replace($normalized, '[^A-Za-z0-9 ]', ' ')
    $normalized = [regex]::Replace($normalized, '\s+', ' ')
    return $normalized.Trim().ToLowerInvariant()
}

function Get-EnglishLocalizationMap([string]$Source) {
    $map = @{}
    $pattern = '(?ms)^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{\s*en\s*=\s*"(?<value>(?:\\.|[^"\\])*)"\s*,?\s*\}'
    foreach ($match in [regex]::Matches($Source, $pattern)) {
        $map[$match.Groups['key'].Value] = ConvertFrom-LuaEscapedString $match.Groups['value'].Value
    }
    return $map
}

function Find-RepeatedTitleBodies([System.IO.FileInfo[]]$Files) {
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $Files) {
        $relative = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $source = [IO.File]::ReadAllText($file.FullName)
        $map = Get-EnglishLocalizationMap $source
        foreach ($key in $map.Keys) {
            if ($key -eq 'mod_description') { continue }
            if ($key -notmatch '^(?<base>.+?)_(?:tooltip|description)$') { continue }
            $base = $Matches['base']
            if (-not $map.ContainsKey($base)) { continue }

            $title = Normalize-ComparisonText $map[$base]
            $body = Normalize-ComparisonText $map[$key]
            if ($title.Length -lt 4 -or $body.Length -lt 4) { continue }

            if (($body -eq $title -or $body.StartsWith($title + ' ')) -and
                    -not (Test-StableBodyDebt $relative $key)) {
                $findings.Add([pscustomobject]@{
                    File = $relative
                    Key = $key
                    Title = $map[$base]
                    Body = $map[$key]
                })
            }
        }
    }
    return $findings
}

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "self-test failed: $Message" }
}

if ($SelfTest) {
    try {
        $source = @'
local localization = {
    good = { en = "Dark Preview" },
    good_tooltip = { en = "Makes the preview darker." },
    bad = { en = "Dark Preview" },
    bad_tooltip = { en = "Dark Preview: makes the preview darker." },
    paren = { en = "Axe Nerf (WT)" },
    paren_description = { en = "Axe Nerf reduces cleave." },
    mod_description = { en = "Tweaker: X" },
}
'@
        $temp = [IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllText($temp, $source)
            $file = [IO.FileInfo]::new($temp)
            $findings = @(Find-RepeatedTitleBodies @($file))
            Assert ($findings.Count -eq 2) 'expected bad tooltip and paren description only'
            Assert (($findings | Where-Object Key -eq 'bad_tooltip').Count -eq 1) 'bad_tooltip missing'
            Assert (($findings | Where-Object Key -eq 'paren_description').Count -eq 1) 'paren_description missing'
        } finally {
            if (Test-Path $temp) { Remove-Item -LiteralPath $temp }
        }
        Write-Host '[check_loc_description_titles] SELF-TEST OK' -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "[check_loc_description_titles] SELF-TEST FAILED -- $_" -ForegroundColor Red
        exit 2
    }
}

try {
    $findings = @(Find-RepeatedTitleBodies @(Get-ActiveLocalizationFiles))
} catch {
    Write-Host "[check_loc_description_titles] ERROR -- $_" -ForegroundColor Red
    exit 2
}

if ($findings.Count -gt 0) {
    Write-Host "[check_loc_description_titles] ERROR -- $($findings.Count) tooltip/description bodies repeat their title." -ForegroundColor Red
    foreach ($finding in $findings) {
        Write-Host ("{0}: {1} repeats title '{2}'" -f $finding.File, $finding.Key, $finding.Title) -ForegroundColor Red
        if (-not $Quiet) {
            Write-Host ("  body: {0}" -f $finding.Body) -ForegroundColor DarkRed
        }
    }
    exit 2
}

if (-not $Quiet) {
    Write-Host '[check_loc_description_titles] OK: no tooltip/description body starts by repeating its title.' -ForegroundColor Green
}
exit 0
