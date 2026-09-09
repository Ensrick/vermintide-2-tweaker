# #1527 actual bounded HTTPS owner + unchanged collector/policy. Offline only.
[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$module=Import-Module (Join-Path $root 'tools/github/public-release-closure-transport.psm1') -Force -PassThru
& $module { Initialize-VtClosureTransportType }
. (Join-Path $root 'tools/github/public-release-closure-collector.ps1')
$compile=@{Path=(Join-Path $PSScriptRoot '_test_fixtures/ClosureAuditHttpFixture.cs');ErrorAction='Stop'}
if ($PSVersionTable.PSEdition -eq 'Desktop') { $compile.ReferencedAssemblies=@('System.Net.Http') }
if (-not ('Vt2.GitHub.Qa.Handler' -as [type])) { Add-Type @compile }

# Reuse the collector's existing authority/card fixtures, not a second policy
# implementation. Only these three declarations are evaluated; its suite is not.
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'check_public_release_closure_collector.ps1'), [ref]$null, [ref]$null)
$wanted=@('Copy-CollectorFixture','New-CollectorFixture','Set-CollectorAttestation')
$functions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $false) |
    Where-Object { $_.Name -cin $wanted })
if ($functions.Count -ne 3) { throw 'collector fixture declarations changed' }
foreach($function in $functions) { . ([scriptblock]::Create($function.Extent.Text)) }

$script:cases=0
function Assert-Transport($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:cases++
}
$dummyToken='vt2-private-fixture-secret-never-print'
$token=ConvertTo-SecureString $dummyToken -AsPlainText -Force
$utf8=New-Object Text.UTF8Encoding($false,$true)
$constructor=[Vt2.GitHub.ClosureAuditTransport].GetConstructors(
    [Reflection.BindingFlags]'NonPublic,Instance')[0]

function New-HttpPlan([string]$Json) {
    $plan=New-Object Vt2.GitHub.Qa.Plan
    $plan.Body=$utf8.GetBytes($Json)
    return $plan
}
function New-HttpPages($Fixture) {
    $plans=New-Object 'Collections.Generic.List[Vt2.GitHub.Qa.Plan]'
    for($pass=0;$pass -lt 2;$pass++) {
        for($offset=0;$offset -lt 3;$offset+=2) {
            $response=Copy-CollectorFixture $Fixture.Response
            $connection=$response.data.repository.issue.comments
            $all=@($connection.nodes)
            $connection.nodes=if($offset -eq 0){@($all[0],$all[1])}else{@($all[2])}
            $connection.pageInfo.hasNextPage=($offset -eq 0)
            $connection.pageInfo.endCursor=if($offset -eq 0){'opaque-after-2'}else{$null}
            $plans.Add((New-HttpPlan ($response | ConvertTo-Json -Depth 15 -Compress)))
        }
    }
    return ,$plans.ToArray()
}

