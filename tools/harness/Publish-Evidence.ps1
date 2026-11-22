#requires -Version 7
<#
.SYNOPSIS
  Turns a rig run's issue cases into the fixed evidence comment of docs/program/PLAN.md section 7 (WP-H-11 steps 1
  and 2): evidence\<issue>.md in the run folder, and with -Post the comment and, where the rules allow, the closure.

.DESCRIPTION
  Reads the run folder's summary.json, plan.json and evidence.txt; a plan with boots is read per boot-<i>\ folder.
  A case belongs to an issue by the issue field the driver printed ("CASE BEGIN id=<case> issue=<n>"). For every issue
  it writes <run>\evidence\<issue>.md: the comment text, then a block of facts that are not part of the comment.

  Comment text (PLAN section 7, rule R7):
      Verification: auto-verified (R) on <mod> <version> at <commit>, rig run <run id>.
      Script: <script path>                       (one line per script of the issue in this run)
      Assertions: <n> passed, 0 failed. Game build <build id>.
      Not covered by automation: <the scripts' not_covered fields, or "nothing">.
  <mod> is the script's qa/runtime/<folder>; <version> its load banner in summary.json loaded_versions; <commit> the
  commit of the staged local build with that version, else the harness checkout's commit run.ps1 recorded
  (repo_commit); <build id> summary.json game_build. A value the run did not record is written as "unknown".

  An issue would close only when all of these hold, and each one that fails is named as the reason it stays open:
  every case of the issue in this run is PASS; every script qa/runtime/index.json lists for the issue ran in this
  run; every script's class is R, S or U (never V or C); no case of the issue is in qa/runtime/quarantine.txt; the
  run's game build is the current one (-CurrentBuild, default: appmanifest_552500.acf); no value above is "unknown".

  -Post comments once per issue per run and closes the ones that may close. It refuses (exit 3) while the
  pull-request gate still demands a "user-confirmed" closure receipt (WP-G-01 not landed: card stop condition), and
  it never runs from an agent (program brief: agents do not comment on or close issues). -Post -WhatIf prints what
  it would post and close and why the others stay open, and changes nothing.

.OUTPUTS
  One row per issue: issue, close (bool), reasons (why it stays open), file (evidence\<issue>.md), comment.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Run,
    [switch] $Post,
    [switch] $WhatIf,
    [string] $RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string] $IndexFile = '',
    [string] $QuarantineFile = '',
    [string] $CurrentBuild = '',
    [string] $SteamApps = '',
    [string] $GateFile = '',                     # default qa/check_pr_autoclose.ps1 (tests pass a stand-in)
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $IndexFile) { $IndexFile = Join-Path $RepoRoot 'qa\runtime\index.json' }
if (-not $QuarantineFile) { $QuarantineFile = Join-Path $RepoRoot 'qa\runtime\quarantine.txt' }
$Run = (Resolve-Path -LiteralPath $Run).Path
$lua = Join-Path $RepoRoot 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$extractor = Join-Path $RepoRoot 'qa\runtime\_stub\index_script.lua'

# banner tags that differ from the qa/runtime folder name (summary.json loaded_versions is keyed by banner tag)
$bannerTags = @{ cosmetics_tweaker = @('cosmetics'); ct_dev = @('ct'); woc = @('WOC'); event_tweaker = @('event_tweaker', 'et') }

function Read-Json([string] $path) { if (Test-Path -LiteralPath $path) { [System.IO.File]::ReadAllText($path) | ConvertFrom-Json } else { $null } }

# ---------- the run: one or more boots ----------
$top = Read-Json (Join-Path $Run 'summary.json')
if (-not $top) { throw "no summary.json in $Run" }
$parts = @()
if ($top.PSObject.Properties['boots'] -and $top.boots) {
    foreach ($b in @($top.boots)) { $parts += Join-Path $Run ([string]$b.folder) }
}
else { $parts += $Run }

