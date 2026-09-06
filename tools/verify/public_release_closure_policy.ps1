# Issue #1527: deterministic public-release closure attestation policy.
# No GitHub, Git, filesystem writes, clock reads, or issue mutations. Inputs
# must be complete authenticated snapshots supplied by a trusted caller.
. (Join-Path $PSScriptRoot 'lifecycle_method_policy.ps1')

function Get-VtClosureBodySha256 {
    param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Body)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $utf8 = New-Object Text.UTF8Encoding($false, $true)
        return ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($Body)))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function ConvertTo-VtClosureTime {
    param($Value)
    if ($Value -isnot [string] -or $Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') { return $null }
    $time = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$time)) { return $null }
    return $time
}

function Test-VtClosureDecimalId {
    param($Value)
    $number = 0L
    return $Value -is [string] -and $Value -cmatch '^[1-9][0-9]{0,18}$' -and
        [long]::TryParse($Value, [ref]$number) -and $number -gt 0
}

function New-VtClosureDecision {
    param([string]$Status, [string]$Reason, [string]$ClosureKey, $Proof)
    return [pscustomobject]@{
        Status=$Status; Valid=($Status -ceq 'Accepted'); Reason=$Reason
        ClosureKey=$ClosureKey; Proof=$Proof; MayMutate=$false
    }
}