function Invoke-HttpFixture {
    param($Plans, $Fixture=(New-CollectorFixture), [string]$Expected='Unavailable',
        [string]$Reason='', [int]$Deadline=30000, [int]$ResponseLimit=4194304,
        [int]$TotalLimit=33554432, [int]$RequestLimit=44)
    $handler=New-Object Vt2.GitHub.Qa.Handler
    foreach($plan in $Plans) { $handler.Plans.Enqueue($plan) }
    $arguments=[object[]]@($token,(Get-VtClosureCollectorQuery),'Ensrick',
        'vermintide-2-tweaker',1527,$Deadline,$ResponseLimit,$TotalLimit,$RequestLimit,$handler)
    for($i=0;$i -lt $arguments.Count;$i++) { $arguments[$i]=$arguments[$i].PSObject.BaseObject }
    $transport=$constructor.Invoke($arguments)
    $original=& $module { ${function:New-VtClosureAuditTransport} }
    # Replace only a module-private factory; the PUBLIC production entry point
    # has no handler, endpoint, query or arbitrary callback parameter.
    & $module { param($value)
        $script:fixtureTransport=$value
        function script:New-VtClosureAuditTransport {
            param($Token, $Query, $Owner, $Name, $Number, $Deadline, $ResponseLimit, $TotalLimit, $RequestLimit)
            $script:fixtureArguments=@($Token,$Query,$Owner,$Name,$Number,$Deadline,$ResponseLimit,$TotalLimit,$RequestLimit)
            return $script:fixtureTransport
        }
    } $transport
    try {
        $output=@(Get-VtAuthenticatedGitHubPublicReleaseClosureAudit -Repository 'Ensrick/vermintide-2-tweaker' `
            -IssueNumber 1527 -AuthToken $token -AttestationId $Fixture.AttestationId `
            -AuthoritySnapshot $Fixture.Authority -EnforceFromUtc $Fixture.Enforce `
            -DeadlineMilliseconds $Deadline -MaxResponseBytes $ResponseLimit `
            -MaxTotalResponseBytes $TotalLimit -MaxRequests $RequestLimit *>&1)
        $observed=& $module { return ,$script:fixtureArguments }
    } finally {
        & $module { param($value)
            Set-Item Function:New-VtClosureAuditTransport -Value $value
            Remove-Variable fixtureTransport -Scope Script
            Remove-Variable fixtureArguments -Scope Script -ErrorAction SilentlyContinue
        } $original
    }
    Assert-Transport ($output.Count -eq 1) 'transport leaked an output/error stream'
    Assert-Transport ([object]::ReferenceEquals($observed[0],$token) -and $observed[1] -ceq (Get-VtClosureCollectorQuery) -and
        $observed[2] -ceq 'Ensrick' -and $observed[3] -ceq 'vermintide-2-tweaker' -and $observed[4] -eq 1527 -and
        $observed[5] -eq $Deadline -and $observed[6] -eq $ResponseLimit -and $observed[7] -eq $TotalLimit -and
        $observed[8] -eq $RequestLimit) 'public wrapper changed trusted constructor scope/budgets'
    $result=$output[0]
    Assert-Transport ($result.Decision.Status -ceq $Expected) 'wrong transport/policy outcome'
    if($Reason) { Assert-Transport ($result.Decision.Reason -ceq $Reason) ("expected {0}; received {1}" -f $Reason,$result.Decision.Reason) }
    Assert-Transport (($result | ConvertTo-Json -Depth 20 -Compress) -notlike ('*'+$dummyToken+'*')) 'token disclosed in result'
    Assert-Transport ($result.MayMutate -is [bool] -and -not $result.MayMutate -and
        $result.Decision.MayMutate -is [bool] -and -not $result.Decision.MayMutate -and
        $result.Transport.MayMutate -is [bool] -and -not $result.Transport.MayMutate) 'mutation authority escaped'
    Assert-Transport ($transport.Disposed -and $handler.Disposed) 'client/handler lifetime leaked'
    foreach($request in $handler.Requests) {
        Assert-Transport ($request.Method -ceq 'POST' -and $request.Uri -ceq 'https://api.github.com/graphql') 'noncanonical HTTP request'
        Assert-Transport ($request.Authorization -ceq ('Bearer '+$dummyToken)) 'explicit authentication was not sent'
        Assert-Transport ($null -eq $request.Request.Headers.Authorization) 'request retained authorization after completion'
        $disposed=$false
        try { $null=$request.Request.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult() } catch { $disposed=$true }
        Assert-Transport $disposed 'request content not disposed'
        $json=ConvertFrom-Json -InputObject $request.Body
        Assert-Transport ($json.query -ceq (Get-VtClosureCollectorQuery)) 'query identity changed'
        Assert-Transport ($json.variables.owner -ceq 'Ensrick' -and $json.variables.name -ceq 'vermintide-2-tweaker' -and
            $json.variables.number -eq 1527 -and @($json.variables.PSObject.Properties).Count -eq 4) 'variable scope changed'
    }
    foreach($plan in $Plans) { Assert-Transport ($plan.SerializeCalls -eq 0) 'response buffered before streaming bound' }
    return [pscustomobject]@{Result=$result;Handler=$handler;Transport=$transport}
}

