# Audits every open GitHub issue against the repository's tracker doctrine.
#
# This is intentionally report-only.  It never edits labels, titles, bodies,
# or comments.  The JSON output is suitable for an _investigating/ snapshot;
# evidence-backed corrections are still made deliberately with gh.

[CmdletBinding()]
param(
    [string]$Repository = "Ensrick/vermintide-2-tweaker",
    [string]$OutputPath,
    [string]$MarkdownPath,
    # Minimum review slots per open issue. Every high-confidence relation is
    # retained even when that exceeds this weaker-match floor.
    [ValidateRange(1, 20)]
    [int]$MaxClosedMatches = 5,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/verify/lifecycle_method_policy.ps1')

$LifecycleLabels = @(
    "verify-fix",
    "verify-fix-coop",
    "diagnostics-armed"
)
$RetiredLifecycleLabels = @('not-started', 'Fixed')

$TypeLabels = @("bug", "enhancement", "feature")

$SeverityLabels = @("0-critical", "1-major", "2-moderate", "3-low")

# Broad evidence terms intentionally produce a review queue, not an automatic
# implementation claim.  Each code names a concrete lesson paid for by prior
# incidents; an issue may match several.  The full text (title/body/labels and
# comments) is considered so all open issues receive the same first-pass audit.
$LessonRules = [ordered]@{
    renderer_specific_material_closure = '(?i)UIRenderer|draw_texture|material.{0,20}not found|gui material|atlas|icon.{0,20}(missing|nil|crash)|(?:athanor|preview).{0,30}(renderer|material|texture|icon)'
    unsafe_native_call_preflight = '(?i)access violation|native (?:AV|crash|call)|Material\.set_texture|Application\.can_get|Resource not loaded|C-level|heap_allocator'
    shared_preview_presentation_descriptor = '(?i)(?:athanor|customi[sz]ation|inventory|score|lobby|hero).{0,35}preview|preview.{0,35}(?:athanor|customi[sz]ation|inventory|score|lobby|hero)|same.{0,20}(?:model|texture|offset).{0,30}(?:screen|preview)'
    custom_unit_behavioral_contract = '(?i)custom (?:unit|model|hat|helmet)|jiggle|fade.{0,20}camera|physics|skeleton|rigged?|\bLOD\b|plume|feather'
    asset_alpha_mip_material_contract = '(?i)alpha|translucen|mip|gloss|matte|too dark|too shiny|texture.{0,25}(?:missing|wrapped|bleed|black|pink)'
    appearance_surface_fanout = '(?i)remote husk|score screen|inventory.{0,25}preview|client.{0,35}(?:cosmetic|illusion|model|offset|rotation|scale|glow)|(?:cosmetic|illusion|model|offset|rotation|scale|glow).{0,35}client|local (?:third|3rd|3p)|hot.?join.{0,25}(?:model|cosmetic|illusion)'
    network_peer_parity = '(?i)host|client|peer|co-?op|network|rpc|sync|husk|hot.?join|lobby|non-mod|remote player'
    canonical_identity_persistence = '(?i)duplicate|per-instance|identity|persist|save|resume|loadout|catalog|selector|revert|profile|craft.{0,25}(?:variant|alias|duplicate)|conversion'
    bounded_transaction_lifecycle = '(?i)bulk reset|batch|full refresh|per-setting|retry|feedback loop|send queue|spam|flood|teardown|transition|on_setting_changed'
    source_first_engine_contract = '(?i)source code|vanilla source|engine contract|hook(?:ed|ing)?|animation.{0,25}(?:missing|fail|wrong)|forge object|native callback'
    custom_asset_contract = '(?i)custom (?:model|skin|texture|icon|hat|helmet|portrait|asset)|resource package|FBX|mesh|mod-bundled unit'
    dynamic_localization_ui_contract = '(?i)locali[sz]|invalid string|tooltip|description.{0,25}(?:repeat|wrong|dynamic)|title.{0,25}repeat|search bar|caret|popup text'
    backend_realm_isolation = '(?i)backend|progression|daily|quest|shilling|official realm|modded realm|EAC|PlayFab|forge.{0,25}(?:backend|realm|access)|crafting.{0,25}(?:backend|realm)'
}

$ToolingLabels = @("tooling")

# Labels in this set describe workflow, severity, or issue shape rather than a
# code-owning subsystem.  Everything else is eligible as an exact subsystem
# signal.  Exact labels are intentionally preferred over a hand-maintained
# mapping so a newly-created mod label participates without a tool update.
$NonSubsystemLabels = @(
    "bug", "enhancement", "feature", "regression", "crash", "documentation",
    "tooling", "not-started", "verify-fix", "verify-fix-coop",
    "diagnostics-armed", "coop-required", "Fixed", "duplicate", "wontfix",
    "invalid", "question", "help wanted", "good first issue", "waiting-user",
    "0-critical", "1-major", "2-moderate", "3-low", "3-minor", "4-low"
)

$TermStopWords = @(
    "about", "after", "again", "against", "also", "another", "appear", "appears",
    "because", "before", "being", "between", "both", "button", "change", "changed",
    "changes", "check", "client", "clients", "could", "current", "does", "doesn",
    "don", "during", "each", "enabled", "every", "from", "game", "have", "having",
    "into", "issue", "issues", "just", "latest", "looks", "make", "menu", "missing",
    "mod", "model", "more", "need", "needs", "normal", "only", "other", "player",
    "players", "same", "setting", "settings", "should", "still", "than", "that",
    "their", "them", "then", "there", "these", "thing", "this", "through", "toggle",
    "using", "version", "weapon", "weapons", "when", "where", "which", "while", "with",
    "work", "working", "works", "would", "wrong"
)

function Get-LabelNames($Issue) {
    return @($Issue.labels | ForEach-Object { [string]$_.name })
}

function Test-IsRepositoryOnlyIssue($Issue) {
    $labels = Get-LabelNames $Issue
    return @($labels | Where-Object { $ToolingLabels -contains $_ }).Count -gt 0
}

function Get-TitleWordCount([string]$Title) {
    if (-not $Title) { return 0 }
    $normalized = $Title -replace '^\[[^]]+\]\s*', ''
    return @($normalized -split '\s+' | Where-Object { $_ }).Count
}

function Get-IssueMethodSelection($Issue, [switch]$IncludeBody) {
    return Get-VtLifecycleMethodSelection -Comments $Issue.comments -Body ([string]$Issue.body) -AllowBodyFallback:$IncludeBody
}

function Test-HasMethodAndExpected($Issue, [switch]$IncludeBody) {
    return (Get-IssueMethodSelection $Issue -IncludeBody:$IncludeBody).Valid
}

function Test-CommentRequiresCoop($Issue) {
    $labels = Get-LabelNames $Issue
    $allowBody = $labels -contains 'diagnostics-armed'
    $selection = Get-IssueMethodSelection $Issue -IncludeBody:$allowBody
    return Test-VtMethodRequiresCoop $selection.Method
}

function Get-IssueFindings($Issue) {
    $labels = Get-LabelNames $Issue
    $lifecycle = @($labels | Where-Object { $LifecycleLabels -contains $_ })
    $retiredLifecycle = @($labels | Where-Object { $RetiredLifecycleLabels -contains $_ })
    $types = @($labels | Where-Object { $TypeLabels -contains $_ })
    $severities = @($labels | Where-Object { $SeverityLabels -contains $_ })
    $findings = New-Object System.Collections.Generic.List[string]

    if ($lifecycle.Count -ne 1) {
        $findings.Add("lifecycle_count_$($lifecycle.Count)")
    }
    if ($retiredLifecycle.Count -gt 0) {
        $findings.Add("retired_lifecycle_present")
    }
    if ($types.Count -ne 1) {
        $findings.Add("type_count_$($types.Count)")
    }
    if ($severities.Count -ne 1) {
        $findings.Add("severity_count_$($severities.Count)")
    }
    if ((Get-TitleWordCount $Issue.title) -gt 8) {
        $findings.Add("title_over_8_words")
    }

    # A newly filed diagnostic may carry its runnable method + expected result
    # in the issue template body. A shipped verify lifecycle still requires the
    # current method comment posted in the same pass as the label.
    $includeIssueBody = $lifecycle -contains 'diagnostics-armed'
    if ($lifecycle.Count -gt 0 -and -not (Test-HasMethodAndExpected $Issue -IncludeBody:$includeIssueBody)) {
        $findings.Add("missing_test_method_comment")
    }

    $repositoryOnly = Test-IsRepositoryOnlyIssue $Issue
    if ($repositoryOnly -and $lifecycle -contains "verify-fix-coop") {
        $findings.Add("repository_only_uses_coop_lifecycle")
    }

    $requiresCoop = Test-CommentRequiresCoop $Issue
    if ($requiresCoop -and $lifecycle -contains "verify-fix") {
        $findings.Add("solo_label_but_coop_test")
    }
    if (-not $requiresCoop -and $lifecycle -contains "verify-fix-coop") {
        $findings.Add("coop_label_without_coop_test_evidence")
    }
    if ($lifecycle -contains "diagnostics-armed") {
        $hasQualifier = $labels -contains "coop-required"
        if ($requiresCoop -and -not $hasQualifier) {
            $findings.Add("coop_diagnostics_missing_qualifier")
        }
        if (-not $requiresCoop -and $hasQualifier) {
            $findings.Add("coop_qualifier_without_test_evidence")
        }
    }

    if ([string]$Issue.body -match '\\n') {
        $findings.Add("literal_escaped_newline_in_body")
    }
    if ([string]$Issue.body -match '(?m)^##\s') {
        $findings.Add("heading_format_in_body")
    }

    $wordCount = @(([string]$Issue.body) -split '\s+' | Where-Object { $_ }).Count
    if ($wordCount -gt 220) {
        $findings.Add("body_over_220_words")
    }

    return @($findings)
}

function Get-VerificationScope($Issue) {
    $labels = Get-LabelNames $Issue
    if (Test-IsRepositoryOnlyIssue $Issue) {
        return "repository-only"
    }
    if ($labels -contains "verify-fix-coop" -or $labels -contains "coop-required") {
        return "coop"
    }
    return "solo"
}

function Get-RiskTier($Issue) {
    $parts = @([string]$Issue.title, [string]$Issue.body)
    foreach ($label in @(Get-LabelNames $Issue)) { $parts += $label }
    $text = $parts -join "`n"
    if ($text -match '(?i)startup crash|blocks? (all )?testing|access violation|heap|backend.*crash|client.*crash|crash.*client') {
        return "critical"
    }
    if ($text -match '(?i)crash|backend|network|rpc|desync|corrupt|official realm|resource not loaded|material.*not found') {
        return "high"
    }
    if ($text -match '(?i)cosmetic|preview|animation|persist|craft|duplicate|locali[sz]|talent|mission|bot') {
        return "moderate"
    }
    return "low"
}

function Get-RecommendedAction($Issue) {
    $labels = Get-LabelNames $Issue
    if (Test-IsRepositoryOnlyIssue $Issue) {
        if ($labels -contains "verify-fix") { return "run the documented autonomous verification, record evidence, then close" }
        if ($labels -contains "diagnostics-armed") { return "run the documented autonomous diagnostic and record its bounded evidence" }
        if ($labels -contains "verify-fix-coop") { return "replace the invalid co-op lifecycle with repository-only verification routing" }
    }
    if ($labels -contains "verify-fix-coop") { return "two-player in-game verification" }
    if ($labels -contains "verify-fix") { return "solo in-game verification" }
    if ($labels -contains "diagnostics-armed") { return "run documented repro and collect bounded diagnostics" }
    return "scope against source, then implement or arm diagnostics"
}

function Get-EmpiricalFallbacks($Issue) {
    $labels = Get-LabelNames $Issue
    $lifecycle = @($labels | Where-Object { $LifecycleLabels -contains $_ }) | Select-Object -First 1
    $number = [int]$Issue.number

    if (Test-IsRepositoryOnlyIssue $Issue) {
        if ($lifecycle -eq "verify-fix") {
            return @(
                [ordered]@{ trigger = "The documented autonomous verification for #$number fails on current canonical source."; change = "Repair the first failing repository invariant and rerun the same deterministic check."; falsifier = "The named check passes from a clean current-master worktree." },
                [ordered]@{ trigger = "The check passes locally but fails in CI or another supported shell/runtime."; change = "Reproduce the environment delta with a bounded fixture and make the tool deterministic across the supported environments."; falsifier = "The compared environments use identical inputs and produce identical results." },
                [ordered]@{ trigger = "The claimed documentation or policy outcome is not enforced by code or a self-test."; change = "Add the smallest executable guard that fails on the retired behavior and update the owner documentation."; falsifier = "An existing blocking guard already proves the stated invariant." }
            )
        }
        return @(
            [ordered]@{ trigger = "The documented autonomous diagnostic for #$number identifies a specific repository-state divergence."; change = "Repair only the first divergent file, rule, or generated artifact and retain the diagnostic as regression coverage."; falsifier = "The diagnostic reports no divergence on current canonical source." },
            [ordered]@{ trigger = "The diagnostic result differs between supported PowerShell/runtime environments."; change = "Reduce the difference to a deterministic fixture and normalize only the proven environment-dependent input."; falsifier = "Both environments receive identical normalized input and still disagree." },
            [ordered]@{ trigger = "Insufficient evidence: the autonomous diagnostic cannot distinguish the remaining candidates."; change = "Add one bounded repository fixture at each adjacent boundary, then rerun without involving the game."; falsifier = "The existing diagnostic already names one causal boundary." }
        )
    }

    if ($lifecycle -eq "verify-fix-coop") {
        return @(
            [ordered]@{ trigger = "The posted host/client verification for #$number fails and paired logs identify the first divergent peer/state."; change = "Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary."; falsifier = "Both peers log identical authoritative state before the visible failure." },
            [ordered]@{ trigger = "Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge."; change = "Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state."; falsifier = "Authority, sender authentication, and lifecycle replay are already identical on both peers." },
            [ordered]@{ trigger = "Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource."; change = "Parity-gate the optional feature and select a resident vanilla fallback for that peer."; falsifier = "The failing peer proves positive parity and local resource closure." }
        )
    }
    if ($lifecycle -eq "verify-fix") {
        return @(
            [ordered]@{ trigger = "The issue's posted build-specific verification fails at a named invariant or surface."; change = "Repair the first failed invariant in the current implementation, scoped to that surface."; falsifier = "The invariant passes while the reported symptom remains." },
            [ordered]@{ trigger = "Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract."; change = "Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior."; falsifier = "The custom and vanilla boundary inputs/outputs are identical." },
            [ordered]@{ trigger = "The loaded version/hash or canonical ancestry does not contain the claimed fix."; change = "Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior."; falsifier = "The failing log and deployed hash prove the current canonical commit was running." }
        )
    }
    if ($lifecycle -eq "diagnostics-armed") {
        return @(
            [ordered]@{ trigger = "The issue's bounded armed repro records a first state divergence."; change = "Repair only the layer named by that trace."; falsifier = "The trace remains healthy through the observed symptom." },
            [ordered]@{ trigger = "Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract."; change = "Repair the first contract mismatch and retain the probe as regression evidence."; falsifier = "Captured state matches the source contract at every sampled boundary." },
            [ordered]@{ trigger = "Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates."; change = "Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix."; falsifier = "The existing probe already identifies one causal boundary." }
        )
    }
    return @(
        [ordered]@{ trigger = "The issue body and cited source establish a bounded acceptance contract."; change = "Implement that contract on current canonical source with a truth-table regression."; falsifier = "Source/runtime evidence contradicts a required premise in the accepted contract." },
        [ordered]@{ trigger = "Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries."; change = "Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence."; falsifier = "Existing evidence already identifies the divergent boundary." },
        [ordered]@{ trigger = "The requested path is blocked by absent provenance/license, resource residency, or external service authority."; change = "Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists."; falsifier = "The required provenance, resource closure, and authority are all positively proved." }
    )
}

function Get-UmbrellaIssues($Lessons) {
    $refs = New-Object System.Collections.Generic.List[int]
    $appearance = @(
        "renderer_specific_material_closure",
        "unsafe_native_call_preflight",
        "shared_preview_presentation_descriptor",
        "custom_unit_behavioral_contract",
        "asset_alpha_mip_material_contract",
        "appearance_surface_fanout"
    )
    if (@($Lessons | Where-Object { $appearance -contains $_ }).Count -gt 0) { $refs.Add(420) }
    if ($Lessons -contains "canonical_identity_persistence" -or $Lessons -contains "backend_realm_isolation") { $refs.Add(428) }
    if ($Lessons -contains "source_first_engine_contract") { $refs.Add(504) }
    $refs.Add(546)
    return @($refs | Select-Object -Unique)
}

function Get-ApplicableLessons($Issue) {
    $parts = @([string]($Issue.title), [string]($Issue.body))
    foreach ($label in @(Get-LabelNames $Issue)) { $parts += [string]($label) }
    foreach ($comment in @($Issue.comments)) { $parts += [string]($comment.body) }
    $evidence = $parts -join "`n"

    # Do not name this `$matches`: PowerShell overwrites that automatic
    # variable with a hashtable after every successful `-match` expression.
    $lessonMatches = @()
    foreach ($entry in $LessonRules.GetEnumerator()) {
        if ($evidence -match $entry.Value) { $lessonMatches += [string]($entry.Key) }
    }
    if ($lessonMatches.Count -eq 0) { $lessonMatches += "general_regression_and_verification_discipline" }
    return @($lessonMatches)
}

function Get-IssueEvidenceText($Issue, [bool]$IncludeComments = $true) {
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add([string]$Issue.title)
    $parts.Add([string]$Issue.body)
    if ($IncludeComments) {
        foreach ($comment in @($Issue.comments)) { $parts.Add([string]$comment.body) }
    }
    return $parts -join "`n"
}

function Get-UniqueStrings($Values) {
    return @($Values | Where-Object { $_ } | ForEach-Object { [string]$_ } | Sort-Object -Unique)
}

function Get-IssueReferences($Issue) {
    $refs = @()
    foreach ($match in [regex]::Matches((Get-IssueEvidenceText $Issue $true), '(?<![A-Za-z0-9])#(?<number>\d{1,5})')) {
        $number = [int]$match.Groups['number'].Value
        if ($number -ne [int]$Issue.number) { $refs += $number }
    }
    return @($refs | Sort-Object -Unique)
}

function Get-CodeIdentifiers($Issue) {
    $text = Get-IssueEvidenceText $Issue $true
    $values = New-Object System.Collections.Generic.List[string]
    $patterns = @(
        '`(?<id>[^`\r\n]{3,100})`',
        '(?<![A-Za-z0-9])(?<id>[A-Za-z0-9_./\\-]+\.(?:lua|ps1|psd1|json|md|dds|png|fbx|unit|material|mod_bundle))(?![A-Za-z0-9])',
        '(?<![A-Za-z0-9])(?<id>[a-z][a-z0-9]*_[a-z0-9_]{2,})(?![A-Za-z0-9])',
        '(?<![A-Za-z0-9])(?<id>[A-Z][A-Za-z0-9_]+\.[A-Za-z_][A-Za-z0-9_.]*)(?![A-Za-z0-9])'
    )
    foreach ($pattern in $patterns) {
        foreach ($match in [regex]::Matches($text, $pattern)) {
            $value = $match.Groups['id'].Value.Trim().ToLowerInvariant()
            if ($value.Length -gt 100 -or $value -match '^https?://' -or $value -match '^[0-9a-f]{7,40}$') { continue }
            $values.Add($value)
        }
    }
    return @(Get-UniqueStrings $values)
}

function Get-NormalizedTermsFromText([string]$Text) {
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($match in [regex]::Matches(([string]$Text).ToLowerInvariant(), '(?<![a-z0-9])[a-z][a-z0-9-]{3,39}(?![a-z0-9])')) {
        $value = $match.Value.Trim('-')
        if (-not $value -or $TermStopWords -contains $value -or $value -match '^v?\d') { continue }
        $values.Add($value)
    }
    return @(Get-UniqueStrings $values)
}

function Get-SubsystemLabels($Issue) {
    return @(Get-LabelNames $Issue | Where-Object {
        $_ -and $NonSubsystemLabels -notcontains $_ -and $_ -notmatch '^\d+-'
    } | Sort-Object -Unique)
}

function Get-ClosureEvidence($Issue) {
    $rows = New-Object System.Collections.Generic.List[object]
    $seenKinds = @{}
    $sources = @()
    $sources += [PSCustomObject]@{ body = [string]$Issue.body; url = [string]$Issue.url }
    foreach ($comment in @($Issue.comments)) {
        $sources += [PSCustomObject]@{ body = [string]$comment.body; url = [string]$comment.url }
    }
    [array]::Reverse($sources)

    $patterns = [ordered]@{
        user_confirmed_fixed = '(?i)user[- ]confirmed fixed|confirmed (?:fully )?(?:fixed|working)|verified (?:as )?fixed|tested and confirmed (?:fixed|working)|fully functional'
        verification_passed = '(?i)(?:verification|test|repro).{0,40}(?:pass(?:ed)?|complete|no longer occurs)|live proof completed'
        regression_coverage = '(?i)(?:offline|unit|regression|self[- ]test).{0,40}(?:pass(?:ed)?|cover(?:s|age)|guard|assert)'
        source_commit_recorded = '(?i)(?:source )?commit\s+`?[0-9a-f]{7,40}`?'
    }
    foreach ($source in $sources) {
        foreach ($entry in $patterns.GetEnumerator()) {
            if ($seenKinds.ContainsKey($entry.Key)) { continue }
            $match = [regex]::Match([string]$source.body, [string]$entry.Value)
            if (-not $match.Success) { continue }
            $excerpt = ([string]$source.body -replace '\s+', ' ').Trim()
            if ($excerpt.Length -gt 180) { $excerpt = $excerpt.Substring(0, 177) + '...' }
            $rows.Add([PSCustomObject][ordered]@{
                kind = [string]$entry.Key
                source_url = [string]$source.url
                excerpt = $excerpt
            })
            $seenKinds[$entry.Key] = $true
        }
    }
    if ((Get-LabelNames $Issue) -contains 'Fixed') {
        $rows.Add([PSCustomObject][ordered]@{ kind = 'fixed_label'; source_url = [string]$Issue.url; excerpt = 'Closed issue carries the historical Fixed label.' })
    }
    if ([string]$Issue.stateReason -eq 'COMPLETED') {
        $rows.Add([PSCustomObject][ordered]@{ kind = 'completed_state_reason'; source_url = [string]$Issue.url; excerpt = 'GitHub stateReason is COMPLETED.' })
    }
    return @($rows | ForEach-Object { $_ })
}

function New-ValueLookup($Values) {
    $lookup = @{}
    foreach ($value in @($Values)) { $lookup[[string]$value] = $true }
    return $lookup
}

function New-IssueProfile($Issue, [bool]$IsClosed) {
    $subsystems = @(Get-SubsystemLabels $Issue)
    $lessons = @(Get-ApplicableLessons $Issue | Where-Object { $_ -ne 'general_regression_and_verification_discipline' })
    $references = @(Get-IssueReferences $Issue)
    $identifiers = @(Get-CodeIdentifiers $Issue)
    $titleTerms = @(Get-NormalizedTermsFromText ([string]$Issue.title))
    $allTerms = @(Get-NormalizedTermsFromText (([string]$Issue.title) + "`n" + ([string]$Issue.body)))
    return [PSCustomObject][ordered]@{
        number = [int]$Issue.number
        issue = $Issue
        subsystem_labels = $subsystems
        subsystem_lookup = New-ValueLookup $subsystems
        lessons = $lessons
        lesson_lookup = New-ValueLookup $lessons
        references = $references
        reference_lookup = New-ValueLookup $references
        code_identifiers = $identifiers
        code_identifier_lookup = New-ValueLookup $identifiers
        title_terms = $titleTerms
        title_term_lookup = New-ValueLookup $titleTerms
        all_terms = $allTerms
        all_term_lookup = New-ValueLookup $allTerms
        closure_evidence = if ($IsClosed) { @(Get-ClosureEvidence $Issue) } else { @() }
    }
}

function Get-Intersection($Left, $Right) {
    if (@($Left).Count -eq 0 -or @($Right).Count -eq 0) { return @() }
    $rightSet = if ($Right -is [System.Collections.IDictionary]) { $Right } else { New-ValueLookup $Right }
    $result = @()
    $seen = @{}
    foreach ($value in @($Left)) {
        $key = [string]$value
        if ($rightSet.ContainsKey($key) -and -not $seen.ContainsKey($key)) {
            $result += $value
            $seen[$key] = $true
        }
    }
    return $result
}

function Add-RelationIndexValue($Index, [string]$Key, [int]$IssueNumber) {
    if (-not $Key) { return }
    if (-not $Index.ContainsKey($Key)) { $Index[$Key] = @() }
    # Each profile has already de-duplicated its own signals, so the same issue
    # number cannot be added twice for one key. Avoid an O(n) `-notcontains`
    # scan on every insertion; common labels/terms otherwise make live audits
    # quadratic before ranking even starts.
    $Index[$Key] += $IssueNumber
}

function New-RelationContext($OpenIssues, $ClosedIssues) {
    $contextTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $openProfiles = @{}
    $closedProfiles = @{}
    $frequency = @{}
    $allProfiles = @()
    foreach ($issue in @($OpenIssues)) {
        $profile = New-IssueProfile $issue $false
        $openProfiles[[string]$profile.number] = $profile
        $allProfiles += $profile
        if (-not $SelfTest -and $allProfiles.Count % 100 -eq 0) { Write-Host "[audit-open-issues] profiled $($allProfiles.Count) issues in $([Math]::Round($contextTimer.Elapsed.TotalSeconds, 1))s" }
    }
    foreach ($issue in @($ClosedIssues)) {
        $profile = New-IssueProfile $issue $true
        $closedProfiles[[string]$profile.number] = $profile
        $allProfiles += $profile
        if (-not $SelfTest -and $allProfiles.Count % 100 -eq 0) { Write-Host "[audit-open-issues] profiled $($allProfiles.Count) issues in $([Math]::Round($contextTimer.Elapsed.TotalSeconds, 1))s" }
    }
    foreach ($profile in $allProfiles) {
        foreach ($term in @($profile.all_terms)) {
            if (-not $frequency.ContainsKey($term)) { $frequency[$term] = 0 }
            $frequency[$term]++
        }
    }
    if (-not $SelfTest) { Write-Host "[audit-open-issues] built term frequencies in $([Math]::Round($contextTimer.Elapsed.TotalSeconds, 1))s" }
    $indexes = [ordered]@{
        references = @{}
        subsystem_labels = @{}
        lessons = @{}
        code_identifiers = @{}
        terms = @{}
    }
    foreach ($profile in @($closedProfiles.Values)) {
        foreach ($value in @($profile.references)) { Add-RelationIndexValue $indexes.references ([string]$value) $profile.number }
        foreach ($value in @($profile.subsystem_labels)) { Add-RelationIndexValue $indexes.subsystem_labels ([string]$value) $profile.number }
        foreach ($value in @($profile.lessons)) { Add-RelationIndexValue $indexes.lessons ([string]$value) $profile.number }
        foreach ($value in @($profile.code_identifiers)) { Add-RelationIndexValue $indexes.code_identifiers ([string]$value) $profile.number }
        foreach ($value in @($profile.all_terms)) { Add-RelationIndexValue $indexes.terms ([string]$value) $profile.number }
    }
    if (-not $SelfTest) { Write-Host "[audit-open-issues] built closed-history indexes in $([Math]::Round($contextTimer.Elapsed.TotalSeconds, 1))s" }
    return [PSCustomObject][ordered]@{
        open_profiles = $openProfiles
        closed_profiles = $closedProfiles
        term_frequency = $frequency
        issue_count = $allProfiles.Count
        indexes = $indexes
    }
}

function Add-RelationReason($Reasons, [string]$Kind, [int]$Score, $Evidence) {
    $Reasons.Add([PSCustomObject][ordered]@{
        kind = $Kind
        score = $Score
        evidence = @($Evidence)
    })
}

function Get-RelatedClosedIssues($OpenProfile, $RelationContext) {
    $candidates = New-Object System.Collections.Generic.List[object]
    $rareLimit = [Math]::Max(8, [Math]::Ceiling([double]$RelationContext.issue_count * 0.08))
    $candidateNumbers = @{}

    foreach ($reference in @($OpenProfile.references)) {
        if ($RelationContext.closed_profiles.ContainsKey([string]$reference)) { $candidateNumbers[[string]$reference] = $true }
        foreach ($number in @($RelationContext.indexes.references[[string]$reference])) { $candidateNumbers[[string]$number] = $true }
    }
    foreach ($number in @($RelationContext.indexes.references[[string]$OpenProfile.number])) { $candidateNumbers[[string]$number] = $true }
    foreach ($value in @($OpenProfile.subsystem_labels)) {
        foreach ($number in @($RelationContext.indexes.subsystem_labels[[string]$value])) { $candidateNumbers[[string]$number] = $true }
    }
    foreach ($value in @($OpenProfile.lessons)) {
        foreach ($number in @($RelationContext.indexes.lessons[[string]$value])) { $candidateNumbers[[string]$number] = $true }
    }
    foreach ($value in @($OpenProfile.code_identifiers)) {
        foreach ($number in @($RelationContext.indexes.code_identifiers[[string]$value])) { $candidateNumbers[[string]$number] = $true }
    }
    foreach ($value in @($OpenProfile.all_terms)) {
        if (-not $RelationContext.term_frequency.ContainsKey($value) -or $RelationContext.term_frequency[$value] -gt $rareLimit) { continue }
        foreach ($number in @($RelationContext.indexes.terms[[string]$value])) { $candidateNumbers[[string]$number] = $true }
    }

    foreach ($candidateNumber in @($candidateNumbers.Keys)) {
        $closedProfile = $RelationContext.closed_profiles[[string]$candidateNumber]
        if (-not $closedProfile) { continue }
        $reasons = New-Object System.Collections.Generic.List[object]
        $score = 0
        $direct = $false

        if (@($OpenProfile.references) -contains [int]$closedProfile.number) {
            Add-RelationReason $reasons 'open_explicitly_references_closed' 120 @("#$($closedProfile.number)")
            $score += 120
            $direct = $true
        }
        if ($closedProfile.reference_lookup.ContainsKey([string]$OpenProfile.number)) {
            Add-RelationReason $reasons 'closed_explicitly_references_open' 120 @("#$($OpenProfile.number)")
            $score += 120
            $direct = $true
        }

        $sharedRefs = @(Get-Intersection $OpenProfile.references $closedProfile.reference_lookup | Where-Object {
            $_ -ne [int]$OpenProfile.number -and $_ -ne [int]$closedProfile.number
        } | Select-Object -First 3)
        if ($sharedRefs.Count -gt 0) {
            $points = [Math]::Min(24, 8 * $sharedRefs.Count)
            Add-RelationReason $reasons 'shared_explicit_references' $points @($sharedRefs | ForEach-Object { "#$_" })
            $score += $points
        }

        $sharedSubsystems = @(Get-Intersection $OpenProfile.subsystem_labels $closedProfile.subsystem_lookup)
        if ($sharedSubsystems.Count -gt 0) {
            $points = [Math]::Min(60, 30 * $sharedSubsystems.Count)
            Add-RelationReason $reasons 'shared_subsystem_labels' $points $sharedSubsystems
            $score += $points
        }

        $sharedLessons = @(Get-Intersection $OpenProfile.lessons $closedProfile.lesson_lookup | Select-Object -First 4)
        if ($sharedLessons.Count -gt 0) {
            $points = [Math]::Min(32, 8 * $sharedLessons.Count)
            Add-RelationReason $reasons 'shared_lifecycle_surface_classes' $points $sharedLessons
            $score += $points
        }

        $sharedIdentifiers = @(Get-Intersection $OpenProfile.code_identifiers $closedProfile.code_identifier_lookup | Select-Object -First 3)
        if ($sharedIdentifiers.Count -gt 0) {
            $points = [Math]::Min(60, 20 * $sharedIdentifiers.Count)
            Add-RelationReason $reasons 'shared_code_identifiers' $points $sharedIdentifiers
            $score += $points
        }

        $sharedTitleTerms = @(Get-Intersection $OpenProfile.title_terms $closedProfile.title_term_lookup | Where-Object {
            $RelationContext.term_frequency.ContainsKey($_) -and $RelationContext.term_frequency[$_] -le $rareLimit
        } | Select-Object -First 4)
        if ($sharedTitleTerms.Count -gt 0) {
            $points = [Math]::Min(28, 7 * $sharedTitleTerms.Count)
            Add-RelationReason $reasons 'shared_distinctive_title_terms' $points $sharedTitleTerms
            $score += $points
        }

        $sharedTerms = @(Get-Intersection $OpenProfile.all_terms $closedProfile.all_term_lookup | Where-Object {
            $RelationContext.term_frequency.ContainsKey($_) -and $RelationContext.term_frequency[$_] -le $rareLimit -and $sharedTitleTerms -notcontains $_
        } | Select-Object -First 5)
        if ($sharedTerms.Count -gt 0) {
            $points = [Math]::Min(15, 3 * $sharedTerms.Count)
            Add-RelationReason $reasons 'shared_distinctive_terms' $points $sharedTerms
            $score += $points
        }

        # Closure evidence cannot create a relationship.  It only raises the
        # review priority of an already-related candidate because it identifies
        # a prior repair that was actually closed/verified rather than abandoned.
        if ($score -gt 0 -and @($closedProfile.closure_evidence).Count -gt 0) {
            $kinds = @($closedProfile.closure_evidence.kind | Sort-Object -Unique)
            $points = [Math]::Min(12, 2 * $kinds.Count)
            Add-RelationReason $reasons 'closure_verification_evidence' $points $kinds
            $score += $points
        }

        if ($score -le 0) { continue }
        $hasStrongCombination = $sharedSubsystems.Count -gt 0 -and (
            $sharedLessons.Count -gt 0 -or $sharedIdentifiers.Count -gt 0 -or
            $sharedTitleTerms.Count -gt 0 -or $sharedTerms.Count -gt 0
        )
        $confidence = if ($direct -or $score -ge 100) { 'high' } elseif ($score -ge 55 -or $hasStrongCombination) { 'medium' } else { 'low' }
        $regressionSignal = if ($direct) {
            'direct-history-reference'
        } elseif ($hasStrongCombination -and @($closedProfile.closure_evidence).Count -gt 0) {
            'same-subsystem-surface-after-verified-closure'
        } elseif ($hasStrongCombination) {
            'same-subsystem-surface'
        } else {
            'related-history-review-only'
        }
        $issue = $closedProfile.issue
        $candidates.Add([PSCustomObject][ordered]@{
            number = [int]$issue.number
            title = [string]$issue.title
            url = [string]$issue.url
            closed_at = [string]$issue.closedAt
            score = [int]$score
            confidence = $confidence
            regression_signal = $regressionSignal
            # Materialize fresh plain objects here. PowerShell can otherwise retain
            # Generic.List pipeline wrappers deeply enough that ConvertTo-Json emits
            # their display strings ("@{kind=...}") instead of structured evidence.
            reasons = @($reasons | ForEach-Object {
                [PSCustomObject][ordered]@{
                    kind = [string]$_.kind
                    score = [int]$_.score
                    evidence = @($_.evidence | ForEach-Object { [string]$_ })
                }
            })
            closure_evidence = @($closedProfile.closure_evidence | ForEach-Object {
                [PSCustomObject][ordered]@{
                    kind = [string]$_.kind
                    source_url = [string]$_.source_url
                    excerpt = [string]$_.excerpt
                }
            })
            review_policy = 'manual review only; never auto-reopen from similarity'
        })
    }

    $sorted = @($candidates | ForEach-Object { $_ } | Sort-Object -Property @{ Expression = 'score'; Descending = $true }, @{ Expression = 'closed_at'; Descending = $true }, @{ Expression = 'number'; Descending = $true })
    $evidenceBacked = @($sorted | Where-Object { $_.confidence -eq 'high' })
    $weakSlots = [Math]::Max(0, $MaxClosedMatches - $evidenceBacked.Count)
    $weakReview = @($sorted | Where-Object { $_.confidence -ne 'high' } | Select-Object -First $weakSlots)
    return @($evidenceBacked + $weakReview | Sort-Object -Property @{ Expression = 'score'; Descending = $true }, @{ Expression = 'closed_at'; Descending = $true }, @{ Expression = 'number'; Descending = $true })
}

function Invoke-Audit($Issues, $ClosedIssues = @()) {
    $auditTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $relationContext = New-RelationContext $Issues $ClosedIssues
    if (-not $SelfTest) { Write-Host "[audit-open-issues] indexed $(@($Issues).Count) open and $(@($ClosedIssues).Count) closed issues in $([Math]::Round($auditTimer.Elapsed.TotalSeconds, 1))s" }
    $rows = @()
    $processed = 0
    foreach ($issue in @($Issues | Sort-Object -Property number)) {
        $findings = @(Get-IssueFindings $issue)
        $lessons = @(Get-ApplicableLessons $issue)
        $related = @(Get-RelatedClosedIssues $relationContext.open_profiles[[string]$issue.number] $relationContext)
        $rows += [PSCustomObject][ordered]@{
            number = [int]$issue.number
            title = [string]$issue.title
            url = [string]$issue.url
            labels = @(Get-LabelNames $issue)
            applicable_lessons = $lessons
            umbrella_issues = @(Get-UmbrellaIssues $lessons)
            risk_tier = Get-RiskTier $issue
            verification_scope = Get-VerificationScope $issue
            recommended_next_action = Get-RecommendedAction $issue
            related_closed_issues = $related
            related_closed_status = if ($related.Count -gt 0) { 'ranked-evidence-review' } else { 'no-evidence-backed-closed-match' }
            fallbacks = @(Get-EmpiricalFallbacks $issue)
            findings = $findings
            clean = ($findings.Count -eq 0)
        }
        $processed++
        if (-not $SelfTest -and $processed % 50 -eq 0) {
            Write-Host "[audit-open-issues] ranked $processed/$(@($Issues).Count) open issues in $([Math]::Round($auditTimer.Elapsed.TotalSeconds, 1))s"
        }
    }

    $counts = [ordered]@{}
    foreach ($finding in @($rows.findings)) {
        foreach ($name in @($finding)) {
            if (-not $counts.Contains($name)) { $counts[$name] = 0 }
            $counts[$name]++
        }
    }

    $lessonCounts = [ordered]@{}
    foreach ($lessons in @($rows.applicable_lessons)) {
        foreach ($name in @($lessons)) {
            if (-not $lessonCounts.Contains($name)) { $lessonCounts[$name] = 0 }
            $lessonCounts[$name]++
        }
    }

    return [PSCustomObject][ordered]@{
        schema = 4
        generated_utc = [DateTime]::UtcNow.ToString("o")
        repository = $Repository
        open_issue_count = $rows.Count
        closed_issue_count = @($ClosedIssues).Count
        clean_issue_count = @($rows | Where-Object { $_.clean }).Count
        open_issues_with_related_closed = @($rows | Where-Object { @($_.related_closed_issues).Count -gt 0 }).Count
        open_issues_without_related_closed = @($rows | Where-Object { @($_.related_closed_issues).Count -eq 0 }).Count
        high_confidence_relation_count = @($rows.related_closed_issues | ForEach-Object { @($_) } | Where-Object { $_.confidence -eq 'high' }).Count
        finding_counts = $counts
        lesson_counts = $lessonCounts
        note = "All related-closed matches are a transparent review queue, never proof of root cause and never authority to auto-reopen. Closure evidence only boosts an independently-related candidate."
        issues = $rows
    }
}

function Convert-AuditToMarkdown($Report) {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Open issue empirical contingency register")
    $lines.Add("")
    $lines.Add("Generated from the live GitHub issue body, comments, labels, and URL at ``$($Report.generated_utc)``. This is a recovery register, not a root-cause claim. Each path states the evidence that must trigger it and the observation that falsifies it. ``Insufficient evidence`` entries deliberately request a bounded probe instead of inventing a fix.")
    $lines.Add("")
    $lines.Add("Open issues audited: **$($Report.open_issue_count)**. Closed issues compared: **$($Report.closed_issue_count)**. Open issues with at least one evidence-ranked closed candidate: **$($Report.open_issues_with_related_closed)**. High-confidence relations: **$($Report.high_confidence_relation_count)**.")
    $lines.Add("")
    $lines.Add("> Related-closed rankings are a manual review queue. They do not prove a shared root cause and must never auto-reopen an issue. Closure evidence only increases priority after an independent relationship signal exists.")
    foreach ($issue in @($Report.issues)) {
        $title = ([string]$issue.title).Trim()
        $labels = @($issue.labels) -join ", "
        $lessons = @($issue.applicable_lessons) -join ", "
        $lines.Add("")
        $lines.Add("## #$($issue.number) - $title")
        $lines.Add("")
        $lines.Add("- Tracker: [$($issue.url)]($($issue.url))")
        $lines.Add("- Current labels: ``$labels``")
        $lines.Add("- Evidence class: ``$lessons``")
        $lines.Add("- Current action: $($issue.recommended_next_action)")
        $lines.Add("- Closed-history status: ``$($issue.related_closed_status)``")
        if (@($issue.related_closed_issues).Count -gt 0) {
            $lines.Add("")
            $lines.Add("**Ranked related closed issues (manual review)**")
            $rank = 0
            foreach ($closed in @($issue.related_closed_issues)) {
                $rank++
                $lines.Add("")
                $lines.Add("$rank. [#$($closed.number) - $($closed.title)]($($closed.url)) - score ``$($closed.score)``, confidence ``$($closed.confidence)``, signal ``$($closed.regression_signal)``, closed ``$($closed.closed_at)``")
                foreach ($reason in @($closed.reasons)) {
                    $reasonEvidence = @($reason.evidence) -join ", "
                    $lines.Add("   - ``$($reason.kind)`` (+$($reason.score)): $reasonEvidence")
                }
                if (@($closed.closure_evidence).Count -gt 0) {
                    $closureKinds = @($closed.closure_evidence.kind | Sort-Object -Unique) -join ", "
                    $lines.Add("   - Prior closure evidence: ``$closureKinds``")
                }
            }
        } else {
            $lines.Add("")
            $lines.Add("No closed issue has an evidence-backed relation under the current exact-reference, subsystem, surface, identifier, and distinctive-term rules. Do not fabricate ancestry.")
        }
        $index = 0
        foreach ($fallback in @($issue.fallbacks)) {
            $index++
            $lines.Add("")
            $lines.Add("**Fallback $index**")
            $lines.Add("")
            $lines.Add("- **Evidence/trigger:** $($fallback.trigger)")
            $lines.Add("- **Change:** $($fallback.change)")
            $lines.Add("- **Falsifier:** $($fallback.falsifier)")
        }
    }
    return $lines -join [Environment]::NewLine
}

function Invoke-SelfTest {
    $fixture = @(
        [PSCustomObject]@{
            number = 1; title = "Blightreaper husk transform"; body = "**Symptom:** remote husk drifts after #90, #92, #93, #94, #95, #96, and #97. ``SimpleHuskInventoryExtension._wield_slot`` differs."; url = "u1"
            labels = @(@{ name = "bug" }, @{ name = "verify-fix-coop" }, @{ name = "WOC" }, @{ name = "0-critical" })
            comments = @(@{ body = "Test method (co-op):`n1. Host equips the Blightreaper while one client observes.`nExpected: remote peer keeps the Blightreaper transform." })
        },
        [PSCustomObject]@{
            number = 2; title = "This title contains far too many words for doctrine"; body = "## Broken\\nBody"; url = "u2"
            labels = @(@{ name = "bug" }, @{ name = "enhancement" }, @{ name = "not-started" })
            comments = @()
        },
        [PSCustomObject]@{
            number = 3; title = "Missing method"; body = "**Symptom:** x"; url = "u3"
            labels = @(@{ name = "feature" }, @{ name = "verify-fix" }, @{ name = "2-moderate" })
            comments = @(@{ body = "Shipped today." })
        },
        [PSCustomObject]@{
            number = 4; title = "Lifecycle checker migration"; body = "**Symptom:** retired lifecycle labels remain accepted."; url = "u4"
            labels = @(@{ name = "enhancement" }, @{ name = "verify-fix" }, @{ name = "tooling" }, @{ name = "2-moderate" })
            comments = @(@{ body = "Verification method (autonomous): run the lifecycle self-tests. Expected: all retired-label fixtures are rejected." })
        },
        [PSCustomObject]@{
            number = 5; title = "Mixed retired lifecycle"; body = "**Symptom:** a retired label survived migration."; url = "u5"
            labels = @(@{ name = "bug" }, @{ name = "diagnostics-armed" }, @{ name = "Fixed" }, @{ name = "cross-mod" }, @{ name = "2-moderate" })
            comments = @(@{ body = "Diagnostic method: run the lifecycle audit. Expected: mixed retired labels are rejected." })
        },
        [PSCustomObject]@{
            number = 6; title = "Runtime weapon documentation regression"; body = "**Symptom:** runtime weapon behavior regressed."; url = "u6"
            labels = @(@{ name = "bug" }, @{ name = "documentation" }, @{ name = "regression" }, @{ name = "Tweaker: Weapons" }, @{ name = "CWV" }, @{ name = "cross-mod" }, @{ name = "verify-fix" }, @{ name = "0-critical" }, @{ name = "WOC" })
            comments = @(@{ body = "Verification method (solo): launch the game and exercise the weapon regression. Expected: runtime behavior remains correct." })
        }
    )
    $closedFixture = @(
        [PSCustomObject]@{
            number = 90; title = "Blightreaper remote husk transform"; body = "Fixed ``SimpleHuskInventoryExtension._wield_slot`` lifecycle handling."; url = "c90"; closedAt = "2026-07-10T00:00:00Z"; stateReason = "COMPLETED"
            labels = @(@{ name = "bug" }, @{ name = "Fixed" }, @{ name = "WOC" })
            comments = @(@{ body = "User-confirmed fixed. Regression coverage passed."; url = "c90-comment" })
        },
        [PSCustomObject]@{
            number = 91; title = "Unrelated release workflow"; body = "Publishing completed."; url = "c91"; closedAt = "2026-07-11T00:00:00Z"; stateReason = "COMPLETED"
            labels = @(@{ name = "tooling" })
            comments = @()
        }
    )
    foreach ($number in 92..97) {
        $closedFixture += [PSCustomObject]@{
            number = $number; title = "Blightreaper history $number"; body = "Prior #1 remote husk transform repair."; url = "c$number"; closedAt = "2026-07-12T00:00:00Z"; stateReason = "COMPLETED"
            labels = @(@{ name = "bug" }, @{ name = "Fixed" }, @{ name = "WOC" })
            comments = @(@{ body = "Regression coverage passed."; url = "c$number-comment" })
        }
    }
    $result = Invoke-Audit $fixture $closedFixture
    if ($result.open_issue_count -ne 6) { throw "fixture count drift" }
    if (-not $result.issues[0].clean) { throw "valid coop issue was rejected" }
    if ($result.issues[1].findings -notcontains "lifecycle_count_0") { throw "retired not-started was incorrectly accepted as lifecycle" }
    if ($result.issues[1].findings -notcontains "type_count_2") { throw "duplicate type not found" }
    if ($result.issues[1].findings -notcontains "severity_count_0") { throw "missing severity not found" }
    if ($result.issues[1].findings -notcontains "literal_escaped_newline_in_body") { throw "escaped newline not found" }
    if ($result.issues[2].findings -notcontains "missing_test_method_comment") { throw "missing method not found" }
    if (-not $result.issues[3].clean) { throw "repository-only issue with one lifecycle and autonomous method was rejected" }
    if ($result.issues[3].verification_scope -ne "repository-only") { throw "repository-only verification scope drift" }
    if ($result.issues[3].recommended_next_action -ne "run the documented autonomous verification, record evidence, then close") { throw "repository-only action drift" }
    if ($result.issues[4].findings -notcontains "retired_lifecycle_present") { throw "mixed retired + canonical lifecycle was accepted" }
    if ($result.issues[5].verification_scope -eq "repository-only") { throw "#661-shaped documentation modifier was incorrectly routed repository-only" }
    if ($result.issues[0].applicable_lessons -notcontains "network_peer_parity") { throw "coop lesson not classified" }
    if ($result.issues[0].verification_scope -ne "coop") { throw "coop verification scope drift" }
    if ($result.issues[0].recommended_next_action -ne "two-player in-game verification") { throw "coop action drift" }
    if ($result.issues[1].risk_tier -notin @("low", "moderate", "high", "critical")) { throw "risk classification drift" }
    if ($result.closed_issue_count -ne 8) { throw "closed fixture count drift" }
    $related = @($result.issues[0].related_closed_issues)
    if ($related.Count -lt 7) { throw "high-confidence relations were truncated by the weak-match floor" }
    foreach ($number in @(90, 92, 93, 94, 95, 96, 97)) {
        if (@($related | Where-Object { $_.number -eq $number }).Count -ne 1) {
            throw "evidence-backed relation #$number was not retained"
        }
    }
    $related90 = @($related | Where-Object { $_.number -eq 90 })[0]
    if ($related.Count -lt 1 -or $related[0].confidence -ne 'high') { throw "directly referenced closed issues did not rank first" }
    if ($related[0].confidence -ne 'high') { throw "direct reference must be high confidence" }
    if (@($related[0].reasons.kind) -notcontains 'open_explicitly_references_closed') { throw "direct reference reason missing" }
    if (@($related90.reasons.kind) -notcontains 'shared_subsystem_labels') { throw "subsystem reason missing" }
    if (@($related90.reasons.kind) -notcontains 'shared_code_identifiers') { throw "code identifier reason missing" }
    $roundTrip = $result | ConvertTo-Json -Depth 18 | ConvertFrom-Json
    if ($roundTrip.issues[0].related_closed_issues[0].reasons[0] -is [string]) {
        throw "JSON relation reasons were stringified"
    }
    if (-not $roundTrip.issues[0].related_closed_issues[0].reasons[0].kind) {
        throw "JSON relation reason structure missing"
    }
    if ($roundTrip.issues[0].related_closed_issues[0].closure_evidence[0] -is [string]) {
        throw "JSON closure evidence was stringified"
    }
    if (@($related90.closure_evidence.kind) -notcontains 'user_confirmed_fixed') { throw "closure evidence missing" }
    if (@($result.issues[1].related_closed_issues | Where-Object { $_.number -eq 91 }).Count -ne 0) { throw "closure evidence created an unrelated relation" }
    foreach ($row in @($result.issues)) {
        if (@($row.fallbacks).Count -ne 3) { throw "issue $($row.number) fallback count drift" }
        foreach ($fallback in @($row.fallbacks)) {
            if (-not $fallback.trigger -or -not $fallback.change -or -not $fallback.falsifier) {
                throw "issue $($row.number) incomplete fallback"
            }
        }
    }
    $soloWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "Ready for solo verification; no second player is required. Expected: PASS." })
    }
    if (Test-CommentRequiresCoop $soloWording) { throw "explicit no-second-player wording was misclassified as co-op" }
    $coopWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "## Diagnostic method (co-op)`n1. Host with two humans and capture the result.`nExpected: bounded evidence." })
    }
    if (-not (Test-CommentRequiresCoop $coopWording)) { throw "co-op diagnostics/two-humans wording was missed" }
    $scopedCoopWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "**Test method (co-op):** Both players confirm the result. Expected: PASS." })
    }
    if (-not (Test-CommentRequiresCoop $scopedCoopWording)) { throw "explicit co-op method header was missed" }
    $scopedSoloWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "**Diagnostic method (solo):** Capture the bounded probe. Rendered parity will later require co-op verification." })
    }
    if (Test-CommentRequiresCoop $scopedSoloWording) { throw "explicit solo method header was overridden by future co-op prose" }
    $correctedScopedSoloWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "## Corrected test method (solo)`nCapture the replacement path. A future implementation may need co-op. Expected: PASS." })
    }
    if (Test-CommentRequiresCoop $correctedScopedSoloWording) { throw "corrected solo method header was not authoritative" }
    $authoritativeSoloWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "**Authoritative solo test - current merged floor:**`nExercise exact owner identity. Remote parity remains under separate co-op issues. Expected: owner path persists." })
    }
    if (Test-CommentRequiresCoop $authoritativeSoloWording) { throw "authoritative solo test header was overridden by remote-scope prose" }
    $markdownScopedCoopWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "### Test method (co-op)`nBoth peers confirm the result. Expected: PASS." })
    }
    if (-not (Test-CommentRequiresCoop $markdownScopedCoopWording)) { throw "Markdown-prefixed co-op method header was missed" }
    $qualifiedScopedCoopWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "Diagnostic method (co-op; deployed v1.2.3)`nOwner and observer capture evidence. Expected: PASS." })
    }
    if (-not (Test-CommentRequiresCoop $qualifiedScopedCoopWording)) { throw "qualified co-op method header was missed" }
    $twoPlayerScopedCoopWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "**TEST METHOD (two-player co-op)**`n1. Reverse roles once.`n`n**PASS =** both peers agree." })
    }
    if (-not (Test-CommentRequiresCoop $twoPlayerScopedCoopWording)) { throw "two-player co-op method header was missed" }
    if (-not (Test-HasMethodAndExpected $twoPlayerScopedCoopWording)) { throw "PASS-equals expected-result wording was missed" }
    $coopRetestWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "Probe extension shipped. Next co-op test method: capture both peers and localize the first divergence. Expected identities are logged." })
    }
    if (-not (Test-CommentRequiresCoop $coopRetestWording)) { throw "co-op retest wording was missed" }
    $floorCorrectionWording = [PSCustomObject]@{
        comments = @(
            [PSCustomObject]@{ body = "## Test method (co-op)`nBoth peers exercise the path. Expected: PASS." },
            [PSCustomObject]@{ body = "## Current deployed-floor correction`nThe newest issue-specific verification procedure/acceptance criteria above remains authoritative; this comment supersedes only older version references. Expected banner v2." }
        )
    }
    if (-not (Test-CommentRequiresCoop $floorCorrectionWording)) { throw "floor-only correction displaced the authoritative co-op method" }
    $passColonWording = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "TEST METHOD (solo)`n1. Exercise the control.`n2. Repeat it.`n**PASS:** the replacement path remains bounded." })
    }
    if (-not (Test-HasMethodAndExpected $passColonWording)) { throw "PASS-colon expected-result wording was missed" }
    $templateBodyDiagnostic = [PSCustomObject]@{
        body = "### Diagnostic method (runnable now)`n1. Run the lifecycle checker against the retired-label fixture.`n### Expected result`nThe fixture is rejected."
        comments = @()
    }
    if (-not (Test-HasMethodAndExpected $templateBodyDiagnostic -IncludeBody)) { throw "new diagnostic template body was not accepted as its initial method" }
    if (Test-HasMethodAndExpected $templateBodyDiagnostic) { throw "verify lifecycle incorrectly accepted a body without a current method comment" }
    $staleThenIncomplete = [PSCustomObject]@{
        comments = @(
            [PSCustomObject]@{ body = "TEST METHOD (solo)`n1. Run the old check.`nExpected: old pass." },
            [PSCustomObject]@{ body = "Diagnostic method:`n1. Run the replacement probe; output contract pending." }
        )
    }
    if (Test-HasMethodAndExpected $staleThenIncomplete) { throw "older valid method masked an incomplete current replacement" }
    $soloCannotRepro = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "Test method corrected: a solo host cannot reproduce this reliable queue; use a remote peer. Expected: no crash." })
    }
    if (-not (Test-CommentRequiresCoop $soloCannotRepro)) { throw "negative solo wording hid remote-peer evidence" }
    $soloDoesNotRequireSecond = [PSCustomObject]@{
        comments = @([PSCustomObject]@{ body = "### Verification after deployment`nThis local score-screen defect does not require a second player. Remote-player coverage remains useful. Expected: local outfit persists." })
    }
    if (Test-CommentRequiresCoop $soloDoesNotRequireSecond) { throw "explicit does-not-require-second-player wording was misclassified as co-op" }
    Write-Host "[audit-open-issues -SelfTest] OK"
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI (gh) is required."
}

