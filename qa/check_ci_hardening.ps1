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

function Test-IssueLifecycleCheckoutContract {
    param([string]$Workflow)
    $errors = @()

    foreach ($permission in @('contents', 'issues')) {
        if ($Workflow -notmatch "(?m)^\s{2}${permission}:\s*read\s*\r?$") {
            $errors += "issue lifecycle workflow requires ${permission}: read"
        }
    }
    $lines = @($Workflow -split '\r?\n')
    $structuralLines = @($lines)
    $scalarIndent = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()
        $indent = $line.Length - $line.TrimStart().Length
        if ($null -ne $scalarIndent) {
            if ($trimmed.Length -eq 0 -or $indent -gt $scalarIndent) {
                $structuralLines[$i] = ''
                continue
            }
            $scalarIndent = $null
        }
        if ($line -match '^(?<indent>\s*)(?:-\s+)?(?<key>[A-Za-z0-9_-]+):\s*[|>]' -and
                $matches['key'] -cne 'sparse-checkout') {
            $scalarIndent = $matches['indent'].Length
        }
    }

    $quotedStructuralKeys = @()
    for ($i = 0; $i -lt $structuralLines.Count; $i++) {
        $line = $structuralLines[$i]
        if ($line -match '^\s*(?:-\s*)?(?:"(?:[^"\\]|\\.)*"|''(?:[^'']|'''')*'')\s*:') {
            $quotedStructuralKeys += $i
        }
    }
    if ($quotedStructuralKeys.Count -gt 0) {
        $errors += "issue lifecycle workflow structural mapping keys must be unquoted"
    }

    $actionUses = @()
    $invalidActionKey = $false
    foreach ($line in $structuralLines) {
        if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
        if ($line -notmatch '^\s*(?:-\s*)?(?<key>[A-Za-z0-9_-]+|"[^"]+"|''[^'']+''):\s*(?<value>.*?)\s*$') {
            continue
        }
        $rawKey = $matches['key']
        $semanticKey = $rawKey
        if (($semanticKey.StartsWith('"') -and $semanticKey.EndsWith('"')) -or
                ($semanticKey.StartsWith("'") -and $semanticKey.EndsWith("'"))) {
            $semanticKey = $semanticKey.Substring(1, $semanticKey.Length - 2)
        }
        if ($semanticKey -ine 'uses') { continue }
        if ($rawKey -cne 'uses') {
            $invalidActionKey = $true
            continue
        }
        $value = ($matches['value'] -replace '\s+#.*$', '').Trim()
        $actionUses += $value
        if ($value -notmatch '@[0-9a-fA-F]{40}$') {
            $errors += "issue lifecycle action is not pinned: $value"
        }
    }
    if ($invalidActionKey) {
        $errors += "issue lifecycle action keys must use the exact unquoted lowercase uses spelling"
    }
    $checkoutUses = @($actionUses | Where-Object { $_ -match '^actions/checkout@' })
    if ($checkoutUses.Count -ne 1) {
        $errors += "issue lifecycle workflow requires exactly one checkout action"
    }

    $jobsIndexes = @()
    for ($i = 0; $i -lt $structuralLines.Count; $i++) {
        if ($structuralLines[$i] -ceq 'jobs:') { $jobsIndexes += $i }
    }
    $jobsStart = -1
    $jobsEnd = $structuralLines.Count
    if ($jobsIndexes.Count -ne 1) {
        $errors += "issue lifecycle workflow requires one top-level jobs mapping"
    } else {
        $jobsStart = [int]$jobsIndexes[0]
        for ($i = $jobsStart + 1; $i -lt $structuralLines.Count; $i++) {
            $line = $structuralLines[$i]
            if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -eq 0) { $jobsEnd = $i; break }
        }
    }

    $trackerIndexes = @()
    $directJobKeys = @()
    $invalidDirectJobKey = $false
    if ($jobsStart -ge 0) {
        for ($i = $jobsStart + 1; $i -lt $jobsEnd; $i++) {
            $line = $structuralLines[$i]
            if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -ne 2) { continue }
            if ($line -match '^  (?<key>[A-Za-z0-9_-]+):\s*$') {
                $directJobKeys += $matches['key']
                if ($matches['key'] -ceq 'tracker-guard') { $trackerIndexes += $i }
            } else {
                $invalidDirectJobKey = $true
            }
        }
    }
    if ($invalidDirectJobKey -or $directJobKeys.Count -ne 1 -or
            $directJobKeys[0] -cne 'tracker-guard') {
        $errors += "issue lifecycle jobs mapping must contain exactly the unquoted tracker-guard job"
    }
    $trackerStart = -1
    $trackerEnd = $jobsEnd
    if ($trackerIndexes.Count -ne 1) {
        $errors += "issue lifecycle workflow requires one direct jobs.tracker-guard mapping"
    } else {
        $trackerStart = [int]$trackerIndexes[0]
        for ($i = $trackerStart + 1; $i -lt $jobsEnd; $i++) {
            $line = $structuralLines[$i]
            if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le 2) { $trackerEnd = $i; break }
        }
    }

    $trackerProperties = @{}
    $invalidTrackerProperty = $false
    $stepsIndexes = @()
    if ($trackerStart -ge 0) {
        for ($i = $trackerStart + 1; $i -lt $trackerEnd; $i++) {
            $line = $structuralLines[$i]
            if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -ne 4) { continue }
            if ($line -match '^    (?<key>[A-Za-z0-9_-]+):\s*(?<value>.*?)\s*$') {
                $key = $matches['key']
                if (-not $trackerProperties.ContainsKey($key)) { $trackerProperties[$key] = @() }
                $trackerProperties[$key] += $matches['value']
                if ($key -ceq 'steps') { $stepsIndexes += $i }
            } else {
                $invalidTrackerProperty = $true
            }
        }
    }
    $expectedTrackerProperties = @{
        'if' = '${{ github.event_name != ''issue_comment'' || !github.event.issue.pull_request }}'
        'runs-on' = 'ubuntu-latest'
        'timeout-minutes' = '5'
        'steps' = ''
    }
    $trackerPropertiesMatch = -not $invalidTrackerProperty -and
        $trackerProperties.Count -eq $expectedTrackerProperties.Count
    if ($trackerPropertiesMatch) {
        foreach ($key in $expectedTrackerProperties.Keys) {
            $values = @($trackerProperties[$key])
            if ($values.Count -ne 1 -or $values[0] -cne $expectedTrackerProperties[$key]) {
                $trackerPropertiesMatch = $false
                break
            }
        }
    }
    if (-not $trackerPropertiesMatch) {
        $errors += "issue lifecycle tracker-guard direct keys must be the exact if/runs-on/timeout-minutes/steps mapping"
    }
    $stepsStart = -1
    $stepsEnd = $trackerEnd
    if ($stepsIndexes.Count -ne 1) {
        $errors += "issue lifecycle tracker-guard requires one direct steps sequence"
    } else {
        $stepsStart = [int]$stepsIndexes[0]
        for ($i = $stepsStart + 1; $i -lt $trackerEnd; $i++) {
            $line = $structuralLines[$i]
            if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le 4) { $stepsEnd = $i; break }
        }
    }

    $directStepStarts = @()
    if ($stepsStart -ge 0) {
        for ($i = $stepsStart + 1; $i -lt $stepsEnd; $i++) {
            if ($structuralLines[$i] -match '^      -(?:\s+|\s*$)') { $directStepStarts += $i }
        }
    }
    if ($directStepStarts.Count -ne 2) {
        $errors += "issue lifecycle tracker-guard steps must contain exactly checkout then guard"
    }

    $checkoutCandidates = @()
    for ($i = $stepsStart + 1; $stepsStart -ge 0 -and $i -lt $stepsEnd; $i++) {
        $line = $structuralLines[$i]
        $stepStart = -1
        $stepIndent = -1
        if ($line -match '^(?<indent>\s*)-\s+uses:\s*actions/checkout@(?<pin>[^\s#]+)') {
            $stepStart = $i
            $stepIndent = $matches['indent'].Length
        } elseif ($line -match '^(?<indent>\s*)uses:\s*actions/checkout@(?<pin>[^\s#]+)') {
            $usesIndent = $matches['indent'].Length
            for ($j = $i - 1; $j -ge 0; $j--) {
                $prior = $structuralLines[$j]
                if ($prior.Trim().Length -eq 0 -or $prior.TrimStart().StartsWith('#')) { continue }
                $priorIndent = $prior.Length - $prior.TrimStart().Length
                if ($priorIndent -lt $usesIndent) {
                    if ($priorIndent -eq ($usesIndent - 2) -and $prior -match '^\s*-\s+') {
                        $stepStart = $j
                        $stepIndent = $priorIndent
                    }
                    break
                }
            }
        }
        if ($stepStart -lt 0) { continue }

        $stepsOwnerFound = $false
        for ($j = $stepStart - 1; $j -ge 0; $j--) {
            $prior = $structuralLines[$j]
            if ($prior.Trim().Length -eq 0 -or $prior.TrimStart().StartsWith('#')) { continue }
            $priorIndent = $prior.Length - $prior.TrimStart().Length
            if ($priorIndent -lt $stepIndent) {
                if ($priorIndent -eq ($stepIndent - 2) -and $prior.Trim() -ceq 'steps:') {
                    $stepsOwnerFound = $true
                }
                break
            }
        }
        if ($stepsOwnerFound) {
            $checkoutCandidates += @{ Index = $i; StepStart = $stepStart; StepIndent = $stepIndent }
        }
    }
    $checkoutStepLines = @()
    $checkoutStepIndent = -1
    $checkoutStepStart = -1
    if ($checkoutCandidates.Count -ne 1) {
        $errors += "issue lifecycle workflow requires exactly one pinned checkout step"
    } else {
        $candidate = $checkoutCandidates[0]
        $stepStart = [int]$candidate.StepStart
        $stepIndent = [int]$candidate.StepIndent
        $checkoutStepIndent = $stepIndent
        $checkoutStepStart = $stepStart
        $stepEnd = $stepsEnd
        for ($i = $stepStart + 1; $i -lt $stepsEnd; $i++) {
            if ($structuralLines[$i] -match '^(?<indent>\s*)-(?:\s+|\s*$)' -and $matches['indent'].Length -eq $stepIndent) {
                $stepEnd = $i
                break
            }
        }
        if ($stepEnd -gt $stepStart) {
            $checkoutStepLines = @($structuralLines[$stepStart..($stepEnd - 1)])
        }
    }

    $checkoutHasExecutionControl = $false
    $checkoutDirectProperties = @{}
    $invalidCheckoutDirectProperty = $false
    foreach ($line in $checkoutStepLines) {
        $indent = $line.Length - $line.TrimStart().Length
        $directMatch = $false
        if ($indent -eq $checkoutStepIndent -and $line -match '^\s*-\s+(?<key>[A-Za-z0-9_-]+):\s*(?<value>.*?)\s*$') {
            $directMatch = $true
        } elseif ($indent -eq ($checkoutStepIndent + 2) -and $line -match '^\s+(?<key>[A-Za-z0-9_-]+):\s*(?<value>.*?)\s*$') {
            $directMatch = $true
        } elseif ($indent -eq $checkoutStepIndent -or $indent -eq ($checkoutStepIndent + 2)) {
            if ($line.Trim().Length -gt 0 -and -not $line.TrimStart().StartsWith('#')) {
                $invalidCheckoutDirectProperty = $true
            }
        }
        if ($directMatch) {
            $key = $matches['key']
            if (-not $checkoutDirectProperties.ContainsKey($key)) { $checkoutDirectProperties[$key] = @() }
            $checkoutDirectProperties[$key] += $matches['value']
        }
        if (($indent -eq $checkoutStepIndent -and $line -match '^\s*-\s*(?:if|continue-on-error):') -or
                ($indent -eq ($checkoutStepIndent + 2) -and $line -match '^\s*(?:if|continue-on-error):')) {
            $checkoutHasExecutionControl = $true
        }
    }
    if ($checkoutHasExecutionControl) {
        $errors += "issue lifecycle checkout step cannot be skipped or error-ignored"
    }
    $checkoutDirectMatch = -not $invalidCheckoutDirectProperty -and $checkoutDirectProperties.Count -eq 3
    if ($checkoutDirectMatch) {
        $nameValues = @($checkoutDirectProperties['name'])
        $usesValues = @($checkoutDirectProperties['uses'])
        $withValues = @($checkoutDirectProperties['with'])
        $normalizedUsesValue = if ($usesValues.Count -eq 1) {
            ($usesValues[0] -replace '\s+#.*$', '').Trim()
        } else { '' }
        $checkoutDirectMatch = $nameValues.Count -eq 1 -and
            $nameValues[0] -ceq 'Checkout default-branch policy' -and
            $usesValues.Count -eq 1 -and
            $normalizedUsesValue -match '^actions/checkout@[0-9a-fA-F]{40}$' -and
            $withValues.Count -eq 1 -and $withValues[0] -ceq ''
    }
    if (-not $checkoutDirectMatch) {
        $errors += "issue lifecycle checkout step direct keys must be the exact name/uses/with mapping"
    }

    $withIndexes = @()
    $withIndent = $checkoutStepIndent + 2
    for ($i = 0; $i -lt $checkoutStepLines.Count; $i++) {
        $line = $checkoutStepLines[$i]
        $indent = $line.Length - $line.TrimStart().Length
        if ($indent -eq $withIndent -and $line.Trim() -ceq 'with:') {
            $withIndexes += $i
        }
    }
    $propertyLines = @()
    if ($withIndexes.Count -ne 1) {
        $errors += "issue lifecycle checkout requires exactly one direct with mapping"
    } else {
        $withIndex = [int]$withIndexes[0]
        $propertyIndent = $withIndent + 2
        for ($i = $withIndex + 1; $i -lt $checkoutStepLines.Count; $i++) {
            $line = $checkoutStepLines[$i]
            if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le $withIndent) { break }
            if ($indent -eq $propertyIndent) { $propertyLines += $line }
        }
    }

    $properties = @{}
    $invalidCheckoutProperty = $false
    foreach ($line in $propertyLines) {
        if ($line -match '^\s+(?<key>[A-Za-z0-9_-]+):\s*(?<value>.*?)\s*$') {
            $key = $matches['key']
            if (-not $properties.ContainsKey($key)) { $properties[$key] = @() }
            $properties[$key] += $matches['value']
        } else {
            $invalidCheckoutProperty = $true
        }
    }
    $expectedCheckoutProperties = @(
        @{ Key = 'persist-credentials'; Value = 'false'; Error = 'issue lifecycle checkout credentials must not persist' },
        @{ Key = 'fetch-depth'; Value = '0'; Error = 'issue lifecycle exact deployed-source validation requires full history' },
        @{ Key = 'filter'; Value = "'blob:none'"; Error = 'issue lifecycle checkout must retain the blob:none bundle exclusion' },
        @{ Key = 'sparse-checkout-cone-mode'; Value = 'false'; Error = 'issue lifecycle checkout must use non-cone sparse patterns' },
        @{ Key = 'sparse-checkout'; Value = '|'; Error = 'issue lifecycle checkout requires one direct sparse-checkout scalar' }
    )
    foreach ($required in $expectedCheckoutProperties) {
        $values = @($properties[$required.Key])
        if ($values.Count -ne 1 -or $values[0] -cne $required.Value) {
            $errors += $required.Error
        }
    }
    $checkoutPropertyKeysMatch = -not $invalidCheckoutProperty -and
        $propertyLines.Count -eq $expectedCheckoutProperties.Count -and
        $properties.Count -eq $expectedCheckoutProperties.Count
    if (-not $checkoutPropertyKeysMatch) {
        $errors += "issue lifecycle checkout with mapping must contain exactly the five unquoted approved inputs"
    }

    $actualPatterns = @()
    $sparseIndexes = @()
    for ($i = 0; $i -lt $checkoutStepLines.Count; $i++) {
        if ($checkoutStepLines[$i] -match '^\s+sparse-checkout:\s*\|\s*$') { $sparseIndexes += $i }
    }
    if ($sparseIndexes.Count -eq 1 -and $properties.ContainsKey('sparse-checkout')) {
        $sparseIndex = [int]$sparseIndexes[0]
        $sparseIndent = $checkoutStepLines[$sparseIndex].Length - $checkoutStepLines[$sparseIndex].TrimStart().Length
        for ($i = $sparseIndex + 1; $i -lt $checkoutStepLines.Count; $i++) {
            $line = $checkoutStepLines[$i]
            if ($line.Trim().Length -eq 0) { continue }
            $lineIndent = $line.Length - $line.TrimStart().Length
            if ($lineIndent -le $sparseIndent) { break }
            $actualPatterns += $line.Trim()
        }
    }
    $expectedPatterns = @('/qa/', '/tools/', '/*/scripts/mods/')
    $patternsMatch = $actualPatterns.Count -eq $expectedPatterns.Count
    if ($patternsMatch) {
        for ($i = 0; $i -lt $expectedPatterns.Count; $i++) {
            if ($actualPatterns[$i] -cne $expectedPatterns[$i]) {
                $patternsMatch = $false
                break
            }
        }
    }
    if (-not $patternsMatch) {
        $errors += "issue lifecycle checkout sparse patterns must be the exact /qa/, /tools/, /*/scripts/mods/ allowlist"
    }
    $guardSteps = @()
    if ($stepsStart -ge 0) {
        for ($s = 0; $s -lt $directStepStarts.Count; $s++) {
            $guardStepStart = [int]$directStepStarts[$s]
            if ($guardStepStart -le $checkoutStepStart) { continue }
            $guardStepEnd = $stepsEnd
            if (($s + 1) -lt $directStepStarts.Count) { $guardStepEnd = [int]$directStepStarts[$s + 1] }
            $shellCount = 0
            $runIndexes = @()
            $hasExecutionControl = $false
            $guardDirectProperties = @{}
            $invalidGuardDirectProperty = $false
            for ($i = $guardStepStart; $i -lt $guardStepEnd; $i++) {
                $line = $structuralLines[$i]
                $indent = $line.Length - $line.TrimStart().Length
                $directMatch = $false
                if ($indent -eq 6 -and $line -match '^\s*-\s+(?<key>[A-Za-z0-9_-]+):\s*(?<value>.*?)\s*$') {
                    $directMatch = $true
                } elseif ($indent -eq 8 -and $line -match '^\s+(?<key>[A-Za-z0-9_-]+):\s*(?<value>.*?)\s*$') {
                    $directMatch = $true
                } elseif ($indent -eq 6 -or $indent -eq 8) {
                    if ($line.Trim().Length -gt 0 -and -not $line.TrimStart().StartsWith('#')) {
                        $invalidGuardDirectProperty = $true
                    }
                }
                if ($directMatch) {
                    $key = $matches['key']
                    if (-not $guardDirectProperties.ContainsKey($key)) { $guardDirectProperties[$key] = @() }
                    $guardDirectProperties[$key] += $matches['value']
                }
                if (($indent -eq 6 -and $line -match '^\s*-\s*shell:\s*pwsh\s*$') -or
                        ($indent -eq 8 -and $line -match '^        shell:\s*pwsh\s*$')) { $shellCount++ }
                if ($indent -eq 8 -and $lines[$i] -match '^        run:\s*[|>]') { $runIndexes += $i }
                if (($indent -eq 6 -and $line -match '^\s*-\s*(?:if|continue-on-error):') -or
                        ($indent -eq 8 -and $line -match '^\s*(?:if|continue-on-error):')) {
                    $hasExecutionControl = $true
                }
            }
            if ($shellCount -ne 1 -or $runIndexes.Count -ne 1) { continue }
            $guardDirectMatch = -not $invalidGuardDirectProperty -and $guardDirectProperties.Count -eq 4
            if ($guardDirectMatch) {
                $nameValues = @($guardDirectProperties['name'])
                $shellValues = @($guardDirectProperties['shell'])
                $envValues = @($guardDirectProperties['env'])
                $runValues = @($guardDirectProperties['run'])
                $guardDirectMatch = $nameValues.Count -eq 1 -and
                    $nameValues[0] -ceq 'Validate tracker lifecycle and pinned test cards' -and
                    $shellValues.Count -eq 1 -and $shellValues[0] -ceq 'pwsh' -and
                    $envValues.Count -eq 1 -and $envValues[0] -ceq '' -and
                    $runValues.Count -eq 1 -and $runValues[0] -ceq '|'
            }
            if (-not $guardDirectMatch) { continue }

            $envIndexes = @()
            for ($i = $guardStepStart; $i -lt $guardStepEnd; $i++) {
                if ($structuralLines[$i] -ceq '        env:') { $envIndexes += $i }
            }
            if ($envIndexes.Count -ne 1) { continue }
            $envIndex = [int]$envIndexes[0]
            $envProperties = @()
            for ($i = $envIndex + 1; $i -lt $guardStepEnd; $i++) {
                $line = $structuralLines[$i]
                if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
                $indent = $line.Length - $line.TrimStart().Length
                if ($indent -le 8) { break }
                if ($indent -eq 10) { $envProperties += $line }
            }
            if ($envProperties.Count -ne 1 -or
                    $envProperties[0] -cne '          GH_TOKEN: ${{ github.token }}') { continue }
            $runIndex = [int]$runIndexes[0]
            $runIndent = 8
            $commands = @()
            for ($i = $runIndex + 1; $i -lt $guardStepEnd; $i++) {
                $line = $lines[$i]
                if ($line.Trim().Length -eq 0 -or $line.TrimStart().StartsWith('#')) { continue }
                $indent = $line.Length - $line.TrimStart().Length
                if ($indent -le $runIndent) { break }
                $commands += $line.Trim()
            }
            $expectedCommands = @(
                './tools/github/check-lifecycle-cardinality.ps1 -SelfTest',
                'if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }',
                './tools/github/check-lifecycle-cardinality.ps1 -Repository ''${{ github.repository }}'''
            )
            $commandsMatch = $commands.Count -eq $expectedCommands.Count
            if ($commandsMatch) {
                for ($i = 0; $i -lt $expectedCommands.Count; $i++) {
                    if ($commands[$i] -cne $expectedCommands[$i]) { $commandsMatch = $false; break }
                }
            }
            if ($commandsMatch -and -not $hasExecutionControl) {
                $guardSteps += $guardStepStart
            }
        }
    }
    if ($guardSteps.Count -ne 1) {
        $errors += "issue lifecycle tracker-guard requires one later unconditional pwsh guard step with exact fail-closed commands"
    }
    if ($directStepStarts.Count -eq 2 -and
            ($checkoutStepStart -ne [int]$directStepStarts[0] -or
            $guardSteps.Count -ne 1 -or [int]$guardSteps[0] -ne [int]$directStepStarts[1])) {
        $errors += "issue lifecycle tracker-guard steps must be exactly checkout first and guard second"
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

    $goodIssueLifecycleWorkflow = @'
permissions:
  contents: read
  issues: read
jobs:
  tracker-guard:
    if: ${{ github.event_name != 'issue_comment' || !github.event.issue.pull_request }}
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - name: Checkout default-branch policy
        uses: actions/checkout@1234567890123456789012345678901234567890 # v4
        with:
          persist-credentials: false
          fetch-depth: 0
          filter: 'blob:none'
          sparse-checkout-cone-mode: false
          sparse-checkout: |
            /qa/
            /tools/
            /*/scripts/mods/
      - name: Validate tracker lifecycle and pinned test cards
        shell: pwsh
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          ./tools/github/check-lifecycle-cardinality.ps1 -SelfTest
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          ./tools/github/check-lifecycle-cardinality.ps1 -Repository '${{ github.repository }}'
'@
    $goodIssueLifecycle = @(Test-IssueLifecycleCheckoutContract $goodIssueLifecycleWorkflow)
    if ($goodIssueLifecycle.Count -ne 0) {
        throw ("valid issue lifecycle checkout was rejected: " + ($goodIssueLifecycle -join '; '))
    }

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

    $badConeWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^\s+sparse-checkout-cone-mode:\s*false\s*\r?\n', ''
    $badCone = @(Test-IssueLifecycleCheckoutContract $badConeWorkflow)
    if (-not ($badCone -match 'non-cone')) {
        throw "issue lifecycle cone-mode regression was not detected"
    }

    $badBundleWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(\s+/\*/scripts/mods/\s*)$', "`$1`n            /*/bundleV2/"
    $badBundle = @(Test-IssueLifecycleCheckoutContract $badBundleWorkflow)
    if (-not ($badBundle -match 'exact .+ allowlist')) {
        throw "issue lifecycle bundle hydration regression was not detected"
    }

    $badBroadWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(\s+/\*/scripts/mods/\s*)$', "`$1`n            /*/"
    $badBroad = @(Test-IssueLifecycleCheckoutContract $badBroadWorkflow)
    if (-not ($badBroad -match 'exact .+ allowlist')) {
        throw "issue lifecycle broad hydration regression was not detected"
    }

    $badOutsideWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^\s+/\*/scripts/mods/\s*$', '            /qa/fixtures/'
    $badOutsideWorkflow += "`n            /*/scripts/mods/"
    $badOutside = @(Test-IssueLifecycleCheckoutContract $badOutsideWorkflow)
    if (-not ($badOutside -match 'exact .+ allowlist')) {
        throw "issue lifecycle out-of-checkout hydration spoof was not detected"
    }

    $badRunScalarWorkflow = @'
