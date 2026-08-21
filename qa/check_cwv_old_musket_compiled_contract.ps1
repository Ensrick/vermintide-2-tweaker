# check_cwv_old_musket_compiled_contract.ps1
#
# Post-compiler issue #1155 gate. The dependency-free Python reader parses the
# checked-in CWV root bundle and proves final VT2 v189 unit geometry/material
# state; source FBX hashes alone cannot catch a stale or mis-oriented compile.

[CmdletBinding()]
param(
    [string]$BundlePath,
    [string]$ContractPath,
    [string]$Python,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$validator = Join-Path $PSScriptRoot 'cwv_old_musket_compiled_contract.py'
if (-not $BundlePath) {
    $BundlePath = Join-Path $repoRoot 'character_weapon_variants\bundleV2\0f038849957ad1b7.mod_bundle'
}
if (-not $ContractPath) {
    $ContractPath = Join-Path $repoRoot 'character_weapon_variants\tools\old_musket_asset_contract.json'
}

function Fail([string]$Message) {
    Write-Host "[check_cwv_old_musket_compiled_contract] FAILED - $Message" -ForegroundColor Red
    exit 2
}

if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    Fail "compiled-contract parser missing: $validator"
}
if (-not (Test-Path -LiteralPath $BundlePath -PathType Leaf)) {
    Fail "compiled root bundle missing: $BundlePath"
}
if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    Fail "Old Musket asset contract missing: $ContractPath"
}

$pythonCommand = $null
$pythonPrefix = @()
$candidates = @()
if ($Python) {
    $resolved = Get-Command -Name $Python -ErrorAction SilentlyContinue
    if (-not $resolved -and (Test-Path -LiteralPath $Python -PathType Leaf)) {
        $candidates += ,@($Python, @())
    }
    elseif ($resolved) {
        $candidates += ,@($resolved.Source, @())
    }
    else {
        Fail "requested Python 3 host not found: $Python"
    }
}
else {
    foreach ($candidate in @(
        @('py', @('-3')),
        @('python3', @()),
        @('python', @())
    )) {
        $resolved = Get-Command -Name $candidate[0] -ErrorAction SilentlyContinue
        if ($resolved) { $candidates += ,@($resolved.Source, @($candidate[1])) }
    }
}

foreach ($candidate in $candidates) {
    $command = $candidate[0]
    $prefix = @($candidate[1])
    & $command @prefix -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 3)' `
        2>$null
    if ($LASTEXITCODE -eq 0) {
        $pythonCommand = $command
        $pythonPrefix = $prefix
        break
    }
}

if (-not $pythonCommand) {
    Fail 'Python 3.9+ is unavailable (tried py -3, python3, and python)'
}

$arguments = @(
    $validator,
    '--bundle', $BundlePath,
    '--contract', $ContractPath
)
if ($Quiet) { $arguments += '--quiet' }

& $pythonCommand @pythonPrefix @arguments
$code = $LASTEXITCODE
if ($null -eq $code) { $code = 99 }
if ($code -notin @(0, 2, 99)) {
    Write-Host "[check_cwv_old_musket_compiled_contract] INFRASTRUCTURE FAILURE - Python host exited $code" -ForegroundColor Red
    exit 99
}
exit $code
