# check-lifecycle-cardinality.ps1 - CI guard for tracker lifecycle integrity.
#
# Issue #750: an out-of-repo reconciliation sweep stripped lifecycle labels from
# open issues (each label removed alone - no paired add, no comment), leaving 10
# open issues bare. This guard makes that state block the qa-gate: it FAILS
# (exit 1) whenever any OPEN issue carries a lifecycle-label cardinality != 1
# or mixes a retired open lifecycle label with its one canonical lifecycle.
#
# Doctrine: PROJECT_STANDARDS.md section 11 "Labels" + "Tracker lifecycle
# discipline". The three lifecycle labels below must stay in lockstep with
# $LifecycleLabels in tools/github/audit-open-issues.ps1 and tools/ship/ship.ps1
# (the taxonomy is closed: CLAUDE.md NON-NEGOTIABLE #13 forbids new status
# labels, so this list should never drift).
#
# HARD FAIL by deliberate design. The advisory qa/check_issue_status_labels.ps1
# pass-3 sweep already warned on bare issues and did not stop the #750 strip
# sweep; a blocking CI step is the fix. There is no skip label or soft mode.
#
# Read-only: exactly ONE `gh issue list` call (never per-issue calls), never
# edits labels, needs only issues:read (works with the default GITHUB_TOKEN).
#
# Exit codes:
#   0 = every open issue carries exactly one canonical lifecycle and no retired one.
#   1 = one or more violations (offending numbers + labels are printed).
#   throws = gh unavailable or the list call failed (CI step fails; a transient
#            GitHub API error is resolved by re-running the job).

