# check_promotion_authorization.ps1 - maintainer-trusted stable-promotion gate.
#
# Stable directories are write-by-promotion-only. A commit trailer is authored
# by the PR branch itself, so it cannot be an authorization boundary. This gate
# accepts a promotion only when the current same-repository PR has:
#   1. the live `stable-promotion-approved` label;
#   2. a maintainer-authored approval line bound to every changed stable dir,
#      its current MOD_VERSION, and the exact PR head SHA; and
#   3. a later label event by that same maintainer.
#
# The label timeline and approval comment remain GitHub's audit record. A push
# makes the SHA stale; removing the label revokes the grant. Issue #676.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$WriteGitHubEnv,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$APPROVAL_LABEL = 'stable-promotion-approved'
$STABLE_DIRS = @(
    'chaos_wastes_tweaker',
    'crafting_in_modded',
    'general_tweaker',
    'gui_tweaker',
    'verminious_dreams_lighting'
)

function Get-StablePromotionRequests {
    param(
        [string[]]$Paths,
        [string]$Root,
        [scriptblock]$ReadSource
    )

    $dirs = New-Object System.Collections.Generic.HashSet[string]
    foreach ($path in @($Paths)) {
        $normalized = "$path".Replace('\', '/')
        foreach ($dir in $STABLE_DIRS) {
            if ($normalized -eq $dir -or $normalized.StartsWith("$dir/")) {
                [void]$dirs.Add($dir)
                break
            }
        }
    }

    $requests = @()
    foreach ($dir in @($dirs | Sort-Object)) {
        $relativeMain = "$dir/scripts/mods/$dir/$dir.lua"
        if ($ReadSource) {
            $text = & $ReadSource $relativeMain
        } else {
            $main = Join-Path $Root $relativeMain
            if (-not (Test-Path -LiteralPath $main)) {
                throw "stable promotion source missing: $main"
            }
            $text = [System.IO.File]::ReadAllText($main, [System.Text.Encoding]::UTF8)
        }
        $match = [regex]::Match($text, 'MOD_VERSION\s*=\s*"(?<version>[^"]+)"')
        if (-not $match.Success) {
            throw "stable promotion source has no MOD_VERSION: $relativeMain"
        }
        $requests += [pscustomobject]@{
            Dir = $dir
            Version = $match.Groups['version'].Value
        }
    }
    return @($requests)
}

function Get-ApprovalEntries {
    param([string]$Body)

    $entries = @()
    if ([string]::IsNullOrWhiteSpace($Body)) { return $entries }
    $pattern = '(?im)^[ \t]*VT2-Promotion-Approval:[ \t]+(?<dir>[a-z0-9_]+)@(?<version>\d+\.\d+\.\d+(?:-[A-Za-z0-9.+-]+)?)[ \t]+head=(?<sha>[0-9a-f]{40})[ \t]*$'
    foreach ($match in [regex]::Matches($Body, $pattern)) {
        $entries += [pscustomobject]@{
            Dir = $match.Groups['dir'].Value
            Version = $match.Groups['version'].Value
            HeadSha = $match.Groups['sha'].Value.ToLowerInvariant()
        }
    }
    return @($entries)
}

function Test-PromotionAuthorization {
    param([pscustomobject]$Context)

    if ($Context.IsFork) {
        return [pscustomobject]@{ Allowed = $false; Reason = 'fork PRs cannot carry stable promotions' }
    }
    if (@($Context.Requests).Count -eq 0) {
        return [pscustomobject]@{ Allowed = $true; Reason = 'no stable directories changed' }
    }
    if (@($Context.Labels) -notcontains $APPROVAL_LABEL) {
        return [pscustomobject]@{ Allowed = $false; Reason = "live label '$APPROVAL_LABEL' is absent" }
    }

    $labelEvents = @($Context.LabelEvents | Where-Object { $_.Label -eq $APPROVAL_LABEL } | Sort-Object CreatedAt)
    if ($labelEvents.Count -eq 0 -or $labelEvents[-1].Event -ne 'labeled') {
        return [pscustomobject]@{ Allowed = $false; Reason = 'approval label has no current grant event' }
    }
    $grant = $labelEvents[-1]
    $grantPermission = "$($Context.Permissions[$grant.Actor])".ToLowerInvariant()
    if ($grantPermission -notin @('admin', 'maintain')) {
        return [pscustomobject]@{ Allowed = $false; Reason = "label actor '$($grant.Actor)' lacks maintainer permission" }
    }

    $expected = @{}
    foreach ($request in @($Context.Requests)) {
        $expected["$($request.Dir)@$($request.Version)@$($Context.HeadSha.ToLowerInvariant())"] = $true
    }

    foreach ($comment in @($Context.Comments | Sort-Object CreatedAt -Descending)) {
        if ($comment.Author -ne $grant.Actor) { continue }
        $permission = "$($Context.Permissions[$comment.Author])".ToLowerInvariant()
        if ($permission -notin @('admin', 'maintain')) { continue }

        $entries = @(Get-ApprovalEntries -Body $comment.Body)
        if ($entries.Count -ne $expected.Count) { continue }
        $found = @{}
        foreach ($entry in $entries) {
            $found["$($entry.Dir)@$($entry.Version)@$($entry.HeadSha)"] = $true
        }
        $exact = $found.Count -eq $expected.Count
        if ($exact) {
            foreach ($key in $expected.Keys) {
                if (-not $found.ContainsKey($key)) { $exact = $false; break }
            }
        }
        if (-not $exact) { continue }

        $created = [DateTimeOffset]::Parse($comment.CreatedAt)
        $updated = [DateTimeOffset]::Parse($comment.UpdatedAt)
        $granted = [DateTimeOffset]::Parse($grant.CreatedAt)
        if ($created -gt $granted -or $updated -gt $granted) {
            continue
        }

        return [pscustomobject]@{
            Allowed = $true
            Reason = 'exact maintainer grant is current'
            Author = $comment.Author
            CommentId = $comment.Id
            GrantedAt = $grant.CreatedAt
        }
    }

    return [pscustomobject]@{ Allowed = $false; Reason = 'no immutable maintainer approval matches the current dirs, versions, and head SHA' }
}

function Invoke-GhLines {
    param([string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& gh @Arguments 2>$null)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($code -ne 0) {
        throw "gh $($Arguments -join ' ') failed with exit $code"
    }
    return @($output | ForEach-Object { "$_" } | Where-Object { $_.Trim() })
}

function Invoke-GhRaw {
    param([string[]]$Arguments)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& gh @Arguments 2>$null)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($code -ne 0) {
        throw "gh $($Arguments -join ' ') failed with exit $code"
    }
    return ($output -join "`n")
}

function Invoke-SelfTest {
    $sha = '0123456789abcdef0123456789abcdef01234567'
    $grantAt = '2026-07-19T06:00:00Z'
    $approval = "VT2-Promotion-Approval: crafting_in_modded@0.8.91 head=$sha"
    $base = [pscustomobject]@{
        IsFork = $false
        HeadSha = $sha
        Requests = @([pscustomobject]@{ Dir = 'crafting_in_modded'; Version = '0.8.91' })
        Labels = @($APPROVAL_LABEL)
        LabelEvents = @([pscustomobject]@{ Event = 'labeled'; Label = $APPROVAL_LABEL; Actor = 'maintainer'; CreatedAt = $grantAt })
        Comments = @([pscustomobject]@{ Id = 7; Author = 'maintainer'; Body = $approval; CreatedAt = '2026-07-19T05:59:00Z'; UpdatedAt = '2026-07-19T05:59:00Z' })
        Permissions = @{ maintainer = 'admin'; contributor = 'write' }
    }

    $tests = @()
    $tests += @{ Name = 'exact maintainer grant'; Context = $base; Expected = $true }

    $missing = $base.PSObject.Copy(); $missing.Labels = @()
    $tests += @{ Name = 'missing label'; Context = $missing; Expected = $false }

    $staleSha = $base.PSObject.Copy(); $staleSha.HeadSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $tests += @{ Name = 'stale head'; Context = $staleSha; Expected = $false }

    $staleVersion = $base.PSObject.Copy(); $staleVersion.Requests = @([pscustomobject]@{ Dir = 'crafting_in_modded'; Version = '0.8.92' })
    $tests += @{ Name = 'stale version'; Context = $staleVersion; Expected = $false }

    $fork = $base.PSObject.Copy(); $fork.IsFork = $true
    $tests += @{ Name = 'fork cannot self-authorize'; Context = $fork; Expected = $false }

    $untrusted = $base.PSObject.Copy(); $untrusted.LabelEvents = @([pscustomobject]@{ Event = 'labeled'; Label = $APPROVAL_LABEL; Actor = 'contributor'; CreatedAt = $grantAt })
    $untrusted.Comments = @([pscustomobject]@{ Id = 8; Author = 'contributor'; Body = $approval; CreatedAt = '2026-07-19T05:59:00Z'; UpdatedAt = '2026-07-19T05:59:00Z' })
    $tests += @{ Name = 'write user cannot authorize'; Context = $untrusted; Expected = $false }

    $removed = $base.PSObject.Copy(); $removed.Labels = @(); $removed.LabelEvents = @(
        [pscustomobject]@{ Event = 'labeled'; Label = $APPROVAL_LABEL; Actor = 'maintainer'; CreatedAt = $grantAt },
        [pscustomobject]@{ Event = 'unlabeled'; Label = $APPROVAL_LABEL; Actor = 'maintainer'; CreatedAt = '2026-07-19T06:01:00Z' }
    )
    $tests += @{ Name = 'label removal revokes'; Context = $removed; Expected = $false }

    $edited = $base.PSObject.Copy(); $edited.Comments = @([pscustomobject]@{ Id = 9; Author = 'maintainer'; Body = $approval; CreatedAt = '2026-07-19T05:59:00Z'; UpdatedAt = '2026-07-19T06:01:00Z' })
    $tests += @{ Name = 'post-grant comment edit invalidates'; Context = $edited; Expected = $false }

    $failed = @()
    $requests = @(Get-StablePromotionRequests -Paths @('crafting_in_modded/itemV2.cfg') -Root '' -ReadSource {
        param([string]$Path)
        if ($Path -ne 'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua') { throw "unexpected source path: $Path" }
        'local MOD_VERSION = "0.8.91"'
    })
    if ($requests.Count -ne 1 -or $requests[0].Version -ne '0.8.91') {
        $failed += 'live PR source reader did not resolve the exact stable version'
    }
    foreach ($test in $tests) {
        $result = Test-PromotionAuthorization -Context $test.Context
        if ($result.Allowed -ne $test.Expected) {
            $failed += "$($test.Name): expected=$($test.Expected) actual=$($result.Allowed) reason=$($result.Reason)"
        }
    }
    if ($failed.Count -gt 0) {
        Write-Host '[check_promotion_authorization] SELF-TEST FAILED' -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        return 2
    }
    Write-Host "[check_promotion_authorization] SELF-TEST PASS - $($tests.Count) authorization cases plus live-source resolution." -ForegroundColor Green
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
if ($env:GITHUB_EVENT_NAME -notin @('pull_request', 'pull_request_target') -or -not $env:GITHUB_EVENT_PATH) {
    if (-not $Quiet) { Write-Host '[check_promotion_authorization] SKIP - not a pull-request workflow.' -ForegroundColor DarkGray }
    exit 0
}
if (-not $env:GH_TOKEN) {
    Write-Host '[check_promotion_authorization] ERROR - GH_TOKEN is required in pull_request CI.' -ForegroundColor Red
    exit 2
}

$event = Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
$repo = "$($event.repository.full_name)"
$number = [int]$event.pull_request.number
$eventHeadSha = "$($event.pull_request.head.sha)".ToLowerInvariant()
$prLine = @(Invoke-GhLines @('api', "repos/$repo/pulls/$number", '--jq', '[.head.sha, .head.repo.full_name] | @tsv'))
if ($prLine.Count -ne 1) {
    Write-Host "[check_promotion_authorization] ERROR - could not resolve live PR #$number head." -ForegroundColor Red
    exit 2
}
$prParts = $prLine[0] -split "`t", 2
$headSha = "$($prParts[0])".ToLowerInvariant()
$headRepo = if ($prParts.Count -gt 1) { "$($prParts[1])" } else { '' }
if ($headSha -ne $eventHeadSha) {
    Write-Host "[check_promotion_authorization] ERROR - workflow event head $eventHeadSha is stale; live PR head is $headSha. Use the current run." -ForegroundColor Red
    exit 2
}
$isFork = $headRepo -ne $repo

$paths = @(Invoke-GhLines @('api', '--paginate', "repos/$repo/pulls/$number/files?per_page=100", '--jq', '.[].filename'))
$stablePathChanged = $false
foreach ($path in $paths) {
    $top = ("$path".Replace('\', '/') -split '/')[0]
    if ($STABLE_DIRS -contains $top) { $stablePathChanged = $true; break }
}
if ($isFork -and $stablePathChanged) {
    Write-Host "[check_promotion_authorization] ERROR - fork PR #$number cannot carry a stable promotion." -ForegroundColor Red
    exit 2
}
$readPrSource = {
    param([string]$Path)
    Invoke-GhRaw @('api', '-H', 'Accept: application/vnd.github.raw+json', "repos/$repo/contents/$Path`?ref=$headSha")
}
$requests = @(Get-StablePromotionRequests -Paths $paths -Root $root -ReadSource $readPrSource)
if ($requests.Count -eq 0) {
    if (-not $Quiet) { Write-Host "[check_promotion_authorization] OK - PR #$number changes no split-mod stable directory." -ForegroundColor Green }
    exit 0
}

$labels = @(Invoke-GhLines @('api', "repos/$repo/pulls/$number", '--jq', '.labels[].name'))
$eventLines = @(Invoke-GhLines @('api', '--paginate', "repos/$repo/issues/$number/events?per_page=100", '--jq', '.[] | select(.event == "labeled" or .event == "unlabeled") | [.event, (.label.name // ""), .actor.login, .created_at] | @tsv'))
$labelEvents = @()
foreach ($line in $eventLines) {
    $parts = $line -split "`t", 4
    if ($parts.Count -eq 4) {
        $labelEvents += [pscustomobject]@{ Event = $parts[0]; Label = $parts[1]; Actor = $parts[2]; CreatedAt = $parts[3] }
    }
}

$commentLines = @(Invoke-GhLines @('api', '--paginate', "repos/$repo/issues/$number/comments?per_page=100", '--jq', '.[] | [.id, .user.login, .created_at, .updated_at, (.body | @base64)] | @tsv'))
$comments = @()
foreach ($line in $commentLines) {
    $parts = $line -split "`t", 5
    if ($parts.Count -eq 5) {
        $body = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[4]))
        $comments += [pscustomobject]@{ Id = $parts[0]; Author = $parts[1]; CreatedAt = $parts[2]; UpdatedAt = $parts[3]; Body = $body }
    }
}

$actors = @($labelEvents.Actor + $comments.Author | Sort-Object -Unique)
$permissions = @{}
foreach ($actor in $actors) {
    try {
        $value = @(Invoke-GhLines @('api', "repos/$repo/collaborators/$actor/permission", '--jq', '.permission'))
        $permissions[$actor] = if ($value.Count -gt 0) { $value[0] } else { 'none' }
    } catch {
        # Non-collaborator commenters return 404. Treat every lookup failure as
        # untrusted; authorization remains fail-closed.
        $permissions[$actor] = 'none'
    }
}

$context = [pscustomobject]@{
    IsFork = $isFork
    HeadSha = $headSha
    Requests = $requests
    Labels = $labels
    LabelEvents = $labelEvents
    Comments = $comments
    Permissions = $permissions
}
$result = Test-PromotionAuthorization -Context $context
if (-not $result.Allowed) {
    Write-Host "[check_promotion_authorization] ERROR - PR #$number stable promotion is not authorized: $($result.Reason)." -ForegroundColor Red
    foreach ($request in $requests) {
        Write-Host "  Required comment: VT2-Promotion-Approval: $($request.Dir)@$($request.Version) head=$headSha" -ForegroundColor Yellow
    }
    Write-Host "  A maintainer must post the exact line(s), then apply '$APPROVAL_LABEL'. Remove the label to revoke." -ForegroundColor Yellow
    exit 2
}

$dirs = @($requests.Dir | Sort-Object -Unique)
Write-Host "[check_promotion_authorization] AUTHORIZED pr=$number head=$headSha dirs=$($dirs -join ',') versions=$((@($requests | ForEach-Object { $_.Dir + '@' + $_.Version })) -join ',') authorizer=$($result.Author) comment=$($result.CommentId) granted=$($result.GrantedAt)" -ForegroundColor Green

if ($WriteGitHubEnv) {
    if (-not $env:GITHUB_ENV) {
        Write-Host '[check_promotion_authorization] ERROR - GITHUB_ENV is unavailable.' -ForegroundColor Red
        exit 2
    }
    $lines = "VT2_PROMOTION=1`nVT2_PROMOTION_DIRS=$($dirs -join ';')`n"
    [System.IO.File]::AppendAllText($env:GITHUB_ENV, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

exit 0
