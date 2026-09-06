# Issue #1328: GitHub provenance reconciliation, never Workshop readiness.

# Issue #1328: pure planner for the step-5b exception-pin repoint. Takes the
# CURRENT text of tools/verify/live_test_contract_exceptions.psd1, the shipped
# mod's exception ModId, and the freshly deployed scripts/mods subtree hash
# (the exact value live_test_source_authority.ps1 compares pins against), and
# returns the rewritten text plus a change report. Semantics:
#   * Only the three CONSUMED structures are rewritten: ReceiptFamilyOverrides
#     (per-mod ModTrees hashtable values), ReceiptRouteOverrides
#     (ModTree scalar / ModTrees array), ReceiptDiscoveryOverrides (ModTree).
#   * LegacyMarkerFamilyModTrees (reviewer context, deliberately unconsumed)
#     and LegacySourceTrees (carried-forward promotion pins) are NEVER touched:
#     their whole top-level sections are excluded from the rewrite.
#   * The stale-value set is computed SEMANTICALLY (Import-PowerShellDataFile)
#     from entries pinning this exact ModId, then replaced TEXTUALLY so every
#     comment, ordering, and unrelated pin survives byte-identical. A pinned
#     multi-tree array collapses to the single deployed tree: only one deployed
#     record exists per mod, so any other member is stale by construction.
#   * The rewrite is verified by re-parsing: any pin for this mod that still
#     lacks the deployed tree is returned in .Unresolved for a loud warning.
function Get-VtExceptionPinRepointPlan {
    param(
        [Parameter(Mandatory=$true)][string]$ExceptionsText,
        [Parameter(Mandatory=$true)][string]$ModId,
        [Parameter(Mandatory=$true)][string]$DeployedTree
    )
    if ($DeployedTree -notmatch '^[0-9a-f]{40}$') { throw "Deployed tree must be a full 40-hex hash, got '$DeployedTree'." }
    if ($ModId -notmatch '^[A-Za-z0-9_]+$') { throw "Exception ModId must be a bare identifier, got '$ModId'." }

    function Get-PinTuples {
        param([string]$Text)
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('vt2-pin-repoint-' + [guid]::NewGuid().ToString('N') + '.psd1')
        try {
            [IO.File]::WriteAllText($tmp, $Text, (New-Object System.Text.UTF8Encoding($false)))
            $data = Import-PowerShellDataFile -LiteralPath $tmp
        }
        finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        $tuples = @()
        foreach ($o in @($data.ReceiptFamilyOverrides)) {
            if ($o -and $o.ModTrees -and $o.ModTrees.ContainsKey($ModId)) {
                $tuples += [pscustomobject]@{ Structure = 'ReceiptFamilyOverrides'; Marker = [string]$o.Marker; Trees = @($o.ModTrees[$ModId]) }
            }
        }
        foreach ($o in @($data.ReceiptRouteOverrides)) {
            if ($o -and [string]$o.ModId -ceq $ModId) {
                $trees = if ($o.ContainsKey('ModTrees')) { @($o.ModTrees) } else { @([string]$o.ModTree) }
                $tuples += [pscustomobject]@{ Structure = 'ReceiptRouteOverrides'; Marker = [string]$o.Marker; Trees = @($trees) }
            }
        }
        foreach ($o in @($data.ReceiptDiscoveryOverrides)) {
            if ($o -and [string]$o.ModId -ceq $ModId) {
                $tuples += [pscustomobject]@{ Structure = 'ReceiptDiscoveryOverrides'; Marker = [string]$o.Marker; Trees = @([string]$o.ModTree) }
            }
        }
        return @($tuples)
    }

    $pins = @(Get-PinTuples -Text $ExceptionsText)
    $stale = @{}
    foreach ($pin in $pins) {
        foreach ($tree in @($pin.Trees)) {
            $t = ([string]$tree).Trim()
            if ($t -match '^[0-9a-f]{40}$' -and $t -cne $DeployedTree) { $stale[$t] = $true }
        }
    }
    $result = [ordered]@{
        PinCount = $pins.Count; StaleTrees = @($stale.Keys | Sort-Object)
        Changed = $false; RewriteCount = 0; NewText = $ExceptionsText; Unresolved = @()
    }
    if ($pins.Count -eq 0 -or $stale.Count -eq 0) { return [pscustomobject]$result }

    $modEsc = [regex]::Escape($ModId)
    $staleAlt = @($stale.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $rewrites = 0
    # Replace a quoted-sha array with the single deployed tree, but ONLY when
    # it actually contains a stale pin for this mod; anything else is returned
    # unchanged. Shared by the hashtable-value and route-override array forms.
    $arrayEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $body = $m.Groups['body'].Value
        $shas = @([regex]::Matches($body, "'([0-9a-f]{40})'") | ForEach-Object { $_.Groups[1].Value })
        $hasStale = $false
        foreach ($sha in $shas) { if ($stale.ContainsKey($sha)) { $hasStale = $true } }
        if ($shas.Count -eq 0 -or -not $hasStale) { return $m.Value }
        $script:__pinRewrites++
        return ($m.Groups['key'].Value + "@('" + $DeployedTree + "')")
    }
    $scalarEvaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($m)
        $script:__pinRewrites++
        return ($m.Groups['key'].Value + "'" + $DeployedTree + "'")
    }

    # Line-based pass so the two deliberately-historical top-level sections can
    # be excluded wholesale. A top-level section starts at 4-space indent.
    # NOTE: no -split limit -- pwsh 7 treats a NEGATIVE limit as right-to-left
    # splitting (returning the whole string for -1), while 5.1 treats it as 0.
    $lines = $ExceptionsText -split "`n"
    $section = ''
    $script:__pinRewrites = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s{4}(\w+)\s*=') { $section = $matches[1] }
        if ($section -eq 'LegacyMarkerFamilyModTrees' -or $section -eq 'LegacySourceTrees') { continue }
        # Family-override hashtable values keyed by this mod: scalar and array.
        $line = [regex]::Replace($line, "(?<key>\b$modEsc\s*=\s*)'(?:$staleAlt)'", $scalarEvaluator)
        $line = [regex]::Replace($line, "(?<key>\b$modEsc\s*=\s*)@\((?<body>[^)]*)\)", $arrayEvaluator)
        # Route/discovery scalar and array pins: entry-scoped by the inline
        # ModId literal so another mod's identical tree can never be rewritten.
        if ($line -match "\bModId\s*=\s*'$modEsc'") {
            $line = [regex]::Replace($line, "(?<key>\bModTrees?\s*=\s*)'(?:$staleAlt)'", $scalarEvaluator)
            $line = [regex]::Replace($line, "(?<key>\bModTrees\s*=\s*)@\((?<body>[^)]*)\)", $arrayEvaluator)
        }
        $lines[$i] = $line
    }
    $rewrites = [int]$script:__pinRewrites
    Remove-Variable -Name __pinRewrites -Scope Script -ErrorAction SilentlyContinue
    $newText = $lines -join "`n"

    # Honest-verification pass: re-parse the rewritten text and surface any pin
    # for this mod that still lacks the deployed tree (unexpected formatting).
    $unresolved = @()
    foreach ($pin in @(Get-PinTuples -Text $newText)) {
        if (@($pin.Trees) -cnotcontains $DeployedTree) {
            $unresolved += ("{0} {1}" -f $pin.Structure, $pin.Marker)
        }
    }
    $result.Changed = ($newText -cne $ExceptionsText)
    $result.RewriteCount = $rewrites
    $result.NewText = $newText
    $result.Unresolved = @($unresolved)
    return [pscustomobject]$result
}

