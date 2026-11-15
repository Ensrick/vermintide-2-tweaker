# convert-cards.ps1 - write one draft verification spec per open issue (WP-G-05).
#
# Source per issue: the newest `## CURRENT LIVE TEST` comment (format in
# tools/verify/README.md) and the issue's row in the audit ledgers
# (docs/audits/2026-11-13_FORMAL_AUDIT/evidence/ledgers/D1..D5_ledger.tsv).
# Output: qa/specs/issue_<N>.json with status "draft", in the format of
# qa/specs/README.md. Card text is copied verbatim; nothing is invented.
#
# GitHub access is read-only (`gh api` GET with --paginate). -IssuesJsonPath
# replaces it with an offline JSON list of
#   { number, labels: [names], comments: [ { id, created_at, body } ] }.
# A spec whose status is "ready" is never overwritten.
#
# Exit codes: 0 = written, 2 = error. ASCII only; PowerShell 7.

[CmdletBinding()]
param(
    [string]$Repository = 'Ensrick/vermintide-2-tweaker',
    [string]$LedgerDir = '',
    [string]$OutDir = '',
    [string]$IssuesJsonPath = '',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# PROJECT_STANDARDS.md section 11 "Mod (1+)" label table -> folder(s). The
# five dev/stable pairs map to the _dev folder; the stable folder is added
# when the issue carries `public-release`.
$script:LabelDirs = [ordered]@{
    'Tweaker: Chaos Wastes' = @{ Dev = 'chaos_wastes_tweaker_dev'; Stable = 'chaos_wastes_tweaker' }
    'Tweaker: General'      = @{ Dev = 'general_tweaker_dev'; Stable = 'general_tweaker' }
    'Tweaker: GUI'          = @{ Dev = 'gui_tweaker_dev'; Stable = 'gui_tweaker' }
    'cim'                   = @{ Dev = 'crafting_in_modded_dev'; Stable = 'crafting_in_modded' }
    'Tweaker: Weapons'      = @{ Dir = 'weapon_tweaker' }
    'Tweaker: Cosmetics'    = @{ Dir = 'cosmetics_tweaker' }
    'Tweaker: Enemies'      = @{ Dir = 'enemy_tweaker' }
    'Tweaker: Events'       = @{ Dir = 'event_tweaker' }
    'Tweaker: Career'       = @{ Dir = 'career_tweaker' }
    'CWV'                   = @{ Dir = 'character_weapon_variants' }
    'WOC'                   = @{ Dir = 'weapons_of_chaos' }
    'dcp'                   = @{ Dir = 'dynamic_cosmetic_portraits' }
    'Character Dialogue'    = @{ Dir = 'character_dialogue' }
    'Progression'           = @{ Dir = 'modded_progression' }
}

# Fallback when an R/V/C issue has no mod label: the ledger `mod` cell's
# tokens (ids and folder names as the audit wrote them).
$script:LedgerTokenDirs = @{
    'gut' = 'gui_tweaker_dev'; 'ct' = 'chaos_wastes_tweaker_dev'; 'gt' = 'general_tweaker_dev'
    'cim' = 'crafting_in_modded_dev'; 'cwv' = 'character_weapon_variants'; 'wt' = 'weapon_tweaker'
    'cos' = 'cosmetics_tweaker'; 'cosmetics' = 'cosmetics_tweaker'; 'crt' = 'career_tweaker'; 'career' = 'career_tweaker'
    'et' = 'enemy_tweaker'; 'enemy' = 'enemy_tweaker'; 'evt' = 'event_tweaker'; 'event' = 'event_tweaker'
    'mp' = 'modded_progression'; 'woc' = 'weapons_of_chaos'; 'dcp' = 'dynamic_cosmetic_portraits'
    'chaos_wastes' = 'chaos_wastes_tweaker_dev'
}

$script:VersionPattern = 'v?[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z]+)?'

function Get-InventoryRows([string]$Root) {
    $inventory = Import-PowerShellDataFile -Path (Join-Path $Root 'tools\mod-inventory.psd1')
    return @($inventory.Mods)
}

function Import-AuditLedgers([string]$Directory) {
    $rows = @{}
    $files = @(Get-ChildItem -LiteralPath $Directory -Filter 'D*_ledger.tsv' -File | Sort-Object Name)
    if ($files.Count -eq 0) { throw "no D*_ledger.tsv files under $Directory" }
    foreach ($file in $files) {
        $lines = @([IO.File]::ReadAllLines($file.FullName, [Text.Encoding]::UTF8))
        if ($lines.Count -lt 1) { continue }
        $header = $lines[0].Split("`t")
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
            $cells = $lines[$i].Split("`t")
            $row = @{ ledger = $file.Name }
            for ($c = 0; $c -lt $header.Count; $c++) { $row[$header[$c]] = if ($c -lt $cells.Count) { $cells[$c] } else { '' } }
            $number = 0
            if ([int]::TryParse([string]$row['number'], [ref]$number)) { $rows[$number] = $row }
        }
    }
    return $rows
}

