# tools/ship/refresh-cards.ps1
#
# Post-ship refresh and corrective reconciliation of pinned
# "## CURRENT LIVE TEST" card DEPLOYMENT SURFACES (issues #1102 and #1343). The
# 2026-08-02 audit found all 31 sampled pinned cards naming
# superseded builds (5-18 patches behind), so a tester following a card fails
# the [id:LOAD] confirmation on a perfectly correct build. This script walks
# the open live-test queue and mechanically advances ONLY the just-shipped
# mod's stale version, manifest, and typed current-artifact tokens inside each
# pinned exact card:
#
#   * version tokens attributed to the shipped mod through its exact runtime
#     anchor ([<tag>:LOAD] vX.Y.Z / vX.Y.Z [<tag>:LOAD] / "[<TAG>] vX.Y.Z
#     loaded" exact banners) are rewritten to the shipped MOD_VERSION;
#   * "item `<published_id>`, ManifestID `<N>`" / "Workshop item
#     `<published_id>`, manifest `<N>`" tokens are rewritten to the manifest
#     the workshop_log confirmed for THIS upload;
#   * `Current receipt`, `Current <stream> receipt`, `Exact live artifact`,
#     `Live artifact`, and `Exact source` fields are bound to the hosted
#     release manifest's source commit, root bundle/SHA-256, and ZIP/SHA-256.
#     Exact `Feature provenance` and every untyped evidence heading remain
#     historical and byte-identical.
#   * full deployed artifact authority validates typed sibling claims without
#     granting write ownership over them. Stale sibling artifact/build claims
#     require all-stream reconciliation or evidence-backed corrective upkeep.
#     Sibling Steam ManifestIDs are preserved, not independently authenticated.
#
# Card step text, expected needles, topology, feature provenance, untyped
# evidence, and every other mod's tokens are NEVER touched. When a card's
# deployment surfaces do not match the expected patterns exactly (no anchor for
# the shipped tag, two distinct anchored versions, a version token on a
# sibling-attributed line, a version string shared with another mod's anchor,
# unrecognized manifest/current-artifact syntax), the card is SKIPPED and
# reported instead of guessed at. The #138 WT card is the canonical
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

function Get-VtStreamIdentitySet {
    param($Stream)
    return @(@([string]$Stream.Identity) + @($Stream.LegacyIdentities) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { ([string]$_).Trim() } | Sort-Object -Unique)
}

function Test-VtAnyStreamIdentityPresent {
    param([string]$Body, $Stream)
    foreach ($identity in @(Get-VtStreamIdentitySet $Stream)) {
        if (Test-VtStreamIdentityPresent -Body $Body -Identity $identity) { return $true }
    }
    return $false
}

function Get-VtVersionTrack {
    param([string]$Version)
    $clean = ([string]$Version).Trim().TrimStart('v', 'V')
    $match = [regex]::Match($clean, '-(?<track>[A-Za-z][A-Za-z0-9.]*)$')
    if ($match.Success) { return $match.Groups['track'].Value.ToLowerInvariant() }
    return 'release'
}

function Get-VtBuildClauseRange {
    param([string]$Line, [int]$Index)
    $searchIndex = [Math]::Max(0, [Math]::Min($Index, $Line.Length - 1))
    $leftSemicolon = $Line.LastIndexOf([char]';', $searchIndex)
    $leftPipe = $Line.LastIndexOf([char]'|', $searchIndex)
    $left = [Math]::Max($leftSemicolon, $leftPipe)
    $start = $left + 1
    $rightSemicolon = $Line.IndexOf([char]';', $searchIndex)
    $rightPipe = $Line.IndexOf([char]'|', $searchIndex)
    $right = if ($rightSemicolon -lt 0) { $rightPipe }
        elseif ($rightPipe -lt 0) { $rightSemicolon }
        else { [Math]::Min($rightSemicolon, $rightPipe) }
    $end = if ($right -ge 0) { $right } else { $Line.Length }
    return [pscustomobject]@{
        Start = $start
        End = $end
        Text = $Line.Substring($start, $end - $start)
    }
}

function Get-VtPreviousBuildClauseRange {
    param([string]$Line, [int]$ClauseStart)
    if ($ClauseStart -le 0) { return $null }
    $separator = $ClauseStart - 1
    if ($Line[$separator] -ne [char]';' -and $Line[$separator] -ne [char]'|') { return $null }
    $left = if ($separator -gt 0) {
        $leftSemicolon = $Line.LastIndexOf([char]';', $separator - 1)
        $leftPipe = $Line.LastIndexOf([char]'|', $separator - 1)
        [Math]::Max($leftSemicolon, $leftPipe)
    }
    else { -1 }
    $start = $left + 1
    return [pscustomobject]@{
        Start = $start
        End = $separator
        Text = $Line.Substring($start, $separator - $start)
    }
}

