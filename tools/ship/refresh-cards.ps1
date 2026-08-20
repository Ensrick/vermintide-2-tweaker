# tools/ship/refresh-cards.ps1
#
# Post-ship refresh and corrective reconciliation of pinned
# "## CURRENT LIVE TEST" card VERSION SURFACES (issues #1102 and #1343). The
# 2026-08-02 audit found all 31 sampled pinned cards naming
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
# versions, a version token on a sibling-attributed line, a version string
# shared with another mod's anchor, unrecognized manifest syntax), the card is
# SKIPPED and reported instead of guessed at. The #138 WT card is the canonical
# sibling-line case: normalize that card through the sanctioned lifecycle path;
# never weaken stream attribution to make the bulk refresher accept it.
# The edit is a GraphQL updateIssueComment on the pinned comment in place, so
# pin state and comment identity survive; it is idempotent (a second run finds
# every token already current and writes nothing).
#
# Selection: every OPEN issue currently carrying a ready lifecycle label
# (verify-fix / diagnostics-armed -- the only issues doctrine allows pinned
# cards on) whose PINNED exact card names the shipped mod's Workshop item id
# or carries the shipped mod's exact runtime anchor. When a load tag is shared
# by multiple streams, the exact mod directory + display/stream identity must
# attribute the anchor; a same-tag anchor alone can never authorize a version
# rewrite. Pin state comes from the
# same paginated GraphQL comment read the CI cardinality guard uses; every
# list is cursor-paginated (the 30-item default-page bug class of #1129).
#
# Invoked by tools/ship/ship.ps1 (step 6b) after the workshop_log has
# confirmed the upload; the ship treats any non-zero exit as a yellow warning
# and never fails on this step. Also runnable standalone.
#
# Manual verification recipe (read-only; writes nothing):
#   pwsh -File tools\ship\refresh-cards.ps1 -SelfTest
#   pwsh -File tools\ship\refresh-cards.ps1 -ReconcileAllStreams -DryRun
# Corrective live pass (only after the complete dry run is reviewed):
#   pwsh -File tools\ship\refresh-cards.ps1 -ReconcileAllStreams
#   pwsh -File tools\ship\refresh-cards.ps1 -DryRun `
#       -PublishedId 3716869446 -NewVersion 0.1.485-dev -LoadTag cwv `
#       -ModDirectory character_weapon_variants `
#       -StreamIdentity "Career Weapon Variants" `
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
    [string]$ModDirectory,
    [string]$StreamIdentity,
    [string]$NewManifest,
    [string]$Repository = 'Ensrick/vermintide-2-tweaker',
    [string]$DeploymentManifestPath,
    [int]$MaxIssues = 1000,
    [switch]$ReconcileAllStreams,
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

$loadTagResolutionHelpers = Join-Path $PSScriptRoot 'load-tag-resolution.ps1'
if (-not (Test-Path -LiteralPath $loadTagResolutionHelpers -PathType Leaf)) {
    Write-Host "refresh-cards: shared LOAD-tag resolver not found: $loadTagResolutionHelpers" -ForegroundColor Red
    exit 2
}
. $loadTagResolutionHelpers

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

function Get-VtStreamIdentityPattern {
    param([string]$Identity)
    if ([string]::IsNullOrWhiteSpace($Identity)) { return $null }
    $trimmed = $Identity.Trim()
    if ($trimmed -match '^(.*?)[ \t]+Dev$') {
        $base = [regex]::Escape($matches[1].Trim())
        return '(?i)(?<![0-9A-Za-z])' + $base +
            '[ \t]*(?:Dev|\([ \t]*Dev[ \t]*\))(?![0-9A-Za-z])'
    }

    $literal = [regex]::Escape($trimmed)
    # A public identity must not match the prefix of its Dev sibling.
    return '(?i)(?<![0-9A-Za-z])' + $literal +
        '(?![0-9A-Za-z]|[ \t]+Dev\b|[ \t]*\([ \t]*Dev\b)'
}

function Test-VtStreamIdentityPresent {
    param([string]$Body, [string]$Identity)
    if ([string]::IsNullOrWhiteSpace($Body)) { return $false }
    $pattern = Get-VtStreamIdentityPattern -Identity $Identity
    return [bool]($pattern -and $Body -match $pattern)
}

function Get-VtMatchRangeDistance {
    param($Left, $Right)
    $leftStart = [int]$Left.Index
    $leftEnd = $leftStart + [int]$Left.Length
    $rightStart = [int]$Right.Index
    $rightEnd = $rightStart + [int]$Right.Length
    if ($leftEnd -le $rightStart) { return $rightStart - $leftEnd }
    if ($rightEnd -le $leftStart) { return $leftStart - $rightEnd }
    return 0
}

function Get-VtCfgStreamIdentity {
    param([string]$CfgText, [string]$Directory)
    if ([string]::IsNullOrWhiteSpace($CfgText) -or
        $CfgText -notmatch 'title[ \t]*=[ \t]*"([^"]+)"') { return $null }
    $identity = $matches[1] -replace ('[ \t]+v' + $script:VtSemverPattern + '$'), ''
    if ($Directory -match '_dev$' -and $identity -notmatch '(?i)[ \t]+Dev$') {
        $identity += ' Dev'
    }
    return $identity
}

