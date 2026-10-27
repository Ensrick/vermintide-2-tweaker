# check_file_sizes.ps1 — flags Lua files exceeding PROJECT_STANDARDS §2.1 limits.
# Target: 1500 lines per file. Hard limit: 2500 lines.
#
# See qa/CHECKS.md row 52.
#
# RATCHET BASELINES (issues #429 and #2): hard-limit (2500) violations are
# frozen in qa/baselines/file_sizes.json. Existing target-tier debt (1500-2500)
# is frozen independently in qa/baselines/file_sizes_target.json. A frozen file
# may shrink but may not grow; a new file crossing either threshold fails. This
# blocks regressions without making the known decomposition debt permanently
# red. Regenerate only through the explicit update switches (never automatic).
# The canonical metric is Get-Content piped to Measure-Object -Line: non-empty
# logical lines. Empty strings do not count; whitespace-only strings do count.
#
# Exit codes: 0 = all within target (or only frozen/baselined hard overages),
#             1 = frozen target-tier debt remains (advisory),
#             2 = a new threshold crossing or growth beyond either baseline.
# -BaselineOnly -Staged validates required indexed JSON and affected indexed Lua
# rows only; valid scope exits 0, invalid/unreadable scope exits 2. No update authority.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [int]$Target = 1500,
    [int]$HardLimit = 2500,
    [switch]$Quiet,
    [switch]$UpdateBaseline,
    [switch]$UpdateTargetBaseline,
    [switch]$SelfTest,
    [switch]$BaselineOnly,
    [switch]$Staged
)

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Join-Path $scriptRoot '..' }
if ($BaselineOnly -or $Staged) {
    try {
        if (-not ($BaselineOnly -and $Staged) -or $SelfTest -or $UpdateBaseline -or $UpdateTargetBaseline) {
            throw '-BaselineOnly requires -Staged and cannot be combined with SelfTest or update modes.'
        }
        $repoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    }
    catch { Write-Host "[check_file_sizes] ERROR -- $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
}
else { $repoRoot = (Resolve-Path $RepoRoot).Path }
$baselinePath = Join-Path $scriptRoot "baselines\file_sizes.json"
$targetBaselinePath = Join-Path $scriptRoot "baselines\file_sizes_target.json"
$overTarget = @()
$overHard = @()
$observedByRel = @{}

if ($UpdateBaseline -and $UpdateTargetBaseline) {
    throw '-UpdateBaseline and -UpdateTargetBaseline are separate reviewed transactions; choose exactly one.'
}

function Test-GeneratedPureDataLua([string]$path) {
    # PROJECT_STANDARDS section 2.1 exempts pure data.  Recognize only the
    # narrow generator contract: an explicit DO NOT HAND-EDIT banner followed
    # by a top-level table return.  Generated logic remains subject to the
    # normal limit, while catalogues such as Character Dialogue's 34k stable
    # event rows do not require an artificial code-module split.
    $head = @(Get-Content -LiteralPath $path -TotalCount 10 -ErrorAction Stop)
    if ($head.Count -eq 0 -or $head[0] -notmatch 'AUTO-GENERATED.+DO NOT HAND-EDIT') {
        return $false
    }
    $firstBodyLine = @($head | Select-Object -Skip 1 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^\s*--' } |
        Select-Object -First 1)
    return $firstBodyLine.Count -eq 1 -and $firstBodyLine[0] -match '^\s*return\s*\{'
}

function Test-RepositoryInternalWorktreePath([string]$path) {
    # Agent tools may create complete linked checkouts beneath a hidden
    # repository-owned worktree container. Those checkouts are not source in
    # this repository and must never be counted or frozen into its baseline.
    # Match the convention structurally so .claude/worktrees, .git/worktrees,
    # .codex/worktrees, and a top-level .worktrees directory are all covered.
    $normalized = $path.Replace('\', '/')
    return [regex]::IsMatch(
        $normalized,
        '(?i)(?:^|/)(?:\.[^/]+/worktrees|\.worktrees)(?:/|$)'
    )
}

function Test-ModLuaCandidate([System.IO.FileInfo]$file) {
    $p = $file.FullName
    if (Test-RepositoryInternalWorktreePath $p) { return $false }
    return $p -notlike "*\_archive\*" `
        -and $p -notlike "*\bundleV2\*" `
        -and $p -notlike "*\.build\*" `
        -and $p -notlike "*\.temp\*" `
        -and $p -notlike "*\.spawn_tweaks_ref\*" `
        -and $p -notlike "*\tweaker\*" `
        -and $p -notlike "*\sample_*\*" `
        -and $p -notlike "*\Vermintide-2-Source-Code\*" `
        -and $p -notlike "*\misc-vermintide-mods\*" `
        -and $p -notlike "*\_big_rebalance_extract\*" `
        -and $p -notlike "*.lua.processed" `
        -and $file.Name -notmatch "^_cosmetic_unlocks" `
        -and $file.Name -notmatch "_localization\.lua$" `
        -and $file.Name -notmatch "^item_master_list_" `
        -and -not (Test-GeneratedPureDataLua $file.FullName)
}

function Find-ModLuas {
    Get-ChildItem -Path $repoRoot -Filter "*.lua" -Recurse -File -ErrorAction SilentlyContinue `
        | Where-Object { Test-ModLuaCandidate $_ }
}

# Baseline keys are repo-relative paths with forward slashes (cross-platform,
# JSON-friendly). Normalize any runtime path to that form before comparison.
function Normalize-RelPath([string]$p) { return $p.Replace('\', '/') }

function Measure-LuaSize {
    param([string]$path, [AllowEmptyCollection()][string[]]$Lines)
    # Preserve the historical baseline metric exactly. Measure-Object -Line
    # excludes empty strings but includes strings containing only whitespace.
    $content = if ($PSBoundParameters.ContainsKey('Lines')) { $Lines } else { Get-Content -LiteralPath $path -ErrorAction Stop }
    return [int](($content | Measure-Object -Line).Lines)
}

function Load-Baseline([string]$path) {
    if (-not (Test-Path $path)) { return @{} }
    try { $j = Get-Content $path -Raw | ConvertFrom-Json } catch { return @{} }
    $map = @{}
    if ($j.files) {
        foreach ($prop in $j.files.PSObject.Properties) { $map[$prop.Name] = [int]$prop.Value }
    }
    return $map
}

function Get-FileSizeClassification {
    param(
        [object[]]$TargetFindings,
        [object[]]$HardFindings,
        [hashtable]$Observed,
        [hashtable]$HardBaseline,
        [hashtable]$TargetBaseline
    )

    $newHard = @()
    $grownHard = @()
    $frozenHard = @()
    foreach ($f in @($HardFindings)) {
        if ($HardBaseline.ContainsKey($f.Rel)) {
            if ($f.Lines -gt $HardBaseline[$f.Rel]) {
                $grownHard += [PSCustomObject]@{ Path=$f.Path; Rel=$f.Rel; Lines=$f.Lines; Baseline=$HardBaseline[$f.Rel] }
            } else {
                $frozenHard += $f
            }
        } else {
            $newHard += $f
        }
    }

    $newTarget = @()
    $grownTarget = @()
    $frozenTarget = @()
    foreach ($f in @($TargetFindings)) {
        if ($TargetBaseline.ContainsKey($f.Rel)) {
            if ($f.Lines -gt $TargetBaseline[$f.Rel]) {
                $grownTarget += [PSCustomObject]@{ Path=$f.Path; Rel=$f.Rel; Lines=$f.Lines; Baseline=$TargetBaseline[$f.Rel] }
            } else {
                $frozenTarget += $f
            }
        } else {
            $newTarget += $f
        }
    }

    $retiredTarget = @()
    foreach ($rel in @($TargetBaseline.Keys | Sort-Object)) {
        if (-not $Observed.ContainsKey($rel) -or [int]$Observed[$rel] -le $Target) {
            $retiredTarget += [PSCustomObject]@{
                Rel = $rel
                Lines = if ($Observed.ContainsKey($rel)) { [int]$Observed[$rel] } else { $null }
                Baseline = [int]$TargetBaseline[$rel]
            }
        }
    }

    return [PSCustomObject]@{
        NewHard=$newHard; GrownHard=$grownHard; FrozenHard=$frozenHard
        NewTarget=$newTarget; GrownTarget=$grownTarget; FrozenTarget=$frozenTarget
        RetiredTarget=$retiredTarget
    }
}

function Test-BaselineIntegrity {
    param([hashtable]$HardBaseline,[hashtable]$TargetBaseline)
    $errors = @()
    foreach ($rel in @($HardBaseline.Keys)) {
        if (Test-RepositoryInternalWorktreePath $rel) { $errors += "hard baseline contains hidden-worktree path: $rel" }
        if ([int]$HardBaseline[$rel] -le $HardLimit) { $errors += "hard baseline is not above $HardLimit lines: $rel" }
    }
    foreach ($rel in @($TargetBaseline.Keys)) {
        $ceiling = [int]$TargetBaseline[$rel]
        if (Test-RepositoryInternalWorktreePath $rel) { $errors += "target baseline contains hidden-worktree path: $rel" }
        if ($ceiling -le $Target -or $ceiling -gt $HardLimit) { $errors += "target baseline is outside ($Target,$HardLimit]: $rel=$ceiling" }
        if ($HardBaseline.ContainsKey($rel)) { $errors += "path appears in both hard and target baselines: $rel" }
    }
    return @($errors)
}

# #1751: this mode reads index objects only; normal/full scans retain their path.
function Read-FileSizeGitLines {
    param([string[]]$Arguments)
    $encoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
        return @(Invoke-QAStateGit -RepoRoot $repoRoot -Arguments (@('--no-optional-locks') + $Arguments))
    }
    finally { [Console]::OutputEncoding = $encoding }
}

function Read-FileSizeIndexBlob {
    param([string]$Path, [switch]$Required)
    $rows = @((@(Read-FileSizeGitLines -Arguments @('-c', 'core.quotepath=false', 'ls-files', '--stage', '-z', '--', $Path)) -join "`n").Split(
        [char[]]@([char]0), [StringSplitOptions]::RemoveEmptyEntries))
    if ($rows.Count -eq 0) {
        if ($Required) { throw "Required indexed baseline is absent: $Path" }
        return [pscustomobject]@{ Present = $false; Lines = [string[]]@() }
    }
    if ($rows.Count -ne 1 -or $rows[0] -notmatch '^(100644|100755) ([0-9a-f]{40,64}) 0\t(.+)$' -or $Matches[3] -cne $Path) {
        throw "Unmerged or non-regular indexed file: $Path"
    }
    $object = $Matches[2]
    return [pscustomobject]@{ Present = $true; Lines = [string[]]@(Read-FileSizeGitLines -Arguments @('cat-file', 'blob', $object)) }
}