function ConvertFrom-VtClosureAttestation {
    param([string]$Body)
    # Flat, closed schema. Reject duplicate/escaped property names before the
    # PS5/PS7 JSON parsers can disagree about last-value-wins interpretation.
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    if ($utf8.GetByteCount($Body) -gt 16384) { return $null }
    $match = [regex]::Match($Body, '\A## PUBLIC RELEASE CLOSURE ATTESTATION\r?\n\s*```json\r?\n(?<json>.+?)\r?\n```\s*\z', 'Singleline')
    if (-not $match.Success) { return $null }
    $json = $match.Groups['json'].Value
    $fields = @('Schema','Repository','IssueNumber','ClosedEventId','ClosedAt','VerifiedAt',
        'VerifierLogin','VerifierAssociation','CardId','CardSha256','EvidenceId','EvidenceSha256',
        'Outcome','ModId','Dir','Stream','WorkshopId','Version','SourceCommit','RootBundle',
        'RootBundleSha256','AssetFilename','AssetSha256')
    $keys = @([regex]::Matches($json, '"(?<key>(?:\\.|[^"\\])*)"\s*:'))
    if ($keys.Count -ne $fields.Count) { return $null }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($key in $keys) {
        $name = $key.Groups['key'].Value
        if ($fields -cnotcontains $name -or -not $seen.Add($name)) { return $null }
    }
    try { $value = $json | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($null -eq $value -or @($value.PSObject.Properties).Count -ne $fields.Count) { return $null }
    # ConvertFrom-Json date coercion differs by host version. Take the two
    # deliberately unescaped UTC string tokens from the same parsed flat JSON.
    foreach ($field in @('ClosedAt','VerifiedAt')) {
        $token = [regex]::Match($json, ('"' + $field + '"\s*:\s*"(?<time>[0-9TZ:.-]+)"'))
        if (-not $token.Success) { return $null }
        $value.$field = $token.Groups['time'].Value
    }
    if (($value.Schema -isnot [int] -and $value.Schema -isnot [long]) -or $value.Schema -ne 1) { return $null }
    if (($value.IssueNumber -isnot [int] -and $value.IssueNumber -isnot [long]) -or $value.IssueNumber -le 0) { return $null }
    foreach ($field in $fields) {
        if ($field -in @('Schema','IssueNumber')) { continue }
        if ($value.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($value.$field)) { return $null }
    }
    foreach ($field in @('CardId','EvidenceId','WorkshopId')) {
        if (-not (Test-VtClosureDecimalId $value.$field)) { return $null }
    }
    foreach ($field in @('CardSha256','EvidenceSha256','RootBundleSha256','AssetSha256')) {
        if ($value.$field -cnotmatch '^[0-9a-f]{64}$') { return $null }
    }
    if ($value.SourceCommit -cnotmatch '^[0-9a-f]{40}$') { return $null }
    return $value
}

function Get-VtPublicReleaseClosureDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)]$Issue,
        $CommentSnapshot,
        [string]$AttestationId,
        $AuthoritySnapshot,
        [Parameter(Mandatory=$true)][string]$EnforceFromUtc,
        [string[]]$TrustedVerifier = @('Ensrick','RainReligion')
    )
    $key = $null
    try {
        # Not an event runner: even a Rejected decision never grants mutation.
        if ($Issue.Complete -isnot [bool] -or -not $Issue.Complete -or $null -eq $Issue.labels -or
                $Repository -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
                [string]$Issue.repository -cne $Repository -or [string]$Issue.number -cnotmatch '^[1-9][0-9]*$' -or
                [string]$Issue.state -inotmatch '^(OPEN|CLOSED)$') {
            return New-VtClosureDecision 'Unavailable' 'issue-snapshot-incomplete' $key
        }
        if (@(Get-VtLabelNames $Issue) -notcontains 'public-release') {
            return New-VtClosureDecision 'NotApplicable' 'not-public-release' $key
        }
        if ([string]$Issue.state -ieq 'OPEN') {
            return New-VtClosureDecision 'NotApplicable' 'issue-not-closed' $key
        }
        $closed = ConvertTo-VtClosureTime $Issue.closedAt
        $enforce = ConvertTo-VtClosureTime $EnforceFromUtc
        if ($null -eq $closed -or $null -eq $enforce -or
                [string]$Issue.closureEventId -cnotmatch '^[A-Za-z0-9_=-]{1,200}$') {
            return New-VtClosureDecision 'Unavailable' 'closure-generation-unavailable' $key
        }
        $key = '{0}#{1}:{2}' -f $Repository, $Issue.number, $Issue.closureEventId
        if ($closed -lt $enforce) {
            return New-VtClosureDecision 'LegacyReviewRequired' 'predates-attestation-policy' $key
        }
        if ($null -eq $CommentSnapshot -or $CommentSnapshot.Complete -isnot [bool] -or
                -not $CommentSnapshot.Complete -or $CommentSnapshot.PinsComplete -isnot [bool] -or
                -not $CommentSnapshot.PinsComplete -or $null -eq $CommentSnapshot.Comments) {
            return New-VtClosureDecision 'Unavailable' 'comment-or-pin-snapshot-incomplete' $key
        }
        $observed = ConvertTo-VtClosureTime $CommentSnapshot.ObservedAt
        $comments = @($CommentSnapshot.Comments)
        if ($null -eq $observed -or $observed -lt $closed -or $comments.Count -gt 2048) {
            return New-VtClosureDecision 'Unavailable' 'comment-snapshot-bounds-or-time' $key
        }
        $byId = @{}; $bodyBytes = 0L
        $utf8 = New-Object Text.UTF8Encoding($false, $true)
        foreach ($comment in $comments) {
            $id = [string]$comment.databaseId
            $created = ConvertTo-VtClosureTime $comment.createdAt
            $updated = ConvertTo-VtClosureTime $comment.updatedAt
            if (-not (Test-VtClosureDecimalId $id) -or $byId.ContainsKey($id) -or
                    $comment.body -isnot [string] -or $null -eq $created -or $null -eq $updated -or
                    $updated -lt $created -or $updated -gt $observed) {
                return New-VtClosureDecision 'Unavailable' 'comment-metadata-incomplete' $key
            }
            $length = $utf8.GetByteCount($comment.body)
            $bodyBytes += $length
            if ($length -gt 1048576 -or $bodyBytes -gt 16777216) {
                return New-VtClosureDecision 'Unavailable' 'comment-snapshot-too-large' $key
            }
            if ((Test-VtCurrentLiveTestCard $comment.body) -and $comment.isPinned -isnot [bool]) {
                return New-VtClosureDecision 'Unavailable' 'card-pin-state-unavailable' $key
            }
            $byId[$id] = $comment
        }
        if ($null -eq $AuthoritySnapshot -or $AuthoritySnapshot.Complete -isnot [bool] -or
                -not $AuthoritySnapshot.Complete -or $AuthoritySnapshot.Source -cne 'deployed-source-contract/v1' -or
                $AuthoritySnapshot.Repository -cne $Repository -or
                $AuthoritySnapshot.ClosedEventId -cne [string]$Issue.closureEventId -or
                $AuthoritySnapshot.ClosedAt -cne [string]$Issue.closedAt -or
                [string]$AuthoritySnapshot.PolicySourceCommit -cnotmatch '^[0-9a-f]{40}$' -or
                $null -eq $AuthoritySnapshot.Authority -or $null -eq $AuthoritySnapshot.Authority.Records -or
                @($AuthoritySnapshot.Authority.Records).Count -eq 0 -or @($AuthoritySnapshot.Authority.Records).Count -gt 256) {
            return New-VtClosureDecision 'Unavailable' 'closure-time-authority-unavailable' $key
        }
        # Canonical case is preserved (including WOC), but two case aliases
        # cannot coexist: the upstream source/inventory resolver rejects them.
        $authorityIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $authorityDirs = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $authorityWorkshopIds = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($record in @($AuthoritySnapshot.Authority.Records)) {
            foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version',
                    'AssetFilename','AssetSha256')) {
                if ($record.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($record.$field)) {
                    return New-VtClosureDecision 'Unavailable' 'authority-record-incomplete' $key
                }
            }
            foreach ($field in @('LoadRoutes','ExactBannerRoutes','CommandRoutes','ReceiptRoutes','MenuSurfaces')) {
                if ($null -eq $record.$field) {
                    return New-VtClosureDecision 'Unavailable' 'authority-routes-incomplete' $key
                }
            }
            # A complete trusted source snapshot can include unrelated carried
            # legacy assets. Its resolver already authenticated their exact
            # LegacySourceTrees identity/version and root->mod tree mapping.
            # Null is explicit legacy provenance, never a fabricated commit;
            # missing, empty or malformed modern source identities still fail.
            $sourceProperty=$record.PSObject.Properties['SourceCommit']
            if ($null -eq $sourceProperty) {
                return New-VtClosureDecision 'Unavailable' 'authority-record-incomplete' $key
            }
            if ($null -eq $record.SourceCommit) {
                foreach ($field in @('RootTree','ModTree')) {
                    if ($record.$field -isnot [string] -or $record.$field -cnotmatch '^[0-9a-f]{40}$') {
                        return New-VtClosureDecision 'Unavailable' 'authority-record-incomplete' $key
                    }
                }
            } elseif ($record.SourceCommit -isnot [string] -or $record.SourceCommit -cnotmatch '^[0-9a-f]{40}$') {
                return New-VtClosureDecision 'Unavailable' 'authority-record-incomplete' $key
            }
            # Old pinned ZIPs can predate root-bundle metadata as well. Preserve
            # their explicit null pair; never fill it from a newer release.
            if ($null -eq $record.PSObject.Properties['RootBundle'] -or
                    $null -eq $record.PSObject.Properties['RootBundleSha256']) {
                return New-VtClosureDecision 'Unavailable' 'authority-record-incomplete' $key
            }
            $legacyWithoutRoot=$null -eq $record.SourceCommit -and
                $null -eq $record.RootBundle -and $null -eq $record.RootBundleSha256
            if (-not $legacyWithoutRoot -and
                    ($record.RootBundle -isnot [string] -or $record.RootBundle -cnotmatch '^[0-9a-f]{16}\.mod_bundle$' -or
                     $record.RootBundleSha256 -isnot [string] -or $record.RootBundleSha256 -cnotmatch '^[0-9a-f]{64}$')) {
                return New-VtClosureDecision 'Unavailable' 'authority-record-incomplete' $key
            }
            if ($record.Public -isnot [bool] -or $record.ModId -cnotmatch '^[A-Za-z][A-Za-z0-9_]*$' -or
                    $record.Dir -cnotmatch '^[a-z][a-z0-9_]*$' -or
                    -not (Test-VtClosureDecimalId $record.WorkshopId) -or
                    -not $authorityIds.Add($record.ModId) -or -not $authorityDirs.Add($record.Dir) -or
                    -not $authorityWorkshopIds.Add($record.WorkshopId) -or
                    $record.Version -cnotmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z][0-9A-Za-z.-]*)?$' -or
                    $record.AssetFilename -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$' -or
                    $record.AssetSha256 -cnotmatch '^[0-9a-f]{64}$') {
                return New-VtClosureDecision 'Unavailable' 'authority-record-incomplete' $key
            }
        }
        if (-not $byId.ContainsKey($AttestationId)) {
            return New-VtClosureDecision 'Rejected' 'missing-attestation' $key
        }
        $attestation = $byId[$AttestationId]
        $receipt = ConvertFrom-VtClosureAttestation $attestation.body
        if ($null -eq $receipt) { return New-VtClosureDecision 'Rejected' 'malformed-attestation' $key }
        $login = [string]$attestation.author.login
        $association = [string]$attestation.authorAssociation
        if ([string]::IsNullOrWhiteSpace($login) -or [string]::IsNullOrWhiteSpace($association)) {
            return New-VtClosureDecision 'Unavailable' 'verifier-metadata-unavailable' $key
        }
        $trusted = @($TrustedVerifier | Where-Object {
            $_ -and $_.Equals($login, [StringComparison]::OrdinalIgnoreCase)
        }).Count -gt 0
        if (-not $trusted -or $association -cnotin @('OWNER','MEMBER','COLLABORATOR') -or
                -not $login.Equals($receipt.VerifierLogin, [StringComparison]::OrdinalIgnoreCase) -or
                $association -cne $receipt.VerifierAssociation) {
            return New-VtClosureDecision 'Rejected' 'untrusted-or-mismatched-verifier' $key
        }
        if ($receipt.Repository -cne $Repository -or $receipt.IssueNumber -ne $Issue.number -or
                $receipt.ClosedEventId -cne [string]$Issue.closureEventId -or
                $receipt.ClosedAt -cne [string]$Issue.closedAt -or $receipt.Outcome -cne 'public-artifact-verified') {
            return New-VtClosureDecision 'Rejected' 'attestation-scope-or-outcome-mismatch' $key
        }
        if ($receipt.CardId -ceq $receipt.EvidenceId -or $AttestationId -ceq $receipt.CardId -or
                $AttestationId -ceq $receipt.EvidenceId -or -not $byId.ContainsKey($receipt.EvidenceId)) {
            return New-VtClosureDecision 'Rejected' 'missing-or-aliased-evidence' $key
        }
        # Reuse only strict card selection, not open-ready lifecycle/watermark:
        # a new Rain result is precisely what this closure receipt reconciles.
        $selection = Get-VtLiveTestCardSelection -Comments $comments -RequirePinnedCard `
            -Authority $AuthoritySnapshot.Authority -EnforceAuthority
        if (-not $selection.Valid) {
            return New-VtClosureDecision 'Rejected' ('invalid-card:' + ($selection.Errors -join ',')) $key
        }
        $card = $selection.Comment
        $evidence = $byId[$receipt.EvidenceId]
        if ([string]$card.databaseId -cne $receipt.CardId -or
                (Get-VtClosureBodySha256 $card.body) -cne $receipt.CardSha256 -or
                (Get-VtClosureBodySha256 $evidence.body) -cne $receipt.EvidenceSha256) {
            return New-VtClosureDecision 'Rejected' 'card-or-evidence-body-mismatch' $key
        }
        $verified = ConvertTo-VtClosureTime $receipt.VerifiedAt
        $cardUpdated = ConvertTo-VtClosureTime $card.updatedAt
        $evidenceCreated = ConvertTo-VtClosureTime $evidence.createdAt
        $evidenceUpdated = ConvertTo-VtClosureTime $evidence.updatedAt
        $attestationCreated = ConvertTo-VtClosureTime $attestation.createdAt
        if ($null -eq $verified -or $cardUpdated -gt $evidenceCreated -or
                $evidenceUpdated -gt $verified -or $verified -gt $closed -or
                $attestationCreated -lt $closed) {
            return New-VtClosureDecision 'Rejected' 'verification-chronology-mismatch' $key
        }
        # Bind the artifact the verifier actually tested, not any unrelated
        # public record that happens to be present on a mixed-stream card.
        $targets = @($selection.AuthorityTargets | Where-Object { [string]$_.ModId -ceq $receipt.ModId })
        if ($targets.Count -ne 1 -or $targets[0].Public -isnot [bool] -or -not $targets[0].Public) {
            return New-VtClosureDecision 'Rejected' 'verified-artifact-not-public-card-target' $key
        }
        $artifact = $targets[0]
        if ($null -eq $artifact.SourceCommit) {
            return New-VtClosureDecision 'Rejected' 'verified-artifact-source-commit-unavailable' $key
        }
        foreach ($field in @('ModId','Dir','Stream','WorkshopId','Version','SourceCommit',
                'RootBundle','RootBundleSha256','AssetFilename','AssetSha256')) {
            if ($artifact.$field -isnot [string] -or $artifact.$field -cne $receipt.$field) {
                return New-VtClosureDecision 'Rejected' ('verified-artifact-mismatch:' + $field) $key
            }
        }
        return New-VtClosureDecision 'Accepted' 'trusted-public-artifact-verification' $key ([pscustomobject]@{
            Schema=1; Repository=$Repository; IssueNumber=$Issue.number; ClosedEventId=$Issue.closureEventId
            ClosedAt=$Issue.closedAt; VerifiedAt=$receipt.VerifiedAt; AttestationId=$AttestationId
            AttestationSha256=(Get-VtClosureBodySha256 $attestation.body)
            CardId=$receipt.CardId; CardSha256=$receipt.CardSha256
            EvidenceId=$receipt.EvidenceId; EvidenceSha256=$receipt.EvidenceSha256
            AuthorityPolicySourceCommit=$AuthoritySnapshot.PolicySourceCommit
            Artifact=$receipt; VerifierLogin=$login; VerifierAssociation=$association
        })
    } catch {
        # Partial/corrupt snapshots or a failed authority reader are an
        # infrastructure condition, never evidence authorizing a reopen.
        return New-VtClosureDecision 'Unavailable' 'closure-policy-input-or-authority-error' $key
    }
}
