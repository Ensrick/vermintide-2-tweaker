# Shared GitHub live-test queue policy.
#
# `diagnostics-armed` and `verify-fix` are invitations to test in VT2 now.
# Their only accepted procedure is the newest comment whose heading is exactly
# `## CURRENT LIVE TEST`.  Keeping selection and validation here prevents ship,
# audit, CI, and generated playtest documents from disagreeing.

$script:VtOpenLifecycleLabels = @('not-started', 'diagnostics-armed', 'verify-fix')
$script:VtReadyLifecycleLabels = @('diagnostics-armed', 'verify-fix')
$script:VtInvalidOpenLifecycleLabels = @('Fixed', 'verify-fix-coop')
# A designated playtester comment after the current test card is an unanswered
# queue result, regardless of whether its prose sounds like pass, fail, a log,
# or a question. Keep this list centralized: closure authorization has a
# broader trust model and must not silently expand the live-test watermark.
$script:VtDesignatedPlaytesterLogins = @('RainReligion')

$liveTestContractPolicy = Join-Path $PSScriptRoot 'live_test_contract.ps1'
if (-not (Test-Path -LiteralPath $liveTestContractPolicy -PathType Leaf)) {
    throw "Live-test deployed-source contract policy is missing: $liveTestContractPolicy"
}
. $liveTestContractPolicy

function Get-VtLabelNames {
    param($Issue)
    return @($Issue.labels | ForEach-Object { [string]$_.name })
}

function Test-VtCurrentLiveTestCard {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $false }
    return $Body -match '(?m)^## CURRENT LIVE TEST\s*$'
}

function Get-VtCommentCreatedAt {
    param($Comment, [switch]$IncludeEdits)
    if ($null -eq $Comment) { return [datetime]::MinValue }

    $createdAt = [datetime]::MinValue
    if ($Comment.createdAt) {
        [datetime]::TryParse([string]$Comment.createdAt, [ref]$createdAt) | Out-Null
    }
    if (-not $IncludeEdits -or -not $Comment.updatedAt) { return $createdAt }

    $updatedAt = [datetime]::MinValue
    [datetime]::TryParse([string]$Comment.updatedAt, [ref]$updatedAt) | Out-Null
    if ($updatedAt -gt $createdAt) { return $updatedAt }
    return $createdAt
}

function Get-VtCommentDatabaseId {
    param($Comment)
    if ($null -eq $Comment) { return $null }
    $raw = $Comment.databaseId
    if ($null -eq $raw) { $raw = $Comment.database_id }
    $value = 0L
    if ($null -ne $raw -and [long]::TryParse([string]$raw, [ref]$value)) { return $value }
    return $null
}

function Test-VtCommentPositionAfter {
    param(
        $Candidate,
        [int]$CandidateIndex,
        $Baseline,
        [int]$BaselineIndex,
        [switch]$CandidateIncludesEdits
    )
    if ($null -eq $Candidate -or $null -eq $Baseline) { return $false }

    $candidateAt = Get-VtCommentCreatedAt -Comment $Candidate -IncludeEdits:$CandidateIncludesEdits
    $baselineAt = Get-VtCommentCreatedAt -Comment $Baseline
    if ($candidateAt -gt $baselineAt) { return $true }
    if ($candidateAt -lt $baselineAt) { return $false }

    # Database ids order comment creation, not later edits. If an edit and the
    # card share GitHub's timestamp precision, fail closed instead of letting
    # the comment's older creation id hide the new tester activity.
    $candidateCreatedAt = Get-VtCommentCreatedAt -Comment $Candidate
    if ($CandidateIncludesEdits -and $candidateAt -gt $candidateCreatedAt) { return $true }

    $candidateId = Get-VtCommentDatabaseId $Candidate
    $baselineId = Get-VtCommentDatabaseId $Baseline
    if ($null -ne $candidateId -and $null -ne $baselineId -and $candidateId -ne $baselineId) {
        return $candidateId -gt $baselineId
    }
    return $CandidateIndex -gt $BaselineIndex
}

function Get-VtCurrentLiveTestCommentPosition {
    param($Comments)
    if (-not $Comments) { return $null }
    $arr = @($Comments)
    $selected = $null
    $selectedIndex = -1
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $body = [string]$arr[$i].body
        if (-not (Test-VtCurrentLiveTestCard $body)) { continue }
        if ($null -eq $selected -or
            (Test-VtCommentPositionAfter -Candidate $arr[$i] -CandidateIndex $i -Baseline $selected -BaselineIndex $selectedIndex)) {
            $selected = $arr[$i]
            $selectedIndex = $i
        }
    }
    if ($null -eq $selected) { return $null }
    return [pscustomobject]@{ Comment=$selected; Index=$selectedIndex }
}

function Get-VtCurrentLiveTestComment {
    param($Comments)
    $position = Get-VtCurrentLiveTestCommentPosition $Comments
    if (-not $position) { return $null }
    return $position.Comment
}

function Get-VtCommentAuthorLogin {
    param($Comment)
    if ($null -eq $Comment) { return $null }
    if ($Comment.author -and $Comment.author.login) { return [string]$Comment.author.login }
    if ($Comment.user -and $Comment.user.login) { return [string]$Comment.user.login }
    return $null
}