$json = & gh issue list --repo $Repository --state open --limit 1000 --json number,title,body,labels,comments,url,updatedAt
if ($LASTEXITCODE -ne 0) { throw "gh open issue list failed." }
$issues = @($json | ConvertFrom-Json)
$closedJson = & gh issue list --repo $Repository --state closed --limit 1000 --json number,title,body,labels,comments,url,updatedAt,closedAt,stateReason
if ($LASTEXITCODE -ne 0) { throw "gh closed issue list failed." }
$closedIssues = @($closedJson | ConvertFrom-Json)
$report = Invoke-Audit $issues $closedIssues
$rendered = $report | ConvertTo-Json -Depth 8

if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $OutputPath,
        $rendered + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "[audit-open-issues] wrote $($report.open_issue_count) issues to $OutputPath"
    Write-Host "[audit-open-issues] clean=$($report.clean_issue_count) findings=$($report.open_issue_count - $report.clean_issue_count)"
} else {
    if (-not $MarkdownPath) { Write-Output $rendered }
}

if ($MarkdownPath) {
    $parent = Split-Path -Parent $MarkdownPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    [System.IO.File]::WriteAllText(
        $MarkdownPath,
        (Convert-AuditToMarkdown $report) + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
    Write-Host "[audit-open-issues] wrote contingency register to $MarkdownPath"
}
