# check_versions.ps1 — verifies MOD_VERSION constants + cfg metadata sync.
# Catches: missing MOD_VERSION constant, cfg title/leading description banner
# doesn't match the current MOD_VERSION, CHANGELOG entry missing for current
# version.
#
# See qa/CHECKS.md rows 10, 11, 51.
#
# Exit codes: 0 = pass, 1 = warnings only, 2 = errors found.

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$errors = @()
$warnings = @()

# Frozen exact triplets found by the 2026-07-17 repository-wide census. These
# preserve unrelated, user-authored Workshop metadata while making the baseline
# a ratchet: changing either MOD_VERSION or the stale banner invalidates the
# triplet and fails until both surfaces agree. Do not add new debt here.
$descriptionVersionDebt = @{
    "chaos_wastes_tweaker"       = "0.7.131-beta|0.7.119-dev"
    "crafting_in_modded"         = "0.8.34|0.8.33"
    "dynamic_cosmetic_portraits" = "0.1.25-dev|0.1.13"
}

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

function Get-DescriptionBannerVersion([string]$cfgText) {
    $match = [regex]::Match(
        $cfgText,
        'description\s*=\s*"\[b\][^"\\]*?\sv(?<bannerVersion>\d+(?:\.\d+){1,3}(?:-[A-Za-z0-9+.-]+)?)\[/b\]')
    if ($match.Success) {
        return $match.Groups['bannerVersion'].Value
    }
    return $null
}

function Test-DescriptionVersionMatch([string]$expectedVersion, [string]$cfgText) {
    $bannerVersion = Get-DescriptionBannerVersion $cfgText
    return $null -eq $bannerVersion -or $bannerVersion -eq $expectedVersion
}

if ($SelfTest) {
    $stale = 'description = "[b]Version Probe v1.2.2-dev[/b]\nProbe";'
    $matching = 'description = "[b]Version Probe v1.2.3-dev[/b]\nProbe";'
    $unversioned = 'description = "Probe";'
    if (Test-DescriptionVersionMatch "1.2.3-dev" $stale) {
        throw "planted description-version mismatch was not rejected"
    }
    if (-not (Test-DescriptionVersionMatch "1.2.3-dev" $matching)) {
        throw "matching description version did not pass"
    }
    if (-not (Test-DescriptionVersionMatch "1.2.3-dev" $unversioned)) {
        throw "optional unversioned description did not pass"
    }
    Write-Host "[check_versions] SELF-TEST PASS — planted banner drift rejected; matching and unversioned descriptions accepted." -ForegroundColor Green
    exit 0
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

    # Row #10a (issue #429): flag 4-segment versions instead of silently
    # stripping the 4th. Semver is 3-segment MAJOR.MINOR.PATCH[-track]; a 4th
    # numeric segment (e.g. 0.9.9.4-dev) is the retired within-patch-hotfix
    # anti-pattern — normalize on the next bump per CLAUDE.md §"Version bumping".
    if ($rawVersion -match '^\d+\.\d+\.\d+\.\d+') {
        $warnings += "${modName}: MOD_VERSION '$rawVersion' has 4 numeric segments; use 3-segment semver (MAJOR.MINOR.PATCH[-track]) — bump PATCH, drop the 4th (CLAUDE.md §Version bumping)"
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

        # Optional tester-visible leading banner. When present, it is another
        # version surface and must agree with the cfg title / MOD_VERSION.
        # Require whitespace + v + digit so names such as "Weapon Variants" do
        # not get mistaken for the version marker.
        $bannerVersion = Get-DescriptionBannerVersion $cfgText
        if ($null -ne $bannerVersion) {
            if ($bannerVersion -ne $strippedVersion) {
                $debtSignature = "$strippedVersion|$bannerVersion"
                if ($descriptionVersionDebt[$modName] -eq $debtSignature) {
                    if (-not $Quiet) {
                        Write-Host "  known description-version debt: $modName $debtSignature" -ForegroundColor DarkGray
                    }
                } else {
                    $errors += "${modName}: cfg description banner says v$bannerVersion but MOD_VERSION is '$rawVersion' (expected v$strippedVersion)"
                }
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
    Write-Host "[check_versions] OK — all mods have valid MOD_VERSION and synced cfg version surfaces." -ForegroundColor Green
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