function Test-VtDesignatedPlaytesterComment {
    param($Comment)
    $login = Get-VtCommentAuthorLogin $Comment
    if ([string]::IsNullOrWhiteSpace($login)) { return $false }
    foreach ($designated in @($script:VtDesignatedPlaytesterLogins)) {
        if ($designated -and $designated.Equals($login, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-VtNewestDesignatedPlaytesterCommentPosition {
    param($Comments)
    if (-not $Comments) { return $null }
    $arr = @($Comments)
    $selected = $null
    $selectedIndex = -1
    for ($i = 0; $i -lt $arr.Count; $i++) {
        if (-not (Test-VtDesignatedPlaytesterComment $arr[$i])) { continue }
        if ($null -eq $selected -or
            (Test-VtCommentPositionAfter -Candidate $arr[$i] -CandidateIndex $i -Baseline $selected -BaselineIndex $selectedIndex -CandidateIncludesEdits)) {
            $selected = $arr[$i]
            $selectedIndex = $i
        }
    }
    if ($null -eq $selected) { return $null }
    return [pscustomobject]@{ Comment=$selected; Index=$selectedIndex }
}

function Test-VtHasUnreconciledDesignatedPlaytesterComment {
    param($Comments)
    $card = Get-VtCurrentLiveTestCommentPosition $Comments
    $tester = Get-VtNewestDesignatedPlaytesterCommentPosition $Comments
    if (-not $card -or -not $tester) { return $false }
    return Test-VtCommentPositionAfter -Candidate $tester.Comment -CandidateIndex $tester.Index `
        -Baseline $card.Comment -BaselineIndex $card.Index -CandidateIncludesEdits
}

function Get-VtCurrentLiveTestCard {
    param($Comments)
    $comment = Get-VtCurrentLiveTestComment $Comments
    if (-not $comment) { return $null }
    return [string]$comment.body
}

function Test-VtCommentHasPinState {
    param($Comment)
    if ($null -eq $Comment) { return $false }
    if ($Comment -is [System.Collections.IDictionary]) {
        return $Comment.Contains('isPinned')
    }
    return $null -ne $Comment.PSObject.Properties['isPinned']
}

function Get-VtPinnedCurrentLiveTestCardCount {
    param($Comments)
    $count = 0
    foreach ($comment in @($Comments)) {
        if ((Test-VtCurrentLiveTestCard ([string]$comment.body)) -and
            (Test-VtCommentHasPinState $comment) -and
            [bool]$comment.isPinned) {
            $count++
        }
    }
    return $count
}

function Get-VtCardField {
    param([string]$Card, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Card)) { return $null }
    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Card, "(?im)^\s*(?:\*\*)?$escaped\s*:\s*(?:\*\*)?\s*(.+?)\s*$")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-VtNumberedStepText {
    param([string]$Card)
    if ([string]::IsNullOrWhiteSpace($Card)) { return @() }
    return @([regex]::Matches($Card, '(?m)^\s*\d+\.\s+(.+?)\s*$') |
        ForEach-Object { $_.Groups[1].Value.Trim() })
}

function Test-VtBuildBannerField {
    param([string]$BuildBanner)
    if ([string]::IsNullOrWhiteSpace($BuildBanner)) { return $false }

    $versionPattern = '\bv?\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?\b'
    if ($BuildBanner -notmatch "(?i)$versionPattern") { return $false }

    # Most mods emit the canonical [name:LOAD] marker. A small number have a
    # different exact runtime banner (for example WOC), which is accepted only
    # when the card explicitly labels and reproduces the whole versioned banner.
    if ($BuildBanner -match '\[[A-Za-z][A-Za-z0-9_]*:LOAD\]') { return $true }
    return [bool]($BuildBanner -match '(?i)\bexact\s+banner\s*:\s*(?:\x60)?\[[A-Za-z][A-Za-z0-9_-]*\]\s+v?\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?\s+loaded\b(?:\x60)?')
}

function Get-VtBuildBannerIdentities {
    param([string]$BuildBanner)
    if ([string]::IsNullOrWhiteSpace($BuildBanner)) { return @() }

    $versionMatches = @([regex]::Matches($BuildBanner, '(?i)\bv?(\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?)\b'))
    $markerMatches = @([regex]::Matches($BuildBanner, '\[[A-Za-z][A-Za-z0-9_-]*:LOAD\]'))
    $identities = New-Object System.Collections.Generic.List[object]
    foreach ($markerMatch in $markerMatches) {
        $nearest = $null
        $nearestDistance = [int]::MaxValue
        $leftSeparator = $BuildBanner.LastIndexOfAny(@([char]';',[char]'|'), $markerMatch.Index)
        $rightSemicolon = $BuildBanner.IndexOf(';', $markerMatch.Index)
        $rightPipe = $BuildBanner.IndexOf('|', $markerMatch.Index)
        $rightSeparator = @($rightSemicolon,$rightPipe | Where-Object { $_ -ge 0 } | Sort-Object | Select-Object -First 1)
        $clauseEnd = if ($rightSeparator.Count -gt 0) { [int]$rightSeparator[0] } else { $BuildBanner.Length }
        $clauseVersions = @($versionMatches | Where-Object {
            $_.Index -gt $leftSeparator -and $_.Index -lt $clauseEnd
        })
        $candidates = if ($clauseVersions.Count -gt 0) { $clauseVersions } else { $versionMatches }
        foreach ($versionMatch in $candidates) {
            $distance = [Math]::Abs($versionMatch.Index - $markerMatch.Index)
            if ($distance -lt $nearestDistance) {
                $nearest = $versionMatch
                $nearestDistance = $distance
            }
        }
        # A version and marker in the same one-line build field should be close
        # enough to describe one identity, not two unrelated prose fragments.
        if ($nearest -and $nearestDistance -le 160) {
            $identities.Add([pscustomobject][ordered]@{
                Marker = $markerMatch.Value
                Version = $nearest.Groups[1].Value
                MarkerIndex = $markerMatch.Index
                VersionIndex = $nearest.Index
            })
        }
    }
    if ($BuildBanner -match '(?i)\bexact\s+banner\s*:') {
        foreach ($match in [regex]::Matches($BuildBanner, '(?i)`?(\[[A-Za-z][A-Za-z0-9_-]*\])\s+v?(\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?)\s+loaded`?')) {
            $exactVersionMatch=@($versionMatches|Where-Object{$_.Groups[1].Value -ieq $match.Groups[2].Value}|Sort-Object{[Math]::Abs($_.Index-$match.Groups[2].Index)}|Select-Object -First 1)
            $identities.Add([pscustomobject][ordered]@{
                Marker = $match.Groups[1].Value
                Version = $match.Groups[2].Value
                MarkerIndex = $match.Groups[1].Index
                VersionIndex = if($exactVersionMatch.Count -gt 0){$exactVersionMatch[0].Index}else{$match.Groups[2].Index}
            })
        }
    }
    return @($identities.ToArray() | Sort-Object Marker,Version -Unique)
}

function Resolve-VtBuildAuthorityTargets {
    param([string]$BuildBanner, $Authority)
    $errors = New-Object System.Collections.Generic.List[string]
    $targets = New-Object System.Collections.Generic.List[object]
    if (-not $Authority) { return [pscustomobject]@{Targets=@();Errors=@()} }
    $identities = @(Get-VtBuildBannerIdentities $BuildBanner)
    $fieldMarkers = @([regex]::Matches([string]$BuildBanner, '\[[A-Za-z][A-Za-z0-9_-]*:LOAD\]') | ForEach-Object Value)
    if ($BuildBanner -match '(?i)\bexact\s+banner\s*:') {
        $fieldMarkers += @([regex]::Matches([string]$BuildBanner, '(?i)`?(\[[A-Za-z][A-Za-z0-9_-]*\])\s+v?\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?\s+loaded`?') |
            ForEach-Object { $_.Groups[1].Value })
    }
    $fieldMarkers = @($fieldMarkers | Sort-Object -Unique)
    $pairedMarkers = @($identities.Marker | Sort-Object -Unique)
    $unpairedMarkers = @($fieldMarkers | Where-Object { $pairedMarkers -notcontains $_ })
    $allVersions=@([regex]::Matches([string]$BuildBanner,'(?i)\bv?(\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?)\b'))
    $pairedVersionIndexes=@($identities|ForEach-Object{[int]$_.VersionIndex}|Sort-Object -Unique)
    $pairedVersionValues=@($identities.Version|ForEach-Object{([string]$_).TrimStart('v')}|Sort-Object -Unique)
    $unpairedVersions=@($allVersions|Where-Object{
        $pairedVersionIndexes -notcontains [int]$_.Index -and
        $pairedVersionValues -notcontains ([string]$_.Groups[1].Value).TrimStart('v')
    })
    if ($identities.Count -eq 0 -or $unpairedMarkers.Count -gt 0 -or $unpairedVersions.Count -gt 0) {
        $errors.Add('build-identity-not-parsable')
        return [pscustomobject]@{Targets=@();Errors=@($errors)}
    }
    foreach ($identity in $identities) {
        $matches = @($Authority.Records | Where-Object {
            [string]$_.Version -ieq [string]$identity.Version -and
            (@($_.LoadRoutes | Where-Object { [string]$_.Marker -ieq [string]$identity.Marker }).Count -gt 0 -or
             @($_.ExactBannerRoutes | Where-Object { [string]$_.Tag -ieq [string]$identity.Marker }).Count -gt 0)
        })
        if ($matches.Count -eq 0) {
            $errors.Add("build-identity-not-deployed:$($identity.Marker)@$($identity.Version)")
        }
        elseif($matches.Count -gt 1){
            $errors.Add("build-identity-ambiguous:$($identity.Marker)@$($identity.Version)")
        }
        elseif(@($targets|Where-Object{[string]$_.ModId -ceq [string]$matches[0].ModId}).Count -eq 0){$targets.Add($matches[0])}
    }
    return [pscustomobject]@{Targets=@($targets.ToArray());Errors=@($errors)}
}

function Get-VtBuildAuthorityErrors {
    param([string]$BuildBanner, $Authority)
    return @((Resolve-VtBuildAuthorityTargets -BuildBanner $BuildBanner -Authority $Authority).Errors)
}

function Get-VtCardCommandErrors {
    param([string]$Card, $Authority, $Targets)
    $errors = New-Object System.Collections.Generic.List[string]
    $knownCommands = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    if ($Authority) {
        foreach ($known in @($Targets.CommandRoutes.Command)) { $null = $knownCommands.Add([string]$known) }
    }
    foreach ($step in @(Get-VtNumberedStepText $Card)) {
        $commands = @([regex]::Matches($step, '(?i)(?<![A-Za-z0-9])/([a-z][a-z0-9_:-]*)'))
        foreach ($match in $commands) {
            $command = '/' + $match.Groups[1].Value
            if (-not $step.Contains(('`' + $command + '`'))) {
                $errors.Add("command-not-exactly-backticked:$command")
                continue
            }
            if ($Authority -and -not $knownCommands.Contains($command)) {
                $errors.Add("command-not-source-registered:$command")
            }
        }

        # A bold, title-cased diagnostic action is runnable only when source
        # registers that exact menu surface. This catches invented friendly
        # names that hide the real slash command (the original #347 defect).
        if ($Authority) {
            $surfaceMatches=New-Object System.Collections.Generic.List[object]
            foreach($match in [regex]::Matches($step,'(?i)\b(?:run|execute|enter|start|arm|open|use|click|select|choose|launch|toggle)\s+(?:the\s+)?\*\*([^*\r\n]{3,120}?(?:diagnostic|diagnostics|probe|audit|regression test)[^*\r\n]{0,60}?)\*\*')){$surfaceMatches.Add($match)}
            foreach($match in [regex]::Matches($step,'(?i)\b(?:run|execute|enter|start|arm|open|use|click|select|choose|launch|toggle)\s+(?:the\s+)?([^*`.,;:\r\n]{3,120}?(?:diagnostic|diagnostics|probe|audit|regression test))(?=\s*(?:[.,;:]|and\b|then\b|$))')){$surfaceMatches.Add($match)}
            foreach ($match in $surfaceMatches) {
                $surface = ($match.Groups[1].Value -replace '\s+', ' ').Trim()
                $registered = @($Targets.MenuSurfaces | Where-Object { [string]$_ -ieq $surface }).Count -gt 0
                if (-not $registered) { $errors.Add("diagnostic-surface-not-source-registered:$surface") }
            }
        }
    }
    return @($errors | Select-Object -Unique)
}

