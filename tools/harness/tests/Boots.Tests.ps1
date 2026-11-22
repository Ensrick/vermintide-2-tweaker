#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/Split-BootPlan.ps1 (WP-H-08): a plan with boots becomes one plan per boot, with the
  plan's fields, the boot's fields on top, and case file paths that still reach the same files.
  Exit codes: 0 pass, 2 failure.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
$splitter = Join-Path (Split-Path $PSScriptRoot) 'Split-BootPlan.ps1'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-boots-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $planDir = Join-Path $root 'repo\qa\runtime\plans'
    $caseDir = Join-Path $root 'repo\qa\runtime\cim'
    New-Item -ItemType Directory -Force -Path $planDir, $caseDir | Out-Null
    Set-Content -LiteralPath (Join-Path $caseDir 'issue_1_write.lua') -Value 'return { run = function(T) end }'
    Set-Content -LiteralPath (Join-Path $caseDir 'issue_1_read.lua') -Value 'return { run = function(T) end }'
    $planPath = Join-Path $planDir 'two-boot.json'
    Set-Content -LiteralPath $planPath -Value @'
{
  "name": "two-boot",
  "modset": "dev-all",
  "timeout": 300,
  "options": { "VMF": { "marker": 1 } },
  "boots": [
    { "cases": [ { "id": "write", "arena": "keep", "file": "../cim/issue_1_write.lua" } ] },
    { "modset": "no-mp", "timeout": 120, "cases": [ { "id": "read", "arena": "keep", "file": "../cim/issue_1_read.lua" } ] }
  ]
}
'@
    $runDir = Join-Path $root 'rig\runs\20261115-000000-two-boot-abcd1234'
    $boots = @(& $splitter -PlanPath $planPath -OutDir $runDir)
    Assert-True ($boots.Count -eq 2) "two boot plans (got $($boots.Count))"
    $p1 = [System.IO.File]::ReadAllText($boots[0].PlanFile) | ConvertFrom-Json
    $p2 = [System.IO.File]::ReadAllText($boots[1].PlanFile) | ConvertFrom-Json
    Assert-True ($boots[0].Dir -eq (Join-Path $runDir 'boot-1') -and (Test-Path -LiteralPath (Join-Path $runDir 'boot-2\boot.plan.json'))) 'each boot has its folder boot-<i> with boot.plan.json'
    Assert-True ($p1.name -eq 'two-boot-boot1' -and $p2.name -eq 'two-boot-boot2') 'boot plans are named <name>-boot<i>'
    Assert-True (-not $p1.PSObject.Properties['boots'] -and -not $p2.PSObject.Properties['boots']) 'boot plans carry no boots'
    Assert-True ($p1.modset -eq 'dev-all' -and $p1.timeout -eq 300 -and $p1.options.VMF.marker -eq 1) "boot 1 keeps the plan's fields"
    Assert-True ($p2.modset -eq 'no-mp' -and $p2.timeout -eq 120 -and $p2.options.VMF.marker -eq 1) "boot 2's own fields win; the rest is the plan's"
    Assert-True ($p1.cases.Count -eq 1 -and $p1.cases[0].id -eq 'write' -and $p2.cases[0].id -eq 'read') "each boot runs only its own cases"
    $reached = [System.IO.Path]::GetFullPath((Join-Path $boots[1].Dir $p2.cases[0].file))
    Assert-True ($reached -eq (Join-Path $caseDir 'issue_1_read.lua') -and -not [System.IO.Path]::IsPathRooted($p2.cases[0].file)) "case paths are relative to the boot plan and reach the same file ($($p2.cases[0].file))"
    Assert-True ($p2.boot.index -eq 2 -and $p2.boot.of -eq 2 -and $p2.boot.plan -eq $planPath) 'boot index, count and source plan recorded'

    $bad = Join-Path $planDir 'bad.json'
    Set-Content -LiteralPath $bad -Value '{ "name": "bad", "boots": [ { "cases": [] } ] }'
    $err = $null; try { & $splitter -PlanPath $bad -OutDir (Join-Path $root 'x') | Out-Null } catch { $err = $_.Exception.Message }
    Assert-True ($err -match 'boot 1 has no cases') 'a boot without cases is refused'
    Set-Content -LiteralPath $bad -Value '{ "name": "bad", "cases": [ { "id": "a", "file": "a.lua" } ], "boots": [ { "cases": [ { "id": "b", "file": "../cim/issue_1_read.lua" } ] } ] }'
    $err = $null; try { & $splitter -PlanPath $bad -OutDir (Join-Path $root 'y') | Out-Null } catch { $err = $_.Exception.Message }
    Assert-True ($err -match 'lists its cases under each boot') 'top-level cases next to boots are refused'
    Set-Content -LiteralPath $bad -Value '{ "name": "bad", "boots": [ { "cases": [ { "id": "b", "file": "../cim/missing.lua" } ] } ] }'
    $err = $null; try { & $splitter -PlanPath $bad -OutDir (Join-Path $root 'z') | Out-Null } catch { $err = $_.Exception.Message }
    Assert-True ($err -match 'case file not found') 'a missing case file is refused'

    # ---- Invoke-RigBoots.ps1 with a stand-in for run.ps1 (never the game) ----
    $fake = Join-Path $root 'fake-run.ps1'
    Set-Content -LiteralPath $fake -Value @'
