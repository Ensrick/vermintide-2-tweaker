param([Parameter(Mandatory)][string]$SourceRoot, [Parameter(Mandatory)][string]$FixtureRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $SourceRoot 'tools/ship/local-deployment-receipt.ps1')
. (Join-Path $SourceRoot 'tools/ship/transaction-lease.ps1')
$script:Count = 0
function Check([bool]$Value, [string]$Name) {
    if (-not $Value) { throw "Local deployment fixture failed: $Name" }
    $script:Count++
}
function Reject([scriptblock]$Action, [string]$Name, [string]$Pattern = '.') {
    $failure = $null
    try { $null = & $Action } catch { $failure = $_.Exception.Message }
    Check ($null -ne $failure -and $failure -match $Pattern) "$Name [$failure]"
}
function Text-File([string]$Path, [string]$Text) {
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
$root = Join-Path $FixtureRoot 'repo'
$target = Join-Path $FixtureRoot 'workshop/123'
$bundle = Join-Path $root 'modx/bundleV2'
$rootBundle = 'aaaaaaaaaaaaaaaa.mod_bundle'
$sideBundle = 'bbbbbbbbbbbbbbbb.mod_bundle'
$builder = '0.6.2+fixture'
$inventory = "@{ Mods = @(@{ Dir='modx'; ModId='modx'; Name='Mod X'; WorkshopId='123'; BundleAuthority='receipt'; RootBundle='$rootBundle'; BuildArtifactExclusions=@() }) }"
Text-File (Join-Path $root '.gitignore') "/modx/bundleV2/`n"
Text-File (Join-Path $root '.gitattributes') "* -text`n"
Text-File (Join-Path $root 'tools/mod-inventory.psd1') $inventory
Text-File (Join-Path $root 'modx/itemV2.cfg') "published_id = 123L;`nvisibility = `"private`";`npreview = `"preview.png`";`n"
Text-File (Join-Path $root 'modx/preview.png') 'not an executable'
Text-File (Join-Path $root 'modx/modx.mod') "descriptor`n"
Text-File (Join-Path $root 'modx/scripts/mods/modx/modx.lua') 'local MOD_VERSION = "1.2.3-dev"'
Text-File (Join-Path $bundle 'modx.mod') "descriptor`n"
Text-File (Join-Path $bundle $rootBundle) 'root bytes'
Text-File (Join-Path $bundle $sideBundle) 'side bytes'
function Git-Fixture([string[]]$Arguments) { return @(Invoke-VtBuildGitCapture -RepoRoot $root -Arguments $Arguments) }
$null = Git-Fixture @('init','--quiet')
$null = Git-Fixture @('config','user.name','Local Deployment Fixture')
$null = Git-Fixture @('config','user.email','fixture@example.invalid')
$null = Git-Fixture @('add','--','.')
$null = Git-Fixture @('commit','--quiet','-m','source')
$source = [string](Git-Fixture @('rev-parse','HEAD'))[0]
$map = Get-VtBuildCommitSourceMap -RepoRoot $root -Mod modx -Commit $source
$output = Get-VtBundleOutputSet -BundleDirectory $bundle -ExpectedDescriptorName modx.mod -ExpectedRootBundle $rootBundle
$policy = New-BuildOutputNormalizationPolicyProof -ModEntry @{Dir='modx';BundleAuthority='receipt';RootBundle=$rootBundle;BuildArtifactExclusions=@()}
$buildReceipt = New-VtBuildReceipt -Mod modx -SourceMap $map -OutputSet $output -BuilderVersion $builder -NormalizationPolicy $policy
Text-File (Join-Path $root 'modx/.build-receipt.json') (ConvertTo-VtBuildReceiptJson -Receipt $buildReceipt)
$null = Git-Fixture @('add','--','modx/.build-receipt.json')
$null = Git-Fixture @('commit','--quiet','-m','receipt')
$source = [string](Git-Fixture @('rev-parse','HEAD'))[0]
$snapshot = Get-VtPublicationSnapshot -RepoRoot $root -SourceCommit $source -Mod modx -ExpectedBuilderVersion $builder
$script:Authorization = @{ Ok=$true; Evidence=@{ mode='hosted_qa'; source_commit=$source }; Message='offline fixture' }
function Get-LivePublicationAuthorization { param($Repo,$SourceCommit) return $script:Authorization }

# Only this isolated child receives private claim/config state. No installed
# settings, global claim, production mutex, or launcher is used.
$env:APPDATA = Join-Path $FixtureRoot 'appdata'
$env:VT2_SHIP_SESSION_ID = 'local-deployment-offline'
$claim = Join-Path $env:APPDATA 'VMBLauncher/ship_claims/modx.claim'
$claimText = "mod = modx`nversion = 1.2.3-dev`nsession = explicit:local-deployment-offline`ncreated = $([datetime]::UtcNow.ToString('o'))`n"
Text-File $claim $claimText
$realReleaseLock = (Get-Command Enter-VtGitHubReleaseMutationMutex).ScriptBlock
$releaseMutexName = 'Local\VT2.LocalDeploy.Release.' + [guid]::NewGuid().ToString('N')
Add-Type -TypeDefinition @'
using System;
using System.Threading;
public static class LocalDeploymentMutexProbe {
    public static bool Available(string name) {
        bool available = false;
        Exception failure = null;
        var thread = new Thread(() => {
            try { using (var mutex = new Mutex(false, name)) {
                available = mutex.WaitOne(0);
                if (available) mutex.ReleaseMutex();
            } } catch (Exception e) { failure = e; }
        });
        thread.IsBackground = true;
        thread.Start();
        if (!thread.Join(5000)) throw new TimeoutException("Fixture mutex probe exceeded its bound.");
        if (failure != null) throw failure;
        return available;
    }
}
'@
function Enter-VtGitHubReleaseMutationMutex { return & $realReleaseLock -MutexName $releaseMutexName }
$lease = Enter-VmbMachineTransactionLease -Action ship -Mod modx -ProjectRoot $root `
    -MutexName ('Local\VT2.LocalDeploy.Owner.' + [guid]::NewGuid().ToString('N')) -RecordPath (Join-Path $FixtureRoot 'owner.json') -TimeoutMilliseconds 5000

function Clone-Object($Value) { return ($Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json) }
$receiptArgs = @{ RepoRoot=$root; Repository='Ensrick/vermintide-2-tweaker'; ReleaseTag='mods-2026-09-06';
    ReceiptAssetName='deployment-receipt-modx.json'; Mod='modx'; Version='1.2.3-dev'; Owner='explicit:local-deployment-offline';
    SourceCommit=$source; PublicationSnapshot=$snapshot; AuthorizationEvidence=$script:Authorization.Evidence; LocalDeployment=$true }
$hostArgs = @{ RepoRoot=$root; Mod='modx'; Version='1.2.3-dev'; SourceCommit=$source; PublishedId='123'; ExpectedBuilderVersion=$builder; TransactionLease=$lease }
$script:Mode = 'Success'
$script:Writes = [Collections.Generic.List[string]]::new()
$script:ServerBytes = [byte[]]::new(0)
function Response($Value) { return @{StatusCode=200; Content=($Value | ConvertTo-Json -Depth 20 -Compress)} }
$request = {
    param($Method,$Uri,$InputBytes,$ContentType,$Accept,$ExpectedResponseBytes)
    Check (-not [LocalDeploymentMutexProbe]::Available($releaseMutexName)) 'release mutex held throughout hosted transaction'
    $assetName = 'deployment-receipt-modx.json'
    $release = @{id=17;tag_name='mods-2026-09-06';draft=$false;prerelease=$false;assets=@(@{id=77;name='manifest.json';size=42})}
    if ($script:Mode -in @('Existing','DeleteFailure')) { $release.assets += @{id=11;name=$assetName;size=2} }
    if ($Method -eq 'GET' -and $Uri.EndsWith('/releases/latest')) {
        switch ($script:Mode) {
            'NoRelease' { return @{StatusCode=404} }
            'Draft' { $release.draft=$true }
            'MissingDraft' { $release.Remove('draft') }
            'StringDraft' { $release.draft='false' }
            'Prerelease' { $release.prerelease=$true }
            'ZeroId' { $release.id=0 }
            'StringId' { $release.id='17' }
            'WrongTag' { $release.tag_name='other-2026-09-06' }
            'Duplicate' { $release.assets += @(@{id=11;name=$assetName;size=2},@{id=12;name=$assetName;size=2}) }
            'CaseAlias' { $release.assets += @{id=11;name='Deployment-receipt-modx.json';size=2} }
        }
        return Response $release
    }
    if ($Method -eq 'DELETE') {
        Check ($Uri -ceq 'https://api.github.com/repos/Ensrick/vermintide-2-tweaker/releases/assets/11') 'only previous deployment receipt can be deleted'
        $script:Writes.Add($Method)
        return @{StatusCode=$(if ($script:Mode -eq 'DeleteFailure') { 500 } else { 204 })}
    }
    if ($Method -eq 'POST') {
        Check ($Uri -ceq 'https://uploads.github.com/repos/Ensrick/vermintide-2-tweaker/releases/17/assets?name=deployment-receipt-modx.json') 'only deployment receipt can be uploaded; no manifest/release creation'
        $script:Writes.Add($Method)
        $script:ServerBytes = [byte[]]$InputBytes.Clone()
        return @{StatusCode=$(if ($script:Mode -eq 'UploadFailure') { 500 } else { 201 })}
    }
    if ($Method -eq 'GET' -and $Uri.Contains('/releases/tags/')) {
        if ($script:Mode -eq 'ReadbackUnavailable') { return @{StatusCode=503} }
        $release.assets = @(@{id=77;name='manifest.json';size=42},@{id=12;name=$assetName;size=$script:ServerBytes.Length;url='https://foreign.invalid/releases/assets/12'})
        if ($script:Mode -eq 'ReadbackMissing') { $release.assets = @() }
        if ($script:Mode -eq 'ReadbackId') { $release.id=18 }
        if ($script:Mode -eq 'ReadbackTag') { $release.tag_name='mods-2026-09-05' }
        return Response $release
    }
    if ($Method -eq 'GET' -and $Uri -ceq 'https://api.github.com/repos/Ensrick/vermintide-2-tweaker/releases/assets/12') {
        $result = [byte[]]$script:ServerBytes.Clone()
        if ($script:Mode -eq 'BytesMismatch') { $result[0] = 33 }
        return @{StatusCode=200;Bytes=$result}
    }
    throw "Unexpected offline request: $Method $Uri"
}
try {
    $receipt = New-WorkshopPublicationReceipt @receiptArgs
    Check ($receipt.purpose -ceq 'local_deploy' -and $receipt.receipt_asset_name -ceq 'deployment-receipt-modx.json') 'exact local purpose/asset'
    Check ($receipt.bundle_authority -ceq 'receipt' -and $receipt.bundle_authority_proof.builder_version -ceq $builder) 'exact committed schema3 builder proof'
    foreach ($change in @(
        @{Key='ReceiptAssetName';Value='publication-receipt-modx.json'},
        @{Key='ReceiptAssetName';Value='deployment-receipt-other.json'},
        @{Key='Mod';Value='Modx'}, @{Key='ReleaseTag';Value='v0.6.2'}, @{Key='Repository';Value='other/repo'}
    )) {
        $bad = $receiptArgs.Clone(); $bad[$change.Key]=$change.Value
        Reject { New-WorkshopPublicationReceipt @bad } "constructor wrong $($change.Key)"
    }
    foreach ($badId in @('0','01',"123`n",'18446744073709551616')) {
        $bad = $receiptArgs.Clone(); $bad.PublicationSnapshot = Clone-Object $snapshot; $bad.PublicationSnapshot.PublishedId = $badId
        Reject { New-WorkshopPublicationReceipt @bad } "constructor bad Workshop ID $badId"
    }
    Reject { Get-VtPublicationSnapshot -RepoRoot $root -SourceCommit $source -Mod modx -ExpectedBuilderVersion '0.6.1+fixture' } 'different executing builder cannot reinterpret existing receipt'
    foreach ($mode in @('Success','Existing','NoRelease','Draft','MissingDraft','StringDraft','Prerelease','ZeroId','StringId','WrongTag','Duplicate','CaseAlias','DeleteFailure','UploadFailure','ReadbackUnavailable','ReadbackMissing','ReadbackId','ReadbackTag','BytesMismatch')) {
        $script:Mode=$mode; $script:Writes.Clear()
        if ($mode -in @('Success','Existing')) {
            $hosted = New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request
            Check ([Convert]::ToBase64String($hosted.Bytes) -ceq [Convert]::ToBase64String($script:ServerBytes)) "$mode exact independent readback"
            Check ($hosted.Snapshot.OutputSet.Fingerprint -ceq $snapshot.OutputSet.Fingerprint) "$mode retains committed output identity"
            $handoff = Write-VtLocalDeploymentReceiptHandoff -Bytes $hosted.Bytes
            try { Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($handoff)) -ceq [Convert]::ToBase64String($hosted.Bytes)) 'private handoff exact bytes' }
            finally { [IO.File]::Delete($handoff) }
        }
        else { Reject { New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request } "hosting $mode" }
        if ($mode -in @('NoRelease','Draft','MissingDraft','StringDraft','Prerelease','ZeroId','StringId','WrongTag','Duplicate','CaseAlias')) {
            Check ($script:Writes.Count -eq 0) "$mode refuses before mutation"
        }
        Check ([LocalDeploymentMutexProbe]::Available($releaseMutexName)) "$mode release mutex is released on an independent thread"
    }
    $script:Mode='Success'; $script:Writes.Clear()
    $script:Authorization.Ok=$false
    Reject { New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request } 'failed live authorization' 'live authorization'
    Check ($script:Writes.Count -eq 0) 'failed live authorization performs no writes'
    $script:Authorization.Ok=$true
    Text-File $claim ($claimText.Replace('1.2.3-dev','1.2.4-dev'))
    Reject { New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request } 'claim version mismatch' 'claim'
    Text-File $claim ($claimText.Replace('explicit:local-deployment-offline','foreign'))
    Reject { New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request } 'foreign owner claim' 'claim'
    Text-File $claim $claimText
    $lease.Mod='other'
    Reject { New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request } 'wrong lease mod' 'owner record|identity'
    $lease.Mod='modx'
    $lease.OwnsMutex=$false
    Reject { New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request } 'borrowed lease' 'owning'
    $lease.OwnsMutex=$true
    Text-File (Join-Path $root 'human.txt') 'preserve me'
    Reject { New-VtHostedLocalDeploymentReceipt @hostArgs -Request $request } 'dirty source' 'clean exact'
    [IO.File]::Delete((Join-Path $root 'human.txt'))
    Check ($script:Writes.Count -eq 0) 'all owner/source denials preserve release'
    foreach ($file in $snapshot.BundleFiles) { Text-File (Join-Path $target $file.Path) ([Text.Encoding]::UTF8.GetString($file.Bytes)) }
    $verified = Assert-VtReceiptLocalDeploymentOutput -Snapshot $snapshot -DeployDirectory $target -Mod modx
    Check ($verified.Count -eq 3 -and $verified.Fingerprint -ceq $snapshot.OutputSet.Fingerprint) 'real exact target census passes'
    Text-File (Join-Path $target 'cccccccccccccccc.mod_bundle') 'stale sidecar'
    Reject { Assert-VtReceiptLocalDeploymentOutput -Snapshot $snapshot -DeployDirectory $target -Mod modx } 'extra target output' 'unexpected'
    [IO.File]::Delete((Join-Path $target 'cccccccccccccccc.mod_bundle'))
    [IO.File]::Delete((Join-Path $target $sideBundle))
    Reject { Assert-VtReceiptLocalDeploymentOutput -Snapshot $snapshot -DeployDirectory $target -Mod modx } 'missing target output' 'missing'
    Text-File (Join-Path $target $sideBundle) 'side bytes'
    Text-File (Join-Path $target 'modx.mod') "descriptor`r`n"
    Reject { Assert-VtReceiptLocalDeploymentOutput -Snapshot $snapshot -DeployDirectory $target -Mod modx } 'receipt descriptor is byte-exact, unlike tracked legacy normalization' 'descriptor|SHA'
    Text-File (Join-Path $target 'modx.mod') "descriptor`n"
    Reject { Assert-VtReceiptLocalDeploymentOutput -Snapshot $snapshot -DeployDirectory (Join-Path $FixtureRoot 'workshop/124') -Mod modx } 'foreign target ID' 'committed target'
    Check ([IO.File]::ReadAllText($claim) -ceq $claimText) 'claim remains byte-exact, never released'
    Write-Host "LOCAL_DEPLOYMENT_ASSERTIONS=$script:Count"
}
finally { Exit-VmbMachineTransactionLease -Lease $lease }
