# check_translation_readiness.ps1 -- versioned cross-mod translation census (#444).
#
# Diagnostic mode (default) reports coverage but succeeds while #444 is blocked on
# stable English/1.0 releases. -Strict is the future release gate: missing target
# strings, Lua-format-token drift, or ambiguous catalog identities fail with exit 2.

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$Quiet,
    [switch]$Strict,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
$AuditVersion = '1.2.0'
$TargetLanguages = @('fr', 'pl', 'es', 'tr', 'de', 'br-pt', 'ru')
$KnownLanguages = @('en') + $TargetLanguages
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

function Measure-DynamicGenerators([string]$text) {
    # Computed loc keys cannot be exported or translated safely by this static
    # census, whether their value is built inline or copied from another runtime
    # provider. Count every statement so -Strict cannot claim completeness while
    # runtime-created rows remain outside the catalog.
    $pattern = '(?m)\bloc\s*\[[^\r\n\]]+\]\s*='
    return [regex]::Matches($text, $pattern).Count
}

function Measure-StaticKeyDuplicates([string]$text) {
    # Parse-StaticEntries returns a hashtable and therefore necessarily keeps
    # only the last definition of a key. Count all English-bearing static
    # definitions before that collapse so export/translation cannot silently
    # target a different row than the Lua runtime ultimately retains.
    $counts = @{}
    $entryPattern = '(?ms)^\s*(?:loc\.)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\{(.*?)\}\s*,?'
    foreach ($match in [regex]::Matches($text, $entryPattern)) {
        $body = $match.Groups[2].Value
        if ($body -notmatch '(?m)(?:^|,)\s*(?:\["en"\]|en)\s*=\s*"') { continue }
        $key = $match.Groups[1].Value
        $counts[$key] = 1 + $(if ($counts.ContainsKey($key)) { $counts[$key] } else { 0 })
    }
    $helperPattern = '(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*en\s*\('
    foreach ($match in [regex]::Matches($text, $helperPattern)) {
        $key = $match.Groups[1].Value
        $counts[$key] = 1 + $(if ($counts.ContainsKey($key)) { $counts[$key] } else { 0 })
    }
    $duplicates = 0
    foreach ($count in $counts.Values) {
        if ($count -gt 1) { $duplicates += $count - 1 }
    }
    return $duplicates
}

function Measure-Entries([hashtable]$entries) {
    $result = @{ English = $entries.Count; Missing = @{}; TokenDrift = @{}; UnknownLocales = @{} }
    foreach ($key in $entries.Keys) {
        foreach ($language in $entries[$key].Keys) {
            if ($KnownLanguages -notcontains $language) {
                if (-not $result.UnknownLocales.ContainsKey($language)) {
                    $result.UnknownLocales[$language] = 0
                }
                $result.UnknownLocales[$language]++
            }
        }
    }
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
        ["pt-br"] = "Contagem: %d%%",
    },
    helper = en("Helper only"),
    duplicate = { en = "First definition" },
    duplicate = en("Second definition"),
    loc[computed_key] = en("Computed English"),
    loc[computed_key .. "_tooltip"] = en("Computed tooltip"),
}
'@
    $entries = Parse-StaticEntries $fixture
    $measure = Measure-Entries $entries
    $dynamicGenerators = Measure-DynamicGenerators $fixture
    $duplicateKeys = Measure-StaticKeyDuplicates $fixture
    $passed = $true
    function Assert([bool]$condition, [string]$description) {
        $verdict = if ($condition) { 'PASS' } else { 'FAIL' }
        Write-Host "  [$verdict] $description" -ForegroundColor $(if ($condition) { 'Green' } else { 'Red' })
        if (-not $condition) { $script:TranslationSelfTestPassed = $false }
    }
    $script:TranslationSelfTestPassed = $true
    Assert ($entries.Count -eq 4) 'parses table, bracketed language id, multiline, and helper forms'
    Assert ($measure.Missing.fr -eq 2) 'counts absent explicit translations after duplicate collapse'
    Assert ($measure.TokenDrift.fr -eq 0) 'accepts matching Lua format tokens'
    Assert ($measure.TokenDrift['br-pt'] -eq 1) 'detects translated format-token drift'
    Assert ($measure.UnknownLocales['pt-br'] -eq 1) 'detects a mistyped Fatshark language id'
    Assert ($dynamicGenerators -eq 2) 'detects English-only computed localization generators'
    Assert ($duplicateKeys -eq 1) 'detects a duplicate static localization identity before hashtable collapse'
    Assert ((Get-FormatSignature 'Count: %d%%') -eq '%d|%%') 'preserves ordered directive and literal-percent signature'
    $passed = $script:TranslationSelfTestPassed
    Write-Host "[translation_readiness] $(if ($passed) { 'OK' } else { 'FAILED' }) -- self-test, audit v$AuditVersion."
    return $(if ($passed) { 0 } else { 2 })
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$files, $englishTotal, $missingTotal, $driftTotal = 0, 0, 0, 0
$unknownLocaleTotal, $dynamicGeneratorTotal, $duplicateKeyTotal = 0, 0, 0
foreach ($file in (Find-LocFiles $repoRoot | Sort-Object FullName)) {
    $files++
    $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
    $entries = Parse-StaticEntries $text
    $measure = Measure-Entries $entries
    $dynamicGenerators = Measure-DynamicGenerators $text
    $duplicateKeys = Measure-StaticKeyDuplicates $text
    $englishTotal += $measure.English
    $dynamicGeneratorTotal += $dynamicGenerators
    $duplicateKeyTotal += $duplicateKeys
    foreach ($count in $measure.UnknownLocales.Values) { $unknownLocaleTotal += $count }
    $parts = @()
    foreach ($language in $TargetLanguages) {
        $missingTotal += $measure.Missing[$language]
        $driftTotal += $measure.TokenDrift[$language]
        $translated = $measure.English - $measure.Missing[$language]
        $parts += "${language}=$translated/$($measure.English)"
    }
    if (-not $Quiet) {
        $relative = [IO.Path]::GetRelativePath($repoRoot, $file.FullName)
        $unknown = if ($measure.UnknownLocales.Count -eq 0) { '-' } else {
            (($measure.UnknownLocales.Keys | Sort-Object | ForEach-Object {
                "$_=$($measure.UnknownLocales[$_])"
            }) -join ',')
        }
        Write-Host ("[translation_readiness] {0}: en={1} {2} unknown_locales={3} dynamic_generators={4} duplicate_keys={5}" -f `
            $relative, $measure.English, ($parts -join ' '), $unknown, $dynamicGenerators, $duplicateKeys)
    }
}

Write-Host ("[translation_readiness] audit=v{0} files={1} english_entries={2} target_languages={3} missing={4} token_drift={5} unknown_locales={6} dynamic_generators={7} duplicate_keys={8} strict={9}" -f `
    $AuditVersion, $files, $englishTotal, $TargetLanguages.Count, $missingTotal,
    $driftTotal, $unknownLocaleTotal, $dynamicGeneratorTotal, $duplicateKeyTotal,
    $Strict.IsPresent)

if ($Strict -and ($missingTotal -gt 0 -or $driftTotal -gt 0 `
        -or $unknownLocaleTotal -gt 0 -or $dynamicGeneratorTotal -gt 0 `
        -or $duplicateKeyTotal -gt 0)) { exit 2 }
exit 0
