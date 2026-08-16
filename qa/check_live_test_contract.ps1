# Offline adversarial fixtures for the deployed CURRENT LIVE TEST source contract.

[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$contractPath = Join-Path $repoRoot 'tools\verify\live_test_contract.ps1'
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "Live-test contract policy not found: $contractPath"
}
. $contractPath

if ($SelfTest) {
    Invoke-VtDeployedSourceContractSelfTest
    exit 0
}

Write-Host '[check_live_test_contract] Use -SelfTest for the offline adversarial contract suite.'
exit 0
