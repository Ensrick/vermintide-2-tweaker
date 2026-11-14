#requires -Version 7
<#
.SYNOPSIS
  Subscribe the logged-in Steam account to a Vermintide 2 Workshop item (or query its state) through the
  Steamworks API that ships with the game. No web cookies, no Steam restart, no GUI.

.DESCRIPTION
  Runs as a short-lived Steam client of app 552500 (child-only SteamAppId), calls ISteamUGC::SubscribeItem and
  DownloadItem, pumps callbacks until the item is installed or the wait expires, then shuts the API down.
  Item state flags: 1 subscribed, 2 legacy, 4 installed, 8 needs update, 16 downloading, 32 download pending.

  Refuses to run while the game itself is running.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ulong] $ItemId,
    [ValidateSet('subscribe', 'state')] [string] $Action = 'subscribe',
    [int] $WaitSeconds = 45,
    [switch] $Child
)
$ErrorActionPreference = 'Stop'
$game = 'C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\binaries_dx12'

if (-not $Child) {
    if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(vermintide2|vermintide2_dx12)$' }) { throw 'The game is running.' }
    if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Steam is not running.' }
    $psi = [System.Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    foreach ($a in '-NoProfile', '-File', $PSCommandPath, '-ItemId', "$ItemId", '-Action', $Action, '-WaitSeconds', "$WaitSeconds", '-Child') { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $game
    $psi.Environment['SteamAppId'] = '552500'; $psi.Environment['SteamGameId'] = '552500'   # child only
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(($WaitSeconds + 30) * 1000)) { $p.Kill($true); throw 'steam-ugc child timed out' }
    $o.Result.TrimEnd(); if ($e.Result.Trim()) { "STDERR: $($e.Result.Trim())" }
    exit $p.ExitCode
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SteamFlat
{
    const string Dll = @"C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\binaries_dx12\steam_api64.dll";
    [DllImport(Dll)] [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_Init();
    [DllImport(Dll)] public static extern void SteamAPI_Shutdown();
    [DllImport(Dll)] public static extern void SteamAPI_RunCallbacks();
    [DllImport(Dll)] public static extern IntPtr SteamAPI_SteamUGC_v017();
    [DllImport(Dll)] public static extern ulong SteamAPI_ISteamUGC_SubscribeItem(IntPtr ugc, ulong id);
    [DllImport(Dll)] public static extern uint SteamAPI_ISteamUGC_GetNumSubscribedItems(IntPtr ugc);
    [DllImport(Dll)] public static extern uint SteamAPI_ISteamUGC_GetItemState(IntPtr ugc, ulong id);
    [DllImport(Dll)] [return: MarshalAs(UnmanagedType.I1)] public static extern bool SteamAPI_ISteamUGC_DownloadItem(IntPtr ugc, ulong id, [MarshalAs(UnmanagedType.I1)] bool highPriority);
}
'@
if (-not [SteamFlat]::SteamAPI_Init()) { Write-Output 'SteamAPI_Init failed (is Steam running and does the account own the game?)'; exit 2 }
try {
    $ugc = [SteamFlat]::SteamAPI_SteamUGC_v017()
    $before = [SteamFlat]::SteamAPI_ISteamUGC_GetNumSubscribedItems($ugc)
    $state0 = [SteamFlat]::SteamAPI_ISteamUGC_GetItemState($ugc, $ItemId)
    Write-Output "subscribed items: $before; item $ItemId state before: $state0"
    if ($Action -eq 'subscribe') {
        if (-not ($state0 -band 1)) { [void][SteamFlat]::SteamAPI_ISteamUGC_SubscribeItem($ugc, $ItemId) }
        $deadline = (Get-Date).AddSeconds($WaitSeconds); $asked = $false; $state = $state0
        while ((Get-Date) -lt $deadline) {
            [SteamFlat]::SteamAPI_RunCallbacks(); Start-Sleep -Milliseconds 200
            $state = [SteamFlat]::SteamAPI_ISteamUGC_GetItemState($ugc, $ItemId)
            if (($state -band 1) -and -not $asked -and -not ($state -band 4)) { [void][SteamFlat]::SteamAPI_ISteamUGC_DownloadItem($ugc, $ItemId, $true); $asked = $true }
            if (($state -band 1) -and ($state -band 4) -and -not ($state -band 8)) { break }
        }
        $after = [SteamFlat]::SteamAPI_ISteamUGC_GetNumSubscribedItems($ugc)
        Write-Output "subscribed items: $after; item $ItemId state after: $state (1 subscribed, 4 installed, 8 needs update, 16 downloading)"
        if (-not (($state -band 1) -and ($state -band 4))) { exit 1 }
    }
}
finally { [SteamFlat]::SteamAPI_Shutdown() }
exit 0
