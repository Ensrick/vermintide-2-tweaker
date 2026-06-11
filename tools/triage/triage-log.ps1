# triage-log.ps1
#
# One-screen session digest for a VT2 console log. Default: digest the most
# recent log under %APPDATA%\Fatshark\Vermintide 2\console_logs\.
#
# Usage:
#   .\tools\triage\triage-log.ps1                       # latest log
#   .\tools\triage\triage-log.ps1 -LogFile <path>       # specific log
#   .\tools\triage\triage-log.ps1 -Verbose              # dump full error/warning lines
#
# Reports:
#   * Session window + duration
#   * Per-mod load state (version, settings_fp, hook count) vs expected
#   * Lifecycle (keep load, host join, mission entries, shutdown)
#   * ct multiplayer-sync telemetry (host_sync_arrived + altar PRE/POST counts)
#   * Error / warning category counts
#   * Anomalies (unexpected mods loaded, expected mods missing)

[CmdletBinding()]
param(
    [string]$LogFile,
    # ExpectedMods uses the VMF new_mod() id (the same string that appears in
    # "[MOD][<id>][INFO]"). Some mods use a short id (wt, ct, gt, ...) and
    # others use the long directory name (cosmetics_tweaker, ...). Verified
    # against the .mod files / live log output.
    [string[]]$ExpectedMods = @(
        'wt','ct','gt','crt','cim','bt','mp','gut',
        'cosmetics_tweaker','verminious_dreams_lighting','event_tweaker',
        'character_weapon_variants','dynamic_cosmetic_portraits','enemy_tweaker'
    )
)

$ErrorActionPreference = 'Stop'

# Aliases: ONLY map where the applied-marker prefix differs from the VMF
# mod-id (the string used in "[MOD][<mod_id>][INFO]" and accepted by new_mod()).
# For mods where the marker prefix matches the VMF id verbatim (wt, ct, gt,
# crt, cim, bt, mp, gut, ...) the alias map needs no entry -- the literal
# capture from the regex is already canonical.
$AliasToCanonical = @{
    'cosmetics' = 'cosmetics_tweaker'
    'vdl'       = 'verminious_dreams_lighting'
    'cwv'       = 'character_weapon_variants'
    'dcp'       = 'dynamic_cosmetic_portraits'
    'dyn_port'  = 'dynamic_cosmetic_portraits'
}

