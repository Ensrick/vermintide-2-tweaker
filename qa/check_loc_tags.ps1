# check_loc_tags.ps1 -- block lifecycle/issue metadata in player-facing text (#694).
#
# Verification state belongs in GitHub labels, issues, changelogs, logs, and
# internal diagnostic data. It must not decorate player-facing option titles or
# tooltips in stable OR development mods. Functional qualifiers such as `(CWV)`,
# `[Host Only]`, `[Client]`, `[WARNING]`, `[Big Rebalance]`, and category/unit
# labels remain valid because they describe behavior or ownership.
#
# Exit codes: 0 clean, 2 violation/tool failure. Findings are blocking.

[CmdletBinding()]
param(
    [switch]$Quiet,
    [switch]$SelfTest,
    [string]$MigrationBase
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

$script:lifecycleSquare = '(?i)\[(?:working|confirmed\s+working|untested|verify-fix(?:-coop)?|diagnostics-armed|diag|crash|needs\s+animations(?:\s*(?:->|→)[^\]]*)?|needs\s+offsets|issue\b[^\]]*|wip|work\s+in\s+progress|experimental|testing|prototype|fixed|unverified|not[- ]started)\]\s*'
$script:lifecycleParen = '(?i)\s*\((?:working|confirmed\s+working|untested|fixed|unverified|verify-fix(?:-coop)?|diagnostics-armed|diag|crash|needs\s+animations|needs\s+offsets|wip|work\s+in\s+progress|experimental|testing|prototype|not[- ]started)\)'
$script:lifecycleProse = '(?i)"[^"\r\n]*(?:\bexperimental\b|\buntested\b|\bunverified\b|\bnot\s+yet\s+confirmed\b|\bverify\s+(?:it|this)\s+in[- ]game\b|\bwork\s+in\s+progress\b)[^"\r\n]*"'
$script:machinery = '(?i)\b(?:decorate_tag|localization_status_sync|loc_status_sync)\b|dev-status-decoration'

# Split stable streams are write-by-promotion-only. These exact legacy lines are
# frozen debt until their already-clean development twins are promoted. Exact
# text matching prevents the exception from admitting new prose in those files.
$script:stableProseDebt = @{
    'chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker_localization.lua' = @(
        'inject_adventure_maps_tooltip = { en = "Experimental. Injected missions carry Chaos Wastes pickups and altars, and their tome and grimoire spots become Chests of Trials. Finale arenas, the Citadel of Eternity, and Belakor''s Temple are never replaced.\n\nHost-only. Requires game restart." },',
        'ct_blessed_bots_tooltip = { en = "Gives every bot three Chaos Wastes survival boons in any game mode to keep them alive longer: they gain power and healing when all allies are down, gain speed and brief damage protection at low health, and make downed allies near them invulnerable. Host-only. Experimental." },'
    )
    'crafting_in_modded/scripts/mods/crafting_in_modded/crafting_in_modded_localization.lua' = @(
        'en = "Opens the Athanor (the Winds of Magic forge) as a modded weapon crafting menu. Always works in the Keep and the Chaos Wastes hub. Inside missions it is experimental and follows the ''Allow crafting bench in mission'' option in Tweaker: GUI''s In-Mission Menus, the same toggle the Standard Crafting Bench uses.",'
    )
    'general_tweaker/scripts/mods/general_tweaker/general_tweaker_localization.lua' = @(
        'gt_bot_rescue_awaiting_tooltip = { en = "Vanilla bots ignore a teammate waiting to be rescued at a respawn point; this sends them to go free that ally. Works only when you are the host; experimental, so verify it in game." },'
    )
}

function Test-StableProseDebt([string]$Relative, [string]$Line) {
    $key = $Relative.Replace('\', '/')
    $allowed = $script:stableProseDebt[$key]
    return $null -ne $allowed -and $allowed -ccontains $Line.Trim()
}

function Remove-LifecycleDecoration([string]$Value) {
    $value = [regex]::Replace($Value, $script:lifecycleSquare, '')
    $value = [regex]::Replace($value, $script:lifecycleParen, '')
    $value = $value.Replace('Inside missions it is experimental and follows', 'Inside missions it follows')
    $value = $value.Replace('This is experimental: the weapon positions are rough, so restart the level after turning it on.', 'Weapon positions may be rough; restart the level after turning it on.')
    $value = $value.Replace('; experimental, so verify it in game.', '.')
    $value = $value.Replace('Experimental. ', '')
    $value = $value.Replace(' Host-only. Experimental.', ' Host-only.')
    return $value.Replace(' Experimental: may be inert in adventure (no Deus economy/mission flow to pay off).', ' Adventure limitation: may be inert without the Deus economy and mission flow.')
}

function Remove-LuaLineComment([string]$Line) {
    $quote = [char]0
    $escaped = $false
    for ($i = 0; $i -lt $Line.Length - 1; $i++) {
        $ch = $Line[$i]
        if ($quote -ne [char]0) {
            if ($escaped) { $escaped = $false; continue }
            if ($ch -eq '\') { $escaped = $true; continue }
            if ($ch -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") { $quote = $ch; continue }
        if ($ch -eq '-' -and $Line[$i + 1] -eq '-') { return $Line.Substring(0, $i) }
    }
    return $Line
}

function Get-ActiveLuaFiles {
    foreach ($dir in Get-ChildItem $repoRoot -Directory) {
        if ($dir.Name -eq 'tweaker' -or $dir.Name.StartsWith('_')) { continue }
        $scripts = Join-Path $dir.FullName 'scripts\mods'
        if (Test-Path $scripts) { Get-ChildItem $scripts -Recurse -File -Filter '*.lua' }
    }
}

function Find-PlayerFacingLifecycleTags([System.IO.FileInfo[]]$Files) {
    $findings = [System.Collections.Generic.List[object]]::new()
    foreach ($file in $Files) {
        $relative = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $isLocalization = $file.Name -like '*_localization.lua'
        $inLongComment = $false
        $lineNumber = 0
        foreach ($rawLine in [IO.File]::ReadLines($file.FullName)) {
            $lineNumber++
            $line = $rawLine
            if ($inLongComment) {
                $end = $line.IndexOf(']]')
                if ($end -lt 0) { continue }
                $line = $line.Substring($end + 2)
                $inLongComment = $false
            }
            while ($line -match '--\[\[') {
                $start = $line.IndexOf('--[[')
                $end = $line.IndexOf(']]', $start + 4)
                if ($end -lt 0) {
                    $line = $line.Substring(0, $start)
                    $inLongComment = $true
                    break
                }
                $line = $line.Remove($start, $end + 2 - $start)
            }
            $line = Remove-LuaLineComment $line
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $isLocalizationConstruction = $isLocalization -or
                $line -match '\ben\s*=' -or $line -match '\.en\s*=' -or
                $line -match '\bloc\s*\[' -or $line -match 'locali[sz]e.*='
            if ($isLocalizationConstruction -and
                    ($line -match $script:lifecycleSquare -or $line -match $script:lifecycleParen)) {
                $findings.Add([pscustomobject]@{
                    File = $relative; Line = $lineNumber; Kind = 'player-facing lifecycle tag'; Text = $line.Trim()
                })
            }
            if ($isLocalizationConstruction -and $line -match $script:lifecycleProse -and
                    -not (Test-StableProseDebt $relative $line)) {
                $findings.Add([pscustomobject]@{
                    File = $relative; Line = $lineNumber; Kind = 'player-facing lifecycle prose'; Text = $line.Trim()
                })
            }
            if ($line -match $script:machinery) {
                $findings.Add([pscustomobject]@{
                    File = $relative; Line = $lineNumber; Kind = 'status-decoration machinery'; Text = $line.Trim()
                })
            }
        }
    }
    return $findings
}

function Get-EnglishValues([string]$Source) {
    $values = [System.Collections.Generic.List[string]]::new()
    $pattern = '(?s)\ben\s*(?:=|\()\s*"(?<value>(?:\\.|[^"\\])*)"'
    foreach ($match in [regex]::Matches($Source, $pattern)) { $values.Add($match.Groups['value'].Value) }
    return $values
}

function Get-LocalizationKeys([string]$Source) {
    $keys = [System.Collections.Generic.List[string]]::new()
    $pattern = '(?m)^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*|loc\s*\[[^\]]+\])\s*=\s*(?:\{\s*)?en\s*(?:=|\()'
    foreach ($match in [regex]::Matches($Source, $pattern)) { $keys.Add($match.Groups['key'].Value) }
    return $keys
}

function Test-Migration([string]$BaseRef) {
    & git -C $repoRoot rev-parse --verify $BaseRef 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "migration base '$BaseRef' is unavailable" }
    $mergeBase = (& git -C $repoRoot merge-base HEAD $BaseRef).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $mergeBase) { throw "cannot resolve merge-base for '$BaseRef'" }
    $paths = @(& git -C $repoRoot diff --name-only $mergeBase -- '*_localization.lua')
    if ($LASTEXITCODE -ne 0) { throw 'git diff failed during migration proof' }
    $errors = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $paths) {
        if (-not $relative -or $relative -like 'tweaker/*') { continue }
        $currentPath = Join-Path $repoRoot $relative
        if (-not (Test-Path $currentPath)) { $errors.Add("$relative was removed"); continue }
        $baseSource = (& git -C $repoRoot show "${mergeBase}:$relative") -join "`n"
        if ($LASTEXITCODE -ne 0) { $errors.Add("$relative missing at $mergeBase"); continue }
        $currentSource = [IO.File]::ReadAllText($currentPath)
        $baseValues = @(Get-EnglishValues $baseSource)
        $currentValues = @(Get-EnglishValues $currentSource)
        if ($baseValues.Count -ne $currentValues.Count) {
            $errors.Add("$relative English-value count changed: $($baseValues.Count) -> $($currentValues.Count)")
            continue
        }
        for ($i = 0; $i -lt $baseValues.Count; $i++) {
            $expected = Remove-LifecycleDecoration $baseValues[$i]
            if ($expected -cne $currentValues[$i]) {
                $errors.Add("$relative English value #$($i + 1) changed beyond lifecycle removal")
                break
            }
        }
        $baseKeys = @(Get-LocalizationKeys $baseSource)
        $currentKeys = @(Get-LocalizationKeys $currentSource)
        if (($baseKeys -join "`0") -cne ($currentKeys -join "`0")) {
            $errors.Add("$relative localization keys/order changed")
        }
    }
    return $errors
}

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "self-test failed: $Message" }
}

