# check_vmb_launcher_path.ps1
#
# Offline regression for issue #683. The canonical ship and standalone release
# paths must share one approved VMBLauncher resolver, preserve path provenance,
# and read builder version metadata from the exact validated executable.

[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$pathHelpers = Join-Path $repoRoot 'tools\vmb-launcher-path.ps1'
$manifestHelpers = Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1'

$failures = New-Object 'System.Collections.Generic.List[string]'
function Assert-Contract {
    param([bool]$Condition, [string]$Description)
    if ($Condition) {
        Write-Host "  [PASS] $Description" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        $failures.Add($Description)
    }
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern, [string]$Description)
    $rejected = $false
    try { & $Action | Out-Null }
    catch { $rejected = $_.Exception.Message -match $Pattern }
    Assert-Contract $rejected $Description
}

Write-Host '=== check_vmb_launcher_path ===' -ForegroundColor Cyan
if (-not (Test-Path -LiteralPath $pathHelpers -PathType Leaf)) {
    Write-Host "[check_vmb_launcher_path] ERROR -- missing $pathHelpers" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $manifestHelpers -PathType Leaf)) {
    Write-Host "[check_vmb_launcher_path] ERROR -- missing $manifestHelpers" -ForegroundColor Red
    exit 2
}
. $pathHelpers
. $manifestHelpers

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
$fixtureRoot = Join-Path $tempRoot ("vt2-launcher-683-" + [guid]::NewGuid().ToString('N'))
$invokingRoot = Join-Path $fixtureRoot 'clean-worktree'
$configuredRoot = Join-Path $fixtureRoot 'configured-project'
$primaryRoot = Join-Path $fixtureRoot 'primary-worktree'
$outsiderRoot = Join-Path $fixtureRoot 'outside-approved-roots'
$relative = 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'

