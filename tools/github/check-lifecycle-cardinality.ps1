# Blocking tracker guard for the live-test queue doctrine.
# Read-only: one batched `gh issue list` call, never tracker mutation.

[CmdletBinding()]
param(
    [string]$Repository = 'Ensrick/vermintide-2-tweaker',
    [string]$IssuesJsonPath,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tools/verify/lifecycle_method_policy.ps1')

function Get-LifecycleViolations($Issues) {
    $violations = @()
    foreach ($issue in @($Issues)) {
        $decision = Get-VtOpenIssueLifecycleDecision $issue
        if (-not $decision.Valid) {
            $violations += [PSCustomObject][ordered]@{
                number = [int]$issue.number
                title = [string]$issue.title
                labels = @($decision.Labels)
                errors = @($decision.Errors)
            }
        }
    }
    return @($violations)
}

function New-TestCard([string]$Topology = 'Solo', [string]$Steps = '1. Equip Kruber''s Mace in the Keep.', [string]$SoloStatus = '') {
    $soloLine = if ($SoloStatus) { "`n**Solo status:** $SoloStatus" } else { '' }
    return "## CURRENT LIVE TEST`n`n**Build/banner:** v1.2.3-dev, confirm ``[wt:LOAD]```n**Topology:** $Topology$soloLine`n`n$Steps`n`n**Expected:** The selected weapon behaves normally."
}

function Invoke-SelfTest {
    $validSolo = New-TestCard
    $validCoop = New-TestCard -Topology 'Co-op (host and one client)' -SoloStatus 'Passed; remote rendering remains.' -Steps "1. Host equips Kruber's Mace.`n2. The joining player observes it."
    $fixture = @(
        [pscustomobject]@{ number=1; title='waiting'; labels=@(@{name='not-started'}); comments=@() },
        [pscustomobject]@{ number=2; title='solo ready'; labels=@(@{name='verify-fix'}); comments=@(@{body=$validSolo}) },
        [pscustomobject]@{ number=3; title='coop ready'; labels=@(@{name='diagnostics-armed'},@{name='coop-required'}); comments=@(@{body=$validCoop}) },
        [pscustomobject]@{ number=4; title='bare'; labels=@(); comments=@() },
        [pscustomobject]@{ number=5; title='old coop'; labels=@(@{name='verify-fix-coop'}); comments=@(@{body=$validCoop}) },
        [pscustomobject]@{ number=6; title='open fixed'; labels=@(@{name='not-started'},@{name='Fixed'}); comments=@() },
        [pscustomobject]@{ number=7; title='blocked ready'; labels=@(@{name='blocked'},@{name='verify-fix'}); comments=@(@{body=$validSolo}) },
        [pscustomobject]@{ number=8; title='blocked waiting'; labels=@(@{name='blocked'},@{name='not-started'}); comments=@() },
        [pscustomobject]@{ number=9; title='coop skipped solo'; labels=@(@{name='verify-fix'},@{name='coop-required'}); comments=@(@{body=(New-TestCard -Topology 'Co-op')}) },
        [pscustomobject]@{ number=10; title='internal key'; labels=@(@{name='diagnostics-armed'}); comments=@(@{body=(New-TestCard -Steps '1. Equip em_mace.')}) },
        [pscustomobject]@{ number=11; title='stale older valid'; labels=@(@{name='verify-fix'}); comments=@(@{body=$validSolo},@{body="## CURRENT LIVE TEST`n**Topology:** Solo`n1. Equip Kruber's Mace.`n**Expected:** Works."}) },
        [pscustomobject]@{ number=12; title='coop nonready'; labels=@(@{name='not-started'},@{name='coop-required'}); comments=@() },
        [pscustomobject]@{ number=13; title='timestamp newest wins'; labels=@(@{name='verify-fix'}); comments=@(
            @{body="## CURRENT LIVE TEST`n**Topology:** Solo`n1. Equip Kruber's Mace.`n**Expected:** Works."; createdAt='2026-07-22T00:00:00Z'},
            @{body=$validSolo; createdAt='2026-07-21T00:00:00Z'}
        ) }
    )
    $violations = @(Get-LifecycleViolations $fixture)
    $bad = @($violations.number | Sort-Object)
    if (($bad -join ',') -ne '4,5,6,7,9,10,11,12,13') { throw "unexpected violations: $($bad -join ',')" }
    foreach ($ok in 1,2,3,8) {
        if ($bad -contains $ok) { throw "valid fixture #$ok rejected" }
    }
    $coop = @($violations | Where-Object number -eq 9)[0]
    if ($coop.errors -notcontains 'live-card-coop-before-solo-passed-or-exhausted') { throw 'solo-first co-op gate missing' }
    $internal = @($violations | Where-Object number -eq 10)[0]
    if ($internal.errors -notcontains 'live-card-internal-key-in-player-steps') { throw 'internal key gate missing' }
    Write-Host '[check-lifecycle-cardinality -SelfTest] OK'
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }

if ($IssuesJsonPath) {
    $json = Get-Content -LiteralPath $IssuesJsonPath -Raw
}
else {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is required.' }
    $json = & gh issue list --repo $Repository --state open --limit 1000 --json number,title,labels,comments
    if ($LASTEXITCODE -ne 0) { throw "gh open issue list failed (exit $LASTEXITCODE)." }
}

$issues = @($json | ConvertFrom-Json)
$violations = @(Get-LifecycleViolations $issues)
if ($violations.Count -eq 0) {
    Write-Host "[check-lifecycle-cardinality] OK: all $($issues.Count) open issues satisfy lifecycle and live-test queue doctrine."
    exit 0
}

Write-Host "[check-lifecycle-cardinality] FAIL: $($violations.Count) open issue(s) violate tracker doctrine:"
foreach ($violation in $violations) {
    $message = "issue #$($violation.number) [$($violation.labels -join ', ')] - $($violation.errors -join ', ') - '$($violation.title)'"
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::error::$message" }
    Write-Host "  - $message"
}
Write-Host '[check-lifecycle-cardinality] Required: exactly one of not-started/diagnostics-armed/verify-fix. Ready states require the newest exact CURRENT LIVE TEST card. Fixed and verify-fix-coop are invalid while open.'
exit 1
