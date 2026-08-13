# Compatibility entry point for the deployed CURRENT LIVE TEST source contract.
#
# Source discovery and finite-output proofs live in live_test_source_authority.ps1.
# This wrapper preserves the public API merged in #1296 and owns the offline
# adversarial fixture used by the lifecycle guard.

$sourceAuthorityPath = Join-Path $PSScriptRoot 'live_test_source_authority.ps1'
if (-not (Test-Path -LiteralPath $sourceAuthorityPath -PathType Leaf)) {
    throw "Live-test source authority is missing: $sourceAuthorityPath"
}
. $sourceAuthorityPath

function Get-VtDeployedSourceContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)]$ReleaseManifest
    )
    return Get-VtCardSourceAuthority -RepoRoot $RepoRoot -DeploymentManifest $ReleaseManifest
}

function Assert-VtContractFixture {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Invoke-VtDeployedSourceContractSelfTest {
    $tempBase = [IO.Path]::GetTempPath()
    $tmp = Join-Path $tempBase ('vt2-live-card-contract-' + [guid]::NewGuid().ToString('N'))
    $utf8 = New-Object Text.UTF8Encoding($false)
    try {
        [IO.Directory]::CreateDirectory((Join-Path $tmp 'tools\verify')) | Out-Null
        $luaRoot = Join-Path $tmp 'fixture_mod\scripts\mods\fixture_mod'
        [IO.Directory]::CreateDirectory($luaRoot) | Out-Null
        [IO.File]::WriteAllText((Join-Path $tmp 'tools\mod-inventory.psd1'), @'
@{ Mods = @(
    @{ Dir='fixture_mod'; ModId='fixture'; WorkshopId='1234567890'; Name='Fixture' }
) }
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $tmp 'tools\verify\live_test_contract_exceptions.psd1'), @'
@{
    LegacySourceTrees=@()
    ReceiptRouteOverrides=@()
    ReceiptFamilyOverrides=@()
    ReceiptDiscoveryOverrides=@()
}
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $luaRoot 'fixture_mod.lua'), @'
local MOD_VERSION = "1.2.3-dev"
local banner_bait = "[bait:LOAD] v%s enabled fp=fake OK"
local phantom_command = 'mod:command("phantom", "not registered", function() end)'
local string_data = 'printf("[fx:string-data]")'
local long_data = [=[printf("[fx:long-string]")]=]
-- printf("[fx:comment]")
local fakeprintf = function() end
fakeprintf("[fx:fake]")
mod.printf("[fx:member-call]")
pcall(printf, "[fx:LOAD] v%s enabled fp=test OK", MOD_VERSION)
mod:command("fx_probe", "Fixture probe", function()
    pcall(printf, "[fx:probe] status=OK")
end)
mod:command([=[fx_long_probe]=], [=[Long-bracket fixture probe]=], function()
    pcall(printf, [=[[fx:long-argument] status=OK]=])
end)
mod:command("fx_other", "Unrelated fixture command", function() end)
if false then
    pcall(printf, "[dead:LOAD] v%s enabled fp=dead OK", MOD_VERSION)
    mod:info("[dead] v%s loaded", MOD_VERSION)
    mod:command("dead_probe", "Unreachable command", function()
        printf("[dead:receipt] status=impossible")
    end)
end
mod:command("fx_goto", "Backward-goto fixture", function()
    ::again::
    printf("[fx:goto-cycle] status=unbounded")
    goto again
end)
local function async_probe()
    printf("[fx:async-command] status=OK")
end
mod:command("fx_async", "Audited helper fixture", function()
    async_probe()
end)
mod:command("fx_bait", (function()
    printf("[fx:unrelated-command-context]")
    return "description"
end)(), function() end)
mod:command("fx_nested", "Nested callback fixture", function()
    local function retained_callback()
        printf("[fx:nested-command-function]")
    end
    mod._fixture_retained_callback = retained_callback
end)
mod:command("fx_loop", "Loop callback fixture", function()
    while mod._fixture_loop do
        printf("[fx:command-loop]")
    end
end)
while mod._fixture_main_loop do
    printf("[fx:main-loop]")
end
function mod.update()
    printf("[fx:per-frame]")
    printf("[cwv:491] view_tag=%s observed_unit=%s reason=%s retained=%s current=none other_player=none", "hero_1", "unit_1", "fixture", "true")
end
mod:dofile("scripts/mods/fixture_mod/_helper").install(mod, { log = printf })
mod:dofile("scripts/mods/fixture_mod/_early").install(mod, { log = printf })
pcall(mod.dofile, mod, "scripts/mods/fixture_mod/_pcall_helper")
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $luaRoot '_helper.lua'), @'
local M = {}
printf("[fx:helper-top-level]")
local emit = assert(deps.log)
function M.install()
    emit("[fx:alias-ok] status=%s", "OK")
end
return M
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $luaRoot '_early.lua'), @'
local M = {}
early("[fx:alias-before-declaration]")
local early = assert(deps.log)
function M.install()
    early("[fx:alias-after-ambiguous-declaration]")
