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
      "cases": [ { "id": "smoke-keep", "arena": "keep", "file": "cases/smoke_keep.lua" } ]
    }
  Case files are Lua source that returns a table { issue = <n>, timeout = <s>, run = function(T) ... end }.

  Exit code: 0 = run completed and every case PASS; 1 = at least one FAIL; 2 = ERROR/TIMEOUT/INCONCLUSIVE or
  the run did not complete; 3 = rig refused to start or isolation was broken.

.NOTES
  Never starts if any Vermintide process exists. Never kills a process it did not start (job object).
  Nothing is written to the persistent environment.
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
    [string] $RigRoot = (Join-Path $env:USERPROFILE '.claude\vt2-harness'),
    [string] $StopOnLog = '',               # no-plan experiments: stop when this regex appears in the log
    [int] $StopDelaySeconds = 5,
    [switch] $KeepOwnerMods                 # no-plan experiments: leave the copied mod list as it is
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$steamApps = 'C:\Program Files (x86)\Steam\steamapps'
$game = Join-Path $steamApps 'common\Warhammer Vermintide 2'
$workshop = Join-Path $steamApps 'workshop\content\552500'
$realProfile = Join-Path $env:APPDATA 'Fatshark\Vermintide 2'

function Get-FileSha([string] $p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { 'absent' } }
function ConvertTo-Hex([string] $text) { -join ([System.Text.Encoding]::UTF8.GetBytes($text) | ForEach-Object { $_.ToString('x2') }) }
function ConvertTo-SjsonString([string] $s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }

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
    $acf = Get-Content -LiteralPath (Join-Path $steamApps 'appmanifest_552500.acf') -Raw
    if ($acf -notmatch '"StateFlags"\s+"4"') { throw 'VT2 is not fully installed (StateFlags is not 4).' }
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^(vermintide2|vermintide2_dx12|vermintide2_launcher)$' }
    if ($running) { throw "A Vermintide process is already running (pid $($running.Id -join ', ')). Refusing to start." }
    if (-not (Get-Process -Name steam -ErrorAction SilentlyContinue)) { throw 'Steam is not running.' }
    $exe = if ($Renderer -eq 'dx12') { Join-Path $game 'binaries_dx12\vermintide2_dx12.exe' } else { Join-Path $game 'binaries\vermintide2.exe' }
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
$driverSource = $null
if ($planObj) {
    if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $workshop $DriverId) 'vt2_rig_driver.mod'))) {
        Write-Host "RIG REFUSED: bootstrap item $DriverId is not installed. Run steam-ugc.ps1 -ItemId $DriverId first."; $mutex.ReleaseMutex(); exit 3
    }
    $driverSource = Get-Content -LiteralPath $DriverFile -Raw
}

# ---------- profile ----------
$profileRoot = Join-Path $RigRoot 'profile'
$rigAppData = Join-Path $profileRoot 'AppData\Roaming'
$rigLocal = Join-Path $profileRoot 'AppData\Local'
$rigVt2 = Join-Path $rigAppData 'Fatshark\Vermintide 2'
New-Item -ItemType Directory -Force -Path $rigVt2, $rigLocal, (Join-Path $rigVt2 'console_logs') | Out-Null
foreach ($f in 'save_data.sav', 'save_data.old', 'launcher.config') {
    $src = Join-Path $realProfile $f
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $rigVt2 $f) -Force }
}
$shader = Join-Path $rigVt2 'shader_cache.pipe_lib'
if (-not (Test-Path -LiteralPath $shader) -and (Test-Path -LiteralPath (Join-Path $realProfile 'shader_cache.pipe_lib'))) {
    Copy-Item -LiteralPath (Join-Path $realProfile 'shader_cache.pipe_lib') -Destination $shader
}
$cfg = (Get-Content -LiteralPath (Join-Path $realProfile 'user_settings.config') -Raw) -replace "`r`n", "`n"
function Set-TopLevel([string] $text, [string] $key, [string] $value) {
    $rx = [regex]("(?m)^" + [regex]::Escape($key) + " = .*$")
    if ($rx.IsMatch($text)) { return $rx.Replace($text, "$key = $value", 1) }
    return "$key = $value`n" + $text
}
$forced = [ordered]@{ borderless_fullscreen = 'false'; fullscreen = 'false'; max_fps = '30'; master_bus_volume = '0' }
if ($planObj -and $planObj.settings) { foreach ($p in $planObj.settings.PSObject.Properties) { $forced[$p.Name] = [string]$p.Value } }
foreach ($k in $forced.Keys) { $cfg = Set-TopLevel $cfg $k $forced[$k] }
$cfg = [regex]::Replace($cfg, '(?ms)^screen_resolution = \[.*?^\]', "screen_resolution = [`n`t1280`n`t720`n]", 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_plan = \{.*?^\}\n', '', 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_results = \{.*?^\}\n', '', 1)
$cfg = [regex]::Replace($cfg, '(?ms)^vt2_rig_progress = \{.*?^\}\n', '', 1)

