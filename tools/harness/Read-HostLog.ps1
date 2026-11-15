#requires -Version 7
<#
.SYNOPSIS
  Host-side reading of a finished rig run's console log: forbidden and expected lines (WP-H-02 step 3), the
  backend write shield (WP-H-14), the measured time to KEEP READY and the mods' load banners.

.DESCRIPTION
  Forbidden lines. Each rule's first matching line that no host_allow_log entry excuses is a hit:
  - Defaults (with -Defaults, and always when -PlanFile is given), on the game's lines only (the driver's own
    [vt2t:] evidence lines are skipped): "<<Script Error>>", "Lua Stack", "was not found in the workshop folder"
    (Vermintide-2-Source-Code/scripts/managers/mod/mod_manager.lua:297), "Syntax error in .mod file" (:376) and
    "Failed to run callback" (:222).
  - Shield defaults while the shield is on (-ShieldOn, or a plan without backend_shield false): no
    "Enqueuing ExecuteCloudScript request updateHeroAttributes" line
    (scripts/managers/backend_playfab/playfab_request_queue.lua:49), no line naming UpdateUserData, and (WP-H-05) no
    "Enqueuing ExecuteCloudScript request deusRunStarted" line (the driver drops that request; a run start sends it).
  - The plan's own host_forbid_log regexes (or -Forbid), on every line.
  Expected lines: every regex of the plan's host_expect_log (or -Expect) must match some line.
  host_allow_log (plan) / -Allow: entries { "pattern": <regex>, "reason": <text> }. A matching line is excused
  and listed under Allowed; an entry without a reason is ignored and reported under AllowErrors. Never drop a
  default: excuse the one proven-benign line with a reason.
  All matching is case-sensitive.

  With -ExitCode the script prints its findings and exits 1 when there is a hit or a missing expected line,
  else 0, so a log fixture can be judged on its own.

.OUTPUTS
  [pscustomobject] ForbidHits (@{ rule; line }), ExpectMisses (patterns), Allowed (@{ rule; line; reason }),
  AllowErrors, ShieldInstalledBeforeFirstCommit (true, false, 'no commit in log', or $null),
  KeepReadySeconds (log timestamp of KEEP READY minus the first timestamped line, or $null),
  KeepReadyDriverT (the driver's own t= on that line, or $null), LoadedVersions (ordered tag -> version from
  "[<tag>:LOAD] v<version>" banners), LevelLoads (WP-H-04: @{ level; seconds } per driver LEVEL READY line,
  @{ level; failed } per LOAD FAILED / LOAD TIMEOUT line).
#>
[CmdletBinding()]
param(
    [string] $Text = '',
    [string] $LogFile = '',
    [Parameter(Mandatory)] [string] $Nonce,
    [switch] $ShieldOn,
    [switch] $Defaults,
    [string] $PlanFile = '',
    [string[]] $Expect = @(),
    [string[]] $Forbid = @(),
    [object[]] $Allow = @(),
    [switch] $ExitCode
)
$ErrorActionPreference = 'Stop'

if ($LogFile) { $Text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $LogFile).Path) }
$shield = [bool]$ShieldOn
if ($PlanFile) {
    $plan = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PlanFile).Path) | ConvertFrom-Json
    $Defaults = $true
    $shield = -not ($plan.PSObject.Properties['backend_shield'] -and $plan.backend_shield -eq $false)
    if ($plan.PSObject.Properties['host_expect_log']) { $Expect = @($Expect) + @($plan.host_expect_log | ForEach-Object { [string]$_ }) }
    if ($plan.PSObject.Properties['host_forbid_log']) { $Forbid = @($Forbid) + @($plan.host_forbid_log | ForEach-Object { [string]$_ }) }
    if ($plan.PSObject.Properties['host_allow_log']) { $Allow = @($Allow) + @($plan.host_allow_log) }
}

$gameLine = '(?m)^(?!.*\[vt2t:)'
$rules = [ordered]@{}
if ($Defaults) {
    $rules['default: <<Script Error>>'] = $gameLine + '.*<<Script Error>>.*$'
    $rules['default: Lua Stack'] = $gameLine + '.*Lua Stack.*$'
    $rules['default: mod not found in the workshop folder'] = $gameLine + '.*was not found in the workshop folder.*$'
    $rules['default: Syntax error in .mod file'] = $gameLine + '.*Syntax error in \.mod file.*$'
    $rules['default: Failed to run callback'] = $gameLine + '.*Failed to run callback.*$'
}
if ($shield) {
    $rules['shield: updateHeroAttributes request'] = $gameLine + '.*Enqueuing ExecuteCloudScript request\s+updateHeroAttributes\b.*$'
    $rules['shield: UpdateUserData request'] = $gameLine + '.*UpdateUserData.*$'
    # WP-H-05: the driver drops deusRunStarted before it is enqueued, so the game's own enqueue line must never appear
    $rules['shield: deusRunStarted request'] = $gameLine + '.*Enqueuing ExecuteCloudScript request\s+deusRunStarted\b.*$'
}
foreach ($pattern in $Forbid) { if ($pattern) { $rules["plan: $pattern"] = '(?m)^.*(?:' + $pattern + ').*$' } }

