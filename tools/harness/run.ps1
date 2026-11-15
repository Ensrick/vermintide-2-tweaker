#requires -Version 7
<#
.SYNOPSIS
  VT2 test rig orchestrator. Starts the retail game directly (no launcher) in the modded realm with an
  isolated profile, optionally on a private desktop, hands the in-game driver a plan, watches the run,
  collects evidence, and proves the owner's real profile was not touched.

.DESCRIPTION
  Plan file (JSON):
    {
      "name": "smoke-keep",
      "mods": ["1369573612", "3733367409"],        // Workshop folder ids to enable, in load order (VMF first)
      "arenas": ["keep", "mission:military"],       // optional; derived from cases when absent
      "timeout": 600,                               // whole-run limit inside the game, seconds
      "settings": { "max_fps": "30" },              // optional extra top-level user settings (SJSON values)
      "cases": [ { "id": "smoke-keep", "arena": "keep", "file": "../_rig/smoke_keep.lua" } ]
    }
  Case files are Lua source that returns a table { issue = <n>, timeout = <s>, run = function(T) ... end }.
  Case file paths are relative to the plan file. See tools/harness/README.md.

  Exit code: 0 = run completed and every case PASS; 1 = at least one FAIL; 2 = ERROR/TIMEOUT/INCONCLUSIVE or
  the run did not complete; 3 = rig refused to start or isolation was broken.

.NOTES
  Never starts if any Vermintide process exists. Never kills a process it did not start (job object).
  Nothing is written to the persistent environment. The Steam library is found from the registry
  (Resolve-Vt2Install.ps1); the rig root defaults to %LOCALAPPDATA%\vt2-harness.
#>
[CmdletBinding()]
param(
    [string] $Plan,
    [string] $Name,
    [switch] $Visible,                      # default is a private desktop that is never switched to
    [int] $TimeoutSeconds = 0,              # host-side hard limit; default = plan timeout + 240
    [ValidateSet('dx12', 'dx11')] [string] $Renderer = 'dx12',
    [string] $ExtraArgs = '',
    [string] $DriverFile = (Join-Path $PSScriptRoot 'driver/vt2_rig_driver.lua'),
    [string] $DriverId = '3839345856',      # private Workshop item: the rig bootstrap
    [string] $RigRoot = (Join-Path $env:LOCALAPPDATA 'vt2-harness'),
    [string] $SteamApps = '',               # default: resolved from HKCU:\Software\Valve\Steam SteamPath
    [string] $StopOnLog = '',               # no-plan experiments: stop when this regex appears in the log
    [int] $StopDelaySeconds = 5,
    [switch] $KeepOwnerMods                 # no-plan experiments: leave the copied mod list as it is
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$realProfile = Join-Path $env:APPDATA 'Fatshark\Vermintide 2'

function Get-FileSha([string] $p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { 'absent' } }

# ---------- plan ----------
$planObj = $null
if ($Plan) {
    $planPath = (Resolve-Path -LiteralPath $Plan).Path
    $planObj = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (-not $Name) { $Name = $planObj.name }
}
if (-not $Name) { throw 'Give -Plan or -Name.' }

# ---------- preflight ----------
try {
    $install = & (Join-Path $here 'Resolve-Vt2Install.ps1') -SteamApps $SteamApps
    $steamApps = $install.SteamApps
    $workshop = $install.Workshop
    $acf = Get-Content -LiteralPath (Join-Path $steamApps 'appmanifest_552500.acf') -Raw
    if ($acf -notmatch '"StateFlags"\s+"4"') { throw 'VT2 is not fully installed (StateFlags is not 4).' }
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(vermintide2|vermintide2_dx12|vermintide2_launcher)$' }
    if ($running) { throw "A Vermintide process is already running (pid $($running.Id -join ', ')). Refusing to start." }
    if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Steam is not running.' }
    $exe = if ($Renderer -eq 'dx12') { Join-Path $install.BinariesDx12 'vermintide2_dx12.exe' } else { Join-Path $install.Binaries 'vermintide2.exe' }
    if (-not (Test-Path -LiteralPath $exe)) { throw "Game exe not found: $exe" }
    $mem = Get-CimInstance Win32_OperatingSystem
    if ($mem.FreePhysicalMemory / 1MB -lt 6) { throw "Free RAM below 6 GiB ($([math]::Round($mem.FreePhysicalMemory / 1MB, 1)) GiB)." }
}
catch { Write-Host "RIG REFUSED: $($_.Exception.Message)"; exit 3 }

$mutex = [System.Threading.Mutex]::new($false, 'Global\Vt2RigSingleInstance')
if (-not $mutex.WaitOne(0)) { Write-Host 'RIG REFUSED: another rig run holds the lock.'; exit 3 }

$nonce = -join ((1..8) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$run = Join-Path $RigRoot "runs\$stamp-$Name-$nonce"
New-Item -ItemType Directory -Force -Path $run | Out-Null
$watched = 'user_settings.config', 'save_data.sav', 'launcher.config'
$before = @{}; foreach ($f in $watched) { $before[$f] = Get-FileSha (Join-Path $realProfile $f) }
$realLogsBefore = @(Get-ChildItem -LiteralPath (Join-Path $realProfile 'console_logs') -Filter 'console-*.log' -ErrorAction SilentlyContinue | ForEach-Object Name)

# ---------- the driver ----------
# The Workshop item $DriverId is a tiny bootstrap that never changes (Steam must list an item as subscribed
# before the game will load it; an unsubscribed folder is ignored). The driver itself is sent as text.
if ($planObj) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $workshop $DriverId) 'vt2_rig_driver.mod'))) {
        Write-Host "RIG REFUSED: bootstrap item $DriverId is not installed. Run steam-ugc.ps1 -ItemId $DriverId first."; $mutex.ReleaseMutex(); exit 3
    }
}

