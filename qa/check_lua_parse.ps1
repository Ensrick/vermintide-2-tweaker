# check_lua_parse.ps1 - blocking syntax gate for active mod Lua (#1223).
#
# PUC Lua 5.1 cannot parse Vermintide's supported `goto` extension. The
# repository's pinned Luacheck binary accepts that authored syntax, so this
# check disables every semantic warning class and retains only structural parse
# errors. This is not proof of the exact VT2 runtime dialect. Ordinary Luacheck
# remains advisory; malformed source is always blocking.

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
$luaParseBatchSize = 40

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
        return [pscustomobject]@{
            ExitCode = 99
            ParserExitCode = $null
            Output = @('No Lua parse targets were supplied.')
        }
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
    $parserExitCode = $LASTEXITCODE
    $exitCode = if ($parserExitCode -eq 0) {
        0
    }
    elseif ($parserExitCode -eq 2) {
        2
    }
    else {
        99
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        ParserExitCode = $parserExitCode
        Output = $output
    }
}

function Invoke-ActiveLuaParse {
    param(
        [object[]]$Mods,
        [string]$Root = $repoRoot
    )

    $modRecords = @($Mods | Where-Object { $null -ne $_ })
    if ($modRecords.Count -eq 0) {
        return [pscustomobject]@{
            ExitCode = 99
            FileCount = 0
            BatchCount = 0
            Output = @('The active-mod inventory contains no mod records.')
        }
    }

    $files = @()
    foreach ($mod in $modRecords) {
        $modDir = [string]$mod.Dir
        if ([string]::IsNullOrWhiteSpace($modDir)) {
            return [pscustomobject]@{
                ExitCode = 99
                FileCount = $files.Count
                BatchCount = 0
                Output = @('An active-mod inventory record has no Dir value.')
            }
        }
        $scriptsRoot = Join-Path $Root (Join-Path $modDir 'scripts\mods')
        if (-not (Test-Path -LiteralPath $scriptsRoot -PathType Container)) {
            return [pscustomobject]@{
                ExitCode = 99
                FileCount = $files.Count
                BatchCount = 0
                Output = @("Active mod '$modDir' has no scripts/mods directory.")
            }
        }
        $modFiles = @(Get-ChildItem -LiteralPath $scriptsRoot -Filter '*.lua' -File -Recurse -Force |
            Sort-Object -Property FullName)
        if ($modFiles.Count -eq 0) {
            return [pscustomobject]@{
                ExitCode = 99
                FileCount = $files.Count
                BatchCount = 0
                Output = @("Active mod '$modDir' has no Lua sources to parse.")
            }
        }
        $files += @($modFiles | ForEach-Object { $_.FullName })
    }

    if ($files.Count -eq 0) {
        return [pscustomobject]@{
            ExitCode = 99
            FileCount = 0
            BatchCount = 0
            Output = @('The active-mod inventory resolved zero Lua sources.')
        }
    }

    $output = @()
    $batchCount = 0
    for ($offset = 0; $offset -lt $files.Count; $offset += $luaParseBatchSize) {
        $last = [Math]::Min($offset + $luaParseBatchSize - 1, $files.Count - 1)
        $batch = @($files[$offset..$last])
        $batchCount += 1
        $result = Invoke-LuaParse $batch
        $output += @($result.Output)
        if ($result.ExitCode -ne 0) {
            return [pscustomobject]@{
                ExitCode = $result.ExitCode
                ParserExitCode = $result.ParserExitCode
                FileCount = $files.Count
                BatchCount = $batchCount
                Output = $output
            }
        }
    }

    return [pscustomobject]@{
        ExitCode = 0
        ParserExitCode = 0
        FileCount = $files.Count
        BatchCount = $batchCount
        Output = $output
    }
}

