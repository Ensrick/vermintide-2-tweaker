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

# Required historical-owner identity is proven BEFORE its new healthy oracle.
# The tracked Lua harness owns the sole strict reverse-delta implementation.
function Assert-JavelinPriorRuntimeIdentity {
    param([string]$LuaExecutable, [string]$Exporter, [string]$Repository)
    foreach ($value in @($LuaExecutable, $Exporter, $Repository)) {
        if ($value.Contains('"') -or $value.Contains([string][char]10) -or $value.Contains([string][char]13)) { throw 'Invalid fixed Javelin exporter path' }
    }
    $fixture = Join-Path (Split-Path -Parent $Exporter) 'cwv_javelin_construction_source.lua'
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $hash = [Security.Cryptography.SHA256]::Create()
    $process = New-Object Diagnostics.Process
    try {
        $text = [IO.File]::ReadAllText($fixture).Replace(([string][char]13 + [char]10), [string][char]10)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($utf8.GetBytes($text)))).Replace('-', '').ToLowerInvariant()
        if ($actual -cne '5fecf5a102b910f7b15a9a4eda309dccc0836c354816b56f784eea2e35671911') { throw 'Required Javelin native closure hash mismatch' }
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $LuaExecutable
        $start.Arguments = '"' + $Exporter + '" --export-prior-javelin "' + $Repository + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = $utf8
        $start.StandardErrorEncoding = $utf8
        $process.StartInfo = $start
        if (-not $process.Start()) { throw 'Javelin identity exporter did not start' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Javelin identity exporter timed out' }
        $output = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('Javelin identity exporter failed: ' + $errorText) }
        $normalized = $output.Replace(([string][char]13 + [char]10), [string][char]10)
        $bytes = $utf8.GetBytes($normalized)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        # The pinned historical owner is LF UTF8 without BOM: raw == normalized.
        if ($bytes.Length -ne 82213 -or $actual -cne '09f5ff3e8378bb9ef81780e69f6b410a09be3ad72dcad01f13bdd3ba07608d92') { throw 'Complete prior Javelin runtime identity mismatch' }
    }
    finally { $process.Dispose(); $hash.Dispose() }
}

