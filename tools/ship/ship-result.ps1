# ship-result.ps1 - one JSON result and one ledger line per ship.ps1 run (WP-P-02).
#
# Dot-sourced by tools/ship/ship.ps1 and qa/check_ship_result.ps1. Every write
# is best effort: a result that cannot be written produces a warning and never
# an exception, so recording can never change a ship's outcome. Nothing is
# written inside the repository: the default directory is
# %APPDATA%\VMBLauncher\ship_runs (override: $env:VT2_SHIP_RESULT_DIR).
# ASCII only; Windows PowerShell 5.1 and PowerShell 7.

function Get-VtShipResultUtcNow {
    return [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-VtShipResultDirectory {
    if (-not [string]::IsNullOrWhiteSpace($env:VT2_SHIP_RESULT_DIR)) { return [string]$env:VT2_SHIP_RESULT_DIR }
    return (Join-Path ([string]$env:APPDATA) 'VMBLauncher\ship_runs')
}

function New-VtShipResult {
    param([string]$Mod, [string]$Mode)
    $now = [DateTime]::UtcNow
    return [ordered]@{
        schema = 1
        run_id = $now.ToString('yyyyMMddTHHmmssZ', [Globalization.CultureInfo]::InvariantCulture) + '-' + [string]$PID
        mod = $Mod
        mode = $Mode
        started_utc = $now.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        ps_version = [string]$PSVersionTable.PSVersion
        version = $null
        published_id = $null
        source_commit = $null
        stages = @()
        status = 'running'
        failed_stage = $null
        message = $null
        finished_utc = $null
    }
}

function Set-VtShipResultStage {
    param($Result, [string]$Name)
    try {
        if ($null -eq $Result -or [string]$Result.status -cne 'running') { return }
        $now = Get-VtShipResultUtcNow
        $stages = @($Result.stages)
        if ($stages.Count -gt 0 -and $null -eq $stages[-1].ended_utc) { $stages[-1].ended_utc = $now }
        $stages += [ordered]@{ name = $Name; started_utc = $now; ended_utc = $null }
        $Result.stages = $stages
    }
    catch { Write-Warning "ship result: could not record stage '$Name': $($_.Exception.Message)" }
}

function Complete-VtShipResult {
    param($Result, [string]$Status, [string]$Message)
    try {
        if ($null -eq $Result -or [string]$Result.status -cne 'running') { return }
        $now = Get-VtShipResultUtcNow
        $stages = @($Result.stages)
        if ($stages.Count -gt 0 -and $null -eq $stages[-1].ended_utc) { $stages[-1].ended_utc = $now }
        $Result.stages = $stages
        $Result.status = $Status
        $Result.message = $Message
        $Result.finished_utc = $now
        if ($Status -cne 'ok' -and $stages.Count -gt 0) { $Result.failed_stage = [string]$stages[-1].name }
    }
    catch {
        Write-Warning "ship result: could not complete the result: $($_.Exception.Message)"
        return
    }
    try {
        $directory = Get-VtShipResultDirectory
        [void][IO.Directory]::CreateDirectory($directory)
        $encoding = New-Object Text.UTF8Encoding($false)
        $path = Join-Path $directory ('{0}-{1}.json' -f $Result.run_id, $Result.mod)
        [IO.File]::WriteAllText($path, (($Result | ConvertTo-Json -Depth 6) + "`n"), $encoding)
        $line = ($Result | ConvertTo-Json -Depth 6 -Compress) + "`n"
        [IO.File]::AppendAllText((Join-Path $directory 'ledger.jsonl'), $line, $encoding)
    }
    catch { Write-Warning "ship result: could not write the result or ledger: $($_.Exception.Message)" }
}
