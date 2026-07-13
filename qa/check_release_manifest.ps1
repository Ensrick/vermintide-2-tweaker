# check_release_manifest.ps1 - validate GitHub release provenance metadata.
#
# Exit 0 = valid (legacy carried entries may warn); exit 2 = invalid manifest.
# -SelfTest is offline and auto-discovered by qa/run_selftests.ps1.

[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$StageRoot,
    [string[]]$RequiredModIds = @(),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1')

function Invoke-SelfTest {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-release-manifest-" + [guid]::NewGuid().ToString('N'))
    $modStage = Join-Path $temp 'example'
    New-Item -ItemType Directory -Path $modStage -Force | Out-Null
    try {
        [System.IO.File]::WriteAllBytes((Join-Path $modStage 'aaaaaaaaaaaaaaaa.mod_bundle'), [byte[]](1, 2, 3, 4))
        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'descriptor')
        $bundleFiles = New-BundleFileRecords -BundleDirectory $modStage
        $entry = [ordered]@{
            mod_id = 'example'; friendly_name = 'Example'; workshop_id = '1234567890'
            version = '1.2.3-dev'; asset_filename = 'example.zip'; sha256 = ('a' * 64)
            visibility = 'friends_only'; source_commit = ('b' * 40); source_state = 'clean'
            builder = [ordered]@{ name = 'VMBLauncher'; version = '1.2.3' }
            bundle_files = $bundleFiles
        }
        $manifest = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'; published_at = '2026-07-13T00:00:00Z'
            mods = @($entry)
        }

        $failures = [System.Collections.Generic.List[string]]::new()
        function Assert([bool]$Condition, [string]$Description) {
            if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
            else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $failures.Add($Description) }
        }

        $valid = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert $valid.Valid 'accepts complete source-to-bundle provenance'
        Assert ($valid.Warnings.Count -eq 0) 'complete provenance emits no warnings'

        $entry.source_commit = 'not-a-commit'
        $badCommit = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $badCommit.Valid) 'rejects malformed source commit'
        $entry.source_commit = ('b' * 40)

        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'tampered')
        $badHash = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $badHash.Valid) 'rejects staged bundle hash mismatch'
        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'descriptor')

        [System.IO.File]::WriteAllText((Join-Path $modStage 'unlisted.mod_bundle'), 'extra')
        $extraFile = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $extraFile.Valid) 'rejects staged output omitted from bundle_files'
        Remove-Item -LiteralPath (Join-Path $modStage 'unlisted.mod_bundle') -Force

        $legacy = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'; published_at = '2026-07-13T00:00:00Z'
            mods = @([ordered]@{
                mod_id = 'legacy'; workshop_id = '42'; version = '0.1.0'; asset_filename = 'legacy.zip'
                sha256 = ('c' * 64)
            })
        }
        $legacyCarry = Test-ReleaseManifest -Manifest $legacy
        Assert $legacyCarry.Valid 'allows a carried pre-transition entry'
        Assert ($legacyCarry.Warnings.Count -eq 1) 'warns for carried entry without provenance'
        $legacyRequired = Test-ReleaseManifest -Manifest $legacy -RequiredModIds @('legacy')
        Assert (-not $legacyRequired.Valid) 'rejects newly staged entry without provenance'

        if ($failures.Count -gt 0) {
            Write-Host "[check_release_manifest] SELF-TEST FAILED -- $($failures.Count) case(s)" -ForegroundColor Red
            return 2
        }
        Write-Host '[check_release_manifest] SELF-TEST OK' -ForegroundColor Green
        return 0
    } finally {
        if (Test-Path -LiteralPath $temp) {
            Get-ChildItem -LiteralPath $temp -Recurse -File | Remove-Item -Force
            Get-ChildItem -LiteralPath $temp -Recurse -Directory | Sort-Object FullName -Descending | Remove-Item -Force
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

if ($SelfTest) { exit (Invoke-SelfTest) }
if (-not $ManifestPath) {
    Write-Host '[check_release_manifest] ERROR -- pass -ManifestPath or -SelfTest.' -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Host "[check_release_manifest] ERROR -- manifest not found: $ManifestPath" -ForegroundColor Red
    exit 2
}

try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
catch {
    Write-Host "[check_release_manifest] ERROR -- invalid JSON: $_" -ForegroundColor Red
    exit 2
}
$verdict = Test-ReleaseManifest -Manifest $manifest -RequiredModIds $RequiredModIds -StageRoot $StageRoot
foreach ($warning in $verdict.Warnings) { Write-Host "[check_release_manifest] WARNING -- $warning" -ForegroundColor Yellow }
if (-not $verdict.Valid) {
    foreach ($error in $verdict.Errors) { Write-Host "[check_release_manifest] ERROR -- $error" -ForegroundColor Red }
    exit 2
}
Write-Host "[check_release_manifest] OK -- $(@($manifest.mods).Count) entries validated." -ForegroundColor Green
exit 0
