# check_appearance_contracts.ps1
#
# Executable G-APPEARANCE census gate (#660). This validates architecture
# declarations and offline evidence references; it does NOT claim that a
# renderer, transition, or peer path has passed in-game verification.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ManifestPath,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
if (-not $ManifestPath) { $ManifestPath = Join-Path $PSScriptRoot 'appearance_contracts.psd1' }

# This vocabulary is the architecture boundary, not manifest-owned data.  If the
# manifest were allowed to define the boundary by itself, deleting a required
# surface/edge from both the vocabulary and every contract would still pass.
# Keep this list aligned with docs/WEAPON_APPEARANCE_STANDARD.md.
$CANONICAL_SURFACES = @(
    'owner_1p', 'owner_3p', 'bot_3p', 'remote_husk_3p',
    'inventory_preview', 'cosmetic_preview', 'athanor_preview',
    'crafting_preview', 'lobby_preview', 'score_screen', 'hold_tab'
)
$CANONICAL_REPLAY_EDGES = @(
    'instance_load', 'initial_spawn', 'equip', 'wield',
    'customization_change', 'style_change', 'mission_transition', 'respawn',
    'hot_join', 'peer_ready', 'parity_ready', 'rejoin',
    'preview_open', 'preview_reopen', 'lobby_score_create',
    'mod_disable_restore'
)
$CANONICAL_CONCERNS = @(
    'unit_identity', 'transform', 'material', 'glow', 'pose',
    'effective_template', 'icon', 'name'
)

function Test-MapKey($Map, [string]$Key) {
    return $null -ne $Map -and $Map -is [System.Collections.IDictionary] -and $Map.Contains($Key)
}

function Get-UniqueErrors([object[]]$Values, [string]$Label) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($value in @($Values)) {
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) {
            $errors.Add("$Label contains an empty value")
        } elseif ($seen.ContainsKey($text)) {
            $errors.Add("$Label contains duplicate '$text'")
        } else {
            $seen[$text] = $true
        }
    }
    return $errors.ToArray()
}

