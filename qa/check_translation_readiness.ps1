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
$AuditVersion = '1.3.0'
$TargetLanguages = @('fr', 'pl', 'es', 'tr', 'de', 'br-pt', 'ru')
$KnownLanguages = @('en') + $TargetLanguages
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
$repoRoot = (Resolve-Path $RepoRoot).Path

function Find-LocFiles([string]$root) {
    # #1176: enumerate canonical owners, never the repository container. A
    # complete nested checkout, QA fixture or reference cache is not a mod.
    # #1101: ancestor names such as .claude must not exclude this checkout.
    $inventoryPath = Join-Path $root 'tools\mod-inventory.psd1'
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "canonical mod inventory is missing: $inventoryPath"
    }
    try { $inventory = Import-PowerShellDataFile -LiteralPath $inventoryPath }
    catch { throw "canonical mod inventory cannot be imported: $($_.Exception.Message)" }
    if (-not $inventory.ContainsKey('Mods') -or $inventory.Mods -isnot [array] `
            -or $inventory.Mods.Count -eq 0) {
        throw 'canonical mod inventory must contain a nonempty Mods array'
    }
    $owners = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $directories = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in $inventory.Mods) {
        if ($entry -isnot [System.Collections.IDictionary] -or $entry.Dir -isnot [string] `
                -or $entry.Dir -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
            throw 'canonical mod inventory contains an unsafe or missing Dir'
        }
        if (-not $owners.Add($entry.Dir)) {
            throw "canonical mod inventory contains duplicate owner: $($entry.Dir)"
        }
        $directories.Add($entry.Dir)
    }
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($dir in $directories) {
        $sourceRoot = Join-Path $root "$dir\scripts\mods\$dir"
        $canonical = Join-Path $sourceRoot "${dir}_localization.lua"
        if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {
            throw "canonical localization entry is missing for owner ${dir}: $canonical"
        }
        # Owned nested localization modules remain in scope. Exclusions are
        # relative to this owner's source tree, not its machine-specific path.
        $prefix = [IO.Path]::GetFullPath($sourceRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -Filter '*_localization.lua' -Recurse -File -ErrorAction Stop) {
            $relative = $file.FullName.Substring($prefix.Length).Replace('\', '/')
            if ($relative -match '(?i)(^|/)(?:\.claude|\.git|_archive|bundleV2|\.build|\.temp|\.release-stage|sample_[^/]*)/') {
                continue
            }
            $paths.Add($file.FullName)
        }
    }
    $ordered = $paths.ToArray()
    [Array]::Sort($ordered, [StringComparer]::Ordinal)
    foreach ($path in $ordered) { Get-Item -LiteralPath $path -ErrorAction Stop }
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

    # Tiny owned trees only: no real worktree, repository copy or localization
    # mutation. Both hosts exercise the same production discovery function.
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $temp = Join-Path $tempBase ('vt2-translation444-' + [guid]::NewGuid().ToString('N'))
    $normal = Join-Path $temp 'normal'
    $linked = Join-Path $temp '.claude\worktrees\checkout'
    $inventoryText = "@{ Mods = @(@{ Dir = 'alpha' }, @{ Dir = 'beta' }) }"
    function Write-DiscoveryFixture([string]$Root, [string]$Relative, [string]$Text) {
        $path = Join-Path $Root $Relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path, $Text, (New-Object Text.UTF8Encoding($false)))
    }
    function Assert-DiscoveryFailure([string]$Root, [string]$Pattern, [string]$Name) {
        $message = ''
        try { $null = @(Find-LocFiles $Root) } catch { $message = $_.Exception.Message }
        Assert ($message -match $Pattern) "$Name (observed: $message)"
    }
    try {
        foreach ($root in @($normal, $linked)) {
            Write-DiscoveryFixture $root 'tools\mod-inventory.psd1' $inventoryText
            foreach ($owner in @('alpha', 'beta')) {
                Write-DiscoveryFixture $root "$owner\scripts\mods\$owner\${owner}_localization.lua" `
                    'return { greeting = { en = "Hello" } }'
            }
            Write-DiscoveryFixture $root 'alpha\scripts\mods\alpha\nested\extra_localization.lua' `
                'return { nested = { en = "Nested" } }'
            foreach ($poison in @(
                '.claude\worktrees\copy\alpha\scripts\mods\alpha\alpha_localization.lua',
                '.spawn_tweaks_ref\alpha\scripts\mods\alpha\alpha_localization.lua',
                '_archive\alpha\scripts\mods\alpha\alpha_localization.lua',
                'sample_mod\scripts\mods\sample_mod\sample_mod_localization.lua',
                'qa\lua\tests\test_event_modifier_localization.lua',
                'alpha\scripts\mods\foreign\foreign_localization.lua',
                'alpha\scripts\mods\alpha\.claude\copy\poison_localization.lua',
                'alpha\scripts\mods\alpha\.build\poison_localization.lua')) {
                Write-DiscoveryFixture $root $poison 'return { poison = { en = "Wrong", zz = "Wrong" } }'
            }
        }
        $found = @(Find-LocFiles $normal)
        Assert ($found.Count -eq 3) 'T444_inventory_owners_only: two owners and one nested module'
        Assert (@($found | Where-Object { $_.FullName -match 'worktrees|\.spawn_tweaks_ref|_archive|sample_mod' }).Count -eq 0) `
            'T444_nested_worktree_and_reference_cache_ignored'
        Assert (@($found | Where-Object { $_.Name -eq 'test_event_modifier_localization.lua' }).Count -eq 0) `
            'T444_qa_fixture_ignored'
        Assert (@($found | Where-Object { $_.Name -eq 'extra_localization.lua' }).Count -eq 1) `
            'T444_nested_localization_included'
        $linkedFound = @(Find-LocFiles $linked)
        Assert (($linkedFound.Name -join '|') -ceq ($found.Name -join '|')) `
            'T444_parent_named_claude_valid: ancestor names do not alter the census'
        Write-DiscoveryFixture $normal 'tools\mod-inventory.psd1' `
            "@{ Mods = @(@{ Dir = 'alpha' }, @{ Dir = 'beta' }, @{ Dir = 'sample_gamma' }) }"
        Write-DiscoveryFixture $normal 'sample_gamma\scripts\mods\sample_gamma\sample_gamma_localization.lua' `
            'return { added = { en = "New owner" } }'
        Assert (@(Find-LocFiles $normal).Count -eq 4) 'T444_new_owner_automatic: no hardcoded owner count'

        Assert-DiscoveryFailure (Join-Path $temp 'missing-inventory') 'inventory is missing' 'T444_missing_inventory_fails'
        foreach ($bad in @(
            @{ Text = '@{ Mods = @() }'; Pattern = 'nonempty Mods array'; Name = 'empty' },
            @{ Text = '@{ Other = @() }'; Pattern = 'nonempty Mods array'; Name = 'missing Mods' },
            @{ Text = "@{ Mods = 'alpha' }"; Pattern = 'nonempty Mods array'; Name = 'nonarray Mods' },
            @{ Text = '@{ Mods = @('; Pattern = 'cannot be imported'; Name = 'malformed' },
            @{ Text = "@{ Mods = @(@{ Dir = '../escape' }) }"; Pattern = 'unsafe or missing Dir'; Name = 'traversal' },
            @{ Text = "@{ Mods = @(@{ Dir = '' }) }"; Pattern = 'unsafe or missing Dir'; Name = 'empty Dir' },
            @{ Text = '@{ Mods = @(@{ Dir = 42 }) }'; Pattern = 'unsafe or missing Dir'; Name = 'nonstring Dir' },
            @{ Text = "@{ Mods = @(@{ Dir = 'alpha' }, @{ Dir = 'ALPHA' }) }"; Pattern = 'duplicate owner'; Name = 'duplicate' })) {
            Write-DiscoveryFixture $normal 'tools\mod-inventory.psd1' $bad.Text
            Assert-DiscoveryFailure $normal $bad.Pattern "T444_invalid_inventory_fails: $($bad.Name)"
        }
        Write-DiscoveryFixture $normal 'tools\mod-inventory.psd1' "@{ Mods = @(@{ Dir = 'missing_owner' }) }"
        Assert-DiscoveryFailure $normal 'canonical localization entry is missing' 'T444_missing_owner_entry_fails'
    }
    finally {
        # Verify the exact owned absolute target before recursive fixture cleanup.
        $resolved = [IO.Path]::GetFullPath($temp)
        if (-not $resolved.StartsWith($tempBase + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) `
                -or [IO.Path]::GetFileName($resolved) -notmatch '^vt2-translation444-[a-f0-9]{32}$') {
            throw 'refusing cleanup outside the owned translation fixture directory'
        }
        if ([IO.Directory]::Exists($resolved)) { [IO.Directory]::Delete($resolved, $true) }
    }
    $passed = $script:TranslationSelfTestPassed
    Write-Host "[translation_readiness] $(if ($passed) { 'OK' } else { 'FAILED' }) -- self-test, audit v$AuditVersion."
    return $(if ($passed) { 0 } else { 2 })
}

if ($SelfTest) { exit (Invoke-SelfTest) }

$files, $englishTotal, $missingTotal, $driftTotal = 0, 0, 0, 0
$unknownLocaleTotal, $dynamicGeneratorTotal, $duplicateKeyTotal = 0, 0, 0
try { $localizationFiles = @(Find-LocFiles $repoRoot) }
catch {
    Write-Host "[translation_readiness] ERROR -- discovery failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 2
}
foreach ($file in $localizationFiles) {
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
        $rootPrefix = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        $fullName = [IO.Path]::GetFullPath($file.FullName)
        $relative = if ($fullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $fullName.Substring($rootPrefix.Length)
        } else { $fullName }
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
