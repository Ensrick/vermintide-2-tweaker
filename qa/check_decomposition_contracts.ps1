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
    'character_weapon_variants'
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

        $entrySource = Get-Content -LiteralPath $entryPath -Raw
        $entryDir = Split-Path $entryPath -Parent
        $modules = @($contract.RequiredModules)
        if ($modules.Count -eq 0) { $failures += "$name has no RequiredModules" }
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
            $stem = [IO.Path]::GetFileNameWithoutExtension($leaf)
            if (-not $entrySource.Contains($stem)) { $failures += "$name owner not wired by entry: $leaf" }
        }
        $rows += [pscustomobject]@{ Name = $name; State = $state; Lines = $lines; Ceiling = $ceiling; Owners = $modules.Count }
    }

    foreach ($required in $RequiredNames) {
        if (-not $seenNames.ContainsKey($required)) { $failures += "required phase missing: $required" }
    }
    return [pscustomobject]@{ Failures = @($failures); Rows = @($rows) }
}

function Invoke-SelfTest {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("vt2-decomposition-contracts-" + [guid]::NewGuid().ToString('N'))
    try {
        $modDir = Join-Path $temp 'demo'
        New-Item -ItemType Directory -Force -Path $modDir | Out-Null
        Set-Content -LiteralPath (Join-Path $modDir 'entry.lua') -Value @('mod:dofile("demo/_owner")', 'return true')
        Set-Content -LiteralPath (Join-Path $modDir '_owner.lua') -Value 'return {}'
        $good = @{ Version = 1; Contracts = @(@{
            Name = 'demo'; State = 'complete'; Entry = 'demo/entry.lua'; CeilingLines = 2; RequiredModules = @('_owner.lua')
        }) }
        $positive = Test-DecompositionContracts $good $temp @('demo')
        if ($positive.Failures.Count -ne 0) { throw "positive fixture failed: $($positive.Failures -join '; ')" }

        $badGrowth = @{ Version = 1; Contracts = @(@{
            Name = 'demo'; State = 'partial'; Entry = 'demo/entry.lua'; CeilingLines = 1; RequiredModules = @('_owner.lua')
        }) }
        $badOwner = @{ Version = 1; Contracts = @(@{
            Name = 'demo'; State = 'partial'; Entry = 'demo/entry.lua'; CeilingLines = 2; RequiredModules = @('_missing.lua')
        }) }
        if ((Test-DecompositionContracts $badGrowth $temp @('demo')).Failures.Count -eq 0) { throw 'planted growth was not detected' }
        if ((Test-DecompositionContracts $badOwner $temp @('demo')).Failures.Count -eq 0) { throw 'planted missing owner was not detected' }
        if ((Test-DecompositionContracts $good $temp @('demo', 'missing')).Failures.Count -eq 0) { throw 'planted missing phase was not detected' }
        if (-not $Quiet) { Write-Host '[check_decomposition_contracts:selftest] OK - positive, growth, owner, and coverage paths verified.' -ForegroundColor Green }
        return 0
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
}

if ($SelfTest) { exit (Invoke-SelfTest) }

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    $manifest = Import-PowerShellDataFile -LiteralPath $ManifestPath
    $result = Test-DecompositionContracts $manifest $root $script:RequiredContractNames
} catch {
    Write-Host "[check_decomposition_contracts] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}

if ($result.Failures.Count -gt 0) {
    foreach ($failure in $result.Failures) { Write-Host "[check_decomposition_contracts] ERROR - $failure" -ForegroundColor Red }
    exit 2
}
if (-not $Quiet) {
    foreach ($row in $result.Rows) {
        Write-Host ("  {0,-28} {1,-8} entry={2,5}/{3,5} owners={4}" -f $row.Name, $row.State, $row.Lines, $row.Ceiling, $row.Owners) -ForegroundColor DarkGray
    }
}
$complete = @($result.Rows | Where-Object State -eq 'complete').Count
$partial = @($result.Rows | Where-Object State -eq 'partial').Count
Write-Host "[check_decomposition_contracts] OK - $complete complete, $partial partial phases; ceilings and owner wiring retained."
exit 0
