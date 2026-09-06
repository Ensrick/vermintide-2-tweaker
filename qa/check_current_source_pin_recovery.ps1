# Offline real-process/Git recovery fixtures. No live API, launcher or game.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'qa\_test_fixtures\publication_handoff_fixture.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('vt2-current-pins-' + [guid]::NewGuid().ToString('N'))
$primary = Join-Path $root 'primary'
$linked = Join-Path $root 'linked'
$hostPath = (Get-Process -Id $PID).Path
$worktreeHost = @(Get-Command pwsh -CommandType Application -ErrorAction Stop)[0].Source
$passed = 0
function Assert([bool]$Value, [string]$Message) {
    if (-not $Value) { throw "[current-pin-recovery] $Message" }
    $script:passed++
}
function Write-Fixture([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path $Path -Parent)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Invoke-FixtureGit([string[]]$GitArgs) {
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& git.exe -C $primary @GitArgs 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code) { throw "Fixture git failed: $($GitArgs -join ' '): $($output -join ' ')" }
    return ($output -join "`n").Trim()
}
function Commit-Fixture([string]$Message) {
    $null = Invoke-FixtureGit @('add','--all')
    $null = Invoke-FixtureGit @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid',
        '-c',('core.hooksPath=' + (Join-Path $root 'empty-hooks')),'commit','-m',$Message)
    return Invoke-FixtureGit @('rev-parse','HEAD')
}
function Invoke-FixtureWorktree([string[]]$Arguments) {
    # The canonical lifecycle wrapper runs in its ordinary PS7 host. Recovery
    # workers still use this suite's host, including genuine PS5.1 executions.
    # Calling the wrapper in-process on PS5 mistakes Git's normal "Preparing
    # worktree" stderr for a terminating NativeCommandError before reading exit.
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = @(& $worktreeHost -NoProfile -NonInteractive -File $wrapper @Arguments 2>&1); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code) { throw "Canonical fixture worktree wrapper failed: $($output -join ' ')" }
    return $code
}
function Run-Worker([string]$Mode, [string]$At, [string]$State, [string]$Commit, [string]$Mutex) {
    foreach ($name in @('result.json','error.txt','finally.txt','crash-ready.txt')) {
        $file = Join-Path $State $name
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
    }
    $arguments = @('-NoProfile','-NonInteractive','-File', (Join-Path $repo 'qa\_test_fixtures\current_pin_recovery_worker.ps1'),
        '-RepoRoot',$repo,'-InvokingRoot',$At,'-FixtureRoot',$State,'-SourceCommit',$Commit,'-Mode',$Mode,'-MutexName',$Mutex)
    $quoted = @($arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' }) -join ' '
    $process = Start-Process -FilePath $hostPath -ArgumentList $quoted -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $State 'worker.out') -RedirectStandardError (Join-Path $State 'worker.err')
    $null = $process.Handle
    try {
        Assert ($process.WaitForExit(40000)) "Worker $Mode exceeded its bounded wait."
        $result = $null; $errorText = ''
        if (Test-Path (Join-Path $State 'result.json')) { $result = [IO.File]::ReadAllText((Join-Path $State 'result.json')) | ConvertFrom-Json }
        if (Test-Path (Join-Path $State 'error.txt')) { $errorText = [IO.File]::ReadAllText((Join-Path $State 'error.txt')) }
        return [pscustomobject]@{ Code = $process.ExitCode; Result = $result; Error = $errorText; Pid = $process.Id }
    }
    finally {
        if (-not $process.HasExited) { $process.Kill(); $null = $process.WaitForExit(5000) }
        $process.Dispose()
    }
}
function Make-Manifest([string]$Commit, [string]$Version) {
    return [ordered]@{ manifest_schema=2; release_tag='mods-2026-09-06'; mods=@(
        [ordered]@{mod_id='alpha';workshop_id='123';version=$Version;source_commit=$Commit;source_state='clean';asset_filename='alpha.zip';sha256=('a'*64)},
        [ordered]@{mod_id='beta';workshop_id='456';version=$Version;source_commit=$Commit;source_state='clean';asset_filename='beta.zip';sha256=('b'*64)}
    ) } | ConvertTo-Json -Depth 8
}
$linkedCreated = $false
try {
    [IO.Directory]::CreateDirectory($primary) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $root 'empty-hooks')) | Out-Null
    $null = Invoke-FixtureGit @('init','--quiet')
    $null = Invoke-FixtureGit @('config','core.autocrlf','false')
    Write-Fixture (Join-Path $primary 'tools\mod-inventory.psd1') "@{ Mods=@(@{Dir='alpha';ModId='alpha';WorkshopId='123'},@{Dir='beta';ModId='beta';WorkshopId='456'}) }"
    Write-Fixture (Join-Path $primary 'alpha\scripts\mods\alpha\alpha.lua') 'local MOD_VERSION = "0.1.1-dev"'
    Write-Fixture (Join-Path $primary 'beta\scripts\mods\beta\beta.lua') 'local MOD_VERSION = "0.1.1-dev"'
    # The canonical worktree wrapper needs only its budget guard in this tiny
    # fixture repository. It never creates another real project worktree.
    $budget = Join-Path $primary 'qa\check_worktree_budget.ps1'
    Write-Fixture $budget ([IO.File]::ReadAllText((Join-Path $repo 'qa\check_worktree_budget.ps1')))
    $seed = Commit-Fixture 'source fixture'
    $alphaOld = Invoke-FixtureGit @('rev-parse',($seed + ':alpha/scripts/mods'))
    $betaOld = Invoke-FixtureGit @('rev-parse',($seed + ':beta/scripts/mods'))
    $pinPath = Join-Path $primary 'tools\verify\live_test_contract_exceptions.psd1'
    $oldPins = "@{`n    LegacyMarkerFamilyModTrees = @{alpha='$alphaOld'}`n    LegacySourceTrees = @()`n    ReceiptFamilyOverrides = @(`n        @{Marker='[pair]';ModTrees=@{alpha='$alphaOld';beta='$betaOld'}}`n    )`n    ReceiptRouteOverrides = @(`n        @{ModId='alpha';Marker='[route]';ModTree='$alphaOld'}`n    )`n    ReceiptDiscoveryOverrides = @(`n        @{ModId='beta';Marker='[discovery]';ModTree='$betaOld'}`n    )`n}`n"
    Write-Fixture $pinPath $oldPins
    $oldCommit = Commit-Fixture 'old published pins'
    Write-Fixture (Join-Path $primary 'alpha\scripts\mods\alpha\alpha.lua') 'local MOD_VERSION = "0.1.2-dev"'
    Write-Fixture (Join-Path $primary 'beta\scripts\mods\beta\beta.lua') 'local MOD_VERSION = "0.1.2-dev"'
    $head = Commit-Fixture 'new reviewed source before publication'
    $alphaNew = Invoke-FixtureGit @('rev-parse',($head + ':alpha/scripts/mods'))
    $betaNew = Invoke-FixtureGit @('rev-parse',($head + ':beta/scripts/mods'))
    . (Join-Path $repo 'tools\ship\exception-pin-finalization.ps1')
    $expected = (Get-VtExceptionPinRepointPlan -ExceptionsText $oldPins -ModId alpha -DeployedTree $alphaNew).NewText
    $expected = (Get-VtExceptionPinRepointPlan -ExceptionsText $expected -ModId beta -DeployedTree $betaNew).NewText
    $wrapper = Join-Path $repo 'tools\worktrees\worktree.ps1'
    $createCode = Invoke-FixtureWorktree @('-Action','Create','-RepoRoot',$primary,'-Name','fixture-linked','-TargetPath',$linked,'-Branch','fixture/linked','-BaseRef','HEAD')
    Assert ($createCode -eq 0) 'Canonical fixture linked checkout creation failed.'
    $linkedCreated = $true
    $oldManifest = Make-Manifest $oldCommit '0.1.1-dev'
    $newManifest = Make-Manifest $head '0.1.2-dev'

    foreach ($case in @('OldCurrent','NewCurrent','MixedLineEndings','LinkedPending','LinkedConflict','CurrentWithPrimaryDirt',
        'LinkedPendingWithDirt','Borrowed','WrongRecord','WrongSource','ReplaceFailure','InvalidLaterRow','Unavailable')) {
        Write-Fixture $pinPath $oldPins
        $dirt = Join-Path $primary 'human-notes.txt'
        if (Test-Path $dirt) { Remove-Item -LiteralPath $dirt }
        $state = Join-Path $root $case
        [IO.Directory]::CreateDirectory($state) | Out-Null
        $manifest = if ($case -in @('OldCurrent','CurrentWithPrimaryDirt')) { $oldManifest } else { $newManifest }
        if ($case -eq 'InvalidLaterRow') {
            $bad = $newManifest | ConvertFrom-Json; $bad.mods[1].source_commit = 'a' * 40
            $manifest = $bad | ConvertTo-Json -Depth 8
        }
        Write-Fixture (Join-Path $state 'server.json') $manifest
        Write-Fixture (Join-Path $state 'claim.txt') 'retained'
        if ($case -in @('LinkedPending','LinkedPendingWithDirt')) { Write-Fixture $pinPath $expected }
        if ($case -eq 'LinkedConflict') { Write-Fixture $pinPath ($oldPins + '# human edit') }
        if ($case -in @('CurrentWithPrimaryDirt','LinkedPendingWithDirt')) { Write-Fixture $dirt 'human-owned' }
        if ($case -eq 'MixedLineEndings') {
            $null = Invoke-FixtureGit @('config','core.autocrlf','true')
            Write-Fixture $pinPath ($oldPins.Replace("`n", "`r`n"))
            # Refresh this toy checkout's normalization/stat cache after changing
            # its checkout policy. No staged blob may differ from fixture HEAD.
            $null = Invoke-FixtureGit @('add','--','tools/verify/live_test_contract_exceptions.psd1')
            Assert ((Invoke-FixtureGit @('diff','--cached','--name-only')) -ceq '') 'Line-ending fixture changed its immutable source blob.'
            Assert ((Invoke-FixtureGit @('status','--porcelain','--untracked-files=all')) -ceq '') 'CRLF primary is not a clean Git-supported checkout.'
            Assert ([IO.File]::ReadAllText((Join-Path $linked 'tools\verify\live_test_contract_exceptions.psd1')) -ceq $oldPins) 'Mixed-ending invoking checkout lost its original LF bytes.'
        }
        $before = [IO.File]::ReadAllText($pinPath)
        $mode = if ($case -in @('Borrowed','WrongRecord','WrongSource','ReplaceFailure','Unavailable')) { $case } else { 'Recover' }
        $result = Run-Worker $mode $linked $state $head ('Local\VT2.CurrentPins.' + [guid]::NewGuid().ToString('N'))
        $after = [IO.File]::ReadAllText($pinPath)
        if ($case -in @('NewCurrent','MixedLineEndings')) {
            Assert ($result.Code -eq 0 -and $result.Result.Changed -and $result.Result.RequiresMetadataPR) "$case did not repair and require metadata review: $($result.Error)"
            $wanted = if ($case -eq 'MixedLineEndings') { $expected.Replace("`n", "`r`n") } else { $expected }
            Assert ($after -ceq $wanted) 'All three consumed structures, both mods and destination line endings were not reconciled together.'
            Assert ($after.Contains("LegacyMarkerFamilyModTrees = @{alpha='$alphaOld'}")) 'Historical pin was rewritten.'
        }
        elseif ($case -in @('LinkedPending','LinkedPendingWithDirt')) {
            Assert ($result.Code -eq 0 -and -not $result.Result.Changed -and $result.Result.RequiresMetadataPR) "$case incorrectly allowed stale invoking source to continue: $($result.Error)"
            Assert ($after -ceq $before) "$case overwrote an existing pending candidate."
        }
        elseif ($case -in @('OldCurrent','CurrentWithPrimaryDirt','Unavailable')) {
            Assert ($result.Code -eq 0 -and -not $result.Result.Changed -and -not $result.Result.RequiresMetadataPR) "$case blocked an authorized no-op/fallback: $($result.Error)"
            Assert ($after -ceq $before) "$case inferred pin authority from an absent/new intended publication."
            if ($case -eq 'Unavailable') { Assert ($result.Result.Status -ceq 'unavailable') 'Unavailable read became successful source proof.' }
        }
        else {
            Assert ($result.Code -ne 0 -and $result.Error) "$case failed to reject invalid authority/write: $($result.Result | ConvertTo-Json -Compress)"
            Assert ($after -ceq $before) "$case partially changed pins before rejecting the later defect."
        }
        Assert (-not (Test-Path (Join-Path $state 'owner.json')) -and (Test-Path (Join-Path $state 'finally.txt'))) "$case did not release its actual transaction."
        Assert ([IO.File]::ReadAllText((Join-Path $state 'claim.txt')) -ceq 'retained') "$case released the claim."
        if (Test-Path $dirt) { Assert ([IO.File]::ReadAllText($dirt) -ceq 'human-owned') "$case overwrote unrelated primary changes." }
        Assert (-not ([IO.File]::ReadAllText((Join-Path $state 'worker.out'))).Contains('TEST BUILD READY')) "$case announced readiness."
        if ($case -eq 'MixedLineEndings') {
            $null = Invoke-FixtureGit @('config','core.autocrlf','false')
            Write-Fixture $pinPath $oldPins
            $null = Invoke-FixtureGit @('add','--','tools/verify/live_test_contract_exceptions.psd1')
            Assert ((Invoke-FixtureGit @('diff','--cached','--name-only')) -ceq '') 'Mixed-ending cleanup changed the fixture source index.'
        }
        Write-Host "[current-pin-recovery] PASS $case"
    }

    foreach ($case in @('CrashBeforeAccept','CrashAfterAccept','CrashAfterPins','ServerChangedAfterDeath')) {
        Write-Fixture $pinPath $oldPins
        if (Test-Path $dirt) { Remove-Item -LiteralPath $dirt }
        $state = Join-Path $root $case
        [IO.Directory]::CreateDirectory($state) | Out-Null
        Write-Fixture (Join-Path $state 'server.json') $(if ($case -eq 'CrashAfterPins') { $newManifest } else { $oldManifest })
        Write-Fixture (Join-Path $state 'new-server.json') $newManifest
        Write-Fixture (Join-Path $state 'claim.txt') 'retained'
        $mutex = 'Local\VT2.CurrentPins.' + [guid]::NewGuid().ToString('N')
        $deathMode = if ($case -eq 'ServerChangedAfterDeath') { 'CrashAfterAccept' } else { $case }
        $dead = Run-Worker $deathMode $linked $state $head $mutex
        Assert ($dead.Code -ne 0 -and (Test-Path (Join-Path $state 'crash-ready.txt')) -and
            -not (Test-Path (Join-Path $state 'finally.txt'))) "$case did not prove actual hard death without finally."
        Assert (Test-Path (Join-Path $state 'owner.json')) "$case did not retain the abandoned durable owner."
        if ($case -eq 'ServerChangedAfterDeath') {
            # A subsequent publication may deliberately restore an older source.
            # Current server authority wins; version numbers are not ordering.
            Write-Fixture (Join-Path $state 'server.json') $oldManifest
        }
        $retry = Run-Worker 'Recover' $linked $state $head $mutex
        Assert ($retry.Code -eq 0) "$case fresh owner failed recovery: $($retry.Error)"
        $requires = ($case -notin @('CrashBeforeAccept','ServerChangedAfterDeath'))
        Assert ($retry.Result.RequiresMetadataPR -eq $requires) "$case inferred publication from previous intent or lost metadata gate."
        $wanted = if ($requires) { $expected } else { $oldPins }
        Assert ([IO.File]::ReadAllText($pinPath) -ceq $wanted) "$case recovered a target other than current server state."
        $readPids = [IO.File]::ReadAllLines((Join-Path $state 'reads.txt'))
        Assert ($readPids -contains [string]$retry.Pid) "$case reused prior memory instead of a fresh-process manifest read."
        Assert (-not (Test-Path (Join-Path $state 'owner.json'))) "$case left recovery ownership behind."
        if ($case -eq 'CrashAfterPins') { Assert (-not $retry.Result.Changed) 'Retry after atomic replacement rewrote the pending candidate.' }
        Write-Host "[current-pin-recovery] PASS $case"
    }
    Write-Fixture $pinPath $oldPins
    $state = Join-Path $root 'RemovedOriginalCheckout'
    [IO.Directory]::CreateDirectory($state) | Out-Null
    Write-Fixture (Join-Path $state 'server.json') $oldManifest
    Write-Fixture (Join-Path $state 'new-server.json') $newManifest
    $mutex = 'Local\VT2.CurrentPins.' + [guid]::NewGuid().ToString('N')
    $dead = Run-Worker 'CrashAfterAccept' $linked $state $head $mutex
    Assert ($dead.Code -ne 0 -and -not (Test-Path (Join-Path $state 'finally.txt'))) 'Removed-checkout control did not actually die.'
    $closeCode = Invoke-FixtureWorktree @('-Action','Close','-RepoRoot',$primary,'-TargetPath',$linked)
    Assert ($closeCode -eq 0) 'Canonical fixture linked checkout close failed.'
    $linkedCreated = $false
    Assert (-not (Test-Path $linked)) 'Original publication checkout still exists.'
    $intervening = Run-Worker 'LeaseOnly' $primary $state $head $mutex
    Assert ($intervening.Code -eq 0 -and -not (Test-Path (Join-Path $state 'owner.json'))) 'Intervening ordinary lease did not acquire/release and erase its owner record.'
    $retry = Run-Worker 'Recover' $primary $state $head $mutex
    Assert ($retry.Code -eq 0 -and $retry.Result.Changed -and $retry.Result.RequiresMetadataPR) "Recovery depended on an old checkout/owner journal: $($retry.Error)"
    Assert ([IO.File]::ReadAllText($pinPath) -ceq $expected) 'Removed-checkout recovery did not repair only the current primary.'
    Write-Host '[current-pin-recovery] PASS RemovedOriginalCheckoutAfterInterveningLease'

    # The actual canonical call is inside the non-BuildOnly authorization arm,
    # after the successful exact-source gate and before the first build phase.
    $ship = [IO.File]::ReadAllText((Join-Path $repo 'tools\ship\ship.ps1'), [Text.Encoding]::UTF8)
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($ship,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) 'Canonical ship does not parse.'
    $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Invoke-VtCurrentSourcePinReconciliation'},$true))
    Assert ($calls.Count -eq 1) 'Canonical recovery must have exactly one actual call site.'
    $owner=$calls[0].Parent
    while ($owner -and $owner -isnot [Management.Automation.Language.IfStatementAst]) { $owner=$owner.Parent }
    Assert ($owner -and $owner.Clauses[0].Item1.Extent.Text -ceq '-not $BuildOnly') 'Recovery escaped the publication-only arm.'
    $prefix=$owner.Extent.Text.Substring(0,$calls[0].Extent.StartOffset-$owner.Extent.StartOffset)
    Assert ($prefix.Contains('Get-LivePublicationAuthorization') -and $prefix.Contains('if (-not $publicationAuthorization.Ok)')) 'Recovery executes before exact hosted authorization.'
    Assert ($owner.Extent.Text.Contains('if ($currentPinResult.RequiresMetadataPR)') -and $owner.Extent.Text.Contains("Fail 'Current source pins require a reviewed metadata PR")) 'Metadata repair no longer stops canonical ship.'
    Remove-VtPublicationHandoffFixtureDirectory -Path $root -ParentRoot ([IO.Path]::GetTempPath()) -LeafPattern '^vt2-current-pins-[0-9a-f]{32}$'
    Write-Host "[current-pin-recovery] PASS $passed assertions; all disposable fixtures closed/removed."
    exit 0
}
catch {
    Write-Host "[current-pin-recovery] FAIL: $_; retained fixture root: $root"
    if ($linkedCreated) { Write-Host "Fixture linked checkout retained for evidence: $linked (not a project worktree)." }
    exit 2
}
