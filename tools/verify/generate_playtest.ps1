<#
.SYNOPSIS
    Generate a per-session PLAYTEST script from the open GitHub issues that are waiting
    on a human in-game verify. Kills the "~100 issues stuck behind one tester" bottleneck
    by pulling every issue's shipped TEST METHOD into ONE ordered walk instead of forcing
    the tester to open each issue and wander the game per-issue.

.DESCRIPTION
    Improvement #3a from the 2026-07 standards review.

    Reads open issues labeled `verify-fix` or `diagnostics-armed`. Every row must
    pass the shared strict policy: the newest comment headed exactly
    `## CURRENT LIVE TEST` carries a build/version banner, explicit topology,
    numbered player-facing steps, and an expected result. Invalid candidates
    abort generation before any output is written.

    Each check is classified by LOCATION with keyword heuristics over the method text so
    the walk is ordered for ONE efficient session: solo keep checks, then a solo adventure
    run, then a solo Chaos Wastes run, then scoreboard/round-end, then boot/log/shutdown
    checks, then a separate CO-OP section split 2-player vs 3-player with a single-lobby
    walk order.

    Emits (overwrite each run - regenerate, do NOT hand-edit):
      docs/PLAYTEST_SCRIPT.md   full solo+coop walk for the author/primary tester
      docs/PLAYTEST_COOP.md     compact coop-only variant in plain language for a second
                                tester (RainReligion) with no repo context

    Classification is best-effort keyword matching; when it misroutes a check, fix the
    method comment or the keyword lists here and regenerate - never hand-edit the docs.

.EXAMPLE
    pwsh tools/verify/generate_playtest.ps1              # pull live issues, write all docs
    pwsh tools/verify/generate_playtest.ps1 -SelfTest    # offline unit test of the heuristics
    pwsh tools/verify/generate_playtest.ps1 -OutDir C:\tmp\pt  # write elsewhere

.NOTES
    Requires the `gh` CLI authenticated for github.com as Ensrick. Read-only against
    GitHub; writes only the three docs. Does not commit.
#>
[CmdletBinding()]
param(
    # Where to write the three docs. Default: <repo>/docs.
    [string]$OutDir,
    # Max issues fetched per label.
    [int]$Limit = 400,
    # Run the offline heuristic self-test and exit (no network, no file writes).
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot 'lifecycle_method_policy.ps1')

# ---------------------------------------------------------------------------
# Heuristics (tune these, then regenerate - never hand-edit the output docs)
# ---------------------------------------------------------------------------

# One-line "what to do" from the method body; falls back to the issue title.
function Get-VtCheckLine {
    param([string]$Method, [string]$Title, [string]$CorrectionVersion)
    if ([string]::IsNullOrWhiteSpace($Method)) { return $Title }
    $m = $Method -replace '\*\*', '' -replace '`', ''
    $picked = $null
    $stepSource = $m
    $requiredCasesHeading = [regex]::Match($m, '(?im)^\s*Required cases\s*$')
    if ($requiredCasesHeading.Success) {
        $stepSource = $m.Substring($requiredCasesHeading.Index + $requiredCasesHeading.Length)
    }
    $steps = [regex]::Matches($stepSource, '(?ms)^\s*\d+\.\s*(.+?)(?=(\r?\n\s*\d+\.)|\z)')
    if ($steps.Count -gt 0) {
        foreach ($s in $steps) {
            $t = ($s.Groups[1].Value -replace '\s+', ' ').Trim()
            # skip the "load the newest log / confirm [xx:LOAD]" boilerplate step
            if ($t -match '(?i)(newest|latest|newly generated).*log|\[[a-z][a-z0-9_]*:LOAD\]|confirm.*version|load the .*log') { continue }
            if ($t.Length -lt 8) { continue }
            $picked = $t; break
        }
        if (-not $picked) { $picked = (($steps[0].Groups[1].Value) -replace '\s+', ' ').Trim() }
    }
    else {
        $line = ($m -replace '\r?\n', ' ')
        if     ($line -match '(?i)\bTEST\b\s*(\([^)]*\))?\s*:?\s*(.+)$') { $picked = $Matches[2] }
        elseif ($line -match '(?i)\b(?:solo|co-?op|two-player)?\s*verification\s*(?:\([^)]*\))?\s*:\s*(.+)$') { $picked = $Matches[1] }
        elseif ($line -match '(?i)to\s+verify[,:]?\s*(.+)$')            { $picked = $Matches[1] }
        else                                                            { $picked = $line }
        $picked = ($picked -replace '\s+', ' ').Trim()
    }
    if ($picked) {
        # drop a leading "Test method (version):" / "method (...):" preamble
        $picked = $picked -replace '(?i)^\s*(?:(?:corrected|authoritative|replacement)\s+)?(?:test\s+)?method\s*(\([^)]*\))?\s*:?\s*', ''
        # keep only the ACTION; the "Expected:" / "Pass =" tail lives in the evidence column
        $picked = $picked -replace '(?is)\s*(expected\s*:|pass\s*(?:=|:)).*$', ''
        $picked = ($picked -replace '\s+', ' ').Trim()
    }
    if ([string]::IsNullOrWhiteSpace($picked) -or $picked.Length -lt 6) { $picked = $Title }
    if ($CorrectionVersion) {
        $picked = $picked -replace '(?i)\bv?\d+\.\d+\.\d+(?:-[a-z0-9.-]+)?\b', ('v' + $CorrectionVersion)
    }
    if ($picked.Length -gt 170) { $picked = $picked.Substring(0, 167).TrimEnd() + '...' }
    return $picked
}

