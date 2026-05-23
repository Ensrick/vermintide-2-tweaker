# check_versions.ps1 — verifies MOD_VERSION constants + cfg title version sync.
# Catches: missing MOD_VERSION constant, cfg title doesn't include current
# MOD_VERSION suffix, CHANGELOG entry missing for current version.
#
# See qa/CHECKS.md rows 10, 11, 51.
#
# Exit codes: 0 = pass, 1 = warnings only, 2 = errors found.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$errors = @()
$warnings = @()

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Find-ModLuas {
    # Each mod has its main lua at <mod>/scripts/mods/<mod>/<mod>.lua per VMB layout.
    # Skip reference materials, archived legacy mods, sample mods.
    Get-ChildItem -Path $repoRoot -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $name = $_.BaseName
            $parent = (Split-Path $p -Parent | Split-Path -Leaf)
            $isMainFile = ($name -eq $parent)
            $isInModsScripts = $p -match "\\scripts\\mods\\$name\\"
            $notExcluded = $p -notlike "*\_archive\*" `
                       -and $p -notlike "*\bundleV2\*" `
                       -and $p -notlike "*\.build\*" `
                       -and $p -notlike "*\.temp\*" `
                       -and $p -notlike "*\.spawn_tweaks_ref\*" `
                       -and $p -notlike "*\tweaker\*" `
                       -and $p -notlike "*\sample_*\*" `
                       -and $p -notlike "*\Helpers*"
            return $isMainFile -and $isInModsScripts -and $notExcluded
        }
}

# Strip non-stage descriptive suffixes; keep stage tags (alpha, beta, dev, rc).
# "0.9.9.1-la-icons" -> "0.9.9.1"
# "0.9.9.1-alpha"    -> "0.9.9.1-alpha"  (alpha is a stage)
# "0.7.83-hotfix"    -> "0.7.83"
function Get-StrippedVersion([string]$rawVersion) {
    if ($rawVersion -match '^(\d+\.\d+(?:\.\d+(?:\.\d+)?)?)(-(?:alpha|beta|dev|rc)\d*)?(-[A-Za-z0-9+.-]+)?$') {
        $stage = if ($matches[2]) { $matches[2] } else { "" }
        return $matches[1] + $stage
    }
    return $rawVersion
}

foreach ($modLua in Find-ModLuas) {
    $modName = $modLua.BaseName
    $luaText = Read-FileUtf8 $modLua.FullName
    if (-not $Quiet) { Write-Host "Checking $modName" -ForegroundColor DarkGray }

    # Row #10: MOD_VERSION constant must exist
    $rawVersion = $null
    if ($luaText -match 'MOD_VERSION\s*=\s*"([^"]+)"') {
        $rawVersion = $matches[1]
    } else {
        $errors += "${modName}: no MOD_VERSION constant found in $modName.lua (PROJECT_STANDARDS §6.1)"
        continue
    }

    $strippedVersion = Get-StrippedVersion $rawVersion

    # Row #11: cfg title should include current version
    $cfgPath = Join-Path (Split-Path $modLua.FullName -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent) "itemV2.cfg"
    if (Test-Path $cfgPath) {
        $cfgText = Read-FileUtf8 $cfgPath
        if ($cfgText -match 'title\s*=\s*"([^"]+)"') {
            $cfgTitle = $matches[1]
            # Should end with " v<stripped_version>"
            $expectedSuffix = " v$strippedVersion"
            if ($cfgTitle -notmatch [regex]::Escape($expectedSuffix) + "(\s|$)") {
                $warnings += "${modName}: cfg title '$cfgTitle' should include suffix '$expectedSuffix' (lua MOD_VERSION='$rawVersion')"
            }
        }
    }

    # Row #51: CHANGELOG entry must exist for current MOD_VERSION.
    # CHANGELOG.md is at the MOD ROOT, not inside scripts/. Walk up 3 levels from
    # <mod>/scripts/mods/<mod>/<mod>.lua to find the mod root.
    $changelogPath = Join-Path (Split-Path $modLua.FullName -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent) "CHANGELOG.md"
    if (Test-Path $changelogPath) {
        $changelogText = Read-FileUtf8 $changelogPath
        # Just check the raw version literal appears somewhere reasonable
        # (different mods use slightly different header formats; lenient scan).
        if ($changelogText -notmatch [regex]::Escape($rawVersion)) {
            $warnings += "${modName}: CHANGELOG.md has no entry mentioning v$rawVersion"
        }
    } else {
        $warnings += "${modName}: no CHANGELOG.md at $changelogPath"
    }
}

# Report
Write-Host ""
if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "[check_versions] OK — all mods have valid MOD_VERSION and synced cfg titles." -ForegroundColor Green
    exit 0
}

if ($warnings.Count -gt 0) {
    Write-Host "[check_versions] WARNINGS:" -ForegroundColor Yellow
    foreach ($w in $warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
}
if ($errors.Count -gt 0) {
    Write-Host "[check_versions] ERRORS:" -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "  X $e" -ForegroundColor Red }
    exit 2
}
exit 1