# ---------- profile ----------
$profileArgs = @{ RealProfile = $realProfile; ProfileRoot = (Join-Path $RigRoot 'profile'); DriverId = $DriverId; KeepOwnerMods = $KeepOwnerMods }
if ($planObj) { $profileArgs.PlanPath = $planPath; $profileArgs.Nonce = $nonce; $profileArgs.DriverFile = $DriverFile }
try { $rigProfile = & (Join-Path $here 'New-RigProfile.ps1') @profileArgs }
catch { Write-Host "RIG REFUSED: profile: $($_.Exception.Message)"; $mutex.ReleaseMutex(); exit 3 }
$profileRoot = $rigProfile.ProfileRoot
$rigAppData = $rigProfile.AppData
$rigLocal = $rigProfile.LocalAppData
$rigVt2 = $rigProfile.Vt2Dir
if ($planObj) { Copy-Item -LiteralPath $planPath -Destination (Join-Path $run 'plan.json') }

# ---------- launch ----------
if (-not ('Vt2GameProcess' -as [type])) { Add-Type -Path (Join-Path $here 'GameProcess.cs') }
$arguments = "-eac-untrusted --bundle-dir ../bundle --ini settings --silent-mode -skip-splash -vt2-test-run $nonce $ExtraArgs".Trim()
$childEnv = @{ SteamAppId = '552500'; SteamGameId = '552500'; USERPROFILE = $profileRoot; APPDATA = $rigAppData; LOCALAPPDATA = $rigLocal }
if ($TimeoutSeconds -le 0) { $TimeoutSeconds = [int](($planObj.timeout ?? 180)) + 240 }
$started = Get-Date
$proc = $null; $verdict = 'UNKNOWN'; $notes = [System.Collections.Generic.List[string]]::new()
$marks = [ordered]@{}; $logPath = $null; $stopAt = $null; $text = ''; $lastHb = $started; $lastNote = ''
$patterns = [ordered]@{
    realm = 'realm = (modded|official)'; mods_scan = 'Starting mod scan'; splash = 'StateSplashScreen'; title = 'StateTitleScreen'
    loading = 'StateLoading'; ingame = 'StateIngame'; run_begin = '\[vt2t:' + $nonce + '\] RUN BEGIN'; keep_ready = '\[vt2t:' + $nonce + '\] KEEP READY'
    run_end = '\[vt2t:' + $nonce + '\] RUN END'
}
try {
    $proc = [Vt2GameProcess]::Start($exe, $arguments, (Split-Path $exe), $childEnv, (-not $Visible))
    "pid $($proc.Pid) desktop '$($proc.DesktopName)' args: $arguments" | Set-Content -LiteralPath (Join-Path $run 'launch.txt')
    Write-Host "rig run $stamp-$Name-$nonce pid $($proc.Pid) private=$(-not $Visible)"
    $deadline = $started.AddSeconds($TimeoutSeconds)
    while (-not $proc.WaitForExit(500)) {
        $now = Get-Date
        if (-not $logPath) {
            $cand = Get-ChildItem -LiteralPath (Join-Path $rigVt2 'console_logs') -Filter 'console-*.log' -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -ge $started.AddSeconds(-2) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($cand) { $logPath = $cand.FullName; $marks['log_created'] = [math]::Round(($now - $started).TotalSeconds, 1) }
        }
        if ($logPath) {
            $fs = [System.IO.File]::Open($logPath, 'Open', 'Read', 'ReadWrite')
            try { $sr = [System.IO.StreamReader]::new($fs); $text = $sr.ReadToEnd() } finally { $fs.Dispose() }
            foreach ($k in $patterns.Keys) {
                if (-not $marks.Contains($k) -and $text -match $patterns[$k]) { $marks[$k] = [math]::Round(($now - $started).TotalSeconds, 1) }
            }
            if ($StopOnLog -and -not $stopAt -and $text -match $StopOnLog) { $stopAt = $now.AddSeconds($StopDelaySeconds); $marks['stop_pattern'] = [math]::Round(($now - $started).TotalSeconds, 1) }
        }
        if ($planObj -and (($now - $lastHb).TotalSeconds -ge 5)) {
            $lastHb = $now
            try {
                $live = [System.IO.File]::ReadAllText((Join-Path $rigVt2 'user_settings.config'))
                $pm = [regex]::Match($live, '(?ms)^vt2_rig_progress = \{.*?^\}')
                if ($pm.Success -and $pm.Value -match 'nonce = "' + $nonce + '"') {
                    $note = [regex]::Match($pm.Value, 'note = "([^"]*)"').Groups[1].Value
                    if ($note -and $note -ne $lastNote) { $lastNote = $note; Write-Host ("  [{0,5:N0}s] {1}" -f ($now - $started).TotalSeconds, $note) }
                }
            } catch { }
        }
        if (-not $Visible) {
            $w = $proc.WindowsOnUserDesktop()
            if ($w.Count -gt 0) { $notes.Add("WINDOW ON USER DESKTOP: $($w -join '; ')"); $verdict = 'VISIBLE-WINDOW'; $proc.Kill(); break }
        }
        if ($stopAt -and $now -ge $stopAt) { $verdict = 'STOPPED-ON-PATTERN'; $proc.Kill(); break }
        if ($now -ge $deadline) { $verdict = 'HOST-TIMEOUT-KILLED'; $proc.Kill(); break }
    }
    if ($verdict -eq 'UNKNOWN') { $verdict = "EXITED code=$($proc.ExitCode)" }
    $marks['ended'] = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    if (-not $Visible) { $notes.Add("private desktop windows at end: $(($proc.WindowsOnPrivateDesktop()) -join ' | ')") }
}
finally {
    if ($proc) { $proc.Dispose() }
    $mutex.ReleaseMutex(); $mutex.Dispose()
}

