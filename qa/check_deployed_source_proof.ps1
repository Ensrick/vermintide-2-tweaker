# Issue #1328: real immutable Git source and stubbed read-only HTTP boundaries.
[CmdletBinding()]
param([switch]$SelfTest,[switch]$Quiet)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'tools\verify\live_test_source_authority.ps1')
$root=Join-Path ([IO.Path]::GetTempPath()) ('vt2-deployed-proof-'+[guid]::NewGuid().ToString('N'))
$utf8=New-Object Text.UTF8Encoding($false)
$script:passed=0
function Assert([bool]$Condition,[string]$Name){
    if(-not $Condition){throw "[deployed-source-proof] $Name"}
    $script:passed++
}
function Reject([scriptblock]$Action,[string]$Pattern,[string]$Name){
    $failure=$null
    try{& $Action | Out-Null}catch{$failure=$_.Exception.Message}
    Assert ($null -ne $failure -and $failure -match $Pattern) "$Name (actual: $failure)"
}
function Copy-Value($Value){return ($Value | ConvertTo-Json -Depth 50 | ConvertFrom-Json)}
function Write-Fixture([string]$Relative,[string]$Text){
    $path=Join-Path $root $Relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path)) | Out-Null
    [IO.File]::WriteAllText($path,$Text,$utf8)
}
function Invoke-FixtureGit([string[]]$Arguments){
    $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try{
        $nativeGit=@(Get-Command git -CommandType Application -ErrorAction Stop)[0].Source
        $output=@(& $nativeGit -C $root @Arguments 2>&1 | ForEach-Object {$_.ToString()})
        $exitCode=$LASTEXITCODE
    }finally{$ErrorActionPreference=$previous}
    if($exitCode -ne 0){throw "Fixture git failed: $($output -join ' ')"}
    return ($output -join "`n").Trim()
}
function Commit-Fixture([string]$Name){
    $null=Invoke-FixtureGit @('add','--all')
    # These commits belong only to the isolated test repository, never the
    # project's checkout or hooks. No live remotes or publication are involved.
    $null=Invoke-FixtureGit @('-c','user.name=Source Proof Fixture','-c','user.email=fixture@example.invalid',
        '-c',('core.hooksPath='+(Join-Path $root 'absent-hooks')),'commit','--quiet','-m',$Name)
    return Invoke-FixtureGit @('rev-parse','HEAD')
}
function Proof($Row,$Legacy=@{},[string[]]$Required=@()){
    return Get-VtDeployedModSourceProof -RepoRoot $root -InventoryEntry $entry `
        -ManifestRow $Row -LegacyByKey $Legacy -RequiredRelativePaths $Required
}
$inventoryText=@'
@{ Mods=@(@{ Dir='fixture_mod'; ModId='WOC'; WorkshopId='1234567890'; Stream='single'; Public=$false; Visibility='friends_only' }) }
'@
$exceptionsText=@'
@{ LegacySourceTrees=@(); ReceiptFamilyOverrides=@(); ReceiptRouteOverrides=@(); ReceiptDiscoveryOverrides=@() }
'@
$body=@'
local MOD_VERSION = "1.2.3-dev"
local mod = get_mod("WOC")
-- local MOD_VERSION = "9.9.9-dev"
local bait = 'local MOD_VERSION = "8.8.8-dev"'
pcall(printf, "[WOC:LOAD] v%s enabled fp=fixture OK", MOD_VERSION)
mod:command("fx_probe", "Fixture", function()
    pcall(printf, "[WOC:probe] status=OK")
end)
'@
$originalReader=(Get-Item Function:Invoke-VtAuthorityGhRead).ScriptBlock
try{
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $null=Invoke-FixtureGit @('-c','init.templateDir=','init','--quiet')
    Write-Fixture 'tools/mod-inventory.psd1' $inventoryText
    Write-Fixture 'tools/verify/live_test_contract_exceptions.psd1' $exceptionsText
    Write-Fixture 'fixture_mod/scripts/mods/fixture_mod/fixture_mod.lua' $body
    Write-Fixture 'fixture_mod/scripts/mods/fixture_mod/anchor.lua' 'return { sentinel = 1328 }'
    $commit=Commit-Fixture 'immutable source'
    $rootTree=Invoke-FixtureGit @('rev-parse',"$commit^{tree}")
    $modTree=Invoke-FixtureGit @('rev-parse',"$commit`:fixture_mod/scripts/mods")
    $blob=Invoke-FixtureGit @('rev-parse',"$commit`:fixture_mod/scripts/mods/fixture_mod/fixture_mod.lua")
    $entry=(Import-PowerShellDataFile (Join-Path $root 'tools/mod-inventory.psd1')).Mods[0]
    $row=[pscustomobject]@{
        mod_id='WOC'; workshop_id='1234567890'; version='1.2.3-dev'; source_commit=$commit; source_state='clean'
        asset_filename='fixture.zip'; sha256=('a'*64); root_bundle='fixture.mod_bundle'
        bundle_files=@([pscustomobject]@{filename='fixture.mod_bundle';sha256=('b'*64)})
    }
    $manifest=[pscustomobject]@{manifest_schema=2;release_tag='mods-2026-09-06';mods=@($row)}
    $inputs=Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $manifest
    Assert ($inputs.InventoryById['WOC'].ModId -ceq 'WOC') 'Canonical uppercase identity was lost.'
    Invoke-VtDeploymentSourcePrefetch -RepoRoot $root -SourceInputs $inputs -ModIds @('WOC')
    $proof=Proof $row
    Assert ($proof.SourceCommit -ceq $commit -and $proof.RootTree -ceq $rootTree -and $proof.ModTree -ceq $modTree) 'Proof differs from independently resolved Git objects.'
    Assert ($proof.Version -ceq '1.2.3-dev' -and $proof.Treeish -ceq $commit -and $proof.WorkshopId -ceq '1234567890') 'Proof identity/version changed.'
    Assert (@($proof.Documents).Count -eq 1) 'Unrequested non-contract Lua was tokenized.'
    $withAnchor=Proof $row @{} @('fixture_mod/scripts/mods/fixture_mod/anchor.lua')
    Assert (@($withAnchor.Documents).Count -eq 2) 'Explicit immutable anchor path was lost.'
    Assert (@($withAnchor.Documents | Where-Object {$_.Content -ceq 'return { sentinel = 1328 }'}).Count -eq 1) 'Requested anchor bytes are not the committed bytes.'

    Write-Fixture 'fixture_mod/scripts/mods/fixture_mod/fixture_mod.lua' ($body.Replace('1.2.3-dev','7.7.7-dev'))
    Assert ((Proof $row).Version -ceq '1.2.3-dev') 'Working-tree replacement changed immutable authority.'
    $authority=Get-VtCardSourceAuthority -RepoRoot $root -DeploymentManifest $manifest
    Assert (@($authority.Records).Count -eq 1 -and $authority.Records[0].ModTree -ceq $modTree) 'Full authority did not consume the shared proof.'
    Assert (@($authority.Records[0].LoadRoutes.Marker) -contains '[WOC:LOAD]') 'Full authority lost its real LOAD route.'
    Assert (@($authority.Records[0].CommandRoutes.Command) -contains '/fx_probe') 'Full authority lost its actual command.'

    foreach($case in @(
        @{Name='case alias';Field='mod_id';Value='woc';Pattern='identity'},
        @{Name='foreign id';Field='mod_id';Value='foreign';Pattern='identity'},
        @{Name='Workshop mismatch';Field='workshop_id';Value='999';Pattern='Workshop identity'},
        @{Name='dirty source';Field='source_state';Value='dirty';Pattern='source_state'},
        @{Name='wrong version';Field='version';Value='1.2.4-dev';Pattern='MOD_VERSION drift'},
        @{Name='missing version';Field='version';Value='';Pattern='no version'},
        @{Name='short source';Field='source_commit';Value='123';Pattern='40-hex'},
        @{Name='nonexistent source';Field='source_commit';Value=('f'*40);Pattern='Source object|could not get object info'},
        @{Name='tree instead of commit';Field='source_commit';Value=$rootTree;Pattern='not a commit'},
        @{Name='blob instead of commit';Field='source_commit';Value=$blob;Pattern='not a commit'},
        @{Name='absent source';Field='source_commit';Value=$null;Pattern='no exact legacy'}
    )){
        $bad=Copy-Value $row; $bad.($case.Field)=$case.Value
        Reject {Proof $bad} $case.Pattern $case.Name
    }
    foreach($case in @(
        @{Name='manifest alias';Field='mod_id';Value='woc';Pattern='canonical case'},
        @{Name='manifest foreign';Field='mod_id';Value='foreign';Pattern='non-inventory'},
        @{Name='bad ZIP path';Field='asset_filename';Value='../fixture.zip';Pattern='ZIP basename'},
        @{Name='bad ZIP hash';Field='sha256';Value='bad';Pattern='ZIP sha256'},
        @{Name='bad bundle path';Field='root_bundle';Value='../fixture.mod_bundle';Pattern='mod_bundle basename'},
        @{Name='manifest dirty';Field='source_state';Value='dirty';Pattern='source_state'},
        @{Name='manifest short commit';Field='source_commit';Value='123';Pattern='40-hex'}
    )){
        $bad=Copy-Value $manifest; $bad.mods[0].($case.Field)=$case.Value
        Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} $case.Pattern $case.Name
    }
    $bad=Copy-Value $manifest; $bad.mods=@($bad.mods[0],$bad.mods[0])
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} 'duplicate mod_id' 'Duplicate manifest rows accepted.'
    $bad=Copy-Value $manifest; $bad.mods=@()
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} 'missing inventory mod' 'Missing deployed identity accepted.'
    $bad=Copy-Value $manifest; $bad.manifest_schema=1
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} 'schema 2' 'Legacy manifest schema accepted.'
    $bad=Copy-Value $manifest; $bad.release_tag=''
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} 'no release_tag' 'Absent release coordinate accepted.'
    $bad=Copy-Value $manifest; $bad | Add-Member _authority_release_tag 'mods-2026-09-05'
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} 'Release tag mismatch' 'Fetched tag mismatch accepted.'
    $bad=Copy-Value $manifest; $bad.mods[0].bundle_files=@()
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} 'exactly one bundle_files' 'Missing root row accepted.'
    $bad=Copy-Value $manifest; $bad.mods[0].bundle_files[0].sha256='bad'
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $bad} 'root bundle sha256' 'Bad root digest accepted.'
    Reject {Invoke-VtDeploymentSourcePrefetch -RepoRoot $root -SourceInputs $inputs -ModIds @('woc')} 'canonical ModIds' 'Prefetch accepted identity alias.'
    Reject {Invoke-VtDeploymentSourcePrefetch -RepoRoot $root -SourceInputs $inputs -ModIds @('WOC','WOC')} 'canonical ModIds' 'Prefetch accepted duplicates.'

    $legacyRow=Copy-Value $row; $legacyRow.source_commit=$null
    $legacy=@{ModId='WOC';Version='1.2.3-dev';RootTree=$rootTree;ModTree=$modTree;Reason='isolated historical fixture'}
    $legacyMap=@{}; $legacyMap["WOC`n1.2.3-dev"]=$legacy
    $legacyProof=Proof $legacyRow $legacyMap
    Assert ($null -eq $legacyProof.SourceCommit -and $legacyProof.Treeish -ceq $rootTree -and $legacyProof.ModTree -ceq $modTree) 'Legacy proof fabricated commit or changed exact root/tree.'
    foreach($case in @(
        @{Field='RootTree';Value=$commit;Pattern='not a tree'},
        @{Field='ModTree';Value=$blob;Pattern='exception drift'},
        @{Field='ModId';Value='woc';Pattern='exact identity'},
        @{Field='Version';Value='1.2.4-dev';Pattern='exact identity'}
    )){
        $badLegacy=@{}+$legacy; $badLegacy[$case.Field]=$case.Value
        $badMap=@{}; $badMap["WOC`n1.2.3-dev"]=$badLegacy
        Reject {Proof $legacyRow $badMap} $case.Pattern "Legacy $($case.Field) mismatch accepted."
    }
    $bad=Copy-Value $row; $bad.source_commit='bad'
    Reject {Proof $bad $legacyMap} '40-hex' 'Malformed nonempty source fell back to legacy.'
    Write-Fixture 'tools/verify/live_test_contract_exceptions.psd1' ("@{LegacySourceTrees=@(@{ModId='WOC';Version='1.2.3-dev';RootTree='$rootTree';ModTree='$modTree';Reason='fixture'});ReceiptFamilyOverrides=@();ReceiptRouteOverrides=@();ReceiptDiscoveryOverrides=@()}")
    $legacyManifest=Copy-Value $manifest; $legacyManifest.mods=@($legacyRow)
    $legacyInputs=Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $legacyManifest
    Assert ($legacyInputs.LegacyByKey.Count -eq 1) 'Exact legacy index was not preserved.'
    Assert ((Get-VtCardSourceAuthority -RepoRoot $root -DeploymentManifest $legacyManifest).Records[0].ModTree -ceq $modTree) 'Full authority legacy path changed.'
    Write-Fixture 'tools/verify/live_test_contract_exceptions.psd1' "@{LegacySourceTrees=@(@{ModId='WOC';Version='1.2.3-dev';RootTree='bad';ModTree='$modTree';Reason='fixture'})}"
    Reject {Get-VtDeploymentSourceInputs -RepoRoot $root -DeploymentManifest $legacyManifest} 'Malformed legacy' 'Malformed historical policy accepted.'
    Write-Fixture 'tools/verify/live_test_contract_exceptions.psd1' $exceptionsText

    Write-Fixture 'fixture_mod/scripts/mods/fixture_mod/fixture_mod.lua' $body
    Write-Fixture 'fixture_mod/scripts/mods/fixture_mod/conflict.lua' 'local MOD_VERSION = "9.9.9-dev"'
    $bad=Copy-Value $row; $bad.source_commit=Commit-Fixture 'conflicting literal version'
    Reject {Proof $bad} 'MOD_VERSION drift' 'Multiple source versions accepted.'
    [IO.File]::Delete((Join-Path $root 'fixture_mod/scripts/mods/fixture_mod/conflict.lua'))
    Write-Fixture 'fixture_mod/scripts/mods/fixture_mod/fixture_mod.lua' ($body.Replace('local MOD_VERSION = "1.2.3-dev"','local VERSION = "1.2.3-dev"'))
    $bad=Copy-Value $row; $bad.source_commit=Commit-Fixture 'phantom versions only'
    Reject {Proof $bad} 'MOD_VERSION drift' 'Comments/strings authorized a nonexistent source version.'
    $noLoad=$body.Replace('pcall(printf, "[WOC:LOAD] v%s enabled fp=fixture OK", MOD_VERSION)','-- no runtime load')
    Write-Fixture 'fixture_mod/scripts/mods/fixture_mod/fixture_mod.lua' $noLoad
    $bad=Copy-Value $row; $bad.source_commit=Commit-Fixture 'valid provenance without receipt policy'
    Assert ((Proof $bad).Version -ceq '1.2.3-dev') 'Pure provenance incorrectly depends on receipt policy.'
    $badManifest=Copy-Value $manifest; $badManifest.mods=@($bad)
    Reject {Get-VtCardSourceAuthority -RepoRoot $root -DeploymentManifest $badManifest} 'no literal runtime' 'Full authority lost its separate LOAD policy.'

    # Only this read boundary is replaced; production constructs every API
    # endpoint. A hostile download URL from release JSON is never followed.
    $script:httpCalls=New-Object 'System.Collections.Generic.List[string]'
    function Invoke-VtAuthorityGhRead {
        param([string[]]$Arguments,[string]$Description)
        $script:httpCalls.Add(($Arguments -join ' '))
        if($Arguments[1] -ceq 'repos/Ensrick/vermintide-2-tweaker/releases/latest'){return ($script:remoteRelease | ConvertTo-Json -Depth 30)}
        if($Arguments[1] -ceq 'repos/Ensrick/vermintide-2-tweaker/releases/assets/2'){return ($script:remoteManifest | ConvertTo-Json -Depth 30)}
        throw "Unexpected remote endpoint: $($Arguments -join ' ')"
    }
    $release=[pscustomobject]@{id=1;tag_name='mods-2026-09-06';draft=$false;assets=@([pscustomobject]@{name='manifest.json';id=2;url='https://invalid.example/never-follow'})}
    $script:remoteRelease=Copy-Value $release; $script:remoteManifest=Copy-Value $manifest
    $read=Get-VtCardDeploymentManifest
    Assert ($read._authority_release_tag -ceq $manifest.release_tag -and $script:httpCalls.Count -eq 2) 'Valid published manifest read failed.'
    Assert ($script:httpCalls[1] -ceq 'api repos/Ensrick/vermintide-2-tweaker/releases/assets/2 -H Accept: application/octet-stream') 'Asset URL rather than fixed repository route was trusted.'
    foreach($case in @(
        @{Field='id';Value=0;Pattern='numeric id'},@{Field='id';Value=-1;Pattern='numeric id'},
        @{Field='id';Value='1';Pattern='numeric id'},@{Field='id';Value=$null;Pattern='numeric id'},
        @{Field='id';Value=1.5;Pattern='numeric id'},
        @{Field='draft';Value=$true;Pattern='published'},@{Field='draft';Value='false';Pattern='published'},
        @{Field='draft';Value=$null;Pattern='published'},
        @{Field='tag_name';Value='MODS-2026-09-06';Pattern='exact mods'},
        @{Field='tag_name';Value='mods-2026-09-06-extra';Pattern='exact mods'}
    )){
        $script:remoteRelease=Copy-Value $release; $script:remoteRelease.($case.Field)=$case.Value; $script:httpCalls.Clear()
        Reject {Get-VtCardDeploymentManifest} $case.Pattern "Remote $($case.Field) guard failed."
        Assert ($script:httpCalls.Count -eq 1) 'Unproven release reached an asset request.'
    }
    foreach($case in @(
        @{Field='id';Value=0;Pattern='numeric id'},@{Field='id';Value='../3';Pattern='numeric id'},
        @{Field='id';Value='2';Pattern='numeric id'},@{Field='name';Value='Manifest.json';Pattern='case-exact'}
    )){
        $script:remoteRelease=Copy-Value $release; $script:remoteRelease.assets[0].($case.Field)=$case.Value; $script:httpCalls.Clear()
        Reject {Get-VtCardDeploymentManifest} $case.Pattern "Remote asset $($case.Field) guard failed."
        Assert ($script:httpCalls.Count -eq 1) 'Unproven asset identity reached an asset request.'
    }
    foreach($alias in @('manifest.json','Manifest.json')){
        $script:remoteRelease=Copy-Value $release
        $script:remoteRelease.assets+= [pscustomobject]@{name=$alias;id=3}; $script:httpCalls.Clear()
        Reject {Get-VtCardDeploymentManifest} 'case-exact' 'Duplicate/aliased manifest accepted.'
        Assert ($script:httpCalls.Count -eq 1) 'Ambiguous assets reached download.'
    }
    $script:remoteRelease=Copy-Value $release; $script:remoteManifest=Copy-Value $manifest
    $script:remoteManifest.release_tag='mods-2026-09-05'
    Reject {Get-VtCardDeploymentManifest} 'Release tag mismatch' 'Downloaded tag mismatch accepted.'
    $script:httpCalls.Clear()
    Write-Fixture 'fixture-manifest.json' ($manifest | ConvertTo-Json -Depth 30)
    $fixtureRead=Get-VtCardDeploymentManifest -ManifestJsonPath (Join-Path $root 'fixture-manifest.json')
    Assert ($fixtureRead.release_tag -ceq $manifest.release_tag -and $script:httpCalls.Count -eq 0) 'Offline manifest fixture path changed.'
    Reject {Remove-VtSourceProofTemporaryDirectory -Path $root -ExpectedParent (Join-Path $root 'wrong') -NamePrefix 'vt2-deployed-proof-'} 'expected isolated' 'Cleanup accepted a foreign root.'
    Assert ([IO.File]::Exists((Join-Path $root 'fixture-manifest.json'))) 'Rejected cleanup deleted fixture bytes.'
    Write-Host "[deployed-source-proof] $script:passed assertions PASS"
}
catch{
    Write-Host "[deployed-source-proof] FAIL: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally{
    Set-Item Function:Invoke-VtAuthorityGhRead -Value $originalReader
    Remove-VtSourceProofTemporaryDirectory -Path $root -ExpectedParent ([IO.Path]::GetTempPath()) -NamePrefix 'vt2-deployed-proof-'
}
# In-process QA dispatch must observe this check's result, not a prior native
# Git status or a future reordered negative fixture (#1550).
exit 0