$cases = @()
foreach ($dir in $parts) {
    $s = Read-Json (Join-Path $dir 'summary.json')
    $p = Read-Json (Join-Path $dir 'plan.json')
    if (-not $s -or -not $p) { continue }
    $issueOf = @{}
    $evidence = Join-Path $dir 'evidence.txt'
    if (Test-Path -LiteralPath $evidence) {
        foreach ($l in [System.IO.File]::ReadAllLines($evidence)) { if ($l -match '^CASE BEGIN id=(\S+) issue=(\d+)') { $issueOf[$Matches[1]] = [int]$Matches[2] } }
    }
    foreach ($c in @($s.cases | Where-Object { $_ })) {
        $issue = if ($issueOf.ContainsKey([string]$c.id)) { $issueOf[[string]$c.id] } else { 0 }
        if ($issue -le 0) { continue }
        $pc = @($p.cases | Where-Object { $_.id -eq $c.id })[0]
        $file = if ($pc) { [string]$pc.file } else { '' }
        # plan case files are relative to qa/runtime/plans (or to the run folder for a re-run alone)
        $script = $file -replace '\\', '/'
        $m = [regex]::Match($script, 'qa/runtime/.+$')
        if ($m.Success) { $script = $m.Value }
        elseif ($script) { $script = ([System.IO.Path]::GetRelativePath($RepoRoot, [System.IO.Path]::GetFullPath((Join-Path (Join-Path $RepoRoot 'qa\runtime\plans') $file)))) -replace '\\', '/' }
        $folder = if ($script -match '^qa/runtime/([^/]+)/') { $Matches[1] } else { 'unknown' }
        $version = $null
        $tags = @($folder) + @($bannerTags[$folder] | Where-Object { $_ })
        foreach ($t in $tags) { if ($s.loaded_versions -and $s.loaded_versions.PSObject.Properties[$t]) { $version = [string]$s.loaded_versions.$t; break } }
        # a staged local build whose version is the one the banner showed gives the commit that was tested
        $buildCommit = $null
        foreach ($lb in @($s.local_builds | Where-Object { $_ })) { if ($version -and [string]$lb.version -eq $version -and $lb.commit) { $buildCommit = [string]$lb.commit } }
        $cases += [pscustomobject]@{
            issue = $issue; id = [string]$c.id; verdict = [string]$c.verdict; asserts = $c.asserts; failed = $c.failed; script = $script; mod = $folder
            version = $(if ($version) { $version } else { 'unknown' })
            commit = $(if ($buildCommit) { $buildCommit } elseif ($s.PSObject.Properties['repo_commit'] -and $s.repo_commit) { [string]$s.repo_commit } else { 'unknown' })
            commit_source = $(if ($buildCommit) { 'staged local build' } elseif ($s.PSObject.Properties['repo_commit'] -and $s.repo_commit) { 'harness checkout (the mod ran from its Workshop build)' } else { 'not recorded' })
            build = $(if ($s.PSObject.Properties['game_build'] -and $s.game_build) { [string]$s.game_build } else { 'unknown' })
            run = [string]$top.run
        }
    }
}

