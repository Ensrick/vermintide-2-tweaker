# check_decomposition_contracts.ps1 -- machine-readable #504 phase census.
#
# This complements check_file_sizes: the size gate knows which files are large,
# while this registry knows which architectural phase owns each entry point and
# which already-extracted owner modules must remain wired. A slice may ratchet a
# ceiling downward; it may never grow the entry or silently delete an owner.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$ManifestPath,
    # Optional comparison point for the per-PR ceiling-debt delta. In GitHub
    # pull-request CI this defaults to origin/$GITHUB_BASE_REF.
    [string]$BaseRef,
    # Deterministic/offline fixture alternative to -BaseRef.
    [string]$BaseManifestPath,
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
if (-not $ManifestPath) { $ManifestPath = Join-Path $PSScriptRoot 'decomposition_contracts.psd1' }

$script:RequiredContractNames = @(
    'event_tweaker',
    'enemy_tweaker',
    'cosmetics_tweaker',
    'weapon_tweaker',
    'weapon_tweaker_dev',
    'career_tweaker_balance',
    'crafting_in_modded_dev',
    'chaos_wastes_tweaker_dev',
    'character_weapon_variants',
    'weapons_of_chaos'
)

function Test-DecompositionContracts {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$RequiredNames
    )

    $failures = @()
    $rows = @()
    $contracts = @($Manifest.Contracts)
    if ($Manifest.Version -ne 1) { $failures += "unsupported manifest Version '$($Manifest.Version)'" }
    if ($contracts.Count -eq 0) { $failures += 'manifest has no Contracts' }

    $seenNames = @{}
    $seenEntries = @{}
    foreach ($contract in $contracts) {
        $name = [string]$contract.Name
        $state = [string]$contract.State
        $entry = ([string]$contract.Entry).Replace('\', '/')
        $ceiling = 0
        [void][int]::TryParse([string]$contract.CeilingLines, [ref]$ceiling)

        if ([string]::IsNullOrWhiteSpace($name)) { $failures += 'contract has blank Name'; continue }
        if ($seenNames.ContainsKey($name)) { $failures += "duplicate contract Name '$name'" } else { $seenNames[$name] = $true }
        if ($state -notin @('complete', 'partial')) { $failures += "$name has invalid State '$state'" }
        if ([string]::IsNullOrWhiteSpace($entry)) { $failures += "$name has blank Entry"; continue }
        if ($entry -match '(^|/)\.\.?(/|$)' -or $entry.StartsWith('/')) { $failures += "$name Entry is not repo-relative: '$entry'"; continue }
        if ($seenEntries.ContainsKey($entry)) { $failures += "duplicate Entry '$entry'" } else { $seenEntries[$entry] = $true }
        if ($ceiling -le 0) { $failures += "$name has invalid CeilingLines '$($contract.CeilingLines)'" }

        $entryPath = Join-Path $Root $entry
        if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) {
            $failures += "$name entry missing: $entry"
            continue
        }
        $lines = (Get-Content -LiteralPath $entryPath | Measure-Object -Line).Lines
        if ($lines -gt $ceiling) { $failures += "$name entry grew: $lines lines > ceiling $ceiling ($entry)" }
        if ($state -eq 'complete' -and $lines -gt 1500) {
            $failures += "$name claims complete but entry remains above the 1500-line target ($lines)"
        }

        $entryDir = Split-Path $entryPath -Parent
        $modules = @($contract.RequiredModules)
        if ($modules.Count -eq 0) { $failures += "$name has no RequiredModules" }
        $moduleSources = @{}
        foreach ($module in $modules) {
            $leaf = [string]$module
            if ($leaf -ne [IO.Path]::GetFileName($leaf) -or -not $leaf.EndsWith('.lua')) {
                $failures += "$name has invalid module leaf '$leaf'"
                continue
            }
            $modulePath = Join-Path $entryDir $leaf
            if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
                $failures += "$name required owner missing: $leaf"
                continue
            }
            $moduleSources[$leaf] = Get-Content -LiteralPath $modulePath -Raw
        }

        # Owners may install bounded child owners. Prove reachability from the
        # entry instead of requiring every owner leaf to appear in the entry
        # text directly. Only sources reached from the entry join the search
        # frontier, so an orphan cannot make itself reachable by naming itself.
        $reachable = @{}
        $frontier = New-Object 'System.Collections.Generic.Queue[string]'
        $frontier.Enqueue((Get-Content -LiteralPath $entryPath -Raw))
        while ($frontier.Count -gt 0) {
            $source = $frontier.Dequeue()
            foreach ($leaf in $moduleSources.Keys) {
                if ($reachable.ContainsKey($leaf)) { continue }
                $stem = [IO.Path]::GetFileNameWithoutExtension($leaf)
                if ($source.Contains($stem)) {
                    $reachable[$leaf] = $true
                    $frontier.Enqueue($moduleSources[$leaf])
                }
            }
        }
        foreach ($leaf in $moduleSources.Keys) {
            if (-not $reachable.ContainsKey($leaf)) {
                $failures += "$name owner not transitively wired from entry: $leaf"
            }
        }
        $rows += [pscustomobject]@{ Name = $name; State = $state; Lines = $lines; Ceiling = $ceiling; Owners = $modules.Count }
    }

    foreach ($required in $RequiredNames) {
        if (-not $seenNames.ContainsKey($required)) { $failures += "required phase missing: $required" }
    }
    return [pscustomobject]@{ Failures = @($failures); Rows = @($rows) }
}