function Get-VtStreamInventory {
    param([string]$RepoRoot)
    $rows = @()
    foreach ($directory in Get-ChildItem -LiteralPath $RepoRoot -Directory) {
        $name = $directory.Name
        $cfgPath = Join-Path $directory.FullName 'itemV2.cfg'
        $luaRoot = Join-Path $directory.FullName "scripts\mods\$name"
        $luaPath = Join-Path $luaRoot "$name.lua"
        if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $luaPath -PathType Leaf)) { continue }
        $cfg = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
        $publishedMatch = [regex]::Match($cfg, 'published_id[ \t]*=[ \t]*(\d+)L')
        $loadTagResolution = Get-VtLoadTagResolution -MainLuaPath $luaPath -LuaRoot $luaRoot
        if (-not $loadTagResolution.Success) {
            if ($loadTagResolution.Source -eq 'missing') { continue }
            throw "LOAD-tag inventory conflict for '$name': $($loadTagResolution.Reason)"
        }
        if (-not $publishedMatch.Success) { continue }
        $rows += [pscustomobject]@{
            Directory = $name
            PublishedId = $publishedMatch.Groups[1].Value
            LoadTag = $loadTagResolution.LoadTag
            Identity = Get-VtCfgStreamIdentity -CfgText $cfg -Directory $name
        }
    }
    return $rows
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
        [string]$NewManifest,
        [bool]$SharedLoadTag = $false,
        [string]$StreamIdentity,
        [string[]]$SiblingPublishedIds = @(),
        [string[]]$SiblingStreamIdentities = @()
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

    $ourIdentityPresent = Test-VtStreamIdentityPresent -Body $Body -Identity $StreamIdentity
    $siblingIdentityPresent = $false
    foreach ($identity in @($SiblingStreamIdentities)) {
        if (Test-VtStreamIdentityPresent -Body $Body -Identity $identity) {
            $siblingIdentityPresent = $true
            break
        }
    }
    $siblingIdPresent = $false
    foreach ($siblingId in @($SiblingPublishedIds)) {
        if ($siblingId -and $Body -match ('(?<!\d)' + [regex]::Escape($siblingId) + '(?!\d)')) {
            $siblingIdPresent = $true
            break
        }
    }

    $anchorLineOurIdentity = $false
    $anchorLineSiblingIdentity = $false
    $itemLineOurIdentity = $false
    $itemLineSiblingIdentity = $false
    $lineAttributions = @()
    $tagEsc = [regex]::Escape($LoadTag)
    $anchorLinePattern = '(?i)(?:\[' + $tagEsc + ':LOAD\]`?[ \t]*`?v' +
        $script:VtSemverPattern + '|v' + $script:VtSemverPattern +
        '`?[ \t]*`?\[' + $tagEsc + ':LOAD\]|\[' + $tagEsc + '\][ \t]+v' +
        $script:VtSemverPattern + '[ \t]+loaded)'
    foreach ($line in ($Body -split "`r?`n")) {
        $ourIdentityPattern = Get-VtStreamIdentityPattern -Identity $StreamIdentity
        $ourIdentityMatches = @()
        if ($ourIdentityPattern) {
            $ourIdentityMatches = @([regex]::Matches($line, $ourIdentityPattern))
        }
        $lineHasOurIdentity = $ourIdentityMatches.Count -gt 0
        $siblingIdentityMatches = @()
        foreach ($identity in @($SiblingStreamIdentities)) {
            $identityPattern = Get-VtStreamIdentityPattern -Identity $identity
            if ($identityPattern) {
                $siblingIdentityMatches += @([regex]::Matches($line, $identityPattern))
            }
        }
        $lineHasSiblingIdentity = $siblingIdentityMatches.Count -gt 0
        $lineAnchors = @()
        foreach ($anchorMatch in @([regex]::Matches($line, $anchorLinePattern))) {
            $anchorOwnership = 'none'
            if ($lineHasOurIdentity -and $lineHasSiblingIdentity) {
                $ourDistance = [int]::MaxValue
                foreach ($m in $ourIdentityMatches) {
                    $ourDistance = [Math]::Min($ourDistance,
                        (Get-VtMatchRangeDistance -Left $m -Right $anchorMatch))
                }
                $siblingDistance = [int]::MaxValue
                foreach ($m in $siblingIdentityMatches) {
                    $siblingDistance = [Math]::Min($siblingDistance,
                        (Get-VtMatchRangeDistance -Left $m -Right $anchorMatch))
                }
                if ($ourDistance -lt $siblingDistance) { $anchorOwnership = 'owned' }
                elseif ($siblingDistance -lt $ourDistance) { $anchorOwnership = 'foreign' }
                else {
                    $anchorOwnership = 'ambiguous'
                }
            }
            else {
                if ($lineHasOurIdentity) { $anchorOwnership = 'owned' }
                elseif ($lineHasSiblingIdentity) { $anchorOwnership = 'foreign' }
            }
            if ($anchorOwnership -eq 'owned') { $anchorLineOurIdentity = $true }
            elseif ($anchorOwnership -eq 'foreign') { $anchorLineSiblingIdentity = $true }
            elseif ($anchorOwnership -eq 'ambiguous') {
                $anchorLineOurIdentity = $true
                $anchorLineSiblingIdentity = $true
            }
            $lineAnchors += [pscustomobject]@{
                Match = $anchorMatch
                Ownership = $anchorOwnership
            }
        }
        if ($pidEsc -and $line -match ('(?<!\d)' + $pidEsc + '(?!\d)') -and $lineHasOurIdentity) {
            $itemLineOurIdentity = $true
        }
        foreach ($siblingId in @($SiblingPublishedIds)) {
            if ($siblingId -and $line -match ('(?<!\d)' + [regex]::Escape($siblingId) + '(?!\d)') -and
                $lineHasSiblingIdentity) {
                $itemLineSiblingIdentity = $true
                break
            }
        }
        $lineAttributions += [pscustomobject]@{
            Line = $line
            OurIdentityMatches = @($ourIdentityMatches)
            SiblingIdentityMatches = @($siblingIdentityMatches)
            Anchors = @($lineAnchors)
        }
    }

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

    $versionOwnership = 'owned'
    if ($SharedLoadTag) {
        if ($anchorLineOurIdentity -and -not $anchorLineSiblingIdentity) {
            $versionOwnership = 'owned'
        }
        elseif ($anchorLineSiblingIdentity -and -not $anchorLineOurIdentity) {
            $versionOwnership = 'foreign'
        }
        elseif ($anchorLineOurIdentity -and $anchorLineSiblingIdentity) {
            $versionOwnership = 'ambiguous'
        }
        elseif ($itemLineOurIdentity -and -not $itemLineSiblingIdentity) {
            $versionOwnership = 'owned'
        }
        elseif ($itemLineSiblingIdentity -and -not $itemLineOurIdentity) {
            $versionOwnership = 'foreign'
        }
        elseif ($itemLineOurIdentity -and $itemLineSiblingIdentity) {
            $versionOwnership = 'ambiguous'
        }
        elseif ($ourIdentityPresent -and -not $siblingIdentityPresent) {
            $versionOwnership = 'owned'
        }
        elseif ($siblingIdentityPresent -and -not $ourIdentityPresent) {
            $versionOwnership = 'foreign'
        }
        elseif ($ourIdentityPresent -and $siblingIdentityPresent) {
            $versionOwnership = 'ambiguous'
        }
        elseif ($pidPresent -and -not $siblingIdPresent) {
            $versionOwnership = 'owned'
        }
        elseif ($siblingIdPresent -and -not $pidPresent) {
            $versionOwnership = 'foreign'
        }
        else {
            $versionOwnership = 'ambiguous'
        }

        if ($versionOwnership -eq 'foreign' -and -not $pidPresent) { return $result }
        if ($versionOwnership -eq 'ambiguous') {
            $result.Status = 'unparseable'
            $result.Reason = "shared load tag '$LoadTag' has no unique '$StreamIdentity' stream attribution"
            return $result
        }
    }
    if ($pidPresent -and $ourAnchors.Count -gt 0) { $result.MatchedBy = 'item-id+load-tag' }
    elseif ($pidPresent) { $result.MatchedBy = 'item-id' }
    else { $result.MatchedBy = 'load-tag' }

    # ---- version surface -------------------------------------------------
    $ourVersions = @($ourAnchors | ForEach-Object { [string]$_.Version } | Select-Object -Unique)
    if ($versionOwnership -eq 'foreign') {
        $ourVersions = @()
    }
    elseif ($ourVersions.Count -eq 0) {
        $result.Status = 'unparseable'
        $result.Reason = "no exact runtime anchor for load tag '$LoadTag' -- cannot attribute version tokens"
        return $result
    }
    if ($ourVersions.Count -gt 1) {
        $result.Status = 'unparseable'
        $result.Reason = "load tag '$LoadTag' anchors " + $ourVersions.Count + ' distinct versions (' + ($ourVersions -join ', ') + ')'
        return $result
    }
    $oldVersion = if ($ourVersions.Count -eq 1) { $ourVersions[0] } else { $null }

    if ($oldVersion -and $oldVersion -ne $cleanVersion) {
        foreach ($pair in $otherAnchors) {
            if ([string]$pair.Version -eq $oldVersion) {
                $result.Status = 'unparseable'
                $result.Reason = "version v$oldVersion is also anchored to '$($pair.Tag)' -- a sweep would stomp the other mod"
                return $result
            }
        }
        if ($SharedLoadTag) {
            $oldEsc = [regex]::Escape($oldVersion)
            $oldToken = '(?<![0-9A-Za-z.-])v?' + $oldEsc +
                '(?![0-9A-Za-z-])(?!\.[0-9A-Za-z])'
            foreach ($row in $lineAttributions) {
                $oldMatches = @([regex]::Matches([string]$row.Line, $oldToken))
                if ($oldMatches.Count -eq 0 -or $row.SiblingIdentityMatches.Count -eq 0) { continue }

                $ownedTokenCount = 0
                foreach ($oldMatch in $oldMatches) {
                    $insideOwnedAnchor = $false
                    foreach ($anchor in @($row.Anchors)) {
                        $anchorMatch = $anchor.Match
                        if ($anchor.Ownership -eq 'owned' -and
                            $oldMatch.Index -ge $anchorMatch.Index -and
                            ($oldMatch.Index + $oldMatch.Length) -le
                                ($anchorMatch.Index + $anchorMatch.Length)) {
                            $insideOwnedAnchor = $true
                            break
                        }
                    }
                    if ($insideOwnedAnchor) {
                        $ownedTokenCount++
                        continue
                    }

                    $ourDistance = [int]::MaxValue
                    foreach ($identityMatch in @($row.OurIdentityMatches)) {
                        $ourDistance = [Math]::Min($ourDistance,
                            (Get-VtMatchRangeDistance -Left $identityMatch -Right $oldMatch))
                    }
                    $siblingDistance = [int]::MaxValue
                    foreach ($identityMatch in @($row.SiblingIdentityMatches)) {
                        $siblingDistance = [Math]::Min($siblingDistance,
                            (Get-VtMatchRangeDistance -Left $identityMatch -Right $oldMatch))
                    }
                    if ($ourDistance -lt $siblingDistance) { $ownedTokenCount++ }
                }

                # A shared-tag line may mention both streams (the established
                # #290 warning shape), but every old-version token must still
                # be exactly attributable to this stream. Any extra token tied
                # to sibling prose makes the all-card sweep unsafe.
                if ($ownedTokenCount -ne $oldMatches.Count) {
                    $result.Status = 'unparseable'
                    $result.Reason = "version v$oldVersion is also associated with a sibling stream on the same line"
                    return $result
                }
            }
        }
    }

    $newBody = $Body
    $changes = @()
    if ($oldVersion -and $oldVersion -ne $cleanVersion -and $cleanVersion) {
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

function Get-VtRefreshedCardAuthorityDecision {
    param([string]$Body, $Authority)
    if (-not $Authority) {
        return [pscustomobject]@{
            Valid = $false
            Errors = @('live-card-authority-unavailable')
        }
    }
    return Get-VtLiveTestCardSelection -Comments @([pscustomobject]@{ body = $Body }) `
        -Authority $Authority -EnforceAuthority
}

# Issue #1343: a sequence of otherwise-correct single-stream rewrites cannot
# repair a cross-mod card because every intermediate body still names at least
# one stale sibling build and therefore fails deployed-source authority. This
# planner rewrites every exact anchored build in one candidate, then the caller
# validates that whole candidate once before any GitHub mutation.
function Get-VtAllStreamReconcilePlan {
    param([string]$Body, [object[]]$Streams)

    $result = [pscustomobject]@{
        Status = 'not-applicable'
        Reason = $null
        NewBody = $null
        Changes = @()
    }
    if (-not (Test-VtCurrentLiveTestCard $Body)) { return $result }

    $streamsByTag = @{}
    $streamsByItem = @{}
    foreach ($stream in @($Streams)) {
        $tagKey = ([string]$stream.LoadTag).ToLowerInvariant()
        if (-not $streamsByTag.ContainsKey($tagKey)) { $streamsByTag[$tagKey] = @() }
        $streamsByTag[$tagKey] = @($streamsByTag[$tagKey]) + @($stream)
        $streamsByItem[[string]$stream.PublishedId] = $stream
    }

    $lineEnding = if ($Body.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @($Body -split "`r?`n")
    $changes = New-Object System.Collections.Generic.List[string]
    $recognized = $false
    $seenPairs = @{}
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $line = [string]$lines[$lineIndex]
        $edits = New-Object System.Collections.Generic.List[object]

        foreach ($tagKey in @($streamsByTag.Keys | Sort-Object)) {
            $tagStreams = @($streamsByTag[$tagKey])
            $tagEsc = [regex]::Escape([string]$tagStreams[0].LoadTag)
            $patterns = @(
                ('(?i)\[' + $tagEsc + ':LOAD\]`?[ \t]*`?v(?<version>' + $script:VtSemverPattern + ')'),
                ('(?i)v(?<version>' + $script:VtSemverPattern + ')`?[ \t]*`?\[' + $tagEsc + ':LOAD\]'),
                ('(?i)\[' + $tagEsc + '\][ \t]+v(?<version>' + $script:VtSemverPattern + ')[ \t]+loaded')
            )
            foreach ($pattern in $patterns) {
                foreach ($match in @([regex]::Matches($line, $pattern))) {
                    $recognized = $true
                    $versionGroup = $match.Groups['version']
                    $oldVersion = [string]$versionGroup.Value
                    $candidates = @($tagStreams)
                    if ($candidates.Count -gt 1) {
                        $byItem = @($candidates | Where-Object {
                            $line -match ('(?<!\d)' + [regex]::Escape([string]$_.PublishedId) + '(?!\d)')
                        })
                        if ($byItem.Count -eq 1) {
                            $candidates = $byItem
                        }
                        else {
                            $byIdentity = @($candidates | Where-Object {
                                Test-VtStreamIdentityPresent -Body $line -Identity ([string]$_.Identity)
                            })
                            if ($byIdentity.Count -eq 1) {
                                $candidates = $byIdentity
                            }
                            else {
                                $byCurrentVersion = @($candidates | Where-Object {
                                    ([string]$_.Version).Equals($oldVersion, [System.StringComparison]::OrdinalIgnoreCase)
                                })
                                if ($byCurrentVersion.Count -eq 1) { $candidates = $byCurrentVersion }
                            }
                        }
                    }
                    if ($candidates.Count -ne 1) {
                        $result.Status = 'unparseable'
                        $result.Reason = "shared load tag '$($tagStreams[0].LoadTag)' on line $($lineIndex + 1) has no unique stream attribution"
                        return $result
                    }
                    $stream = $candidates[0]
                    $newVersion = ([string]$stream.Version).TrimStart('v', 'V')
                    if (-not $oldVersion.Equals($newVersion, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $edits.Add([pscustomobject]@{
                            Index = [int]$versionGroup.Index
                            Length = [int]$versionGroup.Length
                            Replacement = $newVersion
                        })
                        $changes.Add("line $($lineIndex + 1): $($stream.ModId) v$oldVersion -> v$newVersion")
                    }
                }
            }
        }

        # Apply right-to-left so match offsets remain valid.
        foreach ($edit in @($edits | Sort-Object Index -Descending)) {
            $line = $line.Substring(0, $edit.Index) + $edit.Replacement +
                $line.Substring($edit.Index + $edit.Length)
        }

        # Workshop coordinates are optional. If a card supplies them they must
        # be complete and unique; when no Steam-authoritative manifest is
        # available to this corrective lane, remove only incomplete duplicates
        # instead of inventing or copying a ManifestID.
        $pairPattern = '(?i)(?:Workshop[ \t]+)?item[ \t]+`?(?<item>\d+)`?[ \t]*,[ \t]*(?:ManifestID|manifest)[ \t]+`?(?<manifest>\d+)`?'
        $pairMatches = @([regex]::Matches($line, $pairPattern))
        if ($pairMatches.Count -gt 0) { $recognized = $true }
        $pairEdits = New-Object System.Collections.Generic.List[object]
        foreach ($pair in $pairMatches) {
            $key = $pair.Groups['item'].Value + '=' + $pair.Groups['manifest'].Value
            if ($seenPairs.ContainsKey($key)) {
                # Remove the whole duplicate clause so a friendly-name prefix
                # is not stranded as "Tweaker: Cosmetics ;". Delimiters are
                # deliberately excluded from edit ranges: adjacent duplicate
                # clauses then cannot overlap, and punctuation is normalized
                # once after every right-to-left edit is applied.
                $deleteStart = [int]$pair.Index
                $deleteEnd = [int]($pair.Index + $pair.Length)
                $beforePair = $line.Substring(0, $pair.Index)
                $previousSemicolon = $beforePair.LastIndexOf(';')
                if ($previousSemicolon -ge 0) {
                    $deleteStart = $previousSemicolon + 1
                }
                else {
                    $heading = [regex]::Match($line, '^[ \t]*(?:[-*][ \t]+)?\*\*[^*]+:\*\*[ \t]*')
                    if ($heading.Success) { $deleteStart = $heading.Length }
                    else { $deleteStart = 0 }
                }
                $afterPair = $line.Substring($deleteEnd)
                $nextSemicolon = $afterPair.IndexOf(';')
                if ($nextSemicolon -ge 0) { $deleteEnd += $nextSemicolon }
                else { $deleteEnd = $line.Length }
                $pairEdits.Add([pscustomobject]@{
                    Index=$deleteStart; Length=($deleteEnd - $deleteStart); Replacement=''
                })
                $changes.Add("line $($lineIndex + 1): removed duplicate Workshop pair $key")
            }
            else { $seenPairs[$key] = $true }
        }
        foreach ($edit in @($pairEdits | Sort-Object Index -Descending)) {
            $line = $line.Substring(0, $edit.Index) + $edit.Replacement +
                $line.Substring($edit.Index + $edit.Length)
        }

        $completeRanges = @([regex]::Matches($line, $pairPattern))
        $incompletePattern = '(?i)(?:Workshop[ \t]+)?item[ \t]+`?(?<item>\d+)`?'
        $incompleteEdits = New-Object System.Collections.Generic.List[object]
        foreach ($itemMatch in @([regex]::Matches($line, $incompletePattern))) {
            $insidePair = $false
            foreach ($pair in $completeRanges) {
                if ($itemMatch.Index -ge $pair.Index -and
                    ($itemMatch.Index + $itemMatch.Length) -le ($pair.Index + $pair.Length)) {
                    $insidePair = $true
                    break
                }
            }
            if (-not $insidePair -and $streamsByItem.ContainsKey($itemMatch.Groups['item'].Value)) {
                $incompleteEdits.Add([pscustomobject]@{ Index=$itemMatch.Index; Length=$itemMatch.Length; Replacement='' })
                $changes.Add("line $($lineIndex + 1): removed incomplete Workshop item $($itemMatch.Groups['item'].Value)")
            }
        }
        foreach ($edit in @($incompleteEdits | Sort-Object Index -Descending)) {
            $line = $line.Substring(0, $edit.Index) + $edit.Replacement +
                $line.Substring($edit.Index + $edit.Length)
        }
        $line = $line -replace '[ \t]+,', ',' -replace ',[ \t]*,', ',' -replace ';[ \t]*;', ';'
        $line = $line -replace '(:\*\*)[ \t]*;[ \t]*', '$1 ' -replace '[ \t]*;[ \t]*$', ''
        $lines[$lineIndex] = $line
    }

    if (-not $recognized) { return $result }
    if ($changes.Count -eq 0) {
        $result.Status = 'current'
        $result.NewBody = $Body
        return $result
    }
    $newBody = $lines -join $lineEnding
    if ($newBody -ceq $Body) {
        $result.Status = 'current'
        $result.NewBody = $Body
        return $result
    }
    $result.Status = 'refresh'
    $result.NewBody = $newBody
    $result.Changes = @($changes.ToArray())
    return $result
}

function Test-VtRefreshManifestInputAllowed {
    param([string]$Path, [bool]$IsDryRun)
    # A local manifest is useful for offline/read-only rehearsal, but its bytes
    # do not prove the current hosted release. Never let fixture input authorize
    # a GitHub card mutation.
    return [string]::IsNullOrWhiteSpace($Path) -or $IsDryRun
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

    $resolverFixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
        ("vt2-load-tag-{0}" -f ([guid]::NewGuid().ToString('N')))
    $resolverModName = 'crafting_in_modded_dev'
    $resolverModRoot = Join-Path $resolverFixtureRoot $resolverModName
    $resolverLuaRoot = Join-Path $resolverModRoot "scripts\mods\$resolverModName"
    $resolverMain = Join-Path $resolverLuaRoot "$resolverModName.lua"
    $resolverHelper = Join-Path $resolverLuaRoot '_cim_bootstrap_runtime.lua'
    $resolverOtherHelper = Join-Path $resolverLuaRoot '_other_bootstrap_runtime.lua'
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    try {
        New-Item -ItemType Directory -Path $resolverLuaRoot -Force | Out-Null
        [System.IO.File]::WriteAllText(
            (Join-Path $resolverModRoot 'itemV2.cfg'),
            "title = `"Crafting in Modded v0.8.124-dev`"`r`npublished_id = 3733366851L`r`n",
            $utf8NoBom
        )
        [System.IO.File]::WriteAllText($resolverMain, 'local MOD_VERSION = "0.8.124-dev"', $utf8NoBom)
        [System.IO.File]::WriteAllText($resolverHelper, 'mod:echo("[cim:LOAD]")', $utf8NoBom)

        $helperOnly = Get-VtLoadTagResolution -MainLuaPath $resolverMain `
            -LuaRoot $resolverLuaRoot -FallbackTag $resolverModName
        Assert ($helperOnly.Success -and $helperOnly.LoadTag -eq 'cim' -and $helperOnly.Source -eq 'lua-root') `
            'helper-only CIM marker wins before the ship directory fallback'

        $helperInventory = @(Get-VtStreamInventory -RepoRoot $resolverFixtureRoot)
        Assert ($helperInventory.Count -eq 1 -and $helperInventory[0].Directory -eq $resolverModName -and
            $helperInventory[0].LoadTag -eq 'cim') `
            'card inventory consumes the shared helper-owned tag resolution'

        [System.IO.File]::WriteAllText($resolverMain, 'mod:echo("[main:LOAD]")', $utf8NoBom)
        [System.IO.File]::WriteAllText($resolverOtherHelper, 'mod:echo("[other:LOAD]")', $utf8NoBom)
        $mainPreferred = Get-VtLoadTagResolution -MainLuaPath $resolverMain `
            -LuaRoot $resolverLuaRoot -FallbackTag $resolverModName
        Assert ($mainPreferred.Success -and $mainPreferred.LoadTag -eq 'main' -and $mainPreferred.Source -eq 'main') `
            'one main marker remains authoritative over conflicting helper markers'

        [System.IO.File]::WriteAllText($resolverMain, 'local MOD_VERSION = "0.8.124-dev"', $utf8NoBom)
        $otherHelperItem = Get-Item -LiteralPath $resolverOtherHelper
        $otherHelperItem.Attributes = $otherHelperItem.Attributes -bor [System.IO.FileAttributes]::Hidden
        Assert (((Get-Item -LiteralPath $resolverOtherHelper -Force).Attributes -band
            [System.IO.FileAttributes]::Hidden) -ne 0) `
            'conflicting helper fixture carries the actual Windows Hidden attribute'
        $conflictingHelpers = Get-VtLoadTagResolution -MainLuaPath $resolverMain `
            -LuaRoot $resolverLuaRoot -FallbackTag $resolverModName
        Assert (-not $conflictingHelpers.Success -and $conflictingHelpers.Source -eq 'root-conflict' -and
            $conflictingHelpers.Candidates.Count -eq 2 -and
            [string]::IsNullOrWhiteSpace($conflictingHelpers.LoadTag)) `
            'hidden conflicting helper tags fail closed instead of selecting the directory fallback'

        $inventoryConflict = $null
        try { $null = @(Get-VtStreamInventory -RepoRoot $resolverFixtureRoot) }
        catch { $inventoryConflict = $_.Exception.Message }
        Assert ($inventoryConflict -match "LOAD-tag inventory conflict for 'crafting_in_modded_dev'" -and
            $inventoryConflict -match 'cim, other') `
            'card inventory surfaces a deterministic hidden-helper conflict'

        [System.IO.File]::SetAttributes($resolverOtherHelper, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::WriteAllText($resolverOtherHelper, 'mod:echo("[CIM:LOAD]")', $utf8NoBom)
        [System.IO.File]::SetAttributes($resolverOtherHelper, [System.IO.FileAttributes]::Hidden)
        $caseConflict = Get-VtLoadTagResolution -MainLuaPath $resolverMain `
            -LuaRoot $resolverLuaRoot -FallbackTag $resolverModName
        Assert (-not $caseConflict.Success -and $caseConflict.Source -eq 'root-conflict' -and
            $caseConflict.Candidates.Count -eq 2 -and $caseConflict.Candidates -ccontains 'cim' -and
            $caseConflict.Candidates -ccontains 'CIM') `
            'case-variant literal LOAD tags remain distinct and fail closed'

        $markerFree = Resolve-VtLoadTag -MainLuaText 'local x = 1' `
            -LuaTexts @('local y = 2') -FallbackTag 'marker_free_mod'
        Assert ($markerFree.Success -and $markerFree.LoadTag -eq 'marker_free_mod' -and
            $markerFree.Source -eq 'fallback') `
            'marker-free ship streams retain the historical directory fallback'
    }
    finally {
        if (Test-Path -LiteralPath $resolverFixtureRoot) {
            Remove-Item -LiteralPath $resolverFixtureRoot -Recurse -Force
        }
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

    $refreshFixtureAuthority = [pscustomobject]@{ Records = @([pscustomobject]@{
        ModId='ct_dev'; Version='0.7.320-dev'; WorkshopId='3733366926'
        LoadRoutes=@([pscustomobject]@{Marker='[ct:LOAD]'})
        ExactBannerRoutes=@(); CommandRoutes=@(); MenuSurfaces=@()
        ReceiptRoutes=@([pscustomobject]@{
            Marker='[ct:491]'; Signature='[ct:491] tick=%d'; Bound=$false
        })
    }) }
    $refreshAuthorityDecision = Get-VtRefreshedCardAuthorityDecision -Body $plan.NewBody -Authority $refreshFixtureAuthority
    Assert $refreshAuthorityDecision.Valid 'source-authoritative refreshed card may be written'
    $unboundedRefresh = $plan.NewBody.Replace(
        'The run completes without a crash on v0.7.320-dev.',
        'Exactly one `[ct:491] tick=1` receipt appears.'
    )
    $unboundedRefreshDecision = Get-VtRefreshedCardAuthorityDecision -Body $unboundedRefresh -Authority $refreshFixtureAuthority
    Assert (-not $unboundedRefreshDecision.Valid -and @($unboundedRefreshDecision.Errors | Where-Object {
        $_ -like 'diagnostic-evidence-not-bounded:*'
    }).Count -eq 1) 'refresher rejects a rewritten card whose exact receipt route is unbounded'
    $missingRefreshAuthority = Get-VtRefreshedCardAuthorityDecision -Body $plan.NewBody
    Assert (-not $missingRefreshAuthority.Valid -and $missingRefreshAuthority.Errors -contains 'live-card-authority-unavailable') 'refresher fails closed without deployed-source authority'
    Assert (-not (Test-VtRefreshManifestInputAllowed -Path 'fixture-manifest.json' -IsDryRun $false)) 'local manifest cannot authorize a live card mutation'
    Assert (Test-VtRefreshManifestInputAllowed -Path 'fixture-manifest.json' -IsDryRun $true) 'local manifest remains available for a read-only dry run'

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

    $wtDevCard = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons Dev `v0.12.294-dev`; confirm `[wt:LOAD] v0.12.294-dev`
**Current WT receipt:** Tweaker: Weapons Dev, Workshop item `3748824853`, manifest `700`.
**Stream note:** public Tweaker: Weapons prints the same `[wt:LOAD]` prefix; do not enable both.
**Topology:** Solo

1. Test the dev-only command.

**Expected:** Works on v0.12.294-dev.
'@
    $plan = Get-VtCardRefreshPlan -Body $wtDevCard -PublishedId '3712896117' `
        -NewVersion '0.12.294-beta' -LoadTag 'wt' -NewManifest '800' `
        -SharedLoadTag $true -StreamIdentity 'Tweaker: Weapons' `
        -SiblingPublishedIds @('3748824853') -SiblingStreamIdentities @('Tweaker: Weapons Dev')
    Assert ($plan.Status -eq 'not-applicable') 'public WT cannot select a Dev card through the shared load tag'
    Assert ($null -eq $plan.NewBody) 'cross-stream rejection leaves the Dev card untouched'

    $plan = Get-VtCardRefreshPlan -Body $wtDevCard -PublishedId '3748824853' `
        -NewVersion '0.12.295-dev' -LoadTag 'wt' -NewManifest '900' `
        -SharedLoadTag $true -StreamIdentity 'Tweaker: Weapons Dev' `
        -SiblingPublishedIds @('3712896117') -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'refresh') 'same-stream WT Dev card refreshes'
    Assert ($plan.NewBody -notmatch '0\.12\.294-dev') 'same-stream refresh advances every Dev token'
    Assert (([regex]::Matches($plan.NewBody, '0\.12\.295-dev')).Count -eq 3) 'same-stream Dev version count is exact'
    Assert ($plan.NewBody -match 'manifest `900`') 'same-stream Dev manifest advances'

    $wtSiblingThenVersion = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons Dev v0.12.294-dev; confirm `[wt:LOAD] v0.12.294-dev`
**Compatibility note:** public Tweaker: Weapons is mentioned with deliberately long intervening prose that exceeds every former distance guess before v0.12.294-dev.
**Topology:** Solo

1. Test the dev-only command.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $wtSiblingThenVersion -PublishedId '3748824853' `
        -NewVersion '0.12.295-dev' -LoadTag 'wt' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons Dev' -SiblingPublishedIds @('3712896117') `
        -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'unparseable') 'sibling then distant old version fails closed before the global sweep'
    Assert ($plan.Reason -match 'associated with a sibling stream') 'sibling prose collision reports its owner'
    Assert ($null -eq $plan.NewBody) 'sibling-then-version collision cannot partially rewrite the card'

    $wtVersionThenSibling = $wtSiblingThenVersion -replace
        'public Tweaker: Weapons is mentioned with deliberately long intervening prose that exceeds every former distance guess before v0\.12\.294-dev',
        'v0.12.294-dev is separated by deliberately long prose that exceeds every former distance guess before public Tweaker: Weapons'
    $plan = Get-VtCardRefreshPlan -Body $wtVersionThenSibling -PublishedId '3748824853' `
        -NewVersion '0.12.295-dev' -LoadTag 'wt' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons Dev' -SiblingPublishedIds @('3712896117') `
        -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'unparseable') 'distant old version then sibling fails closed regardless of token order'
    Assert ($null -eq $plan.NewBody) 'version-then-sibling collision cannot partially rewrite the card'

    $wtIssue290Shape = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons Dev v0.12.294-dev; confirm `[wt:LOAD] v0.12.294-dev` and do not enable public Tweaker: Weapons simultaneously
