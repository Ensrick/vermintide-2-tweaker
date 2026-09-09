# #1562: execute the real checker and exact BuildOnly post-build statement.
# Only filesystem inventory and the external unpacker boundary are fixture data.
# No real dictionary, compiled-resource validation, launcher, or network is used.
[CmdletBinding()]
param([switch]$Quiet)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$script:assertions = 0
function Check([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "Custom-unit reporting: $Name" }
    $script:assertions++
}

$ship = [IO.File]::ReadAllText((Join-Path $repo 'tools/ship/ship.ps1'))
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($ship, [ref]$tokens, [ref]$parseErrors)
Check (@($parseErrors).Count -eq 0) 'ship parses'
$blocks = @($ast.FindAll({ param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
    $node.Clauses[0].Item1.Extent.Text -ceq '$BuildOnly' -and
    $node.Extent.Text.Contains('& $unitReachabilityGate')
}, $true))
Check ($blocks.Count -eq 1) 'one actual BuildOnly post-build gate owner'

$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/'))
$root = Join-Path $temp ('vt2-unit-reporting-' + [guid]::NewGuid().ToString('N'))
$files = New-Object 'System.Collections.Generic.List[string]'
$directories = @($root, (Join-Path $root 'qa'), (Join-Path $root 'tools'),
    (Join-Path $root 'fixture_mod'), (Join-Path $root 'fixture_mod/units'),
    (Join-Path $root 'fixture_mod/bundleV2'))
