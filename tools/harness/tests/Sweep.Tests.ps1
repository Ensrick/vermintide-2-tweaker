#requires -Version 7
<#
.SYNOPSIS
  Offline test of tools/harness/Parse-Sweep.ps1 over a recorded evidence fixture with known counts (WP-H-03),
  plus the WP-T-01 log line format. Exit codes: 0 pass, 2 failure.
#>
[CmdletBinding()]
param([switch] $Quiet)
$ErrorActionPreference = 'Stop'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool] $condition, [string] $label) {
    if ($condition) { if (-not $Quiet) { Write-Host "  [PASS] $label" } }
    else { $failures.Add($label); Write-Host "  [FAIL] $label" -ForegroundColor Red }
}
$parser = Join-Path (Split-Path $PSScriptRoot) 'Parse-Sweep.ps1'
$fixtures = Join-Path $PSScriptRoot 'fixtures'
$evidence = Join-Path $fixtures 'sweep-evidence.txt'
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('vt2-rig-sweep-tests-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $r = & $parser -EvidenceFile $evidence -OutDir $root -Quiet
    $c = $r.Counts
    Assert-True ($c.rows -eq 10 -and $c.pass -eq 3 -and $c.fail -eq 3 -and $c.skip -eq 4) "known counts: rows 10, PASS 3, FAIL 3, SKIP 4 (got $($c.rows)/$($c.pass)/$($c.fail)/$($c.skip))"
    Assert-True ($c.inconclusive_suites -eq 1) 'the suite that never returned is INCONCLUSIVE'
    $byCheck = @{}; foreach ($row in $r.Rows) { $byCheck["$($row.mod)/$($row.check)"] = $row }
    Assert-True ($byCheck['gt_dev/gt_b'].verdict -eq 'FAIL' -and $byCheck['gt_dev/gt_b'].detail -eq 'expected 1, got 2') 'FAIL row with its detail'
    Assert-True ($byCheck['gt_dev/gt_c'].verdict -eq 'FAIL' -and $byCheck['gt_dev/gt_c'].raw -eq 'BAD-SHAPE') 'BAD-SHAPE counts as FAIL'
    Assert-True ($byCheck['character_weapon_variants/cwv_d'].verdict -eq 'FAIL' -and $byCheck['character_weapon_variants/cwv_d'].raw -eq 'XPASS') 'XPASS counts as FAIL'
    Assert-True ($byCheck['character_weapon_variants/cwv_c'].verdict -eq 'SKIP' -and $byCheck['character_weapon_variants/cwv_c'].raw -eq 'XFAIL') 'XFAIL counts as SKIP'
    Assert-True ($byCheck['cosmetics_tweaker/cos_b'].verdict -eq 'SKIP') 'cosmetics SKIP row'
    Assert-True ($byCheck['/(suite)'].suite -eq 'mp_regression_test' -and $byCheck['/(suite)'].verdict -eq 'SKIP') 'a suite that printed nothing is one SKIP row, never PASS'
    Assert-True (-not $byCheck.ContainsKey('gt_dev/[regression]')) 'info and warning echoes are not rows'
    $suites = @{}; foreach ($s in $r.Suites) { $suites[$s.suite] = $s }
    Assert-True ($suites['gt_regression_test'].count_match -eq $true) 'gt rows match its summary (1 passed, 2 failed)'
    Assert-True ($suites['cwv_regression_test'].count_match -eq $true) 'cwv rows match its summary with xfail and skipped'
    Assert-True ($suites['cosmetics_tweaker_regression_test'].count_match -eq $true -and $suites['cosmetics_tweaker_regression_test'].summary.skip -eq 1) 'cosmetics skip total read from its own line'
    Assert-True ($suites['woc_regression_test'].status -eq 'INCONCLUSIVE') 'woc suite status INCONCLUSIVE'
    $json = [System.IO.File]::ReadAllText((Join-Path $root 'sweep.json')) | ConvertFrom-Json
    Assert-True ($json.counts.rows -eq 10 -and @($json.rows).Count -eq 10) 'sweep.json written with every row'
    Assert-True ((Get-Content -LiteralPath (Join-Path $root 'sweep.md') -Raw) -match '\| gt_dev \| gt_b \| FAIL \| expected 1, got 2 \|') 'sweep.md lists the FAIL rows'

    $pwsh = (Get-Process -Id $PID).Path
    $null = & $pwsh -NoProfile -File $parser -EvidenceFile $evidence -Quiet 2>&1
    Assert-True ($LASTEXITCODE -eq 1) "exit 1 when a check FAILs (got $LASTEXITCODE)"
    $clean = Join-Path $root 'clean.txt'
    Set-Content -LiteralPath $clean -Value @('STEP id=s n=1 - label="run /vdl_regression_test"', 'OUT mod=vdl via=echo text="  PASS: vdl_a"', 'OUT mod=vdl via=echo text="=== 1 passed, 0 failed ==="', 'NOTE id=s key=lines:vdl_regression_test value="2"')
    $null = & $pwsh -NoProfile -File $parser -EvidenceFile $clean -Quiet 2>&1
    Assert-True ($LASTEXITCODE -eq 0) "exit 0 without a FAIL (got $LASTEXITCODE)"
    $null = & $pwsh -NoProfile -File $parser -EvidenceFile (Join-Path $root 'missing.txt') -Quiet 2>&1
    Assert-True ($LASTEXITCODE -eq 2) 'exit 2 when the evidence file is missing'

    $withLog = & $parser -EvidenceFile $clean -LogFile (Join-Path $fixtures 'sweep-rt.console.log') -Quiet
    $logRows = @($withLog.Rows | Where-Object { $_.source -eq 'log' })
    Assert-True ($logRows.Count -eq 3) "WP-T-01 log rows read (got $($logRows.Count))"
    Assert-True (@($logRows | Where-Object { $_.check -eq 'gt_y' -and $_.verdict -eq 'FAIL' -and $_.detail -eq 'value was 3' }).Count -eq 1) 'log FAIL row with detail'
    $logSuite = @($withLog.Suites | Where-Object { $_.suite -eq '[gt:rt]' })[0]
    Assert-True ($logSuite.count_match -eq $true) 'log rows match the done line'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if ($failures.Count) { Write-Host "[Sweep.Tests] FAILED -- $($failures.Count) assertion(s)." -ForegroundColor Red; exit 2 }
Write-Host '[Sweep.Tests] OK -- rows, verdict mapping, suite status, summary match, outputs, exit codes and log rows checked.'
exit 0