function Get-VtAllStreamAnchorContext {
    param([string]$Line, $ClauseRange, [string]$OldVersion)
    $context = [string]$ClauseRange.Text
    $previous = Get-VtPreviousBuildClauseRange -Line $Line `
        -ClauseStart ([int]$ClauseRange.Start)
    if (-not $previous) { return $context }
    $oldPattern = '(?<![0-9A-Za-z.-])v?' + [regex]::Escape($OldVersion) +
        '(?![0-9A-Za-z-])(?!\.[0-9A-Za-z])'
    $hasRuntimeMarker = $previous.Text -match '\[[A-Za-z][A-Za-z0-9_-]*:LOAD\]' -or
        $previous.Text -match ('(?i)\[[A-Za-z][A-Za-z0-9_-]*\][ \t]+v?' +
            $script:VtSemverPattern + '[ \t]+loaded')
    if ($previous.Text -match $oldPattern -and -not $hasRuntimeMarker) {
        return $previous.Text + ';' + $context
    }
    return $context
}

function Resolve-VtAllStreamAnchor {
    param(
        [object[]]$Candidates,
        [string]$Clause,
        [string]$Body,
        [string]$OldVersion
    )
    $remaining = @($Candidates)
    if ($remaining.Count -le 1) { return $remaining }

    $byItem = @($remaining | Where-Object {
        $Clause -match ('(?<!\d)' + [regex]::Escape([string]$_.PublishedId) + '(?!\d)')
    })

    # Public and development streams intentionally share several LOAD tags.
    # A stale but explicit -dev / -beta / clean-release suffix is durable
    # stream evidence even when its numeric version no longer matches either
    # deployed row. This cannot cross a stream boundary because exactly one
    # candidate must own the same release track.
    $oldTrack = Get-VtVersionTrack $OldVersion
    $byTrack = @($remaining | Where-Object {
        (Get-VtVersionTrack ([string]$_.Version)) -ceq $oldTrack
    })

    $byIdentity = @($remaining | Where-Object {
        Test-VtAnyStreamIdentityPresent -Body $Clause -Stream $_
    })
    if ($byIdentity.Count -gt 1) {
        $scored = @($byIdentity | ForEach-Object {
            $stream = $_
            $matchingLengths = @(Get-VtStreamIdentitySet $stream | Where-Object {
                Test-VtStreamIdentityPresent -Body $Clause -Identity ([string]$_)
            } | ForEach-Object { ([string]$_).Length })
            [pscustomobject]@{
                Stream = $stream
                Length = if ($matchingLengths.Count -gt 0) {
                    ($matchingLengths | Measure-Object -Maximum).Maximum
                }
                else { 0 }
            }
        })
        $maxLength = ($scored | Measure-Object -Property Length -Maximum).Maximum
        $byIdentity = @($scored | Where-Object { $_.Length -eq $maxLength } |
            ForEach-Object { $_.Stream })
    }
    $byCurrentVersion = @($remaining | Where-Object {
        ([string]$_.Version).Equals($OldVersion, [System.StringComparison]::OrdinalIgnoreCase)
    })

    # A complete item coordinate elsewhere in the card is a final exact
    # discriminator, but only when precisely one sibling item is named.
    $byBodyItem = @($remaining | Where-Object {
        $Body -match ('(?<!\d)' + [regex]::Escape([string]$_.PublishedId) + '(?!\d)')
    })

    # Every exact discriminator that resolves to one sibling must agree.
    # Track-only evidence is useful for old shared-tag cards, but it must never
    # overrule a contradictory item or display identity. A contradiction
    # returns the original ambiguous set so the caller performs zero writes.
    $evidenceRows = New-Object System.Collections.Generic.List[object]
    foreach ($candidateSet in @(
        [pscustomobject]@{ Rows = @($byItem) },
        [pscustomobject]@{ Rows = @($byIdentity) },
        [pscustomobject]@{ Rows = @($byTrack) },
        [pscustomobject]@{ Rows = @($byCurrentVersion) },
        [pscustomobject]@{ Rows = @($byBodyItem) }
    )) {
        if (@($candidateSet.Rows).Count -eq 1) { $evidenceRows.Add($candidateSet.Rows[0]) }
    }
    if ($evidenceRows.Count -eq 0) { return $remaining }
    $keys = @($evidenceRows | ForEach-Object {
        ([string]$_.Directory) + '|' + ([string]$_.PublishedId)
    } | Sort-Object -Unique)
    if ($keys.Count -ne 1) { return $remaining }
    return @($remaining | Where-Object {
        (([string]$_.Directory) + '|' + ([string]$_.PublishedId)) -ceq $keys[0]
    })
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
    # Exact historical display names still present on pinned cards. These are
    # aliases only for attribution; canonical output always comes from cfg.
    # CWV's former Career name is evidenced by #343/#807 and this tool's
    # pre-rename fixtures. No fuzzy title matching is allowed.
    $legacyIdentitiesByDirectory = @{
        character_weapon_variants = @('Career Weapon Variants', 'Career Weapon Variants Dev')
    }
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
            LegacyIdentities = if ($legacyIdentitiesByDirectory.ContainsKey($name)) {
                @($legacyIdentitiesByDirectory[$name])
            }
            else { @() }
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
        [string[]]$SiblingStreamIdentities = @(),
        $ArtifactTarget,
        [object[]]$ArtifactTargets
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
    $anchorLineForeignConflict = $false
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
            elseif ($anchorOwnership -eq 'foreign') {
                $anchorLineSiblingIdentity = $true
                if ($lineHasOurIdentity) { $anchorLineForeignConflict = $true }
            }
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
        if ($versionOwnership -eq 'foreign' -and $pidPresent -and $anchorLineForeignConflict) {
            $result.Status = 'unparseable'
            $result.Reason = "shared load tag '$LoadTag' anchor conflicts with same-line '$StreamIdentity' attribution"
            return $result
        }
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

    # Current/live artifact headings are deployment-bound authority surfaces,
    # just like the version and optional ManifestID. The shared reviewer owns
    # both parsing and the pure replacement candidate used by strict policy.
    $validationTargets = @($ArtifactTarget)
    $artifactOwner = $null
    if ($PSBoundParameters.ContainsKey('ArtifactTargets')) {
        $validationTargets = @($ArtifactTargets)
        $artifactOwner = ConvertTo-VtCardArtifactTarget $ArtifactTarget
        $fullArtifactTargets = @($validationTargets | ForEach-Object { ConvertTo-VtCardArtifactTarget $_ })
        $ownerRows = @($fullArtifactTargets | Where-Object {
            [string]$_.ModId -ceq [string]$artifactOwner.ModId -and
            [string]$_.Directory -ceq [string]$artifactOwner.Directory -and
            [string]$_.WorkshopId -ceq [string]$artifactOwner.WorkshopId
        })
        $ownerFields = @('ModId','Directory','WorkshopId','Version','SourceCommit',
            'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')
        $ownerMatches = $ownerRows.Count -eq 1 -and
            [string]$artifactOwner.WorkshopId -ceq [string]$PublishedId -and
            [string]$artifactOwner.Version -ceq [string]$cleanVersion
        foreach ($field in $ownerFields) {
            if ([string]::IsNullOrWhiteSpace([string]$artifactOwner.$field) -or
                $ownerRows.Count -ne 1 -or
                [string]$ownerRows[0].$field -cne [string]$artifactOwner.$field) { $ownerMatches = $false }
        }
        if (-not $ownerMatches) {
            $result.Status = 'unparseable'
            $result.Reason = 'publishing-artifact-context-mismatch'
            return $result
        }
    }
    $artifactReview = Get-VtCardCurrentArtifactReview -Card $newBody -Targets $validationTargets
    if ($artifactReview.Status -eq 'unparseable') {
        $result.Status = 'unparseable'
        $result.Reason = @($artifactReview.StructuralErrors) -join ', '
        $result.Changes = @()
        $result.NewBody = $null
        return $result
    }
    if ($artifactOwner) {
        $ownerKey = [string]$artifactOwner.ModId
        $siblingDrift = @($artifactReview.Claims | Where-Object {
            [string]$_.Target -cne $ownerKey -and
            -not ([string]$_.Claimed).Equals([string]$_.Expected, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($siblingDrift.Count -gt 0) {
            $result.Status = 'unparseable'
            $result.Reason = 'sibling-current-artifact-drift:' + (($siblingDrift | ForEach-Object {
                '{0}/{1}@line{2}' -f $_.Target, $_.Field, $_.Line
            }) -join ', ')
            return $result
        }
        # The shared reviewer owns parsing. Its claim ledger must also prove
        # every changed line is exclusively this publisher's before accepting
        # NewCard; full read authority never expands the mutation scope.
        $beforeArtifactLines = @($newBody -split "`r?`n")
        $afterArtifactLines = @([string]$artifactReview.NewCard -split "`r?`n")
        $editsOwned = $beforeArtifactLines.Count -eq $afterArtifactLines.Count
        for ($i = 0; $editsOwned -and $i -lt $beforeArtifactLines.Count; $i++) {
            if ($beforeArtifactLines[$i] -ceq $afterArtifactLines[$i]) { continue }
            $lineClaims = @($artifactReview.Claims | Where-Object { [int]$_.Line -eq ($i + 1) })
            if ($lineClaims.Count -eq 0 -or @($lineClaims | Where-Object {
                [string]$_.Target -cne $ownerKey
            }).Count -gt 0) { $editsOwned = $false }
        }
        if (-not $editsOwned) {
            $result.Status = 'unparseable'
            $result.Reason = 'publishing-artifact-edit-ownership-unproven'
            return $result
        }
        # Cover earlier version/Manifest edits too, including recognized typed
        # receipts with NO artifact Claims. Only truly unqualified fields may
        # inherit the validated final Build/banner's sole selected owner.
        $finalArtifactBody = if ($artifactReview.Status -eq 'stale') { [string]$artifactReview.NewCard } else { $newBody }
        $selectedArtifactTargets = @(Get-VtCardArtifactSelectedTargets -Card $finalArtifactBody -Targets $fullArtifactTargets)
        $originalSegments = @([regex]::Split($Body, '(?<=\n)'))
        $finalSegments = @([regex]::Split($finalArtifactBody, '(?<=\n)'))
        $typedEditsOwned = $originalSegments.Count -eq $finalSegments.Count
        for ($i = 0; $typedEditsOwned -and $i -lt $originalSegments.Count; $i++) {
            if ($originalSegments[$i] -ceq $finalSegments[$i]) { continue }
            $beforeInfo = Get-VtCardArtifactLineInfo -Line $originalSegments[$i].TrimEnd([char[]]"`r`n")
            $afterInfo = Get-VtCardArtifactLineInfo -Line $finalSegments[$i].TrimEnd([char[]]"`r`n")
            if ($beforeInfo.IsFeatureProvenance -or $afterInfo.IsFeatureProvenance) { $typedEditsOwned = $false; break }
            if (-not $beforeInfo.IsTypedCurrent -and -not $afterInfo.IsTypedCurrent) { continue }
            if (-not $beforeInfo.IsTypedCurrent -or -not $afterInfo.IsTypedCurrent -or
                [string]$beforeInfo.Heading -cne [string]$afterInfo.Heading) { $typedEditsOwned = $false; break }
            foreach ($lineInfo in @($beforeInfo,$afterInfo)) {
                $lineText = if ($lineInfo -eq $beforeInfo) { $originalSegments[$i] } else { $finalSegments[$i] }
                $lineOwners = @(Resolve-VtCardArtifactLineTargets -Line $lineText -Heading $lineInfo.Heading -Targets $fullArtifactTargets -NoImplicitSingleton)
                if ($lineOwners.Count -eq 0 -and -not $lineInfo.HasQualifier -and $lineInfo.ItemIds.Count -eq 0 -and
                    $selectedArtifactTargets.Count -eq 1) { $lineOwners = @($selectedArtifactTargets[0]) }
                if ($lineOwners.Count -ne 1 -or [string]$lineOwners[0].ModId -cne $ownerKey) { $typedEditsOwned = $false; break }
            }
        }
        if (-not $typedEditsOwned) {
            $result.Status = 'unparseable'
            $result.Reason = 'publishing-typed-or-provenance-edit-ownership-unproven'
            return $result
        }
    }
    if ($artifactReview.Status -eq 'stale') {
        $newBody = [string]$artifactReview.NewCard
        $changes += @($artifactReview.Changes)
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
        $resolvedAnchors = New-Object System.Collections.Generic.List[object]
        $seenAnchorIndexes = @{}

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
                    $markerMatch = [regex]::Match($match.Value,
                        ('(?i)\[' + $tagEsc + '(?::LOAD)?\]'))
                    $markerIndex = [int]($match.Index + $markerMatch.Index)
                    if ($seenAnchorIndexes.ContainsKey($markerIndex)) { continue }
                    $clauseRange = Get-VtBuildClauseRange -Line $line -Index $markerIndex
                    $anchorContext = Get-VtAllStreamAnchorContext -Line $line `
                        -ClauseRange $clauseRange -OldVersion $oldVersion
                    $candidates = @(Resolve-VtAllStreamAnchor -Candidates $tagStreams `
                        -Clause $anchorContext -Body $Body -OldVersion $oldVersion)
                    if ($candidates.Count -ne 1) {
                        $result.Status = 'unparseable'
                        $result.Reason = "shared load tag '$($tagStreams[0].LoadTag)' on line $($lineIndex + 1) has no unique stream attribution"
                        return $result
                    }
                    $stream = $candidates[0]
                    $newVersion = ([string]$stream.Version).TrimStart('v', 'V')
                    $seenAnchorIndexes[$markerIndex] = $true
                    $resolvedAnchors.Add([pscustomobject]@{
                        MarkerIndex = $markerIndex
                        ClauseStart = [int]$clauseRange.Start
                        ClauseEnd = [int]$clauseRange.End
                        OldVersion = $oldVersion
                        NewVersion = $newVersion
                        ModId = [string]$stream.ModId
                        Identity = [string]$stream.Identity
                        LegacyIdentities = @($stream.LegacyIdentities)
                    })
                }
            }
        }

        # Historical cards sometimes put punctuation or explanatory prose
        # between the version and LOAD marker. The lifecycle parser can still
        # bind those identities safely, so feed only otherwise-unseen markers
        # through the same exact stream resolver.
        if ($line -match '^[ \t]*\*\*Build/banner:\*\*') {
            foreach ($identity in @(Get-VtBuildBannerIdentities $line)) {
                $markerIndex = [int]$identity.MarkerIndex
                if ($seenAnchorIndexes.ContainsKey($markerIndex)) { continue }
                $markerText = [string]$identity.Marker
                $tag = $null
                if ($markerText -match '^\[(?<tag>[A-Za-z][A-Za-z0-9_-]*):LOAD\]$') {
                    $tag = $matches['tag']
                }
                elseif ($markerText -match '^\[(?<tag>[A-Za-z][A-Za-z0-9_-]*)\]$') {
                    $tag = $matches['tag']
                }
                if ([string]::IsNullOrWhiteSpace($tag)) { continue }
                $tagKey = $tag.ToLowerInvariant()
                if (-not $streamsByTag.ContainsKey($tagKey)) {
                    $result.Status = 'unparseable'
                    $result.Reason = "unknown load tag '$tag' on line $($lineIndex + 1)"
                    return $result
                }
                $recognized = $true
                $oldVersion = [string]$identity.Version
                $clauseRange = Get-VtBuildClauseRange -Line $line -Index $markerIndex
                $anchorContext = Get-VtAllStreamAnchorContext -Line $line `
                    -ClauseRange $clauseRange -OldVersion $oldVersion
                $candidates = @(Resolve-VtAllStreamAnchor -Candidates @($streamsByTag[$tagKey]) `
                    -Clause $anchorContext -Body $Body -OldVersion $oldVersion)
                if ($candidates.Count -ne 1) {
                    $result.Status = 'unparseable'
                    $result.Reason = "shared load tag '$tag' on line $($lineIndex + 1) has no unique stream attribution"
                    return $result
                }
                $stream = $candidates[0]
                $seenAnchorIndexes[$markerIndex] = $true
                $resolvedAnchors.Add([pscustomobject]@{
                    MarkerIndex = $markerIndex
                    ClauseStart = [int]$clauseRange.Start
                    ClauseEnd = [int]$clauseRange.End
                    OldVersion = $oldVersion
                    NewVersion = ([string]$stream.Version).TrimStart('v', 'V')
                    ModId = [string]$stream.ModId
                    Identity = [string]$stream.Identity
                    LegacyIdentities = @($stream.LegacyIdentities)
                })
            }
        }

        # Replace every duplicate copy inside the anchor's exact semicolon
        # clause. Historical cards sometimes put a marker-only confirmation
        # clause immediately after a display-name clause. Widen into that one
        # preceding clause only when it contains this stream's exact identity,
        # the same old version, and no competing LOAD marker. This repairs the
        # half-updated identity that reopened #1102 without sweeping unrelated
        # same-version prose elsewhere on the line.
        $editKeys = @{}
        foreach ($group in @($resolvedAnchors | Group-Object {
            '{0}|{1}|{2}' -f $_.ClauseStart, $_.ClauseEnd, $_.OldVersion.ToLowerInvariant()
        })) {
            $rows = @($group.Group)
            $newVersions = @($rows | ForEach-Object { [string]$_.NewVersion } | Sort-Object -Unique)
            if ($newVersions.Count -ne 1) {
                $result.Status = 'unparseable'
                $result.Reason = "version v$($rows[0].OldVersion) has conflicting stream ownership on line $($lineIndex + 1)"
                return $result
            }
            $oldVersion = [string]$rows[0].OldVersion
            $newVersion = [string]$newVersions[0]
            if ($oldVersion.Equals($newVersion, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $segmentStart = [int]$rows[0].ClauseStart
            $segmentEnd = [int]$rows[0].ClauseEnd
            $versionPattern = '(?<![0-9A-Za-z.-])(?<prefix>[vV]?)' +
                [regex]::Escape($oldVersion) + '(?![0-9A-Za-z-])(?!\.[0-9A-Za-z])'
            $identities = @($rows | ForEach-Object { Get-VtStreamIdentitySet $_ } |
                Sort-Object -Unique)
            if ($identities.Count -gt 0) {
                $previous = Get-VtPreviousBuildClauseRange -Line $line -ClauseStart $segmentStart
                $previousIdentityMatches = @()
                if ($previous) {
                    $previousIdentityMatches = @($identities | Where-Object {
                        Test-VtStreamIdentityPresent -Body $previous.Text -Identity ([string]$_)
                    })
                }
                if ($previous -and
                    $previousIdentityMatches.Count -gt 0 -and
                    $previous.Text -match $versionPattern -and
                    $previous.Text -notmatch '\[[A-Za-z][A-Za-z0-9_-]*:LOAD\]' -and
                    $previous.Text -notmatch ('(?i)\[[A-Za-z][A-Za-z0-9_-]*\][ \t]+v?' +
                        $script:VtSemverPattern + '[ \t]+loaded')) {
                    $segmentStart = [int]$previous.Start
                }
            }
            $segment = $line.Substring($segmentStart, $segmentEnd - $segmentStart)
            $tokenMatches = @([regex]::Matches($segment, $versionPattern))
            if ($tokenMatches.Count -eq 0) {
                $result.Status = 'unparseable'
                $result.Reason = "resolved version v$oldVersion has no bounded token on line $($lineIndex + 1)"
                return $result
            }
            foreach ($token in $tokenMatches) {
                $index = $segmentStart + [int]$token.Index
                $key = "$index`:$($token.Length)"
                $prefix = [string]$token.Groups['prefix'].Value
                $replacement = $prefix + $newVersion
                if ($editKeys.ContainsKey($key)) {
                    if ([string]$editKeys[$key] -cne $replacement) {
                        $result.Status = 'unparseable'
                        $result.Reason = "version token at line $($lineIndex + 1), column $($index + 1) has conflicting stream ownership"
                        return $result
                    }
                    continue
                }
                $edits.Add([pscustomobject]@{
                    Index = $index
                    Length = [int]$token.Length
                    Replacement = $replacement
                })
                $editKeys[$key] = $replacement
            }
            $owners = @($rows | ForEach-Object { [string]$_.ModId } | Sort-Object -Unique) -join ','
            $changes.Add("line $($lineIndex + 1): $owners v$oldVersion -> v$newVersion ($($tokenMatches.Count) token(s))")
        }

        foreach ($oldVersion in @($resolvedAnchors | ForEach-Object {
            if (-not ([string]$_.OldVersion).Equals([string]$_.NewVersion,
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                [string]$_.OldVersion
            }
        } | Sort-Object -Unique)) {
            $versionPattern = '(?<![0-9A-Za-z.-])(?<prefix>[vV]?)' +
                [regex]::Escape($oldVersion) + '(?![0-9A-Za-z-])(?!\.[0-9A-Za-z])'
            foreach ($token in @([regex]::Matches($line, $versionPattern))) {
                $key = "$([int]$token.Index)`:$($token.Length)"
                if (-not $editKeys.ContainsKey($key)) {
                    $result.Status = 'unparseable'
                    $result.Reason = "version v$oldVersion has an unattributed same-line token at column $([int]$token.Index + 1)"
                    return $result
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

    $newBody = $lines -join $lineEnding
    $artifactReview = Get-VtCardCurrentArtifactReview -Card $newBody -Targets $Streams
    if ($artifactReview.Status -eq 'unparseable') {
        $result.Status = 'unparseable'
        $result.Reason = @($artifactReview.StructuralErrors) -join ', '
        return $result
    }
    if ($artifactReview.Recognized) { $recognized = $true }
    if ($artifactReview.Status -eq 'stale') {
        $newBody = [string]$artifactReview.NewCard
        foreach ($change in @($artifactReview.Changes)) { $changes.Add([string]$change) }
    }

    if (-not $recognized) { return $result }
    if ($changes.Count -eq 0) {
        $result.Status = 'current'
        $result.NewBody = $Body
        return $result
    }
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
    param([string]$SourcePath = $PSCommandPath)
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

    $wtIssue270Shape = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Cosmetics `v0.9.218-dev`, confirm `[cosmetics:LOAD] v0.9.218-dev`; Tweaker: Weapons Dev `v0.12.317-dev`, confirm `[wt:LOAD] v0.12.317-dev`. Do not enable public Tweaker: Weapons at the same time.
**Workshop receipts:** Tweaker: Cosmetics item `3715714222`, ManifestID `7466125697896787016`; Tweaker: Weapons Dev item `3748824853`, ManifestID `4857948458985088043`
**Topology:** Solo

1. Test the Deepwood Staff and helmet containment path.

**Expected:** Works.
'@
    $plan = Get-VtCardRefreshPlan -Body $wtIssue270Shape -PublishedId '3748824853' `
        -NewVersion '0.12.320-dev' -LoadTag 'wt' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons Dev' -SiblingPublishedIds @('3712896117') `
        -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'unparseable') '#270 same-line foreign anchor cannot be reported current through its Dev item id'
    Assert ($null -eq $plan.NewBody) '#270 version conflict leaves the entire card untouched'

    $plan = Get-VtCardRefreshPlan -Body $wtIssue270Shape -PublishedId '3748824853' `
        -NewVersion '0.12.320-dev' -LoadTag 'wt' -NewManifest '999' -SharedLoadTag $true `
        -StreamIdentity 'Tweaker: Weapons Dev' -SiblingPublishedIds @('3712896117') `
        -SiblingStreamIdentities @('Tweaker: Weapons')
    Assert ($plan.Status -eq 'unparseable') '#270 same-line conflict blocks a manifest-only partial repair'
    Assert ($null -eq $plan.NewBody) '#270 manifest conflict leaves the entire card untouched'

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

    # Exact post-ship regressions that reopened #1102. Version and ManifestID
    # are already current; only the typed artifact claims are stale.
    $cwvArtifact = [pscustomobject]@{
        ModId='character_weapon_variants'; Directory='character_weapon_variants'
        PublishedId='3716869446'; WorkshopId='3716869446'; LoadTag='cwv'
        Identity='Character Weapon Variants'; Version='0.1.536-dev'
        SourceCommit='d03cbc98de87a29511fd8dcb1f7c3ec163646005'
        RootBundle='0f038849957ad1b7.mod_bundle'
        RootBundleSha256='607b7df1ceff8f5247fea266f43601b0299751c78d0ccbf7fa277cdd3d5c9d5a'
        AssetFilename='character_weapon_variants.zip'
        AssetSha256='8f768a4e8aadfa8abb98748af490d684e4c43ab2a6e24fff6f1a12d1b3745e04'
    }
    $issue932Card = @'
## CURRENT LIVE TEST

**Build/banner:** Character Weapon Variants `v0.1.536-dev`; confirm `[cwv:LOAD] v0.1.536-dev`.
**Current receipt:** Workshop item `3716869446`, ManifestID `2764743062372452902`; root `0f038849957ad1b7.mod_bundle` SHA-256 `141990831137E45663B7EE20CF11DD22AEDE84FBBADDD5A8C502D882B8DFE16B`; exact source `07899bb7fc6a2e7c0bb0c6d8156e610a8add14ef`.
**Topology:** Solo

1. Confirm the newest game log contains `[cwv:LOAD] v0.1.536-dev`.

**Expected:** The issue #932 ammunition contract passes.
'@
    $plan = Get-VtCardRefreshPlan -Body $issue932Card -PublishedId '3716869446' `
        -NewVersion '0.1.536-dev' -LoadTag 'cwv' -NewManifest '2764743062372452902' `
        -ArtifactTarget $cwvArtifact
    Assert ($plan.Status -eq 'refresh' -and @($plan.Changes).Count -eq 2) `
        '#932 current version/Manifest card still refreshes its stale source/root receipt'
    Assert ($plan.NewBody -match '607b7df1ceff8f5247fea266f43601b0299751c78d0ccbf7fa277cdd3d5c9d5a' -and
        $plan.NewBody -match 'd03cbc98de87a29511fd8dcb1f7c3ec163646005' -and
        $plan.NewBody -notmatch '141990831137E456|07899bb7') `
        '#932 typed receipt advances to the exact hosted root/source tuple'
    $issue932Second = Get-VtCardRefreshPlan -Body $plan.NewBody -PublishedId '3716869446' `
        -NewVersion '0.1.536-dev' -LoadTag 'cwv' -NewManifest '2764743062372452902' `
        -ArtifactTarget $cwvArtifact
    Assert ($issue932Second.Status -eq 'current' -and $issue932Second.NewBody -ceq $plan.NewBody) `
        '#932 artifact repair is byte-identical on its second pass'

    $issue798Card = @'
## CURRENT LIVE TEST

**Build/banner:** Character Weapon Variants v0.1.536-dev; confirm `[cwv:LOAD] v0.1.536-dev` in the newest log
**Exact live artifact:** Workshop item `3716869446`, manifest `2764743062372452902`; `character_weapon_variants.zip` SHA-256 `551de16dcb2af13b109a18a36d54e21bd18b17a7d80d1a52e81c0610a077173b`
**Exact source:** `3464ff0b09e352b4e317a2be067840e1af350dc2`
**Topology:** Solo

1. Run `/cwv_regression_test` and retain the newest console log.

**Expected:** Every Crowbill supports Weapon Special switching.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $issue798Card -Streams @($cwvArtifact)
    Assert ($plan.Status -eq 'refresh' -and @($plan.Changes).Count -eq 2) `
        '#798 all-stream pass repairs stale Exact live artifact and Exact source fields'
    Assert ($plan.NewBody -match '8f768a4e8aadfa8abb98748af490d684e4c43ab2a6e24fff6f1a12d1b3745e04' -and
        $plan.NewBody -match 'd03cbc98de87a29511fd8dcb1f7c3ec163646005' -and
        $plan.NewBody -notmatch '551de16dcb2a|3464ff0b') `
        '#798 exact-live fields advance without preserving a feature commit as current source'

    $issue774Card = @'
## CURRENT LIVE TEST

**Build/banner:** Character Weapon Variants v0.1.536-dev, confirm `[cwv:LOAD] v0.1.536-dev`; Tweaker: GUI Dev v0.2.343-dev, confirm `[gut:LOAD] v0.2.343-dev`
**Workshop:** Character Weapon Variants, item `3716869446`, manifest `2764743062372452902`
**Topology:** Solo

1. Run `/cwv_regression_test` and retain the newest log if any step fails.

**Expected:** The issue #774 interruption contract passes.

**Deployed evidence:** Source commit `6c354be49ba63793fb3488ce886a40f9b889f29c`; PR #1359; exact-master QA run `32548198950`; release ZIP SHA-256 `b206a76aec4f09fe8c6bcac4564eafedb8edf8698ee12c836d7d02d46e91d2cd`.
'@
    $issue774Review = Get-VtCardCurrentArtifactReview -Card $issue774Card -Targets @($cwvArtifact)
    Assert ($issue774Review.Status -eq 'none' -and $issue774Review.NewCard -ceq $issue774Card) `
        '#774 untyped Deployed evidence remains immutable feature history'
    $featureProvenanceCard = $issue774Card.Replace('**Deployed evidence:**', '**Feature provenance:**')
    $featureProvenanceReview = Get-VtCardCurrentArtifactReview -Card $featureProvenanceCard -Targets @($cwvArtifact)
    Assert ($featureProvenanceReview.Status -eq 'none' -and
        $featureProvenanceReview.FeatureProvenanceLines -eq 1 -and
        $featureProvenanceReview.NewCard -ceq $featureProvenanceCard) `
        'typed Feature provenance is explicitly recognized and preserved byte-for-byte'

    $partialRootCard = $issue932Card -replace
        'root `0f038849957ad1b7\.mod_bundle` SHA-256 `[0-9A-F]+`',
        'root `0f038849957ad1b7.mod_bundle`'
    $partialRootReview = Get-VtCardCurrentArtifactReview -Card $partialRootCard -Targets @($cwvArtifact)
    Assert ($partialRootReview.Status -eq 'unparseable' -and
        $partialRootReview.StructuralErrors -contains 'current-artifact-root-unparseable:character_weapon_variants@line4' -and
        -not $partialRootReview.NewCard) `
        'partial typed root tuple fails closed with no replacement candidate'

    $wrongNamesCard = $issue932Card.Replace(
        '0f038849957ad1b7.mod_bundle` SHA-256 `141990831137E45663B7EE20CF11DD22AEDE84FBBADDD5A8C502D882B8DFE16B',
        'ffffffffffffffff.mod_bundle` SHA-256 `607b7df1ceff8f5247fea266f43601b0299751c78d0ccbf7fa277cdd3d5c9d5a'
    ).Replace('exact source `07899bb7fc6a2e7c0bb0c6d8156e610a8add14ef`',
        'exact source `d03cbc98de87a29511fd8dcb1f7c3ec163646005`')
    $wrongNamesReview = Get-VtCardCurrentArtifactReview -Card $wrongNamesCard -Targets @($cwvArtifact)
    Assert ($wrongNamesReview.Status -eq 'stale' -and
        $wrongNamesReview.DriftErrors -contains 'current-artifact-root-name-drift:character_weapon_variants@line4' -and
        $wrongNamesReview.NewCard -match 'root `0f038849957ad1b7\.mod_bundle`') `
        'wrong root filename with a right digest is corrected independently'

    $wrongZipNameCard = $issue798Card.Replace('character_weapon_variants.zip` SHA-256 `551de16dcb2af13b109a18a36d54e21bd18b17a7d80d1a52e81c0610a077173b',
        'old_character_weapon_variants.zip` SHA-256 `8f768a4e8aadfa8abb98748af490d684e4c43ab2a6e24fff6f1a12d1b3745e04').Replace(
        '3464ff0b09e352b4e317a2be067840e1af350dc2','d03cbc98de87a29511fd8dcb1f7c3ec163646005')
    $wrongZipNameReview = Get-VtCardCurrentArtifactReview -Card $wrongZipNameCard -Targets @($cwvArtifact)
    Assert ($wrongZipNameReview.Status -eq 'stale' -and
        $wrongZipNameReview.DriftErrors -contains 'current-artifact-zip-name-drift:character_weapon_variants@line4' -and
        $wrongZipNameReview.NewCard -match '`character_weapon_variants\.zip` SHA-256') `
        'wrong ZIP filename with a right digest is corrected independently'

    $hashBaitCard = $issue774Card.Replace('**Deployed evidence:**', '**Notes:**') + @'

1. Do not paste `07899bb7fc6a2e7c0bb0c6d8156e610a8add14ef` into the URL.
**Expected detail:** https://example.invalid/551de16dcb2af13b109a18a36d54e21bd18b17a7d80d1a52e81c0610a077173b remains documentation bait.
'@
    $hashBaitReview = Get-VtCardCurrentArtifactReview -Card $hashBaitCard -Targets @($cwvArtifact)
    Assert ($hashBaitReview.Status -eq 'none' -and $hashBaitReview.NewCard -ceq $hashBaitCard) `
        'source/hash bait outside typed headings is never scanned or rewritten'

    $conflictingHashCard = $issue798Card.Replace(
        '551de16dcb2af13b109a18a36d54e21bd18b17a7d80d1a52e81c0610a077173b`',
        '551de16dcb2af13b109a18a36d54e21bd18b17a7d80d1a52e81c0610a077173b`; mirror `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`')
    $conflictingHashReview = Get-VtCardCurrentArtifactReview -Card $conflictingHashCard -Targets @($cwvArtifact)
    Assert ($conflictingHashReview.Status -eq 'unparseable' -and
        $conflictingHashReview.StructuralErrors -contains 'current-artifact-unrecognized-hash:character_weapon_variants@line4') `
        'an extra hash in a typed current line fails closed instead of being stranded'

    $unexplainedOnlyCard = $issue932Card.Replace(
        'root `0f038849957ad1b7.mod_bundle` SHA-256 `141990831137E45663B7EE20CF11DD22AEDE84FBBADDD5A8C502D882B8DFE16B`; exact source `07899bb7fc6a2e7c0bb0c6d8156e610a8add14ef`',
        'opaque `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`')
    $unexplainedOnlyReview = Get-VtCardCurrentArtifactReview -Card $unexplainedOnlyCard -Targets @($cwvArtifact)
    Assert ($unexplainedOnlyReview.Status -eq 'unparseable' -and
        $unexplainedOnlyReview.StructuralErrors -contains 'current-artifact-unrecognized-hash:character_weapon_variants@line4') `
        'an unexplained-only hash under a typed current heading fails closed'

    $pathZipCard = $issue798Card.Replace('character_weapon_variants.zip', 'nested/character_weapon_variants.zip')
    $pathZipReview = Get-VtCardCurrentArtifactReview -Card $pathZipCard -Targets @($cwvArtifact)
    Assert ($pathZipReview.Status -eq 'unparseable' -and
        $pathZipReview.StructuralErrors -contains 'current-artifact-zip-unparseable:character_weapon_variants@line4') `
        'a path-shaped ZIP claim fails closed instead of repairing only its basename'

    $mixedEndingCard = $issue932Card.Replace("`n**Current receipt:**", "`r`n**Current receipt:**")
    $mixedEndingExpected = $mixedEndingCard.Replace(
        '141990831137E45663B7EE20CF11DD22AEDE84FBBADDD5A8C502D882B8DFE16B',
        '607b7df1ceff8f5247fea266f43601b0299751c78d0ccbf7fa277cdd3d5c9d5a').Replace(
        '07899bb7fc6a2e7c0bb0c6d8156e610a8add14ef','d03cbc98de87a29511fd8dcb1f7c3ec163646005')
    $mixedEndingReview = Get-VtCardCurrentArtifactReview -Card $mixedEndingCard -Targets @($cwvArtifact)
    Assert ($mixedEndingReview.Status -eq 'stale' -and $mixedEndingReview.NewCard -ceq $mixedEndingExpected) `
        'artifact repair preserves every original mixed line ending byte'

    # Issue #1746 focused begin. Hermetic capture of #760's approved 2026-10-26
    # metadata/body, plus minimal policy fixtures (not live authority proofs).
    $siblingRecords = @(
        [pscustomobject]@{
            ModId='character_weapon_variants'; Dir='character_weapon_variants'; FriendlyName='Character Weapon Variants'
            WorkshopId='3716869446'; Version='0.1.552-dev'
            SourceCommit='8d9f4dc5368a937a47ecf17279c5f801351dd196'; RootBundle='0f038849957ad1b7.mod_bundle'
            RootBundleSha256='d34d655bf1fa755f7c010a39b4de660a22635f3817314b930ad1c7977fead13c'
            AssetFilename='character_weapon_variants.zip'; AssetSha256='a3e124f2ef7e76e1bbbf0743e59e3d4891ffcd311100f28326eeadf71f08003a'
            LoadRoutes=@([pscustomobject]@{Marker='[cwv:LOAD]'}); ExactBannerRoutes=@(); CommandRoutes=@(); ReceiptRoutes=@(); MenuSurfaces=@()
        },
        [pscustomobject]@{
            ModId='wt_dev'; Dir='weapon_tweaker_dev'; FriendlyName='Weapon Tweaker (Dev)'
            WorkshopId='3748824853'; Version='0.12.339-dev'
            SourceCommit='53a60eb8d92ca96cf369c0c0be97ea25863551ab'; RootBundle='d38aa5cd35c79c3d.mod_bundle'
            RootBundleSha256='44a70864504f313be7c7651651f8797315bffdd4e68f1c16602aab6db36f4dcc'
            AssetFilename='wt_dev.zip'; AssetSha256='6e24b2f0f03b0b3349ef92639f14c6305c38ee952afddcfa7c65fdb3ceeb5dc9'
            LoadRoutes=@([pscustomobject]@{Marker='[wt:LOAD]'}); ExactBannerRoutes=@(); CommandRoutes=@(); ReceiptRoutes=@(); MenuSurfaces=@()
        }
    )
    $exact760 = @'
## CURRENT LIVE TEST

**Build/banner:** Character Weapon Variants v0.1.552-dev, confirm `[cwv:LOAD] v0.1.552-dev`; Tweaker: Weapons Dev v0.12.339-dev, confirm `[wt:LOAD] v0.12.339-dev`
**Topology:** Solo

This is the solo visual/function gate. Do not enable public Tweaker: Weapons and Tweaker: Weapons Dev together; do not add a second player yet.

1. In **Tweaker: Weapons Dev**, enable the **Outrider Grenade Launcher** for Witch Hunter Captain, Bounty Hunter, and Zealot. Equip it on each career.
2. For each of those three Saltzpyre careers, inspect the weapon in the inventory character preview and owner third person. Compare with Kruber using the Outrider Grenade Launcher: Saltzpyre should use the Repeater Pistol body stance; Kruber should keep the Blunderbuss stance.
3. In first and third person, fire, reload from partial and empty ammunition, block, bash, swap away and back, and transition from the Keep into a mission. Every action must remain functional and visually complete.
4. As controls, confirm Warrior Priest and a native Trollhammer remain unchanged.
5. Run `/cwv_regression_test`, exit normally, and attach the newest full log. Include every bounded `[cwv:760]` row and state the career/view/action for any visible mismatch.

**Expected:** Witch Hunter Captain, Bounty Hunter, and Zealot use the Repeater Pistol body stance in preview and owner third person without changing the Outrider's first-person fire, reload, block, or bash behavior. Kruber, Warrior Priest, and native Trollhammer remain unchanged. `cwv_issue760_outrider_saltzpyre_repeater_stance` passes. `network_event_unavailable`, `unit_not_alive`, `dispatch_error`, a missing clip, or visibly wrong motion fails this gate. A solo pass advances the issue to a separate co-op remote-husk card.

**Current Character Weapon Variants receipt:** Workshop item `3716869446`, ManifestID `2268385815225930742`; source `8d9f4dc5368a937a47ecf17279c5f801351dd196`, root `0f038849957ad1b7.mod_bundle` SHA-256 `d34d655bf1fa755f7c010a39b4de660a22635f3817314b930ad1c7977fead13c`, ZIP SHA-256 `a3e124f2ef7e76e1bbbf0743e59e3d4891ffcd311100f28326eeadf71f08003a`.

**Feature provenance:** Earlier CWV source `b95132ab1a5ea12168359170a1f29fc7b063b39a`, root SHA-256 `54c204a8333ded51f7916264ae67d878b78a709315481a65ce1e7cafeb8920c2`, ZIP SHA-256 `34a25e52e9eabb71e018160ee5843d3eba719a74ff75f115c509835a35b1af63`; these are historical references, not the current deployment identifiers.

**Current Weapon Tweaker (Dev) receipt:** Tweaker: Weapons Dev `v0.12.339-dev`, Workshop item `3748824853`, ManifestID `4278357008422959585`; source `53a60eb8d92ca96cf369c0c0be97ea25863551ab`; root `d38aa5cd35c79c3d.mod_bundle` SHA-256 `44a70864504f313be7c7651651f8797315bffdd4e68f1c16602aab6db36f4dcc`.

**Feature provenance (historical WT artifact, not current deployment):** WT Dev source `5139b0a22f859d67797546a55e5ec672786a2610`, root `d38aa5cd35c79c3d.mod_bundle` SHA-256 `9ab53ef47abd8fa8f23c7368fee2f2a91ee0a0d84ed91d824e83c15e97334e87`, ZIP SHA-256 `b7f62aa437ca92c1ffb0eccc77825ceb73f4f92383a6de56e8b17548de7126a0`.
'@
    # LF is canonical for the capture regardless of this script's CRLF checkout.
    $exact760 = $exact760.Replace("`r`n", "`n")
    $siblingPlanArgs = @{
        PublishedId='3716869446'; NewVersion='0.1.552-dev'; LoadTag='cwv'
        StreamIdentity='Character Weapon Variants'; NewManifest='2268385815225930742'
        ArtifactTarget=$siblingRecords[0]; ArtifactTargets=$siblingRecords
    }
    $old760 = $exact760.Replace('ManifestID `2268385815225930742`', 'ManifestID `4572388077344785045`')
    $siblingPlan = Get-VtCardRefreshPlan -Body $old760 @siblingPlanArgs
    Assert ($siblingPlan.Status -eq 'refresh' -and $siblingPlan.NewBody -ceq $exact760) `
        '#1746 actual760 metadata refresh preserves the full approved body except its owned ManifestID'
    $siblingAgain = Get-VtCardRefreshPlan -Body $siblingPlan.NewBody @siblingPlanArgs
    Assert ($siblingAgain.Status -eq 'current' -and $siblingAgain.NewBody -ceq $exact760 -and $siblingAgain.Changes.Count -eq 0) `
        '#1746 current typed sibling card is byte-identical and idempotent'
    $crlf760 = $exact760.Replace("`n", "`r`n")
    $siblingCrlf = Get-VtCardRefreshPlan -Body $crlf760 @siblingPlanArgs
    Assert ($siblingCrlf.Status -eq 'current' -and $siblingCrlf.NewBody -ceq $crlf760) '#1746 CRLF current card stays byte-identical'
    $ownDrift = $exact760.Replace($siblingRecords[0].SourceCommit, ('a' * 40)).Replace(
        $siblingRecords[0].RootBundleSha256, ('b' * 64)).Replace($siblingRecords[0].AssetSha256, ('c' * 64))
    $ownRefresh = Get-VtCardRefreshPlan -Body $ownDrift @siblingPlanArgs
    Assert ($ownRefresh.Status -eq 'refresh' -and $ownRefresh.NewBody -ceq $exact760) '#1746 owner source/root/ZIP advance without changing any sibling bytes'
    $reverseArgs1746 = $siblingPlanArgs.Clone()
    $reverseArgs1746.PublishedId='3748824853'; $reverseArgs1746.NewVersion='0.12.339-dev'; $reverseArgs1746.LoadTag='wt'
    $reverseArgs1746.StreamIdentity='Tweaker: Weapons Dev'; $reverseArgs1746.NewManifest='4278357008422959585'
    $reverseArgs1746.ArtifactTarget=$siblingRecords[1]
    $reverseCard1746 = $exact760.Replace($siblingRecords[1].RootBundleSha256, ('e' * 64))
    $reversePlan1746 = Get-VtCardRefreshPlan -Body $reverseCard1746 @reverseArgs1746
    Assert ($reversePlan1746.Status -eq 'refresh' -and $reversePlan1746.NewBody -ceq $exact760) '#1746 reverse publisher advances WT-owned artifacts without touching CWV'
    $recordBefore = $siblingRecords | ConvertTo-Json -Depth 8 -Compress
    foreach ($field in @('SourceCommit','RootBundle','RootBundleSha256')) {
        $replacement = if ($field -eq 'RootBundle') { 'foreign.mod_bundle' } elseif ($field -eq 'SourceCommit') { 'f' * 40 } else { 'e' * 64 }
        $staleSibling = $exact760.Replace([string]$siblingRecords[1].$field, $replacement)
        $rejected = Get-VtCardRefreshPlan -Body $staleSibling @siblingPlanArgs
        Assert ($rejected.Status -eq 'unparseable' -and $rejected.Reason -like 'sibling-current-artifact-drift:*' -and
            $null -eq $rejected.NewBody -and $rejected.Changes.Count -eq 0) "#1746 stale sibling $field is rejected, never repaired"
    }
    $siblingZipCard = $exact760.Replace('ManifestID `4278357008422959585`;',
        ('ManifestID `4278357008422959585`; ZIP `' + $siblingRecords[1].AssetFilename + '` SHA-256 `' + $siblingRecords[1].AssetSha256 + '`;'))
    foreach ($field in @('AssetFilename','AssetSha256')) {
        $replacement = if ($field -eq 'AssetFilename') { 'foreign.zip' } else { 'd' * 64 }
        $rejected = Get-VtCardRefreshPlan -Body $siblingZipCard.Replace([string]$siblingRecords[1].$field, $replacement) @siblingPlanArgs
        Assert ($rejected.Status -eq 'unparseable' -and $rejected.Reason -like 'sibling-current-artifact-drift:*' -and
            $null -eq $rejected.NewBody) "#1746 stale sibling $field is rejected"
    }
    foreach ($context in @(
        ,@($siblingRecords[0]), ,@($siblingRecords[0],$siblingRecords[1],$siblingRecords[1]),
        ,@($siblingRecords[0],$siblingRecords[0],$siblingRecords[1]), ,@()
    )) {
        $args1746 = $siblingPlanArgs.Clone(); $args1746.ArtifactTargets = $context
        $rejected = Get-VtCardRefreshPlan -Body $exact760 @args1746
        Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) '#1746 missing/duplicate/empty sibling context fails closed'
    }
    foreach ($field in @('SourceCommit','RootBundleSha256','AssetSha256')) {
        $badRecord = $siblingRecords[1] | Select-Object *; $badRecord.$field = $null
        $args1746 = $siblingPlanArgs.Clone(); $args1746.ArtifactTargets = @($siblingRecords[0],$badRecord)
        $rejected = Get-VtCardRefreshPlan -Body $siblingZipCard @args1746
        Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) "#1746 unavailable sibling $field fails closed"
    }
    foreach ($field in @('ModId','Dir','WorkshopId','Version','SourceCommit','RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) {
        $badOwner = $siblingRecords[0] | Select-Object *; $badOwner.$field = 'mismatched'
        $args1746 = $siblingPlanArgs.Clone(); $args1746.ArtifactTarget = $badOwner
        $rejected = Get-VtCardRefreshPlan -Body $exact760 @args1746
        Assert ($rejected.Status -eq 'unparseable' -and $rejected.Reason -eq 'publishing-artifact-context-mismatch' -and
            $null -eq $rejected.NewBody) "#1746 owner/context $field mismatch fails closed"
    }
    $unknownSibling = $exact760.Replace('3748824853','9999999999')
    $rejected = Get-VtCardRefreshPlan -Body $unknownSibling @siblingPlanArgs
    Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) '#1746 unknown typed sibling Workshop item fails closed'
    $ambiguousReceipt = $exact760.Replace('**Current Weapon Tweaker (Dev) receipt:**', '**Current receipt:**').Replace('Workshop item `3748824853`, ', '')
    $rejected = Get-VtCardRefreshPlan -Body $ambiguousReceipt @siblingPlanArgs
    Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) '#1746 unattributed typed sibling is not guessed'
    $mixedReceipt = $exact760.Replace('Workshop item `3748824853`,', 'Workshop item `3748824853`, Workshop item `3716869446`,')
    $rejected = Get-VtCardRefreshPlan -Body $mixedReceipt @siblingPlanArgs
    Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) '#1746 mixed-owner typed receipt line remains ambiguous'
    $hashBait1746 = $exact760.Replace('source `53a60eb8d92ca96cf369c0c0be97ea25863551ab`;', 'source `53a60eb8d92ca96cf369c0c0be97ea25863551ab`; opaque `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`;')
    $rejected = Get-VtCardRefreshPlan -Body $hashBait1746 @siblingPlanArgs
    Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) '#1746 typed sibling hash bait remains rejected'
    Assert (($siblingRecords | ConvertTo-Json -Depth 8 -Compress) -ceq $recordBefore) '#1746 validation never mutates authority record objects'

    # A minimal command-free policy fixture exercises the actual whole-card
    # authority helper independently of #760's richer bounded diagnostic routes.
    $policy1746 = @'
