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

# ONE VOCABULARY (#1158).
#
# Until 2026-08-08 this gate carried its own SPELLINGS for surfaces the census
# already named - bot_3p vs bot, remote_husk_3p vs husk, cosmetic_preview vs
# illusion_browser, athanor_preview vs cim_preview, lobby_preview vs lobby,
# score_screen vs score_team, customization_change vs customize - and never read
# the census. Two vocabularies for one domain means a gap can hide between them:
# neither gate can tell that two rows are the same row. The manifest has been
# renamed to canonical spellings and every name is now validated against one
# authority.
#
# Canonical names are owned by tools/shared_lib/_lib_appearance_descriptor.lua
# (M.CELLS / M.EDGES). The legacy bindings - which old spelling maps to which
# canonical name, which contract names are deliberately FINER than the census,
# and which are genuine census gaps - live in the tooling-only authority below,
# read through the same vendored Lua 5.1 host the census gap generator uses.
#
# The authority is deliberately NOT in the descriptor: that file is byte-synced
# into the CWV mod bundle (tools/shared_lib/manifest.psd1), so a QA-only naming
# change must not touch it or qa/check_shared_lib_drift.ps1 fails until a shipped
# mod file is rewritten. See the PROVENANCE note in the authority.
$AUTHORITY_LUA = 'tools/shared_lib/_lib_appearance_name_authority.lua'

# The required MINIMUM is the architecture boundary and stays declared HERE, not
# derived from M.CELLS. If the manifest defined the boundary by itself, deleting
# a required surface from both the vocabulary and every contract would still
# pass. Deriving it from M.CELLS instead would silently turn every future census
# surface into a mandatory rewrite of all twelve contracts.
#
# This list is the historical eleven, respelled. The six surfaces #1157 added to
# the census (specials, remote_audio, hud_panels, portraits, item_card_2d,
# inventory_tooltip) are ACCEPTED when a contract opts into them but are not yet
# required; expanding the contracts to the full canonical sixteen is a coverage
# change, not a naming change, and is tracked by ISSUE #1197.
#
# Known limit until #1197 lands: the authority resolves contract name -> census
# name, so a canonical surface that NO contract mentions is legal here. Those
# surfaces would otherwise be invisible to this registry, so a successful run
# NAMES them (see the closing NOTE) rather than letting the silence pass for
# coverage. The edge axis needs nothing: all eight canonical edges are already
# refined by at least one contract edge.
$REQUIRED_SURFACES = @(
    'owner_1p', 'owner_3p', 'bot', 'husk',
    'inventory_preview', 'illusion_browser', 'cim_preview',
    'crafting_preview', 'lobby', 'score_team', 'hold_tab'
)
$REQUIRED_REPLAY_EDGES = @(
    'instance_load', 'initial_spawn', 'equip', 'wield',
    'customize', 'style_change', 'career_change', 'mission_transition', 'respawn',
    'hot_join', 'peer_ready', 'parity_ready', 'rejoin',
    'preview_open', 'preview_reopen', 'lobby_score_create',
    'mod_disable_restore'
)
$REQUIRED_CONCERNS = @(
    'unit_identity', 'transform', 'material', 'glow', 'pose',
    'effective_template', 'fade', 'icon', 'name'
)

# Which authority dispositions each axis may use. A surface may be a canonical
# census name or a recorded census GAP (a surface the census cannot express
# yet); an edge may be canonical or a declared REFINEMENT of a canonical edge,
# because the contracts axis is deliberately finer than the census one; the
# concern axis is contracts-only by construction. An 'alias' is a legacy
# spelling and is ALWAYS rejected, so a reverted rename fails loudly instead of
# quietly reintroducing the second vocabulary.
$ACCEPTED_KINDS = @{
    surface = @('canonical', 'census-gap')
    edge    = @('canonical', 'refinement')
    concern = @('contract-only')
}

