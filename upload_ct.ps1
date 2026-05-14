# upload_ct.ps1 — thin wrapper around VMBLauncher.exe upload chaos_wastes_tweaker.
#
# The launcher is the canonical path (see tools/vmb-launcher/CLAUDE.md). This
# wrapper exists for muscle memory + a defensive visibility guard.
#
# ct is the only Tweaker mod whose intended visibility is "public" (see
# `feedback_workshop_metadata_user_dictates.md`). The script aborts if cfg
# drifted away from "public" (catches accidental private->public->private
# round trips) and passes --allow-public to the launcher so its built-in
# public-mod safety gate is satisfied.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'chaos_wastes_tweaker'
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
