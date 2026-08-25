# check_release_reproducibility.ps1 - pre-build source audit and fresh-checkout rebuild proof.
#
# -AuditOnly is read-only and intentionally is not wired into ship.ps1 yet. The
# current ship doctrine commits after Workshop/GitHub publication, so a blocking
# clean-source rule needs a maintainer-approved commit-before-build workflow.
# The full mode builds only through VMBLauncher, applies the repository's exact
# hash-pinned output policy, and compares that canonical output with a schema-2
# manifest entry. It never deploys, uploads, or touches Workshop.
#
# Exit 0 = audit/proof passed; exit 2 = source or reproducibility gate failed.
# -SelfTest is offline and auto-discovered by qa/run_selftests.ps1.

[CmdletBinding()]
param(
    [string]$Mod,
    [string]$CheckoutRoot,
    [string]$ManifestPath,
    [string]$LauncherPath,
    [string]$LauncherSettingsPath,
    [switch]$AuditOnly,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1')
$buildOutputNormalizationHelpers = Join-Path $repoRoot 'tools\ship\build-output-normalization.ps1'
if (-not (Test-Path -LiteralPath $buildOutputNormalizationHelpers -PathType Leaf)) {
    throw "Build-output normalization policy not found: $buildOutputNormalizationHelpers"
}
. $buildOutputNormalizationHelpers
. (Join-Path $repoRoot 'tools\ship\transaction-lease.ps1')

function Remove-LeafTree {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
    }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory |
        Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    Remove-Item -LiteralPath $Path -Force
}

function Invoke-SelfTest {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-release-repro-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $temp 'example\bundleV2') -Force | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $temp 'example\source.lua'), 'return true')
        git -C $temp init --quiet
        git -C $temp add example/source.lua
        git -C $temp -c user.name=SelfTest -c user.email=selftest.invalid commit --quiet --no-verify -m fixture

        $failures = [System.Collections.Generic.List[string]]::new()
        function Assert([bool]$Condition, [string]$Description) {
            if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
            else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $failures.Add($Description) }
        }

        Assert ((Get-ModSourceState -RepoRoot $temp -ModFolder example) -eq 'clean') 'accepts a committed mod source tree'
        [System.IO.File]::WriteAllText((Join-Path $temp 'example\untracked.lua'), 'dirty')
        Assert ((Get-ModSourceState -RepoRoot $temp -ModFolder example) -eq 'dirty') 'rejects uncommitted mod source'
        Remove-Item -LiteralPath (Join-Path $temp 'example\untracked.lua') -Force
        [System.IO.File]::WriteAllText((Join-Path $temp 'example\bundleV2\generated.mod'), 'generated')
        Assert ((Get-ModSourceState -RepoRoot $temp -ModFolder example) -eq 'clean') 'excludes generated bundleV2 changes from source state'

        $expected = @([ordered]@{ filename = 'a.mod'; sha256 = ('a' * 64) })
        $same = @([ordered]@{ filename = 'a.mod'; sha256 = ('a' * 64) })
        $changed = @([ordered]@{ filename = 'a.mod'; sha256 = ('b' * 64) })
        $extra = @($same + [ordered]@{ filename = 'b.mod_bundle'; sha256 = ('c' * 64) })
        Assert ((Compare-VtBundleOutputSets -Expected $expected -Actual $same -RequireLength:$false).Count -eq 0) 'accepts byte-identical file records'
        Assert ((Compare-VtBundleOutputSets -Expected $expected -Actual $changed -RequireLength:$false).Count -eq 1) 'rejects a changed raw bundle hash'
        Assert ((Compare-VtBundleOutputSets -Expected $expected -Actual $extra -RequireLength:$false).Count -eq 1) 'rejects an unrecorded fresh-build output'

        if ($failures.Count -gt 0) {
            Write-Host "[check_release_reproducibility] SELF-TEST FAILED -- $($failures.Count) case(s)" -ForegroundColor Red
            return 2
        }
        Write-Host '[check_release_reproducibility] SELF-TEST OK' -ForegroundColor Green
        return 0
    } finally {
        Remove-LeafTree -Path $temp
    }
}