function Test-AppearanceManifest(
    $Manifest,
    [string]$Root,
    [string[]]$RequiredSurfaces = @(),
    [string[]]$RequiredReplayEdges = @(),
    [string[]]$RequiredConcerns = @()
) {
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Manifest -or $Manifest -isnot [System.Collections.IDictionary]) {
        return @('manifest root must be a data-file map')
    }
    if ($Manifest.SchemaVersion -ne 1) {
        $errors.Add("SchemaVersion must be 1 (got '$($Manifest.SchemaVersion)')")
    }

    $surfaces = @($Manifest.SurfaceVocabulary)
    $edges = @($Manifest.ReplayEdgeVocabulary)
    $concernNames = @($Manifest.ConcernVocabulary)
    $dispositions = @($Manifest.DispositionVocabulary)
    foreach ($message in @(Get-UniqueErrors $surfaces 'SurfaceVocabulary')) { $errors.Add($message) }
    foreach ($message in @(Get-UniqueErrors $edges 'ReplayEdgeVocabulary')) { $errors.Add($message) }
    foreach ($message in @(Get-UniqueErrors $concernNames 'ConcernVocabulary')) { $errors.Add($message) }
    foreach ($message in @(Get-UniqueErrors $dispositions 'DispositionVocabulary')) { $errors.Add($message) }
    if ($surfaces.Count -eq 0) { $errors.Add('SurfaceVocabulary must not be empty') }
    if ($edges.Count -eq 0) { $errors.Add('ReplayEdgeVocabulary must not be empty') }
    if ($concernNames.Count -eq 0) { $errors.Add('ConcernVocabulary must not be empty') }
    foreach ($required in $RequiredSurfaces) {
        if ($surfaces -notcontains $required) {
            $errors.Add("SurfaceVocabulary omits canonical surface '$required'")
        }
    }
    foreach ($required in $RequiredReplayEdges) {
        if ($edges -notcontains $required) {
            $errors.Add("ReplayEdgeVocabulary omits canonical replay edge '$required'")
        }
    }
    foreach ($required in $RequiredConcerns) {
        if ($concernNames -notcontains $required) {
            $errors.Add("ConcernVocabulary omits canonical concern '$required'")
        }
    }

    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $contractIds = @{}
    $contracts = @($Manifest.Contracts)
    if ($contracts.Count -eq 0) { $errors.Add('Contracts must not be empty') }

    foreach ($contract in $contracts) {
        $id = [string]$contract.Id
        $prefix = if ($id) { "contract '$id'" } else { 'contract <missing-id>' }
        if ([string]::IsNullOrWhiteSpace($id)) {
            $errors.Add('contract Id is required')
        } elseif ($contractIds.ContainsKey($id)) {
            $errors.Add("duplicate contract Id '$id'")
        } else {
            $contractIds[$id] = $true
        }
        if ($contract.Claim -ne 'structural-only') {
            $errors.Add("$prefix Claim must be 'structural-only'; this gate cannot assert runtime verification")
        }

        $owners = @($contract.Owners)
        if ($owners.Count -eq 0) { $errors.Add("$prefix has no Owners") }
        foreach ($owner in $owners) {
            if ([string]::IsNullOrWhiteSpace([string]$owner)) {
                $errors.Add("$prefix contains an empty owner path")
                continue
            }
            $ownerPath = [IO.Path]::GetFullPath((Join-Path $Root ([string]$owner)))
            if (-not $ownerPath.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
                $errors.Add("$prefix owner escapes repo root: $owner")
            } elseif (-not (Test-Path -LiteralPath $ownerPath -PathType Leaf)) {
                $errors.Add("$prefix owner file missing: $owner")
            }
        }

        $seenConcerns = @{}
        $concerns = @($contract.Concerns)
        if ($concerns.Count -eq 0) { $errors.Add("$prefix has no Concerns") }
        foreach ($concern in $concerns) {
            $name = [string]$concern.Name
            $cp = "$prefix concern '$name'"
            if ($concernNames -notcontains $name) {
                $errors.Add("$cp is outside ConcernVocabulary")
            }
            if ($seenConcerns.ContainsKey($name)) {
                $errors.Add("$prefix duplicates concern '$name'")
            } else {
                $seenConcerns[$name] = $true
            }

            $tests = @($concern.Tests)
            if ($tests.Count -eq 0) { $errors.Add("$cp has no Tests") }
            $testedSurfaces = @{}
            $testedEdges = @{}
            foreach ($test in $tests) {
                $testPathText = [string]$test.Path
                if ([string]::IsNullOrWhiteSpace($testPathText)) {
                    $errors.Add("$cp test has no Path")
                    continue
                }
                $testPath = [IO.Path]::GetFullPath((Join-Path $Root $testPathText))
                if (-not $testPath.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
                    $errors.Add("$cp test path escapes repo root: $testPathText")
                    continue
                }
                $source = $null
                if (-not (Test-Path -LiteralPath $testPath -PathType Leaf)) {
                    $errors.Add("$cp test file missing: $testPathText")
                } else {
                    $source = [IO.File]::ReadAllText($testPath, [Text.Encoding]::UTF8)
                }
                $names = @($test.Names)
                if ($names.Count -eq 0) { $errors.Add("$cp test '$testPathText' has no Names") }
                foreach ($testName in $names) {
                    if ([string]::IsNullOrWhiteSpace([string]$testName)) {
                        $errors.Add("$cp test '$testPathText' contains an empty test name")
                    } elseif ($null -ne $source -and $source.IndexOf([string]$testName, [StringComparison]::Ordinal) -lt 0) {
                        $errors.Add("$cp test name not found in '$testPathText': $testName")
                    }
                }
                foreach ($surface in @($test.Surfaces)) {
                    if ($surfaces -notcontains $surface) {
                        $errors.Add("$cp test '$testPathText' names unknown surface '$surface'")
                    } else { $testedSurfaces[[string]$surface] = $true }
                }
                foreach ($edge in @($test.ReplayEdges)) {
                    if ($edges -notcontains $edge) {
                        $errors.Add("$cp test '$testPathText' names unknown replay edge '$edge'")
                    } else { $testedEdges[[string]$edge] = $true }
                }
            }

            foreach ($axis in @(
                @{ Label = 'surface'; Vocabulary = $surfaces; Map = $concern.Surfaces; Tested = $testedSurfaces },
                @{ Label = 'replay edge'; Vocabulary = $edges; Map = $concern.ReplayEdges; Tested = $testedEdges }
            )) {
                foreach ($cellName in $axis.Vocabulary) {
                    if (-not (Test-MapKey $axis.Map $cellName)) {
                        $errors.Add("$cp lacks declared $($axis.Label) '$cellName'")
                        continue
                    }
                    $cell = $axis.Map[$cellName]
                    $disposition = [string]$cell.Disposition
                    if ($dispositions -notcontains $disposition) {
                        $errors.Add("$cp $($axis.Label) '$cellName' has invalid disposition '$disposition'")
                        continue
                    }
                    if ($disposition -eq 'covered') {
                        if ([string]::IsNullOrWhiteSpace([string]$cell.Evidence)) {
                            $errors.Add("$cp covered $($axis.Label) '$cellName' lacks Evidence")
                        }
                        if (-not $axis.Tested.ContainsKey([string]$cellName)) {
                            $errors.Add("$cp covered $($axis.Label) '$cellName' has no test mapping")
                        }
                    } elseif ([string]::IsNullOrWhiteSpace([string]$cell.Reason)) {
                        $errors.Add("$cp $disposition $($axis.Label) '$cellName' lacks Reason")
                    }
                }
                foreach ($declared in @($axis.Map.Keys)) {
                    if ($axis.Vocabulary -notcontains $declared) {
                        $errors.Add("$cp declares unknown $($axis.Label) '$declared'")
                    }
                }
            }
        }
    }
    return $errors.ToArray()
}

