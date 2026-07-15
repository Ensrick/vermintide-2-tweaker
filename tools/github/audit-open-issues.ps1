# Audits every open GitHub issue against the repository's tracker doctrine.
#
# This is intentionally report-only.  It never edits labels, titles, bodies,
# or comments.  The JSON output is suitable for an _investigating/ snapshot;
# evidence-backed corrections are still made deliberately with gh.

[CmdletBinding()]
param(
    [string]$Repository = "Ensrick/vermintide-2-tweaker",
    [string]$OutputPath,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

$LifecycleLabels = @(
    "not-started",
    "verify-fix",
    "verify-fix-coop",
    "diagnostics-armed",
    "Fixed"
)

$TypeLabels = @("bug", "enhancement", "feature")

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

$ToolingLabels = @("tooling", "documentation")

function Get-LabelNames($Issue) {
    return @($Issue.labels | ForEach-Object { [string]$_.name })
}

function Get-TitleWordCount([string]$Title) {
    if (-not $Title) { return 0 }
    $normalized = $Title -replace '^\[[^]]+\]\s*', ''
    return @($normalized -split '\s+' | Where-Object { $_ }).Count
}

function Test-HasMethodAndExpected($Issue) {
    $comments = @($Issue.comments | ForEach-Object { [string]$_.body })
    foreach ($comment in $comments) {
        $hasMethod = $comment -match '(?i)test method|verification|verify:|steps?:|repro'
        $hasExpected = $comment -match '(?i)expected|must pass|should pass|result:'
        if ($hasMethod -and $hasExpected) { return $true }
    }
    return $false
}

function Get-LatestTestComment($Issue) {
    $comments = @($Issue.comments)
    for ($index = $comments.Count - 1; $index -ge 0; $index--) {
        $body = [string]$comments[$index].body
        if ($body -match '(?i)test method|verification|verify solo|solo diagnostic|needs? 2 players|two-player|host\s*\+\s*client|host and client|expected') {
            return $body
        }
    }
    return ""
}

function Test-CommentRequiresCoop($Issue) {
    # Historical comments often contain superseded test plans.  The newest
    # explicit test/verification comment is authoritative for current scope.
    $text = Get-LatestTestComment $Issue
    if ($text -match '(?i)test method\s*\(?(?:[^\r\n)]{0,40})\bsolo\b|verify solo|solo diagnostic|\b(?:one|1) tester\b') {
        return $false
    }
    return $text -match '(?i)two players|2 players|2\+ players|host\s*\+\s*client|host and client|second player|both peers|remote peer|non-mod peer|co-op verification'
}

function Get-IssueFindings($Issue) {
    $labels = Get-LabelNames $Issue
    $lifecycle = @($labels | Where-Object { $LifecycleLabels -contains $_ })
    $types = @($labels | Where-Object { $TypeLabels -contains $_ })
    $findings = New-Object System.Collections.Generic.List[string]

    if ($lifecycle.Count -ne 1) {
        $findings.Add("lifecycle_count_$($lifecycle.Count)")
    }
    if ($types.Count -ne 1) {
        $findings.Add("type_count_$($types.Count)")
    }
    if (@($labels | Where-Object { $ToolingLabels -contains $_ }).Count -gt 0 -and
        @($lifecycle | Where-Object { $_ -ne "not-started" }).Count -gt 0) {
        $findings.Add("tooling_uses_human_lifecycle")
    }
    if ((Get-TitleWordCount $Issue.title) -gt 8) {
        $findings.Add("title_over_8_words")
    }

    $humanLifecycle = @($lifecycle | Where-Object {
        $_ -in @("verify-fix", "verify-fix-coop", "diagnostics-armed")
    })
    if ($humanLifecycle.Count -gt 0 -and -not (Test-HasMethodAndExpected $Issue)) {
        $findings.Add("missing_test_method_comment")
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
    if (@($labels | Where-Object { $ToolingLabels -contains $_ }).Count -gt 0) {
        return "maintainer-offline"
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
    if ($labels -contains "Fixed") { return "post-fix hardening, regression coverage, then close" }
    if ($labels -contains "verify-fix-coop") { return "two-player in-game verification" }
    if ($labels -contains "verify-fix") { return "solo in-game verification" }
    if ($labels -contains "diagnostics-armed") { return "run documented repro and collect bounded diagnostics" }
    return "scope against source, then implement or arm diagnostics"
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

function Invoke-Audit($Issues) {
    $rows = @()
    foreach ($issue in @($Issues | Sort-Object -Property number)) {
        $findings = @(Get-IssueFindings $issue)
        $lessons = @(Get-ApplicableLessons $issue)
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
            findings = $findings
            clean = ($findings.Count -eq 0)
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
        schema = 2
        generated_utc = [DateTime]::UtcNow.ToString("o")
        repository = $Repository
        open_issue_count = $rows.Count
        clean_issue_count = @($rows | Where-Object { $_.clean }).Count
        finding_counts = $counts
        lesson_counts = $lessonCounts
        note = "Regex lesson matches are a review queue, not proof of root cause or fix status."
        issues = $rows
    }
}

function Invoke-SelfTest {
    $fixture = @(
        [PSCustomObject]@{
            number = 1; title = "Short title"; body = "**Symptom:** x"; url = "u1"
            labels = @(@{ name = "bug" }, @{ name = "verify-fix-coop" })
            comments = @(@{ body = "Test method: host + client. Expected: pass." })
        },
        [PSCustomObject]@{
            number = 2; title = "This title contains far too many words for doctrine"; body = "## Broken\\nBody"; url = "u2"
            labels = @(@{ name = "bug" }, @{ name = "enhancement" })
            comments = @()
        },
        [PSCustomObject]@{
            number = 3; title = "Missing method"; body = "**Symptom:** x"; url = "u3"
            labels = @(@{ name = "feature" }, @{ name = "verify-fix" })
            comments = @(@{ body = "Shipped today." })
        }
    )
    $result = Invoke-Audit $fixture
    if ($result.open_issue_count -ne 3) { throw "fixture count drift" }
    if (-not $result.issues[0].clean) { throw "valid coop issue was rejected" }
    if ($result.issues[1].findings -notcontains "lifecycle_count_0") { throw "missing lifecycle not found" }
    if ($result.issues[1].findings -notcontains "type_count_2") { throw "duplicate type not found" }
    if ($result.issues[1].findings -notcontains "literal_escaped_newline_in_body") { throw "escaped newline not found" }
    if ($result.issues[2].findings -notcontains "missing_test_method_comment") { throw "missing method not found" }
    if ($result.issues[0].applicable_lessons -notcontains "network_peer_parity") { throw "coop lesson not classified" }
    if ($result.issues[0].verification_scope -ne "coop") { throw "coop verification scope drift" }
    if ($result.issues[0].recommended_next_action -ne "two-player in-game verification") { throw "coop action drift" }
    if ($result.issues[1].risk_tier -notin @("low", "moderate", "high", "critical")) { throw "risk classification drift" }
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
if ($LASTEXITCODE -ne 0) { throw "gh issue list failed." }
$issues = @($json | ConvertFrom-Json)
$report = Invoke-Audit $issues
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
    Write-Output $rendered
}