## CURRENT LIVE TEST

**Build/banner:** Character Weapon Variants v0.1.552-dev, confirm `[cwv:LOAD] v0.1.552-dev`; Weapon Tweaker (Dev) v0.12.339-dev, confirm `[wt:LOAD] v0.12.339-dev`
**Topology:** Solo

1. Equip Kruber's Mace in the Keep.

**Expected:** The weapon remains visible.
'@
    $policyAuthority1746 = [pscustomobject]@{Records=$siblingRecords}
    Assert (Get-VtRefreshedCardAuthorityDecision -Body $policy1746 -Authority $policyAuthority1746).Valid '#1746 full current build authority accepts the minimal policy fixture'
    $badPolicy1746 = $policy1746.Replace('0.12.339-dev','0.12.338-dev')
    Assert (-not (Get-VtRefreshedCardAuthorityDecision -Body $badPolicy1746 -Authority $policyAuthority1746).Valid) '#1746 stale sibling build authority remains rejected'
    $missingPolicy1746 = [pscustomobject]@{Records=@($siblingRecords[0])}
    Assert (-not (Get-VtRefreshedCardAuthorityDecision -Body $policy1746 -Authority $missingPolicy1746).Valid) '#1746 missing sibling build authority remains rejected'
    $public1746 = [pscustomobject]@{
        ModId='wt'; Dir='weapon_tweaker'; FriendlyName='Weapon Tweaker'; WorkshopId='3712896117'; Version='0.12.338-beta'
        SourceCommit='6f4c78e63e3318075fa6d2cd705accffccf8e51b'; RootBundle='ebaffd734a22c9a0.mod_bundle'
        RootBundleSha256='9c300090d6ed5f17a759f4957b9c44b22b0f7d8b23689884329e4fe7ca4b0359'
        AssetFilename='wt.zip'; AssetSha256='3f5d6959d4fbf483a9009fade895c20a21c2abd83784e529863fb3dfb1c7e9f3'
        LoadRoutes=@([pscustomobject]@{Marker='[wt:LOAD]'}); ExactBannerRoutes=@(); CommandRoutes=@(); ReceiptRoutes=@(); MenuSurfaces=@()
    }
    $threeStreams1746 = @($siblingRecords) + @($public1746)
    $threeCard1746 = $policy1746.Replace('**Topology:** Solo',
        ('**Current public receipt:** Workshop item `3712896117`, ManifestID `555555`; source `' + $public1746.SourceCommit + '`; root `' + $public1746.RootBundle + '` SHA-256 `' + $public1746.RootBundleSha256 + '`.' + "`n**Topology:** Solo"))
    $threeCard1746 = $threeCard1746.Replace('confirm `[wt:LOAD] v0.12.339-dev`',
        'confirm `[wt:LOAD] v0.12.339-dev`; Weapon Tweaker v0.12.338-beta, confirm `[wt:LOAD] v0.12.338-beta`')
    $threeArgs1746=$siblingPlanArgs.Clone(); $threeArgs1746.ArtifactTargets=$threeStreams1746
    $threePlan1746=Get-VtCardRefreshPlan -Body $threeCard1746 @threeArgs1746
    Assert ($threePlan1746.Status -eq 'current' -and $threePlan1746.NewBody -ceq $threeCard1746) '#1746 shared WT LOAD public/Dev siblings stay item-specific and byte-identical'
    Assert (Get-VtRefreshedCardAuthorityDecision -Body $threeCard1746 -Authority ([pscustomobject]@{Records=$threeStreams1746})).Valid '#1746 current public/Dev sibling builds retain exact authority attribution'
    # Exact 21 artifact tuples from captured mods-2026-10-26 manifest. Only
    # participating LOAD routes are attached below; this fixture is not a new
    # source/provider proof and has no external/ignored-path dependency.
    $fullArtifacts1746 = '[{"ModId":"wt","Dir":"weapon_tweaker","FriendlyName":"Weapon Tweaker","Version":"0.12.338-beta","WorkshopId":"3712896117","SourceCommit":"6f4c78e63e3318075fa6d2cd705accffccf8e51b","RootBundle":"ebaffd734a22c9a0.mod_bundle","RootBundleSha256":"9c300090d6ed5f17a759f4957b9c44b22b0f7d8b23689884329e4fe7ca4b0359","AssetFilename":"wt.zip","AssetSha256":"3f5d6959d4fbf483a9009fade895c20a21c2abd83784e529863fb3dfb1c7e9f3"},{"ModId":"ct","Dir":"chaos_wastes_tweaker","FriendlyName":"Chaos Wastes Tweaker","Version":"0.7.132-beta","WorkshopId":"3712929235","SourceCommit":"dbf04904661b181f1745304fda7e3a0e6ae87523","RootBundle":"c37627d549d8ce88.mod_bundle","RootBundleSha256":"088edb0c485906a3e877ed7253aaacbc86e6b6a4a200010037f3f030a2f7d402","AssetFilename":"ct.zip","AssetSha256":"be0f0532f3075b48c32141f7947bfcd0b403464eec0e09f420c14c00fbbc0f44"},{"ModId":"ct_dev","Dir":"chaos_wastes_tweaker_dev","FriendlyName":"Chaos Wastes Tweaker (Dev)","Version":"0.7.353-dev","WorkshopId":"3733366926","SourceCommit":"88bada716ee4b3355af2b94f751f68fda5a72569","RootBundle":"195af59fc68656a5.mod_bundle","RootBundleSha256":"90dc563d08f3d0e0ce1e27041ccc5b62694b7a7c124f2eba509398c37e26078e","AssetFilename":"ct_dev.zip","AssetSha256":"6dabbd2df041ccd5645f1b0c871e585669570102f46c0e3cbebdbc9ccdea0cba"},{"ModId":"gt","Dir":"general_tweaker","FriendlyName":"General Tweaker","Version":"0.2.177","WorkshopId":"3713619122","SourceCommit":"af073843bd3572dec5d7ad27615d7cadf4b3d592","RootBundle":null,"RootBundleSha256":null,"AssetFilename":"gt.zip","AssetSha256":"840372b403723b46b250d13336eda5e34ee3f48fa649bfb43c5a348abd630e8e"},{"ModId":"gt_dev","Dir":"general_tweaker_dev","FriendlyName":"General Tweaker (Dev)","Version":"0.2.276-dev","WorkshopId":"3733367409","SourceCommit":"a4fdc05a36f6812bb36bbb654273a1d2c10bbde9","RootBundle":"e6ffaaca2a71199e.mod_bundle","RootBundleSha256":"63e23a872b5b51f1902a492ef627557ce10f22828a19f9c026de8808e9f1a28c","AssetFilename":"gt_dev.zip","AssetSha256":"0ad602273cba469c9d4da4a9addcd37167a01b19131a7d6abeed56c7fa23bc8c"},{"ModId":"gut","Dir":"gui_tweaker","FriendlyName":"GUI Tweaker","Version":"0.2.289","WorkshopId":"3732144878","SourceCommit":"16ce6e805224a31436d67b96b48acedf796928fc","RootBundle":"ff654aa303c38f8c.mod_bundle","RootBundleSha256":"79fab1481af7b92724c41189a0e1ba5aa266568b541855fa28f8ad7fd0573406","AssetFilename":"gut.zip","AssetSha256":"0e6c9014af552b08eac32ee57df31eb600a178d29b510fa4b709e4dffb00a7e8"},{"ModId":"gut_dev","Dir":"gui_tweaker_dev","FriendlyName":"GUI Tweaker (Dev)","Version":"0.2.364-dev","WorkshopId":"3751024698","SourceCommit":"1d2b3c58c42562a631e341e2fd61e836f4261866","RootBundle":"0e89c5285caab001.mod_bundle","RootBundleSha256":"d56b0d8396996a7d74b5104c9723f341763059d08c0fd0d9d5068056598a2a48","AssetFilename":"gut_dev.zip","AssetSha256":"4977d02e70b4d856014dc5dc584637845b043844454d913381bf435e2c4c0592"},{"ModId":"cosmetics_tweaker","Dir":"cosmetics_tweaker","FriendlyName":"Cosmetics Tweaker","Version":"0.9.227-dev","WorkshopId":"3715714222","SourceCommit":"2d61e826839b05b3f102aadebc9c6aa8cff07af4","RootBundle":"6448e4de51a26af1.mod_bundle","RootBundleSha256":"4eef472dfdbb47d906deb0e415417a2465f848a3d71339b3fac1a810f6fbeab3","AssetFilename":"cosmetics_tweaker.zip","AssetSha256":"322716cff6ca714a5c8685c26791c3675c00fd3ac556b67a78f2e56eb78d137f"},{"ModId":"dynamic_cosmetic_portraits","Dir":"dynamic_cosmetic_portraits","FriendlyName":"Dynamic Cosmetic Portraits","Version":"0.1.32-dev","WorkshopId":"3721036701","SourceCommit":"5c94c67b3d85bb07d6564baad913698a0fcfc417","RootBundle":"4b0d338589a2926c.mod_bundle","RootBundleSha256":"9fa84cd43f3b3d6d0391cf5a00d8dba412af173d89b13bc7b1dc26d86127df32","AssetFilename":"dynamic_cosmetic_portraits.zip","AssetSha256":"2a00eceb8bcb501ebbd202a5fef92452262934c832dad3f445ee9d0a6625272c"},{"ModId":"crt","Dir":"career_tweaker","FriendlyName":"Career Tweaker","Version":"0.4.34-beta","WorkshopId":"3716286199","SourceCommit":"a00a5bc914c81ce33f38ffb7ade5943195fdee69","RootBundle":"92ad046507348beb.mod_bundle","RootBundleSha256":"5232aff330afece728ad70a7736793a48a92e27b04d2ee4e4b87106aa450b823","AssetFilename":"crt.zip","AssetSha256":"5bd4ca08cde0b658fcb9609a922910bbdbb5eeb303e0df2cb7434c4b716b272c"},{"ModId":"enemy_tweaker","Dir":"enemy_tweaker","FriendlyName":"Enemy Tweaker","Version":"0.7.65-dev","WorkshopId":"3716780252","SourceCommit":"cd439285cfe7eb7b67eb7127f9b67f372c969ebe","RootBundle":"002586295f98ba25.mod_bundle","RootBundleSha256":"8f01e8ca7c4405e18a9a423bd6044841fb2451fe2c540df13104fa51ce265256","AssetFilename":"enemy_tweaker.zip","AssetSha256":"1a93178d0dc455470402546c2a5d2f0cae967cb77d6c76e5190067f1466adcc1"},{"ModId":"character_weapon_variants","Dir":"character_weapon_variants","FriendlyName":"Character Weapon Variants","Version":"0.1.552-dev","WorkshopId":"3716869446","SourceCommit":"8d9f4dc5368a937a47ecf17279c5f801351dd196","RootBundle":"0f038849957ad1b7.mod_bundle","RootBundleSha256":"d34d655bf1fa755f7c010a39b4de660a22635f3817314b930ad1c7977fead13c","AssetFilename":"character_weapon_variants.zip","AssetSha256":"a3e124f2ef7e76e1bbbf0743e59e3d4891ffcd311100f28326eeadf71f08003a"},{"ModId":"cim","Dir":"crafting_in_modded","FriendlyName":"Crafting In Modded","Version":"0.8.92","WorkshopId":"3721038774","SourceCommit":"f9539ef0f4d7b4647a8fe5bdcca9d78194d0f499","RootBundle":null,"RootBundleSha256":null,"AssetFilename":"cim.zip","AssetSha256":"f6ee6a4b547357473938b84d9660abb08ad320676906e28e37d8b16cd6c4845d"},{"ModId":"cim_dev","Dir":"crafting_in_modded_dev","FriendlyName":"Crafting In Modded (Dev)","Version":"0.8.144-dev","WorkshopId":"3733366851","SourceCommit":"fe7698d21eacba1c2389f1abf8e0e6568d8cf129","RootBundle":"05f34d542fe9a8ef.mod_bundle","RootBundleSha256":"c22b0d9b884d5fde120cbb96e43cc0091f115d70b0eaff0853ee740913a1a052","AssetFilename":"cim_dev.zip","AssetSha256":"8a34ec776ce6d97ae4b4fb12bb213bf96047ee615151a3399bccff2e7cc5db15"},{"ModId":"event_tweaker","Dir":"event_tweaker","FriendlyName":"Event Tweaker","Version":"0.4.54-dev","WorkshopId":"3721290755","SourceCommit":"5c94c67b3d85bb07d6564baad913698a0fcfc417","RootBundle":"ac2d7655ddc4f658.mod_bundle","RootBundleSha256":"db080250b414b775a9dc45f00fa84ebc0b248b78313ef46b6ec2803078a0ce4d","AssetFilename":"event_tweaker.zip","AssetSha256":"210a23d432cebd1300b280715362d8c9d8314eda3144f46f4eb03d0827191b60"},{"ModId":"verminious_dreams_lighting","Dir":"verminious_dreams_lighting","FriendlyName":"Verminious Dreams Lighting","Version":"1.0.7","WorkshopId":"3727221800","SourceCommit":null,"RootBundle":null,"RootBundleSha256":null,"AssetFilename":"verminious_dreams_lighting.zip","AssetSha256":"25c554a568b277168702454086737b1c9503fb018e725201d001b9a1f10a757b"},{"ModId":"verminious_dreams_lighting_dev","Dir":"verminious_dreams_lighting_dev","FriendlyName":"Verminious Dreams Lighting (Dev)","Version":"1.0.20-dev","WorkshopId":"3733366748","SourceCommit":"5c94c67b3d85bb07d6564baad913698a0fcfc417","RootBundle":"6b34ac1c97e5a1be.mod_bundle","RootBundleSha256":"6234553f804415397a0b9ed405915c0d25f9f417436b0607df2ae69ba339ee0d","AssetFilename":"verminious_dreams_lighting_dev.zip","AssetSha256":"7afaf496305f0fd8bc4ef4ec9fdb0286735b3654e231c18e89300ae41df97b5d"},{"ModId":"WOC","Dir":"weapons_of_chaos","FriendlyName":"Weapons of Chaos","Version":"0.1.62-dev","WorkshopId":"3753880932","SourceCommit":"a00a5bc914c81ce33f38ffb7ade5943195fdee69","RootBundle":"dcea08518941f940.mod_bundle","RootBundleSha256":"bd31472af4967c2d1a5d0b933dd8efdea9fe8bf7130a996400621659dfc18fea","AssetFilename":"WOC.zip","AssetSha256":"702d71a3112dbde87bf3d88611917f94da16a4544b3b6cffc60d16008a426fb0"},{"ModId":"mp","Dir":"modded_progression","FriendlyName":"Modded Progression","Version":"0.2.47-dev","WorkshopId":"3730422873","SourceCommit":"5b8e572f0dd8885c680b17c59bbab1e1e2d609a6","RootBundle":"c30cf98443ecafec.mod_bundle","RootBundleSha256":"d6fe249e9f6d2cca604b51723f8b5cc13ec5c8103ab2addc210e3e9e0e3d3252","AssetFilename":"mp.zip","AssetSha256":"9e5b0794c33dc8fbbcb38c63144f6ee33998d86cfb4f5bcb01a63a680d5bdab1"},{"ModId":"character_dialogue","Dir":"character_dialogue","FriendlyName":"Character Dialogue","Version":"0.1.14-dev","WorkshopId":"3765055148","SourceCommit":"28f1af7ef3c657f536a42ce8b4880dcf80a94419","RootBundle":"0e14765f298dd165.mod_bundle","RootBundleSha256":"c7ae8843649a265533a82f1b129411bbca6bc96f2141fe53df81fd0f47fdae60","AssetFilename":"character_dialogue.zip","AssetSha256":"5a6ac5dbf0574becb416044925dd1b9f84756207b318322f7a1fe2dd4e24b453"},{"ModId":"wt_dev","Dir":"weapon_tweaker_dev","FriendlyName":"Weapon Tweaker (Dev)","Version":"0.12.339-dev","WorkshopId":"3748824853","SourceCommit":"53a60eb8d92ca96cf369c0c0be97ea25863551ab","RootBundle":"d38aa5cd35c79c3d.mod_bundle","RootBundleSha256":"44a70864504f313be7c7651651f8797315bffdd4e68f1c16602aab6db36f4dcc","AssetFilename":"wt_dev.zip","AssetSha256":"6e24b2f0f03b0b3349ef92639f14c6305c38ee952afddcfa7c65fdb3ceeb5dc9"}]' | ConvertFrom-Json
    foreach ($record1746 in $fullArtifacts1746) {
        $marker1746 = if ($record1746.ModId -eq 'character_weapon_variants') { '[cwv:LOAD]' } elseif ($record1746.ModId -eq 'wt_dev') { '[wt:LOAD]' } else { $null }
        $record1746 | Add-Member -NotePropertyName LoadRoutes -NotePropertyValue @()
        if ($marker1746) { $record1746.LoadRoutes = @([pscustomobject]@{Marker=$marker1746}) }
        foreach ($empty1746 in @('ExactBannerRoutes','CommandRoutes','ReceiptRoutes','MenuSurfaces')) { $record1746 | Add-Member -NotePropertyName $empty1746 -NotePropertyValue @() }
    }
    $fullArgs1746=$siblingPlanArgs.Clone(); $fullArgs1746.ArtifactTargets=$fullArtifacts1746
    $line9321746=@(($issue932Card -split "`r?`n") | Where-Object { $_ -like '**Current receipt*' })[0]
    $noItem9321746=$issue932Card.Replace($line9321746,
        $line9321746.Replace('Workshop item `3716869446`, ManifestID `2764743062372452902`; ',''))
    $oldOwner9321746=$noItem9321746.Replace('0.1.536-dev','0.1.551-dev')
    $expectedOwner9321746=$oldOwner9321746.Replace('0.1.551-dev','0.1.552-dev').Replace(
        '07899bb7fc6a2e7c0bb0c6d8156e610a8add14ef',$siblingRecords[0].SourceCommit).Replace(
        '141990831137E45663B7EE20CF11DD22AEDE84FBBADDD5A8C502D882B8DFE16B',$siblingRecords[0].RootBundleSha256)
    $owner9321746=Get-VtCardRefreshPlan -Body $oldOwner9321746 @fullArgs1746
    Assert ($fullArtifacts1746.Count -eq 21 -and $owner9321746.Status -eq 'refresh' -and
        $owner9321746.NewBody -ceq $expectedOwner9321746) '#1746 ordinary unqualified no-ID receipt preserves old-to-new owner version refresh under full21 context'
    Assert (Get-VtRefreshedCardAuthorityDecision -Body $owner9321746.NewBody -Authority ([pscustomobject]@{Records=$fullArtifacts1746})).Valid '#1746 refreshed ordinary single-owner card retains complete final build authority'
    foreach ($heading1746 in @('Current Weapon Tweaker (Dev) receipt','Current Unknown Stream receipt')) {
        $edge1746=$oldOwner9321746+"`n`n**$heading1746"+':** v0.1.551-dev; ManifestID `4278357008422959585`.'
        $rejected=Get-VtCardRefreshPlan -Body $edge1746 @fullArgs1746
        Assert ($rejected.Status -eq 'unparseable' -and $rejected.Reason -eq 'publishing-typed-or-provenance-edit-ownership-unproven' -and
            $null -eq $rejected.NewBody) "#1746 qualified heading-only Manifest cannot inherit final singleton owner: $heading1746"
    }
    $ownHeading1746=$oldOwner9321746+"`n`n"+'**Current Character Weapon Variants receipt:** v0.1.551-dev; ManifestID `2268385815225930742`.'
    $ownHeadingPlan1746=Get-VtCardRefreshPlan -Body $ownHeading1746 @fullArgs1746
    Assert ($ownHeadingPlan1746.Status -eq 'refresh' -and $ownHeadingPlan1746.NewBody -match 'receipt:\*\* v0\.1\.552-dev; ManifestID') '#1746 qualified owner Manifest-only line retains proven owned version update'
    $collision1746=$exact760.Replace('Character Weapon Variants v0.1.552-dev, confirm `[cwv:LOAD] v0.1.552-dev`',
        'Character Weapon Variants v0.1.551-dev, confirm `[cwv:LOAD] v0.1.551-dev`').Replace(
        'receipt:** Tweaker: Weapons Dev `v0.12.339-dev`,','receipt:** Tweaker: Weapons Dev `v0.1.551-dev`,')
    $rejected=Get-VtCardRefreshPlan -Body $collision1746 @fullArgs1746
    Assert ($rejected.Status -eq 'unparseable' -and $rejected.Reason -eq 'publishing-typed-or-provenance-edit-ownership-unproven' -and
        $null -eq $rejected.NewBody) '#1746 original-to-final fence catches earlier version sweep on a non-owner artifact line'
    $history1746=$oldOwner9321746+"`n`n"+'**Feature provenance:** earlier v0.1.551-dev.'
    $rejected=Get-VtCardRefreshPlan -Body $history1746 @fullArgs1746
    Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) '#1746 earlier version sweep cannot rewrite recognized historical provenance'
    $unknownItem1746=$oldOwner9321746+"`n`n"+'**Current receipt:** item `9999999999`, v0.1.551-dev; ManifestID `9876543210`.'
    $rejected=Get-VtCardRefreshPlan -Body $unknownItem1746 @fullArgs1746
    Assert ($rejected.Status -eq 'unparseable' -and $null -eq $rejected.NewBody) '#1746 explicit unknown item cannot use the unqualified selected-owner fallback'
    $normalized1746=@($fullArtifacts1746 | ForEach-Object { ConvertTo-VtCardArtifactTarget $_ })
    $sole1746=@($normalized1746 | Where-Object { $_.ModId -eq 'character_weapon_variants' })
    $foreignLine1746='**Current Weapon Tweaker (Dev) receipt:** ManifestID `4278357008422959585`.'
    $legacyResolved1746=@(Resolve-VtCardArtifactLineTargets -Line $foreignLine1746 -Heading 'Current Weapon Tweaker (Dev) receipt' -Targets $sole1746)
    $strictResolved1746=@(Resolve-VtCardArtifactLineTargets -Line $foreignLine1746 -Heading 'Current Weapon Tweaker (Dev) receipt' -Targets $sole1746 -NoImplicitSingleton)
    Assert ($legacyResolved1746.Count -eq 1 -and $legacyResolved1746[0].ModId -eq 'character_weapon_variants' -and
        $strictResolved1746.Count -eq 0) '#1746 default singleton resolver behavior is unchanged; strict ownership opts out explicitly'
    $manifestInfo1746=Get-VtCardArtifactLineInfo -Line $foreignLine1746
    Assert ($manifestInfo1746.IsTypedCurrent -and $manifestInfo1746.HasQualifier -and $manifestInfo1746.Qualifier -ceq 'weapontweakerdev' -and
        $manifestInfo1746.ItemIds.Count -eq 0) '#1746 shared classifier recognizes qualified Manifest-only fields without inventing claims'
    $boundInfo1746=Get-VtCardArtifactLineInfo -Line ('**Current '+('x'*81)+' receipt:** value')
    Assert ($boundInfo1746.Parsed -and -not $boundInfo1746.IsTypedCurrent -and $boundInfo1746.HasQualifier) '#1746 reviewer current-heading bound and resolver qualifier bound remain distinct'
    Assert (-not (Get-VtCardArtifactLineInfo -Line ('**'+('x'*101)+':** value')).Parsed) '#1746 shared generic field limit remains exactly100 characters'
    # No sibling Steam Manifest authority is invented: a changed sibling token
    # is preserved, not refreshed or claimed independently current.
    $otherManifest1746 = $exact760.Replace('4278357008422959585','1234567890')
    $preserved1746 = Get-VtCardRefreshPlan -Body $otherManifest1746 @siblingPlanArgs
    Assert ($preserved1746.Status -eq 'current' -and $preserved1746.NewBody -ceq $otherManifest1746) '#1746 sibling ManifestID is immutable, not independently authenticated'
    # Issue #1746 installed setup begin. Parse our own complete source so the
    # real caller handoff and verdict branches stay under durable CI coverage.
    $wiredSource1746 = [IO.File]::ReadAllText($SourcePath)
    $wiredTokens1746=$null; $wiredErrors1746=$null
    $wiredAst1746=[Management.Automation.Language.Parser]::ParseInput($wiredSource1746,[ref]$wiredTokens1746,[ref]$wiredErrors1746)
    if ($wiredErrors1746.Count) { throw ($wiredErrors1746 | Out-String) }
    $wiredLoop1746=@($wiredAst1746.FindAll({param($n)
        $n -is [Management.Automation.Language.ForEachStatementAst] -and
        $n.Variable.Extent.Text -ceq '$issueNumber' -and $n.Condition.Extent.Text -ceq '$readyIssues'
    },$true))
    if ($wiredLoop1746.Count -ne 1) { throw 'Installed per-issue loop is ambiguous' }
    $loopText1746=$wiredLoop1746[0].Extent.Text
    $lineDiff1746=@($wiredAst1746.FindAll({param($n)
        $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Write-VtCardLineDiff'
    },$true))
    if ($lineDiff1746.Count -ne 1) { throw 'Installed line-diff owner is ambiguous' }
    Invoke-Expression $lineDiff1746[0].Extent.Text
    function Invoke-Installed1746 {
        param([string]$LoopText,[string]$Body,$SourceRecords,$CardAuthority)
        $installedIssue1746=[pscustomobject]@{State='OPEN';Comments=@([pscustomobject]@{
            id='IC_TEST_1746';databaseId=5749497549;body=$Body;isPinned=$true;createdAt='2026-10-26T22:45:26Z'
        })}
        $before1746=$installedIssue1746 | ConvertTo-Json -Depth 8 -Compress
        $writes1746=New-Object 'System.Collections.Generic.List[object]'
        function Get-VtIssueStateAndComments { param($Owner,$Name,$Number) return $installedIssue1746 }
        function Update-VtIssueComment { param($CommentNodeId,$NewBody) $writes1746.Add([pscustomobject]@{Id=$CommentNodeId;Body=$NewBody}) }
        $readyIssues=@(760);$repoOwner='offline';$repoName='fixture';$ReconcileAllStreams=$false;$DryRun=$false
        $PublishedId='3716869446';$NewVersion='0.1.552-dev';$LoadTag='cwv';$NewManifest='2268385815225930742'
        $StreamIdentity='Character Weapon Variants';$sharedLoadTag=$false;$siblingPublishedIds=@();$siblingStreamIdentities=@()
        $sourceAuthority=[pscustomobject]@{Records=$SourceRecords};$currentArtifactTarget=$siblingRecords[0]
        $liveTestAuthority=$CardAuthority;$displayVersion='v0.1.552-dev'
        $summary=@{refreshed=0;current=0;'skipped-unparseable'=0;'skipped-closed'=0;failed=0}
        $cardsSeen=0;$issuesExamined=0;$exitCode=0
        $null=Invoke-Expression $LoopText
        if (($installedIssue1746 | ConvertTo-Json -Depth 8 -Compress) -cne $before1746) { throw 'Installed route mutated issue or pin fixture object' }
        return [pscustomobject]@{Summary=$summary;Writes=@($writes1746.ToArray());Exit=$exitCode;InputExact=$true}
    }
    # Issue #1746 installed assertions begin.
    $receiptLines1746=@(($exact760 -split "`n") | Where-Object {$_ -match '^\*\*Current '})
    $policyWithArtifacts1746=$policy1746+"`n`n"+($receiptLines1746 -join "`n`n")
    $oldPolicy1746=$policyWithArtifacts1746.Replace('ManifestID `2268385815225930742`','ManifestID `4572388077344785045`')
    $installedGood1746=Invoke-Installed1746 $loopText1746 $oldPolicy1746 $siblingRecords $policyAuthority1746
    Assert ($installedGood1746.Summary.refreshed -eq 1 -and $installedGood1746.Writes.Count -eq 1 -and
        $installedGood1746.Writes[0].Id -ceq 'IC_TEST_1746' -and $installedGood1746.Writes[0].Body -ceq $policyWithArtifacts1746) `
        '#1746 installed loop forwards complete context and changes only same comment owned metadata'
    $installedCurrent1746=Invoke-Installed1746 $loopText1746 $policyWithArtifacts1746 $siblingRecords $policyAuthority1746
    Assert ($installedCurrent1746.Summary.current -eq 1 -and $installedCurrent1746.Writes.Count -eq 0) '#1746 installed current valid card is a zero-write result'
    $staleBuild1746=$policyWithArtifacts1746.Replace('0.12.339-dev','0.12.338-dev')
    $installedBadCurrent1746=Invoke-Installed1746 $loopText1746 $staleBuild1746 $siblingRecords $policyAuthority1746
    Assert ($installedBadCurrent1746.Summary.'skipped-unparseable' -eq 1 -and $installedBadCurrent1746.Summary.current -eq 0 -and
        $installedBadCurrent1746.Writes.Count -eq 0) '#1746 installed current path rejects stale sibling build authority rather than reporting current'
    $installedBadRefresh1746=Invoke-Installed1746 $loopText1746 $staleBuild1746.Replace('ManifestID `2268385815225930742`','ManifestID `4572388077344785045`') $siblingRecords $policyAuthority1746
    Assert ($installedBadRefresh1746.Summary.'skipped-unparseable' -eq 1 -and $installedBadRefresh1746.Writes.Count -eq 0) '#1746 installed refresh path rejects stale sibling build authority before write'
    $originalReview1746=${function:Get-VtCardCurrentArtifactReview}
    try {
        function Get-VtCardCurrentArtifactReview { param($Card,$Targets)
            $r=& $originalReview1746 -Card $Card -Targets $Targets
            if ($r.Status -ne 'unparseable') { $r.Status='stale';$r.NewCard=$r.NewCard.Replace('4278357008422959585','1111111111') }
            return $r
        }
        $unownedEdit1746=Get-VtCardRefreshPlan -Body $exact760 @siblingPlanArgs
        Assert ($unownedEdit1746.Status -eq 'unparseable' -and $unownedEdit1746.Reason -eq 'publishing-artifact-edit-ownership-unproven' -and
            $null -eq $unownedEdit1746.NewBody) '#1746 claim ledger rejects reviewer alteration of non-owner Manifest bytes'
    }
    finally { Set-Item Function:Get-VtCardCurrentArtifactReview -Value $originalReview1746 }
    Assert (${function:Get-VtCardCurrentArtifactReview}.ToString() -ceq $originalReview1746.ToString()) '#1746 reviewer ScriptBlock restored exactly after adversarial output'
    # Issue #1746 focused end.

    $allStreams = @(
        [pscustomobject]@{ ModId='character_weapon_variants'; Directory='character_weapon_variants'; PublishedId='3716869446'; LoadTag='cwv'; Identity='Character Weapon Variants'; LegacyIdentities=@('Career Weapon Variants','Career Weapon Variants Dev'); Version='0.1.521-dev'; SourceCommit=$cwvArtifact.SourceCommit; RootBundle=$cwvArtifact.RootBundle; RootBundleSha256=$cwvArtifact.RootBundleSha256; AssetFilename=$cwvArtifact.AssetFilename; AssetSha256=$cwvArtifact.AssetSha256 },
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

    $legacyCwvSplitCard = @'
## CURRENT LIVE TEST

**Build/banner:** Career Weapon Variants Dev `v0.1.518-dev`; confirm `[cwv:LOAD] v0.1.518-dev`; Workshop item `3716869446`, ManifestID `111`
**Topology:** Solo

1. Preserve this exact step.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $legacyCwvSplitCard -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and
        ([regex]::Matches($plan.NewBody, 'v0\.1\.521-dev')).Count -eq 2 -and
        $plan.NewBody -notmatch '0\.1\.518-dev') `
        'source-qualified CWV legacy Dev identity repairs display and LOAD tokens atomically'

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

