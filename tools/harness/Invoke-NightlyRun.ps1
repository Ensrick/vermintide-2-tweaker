#requires -Version 7
<#
.SYNOPSIS
  The rig's nightly run (WP-H-11 steps 4 and 5): smoke and sweep plans while the owner is away, a report, nothing
  published.

.DESCRIPTION
  Meant to be started by the disabled-by-default scheduled task in tools/harness/nightly/ (the owner enables it;
  tools/harness/nightly/README.md). It refuses (exit 0, one line in <RigRoot>\nightly.log, no report) when:
    - the owner is active: the last keyboard or mouse input (GetLastInputInfo) is less than -MinIdleMinutes (30) old;
    - a busy process runs: any name in tools/harness/busy-processes.txt, or any process started from a Steam
      library's steamapps\common folder (every Steam game, so big games such as Spider-Man are covered even when
      the list misses them);
  and it checks both again before every plan, so a returning owner stops the rest of the night. run.ps1's own
  refusals (RAM, Steam, the rig lock) still apply to each plan.

  Patch day (step 5): when the game build id in appmanifest_552500.acf differs from the last nightly run's
  (<RigRoot>\nightly-state.json), it runs the patch-day canary first (qa/check_patch_day.ps1, WP-T-04, when present),
  puts the smoke plans before the sweeps, and lists every stored evidence record (<RigRoot>\runs\*\evidence\*.md)
  whose game build is not the current one as "older than the current game build".

  Writes <ReportDir>\nightly-<yyyy-MM-dd>.md (default qa/runtime/reports of this checkout). It never comments on,
  labels or closes an issue, and never uploads anything.

  Exit codes: 0 done or refused for activity; 1 a plan failed (exit 1 from run.ps1); 2 a plan was incomplete; 3 the
  rig refused a plan.
