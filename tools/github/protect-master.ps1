# Applies the repository's canonical master branch protection policy.
# ASCII-only so Windows PowerShell 5.1 parses this file without a UTF-8 BOM.

[CmdletBinding()]
param(
    [string]$Repository = "Ensrick/vermintide-2-tweaker",
    [string]$Branch = "master",
    [string[]]$RequiredContexts = @("qa-gate", "stable-promotion-authorization", "pr-autoclose-authorization"),
    [switch]$Apply,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"

function Fail {
    param([string]$Message)
    Write-Host "PROTECTION NOT APPLIED: $Message" -ForegroundColor Red
    exit 2
}

function New-ProtectionPayload {
    param([string[]]$Contexts)
    # The legacy contexts array carries no app binding, which left
    # stable-promotion-authorization pinned to app_id null - satisfiable by ANY
    # token that can POST a commit status under that context name (#540).
    # The checks form binds every required context to GitHub Actions (15368).
    $checks = @()
    foreach ($context in $Contexts) {
        $checks += [ordered]@{ context = $context; app_id = 15368 }
    }
    return [ordered]@{
        required_status_checks = [ordered]@{
            strict = $true
            checks = @($checks)
        }
        enforce_admins = $true
        required_pull_request_reviews = $null
        restrictions = $null
        required_linear_history = $false
        allow_force_pushes = $false
        allow_deletions = $false
        block_creations = $false
        required_conversation_resolution = $true
        lock_branch = $false
        allow_fork_syncing = $true
    }
}

function Test-GreenConclusion {
    param([string]$Conclusion)
    return $Conclusion -eq "success"
}

function Invoke-GhCapture {
    param([string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & gh @Arguments 2>$null
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previous
    }
    return @{ Code = $code; Output = ($output -join "`n") }
}

function Invoke-SelfTest {
    $payload = New-ProtectionPayload -Contexts @("qa-gate", "stable-promotion-authorization", "pr-autoclose-authorization")
    if (-not $payload.required_status_checks.strict) { throw "status checks must require an up-to-date branch" }
    $checks = @($payload.required_status_checks.checks)
    if ($checks.Count -ne 3 -or
            $checks[0].context -ne "qa-gate" -or
            $checks[1].context -ne "stable-promotion-authorization" -or
            $checks[2].context -ne "pr-autoclose-authorization") {
        throw "required QA/authorization contexts drift"
    }
    foreach ($check in $checks) {
        if ($check.app_id -ne 15368) { throw "required check '$($check.context)' is not bound to GitHub Actions (app_id 15368)" }
    }
    if (-not $payload.enforce_admins) { throw "administrators must not bypass protection" }
    if ($payload.allow_force_pushes -or $payload.allow_deletions) { throw "force push/deletion must stay disabled" }
    if (-not $payload.required_conversation_resolution) { throw "PR conversations must resolve" }
    if (-not (Test-GreenConclusion "success")) { throw "green QA was rejected" }
    foreach ($bad in @("failure", "cancelled", "skipped", "", $null)) {
        if (Test-GreenConclusion $bad) { throw "non-green QA was accepted: $bad" }
    }
    Write-Host "[protect-master -SelfTest] OK"
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail "GitHub CLI (gh) is required."
}

$run = Invoke-GhCapture @("run", "list", "--repo", $Repository, "--workflow", "QA", "--branch", $Branch, "--status", "completed", "--limit", "1", "--json", "conclusion,headSha,url")
if ($run.Code -ne 0 -or -not $run.Output) {
    Fail "Could not read the latest completed QA run for $Repository/$Branch."
}

try { $latest = @($run.Output | ConvertFrom-Json)[0] } catch {
    Fail "Could not parse the latest QA run: $_"
}
if (-not $latest -or -not (Test-GreenConclusion $latest.conclusion)) {
    $state = if ($latest) { $latest.conclusion } else { "missing" }
    Fail "Refusing branch protection while latest QA is '$state'. Restore green CI first."
}

$payload = New-ProtectionPayload -Contexts $RequiredContexts
$json = $payload | ConvertTo-Json -Depth 6
if (-not $Apply) {
    Write-Host "DRY RUN - latest QA is green; protection payload for $Repository/${Branch}:"
    Write-Host $json
    Write-Host "Re-run with -Apply to update GitHub."
    exit 0
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-branch-protection-" + [guid]::NewGuid().ToString("N") + ".json")
try {
    [System.IO.File]::WriteAllText($temp, $json, (New-Object System.Text.UTF8Encoding($false)))
    $result = Invoke-GhCapture @("api", "--method", "PUT", "-H", "Accept: application/vnd.github+json", "-H", "X-GitHub-Api-Version: 2022-11-28", "repos/$Repository/branches/$Branch/protection", "--input", $temp)
    if ($result.Code -ne 0) {
        Fail "GitHub rejected the branch protection update."
    }
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
}

Write-Host "Applied protected-branch policy to $Repository/$Branch (required contexts: $($RequiredContexts -join ', '))."
exit 0
