# check_runtime_scripts.ps1 - shape gate for rig test scripts and plans (WP-H-13, WP-H-14 step 4).
#
# Scripts: every qa/runtime/**/issue_*.lua and qa/runtime/_rig/*.lua must parse, run its top level with no
# engine access, and return a table with run (function), arena, issue (number, 0 for none), class "R",
# timeout (seconds) and an optional not_covered. An issue_<N>_<slug>.lua file name must carry the same N as
# its issue field, and every T.<name> a script uses must exist in qa/runtime/_stub/T.lua. The Lua half is
# qa/runtime/_stub/check_script.lua, run by the vendored Lua 5.1.
# Plans: every qa/runtime/plans/*.json must parse, and a plan that sets backend_shield to false needs a
# non-empty backend_shield_reason (only plans that test commit behaviour itself may switch the shield off).
# API (WP-H-06): every T.<name> used in qa/runtime/**/*.lua and every stub name is a row of tools/harness/API.md,
# and each row's status agrees with the driver and its helper groups (tools/harness/driver/lib/); see Test-ApiDoc.
# Index (WP-H-11 step 3): qa/runtime/index.json must equal what tools/harness/New-RuntimeIndex.ps1 generates from the
# scripts' own issue and class fields, so an issue-closing script without an entry (or a stale entry) fails here.
#
# Shape only: a script that passes here can still FAIL in the game. The stub never proves a behaviour.
# -SelfTest first proves that the fixtures under qa/_test_fixtures/runtime_scripts/ pass or fail with the
# expected message, then runs the real check. Exit codes: 0 pass, 2 errors.

[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Join-Path $repoRoot 'qa\runtime' }
$luaExe = Join-Path $PSScriptRoot 'lua\vendor\lua-5.1.5-win64\lua5.1.exe'
$stub = Join-Path $repoRoot 'qa\runtime\_stub\T.lua'
$checker = Join-Path $repoRoot 'qa\runtime\_stub\check_script.lua'
$fixtureRoot = Join-Path $PSScriptRoot '_test_fixtures\runtime_scripts'
$realApiDoc = Join-Path $repoRoot 'tools\harness\API.md'
$driverFile = Join-Path $repoRoot 'tools\harness\driver\vt2_rig_driver.lua'
$driverLibDir = Join-Path $repoRoot 'tools\harness\driver\lib'

function Get-RelativePath([string]$Path) {
    if ($Path.StartsWith($repoRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring($repoRoot.Length + 1).Replace('\', '/')
    }
    return $Path
}

function Invoke-LuaChecker([string[]]$Entries) {
    $listFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), 'vt2-runtime-scripts-' + [guid]::NewGuid().ToString('N') + '.txt')
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $process = New-Object System.Diagnostics.Process
    try {
        [System.IO.File]::WriteAllText($listFile, (($Entries -join "`n") + "`n"), $utf8)
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = $luaExe
        $start.Arguments = '"' + $checker + '" "' + $stub + '" "' + $listFile + '"'
        $start.WorkingDirectory = $repoRoot
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process.StartInfo = $start
        if (-not $process.Start()) { throw 'Lua checker did not start' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Lua checker timed out' }
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Lines    = @($stdout.GetAwaiter().GetResult() -split "`r?`n" | Where-Object { $_ -ne '' })
            Stderr   = $stderr.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
        if (Test-Path -LiteralPath $listFile) { Remove-Item -LiteralPath $listFile -Force }
    }
}

function Invoke-RuntimeScriptCheck([string]$ScanRoot) {
    $errors = New-Object System.Collections.Generic.List[string]
    $entries = New-Object System.Collections.Generic.List[string]
    $plans = 0
    if (-not (Test-Path -LiteralPath $ScanRoot -PathType Container)) {
        $errors.Add("$(Get-RelativePath $ScanRoot): folder not found")
        return [pscustomobject]@{ Errors = $errors; Scripts = 0; Plans = 0 }
    }

    foreach ($file in @(Get-ChildItem -LiteralPath $ScanRoot -Recurse -File -Filter 'issue_*.lua')) {
        $match = [regex]::Match($file.Name, '^issue_(\d+)_[a-z0-9][a-z0-9_]*\.lua$')
        if ($match.Success) {
            $entries.Add((Get-RelativePath $file.FullName) + "`t" + $match.Groups[1].Value)
        }
        else {
            $errors.Add("$(Get-RelativePath $file.FullName): file name must be issue_<N>_<slug>.lua with a lower-case slug")
            $entries.Add((Get-RelativePath $file.FullName) + "`t-")
        }
    }
    $rigDir = Join-Path $ScanRoot '_rig'
    if (Test-Path -LiteralPath $rigDir -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $rigDir -File -Filter '*.lua')) {
            if ($file.Name -notlike 'issue_*') { $entries.Add((Get-RelativePath $file.FullName) + "`t-") }
        }
    }

    if ($entries.Count -gt 0) {
        $result = Invoke-LuaChecker -Entries $entries.ToArray()
        $reported = 0
        foreach ($line in $result.Lines) {
            if ($line.StartsWith('ERROR ')) {
                $reported++
                $errors.Add($line.Substring(6))
            }
        }
        if ($result.ExitCode -ne 0 -and $reported -eq 0) {
            $errors.Add("Lua checker failed (exit $($result.ExitCode)): $($result.Stderr.Trim())")
        }
        if ($result.ExitCode -eq 0 -and $reported -gt 0) {
            $errors.Add('Lua checker reported problems but exited 0')
        }
    }

    $plansDir = Join-Path $ScanRoot 'plans'
    if (Test-Path -LiteralPath $plansDir -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $plansDir -File -Filter '*.json')) {
            $plans++
            $rel = Get-RelativePath $file.FullName
            try { $plan = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) | ConvertFrom-Json }
            catch { $errors.Add("${rel}: plan does not parse as JSON: $($_.Exception.Message)"); continue }
            # Same test as tools/harness/New-RigProfile.ps1 uses to switch the driver's shield off.
            if ($plan.PSObject.Properties['backend_shield'] -and $plan.backend_shield -eq $false) {
                $reason = $plan.PSObject.Properties['backend_shield_reason']
                if (-not $reason -or [string]::IsNullOrWhiteSpace([string]$reason.Value)) {
                    $errors.Add("${rel}: backend_shield is false without a backend_shield_reason")
                }
            }
        }
    }
    $apiDoc = Join-Path $ScanRoot 'API.md'
    if (-not (Test-Path -LiteralPath $apiDoc -PathType Leaf)) { $apiDoc = $realApiDoc }
    foreach ($e in (Test-ApiDoc -ScanRoot $ScanRoot -ApiDoc $apiDoc -CheckStub ($apiDoc -eq $realApiDoc))) { $errors.Add($e) }
    return [pscustomobject]@{ Errors = $errors; Scripts = $entries.Count; Plans = $plans }
}