**Current WT receipt:** Tweaker: Weapons Dev `v0.12.294-dev`, Workshop item `3748824853`, manifest `700`.
**Topology:** Solo

1. Test the dev-only command.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $wtIssue290Shape -PublishedId '3748824853' `
        -NewVersion '0.12.295-dev' -LoadTag 'wt' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons Dev' -SiblingPublishedIds @('3712896117') `
        -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'refresh') '#290 same-line unversioned public warning preserves exact Dev ownership'
    Assert (([regex]::Matches($plan.NewBody, 'v0\.12\.295-dev')).Count -eq 3) '#290 shape advances exactly its three owned tokens'

    $wtIssue290Collision = $wtIssue290Shape -replace
        'public Tweaker: Weapons simultaneously',
        'public Tweaker: Weapons v0.12.294-dev simultaneously'
    $plan = Get-VtCardRefreshPlan -Body $wtIssue290Collision -PublishedId '3748824853' `
        -NewVersion '0.12.295-dev' -LoadTag 'wt' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons Dev' -SiblingPublishedIds @('3712896117') `
        -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'unparseable') '#290 same-line warning with a sibling old version fails closed'
    Assert ($null -eq $plan.NewBody) '#290 sibling collision cannot partially rewrite the card'

    $wtIssue138Shape = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons Dev `v0.12.294-dev`; confirm `[wt:LOAD] v0.12.294-dev`