# Parse one CURRENT LIVE TEST body. Returns $null when the card cannot be
# parsed (no numbered step or no Expected line).
function ConvertFrom-LiveTestCard([string]$Body) {
    # Field labels appear bold (**Expected:**) or plain (Expected:); the
    # Expected text may start on its own line and run as a list until the
    # next blank line, field label or heading. Lines are kept verbatim.
    $lines = @(($Body -replace "`r`n", "`n" -replace "`r", "`n").Split("`n"))
    $banner = ''; $topology = ''; $steps = New-Object 'System.Collections.Generic.List[string]'
    $expected = New-Object 'System.Collections.Generic.List[string]'; $inExpected = $false
    $field = '^(?:\*\*)?(?<name>Build/banner|Topology|Expected):(?:\*\*)?\s*(?<rest>.*)$'
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($inExpected) {
            $isHeader = $trimmed -match '^\*\*[^*]+:\*\*' -or $trimmed -match '^#' -or $trimmed -match $field
            if ($isHeader -or ($trimmed.Length -eq 0 -and $expected.Count -gt 0)) { $inExpected = $false }
            elseif ($trimmed.Length -gt 0) { $expected.Add($trimmed); continue }
            else { continue }
        }
        if ($trimmed -match $field) {
            $rest = $Matches['rest'].Trim()
            switch ($Matches['name']) {
                'Build/banner' { $banner = $rest }
                'Topology' { $topology = $rest }
                'Expected' { if ($rest.Length -gt 0) { $expected.Add($rest) }; $inExpected = $true }
            }
            continue
        }
        if ($line -match '^\s*[0-9]+\.\s+\S') { $steps.Add($line.TrimEnd()) }
    }
    if ($steps.Count -eq 0 -or $expected.Count -eq 0) { return $null }
    return [pscustomobject]@{
        Banner = $banner; Topology = $topology
        Steps = @($steps.ToArray()); Expected = ($expected.ToArray() -join "`n")
    }
}

# The version written next to one mod in the Build/banner line, or ''.
function Get-BannerVersion([string]$Banner, $Mod, [int]$ModCount) {
    if ([string]::IsNullOrWhiteSpace($Banner)) { return '' }
    $all = [regex]::Matches($Banner, $script:VersionPattern)
    if ($all.Count -eq 0) { return '' }
    $needles = @(('[' + [string]$Mod.ModId + ':'), ('[' + [string]$Mod.ModId + ']'), [string]$Mod.Name)
    $distinct = @($all | ForEach-Object { $_.Value.TrimStart('v') } | Select-Object -Unique)
    if ($distinct.Count -eq 1) {
        # One version (possibly repeated): it belongs to the only mod, or to the mod the banner names.
        if ($ModCount -eq 1) { return [string]$distinct[0] }
        foreach ($needle in $needles) {
            if (-not [string]::IsNullOrWhiteSpace($needle) -and $Banner.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return [string]$distinct[0] }
        }
        return ''
    }
    foreach ($segment in ($Banner -split '[,;]|\band\b')) {
        $versions = [regex]::Matches($segment, $script:VersionPattern)
        if ($versions.Count -ne 1) { continue }
        foreach ($needle in $needles) {
            if (-not [string]::IsNullOrWhiteSpace($needle) -and $segment.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                return $versions[0].Value.TrimStart('v')
            }
        }
    }
    return ''
}