**Build/banner:** confirm `[wt:LOAD] v0.12.111-preview`
**Topology:** Solo

1. Test the feature.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $ambiguousAllStreamCard -Streams $allStreams
    Assert ($plan.Status -eq 'unparseable' -and $plan.Reason -match 'no unique stream attribution') `
        'all-stream reconciliation fails closed on an unattributed shared LOAD tag and unknown release track'

    $trackOnlyCard = $ambiguousAllStreamCard -replace '0\.12\.111-preview', '0.12.111-dev'
    $plan = Get-VtAllStreamReconcilePlan -Body $trackOnlyCard -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and $plan.NewBody -match '\[wt:LOAD\] v0\.12\.268-dev' -and
        $plan.NewBody -notmatch '0\.13\.2-beta') `
        'stale dev suffix resolves a shared LOAD tag without crossing into public beta'

    $conflictingTrackIdentity = $trackOnlyCard -replace
        'confirm `\[wt:LOAD\]', 'Tweaker: Weapons public `[wt:LOAD]'
    $plan = Get-VtAllStreamReconcilePlan -Body $conflictingTrackIdentity -Streams $allStreams
    Assert ($plan.Status -eq 'unparseable' -and $plan.Reason -match 'no unique stream attribution') `
        'a public display identity cannot be overruled by a contradictory Dev version track'

    $devWithPublicWarning = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons Dev v0.12.267-dev; confirm `[wt:LOAD] v0.12.267-dev` and do not enable public Tweaker: Weapons simultaneously
**Topology:** Solo

1. Preserve this exact step.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $devWithPublicWarning -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and
        ([regex]::Matches($plan.NewBody, 'v0\.12\.268-dev')).Count -eq 2 -and
        $plan.NewBody -notmatch '0\.13\.2-beta') `
        'adjacent exact Dev display and Dev track outrank a same-line unversioned public warning'

    $duplicateBuildVersions = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Cosmetics `v0.9.211-dev`, confirm `[cosmetics:LOAD] v0.9.211-dev`; Tweaker: Weapons Dev `v0.12.267-dev`, confirm `[wt:LOAD] v0.12.267-dev`.
