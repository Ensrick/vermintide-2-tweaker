# check_dofile_package_coverage.ps1
#
# Literal mod:dofile targets are runtime resources, not ordinary loose files.
# VMB compiles only Lua paths named by the owning resource package (or matched
# by its wildcard). A source-only helper therefore passes ordinary unit tests
# but becomes "Resource not found" in-game. This quick gate rejects that drift.

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$errors = New-Object System.Collections.Generic.List[string]
$inventory = Import-PowerShellDataFile (Join-Path $repoRoot "tools\mod-inventory.psd1")

function Read-Utf8([string]$Path) {
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

foreach ($modEntry in $inventory.Mods) {
    $modDir = Get-Item -LiteralPath (Join-Path $repoRoot $modEntry.Dir)

    $packageRoot = Join-Path $modDir.FullName "resource_packages"
    $scriptRoot = Join-Path $modDir.FullName "scripts"
    if (-not (Test-Path -LiteralPath $packageRoot) -or
        -not (Test-Path -LiteralPath $scriptRoot)) {
        continue
    }

    $packageEntries = New-Object System.Collections.Generic.List[string]
    foreach ($packageFile in Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter "*.package") {
        foreach ($match in [regex]::Matches((Read-Utf8 $packageFile.FullName), '"([^"]+)"')) {
            $packageEntries.Add($match.Groups[1].Value)
        }
    }

    foreach ($luaFile in Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter "*.lua") {
        $lineNumber = 0
        foreach ($line in [System.IO.File]::ReadAllLines($luaFile.FullName, [System.Text.Encoding]::UTF8)) {
            $lineNumber++
            $colonCallIndex = $line.IndexOf("mod:dofile")
            $dotCallIndex = $line.IndexOf("mod.dofile")
            $callIndex = if ($colonCallIndex -ge 0 -and $dotCallIndex -ge 0) {
                [Math]::Min($colonCallIndex, $dotCallIndex)
            } elseif ($colonCallIndex -ge 0) {
                $colonCallIndex
            } else {
                $dotCallIndex
            }
            $commentIndex = $line.IndexOf("--")
            if ($callIndex -lt 0 -or ($commentIndex -ge 0 -and $commentIndex -lt $callIndex)) {
                continue
            }

            $targets = New-Object System.Collections.Generic.List[string]
            foreach ($match in [regex]::Matches($line, 'mod:dofile\s*\(\s*["'']([^"'']+)["'']\s*\)')) {
                $targets.Add($match.Groups[1].Value)
            }
            foreach ($match in [regex]::Matches($line, 'mod\.dofile\s*\(\s*mod\s*,\s*["'']([^"'']+)["'']')) {
                $targets.Add($match.Groups[1].Value)
            }
            foreach ($match in [regex]::Matches($line, 'pcall\s*\(\s*mod\.dofile\s*,\s*mod\s*,\s*["'']([^"'']+)["'']')) {
                $targets.Add($match.Groups[1].Value)
            }

            foreach ($target in $targets) {
                $sourcePath = Join-Path $modDir.FullName (($target -replace '/', '\') + ".lua")
                if (-not (Test-Path -LiteralPath $sourcePath)) {
                    $errors.Add("$($modDir.Name): $($luaFile.Name):$lineNumber dofile target has no source file: $target.lua")
                    continue
                }

                $covered = $false
                foreach ($entry in $packageEntries) {
                    if ($entry -eq $target -or ($entry.Contains("*") -and $target -like $entry)) {
                        $covered = $true
                        break
                    }
                }
                if (-not $covered) {
                    $errors.Add("$($modDir.Name): $($luaFile.Name):$lineNumber dofile target omitted from resource package: $target")
                }
            }
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host "[check_dofile_package_coverage] FAIL - $($errors.Count) error(s)" -ForegroundColor Red
    foreach ($errorText in $errors) { Write-Host "  ERROR: $errorText" -ForegroundColor Red }
    exit 2
}

if (-not $Quiet) {
    Write-Host "[check_dofile_package_coverage] OK - literal mod:dofile targets are package-covered" -ForegroundColor Green
}
exit 0
