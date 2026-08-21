# check_cwv_old_musket_asset_contract.ps1
#
# Offline ratchet for issue #1155's normalized Old Musket source assets. The
# original DAE and Blender are intentionally not routine-QA dependencies: the
# generated contract pins the source/topology/frame evidence, while exact FBX
# hashes pin the deterministic conversion output.

[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$cwvRoot = Join-Path $repoRoot 'character_weapon_variants'
$contractPath = Join-Path $cwvRoot 'tools\old_musket_asset_contract.json'
$onePath = Join-Path $cwvRoot 'units\cwv_es_musket_custom\cwv_es_musket_custom.fbx'
$threePath = Join-Path $cwvRoot 'units\cwv_es_musket_custom\cwv_es_musket_custom_3p.fbx'
$errors = New-Object 'System.Collections.Generic.List[string]'

function Add-Failure([string]$Message) {
    $errors.Add($Message)
}

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { Add-Failure $Message }
}

function Require-Exact([object]$Actual, [object]$Expected, [string]$Name) {
    if ([string]$Actual -cne [string]$Expected) {
        Add-Failure "$Name drifted: expected=$Expected actual=$Actual"
    }
}

function Require-Vector(
    [object]$Actual,
    [double[]]$Expected,
    [string]$Name,
    [double]$Tolerance = 0.000000001
) {
    $values = @($Actual)
    if ($values.Count -ne $Expected.Count) {
        Add-Failure "$Name must contain $($Expected.Count) values; actual=$($values.Count)"
        return
    }

    for ($i = 0; $i -lt $Expected.Count; $i++) {
        try {
            $value = [double]$values[$i]
        }
        catch {
            Add-Failure "$Name[$i] is not numeric: $($values[$i])"
            continue
        }

        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or
            [Math]::Abs($value - $Expected[$i]) -gt $Tolerance) {
            Add-Failure "$Name[$i] drifted: expected=$($Expected[$i]) actual=$value"
        }
    }
}

$expectedFbxSha = 'F8EC6568A435D35FD51CC1EB416A0D7B015735ECAA42674EDBBCE9A21E7B5FEE'
$expectedAssets = [ordered]@{
    '1P' = $onePath
    '3P' = $threePath
}
$assetBytes = @{}

foreach ($view in $expectedAssets.Keys) {
    $path = $expectedAssets[$view]
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "$view FBX missing: $path"
        continue
    }

    $actualSha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    Require ($actualSha -ceq $expectedFbxSha) "$view FBX hash drifted: expected=$expectedFbxSha actual=$actualSha"

    $bytes = [IO.File]::ReadAllBytes($path)
    $assetBytes[$view] = $bytes
    $ascii = [Text.Encoding]::ASCII.GetString($bytes)
    Require ($ascii.Contains('Kaydara FBX Binary')) "$view asset is not the expected binary FBX form"
    Require ($ascii.Contains(([char]0) + 'rifle' + ([char]0))) "$view FBX lost required mesh identifier: rifle"
    Require ($ascii.Contains(([char]0) + 'rifle_mat' + ([char]0))) "$view FBX lost required material identifier: rifle_mat"
}

if ($assetBytes.ContainsKey('1P') -and $assetBytes.ContainsKey('3P')) {
    Require ($assetBytes['1P'].Length -eq $assetBytes['3P'].Length) `
        "1P/3P FBX byte lengths differ: 1P=$($assetBytes['1P'].Length) 3P=$($assetBytes['3P'].Length)"
    Require ([System.Collections.StructuralComparisons]::StructuralEqualityComparer.Equals(
            $assetBytes['1P'], $assetBytes['3P'])) `
        '1P/3P FBX files are not byte-identical'
}

$contract = $null
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    Add-Failure "asset contract missing: $contractPath"
}
else {
    try {
        $contract = [IO.File]::ReadAllText($contractPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        Add-Failure "asset contract is not valid JSON: $($_.Exception.Message)"
    }
}

if ($null -ne $contract) {
    Require-Exact $contract.contract 'cwv_old_musket_native_frame_v1' 'contract identity'
    Require-Exact $contract.source_sha256 'A20C6161C9B6302FF424BFC801D036BEE2C8D793D3A027BE309140C04B791550' 'source SHA-256'
    Require-Exact $contract.source_component_signature 'B9F7DBB4EFCAC3C09F44B136C5AAAC03FA172F9060EE67ACF9544B133C6835B6' 'source component signature'
    Require-Exact $contract.source_vertex_count 10014 'source vertex count'
    Require-Exact $contract.source_polygon_count 16483 'source polygon count'
    Require-Exact $contract.basis.source '+X forward/+Y up/+Z side' 'source basis'
    Require-Exact $contract.basis.output '+Y forward/+Z up/+X side' 'output basis'
    Require-Exact $contract.output_1p_sha256 $expectedFbxSha 'contract 1P output SHA-256'
    Require-Exact $contract.output_3p_sha256 $expectedFbxSha 'contract 3P output SHA-256'

    Require-Vector $contract.source_bounds_min @(-1.0, -0.11947000026702881, -0.025645995512604713) 'source bounds min'
    Require-Vector $contract.source_bounds_max @(1.0, 0.11963900178670883, 0.02564600296318531) 'source bounds max'
    Require-Vector $contract.source_root @(-0.5173783898353577, -0.1024550125002861, 0.01740901917219162) 'source root'
    Require-Vector $contract.trigger_anchor @(-0.5211420059204102, -0.06259221583604813, 0.01740901917219162) 'source trigger anchor'
    Require-Vector $contract.native_handgun_j_trigger @(0.0, -0.0037636400666087866, 0.039862796664237976) 'native handgun trigger anchor'
    Require-Vector $contract.output_bounds_min @(-0.043055012822151184, -0.48262161016464233, -0.017014987766742706) 'output bounds min'
    Require-Vector $contract.output_bounds_max @(0.00823698379099369, 1.517378330230713, 0.22209401428699493) 'output bounds max'
    Require-Vector $contract.output_dimensions @(0.051291994750499725, 2.0, 0.23910900950431824) 'output dimensions'
    Require-Vector $contract.output_trigger_anchor @(0.0, -0.0037636160850524902, 0.039862796664237976) 'output trigger anchor'
    Require-Vector $contract.output_trigger_anchor ([double[]]@($contract.native_handgun_j_trigger)) 'output/native trigger alignment' 0.000001
}

if ($errors.Count -gt 0) {
    Write-Host "[check_cwv_old_musket_asset_contract] FAILED - $($errors.Count) error(s):" -ForegroundColor Red
    foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
    exit 2
}

if (-not $Quiet) {
    Write-Host '[check_cwv_old_musket_asset_contract] OK - pinned source/topology/frame contract and byte-identical 1P/3P FBXs' -ForegroundColor Green
}
exit 0
