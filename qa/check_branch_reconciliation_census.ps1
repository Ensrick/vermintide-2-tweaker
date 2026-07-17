# check_branch_reconciliation_census.ps1
#
# Offline schema/freshness gate for issue #625's committed branch census.
# CI clones commonly omit local agent/* refs and most remote tracking refs, so
# this check deliberately does NOT regenerate the census. It validates the
# committed snapshot's schema, internal classifier proofs, age, generator hash,
# and JSON/Markdown fingerprint parity without assuming any refs exist locally.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ReportPath,
    [string]$MarkdownPath,
    [ValidateRange(1, 365)][int]$MaxAgeDays = 14,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$generatorRelative = 'tools/github/branch-reconciliation-census.ps1'

function Get-StringSha256([string]$Text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Get-FileSha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $normalized = ($text -replace "`r`n", "`n") -replace "`r", "`n"
    return Get-StringSha256 $normalized
}

function Get-CensusFailures {
    param(
        $Report,
        [string]$Markdown,
        [string]$Root,
        [datetime]$NowUtc,
        [int]$AllowedAgeDays
    )
    $NowUtc = $NowUtc.ToUniversalTime()
    $failures = @()
    if ($null -eq $Report) { return @('report is null') }
    if ([int]$Report.schema_version -ne 1) { $failures += 'schema_version must be 1' }
    if ([string]$Report.report_kind -ne 'branch-reconciliation-census') { $failures += 'report_kind mismatch' }
    if ($Report.report_only -ne $true) { $failures += 'report_only must be true' }
    if ([string]$Report.base.commit -notmatch '^[0-9a-f]{40}$') { $failures += 'base.commit is not a full SHA-1' }
    if ([string]$Report.census_fingerprint -notmatch '^[0-9a-f]{64}$') { $failures += 'census_fingerprint is not SHA-256' }
    if ([string]$Report.source.ref_inventory_sha256 -notmatch '^[0-9a-f]{64}$') { $failures += 'ref_inventory_sha256 is not SHA-256' }

    $generated = [datetime]::MinValue
    # PowerShell 7 ConvertFrom-Json materializes ISO timestamps as DateTime;
    # Windows PowerShell 5.1 leaves them as strings. Casting the PS7 DateTime
    # back to [string] drops the UTC suffix under the current culture and can
    # create a false future-date result, so preserve typed dates directly.
    if ($Report.generated_at_utc -is [datetime]) {
        $generated = ([datetime]$Report.generated_at_utc).ToUniversalTime()
        $parsed = $true
    } else {
        $parsed = [datetime]::TryParse(
            [string]$Report.generated_at_utc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$generated)
    }
    if (-not $parsed) {
        $failures += 'generated_at_utc is invalid'
    } else {
        $generated = $generated.ToUniversalTime()
        if ($generated -gt $NowUtc.AddMinutes(10)) { $failures += 'generated_at_utc is in the future' }
        if ($generated -lt $NowUtc.AddDays(-$AllowedAgeDays)) { $failures += "census is older than $AllowedAgeDays days" }
    }

    if ([string]$Report.generator.path -ne $generatorRelative) {
        $failures += 'generator.path mismatch'
    } else {
        $generatorPath = Join-Path $Root ($generatorRelative -replace '/', [IO.Path]::DirectorySeparatorChar)
        $liveHash = Get-FileSha256 $generatorPath
        if (-not $liveHash) { $failures += 'generator script is missing' }
        elseif ([string]$Report.generator.sha256 -ne $liveHash) { $failures += 'generator hash is stale; regenerate the census' }
    }

    $allowedAutomatic = @('integrated-ancestor', 'patch-equivalent')
    $actualAutomatic = @($Report.disposition_policy.automatic_states | ForEach-Object { [string]$_ } | Sort-Object -Unique)
    if ($actualAutomatic.Count -ne 2 -or
            @($actualAutomatic | Where-Object { $allowedAutomatic -contains $_ }).Count -ne 2 -or
            [string]$Report.disposition_policy.manual_state -ne 'review-required') {
        $failures += 'disposition policy drifted'
    }

    $tips = @($Report.tips)
    $tipSeen = @{}
    $refSeen = @{}
    $aliasTotal = 0
    $counts = @{ 'integrated-ancestor' = 0; 'patch-equivalent' = 0; 'review-required' = 0 }
    foreach ($tip in $tips) {
        $sha = [string]$tip.tip
        if ($sha -notmatch '^[0-9a-f]{40}$') { $failures += "invalid tip sha: $sha" }
        elseif ($tipSeen.ContainsKey($sha)) { $failures += "duplicate tip record: $sha" }
        else { $tipSeen[$sha] = $true }

        $aliases = @($tip.aliases)
        $aliasTotal += $aliases.Count
        if ([int]$tip.identical_tip_ref_count -ne $aliases.Count) {
            $failures += "$sha identical_tip_ref_count mismatch"
        }
        if ($aliases.Count -eq 0) { $failures += "$sha has no aliases" }
        $aliasNames = @()
        foreach ($alias in $aliases) {
            $ref = [string]$alias.ref
            $aliasNames += $ref
            if ($ref -notmatch '^refs/heads/(?:agent|codex)/.+' -and
                    $ref -notmatch '^refs/remotes/[^/]+/(?:agent|codex)/.+') {
                $failures += "$sha has out-of-scope ref $ref"
            }
            if ($refSeen.ContainsKey($ref)) { $failures += "ref appears in multiple tips: $ref" }
            else { $refSeen[$ref] = $sha }
        }
        if ($aliasNames -notcontains [string]$tip.primary_ref) { $failures += "$sha primary_ref is not an alias" }

        $state = [string]$tip.disposition.state
        if (-not $counts.ContainsKey($state)) {
            $failures += "$sha has unknown disposition $state"
            continue
        }
        $counts[$state]++
        if ($state -eq 'integrated-ancestor') {
            if ($tip.disposition.automatic -ne $true -or
                    $tip.ancestry.tip_is_ancestor_of_base -ne $true) {
                $failures += "$sha ancestor disposition lacks exact ancestry proof"
            }
        } elseif ($state -eq 'patch-equivalent') {
            if ($tip.disposition.automatic -ne $true -or
                    $tip.cherry.pure_patch_equivalent -ne $true -or
                    $tip.cherry.complete -ne $true -or
                    [int]$tip.cherry.plus_unique_count -ne 0 -or
                    [int]$tip.cherry.merge_commit_count -ne 0 -or
                    [int]$tip.cherry.minus_equivalent_count -le 0) {
                $failures += "$sha patch-equivalent disposition lacks complete git-cherry proof"
            }
        } else {
            if ($tip.disposition.automatic -ne $false) { $failures += "$sha review-required was marked automatic" }
            if (-not [string]$tip.disposition.reason) { $failures += "$sha review-required has no reason" }
        }
    }

    if ([int]$Report.source.unique_tip_count -ne $tips.Count) { $failures += 'source.unique_tip_count mismatch' }
    if ([int]$Report.source.ref_count -ne $aliasTotal) { $failures += 'source.ref_count mismatch' }
    if ([int]$Report.source.identical_tip_refs_collapsed -ne ($aliasTotal - $tips.Count)) {
        $failures += 'source.identical_tip_refs_collapsed mismatch'
    }
    if ([int]$Report.summary.integrated_ancestor -ne $counts['integrated-ancestor'] -or
            [int]$Report.summary.patch_equivalent -ne $counts['patch-equivalent'] -or
            [int]$Report.summary.review_required -ne $counts['review-required']) {
        $failures += 'summary disposition counts mismatch'
    }

    if (-not $Markdown) {
        $failures += 'markdown census is empty'
    } else {
        if (-not $Markdown.Contains([string]$Report.census_fingerprint)) { $failures += 'markdown fingerprint mismatch' }
        if (-not $Markdown.Contains([string]$Report.base.commit)) { $failures += 'markdown base commit mismatch' }
        if (-not $Markdown.Contains('Report-only')) { $failures += 'markdown lost report-only warning' }
    }
    return @($failures)
}

