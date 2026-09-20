# Issue #1527: deterministic retained-evidence candidate and action planner.
#
# This library is deliberately pure. It does not read or write a filesystem,
# contact GitHub, inspect ambient credentials, or authorize issue mutation. A
# digest proves only internal integrity; it is not authentication. A future
# trusted storage/event owner must authenticate the complete package before it
# can be used as durable enforcement evidence.
. (Join-Path $PSScriptRoot 'public_release_closure_policy.ps1')

function Add-VtClosureCanonicalJsonValue {
    param(
        [Parameter(Mandatory=$true)][Text.StringBuilder]$Builder,
        [AllowNull()]$Value,
        [int]$Depth = 0
    )
    if ($Depth -gt 32) { throw 'canonical evidence exceeds maximum depth' }
    if ($null -eq $Value) { $null=$Builder.Append('null'); return }
    if ($Value -is [bool]) { $null=$Builder.Append($(if($Value){'true'}else{'false'})); return }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
            $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
            $Value -is [int64]) {
        $null=$Builder.Append(([Convert]::ToString($Value,[Globalization.CultureInfo]::InvariantCulture))); return
    }
    if ($Value -is [string]) {
        # Validate UTF-16 before serializing so lone surrogates are never
        # normalized differently by PS5 and PS7.
        $utf8=New-Object Text.UTF8Encoding($false,$true)
        $null=$utf8.GetByteCount($Value)
        $null=$Builder.Append('"')
        foreach($character in $Value.ToCharArray()) {
            $code=[int][char]$character
            switch($code) {
                8 {$null=$Builder.Append('\b');continue}; 9 {$null=$Builder.Append('\t');continue}
                10 {$null=$Builder.Append('\n');continue}; 12 {$null=$Builder.Append('\f');continue}
                13 {$null=$Builder.Append('\r');continue}; 34 {$null=$Builder.Append('\"');continue}
                92 {$null=$Builder.Append('\\');continue}
            }
            if($code -lt 32) { $null=$Builder.Append(('\u{0:x4}' -f $code)) }
            else { $null=$Builder.Append($character) }
        }
        $null=$Builder.Append('"'); return
    }
    if ($Value -is [Collections.IDictionary]) {
        $names=@($Value.Keys | ForEach-Object { if($_ -isnot [string]){throw 'canonical object key is not a string'}; [string]$_ })
        $unique=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($name in $names){if(-not$unique.Add($name)){throw 'duplicate canonical object key'}}
        [Array]::Sort($names,[StringComparer]::Ordinal)
        $null=$Builder.Append('{');$first=$true
        foreach($name in $names){
            if(-not$first){$null=$Builder.Append(',')};$first=$false
            Add-VtClosureCanonicalJsonValue $Builder $name ($Depth+1);$null=$Builder.Append(':')
            Add-VtClosureCanonicalJsonValue $Builder $Value[$name] ($Depth+1)
        }
        $null=$Builder.Append('}'); return
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [Management.Automation.PSCustomObject]) {
        $null=$Builder.Append('[');$first=$true
        foreach($item in $Value){
            if(-not$first){$null=$Builder.Append(',')};$first=$false
            Add-VtClosureCanonicalJsonValue $Builder $item ($Depth+1)
        }
        $null=$Builder.Append(']'); return
    }
    $properties=@($Value.PSObject.Properties | Where-Object {$_.MemberType -in @('NoteProperty','Property')})
    if($properties.Count -eq 0){throw ('unsupported canonical evidence type: '+$Value.GetType().FullName)}
    $map=[ordered]@{}
    foreach($property in $properties){
        if($map.Contains($property.Name)){throw 'duplicate canonical property'}
        $map[$property.Name]=$property.Value
    }
    Add-VtClosureCanonicalJsonValue $Builder $map ($Depth+1)
}

function ConvertTo-VtClosureCanonicalJson {
    param([Parameter(Mandatory=$true)]$Value)
    $builder=New-Object Text.StringBuilder
    Add-VtClosureCanonicalJsonValue $builder $Value
    return $builder.ToString()
}

function Get-VtClosureCanonicalSha256 {
    param([Parameter(Mandatory=$true)]$Value)
    return Get-VtClosureBodySha256 (ConvertTo-VtClosureCanonicalJson $Value)
}

function New-VtPublicReleaseClosureEvidenceCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Audit,
        [Parameter(Mandatory=$true)]$AuthoritySnapshot
    )
    if($Audit.MayMutate -isnot [bool] -or $Audit.MayMutate -or $null -eq $Audit.Issue -or
            $null -eq $Audit.Decision -or $null -eq $Audit.CommentSnapshot) {
        throw 'audit is not a complete read-only closure result'
    }
    $issue=$Audit.Issue;$decision=$Audit.Decision;$comments=$Audit.CommentSnapshot
    if($issue.Complete -isnot [bool] -or -not$issue.Complete -or
            [string]$issue.repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
            [string]$issue.number -cnotmatch '^[1-9][0-9]*$' -or
            [string]$issue.closureEventId -cnotmatch '^[A-Za-z0-9_=-]{1,200}$' -or
            $AuthoritySnapshot.Complete -isnot [bool] -or -not$AuthoritySnapshot.Complete -or
            [string]$AuthoritySnapshot.Repository -cne [string]$issue.repository -or
            [string]$AuthoritySnapshot.ClosedEventId -cne [string]$issue.closureEventId -or
            [string]$AuthoritySnapshot.ClosedAt -cne [string]$issue.closedAt -or
            [string]$AuthoritySnapshot.PolicySourceCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'closure evidence inputs are incomplete or generation-mismatched'
    }
    $payload=[ordered]@{
        Schema=1
        Repository=[string]$issue.repository
        IssueNumber=[int64]$issue.number
        ClosureKey=[string]$decision.ClosureKey
        ClosedEventId=[string]$issue.closureEventId
        ClosedAt=[string]$issue.closedAt
        CapturedAt=[string]$comments.ObservedAt
        PolicySourceCommit=[string]$AuthoritySnapshot.PolicySourceCommit
        IssueSnapshot=$issue
        CommentSnapshot=$comments
        AuthoritySnapshot=$AuthoritySnapshot
        Decision=$decision
    }
    $digest=Get-VtClosureCanonicalSha256 $payload
    return [pscustomobject]@{
        Schema=1; Kind='public-release-closure-evidence-candidate/v1'
        Digest=$digest; Payload=[pscustomobject]$payload
        Authenticated=$false; MayMutate=$false
    }
}

function Test-VtPublicReleaseClosureEvidenceCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Evidence)
    try {
        $valid=$Evidence.Schema -eq 1 -and
            $Evidence.Kind -ceq 'public-release-closure-evidence-candidate/v1' -and
            $Evidence.Digest -is [string] -and $Evidence.Digest -cmatch '^[0-9a-f]{64}$' -and
            $Evidence.Authenticated -is [bool] -and -not$Evidence.Authenticated -and
            $Evidence.MayMutate -is [bool] -and -not$Evidence.MayMutate -and
            $null -ne $Evidence.Payload -and
            (Get-VtClosureCanonicalSha256 $Evidence.Payload) -ceq $Evidence.Digest -and
            $Evidence.Payload.Schema -eq 1 -and
            $Evidence.Payload.Repository -ceq $Evidence.Payload.IssueSnapshot.repository -and
            [string]$Evidence.Payload.IssueNumber -ceq [string]$Evidence.Payload.IssueSnapshot.number -and
            $Evidence.Payload.ClosedEventId -ceq $Evidence.Payload.IssueSnapshot.closureEventId -and
            $Evidence.Payload.ClosedAt -ceq $Evidence.Payload.IssueSnapshot.closedAt -and
            $Evidence.Payload.ClosureKey -ceq $Evidence.Payload.Decision.ClosureKey -and
            $Evidence.Payload.PolicySourceCommit -ceq $Evidence.Payload.AuthoritySnapshot.PolicySourceCommit
        return [pscustomobject]@{Valid=[bool]$valid;Authenticated=$false;MayMutate=$false;
            Reason=$(if($valid){'candidate-integrity-valid'}else{'candidate-integrity-invalid'})}
    } catch {
        return [pscustomobject]@{Valid=$false;Authenticated=$false;MayMutate=$false;Reason='candidate-integrity-error'}
    }
}

function Get-VtPublicReleaseClosureActionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Audit,
        $EvidenceCandidate
    )
    $decision=$Audit.Decision
    $status=[string]$decision.Status;$reason=[string]$decision.Reason
    $disposition='Unavailable';$required='retry-complete-authenticated-collection'
    if($status -ceq 'Accepted'){$disposition='Accepted';$required='persist-with-authenticated-retained-evidence-owner'}
    elseif($status -ceq 'Rejected' -and $reason -ceq 'missing-attestation'){$disposition='Pending';$required='record-structured-attestation-for-this-closure-generation'}
    elseif($status -ceq 'Rejected'){$disposition='Rejected';$required='maintainer-review-of-bound-rejection'}
    elseif($status -ceq 'NotApplicable'){$disposition='NotApplicable';$required='none'}
    elseif($status -ceq 'LegacyReviewRequired'){$disposition='LegacyReviewRequired';$required='explicit-legacy-migration-review'}
    $evidenceDigest=$null;$candidateValid=$false
    if($null -ne $EvidenceCandidate){
        $check=Test-VtPublicReleaseClosureEvidenceCandidate $EvidenceCandidate
        $candidateValid=$check.Valid
        if($candidateValid){$evidenceDigest=[string]$EvidenceCandidate.Digest}
    }
    $identity=[ordered]@{Schema=1;ClosureKey=[string]$decision.ClosureKey;Status=$status;Reason=$reason;EvidenceDigest=$evidenceDigest}
    return [pscustomobject]@{
        Schema=1;Disposition=$disposition;RequiredNext=$required
        ClosureKey=[string]$decision.ClosureKey
        IntentKey=(Get-VtClosureCanonicalSha256 $identity)
        EvidenceCandidateValid=$candidateValid;EvidenceAuthenticated=$false
        Action='observe-only';MayMutate=$false
    }
}
