# upload_gt.ps1 — thin wrapper around VMBLauncher.exe upload general_tweaker.
#
# The launcher is the canonical path (see tools/vmb-launcher/CLAUDE.md). This
# wrapper exists for muscle memory + a defensive visibility guard.
#
# gt went public 2026-05-14 (intentional flip from friends_only). The script
# aborts if cfg drifted away from "public" so we catch accidental visibility
# regressions, and passes --allow-public so the launcher's built-in public-mod
# safety gate is satisfied. Per `feedback_workshop_metadata_user_dictates.md`,
# never silently change visibility — the cfg's value is what hits Workshop.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'general_tweaker'
$expectedVisibility = 'public'
$launcher = Join-Path $root 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'

if (-not (Test-Path $launcher)) {
    throw "VMBLauncher.exe not found at $launcher. Build via tools/vmb-launcher/publish.ps1 first."
}

$cfgPath = Join-Path $root "$modName\itemV2.cfg"
$cfgRaw = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
if ($cfgRaw -match 'visibility\s*=\s*"([^"]+)"' -and $matches[1] -ne $expectedVisibility) {
    throw "itemV2.cfg has visibility='$($matches[1])' but $modName must be '$expectedVisibility'. Aborting to prevent accidental visibility regression."
}

& $launcher upload $modName --allow-public
exit $LASTEXITCODE