# Expected evidence: log markers named in the method + a pass/expected phrase.
function Get-VtEvidence {
    param([string]$Method, [string]$Correction, [string]$CorrectionVersion)
    if ([string]::IsNullOrWhiteSpace($Method)) { return 'no crash; behavior matches the shipped fix' }
    $parts = @()
    if ($CorrectionVersion) { $parts += ('current floor v' + $CorrectionVersion) }
    $baseMarkerPattern = '\[[A-Za-z][A-Za-z0-9_]*:[A-Za-z0-9_.\-]+\]'
    $correctionMarkerPattern = '\[[A-Za-z][A-Za-z0-9_]*(?::[A-Za-z0-9_.\-]+)?\]'
    $baseMarkers = @([regex]::Matches($Method, $baseMarkerPattern) | ForEach-Object { $_.Value } | Select-Object -Unique)
    $correctionMarkers = @([regex]::Matches([string]$Correction, $correctionMarkerPattern) | ForEach-Object {
        $prefixStart = [math]::Max(0, $_.Index - 12)
        $prefix = ([string]$Correction).Substring($prefixStart, $_.Index - $prefixStart)
        if ($prefix -notmatch '(?i)\bnot\s*`?\s*$') { $_.Value }
    } | Select-Object -Unique)
    if ($correctionMarkers.Count -gt 0) {
        # A banner correction supersedes stale LOAD markers, but retain issue-specific
        # diagnostic markers from the runnable method.
        $baseMarkers = @($baseMarkers | Where-Object { $_ -notmatch '(?i):LOAD\]$' })
    }
    $markers = @(($correctionMarkers + $baseMarkers) | Select-Object -Unique)
    if ($markers) { $parts += ('log ' + ($markers -join ' ')) }
    $cardExpected = Get-VtCardField -Card $Method -Name 'Expected'
    if ($cardExpected) {
        $p = ($cardExpected -replace '\*\*', '').Trim()
        if ($p.Length -gt 110) { $p = $p.Substring(0, 107).TrimEnd() + '...' }
        $parts += ('expected: ' + $p)
    }
    elseif ($Method -match '(?i)pass\s*(?:=|:)\s*\**([^\r\n]+)') {
        $p = ($Matches[1] -replace '\*\*', '').Trim()
        if ($p.Length -gt 110) { $p = $p.Substring(0, 107).TrimEnd() + '...' }
        $parts += ('pass: ' + $p)
    }
    elseif ($Method -match '(?i)expected\s*:?\s*([^\r\n]+)') {
        $p = ($Matches[1] -replace '\*\*', '').Trim()
        if ($p.Length -gt 110) { $p = $p.Substring(0, 107).TrimEnd() + '...' }
        $parts += ('expected: ' + $p)
    }
    if ($parts.Count -eq 0) { return 'no crash; behavior matches the shipped fix' }
    return ($parts -join '; ')
}

# 2-player vs 3-player split for a co-op check.
function Get-VtCoopTier {
    param([string]$Hay)
    if ($Hay -match '(3 players|three players|3\+ players|host bot.*(two|2|three|3) client|two clients|three clients|\b3p\b|three-player|3-player)') {
        return 'COOP-3P'
    }
    return 'COOP-2P'
}

# Classify one issue into a single walk section.
function Get-VtLocation {
    param([string]$Method, [string]$Title, [string[]]$LabelNames)
    $hay = (($Title + " `n " + $Method)).ToLower()
    $isCoop = ($LabelNames -contains 'coop-required')
    if ($isCoop) { return (Get-VtCoopTier $hay) }

    # solo, first match wins (ordered so mission-requiring checks batch together)
    if ($hay -match '(boot flood|warning flood|unknown-interface|on boot|at boot|boot the game|during boot|quit to (desktop|menu)|restart the game|relaunch the game|read the (console )?log|check the (console )?log( for|,)|log[- ]only)') {
        return 'SHUTDOWN'
    }
    if ($hay -match '(scoreboard|score screen|score sync|round end|end of round|end-of-round|end screen|victory screen|defeat screen|results screen|end-mission screen)') {
        return 'SCORE-END'
    }
    if ($hay -match '(chaos wastes|chaos_wastes|citadel|\bshrine\b|\bboon\b|\bcurse\b|\bdeus\b|pilgrim|expedition|cursed|\bcw\b)') {
        return 'MISSION-CW'
    }
    if ($hay -match '(mission|adventure|\blevel\b|in-?game|in-?mission|start a (game|map|mission)|load into|\bhorde\b|\bmap\b|dlc_)') {
        return 'MISSION-ADVENTURE'
    }
    if ($hay -match '(athanor|forge|talent|tooltip|loadout|inventory|hero view|hero select|character select|illusion|portrait|cosmetic|\bhat\b|\bskin\b|options menu|settings menu|dropdown|widget|hold ?tab|crafting bench|weave|emporium|okri|contract board|keep menu|equip screen)') {
        return 'KEEP-MENU'
    }
    if ($hay -match '(wield|husk|\bbots?\b|equip|weapon draw|third[- ]person|3rd person|/give)') {
        return 'KEEP-WORLD'
    }
    return 'KEEP-MENU'
}

# Short mod tag from the issue's mod-tag label (e.g. "Tweaker: Career" -> "Career").
function Get-VtModTag {
    param([string[]]$LabelNames)
    $t = $LabelNames | Where-Object { $_ -like 'Tweaker: *' } | Select-Object -First 1
    if ($t) { return ($t -replace '^Tweaker:\s*', '') }
    if ($LabelNames -contains 'cross-mod') { return 'cross-mod' }
    return $null
}

