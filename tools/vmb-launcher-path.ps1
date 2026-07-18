# Shared VMBLauncher dependency resolution for ship and release publishing.
#
# Issue #683: a clean linked worktree may intentionally use launcher bytes
# from the configured or primary checkout. Every pipeline phase must resolve
# the same bounded candidate set and must reject a caller-supplied path/source
# pair that does not describe one of those approved machine-local locations.

function Test-VmbLauncherPathEqual {
    param([string]$Left, [string]$Right)
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    $leftFull = [System.IO.Path]::GetFullPath($Left).TrimEnd('\', '/')
    $rightFull = [System.IO.Path]::GetFullPath($Right).TrimEnd('\', '/')
    return [string]::Equals($leftFull, $rightFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-VmbLauncherConfiguredProjectRoot {
    param([string]$SettingsPath)
    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) { return $null }
    try {
        $settings = [System.IO.File]::ReadAllText($SettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        throw "VMBLauncher settings are not valid JSON: $SettingsPath ($($_.Exception.Message))"
    }
    if ($null -eq $settings -or [string]::IsNullOrWhiteSpace([string]$settings.ProjectRoot)) { return $null }
    return [System.IO.Path]::GetFullPath([string]$settings.ProjectRoot)
}

# Return the primary checkout that owns a linked worktree's shared git common
# directory. This root supplies dependencies only; callers remain responsible
# for binding build source to the invoking checkout.
function Get-VmbLauncherPrimaryWorktreeRoot {
    param([string]$RepoRoot)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& git -C $RepoRoot rev-parse --path-format=absolute --git-common-dir 2>$null |
            ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($exitCode -ne 0 -or $lines.Count -eq 0) { return $null }
    $common = ([string]$lines[-1]).Trim()
    if ([string]::IsNullOrWhiteSpace($common)) { return $null }
    $common = [System.IO.Path]::GetFullPath($common).TrimEnd('\', '/')
    if ([System.IO.Path]::GetFileName($common) -ine '.git') { return $null }
    $candidate = Split-Path $common -Parent
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { return $null }
    return $candidate
}

function Get-ApprovedVmbLauncherCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$ConfiguredProjectRoot,
        [string]$PrimaryWorktreeRoot,
        [string]$EnvironmentPath
    )

    $relative = 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
    $raw = @()
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentPath)) {
        $raw += [pscustomobject]@{ Path = $EnvironmentPath; Source = 'VT2_SHIP_VMB_LAUNCHER'; ApprovalAnchor = $EnvironmentPath }
    }
    $raw += [pscustomobject]@{ Path = (Join-Path $RepoRoot $relative); Source = 'invoking worktree'; ApprovalAnchor = $RepoRoot }
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredProjectRoot)) {
        $raw += [pscustomobject]@{ Path = (Join-Path $ConfiguredProjectRoot $relative); Source = 'VMBLauncher configured ProjectRoot'; ApprovalAnchor = $ConfiguredProjectRoot }
    }
    if (-not [string]::IsNullOrWhiteSpace($PrimaryWorktreeRoot)) {
        $raw += [pscustomobject]@{ Path = (Join-Path $PrimaryWorktreeRoot $relative); Source = 'primary git worktree'; ApprovalAnchor = $PrimaryWorktreeRoot }
    }

    $seen = @{}
    $result = @()
    foreach ($candidate in $raw) {
        $full = [System.IO.Path]::GetFullPath([string]$candidate.Path)
        $anchor = [System.IO.Path]::GetFullPath([string]$candidate.ApprovalAnchor)
        $key = "$($candidate.Source)|$($full.ToLowerInvariant())|$($anchor.ToLowerInvariant())"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $result += [pscustomobject]@{ Path = $full; Source = [string]$candidate.Source; ApprovalAnchor = $anchor }
    }
    return $result
}

function Assert-VmbLauncherFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Context
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Context points to a missing file: $Path"
    }
    if ((Get-Item -LiteralPath $Path).Length -le 0) {
        throw "$Context points to an empty file: $Path"
    }
}

