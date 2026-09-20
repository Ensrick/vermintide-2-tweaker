# Ratchets the remaining hand-written NetworkLookup append owners while issue
# #428 migrates them onto the shared registration transaction.  Reductions are
# progress; a new owner or growth in an existing owner is a blocking regression.
[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [string]$BaselinePath = '',
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Join-Path $scriptDir '..' }
if ([string]::IsNullOrWhiteSpace($BaselinePath)) {
    $BaselinePath = Join-Path $scriptDir 'baselines\network_lookup_append_budget.json'
}

function Get-ManualAppendRows {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][AllowEmptyCollection()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rows = @()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $declaration = [regex]::Match(
            $Lines[$i],
            '^\s*local\s+(?<variable>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*NetworkLookup(?:\s+and\s+NetworkLookup)?\.(?<axis>[A-Za-z_][A-Za-z0-9_]*)')
        if (-not $declaration.Success) { continue }

        $variable = $declaration.Groups['variable'].Value
        $axis = $declaration.Groups['axis'].Value
        $escaped = [regex]::Escape($variable)
        $rawsetCount = 0
        $hasListAppend = $false
        $hasReverseIndex = $false
        $last = [Math]::Min($Lines.Count - 1, $i + 17)

        for ($j = $i + 1; $j -le $last; $j++) {
            $code = $Lines[$j] -replace '--.*$', ''
            if ($code -match ('^\s*local\s+' + $escaped + '\s*=') -or
                $code -match '^\s*end\s*$') {
                break
            }

            $rawsetCount += [regex]::Matches(
                $code,
                ('rawset\s*\(\s*' + $escaped + '\s*,')).Count
            if ($code -match ($escaped + '\s*\[\s*#\s*' + $escaped + '\s*\+\s*1\s*\]\s*=')) {
                $hasListAppend = $true
            }
            if ($code -match ($escaped + '\s*\[[^\]]+\]\s*=\s*#\s*' + $escaped + '\b')) {
                $hasReverseIndex = $true
            }
        }

        if ($rawsetCount -ge 2 -or ($hasListAppend -and $hasReverseIndex)) {
            $rows += [pscustomobject]@{
                Path = $Path
                Axis = $axis
                Line = $i + 1
            }
        }
    }

    # Some legacy owners write the table expression directly instead of first
    # binding it to a local.  Treat each bounded bidirectional block as one row;
    # consumedThrough prevents the second half of a pair becoming another row.
    $consumedThrough = @{}
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $code = $Lines[$i] -replace '--.*$', ''
        $direct = [regex]::Match(
            $code,
            '(?:rawset\s*\(\s*NetworkLookup\.|NetworkLookup\.)(?<axis>[A-Za-z_][A-Za-z0-9_]*)')
        if (-not $direct.Success) { continue }
        $axis = $direct.Groups['axis'].Value
        if ($consumedThrough.ContainsKey($axis) -and $i -le [int]$consumedThrough[$axis]) { continue }

        $escapedAxis = [regex]::Escape($axis)
        $rawsetCount = 0
        $hasListAppend = $false
        $hasReverseIndex = $false
        $last = [Math]::Min($Lines.Count - 1, $i + 17)
        $scanEnd = $last
        for ($j = $i; $j -le $last; $j++) {
            $scanCode = $Lines[$j] -replace '--.*$', ''
            if ($j -gt $i -and $scanCode -match '^\s*end\s*$') {
                $scanEnd = $j
                break
            }
            $rawsetCount += [regex]::Matches(
                $scanCode,
                ('rawset\s*\(\s*NetworkLookup\.' + $escapedAxis + '\s*,')).Count
            if ($scanCode -match (
                    'NetworkLookup\.' + $escapedAxis + '\s*\[\s*#\s*NetworkLookup\.' +
                    $escapedAxis + '\s*\+\s*1\s*\]\s*=')) {
                $hasListAppend = $true
            }
            if ($scanCode -match (
                    'NetworkLookup\.' + $escapedAxis + '\s*\[[^\]]+\]\s*=\s*#\s*NetworkLookup\.' +
                    $escapedAxis + '\b')) {
                $hasReverseIndex = $true
            }
        }
        if ($rawsetCount -ge 2 -or ($hasListAppend -and $hasReverseIndex)) {
            $rows += [pscustomobject]@{ Path = $Path; Axis = $axis; Line = $i + 1 }
            $consumedThrough[$axis] = $scanEnd
        }
    }
    return @($rows)
}

function Get-AppendBudget {
    param([Parameter(Mandatory = $true)][object[]]$Rows)
    $budget = @{}
    foreach ($row in $Rows) {
        $key = "$($row.Path)|$($row.Axis)"
        if (-not $budget.ContainsKey($key)) { $budget[$key] = 0 }
        $budget[$key]++
    }
    return $budget
}

function Compare-AppendBudget {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Current,
        [Parameter(Mandatory = $true)][hashtable]$Baseline
    )
    $errors = @()
    $reductions = @()
    foreach ($key in @($Current.Keys | Sort-Object)) {
        if (-not $Baseline.ContainsKey($key)) {
            $errors += "new manual append owner: $key (count $($Current[$key]))"
        }
        elseif ([int]$Current[$key] -gt [int]$Baseline[$key]) {
            $errors += "manual append owner grew: $key ($($Baseline[$key]) -> $($Current[$key]))"
        }
    }
    foreach ($key in @($Baseline.Keys | Sort-Object)) {
        $value = if ($Current.ContainsKey($key)) { [int]$Current[$key] } else { 0 }
        if ($value -lt [int]$Baseline[$key]) {
            $reductions += "$key ($($Baseline[$key]) -> $value)"
        }
    }
    return [pscustomobject]@{ Errors = @($errors); Reductions = @($reductions) }
}