if ($SelfTest) {
    try {
        Assert ((Remove-LifecycleDecoration '[working] [Issue 12 & 14] Feature') -ceq 'Feature') 'square lifecycle run'
        Assert ((Remove-LifecycleDecoration 'Feature (Experimental)') -ceq 'Feature') 'parenthesized lifecycle qualifier'
        foreach ($status in @('Fixed', 'diag', 'crash', 'needs animations', 'needs offsets')) {
            Assert ((Remove-LifecycleDecoration "Feature ($status)") -ceq 'Feature') "parenthesized $status qualifier"
        }
        Assert ((Remove-LifecycleDecoration 'Experimental. Feature') -ceq 'Feature') 'lifecycle prose migration'
        foreach ($allowed in @('(CWV) Axe', '[Host Only] Reset', '[Client] Preview', '[WARNING] Unsafe', '[Big Rebalance] Axe', '[Events] Maps', '[EXP] 12')) {
            Assert ((Remove-LifecycleDecoration $allowed) -ceq $allowed) "functional qualifier '$allowed'"
        }
        Assert ((Remove-LuaLineComment 'en = "A -- B" -- comment') -ceq 'en = "A -- B" ') 'Lua comment stripping'
        Write-Host '[check_loc_tags] SELF-TEST OK' -ForegroundColor Green
        exit 0
    } catch {
        Write-Host "[check_loc_tags] SELF-TEST FAILED -- $_" -ForegroundColor Red
        exit 2
    }
}

try {
    $findings = @(Find-PlayerFacingLifecycleTags @(Get-ActiveLuaFiles))
    $migrationErrors = @()
    if ($MigrationBase) { $migrationErrors = @(Test-Migration $MigrationBase) }
} catch {
    Write-Host "[check_loc_tags] ERROR -- $_" -ForegroundColor Red
    exit 2
}

if ($findings.Count -gt 0 -or $migrationErrors.Count -gt 0) {
    Write-Host "[check_loc_tags] FAILED -- player-facing lifecycle metadata is forbidden." -ForegroundColor Red
    foreach ($finding in $findings) {
        Write-Host ("  {0}:{1} [{2}] {3}" -f $finding.File, $finding.Line, $finding.Kind, $finding.Text) -ForegroundColor Yellow
    }
    foreach ($migrationError in $migrationErrors) { Write-Host "  migration: $migrationError" -ForegroundColor Yellow }
    exit 2
}

if (-not $Quiet) {
    $suffix = if ($MigrationBase) { "; migration semantics match $MigrationBase" } else { '' }
    Write-Host "[check_loc_tags] OK -- no player-facing lifecycle/status tags$suffix." -ForegroundColor Green
}
exit 0