# ---------- not_covered from the scripts themselves ----------
$notCovered = @{}
$scriptsSeen = @($cases | ForEach-Object script | Where-Object { $_ } | Sort-Object -Unique)
if ($scriptsSeen.Count) {
    $list = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-evidence-' + [guid]::NewGuid().ToString('N') + '.txt')
    try {
        [System.IO.File]::WriteAllText($list, (($scriptsSeen | ForEach-Object { Join-Path $RepoRoot $_ }) -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
        foreach ($line in @(& $lua $extractor $list)) {
            $f = $line -split "`t"
            if ($f[0] -eq 'OK') { $notCovered[([System.IO.Path]::GetRelativePath($RepoRoot, $f[1]) -replace '\\', '/')] = $f[4] }
        }
    }
    finally { if (Test-Path -LiteralPath $list) { Remove-Item -LiteralPath $list -Force } }
}

$index = Read-Json $IndexFile
$quarantine = @()
if (Test-Path -LiteralPath $QuarantineFile) { $quarantine = @([System.IO.File]::ReadAllLines($QuarantineFile) | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { ($_ -split "`t")[1] }) }
if (-not $CurrentBuild) {
    try {
        $install = & (Join-Path $PSScriptRoot 'Resolve-Vt2Install.ps1') -SteamApps $SteamApps
        $acf = [System.IO.File]::ReadAllText((Join-Path $install.SteamApps 'appmanifest_552500.acf'))
        $CurrentBuild = [regex]::Match($acf, '"buildid"\s+"(\d+)"').Groups[1].Value
    } catch { $CurrentBuild = '' }
}

# ---------- one record per issue ----------
$outDir = Join-Path $Run 'evidence'
$rows = @()
foreach ($group in @($cases | Group-Object issue | Sort-Object { [int]$_.Name })) {
    $issue = [int]$group.Name
    $its = @($group.Group)
    $reasons = @()
    foreach ($c in $its) { if ($c.verdict -ne 'PASS') { $reasons += "case $($c.id) is $($c.verdict)" } }
    $listed = @()
    if ($index -and $index.issues.PSObject.Properties[[string]$issue]) { $listed = @($index.issues.([string]$issue)) }
    else { $reasons += 'qa/runtime/index.json lists no script for this issue' }
    foreach ($entry in $listed) {
        if (@($its | Where-Object { $_.script -eq $entry.script }).Count -eq 0) { $reasons += "listed script $($entry.script) did not run in this run" }
        if ($entry.class -notin 'R', 'S', 'U') { $reasons += "script $($entry.script) is class $($entry.class) (only R, S and U close)" }
    }
    foreach ($c in $its) { if ($quarantine -contains $c.id) { $reasons += "case $($c.id) is quarantined (qa/runtime/quarantine.txt)" } }
    $first = $its[0]
    foreach ($field in 'version', 'commit', 'build') { if (@($its | Where-Object { $_.$field -eq 'unknown' }).Count) { $reasons += "the run did not record the $field" } }
    if ($CurrentBuild -and $first.build -ne 'unknown' -and $first.build -ne $CurrentBuild) { $reasons += "evidence is older than the current game build (run on $($first.build), current $CurrentBuild)" }

    $mods = @($its | ForEach-Object { "$($_.mod) $($_.version)" } | Sort-Object -Unique) -join ', '
    $commits = @($its | ForEach-Object commit | Sort-Object -Unique) -join ', '
    $passed = 0; foreach ($c in $its) { $passed += [int]$c.asserts - [int]$c.failed }
    $failedTotal = 0; foreach ($c in $its) { $failedTotal += [int]$c.failed }
    $nc = @($its | ForEach-Object { $notCovered[$_.script] } | Where-Object { $_ } | Sort-Object -Unique)
    $comment = @(
        "Verification: auto-verified (R) on $mods at $commits, rig run $($first.run)."
        @($its | ForEach-Object script | Sort-Object -Unique | ForEach-Object { "Script: $_" })
        "Assertions: $passed passed, $failedTotal failed. Game build $($first.build)."
        "Not covered by automation: $(if ($nc.Count) { $nc -join ' | ' } else { 'nothing' })."
    ) -join "`n"
    $close = $reasons.Count -eq 0
    $facts = @('', '---', "Issue: #$issue", "Would close: $(if ($close) { 'yes' } else { 'no' })")
    foreach ($r in $reasons) { $facts += "Stays open: $r" }
    foreach ($c in $its) { $facts += "Case: $($c.id) $($c.verdict) ($($c.asserts) asserts, $($c.failed) failed), commit source: $($c.commit_source)" }
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $file = Join-Path $outDir "$issue.md"
    [System.IO.File]::WriteAllText($file, ($comment + "`n" + ($facts -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
    $rows += [pscustomobject]@{ issue = $issue; close = $close; reasons = $reasons; file = "evidence\$issue.md"; comment = $comment }
}

if ($Post) {
    if ($WhatIf) {
        foreach ($r in $rows) {
            Write-Host "would comment on #$($r.issue) ($($r.file))"
            if ($r.close) { Write-Host "would close #$($r.issue): every listed script passed in run $($top.run)" }
            else { foreach ($why in $r.reasons) { Write-Host "#$($r.issue) stays open: $why" } }
        }
    }
    else {
        $gate = if ($GateFile) { $GateFile } else { Join-Path $RepoRoot 'qa\check_pr_autoclose.ps1' }
        if ((Test-Path -LiteralPath $gate) -and ([System.IO.File]::ReadAllText($gate) -match 'Verification:\\s\*user-confirmed')) {
            Write-Host 'PUBLISH REFUSED: the pull-request gate still demands a "user-confirmed" closure receipt (WP-G-01 has not landed); the evidence files are written, nothing was posted.'
            exit 3
        }
        if ($env:CLAUDECODE -or $env:CODEX_SANDBOX) { Write-Host 'PUBLISH REFUSED: agents do not comment on or close issues (program brief); the owner or the lead posts.'; exit 3 }
        foreach ($r in $rows) {
            $body = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-evidence-comment-' + [guid]::NewGuid().ToString('N') + '.md')
            [System.IO.File]::WriteAllText($body, $r.comment + "`n", [System.Text.UTF8Encoding]::new($false))
            try { & gh issue comment $r.issue --body-file $body } finally { Remove-Item -LiteralPath $body -Force }
            if ($LASTEXITCODE -ne 0) { throw "gh issue comment #$($r.issue) failed" }
            if ($r.close) { & gh issue close $r.issue --reason completed; if ($LASTEXITCODE -ne 0) { throw "gh issue close #$($r.issue) failed" } }
        }
    }
}
elseif (-not $Quiet) { foreach ($r in $rows) { Write-Host "evidence #$($r.issue): $($r.file) (would close: $($r.close))" } }
$rows
