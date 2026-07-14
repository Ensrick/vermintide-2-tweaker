# check_translation_readiness.ps1 -- versioned cross-mod translation census (#444).
#
# Diagnostic mode (default) reports coverage but succeeds while #444 is blocked on
# stable English/1.0 releases. -Strict is the future release gate: missing target
# strings or Lua-format-token drift fails with exit 2.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$Strict,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$AuditVersion = '1.0.0'
$TargetLanguages = @('fr', 'pl', 'es', 'tr', 'de', 'br-pt', 'ru')
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$repoRoot = (Resolve-Path $RepoRoot).Path

function Find-LocFiles([string]$root) {
    Get-ChildItem -Path $root -Filter '*_localization.lua' -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $p = $_.FullName
            $p -notlike '*\_archive\*' -and $p -notlike '*\bundleV2\*' `
                -and $p -notlike '*\.build\*' -and $p -notlike '*\.temp\*' `
                -and $p -notlike '*\.release-stage\*' -and $p -notlike '*\tweaker\*' `
                -and $p -notlike '*\sample_*\*'
        }
}

function Get-FormatSignature([string]$value) {
    if ($null -eq $value) { return '' }
    $tokens = @()
    $pattern = '%(?:%|[-+ #0]*[0-9]*(?:\.[0-9]+)?[diouxXeEfgGqscaA])'
    foreach ($m in [regex]::Matches($value, $pattern)) { $tokens += $m.Value }
    return ($tokens -join '|')
}

function Parse-StaticEntries([string]$text) {
    $entries = @{}
    # Standard return-table and loc.<key> assignment forms. Localization values
    # are flat language maps; stop at their first closing brace.
    $entryPattern = '(?ms)^\s*(?:loc\.)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{(.*?)\}\s*,?'
    foreach ($match in [regex]::Matches($text, $entryPattern)) {
        $key, $body = $match.Groups[1].Value, $match.Groups[2].Value
        $languages = @{}
        $langPattern = '(?m)(?:^|,)\s*(?:\["([a-z]{2}(?:-[a-z]{2})?)"\]|([a-z]{2}(?:-[a-z]{2})?))\s*=\s*"((?:[^"\\]|\\.)*)"'
        foreach ($lang in [regex]::Matches($body, $langPattern)) {
            $id = if ($lang.Groups[1].Success) { $lang.Groups[1].Value } else { $lang.Groups[2].Value }
            $languages[$id] = $lang.Groups[3].Value
        }
        if ($languages.ContainsKey('en')) { $entries[$key] = $languages }
    }
    # Helper form used by event_tweaker: key = en("English").
    $helperPattern = '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*en\s*\(\s*"((?:[^"\\]|\\.)*)"\s*\)'
    foreach ($match in [regex]::Matches($text, $helperPattern)) {
        $entries[$match.Groups[1].Value] = @{ en = $match.Groups[2].Value }
    }
    return $entries
}

function Measure-Entries([hashtable]$entries) {
    $result = @{ English = $entries.Count; Missing = @{}; TokenDrift = @{} }
    foreach ($language in $TargetLanguages) {
        $missing, $drift = 0, 0
        foreach ($key in $entries.Keys) {
            $row = $entries[$key]
            if (-not $row.ContainsKey($language) -or [string]::IsNullOrWhiteSpace($row[$language])) {
                $missing++
            } elseif ((Get-FormatSignature $row.en) -ne (Get-FormatSignature $row[$language])) {
                $drift++
            }
        }
        $result.Missing[$language] = $missing
        $result.TokenDrift[$language] = $drift
    }
    return $result
}

function Invoke-SelfTest {
    $fixture = @'
return {
    plain = { en = "Hello", fr = "Bonjour", ["br-pt"] = "Ola" },
    formatted = {
        en = "Count: %d%%",
        fr = "Compte : %d%%",
        ["br-pt"] = "Contagem: %s%%",
    },
    helper = en("Helper only"),
}
'@
    $entries = Parse-StaticEntries $fixture
    $measure = Measure-Entries $entries
    $passed = $true
    function Assert([bool]$condition, [string]$description) {
        $verdict = if ($condition) { 'PASS' } else { 'FAIL' }
        Write-Host "  [$verdict] $description" -ForegroundColor $(if ($condition) { 'Green' } else { 'Red' })
        if (-not $condition) { $script:TranslationSelfTestPassed = $false }
    }
    $script:TranslationSelfTestPassed = $true
    Assert ($entries.Count -eq 3) 'parses table, bracketed language id, multiline, and helper forms'
    Assert ($measure.Missing.fr -eq 1) 'counts an absent explicit translation'
    Assert ($measure.TokenDrift.fr -eq 0) 'accepts matching Lua format tokens'
    Assert ($measure.TokenDrift['br-pt'] -eq 1) 'detects translated format-token drift'
    Assert ((Get-FormatSignature 'Count: %d%%') -eq '%d|%%') 'preserves ordered directive and literal-percent signature'
    $passed = $script:TranslationSelfTestPassed
    Write-Host "[translation_readiness] $(if ($passed) { 'OK' } else { 'FAILED' }) -- self-test, audit v$AuditVersion."
    return $(if ($passed) { 0 } else { 2 })
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$files, $englishTotal, $missingTotal, $driftTotal = 0, 0, 0, 0
foreach ($file in (Find-LocFiles $repoRoot | Sort-Object FullName)) {
    $files++
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $entries = Parse-StaticEntries $text
    $measure = Measure-Entries $entries
    $englishTotal += $measure.English
    $parts = @()
    foreach ($language in $TargetLanguages) {
        $missingTotal += $measure.Missing[$language]
        $driftTotal += $measure.TokenDrift[$language]
        $translated = $measure.English - $measure.Missing[$language]
        $parts += "${language}=$translated/$($measure.English)"
    }
    if (-not $Quiet) {
        $relative = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        Write-Host ("[translation_readiness] {0}: en={1} {2}" -f $relative, $measure.English, ($parts -join ' '))
    }
}

Write-Host ("[translation_readiness] audit=v{0} files={1} english_entries={2} target_languages={3} missing={4} token_drift={5} strict={6}" -f `
    $AuditVersion, $files, $englishTotal, $TargetLanguages.Count, $missingTotal,
    $driftTotal, $Strict.IsPresent)

if ($Strict -and ($missingTotal -gt 0 -or $driftTotal -gt 0)) { exit 2 }
exit 0
