#requires -Version 7
<#
.SYNOPSIS
  Generates qa/runtime/index.json (WP-H-11 step 3): issue number -> the rig scripts that verify it, with their class,
  read from each script's own header fields.

.DESCRIPTION
  Every *.lua under qa/runtime except _stub/ and _shared/ (helpers, not cases) is a rig script. Its top level runs in
  the engine-free sandbox of qa/runtime/_stub/index_script.lua (vendored Lua 5.1), which reports its issue, class and
  not_covered fields. Scripts with issue 0 (harness self-tests, packs without an issue) are not listed.
  Tools/harness/Publish-Evidence.ps1 closes an issue only when every script listed for it here passed in one run.

  -Check compares the generated text with the committed file and exits 1 on any difference (a script with an issue
  that has no entry, a stale entry, a changed class): qa/check_runtime_scripts.ps1 runs it. Without -Check the file
  is written.

.OUTPUTS
  The index as an ordered dictionary ({ issues = { "<n>" = @(@{ script; class }) } }).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Join-Path $PSScriptRoot '..\..'),
    [string] $OutFile = '',
    [switch] $Check,
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$runtime = Join-Path $RepoRoot 'qa\runtime'
if (-not $OutFile) { $OutFile = Join-Path $runtime 'index.json' }
$lua = Join-Path $RepoRoot 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$extractor = Join-Path $runtime '_stub\index_script.lua'

$scripts = @(Get-ChildItem -LiteralPath $runtime -Recurse -File -Filter '*.lua' | Where-Object {
        $rel = [System.IO.Path]::GetRelativePath($runtime, $_.FullName) -replace '\\', '/'
        $rel -notmatch '^(_stub|_shared)/'
    } | Sort-Object FullName)
$list = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-runtime-index-' + [guid]::NewGuid().ToString('N') + '.txt')
try {
    [System.IO.File]::WriteAllText($list, (($scripts | ForEach-Object FullName) -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
    $out = & $lua $extractor $list
    if ($LASTEXITCODE -ne 0) { throw "index_script.lua exited $LASTEXITCODE" }
}
finally { if (Test-Path -LiteralPath $list) { Remove-Item -LiteralPath $list -Force } }

$problems = @()
$byIssue = @{}
foreach ($line in @($out)) {
    $f = $line -split "`t"
    $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $f[1]) -replace '\\', '/'
    if ($f[0] -ne 'OK') { $problems += "${rel}: $($f[2])"; continue }
    $issue = 0
    if (-not [int]::TryParse($f[2], [ref]$issue)) { $problems += "${rel}: issue field is not a number ($($f[2]))"; continue }
    if ($issue -le 0) { continue }
    if (-not $byIssue.ContainsKey($issue)) { $byIssue[$issue] = @() }
    $byIssue[$issue] += [ordered]@{ script = $rel; class = $f[3] }
}
if ($problems.Count) { foreach ($p in $problems) { Write-Host "index: $p" }; throw "$($problems.Count) rig script(s) could not be read for the index" }

$issues = [ordered]@{}
foreach ($n in @($byIssue.Keys | Sort-Object)) { $issues[[string]$n] = @($byIssue[$n] | Sort-Object { $_.script }) }
$index = [ordered]@{
    generated_by = 'tools/harness/New-RuntimeIndex.ps1 (from each script''s issue and class fields; do not edit by hand)'
    issues       = $issues
}
$text = ($index | ConvertTo-Json -Depth 6) -replace "`r`n", "`n"
$text += "`n"

if ($Check) {
    $current = if (Test-Path -LiteralPath $OutFile) { [System.IO.File]::ReadAllText($OutFile) -replace "`r`n", "`n" } else { '' }
    if ($current -cne $text) {
        if (-not $Quiet) { Write-Host "qa/runtime/index.json is out of date: run pwsh -NoProfile -File tools/harness/New-RuntimeIndex.ps1" }
        exit 1
    }
    if (-not $Quiet) { Write-Host "qa/runtime/index.json is current ($($issues.Count) issues)." }
    exit 0
}
[System.IO.File]::WriteAllText($OutFile, $text, [System.Text.UTF8Encoding]::new($false))
if (-not $Quiet) { Write-Host "wrote $OutFile ($($issues.Count) issues)" }
$index
