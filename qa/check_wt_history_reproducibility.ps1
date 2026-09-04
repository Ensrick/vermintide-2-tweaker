# Blocking offline provenance/reproduction gate for Tweaker: Weapons #1436.
# It never writes inside the repository. With the optional decompiled source
# checkout it regenerates to a temporary file and requires byte-exact output.

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
    $evidenceRoot = Join-Path $toolRoot 'evidence\patch_5_2'
    $extractor = Join-Path $toolRoot 'extract_weapon_history.lua'
    $generator = Join-Path $toolRoot 'generate_patch_5_2_history.lua'
    $oracleRoot = Join-Path $toolRoot 'source_oracle'
    $oracleExtractor = Join-Path $oracleRoot 'extract_weapon_history_oracle.lua'
    $oracleSpec = Join-Path $oracleRoot 'patch_5_2_source_spec.lua'
    $oracleRoutes = Join-Path $oracleRoot 'patch_5_2_routes_oracle.lua'
    $sourceCatalog = Join-Path $evidenceRoot '_wt_history_5_2_source_catalog.lua'
    $generatedCatalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_5_2_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pinned = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $generator = '8d5a643fce288e5b7be0ef0518796d200bfdb0ebab969862019abbbbb71420dd'
        $sourceCatalog = 'ba5c9c7f68f45890fc43849f5abedbc14d31f533a0c1c82edfffe9b646bb1456'
        $generatedCatalog = '041d02125a8e05a3347cc2c1640d092f1a77f75502ae19c57a47bffa41d0ce10'
        $oracleExtractor = '767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $oracleSpec = 'd5e32fde9031772dcd5ee8e380fe0b949535c60774d91e450aad598a04fa2dee'
        $oracleRoutes = 'aae106b4c24bf5e865ac614ae3cad9d4821828b5a7ffab4ee118f707463eebe8'
    }
    foreach ($entry in $pinned.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) {
            throw "missing #1436 provenance artifact: $($entry.Key)"
        }
        $actual = Get-Sha256 $entry.Key
        if ($actual -cne $entry.Value) {
            throw "#1436 pinned hash drift: $($entry.Key) expected=$($entry.Value) actual=$actual"
        }
    }

    $sourceText = [IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8)
    if ($sourceText.IndexOf($anchor.ContentRevision,
            [StringComparison]::Ordinal) -lt 0) {
        throw '#1436 source catalog does not consume the central current-source anchor'
    }
    $artifactMatches = [regex]::Matches($sourceText,
        '(?m)^\s*(_wt_history_(?:profiles|snapshot)_[A-Za-z0-9_]+)\s*=\s*"([0-9a-f]{64})"')
    if ($artifactMatches.Count -ne 9) {
        throw "#1436 evidence ledger must contain exactly 9 artifacts; got $($artifactMatches.Count)"
    }
    $expectedEvidence = @('_wt_history_5_2_source_catalog.lua')
    foreach ($match in $artifactMatches) {
        $name = $match.Groups[1].Value + '.lua'
        $path = Join-Path $evidenceRoot $name
        $expectedEvidence += $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "missing #1436 evidence file: $name"
        }
        $actual = Get-Sha256 $path
        if ($actual -cne $match.Groups[2].Value) {
            throw "#1436 evidence hash drift: $name expected=$($match.Groups[2].Value) actual=$actual"
        }
    }
    $actualEvidence = @(Get-ChildItem -LiteralPath $evidenceRoot -File -Filter '*.lua' |
        ForEach-Object Name | Sort-Object)
    $expectedEvidence = @($expectedEvidence | Sort-Object)
    if (($actualEvidence -join "`n") -cne ($expectedEvidence -join "`n")) {
        throw '#1436 evidence directory contains an unledgered or missing Lua artifact'
    }

    $sourceRequirements = @(Read-WtHistorySourceBlobLedger -Path $oracleRoutes)
    if ($sourceRequirements.Count -ne 63) {
        throw "#1436 Patch 5.2 source-object ledger must contain 63 rows; got $($sourceRequirements.Count)"
    }
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
        Write-Host "[check_wt_history_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned evidence/output OK): $selectionDetail" -ForegroundColor Yellow
        exit 0
    }

    $currentRevision = $anchor.ContentRevision

    # Issue #1529 is provenance-only: every source path referenced by any of
    # the thirteen history families must resolve to the same Git blob at the
    # retired 6.12.0 anchor and the canonical 6.12.1 anchor. Derive the scope
    # from the checked-in source catalogs/specifications so a newly referenced
    # input cannot silently escape this transition proof.
    $previousContentRevision = '038498af2b565bcb10bf5ed225638293a7640c83'
    $transitionInputs = @(
        Get-ChildItem (Join-Path $toolRoot 'evidence') -Recurse -File `
            -Filter '*source_catalog.lua'
        Get-ChildItem $oracleRoot -File -Filter '*source_spec.lua'
    )
    $transitionPaths = New-Object 'System.Collections.Generic.HashSet[string]' `
        ([StringComparer]::Ordinal)
    foreach ($transitionInput in $transitionInputs) {
        $transitionText = [IO.File]::ReadAllText($transitionInput.FullName,
            [Text.Encoding]::UTF8)
        foreach ($match in [regex]::Matches($transitionText,
                '"(scripts/[A-Za-z0-9_./-]+\.lua)"')) {
            $null = $transitionPaths.Add($match.Groups[1].Value)
        }
    }
    if ($transitionPaths.Count -ne 36) {
        throw "#1529 current-source transition scope drift: expected=36 actual=$($transitionPaths.Count)"
    }
    foreach ($sourcePath in @($transitionPaths | Sort-Object)) {
        $before = Invoke-WtHistoryReadOnlyGit -Repository $source -Arguments @(
            'rev-parse', '--verify', "${previousContentRevision}:$sourcePath")
        $after = Invoke-WtHistoryReadOnlyGit -Repository $source -Arguments @(
            'rev-parse', '--verify', "$currentRevision`:$sourcePath")
        $beforeBlobs = @($before.Output | Where-Object { $_ -match '^[0-9a-f]{40}$' })
        $afterBlobs = @($after.Output | Where-Object { $_ -match '^[0-9a-f]{40}$' })
        if ($before.ExitCode -ne 0 -or $after.ExitCode -ne 0 -or
            $beforeBlobs.Count -ne 1 -or $afterBlobs.Count -ne 1) {
            throw "#1529 source transition object is unavailable: $sourcePath"
        }
        if ($beforeBlobs[0] -cne $afterBlobs[0]) {
            throw "#1529 gameplay source blob changed across 6.12.0/6.12.1: $sourcePath"
        }
    }
    $rehydration = @(
        [pscustomobject]@{ Name = '_wt_history_snapshot_5_1_1_part_1_generated.lua'; Mode = '--rehydrate-snapshot'; Revision = '8224b4436e20905a6ba463cb28fa2d7771bb2330' },
        [pscustomobject]@{ Name = '_wt_history_snapshot_5_1_1_part_2_generated.lua'; Mode = '--rehydrate-snapshot'; Revision = '8224b4436e20905a6ba463cb28fa2d7771bb2330' },
        [pscustomobject]@{ Name = '_wt_history_snapshot_5_2_0_part_1_generated.lua'; Mode = '--rehydrate-snapshot'; Revision = '4f496970e2e7514bef7d612ab91331aa065d5e52' },
        [pscustomobject]@{ Name = '_wt_history_snapshot_5_2_0_part_2_generated.lua'; Mode = '--rehydrate-snapshot'; Revision = '4f496970e2e7514bef7d612ab91331aa065d5e52' },
        [pscustomobject]@{ Name = '_wt_history_snapshot_5_2_3_generated.lua'; Mode = '--rehydrate-snapshot'; Revision = 'cdc0a86e24e017119e6d6998870bf76f6e76e868' },
        [pscustomobject]@{ Name = '_wt_history_profiles_5_1_1_generated.lua'; Mode = '--rehydrate-profiles'; Revision = '8224b4436e20905a6ba463cb28fa2d7771bb2330' },
        [pscustomobject]@{ Name = '_wt_history_profiles_5_1_1_dlc_generated.lua'; Mode = '--rehydrate-profiles'; Revision = '8224b4436e20905a6ba463cb28fa2d7771bb2330' },
        [pscustomobject]@{ Name = '_wt_history_profiles_5_2_0_generated.lua'; Mode = '--rehydrate-profiles'; Revision = '4f496970e2e7514bef7d612ab91331aa065d5e52' },
        [pscustomobject]@{ Name = '_wt_history_profiles_5_2_0_dlc_generated.lua'; Mode = '--rehydrate-profiles'; Revision = '4f496970e2e7514bef7d612ab91331aa065d5e52' }
    )
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $tempBase ('wt1436-' + [guid]::NewGuid().ToString('N'))
    if (-not $temporaryRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'unsafe temporary reproduction path'
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    # Keep every generated artifact in one private flat directory. Cleanup can
    # then remove each known file individually; this gate never needs a
    # recursive filesystem delete.
    $temporaryEvidence = $temporaryRoot
    try {
        $extractorSelfTest = @(& $lua $extractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "#1436 evidence numeric self-test failed: $($extractorSelfTest -join ' ')"
        }
        $oracleSelfTest = @(& $lua $oracleExtractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "#1436 oracle numeric self-test failed: $($oracleSelfTest -join ' ')"
        }

        Copy-Item -LiteralPath $sourceCatalog -Destination $temporaryEvidence
        foreach ($row in $rehydration) {
            $checkedIn = Join-Path $evidenceRoot $row.Name
            $regenerated = Join-Path $temporaryEvidence $row.Name
            Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
                -Arguments @($row.Mode, $row.Revision, $currentRevision, $checkedIn) `
                -WorkingDirectory $source -OutputPath $regenerated
            $expectedHash = Get-Sha256 $checkedIn
            $actualHash = Get-Sha256 $regenerated
            if ($actualHash -cne $expectedHash) {
                throw "#1436 source evidence is not reproducible: $($row.Name) checked-in=$expectedHash regenerated=$actualHash"
            }

            $oracleRegenerated = Join-Path $temporaryRoot ('oracle-' + $row.Name)
            Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
                -Arguments @('--source-repo', $source, $row.Mode, $row.Revision,
                    $currentRevision, $checkedIn) `
                -WorkingDirectory $root -OutputPath $oracleRegenerated
            $comparison = @(& $lua $oracleExtractor --compare-evidence `
                $checkedIn $oracleRegenerated 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "#1436 independent source evidence differs: $($row.Name) $($comparison -join ' ')"
            }
        }

        $temporaryRoutes = Join-Path $temporaryRoot 'patch_5_2_routes_oracle.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, '--routes', $currentRevision, $oracleSpec) `
            -WorkingDirectory $root -OutputPath $temporaryRoutes
        $expectedRouteHash = Get-Sha256 $oracleRoutes
        $actualRouteHash = Get-Sha256 $temporaryRoutes
        if ($actualRouteHash -cne $expectedRouteHash) {
            throw "#1436 source route oracle is not reproducible: checked-in=$expectedRouteHash regenerated=$actualRouteHash"
        }

        $temporaryCatalog = Join-Path $temporaryRoot '_wt_history_5_2_catalog.lua'
        $generatorOutput = @(& $lua $generator $source $temporaryEvidence $temporaryCatalog 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "#1436 catalog generator failed (exit $LASTEXITCODE): $($generatorOutput -join ' ')"
        }
        $expectedHash = Get-Sha256 $generatedCatalog
        $actualHash = Get-Sha256 $temporaryCatalog
        if ($actualHash -cne $expectedHash) {
            throw "#1436 generated catalog is not reproducible: checked-in=$expectedHash regenerated=$actualHash"
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            $resolvedTemporary = [IO.Path]::GetFullPath($temporaryRoot)
            if (-not $resolvedTemporary.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'refusing to remove unsafe temporary reproduction path'
            }
            $unexpectedDirectories = @(Get-ChildItem -LiteralPath $resolvedTemporary `
                -Directory -Force)
            if ($unexpectedDirectories.Count -ne 0) {
                throw 'refusing to clean a non-flat temporary reproduction path'
            }
            foreach ($temporaryFile in @(Get-ChildItem -LiteralPath $resolvedTemporary `
                    -File -Force)) {
                Remove-Item -LiteralPath $temporaryFile.FullName -Force
            }
            Remove-Item -LiteralPath $resolvedTemporary -Force
        }
    }

    Write-Detail "[check_wt_history_reproducibility] OK - exact evidence, source oracle, and catalog reproduced from $source" 'Green'
    exit 0
} catch {
    Write-Host "[check_wt_history_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
