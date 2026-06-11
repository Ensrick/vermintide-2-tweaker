# check_in_progress.ps1 — scans .in_progress/ for sentinel files and warns
# about stale claims (>24h old) or in-flight claims that collide with the
# currently staged files in git.
#
# Convention is documented in `.in_progress/README.md` and CLAUDE.md
# § "Multi-agent coordination". The sentinel files are advisory — this
# script never blocks; it only emits WARNINGs that other sessions / the
# pre-commit hook can surface.
#
# Exit codes:
#   0 = no warnings — directory empty, or all sentinels fresh + no staged
#       collision.
#   1 = stale sentinel (>24h old) or staged-file collision with an in-flight
#       claim — review and either remove the sentinel or coordinate.
#   2 = malformed sentinel file (missing timestamp, wrong filename, etc.).
#
# Usage:
#   .\qa\check_in_progress.ps1              # full scan
#   .\qa\check_in_progress.ps1 -Quiet       # only print warnings/errors
#   .\qa\check_in_progress.ps1 -SkipGitDiff # don't cross-check staged files

[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SkipGitDiff
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path $RepoRoot).Path
$inProgressDir = Join-Path $repoRoot ".in_progress"
$exitCode = 0
$warnings = @()
$errors = @()

function Read-FileUtf8([string]$path) {
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

if (-not (Test-Path $inProgressDir)) {
    if (-not $Quiet) {
        Write-Host "[check_in_progress] no .in_progress/ directory — convention not in use." -ForegroundColor DarkGray
    }
    exit 0
}

# Sentinel files are *.md, excluding the README (documents the convention).
$sentinels = @(Get-ChildItem -Path $inProgressDir -Filter "*.md" -File -ErrorAction SilentlyContinue `
    | Where-Object { $_.Name -ne "README.md" })

if ($sentinels.Count -eq 0) {
    if (-not $Quiet) {
        Write-Host "[check_in_progress] OK — no in-flight claims." -ForegroundColor Green
    }
    exit 0
}

# Build the set of valid mod directory names at the repo root so we can flag
# sentinels that point at non-existent mods.
$validMods = @(Get-ChildItem -Path $repoRoot -Directory -ErrorAction SilentlyContinue `
    | Where-Object {
        $name = $_.Name
        # Skip dotfiles, archives, generic dirs.
        return ($name -notlike ".*") `
            -and ($name -notlike "_*") `
            -and ($name -ne "qa") `
            -and ($name -ne "tools") `
            -and ($name -ne "dumps") `
            -and ($name -ne "__pycache__")
    } `
    | ForEach-Object { $_.Name })

# Parse each sentinel; collect claimed-mod set for the git-diff cross-check.
$claimed = @{}    # mod_name -> @{ Sentinel, Timestamp, SessionId, AgeHours }
$nowUtc = (Get-Date).ToUniversalTime()
$staleThresholdHours = 24

foreach ($sentinel in $sentinels) {
    $modName = $sentinel.BaseName
    $sentinelText = Read-FileUtf8 $sentinel.FullName

    # Validate: sentinel basename should match an existing mod directory.
    if ($validMods -notcontains $modName) {
        $errors += "${modName}: sentinel filename does not match any mod directory at the repo root ($($sentinel.Name))"
        continue
    }

    # Parse timestamp from the sentinel body. Expected format:
    #   - **Started:** 2026-05-25T14:32:00Z
    # (the template in .in_progress/README.md).
    $timestamp = $null
    if ($sentinelText -match '(?im)^\s*-\s*\*\*Started:\*\*\s*([0-9T:\-\+Z\.\s]+?)\s*$') {
        $rawTs = $matches[1].Trim()
        try {
            $timestamp = [System.DateTime]::Parse($rawTs, [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
        } catch {
            $errors += "${modName}: sentinel has unparseable Started timestamp '$rawTs'"
            continue
        }
    } else {
        $errors += "${modName}: sentinel missing required '- **Started:** <ISO-8601-UTC>' line"
        continue
    }

    # Parse session ID (optional but recommended).
    $sessionId = "(unknown)"
    if ($sentinelText -match '(?im)^\s*-\s*\*\*Session ID:\*\*\s*(.+?)\s*$') {
        $sessionId = $matches[1].Trim()
    }

    $ageHours = ($nowUtc - $timestamp).TotalHours
    $claimed[$modName] = @{
        Sentinel  = $sentinel.FullName
        Timestamp = $timestamp
        SessionId = $sessionId
        AgeHours  = $ageHours
    }

    if (-not $Quiet) {
        $ageDisplay = if ($ageHours -lt 1) { "{0:N0}m" -f ($ageHours * 60) } else { "{0:N1}h" -f $ageHours }
        Write-Host "  - ${modName}: claimed by '$sessionId' since $($timestamp.ToString('u')) ($ageDisplay ago)" -ForegroundColor DarkCyan
    }

    if ($ageHours -gt $staleThresholdHours) {
        $warnings += "[in-progress] ${modName}: sentinel is $([math]::Round($ageHours,1))h old (>$staleThresholdHours h) — probably stale, remove if work is done"
    }
}

# Cross-reference staged files against claimed mods. Each staged path is
# expected to live under <mod_name>/...; first path segment names the mod.
if (-not $SkipGitDiff -and $claimed.Count -gt 0) {
    Push-Location $repoRoot
    try {
        $staged = & git diff --cached --name-only --diff-filter=ACMR 2>$null
        if ($LASTEXITCODE -eq 0 -and $staged) {
            $stagedMods = @{}
            foreach ($path in $staged) {
                # Normalize path separators; take first segment.
                $norm = $path -replace '\\', '/'
                $first = ($norm -split '/', 2)[0]
                if ($first -and $validMods -contains $first) {
                    if (-not $stagedMods.ContainsKey($first)) { $stagedMods[$first] = @() }
                    $stagedMods[$first] += $path
                }
            }

            foreach ($modName in $stagedMods.Keys) {
                if ($claimed.ContainsKey($modName)) {
                    $c = $claimed[$modName]
                    $fileCount = $stagedMods[$modName].Count
                    $warnings += "[in-progress] ${modName} is claimed by session '$($c.SessionId)' since $($c.Timestamp.ToString('u')) — $fileCount staged file(s) collide; consider coordinating"
                }
            }
        }
    } catch {
        # Best-effort; not a git repo or git unavailable -> skip silently.
    } finally {
        Pop-Location
    }
}

# Report.
Write-Host ""
if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "[check_in_progress] OK — $($claimed.Count) active claim(s), all fresh, no staged collision." -ForegroundColor Green
    exit 0
}

if ($warnings.Count -gt 0) {
    Write-Host "[check_in_progress] WARNINGS:" -ForegroundColor Yellow
    foreach ($w in $warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
    if ($exitCode -lt 1) { $exitCode = 1 }
}
if ($errors.Count -gt 0) {
    Write-Host "[check_in_progress] ERRORS (malformed sentinels):" -ForegroundColor Red
    foreach ($e in $errors) { Write-Host "  X $e" -ForegroundColor Red }
    $exitCode = 2
}

exit $exitCode
