#requires -Version 7
<#
.SYNOPSIS
  Turns the in-mod regression output of a rig run into sweep.json and sweep.md, one row per check (WP-H-03).

.DESCRIPTION
  Reads the run's evidence.txt: the sweep case (qa/runtime/_rig/sweep_regression.lua) prints
  STEP ... label="run /<command>" before each suite, the driver prints every VMF echo the suite makes as
  OUT mod=<VMF mod name> via=echo text="<text>", and the case notes lines:<command> when the command returned.
  Rows and summaries are recognised with the patterns in tools/harness/sweep-formats.psd1. With -LogFile it also
  reads WP-T-01 engine lines "[<prefix>:rt] <check> <VERDICT> <detail>" from the console log.

  Each row: suite, mod, check, verdict (PASS, FAIL or SKIP), raw (the runner's own word), detail, source.
  XPASS and BAD-SHAPE count as FAIL, XFAIL as SKIP (see the formats file). A check that printed nothing is never
  a PASS: a suite whose command returned without output gets one SKIP row; a suite whose command never returned
  (crash or time limit) is INCONCLUSIVE. Each suite's row count is compared with its own summary line (within 5%).

  Writes <OutDir>\sweep.json and <OutDir>\sweep.md when -OutDir is given. Exit codes: 0 no FAIL row, 1 at least
  one FAIL row, 2 input missing or unreadable.

.OUTPUTS
  [pscustomobject] Rows, Suites, Counts (rows, pass, fail, skip, inconclusive_suites).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $EvidenceFile,
    [string] $LogFile = '',
    [string] $OutDir = '',
    [string] $FormatsFile = (Join-Path $PSScriptRoot 'sweep-formats.psd1'),
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $EvidenceFile -PathType Leaf)) { Write-Host "[sweep] ERROR -- evidence file not found: $EvidenceFile"; exit 2 }
$formats = Import-PowerShellDataFile -LiteralPath $FormatsFile

function Get-Format([string] $mod) {
    foreach ($f in $formats.Formats) { if ($f.Mod -eq $mod) { return $f } }
    foreach ($f in $formats.Formats) { if ($f.Mod -eq '*') { return $f } }
}
function Get-Verdict([string] $raw) {
    switch ($raw) { 'PASS' { 'PASS' } 'SKIP' { 'SKIP' } 'XFAIL' { 'SKIP' } default { 'FAIL' } }
}

$rows = [System.Collections.Generic.List[object]]::new()
$seen = @{}
$suites = [ordered]@{}
function Get-Suite([string] $name) {
    if (-not $suites.Contains($name)) {
        $suites[$name] = [ordered]@{ suite = $name; mods = [System.Collections.Generic.List[string]]::new(); returned = $false; lines = $null; rows = 0; summary = $null; status = $null; count_match = $null }
    }
    $suites[$name]
}
function Add-Row($suite, [string] $mod, [string] $check, [string] $raw, [string] $detail, [string] $source) {
    $key = "$($suite.suite)|$mod|$check"
    if ($seen.ContainsKey($key)) { return }
    $seen[$key] = $true
    $rows.Add([ordered]@{ suite = $suite.suite; mod = $mod; check = $check; verdict = (Get-Verdict $raw); raw = $raw; detail = $detail; source = $source })
    $suite.rows++
    if ($mod -and -not $suite.mods.Contains($mod)) { $suite.mods.Add($mod) }
}

$current = $null
foreach ($line in [System.IO.File]::ReadAllLines((Resolve-Path -LiteralPath $EvidenceFile).Path)) {
    if ($line -match '^STEP id=\S+ n=\d+ - label="run /(?<cmd>[^"]+)"$') { $current = Get-Suite $Matches.cmd; continue }
    if ($line -match '^NOTE id=\S+ key=lines:(?<cmd>\S+) value="(?<n>\d+)"$') { $s = Get-Suite $Matches.cmd; $s.returned = $true; $s.lines = [int]$Matches.n; continue }
    if ($line -notmatch '^OUT mod=(?<mod>\S+) via=(?<via>\S+) text="(?<text>.*)"$') { continue }
    $mod = $Matches.mod; $via = $Matches.via; $text = $Matches.text
    if ($via -ne 'echo') { continue }
    $suite = if ($current) { $current } else { Get-Suite '(no suite)' }
    $fmt = Get-Format $mod
    $m = [regex]::Match($text, $fmt.Row)
    if ($m.Success) {
        $detail = ($m.Groups['rest'].Value.Trim() -replace '^--\s*', '')
        Add-Row $suite $mod $m.Groups['check'].Value $m.Groups['verdict'].Value $detail 'echo'
        continue
    }
    $m = [regex]::Match($text, $fmt.Summary)
    if ($m.Success) {
        $suite.summary = [ordered]@{ pass = [int]$m.Groups['pass'].Value; fail = [int]$m.Groups['fail'].Value
            xfail = $(if ($m.Groups['xfail'].Success) { [int]$m.Groups['xfail'].Value } else { 0 })
            skip = $(if ($m.Groups['skip'].Success) { [int]$m.Groups['skip'].Value } else { 0 }) }
        if (-not $suite.mods.Contains($mod)) { $suite.mods.Add($mod) }
        continue
    }
    $m = [regex]::Match($text, $fmt.SkipSummary)
    if ($m.Success -and $suite.summary) { $suite.summary.skip = [int]$m.Groups['skip'].Value }
}

