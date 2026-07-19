# Canonical active-mod inventory integrity gate (issue #546).
# ASCII-only for Windows PowerShell 5.1 parsing.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Test-InventoryModel {
    param(
        [object[]]$Mods,
        [string[]]$DiscoveredDirs,
        [hashtable]$CfgByDir,
        [string]$Readme,
        [hashtable]$ExcludedDirs
    )
    $errors = @()
    $seenDir = @{}; $seenId = @{}; $seenWorkshop = @{}
    $required = @('Dir', 'ModId', 'WorkshopId', 'Visibility', 'Stream', 'Public', 'Name', 'RootBundle')

    foreach ($mod in @($Mods)) {
        foreach ($field in $required) {
            if ($null -eq $mod[$field] -or ([string]$mod[$field]).Trim() -eq '') {
                $errors += "inventory entry is missing $field"
            }
        }
        $dir = [string]$mod.Dir; $id = [string]$mod.ModId; $workshop = [string]$mod.WorkshopId
        if ($seenDir.ContainsKey($dir)) { $errors += "duplicate inventory directory: $dir" } else { $seenDir[$dir] = $true }
        if ($seenId.ContainsKey($id)) { $errors += "duplicate VMF mod id: $id" } else { $seenId[$id] = $true }
        if ($seenWorkshop.ContainsKey($workshop)) { $errors += "duplicate Workshop id: $workshop" } else { $seenWorkshop[$workshop] = $true }

        if ($mod.Visibility -notin @('public', 'friends_only', 'private')) { $errors += "invalid visibility for ${dir}: $($mod.Visibility)" }
        if ($mod.Stream -notin @('single', 'stable', 'dev')) { $errors += "invalid stream for ${dir}: $($mod.Stream)" }
        if ([bool]$mod.Public -ne ($mod.Visibility -eq 'public')) { $errors += "Public flag disagrees with visibility for $dir" }

        if (-not $CfgByDir.ContainsKey($dir)) {
            $errors += "inventory directory missing live itemV2.cfg: $dir"
        } else {
            $cfg = $CfgByDir[$dir]
            if ($cfg.WorkshopId -ne $workshop) { $errors += "Workshop id drift for ${dir}: inventory=$workshop cfg=$($cfg.WorkshopId)" }
            if ($cfg.Visibility -ne $mod.Visibility) { $errors += "visibility drift for ${dir}: inventory=$($mod.Visibility) cfg=$($cfg.Visibility)" }
            if ($cfg.ModId -and $cfg.ModId -ne $id) { $errors += "VMF id drift for ${dir}: inventory=$id source=$($cfg.ModId)" }
        }
        $readmeLink = '[`' + $dir + '`](./' + $dir + '/)'
        if ($Readme -notmatch [regex]::Escape($readmeLink)) {
            $errors += "README mod directory omits active inventory entry: $dir"
        }
    }

    foreach ($dir in @($DiscoveredDirs)) {
        if (-not $seenDir.ContainsKey($dir) -and -not $ExcludedDirs.ContainsKey($dir)) {
            $errors += "active root mod with itemV2.cfg is absent from inventory: $dir"
        }
    }
    return $errors
}

function Invoke-SelfTest {
    $mods = @(@{ Dir='alpha'; ModId='a'; WorkshopId='123'; Visibility='public'; Stream='single'; Public=$true; Name='Alpha'; RootBundle='aaaaaaaaaaaaaaaa.mod_bundle' })
    $cfg = @{ alpha = @{ WorkshopId='123'; Visibility='public'; ModId='a' } }
    $readme = '| [`alpha`](./alpha/) |'
    $good = @(Test-InventoryModel $mods @('alpha', 'stale') $cfg $readme @{ stale=$true })
    if ($good.Count -ne 0) { throw "valid inventory rejected: $($good -join '; ')" }

    $badMods = @(
        @{ Dir='alpha'; ModId='a'; WorkshopId='123'; Visibility='public'; Stream='single'; Public=$false; Name='Alpha'; RootBundle='aaaaaaaaaaaaaaaa.mod_bundle' },
        @{ Dir='alpha'; ModId='a'; WorkshopId='123'; Visibility='friends_only'; Stream='wrong'; Public=$false; Name='Duplicate'; RootBundle='bbbbbbbbbbbbbbbb.mod_bundle' }
    )
    $bad = @(Test-InventoryModel $badMods @('alpha', 'beta') $cfg '' @{})
    foreach ($needle in @('duplicate inventory directory', 'duplicate VMF mod id', 'duplicate Workshop id', 'active root mod', 'README', 'Public flag', 'invalid stream')) {
        if (-not ($bad -match $needle)) { throw "planted inventory failure not detected: $needle" }
    }
    $missingRoot = @(Test-InventoryModel @(@{ Dir='alpha'; ModId='a'; WorkshopId='123'; Visibility='public'; Stream='single'; Public=$true; Name='Alpha' }) @('alpha') $cfg $readme @{})
    if (-not ($missingRoot -match 'missing RootBundle')) { throw 'planted RootBundle omission not detected' }
    Write-Host '[check_mod_inventory -SelfTest] OK'
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path $RepoRoot).Path
$inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    Write-Host '[check_mod_inventory] ERROR - tools/mod-inventory.psd1 is missing.' -ForegroundColor Red
    exit 2
}
try { $inventory = Import-PowerShellDataFile -Path $inventoryPath } catch {
    Write-Host "[check_mod_inventory] ERROR - inventory cannot be imported: $_" -ForegroundColor Red
    exit 2
}

foreach ($entry in @($inventory.Mods)) {
    $bundlePath = Join-Path $root "$($entry.Dir)\bundleV2\$($entry.RootBundle)"
    if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
        Write-Host "[check_mod_inventory] ERROR - RootBundle missing for $($entry.Dir): $($entry.RootBundle)" -ForegroundColor Red
        exit 2
    }
}

$cfgByDir = @{}
$discovered = @()
foreach ($modDir in @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue)) {
    $cfgFile = Get-Item -LiteralPath (Join-Path $modDir.FullName 'itemV2.cfg') -ErrorAction SilentlyContinue
    if (-not $cfgFile) { continue }
    $dir = Split-Path (Split-Path $cfgFile.FullName -Parent) -Leaf
    $text = [System.IO.File]::ReadAllText($cfgFile.FullName, [System.Text.Encoding]::UTF8)
    $workshop = if ($text -match 'published_id\s*=\s*(\d+)L?\s*;') { $matches[1] } else { '' }
    $visibility = if ($text -match 'visibility\s*=\s*"([^"]+)"') { $matches[1] } else { '' }
    $mainPath = Join-Path $root "$dir\scripts\mods\$dir\$dir.lua"
    $modId = ''
    if (Test-Path -LiteralPath $mainPath) {
        $mainText = [System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)
        if ($mainText -match 'get_mod\s*\(\s*"([^"]+)"\s*\)') { $modId = $matches[1] }
    }
    $cfgByDir[$dir] = @{ WorkshopId=$workshop; Visibility=$visibility; ModId=$modId }
    $discovered += $dir
}

$readmePath = Join-Path $root 'README.md'
$readme = if (Test-Path $readmePath) { [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8) } else { '' }
$excluded = @{}
$errors = @(Test-InventoryModel @($inventory.Mods) $discovered $cfgByDir $readme $excluded)
if ($errors.Count -gt 0) {
    Write-Host '[check_mod_inventory] ERRORS:' -ForegroundColor Red
    foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) { Write-Host "[check_mod_inventory] OK - $(@($inventory.Mods).Count) active release/lint records match cfg, source, and README." -ForegroundColor Green }
exit 0