function Get-SpecMods([string[]]$Labels, $LedgerRow, [string]$Class, $Inventory) {
    $dirs = New-Object 'System.Collections.Generic.List[string]'
    $public = $Labels -ccontains 'public-release'
    foreach ($label in $script:LabelDirs.Keys) {
        if ($Labels -cnotcontains $label) { continue }
        $map = $script:LabelDirs[$label]
        if ($map.ContainsKey('Dev')) {
            if (-not $dirs.Contains($map.Dev)) { $dirs.Add($map.Dev) }
            if ($public -and -not $dirs.Contains($map.Stable)) { $dirs.Add($map.Stable) }
        } elseif (-not $dirs.Contains($map.Dir)) { $dirs.Add($map.Dir) }
    }
    $fromLedger = $false
    if ($dirs.Count -eq 0 -and @('R', 'V', 'C') -ccontains $Class -and $null -ne $LedgerRow) {
        $known = @($Inventory | ForEach-Object { [string]$_.Dir })
        foreach ($token in ([string]$LedgerRow['mod'] -split '[^A-Za-z0-9_]+')) {
            if ([string]::IsNullOrWhiteSpace($token)) { continue }
            $dir = if ($known -ccontains $token) { $token } else { $script:LedgerTokenDirs[$token.ToLowerInvariant()] }
            if ($dir -and -not $dirs.Contains($dir)) { $dirs.Add($dir); $fromLedger = $true }
        }
    }
    return [pscustomobject]@{ Dirs = @($dirs.ToArray()); FromLedger = $fromLedger }
}

function New-DraftSpec {
    param([Parameter(Mandatory)]$Issue, $LedgerRow, $Inventory)
    $number = [int]$Issue.number
    $labels = @($Issue.labels | ForEach-Object { [string]$_ })
    $cards = @($Issue.comments | Where-Object { [string]$_.body -match '^\s*## CURRENT LIVE TEST' } |
        Sort-Object { [datetime]$_.created_at })
    $card = if ($cards.Count -gt 0) { $cards[-1] } else { $null }
    $parsed = if ($null -ne $card) { ConvertFrom-LiveTestCard ([string]$card.body) } else { $null }
    $notes = @()

    $class = 'X'
    if ($null -ne $LedgerRow) {
        $cell = [string]$LedgerRow['verification_class']
        foreach ($ch in $cell.ToCharArray()) { if ('USRVCX'.IndexOf($ch) -ge 0) { $class = [string]$ch; break } }
    }
    $onFail = $null
    if ($null -eq $LedgerRow) { $onFail = 'unclassified: triage first' }
    if ($null -ne $card -and $null -eq $parsed) {
        $class = 'X'; $onFail = 'card could not be parsed: triage first'; $notes += 'unparsed-card'
    }

    $modInfo = Get-SpecMods $labels $LedgerRow $class $Inventory
    if (@('R', 'V', 'C') -ccontains $class -and $modInfo.Dirs.Count -eq 0) {
        $class = 'X'; $onFail = 'no mod folder from labels or ledger: triage first'; $notes += 'no-mod'
    }
    if ($modInfo.FromLedger) { $notes += 'mods-from-ledger' }

    $autoCheck = if ($null -ne $LedgerRow) { [string]$LedgerRow['auto_check'] } else { '' }
    $expected = if ($null -ne $parsed) { [string]$parsed.Expected } else { '' }
    $banner = if ($null -ne $parsed) { [string]$parsed.Banner } else { '' }

    $mods = @()
    foreach ($dir in $modInfo.Dirs) {
        $row = @($Inventory | Where-Object { [string]$_.Dir -ceq $dir })[0]
        $mods += [ordered]@{ dir = $dir; min_version = (Get-BannerVersion $banner $row $modInfo.Dirs.Count); settings = $null }
    }
    $assertions = @()
    if ($expected.Length -gt 0) { $assertions += $expected }
    if ($autoCheck.Length -gt 0) { $assertions += $autoCheck }

    $spec = [ordered]@{
        schema = 1
        issue = $number
        class = $class
        status = 'draft'
        vp = $null
        arena = if (@('U', 'S', 'X') -ccontains $class) { 'none' } else { 'unknown' }
    }
    if ($mods.Count -gt 0) { $spec.mods = $mods }
    $spec.cases = @([ordered]@{
        script = ''
        steps = @(if ($null -ne $parsed) { $parsed.Steps })
        assertions = $assertions
        pass_closes = (@('U', 'S', 'R') -ccontains $class)
    })
    if (@('U', 'S') -ccontains $class) { $spec.offline = @([ordered]@{ class = $class; command = ''; expect = $autoCheck }) }
    if (@('V', 'C') -ccontains $class) {
        $humans = @()
        if ($expected.Length -gt 0) { $humans += $expected } elseif ($autoCheck.Length -gt 0) { $humans += $autoCheck }
        if ($class -ceq 'C') { $humans += 'needs two clients' }
        if ($humans.Count -eq 0) { $humans += 'needs eyes or ears' }
        $spec.left_for_humans = $humans
    }
    if ($null -ne $onFail) { $spec.on_fail = $onFail }
    $spec.source = [ordered]@{
        card_comment_id = if ($null -ne $card) { [long]$card.id } else { $null }
        card_date = if ($null -ne $card) { ([datetime]$card.created_at).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) } else { $null }
        ledger = if ($null -ne $LedgerRow) { [string]$LedgerRow['ledger'] } else { $null }
    }
    return [pscustomobject]@{ Spec = $spec; HasCard = ($null -ne $card); Notes = $notes }
}

