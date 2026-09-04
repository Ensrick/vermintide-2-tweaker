# Blocking offline provenance/reproduction gate for issue #1436's Patch 2.0.9.1
# Kruber Halberd slice. The adjacent diff selects the complete missing-overhead
# chain boundary and a second pass rehydrates only those leaves against current.

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
    $evidenceRoot = Join-Path $toolRoot 'evidence\patch_2_0_9_1'
    $extractor = Join-Path $toolRoot 'extract_weapon_history.lua'
    $oracleExtractor = Join-Path $toolRoot 'source_oracle\extract_weapon_history_oracle.lua'
    $generator = Join-Path $toolRoot 'generate_patch_2_0_9_1_history.lua'
    $sourceCatalog = Join-Path $evidenceRoot '_wt_history_2_0_9_1_source_catalog.lua'
    $adjacentEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_2_0_9_to_2_0_9_1_generated.lua'
    $rehydratedEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_2_0_9_rehydrated_generated.lua'
    $generatedCatalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_2_0_9_1_catalog.lua'
    $devCatalog = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_2_0_9_1_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pinned = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracleExtractor = '767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $generator = '36b36ba3ef5c6ed84190c22541f9f3c06e5c245c0b9b2d8e1ffa33dee5fb7da1'
        $sourceCatalog = '34e8a179935985c91bb82fb213811d94b04fe4e90ab94907d4f975961619574b'
        $adjacentEvidence = '845a4d0af283c61cfa1c63cb923c94b07d36c7c4f48be672ecaaab2701bc909c'
        $rehydratedEvidence = '53a9ade7bac742fbb2f81113bf6a4657456068f5c75588d038c03f46c4f9a28d'
        $generatedCatalog = '188e83aa343edbd7eaefc3ee262665d07937588b3ed8c74293a461c938a055d9'
        $devCatalog = '188e83aa343edbd7eaefc3ee262665d07937588b3ed8c74293a461c938a055d9'
    }
    foreach ($entry in $pinned.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) {
            throw "missing Patch 2.0.9.1 provenance artifact: $($entry.Key)"
        }
        $actual = Get-Sha256 $entry.Key
        if ($actual -cne $entry.Value) {
            throw "Patch 2.0.9.1 pinned hash drift: $($entry.Key) expected=$($entry.Value) actual=$actual"
        }
    }

    $sourceText = [IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8)
    if ($sourceText.IndexOf($anchor.ContentRevision,
            [StringComparison]::Ordinal) -lt 0) {
        throw 'Patch 2.0.9.1 source catalog does not consume the central current-source anchor'
    }
    $artifactMatches = [regex]::Matches($sourceText,
        '(?m)^\s*(_wt_history_snapshot_[A-Za-z0-9_]+)\s*=\s*"([0-9a-f]{64})"')
    if ($artifactMatches.Count -ne 2) {
        throw "Patch 2.0.9.1 evidence ledger must contain exactly 2 artifacts; got $($artifactMatches.Count)"
    }
    foreach ($match in $artifactMatches) {
        $evidencePath = Join-Path $evidenceRoot ($match.Groups[1].Value + '.lua')
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw "Patch 2.0.9.1 ledger artifact is missing: $evidencePath"
        }
        $actual = Get-Sha256 $evidencePath
        if ($actual -cne $match.Groups[2].Value) {
            throw "Patch 2.0.9.1 evidence ledger drift: $evidencePath expected=$($match.Groups[2].Value) actual=$actual"
        }
    }

    $expectedEvidence = @(
        '_wt_history_2_0_9_1_source_catalog.lua',
        '_wt_history_snapshot_2_0_9_rehydrated_generated.lua',
        '_wt_history_snapshot_2_0_9_to_2_0_9_1_generated.lua'
    ) | Sort-Object
    $actualEvidence = @(Get-ChildItem -LiteralPath $evidenceRoot -File -Filter '*.lua' |
        ForEach-Object Name | Sort-Object)
    if (($actualEvidence -join [Environment]::NewLine) -cne
            ($expectedEvidence -join [Environment]::NewLine)) {
        throw 'Patch 2.0.9.1 evidence directory contains an unledgered or missing Lua artifact'
    }

    $historicalRevision = '6d41bab482ac64ebebc5c8bba2c3a47954952af9'
    $postRevision = '90c7c21adb7aa2b7de5fcdca5094727895fbeb1a'
    $currentRevision = $anchor.ContentRevision
    $sourcePath = 'scripts/settings/equipment/weapon_templates/halberds.lua'
    $sourceRequirements = @(
        [pscustomobject]@{ Revision = $historicalRevision; Path = $sourcePath; Blob = '220f6834ce7e54eaa3264792786fcdf4bb0c4198' },
        [pscustomobject]@{ Revision = $postRevision; Path = $sourcePath; Blob = 'b890247081ef2a8a61579fe5f6c85e68cc0d6563' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $sourcePath; Blob = '68256d553f364ca97a7dabccb617020afe5a0064' }
    )
    $sourceSelection = Find-WtHistorySourceRepo -Root $root -Explicit $SourceRepo -Requirements $sourceRequirements
    $source = $sourceSelection.Path
    if (-not $source) {
        $selectionDetail = if ($sourceSelection.Rejections.Count -gt 0) {
            $sourceSelection.Rejections -join '; '
        }
        else { 'no source checkout candidate was found' }
        if ($RequireSource) {
            throw "Vermintide-2-Source-Code checkout is required but unavailable or incomplete: $selectionDetail"
        }
        Write-Host "[check_wt_history_patch_2_0_9_1_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned evidence/output OK): $selectionDetail" -ForegroundColor Yellow
        exit 0
    }

    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $tempBase ('wt1436-p2091-' + [guid]::NewGuid().ToString('N'))
    if (-not $temporaryRoot.StartsWith($tempBase,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw 'unsafe temporary reproduction path'
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        $extractorSelfTest = @(& $lua $extractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 2.0.9.1 primary numeric self-test failed: $($extractorSelfTest -join ' ')"
        }
        $oracleSelfTest = @(& $lua $oracleExtractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 2.0.9.1 oracle self-test failed: $($oracleSelfTest -join ' ')"
        }

        $primaryAdjacent = Join-Path $temporaryRoot 'primary-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor -Arguments @($historicalRevision, $postRevision, $sourcePath) -WorkingDirectory $source -OutputPath $primaryAdjacent
        if ((Get-Sha256 $primaryAdjacent) -cne (Get-Sha256 $adjacentEvidence)) {
            throw 'Patch 2.0.9.1 adjacent source evidence is not byte-reproducible'
        }

        $oracleAdjacent = Join-Path $temporaryRoot 'oracle-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor -Arguments @('--source-repo', $source, $historicalRevision, $postRevision, $sourcePath) -WorkingDirectory $root -OutputPath $oracleAdjacent
        $comparison = @(& $lua $oracleExtractor --compare-evidence $adjacentEvidence $oracleAdjacent 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 2.0.9.1 independent adjacent evidence differs: $($comparison -join ' ')"
        }

        $primaryRehydrated = Join-Path $temporaryRoot 'primary-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor -Arguments @('--rehydrate-snapshot', $historicalRevision, $currentRevision, $adjacentEvidence) -WorkingDirectory $source -OutputPath $primaryRehydrated
        if ((Get-Sha256 $primaryRehydrated) -cne
                (Get-Sha256 $rehydratedEvidence)) {
            throw 'Patch 2.0.9.1 current-anchor evidence is not byte-reproducible'
        }

        $oracleRehydrated = Join-Path $temporaryRoot 'oracle-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor -Arguments @('--source-repo', $source, '--rehydrate-snapshot', $historicalRevision, $currentRevision, $adjacentEvidence) -WorkingDirectory $root -OutputPath $oracleRehydrated
        $comparison = @(& $lua $oracleExtractor --compare-evidence $rehydratedEvidence $oracleRehydrated 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 2.0.9.1 independent current-anchor evidence differs: $($comparison -join ' ')"
        }

        $temporaryCatalog = Join-Path $temporaryRoot '_wt_history_2_0_9_1_catalog.lua'
        $generatorOutput = @(& $lua $generator $source $evidenceRoot $temporaryCatalog 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 2.0.9.1 catalog generator failed (exit $LASTEXITCODE): $($generatorOutput -join ' ')"
        }
        if ((Get-Sha256 $temporaryCatalog) -cne
                (Get-Sha256 $generatedCatalog)) {
            throw 'Patch 2.0.9.1 generated catalog is not byte-reproducible'
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
            if (-not $resolvedTemporary.StartsWith($tempBase,
                    [StringComparison]::OrdinalIgnoreCase)) {
                throw 'refusing to remove unsafe temporary reproduction path'
            }
            $unexpectedDirectories = @(
                Get-ChildItem -LiteralPath $resolvedTemporary -Directory -Force)
            if ($unexpectedDirectories.Count -ne 0) {
                throw 'refusing to clean a non-flat temporary reproduction path'
            }
            foreach ($temporaryFile in @(
                    Get-ChildItem -LiteralPath $resolvedTemporary -File -Force)) {
                Remove-Item -LiteralPath $temporaryFile.FullName -Force
            }
            Remove-Item -LiteralPath $resolvedTemporary -Force
        }
    }

    Write-Detail "[check_wt_history_patch_2_0_9_1_reproducibility] OK - exact 20-leaf Halberd chain, current guards, independent oracle, and catalog reproduced from $source" 'Green'
    exit 0
}
catch {
    Write-Host "[check_wt_history_patch_2_0_9_1_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
