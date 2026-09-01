# Blocking offline provenance/reproduction gate for issue #1436's Patch
# 6.11.0 Kruber Longbow slice. The adjacent evaluator selects the identical
# aim_zoom_delay leaf exposed by both source-evaluated templates; rehydration
# guards both current routes. All generated scratch output stays outside repo.

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
    . (Join-Path $root 'tools\weapon-history\source-anchor.ps1')
    $anchor = Read-WtHistorySourceAnchor -RepoRoot $root
    $toolRoot = Join-Path $root 'tools\weapon-history'
    $evidenceRoot = Join-Path $toolRoot 'evidence\patch_6_11_0'
    $extractor = Join-Path $toolRoot 'extract_weapon_history.lua'
    $oracleExtractor = Join-Path $toolRoot `
        'source_oracle\extract_weapon_history_oracle.lua'
    $generator = Join-Path $toolRoot 'generate_patch_6_11_0_history.lua'
    $sourceCatalog = Join-Path $evidenceRoot `
        '_wt_history_6_11_0_source_catalog.lua'
    $adjacentEvidence = Join-Path $evidenceRoot `
        '_wt_history_snapshot_6_10_0_to_6_11_0_generated.lua'
    $rehydratedEvidence = Join-Path $evidenceRoot `
        '_wt_history_snapshot_6_10_0_rehydrated_generated.lua'
    $generatedCatalog = Join-Path $root `
        'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_11_0_catalog.lua'
    $devCatalog = Join-Path $root `
        'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_6_11_0_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pinned = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracleExtractor = '767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $generator = 'c4314b6573d67bdf0e93ba568f34499eb7faa6ad599e9c9896d74d7e477c19a5'
        $sourceCatalog = '009940abefe416cac2a7f9b3065ab225dd60388e152428b5333bb454080ab52a'
        $adjacentEvidence = '87b6f190c7beade349cbcb96a869c8bb43c2eba645849b4811bf670230739841'
        $rehydratedEvidence = '40a209e92700b23f39dea9ec0597a023ad9a78b97415d82baff8b55eaa5c3251'
        $generatedCatalog = 'f6bff8ce740a42e9e8473e7b18fbf31f9a28bd7e29b4156ff9b2e52b1df3fd56'
        $devCatalog = 'f6bff8ce740a42e9e8473e7b18fbf31f9a28bd7e29b4156ff9b2e52b1df3fd56'
    }
    foreach ($entry in $pinned.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) {
            throw "missing Patch 6.11.0 provenance artifact: $($entry.Key)"
        }
        $actual = Get-Sha256 $entry.Key
        if ($actual -cne $entry.Value) {
            throw "Patch 6.11.0 pinned hash drift: $($entry.Key) expected=$($entry.Value) actual=$actual"
        }
    }
    if ((Get-Sha256 $generatedCatalog) -cne (Get-Sha256 $devCatalog)) {
        throw 'Patch 6.11.0 public and Dev generated catalogs are not byte-identical'
    }

    $sourceText = [IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8)
    if ($sourceText.IndexOf($anchor.ContentRevision,
            [StringComparison]::Ordinal) -lt 0) {
        throw 'Patch 6.11.0 source catalog does not consume the central current-source anchor'
    }
    $artifactMatches = [regex]::Matches($sourceText,
        '(?m)^\s*(_wt_history_snapshot_[A-Za-z0-9_]+)\s*=\s*"([0-9a-f]{64})"')
    if ($artifactMatches.Count -ne 2) {
        throw "Patch 6.11.0 evidence ledger must contain exactly 2 artifacts; got $($artifactMatches.Count)"
    }
    foreach ($match in $artifactMatches) {
        $evidencePath = Join-Path $evidenceRoot ($match.Groups[1].Value + '.lua')
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw "Patch 6.11.0 ledger artifact is missing: $evidencePath"
        }
        $actual = Get-Sha256 $evidencePath
        if ($actual -cne $match.Groups[2].Value) {
            throw "Patch 6.11.0 evidence ledger drift: $evidencePath expected=$($match.Groups[2].Value) actual=$actual"
        }
    }

    $expectedEvidence = @(
        '_wt_history_6_11_0_source_catalog.lua',
        '_wt_history_snapshot_6_10_0_rehydrated_generated.lua',
        '_wt_history_snapshot_6_10_0_to_6_11_0_generated.lua'
    ) | Sort-Object
    $actualEvidence = @(Get-ChildItem -LiteralPath $evidenceRoot -File `
        -Filter '*.lua' | ForEach-Object Name | Sort-Object)
    if (($actualEvidence -join "`n") -cne ($expectedEvidence -join "`n")) {
        throw 'Patch 6.11.0 evidence directory contains an unledgered or missing Lua artifact'
    }

    $historicalRevision = '5ff26df11311ba011f3313b9b232ed0d8b64b921'
    $postRevision = 'abe82ab4ba3e00c22d912093b37234c59f8a00d9'
    $currentRevision = $anchor.ContentRevision
    $sourcePath = `
        'scripts/settings/equipment/weapon_templates/longbows_empire.lua'
    $sourceRequirements = @(
        [pscustomobject]@{ Revision = $historicalRevision; Path = $sourcePath; Blob = '6408a36495e3c78e9a9ed2dbc91a913c512d9aed' },
        [pscustomobject]@{ Revision = $postRevision; Path = $sourcePath; Blob = 'b4e374e2d9a2dbc0c25537617163901eeca1fc03' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $sourcePath; Blob = 'a4685fbd52464f3a65ade77776a85a131dea8476' }
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
        Write-Host "[check_wt_history_patch_6_11_0_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned evidence/output OK): $selectionDetail" -ForegroundColor Yellow
        exit 0
    }

    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $tempBase `
        ('wt1436-p6110-' + [guid]::NewGuid().ToString('N'))
    if (-not $temporaryRoot.StartsWith($tempBase,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'unsafe temporary reproduction path'
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        $extractorSelfTest = @(& $lua $extractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.11.0 primary numeric self-test failed: $($extractorSelfTest -join ' ')"
        }
        $oracleSelfTest = @(& $lua $oracleExtractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.11.0 oracle numeric self-test failed: $($oracleSelfTest -join ' ')"
        }

        $primaryAdjacent = Join-Path $temporaryRoot 'primary-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @($historicalRevision, $postRevision, $sourcePath) `
            -WorkingDirectory $source -OutputPath $primaryAdjacent
        if ((Get-Sha256 $primaryAdjacent) -cne (Get-Sha256 $adjacentEvidence)) {
            throw 'Patch 6.11.0 adjacent source evidence is not byte-reproducible'
        }

        $oracleAdjacent = Join-Path $temporaryRoot 'oracle-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, $historicalRevision,
                $postRevision, $sourcePath) `
            -WorkingDirectory $root -OutputPath $oracleAdjacent
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $adjacentEvidence $oracleAdjacent 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.11.0 independent adjacent evidence differs: $($comparison -join ' ')"
        }

        $primaryRehydrated = Join-Path $temporaryRoot 'primary-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @('--rehydrate-snapshot', $historicalRevision,
                $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $source -OutputPath $primaryRehydrated
        if ((Get-Sha256 $primaryRehydrated) -cne (Get-Sha256 $rehydratedEvidence)) {
            throw 'Patch 6.11.0 current-anchor evidence is not byte-reproducible'
        }

        $oracleRehydrated = Join-Path $temporaryRoot 'oracle-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, '--rehydrate-snapshot',
                $historicalRevision, $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $root -OutputPath $oracleRehydrated
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $rehydratedEvidence $oracleRehydrated 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.11.0 independent current-anchor evidence differs: $($comparison -join ' ')"
        }

        $temporaryCatalog = Join-Path $temporaryRoot `
            '_wt_history_6_11_0_catalog.lua'
        $generatorOutput = @(& $lua $generator $source $evidenceRoot `
            $temporaryCatalog 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.11.0 catalog generator failed (exit $LASTEXITCODE): $($generatorOutput -join ' ')"
        }
        if ((Get-Sha256 $temporaryCatalog) -cne
            (Get-Sha256 $generatedCatalog)) {
            throw 'Patch 6.11.0 generated catalog is not byte-reproducible'
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

    Write-Detail "[check_wt_history_patch_6_11_0_reproducibility] OK - two-template adjacent boundary, current guards, independent oracle, and catalog reproduced from $source" 'Green'
    exit 0
}
catch {
    Write-Host "[check_wt_history_patch_6_11_0_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
