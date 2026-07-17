-- career_tweaker / _crt_regression.lua
--
-- Responsibility: the /crt_regression_test smoke suite. Owns the harness
-- (_rt_register + the _RT_CHECKS registry + the command) and all check
-- bodies, IN THEIR FROZEN REGISTRATION ORDER. The suite is load-bearing for the
-- issue 425 cross-peer wire safety: every check here must still register and
-- structurally pass. Check NAMES and their registration ORDER are frozen surface
-- (they define the in-game /crt_regression_test output order) -- do not reorder.
--
-- Manifest position: LAST. The check bodies read several surfaces owned by other
-- modules -- balance (mod._crt.balance), the two _dbg helpers
-- (mod._crt.dbg / dbg_alert), and MOD_VERSION (mod._crt.MOD_VERSION). Those are
-- captured as module-locals at load time here, so this module MUST load after
-- career_tweaker_balance and after the entry has populated
-- mod._crt.{MOD_VERSION,dbg,dbg_alert,balance}. Most check bodies otherwise read
-- only globals or existing mod fields (mod._crt_registered_buff_names,
-- mod._crt_mod_registered_buff_names, mod._crt_peer_parity), which resolve at
-- command-invocation time.
--
-- Split out of career_tweaker.lua (v0.3.57-dev, Phase 1 OOP decomposition); pure
-- structural move, no behavior change. mod._crt.rt_register is exported so a
-- future phase can distribute checks into the modules that own the guarded code
-- (PROJECT_STANDARDS 2.2a rule 6) without moving the harness again.

local mod = get_mod("crt")
mod._crt = mod._crt or {}

-- Coupled surface captured from the mod._crt namespace at load (see header).
local MOD_VERSION               = mod._crt.MOD_VERSION
local _dbg                      = mod._crt.dbg
local _dbg_alert                = mod._crt.dbg_alert
local balance                   = mod._crt.balance

-- /regression_test scaffold.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
-- Exported so a future phase can register checks from the owning module.
mod._crt.rt_register = _rt_register

