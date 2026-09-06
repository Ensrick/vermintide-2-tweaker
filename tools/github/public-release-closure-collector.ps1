# #1527: bounded, read-only collection for the existing closure policy.
# The trusted caller supplies authenticated GraphQL transport and retained
# closure-time authority. No CLI, workflow, writes, retries, or archive owner.
. (Join-Path $PSScriptRoot '../verify/public_release_closure_policy.ps1')

function Get-VtClosureCollectorQuery {
    return @'
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    nameWithOwner
    issue(number: $number) {
      id number state updatedAt closedAt
      labels(first: 100) {
        nodes { name }
        totalCount pageInfo { hasNextPage endCursor }
      }
      timelineItems(last: 1, itemTypes: [CLOSED_EVENT, REOPENED_EVENT]) {
        totalCount
        nodes {
          __typename
          ... on ClosedEvent { id createdAt }
          ... on ReopenedEvent { id createdAt }
        }
      }
      comments(first: 100, after: $after) {
        totalCount pageInfo { hasNextPage endCursor }
        nodes { databaseId body createdAt updatedAt isPinned authorAssociation author { login } }
      }
    }
  }
}
'@
}

function Test-VtClosureCollectorInteger {
    param($Value, [long]$Minimum, [long]$Maximum)
    return ($Value -is [int] -or $Value -is [long]) -and
        $Value -ge $Minimum -and $Value -le $Maximum
}

function Get-VtClosureCollectorPage {
    # GraphQL's initial cursor is literal null. A typed string parameter
    # coerces null to "", which is a different opaque cursor on the wire.
    param($Context, [AllowNull()][object]$After)
    if ($Context.RequestCount -ge 44 -or $Context.Timer.ElapsedMilliseconds -ge $Context.DeadlineMilliseconds) {
        throw 'closure-collector:request-budget'
    }
    $Context.RequestCount++
    try {
        $response = & $Context.Request (Get-VtClosureCollectorQuery) @{
            owner=$Context.Owner; name=$Context.Name; number=$Context.Number; after=$After
        }
    } catch { throw 'closure-collector:github-request-failed' }
    # The callback must itself bound transport time/response bytes. This budget
    # refuses further requests after an overrun; it cannot preempt a callback.
    if ($Context.Timer.ElapsedMilliseconds -ge $Context.DeadlineMilliseconds) {
        throw 'closure-collector:request-budget'
    }
    if ($null -eq $response -or $null -ne $response.errors -or
            $null -eq $response.data -or $null -eq $response.data.repository -or
            $response.data.repository.nameWithOwner -isnot [string] -or
            $response.data.repository.nameWithOwner -cne $Context.Repository) {
        throw 'closure-collector:github-envelope-or-repository'
    }
    $issue = $response.data.repository.issue
    if ($null -eq $issue -or -not (Test-VtClosureCollectorInteger $issue.number 1 ([int]::MaxValue)) -or
            $issue.number -ne $Context.Number -or $issue.id -isnot [string] -or
            $issue.id -cnotmatch '^[A-Za-z0-9_=-]{1,200}$' -or
            $issue.state -isnot [string] -or $issue.state -cnotin @('OPEN','CLOSED') -or
            $null -eq $issue.PSObject.Properties['closedAt'] -or
            $null -eq (ConvertTo-VtClosureTime $issue.updatedAt)) {
        throw 'closure-collector:issue-identity-or-metadata'
    }
    $labels = $issue.labels
    if ($null -eq $labels -or $null -eq $labels.nodes -or
            -not (Test-VtClosureCollectorInteger $labels.totalCount 0 100) -or
            $labels.pageInfo.hasNextPage -isnot [bool] -or $labels.pageInfo.hasNextPage -or
            @($labels.nodes).Count -ne $labels.totalCount) {
        throw 'closure-collector:labels-incomplete'
    }
    $labelNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($label in @($labels.nodes)) {
        if ($label.name -isnot [string] -or [string]::IsNullOrWhiteSpace($label.name) -or
                $label.name.Length -gt 100 -or -not $labelNames.Add($label.name)) {
            throw 'closure-collector:labels-invalid'
        }
    }
    $timeline = $issue.timelineItems
    if ($null -eq $timeline -or $null -eq $timeline.nodes -or
            -not (Test-VtClosureCollectorInteger $timeline.totalCount 0 ([int]::MaxValue)) -or
            @($timeline.nodes).Count -ne [Math]::Min(1, $timeline.totalCount)) {
        throw 'closure-collector:closure-tail-incomplete'
    }
    $event = if ($timeline.totalCount -gt 0) { @($timeline.nodes)[0] } else { $null }
    if ($null -ne $event -and ($event.__typename -isnot [string] -or
            $event.__typename -cnotin @('ClosedEvent','ReopenedEvent') -or
            $event.id -isnot [string] -or $event.id -cnotmatch '^[A-Za-z0-9_=-]{1,200}$' -or
            $null -eq (ConvertTo-VtClosureTime $event.createdAt))) {
        throw 'closure-collector:closure-tail-invalid'
    }
    if ($issue.state -ceq 'CLOSED') {
        if ($null -eq (ConvertTo-VtClosureTime $issue.closedAt) -or $null -eq $event -or
                $event.__typename -cne 'ClosedEvent' -or $event.createdAt -cne $issue.closedAt -or
                (ConvertTo-VtClosureTime $issue.updatedAt) -lt (ConvertTo-VtClosureTime $issue.closedAt)) {
            throw 'closure-collector:closure-generation-mismatch'
        }
    } elseif ($null -ne $issue.closedAt -or ($null -ne $event -and $event.__typename -cne 'ReopenedEvent')) {
        throw 'closure-collector:open-generation-mismatch'
    }
    $connection = $issue.comments
    if ($null -eq $connection -or $null -eq $connection.nodes -or
            -not (Test-VtClosureCollectorInteger $connection.totalCount 0 2048) -or
            $connection.pageInfo.hasNextPage -isnot [bool] -or @($connection.nodes).Count -gt 100) {
        throw 'closure-collector:comments-connection-incomplete'
    }
    # Fixed-order serialization is only an in-process race comparison, never
    # a signature or a substitute for source/artifact authority.
    $metadata = [ordered]@{
        id=$issue.id; number=$issue.number; state=$issue.state; updatedAt=$issue.updatedAt
        closedAt=$issue.closedAt; labels=@($labels.nodes | ForEach-Object { $_.name })
        eventCount=$timeline.totalCount; eventId=$event.id; eventType=$event.__typename
        eventCreatedAt=$event.createdAt; commentCount=$connection.totalCount
    } | ConvertTo-Json -Depth 4 -Compress
    return [pscustomobject]@{ Issue=$issue; Event=$event; Connection=$connection; Metadata=$metadata }
}

