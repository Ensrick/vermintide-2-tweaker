# Authoritative deployed-source contract for GitHub CURRENT LIVE TEST cards.
#
# The daily release manifest identifies the exact source commit deployed for
# every Workshop item.  Read only the relevant Lua text from those commits so
# a card cannot claim a current-master command or banner that has not actually
# reached the Workshop yet.  This file is dot-sourced by the shared lifecycle
# policy and is deliberately free of GitHub mutation.

$script:VtContractSemverPattern = '\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?'
$script:VtContractTagPattern = '[A-Za-z][A-Za-z0-9_-]*'

function Get-VtOrderedUniqueStrings {
    param([object[]]$Values)
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $result = @()
    foreach ($value in @($Values)) {
        $text = [string]$value
        if ($seen.Add($text)) { $result += $text }
    }
    return @($result)
}

function Invoke-VtContractGit {
    param(
        [string]$RepoRoot,
        [string[]]$Arguments,
        [switch]$AllowNoMatch
    )

    $output = @(& git -C $RepoRoot @Arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not ($AllowNoMatch -and $code -eq 1)) {
        throw "git $($Arguments -join ' ') failed ($code): $($output -join [Environment]::NewLine)"
    }
    return @($output | ForEach-Object { [string]$_ })
}

function Invoke-VtContractDeployedBlobPrefetch {
    param(
        [string]$RepoRoot,
        [object[]]$DeployedTrees
    )

    # In a blob:none partial clone (the dedicated lifecycle CI checkout and
    # the qa.yml checkout), every deployed-tree blob absent from the local
    # object store costs a promisor network fetch inside git show/grep. The
    # 2026-08-13/15 scheduled guard runs exceeded their five-minute ceiling
    # exactly there: 841 deployed blobs were missing under the old qa+tools
    # sparse cone (#750). Enumerate the missing blobs across every deployed
    # source tree first and hydrate them in a few batched fetches, mirroring
    # git's own internal lazy-fetch invocation. Best-effort by design: on any
    # failure the per-object lazy path remains the correctness fallback, only
    # slower, so this warns instead of failing the guard.
    $promisorOutput = @(& git -C $RepoRoot config --get remote.origin.promisor 2>&1)
    if ($LASTEXITCODE -ne 0 -or ([string]$promisorOutput[0]).Trim() -cne 'true') { return }

    $missing = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($target in @($DeployedTrees)) {
        $treeOutput = @(& git -C $RepoRoot rev-parse "$($target.Commit):$($target.Root)" 2>&1)
        # A missing path or commit is reported authoritatively by the main
        # contract pass; the prefetch silently skips it.
        if ($LASTEXITCODE -ne 0 -or $treeOutput.Count -lt 1) { continue }
        $treeId = ([string]$treeOutput[0]).Trim()
        if ($treeId -notmatch '^[0-9a-f]{40,64}$') { continue }
        # --missing=print lists absent objects as ?<oid> without lazy-fetching.
        $objectLines = @(& git -C $RepoRoot rev-list --objects --missing=print $treeId 2>&1)
        if ($LASTEXITCODE -ne 0) { continue }
        foreach ($line in $objectLines) {
            if ([string]$line -match '^\?([0-9a-f]{40,64})$' -and $seen.Add($matches[1])) {
                $missing.Add($matches[1])
            }
        }
    }
    if ($missing.Count -eq 0) { return }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $batches = 0
    for ($offset = 0; $offset -lt $missing.Count; $offset += 200) {
        $last = [Math]::Min($offset + 199, $missing.Count - 1)
        $batch = @($missing[$offset..$last])
        $fetchOutput = @(& git -C $RepoRoot -c fetch.negotiationAlgorithm=noop fetch origin --quiet `
            --no-tags --no-write-fetch-head --recurse-submodules=no --filter=blob:none @batch 2>&1)
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Deployed-blob prefetch batch failed (exit $LASTEXITCODE); falling back to per-blob lazy fetches: $($fetchOutput -join ' ')"
            return
        }
        $batches++
    }
    $stopwatch.Stop()
    Write-Host "[live-test-contract] prefetched $($missing.Count) missing deployed-source blob(s) in $batches batched fetch(es), $([int]$stopwatch.Elapsed.TotalMilliseconds)ms"
}

function Get-VtDeployedSourceContract {
    param(
        [string]$RepoRoot,
        $ReleaseManifest
    )

    if ([string]::IsNullOrWhiteSpace($RepoRoot) -or
        -not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
        throw "Live-test contract RepoRoot is missing: '$RepoRoot'."
    }
    if (-not $ReleaseManifest -or "$($ReleaseManifest.manifest_schema)" -ne '2') {
        throw 'Live-test contract requires a release manifest with manifest_schema=2.'
    }

    $inventoryPath = Join-Path $RepoRoot 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Active mod inventory is missing: $inventoryPath"
    }
    $inventory = Import-PowerShellDataFile $inventoryPath

    $prefetchTargets = @()
    foreach ($mod in @($inventory.Mods)) {
        $workshopId = [string]$mod.WorkshopId
        if ([string]::IsNullOrWhiteSpace($workshopId)) { continue }
        $deployed = @($ReleaseManifest.mods | Where-Object { [string]$_.workshop_id -eq $workshopId })
        if ($deployed.Count -ne 1) { continue }
        $commit = [string]$deployed[0].source_commit
        if ($commit -notmatch '^[0-9a-f]{40}$') { continue }
        $prefetchTargets += [pscustomobject]@{
            Commit = $commit
            Root = "$($mod.Dir)/scripts/mods/$($mod.Dir)"
        }
    }
    Invoke-VtContractDeployedBlobPrefetch -RepoRoot $RepoRoot -DeployedTrees $prefetchTargets

    $entries = @()
    $legacyFallbacks = @()
    $commands = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    $receipts = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($mod in @($inventory.Mods)) {
        $workshopId = [string]$mod.WorkshopId
        if ([string]::IsNullOrWhiteSpace($workshopId)) { continue }
        $deployed = @($ReleaseManifest.mods | Where-Object { [string]$_.workshop_id -eq $workshopId })
        if ($deployed.Count -ne 1) {
            throw "Release manifest must contain exactly one entry for $($mod.Dir) Workshop item $workshopId; found $($deployed.Count)."
        }
        $deployed = $deployed[0]
        $commit = [string]$deployed.source_commit
        $version = [string]$deployed.version
        $provenance = 'release-manifest-source-commit'
        if ([string]::IsNullOrWhiteSpace($commit)) {
            # Two old carry-forward entries predate manifest schema-2
            # provenance. Their release version remains authoritative; bind
            # the tag/command surface to current source only when that source
            # declares the exact same version, and expose the fallback.
            $commit = [string](@(Invoke-VtContractGit -RepoRoot $RepoRoot -Arguments @('rev-parse', 'HEAD'))[0])
            $commit = $commit.Trim()
            $provenance = 'release-version-current-source-fallback'
            $legacyFallbacks += [string]$mod.Dir
        }
        elseif ($commit -notmatch '^[0-9a-f]{40}$') {
            throw "Release manifest source_commit is invalid for $($mod.Dir): '$commit'."
        }
        if ($version -notmatch ('^' + $script:VtContractSemverPattern + '$')) {
            throw "Release manifest version is invalid for $($mod.Dir): '$version'."
        }

        Invoke-VtContractGit -RepoRoot $RepoRoot -Arguments @('cat-file', '-e', "$commit^{commit}") | Out-Null
        $mainPath = "$($mod.Dir)/scripts/mods/$($mod.Dir)/$($mod.Dir).lua"
        $mainText = (Invoke-VtContractGit -RepoRoot $RepoRoot -Arguments @('show', "${commit}:$mainPath")) -join "`n"
        $sourceVersion = [regex]::Match($mainText, 'MOD_VERSION\s*=\s*["'']([^"'']+)["'']').Groups[1].Value
        if ($sourceVersion -ne $version) {
            throw "Deployed version provenance drift for $($mod.Dir): manifest '$version', source commit '$sourceVersion'."
        }

        $sourceRoot = "$($mod.Dir)/scripts/mods/$($mod.Dir)"
        $lines = @(Invoke-VtContractGit -RepoRoot $RepoRoot -AllowNoMatch -Arguments @(
            'grep', '-h', '-I', '-A', '4',
            '-e', ':LOAD]',
            '-e', 'mod:command',
            $commit, '--', $sourceRoot
        ))
        $printfLines = @(Invoke-VtContractGit -RepoRoot $RepoRoot -AllowNoMatch -Arguments @(
            'grep', '-h', '-I', '-C', '6', '-e', 'printf',
            $commit, '--', $sourceRoot
        ))

        $loadTags = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
        $modCommands = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
        $modReceipts = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
        $identityText = $lines -join "`n"
        foreach ($line in $lines) {
            foreach ($match in [regex]::Matches($line, '\[(' + $script:VtContractTagPattern + '):LOAD\]')) {
                [void]$loadTags.Add($match.Groups[1].Value)
            }
        }
        foreach ($match in [regex]::Matches($identityText, 'mod:command\s*\(\s*["'']([^"'']+)["'']')) {
            [void]$modCommands.Add($match.Groups[1].Value)
            [void]$commands.Add($match.Groups[1].Value)
        }
        $printfText = $printfLines -join "`n"
        foreach ($match in [regex]::Matches($printfText, '\[([A-Za-z][A-Za-z0-9_-]*(?::[A-Za-z0-9_-]+)?)\]')) {
            if ($match.Groups[1].Value -notmatch '(?i):LOAD$') {
                $prefix = "[$($match.Groups[1].Value)]"
                [void]$modReceipts.Add($prefix)
                [void]$receipts.Add($prefix)
            }
        }

        # Some probes deliberately format through a tiny injected/helper
        # function rather than calling printf at every observation site. Their
        # exact routes are declared below and checked against this deployed
        # commit; a stale marker or a severed printf adapter fails closed.
        $receiptEvidence = @(
            @{ Prefix='[WOC:633]'; WorkshopId='3753880932'; MarkerPath='_woc_blightreaper_audio.lua'; MarkerNeedle='[WOC:633]'; ProofPath='_woc_blightreaper_audio.lua'; ProofNeedle='pcall(printf_fn, format, ...)' },
            @{ Prefix='[gut:630]'; WorkshopId='3751024698'; MarkerPath='_gut_dx12_fence630.lua'; MarkerNeedle='[gut:630]'; ProofPath='gui_tweaker_dev.lua'; ProofNeedle='emit = function(line) printf("%s", line) end' },
            @{ Prefix='[cwv:343]'; WorkshopId='3716869446'; MarkerPath='_cwv_smoke_bomb_probe.lua'; MarkerNeedle='[cwv:343]'; ProofPath='_cwv_smoke_bomb_probe.lua'; ProofNeedle='pcall(printf, "%s", line)' },
            @{ Prefix='[cwv:760]'; WorkshopId='3716869446'; MarkerPath='_cwv_outrider_animation.lua'; MarkerNeedle='[cwv:760]'; ProofPath='_cwv_core_templates.lua'; ProofNeedle='emit_evidence(printf' },
            @{ Prefix='[gt:753]'; WorkshopId='3733367409'; MarkerPath='_gt_diag_disconnect_failure.lua'; MarkerNeedle='[gt:753]'; ProofPath='_gt_diag_disconnect_failure.lua'; ProofNeedle='pcall(engine_printf, "[gt:753] " .. fmt, ...)' },
            @{ Prefix='[ct:132]'; WorkshopId='3733366926'; MarkerPath='_ct_diag_cursed_chest132.lua'; MarkerNeedle='[ct:132]'; ProofPath='_ct_diag_cursed_chest132.lua'; ProofNeedle='pcall(printf, fmt, ...)' },
            @{ Prefix='[ct:349]'; WorkshopId='3733366926'; MarkerPath='_ct_diag_cursed_chest132.lua'; MarkerNeedle='[ct:349]'; ProofPath='_ct_diag_cursed_chest132.lua'; ProofNeedle='pcall(printf, fmt, ...)' },
            @{ Prefix='[mp:607]'; WorkshopId='3730422873'; MarkerPath='_mp_loot_diag_runtime.lua'; MarkerNeedle='[mp:607]'; ProofPath='modded_progression.lua'; ProofNeedle='print_log = printf' }
        )
        foreach ($proof in @($receiptEvidence | Where-Object { $_.WorkshopId -eq $workshopId })) {
            $markerPath = "$sourceRoot/$($proof.MarkerPath)"
            $proofPath = "$sourceRoot/$($proof.ProofPath)"
            $markerText = (Invoke-VtContractGit -RepoRoot $RepoRoot -Arguments @('show', "${commit}:$markerPath")) -join "`n"
            $proofText = if ($proofPath -eq $markerPath) { $markerText } else {
                (Invoke-VtContractGit -RepoRoot $RepoRoot -Arguments @('show', "${commit}:$proofPath")) -join "`n"
            }
            if ($markerText.IndexOf([string]$proof.MarkerNeedle, [System.StringComparison]::Ordinal) -lt 0 -or
                $proofText.IndexOf([string]$proof.ProofNeedle, [System.StringComparison]::Ordinal) -lt 0) {
                throw "Deployed printf receipt proof drifted for $($proof.Prefix) at $commit."
            }
            [void]$modReceipts.Add([string]$proof.Prefix)
            [void]$receipts.Add([string]$proof.Prefix)
        }
        if ($loadTags.Count -eq 0) {
            throw "Deployed source has no [tag:LOAD] marker for $($mod.Dir) at $commit."
        }

        $entries += [pscustomobject][ordered]@{
            Directory = [string]$mod.Dir
            ModId = [string]$mod.ModId
            WorkshopId = $workshopId
            Version = $version
            SourceCommit = $commit
            Provenance = $provenance
            LoadTags = @($loadTags | Sort-Object)
            Commands = @($modCommands | Sort-Object)
            PrintfReceipts = @($modReceipts | Sort-Object)
        }
    }

    return [pscustomobject][ordered]@{
        ReleaseTag = [string]$ReleaseManifest.release_tag
        PublishedAt = [string]$ReleaseManifest.published_at
        Entries = @($entries)
        Commands = @($commands | Sort-Object)
        PrintfReceipts = @($receipts | Sort-Object)
        LegacySourceFallbacks = @($legacyFallbacks | Sort-Object)
    }
}

function Get-VtCardVersionAnchors {
    param([string]$BuildBanner)

    $pairs = @{}
    if ([string]::IsNullOrWhiteSpace($BuildBanner)) { return @() }
    $sem = $script:VtContractSemverPattern
    $tag = $script:VtContractTagPattern
    $patterns = @(
        @{ Pattern=('\[(' + $tag + '):LOAD\]`?[ \t]*`?v?(' + $sem + ')'); Tag=1; Version=2 },
        @{ Pattern=('v?(' + $sem + ')`?[ \t]*`?\[(' + $tag + '):LOAD\]'); Tag=2; Version=1 },
        @{ Pattern=('\[(' + $tag + ')\][ \t]+v?(' + $sem + ')[ \t]+loaded'); Tag=1; Version=2 }
    )
    foreach ($spec in $patterns) {
        foreach ($match in [regex]::Matches($BuildBanner, $spec.Pattern, 'IgnoreCase')) {
            $tagValue = $match.Groups[$spec.Tag].Value
            $versionValue = $match.Groups[$spec.Version].Value
            $pairs[($tagValue.ToLowerInvariant() + '|' + $versionValue.ToLowerInvariant())] =
                [pscustomobject]@{ Tag=$tagValue; Version=$versionValue }
        }
    }

    # The template permits "vX, confirm [tag:LOAD]". After consuming every
    # adjacent explicit pair, bind this loose form only when exactly one tag
    # and one version remain. This supports a mixed card containing one exact
    # banner plus one template-form banner without guessing among siblings.
    $tags = @(Get-VtOrderedUniqueStrings @([regex]::Matches($BuildBanner, '\[(' + $tag + '):LOAD\]', 'IgnoreCase') |
        ForEach-Object { $_.Groups[1].Value }))
    $versions = @(Get-VtOrderedUniqueStrings @([regex]::Matches($BuildBanner, '(?i)\bv?(' + $sem + ')\b') |
        ForEach-Object { $_.Groups[1].Value }))
    $remainingTags = @($tags | Where-Object { $candidate=$_; @($pairs.Values | Where-Object { $_.Tag -ieq $candidate }).Count -eq 0 })
    $remainingVersions = @($versions | Where-Object { $candidate=$_; @($pairs.Values | Where-Object { $_.Version -ieq $candidate }).Count -eq 0 })
    if ($remainingTags.Count -eq 1 -and $remainingVersions.Count -eq 1) {
        $pairs[($remainingTags[0].ToLowerInvariant() + '|' + $remainingVersions[0].ToLowerInvariant())] =
            [pscustomobject]@{ Tag=$remainingTags[0]; Version=$remainingVersions[0] }
    }
    return @($pairs.Values)
}

function Get-VtCardExpectedEvidenceText {
    param([string]$Card)

    $result = @()
    $inside = $false
    foreach ($line in @($Card -split "`r?`n")) {
        if (-not $inside) {
            if ($line -match '(?i)^\s*\*\*Expected:\*\*\s*(.*)$') {
                $inside = $true
                $result += $matches[1]
            }
            continue
        }
        # Expected may legitimately span several paragraphs. Stop before
        # provenance or historical prose so an obsolete marker cannot satisfy
        # the current diagnostic receipt contract.
        if ($line -match '(?i)^\s*(?:\*\*[A-Za-z][^*]*:\*\*|Note:|Supersedes:|Deployed floor:|\*\()') {
            break
        }
        $result += $line
    }
    return ($result -join "`n").Trim()
}

function Get-VtCardContractErrors {
    param(
        [string]$Card,
        [string]$BuildBanner,
        $Contract,
        [switch]$RequirePrintfEvidence
    )

    $errors = New-Object System.Collections.Generic.List[string]
    if (-not $Contract) { return @() }
    $pairs = @(Get-VtCardVersionAnchors $BuildBanner)
    if ($pairs.Count -eq 0) {
        $errors.Add('build-anchor-version-not-bound')
    }

    $matchedEntries = @()
    foreach ($pair in $pairs) {
        $matches = @($Contract.Entries | Where-Object {
            @($_.LoadTags | Where-Object { $_ -ieq $pair.Tag }).Count -gt 0 -and
            [string]$_.Version -ieq [string]$pair.Version
        })
        if ($matches.Count -eq 0) {
            $errors.Add("undeployed-build-$($pair.Tag)-$($pair.Version)")
        }
        else {
            $matchedEntries += $matches
        }
    }
    $allTags = @(Get-VtOrderedUniqueStrings @([regex]::Matches($BuildBanner, '\[(' + $script:VtContractTagPattern + '):LOAD\]', 'IgnoreCase') |
        ForEach-Object { $_.Groups[1].Value }))
    $allVersions = @(Get-VtOrderedUniqueStrings @([regex]::Matches($BuildBanner, '(?i)\bv?(' + $script:VtContractSemverPattern + ')\b') |
        ForEach-Object { $_.Groups[1].Value }))
    foreach ($tag in $allTags) {
        if (@($pairs | Where-Object { $_.Tag -ieq $tag }).Count -eq 0) {
            $errors.Add("unbound-build-load-tag-$tag")
        }
    }
    foreach ($version in $allVersions) {
        if (@($pairs | Where-Object { $_.Version -ieq $version }).Count -eq 0) {
            $errors.Add("unbound-build-version-$version")
        }
    }

    $authoritativeLines = @($Card -split "`r?`n" | Where-Object {
        $_ -match '(?i)^\s*\*\*(?:Build/banner|Workshop(?: receipts)?|Current deployed floor)\s*:\*\*'
    })
    $authoritativeText = $authoritativeLines -join "`n"
    $workshopIds = @([regex]::Matches($authoritativeText, '(?i)(?:workshop[ \t]+)?item[ \t]+`?(\d{10})`?') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    foreach ($workshopId in $workshopIds) {
        if (@($matchedEntries | Where-Object { [string]$_.WorkshopId -eq $workshopId }).Count -eq 0) {
            $errors.Add("workshop-item-not-bound-to-build-$workshopId")
        }
    }

    $manifestByItem = @{}
    foreach ($line in $authoritativeLines) {
        if ($line -notmatch '(?i)manifest(?:id)?') { continue }
        $items = @(Get-VtOrderedUniqueStrings @([regex]::Matches($line, '(?i)(?:workshop[ \t]+)?item[ \t]+`?(\d{10})`?') |
            ForEach-Object { $_.Groups[1].Value }))
        $manifests = @(Get-VtOrderedUniqueStrings @([regex]::Matches($line, '(?i)manifest(?:id)?[ \t]+`?(\d{6,})`?') |
            ForEach-Object { $_.Groups[1].Value }))
        if ($manifests.Count -eq 0) { continue }
        if ($items.Count -eq 1) {
            if (-not $manifestByItem.ContainsKey($items[0])) { $manifestByItem[$items[0]] = @() }
            $manifestByItem[$items[0]] = @($manifestByItem[$items[0]]) + $manifests
        }
        elseif ($items.Count -ne $manifests.Count) {
            $errors.Add('unscoped-manifest-id')
        }
        else {
            for ($i = 0; $i -lt $items.Count; $i++) {
                if (-not $manifestByItem.ContainsKey($items[$i])) { $manifestByItem[$items[$i]] = @() }
                $manifestByItem[$items[$i]] = @($manifestByItem[$items[$i]]) + $manifests[$i]
            }
        }
    }
    foreach ($item in @($manifestByItem.Keys)) {
        $distinct = @($manifestByItem[$item] | Sort-Object -Unique)
        if ($distinct.Count -gt 1) { $errors.Add("contradictory-manifest-ids-$item") }
    }

    $registered = @($matchedEntries | ForEach-Object { @($_.Commands) } | Sort-Object -Unique)
    foreach ($step in @(Get-VtNumberedStepText $Card)) {
        foreach ($match in [regex]::Matches($step, '`/([A-Za-z][A-Za-z0-9_:-]+)(?:[ \t][^`]*)?`')) {
            $command = $match.Groups[1].Value
            if ($registered -notcontains $command) {
                $errors.Add("unregistered-command-$command")
            }
        }
    }

    $evidenceText = (@(Get-VtNumberedStepText $Card) + @((Get-VtCardExpectedEvidenceText $Card))) -join "`n"
    if ($RequirePrintfEvidence) {
        $requestsLogEvidence = $evidenceText -match '(?i)\b(?:attach|retain|save|inspect|read|capture|check|grep)\b[^\r\n]{0,100}\b(?:log|row|trace|receipt|needle)s?\b' -or
            $evidenceText -match '(?i)\b(?:log(?!\s+spam\b)|row|trace|receipt|needle)s?\b[^\r\n]{0,100}\b(?:contains?|carries|records?|reports?|classifies|identifies|appears?|shows?|verdict|result)\b' -or
            $evidenceText -match '(?i)\bbounded\b[^\r\n]{0,60}\brows?\b'
        $requestedReceipts = @([regex]::Matches($evidenceText, '\[([A-Za-z][A-Za-z0-9_-]*(?::[A-Za-z0-9_-]+)?)\]') |
            ForEach-Object { "[$($_.Groups[1].Value)]" } |
            Where-Object { $_ -notmatch '(?i):LOAD\]$' } |
            Sort-Object -Unique)
        if ($requestedReceipts.Count -eq 0 -and $requestsLogEvidence) {
            $errors.Add('diagnostic-log-evidence-prefix-missing')
        }
        $boundReceipts = @($matchedEntries | ForEach-Object { @($_.PrintfReceipts) } | Sort-Object -Unique)
        foreach ($receipt in $requestedReceipts) {
            if (@($boundReceipts | Where-Object { $_ -ieq $receipt }).Count -eq 0) {
                $errors.Add("requested-receipt-not-printf-$($receipt.Trim('[', ']'))")
            }
        }
    }

    return @($errors | Select-Object -Unique)
}

function Invoke-VtDeployedSourceContractSelfTest {
    $tempBase = [System.IO.Path]::GetTempPath()
    $tmp = Join-Path $tempBase ('vt2-live-card-contract-' + [guid]::NewGuid().ToString('N'))
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try {
        [void][System.IO.Directory]::CreateDirectory((Join-Path $tmp 'tools'))
        $luaRoot = Join-Path $tmp 'fixture_mod\scripts\mods\fixture_mod'
        [void][System.IO.Directory]::CreateDirectory($luaRoot)
        [System.IO.File]::WriteAllText((Join-Path $tmp 'tools\mod-inventory.psd1'), @'
@{ Mods = @(
    @{ Dir='fixture_mod'; ModId='fixture'; WorkshopId='1234567890';
       Visibility='friends_only'; Stream='single'; Public=$false;
       Name='Fixture'; RootBundle='fixture.mod_bundle' }
) }
'@, $utf8)
        [System.IO.File]::WriteAllText((Join-Path $luaRoot 'fixture_mod.lua'), @'
local MOD_VERSION = "1.2.3-dev"
pcall(printf, "[fx:LOAD] v%s enabled fp=test OK", MOD_VERSION)
mod:command(
    "fx_probe",
    "Fixture probe",
    function()
        pcall(printf,
            "[fx:probe] status=OK")
    end)
'@, $utf8)
        & git -C $tmp init -q
        & git -C $tmp config user.email 'fixture@example.invalid'
        & git -C $tmp config user.name 'VT2 Contract Fixture'
        & git -C $tmp config core.autocrlf false
        & git -C $tmp add -- .
        & git -C $tmp commit -q -m fixture
        if ($LASTEXITCODE -ne 0) { throw 'Could not commit deployed-source contract fixture.' }
        $commit = (& git -C $tmp rev-parse HEAD).Trim()
        $manifest = [pscustomobject]@{
            manifest_schema = 2
            release_tag = 'mods-fixture'
            published_at = '2026-08-13T00:00:00Z'
            mods = @([pscustomobject]@{
                mod_id='fixture'; workshop_id='1234567890'; version='1.2.3-dev'; source_commit=$commit
            })
        }
        $contract = Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest
        if ($contract.Entries.Count -ne 1 -or $contract.Entries[0].LoadTags -notcontains 'fx') {
            throw 'Fixture load-tag identity was not recovered.'
        }
        if ($contract.Commands -notcontains 'fx_probe') {
            throw 'Fixture multiline command registration was not recovered.'
        }
        if ($contract.PrintfReceipts -notcontains '[fx:probe]') {
            throw 'Fixture multiline printf receipt was not recovered.'
        }
        $manifest.mods[0].version = '1.2.4-dev'
        $rejected = $false
        try { Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest | Out-Null }
        catch { $rejected = $_.Exception.Message -match 'provenance drift' }
        if (-not $rejected) { throw 'Planted manifest/source version mismatch was accepted.' }

        # Regression proof for #750: in a blob:none partial clone (the shape of
        # the dedicated lifecycle CI checkout) the contract must recover the
        # deployed identity through the batched blob prefetch. GIT_NO_LAZY_FETCH
        # forbids the per-object fallback on git >= 2.45, and the missing-object
        # census proves hydration happened on every git version.
        $manifest.mods[0].version = '1.2.3-dev'
        & git -C $tmp config uploadpack.allowfilter true
        & git -C $tmp config uploadpack.allowanysha1inwant true
        $partial = Join-Path $tmp 'partial-clone'
        $sourcePath = ($tmp -replace '\\', '/')
        $sourceUrl = if ($sourcePath.StartsWith('/')) { "file://$sourcePath" } else { "file:///$sourcePath" }
        $cloneOutput = @(& git clone --quiet --no-checkout --filter=blob:none $sourceUrl $partial 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not create partial-clone contract fixture: $($cloneOutput -join ' ')" }
        & git -C $partial config core.longpaths true
        # Hydrate everything except the deployed mod tree, so its Lua blobs are
        # genuinely absent, exactly like historical deployed source in CI.
        & git -C $partial sparse-checkout set --no-cone '/*' '!/fixture_mod/'
        $checkoutOutput = @(& git -C $partial checkout --quiet 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not check out partial-clone contract fixture: $($checkoutOutput -join ' ')" }
        $missingBefore = @(& git -C $partial rev-list --objects --missing=print HEAD 2>&1 |
            Where-Object { [string]$_ -match '^\?[0-9a-f]{40,64}$' })
        if ($missingBefore.Count -lt 1) { throw 'Partial-clone fixture left no deployed blob missing.' }
        $previousNoLazyFetch = $env:GIT_NO_LAZY_FETCH
        try {
            $env:GIT_NO_LAZY_FETCH = '1'
            $partialContract = Get-VtDeployedSourceContract -RepoRoot $partial -ReleaseManifest $manifest
        }
        finally {
            if ($null -eq $previousNoLazyFetch) {
                Remove-Item Env:GIT_NO_LAZY_FETCH -ErrorAction SilentlyContinue
            }
            else { $env:GIT_NO_LAZY_FETCH = $previousNoLazyFetch }
        }
        if ($partialContract.Entries.Count -ne 1 -or
            $partialContract.Entries[0].LoadTags -notcontains 'fx' -or
            $partialContract.Commands -notcontains 'fx_probe' -or
            $partialContract.PrintfReceipts -notcontains '[fx:probe]') {
            throw 'Partial-clone contract lost deployed identity through the batched prefetch.'
        }
        $missingAfter = @(& git -C $partial rev-list --objects --missing=print HEAD 2>&1 |
            Where-Object { [string]$_ -match '^\?[0-9a-f]{40,64}$' })
        if ($missingAfter.Count -ne 0) {
            throw "Batched prefetch left $($missingAfter.Count) deployed blob(s) unhydrated."
        }
        Write-Host '[live-test-contract -SelfTest] OK'
    }
    finally {
        $resolvedTemp = [System.IO.Path]::GetFullPath($tempBase).TrimEnd([char[]]@('\', '/'))
        $resolvedTarget = [System.IO.Path]::GetFullPath($tmp)
        if ($resolvedTarget.StartsWith($resolvedTemp + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase) -and
            [System.IO.Path]::GetFileName($resolvedTarget) -like 'vt2-live-card-contract-*' -and
            [System.IO.Directory]::Exists($resolvedTarget)) {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($resolvedTarget, '*',
                    [System.IO.SearchOption]::AllDirectories)) {
                [System.IO.File]::SetAttributes($file, [System.IO.FileAttributes]::Normal)
            }
            [System.IO.Directory]::Delete($resolvedTarget, $true)
        }
    }
}
