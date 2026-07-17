# branch-reconciliation-census.ps1
#
# Issue #625: inventory local and remote agent/* + codex/* refs without
# checking out, merging, deleting, pushing, or otherwise mutating any ref.
# Only two conclusions are automatic:
#   * integrated-ancestor -- the exact tip is already an ancestor of base;
#   * patch-equivalent    -- every divergent non-merge patch is `git cherry -`.
# Everything else remains review-required, even when a branch name, issue
# number, version, or changed path makes a semantic conclusion look obvious.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$BaseRef = 'origin/master',
    [string]$OutputPath,
    [string]$MarkdownPath,
    [switch]$NoWrite,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$script:ToolSchemaVersion = 1
$script:ToolRelativePath = 'tools/github/branch-reconciliation-census.ps1'
$script:GitRepo = $null

function Get-StringSha256([string]$Text) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    # Git may materialize PowerShell files as LF or CRLF depending on host
    # checkout settings. Hash canonical text so the committed snapshot remains
    # valid across Windows PowerShell and pwsh/Linux checkouts.
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $normalized = ($text -replace "`r`n", "`n") -replace "`r", "`n"
    return Get-StringSha256 $normalized
}

function Invoke-GitLines {
    param(
        [Parameter(Mandatory)][string[]]$GitArgs,
        [switch]$AllowFailure
    )
    # Windows PowerShell 5.1 promotes native stderr to a terminating
    # NativeCommandError under Stop. Temporarily collect it as ordinary output
    # so allowed probes such as merge-base exit 1 remain inspectable.
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = @(& git -C $script:GitRepo @GitArgs 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    $lines = @($raw | ForEach-Object { [string]$_ })
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($GitArgs -join ' ') failed (exit $code): $($lines -join '; ')"
    }
    return [PSCustomObject]@{
        code = $code
        lines = $lines
        text = ($lines -join "`n")
    }
}

function Get-UniqueSortedStrings($Values) {
    return @($Values | Where-Object { $_ -ne $null -and [string]$_ -ne '' } |
        ForEach-Object { [string]$_ } | Sort-Object -Unique)
}

function Get-GitPathList([string]$From, [string]$To) {
    if (-not $From -or -not $To) { return @() }
    $result = Invoke-GitLines -GitArgs @('diff', '--name-only', "$From..$To", '--') -AllowFailure
    if ($result.code -ne 0) { return @() }
    return @(Get-UniqueSortedStrings $result.lines)
}

function Get-IssueNumbers([string[]]$Texts) {
    $numbers = New-Object System.Collections.Generic.List[int]
    foreach ($text in @($Texts)) {
        if (-not $text) { continue }
        foreach ($match in [regex]::Matches($text, '(?<![A-Za-z0-9])#(?<n>\d{1,5})')) {
            $numbers.Add([int]$match.Groups['n'].Value)
        }
        foreach ($match in [regex]::Matches($text, '(?i)\bissue\s*#?\s*(?<n>\d{1,5})\b')) {
            $numbers.Add([int]$match.Groups['n'].Value)
        }
        foreach ($match in [regex]::Matches($text,
                '(?i)(?:^|[/_-])(?:issue|fix|bug|gh)[_-]?(?<n>\d{2,5})(?:$|[/_-])')) {
            $numbers.Add([int]$match.Groups['n'].Value)
        }
        foreach ($match in [regex]::Matches($text,
                '(?i)^refs/(?:heads|remotes/[^/]+)/(?:agent|codex)/(?<n>\d{2,5})(?:$|[/_-])')) {
            $numbers.Add([int]$match.Groups['n'].Value)
        }
    }
    return @($numbers | Sort-Object -Unique)
}

function Get-TrackedRefs {
    $result = Invoke-GitLines -GitArgs @(
        'for-each-ref', '--format=%(refname)%09%(objectname)',
        'refs/heads/agent/', 'refs/heads/codex/', 'refs/remotes/'
    )
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in $result.lines) {
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $ref = $parts[0]
        $tip = $parts[1].ToLowerInvariant()
        $kind = $null
        $short = $null
        $remote = $null
        if ($ref -match '^refs/heads/(?<name>(?:agent|codex)/.+)$') {
            $kind = 'local'
            $short = $matches['name']
        } elseif ($ref -match '^refs/remotes/(?<remote>[^/]+)/(?<name>(?:agent|codex)/.+)$') {
            $kind = 'remote'
            $remote = $matches['remote']
            $short = "$remote/$($matches['name'])"
        } else {
            continue
        }
        if ($ref -match '/HEAD$' -or $tip -notmatch '^[0-9a-f]{40}$') { continue }
        $rows.Add([ordered]@{
            ref = $ref
            short_name = $short
            kind = $kind
            remote = $remote
            tip = $tip
        })
    }
    return @($rows | Sort-Object ref)
}

