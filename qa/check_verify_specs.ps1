# check_verify_specs.ps1 - validate every verification spec in qa/specs/.
#
# One JSON file per issue (qa/specs/issue_<issue>.json) states how that issue is
# decided (WP-G-04). The field table is qa/specs/README.md; spec.schema.json is
# the editor schema. This check validates by hand (no Test-Json: it is absent
# from Windows PowerShell 5.1) and never calls GitHub.
#
# Rules:
#   R1 the file name matches `issue`
#   R2 required fields present, enum values and types valid, no unknown
#      top-level key
#   R3 class-conditional requirements (mods for R/V/C, cases for R/C,
#      offline for U/S, left_for_humans for V/C; arena none only for U/S/X)
#   R4 every mods[].dir is a Dir of tools/mod-inventory.psd1
#   R5 status ready: every cases[].script is a file under qa/runtime/, every
#      offline[].command is non-empty and its first token that ends in .ps1 or
#      .lua exists, arena is not unknown
#   R6 status draft: empty script and command strings are allowed
#
# Exit codes: 0 = every spec valid (or no spec files), 2 = errors.
# ASCII only; Windows PowerShell 5.1 and PowerShell 7.

[CmdletBinding()]
param(
    [string]$RepoRoot = '',
    [switch]$Quiet,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$script:SpecTopLevelKeys = @(
    'schema', 'issue', 'class', 'status', 'vp', 'arena', 'mods', 'boots',
    'depends_on', 'setup', 'cases', 'offline', 'rt_checks', 'left_for_humans',
    'on_fail', 'source'
)
$script:SpecRequiredKeys = @('schema', 'issue', 'class', 'status', 'vp', 'arena')
$script:SpecClasses = @('U', 'S', 'R', 'V', 'C', 'X')

function Test-SpecInteger($Value) {
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte])
}

function Test-SpecArray($Value) {
    return ($Value -is [System.Array])
}

function Test-SpecObject($Value) {
    return ($Value -is [System.Management.Automation.PSCustomObject])
}

function Get-SpecPropertyNames($Object) {
    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Test-SpecHasProperty($Object, [string]$Name) {
    return (@($Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name }).Count -eq 1)
}

function Get-VerifySpecInventoryDirs {
    param([Parameter(Mandatory)][string]$Root)
    $inventoryPath = Join-Path $Root 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "tools/mod-inventory.psd1 is missing under $Root"
    }
    $inventory = Import-PowerShellDataFile -Path $inventoryPath
    return @($inventory.Mods | ForEach-Object { [string]$_.Dir })
}

