param([switch]$SelfTest, [switch]$Quiet)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'tools/ship/local-deployment-receipt.ps1')
$script:Count = 0
function Check([bool]$Value, [string]$Name) {
    if (-not $Value) { throw "Local deployment check failed: $Name" }
    $script:Count++
}
$shipPath = Join-Path $repo 'tools/ship/ship.ps1'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($shipPath,[ref]$tokens,[ref]$parseErrors)
Check (@($parseErrors).Count -eq 0) 'ship parses'
$policy=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-ShipDeploymentPolicy'},$true)
. ([scriptblock]::Create($policy.Extent.Text))
$tracked=Get-ShipDeploymentPolicy -PublishedId '123' -DeployDirectoryExists $true -BundleAuthority tracked
Check ($tracked.ShouldDeploy -and $tracked.Mode -ceq 'subscribed') 'tracked subscription unchanged'
$local=Get-ShipDeploymentPolicy -PublishedId '123' -DeployDirectoryExists $true -BundleAuthority receipt -NoRemote
Check ($local.ShouldDeploy -and $local.RequiresDeploymentReceipt -and -not $local.RemoteDeploy) 'receipt local-only deployment'
$missing=Get-ShipDeploymentPolicy -PublishedId '123' -DeployDirectoryExists $false -BundleAuthority receipt
Check (-not $missing.ShouldDeploy -and $missing.Mode -ceq 'publication-only') 'missing subscription stays publication-only'
$build=Get-ShipDeploymentPolicy -PublishedId '123' -DeployDirectoryExists $true -BundleAuthority receipt -BuildOnly
Check (-not $build.ShouldDeploy -and $build.Mode -ceq 'publication-only') 'BuildOnly never requires deployment receipt'
$denied=$false
try { $null=Get-ShipDeploymentPolicy -PublishedId '123' -DeployDirectoryExists $true -BundleAuthority receipt } catch { $denied=$true }
Check $denied 'receipt remote deployment denied'
$ship=[IO.File]::ReadAllText($shipPath)
Check ($ship.Contains("'--deployment-receipt'") -and $ship.Contains('Assert-VtReceiptLocalDeploymentOutput')) 'real ship calls receipt and exact-set boundaries'
$capabilities=@('capability_schema=1','version=0.6.2','publication_receipt_schema=3','deployment_receipt_schema=3',
    'capabilities=hosted-publication-receipt-v3,locked-upload-snapshot-v1,git-commit-blob-snapshot-v1,constrained-first-upload-bootstrap-v1,machine-transaction-lease-v1,crash-safe-upload-acl-journal-v1,receipt-authority-publication-v1,receipt-authority-local-deploy-v1')
Check (Test-VmbLauncherPublicationCapabilityOutput -Lines $capabilities -RequireReceiptAuthority -RequireLocalDeployment).Ok 'local deployment capability requires full receipt protocol'
$old=@($capabilities | ForEach-Object { $_.Replace('version=0.6.2','version=0.6.1') })
Check (-not (Test-VmbLauncherPublicationCapabilityOutput -Lines $old -RequireLocalDeployment).Ok) '0.6.1 cannot authorize local receipt deployment'
Check (Test-VmbLauncherPublicationCapabilityOutput -Lines $old).Ok 'existing tracked publication capability remains 0.6.1 compatible'
Check (-not (Test-VmbLauncherPublicationCapabilityOutput -Lines @($capabilities | Where-Object { $_ -notlike 'deployment_receipt_schema=*' }) -RequireLocalDeployment).Ok) 'missing deployment schema refused'
Check (-not (Test-VmbLauncherPublicationCapabilityOutput -Lines @($capabilities | ForEach-Object { $_.Replace(',receipt-authority-local-deploy-v1','') }) -RequireLocalDeployment).Ok) 'missing deployment capability refused'
$downstream=Get-VtBundleAuthorityDownstreamPolicy -Entry @{Dir='modx';BundleAuthority='receipt';RootBundle='aaaaaaaaaaaaaaaa.mod_bundle'}
Check ($downstream.ReceiptLocalDeploy -and -not $downstream.Deploy -and -not $downstream.Update -and -not $downstream.Recover) 'separate local capability does not broaden legacy consumers'