$allowRules = [System.Collections.Generic.List[object]]::new()
$allowErrors = [System.Collections.Generic.List[string]]::new()
foreach ($a in $Allow) {
    $pattern = [string]$a.pattern
    $reason = [string]$a.reason
    if (-not $pattern -or [string]::IsNullOrWhiteSpace($reason)) { $allowErrors.Add("host_allow_log entry without pattern or reason: '$pattern'"); continue }
    $allowRules.Add([pscustomobject]@{ Pattern = $pattern; Reason = $reason })
}

$hits = [System.Collections.Generic.List[object]]::new()
$allowed = [System.Collections.Generic.List[object]]::new()
foreach ($rule in $rules.Keys) {
    foreach ($m in [regex]::Matches($Text, $rules[$rule])) {
        $line = $m.Value.Trim()
        $excuse = $null
        foreach ($a in $allowRules) { if ([regex]::IsMatch($line, $a.Pattern)) { $excuse = $a; break } }
        if ($excuse) { $allowed.Add([ordered]@{ rule = $rule; line = $line; reason = $excuse.Reason }); continue }
        $hits.Add([ordered]@{ rule = $rule; line = $line })
        break
    }
}
$misses = @($Expect | Where-Object { $_ -and -not [regex]::IsMatch($Text, $_, [System.Text.RegularExpressions.RegexOptions]::Multiline) })

$tag = '\[vt2t:' + [regex]::Escape($Nonce) + '\] '
$shieldAt = [regex]::Match($Text, $tag + 'SHIELD installed')
$commitAt = [regex]::Match($Text, '_commit_internal')
$order = $null
if ($shieldAt.Success -and $commitAt.Success) { $order = $shieldAt.Index -lt $commitAt.Index }
elseif ($shieldAt.Success) { $order = 'no commit in log' }

function ConvertTo-Seconds([System.Text.RegularExpressions.Match] $m) {
    [int]$m.Groups['h'].Value * 3600 + [int]$m.Groups['m'].Value * 60 + [int]$m.Groups['s'].Value + [int]$m.Groups['ms'].Value / 1000.0
}
$stamp = '(?<h>\d\d):(?<m>\d\d):(?<s>\d\d)\.(?<ms>\d{3}) '
$firstLine = [regex]::Match($Text, '(?m)^' + $stamp)
$keepLine = [regex]::Match($Text, '(?m)^' + $stamp + '.*' + $tag + 'KEEP READY level=\S+ t=(?<t>[\d\.]+)')
$keepSeconds = $null; $keepDriverT = $null
if ($keepLine.Success) {
    $keepDriverT = [double]$keepLine.Groups['t'].Value
    if ($firstLine.Success) {
        $keepSeconds = (ConvertTo-Seconds $keepLine) - (ConvertTo-Seconds $firstLine)
        if ($keepSeconds -lt 0) { $keepSeconds += 86400 }
        $keepSeconds = [math]::Round($keepSeconds, 1)
    }
}

$versions = [ordered]@{}
foreach ($m in [regex]::Matches($Text, '\[(?<tag>[A-Za-z_]+):LOAD\] v(?<v>[0-9][^\s,;]*)')) {
    if (-not $versions.Contains($m.Groups['tag'].Value)) { $versions[$m.Groups['tag'].Value] = $m.Groups['v'].Value }
}

$loads = [System.Collections.Generic.List[object]]::new()
foreach ($m in [regex]::Matches($Text, $tag + '(?:LEVEL READY level=(?<l>\S+) t=[\d\.]+ load_seconds=(?<s>[\d\.]+)|LOAD (?<f>FAILED|TIMEOUT) (?:arena|level)=(?<a>\S+))')) {
    if ($m.Groups['l'].Success) { $loads.Add([ordered]@{ level = $m.Groups['l'].Value; seconds = [double]$m.Groups['s'].Value }) }
    else { $loads.Add([ordered]@{ level = $m.Groups['a'].Value; failed = $m.Groups['f'].Value }) }
}

$result = [pscustomobject]@{
    ForbidHits                       = $hits.ToArray()
    ExpectMisses                     = @($misses)
    Allowed                          = $allowed.ToArray()
    AllowErrors                      = $allowErrors.ToArray()
    ShieldInstalledBeforeFirstCommit = $order
    KeepReadySeconds                 = $keepSeconds
    KeepReadyDriverT                 = $keepDriverT
    LoadedVersions                   = $versions
    LevelLoads                       = $loads.ToArray()
}
if (-not $ExitCode) { return $result }

foreach ($h in $result.ForbidHits) { Write-Host "FORBIDDEN LOG LINE ($($h.rule)): $($h.line)" }
foreach ($p in $result.ExpectMisses) { Write-Host "EXPECTED LOG LINE MISSING: $p" }
foreach ($a in $result.Allowed) { Write-Host "allowed ($($a.rule)): $($a.line) -- $($a.reason)" }
foreach ($e in $result.AllowErrors) { Write-Host "host_allow_log: $e" }
if ($result.ForbidHits.Count -or $result.ExpectMisses.Count) { exit 1 }
Write-Host 'host log OK'
exit 0