# Same fixed exporter protocol; complete prior core bytes never persist.
function Assert-ShortswordPriorCoreIdentity {
    param([string]$LuaExecutable, [string]$Exporter, [string]$Repository)
    foreach ($value in @($LuaExecutable, $Exporter, $Repository)) {
        if ($value.Contains('"') -or $value.Contains([string][char]10) -or $value.Contains([string][char]13)) { throw 'Invalid fixed Shortsword exporter path' }
    }
    $fixture = Join-Path (Split-Path -Parent $Exporter) 'cwv_shortsword_construction_source.lua'
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $hash = [Security.Cryptography.SHA256]::Create()
    $process = New-Object Diagnostics.Process
    try {
        $text = [IO.File]::ReadAllText($fixture).Replace(([string][char]13 + [char]10), [string][char]10)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($utf8.GetBytes($text)))).Replace('-', '').ToLowerInvariant()
        if ($actual -cne 'd9a9b62746679ee6bfd5eefff02213ecb29ac82047d8e1f775ff6f8d3aeeaf53') { throw 'Required Shortsword native closure hash mismatch' }
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $LuaExecutable
        $start.Arguments = '"' + $Exporter + '" --export-prior-shortsword-core "' + $Repository + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = $utf8
        $start.StandardErrorEncoding = $utf8
        $process.StartInfo = $start
        if (-not $process.Start()) { throw 'Shortsword identity exporter did not start' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Shortsword identity exporter timed out' }
        $output = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('Shortsword identity exporter failed: ' + $errorText) }
        $normalized = $output.Replace(([string][char]13 + [char]10), [string][char]10)
        $bytes = $utf8.GetBytes($normalized)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        # The pinned historical owner is LF UTF8 without BOM: raw == normalized.
        if ($bytes.Length -ne 66493 -or $actual -cne 'db221e2396ba9054475ce730cce9880785d47e334ea3b26b8dc3f0bd1a9cb35a') { throw 'Complete prior Shortsword runtime identity mismatch' }
    }
    finally { $process.Dispose(); $hash.Dispose() }
}
function Assert-ElvenShieldPriorCoreIdentity {
    param([string]$LuaExecutable, [string]$Exporter, [string]$Repository)
    foreach ($value in @($LuaExecutable, $Exporter, $Repository)) {
        if ($value.Contains('"') -or $value.Contains([string][char]10) -or $value.Contains([string][char]13)) { throw 'Invalid fixed ElvenShield exporter path' }
    }
    $fixture = Join-Path (Split-Path -Parent $Exporter) 'cwv_elven_shield_construction_source.lua'
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $hash = [Security.Cryptography.SHA256]::Create()
    $process = New-Object Diagnostics.Process
    try {
        $text = [IO.File]::ReadAllText($fixture).Replace(([string][char]13 + [char]10), [string][char]10)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($utf8.GetBytes($text)))).Replace('-', '').ToLowerInvariant()
        if ($actual -cne '9c303ada988fa2ebd5c3b7c530461b9e787464cc153ac87d18687f5035f10f45') { throw 'Required ElvenShield native closure hash mismatch' }
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $LuaExecutable
        $start.Arguments = '"' + $Exporter + '" --export-prior-elven-shield-core "' + $Repository + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = $utf8
        $start.StandardErrorEncoding = $utf8
        $process.StartInfo = $start
        if (-not $process.Start()) { throw 'ElvenShield identity exporter did not start' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'ElvenShield identity exporter timed out' }
        $output = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('ElvenShield identity exporter failed: ' + $errorText) }
        $normalized = $output.Replace(([string][char]13 + [char]10), [string][char]10)
        $bytes = $utf8.GetBytes($normalized)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        # The pinned historical owner is LF UTF8 without BOM: raw == normalized.
        if ($bytes.Length -ne 67523 -or $actual -cne '2aeb3673d4a05a1cd257f18a24d66c2e38e9b2a3957a6dd8eb4afc8af46a7a08') { throw 'Complete prior ElvenShield runtime identity mismatch' }
    }
    finally { $process.Dispose(); $hash.Dispose() }
}
function Assert-GreataxePriorCoreIdentity {
    param([string]$LuaExecutable, [string]$Exporter, [string]$Repository)
    foreach ($value in @($LuaExecutable, $Exporter, $Repository)) {
        if ($value.Contains('"') -or $value.Contains([string][char]10) -or $value.Contains([string][char]13)) { throw 'Invalid fixed Greataxe exporter path' }
    }
    $fixture = Join-Path (Split-Path -Parent $Exporter) 'cwv_greataxe_construction_source.lua'
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    $hash = [Security.Cryptography.SHA256]::Create()
    $process = New-Object Diagnostics.Process
    try {
        $text = [IO.File]::ReadAllText($fixture).Replace(([string][char]13 + [char]10), [string][char]10)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($utf8.GetBytes($text)))).Replace('-', '').ToLowerInvariant()
        if ($actual -cne '215cfae8dca6a05008c783c9b1773b7d8ad801665538c013cdf5246bce2001d2') { throw 'Required Greataxe native closure hash mismatch' }
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $LuaExecutable
        $start.Arguments = '"' + $Exporter + '" --export-prior-greataxe-core "' + $Repository + '"'
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = $utf8
        $start.StandardErrorEncoding = $utf8
        $process.StartInfo = $start
        if (-not $process.Start()) { throw 'Greataxe identity exporter did not start' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(10000)) { $process.Kill(); throw 'Greataxe identity exporter timed out' }
        $output = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ('Greataxe identity exporter failed: ' + $errorText) }
        $normalized = $output.Replace(([string][char]13 + [char]10), [string][char]10)
        $bytes = $utf8.GetBytes($normalized)
        $actual = ([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        # The pinned historical owner is LF UTF8 without BOM: raw == normalized.
        if ($bytes.Length -ne 68110 -or $actual -cne 'd110baa4df99a212ab1f14a62fd127ace8a96dac4dd4a13f7c32eeff2460309d') { throw 'Complete prior Greataxe runtime identity mismatch' }
    }
    finally { $process.Dispose(); $hash.Dispose() }
}
$tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$inventoryRoot = [IO.Path]::GetFullPath((Join-Path $tempParent ('vt2-lua-suite-' + [guid]::NewGuid().ToString('N'))))
$inventoryCreated = $false
$exitCode = 2
try {
    if (-not $SelfTest) {
        $exporter = Join-Path $luaRoot 'fixtures\cwv_javelin_construction_harness.lua'
        Assert-JavelinPriorRuntimeIdentity -LuaExecutable $luaExe -Exporter $exporter -Repository (Split-Path -Parent $PSScriptRoot)
        $shortswordExporter = Join-Path $luaRoot 'fixtures\cwv_shortsword_construction_harness.lua'
        Assert-ShortswordPriorCoreIdentity -LuaExecutable $luaExe -Exporter $shortswordExporter -Repository (Split-Path -Parent $PSScriptRoot)
        $elvenShieldExporter = Join-Path $luaRoot 'fixtures\cwv_elven_shield_construction_harness.lua'
        Assert-ElvenShieldPriorCoreIdentity -LuaExecutable $luaExe -Exporter $elvenShieldExporter -Repository (Split-Path -Parent $PSScriptRoot)
        $greataxeExporter = Join-Path $luaRoot 'fixtures\cwv_greataxe_construction_harness.lua'
        Assert-GreataxePriorCoreIdentity -LuaExecutable $luaExe -Exporter $greataxeExporter -Repository (Split-Path -Parent $PSScriptRoot)
    }
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

        # Importing the discovered registration function without calling it
        # must not count as coverage. Exercise the unmodified real runner;
        # this probe adds only an unused transitive require in one suite.
        $importOnlyProbe = Join-Path $inventoryRoot 'import-only-probe.lua'
        $probeSource = @'
local runner, inventory, sentinel = arg[1], arg[2], arg[3]
local native_require = require
package.preload[sentinel] = function() return function() end end
local injected = false
_G.require = function(name)
    local registration = native_require(name)
    if not injected and type(name) == "string" and name:match("^test_")
            and type(registration) == "function" then
        injected = true
        return function(...)
            require(sentinel)
            return registration(...)
        end
    end
    return registration
end
arg[0], arg[1], arg[2], arg[3] = runner, "--suite-manifest", inventory, nil
dofile(runner)
'@
        [IO.File]::WriteAllText($importOnlyProbe, $probeSource, (New-Object Text.UTF8Encoding($false)))
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = @(& $luaExe $importOnlyProbe $runner $inventoryPath $sentinel 2>&1)
            $negativeCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        if ($negativeCode -ne 2 -or -not ($output | Where-Object { "$_".Contains($needle) })) {
            throw "real runner did not reject the import-only suite at its coverage boundary (exit $negativeCode)"
        }
        Write-Host '[lua_suite_manifest] SELF-TEST OK -- the real runner rejects an import-only suite.'

        # A registration error must restore an inherited require by exact raw
        # shape, not create a persistent raw field or replace its metatable.
        $restoreProbe = Join-Path $inventoryRoot 'restore-require-probe.lua'
        $probeSource = @'
local runner, inventory = arg[1], arg[2]
local native_require, native_exit = require, os.exit
local previous_meta = getmetatable(_G)
local injected = false
local function inherited_require(name)
    local registration = native_require(name)
    if not injected and type(name) == "string" and name:match("^test_")
            and type(registration) == "function" then
        injected = true
        return function() error("planted suite registration error") end
    end
    return registration
end
local probe_meta = { __index = function(_, name)
    if name == "require" then return inherited_require end
end }
rawset(_G, "require", nil)
setmetatable(_G, probe_meta)
os.exit = function(code)
    local restored = rawget(_G, "require") == nil and getmetatable(_G) == probe_meta
    io.write(restored and "[lua_suite_manifest] REQUIRE RAW SHAPE RESTORED\n"
        or "[lua_suite_manifest] REQUIRE RAW SHAPE LOST\n")
    os.exit = native_exit
    setmetatable(_G, previous_meta)
    rawset(_G, "require", native_require)
    native_exit(restored and code or 3)
end
arg[0], arg[1], arg[2] = runner, "--suite-manifest", inventory
dofile(runner)
'@
        [IO.File]::WriteAllText($restoreProbe, $probeSource, (New-Object Text.UTF8Encoding($false)))
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = @(& $luaExe $restoreProbe $runner $inventoryPath 2>&1)
            $negativeCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousPreference }
        if ($negativeCode -ne 2 -or
            -not ($output | Where-Object { "$_".Contains('[lua_suite_manifest] REQUIRE RAW SHAPE RESTORED') }) -or
            -not ($output | Where-Object { "$_".Contains('planted suite registration error') })) {
            throw "real runner did not restore inherited require after registration failure (exit $negativeCode)"
        }
        Write-Host '[lua_suite_manifest] SELF-TEST OK -- registration errors restore exact require raw shape.'
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