permissions:
  contents: read
  issues: read
jobs:
  tracker-guard:
    timeout-minutes: 5
    steps:
      - shell: pwsh
        run: |2-
          uses: actions/checkout@1234567890123456789012345678901234567890
          with:
            persist-credentials: false
            fetch-depth: 0
            filter: 'blob:none'
            sparse-checkout-cone-mode: false
            sparse-checkout: |
              /qa/
              /tools/
              /*/scripts/mods/
          ./tools/github/check-lifecycle-cardinality.ps1 -SelfTest
          ./tools/github/check-lifecycle-cardinality.ps1 -Repository 'owner/repo'
'@
    $badRunScalar = @(Test-IssueLifecycleCheckoutContract $badRunScalarWorkflow)
    if (-not ($badRunScalar -match 'exactly one pinned checkout step')) {
        throw "issue lifecycle run-scalar checkout spoof was not detected"
    }

    $badEnvWorkflow = $goodIssueLifecycleWorkflow -replace '(?ms)^          sparse-checkout:\s*\|\r?\n            /qa/\r?\n            /tools/\r?\n            /\*/scripts/mods/', "        env:`n          sparse-checkout: |`n            /qa/`n            /tools/`n            /*/scripts/mods/"
    $badEnv = @(Test-IssueLifecycleCheckoutContract $badEnvWorkflow)
    if (-not ($badEnv -match 'direct sparse-checkout')) {
        throw "issue lifecycle same-step env hydration spoof was not detected"
    }

    $badDecoyWorkflow = @'
