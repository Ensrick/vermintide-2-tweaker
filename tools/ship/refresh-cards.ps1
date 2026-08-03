# tools/ship/refresh-cards.ps1
#
# Post-ship refresh of pinned "## CURRENT LIVE TEST" card VERSION SURFACES
# (issue #1102). The 2026-08-02 audit found all 31 sampled pinned cards naming
# superseded builds (5-18 patches behind), so a tester following a card fails
# the [id:LOAD] confirmation on a perfectly correct build. This script walks
# the open live-test queue and mechanically advances ONLY the just-shipped
# mod's stale version/manifest tokens inside each pinned exact card:
#
#   * version tokens attributed to the shipped mod through its exact runtime
#     anchor ([<tag>:LOAD] vX.Y.Z / vX.Y.Z [<tag>:LOAD] / "[<TAG>] vX.Y.Z
#     loaded" exact banners) are rewritten to the shipped MOD_VERSION;
#   * "item `<published_id>`, ManifestID `<N>`" / "Workshop item
#     `<published_id>`, manifest `<N>`" tokens are rewritten to the manifest
#     the workshop_log confirmed for THIS upload.
#
# Card step text, expected needles, topology, and every other mod's tokens are
# NEVER touched. When a card's version surfaces do not match the expected
# patterns exactly (no anchor for the shipped tag, two distinct anchored
# versions, a version string shared with another mod's anchor, unrecognized
# manifest syntax), the card is SKIPPED and reported instead of guessed at.
# The edit is a GraphQL updateIssueComment on the pinned comment in place, so
# pin state and comment identity survive; it is idempotent (a second run finds
# every token already current and writes nothing).
#
# Selection: every OPEN issue currently carrying a ready lifecycle label
# (verify-fix / diagnostics-armed -- the only issues doctrine allows pinned
# cards on) whose PINNED exact card names the shipped mod's Workshop item id
# OR carries the shipped mod's exact runtime anchor. Pin state comes from the
# same paginated GraphQL comment read the CI cardinality guard uses; every
# list is cursor-paginated (the 30-item default-page bug class of #1129).
#
# Invoked by tools/ship/ship.ps1 (step 6b) after the workshop_log has
# confirmed the upload; the ship treats any non-zero exit as a yellow warning
# and never fails on this step. Also runnable standalone.
#
# Manual verification recipe (read-only; writes nothing):
#   pwsh -File tools\ship\refresh-cards.ps1 -SelfTest
#   pwsh -File tools\ship\refresh-cards.ps1 -DryRun `
#       -PublishedId 3716869446 -NewVersion 0.1.485-dev -LoadTag cwv `
#       -NewManifest 1229843190245484744
#   The -DryRun pass prints every intended per-line edit (- old / + new) and
#   the per-card verdict (refreshed / current / skipped-unparseable /
#   skipped-closed) without mutating any comment. Re-running the same live
#   invocation twice must report every card 'current' on the second pass.
#
# Exit codes: 0 = OK (including nothing to do), 1 = completed but at least one
# card was skipped-unparseable or an update failed (advisory follow-up),
# 2 = hard failure (gh unavailable, GraphQL error).
#
# NOTE: comments + strings are ASCII only (PS 5.1 parses .ps1 as Windows-1252;
# qa/check_ps51_compatibility.ps1 enforces the byte set).

