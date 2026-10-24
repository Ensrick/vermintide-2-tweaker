# check_lua_unit_tests.ps1 - offline Lua 5.1 host-unit gate (issue #544).

[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$luaRoot = Join-Path $PSScriptRoot 'lua'
$runtimeRoot = Join-Path $luaRoot 'vendor\lua-5.1.5-win64'
$luaExe = Join-Path $runtimeRoot 'lua5.1.exe'
$runner = Join-Path $luaRoot 'run.lua'

if (-not (Test-Path -LiteralPath $luaExe -PathType Leaf)) {
    Write-Host '[lua_unit_tests] ERROR -- vendored Lua 5.1 runtime is missing.' -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) {
    Write-Host '[lua_unit_tests] ERROR -- qa/lua/run.lua is missing.' -ForegroundColor Red
    exit 2
}

$expectedHashes = @{
    'lua5.1.exe' = 'C9BF063327F6A719AA2D2C25A13A6FB006EBA3F23B53BCD6A629DC04507C18B6'
    'lua5.1.dll' = '0D620E2AC810A76CE6D43CC8EFBA7B2329611BE37A8B16D55BB58E09B059FC6C'
    'lua5.1.exe.manifest' = '639F0C8BA12E332A160AFA2832CF7FF69482A71A1D7ECBCA0B3166953F2B1415'
    'lua5.1.dll.manifest' = '639F0C8BA12E332A160AFA2832CF7FF69482A71A1D7ECBCA0B3166953F2B1415'
    'Microsoft.VC80.CRT\Microsoft.VC80.CRT.manifest' = 'BC6BA66A1E93C8FAE1C36A29A8E3B2500F3EE1950A99214F219F6D11058CF55C'
    'Microsoft.VC80.CRT\msvcr80.dll' = '2219E15B66ABA301909128E6775E0B4F8B28B529B3EC087161EDAE55E2676C65'
}
foreach ($fileName in $expectedHashes.Keys) {
    $path = Join-Path $runtimeRoot $fileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Write-Host "[lua_unit_tests] ERROR -- vendored runtime file missing: $fileName" -ForegroundColor Red
        exit 2
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actual -ne $expectedHashes[$fileName]) {
        Write-Host "[lua_unit_tests] ERROR -- SHA-256 mismatch for $fileName." -ForegroundColor Red
        exit 2
    }
}

function Get-LuaSuiteNames {
    param([Parameter(Mandatory = $true)][string]$TestRoot)

    # Discovery is independent of the explicit Lua list. Imported children are
    # allowed, but every physical test file must be reached during registration.
    $files = @(Get-ChildItem -LiteralPath $TestRoot -Filter 'test_*.lua' -File)
    [string[]]$names = @($files | ForEach-Object { $_.BaseName })
    if ($names.Count -eq 0) { throw "No Lua test suites discovered in $TestRoot" }
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return $names
}

$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$inventoryRoot = [IO.Path]::GetFullPath((Join-Path $tempParent ('vt2-lua-suite-' + [guid]::NewGuid().ToString('N'))))
$inventoryCreated = $false
$exitCode = 2
try {
    [void][IO.Directory]::CreateDirectory($inventoryRoot)
    $inventoryCreated = $true
    $inventoryPath = Join-Path $inventoryRoot 'suites.txt'
    $names = @(Get-LuaSuiteNames -TestRoot (Join-Path $luaRoot 'tests'))
    [IO.File]::WriteAllText($inventoryPath, (($names -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    $arguments = @($runner, '--suite-manifest', $inventoryPath)
    if ($SelfTest) { $arguments = @($runner, '--self-test') }

    if (-not $Quiet) {
        Write-Host ("=== lua_unit_tests ({0}) ===" -f $(if ($SelfTest) { 'self-test' } else { 'suite' })) -ForegroundColor Cyan
    }
    & $luaExe @arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "runner exited $code" }

    if ($SelfTest) {
        # Exercise actual discovery AND the real runner's coverage call. A
        # comment naming this suite, or disconnecting the call, cannot satisfy
        # this negative integration test. No repository file is created/edited.
        $fixture = Join-Path $inventoryRoot 'discovery'
        [void][IO.Directory]::CreateDirectory($fixture)
        $sentinel = 'test_1700_unlisted_sentinel'
        [IO.File]::WriteAllText((Join-Path $fixture "$sentinel.lua"), "return function() end`n")
        [IO.File]::WriteAllText((Join-Path $fixture 'not_a_suite.txt'), 'ignored')
        $discovered = @(Get-LuaSuiteNames -TestRoot $fixture)
        if ($discovered.Count -ne 1 -or $discovered[0] -cne $sentinel) {
            throw 'suite file discovery did not identify the unlisted fixture exactly'
        }
        [IO.File]::WriteAllText($inventoryPath, (($discovered -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
        $previousPreference = $ErrorActionPreference
        try {
            # PS5.1 converts native stderr to error records; retain the real
            # exit and text rather than throwing before we can inspect them.
            $ErrorActionPreference = 'Continue'
            $output = @(& $luaExe $runner '--suite-manifest' $inventoryPath 2>&1)
            $negativeCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        $needle = "[lua_suite_manifest] ERROR -- unreached test suites: $sentinel"
        if ($negativeCode -ne 2 -or -not ($output | Where-Object { "$_".Contains($needle) })) {
            throw "real runner did not reject the discovered unlisted suite (exit $negativeCode)"
        }
        Write-Host '[lua_suite_manifest] SELF-TEST OK -- actual discovery and runner reject an unlisted suite.'
    }
    $exitCode = 0
}
catch {
    Write-Host "[lua_unit_tests] ERROR -- $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    try {
        if ($inventoryCreated -and (Test-Path -LiteralPath $inventoryRoot)) {
            $resolved = (Get-Item -LiteralPath $inventoryRoot -Force).FullName
            $prefix = $tempParent + [IO.Path]::DirectorySeparatorChar
            if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                -not (Split-Path $resolved -Leaf).StartsWith('vt2-lua-suite-', [StringComparison]::Ordinal) -or
                ((Get-Item -LiteralPath $inventoryRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Refusing cleanup outside the verified owned inventory directory: $resolved"
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
    catch {
        # Keep the check's documented blocking exit even across a child-host
        # boundary; an unhandled PowerShell exception can otherwise exit 1,
        # which ordinary QA reserves for advisory findings.
        Write-Host "[lua_unit_tests] ERROR -- inventory cleanup failed: $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 2
    }
}
exit $exitCode
