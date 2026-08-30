# Blocking offline provenance/reproduction gate for issue #1436's Patch 3.1
# Blunderbuss slice. The checked-in adjacent diff selects one official
# boundary operation; a second pass rehydrates that path against the current
# source anchor. All generated output is written outside the repository.

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
    } finally {
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
    $evidenceRoot = Join-Path $toolRoot 'evidence\patch_3_1'
    $extractor = Join-Path $toolRoot 'extract_weapon_history.lua'
    $oracleExtractor = Join-Path $toolRoot 'source_oracle\extract_weapon_history_oracle.lua'
    $generator = Join-Path $toolRoot 'generate_patch_3_1_history.lua'
    $sourceCatalog = Join-Path $evidenceRoot '_wt_history_3_1_source_catalog.lua'
    $adjacentEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_pre_3_1_to_3_1_generated.lua'
    $rehydratedEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_pre_3_1_rehydrated_generated.lua'
    $generatedCatalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_3_1_catalog.lua'
    $devCatalog = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_3_1_catalog.lua'
    $ledger = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_completeness_ledger.lua'
    $devLedger = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_completeness_ledger.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pinned = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracleExtractor = '767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $generator = 'feda7d45e61f841a759cbc89cebab23fe1cbd1544a9c2936725422eebb468948'
        $sourceCatalog = 'b49513c06f9bcfe2fae9d12866e8ddfb07d2dccc67472208af4645eca12601e6'
        $adjacentEvidence = '63047d1c57551eca5cb46763d91ada62e9ae2d0a945232e591c7e4500dde5d76'
        $rehydratedEvidence = '7563d45d92bafbcc8be35cc8b5130ed59a8520b8fc4a7aa1e9f372aac9020c14'
        $generatedCatalog = '97591a96fe5187f47eb2fc50f1b01096885073cceda14a965161d1f57f9ea74e'
        $devCatalog = '97591a96fe5187f47eb2fc50f1b01096885073cceda14a965161d1f57f9ea74e'
        $ledger = '77512ca3ae7254e97e397865c208530e71425db553f7356d6d6e7fe8da54bad2'
        $devLedger = '77512ca3ae7254e97e397865c208530e71425db553f7356d6d6e7fe8da54bad2'
    }
    foreach ($entry in $pinned.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) {
            throw "missing Patch 3.1 provenance artifact: $($entry.Key)"
        }
        $actual = Get-Sha256 $entry.Key
        if ($actual -cne $entry.Value) {
            throw "Patch 3.1 pinned hash drift: $($entry.Key) expected=$($entry.Value) actual=$actual"
        }
    }
    if ((Get-Sha256 $generatedCatalog) -cne (Get-Sha256 $devCatalog)) {
        throw 'Patch 3.1 public/dev catalogs are not byte-identical'
    }
    if ((Get-Sha256 $ledger) -cne (Get-Sha256 $devLedger)) {
        throw 'Patch 3.1 public/dev completeness ledgers are not byte-identical'
    }

    $sourceText = [IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8)
    if ($sourceText.IndexOf($anchor.ContentRevision,
            [StringComparison]::Ordinal) -lt 0) {
        throw 'Patch 3.1 source catalog does not consume the central current-source anchor'
    }
    foreach ($requiredSourceLiteral in @(
        'blunderbuss_template_1_vs',
        'current_only_versus_template',
        'https://www.vermintide.com/news/patch-31'
    )) {
        if ($sourceText.IndexOf($requiredSourceLiteral,
                [StringComparison]::Ordinal) -lt 0) {
            throw "Patch 3.1 source catalog is missing bounded-scope evidence: $requiredSourceLiteral"
        }
    }
    $artifactMatches = [regex]::Matches($sourceText,
        '(?m)^\s*(_wt_history_snapshot_[A-Za-z0-9_]+)\s*=\s*"([0-9a-f]{64})"')
    if ($artifactMatches.Count -ne 2) {
        throw "Patch 3.1 evidence ledger must contain exactly 2 artifacts; got $($artifactMatches.Count)"
    }
    foreach ($match in $artifactMatches) {
        $evidencePath = Join-Path $evidenceRoot ($match.Groups[1].Value + '.lua')
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw "Patch 3.1 ledger artifact is missing: $evidencePath"
        }
        $actual = Get-Sha256 $evidencePath
        if ($actual -cne $match.Groups[2].Value) {
            throw "Patch 3.1 evidence ledger drift: $evidencePath expected=$($match.Groups[2].Value) actual=$actual"
        }
    }

    $expectedEvidence = @(
        '_wt_history_3_1_source_catalog.lua',
        '_wt_history_snapshot_pre_3_1_rehydrated_generated.lua',
        '_wt_history_snapshot_pre_3_1_to_3_1_generated.lua'
    ) | Sort-Object
    $actualEvidence = @(Get-ChildItem -LiteralPath $evidenceRoot -File -Filter '*.lua' |
        ForEach-Object Name | Sort-Object)
    if (($actualEvidence -join "`n") -cne ($expectedEvidence -join "`n")) {
        throw 'Patch 3.1 evidence directory contains an unledgered or missing Lua artifact'
    }

    $extractorSelfTest = @(& $lua $extractor --self-test 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Patch 3.1 primary numeric/presence self-test failed: $($extractorSelfTest -join ' ')"
    }
    $oracleSelfTest = @(& $lua $oracleExtractor --self-test 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Patch 3.1 oracle numeric/presence self-test failed: $($oracleSelfTest -join ' ')"
    }

    $historicalRevision = 'c96aa3858011ecd557d55d80b66fe3bb8342eeb2'
    $postRevision = '3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63'
    $currentRevision = $anchor.ContentRevision
    $sourcePath = 'scripts/settings/equipment/weapon_templates/blunderbusses.lua'
    $sourceRequirements = @(
        [pscustomobject]@{ Revision = $historicalRevision; Path = $sourcePath; Blob = 'f8f6ec97a974bd5767c1ccabf9fc593dba785d34' },
        [pscustomobject]@{ Revision = $postRevision; Path = $sourcePath; Blob = '5370ab322355f8066377779aed1fed8e00a864ba' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $sourcePath; Blob = '87dca4018c18051d653a80b7aff501ed9815a5d0' }
    )
    $sourceSelection = Find-WtHistorySourceRepo -Root $root -Explicit $SourceRepo `
        -Requirements $sourceRequirements
    $source = $sourceSelection.Path
    if (-not $source) {
        $selectionDetail = if ($sourceSelection.Rejections.Count -gt 0) {
            $sourceSelection.Rejections -join '; '
        } else { 'no source checkout candidate was found' }
        if ($RequireSource) {
            throw "Vermintide-2-Source-Code checkout is required but unavailable or incomplete: $selectionDetail"
        }
        Write-Host "[check_wt_history_patch_3_1_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned evidence/output OK): $selectionDetail" -ForegroundColor Yellow
        exit 0
    }

    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $tempBase ('wt1436-p31-' + [guid]::NewGuid().ToString('N'))
    if (-not $temporaryRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'unsafe temporary reproduction path'
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        $primaryAdjacent = Join-Path $temporaryRoot 'primary-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @($historicalRevision, $postRevision, $sourcePath) `
            -WorkingDirectory $source -OutputPath $primaryAdjacent
        if ((Get-Sha256 $primaryAdjacent) -cne (Get-Sha256 $adjacentEvidence)) {
            throw 'Patch 3.1 adjacent source evidence is not byte-reproducible'
        }

        $oracleAdjacent = Join-Path $temporaryRoot 'oracle-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, $historicalRevision,
                $postRevision, $sourcePath) `
            -WorkingDirectory $root -OutputPath $oracleAdjacent
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $adjacentEvidence $oracleAdjacent 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 3.1 independent adjacent evidence differs: $($comparison -join ' ')"
        }

        $primaryRehydrated = Join-Path $temporaryRoot 'primary-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @('--rehydrate-snapshot', $historicalRevision,
                $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $source -OutputPath $primaryRehydrated
        if ((Get-Sha256 $primaryRehydrated) -cne (Get-Sha256 $rehydratedEvidence)) {
            throw 'Patch 3.1 current-anchor evidence is not byte-reproducible'
        }

        $oracleRehydrated = Join-Path $temporaryRoot 'oracle-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, '--rehydrate-snapshot',
                $historicalRevision, $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $root -OutputPath $oracleRehydrated
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $rehydratedEvidence $oracleRehydrated 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 3.1 independent current-anchor evidence differs: $($comparison -join ' ')"
        }

        $temporaryCatalog = Join-Path $temporaryRoot '_wt_history_3_1_catalog.lua'
        $generatorOutput = @(& $lua $generator $source $evidenceRoot $temporaryCatalog 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 3.1 catalog generator failed (exit $LASTEXITCODE): $($generatorOutput -join ' ')"
        }
        if ((Get-Sha256 $temporaryCatalog) -cne (Get-Sha256 $generatedCatalog)) {
            throw 'Patch 3.1 generated catalog is not byte-reproducible'
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
            if (-not $resolvedTemporary.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'refusing to remove unsafe temporary reproduction path'
            }
            $unexpectedDirectories = @(Get-ChildItem -LiteralPath $resolvedTemporary -Directory -Force)
            if ($unexpectedDirectories.Count -ne 0) {
                throw 'refusing to clean a non-flat temporary reproduction path'
            }
            foreach ($temporaryFile in @(Get-ChildItem -LiteralPath $resolvedTemporary -File -Force)) {
                Remove-Item -LiteralPath $temporaryFile.FullName -Force
            }
            Remove-Item -LiteralPath $resolvedTemporary -Force
        }
    }

    Write-Detail "[check_wt_history_patch_3_1_reproducibility] OK - adjacent 12-to-16 boundary, exact current guard, Versus exclusion, independent oracle, completeness ledger, and catalog reproduced from $source" 'Green'
    exit 0
} catch {
    Write-Host "[check_wt_history_patch_3_1_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
