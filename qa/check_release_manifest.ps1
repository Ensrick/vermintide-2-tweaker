# check_release_manifest.ps1 - validate GitHub release provenance metadata.
#
# Exit 0 = valid (legacy carried entries may warn); exit 2 = invalid manifest.
# -SelfTest is offline and auto-discovered by qa/run_selftests.ps1.

[CmdletBinding()]
param(
    [string]$ManifestPath,
    [string]$StageRoot,
    [string[]]$RequiredModIds = @(),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $repoRoot 'tools\publish-release\release-manifest.ps1')
. (Join-Path $repoRoot 'tools\ship\publication-authorization.ps1')

function Invoke-SelfTest {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-release-manifest-" + [guid]::NewGuid().ToString('N'))
    $modStage = Join-Path $temp 'example'
    New-Item -ItemType Directory -Path $modStage -Force | Out-Null
    try {
        [System.IO.File]::WriteAllBytes((Join-Path $modStage 'aaaaaaaaaaaaaaaa.mod_bundle'), [byte[]](1, 2, 3, 4))
        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'descriptor')
        $bundleFiles = New-BundleFileRecords `
            -BundleDirectory $modStage `
            -ExpectedDescriptorName 'example.mod' `
            -ExpectedRootBundle 'aaaaaaaaaaaaaaaa.mod_bundle'
        $entry = [ordered]@{
            mod_id = 'example'; friendly_name = 'Example'; workshop_id = '1234567890'
            version = '1.2.3-dev'; asset_filename = 'example.zip'; sha256 = ('a' * 64)
            visibility = 'friends_only'; source_commit = ('b' * 40); source_state = 'clean'
            builder = [ordered]@{ name = 'VMBLauncher'; version = '1.2.3' }
            root_bundle = 'aaaaaaaaaaaaaaaa.mod_bundle'
            descriptor_name = 'example.mod'
            bundle_files = $bundleFiles
            publication_authorization = [ordered]@{
                mode = 'hosted_qa'; source_commit = ('b' * 40)
                checked_at_utc = '2026-07-26T00:00:00Z'; default_branch = 'master'
                default_branch_commit = ('b' * 40); merged_pr_number = 724
                qa_check = 'qa-gate'; qa_check_url = 'https://example.invalid/check/724'
                qa_completed_at_utc = '2026-07-26T00:00:00Z'
            }
        }
        $manifest = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'; published_at = '2026-07-13T00:00:00Z'
            mods = @($entry)
        }

        $failures = [System.Collections.Generic.List[string]]::new()
        function Assert([bool]$Condition, [string]$Description) {
            if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
            else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $failures.Add($Description) }
        }

        $authSha = ('b' * 40)
        $liveAuth = Test-PublicationAuthorizationSnapshot `
            -SourceCommit $authSha `
            -DefaultBranch master `
            -DefaultBranchCommit $authSha `
            -PullRequests @([pscustomobject]@{
                number = 724; merged_at = '2026-07-26T00:00:00Z'
                merge_commit_sha = $authSha; base = [pscustomobject]@{ ref = 'master' }
            }) `
            -CheckRuns @([pscustomobject]@{
                name = 'qa-gate'; head_sha = $authSha; status = 'completed'
                conclusion = 'success'; completed_at = '2026-07-26T00:05:00Z'
                html_url = 'https://example.invalid/check/724'
            })
        $forgedAuth = $liveAuth.Evidence | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $forgedAuth.merged_pr_number = 999
        Assert (-not (Test-PublicationEvidenceMatchesLive -CallerEvidence $forgedAuth -LiveEvidence $liveAuth.Evidence).Ok) 'rejects forged caller authorization JSON against independently queried live evidence'

        $roundTrippedAuth = $liveAuth.Evidence | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        Assert (Test-PublicationEvidenceMatchesLive -CallerEvidence $roundTrippedAuth -LiveEvidence $liveAuth.Evidence).Ok 'accepts an equivalent JSON round-tripped UTC completion timestamp'
        $differentCompletedAt = $liveAuth.Evidence | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $differentCompletedAt.qa_completed_at_utc = '2026-07-26T00:05:01Z'
        Assert (-not (Test-PublicationEvidenceMatchesLive -CallerEvidence $differentCompletedAt -LiveEvidence $liveAuth.Evidence).Ok) 'rejects a genuinely different QA completion timestamp'

        $staleCallerAuth = $liveAuth.Evidence | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $movedHeadAuth = $liveAuth.Evidence | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        $movedHeadAuth.source_commit = ('c' * 40)
        $movedHeadAuth.default_branch_commit = ('c' * 40)
        Assert (-not (Test-PublicationEvidenceMatchesLive -CallerEvidence $staleCallerAuth -LiveEvidence $movedHeadAuth).Ok) 'rejects caller evidence made stale by a default-branch HEAD move'

        $valid = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert $valid.Valid 'accepts complete source-to-bundle provenance'
        Assert ($valid.Warnings.Count -eq 0) 'complete provenance emits no warnings'

        $immutableOutput = Get-VtBundleOutputSet `
            -BundleDirectory $modStage `
            -ExpectedDescriptorName 'example.mod' `
            -ExpectedRootBundle 'aaaaaaaaaaaaaaaa.mod_bundle'
        $immutableProofs = @($immutableOutput.Files | ForEach-Object {
            [pscustomobject]@{
                Path = [string]$_.Name
                Length = [long]$_.Length
                Sha256 = [string]$_.Sha256
                Bytes = [System.IO.File]::ReadAllBytes((Join-Path $modStage $_.Name))
            }
        })
        $exactZipBytes = New-ReleaseZipBytesFromImmutableOutput `
            -OutputSet $immutableOutput `
            -BundleFiles $immutableProofs `
            -Version "$($entry.version)"
        $exactZip = Join-Path $temp 'exact.zip'
        [System.IO.File]::WriteAllBytes($exactZip, [byte[]]$exactZipBytes)
        $exactZipVerdict = Test-ReleaseZipSnapshot `
            -ZipBytes $exactZipBytes `
            -ManifestEntry $entry
        Assert $exactZipVerdict.Valid 'immutable zip snapshot contains only exact manifest bundle bytes and updater version'
        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'mutated-after-proof')
        $afterStageMutation = New-ReleaseZipBytesFromImmutableOutput `
            -OutputSet $immutableOutput `
            -BundleFiles $immutableProofs `
            -Version "$($entry.version)"
        Assert (
            [System.BitConverter]::ToString($afterStageMutation) -ceq
                [System.BitConverter]::ToString($exactZipBytes)
        ) 'mutable staging replacement cannot alter an immutable commit-byte zip'
        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'descriptor')
        [System.IO.File]::WriteAllText(
            (Join-Path $modStage 'vt2updater_version.txt'),
            "$($entry.version)",
            [System.Text.Encoding]::ASCII)
        Assert (
            (Get-ReleaseZipSnapshotBindingMode -ManifestEntry $entry -IsStaged $true -IsCarried $false) -eq
                'exact_bundle_files'
        ) 'newly staged snapshot with bundle records uses exact inner-file binding'

        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'swapped-during-compression')
        $swappedZip = Join-Path $temp 'swapped.zip'
        Compress-Archive -Path (Join-Path $modStage '*') -DestinationPath $swappedZip -Force
        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'descriptor')
        $swappedZipVerdict = Test-ReleaseZipSnapshot `
            -ZipBytes ([System.IO.File]::ReadAllBytes($swappedZip)) `
            -ManifestEntry $entry
        Assert (-not $swappedZipVerdict.Valid) 'restoring staged paths after compression cannot hide swapped zip payload bytes'

        [System.IO.File]::WriteAllText((Join-Path $modStage 'injected.txt'), 'injected')
        $injectedZip = Join-Path $temp 'injected.zip'
        Compress-Archive -Path (Join-Path $modStage '*') -DestinationPath $injectedZip -Force
        Remove-Item -LiteralPath (Join-Path $modStage 'injected.txt') -Force
        $injectedZipVerdict = Test-ReleaseZipSnapshot `
            -ZipBytes ([System.IO.File]::ReadAllBytes($injectedZip)) `
            -ManifestEntry $entry
        Assert (-not $injectedZipVerdict.Valid) 'immutable zip snapshot rejects unrepresented injected entries'

        $entry.source_commit = 'not-a-commit'
        $badCommit = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $badCommit.Valid) 'rejects malformed source commit'
        $entry.source_commit = ('b' * 40)

        $entry.publication_authorization.source_commit = ('c' * 40)
        $badAuthorizationCommit = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $badAuthorizationCommit.Valid) 'rejects publication evidence bound to a different source commit'
        $entry.publication_authorization.source_commit = ('b' * 40)

        $savedAuthorization = $entry.publication_authorization
        $entry.Remove('publication_authorization')
        $missingAuthorization = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $missingAuthorization.Valid) 'rejects staged provenance without publication authorization'
        $entry['publication_authorization'] = $savedAuthorization

        $entry.source_state = 'dirty'
        $dirtySource = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $dirtySource.Valid) 'rejects dirty source provenance'
        $entry.source_state = 'clean'

        $savedBundleFiles = $entry.bundle_files
        $entry.bundle_files = @($savedBundleFiles) + @(
            [ordered]@{ filename = 'other.mod'; sha256 = ('2' * 64) }
        )
        $extraDescriptor = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example')
        Assert (-not $extraDescriptor.Valid) 'shared output-set contract rejects an additional descriptor in manifest records'
        $entry.bundle_files = $savedBundleFiles

        $entry.publication_authorization.mode = 'emergency_override'
        $emergency = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $emergency.Valid) 'rejects emergency publication authorization'
        $entry.publication_authorization = [ordered]@{
            mode = 'hosted_qa'; source_commit = ('b' * 40)
            checked_at_utc = '2026-07-26T00:00:00Z'; default_branch = 'master'
            default_branch_commit = ('b' * 40); merged_pr_number = 724
            qa_check = 'qa-gate'; qa_check_url = 'https://example.invalid/check/724'
            qa_completed_at_utc = '2026-07-26T00:00:00Z'
        }

        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'tampered')
        $badHash = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $badHash.Valid) 'rejects staged bundle hash mismatch'
        [System.IO.File]::WriteAllText((Join-Path $modStage 'example.mod'), 'descriptor')

        [System.IO.File]::WriteAllText((Join-Path $modStage 'unlisted.mod_bundle'), 'extra')
        $extraFile = Test-ReleaseManifest -Manifest $manifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $extraFile.Valid) 'rejects staged output omitted from bundle_files'
        Remove-Item -LiteralPath (Join-Path $modStage 'unlisted.mod_bundle') -Force

        $legacy = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'; published_at = '2026-07-13T00:00:00Z'
            mods = @([ordered]@{
                mod_id = 'legacy'; workshop_id = '42'; version = '0.1.0'; asset_filename = 'legacy.zip'
                sha256 = ('c' * 64)
            })
        }
        $legacyCarry = Test-ReleaseManifest -Manifest $legacy
        Assert $legacyCarry.Valid 'allows a carried pre-transition entry'
        Assert ($legacyCarry.Warnings.Count -eq 1) 'warns for carried entry without provenance'
        $roundTrippedLegacyEntry = (
            $legacy | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        ).mods[0]
        Assert (
            @(Get-ReleaseManifestBundleFileRecords -ManifestEntry $roundTrippedLegacyEntry).Count -eq 0
        ) 'normalizes a JSON-round-tripped absent bundle_files property to zero records'
        Assert (
            (Get-ReleaseZipSnapshotBindingMode -ManifestEntry $roundTrippedLegacyEntry -IsStaged $false -IsCarried $true) -eq
                'legacy_carried_whole_zip'
        ) 'routes only an unchanged historical carry without records to whole-zip binding'
        Assert (
            (Get-ReleaseZipSnapshotBindingMode -ManifestEntry $legacy.mods[0] -IsStaged $true -IsCarried $true) -eq
                'invalid_missing_bundle_files'
        ) 'never grants the historical carry exception to a newly staged zip'
        Assert (
            (Get-ReleaseZipSnapshotBindingMode -ManifestEntry $legacy.mods[0] -IsStaged $false -IsCarried $false) -eq
                'invalid_missing_bundle_files'
        ) 'rejects an unclassified zip without commit-derived bundle records'
        $legacyStrictVerdict = Test-ReleaseZipSnapshot `
            -ZipBytes ([System.IO.File]::ReadAllBytes($exactZip)) `
            -ManifestEntry $roundTrippedLegacyEntry
        Assert (-not $legacyStrictVerdict.Valid) 'strict inner-file verifier remains fail-closed without bundle records'
        $legacy.mods[0]['bundle_files'] = $null
        Assert (
            @(Get-ReleaseManifestBundleFileRecords -ManifestEntry $legacy.mods[0]).Count -eq 0
        ) 'normalizes an explicit null carried bundle_files property to zero records'
        $legacy.mods[0].Remove('bundle_files')
        $legacyRequired = Test-ReleaseManifest -Manifest $legacy -RequiredModIds @('legacy')
        Assert (-not $legacyRequired.Valid) 'rejects newly staged entry without provenance'

        $carried = [ordered]@{
            mod_id = 'carried'; friendly_name = 'Carried'; workshop_id = '9876543210'
            version = '9.9.9-dev'; asset_filename = 'carried.zip'; sha256 = ('d' * 64)
            visibility = 'friends_only'; source_commit = ('e' * 40); source_state = 'clean'
            builder = [ordered]@{ name = 'VMBLauncher'; version = '1.2.3' }
            publication_authorization = [ordered]@{
                mode = 'hosted_qa'; source_commit = ('e' * 40)
                checked_at_utc = '2026-07-26T00:00:00Z'; default_branch = 'master'
                default_branch_commit = ('e' * 40); merged_pr_number = 723
                qa_check = 'qa-gate'; qa_check_url = 'https://example.invalid/check/723'
                qa_completed_at_utc = '2026-07-26T00:00:00Z'
            }
            bundle_files = @(
                [ordered]@{ filename = 'bbbbbbbbbbbbbbbb.mod_bundle'; sha256 = ('f' * 64) },
                [ordered]@{ filename = 'carried.mod'; sha256 = ('1' * 64) }
            )
        }
        $filteredManifest = [ordered]@{
            manifest_schema = 2; release_tag = 'mods-test'; published_at = '2026-07-13T00:00:00Z'
            mods = @($entry, $carried)
        }
        $filtered = Test-ReleaseManifest -Manifest $filteredManifest -RequiredModIds @('example') -StageRoot $temp
        Assert $filtered.Valid 'filtered publish does not require carried sibling bundle files in StageRoot'
        Assert (
            (Get-ReleaseZipSnapshotBindingMode -ManifestEntry $carried -IsStaged $false -IsCarried $true) -eq
                'exact_bundle_files'
        ) 'provenance-bearing carried zip retains strict inner-file binding'

        $savedCarriedAuthorization = $carried.publication_authorization
        $carried.Remove('publication_authorization')
        $carried.source_state = 'dirty'
        $legacyProvenanceCarry = Test-ReleaseManifest -Manifest $filteredManifest -RequiredModIds @('example') -StageRoot $temp
        Assert $legacyProvenanceCarry.Valid 'filtered publish allows unchanged carried pre-authorization provenance'
        Assert ($legacyProvenanceCarry.Warnings.Count -eq 2) 'warns for carried missing authorization and historical dirty source'
        $requiredLegacyProvenance = Test-ReleaseManifest -Manifest $filteredManifest -RequiredModIds @('example', 'carried') -StageRoot $temp
        Assert (-not $requiredLegacyProvenance.Valid) 'newly staged entries cannot use carried transition allowances'
        $carried.source_state = 'clean'
        $carried['publication_authorization'] = $savedCarriedAuthorization

        $carried.publication_authorization.qa_check = 'wrong-check'
        $badCarriedAuthorization = Test-ReleaseManifest -Manifest $filteredManifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $badCarriedAuthorization.Valid) 'filtered publish rejects malformed present carried authorization'
        $carried.publication_authorization.qa_check = 'qa-gate'

        $carried.source_commit = 'bad'
        $badCarriedMetadata = Test-ReleaseManifest -Manifest $filteredManifest -RequiredModIds @('example') -StageRoot $temp
        Assert (-not $badCarriedMetadata.Valid) 'filtered publish still validates carried sibling provenance metadata'
        $carried.source_commit = ('e' * 40)

        if ($failures.Count -gt 0) {
            Write-Host "[check_release_manifest] SELF-TEST FAILED -- $($failures.Count) case(s)" -ForegroundColor Red
            return 2
        }
        Write-Host '[check_release_manifest] SELF-TEST OK' -ForegroundColor Green
        return 0
    } finally {
        if (Test-Path -LiteralPath $temp) {
            Get-ChildItem -LiteralPath $temp -Recurse -File | Remove-Item -Force
            Get-ChildItem -LiteralPath $temp -Recurse -Directory | Sort-Object FullName -Descending | Remove-Item -Force
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

if ($SelfTest) { exit (Invoke-SelfTest) }
if (-not $ManifestPath) {
    Write-Host '[check_release_manifest] ERROR -- pass -ManifestPath or -SelfTest.' -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Write-Host "[check_release_manifest] ERROR -- manifest not found: $ManifestPath" -ForegroundColor Red
    exit 2
}

try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json }
catch {
    Write-Host "[check_release_manifest] ERROR -- invalid JSON: $_" -ForegroundColor Red
    exit 2
}
$verdict = Test-ReleaseManifest -Manifest $manifest -RequiredModIds $RequiredModIds -StageRoot $StageRoot
foreach ($warning in $verdict.Warnings) { Write-Host "[check_release_manifest] WARNING -- $warning" -ForegroundColor Yellow }
if (-not $verdict.Valid) {
    foreach ($error in $verdict.Errors) { Write-Host "[check_release_manifest] ERROR -- $error" -ForegroundColor Red }
    exit 2
}
Write-Host "[check_release_manifest] OK -- $(@($manifest.mods).Count) entries validated." -ForegroundColor Green
exit 0