**Stream note:** public Tweaker: Weapons (`v0.12.290-beta`) shares the prefix. Read the Dev chat header `=== wt regression_test (v0.12.294-dev) ===` instead.
**Topology:** Solo

1. Test the dev-only command.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $wtIssue138Shape -PublishedId '3748824853' `
        -NewVersion '0.12.295-dev' -LoadTag 'wt' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons Dev' -SiblingPublishedIds @('3712896117') `
        -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'unparseable') '#138 sibling-only line with a Dev token is deliberately skipped'
    Assert ($plan.Reason -match 'associated with a sibling stream') '#138 skip records the exact attribution reason'
    Assert ($null -eq $plan.NewBody) '#138 skip leaves the entire card untouched for sanctioned normalization'

    $wtMirrorCard = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons (Dev) v0.12.294-dev; confirm `[wt:LOAD] v0.12.294-dev`
**Workshop receipts:** Dev item `3748824853`, manifest `700`; public beta mirror item `3712896117`, manifest `600`.
**Topology:** Solo

1. Run the dev-only command.

**Expected:** Works on v0.12.294-dev.
'@
    $plan = Get-VtCardRefreshPlan -Body $wtMirrorCard -PublishedId '3712896117' `
        -NewVersion '0.12.294-beta' -LoadTag 'wt' -NewManifest '800' `
        -SharedLoadTag $true -StreamIdentity 'Tweaker: Weapons' `
        -SiblingPublishedIds @('3748824853') -SiblingStreamIdentities @('Tweaker: Weapons Dev')
    Assert ($plan.Status -eq 'refresh') 'sibling-anchored card permits an exact item-only manifest refresh'
    Assert ($plan.NewBody -match '\[wt:LOAD\] v0\.12\.294-dev') 'item-only manifest refresh preserves the Dev anchor'
    Assert ($plan.NewBody -match 'Dev item `3748824853`, manifest `700`') 'item-only manifest refresh preserves sibling receipt'
    Assert ($plan.NewBody -match 'public beta mirror item `3712896117`, manifest `800`') 'item-only manifest refresh advances only its item'

    $plan = Get-VtCardRefreshPlan -Body $wtMirrorCard -PublishedId '3748824853' `
        -NewVersion '0.12.295-dev' -LoadTag 'wt' -NewManifest '900' `
        -SharedLoadTag $true -StreamIdentity 'Tweaker: Weapons Dev' `
        -SiblingPublishedIds @('3712896117') -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'refresh') 'Dev stream owns its named anchor despite a public mirror receipt'
    Assert ($plan.NewBody -match '\[wt:LOAD\] v0\.12\.295-dev') 'Dev stream advances its own anchor'
    Assert ($plan.NewBody -match 'public beta mirror item `3712896117`, manifest `600`') 'Dev refresh preserves public mirror receipt'

    $wtAmbiguousCard = @'
