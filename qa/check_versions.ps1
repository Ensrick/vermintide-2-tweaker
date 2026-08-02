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
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = Join-Path $PSScriptRoot ".."
}
$repoRoot = (Resolve-Path $RepoRoot).Path
$errors = @()
$warnings = @()
$releaseIdentityHelpers = Join-Path $repoRoot 'tools\ship\release-identity.ps1'
if (-not (Test-Path -LiteralPath $releaseIdentityHelpers -PathType Leaf)) {
    throw "Release identity helpers not found: $releaseIdentityHelpers"
}
. $releaseIdentityHelpers

# Frozen exact triplets found by the 2026-07-17 repository-wide census. These
# preserve unrelated, user-authored Workshop metadata while making the baseline
# a ratchet: changing either MOD_VERSION or the stale banner invalidates the
# triplet and fails until both surfaces agree. Do not add new debt here.
$descriptionVersionDebt = @{
    "chaos_wastes_tweaker"       = "0.7.131-beta|0.7.119-dev"
    "crafting_in_modded"         = "0.8.34|0.8.33"
    "dynamic_cosmetic_portraits" = "0.1.25-dev|0.1.13"
}

function Try-ReadFileUtf8([string]$path) {
    try {
        return [pscustomobject]@{
            Ok = $true
            Text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        }
    }
    catch [System.IO.FileNotFoundException], [System.IO.DirectoryNotFoundException] {
        # Agent worktrees may be removed between enumeration and this read.
        # That race is not a version defect in the invoking checkout.
        return [pscustomobject]@{ Ok = $false; Text = $null }
    }
}

function Test-ModLuaCandidate([string]$path, [string]$name, [string]$parent) {
    $isMainFile = ($name -eq $parent)
    $isInModsScripts = $path -match "\\scripts\\mods\\$([regex]::Escape($name))\\"
    $notExcluded = $path -notlike "*\_archive\*" `
               -and $path -notlike "*\bundleV2\*" `
               -and $path -notlike "*\.build\*" `
               -and $path -notlike "*\.temp\*" `
               -and $path -notlike "*\.claude\*" `
               -and $path -notlike "*\.git\*" `
               -and $path -notlike "*\.spawn_tweaks_ref\*" `
               -and $path -notlike "*\tweaker\*" `
               -and $path -notlike "*\sample_*\*" `
               -and $path -notlike "*\Helpers*"
    return $isMainFile -and $isInModsScripts -and $notExcluded
}

function Find-ModLuas {
    # Each mod has its main lua at <mod>/scripts/mods/<mod>/<mod>.lua per VMB layout.
    # Skip reference materials, archived legacy mods, sample mods.
    Get-ChildItem -Path $repoRoot -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object {
            $p = $_.FullName
            $name = $_.BaseName
            $parent = (Split-Path $p -Parent | Split-Path -Leaf)
            return Test-ModLuaCandidate $p $name $parent
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
    $staleFirst = "## 1.2.2-dev (2026-07-17)`nold`n`n## 1.2.3-dev (2026-07-18)`nnew"
    if ((Test-ReleaseIdentity -SourceVersion '1.2.3-dev' -ChangelogText $staleFirst).Ok) {
        throw "stale-first CHANGELOG fixture was not rejected"
    }
    $missingFirst = "## Release candidate (2026-07-18)`n`n## 1.2.3-dev (2026-07-17)"
    if ((Test-ReleaseIdentity -SourceVersion '1.2.3-dev' -ChangelogText $missingFirst).Ok) {
        throw "missing-first-version CHANGELOG fixture was not rejected"
    }
    $validFirst = "## v1.2.3-dev (2026-07-18) - newest`nbody`n`n## 1.2.2-dev - old"
    if (-not (Test-ReleaseIdentity -SourceVersion '1.2.3-dev' -ChangelogText $validFirst).Ok) {
        throw "valid newest-first CHANGELOG fixture did not pass"
    }
    $canonicalCandidate = 'C:\repo\weapon_tweaker\scripts\mods\weapon_tweaker\weapon_tweaker.lua'
    if (-not (Test-ModLuaCandidate $canonicalCandidate 'weapon_tweaker' 'weapon_tweaker')) {
        throw 'canonical main-mod Lua candidate was excluded'
    }
    $agentCandidate = 'C:\repo\.claude\worktrees\agent-race\weapon_tweaker\scripts\mods\weapon_tweaker\weapon_tweaker.lua'
    if (Test-ModLuaCandidate $agentCandidate 'weapon_tweaker' 'weapon_tweaker') {
        throw 'agent-worktree Lua candidate was not excluded'
    }
    $vanishedRead = Try-ReadFileUtf8 (Join-Path ([System.IO.Path]::GetTempPath()) 'vt2-check-versions-vanished-file')
    if ($vanishedRead.Ok) {
        throw 'vanished-file read did not fail closed'
    }
    Write-Host "[check_versions] SELF-TEST PASS - banner drift, release identity, agent-worktree exclusion, and vanished reads covered." -ForegroundColor Green
    exit 0
}

foreach ($modLua in Find-ModLuas) {
    $modName = $modLua.BaseName
    $luaRead = Try-ReadFileUtf8 $modLua.FullName
    if (-not $luaRead.Ok) {
        $warnings += "${modName}: SKIP - main Lua vanished during version scan: $($modLua.FullName)"
        continue
    }
    $luaText = $luaRead.Text
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
        $cfgRead = Try-ReadFileUtf8 $cfgPath
        if (-not $cfgRead.Ok) {
            $warnings += "${modName}: SKIP - itemV2.cfg vanished during version scan: $cfgPath"
            continue
        }
        $cfgText = $cfgRead.Text
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

    # Row #51 (issue #724): the NEWEST CHANGELOG entry is the release identity
    # consumed by ship.ps1. It must lead with exactly MOD_VERSION after removing
    # only the optional display 'v'; a matching historical entry is insufficient.
    # CHANGELOG.md is at the MOD ROOT, not inside scripts/. Walk up 3 levels from
    # <mod>/scripts/mods/<mod>/<mod>.lua to find the mod root.
    $changelogPath = Join-Path (Split-Path $modLua.FullName -Parent | Split-Path -Parent | Split-Path -Parent | Split-Path -Parent) "CHANGELOG.md"
    if (Test-Path $changelogPath) {
        $changelogRead = Try-ReadFileUtf8 $changelogPath
        if (-not $changelogRead.Ok) {
            $warnings += "${modName}: SKIP - CHANGELOG.md vanished during version scan: $changelogPath"
            continue
        }
        $changelogText = $changelogRead.Text
        $identity = Test-ReleaseIdentity -SourceVersion $rawVersion -ChangelogText $changelogText
        if (-not $identity.Ok) {
            $errors += "${modName}: $($identity.Message)"
        }
    } else {
        $errors += "${modName}: no CHANGELOG.md at $changelogPath"
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