# Execute the actual installed deployment statement; only external boundaries
# are stubbed, with no real launcher or HTTP. Preserve tracked argv verbatim.
$deployNode=@($ast.FindAll({param($n)
    $n -is [Management.Automation.Language.IfStatementAst] -and
    $n.Clauses[0].Item1.Extent.Text -ceq '$deploymentPolicy.ShouldDeploy' -and
    $n.Clauses[0].Item2.Extent.Text.Contains('New-VtHostedLocalDeploymentReceipt')
},$true))
Check ($deployNode.Count -eq 1) 'one canonical deployment statement'
$deployProgram=[scriptblock]::Create($deployNode[0].Extent.Text)
foreach ($mode in @('Tracked','Local','HostFailure','LauncherFailure','Missing')) {
    & {
        param($Case,$Program)
        $deploymentPolicy=if ($Case -ceq 'Tracked') { $tracked } elseif ($Case -ceq 'Missing') { $missing } else { $local }
        $NoRemote=$Case -cne 'Tracked'; $Mod='modx'; $launcherSettings='private-config'; $repoRoot=$repo
        $modVersion='1.2.3-dev'; $sourceCommit='a'*40; $publishedId='123'; $buildBuilderVersion='0.6.2+fixture'
        $transactionLease=@{}; $vmbRcResolution=@{}; $launcherExecutableLease=@{}
        $script:BoundaryCalls=0; $script:HostCalls=0; $script:BoundaryArgs=@(); $script:BoundaryPath=$null
        function New-VtHostedLocalDeploymentReceipt {
            $script:HostCalls++
            if ($Case -ceq 'HostFailure') { throw 'original hosting failure' }
            return @{Bytes=[Text.Encoding]::UTF8.GetBytes('offline receipt');Snapshot=@{}}
        }
        function Invoke-WithShipVmbRc { param($RepoRoot,$Resolution,$Action) & $Action }
        function Invoke-ShipLauncherNoWindow {
            param($LauncherExecutableLease,$ArgumentList,[switch]$ReplayOutput)
            $script:BoundaryCalls++; $script:BoundaryArgs=@($ArgumentList)
            if ($Case -cne 'Tracked') {
                $script:BoundaryPath=$ArgumentList[-1]
                Check ([IO.File]::ReadAllText($script:BoundaryPath) -ceq 'offline receipt') 'actual private receipt exists during launcher handoff'
            }
            return @{ExitCode=$(if ($Case -ceq 'LauncherFailure') { 7 } else { 0 })}
        }
        function Fail([string]$Message) { throw $Message }
        $failure=$null
        try { & $Program 6>$null } catch { $failure=$_.Exception.Message }
        if ($Case -ceq 'HostFailure') {
            Check ($failure -ceq 'original hosting failure' -and $script:BoundaryCalls -eq 0) 'hosting failure prevents launcher and retains original error'
        } elseif ($Case -ceq 'Missing') {
            Check ($null -eq $failure -and $script:BoundaryCalls -eq 0 -and $script:HostCalls -eq 0) 'missing subscription invokes neither host nor launcher'
        } elseif ($Case -ceq 'Tracked') {
            Check ($null -eq $failure -and $script:BoundaryCalls -eq 1 -and $script:HostCalls -eq 0) 'tracked deploy does not acquire receipt authority'
            Check (($script:BoundaryArgs -join '|') -ceq 'deploy|modx|--config|private-config') 'tracked argv unchanged'
        } else {
            Check ($script:BoundaryCalls -eq 1 -and $script:HostCalls -eq 1) 'one local receipt and one canonical launcher call'
            Check (($script:BoundaryArgs[0..5] -join '|') -ceq 'deploy|modx|--no-remote|--config|private-config|--deployment-receipt') 'local-only deployment receives separate receipt flag'
            Check (-not [IO.File]::Exists($script:BoundaryPath)) 'actual finally removes receipt after success or failure'
            Check (($Case -ceq 'Local' -and $null -eq $failure) -or ($Case -ceq 'LauncherFailure' -and $failure -match 'exited 7')) 'original launcher status preserved'
        }
    } $mode $deployProgram
}

