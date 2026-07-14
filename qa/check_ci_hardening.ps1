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
    param([string]$Workflow, [string]$ProtectionTool)
    $errors = @()

    if ($Workflow -notmatch '(?m)^permissions:\s*\r?$' -or $Workflow -notmatch '(?m)^\s{2}contents:\s*read\s*\r?$') {
        $errors += "workflow must declare least-privilege permissions: contents: read"
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
            $Workflow -notmatch 'tools/ship/ship\.ps1\s+-SelfTest') {
        $errors += "promised Windows PowerShell 5.1 release surfaces need CI self-tests"
    }

    if ($ProtectionTool -notmatch 'enforce_admins\s*=\s*\$true' -or
            $ProtectionTool -notmatch 'allow_force_pushes\s*=\s*\$false' -or
            $ProtectionTool -notmatch 'allow_deletions\s*=\s*\$false') {
        $errors += "branch protection tool must cover admins, force pushes, and deletion"
    }
    if ($ProtectionTool -notmatch 'Test-GreenConclusion' -or $ProtectionTool -notmatch 'Refusing branch protection while latest QA') {
        $errors += "branch protection tool must fail closed while QA is red"
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
      - shell: powershell
        run: ./qa/check_promotion.ps1 -SelfTest
      - shell: powershell
        run: ./tools/ship/ship.ps1 -SelfTest
'@
    $goodTool = 'enforce_admins = $true; allow_force_pushes = $false; allow_deletions = $false; Test-GreenConclusion; Refusing branch protection while latest QA'
    $good = @(Test-CiContract $goodWorkflow $goodTool)
    if ($good.Count -ne 0) { throw ("valid CI contract was rejected: " + ($good -join '; ')) }

    $badWorkflow = $goodWorkflow -replace '@1234567890123456789012345678901234567890', '@v4'
    $badWorkflow = $badWorkflow -replace '    branches: \[master\]', "    branches: [master]`n    paths:`n      - '**/*.lua'"
    $badTool = 'enforce_admins = $false; allow_force_pushes = $true; allow_deletions = $true'
    $bad = @(Test-CiContract $badWorkflow $badTool)
    if ($bad.Count -lt 4) { throw "planted CI/protection failures were not detected" }
    if (-not ($bad -match 'immutable')) { throw "mutable action pin was not detected" }
    if (-not ($bad -match 'path filters')) { throw "fragile push path filter was not detected" }
    Write-Host "[check_ci_hardening -SelfTest] OK"
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path $RepoRoot).Path
$workflowPath = Join-Path $root '.github\workflows\qa.yml'
$protectionPath = Join-Path $root 'tools\github\protect-master.ps1'
if (-not (Test-Path $workflowPath) -or -not (Test-Path $protectionPath)) {
    Write-Host "[check_ci_hardening] ERROR - workflow or protection tool missing." -ForegroundColor Red
    exit 2
}

$workflow = [System.IO.File]::ReadAllText($workflowPath, [System.Text.Encoding]::UTF8)
$protection = [System.IO.File]::ReadAllText($protectionPath, [System.Text.Encoding]::UTF8)
$errors = @(Test-CiContract $workflow $protection)
if ($errors.Count -gt 0) {
    Write-Host "[check_ci_hardening] ERRORS:" -ForegroundColor Red
    foreach ($errorMessage in $errors) { Write-Host "  X $errorMessage" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) { Write-Host "[check_ci_hardening] OK - CI workflow and protected-branch policy are hardened." -ForegroundColor Green }
exit 0
