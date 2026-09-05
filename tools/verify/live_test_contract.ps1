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
    @{ Dir='fixture_mod'; ModId='fixture'; WorkshopId='1234567890'; Visibility='public'; Stream='single'; Public=$true; Name='Fixture' }
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
local pcall_ok, pcall_value = pcall(mod.command, mod,
    "fx_pcall_probe", "Protected fixture probe",
    function()
        pcall(printf, "[fx:pcall-probe] status=OK")
    end)
local dynamic_command_name = "fx_dynamic_name"
pcall(mod.command, mod, dynamic_command_name, "Dynamic-name bait", function() end)
pcall(mod.command, mod, "fx_" .. dynamic_command_name, "Concatenated-name bait", function() end)
pcall(other.command, mod, "fx_foreign_callable", "Foreign-callable bait", function() end)
pcall(mod.command, other, "fx_foreign_self", "Foreign-self bait", function() end)
pcall(mod.commands, mod, "fx_near_member", "Near-member bait", function() end)
xpcall(mod.command, mod, "fx_near_wrapper", "Near-wrapper bait", function() end)
helper.pcall(mod.command, mod, "fx_member_pcall", "Member-pcall bait", function() end)
pcall(mod.command, mod, ("fx_parenthesized"), "Parenthesized-name bait", function() end)
pcall(mod.command, mod, "Fx_uppercase", "Invalid-name bait", function() end)
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
    pcall(mod.command, mod, "dead_pcall_probe", "Unreachable protected command", function()
        printf("[dead:pcall-receipt] status=impossible")
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
pcall(mod.dofile, mod, "scripts/mods/fixture_mod/_pcall_command_only")
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
        [IO.File]::WriteAllText((Join-Path $luaRoot '_pcall_command_only.lua'), @'
pcall(mod.command, mod, "fx_pcall_only", "Protected-only fixture probe", function() end)
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
                asset_filename='fixture_mod.zip'
                sha256=('e' * 64)
                source_commit=$commit
                source_state='clean'
                root_bundle='0123456789abcdef.mod_bundle'
                bundle_files=@([pscustomobject]@{
                    filename='0123456789abcdef.mod_bundle'
                    sha256=('f' * 64)
                })
            })
        }

        $contract = Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest
        Assert-VtContractFixture (@($contract.Records).Count -eq 1) 'Fixture authority did not resolve exactly one record.'
        $record = @($contract.Records)[0]
        Assert-VtContractFixture ([string]$record.Stream -ceq 'single') 'Inventory stream was not projected into card authority.'
        Assert-VtContractFixture ([string]$record.Visibility -ceq 'public') 'Inventory visibility was not projected into card authority.'
        Assert-VtContractFixture ([bool]$record.Public) 'Inventory public-release fact was not projected into card authority.'
        Assert-VtContractFixture ([string]$record.SourceCommit -ceq $commit) 'Exact source commit was not projected into card authority.'
        Assert-VtContractFixture ([string]$record.RootBundle -ceq '0123456789abcdef.mod_bundle') 'Root bundle filename was not projected into card authority.'
        Assert-VtContractFixture ([string]$record.RootBundleSha256 -ceq ('f' * 64)) 'Root bundle digest was not projected into card authority.'
        Assert-VtContractFixture ([string]$record.AssetFilename -ceq 'fixture_mod.zip') 'ZIP filename was not projected into card authority.'
        Assert-VtContractFixture ([string]$record.AssetSha256 -ceq ('e' * 64)) 'ZIP digest was not projected into card authority.'
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -contains '[fx:LOAD]') 'Literal LOAD route was not recovered.'
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -notcontains '[bait:LOAD]') 'String-only LOAD bait was accepted.'
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -notcontains '[dead:LOAD]') 'Literal-false LOAD route was accepted.'
        Assert-VtContractFixture (@($record.LoadRoutes.Marker) -notcontains '[unreachable:LOAD]') 'Unloaded-document LOAD route was accepted.'
        Assert-VtContractFixture (@($record.ExactBannerRoutes.Tag) -notcontains '[dead]') 'Literal-false exact banner was accepted.'
        Assert-VtContractFixture (@($record.ExactBannerRoutes.Tag) -notcontains '[unreachable]') 'Unloaded-document exact banner was accepted.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -contains '/fx_probe') 'Exact command registration was not recovered.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -contains '/fx_pcall_probe') 'Literal pcall(mod.command, mod, ...) registration was not recovered.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -contains '/fx_pcall_only') 'Protected command registration in a printf-free reachable document was not recovered.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -contains '/fx_long_probe') 'Long-bracket command argument was not recovered.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains '/phantom') 'String-only phantom command was accepted.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains '/dead_probe') 'Literal-false command registration was accepted.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains '/dead_pcall_probe') 'Literal-false protected command registration was accepted.'
        Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains '/unreachable_probe') 'Unloaded-document command registration was accepted.'
        foreach ($forbiddenCommand in '/fx_dynamic_name','/fx_','/fx_foreign_callable','/fx_foreign_self','/fx_near_member','/fx_near_wrapper','/fx_member_pcall','/fx_parenthesized','/Fx_uppercase') {
            Assert-VtContractFixture (@($record.CommandRoutes.Command) -notcontains $forbiddenCommand) "Ambiguous or near-match protected command registration was accepted: $forbiddenCommand"
        }

        $routes = @($record.ReceiptRoutes)
        Assert-VtContractFixture (@($routes.Signature) -contains '[fx:probe] status=OK') 'Direct printf receipt was not recovered.'
        Assert-VtContractFixture (@($routes.Signature) -contains '[fx:long-argument] status=OK') 'Long-bracket printf argument was not recovered.'
        Assert-VtContractFixture (@($routes | Where-Object { $_.Signature -eq '[fx:probe] status=OK' -and $_.Bound }).Count -eq 1) 'Explicit-command receipt was not bounded.'
        Assert-VtContractFixture (@($routes | Where-Object {
            $_.Signature -eq '[fx:probe] status=OK' -and @($_.ActionCommands) -contains '/fx_probe'
        }).Count -eq 1) 'Explicit-command receipt was not bound to its exact action command.'
        Assert-VtContractFixture (@($routes | Where-Object {
            $_.Signature -eq '[fx:pcall-probe] status=OK' -and $_.Bound -and @($_.ActionCommands) -contains '/fx_pcall_probe'
        }).Count -eq 1) 'Protected explicit-command receipt was not bounded and bound to its exact action command.'
        Assert-VtContractFixture (@($routes.Signature) -notcontains '[dead:receipt] status=impossible') 'Literal-false receipt route was accepted.'
        Assert-VtContractFixture (@($routes.Signature) -notcontains '[dead:pcall-receipt] status=impossible') 'Literal-false protected-command receipt route was accepted.'
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

        # #577: a marker family with two terminal signatures is admitted only
        # route-by-route. The rejection signature has two distinct emitters,
        # and both early returns are part of its finite-output proof.
        $familyTree = 'c' * 40
        $familyPath = 'fixture_mod/scripts/mods/fixture_mod/_family577.lua'
        $familySource = @'
