#requires -Version 7
<#
.SYNOPSIS
  Finds the Steam library that holds Vermintide 2 (app 552500), starting from the Steam path in the registry.

.DESCRIPTION
  Reads HKCU:\Software\Valve\Steam SteamPath, then looks for appmanifest_552500.acf in that steamapps folder and
  in every library listed in its libraryfolders.vdf. Nothing is written. Pass -SteamApps to skip the lookup.

.OUTPUTS
  [pscustomobject] with SteamApps, Game, Workshop, BinariesDx12, Binaries.
#>
[CmdletBinding()]
param(
    [string] $SteamApps = ''
)
$ErrorActionPreference = 'Stop'

if (-not $SteamApps) {
    $key = Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue
    if (-not $key -or -not $key.SteamPath) { throw 'Steam is not installed for this user (registry value HKCU:\Software\Valve\Steam SteamPath is missing).' }
    $root = [System.IO.Path]::GetFullPath(($key.SteamPath -replace '/', '\'))
    $libraries = [System.Collections.Generic.List[string]]::new()
    $libraries.Add((Join-Path $root 'steamapps'))
    $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
            $libraries.Add((Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps'))
        }
    }
    foreach ($library in $libraries) {
        if (Test-Path -LiteralPath (Join-Path $library 'appmanifest_552500.acf') -PathType Leaf) { $SteamApps = $library; break }
    }
    if (-not $SteamApps) { throw "Vermintide 2 (app 552500) is not installed in any Steam library under $root." }
}

$game = Join-Path $SteamApps 'common\Warhammer Vermintide 2'
[pscustomobject]@{
    SteamApps    = $SteamApps
    Game         = $game
    Workshop     = Join-Path $SteamApps 'workshop\content\552500'
    BinariesDx12 = Join-Path $game 'binaries_dx12'
    Binaries     = Join-Path $game 'binaries'
}