$helperSource=[IO.File]::ReadAllText((Join-Path $repo 'tools/ship/local-deployment-receipt.ps1'))
$helperAst=[Management.Automation.Language.Parser]::ParseInput($helperSource,[ref]$tokens,[ref]$parseErrors)
Check (@($parseErrors).Count -eq 0) 'local receipt helper parses'
$ownerFinally=@($helperAst.FindAll({param($n)
    $n -is [Management.Automation.Language.TryStatementAst] -and $null -ne $n.Finally -and
    $n.Finally.Extent.Text.Contains('$mutex.ReleaseMutex()')
},$true))
Check ($ownerFinally.Count -eq 1) 'one production release cleanup owner'
$finallyText=$ownerFinally[0].Finally.Extent.Text
$finallyProgram=[scriptblock]::Create($finallyText.Substring(1,$finallyText.Length-2))
foreach ($mode in @('Success','CleanupFailure','PrimaryFailure','WarningObserverFailure')) {
    & {
        param($Case,$Program)
        $script:Disposed=$false; $script:ReleaseAttempted=$false
        $mutex=[pscustomobject]@{Fail=($Case -cne 'Success')}
        $mutex | Add-Member ScriptMethod ReleaseMutex { $script:ReleaseAttempted=$true; if ($this.Fail) { throw 'fixture release failure' } }
        $mutex | Add-Member ScriptMethod Dispose { $script:Disposed=$true }
        $primaryFailure=if ($Case -in @('PrimaryFailure','WarningObserverFailure')) { [Exception]::new('original error') } else { $null }
        $WarningPreference='Stop'
        if ($Case -ceq 'WarningObserverFailure') { function Write-Warning { throw 'observer failure' } }
        $failure=$null
        try { & $Program 3>$null } catch { $failure=$_.Exception.Message }
        Check ($script:ReleaseAttempted -and $script:Disposed) "$Case always releases and disposes"
        if ($Case -ceq 'CleanupFailure') { Check ($failure -match 'fixture release failure') 'failed cleanup blocks otherwise-successful handoff' }
        else { Check ($null -eq $failure) "$Case cleanup cannot replace primary error, including WarningPreference Stop" }
    } $mode $finallyProgram
}

if (-not $SelfTest) { Write-Host "PASS: local deployment source checks ($script:Count assertions)."; exit 0 }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('vt2-local-deployment-' + [guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($fixture)
$process=$null
try {
    $stdout=Join-Path $fixture 'stdout.txt'; $stderr=Join-Path $fixture 'stderr.txt'
    $hostPath=(Get-Process -Id $PID).Path
    $worker=Join-Path $PSScriptRoot '_test_fixtures/local_deployment_receipt_worker.ps1'
    $args=@('-NoProfile','-File',$worker,'-SourceRoot',$repo,'-FixtureRoot',$fixture)
    $quoted=@($args | ForEach-Object { ConvertTo-PublicationNativeArgument -Value $_ }) -join ' '
    $process=Start-Process -FilePath $hostPath -ArgumentList $quoted -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Retain the handle before exit, as in the existing native fixture owner;
    # otherwise PS5 may return a null ExitCode despite successful completion.
    $null=$process.Handle
    Check ($process.WaitForExit(180000)) 'isolated worker completes within three-minute setup ceiling'
    $out=[IO.File]::ReadAllText($stdout); $err=[IO.File]::ReadAllText($stderr)
    Check ($process.ExitCode -eq 0) "worker exit $($process.ExitCode): $out $err"
    Check ($out -match 'LOCAL_DEPLOYMENT_ASSERTIONS=([0-9]+)') 'worker assertion count reported'
    $workerCount=[int]$matches[1]
    Check (-not [IO.File]::Exists((Join-Path $fixture 'owner.json'))) 'private lease record cleaned'
    Write-Host "PASS: local deployment receipt ($script:Count source/parent + $workerCount isolated assertions)."
}
finally {
    if ($null -ne $process) {
        if (-not $process.HasExited) { $process.Kill(); $null=$process.WaitForExit(5000) }
        $process.Dispose()
    }
    # Census first; never follow a junction or recursively delete a path.
    $full=[IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetFileName($full) -cnotmatch '\Avt2-local-deployment-[0-9a-f]{32}\z') { throw 'Unsafe fixture cleanup root.' }
    $ancestor=[IO.DirectoryInfo]::new($full)
    while ($null -ne $ancestor) {
        if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse fixture cleanup ancestry.' }
        $ancestor=$ancestor.Parent
    }
    $dirs=[Collections.Generic.List[string]]::new(); $files=[Collections.Generic.List[string]]::new()
    $dirs.Add($full)
    for ($i=0; $i -lt $dirs.Count; $i++) {
        foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($dirs[$i])) {
            $path=[IO.Path]::GetFullPath($entry)
            if (-not $path.StartsWith($full + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Escaped fixture cleanup path.' }
            $attributes=[IO.File]::GetAttributes($path)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse fixture cleanup descendant.' }
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $dirs.Add($path) } else { $files.Add($path) }
        }
    }
    foreach ($file in $files) { [IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal); [IO.File]::Delete($file) }
    for ($i=$dirs.Count-1; $i -ge 0; $i--) { [IO.Directory]::Delete($dirs[$i],$false) }
}
