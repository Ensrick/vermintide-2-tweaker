# Focused policy and behavior gate for post-VMB build normalization.
# ASCII-only for Windows PowerShell 5.1 parsing.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$helperPath = Join-Path $PSScriptRoot '..\tools\ship\build-output-normalization.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    Write-Host "[check_build_output_normalization] ERROR - helper missing: $helperPath" -ForegroundColor Red
    exit 2
}
. $helperPath

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

function Invoke-NormalizationSelfTest {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-build-normalization-" + [guid]::NewGuid().ToString('N'))
    $exampleBundle = Join-Path $temp 'example\bundleV2'
    $otherBundle = Join-Path $temp 'other\bundleV2'
    $toolsDir = Join-Path $temp 'tools'
    [System.IO.Directory]::CreateDirectory($exampleBundle) | Out-Null
    [System.IO.Directory]::CreateDirectory($otherBundle) | Out-Null
    [System.IO.Directory]::CreateDirectory($toolsDir) | Out-Null

    $failures = [System.Collections.Generic.List[string]]::new()
    function Assert([bool]$Condition, [string]$Description) {
        if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
        else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $failures.Add($Description) }
    }

    try {
        $rootName = 'aaaaaaaaaaaaaaaa.mod_bundle'
        $sidecarName = 'cccccccccccccccc.mod_bundle'
        $unrelatedName = 'eeeeeeeeeeeeeeee.mod_bundle'
        $rootPath = Join-Path $exampleBundle $rootName
        $sidecarPath = Join-Path $exampleBundle $sidecarName
        $unrelatedPath = Join-Path $exampleBundle $unrelatedName
        $otherSidecarPath = Join-Path $otherBundle $sidecarName
        [System.IO.File]::WriteAllBytes($rootPath, [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes($sidecarPath, [byte[]](4, 5, 6, 7))
        [System.IO.File]::WriteAllBytes($unrelatedPath, [byte[]](8, 9))
        [System.IO.File]::WriteAllBytes($otherSidecarPath, [byte[]](4, 5, 6, 7))
        $sidecarSha = (Get-FileHash -LiteralPath $sidecarPath -Algorithm SHA256).Hash.ToLowerInvariant()

        $inventoryText = @"
@{
    Mods = @(
        @{
            Dir = 'example'; ModId = 'example'; WorkshopId = '1'; Visibility = 'private';
            Stream = 'single'; Public = `$false; Name = 'Example'; RootBundle = '$rootName';
            BuildArtifactExclusions = @(
                @{ Name = '$sidecarName'; Sha256 = '$sidecarSha'; Reason = 'fixture SDK tool-only output' }
            )
        },
        @{
            Dir = 'other'; ModId = 'other'; WorkshopId = '2'; Visibility = 'private';
            Stream = 'single'; Public = `$false; Name = 'Other'; RootBundle = 'bbbbbbbbbbbbbbbb.mod_bundle'
        }
    )
}
"@
        [System.IO.File]::WriteAllText((Join-Path $toolsDir 'mod-inventory.psd1'), $inventoryText, [System.Text.UTF8Encoding]::new($false))

        $exact = Invoke-BuildOutputNormalization -RepoRoot $temp -Mod example
        Assert ($exact.Removed -eq 1 -and -not (Test-Path -LiteralPath $sidecarPath)) 'exact inventoried sidecar is removed'
        Assert ((Test-Path -LiteralPath $rootPath) -and (Test-Path -LiteralPath $unrelatedPath)) 'root and unrelated bundles remain untouched'
        $normalizedEmittedMap = @((Get-ChildItem -LiteralPath $exampleBundle -File).Name | Sort-Object)

        $absent = Invoke-BuildOutputNormalization -RepoRoot $temp -Mod example
        Assert ($absent.Absent -eq 1 -and $absent.Removed -eq 0) 'absent sidecar is a successful no-op'
        $normalizedAbsentMap = @((Get-ChildItem -LiteralPath $exampleBundle -File).Name | Sort-Object)
        Assert (@(Compare-Object $normalizedEmittedMap $normalizedAbsentMap).Count -eq 0) 'emitted and absent raw maps normalize to the same canonical file set'

        $other = Invoke-BuildOutputNormalization -RepoRoot $temp -Mod other
        Assert ($other.Removed -eq 0 -and $other.Absent -eq 0 -and (Test-Path -LiteralPath $otherSidecarPath)) 'ordinary mod without a policy leaves the same leaf untouched'

        [System.IO.File]::WriteAllBytes($sidecarPath, [byte[]](99, 98, 97))
        $wrongHashFailed = $false
        try { Invoke-BuildOutputNormalization -RepoRoot $temp -Mod example | Out-Null }
        catch { $wrongHashFailed = $_.Exception.Message -match 'REFUSED changed bytes' }
        Assert ($wrongHashFailed -and (Test-Path -LiteralPath $sidecarPath)) 'changed bytes fail closed and remain for inspection'

        $invalid = @{
            Dir = 'bad'; RootBundle = $rootName;
            BuildArtifactExclusions = @(
                @{ Name = '..\escape.mod_bundle'; Sha256 = 'bad'; Reason = '' },
                @{ Name = 'dddddddddddddddd.mod_bundle'; Sha256 = 'bad'; Reason = '' },
                @{ Name = 'example.mod'; Sha256 = ('c' * 64); Reason = 'descriptor collision' },
                @{ Name = $rootName; Sha256 = ('a' * 64); Reason = 'root collision' },
                @{ Name = 'ffffffffffffffff.mod_bundle'; Sha256 = ('b' * 64); Reason = 'duplicate one' },
                @{ Name = 'ffffffffffffffff.mod_bundle'; Sha256 = ('b' * 64); Reason = 'duplicate two' }
            )
        }
        $policyErrors = @(Get-BuildArtifactExclusionErrors -ModEntry $invalid)
        Assert (($policyErrors -match 'invalid BuildArtifactExclusions name').Count -gt 0) 'path-shaped exclusion is rejected'
        Assert (($policyErrors -match 'invalid BuildArtifactExclusions SHA-256').Count -gt 0) 'invalid SHA-256 is rejected'
        Assert (($policyErrors -match 'example.mod').Count -gt 0) 'mod descriptor cannot be excluded'
        Assert (($policyErrors -match 'reason is empty').Count -gt 0) 'empty reason is rejected'
        Assert (($policyErrors -match 'cannot name RootBundle').Count -gt 0) 'canonical root bundle cannot be excluded'
        Assert (($policyErrors -match 'duplicate BuildArtifactExclusions').Count -gt 0) 'duplicate exclusion is rejected'

        if ($failures.Count -gt 0) {
            Write-Host "[check_build_output_normalization] SELF-TEST FAILED - $($failures.Count) case(s)" -ForegroundColor Red
            return 2
        }
        Write-Host '[check_build_output_normalization] SELF-TEST OK' -ForegroundColor Green
        return 0
    }
    finally {
        Remove-LeafTree -Path $temp
    }
}

if ($SelfTest) { exit (Invoke-NormalizationSelfTest) }

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    Write-Host "[check_build_output_normalization] ERROR - inventory missing: $inventoryPath" -ForegroundColor Red
    exit 2
}
$inventory = Import-PowerShellDataFile -Path $inventoryPath
$errors = @()
foreach ($entry in @($inventory.Mods)) {
    $errors += @(Get-BuildArtifactExclusionErrors -ModEntry $entry)
}
if ($errors.Count -gt 0) {
    Write-Host '[check_build_output_normalization] ERRORS:' -ForegroundColor Red
    foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) {
    $policyCount = @($inventory.Mods | ForEach-Object {
        @($_.BuildArtifactExclusions | Where-Object { $null -ne $_ })
    }).Count
    Write-Host "[check_build_output_normalization] OK - $policyCount exact exclusion policy record(s) are valid." -ForegroundColor Green
}
exit 0