# ---------- collect ----------
if ($logPath) { Copy-Item -LiteralPath $logPath -Destination (Join-Path $run 'console.log') -Force; $text = Get-Content -LiteralPath $logPath -Raw }
Copy-Item -LiteralPath (Join-Path $rigVt2 'user_settings.config') -Destination (Join-Path $run 'user_settings.after.config') -Force
Get-ChildItem -LiteralPath (Join-Path $rigVt2 'crash_dumps') -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $started } |
    ForEach-Object { $notes.Add("crash dump: $($_.Name) $($_.Length) bytes") }
$after = @{}; foreach ($f in $watched) { $after[$f] = Get-FileSha (Join-Path $realProfile $f) }
$isolation = 'OK'
foreach ($f in $watched) { if ($before[$f] -ne $after[$f]) { $isolation = 'BROKEN'; $notes.Add("owner file changed: $f") } }
$realLogsAfter = @(Get-ChildItem -LiteralPath (Join-Path $realProfile 'console_logs') -Filter 'console-*.log' -ErrorAction SilentlyContinue | ForEach-Object Name)
$leaked = @($realLogsAfter | Where-Object { $_ -notin $realLogsBefore })
if ($leaked.Count) { $isolation = 'BROKEN'; $notes.Add("log written to the owner's real profile: $($leaked -join ', ')") }

