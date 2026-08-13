# Shared GitHub live-test queue policy.
#
# `diagnostics-armed` and `verify-fix` are invitations to test in VT2 now.
# Their only accepted procedure is the newest comment whose heading is exactly
# `## CURRENT LIVE TEST`.  Keeping selection and validation here prevents ship,
# audit, CI, and generated playtest documents from disagreeing.

$script:VtOpenLifecycleLabels = @('not-started', 'diagnostics-armed', 'verify-fix')
$script:VtReadyLifecycleLabels = @('diagnostics-armed', 'verify-fix')
$script:VtInvalidOpenLifecycleLabels = @('Fixed', 'verify-fix-coop')

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

function Get-VtCurrentLiveTestComment {
    param($Comments)
    if (-not $Comments) { return $null }
    $arr = @($Comments)
    $selected = $null
    $selectedAt = [datetime]::MinValue
    $selectedIndex = -1
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $body = [string]$arr[$i].body
        if (-not (Test-VtCurrentLiveTestCard $body)) { continue }
        $createdAt = [datetime]::MinValue
        # GitHub returns PSCustomObject comments, while offline fixtures often
        # use hashtables. Dot-key lookup works for both; PSObject.Properties
        # does not expose hashtable keys and would silently fall back to array
        # order in the guard's own regression tests.
        $rawCreatedAt = $arr[$i].createdAt
        if ($rawCreatedAt) {
            [datetime]::TryParse([string]$rawCreatedAt, [ref]$createdAt) | Out-Null
        }
        if ($createdAt -gt $selectedAt -or ($createdAt -eq $selectedAt -and $i -gt $selectedIndex)) {
            $selected = $arr[$i]
            $selectedAt = $createdAt
            $selectedIndex = $i
        }
    }
    return $selected
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
    param($Comments, [switch]$RequirePinnedCard, $Contract, [switch]$RequirePrintfEvidence)

    $comment = Get-VtCurrentLiveTestComment $Comments
    $card = if ($comment) { [string]$comment.body } else { $null }
    $build = Get-VtCardField -Card $card -Name 'Build/banner'
    $topology = Get-VtCardField -Card $card -Name 'Topology'
    $soloStatus = Get-VtCardField -Card $card -Name 'Solo status'
    $expected = Get-VtCardField -Card $card -Name 'Expected'
    $steps = @(Get-VtNumberedStepText $card)
    $errors = New-Object System.Collections.Generic.List[string]

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
        foreach ($contractError in @(Get-VtCardContractErrors -Card $card -BuildBanner $build -Contract $Contract -RequirePrintfEvidence:$RequirePrintfEvidence)) {
            $errors.Add($contractError)
        }
        if ($topology -match '(?i)^Co-?op(?:\s|$)' -and $soloStatus -notmatch '(?i)\b(?:passed|complete|completed|exhausted)\b') {
            $errors.Add('coop-before-solo-passed-or-exhausted')
        }
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
        RequiresCoop = [bool]($topology -match '(?i)^Co-?op(?:\s|$)')
        Errors = @($errors)
        Valid = $errors.Count -eq 0
    }
}

function Get-VtOpenIssueLifecycleDecision {
    param($Issue, [switch]$RequirePinnedCard, $Contract)

    $labels = @(Get-VtLabelNames $Issue)
    $lifecycle = @($labels | Where-Object { $script:VtOpenLifecycleLabels -contains $_ })
    $invalid = @($labels | Where-Object { $script:VtInvalidOpenLifecycleLabels -contains $_ })
    $ready = @($lifecycle | Where-Object { $script:VtReadyLifecycleLabels -contains $_ })
    $blocked = $labels -contains 'blocked'
    $coop = $labels -contains 'coop-required'
    $card = Get-VtLiveTestCardSelection -Comments $Issue.comments -RequirePinnedCard:$RequirePinnedCard `
        -Contract $Contract -RequirePrintfEvidence:($labels -contains 'diagnostics-armed')
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
    param($Comments, [string]$Body, [switch]$AllowBodyFallback)
    $selection = Get-VtLiveTestCardSelection $Comments
    return [PSCustomObject][ordered]@{
        Method = $selection.Card
        Source = if ($selection.Card) { 'current-live-test-comment' } else { 'none' }
        Correction = $null
        CorrectionVersion = $null
        HasExpected = -not [string]::IsNullOrWhiteSpace($selection.Expected)
        Runnable = $selection.Steps.Count -gt 0
        Valid = $selection.Valid
        Errors = $selection.Errors
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
