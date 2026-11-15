# check_release_driver.ps1 - offline fixtures for tools/ship/release-driver.ps1 (WP-P-09).
#
# gh, git and sleep are replaced by in-process stubs: no network, no launcher,
# no claim, no ship. Covers the land step's exit codes, the pull-request body
# rule, the journal and session-id rules, skipped completed steps, the claim
# stale/other-owner stop, the version step, the clean-version stop (exit 20),
# the three-try head retry (exit 24) and a dry run that changes nothing.
# run_selftests discovers the -SelfTest switch. Exit codes: 0 pass, 2 fail.
# ASCII only; Windows PowerShell 5.1 and PowerShell 7.

[CmdletBinding()]
param([switch]$SelfTest, [switch]$Quiet)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\ship\release-driver.ps1')

if (-not $SelfTest) {
    if (-not $Quiet) { Write-Host '[check_release_driver] Use -SelfTest for the offline release-driver fixtures.' }
    exit 0
}

# --- stubs (defined after the dot-source, so they replace the real wrappers) ---
$script:fake = $null
function Reset-Fake {
    param($View, $Checks, $Runs)
    $script:fake = @{
        View = New-Object 'System.Collections.Generic.List[object]'
        Checks = New-Object 'System.Collections.Generic.List[object]'
        Runs = New-Object 'System.Collections.Generic.List[object]'
        Calls = New-Object 'System.Collections.Generic.List[string]'
    }
    foreach ($item in @($View)) { $script:fake.View.Add($item) }
    foreach ($item in @($Checks)) { $script:fake.Checks.Add($item) }
    foreach ($item in @($Runs)) { $script:fake.Runs.Add($item) }
}
function Get-FakeNext([string]$Key) {
    $queue = $script:fake[$Key]
    if ($queue.Count -eq 0) { return $null }
    $item = $queue[0]
    if ($queue.Count -gt 1) { $queue.RemoveAt(0) }
    return $item
}
function Invoke-ReleaseGh {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $verb = ($Arguments[0] + ' ' + $Arguments[1])
    $script:fake.Calls.Add($verb)
    switch ($verb) {
        'pr view' { return [pscustomobject]@{ ExitCode = 0; Output = ((Get-FakeNext 'View') | ConvertTo-Json -Depth 4 -Compress) } }
        'pr checks' { return [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject @(Get-FakeNext 'Checks') -Depth 4 -Compress) } }
        'run list' { return [pscustomobject]@{ ExitCode = 0; Output = (ConvertTo-Json -InputObject @(Get-FakeNext 'Runs') -Depth 4 -Compress) } }
        default { return [pscustomobject]@{ ExitCode = 0; Output = '' } }
    }
}
function Invoke-ReleaseGit { param([string[]]$Arguments, [string]$RepoRoot = '') return [pscustomobject]@{ ExitCode = 0; Output = '' } }
function Invoke-ReleaseSleep { param([int]$Seconds) }
function Write-ReleaseLog { param([string]$Message) }

$merge = 'a' * 40
function State([string]$State, [string]$Merge, [string]$Head = ('1' * 40), [string]$Commit = '') {
    $mc = if ($Commit) { [pscustomobject]@{ oid = $Commit } } else { $null }
    return [pscustomobject]@{ state = $State; mergeStateStatus = $Merge; headRefOid = $Head; mergeCommit = $mc }
}
$green = @([pscustomobject]@{ name = 'qa-gate'; bucket = 'pass' }, [pscustomobject]@{ name = 'pr-autoclose-authorization'; bucket = 'pass' })
$pending = @([pscustomobject]@{ name = 'qa-gate'; bucket = 'pending' })
$red = @([pscustomobject]@{ name = 'qa-gate'; bucket = 'fail' })
$masterOk = @([pscustomobject]@{ headSha = $merge; status = 'completed'; conclusion = 'success'; databaseId = 1; event = 'push' })
$masterRed = @([pscustomobject]@{ headSha = $merge; status = 'completed'; conclusion = 'failure'; databaseId = 2; event = 'push' })
$masterRunning = @([pscustomobject]@{ headSha = $merge; status = 'in_progress'; conclusion = ''; databaseId = 3; event = 'push' })
$nightlyOnly = @([pscustomobject]@{ headSha = $merge; status = 'completed'; conclusion = 'failure'; databaseId = 4; event = 'schedule' })

