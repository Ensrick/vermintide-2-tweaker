# Issue #1328: immutable deployed-source proof shared by live-card policy and
# canonical pin recovery. These functions establish GitHub source provenance,
# not finite receipt behavior, Workshop transfer, or in-game readiness.
# Loaded by live_test_source_authority.ps1; its immutable Git/lexer helpers are
# deliberately reused, including the #750 batched partial-clone hydration.

function Remove-VtSourceProofTemporaryDirectory {
    param([string]$Path,[string]$ExpectedParent,[string]$NamePrefix)
    $parent=[IO.Path]::GetFullPath($ExpectedParent).TrimEnd([char[]]'\/')
    $target=[IO.Path]::GetFullPath($Path).TrimEnd([char[]]'\/')
    if([string]::IsNullOrWhiteSpace($NamePrefix) -or
       -not [string]::Equals([IO.Path]::GetDirectoryName($target),$parent,[StringComparison]::OrdinalIgnoreCase) -or
       -not [IO.Path]::GetFileName($target).StartsWith($NamePrefix,[StringComparison]::Ordinal)){
        throw 'Source-proof cleanup target is not its expected isolated temporary directory.'
    }
    if(-not [IO.Directory]::Exists($target)){return}
    for($ancestor=$target; $ancestor; $ancestor=[IO.Path]::GetDirectoryName($ancestor)){
        if(([IO.File]::GetAttributes($ancestor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'Source-proof cleanup refuses reparse-point ancestry.'
        }
    }
    $files=New-Object 'System.Collections.Generic.List[string]'
    $directories=New-Object 'System.Collections.Generic.List[string]'
    $pending=New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($target)
    # Validate the complete finite tree before deleting any entry. Never follow
    # junctions/symlinks and never invoke a recursive filesystem delete.
    while($pending.Count -gt 0){
        $directory=$pending.Pop(); $directories.Add($directory)
        foreach($entry in [IO.Directory]::GetFileSystemEntries($directory)){
            $full=[IO.Path]::GetFullPath($entry)
            if(-not $full.StartsWith($target+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
                throw 'Source-proof cleanup descendant escaped its temporary root.'
            }
            $attributes=[IO.File]::GetAttributes($full)
            if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Source-proof cleanup refuses reparse-point descendants.'}
            if(($attributes -band [IO.FileAttributes]::Directory) -ne 0){$pending.Push($full)}else{$files.Add($full)}
        }
    }
    foreach($file in $files){[IO.File]::SetAttributes($file,[IO.FileAttributes]::Normal); [IO.File]::Delete($file)}
    foreach($directory in @($directories | Sort-Object Length -Descending)){[IO.Directory]::Delete($directory,$false)}
}

function Get-VtDeploymentSourceInputs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)]$DeploymentManifest
    )
    if ([int]$DeploymentManifest.manifest_schema -lt 2) { throw 'Deployment manifest schema 2 or newer is required.' }
    if ($DeploymentManifest.PSObject.Properties['_authority_release_tag'] -and
        [string]$DeploymentManifest._authority_release_tag -cne [string]$DeploymentManifest.release_tag) {
        throw "Release tag mismatch: fetched=$($DeploymentManifest._authority_release_tag), manifest=$($DeploymentManifest.release_tag)."
    }
    if ([string]::IsNullOrWhiteSpace([string]$DeploymentManifest.release_tag)) { throw 'Deployment manifest has no release_tag.' }
    $inventoryPath=Join-Path $RepoRoot 'tools/mod-inventory.psd1'
    $exceptionsPath=Join-Path $RepoRoot 'tools/verify/live_test_contract_exceptions.psd1'
    if(-not(Test-Path -LiteralPath $inventoryPath)){throw "Canonical mod inventory is missing: $inventoryPath"}
    if(-not(Test-Path -LiteralPath $exceptionsPath)){throw "Live-test card authority exceptions are missing: $exceptionsPath"}
    $inventory=Import-PowerShellDataFile -LiteralPath $inventoryPath
    $exceptions=Import-PowerShellDataFile -LiteralPath $exceptionsPath

    $inventoryById=@{}; $inventoryByWorkshop=@{}
    foreach($entry in @($inventory.Mods)){
        $id=[string]$entry.ModId; $item=[string]$entry.WorkshopId
        if([string]::IsNullOrWhiteSpace($id)-or$inventoryById.ContainsKey($id)){throw "Canonical mod inventory contains a missing or duplicate ModId '$id'."}
        if([string]::IsNullOrWhiteSpace($item)-or$inventoryByWorkshop.ContainsKey($item)){throw "Canonical mod inventory contains a missing or duplicate WorkshopId '$item'."}
        $inventoryById[$id]=$entry; $inventoryByWorkshop[$item]=$entry
    }
    $deployedById=@{}; $deployedByWorkshop=@{}
    foreach($row in @($DeploymentManifest.mods)){
        $id=[string]$row.mod_id; $item=[string]$row.workshop_id
        if([string]::IsNullOrWhiteSpace($id)-or$deployedById.ContainsKey($id)){throw "Deployment manifest contains a missing or duplicate mod_id '$id'."}
        if([string]::IsNullOrWhiteSpace($item)-or$deployedByWorkshop.ContainsKey($item)){throw "Deployment manifest contains a missing or duplicate workshop_id '$item'."}
        if(-not$inventoryById.ContainsKey($id)){throw "Deployment manifest contains non-inventory mod '$id'."}
        if([string]$inventoryById[$id].ModId -cne $id){throw "Deployment manifest mod_id '$id' does not match canonical case '$($inventoryById[$id].ModId)'."}
        $deployedById[$id]=$row; $deployedByWorkshop[$item]=$row
    }
    foreach($id in @($inventoryById.Keys)){if(-not$deployedById.ContainsKey($id)){throw "Deployment manifest is missing inventory mod '$id'."}}
    # Fail cheap release-row defects before opening hundreds of immutable Lua
    # blobs. Legacy no-commit rows are validated against pinned trees below.
    foreach($id in @($deployedById.Keys)){
        $row=$deployedById[$id];$commit=[string]$row.source_commit
        $assetFilename=[string]$row.asset_filename
        $assetSha256=[string]$row.sha256
        if([string]::IsNullOrWhiteSpace($assetFilename)-or
           [IO.Path]::GetFileName($assetFilename) -cne $assetFilename -or
           $assetFilename -notmatch '(?i)\.zip$'){
            throw "Deployed mod '$id' asset_filename must be one ZIP basename."
        }
        if($assetSha256 -notmatch '^[0-9a-f]{64}$'){
            throw "Deployed mod '$id' ZIP sha256 is not a full lowercase 64-hex digest."
        }
        $rootBundle=[string]$row.root_bundle
        if(-not[string]::IsNullOrWhiteSpace($rootBundle)){
            if([IO.Path]::GetFileName($rootBundle) -cne $rootBundle -or
               $rootBundle -notmatch '(?i)\.mod_bundle$'){
                throw "Deployed mod '$id' root_bundle must be one mod_bundle basename."
            }
            $rootRows=@($row.bundle_files|Where-Object{[string]$_.filename -ceq $rootBundle})
            if($rootRows.Count -ne 1){
                throw "Deployed mod '$id' root_bundle '$rootBundle' must resolve to exactly one bundle_files row."
            }
            if([string]$rootRows[0].sha256 -notmatch '^[0-9a-f]{64}$'){
                throw "Deployed mod '$id' root bundle sha256 is not a full lowercase 64-hex digest."
            }
        }
        if([string]::IsNullOrWhiteSpace($commit)){continue}
        if($commit -notmatch '^[0-9a-f]{40}$'){throw "Deployed mod '$id' source_commit is not a full 40-hex commit."}
        if([string]$row.source_state -cne 'clean'){throw "Deployed mod '$id' source_state must be clean, got '$($row.source_state)'."}
    }

    $legacyByKey=@{}
    foreach($legacy in @($exceptions.LegacySourceTrees)){
        $key=([string]$legacy.ModId)+"`n"+([string]$legacy.Version)
        if($legacyByKey.ContainsKey($key)){throw "Duplicate legacy source-tree exception '$key'."}
        if([string]$legacy.RootTree -notmatch '^[0-9a-f]{40}$' -or [string]$legacy.ModTree -notmatch '^[0-9a-f]{40}$' -or [string]::IsNullOrWhiteSpace([string]$legacy.Reason)){
            throw "Malformed legacy source-tree exception '$key'."
        }
        $legacyByKey[$key]=$legacy
    }

    return [pscustomobject]@{
        Inventory=$inventory; Exceptions=$exceptions
        InventoryById=$inventoryById; DeployedById=$deployedById; LegacyByKey=$legacyByKey
    }
}