function Resolve-ApprovedVmbLauncherPath {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$RequestedPath,
        [string]$RequestedSource,
        [string]$RequestedApprovalAnchor,
        [string]$ConfiguredProjectRoot,
        [string]$PrimaryWorktreeRoot,
        [string]$EnvironmentPath
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath) -and
            (-not [string]::IsNullOrWhiteSpace($RequestedSource) -or
             -not [string]::IsNullOrWhiteSpace($RequestedApprovalAnchor))) {
        throw 'VMBLauncher source/provenance was supplied without a launcher path.'
    }

    $relative = 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'

    # A canonical ship passes the approval snapshot that produced its selected
    # path. Revalidate that immutable handoff instead of rereading the mutable
    # global ProjectRoot, which another concurrent ship may temporarily bind.
    if (-not [string]::IsNullOrWhiteSpace($RequestedApprovalAnchor)) {
        if ([string]::IsNullOrWhiteSpace($RequestedSource)) {
            throw 'VMBLauncher approval anchor was supplied without its source/provenance.'
        }
        $requestedFull = [System.IO.Path]::GetFullPath($RequestedPath)
        $anchorFull = [System.IO.Path]::GetFullPath($RequestedApprovalAnchor)
        $expectedPath = $null
        switch -CaseSensitive ($RequestedSource) {
            'VT2_SHIP_VMB_LAUNCHER' {
                $expectedPath = $anchorFull
            }
            'invoking worktree' {
                if (-not (Test-VmbLauncherPathEqual $anchorFull $RepoRoot)) {
                    throw "VMBLauncher source/provenance mismatch: invoking-worktree anchor '$anchorFull' is not '$RepoRoot'."
                }
                $expectedPath = Join-Path $anchorFull $relative
            }
            'VMBLauncher configured ProjectRoot' {
                if (-not (Test-Path -LiteralPath $anchorFull -PathType Container)) {
                    throw "VMBLauncher configured ProjectRoot approval anchor is missing: $anchorFull"
                }
                $expectedPath = Join-Path $anchorFull $relative
            }
            'primary git worktree' {
                if ([string]::IsNullOrWhiteSpace($PrimaryWorktreeRoot) -or
                        -not (Test-VmbLauncherPathEqual $anchorFull $PrimaryWorktreeRoot)) {
                    throw "VMBLauncher source/provenance mismatch: primary-worktree anchor '$anchorFull' is not '$PrimaryWorktreeRoot'."
                }
                $expectedPath = Join-Path $anchorFull $relative
            }
            default {
                throw "Unknown VMBLauncher source/provenance: '$RequestedSource'."
            }
        }
        if (-not (Test-VmbLauncherPathEqual $requestedFull $expectedPath)) {
            throw ("VMBLauncher source/provenance mismatch: path '$requestedFull' does not match " +
                   "source '$RequestedSource' at approval anchor '$anchorFull'.")
        }
        Assert-VmbLauncherFile -Path $requestedFull -Context 'Requested VMBLauncher path'
        return [pscustomobject]@{
            Path = $requestedFull
            Source = $RequestedSource
            ApprovalAnchor = $anchorFull
        }
    }

    $candidates = @(Get-ApprovedVmbLauncherCandidates `
        -RepoRoot $RepoRoot `
        -ConfiguredProjectRoot $ConfiguredProjectRoot `
        -PrimaryWorktreeRoot $PrimaryWorktreeRoot `
        -EnvironmentPath $EnvironmentPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $requestedFull = [System.IO.Path]::GetFullPath($RequestedPath)
        $pathMatches = @($candidates | Where-Object {
            Test-VmbLauncherPathEqual $_.Path $requestedFull
        })
        if ($pathMatches.Count -eq 0) {
            throw ("Requested VMBLauncher path is not an approved machine-local candidate: $requestedFull. " +
                   "Approved candidates: $(@($candidates | ForEach-Object { $_.Path }) -join '; ')")
        }

        $selected = $null
        if (-not [string]::IsNullOrWhiteSpace($RequestedSource)) {
            $selected = @($pathMatches | Where-Object {
                [string]::Equals($_.Source, $RequestedSource, [System.StringComparison]::Ordinal)
            }) | Select-Object -First 1
            if ($null -eq $selected) {
                throw ("VMBLauncher source/provenance mismatch for '$requestedFull': requested " +
                       "'$RequestedSource', approved as $(@($pathMatches | ForEach-Object { $_.Source }) -join ', ').")
            }
        } else {
            $selected = $pathMatches[0]
        }
        Assert-VmbLauncherFile -Path $selected.Path -Context 'Requested VMBLauncher path'
        return $selected
    }

    # An environment override is an explicit operator choice. If it is set but
    # invalid, fail instead of silently falling back to another executable.
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentPath)) {
        $environmentCandidate = @($candidates | Where-Object { $_.Source -eq 'VT2_SHIP_VMB_LAUNCHER' }) |
            Select-Object -First 1
        Assert-VmbLauncherFile -Path $environmentCandidate.Path -Context 'VT2_SHIP_VMB_LAUNCHER'
        return $environmentCandidate
    }

    $attempted = @()
    foreach ($candidate in $candidates) {
        $attempted += $candidate.Path
        if ((Test-Path -LiteralPath $candidate.Path -PathType Leaf) -and
                (Get-Item -LiteralPath $candidate.Path).Length -gt 0) {
            return $candidate
        }
    }
    throw ("VMBLauncher.exe was not found in any approved machine-local location: " +
           ($attempted -join '; ') +
           ". Set VT2_SHIP_VMB_LAUNCHER to the published executable or publish it in the primary/configured worktree.")
}
