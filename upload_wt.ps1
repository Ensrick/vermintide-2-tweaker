# upload_wt.ps1 — thin wrapper around VMBLauncher.exe upload weapon_tweaker.
#
# The launcher is the canonical path (see tools/vmb-launcher/CLAUDE.md). This
# wrapper exists for muscle memory + a defensive visibility guard.
#
# HISTORY/WARNING: a prior automated change to public once got wt
# flagged/removed-from-community (irreversible). The user re-made wt PUBLIC
# deliberately on 2026-06-15 and accepts that risk (see memory
# `project_vt2_public_mods_2026-06`). The guard now aborts if cfg drifts AWAY
# from "public", and passes --allow-public so the launcher's public-mod gate is
# satisfied. If wt ever gets flagged again, revert this + the cfg to friends_only.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'weapon_tweaker'
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