$failures = @()
function Expect([string]$Name, [int]$Expected, [scriptblock]$Setup, [scriptblock]$Extra = $null) {
    & $Setup
    $code = Invoke-ReleaseLand -Pr 7 -PollSeconds 1 -TimeoutMinutes 1
    $ok = ($code -eq $Expected)
    if ($ok -and $null -ne $Extra) { $ok = [bool](& $Extra) }
    if (-not $ok) { $script:failures += "land '$Name': expected exit $Expected, got $code (calls: $($script:fake.Calls -join ', '))" }
    else { Write-Host "  [PASS] land $Name -> exit $code" -ForegroundColor Green }
}

Expect 'clean merge' 0 { Reset-Fake -View @((State 'OPEN' 'CLEAN'), (State 'MERGED' 'UNKNOWN' -Commit $merge)) -Checks @(,$green) -Runs @(,$masterOk) } { $script:fake.Calls -contains 'pr merge' }
Expect 'unknown, then clean' 0 { Reset-Fake -View @((State 'OPEN' 'UNKNOWN'), (State 'OPEN' 'CLEAN'), (State 'MERGED' 'UNKNOWN' -Commit $merge)) -Checks @(,$green) -Runs @(,$masterOk) }
Expect 'dirty' 11 { Reset-Fake -View @(,(State 'OPEN' 'DIRTY')) }
Expect 'behind, updated, then clean' 0 {
    Reset-Fake -View @((State 'OPEN' 'BEHIND' -Head ('1' * 40)), (State 'OPEN' 'BLOCKED' -Head ('1' * 40)), (State 'OPEN' 'BLOCKED' -Head ('2' * 40)), (State 'OPEN' 'CLEAN' -Head ('2' * 40)), (State 'MERGED' 'UNKNOWN' -Commit $merge)) -Checks @(,$green) -Runs @(,$masterOk)
} { @($script:fake.Calls | Where-Object { $_ -ceq 'pr update-branch' }).Count -eq 1 }
Expect 'pending, then green' 0 { Reset-Fake -View @((State 'OPEN' 'BLOCKED'), (State 'OPEN' 'BLOCKED'), (State 'MERGED' 'UNKNOWN' -Commit $merge)) -Checks @($pending, $green) -Runs @(,$masterOk) }
Expect 'failed check' 12 { Reset-Fake -View @(,(State 'OPEN' 'BLOCKED')) -Checks @(,$red) } { $script:fake.Calls -notcontains 'pr merge' }
Expect 'merge refused' 10 { Reset-Fake -View @((State 'OPEN' 'CLEAN'), (State 'OPEN' 'CLEAN')) -Checks @(,$green) }
Expect 'master QA failed' 13 { Reset-Fake -View @((State 'OPEN' 'CLEAN'), (State 'MERGED' 'UNKNOWN' -Commit $merge)) -Checks @(,$green) -Runs @(,$masterRed) }
Expect 'master QA running, then green' 0 { Reset-Fake -View @((State 'OPEN' 'CLEAN'), (State 'MERGED' 'UNKNOWN' -Commit $merge)) -Checks @(,$green) -Runs @($masterRunning, $masterOk) }
Expect 'only a nightly run at the merge commit' 14 { Reset-Fake -View @((State 'OPEN' 'CLEAN'), (State 'MERGED' 'UNKNOWN' -Commit $merge)) -Checks @(,$green) -Runs @(,$nightlyOnly) }
Expect 'already merged' 0 { Reset-Fake -View @(,(State 'MERGED' 'UNKNOWN' -Commit $merge)) -Runs @(,$masterOk) } { $script:fake.Calls -notcontains 'pr merge' }

# Pull-request body rule.
foreach ($case in @(
    @{ Body = 'Refs #12'; Ok = $true }, @{ Body = 'Fixes #12'; Ok = $false }, @{ Body = 'closes: #3'; Ok = $false },
    @{ Body = 'This resolved #4 earlier'; Ok = $false }, @{ Body = 'prefixfixes #12 and fix-up'; Ok = $true }, @{ Body = ''; Ok = $true }
)) {
    if ((Test-ReleasePrBody -Body $case.Body) -ne $case.Ok) { $failures += "body rule: '$($case.Body)' should be $(if ($case.Ok) { 'accepted' } else { 'rejected' })" }
}
if (-not ($failures | Where-Object { $_ -like 'body rule*' })) { Write-Host '  [PASS] pull-request body rule rejects closing keywords' -ForegroundColor Green }

