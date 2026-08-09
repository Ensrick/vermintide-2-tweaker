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

        # Census scans (#1159). Byte comparison only sees declared copies, so
        # each planted census failure is paired with a run the census must NOT
        # fail: green has to mean "nothing undeclared", not "scan found nothing".
        $orphanCopy = Join-Path $consumerDir "_lib_orphan.lua"
        [System.IO.File]::WriteAllBytes($orphanCopy, [byte[]](66, 10))
        & (Join-Path $libDir "sync-shared-libs.ps1") -RepoRoot $temp -Quiet *>$null
        if ($LASTEXITCODE -ne 2) { throw "undeclared consumer copy was not rejected" }
        Remove-Item -LiteralPath $orphanCopy -Force

        $unmanifested = Join-Path $libDir "_lib_unmanifested.lua"
        [System.IO.File]::WriteAllBytes($unmanifested, [byte[]](67, 10))
        & (Join-Path $libDir "sync-shared-libs.ps1") -RepoRoot $temp -Quiet *>$null
        if ($LASTEXITCODE -ne 2) { throw "unmanifested canonical library was not rejected" }
        Remove-Item -LiteralPath $unmanifested -Force

        # Build output and tool-owned checkouts are not mod source: a copy there
        # must stay invisible, or the census would be permanently red.
        $bundleDir = Join-Path $temp "demo\bundleV2"
        $worktreeDir = Join-Path $temp ".claude\worktrees\agent-a\demo\scripts\mods\demo"
        [System.IO.Directory]::CreateDirectory($bundleDir) | Out-Null
        [System.IO.Directory]::CreateDirectory($worktreeDir) | Out-Null
        $bundleCopy = Join-Path $bundleDir "_lib_orphan.lua"
        $worktreeCopy = Join-Path $worktreeDir "_lib_orphan.lua"
        [System.IO.File]::WriteAllBytes($bundleCopy, [byte[]](68, 10))
        [System.IO.File]::WriteAllBytes($worktreeCopy, [byte[]](69, 10))
        & (Join-Path $libDir "sync-shared-libs.ps1") -RepoRoot $temp -Quiet *>$null
        if ($LASTEXITCODE -ne 0) { throw "census fired on excluded build/worktree output" }
        Remove-Item -LiteralPath $bundleCopy -Force
        Remove-Item -LiteralPath $worktreeCopy -Force

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
