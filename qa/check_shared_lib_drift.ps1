# Verifies that build-time copied _lib_*.lua files exactly match their canonical
# tools/shared_lib sources. Exit 2 is blocking drift; issue #428.
[CmdletBinding()]
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [switch]$Quiet,
    [switch]$SelfTest
)
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path $RepoRoot).Path
$syncScript = Join-Path $repoRoot "tools\shared_lib\sync-shared-libs.ps1"
if ($SelfTest) {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-shared-lib-test-" + [guid]::NewGuid().ToString("N"))
    try {
        $libDir = Join-Path $temp "tools\shared_lib"
        $consumerDir = Join-Path $temp "demo\scripts\mods\demo"
        [System.IO.Directory]::CreateDirectory($libDir) | Out-Null
        [System.IO.Directory]::CreateDirectory($consumerDir) | Out-Null
        Copy-Item -LiteralPath $syncScript -Destination (Join-Path $libDir "sync-shared-libs.ps1")
        [System.IO.File]::WriteAllText((Join-Path $libDir "manifest.psd1"),
            '@{ Libraries = @( @{ Source = "_lib_test.lua"; Consumers = @("demo/scripts/mods/demo/_lib_test.lua") } ) }',
            [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllBytes((Join-Path $libDir "_lib_test.lua"), [byte[]](65, 10))
        [System.IO.File]::WriteAllBytes((Join-Path $consumerDir "_lib_test.lua"), [byte[]](65, 13, 10))
        & (Join-Path $libDir "sync-shared-libs.ps1") -RepoRoot $temp -Quiet *>$null
        if ($LASTEXITCODE -ne 2) { throw "exact-byte drift was not rejected" }
        & (Join-Path $libDir "sync-shared-libs.ps1") -RepoRoot $temp -Apply -Quiet *>$null
        if ($LASTEXITCODE -ne 0) { throw "apply did not repair the consumer" }
        & (Join-Path $libDir "sync-shared-libs.ps1") -RepoRoot $temp -Quiet *>$null
        if ($LASTEXITCODE -ne 0) { throw "repaired consumer did not validate" }
        if (-not $Quiet) { Write-Host "[check_shared_lib_drift self-test] PASS" -ForegroundColor Green }
        exit 0
    } catch {
        Write-Host "[check_shared_lib_drift self-test] FAIL: $_" -ForegroundColor Red
        exit 2
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
}
if (-not (Test-Path -LiteralPath $syncScript -PathType Leaf)) {
    Write-Host "[check_shared_lib_drift] ERROR: missing sync tool: $syncScript" -ForegroundColor Red
    exit 2
}
& $syncScript -RepoRoot $repoRoot -Quiet:$Quiet
exit $LASTEXITCODE