[System.IO.Directory]::CreateDirectory($invokingRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($configuredRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($primaryRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($outsiderRoot) | Out-Null

try {
    $configuredLauncher = Join-Path $configuredRoot $relative
    [System.IO.Directory]::CreateDirectory((Split-Path $configuredLauncher -Parent)) | Out-Null
    $hostExecutable = (Get-Process -Id $PID).Path
    Copy-Item -LiteralPath $hostExecutable -Destination $configuredLauncher

    $settingsPath = Join-Path $fixtureRoot 'settings.json'
    $settingsJson = @{ ProjectRoot = $configuredRoot } | ConvertTo-Json
    [System.IO.File]::WriteAllText($settingsPath, $settingsJson, (New-Object System.Text.UTF8Encoding($false)))
    $configuredFromSettings = Get-VmbLauncherConfiguredProjectRoot -SettingsPath $settingsPath
    Assert-Contract (Test-VmbLauncherPathEqual $configuredFromSettings $configuredRoot) 'configured ProjectRoot is read exactly'

    $fallback = Resolve-ApprovedVmbLauncherPath `
        -RepoRoot $invokingRoot `
        -ConfiguredProjectRoot $configuredFromSettings `
        -PrimaryWorktreeRoot $primaryRoot
    Assert-Contract (Test-VmbLauncherPathEqual $fallback.Path $configuredLauncher) 'clean worktree resolves the external configured launcher'
    Assert-Contract ($fallback.Source -eq 'VMBLauncher configured ProjectRoot') 'clean-worktree fallback retains configured-root provenance'

    $handoff = Resolve-ApprovedVmbLauncherPath `
        -RepoRoot $invokingRoot `
        -RequestedPath $fallback.Path `
        -RequestedSource $fallback.Source `
        -RequestedApprovalAnchor $fallback.ApprovalAnchor `
        -ConfiguredProjectRoot $primaryRoot `
        -PrimaryWorktreeRoot $primaryRoot
    Assert-Contract ((Test-VmbLauncherPathEqual $handoff.Path $fallback.Path) -and
        $handoff.Source -eq $fallback.Source -and
        (Test-VmbLauncherPathEqual $handoff.ApprovalAnchor $configuredRoot)) 'ship-to-release exact approval snapshot revalidates despite mutable configured-root drift'

    $version = Get-VmbLauncherVersion -LauncherPath $handoff.Path
    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($configuredLauncher)
    $expectedVersion = if (-not [string]::IsNullOrWhiteSpace($versionInfo.ProductVersion)) {
        $versionInfo.ProductVersion
    } else {
        $versionInfo.FileVersion
    }
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($version)) 'validated launcher exposes real version metadata'
    Assert-Contract ($version -eq $expectedVersion) 'manifest builder version comes from the exact handed-off executable'

    $outsideLauncher = Join-Path $outsiderRoot 'VMBLauncher.exe'
    Copy-Item -LiteralPath $hostExecutable -Destination $outsideLauncher
    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath `
            -RepoRoot $invokingRoot `
            -RequestedPath $outsideLauncher `
            -ConfiguredProjectRoot $configuredFromSettings `
            -PrimaryWorktreeRoot $primaryRoot
    } 'not an approved machine-local candidate' 'existing but unapproved explicit launcher path fails closed'

    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath `
            -RepoRoot $invokingRoot `
            -RequestedPath $configuredLauncher `
            -RequestedSource 'invoking worktree' `
            -RequestedApprovalAnchor $configuredRoot `
            -ConfiguredProjectRoot $configuredFromSettings `
            -PrimaryWorktreeRoot $primaryRoot
    } 'source/provenance mismatch' 'launcher path/source provenance mismatch fails closed'

    $emptyRoot = Join-Path $fixtureRoot 'no-launcher'
    [System.IO.Directory]::CreateDirectory($emptyRoot) | Out-Null
    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath -RepoRoot $emptyRoot
    } 'not found in any approved' 'standalone fallback fails closed without an approved launcher'

    $missingOverride = Join-Path $fixtureRoot 'missing-explicit.exe'
    Assert-Rejected {
        Resolve-ApprovedVmbLauncherPath `
            -RepoRoot $invokingRoot `
            -ConfiguredProjectRoot $configuredFromSettings `
            -EnvironmentPath $missingOverride
    } 'VT2_SHIP_VMB_LAUNCHER points to a missing file' 'invalid environment override never silently falls back'

    $shipPath = Join-Path $repoRoot 'tools\ship\ship.ps1'
    $publishPath = Join-Path $repoRoot 'tools\publish-release\publish-release.ps1'
    $shipText = [System.IO.File]::ReadAllText($shipPath, [System.Text.Encoding]::UTF8)
    $publishText = [System.IO.File]::ReadAllText($publishPath, [System.Text.Encoding]::UTF8)
    Assert-Contract ($shipText.Contains('-LauncherPath $launcherResolution.Path') -and
        $shipText.Contains('-LauncherSource $launcherResolution.Source') -and
        $shipText.Contains('-LauncherApprovalAnchor $launcherResolution.ApprovalAnchor')) 'ship passes the exact approved launcher snapshot to release publishing'
    Assert-Contract ($publishText -match '(?m)^\s*\[string\]\$LauncherPath\b' -and
        $publishText -match '(?m)^\s*\[string\]\$LauncherSource\b' -and
        $publishText -match '(?m)^\s*\[string\]\$LauncherApprovalAnchor\b') 'release publisher declares the launcher handoff parameters'
    Assert-Contract ($publishText.Contains('Resolve-ApprovedVmbLauncherPath') -and
        $publishText.Contains('Get-VmbLauncherVersion -LauncherPath $launcher')) 'release publisher revalidates the shared path before recording its version'
}
finally {
    $fixtureFull = [System.IO.Path]::GetFullPath($fixtureRoot)
    $safeFixture = $fixtureFull.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        ([System.IO.Path]::GetFileName($fixtureFull) -like 'vt2-launcher-683-*')
    if (-not $safeFixture) {
        throw "Refusing fixture cleanup outside the expected temp root: $fixtureFull"
    }
    if (Test-Path -LiteralPath $fixtureFull) {
        Get-ChildItem -LiteralPath $fixtureFull -Recurse -File | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName
        }
        Get-ChildItem -LiteralPath $fixtureFull -Recurse -Directory |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName }
        Remove-Item -LiteralPath $fixtureFull
    }
}

if ($failures.Count -gt 0) {
    Write-Host "[check_vmb_launcher_path] FAILED -- $($failures.Count) contract regression(s)." -ForegroundColor Red
    exit 2
}
Write-Host '[check_vmb_launcher_path] OK -- launcher path/provenance contracts pass.' -ForegroundColor Green
exit 0