function Get-AppearanceNameAuthority([string]$Root) {
    $luaExe = Join-Path $Root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
    $emitter = Join-Path $Root 'tools\shared_lib\emit-appearance-names.lua'
    if (-not (Test-Path -LiteralPath $luaExe -PathType Leaf)) {
        throw "vendored Lua 5.1 runtime is missing: $luaExe"
    }
    if (-not (Test-Path -LiteralPath $emitter -PathType Leaf)) {
        throw "name authority emitter is missing: $emitter"
    }
    # Native stderr is promoted to a terminating error under Stop; collect it as
    # ordinary output so a broken authority is reportable rather than a crash.
    $saved = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $raw = @(& $luaExe $emitter ($Root -replace '\\', '/') 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $saved
    }
    if ($code -ne 0) {
        throw ("reading $AUTHORITY_LUA failed (lua exit $code): " + ($raw -join '; '))
    }

    $authority = @{ surface = @{}; edge = @{}; concern = @{} }
    foreach ($line in $raw) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text.StartsWith('#')) { continue }
        $f = $text.Split("`t")
        if ($f.Count -lt 4) { throw "malformed authority row: $text" }
        $axis = [string]$f[0]
        if (-not $authority.ContainsKey($axis)) { throw "unknown authority axis '$axis'" }
        $authority[$axis][[string]$f[1]] = [pscustomobject]@{
            Kind      = [string]$f[2]
            Canonical = [string]$f[3]
            Reason    = if ($f.Count -ge 5) { [string]$f[4] } else { '' }
        }
    }
    foreach ($axis in @('surface', 'edge', 'concern')) {
        if ($authority[$axis].Count -eq 0) { throw "$AUTHORITY_LUA emitted no $axis names" }
    }
    return $authority
}