end
return M
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $luaRoot '_pcall_helper.lua'), @'
printf("[fx:pcall-reachable] status=loaded")
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $luaRoot '_shadow.lua'), @'
local printf = mod.debug
printf("[fx:shadow]")
local reassigned = assert(deps.log)
reassigned = mod.debug
reassigned("[fx:reassigned]")
local multi = assert(deps.log)
local second = multi
second("[fx:multi-hop]")
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $luaRoot '_multi_shadow.lua'), @'
local first, printf, third = nil, mod.debug, nil
printf("[fx:multi-local-shadow]")
for _, printf in pairs({}) do
    printf("[fx:for-shadow]")
end
printf, third = mod.debug, nil
printf("[fx:multi-assignment-shadow]")
'@, $utf8)
        [IO.File]::WriteAllText((Join-Path $luaRoot '_unreachable.lua'), @'
printf("[unreachable:LOAD] v%s enabled fp=dead OK", "1.2.3-dev")
mod:info("[unreachable] v%s loaded", "1.2.3-dev")
mod:command("unreachable_probe", "Unloaded command", function()
    printf("[unreachable:receipt] status=impossible")
end)
'@, $utf8)
        & git -C $tmp init -q
        & git -C $tmp config user.email 'fixture@example.invalid'
        & git -C $tmp config user.name 'VT2 Contract Fixture'
        & git -C $tmp config core.autocrlf false
        & git -C $tmp add -- .
        & git -C $tmp commit -q -m fixture
        if ($LASTEXITCODE -ne 0) { throw 'Could not commit deployed-source contract fixture.' }
        $commit = (& git -C $tmp rev-parse HEAD).Trim()
        $fixtureModTree = (& git -C $tmp rev-parse "$commit`:fixture_mod/scripts/mods").Trim()
        [IO.File]::WriteAllText((Join-Path $tmp 'tools\verify\live_test_contract_exceptions.psd1'), @"
@{
    LegacySourceTrees=@()
    ReceiptFamilyOverrides=@()
    ReceiptDiscoveryOverrides=@()
    ReceiptRouteOverrides=@(
        @{
            ModId='fixture';ModTree='$fixtureModTree'
            Source='fixture_mod/scripts/mods/fixture_mod/fixture_mod.lua'
            Marker='[fx:async-command]';Signature='[fx:async-command] status=OK'
            Bound='one helper call in each explicit /fx_async callback transaction'
            ActionCommands=@('/fx_async')
            EmitterAnchors=@(@{Tokens=@('printf','(','String:[fx:async-command] status=OK',')')})
            GuardAnchors=@(
                @{Tokens=@('local','function','async_probe','(',')')},
                @{Tokens=@('mod',':','command','(','String:fx_async')},
                @{Tokens=@('async_probe','(',')')}
            )
        }
    )
}
"@, $utf8)
        $manifest = [pscustomobject]@{
            manifest_schema = 2
            release_tag = 'mods-fixture'
            published_at = '2026-08-13T00:00:00Z'
            mods = @([pscustomobject]@{
                mod_id='fixture'
                friendly_name='Fixture'
                workshop_id='1234567890'
                version='1.2.3-dev'
                source_commit=$commit
                source_state='clean'
            })
        }

        $contract = Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest
        Assert-VtContractFixture (@($contract.Records).Count -eq 1) 'Fixture authority did not resolve exactly one record.'
        $record = @($contract.Records)[0]
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -contains '[fx:LOAD]') 'Literal LOAD route was not recovered.'
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -notcontains '[bait:LOAD]') 'String-only LOAD bait was accepted.'
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -notcontains '[dead:LOAD]') 'Literal-false LOAD route was accepted.'
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -notcontains '[unreachable:LOAD]') 'Unloaded-document LOAD route was accepted.'
        Assert-VtContractFixture (@($record.ExactBannerRoutes.Tag) -notcontains '[dead]') 'Literal-false exact banner was accepted.'
        Assert-VtContractFixture (@($record.ExactBannerRoutes.Tag) -notcontains '[unreachable]') 'Unloaded-document exact banner was accepted.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -contains '/fx_probe') 'Exact command registration was not recovered.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -contains '/fx_long_probe') 'Long-bracket command argument was not recovered.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains '/phantom') 'String-only phantom command was accepted.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains '/dead_probe') 'Literal-false command registration was accepted.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains '/unreachable_probe') 'Unloaded-document command registration was accepted.'

        $routes = @($record.ReceiptRoutes)
        Assert-VtContractFixture (@($routes.Signature) -contains '[fx:probe] status=OK') 'Direct printf receipt was not recovered.'
        Assert-VtContractFixture (@($routes.Signature) -contains '[fx:long-argument] status=OK') 'Long-bracket printf argument was not recovered.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:probe] status=OK' -and $_.Bound }).Count -eq 1) 'Explicit-command receipt was not bounded.'
        Assert-VtContractFixture (@($routes | Where-Object {
            $_.Signature -eq '[fx:probe] status=OK' -and @($_.ActionCommands) -contains '/fx_probe'
        }).Count -eq 1) 'Explicit-command receipt was not bound to its exact action command.'
        Assert-VtContractFixture (@($routes.Signature) -notcontains '[dead:receipt] status=impossible') 'Literal-false receipt route was accepted.'
        Assert-VtContractFixture (@($routes.Signature) -notcontains '[unreachable:receipt] status=impossible') 'Unloaded-document receipt route was accepted.'
        Assert-VtContractFixture (@($routes | Where-Object {
            $_.Signature -eq '[fx:goto-cycle] status=unbounded' -and -not $_.Bound -and @($_.ActionCommands) -contains '/fx_goto'
        }).Count -eq 1) 'Backward-goto command receipt was incorrectly certified loop-free.'
        Assert-VtContractFixture (@($routes | Where-Object {
            $_.Signature -eq '[fx:async-command] status=OK' -and $_.Bound -and @($_.ActionCommands) -contains '/fx_async' -and
            [string]$_.BoundProof -like 'override:*'
        }).Count -eq 1) 'Immutable async-helper override did not bind its exact action command.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:per-frame]' -and -not $_.Bound }).Count -eq 1) 'Per-frame receipt was not rejected as unbounded.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:helper-top-level]' -and -not $_.Bound }).Count -eq 1) 'Repeatable helper top-level receipt was accepted as module-lifetime bounded.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:unrelated-command-context]' -and -not $_.Bound }).Count -eq 1) 'An unrelated function inside mod:command arguments was accepted as the command callback.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:nested-command-function]' -and -not $_.Bound }).Count -eq 1) 'A retained function nested inside a command callback was accepted as the command callback itself.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:command-loop]' -and -not $_.Bound }).Count -eq 1) 'A command-callback loop was accepted without an immutable finite-bound proof.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:main-loop]' -and -not $_.Bound }).Count -eq 1) 'A framework-main loop was accepted without an immutable finite-bound proof.'
        Assert-VtContractFixture (@($routes | Where-Object {
            $_.Marker -eq '[cwv:491]' -and -not $_.Bound
        }).Count -eq 1) 'Merged #491 fail-open regression: the per-frame receipt was not retained as unbounded.'
        foreach ($forbidden in '[fx:string-data]','[fx:long-string]','[fx:comment]','[fx:fake]','[fx:member-call]','[fx:shadow]','[fx:multi-local-shadow]','[fx:for-shadow]','[fx:multi-assignment-shadow]','[fx:global-member-shadow]','[fx:global-rawset-shadow]','[fx:reassigned]','[fx:multi-hop]','[fx:alias-before-declaration]','[fx:alias-after-ambiguous-declaration]') {
            Assert-VtContractFixture (@($routes.Signature) -notcontains $forbidden) "Phantom or ambiguous route was accepted: $forbidden"
        }
        Assert-VtContractFixture (@($routes.Signature) -contains '[fx:alias-ok] status=%s') 'One-hop raw printf injection was not recovered.'
        Assert-VtContractFixture (@($routes.Signature) -contains '[fx:pcall-reachable] status=loaded') 'Literal pcall(mod.dofile, mod, path) reachability was not recovered.'

        $mutationCases=@(
            '_G.printf = mod.debug',
            '_G["printf"] = mod.debug',
            'rawset(_G, "printf", mod.debug)',
            'getfenv(0).printf = mod.debug',
            'local env = getfenv(0); env.printf = mod.debug',
            'rawset(getfenv(2), "printf", mod.debug)',
            'setfenv(0, {})',
            'debug.setfenv(0, {})',
            'pcall(setfenv, 0, {})'
        )
        foreach($mutationCase in $mutationCases){
            Assert-VtContractFixture (Test-VtLuaMutatesGlobalPrintf -Tokens @(Get-VtLuaTokens -Content $mutationCase)) "Global/environment printf mutation was not rejected: $mutationCase"
        }
        foreach($safeCase in @(
            'local bait = ''_G.printf = fake'' -- rawset(_G, "printf", fake)',
            'local pf = rawget(_G, "printf")',
            'local env = getfenv(M.dump)'
        )){
            Assert-VtContractFixture (-not(Test-VtLuaMutatesGlobalPrintf -Tokens @(Get-VtLuaTokens -Content $safeCase))) "Read-only/string global printf bait was rejected: $safeCase"
        }

        # Cross-file trust is record-wide: a clean main document cannot lend
        # raw printf authority when any sibling mutates the ambient logger.
        [IO.File]::WriteAllText((Join-Path $luaRoot '_global_shadow.lua'), @'
rawset(_G, "printf", mod.debug)
'@, $utf8)
        & git -C $tmp add -- .
        & git -C $tmp commit -q -m 'plant cross-file global printf mutation'
        if($LASTEXITCODE -ne 0){throw 'Could not commit cross-file global printf fixture.'}
        $mutatingCommit=(& git -C $tmp rev-parse HEAD).Trim()
        $manifest.mods[0].source_commit=$mutatingCommit
        $rejected=$false
        try{Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest|Out-Null}
        catch{$rejected=$_.Exception.Message -match 'mutates global/environment printf'}
        Assert-VtContractFixture $rejected 'Cross-file global printf mutation did not reject the complete deployed record.'
        $manifest.mods[0].source_commit=$commit

        $manifest.mods[0].source_state = 'dirty'
        $rejected = $false
        try { Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest | Out-Null }
        catch { $rejected = $_.Exception.Message -match 'source_state must be clean' }
        Assert-VtContractFixture $rejected 'Dirty deployed source was accepted.'
        $manifest.mods[0].source_state = 'clean'

        $manifest.mods[0].version = '1.2.4-dev'
        $rejected = $false
        try { Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest | Out-Null }
        catch { $rejected = $_.Exception.Message -match 'MOD_VERSION drift' }
        Assert-VtContractFixture $rejected 'Manifest/source version mismatch was accepted.'
        $manifest.mods[0].version = '1.2.3-dev'

        $manifest.mods += [pscustomobject]@{
            mod_id='fixture'
            friendly_name='Duplicate'
            workshop_id='9999999999'
            version='1.2.3-dev'
            source_commit=$commit
            source_state='clean'
        }
        $rejected = $false
        try { Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest | Out-Null }
        catch { $rejected = $_.Exception.Message -match 'duplicate mod_id' }
        Assert-VtContractFixture $rejected 'Duplicate release mod_id was accepted.'

        $exceptions = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'live_test_contract_exceptions.psd1')
        $requiredRoutes = @(
            # Seven exact routes the superseding audit proved were legitimate
            # false rejects in the merged marker-wide scanner.
            @{ Marker='[gut:217]'; Signature='[gut:217] compendium tabs injected into HeroWindowPanelConsole definitions (Armory, Bestiary)' },
            @{ Marker='[gut_dev:NATIVE_LOADOUTS]'; Signature='[gut_dev:NATIVE_LOADOUTS] #375 selected-read career=%s caller=%s requested=%s resolved=%s selected=%s row=[melee=%s ranged=%s] canonical=[melee=%s ranged=%s] served=[slot=%s value=%s source=%s]' },
            @{ Marker='[wt:661]'; Signature='[wt:661] wield-boundary item=%s career=%s template=%s result=%s trace=%d/%d' },
            @{ Marker='[cos:373]'; Signature='[cos:373] receiver coverage OK: no magic/runed shield family gaps' },
            @{ Marker='[cos:704]'; Signature='[cos:704] summary inspected=%d suspects=%d emitted=%d truncated=%s signature_truncated=%s signature_bytes=%d' },
            @{ Marker='[cwv:343]'; Signature='[cwv:343] status=%s base=%s area=%s pool=%d/%.6f healthy=%s exact_z_scale=%s registration_quarantined=%s' },
            @{ Marker='[crt:699]'; Signature='[crt:699] icon active=true subject=%s buff=%s role=%s template=%s expected=%s icon=%s atlas=%s atlas_id=%s widget=%s widget_icon=%s semantic_match=%s numb_collision=%s hud_widgets=%d hud_capacity=%d hidebuffs=%s hidden=%s priority=%s' },
            # Current bounded routes surfaced by the independent merge audit.
            @{ Marker='[ct:skull52]'; Signature='[ct:skull52] %s' },
            @{ Marker='[gt:488]'; Signature='[gt:488] bot-hazard type=%s milestone=%s active_before=%d active_after=%d damage_in=%.3f damage_out=%.3f record=%d/%d' },
            @{ Marker='[gt:488]'; Signature='[gt:488] ratling-shield state=%d/%d wielded=%s wielded_template=%s wielded_shield=%s melee_template=%s melee_shield=%s blocking=%s projectile_hit=%s victim_self=%s taking_cover=%s input=%s mutation=0' },
            @{ Marker='[WOC:boss-catalog]'; Signature='[WOC:boss-catalog] facet=authored id=%s issue=%s stage=%s status=%s registration_enabled=%s required=%s missing=%s' },
            @{ Marker='[cos:656]'; Signature='[cos:656] registered skin=%s donor=%s vanilla_geometry=true enabled=%s' },
            @{ Marker='[cwv:760]'; Signature='[cwv:760] surface=%s career=%s event=%s result=%s source=%s evidence=%d/%d visual=unverified' }
        )
        foreach ($required in $requiredRoutes) {
            $matches = @($exceptions.ReceiptRouteOverrides | Where-Object {
                [string]$_.Marker -ceq [string]$required.Marker -and
                [string]$_.Signature -ceq [string]$required.Signature -and
                @($_.EmitterAnchors).Count -gt 0 -and @($_.GuardAnchors).Count -gt 0
            })
            Assert-VtContractFixture ($matches.Count -eq 1) "Exact prior false-reject route is not anchored: $($required.Marker)"
        }
        $unsafe491 = @(
            @($exceptions.ReceiptRouteOverrides) +
            @($exceptions.ReceiptFamilyOverrides) +
            @($exceptions.ReceiptDiscoveryOverrides) |
                Where-Object { [string]$_.Marker -ceq '[cwv:491]' }
        )
        Assert-VtContractFixture ($unsafe491.Count -eq 0) 'Known-unbounded [cwv:491] received an override.'

        Write-Host '[live-test-contract -SelfTest] OK'
    }
    finally {
        $resolvedBase = [IO.Path]::GetFullPath($tempBase).TrimEnd([char[]]@('\', '/'))
        $resolvedTarget = [IO.Path]::GetFullPath($tmp)
        if ($resolvedTarget.StartsWith($resolvedBase + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedTarget) -like 'vt2-live-card-contract-*' -and
            [IO.Directory]::Exists($resolvedTarget)) {
            foreach ($file in [IO.Directory]::EnumerateFiles($resolvedTarget, '*', [IO.SearchOption]::AllDirectories)) {
                [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
            }
            [IO.Directory]::Delete($resolvedTarget, $true)
        }
    }
}
