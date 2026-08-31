# Blocking offline provenance/reproduction gate for issue #1436's bounded
# Patch 2.0.10 Sword-and-Dagger slice. All generated output stays in OS temp.
[CmdletBinding()]
param([string]$RepoRoot, [string]$SourceRepo, [switch]$RequireSource,
    [switch]$Quiet)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Detail([string]$Text) {
    if (-not $Quiet) { Write-Host $Text -ForegroundColor DarkGray }
}
function Generate([string]$Lua, [string]$Script, [string[]]$Arguments,
    [string]$Cwd, [string]$Out) {
    if ($env:GIT_NO_LAZY_FETCH -cne '1' -or $env:GIT_OPTIONAL_LOCKS -cne '0') {
        throw 'post-selection Git read escaped the no-fetch/no-lock guard'
    }
    $had = Test-Path Env:WT_HISTORY_OUTPUT
    $prior = $env:WT_HISTORY_OUTPUT
    try {
        $env:WT_HISTORY_OUTPUT = $Out
        Push-Location -LiteralPath $Cwd
        try { $log = @(& $Lua $Script @Arguments 2>&1); $exit = $LASTEXITCODE }
        finally { Pop-Location }
        if ($exit -ne 0) { throw "generator failed: $($log -join ' ')" }
        if (-not (Test-Path -LiteralPath $Out -PathType Leaf)) {
            throw "generator did not create $Out"
        }
    } finally {
        if ($had) { $env:WT_HISTORY_OUTPUT = $prior }
        else { Remove-Item Env:WT_HISTORY_OUTPUT -ErrorAction SilentlyContinue }
    }
}