# WP-H-06: tools/harness/API.md lists every helper. Every T.<name> that a Lua file under the scan root uses outside a
# comment, and every helper name of the stub, must be a row of its table. A row whose status does not start with
# "planned" must be defined by the driver or a helper group (function T.<name>, or T.<name> = ...); a planned row must
# not be, so the document cannot fall behind the code in either direction.
function Test-ApiDoc([string]$ScanRoot, [string]$ApiDoc, [bool]$CheckStub) {
    $errors = New-Object System.Collections.Generic.List[string]
    $docRel = Get-RelativePath $ApiDoc
    if (-not (Test-Path -LiteralPath $ApiDoc -PathType Leaf)) { $errors.Add("${docRel}: not found"); return $errors }
    $rows = [ordered]@{}
    $rowRx = '(?m)^\|\s*`T\.([A-Za-z_][A-Za-z0-9_]*)[^`]*`\s*\|\s*([^|]*?)\s*\|'
    foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($ApiDoc), $rowRx)) { $rows[$m.Groups[1].Value] = $m.Groups[2].Value }
    if ($rows.Count -eq 0) { $errors.Add("${docRel}: no helper rows (| ``T.<name>`` | <status> | ...)"); return $errors }

    $defined = @{}
    $sources = @($driverFile) + @(Get-ChildItem -LiteralPath $driverLibDir -File -Filter '*.lua' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($f in $sources) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { continue }
        foreach ($m in [regex]::Matches([System.IO.File]::ReadAllText($f), '(?m)\bfunction\s+T\.([A-Za-z_][A-Za-z0-9_]*)\b|^\s*T\.([A-Za-z_][A-Za-z0-9_]*)\s*=(?!=)')) {
            $defined[$m.Groups[1].Value + $m.Groups[2].Value] = $true
        }
    }

    $used = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $ScanRoot -Recurse -File -Filter '*.lua' | Where-Object { $_.FullName -notmatch '[\\/]_stub[\\/]' })) {
        $code = [regex]::Replace([System.IO.File]::ReadAllText($file.FullName), '--\[(=*)\[.*?\]\1\]', '', 'Singleline')
        $code = [regex]::Replace($code, '--[^\r\n]*', '')
        foreach ($m in [regex]::Matches($code, '(?<![A-Za-z0-9_.])T\.([A-Za-z_][A-Za-z0-9_]*)')) {
            if (-not $used.Contains($m.Groups[1].Value)) { $used[$m.Groups[1].Value] = Get-RelativePath $file.FullName }
        }
    }
    foreach ($n in $used.Keys) {
        if (-not $rows.Contains($n)) { $errors.Add("$($used[$n]): T.$n is not listed in $docRel") }
    }
    if ($CheckStub) {
        $stubText = [System.IO.File]::ReadAllText($stub)
        foreach ($block in [regex]::Matches($stubText, '(?ms)^local (?:NAMES|FIELDS) = \{(.*?)^?\}')) {
            foreach ($m in [regex]::Matches($block.Groups[1].Value, '"([A-Za-z_][A-Za-z0-9_]*)"')) {
                if (-not $rows.Contains($m.Groups[1].Value)) { $errors.Add("qa/runtime/_stub/T.lua: T.$($m.Groups[1].Value) is not listed in $docRel") }
            }
        }
    }
    foreach ($n in $rows.Keys) {
        $planned = $rows[$n] -match '^planned'
        if ($planned -and $defined[$n]) { $errors.Add("${docRel}: T.$n is marked '$($rows[$n])' but the driver or a helper group defines it") }
        if (-not $planned -and -not $defined[$n]) { $errors.Add("${docRel}: T.$n is marked '$($rows[$n])' but neither the driver nor a helper group defines it") }
    }
    return $errors
}