# This record is private, in-memory provenance prepared before publication and
# armed by the publisher after confirmed GitHub publication, before receipt
# handoff. It is not an
# upload receipt, restart journal, or permission to publish/label anything.
function New-VtPublishedPinContext {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$Mod,
        [Parameter(Mandatory)][string]$ModId,
        [Parameter(Mandatory)][string]$SourceCommit,
        [Parameter(Mandatory)][string]$ModTree,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$PublishedId,
        [Parameter(Mandatory)][string]$ReleaseTag
    )
    $json = [ordered]@{
        Purpose = 'github-source-pins-v1'; Repository = 'Ensrick/vermintide-2-tweaker'
        RepoRoot = [IO.Path]::GetFullPath($RepoRoot); Mod = $Mod; ModId = $ModId
        SourceCommit = $SourceCommit; ModTree = $ModTree; Version = $Version
        PublishedId = $PublishedId; ReleaseTag = $ReleaseTag
    } | ConvertTo-Json -Compress
    $null = ConvertFrom-VtPublishedPinContext -Json $json
    return $json
}

function ConvertFrom-VtPublishedPinContext {
    param([Parameter(Mandatory)][string]$Json)
    if ($Json.Length -gt 8192) { throw 'Publication pin context exceeds its bound.' }
    $record = $Json | ConvertFrom-Json
    $fields = @('Purpose', 'Repository', 'RepoRoot', 'Mod', 'ModId', 'SourceCommit', 'ModTree', 'Version', 'PublishedId', 'ReleaseTag')
    $names = @($record.PSObject.Properties.Name)
    if ((($names | Sort-Object) -join ',') -cne (($fields | Sort-Object) -join ',')) {
        throw 'Publication pin context has an unexpected shape.'
    }
    foreach ($name in $fields) {
        if ($record.$name -isnot [string] -or [string]::IsNullOrWhiteSpace($record.$name)) {
            throw "Publication pin context field '$name' must be a nonempty string."
        }
    }
    if ($record.Purpose -cne 'github-source-pins-v1' -or
        $record.Repository -cne 'Ensrick/vermintide-2-tweaker' -or
        $record.Mod -cnotmatch '^[a-z][a-z0-9_]*$' -or
        $record.ModId -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$' -or
        $record.SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
        $record.ModTree -cnotmatch '^[0-9a-f]{40}$' -or
        $record.Version -cnotmatch '^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$' -or
        $record.PublishedId -cnotmatch '^[1-9][0-9]*$' -or
        $record.ReleaseTag -cnotmatch '^mods-\d{4}-\d{2}-\d{2}$' -or
        -not [IO.Path]::IsPathRooted($record.RepoRoot)) {
        throw 'Publication pin context identity is malformed (zero-ID bootstrap is excluded).'
    }
    return $record
}

