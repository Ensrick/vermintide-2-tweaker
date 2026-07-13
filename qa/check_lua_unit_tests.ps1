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

$arguments = @($runner)
if ($SelfTest) { $arguments += '--self-test' }

if (-not $Quiet) {
    Write-Host ("=== lua_unit_tests ({0}) ===" -f $(if ($SelfTest) { 'self-test' } else { 'suite' })) -ForegroundColor Cyan
}

& $luaExe @arguments
$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Host "[lua_unit_tests] ERROR -- runner exited $code." -ForegroundColor Red
    exit 2
}
exit 0