# Priority labels are mutually exclusive by doctrine. Unknown/missing priority sorts
# after the four documented levels so a malformed issue cannot jump ahead of a crash.
function Get-VtPriorityRank {
    param([string[]]$LabelNames)
    foreach ($pair in @(
        @{ Name = '0-critical'; Rank = 0 }
        @{ Name = '1-major';    Rank = 1 }
        @{ Name = '2-moderate'; Rank = 2 }
        @{ Name = '3-low';      Rank = 3 }
    )) {
        if ($LabelNames -contains $pair.Name) { return $pair.Rank }
    }
    return 4
}

function Sort-VtRows {
    param($Items)
    return @($Items | Sort-Object `
        @{ Expression = 'PriorityRank'; Ascending = $true }, `
        @{ Expression = 'UpdatedAt'; Descending = $true }, `
        @{ Expression = 'Number'; Ascending = $true })
}

# Strip internal jargon for the plain-language second-tester doc.
function ConvertTo-PlainLanguage {
    param([string]$Text)
    if (-not $Text) { return $Text }
    $s = $Text -replace '\*\*', '' -replace '`', ''
    $s = $s -replace '(?i)\bno\s+CTD\b', 'no crash to desktop'
    $s = $s -replace '(?i)\bCTD\b', 'a crash to desktop'
    $s = $s -replace '(?i)\bcold[- ]?join(ing)?\b', 'joining a game already in progress'
    $s = $s -replace '(?i)\bno-?cwv peer\b', 'a player who does NOT have that mod'
    $s = $s -replace '(?i)\bclient husks?\b', "joining players' characters"
    $s = $s -replace '(?i)\bremote husks?\b', "other players' characters"
    $s = $s -replace '(?i)\bhusks?\b', "other players' characters"
    $s = $s -replace "(?i)\bpeer's\b", "player's"
    $s = $s -replace "(?i)\bpeers'\b", "players'"
    $s = $s -replace '(?i)\bpeer\b', 'player'
    $s = $s -replace '(?i)\bpeers\b', 'players'
    $s = $s -replace "(?i)\bclient's\b", "joining player's"
    $s = $s -replace "(?i)\bclients'\b", "joining players'"
    $s = $s -replace '(?i)\bclient\b', 'joining player'
    $s = $s -replace '(?i)\bclients\b', 'joining players'
    $s = $s -replace '(?i)\brpc\b', 'network message'
    $s = $s -replace '\[[a-z][a-z0-9_]*:LOAD\]\s*(v[\d.][\w.-]*)', 'the version line ($1) shown when the mod loads'
    $s = $s -replace '\[[a-z][a-z0-9_]*:[A-Za-z0-9_.\-]+\]', 'a marker in the game log'
    $s = $s -replace '\s+', ' '
    $s = $s -replace '(?i)\bthe the\b', 'the'
    # em dash / en dash -> comma-space (repo rule: no em dashes)
    $s = $s -replace '\s*[—–]\s*', ', '
    return $s.Trim()
}

# First up to $Max sentences, length-capped - keeps the plain-doc action short.
function Get-VtFirstSentences {
    param([string]$Text, [int]$Max = 2)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
    $parts = [regex]::Split($Text, '(?<=[.!?])\s+')
    $out = (($parts | Select-Object -First $Max) -join ' ').Trim()
    if ($out.Length -gt 200) { $out = $out.Substring(0, 197).TrimEnd() + '...' }
    return $out
}

# Plain-language PASS line for the second-tester doc. Reads the method's own
# pass/expected phrase; if it still reads technical, falls back to a generic PASS
# so the second-tester doc stays jargon-free.
function Get-VtPlainPass {
    param([string]$Method)
    $p = ''
    if     ($Method -match '(?i)pass\s*(?:=|:)\s*\**([^\r\n]+)') { $p = $Matches[1] }
    elseif ($Method -match '(?i)expected\s*:?\s*([^\r\n]+)') { $p = $Matches[1] }
    $p = ConvertTo-PlainLanguage $p
    $jargon = '(?i)(\.lua|preflight|send-?queue|reliable queue|network message|\bcache\b|unit-not|boxed|\bnil\b|\bindex\b|networklookup|\bprobe\b|marker in the game log|_[a-z]+_[a-z]|::|regression|falsifier|reso(?:lve|urce) )'
    if ([string]::IsNullOrWhiteSpace($p) -or $p.Length -gt 150 -or $p -match $jargon) {
        return 'everything behaves normally for all players and nobody crashes.'
    }
    return $p
}

# ---------------------------------------------------------------------------
# Self-test (offline)
# ---------------------------------------------------------------------------
function Invoke-SelfTest {
    $fail = 0
    function Assert($cond, $name) {
        if ($cond) { Write-Host "  PASS $name" -ForegroundColor Green }
        else { Write-Host "  FAIL $name" -ForegroundColor Red; $script:fail++ }
    }
    $script:fail = 0
    Write-Host 'generate_playtest self-test' -ForegroundColor Cyan

    # method selection: real method beats a later bookkeeping comment
    $cs = @(
        [pscustomobject]@{ body = "Fix shipped in v0.4.5-beta.`n`n**Test method (solo):**`n1. Load the newest log and confirm [crt:LOAD] v0.4.5-beta.`n2. Pick Foot Knight, open Talents, hover the reworked tooltips. Pass = tooltips render, no crash." },
        [pscustomobject]@{ body = 'Re-applying: verify-fix was set 2026-07-17 and has been stripped since.' }
    )
    $m = Get-VtMethodComment $cs
    Assert ($m -and $m -match 'Foot Knight') 'method skips bookkeeping, picks real test comment'

    $corrected = @(
        [pscustomobject]@{ body = "**TEST METHOD (solo)**`n1. Buy a starting boon.`n2. Confirm the boon price.`nPASS = old instructions." },
        [pscustomobject]@{ body = "## Corrected test method (solo)`n1. Activate a Trial Chest at zero cost.`n2. Set an absolute cost and confirm one debit.`n3. Confirm no second charge.`nPASS = the Trial Chest contract replaces the preceding method." }
    )
    $correctedMethod = Get-VtMethodComment $corrected
    Assert ($correctedMethod -match 'Trial Chest' -and $correctedMethod -notmatch 'starting boon') 'explicit corrected method outranks older formatted instructions'
    Assert ((Get-VtCheckLine -Method $correctedMethod -Title 'fallback') -notmatch 'Corrected test method') 'corrected method preamble is stripped from generated action'

    $lifecycleCorrection = @(
        [pscustomobject]@{ body = "TEST METHOD (two-player co-op)`n1. Exercise the old shipped fix.`n2. Repeat after hot join.`nPASS = old verification contract." },
        [pscustomobject]@{ body = "## Current deployed-floor correction`nThe newest issue-specific procedure above remains authoritative; this supersedes only old version references." },
        [pscustomobject]@{ body = "Lifecycle correction.`n`nDiagnostic method:`n1. Exercise the current diagnostic surface.`n2. Attach both logs.`n3. Add the missing contract row before restoring verify-fix." }
    )
    $currentDiagnostic = Get-VtMethodComment $lifecycleCorrection
    Assert ($currentDiagnostic -match 'current diagnostic surface' -and $currentDiagnostic -notmatch 'old shipped fix') 'newest explicit diagnostic method supersedes older TEST METHOD'

    $floorOnlyCorrection = @(
        [pscustomobject]@{ body = "Co-op verification:`n1. Exercise Shadow gameplay.`n2. Confirm both peers retain the gameplay.`nExpected: no crash." },
        [pscustomobject]@{ body = "## Current deployed-floor correction`nThe newest issue-specific verification procedure above remains authoritative; this comment supersedes only older build references.`nTest v0.4.38-dev and confirm [event_tweaker:LOAD]." }
    )
    $floorMethod = Get-VtMethodComment $floorOnlyCorrection
    $floorCorrection = Get-VtMethodCorrection -Comments $floorOnlyCorrection -Method $floorMethod
    Assert ($floorMethod -match 'Exercise Shadow gameplay') 'reference-only floor correction preserves runnable method above'
    Assert ($floorCorrection -match '0.4.38-dev' -and (Get-VtCorrectionVersion $floorCorrection) -eq '0.4.38-dev') 'later floor correction is retained as method context'
    Assert ((Get-VtEvidence -Method $floorMethod -Correction $floorCorrection -CorrectionVersion '0.4.38-dev') -match 'current floor v0.4.38-dev') 'floor correction updates generated evidence'

    $bannerCorrection = 'Verification banner correction: emits `[crt:LOAD]`, not `[career_tweaker:LOAD]`. For deployed v0.4.13-beta; source v0.4.14-beta is not deployed.'
    $bannerEvidence = Get-VtEvidence -Method "Co-op verification:`n1. Confirm [career_tweaker:LOAD].`n2. Exercise the fix.`nExpected: no crash." -Correction $bannerCorrection -CorrectionVersion (Get-VtCorrectionVersion $bannerCorrection)
    Assert ($bannerEvidence -match 'current floor v0.4.13-beta' -and $bannerEvidence -match '\[crt:LOAD\]' -and $bannerEvidence -notmatch '\[career_tweaker:LOAD\]') 'banner correction replaces negated stale LOAD marker and keeps deployed floor'

    $authoritative = @(
        [pscustomobject]@{ body = "TEST METHOD (solo)`n1. Exercise stale behavior.`n2. Record it.`nPASS = old." },
        [pscustomobject]@{ body = "Authoritative co-op method for the current deployed floor:`n1. Exercise the current behavior.`n2. Retain both logs." }
    )
    Assert ((Get-VtMethodComment $authoritative) -match 'current behavior') 'authoritative co-op method is an explicit replacement boundary'

    $cl = Get-VtCheckLine -Method $m -Title 'crt Foot Knight talent tooltip CTD'
    Assert ($cl -match 'Foot Knight' -and $cl -notmatch 'newest log') 'check-line skips LOAD boilerplate step'

    $ev = Get-VtEvidence -Method $m
    Assert ($ev -match '\[crt:LOAD\]' -and $ev -match 'pass:') 'evidence carries log marker + pass'
    $colonEv = Get-VtEvidence -Method "TEST METHOD (solo)`n1. Exercise the control.`n2. Repeat it.`n**PASS:** colon-form evidence is retained."
    Assert ($colonEv -match 'pass: colon-form evidence is retained') 'evidence accepts Markdown PASS-colon headings'

    Assert ((Get-VtMethodComment @([pscustomobject]@{ body = 'bumping this' })) -eq $null) 'no-method issue returns null'

    $inlineVerification = Get-VtCheckLine -Method 'Verification (solo): restart the item, launch Deepest progress, then open an upgrade chest. Expected: no crash.' -Title 'fallback'
    Assert ($inlineVerification -match '^restart the item' -and $inlineVerification -notmatch '^Verification') 'inline Verification heading is stripped from generated action'

    $requiredCases = "## Current deployed co-op verification method`n**Setup**`n1. Host with bots.`n2. Enable aid priority.`n**Required cases**`n1. Down a player near the bot and confirm aid remains pinned.`n2. Repeat for disabled states."
    Assert ((Get-VtCheckLine -Method $requiredCases -Title 'fallback') -match '^Down a player') 'required-cases action outranks setup boilerplate'

    $underscoredLoad = "Authoritative co-op method:`n1. Both peers confirm [event_tweaker:LOAD] in newly generated logs.`n2. Launch Adventure Shadow."
    Assert ((Get-VtCheckLine -Method $underscoredLoad -Title 'fallback') -match '^Launch Adventure') 'LOAD boilerplate recognizes underscored mod ids'

    # inline coop method
    $inline = 'Shipped in cwv v0.1.447. TEST (2 players, one WITHOUT cwv): wearer equips Old Musket, play to the end scoreboard; no CTD on the no-cwv peer.'
    Assert ((Get-VtMethodComment @([pscustomobject]@{ body = $inline })) -ne $null) 'inline TEST(...) recognized as method'

    # classification
    Assert ((Get-VtLocation -Method $m -Title 'crt tooltip' -LabelNames @('verify-fix')) -eq 'KEEP-MENU') 'talent tooltip -> KEEP-MENU'
    Assert ((Get-VtLocation -Method $inline -Title 'score sync' -LabelNames @('verify-fix-coop')) -eq 'COOP-2P') 'coop label -> COOP-2P'
    Assert ((Get-VtLocation -Method 'Open the menu and attach the resulting log.' -Title 'bounded probe' -LabelNames @('diagnostics-armed', 'coop-required')) -eq 'COOP-2P') 'coop-required routes armed diagnostics to co-op without relying on prose'
    Assert ((Get-VtLocation -Method 'Test (3 players + host bot): host cosmetics visible on client husks at cold join.' -Title 'host cosmetics' -LabelNames @('verify-fix-coop')) -eq 'COOP-3P') '3 players -> COOP-3P'
    Assert ((Get-VtLocation -Method 'Load a Chaos Wastes expedition, grab a boon at the shrine.' -Title 'boon' -LabelNames @('verify-fix')) -eq 'MISSION-CW') 'chaos wastes -> MISSION-CW'
    Assert ((Get-VtLocation -Method 'Start an Adventure mission on Righteous Stand, watch for the horde.' -Title 'spawn' -LabelNames @('verify-fix')) -eq 'MISSION-ADVENTURE') 'adventure -> MISSION-ADVENTURE'
    Assert ((Get-VtLocation -Method 'Boot the game and confirm no warning flood in the console log.' -Title 'boot flood' -LabelNames @('verify-fix')) -eq 'SHUTDOWN') 'boot flood -> SHUTDOWN'
    Assert ((Get-VtLocation -Method 'Finish a mission and check the scoreboard totals.' -Title 'score' -LabelNames @('verify-fix')) -eq 'SCORE-END') 'scoreboard -> SCORE-END'

    # plain language + no em dash
    $plain = ConvertTo-PlainLanguage 'Host cosmetics visible on client husks at cold-join, no CTD.'
    Assert ($plain -notmatch 'husk' -and $plain -notmatch 'CTD' -and $plain -notmatch '[—–]' -and $plain -notmatch 'no a crash') 'plain language strips husk/CTD/em-dash'

    Assert ((Get-VtModTag @('bug', 'Tweaker: General', '2-moderate')) -eq 'General') 'mod tag extracted from label'
    Assert ((Get-VtPriorityRank @('bug', '1-major')) -eq 1) 'priority rank extracted from label'
    Assert ((Get-VtPriorityRank @('bug')) -eq 4) 'missing priority sorts last'
    Assert (Test-VtRepositoryOnlyLabels @('enhancement', 'tooling', 'verify-fix')) 'tooling lifecycle routes to autonomous verification'
    Assert (-not (Test-VtRepositoryOnlyLabels @('bug', 'documentation', 'regression', 'Tweaker: Weapons', 'CWV', 'cross-mod', 'verify-fix', '0-critical', 'WOC'))) '#661-shaped documentation modifier stays runtime'
    Assert (Test-VtRepositoryOnlyLabels @('documentation', 'tooling', 'diagnostics-armed')) 'documentation plus tooling routes to autonomous verification'
    Assert (-not (Test-VtRepositoryOnlyLabels @('bug', 'verify-fix'))) 'runtime verify remains in the in-game playtest queue'

    $bodyOnlyDiagnostic = "### Diagnostic method (runnable now)`n1. Run the repository lifecycle fixture.`n`n### Expected result`nThe retired label is rejected."
    $bodySelection = Get-VtLifecycleMethodSelection -Comments @() -Body $bodyOnlyDiagnostic -AllowBodyFallback
    Assert ($bodySelection.Valid -and $bodySelection.Source -eq 'body') 'new diagnostics may use an explicit runnable issue-body method'
    $verifySelection = Get-VtLifecycleMethodSelection -Comments @() -Body $bodyOnlyDiagnostic
    Assert (-not $verifySelection.Valid) 'verify lifecycle never falls back to an issue-body method'
    $coopBodySelection = Get-VtLifecycleMethodSelection -Comments @() -Body "### Diagnostic method (runnable now)`n1. Host plus one client reproduces the transition.`nExpected: both peers log the same state." -AllowBodyFallback
    Assert ($coopBodySelection.Valid -and (Test-VtMethodRequiresCoop $coopBodySelection.Method)) 'body-only diagnostic and co-op routing use the same selected method'

    $ordered = Sort-VtRows @(
        [pscustomobject]@{ Number = 1; PriorityRank = 2; UpdatedAt = [datetime]'2026-07-19T03:00:00Z' }
        [pscustomobject]@{ Number = 2; PriorityRank = 0; UpdatedAt = [datetime]'2026-07-18T03:00:00Z' }
        [pscustomobject]@{ Number = 3; PriorityRank = 2; UpdatedAt = [datetime]'2026-07-19T04:00:00Z' }
    )
    Assert (($ordered.Number -join ',') -eq '2,3,1') 'rows sort by priority then newest update'

    $plainClient = ConvertTo-PlainLanguage "A client joins and checks the client's weapon."
    Assert ($plainClient -eq "A joining player joins and checks the joining player's weapon.") 'plain language preserves client grammar'

    if ($script:fail -eq 0) { Write-Host 'SELF-TEST PASS' -ForegroundColor Green; exit 0 }
    else { Write-Host "SELF-TEST FAIL ($script:fail)" -ForegroundColor Red; exit 1 }
}

function Invoke-StrictLiveTestSelfTest {
    $fail = 0
    function Assert-Strict($condition, [string]$name) {
        if ($condition) { Write-Host "  PASS $name" -ForegroundColor Green }
        else { Write-Host "  FAIL $name" -ForegroundColor Red; $script:strictFail++ }
    }
    $script:strictFail = 0
    $soloCard = "## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.3-dev, confirm ``[wt:LOAD]```n**Topology:** Solo`n`n1. Equip Kruber's Mace in the Keep.`n`n**Expected:** Kruber's Mace remains visible."
    $exactBannerCard = "## CURRENT LIVE TEST`n`n**Build/banner:** exact banner: [WOC] v0.1.42-dev loaded`n**Topology:** Solo`n`n1. Equip the Blightreaper in the Keep.`n`n**Expected:** The Blightreaper remains visible."
    $coopCard = "## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.3-dev, confirm ``[wt:LOAD]```n**Topology:** Co-op (host and one client)`n**Solo status:** Passed; only the remote view remains.`n`n1. Host equips Kruber's Mace.`n2. The joining player observes it.`n`n**Expected:** Both players see Kruber's Mace."
    $solo = Get-VtLiveTestCardSelection @([pscustomobject]@{ body=$soloCard })
    $exactBanner = Get-VtLiveTestCardSelection @([pscustomobject]@{ body=$exactBannerCard })
    $coop = Get-VtLiveTestCardSelection @([pscustomobject]@{ body=$coopCard })
    Assert-Strict $solo.Valid 'strict solo card accepted'
    Assert-Strict $exactBanner.Valid 'clearly labeled exact versioned banner accepted'
    Assert-Strict ($coop.Valid -and $coop.RequiresCoop) 'strict co-op card accepted after solo pass'
    Assert-Strict ((Get-VtCheckLine -Method $soloCard -Title 'fallback') -match "Kruber's Mace") 'localized numbered step becomes check line'
    Assert-Strict ((Get-VtEvidence -Method $soloCard) -match 'expected:') 'card Expected field becomes evidence'
    Assert-Strict ((Get-VtLocation -Method $soloCard -Title 'weapon' -LabelNames @('verify-fix')) -notlike 'COOP*') 'solo ready label stays solo'
    Assert-Strict ((Get-VtLocation -Method $coopCard -Title 'weapon' -LabelNames @('verify-fix','coop-required')) -eq 'COOP-2P') 'coop-required routes co-op card'
    $invalid = Get-VtLiveTestCardSelection @([pscustomobject]@{ body=$soloCard.Replace("Kruber's Mace", 'em_mace') })
    Assert-Strict (-not $invalid.Valid -and $invalid.Errors -contains 'internal-key-in-player-steps') 'internal key in player step fails closed'
    $commandCard = $soloCard.Replace("Equip Kruber's Mace in the Keep.", 'Run `/woc_pose_reset` in chat.')
    $command = Get-VtLiveTestCardSelection @([pscustomobject]@{ body=$commandCard })
    Assert-Strict $command.Valid 'backticked slash command is allowed in a player step'
    $stale = Get-VtLiveTestCardSelection @(
        [pscustomobject]@{ body=$soloCard },
        [pscustomobject]@{ body="## CURRENT LIVE TEST`n**Topology:** Solo`n1. Equip Kruber's Mace.`n**Expected:** Visible." }
    )
    Assert-Strict (-not $stale.Valid) 'newest incomplete card overrides older valid card'
    if ($script:strictFail -gt 0) { throw "generate_playtest strict self-test failed ($script:strictFail)" }
    Write-Host '[generate_playtest -SelfTest] OK'
}

if ($SelfTest) { Invoke-StrictLiveTestSelfTest; exit 0 }

# ---------------------------------------------------------------------------
# Fetch
# ---------------------------------------------------------------------------
if (-not $OutDir) { $OutDir = Join-Path $repo 'docs' }

Write-Host 'Fetching open live-test candidates from GitHub...' -ForegroundColor Cyan
$byNumber = [ordered]@{}
$raw = & gh issue list --state open --json number,title,body,labels,comments,url,updatedAt --limit $Limit 2>$null | Out-String
if ([string]::IsNullOrWhiteSpace($raw)) { throw 'No issue data returned. Is gh authenticated? (gh auth status)' }
$allOpen = @($raw | ConvertFrom-Json)
$candidateLabels = @('diagnostics-armed', 'verify-fix', 'verify-fix-coop', 'Fixed', 'coop-required')
foreach ($it in $allOpen) {
    $names = @(Get-VtLabelNames $it)
    if (@($names | Where-Object { $candidateLabels -contains $_ }).Count -gt 0) {
        $byNumber[[string]$it.number] = $it
    }
}
Write-Host "  candidates: $($byNumber.Count)"

$invalidCandidates = @()
foreach ($k in $byNumber.Keys) {
    $decision = Get-VtOpenIssueLifecycleDecision $byNumber[$k]
    if (-not $decision.Valid) {
        $invalidCandidates += "#$k ($($decision.Errors -join ', '))"
    }
}
if ($invalidCandidates.Count -gt 0) {
    throw "Live-test queue is invalid; no documents were written: $($invalidCandidates -join '; ')"
}
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

# ---------------------------------------------------------------------------
# Classify
# ---------------------------------------------------------------------------
$rows = New-Object System.Collections.Generic.List[object]
foreach ($k in $byNumber.Keys) {
    $it = $byNumber[$k]
    $labelNames = @($it.labels | ForEach-Object { $_.name })
    $selection = Get-VtLifecycleMethodSelection -Comments $it.comments -Body ([string]$it.body)
    $method = $selection.Method
    $correction = $selection.Correction
    $correctionVersion = $selection.CorrectionVersion
    $hasMethod = $selection.Valid
    $rows.Add([pscustomobject]@{
        Number   = [int]$it.number
        Title    = [string]$it.title
        Mod      = Get-VtModTag $labelNames
        Section  = Get-VtLocation -Method $method -Title $it.title -LabelNames $labelNames
        Check    = Get-VtCheckLine -Method $method -Title $it.title -CorrectionVersion $correctionVersion
        Evidence = Get-VtEvidence -Method $method -Correction $correction -CorrectionVersion $correctionVersion
        HasMethod= $hasMethod
        Method   = $method
        Diag     = ($labelNames -contains 'diagnostics-armed')
        PriorityRank = Get-VtPriorityRank $labelNames
        UpdatedAt = [datetime]$it.updatedAt
    })
}

# Section definitions in walk order: key, heading, blurb, minutes-per-check
# Time model: Over = one-time section overhead (load/coordination); Per = per-check
# observe time. Section estimate = Over + count*Per. Checks batch into the section's
# run(s), so per-check stays small and the overhead is paid once - rough by design.
$sections = @(
    @{ Key='KEEP-MENU';         Title='1. Solo - Keep menus';          Blurb='Hero view, inventory, talents, Athanor/forge, options, cosmetics/illusions. No mission load needed.'; Over=0;  Per=1.5 }
    @{ Key='KEEP-WORLD';        Title='2. Solo - Keep world';          Blurb='Wield/draw a weapon, bots, and bot-husk visuals inside the keep.'; Over=0;  Per=2 }
    @{ Key='MISSION-ADVENTURE'; Title='3. Solo - Adventure run';       Blurb='Load one Adventure mission and batch every in-mission check here.'; Over=8;  Per=1.5 }
    @{ Key='MISSION-CW';        Title='4. Solo - Chaos Wastes run';    Blurb='One Chaos Wastes expedition: shrines, boons, curses, citadel.'; Over=12; Per=1.5 }
    @{ Key='SCORE-END';         Title='5. Solo - Scoreboard / round end'; Blurb='Check at the end of the runs above.'; Over=0;  Per=1 }
    @{ Key='SHUTDOWN';          Title='6. Boot / log / shutdown';      Blurb='Read the console log on boot / quit; no gameplay needed.'; Over=0;  Per=1 }
)
$coopSections = @(
    @{ Key='COOP-2P'; Title='2 players'; Over=10; Per=2 }
    @{ Key='COOP-3P'; Title='3+ players'; Over=10; Per=2 }
)

# ---------------------------------------------------------------------------
# Emit docs/PLAYTEST_SCRIPT.md
# ---------------------------------------------------------------------------
$now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
function Fmt-Row {
    param($r)
    $modTag = if ($r.Mod) { " ($($r.Mod))" } else { '' }
    $diag = if ($r.Diag) { ' [diag]' } else { '' }
    return "- [ ] #$($r.Number)$modTag$diag - $($r.Check)`n  _Evidence:_ $($r.Evidence)"
}

$L = New-Object System.Collections.Generic.List[string]
$L.Add('# Playtest Script (verify-state issues)')
$L.Add('')
$L.Add("> GENERATED by ``tools/verify/generate_playtest.ps1`` on $now. Do NOT hand-edit - rerun the tool.")
$L.Add('> Source: valid open issues labeled `verify-fix` or `diagnostics-armed`. `coop-required` routes a card to the co-op section after its solo stage is passed/exhausted.')
$L.Add('> Ordered for one session: solo keep -> solo adventure -> solo Chaos Wastes -> scoreboard -> boot/log, then co-op.')
$L.Add('> Each box comes from the newest exact `## CURRENT LIVE TEST` comment. Generation aborts before writing if any candidate is invalid.')
$L.Add('')
$total = $rows.Count
$soloCount = @($rows | Where-Object { $_.Section -notlike 'COOP*' }).Count
$coopCount = $total - $soloCount
$L.Add("**$total checks** across ${soloCount} solo + ${coopCount} co-op.")
$L.Add('')
$L.Add('---')
$L.Add('')
$L.Add('## Solo session')
$L.Add('')

$secEstimates = @()
foreach ($sec in $sections) {
    $items = Sort-VtRows ($rows | Where-Object { $_.Section -eq $sec.Key })
    if ($items.Count -eq 0) { continue }
    $mins = [math]::Round($sec.Over + $items.Count * $sec.Per)
    $secEstimates += "$($sec.Title): $($items.Count) checks, ~$mins min"
    $L.Add("### $($sec.Title)  _($($items.Count) checks, ~$mins min)_")
    $L.Add("$($sec.Blurb)")
    $L.Add('')
    foreach ($r in $items) { $L.Add((Fmt-Row $r)) }
    $L.Add('')
}

$L.Add('---')
$L.Add('')
$L.Add('## Co-op session')
$L.Add('')
$L.Add('**Suggested single-lobby walk order** (do it once, top to bottom):')
$L.Add('1. All players subscribe/update to the versions named below and join ONE lobby in the keep. Confirm each log shows the expected `[<mod>:LOAD]` version.')
$L.Add('2. Run the keep / cold-join checks: have a client leave and re-join mid-session where a check calls for it.')
$L.Add('3. Start an Adventure mission together and clear the in-mission co-op checks.')
$L.Add('4. Play to the end scoreboard and clear the score-sync checks.')
$L.Add('5. For the 3+ player checks, pull in a third player and repeat only those rows.')
$L.Add('')
foreach ($sec in $coopSections) {
    $items = Sort-VtRows ($rows | Where-Object { $_.Section -eq $sec.Key })
    if ($items.Count -eq 0) { continue }
    $mins = [math]::Round($sec.Over + $items.Count * $sec.Per)
    $secEstimates += "Co-op $($sec.Title): $($items.Count) checks, ~$mins min"
    $L.Add("### Co-op - $($sec.Title)  _($($items.Count) checks, ~$mins min)_")
    $L.Add('')
    foreach ($r in $items) { $L.Add((Fmt-Row $r)) }
    $L.Add('')
}

$L.Add('---')
$L.Add('')
$L.Add('## Footer')
$L.Add('')
$L.Add('### Rough time estimate')
foreach ($e in $secEstimates) { $L.Add("- $e") }
$L.Add('')
$scriptPath = Join-Path $OutDir 'PLAYTEST_SCRIPT.md'
$L -join "`n" | Set-Content -Path $scriptPath -Encoding utf8

# ---------------------------------------------------------------------------
# Emit docs/PLAYTEST_COOP.md (plain language, second tester, no repo context)
# ---------------------------------------------------------------------------
$C = New-Object System.Collections.Generic.List[string]
$C.Add('# Co-op Playtest Checklist')
$C.Add('')
$C.Add("> Auto-generated on $now. Plain-language co-op-only checklist for a second tester.")
$C.Add('')
$C.Add('Thanks for helping test. Each item below is either a fix to verify or a diagnostic check that needs real co-op evidence. You do not need any of our tools or notes, just the game and this list.')
$C.Add('')
$C.Add('## Before you start')
$C.Add('- Make sure everyone in the group has updated to the newest version of each mod. Re-subscribe if you are not sure.')
$C.Add('- Turn on the in-game console log if you can, so we can read it afterward. If you cannot, just watch for anything that looks wrong on screen.')
$C.Add('- Play in ONE group/lobby the whole time so you can tick off as many items as possible in a single session.')
$C.Add('- "It works if" describes a fix PASS. "Please report" marks a diagnostic check. If you see a crash or the wrong thing, note the item number and what happened.')
$C.Add('')
$C.Add('## Suggested order')
$C.Add('1. Everyone joins one lobby in the keep and confirms the game loaded the newest mod versions.')
$C.Add('2. Do the checks that happen in the keep or when someone joins a game in progress.')
$C.Add('3. Start a normal mission together and do the in-mission checks.')
$C.Add('4. Play through to the end-of-round score screen and check those items.')
$C.Add('5. If some items need a third player, add one and redo just those.')
$C.Add('')

foreach ($sec in $coopSections) {
    $items = Sort-VtRows ($rows | Where-Object { $_.Section -eq $sec.Key })
    if ($items.Count -eq 0) { continue }
    $label = if ($sec.Key -eq 'COOP-2P') { 'Games with 2 players' } else { 'Games with 3 or more players' }
    $C.Add("## $label")
    $C.Add('')
    $n = 0
    foreach ($r in $items) {
        $n++
        $modName = if ($r.Mod) { "$($r.Mod): " } else { '' }
        $do = Get-VtFirstSentences (ConvertTo-PlainLanguage $r.Check) 2
        $pass = Get-VtPlainPass $r.Method
        if ($r.Diag -and $pass -eq 'everything behaves normally for all players and nobody crashes.') {
            $pass = "attach both players' logs and note what appeared on each player's screen."
        }
        if (-not $r.HasMethod) {
            $C.Add("$n. (Item #$($r.Number)) $modName$($r.Title). We are missing exact steps for this one, so just play normally and tell us if anything about it looks broken.")
        }
        else {
            $C.Add("$n. (Item #$($r.Number)) $modName$do")
            if ($r.Diag) { $C.Add("   - Please report: $pass") }
            else { $C.Add("   - It works if: $pass") }
        }
    }
    $C.Add('')
}
$C.Add('When you are done, tell us which item numbers passed and which did not. Thank you.')
$C.Add('')

$coopPath = Join-Path $OutDir 'PLAYTEST_COOP.md'
$C -join "`n" | Set-Content -Path $coopPath -Encoding utf8

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Generated:' -ForegroundColor Green
Write-Host "  $scriptPath"
Write-Host "  $coopPath"
Write-Host ''
Write-Host "Total issues: $total   (solo $soloCount, coop $coopCount)"
Write-Host 'Per-section counts:'
foreach ($sec in ($sections + $coopSections)) {
    $c = @($rows | Where-Object { $_.Section -eq $sec.Key }).Count
    Write-Host ("  {0,-18} {1}" -f $sec.Key, $c)
}
