# Issue #1328: GitHub provenance reconciliation, never Workshop readiness.

# #1777: narrow opt-in route retention; provenance is not publication authority.
function ConvertFrom-VtExceptionPinText {
    param([Parameter(Mandatory)][string]$Text)
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('vt2-pin-data-' + [guid]::NewGuid().ToString('N') + '.psd1')
    try {
        [IO.File]::WriteAllText($temporary, $Text, (New-Object Text.UTF8Encoding($false)))
        return Import-PowerShellDataFile -LiteralPath $temporary
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
}

function Get-VtReviewedRouteTransitionDeclarations {
    param([Parameter(Mandatory)][AllowEmptyCollection()]$Data)
    $keys = @($Data.Keys | Where-Object { [string]$_ -ieq 'ReviewedRouteTransitions' })
    if ($keys.Count -eq 0) { return @() }
    if ($keys.Count -ne 1 -or [string]$keys[0] -cne 'ReviewedRouteTransitions' -or
        $Data[$keys[0]] -isnot [array]) { throw '[route-transition] invalid declaration section' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($declaration in @($Data.ReviewedRouteTransitions)) {
        $fields = @('ModId','FromSourceCommit','CandidateModTree','CandidateReceiptSha256')
        if ($declaration -isnot [System.Collections.IDictionary] -or $declaration.Count -ne $fields.Count) {
            throw '[route-transition] declaration must contain exactly four fields'
        }
        foreach ($field in $fields) {
            if (@($declaration.Keys) -cnotcontains $field -or $declaration[$field] -isnot [string]) {
                throw "[route-transition] missing, mistyped or wrong-case field '$field'"
            }
        }
        if ($declaration.ModId -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$' -or
            $declaration.FromSourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
            $declaration.CandidateModTree -cnotmatch '^[0-9a-f]{40}$' -or
            $declaration.CandidateReceiptSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            -not $seen.Add($declaration.ModId)) { throw '[route-transition] malformed or duplicate declaration' }
        $declaration
    }
}

function Test-VtRouteTransitionDataEqual {
    param($Left, $Right, [int]$Depth = 0)
    if ($Depth -gt 16) { return $false }
    if ($null -eq $Left -or $null -eq $Right) { return $null -eq $Left -and $null -eq $Right }
    if ($Left -is [System.Collections.IDictionary]) {
        if ($Right -isnot [System.Collections.IDictionary] -or $Left.Count -ne $Right.Count) { return $false }
        foreach ($key in $Left.Keys) {
            if (@($Right.Keys) -cnotcontains $key -or
                -not (Test-VtRouteTransitionDataEqual $Left[$key] $Right[$key] ($Depth + 1))) { return $false }
        }
        return $true
    }
    if ($Left -is [array]) {
        if ($Right -isnot [array] -or $Left.Count -ne $Right.Count) { return $false }
        for ($i = 0; $i -lt $Left.Count; $i++) {
            if (-not (Test-VtRouteTransitionDataEqual $Left[$i] $Right[$i] ($Depth + 1))) { return $false }
        }
        return $true
    }
    return $Left.GetType() -eq $Right.GetType() -and $Left -ceq $Right
}

function Assert-VtReviewedRouteTransitionRows {
    param([Parameter(Mandatory)][AllowEmptyCollection()]$Data, [Parameter(Mandatory)][string]$ModId,
          [Parameter(Mandatory)][string]$FromTree, [Parameter(Mandatory)][string]$ToTree)
    foreach ($family in @($Data.ReceiptFamilyOverrides)) {
        $familyIds = @($family.ModId) + @($family.ModIds)
        if ($family.ModTrees) { $familyIds += @($family.ModTrees.Keys) }
        if ($family.SourcesByMod) { $familyIds += @($family.SourcesByMod.Keys) }
        if (@($familyIds | Where-Object { [string]$_ -ieq $ModId }).Count) {
            throw '[route-transition] family/discovery ownership is not eligible'
        }
    }
    if (@($Data.ReceiptDiscoveryOverrides | Where-Object { [string]$_.ModId -ieq $ModId }).Count) {
        throw '[route-transition] family/discovery ownership is not eligible'
    }
    $rows = @($Data.ReceiptRouteOverrides | Where-Object { [string]$_.ModId -ieq $ModId })
    if ($FromTree -ceq $ToTree -or $rows.Count -eq 0) { throw '[route-transition] two distinct trees and route ownership required' }
    $seenRoutes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($row in $rows) {
        if ($row -isnot [System.Collections.IDictionary] -or -not $seenRoutes.Add(([string]$row.Source + [char]10 + [string]$row.Signature))) {
            throw '[route-transition] malformed or duplicate route identity'
        }
        $trees = @($row.ModTrees)
        if ([string]$row.ModId -cne $ModId -or @($row.Keys) -cnotcontains 'ModTrees' -or
            $row.ContainsKey('ModTree') -or $row.ModTrees -isnot [array] -or
            $trees.Count -ne 2 -or @($trees | Where-Object { $_ -isnot [string] -or $_ -cnotmatch '^[0-9a-f]{40}$' }).Count -or
            @($trees | Sort-Object -Unique -CaseSensitive).Count -ne 2 -or
            $trees -cnotcontains $FromTree -or $trees -cnotcontains $ToTree) {
            throw '[route-transition] every route must name exactly the same reviewed pair'
        }
    }
    return @($rows)
}

# Only existing canonical owners call this constructor. It reads the exact
# authorized commit and actual text; no boolean or user-declared prefix is proof.
function New-VtReviewedRouteTransitionProofs {
    param([Parameter(Mandatory)][string]$RepoRoot, [Parameter(Mandatory)][string]$SourceCommit,
          [Parameter(Mandatory)][string]$ExceptionsText)
    $data = ConvertFrom-VtExceptionPinText $ExceptionsText
    $declarations = @(Get-VtReviewedRouteTransitionDeclarations $data)
    $proofs = @{}
    if ($declarations.Count -eq 0) { return $proofs }
    . (Join-Path $PSScriptRoot 'build-receipt.ps1')
    . (Join-Path $PSScriptRoot 'build-output-normalization.ps1')
    . (Join-Path $PSScriptRoot '..\verify\live_test_source_authority.ps1')
    if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
        (Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse','HEAD') -Description 'Transition source HEAD') -cne $SourceCommit -or
        (Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('diff','--name-only',$SourceCommit,'--','tools/mod-inventory.psd1') -Description 'Transition inventory cleanliness')) {
        throw '[route-transition] exact canonical source/inventory context required'
    }
    $committedText = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('show',($SourceCommit + ':tools/verify/live_test_contract_exceptions.psd1')) -Description 'Committed transition policy'
    $committed = ConvertFrom-VtExceptionPinText $committedText
    $committedDeclarations = @(Get-VtReviewedRouteTransitionDeclarations $committed)
    if (-not (Test-VtRouteTransitionDataEqual $declarations $committedDeclarations)) {
        throw '[route-transition] declaration differs from authorized source'
    }
    $inventory = Import-PowerShellDataFile -LiteralPath (Join-Path $RepoRoot 'tools/mod-inventory.psd1')
    foreach ($declaration in $declarations) {
        $id = [string]$declaration.ModId
        $entries = @($inventory.Mods | Where-Object { [string]$_.ModId -ieq $id })
        if ($entries.Count -ne 1 -or [string]$entries[0].ModId -cne $id) { throw '[route-transition] canonical inventory identity missing or ambiguous' }
        $entry = $entries[0]
        $authority = Assert-VtBundleAuthorityEntry -Entry $entry
        $dir = [string]$entry.Dir
        $relativeRoot = $dir + '/scripts/mods'
        $from = [string]$declaration.FromSourceCommit
        if ((Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('cat-file','-t',$from) -Description 'Transition ancestor object') -cne 'commit') {
            throw '[route-transition] FromSourceCommit is not a commit'
        }
        $null = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('merge-base','--is-ancestor',$from,$SourceCommit) -Description 'Transition same-history ancestor'
        $fromTree = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',($from + ':' + $relativeRoot)) -Description 'Transition From tree'
        $toTree = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',($SourceCommit + ':' + $relativeRoot)) -Description 'Transition candidate tree'
        if ($fromTree -cnotmatch '^[0-9a-f]{40}$' -or $toTree -cne [string]$declaration.CandidateModTree) {
            throw '[route-transition] inventory-qualified candidate tree mismatch'
        }
        foreach ($tree in @($fromTree,$toTree)) {
            if ((Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('cat-file','-t',$tree) -Description 'Transition subtree type') -cne 'tree') {
                throw '[route-transition] source subtree is not a tree'
            }
        }
        $rows = @(Assert-VtReviewedRouteTransitionRows $data $id $fromTree $toTree)
        $committedRows = @(Assert-VtReviewedRouteTransitionRows $committed $id $fromTree $toTree)
        if (-not (Test-VtRouteTransitionDataEqual $rows $committedRows)) { throw '[route-transition] routes differ from authorized source' }
        foreach ($row in $rows) {
            $paths = @([string]$row.Source)
            foreach ($anchor in @($row.EmitterAnchors) + @($row.GuardAnchors)) {
                $paths += Get-VtReceiptAnchorSource -Anchor $anchor -DefaultSource ([string]$row.Source)
            }
            foreach ($path in $paths) {
                if (-not $path.StartsWith(($relativeRoot + '/'),[StringComparison]::Ordinal)) { throw '[route-transition] foreign route/anchor source' }
            }
        }
        $receiptPath = $dir + '/.build-receipt.json'
        $receiptBlob = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('rev-parse',($SourceCommit + ':' + $receiptPath)) -Description 'Transition committed receipt'
        $receiptHash = Get-VtBuildGitBlobSha256 -RepoRoot $RepoRoot -GitBlob $receiptBlob
        if ($receiptHash -cne [string]$declaration.CandidateReceiptSha256) { throw '[route-transition] candidate receipt digest mismatch' }
        $receiptJson = Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('show',($SourceCommit + ':' + $receiptPath)) -Description 'Transition receipt bytes'
        $receipt = ConvertFrom-VtBuildReceiptJson -Json $receiptJson
        $sourceMap = Get-VtBuildCommitSourceMap -RepoRoot $RepoRoot -Mod $dir -Commit $SourceCommit
        if ($authority -ceq 'tracked') {
            $outputs = Get-VtBuildCommitOutputSet -RepoRoot $RepoRoot -Mod $dir -Commit $SourceCommit -SourceMap $sourceMap -InventoryEntry $entry
        }
        else {
            if (Get-VtGitScalar -RepoRoot $RepoRoot -Arguments @('ls-tree','-r',$SourceCommit,'--',($dir + '/bundleV2')) -Description 'Receipt-authority tracked output absence') {
                throw '[route-transition] receipt authority has tracked output'
            }
            $outputs = Get-VtBuildReceiptDeclaredOutputSet -Receipt $receipt -ExpectedMod $dir
        }
        $normalization = New-BuildOutputNormalizationPolicyProof -ModEntry $entry
        $valid = Test-VtBuildReceiptProof -Receipt $receipt -ExpectedMod $dir -SourceMap $sourceMap -OutputSet $outputs -NormalizationPolicy $normalization -MinimumSchema 3
        if (-not $valid.Ok) { throw ('[route-transition] candidate schema-3 proof invalid: ' + ($valid.Problems -join '; ')) }
        # Retention validation only: the unchanged consumer still selects and
        # discovers active routes exclusively from the current manifest.
        foreach ($commit in @($from,$SourceCommit)) {
            $required = @(Get-VtExceptionSourcePaths -Exceptions $data -ModId $id)
            $documents = @(Get-VtDeployedLuaDocuments -RepoRoot $RepoRoot -Treeish $commit -RelativeRoot $relativeRoot -RequiredRelativePaths $required)
            $byPath = @{}
            foreach ($document in $documents) { $byPath[[string]$document.RelativePath] = $document }
            foreach ($row in $rows) {
                Test-VtReceiptOverrideDefinition -Override $row -Context 'reviewed route retention'
                Test-VtDocumentAnchors -ByPath $byPath -Override $row -DefaultSource ([string]$row.Source) -Context 'Reviewed route retention'
            }
        }
        $proofs[$id] = [pscustomobject]@{
            ModId=$id; FromTree=$fromTree; ToTree=$toTree; SourceCommit=$SourceCommit
            Declaration=$declaration; Rows=$rows; ReceiptSha256=$receiptHash
        }
    }
    return $proofs
}


function Get-VtReviewedRoutePlanningTransition {
    param([Parameter(Mandatory)][string]$ExceptionsText, [Parameter(Mandatory)][string]$ModId,
          [Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$TransitionProofs, [switch]$AllRows)
    $data = ConvertFrom-VtExceptionPinText $ExceptionsText
    $declarations = @(Get-VtReviewedRouteTransitionDeclarations $data)
    if ($declarations.Count -ne $TransitionProofs.Count) { throw '[route-transition] exact constructed proof set required' }
    $selected = $null
    foreach ($declaration in $declarations) {
        $id = [string]$declaration.ModId
        if (-not $TransitionProofs.ContainsKey($id)) { throw '[route-transition] exact constructed proof set required' }
        $proof = $TransitionProofs[$id]
        if ($null -eq $proof -or [string]$proof.ModId -cne $id -or
            [string]$proof.SourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
            -not (Test-VtRouteTransitionDataEqual $declaration $proof.Declaration)) {
            throw '[route-transition] declaration differs from constructed proof'
        }
        if ($AllRows -or $id -ceq $ModId) {
            $rows = @(Assert-VtReviewedRouteTransitionRows $data $id $proof.FromTree $proof.ToTree)
            if (-not (Test-VtRouteTransitionDataEqual $rows $proof.Rows)) { throw '[route-transition] planned rows differ from constructed proof' }
        }
        if ($id -ceq $ModId) { $selected = $proof }
    }
    return $selected
}

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
#     unmarked multi-tree array collapses to the single deployed tree. #1777
#     explicitly reviewed route pairs alone may retain an unused member after
#     committed source/receipt/pair proof; the manifest still selects authority.
#   * The rewrite is verified by re-parsing: any pin for this mod that still
#     lacks the deployed tree is returned in .Unresolved for a loud warning.
function Get-VtExceptionPinRepointPlan {
    param(
        [Parameter(Mandatory=$true)][string]$ExceptionsText,
        [Parameter(Mandatory=$true)][string]$ModId,
        [Parameter(Mandatory=$true)][string]$DeployedTree,
        [hashtable]$TransitionProofs = @{}
    )
    if ($DeployedTree -notmatch '^[0-9a-f]{40}$') { throw "Deployed tree must be a full 40-hex hash, got '$DeployedTree'." }
    if ($ModId -notmatch '^[A-Za-z0-9_]+$') { throw "Exception ModId must be a bare identifier, got '$ModId'." }

    # Bind the actual text being planned, including the primary destination.
    # An active declaration without constructor-produced facts cannot fall back.
    $transition = Get-VtReviewedRoutePlanningTransition -ExceptionsText $ExceptionsText -ModId $ModId -TransitionProofs $TransitionProofs
    function Get-PinTuples {
        param([string]$Text)
        $data = ConvertFrom-VtExceptionPinText $Text
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
    if ($transition -and @($transition.FromTree,$transition.ToTree) -ccontains $DeployedTree) {
        return [pscustomobject]@{
            PinCount=$pins.Count; StaleTrees=@(); Changed=$false; RewriteCount=0
            NewText=$ExceptionsText; Unresolved=@()
        }
    }
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

# Internal byte writer shared by the individually authorized live finalizer and
# canonical-entry recovery. It grants no lease, source, or publication authority.
function Write-VtExceptionPinBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][byte[]]$OriginalBytes,
        [Parameter(Mandatory)][string]$NewText
    )
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Exception pins cannot be a reparse point.' }
    $encoding = New-Object Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes($NewText)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.pending'
    try {
        [IO.File]::WriteAllBytes($temporary, $bytes)
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($temporary)) -cne [Convert]::ToBase64String($bytes)) {
            throw 'Exception-pin staged bytes failed readback.'
        }
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -cne [Convert]::ToBase64String($OriginalBytes)) {
            throw 'Exception pins changed during reconciliation; preserving the newer file.'
        }
        [IO.File]::Replace($temporary, $Path, [NullString]::Value)
        if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -cne [Convert]::ToBase64String($bytes)) {
            throw 'Exception-pin persisted bytes failed readback.'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
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
    $transitionProofs = New-VtReviewedRouteTransitionProofs -RepoRoot $record.RepoRoot -SourceCommit $record.SourceCommit -ExceptionsText $text
    $plan = Get-VtExceptionPinRepointPlan -ExceptionsText $text -ModId $record.ModId -DeployedTree $record.ModTree -TransitionProofs $transitionProofs
    if (@($plan.Unresolved).Count -gt 0) {
        throw "Exception pins remain unresolved; original bytes retained: $($plan.Unresolved -join ', ')"
    }
    if ($plan.Changed) {
        Write-VtExceptionPinBytes -Path $path -OriginalBytes $original -NewText $plan.NewText
        Write-Host ("  GitHub source pins: {0} value(s) for {1} -> {2}." -f $plan.RewriteCount, $record.ModId, $record.ModTree) -ForegroundColor Yellow
        Write-Host '  Carry the working-tree pin change in the next reviewed PR; this is NOT Workshop/test-readiness evidence.' -ForegroundColor Yellow
    }
    return [pscustomobject]@{
        Completed = $true; Changed = [bool]$plan.Changed; PinCount = $plan.PinCount
        Summary = $(if ($plan.Changed) { "repointed $($plan.RewriteCount) values (working tree; carry in next PR)" } else { "current ($($plan.PinCount) pin groups)" })
    }
}
