# upload_gt.ps1 — thin wrapper around VMBLauncher.exe upload general_tweaker.
#
# The launcher is the canonical path (see tools/vmb-launcher/CLAUDE.md). This
# wrapper exists for muscle memory + a defensive visibility guard that aborts
# before invoking the launcher if itemV2.cfg drifted away from "friends_only"
# (catches accidental escalation to "public", which is irreversible if the
# mod gets flagged).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$modName = 'general_tweaker'
$expectedVisibility = 'friends_only'
$launcher = Join-Path $root 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe'

if (-not (Test-Path $launcher)) {
    throw "VMBLauncher.exe not found at $launcher. Build via tools/vmb-launcher/publish.ps1 first."
}

# Defensive visibility check before the launcher even sees the cfg.
$cfgPath = Join-Path $root "$modName\itemV2.cfg"
$cfgRaw = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
if ($cfgRaw -match 'visibility\s*=\s*"([^"]+)"' -and $matches[1] -ne $expectedVisibility) {
    throw "itemV2.cfg has visibility='$($matches[1])' but $modName must be '$expectedVisibility'. Aborting to prevent accidental visibility regression."
}

& $launcher upload $modName
exit $LASTEXITCODE
