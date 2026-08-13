# check_lua_parse.ps1 - blocking syntax gate for active mod Lua (#1223).
#
# PUC Lua 5.1 cannot parse Vermintide's supported `goto` extension. The
# repository's pinned Luacheck binary uses a LuaJIT-compatible parser, so this
# check disables every semantic warning class and retains only parse errors.
# Ordinary Luacheck remains advisory; syntax validity is always blocking.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$repoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$luacheck = Join-Path $repoRoot 'tools\luacheck\luacheck.exe'
$inventoryPath = Join-Path $repoRoot 'tools\mod-inventory.psd1'
$expectedLuacheckSha256 = '0F1C69C4D09F1EBB4D8DF14C215E4553E2E639BD4CB7BF3C639B0DAA6198317B'

function Assert-LuaParser {
    if (-not (Test-Path -LiteralPath $luacheck -PathType Leaf)) {
        throw "Vendored Lua parser is missing: $luacheck"
    }
    $actual = (Get-FileHash -LiteralPath $luacheck -Algorithm SHA256).Hash
    if ($actual -ne $expectedLuacheckSha256) {
        throw "Vendored Lua parser SHA-256 mismatch: expected $expectedLuacheckSha256, got $actual"
    }
}

function Invoke-LuaParse([string[]]$Targets) {
    if (-not $Targets -or $Targets.Count -eq 0) {
        return [pscustomobject]@{ ExitCode = 2; Output = @('No Lua parse targets were supplied.') }
    }

    $arguments = @($Targets) + @(
        '--no-config',
        '--std', 'luajit',
        '--ignore', '1', '2', '3', '4', '5', '6',
        '--no-max-line-length',
        '--no-max-code-line-length',
        '--no-max-string-line-length',
        '--no-max-comment-line-length',
        '--formatter', 'plain',
        '--no-color',
        '--no-cache'
    )
    $output = @(& $luacheck @arguments 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Invoke-SelfTest {
    Assert-LuaParser
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-lua-parse-' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        $gotoPath = Join-Path $tempRoot 'goto.lua'
        $warningPath = Join-Path $tempRoot 'warnings.lua'
        $invalidPath = Join-Path $tempRoot 'invalid.lua'
        [System.IO.File]::WriteAllText($gotoPath, @'
local function first_true(values)
    local found
    for i = 1, #values do
        if not values[i] then goto continue end
        found = i
        ::continue::
    end
    return found
end
return first_true
'@)
        [System.IO.File]::WriteAllText($warningPath, "undeclared_global = 1`n")
        [System.IO.File]::WriteAllText($invalidPath, "local broken = function(`n")

        $valid = Invoke-LuaParse @($gotoPath, $warningPath)
        if ($valid.ExitCode -ne 0) {
            throw "LuaJIT-compatible positive path failed: $($valid.Output -join [Environment]::NewLine)"
        }
        $invalid = Invoke-LuaParse @($invalidPath)
        if ($invalid.ExitCode -eq 0) { throw 'Planted Lua syntax error was accepted.' }
        if (($invalid.Output -join "`n") -notmatch '(?i)error|expected|syntax') {
            throw 'Planted Lua syntax failure produced no parse diagnostic.'
        }
    }
    finally {
        foreach ($path in @($gotoPath, $warningPath, $invalidPath)) {
            if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
        if (Test-Path -LiteralPath $tempRoot -PathType Container) {
            Remove-Item -LiteralPath $tempRoot -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host '[check_lua_parse -SelfTest] OK - LuaJIT goto, warning-only, and planted syntax paths verified.'
}

try {
    Assert-LuaParser
    if ($SelfTest) { Invoke-SelfTest; exit 0 }

    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Active-mod inventory is missing: $inventoryPath"
    }
    $inventory = Import-PowerShellDataFile -LiteralPath $inventoryPath
    $targets = @()
    $fileCount = 0
    foreach ($mod in @($inventory.Mods)) {
        $scriptsRoot = Join-Path $repoRoot (Join-Path ([string]$mod.Dir) 'scripts\mods')
        if (-not (Test-Path -LiteralPath $scriptsRoot -PathType Container)) {
            throw "Active mod '$($mod.Dir)' has no scripts/mods directory."
        }
        $count = @(Get-ChildItem -LiteralPath $scriptsRoot -Filter '*.lua' -File -Recurse).Count
        if ($count -eq 0) { throw "Active mod '$($mod.Dir)' has no Lua sources to parse." }
        $fileCount += $count
        $targets += $scriptsRoot
    }
    if ($fileCount -eq 0) { throw 'The active-mod inventory resolved zero Lua sources.' }

    $result = Invoke-LuaParse $targets
    if ($result.ExitCode -ne 0) {
        Write-Host '[check_lua_parse] FAILED - active mod Lua contains a syntax error.' -ForegroundColor Red
        $result.Output | ForEach-Object { Write-Host $_ }
        exit 2
    }
    if (-not $Quiet) {
        Write-Host "[check_lua_parse] OK - $fileCount active mod Lua files parse under the pinned LuaJIT-compatible grammar."
    }
    exit 0
}
catch {
    Write-Host "[check_lua_parse] ERROR - $_" -ForegroundColor Red
    exit 2
}
