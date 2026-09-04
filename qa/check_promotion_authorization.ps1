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
    [switch]$ValidateAuthorizedEnvironment,
    [string[]]$ChangedPath,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
. (Join-Path $PSScriptRoot 'promotion_version_reader.ps1')
$APPROVAL_LABEL = 'stable-promotion-approved'
$VERSION_PATTERN = '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.+-]+)?$'
$STABLE_DIRS = @(
    'chaos_wastes_tweaker',
    'crafting_in_modded',
    'general_tweaker',
    'gui_tweaker',
    'verminious_dreams_lighting'
)

function Get-PromotionRequestError {
    param([object[]]$Requests)

    $seen = @{}
    foreach ($request in @($Requests)) {
        $dir = "$($request.Dir)"
        $version = "$($request.Version)"
        if ($STABLE_DIRS -cnotcontains $dir) {
            return "request contains an unknown or non-canonical stable directory '$dir'"
        }
        if ($version -notmatch $VERSION_PATTERN) {
            return "request for '$dir' has invalid version '$version'"
        }
        if ($seen.ContainsKey($dir)) {
            return "request contains duplicate stable directory '$dir'"
        }
        $seen[$dir] = $true
    }
    return $null
}

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
        $version = Get-CanonicalPromotionModVersion -Text $text -SourceLabel $relativeMain
        $requests += [pscustomobject]@{
            Dir = $dir
            Version = $version
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
    $requestError = Get-PromotionRequestError -Requests @($Context.Requests)
    if ($requestError) {
        return [pscustomobject]@{ Allowed = $false; Reason = $requestError }
    }
    if (@($Context.Labels) -notcontains $APPROVAL_LABEL) {
        return [pscustomobject]@{ Allowed = $false; Reason = "live label '$APPROVAL_LABEL' is absent" }
    }

    $labelEvents = @($Context.LabelEvents | Where-Object { $_.Label -eq $APPROVAL_LABEL } | Sort-Object CreatedAt)
    if ($labelEvents.Count -eq 0 -or $labelEvents[-1].Event -ne 'labeled') {
        return [pscustomobject]@{ Allowed = $false; Reason = 'approval label has no current grant event' }
    }
    $grant = $labelEvents[-1]
    # A repository owner is always an administrator of a personal repository.
    # GitHub's Actions token can return 403 for the collaborator-permission
    # endpoint even when the actor is the owner, so prove that case from the
    # immutable repository owner identity carried by the pull-request event.
    $grantIsOwner = -not [string]::IsNullOrWhiteSpace("$($Context.OwnerLogin)") -and
        "$($grant.Actor)".Equals("$($Context.OwnerLogin)", [StringComparison]::OrdinalIgnoreCase)
    $grantPermission = if ($grantIsOwner) { 'admin' } else { "$($Context.Permissions[$grant.Actor])".ToLowerInvariant() }
    if ($grantPermission -notin @('admin', 'maintain')) {
        return [pscustomobject]@{ Allowed = $false; Reason = "label actor '$($grant.Actor)' lacks maintainer permission" }
    }

    $expected = @{}
    foreach ($request in @($Context.Requests)) {
        $expected["$($request.Dir)@$($request.Version)@$($Context.HeadSha.ToLowerInvariant())"] = $true
    }

    foreach ($comment in @($Context.Comments | Sort-Object CreatedAt -Descending)) {
        if ($comment.Author -ne $grant.Actor) { continue }
        $commentIsOwner = -not [string]::IsNullOrWhiteSpace("$($Context.OwnerLogin)") -and
            "$($comment.Author)".Equals("$($Context.OwnerLogin)", [StringComparison]::OrdinalIgnoreCase)
        $permission = if ($commentIsOwner) { 'admin' } else { "$($Context.Permissions[$comment.Author])".ToLowerInvariant() }
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

function Get-PromotionEnvironmentLines {
    param(
        [object[]]$Requests,
        [pscustomobject]$Authorization
    )

    # These values are derived only from an already successful exact
    # authorization result. Every later capability remains bound to an exact
    # directory and version rather than one job-wide suffix bit.
    if (-not $Authorization -or -not $Authorization.Allowed -or @($Requests).Count -eq 0) {
        return @()
    }

    $requestError = Get-PromotionRequestError -Requests @($Requests)
    if ($requestError) { throw $requestError }

    $ordered = @($Requests | Sort-Object Dir)
    $dirs = @($ordered | ForEach-Object { $_.Dir })
    $pairs = @($ordered | ForEach-Object { $_.Dir + '@' + $_.Version })
    $suffixPairs = @(
        $ordered |
            Where-Object { "$($_.Version)" -match '-' } |
            ForEach-Object { $_.Dir + '@' + $_.Version }
    )
    return @(
        'VT2_PROMOTION=1'
        "VT2_PROMOTION_DIRS=$($dirs -join ';')"
        "VT2_PROMOTION_AUTHORIZED_REQUESTS=$($pairs -join ';')"
        # Emit the empty value too. It overwrites any ambient capability from
        # the job environment for a clean-version authorization.
        "VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS=$($suffixPairs -join ';')"
    )
}

function Read-PromotionPairMap {
    param(
        [AllowNull()][string]$Raw,
        [string]$Name,
        [switch]$AllowEmpty
    )

    $pairs = @{}
    if ($null -eq $Raw) { throw "$Name is missing" }
    if ($Raw.Length -eq 0) {
        if (-not $AllowEmpty) { throw "$Name is empty" }
        return [pscustomobject]@{ Pairs = $pairs }
    }
    foreach ($token in [regex]::Split($Raw, ';')) {
        $match = [regex]::Match($token, '^(?<dir>[a-z0-9_]+)@(?<version>\d+\.\d+\.\d+(?:-[A-Za-z0-9.+-]+)?)$')
        if (-not $match.Success) { throw "$Name contains malformed entry '$token'" }
        $dir = $match.Groups['dir'].Value
        $version = $match.Groups['version'].Value
        if ($STABLE_DIRS -cnotcontains $dir) { throw "$Name contains unauthorized directory '$dir'" }
        if ($pairs.ContainsKey($dir)) { throw "$Name contains duplicate directory '$dir'" }
        $pairs[$dir] = $version
    }
    return [pscustomobject]@{ Pairs = $pairs }
}

function Read-PromotionDirList {
    param([AllowNull()][string]$Raw)

    if ([string]::IsNullOrEmpty($Raw)) { throw 'VT2_PROMOTION_DIRS is missing or empty' }
    $seen = @{}
    $dirs = @()
    foreach ($dir in [regex]::Split($Raw, ';')) {
        if ($STABLE_DIRS -cnotcontains $dir) { throw "VT2_PROMOTION_DIRS contains unauthorized directory '$dir'" }
        if ($seen.ContainsKey($dir)) { throw "VT2_PROMOTION_DIRS contains duplicate directory '$dir'" }
        $seen[$dir] = $true
        $dirs += $dir
    }
    return @($dirs)
}

function Invoke-AuthorizedPromotionValidation {
    param(
        [string]$Root,
        [string[]]$Paths,
        [AllowNull()][string]$PromotionFlag,
        [AllowNull()][string]$PromotionDirs,
        [AllowNull()][string]$AuthorizedRequests,
        [AllowNull()][string]$AuthorizedSuffixRequests,
        [bool]$AuthorizedSuffixRequestsPresent,
        [scriptblock]$ReadSource,
        [scriptblock]$InvokeGate
    )

    # Never inherit a caller's direct suffix override. A validated pair sets it
    # for one gate invocation, and every path clears it again.
    $env:VT2_SUFFIX_OK = ''
    try {
        if ($PromotionFlag -cne '1') { throw 'VT2_PROMOTION is not exactly 1' }
        if (-not $Paths -or @($Paths).Count -eq 0) { throw 'checked-tree change set is missing' }

        $dirs = @(Read-PromotionDirList -Raw $PromotionDirs)
        $authorized = (Read-PromotionPairMap -Raw $AuthorizedRequests -Name 'VT2_PROMOTION_AUTHORIZED_REQUESTS').Pairs
        if (-not $AuthorizedSuffixRequestsPresent) {
            throw 'VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS is missing'
        }
        $suffixAuthorized = (Read-PromotionPairMap -Raw $AuthorizedSuffixRequests -Name 'VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS' -AllowEmpty).Pairs
        $checked = @(Get-StablePromotionRequests -Paths $Paths -Root $Root -ReadSource $ReadSource)

        if ($checked.Count -ne $dirs.Count -or $authorized.Count -ne $dirs.Count) {
            throw "authorized directories, authorized request pairs, and checked-tree stable directories differ (dirs=$($dirs.Count) pairs=$($authorized.Count) checked=$($checked.Count))"
        }
        foreach ($dir in $dirs) {
            if (-not $authorized.ContainsKey($dir)) { throw "authorized request pair is missing '$dir'" }
            if (@($checked | Where-Object { $_.Dir -ceq $dir }).Count -ne 1) {
                throw "checked-tree request is missing or duplicates '$dir'"
            }
        }
        foreach ($request in $checked) {
            if (-not $authorized.ContainsKey($request.Dir) -or
                    "$($authorized[$request.Dir])" -cne "$($request.Version)") {
                throw "checked-tree version '$($request.Dir)@$($request.Version)' does not match its authorized request pair"
            }
        }

        foreach ($entry in $suffixAuthorized.GetEnumerator()) {
            if (-not $authorized.ContainsKey($entry.Key) -or
                    "$($authorized[$entry.Key])" -cne "$($entry.Value)" -or
                    "$($entry.Value)" -notmatch '-') {
                throw "suffix authorization '$($entry.Key)@$($entry.Value)' is not an exact suffixed authorized request"
            }
        }
        foreach ($entry in $authorized.GetEnumerator()) {
            $mustHaveSuffix = "$($entry.Value)" -match '-'
            if ($suffixAuthorized.ContainsKey($entry.Key) -ne $mustHaveSuffix) {
                throw "suffix authorization is not exact for '$($entry.Key)@$($entry.Value)'"
            }
        }

        foreach ($dir in @($dirs | Sort-Object)) {
            # Re-read the checked tree immediately before this specific gate.
            # This also fails closed if a future workflow validates a different
            # tree from the exact PR-head version authorized by the maintainer.
            $current = @(Get-StablePromotionRequests -Paths @("$dir/__authorized_validation__") -Root $Root -ReadSource $ReadSource)
            if ($current.Count -ne 1 -or "$($current[0].Version)" -cne "$($authorized[$dir])") {
                $actual = if ($current.Count -eq 1) { "$($current[0].Version)" } else { '<unreadable>' }
                throw "checked-tree MOD_VERSION '$dir@$actual' changed from authorized pair '$dir@$($authorized[$dir])' before its gate"
            }

            $env:VT2_SUFFIX_OK = if ($suffixAuthorized.ContainsKey($dir)) { '1' } else { '' }
            try {
                $gateOutput = @(& $InvokeGate $dir $Paths)
                if ($gateOutput.Count -ne 1 -or "$($gateOutput[0])" -notmatch '^\d+$') {
                    throw "promotion gate for '$dir' returned no exact exit code"
                }
                $gateCode = [int]$gateOutput[0]
                if ($gateCode -ne 0) { throw "promotion gate for '$dir' failed with exit $gateCode" }
            } finally {
                $env:VT2_SUFFIX_OK = ''
            }
        }
    } finally {
        $env:VT2_SUFFIX_OK = ''
    }
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
        OwnerLogin = 'repo-owner'
        HeadSha = $sha
        Requests = @([pscustomobject]@{ Dir = 'crafting_in_modded'; Version = '0.8.91' })
        Labels = @($APPROVAL_LABEL)
        LabelEvents = @([pscustomobject]@{ Event = 'labeled'; Label = $APPROVAL_LABEL; Actor = 'maintainer'; CreatedAt = $grantAt })
        Comments = @([pscustomobject]@{ Id = 7; Author = 'maintainer'; Body = $approval; CreatedAt = '2026-07-19T05:59:00Z'; UpdatedAt = '2026-07-19T05:59:00Z' })
        Permissions = @{ maintainer = 'admin'; contributor = 'write' }
    }

    $tests = @()
    $tests += @{ Name = 'exact maintainer grant'; Context = $base; Expected = $true }

    $owner = $base.PSObject.Copy()
    $owner.LabelEvents = @([pscustomobject]@{ Event = 'labeled'; Label = $APPROVAL_LABEL; Actor = 'repo-owner'; CreatedAt = $grantAt })
    $owner.Comments = @([pscustomobject]@{ Id = 10; Author = 'repo-owner'; Body = $approval; CreatedAt = '2026-07-19T05:59:00Z'; UpdatedAt = '2026-07-19T05:59:00Z' })
    $owner.Permissions = @{ 'repo-owner' = 'none' }
    $tests += @{ Name = 'repository owner survives unavailable collaborator permission'; Context = $owner; Expected = $true }

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

    $suffixed = $base.PSObject.Copy()
    $suffixed.Requests = @([pscustomobject]@{ Dir = 'crafting_in_modded'; Version = '0.8.91-beta' })
    $suffixed.Comments = @([pscustomobject]@{
        Id = 11
        Author = 'maintainer'
        Body = "VT2-Promotion-Approval: crafting_in_modded@0.8.91-beta head=$sha"
        CreatedAt = '2026-07-19T05:59:00Z'
        UpdatedAt = '2026-07-19T05:59:00Z'
    })
    $tests += @{ Name = 'exact suffixed maintainer grant'; Context = $suffixed; Expected = $true }

    $duplicateRequest = $base.PSObject.Copy()
    $duplicateRequest.Requests = @(
        [pscustomobject]@{ Dir = 'crafting_in_modded'; Version = '0.8.91' },
        [pscustomobject]@{ Dir = 'crafting_in_modded'; Version = '0.8.91' }
    )
    $tests += @{ Name = 'duplicate request directory'; Context = $duplicateRequest; Expected = $false }

    $mixed = $base.PSObject.Copy()
    $mixed.Requests = @(
        [pscustomobject]@{ Dir = 'gui_tweaker'; Version = '0.2.289' },
        [pscustomobject]@{ Dir = 'chaos_wastes_tweaker'; Version = '0.7.132-beta' }
    )
    $mixed.Comments = @([pscustomobject]@{
        Id = 12
        Author = 'maintainer'
        Body = "VT2-Promotion-Approval: gui_tweaker@0.2.289 head=$sha`nVT2-Promotion-Approval: chaos_wastes_tweaker@0.7.132-beta head=$sha"
        CreatedAt = '2026-07-19T05:59:00Z'
        UpdatedAt = '2026-07-19T05:59:00Z'
    })
    $tests += @{ Name = 'mixed clean and suffixed maintainer grant'; Context = $mixed; Expected = $true }

    $multipleSuffixed = $base.PSObject.Copy()
    $multipleSuffixed.Requests = @(
        [pscustomobject]@{ Dir = 'crafting_in_modded'; Version = '0.8.92-rc1' },
        [pscustomobject]@{ Dir = 'chaos_wastes_tweaker'; Version = '0.7.132-beta' }
    )
    $multipleSuffixed.Comments = @([pscustomobject]@{
        Id = 13
        Author = 'maintainer'
        Body = "VT2-Promotion-Approval: crafting_in_modded@0.8.92-rc1 head=$sha`nVT2-Promotion-Approval: chaos_wastes_tweaker@0.7.132-beta head=$sha"
        CreatedAt = '2026-07-19T05:59:00Z'
        UpdatedAt = '2026-07-19T05:59:00Z'
    })
    $tests += @{ Name = 'multiple suffixed maintainer grant'; Context = $multipleSuffixed; Expected = $true }

    $failed = @()
    $requests = @(Get-StablePromotionRequests -Paths @('crafting_in_modded/itemV2.cfg') -Root '' -ReadSource {
        param([string]$Path)
        if ($Path -ne 'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded.lua') { throw "unexpected source path: $Path" }
        'local MOD_VERSION = "0.8.91"'
    })
    if ($requests.Count -ne 1 -or $requests[0].Version -ne '0.8.91') {
        $failed += 'live PR source reader did not resolve the exact stable version'
    }
    $closureRebindSource = "local MOD_VERSION=`"0.8.91-beta`"`nlocal t={run=function() local y=1; MOD_VERSION=`"0.8.91-evil`" end}; t.run()"
    $labelImmediateSource = "local MOD_VERSION=`"0.8.91-beta`"`n::again:: MOD_VERSION=`"0.8.91-evil`""
    $labelParenListSource = "local MOD_VERSION=`"0.8.91-beta`"`nlocal t={}`n::again:: MOD_VERSION,(t).x=`"0.8.91-evil`",1"
    $labelCallListSource = "local MOD_VERSION=`"0.8.91-beta`"`nlocal function f() return {} end`n::again:: MOD_VERSION,f().x=`"0.8.91-evil`",1"
    $labelMiddleListSource = "local MOD_VERSION=`"0.8.91-beta`"`nlocal t={}`n::again:: t.x,MOD_VERSION,(t).y=1,`"0.8.91-evil`",2"
    $labelFunctionSource = "local MOD_VERSION=`"0.8.91-beta`"`n::again:: function MOD_VERSION() end"
    $labelNamedSource = "local MOD_VERSION=`"0.8.91-beta`"`n::again:: local x,MOD_VERSION"
    $labelClosureSource = "local MOD_VERSION=`"0.8.91-beta`"`nlocal t={run=function() ::again:: MOD_VERSION=`"0.8.91-evil`" end}; t.run()"
    $labelMemberSource = "local MOD_VERSION=`"0.8.91-beta`"`nlocal mod={}`n::again:: mod.MOD_VERSION=`"member`""
    $readerCases = @(
        [pscustomobject]@{
            Name = 'line-comment decoy'
            Text = "-- local MOD_VERSION = `"9.9.9-beta`"`nlocal MOD_VERSION = `"0.8.91`""
            Version = '0.8.91'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'short-string decoys'
            Text = @'
local a = 'local MOD_VERSION = "9.9.9-beta"'
local b = "MOD_VERSION = '9.9.8'"
local MOD_VERSION = "0.8.91"
'@
            Version = '0.8.91'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'long-comment decoy'
            Text = "--[=[`nlocal MOD_VERSION = `"9.9.9-beta`"`n]=]`nlocal MOD_VERSION = `"0.8.91`""
            Version = '0.8.91'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'long-string decoy'
            Text = "local bait = [==[`nlocal MOD_VERSION = `"9.9.9-beta`"`n]==]`nlocal MOD_VERSION = `"0.8.91`""
            Version = '0.8.91'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'generic and member decoys'
            Text = "local OTHER_MOD_VERSION = `"9.9.9-beta`"`nmod.MOD_VERSION = `"9.9.8-beta`"`nlocal MOD_VERSION = `"0.8.91`""
            Version = '0.8.91'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'ordinary comma-separated reads'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal a = { MOD_VERSION, `"x`" }`nlocal b = string.format(`"%s:%s`", MOD_VERSION, `"x`")`nlocal c, d = MOD_VERSION, `"x`""
            Version = '0.8.91'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'comparison is not reassignment'
            Text = "local MOD_VERSION = `"0.8.91`"`nif MOD_VERSION == `"0.8.91`" then`n    return true`nend"
            Version = '0.8.91'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'authorization bypass decoy resolves real suffix'
            Text = "-- MOD_VERSION = `"0.8.91-beta`"`nlocal MOD_VERSION = `"0.8.91-evil`""
            Version = '0.8.91-evil'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'duplicate canonical declarations'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal MOD_VERSION = `"0.8.92`""
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'post-declaration reassignment'
            Text = "local MOD_VERSION = `"0.8.91`"`nMOD_VERSION = `"0.8.92`""
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'multiple-assignment rebinding from first slot'
            Text = "local MOD_VERSION = `"0.8.91`"`nMOD_VERSION, x = `"0.8.92`", 1"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'multiple-local rebinding from later slot'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal x, MOD_VERSION = 1, `"0.8.92`""
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'complex parenthesized multiple-assignment lvalue'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal t = {}`nMOD_VERSION, (t).x = `"0.8.92`", 1"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'complex call-result multiple-assignment lvalue'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal function f() return {} end`nMOD_VERSION, f().x = `"0.8.92`", 1"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'executable closure in table reassigns canonical local'
            Text = $closureRebindSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'bare table field is conservatively rejected'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal t = { MOD_VERSION = `"decoy`" }"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'global function rebinding'
            Text = "local MOD_VERSION = `"0.8.91`"`nfunction MOD_VERSION() end"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'local function shadow'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal function MOD_VERSION() end"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'named function parameter shadow'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal function f(x, MOD_VERSION) return x end"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'anonymous function parameter shadow'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal f = function(x, MOD_VERSION) return x end"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'local namelist shadow without initializer'
            Text = "local MOD_VERSION = `"0.8.91`"`nlocal x, MOD_VERSION"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'generic for namelist shadow'
            Text = "local MOD_VERSION = `"0.8.91`"`nfor x, MOD_VERSION in pairs({}) do return x end"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent immediate reassignment'
            Text = $labelImmediateSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent parenthesized list reassignment'
            Text = $labelParenListSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent call-result list reassignment'
            Text = $labelCallListSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent middle-slot list reassignment'
            Text = $labelMiddleListSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent function rebinding'
            Text = $labelFunctionSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent local namelist shadow'
            Text = $labelNamedSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent closure reassignment'
            Text = $labelClosureSource
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'label-adjacent member assignment remains unrelated'
            Text = $labelMemberSource
            Version = '0.8.91-beta'
            Fails = $false
        },
        [pscustomobject]@{
            Name = 'global decoy plus canonical declaration'
            Text = "MOD_VERSION = `"9.9.9`"`nlocal MOD_VERSION = `"0.8.91`""
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'nested dead declaration'
            Text = "if false then`n    local MOD_VERSION = `"9.9.9`"`nend"
            Version = $null
            Fails = $true
        },
        [pscustomobject]@{
            Name = 'invalid canonical version'
            Text = 'local MOD_VERSION = "0.8"'
            Version = $null
            Fails = $true
        }
    )
    foreach ($readerCase in $readerCases) {
        $actualVersion = $null
        $readerFailed = $false
        try {
            $actualVersion = Get-CanonicalPromotionModVersion -Text $readerCase.Text -SourceLabel $readerCase.Name
        } catch {
            $readerFailed = $true
        }
        if ($readerFailed -ne $readerCase.Fails -or
                (-not $readerFailed -and "$actualVersion" -cne "$($readerCase.Version)")) {
            $failed += "canonical reader $($readerCase.Name): expectedFail=$($readerCase.Fails) actualFail=$readerFailed expectedVersion=$($readerCase.Version) actualVersion=$actualVersion"
        }
    }
    $repoFullPath = [System.IO.Path]::GetFullPath($RepoRoot)
    $dialectParser = Join-Path $repoFullPath 'tools\luacheck\luacheck.exe'
    $dialectFixtures = @()
    if (-not (Test-Path -LiteralPath $dialectParser -PathType Leaf)) {
        $failed += "vendored repository Lua-dialect parser missing for label proof: $dialectParser"
    } else {
        try {
            $labelSources = @(
                $labelImmediateSource,
                $labelParenListSource,
                $labelCallListSource,
                $labelMiddleListSource,
                $labelFunctionSource,
                $labelNamedSource,
                $labelClosureSource,
                $labelMemberSource
            )
            for ($labelIndex = 0; $labelIndex -lt $labelSources.Count; $labelIndex++) {
                $labelPath = Join-Path ([System.IO.Path]::GetTempPath()) `
                    ("promotion_version_label_" + [System.Guid]::NewGuid().ToString('N') + '.lua')
                [System.IO.File]::WriteAllText($labelPath, $labelSources[$labelIndex], [System.Text.Encoding]::ASCII)
                $dialectFixtures += $labelPath
            }
            $dialectArguments = @($dialectFixtures) + @(
                '--no-config', '--std', 'luajit', '--ignore', '1', '2', '3', '4', '5', '6',
                '--formatter', 'plain', '--no-color', '--no-cache'
            )
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $dialectOutput = @(& $dialectParser @dialectArguments 2>&1)
                $dialectCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $savedPreference
            }
            if ($dialectCode -ne 0) {
                $failed += "repository Lua-dialect parser rejected label adversaries: exit=$dialectCode output=$($dialectOutput -join ' | ')"
            }
        } finally {
            foreach ($dialectFixture in $dialectFixtures) {
                if (Test-Path -LiteralPath $dialectFixture -PathType Leaf) {
                    Remove-Item -LiteralPath $dialectFixture
                }
            }
        }
    }

    $luaExe = Join-Path $repoFullPath 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
    if (-not (Test-Path -LiteralPath $luaExe -PathType Leaf)) {
        $failed += "vendored Lua 5.1 runtime missing for closure semantic proof: $luaExe"
    } else {
        $luaPrograms = @(
            [pscustomobject]@{
                Name = 'closure semantic rebind'
                Text = $closureRebindSource + '; io.write(MOD_VERSION)'
                Expected = '0.8.91-evil'
            },
            [pscustomobject]@{
                Name = 'complex list semantic rebind'
                Text = $labelParenListSource.Replace('::again:: ', '') + '; io.write(MOD_VERSION)'
                Expected = '0.8.91-evil'
            }
        )
        foreach ($luaProgram in $luaPrograms) {
            $luaFixture = Join-Path ([System.IO.Path]::GetTempPath()) `
                ("promotion_version_reader_" + [System.Guid]::NewGuid().ToString('N') + '.lua')
            $savedPreference = $ErrorActionPreference
            try {
                # Invoke a file rather than `lua -e <source>`: Windows PowerShell
                # 5.1 rewrites embedded quotes in native arguments, while an exact
                # fixture file proves the same Lua semantics on both hosts.
                [System.IO.File]::WriteAllText($luaFixture, $luaProgram.Text, [System.Text.Encoding]::ASCII)
                $ErrorActionPreference = 'Continue'
                $luaOutput = @(& $luaExe $luaFixture 2>&1)
                $luaCode = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $savedPreference
                if (Test-Path -LiteralPath $luaFixture -PathType Leaf) {
                    Remove-Item -LiteralPath $luaFixture
                }
            }
            if ($luaCode -ne 0 -or ($luaOutput -join '') -cne $luaProgram.Expected) {
                $failed += "vendored Lua 5.1 did not prove $($luaProgram.Name): exit=$luaCode output=$($luaOutput -join '')"
            }
        }
    }

    $inventoryPath = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) 'tools\mod-inventory.psd1'
    $mainCount = 0
    $mainDirs = @()
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        $failed += "canonical mod inventory missing: $inventoryPath"
    } else {
        $inventory = Import-PowerShellDataFile -LiteralPath $inventoryPath
        foreach ($entry in @($inventory.Mods)) {
            $dir = "$($entry.Dir)"
            $mainPath = Join-Path ([System.IO.Path]::GetFullPath($RepoRoot)) "$dir\scripts\mods\$dir\$dir.lua"
            if (-not (Test-Path -LiteralPath $mainPath -PathType Leaf)) {
                $failed += "canonical main file missing: $mainPath"
                continue
            }
            $mainCount++
            $mainDirs += $dir
            try {
                [void](Get-CanonicalPromotionModVersion `
                    -Text ([System.IO.File]::ReadAllText($mainPath, [System.Text.Encoding]::UTF8)) `
                    -SourceLabel $mainPath)
            } catch {
                $failed += "canonical main file rejected by shared reader: $dir :: $($_.Exception.Message)"
            }
        }
        if ($mainCount -eq 0) { $failed += 'canonical main-file reader coverage was empty' }
        foreach ($stableDir in $STABLE_DIRS) {
            if ($mainDirs -cnotcontains $stableDir) {
                $failed += "canonical main-file reader coverage omitted stable promotion directory: $stableDir"
            }
        }
    }
    foreach ($test in $tests) {
        $result = Test-PromotionAuthorization -Context $test.Context
        if ($result.Allowed -ne $test.Expected) {
            $failed += "$($test.Name): expected=$($test.Expected) actual=$($result.Allowed) reason=$($result.Reason)"
        }
    }

    $cleanResult = Test-PromotionAuthorization -Context $base
    $cleanEnvironment = @(Get-PromotionEnvironmentLines -Requests $base.Requests -Authorization $cleanResult)
    $expectedCleanEnvironment = @(
        'VT2_PROMOTION=1',
        'VT2_PROMOTION_DIRS=crafting_in_modded',
        'VT2_PROMOTION_AUTHORIZED_REQUESTS=crafting_in_modded@0.8.91',
        'VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS='
    )
    if (($cleanEnvironment -join "`n") -cne ($expectedCleanEnvironment -join "`n")) {
        $failed += 'clean authorized promotion did not emit exact pairs and an explicit empty suffix value'
    }

    $suffixedResult = Test-PromotionAuthorization -Context $suffixed
    $suffixedEnvironment = @(Get-PromotionEnvironmentLines -Requests $suffixed.Requests -Authorization $suffixedResult)
    if ($suffixedEnvironment -notcontains 'VT2_PROMOTION_AUTHORIZED_REQUESTS=crafting_in_modded@0.8.91-beta' -or
            $suffixedEnvironment -notcontains 'VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS=crafting_in_modded@0.8.91-beta') {
        $failed += 'exact suffixed maintainer grant did not emit exact request and suffix pairs'
    }

    $mixedResult = Test-PromotionAuthorization -Context $mixed
    $mixedEnvironment = @(Get-PromotionEnvironmentLines -Requests $mixed.Requests -Authorization $mixedResult)
    if ($mixedEnvironment -notcontains 'VT2_PROMOTION_AUTHORIZED_REQUESTS=chaos_wastes_tweaker@0.7.132-beta;gui_tweaker@0.2.289' -or
            $mixedEnvironment -notcontains 'VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS=chaos_wastes_tweaker@0.7.132-beta') {
        $failed += 'mixed authorization did not preserve exact per-directory suffix scope'
    }

    $multipleSuffixedResult = Test-PromotionAuthorization -Context $multipleSuffixed
    $multipleSuffixedEnvironment = @(Get-PromotionEnvironmentLines -Requests $multipleSuffixed.Requests -Authorization $multipleSuffixedResult)
    if ($multipleSuffixedEnvironment -notcontains 'VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS=chaos_wastes_tweaker@0.7.132-beta;crafting_in_modded@0.8.92-rc1') {
        $failed += 'multiple suffixed authorization did not preserve both exact directory/version pairs'
    }

    $staleSuffix = $suffixed.PSObject.Copy()
    $staleSuffix.HeadSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $staleSuffixResult = Test-PromotionAuthorization -Context $staleSuffix
    if (@(Get-PromotionEnvironmentLines -Requests $staleSuffix.Requests -Authorization $staleSuffixResult).Count -ne 0) {
        $failed += 'stale SHA authorization emitted promotion environment or suffix capability'
    }

    $missingSuffix = $suffixed.PSObject.Copy()
    $missingSuffix.Labels = @()
    $missingSuffixResult = Test-PromotionAuthorization -Context $missingSuffix
    if (@(Get-PromotionEnvironmentLines -Requests $missingSuffix.Requests -Authorization $missingSuffixResult).Count -ne 0) {
        $failed += 'missing-label authorization emitted promotion environment or suffix capability'
    }

    function Invoke-ValidationFixture {
        param(
            [hashtable]$Versions,
            [string[]]$Paths,
            [string]$Dirs,
            [AllowNull()][string]$Pairs,
            [AllowNull()][string]$SuffixPairs,
            [bool]$SuffixPairsPresent = $true,
            [string[]]$FailGate = @()
        )

        $reads = @{}
        $calls = New-Object System.Collections.Generic.List[string]
        $reader = {
            param([string]$Path)
            $dir = ($Path.Replace('\', '/') -split '/')[0]
            if (-not $Versions.ContainsKey($dir)) { throw "fixture has no version for '$dir'" }
            $reads[$dir] = 1 + [int]$reads[$dir]
            $raw = $Versions[$dir]
            $sequence = @(
                if ($raw -is [System.Array]) { $raw | ForEach-Object { "$_" } }
                else { "$raw" }
            )
            $index = [Math]::Min($reads[$dir] - 1, $sequence.Count - 1)
            return "local MOD_VERSION = `"$($sequence[$index])`""
        }.GetNewClosure()
        $gate = {
            param([string]$Dir, [string[]]$GatePaths)
            [void]$calls.Add("$Dir|$env:VT2_SUFFIX_OK|$($GatePaths.Count)")
            if ($FailGate -ccontains $Dir) { return 1 }
            return 0
        }.GetNewClosure()
        $errorText = $null
        try {
            Invoke-AuthorizedPromotionValidation -Root '' -Paths $Paths -PromotionFlag '1' `
                -PromotionDirs $Dirs -AuthorizedRequests $Pairs -AuthorizedSuffixRequests $SuffixPairs `
                -AuthorizedSuffixRequestsPresent $SuffixPairsPresent `
                -ReadSource $reader -InvokeGate $gate
        } catch {
            $errorText = $_.Exception.Message
        }
        return [pscustomobject]@{
            Error = $errorText
            Calls = @($calls)
            SuffixAfter = "$env:VT2_SUFFIX_OK"
        }
    }

    $env:VT2_SUFFIX_OK = '1'
    $env:VT2_PROMOTION_SUFFIX_AUTHORIZED = '1'
    $cleanValidation = Invoke-ValidationFixture `
        -Versions @{ crafting_in_modded = '0.8.91' } `
        -Paths @('crafting_in_modded/itemV2.cfg') `
        -Dirs 'crafting_in_modded' `
        -Pairs 'crafting_in_modded@0.8.91' `
        -SuffixPairs ''
    if ($cleanValidation.Error -or ($cleanValidation.Calls -join ';') -cne 'crafting_in_modded||1' -or $cleanValidation.SuffixAfter) {
        $failed += "ambient suffix capability contaminated a clean per-directory gate or survived validation: error=$($cleanValidation.Error) calls=$($cleanValidation.Calls -join ';') after=$($cleanValidation.SuffixAfter)"
    }

    $missingSuffixRecord = Invoke-ValidationFixture `
        -Versions @{ crafting_in_modded = '0.8.91' } `
        -Paths @('crafting_in_modded/itemV2.cfg') `
        -Dirs 'crafting_in_modded' `
        -Pairs 'crafting_in_modded@0.8.91' `
        -SuffixPairs '' `
        -SuffixPairsPresent $false
    if ($missingSuffixRecord.Error -notmatch 'VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS is missing' -or
            $missingSuffixRecord.Calls.Count -ne 0 -or $missingSuffixRecord.SuffixAfter) {
        $failed += "absent suffix record was not distinguished from a present empty record: error=$($missingSuffixRecord.Error) calls=$($missingSuffixRecord.Calls -join ';')"
    }
    $env:VT2_PROMOTION_SUFFIX_AUTHORIZED = $null

    $mixedValidation = Invoke-ValidationFixture `
        -Versions @{ chaos_wastes_tweaker = '0.7.132-beta'; gui_tweaker = '0.2.289' } `
        -Paths @('chaos_wastes_tweaker/CHANGELOG.md', 'gui_tweaker/itemV2.cfg') `
        -Dirs 'chaos_wastes_tweaker;gui_tweaker' `
        -Pairs 'chaos_wastes_tweaker@0.7.132-beta;gui_tweaker@0.2.289' `
        -SuffixPairs 'chaos_wastes_tweaker@0.7.132-beta'
    if ($mixedValidation.Error -or
            ($mixedValidation.Calls -join ';') -cne 'chaos_wastes_tweaker|1|2;gui_tweaker||2' -or
            $mixedValidation.SuffixAfter) {
        $failed += "mixed clean and suffixed gates did not isolate and clear suffix permission per directory: error=$($mixedValidation.Error) calls=$($mixedValidation.Calls -join ';') after=$($mixedValidation.SuffixAfter)"
    }

    $multiSuffixValidation = Invoke-ValidationFixture `
        -Versions @{ chaos_wastes_tweaker = '0.7.132-beta'; crafting_in_modded = '0.8.92-rc1' } `
        -Paths @('chaos_wastes_tweaker/itemV2.cfg', 'crafting_in_modded/itemV2.cfg') `
        -Dirs 'chaos_wastes_tweaker;crafting_in_modded' `
        -Pairs 'chaos_wastes_tweaker@0.7.132-beta;crafting_in_modded@0.8.92-rc1' `
        -SuffixPairs 'chaos_wastes_tweaker@0.7.132-beta;crafting_in_modded@0.8.92-rc1'
    if ($multiSuffixValidation.Error -or
            ($multiSuffixValidation.Calls -join ';') -cne 'chaos_wastes_tweaker|1|2;crafting_in_modded|1|2' -or
            $multiSuffixValidation.SuffixAfter) {
        $failed += "multiple suffixed gates did not receive their own exact permission: error=$($multiSuffixValidation.Error) calls=$($multiSuffixValidation.Calls -join ';') after=$($multiSuffixValidation.SuffixAfter)"
    }

    $treeMismatch = Invoke-ValidationFixture `
        -Versions @{ crafting_in_modded = '0.8.92-beta' } `
        -Paths @('crafting_in_modded/itemV2.cfg') `
        -Dirs 'crafting_in_modded' `
        -Pairs 'crafting_in_modded@0.8.91-beta' `
        -SuffixPairs 'crafting_in_modded@0.8.91-beta'
    if ($treeMismatch.Error -notmatch 'does not match its authorized request pair' -or $treeMismatch.Calls.Count -ne 0 -or $treeMismatch.SuffixAfter) {
        $failed += 'checked-tree/version mismatch did not fail closed before the gate'
    }

    $lateMismatch = Invoke-ValidationFixture `
        -Versions @{ crafting_in_modded = @('0.8.91-beta', '0.8.92-beta') } `
        -Paths @('crafting_in_modded/itemV2.cfg') `
        -Dirs 'crafting_in_modded' `
        -Pairs 'crafting_in_modded@0.8.91-beta' `
        -SuffixPairs 'crafting_in_modded@0.8.91-beta'
    if ($lateMismatch.Error -notmatch 'changed from authorized pair' -or $lateMismatch.Calls.Count -ne 0 -or $lateMismatch.SuffixAfter) {
        $failed += "immediate pre-gate checked-tree version revalidation is missing: error=$($lateMismatch.Error) calls=$($lateMismatch.Calls -join ';')"
    }

    $missingPair = Invoke-ValidationFixture `
        -Versions @{ chaos_wastes_tweaker = '0.7.132-beta'; gui_tweaker = '0.2.289' } `
        -Paths @('chaos_wastes_tweaker/itemV2.cfg', 'gui_tweaker/itemV2.cfg') `
        -Dirs 'chaos_wastes_tweaker;gui_tweaker' `
        -Pairs 'chaos_wastes_tweaker@0.7.132-beta' `
        -SuffixPairs 'chaos_wastes_tweaker@0.7.132-beta'
    if (-not $missingPair.Error -or $missingPair.Calls.Count -ne 0 -or $missingPair.SuffixAfter) {
        $failed += 'missing per-directory authorization pair did not fail closed'
    }

    $duplicatePair = Invoke-ValidationFixture `
        -Versions @{ crafting_in_modded = '0.8.91-beta' } `
        -Paths @('crafting_in_modded/itemV2.cfg') `
        -Dirs 'crafting_in_modded' `
        -Pairs 'crafting_in_modded@0.8.91-beta;crafting_in_modded@0.8.91-beta' `
        -SuffixPairs 'crafting_in_modded@0.8.91-beta'
    if ($duplicatePair.Error -notmatch 'duplicate directory' -or $duplicatePair.Calls.Count -ne 0 -or $duplicatePair.SuffixAfter) {
        $failed += 'duplicate per-directory authorization pair did not fail closed'
    }

    $missingSuffixPair = Invoke-ValidationFixture `
        -Versions @{ crafting_in_modded = '0.8.91-beta' } `
        -Paths @('crafting_in_modded/itemV2.cfg') `
        -Dirs 'crafting_in_modded' `
        -Pairs 'crafting_in_modded@0.8.91-beta' `
        -SuffixPairs ''
    if ($missingSuffixPair.Error -notmatch 'suffix authorization is not exact' -or $missingSuffixPair.Calls.Count -ne 0 -or $missingSuffixPair.SuffixAfter) {
        $failed += "missing suffixed per-directory authorization did not fail closed: error=$($missingSuffixPair.Error) calls=$($missingSuffixPair.Calls -join ';')"
    }

    $wrongSuffixPair = Invoke-ValidationFixture `
        -Versions @{ crafting_in_modded = '0.8.91-beta' } `
        -Paths @('crafting_in_modded/itemV2.cfg') `
        -Dirs 'crafting_in_modded' `
        -Pairs 'crafting_in_modded@0.8.91-beta' `
        -SuffixPairs 'crafting_in_modded@0.8.92-beta'
    if ($wrongSuffixPair.Error -notmatch 'is not an exact suffixed authorized request' -or $wrongSuffixPair.Calls.Count -ne 0 -or $wrongSuffixPair.SuffixAfter) {
        $failed += "foreign suffixed version pair did not fail closed: error=$($wrongSuffixPair.Error) calls=$($wrongSuffixPair.Calls -join ';')"
    }

    $gateFailure = Invoke-ValidationFixture `
        -Versions @{ chaos_wastes_tweaker = '0.7.132-beta'; gui_tweaker = '0.2.289' } `
        -Paths @('chaos_wastes_tweaker/itemV2.cfg', 'gui_tweaker/itemV2.cfg') `
        -Dirs 'chaos_wastes_tweaker;gui_tweaker' `
        -Pairs 'chaos_wastes_tweaker@0.7.132-beta;gui_tweaker@0.2.289' `
        -SuffixPairs 'chaos_wastes_tweaker@0.7.132-beta' `
        -FailGate @('chaos_wastes_tweaker')
    if ($gateFailure.Error -notmatch 'failed with exit 1' -or
            ($gateFailure.Calls -join ';') -cne 'chaos_wastes_tweaker|1|2' -or
            $gateFailure.SuffixAfter) {
        $failed += "failed gate did not stop the sequence and clear its suffix permission: error=$($gateFailure.Error) calls=$($gateFailure.Calls -join ';') after=$($gateFailure.SuffixAfter)"
    }
    if ($failed.Count -gt 0) {
        Write-Host '[check_promotion_authorization] SELF-TEST FAILED' -ForegroundColor Red
        $failed | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        return 2
    }
    Write-Host "[check_promotion_authorization] SELF-TEST PASS - $($tests.Count) authorization cases, $($readerCases.Count) lexical reader adversaries, eight repository-dialect label proofs, two Lua 5.1 semantic proofs, $mainCount canonical main files (including all $($STABLE_DIRS.Count) stable promotion dirs), exact environment records, and eleven checked-tree/per-directory capability cases." -ForegroundColor Green
    return 0
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
if ($ValidateAuthorizedEnvironment) {
    $gateScript = Join-Path $PSScriptRoot 'check_promotion.ps1'
    $gate = {
        param([string]$Dir, [string[]]$Paths)
        & $gateScript -Mod $Dir -RepoRoot $root -ChangedPath $Paths
        return [int]$LASTEXITCODE
    }.GetNewClosure()
    $authorizedSuffixRequestsPresent = Test-Path -LiteralPath 'Env:VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS'
    try {
        Invoke-AuthorizedPromotionValidation -Root $root -Paths $ChangedPath `
            -PromotionFlag $env:VT2_PROMOTION `
            -PromotionDirs $env:VT2_PROMOTION_DIRS `
            -AuthorizedRequests $env:VT2_PROMOTION_AUTHORIZED_REQUESTS `
            -AuthorizedSuffixRequests $env:VT2_PROMOTION_SUFFIX_AUTHORIZED_REQUESTS `
            -AuthorizedSuffixRequestsPresent $authorizedSuffixRequestsPresent `
            -InvokeGate $gate
        if (-not $Quiet) {
            Write-Host '[check_promotion_authorization] CHECKED-TREE VALIDATION PASS - every stable gate matched its exact authorized directory/version/suffix pair.' -ForegroundColor Green
        }
        exit 0
    } catch {
        $env:VT2_SUFFIX_OK = ''
        Write-Host "[check_promotion_authorization] CHECKED-TREE VALIDATION FAILED - $($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }
}

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
    OwnerLogin = "$($event.repository.owner.login)"
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
    $environmentLines = @(Get-PromotionEnvironmentLines -Requests $requests -Authorization $result)
    if ($environmentLines.Count -lt 2) {
        Write-Host '[check_promotion_authorization] ERROR - authorized request produced no promotion environment.' -ForegroundColor Red
        exit 2
    }
    $lines = ($environmentLines -join "`n") + "`n"
    [System.IO.File]::AppendAllText($env:GITHUB_ENV, $lines, (New-Object System.Text.UTF8Encoding($false)))
}

exit 0