function Invoke-VtDeploymentSourcePrefetch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)]$SourceInputs,
        [string[]]$ModIds
    )
    $inventory=$SourceInputs.Inventory; $deployedById=$SourceInputs.DeployedById
    $legacyByKey=$SourceInputs.LegacyByKey
    $entries=@($inventory.Mods)
    if($PSBoundParameters.ContainsKey('ModIds')){
        $entries=@()
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($id in @($ModIds)){
            if([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id) -or
               -not $SourceInputs.InventoryById.ContainsKey($id) -or
               [string]$SourceInputs.InventoryById[$id].ModId -cne $id){
                throw "Prefetch requires distinct canonical ModIds; invalid '$id'."
            }
            $entries+= $SourceInputs.InventoryById[$id]
        }
    }
    # Hydrate every deployed Lua blob this pass will read in a few batched
    # fetches before the per-mod archive transactions begin (#750). Targets are
    # resolved leniently here; the record loop below is the authority on a
    # malformed or unreachable deployed tree.
    $prefetchTargets=@()
    foreach($entry in $entries){
        $id=[string]$entry.ModId
        if(-not$deployedById.ContainsKey($id)){continue}
        $row=$deployedById[$id]
        $treeish=[string]$row.source_commit
        if([string]::IsNullOrWhiteSpace($treeish)){
            $legacyKey=$id+"`n"+([string]$row.version)
            if(-not$legacyByKey.ContainsKey($legacyKey)){continue}
            $treeish=[string]$legacyByKey[$legacyKey].RootTree
        }
        $prefetchTargets+=[pscustomobject]@{
            Commit=$treeish
            Root=(([string]$entry.Dir).TrimEnd([char[]]'\/') -replace '\\','/') + '/scripts/mods'
        }
    }
    Invoke-VtContractDeployedBlobPrefetch -RepoRoot $RepoRoot -DeployedTrees @($prefetchTargets)

}