mod:hook("BackendInterfacePeddlerPlayFab", "exchange_chips", function(func, self, item_id, chip_type, price, callback_fn, ...)
    if _is_mp_realm() and chip_type == Dailies.REWARD_KIND then
        local plan, reason = validate(item_id)
        if not plan then
            pcall(printf, "[fx:577] purchase_rejected item=%s reason=%s backend=none",
                tostring(item_id), tostring(reason))
            if callback_fn then callback_fn(false) end
            return
        end
        local granted, balance_or_reason = purchase(plan)
        if not granted then
            pcall(printf, "[fx:577] purchase_rejected item=%s reason=%s backend=none",
                tostring(item_id), tostring(balance_or_reason))
            if callback_fn then callback_fn(false) end
            return
        end
        local overlaid, overlay_reason = sync_overlay(self)
        pcall(printf, "[fx:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none",
            tostring(item_id), plan.price, balance_or_reason, tostring(overlaid or overlay_reason))
        if callback_fn then callback_fn(true, { granted }) end
        return
    end
    return func(self, item_id, chip_type, price, callback_fn, ...)
end)

function mod.update()
    printf("[fx:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none forged")
end
'@
        $familyOverrides = @(
            @{
                Marker='[fx:577]';ModId='fixture';ModTrees=@{fixture=$familyTree}
                SourcesByMod=@{fixture=$familyPath}
                Signature='[fx:577] purchase_rejected item=%s reason=%s backend=none'
                Bound='two failure branches terminate before any later terminal route'
                EmitterAnchors=@(
                    'if not plan then pcall(printf, "[fx:577] purchase_rejected item=%s reason=%s backend=none"'
                    'if not granted then pcall(printf, "[fx:577] purchase_rejected item=%s reason=%s backend=none"'
                )
                GuardAnchors=@(
                    'mod:hook("BackendInterfacePeddlerPlayFab", "exchange_chips"'
                    'if _is_mp_realm() and chip_type == Dailies.REWARD_KIND then'
                    'tostring(reason)) if callback_fn then callback_fn(false) end return end'
                    'tostring(balance_or_reason)) if callback_fn then callback_fn(false) end return end'
                )
            }
            @{
                Marker='[fx:577]';ModId='fixture';ModTrees=@{fixture=$familyTree}
                SourcesByMod=@{fixture=$familyPath}
                Signature='[fx:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none'
                Bound='one commit after successful validation and purchase'
                EmitterAnchors=@(
                    'pcall(printf, "[fx:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none"'
                )
                GuardAnchors=@(
                    'mod:hook("BackendInterfacePeddlerPlayFab", "exchange_chips"'
                    'if _is_mp_realm() and chip_type == Dailies.REWARD_KIND then'
                    'local granted, balance_or_reason = purchase(plan)'
                    'local overlaid, overlay_reason = sync_overlay(self)'
                    'if callback_fn then callback_fn(true, { granted }) end return end return func(self, item_id, chip_type, price, callback_fn, ...)'
                )
            }
        )
        $invokeFamily577 = {
            param([string]$Source, [string]$RecordTree, $Overrides, [string]$SourcePath = $familyPath)
            $document = [pscustomobject]@{
                RelativePath=$SourcePath
                Content=$Source
                Tokens=@(Get-VtLuaTokens -Content $Source)
            }
            $scan = Get-VtDirectLuaCallRoutes -Document $document
            $record = [pscustomobject]@{
                ModId='fixture'
                ModTree=$RecordTree
                ReceiptRoutes=@($scan.ReceiptRoutes)
            }
            Set-VtReceiptFamilyOverrides -Records @($record) -DocumentsByMod @{fixture=@($document)} `
                -Exceptions @{ReceiptFamilyOverrides=@($Overrides)}
            return $record
        }
        $familyRecord = & $invokeFamily577 $familySource $familyTree $familyOverrides
        $familyReject = @($familyRecord.ReceiptRoutes | Where-Object {
            [string]$_.Signature -ceq '[fx:577] purchase_rejected item=%s reason=%s backend=none'
        })
        $familyCommit = @($familyRecord.ReceiptRoutes | Where-Object {
            [string]$_.Signature -ceq '[fx:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none'
        })
        Assert-VtContractFixture ($familyReject.Count -eq 2 -and @($familyReject | Where-Object { -not $_.Bound }).Count -eq 0) 'Both rejection callsites were not independently bounded.'
        Assert-VtContractFixture ($familyCommit.Count -eq 1 -and $familyCommit[0].Bound) 'Committed terminal route was not independently bounded.'
        Assert-VtContractFixture (@($familyRecord.ReceiptRoutes | Where-Object {
            [string]$_.Signature -like '[[]fx:577[]]*forged' -and $_.Bound
        }).Count -eq 0) 'A forged marker-family suffix borrowed the committed-route bound.'

        $assertFamily577Rejected = {
            param([string]$MutatedSource, [string]$ExpectedError, [string]$Message)
            $rejected = $false
            try { & $invokeFamily577 $MutatedSource $familyTree $familyOverrides | Out-Null }
            catch { $rejected = [string]$_.Exception.Message -match $ExpectedError }
            Assert-VtContractFixture $rejected $Message
        }
        $noFirstReturn = $familySource.Replace(@'
                tostring(item_id), tostring(reason))
            if callback_fn then callback_fn(false) end
            return
'@, @'
                tostring(item_id), tostring(reason))
            if callback_fn then callback_fn(false) end
'@)
        & $assertFamily577Rejected $noFirstReturn 'anchor drift' 'Removing the first rejection return did not fail closed.'
        $noSecondReturn = $familySource.Replace(@'
                tostring(item_id), tostring(balance_or_reason))
            if callback_fn then callback_fn(false) end
            return
'@, @'
                tostring(item_id), tostring(balance_or_reason))
            if callback_fn then callback_fn(false) end
'@)
        & $assertFamily577Rejected $noSecondReturn 'anchor drift' 'Removing the second rejection return did not fail closed.'
        & $assertFamily577Rejected ($familySource.Replace('"exchange_chips"', '"exchange_tokens"')) 'anchor drift' 'Changing the owning hook did not fail closed.'
        & $assertFamily577Rejected ($familySource.Replace('if _is_mp_realm() and chip_type == Dailies.REWARD_KIND then', 'if _is_mp_realm() or chip_type == Dailies.REWARD_KIND then')) 'anchor drift' 'Changing the realm/currency gate did not fail closed.'
        & $assertFamily577Rejected ($familySource.Replace('[fx:577] purchase_rejected item=%s reason=%s backend=none', '[fx:577] purchase_rejected item=%s reason=%s backend=local')) 'anchor drift' 'Changing the rejection format string did not fail closed.'
        & $assertFamily577Rejected ($familySource.Replace('[fx:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none', '[fx:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=local')) 'anchor drift' 'Changing the committed format string did not fail closed.'
        $rejected = $false
        try { & $invokeFamily577 $familySource ('d' * 40) $familyOverrides | Out-Null }
        catch { $rejected = [string]$_.Exception.Message -match 'immutable-tree drift' }
        Assert-VtContractFixture $rejected 'Changing the deployed source tree did not fail closed.'
        $savedFamilySource = $familyOverrides[0].SourcesByMod.fixture
        try {
            $familyOverrides[0].SourcesByMod.fixture = 'fixture_mod/scripts/mods/fixture_mod/_missing.lua'
            $rejected = $false
            try { & $invokeFamily577 $familySource $familyTree $familyOverrides | Out-Null }
            catch { $rejected = [string]$_.Exception.Message -match 'source missing' }
            Assert-VtContractFixture $rejected 'Changing the audited source path did not fail closed.'
        }
        finally { $familyOverrides[0].SourcesByMod.fixture = $savedFamilySource }

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

        $manifest.mods[0].sha256 = 'not-a-sha256'
        $rejected = $false
        try { Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest | Out-Null }
        catch { $rejected = $_.Exception.Message -match 'ZIP sha256' }
        Assert-VtContractFixture $rejected 'Malformed ZIP authority was accepted.'
        $manifest.mods[0].sha256 = ('e' * 64)

        $savedBundleFiles = $manifest.mods[0].bundle_files
        $manifest.mods[0].bundle_files = @()
        $rejected = $false
        try { Get-VtDeployedSourceContract -RepoRoot $tmp -ReleaseManifest $manifest | Out-Null }
        catch { $rejected = $_.Exception.Message -match 'must resolve to exactly one bundle_files row' }
        Assert-VtContractFixture $rejected 'A root bundle missing from bundle_files was accepted.'
        $manifest.mods[0].bundle_files = $savedBundleFiles

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
        $legacy577 = @($exceptions.LegacyMarkerFamilyAudits | Where-Object { [string]$_.Marker -ceq '[mp:577]' })
        Assert-VtContractFixture ($legacy577.Count -eq 0) '#577 still relies on the non-consumed legacy marker audit.'
        $mp577Routes = @($exceptions.ReceiptFamilyOverrides | Where-Object { [string]$_.Marker -ceq '[mp:577]' })
        Assert-VtContractFixture ($mp577Routes.Count -eq 2) '#577 must expose exactly the rejection and committed family routes.'
        $mp577Reject = @($mp577Routes | Where-Object { [string]$_.Signature -ceq '[mp:577] purchase_rejected item=%s reason=%s backend=none' })
        $mp577Commit = @($mp577Routes | Where-Object { [string]$_.Signature -ceq '[mp:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none' })
        Assert-VtContractFixture ($mp577Reject.Count -eq 1 -and @($mp577Reject[0].EmitterAnchors).Count -eq 2 -and @($mp577Reject[0].GuardAnchors).Count -eq 4) '#577 rejection authority no longer binds both failure callsites and returns.'
        Assert-VtContractFixture ($mp577Commit.Count -eq 1 -and @($mp577Commit[0].EmitterAnchors).Count -eq 1 -and @($mp577Commit[0].GuardAnchors).Count -eq 5) '#577 committed authority no longer binds the successful transaction tail.'
        foreach($mp577Route in $mp577Routes){
            Assert-VtContractFixture ([string]$mp577Route.ModTrees.mp -ceq 'bf943e376bae259ce9e7945e491ca0f5350944d6') '#577 immutable MP tree pin drifted unexpectedly.'
            Assert-VtContractFixture ([string]$mp577Route.SourcesByMod.mp -ceq 'modded_progression/scripts/mods/modded_progression/modded_progression.lua') '#577 audited source path drifted unexpectedly.'
        }
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

        # Regression proof for #750: in a blob:none partial clone (the shape of
        # the dedicated lifecycle CI checkout) the authority must recover the
        # deployed identity through the batched blob prefetch. GIT_NO_LAZY_FETCH
        # forbids the per-object fallback on git >= 2.45, and the missing-object
        # census proves hydration happened on every git version. The census is
        # taken over the deployed subtree rather than the clone's HEAD, because
        # the planted mutation commit above is deliberately not the deployed
        # tree and its blobs are never prefetched.
        $manifest.mods = @($manifest.mods[0])
        & git -C $tmp config uploadpack.allowfilter true
        & git -C $tmp config uploadpack.allowanysha1inwant true
        $partial = Join-Path $tmp 'partial-clone'
        $sourcePath = ($tmp -replace '\\', '/')
        $sourceUrl = if ($sourcePath.StartsWith('/')) { "file://$sourcePath" } else { "file:///$sourcePath" }
        $cloneOutput = @(& git clone --quiet --no-checkout --filter=blob:none $sourceUrl $partial 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not create partial-clone contract fixture: $($cloneOutput -join ' ')" }
        & git -C $partial config core.longpaths true
        # Hydrate everything except the deployed mod tree, so its Lua blobs are
        # genuinely absent, exactly like historical deployed source in CI.
        & git -C $partial sparse-checkout set --no-cone '/*' '!/fixture_mod/'
        $checkoutOutput = @(& git -C $partial checkout --quiet 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Could not check out partial-clone contract fixture: $($checkoutOutput -join ' ')" }
        $deployedTree = (& git -C $partial rev-parse "$commit`:fixture_mod/scripts/mods").Trim()
        $missingBefore = @(& git -C $partial rev-list --objects --missing=print $deployedTree 2>&1 |
            Where-Object { [string]$_ -match '^\?[0-9a-f]{40,64}$' })
        Assert-VtContractFixture ($missingBefore.Count -ge 1) 'Partial-clone fixture left no deployed blob missing.'
        $previousNoLazyFetch = $env:GIT_NO_LAZY_FETCH
        try {
            $env:GIT_NO_LAZY_FETCH = '1'
            $partialContract = Get-VtDeployedSourceContract -RepoRoot $partial -ReleaseManifest $manifest
        }
        finally {
            if ($null -eq $previousNoLazyFetch) {
                Remove-Item Env:GIT_NO_LAZY_FETCH -ErrorAction SilentlyContinue
            }
            else { $env:GIT_NO_LAZY_FETCH = $previousNoLazyFetch }
        }
        $partialRecords = @($partialContract.Records)
        Assert-VtContractFixture ($partialRecords.Count -eq 1) 'Partial-clone authority did not resolve exactly one record.'
        Assert-VtContractFixture (@($partialRecords[0].LoadRoutes.Marker) -contains '[fx:LOAD]') 'Partial-clone authority lost the deployed LOAD route through the batched prefetch.'
        Assert-VtContractFixture (@($partialRecords[0].CommandRoutes.Command) -contains '/fx_probe') 'Partial-clone authority lost the deployed command route through the batched prefetch.'
        Assert-VtContractFixture (@($partialRecords[0].ReceiptRoutes.Signature) -contains '[fx:probe] status=OK') 'Partial-clone authority lost the deployed receipt route through the batched prefetch.'
        $missingAfter = @(& git -C $partial rev-list --objects --missing=print $deployedTree 2>&1 |
            Where-Object { [string]$_ -match '^\?[0-9a-f]{40,64}$' })
        Assert-VtContractFixture ($missingAfter.Count -eq 0) "Batched prefetch left $($missingAfter.Count) deployed blob(s) unhydrated."

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