[CmdletBinding()]
param(
    [string]$PublishedId,
    [string]$NewVersion,
    [string]$LoadTag,
    [string]$NewManifest,
    [string]$Repository = 'Ensrick/vermintide-2-tweaker',
    [int]$MaxIssues = 100,
    [switch]$DryRun,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# The exact-card definition (heading match) is owned by the shared lifecycle
# policy so ship, CI, audit, and this refresher can never disagree on what a
# card IS. Offline: dot-sourcing a tracked file, no network.
$lifecycleMethodPolicy = Join-Path $PSScriptRoot '..\verify\lifecycle_method_policy.ps1'
if (-not (Test-Path -LiteralPath $lifecycleMethodPolicy -PathType Leaf)) {
    Write-Host "refresh-cards: shared lifecycle method policy not found: $lifecycleMethodPolicy" -ForegroundColor Red
    exit 2
}
. $lifecycleMethodPolicy

# Loose semver: 3 segments, tolerated legacy 4th, optional release-track suffix.
$script:VtSemverPattern = '\d+\.\d+\.\d+(?:\.\d+)?(?:-[A-Za-z0-9.]+)?'
$script:VtAnchorTagPattern = '[A-Za-z][A-Za-z0-9_-]*'

# Every (tag, version) pair bound by an exact runtime anchor in the card body:
#   A: [tag:LOAD] v1.2.3      (optional backticks between)
#   B: v1.2.3 [tag:LOAD]      (optional backticks between)
#   C: [TAG] v1.2.3 loaded    (exact versioned banner, e.g. WOC)
# Only whitespace/backticks may sit between version and anchor, so prose like
# "v0.1.485-dev` and `[cim:LOAD]" cannot cross-bind a version to the wrong tag.
function Get-VtCardVersionAnchors {
    param([string]$Body)
    # Plain return, not comma-return: every call site wraps with @(), and the
    # comma + @() combination nests the array (memory:
    # reference_ps_comma_return_wrapped_by_array_subexpr).
    $pairs = @()
    if ([string]::IsNullOrWhiteSpace($Body)) { return $pairs }
    $sem = $script:VtSemverPattern
    $tag = $script:VtAnchorTagPattern
    $patterns = @(
        ('\[(' + $tag + '):LOAD\]`?[ \t]*`?v(' + $sem + ')'),
        ('v(' + $sem + ')`?[ \t]*`?\[(' + $tag + '):LOAD\]'),
        ('\[(' + $tag + ')\][ \t]+v(' + $sem + ')[ \t]+loaded')
    )
    for ($i = 0; $i -lt $patterns.Count; $i++) {
        foreach ($m in [regex]::Matches($Body, $patterns[$i], 'IgnoreCase')) {
            if ($i -eq 1) {
                $pairs += [pscustomobject]@{ Tag = $m.Groups[2].Value; Version = $m.Groups[1].Value }
            }
            else {
                $pairs += [pscustomobject]@{ Tag = $m.Groups[1].Value; Version = $m.Groups[2].Value }
            }
        }
    }
    return $pairs
}

# Pure per-card decision + rewrite. Returns Status:
#   'not-applicable'  - not an exact card, or names neither the shipped item
#                       id nor the shipped tag's anchor
#   'unparseable'     - applicable but a version surface does not match the
#                       expected patterns; NOTHING is rewritten (all-or-nothing)
#   'current'         - applicable and every token already names the shipped
#                       version/manifest (idempotent second run lands here)
#   'refresh'         - NewBody carries the token rewrites listed in Changes
function Get-VtCardRefreshPlan {
    param(
        [string]$Body,
        [string]$PublishedId,
        [string]$NewVersion,
        [string]$LoadTag,
        [string]$NewManifest
    )

    $result = [pscustomobject]@{
        Status = 'not-applicable'
        MatchedBy = $null
        Reason = $null
        NewBody = $null
        Changes = @()
    }
    if (-not (Test-VtCurrentLiveTestCard $Body)) { return $result }

    $cleanVersion = if ($NewVersion) { $NewVersion.TrimStart('v', 'V') } else { '' }
    $pidEsc = if ($PublishedId) { [regex]::Escape($PublishedId) } else { $null }
    $pidPresent = $false
    if ($pidEsc) { $pidPresent = [bool]($Body -match ('(?<!\d)' + $pidEsc + '(?!\d)')) }

    $anchors = @(Get-VtCardVersionAnchors -Body $Body)
    $ourAnchors = @()
    $otherAnchors = @()
    foreach ($pair in $anchors) {
        if ($LoadTag -and ([string]$pair.Tag).Equals($LoadTag, [System.StringComparison]::OrdinalIgnoreCase)) {
            $ourAnchors += $pair
        }
        else {
            $otherAnchors += $pair
        }
    }

    if (-not $pidPresent -and $ourAnchors.Count -eq 0) { return $result }
    if ($pidPresent -and $ourAnchors.Count -gt 0) { $result.MatchedBy = 'item-id+load-tag' }
    elseif ($pidPresent) { $result.MatchedBy = 'item-id' }
    else { $result.MatchedBy = 'load-tag' }

    # ---- version surface -------------------------------------------------
    $ourVersions = @($ourAnchors | ForEach-Object { [string]$_.Version } | Select-Object -Unique)
    if ($ourVersions.Count -eq 0) {
        $result.Status = 'unparseable'
        $result.Reason = "no exact runtime anchor for load tag '$LoadTag' -- cannot attribute version tokens"
        return $result
    }
    if ($ourVersions.Count -gt 1) {
        $result.Status = 'unparseable'
        $result.Reason = "load tag '$LoadTag' anchors " + $ourVersions.Count + ' distinct versions (' + ($ourVersions -join ', ') + ')'
        return $result
    }
    $oldVersion = $ourVersions[0]

    if ($oldVersion -ne $cleanVersion) {
        foreach ($pair in $otherAnchors) {
            if ([string]$pair.Version -eq $oldVersion) {
                $result.Status = 'unparseable'
                $result.Reason = "version v$oldVersion is also anchored to '$($pair.Tag)' -- a sweep would stomp the other mod"
                return $result
            }
        }
    }

    $newBody = $Body
    $changes = @()
    if ($oldVersion -ne $cleanVersion -and $cleanVersion) {
        # Standalone token: no alnum/hyphen may follow, and a following dot
        # only blocks the match when it would EXTEND the version (".2"); a
        # sentence-ending period ("on v0.7.315-dev.") must not shield a token.
        $verPattern = '(?<![0-9A-Za-z.-])v?' + [regex]::Escape($oldVersion) + '(?![0-9A-Za-z-])(?!\.[0-9A-Za-z])'
        $hits = [regex]::Matches($newBody, $verPattern).Count
        $replacement = {
            param($m)
            if ($m.Value.StartsWith('v') -or $m.Value.StartsWith('V')) { return 'v' + $cleanVersion }
            return $cleanVersion
        }.GetNewClosure()
        $newBody = [regex]::Replace($newBody, $verPattern, $replacement)
        $changes += "version v$oldVersion -> v$cleanVersion ($hits token(s))"
    }

    # ---- manifest surface ------------------------------------------------
    if ($NewManifest -and $pidEsc) {
        $manifestPattern = '(?i)(item[ \t]+`?' + $pidEsc + '`?[ \t]*,[ \t]*manifest(?:id)?[ \t]+`?)(\d+)'
        $stale = @([regex]::Matches($newBody, $manifestPattern) | Where-Object { $_.Groups[2].Value -ne $NewManifest })
        if ($stale.Count -gt 0) {
            foreach ($m in $stale) {
                $changes += ('manifest ' + $m.Groups[2].Value + ' -> ' + $NewManifest + " (item $PublishedId)")
            }
            $manifestReplacement = { param($m) $m.Groups[1].Value + $NewManifest }.GetNewClosure()
            $newBody = [regex]::Replace($newBody, $manifestPattern, $manifestReplacement)
        }
        # A line that names this item id AND says 'manifest' but did not match
        # the expected token shape is a version surface we cannot safely edit.
        foreach ($line in ($newBody -split "`r?`n")) {
            if ($line -notmatch ('(?<!\d)' + $pidEsc + '(?!\d)')) { continue }
            if ($line -notmatch '(?i)manifest') { continue }
            if ($line -notmatch $manifestPattern) {
                $result.Status = 'unparseable'
                $result.Reason = "unrecognized manifest syntax on a line naming item $PublishedId"
                $result.Changes = @()
                $result.NewBody = $null
                return $result
            }
        }
    }

    if ($changes.Count -eq 0) {
        $result.Status = 'current'
        $result.NewBody = $Body
        return $result
    }
    $result.Status = 'refresh'
    $result.NewBody = $newBody
    $result.Changes = @($changes)
    return $result
}

# ---------------------------------------------------------------------------
# Offline self-test (qa convention: exit 0 = OK, exit 2 = regression). Pure
# fixtures modeled on real pinned cards (#52 single-mod, #278/#918 multi-mod,
# WOC exact banner); no gh/network so qa/run_selftests.ps1 stays CI-safe.
# ---------------------------------------------------------------------------
function Invoke-RefreshCardsSelfTest {
    $script:__rcpass = $true
    function Assert($cond, $desc) {
        $verdict = if ($cond) { 'PASS' } else { 'FAIL' }
        $colour = if ($cond) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $desc) -ForegroundColor $colour
        if (-not $cond) { $script:__rcpass = $false }
    }

    $singleCard = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Chaos Wastes Dev v0.7.315-dev; confirm `[ct:LOAD] v0.7.315-dev`; CT Workshop item `3733366926`, manifest `3145935923988224185`
**Topology:** Solo

1. Play the mission normally.

**Expected:** The run completes without a crash on v0.7.315-dev.
'@

    $plan = Get-VtCardRefreshPlan -Body $singleCard -PublishedId '3733366926' -NewVersion '0.7.320-dev' -LoadTag 'ct' -NewManifest '999000111'
    Assert ($plan.Status -eq 'refresh') 'single-mod card refreshes'
    Assert ($plan.MatchedBy -eq 'item-id+load-tag') 'single-mod card matched by both selectors'
    Assert ($plan.NewBody -notmatch '0\.7\.315-dev') 'no stale version token survives'
    Assert (([regex]::Matches($plan.NewBody, 'v0\.7\.320-dev')).Count -eq 3) 'all three version tokens advanced'
    Assert ($plan.NewBody -match 'manifest `999000111`') 'manifest token advanced with backticks preserved'
    Assert ($plan.NewBody -notmatch '3145935923988224185') 'stale manifest gone'
    Assert ($plan.NewBody -match '1\. Play the mission normally\.') 'step text untouched'

    $second = Get-VtCardRefreshPlan -Body $plan.NewBody -PublishedId '3733366926' -NewVersion '0.7.320-dev' -LoadTag 'ct' -NewManifest '999000111'
    Assert ($second.Status -eq 'current') 'second pass is a no-op (idempotent)'
    Assert ($second.NewBody -eq $plan.NewBody) 'second pass leaves the body byte-identical'

    $multiCard = @'
## CURRENT LIVE TEST

**Build/banner:** Career Weapon Variants v0.1.485-dev and Crafting in Modded Dev v0.8.112-dev; confirm `[cwv:LOAD] v0.1.485-dev` and `[cim:LOAD] v0.8.112-dev`
**Current deployed floor:** Career Weapon Variants item `3716869446`, ManifestID `1110000000`; Crafting in Modded item `3733366851`, ManifestID `2220000000`
**Topology:** Solo

1. Craft and equip the weapon.

**Expected:** No decode failure.
'@

    $plan = Get-VtCardRefreshPlan -Body $multiCard -PublishedId '3733366851' -NewVersion '0.8.120-dev' -LoadTag 'cim' -NewManifest '3330000000'
    Assert ($plan.Status -eq 'refresh') 'multi-mod card refreshes for the shipped mod'
    Assert ($plan.NewBody -match '\[cwv:LOAD\] v0\.1\.485-dev') 'sibling mod version anchor untouched'
    Assert ($plan.NewBody -match 'Career Weapon Variants v0\.1\.485-dev') 'sibling mod prose version untouched'
    Assert ($plan.NewBody -match 'item `3716869446`, ManifestID `1110000000`') 'sibling mod manifest untouched'
    Assert ($plan.NewBody -match '\[cim:LOAD\] v0\.8\.120-dev') 'shipped mod anchor advanced'
    Assert ($plan.NewBody -match 'Crafting in Modded Dev v0\.8\.120-dev') 'shipped mod prose version advanced'
    Assert ($plan.NewBody -match 'item `3733366851`, ManifestID `3330000000`') 'shipped mod manifest advanced'

    $plan = Get-VtCardRefreshPlan -Body $multiCard -PublishedId '3712896117' -NewVersion '0.13.1-dev' -LoadTag 'wt' -NewManifest '444'
    Assert ($plan.Status -eq 'not-applicable') 'card naming neither item id nor tag is not applicable'

    $noAnchor = @'
## CURRENT LIVE TEST

**Build/banner:** Some Mod v0.5.5-dev; item `3733366851`, ManifestID `2220000000`
**Topology:** Solo

1. Do the thing.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $noAnchor -PublishedId '3733366851' -NewVersion '0.8.120-dev' -LoadTag 'cim' -NewManifest '333'
    Assert ($plan.Status -eq 'unparseable') 'item-id card without a runtime anchor for the tag is skipped'
    Assert ($null -eq $plan.NewBody) 'unparseable card gets no partial rewrite'

    $shared = @'
## CURRENT LIVE TEST

**Build/banner:** confirm `[cwv:LOAD] v0.5.5-dev` and `[cim:LOAD] v0.5.5-dev`; Crafting in Modded item `3733366851`, ManifestID `2220000000`
**Topology:** Solo

1. Do the thing.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $shared -PublishedId '3733366851' -NewVersion '0.8.120-dev' -LoadTag 'cim' -NewManifest '333'
    Assert ($plan.Status -eq 'unparseable') 'version string shared with another anchored mod is skipped'

    $twoVersions = @'
## CURRENT LIVE TEST

**Build/banner:** confirm `[ct:LOAD] v1.0.0-dev`; earlier build `[ct:LOAD] v1.0.1-dev`
**Topology:** Solo

1. Do the thing.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $twoVersions -PublishedId '3733366926' -NewVersion '1.0.2-dev' -LoadTag 'ct'
    Assert ($plan.Status -eq 'unparseable') 'two distinct anchored versions for one tag is skipped'

    $wocCard = @'
## CURRENT LIVE TEST

**Build/banner:** exact banner: [WOC] v0.1.42-dev loaded
**Topology:** Solo

1. Equip the Blightreaper in the Keep.

**Expected:** The Blightreaper remains visible.
'@
    $plan = Get-VtCardRefreshPlan -Body $wocCard -PublishedId '3753880932' -NewVersion '0.1.50-dev' -LoadTag 'WOC'
    Assert ($plan.Status -eq 'refresh') 'exact versioned banner card refreshes'
    Assert ($plan.MatchedBy -eq 'load-tag') 'banner card selected by load tag'
    Assert ($plan.NewBody -match '\[WOC\] v0\.1\.50-dev loaded') 'exact banner version advanced'

    $beforeTag = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Cosmetics v0.9.183-dev; v0.1.484-dev `[cwv:LOAD]`; Cosmetics Workshop item `3715714222`, manifest `4186151811631343486`
**Topology:** Solo

1. Do the thing.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $beforeTag -PublishedId '3716869446' -NewVersion '0.1.490-dev' -LoadTag 'cwv'
    Assert ($plan.Status -eq 'refresh') 'version-before-anchor form refreshes'
    Assert ($plan.NewBody -match 'v0\.1\.490-dev `\[cwv:LOAD\]`') 'version-before-anchor token advanced'
    Assert ($plan.NewBody -match 'v0\.9\.183-dev') 'unanchored sibling prose version untouched'
    Assert ($plan.NewBody -match 'manifest `4186151811631343486`') 'sibling manifest untouched without -NewManifest for it'

    $plan = Get-VtCardRefreshPlan -Body $singleCard -PublishedId '3733366926' -NewVersion '0.7.320-dev' -LoadTag 'ct'
    Assert ($plan.Status -eq 'refresh') 'no -NewManifest still refreshes versions'
    Assert ($plan.NewBody -match 'manifest `3145935923988224185`') 'no -NewManifest leaves manifest untouched'

    $reversed = @'
## CURRENT LIVE TEST

**Build/banner:** confirm `[ct:LOAD] v0.7.315-dev`; ManifestID `3145935923988224185` for item `3733366926`
**Topology:** Solo

1. Do the thing.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $reversed -PublishedId '3733366926' -NewVersion '0.7.320-dev' -LoadTag 'ct' -NewManifest '999'
    Assert ($plan.Status -eq 'unparseable') 'reversed manifest syntax is skipped, not guessed'

    $manifestOnly = @'
## CURRENT LIVE TEST

**Build/banner:** confirm `[ct:LOAD] v0.7.320-dev`; CT Workshop item `3733366926`, manifest `3145935923988224185`
**Topology:** Solo

1. Do the thing.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $manifestOnly -PublishedId '3733366926' -NewVersion '0.7.320-dev' -LoadTag 'ct' -NewManifest '999'
    Assert ($plan.Status -eq 'refresh') 'version-current card still refreshes a stale manifest'
    Assert ($plan.NewBody -match 'manifest `999`') 'manifest-only refresh applied'
    Assert (@($plan.Changes).Count -eq 1) 'manifest-only refresh reports exactly one change'

    $notCard = "Just a comment mentioning item ``3733366926`` and v0.7.315-dev"
    $plan = Get-VtCardRefreshPlan -Body $notCard -PublishedId '3733366926' -NewVersion '0.7.320-dev' -LoadTag 'ct' -NewManifest '999'
    Assert ($plan.Status -eq 'not-applicable') 'non-card comment is never touched'

    $crlfCard = $singleCard -replace "`n", "`r`n"
    $plan = Get-VtCardRefreshPlan -Body $crlfCard -PublishedId '3733366926' -NewVersion '0.7.320-dev' -LoadTag 'ct' -NewManifest '999'
    Assert ($plan.Status -eq 'refresh') 'CRLF card body parses and refreshes'
    Assert ($plan.NewBody -match "`r`n") 'CRLF line endings preserved'

    Write-Host ''
    if ($script:__rcpass) {
        Write-Host '[refresh-cards -SelfTest] OK' -ForegroundColor Green
        exit 0
    }
    Write-Host '[refresh-cards -SelfTest] FAILED' -ForegroundColor Red
    exit 2
}

