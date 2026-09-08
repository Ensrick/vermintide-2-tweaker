# Offline fixtures of the actual broker/functions. No production claims/state.
[CmdletBinding()]
param([switch]$SelfTest, [string]$WorkerMode, [string]$FixtureRoot)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$claimScript = Join-Path $repo 'tools\ship\claim.ps1'
$tokens=$null; $errors=$null
$ast = [Management.Automation.Language.Parser]::ParseFile($claimScript,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Broker parse failed.' }
foreach ($fn in @($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false))) {
    . ([scriptblock]::Create($fn.Extent.Text))
}
. (Join-Path $repo 'tools\ship\claim-allocation.ps1')
$now = [datetime]::SpecifyKind([datetime]'2026-09-08T12:00:00',[DateTimeKind]::Utc)
$utf8 = New-Object Text.UTF8Encoding($false)
$review = 'https://github.com/Ensrick/vermintide-2-tweaker/issues/724'
$hostPath = (Get-Process -Id $PID).Path
$script:passed=0
function Assert([bool]$Value,[string]$Message) {
    if (-not $Value) { throw "[permanent-claims] $Message" }; $script:passed++
}
function Refuses([scriptblock]$Action,[string]$Message) {
    $threw=$false; try { & $Action | Out-Null } catch { $threw=$true }
    Assert $threw $Message
}
function New-Case([string]$Name,[string]$Version='0.2.177') {
    $dir=Join-Path $root $Name
    [IO.Directory]::CreateDirectory((Join-Path $dir 'fixture_mod\scripts\mods\fixture_mod')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $dir 'claims')) | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'fixture_mod\scripts\mods\fixture_mod\fixture_mod.lua'),('local MOD_VERSION = "'+$Version+'"'),$utf8)
    return $dir
}
function Init([string]$Dir,[string]$Floor='0.2.177',[string]$Hash='absent') {
    Initialize-PermanentAllocation (Join-Path $Dir 'claims') fixture_mod $Dir $Floor $Hash $review
}
function Op([string]$Dir,[string]$Operation='Acquire',[string]$Owner='fixture-owner',[datetime]$Time=$now,[string]$Version='0.2.178') {
    Invoke-PermanentClaim -Operation $Operation -ClaimsDir (Join-Path $Dir 'claims') -Mod fixture_mod -RepoRoot $Dir -Session $Owner -NowUtc $Time -ExpectedVersion $Version
}
function Plant([string]$Dir,[string]$Version,[datetime]$Time,[string]$Owner='old-owner') {
    $raw=Format-ClaimContent fixture_mod $Version $Owner $Time
    [IO.File]::WriteAllText((Join-Path $Dir 'claims\fixture_mod.claim'),$raw,$utf8)
    return Get-AllocationHash ([Text.Encoding]::UTF8.GetBytes($raw))
}
function State([string]$Dir) { Read-AllocationState (Join-Path $Dir 'claims\fixture_mod.allocation') fixture_mod }
function Start-Worker([string]$Mode,[string]$Dir,[string]$Prefix) {
    $p=Start-Process -FilePath $hostPath -ArgumentList @('-NoProfile','-NonInteractive','-File',('"'+$PSCommandPath+'"'),
        '-WorkerMode',$Mode,'-FixtureRoot',('"'+$Dir+'"')) -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput ($Prefix+'.out') -RedirectStandardError ($Prefix+'.err')
    $null=$p.Handle
    return $p
}
if ($WorkerMode) {
    if ([IO.Path]::GetFileName([IO.Path]::GetDirectoryName($FixtureRoot)) -cnotmatch '\Avt2-permanent-claims-[a-f0-9]{32}\z') { throw 'Worker requires owned fixture root.' }
    if ($WorkerMode -in @('CrashReserved','CrashRetired','OldWriterWins')) {
        $originalWriter=(Get-Command Write-AllocationState).ScriptBlock
        function Write-AllocationState {
            param([string]$Path,[AllowNull()][string]$ExpectedRaw,[string]$Raw)
            & $originalWriter @PSBoundParameters
            $hit=($WorkerMode -ceq 'CrashRetired' -and $Raw.Contains("status=released`n")) -or
                ($WorkerMode -cin @('CrashReserved','OldWriterWins') -and $Raw.Contains("status=active`n"))
            if ($hit) {
                [IO.File]::WriteAllText((Join-Path $FixtureRoot 'boundary.txt'),$WorkerMode,$utf8)
                if ($WorkerMode -ceq 'OldWriterWins') {
                    $null=Plant $FixtureRoot '0.2.178' $now 'old-racing-owner'
                } else { [Diagnostics.Process]::GetCurrentProcess().Kill() }
            }
        }
    }
    if ($WorkerMode -ceq 'OtherMutexDelete') {
        $p=Join-Path $FixtureRoot 'claims\fixture_mod.claim'
        $blocked=0
        try { [IO.File]::WriteAllText($p,'foreign replacement',$utf8) } catch [IO.IOException] { $blocked++ }
        try { [IO.File]::Delete($p) } catch [IO.IOException] { $blocked++ }
        if ($blocked -eq 2) { exit 0 }; exit 9
    }
    if ($WorkerMode -cin @('RaceA','RaceB')) {
        $r=Op $FixtureRoot Acquire $WorkerMode
        if ($r.Ok) { Write-Output $r.Version; exit 0 }; exit 1
    }
    try { $null=Op $FixtureRoot Acquire 'fresh-owner' $now.AddHours(26); exit 9 }
    catch { Write-Output $_.Exception.Message; exit 2 }
    finally { [IO.File]::WriteAllText((Join-Path $FixtureRoot 'worker-finally.txt'),'ran',$utf8) }
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('vt2-permanent-claims-'+[guid]::NewGuid().ToString('N'))
$workers=New-Object Collections.ArrayList
try {
    # Missing history is not auto-derived from source; explicit reviewed floor.
    $dir=New-Case basic
    Refuses { Op $dir } 'missing history refuses acquisition'
    Assert (-not [IO.File]::Exists((Join-Path $dir 'claims\fixture_mod.claim'))) 'missing history creates no claim'
    Refuses { Init $dir '0.2.176' } 'floor below source refused'
    Refuses { Init $dir '0.2.177' ('a'*64) } 'wrong reviewed absence refused'
    $null=Init $dir
    Refuses { Init $dir } 'initialization cannot reset existing floor'
    $r=Op $dir
    Assert ($r.Ok -and $r.Version -ceq '0.2.178') 'first reservation above source/floor'
    $claimPath=Join-Path $dir 'claims\fixture_mod.claim'
    $wire=[IO.File]::ReadAllText($claimPath)
    Assert ((Read-ClaimFile $claimPath).Version -ceq '0.2.178') 'legacy four-field reader still accepts exact claim'
    Assert ((Op $dir).Version -ceq '0.2.178' -and (State $dir).Floor -ceq '0.2.178') 'same owner live idempotence does not burn another'
    Assert (-not (Op $dir Acquire foreign).Ok) 'foreign live acquisition denied'
    Assert ((Op $dir Verify).State -ceq 'ok') 'exact binding owner/version verifies'
    Assert ((Op $dir Verify foreign).State -ceq 'owner_mismatch') 'foreign verification denied'
    Assert ((Op $dir Verify fixture-owner $now '0.2.179').State -ceq 'mismatch') 'wrong version denied'
    Assert (-not (Op $dir Release foreign).Ok) 'foreign release denied'
    Assert ([IO.File]::ReadAllText($claimPath) -ceq $wire) 'foreign actions preserve raw claim'
    Assert ((Op $dir Release).Removed -and (State $dir).Floor -ceq '0.2.178') 'normal release retains floor'
    Assert ((Op $dir Release).Ok) 'release is idempotent'
    Assert ((Op $dir Acquire new-owner).Version -ceq '0.2.179') 'release/reclaim cannot reuse abandoned number'

    $dir=New-Case stale
    $hash=Plant $dir '0.2.189' $now.AddHours(-25)
    $before=[IO.File]::ReadAllBytes((Join-Path $dir 'claims\fixture_mod.claim'))
    Refuses { Init $dir '0.2.188' $hash } 'floor below existing claim refused'
    $null=Init $dir '0.2.189' $hash
    Assert ((Get-AllocationHash ([IO.File]::ReadAllBytes((Join-Path $dir 'claims\fixture_mod.claim')))) -ceq (Get-AllocationHash $before)) 'stale adoption preserves exact bytes'
    Assert ((Op $dir Verify old-owner $now '0.2.189').State -ceq 'stale') 'adoption does not renew stale timestamp'
    $r=Op $dir Acquire replacement
    Assert ($r.BrokeStale -and $r.Version -ceq '0.2.190') 'stale higher reservation forces fresh higher version'

    $dir=New-Case suffix '1.3.9-beta'
    $null=Init $dir '1.4.19'
    Assert ((Op $dir).Version -ceq '1.4.20-beta') 'numeric floor beats source while source track is preserved'
    foreach ($bad in @('0.2.1.1','00.2.1',"0.2.1`n",'-1.2.3','1.0.2147483648')) {
        Refuses { Get-AllocationVersion $bad } "malformed/overflow version refused: $($bad.Trim())"
    }
    foreach ($bad in @('../other','Fixture_mod',"fixture_mod`n",'fixture_mod:stream')) {
        Refuses { Get-AllocationPaths (Join-Path $dir 'claims') $bad } 'invalid/alias mod identity refused'
    }
    $policyPath=Join-Path $dir 'private-policy.psd1'
    foreach ($bad in @("@{Schema=1;EnabledMods=`$null}","@{Schema=1;EnabledMods='fixture_mod'}",
        "@{Schema=1;EnabledMods=@('fixture_mod','fixture_mod')}","@{Schema='1';EnabledMods=@()}",
        "@{schema=1;EnabledMods=@()}","@{Schema=1;EnabledMods=@('Fixture_mod')}")) {
        [IO.File]::WriteAllText($policyPath,$bad,$utf8)
        Refuses { Get-AllocationPolicy $policyPath fixture_mod } 'malformed activation policy rejected'
    }
    $dir=New-Case corrupt
    $null=Init $dir
    $statePath=Join-Path $dir 'claims\fixture_mod.allocation'
    $valid=[IO.File]::ReadAllText($statePath)
    foreach ($bad in @('', 'partial', $valid.Replace('mod=fixture_mod','mod=foreign'),$valid.Replace('claim_sha256=-','claim_sha256='+('a'*64)),$valid.Replace('floor=0.2.177','floor=0.2.177-dev'),($valid+"extra`n"))) {
        [IO.File]::WriteAllText($statePath,$bad,$utf8)
        Refuses { Op $dir } ("corrupt state fails closed: " + $bad.Replace("`n",'|'))
        Assert ([IO.File]::ReadAllText($statePath) -ceq $bad) 'corrupt state is never repaired/reset implicitly'
    }
    [IO.File]::WriteAllText($statePath,$valid,$utf8)
    $null=Op $dir
    $null=Plant $dir '0.2.178' $now 'old-unbound-writer'
    foreach ($operation in @('Acquire','Verify','Release')) { Refuses { Op $dir $operation } "unbound old broker refused by $operation" }
    Assert ((Read-ClaimFile (Join-Path $dir 'claims\fixture_mod.claim')).Session -ceq 'old-unbound-writer') 'unbound foreign bytes preserved'

    # Real native handle excludes writers in a different mutex domain.
    $dir=New-Case native
    $null=Init $dir; $null=Op $dir
    $locked=Open-AllocationClaim (Join-Path $dir 'claims\fixture_mod.claim')
    try {
        $p=Start-Worker OtherMutexDelete $dir (Join-Path $dir 'contender'); [void]$workers.Add($p)
        Assert ($p.WaitForExit(20000)) 'old-domain native contender terminates within setup bound'
        Assert ($p.ExitCode -eq 0) 'held exact claim handle refuses cross-domain write and delete'
        Assert ($locked.Raw -ceq (State $dir).ClaimRaw) 'held native proof is exact ledger binding'
    } finally { $locked.Stream.Dispose() }
    $null=Op $dir Release
    Assert (-not [IO.File]::Exists((Join-Path $dir 'claims\fixture_mod.claim'))) 'native delete-on-close removes owned exact claim'

    foreach ($mode in @('CrashReserved','CrashRetired','OldWriterWins')) {
        $dir=New-Case $mode; $null=Init $dir
        if ($mode -ceq 'CrashRetired') { $null=Op $dir }
        $p=Start-Worker $mode $dir (Join-Path $dir 'worker'); [void]$workers.Add($p)
        Assert ($p.WaitForExit(20000)) "$mode process terminates within setup bound"
        Assert ([IO.File]::Exists((Join-Path $dir 'boundary.txt'))) "$mode reached actual durable-write boundary"
        Assert ((State $dir).Floor -ceq '0.2.178') "$mode cannot lose burned floor"
        if ($mode -ceq 'OldWriterWins') {
            Assert ($p.ExitCode -eq 2) 'old writer wins CREATE_NEW but cannot report success'
            Assert ([IO.File]::Exists((Join-Path $dir 'worker-finally.txt'))) 'ordinary refusal executes finally control'
            Refuses { Op $dir } 'old writer winner is unbound, never silently deleted'
        } else {
            Assert ($p.ExitCode -ne 0) "$mode is actual hard owner death, not normal return"
            Assert (-not [IO.File]::Exists((Join-Path $dir 'worker-finally.txt'))) "$mode skips finally through actual hard death"
            if ($mode -ceq 'CrashReserved') { Assert (-not [IO.File]::Exists((Join-Path $dir 'claims\fixture_mod.claim'))) 'reservation persisted before claim publication' }
            else { Assert ((State $dir).Status -ceq 'released') 'retired state persisted before claim deletion' }
            Assert ((Op $dir Acquire next-owner $now.AddHours(27)).Version -ceq '0.2.179') "$mode recovery burns old allocation and uses next"
        }
    }
    $dir=New-Case race; $null=Init $dir
    $a=Start-Worker RaceA $dir (Join-Path $dir 'a'); [void]$workers.Add($a)
    $b=Start-Worker RaceB $dir (Join-Path $dir 'b'); [void]$workers.Add($b)
    Assert ($a.WaitForExit(20000) -and $b.WaitForExit(20000)) 'two independent broker processes finish bounded'
    Assert (@($a.ExitCode,$b.ExitCode | Where-Object { $_ -eq 0 }).Count -eq 1) 'exactly one process owns reservation'
    Assert ((State $dir).Floor -ceq '0.2.178') 'contention does not duplicate or waste live reservation'

    $dir=New-Case partial; $null=Init $dir; $null=Op $dir
    $claimPath=Join-Path $dir 'claims\fixture_mod.claim'
    $statePath=Join-Path $dir 'claims\fixture_mod.allocation'
    $savedState=[IO.File]::ReadAllText($statePath)
    foreach ($partial in @('', '# partial claim', (Format-ClaimContent fixture_mod '0.2.178' "bad`nowner" $now))) {
        [IO.File]::WriteAllText($claimPath,$partial,$utf8)
        Refuses { Op $dir } 'partial/torn/malformed claim refuses automatic recovery'
        Assert ([IO.File]::ReadAllText($statePath) -ceq $savedState) 'partial claim does not lower or erase floor'
        Assert ([IO.File]::ReadAllText($claimPath) -ceq $partial) 'partial claim preserved for explicit reconciliation'
    }
    $dir=New-Case blockedstate; $null=Init $dir
    $statePath=Join-Path $dir 'claims\fixture_mod.allocation'
    $held=[IO.File]::Open($statePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        Refuses { Op $dir } 'failed atomic floor replacement refuses claim publication'
        Assert (-not [IO.File]::Exists((Join-Path $dir 'claims\fixture_mod.claim'))) 'failed floor commit never creates claim'
    } finally { $held.Dispose() }
    Assert ((State $dir).Floor -ceq '0.2.177') 'failed atomic replacement preserves previous complete floor'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $dir 'claims') -Filter '*.pending').Count -eq 0) 'normal failed write cleans only its pending file'
    # Uncommitted crash residue must never be interpreted as authoritative state.
    [IO.File]::WriteAllText(($statePath+'.orphan.pending'),'partial',$utf8)
    Assert ((Op $dir).Version -ceq '0.2.178') 'uncommitted orphan pending file cannot advance/reset authority'
    $dir=New-Case revoked; $null=Init $dir; $null=Op $dir
    $claimPath=Join-Path $dir 'claims\fixture_mod.claim'; $revoked=[IO.File]::ReadAllText($claimPath)
    $null=Op $dir Release
    [IO.File]::WriteAllText($claimPath,$revoked,$utf8)
    Refuses { Op $dir Verify } 'exact old claim replay after release cannot authorize shipment'
    Assert ((Op $dir Acquire new-owner).Version -ceq '0.2.179') 'exact retired residue is safely deleted without reusing allocation'
    $dir=New-Case foreignrecord; $null=Init $dir
    $foreignPath=Join-Path $dir 'claims\doomrocket.claim'
    [IO.File]::WriteAllText($foreignPath,'foreign project data',$utf8)
    $null=Op $dir; $null=Op $dir Release
    Assert ([IO.File]::ReadAllText($foreignPath) -ceq 'foreign project data') 'operations never sweep unrelated project claims'

    # Actual main dispatcher on private copies, including activation/lost-state
    # guard. No installed/shared policy is edited.
    $dir=New-Case cli
    $toolDir=Join-Path $dir 'tools\ship'; [IO.Directory]::CreateDirectory($toolDir) | Out-Null
    foreach ($name in @('claim.ps1','claim-allocation.ps1','claim-allocation-policy.psd1','build-output-normalization.ps1','bundle-authority.ps1')) {
        [IO.File]::Copy((Join-Path $repo ('tools\ship\'+$name)),(Join-Path $toolDir $name))
    }
    $privateCli=Join-Path $toolDir 'claim.ps1'; $claims=Join-Path $dir 'claims'
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -Session cli-owner -Quiet *>&1
    Assert ($LASTEXITCODE -eq 0) 'dormant dispatcher preserves ordinary legacy allocation'
    $raw=[IO.File]::ReadAllText((Join-Path $claims 'fixture_mod.claim'))
    $hash=Get-AllocationHash ([Text.Encoding]::UTF8.GetBytes($raw))
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -InitializeAllocation -ReviewedFloor '0.2.178' -ExpectedClaimSha256 $hash -ReviewReference $review *>&1
    Assert ($LASTEXITCODE -eq 0) 'actual explicit initializer adopts exact existing claim'
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -Session cli-owner -Verify -ExpectedVersion '0.2.178' -Quiet *>&1
    Assert ($LASTEXITCODE -eq 2) 'not-yet-activated checkout refuses initialized history'
    [IO.File]::WriteAllText((Join-Path $toolDir 'claim-allocation-policy.psd1'),"@{Schema=1;EnabledMods=@('fixture_mod')}",$utf8)
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -Session cli-owner -Verify -ExpectedVersion '0.2.178' -Quiet *>&1
    Assert ($LASTEXITCODE -eq 0) 'actual activated Verify accepts exact adopted live owner'
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -Session cli-owner -Release -Quiet *>&1
    Assert ($LASTEXITCODE -eq 0) 'actual activated release succeeds without removing floor'
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -Session cli-next -Quiet *>&1
    Assert ($LASTEXITCODE -eq 0 -and (Read-ClaimFile (Join-Path $claims 'fixture_mod.claim')).Version -ceq '0.2.179') 'actual activated dispatcher allocates above burned floor'
    [IO.File]::Move((Join-Path $claims 'fixture_mod.allocation'),(Join-Path $claims 'retained-for-proof'))
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -Session cli-next -Verify -ExpectedVersion '0.2.179' -Quiet *>&1
    Assert ($LASTEXITCODE -eq 2) 'lost active history cannot fall back to legacy Verify'
    $output=& $privateCli -Mod fixture_mod -RepoRoot $dir -ClaimsDir $claims -Session cli-next -Quiet *>&1
    Assert ($LASTEXITCODE -eq 2) 'lost active history cannot fall back to legacy Acquire'
    Assert ([IO.File]::ReadAllText((Join-Path $claims 'fixture_mod.claim')).Contains('0.2.179')) 'lost history preserves pending claim'
    Write-Host "[permanent-claims] PASS $script:passed assertions; $($PSVersionTable.PSVersion)."
}
finally {
    foreach ($p in $workers) { if (-not $p.HasExited) { $p.Kill(); $null=$p.WaitForExit(5000) }; $p.Dispose() }
    # Validate the whole private census first, then individual files/empty dirs.
    if ([IO.Directory]::Exists($root)) {
        $full=Assert-AllocationPath $root
        if ([IO.Path]::GetFileName($full) -cnotmatch '\Avt2-permanent-claims-[a-f0-9]{32}\z') { throw 'Unsafe fixture root.' }
        $entries=@(Get-ChildItem -LiteralPath $full -Recurse -Force)
        foreach ($entry in $entries) {
            if (-not $entry.FullName.StartsWith($full+'\',[StringComparison]::OrdinalIgnoreCase) -or
                ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe fixture descendant.' }
        }
        foreach ($entry in @($entries | Where-Object { -not $_.PSIsContainer })) { [IO.File]::Delete($entry.FullName) }
        foreach ($entry in @($entries | Where-Object PSIsContainer | Sort-Object { $_.FullName.Length } -Descending)) { [IO.Directory]::Delete($entry.FullName,$false) }
        [IO.Directory]::Delete($full,$false)
    }
}
exit 0
