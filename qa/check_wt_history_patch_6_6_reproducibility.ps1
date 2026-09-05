# Blocking offline provenance/reproduction gate for issue #1436's Patch 6.6
# Deepwood Staff slice. The checked-in adjacent diff selects the three official
# Chaos Warrior with Shield leaves; a second pass rehydrates those paths against
# the current source anchor. All generated output is written outside the repo.

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

function Find-SourceRepo([string]$Root, [string]$Explicit) {
    $candidates = @()
    if ($Explicit) { $candidates += $Explicit }
    if ($env:VT2_SOURCE_REPO) { $candidates += $env:VT2_SOURCE_REPO }
    $candidates += (Join-Path (Split-Path $Root -Parent) 'Vermintide-2-Source-Code')

    try {
        $common = (& git -C $Root rev-parse --git-common-dir 2>$null)
        if ($LASTEXITCODE -eq 0 -and $common) {
            if (-not [IO.Path]::IsPathRooted($common)) {
                $common = Join-Path $Root $common
            }
            $mainRoot = Split-Path ([IO.Path]::GetFullPath($common)) -Parent
            $candidates += (Join-Path (Split-Path $mainRoot -Parent) 'Vermintide-2-Source-Code')
        }
    } catch {
        # Source absence is handled below; pinned artifacts remain enforceable.
    }

    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate '.git'))) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $toolRoot = Join-Path $root 'tools\weapon-history'
    $evidenceRoot = Join-Path $toolRoot 'evidence\patch_6_6'
    $extractor = Join-Path $toolRoot 'extract_weapon_history.lua'
    $oracleExtractor = Join-Path $toolRoot 'source_oracle\extract_weapon_history_oracle.lua'
    $generator = Join-Path $toolRoot 'generate_patch_6_6_history.lua'
    $sourceCatalog = Join-Path $evidenceRoot '_wt_history_6_6_source_catalog.lua'
    $adjacentEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_6_5_4_to_6_6_0_generated.lua'
    $rehydratedEvidence = Join-Path $evidenceRoot '_wt_history_snapshot_6_5_4_rehydrated_generated.lua'
    $generatedCatalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_6_catalog.lua'
    $devCatalog = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_6_6_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pinned = [ordered]@{
        $extractor = '76e6e9b05d1945c94022e94ed6190b079b5320dae7a5f0797000cd5a098e338f'
        $oracleExtractor = '3f4c3f2d630c261a3b0037a42e41ebafd560d8050afd49bc67c67259b406f311'
        $generator = '13925ee8388e5e199b95f31a74c04380f0b66e7632301423257d5943b8303cdc'
        $sourceCatalog = 'd8dab8d2f3056dc45a5331eb8628e80af7b59413e2c6e8083f94873839514e73'
        $adjacentEvidence = 'c3e97e994ac6cc9da1862fdcd1d494fbdc924daddb039c15d03a9379d5e59121'
        $rehydratedEvidence = 'b06c8114fad35b8d318f42338cd639aaa5d131185200f1bd1145bf89f80145af'
        $generatedCatalog = 'ccb88625c8bdf63a00913b7c915d149365e9524511599b405e80ed7ed2316927'
        $devCatalog = 'ccb88625c8bdf63a00913b7c915d149365e9524511599b405e80ed7ed2316927'
    }
    foreach ($entry in $pinned.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Key -PathType Leaf)) {
            throw "missing Patch 6.6 provenance artifact: $($entry.Key)"
        }
        $actual = Get-Sha256 $entry.Key
        if ($actual -cne $entry.Value) {
            throw "Patch 6.6 pinned hash drift: $($entry.Key) expected=$($entry.Value) actual=$actual"
        }
    }

    $sourceText = [IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8)
    $artifactMatches = [regex]::Matches($sourceText,
        '(?m)^\s*(_wt_history_snapshot_[A-Za-z0-9_]+)\s*=\s*"([0-9a-f]{64})"')
    if ($artifactMatches.Count -ne 2) {
        throw "Patch 6.6 evidence ledger must contain exactly 2 artifacts; got $($artifactMatches.Count)"
    }
    foreach ($match in $artifactMatches) {
        $evidencePath = Join-Path $evidenceRoot ($match.Groups[1].Value + '.lua')
        if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
            throw "Patch 6.6 ledger artifact is missing: $evidencePath"
        }
        $actual = Get-Sha256 $evidencePath
        if ($actual -cne $match.Groups[2].Value) {
            throw "Patch 6.6 evidence ledger drift: $evidencePath expected=$($match.Groups[2].Value) actual=$actual"
        }
    }

    $expectedEvidence = @(
        '_wt_history_6_6_source_catalog.lua',
        '_wt_history_snapshot_6_5_4_rehydrated_generated.lua',
        '_wt_history_snapshot_6_5_4_to_6_6_0_generated.lua'
    ) | Sort-Object
    $actualEvidence = @(Get-ChildItem -LiteralPath $evidenceRoot -File -Filter '*.lua' |
        ForEach-Object Name | Sort-Object)
    if (($actualEvidence -join "`n") -cne ($expectedEvidence -join "`n")) {
        throw 'Patch 6.6 evidence directory contains an unledgered or missing Lua artifact'
    }

    $source = Find-SourceRepo $root $SourceRepo
    if (-not $source) {
        if ($RequireSource) {
            throw 'Vermintide-2-Source-Code checkout is required but was not found'
        }
        Write-Detail '[check_wt_history_patch_6_6_reproducibility] source checkout absent; exact regeneration SKIP (pinned evidence/output OK)' 'Yellow'
        exit 0
    }

    $historicalRevision = '5a74a378502353b075cbe0c3abe37da07f1d9bc9'
    $postRevision = '877aa9b2720d297e0594f7039773eca610324f5b'
    $currentRevision = 'c5e4968b1fbb00c49884e56d640ef990a9c04dd0'
    $sourcePaths = @(
        'scripts/settings/equipment/weapon_templates/staff_life.lua',
        'scripts/settings/dlcs/woods/woods_equipment_settings.lua'
    )

    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $temporaryRoot = Join-Path $tempBase ('wt1436-p66-' + [guid]::NewGuid().ToString('N'))
    if (-not $temporaryRoot.StartsWith($tempBase, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'unsafe temporary reproduction path'
    }
    New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
    try {
        $extractorSelfTest = @(& $lua $extractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.6 primary numeric self-test failed: $($extractorSelfTest -join ' ')"
        }
        $oracleSelfTest = @(& $lua $oracleExtractor --self-test 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.6 oracle numeric self-test failed: $($oracleSelfTest -join ' ')"
        }

        $primaryAdjacent = Join-Path $temporaryRoot 'primary-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments (@($historicalRevision, $postRevision) + $sourcePaths) `
            -WorkingDirectory $source -OutputPath $primaryAdjacent
        if ((Get-Sha256 $primaryAdjacent) -cne (Get-Sha256 $adjacentEvidence)) {
            throw 'Patch 6.6 adjacent source evidence is not byte-reproducible'
        }

        $oracleAdjacent = Join-Path $temporaryRoot 'oracle-adjacent.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments (@('--source-repo', $source, $historicalRevision,
                $postRevision) + $sourcePaths) `
            -WorkingDirectory $root -OutputPath $oracleAdjacent
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $adjacentEvidence $oracleAdjacent 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.6 independent adjacent evidence differs: $($comparison -join ' ')"
        }

        $primaryRehydrated = Join-Path $temporaryRoot 'primary-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $extractor `
            -Arguments @('--rehydrate-snapshot', $historicalRevision,
                $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $source -OutputPath $primaryRehydrated
        if ((Get-Sha256 $primaryRehydrated) -cne (Get-Sha256 $rehydratedEvidence)) {
            throw 'Patch 6.6 current-anchor evidence is not byte-reproducible'
        }

        $oracleRehydrated = Join-Path $temporaryRoot 'oracle-rehydrated.lua'
        Invoke-LuaGeneratedFile -Lua $lua -Script $oracleExtractor `
            -Arguments @('--source-repo', $source, '--rehydrate-snapshot',
                $historicalRevision, $currentRevision, $adjacentEvidence) `
            -WorkingDirectory $root -OutputPath $oracleRehydrated
        $comparison = @(& $lua $oracleExtractor --compare-evidence `
            $rehydratedEvidence $oracleRehydrated 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.6 independent current-anchor evidence differs: $($comparison -join ' ')"
        }

        $temporaryCatalog = Join-Path $temporaryRoot '_wt_history_6_6_catalog.lua'
        $generatorOutput = @(& $lua $generator $source $evidenceRoot $temporaryCatalog 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Patch 6.6 catalog generator failed (exit $LASTEXITCODE): $($generatorOutput -join ' ')"
        }
        if ((Get-Sha256 $temporaryCatalog) -cne (Get-Sha256 $generatedCatalog)) {
            throw 'Patch 6.6 generated catalog is not byte-reproducible'
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

    Write-Detail "[check_wt_history_patch_6_6_reproducibility] OK - adjacent boundary, current guard, independent oracle, and catalog reproduced from $source" 'Green'
    exit 0
} catch {
    Write-Host "[check_wt_history_patch_6_6_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