#>
[CmdletBinding()]
param(
    [string] $RigRoot = (Join-Path $env:LOCALAPPDATA 'vt2-harness'),
    [string[]] $Plans = @('smoke-public.json', 'smoke-dev.json', 'sweep-public.json', 'sweep-dev.json'),
    [string] $PlansDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\plans'),
    [string] $ReportDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\reports'),
    [int] $MinIdleMinutes = 30,
    [string] $BusyProcessesFile = (Join-Path $PSScriptRoot 'busy-processes.txt'),
    [string] $SteamApps = '',
    [string] $RunScript = (Join-Path $PSScriptRoot 'run.ps1'),
    [string] $CanaryScript = (Join-Path $PSScriptRoot '..\..\qa\check_patch_day.ps1'),
    [double] $IdleMinutesOverride = -1,          # tests only: pretend this much idle time
    [string[]] $ProcessOverride = $null,         # tests only: pretend these process names (name|path) are running
    [switch] $WhatIf
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $RigRoot | Out-Null
$log = Join-Path $RigRoot 'nightly.log'
function Write-NightlyLog([string] $text) { Add-Content -LiteralPath $log -Value ("{0} {1}" -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $text); Write-Host $text }

if (-not ('Vt2Idle' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Vt2Idle
{
    [StructLayout(LayoutKind.Sequential)] struct LastInput { public uint size; public uint time; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LastInput info);
    /// <summary>Milliseconds since the last keyboard or mouse input in this session.</summary>
    public static uint IdleMilliseconds()
    {
        var info = new LastInput { size = (uint)Marshal.SizeOf(typeof(LastInput)) };
        if (!GetLastInputInfo(ref info)) return 0;
        return unchecked((uint)Environment.TickCount - info.time);
    }
}
'@
}

function Get-IdleMinutes { if ($IdleMinutesOverride -ge 0) { return $IdleMinutesOverride } return [Vt2Idle]::IdleMilliseconds() / 60000.0 }

$busyNames = @()
if (Test-Path -LiteralPath $BusyProcessesFile) {
    $busyNames = @([System.IO.File]::ReadAllLines($BusyProcessesFile) | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ } | ForEach-Object { $_ -replace '\.exe$', '' })
}
$steamRoots = @()
try {
    $install = & (Join-Path $PSScriptRoot 'Resolve-Vt2Install.ps1') -SteamApps $SteamApps
    $steamRoots += (Join-Path $install.SteamApps 'common')
    $acf = [System.IO.File]::ReadAllText((Join-Path $install.SteamApps 'appmanifest_552500.acf'))
    $build = [regex]::Match($acf, '"buildid"\s+"(\d+)"').Groups[1].Value
    $key = Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue
    if ($key -and $key.SteamPath) {
        $vdf = Join-Path ([System.IO.Path]::GetFullPath(($key.SteamPath -replace '/', '\'))) 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) { foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) { $steamRoots += Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common' } }
    }
}
catch { $build = '' }
$steamRoots = @($steamRoots | ForEach-Object { [System.IO.Path]::GetFullPath($_).TrimEnd('\') + '\' } | Sort-Object -Unique)

function Get-BusyReason {
    $idle = Get-IdleMinutes
    if ($idle -lt $MinIdleMinutes) { return "the owner is active (last input $([math]::Round($idle, 1)) min ago, need $MinIdleMinutes)" }
    $procs = if ($null -ne $ProcessOverride) {
        @($ProcessOverride | ForEach-Object { $n, $pth = $_ -split '\|', 2; [pscustomobject]@{ ProcessName = $n; Path = $pth } })
    }
    else { @(Get-Process -ErrorAction SilentlyContinue | Select-Object ProcessName, Path) }
    $named = @($procs | Where-Object { $busyNames -contains $_.ProcessName } | ForEach-Object ProcessName | Sort-Object -Unique)
    if ($named.Count) { return "a busy process runs ($($named -join ', '); busy-processes.txt)" }
    $games = @($procs | Where-Object { $p = [string]$_.Path; $p -and @($steamRoots | Where-Object { $p.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count } | ForEach-Object ProcessName | Sort-Object -Unique)
    if ($games.Count) { return "a Steam game runs ($($games -join ', '))" }
    return $null
}

$why = Get-BusyReason
if ($why) { Write-NightlyLog "nightly refused: $why"; exit 0 }

$stateFile = Join-Path $RigRoot 'nightly-state.json'
$state = if (Test-Path -LiteralPath $stateFile) { [System.IO.File]::ReadAllText($stateFile) | ConvertFrom-Json } else { $null }
$lastBuild = if ($state -and $state.PSObject.Properties['last_build']) { [string]$state.last_build } else { '' }
$patchDay = [bool]($build -and $lastBuild -and $build -ne $lastBuild)
$order = @($Plans)
if ($patchDay) { $order = @($Plans | Where-Object { $_ -like 'smoke*' }) + @($Plans | Where-Object { $_ -notlike 'smoke*' }) }

$lines = @("# Nightly rig run $((Get-Date).ToString('yyyy-MM-dd'))", '', "Game build: $(if ($build) { $build } else { 'unknown' }) (last nightly: $(if ($lastBuild) { $lastBuild } else { 'none' }))$(if ($patchDay) { ' - patch day' })", '')
$worst = 0
if ($patchDay) {
    if (Test-Path -LiteralPath $CanaryScript) {
        if ($WhatIf) { $lines += "Canary: would run $CanaryScript" }
        else {
            $out = & pwsh -NoProfile -NonInteractive -File $CanaryScript 2>&1
            $lines += "Canary (qa/check_patch_day.ps1): exit $LASTEXITCODE"
            $lines += @($out | Select-Object -Last 8 | ForEach-Object { "    $_" })
        }
    }
    else { $lines += 'Canary: qa/check_patch_day.ps1 is not in this checkout yet (WP-T-04); smoke plans run first.' }
    $stale = @()
    foreach ($f in @(Get-ChildItem -Path (Join-Path $RigRoot 'runs\*\evidence\*.md') -File -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match([System.IO.File]::ReadAllText($f.FullName), 'Game build (\S+?)\.?\r?\n')
        if ($m.Success -and $m.Groups[1].Value -ne $build) { $stale += "$([System.IO.Path]::GetRelativePath($RigRoot, $f.FullName)) (game build $($m.Groups[1].Value))" }
    }
    $lines += '', "Evidence older than the current game build ($($stale.Count)):"
    $lines += @($stale | ForEach-Object { "- $_" })
    $lines += ''
}

$lines += '| Plan | Run | Exit | Cases | Notes |', '|---|---|---|---|---|'
foreach ($p in $order) {
    $planPath = Join-Path $PlansDir $p
    $why = Get-BusyReason
    if ($why) { $lines += "| $p | - | - | - | not run: $why |"; Write-NightlyLog "nightly stopped before ${p}: $why"; break }
    if (-not (Test-Path -LiteralPath $planPath)) { $lines += "| $p | - | - | - | plan not found |"; continue }
    if ($WhatIf) { $lines += "| $p | - | - | - | would run |"; continue }
    $before = @(Get-ChildItem -LiteralPath (Join-Path $RigRoot 'runs') -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
    $global:LASTEXITCODE = 0
    $null = & $RunScript -Plan $planPath -RigRoot $RigRoot -Wait 10
    $code = $LASTEXITCODE
    $new = @(Get-ChildItem -LiteralPath (Join-Path $RigRoot 'runs') -Directory -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Name } | Sort-Object Name | Select-Object -Last 1)
    $runName = if ($new.Count) { $new[0].Name } else { '-' }
    $counts = '-'; $note = ''
    if ($new.Count -and (Test-Path -LiteralPath (Join-Path $new[0].FullName 'summary.json'))) {
        $s = [System.IO.File]::ReadAllText((Join-Path $new[0].FullName 'summary.json')) | ConvertFrom-Json
        $counts = (@($s.cases | Where-Object { $_ } | Group-Object verdict | Sort-Object Name | ForEach-Object { "$($_.Name) $($_.Count)" })) -join ', '
        if ($s.sweep) { $note = "sweep rows $($s.sweep.rows): PASS $($s.sweep.pass), FAIL $($s.sweep.fail), SKIP $($s.sweep.skip)" }
    }
    $lines += "| $p | $runName | $code | $counts | $note |"
    if ($code -gt $worst) { $worst = $code }
}
$lines += '', 'This report publishes nothing: no issue is commented on, labelled or closed (tools/harness/Publish-Evidence.ps1 does that, by hand).'

if (-not $WhatIf) {
    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
    $report = Join-Path $ReportDir ('nightly-{0}.md' -f (Get-Date).ToString('yyyy-MM-dd'))
    $lines | Set-Content -LiteralPath $report -Encoding utf8
    if ($build) { [ordered]@{ last_build = $build; last_run = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8 }
    Write-NightlyLog "nightly done: $report (worst exit $worst)"
}
else { $lines | ForEach-Object { Write-Host $_ } }
exit $worst