foreach ($required in @($luaExe, $stub, $checker)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        Write-Host "[runtime_scripts] ERROR -- missing $(Get-RelativePath $required)" -ForegroundColor Red
        exit 2
    }
}

if ($SelfTest) {
    $expectations = @(
        @{ Name = 'good'; Needle = $null },
        @{ Name = 'misspelled_helper'; Needle = 'unknown helper T.exepct' },
        @{ Name = 'issue_mismatch'; Needle = 'file name says issue 8 but the issue field is 9' },
        @{ Name = 'plan_without_reason'; Needle = 'backend_shield is false without a backend_shield_reason' },
        @{ Name = 'top_level_engine'; Needle = "top level reads global 'Managers'" },
        @{ Name = 'undocumented_helper'; Needle = 'T.note is not listed in qa/_test_fixtures/runtime_scripts/undocumented_helper/API.md' },
        @{ Name = 'api_status_wrong'; Needle = "T.step is marked 'planned: fixture' but the driver or a helper group defines it" }
    )
    $selfFailures = 0
    foreach ($e in $expectations) {
        $r = Invoke-RuntimeScriptCheck -ScanRoot (Join-Path $fixtureRoot $e.Name)
        if ($null -eq $e.Needle) {
            $ok = $r.Errors.Count -eq 0 -and $r.Scripts -gt 0 -and $r.Plans -gt 0
        }
        else {
            $ok = $r.Errors.Count -gt 0 -and @($r.Errors | Where-Object { $_.Contains($e.Needle) }).Count -gt 0
        }
        if ($ok) {
            if (-not $Quiet) { Write-Host "[runtime_scripts] SELF-TEST OK -- fixture $($e.Name)" }
        }
        else {
            $selfFailures++
            Write-Host "[runtime_scripts] SELF-TEST FAILED -- fixture $($e.Name): $($r.Errors -join ' | ')" -ForegroundColor Red
        }
    }
    if ($selfFailures -gt 0) { exit 2 }
}

$result = Invoke-RuntimeScriptCheck -ScanRoot $Root
$realRuntime = Join-Path $repoRoot 'qa\runtime'
if ([System.IO.Path]::GetFullPath($Root).TrimEnd('\') -eq [System.IO.Path]::GetFullPath($realRuntime).TrimEnd('\')) {
    $global:LASTEXITCODE = 0
    & (Join-Path $repoRoot 'tools\harness\New-RuntimeIndex.ps1') -RepoRoot $repoRoot -Check -Quiet
    if ($LASTEXITCODE -ne 0) {
        $result.Errors.Add('qa/runtime/index.json is out of date (an issue-closing script has no entry, or an entry is stale): run pwsh -NoProfile -File tools/harness/New-RuntimeIndex.ps1')
    }
}
if ($result.Errors.Count -gt 0) {
    foreach ($e in $result.Errors) { Write-Host "[runtime_scripts] ERROR -- $e" -ForegroundColor Red }
    Write-Host "[runtime_scripts] FAILED -- $($result.Errors.Count) problem(s) in $($result.Scripts) script(s) and $($result.Plans) plan(s)." -ForegroundColor Red
    exit 2
}
Write-Host "[runtime_scripts] OK -- $($result.Scripts) script(s) and $($result.Plans) plan(s) have the expected shape."
exit 0
