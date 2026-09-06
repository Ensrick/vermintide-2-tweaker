# Offline actual-production publisher/ship handoff checks; no native or live HTTP.
[CmdletBinding()]
param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'tools\ship\exception-pin-finalization.ps1')
. (Join-Path $repo 'qa\_test_fixtures\publication_handoff_fixture.ps1')
$root = Join-Path ([IO.Path]::GetTempPath()) ('vt2-handoff-suite-' + [guid]::NewGuid().ToString('N'))
$script:passed = 0
function Assert([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "[publication-pin-handoff] $Name" }
    $script:passed++
}
try {
    [IO.Directory]::CreateDirectory($root) | Out-Null
    $prepared = New-VtPublishedPinContext -RepoRoot $root -Mod fixture -ModId fixture -SourceCommit ('c' * 40) `
        -ModTree ('b' * 40) -Version '0.1.2-dev' -PublishedId '123' -ReleaseTag 'mods-2026-09-06'
    $program = Get-VtPublicationHandoffFixtureProgram -RepoRoot $repo
    $confirmed = @('ExistingSuccess','NewSuccess','ExistingReceiptFailure','NewReceiptFailure',
        'ExistingReportFailure','NewReportFailure','ExistingCleanupFailure','NewCleanupFailure',
        'ExistingWarningStop','NewWarningStop','ExistingMutexWarningStop','NewMutexWarningStop')
    $unconfirmed = @('ExistingUploadAmbiguous','NewUploadAmbiguous','ExistingUploadFailure','NewUploadFailure',
        'NewDraftAmbiguous','NewDraftStillDraft','NewDraftWrongId','NewDraftWrongTag','NewDraftMissingFlag',
        'ExistingDraft','ExistingMissingDraft','ExistingStringDraft','ExistingWrongTag','ExistingZeroId',
        'PreArmed','ExtraField','MissingPrepared','MalformedPrepared','WrongPurpose','WrongRepository',
        'WrongRoot','WrongMod','WrongModId','WrongCommit','WrongTree','WrongVersion','WrongPublishedId','WrongReleaseTag',
        'MultipleReceiptInputs','MultipleStagedRows','MissingStagedRow','WrongStagedSource','WrongStagedVersion','BootstrapPrepared')
    foreach ($case in @($confirmed + $unconfirmed + @('Bootstrap','DryRun','NoHolder'))) {
        $result = Invoke-VtPublicationHandoffFixture -RepoRoot $repo -FixtureRoot $root -PreparedJson $prepared -Case $case -Program $program
        Assert ($result.PublisherCleanupCount -eq 2) "$case did not execute both actual publisher cleanup blocks."
        Assert ($result.Events -contains 'publisher-release-mutex-release') "$case skipped release-mutex cleanup."
        Assert ($result.Events -contains 'publisher-launcher-cleanup') "$case skipped launcher cleanup."
        Assert ($result.Events -contains 'publisher-joined-lease-cleanup') "$case skipped joined-lease cleanup."
        if ($confirmed -contains $case) {
            Assert ($result.PublishedJson -ceq $prepared) "$case lost confirmed publisher-owned identity."
            Assert ($result.ImportedJson -ceq $prepared) "$case did not import outcome through actual ship finally."
            Assert (@($result.Requests | Where-Object ArmedBefore).Count -eq 0) "$case armed before the final successful request."
            if ($case.EndsWith('Success', [StringComparison]::Ordinal)) {
                Assert ([string]::IsNullOrEmpty($result.Error) -and $result.ReceiptWritten) "$case did not complete ordinary receipt handoff."
            }
            else {
                Assert (-not [string]::IsNullOrEmpty($result.Error)) "$case fixture failed to inject a post-confirmation error."
                Assert ($result.Error.Contains('publish-release.ps1 failed before Workshop upload:')) "$case bypassed the actual ship catch."
                $expectedError = if ($case.EndsWith('ReceiptFailure')) { 'WriteAllBytes' }
                    elseif ($case.EndsWith('ReportFailure')) { 'planted-report-failure' }
                    elseif ($case.EndsWith('CleanupFailure')) { 'planted-launcher-cleanup-failure' }
                    elseif ($case.EndsWith('MutexWarningStop')) { 'planted-mutex-release-failure' }
                    else { 'planted-stage-cleanup-failure' }
                Assert ($result.Error.Contains($expectedError)) "$case lost its original injected error."
            }
        }
        elseif ($case -eq 'PreArmed') {
            # A deliberately forged caller holder is rejected, not silently reset.
            # Canonical ship always creates the fresh empty holder itself.
            Assert ($result.Requests.Count -eq 0 -and $result.Error.Contains('fresh, closed two-field')) 'Pre-armed holder reached mutation.'
        }
        else {
            Assert ($null -eq $result.PublishedJson -and $null -eq $result.ImportedJson) "$case inferred publication from intent or ambiguous response."
            if ($case -in @('Bootstrap','DryRun','NoHolder')) {
                Assert ([string]::IsNullOrEmpty($result.Error)) "$case unexpectedly failed its valid excluded flow."
                if ($case -eq 'DryRun') { Assert ($result.Requests.Count -eq 0) 'DryRun reached remote mutation.' }
            }
            else {
                Assert (-not [string]::IsNullOrEmpty($result.Error)) "$case did not fail closed."
            }
        }
        if ($case -notmatch '^(Existing|New|Bootstrap)$' -and $case -in @('ExtraField','MissingPrepared','MalformedPrepared',
            'WrongPurpose','WrongRepository','WrongRoot','WrongMod','WrongModId','WrongCommit','WrongTree','WrongVersion',
            'WrongPublishedId','WrongReleaseTag','MultipleReceiptInputs','MultipleStagedRows','MissingStagedRow',
            'WrongStagedSource','WrongStagedVersion','BootstrapPrepared')) {
            Assert ($result.Requests.Count -eq 0) "$case validation happened after remote mutation."
        }
        if ($case.StartsWith('New', [StringComparison]::Ordinal) -and $result.Requests.Count -gt 0) {
            Assert ($result.Requests[0].Method -ceq 'POST' -and $result.Requests[0].Uri.EndsWith('/releases')) "$case did not use real draft creation."
        }
        $manifest = @($result.Requests | Where-Object { $_.Uri -match '/assets\?name=manifest.json$' })
        if ($manifest.Count) {
            Assert ($manifest.Count -eq 1 -and $manifest[0].Bytes -ceq 'e30=') "$case did not upload exact immutable manifest bytes once."
            $assetCalls = @($result.Requests | Where-Object { $_.Uri -match '/assets\?name=' })
            Assert ($assetCalls[-1].Uri -match 'name=manifest.json$') "$case did not retain manifest-last publication."
        }
        Write-Host "[publication-pin-handoff] PASS $case"
    }
    # Source inventory is canonical: a manifest ModId is not a lowercase folder
    # slug. In particular Weapons of Chaos has always published as uppercase WOC.
    $inventory = Import-PowerShellDataFile -LiteralPath (Join-Path $repo 'tools\mod-inventory.psd1')
    foreach ($row in $inventory.Mods) {
        $context = New-VtPublishedPinContext -RepoRoot $root -Mod $row.Dir -ModId $row.ModId `
            -SourceCommit ('c' * 40) -ModTree ('b' * 40) -Version '0.1.2-dev' `
            -PublishedId $row.WorkshopId -ReleaseTag 'mods-2026-09-06'
        $decoded = ConvertFrom-VtPublishedPinContext -Json $context
        Assert ($decoded.Mod -ceq $row.Dir -and $decoded.ModId -ceq $row.ModId) "Canonical inventory identity $($row.Dir) changed case or was rejected."
        Assert-VtPinPublicationHandoff -Handoff @{ PreparedJson = $context; PublishedJson = $null } -ExpectedJson $context
        Assert ($decoded.PublishedId -ceq [string]$row.WorkshopId) "Canonical inventory Workshop identity $($row.Dir) changed."
    }
    $woc = @($inventory.Mods | Where-Object { $_.Dir -ceq 'weapons_of_chaos' })
    Assert ($woc.Count -eq 1 -and $woc[0].ModId -ceq 'WOC') 'The uppercase WOC integration control is no longer canonical; update this explicit fixture.'
    $wocContext = New-VtPublishedPinContext -RepoRoot $root -Mod $woc[0].Dir -ModId $woc[0].ModId `
        -SourceCommit ('c' * 40) -ModTree ('b' * 40) -Version '0.1.2-dev' `
        -PublishedId $woc[0].WorkshopId -ReleaseTag 'mods-2026-09-06'
    foreach ($case in @('ExistingSuccess','NewReceiptFailure','WrongModIdCase')) {
        $result = Invoke-VtPublicationHandoffFixture -RepoRoot $repo -FixtureRoot $root -PreparedJson $wocContext -Case $case -Program $program
        if ($case -eq 'WrongModIdCase') {
            Assert ($result.Requests.Count -eq 0 -and $null -eq $result.ImportedJson -and
                $result.Error.Contains("publisher-owned 'ModId'")) 'A lowercase alias was accepted for canonical WOC.'
        }
        else {
            Assert ($result.PublishedJson -ceq $wocContext -and $result.ImportedJson -ceq $wocContext) "WOC $case lost its exact case-preserved identity."
            Assert (($case -eq 'ExistingSuccess' -and [string]::IsNullOrEmpty($result.Error)) -or
                ($case -eq 'NewReceiptFailure' -and $result.Error.Contains('WriteAllBytes'))) "WOC $case did not exercise its intended outcome."
        }
    }
    Write-Host "[publication-pin-handoff] PASS $script:passed assertions across $($confirmed.Count + $unconfirmed.Count + 3) baseline cases, $($inventory.Mods.Count) inventory identities and 3 WOC cases."
}
finally {
    Remove-VtPublicationHandoffFixtureDirectory -Path $root -ParentRoot ([IO.Path]::GetTempPath()) -LeafPattern '^vt2-handoff-suite-[0-9a-f]{32}$'
}