**Topology:** Solo

1. Preserve this exact step.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $duplicateBuildVersions -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and
        ([regex]::Matches($plan.NewBody, 'v0\.9\.215-dev')).Count -eq 2 -and
        ([regex]::Matches($plan.NewBody, 'v0\.12\.268-dev')).Count -eq 2) `
        'duplicate display and LOAD-adjacent versions advance in one clause-bounded plan'
    Assert ($plan.NewBody -notmatch '0\.9\.211-dev|0\.12\.267-dev' -and
        $plan.NewBody -match '1\. Preserve this exact step\.') `
        'duplicate-version repair removes stale build tokens and preserves test steps'

    $semicolonSplitVersion = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons Dev `v0.12.267-dev`; confirm `[wt:LOAD] v0.12.267-dev`
**Topology:** Solo

1. Preserve this exact step.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $semicolonSplitVersion -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and
        ([regex]::Matches($plan.NewBody, 'v0\.12\.268-dev')).Count -eq 2 -and
        $plan.NewBody -notmatch '0\.12\.267-dev') `
        'semicolon-split display and LOAD versions advance atomically on one versioned line'

    $foreignSameVersion = $semicolonSplitVersion -replace
        '\*\*Build/banner:\*\*',
        '**Build/banner:** Unrelated Tool `v0.12.267-dev`;'
    $plan = Get-VtAllStreamReconcilePlan -Body $foreignSameVersion -Streams $allStreams
    Assert ($plan.Status -eq 'unparseable' -and
        $plan.Reason -match 'unattributed same-line token') `
        'same-version prose outside the exact stream segment fails closed instead of being swept'

    $foreignPipeVersion = $semicolonSplitVersion -replace
        '`\[wt:LOAD\] v0\.12\.267-dev`',
        '`[wt:LOAD] v0.12.267-dev` | unrelated prose v0.12.267-dev'
    $plan = Get-VtAllStreamReconcilePlan -Body $foreignPipeVersion -Streams $allStreams
    Assert ($plan.Status -eq 'unparseable' -and
        $plan.Reason -match 'unattributed same-line token') `
        'pipe-separated foreign prose is a separate clause and fails closed instead of being swept'

    $foreignExactBanner = $semicolonSplitVersion -replace
        '`v0\.12\.267-dev`;',
        '`v0.12.267-dev` with `[foreign] v0.12.267-dev loaded`;'
    $plan = Get-VtAllStreamReconcilePlan -Body $foreignExactBanner -Streams $allStreams
    Assert ($plan.Status -eq 'unparseable' -and
        $plan.Reason -match 'unattributed same-line token') `
        'a preceding clause with a foreign exact banner is never widened or rewritten'

    $punctuatedBuildVersion = @'