if ($SelfTest) { exit (Invoke-SelfTest) }
if (-not $Mod) {
    Write-Host '[check_release_reproducibility] ERROR -- pass -Mod <folder-or-id> (or -SelfTest).' -ForegroundColor Red
    exit 2
}
if (-not $CheckoutRoot) { $CheckoutRoot = $repoRoot }
try { $CheckoutRoot = (Resolve-Path -LiteralPath $CheckoutRoot).Path }
catch {
    Write-Host "[check_release_reproducibility] ERROR -- checkout not found: $CheckoutRoot" -ForegroundColor Red
    exit 2
}

$inventoryPath = Join-Path $CheckoutRoot 'tools\mod-inventory.psd1'
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    Write-Host "[check_release_reproducibility] ERROR -- mod inventory missing from checkout: $inventoryPath" -ForegroundColor Red
    exit 2
}
$inventory = Import-PowerShellDataFile -Path $inventoryPath
$matches = @($inventory.Mods | Where-Object { $_.Dir -eq $Mod -or $_.ModId -eq $Mod })
if ($matches.Count -ne 1) {
    Write-Host "[check_release_reproducibility] ERROR -- '$Mod' does not resolve uniquely in tools/mod-inventory.psd1." -ForegroundColor Red
    exit 2
}
$inventoryEntry = $matches[0]
$modFolder = "$($inventoryEntry.Dir)"
$modId = "$($inventoryEntry.ModId)"
if ("$($inventoryEntry.BundleAuthority)" -cne 'tracked') {
    Write-Host "[check_release_reproducibility] ERROR -- unsupported BundleAuthority '$($inventoryEntry.BundleAuthority)' for $modFolder." -ForegroundColor Red
    exit 2
}
$sourceCommit = Get-ReleaseSourceCommit -RepoRoot $CheckoutRoot
$sourceChanges = @(Get-ModSourceChanges -RepoRoot $CheckoutRoot -ModFolder $modFolder)

Write-Host "Release source audit: $modFolder ($modId)" -ForegroundColor Cyan
Write-Host "  checkout: $CheckoutRoot"
Write-Host "  commit  : $sourceCommit"
if ($sourceChanges.Count -gt 0) {
    Write-Host '  state   : DIRTY -- immutable source precondition is not met' -ForegroundColor Red
    foreach ($change in $sourceChanges) { Write-Host "    $change" -ForegroundColor DarkGray }
    Write-Host '[check_release_reproducibility] BLOCKED -- commit the exact release source before any build/upload.' -ForegroundColor Red
    exit 2
}
Write-Host '  state   : CLEAN' -ForegroundColor Green

if ($AuditOnly) {
    Write-Host '[check_release_reproducibility] AUDIT PASS -- source is ready for a commit-before-build workflow.' -ForegroundColor Green
    exit 0
}
if (-not $ManifestPath) {
    Write-Host '[check_release_reproducibility] ERROR -- full proof needs -ManifestPath <schema-2 manifest.json>.' -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Host "[check_release_reproducibility] ERROR -- manifest not found: $ManifestPath" -ForegroundColor Red
    exit 2
}
try { $manifest = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
catch {
    Write-Host "[check_release_reproducibility] ERROR -- invalid manifest JSON: $_" -ForegroundColor Red
    exit 2
}
$entries = @($manifest.mods | Where-Object { "$($_.mod_id)" -eq $modId })
if ($entries.Count -ne 1) {
    Write-Host "[check_release_reproducibility] ERROR -- manifest must contain exactly one '$modId' entry." -ForegroundColor Red
    exit 2
}
$entry = $entries[0]
if ("$($entry.source_commit)" -ne $sourceCommit) {
    Write-Host "[check_release_reproducibility] ERROR -- checkout HEAD $sourceCommit does not match manifest source_commit $($entry.source_commit)." -ForegroundColor Red
    exit 2
}
if ("$($entry.source_state)" -ne 'clean') {
    Write-Host "[check_release_reproducibility] ERROR -- manifest entry is not source_state clean." -ForegroundColor Red
    exit 2
}
if ("$($entry.builder.name)" -ne 'VMBLauncher') {
    Write-Host "[check_release_reproducibility] ERROR -- manifest builder is not VMBLauncher." -ForegroundColor Red
    exit 2
}

if (-not $LauncherPath) {
    $LauncherPath = Join-Path $repoRoot 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'
}
if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
    Write-Host "[check_release_reproducibility] ERROR -- VMBLauncher not found: $LauncherPath" -ForegroundColor Red
    exit 2
}
$vmbrc = Join-Path $CheckoutRoot '.vmbrc'
if (-not (Test-Path -LiteralPath $vmbrc -PathType Leaf)) {
    Write-Host "[check_release_reproducibility] ERROR -- fresh checkout needs ignored .vmbrc setup; copy .vmbrc.example and adjust only machine-local paths." -ForegroundColor Red
    exit 2
}
if (-not $LauncherSettingsPath) { $LauncherSettingsPath = Join-Path $env:APPDATA 'VMBLauncher\settings.json' }
if (-not (Test-Path -LiteralPath $LauncherSettingsPath -PathType Leaf)) {
    Write-Host "[check_release_reproducibility] ERROR -- launcher settings not found: $LauncherSettingsPath" -ForegroundColor Red
    exit 2
}