$hadNoFetch = Test-Path Env:GIT_NO_LAZY_FETCH
$oldNoFetch = $env:GIT_NO_LAZY_FETCH
$hadLocks = Test-Path Env:GIT_OPTIONAL_LOCKS
$oldLocks = $env:GIT_OPTIONAL_LOCKS
$guarded = $false
try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    . (Join-Path $root 'tools\weapon-history\source-anchor.ps1')
    $anchor = Read-WtHistorySourceAnchor -RepoRoot $root
    $tool = Join-Path $root 'tools\weapon-history'
    $evidence = Join-Path $tool 'evidence\patch_2_0_10'
    $extractor = Join-Path $tool 'extract_weapon_history.lua'
    $oracle = Join-Path $tool 'source_oracle\extract_weapon_history_oracle.lua'
    $spec = Join-Path $tool 'source_oracle\patch_2_0_10_source_spec.lua'
    $generator = Join-Path $tool 'generate_patch_2_0_10_history.lua'
    $sourceCatalog = Join-Path $evidence '_wt_history_2_0_10_source_catalog.lua'
    $catalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_2_0_10_catalog.lua'
    $devCatalog = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_2_0_10_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pins = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracle = '767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $generator = '5c74c7e2e81253f4c9a7f022d312a28c324d0318efe611ff7d770a94446fd542'
        $spec = 'e7b8f033c4f3bdd543489898847c829753ad6f9270a1abc9761d4ee474b92665'
        $sourceCatalog = '0b69388b68ecf32ff8ec2cd9f77489b9eacaec2279b806da24c7175e0583b50a'
        $catalog = '74ed7ed9f3b9998c10b279f2a91465625016b3412de0b0b04513c1c1552f680a'
        $devCatalog = '74ed7ed9f3b9998c10b279f2a91465625016b3412de0b0b04513c1c1552f680a'
    }
    foreach ($pin in $pins.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $pin.Key -PathType Leaf) -or
            (Hash $pin.Key) -cne $pin.Value) {
            throw "pinned artifact drift: $($pin.Key)"
        }
    }
    if ((Hash $catalog) -cne (Hash $devCatalog)) {
        throw 'Patch 2.0.10 public/dev catalogs are not byte-identical'
    }

    $ledger = [ordered]@{
        '_wt_history_2_0_10_routes_oracle.lua' = '7e706777183dbd854f8edd6351bef95df58840b392c35cdc63e0d59f9999a694'
        '_wt_history_profiles_2_0_9_1_to_2_0_10_generated.lua' = 'b8e7a4e42c68dbfddd9b20564fbae5851bd7201a93689b8a669f799889d8afba'
        '_wt_history_profiles_current_6_12_0_generated.lua' = '7eb51fc267d42212bef2ab5bd07211288d9256e4dd7783094e714550dc88aeb2'
        '_wt_history_profiles_post_2_0_10_generated.lua' = 'f40fc0505834a1e15bbe43d298cef97486ab35d1adb4d8bd144ac6c453b22678'
    }
    $actual = @(Get-ChildItem -LiteralPath $evidence -File -Filter '*.lua' |
        ForEach-Object Name)
    if ($actual.Count -ne 5 -or ($actual | Where-Object {
        $_ -ne '_wt_history_2_0_10_source_catalog.lua' -and -not $ledger.Contains($_)
    }).Count) { throw 'Patch 2.0.10 evidence directory census drift' }
    foreach ($row in $ledger.GetEnumerator()) {
        if ((Hash (Join-Path $evidence $row.Key)) -cne $row.Value) {
            throw "evidence ledger drift: $($row.Key)"
        }
    }
    if ([IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8).IndexOf(
        $anchor.ContentRevision, [StringComparison]::Ordinal) -lt 0) {
        throw 'Patch 2.0.10 source catalog current anchor drift'
    }

    $old = '90c7c21adb7aa2b7de5fcdca5094727895fbeb1a'
    $post = '67d593c4f98653e1d511105b6adeebb5d6619c58'
    $current = $anchor.ContentRevision
    $power = 'scripts/settings/equipment/power_level_templates.lua'
    $damage = 'scripts/settings/equipment/damage_profile_templates.lua'
    $template = 'scripts/settings/equipment/weapon_templates/dual_wield_sword_dagger.lua'
    $files = @(
        @($power, 'f9643cb2701d0a8bc5df8f9ea103a0ce8a528d67', 'f9643cb2701d0a8bc5df8f9ea103a0ce8a528d67', '6eba753d985ea80057947ed1ae1a25214204783e'),
        @($damage, '44ddcd9af0bb0df90bee614d102cdb6d99a6881f', 'a6d3544ef2368a218661fd457468c7f9502bed31', 'e8330328d0085f6aee09e0495ba88fdc0211d5aa'),
        @($template, 'c23af26d0557f5b29e52cafa72c52562da0a6f56', 'c23af26d0557f5b29e52cafa72c52562da0a6f56', '62d57cc3537ef6c7f78a40a8988027f0b527c8d9')
    )
    $requirements = foreach ($file in $files) {
        for ($index = 1; $index -le 3; $index++) {
            [pscustomobject]@{
                Revision = @($old, $post, $current)[$index - 1]
                Path = $file[0]
                Blob = $file[$index]
            }
        }
    }
    foreach ($row in @(
        @('scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua', 'a7f6e9e9fd9eb3e862c4c7a1ea5babfc5c43a733'),
        @('scripts/settings/equipment/damage_profile_templates_dlc_cog.lua', '01d295acab5e5850c83f31939124ca3124edc403'),
        @('scripts/settings/equipment/damage_profile_templates_dlc_woods.lua', 'c379649a9dd9366004ac6e2221780f10dcfec581')
    )) {
        $requirements += [pscustomobject]@{
            Revision = $current; Path = $row[0]; Blob = $row[1]
        }
    }
    if (@($requirements).Count -ne 12) {
        throw 'Patch 2.0.10 revision/path/blob requirement closure drift'
    }
    $selection = Find-WtHistorySourceRepo -Root $root -Explicit $SourceRepo `
        -Requirements $requirements
    $source = $selection.Path
    if (-not $source) {
        if ($RequireSource) {
            throw "source checkout is required but unavailable or incomplete: $($selection.Rejections -join '; ')"
        }
        Write-Host '[check_wt_history_patch_2_0_10_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned artifacts OK)' -ForegroundColor Yellow
        exit 0
    }

    $env:GIT_NO_LAZY_FETCH = '1'
    $env:GIT_OPTIONAL_LOCKS = '0'
    $guarded = $true
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $tmp = Join-Path $tempBase ('wt1436-p2010-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        foreach ($evaluator in @($extractor, $oracle)) {
            & $lua $evaluator --self-test | Out-Null
            if ($LASTEXITCODE) { throw 'numeric/presence self-test failed' }
        }
        $adjacent = Join-Path $evidence '_wt_history_profiles_2_0_9_1_to_2_0_10_generated.lua'
        $jobs = @(
            [pscustomobject]@{ Name = 'adjacent'; Arguments = @('--profiles', $old, $post, $power, $damage); Evidence = '_wt_history_profiles_2_0_9_1_to_2_0_10_generated.lua' },
            [pscustomobject]@{ Name = 'post'; Arguments = @('--profiles', $post, $old, $power, $damage); Evidence = '_wt_history_profiles_post_2_0_10_generated.lua' },
            [pscustomobject]@{ Name = 'current'; Arguments = @('--rehydrate-profiles', $current, $current, $adjacent); Evidence = '_wt_history_profiles_current_6_12_0_generated.lua' }
        )
        foreach ($job in $jobs) {
            $primaryOut = Join-Path $tmp ($job.Name + '-primary.lua')
            Generate $lua $extractor $job.Arguments $source $primaryOut
            $checked = Join-Path $evidence $job.Evidence
            if ((Hash $primaryOut) -cne (Hash $checked)) {
                throw "non-reproducible evidence: $($job.Name)"
            }
            $oracleOut = Join-Path $tmp ($job.Name + '-oracle.lua')
            Generate $lua $oracle (@('--source-repo', $source) + $job.Arguments) `
                $root $oracleOut
            $comparison = @(& $lua $oracle --compare-evidence $checked $oracleOut 2>&1)
            if ($LASTEXITCODE) {
                throw "independent evidence differs ($($job.Name)): $($comparison -join ' ')"
            }
        }
        $routeOut = Join-Path $tmp 'routes.lua'
        Generate $lua $oracle @('--source-repo', $source, '--routes', $current, $spec) `
            $root $routeOut
        if ((Hash $routeOut) -cne
            (Hash (Join-Path $evidence '_wt_history_2_0_10_routes_oracle.lua'))) {
            throw 'Patch 2.0.10 current profile routes are not byte-reproducible'
        }
        $catalogOut = Join-Path $tmp 'catalog.lua'
        $log = @(& $lua $generator $source $evidence $catalogOut 2>&1)
        if ($LASTEXITCODE) { throw "catalog generator failed: $($log -join ' ')" }
        if ((Hash $catalogOut) -cne (Hash $catalog)) {
            throw 'Patch 2.0.10 catalog is not byte-reproducible'
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            if (@(Get-ChildItem $tmp -Directory -Force).Count) {
                throw 'unsafe non-flat temp cleanup'
            }
            foreach ($file in @(Get-ChildItem $tmp -File -Force)) {
                Remove-Item -LiteralPath $file.FullName -Force
            }
            Remove-Item -LiteralPath $tmp -Force
        }
    }
    Detail "[check_wt_history_patch_2_0_10_reproducibility] OK - exact two-leaf boundary, two private current-schema profiles, and four explicit routes reproduced from $source"
    exit 0
} catch {
    Write-Host "[check_wt_history_patch_2_0_10_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
} finally {
    if ($guarded) {
        if ($hadNoFetch) { $env:GIT_NO_LAZY_FETCH = $oldNoFetch }
        else { Remove-Item Env:GIT_NO_LAZY_FETCH -ErrorAction SilentlyContinue }
        if ($hadLocks) { $env:GIT_OPTIONAL_LOCKS = $oldLocks }
        else { Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue }
    }
}