## CURRENT LIVE TEST

**Build/banner:** confirm `[wt:LOAD] v0.12.294-dev`
**Topology:** Solo

1. Test the weapon.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $wtAmbiguousCard -PublishedId '3712896117' `
        -NewVersion '0.12.294-beta' -LoadTag 'wt' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons' -SiblingPublishedIds @('3748824853') `
        -SiblingStreamIdentities @('Tweaker: Weapons Dev')
    Assert ($plan.Status -eq 'unparseable') 'shared-tag card with no stream identity fails closed'
    Assert ($plan.Reason -match 'no unique') 'shared-tag ambiguity reports its exact reason'

    Assert (Test-VtStreamIdentityPresent -Body 'Enable Tweaker: Weapons (Dev).' -Identity 'Tweaker: Weapons Dev') `
        'Dev stream identity accepts the parenthesized display form'
    Assert (-not (Test-VtStreamIdentityPresent -Body 'Enable Tweaker: Weapons Dev.' -Identity 'Tweaker: Weapons')) `
        'public stream identity rejects the Dev suffix'
    Assert (Test-VtStreamIdentityPresent -Body 'Enable public Tweaker: Weapons.' -Identity 'Tweaker: Weapons') `
        'public stream identity matches its exact display form'

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

    $allStreams = @(
        [pscustomobject]@{ ModId='career_weapon_variants'; Directory='character_weapon_variants'; PublishedId='3716869446'; LoadTag='cwv'; Identity='Career Weapon Variants'; Version='0.1.521-dev' },
        [pscustomobject]@{ ModId='tweaker_cosmetics'; Directory='tweaker_cosmetics'; PublishedId='3715714222'; LoadTag='cosmetics'; Identity='Tweaker: Cosmetics'; Version='0.9.215-dev' },
        [pscustomobject]@{ ModId='tweaker_weapons'; Directory='tweaker_weapons'; PublishedId='3712896117'; LoadTag='wt'; Identity='Tweaker: Weapons'; Version='0.13.2-beta' },
        [pscustomobject]@{ ModId='tweaker_weapons_dev'; Directory='tweaker_weapons_dev'; PublishedId='3748824853'; LoadTag='wt'; Identity='Tweaker: Weapons Dev'; Version='0.12.268-dev' }
    )
    $crossModCard = @'
## CURRENT LIVE TEST

**Build/banner:** Career Weapon Variants `[cwv:LOAD] v0.1.518-dev`; Tweaker: Cosmetics `[cosmetics:LOAD] v0.9.211-dev`; Workshop item `3716869446`
**Topology:** Solo

1. Test the feature.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $crossModCard -Streams $allStreams
    Assert ($plan.Status -eq 'refresh') 'all-stream reconciliation plans one atomic cross-mod candidate'
    Assert ($plan.NewBody -match '\[cwv:LOAD\] v0\.1\.521-dev' -and
        $plan.NewBody -match '\[cosmetics:LOAD\] v0\.9\.215-dev') `
        'all recognized cross-mod anchors advance together'
    Assert ($plan.NewBody -notmatch 'Workshop item `3716869446`') `
        'known incomplete Workshop coordinates are removed rather than fabricated'

    $sharedTagCard = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons Dev `[wt:LOAD] v0.12.267-dev`; Workshop item `3748824853`, ManifestID `111`
**Topology:** Solo

1. Test the feature.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $sharedTagCard -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and $plan.NewBody -match '\[wt:LOAD\] v0\.12\.268-dev') `
        'shared LOAD tag resolves through exact stream identity and Workshop item'
    Assert ($plan.NewBody -notmatch '0\.13\.2-beta') 'shared LOAD tag never crosses into the public sibling'

    $ambiguousAllStreamCard = @'