function Invoke-VtPinDescendantDrain {
    [VmbTransactionProcessTreeGuard]::TerminateAndWaitForResidualDescendants(10000)
}

# A private reference shared with the internal publisher, not a CLI receipt or
# durable journal. Validate before the first remote mutation; after success the
# publisher performs only one non-throwing field assignment before handoff.
function Assert-VtPinPublicationHandoff {
    param(
        [Parameter(Mandatory)][hashtable]$Handoff,
        [AllowNull()][string]$ExpectedJson
    )
    if ($Handoff.Count -ne 2 -or @($Handoff.Keys) -cnotcontains 'PreparedJson' -or
        @($Handoff.Keys) -cnotcontains 'PublishedJson' -or $null -ne $Handoff.PublishedJson) {
        throw 'Publication pin handoff must be a fresh, closed two-field holder.'
    }
    if ([string]::IsNullOrEmpty($ExpectedJson)) {
        if ($null -ne $Handoff.PreparedJson) { throw 'Bootstrap cannot carry publication pin provenance.' }
        return
    }
    if ($Handoff.PreparedJson -isnot [string]) { throw 'Publication pin handoff has no prepared identity.' }
    $prepared = ConvertFrom-VtPublishedPinContext -Json $Handoff.PreparedJson
    $expected = ConvertFrom-VtPublishedPinContext -Json $ExpectedJson
    foreach ($field in $expected.PSObject.Properties.Name) {
        if ([string]$prepared.$field -cne [string]$expected.$field) {
            throw "Publication pin handoff disagrees with publisher-owned '$field'."
        }
    }
}

function Assert-VtPublishedReleaseIdentity {
    param([Parameter(Mandatory)]$Release, [Parameter(Mandatory)][string]$Tag)
    if ([string]$Release.id -cnotmatch '^[1-9][0-9]*$' -or
        [string]$Release.tag_name -cne $Tag -or
        $Release.draft -isnot [bool] -or $Release.draft) {
        throw 'Source-pin provenance requires the exact confirmed published release, not an absent/ambiguous draft flag.'
    }
}