function Get-VtClosureCollectorPass {
    param($Context)
    $after=$null; $metadata=$null; $first=$null; $bytes=0L
    $comments=New-Object 'Collections.Generic.List[object]'
    $ids=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $cursors=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $utf8=New-Object Text.UTF8Encoding($false, $true)
    do {
        $page=Get-VtClosureCollectorPage -Context $Context -After $after
        if ($null -eq $first) { $first=$page; $metadata=$page.Metadata }
        elseif ($metadata -cne $page.Metadata) { throw 'closure-collector:issue-changed-during-pagination' }
        foreach ($comment in @($page.Connection.nodes)) {
            if (-not (Test-VtClosureCollectorInteger $comment.databaseId 1 ([long]::MaxValue)) -or
                    -not $ids.Add([string]$comment.databaseId) -or $comment.body -isnot [string] -or
                    $comment.isPinned -isnot [bool] -or
                    $comment.authorAssociation -isnot [string] -or
                    $comment.authorAssociation -cnotin @('COLLABORATOR','CONTRIBUTOR','FIRST_TIMER',
                        'FIRST_TIME_CONTRIBUTOR','MANNEQUIN','MEMBER','NONE','OWNER') -or
                    $null -eq (ConvertTo-VtClosureTime $comment.createdAt) -or
                    $null -eq (ConvertTo-VtClosureTime $comment.updatedAt) -or
                    (ConvertTo-VtClosureTime $comment.updatedAt) -lt (ConvertTo-VtClosureTime $comment.createdAt) -or
                    $null -eq $comment.PSObject.Properties['author']) {
                throw 'closure-collector:comment-metadata-invalid'
            }
            $length=$utf8.GetByteCount($comment.body); $bytes+=$length
            if ($length -gt 1048576 -or $bytes -gt 16777216 -or $comments.Count -ge 2048) {
                throw 'closure-collector:comment-byte-or-count-bound'
            }
            $login=if ($null -ne $comment.author) { $comment.author.login } else { $null }
            if ($null -ne $comment.author -and ($login -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($login) -or $login.Length -gt 100)) {
                throw 'closure-collector:comment-author-invalid'
            }
            $comments.Add([pscustomobject][ordered]@{
                databaseId=[string]$comment.databaseId; body=$comment.body
                createdAt=$comment.createdAt; updatedAt=$comment.updatedAt; isPinned=$comment.isPinned
                authorAssociation=$comment.authorAssociation
                author=$(if ($null -eq $login) { $null } else { [pscustomobject]@{login=$login} })
            })
        }
        if ($comments.Count -gt $page.Connection.totalCount) { throw 'closure-collector:comment-count-mismatch' }
        $more=$page.Connection.pageInfo.hasNextPage
        if ($more) {
            $after=$page.Connection.pageInfo.endCursor
            if ($after -isnot [string] -or [string]::IsNullOrWhiteSpace($after) -or
                    $after.Length -gt 512 -or -not $cursors.Add($after) -or
                    @($page.Connection.nodes).Count -eq 0 -or $comments.Count -ge $page.Connection.totalCount) {
                throw 'closure-collector:pagination-no-progress'
            }
        } elseif ($comments.Count -ne $page.Connection.totalCount) {
            throw 'closure-collector:comments-truncated'
        }
    } while ($more)
    return [pscustomobject]@{ Page=$first; Comments=$comments.ToArray(); BodyBytes=$bytes }
}

function Get-VtGitHubPublicReleaseClosureAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][int]$IssueNumber,
        [Parameter(Mandatory=$true)][scriptblock]$Request,
        [string]$AttestationId,
        $AuthoritySnapshot,
        [Parameter(Mandatory=$true)][string]$EnforceFromUtc,
        [string[]]$TrustedVerifier=@('Ensrick','RainReligion'),
        [ValidateRange(1,60000)][int]$DeadlineMilliseconds=30000
    )
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $context=$null; $issue=$null; $snapshot=$null
    try {
        if ($Repository -cnotmatch '^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$' -or $IssueNumber -le 0) {
            throw 'closure-collector:invalid-scope'
        }
        $context=[pscustomobject]@{
            Repository=$Repository; Owner=$Matches[1]; Name=$Matches[2]; Number=$IssueNumber
            Request=$Request; RequestCount=0; Timer=$timer; DeadlineMilliseconds=$DeadlineMilliseconds
        }
        $first=Get-VtClosureCollectorPass $context
        $second=Get-VtClosureCollectorPass $context
        if ($first.Page.Metadata -cne $second.Page.Metadata -or
                $first.Comments.Count -ne $second.Comments.Count) {
            throw 'closure-collector:issue-changed-between-passes'
        }
        for ($i=0; $i -lt $first.Comments.Count; $i++) {
            if (($first.Comments[$i] | ConvertTo-Json -Depth 3 -Compress) -cne
                    ($second.Comments[$i] | ConvertTo-Json -Depth 3 -Compress)) {
                throw 'closure-collector:comment-or-pin-changed-between-passes'
            }
        }
        $observed=[DateTimeOffset]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture).Replace('+00:00','Z')
        $raw=$second.Page.Issue
        if ((ConvertTo-VtClosureTime $raw.updatedAt) -gt (ConvertTo-VtClosureTime $observed)) {
            throw 'closure-collector:future-issue-metadata'
        }
        $issue=[pscustomobject]@{
            Complete=$true; repository=$Repository; number=$raw.number; state=$raw.state
            labels=@($raw.labels.nodes | ForEach-Object { [pscustomobject]@{name=$_.name} })
            closedAt=$raw.closedAt; closureEventId=$second.Page.Event.id
        }
        $snapshot=[pscustomobject]@{
            Complete=$true; PinsComplete=$true; ObservedAt=$observed; Comments=$second.Comments
        }
        $decision=Get-VtPublicReleaseClosureDecision -Repository $Repository -Issue $issue `
            -CommentSnapshot $snapshot -AttestationId $AttestationId -AuthoritySnapshot $AuthoritySnapshot `
            -EnforceFromUtc $EnforceFromUtc -TrustedVerifier $TrustedVerifier
    } catch {
        $reason='closure-collector:invalid-or-unavailable-snapshot'
        if ($_.Exception.Message -cmatch '^closure-collector:[a-z-]+$') { $reason=$_.Exception.Message }
        $decision=New-VtClosureDecision 'Unavailable' $reason
        $issue=$null; $snapshot=$null
    } finally { $timer.Stop() }
    return [pscustomobject]@{
        MayMutate=$false; Decision=$decision; Issue=$issue; CommentSnapshot=$snapshot
        Collection=[pscustomobject]@{
            Source='github-graphql-one-issue/v1'; RequestCount=$(if ($context) { $context.RequestCount } else { 0 })
            ElapsedMilliseconds=$timer.ElapsedMilliseconds
        }
    }
}
