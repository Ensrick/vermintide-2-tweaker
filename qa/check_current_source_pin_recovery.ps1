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
    foreach ($name in @('result.json','error.txt','finally.txt','crash-ready.txt','mutant-installed.txt')) {
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

    # #1777: opt-in tests extend the SAME actual-function/Git/process fixture.
    # Tiny inert bundle/descriptor bytes exercise receipt semantics, NOT an SDK
    # build, game launch, publication, Workshop observation or historical proof.
    . (Join-Path $repo 'tools\ship\build-receipt.ps1')
    . (Join-Path $repo 'tools\ship\build-output-normalization.ps1')
    . (Join-Path $repo 'tools\verify\live_test_source_authority.ps1')
    function Get-TransitionSource([string]$Version) {
        $source = @'
local MOD_VERSION = "__FIXTURE_VERSION__"
local emitted = false
local function emit()
    if emitted then return end
    emitted = true
    printf("[alpha:1777] status=OK")
    printf("[alpha:1777] other=OK")
end
emit()
'@
        return $source.Replace('__FIXTURE_VERSION__',$Version)
    }
    function New-TransitionPins([string]$FromCommit, [string]$FromTree, [string]$ToTree, [string]$ReceiptHash) {
        $text = @"
@{
    ReviewedRouteTransitions = @(
        @{ModId='alpha';FromSourceCommit='$FromCommit';CandidateModTree='$ToTree';CandidateReceiptSha256='$ReceiptHash'}
    )
    LegacyMarkerFamilyModTrees = @{alpha='$FromTree'}
    LegacySourceTrees = @()
    ReceiptFamilyOverrides = @()
    ReceiptRouteOverrides = @(
        @{ModId='alpha';ModTrees=@('$FromTree','$ToTree');Source='alpha/scripts/mods/alpha/alpha.lua';Marker='[alpha:1777]';Signature='[alpha:1777] status=OK';Bound='one call per module generation';EmitterAnchors=@('printf("[alpha:1777] status=OK")');GuardAnchors=@('local emitted = false','if emitted then return end','emitted = true')}
        @{ModId='alpha';ModTrees=@('$FromTree','$ToTree');Source='alpha/scripts/mods/alpha/alpha.lua';Marker='[alpha:1777]';Signature='[alpha:1777] other=OK';Bound='one call per module generation';EmitterAnchors=@('printf("[alpha:1777] other=OK")');GuardAnchors=@('local emitted = false','if emitted then return end','emitted = true')}
    )
    ReceiptDiscoveryOverrides = @(
        @{ModId='beta';Marker='[discovery]';ModTree='$betaNew'}
    )
}
"@
        return $text.Replace(([string][char]13),'') + [char]10
    }
    function Get-TransitionManifest([string]$AlphaCommit, [string]$AlphaVersion, [string]$BetaCommit) {
        $value = Make-Manifest $BetaCommit '0.1.2-dev' | ConvertFrom-Json
        $value.mods[0].source_commit = $AlphaCommit; $value.mods[0].version = $AlphaVersion
        return $value | ConvertTo-Json -Depth 8
    }
    function Assert-TransitionRefusal($Run, [string]$Expected, [string]$Name) {
        Assert ($Run.Code -ne 0 -and $Run.Error.Contains($Expected)) "$Name must fail closed in the normal policy assertion."
    }
    function Run-Transition([string]$Name, [string]$Commit, [string]$Manifest, [string]$Mode = 'Recover') {
        $state = Join-Path $root ('Transition-' + $Name)
        [IO.Directory]::CreateDirectory($state) | Out-Null
        Write-Fixture (Join-Path $state 'server.json') $Manifest
        Write-Fixture (Join-Path $state 'claim.txt') 'retained'
        $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pinPath))
        $run = Run-Worker $Mode $primary $state $Commit ('Local\VT2.CurrentPins.' + [guid]::NewGuid().ToString('N'))
        # Setup/compile failures CANNOT kill a mutant. This check is outside the
        # control's normal-assertion catch and requires the installation marker.
        if ($Mode -like 'Mutant*') {
            Assert ((Test-Path (Join-Path $state 'mutant-installed.txt')) -and
                [IO.File]::ReadAllText((Join-Path $state 'mutant-installed.txt')) -ceq $Mode) "$Name mutant setup did not complete."
        }
        Assert (-not (Test-Path (Join-Path $state 'owner.json')) -and (Test-Path (Join-Path $state 'finally.txt'))) "$Name lost normal owning-lease cleanup."
        Assert ([IO.File]::ReadAllText((Join-Path $state 'claim.txt')) -ceq 'retained') "$Name released the fixture claim."
        Assert (-not ([IO.File]::ReadAllText((Join-Path $state 'worker.out'))).Contains('TEST BUILD READY')) "$Name announced readiness."
        return [pscustomobject]@{ Run=$run; Before=$before; After=[Convert]::ToBase64String([IO.File]::ReadAllBytes($pinPath)); State=$state }
    }
    $lf = [string][char]10
    $alphaPath = Join-Path $primary 'alpha\scripts\mods\alpha\alpha.lua'
    Write-Fixture (Join-Path $primary 'tools\mod-inventory.psd1') "@{ Mods=@(@{Dir='alpha';ModId='alpha';WorkshopId='123';RootBundle='aaaaaaaaaaaaaaaa.mod_bundle';BundleAuthority='tracked'},@{Dir='beta';ModId='beta';WorkshopId='456'}) }"
    Write-Fixture $pinPath $expected
    Write-Fixture $alphaPath (Get-TransitionSource '0.1.3-dev')
    Write-Fixture (Join-Path $primary 'alpha\alpha.mod') 'inert fixture descriptor'
    Write-Fixture (Join-Path $primary 'alpha\bundleV2\alpha.mod') 'inert fixture descriptor'
    Write-Fixture (Join-Path $primary 'alpha\bundleV2\aaaaaaaaaaaaaaaa.mod_bundle') 'inert fixture output'
    $fromCommit = Commit-Fixture 'reviewable same-mod ancestor (not publication evidence)'
    $fromTree = Invoke-FixtureGit @('rev-parse',($fromCommit + ':alpha/scripts/mods'))
    Write-Fixture $alphaPath (Get-TransitionSource '0.1.4-dev')
    $toSource = Commit-Fixture 'candidate source and inert complete output set'
    $toTree = Invoke-FixtureGit @('rev-parse',($toSource + ':alpha/scripts/mods'))
    $entry = (Import-PowerShellDataFile -LiteralPath (Join-Path $primary 'tools\mod-inventory.psd1')).Mods[0]
    $map = Get-VtBuildCommitSourceMap -RepoRoot $primary -Mod alpha -Commit $toSource
    $outputs = Get-VtBuildCommitOutputSet -RepoRoot $primary -Mod alpha -Commit $toSource -SourceMap $map -InventoryEntry $entry
    $normalization = New-BuildOutputNormalizationPolicyProof -ModEntry $entry
    $receipt = New-VtBuildReceipt -Mod alpha -SourceMap $map -OutputSet $outputs -BuilderVersion 'inert-fixture-only' -NormalizationPolicy $normalization
    $receiptPath = Write-VtBuildReceipt -RepoRoot $primary -Mod alpha -Receipt $receipt
    $receiptText = [IO.File]::ReadAllText($receiptPath)
    $receiptHash = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $null = Commit-Fixture 'schema-3 fixture receipt (no compile or publication)'
    $pairPins = New-TransitionPins $fromCommit $fromTree $toTree $receiptHash
    Write-Fixture $pinPath $pairPins
    $pairHead = Commit-Fixture 'reviewed exact pair declaration outside mod source'
    $pairOldManifest = Get-TransitionManifest $fromCommit '0.1.3-dev' $pairHead
    $pairNewManifest = Get-TransitionManifest $pairHead '0.1.4-dev' $pairHead
    foreach ($case in @('FromCurrent','ToCurrent','FinalizerTo')) {
        $manifest = if ($case -eq 'FromCurrent') { $pairOldManifest } else { $pairNewManifest }
        $mode = if ($case -eq 'FinalizerTo') { 'TransitionFinalize' } else { 'Recover' }
        $outcome = Run-Transition $case $pairHead $manifest $mode
        if ($case -eq 'FinalizerTo') { Assert $outcome.Run.Result.Completed 'Actual finalizer did not complete its retained-pair plan.' }
        Assert ($outcome.Run.Code -eq 0 -and -not $outcome.Run.Result.Changed -and -not $outcome.Run.Result.RequiresMetadataPR) "$case did not retain its reviewed pair: $($outcome.Run.Error)"
        Assert ($outcome.Before -ceq $outcome.After) "$case was not a byte-exact no-op."
        # Actual selected-source consumer, not a modeled/prefilled route list.
        $selectedCommit = if ($case -eq 'FromCurrent') { $fromCommit } else { $pairHead }
        $selectedTree = if ($case -eq 'FromCurrent') { $fromTree } else { $toTree }
        $documents = @(Get-VtDeployedLuaDocuments -RepoRoot $primary -Treeish $selectedCommit -RelativeRoot 'alpha/scripts/mods')
        $scan = Get-VtDirectLuaCallRoutes -Document $documents[0]
        $routes = New-Object 'System.Collections.Generic.List[object]'
        foreach ($route in @($scan.ReceiptRoutes)) { $routes.Add($route) }
        Set-VtReceiptOverrideBounds -ModId alpha -ModTree $selectedTree -Documents $documents -Routes $routes -CommandRoutes @($scan.CommandRoutes) -Exceptions (Import-PowerShellDataFile -LiteralPath $pinPath)
        Assert ($routes.Count -eq 2 -and @($routes | Where-Object { -not $_.Bound }).Count -eq 0) "$case bypassed actual selected-source route/anchor checks."
    }
    # The constructor and pure planner must bind the actual text parameter,
    # not another import of the working file. No setup fault counts as refusal.
    $pairProofs = New-VtReviewedRouteTransitionProofs -RepoRoot $primary -SourceCommit $pairHead -ExceptionsText $pairPins
    $changedText = $pairPins.Replace("Bound='one call per module generation'","Bound='unreviewed changed bound'")
    Assert ($changedText -cne $pairPins) 'Actual-text mismatch setup did not change its bound.'
    $message = ''
    try { $null = New-VtReviewedRouteTransitionProofs -RepoRoot $primary -SourceCommit $pairHead -ExceptionsText $changedText }
    catch { $message = $_.Exception.Message }
    Assert ($message -ceq '[route-transition] routes differ from authorized source') 'Constructor trusted another metadata import instead of actual text.'
    $message = ''
    try { $null = Get-VtExceptionPinRepointPlan -ExceptionsText $changedText -ModId alpha -DeployedTree $toTree -TransitionProofs $pairProofs }
    catch { $message = $_.Exception.Message }
    Assert ($message -ceq '[route-transition] planned rows differ from constructed proof') 'Planner trusted stale proof rows instead of actual text.'
    $message = ''
    try { $null = Get-VtExceptionPinRepointPlan -ExceptionsText $pairPins -ModId alpha -DeployedTree $toTree }
    catch { $message = $_.Exception.Message }
    Assert ($message -ceq '[route-transition] exact constructed proof set required') 'Unconstructed transition facts were optional.'

    # Metadata-only HEAD changes preserve tree/receipt, NOT prior HEAD approval.
    Write-Fixture $pinPath ($pairPins + $lf + '# reviewed metadata-only head')
    $metadataHead = Commit-Fixture 'metadata-only exact new head'
    $outcome = Run-Transition 'MetadataHead' $metadataHead (Get-TransitionManifest $metadataHead '0.1.4-dev' $metadataHead)
    Assert ($outcome.Run.Code -eq 0 -and $outcome.Before -ceq $outcome.After) 'Metadata-only HEAD was confused with a changed mod tree.'
    $badSourceHead = Run-Transition 'OldHeadNotAuthorized' $pairHead $pairNewManifest
    Assert-TransitionRefusal $badSourceHead.Run 'already authorized clean exact source checkout' 'OldHeadNotAuthorized'

    # Every negative is committed fixture policy before the real owner enters;
    # mismatch/shape/receipt failures must leave the original bytes untouched.
    $orphan = Invoke-FixtureGit @('-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit-tree',($fromCommit + '^{tree}'),'-m','unrelated source history')
    $third = 'c' * 40
    $cases = @(
        @{Name='UnknownField';Text=$pairPins.Replace("CandidateModTree=","Extra='no';CandidateModTree=");Error='exactly four fields'},
        @{Name='WrongCaseField';Text=$pairPins.Replace('FromSourceCommit=','fromSourceCommit=');Error='wrong-case field'},
        @{Name='WrongCaseId';Text=$pairPins.Replace("ModId='alpha';FromSourceCommit=","ModId='Alpha';FromSourceCommit=");Error='canonical inventory identity'},
        @{Name='DuplicateDeclaration';Text=$pairPins;Error='malformed or duplicate'},
        @{Name='DuplicateMember';Text=$pairPins.Replace("ModTrees=@('$fromTree','$toTree')","ModTrees=@('$fromTree','$fromTree')");Error='every route must name exactly'},
        @{Name='UppercaseMember';Text=$pairPins.Replace("ModTrees=@('$fromTree','$toTree')",("ModTrees=@('" + $fromTree.ToUpperInvariant() + "','$toTree')"));Error='every route must name exactly'},
        @{Name='ThirdMember';Text=$pairPins.Replace("ModTrees=@('$fromTree','$toTree')","ModTrees=@('$fromTree','$toTree','$third')");Error='every route must name exactly'},
        @{Name='SplitPair';Text=$pairPins;Error='every route must name exactly'},
        @{Name='ForeignCandidate';Text=$pairPins.Replace("CandidateModTree='$toTree'","CandidateModTree='$betaNew'");Error='inventory-qualified candidate tree mismatch'},
        @{Name='ReceiptDigest';Text=$pairPins.Replace($receiptHash,('d'*64));Error='candidate receipt digest mismatch'},
        @{Name='NonAncestor';Text=$pairPins.Replace($fromCommit,$orphan);Error='Transition same-history ancestor failed'},
        @{Name='ForeignSource';Text=$pairPins.Replace('alpha/scripts/mods/alpha/alpha.lua','beta/scripts/mods/beta/beta.lua');Error='foreign route/anchor source'},
        @{Name='GuardDrift';Text=$pairPins.Replace("'emitted = true'","'emitted = 17'");Error='Reviewed route retention anchor drift'},
        @{Name='MixedFamily';Text=$pairPins.Replace('ReceiptFamilyOverrides = @()',"ReceiptFamilyOverrides = @(@{ModId='alpha';ModTrees=@{alpha='$fromTree'}})");Error='family/discovery ownership'},
        @{Name='WrongFieldType';Text=$pairPins.Replace("FromSourceCommit='$fromCommit'","FromSourceCommit=17");Error='mistyped or wrong-case'},
        @{Name='ScalarPins';Text=$pairPins.Replace("ModTrees=@('$fromTree','$toTree')","ModTree='$fromTree'");Error='every route must name exactly'},
        @{Name='SameSourceTree';Text=$pairPins.Replace("FromSourceCommit='$fromCommit'","FromSourceCommit='$toSource'");Error='two distinct trees'},
        @{Name='DuplicateRoute';Text=$pairPins.Replace("Signature='[alpha:1777] other=OK'","Signature='[alpha:1777] status=OK'");Error='duplicate route identity'},
        @{Name='MixedDiscovery';Text=$pairPins.Replace("ModId='beta';Marker='[discovery]';ModTree='$betaNew'","ModId='alpha';Marker='[discovery]';ModTree='$fromTree'");Error='family/discovery ownership'}
    )
    # Duplicate declaration must be INSIDE its array, not a PSD parser failure.
    $duplicate = "        @{ModId='alpha';FromSourceCommit='$fromCommit';CandidateModTree='$toTree';CandidateReceiptSha256='$receiptHash'}"
    $cases[3].Text = $pairPins.Replace(('    )' + $lf + '    LegacyMarkerFamilyModTrees'),($duplicate + $lf + '    )' + $lf + '    LegacyMarkerFamilyModTrees'))
    # Split only the second inline row; the first row still includes Current=To.
    $line = @($pairPins -split $lf | Where-Object { $_.Contains("Signature='[alpha:1777] other=OK'") })[0]
    $cases[7].Text = $pairPins.Replace($line,$line.Replace($toTree,$third))
    foreach ($case in $cases) {
        Assert ($case.Text -cne $pairPins) "$($case.Name) setup failed to mutate the intended policy."
        if ($case.Name -eq 'GuardDrift') {
            # "emitted = false" also occurs in the real initializer and is NOT
            # a missing anchor. This sentinel is absent in both authored sources.
            Assert (-not (Get-TransitionSource '0.1.3-dev').Contains('emitted = 17') -and
                -not (Get-TransitionSource '0.1.4-dev').Contains('emitted = 17')) 'GuardDrift setup must name a genuinely absent source anchor.'
        }
        Write-Fixture $pinPath $case.Text
        $caseHead = Commit-Fixture ('reject ' + $case.Name)
        $outcome = Run-Transition $case.Name $caseHead (Get-TransitionManifest $caseHead '0.1.4-dev' $caseHead)
        Assert-TransitionRefusal $outcome.Run $case.Error $case.Name
        Assert ($outcome.Before -ceq $outcome.After) "$($case.Name) wrote before rejecting its policy."
        if ($case.Name -in @('MixedFamily','MixedDiscovery')) {
            # Supplied text cannot mask ineligible AUTHORIZED committed policy.
            $removalName = 'Committed' + $case.Name + 'Removal'
            $remove = if ($case.Name -eq 'MixedFamily') { "@{ModId='alpha';ModTrees=@{alpha='$fromTree'}}" } else { "@{ModId='alpha';Marker='[discovery]';ModTree='$fromTree'}" }
            Assert ([regex]::Matches($case.Text,[regex]::Escape($remove)).Count -eq 1) "$removalName setup must remove exactly one owned entry."
            $maskedText = $case.Text.Replace($remove,'')
            $sourceBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pinPath))
            $message = ''
            try { $null = New-VtReviewedRouteTransitionProofs -RepoRoot $primary -SourceCommit $caseHead -ExceptionsText $maskedText }
            catch { $message = $_.Exception.Message }
            Assert ($message -ceq '[route-transition] family/discovery ownership is not eligible') "$removalName must preserve the exact committed-eligibility refusal."
            Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($pinPath)) -ceq $sourceBytes) "$removalName changed committed policy bytes."
            Write-Host "[current-pin-recovery] PASS $removalName exact policy refusal"
        }
    }
    # Digest agrees with tampered bytes; semantic schema-3 proof still refuses.
    $badReceipt = $receiptText | ConvertFrom-Json
    $badReceipt.source_fingerprint_sha256 = 'e' * 64
    Write-Fixture $receiptPath (ConvertTo-VtBuildReceiptJson $badReceipt)
    $badHash = (Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Fixture $pinPath ($pairPins.Replace($receiptHash,$badHash))
    $badReceiptHead = Commit-Fixture 'semantic receipt defect with matching declaration digest'
    $outcome = Run-Transition 'ReceiptSemantic' $badReceiptHead (Get-TransitionManifest $badReceiptHead '0.1.4-dev' $badReceiptHead)
    Assert-TransitionRefusal $outcome.Run 'candidate schema-3 proof invalid' 'ReceiptSemantic'
    Assert ($outcome.Before -ceq $outcome.After) 'Semantic receipt failure changed metadata.'

    # A genuine third source exists, but it is NOT granted retained-pair status.
    Write-Fixture $receiptPath $receiptText
    Write-Fixture $pinPath $pairPins
    Write-Fixture $alphaPath (Get-TransitionSource '0.1.5-dev')
    $thirdCommit = Commit-Fixture 'independent currently selected third source'
    $thirdTree = Invoke-FixtureGit @('rev-parse',($thirdCommit + ':alpha/scripts/mods'))
    $outcome = Run-Transition 'NoNextGenerationReuse' $thirdCommit (Get-TransitionManifest $thirdCommit '0.1.5-dev' $thirdCommit)
    Assert-TransitionRefusal $outcome.Run 'inventory-qualified candidate tree mismatch' 'NoNextGenerationReuse'
    Assert ($outcome.Before -ceq $outcome.After) 'A new source generation silently reused retained authority.'
    Write-Fixture $alphaPath (Get-TransitionSource '0.1.4-dev')
    $restoredHead = Commit-Fixture 'restore exact reviewed candidate and receipt'
    $splitCase = @($cases | Where-Object { $_.Name -ceq 'SplitPair' })[0]
    Write-Fixture $pinPath $splitCase.Text
    $invalidThirdHead = Commit-Fixture 'malformed policy precedes valid missing-current fallback'
    $outcome = Run-Transition 'MalformedBeforeMissingCurrent' $invalidThirdHead (Get-TransitionManifest $thirdCommit '0.1.5-dev' $invalidThirdHead)
    Assert-TransitionRefusal $outcome.Run 'every route must name exactly the same reviewed pair' 'MalformedBeforeMissingCurrent'
    Assert ($outcome.Before -ceq $outcome.After) 'Malformed policy took missing-current rewrite before failing.'
    Write-Fixture $pinPath $pairPins
    $restoredHead = Commit-Fixture 'restore valid reviewed policy before ordinary recovery'
    $thirdManifest = Get-TransitionManifest $thirdCommit '0.1.5-dev' $restoredHead
    $outcome = Run-Transition 'MissingCurrent' $restoredHead $thirdManifest
    Assert ($outcome.Run.Code -eq 0 -and $outcome.Run.Result.Changed -and $outcome.Run.Result.RequiresMetadataPR) 'MissingCurrent must take ordinary rewrite plus reviewed metadata stop.'
    $missingText = [IO.File]::ReadAllText($pinPath)
    Assert ($missingText.Contains("ModTrees=@('$thirdTree')") -and -not $missingText.Contains("ModTrees=@('$fromTree','$toTree','$thirdTree')")) 'MissingCurrent invented a third retained member.'
    Assert ($missingText.Contains("FromSourceCommit='$fromCommit'")) 'MissingCurrent silently replaced/revoked its declaration instead of leaving a review candidate.'
    Write-Fixture $pinPath $pairPins

    # Real hard death in the existing worker; only the fresh server read selects
    # a member. No surviving old owner/checkout observation becomes authority.
    foreach ($deathMode in @('CrashBeforeAccept','CrashAfterAccept','CrashAfterPins')) {
        $state = Join-Path $root ('Transition-' + $deathMode)
        [IO.Directory]::CreateDirectory($state) | Out-Null
        $old = Get-TransitionManifest $fromCommit '0.1.3-dev' $restoredHead
        $new = Get-TransitionManifest $restoredHead '0.1.4-dev' $restoredHead
        Write-Fixture (Join-Path $state 'server.json') $(if ($deathMode -eq 'CrashAfterPins') { $new } else { $old })
        Write-Fixture (Join-Path $state 'new-server.json') $new
        Write-Fixture (Join-Path $state 'claim.txt') 'retained'
        $mutex = 'Local\VT2.CurrentPins.' + [guid]::NewGuid().ToString('N')
        $dead = Run-Worker $deathMode $primary $state $restoredHead $mutex
        Assert ($dead.Code -ne 0 -and (Test-Path (Join-Path $state 'crash-ready.txt')) -and -not (Test-Path (Join-Path $state 'finally.txt'))) "$deathMode did not actually die without finally."
        $retry = Run-Worker 'Recover' $primary $state $restoredHead $mutex
        Assert ($retry.Code -eq 0 -and -not $retry.Result.Changed -and -not $retry.Result.RequiresMetadataPR) "$deathMode failed reviewed-pair fresh-process recovery: $($retry.Error)"
        Assert ([IO.File]::ReadAllText($pinPath) -ceq $pairPins) "$deathMode rewrote a valid reviewed pair."
        Assert ([IO.File]::ReadAllLines((Join-Path $state 'reads.txt')) -contains [string]$retry.Pid) "$deathMode did not read the fresh current manifest."
        Assert ([IO.File]::ReadAllText((Join-Path $state 'claim.txt')) -ceq 'retained') "$deathMode released the claim."
    }

    # The primary destination has its OWN exact text. A valid clean linked
    # source plus a stale legacy sibling must not bypass a changed retained row.
    $destinationPins = $pairPins.Replace("Marker='[discovery]';ModTree='$betaNew'","Marker='[discovery]';ModTree='$betaOld'")
    Write-Fixture $pinPath $destinationPins
    $destinationHead = Commit-Fixture 'destination exact-text guard source'
    $createCode = Invoke-FixtureWorktree @('-Action','Create','-RepoRoot',$primary,'-Name','fixture-transition-target','-TargetPath',$linked,'-Branch','fixture/transition-target','-BaseRef','HEAD')
    Assert ($createCode -eq 0) 'Transition destination linked fixture creation failed.'
    $linkedCreated = $true
    $row = @($destinationPins -split $lf | Where-Object { $_.Contains("Signature='[alpha:1777] other=OK'") })[0]
    $conflict = $destinationPins.Replace($row,$row.Replace($toTree,$thirdTree))
    Assert ($conflict -cne $destinationPins) 'Destination pair-conflict setup did not change its row.'
    Write-Fixture $pinPath $conflict
    $state = Join-Path $root 'Transition-DestinationPairConflict'
    [IO.Directory]::CreateDirectory($state) | Out-Null
    Write-Fixture (Join-Path $state 'server.json') (Get-TransitionManifest $destinationHead '0.1.4-dev' $destinationHead)
    Write-Fixture (Join-Path $state 'claim.txt') 'retained'
    $before = [Convert]::ToBase64String([IO.File]::ReadAllBytes($pinPath))
    $outcome = Run-Worker 'Recover' $linked $state $destinationHead ('Local\VT2.CurrentPins.' + [guid]::NewGuid().ToString('N'))
    Assert-TransitionRefusal $outcome 'every route must name exactly the same reviewed pair' 'DestinationPairConflict'
    Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($pinPath)) -ceq $before) 'Destination pair conflict was overwritten.'
    Assert ([IO.File]::ReadAllText((Join-Path $state 'claim.txt')) -ceq 'retained') 'Destination pair conflict released the claim.'
    Write-Fixture $pinPath $destinationPins
    $closeCode = Invoke-FixtureWorktree @('-Action','Close','-RepoRoot',$primary,'-TargetPath',$linked)
    Assert ($closeCode -eq 0) 'Transition destination linked fixture close failed.'
    $linkedCreated = $false

    # Mutants replace ONE exact preimage in actual production functions, outside
    # the worker catch. Each must fail the SAME normal outcome assertion; a
    # setup/parser failure or unrelated exception cannot count as a killed control.
    $transitionControlsKilled = 0
    foreach ($control in @(
        @{Name='Receipt';Case='ReceiptDigest';Mode='MutantReceipt'},
        @{Name='Pair';Case='SplitPair';Mode='MutantPair'},
        @{Name='Ancestry';Case='NonAncestor';Mode='MutantAncestry'},
        @{Name='Membership';Case='MissingCurrent';Mode='MutantMembership'}
    )) {
        $case = @($cases | Where-Object { $_.Name -ceq $control.Case })
        $text = if ($control.Name -eq 'Membership') { $pairPins } else { $case[0].Text }
        Write-Fixture $pinPath $text
        $controlHead = Commit-Fixture ('mutant control ' + $control.Name)
        $manifest = if ($control.Name -eq 'Membership') { Get-TransitionManifest $thirdCommit '0.1.5-dev' $controlHead } else { Get-TransitionManifest $controlHead '0.1.4-dev' $controlHead }
        $outcome = Run-Transition ('Control-' + $control.Name) $controlHead $manifest $control.Mode
        Assert ($outcome.Run.Code -eq 0 -and $null -ne $outcome.Run.Result) "$($control.Name) mutant did not reach the normal actual plan return."
        $normalMessage = if ($control.Name -eq 'Membership') { '[current-pin-recovery] MissingCurrent must take ordinary rewrite plus reviewed metadata stop.' } else { "[current-pin-recovery] $($control.Case) must fail closed in the normal policy assertion." }
        $killed = $false
        try {
            if ($control.Name -eq 'Membership') {
                Assert ($outcome.Run.Code -eq 0 -and $outcome.Run.Result.Changed -and $outcome.Run.Result.RequiresMetadataPR) 'MissingCurrent must take ordinary rewrite plus reviewed metadata stop.'
            } else { Assert-TransitionRefusal $outcome.Run $case[0].Error $control.Case }
        }
        catch {
            if ($_.Exception.Message -cne $normalMessage) { throw }
            $killed = $true
        }
        Assert $killed "$($control.Name) control did not fail its normal assertion."
        $transitionControlsKilled++
        Assert ($outcome.Before -ceq $outcome.After) "$($control.Name) control unexpectedly changed fixture bytes."
        Write-Host "[current-pin-recovery] PASS #1777 mutant $($control.Name) killed by normal assertion"
    }
    Write-Fixture $pinPath $pairPins
    # Membership is the final control and commits this exact pair already.
    # Reuse that real HEAD; do not invent an empty "restore" source commit.
    Assert ((Invoke-FixtureGit @('status','--porcelain','--untracked-files=all')) -ceq '') 'Final membership control must retain the committed reviewed pair.'
    $finalHead = Invoke-FixtureGit @('rev-parse','HEAD')
    # Revocation narrows to ordinary legacy semantics; old proof is not replayed.
    $revoked = $pairPins.Replace("    ReviewedRouteTransitions = @(" + $lf + "        @{ModId='alpha';FromSourceCommit='$fromCommit';CandidateModTree='$toTree';CandidateReceiptSha256='$receiptHash'}" + $lf + '    )','    ReviewedRouteTransitions = @()')
    Assert ($revoked -cne $pairPins) 'Revocation fixture did not remove the declaration.'
    Write-Fixture $pinPath $revoked
    $revokedHead = Commit-Fixture 'explicit protected-policy revocation fixture'
    $outcome = Run-Transition 'Revoked' $revokedHead (Get-TransitionManifest $revokedHead '0.1.4-dev' $revokedHead)
    Assert ($outcome.Run.Code -eq 0 -and $outcome.Run.Result.Changed -and $outcome.Run.Result.RequiresMetadataPR) 'Revocation replayed an earlier retained-pair proof.'
    Assert ($transitionControlsKilled -eq 4) 'Transition mutation-control census changed.'
    Write-Host "[current-pin-recovery] PASS #1777 reviewed-pair source/receipt/worker cases; controls killed=$transitionControlsKilled; cumulative assertions=$passed"

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
