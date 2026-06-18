# upload_event_tweaker.ps1 — thin wrapper around VMBLauncher.exe upload event_tweaker.
#
# The launcher is the canonical path (see tools/vmb-launcher/CLAUDE.md). This
# wrapper exists for muscle memory + a defensive visibility guard.
#
# event_tweaker was made PUBLIC on the Workshop 2026-06-13 (user decision; see
# memory `project_vt2_public_mods_2026-06`). The guard now aborts if cfg drifted
# AWAY from "public", and passes --allow-public so the launcher's built-in
# public-mod safety gate is satisfied (mirrors upload_ct.ps1).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'event_tweaker'
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