permissions:
  contents: read
  issues: read
jobs:
  hydration-decoy:
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@1234567890123456789012345678901234567890
        with:
          persist-credentials: false
          fetch-depth: 0
          filter: 'blob:none'
          sparse-checkout-cone-mode: false
          sparse-checkout: |
            /qa/
            /tools/
            /*/scripts/mods/
      - shell: pwsh
        run: |
          ./tools/github/check-lifecycle-cardinality.ps1 -SelfTest
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          ./tools/github/check-lifecycle-cardinality.ps1 -Repository '${{ github.repository }}'
  tracker-guard:
    steps:
      - shell: pwsh
        run: Write-Host 'guard disabled'
'@
    $badDecoy = @(Test-IssueLifecycleCheckoutContract $badDecoyWorkflow)
    if (-not ($badDecoy -match 'tracker-guard direct keys') -or
            -not ($badDecoy -match 'pinned checkout step') -or
            -not ($badDecoy -match 'pwsh guard step')) {
        throw "issue lifecycle decoy-job spoof was not detected"
    }

    $badCommentedGuardsWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(\s+)(\./tools/github/check-lifecycle-cardinality\.ps1|-?if \(\$LASTEXITCODE)', '$1# $2'
    $badCommentedGuards = @(Test-IssueLifecycleCheckoutContract $badCommentedGuardsWorkflow)
    if (-not ($badCommentedGuards -match 'pwsh guard step')) {
        throw "issue lifecycle commented-guard spoof was not detected"
    }

    $badSkippedWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(      - name: Checkout default-branch policy)$', "`$1`n        if: false"
    $badSkippedWorkflow = $badSkippedWorkflow -replace '(?m)^(      - name: Validate tracker lifecycle and pinned test cards)$', "`$1`n        continue-on-error: true"
    $badSkipped = @(Test-IssueLifecycleCheckoutContract $badSkippedWorkflow)
    if (-not ($badSkipped -match 'checkout step cannot be skipped') -or
            -not ($badSkipped -match 'pwsh guard step')) {
        throw "issue lifecycle skipped/error-ignored step spoof was not detected"
    }

    $badJobIfWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^    if: \$\{\{ github\.event_name != ''issue_comment'' \|\| !github\.event\.issue\.pull_request \}\}$', '    if: false'
    $badJobIf = @(Test-IssueLifecycleCheckoutContract $badJobIfWorkflow)
    if (-not ($badJobIf -match 'tracker-guard direct keys')) {
        throw "issue lifecycle skipped tracker job spoof was not detected"
    }

    $badDuplicateJobIfWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(    if: .+)$', "`$1`n    if: false"
    $badDuplicateJobIf = @(Test-IssueLifecycleCheckoutContract $badDuplicateJobIfWorkflow)
    if (-not ($badDuplicateJobIf -match 'tracker-guard direct keys')) {
        throw "issue lifecycle duplicate job-if spoof was not detected"
    }

    $badDuplicateTimeoutWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(    timeout-minutes: 5)$', "`$1`n    timeout-minutes: 30"
    $badDuplicateTimeout = @(Test-IssueLifecycleCheckoutContract $badDuplicateTimeoutWorkflow)
    if (-not ($badDuplicateTimeout -match 'tracker-guard direct keys')) {
        throw "issue lifecycle duplicate timeout spoof was not detected"
    }

    $badJobContinueWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(    timeout-minutes: 5)$', "`$1`n    continue-on-error: true"
    $badJobContinue = @(Test-IssueLifecycleCheckoutContract $badJobContinueWorkflow)
    if (-not ($badJobContinue -match 'tracker-guard direct keys')) {
        throw "issue lifecycle job continue-on-error spoof was not detected"
    }

    $badLfsWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(          fetch-depth: 0)$', "`$1`n          lfs: true"
    $badLfs = @(Test-IssueLifecycleCheckoutContract $badLfsWorkflow)
    if (-not ($badLfs -match 'five unquoted approved inputs')) {
        throw "issue lifecycle extra checkout input spoof was not detected"
    }

    $badQuotedSparseWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(          sparse-checkout-cone-mode: false)$', "`$1`n          `"sparse-checkout`": |`n            /*/"
    $badQuotedSparse = @(Test-IssueLifecycleCheckoutContract $badQuotedSparseWorkflow)
    if (-not ($badQuotedSparse -match 'five unquoted approved inputs')) {
        throw "issue lifecycle quoted duplicate checkout input spoof was not detected"
    }

    $badFoldedRunWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^        run: \|$', '        run: >2-'
    $badFoldedRun = @(Test-IssueLifecycleCheckoutContract $badFoldedRunWorkflow)
    if (-not ($badFoldedRun -match 'pwsh guard step')) {
        throw "issue lifecycle folded guard scalar spoof was not detected"
    }

    $badQuotedCheckoutIfWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(        uses: actions/checkout@[^\r\n]+)$', "`$1`n        `"if`": false"
    $badQuotedCheckoutIf = @(Test-IssueLifecycleCheckoutContract $badQuotedCheckoutIfWorkflow)
    if (-not ($badQuotedCheckoutIf -match 'checkout step direct keys')) {
        throw "issue lifecycle quoted checkout-if spoof was not detected"
    }

    $badQuotedGuardIfWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(        shell: pwsh)$', "`$1`n        `"if`": false"
    $badQuotedGuardIf = @(Test-IssueLifecycleCheckoutContract $badQuotedGuardIfWorkflow)
    if (-not ($badQuotedGuardIf -match 'pwsh guard step')) {
        throw "issue lifecycle quoted guard-if spoof was not detected"
    }

    $badQuotedGuardContinueWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(        shell: pwsh)$', "`$1`n        `"continue-on-error`": true"
    $badQuotedGuardContinue = @(Test-IssueLifecycleCheckoutContract $badQuotedGuardContinueWorkflow)
    if (-not ($badQuotedGuardContinue -match 'pwsh guard step')) {
        throw "issue lifecycle quoted guard continue-on-error spoof was not detected"
    }

    $badQuotedUsesWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(        uses: actions/checkout@[^\r\n]+)$', "`$1`n        `"uses`": actions/checkout@v4"
    $badQuotedUses = @(Test-IssueLifecycleCheckoutContract $badQuotedUsesWorkflow)
    if (-not ($badQuotedUses -match 'checkout step direct keys')) {
        throw "issue lifecycle quoted duplicate uses spoof was not detected"
    }

    $badExtraStepWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(      - name: Validate tracker lifecycle and pinned test cards)$', "      - uses: attacker/action@1234567890123456789012345678901234567890`n`$1"
    $badExtraStep = @(Test-IssueLifecycleCheckoutContract $badExtraStepWorkflow)
    if (-not ($badExtraStep -match 'exactly checkout then guard')) {
        throw "issue lifecycle extra tracker step was not detected"
    }

    $badQuotedActionWorkflow = $goodIssueLifecycleWorkflow + "`n" + @'
  decoy:
    runs-on: ubuntu-latest
    steps:
      - "uses": attacker/action@main