if ($SelfTest) { Invoke-RefreshCardsSelfTest }

# ---------------------------------------------------------------------------
# Live path (gh + GraphQL). Read pattern mirrors
# tools/github/check-lifecycle-cardinality.ps1: cursor-paginated open-issue
# and comment reads, comments (with isPinned) fetched only for issues carrying
# a ready lifecycle label -- the only issues doctrine allows pinned cards on.
# ---------------------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($PublishedId) -or [string]::IsNullOrWhiteSpace($NewVersion)) {
    Write-Host 'refresh-cards: -PublishedId and -NewVersion are required (or use -SelfTest).' -ForegroundColor Red
    exit 2
}
if ($Repository -notmatch '^([^/]+)/([^/]+)$') {
    Write-Host "refresh-cards: Repository must be OWNER/NAME, got '$Repository'." -ForegroundColor Red
    exit 2
}
$repoOwner = $Matches[1]
$repoName = $Matches[2]
$displayVersion = 'v' + $NewVersion.TrimStart('v', 'V')

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host 'refresh-cards: GitHub CLI (gh) is required.' -ForegroundColor Red
    exit 2
}

function Invoke-VtRefreshGraphQl {
    param([string]$Query, [hashtable]$StringFields, [hashtable]$TypedFields, [string]$BodyFile)

    $arguments = @('api', 'graphql', '-f', "query=$Query")
    if ($StringFields) {
        foreach ($name in @($StringFields.Keys | Sort-Object)) {
            $value = $StringFields[$name]
            if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) { continue }
            $arguments += @('-f', "$name=$value")
        }
    }
    if ($TypedFields) {
        foreach ($name in @($TypedFields.Keys | Sort-Object)) {
            $value = $TypedFields[$name]
            if ($null -eq $value) { continue }
            $arguments += @('-F', "$name=$value")
        }
    }
    if ($BodyFile) {
        # -F name=@file reads the raw file contents; keeps multi-KB card
        # bodies off the process command line entirely.
        $arguments += @('-F', "body=@$BodyFile")
    }

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $raw = & gh @arguments 2>&1 | Out-String } finally { $ErrorActionPreference = $prev }
    if ($LASTEXITCODE -ne 0) { throw "gh api graphql failed (exit $LASTEXITCODE): $raw" }
    $payload = $raw | ConvertFrom-Json
    if ($payload.errors) {
        $messages = @($payload.errors | ForEach-Object { $_.message }) -join '; '
        throw "GitHub GraphQL returned errors: $messages"
    }
    return $payload.data
}