function Get-CommitRows([string]$BaseCommit, [string]$Tip, $PatchStatus) {
    $range = "$BaseCommit..$Tip"
    $log = Invoke-GitLines -GitArgs @(
        'log', '--reverse', '--format=%H%x09%P%x09%aI%x09%s', $range, '--'
    ) -AllowFailure
    if ($log.code -ne 0) { return @() }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in $log.lines) {
        $parts = $line -split "`t", 4
        if ($parts.Count -lt 4) { continue }
        $parents = @($parts[1] -split '\s+' | Where-Object { $_ })
        $sha = $parts[0].ToLowerInvariant()
        $status = 'not-evaluated'
        if ($PatchStatus.ContainsKey($sha)) { $status = $PatchStatus[$sha] }
        elseif ($parents.Count -gt 1) { $status = 'merge-commit' }
        $rows.Add([ordered]@{
            sha = $sha
            parents = $parents
            author_date_utc = $parts[2]
            subject = $parts[3]
            patch_status = $status
            issue_refs = @(Get-IssueNumbers @($parts[3]))
        })
    }
    return $rows.ToArray()
}

function Get-Disposition {
    param(
        [bool]$TipIsAncestor,
        [bool]$PurePatchEquivalent,
        [bool]$HasMergeBase,
        [int]$Ahead,
        [int]$Behind,
        [int]$PlusCount,
        [int]$MergeCommitCount,
        [int]$OverlapCount,
        [int]$VersionPathCount,
        [bool]$CherryComplete
    )
    if ($TipIsAncestor) {
        return [ordered]@{
            state = 'integrated-ancestor'
            automatic = $true
            reason = 'tip-is-ancestor-of-base'
            review_signals = @()
        }
    }
    if ($PurePatchEquivalent) {
        return [ordered]@{
            state = 'patch-equivalent'
            automatic = $true
            reason = 'all-divergent-nonmerge-patches-are-git-cherry-minus'
            review_signals = @()
        }
    }
    $signals = New-Object System.Collections.Generic.List[string]
    if (-not $HasMergeBase) { $signals.Add('unrelated-history') }
    if ($Ahead -gt 0) { $signals.Add('ahead-of-base') }
    if ($Behind -gt 0) { $signals.Add('diverged-from-current-base') }
    if ($PlusCount -gt 0) { $signals.Add('unique-patches') }
    if ($MergeCommitCount -gt 0) { $signals.Add('merge-commits-require-semantic-review') }
    if ($OverlapCount -gt 0) { $signals.Add('current-source-overlap') }
    if ($VersionPathCount -gt 0) { $signals.Add('version-or-manifest-paths') }
    if (-not $CherryComplete) { $signals.Add('patch-equivalence-incomplete') }
    if ($signals.Count -eq 0) { $signals.Add('semantic-disposition-not-proven') }
    return [ordered]@{
        state = 'review-required'
        automatic = $false
        reason = 'not-proven-by-ancestry-or-pure-patch-equivalence'
        review_signals = @($signals | Sort-Object -Unique)
    }
}