try {
    $f=New-CollectorFixture
    $f.Evidence.body="Raw body`r`n"+[char]0x00e9+[char]::ConvertFromUtf32(0x1f642)+' \ud800 literal text'
    $f.Receipt.EvidenceSha256=Get-VtClosureBodySha256 $f.Evidence.body
    Set-CollectorAttestation $f
    $plans=New-HttpPages $f
    $ok=Invoke-HttpFixture -Plans $plans -Fixture $f -Expected Accepted
    Assert-Transport ($ok.Result.Transport.RequestCount -eq 4) 'two-pass HTTPS orchestration was skipped'
    Assert-Transport ($ok.Result.CommentSnapshot.Comments[1].body -ceq $f.Evidence.body) 'raw body/Unicode/newline changed'
    Assert-Transport ($ok.Result.CommentSnapshot.Comments[1].createdAt -is [string]) 'timestamp string coerced by host parser'
    for($i=0;$i -lt 4;$i++) {
        $request=ConvertFrom-Json $ok.Handler.Requests[$i].Body
        if($i % 2 -eq 0) {
            Assert-Transport ($null -eq $request.variables.after -and $ok.Handler.Requests[$i].Body.Contains('"after":null')) 'initial cursor not literal null'
        } else { Assert-Transport ($request.variables.after -ceq 'opaque-after-2') 'opaque continuation changed' }
        Assert-Transport ($plans[$i].ResponseDisposals -eq 1 -and $plans[$i].ContentDisposals -eq 1 -and
            $plans[$i].StreamDisposals -eq 1) 'normal response resources leaked'
    }
    $f=New-CollectorFixture;$f.Authority=$null
    $null=Invoke-HttpFixture -Plans (New-HttpPages $f) -Fixture $f -Expected Unavailable -Reason 'closure-time-authority-unavailable'
    $f=New-CollectorFixture;$f.Enforce='2026-09-07T00:00:00Z';$f.Authority=$null
    $null=Invoke-HttpFixture -Plans (New-HttpPages $f) -Fixture $f -Expected LegacyReviewRequired

    foreach($row in @(@{Status=401;Reason='authentication'},@{Status=403;Reason='authentication'},
        @{Status=302;Reason='redirect'},@{Status=307;Reason='redirect'},@{Status=429;Reason='http-status'},@{Status=500;Reason='http-status'})) {
        $p=New-HttpPlan ('{"error":"'+$dummyToken+'"}');$p.Status=$row.Status
        $r=Invoke-HttpFixture @($p) -Reason ('closure-transport:'+$row.Reason)
        Assert-Transport ($r.Transport.RequestCount -eq 1 -and $p.Reads -eq 0 -and $p.ResponseDisposals -eq 1) 'HTTP failure retried/read/leaked'
    }
    foreach($contentType in @($null,'text/html','application/json; charset=utf-16')) {
        $p=New-HttpPlan '{}';$p.ContentType=$contentType
        $null=Invoke-HttpFixture @($p) -Reason 'closure-transport:content-type'
    }
    $p=New-HttpPlan '{}';$p.ContentEncoding='gzip'
    $null=Invoke-HttpFixture @($p) -Reason 'closure-transport:content-encoding'
    $p=New-HttpPlan '{}';$p.Body=[byte[]]@(0x7b,0x22,0x78,0x22,0x3a,0x22,0xc3,0x28,0x22,0x7d)
    $null=Invoke-HttpFixture @($p) -Reason 'closure-transport:utf8'
    foreach($raw in @('{"x":"\ud800"}','{"x":"\udc00"}','{"x":"\ud800\u0041"}',
        '{"x":1,}','{/*comment*/"data":{}}','[]',('{'+'"x":['*33+'0'+']'*33+'}'),
        '{"data":null,"x":NaN}','{"data":null,"x":Infinity}','{"data":null,"x":undefined}',
        '{"data":null,"x":01}','{"data":null,"x":0x10}','{"data":null,"x":+1}',
        '{"data":null,"x":.1}','{"data":null,"x":1.}',
        '{"data":null,"x":[1,,2]}','{"data":null,"x":[,1]}','{true:null}')) {
        $null=Invoke-HttpFixture @((New-HttpPlan $raw)) -Reason 'closure-transport:json-wire'
    }
    foreach($raw in @('{"data": nope}','{"errors":[{"message":"'+$dummyToken+'"}],"data":null}')) {
        $r=Invoke-HttpFixture @((New-HttpPlan $raw))
        Assert-Transport ($null -eq $r.Result.CommentSnapshot) 'invalid envelope exposed a trusted snapshot'
    }

    $p=New-HttpPlan '{}';$p.DeclaredLength=4097
    $null=Invoke-HttpFixture @($p) -ResponseLimit 4096 -Reason 'closure-transport:response-byte-bound'
    Assert-Transport ($p.Reads -eq 0) 'declared oversize body was read'
    $p=New-HttpPlan ('x'*2000)
    $null=Invoke-HttpFixture @($p) -ResponseLimit 1024 -Reason 'closure-transport:response-byte-bound'
    Assert-Transport ($p.BytesRead -eq 1025) 'streaming oversize read beyond one proof byte'
    $p=New-HttpPlan ('x'*2000);$p.DeclaredLength=1
    $null=Invoke-HttpFixture @($p) -ResponseLimit 1024 -Reason 'closure-transport:response-byte-bound'
    Assert-Transport ($p.BytesRead -eq 1025) 'lying Content-Length bypassed streaming bound'
    $f=New-CollectorFixture;$plans=New-HttpPages $f
    $budget=$plans[0].Body.Length+$plans[1].Body.Length+$plans[2].Body.Length-1
    $r=Invoke-HttpFixture -Plans $plans -TotalLimit $budget -Reason 'closure-transport:total-byte-bound'
    Assert-Transport ($r.Transport.RequestCount -eq 3 -and $r.Transport.ResponseBytes -eq $budget+1) 'cumulative bytes reset across pages'
    $r=Invoke-HttpFixture -Plans (New-HttpPages $f) -RequestLimit 3 -Reason 'closure-transport:request-bound'
    Assert-Transport ($r.Transport.RequestCount -eq 3) 'physical request budget bypassed'

    foreach($phase in @('headers','body','stream')) {
        $p=New-HttpPlan '{"data":{}}';$p.IgnoreCancellation=$true
        if($phase -eq 'headers'){$p.HeaderDelay=600}
        elseif($phase -eq 'body'){$p.ReadDelay=600}
        else{$p.StreamDelay=600}
        $clock=[Diagnostics.Stopwatch]::StartNew()
        $r=Invoke-HttpFixture @($p) -Deadline 150 -Reason 'closure-transport:deadline'
        Assert-Transport ($clock.ElapsedMilliseconds -lt 2000) 'deadline did not bound asynchronous phase'
        # Let the deliberately cancellation-ignoring fixture finish so its
        # late ownership transfer and disposal are observed, not abandoned.
        [Threading.Thread]::Sleep(700)
        Assert-Transport ($p.ResponseDisposals -eq 1 -and $p.ContentDisposals -eq 1 -and $p.StreamDisposals -eq 1) 'late response/stream leaked'
    }
    $plans=New-HttpPages (New-CollectorFixture)
    foreach($p in $plans){$p.HeaderDelay=250}
    $r=Invoke-HttpFixture -Plans $plans -Deadline 400 -Reason 'closure-transport:deadline'
    Assert-Transport ($r.Transport.RequestCount -eq 2) 'shared deadline reset per page or first pass was skipped'
    foreach($phase in @('headers','body')) {
        $p=New-HttpPlan '{}';$p.ErrorText=$dummyToken
        if($phase -eq 'headers'){$p.HeaderThrows=$true}else{$p.ReadThrows=$true}
        $null=Invoke-HttpFixture @($p) -Reason 'closure-transport:io'
    }
    $f=New-CollectorFixture
    $missing=@(Get-VtAuthenticatedGitHubPublicReleaseClosureAudit -Repository 'Ensrick/vermintide-2-tweaker' `
        -IssueNumber 1527 -AuthToken $null -AttestationId $f.AttestationId -AuthoritySnapshot $f.Authority `
        -EnforceFromUtc $f.Enforce *>&1)
    Assert-Transport ($missing.Count -eq 1 -and $missing[0].Decision.Status -ceq 'Unavailable' -and
        $missing[0].Decision.Reason -ceq 'closure-transport:configuration' -and $missing[0].Transport.RequestCount -eq 0) 'missing explicit token reached network or leaked diagnostics'
    $wrongQueryHandler=New-Object Vt2.GitHub.Qa.Handler
    $arguments=[object[]]@($token,((Get-VtClosureCollectorQuery)+' '),'Ensrick','vermintide-2-tweaker',1527,30000,4096,8192,4,$wrongQueryHandler)
    for($i=0;$i -lt $arguments.Count;$i++) { $arguments[$i]=$arguments[$i].PSObject.BaseObject }
    $refused=$false
    try { $null=$constructor.Invoke($arguments) } catch { $refused=$true }
    Assert-Transport ($refused -and $wrongQueryHandler.Disposed -and $wrongQueryHandler.Requests.Count -eq 0) 'changed query was sent or construction leaked handler'
    Assert-Transport ($token.Length -eq $dummyToken.Length) 'transport disposed caller-owned token'
    $liveHandler=[Vt2.GitHub.ClosureAuditTransport].GetMethod('NewHandler',[Reflection.BindingFlags]'NonPublic,Static').Invoke($null,@())
    try { Assert-Transport (-not $liveHandler.AllowAutoRedirect -and -not $liveHandler.UseCookies -and
        -not $liveHandler.UseDefaultCredentials -and $liveHandler.AutomaticDecompression -eq [Net.DecompressionMethods]::None -and
        $liveHandler.MaxResponseHeadersLength -eq 32) 'live HTTPS handler unsafe defaults' } finally {$liveHandler.Dispose()}
    $parameters=(Get-Command Get-VtAuthenticatedGitHubPublicReleaseClosureAudit).Parameters.Keys
    foreach($forbidden in @('Uri','Url','Query','Request','Handler','Endpoint','Factory')) {
        Assert-Transport ($parameters -notcontains $forbidden) 'private transport seam exposed as live input'
    }
    Write-Host "[check_public_release_closure_transport] PASS -- $script:cases assertions; host=$($PSVersionTable.PSVersion); DateKind=$((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')); no network or mutation."
} finally { $token.Dispose() }
