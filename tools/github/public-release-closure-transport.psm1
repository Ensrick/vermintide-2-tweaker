# Trusted read-only HTTPS owner for #1527. Importing performs no network I/O.
. (Join-Path $PSScriptRoot 'public-release-closure-collector.ps1')

function Initialize-VtClosureTransportType {
    if (-not ('Vt2.GitHub.ClosureAuditTransport' -as [type])) {
        Add-Type -AssemblyName System.Net.Http
        $compile=@{Path=(Join-Path $PSScriptRoot 'ClosureAuditTransport.cs');ErrorAction='Stop'}
        if ($PSVersionTable.PSEdition -eq 'Desktop') { $compile.ReferencedAssemblies=@('System.Net.Http') }
        Add-Type @compile
    }
}

function New-VtClosureAuditTransport {
    param($Token, $Query, $Owner, $Name, $Number, $Deadline, $ResponseLimit, $TotalLimit, $RequestLimit)
    return [Vt2.GitHub.ClosureAuditTransport]::new(
        $Token, $Query, $Owner, $Name, $Number, $Deadline, $ResponseLimit, $TotalLimit, $RequestLimit)
}

function Get-VtAuthenticatedGitHubPublicReleaseClosureAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][int]$IssueNumber,
        [Parameter(Mandatory=$true)][AllowNull()][Security.SecureString]$AuthToken,
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyString()][string]$AttestationId,
        [Parameter(Mandatory=$true)][AllowNull()]$AuthoritySnapshot,
        [Parameter(Mandatory=$true)][string]$EnforceFromUtc,
        [string[]]$TrustedVerifier=@('Ensrick','RainReligion'),
        [ValidateRange(1,60000)][int]$DeadlineMilliseconds=30000,
        [ValidateRange(1,16777216)][int]$MaxResponseBytes=4194304,
        [ValidateRange(1,67108864)][int]$MaxTotalResponseBytes=33554432,
        [ValidateRange(1,44)][int]$MaxRequests=44
    )
    $transport=$null; $result=$null
    try {
        if ($Repository -cnotmatch '^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$' -or $IssueNumber -le 0) {
            throw 'invalid scope'
        }
        $owner=$Matches[1]; $name=$Matches[2]
        Initialize-VtClosureTransportType
        $query=Get-VtClosureCollectorQuery
        $transport=New-VtClosureAuditTransport $AuthToken $query $owner $name $IssueNumber `
            $DeadlineMilliseconds $MaxResponseBytes $MaxTotalResponseBytes $MaxRequests
        $dateKind=(Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
        $request={
            param($RequestedQuery, $Variables)
            if ($RequestedQuery -cne $query -or $Variables.Keys.Count -ne 4 -or
                $Variables.owner -cne $owner -or $Variables.name -cne $name -or
                $Variables.number -ne $IssueNumber -or -not $Variables.ContainsKey('after') -or
                ($null -ne $Variables.after -and $Variables.after -isnot [string])) {
                throw 'closure-transport:request-shape'
            }
            $raw=$transport.ReadPage($Variables.after)
            $arguments=@{InputObject=$raw; ErrorAction='Stop'}
            # PS5 preserves ISO strings; recent PS7 needs this explicit option.
            # Older unsupported coercing hosts fail the unchanged collector's
            # string checks; never normalize a DateTime back to guessed bytes.
            if ($dateKind) { $arguments.DateKind='String' }
            $envelope=ConvertFrom-Json @arguments
            if ($envelope -isnot [Management.Automation.PSCustomObject] -or
                $null -eq $envelope.PSObject.Properties['data']) { throw 'closure-transport:json-envelope' }
            return $envelope
        }.GetNewClosure()
        $result=Get-VtGitHubPublicReleaseClosureAudit -Repository $Repository -IssueNumber $IssueNumber `
            -Request $request -AttestationId $AttestationId -AuthoritySnapshot $AuthoritySnapshot `
            -EnforceFromUtc $EnforceFromUtc -TrustedVerifier $TrustedVerifier -DeadlineMilliseconds $DeadlineMilliseconds
        if ($transport.FailureCode -or $transport.DeadlineExceeded) {
            $failure=if($transport.FailureCode){$transport.FailureCode}else{'deadline'}
            $result.Decision=New-VtClosureDecision 'Unavailable' ('closure-transport:'+$failure)
            $result.Issue=$null; $result.CommentSnapshot=$null
        }
    } catch {
        # No token, request headers, response text or exception details escape.
        $result=[pscustomobject]@{MayMutate=$false; Issue=$null; CommentSnapshot=$null
            Decision=(New-VtClosureDecision 'Unavailable' 'closure-transport:configuration')
            Collection=[pscustomobject]@{Source='github-graphql-one-issue/v1';RequestCount=0;ElapsedMilliseconds=0}}
    } finally {
        if ($null -ne $transport) { $transport.Dispose() }
    }
    $result.MayMutate=$false
    $result | Add-Member -NotePropertyName Transport -NotePropertyValue ([pscustomobject]@{
        Source='github-graphql-https-bounded/v1'; MayMutate=$false
        RequestCount=$(if($transport){$transport.RequestCount}else{0})
        ResponseBytes=$(if($transport){$transport.ResponseBytes}else{0})
        ElapsedMilliseconds=$(if($transport){$transport.ElapsedMilliseconds}else{0})
    })
    return $result
}

Export-ModuleMember -Function Get-VtAuthenticatedGitHubPublicReleaseClosureAudit
