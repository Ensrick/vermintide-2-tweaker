# upload_event_tweaker.ps1 - Upload Tweaker: Events to Steam Workshop (VMB layout)
# itemV2.cfg currently has visibility = "private" - DO NOT change to "public" without
# explicit user direction. A prior automated change to public on other mods got them
# flagged/removed-from-community, which is irreversible.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfg  = Join-Path $root 'event_tweaker\itemV2.cfg'
$tool = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader\ugc_tool.exe'

if (-not (Test-Path $cfg))  { throw "itemV2.cfg not found at $cfg" }
if (-not (Test-Path $tool)) { throw "ugc_tool.exe not found at $tool" }

$bundle = Join-Path $root 'event_tweaker\bundleV2'
if (-not (Test-Path $bundle) -or -not (Get-ChildItem $bundle -Filter '*.mod_bundle' -ErrorAction SilentlyContinue)) {
    throw "No bundleV2 output found at $bundle - run VMB build first"
}

# Sanity-check visibility before pushing - bash echo y|ugc_tool will commit whatever's in the cfg.
$cfgContent = Get-Content $cfg -Raw
if ($cfgContent -match 'visibility\s*=\s*"public"') {
    throw "itemV2.cfg has visibility = `"public`". Aborting upload. Confirm with user first."
}

Write-Host "Uploading event_tweaker via $tool" -ForegroundColor Cyan
& bash -c "echo y | '$($tool -replace '\\','/')' -c '$($cfg -replace '\\','/')' -x"