function Get-VtCardManifestReview {
    param([string]$Card, $Authority, $Targets)
    if ([string]::IsNullOrWhiteSpace($Card)) {
        return [pscustomobject]@{Errors=@();Advisories=@()}
    }
    $errors = New-Object System.Collections.Generic.List[string]
    $itemMatches = @([regex]::Matches($Card, '(?i)\b(?:Workshop(?:\s+item)?|item|PublishedFileID)\s*(?:=|:)?\s*`?([0-9]{5,})`?'))
    $manifestMatches = @([regex]::Matches($Card, '(?i)\b(?:Steam\s+)?manifest(?:ID)?\s*(?:=|:)?\s*`?([0-9]{5,})`?'))
    $byItem = @{}
    $itemOccurrences = @{}
    foreach($itemMatch in $itemMatches){
        $itemId=$itemMatch.Groups[1].Value
        if(-not$itemOccurrences.ContainsKey($itemId)){$itemOccurrences[$itemId]=0}
        $itemOccurrences[$itemId]=[int]$itemOccurrences[$itemId]+1
    }

    foreach ($manifestMatch in $manifestMatches) {
        $selectedItem = $null
        $selectedDistance = [int]::MaxValue
        foreach ($itemMatch in $itemMatches) {
            # Prefer the closest preceding item. A following item is accepted
            # only for the explicit "manifest ... Workshop item ..." form.
            $distance = if ($itemMatch.Index -le $manifestMatch.Index) {
                $manifestMatch.Index - $itemMatch.Index
            }
            else {
                ($itemMatch.Index - $manifestMatch.Index) + 1000
            }
            if ($distance -lt $selectedDistance -and $distance -le 1400) {
                $selectedItem = $itemMatch.Groups[1].Value
                $selectedDistance = $distance
            }
        }
        $manifestId = $manifestMatch.Groups[1].Value
        if (-not $selectedItem) {
            $errors.Add("manifest-without-workshop-item:$manifestId")
            continue
        }
        if (-not $byItem.ContainsKey($selectedItem)) { $byItem[$selectedItem] = @() }
        $byItem[$selectedItem] = @($byItem[$selectedItem]) + $manifestId
    }

    foreach ($itemId in @($byItem.Keys)) {
        $distinct = @($byItem[$itemId] | Sort-Object -Unique)
        if ($distinct.Count -gt 1) {
            $errors.Add("distinct-manifests-for-workshop-item:$itemId=$($distinct -join ',')")
        }
        if(@($byItem[$itemId]).Count -gt $distinct.Count){
            $errors.Add("duplicate-workshop-manifest-pair:$itemId=$($distinct -join ',')")
        }
    }
    foreach($itemId in @($itemOccurrences.Keys)){
        $pairedCount=if($byItem.ContainsKey($itemId)){@($byItem[$itemId]).Count}else{0}
        if($pairedCount -ne [int]$itemOccurrences[$itemId]){
            $errors.Add("workshop-item-without-manifest:$itemId")
        }
    }

    if ($Authority) {
        $deployedItems = @{}
        foreach ($build in @($Targets)) { $deployedItems[[string]$build.WorkshopId] = $build }
        foreach ($itemMatch in $itemMatches) {
            $itemId = $itemMatch.Groups[1].Value
            if (-not $deployedItems.ContainsKey($itemId)) { $errors.Add("workshop-item-not-selected-build:$itemId") }
        }
    }
    return [pscustomobject]@{
        Errors=@($errors | Select-Object -Unique)
        Advisories=@()
    }
}

function Get-VtCardManifestErrors {
    param([string]$Card, $Authority, $Targets)
    return @((Get-VtCardManifestReview -Card $Card -Authority $Authority -Targets $Targets).Errors)
}

# Issue #1102: headings that explicitly claim a current/live artifact are
# deployment authority, not historical feature provenance. Keep parsing and
# replacement planning pure and shared so the refresher and strict guard cannot
# disagree about a card. Untyped evidence and exact Feature provenance lines
# remain immutable.
function Get-VtCardArtifactObjectValue {
    param($Object, [string[]]$Names)
    if ($null -eq $Object) { return $null }
    foreach ($name in @($Names)) {
        $value = $null
        if ($Object -is [System.Collections.IDictionary]) {
            if ($Object.Contains($name)) { $value = $Object[$name] }
        }
        else {
            $property = $Object.PSObject.Properties[$name]
            if ($property) { $value = $property.Value }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) {
            return [string]$value
        }
    }
    return $null
}

function ConvertTo-VtCardArtifactTarget {
    param($Target)
    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @(
        (Get-VtCardArtifactObjectValue $Target @('ModId')),
        (Get-VtCardArtifactObjectValue $Target @('Dir','Directory')),
        (Get-VtCardArtifactObjectValue $Target @('FriendlyName','Identity')),
        (Get-VtCardArtifactObjectValue $Target @('LoadTag'))
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { $null = $names.Add([string]$name) }
    }

    $markers = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($route in @($Target.LoadRoutes)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$route.Marker)) { $null = $markers.Add([string]$route.Marker) }
    }
    foreach ($route in @($Target.ExactBannerRoutes)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$route.Tag)) { $null = $markers.Add([string]$route.Tag) }
    }
    $loadTag = Get-VtCardArtifactObjectValue $Target @('LoadTag')
    if ($loadTag) {
        $null = $markers.Add("[$loadTag`:LOAD]")
        $null = $markers.Add("[$loadTag]")
    }

    return [pscustomobject][ordered]@{
        Raw = $Target
        ModId = Get-VtCardArtifactObjectValue $Target @('ModId')
        Directory = Get-VtCardArtifactObjectValue $Target @('Dir','Directory')
        FriendlyName = Get-VtCardArtifactObjectValue $Target @('FriendlyName','Identity')
        Version = ([string](Get-VtCardArtifactObjectValue $Target @('Version'))).TrimStart('v','V')
        WorkshopId = Get-VtCardArtifactObjectValue $Target @('WorkshopId','PublishedId')
        SourceCommit = Get-VtCardArtifactObjectValue $Target @('SourceCommit')
        RootBundle = Get-VtCardArtifactObjectValue $Target @('RootBundle')
        RootBundleSha256 = Get-VtCardArtifactObjectValue $Target @('RootBundleSha256')
        AssetFilename = Get-VtCardArtifactObjectValue $Target @('AssetFilename')
        AssetSha256 = Get-VtCardArtifactObjectValue $Target @('AssetSha256')
        Names = @($names)
        Markers = @($markers)
    }
}

