[CmdletBinding()]
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$wocRoot = Join-Path $repoRoot 'weapons_of_chaos'
$errors = New-Object System.Collections.Generic.List[string]

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { $errors.Add($Message) }
}

$expectedHash = '4BDA4ED14BDA32B3560BCB7BF0BF256274539BE67ECEECD4D0B9A7713180865F'
$units = @(
    'units/woc_skarrik_halberd/skarrik_halberd'
    'units/woc_skarrik_halberd/skarrik_halberd_3p'
)

foreach ($unit in $units) {
    $relative = $unit.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $fbxPath = Join-Path $wocRoot ($relative + '.fbx')
    $unitPath = Join-Path $wocRoot ($relative + '.unit')
    Require (Test-Path -LiteralPath $fbxPath -PathType Leaf) "missing authored FBX: $unit"
    Require (Test-Path -LiteralPath $unitPath -PathType Leaf) "missing authored unit: $unit"
    if (Test-Path -LiteralPath $fbxPath -PathType Leaf) {
        $actual = (Get-FileHash -LiteralPath $fbxPath -Algorithm SHA256).Hash
        Require ($actual -eq $expectedHash) "authored FBX drifted: $unit expected=$expectedHash actual=$actual"
    }
    if (Test-Path -LiteralPath $unitPath -PathType Leaf) {
        $source = [IO.File]::ReadAllText($unitPath, [Text.Encoding]::UTF8)
        Require ($source.Contains('skarrik_halberd_mat = "units/woc_skarrik_dual_swords/skarrik_swords"')) "$unit does not reuse #615 shared material"
        Require ($source.Contains('skarrik_halberd = {')) "$unit has wrong renderable identity"
    }
}

$packagePath = Join-Path $wocRoot 'resource_packages/weapons_of_chaos/weapons_of_chaos.package'
$package = [IO.File]::ReadAllText($packagePath, [Text.Encoding]::UTF8)
foreach ($unit in $units) {
    Require ($package.Contains('"' + $unit + '"')) "package closure omits $unit"
}

$catalogPath = Join-Path $wocRoot 'scripts/mods/weapons_of_chaos/_woc_boss_weapon_catalog.lua'
$catalog = [IO.File]::ReadAllText($catalogPath, [Text.Encoding]::UTF8)
Require ($catalog.Contains('material = "units/woc_skarrik_dual_swords/skarrik_swords"')) 'catalog does not name #615 shared material owner'
Require ($catalog.Contains('material_owner_issue = 615')) 'catalog does not preserve shared-material issue ownership'
Require (-not $catalog.Contains('unresolved_texture_hashes')) 'resolved zero-byte texture is still represented as an unresolved blocker'

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) { Write-Error $errorMessage }
    throw "[check_woc_skarrik_halberd_sources] FAIL - $($errors.Count) error(s)"
}
if (-not $Quiet) {
    Write-Host "[check_woc_skarrik_halberd_sources] OK - pinned 1P/3P FBX pair, shared #615 material binding, package closure" -ForegroundColor Green
}
