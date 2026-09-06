# Canonical-entry hard-death recovery: current server state, never prior intent.
# No CLI, journal replay, build, upload, claim release, or tracker mutation.
. (Join-Path $PSScriptRoot 'exception-pin-finalization.ps1')
. (Join-Path $PSScriptRoot '..\verify\live_test_source_authority.ps1')
. (Join-Path $PSScriptRoot '..\publish-release\release-mutation-lock.ps1')

function Get-VtConsumedExceptionPinIds {
    param([Parameter(Mandatory)]$Exceptions)
    $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($row in @($Exceptions.ReceiptFamilyOverrides)) {
        if ($row -and $row.ModTrees) {
            foreach ($id in $row.ModTrees.Keys) { $null = $ids.Add([string]$id) }
        }
    }
    foreach ($row in @($Exceptions.ReceiptRouteOverrides) + @($Exceptions.ReceiptDiscoveryOverrides)) {
        if ($row) { $null = $ids.Add([string]$row.ModId) }
    }
    $ordered = [string[]]@($ids)
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    return $ordered
}

function Get-VtCurrentSourcePinPlan {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)]$DeploymentManifest,
        [Parameter(Mandatory)][string]$ExceptionsText
    )
    $inputs = Get-VtDeploymentSourceInputs -RepoRoot $RepoRoot -DeploymentManifest $DeploymentManifest
    $ids = @(Get-VtConsumedExceptionPinIds -Exceptions $inputs.Exceptions)
    Invoke-VtDeploymentSourcePrefetch -RepoRoot $RepoRoot -SourceInputs $inputs -ModIds $ids
    $text = $ExceptionsText
    $changes = New-Object 'System.Collections.Generic.List[object]'
    foreach ($id in $ids) {
        # Inputs and proof both enforce exact canonical identity. No historical
        # tree hash is fabricated into a commit-bearing publication context.
        $proof = Get-VtDeployedModSourceProof -RepoRoot $RepoRoot -InventoryEntry $inputs.InventoryById[$id] `
            -ManifestRow $inputs.DeployedById[$id] -LegacyByKey $inputs.LegacyByKey
        $plan = Get-VtExceptionPinRepointPlan -ExceptionsText $text -ModId $id -DeployedTree $proof.ModTree
        if (@($plan.Unresolved).Count) { throw "Current source pins for '$id' remain unresolved: $($plan.Unresolved -join ', ')." }
        if ($plan.Changed) {
            $changes.Add([pscustomobject]@{ ModId = $id; ModTree = $proof.ModTree; PinCount = $plan.PinCount; RewriteCount = $plan.RewriteCount })
        }
        $text = $plan.NewText
    }
    # All rows are proved before the caller may write even the first pin.
    return [pscustomobject]@{ Changed = ($text -cne $ExceptionsText); NewText = $text; Changes = @($changes.ToArray()); ModIds = $ids }
}

function Assert-VtSourcePinRecoveryOwner {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)]$TransactionLease)
    $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd([char[]]@('\','/'))
    $process = [Diagnostics.Process]::GetCurrentProcess()
    if (-not $TransactionLease.Acquired -or -not $TransactionLease.OwnsMutex -or -not $TransactionLease.MutexHolder -or
        $TransactionLease.OwnerPid -ne $PID -or $TransactionLease.Action -cne 'ship' -or
        $TransactionLease.OwnerStartUtcTicks -ne $process.StartTime.ToUniversalTime().Ticks -or
        -not [string]::Equals($root, [string]$TransactionLease.ProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Current source-pin recovery requires the original owning canonical ship lease.'
    }
    $owner = [IO.File]::ReadAllText($TransactionLease.RecordPath) | ConvertFrom-Json
    if ([string]$owner.schema -cne '2' -or [string]$owner.lease_id -cne [string]$TransactionLease.LeaseId -or
        [string]$owner.owner_pid -cne [string]$PID -or
        [string]$owner.owner_start_utc_ticks -cne [string]$TransactionLease.OwnerStartUtcTicks -or
        [string]$owner.session_id -cne [string]$process.SessionId -or $owner.action -cne 'ship' -or
        [string]$owner.mod -cne [string]$TransactionLease.Mod -or
        -not [string]::Equals($root, [string]$owner.project_root, [StringComparison]::OrdinalIgnoreCase) -or
        [string]$owner.process_tree_job_name -cne [VmbTransactionProcessTreeGuard]::Ensure()) {
        throw 'Current source-pin recovery lost its authenticated transaction owner record.'
    }
}

function Invoke-VtCurrentSourcePinReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$SourceCommit,
        [Parameter(Mandatory)]$TransactionLease
    )
    Assert-VtSourcePinRecoveryOwner -RepoRoot $RepoRoot -TransactionLease $TransactionLease
    if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
        (Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse','HEAD') -Description 'Recovery source HEAD') -cne $SourceCommit -or
        (Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('status','--porcelain','--untracked-files=all') -Description 'Recovery source cleanliness')) {
        throw 'Source-pin recovery requires the already authorized clean exact source checkout.'
    }
    $primary = Get-VmbLauncherPrimaryWorktreeRoot -RepoRoot $RepoRoot
    if ([string]::IsNullOrWhiteSpace($primary)) { throw 'Cannot discover the current primary checkout for source-pin recovery.' }
    $common = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse','--path-format=absolute','--git-common-dir') -Description 'Recovery invoking common directory'
    $primaryCommon = Get-VtGitScalar -RepoRoot $primary -Arguments @('rev-parse','--path-format=absolute','--git-common-dir') -Description 'Recovery primary common directory'
    if (-not [string]::Equals([IO.Path]::GetFullPath($common), [IO.Path]::GetFullPath($primaryCommon), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source-pin recovery primary belongs to a different Git common directory.'
    }
    Invoke-VtPinDescendantDrain
    $releaseMutex = Enter-VtGitHubReleaseMutationMutex
    try {
        try { $manifest = Get-VtCardDeploymentManifest -Repository 'Ensrick/vermintide-2-tweaker' }
        catch {
            # No manifest means no repair authority, not permission to recreate
            # sibling entries. The existing publisher owns its separate bounded
            # target/different-release fallback and must still pass every gate.
            return [pscustomobject]@{ Status = 'unavailable'; Changed = $false; RequiresMetadataPR = $false; Summary = "Current manifest unavailable; no pins changed: $($_.Exception.Message)" }
        }
        $relative = 'tools\verify\live_test_contract_exceptions.psd1'
        $sourcePath = Join-Path $RepoRoot $relative
        $sourceBytes = [IO.File]::ReadAllBytes($sourcePath)
        $sourceText = [Text.Encoding]::UTF8.GetString($sourceBytes).TrimStart([char]0xfeff)
        $plan = Get-VtCurrentSourcePinPlan -RepoRoot $RepoRoot -DeploymentManifest $manifest -ExceptionsText $sourceText
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($sourcePath)) -cne [Convert]::ToBase64String($sourceBytes)) {
            throw 'Invoking source pins changed while current manifest provenance was being checked.'
        }
        if (-not $plan.Changed) {
            return [pscustomobject]@{ Status = 'current'; Changed = $false; RequiresMetadataPR = $false; Summary = "Current GitHub source pins ($($plan.ModIds.Count) mod identities); no publication authority granted." }
        }
        $target = Join-Path $primary $relative
        $primaryBytes = [IO.File]::ReadAllBytes($target)
        $primaryText = [Text.Encoding]::UTF8.GetString($primaryBytes).TrimStart([char]0xfeff)
        # A clean linked checkout may have different Git-supported line endings.
        # Reuse the proven target identities on the destination's own text;
        # never copy its sibling checkout's formatting over the primary.
        $primaryCandidate = $primaryText
        foreach ($change in $plan.Changes) {
            $destinationPlan = Get-VtExceptionPinRepointPlan -ExceptionsText $primaryCandidate `
                -ModId $change.ModId -DeployedTree $change.ModTree
            if (@($destinationPlan.Unresolved).Count -or $destinationPlan.PinCount -ne $change.PinCount) {
                throw 'Primary source pins require manual reconciliation; original bytes retained.'
            }
            $primaryCandidate = $destinationPlan.NewText
        }
        if ($primaryText -ceq $primaryCandidate) {
            return [pscustomobject]@{ Status = 'pending'; Changed = $false; RequiresMetadataPR = $true; Summary = "Primary already contains the current pin candidate at '$target'. The invoking source still requires its reviewed metadata merge." }
        }
        $primaryHead = Get-VtGitScalar -RepoRoot $primary -Arguments @('rev-parse','HEAD') -Description 'Recovery primary HEAD'
        $primaryStatus = Get-VtGitScalar -RepoRoot $primary -Arguments @('status','--porcelain','--untracked-files=all') -Description 'Recovery primary cleanliness'
        if ($primaryHead -cne $SourceCommit -or $primaryStatus) {
            throw 'Source pins require a metadata PR, but the primary checkout is not the clean current baseline; all primary edits were preserved.'
        }
        # The destination is freshly derived, never an old worktree/journal path.
        # Refuse reparse components before a write can escape that checkout.
        $component = Get-Item -LiteralPath (Split-Path $target -Parent) -Force
        while ($null -ne $component) {
            if ($component.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source-pin recovery refuses a reparse destination component.' }
            $component = $component.Parent
        }
        Write-VtExceptionPinBytes -Path $target -OriginalBytes $primaryBytes -NewText $primaryCandidate
        return [pscustomobject]@{ Status = 'reconciled'; Changed = $true; RequiresMetadataPR = $true; Summary = "Reconciled $($plan.Changes.Count) mod identities in '$target'. Review and merge this metadata before retrying; no Workshop delivery is inferred." }
    }
    finally {
        try { $releaseMutex.ReleaseMutex() }
        finally { $releaseMutex.Dispose() }
    }
}
