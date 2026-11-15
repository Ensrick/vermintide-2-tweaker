#requires -Version 7
<#
.SYNOPSIS
  Puts a locally built mod into a rig slot so a plan can test it without touching the mod's real Workshop folder
  (WP-H-07 step 2).

.DESCRIPTION
  1. Resolves the slot with Get-RigSlot.ps1: only ids listed in tools/harness/slots.psd1 are accepted, never a
     real mod's id or the bootstrap. The slot item must be installed (its Workshop folder exists).
  2. Unless -NoBuild: builds the mod from the worktree that holds this script through the canonical
     tools/ship/ship.ps1 -Mod <dir> -BuildOnly (VMBLauncher build <mod> --clean with a private --config whose
     ProjectRoot is this worktree), holding the machine-wide build lock so parallel VMB builds cannot collide.
  3. Replaces the slot folder's files with <dir>\bundleV2\* and writes slot.json there: slot, slot id, mod dir,
     VMF mod id, real Workshop id, git commit (and whether the tree was dirty), MOD_VERSION, time, and the SHA-256
     of every staged file. run.ps1 (plan field local_builds) refuses a slot whose files no longer match.
  Writes nothing outside the slot folder (and, when building, the worktree's bundleV2 and build receipt).

  Exit codes: 0 staged, 2 refused or failed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Mod,
    [Parameter(Mandatory)] [int] $Slot,
    [switch] $NoBuild,
    [string] $SteamApps = '',
    [string] $SlotsFile = (Join-Path $PSScriptRoot 'slots.psd1'),
    [string] $BuildMutex = 'Global\Ensrick.VT2.Program.BuildOnly',
    [int] $BuildLockMinutes = 90
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$inventoryPath = Join-Path $repo 'tools\mod-inventory.psd1'
try {
    $row = @((Import-PowerShellDataFile -LiteralPath $inventoryPath).Mods | Where-Object { $_.Dir -eq $Mod })
    if ($row.Count -ne 1) { throw "not an inventory mod folder: $Mod" }
    $install = & (Join-Path $PSScriptRoot 'Resolve-Vt2Install.ps1') -SteamApps $SteamApps
    $slotInfo = & (Join-Path $PSScriptRoot 'Get-RigSlot.ps1') -Slot $Slot -Workshop $install.Workshop -SlotsFile $SlotsFile -Inventory $inventoryPath
    if (-not (Test-Path -LiteralPath $slotInfo.Dir -PathType Container)) { throw "slot $Slot ($($slotInfo.Id)) is not installed: run tools/harness/steam-ugc.ps1 -ItemId $($slotInfo.Id)" }
    if (@(Get-ChildItem -LiteralPath $slotInfo.Dir -Directory).Count) { throw "slot folder holds subfolders; refusing to stage: $($slotInfo.Dir)" }
    $modDir = Join-Path $repo $Mod
    $mainLua = Join-Path $modDir "scripts\mods\$Mod\$Mod.lua"
}
catch { Write-Host "STAGE REFUSED: $($_.Exception.Message)"; exit 2 }

if (-not $NoBuild) {
    $mutex = [System.Threading.Mutex]::new($false, $BuildMutex)
    $held = $false
    try {
        Write-Host "[stage-build] waiting for the build lock"
        try { $held = $mutex.WaitOne([TimeSpan]::FromMinutes($BuildLockMinutes)) } catch [System.Threading.AbandonedMutexException] { $held = $true }
        if (-not $held) { Write-Host "STAGE REFUSED: build lock not acquired in $BuildLockMinutes min"; exit 2 }
        Push-Location -LiteralPath $repo
        try { & (Get-Process -Id $PID).Path -NoProfile -File (Join-Path $repo 'tools\ship\ship.ps1') -Mod $Mod -BuildOnly; $code = $LASTEXITCODE }
        finally { Pop-Location }
        if ($code -ne 0) { Write-Host "STAGE FAILED: ship.ps1 -BuildOnly exit $code"; exit 2 }
    }
    finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

$bundle = Join-Path $modDir 'bundleV2'
$files = @(Get-ChildItem -LiteralPath $bundle -File -ErrorAction SilentlyContinue)
if (-not ($files | Where-Object { $_.Name -eq "$Mod.mod" })) { Write-Host "STAGE FAILED: $bundle has no $Mod.mod (build first, or drop -NoBuild)"; exit 2 }
$version = $null
if (Test-Path -LiteralPath $mainLua -PathType Leaf) {
    $m = [regex]::Match([System.IO.File]::ReadAllText($mainLua), '(?m)^local MOD_VERSION = "([^"]+)"')
    if ($m.Success) { $version = $m.Groups[1].Value }
}
$commit = (git -C $repo rev-parse HEAD).Trim()
$dirty = [bool](git -C $repo status --porcelain -- $Mod)

foreach ($old in @(Get-ChildItem -LiteralPath $slotInfo.Dir -File)) { Remove-Item -LiteralPath $old.FullName -Force }
$hashes = [ordered]@{}
foreach ($f in ($files | Sort-Object Name)) {
    $target = Join-Path $slotInfo.Dir $f.Name
    Copy-Item -LiteralPath $f.FullName -Destination $target -Force
    $hashes[$f.Name] = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
}
$record = [ordered]@{
    slot = $Slot; slot_id = $slotInfo.Id; mod = $Mod; mod_id = [string]$row[0].ModId; real_id = [string]$row[0].WorkshopId
    commit = $commit; dirty = $dirty; version = $version; staged_utc = (Get-Date).ToUniversalTime().ToString('o'); files = $hashes
}
[System.IO.File]::WriteAllText((Join-Path $slotInfo.Dir 'slot.json'), ($record | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
$check = & (Join-Path $PSScriptRoot 'Test-RigSlot.ps1') -SlotDir $slotInfo.Dir -Mod $Mod
if (-not $check.Ok) { Write-Host "STAGE FAILED: $($check.Problems -join '; ')"; exit 2 }
Write-Host "[stage-build] staged $Mod $version ($commit$(if ($dirty) { ', dirty' })) into slot $Slot ($($slotInfo.Id)): $($hashes.Count) files"
exit 0
