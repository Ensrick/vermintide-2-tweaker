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
        # Absence is handled below; the pinned evidence gate remains available.
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
        $extractor = 'c0a2775e5c3f52e9b11ca701e7ed9e916287cc78b39e1c5edc5caf52d6468e46'
        $generator = 'bb2e366992226a9ffb1acc223dee99fa944264d02e3ad96be410e8d660a6f523'
        $sourceCatalog = '4d346e1b5f0f79f8ddc06e9d58d2e8345257ed24d30ac02fb53373ea96d34dd4'
        $generatedCatalog = '95cc058d5fc32751859f1c4fe913a93d7d31553dea91edd834d700bcafb9ae43'
        $oracleExtractor = '6c8ae7ef0dee07e93632e20427600cab15046aadcb0ad4bbe082d15a95ea5bdf'
        $oracleSpec = 'df8976bdfbd6bf182fae88dededd00554a9352eabf2fc9413a59184d846bdc1d'
        $oracleRoutes = '07e2dd48b667b1c26550299ca60d02658aebc29804bf8caa3a57081353af99c4'
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

    $source = Find-SourceRepo $root $SourceRepo
    if (-not $source) {
        if ($RequireSource) {
            throw 'Vermintide-2-Source-Code checkout is required but was not found'
        }
        Write-Detail '[check_wt_history_reproducibility] source checkout absent; exact regeneration SKIP (pinned evidence/output OK)' 'Yellow'
        exit 0
    }

    $currentRevision = 'c5e4968b1fbb00c49884e56d640ef990a9c04dd0'
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