function Get-VtReadyOpenIssueNumbers {
    param([string]$Owner, [string]$Name)
    $query = @'
query($owner: String!, $name: String!, $after: String) {
  repository(owner: $owner, name: $name) {
    issues(first: 100, after: $after, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
      nodes { number labels(first: 100) { nodes { name } } }
      pageInfo { hasNextPage endCursor }
    }
  }
}
'@
    $ready = @()
    $after = $null
    do {
        $vars = @{ owner = $Owner; name = $Name }
        if ($after) { $vars.after = $after }
        $data = Invoke-VtRefreshGraphQl -Query $query -StringFields $vars
        if (-not $data.repository) { throw "GitHub repository '$Owner/$Name' was not found." }
        $connection = $data.repository.issues
        foreach ($node in @($connection.nodes)) {
            $labelNames = @($node.labels.nodes | ForEach-Object { [string]$_.name })
            if (($labelNames -contains 'verify-fix') -or ($labelNames -contains 'diagnostics-armed')) {
                $ready += [int]$node.number
            }
        }
        $after = if ($connection.pageInfo.hasNextPage) { [string]$connection.pageInfo.endCursor } else { $null }
    } while ($after)
    # Plain return: the call site wraps with @() (comma-return would nest).
    return $ready
}

function Get-VtIssueStateAndComments {
    param([string]$Owner, [string]$Name, [int]$Number)
    $query = @'
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      state
      comments(first: 100, after: $after) {
        nodes { id databaseId body isPinned createdAt }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}
'@
    $comments = @()
    $state = $null
    $after = $null
    do {
        $vars = @{ owner = $Owner; name = $Name }
        if ($after) { $vars.after = $after }
        $data = Invoke-VtRefreshGraphQl -Query $query -StringFields $vars -TypedFields @{ number = $Number }
        if (-not $data.repository.issue) { throw "GitHub issue #$Number was not found." }
        $state = [string]$data.repository.issue.state
        $connection = $data.repository.issue.comments
        $comments += @($connection.nodes)
        $after = if ($connection.pageInfo.hasNextPage) { [string]$connection.pageInfo.endCursor } else { $null }
    } while ($after)
    return [pscustomobject]@{ State = $state; Comments = @($comments) }
}