# evidence lines
$lines = @(); if ($text) { $lines = @([regex]::Matches($text, '(?m)^.*\[vt2t:' + $nonce + '\] (.*)$') | ForEach-Object { $_.Groups[1].Value.TrimEnd() }) }
$lines | Set-Content -LiteralPath (Join-Path $run 'evidence.txt')
$cases = @()
foreach ($l in $lines) {
    if ($l -match '^CASE END id=(\S+) verdict=(\S+) asserts=(\d+) failed=(\d+) t=([\d\.]+)(?: detail="(.*)")?') {
        $cases += [ordered]@{ id = $Matches[1]; verdict = $Matches[2]; asserts = [int]$Matches[3]; failed = [int]$Matches[4]; seconds = [double]$Matches[5]; detail = $Matches[6] }
    }
}
$runEnd = [bool]($lines | Where-Object { $_ -match '^RUN END' })
$scriptErrors = @([regex]::Matches($text, '(?m)^.*(\[Script Error\]|<<Script Error>>|Lua Stack).*$') | Select-Object -First 5 | ForEach-Object { $_.Value.Trim() })
$exit = 2
if ($isolation -ne 'OK') { $exit = 3 }
elseif ($planObj -and $runEnd -and $cases.Count -gt 0) {
    if ($cases | Where-Object { $_.verdict -eq 'FAIL' }) { $exit = 1 }
    elseif ($cases | Where-Object { $_.verdict -ne 'PASS' }) { $exit = 2 }
    else { $exit = 0 }
}
elseif (-not $planObj) { $exit = 0 }
$summary = [ordered]@{
    run = "$stamp-$Name-$nonce"; name = $Name; nonce = $nonce; verdict = $verdict; exit = $exit; isolation = $isolation
    private_desktop = (-not $Visible); renderer = $Renderer; arguments = $arguments; run_end_seen = $runEnd
    marks_seconds = $marks; cases = $cases; script_errors = $scriptErrors; evidence_lines = $lines.Count
    log = (Join-Path $run 'console.log'); notes = $notes
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'summary.json') -Encoding utf8
$md = @("# Rig run $($summary.run)", '', "Verdict: $verdict | exit $exit | isolation $isolation | RUN END seen: $runEnd", '', '| Case | Verdict | Asserts | Failed | Seconds | Detail |', '|---|---|---|---|---|---|')
foreach ($c in $cases) { $md += "| $($c.id) | $($c.verdict) | $($c.asserts) | $($c.failed) | $($c.seconds) | $($c.detail) |" }
$md | Set-Content -LiteralPath (Join-Path $run 'summary.md') -Encoding utf8
$summary | ConvertTo-Json -Depth 6
exit $exit
