# Executes only the real completion/reporting boundary, never build or upload.
param([string]$RepoRoot, [ValidateSet('Success','LauncherFailure','TransactionFailure')][string]$Mode)
$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\ship\ship.ps1'), [Text.Encoding]::UTF8)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Completion source did not parse.' }
$owners = @($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.TryStatementAst] -and
    $_.Body.Extent.Text.Contains('$transactionLease = Enter-VmbMachineTransactionLease')
})
if ($owners.Count -ne 1) { throw 'Expected one production transaction owner.' }
$owner = $owners[0]
$claims = @($owner.Body.Statements | Where-Object { $_.Extent.Text.StartsWith('if (-not $NoClaim)') })
if ($claims.Count -ne 1) { throw 'Expected one transaction-owned claim finalization.' }
$start = $claims[0].Extent.StartOffset
# Include a premature report if it still exists inside the transaction body.
$premature = @($owner.Body.Statements | Where-Object {
    $_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -ceq '$uploadHuman'
})
if ($premature.Count) { $start = [Math]::Min($start, $premature[0].Extent.StartOffset) }
$body = $source.Substring($start, $owner.Body.Extent.EndOffset - 1 - $start)
$after = $source.Substring($owner.Extent.EndOffset)
if (($body + $after) -match '&\s*\$pubScript|Invoke-VmbLauncherProcess|Enter-VmbMachineTransactionLease') {
    throw 'Completion extraction unexpectedly includes production side effects.'
}
function Exit-VmbLauncherExecutableLease {
    param($Lease)
    Write-Host 'fixture-launcher-cleanup'
    if ($Mode -eq 'LauncherFailure') { throw 'planted-launcher-cleanup-failure' }
}
function Exit-VmbMachineTransactionLease {
    param($Lease)
    Write-Host 'fixture-transaction-cleanup'
    if ($Mode -eq 'TransactionFailure') { throw 'planted-transaction-cleanup-failure' }
}
$NoClaim = $true
$publishedPinContext = $null
$pinFinalizationAttempted = $false
$privateLauncherSettings = $null
$launcherExecutableLease = @{}
$transactionLease = @{}
$uploadStatus = 'UPLOADED'; $Mod = 'fixture'; $modVersion = '0.1.1-dev'; $publishedId = '12345'
$deploymentPolicy = @{ Mode = 'publication-only'; Reason = 'offline fixture' }
$githubStatus = 'OK'; $labelSummary = @(); $pinSummary = 'OK'; $cardSummary = 'OK'; $loadTag = 'fixture'
& ([scriptblock]::Create("try {`n" + $body + "`n} finally " + $owner.Finally.Extent.Text + "`n" + $after))
