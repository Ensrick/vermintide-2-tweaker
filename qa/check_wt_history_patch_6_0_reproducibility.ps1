# Blocking offline provenance/reproduction gate for issue #1436's bounded
# Patch 6.0 slice. Generated output stays in a flat OS-temp directory.
[CmdletBinding()]
param([string]$RepoRoot, [string]$SourceRepo, [switch]$RequireSource,
    [switch]$Quiet)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Join-Path $PSScriptRoot '..' }
function Hash([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Detail([string]$Text) { if (-not $Quiet) { Write-Host $Text -ForegroundColor DarkGray } }
function Generate([string]$Lua, [string]$Script, [string[]]$Arguments,
    [string]$Cwd, [string]$Out) {
    $had = Test-Path Env:WT_HISTORY_OUTPUT; $prior = $env:WT_HISTORY_OUTPUT
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
try {
    $root = (Resolve-Path -LiteralPath $RepoRoot).Path
    . (Join-Path $root 'tools\weapon-history\source-anchor.ps1')
    $anchor = Read-WtHistorySourceAnchor -RepoRoot $root
    $tool = Join-Path $root 'tools\weapon-history'
    $evidence = Join-Path $tool 'evidence\patch_6_0'
    $extractor = Join-Path $tool 'extract_weapon_history.lua'
    $oracle = Join-Path $tool 'source_oracle\extract_weapon_history_oracle.lua'
    $generator = Join-Path $tool 'generate_patch_6_0_history.lua'
    $sourceCatalog = Join-Path $evidence '_wt_history_6_0_source_catalog.lua'
    $catalog = Join-Path $root 'weapon_tweaker\scripts\mods\weapon_tweaker\_wt_history_6_0_catalog.lua'
    $devCatalog = Join-Path $root 'weapon_tweaker_dev\scripts\mods\weapon_tweaker_dev\_wt_history_6_0_catalog.lua'
    $lua = Join-Path $root 'qa\lua\vendor\lua-5.1.5-win64\lua5.1.exe'
    $pins = [ordered]@{
        $extractor='ae916ba306e0f5933f71e9b41ed0c0e7df46c28585da4fb92b5e2cc03199b15a'
        $oracle='767c73dd8f2caf35575324aae7ac09e2460a3506f9ad6c8296d2bee6e973a2d5'
        $generator='18762b353dc2e4896f2dd8845e74b881083330fd2e5b3293d906c6d2c94ef754'
        $sourceCatalog='e450a95939b4d39ae6011e30e2283f969282ceeeb92b36e7e0737f2bbb1c918f'
        $catalog='7ba475c8ab7a8e635b1bfde179a867dde8594af654cce5ce1d70255e1bdae826'
        $devCatalog='7ba475c8ab7a8e635b1bfde179a867dde8594af654cce5ce1d70255e1bdae826'
    }
    foreach ($pin in $pins.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $pin.Key -PathType Leaf) -or
            (Hash $pin.Key) -cne $pin.Value) { throw "pinned artifact drift: $($pin.Key)" }
    }
    $ledger = @{
        '_wt_history_profiles_current_6_12_0_generated.lua'='3c593a19fb8fd7ff8c8c0c35e2105a1ebdf46d2600dee98d971a89dc3cfddd95'
        '_wt_history_profiles_5_6_1_rehydrated_generated.lua'='e7d7c5c14526b2e09c0c74827a4e1760d1aaab65751273fe1386d8b337968943'
        '_wt_history_profiles_5_6_1_to_6_0_generated.lua'='990537de0d7405883f1cc2b9b70a0fba07a7a2cc1b99c66d4507c73c36ee2685'
        '_wt_history_snapshot_5_6_1_breton_rehydrated_generated.lua'='61837ef47d543637fa7554a8f0c0416cde2ef32bc789fb1a1344612535394763'
        '_wt_history_snapshot_5_6_1_breton_to_6_0_generated.lua'='ba310d502f9395db0a87d0670254034187efcea2f7e91db52db3a541d875f905'
        '_wt_history_snapshot_5_6_1_sword_shield_rehydrated_generated.lua'='e6fafa985f7fd4d8e1e36733e9672be62ebfdc446b62bd8d1125fc6c7e7bb9ce'
        '_wt_history_snapshot_5_6_1_sword_shield_to_6_0_generated.lua'='c875fb82bc37f2841dd99ad598f3b16bf755c44f2f82dae2356b26decd047791'
    }
    $actual = @(Get-ChildItem -LiteralPath $evidence -File -Filter '*.lua' | ForEach-Object Name)
    if ($actual.Count -ne 8 -or ($actual | Where-Object { $_ -ne '_wt_history_6_0_source_catalog.lua' -and -not $ledger.ContainsKey($_) }).Count) {
        throw 'Patch 6.0 evidence directory census drift'
    }
    foreach ($row in $ledger.GetEnumerator()) {
        if ((Hash (Join-Path $evidence $row.Key)) -cne $row.Value) {
            throw "evidence ledger drift: $($row.Key)"
        }
    }
    if ([IO.File]::ReadAllText($sourceCatalog).IndexOf($anchor.ContentRevision,
        [StringComparison]::Ordinal) -lt 0) { throw 'current source anchor drift' }
    $old='f64ecd2495bd26b1b0a4d296970bef0a0d7a06a9'; $post='da0bbdaf6af1ca7e8c96e7892a3416a4aa8a7f87'; $current=$anchor.ContentRevision
    $files = @(
        @('scripts/settings/equipment/weapon_templates/1h_swords_shield.lua','70e77acd479b141c577eadf37097f6f909f4de6d','86dd1780c0d47b7498eb1e82e9c1555b1c3a3453','aed608e09cb504a3ac403e01e3a207630233044c'),
        @('scripts/settings/equipment/weapon_templates/1h_swords_shield_breton.lua','67f836c0f9f024889ad8aec2b1dbe92a503a7434','3131d0570530893d4edde6edd8ac126de8c1cff3','e8463479350cb9a3195f553f46dabd2d658d279e'),
        @('scripts/settings/equipment/power_level_templates.lua','4a0d78a4d6125bb3f14575b505fb3d4c2d014094','4a0d78a4d6125bb3f14575b505fb3d4c2d014094','6eba753d985ea80057947ed1ae1a25214204783e'),
        @('scripts/settings/equipment/damage_profile_templates.lua','e5d56cfb8de366baf1a946f70566ea052688c969','2daa213ce02ae4199a2f8147c8fb1d6753be59f2','e8330328d0085f6aee09e0495ba88fdc0211d5aa'),
        @('scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua','a5276cb9dbea4bbdf642905ef6b7b9cd3ad4e7fa','8bc80fad3e34e165a942c4969e27ae418dc6ae08','a7f6e9e9fd9eb3e862c4c7a1ea5babfc5c43a733'),
        @('scripts/settings/equipment/damage_profile_templates_dlc_cog.lua','01d295acab5e5850c83f31939124ca3124edc403','01d295acab5e5850c83f31939124ca3124edc403','01d295acab5e5850c83f31939124ca3124edc403'),
        @('scripts/settings/equipment/damage_profile_templates_dlc_woods.lua','c379649a9dd9366004ac6e2221780f10dcfec581','c379649a9dd9366004ac6e2221780f10dcfec581','c379649a9dd9366004ac6e2221780f10dcfec581'),
        @('scripts/settings/equipment/weapon_templates/staff_fireball_fireball.lua','1cc99c0b50d2a215807cc5aa11cefad0e2044174','18fc3da707e6bf155a12118361b43c176401e916','18fc3da707e6bf155a12118361b43c176401e916'))
    $requirements = foreach($f in $files) { for($i=1;$i -le 3;$i++){ [pscustomobject]@{Revision=@($old,$post,$current)[$i-1];Path=$f[0];Blob=$f[$i]} } }
    $selection = Find-WtHistorySourceRepo -Root $root -Explicit $SourceRepo -Requirements $requirements
    $source=$selection.Path
    if (-not $source) {
        if ($RequireSource) { throw "source checkout is required but unavailable or incomplete: $($selection.Rejections -join '; ')" }
        Write-Host '[check_wt_history_patch_6_0_reproducibility] source checkout unavailable or incomplete; exact regeneration SKIP (pinned artifacts OK)' -ForegroundColor Yellow
        exit 0
    }
    $tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()); $tmp=Join-Path $tempBase ('wt1436-p60-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        foreach($s in @($extractor,$oracle)){ & $lua $s --self-test | Out-Null; if($LASTEXITCODE){throw 'numeric self-test failed'} }
        $jobs=@(
            [pscustomobject]@{Name='sword-a';Args=@($old,$post,$files[0][0]);Evidence='_wt_history_snapshot_5_6_1_sword_shield_to_6_0_generated.lua'},
            [pscustomobject]@{Name='sword-r';Args=@('--rehydrate-snapshot',$old,$current,(Join-Path $evidence '_wt_history_snapshot_5_6_1_sword_shield_to_6_0_generated.lua'));Evidence='_wt_history_snapshot_5_6_1_sword_shield_rehydrated_generated.lua'},
            [pscustomobject]@{Name='bret-a';Args=@($old,$post,$files[1][0]);Evidence='_wt_history_snapshot_5_6_1_breton_to_6_0_generated.lua'},
            [pscustomobject]@{Name='bret-r';Args=@('--rehydrate-snapshot',$old,$current,(Join-Path $evidence '_wt_history_snapshot_5_6_1_breton_to_6_0_generated.lua'));Evidence='_wt_history_snapshot_5_6_1_breton_rehydrated_generated.lua'},
            [pscustomobject]@{Name='prof-a';Args=@('--profiles',$old,$post,$files[2][0],$files[3][0],$files[4][0],$files[5][0],$files[6][0]);Evidence='_wt_history_profiles_5_6_1_to_6_0_generated.lua'},
            [pscustomobject]@{Name='prof-h';Args=@('--rehydrate-profiles',$old,$current,(Join-Path $evidence '_wt_history_profiles_5_6_1_to_6_0_generated.lua'));Evidence='_wt_history_profiles_5_6_1_rehydrated_generated.lua'},
            [pscustomobject]@{Name='prof-c';Args=@('--rehydrate-profiles',$current,$current,(Join-Path $evidence '_wt_history_profiles_5_6_1_to_6_0_generated.lua'));Evidence='_wt_history_profiles_current_6_12_0_generated.lua'})
        foreach($j in $jobs){
            $out=Join-Path $tmp ($j.Name+'-primary.lua')
            Generate $lua $extractor $j.Args $source $out
            $checked=Join-Path $evidence $j.Evidence
            if((Hash $out)-cne(Hash $checked)){throw "non-reproducible evidence: $($j.Name)"}
            $oracleOut=Join-Path $tmp ($j.Name+'-oracle.lua')
            Generate $lua $oracle (@('--source-repo',$source)+$j.Args) $root $oracleOut
            $comparison=@(& $lua $oracle --compare-evidence $checked $oracleOut 2>&1)
            if($LASTEXITCODE){throw "independent evidence differs ($($j.Name)): $($comparison -join ' ')"}
        }
        $out=Join-Path $tmp 'catalog.lua'; $log=@(& $lua $generator $source $evidence $out 2>&1); if($LASTEXITCODE){throw "catalog generator failed: $($log -join ' ')"};if((Hash $out)-cne(Hash $catalog)){throw 'catalog is not byte-reproducible'}
    } finally {
        if (Test-Path -LiteralPath $tmp) { if(@(Get-ChildItem $tmp -Directory -Force).Count){throw 'unsafe non-flat temp cleanup'}; Get-ChildItem $tmp -File -Force | Remove-Item -Force; Remove-Item $tmp -Force }
    }
    Detail "[check_wt_history_patch_6_0_reproducibility] OK - exact evidence and catalog reproduced from $source"
    exit 0
} catch { Write-Host "[check_wt_history_patch_6_0_reproducibility] ERROR - $($_.Exception.Message)" -ForegroundColor Red; exit 2 }
