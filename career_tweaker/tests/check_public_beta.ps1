[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $modRoot 'scripts\mods\career_tweaker'
$entry = [System.IO.File]::ReadAllText((Join-Path $sourceRoot 'career_tweaker.lua'))
$data = [System.IO.File]::ReadAllText((Join-Path $sourceRoot 'career_tweaker_data.lua'))
$regression = [System.IO.File]::ReadAllText((Join-Path $sourceRoot '_crt_regression.lua'))

$failures = @()
function Require([bool]$condition, [string]$message) {
    if (-not $condition) { $script:failures += $message }
}

Require ($entry -match 'local\s+MOD_VERSION\s*=\s*"\d+\.\d+\.\d+-beta"') 'MOD_VERSION is not a beta'
Require ($entry -match 'PUBLIC_BETA_TALENT_SWAPS_DISABLED\s*=\s*true') 'talent-swap disable marker missing'
Require ($entry -match 'PUBLIC_BETA_BARDIN_PROBE_DISABLED\s*=\s*true') 'Bardin-probe disable marker missing'
Require ($entry -match 'PUBLIC_BETA_UMBRELLA_AUDIT_DISABLED\s*=\s*true') 'umbrella-audit disable marker missing'

Require (-not ($data -match 'setting_id\s*=\s*"career_swapping_group"')) 'casting/transposition group is exposed'
Require (-not ($data -match 'setting_id\s*=\s*"talent_swap_')) 'casting/transposition setting is exposed'
Require (-not ($entry -match 'pcall\s*\(\s*mod\.dofile[^\r\n]*_crt_talent_swap')) 'talent-swap module is loaded'
Require (-not ($entry -match 'pcall\s*\(\s*mod\.dofile[\s\S]{0,120}_crt_bardin_disabler_probe')) 'Bardin probe is loaded'
Require (-not ($entry -match 'mod:command\s*\(\s*"crt_umbrella_audit"')) 'umbrella audit command is registered'
Require (-not ($entry -match '(?m)^\s*apply_talent_swaps\s*\(')) 'talent swaps are applied'

Require ($regression -match '_rt_register\("public_beta_talent_swaps_disabled"') 'runtime talent-swap exclusion check missing'
Require ($regression -match '_rt_register\("public_beta_issue_probes_disabled"') 'runtime issue-probe exclusion check missing'

if ($failures.Count -gt 0) {
    Write-Host "[career beta contract] FAILED - $($failures.Count) finding(s):" -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  ! $failure" -ForegroundColor Red }
    exit 1
}

Write-Host '[career beta contract] PASS - casting/transposition and issue probes are fail-closed.' -ForegroundColor Green
exit 0
