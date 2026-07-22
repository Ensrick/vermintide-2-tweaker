# Static CI policy guard for issue #540.
# ASCII-only for Windows PowerShell 5.1 parsing.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot ".." }

function Test-CiContract {
    param(
        [string]$Workflow,
        [string]$TrustedWorkflow,
        [string]$AutoCloseAuthWorkflow,
        [string]$AutoCloseAuditWorkflow,
        [string]$ProtectionTool
    )
    $errors = @()

    if ($Workflow -notmatch '(?m)^permissions:\s*\r?$' -or $Workflow -notmatch '(?m)^\s{2}contents:\s*read\s*\r?$') {
        $errors += "workflow must declare least-privilege permissions: contents: read"
    }
    if ($Workflow -notmatch '(?m)^\s{2}issues:\s*read\s*\r?$') {
        $errors += "trusted promotion audit requires read-only issue timeline and comment metadata"
    }
    if ($Workflow -notmatch '(?m)^\s{2}pull-requests:\s*read\s*\r?$') {
        $errors += "trusted promotion audit requires read-only pull-request metadata"
    }
    if ($Workflow -notmatch '(?m)^concurrency:\s*\r?$' -or $Workflow -notmatch '(?m)^\s{2}cancel-in-progress:\s*true\s*\r?$') {
        $errors += "workflow must cancel superseded runs"
    }
    if ($Workflow -notmatch '(?m)^\s{2}push:\s*\r?$' -or $Workflow -notmatch '(?m)^\s{2}pull_request:\s*\r?$' -or $Workflow -notmatch '(?m)^\s{2}workflow_dispatch:\s*\r?$') {
        $errors += "workflow must cover push, pull_request, and manual dispatch"
    }

    # A top-level push path filter silently skips build inputs that the allowlist
    # forgot. Inspect only the push block, ending at the next two-space event.
    $push = [regex]::Match($Workflow, '(?ms)^\s{2}push:\s*\r?\n(?<body>.*?)(?=^\s{2}[A-Za-z_]+:\s*(?:\r?\n|$))')
    if ($push.Success -and $push.Groups['body'].Value -match '(?m)^\s+paths(?:-ignore)?:') {
        $errors += "push path filters are forbidden; CI must cover every repository input"
    }

    $uses = [regex]::Matches($Workflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')
    if ($uses.Count -eq 0) { $errors += "workflow has no pinned actions" }
    foreach ($m in $uses) {
        if ($m.Groups[1].Value -notmatch '@[0-9a-fA-F]{40}$') {
            $errors += "action is not pinned to an immutable 40-character SHA: $($m.Groups[1].Value)"
        }
    }
    if ($Workflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*\r?$') {
        $errors += "checkout credentials must not persist after checkout"
    }
    if ($Workflow -notmatch '(?m)^\s+fetch-depth:\s*0\s*\r?$') {
        $errors += "full history is required for diff-aware checks"
    }
    if ($Workflow -notmatch '(?m)^\s+timeout-minutes:\s*\d+\s*\r?$') {
        $errors += "job timeout is required"
    }
    if ($Workflow -notmatch '(?m)^\s+-?\s*shell:\s*powershell\s*\r?$' -or
            $Workflow -notmatch 'check_promotion\.ps1\s+-SelfTest' -or
            $Workflow -notmatch 'tools/ship/ship\.ps1\s+-SelfTest' -or
            $Workflow -notmatch 'check_ps51_compatibility\.ps1\s+-SelfTest') {
        $errors += "promised Windows PowerShell 5.1 release surfaces need CI self-tests"
    }
    if ($Workflow -notmatch 'check_promotion_authorization\.ps1\s+-WriteGitHubEnv' -or
            $Workflow -notmatch "if:\s*github\.event_name\s*==\s*'pull_request'" -or
            $Workflow -notmatch 'if:\s*env\.VT2_PROMOTION\s*==\s*''1''' -or
            $Workflow -notmatch 'check_promotion\.ps1\s+-Mod\s+\$dir') {
        $errors += "stable promotion PRs must pass trusted authorization and exact per-dir promotion QA"
    }
    if ($Workflow -notmatch 'check_pr_autoclose\.ps1') {
        $errors += "ordinary pull-request QA must run the auto-close keyword guard"
    }
    if ($TrustedWorkflow -notmatch '(?m)^\s{2}pull_request_target:\s*\r?$' -or
            $TrustedWorkflow -notmatch '(?m)^\s{2}stable-promotion-authorization:\s*\r?$' -or
            $TrustedWorkflow -notmatch 'check_promotion_authorization\.ps1' -or
            $TrustedWorkflow -match 'github\.event\.pull_request\.head' -or
            $TrustedWorkflow -notmatch 'ref:\s*\$\{\{\s*github\.event\.repository\.default_branch\s*\}\}') {
        $errors += "promotion authorization must run from a base-owned pull_request_target workflow that never checks out PR code"
    }
    foreach ($eventType in @('opened', 'synchronize', 'reopened', 'labeled', 'unlabeled')) {
        if ($TrustedWorkflow -notmatch "(?m)^\s+types:\s*\[[^\]]*\b${eventType}\b") {
            $errors += "trusted promotion workflow must react to ${eventType}"
        }
    }
    if ($TrustedWorkflow -notmatch '(?m)^concurrency:\s*\r?$' -or
            $TrustedWorkflow -notmatch '(?m)^\s{2}cancel-in-progress:\s*true\s*\r?$' -or
            $TrustedWorkflow -notmatch '(?m)^\s{4}timeout-minutes:\s*\d+\s*\r?$') {
        $errors += "trusted promotion workflow requires cancellation and a job timeout"
    }
    foreach ($permission in @('contents', 'issues', 'pull-requests')) {
        if ($TrustedWorkflow -notmatch "(?m)^\s{2}${permission}:\s*read\s*\r?$") {
            $errors += "trusted promotion workflow requires read-only ${permission} permission"
        }
    }
    foreach ($match in [regex]::Matches($TrustedWorkflow, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')) {
        if ($match.Groups[1].Value -notmatch '@[0-9a-fA-F]{40}$') {
            $errors += "trusted promotion action is not pinned: $($match.Groups[1].Value)"
        }
    }
    if ($TrustedWorkflow -notmatch '(?m)^\s+persist-credentials:\s*false\s*\r?$') {
        $errors += "trusted promotion checkout credentials must not persist"
    }

    if ($AutoCloseAuthWorkflow -notmatch '(?m)^\s{2}pull_request_target:\s*\r?$' -or
            $AutoCloseAuthWorkflow -notmatch '(?m)^\s+types:\s*\[[^\]]*opened[^\]]*edited[^\]]*synchronize[^\]]*reopened[^\]]*\]' -or
            $AutoCloseAuthWorkflow -notmatch '(?m)^\s{2}issues:\s*read\s*\r?$' -or
            $AutoCloseAuthWorkflow -notmatch '(?m)^\s{2}pr-autoclose-authorization:\s*\r?$' -or
            $AutoCloseAuthWorkflow -notmatch 'check_pr_autoclose\.ps1' -or
            $AutoCloseAuthWorkflow -match 'github\.event\.pull_request\.head' -or
            $AutoCloseAuthWorkflow -notmatch 'ref:\s*\$\{\{\s*github\.event\.repository\.default_branch\s*\}\}') {
        $errors += "pre-merge auto-close authorization must be a read-only base-owned pull_request_target status"
    }
    foreach ($permission in @('contents', 'issues', 'pull-requests')) {
        if ($AutoCloseAuthWorkflow -notmatch "(?m)^\s{2}${permission}:\s*read\s*\r?$") {
            $errors += "pre-merge auto-close authorization requires read-only ${permission} permission"
        }
    }

    if ($AutoCloseAuditWorkflow -notmatch '(?m)^\s{2}pull_request_target:\s*\r?$' -or
            $AutoCloseAuditWorkflow -notmatch '(?m)^\s+types:\s*\[closed\]\s*\r?$' -or
            $AutoCloseAuditWorkflow -notmatch '(?m)^\s{2}issues:\s*write\s*\r?$' -or
            $AutoCloseAuditWorkflow -notmatch 'check_pr_autoclose\.ps1\s+-PostMergeAudit\s+-Repair' -or
            $AutoCloseAuditWorkflow -match 'github\.event\.pull_request\.head' -or
            $AutoCloseAuditWorkflow -notmatch 'ref:\s*\$\{\{\s*github\.event\.repository\.default_branch\s*\}\}') {
        $errors += "post-merge auto-close recovery must run trusted default-branch policy and limit writes to issue recovery"
    }
    foreach ($permission in @('contents', 'pull-requests')) {
        if ($AutoCloseAuditWorkflow -notmatch "(?m)^\s{2}${permission}:\s*read\s*\r?$") {
            $errors += "post-merge auto-close recovery requires ${permission}: read"
        }
    }
    foreach ($pair in @(
        @{ Name = 'pre-merge auto-close'; Text = $AutoCloseAuthWorkflow },
        @{ Name = 'post-merge auto-close'; Text = $AutoCloseAuditWorkflow }
    )) {
        foreach ($match in [regex]::Matches($pair.Text, '(?m)^\s*-?\s*uses:\s*([^\s#]+)')) {
            if ($match.Groups[1].Value -notmatch '@[0-9a-fA-F]{40}$') {
                $errors += "$($pair.Name) action is not pinned: $($match.Groups[1].Value)"
            }
        }
    }

    if ($ProtectionTool -notmatch 'enforce_admins\s*=\s*\$true' -or
            $ProtectionTool -notmatch 'allow_force_pushes\s*=\s*\$false' -or
            $ProtectionTool -notmatch 'allow_deletions\s*=\s*\$false') {
        $errors += "branch protection tool must cover admins, force pushes, and deletion"
    }
    if ($ProtectionTool -notmatch 'Test-GreenConclusion' -or $ProtectionTool -notmatch 'Refusing branch protection while latest QA') {
        $errors += "branch protection tool must fail closed while QA is red"
    }
    if ($ProtectionTool -notmatch 'stable-promotion-authorization') {
        $errors += "branch protection must require the base-owned promotion authorization status"
    }
    if ($ProtectionTool -notmatch 'pr-autoclose-authorization') {
        $errors += "branch protection must require the base-owned PR auto-close authorization status"
    }
    return $errors
}

function Invoke-SelfTest {
    $goodWorkflow = @'
on:
  push:
    branches: [master]
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
  issues: read
  pull-requests: read
concurrency:
  group: qa
  cancel-in-progress: true
jobs:
  qa-gate:
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@1234567890123456789012345678901234567890
        with:
          fetch-depth: 0
          persist-credentials: false
      - if: github.event_name == 'pull_request'
        shell: pwsh
        run: ./qa/check_promotion_authorization.ps1 -WriteGitHubEnv
      - if: env.VT2_PROMOTION == '1'
        shell: pwsh
        run: ./qa/check_promotion.ps1 -Mod $dir
      - shell: powershell
        run: ./qa/check_promotion.ps1 -SelfTest
      - shell: powershell
        run: ./tools/ship/ship.ps1 -SelfTest
      - shell: powershell
        run: ./qa/check_ps51_compatibility.ps1 -SelfTest
      - shell: pwsh
        run: ./qa/check_pr_autoclose.ps1
'@
    $goodTrustedWorkflow = @'
on:
  pull_request_target:
    types: [opened, synchronize, reopened, labeled, unlabeled]
permissions:
  contents: read
  issues: read
  pull-requests: read
concurrency:
  group: stable-promotion-authorization
  cancel-in-progress: true
jobs:
  stable-promotion-authorization:
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@1234567890123456789012345678901234567890
        with:
          ref: ${{ github.event.repository.default_branch }}
          persist-credentials: false
      - run: ./qa/check_promotion_authorization.ps1
'@
    $goodAutoCloseAuthWorkflow = @'
on:
  pull_request_target:
    types: [opened, edited, synchronize, reopened]
permissions:
  contents: read
  issues: read
  pull-requests: read
jobs:
  pr-autoclose-authorization:
    steps:
      - uses: actions/checkout@1234567890123456789012345678901234567890
        with:
          ref: ${{ github.event.repository.default_branch }}
          persist-credentials: false
      - run: ./qa/check_pr_autoclose.ps1
'@
    $goodAutoCloseAuditWorkflow = @'
on:
  pull_request_target:
    types: [closed]
permissions:
  contents: read
  issues: write
  pull-requests: read
jobs:
  audit:
    steps:
      - uses: actions/checkout@1234567890123456789012345678901234567890
        with:
          ref: ${{ github.event.repository.default_branch }}
          persist-credentials: false
      - run: ./qa/check_pr_autoclose.ps1 -PostMergeAudit -Repair
'@
    $goodTool = 'enforce_admins = $true; allow_force_pushes = $false; allow_deletions = $false; Test-GreenConclusion; Refusing branch protection while latest QA'
    $goodTool += '; stable-promotion-authorization; pr-autoclose-authorization'
    $good = @(Test-CiContract $goodWorkflow $goodTrustedWorkflow $goodAutoCloseAuthWorkflow $goodAutoCloseAuditWorkflow $goodTool)
    if ($good.Count -ne 0) { throw ("valid CI contract was rejected: " + ($good -join '; ')) }

    $badWorkflow = $goodWorkflow -replace '@1234567890123456789012345678901234567890', '@v4'
    $badWorkflow = $badWorkflow -replace '    branches: \[master\]', "    branches: [master]`n    paths:`n      - '**/*.lua'"
    $badTool = 'enforce_admins = $false; allow_force_pushes = $true; allow_deletions = $true'
    $badTrustedWorkflow = $goodTrustedWorkflow -replace 'repository\.default_branch', 'pull_request.head.sha'
    $badAutoCloseAuthWorkflow = $goodAutoCloseAuthWorkflow -replace 'repository\.default_branch', 'pull_request.head.sha'
    $badAutoCloseAuditWorkflow = $goodAutoCloseAuditWorkflow -replace 'repository\.default_branch', 'pull_request.head.sha'
    $bad = @(Test-CiContract $badWorkflow $badTrustedWorkflow $badAutoCloseAuthWorkflow $badAutoCloseAuditWorkflow $badTool)
    if ($bad.Count -lt 4) { throw "planted CI/protection failures were not detected" }
    if (-not ($bad -match 'immutable')) { throw "mutable action pin was not detected" }
    if (-not ($bad -match 'path filters')) { throw "fragile push path filter was not detected" }
    Write-Host "[check_ci_hardening -SelfTest] OK"
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path $RepoRoot).Path
$workflowPath = Join-Path $root '.github\workflows\qa.yml'
$trustedWorkflowPath = Join-Path $root '.github\workflows\stable-promotion-authorization.yml'
$autoCloseAuthWorkflowPath = Join-Path $root '.github\workflows\pr-autoclose-authorization.yml'
$autoCloseAuditWorkflowPath = Join-Path $root '.github\workflows\pr-autoclose-audit.yml'
$protectionPath = Join-Path $root 'tools\github\protect-master.ps1'
if (-not (Test-Path $workflowPath) -or -not (Test-Path $trustedWorkflowPath) -or
        -not (Test-Path $autoCloseAuthWorkflowPath) -or -not (Test-Path $autoCloseAuditWorkflowPath) -or
        -not (Test-Path $protectionPath)) {
    Write-Host "[check_ci_hardening] ERROR - QA/trusted workflows or protection tool missing." -ForegroundColor Red
    exit 2
}

$workflow = [System.IO.File]::ReadAllText($workflowPath, [System.Text.Encoding]::UTF8)
$trustedWorkflow = [System.IO.File]::ReadAllText($trustedWorkflowPath, [System.Text.Encoding]::UTF8)
$autoCloseAuthWorkflow = [System.IO.File]::ReadAllText($autoCloseAuthWorkflowPath, [System.Text.Encoding]::UTF8)
$autoCloseAuditWorkflow = [System.IO.File]::ReadAllText($autoCloseAuditWorkflowPath, [System.Text.Encoding]::UTF8)
$protection = [System.IO.File]::ReadAllText($protectionPath, [System.Text.Encoding]::UTF8)
$errors = @(Test-CiContract $workflow $trustedWorkflow $autoCloseAuthWorkflow $autoCloseAuditWorkflow $protection)
if ($errors.Count -gt 0) {
    Write-Host "[check_ci_hardening] ERRORS:" -ForegroundColor Red
    foreach ($errorMessage in $errors) { Write-Host "  X $errorMessage" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) { Write-Host "[check_ci_hardening] OK - CI workflow and protected-branch policy are hardened." -ForegroundColor Green }
exit 0
