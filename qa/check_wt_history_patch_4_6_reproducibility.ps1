# Blocking offline provenance/reproduction gate for issue #1436's bounded
# Patch 4.6 Hagbane-only slice. Generated output stays in a flat OS-temp dir.
[CmdletBinding()]
param([string]$RepoRoot, [string]$SourceRepo, [switch]$RequireSource,
    [switch]$Quiet, [switch]$SelfTest)

$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }

function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Detail([string]$Text) {
    if (-not $Quiet) { Write-Host $Text -ForegroundColor DarkGray }
}
function Assert-ReadOnlyGitGuard {
    if ($env:GIT_NO_LAZY_FETCH -cne '1' -or
        $env:GIT_OPTIONAL_LOCKS -cne '0') {
        throw 'post-selection Git read escaped the no-fetch/no-lock guard'
    }
}
function Get-ReadOnlyGitEnvironmentState {
    [pscustomobject]@{
        NoLazyFetchPresent = Test-Path Env:GIT_NO_LAZY_FETCH
        NoLazyFetch = [Environment]::GetEnvironmentVariable(
            'GIT_NO_LAZY_FETCH', 'Process')
        OptionalLocksPresent = Test-Path Env:GIT_OPTIONAL_LOCKS
        OptionalLocks = [Environment]::GetEnvironmentVariable(
            'GIT_OPTIONAL_LOCKS', 'Process')
    }
}
function Enter-ReadOnlyGitEnvironment {
    [Environment]::SetEnvironmentVariable('GIT_NO_LAZY_FETCH', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS', '0', 'Process')
    Assert-ReadOnlyGitGuard
}
function Restore-ReadOnlyGitEnvironment($State) {
    if ($State.NoLazyFetchPresent) {
        [Environment]::SetEnvironmentVariable('GIT_NO_LAZY_FETCH',
            $State.NoLazyFetch, 'Process')
    }
    else {
        Remove-Item Env:GIT_NO_LAZY_FETCH -ErrorAction SilentlyContinue
    }
    if ($State.OptionalLocksPresent) {
        [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS',
            $State.OptionalLocks, 'Process')
    }
    else {
        Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue
    }
}
function Generate([string]$Lua, [string]$Script, [string[]]$Arguments,
    [string]$Cwd, [string]$Out) {
    Assert-ReadOnlyGitGuard
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

$outerGitEnvironment = Get-ReadOnlyGitEnvironmentState
if ($SelfTest) {
    $selfTestFailures = @()
    try {
        foreach ($case in @(
            [pscustomobject]@{ Present = $false; NoLazyFetch = $null; OptionalLocks = $null },
            [pscustomobject]@{ Present = $true; NoLazyFetch = 'sentinel-fetch'; OptionalLocks = 'sentinel-locks' }
        )) {
            if ($case.Present) {
                [Environment]::SetEnvironmentVariable('GIT_NO_LAZY_FETCH',
                    $case.NoLazyFetch, 'Process')
                [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS',
                    $case.OptionalLocks, 'Process')
            }
            else {
                Remove-Item Env:GIT_NO_LAZY_FETCH -ErrorAction SilentlyContinue
                Remove-Item Env:GIT_OPTIONAL_LOCKS -ErrorAction SilentlyContinue
            }
            $before = Get-ReadOnlyGitEnvironmentState
            Enter-ReadOnlyGitEnvironment
            Restore-ReadOnlyGitEnvironment $before
            $after = Get-ReadOnlyGitEnvironmentState
            if ($after.NoLazyFetchPresent -ne $before.NoLazyFetchPresent -or
                $after.OptionalLocksPresent -ne $before.OptionalLocksPresent -or
                ($before.NoLazyFetchPresent -and
                    $after.NoLazyFetch -cne $before.NoLazyFetch) -or
                ($before.OptionalLocksPresent -and
                    $after.OptionalLocks -cne $before.OptionalLocks)) {
                $selfTestFailures += "raw environment restoration failed present=$($case.Present)"
            }
        }
    }
    finally {
        Restore-ReadOnlyGitEnvironment $outerGitEnvironment
    }
    if ($selfTestFailures.Count) {
        Write-Host '[check_wt_history_patch_4_6_reproducibility:selftest] FAILED' -ForegroundColor Red
        $selfTestFailures | ForEach-Object { Write-Host "  X $_" -ForegroundColor Red }
        exit 2
    }
    Write-Host '[check_wt_history_patch_4_6_reproducibility:selftest] OK - no-fetch/no-lock guard restores present and absent raw environment state.' -ForegroundColor Green
    exit 0
}

$gitEnvironment = $outerGitEnvironment
$gitReadOnlyGuardArmed = $false

try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    . (Join-Path $root 'tools\weapon-history\source-anchor.ps1')
    $anchor = Read-WtHistorySourceAnchor -RepoRoot $root
    $tool = Join-Path $root 'tools\weapon-history'
    $evidence = Join-Path $tool 'evidence\patch_4_6'
    $extractor = Join-Path $tool 'extract_weapon_history.lua'
    $oracle = Join-Path $tool 'source_oracle\extract_weapon_history_oracle.lua'
    $spec = Join-Path $tool 'source_oracle\patch_4_6_source_spec.lua'
    $generator = Join-Path $tool 'generate_patch_4_6_history.lua'
    $sourceCatalog = Join-Path $evidence '_wt_history_4_6_source_catalog.lua'
    $catalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_4_6_catalog.lua'
    $devCatalog = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_4_6_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'

    $pins = [ordered]@{
        $extractor = 'ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracle = '1f5f26f4d302671859e7dadcf0f25d536b2601b03ee27d0a6ae35cb8723d52bd'
        $generator = '27a406f45632d85e80a72e839f8c642e51a7f379d66b12e795424f7c5d5d7b7d'
        $spec = '69f2a7df8e5b1e6dac681b684e67ddefa55eace25ffe7eee0d4095422313913e'
        $sourceCatalog = 'ee34d0026406343e3b5800f72d63da7cfb4c950aef0abb3a1b5dda8f911b2940'
        $catalog = 'e52809188121fd2ec81add1c3cffe0b9c7598c6ecac9c80d1d3e75bb78d40ad0'
        $devCatalog = 'e52809188121fd2ec81add1c3cffe0b9c7598c6ecac9c80d1d3e75bb78d40ad0'
    }
    foreach ($pin in $pins.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $pin.Key -PathType Leaf) -or
            (Hash $pin.Key) -cne $pin.Value) {
            throw "pinned artifact drift: $($pin.Key)"
        }
    }
    if ((Hash $catalog) -cne (Hash $devCatalog)) {
        throw 'Patch 4.6 public/dev catalogs are not byte-identical'
    }

    $ledger = [ordered]@{
        '_wt_history_4_6_routes_oracle.lua' = '52902d86ef11f1da7fcf1d10e25f36b1bcbdfe7881221ab863a28f0b75f2e179'
        '_wt_history_profiles_4_5_1_rehydrated_generated.lua' = 'c3a0167e80e4980c660b203f0b9aebb62a4672f55ec122f4426f6d7339c2b377'
        '_wt_history_profiles_4_5_1_to_4_6_generated.lua' = 'c4fb71879225b85e4021b541206536134b1a943c2112a43c590025bea33973b0'
        '_wt_history_profiles_current_6_12_0_generated.lua' = 'b37a67604422766c07a71c675c47d2f6ffeccd1710ca97d7320c50aaf723e3fb'
        '_wt_history_profiles_post_4_6_generated.lua' = '877cb30430d9bb9ffc28903586b9b4d483502790e2c557624da32585864a2351'
        '_wt_history_snapshot_4_5_1_rehydrated_generated.lua' = '048cfd627e4e894277d030615cb3a31f84c5c6d43615270d02dd2fba52846e98'
        '_wt_history_snapshot_4_5_1_to_4_6_generated.lua' = 'd26d7fdc14928639d9ea224783a4f5157a8af505ed8b12871996d68c34765945'
    }
    $actual = @(Get-ChildItem -LiteralPath $evidence -File -Filter '*.lua' |
        ForEach-Object Name)
    if ($actual.Count -ne 8 -or ($actual | Where-Object {
        $_ -ne '_wt_history_4_6_source_catalog.lua' -and -not $ledger.Contains($_)
    }).Count) {
        throw 'Patch 4.6 evidence directory census drift'
    }
    foreach ($row in $ledger.GetEnumerator()) {
        if ((Hash (Join-Path $evidence $row.Key)) -cne $row.Value) {
            throw "evidence ledger drift: $($row.Key)"
        }
    }
    $sourceText = [IO.File]::ReadAllText($sourceCatalog, [Text.Encoding]::UTF8)
    if ($sourceText.IndexOf($anchor.ContentRevision,
        [StringComparison]::Ordinal) -lt 0) {
        throw 'Patch 4.6 source catalog current anchor drift'
    }

    $old = '0cec9547152a395c4f35f75288f29d8b18b8294f'
    $post = 'b38754a3bd61983118215359845d5b4fe5005014'
    $current = $anchor.ContentRevision
    $power = 'scripts/settings/equipment/power_level_templates.lua'
    $damage = 'scripts/settings/equipment/damage_profile_templates.lua'
    $morris = 'scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua'
    $cog = 'scripts/settings/equipment/damage_profile_templates_dlc_cog.lua'
    $woods = 'scripts/settings/equipment/damage_profile_templates_dlc_woods.lua'
    $template = 'scripts/settings/equipment/weapon_templates/shortbows_hagbane.lua'
    $files = @(
        @($power, '13eeccec333d072261afd1705d4e18c8a411095e', '13eeccec333d072261afd1705d4e18c8a411095e', '6eba753d985ea80057947ed1ae1a25214204783e'),
        @($damage, '6653fb47c9ee40611bc0525fd62bc7f927c17fdf', 'c0b1c1f09996eb009b4a269ddc60db005e862061', 'e8330328d0085f6aee09e0495ba88fdc0211d5aa'),
        @($morris, 'a3f8460405a808442bd4f53bc8de424ac934a3cb', '314db1d53cdbd2bd6654df4d87f3244819d22653', 'a7f6e9e9fd9eb3e862c4c7a1ea5babfc5c43a733'),
        @($cog, '5c5c41c056c16ba0624eca1b4e918eb80c41dd28', '5c5c41c056c16ba0624eca1b4e918eb80c41dd28', '01d295acab5e5850c83f31939124ca3124edc403'),
        @($woods, '8722245ebf343116dfd8164b7ff15356e1d37ba8', '5ceb7298a2e3f2394b1bef37e2c3d659738eeae3', 'c379649a9dd9366004ac6e2221780f10dcfec581'),
        @($template, '2450220312570da7d14a3741edcf6c4d3ae0ec70', 'ca19bd7d9c02702bd82b0f2dddc40fa75bb79fdc', '9803627f8e1a4573b6dbea8b11f8836e7460214f')
    )
    if (@($files).Count -ne 6 -or
        @($files | ForEach-Object { $_[0] } | Select-Object -Unique).Count -ne 6) {
        throw 'Patch 4.6 declared source dependency closure drift'
    }
    $requirements = foreach ($file in $files) {
        for ($index = 1; $index -le 3; $index++) {
            [pscustomobject]@{
                Revision = @($old, $post, $current)[$index - 1]
                Path = $file[0]
                Blob = $file[$index]
            }
        }
    }
    if (@($requirements).Count -ne 18) {
        throw 'Patch 4.6 revision/path/blob requirement closure drift'
    }
    $selection = Find-WtHistorySourceRepo -Root $root -Explicit $SourceRepo `
        -Requirements $requirements
    $source = $selection.Path
    if (-not $source) {
        if ($RequireSource) {
            throw "source checkout is required but unavailable or incomplete: $($selection.Rejections -join '; ')"
        }
        Write-Host '[check_wt_history_patch_4_6_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned artifacts OK)' -ForegroundColor Yellow
        exit 0
    }

    $tamperedRequirements = @($requirements | ForEach-Object {
        [pscustomobject]@{
            Revision = $_.Revision
            Path = $_.Path
            Blob = $_.Blob
        }
    })
    $tamperedRows = @($tamperedRequirements | Where-Object {
        $_.Revision -ceq $current -and $_.Path -ceq $woods
    })
    if ($tamperedRows.Count -ne 1) {
        throw 'Patch 4.6 hidden-profile adversary target drift'
    }
    $tamperedRows[0].Blob = '0000000000000000000000000000000000000000'
    $tamperedSelection = Find-WtHistorySourceRepo -Root $root -Explicit $source `
        -Requirements $tamperedRequirements
    if ($tamperedSelection.Path -or
        (($tamperedSelection.Rejections -join '; ').IndexOf(
            'blob mismatch', [StringComparison]::Ordinal) -lt 0)) {
        throw 'Patch 4.6 one-blob-mismatch source-selection adversary failed'
    }

    $gitReadOnlyGuardArmed = $true
    Enter-ReadOnlyGitEnvironment
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $tmp = Join-Path $tempBase ('wt1436-p46-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        foreach ($evaluatorPath in @($extractor, $oracle)) {
            & $lua $evaluatorPath --self-test | Out-Null
            if ($LASTEXITCODE) { throw 'numeric/presence self-test failed' }
        }
        $adjacentProfiles = Join-Path $evidence '_wt_history_profiles_4_5_1_to_4_6_generated.lua'
        $adjacentTemplate = Join-Path $evidence '_wt_history_snapshot_4_5_1_to_4_6_generated.lua'
        $jobs = @(
            [pscustomobject]@{ Name = 'template-a'; Arguments = @($old, $post, $template); Evidence = '_wt_history_snapshot_4_5_1_to_4_6_generated.lua' },
            [pscustomobject]@{ Name = 'template-r'; Arguments = @('--rehydrate-snapshot', $old, $current, $adjacentTemplate); Evidence = '_wt_history_snapshot_4_5_1_rehydrated_generated.lua' },
            [pscustomobject]@{ Name = 'profile-a'; Arguments = @('--profiles', $old, $post, $power, $damage); Evidence = '_wt_history_profiles_4_5_1_to_4_6_generated.lua' },
            [pscustomobject]@{ Name = 'profile-h'; Arguments = @('--rehydrate-profiles', $old, $current, $adjacentProfiles); Evidence = '_wt_history_profiles_4_5_1_rehydrated_generated.lua' },
            [pscustomobject]@{ Name = 'profile-p'; Arguments = @('--rehydrate-profiles', $post, $post, $adjacentProfiles); Evidence = '_wt_history_profiles_post_4_6_generated.lua' },
            [pscustomobject]@{ Name = 'profile-c'; Arguments = @('--rehydrate-profiles', $current, $current, $adjacentProfiles); Evidence = '_wt_history_profiles_current_6_12_0_generated.lua' }
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
            $comparison = @(& $lua $oracle --compare-evidence `
                $checked $oracleOut 2>&1)
            if ($LASTEXITCODE) {
                throw "independent evidence differs ($($job.Name)): $($comparison -join ' ')"
            }
        }

        $routeOut = Join-Path $tmp 'routes-oracle.lua'
        Generate $lua $oracle @('--source-repo', $source, '--routes', $current, $spec) `
            $root $routeOut
        if ((Hash $routeOut) -cne (Hash (Join-Path $evidence '_wt_history_4_6_routes_oracle.lua'))) {
            throw 'Patch 4.6 current profile routes are not byte-reproducible'
        }

        $catalogOut = Join-Path $tmp 'catalog.lua'
        Assert-ReadOnlyGitGuard
        $log = @(& $lua $generator $source $evidence $catalogOut 2>&1)
        if ($LASTEXITCODE) { throw "catalog generator failed: $($log -join ' ')" }
        if ((Hash $catalogOut) -cne (Hash $catalog)) {
            throw 'Patch 4.6 catalog is not byte-reproducible'
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            if (@(Get-ChildItem $tmp -Directory -Force).Count) {
                throw 'unsafe non-flat temp cleanup'
            }
            Get-ChildItem $tmp -File -Force | Remove-Item -Force
            Remove-Item $tmp -Force
        }
    }
    Detail "[check_wt_history_patch_4_6_reproducibility] OK - exact Hagbane boundary, exclusions, independent oracle, two private profiles, and two current routes reproduced from $source"
    exit 0
} catch {
    Write-Host "[check_wt_history_patch_4_6_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red
    exit 2
} finally {
    if ($gitReadOnlyGuardArmed) {
        Restore-ReadOnlyGitEnvironment $gitEnvironment
    }
}