'@
    $badQuotedAction = @(Test-IssueLifecycleCheckoutContract $badQuotedActionWorkflow)
    if (-not ($badQuotedAction -match 'exact unquoted lowercase uses')) {
        throw "issue lifecycle quoted mutable action outside tracker job was not detected"
    }

    $badEscapedQuotedActionWorkflow = $goodIssueLifecycleWorkflow + "`n" + @'
  decoy:
    runs-on: ubuntu-latest
    steps:
      - "us\u0065s": attacker/action@main
'@
    $badEscapedQuotedAction = @(Test-IssueLifecycleCheckoutContract $badEscapedQuotedActionWorkflow)
    if (-not ($badEscapedQuotedAction -match 'structural mapping keys must be unquoted') -or
            -not ($badEscapedQuotedAction -match 'exactly the unquoted tracker-guard job')) {
        throw "issue lifecycle escaped quoted action key spoof was not detected"
    }

    $badEscapedJobsWorkflow = $goodIssueLifecycleWorkflow + "`n" + @'
"jo\u0062s":
  decoy:
    runs-on: ubuntu-latest
'@
    $badEscapedJobs = @(Test-IssueLifecycleCheckoutContract $badEscapedJobsWorkflow)
    if (-not ($badEscapedJobs -match 'structural mapping keys must be unquoted')) {
        throw "issue lifecycle escaped quoted jobs key spoof was not detected"
    }

    $badBareDashStepWorkflow = $goodIssueLifecycleWorkflow -replace '(?m)^(      - name: Checkout default-branch policy)$', "      -`n        shell: pwsh`n        run: Write-Host 'untracked pre-checkout step'`n`$1"
    $badBareDashStep = @(Test-IssueLifecycleCheckoutContract $badBareDashStepWorkflow)
    if (-not ($badBareDashStep -match 'exactly checkout then guard')) {
        throw "issue lifecycle bare-dash extra step was not detected"
    }
    Write-Host "[check_ci_hardening -SelfTest] OK"
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path $RepoRoot).Path
$workflowPath = Join-Path $root '.github\workflows\qa.yml'
$trustedWorkflowPath = Join-Path $root '.github\workflows\stable-promotion-authorization.yml'
$autoCloseAuthWorkflowPath = Join-Path $root '.github\workflows\pr-autoclose-authorization.yml'
$autoCloseAuditWorkflowPath = Join-Path $root '.github\workflows\pr-autoclose-audit.yml'
$issueLifecycleWorkflowPath = Join-Path $root '.github\workflows\issue-lifecycle.yml'
$protectionPath = Join-Path $root 'tools\github\protect-master.ps1'
if (-not (Test-Path $workflowPath) -or -not (Test-Path $trustedWorkflowPath) -or
        -not (Test-Path $autoCloseAuthWorkflowPath) -or -not (Test-Path $autoCloseAuditWorkflowPath) -or
        -not (Test-Path $issueLifecycleWorkflowPath) -or -not (Test-Path $protectionPath)) {
    Write-Host "[check_ci_hardening] ERROR - QA/trusted/lifecycle workflows or protection tool missing." -ForegroundColor Red
    exit 2
}