param([string] $Plan, [string] $Name, [string] $RunDir, [string] $RigRoot, [switch] $KeepProfile, [string] $Renderer, [string] $Marker, [switch] $NoOrderCheck)
$p = [System.IO.File]::ReadAllText($Plan) | ConvertFrom-Json
Add-Content -LiteralPath (Join-Path $RigRoot 'calls.txt') -Value "$Name keep=$([bool]$KeepProfile) renderer=$Renderer dir=$(Split-Path $RunDir -Leaf) noorder=$([bool]$NoOrderCheck)"
$code = [int]$p.fake_exit
$verdict = switch ($code) { 0 { 'PASS' } 1 { 'FAIL' } default { 'ERROR' } }
[ordered]@{ isolation = 'OK'; run_end_seen = $true; cases = @([ordered]@{ id = $p.cases[0].id; verdict = $verdict; detail = '' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RunDir 'summary.json')
exit $code
'@
    $invoker = Join-Path (Split-Path $PSScriptRoot) 'Invoke-RigBoots.ps1'
    $pwsh = (Get-Process -Id $PID).Path
    function Invoke-Fake([string] $exits) {
        $rig = Join-Path $root ('rig-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $rig | Out-Null
        $codes = @($exits -split ',' | ForEach-Object { [int]$_ })
        $bootsJson = ($codes | ForEach-Object -Begin { $i = 0 } -Process { $i++; '{ "fake_exit": ' + $_ + ', "cases": [ { "id": "c' + $i + '", "arena": "keep", "file": "../cim/issue_1_read.lua" } ] }' }) -join ', '
        $pf = Join-Path $planDir ('fake-' + [guid]::NewGuid().ToString('N') + '.json')
        Set-Content -LiteralPath $pf -Value ('{ "name": "fake", "fake_exit": 0, "boots": [ ' + $bootsJson + ' ] }')
        $lockName = 'Local\Vt2RigBootsTest-' + [guid]::NewGuid().ToString('N')
        $null = & $pwsh -NoProfile -Command "& '$invoker' -PlanPath '$pf' -Name 'fake' -RigRoot '$rig' -ChildArgs @{ Renderer = 'dx11' } -RunScript '$fake' -LockName '$lockName'; exit `$LASTEXITCODE"
        $code = $LASTEXITCODE
        $calls = @(Get-Content -LiteralPath (Join-Path $rig 'calls.txt') -ErrorAction SilentlyContinue)
        $sum = Get-ChildItem -LiteralPath (Join-Path $rig 'runs') -Directory | Select-Object -First 1 | ForEach-Object { Get-Content -LiteralPath (Join-Path $_.FullName 'summary.json') -Raw | ConvertFrom-Json }
        [pscustomobject]@{ Exit = $code; Calls = $calls; Summary = $sum }
    }
    $ok = Invoke-Fake '0,0'
    Assert-True ($ok.Exit -eq 0 -and $ok.Calls.Count -eq 2) "two passing boots: both run, exit 0 (exit $($ok.Exit), calls $($ok.Calls.Count))"
    Assert-True ($ok.Calls[0] -eq 'fake-boot1 keep=False renderer=dx11 dir=boot-1 noorder=True' -and $ok.Calls[1] -eq 'fake-boot2 keep=True renderer=dx11 dir=boot-2 noorder=True') "boot 1 on a fresh profile, boot 2 with -KeepProfile, child arguments passed, no order check in boots ($($ok.Calls -join ' | '))"
    Assert-True ($ok.Summary.boots.Count -eq 2 -and $ok.Summary.boots[1].cases[0].id -eq 'c2' -and $ok.Summary.boots_planned -eq 2) 'the run summary lists every boot with its cases'
    $fail = Invoke-Fake '1,0'
    Assert-True ($fail.Exit -eq 1 -and $fail.Calls.Count -eq 2) 'a FAIL in boot 1 still runs boot 2; the run exits 1'
    $refused = Invoke-Fake '3,0'
    Assert-True ($refused.Exit -eq 3 -and $refused.Calls.Count -eq 1 -and $refused.Summary.boots.Count -eq 1) 'a refused boot ends the sequence; the run exits 3'
    $error2 = Invoke-Fake '0,2'
    Assert-True ($error2.Exit -eq 2) 'an ERROR in a later boot makes the run exit 2'
    # another process holding the rig lock: the boots are refused before any runs
    $held = 'Local\Vt2RigBootsTestHeld-' + [guid]::NewGuid().ToString('N')
    $holder = Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile', '-Command', "`$m = [System.Threading.Mutex]::new(`$true, '$held'); Start-Sleep -Seconds 20") -PassThru -WindowStyle Hidden
    try {
        $deadline = (Get-Date).AddSeconds(10)
        do { Start-Sleep -Milliseconds 200; $probe = [System.Threading.Mutex]::new($false, $held); $free = $probe.WaitOne(0); if ($free) { $probe.ReleaseMutex() }; $probe.Dispose() } while ($free -and (Get-Date) -lt $deadline)
        $rig = Join-Path $root 'rig-held'; New-Item -ItemType Directory -Force -Path $rig | Out-Null
        $out = & $pwsh -NoProfile -Command "& '$invoker' -PlanPath '$planPath' -Name 'held' -RigRoot '$rig' -RunScript '$fake' -LockName '$held'; exit `$LASTEXITCODE" 2>&1
        Assert-True ($LASTEXITCODE -eq 3 -and ($out -join ' ') -match 'another rig run holds the lock' -and -not (Test-Path (Join-Path $rig 'calls.txt'))) "a held rig lock refuses the boots (exit $LASTEXITCODE)"
    }
    finally { if (-not $holder.HasExited) { Stop-Process -Id $holder.Id -Force } }

    $real = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\..\qa\runtime\plans\two-boot-persist.json')) | ConvertFrom-Json
    Assert-True (@($real.boots).Count -eq 2 -and -not $real.PSObject.Properties['cases']) 'the committed two-boot-persist plan has two boots and no top-level cases'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($failures.Count) { Write-Host "[Boots.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[Boots.Tests] OK -- boot plans, inherited and per-boot fields, case paths and refusals checked.'
exit 0