function ConvertTo-SpecJson($Spec) {
    return (($Spec | ConvertTo-Json -Depth 8) -replace "`r`n", "`n") + "`n"
}

function Get-OpenIssuesOnline([string]$Repo) {
    $issues = @()
    $lines = @(& gh api --paginate "repos/$Repo/issues?state=open&per_page=100" --jq '.[] | select(.pull_request == null) | {number, labels: [.labels[].name]}')
    if ($LASTEXITCODE -ne 0) { throw "gh api issues failed (exit $LASTEXITCODE)" }
    foreach ($line in $lines) {
        $issue = $line | ConvertFrom-Json
        $commentLines = @(& gh api --paginate "repos/$Repo/issues/$($issue.number)/comments?per_page=100" --jq '.[] | select(.body | test("^\\s*## CURRENT LIVE TEST")) | {id, created_at, body}')
        if ($LASTEXITCODE -ne 0) { throw "gh api comments for #$($issue.number) failed (exit $LASTEXITCODE)" }
        $comments = @($commentLines | ForEach-Object { $_ | ConvertFrom-Json })
        $issues += [pscustomobject]@{ number = [int]$issue.number; labels = @($issue.labels); comments = $comments }
    }
    return $issues
}

function Invoke-ConvertCards {
    param($Issues, [string]$Ledgers, [string]$Out, [string]$Root)
    $inventory = Get-InventoryRows $Root
    $ledger = Import-AuditLedgers $Ledgers
    [void][IO.Directory]::CreateDirectory($Out)
    $written = 0; $keptReady = 0; $noCard = @(); $noLedger = @(); $flagged = @()
    foreach ($issue in @($Issues | Sort-Object { [int]$_.number })) {
        $number = [int]$issue.number
        $path = Join-Path $Out ("issue_{0}.json" -f $number)
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            try { $existing = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json } catch { $existing = $null }
            if ($null -ne $existing -and [string]$existing.status -ceq 'ready') { $keptReady++; continue }
        }
        $row = if ($ledger.ContainsKey($number)) { $ledger[$number] } else { $null }
        $result = New-DraftSpec -Issue $issue -LedgerRow $row -Inventory $inventory
        [IO.File]::WriteAllText($path, (ConvertTo-SpecJson $result.Spec), (New-Object Text.UTF8Encoding($false)))
        $written++
        if (-not $result.HasCard) { $noCard += $number }
        if ($null -eq $row) { $noLedger += $number }
        foreach ($note in $result.Notes) { $flagged += "#$number $note" }
    }
    return [pscustomobject]@{
        Open = @($Issues).Count; Written = $written; KeptReady = $keptReady
        NoCard = $noCard; NoLedger = $noLedger; Flagged = $flagged
    }
}