$workflow = [System.IO.File]::ReadAllText($workflowPath, [System.Text.Encoding]::UTF8)
$trustedWorkflow = [System.IO.File]::ReadAllText($trustedWorkflowPath, [System.Text.Encoding]::UTF8)
$autoCloseAuthWorkflow = [System.IO.File]::ReadAllText($autoCloseAuthWorkflowPath, [System.Text.Encoding]::UTF8)
$autoCloseAuditWorkflow = [System.IO.File]::ReadAllText($autoCloseAuditWorkflowPath, [System.Text.Encoding]::UTF8)
$issueLifecycleWorkflow = [System.IO.File]::ReadAllText($issueLifecycleWorkflowPath, [System.Text.Encoding]::UTF8)
$protection = [System.IO.File]::ReadAllText($protectionPath, [System.Text.Encoding]::UTF8)
$errors = @(Test-CiContract $workflow $trustedWorkflow $autoCloseAuthWorkflow $autoCloseAuditWorkflow $protection)
$errors += @(Test-IssueLifecycleCheckoutContract $issueLifecycleWorkflow)
if ($errors.Count -gt 0) {
    Write-Host "[check_ci_hardening] ERRORS:" -ForegroundColor Red
    foreach ($errorMessage in $errors) { Write-Host "  X $errorMessage" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) { Write-Host "[check_ci_hardening] OK - CI workflow and protected-branch policy are hardened." -ForegroundColor Green }
exit 0
