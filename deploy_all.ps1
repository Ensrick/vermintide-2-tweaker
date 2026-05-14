# deploy_all.ps1 — bulk-deploy VMB-built mods via VMBLauncher.exe.
#
# Thin loop around `VMBLauncher.exe deploy <mod>`. The launcher does the
# hash-verified copy from each mod's bundleV2/ into its Workshop content
# folder. Default mod list matches the historically deployed set; pass -Mods
# to override.
param(
    [string[]]$Mods = @("chaos_wastes_tweaker", "weapon_tweaker", "general_tweaker")
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $root 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'

if (-not (Test-Path $launcher)) {
    throw "VMBLauncher.exe not found at $launcher. Build via tools/vmb-launcher/publish.ps1 first."
}

$failures = @()
foreach ($mod in $Mods) {
    Write-Host ""
    Write-Host "=== deploy $mod ===" -ForegroundColor Cyan
    & $launcher deploy $mod
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $mod (exit $LASTEXITCODE)" -ForegroundColor Red
        $failures += $mod
    }
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host ("Deploy failed for: {0}" -f ($failures -join ', ')) -ForegroundColor Red
    exit 1
}
Write-Host ("Deployed {0} mod(s)." -f $Mods.Count) -ForegroundColor Green
exit 0
