# Focused policy and behavior gate for post-VMB build normalization.
# ASCII-only for Windows PowerShell 5.1 parsing.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$helperPath = Join-Path $PSScriptRoot '..\tools\ship\build-output-normalization.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    Write-Host "[check_build_output_normalization] ERROR - helper missing: $helperPath" -ForegroundColor Red
    exit 2
}
. $helperPath

$script:SdkSidecarName = 'e7852992f40eb619.mod_bundle'
$script:SdkSidecarSha256 = 'e1a04e500f8255ebedcaffb4e35e829adbd99ebf46c2b8b4cd89d26dca4735e2'
$script:SdkSidecarPolicyDirs = @(
    'weapon_tweaker',
    'weapon_tweaker_dev',
    'chaos_wastes_tweaker',
    'chaos_wastes_tweaker_dev',
    'general_tweaker_dev',
    'gui_tweaker',
    'gui_tweaker_dev',
    'cosmetics_tweaker',
    'dynamic_cosmetic_portraits',
    'career_tweaker',
    'enemy_tweaker',
    'character_weapon_variants',
    'character_dialogue',
    'crafting_in_modded_dev',
    'event_tweaker',
    'modded_progression',
    'verminious_dreams_lighting_dev',
    'weapons_of_chaos'
)
$script:SdkSidecarDeferredDirs = @(
    'general_tweaker',
    'crafting_in_modded',
    'verminious_dreams_lighting'
)

function Get-SdkSidecarInventoryCompletenessErrors {
    param([Parameter(Mandatory = $true)][object[]]$ModEntries)

    $errors = [System.Collections.Generic.List[string]]::new()
    $byDir = @{}
    foreach ($entry in @($ModEntries)) {
        $dir = [string]$entry.Dir
        if (-not [string]::IsNullOrWhiteSpace($dir)) { $byDir[$dir] = $entry }
    }

    $expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($dir in $script:SdkSidecarPolicyDirs) { [void]$expected.Add($dir) }
    $actual = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in @($ModEntries)) {
        if (@($entry.BuildArtifactExclusions | Where-Object { $null -ne $_ }).Count -gt 0) {
            [void]$actual.Add([string]$entry.Dir)
        }
    }

    foreach ($dir in $script:SdkSidecarPolicyDirs) {
        if (-not $actual.Contains($dir)) {
            $errors.Add("SDK sidecar policy is missing from required mod: $dir")
            continue
        }
        $entry = $byDir[$dir]
        $rows = @($entry.BuildArtifactExclusions | Where-Object { $null -ne $_ })
        if ($rows.Count -ne 1) {
            $errors.Add("SDK sidecar policy must contain exactly one exclusion for ${dir}: found $($rows.Count)")
            continue
        }
        if ([string]$rows[0].Name -cne $script:SdkSidecarName) {
            $errors.Add("SDK sidecar policy filename drifted for ${dir}: $([string]$rows[0].Name)")
        }
        if ([string]$rows[0].Sha256 -cne $script:SdkSidecarSha256) {
            $errors.Add("SDK sidecar policy SHA-256 drifted for $dir")
        }
        if ([string]$entry.RootBundle -ceq $script:SdkSidecarName) {
            $errors.Add("SDK sidecar policy collides with RootBundle for $dir")
        }
    }

    foreach ($dir in $actual) {
        if (-not $expected.Contains($dir)) {
            $errors.Add("unexpected SDK sidecar policy-bearing mod: $dir")
        }
    }
    foreach ($dir in $script:SdkSidecarDeferredDirs) {
        if ($actual.Contains($dir)) {
            $errors.Add("deferred stable mod must remain policy-free pending its own evidence: $dir")
        }
    }
    return @($errors)
}

function Remove-LeafTree {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
    }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory |
        Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
        }
    Remove-Item -LiteralPath $Path -Force
}