function Get-VtCardArtifactSelectedTargets {
    param([string]$Card, $Targets)
    $rows = @($Targets)
    if ($rows.Count -le 1) { return $rows }
    $build = Get-VtCardField -Card $Card -Name 'Build/banner'
    $identities = @(Get-VtBuildBannerIdentities -BuildBanner $build)
    if ($identities.Count -eq 0) { return $rows }

    $selected = New-Object System.Collections.Generic.List[object]
    $selectedKeys = @{}
    foreach ($identity in $identities) {
        $matches = @($rows | Where-Object {
            ([string]$_.Version).Equals(([string]$identity.Version).TrimStart('v','V'),
                [System.StringComparison]::OrdinalIgnoreCase) -and
            @($_.Markers | Where-Object {
                ([string]$_).Equals([string]$identity.Marker,
                    [System.StringComparison]::OrdinalIgnoreCase)
            }).Count -gt 0
        })
        if ($matches.Count -ne 1) { return $rows }
        $key = [string]$matches[0].ModId + "`n" + [string]$matches[0].WorkshopId
        if (-not $selectedKeys.ContainsKey($key)) {
            $selected.Add($matches[0])
            $selectedKeys[$key] = $true
        }
    }
    if ($selected.Count -eq 0) { return $rows }
    return @($selected.ToArray())
}

function ConvertTo-VtCardArtifactNameKey {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    return ([regex]::Replace($Value.ToLowerInvariant(), '[^a-z0-9]+', ''))
}

function Resolve-VtCardArtifactLineTargets {
    param([string]$Line, [string]$Heading, $Targets)
    $rows = @($Targets)
    $itemIds = @([regex]::Matches($Line,
        '(?i)\b(?:Workshop(?:\s+item)?|item|PublishedFileID)\s*(?:=|:)?\s*`?([0-9]{5,})`?') |
        ForEach-Object { [string]$_.Groups[1].Value } | Sort-Object -Unique)
    if ($itemIds.Count -gt 0) {
        return @($rows | Where-Object { $itemIds -contains [string]$_.WorkshopId })
    }
    if ($rows.Count -eq 1) { return $rows }

    if ($Heading -match '(?i)^Current[ \t]+(.+?)[ \t]+receipt$') {
        $qualifier = ConvertTo-VtCardArtifactNameKey $Matches[1]
        if ($qualifier) {
            return @($rows | Where-Object {
                @($_.Names | Where-Object {
                    (ConvertTo-VtCardArtifactNameKey ([string]$_)) -ceq $qualifier
                }).Count -gt 0
            })
        }
    }
    return @()
}