function Write-Fixture([string]$Relative, [string]$Text) {
    $path = Join-Path $root $Relative
    [IO.File]::WriteAllText($path, $Text, (New-Object Text.UTF8Encoding($false)))
    if (-not $files.Contains($path)) { $files.Add($path) }
}
try {
    foreach ($directory in $directories) { [void][IO.Directory]::CreateDirectory($directory) }
    # Copy the entire production checker byte-for-byte, never its implementation.
    $checker = Join-Path $root 'qa/check_custom_unit_bundle_reachability.ps1'
    [IO.File]::Copy((Join-Path $repo 'qa/check_custom_unit_bundle_reachability.ps1'), $checker)
    $files.Add($checker)
    Write-Fixture 'post-build.ps1' $blocks[0].Extent.Text
    foreach ($gate in @('check_build_receipts', 'check_release_bundle_atomicity', 'check_cwv_old_musket_compiled_contract')) {
        Write-Fixture ("qa/$gate.ps1") ('param([string]$Mod,[switch]$Quiet)' + "`n" +
            "Write-Host 'FIXTURE-GATE $gate'" + "`nexit 0`n")
    }
    Write-Fixture 'fixture_mod/fixture_mod.mod' 'packages = { "fixture/root" }'
    Write-Fixture 'fixture_mod/units/example.unit' 'unit = {}'
    Write-Fixture 'fixture_mod/bundleV2/aaaaaaaaaaaaaaaa.mod_bundle' 'private dependency-boundary fixture, not compiled data'

    foreach ($mode in @('MissingUnpacker', 'MissingDictionary', 'Reachable', 'Unreachable', 'Malformed', 'BadHash', 'NotApplicable')) {
        $inventory = "@{ Mods = @(@{ Dir = 'fixture_mod' }) }"
        if ($mode -ceq 'NotApplicable') { $inventory = '@{ Mods = @() }' }
        Write-Fixture 'tools/mod-inventory.psd1' $inventory
        foreach ($surface in @('Checker', 'BuildOnly')) {
            foreach ($quietCheck in @($false, $true)) {
                $result = & {
                    param($Case, $Surface, $CheckQuiet, $Root)
                    # Functions and environment overrides stay in this private scope;
                    # environment values are restored even when the real checker throws.
                    function Test-Path {
                        param([string]$LiteralPath, [string]$PathType)
                        if ($LiteralPath -ceq 'fixture-unpacker') { return $Case -cne 'MissingUnpacker' }
                        if ($LiteralPath -ceq 'fixture-dictionary') { return $Case -cne 'MissingDictionary' }
                        return Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType $PathType
                    }
                    function fixture-unpacker {
                        # Production Invoke-Unpacker owns argv, status, and parsing.
                        Check (($args[0..3] -join '|') -ceq '--dict|NUL|--zstd-dict|fixture-dictionary') 'unpacker argv retained'
                        $global:LASTEXITCODE = 0
                        if ($args[4] -ceq 'murmur') {
                            if ($Case -ceq 'BadHash') { return 'no hash result' }
                            if ($args[6] -ceq 'fixture/root') { return 'aaaaaaaaaaaaaaaa' }
                            Check ($args[6] -ceq 'units/example') 'exact authored unit hashed'
                            return 'bbbbbbbbbbbbbbbb'
                        }
                        Check ($args[4] -ceq 'list') 'only list/hash boundary used'
                        if ($Case -ceq 'Malformed') { $global:LASTEXITCODE = 7; return 'planted malformed bundle' }
                        if ($Case -ceq 'Unreachable') { return 'cccccccccccccccc.unit' }
                        return 'bbbbbbbbbbbbbbbb.unit'
                    }
                    function Fail([string]$Message) { throw $Message }
                    $oldUnpacker = $env:VT2_BUNDLE_UNPACKER
                    $oldDictionary = $env:VT2_COMPRESSION_DICTIONARY
                    $oldExit = $global:LASTEXITCODE
                    try {
                        $env:VT2_BUNDLE_UNPACKER = 'fixture-unpacker'
                        $env:VT2_COMPRESSION_DICTIONARY = 'fixture-dictionary'
                        $global:LASTEXITCODE = 0
                        $repoRoot = $Root; $BuildOnly = $true; $Mod = 'character_weapon_variants'
                        $output = New-Object 'System.Collections.Generic.List[string]'
                        $errorText = $null
                        try {
                            if ($Surface -ceq 'Checker') {
                                & (Join-Path $Root 'qa/check_custom_unit_bundle_reachability.ps1') -Quiet:$CheckQuiet 6>&1 |
                                    ForEach-Object { $output.Add([string]$_) }
                            } else {
                                & (Join-Path $Root 'post-build.ps1') 6>&1 | ForEach-Object { $output.Add([string]$_) }
                            }
                        } catch { $errorText = $_.Exception.Message }
                        [pscustomobject]@{ Text = $output -join "`n"; Code = $global:LASTEXITCODE; Error = $errorText }
                    } finally {
                        $env:VT2_BUNDLE_UNPACKER = $oldUnpacker
                        $env:VT2_COMPRESSION_DICTIONARY = $oldDictionary
                        $global:LASTEXITCODE = $oldExit
                    }
                } $mode $surface $quietCheck $root
                $label = "$mode/$surface/quiet=$quietCheck"
                if ($mode -in @('MissingUnpacker', 'MissingDictionary')) {
                    Check ($null -eq $result.Error -and $result.Code -eq 0) "$label optional skip remains exit zero"
                    Check ($result.Text -match '\[check_custom_unit_bundle_reachability\] SKIP -') "$label skip remains visible"
                    $reason = if ($mode -ceq 'MissingUnpacker') { 'bundle unpacker unavailable' } else { 'compression.dictionary unavailable' }
                    Check ($result.Text.Contains($reason)) "$label precise dependency reason"
                    Check ($result.Text -notmatch '\[check_custom_unit_bundle_reachability\] (?:OK|PASS)') "$label never reports resource pass"
                } elseif ($mode -ceq 'Unreachable') {
                    Check ($result.Code -eq 2) "$label resource failure remains exit two"
                    Check ($result.Text -match '\] FAIL - 1 unreachable') "$label retains resource failure"
                    Check ($result.Text.Contains('absent from every compiled bundle')) "$label retains actual reachability assertion"
                } elseif ($mode -in @('Malformed', 'BadHash')) {
                    $reason = if ($mode -ceq 'Malformed') { 'bundle unpacker failed (7)' } else { 'no Murmur64 result' }
                    Check ($null -ne $result.Error -and $result.Error.Contains($reason)) "$label original tool error propagates"
                } else {
                    Check ($null -eq $result.Error -and $result.Code -eq 0) "$label succeeds"
                    if ($surface -ceq 'BuildOnly' -or -not $quietCheck) {
                        $expected = if ($mode -ceq 'NotApplicable') { 'NOT APPLICABLE - no authored custom unit resources' } else { 'PASS - 1 custom unit resource(s)' }
                        Check ($result.Text.Contains($expected)) "$label exact applicable outcome"
                    }
                }
                if ($surface -ceq 'BuildOnly') {
                    if ($mode -in @('Unreachable', 'Malformed', 'BadHash')) {
                        Check (-not $result.Text.Contains('BUILD-ONLY COMPLETE')) "$label failure cannot print completion"
                        Check (-not $result.Text.Contains('FIXTURE-GATE check_cwv_old_musket_compiled_contract')) "$label failure stops next gate"
                    } else {
                        Check ($result.Text.Contains('FIXTURE-GATE check_cwv_old_musket_compiled_contract')) "$label applicable next gate still runs"
                        Check ($result.Text.Contains('BUILD-ONLY COMPLETE')) "$label completion retained"
                        Check ($result.Text.Contains('SKIP is not verification')) "$label footer explicitly qualifies optional result"
                        Check (-not $result.Text.Contains('atomicity, custom-unit reachability, and applicable compiled contracts verified')) "$label no false aggregate claim"
                    }
                }
            }
        }
    }
} finally {
    # Validate every exact owned path before deleting anything; no recursive delete.
    foreach ($path in @($files) + $directories) {
        $full = [IO.Path]::GetFullPath($path)
        if (-not $full.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and $full -cne $root) {
            throw 'Fixture cleanup escaped private root.'
        }
        if (Microsoft.PowerShell.Management\Test-Path -LiteralPath $full) {
            $entry = Get-Item -LiteralPath $full -Force
            while ($null -ne $entry) {
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Fixture cleanup refuses reparse paths.' }
                $entry = $entry.Parent
            }
        }
    }
    foreach ($path in $files) { if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) } }
    for ($i = $directories.Count - 1; $i -ge 0; $i--) {
        if ([IO.Directory]::Exists($directories[$i])) { [IO.Directory]::Delete($directories[$i], $false) }
    }
}
if (-not $Quiet) { Write-Host "[check_custom_unit_gate_reporting] PASS - $script:assertions actual checker/BuildOnly assertions" -ForegroundColor Green }
exit 0