function Invoke-BranchCensus {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$CanonicalBase,
        [datetime]$GeneratedAtUtc = ([datetime]::UtcNow)
    )
    $script:GitRepo = (Resolve-Path -LiteralPath $RepositoryRoot).Path
    $inside = Invoke-GitLines -GitArgs @('rev-parse', '--is-inside-work-tree')
    if ($inside.text.Trim() -ne 'true') { throw "$RepositoryRoot is not a git worktree" }
    $baseResult = Invoke-GitLines -GitArgs @('rev-parse', "$CanonicalBase^{commit}")
    $baseCommit = $baseResult.text.Trim().ToLowerInvariant()
    if ($baseCommit -notmatch '^[0-9a-f]{40}$') { throw "base ref did not resolve to a commit: $CanonicalBase" }

    $refs = @(Get-TrackedRefs)
    $byTip = @{}
    foreach ($ref in $refs) {
        if (-not $byTip.ContainsKey($ref.tip)) {
            $byTip[$ref.tip] = New-Object System.Collections.Generic.List[object]
        }
        $byTip[$ref.tip].Add($ref)
    }

    $tipRows = New-Object System.Collections.Generic.List[object]
    foreach ($tip in @($byTip.Keys | Sort-Object)) {
        $aliases = @($byTip[$tip] | Sort-Object @{ Expression = { if ($_.kind -eq 'local') { 0 } else { 1 } } }, short_name)
        $primary = $aliases[0]
        $tipAncestorResult = Invoke-GitLines -GitArgs @('merge-base', '--is-ancestor', $tip, $baseCommit) -AllowFailure
        $baseAncestorResult = Invoke-GitLines -GitArgs @('merge-base', '--is-ancestor', $baseCommit, $tip) -AllowFailure
        $tipIsAncestor = $tipAncestorResult.code -eq 0
        $baseIsAncestor = $baseAncestorResult.code -eq 0
        $mergeBaseResult = Invoke-GitLines -GitArgs @('merge-base', $baseCommit, $tip) -AllowFailure
        $mergeBase = if ($mergeBaseResult.code -eq 0) { $mergeBaseResult.text.Trim().ToLowerInvariant() } else { $null }
        $hasMergeBase = [bool]($mergeBase -and $mergeBase -match '^[0-9a-f]{40}$')

        $ahead = 0
        $behind = 0
        $countsResult = Invoke-GitLines -GitArgs @('rev-list', '--left-right', '--count', "$baseCommit...$tip") -AllowFailure
        if ($countsResult.code -eq 0 -and $countsResult.text -match '^\s*(\d+)\s+(\d+)\s*$') {
            $behind = [int]$matches[1]
            $ahead = [int]$matches[2]
        }

        $patchStatus = @{}
        $plusCount = 0
        $minusCount = 0
        $cherryResult = if ($hasMergeBase) {
            Invoke-GitLines -GitArgs @('cherry', '-v', $baseCommit, $tip) -AllowFailure
        } else {
            [PSCustomObject]@{ code = 1; lines = @(); text = '' }
        }
        if ($cherryResult.code -eq 0) {
            foreach ($line in $cherryResult.lines) {
                if ($line -match '^(?<sign>[+-])\s+(?<sha>[0-9a-fA-F]{40})(?:\s|$)') {
                    $sha = $matches['sha'].ToLowerInvariant()
                    if ($matches['sign'] -eq '+') {
                        $patchStatus[$sha] = 'unique'
                        $plusCount++
                    } else {
                        $patchStatus[$sha] = 'equivalent'
                        $minusCount++
                    }
                }
            }
        }

        $commits = @(Get-CommitRows $baseCommit $tip $patchStatus)
        $branchOnlyCount = $commits.Count
        $mergeCommitCount = @($commits | Where-Object { @($_.parents).Count -gt 1 }).Count
        $nonMergeCount = $branchOnlyCount - $mergeCommitCount
        $cherryComplete = $cherryResult.code -eq 0 -and ($plusCount + $minusCount) -eq $nonMergeCount
        $purePatchEquivalent = $branchOnlyCount -gt 0 -and $mergeCommitCount -eq 0 -and
            $plusCount -eq 0 -and $minusCount -eq $branchOnlyCount -and $cherryComplete

        $changedPaths = if ($hasMergeBase) { @(Get-GitPathList $mergeBase $tip) } else { @() }
        $currentPaths = if ($hasMergeBase) { @(Get-GitPathList $mergeBase $baseCommit) } else { @() }
        $currentSet = @{}
        foreach ($path in $currentPaths) { $currentSet[$path] = $true }
        $overlap = @($changedPaths | Where-Object { $currentSet.ContainsKey($_) } | Sort-Object -Unique)
        $versionPaths = @($changedPaths | Where-Object {
            $_ -match '(^|/)CHANGELOG\.md$' -or
            $_ -match '(^|/)itemV2\.cfg$' -or
            $_ -match '(^|/)PUBLISHED_IDS\.md$' -or
            $_ -match '(^|/)tools/mod-inventory\.psd1$' -or
            $_ -match '(^|/)tools/release-manifest\.json$' -or
            $_ -match '(^|/)bundleV2/'
        } | Sort-Object -Unique)
        $manifestPaths = @($changedPaths | Where-Object {
            $_ -match '(^|/)itemV2\.cfg$' -or
            $_ -match '(^|/)bundleV2/' -or
            $_ -match '(^|/)resource_packages/' -or
            $_ -match '(^|/)PUBLISHED_IDS\.md$' -or
            $_ -match '(^|/)tools/mod-inventory\.psd1$'
        } | Sort-Object -Unique)

        $issueTexts = New-Object System.Collections.Generic.List[string]
        foreach ($alias in $aliases) { $issueTexts.Add([string]$alias.ref) }
        foreach ($commit in $commits) { $issueTexts.Add([string]$commit.subject) }
        $bodyResult = Invoke-GitLines -GitArgs @('log', '--format=%B', "$baseCommit..$tip", '--') -AllowFailure
        if ($bodyResult.code -eq 0) { $issueTexts.Add($bodyResult.text) }
        $issueRefs = @(Get-IssueNumbers $issueTexts)

        $tipMetaResult = Invoke-GitLines -GitArgs @('show', '-s', '--format=%cI%x09%an%x09%s', $tip)
        $tipMeta = $tipMetaResult.text -split "`t", 3
        $disposition = Get-Disposition -TipIsAncestor $tipIsAncestor `
            -PurePatchEquivalent $purePatchEquivalent -HasMergeBase $hasMergeBase `
            -Ahead $ahead -Behind $behind -PlusCount $plusCount `
            -MergeCommitCount $mergeCommitCount -OverlapCount $overlap.Count `
            -VersionPathCount $versionPaths.Count -CherryComplete $cherryComplete

        $tipRows.Add([ordered]@{
            tip = $tip
            primary_ref = $primary.ref
            aliases = @($aliases | ForEach-Object {
                [ordered]@{
                    ref = $_.ref
                    short_name = $_.short_name
                    kind = $_.kind
                    remote = $_.remote
                }
            })
            identical_tip_ref_count = $aliases.Count
            tip_metadata = [ordered]@{
                committed_at_utc = if ($tipMeta.Count -ge 1) { $tipMeta[0] } else { $null }
                author = if ($tipMeta.Count -ge 2) { $tipMeta[1] } else { $null }
                subject = if ($tipMeta.Count -ge 3) { $tipMeta[2] } else { $null }
            }
            ancestry = [ordered]@{
                merge_base = $mergeBase
                has_common_history = $hasMergeBase
                tip_is_ancestor_of_base = $tipIsAncestor
                base_is_ancestor_of_tip = $baseIsAncestor
            }
            ahead_behind = [ordered]@{
                ahead = $ahead
                behind = $behind
            }
            cherry = [ordered]@{
                plus_unique_count = $plusCount
                minus_equivalent_count = $minusCount
                evaluated_nonmerge_count = $plusCount + $minusCount
                nonmerge_commit_count = $nonMergeCount
                merge_commit_count = $mergeCommitCount
                complete = $cherryComplete
                pure_patch_equivalent = $purePatchEquivalent
            }
            issue_refs = $issueRefs
            changed_paths = $changedPaths
            # The exact overlap is the actionable signal. Recording the full
            # base-side path set once per tip repeated ~155k entries in the
            # real census without adding branch-specific evidence.
            current_source_changed_path_count = $currentPaths.Count
            current_source_overlap = $overlap
            version_paths = $versionPaths
            manifest_paths = $manifestPaths
            divergent_commits = $commits
            disposition = $disposition
        })
    }

    $inventoryLines = @($refs | ForEach-Object { "$($_.ref)=$($_.tip)" } | Sort-Object)
    $stateCounts = [ordered]@{
        integrated_ancestor = @($tipRows | Where-Object { $_.disposition.state -eq 'integrated-ancestor' }).Count
        patch_equivalent = @($tipRows | Where-Object { $_.disposition.state -eq 'patch-equivalent' }).Count
        review_required = @($tipRows | Where-Object { $_.disposition.state -eq 'review-required' }).Count
    }
    $fingerprintLines = New-Object System.Collections.Generic.List[string]
    $fingerprintLines.Add("base=$baseCommit")
    foreach ($row in $tipRows) {
        $aliasText = @($row.aliases | ForEach-Object { $_.ref } | Sort-Object) -join ','
        $fingerprintLines.Add((
            '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f
            $row.tip, $aliasText, $row.disposition.state,
            $row.ahead_behind.ahead, $row.ahead_behind.behind,
            $row.cherry.plus_unique_count, $row.cherry.minus_equivalent_count,
            @($row.current_source_overlap).Count
        ))
    }
    $toolPath = Join-Path $RepositoryRoot ($script:ToolRelativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    return [ordered]@{
        schema_version = $script:ToolSchemaVersion
        report_kind = 'branch-reconciliation-census'
        generated_at_utc = $GeneratedAtUtc.ToUniversalTime().ToString('o')
        report_only = $true
        generator = [ordered]@{
            path = $script:ToolRelativePath
            sha256 = Get-FileSha256 $toolPath
        }
        base = [ordered]@{
            requested_ref = $CanonicalBase
            commit = $baseCommit
        }
        source = [ordered]@{
            ref_patterns = @('refs/heads/agent/*', 'refs/heads/codex/*', 'refs/remotes/*/agent/*', 'refs/remotes/*/codex/*')
            ref_count = $refs.Count
            unique_tip_count = $tipRows.Count
            identical_tip_refs_collapsed = $refs.Count - $tipRows.Count
            ref_inventory_sha256 = Get-StringSha256 ($inventoryLines -join "`n")
        }
        summary = $stateCounts
        census_fingerprint = Get-StringSha256 ($fingerprintLines -join "`n")
        disposition_policy = [ordered]@{
            automatic_states = @('integrated-ancestor', 'patch-equivalent')
            manual_state = 'review-required'
            note = 'No semantic, version, diagnostic-only, obsolete, or integration conclusion is automatic.'
        }
        tips = $tipRows.ToArray()
    }
}