function Write-VtPinFinalizationWarning {
    param([Parameter(Mandatory)][string]$Message)
    # Secondary reporting cannot supersede the already-reported ship failure
    # or prevent lease cleanup, even when a host warning observer throws.
    try { Write-Warning $Message -WarningAction Continue }
    catch {
        try { [Console]::Error.WriteLine($Message) }
        catch { } # Closed/broken reporting sink; preserve primary exit/error.
    }
}

function Invoke-VtPublishedPinFinalization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PublicationJson,
        [Parameter(Mandatory)][object]$TransactionLease
    )
    $record = ConvertFrom-VtPublishedPinContext -Json $PublicationJson
    # Reconciliation must remain inside the authenticated original ship lease,
    # never a joined borrower or a standalone recovery/publication entry point.
    if (-not $TransactionLease.Acquired -or -not $TransactionLease.OwnsMutex -or
        $TransactionLease.OwnerPid -ne $PID -or $TransactionLease.Action -cne 'ship' -or
        $TransactionLease.Mod -cne $record.Mod -or
        -not [string]::Equals([IO.Path]::GetFullPath($TransactionLease.ProjectRoot),
            [IO.Path]::GetFullPath($record.RepoRoot), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Publication pin context does not match the owning ship transaction.'
    }
    $owner = [IO.File]::ReadAllText($TransactionLease.RecordPath) | ConvertFrom-Json
    if ([string]$owner.lease_id -cne [string]$TransactionLease.LeaseId) {
        throw 'Publication pin finalization lost its authenticated owner record.'
    }

    # Exit-VmbMachineTransactionLease also drains defensively. This explicit
    # drain is necessary BEFORE any working-tree write: the SDK/launcher can
    # leave descendants behind even when its direct process already exited.
    Invoke-VtPinDescendantDrain
    $path = Join-Path $record.RepoRoot 'tools\verify\live_test_contract_exceptions.psd1'
    $file = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Exception pins cannot be a reparse point.' }
    $original = [IO.File]::ReadAllBytes($path)
    $text = [Text.Encoding]::UTF8.GetString($original).TrimStart([char]0xfeff)
    $plan = Get-VtExceptionPinRepointPlan -ExceptionsText $text -ModId $record.ModId -DeployedTree $record.ModTree
    if (@($plan.Unresolved).Count -gt 0) {
        throw "Exception pins remain unresolved; original bytes retained: $($plan.Unresolved -join ', ')"
    }
    if ($plan.Changed) {
        $encoding = New-Object Text.UTF8Encoding($false)
        $bytes = $encoding.GetBytes($plan.NewText)
        # Stage beside the target and replace atomically, so a write exception
        # cannot truncate the authority file used by all other mod cards.
        $temporary = $path + '.' + [guid]::NewGuid().ToString('N') + '.pending'
        try {
            [IO.File]::WriteAllBytes($temporary, $bytes)
            if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($temporary)) -cne [Convert]::ToBase64String($bytes)) {
                throw 'Exception-pin staged bytes failed readback.'
            }
            if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String($original)) {
                throw 'Exception pins changed during reconciliation; preserving the newer file.'
            }
            [IO.File]::Replace($temporary, $path, [NullString]::Value)
            if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String($bytes)) {
                throw 'Exception-pin persisted bytes failed readback.'
            }
        }
        finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        }
        Write-Host ("  GitHub source pins: {0} value(s) for {1} -> {2}." -f $plan.RewriteCount, $record.ModId, $record.ModTree) -ForegroundColor Yellow
        Write-Host '  Carry the working-tree pin change in the next reviewed PR; this is NOT Workshop/test-readiness evidence.' -ForegroundColor Yellow
    }
    return [pscustomobject]@{
        Completed = $true; Changed = [bool]$plan.Changed; PinCount = $plan.PinCount
        Summary = $(if ($plan.Changed) { "repointed $($plan.RewriteCount) values (working tree; carry in next PR)" } else { "current ($($plan.PinCount) pin groups)" })
    }
}
