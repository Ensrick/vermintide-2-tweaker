# Blocking offline provenance/reproduction gate for issue #1436's bounded
# Patch 3.1 Blunderbuss and Tuskgor Spear slices. Each checked-in adjacent diff
# selects one official boundary operation; a second pass rehydrates that path
# against the current source anchor. Output is written outside the repository.

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
    $tuskgorAdjacentEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_pre_3_1_tuskgor_to_3_1_generated.lua'
    $tuskgorRehydratedEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_pre_3_1_tuskgor_rehydrated_generated.lua'
    $generatedCatalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_3_1_catalog.lua'
    $devCatalog = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_3_1_catalog.lua'
    $ledger = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_completeness_ledger.lua'
    $devLedger = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_completeness_ledger.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pinned = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracleExtractor = '767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $generator = '2c43825624591c3f22d2827ec98dd594c2113e2088c7d929b8101321469c4b7b'
        $sourceCatalog = '722a152e021b2e4d9953b31a959894dd9b990f66c630e0f5db1117301c5a91cd'
        $adjacentEvidence = '63047d1c57551eca5cb46763d91ada62e9ae2d0a945232e591c7e4500dde5d76'
        $rehydratedEvidence = '7563d45d92bafbcc8be35cc8b5130ed59a8520b8fc4a7aa1e9f372aac9020c14'
        $tuskgorAdjacentEvidence = '1670075b4ba9072a0f1226152575d1c598d7efb572929680edc3e8b8271c6c95'
        $tuskgorRehydratedEvidence = '6b5030dc1316a6080f1ae579d3beed3cff637d64d621d8d10701c6add6f9f5d3'
        $generatedCatalog = '60539707496e9ecb1e77aa3d6b4168aca96d271c2ff92a7267d0637d544018ad'
        $devCatalog = '60539707496e9ecb1e77aa3d6b4168aca96d271c2ff92a7267d0637d544018ad'
        $ledger = '8bdd058cf5cda3b32f4273dbe0f4bf6dcaec887a02dcb49023845d38a10481ad'
        $devLedger = '8bdd058cf5cda3b32f4273dbe0f4bf6dcaec887a02dcb49023845d38a10481ad'
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
        'two_handed_heavy_spears_template',
        'scripts/settings/equipment/weapon_templates/2h_heavy_spears.lua',
        'P310-TUSKGOR-BLOCK-COST',
        'https://www.vermintide.com/news/patch-31'
    )) {
        if ($sourceText.IndexOf($requiredSourceLiteral,
                [StringComparison]::Ordinal) -lt 0) {
            throw "Patch 3.1 source catalog is missing bounded-scope evidence: $requiredSourceLiteral"
        }
    }
    $artifactMatches = [regex]::Matches($sourceText,
        '(?m)^\s*(_wt_history_snapshot_[A-Za-z0-9_]+)\s*=\s*"([0-9a-f]{64})"')
    if ($artifactMatches.Count -ne 4) {
        throw "Patch 3.1 evidence ledger must contain exactly 4 artifacts; got $($artifactMatches.Count)"
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
        '_wt_history_snapshot_pre_3_1_to_3_1_generated.lua',
        '_wt_history_snapshot_pre_3_1_tuskgor_rehydrated_generated.lua',
        '_wt_history_snapshot_pre_3_1_tuskgor_to_3_1_generated.lua'
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
    $blunderbussPath = 'scripts/settings/equipment/weapon_templates/blunderbusses.lua'
    $tuskgorPath = 'scripts/settings/equipment/weapon_templates/2h_heavy_spears.lua'
    $sourceRequirements = @(
        [pscustomobject]@{ Revision = $historicalRevision; Path = $blunderbussPath; Blob = 'f8f6ec97a974bd5767c1ccabf9fc593dba785d34' },
        [pscustomobject]@{ Revision = $postRevision; Path = $blunderbussPath; Blob = '5370ab322355f8066377779aed1fed8e00a864ba' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $blunderbussPath; Blob = '87dca4018c18051d653a80b7aff501ed9815a5d0' },
        [pscustomobject]@{ Revision = $historicalRevision; Path = $tuskgorPath; Blob = 'bdd5a9bed6cf3e4a826206318a090cc198ccf7de' },
        [pscustomobject]@{ Revision = $postRevision; Path = $tuskgorPath; Blob = '5b0175fdfb69412fe8daa76180238ca399768b3a' },
        [pscustomobject]@{ Revision = $currentRevision; Path = $tuskgorPath; Blob = '7575b5035a40d9957514667538d253af46e18c9a' }
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
        $reproductionJobs = @(
            [pscustomobject]@{
                Id = 'blunderbuss'
                Path = $blunderbussPath
                Adjacent = $adjacentEvidence
                Rehydrated = $rehydratedEvidence
            },
            [pscustomobject]@{
                Id = 'tuskgor'
                Path = $tuskgorPath
                Adjacent = $tuskgorAdjacentEvidence
                Rehydrated = $tuskgorRehydratedEvidence
            }
        )
        foreach ($job in $reproductionJobs) {
            $primaryAdjacent = Join-Path $temporaryRoot ("primary-$($job.Id)-adjacent.lua")
            Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
                -Arguments @($historicalRevision, $postRevision, $job.Path) `
                -WorkingDirectory $source -OutputPath $primaryAdjacent
            if ((Get-Sha256 $primaryAdjacent) -cne (Get-Sha256 $job.Adjacent)) {
                throw "Patch 3.1 $($job.Id) adjacent source evidence is not byte-reproducible"
            }

            $oracleAdjacent = Join-Path $temporaryRoot ("oracle-$($job.Id)-adjacent.lua")
            Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
                -Arguments @('--source-repo', $source, $historicalRevision,
                    $postRevision, $job.Path) `
                -WorkingDirectory $root -OutputPath $oracleAdjacent
            $comparison = @(& $lua $oracleExtractor --compare-evidence `
                $job.Adjacent $oracleAdjacent 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Patch 3.1 independent $($job.Id) adjacent evidence differs: $($comparison -join ' ')"
            }

            $primaryRehydrated = Join-Path $temporaryRoot ("primary-$($job.Id)-rehydrated.lua")
            Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
                -Arguments @('--rehydrate-snapshot', $historicalRevision,
                    $currentRevision, $job.Adjacent) `
                -WorkingDirectory $source -OutputPath $primaryRehydrated
            if ((Get-Sha256 $primaryRehydrated) -cne (Get-Sha256 $job.Rehydrated)) {
                throw "Patch 3.1 $($job.Id) current-anchor evidence is not byte-reproducible"
            }

            $oracleRehydrated = Join-Path $temporaryRoot ("oracle-$($job.Id)-rehydrated.lua")
            Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
                -Arguments @('--source-repo', $source, '--rehydrate-snapshot',
                    $historicalRevision, $currentRevision, $job.Adjacent) `
                -WorkingDirectory $root -OutputPath $oracleRehydrated
            $comparison = @(& $lua $oracleExtractor --compare-evidence `
                $job.Rehydrated $oracleRehydrated 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Patch 3.1 independent $($job.Id) current-anchor evidence differs: $($comparison -join ' ')"
            }
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

    Write-Detail "[check_wt_history_patch_3_1_reproducibility] OK - bounded 12-to-16 ammunition and 0.25-to-0.5 block-cost boundaries, exact current guards, Versus exclusion, independent oracle, completeness ledger, and catalog reproduced from $source" 'Green'
    exit 0
} catch {
    Write-Host "[check_wt_history_patch_3_1_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