function Invoke-NormalizationSelfTest {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-build-normalization-" + [guid]::NewGuid().ToString('N'))
    $exampleBundle = Join-Path $temp 'example\bundleV2'
    $otherBundle = Join-Path $temp 'other\bundleV2'
    $toolsDir = Join-Path $temp 'tools'
    [System.IO.Directory]::CreateDirectory($exampleBundle) | Out-Null
    [System.IO.Directory]::CreateDirectory($otherBundle) | Out-Null
    [System.IO.Directory]::CreateDirectory($toolsDir) | Out-Null

    $failures = [System.Collections.Generic.List[string]]::new()
    function Assert([bool]$Condition, [string]$Description) {
        if ($Condition) { Write-Host "  [PASS] $Description" -ForegroundColor Green }
        else { Write-Host "  [FAIL] $Description" -ForegroundColor Red; $failures.Add($Description) }
    }

    try {
        $rootName = 'aaaaaaaaaaaaaaaa.mod_bundle'
        $sidecarName = 'cccccccccccccccc.mod_bundle'
        $unrelatedName = 'eeeeeeeeeeeeeeee.mod_bundle'
        $rootPath = Join-Path $exampleBundle $rootName
        $sidecarPath = Join-Path $exampleBundle $sidecarName
        $unrelatedPath = Join-Path $exampleBundle $unrelatedName
        $otherSidecarPath = Join-Path $otherBundle $sidecarName
        [System.IO.File]::WriteAllBytes($rootPath, [byte[]](1, 2, 3))
        [System.IO.File]::WriteAllBytes($sidecarPath, [byte[]](4, 5, 6, 7))
        [System.IO.File]::WriteAllBytes($unrelatedPath, [byte[]](8, 9))
        [System.IO.File]::WriteAllBytes($otherSidecarPath, [byte[]](4, 5, 6, 7))
        $sidecarSha = (Get-FileHash -LiteralPath $sidecarPath -Algorithm SHA256).Hash.ToLowerInvariant()

        $proofInputs = @(
            [pscustomobject]@{
                Name = 'ffffffffffffffff.mod_bundle'; Sha256 = ('1' * 64); Reason = 'later ordinal filename'
            },
            [pscustomobject]@{
                Name = '0000000000000000.mod_bundle'; Sha256 = ('2' * 64); Reason = 'earlier ordinal filename'
            }
        )
        $orderedProof = New-BuildOutputNormalizationPolicyProof -Exclusions $proofInputs
        Assert ($orderedProof.Algorithm -ceq 'exact-build-artifact-exclusions-sha256-v1') `
            'policy proof declares the exact normalization algorithm'
        Assert ((@($orderedProof.ExcludedOutputs).Filename -join ',') -ceq
            '0000000000000000.mod_bundle,ffffffffffffffff.mod_bundle') `
            'policy proof uses culture-independent ordinal filename ordering'

        $reasonChangedProof = New-BuildOutputNormalizationPolicyProof -Exclusions @(
            [pscustomobject]@{
                Name = '0000000000000000.mod_bundle'; Sha256 = ('2' * 64); Reason = 'rewritten explanation'
            },
            [pscustomobject]@{
                Name = 'ffffffffffffffff.mod_bundle'; Sha256 = ('1' * 64); Reason = 'different prose only'
            }
        )
        $reasonComparison = Compare-BuildOutputNormalizationPolicyProof `
            -Expected $orderedProof -Actual $reasonChangedProof
        Assert ($reasonComparison.Ok -and
            [string]$orderedProof.FingerprintSha256 -ceq [string]$reasonChangedProof.FingerprintSha256) `
            'Reason remains explanatory and cannot change policy identity'

        $filenameDriftProof = New-BuildOutputNormalizationPolicyProof -Exclusions @(
            [pscustomobject]@{
                Name = '0000000000000000.mod_bundle'; Sha256 = ('2' * 64); Reason = 'same first output'
            },
            [pscustomobject]@{
                Name = 'eeeeeeeeeeeeeeee.mod_bundle'; Sha256 = ('1' * 64); Reason = 'changed filename'
            }
        )
        $filenameDrift = Compare-BuildOutputNormalizationPolicyProof -Expected $orderedProof -Actual $filenameDriftProof
        Assert (-not $filenameDrift.Ok -and
            @($filenameDrift.Problems | Where-Object { $_ -like 'normalization policy exclusion removed:*' }).Count -eq 1 -and
            @($filenameDrift.Problems | Where-Object { $_ -like 'normalization policy exclusion added:*' }).Count -eq 1) `
            'filename drift reports one deterministic removal and addition'

        $hashDriftProof = New-BuildOutputNormalizationPolicyProof -Exclusions @(
            [pscustomobject]@{
                Name = 'ffffffffffffffff.mod_bundle'; Sha256 = ('3' * 64); Reason = 'changed hash'
            },
            [pscustomobject]@{
                Name = '0000000000000000.mod_bundle'; Sha256 = ('2' * 64); Reason = 'same first output'
            }
        )
        $hashDrift = Compare-BuildOutputNormalizationPolicyProof -Expected $orderedProof -Actual $hashDriftProof
        Assert (-not $hashDrift.Ok -and
            @($hashDrift.Problems | Where-Object { $_ -eq 'normalization policy exclusion SHA-256 changed: ffffffffffffffff.mod_bundle' }).Count -eq 1) `
            'SHA-256 drift is rejected at the exact filename'

        $wrongAlgorithmProof = [pscustomobject][ordered]@{
            Algorithm = 'invented-policy-v9'
            FingerprintSha256 = $orderedProof.FingerprintSha256
            ExcludedOutputs = @($orderedProof.ExcludedOutputs)
        }
        $algorithmDrift = Compare-BuildOutputNormalizationPolicyProof -Expected $orderedProof -Actual $wrongAlgorithmProof
        Assert (-not $algorithmDrift.Ok -and
            @($algorithmDrift.Problems | Where-Object { $_ -like 'actual normalization policy algorithm*' }).Count -eq 1) `
            'algorithm drift fails closed'

        $wrongFingerprintProof = [pscustomobject][ordered]@{
            Algorithm = $orderedProof.Algorithm
            FingerprintSha256 = ('0' * 64)
            ExcludedOutputs = @($orderedProof.ExcludedOutputs)
        }
        $fingerprintDrift = Compare-BuildOutputNormalizationPolicyProof -Expected $orderedProof -Actual $wrongFingerprintProof
        Assert (-not $fingerprintDrift.Ok -and
            @($fingerprintDrift.Problems | Where-Object { $_ -eq 'actual normalization policy fingerprint does not match ExcludedOutputs' }).Count -eq 1) `
            'fingerprint drift fails closed even when entry fields are unchanged'

        $wrongOrderProof = [pscustomobject][ordered]@{
            Algorithm = $orderedProof.Algorithm
            FingerprintSha256 = $orderedProof.FingerprintSha256
            ExcludedOutputs = @($orderedProof.ExcludedOutputs[1], $orderedProof.ExcludedOutputs[0])
        }
        $orderingDrift = Compare-BuildOutputNormalizationPolicyProof -Expected $orderedProof -Actual $wrongOrderProof
        Assert (-not $orderingDrift.Ok -and
            @($orderingDrift.Problems | Where-Object { $_ -eq 'actual normalization policy exclusions are not in canonical ordinal order' }).Count -eq 1) `
            'noncanonical proof ordering fails closed'

        $emptyProof = New-BuildOutputNormalizationPolicyProof -Exclusions @()
        Assert (@($emptyProof.ExcludedOutputs).Count -eq 0 -and
            [string]$emptyProof.FingerprintSha256 -ceq
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855') `
            'no-exclusion policy has the SHA-256 empty-input identity'

        $inventoryText = @"
@{
    Mods = @(
        @{
            Dir = 'example'; ModId = 'example'; WorkshopId = '1'; Visibility = 'private';
            Stream = 'single'; Public = `$false; Name = 'Example'; BundleAuthority = 'tracked'; RootBundle = '$rootName';
            BuildArtifactExclusions = @(
                @{ Name = '$sidecarName'; Sha256 = '$sidecarSha'; Reason = 'fixture SDK tool-only output' }
            )
        },
        @{
            Dir = 'other'; ModId = 'other'; WorkshopId = '2'; Visibility = 'private';
            Stream = 'single'; Public = `$false; Name = 'Other'; BundleAuthority = 'tracked'; RootBundle = 'bbbbbbbbbbbbbbbb.mod_bundle'
        }
    )
}
"@
        [System.IO.File]::WriteAllText((Join-Path $toolsDir 'mod-inventory.psd1'), $inventoryText, [System.Text.UTF8Encoding]::new($false))

        $exact = Invoke-BuildOutputNormalization -RepoRoot $temp -Mod example
        Assert ($exact.Removed -eq 1 -and -not (Test-Path -LiteralPath $sidecarPath)) 'exact inventoried sidecar is removed'
        Assert ((Test-Path -LiteralPath $rootPath) -and (Test-Path -LiteralPath $unrelatedPath)) 'root and unrelated bundles remain untouched'
        $resolvedExamplePolicy = Get-ModBuildOutputNormalizationPolicyProof -RepoRoot $temp -Mod example
        Assert ((Compare-BuildOutputNormalizationPolicyProof -Expected $resolvedExamplePolicy -Actual $exact.Policy).Ok) `
            'normalization returns the exact applied policy proof'
        Assert ($exact.BundleAuthority -ceq 'tracked' -and @($exact.PolicyDetails).Count -eq 1 -and
            [string]$exact.PolicyDetails[0].Reason -ceq 'fixture SDK tool-only output') `
            'normalization preserves tracked authority and explanatory Reason outside identity'
        Assert (-not (Test-BuildOutputObjectHasProperty -Object $exact.Policy.ExcludedOutputs[0] -Name 'Reason')) `
            'hashed ExcludedOutputs omit explanatory Reason'
        $normalizedEmittedMap = @((Get-ChildItem -LiteralPath $exampleBundle -File).Name | Sort-Object)

        $absent = Invoke-BuildOutputNormalization -RepoRoot $temp -Mod example
        Assert ($absent.Absent -eq 1 -and $absent.Removed -eq 0) 'absent sidecar is a successful no-op'
        Assert ((Compare-BuildOutputNormalizationPolicyProof -Expected $exact.Policy -Actual $absent.Policy).Ok) `
            'emitted and absent exclusions return the same applied policy identity'
        $normalizedAbsentMap = @((Get-ChildItem -LiteralPath $exampleBundle -File).Name | Sort-Object)
        Assert (@(Compare-Object $normalizedEmittedMap $normalizedAbsentMap).Count -eq 0) 'emitted and absent raw maps normalize to the same canonical file set'

        $other = Invoke-BuildOutputNormalization -RepoRoot $temp -Mod other
        Assert ($other.Removed -eq 0 -and $other.Absent -eq 0 -and (Test-Path -LiteralPath $otherSidecarPath)) 'ordinary mod without a policy leaves the same leaf untouched'
        Assert ($null -ne $other.Policy -and @($other.Policy.ExcludedOutputs).Count -eq 0 -and
            (Compare-BuildOutputNormalizationPolicyProof -Expected $emptyProof -Actual $other.Policy).Ok -and
            @($other.PolicyDetails).Count -eq 0) `
            'normalization returns exact empty policy identity when no exclusions exist'

        [System.IO.File]::WriteAllBytes($sidecarPath, [byte[]](99, 98, 97))
        $wrongHashFailed = $false
        try { Invoke-BuildOutputNormalization -RepoRoot $temp -Mod example | Out-Null }
        catch { $wrongHashFailed = $_.Exception.Message -match 'REFUSED changed bytes' }
        Assert ($wrongHashFailed -and (Test-Path -LiteralPath $sidecarPath)) 'changed bytes fail closed and remain for inspection'

        [System.IO.File]::WriteAllBytes($sidecarPath, [byte[]](4, 5, 6, 7))
        $swapPath = $sidecarPath + '.swap'
        $script:__normalizationReplacementBlocked = $false
        $lockedRemoval = Invoke-BuildOutputNormalization -RepoRoot $temp -Mod example `
            -BeforeDeleteTestHook {
                param($lockedPath)
                try {
                    Move-Item -LiteralPath $lockedPath -Destination $swapPath -Force -ErrorAction Stop
                    [System.IO.File]::WriteAllBytes($lockedPath, [byte[]](99, 98, 97))
                }
                catch { $script:__normalizationReplacementBlocked = $true }
            }
        Assert ($script:__normalizationReplacementBlocked -and
            $lockedRemoval.Removed -eq 1 -and
            -not (Test-Path -LiteralPath $sidecarPath) -and
            -not (Test-Path -LiteralPath $swapPath)) `
            'exact exclusion stays handle-locked from hash through deletion'
        Remove-Variable -Name __normalizationReplacementBlocked -Scope Script -ErrorAction SilentlyContinue

        $invalid = @{
            Dir = 'bad'; BundleAuthority = 'tracked'; RootBundle = $rootName;
            BuildArtifactExclusions = @(
                @{ Name = '..\escape.mod_bundle'; Sha256 = 'bad'; Reason = '' },
                @{ Name = 'dddddddddddddddd.mod_bundle'; Sha256 = 'bad'; Reason = '' },
                @{ Name = 'example.mod'; Sha256 = ('c' * 64); Reason = 'descriptor collision' },
                @{ Name = $rootName; Sha256 = ('a' * 64); Reason = 'root collision' },
                @{ Name = 'ffffffffffffffff.mod_bundle'; Sha256 = ('b' * 64); Reason = 'duplicate one' },
                @{ Name = 'ffffffffffffffff.mod_bundle'; Sha256 = ('b' * 64); Reason = 'duplicate two' }
            )
        }
        $policyErrors = @(Get-BuildArtifactExclusionErrors -ModEntry $invalid)
        Assert (($policyErrors -match 'invalid BuildArtifactExclusions name').Count -gt 0) 'path-shaped exclusion is rejected'
        Assert (($policyErrors -match 'invalid BuildArtifactExclusions SHA-256').Count -gt 0) 'invalid SHA-256 is rejected'
        Assert (($policyErrors -match 'example.mod').Count -gt 0) 'mod descriptor cannot be excluded'
        Assert (($policyErrors -match 'reason is empty').Count -gt 0) 'empty reason is rejected'
        Assert (($policyErrors -match 'cannot name RootBundle').Count -gt 0) 'canonical root bundle cannot be excluded'
        Assert (($policyErrors -match 'duplicate BuildArtifactExclusions').Count -gt 0) 'duplicate exclusion is rejected'

        $missingAuthority = @{
            Dir = 'missing-authority'; RootBundle = $rootName; BuildArtifactExclusions = @()
        }
        $wrongAuthority = @{
            Dir = 'wrong-authority'; BundleAuthority = 'generated'; RootBundle = $rootName;
            BuildArtifactExclusions = @()
        }
        $receiptAuthority = @{
            Dir = 'receipt_authority'; BundleAuthority = 'receipt'; RootBundle = $rootName;
            BuildArtifactExclusions = @()
        }
        Assert ((@(Get-BuildOutputPolicyErrors -ModEntry $missingAuthority) -match 'invalid BundleAuthority').Count -eq 1) `
            'missing BundleAuthority fails closed'
        Assert ((@(Get-BuildOutputPolicyErrors -ModEntry $wrongAuthority) -match 'invalid BundleAuthority').Count -eq 1) `
            'unsupported BundleAuthority fails closed'
        Assert (@(Get-BuildOutputPolicyErrors -ModEntry $receiptAuthority).Count -eq 0) `
            'receipt BundleAuthority reuses the exact normalization policy'
        $malformedAuthorityConstructorFailed = $false
        try { New-BuildOutputNormalizationPolicyProof -ModEntry $wrongAuthority | Out-Null }
        catch { $malformedAuthorityConstructorFailed = $_.Exception.Message -match 'invalid BundleAuthority' }
        Assert $malformedAuthorityConstructorFailed 'ModEntry proof construction reuses fail-closed authority validation'

        $malformedProofInputFailed = $false
        try {
            New-BuildOutputNormalizationPolicyProof -Exclusions @(
                [pscustomobject]@{ Name = 'aaaaaaaaaaaaaaaa.mod_bundle'; Sha256 = 'bad'; Reason = 'bad hash' }
            ) | Out-Null
        }
        catch { $malformedProofInputFailed = $_.Exception.Message -match 'invalid BuildArtifactExclusions SHA-256' }
        Assert $malformedProofInputFailed 'policy proof constructor rejects malformed exact exclusions'

        function New-SdkSidecarCompletenessFixture {
            $rows = @()
            foreach ($dir in $script:SdkSidecarPolicyDirs) {
                $rows += [pscustomobject]@{
                    Dir = $dir
                    RootBundle = ($dir + '.mod_bundle')
                    BuildArtifactExclusions = @(
                        [pscustomobject]@{
                            Name = $script:SdkSidecarName
                            Sha256 = $script:SdkSidecarSha256
                            Reason = 'fixture SDK tool-only output'
                        }
                    )
                }
            }
            foreach ($dir in $script:SdkSidecarDeferredDirs) {
                $rows += [pscustomobject]@{
                    Dir = $dir
                    RootBundle = ($dir + '.mod_bundle')
                    BuildArtifactExclusions = @()
                }
            }
            return @($rows)
        }

        $completeInventory = @(New-SdkSidecarCompletenessFixture)
        Assert (@(Get-SdkSidecarInventoryCompletenessErrors -ModEntries $completeInventory).Count -eq 0) `
            'live inventory completeness accepts the exact 18-policy transfer'

        $omittedInventory = @($completeInventory | Where-Object { $_.Dir -cne 'general_tweaker_dev' })
        Assert ((@(Get-SdkSidecarInventoryCompletenessErrors -ModEntries $omittedInventory) -match
            'missing from required mod: general_tweaker_dev').Count -eq 1) `
            'live inventory completeness rejects one omitted candidate'

        $extraInventory = @(New-SdkSidecarCompletenessFixture)
        $extraRow = @($extraInventory | Where-Object { $_.Dir -ceq 'general_tweaker' })[0]
        $extraRow.BuildArtifactExclusions = @(
            [pscustomobject]@{
                Name = $script:SdkSidecarName
                Sha256 = $script:SdkSidecarSha256
                Reason = 'premature stable transfer'
            }
        )
        $extraErrors = @(Get-SdkSidecarInventoryCompletenessErrors -ModEntries $extraInventory)
        Assert ((@($extraErrors -match 'unexpected SDK sidecar policy-bearing mod: general_tweaker').Count -eq 1) -and
            (@($extraErrors -match 'deferred stable mod must remain policy-free.*general_tweaker').Count -eq 1)) `
            'live inventory completeness rejects an unevidenced deferred stable row'

        $wrongHashInventory = @(New-SdkSidecarCompletenessFixture)
        @($wrongHashInventory | Where-Object { $_.Dir -ceq 'career_tweaker' })[0].BuildArtifactExclusions[0].Sha256 = ('f' * 64)
        Assert ((@(Get-SdkSidecarInventoryCompletenessErrors -ModEntries $wrongHashInventory) -match
            'SHA-256 drifted for career_tweaker').Count -eq 1) `
            'live inventory completeness rejects a changed candidate hash'

        $secondExclusionInventory = @(New-SdkSidecarCompletenessFixture)
        $secondRow = @($secondExclusionInventory | Where-Object { $_.Dir -ceq 'enemy_tweaker' })[0]
        $secondRow.BuildArtifactExclusions = @(
            @($secondRow.BuildArtifactExclusions)[0],
            [pscustomobject]@{
                Name = 'ffffffffffffffff.mod_bundle'
                Sha256 = ('a' * 64)
                Reason = 'unexpected second exclusion'
            }
        )
        Assert ((@(Get-SdkSidecarInventoryCompletenessErrors -ModEntries $secondExclusionInventory) -match
            'exactly one exclusion for enemy_tweaker: found 2').Count -eq 1) `
            'live inventory completeness rejects a second valid-looking exclusion'

        if ($failures.Count -gt 0) {
            Write-Host "[check_build_output_normalization] SELF-TEST FAILED - $($failures.Count) case(s)" -ForegroundColor Red
            return 2
        }
        Write-Host '[check_build_output_normalization] SELF-TEST OK' -ForegroundColor Green
        return 0
    }
    finally {
        Remove-LeafTree -Path $temp
    }
}

if ($SelfTest) { exit (Invoke-NormalizationSelfTest) }

$root = (Resolve-Path -LiteralPath $RepoRoot).Path
$inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
    Write-Host "[check_build_output_normalization] ERROR - inventory missing: $inventoryPath" -ForegroundColor Red
    exit 2
}
$inventory = Import-PowerShellDataFile -Path $inventoryPath
$errors = @()
$errors += @(Get-SdkSidecarInventoryCompletenessErrors -ModEntries @($inventory.Mods))
foreach ($entry in @($inventory.Mods)) {
    $errors += @(Get-BuildOutputPolicyErrors -ModEntry $entry)
    try {
        New-BuildOutputNormalizationPolicyProof -ModEntry $entry | Out-Null
    }
    catch {
        $errors += "normalization policy proof failed for $($entry.Dir): $($_.Exception.Message)"
    }
}
if ($errors.Count -gt 0) {
    Write-Host '[check_build_output_normalization] ERRORS:' -ForegroundColor Red
    foreach ($message in $errors) { Write-Host "  X $message" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) {
    $policyCount = @($inventory.Mods | ForEach-Object {
        @($_.BuildArtifactExclusions | Where-Object { $null -ne $_ })
    }).Count
    Write-Host "[check_build_output_normalization] OK - $policyCount exact exclusion policy record(s) are valid." -ForegroundColor Green
}
exit 0
