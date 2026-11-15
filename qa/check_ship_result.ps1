# check_ship_result.ps1 - offline fixtures for tools/ship/ship-result.ps1 (WP-P-02).
#
# Every ship.ps1 run leaves one result JSON and one ledger line. This check
# proves the helper in a temp folder: one completion writes one parseable
# file and one ledger line, a second completion writes nothing more, and an
# unwritable folder warns instead of throwing. run_selftests discovers the
# -SelfTest switch. Exit codes: 0 pass, 2 fail. ASCII only; PS 5.1 and 7.

[CmdletBinding()]
param([switch]$SelfTest, [switch]$Quiet)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\ship\ship-result.ps1')

if (-not $SelfTest) {
    if (-not $Quiet) { Write-Host '[check_ship_result] Use -SelfTest for the offline ship-result fixtures.' }
    exit 0
}

$failures = @()
$temp = Join-Path ([IO.Path]::GetTempPath()) ('vt2-ship-result-' + [guid]::NewGuid().ToString('N'))
$previousDir = $env:VT2_SHIP_RESULT_DIR
try {
    [void][IO.Directory]::CreateDirectory($temp)
    $env:VT2_SHIP_RESULT_DIR = $temp
    if ((Get-VtShipResultDirectory) -cne $temp) { $failures += 'VT2_SHIP_RESULT_DIR override ignored' }

    $result = New-VtShipResult -Mod 'fixture_mod' -Mode 'ship'
    if ($result.status -cne 'running' -or $result.schema -ne 1 -or $null -ne $result.version) { $failures += 'new result shape' }
    Set-VtShipResultStage -Result $result -Name 'resolve'
    Set-VtShipResultStage -Result $result -Name 'preflight'
    Complete-VtShipResult -Result $result -Status 'failed' -Message 'fixture failure'
    $files = @(Get-ChildItem -LiteralPath $temp -Filter '*-fixture_mod.json' -File)
    if ($files.Count -ne 1) { $failures += "expected one result file, found $($files.Count)" }
    else {
        $parsed = [IO.File]::ReadAllText($files[0].FullName) | ConvertFrom-Json
        foreach ($key in @('schema', 'mod', 'mode', 'status', 'failed_stage', 'stages')) {
            if (@($parsed.PSObject.Properties.Name) -cnotcontains $key) { $failures += "result lacks $key" }
        }
        if ($parsed.status -cne 'failed' -or $parsed.failed_stage -cne 'preflight') { $failures += "status/failed_stage: $($parsed.status)/$($parsed.failed_stage)" }
        if (@($parsed.stages).Count -ne 2 -or $null -eq $parsed.stages[0].ended_utc -or $null -eq $parsed.stages[1].ended_utc) { $failures += 'stages not closed' }
    }
    $ledger = Join-Path $temp 'ledger.jsonl'
    $lines = @(if (Test-Path -LiteralPath $ledger) { [IO.File]::ReadAllLines($ledger) | Where-Object { $_.Trim() } })
    if ($lines.Count -ne 1) { $failures += "expected one ledger line, found $($lines.Count)" }

    Complete-VtShipResult -Result $result -Status 'ok' -Message 'second completion'
    $lines = @([IO.File]::ReadAllLines($ledger) | Where-Object { $_.Trim() })
    if ($lines.Count -ne 1 -or @(Get-ChildItem -LiteralPath $temp -Filter '*.json' -File).Count -ne 1) { $failures += 'a second completion wrote again' }

    # An unwritable result directory warns and never throws.
    $blocker = Join-Path $temp 'not-a-directory'
    [IO.File]::WriteAllText($blocker, 'file, not a folder')
    $env:VT2_SHIP_RESULT_DIR = Join-Path $blocker 'child'
    $second = New-VtShipResult -Mod 'fixture_mod' -Mode 'build-only'
    $warnings = @()
    try {
        $warnings = @(Complete-VtShipResult -Result $second -Status 'crashed' -Message 'fixture' 3>&1 |
            Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
    } catch { $failures += "unwritable folder threw: $($_.Exception.Message)" }
    if ($warnings.Count -lt 1) { $failures += 'unwritable folder gave no warning' }
} catch {
    $failures += "crash: $($_.Exception.Message)"
} finally {
    $env:VT2_SHIP_RESULT_DIR = $previousDir
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

if ($failures.Count -gt 0) {
    Write-Host '[check_ship_result -SelfTest] FAILED' -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
    exit 2
}
Write-Host '[check_ship_result -SelfTest] OK -- one result and one ledger line per run, idempotent, never throws.' -ForegroundColor Green
exit 0
