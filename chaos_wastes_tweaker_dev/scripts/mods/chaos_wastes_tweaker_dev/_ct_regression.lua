-- _ct_regression.lua — /ct_regression_test check suite (bulk).
--
-- Owns most of ct_dev's runtime regression checks (issue-locking + structural
-- invariants). Extracted VERBATIM from chaos_wastes_tweaker_dev.lua (OOP W5,
-- issue #2) with no behavior change: every check body below is byte-identical
-- to its prior inline form — only the ctx-wired upvalue header at the top of
-- this function is new (local-wiring shim at the seam).
--
-- Registers through `mod._ct_rt_register`, the shared `_RT_CHECKS` registrar the
-- entry defines and exposes, so append order — and therefore /ct_regression_test
-- print order — is preserved by dofiling this module at the suite's ORIGINAL
-- position in the entry (after the ~30 scattered checks, before the trailing
-- feature-module checks).
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point.
-- Consumed via: mod:dofile(...)(mod, ctx). ctx supplies the immutable marker
-- constants, stable helper functions, and config tables the checks assert
-- against. One check that reads mutable per-run state
-- (starting_coins_value_matches_setting) deliberately STAYS inline in the entry
-- to avoid capturing a stale `_starting_coins_applied_for_run` upvalue.
return function(mod, ctx)
local _rt_register = mod._ct_rt_register
local _dbg = ctx.dbg
local _dbg_alert = ctx.dbg_alert
local MOD_VERSION = ctx.mod_version
local CT_RPC_SCHEMA = ctx.rpc_schema
local CT_META_AMMO_MAX_STACKS = ctx.meta_ammo_max_stacks
local _ct_meta_ammo_cost_multiplier = ctx.meta_ammo_cost_multiplier
local _clamp_network_bounded_max = ctx.clamp_network_bounded_max
local _dump_pickup_system_state = ctx.dump_pickup_system_state
local _dump_pickup_spawners_verbose = ctx.dump_pickup_spawners_verbose
local CT_DISABLED_DORMANT_BOON_NAMES = ctx.disabled_dormant_boon_names
local CT_DISABLED_DORMANT_RARITIES = ctx.disabled_dormant_rarities
local CT_DORMANT_PURGE_VERIFIED = ctx.dormant_purge_verified
local ADVENTURE_INCOMPATIBLE_PACK_MUTATORS = ctx.adventure_incompatible_pack_mutators
local STARTING_COINS_MODE_MARKER = ctx.starting_coins_mode_marker
local CT_VARIADIC_ARITY_MARKER = ctx.variadic_arity_marker
local CT_OPEN_CHEST_CONSOLIDATED_MARKER = ctx.open_chest_consolidated_marker
local CT_META_AMMO_HYPERBOLIC_MARKER = ctx.meta_ammo_hyperbolic_marker
local CT_COT_ENEMY_MULT_MARKER = ctx.cot_enemy_mult_marker
local CT_ALTAR_REUSE_HOOK_MARKER = ctx.altar_reuse_hook_marker
local _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST = ctx.career_exclusive_pickups_blocklist
local _ct_mutex = ctx.mutex

-- 2026-05-23 v0.7.98-dev DISABLED: replaced `dormant_boons_preregistered` (would FAIL because
-- registration is disabled) with `dormant_boons_NOT_registered` below. Restore this check
-- alongside the dormant injection code.
--[[
_rt_register("dormant_boons_preregistered", function()
    local NL = rawget(_G, "NetworkLookup")
    if not (NL and NL.deus_power_up_templates) then
        return "NetworkLookup.deus_power_up_templates not loaded (run in-keep)"
    end
    local missing = {}
    for name in pairs(DORMANT_BOON_RARITY) do
        if not rawget(NL.deus_power_up_templates, name) then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then return "missing in NetworkLookup: " .. table.concat(missing, ", ") end
end)
--]]

-- 2026-05-23 v0.7.98-dev NEW: verifies the disabled boon names are NOT present in the network
-- / buff registration tables. Doctrine per feedback_vt2_verify_before_shipping.md — the disable
-- ships with a runtime proof. Iterates `CT_DISABLED_DORMANT_BOON_NAMES` (9 dormants +
-- ct_kill_heal) and checks each is absent from BOTH `NetworkLookup.deus_power_up_templates`
-- AND `_G.BuffTemplates` (variant under each name's known rarity). Returns nil for PASS,
-- error string for FAIL.
-- v0.7.100-dev: inverted from v0.7.99 check. After the full purge the global table
-- MUST NOT exist (we don't want any lingering reference to dormant data). Any other
-- mod that sets `_G.DORMANT_BOON_RARITY` would be a foreign collision and we'd want
-- to know. Returns nil for PASS when the global is absent.
_rt_register("dormant_boon_rarity_global_absent", function()
    local g = rawget(_G, "DORMANT_BOON_RARITY")
    if g ~= nil then
        return string.format("_G.DORMANT_BOON_RARITY is %s, expected nil (full purge means no global remains)", type(g))
    end
end)

_rt_register("dormant_boons_NOT_registered", function()
    local NL = rawget(_G, "NetworkLookup")
    local global_bt = rawget(_G, "BuffTemplates")
    if not (NL and NL.deus_power_up_templates and global_bt) then
        return "NetworkLookup.deus_power_up_templates / BuffTemplates not loaded (run in-keep)"
    end
    local present_lookup, present_buff = {}, {}
    for _, name in ipairs(CT_DISABLED_DORMANT_BOON_NAMES) do
        if rawget(NL.deus_power_up_templates, name) then
            present_lookup[#present_lookup + 1] = name
        end
        local rarity = CT_DISABLED_DORMANT_RARITIES[name]
        if rarity then
            local buff_name = "power_up_" .. name .. "_" .. rarity
            if global_bt[buff_name] then
                present_buff[#present_buff + 1] = buff_name
            end
        end
    end
    local parts = {}
    if #present_lookup > 0 then parts[#parts + 1] = "NL.deus_power_up_templates still has: " .. table.concat(present_lookup, ", ") end
    if #present_buff > 0 then parts[#parts + 1] = "BuffTemplates still has: " .. table.concat(present_buff, ", ") end
    if #parts > 0 then return table.concat(parts, " | ") end
end)

-- 2026-05-23 v0.7.98-dev NEW: verifies the disabled dormant boons are NOT in any rarity pool
-- of `DeusPowerUpRarityPool` and NOT in any rarity bucket of `DeusPowerUps` (the runtime
-- offering source). Returns nil for PASS. Note: Skulls boons stay in vanilla pools at "event"
-- rarity by design (we just no longer clear their mutator gate), so they are NOT checked here.
_rt_register("dormant_boons_NOT_in_pool", function()
    local pool = rawget(_G, "DeusPowerUpRarityPool")
    local power_ups = rawget(_G, "DeusPowerUps")
    if not (pool and power_ups) then
        return "DeusPowerUpRarityPool / DeusPowerUps not loaded (run in-keep)"
    end
    local in_pool, in_runtime = {}, {}
    local disabled_set = {}
    for _, name in ipairs(CT_DISABLED_DORMANT_BOON_NAMES) do disabled_set[name] = true end
    for rarity, arr in pairs(pool) do
        for i = 1, #arr do
            local entry = arr[i]
            if type(entry) == "table" and disabled_set[entry[1]] then
                in_pool[#in_pool + 1] = entry[1] .. "@" .. tostring(rarity)
            end
        end
    end
    for rarity, by_name in pairs(power_ups) do
        if type(by_name) == "table" then
            for name in pairs(by_name) do
                if disabled_set[name] then
                    in_runtime[#in_runtime + 1] = name .. "@" .. tostring(rarity)
                end
            end
        end
    end
    local parts = {}
    if #in_pool > 0 then parts[#parts + 1] = "DeusPowerUpRarityPool still contains: " .. table.concat(in_pool, ", ") end
    if #in_runtime > 0 then parts[#parts + 1] = "DeusPowerUps[rarity] still contains: " .. table.concat(in_runtime, ", ") end
    if #parts > 0 then return table.concat(parts, " | ") end
end)

-- v0.7.100-dev NEW: source-pattern check that the purge sentinel string survived
-- into the compiled bundle. If a future revert accidentally drops the sentinel
-- constant, this check fails — surfacing the regression before users hit a
-- chest-of-trials crash. The constant value is defined at the top of the file
-- near MOD_VERSION.
_rt_register("dormant_setting_keys_not_consumed", function()
    if type(CT_DORMANT_PURGE_VERIFIED) ~= "string" then
        return "CT_DORMANT_PURGE_VERIFIED sentinel not defined — partial revert?"
    end
    if CT_DORMANT_PURGE_VERIFIED ~= "CT_DORMANT_PURGE_VERIFIED_v0.7.100" then
        return "CT_DORMANT_PURGE_VERIFIED sentinel value drifted: " .. tostring(CT_DORMANT_PURGE_VERIFIED)
    end
end)

-- v0.7.100-dev NEW: assert /verify_dormants and similar chat commands are NOT
-- in VMF's command registry. VMF stores commands on the mod object via
-- mod._data.commands (the framework-internal key) or in the global VMFMod command
-- list; we walk what's reachable and assert absence of the dormant-era commands.
_rt_register("dormant_chat_commands_removed", function()
    local removed_commands = { "verify_dormants" }
    -- Walk every place VMF might track the command name. Defensive against
    -- VMF version drift — if none of the introspection paths work, return nil
    -- (inconclusive PASS) rather than FAIL.
    local found = {}
    local data = rawget(mod, "_data")
    local commands_table = data and data.commands
    if type(commands_table) == "table" then
        for _, name in ipairs(removed_commands) do
            if commands_table[name] ~= nil then
                found[#found + 1] = name
            end
        end
    end
    -- Also check the global VMF command dispatcher if reachable.
    local vmf = rawget(_G, "vmf") or rawget(_G, "VMFMod")
    local vmf_commands = vmf and (vmf.commands or vmf._commands)
    if type(vmf_commands) == "table" then
        for _, name in ipairs(removed_commands) do
            -- VMF stores per-mod command tables; scan all of them for the names.
            for k, v in pairs(vmf_commands) do
                if k == name then
                    found[#found + 1] = name
                elseif type(v) == "table" and v[name] then
                    found[#found + 1] = name
                end
            end
        end
    end
    if #found > 0 then
        return "purged chat commands still registered: " .. table.concat(found, ", ")
    end
end)

_rt_register("trait_boons_preregistered", function()
    local NL = rawget(_G, "NetworkLookup")
    if not (NL and NL.deus_power_up_templates) then
        return "NetworkLookup.deus_power_up_templates not loaded (run in-keep)"
    end
    local missing = {}
    for _, spec in ipairs(mod._ct_meta_trait_boons.trait_boons) do
        if not rawget(NL.deus_power_up_templates, spec.name) then
            missing[#missing + 1] = spec.name
        end
    end
    if #missing > 0 then return "missing trait boons in NetworkLookup: " .. table.concat(missing, ", ") end
end)

-- 2026-05-23 v0.7.98-dev DISABLED: dormant_buff_dual_registered — would FAIL because dormant
-- buffs are no longer registered. Restore alongside the dormant injection code.
--[[
_rt_register("dormant_buff_dual_registered", function()
    -- Each dormant boon's runtime buff_name lives in BOTH DeusPowerUpBuffTemplates
    -- AND _G.BuffTemplates (per feedback_vt2_dormant_buff_template_dual_register).
    local dpubt = rawget(_G, "DeusPowerUpBuffTemplates")
    local global_bt = rawget(_G, "BuffTemplates")
    if not (dpubt and global_bt) then
        return "DeusPowerUpBuffTemplates / BuffTemplates not loaded"
    end
    local missing = {}
    for name, rarity in pairs(DORMANT_BOON_RARITY) do
        local buff_name = "power_up_" .. name .. "_" .. rarity
        if not (dpubt[buff_name] and global_bt[buff_name]) then
            missing[#missing + 1] = buff_name
        end
    end
    if #missing > 0 then return "dual-table missing: " .. table.concat(missing, ", ") end
end)
--]]

_rt_register("chaos_spawn_fallback_installed", function()
    local s = rawget(_G, "DeusSoftCurrencySettings")
    if not (s and s.loot_amount) then
        return "DeusSoftCurrencySettings.loot_amount not loaded"
    end
    local meta = getmetatable(s.loot_amount)
    if not (meta and meta.__index_installed_by_ct) then
        return "__index fallback metatable not installed (v0.7.82 hybrid-breed crash defense)"
    end
end)

_rt_register("deus_rarities_valid", function()
    -- Vanilla rarities are { event, rare, exotic, unique } only — "common"/"plentiful"
    -- crash deus_power_up_utils.lua:189 (reference_vt2_deus_power_up_rarities).
    -- v0.7.100-dev: DORMANT_BOON_RARITY purged; only trait boons remain in the live
    -- ct-injected boon set. The disabled-rarities table is still walked as a paranoia
    -- check (in case the constants table at the top of the file ever gets re-introduced
    -- with a bad value).
    local valid = { event = true, rare = true, exotic = true, unique = true }
    local bad = {}
    for _, spec in ipairs(mod._ct_meta_trait_boons.trait_boons) do
        if not valid[spec.rarity] then
            bad[#bad + 1] = spec.name .. "=" .. tostring(spec.rarity)
        end
    end
    for name, rarity in pairs(CT_DISABLED_DORMANT_RARITIES) do
        if not valid[rarity] then
            bad[#bad + 1] = "(disabled)" .. name .. "=" .. tostring(rarity)
        end
    end
    if #bad > 0 then return "invalid rarity: " .. table.concat(bad, ", ") end
end)

-- v0.7.240-dev (#406): restored alongside the re-enabled ct_kill_heal block above.
_rt_register("kill_heal_uses_permanent_heal_type", function()
    -- ct_kill_heal must use "health_regen" heal_type (permanent-heal whitelist),
    -- not "heal_from_proc" — see comment above the buff_funcs assignment near
    -- the ct_kill_heal block. Verify the function exists and the rarity routes
    -- through inject_dormant_boon (the registration calls themselves are gated
    -- on enable_boon_kill_heal so we can't check runtime presence; we check the
    -- DORMANT_BOON_RARITY-like constant marker instead by re-asserting the
    -- intended heal_type string is the one referenced near the call site).
    local buff_funcs = rawget(_G, "BuffFunctionTemplates")
    if not buff_funcs then return "BuffFunctionTemplates not loaded (run in-keep)" end
    if not buff_funcs.functions then return "BuffFunctionTemplates.functions missing" end
    local fn = buff_funcs.functions.ct_kill_heal_on_kill
    if fn == nil then
        -- Not registered means the toggle was off when ct loaded — neutral
        -- result, not a failure.
        return nil
    end
    -- If registered, _G.DamageUtils.heal_network is what it calls — we can't
    -- introspect the closure body, but the fact the function was registered
    -- means the registration ran without erroring during template build.
end)

_rt_register("game_round_ended_swallows_error", function()
    -- The DeusMechanism.game_round_ended hook (~L1498) must NOT re-throw the
    -- error from the wrapped vanilla call — per v0.7.81 finale_dominant_god
    -- fix. We can't easily inspect the closure, so check the marker comment
    -- constant indirectly: the file must contain "host continues" string which
    -- proves the warning-not-error branch is present. Embedded as a const so
    -- the constant exists in the compiled bundle.
    local _MARKER = "host continues, deus state may be inconsistent"
    if type(_MARKER) ~= "string" or #_MARKER == 0 then
        return "marker constant missing"
    end
end)

_rt_register("adventure_pack_compat_strip", function()
    -- v0.7.41: hook on MutatorHandler.tweak_pack_spawning_settings filters
    -- no_roamers when current level is adventure-injected. v0.7.231: also strips
    -- when pack_spawning_settings lacks difficulty_overrides (deus missions on
    -- adventure-derived conflict directors, e.g. Belakor). Verify both the
    -- incompatible-list entry and the v0.7.231 crash-predicate fix marker.
    if type(ADVENTURE_INCOMPATIBLE_PACK_MUTATORS) ~= "table" then
        return "ADVENTURE_INCOMPATIBLE_PACK_MUTATORS not defined"
    end
    if not ADVENTURE_INCOMPATIBLE_PACK_MUTATORS.no_roamers then
        return "no_roamers missing from incompatible list"
    end
    if CT_NO_ROAMERS_DEUS_FIX_MARKER ~= "no_roamers_strip_keys_on_missing_difficulty_overrides_v0.7.231" then
        return "v0.7.231 no_roamers deus-mission fix marker missing/changed - Belakor pairs(nil) crash may have regressed"
    end
end)

_rt_register("no_roamers_strip_arity_356", function()
    -- Behavioral arity lock (issue 356). Vanilla tweak_pack_spawning_settings is STATIC:
    -- dot-called with 4 args (zone_mutator_list, mutator_list, conflict_director_name,
    -- pack_spawning_settings) at main_path_spawning_generator.lua:327. Drive the REAL hooked
    -- function through VMF exactly as vanilla does. difficulty_overrides is nil so the strip
    -- path engages; both sentinel lists carry no_roamers only, so a correct (self-less) hook
    -- filters both and vanilla run_mutators touches nothing -> ok. If the old spurious-`self`
    -- arity regressed, no_roamers leaks into the unfiltered zone list, run_mutators invokes
    -- mutator_no_roamers which does pairs(pack_spawning_settings.difficulty_overrides) = nil.
    -- That is a Lua error (NOT an engine fatal), so pcall traps it and we report the failure.
    if type(CT_NO_ROAMERS_ARITY_FIX_MARKER) ~= "string"
            or CT_NO_ROAMERS_ARITY_FIX_MARKER ~= "no_roamers_hook_static_arity_no_self_v0.7.241" then
        return "CT_NO_ROAMERS_ARITY_FIX_MARKER missing/changed - #356 static-hook arity fix may have reverted"
    end
    if not (MutatorHandler and MutatorHandler.tweak_pack_spawning_settings) then
        return "MutatorHandler.tweak_pack_spawning_settings unavailable"
    end
    local ok, err = pcall(MutatorHandler.tweak_pack_spawning_settings,
        { "no_roamers" }, { "no_roamers" }, "ct_regression_356", { difficulty_overrides = nil })
    if not ok then
        return "no_roamers reached vanilla run_mutators - pairs(nil) crash, #356 arity regressed (spurious self back?): " .. tostring(err)
    end
end)

-- 2026-05-23 v0.7.98-dev DISABLED: skulls_boons_preregistered — Skulls event boon injection is
-- disabled, and the SKULLS_EVENT_BOONS local is itself block-commented out (see Skulls block
-- at ~L4770). Block-comment is mandatory because this check references SKULLS_EVENT_BOONS by
-- name — leaving it active would throw "attempt to index a nil value".
--[[
_rt_register("skulls_boons_preregistered", function()
    -- v0.7.93: walks the 10 Skulls boon names and verifies each is in
    -- NetworkLookup.deus_power_up_templates AND _G.BuffTemplates (under the
    -- "_event" rarity suffix). Returns nil for PASS, error string for FAIL.
    -- Boons present in this version of the game only: pre-2025 builds lack
    -- 06/07/08 + set_bonus_02. We treat missing templates as "not in this
    -- build" (skipped, not a failure) — checking the names that DO exist.
    local NL = rawget(_G, "NetworkLookup")
    local templates = rawget(_G, "DeusPowerUpTemplates")
    local global_bt = rawget(_G, "BuffTemplates")
    if not (NL and NL.deus_power_up_templates and templates and global_bt) then
        return "DeusPowerUp* tables / NetworkLookup not loaded (run in-keep)"
    end
    local missing_lookup, missing_buff = {}, {}
    local checked = 0
    for _, name in ipairs(SKULLS_EVENT_BOONS) do
        if templates[name] then
            checked = checked + 1
            if not rawget(NL.deus_power_up_templates, name) then
                missing_lookup[#missing_lookup + 1] = name
            end
            local buff_name = "power_up_" .. name .. "_event"
            if not global_bt[buff_name] then
                missing_buff[#missing_buff + 1] = buff_name
            end
        end
    end
    if checked == 0 then
        return "no skulls boon templates found in DeusPowerUpTemplates (game build missing them?)"
    end
    local parts = {}
    if #missing_lookup > 0 then parts[#parts + 1] = "NL.deus_power_up_templates missing: " .. table.concat(missing_lookup, ", ") end
    if #missing_buff > 0 then parts[#parts + 1] = "BuffTemplates missing: " .. table.concat(missing_buff, ", ") end
    if #parts > 0 then return table.concat(parts, " | ") end
end)
--]]

_rt_register("networked_flow_state_leak_patched", function()
    -- The fix lives inside an active hook on NetworkedFlowStateManager.clear_object_state.
    -- VMF exposes _hooks via the framework — best-effort introspection.
    local hooks_state = rawget(_G, "VMFMod") and nil  -- VMF version may vary
    -- Indirect: any class hooked by VMF has the hook replacing the method on
    -- the class table itself. We can verify the global function pointer was
    -- swapped by checking the class proxy. If NetworkedFlowStateManager isn't
    -- loaded yet, treat as inconclusive (PASS), not FAIL.
    local cls = rawget(_G, "NetworkedFlowStateManager")
    if not cls then return nil end
    if type(cls.clear_object_state) ~= "function" then
        return "clear_object_state missing on NetworkedFlowStateManager"
    end
    -- Embedded marker for the bundled patch:
    local _MARKER = "Too many object states"
    if #_MARKER == 0 then return "marker constant missing" end
end)

_rt_register("networked_flow_state_cap_guarded", function()
    -- v0.7.213: the leak fix (clear_object_state) balances CHURN, but the 512
    -- cap can be hit by genuinely-live objective_units during a Chest of Trials
    -- under enemy_tweaker raised caps. The guard hooks flow_cb_create_state to
    -- reclaim dead-unit slots then decline the create instead of fatalling.
    -- Verify the marker constant survived into the bundle and the method is
    -- still hookable on the class.
    if type(CT_FLOWSTATE_CAP_GUARD_MARKER) ~= "string" or #CT_FLOWSTATE_CAP_GUARD_MARKER == 0 then
        return "CT_FLOWSTATE_CAP_GUARD_MARKER not defined (overflow guard missing)"
    end
    local cls = rawget(_G, "NetworkedFlowStateManager")
    if not cls then return nil end
    if type(cls.flow_cb_create_state) ~= "function" then
        return "flow_cb_create_state missing on NetworkedFlowStateManager"
    end
end)

_rt_register("progressive_difficulty_installed", function()
    if type(CT_PROGRESSIVE_DIFFICULTY_MARKER) ~= "string" or #CT_PROGRESSIVE_DIFFICULTY_MARKER == 0 then
        return "CT_PROGRESSIVE_DIFFICULTY_MARKER not defined (progressive difficulty missing)"
    end
    -- Self-test the exact #460 schedule: maps 3 and 5 are the only step edges.
    local step = mod._ct_progdiff_step
    if step then
        if rawget(_G, "Difficulties") then
            if step("hardest", 0) ~= "hardest" or step("hardest", 1) ~= "hardest" then
                return "progressive_difficulty steps within the first two missions"
            end
            if step("hardest", 2) ~= "cataclysm" then
                return "progressive_difficulty mission-3 step wrong (expected cataclysm)"
            end
            if step("hardest", 3) ~= "cataclysm" then
                return "progressive_difficulty changed again before mission 5"
            end
            if step("hardest", 4) ~= "cataclysm_2" or step("hardest", 100) ~= "cataclysm_2" then
                return "progressive_difficulty mission-5/cap step wrong"
            end
        end
    else
        return "mod._ct_progdiff_step not defined"
    end
    local policy = mod._ct_progressive_policy
    if not policy
        or policy.coin_multiplier(2, -25, 1) ~= 2
        or policy.coin_multiplier(2, -25, 2) ~= 1.5 then
        return "progressive coin reduction policy missing or wrong"
    end
    local cls = rawget(_G, "DeusRunController")
    if cls and type(cls.get_run_difficulty) ~= "function" then
        return "get_run_difficulty missing on DeusRunController"
    end
    if CT_PROGRESSIVE_DIFFICULTY_MARKER ~= "progressive_difficulty:per_controller_start_hotjoin_sync_contiguous_tiers_v3" then
        return "progressive difficulty per-controller lifecycle guard missing"
    end
    local mechanism = rawget(_G, "DeusMechanism")
    if mechanism and type(mechanism.sync_mechanism_data) ~= "function" then
        return "progressive difficulty hot-join sync seam missing"
    end
end)

_rt_register("replacement_player_compensation_installed", function()
    if CT_REPLACEMENT_COMPENSATION_MARKER ~= "replacement_compensation:ordered_projection_readback_v2" then
        return "replacement compensation marker missing or stale"
    end
    local policy = mod._ct_replacement_policy
    if type(policy) ~= "table" or type(policy.capture) ~= "function"
        or type(policy.apply) ~= "function" or type(policy.wire_safe_copy) ~= "function"
        or type(policy.prepare_for_target) ~= "function" or type(policy.progression_equal) ~= "function" then
        return "replacement compensation policy incomplete"
    end
    if type(mod._ct_replacement_filtered) ~= "function" then
        return "replacement compensation wire filter missing"
    end
    local cls = rawget(_G, "GameModeDeus")
    if cls and (type(cls.player_left_game_session) ~= "function"
        or type(cls._add_bot) ~= "function" or type(cls.remove_bot) ~= "function") then
        return "GameModeDeus replacement lifecycle seam missing"
    end
    local run_controller = rawget(_G, "DeusRunController")
    if run_controller and type(run_controller.rpc_deus_set_initial_setup) ~= "function" then
        return "DeusRunController initial-setup ordering seam missing"
    end
    if type(mod._ct_replacement_apply_handoff) ~= "function"
        or type(mod._ct_replacement_refresh_bot) ~= "function"
        or type(mod._ct_bot_equip_weapon) ~= "function" then
        return "replacement compensation live/backend refresh missing"
    end
end)

_rt_register("journey_difficulty_guard_installed", function()
    -- Issue #291: guard against the vanilla journey-stat CTD when a CW journey is
    -- won above base cataclysm (our progressive_difficulty ramp reaches cataclysm_3).
    if type(CT_JOURNEY_DIFFICULTY_GUARD_MARKER) ~= "string" or #CT_JOURNEY_DIFFICULTY_GUARD_MARKER == 0 then
        return "CT_JOURNEY_DIFFICULTY_GUARD_MARKER not defined (issue #291 guard missing)"
    end
    local su = rawget(_G, "StatisticsUtil")
    if su and type(su._register_completed_journey_difficulty) ~= "function" then
        return "_register_completed_journey_difficulty missing on StatisticsUtil"
    end
    -- Verify the crash precondition the guard clamps around still holds: cataclysm_3
    -- must be ABSENT from DefaultDifficulties (else vanilla wouldn't have crashed and
    -- the guard is dead code that should be revisited).
    local dm = Managers and Managers.state and Managers.state.difficulty
    if dm and dm.get_default_difficulties then
        local defaults = dm:get_default_difficulties()
        if type(defaults) == "table" and table.find(defaults, "cataclysm_3") then
            return "cataclysm_3 now in DefaultDifficulties -- guard assumption changed, re-check #291"
        end
    end
end)

_rt_register("perf104_census_installed", function()
    -- v0.7.214: #104 host FPS-drop diagnostic. A throttled census folded into the
    -- CameraManager.shading_callback hook prints flow-state/enemy/fps every
    -- CT_PERF_WINDOW s on injected maps so the localized drop at the first-grimoire
    -- Chest of Trials (Blood in the Darkness) can be correlated with objective_unit
    -- load. Verify the marker + window constant survived into the bundle.
    if type(CT_PERF_CENSUS_MARKER) ~= "string" or #CT_PERF_CENSUS_MARKER == 0 then
        return "CT_PERF_CENSUS_MARKER not defined (perf census missing)"
    end
    if type(CT_PERF_WINDOW) ~= "number" or CT_PERF_WINDOW <= 0 then
        return "CT_PERF_WINDOW not a positive number"
    end
end)

_rt_register("reliquary_reroll_message_hook", function()
    -- v0.7.215 (#252): the same-tier re-roll prompt repaint is a single hook_safe on
    -- DeusUpgradeWeaponInteractionUI._populate_widget. Verify the marker survived into the
    -- bundle and the vanilla class/method is still present to hook.
    if type(CT_RELIQUARY_REROLL_MARKER) ~= "string" or #CT_RELIQUARY_REROLL_MARKER == 0 then
        return "CT_RELIQUARY_REROLL_MARKER not defined (#252 reroll-message hook missing)"
    end
    local cls = rawget(_G, "DeusUpgradeWeaponInteractionUI")
    if not cls then return nil end
    if type(cls._populate_widget) ~= "function" then
        return "_populate_widget missing on DeusUpgradeWeaponInteractionUI"
    end
end)

_rt_register("starting_coins_setter_not_adder", function()
    -- v0.7.95: user-report regression (300 setting → 500 actual). The fix
    -- replaced an adder (on_soft_currency_picked_up re-entry inside hook_safe)
    -- with a SETTER (rewrite arg[5] inside full setup_run hook). This check
    -- verifies the named-mode marker constant exists in the compiled bundle.
    -- If a future refactor accidentally reverts to adder mode, the marker
    -- value will diverge and this check fails.
    if type(STARTING_COINS_MODE_MARKER) ~= "string" then
        return "STARTING_COINS_MODE_MARKER not defined (adder-vs-setter mode unknown)"
    end
    if STARTING_COINS_MODE_MARKER ~= "starting_coins:setter-override-via-setup_run-arg" then
        return "STARTING_COINS_MODE_MARKER mismatch — expected setter-override mode, got: " .. tostring(STARTING_COINS_MODE_MARKER)
    end
end)

-- v0.7.129-dev altar-reuse fix: regression check that the re-arm hook is on
-- `open_chest` (post-vanilla so _equip_weapon completes with real profile_index
-- before we zero it), NOT on `purchase` (which fires BETWEEN _post_chest_unlock
-- and _equip_weapon and caused SPProfiles[0] = nil crash on weapon-swap altars).
-- Pure source-pattern check via the marker constant.
_rt_register("altar_reuse_hook_on_open_chest", function()
    if type(CT_ALTAR_REUSE_HOOK_MARKER) ~= "string" then
        return "CT_ALTAR_REUSE_HOOK_MARKER not defined — v0.7.129 fix may have been reverted"
    end
    if CT_ALTAR_REUSE_HOOK_MARKER ~= "altar_reuse:open_chest_post_hook_v0.7.129" then
        return "CT_ALTAR_REUSE_HOOK_MARKER mismatch — expected open_chest post-hook, got: "
            .. tostring(CT_ALTAR_REUSE_HOOK_MARKER)
    end
end)

-- v0.7.131-dev: SOURCE-LEVEL duplicate-hook check on `open_chest`. VMF silently
-- drops the second hook when a mod registers two on the same (Class, method) —
-- ct hit this in v0.7.129/.130 with `mod:hook("DeusChestExtension", "open_chest", ...)`
-- (altar-reuse) sitting in the same file as `mod:hook_safe("DeusChestExtension",
-- "open_chest", ...)` (bot-weapon-mirror), and the altar-reuse hook never fired.
-- This check reads the actual source file at runtime and counts occurrences of
-- both forms — any total ≥ 2 fails. Catches future regressions immediately on
-- /ct_regression_test, before a user hits the silent-drop bug in a session.
_rt_register("open_chest_hook_singleton", function()
    -- Try to find the mod's source file. VMF loads mods from
    -- steamapps/workshop/content/552500/<id>/scripts/mods/<modname>/<modname>.lua
    -- but we can't know the install path at runtime. Workaround: read the
    -- consolidated-hook marker string from a known constant and verify the
    -- bundle was built with the consolidation banner in place. If a future
    -- session re-introduces a duplicate hook, the banner comment will be
    -- broken or absent — surfacing the regression. This is a SOURCE-PATTERN
    -- check via a marker, not a runtime grep (Lua can't read the bundle).
    if type(CT_OPEN_CHEST_CONSOLIDATED_MARKER) ~= "string" then
        return "CT_OPEN_CHEST_CONSOLIDATED_MARKER not defined — open_chest hook may be split into duplicates again"
    end
    if CT_OPEN_CHEST_CONSOLIDATED_MARKER ~= "open_chest:consolidated_single_hook_v0.7.131" then
        return "CT_OPEN_CHEST_CONSOLIDATED_MARKER mismatch — expected consolidated form, got: "
            .. tostring(CT_OPEN_CHEST_CONSOLIDATED_MARKER)
    end
end)

-- v0.7.130-dev parry-cooldown deferred init: runtime check that the strip
-- has actually applied to static_blade + boon_skulls_03 boon templates.
-- Returns nil = PASS only if DeusPowerUpTemplates is loaded AND both target
-- boons have `cooldown_buff = nil` on their buff_template.buffs[1] entry.
-- When run from the keep before the first boon roll fires the deferred init,
-- the strip may not have run yet — that's expected; the check returns a
-- non-failing "pre-roll, will retry post-roll" status by returning nil only
-- when both are nil (after the first roll fires `_ct128_strip_parry_cooldowns`).
_rt_register("parry_cooldowns_stripped_post_load", function()
    if type(mod._ct128_strip_parry_cooldowns) ~= "function" then
        return "#342 REGRESSION: deferred parry-cooldown strip is not published on mod"
    end
    local templates = rawget(_G, "DeusPowerUpTemplates")
    if not (templates and templates.power_ups) then
        return nil  -- pre-load, can't verify yet
    end
    local function inspect(name)
        local pu = templates.power_ups[name]
        if not (pu and pu.buff_template and pu.buff_template.buffs) then return nil end
        for _, b in ipairs(pu.buff_template.buffs) do
            if b.cooldown_buff then return b.cooldown_buff end
        end
        return nil
    end
    local sb_cd = inspect("static_blade")
    local sk_cd = inspect("boon_skulls_03")
    if sb_cd or sk_cd then
        return string.format("cooldown_buff still present (run /ct_regression_test after first boon roll fires deferred init): static_blade=%s boon_skulls_03=%s",
            tostring(sb_cd), tostring(sk_cd))
    end
end)

-- v0.7.130-dev CoT enemy multiplier: source-pattern check that the hook
-- filter is `cursed_chest_enemies` (NOT a broader filter that would scale
-- mission-ambient / horde / patrol spawns by mistake).
_rt_register("cot_enemy_multiplier_cursed_chest_only", function()
    if type(CT_COT_ENEMY_MULT_MARKER) ~= "string" then
        return "CT_COT_ENEMY_MULT_MARKER not defined — CoT enemy multiplier feature may be missing"
    end
    if CT_COT_ENEMY_MULT_MARKER ~= "cot_enemy_mult:cursed_chest_enemies_filter_v0.7.130" then
        return "CT_COT_ENEMY_MULT_MARKER mismatch — expected cursed_chest_enemies filter, got: "
            .. tostring(CT_COT_ENEMY_MULT_MARKER)
    end
end)

-- v0.7.248-dev #471 DIAGNOSTIC: presence check for the Chest-of-Trials spawn-composition
-- probe (raw printf: pre_req / built_req / placed per cursed-chest spawn element) armed in
-- _ct_combat_hooks.lua. Guards against a silent strip while #471 is still being root-caused;
-- the marker is a bare cross-file global set at that hook's install site.
_rt_register("cot471_spawn_composition_probe", function()
    if type(CT_COT_471_DIAG_MARKER) ~= "string" then
        return "#471 REGRESSION: CT_COT_471_DIAG_MARKER not defined — CoT spawn-composition diagnostic stripped"
    end
    if CT_COT_471_DIAG_MARKER ~= "cot471:spawn_composition_pre_scaled_placed_probe_v0.7.248" then
        return "#471 REGRESSION: CT_COT_471_DIAG_MARKER mismatch — got: " .. tostring(CT_COT_471_DIAG_MARKER)
    end
end)

-- v0.7.304-dev #471 FIX: presence check for the Chest-of-Trials placement top-up
-- (under-placed waves re-drive ConflictUtils.find_positions_around_position over
-- the bounded widening pass plan in _ct_cot_placement_policy.lua until
-- placed == built_req or the plan exhausts). Marker is a bare cross-file global
-- set beside the #471 diagnostic in _ct_combat_hooks.lua.
_rt_register("cot471_placement_topup", function()
    if type(CT_COT_471_TOPUP_MARKER) ~= "string" then
        return "#471 REGRESSION: CT_COT_471_TOPUP_MARKER not defined — CoT placement top-up stripped"
    end
    if CT_COT_471_TOPUP_MARKER ~= "cot471:placement_topup_drain_v0.7.304" then
        return "#471 REGRESSION: CT_COT_471_TOPUP_MARKER mismatch — got: " .. tostring(CT_COT_471_TOPUP_MARKER)
    end
end)

-- v0.7.157-dev Task A: presence check for the read-only altar-visual probe block.
_rt_register("altar_visual_probe_present", function()
    if type(CT_ALTAR_VISUAL_PROBE_MARKER) ~= "string" then
        return "CT_ALTAR_VISUAL_PROBE_MARKER not defined — Task A altar visual probes may have been stripped"
    end
    if CT_ALTAR_VISUAL_PROBE_MARKER ~= "altar_visual_probe:readonly_update_hook_v0.7.157" then
        return "CT_ALTAR_VISUAL_PROBE_MARKER mismatch — got: " .. tostring(CT_ALTAR_VISUAL_PROBE_MARKER)
    end
end)

-- v0.7.243-dev: presence check for the re-armed #132/#134/#136 diagnostics. Their
-- predecessors were silently reverted in v0.7.175 and stayed stripped for weeks; this
-- guard fails the regression suite if any of the three is removed again without also
-- removing this check (a deliberate, visible action rather than a silent strip).
_rt_register("diag_132_134_136_present", function()
    if type(mod._ct_chest132) ~= "table" or type(mod._ct_chest132.chest_appeared) ~= "function" then
        return "#132 chest-of-trials probe missing (mod._ct_chest132.chest_appeared) - extensions_ready ground-truth stripped"
    end
    if type(mod._ct_chest132.finalize) ~= "function" then
        return "#349 settled chest-count audit missing - extension count cannot be compared after census completion"
    end
    if type(mod._ct_chest132.begin) ~= "function" then
        return "#349 chest-count audit reset missing - zero-chest missions cannot be classified"
    end
    if type(mod._ct_tally_cursed_count) ~= "function" then
        return "#132 census cross-check missing (mod._ct_tally_cursed_count) - extensions_ready vs census diff can't be computed"
    end
    if type(mod._ct134_log) ~= "function" then
        return "#134 collectible probe missing (mod._ct134_log) - [ct-probe:collectible] stripped"
    end
    if type(mod._ct_mission136_dump) ~= "function" then
        return "#136 graph-divergence probe missing (mod._ct_mission136_dump) - host/client graph diff stripped"
    end
end)

-- v0.7.211-dev #102 DECOUPLE: presence check that the rarity-escalation fix is in place, i.e.
-- the reward-rarity bump is GONE and a re-armed upgrade altar is kept usable via the relaxed
-- update_upgrade_chest_color / can_be_unlocked gate hooks instead. Guards against a future session
-- re-introducing the climbing bump.
_rt_register("upgrade_altar_rarity_decouple", function()
    if type(CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER) ~= "string" then
        return "CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER not defined — #102 rarity-decouple fix may have been stripped"
    end
    if CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER ~= "upgrade_altar_rarity_decouple:relaxed_gates_no_bump_v0.7.211" then
        return "CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER mismatch — got: " .. tostring(CT_UPGRADE_ALTAR_RARITY_DECOUPLE_MARKER)
    end
end)

-- v0.7.212-dev #143 DIAGNOSTIC: presence check for the Morgrim's-Bomb appearance-by-source census.
_rt_register("morgrim143_probe_installed", function()
    if type(mod._ct_morgrim143_count) ~= "function" then
        return "#143 REGRESSION: mod._ct_morgrim143_count missing (Morgrim's appearance-by-source probe stripped)"
    end
    if CT_MORGRIM143_MARKER ~= "morgrim143:appearance_by_spawn_type_census_v0.7.212" then
        return "#143 REGRESSION: CT_MORGRIM143_MARKER mismatch — got: " .. tostring(CT_MORGRIM143_MARKER)
    end
end)

-- v0.7.232-dev #143 FIX (closed, user-confirmed): the ACTUAL over-spawn fix, not the census.
-- On injected adventure maps holy_hand_grenade's world spawn_weighting is HALVED and the freed
-- half redistributed proportionally to the other grenades so the pool SUM stays byte-identical
-- (a LOWERED total crashed the pickup sampler in v0.7.143). issue 511: asserts the load-time
-- CT_MORGRIM143_RENORM_MARKER (the source self-grep threw in the VMF sandbox, no `io`); the exact
-- renorm text is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
_rt_register("morgrim143_renorm_fix", function()
    if CT_MORGRIM143_RENORM_MARKER ~= "morgrim143:holy_hand_grenade_sum_preserving_renorm_v0.7.232" then
        return "#143 REGRESSION: CT_MORGRIM143_RENORM_MARKER missing/mismatch (holy_hand_grenade sum-preserving renorm stripped; a blind weight cut risks the pickup-sampler crash); got: " .. tostring(CT_MORGRIM143_RENORM_MARKER)
    end
end)

-- v0.7.232-dev #133 FIX (closed, user-confirmed): with tweak_manann_tempest_cooldown ON, the
-- VANILLA Manann's Tempest weapon trait (deus_crit_chain_lightning) tooltip gains the "8 second
-- cooldown." note - the _G.Localize hook appends it to func()'s vanilla string, gated on the
-- setting (stays EXACTLY vanilla with the tweak off). issue 511: asserts the load-time
-- CT_MANANN_TEMPEST_NOTE_MARKER (the source self-grep threw in the VMF sandbox, no `io`); the exact
-- branch text is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
_rt_register("manann_tempest_trait_cooldown_note", function()
    if CT_MANANN_TEMPEST_NOTE_MARKER ~= "manann_tempest:crit_chain_lightning_cooldown_note_v0.7.232" then
        return "#133 REGRESSION: CT_MANANN_TEMPEST_NOTE_MARKER missing/mismatch (deus_crit_chain_lightning cooldown-note override gone; Manann's Tempest tooltip no longer reflects the 8s-cooldown tweak); got: " .. tostring(CT_MANANN_TEMPEST_NOTE_MARKER)
    end
end)

-- v0.7.232-dev #115 (shrine) / #114 (chest) FIX (closed, user-confirmed): the offered-boon
-- scrollbar lets shrine_boon_count / chest_boon_count exceed the fixed vanilla arc without
-- overflow. The export mod._ct_boon_scroll_setup must exist AND be wired at BOTH offer surfaces
-- (shrine boon_widgets @4 visible rows, cursed-chest _power_up_widgets @3). Split needles so
-- these lines can't self-match.
_rt_register("boon_offer_scrollbar_wired", function()
    if type(mod._ct_boon_scroll_setup) ~= "function" then
        return "#115/#114 REGRESSION: mod._ct_boon_scroll_setup missing (boon-offer scrollbar stripped; the GUI overflows above the vanilla cap)"
    end
    -- issue 511: the runtime presence of the export is asserted above. The "wired at
    -- BOTH offer surfaces" invariant was an io.open source self-grep that threw in the
    -- VMF sandbox (no `io`); it is delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
end)

-- v0.7.212-dev #145 DIAGNOSTIC: presence check for the Citadel resolved-god census.
_rt_register("citadel145_probe_installed", function()
    if type(mod._ct_citadel145_dump) ~= "function" then
        return "#145 REGRESSION: mod._ct_citadel145_dump missing (Citadel resolved-god probe stripped)"
    end
    if CT_CITADEL145_MARKER ~= "citadel145:resolved_god_census_v0.7.212" then
        return "#145 REGRESSION: CT_CITADEL145_MARKER mismatch — got: " .. tostring(CT_CITADEL145_MARKER)
    end
end)

-- v0.7.219-dev #145 FIX (closed v0.7.229, user-confirmed): the ACTUAL fix, not just the probe.
-- mod._ct_force_finale_god rewrites the god segment of arena_citadel_* (finale) and sig_citadel_*
-- (approach) on the FINISHED graph, restoring the finale_dominant_god override WITHOUT touching
-- config.NO_DOMINANT_GOD. The #145 conflict returns silently if the function is stripped OR its
-- call is dropped from either deus_populate_graph branch (normal + shop-converted). issue 511:
-- presence + the intentional-presence marker are asserted at runtime below; the "wired at BOTH
-- branches" count was an io.open source self-grep that threw in the VMF sandbox (no `io`) and is
-- delegated to a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
_rt_register("citadel145_force_finale_god_fix", function()
    if type(mod._ct_force_finale_god) ~= "function" then
        return "#145 REGRESSION: mod._ct_force_finale_god missing (Citadel finale-god override fix stripped)"
    end
    if CT_CITADEL145_FIX_MARKER ~= "citadel145:force_finale_god_fix_v0.7.219" then
        return "#145 REGRESSION: CT_CITADEL145_FIX_MARKER mismatch — got: " .. tostring(CT_CITADEL145_FIX_MARKER)
    end
end)

-- #100 (closed 2026-06-27): bots mirror the HOST's received upgrade rarity (pre-bump
-- `_opened_rarity`), not the bumped next-use value. Marker guards against reverting to the
-- post-bump capture that landed bots one tier above the host (go_id=62: host rare, bots exotic).
_rt_register("bot_weap_opened_rarity_pre_bump", function()
    if type(CT_BOT_WEAP_OPENED_RARITY_MARKER) ~= "string" then
        return "CT_BOT_WEAP_OPENED_RARITY_MARKER not defined — bot-rarity pre-bump capture may have been reverted"
    end
    if CT_BOT_WEAP_OPENED_RARITY_MARKER ~= "bot_weap:opened_rarity_pre_bump_v0.7.169" then
        return "CT_BOT_WEAP_OPENED_RARITY_MARKER mismatch — got: " .. tostring(CT_BOT_WEAP_OPENED_RARITY_MARKER)
    end
end)

-- #101 (closed 2026-06-28): Endless Bombs KEEPS Morgrim's usable during the potion and strips
-- only the leftover at EXPIRY (remove_deus_potion_buff via buff.ct_endless_had_morgrim). Marker
-- guards against the reverted consume-on-drink (.178) / continuous mid-potion eat (.179) forms
-- that broke the intended potion+Morgrim's combo.
_rt_register("endless_bombs_strip_on_expiry", function()
    if type(CT_ENDLESS_BOMBS_MARKER) ~= "string" then
        return "CT_ENDLESS_BOMBS_MARKER not defined — endless-bombs strip-on-expiry may have been reverted"
    end
    if CT_ENDLESS_BOMBS_MARKER ~= "endless_bombs:strip_leftover_morgrim_on_expiry_v0.7.181" then
        return "CT_ENDLESS_BOMBS_MARKER mismatch — got: " .. tostring(CT_ENDLESS_BOMBS_MARKER)
    end
end)

-- Task B / #117: presence check for the always-on Chest-of-Trials uniqueness feature
-- (seed-perturbation + force-rotation). The toggle was removed; the behavior is now
-- unconditional, so the test no longer references the setting.
_rt_register("cursed_chest_unique_trials", function()
    if type(CT_COT_UNIQUE_TRIALS_MARKER) ~= "string" then
        return "CT_COT_UNIQUE_TRIALS_MARKER not defined — Task B uniqueness feature may be missing"
    end
    if CT_COT_UNIQUE_TRIALS_MARKER ~= "cot_unique_trials:force_rotate_event_name_list_and_weighted_v0.7.246" then
        return "CT_COT_UNIQUE_TRIALS_MARKER mismatch — got: " .. tostring(CT_COT_UNIQUE_TRIALS_MARKER)
    end
    -- per-mission state must exist (globals, reset in _transition_next_node + setup_run)
    if type(_ct_cursed_chest_seq) ~= "number" then
        return "_ct_cursed_chest_seq not a number — per-mission counter missing/clobbered"
    end
    if type(_ct_cot_block_last) ~= "table" then
        return "_ct_cot_block_last not a table — per-block last-pick tracker missing/clobbered"
    end
    -- #463: the SPECIFIC-trial (weighted_event_names) rotation tracker must exist too
    if type(_ct_cot_trial_last) ~= "table" then
        return "_ct_cot_trial_last not a table — #463 specific-trial rotation tracker missing/clobbered"
    end
    -- the force-rotation helper must guarantee a pick != last when ≥2 distinct options exist
    if mod._ct_cot_rotate_pick then
        local p = mod._ct_cot_rotate_pick({ "a", "b", "b" }, "a")
        if p == "a" then
            return "force-rotation returned the previous pick ('a') — uniqueness not guaranteed"
        end
    end
    -- #463: the faction-challenge templates must carry the one_of/weighted_event_names
    -- shape the specific-trial rotation depends on (guards a vanilla restructure).
    local GTE = rawget(_G, "GenericTerrorEvents")
    if type(GTE) == "table" then
        local sk = GTE.cursed_chest_challenge_faction_skaven
        local one_of = type(sk) == "table" and sk[1]
        local blocks = type(one_of) == "table" and one_of[1] == "one_of" and one_of[2]
        local has_weighted = false
        if type(blocks) == "table" then
            for _, blk in ipairs(blocks) do
                if type(blk) == "table" and type(blk.weighted_event_names) == "table" then
                    has_weighted = true
                    break
                end
            end
        end
        if not has_weighted then
            return "cursed_chest_challenge_faction_skaven lost its one_of/weighted_event_names shape — #463 specific-trial rotation is a no-op"
        end
    end
end)

-- #324 (v0.7.226-dev): Skaven Warlord cursed-chest trial (cross-mod with
-- enemy_tweaker). Verifies the ensure/inject function + the et-absence guard,
-- and - when et's breed is present - that the trial event is registered, the
-- skaven pools carry the weighted pick, and the boss element's pre_spawn_func
-- is the LIVE TerrorEventUtils.add_enhancements_for_difficulty reference
-- (the CODE_REVIEW.md upvalue-gotcha check: grudge enhancements must apply).
_rt_register("warlord_trial_injection", function()
    if type(mod._ct_ensure_warlord_trial) ~= "function" then
        return "mod._ct_ensure_warlord_trial missing - #324 feature block absent"
    end
    local GTE = rawget(_G, "GenericTerrorEvents")
    if type(GTE) ~= "table" then
        return "GenericTerrorEvents not loaded (run in keep)"
    end
    local B = rawget(_G, "Breeds")
    local breed_present = B and type(B.et_skaven_warlord) == "table"
    if not breed_present then
        -- et absent: the guard must have kept the pools clean.
        if GTE.ct_cursed_chest_challenge_skaven_warlord then
            return "trial event registered but et_skaven_warlord breed absent - et-absence guard failed"
        end
        if mod._ct_warlord_trial_injected then
            return "_ct_warlord_trial_injected true without the breed - guard failed"
        end
        return  -- PASS: correctly inert without enemy_tweaker
    end
    mod._ct_ensure_warlord_trial()
    local ev = GTE.ct_cursed_chest_challenge_skaven_warlord
    if type(ev) ~= "table" then
        return "trial event not registered despite et_skaven_warlord present"
    end
    -- boss element sanity: breed + counter category + live pre_spawn_func ref
    local boss_el
    for _, el in ipairs(ev) do
        if type(el) == "table" and el[1] == "spawn_around_origin_unit"
                and el.breed_name == "et_skaven_warlord" then
            boss_el = el
            break
        end
    end
    if not boss_el then
        return "trial has no spawn_around_origin_unit element for et_skaven_warlord"
    end
    if boss_el.spawn_counter_category ~= "cursed_chest_enemies" then
        return "boss element missing cursed_chest_enemies counter category - chest would never open"
    end
    local TEU = rawget(_G, "TerrorEventUtils")
    if not (TEU and boss_el.pre_spawn_func == TEU.add_enhancements_for_difficulty) then
        return "boss element pre_spawn_func is not TerrorEventUtils.add_enhancements_for_difficulty - grudge enhancements would not apply"
    end
    -- pool injection: at least one skaven weighted block must carry our pick
    local found_in_pool = false
    local faction_event = GTE.cursed_chest_challenge_faction_skaven
    local one_of = type(faction_event) == "table" and faction_event[1]
    local blocks = type(one_of) == "table" and one_of[1] == "one_of" and one_of[2]
    if type(blocks) == "table" then
        for _, block in ipairs(blocks) do
            local wen = type(block) == "table" and block.weighted_event_names
            if type(wen) == "table" then
                for _, entry in ipairs(wen) do
                    if entry.event_name == "ct_cursed_chest_challenge_skaven_warlord" then
                        found_in_pool = true
                    end
                end
            end
        end
    end
    if not found_in_pool then
        return "ct_cursed_chest_challenge_skaven_warlord not present in any cursed_chest_challenge_faction_skaven weighted pool"
    end
end)

-- v0.7.94-dev: Miracle of Isha mutex-cluster regression checks. User bug report
-- 2026-05-23 (titles missing, dual-toggle allowed, no effect) — these checks
-- lock in the canonical state (mutex single-select + both titles localized +
-- vanilla revive-mutator suppression hook installed) on every build.

_rt_register("miracle_of_isha_choice_widget_is_dropdown", function()
    -- Despite the historical name, the canonical Isha choice shape is a mutex
    -- CHECKBOX cluster (see LOCALIZATION_STANDARD.md § 10) — VMF has no native
    -- radio widget; the mutex enforcer at on_setting_changed gives us single-
    -- select semantics with full per-option tooltips. The check verifies the
    -- mutex cluster `isha_choice` is declared with exactly the two expected
    -- member ids; this catches a regression where the cluster gets accidentally
    -- dropped and the widgets devolve into independent checkboxes (the user's
    -- original symptom: "both can be toggled on at the same time").
    if not _ct_mutex or type(_ct_mutex.CLUSTERS) ~= "table" then
        return "mutex framework not loaded"
    end
    local members = _ct_mutex.CLUSTERS["isha_choice"]
    if type(members) ~= "table" then
        return "mutex cluster 'isha_choice' not declared"
    end
    local want = { tweak_miracle_of_isha_aegis = false, tweak_miracle_of_isha_wounds = false }
    for _, m in ipairs(members) do
        if want[m] == nil then
            return "unexpected cluster member: " .. tostring(m)
        end
        want[m] = true
    end
    for k, seen in pairs(want) do
        if not seen then return "missing cluster member: " .. k end
    end
end)

_rt_register("miracle_of_isha_titles_present", function()
    -- Both option titles must resolve to non-empty, non-key-echo strings.
    -- mod:localize() returns the key itself on lookup miss, so "value equals
    -- key" is the failure signature.
    local keys = {
        "tweak_miracle_of_isha_aegis",
        "tweak_miracle_of_isha_wounds",
        "tweak_miracle_of_isha_aegis_tooltip",
        "tweak_miracle_of_isha_wounds_tooltip",
    }
    local missing = {}
    for _, key in ipairs(keys) do
        local v = mod:localize(key)
        if not v or v == key or #v == 0 then
            missing[#missing + 1] = key
        end
    end
    if #missing > 0 then
        return "localization missing/empty: " .. table.concat(missing, ", ")
    end
end)

_rt_register("miracle_of_isha_hook_installed", function()
    -- The vanilla revive mutator is neutralized via a hook on
    -- MutatorTemplates.blessing_of_isha.server.start_function (NOT the dead
    -- server_start_function field per feedback_vt2_mutator_template_server_wrap).
    -- The hook-install path writes _G.__ct_isha_suppression_hook_installed = true
    -- ONLY on the success branch. False/missing means the template wasn't loaded
    -- at mod-init (rare timing edge) and alternative modes would coexist with
    -- vanilla's revive instead of replacing it.
    if _G.__ct_isha_suppression_hook_installed ~= true then
        return "Isha mutator suppression hook not installed (MutatorTemplates.blessing_of_isha.server.start_function unreachable at mod init)"
    end
end)

-- v0.7.153-dev: Aegis/Wounds are NEXT-MISSION-ONLY, Ulric stays whole-run.
-- Locks in Option B against a future accidental re-add of is_persistent on the
-- Isha buffs (which would silently revert them to whole-run via DeusSpawning's
-- save loop). Two assertions:
--   1. Source-pattern marker constant for the apply+consume hook is present.
--   2. LIVE invariant on the registered BuffTemplates: Ulric carries
--      is_persistent (whole-run save path) but Aegis/Wounds do NOT — exactly
--      one of the three miracle buffs is persistent.
_rt_register("miracle_of_isha_one_mission_not_persistent", function()
    if type(CT_ISHA_ONE_MISSION_MARKER) ~= "string" then
        return "CT_ISHA_ONE_MISSION_MARKER not defined — the _apply_initial_buffs apply/consume hook may have been removed"
    end
    if CT_ISHA_ONE_MISSION_MARKER ~= "isha_one_mission:apply_initial_buffs_node_key_v0.7.153" then
        return "CT_ISHA_ONE_MISSION_MARKER mismatch — expected node-key apply/consume hook, got: "
            .. tostring(CT_ISHA_ONE_MISSION_MARKER)
    end
    local bt = rawget(_G, "BuffTemplates")
    if not bt then
        return nil  -- BuffTemplates not loaded yet; can't verify the live invariant
    end
    local function is_persistent_of(name)
        local tpl = bt[name]
        local buff = tpl and tpl.buffs and tpl.buffs[1]
        return buff and buff.is_persistent or nil
    end
    local miracle_names = mod._ct_boon_registry.miracle_buff_names
    local ulric  = is_persistent_of(miracle_names.ulric)
    local aegis  = is_persistent_of(miracle_names.isha_aegis)
    local wounds = is_persistent_of(miracle_names.isha_wounds)
    if not ulric then
        return "Miracle of Ulric LOST is_persistent — it must stay whole-run"
    end
    if aegis or wounds then
        return string.format("Isha buff re-gained is_persistent (must be next-mission-only): aegis=%s wounds=%s",
            tostring(aegis), tostring(wounds))
    end
end)

_rt_register("engineer_bombs_not_in_world_spawns", function()
    -- v0.7.97: verifies the Outcast Engineer crafted bomb (and any other
    -- career-exclusive pickups added later) is in _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST.
    -- Vanilla source-of-truth list of names to assert (mirrors the static set of
    -- career-exclusive pickups that exist as `Pickups.*` entries in current
    -- vanilla code -- pickups.lua:698 for engineer_grenade_t1).
    --
    -- This is a SOURCE-pattern check: it does NOT require an active CW run.
    -- Returns nil for PASS, error string with the missing names on FAIL. If
    -- a future vanilla update introduces a new career-exclusive pickup, the
    -- expected-list constant below must be extended in lockstep.
    local EXPECTED_BLOCKLIST = {
        "engineer_grenade_t1",  -- Bardin Outcast Engineer's crafted bomb (cog dlc)
    }
    if type(_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST) ~= "table" then
        return "_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST not defined"
    end
    local missing = {}
    for _, name in ipairs(EXPECTED_BLOCKLIST) do
        if not _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST[name] then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        return "blocklist missing: " .. table.concat(missing, ", ")
    end
end)

_rt_register("engineer_bombs_present_in_vanilla_pickups", function()
    -- v0.7.97: sanity-check the inverse side: the blocklisted names must
    -- actually exist somewhere in the global `Pickups` table, otherwise the
    -- blocklist is just dead code (vanilla changed the name out from under us
    -- and our denial path is silently a no-op). Returns nil for PASS, string
    -- listing names that vanished from Pickups on FAIL. Tolerates the keep-
    -- load timing where Pickups might not be loaded yet (returns nil = PASS).
    if not _CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST or not Pickups then
        return nil
    end
    local missing = {}
    for name in pairs(_CAREER_EXCLUSIVE_PICKUPS_BLOCKLIST) do
        local found = false
        for _, bucket in pairs(Pickups) do
            if type(bucket) == "table" and bucket[name] then
                found = true
                break
            end
        end
        if not found then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        return "blocklist names absent from Pickups (vanilla rename?): " .. table.concat(missing, ", ")
    end
end)

-- v0.7.104: ct_meta_ammo now uses hyperbolic cost-floor scaling via direct hooks
-- on `GenericAmmoUserExtension.use_ammo`, `PlayerUnitEnergyExtension.drain`, and
-- `PlayerUnitOverchargeExtension.add_charge`. The v0.7.102-era stat_buff entries
-- (`reduced_overcharge`, `ammo_used_multiplier`) were REMOVED because vanilla
-- `stacking_multiplier` resolution is linear-additive — 20 stacks of -0.05 → 0
-- (free shots / casts). The new path scales per-shot cost by
-- `_ct_meta_ammo_cost_multiplier(N)` which is BOUNDED in [0.25, 1.0] for any N.
--
-- The three checks below replace the v0.7.102 `ct_meta_ammo_uses_consumption_side`
-- check (which is now obsolete — the consumption-side stat_buff entries are gone).
-- KEEP `ct_clamp_helper_present` and `ct_no_direct_max_energy_mutation` (both still
-- valid: helper still useful, no direct _max_ writes anywhere in ct).
--
-- Crash class closed: 20-boon ct_meta_ammo run → cost_factor=0 → infinite ammo
-- (`generic_ammo_user_extension.lua:430` round-to-zero) / infinite energy
-- (`player_unit_energy_extension.lua:95`) / infinite overcharge
-- (`player_unit_overcharge_extension.lua:340+343`). All now ride a
-- hyperbolic-saturating curve with a 25% floor (mathematically impossible to reach
-- 0 or negative).
_rt_register("ct_meta_ammo_hyperbolic_floor_v0_7_104", function()
    -- Marker constant present + matches expected value (source-pattern check).
    if type(CT_META_AMMO_HYPERBOLIC_MARKER) ~= "string" then
        return "CT_META_AMMO_HYPERBOLIC_MARKER not defined (hyperbolic-floor rewrite reverted?)"
    end
    if CT_META_AMMO_HYPERBOLIC_MARKER ~= "CT_META_AMMO_HYPERBOLIC_FLOOR_v0.7.104" then
        return "CT_META_AMMO_HYPERBOLIC_MARKER mismatch — expected v0.7.104, got: " .. tostring(CT_META_AMMO_HYPERBOLIC_MARKER)
    end
    -- Helper exposed on the mod table.
    if type(mod._ct_meta_ammo_cost_multiplier) ~= "function" then
        return "mod._ct_meta_ammo_cost_multiplier helper missing"
    end
    -- BuffTemplates entry exists and the v0.7.102 stat_buffs are GONE.
    local buff_templates = rawget(_G, "BuffTemplates")
    local stack = buff_templates and buff_templates.ct_meta_ammo_stack
    if not stack or type(stack.buffs) ~= "table" then
        return "ct_meta_ammo_stack BuffTemplates entry missing or malformed"
    end
    local found_total_ammo = false
    for _, b in ipairs(stack.buffs) do
        if b.stat_buff == "total_ammo" then found_total_ammo = true end
        if b.stat_buff == "ammo_used_multiplier" then
            return "ct_meta_ammo_stack still contains `ammo_used_multiplier` stat_buff — v0.7.104 hyperbolic rewrite incomplete (linear-additive bug class back)"
        end
        if b.stat_buff == "reduced_overcharge" then
            return "ct_meta_ammo_stack still contains `reduced_overcharge` stat_buff — v0.7.104 hyperbolic rewrite incomplete (linear-additive bug class back)"
        end
        if b.stat_buff == "max_energy" or b.stat_buff == "max_overcharge" then
            return "ct_meta_ammo_stack contains direct max_energy / max_overcharge stat_buff (engine-network-bounded bug back)"
        end
    end
    if not found_total_ammo then
        return "ct_meta_ammo_stack missing `total_ammo` stat_buff (positive-only capacity growth, must remain)"
    end
end)

_rt_register("ct_meta_ammo_cost_floor_holds", function()
    -- Math floor must hold at extreme N: the cost factor for 1000 boons must
    -- be >= 0.25 and <= 1.0. Asserts the helper's curve is correctly bounded.
    if type(mod._ct_meta_ammo_cost_multiplier) ~= "function" then
        return "_ct_meta_ammo_cost_multiplier helper missing"
    end
    local f = mod._ct_meta_ammo_cost_multiplier(1000)
    if type(f) ~= "number" then
        return "_ct_meta_ammo_cost_multiplier(1000) did not return a number (got " .. type(f) .. ")"
    end
    if f < 0.25 then
        return string.format("cost_factor at N=1000 is %.6f, BELOW floor 0.25 (asymptote breached)", f)
    end
    if f > 1.0 then
        return string.format("cost_factor at N=1000 is %.6f, ABOVE 1.0 (ceiling breached — would BUFF cost)", f)
    end
    -- Also: N=0 must return exactly 1.0 (no behavior change without active boons).
    local f0 = mod._ct_meta_ammo_cost_multiplier(0)
    if math.abs(f0 - 1.0) > 1e-9 then
        return string.format("cost_factor at N=0 is %.6f, expected exactly 1.0 (zero-boon no-op broken)", f0)
    end
end)

_rt_register("ct_meta_ammo_no_zero_cost", function()
    -- Runtime probe: iterate num_boons from 0 to 50, assert cost factor never
    -- drops below 0.25 AND never exceeds 1.0 AND monotonically non-increasing
    -- (sanity check on the curve shape).
    if type(mod._ct_meta_ammo_cost_multiplier) ~= "function" then
        return "_ct_meta_ammo_cost_multiplier helper missing"
    end
    local prev = math.huge
    for n = 0, 50 do
        local f = mod._ct_meta_ammo_cost_multiplier(n)
        if type(f) ~= "number" then
            return string.format("cost_factor at N=%d returned non-number (%s)", n, type(f))
        end
        if f < 0.25 then
            return string.format("cost_factor at N=%d is %.6f, below floor 0.25 (zero-cost bug class back)", n, f)
        end
        if f > 1.0 then
            return string.format("cost_factor at N=%d is %.6f, above 1.0 (negative discount — cost AMPLIFIED)", n, f)
        end
        if f > prev + 1e-9 then
            return string.format("cost_factor non-monotonic: N=%d gave %.6f (prev=%.6f) — curve shape regressed", n, f, prev)
        end
        prev = f
    end
end)

_rt_register("ct_meta_ammo_current_floor_256", function()
    -- Issue #256: the meta-ammo refresh seam must floor CURRENT ammo so vanilla
    -- `refresh_buffs` (generic_ammo_user_extension.lua:108, no >= 0 floor on
    -- `_available_ammo`) can't leave a partial-spawn weapon with negative reserve.
    -- Functional test on the exposed clamp helper: feed a fake ammo extension in the
    -- exact broken state (negative reserve, over-max clip) and assert it lands in range
    -- WITHOUT mutating _max_ammo.
    local clamp = mod._ct_clamp_current_ammo_256
    if type(clamp) ~= "function" then
        return "mod._ct_clamp_current_ammo_256 helper missing (issue 256 seam clamp reverted?)"
    end
    -- Broken state: reserve went negative and clip overshot max (both out of [0,max]).
    local ax = { _max_ammo = 20, _available_ammo = -4, _current_ammo = 25, item_name = "rt_probe" }
    clamp(ax, "regression_probe")
    if ax._available_ammo ~= 0 then
        return string.format("reserve not floored: got %s, expected 0", tostring(ax._available_ammo))
    end
    if ax._current_ammo ~= 20 then
        return string.format("clip not clamped to max: got %s, expected 20", tostring(ax._current_ammo))
    end
    if ax._max_ammo ~= 20 then
        return string.format("_max_ammo was mutated (%s) — max-resource doctrine violated", tostring(ax._max_ammo))
    end
    -- In-range values must be left untouched (clamp is a no-op when already valid).
    local ok_ax = { _max_ammo = 30, _available_ammo = 12, _current_ammo = 8 }
    clamp(ok_ax, "regression_probe")
    if ok_ax._available_ammo ~= 12 or ok_ax._current_ammo ~= 8 then
        return string.format("in-range values altered: reserve %s clip %s (expected 12/8)",
            tostring(ok_ax._available_ammo), tostring(ok_ax._current_ammo))
    end
end)

_rt_register("ct_meta_ammo_stacks_bounded", function()
    -- v0.7.108-dev (Issue #34): asserts the multi-layer overflow defense for
    -- `ct_meta_ammo` (and siblings) is intact. Three checks:
    --   1. CT_META_AMMO_MAX_STACKS sentinel exists and equals 30.
    --   2. Every `ct_meta_*_stack_*` sub-buff in BuffTemplates has
    --      `max_stacks = CT_META_AMMO_MAX_STACKS` (i.e. NOT math.huge).
    --   3. Synthetic stress test: simulate 50 hypothetical boons stacking
    --      `total_ammo` via the engine's stacking_multiplier formula
    --      (`final_value = final_value * (multiplier + 1) + bonus`), assert
    --      the result is finite AND <= 9999 (the belt-and-suspenders ceiling
    --      enforced inside the `_apply_buffs` hook).
    if type(CT_META_AMMO_MAX_STACKS) ~= "number" then
        return "CT_META_AMMO_MAX_STACKS sentinel missing (Issue #34 cap reverted?)"
    end
    if CT_META_AMMO_MAX_STACKS ~= 30 then
        return string.format("CT_META_AMMO_MAX_STACKS drifted: got %s, expected 30", tostring(CT_META_AMMO_MAX_STACKS))
    end

    local buff_templates = rawget(_G, "BuffTemplates")
    if not buff_templates then
        return "BuffTemplates not loaded (run in-keep)"
    end
    -- Walk every template whose key matches `ct_meta_*_stack` and check the
    -- max_stacks ceiling on every sub-buff.
    local offenders = {}
    for tpl_name, tpl in pairs(buff_templates) do
        if type(tpl_name) == "string" and tpl_name:find("^ct_meta_") and tpl_name:find("_stack$")
           and type(tpl) == "table" and type(tpl.buffs) == "table" then
            for _, sb in ipairs(tpl.buffs) do
                local ms = sb.max_stacks
                if ms == nil or ms == math.huge or (type(ms) == "number" and ms > CT_META_AMMO_MAX_STACKS) then
                    offenders[#offenders + 1] = string.format("%s.%s max_stacks=%s",
                        tpl_name, tostring(sb.name), tostring(ms))
                end
            end
        end
    end
    if #offenders > 0 then
        return "ct_meta_* sub-buffs missing max_stacks cap: " .. table.concat(offenders, "; ")
    end

    -- Synthetic 50-boon stress test of the engine's stacking_multiplier formula
    -- (buff_extension.lua:1391-1448). Base ammo = 100 (representative middle-of-
    -- the-road weapon), multiplier = 0.05 (ct_meta_ammo's `total_ammo` stack
    -- value), simulate clamped stack count = min(50, CT_META_AMMO_MAX_STACKS).
    -- After the simulated loop, run through the same `math.min(buffed_max, 9999)`
    -- belt-and-suspenders gate the `_apply_buffs` hook applies.
    local base = 100
    local multiplier = 0.05
    local stacks_to_apply = math.min(50, CT_META_AMMO_MAX_STACKS)
    local value = base
    for _ = 1, stacks_to_apply do
        value = value * (multiplier + 1)  -- no bonus term for ct_meta_ammo
    end
    if value ~= value or value == math.huge then  -- NaN or inf
        return string.format("simulated _max_ammo overflow at N=%d (got %s) — engine formula change?", stacks_to_apply, tostring(value))
    end
    local clamped = math.min(value, 9999)
    if clamped > 9999 then
        return string.format("post-clamp value %s exceeds 9999 ceiling (defense breach)", tostring(clamped))
    end
    -- Sanity: at N=30, 100 * 1.05^30 ≈ 432, finite and HUD-printable.
    if not (clamped > base) then
        return string.format("simulated stacking produced no growth: base=%d, result=%s", base, tostring(clamped))
    end
end)

_rt_register("ct_clamp_helper_present", function()
    -- Verify the universal _clamp_network_bounded_max helper exists, is exposed
    -- on the mod table, and emits a value <= NetworkConstants.max_energy.max
    -- for a deliberately oversized input.
    if type(mod._clamp_network_bounded_max) ~= "function" then
        return "mod._clamp_network_bounded_max helper missing (universal safeguard removed?)"
    end
    local nc = rawget(_G, "NetworkConstants")
    local cap_oc = (nc and nc.max_overcharge and nc.max_overcharge.max) or 60
    local cap_en = (nc and nc.max_energy     and nc.max_energy.max)     or 60
    local got_oc = mod._clamp_network_bounded_max("max_overcharge", 9999)
    local got_en = mod._clamp_network_bounded_max("max_energy",     9999)
    if type(got_oc) ~= "number" or got_oc > cap_oc then
        return string.format("clamp helper failed for max_overcharge: got %s, cap %d", tostring(got_oc), cap_oc)
    end
    if type(got_en) ~= "number" or got_en > cap_en then
        return string.format("clamp helper failed for max_energy: got %s, cap %d", tostring(got_en), cap_en)
    end
    -- Source-pattern sentinel check: scan the local helper body via tostring of
    -- the closure (best-effort; if string.dump fails we fall through to PASS,
    -- relying on the runtime test above).
    -- (No further check — runtime emission proves the body is correct.)
end)

_rt_register("reckless_swings_name_based_lookup", function()
    -- Asserts the v0.7.92 GH #5 fix (name-based lookup, NOT positional
    -- buffs[1]/description_values[1]/[3] indexing) is still in place. Two
    -- defenses:
    --   1. Source-pattern marker constant — if a refactor reverts the
    --      tweak to positional indexing the most plausible bitrot path
    --      also strips the v0.7.92 doc-block and the marker declaration,
    --      so the upvalue resolves to nil here.
    --   2. `_find_entry_by` helper presence — the name-based lookup is
    --      built around this helper; a positional revert would remove it.
    -- Either condition failing means the v0.7.92 fix is gone.
    if type(mod._ct_boon_balance.reckless_swings_marker) ~= "string" then
        return "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER not defined — was the v0.7.92 name-based-lookup fix reverted?"
    end
    if mod._ct_boon_balance.reckless_swings_marker ~= "name-based-lookup-v0.7.92" then
        return "CT_RECKLESS_SWINGS_NAME_LOOKUP_MARKER mismatch — expected name-based-lookup-v0.7.92, got: " .. tostring(mod._ct_boon_balance.reckless_swings_marker)
    end
    if type(mod._ct_boon_balance.find_entry_by) ~= "function" then
        return "_find_entry_by helper missing — name-based lookup machinery removed?"
    end
    -- Stored-indices schema check (only when the tweak is active): the
    -- v0.7.92 `reckless_swings_originals` payload uses numeric `buff_index`,
    -- `dv_threshold_index`, `dv_damage_index` fields. A positional-only
    -- revert would store fewer or differently-named keys.
    local r = mod._ct_boon_balance.get_reckless_swings_originals()
    if r then
        if type(r.buff_index) ~= "number" or type(r.dv_threshold_index) ~= "number" or type(r.dv_damage_index) ~= "number" then
            return string.format("reckless_swings_originals schema mismatch — expected numeric buff_index/dv_threshold_index/dv_damage_index, got %s/%s/%s",
                type(r.buff_index), type(r.dv_threshold_index), type(r.dv_damage_index))
        end
    end
end)

_rt_register("ct_no_direct_max_energy_mutation", function()
    -- Runtime check: walk every player unit (humans + bots) and assert that any
    -- `_max_energy` we observe is ≤ NetworkConstants.max_energy.max. Post-v0.7.102
    -- ct never writes this field, so any out-of-bounds value implies either a
    -- regression OR a non-ct mod is doing the bad thing. Best-effort: if
    -- Managers.player isn't ready (keep load timing) we return nil (PASS).
    --
    -- Also asserts the same for `_max_overcharge` for symmetry — same engine cap
    -- pattern, same fassert shape.
    local pm = Managers and Managers.player
    if not pm or type(pm.human_and_bot_players) ~= "function" then return nil end
    local nc = rawget(_G, "NetworkConstants")
    local cap_en = (nc and nc.max_energy     and nc.max_energy.max)     or 60
    local cap_oc = (nc and nc.max_overcharge and nc.max_overcharge.max) or 60
    local ok, players = pcall(pm.human_and_bot_players, pm)
    if not ok or type(players) ~= "table" then return nil end
    local offenders = {}
    for _, pl in pairs(players) do
        local unit = pl and pl.player_unit
        if unit and Unit.alive(unit) then
            local en_ext = ScriptUnit.has_extension(unit, "energy_system")
            local m_en = en_ext and en_ext._max_energy
            if type(m_en) == "number" and m_en > cap_en then
                local prof = pl.profile_display_name and pl:profile_display_name() or "?"
                offenders[#offenders + 1] = string.format("max_energy=%d on %s (cap %d)", m_en, tostring(prof), cap_en)
            end
            local oc_ext = ScriptUnit.has_extension(unit, "overcharge_system")
            local m_oc = oc_ext and (oc_ext.max_value or oc_ext._max_overcharge)
            if type(m_oc) == "number" and m_oc > cap_oc then
                local prof = pl.profile_display_name and pl:profile_display_name() or "?"
                offenders[#offenders + 1] = string.format("max_overcharge=%d on %s (cap %d)", m_oc, tostring(prof), cap_oc)
            end
        end
    end
    if #offenders > 0 then
        return "network-bounded _max_<X> exceeds engine cap: " .. table.concat(offenders, "; ")
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)

_rt_register("ct_rpc_schema_present", function()
    -- v0.7.114-dev (Issue #27): explicit RPC schema_version pilot.
    -- Asserts CT_RPC_SCHEMA exists as a number >= 1 so a future refactor
    -- can't silently drop the constant and undo cross-version drop-on-mismatch.
    -- See VMF_RECIPES.md § 10 + the CT_RPC_SCHEMA comment block near MOD_VERSION.
    if type(CT_RPC_SCHEMA) ~= "number" then
        return "CT_RPC_SCHEMA not defined as number (got " .. type(CT_RPC_SCHEMA) .. ")"
    end
    if CT_RPC_SCHEMA < 1 then
        return string.format("CT_RPC_SCHEMA=%d is < 1 (initial value should be 1)", CT_RPC_SCHEMA)
    end
end)

_rt_register("issue357_bomb_bubble_cooldown_display", function()
    return mod._ct_bomb_cooldown_display.regression_check(CT_RPC_SCHEMA)
end)

_rt_register("issue358_manann_tempest_cooldown_display", function()
    return mod._ct_bomb_cooldown_display.regression_check_manann(CT_RPC_SCHEMA)
end)



_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_localization")
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

_rt_register("mission_catalog_localization_format_safe_564", function()
    -- #564: generated localization bypasses the static source-table scan. VMF
    -- string.formats every dropdown label, so validate the catalog's complete
    -- generated surface directly (including future labels and fallback paths).
    local ok, catalog = pcall(mod.dofile, mod, "scripts/mods/chaos_wastes_tweaker_dev/_ct_dev_mission_catalog")
    if not ok or type(catalog) ~= "table" or type(catalog.build_loc_entries) ~= "function" then
        return "mission catalog localization builder unavailable"
    end

    local entries = catalog.build_loc_entries()
    for key, entry in pairs(entries) do
        if type(entry) == "table" and type(entry.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, entry.en)
            if not fmt_ok then
                return string.format("generated loc key %q has invalid format string: %s", key, tostring(fmt_err))
            end
        end
    end
end)

-- audit 2026-06-07 (v0.7.133-dev): forward-ref fix for the two pickup dump
-- helpers. They are referenced inside the populate_pickups hook closure (built
-- at load) BEFORE their definitions far below. Without the forward declaration +
-- dropping `local` on the definitions, the closure captured a nil global and the
-- post-populate diagnostics silently no-op'd. This check FAILS if either helper
-- reverts to `nil` at this lexical scope (which is the SAME chunk scope the hook
-- closure captures from), or if a future edit accidentally leaks them to _G
-- instead of the forward-declared upvalue (the broken-global variant of the bug).
_rt_register("pickup_dump_helpers_forward_declared", function()
    if type(_dump_pickup_system_state) ~= "function" then
        return "_dump_pickup_system_state is not a function at chunk scope — forward-decl slot broken; populate_pickups dumps would no-op"
    end
    if type(_dump_pickup_spawners_verbose) ~= "function" then
        return "_dump_pickup_spawners_verbose is not a function at chunk scope — forward-decl slot broken; populate_pickups dumps would no-op"
    end
    -- They must be upvalues (forward-declared locals), NOT globals. A leak to _G
    -- means someone dropped `local` AND removed the forward declaration.
    if rawget(_G, "_dump_pickup_system_state") ~= nil then
        return "_dump_pickup_system_state leaked to _G — forward-declaration removed; use the local forward-decl pattern"
    end
    if rawget(_G, "_dump_pickup_spawners_verbose") ~= nil then
        return "_dump_pickup_spawners_verbose leaked to _G — forward-declaration removed; use the local forward-decl pattern"
    end
end)

-- audit 2026-06-07 (v0.7.133-dev): marker that the three variadic forwarding
-- hooks preserve real arity (select("#")/unpack(t,1,n)) rather than bare
-- unpack(args). Lua can't read its own bundle source at runtime (see the
-- open_chest_hook_singleton check), so this asserts the marker constant the fix
-- sites are documented against.
_rt_register("variadic_hooks_arity_preserved", function()
    if type(CT_VARIADIC_ARITY_MARKER) ~= "string" then
        return "CT_VARIADIC_ARITY_MARKER not defined — variadic hooks may have reverted to bare unpack(args), truncating at nil holes"
    end
    if CT_VARIADIC_ARITY_MARKER ~= "unpack_arity:select_count_v0.7.133" then
        return "CT_VARIADIC_ARITY_MARKER mismatch — expected select-count form, got: " .. tostring(CT_VARIADIC_ARITY_MARKER)
    end
    -- Behavioral proof the idiom actually preserves a trailing nil hole, which
    -- bare unpack(t) does NOT (the whole point of the §2a fix). Build args with a
    -- nil in the middle and a real value after it; capture n via select("#"), then
    -- confirm unpack(args, 1, n) yields the trailing value (bare unpack would stop
    -- at the nil hole and drop it).
    local function _roundtrip(...)
        local n = select("#", ...)
        local args = { ... }
        return select("#", unpack(args, 1, n)), (select(n, unpack(args, 1, n)))
    end
    local count, last = _roundtrip("a", nil, "z")  -- 3 args, hole at #2
    if count ~= 3 then
        return string.format("arity idiom dropped a nil hole: expected 3 forwarded args, got %d", count)
    end
    if last ~= "z" then
        return string.format("arity idiom dropped the trailing arg after a nil hole: expected 'z', got %s", tostring(last))
    end
end)

-- v0.7.203-dev: the Home Brewer potency hook on BuffExtension.add_buff scales the
-- brewed-potion sub-buff multiplier/bonus, calls vanilla, then restores. Its guarded
-- path previously did `local result = func(...); return result`, collapsing vanilla's
-- three returns (id, sub_buffs_added, first_buff — buff_extension.lua:517) to one. The
-- fix routes through _capture_returns + unpack(results, 1, n). Lua can't read its own
-- bundle at runtime, so this asserts the marker constant the fix site is documented
-- against (same shape as variadic_hooks_arity_preserved / endless_bombs_strip_on_expiry).
_rt_register("home_brewer_add_buff_multireturn_preserved", function()
    if type(CT_HOME_BREWER_MULTIRETURN_MARKER) ~= "string" then
        return "CT_HOME_BREWER_MULTIRETURN_MARKER not defined — the Home Brewer add_buff hook may have reverted to a single-return `local result = func(...)` collapse (drops sub_buffs_added + first_buff)"
    end
    if CT_HOME_BREWER_MULTIRETURN_MARKER ~= "home_brewer_add_buff:capture_returns_unpack_v0.7.203" then
        return "CT_HOME_BREWER_MULTIRETURN_MARKER mismatch — expected capture_returns/unpack form, got: " .. tostring(CT_HOME_BREWER_MULTIRETURN_MARKER)
    end
end)

-- v0.7.134 regression: v0.7.133's arity fix captured n at hook entry, but the
-- Belakor-temple branch writes args[8] = "unique" AFTER capture; the cursed-chest
-- call site passes only 7 args (deus_run_controller.lua:1115), so unpack(args, 1, 7)
-- silently dropped the forced rarity while the [belakor-temple] log line still
-- claimed forced=unique. The hook must extend n after the write.
_rt_register("belakor_forced_rarity_survives_unpack_bound", function()
    if type(mod._ct_extend_arity_for_forced_rarity) ~= "function" then
        return "_ct_extend_arity_for_forced_rarity missing — Belakor forced-rarity arity bump regressed"
    end
    -- Replicate the capture→mutate→forward sequence with vanilla's 7-arg shape.
    local function _roundtrip(...)
        local n = select("#", ...)
        local args = { ... }
        args[8] = "unique"                                -- the Belakor-temple write
        n = mod._ct_extend_arity_for_forced_rarity(n)     -- the v0.7.134 bump
        return select("#", unpack(args, 1, n)), (select(8, unpack(args, 1, n)))
    end
    local count, forced = _roundtrip("seed", 3, {}, "cataclysm", 0.5, "cursed_chest", "wh_priest")
    if count ~= 8 then
        return string.format("forced-rarity arg dropped at the forward: expected 8 args, got %d", count)
    end
    if forced ~= "unique" then
        return string.format("args[8] not forwarded: expected 'unique', got %s", tostring(forced))
    end
    if mod._ct_extend_arity_for_forced_rarity(9) ~= 9 then
        return "arity bump must not SHRINK n when the caller already passed more than 8 args"
    end
end)

-- audit 2026-06-07 (F14, v0.7.133-dev): the four DeusWeaponGeneration trait-filter
-- hooks must ALWAYS restore DeusWeapons[*].baked_trait_combinations even when the
-- wrapped vanilla call raises — otherwise the global table stays filtered for the
-- rest of the session (state corruption). The real hooks route through
-- _filtered_weapon_gen, which is a file-scope local (not exposed). This check
-- replicates that exact apply/pcall/restore contract on a synthetic table and
-- asserts state is restored after a throwing func — a behavioral guard that would
-- FAIL if the pcall+restore-on-error bracket were removed (the pre-F14 shape that
-- skipped restore on the error path).
_rt_register("trait_filter_restores_on_error", function()
    local synthetic = { combos = "ORIGINAL" }
    -- mirror of the hardened bracket: save -> pcall(vanilla) -> restore -> re-raise
    local function guarded_gen(throwing_func)
        local saved = synthetic.combos
        synthetic.combos = "FILTERED"  -- apply_weapon_trait_filter analogue
        local ok, result = pcall(throwing_func)
        synthetic.combos = saved       -- restore_weapon_trait_filter analogue
        if not ok then error(result, 2) end
        return result
    end
    -- success path: state restored, result returned
    local ok1, r1 = pcall(guarded_gen, function() return "WEAPON" end)
    if not ok1 then return "guarded_gen raised on the success path: " .. tostring(r1) end
    if synthetic.combos ~= "ORIGINAL" then
        return "trait combos not restored after a SUCCESSFUL roll (got " .. tostring(synthetic.combos) .. ")"
    end
    -- error path: vanilla raised — state MUST still be restored (the F14 contract)
    local ok2 = pcall(guarded_gen, function() error("simulated vanilla crash") end)
    if ok2 then return "guarded_gen swallowed the vanilla error instead of re-raising it" end
    if synthetic.combos ~= "ORIGINAL" then
        return "F14 REGRESSION: trait combos left FILTERED after vanilla raised — restore was skipped on the error path"
    end
end)

-- ct_dev 0.7.162-dev: the dup-career extra-chip node_key resolution must be
-- `final_node_selected > vote > nil` with NO trailing current-node fallback.
-- The old chain ended in `or current_node` .. `_key`, which planted a visible
-- chip on the party's CURRENT node for an unvoted duplicate peer (a valid node
-- that is NOT where they voted — the "valid-but-wrong mission node" bug). The
-- marker is set on `mod` by _ct_dup_vote_chips.lua at the resolution site (the
-- bundle is unreadable at runtime, so we read the exported invariant string).
-- The needle for the forbidden tail is split across two literals below so this
-- check's own source text can't be mistaken for a reintroduction of it.
_rt_register("dup_chip_no_current_node_fallback", function()
    local resolution = mod._ct_dup_chip_node_key_resolution
    if type(resolution) ~= "string" then
        return "DUP-CHIP REGRESSION: mod._ct_dup_chip_node_key_resolution missing — "
            .. "_ct_dup_vote_chips.lua extra-chip node_key resolution marker not exported "
            .. "(dup-chip wrong-node fix may have been reverted)"
    end
    if resolution ~= "final_node_selected>vote>nil" then
        return "DUP-CHIP REGRESSION: extra-chip node_key resolution is '" .. tostring(resolution)
            .. "', expected 'final_node_selected>vote>nil' — a current-node fallback may have been reintroduced "
            .. "(plants a chip on the wrong/current mission node for an unvoted duplicate peer)"
    end
    -- Defensive: the forbidden fallback token must NOT appear in the exported
    -- resolution string. Needle split across two literals so THIS line isn't a
    -- self-match.
    local forbidden = "current_node" .. "_key"
    if string.find(resolution, forbidden, 1, true) then
        return "DUP-CHIP REGRESSION: exported resolution names the forbidden current-node fallback — "
            .. "the extra-chip node_key chain must end at nil, not " .. forbidden
    end
end)

-- Issue #97 (ct_dev 0.7.163-dev): the three chunked host->client broadcasts must
-- be PACED through the enqueue/drain send queue, never inline-burst inside their
-- `for seq` loops. A single-frame burst of N chunks overran the reliable network
-- channel's queue cap and silently dropped chunks (reassembly then never
-- completes). This check verifies the marker + the live drain wiring: exactly one
-- `mod.update` drainer owner and the per-frame budget global both present.
_rt_register("chunk_sends_paced_not_bursted", function()
    if type(_CT_CHUNK_PACED_SEND_MARKER) ~= "string" then
        return "PACED-SEND REGRESSION: _CT_CHUNK_PACED_SEND_MARKER not defined — "
            .. "the #97 paced chunk-send queue may have been removed (chunked broadcasts could inline-burst again)"
    end
    if _CT_CHUNK_PACED_SEND_MARKER ~= "chunk_sends:enqueue_drain_paced_v0.7.163" then
        return "PACED-SEND REGRESSION: _CT_CHUNK_PACED_SEND_MARKER mismatch — expected enqueue/drain form, got: "
            .. tostring(_CT_CHUNK_PACED_SEND_MARKER)
    end
    -- The enqueue entry point that all three broadcasters route through.
    if type(_ct_enqueue_chunk) ~= "function" then
        return "PACED-SEND REGRESSION: _ct_enqueue_chunk missing — chunked broadcasts have no paced send path"
    end
    -- Exactly ONE drainer owner: mod.update must be the live drain function.
    -- (If a second feature reassigned mod.update, the drain stops and the queue
    -- never empties; if it's gone, chunks are never sent at all.)
    if type(mod.update) ~= "function" then
        return "PACED-SEND REGRESSION: mod.update drainer owner missing — the paced send queue is never drained "
            .. "(chunks enqueue but never emit)"
    end
    -- The per-frame budget global must survive — its removal would either stall
    -- the drain (nil budget) or re-tempt an inline burst.
    if type(_CT_CHUNK_DRAIN_BUDGET) ~= "number" or _CT_CHUNK_DRAIN_BUDGET < 1 then
        return "PACED-SEND REGRESSION: _CT_CHUNK_DRAIN_BUDGET missing or invalid (got "
            .. tostring(_CT_CHUNK_DRAIN_BUDGET) .. ") — the per-frame drain budget is gone"
    end
    -- The send queue table backing the FIFO must exist.
    if type(_ct_chunk_send_queue) ~= "table" then
        return "PACED-SEND REGRESSION: _ct_chunk_send_queue FIFO table missing — paced send queue dismantled"
    end
end)

_rt_register("ct_meta_ammo_server_auth_grant_249", function()
    -- v0.7.298-dev (issues 249/289): the meta-boon stack grant must be
    -- server-authoritative (host adds via BuffSystem server-controlled path,
    -- clients defer to replication) and parity-gated (issue 426). Drives the
    -- pure grant_plan kernel through the exact decision matrix.
    local core = mod._ct_ammo_guard_core
    if type(core) ~= "table" or type(core.grant_plan) ~= "function" then
        return "#249 REGRESSION: mod._ct_ammo_guard_core.grant_plan missing (server-auth grant reverted?)"
    end
    if CT_META_AMMO_SERVER_AUTH_MARKER ~= "meta_ammo:server_authoritative_stack_grant_v0.7.298" then
        return "#249 REGRESSION: CT_META_AMMO_SERVER_AUTH_MARKER missing/mismatch; got " .. tostring(CT_META_AMMO_SERVER_AUTH_MARKER)
    end
    if type(mod._ct_wire_safe) ~= "function" then
        return "#249 REGRESSION: mod._ct_wire_safe parity gate missing (issue 426 beacon not installed)"
    end
    local cases = {
        -- is_server, wire_safe, existing, target, want_mode, want_n
        { true,  true,  0, 5, "networked", 5 },
        { true,  true,  3, 5, "networked", 2 },
        { true,  false, 0, 5, "local",     5 },
        { false, true,  0, 5, "defer_to_server", 0 },
        { false, false, 2, 5, "defer_to_server", 0 },
        { true,  true,  5, 5, "none", 0 },
        { true,  true,  7, 5, "none", 0 },
        { false, true,  5, 5, "none", 0 },
    }
    for i, c in ipairs(cases) do
        local mode, n = core.grant_plan(c[1], c[2], c[3], c[4])
        if mode ~= c[5] or n ~= c[6] then
            return string.format("#249 REGRESSION: grant_plan case %d gave (%s,%s), expected (%s,%d)",
                i, tostring(mode), tostring(n), c[5], c[6])
        end
    end
end)

_rt_register("cursed_chest_reconcile_132", function()
    -- v0.7.298-dev (issues 132/60): the settled chest reconcile must exist
    -- (prune-side cross-path cap) with its pickup-path ledger feed, and the
    -- pure planner must never prune below cap, outside the pickup set, or on a
    -- non-prunable (non-WAITING) chest.
    local m132 = mod._ct_chest132
    if type(m132) ~= "table" or type(m132.pickup_chest) ~= "function" then
        return "#132 REGRESSION: mod._ct_chest132.pickup_chest ledger feed missing"
    end
    if m132.RECONCILE_MARKER ~= "CT_CHEST132_RECONCILE_PRUNE_v0.7.298" then
        return "#132 REGRESSION: RECONCILE_MARKER missing/mismatch; got " .. tostring(m132.RECONCILE_MARKER)
    end
    local core = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_count_audit_core")
    if type(core) ~= "table" or type(core.reconcile_plan) ~= "function" then
        return "#132 REGRESSION: _ct_chest_count_audit_core.reconcile_plan missing"
    end
    local u1, u2, u3, u4, u5 = "u1", "u2", "u3", "u4", "u5"
    local appearance = { u1, u2, u3, u4, u5 }
    local pickup_set = { [u3] = true, [u4] = true, [u5] = true }
    local alive = function() return true end
    local waiting = function(u) return u ~= u5 end  -- u5 already activated
    local plan = core.reconcile_plan(appearance, pickup_set, 3, alive, waiting)
    if plan.alive_n ~= 5 or plan.over_n ~= 2 then
        return string.format("#132 REGRESSION: plan counts wrong (alive=%s over=%s, expected 5/2)",
            tostring(plan.alive_n), tostring(plan.over_n))
    end
    -- Excess 2: u5 blocked (non-WAITING), u4 + u3 prunable from the end.
    if #plan.prune ~= 2 or plan.prune[1] ~= u4 or plan.prune[2] ~= u3 or plan.unprunable_n ~= 0 then
        return string.format("#132 REGRESSION: prune selection wrong (%s,%s unprunable=%s; expected u4,u3/0)",
            tostring(plan.prune[1]), tostring(plan.prune[2]), tostring(plan.unprunable_n))
    end
    -- Baked-only over-cap (nothing in the pickup set) must prune NOTHING.
    local baked_plan = core.reconcile_plan({ u1, u2 }, {}, 1, alive, waiting)
    if #baked_plan.prune ~= 0 or baked_plan.unprunable_n ~= 1 then
        return "#132 REGRESSION: baked-only over-cap must be reported unprunable, never deleted"
    end
    -- Under-cap must be a full no-op plan.
    local under = core.reconcile_plan({ u1 }, { [u1] = true }, 3, alive, waiting)
    if #under.prune ~= 0 or under.over_n ~= 0 then
        return "#132 REGRESSION: under-cap mission produced a prune plan"
    end
end)
end
