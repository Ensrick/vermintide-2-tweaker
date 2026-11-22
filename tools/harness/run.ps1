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
      "backend_shield": false,                      // optional; only for cases that test commit behaviour itself,
      "backend_shield_reason": "...",               //   and then with a reason (qa/check_runtime_scripts.ps1)
      "cases": [ { "id": "smoke-keep", "arena": "keep", "file": "../_rig/smoke_keep.lua" } ]
    }
  Case files are Lua source that returns a table { issue = <n>, timeout = <s>, run = function(T) ... end }.
  Case file paths are relative to the plan file. Every qa/runtime/_shared/*.lua travels with the plan
  (T.shared(<name>) in a case), and so does every driver helper group in tools/harness/driver/lib/*.lua
  (tools/harness/API.md). See tools/harness/README.md.

  Optional plan fields (WP-H-02): "expect_mods" (VMF mod ids the smoke case asserts are loaded),
  "host_expect_log" / "host_forbid_log" (regex lists checked on the final log) and "host_allow_log"
  ([{ "pattern", "reason" }] excusing one proven-benign line). Read-HostLog.ps1 adds the default forbidden lines
  (<<Script Error>>, Lua Stack, "was not found in the workshop folder", "Syntax error in .mod file",
  "Failed to run callback") and, while the backend write shield is on (WP-H-14), any updateHeroAttributes or
  UpdateUserData request. A plan with backend_shield false drops only the two shield defaults. A forbidden hit or
  a missing expected line makes the run exit 1 and is named in summary.json / summary.md.

  Local builds (WP-H-07): "local_builds": [{ "mod": "<dir>", "slot": <n> }] runs a build that stage-build.ps1 put
  into rig slot <n> (tools/harness/slots.psd1). Before launch the slot's files must match its slot.json, else the
  rig refuses (exit 3). The slot id takes the real id's place in the profile's mod list and the real id is
  disabled; the load banner must show the staged version (an expected line), and summary.json records the
  build's commit, version and whether the real Workshop folder stayed byte-identical.

  Several boots (WP-H-08): "boots": [ { "cases": [...] }, { "cases": [...], "modset": "..." } ] instead of top-level
  "cases" runs the boots in order on one rig profile; every boot after the first starts from the profile the one
  before it left. Each boot's evidence is in <run>\boot-<i>\; the run's summary lists every boot (Split-BootPlan.ps1).

  Exit code: 0 = run completed and every case PASS; 1 = at least one FAIL (also when the run broke off later), a
  forbidden log line or a missing expected line; 2 = ERROR/TIMEOUT/INCONCLUSIVE/CRASH or the run did not complete;
  3 = rig refused to start or isolation was broken.

  Reliability (WP-H-09; tools/harness/README.md "Reliability"): -Wait <minutes> queues for the rig lock; a busy
  process (busy-processes.txt) or free RAM under -MinFreeGiB refuses the start; the run is stopped as INCONCLUSIVE
  when the driver's progress checkpoint stops moving (-StallPlaySeconds in play, -StallLoadSeconds while booting or
  loading) or free RAM falls under -StopFreeGiB; a new crash dump, or an exit without RUN END, makes the running case
  CRASH (Get-RunVerdicts.ps1); a FAIL is re-run once alone in a fresh boot (Invoke-OrderCheck.ps1, not with
  -NoOrderCheck); with -Retain <N> only, older run folders that qa/runtime/reports does not name are reduced to their
  summaries under runs\_archive\ (Remove-OldRuns.ps1); by default nothing is pruned.

  Stills (WP-H-10; README "Stills"): when a case calls T.shot, the driver saves a vt2_rig_shot request and holds
  still; this script sees it and captures the game window into <run>\stills\ (GameProcess.cs CaptureStill), listed
  in shots.json and summary.json "shots". Plan "require_stills": true makes a missing, wrong-sized (plan
  "still_size", default [1280, 720]) or too dark (plan "still_min_brightness", default 8 of 255) still a note and
  the run at least exit 2.

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
    [string] $SharedDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\_shared'),
    [string] $LibDir = (Join-Path $PSScriptRoot 'driver\lib'),        # WP-H-06 driver helper groups (T.set, T.shot, ...)
    [string] $SlotsFile = (Join-Path $PSScriptRoot 'slots.psd1'),     # WP-H-07 rig slots for plan local_builds
    [string] $RigRoot = (Join-Path $env:LOCALAPPDATA 'vt2-harness'),
    [string] $SteamApps = '',               # default: resolved from HKCU:\Software\Valve\Steam SteamPath
    [string] $StopOnLog = '',               # no-plan experiments: stop when this regex appears in the log
    [int] $StopDelaySeconds = 5,
    [switch] $KeepOwnerMods,                # no-plan experiments: leave the copied mod list as it is
    [string] $RunDir = '',                  # WP-H-08: evidence folder of one boot of a plan with boots (Invoke-RigBoots.ps1)
    [switch] $KeepProfile,                  # WP-H-08: a later boot starts from the profile the boot before it left
    [double] $Wait = 0,                     # WP-H-09: minutes to wait for the rig lock (0 = refuse when it is held)
    [switch] $NoOrderCheck,                 # WP-H-09: do not re-run a FAIL alone (Repeat-Plan.ps1, boots, the re-run itself)
    [int] $Retain = 0,                      # WP-H-09: prune run folders beyond the newest N (Remove-OldRuns.ps1); 0 = prune nothing
    [string] $ReportsDir = (Join-Path $PSScriptRoot '..\..\qa\runtime\reports'),
    [string] $BusyProcessesFile = (Join-Path $PSScriptRoot 'busy-processes.txt'),
    [double] $MinFreeGiB = 6,               # WP-H-09: refuse to start below this much free RAM
    [double] $StopFreeGiB = 3,              # WP-H-09: stop the run as INCONCLUSIVE below this much free RAM
    [int] $StallPlaySeconds = 60,           # WP-H-09: progress checkpoint age that ends a run in play ...
    [int] $StallLoadSeconds = 240,          # ... and while booting or loading
    [string] $LockName = 'Global\Vt2RigSingleInstance'
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
    # WP-H-08: "modset" fills mods and expect_mods (New-RigProfile.ps1 resolves the plan the same way)
    try { $planObj = & (Join-Path $PSScriptRoot 'Resolve-RigPlan.ps1') -Plan $planObj }
    catch { Write-Host "RIG REFUSED: plan: $($_.Exception.Message)"; exit 3 }
    if (-not $Name) { $Name = $planObj.name }
}
if (-not $Name) { throw 'Give -Plan or -Name.' }

# ---------- boots (WP-H-08) ----------
# A plan with "boots" runs once per boot, in order, on one rig profile: boot 1 starts from a fresh copy of the
# owner's profile, every later boot from the profile the boot before it left (save, settings, mod data), so a case
# can check what survives a restart. Invoke-RigBoots.ps1 holds the rig lock across the boots and runs this script
# once per boot (Split-BootPlan.ps1 writes each boot's plan; evidence in <run>\boot-<i>\).
if ($planObj -and $planObj.PSObject.Properties['boots'] -and $planObj.boots) {
    $childArgs = @{ Renderer = $Renderer; ExtraArgs = $ExtraArgs; DriverFile = $DriverFile; DriverId = $DriverId; SharedDir = $SharedDir; SlotsFile = $SlotsFile; SteamApps = $SteamApps }
    if ($Visible) { $childArgs.Visible = $true }
    if ($TimeoutSeconds -gt 0) { $childArgs.TimeoutSeconds = $TimeoutSeconds }
    & (Join-Path $here 'Invoke-RigBoots.ps1') -PlanPath $planPath -Name $Name -RigRoot $RigRoot -ChildArgs $childArgs -RunScript $PSCommandPath -Wait $Wait -LockName $LockName -Retain $Retain -ReportsDir $ReportsDir
    exit $LASTEXITCODE
}

# ---------- preflight ----------
try {
    $install = & (Join-Path $here 'Resolve-Vt2Install.ps1') -SteamApps $SteamApps
    $steamApps = $install.SteamApps
    $workshop = $install.Workshop
    # WP-H-07: every local build must sit in a rig slot whose files still match its slot.json
    $localBuilds = @()
    if ($planObj -and $planObj.PSObject.Properties['local_builds']) {
        $inventory = Import-PowerShellDataFile -LiteralPath (Join-Path $here '..\mod-inventory.psd1')
        foreach ($lb in @($planObj.local_builds)) {
            $dir = [string]$lb.mod
            $row = @($inventory.Mods | Where-Object { $_.Dir -eq $dir })
            if ($row.Count -ne 1) { throw "local_builds: not an inventory mod folder: $dir" }
            $slot = & (Join-Path $here 'Get-RigSlot.ps1') -Slot ([int]$lb.slot) -Workshop $workshop -SlotsFile $SlotsFile
            $check = & (Join-Path $here 'Test-RigSlot.ps1') -SlotDir $slot.Dir -Mod $dir
            if (-not $check.Ok) { throw "local_builds: slot $($slot.Slot) ($($slot.Id)) for $dir does not match its slot.json: $($check.Problems -join '; ')" }
            $localBuilds += [ordered]@{
                mod = $dir; mod_id = [string]$row[0].ModId; slot = $slot.Slot; slot_id = $slot.Id; real_id = [string]$row[0].WorkshopId
                commit = [string]$check.Info.commit; dirty = [bool]$check.Info.dirty; version = [string]$check.Info.version
                real_dir = (Join-Path $workshop ([string]$row[0].WorkshopId)); real_folder_unchanged = $null
            }
        }
    }
    $acf = Get-Content -LiteralPath (Join-Path $steamApps 'appmanifest_552500.acf') -Raw
    # WP-H-11: the game build and the harness checkout's commit go into summary.json (Publish-Evidence.ps1 cites both)
    $gameBuild = [regex]::Match($acf, '"buildid"\s+"(\d+)"').Groups[1].Value
    $repoCommit = ''
    try { $repoCommit = [string](& git -C (Join-Path $here '..\..') rev-parse HEAD 2>$null) } catch { }
    if ($acf -notmatch '"StateFlags"\s+"4"') { throw 'VT2 is not fully installed (StateFlags is not 4).' }
    $exe = if ($Renderer -eq 'dx12') { Join-Path $install.BinariesDx12 'vermintide2_dx12.exe' } else { Join-Path $install.Binaries 'vermintide2.exe' }
    if (-not (Test-Path -LiteralPath $exe)) { throw "Game exe not found: $exe" }
}
catch { Write-Host "RIG REFUSED: $($_.Exception.Message)"; exit 3 }

# ---------- rig lock (WP-H-09 queue: -Wait <minutes>) ----------
# One run at a time. A plan with boots holds the lock in Invoke-RigBoots.ps1 on this same thread, so a boot's own
# WaitOne returns at once (a mutex is re-entrant for its owning thread). An abandoned lock (its holder died) is ours.
$mutex = [System.Threading.Mutex]::new($false, $LockName)
$waitMs = [int]([math]::Max(0.0, [double]$Wait) * 60000)
if ($waitMs -gt 0) { Write-Host "waiting up to $Wait min for the rig lock" }
$gotLock = $false
try { $gotLock = $mutex.WaitOne($waitMs) } catch [System.Threading.AbandonedMutexException] { $gotLock = $true }
if (-not $gotLock) { Write-Host "RIG REFUSED: another rig run holds the lock$(if ($waitMs -gt 0) { " (waited $Wait min)" })."; $mutex.Dispose(); exit 3 }

# ---------- preflight under the lock: nothing else may be running (WP-H-09 step 3) ----------
try {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(vermintide2|vermintide2_dx12|vermintide2_launcher)$' }
    if ($running) { throw "A Vermintide process is already running (pid $($running.Id -join ', ')). Refusing to start." }
    $busyNames = @()
    if (Test-Path -LiteralPath $BusyProcessesFile) {
        $busyNames = @([System.IO.File]::ReadAllLines($BusyProcessesFile) | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ } | ForEach-Object { $_ -replace '\.exe$', '' })
    }
    $busy = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $busyNames -contains $_.ProcessName })
    if ($busy.Count) { throw "A busy process is running ($((@($busy | ForEach-Object { "$($_.ProcessName) pid $($_.Id)" })) -join ', '); busy-processes.txt). Refusing to start." }
    if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Steam is not running.' }
    $mem = Get-CimInstance Win32_OperatingSystem
    if ($mem.FreePhysicalMemory / 1MB -lt $MinFreeGiB) { throw "Free RAM below $MinFreeGiB GiB ($([math]::Round($mem.FreePhysicalMemory / 1MB, 1)) GiB)." }
}
catch { Write-Host "RIG REFUSED: $($_.Exception.Message)"; $mutex.ReleaseMutex(); $mutex.Dispose(); exit 3 }

$nonce = -join ((1..8) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$run = if ($RunDir) { $RunDir } else { Join-Path $RigRoot "runs\$stamp-$Name-$nonce" }
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
if ($planObj) { $profileArgs.PlanPath = $planPath; $profileArgs.Nonce = $nonce; $profileArgs.DriverFile = $DriverFile; $profileArgs.SharedDir = $SharedDir; $profileArgs.LibDir = $LibDir }
if ($localBuilds.Count) {
    $swaps = @{}; $versions = @{}
    foreach ($lb in $localBuilds) { $swaps[$lb.real_id] = $lb.slot_id; if ($lb.version) { $versions[$lb.mod_id] = $lb.version } }
    $profileArgs.SlotSwaps = $swaps; $profileArgs.ExpectVersions = $versions
}
function Get-FolderHashes([string] $dir) {
    $h = [ordered]@{}
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Sort-Object Name)) { $h[$f.Name] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash }
    ($h.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';'
}
$realFoldersBefore = @{}; foreach ($lb in $localBuilds) { $realFoldersBefore[$lb.real_id] = Get-FolderHashes $lb.real_dir }
# WP-H-08: a later boot of a plan with boots keeps the profile the boot before it left
if ($KeepProfile) { $profileArgs.KeepProfile = $true }
try { $rigProfile = & (Join-Path $here 'New-RigProfile.ps1') @profileArgs }
catch { Write-Host "RIG REFUSED: profile: $($_.Exception.Message)"; $mutex.ReleaseMutex(); exit 3 }
$profileRoot = $rigProfile.ProfileRoot
$rigAppData = $rigProfile.AppData
$rigLocal = $rigProfile.LocalAppData
$rigVt2 = $rigProfile.Vt2Dir
if ($planObj) { Copy-Item -LiteralPath $planPath -Destination (Join-Path $run 'plan.json') }

# ---------- launch ----------
if (-not ('Vt2GameProcess' -as [type])) { Add-Type -Path (Join-Path $here 'GameProcess.cs') }
# WP-H-02: ask the game to write its console log into the run folder; Find-RunLog.ps1 falls back to the
# profile's console_logs folder when that file does not appear within 20 s.
$switchLog = Join-Path $run 'console.log'
$profileLogDir = Join-Path $rigVt2 'console_logs'
if ($switchLog.Contains('"')) { Write-Host "RIG REFUSED: quote in the run folder path: $switchLog"; $mutex.ReleaseMutex(); exit 3 }
$arguments = "-eac-untrusted --bundle-dir ../bundle --ini settings --silent-mode -skip-splash --default-console-log-path `"$switchLog`" -vt2-test-run $nonce $ExtraArgs".Trim()
$childEnv = @{ SteamAppId = '552500'; SteamGameId = '552500'; USERPROFILE = $profileRoot; APPDATA = $rigAppData; LOCALAPPDATA = $rigLocal }
if ($TimeoutSeconds -le 0) { $TimeoutSeconds = [int](($planObj.timeout ?? 180)) + 240 }
$started = Get-Date
$proc = $null; $verdict = 'UNKNOWN'; $notes = [System.Collections.Generic.List[string]]::new()
$marks = [ordered]@{}; $logPath = $null; $logSource = $null; $stopAt = $null; $text = ''; $lastHb = $started; $lastNote = ''
# WP-H-09 liveness and resource floor: the driver's checkpoint (seq, t) must keep moving; free RAM must stay above the floor
$hostStop = ''; $hostStopDetail = ''; $lastProgressAt = $started; $lastProgressKey = ''; $progressPhase = ''
# WP-H-10 stills: one capture per vt2_rig_shot request, while the driver holds still
$shots = [System.Collections.Generic.List[object]]::new(); $lastShotSeq = 0; $shotStamp = [datetime]::MinValue
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
        if (-not $logPath -or $logSource -eq 'profile-fallback') {
            $found = & (Join-Path $here 'Find-RunLog.ps1') -SwitchPath $switchLog -ProfileLogDir $profileLogDir -Started $started -Now $now
            if ($found -and $found.Path -ne $logPath) {
                if (-not $logPath) { $marks['log_created'] = [math]::Round(($now - $started).TotalSeconds, 1) }
                $logPath = $found.Path; $logSource = $found.Source
            }
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
                    $key = [regex]::Match($pm.Value, '(?m)^\tseq = (\S+)').Groups[1].Value + '/' + [regex]::Match($pm.Value, '(?m)^\tt = (\S+)').Groups[1].Value
                    if ($key -ne $lastProgressKey) { $lastProgressKey = $key; $lastProgressAt = $now }
                    $progressPhase = [regex]::Match($pm.Value, '(?m)^\tphase = "([^"]*)"').Groups[1].Value
                }
            } catch { }
            # before the driver's first checkpoint, and while it boots or loads, the long limit applies
            $limit = if (-not $lastProgressKey -or $progressPhase -in 'BOOT', 'LOADING') { $StallLoadSeconds } else { $StallPlaySeconds }
            $age = ($now - $lastProgressAt).TotalSeconds
            if ($age -gt $limit) {
                $hostStop = 'stalled'; $hostStopDetail = "no progress checkpoint for $([math]::Round($age)) s in phase $(if ($progressPhase) { $progressPhase } else { 'none yet' }), limit $limit s"
                $notes.Add("stalled: $hostStopDetail"); $verdict = 'STALLED-KILLED'; $proc.Kill(); break
            }
            try {
                $freeGiB = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB
                if ($freeGiB -lt $StopFreeGiB) {
                    $hostStop = 'low-ram'; $hostStopDetail = "$([math]::Round($freeGiB, 2)) GiB free, floor $StopFreeGiB GiB"
                    $notes.Add("low RAM: $hostStopDetail"); $verdict = 'LOW-RAM-KILLED'; $proc.Kill(); break
                }
            } catch { }
        }
        if ($planObj) {
            try {
                $cfgFile = Join-Path $rigVt2 'user_settings.config'
                $cfgStamp = [System.IO.File]::GetLastWriteTimeUtc($cfgFile)
                if ($cfgStamp -ne $shotStamp) {
                    $shotStamp = $cfgStamp
                    $sm = [regex]::Match([System.IO.File]::ReadAllText($cfgFile), '(?ms)^vt2_rig_shot = \{.*?^\}')
                    if ($sm.Success -and $sm.Value -match 'nonce = "' + $nonce + '"') {
                        $sseq = [int][regex]::Match($sm.Value, '(?m)^\tseq = (\d+)').Groups[1].Value
                        if ($sseq -gt $lastShotSeq) {
                            for ($k = $lastShotSeq + 1; $k -lt $sseq; $k++) { $shots.Add([ordered]@{ seq = $k; ok = $false; error = 'the next request replaced it before the host saw it' }) }
                            $lastShotSeq = $sseq
                            $sCase = [regex]::Match($sm.Value, '(?m)^\tcase = "([^"]*)"').Groups[1].Value
                            $sLabel = [regex]::Match($sm.Value, '(?m)^\tlabel = "([^"]*)"').Groups[1].Value
                            $stillDir = Join-Path $run 'stills'
                            New-Item -ItemType Directory -Force -Path $stillDir | Out-Null
                            $safe = (($sCase + '-' + $sLabel) -replace '[^A-Za-z0-9_.-]', '_'); if ($safe.Length -gt 60) { $safe = $safe.Substring(0, 60) }
                            $png = Join-Path $stillDir ('{0:000}-{1}.png' -f $sseq, $safe)
                            $still = $proc.CaptureStill($png)
                            $shots.Add([ordered]@{
                                seq = $sseq; case = $sCase; label = $sLabel; ok = $still.Ok; route = $still.Route; window = $still.Window
                                file = $(if ($still.Ok) { "stills\$(Split-Path -Leaf $png)" } else { $null }); width = $still.Width; height = $still.Height
                                mean_brightness = [math]::Round($still.MeanBrightness, 1); error = $still.Error; seconds = [math]::Round(($now - $started).TotalSeconds, 1)
                            })
                            Write-Host ("  [{0,5:N0}s] still {1} {2}: {3}" -f ($now - $started).TotalSeconds, $sseq, $sLabel, $(if ($still.Ok) { "$($still.Width)x$($still.Height) mean $([math]::Round($still.MeanBrightness, 1))" } else { $still.Error }))
                        }
                    }
                }
            } catch { }
        }
        if (-not $Visible) {
            $w = $proc.WindowsOnUserDesktop()
            if ($w.Count -gt 0) { $notes.Add("WINDOW ON USER DESKTOP: $($w -join '; ')"); $verdict = 'VISIBLE-WINDOW'; $hostStop = 'visible-window'; $proc.Kill(); break }
        }
        if ($stopAt -and $now -ge $stopAt) { $verdict = 'STOPPED-ON-PATTERN'; $hostStop = 'stopped-on-pattern'; $proc.Kill(); break }
        if ($now -ge $deadline) { $verdict = 'HOST-TIMEOUT-KILLED'; $hostStop = 'host-timeout'; $hostStopDetail = "$TimeoutSeconds s"; $proc.Kill(); break }
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
$found = & (Join-Path $here 'Find-RunLog.ps1') -SwitchPath $switchLog -ProfileLogDir $profileLogDir -Started $started -FallbackAfterSeconds 0
if ($found) { $logPath = $found.Path; $logSource = $found.Source }
$evidenceLog = $switchLog
if ($logPath) {
    if (Test-Path -LiteralPath $switchLog -PathType Container) { $evidenceLog = Join-Path $run 'console.game.log' }
    if ($logPath -ne $evidenceLog) { Copy-Item -LiteralPath $logPath -Destination $evidenceLog -Force }
    $text = Get-Content -LiteralPath $logPath -Raw
}
Copy-Item -LiteralPath (Join-Path $rigVt2 'user_settings.config') -Destination (Join-Path $run 'user_settings.after.config') -Force
# WP-H-09 step 2: a new crash dump is copied into <run>\crash\ (up to 64 MiB each; the log is already in the run folder)
$dumps = @(Get-ChildItem -LiteralPath (Join-Path $rigVt2 'crash_dumps') -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $started })
foreach ($d in $dumps) {
    if ($d.Length -le 64MB) {
        New-Item -ItemType Directory -Force -Path (Join-Path $run 'crash') | Out-Null
        Copy-Item -LiteralPath $d.FullName -Destination (Join-Path $run "crash\$($d.Name)") -Force
        $notes.Add("crash dump: $($d.Name) $($d.Length) bytes (copied to crash\)")
    }
    else { $notes.Add("crash dump: $($d.Name) $($d.Length) bytes (over 64 MiB, not copied)") }
}
$after = @{}; foreach ($f in $watched) { $after[$f] = Get-FileSha (Join-Path $realProfile $f) }
$isolation = 'OK'
foreach ($f in $watched) { if ($before[$f] -ne $after[$f]) { $isolation = 'BROKEN'; $notes.Add("owner file changed: $f") } }
$realLogsAfter = @(Get-ChildItem -LiteralPath (Join-Path $realProfile 'console_logs') -Filter 'console-*.log' -ErrorAction SilentlyContinue | ForEach-Object Name)
$leaked = @($realLogsAfter | Where-Object { $_ -notin $realLogsBefore })
if ($leaked.Count) { $isolation = 'BROKEN'; $notes.Add("log written to the owner's real profile: $($leaked -join ', ')") }
# WP-H-07: the real Workshop folder of every locally built mod must be byte-identical before and after
foreach ($lb in $localBuilds) {
    $lb.real_folder_unchanged = ((Get-FolderHashes $lb.real_dir) -ceq $realFoldersBefore[$lb.real_id])
    if (-not $lb.real_folder_unchanged) { $notes.Add("real Workshop folder of $($lb.mod) ($($lb.real_id)) changed during the run") }
}

# evidence lines
$lines = @(); if ($text) { $lines = @([regex]::Matches($text, '(?m)^.*\[vt2t:' + $nonce + '\] (.*)$') | ForEach-Object { $_.Groups[1].Value.TrimEnd() }) }
$lines | Set-Content -LiteralPath (Join-Path $run 'evidence.txt')
$runEnd = [bool]($lines | Where-Object { $_ -match '^RUN END' })
# WP-H-08 step 4: the driver makes the lobby private at KEEP READY and says whether the game reports it private
$lobbyPrivate = $null
foreach ($l in $lines) { if ($l -match '^LOBBY private=(true|false)(\s|$)') { $lobbyPrivate = $Matches[1] -eq 'true' } }
if ($planObj -and ($lines | Where-Object { $_ -match '^KEEP READY' }) -and $lobbyPrivate -ne $true) { $notes.Add('the lobby was not reported private after KEEP READY (LOBBY line)') }
$scriptErrors = @([regex]::Matches($text, '(?m)^.*(\[Script Error\]|<<Script Error>>|Lua Stack).*$') | Select-Object -First 5 | ForEach-Object { $_.Value.Trim() })

# host_expect_log / host_forbid_log with their defaults (WP-H-02), the backend write shield defaults and timing
# (WP-H-14), time to KEEP READY and load banners: all in Read-HostLog.ps1. No-plan experiments get none of the
# defaults.
$shieldOn = [bool]($planObj -and -not ($planObj.PSObject.Properties['backend_shield'] -and $planObj.backend_shield -eq $false))
$hostArgs = @{ Text = [string]$text; Nonce = $nonce }
if ($planObj) { $hostArgs.PlanFile = $planPath }
# WP-H-07: each local build's load banner must show the staged version
$bannerExpect = @($localBuilds | Where-Object { $_.version } | ForEach-Object { '\[[A-Za-z_]+:LOAD\] v' + [regex]::Escape($_.version) + '(?![0-9A-Za-z.+\-])' })
if ($bannerExpect.Count) { $hostArgs.Expect = $bannerExpect }
$hostLog = & (Join-Path $here 'Read-HostLog.ps1') @hostArgs
$forbidHits = @($hostLog.ForbidHits)
$expectMisses = @($hostLog.ExpectMisses)
$shieldFirst = $hostLog.ShieldInstalledBeforeFirstCommit
foreach ($h in $forbidHits) { Write-Host "FORBIDDEN LOG LINE ($($h.rule)): $($h.line)" }
foreach ($p in $expectMisses) { Write-Host "EXPECTED LOG LINE MISSING: $p" }
foreach ($e in @($hostLog.AllowErrors)) { $notes.Add("host_allow_log: $e") }

# WP-H-09: the case table, with CRASH, host stops and verdicts recovered from the last progress checkpoint
$progressCurrent = ''; $progressVerdicts = ''
$afterCfg = Join-Path $run 'user_settings.after.config'
if (Test-Path -LiteralPath $afterCfg) {
    $pm = [regex]::Match([System.IO.File]::ReadAllText($afterCfg), '(?ms)^vt2_rig_progress = \{.*?^\}')
    if ($pm.Success -and $pm.Value -match 'nonce = "' + $nonce + '"') {
        $progressCurrent = [regex]::Match($pm.Value, '(?m)^\tcurrent = "([^"]*)"').Groups[1].Value
        $progressVerdicts = [regex]::Match($pm.Value, '(?m)^\tverdicts = "([^"]*)"').Groups[1].Value
    }
}
$crashed = [bool]($planObj -and -not $runEnd -and ($dumps.Count -gt 0 -or (-not $hostStop -and $verdict -like 'EXITED*')))
$crashDetail = if ($dumps.Count) { "crash dump $($dumps[0].Name)" } elseif ($crashed) { "process $verdict without RUN END" } else { '' }
$planCaseIds = @(); if ($planObj -and $planObj.PSObject.Properties['cases']) { $planCaseIds = @($planObj.cases | ForEach-Object { [string]$_.id }) }
$verdictArgs = @{ Lines = [string[]]$lines; PlanCaseIds = [string[]]$planCaseIds; RunEnd = $runEnd; Crashed = $crashed; CrashDetail = $crashDetail; HostStop = $hostStop; HostStopDetail = $hostStopDetail; ProgressCurrent = $progressCurrent; ProgressVerdicts = $progressVerdicts }
$runVerdicts = & (Join-Path $here 'Get-RunVerdicts.ps1') @verdictArgs
$cases = @($runVerdicts.Cases)

$exit = 2
if ($isolation -ne 'OK') { $exit = 3 }
elseif ($planObj) { $exit = $runVerdicts.Exit }
else { $exit = 0 }
if (($forbidHits.Count -or $expectMisses.Count) -and $exit -ne 3) { $exit = 1 }
# WP-H-10: every saved still request must have a still; with "require_stills" each must also be the right size and not black
$shotRequests = @($lines | Where-Object { $_ -match '^SHOT REQ .* saved=true' }).Count
if ($shots.Count) { $shots | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $run 'shots.json') -Encoding utf8 }
if ($planObj -and $planObj.PSObject.Properties['require_stills'] -and $planObj.require_stills -eq $true) {
    $wantSize = @(1280, 720); if ($planObj.PSObject.Properties['still_size'] -and $planObj.still_size) { $wantSize = @($planObj.still_size | ForEach-Object { [int]$_ }) }
    $floor = 8; if ($planObj.PSObject.Properties['still_min_brightness']) { $floor = [double]$planObj.still_min_brightness }
    $bad = @()
    if ($shots.Count -lt $shotRequests -or $shotRequests -eq 0) { $bad += "$($shots.Count) still(s) for $shotRequests saved request(s)" }
    foreach ($sh in $shots) {
        if (-not $sh.ok) { $bad += "still $($sh.seq): $($sh.error)" }
        elseif ($sh.width -ne $wantSize[0] -or $sh.height -ne $wantSize[1]) { $bad += "still $($sh.seq): $($sh.width)x$($sh.height), want $($wantSize[0])x$($wantSize[1])" }
        elseif ($sh.mean_brightness -lt $floor) { $bad += "still $($sh.seq): mean brightness $($sh.mean_brightness) under $floor" }
    }
    foreach ($b in $bad) { $notes.Add("require_stills: $b") }
    if ($bad.Count -and $exit -eq 0) { $exit = 2 }
}
# WP-H-03: a plan with "sweep": true turns the regression suites' output into sweep.json / sweep.md; a FAIL row
# fails the run (exit 1). A suite that never returned, or a plan mod no suite printed for (missing_suites), leaves an
# otherwise passing run incomplete (exit 2).
$sweep = $null
if ($planObj -and $planObj.PSObject.Properties['sweep'] -and $planObj.sweep -eq $true) {
    $expectMods = @(); if ($planObj.PSObject.Properties['expect_mods'] -and $planObj.expect_mods) { $expectMods = @($planObj.expect_mods | ForEach-Object { [string]$_ }) }
    $sweepResult = & (Join-Path $here 'Parse-Sweep.ps1') -EvidenceFile (Join-Path $run 'evidence.txt') -LogFile ([string]$logPath) -OutDir $run -ExpectMods $expectMods -Quiet
    $sweep = $sweepResult.Counts
    if ($sweep.fail -gt 0 -and $exit -ne 3) { $exit = 1 }
    elseif (($sweep.inconclusive_suites + $sweep.missing_suites) -gt 0 -and $exit -eq 0) { $exit = 2 }
}
# WP-H-09 step 7: a FAIL is re-run once alone in a fresh boot before it is reported; PASS alone = order-dependent
$orderCheck = @()
$failed = @($cases | Where-Object { $_.verdict -eq 'FAIL' } | ForEach-Object { $_.id })
if ($planObj -and -not $NoOrderCheck -and $isolation -eq 'OK' -and $failed.Count -and $planCaseIds.Count -gt 1) {
    $orderArgs = @{ Renderer = $Renderer; ExtraArgs = $ExtraArgs; DriverFile = $DriverFile; DriverId = $DriverId; SharedDir = $SharedDir; LibDir = $LibDir; SlotsFile = $SlotsFile; SteamApps = $SteamApps; Wait = $Wait; LockName = $LockName; BusyProcessesFile = $BusyProcessesFile }
    if ($Visible) { $orderArgs.Visible = $true }
    $orderCheck = @(& (Join-Path $here 'Invoke-OrderCheck.ps1') -PlanPath $planPath -RunDir $run -CaseIds $failed -RigRoot $RigRoot -RunScript $PSCommandPath -ChildArgs $orderArgs)
    foreach ($o in $orderCheck) {
        $c = @($cases | Where-Object { $_.id -eq $o.id })[0]
        if ($c) { $c.alone_verdict = $o.alone_verdict; $c.order_dependent = $o.order_dependent }
        $notes.Add("order check: $($o.id) FAIL in the plan, $(if ($o.alone_verdict) { $o.alone_verdict } else { 'no verdict' }) alone ($($o.folder))$(if ($o.order_dependent) { ': order-dependent' })")
    }
}
elseif ($planObj -and $failed.Count -and $planCaseIds.Count -gt 1) { $notes.Add('order check skipped' + $(if ($NoOrderCheck) { ' (-NoOrderCheck)' } else { " (isolation $isolation)" })) }

# WP-H-09 step 5: retention, opt-in (-Retain), top-level runs only (a boot or a re-run lives inside its parent's folder)
$retention = $null
if (-not $RunDir -and $Retain -gt 0) {
    try { $retention = & (Join-Path $here 'Remove-OldRuns.ps1') -RunsDir (Join-Path $RigRoot 'runs') -Retain $Retain -ReportsDir $ReportsDir -Protect $run }
    catch { $notes.Add("retention failed: $($_.Exception.Message)") }
}

$summary = [ordered]@{
    run = "$stamp-$Name-$nonce"; name = $Name; nonce = $nonce; verdict = $verdict; exit = $exit; isolation = $isolation
    run_state = $runVerdicts.State; running_case = $runVerdicts.Running; host_stop = $hostStop; host_stop_detail = $hostStopDetail
    crashed = $crashed; crash_dumps = @($dumps | ForEach-Object { $_.Name }); order_check = $orderCheck
    retention_removed = @($retention.Removed | Where-Object { $_ })
    private_desktop = (-not $Visible); renderer = $Renderer; arguments = $arguments; run_end_seen = $runEnd
    keep_ready_seconds = $hostLog.KeepReadySeconds; keep_ready_driver_t = $hostLog.KeepReadyDriverT
    backend_shield = [bool]$shieldOn; shield_installed_before_first_commit = $shieldFirst
    save = $rigProfile.Save; lobby_private = $lobbyPrivate; shot_requests = $shotRequests; shots = @($shots)
    game_build = $gameBuild; repo_commit = $repoCommit.Trim()
    host_forbid_hits = $forbidHits; host_expect_misses = $expectMisses; host_allowed = @($hostLog.Allowed)
    loaded_versions = $hostLog.LoadedVersions; local_builds = @($localBuilds); level_loads = @($hostLog.LevelLoads); sweep = $sweep
    marks_seconds = $marks; cases = $cases; script_errors = $scriptErrors; evidence_lines = $lines.Count
    log = $evidenceLog; log_source = $logSource; notes = $notes
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'summary.json') -Encoding utf8
$md = @("# Rig run $($summary.run)", '', "Verdict: $verdict | exit $exit | isolation $isolation | RUN END seen: $runEnd", '', '| Case | Verdict | Asserts | Failed | Seconds | Detail |', '|---|---|---|---|---|---|')
foreach ($c in $cases) { $md += "| $($c.id) | $($c.verdict) | $($c.asserts) | $($c.failed) | $($c.seconds) | $($c.detail) |" }
$md += ''
$md += "KEEP READY after $($hostLog.KeepReadySeconds) s of log (driver t=$($hostLog.KeepReadyDriverT)) | log source: $logSource"
$md += "Backend shield: $(if ($shieldOn) { 'on' } else { 'off' }) | installed before first commit: $shieldFirst"
foreach ($h in $forbidHits) { $md += "Forbidden log line ($($h.rule)): ``$($h.line)``" }
foreach ($p in $expectMisses) { $md += "Expected log line missing: ``$p``" }
foreach ($a in @($hostLog.Allowed)) { $md += "Allowed log line ($($a.rule)): ``$($a.line)`` -- $($a.reason)" }
foreach ($lb in $localBuilds) { $md += "Local build: $($lb.mod) $($lb.version) at $($lb.commit)$(if ($lb.dirty) { ' (dirty)' }) in slot $($lb.slot) ($($lb.slot_id)) | real folder unchanged: $($lb.real_folder_unchanged)" }
foreach ($ll in @($hostLog.LevelLoads)) { $md += "Level load: $($ll.level) $(if ($ll.failed) { $ll.failed } else { "$($ll.seconds) s" })" }
foreach ($sh in $shots) { $md += "Still $($sh.seq) ($($sh.case), $($sh.label)): $(if ($sh.ok) { "$($sh.file) $($sh.width)x$($sh.height) mean brightness $($sh.mean_brightness) via $($sh.route)" } else { "not captured: $($sh.error)" })" }
if ($sweep) { $md += "Regression sweep: rows $($sweep.rows), PASS $($sweep.pass), FAIL $($sweep.fail), SKIP $($sweep.skip), inconclusive suites $($sweep.inconclusive_suites), missing suites $($sweep.missing_suites) (sweep.md)" }
if (@($hostLog.LoadedVersions.Keys).Count) { $md += "Load banners: $((@($hostLog.LoadedVersions.Keys) | ForEach-Object { "$_ $($hostLog.LoadedVersions[$_])" }) -join ', ')" }
$md | Set-Content -LiteralPath (Join-Path $run 'summary.md') -Encoding utf8
$summary | ConvertTo-Json -Depth 6
exit $exit
