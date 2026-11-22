# check_integration.ps1 - the engine-free integration tier (WP-T-03): loads the real vanilla data tables from the
# decompile in plain Lua 5.1 (the vendored qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe) and checks mod data against
# them in seconds. Evidence class S.
#
# The decompile comes from -DecompileRoot, else $env:VT2_DECOMPILE_ROOT, else ../Vermintide-2-Source-Code next to
# this checkout or next to its primary checkout. Without it (hosted CI has none) the check prints
# "[integration] SKIP - decompile not available" and exits 0. The decompile is proprietary: nothing is copied from it.
# It runs qa/integration/run.lua with a mod map (VMF mod id -> folder from tools/mod-inventory.psd1, and the list of
# Character Weapon Variants modules), prints the vanilla files executed, the table sizes and one line per suite
# (qa/integration/suites/), and exits 2 when a suite reports a problem, 3 when a vanilla file no longer loads.
# -SelfTest runs every suite against a planted bad key (and a planted stub value) and requires each to be caught.

[CmdletBinding()]
param(
    [string]$DecompileRoot = '',
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$luaExe = Join-Path $PSScriptRoot 'lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$runLua = Join-Path $PSScriptRoot 'integration\run.lua'

$candidates = @()
if ($DecompileRoot) { $candidates += $DecompileRoot }
elseif ($env:VT2_DECOMPILE_ROOT) { $candidates += $env:VT2_DECOMPILE_ROOT }
else {
    $candidates += (Join-Path $repoRoot '..\Vermintide-2-Source-Code')
    try {
        $common = (& git -C $repoRoot rev-parse --path-format=absolute --git-common-dir 2>$null)
        if ($common) { $candidates += (Join-Path (Split-Path (Split-Path $common)) 'Vermintide-2-Source-Code') }
    } catch { }
}
$decompile = $null
foreach ($c in $candidates) { if ($c -and (Test-Path -LiteralPath (Join-Path $c 'scripts\settings') -PathType Container)) { $decompile = (Resolve-Path -LiteralPath $c).Path; break } }
if (-not $decompile) { Write-Host '[integration] SKIP - decompile not available'; exit 0 }
if (-not (Test-Path -LiteralPath $luaExe -PathType Leaf)) { Write-Host "[integration] ERROR - vendored Lua missing: $luaExe" -ForegroundColor Red; exit 2 }

function ConvertTo-LuaString([string]$s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }
$inventory = Import-PowerShellDataFile -LiteralPath (Join-Path $repoRoot 'tools\mod-inventory.psd1')
$dirs = @($inventory.Mods | Where-Object { $_.ModId -and $_.Dir } | ForEach-Object { "[$(ConvertTo-LuaString ([string]$_.ModId))] = $(ConvertTo-LuaString ([string]$_.Dir))" })
$cwvDir = Join-Path $repoRoot 'character_weapon_variants\scripts\mods\character_weapon_variants'
$cwv = @(Get-ChildItem -LiteralPath $cwvDir -File -Filter '_cwv_*.lua' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { ConvertTo-LuaString $_.Name })
$map = "return {`n  dirs = { $($dirs -join ', ') },`n  files = { cwv_modules = { $($cwv -join ', ') } },`n}`n"
$mapFile = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-integration-map-' + [guid]::NewGuid().ToString('N') + '.lua')
try {
    [System.IO.File]::WriteAllText($mapFile, $map, [System.Text.UTF8Encoding]::new($false))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $luaArgs = @($runLua, ($decompile -replace '\\', '/'), ($repoRoot -replace '\\', '/'), $mapFile)
    if ($SelfTest) { $luaArgs += 'selftest' }
    $out = & $luaExe @luaArgs 2>&1
    $code = $LASTEXITCODE
    $sw.Stop()
}
finally { if (Test-Path -LiteralPath $mapFile) { Remove-Item -LiteralPath $mapFile -Force } }

$head = (& git -C $decompile rev-parse --short HEAD 2>$null)
foreach ($line in @($out | ForEach-Object { "$_" })) {
    if (-not $Quiet -or $line -match '^(vanilla files executed|ItemMasterList=|suite |LOAD FAILED|STOP|selftest)' -or $line -match '^\s+problem:') { Write-Host "[integration] $line" }
}
$mode = if ($SelfTest) { 'self-test' } else { 'check' }
if ($code -eq 0) { Write-Host ("[integration] OK - {0} passed in {1:N1} s (decompile {2})" -f $mode, $sw.Elapsed.TotalSeconds, $(if ($head) { $head } else { $decompile })) -ForegroundColor Green; exit 0 }
if ($code -eq 3) { Write-Host '[integration] FAILED - a vanilla data file no longer loads (see LOAD FAILED above)' -ForegroundColor Red; exit 2 }
Write-Host "[integration] FAILED - $mode reported problems (exit $code)" -ForegroundColor Red
exit 2
