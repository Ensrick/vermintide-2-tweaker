#requires -Version 7
<#
.SYNOPSIS
  Prepares (and with -Publish creates) the rig's six private Workshop slot items, once (WP-H-07 step 1).

.DESCRIPTION
  For every slot in tools/harness/slots.psd1 whose Id is still empty, writes an item folder under
  <RigRoot>\slot-items\slot<n>\ with:
    item.cfg          title "VT2 Rig Slot <n>", visibility "private", content = "content"
    item_preview.png  a 1x1 placeholder image
    content\          the bootstrap item's bundles (Workshop folder 3839345856) plus slot-item\vt2_rig_slot.mod
  and prints the two commands that create and install the item, the procedure proven for the bootstrap:
    ugc_tool.exe -c <item.cfg> -x                         (creates the private item; writes published_id into item.cfg)
    pwsh -File tools/harness/steam-ugc.ps1 -ItemId <id>   (subscribes and installs it through the game's steam_api64)
  -Publish runs both and prints the slots.psd1 line to record. The items carry placeholder content only: no
  mod content is uploaded, and an item is never made public or friends-visible.
#>
[CmdletBinding()]
param(
    [string] $RigRoot = (Join-Path $env:LOCALAPPDATA 'vt2-harness'),
    [string] $SteamApps = '',
    [string] $SlotsFile = (Join-Path $PSScriptRoot 'slots.psd1'),
    [string] $UgcTool = '',
    [string] $BootstrapId = '3839345856',
    [switch] $Publish
)
$ErrorActionPreference = 'Stop'
$install = & (Join-Path $PSScriptRoot 'Resolve-Vt2Install.ps1') -SteamApps $SteamApps
if (-not $UgcTool) { $UgcTool = Join-Path $install.SteamApps 'common\Vermintide 2 SDK\ugc_uploader\ugc_tool.exe' }
$bootstrapDir = Join-Path $install.Workshop $BootstrapId
$bundles = @(Get-ChildItem -LiteralPath $bootstrapDir -File -Filter '*.mod_bundle' -ErrorAction SilentlyContinue)
if (-not $bundles.Count) { throw "bootstrap item $BootstrapId is not installed: $bootstrapDir" }
$slotMod = Join-Path $PSScriptRoot 'slot-item\vt2_rig_slot.mod'
$png = [System.Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==')

foreach ($s in @((Import-PowerShellDataFile -LiteralPath $SlotsFile).Slots)) {
    if ([string]$s.Id) { Write-Host "slot $($s.Slot): already created ($($s.Id)), skipped"; continue }
    $dir = Join-Path $RigRoot "slot-items\slot$($s.Slot)"
    $content = Join-Path $dir 'content'
    New-Item -ItemType Directory -Force -Path $content | Out-Null
    foreach ($b in $bundles) { Copy-Item -LiteralPath $b.FullName -Destination (Join-Path $content $b.Name) -Force }
    Copy-Item -LiteralPath $slotMod -Destination (Join-Path $content 'vt2_rig_slot.mod') -Force
    [System.IO.File]::WriteAllBytes((Join-Path $dir 'item_preview.png'), $png)
    $cfgPath = Join-Path $dir 'item.cfg'
    if (-not (Test-Path -LiteralPath $cfgPath)) {
        $cfg = "title = `"$($s.Title)`";`ndescription = `"Private test-rig slot for the Tweaker mods. Placeholder content; the automated test rig stages local builds into it. Not for players.`";`npreview = `"item_preview.png`";`ncontent = `"content`";`nlanguage = `"english`";`nvisibility = `"private`";`napply_for_sanctioned_status = false;`ntags = [ ];`n"
        [System.IO.File]::WriteAllText($cfgPath, $cfg, [System.Text.UTF8Encoding]::new($false))
    }
    $text = [System.IO.File]::ReadAllText($cfgPath)
    if ($text -notmatch '(?m)^visibility = "private";') { throw "$cfgPath is not private; refusing" }
    $idMatch = [regex]::Match($text, '(?m)^published_id = (\d+)L;')
    Write-Host "slot $($s.Slot): item folder $dir"
    Write-Host "  create:    & `"$UgcTool`" -c `"$cfgPath`" -x   (working directory $dir)"
    Write-Host "  subscribe: pwsh -NoProfile -File tools/harness/steam-ugc.ps1 -ItemId <published_id from item.cfg>"
    if (-not $Publish) { continue }
    if (-not $idMatch.Success) {
        if (-not (Test-Path -LiteralPath $UgcTool -PathType Leaf)) { throw "ugc_tool not found: $UgcTool" }
        Push-Location -LiteralPath $dir
        try { & $UgcTool -c $cfgPath -x; $code = $LASTEXITCODE } finally { Pop-Location }
        $idMatch = [regex]::Match([System.IO.File]::ReadAllText($cfgPath), '(?m)^published_id = (\d+)L;')
        if ($code -ne 0 -or -not $idMatch.Success) { throw "slot $($s.Slot): ugc_tool exit $code, no published_id in $cfgPath" }
    }
    $id = $idMatch.Groups[1].Value
    & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $PSScriptRoot 'steam-ugc.ps1') -ItemId $id
    if ($LASTEXITCODE -ne 0) { throw "slot $($s.Slot): steam-ugc.ps1 -ItemId $id exit $LASTEXITCODE" }
    Write-Host "  record in slots.psd1:  @{ Slot = $($s.Slot); Id = '$id'; Title = '$($s.Title)' }"
}