## CURRENT LIVE TEST

**Build/banner:** confirm `[wt:LOAD] v0.12.111-dev`
**Topology:** Solo

1. Test the feature.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $ambiguousAllStreamCard -Streams $allStreams
    Assert ($plan.Status -eq 'unparseable' -and $plan.Reason -match 'no unique stream attribution') `
        'all-stream reconciliation fails closed on an unattributed shared LOAD tag'

    $duplicatePairCard = @'
## CURRENT LIVE TEST

**Build/banner:** Career Weapon Variants `[cwv:LOAD] v0.1.521-dev`; Workshop item `3716869446`, ManifestID `222`
**Receipt:** Workshop item `3716869446`, ManifestID `222`
**Topology:** Solo

1. Test the feature.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $duplicatePairCard -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and
        ([regex]::Matches($plan.NewBody, '3716869446')).Count -eq 1) `
        'duplicate complete Workshop coordinates are normalized across card lines'

    $namedDuplicateCard = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Cosmetics `[cosmetics:LOAD] v0.9.211-dev`; Tweaker: Weapons Dev `[wt:LOAD] v0.12.268-dev`; Cosmetics Workshop item `3715714222`, manifest `333`; Tweaker: Weapons Dev item `3748824853`, ManifestID `555`
**Workshop receipts:** Tweaker: Cosmetics item `3715714222`, ManifestID `333`; Career Weapon Variants item `3716869446`, ManifestID `444`; Tweaker: Weapons Dev item `3748824853`, ManifestID `555`
**Topology:** Solo