function Invoke-SelfTest {
    Assert-LuaParser
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-lua-parse-' + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        $scriptsRoot = Join-Path $tempRoot 'alpha\scripts\mods\alpha'
        [System.IO.Directory]::CreateDirectory($scriptsRoot) | Out-Null
        $gotoPath = Join-Path $scriptsRoot 'good-001-goto.lua'
        $warningPath = Join-Path $scriptsRoot 'good-002-warning.lua'
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
        for ($i = 3; $i -le 41; $i += 1) {
            $path = Join-Path $scriptsRoot ('good-{0:D3}.lua' -f $i)
            [System.IO.File]::WriteAllText($path, "return $i`n")
        }

        $mods = @([pscustomobject]@{ Dir = 'alpha' })
        $valid = Invoke-ActiveLuaParse -Mods $mods -Root $tempRoot
        if ($valid.ExitCode -ne 0) {
            throw "Structural positive path failed: $($valid.Output -join [Environment]::NewLine)"
        }
        if ($valid.FileCount -ne 41 -or $valid.BatchCount -ne 2) {
            throw "Exact-file batching mismatch: expected 41 files in 2 batches, got $($valid.FileCount) in $($valid.BatchCount)."
        }

        $invalidPath = Join-Path $scriptsRoot 'zz-hidden-bad.lua'
        [System.IO.File]::WriteAllText($invalidPath, "local broken = function(`n")
        [System.IO.File]::SetAttributes($invalidPath, [System.IO.FileAttributes]::Hidden)
        $invalid = Invoke-ActiveLuaParse -Mods $mods -Root $tempRoot
        if ($invalid.ExitCode -ne 2) { throw "Planted hidden Lua syntax error returned $($invalid.ExitCode), expected 2." }
        if ($invalid.FileCount -ne 42 -or $invalid.BatchCount -ne 2) {
            throw "Hidden-file batching mismatch: expected 42 files in 2 batches, got $($invalid.FileCount) in $($invalid.BatchCount)."
        }
        if (($invalid.Output -join "`n") -notmatch '(?i)error|expected|syntax') {
            throw 'Planted Lua syntax failure produced no parse diagnostic.'
        }
        if (($invalid.Output -join "`n") -notmatch 'zz-hidden-bad\.lua') {
            throw 'Planted hidden Lua syntax failure did not name the exact file.'
        }

        $missingPath = Join-Path $scriptsRoot 'missing.lua'
        $missing = Invoke-LuaParse @($missingPath)
        if ($missing.ParserExitCode -lt 3 -or $missing.ExitCode -ne 99) {
            throw "Parser I/O failure was not classified as infrastructure: parser=$($missing.ParserExitCode), gate=$($missing.ExitCode)."
        }
        $empty = Invoke-ActiveLuaParse -Mods @() -Root $tempRoot
        if ($empty.ExitCode -ne 99) { throw 'Empty active-mod inventory did not fail as infrastructure.' }
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot -PathType Container) {
            $resolvedTemp = (Resolve-Path -LiteralPath $tempRoot).Path
            $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
            if (-not $resolvedTemp.StartsWith($systemTemp + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove self-test directory outside the system temp root: $resolvedTemp"
            }
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host '[check_lua_parse -SelfTest] OK - structural goto, warning-only, exact batching, hidden syntax, I/O, and empty-inventory paths verified.'
}

try {
    Assert-LuaParser
    if ($SelfTest) { Invoke-SelfTest; exit 0 }

    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Active-mod inventory is missing: $inventoryPath"
    }
    $inventory = Import-PowerShellDataFile -LiteralPath $inventoryPath
    $result = Invoke-ActiveLuaParse -Mods @($inventory.Mods) -Root $repoRoot
    if ($result.ExitCode -eq 2) {
        Write-Host '[check_lua_parse] FAILED - active mod Lua contains a syntax error.' -ForegroundColor Red
        $result.Output | ForEach-Object { Write-Host $_ }
        exit 2
    }
    if ($result.ExitCode -ne 0) {
        Write-Host '[check_lua_parse] ERROR - parser, inventory, or source I/O failed.' -ForegroundColor Red
        $result.Output | ForEach-Object { Write-Host $_ }
        exit 99
    }
    if (-not $Quiet) {
        Write-Host "[check_lua_parse] OK - $($result.FileCount) active mod Lua files structurally parse in $($result.BatchCount) exact-file batches."
    }
    exit 0
}
catch {
    Write-Host "[check_lua_parse] ERROR - $_" -ForegroundColor Red
    exit 99
}