function Convert-CensusToMarkdown($Report) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Agent and Codex branch reconciliation census')
    $lines.Add('')
    $lines.Add("Generated: ``$($Report.generated_at_utc)``")
    $lines.Add('')
    $lines.Add("Base: ``$($Report.base.requested_ref)`` at ``$($Report.base.commit)``")
    $lines.Add('')
    $lines.Add("Census fingerprint: ``$($Report.census_fingerprint)``")
    $lines.Add('')
    $lines.Add("Refs: **$($Report.source.ref_count)**; unique tips after deduplication: **$($Report.source.unique_tip_count)**; collapsed aliases: **$($Report.source.identical_tip_refs_collapsed)**.")
    $lines.Add("Disposition: **$($Report.summary.integrated_ancestor)** integrated ancestors, **$($Report.summary.patch_equivalent)** pure patch-equivalent tips, **$($Report.summary.review_required)** requiring review.")
    $lines.Add('')
    $lines.Add('> Report-only. Only exact ancestry and complete `git cherry` patch equivalence are automatic. Every other tip remains review-required; this tool never merges, deletes, checks out, pushes, or edits refs.')
    $lines.Add('')
    $lines.Add('| Disposition | Tip | A/B | Cherry +/- | Overlap | Issues | Refs |')
    $lines.Add('|---|---:|---:|---:|---:|---:|---|')
    foreach ($row in @($Report.tips)) {
        $refs = @($row.aliases | ForEach-Object { $_.short_name }) -join ', '
        $refs = $refs.Replace('|', '\|')
        $issues = if (@($row.issue_refs).Count -gt 0) { '#' + (@($row.issue_refs) -join ', #') } else { '-' }
        $lines.Add(('| {0} | `{1}` | {2}/{3} | {4}/{5} | {6} | {7} | {8} |' -f
            $row.disposition.state, $row.tip.Substring(0, 10),
            $row.ahead_behind.ahead, $row.ahead_behind.behind,
            $row.cherry.plus_unique_count, $row.cherry.minus_equivalent_count,
            @($row.current_source_overlap).Count, $issues, $refs))
    }
    $lines.Add('')
    $lines.Add('The JSON sibling is authoritative and contains aliases, ancestry, commits, paths, overlap, version/manifest signals, and review reasons for every unique tip.')
    return $lines -join [Environment]::NewLine
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-ToolSelfTest {
    $tests = 0
    $passed = 0
    function Assert([bool]$Condition, [string]$Name) {
        $script:SelfTests++
        if ($Condition) {
            $script:SelfPassed++
            Write-Host "  ok  $Name" -ForegroundColor Green
        } else {
            Write-Host "  FAIL $Name" -ForegroundColor Red
        }
    }
    $script:SelfTests = 0
    $script:SelfPassed = 0
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('branch_census_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $fixture | Out-Null
    $savedRepo = $script:GitRepo
    try {
        $script:GitRepo = $fixture
        Invoke-GitLines -GitArgs @('init', '-q') | Out-Null
        Invoke-GitLines -GitArgs @('config', 'user.email', 'fixture@example.invalid') | Out-Null
        Invoke-GitLines -GitArgs @('config', 'user.name', 'Fixture') | Out-Null
        Invoke-GitLines -GitArgs @('config', 'commit.gpgsign', 'false') | Out-Null
        Invoke-GitLines -GitArgs @('config', 'core.autocrlf', 'false') | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture 'shared.txt'), "base`n")
        Invoke-GitLines -GitArgs @('add', 'shared.txt') | Out-Null
        Invoke-GitLines -GitArgs @('commit', '-q', '-m', 'base') | Out-Null
        Invoke-GitLines -GitArgs @('branch', '-M', 'master') | Out-Null
        $base = (Invoke-GitLines -GitArgs @('rev-parse', 'HEAD')).text.Trim()
        Invoke-GitLines -GitArgs @('update-ref', 'refs/heads/agent/ancestor', $base) | Out-Null

        Invoke-GitLines -GitArgs @('checkout', '-q', '-b', 'agent/patch-source', $base) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture 'equivalent.txt'), "same patch`n")
        Invoke-GitLines -GitArgs @('add', 'equivalent.txt') | Out-Null
        Invoke-GitLines -GitArgs @('commit', '-q', '-m', 'fixture equivalent #625') | Out-Null
        $patchTip = (Invoke-GitLines -GitArgs @('rev-parse', 'HEAD')).text.Trim()
        Invoke-GitLines -GitArgs @('update-ref', 'refs/heads/codex/patch-copy', $patchTip) | Out-Null
        Invoke-GitLines -GitArgs @('update-ref', 'refs/remotes/origin/agent/patch-copy', $patchTip) | Out-Null

        Invoke-GitLines -GitArgs @('checkout', '-q', '-b', 'agent/issue-625-unique', $base) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture 'unique.txt'), "unique`n")
        Invoke-GitLines -GitArgs @('add', 'unique.txt') | Out-Null
        Invoke-GitLines -GitArgs @('commit', '-q', '-m', 'unique work #625') | Out-Null

        Invoke-GitLines -GitArgs @('checkout', '-q', '-b', 'codex/fix-777-overlap', $base) | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture 'shared.txt'), "branch change`n")
        Invoke-GitLines -GitArgs @('add', 'shared.txt') | Out-Null
        Invoke-GitLines -GitArgs @('commit', '-q', '-m', 'overlap issue 777') | Out-Null

        Invoke-GitLines -GitArgs @('checkout', '-q', 'master') | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture 'equivalent.txt'), "same patch`n")
        Invoke-GitLines -GitArgs @('add', 'equivalent.txt') | Out-Null
        Invoke-GitLines -GitArgs @('commit', '-q', '-m', 'land equivalent differently') | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture 'shared.txt'), "master change`n")
        Invoke-GitLines -GitArgs @('add', 'shared.txt') | Out-Null
        Invoke-GitLines -GitArgs @('commit', '-q', '-m', 'current source moved') | Out-Null

        $before = (Invoke-GitLines -GitArgs @('show-ref')).text
        $report = Invoke-BranchCensus -RepositoryRoot $fixture -CanonicalBase master `
            -GeneratedAtUtc ([datetime]'2026-07-17T00:00:00Z')
        $after = (Invoke-GitLines -GitArgs @('show-ref')).text

        Assert ($before -eq $after) 'census does not mutate refs'
        Assert ($report.source.ref_count -eq 6) 'local and remote refs are all enumerated'
        Assert ($report.source.unique_tip_count -eq 4) 'identical tips are deduplicated'
        $ancestor = @($report.tips | Where-Object { $_.primary_ref -eq 'refs/heads/agent/ancestor' })[0]
        Assert ($ancestor.disposition.state -eq 'integrated-ancestor') 'ancestor is the first automatic class'
        $patch = @($report.tips | Where-Object { @($_.aliases.ref) -contains 'refs/heads/agent/patch-source' })[0]
        Assert ($patch.identical_tip_ref_count -eq 3) 'same-tip aliases share one record'
        Assert ($patch.disposition.state -eq 'patch-equivalent') 'pure git-cherry minus is the second automatic class'
        Assert ($patch.cherry.plus_unique_count -eq 0 -and $patch.cherry.minus_equivalent_count -eq 1) 'patch signals are explicit'
        $unique = @($report.tips | Where-Object { @($_.issue_refs) -contains 625 -and $_.disposition.state -eq 'review-required' })[0]
        Assert ($null -ne $unique -and @($unique.changed_paths) -contains 'unique.txt') 'unique patch remains review-required with paths and issue ref'
        $overlap = @($report.tips | Where-Object { @($_.issue_refs) -contains 777 })[0]
        Assert ($overlap.disposition.state -eq 'review-required') 'semantic overlap is never auto-classified'
        Assert (@($overlap.current_source_overlap) -contains 'shared.txt') 'current-source overlap is recorded'
        Assert ($overlap.current_source_changed_path_count -gt 0) 'current-source breadth is recorded without repeating every path'

        $jsonPath = Join-Path $fixture 'report.json'
        $mdPath = Join-Path $fixture 'report.md'
        Write-Utf8NoBom $jsonPath (($report | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
        Write-Utf8NoBom $mdPath ((Convert-CensusToMarkdown $report) + [Environment]::NewLine)
        $roundTrip = [IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
        Assert ($roundTrip.schema_version -eq 1 -and $roundTrip.tips.Count -eq 4) 'machine report round-trips under this PowerShell host'
        Assert ([IO.File]::ReadAllText($mdPath).Contains($report.census_fingerprint)) 'markdown carries the machine fingerprint'
        $lfPath = Join-Path $fixture 'hash-lf.ps1'
        $crlfPath = Join-Path $fixture 'hash-crlf.ps1'
        [IO.File]::WriteAllText($lfPath, "one`ntwo`n", (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($crlfPath, "one`r`ntwo`r`n", (New-Object Text.UTF8Encoding($false)))
        Assert ((Get-FileSha256 $lfPath) -eq (Get-FileSha256 $crlfPath)) 'generator hash is portable across LF and CRLF checkouts'
    } finally {
        $script:GitRepo = $savedRepo
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        $fixtureFull = [IO.Path]::GetFullPath($fixture)
        if ($fixtureFull.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
                (Test-Path -LiteralPath $fixtureFull)) {
            Remove-Item -LiteralPath $fixtureFull -Recurse -Force
        }
    }
    if ($script:SelfPassed -ne $script:SelfTests) {
        Write-Host "[branch-reconciliation-census -SelfTest] FAILED $($script:SelfPassed)/$($script:SelfTests)" -ForegroundColor Red
        exit 2
    }
    Write-Host "[branch-reconciliation-census -SelfTest] OK $($script:SelfPassed)/$($script:SelfTests)"
    exit 0
}

if ($SelfTest) {
    Invoke-ToolSelfTest
}

if (-not $RepoRoot) {
    $RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if (-not $OutputPath) { $OutputPath = Join-Path $RepoRoot 'docs/generated/BRANCH_RECONCILIATION.generated.json' }
if (-not $MarkdownPath) { $MarkdownPath = Join-Path $RepoRoot 'docs/generated/BRANCH_RECONCILIATION.generated.md' }

$report = Invoke-BranchCensus -RepositoryRoot $RepoRoot -CanonicalBase $BaseRef
if (-not $NoWrite) {
    Write-Utf8NoBom $OutputPath (($report | ConvertTo-Json -Depth 20) + [Environment]::NewLine)
    Write-Utf8NoBom $MarkdownPath ((Convert-CensusToMarkdown $report) + [Environment]::NewLine)
    Write-Host "[branch-reconciliation-census] wrote $($report.source.unique_tip_count) tips / $($report.source.ref_count) refs"
    Write-Host "[branch-reconciliation-census] json=$OutputPath"
    Write-Host "[branch-reconciliation-census] markdown=$MarkdownPath"
} else {
    Write-Output ($report | ConvertTo-Json -Depth 20)
}
