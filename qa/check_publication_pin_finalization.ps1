# Offline actual-process tests. No launcher, SDK, Steam, game, or network.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'tools\ship\exception-pin-finalization.ps1')
$hostPath = (Get-Process -Id $PID).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('vt2-pin-fixtures-' + [guid]::NewGuid().ToString('N'))
$passed = 0
function Assert([bool]$Value, [string]$Message) {
    if (-not $Value) { throw "[pin-finalization] $Message" }
    $script:passed++
}
function Start-Hidden([string[]]$Arguments, [string]$LogPrefix) {
    $process = Start-Process -FilePath $hostPath -ArgumentList $Arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput ($LogPrefix + '.out') -RedirectStandardError ($LogPrefix + '.err')
    # PS5 must retain the process handle before a short-lived child exits;
    # otherwise ExitCode can be null after WaitForExit despite actual exit 1.
    $null = $process.Handle
    return $process
}
try {
    foreach ($mode in @('Exit','Throw','Success','NoPublication','ReadFailure','WriteFailure','WrongOwner','WrongRoot','Malformed','Unresolved','DrainFailure','WarningsStop','ObserverFailure','HandoffExistingReceiptFailure','HandoffNewReceiptFailure','HandoffExistingReportFailure','HandoffExistingCleanupFailure','HandoffExistingWarningStop')) {
        $isHandoff = $mode.StartsWith('Handoff', [StringComparison]::Ordinal)
        $holdsForContender = $isHandoff -or $mode -in @('Exit','Throw','WarningsStop','ObserverFailure')
        $folder = Join-Path $root $mode
        $parent = Join-Path $folder 'tools\verify'
        [IO.Directory]::CreateDirectory($parent) | Out-Null
        $path = Join-Path $parent 'live_test_contract_exceptions.psd1'
        $stale = 'a' * 40
        $new = 'b' * 40
        $original = "@{`n    ReceiptFamilyOverrides = @(`n        @{Marker='[fixture]';ModTrees=@{fixture='$stale';sibling='$stale'}}`n    )`n    ReceiptRouteOverrides = @()`n    ReceiptDiscoveryOverrides = @()`n}"
        if ($mode -eq 'Unresolved') {
            $original = $original.Replace("fixture='$stale'", "fixture = `n'$stale'")
        }
        [IO.File]::WriteAllText($path, $original, (New-Object Text.UTF8Encoding($false)))
        $semaphore = 'Local\VT2.PinFixture.' + [guid]::NewGuid().ToString('N')
        $worker = Start-Hidden -Arguments @('-NoProfile','-NonInteractive','-File',
            (Join-Path $PSScriptRoot '_test_fixtures\publication_pin_worker.ps1'),
            '-RepoRoot',$repo,'-FixtureRoot',$folder,'-SemaphoreName',$semaphore,'-Mode',$mode) -LogPrefix (Join-Path $folder 'worker')
        try {
            if ($holdsForContender) {
                $marker = Join-Path $folder 'reconciled.txt'
                $deadline = [DateTime]::UtcNow.AddSeconds(20)
                while (-not (Test-Path -LiteralPath $marker)) {
                    if ($worker.HasExited -or [DateTime]::UtcNow -gt $deadline) {
                        throw "Worker $mode did not reconcile: $([IO.File]::ReadAllText((Join-Path $folder 'worker.err')))"
                    }
                    Start-Sleep -Milliseconds 20
                }
                $contenderArguments = @('-NoProfile','-NonInteractive','-File',
                    (Join-Path $PSScriptRoot '_test_fixtures\machine_transaction_worker.ps1'),
                    '-HelperPath',(Join-Path $repo 'tools\ship\transaction-lease.ps1'),
                    '-SemaphoreName',$semaphore,'-RecordPath',(Join-Path $folder 'owner.json'),
                    '-Action','ship','-Mod','fixture','-ProjectRoot',$folder,
                    '-TimeoutMilliseconds','200','-MarkerPath',(Join-Path $folder 'contender.marker'))
                $contender = Start-Hidden -Arguments $contenderArguments -LogPrefix (Join-Path $folder 'contender')
                try {
                    Assert ($contender.WaitForExit(15000)) 'Contender exceeded bounded wait.'
                    Assert ($contender.ExitCode -ne 0 -and -not (Test-Path (Join-Path $folder 'contender.marker'))) 'Contender acquired before finalization lease release.'
                    Assert ([IO.File]::ReadAllText((Join-Path $folder 'contender.err')).Contains('machine mutex')) 'Contender failed for a reason other than bounded mutex contention.'
                }
                finally { $contender.Dispose() }
                [IO.File]::WriteAllText((Join-Path $folder 'release.txt'), 'release')
            }
            Assert ($worker.WaitForExit(20000)) "Worker $mode exceeded bounded wait."
            $expectedCode = if ($mode -eq 'Success') { 0 } else { 1 }
            Assert ($worker.ExitCode -eq $expectedCode) "Worker $mode lost original exit ($($worker.ExitCode))."
            if ($holdsForContender) {
                $retry = Start-Hidden -Arguments $contenderArguments -LogPrefix (Join-Path $folder 'contender-retry')
                try {
                    Assert ($retry.WaitForExit(15000)) 'Post-release contender exceeded bounded wait.'
                    Assert ($retry.ExitCode -eq 0 -and (Test-Path (Join-Path $folder 'contender.marker'))) 'Same contender could not acquire after release.'
                }
                finally { $retry.Dispose() }
            }
            $actual = [IO.File]::ReadAllText($path)
            $events = [IO.File]::ReadAllText((Join-Path $folder 'events.txt'))
            if ($holdsForContender -or $mode -eq 'Success') {
                Assert ($actual.Contains("fixture='$new'") -and $actual.Contains("sibling='$stale'")) "Worker $mode did not persist only intended pins."
                Assert ($events.IndexOf('uploader-saw-original-pins') -lt $events.IndexOf('reconciled')) 'Pins changed before uploader clean-root boundary.'
                Assert ($events.IndexOf('reconciled') -lt $events.IndexOf('lease-released')) 'Pin write ran after lease release.'
            }
            else {
                Assert ($actual -ceq $original) "Worker $mode changed pins without a completed finalization."
                if ($mode -ne 'NoPublication') { Assert ($events.Contains('finalization-error:')) "Worker $mode did not report secondary failure." }
            }
            Assert (Test-Path (Join-Path $folder 'claim.txt')) 'Failure finalization removed version claim.'
            Assert ($events.Contains('launcher-lease-released')) 'Actual production tail skipped launcher cleanup.'
            Assert (-not (Test-Path (Join-Path $folder 'owner.json'))) 'Worker left transaction ownership behind.'
            Assert (@(Get-ChildItem -LiteralPath $parent -Filter '*.pending').Count -eq 0) 'Worker left temporary pin output behind.'
            $stdout = [IO.File]::ReadAllText((Join-Path $folder 'worker.out'))
            $stderr = [IO.File]::ReadAllText((Join-Path $folder 'worker.err'))
            Assert (-not ($stdout + $stderr).Contains('TEST BUILD READY')) 'Actual production output announced test readiness.'
            if ($mode -eq 'Throw') { Assert ($stderr.Contains('original-upload-failure')) 'Cleanup replaced the original upload exception.' }
            if ($isHandoff) {
                $publisherError = [IO.File]::ReadAllText((Join-Path $folder 'publisher-error.txt'))
                $escapingError = [IO.File]::ReadAllText((Join-Path $folder 'escaping-error.txt'))
                Assert ($escapingError -ceq $publisherError) "Worker $mode replaced the publisher exception. Expected: $publisherError; escaping: $escapingError"
                Assert ($stderr.Contains('publish-release.ps1')) "Worker $mode did not rethrow the escaping publisher error."
                Assert ($events.Contains('published-before-handoff-failure')) 'Real publisher tail never supplied confirmed provenance.'
            }
        }
        finally {
            if (-not $worker.HasExited) { $worker.Kill(); $worker.WaitForExit(5000) | Out-Null }
            $worker.Dispose()
        }
    }
    foreach ($id in @('0','-1','1x')) {
        $rejected = $false
        try {
            New-VtPublishedPinContext -RepoRoot $root -Mod fixture -ModId fixture -SourceCommit ('c' * 40) -ModTree ('b' * 40) -Version '0.1.2-dev' -PublishedId $id -ReleaseTag 'mods-2026-09-06' | Out-Null
        }
        catch { $rejected = $true }
        Assert $rejected "Invalid/bootstrap identity $id was accepted."
    }
    # Remove only disposable paths below this verified unique fixture root.
    # No recursive delete; repository/output/Steam paths are never targets.
    $resolved = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    $children = @(Get-ChildItem -LiteralPath $root -Recurse -Force)
    foreach ($entry in $children) {
        if (-not $entry.FullName.StartsWith($resolved, [StringComparison]::OrdinalIgnoreCase) -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Fixture cleanup path is unsafe.' }
    }
    foreach ($entry in @($children | Where-Object { -not $_.PSIsContainer })) { Remove-Item -LiteralPath $entry.FullName -Force }
    foreach ($entry in @($children | Where-Object PSIsContainer | Sort-Object { $_.FullName.Length } -Descending)) { Remove-Item -LiteralPath $entry.FullName }
    Remove-Item -LiteralPath $root
    Write-Host "[pin-finalization] PASS $passed checks ($($PSVersionTable.PSVersion)); disposable fixtures removed."
    exit 0
}
catch {
    Write-Host "[pin-finalization] FAIL: $_; artifacts: $root"
    exit 2
}
