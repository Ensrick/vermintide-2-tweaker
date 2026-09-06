# Offline publisher -> ship handoff fixture. No live HTTP, launcher or lease work.
# The tested preparation, publication branches, receipt writer, publisher cleanup
# blocks, and ship invocation/import are extracted from the production AST.

function Remove-VtPublicationHandoffFixtureDirectory {
    param([string]$Path, [string]$ParentRoot, [string]$LeafPattern)
    $root = [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\','/'))
    $parent = [IO.Path]::GetFullPath($ParentRoot).TrimEnd([char[]]@('\','/'))
    if (-not $root.StartsWith($parent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($root) -notmatch $LeafPattern) { throw 'Unsafe fixture cleanup target.' }
    if (-not (Test-Path -LiteralPath $root)) { return }
    $component = Get-Item -LiteralPath $root -Force
    while ($null -ne $component) {
        if ($component.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture cleanup refuses a reparse component.' }
        $component = $component.Parent
    }
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $files = New-Object 'System.Collections.Generic.List[string]'
    $directories = New-Object 'System.Collections.Generic.List[string]'
    $pending.Enqueue($root)
    while ($pending.Count) {
        $directory = $pending.Dequeue()
        $directories.Add($directory)
        foreach ($entry in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $full = [IO.Path]::GetFullPath($entry.FullName)
            if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
                ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Unsafe fixture descendant; nothing removed.' }
            if ($entry.PSIsContainer) { $pending.Enqueue($full) } else { $files.Add($full) }
        }
    }
    # Every path has been validated before the first individual deletion.
    foreach ($file in $files) {
        if ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture file changed to a reparse point.' }
        Remove-Item -LiteralPath $file -Force
    }
    foreach ($directory in @($directories | Sort-Object Length -Descending)) {
        if ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture directory changed to a reparse point.' }
        if (@(Get-ChildItem -LiteralPath $directory -Force).Count) { throw 'Fixture directory is not empty; cleanup stops.' }
        [IO.Directory]::Delete($directory, $false)
    }
}

function Get-VtPublicationHandoffFixtureProgram {
    param([Parameter(Mandatory)][string]$RepoRoot)
    $tokens = $null; $errors = $null
    # PS5 ParseFile may decode BOM-less UTF-8 differently from ReadAllText.
    # Derive both AST offsets and selected extents from the same decoded input.
    $source = [IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\publish-release\publish-release.ps1'), [Text.Encoding]::UTF8)
    $publisher = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Production publisher did not parse.' }
    $owners = @($publisher.FindAll({ param($node)
        if ($node -isnot [Management.Automation.Language.TryStatementAst]) { return $false }
        return @($node.Body.Statements | Where-Object {
            $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
            $_.Left.Extent.Text -ceq '$publisherPinContext'
        }).Count -eq 1
    }, $true))
    if ($owners.Count -ne 1) { throw 'Expected one exact production handoff preparation owner.' }
    $inner = $owners[0]
    $start = @($inner.Body.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -and
        $_.Left.Extent.Text -ceq '$publisherPinContext'
    })[0].Extent.StartOffset
    $outer = $inner.Parent
    while ($outer -and $outer -isnot [Management.Automation.Language.TryStatementAst]) { $outer = $outer.Parent }
    if (-not $outer -or -not $inner.Finally -or -not $outer.Finally -or
        -not $inner.Finally.Extent.Text.Contains('$releaseMutationMutex.Dispose()') -or
        -not $outer.Finally.Extent.Text.Contains('Remove-PublicationStageDirectory') -or
        -not $outer.Finally.Extent.Text.Contains('Exit-VmbMachineTransactionLease')) {
        throw 'Production publisher cleanup ownership changed; fixture extraction must be reviewed.'
    }
    $tail = $source.Substring($start, $inner.Body.Extent.EndOffset - 1 - $start)
    if (-not $tail.Contains('Copy-PublicationReceiptOutput') -or
        -not $tail.Contains('Publish-GitHubReleaseAssetsById') -or
        -not $tail.Contains('Publish-GitHubDraftRelease')) { throw 'Publisher mutation tail extraction is incomplete.' }
    $publisherProgram = [scriptblock]::Create(
        "try { try {`n" + $tail + "`n} finally " + $inner.Finally.Extent.Text +
        "`n} finally " + $outer.Finally.Extent.Text)

    $shipText = [IO.File]::ReadAllText((Join-Path $RepoRoot 'tools\ship\ship.ps1'), [Text.Encoding]::UTF8)
    $ship = [Management.Automation.Language.Parser]::ParseInput($shipText, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw 'Production ship did not parse.' }
    $calls = @($ship.FindAll({ param($node)
        if ($node -isnot [Management.Automation.Language.TryStatementAst]) { return $false }
        return @($node.Body.Statements | Where-Object {
            $_ -is [Management.Automation.Language.PipelineAst] -and
            $_.Extent.Text.Contains('& $pubScript') -and $_.Extent.Text.Contains('-SourcePinHandoff')
        }).Count -eq 1
    }, $true))
    if ($calls.Count -ne 1 -or -not $calls[0].Finally -or
        -not $calls[0].Finally.Extent.Text.Contains('$publishedPinContext = $sourcePinHandoff.PublishedJson')) {
        throw 'Expected the exact production publisher invocation and ship import finally.'
    }
    return [pscustomobject]@{
        Publisher = $publisherProgram
        ShipInvocation = [scriptblock]::Create($calls[0].Extent.Text)
        PublisherCleanupCount = 2
    }
}

function Invoke-VtPublicationHandoffFixture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$FixtureRoot,
        [Parameter(Mandatory)][string]$PreparedJson,
        [Parameter(Mandatory)][string]$Case,
        [object]$Program
    )
    . (Join-Path $RepoRoot 'tools\ship\exception-pin-finalization.ps1')
    . (Join-Path $RepoRoot 'tools\publish-release\github-release-api.ps1')
    if ($null -eq $Program) { $Program = Get-VtPublicationHandoffFixtureProgram -RepoRoot $RepoRoot }
    $canonical = ConvertFrom-VtPublishedPinContext -Json $PreparedJson
    $fixtureBase = [IO.Path]::GetFullPath($FixtureRoot).TrimEnd([char[]]@('\','/'))
    if (-not [string]::Equals($fixtureBase, [IO.Path]::GetFullPath($canonical.RepoRoot).TrimEnd([char[]]@('\','/')),
        [StringComparison]::OrdinalIgnoreCase)) { throw 'Prepared context must target exactly the isolated fixture root.' }
    $work = Join-Path $fixtureBase ('handoff-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $state = @{
        Events = New-Object 'System.Collections.Generic.List[string]'
        Requests = New-Object 'System.Collections.Generic.List[object]'
        Error = $null; Imported = $null; ReceiptWritten = $false
        Mode = $Case; Holder = $null
    }
    try {
        $repoRoot = $canonical.RepoRoot
        $sourceCommit = $canonical.SourceCommit
        $Tag = $canonical.ReleaseTag
        $Mod = $canonical.Mod
        $ghRepo = $canonical.Repository
        $stage = Join-Path $work 'stage'
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        $manifestPath = Join-Path $work 'manifest.json'
        [IO.File]::WriteAllText($manifestPath, '{}')
        $manifestMods = @([pscustomobject]@{
            mod_id = $canonical.ModId; source_commit = $canonical.SourceCommit
            version = $canonical.Version; workshop_id = $canonical.PublishedId
        })
        $receiptInputs = @([pscustomobject]@{
            Folder = $canonical.Mod; ModId = $canonical.ModId; Version = $canonical.Version
        })
        $sourcePinHandoff = @{ PreparedJson = $PreparedJson; PublishedJson = $null }
        $state.Holder = $sourcePinHandoff
        $filterActive = $true
        $releaseExists = -not $Case.StartsWith('New', [StringComparison]::Ordinal)
        $DryRun = ($Case -eq 'DryRun')
        $carriedIdSet = @{}
        $targetRelease = [pscustomobject]@{ id = 777; tag_name = $Tag; draft = $false; assets = @() }
        $receiptOutputAssetName = 'publication-receipt-fixture.json'
        $assetSnapshots = @(
            [pscustomobject]@{ Name = 'fixture.zip'; Bytes = [byte[]](1,2,3); ContentType = 'application/zip' },
            [pscustomobject]@{ Name = $receiptOutputAssetName; Bytes = [byte[]](4,5,6); ContentType = 'application/json' },
            [pscustomobject]@{ Name = 'manifest.json'; Bytes = [Text.Encoding]::UTF8.GetBytes('{}'); ContentType = 'application/json' }
        )
        $assetPaths = @('fixture.zip', $receiptOutputAssetName, 'manifest.json')
        $receiptPath = Join-Path $work 'receipt.json'
        if ($Case.EndsWith('ReceiptFailure', [StringComparison]::Ordinal)) {
            # Real File.WriteAllBytes failure, not a replacement receipt function.
            $receiptPath = Join-Path $work 'absent-parent\receipt.json'
        }
        switch ($Case) {
            'PreArmed' { $sourcePinHandoff.PublishedJson = $PreparedJson }
            'NoHolder' { $sourcePinHandoff = $null; $state.Holder = $null }
            'ExtraField' { $sourcePinHandoff.Other = 'not allowed' }
            'MissingPrepared' { $sourcePinHandoff.Remove('PreparedJson') }
            'MalformedPrepared' { $sourcePinHandoff.PreparedJson = '{broken' }
            'MultipleReceiptInputs' { $receiptInputs += $receiptInputs[0] }
            'MultipleStagedRows' { $manifestMods += $manifestMods[0] }
            'MissingStagedRow' { $manifestMods = @() }
            'WrongStagedSource' { $manifestMods[0].source_commit = 'e' * 40 }
            'WrongStagedVersion' { $manifestMods[0].version = '9.9.9-dev' }
            'Bootstrap' { $manifestMods[0].workshop_id = '0'; $sourcePinHandoff.PreparedJson = $null }
            'BootstrapPrepared' { $manifestMods[0].workshop_id = '0' }
            'ExistingDraft' { $targetRelease.draft = $true }
            'ExistingMissingDraft' { $targetRelease.PSObject.Properties.Remove('draft') }
            'ExistingStringDraft' { $targetRelease.draft = 'false' }
            'ExistingWrongTag' { $targetRelease.tag_name = 'mods-2000-01-01' }
            'ExistingZeroId' { $targetRelease.id = 0 }
        }
        $wrongFields = @{
            WrongPurpose = @('Purpose','other'); WrongRepository = @('Repository','other/repo')
            WrongRoot = @('RepoRoot',(Join-Path $fixtureBase 'foreign')); WrongMod = @('Mod','other_mod')
            WrongModId = @('ModId','other'); WrongCommit = @('SourceCommit',('d' * 40))
            WrongTree = @('ModTree',('e' * 40)); WrongVersion = @('Version','9.9.9-dev')
            WrongPublishedId = @('PublishedId','999'); WrongReleaseTag = @('ReleaseTag','mods-2000-01-01')
        }
        if ($wrongFields.ContainsKey($Case)) {
            $changed = $PreparedJson | ConvertFrom-Json
            $axis = $wrongFields[$Case]
            $changed.($axis[0]) = $axis[1]
            $sourcePinHandoff.PreparedJson = $changed | ConvertTo-Json -Compress
        }

        # These fixtures enter below the publisher's independent authorization /
        # immutable-snapshot preparation. They do not claim to retest those gates.
        function git {
            $expected = @('-C', $canonical.RepoRoot, 'rev-parse', ($canonical.SourceCommit + ':' + $canonical.Mod + '/scripts/mods'))
            if (($args -join '|') -cne ($expected -join '|')) { throw 'Unexpected fixture source-tree lookup.' }
            $state.Events.Add('source-tree-checked')
            return $canonical.ModTree
        }
        function Get-GitHubReleaseToken { throw 'Fixture must not request a live token.' }
        function Invoke-GitHubReleaseApiRequest {
            param($Method, $Uri, [byte[]]$InputBytes, $ContentType)
            if ($Uri -notmatch '^https://(?:api|uploads)\.github\.com/repos/Ensrick/vermintide-2-tweaker/releases') {
                throw 'Unexpected fixture remote coordinate.'
            }
            $state.Requests.Add([pscustomobject]@{
                Method = $Method; Uri = $Uri; ArmedBefore = ($null -ne $state.Holder.PublishedJson)
                Bytes = [Convert]::ToBase64String([byte[]]$InputBytes)
            })
            $state.Events.Add("request:$Method")
            $status = 201; $response = $null
            if ($Uri -match '/assets\?name=manifest.json$') {
                if ($Case.EndsWith('UploadAmbiguous', [StringComparison]::Ordinal)) { $status = 0 }
                if ($Case.EndsWith('UploadFailure', [StringComparison]::Ordinal)) { $status = 500 }
            }
            if ($Method -eq 'POST' -and $Uri.EndsWith('/releases', [StringComparison]::Ordinal)) {
                $response = [pscustomobject]@{ id = 888; tag_name = $Tag; draft = $true; assets = @() }
            }
            if ($Method -eq 'PATCH') {
                $status = 200
                $response = [pscustomobject]@{ id = 888; tag_name = $Tag; draft = $false; assets = @() }
                switch ($Case) {
                    'NewDraftAmbiguous' { $status = 0 }
                    'NewDraftStillDraft' { $response.draft = $true }
                    'NewDraftWrongId' { $response.id = 889 }
                    'NewDraftWrongTag' { $response.tag_name = 'mods-2000-01-01' }
                    'NewDraftMissingFlag' { $response.PSObject.Properties.Remove('draft') }
                }
            }
            return [pscustomobject]@{
                StatusCode = $status; Content = ($response | ConvertTo-Json -Compress)
                Bytes = [byte[]]@(); Error = 'fixture transport failure'
            }
        }
        function Write-Host {
            param([object]$Object, $ForegroundColor, [switch]$NoNewline)
            if ([string]$Object -match '^Release (updated|published):') {
                $state.Events.Add('report-after-publication')
                if ($Case.EndsWith('ReportFailure', [StringComparison]::Ordinal)) { throw 'planted-report-failure' }
            }
        }
        function Remove-PublicationStageDirectory {
            param($Path, $RepoRoot)
            $state.Events.Add('publisher-stage-cleanup')
            if ($Case -in @('ExistingWarningStop','NewWarningStop')) { throw 'planted-stage-cleanup-failure' }
        }
        function Exit-VmbLauncherExecutableLease {
            param($Lease)
            $state.Events.Add('publisher-launcher-cleanup')
            if ($Case.EndsWith('CleanupFailure', [StringComparison]::Ordinal)) { throw 'planted-launcher-cleanup-failure' }
        }
        function Exit-VmbMachineTransactionLease {
            param($Lease)
            $state.Events.Add('publisher-joined-lease-cleanup')
        }
        function Fail { param([string]$Message) throw $Message }
        $releaseMutationMutex = [pscustomobject]@{}
        $releaseMutationMutex | Add-Member ScriptMethod ReleaseMutex {
            $state.Events.Add('publisher-release-mutex-release')
            if ($Case.EndsWith('MutexWarningStop', [StringComparison]::Ordinal)) { throw 'planted-mutex-release-failure' }
        }.GetNewClosure()
        $releaseMutationMutex | Add-Member ScriptMethod Dispose {
            $state.Events.Add('publisher-release-mutex-dispose')
        }.GetNewClosure()
        $releaseMutationLockHeld = $true
        $ownsLauncherExecutableLease = $true
        $effectiveLauncherLease = [pscustomobject]@{ FixtureOnly = $true }
        $releaseTransactionLease = [pscustomobject]@{ FixtureOnly = $true; OwnsMutex = $false }
        $publicationAuthorizationJson = '{}'
        $launcherResolution = [pscustomobject]@{ Path = 'never-launch'; Source = 'fixture'; ApprovalAnchor = 'fixture' }
        $launcherExecutableLease = [pscustomobject]@{ FixtureOnly = $true }
        $publishedPinContext = $null
        $publisherProgram = $Program.Publisher
        $pubScript = {
            param($Tag, $Mods, [switch]$SkipBuild, $PublicationAuthorizationJson, $PublicationReceiptOutputPath,
                [hashtable]$SourcePinHandoff, $LauncherPath, $LauncherSource, $LauncherApprovalAnchor, $LauncherExecutableLease)
            if (-not [object]::ReferenceEquals($SourcePinHandoff, $state.Holder)) { throw 'Fixture lost the actual reference handoff.' }
            $LASTEXITCODE = 0
            & $publisherProgram
        }
        $WarningPreference = if ($Case.EndsWith('WarningStop', [StringComparison]::Ordinal)) { 'Stop' } else { 'Continue' }
        try { . $Program.ShipInvocation | Out-Null }
        catch { $state.Error = $_.Exception.Message }
        $state.Imported = $publishedPinContext
        $state.ReceiptWritten = [IO.File]::Exists($receiptPath)
        return [pscustomobject]@{
            PublishedJson = $sourcePinHandoff.PublishedJson; ImportedJson = $state.Imported
            Error = $state.Error; Requests = @($state.Requests.ToArray()); Events = @($state.Events.ToArray())
            ReceiptWritten = $state.ReceiptWritten; PublisherCleanupCount = $Program.PublisherCleanupCount
        }
    }
    finally {
        Remove-VtPublicationHandoffFixtureDirectory -Path $work -ParentRoot $fixtureBase -LeafPattern '^handoff-[0-9a-f]{32}$'
    }
}