1. Test the feature.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $namedDuplicateCard -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and $plan.NewBody -match
        '\*\*Workshop receipts:\*\* Career Weapon Variants item `3716869446`, ManifestID `444`(?:\r?\n|$)') `
        'duplicate first and last receipt clauses leave the unique middle clause intact'
    Assert ($plan.NewBody -notmatch 'Tweaker: Cosmetics[ \t]+;') `
        'duplicate coordinate cleanup leaves no dangling friendly-name clause'

    $noKnownSurfaceCard = @'
## CURRENT LIVE TEST

**Build/banner:** tester records the visible version manually.
**Topology:** Solo

1. Test the feature.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $noKnownSurfaceCard -Streams $allStreams
    Assert ($plan.Status -eq 'not-applicable') 'card without a recognized deployed surface is untouched'

    $currentCrlfAllStreamCard = ($sharedTagCard -replace '0\.12\.267-dev', '0.12.268-dev') -replace "`n", "`r`n"
    $plan = Get-VtAllStreamReconcilePlan -Body $currentCrlfAllStreamCard -Streams $allStreams
    Assert ($plan.Status -eq 'current' -and $plan.NewBody -ceq $currentCrlfAllStreamCard) `
        'all-stream reconciliation preserves a current CRLF card byte-for-byte'

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

if (-not $ReconcileAllStreams -and
    ([string]::IsNullOrWhiteSpace($PublishedId) -or [string]::IsNullOrWhiteSpace($NewVersion) -or
     [string]::IsNullOrWhiteSpace($LoadTag) -or [string]::IsNullOrWhiteSpace($ModDirectory) -or
     [string]::IsNullOrWhiteSpace($StreamIdentity))) {
    Write-Host 'refresh-cards: -PublishedId, -NewVersion, -LoadTag, -ModDirectory, and -StreamIdentity are required (or use -SelfTest).' -ForegroundColor Red
    exit 2
}
if ($ReconcileAllStreams -and ($PublishedId -or $NewVersion -or $LoadTag -or $ModDirectory -or
    $StreamIdentity -or $NewManifest)) {
    Write-Host 'refresh-cards: -ReconcileAllStreams cannot be combined with single-stream coordinates.' -ForegroundColor Red
    exit 2
}
if (-not (Test-VtRefreshManifestInputAllowed -Path $DeploymentManifestPath -IsDryRun ([bool]$DryRun))) {
    Write-Host 'refresh-cards: -DeploymentManifestPath is fixture input and requires -DryRun; live mutations must use the hosted latest release.' -ForegroundColor Red
    exit 2
}
if ($Repository -notmatch '^([^/]+)/([^/]+)$') {
    Write-Host "refresh-cards: Repository must be OWNER/NAME, got '$Repository'." -ForegroundColor Red
    exit 2
}
$repoOwner = $Matches[1]
$repoName = $Matches[2]
$displayVersion = if ($ReconcileAllStreams) { $null } else { 'v' + $NewVersion.TrimStart('v', 'V') }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
try {
    $deploymentManifest = Get-VtCardDeploymentManifest -Repository $Repository -ManifestJsonPath $DeploymentManifestPath
    $sourceAuthority = Get-VtCardSourceAuthority -RepoRoot $repoRoot -DeploymentManifest $deploymentManifest
    $liveTestAuthority = New-VtLiveTestCardAuthority -Source $sourceAuthority -DeploymentManifest $deploymentManifest
}
catch {
    Write-Host ("refresh-cards: deployed live-test authority unavailable -- {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 2
}
$streamInventory = @(Get-VtStreamInventory -RepoRoot $repoRoot)
$reconcileStreams = @()
if ($ReconcileAllStreams) {
    try {
        foreach ($inventoryStream in $streamInventory) {
            $authorityRows = @($sourceAuthority.Records | Where-Object {
                [string]$_.WorkshopId -eq [string]$inventoryStream.PublishedId
            })
            if ($authorityRows.Count -ne 1) {
                throw "Workshop item '$($inventoryStream.PublishedId)' did not resolve to exactly one deployed-source record."
            }
            $authorityRow = $authorityRows[0]
            if (-not ([string]$authorityRow.Dir).Equals([string]$inventoryStream.Directory,
                [System.StringComparison]::Ordinal)) {
                throw "directory drift for Workshop item '$($inventoryStream.PublishedId)': inventory=$($inventoryStream.Directory), deployed=$($authorityRow.Dir)."
            }
            if ([string]::IsNullOrWhiteSpace([string]$inventoryStream.Identity)) {
                throw "stream '$($inventoryStream.Directory)' has no exact display identity."
            }
            $reconcileStreams += [pscustomobject]@{
                ModId = [string]$authorityRow.ModId
                Directory = [string]$inventoryStream.Directory
                PublishedId = [string]$inventoryStream.PublishedId
                LoadTag = [string]$inventoryStream.LoadTag
                Identity = [string]$inventoryStream.Identity
                Version = ([string]$authorityRow.Version).TrimStart('v', 'V')
            }
        }
        if ($reconcileStreams.Count -ne @($sourceAuthority.Records).Count) {
            throw "stream inventory/deployed-source cardinality drift: inventory=$($reconcileStreams.Count), deployed=$(@($sourceAuthority.Records).Count)."
        }
    }
    catch {
        Write-Host ("refresh-cards: all-stream inventory unavailable -- {0}" -f $_.Exception.Message) -ForegroundColor Red
        exit 2
    }
}
else {
    $currentStreams = @($streamInventory | Where-Object { $_.Directory -eq $ModDirectory })
    if ($currentStreams.Count -ne 1) {
        Write-Host "refresh-cards: exact mod directory '$ModDirectory' did not resolve to one stream." -ForegroundColor Red
        exit 2
    }
    $currentStream = $currentStreams[0]
    if ([string]$currentStream.PublishedId -ne $PublishedId -or
        -not ([string]$currentStream.LoadTag).Equals($LoadTag, [System.StringComparison]::OrdinalIgnoreCase) -or
        -not ([string]$currentStream.Identity).Equals($StreamIdentity, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("refresh-cards: stream identity mismatch for {0}: expected item={1}, tag={2}, identity={3}; got item={4}, tag={5}, identity={6}." -f `
            $ModDirectory, $currentStream.PublishedId, $currentStream.LoadTag, $currentStream.Identity,
            $PublishedId, $LoadTag, $StreamIdentity) -ForegroundColor Red
        exit 2
    }
    $siblingStreams = @($streamInventory | Where-Object {
        $_.Directory -ne $ModDirectory -and
        ([string]$_.LoadTag).Equals($LoadTag, [System.StringComparison]::OrdinalIgnoreCase)
    })
    $sharedLoadTag = $siblingStreams.Count -gt 0
    $siblingPublishedIds = @($siblingStreams | ForEach-Object { [string]$_.PublishedId })
    $siblingStreamIdentities = @($siblingStreams | ForEach-Object { [string]$_.Identity })
}

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
if ($ReconcileAllStreams) {
    Write-Host ("refresh-cards: reconcile all {0} deployed streams atomically [{1}]" -f `
        $reconcileStreams.Count, $modeLabel)
}
else {
    Write-Host ("refresh-cards: {0} ({1}, item {2}) -> {3}{4} [{5}]" -f $StreamIdentity, $ModDirectory, $PublishedId, $displayVersion,
        $(if ($NewManifest) { ", manifest $NewManifest" } else { ', manifest unchanged' }), $modeLabel)
}

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
            if ($ReconcileAllStreams) {
                $plan = Get-VtAllStreamReconcilePlan -Body ([string]$card.body) -Streams $reconcileStreams
            }
            else {
                $plan = Get-VtCardRefreshPlan -Body ([string]$card.body) -PublishedId $PublishedId `
                    -NewVersion $NewVersion -LoadTag $LoadTag -NewManifest $NewManifest `
                    -SharedLoadTag $sharedLoadTag -StreamIdentity $StreamIdentity `
                    -SiblingPublishedIds $siblingPublishedIds -SiblingStreamIdentities $siblingStreamIdentities
            }
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
                    if ($ReconcileAllStreams) {
                        $authorityDecision = Get-VtRefreshedCardAuthorityDecision -Body ([string]$card.body) -Authority $liveTestAuthority
                        if (-not $authorityDecision.Valid) {
                            Write-Host ("  ! {0}: skipped-unparseable -- current card fails deployed-source authority: {1}" -f `
                                $cardRef, (@($authorityDecision.Errors) -join ', ')) -ForegroundColor Yellow
                            $summary['skipped-unparseable']++
                            $exitCode = 1
                            continue
                        }
                        Write-Host ("  = {0}: current (all recognized surfaces pass authority)" -f $cardRef) -ForegroundColor DarkGray
                    }
                    else {
                        Write-Host ("  = {0}: current (already names {1})" -f $cardRef, $displayVersion) -ForegroundColor DarkGray
                    }
                    $summary['current']++
                }
                'refresh' {
                    $authorityDecision = Get-VtRefreshedCardAuthorityDecision -Body $plan.NewBody -Authority $liveTestAuthority
                    if (-not $authorityDecision.Valid) {
                        Write-Host ("  ! {0}: skipped-unparseable -- refreshed card fails deployed-source authority: {1}" -f `
                            $cardRef, (@($authorityDecision.Errors) -join ', ')) -ForegroundColor Yellow
                        $summary['skipped-unparseable']++
                        $exitCode = 1
                        continue
                    }
                    $matchedBy = if ($ReconcileAllStreams) { 'all-streams' } else { $plan.MatchedBy }
                    Write-Host ("  + {0}: refreshed [{1}] -- {2}" -f $cardRef, $matchedBy, ($plan.Changes -join '; ')) -ForegroundColor Green
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