function Invoke-CheckSelfTest {
    $script:Tests = 0
    $script:Passed = 0
    function Assert([bool]$Condition, [string]$Name) {
        $script:Tests++
        if ($Condition) { $script:Passed++; Write-Host "  ok  $Name" -ForegroundColor Green }
        else { Write-Host "  FAIL $Name" -ForegroundColor Red }
    }
    function Clone($Value) { return (($Value | ConvertTo-Json -Depth 20) | ConvertFrom-Json) }

    $generatorPath = Join-Path $RepoRoot ($generatorRelative -replace '/', [IO.Path]::DirectorySeparatorChar)
    $now = [datetime]::SpecifyKind([datetime]'2026-07-17T12:00:00', [DateTimeKind]::Utc)
    $report = [PSCustomObject][ordered]@{
        schema_version = 1
        report_kind = 'branch-reconciliation-census'
        generated_at_utc = '2026-07-17T11:00:00.0000000Z'
        report_only = $true
        generator = [PSCustomObject][ordered]@{ path = $generatorRelative; sha256 = Get-FileSha256 $generatorPath }
        base = [PSCustomObject][ordered]@{ requested_ref = 'origin/master'; commit = ('a' * 40) }
        source = [PSCustomObject][ordered]@{
            ref_patterns = @('refs/heads/agent/*')
            ref_count = 2
            unique_tip_count = 2
            identical_tip_refs_collapsed = 0
            ref_inventory_sha256 = ('b' * 64)
        }
        summary = [PSCustomObject][ordered]@{ integrated_ancestor = 1; patch_equivalent = 0; review_required = 1 }
        census_fingerprint = ('c' * 64)
        disposition_policy = [PSCustomObject][ordered]@{
            automatic_states = @('integrated-ancestor', 'patch-equivalent')
            manual_state = 'review-required'
        }
        tips = @(
            [PSCustomObject][ordered]@{
                tip = ('d' * 40); primary_ref = 'refs/heads/agent/done'; identical_tip_ref_count = 1
                aliases = @([PSCustomObject]@{ ref = 'refs/heads/agent/done'; short_name = 'agent/done'; kind = 'local'; remote = $null })
                ancestry = [PSCustomObject]@{ tip_is_ancestor_of_base = $true }
                cherry = [PSCustomObject]@{ pure_patch_equivalent = $false; complete = $true; plus_unique_count = 0; minus_equivalent_count = 0; merge_commit_count = 0 }
                disposition = [PSCustomObject]@{ state = 'integrated-ancestor'; automatic = $true; reason = 'tip-is-ancestor-of-base' }
            },
            [PSCustomObject][ordered]@{
                tip = ('e' * 40); primary_ref = 'refs/heads/codex/review'; identical_tip_ref_count = 1
                aliases = @([PSCustomObject]@{ ref = 'refs/heads/codex/review'; short_name = 'codex/review'; kind = 'local'; remote = $null })
                ancestry = [PSCustomObject]@{ tip_is_ancestor_of_base = $false }
                cherry = [PSCustomObject]@{ pure_patch_equivalent = $false; complete = $true; plus_unique_count = 1; minus_equivalent_count = 0; merge_commit_count = 0 }
                disposition = [PSCustomObject]@{ state = 'review-required'; automatic = $false; reason = 'not-proven' }
            }
        )
    }
    $md = "# Census`n`nReport-only $($report.base.commit) $($report.census_fingerprint)`n"
    $validFailures = @(Get-CensusFailures $report $md $RepoRoot $now 14)
    if ($validFailures.Count -gt 0) {
        foreach ($failure in $validFailures) { Write-Host "    diagnostic: $failure" -ForegroundColor DarkYellow }
    }
    Assert ($validFailures.Count -eq 0) 'valid offline snapshot passes without git refs'

    $badAuto = Clone $report
    $badAuto.tips[1].disposition.state = 'patch-equivalent'
    $badAuto.tips[1].disposition.automatic = $true
    $badAuto.summary.review_required = 0
    $badAuto.summary.patch_equivalent = 1
    Assert (@((Get-CensusFailures $badAuto $md $RepoRoot $now 14) | Where-Object { $_ -match 'git-cherry proof' }).Count -eq 1) 'semantic work cannot claim patch-equivalent without proof'

    $stale = Clone $report
    $stale.generated_at_utc = '2026-06-01T00:00:00Z'
    Assert (@((Get-CensusFailures $stale $md $RepoRoot $now 14) | Where-Object { $_ -match 'older than' }).Count -eq 1) 'stale timestamp is rejected'

    $duplicate = Clone $report
    $duplicate.tips[1].aliases[0].ref = 'refs/heads/agent/done'
    Assert (@((Get-CensusFailures $duplicate $md $RepoRoot $now 14) | Where-Object { $_ -match 'multiple tips' }).Count -eq 1) 'duplicate ref ownership is rejected'

    $badHash = Clone $report
    $badHash.generator.sha256 = ('0' * 64)
    Assert (@((Get-CensusFailures $badHash $md $RepoRoot $now 14) | Where-Object { $_ -match 'generator hash' }).Count -eq 1) 'generator change requires regeneration'

    $lineEndingRoot = Join-Path ([IO.Path]::GetTempPath()) ('branch_census_hash_' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $lineEndingRoot | Out-Null
    try {
        $lfPath = Join-Path $lineEndingRoot 'lf.ps1'
        $crlfPath = Join-Path $lineEndingRoot 'crlf.ps1'
        [IO.File]::WriteAllText($lfPath, "one`ntwo`n", (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($crlfPath, "one`r`ntwo`r`n", (New-Object Text.UTF8Encoding($false)))
        Assert ((Get-FileSha256 $lfPath) -eq (Get-FileSha256 $crlfPath)) 'generator hash is checkout-line-ending independent'
    } finally {
        if (Test-Path -LiteralPath $lineEndingRoot) {
            Remove-Item -LiteralPath $lineEndingRoot -Recurse -Force
        }
    }

    if ($script:Passed -ne $script:Tests) {
        Write-Host "[check_branch_reconciliation_census -SelfTest] FAILED $($script:Passed)/$($script:Tests)" -ForegroundColor Red
        exit 2
    }
    Write-Host "[check_branch_reconciliation_census -SelfTest] OK $($script:Passed)/$($script:Tests)"
    exit 0
}

if ($SelfTest) { Invoke-CheckSelfTest }

if (-not $ReportPath) { $ReportPath = Join-Path $RepoRoot 'docs/generated/BRANCH_RECONCILIATION.generated.json' }
if (-not $MarkdownPath) { $MarkdownPath = Join-Path $RepoRoot 'docs/generated/BRANCH_RECONCILIATION.generated.md' }
$errors = @()
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
    $errors += "missing report: $ReportPath"
} elseif (-not (Test-Path -LiteralPath $MarkdownPath -PathType Leaf)) {
    $errors += "missing markdown: $MarkdownPath"
} else {
    try {
        $report = [IO.File]::ReadAllText($ReportPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $markdown = [IO.File]::ReadAllText($MarkdownPath, [Text.Encoding]::UTF8)
        $errors += @(Get-CensusFailures $report $markdown $RepoRoot ([datetime]::UtcNow) $MaxAgeDays)
    } catch {
        $errors += "could not parse census: $_"
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "[check_branch_reconciliation_census] ERROR - $message" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) {
    Write-Host "[check_branch_reconciliation_census] OK - committed census schema, freshness, generator hash, and dispositions are valid (offline)."
}
exit 0
