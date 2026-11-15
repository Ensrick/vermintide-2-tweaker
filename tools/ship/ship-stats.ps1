# ship-stats.ps1 - count ship.ps1 runs by status and failed stage (WP-P-02).
#
# Reads the ledger written by tools/ship/ship-result.ps1 (one JSON object per
# line) and prints the counts as JSON. Read-only. ASCII only; PS 5.1 and 7.

[CmdletBinding()]
param([string]$LedgerPath = '')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ship-result.ps1')
if ([string]::IsNullOrWhiteSpace($LedgerPath)) { $LedgerPath = Join-Path (Get-VtShipResultDirectory) 'ledger.jsonl' }

$byStatus = [ordered]@{}
$byFailedStage = [ordered]@{}
$runs = 0
$unreadable = 0
if (Test-Path -LiteralPath $LedgerPath -PathType Leaf) {
    foreach ($line in [IO.File]::ReadAllLines($LedgerPath, [Text.Encoding]::UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entry = $line | ConvertFrom-Json } catch { $unreadable++; continue }
        $runs++
        $status = [string]$entry.status
        if (-not $byStatus.Contains($status)) { $byStatus[$status] = 0 }
        $byStatus[$status]++
        if ($status -cne 'ok') {
            $stage = if ([string]::IsNullOrWhiteSpace([string]$entry.failed_stage)) { '(none)' } else { [string]$entry.failed_stage }
            if (-not $byFailedStage.Contains($stage)) { $byFailedStage[$stage] = 0 }
            $byFailedStage[$stage]++
        }
    }
}
[ordered]@{
    ledger = $LedgerPath
    runs = $runs
    unreadable_lines = $unreadable
    by_status = $byStatus
    by_failed_stage = $byFailedStage
} | ConvertTo-Json -Depth 4