if ($planObj -or -not $KeepOwnerMods) {
    $wanted = @(); if ($planObj -and $planObj.mods) { $wanted = @($planObj.mods | ForEach-Object { [string]$_ }) }
    if ($planObj) { $wanted += $DriverId }
    # the driver needs an entry in the mods array; add one when missing
    if ($planObj -and $cfg -notmatch ('(?m)^\t\tid = "' + $DriverId + '"')) {
        $entry = "`t{`n`t`tauthor = `"rig`"`n`t`tauthor_id = 0`n`t`tbanned = false`n`t`tdependency_error = `"`"`n`t`tdescription = `"`"`n`t`tdownload_pending = false`n`t`tdownloading = false`n`t`tenabled = true`n`t`tid = `"$DriverId`"`n`t`tinstalled = true`n`t`tlast_updated = `"1/1/2026 12:00:00 AM`"`n`t`tname = `"VT2 Rig Driver`"`n`t`tnum_children = 0`n`t`tout_of_date = false`n`t`tsanctioned = false`n`t`tsubscribed = true`n`t}`n"
        $m = [regex]::Match($cfg, '(?ms)^mods = \[\n.*?^\]')
        if (-not $m.Success) { throw 'mods array not found in user_settings.config' }
        $insertAt = $m.Index + $m.Length - 1
        $cfg = $cfg.Substring(0, $insertAt) + $entry + $cfg.Substring($insertAt)
    }
    $cfg = [regex]::Replace($cfg, '(?m)^(\t\t)enabled = (true|false)(\n\t\tid = "(\d+)")', {
            param($m)
            $on = if ($wanted -contains $m.Groups[4].Value) { 'true' } else { 'false' }
            $m.Groups[1].Value + "enabled = $on" + $m.Groups[3].Value
        })
    # order: the game loads in array order; move wanted entries to the front in the plan's order is not needed
    # as long as VMF stays first and the driver is last, which the insert above guarantees.
}

if ($planObj) {
    $planDir = Split-Path $planPath
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("vt2_rig_plan = {`n")
    [void]$sb.Append("`tnonce = `"$nonce`"`n`tname = $(ConvertTo-SjsonString $planObj.name)`n")
    [void]$sb.Append("`ttimeout = $([int]($planObj.timeout ?? 600))`n`tsettle = $([int]($planObj.settle ?? 4))`n`tquit = true`n")
    if ($planObj.PSObject.Properties['backend_shield'] -and $planObj.backend_shield -eq $false) { [void]$sb.Append("`tbackend_shield = false`n") }
    if ($planObj.arenas) { [void]$sb.Append("`tarenas = [`n"); foreach ($a in $planObj.arenas) { [void]$sb.Append("`t`t$(ConvertTo-SjsonString $a)`n") }; [void]$sb.Append("`t]`n") }
    [void]$sb.Append("`tdriver_hex = `"$(ConvertTo-Hex $driverSource)`"`n")
    [void]$sb.Append("`tcases = [`n")
    foreach ($c in $planObj.cases) {
        $file = Join-Path $planDir $c.file
        if (-not (Test-Path -LiteralPath $file)) { throw "Case file not found: $file" }
        $src = Get-Content -LiteralPath $file -Raw
        [void]$sb.Append("`t`t{`n`t`t`tid = $(ConvertTo-SjsonString $c.id)`n`t`t`tarena = $(ConvertTo-SjsonString ($c.arena ?? 'keep'))`n`t`t`thex = `"$(ConvertTo-Hex $src)`"`n`t`t}`n")
    }
    [void]$sb.Append("`t]`n}`n")
    $cfg = $sb.ToString() + $cfg
    Copy-Item -LiteralPath $planPath -Destination (Join-Path $run 'plan.json')
}
[System.IO.File]::WriteAllText((Join-Path $rigVt2 'user_settings.config'), $cfg, [System.Text.UTF8Encoding]::new($false))

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