[CmdletBinding()]
param(
    [string]$Repository = "Ensrick/vermintide-2-tweaker",
    # Path to a JSON array of issue rows ({number,title,labels:[{name}]}) for
    # offline fail-path testing. When set, gh is never called and no live issue
    # is read or mutated.
    [string]$IssuesJsonPath,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

$LifecycleLabels = @(
    "verify-fix",
    "verify-fix-coop",
    "diagnostics-armed"
)
$RetiredLifecycleLabels = @("not-started", "Fixed")

function Get-LifecycleViolations($Issues) {
    $violations = @()
    foreach ($issue in @($Issues)) {
        $labels = @($issue.labels | ForEach-Object { [string]$_.name })
        $lifecycle = @($labels | Where-Object { $LifecycleLabels -contains $_ })
        $retired = @($labels | Where-Object { $RetiredLifecycleLabels -contains $_ })
        if ($lifecycle.Count -ne 1 -or $retired.Count -gt 0) {
            $violations += [PSCustomObject][ordered]@{
                number = [int]$issue.number
                title = [string]$issue.title
                lifecycle_count = $lifecycle.Count
                lifecycle_labels = @($lifecycle)
                retired_labels = @($retired)
            }
        }
    }
    return @($violations)
}

function Invoke-SelfTest {
    $fixture = @(
        [PSCustomObject]@{ number = 1; title = "clean solo verify"; labels = @(@{ name = "bug" }, @{ name = "verify-fix" }, @{ name = "wt" }) },
        [PSCustomObject]@{ number = 2; title = "bare after strip sweep"; labels = @(@{ name = "bug" }, @{ name = "2-moderate" }) },
        [PSCustomObject]@{ number = 3; title = "competing lifecycle pair"; labels = @(@{ name = "verify-fix" }, @{ name = "verify-fix-coop" }) },
        [PSCustomObject]@{ number = 4; title = "clean coop verify"; labels = @(@{ name = "verify-fix-coop" }) },
        [PSCustomObject]@{ number = 5; title = "no labels at all"; labels = @() },
        [PSCustomObject]@{ number = 6; title = "retired untouched state"; labels = @(@{ name = "not-started" }, @{ name = "tooling" }) },
        [PSCustomObject]@{ number = 7; title = "retired verified state"; labels = @(@{ name = "Fixed" }, @{ name = "documentation" }) },
        [PSCustomObject]@{ number = 8; title = "clean repository-only verify"; labels = @(@{ name = "verify-fix" }, @{ name = "tooling" }) },
        [PSCustomObject]@{ number = 9; title = "canonical plus retired"; labels = @(@{ name = "diagnostics-armed" }, @{ name = "Fixed" }) }
    )
    $violations = @(Get-LifecycleViolations $fixture)
    if ($violations.Count -ne 6) { throw "expected 6 violations, got $($violations.Count)" }
    if (@($violations | Where-Object { $_.number -eq 2 -and $_.lifecycle_count -eq 0 }).Count -ne 1) { throw "bare issue not flagged" }
    if (@($violations | Where-Object { $_.number -eq 3 -and $_.lifecycle_count -eq 2 }).Count -ne 1) { throw "competing lifecycle pair not flagged" }
    if (@($violations | Where-Object { $_.number -eq 5 }).Count -ne 1) { throw "label-less issue not flagged" }
    if (@($violations | Where-Object { $_.number -eq 6 -and $_.lifecycle_count -eq 0 }).Count -ne 1) { throw "retired not-started was accepted" }
    if (@($violations | Where-Object { $_.number -eq 7 -and $_.lifecycle_count -eq 0 }).Count -ne 1) { throw "retired Fixed was accepted" }
    if (@($violations | Where-Object { $_.number -eq 9 -and $_.lifecycle_count -eq 1 -and ($_.retired_labels -contains 'Fixed') }).Count -ne 1) { throw "canonical plus retired label was accepted" }
    if (@($violations | Where-Object { $_.number -in @(1, 4, 8) }).Count -ne 0) { throw "clean issue was misflagged" }
    $double = @($violations | Where-Object { $_.number -eq 3 })[0]
    if (($double.lifecycle_labels -join ",") -ne "verify-fix,verify-fix-coop") { throw "violation must name the competing labels" }
    Write-Host "[check-lifecycle-cardinality -SelfTest] OK"
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

if ($IssuesJsonPath) {
    $json = Get-Content -LiteralPath $IssuesJsonPath -Raw
} else {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) is required."
    }
    # ONE list call covering every open issue - never per-issue API calls.
    $json = & gh issue list --repo $Repository --state open --limit 1000 --json number,title,labels
    if ($LASTEXITCODE -ne 0) { throw "gh open issue list failed (exit $LASTEXITCODE)." }
}

$issues = @($json | ConvertFrom-Json)
$violations = @(Get-LifecycleViolations $issues)

if ($violations.Count -eq 0) {
    Write-Host "[check-lifecycle-cardinality] OK: all $(@($issues).Count) open issues carry exactly one canonical lifecycle label and no retired lifecycle."
    exit 0
}

$isActions = $env:GITHUB_ACTIONS -eq "true"
Write-Host "[check-lifecycle-cardinality] FAIL: $($violations.Count) open issue(s) violate lifecycle integrity (exactly 1 of: $($LifecycleLabels -join ', '); none of: $($RetiredLifecycleLabels -join ', ')):"
foreach ($violation in $violations) {
    $labelText = if ($violation.lifecycle_count -eq 0) { "NO lifecycle label" } else { $violation.lifecycle_labels -join " + " }
    if ($violation.retired_labels.Count -gt 0) { $labelText += "; retired: $($violation.retired_labels -join ' + ')" }
    $message = "issue #$($violation.number) has $labelText - `"$($violation.title)`""
    if ($isActions) { Write-Host "::error::Lifecycle cardinality: $message" }
    Write-Host "  - $message"
}
Write-Host "[check-lifecycle-cardinality] Fix: route every lifecycle edit through tools/ship/ship.ps1 Get-LifecycleEditPlan (add the target + remove competing labels in ONE gh issue edit). See PROJECT_STANDARDS.md section 11 'Tracker lifecycle discipline' and issue #750."
exit 1