function Get-VtCardCurrentArtifactReview {
    [CmdletBinding()]
    param([string]$Card, $Targets)

    $structuralErrors = New-Object System.Collections.Generic.List[string]
    $driftErrors = New-Object System.Collections.Generic.List[string]
    $changes = New-Object System.Collections.Generic.List[string]
    $claims = New-Object System.Collections.Generic.List[object]
    $cardEdits = New-Object System.Collections.Generic.List[object]
    $recognizedHeadings = 0
    $featureProvenanceLines = 0

    if ([string]::IsNullOrWhiteSpace($Card)) {
        return [pscustomobject][ordered]@{
            Status='none';Recognized=$false;FeatureProvenanceLines=0;Claims=@()
            StructuralErrors=@();DriftErrors=@();Errors=@();Changes=@();NewCard=$Card
        }
    }

    $normalizedTargets = @($Targets | ForEach-Object { ConvertTo-VtCardArtifactTarget $_ })
    $cardTargets = @(Get-VtCardArtifactSelectedTargets -Card $Card -Targets $normalizedTargets)
    $lines = @($Card -split "`r?`n")
    $lineStarts = New-Object System.Collections.Generic.List[int]
    $lineCursor = 0
    for ($lineOffsetIndex = 0; $lineOffsetIndex -lt $lines.Count; $lineOffsetIndex++) {
        $lineStarts.Add($lineCursor)
        if ($lineOffsetIndex -lt ($lines.Count - 1)) {
            $nextNewline = $Card.IndexOf("`n", $lineCursor)
            if ($nextNewline -lt 0) { break }
            $lineCursor = $nextNewline + 1
        }
    }

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = [string]$lines[$lineIndex]
        $headingMatch = [regex]::Match($line,
            '^[ \t]*(?:[-*][ \t]+)?\*\*(?<heading>[^*\r\n]{1,100}?):\*\*[ \t]*(?<value>.*)$')
        if (-not $headingMatch.Success) { continue }
        $heading = $headingMatch.Groups['heading'].Value.Trim()
        if ($heading.Equals('Feature provenance', [System.StringComparison]::OrdinalIgnoreCase)) {
            $featureProvenanceLines++
            continue
        }
        $typedCurrentHeading = $heading.Equals('Exact live artifact', [System.StringComparison]::OrdinalIgnoreCase) -or
            $heading.Equals('Live artifact', [System.StringComparison]::OrdinalIgnoreCase) -or
            $heading.Equals('Exact source', [System.StringComparison]::OrdinalIgnoreCase) -or
            $heading.Equals('Current receipt', [System.StringComparison]::OrdinalIgnoreCase) -or
            $heading -match '(?i)^Current[ \t]+.{1,80}[ \t]+receipt$'
        if (-not $typedCurrentHeading) { continue }
        $recognizedHeadings++

        $valueGroup = $headingMatch.Groups['value']
        $value = [string]$valueGroup.Value
        $valueOffset = [int]$valueGroup.Index
        $sourceHint = $heading.Equals('Exact source', [System.StringComparison]::OrdinalIgnoreCase) -or
            $value -match '(?i)\b(?:exact[ \t]+source|source(?:[ \t]+commit)?)\b'
        $rootHint = $value -match '(?i)\broot\b|\.mod_bundle\b'
        $zipHint = $value -match '(?i)\b(?:release[ \t]+)?zip\b|\.zip\b'
        $hashMatches = @([regex]::Matches($value,
            '(?i)(?<![0-9a-f])(?:[0-9a-f]{64}|[0-9a-f]{40})(?![0-9a-f])'))
        if (-not $sourceHint -and -not $rootHint -and -not $zipHint -and
            $hashMatches.Count -eq 0) { continue }

        $lineNumber = $lineIndex + 1
        $lineTargets = @(Resolve-VtCardArtifactLineTargets -Line $line -Heading $heading -Targets $cardTargets)
        if ($lineTargets.Count -ne 1) {
            $structuralErrors.Add("current-artifact-target-ambiguous:$heading@line$lineNumber")
            continue
        }
        $target = $lineTargets[0]
        $targetKey = if ($target.ModId) { [string]$target.ModId } else { [string]$target.WorkshopId }
        $lineEdits = New-Object System.Collections.Generic.List[object]
        $parsedHashRanges = New-Object System.Collections.Generic.List[object]

        if ($sourceHint) {
            $sourceMatches = if ($heading.Equals('Exact source', [System.StringComparison]::OrdinalIgnoreCase)) {
                @([regex]::Matches($value,
                    '(?i)(?<![0-9a-f])(?<value>[0-9a-f]{40})(?![0-9a-f])'))
            }
            else {
                @([regex]::Matches($value,
                    '(?i)\b(?:exact[ \t]+source|source(?:[ \t]+commit)?)[ \t]*(?:=|:)?[ \t]*`?(?<value>[0-9a-f]{40})`?'))
            }
            if ($sourceMatches.Count -ne 1) {
                $structuralErrors.Add("current-artifact-source-unparseable:$targetKey@line$lineNumber")
            }
            else {
                $group = $sourceMatches[0].Groups['value']
                $claimed = [string]$group.Value
                $expected = [string]$target.SourceCommit
                $absoluteIndex = $valueOffset + [int]$group.Index
                $parsedHashRanges.Add([pscustomobject]@{Index=$absoluteIndex;Length=[int]$group.Length})
                if ($expected -notmatch '^[0-9a-f]{40}$') {
                    $structuralErrors.Add("current-artifact-source-authority-unavailable:$targetKey@line$lineNumber")
                }
                else {
                    $claims.Add([pscustomobject]@{Field='source';Claimed=$claimed;Expected=$expected;Target=$targetKey;Line=$lineNumber})
                    if (-not $claimed.Equals($expected, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $driftErrors.Add("current-artifact-source-drift:$targetKey@line$lineNumber")
                        $lineEdits.Add([pscustomobject]@{Index=$absoluteIndex;Length=[int]$group.Length;Replacement=$expected})
                        $changes.Add("line $lineNumber`: $targetKey source $claimed -> $expected")
                    }
                }
            }
        }

        if ($rootHint) {
            $rootMatches = @([regex]::Matches($value,
                '(?i)\broot(?:[ \t]+bundle)?(?:[ \t]*(?:=|:)?[ \t]*`?(?<name>[A-Za-z0-9._-]+\.mod_bundle)`?)?[ \t]*(?:,|;)?[ \t]*SHA(?:-?256)[ \t]*(?:=|:)?[ \t]*`?(?<sha>[0-9a-f]{64})`?'))
            if ($rootMatches.Count -ne 1) {
                $structuralErrors.Add("current-artifact-root-unparseable:$targetKey@line$lineNumber")
            }
            else {
                $rootMatch = $rootMatches[0]
                $nameGroup = $rootMatch.Groups['name']
                $shaGroup = $rootMatch.Groups['sha']
                $claimedSha = [string]$shaGroup.Value
                $expectedSha = [string]$target.RootBundleSha256
                $shaIndex = $valueOffset + [int]$shaGroup.Index
                $parsedHashRanges.Add([pscustomobject]@{Index=$shaIndex;Length=[int]$shaGroup.Length})
                if ([string]$target.RootBundle -notmatch '(?i)\.mod_bundle$' -or
                    $expectedSha -notmatch '^[0-9a-f]{64}$') {
                    $structuralErrors.Add("current-artifact-root-authority-unavailable:$targetKey@line$lineNumber")
                }
                else {
                    if ($nameGroup.Success -and $nameGroup.Length -gt 0) {
                        $claimedName = [string]$nameGroup.Value
                        $expectedName = [string]$target.RootBundle
                        $claims.Add([pscustomobject]@{Field='root-name';Claimed=$claimedName;Expected=$expectedName;Target=$targetKey;Line=$lineNumber})
                        if (-not $claimedName.Equals($expectedName, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $driftErrors.Add("current-artifact-root-name-drift:$targetKey@line$lineNumber")
                            $lineEdits.Add([pscustomobject]@{Index=($valueOffset+[int]$nameGroup.Index);Length=[int]$nameGroup.Length;Replacement=$expectedName})
                            $changes.Add("line $lineNumber`: $targetKey root $claimedName -> $expectedName")
                        }
                    }
                    $claims.Add([pscustomobject]@{Field='root-sha256';Claimed=$claimedSha;Expected=$expectedSha;Target=$targetKey;Line=$lineNumber})
                    if (-not $claimedSha.Equals($expectedSha, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $driftErrors.Add("current-artifact-root-sha256-drift:$targetKey@line$lineNumber")
                        $lineEdits.Add([pscustomobject]@{Index=$shaIndex;Length=[int]$shaGroup.Length;Replacement=$expectedSha})
                        $changes.Add("line $lineNumber`: $targetKey root SHA-256 $claimedSha -> $expectedSha")
                    }
                }
            }
        }

        if ($zipHint) {
            $zipMatches = @([regex]::Matches($value,
                '(?i)(?<![-A-Za-z0-9._/\\])`?(?<name>[A-Za-z0-9._-]+\.zip)`?[ \t]*(?:,|;)?[ \t]*SHA(?:-?256)[ \t]*(?:=|:)?[ \t]*`?(?<sha>[0-9a-f]{64})`?'))
            if ($zipMatches.Count -eq 0) {
                $zipMatches = @([regex]::Matches($value,
                    '(?i)\b(?:release[ \t]+)?ZIP(?:[ \t]+asset)?[ \t]*(?:,|;)?[ \t]*SHA(?:-?256)[ \t]*(?:=|:)?[ \t]*`?(?<sha>[0-9a-f]{64})`?'))
            }
            if ($zipMatches.Count -ne 1) {
                $structuralErrors.Add("current-artifact-zip-unparseable:$targetKey@line$lineNumber")
            }
            else {
                $zipMatch = $zipMatches[0]
                $nameGroup = $zipMatch.Groups['name']
                $shaGroup = $zipMatch.Groups['sha']
                $claimedSha = [string]$shaGroup.Value
                $expectedSha = [string]$target.AssetSha256
                $shaIndex = $valueOffset + [int]$shaGroup.Index
                $parsedHashRanges.Add([pscustomobject]@{Index=$shaIndex;Length=[int]$shaGroup.Length})
                if ([string]$target.AssetFilename -notmatch '(?i)\.zip$' -or
                    $expectedSha -notmatch '^[0-9a-f]{64}$') {
                    $structuralErrors.Add("current-artifact-zip-authority-unavailable:$targetKey@line$lineNumber")
                }
                else {
                    if ($nameGroup.Success -and $nameGroup.Length -gt 0) {
                        $claimedName = [string]$nameGroup.Value
                        $expectedName = [string]$target.AssetFilename
                        $claims.Add([pscustomobject]@{Field='zip-name';Claimed=$claimedName;Expected=$expectedName;Target=$targetKey;Line=$lineNumber})
                        if (-not $claimedName.Equals($expectedName, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $driftErrors.Add("current-artifact-zip-name-drift:$targetKey@line$lineNumber")
                            $lineEdits.Add([pscustomobject]@{Index=($valueOffset+[int]$nameGroup.Index);Length=[int]$nameGroup.Length;Replacement=$expectedName})
                            $changes.Add("line $lineNumber`: $targetKey ZIP $claimedName -> $expectedName")
                        }
                    }
                    $claims.Add([pscustomobject]@{Field='zip-sha256';Claimed=$claimedSha;Expected=$expectedSha;Target=$targetKey;Line=$lineNumber})
                    if (-not $claimedSha.Equals($expectedSha, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $driftErrors.Add("current-artifact-zip-sha256-drift:$targetKey@line$lineNumber")
                        $lineEdits.Add([pscustomobject]@{Index=$shaIndex;Length=[int]$shaGroup.Length;Replacement=$expectedSha})
                        $changes.Add("line $lineNumber`: $targetKey ZIP SHA-256 $claimedSha -> $expectedSha")
                    }
                }
            }
        }

        foreach ($hashMatch in $hashMatches) {
            $absoluteIndex = $valueOffset + [int]$hashMatch.Index
            $known = @($parsedHashRanges.ToArray() | Where-Object {
                $absoluteIndex -ge [int]$_.Index -and
                ($absoluteIndex + $hashMatch.Length) -le ([int]$_.Index + [int]$_.Length)
            }).Count -gt 0
            if (-not $known) {
                $structuralErrors.Add("current-artifact-unrecognized-hash:$targetKey@line$lineNumber")
            }
        }

        $editKeys = @{}
        foreach ($edit in @($lineEdits.ToArray())) {
            $key = "$($edit.Index):$($edit.Length)"
            if ($editKeys.ContainsKey($key) -and [string]$editKeys[$key] -cne [string]$edit.Replacement) {
                $structuralErrors.Add("current-artifact-overlapping-edit:$targetKey@line$lineNumber")
            }
            else { $editKeys[$key] = [string]$edit.Replacement }
        }
        $uniqueEdits = @($lineEdits.ToArray() | Group-Object { "$($_.Index):$($_.Length)" } |
            ForEach-Object { $_.Group[0] } | Sort-Object Index -Descending)
        foreach ($edit in $uniqueEdits) {
            $cardEdits.Add([pscustomobject]@{
                Index = [int]$lineStarts[$lineIndex] + [int]$edit.Index
                Length = [int]$edit.Length
                Replacement = [string]$edit.Replacement
            })
        }
    }

    $structural = @($structuralErrors.ToArray() | Select-Object -Unique)
    $drift = @($driftErrors.ToArray() | Select-Object -Unique)
    $status = if ($structural.Count -gt 0) { 'unparseable' }
        elseif ($drift.Count -gt 0) { 'stale' }
        elseif ($recognizedHeadings -gt 0) { 'current' }
        else { 'none' }
    $newCard = $Card
    if ($structural.Count -gt 0) { $newCard = $null }
    elseif ($drift.Count -gt 0) {
        foreach ($edit in @($cardEdits.ToArray() | Sort-Object Index -Descending)) {
            $newCard = $newCard.Substring(0, [int]$edit.Index) + [string]$edit.Replacement +
                $newCard.Substring([int]$edit.Index + [int]$edit.Length)
        }
    }
    return [pscustomobject][ordered]@{
        Status = $status
        Recognized = $recognizedHeadings -gt 0
        FeatureProvenanceLines = $featureProvenanceLines
        Claims = @($claims.ToArray())
        StructuralErrors = $structural
        DriftErrors = $drift
        Errors = @($structural + $drift)
        Changes = @($changes.ToArray())
        NewCard = $newCard
    }
}

function Test-VtNativeChatMarkerException {
    param([string]$Line,$Match,$AllMatches)
    $end=$Line.Length
    foreach($candidate in @($AllMatches)){
        if($candidate.Index -gt $Match.Index -and $candidate.Index -lt $end){$end=$candidate.Index}
    }
    $segment=$Line.Substring($Match.Index,$end-$Match.Index)
    # A native-chat disclaimer is an exclusion only. Contradictory prose such
    # as "[x:y] must appear, but it is not a log line" still makes a positive
    # evidence claim and must be resolved against deployed source.
    $positiveRequirement=$segment -match '(?i)\b(?:must|shall|should|needs?\s+to|has\s+to|required\s+to)\s+(?:be\s+)?(?:appear|present|emit|print|log|show)' -or
        $segment -match '(?i)\b(?:is|are)\s+(?:strictly\s+)?required\b'
    if($positiveRequirement){return $false}
    return $segment -match '(?i)not\s+a\s+log\s+line' -and
        $segment -match '(?i)(?:not\s+(?:a\s+)?pass\s+condition|absence\s+proves\s+nothing|do\s+not\s+use\s+it\s+as)'
}

function Get-VtCardActionCommands {
    param([string]$Card)
    $commands=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach($step in @(Get-VtNumberedStepText $Card)){
        foreach($match in @([regex]::Matches($step,'(?i)`(/[a-z][a-z0-9_:-]*)`'))){
            $null=$commands.Add([string]$match.Groups[1].Value)
        }
    }
    return @($commands)
}

function Get-VtReceiptRouteDiscriminator {
    param($Route)
    $tail=([string]$Route.Signature).Substring(([string]$Route.Marker).Length).Trim()
    $literalPrefix=[regex]::Split($tail,'%(?:[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGaAspq%])',2)[0]
    $words=@([regex]::Matches($literalPrefix,'#\d+|[A-Za-z0-9_-]+')|ForEach-Object Value)
    if($words.Count -gt 0){
        $take=if([string]$words[0] -match '^#\d+$'){2}elseif([string]$words[0] -match '[-_]'){1}else{3}
        return (($words|Select-Object -First ([Math]::Min($take,$words.Count))) -join ' ')
    }
    return $null
}

function Get-VtEvidenceWords([string]$Text) {
    return @([regex]::Matches([string]$Text,'#\d+|[A-Za-z0-9]+(?:[-_][A-Za-z0-9]+)*')|ForEach-Object{$_.Value.ToLowerInvariant()})
}

function Get-VtReceiptRouteWords($Route) {
    $tail=([string]$Route.Signature).Substring(([string]$Route.Marker).Length).Trim()
    $literalPrefix=[regex]::Split($tail,'%(?:[-+ #0]*\d*(?:\.\d+)?[cdiouxXeEfgGaAspq%])',2)[0]
    return @(Get-VtEvidenceWords $literalPrefix)
}

function Get-VtReceiptRouteFieldNames($Route) {
    $tail=([string]$Route.Signature).Substring(([string]$Route.Marker).Length)
    return @([regex]::Matches($tail,'(?<![A-Za-z0-9_-])([A-Za-z][A-Za-z0-9_-]*)\s*=')|
        ForEach-Object{$_.Groups[1].Value.ToLowerInvariant()}|Select-Object -Unique)
}

function Get-VtEvidenceFragment([string]$Line,$Match) {
    $end=$Match.Index+$Match.Length
    $delimiterLength=0
    for($i=$Match.Index-1;$i -ge 0 -and $Line[$i] -eq [char]96;$i--){$delimiterLength++}
    if($delimiterLength -gt 0){
        $delimiter=([string][char]96)*$delimiterLength
        $close=$Line.IndexOf($delimiter,$end,[StringComparison]::Ordinal)
        if($close -ge 0){
            $inside=$Line.Substring($end,$close-$end)
            # For a marker-only code span, its route discriminator lives in
            # the immediately following prose ("the `[marker]` line"). Exact
            # receipt spans keep using only their literal in-span suffix.
            if([string]::IsNullOrWhiteSpace($inside)-and$close+$delimiter.Length -lt $Line.Length){
                $after=$Line.Substring($close+$delimiter.Length)
                # A sentence boundary closes the marker reference. Do not
                # accidentally treat the next sentence as an invented route
                # discriminator ("receipt begins `[id]`. This is ...").
                if($after -match '^\s*[.!?](?:\s|$)'){return ''}
                return $after
            }
            return $inside
        }
    }
    return $Line.Substring($end)
}

function Test-VtWordPrefix([string[]]$Left,[string[]]$Right) {
    if($Left.Count -eq 0 -or $Right.Count -eq 0){return $false}
    $count=[Math]::Min($Left.Count,$Right.Count)
    for($i=0;$i -lt $count;$i++){if([string]$Left[$i] -cne [string]$Right[$i]){return $false}}
    return $true
}

function Get-VtEvidenceRouteMatches($MarkerRoutes,[string]$Fragment) {
    $fragmentText=([string]$Fragment).Trim()
    if([string]::IsNullOrWhiteSpace($fragmentText)-or(Test-VtGenericMarkerReference $fragmentText)){
        # A marker is a stable prefix only when its complete deployed family is
        # safe. The caller accepts this set only if every exact route is finite;
        # one unbounded sibling makes the marker-wide claim fail closed.
        return @($MarkerRoutes)
    }

    $fieldNames=@([regex]::Matches($fragmentText,'(?<![A-Za-z0-9_-])([A-Za-z][A-Za-z0-9_-]*)\s*=')|
        ForEach-Object{$_.Groups[1].Value.ToLowerInvariant()}|Select-Object -Unique)
    $prefixText=$fragmentText
    $ellipsis=$prefixText.IndexOf('...',[StringComparison]::Ordinal)
    if($ellipsis -ge 0){$prefixText=$prefixText.Substring(0,$ellipsis)}
    $equals=$prefixText.IndexOf('=',[StringComparison]::Ordinal)
    if($equals -ge 0){
        $fieldStart=$equals-1
        while($fieldStart -ge 0 -and $prefixText[$fieldStart] -match '[A-Za-z0-9_-]'){$fieldStart--}
        $prefixText=$prefixText.Substring(0,$equals).Trim()
    }
    $prefixWords=@(Get-VtEvidenceWords $prefixText)

    return @($MarkerRoutes|Where-Object{
        $route=$_
        $routeFields=@(Get-VtReceiptRouteFieldNames $route)
        foreach($field in $fieldNames){if($routeFields -notcontains $field){return $false}}
        if($prefixWords.Count -eq 0){return $fieldNames.Count -gt 0}
        $routeWords=@(Get-VtReceiptRouteWords $route)
        return Test-VtWordPrefix -Left $prefixWords -Right $routeWords
    })
}

function Test-VtGenericMarkerReference([string]$After) {
    if(([string]$After).TrimStart().StartsWith('`',[StringComparison]::Ordinal)){return $true}
    $words=@(Get-VtEvidenceWords $After|Select-Object -First 6)
    if($words.Count -eq 0){return $true}
    $generic=@('line','lines','row','rows','receipt','receipts','warning','warnings','output','outputs','dump','block','context','diagnostic','diagnostics','grep','require','requires','appears','appear')
    if($generic -contains [string]$words[0]){return $true}
    # Natural card prose often qualifies a marker-wide artifact before the
    # noun ("smoke-bomb diagnostic row", "injection line"). It is still a
    # family reference, not an invented literal signature. This remains
    # fail-closed: the caller accepts it only when every route in the complete
    # deployed marker family is finite, or when the same card already quoted
    # exactly one route and calls that route a line/row/receipt later.
    if(([string]$After -notmatch '=') -and
       @($words|Select-Object -First 4|Where-Object{$_ -in @('line','lines','row','rows','receipt','receipts','diagnostic','diagnostics','output','outputs')}).Count -gt 0){
        return $true
    }
    return $false
}

function Test-VtStableReceiptPrefixReference([string]$Fragment,$Routes) {
    $words=@(Get-VtEvidenceWords ([string]$Fragment).Trim())
    if($words.Count -eq 0){return $false}
    # A shared literal prefix is an intentional route selector only when it is
    # independently discriminating. A one/two-word prose stem such as
    # "event" or "state changed" stays ambiguous; authored identifiers such
    # as RECEIVER-GAP (or a three-word literal prefix) may select a finite
    # bounded subgroup.
    $first=[string]$words[0]
    if($first -notmatch '[-_]' -and $first -notmatch '^#\d+$' -and $words.Count -lt 3){return $false}
    foreach($route in @($Routes)){
        $routeWords=@(Get-VtReceiptRouteWords $route)
        if($routeWords.Count -lt $words.Count -or -not(Test-VtWordPrefix -Left $words -Right $routeWords)){return $false}
    }
    return $true
}

function Test-VtGenericReferenceMayReuseExactRoute([string]$Fragment) {
    $words=@(Get-VtEvidenceWords ([string]$Fragment).Trim()|Select-Object -First 5)
    if($words.Count -eq 0){return $false}
    if(@($words|Where-Object{$_ -in @('warning','warnings','error','errors','failure','failures')}).Count -gt 0){return $false}
    return @($words|Where-Object{$_ -in @('line','receipt','row')}).Count -gt 0
}

function Get-VtCardEvidenceErrors {
    param([string]$Card, $Authority, $Targets)
    if (-not $Authority -or [string]::IsNullOrWhiteSpace($Card)) { return @() }
    $errors = New-Object System.Collections.Generic.List[string]
    $routes=@($Targets.ReceiptRoutes)
    $actionCommands=@(Get-VtCardActionCommands -Card $Card)

    $lines = @($Card -split '\r?\n' | Where-Object {
        $_ -notmatch '(?i)^\s*\*\(card (?:refreshed|re-cut|restored)' -and
        $_ -notmatch '(?i)^\s*\*\*Build/banner:\*\*'
    })
    $references=New-Object System.Collections.Generic.List[object]
    foreach ($line in $lines) {
        $markerMatches=@([regex]::Matches($line, '\[[A-Za-z][A-Za-z0-9_-]*:[A-Za-z0-9_.:-]+\]'))
        foreach ($match in $markerMatches) {
            $marker = $match.Value
            if ($marker -match '(?i):LOAD\]$') { continue }
            if(Test-VtNativeChatMarkerException -Line $line -Match $match -AllMatches $markerMatches){continue}
            $markerRoutes=@($routes|Where-Object{[string]$_.Marker -ieq $marker})
            if($markerRoutes.Count -eq 0){
                $errors.Add("diagnostic-evidence-not-in-selected-build:$marker")
                continue
            }
            $fragment=Get-VtEvidenceFragment -Line $line -Match $match
            $genericReference=Test-VtGenericMarkerReference $fragment
            $specific=@(Get-VtEvidenceRouteMatches -MarkerRoutes $markerRoutes -Fragment $fragment)
            if($specific.Count -eq 0){
                $errors.Add("diagnostic-evidence-signature-not-source-registered:$marker");continue
            }
            $references.Add([pscustomobject]@{
                Marker=$marker;MarkerRoutes=@($markerRoutes);Fragment=$fragment
                Generic=[bool]$genericReference;Matches=@($specific)
            })
        }
    }

    # A card may quote one exact receipt and later call it "the [marker]
    # line". Resolve that repeat to the one explicit route cited elsewhere in
    # the same card; without exactly one explicit route, marker-only evidence
    # still means the complete family and fails if any sibling is unbounded.
    $explicitByMarker=@{}
    foreach($reference in $references.ToArray()){
        if($reference.Generic){continue}
        $signatures=@($reference.Matches.Signature|Sort-Object -Unique)
        if($signatures.Count -ne 1){continue}
        $key=([string]$reference.Marker).ToLowerInvariant()
        if(-not$explicitByMarker.ContainsKey($key)){$explicitByMarker[$key]=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)}
        $null=$explicitByMarker[$key].Add([string]$signatures[0])
    }
    foreach($reference in $references.ToArray()){
        $specific=@($reference.Matches)
        if($reference.Generic){
            $key=([string]$reference.Marker).ToLowerInvariant()
            if((Test-VtGenericReferenceMayReuseExactRoute $reference.Fragment)-and
               $explicitByMarker.ContainsKey($key)-and$explicitByMarker[$key].Count -eq 1){
                $signature=$explicitByMarker[$key].GetEnumerator()|Select-Object -First 1
                $specific=@($reference.MarkerRoutes|Where-Object{[string]$_.Signature -ceq [string]$signature})
            }
        }else{
            $distinctSignatures=@($specific.Signature|Sort-Object -Unique)
            if($distinctSignatures.Count -ne 1 -and -not(Test-VtStableReceiptPrefixReference -Fragment $reference.Fragment -Routes $specific)){
                $errors.Add("diagnostic-evidence-signature-ambiguous:$($reference.Marker)");continue
            }
        }
        if(@($specific|Where-Object{-not[bool]$_.Bound}).Count -gt 0){
            $errors.Add("diagnostic-evidence-not-bounded:$($reference.Marker)")
        }
        $wrongAction=@($specific|Where-Object{
            $owners=@($_.ActionCommands|Where-Object{$_}|Sort-Object -Unique)
            $owners.Count -gt 0 -and @($owners|Where-Object{$actionCommands -ccontains [string]$_}).Count -eq 0
        })
        if($wrongAction.Count -gt 0){
            $required=@($wrongAction|ForEach-Object{@($_.ActionCommands)}|Where-Object{$_}|Sort-Object -Unique)
            $errors.Add("diagnostic-evidence-action-command-mismatch:$($reference.Marker)=>$($required -join '|')")
        }
    }
    return @($errors | Select-Object -Unique)
}

function Test-VtCardHasInternalKeys {
    param([string]$Card)
    foreach ($step in @(Get-VtNumberedStepText $Card)) {
        # Player actions use localized names. Snake-case identifiers belong in
        # diagnostics/log expectations, never in the numbered player steps.
        # A backticked slash command is itself the exact player-facing action,
        # so remove those tokens before looking for leaked internal item keys.
        $playerProse = $step -replace '(?i)\x60/[a-z0-9_:-]+\x60', ''
        if ($playerProse -match '(?i)(?<![/A-Za-z0-9])(?:[a-z][a-z0-9]*_){1,}[a-z0-9_]+\b') {
            return $true
        }
    }
    return $false
}

function Get-VtLiveTestCardSelection {
    param($Comments, [switch]$RequirePinnedCard, $Authority, [switch]$EnforceAuthority)

    $comment = Get-VtCurrentLiveTestComment $Comments
    $card = if ($comment) { [string]$comment.body } else { $null }
    $build = Get-VtCardField -Card $card -Name 'Build/banner'
    $topology = Get-VtCardField -Card $card -Name 'Topology'
    $soloStatus = Get-VtCardField -Card $card -Name 'Solo status'
    $expected = Get-VtCardField -Card $card -Name 'Expected'
    $steps = @(Get-VtNumberedStepText $card)
    $errors = New-Object System.Collections.Generic.List[string]
    $authorityErrors = New-Object System.Collections.Generic.List[string]
    $authorityAdvisories = New-Object System.Collections.Generic.List[string]
    $buildResolution=Resolve-VtBuildAuthorityTargets -BuildBanner $build -Authority $Authority
    $targets=@($buildResolution.Targets)
    $currentArtifactReview=$null

    if (-not $card) {
        $errors.Add('missing-current-live-test-card')
    }
    else {
        if ($RequirePinnedCard) {
            if (-not (Test-VtCommentHasPinState $comment)) {
                $errors.Add('current-live-test-card-pin-state-unavailable')
            }
            elseif (-not [bool]$comment.isPinned) {
                $errors.Add('current-live-test-card-not-pinned')
            }

            $pinnedExactCardCount = Get-VtPinnedCurrentLiveTestCardCount $Comments
            if ($pinnedExactCardCount -ne 1) {
                $errors.Add("pinned-current-live-test-card-count-$pinnedExactCardCount")
            }
        }
        if (-not (Test-VtBuildBannerField $build)) {
            $errors.Add('missing-build-version-or-runtime-banner')
        }
        foreach ($authorityError in @($buildResolution.Errors)) {
            $authorityErrors.Add($authorityError)
        }
        if ($topology -notmatch '(?i)^(Solo|Co-?op)(?:\s|$)') {
            $errors.Add('invalid-topology')
        }
        if ($steps.Count -eq 0) {
            $errors.Add('missing-numbered-steps')
        }
        if (-not $expected) {
            $errors.Add('missing-expected-result')
        }
        if (Test-VtCardHasInternalKeys $card) {
            $errors.Add('internal-key-in-player-steps')
        }
        if(-not$Authority -or ($buildResolution.Errors.Count -eq 0 -and $targets.Count -gt 0)){
            foreach ($commandError in @(Get-VtCardCommandErrors -Card $card -Authority $Authority -Targets $targets)) {
                $authorityErrors.Add($commandError)
            }
            $manifestReview=Get-VtCardManifestReview -Card $card -Authority $Authority -Targets $targets
            foreach ($manifestError in @($manifestReview.Errors)) {
                $authorityErrors.Add($manifestError)
            }
            foreach ($manifestAdvisory in @($manifestReview.Advisories)) {
                $authorityAdvisories.Add($manifestAdvisory)
            }
            if($Authority){
                $currentArtifactReview=Get-VtCardCurrentArtifactReview -Card $card -Targets $targets
                foreach($artifactError in @($currentArtifactReview.Errors)){
                    $authorityErrors.Add($artifactError)
                }
            }
            foreach ($evidenceError in @(Get-VtCardEvidenceErrors -Card $card -Authority $Authority -Targets $targets)) {
                $authorityErrors.Add($evidenceError)
            }
        }
        if ($topology -match '(?i)^Co-?op(?:\s|$)' -and $soloStatus -notmatch '(?i)\b(?:passed|complete|completed|exhausted)\b') {
            $errors.Add('coop-before-solo-passed-or-exhausted')
        }
    }
    if($EnforceAuthority){
        foreach($authorityError in @($authorityErrors|Select-Object -Unique)){$errors.Add($authorityError)}
    }
    $reportedAdvisories=New-Object System.Collections.Generic.List[string]
    foreach($advisory in @($authorityAdvisories|Select-Object -Unique)){$reportedAdvisories.Add($advisory)}
    if(-not$EnforceAuthority){
        foreach($authorityError in @($authorityErrors|Select-Object -Unique)){$reportedAdvisories.Add($authorityError)}
    }

    return [PSCustomObject][ordered]@{
        Card = $card
        Comment = $comment
        Pinned = [bool]($comment -and (Test-VtCommentHasPinState $comment) -and [bool]$comment.isPinned)
        PinnedExactCardCount = Get-VtPinnedCurrentLiveTestCardCount $Comments
        BuildBanner = $build
        Topology = $topology
        SoloStatus = $soloStatus
        Steps = @($steps)
        Expected = $expected
        AuthorityTargets = @($targets)
        CurrentArtifactReview = $currentArtifactReview
        AuthorityEnforced = [bool]$EnforceAuthority
        AuthorityErrors = @($authorityErrors | Select-Object -Unique)
        AuthorityAdvisories = @($authorityAdvisories | Select-Object -Unique)
        Advisories = @($reportedAdvisories | Select-Object -Unique)
        RequiresCoop = [bool]($topology -match '(?i)^Co-?op(?:\s|$)')
        Errors = @($errors)
        Valid = $errors.Count -eq 0
    }
}

function Get-VtOpenIssueLifecycleDecision {
    param($Issue, [switch]$RequirePinnedCard, $Authority, [switch]$EnforceAuthority)

    $labels = @(Get-VtLabelNames $Issue)
    $lifecycle = @($labels | Where-Object { $script:VtOpenLifecycleLabels -contains $_ })
    $invalid = @($labels | Where-Object { $script:VtInvalidOpenLifecycleLabels -contains $_ })
    $ready = @($lifecycle | Where-Object { $script:VtReadyLifecycleLabels -contains $_ })
    $blocked = $labels -contains 'blocked'
    $coop = $labels -contains 'coop-required'
    $card = Get-VtLiveTestCardSelection -Comments $Issue.comments -RequirePinnedCard:$RequirePinnedCard -Authority $Authority -EnforceAuthority:$EnforceAuthority
    $errors = New-Object System.Collections.Generic.List[string]

    if ($lifecycle.Count -ne 1) { $errors.Add("lifecycle-count-$($lifecycle.Count)") }
    foreach ($name in $invalid) { $errors.Add("invalid-open-lifecycle-$name") }

    if ($blocked) {
        if ($lifecycle.Count -ne 1 -or $lifecycle[0] -ne 'not-started') { $errors.Add('blocked-must-be-not-started') }
        if ($coop) { $errors.Add('blocked-forbids-coop-required') }
    }

    if ($ready.Count -eq 1) {
        if ($labels -contains 'tooling') { $errors.Add('tooling-cannot-enter-live-test-queue') }
        foreach ($cardError in @($card.Errors)) { $errors.Add("live-card-$cardError") }
        if ($coop -ne $card.RequiresCoop) { $errors.Add('coop-label-topology-mismatch') }
        if (Test-VtHasUnreconciledDesignatedPlaytesterComment $Issue.comments) {
            $errors.Add('unreconciled-designated-playtester-comment')
        }
    }
    elseif ($coop) {
        $errors.Add('coop-required-without-ready-state')
    }

    return [PSCustomObject][ordered]@{
        Labels = $labels
        Lifecycle = $lifecycle
        Ready = $ready.Count -eq 1
        Blocked = $blocked
        CoopRequired = $coop
        Card = $card
        Advisories = @($card.Advisories | ForEach-Object { "live-card-$_" } | Select-Object -Unique)
        Errors = @($errors | Select-Object -Unique)
        Valid = $errors.Count -eq 0
    }
}

# Compatibility wrappers retained for audit/generator call sites while their
# output shape moves to the strict card contract.
function Get-VtMethodComment { param($Comments) return Get-VtCurrentLiveTestCard $Comments }
function Test-VtExplicitMethodComment { param([string]$Body) return Test-VtCurrentLiveTestCard $Body }
function Test-VtMethodHasExpected { param([string]$Method) return -not [string]::IsNullOrWhiteSpace((Get-VtCardField $Method 'Expected')) }
function Test-VtMethodIsRunnable { param([string]$Method) return @(Get-VtNumberedStepText $Method).Count -gt 0 }
function Test-VtMethodRequiresCoop { param([string]$Method) return [bool]((Get-VtCardField $Method 'Topology') -match '(?i)^Co-?op(?:\s|$)') }
function Get-VtMethodCorrection { return $null }
function Get-VtCorrectionVersion { return $null }
function Get-VtLifecycleMethodSelection {
    param($Comments, [string]$Body, [switch]$AllowBodyFallback, $Authority, [switch]$EnforceAuthority)
    $selection = Get-VtLiveTestCardSelection -Comments $Comments -Authority $Authority -EnforceAuthority:$EnforceAuthority
    return [PSCustomObject][ordered]@{
        Method = $selection.Card
        Source = if ($selection.Card) { 'current-live-test-comment' } else { 'none' }
        Correction = $null
        CorrectionVersion = $null
        HasExpected = -not [string]::IsNullOrWhiteSpace($selection.Expected)
        Runnable = $selection.Steps.Count -gt 0
        Valid = $selection.Valid
        Errors = $selection.Errors
        Advisories = $selection.Advisories
        AuthorityErrors = $selection.AuthorityErrors
    }
}
function Test-VtFailedVerificationEvidence {
    param([string]$Method)
    if ([string]::IsNullOrWhiteSpace($Method)) { return $false }
    return $Method -match '(?i)(?:verification|retest|test)\s+(?:failed|still fails)|(?:still|again)\s+(?:broken|crash(?:es|ed)?|fails?|reproduc(?:es|ed|ible))|no\s+(?:change|improvement)|not\s+(?:fixed|working)'
}
function Test-VtRepositoryOnlyLabels {
    param([string[]]$LabelNames)
    return $LabelNames -contains 'tooling'
}