function Update-VtIssueComment {
    param([string]$CommentNodeId, [string]$NewBody)
    $mutation = @'
mutation($id: ID!, $body: String!) {
  updateIssueComment(input: {id: $id, body: $body}) {
    issueComment { id }
  }
}
'@
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tempFile, $NewBody, (New-Object System.Text.UTF8Encoding($false)))
        Invoke-VtRefreshGraphQl -Query $mutation -StringFields @{ id = $CommentNodeId } -BodyFile $tempFile | Out-Null
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}

function Write-VtCardLineDiff {
    param([string]$OldBody, [string]$NewBody)
    $oldLines = $OldBody -split "`r?`n"
    $newLines = $NewBody -split "`r?`n"
    $max = [Math]::Min($oldLines.Count, $newLines.Count)
    for ($i = 0; $i -lt $max; $i++) {
        if ($oldLines[$i] -ne $newLines[$i]) {
            Write-Host ("      - " + $oldLines[$i]) -ForegroundColor DarkYellow
            Write-Host ("      + " + $newLines[$i]) -ForegroundColor DarkGreen
        }
    }
}

$modeLabel = if ($DryRun) { 'DRY RUN (no comment is written)' } else { 'live' }
Write-Host ("refresh-cards: item {0} -> {1}{2} [{3}]" -f $PublishedId, $displayVersion,
    $(if ($NewManifest) { ", manifest $NewManifest" } else { ', manifest unchanged' }), $modeLabel)