function Get-VtDeployedModSourceProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)]$InventoryEntry,
        [Parameter(Mandatory=$true)]$ManifestRow,
        [Parameter(Mandatory=$true)][System.Collections.IDictionary]$LegacyByKey,
        [string[]]$RequiredRelativePaths=@()
    )
    $entry=$InventoryEntry; $row=$ManifestRow; $id=[string]$entry.ModId
    if([string]::IsNullOrWhiteSpace($id) -or [string]$row.mod_id -cne $id){
        throw "Deployed mod identity does not match canonical ModId '$id'."
    }
    if([string]$row.workshop_id -cne [string]$entry.WorkshopId){throw "Workshop identity drift for '$id': inventory=$($entry.WorkshopId), deployed=$($row.workshop_id)."}
    if([string]::IsNullOrWhiteSpace([string]$row.version)){throw "Deployed mod '$id' has no version."}
    $relativeRoot=(([string]$entry.Dir).TrimEnd([char[]]'\/') -replace '\\','/') + '/scripts/mods'
    $commit=[string]$row.source_commit
    $rootTree=$null; $modTree=$null; $treeish=$null
    if(-not[string]::IsNullOrWhiteSpace($commit)){
        if($commit -notmatch '^[0-9a-f]{40}$'){throw "Deployed mod '$id' source_commit is not a full 40-hex commit."}
        if([string]$row.source_state -cne 'clean'){throw "Deployed mod '$id' source_state must be clean, got '$($row.source_state)'."}
        $type=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('cat-file','-t',$commit) -Description "Source object for '$id'"
        if($type -cne 'commit'){throw "Deployed mod '$id' source_commit is not a commit object."}
        $rootTree=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',"$commit^{tree}") -Description "Root tree for '$id'"
        $modTree=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',"$commit`:$relativeRoot") -Description "Mod subtree for '$id'"
        if($rootTree -notmatch '^[0-9a-f]{40}$' -or $modTree -notmatch '^[0-9a-f]{40}$'){throw "Deployed source tree resolution failed for '$id'."}
        $treeish=$commit
    }else{
        $legacyKey=$id+"`n"+([string]$row.version)
        if(-not$legacyByKey.ContainsKey($legacyKey)){throw "Deployed mod '$id' has no source_commit and no exact legacy tree exception for '$($row.version)'."}
        $legacy=$legacyByKey[$legacyKey]
        if([string]$legacy.ModId -cne $id -or [string]$legacy.Version -cne [string]$row.version){
            throw "Legacy source-tree exception does not match exact identity/version '$legacyKey'."
        }
        $legacy=$legacyByKey[$legacyKey]; $rootTree=[string]$legacy.RootTree; $modTree=[string]$legacy.ModTree
        $type=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('cat-file','-t',$rootTree) -Description "Legacy root tree for '$id'"
        if($type -cne 'tree'){throw "Legacy root tree for '$id' is not a tree object."}
        $derived=Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',"$rootTree`:$relativeRoot") -Description "Legacy mod subtree for '$id'"
        if($derived -cne $modTree){throw "Legacy source-tree exception drift for '$id': pinned=$modTree, actual=$derived."}
        $treeish=$rootTree
    }
    $documents=@(Get-VtDeployedLuaDocuments -RepoRoot $RepoRoot -Treeish $treeish `
        -RelativeRoot $relativeRoot -RequiredRelativePaths $RequiredRelativePaths)
    if($documents.Count -eq 0){throw "Deployed mod '$id' has no Lua source under '$relativeRoot'."}
    $declaredVersions=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($document in $documents){
        if([string]$document.Content -notmatch '(?i)MOD_VERSION'){continue}
        $tokens=@($document.Tokens)
        for($versionIndex=0;$versionIndex+3 -lt $tokens.Count;$versionIndex++){
            if((Test-VtLuaToken $tokens[$versionIndex] 'local' 'Identifier') -and
                (Test-VtLuaToken $tokens[$versionIndex+1] 'MOD_VERSION' 'Identifier') -and
                (Test-VtLuaToken $tokens[$versionIndex+2] '=') -and
                [string]$tokens[$versionIndex+3].Kind -eq 'String'){
                $null=$declaredVersions.Add(([string]$tokens[$versionIndex+3].Value).TrimStart('v'))
            }
        }
    }
    $releaseVersion=([string]$row.version).TrimStart('v')
    if($declaredVersions.Count -ne 1 -or -not$declaredVersions.Contains($releaseVersion)){
        throw "Deployed mod '$id' MOD_VERSION drift: source=$(@($declaredVersions) -join ','), release=$releaseVersion."
    }
    return [pscustomobject]@{
        ModId=$id; Dir=[string]$entry.Dir; Version=$releaseVersion
        WorkshopId=[string]$row.workshop_id
        SourceCommit=if($commit){$commit}else{$null}
        RootTree=$rootTree; ModTree=$modTree; Treeish=$treeish
        RelativeRoot=$relativeRoot; Documents=@($documents)
    }
}