function ConvertFrom-FileSizeBaselineText {
    param([string]$Text, [string]$Name, [switch]$TargetTier)
    if ([string]::IsNullOrWhiteSpace($Text)) { throw "Required baseline is empty: $Name" }
    $value = $Text | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $value -or $value -isnot [pscustomobject] -or $value.files -isnot [pscustomobject]) {
        throw "Baseline must contain an object-valued files map: $Name"
    }
    foreach ($field in @('hard_limit') + $(if ($TargetTier) { @('target') } else { @() })) {
        $number = $value.$field
        $expected = if ($field -eq 'target') { $Target } else { $HardLimit }
        if (($number -isnot [int] -and $number -isnot [long]) -or $number -ne $expected) {
            throw "Invalid baseline metadata ${Name}: $field"
        }
    }
    $map = @{}
    foreach ($row in $value.files.PSObject.Properties) {
        $key = $row.Name
        if ([string]::IsNullOrWhiteSpace($key) -or $key -notmatch '\.lua$' -or $key -match '[:\\\x00-\x1f]' -or
            $key.StartsWith('/') -or $key.Contains('//') -or @($key.Split('/') | Where-Object { $_ -eq '.' -or $_ -eq '..' }).Count) {
            throw "Invalid baseline path in ${Name}: $key"
        }
        if (($row.Value -isnot [int] -and $row.Value -isnot [long]) -or $row.Value -le 0 -or $row.Value -gt [int]::MaxValue) {
            throw "Invalid integer baseline count in ${Name}: $key"
        }
        $map[$key] = [int]$row.Value
    }
    return $map
}