$summary = @{ refreshed = 0; current = 0; 'skipped-unparseable' = 0; 'skipped-closed' = 0; failed = 0 }
$cardsSeen = 0
$issuesExamined = 0
$exitCode = 0

try {
    $readyIssues = @(Get-VtReadyOpenIssueNumbers -Owner $repoOwner -Name $repoName)
    Write-Host ("  {0} open issue(s) carry a ready lifecycle label." -f $readyIssues.Count)
    if ($readyIssues.Count -gt $MaxIssues) {
        Write-Host ("  HARD CAP: examining only the {0} most recently updated of {1} ready issues; re-run for the remainder." -f $MaxIssues, $readyIssues.Count) -ForegroundColor Yellow
        # Array slice, not Select-Object -First: pipeline-stop kills child
        # scripts under ship.ps1 (memory: ps_select_first_kills_ship_pipeline).
        $readyIssues = @($readyIssues[0..($MaxIssues - 1)])
        $exitCode = 1
    }

    foreach ($issueNumber in $readyIssues) {
        $issue = Get-VtIssueStateAndComments -Owner $repoOwner -Name $repoName -Number $issueNumber
        $issuesExamined++

        $pinnedCards = @($issue.Comments | Where-Object {
            [bool]$_.isPinned -and (Test-VtCurrentLiveTestCard ([string]$_.body))
        })
        if ($pinnedCards.Count -eq 0) { continue }

        foreach ($card in $pinnedCards) {
            $plan = Get-VtCardRefreshPlan -Body ([string]$card.body) -PublishedId $PublishedId `
                -NewVersion $NewVersion -LoadTag $LoadTag -NewManifest $NewManifest
            if ($plan.Status -eq 'not-applicable') { continue }
            $cardsSeen++
            $cardRef = "#$issueNumber comment $($card.databaseId)"

            if ($issue.State -ne 'OPEN') {
                Write-Host ("  - {0}: skipped-closed (issue state {1})" -f $cardRef, $issue.State) -ForegroundColor DarkGray
                $summary['skipped-closed']++
                continue
            }
            switch ($plan.Status) {
                'unparseable' {
                    Write-Host ("  ! {0}: skipped-unparseable -- {1}" -f $cardRef, $plan.Reason) -ForegroundColor Yellow
                    $summary['skipped-unparseable']++
                    $exitCode = 1
                }
                'current' {
                    Write-Host ("  = {0}: current (already names {1})" -f $cardRef, $displayVersion) -ForegroundColor DarkGray
                    $summary['current']++
                }
                'refresh' {
                    Write-Host ("  + {0}: refreshed [{1}] -- {2}" -f $cardRef, $plan.MatchedBy, ($plan.Changes -join '; ')) -ForegroundColor Green
                    Write-VtCardLineDiff -OldBody ([string]$card.body) -NewBody $plan.NewBody
                    if (-not $DryRun) {
                        try {
                            Update-VtIssueComment -CommentNodeId ([string]$card.id) -NewBody $plan.NewBody
                            $summary['refreshed']++
                        }
                        catch {
                            Write-Host ("  ! {0}: updateIssueComment FAILED -- {1}" -f $cardRef, $_.Exception.Message) -ForegroundColor Yellow
                            $summary['failed']++
                            $exitCode = 1
                        }
                    }
                    else {
                        $summary['refreshed']++
                    }
                }
            }
        }
    }
}
catch {
    Write-Host ("refresh-cards: FAILED -- {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 2
}

Write-Host ''
Write-Host ("[refresh-cards] {0}refreshed={1} current={2} skipped-unparseable={3} skipped-closed={4} failed={5} (cards={6}, ready issues examined={7})" -f `
    $(if ($DryRun) { 'DRY RUN ' } else { '' }), $summary['refreshed'], $summary['current'], `
    $summary['skipped-unparseable'], $summary['skipped-closed'], $summary['failed'], $cardsSeen, $issuesExamined)
exit $exitCode
