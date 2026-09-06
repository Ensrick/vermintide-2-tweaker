param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [Parameter(Mandatory)][string]$SemaphoreName,
    [ValidateSet('Exit', 'Throw', 'Success', 'NoPublication', 'ReadFailure', 'WriteFailure', 'WrongOwner', 'WrongRoot', 'Malformed', 'Unresolved', 'DrainFailure', 'WarningsStop', 'ObserverFailure')]
    [string]$Mode
)
$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'tools\ship\transaction-lease.ps1')
. (Join-Path $RepoRoot 'tools\ship\exception-pin-finalization.ps1')
$lease = $null
$lock = $null
$publication = $null
$attempted = $false
$path = Join-Path $FixtureRoot 'tools\verify\live_test_contract_exceptions.psd1'
$events = Join-Path $FixtureRoot 'events.txt'
function Event([string]$Name) { [IO.File]::AppendAllText($events, $Name + "`n") }
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $RepoRoot 'tools\ship\ship.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Ship fixture source did not parse.' }
$ownerTry = @($ast.EndBlock.Statements | Where-Object {
    $_ -is [Management.Automation.Language.TryStatementAst] -and
    $_.Body.Extent.Text.Contains('$transactionLease = Enter-VmbMachineTransactionLease')
})
if ($ownerTry.Count -ne 1) { throw 'Expected exactly one production transaction owner.' }
$tail = $ownerTry[0].Finally.Extent.Text
# Execute the unchanged ACTUAL production tail, never the build/network body.
$productionFinally = [scriptblock]::Create($tail.Substring(1, $tail.Length - 2))
if ($tail -match 'claim\.ps1|refresh-cards|TEST BUILD READY|\bgh\b') { throw 'Production tail acquired a forbidden readiness/claim/tracker call.' }
$realFinalize = (Get-Command Invoke-VtPublishedPinFinalization).ScriptBlock
$realDrain = (Get-Command Invoke-VtPinDescendantDrain).ScriptBlock
$realExit = (Get-Command Exit-VmbMachineTransactionLease).ScriptBlock
function Invoke-VtPinDescendantDrain {
    if ($Mode -eq 'DrainFailure') { throw 'planted-drain-failure' }
    & $realDrain
    Event 'drained'
}
function Invoke-VtPublishedPinFinalization {
    param($PublicationJson, $TransactionLease)
    try {
        $result = & $realFinalize -PublicationJson $PublicationJson -TransactionLease $TransactionLease
        if ($child -and -not $child.WaitForExit(1000)) { throw 'Residual child survived pin finalization.' }
        if (-not (Test-Path -LiteralPath $TransactionLease.RecordPath)) { throw 'Lease released before pin finalization.' }
        Event 'reconciled-child-dead-lease-held'
        if ($Mode -in @('Exit','Throw','WarningsStop','ObserverFailure')) {
            [IO.File]::WriteAllText((Join-Path $FixtureRoot 'reconciled.txt'), 'ready')
            $deadline = [DateTime]::UtcNow.AddSeconds(15)
            while (-not (Test-Path -LiteralPath (Join-Path $FixtureRoot 'release.txt'))) {
                if ([DateTime]::UtcNow -gt $deadline) { throw 'Parent did not release fixture.' }
                Start-Sleep -Milliseconds 20
            }
        }
        return $result
    }
    catch { Event ('finalization-error:' + $_.Exception.Message); throw }
}
function Exit-VmbLauncherExecutableLease { param($Lease) Event 'launcher-lease-released' }
function Exit-VmbMachineTransactionLease { param($Lease) & $realExit -Lease $Lease; Event 'lease-released' }
function Write-Warning {
    [CmdletBinding()]param([Parameter(Position=0)][string]$Message)
    if ($Mode -eq 'ObserverFailure') { throw 'planted-warning-observer-failure' }
    Microsoft.PowerShell.Utility\Write-Warning @PSBoundParameters
}
if ($Mode -eq 'WarningsStop') { $WarningPreference = 'Stop' }
try {
    $lease = Enter-VmbMachineTransactionLease -Action ship -Mod fixture -ProjectRoot $FixtureRoot `
        -RecordPath (Join-Path $FixtureRoot 'owner.json') -SemaphoreName $SemaphoreName
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'claim.txt'), 'retained')
    $publication = New-VtPublishedPinContext -RepoRoot $FixtureRoot -Mod fixture -ModId fixture `
        -SourceCommit ('c' * 40) -ModTree ('b' * 40) -Version '0.1.2-dev' -PublishedId '12345' -ReleaseTag 'mods-2026-09-06'
    if ($Mode -eq 'NoPublication') { $publication = $null; exit 1 }
    Event 'published'
    $before = [IO.File]::ReadAllText($path)
    if (-not $before.Contains(('a' * 40))) { throw 'Pins were written before the uploader clean-root boundary.' }
    Event 'uploader-saw-original-pins'
    # A contained harmless child must be dead before finalization returns;
    # production drain, not this fixture, owns its termination.
    $childReady = Join-Path $FixtureRoot 'child-locked.txt'
    $command = 'Start-Sleep -Seconds 30'
    if ($Mode -in @('Exit','Throw','Success','WarningsStop','ObserverFailure')) {
        # No-delete handle makes replacement impossible until real drain kills
        # this process; merely observing death AFTER the write is insufficient.
        $command = '$h=[IO.File]::Open(''' + $path.Replace("'","''") + ''',''Open'',''Read'',''Read'');[IO.File]::WriteAllText(''' +
            $childReady.Replace("'","''") + ''',''locked'');try {Start-Sleep -Seconds 30} finally {$h.Dispose()}'
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $child = Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru
    $null = $child.Handle
    if ($Mode -in @('Exit','Throw','Success','WarningsStop','ObserverFailure')) {
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (-not (Test-Path -LiteralPath $childReady)) {
            if ($child.HasExited -or [DateTime]::UtcNow -gt $deadline) { throw 'Residual child did not acquire pin lock.' }
            Start-Sleep -Milliseconds 20
        }
    }
    [IO.File]::WriteAllText((Join-Path $FixtureRoot 'child.txt'), [string]$child.Id)
    if ($Mode -eq 'ReadFailure') { $lock = [IO.File]::Open($path, 'Open', 'Read', 'None') }
    if ($Mode -eq 'WriteFailure') { $lock = [IO.File]::Open($path, 'Open', 'Read', 'Read') }
    if ($Mode -eq 'WrongOwner') { $lease.Mod = 'foreign' }
    if ($Mode -eq 'WrongRoot') {
        $changed = $publication | ConvertFrom-Json
        $changed.RepoRoot = Join-Path $FixtureRoot 'foreign'
        $publication = $changed | ConvertTo-Json -Compress
    }
    if ($Mode -eq 'Malformed') { $publication = '{}' }
    if ($Mode -eq 'Success') {
        $attempted = $true
        $first = Invoke-VtPublishedPinFinalization -PublicationJson $publication -TransactionLease $lease
        if (-not $first.Completed -or -not $first.Changed) { throw 'Successful path did not persist pins.' }
        $stamp = (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks
        $second = Invoke-VtPublishedPinFinalization -PublicationJson $publication -TransactionLease $lease
        if ($second.Changed -or (Get-Item -LiteralPath $path).LastWriteTimeUtc.Ticks -ne $stamp) { throw 'Second finalization was not a byte/file-time no-op.' }
        Event 'success-reconciled'
        exit 0
    }
    Event 'upload-failed'
    if ($Mode -eq 'Throw') { throw 'original-upload-failure' }
    exit 1
}
finally {
    try {
        $transactionLease = $lease
        $launcherExecutableLease = [pscustomobject]@{ FixtureOnly = $true }
        $privateLauncherSettings = $null
        $publishedPinContext = $publication
        $pinFinalizationAttempted = $attempted
        & $productionFinally
    }
    finally {
        if ($lock) { $lock.Dispose() }
        if ($child) { $child.Dispose() }
    }
}