# The check that makes the two vocabularies one: every name a contract uses must
# be KNOWN to the authority and carry a kind this axis accepts. An unmapped name
# can never reach a cell declaration, and a legacy spelling names its own
# replacement instead of failing generically.
function Get-AuthorityNameErrors([string[]]$Names, [string]$Axis, [string]$Label, $Authority) {
    $errors = [System.Collections.Generic.List[string]]::new()
    $table = $Authority[$Axis]
    $accepted = $ACCEPTED_KINDS[$Axis]
    foreach ($name in @($Names)) {
        $text = [string]$name
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if (-not $table.ContainsKey($text)) {
            $errors.Add("$Label '$text' is unknown to the appearance name authority - a new surface or edge enters through M.CELLS / M.EDGES in tools/shared_lib/_lib_appearance_descriptor.lua and is then bound in $AUTHORITY_LUA")
            continue
        }
        $entry = $table[$text]
        if ($accepted -notcontains $entry.Kind) {
            if ($entry.Kind -eq 'alias') {
                $errors.Add("$Label '$text' is the legacy spelling of canonical '$($entry.Canonical)' - rename it to '$($entry.Canonical)'; the binding lives in $AUTHORITY_LUA")
            } else {
                $errors.Add("$Label '$text' is declared '$($entry.Kind)' in $AUTHORITY_LUA, which the $Axis axis does not accept")
            }
        }
    }
    return $errors.ToArray()
}

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
    $Authority,
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

    # Spelling: both what the manifest declares AND this gate's own required
    # minimum, so the hard-coded list above cannot drift from the authority.
    foreach ($axis in @(
        @{ Names = $surfaces; Axis = 'surface'; Label = 'SurfaceVocabulary surface' },
        @{ Names = $edges; Axis = 'edge'; Label = 'ReplayEdgeVocabulary replay edge' },
        @{ Names = $concernNames; Axis = 'concern'; Label = 'ConcernVocabulary concern' },
        @{ Names = $RequiredSurfaces; Axis = 'surface'; Label = 'required surface' },
        @{ Names = $RequiredReplayEdges; Axis = 'edge'; Label = 'required replay edge' },
        @{ Names = $RequiredConcerns; Axis = 'concern'; Label = 'required concern' }
    )) {
        foreach ($message in @(Get-AuthorityNameErrors $axis.Names $axis.Axis $axis.Label $Authority)) {
            $errors.Add($message)
        }
    }

    # Coverage: a manifest may add canonical surfaces beyond the minimum, but
    # never drop one that is required.
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
    [switch]$MissingTestName,
    [switch]$LegacySurfaceSpelling,
    [switch]$UnknownVocabularySurface,
    [switch]$UnknownVocabularyEdge,
    [switch]$ExtraGapSurface,
    [switch]$ExtraRefinementEdge
) {
    # The legacy case renames the second surface to its banned old spelling, so
    # the gate must reject it AND name the canonical replacement.
    $previewName = if ($LegacySurfaceSpelling) { 'preview_alt' } else { 'preview' }
    $surfaceMap = @{
        owner = @{ Disposition = 'covered'; Evidence = 'fixture owner adapter' }
    }
    $surfaceMap[$previewName] = if ($UnmappedCoveredSurface) {
        @{ Disposition = 'covered'; Evidence = 'fixture preview adapter' }
    } else {
        @{ Disposition = 'deferred'; Reason = 'fixture deferral' }
    }
    if ($DropSurface) { $surfaceMap.Remove($previewName) }
    $edgeMap = @{
        equip = @{ Disposition = 'covered'; Evidence = 'fixture equip replay' }
        join = @{ Disposition = 'not-applicable'; Reason = 'fixture local-only provider' }
    }
    if ($DropEdge) { $edgeMap.Remove('join') }

    $surfaceVocabulary = @('owner', $previewName)
    $edgeVocabulary = @('equip', 'join')
    # An opted-in census gap / refinement must be ACCEPTED even though it is not
    # in the required minimum: that is the "validated if present" rule.
    if ($ExtraGapSurface) {
        $surfaceVocabulary += 'bench'
        $surfaceMap['bench'] = @{ Disposition = 'deferred'; Reason = 'fixture census gap' }
    }
    if ($ExtraRefinementEdge) {
        $edgeVocabulary += 'join_late'
        $edgeMap['join_late'] = @{ Disposition = 'not-applicable'; Reason = 'fixture refinement' }
    }

    $tests = if ($DropTests) { @() } else {
        @(@{
            Path = 'qa/tests/fixture.lua'
            Names = @($(if ($MissingTestName) { 'missing marker' } else { 'fixture appearance test' }))
            Surfaces = @('owner')
            ReplayEdges = @('equip')
        })
    }
    if ($DropVocabularySurface) { $surfaceVocabulary = @('owner') }
    if ($UnknownVocabularySurface) { $surfaceVocabulary += 'not_a_surface' }
    if ($DropVocabularyEdge) { $edgeVocabulary = @('equip') }
    if ($UnknownVocabularyEdge) { $edgeVocabulary += 'not_an_edge' }
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
            @{ Name = 'missing named test fails'; Manifest = New-SelfTestManifest -MissingTestName; Needle = 'test name not found' },
            # #1158 single-vocabulary reconciliation.
            @{ Name = 'legacy spelling fails and names its replacement'; Manifest = New-SelfTestManifest -LegacySurfaceSpelling; Needle = "'preview_alt' is the legacy spelling of canonical 'preview' - rename it to 'preview'" },
            @{ Name = 'unmapped surface fails naming the authority'; Manifest = New-SelfTestManifest -UnknownVocabularySurface; Needle = "'not_a_surface' is unknown to the appearance name authority" },
            @{ Name = 'unmapped replay edge fails naming the authority'; Manifest = New-SelfTestManifest -UnknownVocabularyEdge; Needle = "'not_an_edge' is unknown to the appearance name authority" },
            @{ Name = 'opted-in census-gap surface is accepted'; Manifest = New-SelfTestManifest -ExtraGapSurface; Needle = $null },
            @{ Name = 'opted-in refinement edge is accepted'; Manifest = New-SelfTestManifest -ExtraRefinementEdge; Needle = $null }
        )
        $fixtureAuthority = @{
            surface = @{
                owner       = [pscustomobject]@{ Kind = 'canonical'; Canonical = 'owner'; Reason = '' }
                preview     = [pscustomobject]@{ Kind = 'canonical'; Canonical = 'preview'; Reason = '' }
                preview_alt = [pscustomobject]@{ Kind = 'alias'; Canonical = 'preview'; Reason = '' }
                bench       = [pscustomobject]@{ Kind = 'census-gap'; Canonical = ''; Reason = 'fixture gap' }
            }
            edge = @{
                equip     = [pscustomobject]@{ Kind = 'canonical'; Canonical = 'equip'; Reason = '' }
                join      = [pscustomobject]@{ Kind = 'canonical'; Canonical = 'join'; Reason = '' }
                join_late = [pscustomobject]@{ Kind = 'refinement'; Canonical = 'join'; Reason = 'fixture refinement' }
            }
            concern = @{
                unit_identity = [pscustomobject]@{ Kind = 'contract-only'; Canonical = ''; Reason = 'fixture' }
            }
        }
        $failed = 0
        foreach ($case in $cases) {
            $found = @(Test-AppearanceManifest $case.Manifest $temp $fixtureAuthority `
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

        # The fixture cases prove the RULES. This proves the gate is actually
        # plugged into the LIVE authority and that this script's own required
        # minimum still speaks its language: a self-test that only ever exercised
        # its own fixture would stay green with the real reader broken, which is
        # the inert-instrument class (docs/BUG_CLASSES.md § 85).
        try {
            $live = Get-AppearanceNameAuthority (Resolve-Path -LiteralPath $RepoRoot).Path
            $liveProblems = [System.Collections.Generic.List[string]]::new()
            foreach ($pair in @(
                @{ Names = $REQUIRED_SURFACES; Axis = 'surface'; Label = 'required surface' },
                @{ Names = $REQUIRED_REPLAY_EDGES; Axis = 'edge'; Label = 'required replay edge' },
                @{ Names = $REQUIRED_CONCERNS; Axis = 'concern'; Label = 'required concern' }
            )) {
                foreach ($message in @(Get-AuthorityNameErrors $pair.Names $pair.Axis $pair.Label $live)) {
                    $liveProblems.Add($message)
                }
            }
            # Every spelling this gate used before the rename must stay recorded,
            # or a reverted rename would read as an unknown name and lose the
            # "rename it to X" instruction.
            foreach ($legacy in @('bot_3p', 'remote_husk_3p', 'cosmetic_preview', 'athanor_preview', 'lobby_preview', 'score_screen')) {
                if (-not $live['surface'].ContainsKey($legacy) -or $live['surface'][$legacy].Kind -ne 'alias') {
                    $liveProblems.Add("legacy surface spelling '$legacy' is no longer recorded as an alias")
                }
            }
            if (-not $live['edge'].ContainsKey('customization_change') -or $live['edge']['customization_change'].Kind -ne 'alias') {
                $liveProblems.Add("legacy edge spelling 'customization_change' is no longer recorded as an alias")
            }
            if ($liveProblems.Count -gt 0) {
                foreach ($problem in $liveProblems) {
                    Write-Host "  [FAIL] live authority: $problem" -ForegroundColor Red
                }
                $failed += $liveProblems.Count
            } elseif (-not $Quiet) {
                Write-Host ("  [PASS] live authority readable and this gate's required set resolves ({0} surfaces, {1} edges, {2} concerns)" -f
                    $live['surface'].Count, $live['edge'].Count, $live['concern'].Count) -ForegroundColor Green
            }
        } catch {
            Write-Host "  [FAIL] live authority unreadable: $($_.Exception.Message)" -ForegroundColor Red
            $failed++
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
    $authority = Get-AppearanceNameAuthority $resolvedRoot
    $failures = @(Test-AppearanceManifest $manifest $resolvedRoot $authority `
        -RequiredSurfaces $REQUIRED_SURFACES `
        -RequiredReplayEdges $REQUIRED_REPLAY_EDGES `
        -RequiredConcerns $REQUIRED_CONCERNS)
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

    # Visibility, not enforcement (#1197). Name resolution only runs contract ->
    # census, so a canonical surface no contract mentions is silently absent -
    # exactly the "gap hides between the two vocabularies" shape this change
    # exists to kill. Report it on every green run so the remaining coverage debt
    # is stated rather than inferred. This never changes the exit code.
    $declaredSurfaces = @($manifest.SurfaceVocabulary)
    $unrepresented = @($authority['surface'].Keys |
        Where-Object { $authority['surface'][$_].Kind -eq 'canonical' -and $declaredSurfaces -notcontains $_ } |
        Sort-Object)
    if ($unrepresented.Count -gt 0) {
        Write-Host ("[check_appearance_contracts] NOTE - {0} canonical surface(s) have no contract representation (issue #1197): {1}" -f
            $unrepresented.Count, ($unrepresented -join ', '))
    }
}
exit 0