function Compare-DecompositionDebt {
    param(
        [Parameter(Mandatory)]$CurrentManifest,
        [Parameter(Mandatory)]$BaseManifest
    )

    $failures = @()
    $rows = @()
    $currentByName = @{}
    $baseByName = @{}
    $currentSum = 0
    $baseSum = 0

    foreach ($contract in @($CurrentManifest.Contracts)) {
        $name = [string]$contract.Name
        $ceiling = 0
        if ([string]::IsNullOrWhiteSpace($name) -or -not [int]::TryParse([string]$contract.CeilingLines, [ref]$ceiling) -or $ceiling -le 0) {
            continue
        }
        $currentByName[$name] = $ceiling
        $currentSum += $ceiling
    }
    foreach ($contract in @($BaseManifest.Contracts)) {
        $name = [string]$contract.Name
        $ceiling = 0
        if ([string]::IsNullOrWhiteSpace($name) -or -not [int]::TryParse([string]$contract.CeilingLines, [ref]$ceiling) -or $ceiling -le 0) {
            $failures += "base manifest has invalid ceiling for '$name'"
            continue
        }
        $baseByName[$name] = $ceiling
        $baseSum += $ceiling
    }

    foreach ($name in @($baseByName.Keys | Sort-Object)) {
        if (-not $currentByName.ContainsKey($name)) {
            $failures += "ratchet contract removed since base: $name"
            $rows += [pscustomobject]@{ Name = $name; Base = $baseByName[$name]; Current = $null; Delta = $null; Kind = 'removed' }
            continue
        }
        $delta = $currentByName[$name] - $baseByName[$name]
        if ($delta -gt 0) {
            $failures += "ratchet ceiling grew since base: $name $($baseByName[$name]) -> $($currentByName[$name]) (+$delta)"
        }
        $rows += [pscustomobject]@{ Name = $name; Base = $baseByName[$name]; Current = $currentByName[$name]; Delta = $delta; Kind = 'existing' }
    }
    foreach ($name in @($currentByName.Keys | Where-Object { -not $baseByName.ContainsKey($_) } | Sort-Object)) {
        $rows += [pscustomobject]@{ Name = $name; Base = $null; Current = $currentByName[$name]; Delta = $null; Kind = 'added' }
    }

    return [pscustomobject]@{
        Failures = @($failures)
        Rows = @($rows)
        BaseSum = $baseSum
        CurrentSum = $currentSum
        Delta = $currentSum - $baseSum
        Added = @($rows | Where-Object Kind -eq 'added').Count
        Removed = @($rows | Where-Object Kind -eq 'removed').Count
        Regrown = @($rows | Where-Object { $_.Kind -eq 'existing' -and $_.Delta -gt 0 }).Count
    }
}