if ($LogFile -and (Test-Path -LiteralPath $LogFile -PathType Leaf)) {
    $log = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $LogFile).Path)
    foreach ($m in [regex]::Matches($log, $formats.Log.Done)) {
        $s = Get-Suite ("[" + $m.Groups['prefix'].Value + ":rt]")
        $s.returned = $true
        $s.summary = [ordered]@{ pass = [int]$m.Groups['pass'].Value; fail = [int]$m.Groups['fail'].Value; xfail = [int]$m.Groups['xfail'].Value; skip = [int]$m.Groups['skip'].Value }
    }
    foreach ($m in [regex]::Matches($log, $formats.Log.Row)) {
        if ($m.Groups['check'].Value -eq 'done') { continue }
        $s = Get-Suite ("[" + $m.Groups['prefix'].Value + ":rt]")
        Add-Row $s $m.Groups['prefix'].Value $m.Groups['check'].Value $m.Groups['verdict'].Value $m.Groups['detail'].Value.Trim() 'log'
    }
}

foreach ($s in $suites.Values) {
    if ($s.suite -eq '(no suite)') { $s.status = 'ran'; continue }
    if (-not $s.returned) { $s.status = 'INCONCLUSIVE'; continue }
    if ($s.rows -eq 0) {
        $s.status = 'printed nothing'
        Add-Row $s '' '(suite)' 'SKIP' 'the command returned without a check row' 'echo'
        continue
    }
    $s.status = 'ran'
    if ($s.summary) {
        $total = $s.summary.pass + $s.summary.fail + $s.summary.xfail + $s.summary.skip
        $s.count_match = ($total -gt 0) -and ([math]::Abs($s.rows - $total) -le [math]::Ceiling($total * 0.05))
    }
}

$counts = [ordered]@{
    rows = $rows.Count
    pass = @($rows | Where-Object { $_.verdict -eq 'PASS' }).Count
    fail = @($rows | Where-Object { $_.verdict -eq 'FAIL' }).Count
    skip = @($rows | Where-Object { $_.verdict -eq 'SKIP' }).Count
    inconclusive_suites = @($suites.Values | Where-Object { $_.status -eq 'INCONCLUSIVE' }).Count
}
$result = [pscustomobject]@{ Counts = $counts; Suites = @($suites.Values); Rows = $rows.ToArray() }

if ($OutDir) {
    [ordered]@{ evidence = $EvidenceFile; log = $LogFile; counts = $counts; suites = @($suites.Values); rows = $rows.ToArray() } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'sweep.json') -Encoding utf8
    $md = @('# Regression sweep', '', "Rows $($counts.rows): PASS $($counts.pass), FAIL $($counts.fail), SKIP $($counts.skip); inconclusive suites $($counts.inconclusive_suites)", '',
        '| Suite | Mods | Rows | Summary pass/fail/xfail/skip | Count matches summary | Status |', '|---|---|---|---|---|---|')
    foreach ($s in $suites.Values) {
        $sum = if ($s.summary) { "$($s.summary.pass)/$($s.summary.fail)/$($s.summary.xfail)/$($s.summary.skip)" } else { '-' }
        $md += "| $($s.suite) | $($s.mods -join ', ') | $($s.rows) | $sum | $($s.count_match) | $($s.status) |"
    }
    $fails = @($rows | Where-Object { $_.verdict -eq 'FAIL' })
    if ($fails.Count) {
        $md += ''; $md += '## FAIL rows'; $md += ''; $md += '| Mod | Check | Raw | Detail |'; $md += '|---|---|---|---|'
        foreach ($r in $fails) { $md += "| $($r.mod) | $($r.check) | $($r.raw) | $(($r.detail -replace '\|', '/')) |" }
    }
    $md | Set-Content -LiteralPath (Join-Path $OutDir 'sweep.md') -Encoding utf8
}
if (-not $Quiet) { Write-Host "[sweep] rows=$($counts.rows) pass=$($counts.pass) fail=$($counts.fail) skip=$($counts.skip) inconclusive_suites=$($counts.inconclusive_suites)" }
$result
if ($counts.fail -gt 0) { exit 1 }
exit 0