function Test-SpecRepoFile {
    param([string]$Root, [string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
    $norm = $RelativePath.Trim().Replace('\', '/')
    if ($norm.StartsWith('/') -or $norm -match '^[A-Za-z]:' -or ($norm -split '/') -contains '..') { return $false }
    return (Test-Path -LiteralPath (Join-Path $Root $norm) -PathType Leaf)
}

# Validate one parsed spec. Returns an array of error strings (empty = valid).
function Test-VerifySpec {
    param(
        [Parameter(Mandatory)]$Spec,
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$InventoryDirs
    )
    $errors = New-Object 'System.Collections.Generic.List[string]'
    if (-not (Test-SpecObject $Spec)) {
        $errors.Add('R2 the top level is not a JSON object') | Out-Null
        return @($errors)
    }
    $names = Get-SpecPropertyNames $Spec
    foreach ($name in $names) {
        if ($script:SpecTopLevelKeys -cnotcontains $name) { $errors.Add("R2 unknown top-level key '$name'") | Out-Null }
    }
    foreach ($name in $script:SpecRequiredKeys) {
        if ($names -cnotcontains $name) { $errors.Add("R2 required field '$name' is missing") | Out-Null }
    }

    $issue = $Spec.issue
    if ($names -ccontains 'schema' -and -not ((Test-SpecInteger $Spec.schema) -and [long]$Spec.schema -eq 1)) {
        $errors.Add('R2 schema must be the integer 1') | Out-Null
    }
    $issueValid = $names -ccontains 'issue' -and (Test-SpecInteger $issue) -and [long]$issue -ge 1
    if ($names -ccontains 'issue' -and -not $issueValid) { $errors.Add('R2 issue must be a positive integer') | Out-Null }
    if ($issueValid) {
        $expectedName = 'issue_' + ([long]$issue).ToString([Globalization.CultureInfo]::InvariantCulture) + '.json'
        if ($FileName -cne $expectedName) { $errors.Add("R1 file name '$FileName' does not match issue $issue (expected $expectedName)") | Out-Null }
    } elseif ($FileName -cnotmatch '^issue_[1-9][0-9]*\.json$') {
        $errors.Add("R1 file name '$FileName' is not issue_<issue>.json") | Out-Null
    }

    $class = [string]$Spec.class
    $classValid = ($Spec.class -is [string]) -and ($script:SpecClasses -ccontains $class)
    if ($names -ccontains 'class' -and -not $classValid) { $errors.Add('R2 class must be one of U S R V C X') | Out-Null }
    $status = [string]$Spec.status
    $statusValid = ($Spec.status -is [string]) -and (@('draft', 'ready') -ccontains $status)
    if ($names -ccontains 'status' -and -not $statusValid) { $errors.Add('R2 status must be draft or ready') | Out-Null }
    if ($names -ccontains 'vp' -and $null -ne $Spec.vp -and
            -not (($Spec.vp -is [string]) -and ([string]$Spec.vp -cmatch '^VP-[A-Z0-9]+-[0-9]{2}$'))) {
        $errors.Add('R2 vp must be VP-<BUCKET>-<NN> or null') | Out-Null
    }
    $arena = [string]$Spec.arena
    $arenaValid = ($Spec.arena -is [string]) -and ($arena -cmatch '^(none|boot|keep|deus|coop|unknown|mission:[A-Za-z0-9_]+)$')
    if ($names -ccontains 'arena' -and -not $arenaValid) {
        $errors.Add('R2 arena must be none, boot, keep, deus, coop, unknown or mission:<level_key>') | Out-Null
    }

    # Optional fields: types when present.
    $mods = @()
    if ($names -ccontains 'mods') {
        if (-not (Test-SpecArray $Spec.mods)) { $errors.Add('R2 mods must be an array') | Out-Null }
        else {
            $mods = @($Spec.mods)
            foreach ($mod in $mods) {
                if (-not (Test-SpecObject $mod) -or -not (Test-SpecHasProperty $mod 'dir') -or -not ($mod.dir -is [string]) -or
                        [string]::IsNullOrWhiteSpace([string]$mod.dir)) {
                    $errors.Add('R2 every mods[] entry needs a string dir') | Out-Null
                    continue
                }
                foreach ($key in (Get-SpecPropertyNames $mod)) {
                    if (@('dir', 'min_version', 'settings') -cnotcontains $key) { $errors.Add("R2 unknown mods[] key '$key'") | Out-Null }
                }
                if ((Test-SpecHasProperty $mod 'min_version') -and $null -ne $mod.min_version -and -not ($mod.min_version -is [string])) {
                    $errors.Add('R2 mods[].min_version must be a string or null') | Out-Null
                }
                if ((Test-SpecHasProperty $mod 'settings') -and $null -ne $mod.settings -and -not (Test-SpecObject $mod.settings)) {
                    $errors.Add('R2 mods[].settings must be an object or null') | Out-Null
                }
                if ($InventoryDirs -cnotcontains [string]$mod.dir) {
                    $errors.Add("R4 mods[].dir '$($mod.dir)' is not a Dir of tools/mod-inventory.psd1") | Out-Null
                }
            }
        }
    }
    if ($names -ccontains 'boots' -and -not ((Test-SpecInteger $Spec.boots) -and [long]$Spec.boots -ge 0)) {
        $errors.Add('R2 boots must be an integer, 0 or more') | Out-Null
    }
    if ($names -ccontains 'depends_on') {
        if (-not (Test-SpecArray $Spec.depends_on) -or
                @($Spec.depends_on | Where-Object { -not ($_ -is [string]) -or [string]$_ -cnotmatch '^WP-[A-Z0-9]+-[0-9]{2}$' }).Count -gt 0) {
            $errors.Add('R2 depends_on must be an array of WP ids') | Out-Null
        }
    }
    foreach ($textKey in @('setup', 'on_fail')) {
        if ($names -ccontains $textKey -and -not ($Spec.$textKey -is [string])) { $errors.Add("R2 $textKey must be a string") | Out-Null }
    }
    $cases = @()
    if ($names -ccontains 'cases') {
        if (-not (Test-SpecArray $Spec.cases)) { $errors.Add('R2 cases must be an array') | Out-Null }
        else {
            $cases = @($Spec.cases)
            foreach ($case in $cases) {
                $ok = (Test-SpecObject $case) -and
                    (Test-SpecHasProperty $case 'script') -and ($case.script -is [string]) -and
                    (Test-SpecHasProperty $case 'steps') -and (Test-SpecArray $case.steps) -and
                    (Test-SpecHasProperty $case 'assertions') -and (Test-SpecArray $case.assertions) -and
                    (Test-SpecHasProperty $case 'pass_closes') -and ($case.pass_closes -is [bool])
                if (-not $ok) { $errors.Add('R2 every cases[] entry needs script (string), steps [], assertions [], pass_closes (bool)') | Out-Null }
            }
        }
    }
    $offline = @()
    if ($names -ccontains 'offline') {
        if (-not (Test-SpecArray $Spec.offline)) { $errors.Add('R2 offline must be an array') | Out-Null }
        else {
            $offline = @($Spec.offline)
            foreach ($entry in $offline) {
                $ok = (Test-SpecObject $entry) -and
                    (Test-SpecHasProperty $entry 'class') -and (@('U', 'S') -ccontains [string]$entry.class) -and
                    (Test-SpecHasProperty $entry 'command') -and ($entry.command -is [string]) -and
                    (Test-SpecHasProperty $entry 'expect') -and ($entry.expect -is [string])
                if (-not $ok) { $errors.Add('R2 every offline[] entry needs class (U or S), command (string), expect (string)') | Out-Null }
            }
        }
    }
    if ($names -ccontains 'rt_checks') {
        if (-not (Test-SpecArray $Spec.rt_checks)) { $errors.Add('R2 rt_checks must be an array') | Out-Null }
        else {
            foreach ($check in @($Spec.rt_checks)) {
                $ok = (Test-SpecObject $check) -and
                    ($check.mod -is [string]) -and -not [string]::IsNullOrWhiteSpace([string]$check.mod) -and
                    ($check.check -is [string]) -and -not [string]::IsNullOrWhiteSpace([string]$check.check) -and
                    ($check.behavioural -is [bool])
                if (-not $ok) { $errors.Add('R2 every rt_checks[] entry needs mod, check (strings) and behavioural (bool)') | Out-Null }
            }
        }
    }
    $humans = @()
    if ($names -ccontains 'left_for_humans') {
        if (-not (Test-SpecArray $Spec.left_for_humans) -or
                @($Spec.left_for_humans | Where-Object { -not ($_ -is [string]) }).Count -gt 0) {
            $errors.Add('R2 left_for_humans must be an array of strings') | Out-Null
        } else { $humans = @($Spec.left_for_humans) }
    }
    if ($names -ccontains 'source') {
        $source = $Spec.source
        $ok = (Test-SpecObject $source)
        if ($ok) {
            foreach ($key in @('card_comment_id', 'card_date', 'ledger')) {
                if (-not (Test-SpecHasProperty $source $key)) { $ok = $false }
            }
            foreach ($key in (Get-SpecPropertyNames $source)) {
                if (@('card_comment_id', 'card_date', 'ledger') -cnotcontains $key) { $ok = $false }
            }
        }
        if (-not $ok) { $errors.Add('R2 source must be { card_comment_id, card_date, ledger }') | Out-Null }
    }

    # R3 class-conditional requirements.
    if ($classValid) {
        if (@('R', 'V', 'C') -ccontains $class -and $mods.Count -eq 0) { $errors.Add("R3 class $class requires a non-empty mods array") | Out-Null }
        if (@('R', 'C') -ccontains $class -and $cases.Count -eq 0) { $errors.Add("R3 class $class requires a non-empty cases array") | Out-Null }
        if (@('U', 'S') -ccontains $class -and $offline.Count -eq 0) { $errors.Add("R3 class $class requires a non-empty offline array") | Out-Null }
        if (@('V', 'C') -ccontains $class -and $humans.Count -eq 0) { $errors.Add("R3 class $class requires a non-empty left_for_humans array") | Out-Null }
        if ($arenaValid -and $arena -ceq 'none' -and @('U', 'S', 'X') -cnotcontains $class) {
            $errors.Add("R3 arena none is only for class U, S or X (class $class)") | Out-Null
        }
    }

    # R5 / R6 status-conditional requirements.
    if ($statusValid -and $status -ceq 'ready') {
        if ($arenaValid -and $arena -ceq 'unknown') { $errors.Add('R5 a ready spec cannot have arena unknown') | Out-Null }
        foreach ($case in $cases) {
            if (-not (Test-SpecObject $case) -or -not ($case.script -is [string])) { continue }
            $scriptPath = ([string]$case.script).Trim().Replace('\', '/')
            if (-not $scriptPath.StartsWith('qa/runtime/', [StringComparison]::Ordinal) -or -not (Test-SpecRepoFile $Root $scriptPath)) {
                $errors.Add("R5 cases[].script '$($case.script)' is not a file under qa/runtime/") | Out-Null
            }
        }
        foreach ($entry in $offline) {
            if (-not (Test-SpecObject $entry) -or -not ($entry.command -is [string])) { continue }
            $command = ([string]$entry.command).Trim()
            if ($command.Length -eq 0) { $errors.Add('R5 offline[].command is empty in a ready spec') | Out-Null; continue }
            $fileToken = $null
            foreach ($token in ($command -split '\s+')) {
                $candidate = $token.Trim('"', "'")
                if ($candidate -match '\.(ps1|lua)$') { $fileToken = $candidate; break }
            }
            if ($null -ne $fileToken -and -not (Test-SpecRepoFile $Root $fileToken)) {
                $errors.Add("R5 offline[].command names '$fileToken', which does not exist") | Out-Null
            }
        }
    }
    return @($errors)
}

function Read-VerifySpecFile {
    param([Parameter(Mandatory)][string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return ($text | ConvertFrom-Json)
}

function Invoke-VerifySpecDirectory {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string[]]$InventoryDirs)
    $results = @()
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $results }
    $files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.json' -File | Where-Object { $_.Name -cne 'spec.schema.json' } | Sort-Object Name)
    foreach ($file in $files) {
        try {
            $spec = Read-VerifySpecFile -Path $file.FullName
            $errs = @(Test-VerifySpec -Spec $spec -FileName $file.Name -Root $Root -InventoryDirs $InventoryDirs)
        } catch {
            $errs = @("R2 not valid JSON: $($_.Exception.Message)")
        }
        $results += [pscustomobject]@{ Name = $file.Name; Errors = $errs }
    }
    return $results
}

function Invoke-VerifySpecsSelfTest {
    param([Parameter(Mandatory)][string]$Root)
    $fixtureRoot = Join-Path $Root 'qa\_test_fixtures\verify_specs'
    $failures = @()
    $dirs = Get-VerifySpecInventoryDirs -Root $Root
    $valid = @(Invoke-VerifySpecDirectory -Directory (Join-Path $fixtureRoot 'valid') -Root $Root -InventoryDirs $dirs)
    $invalid = @(Invoke-VerifySpecDirectory -Directory (Join-Path $fixtureRoot 'invalid') -Root $Root -InventoryDirs $dirs)
    if ($valid.Count -ne 2) { $failures += "expected 2 valid fixtures, found $($valid.Count)" }
    foreach ($result in $valid) {
        if ($result.Errors.Count -ne 0) { $failures += "valid fixture $($result.Name) was rejected: $($result.Errors -join '; ')" }
        else { Write-Host "  [PASS] accepted $($result.Name)" -ForegroundColor Green }
    }
    # Each invalid fixture must fail for its own planted reason.
    $expected = @{
        'issue_9103.json' = 'R1 file name'
        'issue_9104.json' = 'R3 class R requires a non-empty cases array'
        'issue_9105.json' = 'R4 mods[].dir'
        'issue_9106.json' = 'R5 cases[].script'
    }
    if ($invalid.Count -ne $expected.Count) { $failures += "expected $($expected.Count) invalid fixtures, found $($invalid.Count)" }
    foreach ($result in $invalid) {
        $want = $expected[$result.Name]
        if (-not $want) { $failures += "unexpected invalid fixture $($result.Name)"; continue }
        $hit = @($result.Errors | Where-Object { $_.StartsWith($want, [StringComparison]::Ordinal) })
        # Exactly one error: the fixture is otherwise valid, so only the planted rule fires.
        if ($hit.Count -ne 1 -or $result.Errors.Count -ne 1) { $failures += "invalid fixture $($result.Name) was not rejected by '$want' alone (errors: $($result.Errors -join '; '))" }
        else { Write-Host "  [PASS] rejected $($result.Name): $($hit[0])" -ForegroundColor Green }
    }
    if ($failures.Count -gt 0) {
        Write-Host '[check_verify_specs -SelfTest] FAILED' -ForegroundColor Red
        foreach ($failure in $failures) { Write-Host "  X $failure" -ForegroundColor Red }
        return 2
    }
    Write-Host '[check_verify_specs -SelfTest] OK -- 2 fixtures accepted, 4 rejected.' -ForegroundColor Green
    return 0
}

# Windows PowerShell 5.1 can leave $PSScriptRoot empty in a parameter default
# (#1721), so the default root is resolved here.
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = Split-Path $PSScriptRoot -Parent }
$root = (Resolve-Path -LiteralPath $RepoRoot).Path
if ($SelfTest) { exit (Invoke-VerifySpecsSelfTest -Root $root) }

try {
    $inventoryDirs = Get-VerifySpecInventoryDirs -Root $root
} catch {
    Write-Host "[check_verify_specs] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
$results = @(Invoke-VerifySpecDirectory -Directory (Join-Path $root 'qa\specs') -Root $root -InventoryDirs $inventoryDirs)
$bad = @($results | Where-Object { $_.Errors.Count -gt 0 })
if ($bad.Count -gt 0) {
    Write-Host "[check_verify_specs] ERRORS in $($bad.Count) of $($results.Count) spec(s):" -ForegroundColor Red
    foreach ($result in $bad) {
        foreach ($message in $result.Errors) { Write-Host "  X qa/specs/$($result.Name): $message" -ForegroundColor Red }
    }
    exit 2
}
if (-not $Quiet) { Write-Host "[check_verify_specs] OK - $($results.Count) specs" -ForegroundColor Green }
exit 0