function Read-Baseline {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "missing baseline: $Path"
    }
    $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($null -eq $document -or $document.schema -ne 1 -or $null -eq $document.rows) {
        throw "baseline must use schema 1 and contain rows"
    }
    $result = @{}
    foreach ($row in @($document.rows)) {
        $pathValue = [string]$row.path
        $axisValue = [string]$row.axis
        $countValue = 0
        if ([string]::IsNullOrWhiteSpace($pathValue) -or
            [string]::IsNullOrWhiteSpace($axisValue) -or
            -not [int]::TryParse([string]$row.count, [ref]$countValue) -or
            $countValue -le 0) {
            throw "baseline contains a malformed row"
        }
        $key = "$pathValue|$axisValue"
        if ($result.ContainsKey($key)) { throw "baseline contains duplicate row: $key" }
        $result[$key] = $countValue
    }
    return $result
}

function Invoke-SelfTest {
    try {
        $fixture = @(
            'local a = NetworkLookup.damage_profiles',
            'rawset(a, #a + 1, "one"); rawset(a, "one", #a)',
            'local b = NetworkLookup and NetworkLookup.item_names',
            'b[#b + 1] = "two"',
            'b["two"] = #b',
            'local c = NetworkLookup.weapon_skins',
            'rawset(c, #c + 1, "ignored")',
            'end',
            'rawset(c, "ignored", #c)',
            'local d = NetworkLookup.projectile_units',
            'rawset(d, #d + 1, "ignored")',
            'local d = something_else',
            'rawset(d, "ignored", #d)',
            'if NetworkLookup and NetworkLookup.husks then',
            'rawset(NetworkLookup.husks, #NetworkLookup.husks + 1, "three")',
            'rawset(NetworkLookup.husks, "three", #NetworkLookup.husks)',
            'end'
        )
        $rows = @(Get-ManualAppendRows -Lines $fixture -Path 'fixture.lua')
        if ($rows.Count -ne 3 -or
            $rows[0].Axis -ne 'damage_profiles' -or
            $rows[1].Axis -ne 'item_names' -or
            $rows[2].Axis -ne 'husks') {
            throw "scanner fixture expected three exact append owners"
        }

        $baseline = @{ 'a.lua|damage_profiles' = 2; 'b.lua|item_names' = 1 }
        $same = Compare-AppendBudget -Current @{ 'a.lua|damage_profiles' = 2; 'b.lua|item_names' = 1 } -Baseline $baseline
        if ($same.Errors.Count -ne 0 -or $same.Reductions.Count -ne 0) { throw "equal budget did not pass" }
        $reduced = Compare-AppendBudget -Current @{ 'a.lua|damage_profiles' = 1 } -Baseline $baseline
        if ($reduced.Errors.Count -ne 0 -or $reduced.Reductions.Count -ne 2) { throw "reduction was not accepted" }
        $grown = Compare-AppendBudget -Current @{ 'a.lua|damage_profiles' = 3 } -Baseline $baseline
        if ($grown.Errors.Count -ne 1) { throw "growth was not rejected" }
        $newOwner = Compare-AppendBudget -Current @{ 'c.lua|husks' = 1 } -Baseline $baseline
        if ($newOwner.Errors.Count -ne 1) { throw "new owner was not rejected" }

        if (-not $Quiet) { Write-Host '[check_network_lookup_append_budget self-test] PASS' -ForegroundColor Green }
        exit 0
    }
    catch {
        Write-Host "[check_network_lookup_append_budget self-test] FAIL: $_" -ForegroundColor Red
        exit 2
    }
}

if ($SelfTest) { Invoke-SelfTest }

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\', '/')
    $inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "missing active-mod inventory: $inventoryPath"
    }
    $inventory = Import-PowerShellDataFile -LiteralPath $inventoryPath
    if ($null -eq $inventory.Mods -or @($inventory.Mods).Count -eq 0) {
        throw 'active-mod inventory contains no mods'
    }

    $allRows = @()
    foreach ($mod in @($inventory.Mods)) {
        $dir = [string]$mod.Dir
        if ([string]::IsNullOrWhiteSpace($dir)) { throw 'active-mod inventory contains a blank directory' }
        $sourceRoot = Join-Path $root "$dir\scripts\mods"
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            throw "active mod source root is missing: $sourceRoot"
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -Filter '*.lua' -File -Recurse -Force)) {
            $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
            $lines = @(Get-Content -LiteralPath $file.FullName)
            $allRows += @(Get-ManualAppendRows -Lines $lines -Path $relative)
        }
    }

    $current = Get-AppendBudget -Rows @($allRows)
    $baseline = Read-Baseline -Path $BaselinePath
    $comparison = Compare-AppendBudget -Current $current -Baseline $baseline

    foreach ($errorMessage in $comparison.Errors) {
        Write-Host "[check_network_lookup_append_budget] ERROR: $errorMessage" -ForegroundColor Red
    }
    if (-not $Quiet) {
        $currentTotal = ($current.Values | Measure-Object -Sum).Sum
        $baselineTotal = ($baseline.Values | Measure-Object -Sum).Sum
        if ($null -eq $currentTotal) { $currentTotal = 0 }
        if ($null -eq $baselineTotal) { $baselineTotal = 0 }
        Write-Host "[check_network_lookup_append_budget] current=$currentTotal baseline=$baselineTotal owners=$($current.Count)"
        foreach ($reduction in $comparison.Reductions) {
            Write-Host "  migration progress: $reduction" -ForegroundColor Green
        }
    }
    if ($comparison.Errors.Count -gt 0) { exit 2 }
    exit 0
}
catch {
    Write-Host "[check_network_lookup_append_budget] ERROR: $_" -ForegroundColor Red
    exit 2
}
