# run_ps51_parse_matrix.ps1 - parse a repository-relative script list with PS5.
# This file is byte-ASCII because it is itself part of the PS5 bootstrap set.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$ListPath,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$rootFull = (Resolve-Path $RepoRoot).Path.TrimEnd('\', '/')
$rootPrefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
$problems = @()

foreach ($relativePath in [System.IO.File]::ReadAllLines($ListPath, [System.Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $rootFull $relativePath))
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        $problems += "${relativePath}: path escapes repository root"
        continue
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $problems += "${relativePath}: script is missing"
        continue
    }

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($fullPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        $line = $parseError.Extent.StartLineNumber
        $column = $parseError.Extent.StartColumnNumber
        $problems += ("{0}:{1}:{2}: {3}" -f $relativePath, $line, $column, $parseError.Message)
    }
}

if ($problems.Count -gt 0) {
    Write-Host "[run_ps51_parse_matrix] FAILED:" -ForegroundColor Red
    foreach ($problem in $problems) { Write-Host "  X $problem" -ForegroundColor Red }
    exit 2
}

if (-not $Quiet) { Write-Host "[run_ps51_parse_matrix] PASS - invocation closure parses under Windows PowerShell 5.1." -ForegroundColor Green }
exit 0