function New-SelfTestManifest(
    [switch]$DropSurface,
    [switch]$DropEdge,
    [switch]$DropVocabularySurface,
    [switch]$DropVocabularyEdge,
    [switch]$DropVocabularyConcern,
    [switch]$DropTests,
    [switch]$UnmappedCoveredSurface,
    [switch]$MissingTestName
) {
    $surfaceMap = @{
        owner = @{ Disposition = 'covered'; Evidence = 'fixture owner adapter' }
        preview = if ($UnmappedCoveredSurface) {
            @{ Disposition = 'covered'; Evidence = 'fixture preview adapter' }
        } else {
            @{ Disposition = 'deferred'; Reason = 'fixture deferral' }
        }
    }
    if ($DropSurface) { $surfaceMap.Remove('preview') }
    $edgeMap = @{
        equip = @{ Disposition = 'covered'; Evidence = 'fixture equip replay' }
        join = @{ Disposition = 'not-applicable'; Reason = 'fixture local-only provider' }
    }
    if ($DropEdge) { $edgeMap.Remove('join') }
    $tests = if ($DropTests) { @() } else {
        @(@{
            Path = 'qa/tests/fixture.lua'
            Names = @($(if ($MissingTestName) { 'missing marker' } else { 'fixture appearance test' }))
            Surfaces = @('owner')
            ReplayEdges = @('equip')
        })
    }
    $surfaceVocabulary = @('owner', 'preview')
    if ($DropVocabularySurface) { $surfaceVocabulary = @('owner') }
    $edgeVocabulary = @('equip', 'join')
    if ($DropVocabularyEdge) { $edgeVocabulary = @('equip') }
    $concernVocabulary = @('unit_identity')
    if ($DropVocabularyConcern) { $concernVocabulary = @('other') }
    return @{
        SchemaVersion = 1
        SurfaceVocabulary = $surfaceVocabulary
        ReplayEdgeVocabulary = $edgeVocabulary
        ConcernVocabulary = $concernVocabulary
        DispositionVocabulary = @('covered', 'deferred', 'not-applicable')
        Contracts = @(@{
            Id = 'fixture.contract'
            Issue = 660
            Claim = 'structural-only'
            Owners = @('owner.lua')
            Concerns = @(@{
                Name = 'unit_identity'
                Surfaces = $surfaceMap
                ReplayEdges = $edgeMap
                Tests = $tests
            })
        })
    }
}