function Get-RepoRelativePath {
    param([string]$Root, [string]$Path)
    $rootPath = [System.IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootUri = New-Object System.Uri($rootPath)
    $pathUri = New-Object System.Uri($fullPath)
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace('\', '/')
}

function Import-GitDataManifest {
    param([string]$Root, [string]$Ref, [string]$RepoPath)
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $content = @(& git -C $Root show "$Ref`:$RepoPath" 2>&1 | ForEach-Object { $_.ToString() })
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($code -ne 0) {
        throw "cannot read decomposition baseline $Ref`:$RepoPath (git exit $code): $($content -join ' | ')"
    }

    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ("vt2-decomposition-base-" + [guid]::NewGuid().ToString('N') + '.psd1')
    try {
        [System.IO.File]::WriteAllText($temp, ($content -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
        return Import-PowerShellDataFile -LiteralPath $temp
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Invoke-SelfTest {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("vt2-decomposition-contracts-" + [guid]::NewGuid().ToString('N'))
    try {
        $modDir = Join-Path $temp 'demo'
        New-Item -ItemType Directory -Force -Path $modDir | Out-Null
        Set-Content -LiteralPath (Join-Path $modDir 'entry.lua') -Value @('mod:dofile("demo/_owner")', 'return true')
        Set-Content -LiteralPath (Join-Path $modDir '_owner.lua') -Value @('mod:dofile("demo/_child")', 'return {}')
        Set-Content -LiteralPath (Join-Path $modDir '_child.lua') -Value 'return {}'
        Set-Content -LiteralPath (Join-Path $modDir '_orphan.lua') -Value 'return {}'
        $good = @{ Version = 1; Contracts = @(@{
            Name = 'demo'; State = 'complete'; Entry = 'demo/entry.lua'; CeilingLines = 2; RequiredModules = @('_owner.lua', '_child.lua')
        }) }
        $positive = Test-DecompositionContracts $good $temp @('demo')
        if ($positive.Failures.Count -ne 0) { throw "positive fixture failed: $($positive.Failures -join '; ')" }

        $badGrowth = @{ Version = 1; Contracts = @(@{
            Name = 'demo'; State = 'partial'; Entry = 'demo/entry.lua'; CeilingLines = 1; RequiredModules = @('_owner.lua')
        }) }
        $badOwner = @{ Version = 1; Contracts = @(@{
            Name = 'demo'; State = 'partial'; Entry = 'demo/entry.lua'; CeilingLines = 2; RequiredModules = @('_missing.lua')
        }) }
        $badOrphan = @{ Version = 1; Contracts = @(@{
            Name = 'demo'; State = 'partial'; Entry = 'demo/entry.lua'; CeilingLines = 2; RequiredModules = @('_owner.lua', '_orphan.lua')
        }) }
        if ((Test-DecompositionContracts $badGrowth $temp @('demo')).Failures.Count -eq 0) { throw 'planted growth was not detected' }
        if ((Test-DecompositionContracts $badOwner $temp @('demo')).Failures.Count -eq 0) { throw 'planted missing owner was not detected' }
        if ((Test-DecompositionContracts $badOrphan $temp @('demo')).Failures.Count -eq 0) { throw 'planted transitive orphan was not detected' }
        if ((Test-DecompositionContracts $good $temp @('demo', 'missing')).Failures.Count -eq 0) { throw 'planted missing phase was not detected' }

        $baseDebt = @{ Version = 1; Contracts = @(
            @{ Name = 'demo'; CeilingLines = 10 },
            @{ Name = 'other'; CeilingLines = 20 }
        ) }
        $burnDebt = @{ Version = 1; Contracts = @(
            @{ Name = 'demo'; CeilingLines = 8 },
            @{ Name = 'other'; CeilingLines = 20 }
        ) }
        $burn = Compare-DecompositionDebt $burnDebt $baseDebt
        if ($burn.Failures.Count -ne 0 -or $burn.BaseSum -ne 30 -or $burn.CurrentSum -ne 28 -or $burn.Delta -ne -2) {
            throw 'debt burn-down fixture did not report exact -2 ceiling delta'
        }
        $growthDebt = @{ Version = 1; Contracts = @(
            @{ Name = 'demo'; CeilingLines = 11 },
            @{ Name = 'other'; CeilingLines = 20 }
        ) }
        $growth = Compare-DecompositionDebt $growthDebt $baseDebt
        if ($growth.Failures.Count -eq 0 -or $growth.Regrown -ne 1 -or $growth.Delta -ne 1) {
            throw 'planted per-contract ceiling growth was not detected'
        }
        $removedDebt = @{ Version = 1; Contracts = @(@{ Name = 'demo'; CeilingLines = 10 }) }
        if ((Compare-DecompositionDebt $removedDebt $baseDebt).Failures.Count -eq 0) {
            throw 'planted ratchet-contract removal was not detected'
        }
        $expandedDebt = @{ Version = 1; Contracts = @(
            @{ Name = 'demo'; CeilingLines = 10 },
            @{ Name = 'other'; CeilingLines = 20 },
            @{ Name = 'new_inventory'; CeilingLines = 5 }
        ) }
        $expanded = Compare-DecompositionDebt $expandedDebt $baseDebt
        if ($expanded.Failures.Count -ne 0 -or $expanded.Added -ne 1 -or $expanded.Delta -ne 5) {
            throw 'newly inventoried debt was not distinguished from existing-ceiling regrowth'
        }
        if (-not $Quiet) { Write-Host '[check_decomposition_contracts:selftest] OK - current ceilings, owner retention, debt burn, planted regrowth/removal, and inventory-expansion paths verified.' -ForegroundColor Green }
        return 0
    } finally {
        if (Test-Path -LiteralPath $temp) {
            foreach ($file in @(Get-ChildItem -LiteralPath $modDir -File -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $file.FullName -Force
            }
            if (Test-Path -LiteralPath $modDir) { Remove-Item -LiteralPath $modDir -Force }
            Remove-Item -LiteralPath $temp -Force
        }
    }
}

if ($SelfTest) { exit (Invoke-SelfTest) }

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath).Path
    $manifest = Import-PowerShellDataFile -LiteralPath $resolvedManifest
    $result = Test-DecompositionContracts $manifest $root $script:RequiredContractNames
    $debt = $null
    $debtSource = $null
    if (-not $BaseRef -and -not $BaseManifestPath -and $env:GITHUB_EVENT_NAME -eq 'pull_request' -and $env:GITHUB_BASE_REF) {
        $BaseRef = "origin/$($env:GITHUB_BASE_REF)"
    }
    if ($BaseManifestPath) {
        $resolvedBase = (Resolve-Path -LiteralPath $BaseManifestPath).Path
        $baseManifest = Import-PowerShellDataFile -LiteralPath $resolvedBase
        $debtSource = $resolvedBase
        $debt = Compare-DecompositionDebt $manifest $baseManifest
    }
    elseif ($BaseRef) {
        $manifestRepoPath = Get-RepoRelativePath $root $resolvedManifest
        $baseManifest = Import-GitDataManifest $root $BaseRef $manifestRepoPath
        $debtSource = $BaseRef
        $debt = Compare-DecompositionDebt $manifest $baseManifest
    }
    if ($debt) { $result.Failures += @($debt.Failures) }
} catch {
    Write-Host "[check_decomposition_contracts] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

if (-not $Quiet) {
    foreach ($row in $result.Rows) {
        Write-Host ("  {0,-28} {1,-8} entry={2,5}/{3,5} owners={4}" -f $row.Name, $row.State, $row.Lines, $row.Ceiling, $row.Owners) -ForegroundColor DarkGray
    }
}
if ($debt) {
    $status = if ($debt.Regrown -gt 0) {
        'REGROWTH'
    }
    elseif ($debt.Delta -lt 0) {
        'BURN-DOWN'
    }
    elseif ($debt.Delta -gt 0 -and $debt.Added -gt 0) {
        'INVENTORY-EXPANSION'
    }
    else {
        'FLAT'
    }
    $deltaText = if ($debt.Delta -gt 0) { "+$($debt.Delta)" } else { "$($debt.Delta)" }
    Write-Host ("[decomposition-ratchet] base={0} ceiling_sum={1} current={2} delta={3} status={4} regrown={5} added={6} removed={7}" -f $debtSource, $debt.BaseSum, $debt.CurrentSum, $deltaText, $status, $debt.Regrown, $debt.Added, $debt.Removed)
    if (-not $Quiet) {
        foreach ($row in @($debt.Rows | Where-Object { $_.Kind -ne 'existing' -or $_.Delta -ne 0 })) {
            if ($row.Kind -eq 'added') {
                Write-Host ("  + {0}: NEW ceiling {1}" -f $row.Name, $row.Current) -ForegroundColor Yellow
            }
            elseif ($row.Kind -eq 'removed') {
                Write-Host ("  ! {0}: REMOVED (base ceiling {1})" -f $row.Name, $row.Base) -ForegroundColor Red
            }
            else {
                $rowDelta = if ($row.Delta -gt 0) { "+$($row.Delta)" } else { "$($row.Delta)" }
                Write-Host ("  {0} {1}: {2} -> {3} ({4})" -f $(if ($row.Delta -gt 0) { '!' } else { '-' }), $row.Name, $row.Base, $row.Current, $rowDelta)
            }
        }
    }
}
if ($result.Failures.Count -gt 0) {
    foreach ($failure in $result.Failures) { Write-Host "[check_decomposition_contracts] ERROR - $failure" -ForegroundColor Red }
    exit 2
}
$complete = @($result.Rows | Where-Object State -eq 'complete').Count
$partial = @($result.Rows | Where-Object State -eq 'partial').Count
Write-Host "[check_decomposition_contracts] OK - $complete complete, $partial partial phases; ceilings and owner wiring retained."
exit 0
