# tools/ship/publication-authorization.ps1
#
# Canonical publication-authorization policy shared by ship.ps1 and the
# GitHub-release publisher. Real publication is allowed only for the exact
# clean live default-branch commit, with an associated merged pull request and
# a successful hosted qa-gate check on that same commit.
#
# Caller-provided JSON is audit correlation only. Every mutating component must
# call Get-LivePublicationAuthorization itself immediately before mutation.
#
# ASCII only for Windows PowerShell 5.1 compatibility.

function Test-PublicationAuthorizationSnapshot {
    param(
        [string]$SourceCommit,
        [string]$DefaultBranch,
        [string]$DefaultBranchCommit,
        [object[]]$PullRequests,
        [object[]]$CheckRuns,
        [datetime]$CheckedAtUtc = ([datetime]::UtcNow)
    )

    $source = if ($SourceCommit) { $SourceCommit.Trim().ToLowerInvariant() } else { '' }
    $checked = $CheckedAtUtc.ToUniversalTime().ToString(
        'yyyy-MM-ddTHH:mm:ssZ',
        [System.Globalization.CultureInfo]::InvariantCulture)

    if ($source -notmatch '^[0-9a-f]{40}$') {
        return @{ Ok = $false; Message = "Source commit '$SourceCommit' is not a full Git commit SHA."; Evidence = $null }
    }
    if ([string]::IsNullOrWhiteSpace($DefaultBranch)) {
        return @{ Ok = $false; Message = 'GitHub did not report a default branch.'; Evidence = $null }
    }
    $defaultSha = if ($DefaultBranchCommit) { $DefaultBranchCommit.Trim().ToLowerInvariant() } else { '' }
    if ($defaultSha -ne $source) {
        return @{ Ok = $false; Message = "Source commit $source is not live $DefaultBranch HEAD ($defaultSha)."; Evidence = $null }
    }

    $merged = @($PullRequests | Where-Object {
        $_ -and $_.merged_at -and $_.base -and
        ([string]$_.base.ref -eq $DefaultBranch) -and
        ([string]$_.merge_commit_sha).ToLowerInvariant() -eq $source
    } | Sort-Object { [int]$_.number })
    if ($merged.Count -eq 0) {
        return @{ Ok = $false; Message = "No merged pull request binds exact commit $source to $DefaultBranch."; Evidence = $null }
    }

    $qa = @($CheckRuns | Where-Object {
        $_ -and ([string]$_.name -eq 'qa-gate') -and
        ([string]$_.head_sha).ToLowerInvariant() -eq $source -and
        ([string]$_.status -eq 'completed') -and
        ([string]$_.conclusion -eq 'success') -and
        $_.completed_at
    } | Sort-Object { [datetime]$_.completed_at } -Descending)
    if ($qa.Count -eq 0) {
        return @{ Ok = $false; Message = "Hosted qa-gate is not completed/successful for exact commit $source."; Evidence = $null }
    }

    $completed = ([datetime]$qa[0].completed_at).ToUniversalTime().ToString(
        'yyyy-MM-ddTHH:mm:ssZ',
        [System.Globalization.CultureInfo]::InvariantCulture)
    return @{
        Ok = $true
        Message = "live $DefaultBranch commit, merged PR #$($merged[0].number), hosted qa-gate success"
        Evidence = [ordered]@{
            mode = 'hosted_qa'
            source_commit = $source
            checked_at_utc = $checked
            default_branch = $DefaultBranch
            default_branch_commit = $defaultSha
            merged_pr_number = [int]$merged[0].number
            qa_check = 'qa-gate'
            qa_check_url = [string]$qa[0].html_url
            qa_completed_at_utc = $completed
        }
    }
}

function Invoke-PublicationNativeCapture {
    param([scriptblock]$Command)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $Command 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ ExitCode = $code; Lines = $lines }
}

function ConvertFrom-PublicationNativeJson {
    param([object]$Capture, [string]$Description)
    if ($Capture.ExitCode -ne 0) {
        throw "$Description query failed (exit $($Capture.ExitCode)): $($Capture.Lines -join ' | ')"
    }
    try {
        return (($Capture.Lines -join "`n") | ConvertFrom-Json)
    }
    catch {
        throw "$Description returned invalid JSON: $($_.Exception.Message)"
    }
}

function Get-LivePublicationAuthorization {
    param(
        [string]$Repo,
        [string]$SourceCommit
    )

    $repoInfo = ConvertFrom-PublicationNativeJson `
        (Invoke-PublicationNativeCapture { & gh api "repos/$Repo" }) `
        'GitHub repository'
    $defaultBranch = [string]$repoInfo.default_branch
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
        throw 'GitHub repository response omitted default_branch.'
    }
    $branchRef = ConvertFrom-PublicationNativeJson `
        (Invoke-PublicationNativeCapture { & gh api "repos/$Repo/git/ref/heads/$defaultBranch" }) `
        'GitHub default-branch ref'
    $pulls = @(ConvertFrom-PublicationNativeJson `
        (Invoke-PublicationNativeCapture { & gh api -H 'Accept: application/vnd.github+json' "repos/$Repo/commits/$SourceCommit/pulls" }) `
        'GitHub associated pull requests')
    $checksResponse = ConvertFrom-PublicationNativeJson `
        (Invoke-PublicationNativeCapture { & gh api -H 'Accept: application/vnd.github+json' "repos/$Repo/commits/$SourceCommit/check-runs" }) `
        'GitHub check runs'

    return Test-PublicationAuthorizationSnapshot `
        -SourceCommit $SourceCommit `
        -DefaultBranch $defaultBranch `
        -DefaultBranchCommit ([string]$branchRef.object.sha) `
        -PullRequests $pulls `
        -CheckRuns @($checksResponse.check_runs)
}

function ConvertTo-PublicationEvidenceUtcString {
    param([object]$Value)

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace("$Value")) {
        return ''
    }
    try {
        return ([datetime]$Value).ToUniversalTime().ToString(
            'yyyy-MM-ddTHH:mm:ssZ',
            [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return ''
    }
}

function Test-PublicationEvidenceMatchesLive {
    param(
        [object]$CallerEvidence,
        [object]$LiveEvidence
    )

    if (-not $CallerEvidence -or -not $LiveEvidence) {
        return @{ Ok = $false; Message = 'Both caller and independently queried live authorization evidence are required.' }
    }
    $fields = @(
        'mode',
        'source_commit',
        'default_branch',
        'default_branch_commit',
        'merged_pr_number',
        'qa_check',
        'qa_check_url',
        'qa_completed_at_utc'
    )
    foreach ($field in $fields) {
        $callerValue = [string]$CallerEvidence.$field
        $liveValue = [string]$LiveEvidence.$field
        if ($field -eq 'qa_completed_at_utc') {
            # PowerShell 7 ConvertFrom-Json materializes ISO timestamps as
            # DateTime while Windows PowerShell 5.1 keeps strings. Compare the
            # same UTC instant, not the caller process's culture rendering.
            $callerValue = ConvertTo-PublicationEvidenceUtcString $CallerEvidence.$field
            $liveValue = ConvertTo-PublicationEvidenceUtcString $LiveEvidence.$field
        }
        if ([string]::IsNullOrWhiteSpace($callerValue) -or $callerValue -ne $liveValue) {
            return @{ Ok = $false; Message = "Caller authorization field '$field' does not match the independently queried live value." }
        }
    }
    return @{ Ok = $true; Message = 'caller evidence matches independently queried live authorization' }
}
