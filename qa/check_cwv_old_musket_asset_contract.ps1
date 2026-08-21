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

$expectedFbxSha = '2DD3683905F867207939318D80242ED291F1361A04AF73B39EAC57925C5D2187'
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
    Require-Exact $contract.contract 'cwv_old_musket_native_frame_v3' 'contract identity'
    Require-Exact $contract.source_sha256 'A20C6161C9B6302FF424BFC801D036BEE2C8D793D3A027BE309140C04B791550' 'source SHA-256'
    Require-Exact $contract.source_component_signature 'B9F7DBB4EFCAC3C09F44B136C5AAAC03FA172F9060EE67ACF9544B133C6835B6' 'source component signature'
    Require-Exact $contract.source_vertex_count 10014 'source vertex count'
    Require-Exact $contract.source_polygon_count 16483 'source polygon count'
    Require-Exact $contract.basis.source '+X forward/-Y accepted Handgun up/-Z accepted Handgun side' 'source basis'
    Require-Exact $contract.basis.output '+Y forward/+Z accepted Handgun up/+X accepted Handgun side' 'output basis'
    Require-Vector $contract.basis.matrix[0] @(0.0, 0.0, -1.0) 'basis matrix row 0'
    Require-Vector $contract.basis.matrix[1] @(1.0, 0.0, 0.0) 'basis matrix row 1'
    Require-Vector $contract.basis.matrix[2] @(0.0, -1.0, 0.0) 'basis matrix row 2'

    $m = $contract.basis.matrix
    if ($null -ne $m -and $m.Count -eq 3) {
        for ($row = 0; $row -lt 3; $row++) {
            for ($column = 0; $column -lt 3; $column++) {
                $dot = 0.0
                for ($index = 0; $index -lt 3; $index++) {
                    $dot += [double]$m[$index][$row] * [double]$m[$index][$column]
                }
                $expected = if ($row -eq $column) { 1.0 } else { 0.0 }
                Require ([math]::Abs($dot - $expected) -le 0.000001) `
                    "basis matrix must be orthonormal at [$row,$column]"
            }
        }
        $determinant = [double]$m[0][0] * ([double]$m[1][1] * [double]$m[2][2] - [double]$m[1][2] * [double]$m[2][1]) `
            - [double]$m[0][1] * ([double]$m[1][0] * [double]$m[2][2] - [double]$m[1][2] * [double]$m[2][0]) `
            + [double]$m[0][2] * ([double]$m[1][0] * [double]$m[2][1] - [double]$m[1][1] * [double]$m[2][0])
        Require ([math]::Abs($determinant - 1.0) -le 0.000001) `
            'basis matrix must remain a determinant-1 rotation, never a mirror'
    }
    Require-Exact $contract.output_1p_sha256 $expectedFbxSha 'contract 1P output SHA-256'
    Require-Exact $contract.output_3p_sha256 $expectedFbxSha 'contract 3P output SHA-256'
    Require-Exact $contract.output_geometry_sha256 '060C46AE6FFD2CB5753C02AF72459DB0E4382A9FA3680CBC774685D418C2CB9A' 'ordered geometry/winding SHA-256'

    Require-Vector $contract.source_bounds_min @(-1.0, -0.11947000026702881, -0.025645995512604713) 'source bounds min'
    Require-Vector $contract.source_bounds_max @(1.0, 0.11963900178670883, 0.02564600296318531) 'source bounds max'
    Require-Vector $contract.source_root @(-0.5173783898353577, -0.02272941917181015, 0.01740901917219162) 'source root'
    Require-Vector $contract.trigger_anchor @(-0.5211420059204102, -0.06259221583604813, 0.01740901917219162) 'source trigger anchor'
    Require-Vector $contract.trigger_tail_anchor @(-0.4975546598434448, -0.10970599204301834, 0.015542463399469852) 'source signed trigger-tail anchor'
    Require-Vector $contract.native_handgun_j_trigger @(0.0, -0.0037636400666087866, 0.039862796664237976) 'native handgun trigger anchor'
    Require-Vector $contract.output_bounds_min @(-0.00823698379099369, -0.48262161016464233, -0.14236842095851898) 'output bounds min'
    Require-Vector $contract.output_bounds_max @(0.043055012822151184, 1.517378330230713, 0.09674058109521866) 'output bounds max'
    Require-Vector $contract.output_dimensions @(0.051291994750499725, 2.0, 0.23910900950431824) 'output dimensions'
    Require-Vector $contract.output_trigger_anchor @(0.0, -0.0037636160850524902, 0.039862796664237976) 'output trigger anchor'
    Require-Vector $contract.output_trigger_tail_anchor @(0.0018665557727217674, 0.019823729991912842, 0.08697657287120819) 'output signed trigger-tail anchor'
    Require-Vector $contract.output_trigger_roll_vector @(0.0018665557727217674, 0.023587346076965332, 0.047113776206970215) 'output signed roll vector'
    Require-Vector $contract.output_trigger_anchor ([double[]]@($contract.native_handgun_j_trigger)) 'output/native trigger alignment' 0.000001
    Require ([double]$contract.output_trigger_roll_vector[2] -gt 0.04) `
        'signed roll landmark must remain above +0.04 on Handgun Z; the v0.1.525 upside-down export used the opposite half-space'
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