function Invoke-SelfTest {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('vt2-appearance-gate-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path (Join-Path $temp 'qa/tests') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $temp 'owner.lua'), '-- fixture owner', [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText((Join-Path $temp 'qa/tests/fixture.lua'), 'fixture appearance test', [Text.UTF8Encoding]::new($false))

        $cases = @(
            @{ Name = 'complete manifest passes'; Manifest = New-SelfTestManifest; Needle = $null },
            @{ Name = 'missing surface fails'; Manifest = New-SelfTestManifest -DropSurface; Needle = "lacks declared surface 'preview'" },
            @{ Name = 'missing replay edge fails'; Manifest = New-SelfTestManifest -DropEdge; Needle = "lacks declared replay edge 'join'" },
            @{ Name = 'contracted surface vocabulary fails'; Manifest = New-SelfTestManifest -DropVocabularySurface; Needle = "omits canonical surface 'preview'" },
            @{ Name = 'contracted replay vocabulary fails'; Manifest = New-SelfTestManifest -DropVocabularyEdge; Needle = "omits canonical replay edge 'join'" },
            @{ Name = 'contracted concern vocabulary fails'; Manifest = New-SelfTestManifest -DropVocabularyConcern; Needle = "omits canonical concern 'unit_identity'" },
            @{ Name = 'missing tests fails'; Manifest = New-SelfTestManifest -DropTests; Needle = 'has no Tests' },
            @{ Name = 'covered surface without mapped test fails'; Manifest = New-SelfTestManifest -UnmappedCoveredSurface; Needle = "covered surface 'preview' has no test mapping" },
            @{ Name = 'missing named test fails'; Manifest = New-SelfTestManifest -MissingTestName; Needle = 'test name not found' }
        )
        $failed = 0
        foreach ($case in $cases) {
            $found = @(Test-AppearanceManifest $case.Manifest $temp `
                -RequiredSurfaces @('owner', 'preview') `
                -RequiredReplayEdges @('equip', 'join') `
                -RequiredConcerns @('unit_identity'))
            $ok = if ($null -eq $case.Needle) {
                $found.Count -eq 0
            } else {
                ($found -join "`n").IndexOf($case.Needle, [StringComparison]::Ordinal) -ge 0
            }
            if ($ok) {
                if (-not $Quiet) { Write-Host "  [PASS] $($case.Name)" -ForegroundColor Green }
            } else {
                $failed++
                Write-Host "  [FAIL] $($case.Name): $($found -join '; ')" -ForegroundColor Red
            }
        }
        if ($failed -gt 0) {
            Write-Host "[check_appearance_contracts:selftest] FAILED - $failed case(s)" -ForegroundColor Red
            return 2
        }
        if (-not $Quiet) { Write-Host '[check_appearance_contracts:selftest] OK - positive and planted failures detected.' -ForegroundColor Green }
        return 0
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($SelfTest) {
    exit (Invoke-SelfTest)
}

try {
    $resolvedRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
    $resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath).Path
    $manifest = Import-PowerShellDataFile -LiteralPath $resolvedManifest
    $failures = @(Test-AppearanceManifest $manifest $resolvedRoot `
        -RequiredSurfaces $CANONICAL_SURFACES `
        -RequiredReplayEdges $CANONICAL_REPLAY_EDGES `
        -RequiredConcerns $CANONICAL_CONCERNS)
} catch {
    Write-Host "[check_appearance_contracts] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Host "[check_appearance_contracts] ERROR - $failure" -ForegroundColor Red
    }
    exit 2
}
if (-not $Quiet) {
    $concernCount = @($manifest.Contracts | ForEach-Object { @($_.Concerns) }).Count
    Write-Host "[check_appearance_contracts] OK - $(@($manifest.Contracts).Count) contract(s), $concernCount concern declaration(s); structural evidence only."
}
exit 0