function Write-ConvertSummary($Report) {
    Write-Host ("open issues: {0}, specs written: {1}, without card: {2}, without ledger row: {3}" -f `
        $Report.Open, $Report.Written, $Report.NoCard.Count, $Report.NoLedger.Count)
    if ($Report.KeptReady -gt 0) { Write-Host "ready specs kept: $($Report.KeptReady)" }
    if ($Report.NoLedger.Count -gt 0) { Write-Host ("without ledger row: " + (($Report.NoLedger | ForEach-Object { "#$_" }) -join ' ')) }
    foreach ($line in $Report.Flagged) { Write-Host "flag: $line" }
}

function Invoke-ConvertSelfTest([string]$Root) {
    $fixture = Join-Path $Root 'qa\_test_fixtures\verify_specs\convert'
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('vt2-convert-cards-' + [guid]::NewGuid().ToString('N'))
    $failures = @()
    try {
        $issues = [IO.File]::ReadAllText((Join-Path $fixture 'issues.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
        # A ready spec must survive a rerun.
        [void][IO.Directory]::CreateDirectory($temp)
        $readyText = '{"schema":1,"issue":9203,"class":"S","status":"ready","vp":null,"arena":"none","offline":[{"class":"S","command":"pwsh -NoProfile -File qa/check_verify_specs.ps1","expect":"exit 0"}]}' + "`n"
        [IO.File]::WriteAllText((Join-Path $temp 'issue_9203.json'), $readyText)
        $report = Invoke-ConvertCards -Issues $issues -Ledgers (Join-Path $fixture 'ledgers') -Out $temp -Root $Root
        if ($report.Open -ne 3 -or $report.Written -ne 2 -or $report.KeptReady -ne 1) { $failures += "counts: open=$($report.Open) written=$($report.Written) kept=$($report.KeptReady)" }
        if (([IO.File]::ReadAllText((Join-Path $temp 'issue_9203.json'))) -cne $readyText) { $failures += 'a ready spec was overwritten' }

        $withCard = [IO.File]::ReadAllText((Join-Path $temp 'issue_9201.json')) | ConvertFrom-Json
        if ($withCard.class -cne 'R' -or $withCard.status -cne 'draft' -or $withCard.arena -cne 'unknown') { $failures += 'card issue: class/status/arena' }
        if (@($withCard.mods).Count -ne 2 -or $withCard.mods[0].dir -cne 'general_tweaker_dev' -or $withCard.mods[1].dir -cne 'general_tweaker') { $failures += 'card issue: dev then stable folder for public-release' }
        if ($withCard.mods[0].min_version -cne '0.2.279-dev') { $failures += "card issue: min_version '$($withCard.mods[0].min_version)'" }
        if (@($withCard.cases[0].steps).Count -ne 2 -or $withCard.cases[0].steps[0] -cne '1. Open General Tweaker in the Mod Tweaker menu.') { $failures += 'card issue: steps not verbatim' }
        if ($withCard.cases[0].assertions[0] -cne ("- The game does not crash.`n- The key works.") -or $withCard.cases[0].assertions[1] -cne 'fixture auto check') { $failures += 'card issue: assertions' }
        if ($withCard.cases[0].pass_closes -ne $true -or $withCard.source.card_comment_id -ne 1001 -or $withCard.source.ledger -cne 'D9_ledger.tsv') { $failures += 'card issue: pass_closes/source' }

        $noCard = [IO.File]::ReadAllText((Join-Path $temp 'issue_9202.json')) | ConvertFrom-Json
        if ($noCard.class -cne 'X' -or $noCard.on_fail -cne 'unclassified: triage first' -or $noCard.arena -cne 'none') { $failures += 'no-ledger issue: class X with triage note' }
        if ($null -ne $noCard.source.card_comment_id -or @($noCard.cases[0].steps).Count -ne 0) { $failures += 'no-card issue: invented card data' }
        if ($report.NoCard.Count -ne 1 -or $report.NoLedger.Count -ne 1) { $failures += "summary: without card $($report.NoCard.Count), without ledger $($report.NoLedger.Count)" }

    } catch {
        $failures += "crash: $($_.Exception.Message)"
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
    if ($failures.Count -gt 0) {
        Write-Host '[convert-cards -SelfTest] FAILED' -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
        return 2
    }
    Write-Host '[convert-cards -SelfTest] OK -- card and no-card fixtures, ready spec kept.' -ForegroundColor Green
    return 0
}

if ($SelfTest) { exit (Invoke-ConvertSelfTest $repoRoot) }

if ([string]::IsNullOrWhiteSpace($LedgerDir)) { $LedgerDir = Join-Path $repoRoot 'docs\audits\2026-11-13_FORMAL_AUDIT\evidence\ledgers' }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $repoRoot 'qa\specs' }
if (-not (Test-Path -LiteralPath $LedgerDir -PathType Container)) {
    Write-Host "[convert-cards] ERROR - ledger directory not found: $LedgerDir" -ForegroundColor Red
    exit 2
}
try {
    $issues = if ($IssuesJsonPath) {
        [IO.File]::ReadAllText($IssuesJsonPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
    } else { Get-OpenIssuesOnline $Repository }
    $report = Invoke-ConvertCards -Issues $issues -Ledgers $LedgerDir -Out $OutDir -Root $repoRoot
} catch {
    Write-Host "[convert-cards] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
Write-ConvertSummary $report
exit 0