# Journal round trip and the session-id rule, in a temp result directory.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('vt2-release-driver-' + [guid]::NewGuid().ToString('N'))
$previousDir = $env:VT2_SHIP_RESULT_DIR
$previousSession = $env:VT2_SHIP_SESSION_ID
try {
    [void][IO.Directory]::CreateDirectory($temp)
    $env:VT2_SHIP_RESULT_DIR = $temp
    $journal = New-ReleaseJournal -Mod 'fixture_mod'
    $journal.version = '0.1.2-dev'
    Add-ReleaseJournalStep -Journal $journal -Name 'claim' -Result 'done'
    Save-ReleaseJournal -Journal $journal
    $read = Read-ReleaseJournal -Mod 'fixture_mod'
    if ($null -eq $read -or [string]$read.session_id -cne [string]$journal.session_id -or [string]$read.version -cne '0.1.2-dev' -or @($read.steps).Count -ne 1) {
        $failures += 'journal round trip lost data'
    } elseif (-not (Test-Path -LiteralPath (Join-Path $temp 'release-fixture_mod.json'))) {
        $failures += 'journal path is not release-<mod>.json under the result directory'
    } else { Write-Host '  [PASS] journal round trip' -ForegroundColor Green }
    $env:VT2_SHIP_SESSION_ID = 'some-other-session'
    Set-ReleaseSession -Journal $read
    if ($env:VT2_SHIP_SESSION_ID -cne [string]$journal.session_id) { $failures += 'journal session id did not win over the environment' }
    else { Write-Host '  [PASS] journal session id wins over an existing environment value' -ForegroundColor Green }
} catch {
    $failures += "journal fixture crashed: $($_.Exception.Message)"
} finally {
    $env:VT2_SHIP_RESULT_DIR = $previousDir
    $env:VT2_SHIP_SESSION_ID = $previousSession
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

# --- parts (b) and (c): the step machine, with a fixture repository ---------
$script:tool = @{ Calls = New-Object 'System.Collections.Generic.List[string]'; Verify = 0; ShipMessage = ''; ShipOk = $false }
$script:gitCalls = New-Object 'System.Collections.Generic.List[string]'
function Invoke-ReleaseTool {
    param([string]$RepoRoot, [string]$Script, [string[]]$Arguments = @())
    $name = Split-Path $Script -Leaf
    $script:tool.Calls.Add(($name + ' ' + ($Arguments -join ' ')).Trim())
    switch ($name) {
        'claim.ps1' {
            if ($Arguments -contains '-Verify') { return [pscustomobject]@{ ExitCode = $script:tool.Verify; Output = '' } }
            return [pscustomobject]@{ ExitCode = 0; Output = "  Allocated version: 0.1.3-dev" }
        }
        'ship.ps1' {
            $record = [ordered]@{ schema = 1; mod = 'fixture_mod'; version = $script:tool.Version; mode = 'ship'
                status = $(if ($script:tool.ShipOk) { 'ok' } else { 'failed' }); message = $script:tool.ShipMessage }
            [IO.File]::AppendAllText((Join-Path (Get-VtShipResultDirectory) 'ledger.jsonl'), (($record | ConvertTo-Json -Compress) + "`n"))
            return [pscustomobject]@{ ExitCode = $(if ($script:tool.ShipOk) { 0 } else { 1 }); Output = '' }
        }
        default { return [pscustomobject]@{ ExitCode = 0; Output = '' } }
    }
}
function Invoke-ReleaseGit {
    param([string[]]$Arguments, [string]$RepoRoot = '')
    $script:gitCalls.Add(($Arguments -join ' '))
    return [pscustomobject]@{ ExitCode = 0; Output = '' }
}
function Reset-Machine([string]$Version, [int]$Verify = 0, [bool]$ShipOk = $false, [string]$ShipMessage = '') {
    $script:tool.Calls.Clear(); $script:gitCalls.Clear()
    $script:tool.Verify = $Verify; $script:tool.ShipOk = $ShipOk; $script:tool.ShipMessage = $ShipMessage; $script:tool.Version = $Version
    $ledger = Join-Path (Get-VtShipResultDirectory) 'ledger.jsonl'
    if (Test-Path -LiteralPath $ledger) { Remove-Item -LiteralPath $ledger -Force }
    $journal = New-ReleaseJournal -Mod 'fixture_mod'
    $journal.version = $Version; $journal.branch = 'wp/fixture'
    return $journal
}
$machineRoot = Join-Path ([IO.Path]::GetTempPath()) ('vt2-release-machine-' + [guid]::NewGuid().ToString('N'))
$previousDir = $env:VT2_SHIP_RESULT_DIR
$options = [pscustomobject]@{ ChangelogFile = ''; CommitMessageFile = ''; PrTitle = ''; PrBodyFile = ''; AllowPublic = $false; NoRemote = $false; ConfirmVersion = ''; DryRun = $false; PollSeconds = 1; TimeoutMinutes = 1 }
try {
    $modDir = Join-Path $machineRoot 'fixture_mod'
    [void][IO.Directory]::CreateDirectory((Join-Path $modDir 'scripts\mods\fixture_mod'))
    [void][IO.Directory]::CreateDirectory((Join-Path $machineRoot 'runs'))
    $env:VT2_SHIP_RESULT_DIR = Join-Path $machineRoot 'runs'
    $lua = Join-Path $modDir 'scripts\mods\fixture_mod\fixture_mod.lua'
    [IO.File]::WriteAllText($lua, "local mod = get_mod(""fixture_mod"")`nlocal MOD_VERSION = ""0.1.2-dev""`n")
    [IO.File]::WriteAllText((Join-Path $modDir 'itemV2.cfg'), "title = ""Fixture v0.1.2-dev"";`ndescription = ""[b]Fixture v0.1.2-dev[/b]"";`n")
    [IO.File]::WriteAllText((Join-Path $modDir 'CHANGELOG.md'), "# Fixture Changelog`n`n## 0.1.2-dev (2026-11-14) -- old`n`n- old entry`n")
    $entry = Join-Path $machineRoot 'entry.md'
    [IO.File]::WriteAllText($entry, "## {VERSION} (2026-11-15) -- fixture`n`n- fixture entry`n")

    # A completed claim is skipped: only the read-only verify runs.
    $j = Reset-Machine '0.1.3-dev' 0
    $code = Invoke-ReleaseSteps -Steps @('claim') -Journal $j -RepoRoot $machineRoot -Options $options
    if ($code -ne 0 -or @($script:tool.Calls | Where-Object { $_ -like 'claim.ps1*' -and $_ -notlike '*-Verify*' }).Count -ne 0) { $failures += "completed claim was not skipped (exit $code; $($script:tool.Calls -join '; '))" }
    else { Write-Host '  [PASS] a completed claim is skipped (verify only)' -ForegroundColor Green }
    foreach ($case in @(@{ Verify = 5; Exit = 21; Name = 'stale' }, @{ Verify = 6; Exit = 22; Name = 'other owner' })) {
        $j = Reset-Machine '0.1.3-dev' $case.Verify
        $code = Invoke-ReleaseSteps -Steps @('claim') -Journal $j -RepoRoot $machineRoot -Options $options
        if ($code -ne $case.Exit -or @($script:tool.Calls | Where-Object { $_ -notlike '*-Verify*' }).Count -ne 0) { $failures += "claim $($case.Name): expected exit $($case.Exit) and no re-claim, got $code" }
        else { Write-Host "  [PASS] claim $($case.Name) stops with exit $code and never re-claims" -ForegroundColor Green }
    }

    # Version step writes MOD_VERSION, the cfg banners and the CHANGELOG entry once.
    $j = Reset-Machine '0.1.3-dev' 0
    $vOptions = $options.PSObject.Copy(); $vOptions.ChangelogFile = $entry
    $code = Invoke-ReleaseSteps -Steps @('version') -Journal $j -RepoRoot $machineRoot -Options $vOptions
    $cfgText = [IO.File]::ReadAllText((Join-Path $modDir 'itemV2.cfg'))
    $logText = [IO.File]::ReadAllText((Join-Path $modDir 'CHANGELOG.md'))
    if ($code -ne 0 -or (Get-ReleaseSourceVersion $machineRoot 'fixture_mod') -cne '0.1.3-dev' -or $cfgText.Contains('v0.1.2-dev') -or
            -not $cfgText.Contains('Fixture v0.1.3-dev"') -or -not $cfgText.Contains('[b]Fixture v0.1.3-dev[/b]') -or
            $logText.IndexOf('## 0.1.3-dev') -lt 0 -or $logText.IndexOf('## 0.1.3-dev') -gt $logText.IndexOf('## 0.1.2-dev')) {
        $failures += "version step did not write the version consistently (exit $code)"
    } else { Write-Host '  [PASS] version step writes MOD_VERSION, cfg title/banner and the top CHANGELOG entry' -ForegroundColor Green }
    $code = Invoke-ReleaseSteps -Steps @('version') -Journal $j -RepoRoot $machineRoot -Options $vOptions
    if ($code -ne 0 -or ([regex]::Matches([IO.File]::ReadAllText((Join-Path $modDir 'CHANGELOG.md')), '## 0\.1\.3-dev')).Count -ne 1) { $failures += 'a rerun of the version step changed the files again' }
    else { Write-Host '  [PASS] a completed version step is skipped on rerun' -ForegroundColor Green }

    # Clean version: the ship step stops with exit 20 unless -ConfirmVersion names it.
    $j = Reset-Machine '1.2.3' 0 $true
    $code = Invoke-ReleaseSteps -Steps @('ship') -Journal $j -RepoRoot $machineRoot -Options $options
    if ($code -ne 20 -or @($script:tool.Calls | Where-Object { $_ -like 'ship.ps1*' }).Count -ne 0) { $failures += "clean version did not stop with exit 20 (got $code)" }
    else { Write-Host '  [PASS] clean version stops before the ship with exit 20' -ForegroundColor Green }
    $cOptions = $options.PSObject.Copy(); $cOptions.ConfirmVersion = '1.2.3'
    $code = Invoke-ReleaseSteps -Steps @('ship') -Journal $j -RepoRoot $machineRoot -Options $cOptions
    if ($code -ne 0) { $failures += "confirmed clean version did not ship (got $code)" } else { Write-Host '  [PASS] -ConfirmVersion lets a clean version ship' -ForegroundColor Green }

    # A version with an ok ship record is never shipped again.
    $code = Invoke-ReleaseSteps -Steps @('ship') -Journal $j -RepoRoot $machineRoot -Options $cOptions
    if ($code -ne 0 -or @($script:tool.Calls | Where-Object { $_ -like 'ship.ps1*' }).Count -ne 1) { $failures += 'a completed ship was repeated' }
    else { Write-Host '  [PASS] a version with an ok ship record is not shipped again' -ForegroundColor Green }

    # Head moved: sync and ship again, at most three times, then exit 24.
    $j = Reset-Machine '0.1.3-dev' 0 $false 'Publication authorization FAILED: Source commit 1111 is not live master HEAD (2222).'
    $code = Invoke-ReleaseSteps -Steps @('ship') -Journal $j -RepoRoot $machineRoot -Options $options
    $ships = @($script:tool.Calls | Where-Object { $_ -like 'ship.ps1*' }).Count
    $syncs = @($script:gitCalls | Where-Object { $_ -like 'checkout --detach origin/master*' }).Count
    if ($code -ne 24 -or $ships -ne 3 -or $syncs -ne 3) { $failures += "head retry: expected exit 24 after 3 ships/3 syncs, got exit $code, $ships ships, $syncs syncs" }
    else { Write-Host '  [PASS] a moved head retries sync + ship three times, then exit 24' -ForegroundColor Green }
    $j = Reset-Machine '0.1.3-dev' 0 $false 'SDK upload failed'
    $code = Invoke-ReleaseSteps -Steps @('ship') -Journal $j -RepoRoot $machineRoot -Options $options
    if ($code -ne 23 -or @($script:tool.Calls | Where-Object { $_ -like 'ship.ps1*' }).Count -ne 1) { $failures += "an ordinary ship failure was retried (exit $code)" }
    else { Write-Host '  [PASS] an ordinary ship failure stops after one attempt (exit 23)' -ForegroundColor Green }

    # Dry run: nine steps reported, nothing written.
    $journalPath = Get-ReleaseJournalPath -Mod 'fixture_mod'
    if (Test-Path -LiteralPath $journalPath) { Remove-Item -LiteralPath $journalPath -Force }
    $j = Reset-Machine $null 3
    $dOptions = $options.PSObject.Copy(); $dOptions.DryRun = $true
    $printed = @(& { Invoke-ReleaseSteps -Steps $script:ReleaseStepNames -Journal $j -RepoRoot $machineRoot -Options $dOptions | Out-Null } 6>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match '^\[release\] .+: (done|pending)$' })
    if ($printed.Count -ne 9 -or (Test-Path -LiteralPath $journalPath) -or @($script:gitCalls | Where-Object { $_ -like 'fetch*' -or $_ -like 'checkout*' -or $_ -like 'commit*' }).Count -ne 0) {
        $failures += "dry run printed $($printed.Count) step lines or wrote state"
    } else { Write-Host '  [PASS] dry run prints nine steps and changes nothing' -ForegroundColor Green }
} catch {
    $failures += "step-machine fixture crashed: $($_.Exception.Message)"
} finally {
    $env:VT2_SHIP_RESULT_DIR = $previousDir
    if (Test-Path -LiteralPath $machineRoot) { Remove-Item -LiteralPath $machineRoot -Recurse -Force }
}
if ($failures.Count -gt 0) {
    Write-Host '[check_release_driver -SelfTest] FAILED' -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
    exit 2
}
Write-Host '[check_release_driver -SelfTest] OK -- land exit codes, body rule, journal, session id, skips, clean-version stop, head retry, dry run.' -ForegroundColor Green
exit 0