## CURRENT LIVE TEST

**Build/banner:** v0.12.267-dev, confirm `[wt:LOAD]`; Tweaker: Weapons Dev Workshop item `3748824853`, manifest `111`
**Topology:** Solo

1. Preserve this exact step.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $punctuatedBuildVersion -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and $plan.NewBody -match
        'v0\.12\.268-dev, confirm `\[wt:LOAD\]`') `
        'punctuated version-before-marker identity advances through the lifecycle parser binding'

    $dualWtStreams = @'
## CURRENT LIVE TEST

**Build/banner:** Tweaker: Weapons public `v0.13.1-beta`, confirm `[wt:LOAD] v0.13.1-beta`; Tweaker: Weapons Dev `v0.12.267-dev`, confirm `[wt:LOAD] v0.12.267-dev`
**Topology:** Solo

1. Test each stream in a separate launch.

**Expected:** Works.
'@
    $plan = Get-VtAllStreamReconcilePlan -Body $dualWtStreams -Streams $allStreams
    Assert ($plan.Status -eq 'refresh' -and
        ([regex]::Matches($plan.NewBody, 'v0\.13\.2-beta')).Count -eq 2 -and
        ([regex]::Matches($plan.NewBody, 'v0\.12\.268-dev')).Count -eq 2) `
        'one card can advance public and dev siblings independently by clause and release track'

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
$currentArtifactTarget = $null
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
                LegacyIdentities = @($inventoryStream.LegacyIdentities)
                Version = ([string]$authorityRow.Version).TrimStart('v', 'V')
                SourceCommit = [string]$authorityRow.SourceCommit
                RootBundle = [string]$authorityRow.RootBundle
                RootBundleSha256 = [string]$authorityRow.RootBundleSha256
                AssetFilename = [string]$authorityRow.AssetFilename
                AssetSha256 = [string]$authorityRow.AssetSha256
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
    $currentAuthorityRows = @($sourceAuthority.Records | Where-Object {
        [string]$_.Dir -ceq [string]$ModDirectory -and
        [string]$_.WorkshopId -ceq [string]$PublishedId
    })
    if ($currentAuthorityRows.Count -ne 1) {
        Write-Host "refresh-cards: exact stream '$ModDirectory' did not resolve to one deployed artifact authority record." -ForegroundColor Red
        exit 2
    }
    $currentArtifactTarget = $currentAuthorityRows[0]
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
                    -SiblingPublishedIds $siblingPublishedIds -SiblingStreamIdentities $siblingStreamIdentities `
                    -ArtifactTarget $currentArtifactTarget -ArtifactTargets @($sourceAuthority.Records)
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
                    $authorityDecision = Get-VtRefreshedCardAuthorityDecision -Body ([string]$card.body) -Authority $liveTestAuthority
                    if (-not $authorityDecision.Valid) {
                        Write-Host ("  ! {0}: skipped-unparseable -- current card fails deployed-source authority: {1}" -f `
                            $cardRef, (@($authorityDecision.Errors) -join ', ')) -ForegroundColor Yellow
                        $summary['skipped-unparseable']++
                        $exitCode = 1
                        continue
                    }
                    if ($ReconcileAllStreams) {
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
