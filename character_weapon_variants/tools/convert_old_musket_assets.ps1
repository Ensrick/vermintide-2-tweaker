param(
    [string]$Blender = (Join-Path $env:ProgramFiles 'Blender Foundation\Blender 4.4\blender.exe'),
    [string]$Source = (Join-Path $env:USERPROFILE 'Downloads\old-musket\extracted\model\model.dae')
)

$ErrorActionPreference = 'Stop'
$toolDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$modDir = Split-Path -Parent $toolDir
$helper = Join-Path $toolDir 'prepare_old_musket_fbx.py'
$unitDir = Join-Path $modDir 'units\cwv_es_musket_custom'
$output1p = Join-Path $unitDir 'cwv_es_musket_custom.fbx'
$output3p = Join-Path $unitDir 'cwv_es_musket_custom_3p.fbx'
$report = Join-Path $toolDir 'old_musket_asset_contract.json'

foreach ($required in @($Blender, $Source, $helper)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required Old Musket conversion input is missing: $required"
    }
}

& $Blender --factory-startup --background --python-exit-code 1 --python $helper -- `
    --input $Source `
    --output-1p $output1p `
    --output-3p $output3p `
    --report $report
if ($LASTEXITCODE -ne 0) {
    throw "Old Musket Blender normalization failed with exit code $LASTEXITCODE"
}

Write-Host '[old-musket-assets] Native-frame FBX pair and contract regenerated.' -ForegroundColor Green