function Invoke-StagedFileSizeBaselines {
    . (Join-Path $scriptRoot 'worktree_state.ps1')
    $paths = @('qa/baselines/file_sizes.json', 'qa/baselines/file_sizes_target.json')
    $before, $after = @(), @()
    foreach ($path in $paths) {
        $index = Read-FileSizeIndexBlob -Path $path -Required
        $old = @(Read-FileSizeGitLines -Arguments @('show', ('HEAD:' + $path))) -join "`n"
        $before += ,(ConvertFrom-FileSizeBaselineText -Text $old -Name ('HEAD:' + $path) -TargetTier:($path -eq $paths[1]))
        $after += ,(ConvertFrom-FileSizeBaselineText -Text ($index.Lines -join "`n") -Name (':' + $path) -TargetTier:($path -eq $paths[1]))
    }
    $errors = @(Test-BaselineIntegrity -HardBaseline $after[0] -TargetBaseline $after[1])
    if ($errors.Count) { throw ($errors -join '; ') }
    $changed = @{}
    for ($tier = 0; $tier -lt 2; $tier++) {
        foreach ($key in @($before[$tier].Keys) + @($after[$tier].Keys)) {
            if (-not $before[$tier].ContainsKey($key) -or -not $after[$tier].ContainsKey($key) -or $before[$tier][$key] -ne $after[$tier][$key]) {
                $changed[$key] = $true
            }
        }
    }
    $observed, $scopedHard, $scopedTarget = @{}, @{}, @{}
    $hard, $targetRows = @(), @()
    foreach ($key in @($changed.Keys | Sort-Object)) {
        if ($after[0].ContainsKey($key)) { $scopedHard[$key] = $after[0][$key] }
        if ($after[1].ContainsKey($key)) { $scopedTarget[$key] = $after[1][$key] }
        $blob = Read-FileSizeIndexBlob -Path $key
        if (-not $blob.Present) { continue }
        $count = Measure-LuaSize -Lines $blob.Lines
        $observed[$key] = $count
        $row = [pscustomobject]@{ Path = $key; Rel = $key; Lines = $count }
        if ($count -gt $HardLimit) { $hard += $row }
        elseif ($count -gt $Target) { $targetRows += $row }
    }
    $result = Get-FileSizeClassification -TargetFindings $targetRows -HardFindings $hard -Observed $observed `
        -HardBaseline $scopedHard -TargetBaseline $scopedTarget
    if (@($result.NewHard).Count -or @($result.GrownHard).Count -or @($result.NewTarget).Count -or @($result.GrownTarget).Count) {
        throw 'Indexed baseline changes leave an affected Lua path above its applicable indexed ceiling.'
    }
    Write-Host "[check_file_sizes] STAGED BASELINES OK -- $($changed.Count) affected Lua row(s); no repository scan or baseline-update authorization."
}

function Invoke-SelfTest {
    $script:FileSizeSelfTestPass = $true
    function Assert([bool]$condition, [string]$description) {
        $verdict = if ($condition) { 'PASS' } else { 'FAIL' }
        $colour = if ($condition) { 'Green' } else { 'Red' }
        Write-Host ("  [{0}] {1}" -f $verdict, $description) -ForegroundColor $colour
        if (-not $condition) { $script:FileSizeSelfTestPass = $false }
    }

    $canonicalRel = 'chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua'
    $canonicalPath = Join-Path $repoRoot ($canonicalRel.Replace('/', '\'))
    $canonicalFile = Get-Item -LiteralPath $canonicalPath -ErrorAction Stop
    $clonedSuffix = 'career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua'

    Assert (Test-RepositoryInternalWorktreePath ".claude/worktrees/agent-a/$clonedSuffix") 'ignores Claude nested worktree checkout'
    Assert (Test-RepositoryInternalWorktreePath ".codex/worktrees/task-a/$clonedSuffix") 'ignores equivalent hidden-tool worktree checkout'
    Assert (Test-RepositoryInternalWorktreePath ".git/worktrees/task-a/gitdir") 'ignores Git repository-internal worktree metadata'
    Assert (Test-RepositoryInternalWorktreePath ".worktrees/task-a/$clonedSuffix") 'ignores conventional top-level hidden worktree checkout'
    Assert (-not (Test-RepositoryInternalWorktreePath $canonicalRel)) 'does not classify canonical module as worktree metadata'
    Assert (Test-ModLuaCandidate $canonicalFile) 'canonical oversized module remains in scan candidates'
    $canonicalLines = Measure-LuaSize $canonicalPath
    Assert ($canonicalLines -gt $HardLimit) 'canonical fixture still exercises hard-limit enforcement'

    $metricBlankPath = Join-Path ([IO.Path]::GetTempPath()) ('vt2-file-size-blank-' + [guid]::NewGuid().ToString('N') + '.lua')
    $metricWhitespacePath = Join-Path ([IO.Path]::GetTempPath()) ('vt2-file-size-whitespace-' + [guid]::NewGuid().ToString('N') + '.lua')
    try {
        $utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($metricBlankPath, "first`n`nlast`n", $utf8NoBom)
        [IO.File]::WriteAllText($metricWhitespacePath, "first`n   `nlast`n", $utf8NoBom)
        Assert ((Measure-LuaSize $metricBlankPath) -eq 2) 'canonical metric excludes an empty logical line'
        Assert ((Measure-LuaSize $metricWhitespacePath) -eq 3) 'canonical metric includes a whitespace-only logical line'
    } finally {
        if (Test-Path -LiteralPath $metricBlankPath -PathType Leaf) { Remove-Item -LiteralPath $metricBlankPath -Force }
        if (Test-Path -LiteralPath $metricWhitespacePath -PathType Leaf) { Remove-Item -LiteralPath $metricWhitespacePath -Force }
    }

    $generatedCatalogRel = 'weapon_tweaker/scripts/mods/weapon_tweaker/_wt_history_5_2_catalog.lua'
    $generatedCatalogPath = Join-Path $repoRoot ($generatedCatalogRel.Replace('/', '\'))
    $generatedCatalogFile = Get-Item -LiteralPath $generatedCatalogPath -ErrorAction Stop
    Assert (Test-GeneratedPureDataLua $generatedCatalogPath) 'recognizes the pinned #1436 generated pure-data catalogue'
    Assert (-not (Test-ModLuaCandidate $generatedCatalogFile)) 'exempts the pinned #1436 generated pure-data catalogue from code limits'
    $commentedCatalogRel = 'character_dialogue/scripts/mods/character_dialogue/character_dialogue_catalogue.lua'
    $commentedCatalogPath = Join-Path $repoRoot ($commentedCatalogRel.Replace('/', '\'))
    $commentedCatalogFile = Get-Item -LiteralPath $commentedCatalogPath -ErrorAction Stop
    Assert (Test-GeneratedPureDataLua $commentedCatalogPath) 'allows generated data-shape comments before the literal table return'
    Assert (-not (Test-ModLuaCandidate $commentedCatalogFile)) 'retains the existing Character Dialogue pure-data exemption'

    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $fixturePrefix = 'vt2-file-size-' + [guid]::NewGuid().ToString('N')
    $nearMissPath = Join-Path $tempBase ($fixturePrefix + '-near-miss.lua')
    $logicPath = Join-Path $tempBase ($fixturePrefix + '-logic.lua')
    try {
        $utf8NoBom = New-Object Text.UTF8Encoding($false)
        [IO.File]::WriteAllText($nearMissPath,
            "-- AUTO-GENERATED by fixture; DO NOT HAND-EDIT.`nreturn build_catalog()`n",
            $utf8NoBom)
        [IO.File]::WriteAllText($logicPath,
            "-- AUTO-GENERATED by fixture; DO NOT HAND-EDIT.`nlocal side_effect = true`nreturn {}`n",
            $utf8NoBom)
        $nearMissFile = Get-Item -LiteralPath $nearMissPath -ErrorAction Stop
        $logicFile = Get-Item -LiteralPath $logicPath -ErrorAction Stop
        Assert (-not (Test-GeneratedPureDataLua $nearMissPath)) 'rejects a generated banner without a literal table return'
        Assert (Test-ModLuaCandidate $nearMissFile) 'keeps a generated near-miss under ordinary code limits'
        Assert (-not (Test-GeneratedPureDataLua $logicPath)) 'rejects executable logic between the banner and table return'
        Assert (Test-ModLuaCandidate $logicFile) 'keeps generated executable logic under ordinary code limits'
    } finally {
        if (Test-Path -LiteralPath $nearMissPath -PathType Leaf) {
            Remove-Item -LiteralPath $nearMissPath -Force
        }
        if (Test-Path -LiteralPath $logicPath -PathType Leaf) {
            Remove-Item -LiteralPath $logicPath -Force
        }
    }

    $baseline = Load-Baseline $baselinePath
    $targetBaseline = Load-Baseline $targetBaselinePath
    $internalBaselineKeys = @($baseline.Keys | Where-Object { Test-RepositoryInternalWorktreePath $_ })
    $internalTargetBaselineKeys = @($targetBaseline.Keys | Where-Object { Test-RepositoryInternalWorktreePath $_ })
    Assert ($baseline.Count -eq 2) 'baseline contains exactly the 2 remaining canonical oversized modules'
    Assert ($internalBaselineKeys.Count -eq 0) 'baseline contains no nested-worktree entries'
    Assert ($targetBaseline.Count -gt 0) 'target-tier debt map is populated'
    Assert ($internalTargetBaselineKeys.Count -eq 0) 'target-tier debt map contains no nested-worktree entries'
    Assert (@(Test-BaselineIntegrity -HardBaseline $baseline -TargetBaseline $targetBaseline).Count -eq 0) 'hard and target baselines are disjoint and threshold-valid'
    Assert ($baseline.ContainsKey($canonicalRel)) 'baseline retains a canonical oversized module'
    Assert (-not $baseline.ContainsKey('chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua')) 'completed CT Dev decomposition is removed from frozen debt'
    Assert (-not $baseline.ContainsKey('character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua')) 'completed CWV decomposition is removed from frozen debt'
    Assert (-not $baseline.ContainsKey('career_tweaker/scripts/mods/career_tweaker/career_tweaker_balance.lua')) 'completed Career decomposition is removed from frozen debt'
    # A file that drops back under the hard limit leaves the frozen set entirely:
    # it can no longer be "frozen at" anything, and check_decomposition_contracts
    # owns its ratchet from then on. cim_dev crossed back under at 0.8.120-dev.
    Assert (-not $baseline.ContainsKey('crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua')) 'cim_dev decomposition below the hard limit is removed from frozen debt'
    # The wt mirror pair crossed back under together at 0.12.301-beta / 0.12.302-dev.
    # Both stream entries leave the frozen set in the same slice, because the gate
    # that binds them (check_wt_stream_parity) forbids one stream decomposing alone.
    Assert (-not $baseline.ContainsKey('weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua')) 'wt decomposition below the hard limit is removed from frozen debt'
    Assert (-not $baseline.ContainsKey('weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua')) 'wt_dev mirror decomposition below the hard limit is removed from frozen debt'

    $fixtureHard = @{ 'hard.lua'=2601 }
    $fixtureTarget = @{ 'grown.lua'=1600; 'shrunk.lua'=1700; 'removed.lua'=1800; 'frozen.lua'=1900 }
    $fixtureObserved = @{ 'hard.lua'=2601; 'grown.lua'=1601; 'shrunk.lua'=1499; 'frozen.lua'=1850; 'new.lua'=1501 }
    $fixtureTargetFindings = @(
        [PSCustomObject]@{Path='grown.lua';Rel='grown.lua';Lines=1601}
        [PSCustomObject]@{Path='frozen.lua';Rel='frozen.lua';Lines=1850}
        [PSCustomObject]@{Path='new.lua';Rel='new.lua';Lines=1501}
    )
    $fixtureHardFindings = @([PSCustomObject]@{Path='hard.lua';Rel='hard.lua';Lines=2601})
    $classification = Get-FileSizeClassification -TargetFindings $fixtureTargetFindings -HardFindings $fixtureHardFindings `
        -Observed $fixtureObserved -HardBaseline $fixtureHard -TargetBaseline $fixtureTarget
    Assert ($classification.FrozenHard.Count -eq 1 -and $classification.NewHard.Count -eq 0 -and $classification.GrownHard.Count -eq 0) 'unchanged hard debt remains frozen'
    Assert ($classification.GrownTarget.Count -eq 1 -and $classification.GrownTarget[0].Rel -eq 'grown.lua') 'target-tier growth is blocking debt'
    Assert ($classification.NewTarget.Count -eq 1 -and $classification.NewTarget[0].Rel -eq 'new.lua') 'a new target-tier oversized file is blocking debt'
    Assert ($classification.FrozenTarget.Count -eq 1 -and $classification.FrozenTarget[0].Rel -eq 'frozen.lua') 'target-tier shrinkage above target remains allowed'
    Assert ($classification.RetiredTarget.Count -eq 2 -and @($classification.RetiredTarget.Rel) -contains 'shrunk.lua' -and @($classification.RetiredTarget.Rel) -contains 'removed.lua') 'below-target and removed files retire cleanly from target debt'

    try {
        . (Join-Path $scriptRoot 'fixtures/file_sizes_staged.ps1')
        $stagedArgs = @{
            CheckerSource = [IO.File]::ReadAllText((Join-Path $scriptRoot 'check_file_sizes.ps1'))
            HookSource = [IO.File]::ReadAllText((Join-Path $repoRoot 'tools/hooks/pre-commit.ps1'))
            HelperSource = [IO.File]::ReadAllText((Join-Path $scriptRoot 'worktree_state.ps1'))
        }
        $stagedResult = Invoke-FileSizeStagedSelfTest @stagedArgs
        Assert $stagedResult 'actual index-only baseline checker and hook contracts'
    }
    catch { Assert $false ("staged baseline fixture failed: " + $_.Exception.Message) }

    if ($script:FileSizeSelfTestPass) {
        Write-Host '[check_file_sizes -SelfTest] OK -- dual-tier ratchet and worktree exclusion intact.' -ForegroundColor Green
        return 0
    }
    Write-Host '[check_file_sizes -SelfTest] FAILED -- worktree exclusion or canonical enforcement regressed.' -ForegroundColor Red
    return 2
}

if ($SelfTest) { exit (Invoke-SelfTest) }
if ($BaselineOnly) {
    try { Invoke-StagedFileSizeBaselines; exit 0 }
    catch { Write-Host "[check_file_sizes] ERROR -- $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
}

foreach ($lua in Find-ModLuas) {
    $lineCount = Measure-LuaSize $lua.FullName
    $relPath = $lua.FullName.Substring($repoRoot.Length + 1)
    $rel = Normalize-RelPath $relPath
    $observedByRel[$rel] = $lineCount
    if (-not $Quiet) { Write-Host "  $relPath -- $lineCount lines" -ForegroundColor DarkGray }
    if ($lineCount -gt $HardLimit) {
        $overHard += [PSCustomObject]@{ Path = $relPath; Rel = $rel; Lines = $lineCount }
    } elseif ($lineCount -gt $Target) {
        $overTarget += [PSCustomObject]@{ Path = $relPath; Rel = $rel; Lines = $lineCount }
    }
}

# --- -UpdateBaseline: freeze the CURRENT over-hard set and exit (explicit only) ---
if ($UpdateBaseline) {
    $files = [ordered]@{}
    foreach ($f in ($overHard | Sort-Object -Property Rel)) { $files[$f.Rel] = $f.Lines }
    $payload = [ordered]@{
        '_comment'  = "Frozen file-size violations (Lua files over the $HardLimit-line hard limit). Regenerate ONLY with check_file_sizes.ps1 -UpdateBaseline. A baselined file fails only if it GROWS beyond its frozen count; any non-baselined file crossing the hard limit fails immediately. Issue #429 / PROJECT_STANDARDS §11."
        'hard_limit' = $HardLimit
        'generated'  = (Get-Date).ToString('yyyy-MM-dd')
        'files'      = $files
    }
    $dir = Split-Path $baselinePath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $baselinePath -Encoding utf8
    Write-Host "[check_file_sizes] baseline UPDATED: $($files.Count) file(s) frozen -> $baselinePath" -ForegroundColor Cyan
    foreach ($k in $files.Keys) { Write-Host ("  frozen  {0} -- {1} lines" -f $k, $files[$k]) -ForegroundColor DarkGray }
    exit 0
}

# --- -UpdateTargetBaseline: freeze the CURRENT target-tier set and exit ---
if ($UpdateTargetBaseline) {
    $files = [ordered]@{}
    foreach ($f in ($overTarget | Sort-Object -Property Rel)) { $files[$f.Rel] = $f.Lines }
    $payload = [ordered]@{
        '_comment' = "Frozen target-tier Lua debt (files over $Target and at or below $HardLimit non-empty logical lines). Regenerate ONLY with check_file_sizes.ps1 -UpdateTargetBaseline after review. A frozen file may shrink but may not grow; any unlisted file crossing the target blocks. Issue #2 / PROJECT_STANDARDS sections 2.1 and 11."
        'target' = $Target
        'hard_limit' = $HardLimit
        'metric' = 'PowerShell Get-Content | Measure-Object -Line non-empty logical lines (whitespace-only lines count)'
        'generated' = (Get-Date).ToString('yyyy-MM-dd')
        'files' = $files
    }
    $dir = Split-Path $targetBaselinePath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $payload | ConvertTo-Json -Depth 4 | Set-Content -Path $targetBaselinePath -Encoding utf8
    Write-Host "[check_file_sizes] target baseline UPDATED: $($files.Count) file(s) frozen -> $targetBaselinePath" -ForegroundColor Cyan
    foreach ($k in $files.Keys) { Write-Host ("  frozen  {0} -- {1} lines" -f $k, $files[$k]) -ForegroundColor DarkGray }
    exit 0
}

$baseline = Load-Baseline $baselinePath
$targetBaseline = Load-Baseline $targetBaselinePath
$baselineErrors = @(Test-BaselineIntegrity -HardBaseline $baseline -TargetBaseline $targetBaseline)
if ($baselineErrors.Count -gt 0) {
    Write-Host '[check_file_sizes] ERRORS - malformed or overlapping baseline debt:' -ForegroundColor Red
    foreach ($message in $baselineErrors) { Write-Host "  X $message" -ForegroundColor Red }
    exit 2
}
$classification = Get-FileSizeClassification -TargetFindings $overTarget -HardFindings $overHard `
    -Observed $observedByRel -HardBaseline $baseline -TargetBaseline $targetBaseline

# Report
Write-Host ""
if ($classification.FrozenHard.Count -gt 0) {
    Write-Host "[check_file_sizes] $($classification.FrozenHard.Count) file(s) over the $HardLimit-line hard limit are BASELINED (frozen in qa/baselines/file_sizes.json); non-blocking until they grow. (baselined: $($classification.FrozenHard.Count))" -ForegroundColor DarkCyan
}

if ($classification.FrozenTarget.Count -gt 0) {
    Write-Host "[check_file_sizes] WARNINGS - $($classification.FrozenTarget.Count) frozen file(s) remain over the $Target-line target (split when a natural boundary appears):" -ForegroundColor Yellow
    foreach ($f in $classification.FrozenTarget | Sort-Object -Property Lines -Descending) {
        Write-Host "  ! $($f.Path) — $($f.Lines) lines" -ForegroundColor Yellow
    }
}

if ($classification.RetiredTarget.Count -gt 0) {
    Write-Host "[check_file_sizes] $($classification.RetiredTarget.Count) target baseline row(s) are now below target or absent and may be removed with -UpdateTargetBaseline:" -ForegroundColor DarkCyan
    foreach ($f in $classification.RetiredTarget) {
        $current = if ($null -eq $f.Lines) { 'absent' } else { "$($f.Lines) lines" }
        Write-Host "  - $($f.Rel) - $current (was frozen at $($f.Baseline))" -ForegroundColor DarkCyan
    }
}

if ($classification.NewHard.Count -gt 0 -or $classification.GrownHard.Count -gt 0 -or
    $classification.NewTarget.Count -gt 0 -or $classification.GrownTarget.Count -gt 0) {
    Write-Host "[check_file_sizes] ERRORS - file-size ratchet regressions (split required; baseline updates require explicit review):" -ForegroundColor Red
    foreach ($f in $classification.NewHard | Sort-Object -Property Lines -Descending) {
        Write-Host "  X NEW over hard limit: $($f.Path) — $($f.Lines) lines (limit $HardLimit)" -ForegroundColor Red
    }
    foreach ($f in $classification.GrownHard | Sort-Object -Property Lines -Descending) {
        Write-Host "  X GREW beyond baseline: $($f.Path) — $($f.Lines) lines (was frozen at $($f.Baseline))" -ForegroundColor Red
    }
    foreach ($f in $classification.NewTarget | Sort-Object -Property Lines -Descending) {
        Write-Host "  X NEW over target: $($f.Path) — $($f.Lines) lines (target $Target)" -ForegroundColor Red
    }
    foreach ($f in $classification.GrownTarget | Sort-Object -Property Lines -Descending) {
        Write-Host "  X GREW beyond target baseline: $($f.Path) — $($f.Lines) lines (was frozen at $($f.Baseline))" -ForegroundColor Red
    }
    exit 2
}

if ($overTarget.Count -gt 0) { exit 1 }

Write-Host "[check_file_sizes] OK — no new hard-limit offenders; all other files within target ($Target lines)." -ForegroundColor Green
exit 0