$tempSettings = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-vmb-settings-" + [guid]::NewGuid().ToString('N') + '.json')
$launcherLease = $null
$rebuildTransactionLease = $null
try {
    $launcherLease = Enter-VmbLauncherExecutableLease `
        -LauncherPath $LauncherPath -RequireDirectPath
    $launcherVersion = [string](Assert-VmbLauncherExecutableLease `
        -Lease $launcherLease -VerifyContent).version
    if ($launcherVersion -ne "$($entry.builder.version)") {
        Write-Host "[check_release_reproducibility] ERROR -- launcher version $launcherVersion does not match manifest builder version $($entry.builder.version)." -ForegroundColor Red
        exit 2
    }
    $rebuildTransactionLease = Enter-VmbMachineTransactionLease `
        -Action 'reproducibility-build' `
        -Mod $modFolder `
        -ProjectRoot $CheckoutRoot

    $settings = [System.IO.File]::ReadAllText($LauncherSettingsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $settings.ProjectRoot = $CheckoutRoot
    $json = $settings | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($tempSettings, $json, [System.Text.UTF8Encoding]::new($false))

    Write-Host "  builder : VMBLauncher $launcherVersion" -ForegroundColor Cyan
    Write-Host "  action  : clean rebuild only (no deploy/upload)" -ForegroundColor Cyan
    $buildRun = Invoke-VmbLauncherProcess `
        -Lease $launcherLease `
        -ArgumentList @('--config', $tempSettings, '--no-banner', 'build', $modFolder, '--clean') `
        -WorkingDirectory $CheckoutRoot `
        -ReplayOutput
    if ($buildRun.ExitCode -ne 0) {
        Write-Host "[check_release_reproducibility] ERROR -- VMBLauncher build exited $($buildRun.ExitCode)." -ForegroundColor Red
        exit 2
    }

    try {
        $buildNormalization = Invoke-BuildOutputNormalization -RepoRoot $CheckoutRoot -Mod $modFolder
    } catch {
        Write-Host "[check_release_reproducibility] ERROR -- build-output normalization failed: $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }

    $bundleDir = Join-Path (Join-Path $CheckoutRoot $modFolder) 'bundleV2'
    $actual = Get-VtBundleOutputSet `
        -BundleDirectory $bundleDir `
        -ExpectedDescriptorName "$modFolder.mod" `
        -ExpectedRootBundle "$($inventoryEntry.RootBundle)"
    $errors = @(Compare-VtBundleOutputSets `
        -Expected @($entry.bundle_files) `
        -Actual $actual `
        -ExpectedLabel 'release manifest' `
        -ActualLabel 'fresh build' `
        -RequireLength:$false)
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) { Write-Host "[check_release_reproducibility] ERROR -- $error" -ForegroundColor Red }
        exit 2
    }
    Write-Host "[check_release_reproducibility] PASS -- $(@($actual.Files).Count) canonical post-policy file(s) rebuilt byte-identically from $sourceCommit." -ForegroundColor Green
    exit 0
} finally {
    try {
        try {
            if (Test-Path -LiteralPath $tempSettings) {
                Remove-Item -LiteralPath $tempSettings -Force
            }
        }
        finally {
            if ($null -ne $launcherLease) {
                Exit-VmbLauncherExecutableLease -Lease $launcherLease
            }
        }
    }
    finally {
        if ($null -ne $rebuildTransactionLease) {
            Exit-VmbMachineTransactionLease -Lease $rebuildTransactionLease
        }
    }
}
