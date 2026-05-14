# upload_ct.ps1 — thin wrapper around VMBLauncher's headless upload verb.
#
# Per tools/vmb-launcher/CLAUDE.md, VMBLauncher.exe is the canonical
# build/deploy/upload pipeline and the .ps1 scripts are fallbacks. This wrapper
# stays so the muscle-memory invocation still works, but the actual upload
# is performed by the launcher.
#
# ct is the only Tweaker mod whose intended visibility is "public", so this
# wrapper always passes --allow-public. The launcher itself refuses to push
# a visibility="public" mod without this flag (mirrors the GUI confirmation
# modal) — see tools/vmb-launcher/CLAUDE.md "Visibility safety".
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$launcher = Join-Path $root 'tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\VMBLauncher.exe'
if (-not (Test-Path $launcher)) {
    throw "VMBLauncher.exe not found at $launcher. Build it with: cd tools/vmb-launcher && .\publish.ps1 -SkipOpen"
}
& $launcher upload chaos_wastes_tweaker --allow-public --no-banner
if ($LASTEXITCODE -ne 0) { throw "VMBLauncher upload exited with code $LASTEXITCODE" }

# Independent verification via Steam Web API — ugc_tool's "Upload finished"
# message does NOT confirm transfer, so we always cross-check the live
# Workshop entry's file_size/time_updated.
try {
    $api = Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' `
        -Body @{ itemcount = 1; 'publishedfileids[0]' = '3712929235' } -TimeoutSec 30
    $d = $api.response.publishedfiledetails[0]
    Write-Host ('[verify] live: title="{0}" visibility={1} file_size={2} time_updated={3}' -f `
        $d.title, $d.visibility, $d.file_size, $d.time_updated) -ForegroundColor Cyan
} catch {
    Write-Host "[verify] Steam Web API verify failed: $_" -ForegroundColor Yellow
}