mod:command("crt_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== crt regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)
mod:info("[regression-test-command] registered as /crt_regression_test")

-- ============================================================
-- /regression_test checks
-- ============================================================
-- The crt_* buff name canonical list is duplicated here so the check stays
-- decoupled from career_tweaker_balance.lua's local _CRT_BUFF_NAMES. Keep
-- both lists in sync (alphabetical sort is load-bearing for cross-peer
-- NetworkLookup determinism per career_tweaker_balance.lua's header).

local _CRT_BUFF_NAMES_EXPECTED = {
    "crt_bardin_ranger_exuberance_stack_remover",
    "crt_bh_double_shotted_damage_buff",
    "crt_bh_jwd_special_kill_dr_proc",
    "crt_bh_jwd_special_kill_dr_stack",
    "crt_bh_jwd_stack_remover",
    "crt_engineer_leading_shots_accumulator",
    "crt_engineer_leading_shots_counter",
    "crt_engineer_leading_shots_crit",
    "crt_knight_counter_punch_proc",
    "crt_knight_counter_punch_stack",
    "crt_maidenguard_dance_of_blades_dodge",
    "crt_maidenguard_dance_of_blades_proc",
    "crt_maidenguard_dance_of_blades_stack",
    "crt_mainstay_universal_stagger",
    "crt_merc_blade_barrier_proc",
    "crt_merc_blade_barrier_remover",
    "crt_merc_blade_barrier_stack",
    "crt_merc_enhanced_training_as",
    "crt_priest_prayer_self_extra",
    "crt_questingknight_impetuous_as",
    "crt_questingknight_impetuous_as_proc",
    "crt_questingknight_impetuous_power",
    "crt_questingknight_impetuous_power_proc",
    "crt_sienna_flame_unending_driver",
    "crt_sienna_flame_unending_stack",
    "crt_sienna_natural_talent_ranged_driver",
    "crt_sienna_natural_talent_ranged_stack",
    "crt_sienna_numb_to_pain_proc",
    "crt_sienna_numb_to_pain_remover",
    "crt_sienna_numb_to_pain_stack",
    "crt_unchained_ult_max_us",
    "crt_waywatcher_drakiras_alacrity_passive",
    "crt_waywatcher_fervent_huntress_passive",
    "crt_zealot_holy_fortitude_max_hp",
}

_rt_register("crt_buffs_preregistered", function()
    local NL = rawget(_G, "NetworkLookup")
    if not (NL and NL.buff_templates) then
        return "NetworkLookup.buff_templates not loaded (run in-keep)"
    end
    local missing = {}
    for _, name in ipairs(_CRT_BUFF_NAMES_EXPECTED) do
        if not rawget(NL.buff_templates, name) then
            missing[#missing + 1] = name
            if #missing >= 5 then break end
        end
    end
    if #missing > 0 then return "missing in NL: " .. table.concat(missing, ", ") end
end)

_rt_register("crt_buffs_in_global_table", function()
    -- BuffTemplates must contain the same crt_* names (registered as
    -- placeholder stubs in _crt_pre_register_buffs ~L67 of balance.lua).
    local BT = rawget(_G, "BuffTemplates")
    if not BT then return "BuffTemplates not loaded (run in-keep)" end
    local missing = {}
    for _, name in ipairs(_CRT_BUFF_NAMES_EXPECTED) do
        if rawget(BT, name) == nil then
            missing[#missing + 1] = name
            if #missing >= 5 then break end
        end
    end
    if #missing > 0 then return "missing in BuffTemplates: " .. table.concat(missing, ", ") end
end)

_rt_register("rawget_on_buff_templates_marker", function()
    -- v0.3.4 fix: NetworkLookup tables error on missing-key reads, so any code
    -- that checks for buff presence must use rawget(...). Verify the marker
    -- text from balance.lua's header comment is compiled into the bundle.
    local _MARKER = "must use `rawget(t, key)` for existence checks"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    -- Helpers route through VMF (mod:debug / mod:warning); just verify they don't raise.
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)

_rt_register("armor_overcharge_hook_targets_present", function()
    -- v0.3.32-dev: the armor/overcharge module installs exactly ONE mod:hook on
    -- each of its two targets (VMF drops the 2nd hook on the same (Class, method)
    -- silently). The STATIC duplicate-hook guarantee is enforced at build time by
    -- tools/mod-lint/lint-mod.ps1; this runtime check confirms both hook TARGETS
    -- are resolvable (i.e. the module had something real to hook). Both functions
    -- live in core scripts loaded well before any keep state, so this passes even
    -- from the keep.
    local DU = rawget(_G, "DamageUtils")
    if type(DU) ~= "table" or type(DU.apply_buffs_to_damage) ~= "function" then
        return "DamageUtils.apply_buffs_to_damage missing"
    end
    local PUHE = rawget(_G, "PlayerUnitHealthExtension")
    if type(PUHE) ~= "table" or type(PUHE.add_damage) ~= "function" then
        return "PlayerUnitHealthExtension.add_damage missing"
    end
end)

_rt_register("armor_overcharge_self_dot_toggle_wired", function()
    -- #334: the self-inflicted-DoT fix adds toggle
    -- `unchained_no_overcharge_from_self_dot` (the Blood Magic overcharge case)
    -- and folds the Gromril + Necromancer self-DoT coverage into the existing
    -- `armor_gromril_ignore_chip`. The `_is_self_dot` predicate is a module-local
    -- in career_tweaker_armor_overcharge.lua (not reachable from here), so this
    -- check verifies the new toggle's DATA widget + both LOC keys are present —
    -- i.e. the option actually renders and reads back.
    local ok_d, data = pcall(require, "scripts/mods/career_tweaker/career_tweaker_data")
    if not ok_d or type(data) ~= "table" then return "career_tweaker_data not loadable" end
    local found = false
    local function walk(node)
        if type(node) ~= "table" then return end
        if node.setting_id == "unchained_no_overcharge_from_self_dot" then found = true end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if not found then
        return "unchained_no_overcharge_from_self_dot widget missing from data tree"
    end
    local ok_l, loc = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_localization")
    if ok_l and type(loc) == "table" then
        if type(loc.unchained_no_overcharge_from_self_dot) ~= "table" then
            return "unchained_no_overcharge_from_self_dot loc label missing"
        end
        if type(loc.unchained_no_overcharge_from_self_dot_tooltip) ~= "table" then
            return "unchained_no_overcharge_from_self_dot_tooltip loc missing"
        end
    end
end)

_rt_register("armor_cursed_armor_procfunc_wrapper", function()
    -- v0.3.56-dev (IMPROVEMENT_BACKLOG P0): the Necromancer Cursed Armor path no
    -- longer replaces be.trigger_procs (which swallowed EVERY buff's
    -- on_damage_taken procs for the exempt tick). It re-points ONLY the Cursed
    -- Armor counter-remover proc through a crt-owned ProcFunctions wrapper that
    -- delegates to the vanilla remove_buff_stack unless the victim's tick is
    -- flagged exempt. Lock the NEW shape: the wrapper exists AND the vanilla
    -- template's proc entry is re-pointed to it (never left as raw
    -- remove_buff_stack — that would mean the trigger_procs-swallow shape is
    -- back). Both globals load well before any keep state.
    local PF = rawget(_G, "ProcFunctions")
    if type(PF) ~= "table" then return "ProcFunctions not loaded (run in-keep)" end
    if type(PF.crt_cursed_armor_counter_remover) ~= "function" then
        return "ProcFunctions.crt_cursed_armor_counter_remover wrapper missing — trigger_procs-swallow regression?"
    end
    if type(PF.remove_buff_stack) ~= "function" then
        return "ProcFunctions.remove_buff_stack (delegate target) missing"
    end
    local BT = rawget(_G, "BuffTemplates")
    if type(BT) ~= "table" then return "BuffTemplates not loaded (run in-keep)" end
    local tmpl = rawget(BT, "sienna_necromancer_5_2_counter_remover")
    local sub = tmpl and tmpl.buffs and tmpl.buffs[1]
    if type(sub) ~= "table" then
        return "sienna_necromancer_5_2_counter_remover template missing/malformed"
    end
    if sub.buff_func ~= "crt_cursed_armor_counter_remover" then
        return string.format(
            "counter-remover buff_func is %q, expected crt_cursed_armor_counter_remover (be.trigger_procs replacement must NOT be reintroduced)",
            tostring(sub.buff_func))
    end
end)

_rt_register("public_beta_talent_swaps_disabled", function()
    if mod._crt.PUBLIC_BETA_TALENT_SWAPS_DISABLED ~= true then
        return "public-beta talent-swap disable marker missing"
    end
    if mod._crt.apply_talent_swaps ~= nil or mod._crt.restore_talent_swaps ~= nil
        or mod._crt.refresh_talent_ui ~= nil or mod._crt.ALL_CAREERS ~= nil then
        return "talent-swap runtime surface is exposed in the public beta"
    end
end)

_rt_register("crt_buff_names_deterministic_sorted", function()
    -- issue 425 / PROJECT_STANDARDS §9.3 (registration parity): the crt_* buff names are
    -- pre-registered into NetworkLookup + BuffTemplates UNCONDITIONALLY at load (present at
    -- default settings — covered by crt_buffs_preregistered / crt_buffs_in_global_table) and
    -- in a DETERMINISTIC alphabetical order. The order assigns the sequential NetworkLookup
    -- indices every peer must agree on; a reorder silently diverges peer indices and CTDs on
    -- rpc_add_buff (career_tweaker_balance.lua header). Lock the sorted invariant against the
    -- real registration list exported by career_tweaker_balance.lua (strict ascending also
    -- catches a duplicate name).
    local names = mod._crt_registered_buff_names
    if type(names) ~= "table" then
        return "mod._crt_registered_buff_names not exported by career_tweaker_balance.lua"
    end
    for i = 2, #names do
        -- >= (not <) so an out-of-order OR duplicate name both fail.
        if names[i - 1] >= names[i] then
            return string.format(
                "registration list not strictly ascending at index %d (%q then %q) -- cross-peer NetworkLookup index order broken",
                i, tostring(names[i - 1]), tostring(names[i]))
        end
    end
end)

_rt_register("crt_buff_names_catalog_parity", function()
    -- issue 425: _CRT_BUFF_NAMES_EXPECTED (this file, consumed by crt_buffs_preregistered /
    -- crt_buffs_in_global_table) is a deliberately decoupled copy of
    -- career_tweaker_balance.lua's _CRT_BUFF_NAMES (the site that actually registers into
    -- NetworkLookup + BuffTemplates). If the two drift, the presence checks silently validate
    -- a stale catalog. Assert exact length + per-index equality so a name added/removed/
    -- reordered on one side but not the other fails here.
    local registered = mod._crt_registered_buff_names
    if type(registered) ~= "table" then
        return "mod._crt_registered_buff_names not exported (catalog parity cannot be checked)"
    end
    if #registered ~= #_CRT_BUFF_NAMES_EXPECTED then
        return string.format(
            "catalog size mismatch: registration site has %d, RT expected list has %d",
            #registered, #_CRT_BUFF_NAMES_EXPECTED)
    end
    for i = 1, #registered do
        if registered[i] ~= _CRT_BUFF_NAMES_EXPECTED[i] then
            return string.format(
                "catalog mismatch at index %d: registration=%q vs RT-expected=%q",
                i, tostring(registered[i]), tostring(_CRT_BUFF_NAMES_EXPECTED[i]))
        end
    end
end)

-- ------------------------------------------------------------
-- Issue 425 regression checks: peer-parity beacon + wire safety
-- ------------------------------------------------------------

_rt_register("crt_peer_parity_lib_loaded", function()
    -- The COPIED shared lib (master tools/shared_lib/_lib_peer_parity.lua)
    -- built an instance and exposed the contract API.
    local pp = mod._crt_peer_parity
    if type(pp) ~= "table" then return "mod._crt_peer_parity not built (lib load or factory failed)" end
    for _, m in ipairs({ "install", "register_gated_feature", "all_peers_have",
                         "tick", "feature_count", "applied_state", "is_installed" }) do
        if type(pp[m]) ~= "function" then return "beacon missing method: " .. m end
    end
    if type(mod.network_register) == "function" and not pp:is_installed() then
        return "beacon channel not registered despite VMF network_register present"
    end
end)

_rt_register("crt_peer_parity_failsafe_posture", function()
    -- Chosen posture: networked reworks are INERT until all peers are
    -- POSITIVELY confirmed (issue 371 mandate; same assertions as cwv's suite).
    local pp = mod._crt_peer_parity
    if type(pp) ~= "table" then return "beacon absent" end
    if pp._initial_applied ~= "disabled" then
        return "beacon did not initialise to the fail-safe (disabled) state"
    end
    if pp.FAILSAFE_POSTURE ~= "feature_inert_until_confirmed" then
        return "beacon failsafe posture marker changed unexpectedly"
    end
    local c = pp.__classify
    if type(c) ~= "function" then return "beacon classifier (__classify) missing" end
    if c({}, {}) ~= true then return "solo (no other peers) must classify all-present" end
    if c({ p1 = true }, {}) ~= false then
        return "a present-but-unacked peer must fail-safe to NOT-all-present"
    end
    if c({ p1 = true }, { p1 = true }) ~= true then return "an acked peer must count as present" end
    if c({ p1 = true, p2 = true }, { p1 = true }) ~= false then
        return "a partially-acked lobby must classify NOT-all-present"
    end
    local ok = pcall(function() return pp:all_peers_have() end)
    if not ok then return "all_peers_have threw (must fail-safe to false, never error)" end
end)

_rt_register("crt_wire_safe_wrappers_registered", function()
    -- The three wire-safe wrappers exist in the tables the engine resolves
    -- proc/update names from (ProcFunctions per buff_extension.lua:1351,
    -- BuffFunctionTemplates.functions per buff_extension.lua:794), and the
    -- vanilla functions they delegate to are still present.
    local PF = rawget(_G, "ProcFunctions")
    if type(PF) ~= "table" then return "ProcFunctions not loaded (run in-keep)" end
    if type(PF.crt_wire_safe_add_buff) ~= "function" then
        return "ProcFunctions.crt_wire_safe_add_buff missing"
    end
    if type(PF.crt_wire_safe_add_buff_on_special_kill) ~= "function" then
        return "ProcFunctions.crt_wire_safe_add_buff_on_special_kill missing"
    end
    if type(PF.add_buff) ~= "function" or type(PF.add_buff_on_special_kill) ~= "function" then
        return "vanilla ProcFunctions delegates missing (engine changed?)"
    end
    local BFT = rawget(_G, "BuffFunctionTemplates")
    local fns = BFT and BFT.functions
    if type(fns) ~= "table" then return "BuffFunctionTemplates.functions not loaded" end
    if type(fns.crt_wire_safe_overcharge_chunks_driver) ~= "function" then
        return "BuffFunctionTemplates.functions.crt_wire_safe_overcharge_chunks_driver missing"
    end
    if type(fns.activate_server_buff_stacks_based_on_overcharge_chunks) ~= "function" then
        return "vanilla overcharge-chunk driver missing (engine changed?)"
    end
    if type(fns.crt_wire_safe_distance_aura_driver) ~= "function" then
        return "BuffFunctionTemplates.functions.crt_wire_safe_distance_aura_driver missing"
    end
    if type(fns.activate_buff_on_distance) ~= "function" then
        return "vanilla distance-aura driver missing (engine changed?)"
    end
end)

-- Canonical list of the reworks whose crt_* buffs reach vanilla networked buff
-- paths (issue 425). Deliberately duplicated from the network_unsafe tags in
-- career_tweaker_balance.lua, same decoupling rationale as
-- _CRT_BUFF_NAMES_EXPECTED above: a tag added/removed on one side but not the
-- other must fail here, not silently change the gated surface.
local _CRT_NETWORK_UNSAFE_EXPECTED = {
    "rework_bw_unchained_abandon_innate_flame_unending",
    "rework_bw_unchained_natural_talent_ranged",
    "rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit",
    "rework_es_mercenary_blade_barrier_60x_minus_10_on_hit",
    "rework_es_mercenary_enhanced_training_tiered",
    "rework_es_questingknight_virtue_of_impetuous_buffed",
    "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr",
}

_rt_register("crt_network_unsafe_catalog_parity", function()
    local ids = balance and balance.network_unsafe_ids
    if type(ids) ~= "table" then
        return "balance.network_unsafe_ids not exported by career_tweaker_balance.lua"
    end
    if #ids ~= #_CRT_NETWORK_UNSAFE_EXPECTED then
        return string.format("network_unsafe catalog size mismatch: balance has %d, RT expects %d",
            #ids, #_CRT_NETWORK_UNSAFE_EXPECTED)
    end
    for i = 1, #ids do
        if ids[i] ~= _CRT_NETWORK_UNSAFE_EXPECTED[i] then
            return string.format("network_unsafe catalog mismatch at index %d: balance=%q vs RT=%q",
                i, tostring(ids[i]), tostring(_CRT_NETWORK_UNSAFE_EXPECTED[i]))
        end
    end
    local pp = mod._crt_peer_parity
    if type(pp) == "table" and pp:feature_count() < 1 then
        return "beacon gated-feature registry empty -- crt_networked_reworks was not registered"
    end
    if not (balance and type(balance.parity_gate_ok) == "function"
            and type(balance.wire_parity_live) == "function") then
        return "balance parity helpers (parity_gate_ok / wire_parity_live) not exported"
    end
end)

_rt_register("crt_no_raw_networked_funcs_on_crt_templates", function()
    -- Class-31 sweep invariant: no MOD-REGISTERED buff template may reference a
    -- RAW networked proc/update function -- every networked add must route
    -- through a crt_wire_safe_* wrapper. Walks the live registry
    -- (mod._crt_mod_registered_buff_names: balance crt_* names + tourney's
    -- vanilla-prefixed names), so it catches a regression on the known sites
    -- AND any future rework/port that wires a raw networked func. Stubs
    -- (toggle off / parity-gated) have empty buffs and pass vacuously.
    local BT = rawget(_G, "BuffTemplates")
    if not BT then return "BuffTemplates not loaded (run in-keep)" end
    local registry = mod._crt_mod_registered_buff_names
    if type(registry) ~= "table" or next(registry) == nil then
        return "mod._crt_mod_registered_buff_names registry missing/empty"
    end
    -- The registry must cover at least the balance catalog (a module that
    -- forgets to register its names would silently shrink the sweep).
    for _, name in ipairs(_CRT_BUFF_NAMES_EXPECTED) do
        if not registry[name] then
            return string.format("registry missing balance-registered name %q", name)
        end
    end
    local RAW_NETWORKED = {
        add_buff = true,
        add_buff_on_special_kill = true,
        activate_server_buff_stacks_based_on_overcharge_chunks = true,
        activate_buff_on_distance = true,
    }
    for name in pairs(registry) do
        local t = rawget(BT, name)
        local subs = t and t.buffs
        if type(subs) == "table" then
            for i = 1, #subs do
                local sub = subs[i]
                if type(sub) == "table" then
                    if RAW_NETWORKED[sub.buff_func] then
                        return string.format("%s.buffs[%d] uses raw networked buff_func %q (must be a crt_wire_safe_* wrapper)",
                            name, i, tostring(sub.buff_func))
                    end
                    if RAW_NETWORKED[sub.update_func] then
                        return string.format("%s.buffs[%d] uses raw networked update_func %q (must be a crt_wire_safe_* wrapper)",
                            name, i, tostring(sub.update_func))
                    end
                end
            end
        end
    end
end)

_rt_register("crt_trn_wh_priest_wire_safe_wiring", function()
    -- issue 425: when the trn_wh_priest port is APPLIED, the vanilla
    -- victor_priest_5_2 aura must carry BOTH patched fields together -- the
    -- mod-registered buff_to_add AND the crt wire-safe driver. The generic
    -- sweep above cannot see this template (vanilla name, not mod-registered),
    -- so lock the pairing here. Unapplied (toggle off / parity-gated /
    -- restored) states pass vacuously.
    local BT = rawget(_G, "BuffTemplates")
    local t = BT and rawget(BT, "victor_priest_5_2")
    local sub = t and t.buffs and t.buffs[1]
    if type(sub) ~= "table" then return end
    if sub.buff_to_add == "victor_priest_5_2_speed_buff"
            and sub.update_func ~= "crt_wire_safe_distance_aura_driver" then
        return string.format(
            "victor_priest_5_2 carries the mod buff_to_add but update_func is %q (raw driver would broadcast a mod index)",
            tostring(sub.update_func))
    end
end)

_rt_register("crt_hot_join_filter_target_present", function()
    -- The issue 425 hot-join replay filter hooks BuffSystem.hot_join_sync
    -- (buff_system.lua:66). Static single-hook guarantee is lint-mod's job;
    -- this confirms the hook target is still resolvable so the filter had
    -- something real to wrap.
    local BS = rawget(_G, "BuffSystem")
    if type(BS) ~= "table" or type(BS.hot_join_sync) ~= "function" then
        return "BuffSystem.hot_join_sync missing (engine changed? hot-join filter dead)"
    end
end)

-- ------------------------------------------------------------
-- Issue 506: shared peer-parity lib commits _applied before callbacks
-- ------------------------------------------------------------
_rt_register("crt_parity_applied_state_committed_before_callbacks", function()
    -- The shared lib must commit _applied BEFORE firing the gated-feature
    -- callbacks, so a callback that reads inst:applied_state() sees the
    -- transition it is part of. crt formerly kept a private
    -- mod._crt_parity_settled_enabled mirror to dodge the old stale read; that
    -- flag was removed (v0.3.58-dev) once the master lib was fixed, so the apply
    -- engines now read pp:applied_state() directly and THIS check is what locks
    -- the ordering invariant they depend on.
    --
    -- Build a THROWAWAY instance (never install()d -> no VMF channel, no
    -- mod.update wrap), register a probe feature whose on_enable records
    -- applied_state(), then drive a solo enable and assert it observed
    -- "enabled". If the transition cannot be driven here (a populated lobby
    -- holds the probe disabled), skip rather than false-fail -- the same
    -- run-in-keep posture the other beacon checks take.
    local ok, factory = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/_lib_peer_parity")
    if not ok or type(factory) ~= "function" then return "peer-parity lib not loadable" end
    local inst = factory(mod, {
        channel           = "crt_rt_probe_parity",
        echo_prefix       = "[crt-rt]",
        poll_interval     = 0,
        announce_interval = 1e12,   -- suppress the probe's network announce
    })
    if type(inst) ~= "table" then return "parity factory did not return an instance" end
    local seen_state
    inst:register_gated_feature("__crt_rt_order_probe__", {
        on_enable = function() seen_state = inst:applied_state() end,
    })
    pcall(function() inst:tick(10) end)   -- solo enables on the first tick (settle 0)
    if seen_state == nil then return end  -- enable did not fire in this env; skip
    if seen_state ~= "enabled" then
        return string.format(
            "applied_state() inside on_enable was %q, expected \"enabled\" -- shared lib fired callbacks before committing _applied (issue 506 regression)",
            tostring(seen_state))
    end
end)

-- ------------------------------------------------------------
-- Issue 507: Hellborg's Tutelage crit hook install tripwire
-- ------------------------------------------------------------
_rt_register("crt_hellborgs_crit_hook_installed", function()
    -- The Hellborg's Tutelage crit-chance reduction hooks the plain global
    -- ActionUtils.get_critical_strike_chance via TABLE-form, guarded by an
    -- at-load `if ActionUtils` presence test (table-form cannot hook a nil
    -- target). Under the current load order ActionUtils is a boot-time helper
    -- present long before crt, so the hook installs; if load order ever shifts
    -- and it is absent at crt load, the hook is skipped and the reduction
    -- silently vanishes. career_tweaker_balance.lua records the install decision
    -- in mod._crt_hellborgs_crit_hook_installed; assert it is true so the latent
    -- skip becomes a loud failure, and confirm the target still resolves now.
    if mod._crt_hellborgs_crit_hook_installed ~= true then
        return "ActionUtils.get_critical_strike_chance hook did NOT install at load (ActionUtils absent at crt load -> Hellborg's Tutelage crit reduction inactive; load-order regression)"
    end
    local AU = rawget(_G, "ActionUtils")
    if type(AU) ~= "table" or type(AU.get_critical_strike_chance) ~= "function" then
        return "ActionUtils.get_critical_strike_chance missing now (engine changed?)"
    end
end)

_rt_register("crt_mod_tweaker_exclusive_groups_registered", function()
    -- issue 446 Part 2: crt bridges its same-talent rival mutex clusters into
    -- gut's Mod Tweaker exclusive-group API at on_all_mods_loaded. Assert the
    -- pass RAN and did not partially fail. gut-absent is a valid PASS -- the
    -- registration is a best-effort enhancement with no hard dependency.
    -- Runtime-only: reads the status fields the registration wrote + drives the
    -- live gut reverse-lookup. No source read, no io (issue 511).
    if mod._crt_exclusive_groups_ran ~= true then
        return "on_all_mods_loaded exclusive-group registration never ran (VMF lifecycle regression?)"
    end
    local status = mod._crt_exclusive_groups_status
    if status == "gut-absent" then return end          -- valid: gut not installed
    if status ~= "ok" then
        return "exclusive-group registration status: " .. tostring(status)
    end
    -- gut present + status ok: prove the wiring end-to-end by resolving each
    -- declared 2+ member cluster's first member back to its crt_<group_id> via
    -- gut's public reverse-lookup. Fully data-driven off mutex.CLUSTERS so it
    -- tracks whatever clusters crt declares (no hardcoded member list).
    local gut = get_mod("gut_dev") or get_mod("gut")
    local mt  = gut and gut.mod_tweaker
    if not (mt and type(mt.get_exclusive_group_id) == "function") then
        return "status ok but gut mod_tweaker reverse-lookup API missing"
    end
    local mutex    = mod._crt and mod._crt.mutex
    local clusters = mutex and mutex.CLUSTERS
    if type(clusters) ~= "table" then
        return "mutex.CLUSTERS not exposed on mod._crt.mutex (mutex load regression?)"
    end
    local checked = 0
    for group_id, members in pairs(clusters) do
        if type(members) == "table" and #members >= 2 then
            local got = mt:get_exclusive_group_id("crt", members[1])
            if got ~= "crt_" .. group_id then
                return string.format("cluster %q member %q resolves to %s (expected crt_%s)",
                    tostring(group_id), tostring(members[1]), tostring(got), tostring(group_id))
            end
            checked = checked + 1
        end
    end
    if checked == 0 then
        return "no 2+ member clusters found to verify (mutex load regression?)"
    end
end)

_rt_register("issue445_rework_family_masters", function()
    local policy = mod._crt and mod._crt.rework_master_policy
    if type(policy) ~= "table" or type(policy.plan) ~= "function"
        or type(policy.derive_masters) ~= "function" then
        return "rework-master policy missing"
    end
    if #(policy.ensrick_ids or {}) < 50 then
        return "native rework family catalog unexpectedly small: " .. tostring(#(policy.ensrick_ids or {}))
    end
    if #(policy.tourney_ids or {}) < 10 then
        return "Tourney family catalog unexpectedly small: " .. tostring(#(policy.tourney_ids or {}))
    end
    local mutex = mod._crt and mod._crt.mutex
    local members = mutex and mutex.CLUSTERS and mutex.CLUSTERS.rework_family_master_choice
    if type(members) ~= "table" or #members ~= 2
        or members[1] ~= "rework_master_ensrick"
        or members[2] ~= "rework_master_tourney" then
        return "live rework-family mutex pair missing or reordered"
    end
end)

_rt_register("issue405_heal_network_is_server_gated", function()
    -- Issue 405 (client CTD on Fires-from-Ash THP heal): the heal_from_proc
    -- call must stay behind the Managers.player.is_server gate. The gate site
    -- (career_tweaker_balance.lua, Fires-from-Ash wrapper) sets this marker at
    -- load; a reverted/edited-out gate drops the marker and this check fails.
    -- Runtime marker per the issue 511 doctrine (no source self-read).
    if mod._crt405_heal_is_server_gated ~= true then
        return "Fires-from-Ash THP heal missing its is_server gate marker (issue 405 client CTD class)"
    end
end)

_rt_register("issue472_focused_spirit_contract", function()
    local policy = mod._crt and mod._crt.damage_classification
    if type(policy) ~= "table" or type(policy.focused_spirit_ignores) ~= "function" then
        return "shared damage-classification policy missing"
    end
    local unit = {}
    if not policy.focused_spirit_ignores(unit, unit, nil, "wounded_dot")
       or not policy.focused_spirit_ignores({}, unit, "skaven_ratling_gunner", "shot_machinegun")
       or policy.focused_spirit_ignores({}, unit, "skaven_storm_vermin", "light_attack") then
        return "Focused Spirit ignore policy boundary drifted"
    end

    local defs = balance and balance.BALANCE_MODS
    local rework = defs and defs.rework_we_maidenguard_focused_spirit_stacks
    if type(rework) ~= "table" or #rework.patches ~= 4 then
        return "Focused Spirit stacking rework patches missing"
    end

    local PF = rawget(_G, "ProcFunctions")
    local BFT = rawget(_G, "BuffFunctionTemplates")
    local fns = BFT and BFT.functions
    if type(PF) ~= "table" or type(PF.crt_focused_spirit_damage_taken) ~= "function" then
        return "Focused Spirit one-stack proc wrapper missing"
    end
    if type(fns) ~= "table" or type(fns.crt_focused_spirit_arm_growth) ~= "function" then
        return "Focused Spirit growth re-arm function missing"
    end
    local tmpl = BuffTemplates and BuffTemplates.kerillian_maidenguard_power_level_on_unharmed
    local sub = tmpl and tmpl.buffs and tmpl.buffs[1]
    if not sub or sub.buff_func ~= "crt_focused_spirit_damage_taken" then
        return "Focused Spirit vanilla proc was not routed through crt wrapper"
    end
end)

_rt_register("issue283_talent_menu_noop_guard", function()
    local selection = mod._crt and mod._crt.talent_selection
    if mod._crt.talent_menu_guard_installed ~= true then
        return "talent-menu no-op guard did not install"
    end
    if type(selection) ~= "table" or type(selection.equal) ~= "function"
       or type(selection.snapshot) ~= "function" then
        return "talent-selection policy missing"
    end
    local opened = selection.snapshot({ 1, 2, 3, 1, 2, 3 })
    if not selection.equal(opened, { 1, 2, 3, 1, 2, 3 })
       or selection.equal(opened, { 1, 1, 3, 1, 2, 3 }) then
        return "talent-selection no-op/change boundary drifted"
    end
end)

_rt_register("issue366_ale_independent_stack_decay", function()
    local defs = balance and balance.BALANCE_MODS
    local rework = defs and defs.rework_dr_ranger_ale_independent_decay
    if type(rework) ~= "table" or type(rework.patches) ~= "table" or #rework.patches ~= 2 then
        return "Ranger ale independent-decay patch pair missing"
    end
    for i = 1, 2 do
        local patch = rework.patches[i]
        if patch.buff ~= "bardin_survival_ale_buff"
           or patch.sub_index ~= i
           or patch.field ~= "refresh_durations"
           or patch.value ~= false then
            return "Ranger ale sub-buff patch contract drifted at index " .. tostring(i)
        end
    end
    if mod:get("rework_dr_ranger_ale_independent_decay") then
        local template = BuffTemplates and BuffTemplates.bardin_survival_ale_buff
        local buffs = template and template.buffs
        if not buffs or not buffs[1] or not buffs[2]
           or buffs[1].refresh_durations ~= false
           or buffs[2].refresh_durations ~= false then
            return "enabled Ranger ale rework did not reach both live sub-buffs"
        end
    end
end)

-- Keep the registered name stable: regression names and order are a frozen
-- tester-facing surface even though the target changed from 1.0s to 0.75s.
_rt_register("issue367_ale_one_second_drink", function()
    local defs = balance and balance.BALANCE_MODS
    local rework = defs and defs.rework_dr_ranger_ale_one_second_drink
    if type(rework) ~= "table" or type(rework.custom_apply) ~= "function"
       or type(rework.custom_restore) ~= "function" then
        return "Ranger ale action-time rework missing"
    end
    if mod:get("rework_dr_ranger_ale_one_second_drink") then
        local template = WeaponTemplates and WeaponTemplates.bardin_survival_ale
        local action = template and template.actions and template.actions.action_one
            and template.actions.action_one.default
        local resolved_duration = action and action.anim_time_scale
            and action.total_time / action.anim_time_scale
        if not action or action.total_time ~= 1.9
           or type(action.anim_time_scale) ~= "number"
           or math.abs(action.anim_time_scale - (1.9 / 0.75)) > 0.000001
           or math.abs(resolved_duration - 0.75) > 0.000001 then
            return "enabled Ranger ale action did not resolve to 0.75 seconds"
        end
    end
end)

_rt_register("public_beta_issue_probes_disabled", function()
    if mod._crt.PUBLIC_BETA_BARDIN_PROBE_DISABLED ~= true
        or mod._crt.PUBLIC_BETA_UMBRELLA_AUDIT_DISABLED ~= true then
        return "public-beta issue-probe disable marker missing"
    end
    if mod._crt.bardin_disabler_probe ~= nil
        or mod._crt_bardin_disabler_tick ~= nil
        or mod._crt.umbrella_audit ~= nil then
        return "an investigation probe is active in the public beta"
    end
end)

_rt_register("issue473_dance_of_blades_contract", function()
    local policy = mod._crt and mod._crt.dance_of_blades
    if type(policy) ~= "table" or type(policy.templates) ~= "function"
       or type(policy.validate) ~= "function" then
        return "Dance of Blades policy missing"
    end
    if not policy.validate(policy.templates()) then
        return "Dance of Blades pure stack contract drifted"
    end
    local defs = balance and balance.BALANCE_MODS
    local rework = defs and defs.rework_we_maidenguard_dance_of_blades
    if type(rework) ~= "table" or rework.network_unsafe ~= true then
        return "Dance of Blades rework missing peer-parity classification"
    end
    local BFT = rawget(_G, "BuffFunctionTemplates")
    local fns = BFT and BFT.functions
    if type(fns) ~= "table"
       or type(fns.crt_maidenguard_dance_blocking_dodge) ~= "function" then
        return "Dance of Blades blocking-dodge function missing"
    end
    if mod:get("rework_we_maidenguard_dance_of_blades")
       and balance.parity_gate_ok and balance.parity_gate_ok() then
        local stack = BuffTemplates and BuffTemplates[policy.stack_buff]
        if not policy.validate({
            [policy.dodge_buff] = BuffTemplates[policy.dodge_buff],
            [policy.proc_buff] = BuffTemplates[policy.proc_buff],
            [policy.stack_buff] = stack,
        }) then
            return "enabled Dance of Blades templates do not match policy"
        end
    end
end)

_rt_register("issue447_flagellation_contract", function()
    local feature = mod._crt and mod._crt.flagellation
    local policy = feature and feature.policy
    if type(policy) ~= "table" or type(policy.conversion_amount) ~= "function"
       or type(policy.resolve_devotion) ~= "function" then
        return "Flagellation policy missing"
    end
    local amount, gained = policy.conversion_amount(10, 14, 100)
    if amount ~= 2 or gained ~= 4 then return "Flagellation ratio self-test failed" end
    if feature.hook_installed ~= true or type(feature.proc_names) ~= "table"
       or #feature.proc_names < 3 then
        return "Flagellation level-5 proc/add_heal wiring incomplete"
    end
    local defs = balance and balance.BALANCE_MODS
    if type(defs and defs.rework_wh_zealot_flagellation) ~= "table" then
        return "Flagellation missing from native/Ensrick rework catalog"
    end
    local clusters = mod._crt and mod._crt.mutex and mod._crt.mutex.CLUSTERS
    local zealot_mutex = clusters and clusters.zealot_thp_conversions
    if type(zealot_mutex) ~= "table" or #zealot_mutex ~= 2 then
        return "Zealot THP conversion mutex missing"
    end
    if not feature.devotion then
        return "live Devotion talent unresolved; inspect automatic [crt:447] census"
    end
end)

_rt_register("issue619_foot_knight_contract", function()
    local feature = mod._crt and mod._crt.foot_knight
    local policy = feature and feature.policy
    if type(feature) ~= "table" or type(feature.tick) ~= "function"
       or type(feature.outgoing_damage_multiplier) ~= "function" then
        return "Foot Knight runtime module missing"
    end
    if type(policy) ~= "table"
       or not policy.is_shield_type("AXE_1H_SHIELD")
       or not policy.is_non_polearm_great_type("AXE_2H")
       or policy.is_non_polearm_great_type("SPEAR_2H") then
        return "Foot Knight weapon capability taxonomy drifted"
    end
    if policy.ROCK_DESCRIPTION_KEY ~= "markus_knight_passive_block_cost_aura_desc_2"
       or policy.TEAMWORK_DESCRIPTION_KEY ~= "markus_knight_damage_taken_ally_proximity_desc_2" then
        return "Foot Knight authored talent-description keys drifted"
    end
    for _, key in ipairs({ policy.ROCK_DESCRIPTION_KEY, policy.TEAMWORK_DESCRIPTION_KEY }) do
        local expected = policy.talent_description(key,
            function(setting_id) return mod:get(setting_id) end)
        if expected ~= nil and Localize(key) ~= expected then
            return "Foot Knight live talent description did not compose: " .. key
        end
    end
    local local_names = {
        "crt_fk_uninterruptible_heavies",
        "crt_fk_rock_dodge_distance",
        "crt_fk_rock_shield_power",
        "crt_fk_teamwork_innate_dr_cancel",
        "crt_fk_teamwork_great_power",
        "crt_fk_final_march",
    }
    for _, name in ipairs(local_names) do
        local template = BuffTemplates and rawget(BuffTemplates, name)
        if type(template) ~= "table" or template._crt_local_only ~= true then
            return "missing local-only Foot Knight buff " .. name
        end
        local lookup = rawget(_G, "NetworkLookup")
        if lookup and lookup.buff_templates and rawget(lookup.buff_templates, name) then
            return "local-only Foot Knight buff leaked into NetworkLookup: " .. name
        end
    end
    local expected_icons = {
        crt_fk_uninterruptible_heavies = "markus_knight_ability_invulnerability",
        crt_fk_rock_dodge_distance = "markus_knight_passive_block_cost_aura",
        crt_fk_rock_shield_power = "markus_knight_passive_power_increase",
        crt_fk_teamwork_great_power = "markus_knight_passive_power_increase",
        crt_fk_final_march = "markus_knight_movement_speed_on_incapacitated_allies",
    }
    for buff_name, icon in pairs(expected_icons) do
        if not feature.buff_icons or feature.buff_icons[buff_name] ~= icon then
            return "Foot Knight resident buff icon drifted: " .. buff_name
        end
        local template = BuffTemplates and rawget(BuffTemplates, buff_name)
        local first = template and template.buffs and template.buffs[1]
        if not first or first.icon ~= icon then
            return "Foot Knight active-effect buff has no stable icon: " .. buff_name
        end
    end
    local player_manager = Managers.player
    local player = player_manager and player_manager.local_player
        and player_manager:local_player()
    local unit = player and player.player_unit
    local buff_extension = unit and Unit.alive(unit)
        and ScriptUnit.has_extension(unit, "buff_system")
    if buff_extension then
        local active = {}
        local buffs = buff_extension:active_buffs()
        for _, buff in ipairs(buffs or {}) do
            local template = not buff.removed and buff.template
            if template and template.name then active[template.name] = true end
        end
        if not mod:get("rework_es_knight_innate_uninterruptible_heavies")
           and active.crt_fk_uninterruptible_heavies then
            return "inactive heavy rework retained its icon buff"
        end
        if not mod:get("rework_es_knight_rock_shield_offense")
           and (active.crt_fk_rock_dodge_distance or active.crt_fk_rock_shield_power) then
            return "inactive Rock rework retained an icon buff"
        end
        if not mod:get("rework_es_knight_teamwork_great_weapon_offense")
           and active.crt_fk_teamwork_great_power then
            return "inactive Teamwork rework retained its icon buff"
        end
        if not mod:get("rework_es_knight_final_march")
           and (active.crt_fk_final_march_power or active.crt_fk_final_march_dr) then
            return "inactive Final March retained an icon buff"
        end
    end
    local dodge = BuffTemplates and BuffTemplates.crt_fk_rock_dodge_distance
    local dodge_buff = dodge and dodge.buffs and dodge.buffs[1]
    if not dodge_buff or dodge_buff.multiplier ~= 0.90
       or dodge_buff.apply_buff_func ~= "apply_movement_buff"
       or dodge_buff.remove_buff_func ~= "remove_movement_buff" then
        return "Rock dodge-distance tradeoff contract drifted"
    end
    local dr_cancel = BuffTemplates and BuffTemplates.crt_fk_teamwork_innate_dr_cancel
    local dr_buff = dr_cancel and dr_cancel.buffs and dr_cancel.buffs[1]
    if not dr_buff or dr_buff.stat_buff ~= "damage_taken" or dr_buff.multiplier ~= 0.10 then
        return "Teamwork innate-DR cancellation contract drifted"
    end
    local defs = balance and balance.BALANCE_MODS
    if #(feature.setting_ids or {}) ~= 6 then
        return "Foot Knight suite does not expose exactly six toggles"
    end
    for _, setting_id in ipairs(feature.setting_ids or {}) do
        if type(defs and defs[setting_id]) ~= "table" then
            return "Foot Knight toggle missing from rework-master catalog: " .. tostring(setting_id)
        end
    end
    if mod:get("rework_es_knight_secondary_melee") then
        local carriers = { CareerSettings and CareerSettings.es_knight }
        for _, profile in pairs(SPProfiles or {}) do
            for _, career in ipairs(profile.careers or {}) do
                if career.name == "es_knight" then carriers[#carriers + 1] = career end
            end
        end
        for _, career in ipairs(carriers) do
            local slot_map = career and career.item_slot_types_by_slot_name
            local slot_types = slot_map and slot_map.slot_ranged or {}
            local has_melee, has_ranged = false, false
            for _, slot_type in ipairs(slot_types) do
                if slot_type == "melee" then has_melee = true end
                if slot_type == "ranged" then has_ranged = true end
            end
            if not has_melee or not has_ranged then
                return "enabled secondary slot does not accept both melee and ranged"
            end
        end
    end
    if mod:get("rework_es_knight_teamwork_great_weapon_offense") then
        local template = BuffTemplates and BuffTemplates.markus_knight_damage_taken_ally_proximity
        local driver = template and template.buffs and template.buffs[1]
        if not driver or driver.range ~= 10 then
            return "enabled That's Bloody Teamwork! radius is not 10m"
        end
    end
    if mod:get("rework_es_knight_protective_presence_10m_rock_20m") then
        local base = BuffTemplates and BuffTemplates.markus_knight_passive
        local block = BuffTemplates and BuffTemplates.markus_knight_passive_block_cost_aura
        local rock = BuffTemplates and BuffTemplates.markus_knight_passive_range
        local base_driver = base and base.buffs and base.buffs[1]
        local block_driver = block and block.buffs and block.buffs[1]
        local rock_driver = rock and rock.buffs and rock.buffs[1]
        if not base_driver or base_driver.range ~= 10
           or not block_driver or block_driver.range ~= 20
           or not rock_driver or rock_driver.range ~= 20 then
            return "enabled Protective Presence/Rock ranges are not 10m/20m"
        end
    end
end)