function Write-Section { param($Title) Write-Host ""; Write-Host ("== {0} " -f $Title).PadRight(78, '=') -ForegroundColor Cyan }
function Write-OK     { param($Msg) Write-Host "  [OK]   $Msg" -ForegroundColor Green }
function Write-WARN   { param($Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-FAIL   { param($Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Write-INFO   { param($Msg) Write-Host "  $Msg" }

# ---------------------------------------------------------------------------
# Find log
# ---------------------------------------------------------------------------
if (-not $LogFile) {
    $logDir = Join-Path $env:APPDATA "Fatshark\Vermintide 2\console_logs"
    if (-not (Test-Path $logDir)) { throw "Log dir not found: $logDir" }
    $latest = Get-ChildItem $logDir -Filter "console-*.log" |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No console-*.log files in $logDir" }
    $LogFile = $latest.FullName
}
if (-not (Test-Path $LogFile)) { throw "Log not found: $LogFile" }
$logInfo = Get-Item $LogFile

Write-Host ""
Write-Host ("VT2 SESSION TRIAGE  --  {0}" -f (Split-Path $LogFile -Leaf)) -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ("  size {0:N0} bytes,  modified {1}" -f $logInfo.Length, $logInfo.LastWriteTime)

# ---------------------------------------------------------------------------
# Slurp + parse session bounds
# ---------------------------------------------------------------------------
$lines = Get-Content $LogFile
$tsRe  = '^(\d{2}:\d{2}:\d{2}\.\d{3})'

$firstTs = $null; $lastTs = $null
foreach ($l in $lines) {
    if ($l -match $tsRe) { if (-not $firstTs) { $firstTs = $matches[1] }; $lastTs = $matches[1] }
}
$duration = ""
if ($firstTs -and $lastTs) {
    $a = [TimeSpan]::Parse(($firstTs -replace '\.','.'))
    $b = [TimeSpan]::Parse(($lastTs  -replace '\.','.'))
    if ($b -lt $a) { $b = $b.Add([TimeSpan]::FromHours(24)) }   # crossed midnight
    $duration = "{0:hh\:mm\:ss}" -f ($b - $a)
}

Write-Section "Session"
Write-INFO ("start={0}   end={1}   duration={2}   lines={3:N0}" -f $firstTs, $lastTs, $duration, $lines.Count)

# ---------------------------------------------------------------------------
# Per-mod load state
# ---------------------------------------------------------------------------
Write-Section "Mods loaded"

# Discover every mod that emitted anything to the log
$allModsSeen = @{}
foreach ($l in $lines) {
    if ($l -match '\[MOD\]\[([^\]]+)\]') { $allModsSeen[$matches[1]] = $true }
}

# Parse applied-marker. Two formats accepted during transition:
#   NEW  "[<short>:LOAD] v<ver> enabled fp=<hash> OK"
#   OLD  "[<short>] enabled v<ver> settings_fp=<hash>"
# Key the result by the canonical mod_id (alias-mapped) so it joins cleanly
# with VMF's "[MOD][<canonical>]" prefix.
$applied = @{}
foreach ($l in $lines) {
    $short = $null; $ver = $null; $fp = $null; $format = $null
    if ($l -match '\[(\w+):LOAD\] v(\S+) enabled .*\bfp=(\w+)') {
        $short = $matches[1]; $ver = $matches[2]; $fp = $matches[3]; $format = 'LOAD'
    } elseif ($l -match '\[(\w+)\] enabled v(\S+) .*\bsettings_fp=(\w+)') {
        $short = $matches[1]; $ver = $matches[2]; $fp = $matches[3]; $format = 'legacy'
    }
    if ($short) {
        $canonical = if ($AliasToCanonical.ContainsKey($short)) { $AliasToCanonical[$short] } else { $short }
        $applied[$canonical] = @{ Version = $ver; Fp = $fp; Alias = $short; Format = $format }
    }
}

# Count hooks installed per mod
$hookCounts = @{}
foreach ($l in $lines) {
    if ($l -match '\[MOD\]\[([^\]]+)\]\[INFO\].*\(hook(?:_safe|_origin)?\):') {
        $m = $matches[1]
        if (-not $hookCounts.ContainsKey($m)) { $hookCounts[$m] = 0 }
        $hookCounts[$m]++
    }
}

# Count INFO/ECHO line volume per mod (chattiness signal)
$infoVolume = @{}
foreach ($l in $lines) {
    if ($l -match '\[MOD\]\[([^\]]+)\]\[INFO\]') {
        $m = $matches[1]
        if (-not $infoVolume.ContainsKey($m)) { $infoVolume[$m] = 0 }
        $infoVolume[$m]++
    }
}

# Build report for every mod that emitted anything
$rows = @()
$expectedSet = @{}
foreach ($e in $ExpectedMods) { $expectedSet[$e] = $true }

foreach ($mod in ($allModsSeen.Keys | Sort-Object)) {
    $isExpected = $expectedSet.ContainsKey($mod)
    $a = $applied[$mod]
    $ver = if ($a) { $a.Version } else { '-' }
    $fp  = if ($a) { $a.Fp      } else { '-' }
    $h   = if ($hookCounts.ContainsKey($mod)) { $hookCounts[$mod] } else { 0 }
    $iv  = if ($infoVolume.ContainsKey($mod)) { $infoVolume[$mod] } else { 0 }
    $rows += [PSCustomObject]@{
        Mod      = $mod
        Status   = if ($a) { 'LOADED' } else { 'no-marker' }
        Version  = $ver
        Hooks    = $h
        InfoLines= $iv
        Fp       = $fp
        Expected = if ($isExpected) { 'yes' } else { 'NO' }
    }
}

$rows | Format-Table -AutoSize | Out-String -Width 110 | Write-Host

# Missing expected
$expectedLoaded = @{}
foreach ($r in $rows) { if ($r.Status -eq 'LOADED') { $expectedLoaded[$r.Mod] = $true } }
foreach ($e in $ExpectedMods) {
    if (-not $allModsSeen.ContainsKey($e)) { Write-INFO ("  (not in this session: {0} -- may be disabled)" -f $e) }
}

# Anomalies: loaded but not in expected list
$anoms = $rows | Where-Object { $_.Expected -eq 'NO' -and $_.Status -eq 'LOADED' }
if ($anoms) {
    Write-Host ""
    Write-WARN "Mods loaded but not in expected list:"
    foreach ($a in $anoms) { Write-WARN ("  {0}  v{1}  hooks={2}" -f $a.Mod, $a.Version, $a.Hooks) }
}

# Chattiness call-out (INFO lines >2000 is excessive)
$chatty = $rows | Where-Object { $_.InfoLines -gt 2000 }
if ($chatty) {
    Write-Host ""
    Write-WARN "Excessive log volume (consider demoting per-call logs to DEBUG):"
    foreach ($c in $chatty) { Write-WARN ("  {0,-30}  {1,6:N0} INFO lines" -f $c.Mod, $c.InfoLines) }
}

# ---------------------------------------------------------------------------
# Lifecycle events
# ---------------------------------------------------------------------------
Write-Section "Lifecycle"

$keepLoads     = $lines | Select-String -Pattern 'nested_level_name\s+levels/inn/world'
$hostJoins     = $lines | Select-String -Pattern 'Connected to host:\s+(\S+)'
$levelLoads    = $lines | Select-String -Pattern 'nested_level_name\s+(levels/\S+)'

if ($keepLoads.Count -gt 0)  { Write-OK ("Keep entered {0} time(s)" -f $keepLoads.Count) }
if ($hostJoins.Count -gt 0)  {
    foreach ($h in $hostJoins) {
        if ($h.Line -match 'Connected to host:\s+(\S+)') {
            Write-OK ("Joined host {0}" -f $matches[1])
        }
    }
}
$missionLoads = $levelLoads | Where-Object { $_.Line -notmatch 'levels/inn/' -and $_.Line -notmatch 'levels/end_screen' -and $_.Line -notmatch 'levels/honor_hall' }
if ($missionLoads.Count -gt 0) {
    Write-OK ("Mission level loads: {0}" -f $missionLoads.Count)
    foreach ($m in ($missionLoads | Select-Object -First 5)) {
        if ($m.Line -match 'nested_level_name\s+(levels/\S+)') {
            Write-INFO ("    -> {0}" -f $matches[1])
        }
    }
}
if ($keepLoads.Count -eq 0 -and $hostJoins.Count -eq 0 -and $missionLoads.Count -eq 0) {
    Write-WARN "No lifecycle events detected (game may not have entered keep)"
}

# ---------------------------------------------------------------------------
# ct multiplayer-sync telemetry
# ---------------------------------------------------------------------------
Write-Section "ct multiplayer / instrumentation"

$ctHostSync   = $lines | Select-String -Pattern '\[ct[^\]]*\][^\]]*altar:host_sync_arrived'
$ctGraphApply = $lines | Select-String -Pattern '\[ct_graph\].*applied host snapshot'
$ctAltarPre   = $lines | Select-String -Pattern '\[ct[^\]]*\].*altar:get_chest_type.*PRE\b'
$ctAltarPost  = $lines | Select-String -Pattern '\[ct[^\]]*\].*altar:get_chest_type.*POST\b'

if ($ctHostSync.Count -gt 0) {
    Write-OK ("ct host_sync_arrived fired {0} time(s)" -f $ctHostSync.Count)
    foreach ($s in ($ctHostSync | Select-Object -First 2)) {
        $clean = ($s.Line -replace '.*\[ct:dbg\] \[altar:host_sync_arrived\] ','')
        Write-INFO ("    {0}" -f $clean.Substring(0,[Math]::Min(140,$clean.Length)))
    }
} else {
    Write-INFO "ct host_sync_arrived: not seen (no CW run as client?)"
}
if ($ctGraphApply.Count -gt 0) {
    Write-OK ("ct_graph snapshot applied {0} time(s)" -f $ctGraphApply.Count)
}
if ($ctAltarPre.Count -gt 0) {
    if ($ctAltarPre.Count -eq $ctAltarPost.Count) {
        Write-OK ("ct altar PRE/POST balanced: {0}/{1} pairs" -f $ctAltarPre.Count, $ctAltarPost.Count)
    } else {
        Write-WARN ("ct altar PRE/POST IMBALANCED: PRE={0}  POST={1}" -f $ctAltarPre.Count, $ctAltarPost.Count)
    }
}

# wt safe_hook / traced_hook install confirmation
$wtSafe   = $lines | Select-String -Pattern '\[wt:safe_hook\] installed'
$wtTraced = $lines | Select-String -Pattern '\[wt:traced_hook\] installed'
Write-Host ""
if ($wtSafe.Count   -gt 0) { Write-OK "wt safe_hook installed (marker present)" }   else { Write-WARN "wt safe_hook marker NOT seen" }
if ($wtTraced.Count -gt 0) { Write-OK "wt traced_hook installed (marker present)" } else { Write-WARN "wt traced_hook marker NOT seen" }

# ---------------------------------------------------------------------------
# Errors + warnings
# ---------------------------------------------------------------------------
Write-Section "Errors and warnings"

# Wrap each result in @(...) so $null pipelines coerce to empty arrays
# (PowerShell quirk: a function-arg positional-binding error happens when
# $null follows another arg, because $null is treated as "no argument").
$luaAttempts  = @($lines | Select-String -Pattern 'attempt to (call|index)')
$scriptErrs   = @($lines | Select-String -Pattern 'script error')
$resourceMiss = @($lines | Select-String -Pattern "Resource '#ID\[")
$matErr       = @($lines | Select-String -Pattern 'Failed looking up material')
$nilValue     = @($lines | Select-String -Pattern 'nil value')
# Real crash signatures only. The engine prints harmless "<<crashify-property>>"
# tags and "setup_crash_report" startup lines on EVERY boot -- excluded here.
$crash        = @($lines | Select-String -Pattern '(Crashed in|FATAL:|Assertion failed|stingray\.exe has stopped)' |
                  Where-Object { $_.Line -notmatch 'crashify-property|setup_crash_report' })

function Show-LogCategory {
    param([string]$Name, $Hits, [string]$Severity)
    # Select-String returns $null when zero matches; coerce to empty array.
    $arr = @($Hits)
    $n = $arr.Count
    if ($n -eq 0) { Write-OK ("{0}: 0" -f $Name); return }
    if ($Severity -eq 'fail') { Write-FAIL ("{0}: {1}" -f $Name, $n) }
    else                      { Write-WARN ("{0}: {1}" -f $Name, $n) }
    foreach ($h in ($arr | Select-Object -First 3)) {
        Write-INFO ("    L{0}: {1}" -f $h.LineNumber, $h.Line.Substring(0,[Math]::Min(150,$h.Line.Length)))
    }
    if ($n -gt 3) { Write-INFO ("    ... and {0} more" -f ($n - 3)) }
}

Show-LogCategory -Name 'Lua runtime errors  (attempt to call/index)' -Hits $luaAttempts  -Severity 'fail'
Show-LogCategory -Name 'Script errors        (script error)'          -Hits $scriptErrs   -Severity 'fail'
Show-LogCategory -Name "Resource lookup fails (Resource '#ID[)"       -Hits $resourceMiss -Severity 'fail'
Show-LogCategory -Name 'Nil-value errors'                             -Hits $nilValue     -Severity 'fail'
Show-LogCategory -Name 'Crash/Assertion lines'                        -Hits $crash        -Severity 'fail'
Show-LogCategory -Name 'MeshObject material misses'                   -Hits $matErr       -Severity 'warn'

if ($matErr.Count -gt 0) {
    $unique = $matErr | ForEach-Object {
        if ($_.Line -match 'material:\s+`(#ID\[\w+\])`') { $matches[1] }
    } | Sort-Object -Unique
    Write-INFO ("    Unique missing materials: {0}" -f ($unique -join ', '))
}

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
Write-Section "Verdict"

$verdictFail = $false
if ($luaAttempts.Count -gt 0)  { $verdictFail = $true }
if ($scriptErrs.Count -gt 0)   { $verdictFail = $true }
if ($resourceMiss.Count -gt 0) { $verdictFail = $true }
if ($crash.Count -gt 0)        { $verdictFail = $true }

# Check every expected mod that emitted ANYTHING also has an applied-marker
$loadFail = @()
foreach ($e in $ExpectedMods) {
    if ($allModsSeen.ContainsKey($e) -and -not $applied.ContainsKey($e)) {
        $loadFail += $e
    }
}
if ($loadFail.Count -gt 0) {
    $verdictFail = $true
    Write-FAIL ("Mods that loaded but never emitted applied-marker: {0}" -f ($loadFail -join ', '))
}

if ($verdictFail) {
    Write-FAIL "SESSION HAD PROBLEMS  --  see above for details"
    exit 1
} else {
    Write-OK "SESSION CLEAN  --  all expected mods applied, no Lua errors, no resource misses"
    exit 0
}
