# Blocking offline provenance/reproduction gate for issue #1436's Hotfix
# 6.11.2 Dagger H2 and Axe & Falchion H1/H2 slice. Checked-in adjacent diffs
# select exactly three official boundary operations; second passes rehydrate
# those paths against the current source anchor. Output stays outside the repo.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$SourceRepo,
    [switch]$RequireSource,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Write-Detail([string]$Message, [string]$Color = 'DarkGray') {
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Invoke-LuaGeneratedFile {
    param(
        [Parameter(Mandatory)][string]$Lua,
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$OutputPath
    )
    $hadOutput = Test-Path Env:WT_HISTORY_OUTPUT
    $priorOutput = $env:WT_HISTORY_OUTPUT
    $pushed = $false
    try {
        $env:WT_HISTORY_OUTPUT = $OutputPath
        Push-Location -LiteralPath $WorkingDirectory
        $pushed = $true
        $output = @(& $Lua $Script @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Lua generator failed (exit $LASTEXITCODE): $($output -join ' ')"
        }
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
            throw "Lua generator did not create $OutputPath"
        }
    }
    finally {
        if ($pushed) { Pop-Location }
        if ($hadOutput) { $env:WT_HISTORY_OUTPUT = $priorOutput }
        else { Remove-Item Env:WT_HISTORY_OUTPUT -ErrorAction SilentlyContinue }
    }
}

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $anchorHelpers = Join-Path $root 'tools\weapon-history\source-anchor.ps1'
    . $anchorHelpers
    $anchor = Read-WtHistorySourceAnchor -RepoRoot $root
    $toolRoot = Join-Path $root 'tools\weapon-history'
    $evidenceRoot = Join-Path $toolRoot 'evidence\patch_6_11_2'
    $extractor = Join-Path $toolRoot 'extract_weapon_history.lua'
    $oracleExtractor = Join-Path $toolRoot `
        'source_oracle\extract_weapon_history_oracle.lua'
    $generator = Join-Path $toolRoot 'generate_patch_6_11_2_history.lua'
    $sourceCatalog = Join-Path $evidenceRoot `
        '_wt_history_6_11_2_source_catalog.lua'
    $adjacentEvidence = Join-Path $evidenceRoot `
        '_wt_history_snapshot_6_11_1_to_6_11_2_generated.lua'
    $rehydratedEvidence = Join-Path $evidenceRoot `
        '_wt_history_snapshot_6_11_1_rehydrated_generated.lua'
    $axeAdjacentEvidence = Join-Path $evidenceRoot `
        '_wt_history_snapshot_6_11_1_axe_falchion_to_6_11_2_generated.lua'
    $axeRehydratedEvidence = Join-Path $evidenceRoot `
        '_wt_history_snapshot_6_11_1_axe_falchion_rehydrated_generated.lua'
    $generatedCatalog = Join-Path $root `
        'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_11_2_catalog.lua'
    $devCatalog = Join-Path $root `
        'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_6_11_2_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pinned = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracleExtractor = '767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $generator = '811409f567fbeb6e1594a481f5a8c1204077d36e224f083c7fcbf806d2cac026'
        $sourceCatalog = '3a5c9675f415bc31668521ad6e9373ef475eceb797c275bbdc584b7d63161f37'
        $adjacentEvidence = 'c73b84364a83038ccdd60522b19d654e08519fe706289174253acab74e6716c6'
        $rehydratedEvidence = '5479c3a8d57e60d6716182923731087088d9146394a39674f943a7b21d4405b2'
        $axeAdjacentEvidence = '8e3fbd667f3503a5d27bdd3b7588f0b5405ceddc6f3545db85cf8b1d5ad0c3c3'
        $axeRehydratedEvidence = 'e12c444ba28ec368ce44823150ee6496f24d0ed6cbbd3dfc08c4f114bf1c0ff8'
        $generatedCatalog = '47797bf35cd07679d2517f213a29c729829a29b96ef4ea02c746f7c1a84e3efc'
        $devCatalog = '47797bf35cd07679d2517f213a29c729829a29b96ef4ea02c746f7c1a84e3efc'
    }
    foreach ($entry in $pinned.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) {
            throw "missing Hotfix 6.11.2 provenance artifact: $($entry.Key)"
        }
        $actual = Get-Sha256 $entry.Key
        if ($actual -cne $entry.Value) {
            throw "Hotfix 6.11.2 pinned hash drift: $($entry.Key) expected=$($entry.Value) actual=$actual"
        }
    }
    if ((Get-Sha256 $generatedCatalog) -cne (Get-Sha256 $devCatalog)) {
        throw 'Hotfix 6.11.2 public and Dev generated catalogs are not byte-identical'
    }

    $sourceText = [IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8)
    if ($sourceText.IndexOf($anchor.ContentRevision,
            [StringComparison]::Ordinal) -lt 0) {
        throw 'Hotfix 6.11.2 source catalog does not consume the central current-source anchor'
    }
    $artifactMatches = [regex]::Matches($sourceText,
        '(?m)^\s*(_wt_history_snapshot_[A-Za-z0-9_]+)\s*=\s*"([0-9a-f]{64})"')
    if ($artifactMatches.Count -ne 4) {
        throw "Hotfix 6.11.2 evidence ledger must contain exactly 4 artifacts; got $($artifactMatches.Count)"
    }
    foreach ($match in $artifactMatches) {
        $evidencePath = Join-Path $evidenceRoot ($match.Groups[1].Value + '.lua')
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw "Hotfix 6.11.2 ledger artifact is missing: $evidencePath"
        }
        $actual = Get-Sha256 $evidencePath
        if ($actual -cne $match.Groups[2].Value) {
            throw "Hotfix 6.11.2 evidence ledger drift: $evidencePath expected=$($match.Groups[2].Value) actual=$actual"
        }
    }

    $expectedEvidence = @(
        '_wt_history_6_11_2_source_catalog.lua',
        '_wt_history_snapshot_6_11_1_axe_falchion_rehydrated_generated.lua',
        '_wt_history_snapshot_6_11_1_axe_falchion_to_6_11_2_generated.lua',
        '_wt_history_snapshot_6_11_1_rehydrated_generated.lua',
        '_wt_history_snapshot_6_11_1_to_6_11_2_generated.lua'
    ) | Sort-Object
    $actualEvidence = @(Get-ChildItem -LiteralPath $evidenceRoot -File `
        -Filter '*.lua' | ForEach-Object Name | Sort-Object)
    if (($actualEvidence -join "`n") -cne ($expectedEvidence -join "`n")) {
        throw 'Hotfix 6.11.2 evidence directory contains an unledgered or missing Lua artifact'
    }

    $historicalRevision = '1a0a4e0caf5c119bfe8d42a4d1bc23b34a7b005e'
    $postRevision = '9fbf92c11acfaca5c49f5e40d565b0743a2bdf43'
    $currentRevision = $anchor.ContentRevision
    $sourcePath = `
        'scripts/settings/equipment/weapon_templates/1h_dagger_wizard.lua'
    $axeSourcePath = `
        'scripts/settings/equipment/weapon_templates/dual_wield_axe_falchion.lua'
    $damageProfilePath = 'scripts/settings/equipment/damage_profile_templates.lua'
    $networkLookupPath = 'scripts/network_lookup/network_lookup.lua'
    $sourceRequirements = @(
        [pscustomobject]@{ Revision = $historicalRevision; Path = $sourcePath; Blob = '656ef0ffac628d707d13adbf3c4a8950aec7fca7' },
        [pscustomobject]@{ Revision = $postRevision; Path = $sourcePath; Blob = 'fcfeecee65342ae8b3bb4a75a57e248c3a677b1e' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $sourcePath; Blob = 'fcfeecee65342ae8b3bb4a75a57e248c3a677b1e' },
        [pscustomobject]@{ Revision = $historicalRevision; Path = $axeSourcePath; Blob = '5d51821f8186ceb111e4ff97dd2b975d159bde4a' },
        [pscustomobject]@{ Revision = $postRevision; Path = $axeSourcePath; Blob = 'fae29e68dd3779c66a0e8c09285ded12b33667c5' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $axeSourcePath; Blob = 'fae29e68dd3779c66a0e8c09285ded12b33667c5' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $damageProfilePath; Blob = 'e8330328d0085f6aee09e0495ba88fdc0211d5aa' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $networkLookupPath; Blob = 'cc1231cc56cb22450c05a2da12e7e0aa1a634695' }
    )
    $sourceSelection = Find-WtHistorySourceRepo -Root $root `
        -Explicit $SourceRepo -Requirements $sourceRequirements
    $source = $sourceSelection.Path
    if (-not $source) {
        $selectionDetail = if ($sourceSelection.Rejections.Count -gt 0) {
            $sourceSelection.Rejections -join '; '
        }
        else { 'no source checkout candidate was found' }
        if ($RequireSource) {
            throw "Vermintide-2-Source-Code checkout is required but unavailable or incomplete: $selectionDetail"
        }
        Write-Host "[check_wt_history_patch_6_11_2_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned evidence/output OK): $selectionDetail" -ForegroundColor Yellow
        exit 0
    }

    $damageProfiles = Invoke-WtHistoryReadOnlyGit -Repository $source `
        -Arguments @('show', "$currentRevision`:$damageProfilePath")
    if ($damageProfiles.ExitCode -ne 0) {
        throw 'Hotfix 6.11.2 current native damage-profile source is unreadable'
    }
    $damageProfileText = $damageProfiles.Output -join "`n"
    $daggerHistoricalProfileMatches = [regex]::Matches($damageProfileText,
        '(?m)^DamageProfileTemplates\.dagger_h1_medium_smiter_diag\s*=\s*\{\s*$')
    $daggerCurrentProfileMatches = [regex]::Matches($damageProfileText,
        '(?m)^new_template\([^\r\n]*"medium_burning_smiter_stab_H"[^\r\n]*\)\s*$')
    $axeHistoricalProfileMatches = [regex]::Matches($damageProfileText,
        '(?m)^DamageProfileTemplates\.axe_falcion_heavy_smiter_vertical_right\s*=\s*\{\s*$')
    $axeCurrentProfileMatches = [regex]::Matches($damageProfileText,
        '(?m)^new_template\("light_slashing_smiter_dual", nil, "light_blunt_smiter_dual", nil, "blunt_smiter"\)\s*$')
    if ($daggerHistoricalProfileMatches.Count -ne 1 -or
        $daggerCurrentProfileMatches.Count -ne 1 -or
        $axeHistoricalProfileMatches.Count -ne 1 -or
        $axeCurrentProfileMatches.Count -ne 1) {
        throw 'Hotfix 6.11.2 native damage-profile identity contract drift'
    }

    $networkLookup = Invoke-WtHistoryReadOnlyGit -Repository $source `
        -Arguments @('show', "$currentRevision`:$networkLookupPath")
    if ($networkLookup.ExitCode -ne 0) {
        throw 'Hotfix 6.11.2 current damage-profile lookup source is unreadable'
    }
    $lookupMatches = [regex]::Matches(($networkLookup.Output -join "`n"),
        '(?m)^NetworkLookup\.damage_profiles\s*=\s*create_lookup\(\{\},\s*DamageProfileTemplates\)\s*$')
    if ($lookupMatches.Count -ne 1) {
        throw 'Hotfix 6.11.2 native damage-profile network lookup contract drift'
    }

    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $tempBase `
        ('wt1436-p6112-' + [guid]::NewGuid().ToString('N'))
    if (-not $temporaryRoot.StartsWith($tempBase,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'unsafe temporary reproduction path'
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        $extractorSelfTest = @(& $lua $extractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hotfix 6.11.2 primary numeric self-test failed: $($extractorSelfTest -join ' ')"
        }
        $oracleSelfTest = @(& $lua $oracleExtractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hotfix 6.11.2 oracle numeric self-test failed: $($oracleSelfTest -join ' ')"
        }

        $primaryAdjacent = Join-Path $temporaryRoot 'primary-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @($historicalRevision, $postRevision, $sourcePath) `
            -WorkingDirectory $source -OutputPath $primaryAdjacent
        if ((Get-Sha256 $primaryAdjacent) -cne (Get-Sha256 $adjacentEvidence)) {
            throw 'Hotfix 6.11.2 adjacent source evidence is not byte-reproducible'
        }

        $oracleAdjacent = Join-Path $temporaryRoot 'oracle-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, $historicalRevision,
                $postRevision, $sourcePath) `
            -WorkingDirectory $root -OutputPath $oracleAdjacent
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $adjacentEvidence $oracleAdjacent 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hotfix 6.11.2 independent adjacent evidence differs: $($comparison -join ' ')"
        }

        $axePrimaryAdjacent = Join-Path $temporaryRoot 'axe-primary-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @($historicalRevision, $postRevision, $axeSourcePath) `
            -WorkingDirectory $source -OutputPath $axePrimaryAdjacent
        if ((Get-Sha256 $axePrimaryAdjacent) -cne
            (Get-Sha256 $axeAdjacentEvidence)) {
            throw 'Hotfix 6.11.2 Axe & Falchion adjacent source evidence is not byte-reproducible'
        }

        $axeOracleAdjacent = Join-Path $temporaryRoot 'axe-oracle-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, $historicalRevision,
                $postRevision, $axeSourcePath) `
            -WorkingDirectory $root -OutputPath $axeOracleAdjacent
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $axeAdjacentEvidence $axeOracleAdjacent 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hotfix 6.11.2 independent Axe & Falchion adjacent evidence differs: $($comparison -join ' ')"
        }

        $primaryRehydrated = Join-Path $temporaryRoot 'primary-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @('--rehydrate-snapshot', $historicalRevision,
                $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $source -OutputPath $primaryRehydrated
        if ((Get-Sha256 $primaryRehydrated) -cne (Get-Sha256 $rehydratedEvidence)) {
            throw 'Hotfix 6.11.2 current-anchor evidence is not byte-reproducible'
        }

        $oracleRehydrated = Join-Path $temporaryRoot 'oracle-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, '--rehydrate-snapshot',
                $historicalRevision, $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $root -OutputPath $oracleRehydrated
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $rehydratedEvidence $oracleRehydrated 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hotfix 6.11.2 independent current-anchor evidence differs: $($comparison -join ' ')"
        }

        $axePrimaryRehydrated = Join-Path $temporaryRoot `
            'axe-primary-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @('--rehydrate-snapshot', $historicalRevision,
                $currentRevision, $axeAdjacentEvidence) `
            -WorkingDirectory $source -OutputPath $axePrimaryRehydrated
        if ((Get-Sha256 $axePrimaryRehydrated) -cne
            (Get-Sha256 $axeRehydratedEvidence)) {
            throw 'Hotfix 6.11.2 Axe & Falchion current-anchor evidence is not byte-reproducible'
        }

        $axeOracleRehydrated = Join-Path $temporaryRoot `
            'axe-oracle-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, '--rehydrate-snapshot',
                $historicalRevision, $currentRevision, $axeAdjacentEvidence) `
            -WorkingDirectory $root -OutputPath $axeOracleRehydrated
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $axeRehydratedEvidence $axeOracleRehydrated 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hotfix 6.11.2 independent Axe & Falchion current-anchor evidence differs: $($comparison -join ' ')"
        }

        $temporaryCatalog = Join-Path $temporaryRoot `
            '_wt_history_6_11_2_catalog.lua'
        $generatorOutput = @(& $lua $generator $source $evidenceRoot `
            $temporaryCatalog 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hotfix 6.11.2 catalog generator failed (exit $LASTEXITCODE): $($generatorOutput -join ' ')"
        }
        if ((Get-Sha256 $temporaryCatalog) -cne
            (Get-Sha256 $generatedCatalog)) {
            throw 'Hotfix 6.11.2 generated catalog is not byte-reproducible'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
            if (-not $resolvedTemporary.StartsWith($tempBase,
                    [StringComparison]::OrdinalIgnoreCase)) {
                throw 'refusing to remove unsafe temporary reproduction path'
            }
            $unexpectedDirectories = @(Get-ChildItem -LiteralPath `
                $resolvedTemporary -Directory -Force)
            if ($unexpectedDirectories.Count -ne 0) {
                throw 'refusing to clean a non-flat temporary reproduction path'
            }
            foreach ($temporaryFile in @(Get-ChildItem -LiteralPath `
                    $resolvedTemporary -File -Force)) {
                Remove-Item -LiteralPath $temporaryFile.FullName -Force
            }
            Remove-Item -LiteralPath $resolvedTemporary -Force
        }
    }

    Write-Detail "[check_wt_history_patch_6_11_2_reproducibility] OK - three native routes across Dagger and Axe & Falchion, current guards, independent oracle, and catalog reproduced from $source" 'Green'
    exit 0
}
catch {
    Write-Host "[check_wt_history_patch_6_11_2_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
