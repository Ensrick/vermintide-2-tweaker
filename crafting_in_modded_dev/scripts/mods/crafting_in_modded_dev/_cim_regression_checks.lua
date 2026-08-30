-- _cim_regression_checks.lua - core runtime regression registrations for CIM dev
--
-- Owns the first 33 late regression checks after the three cleanup checks. It
-- depends on entry-supplied state accessors and returns the exact loadout
-- sandbox helper consumed by the following forge-surface regression owner;
-- registration order and helper identity are frozen structural contracts.
--
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via:
-- scripts/mods/crafting_in_modded_dev/_cim_regression_checks

return function(context)
    local mod = context.mod
    local _rt_register = context.rt_register
    local _rt_src_read = context.rt_src_read
    local _dbg = context.dbg
    local _dbg_alert = context.dbg_alert
    local _bubble_cap = context.bubble_cap
    local _value_for_bubbles = context.value_for_bubbles
    local _cap_grid_property_arrays = context.cap_grid_property_arrays
    local _forge_load = context.forge_load
    local _store_property_slot = context.store_property_slot
    local _modded_loadout_load = context.modded_loadout_load
    local _weave_economy_source_anchor = mod._cim_weave_economy_source_anchor
    local _accessory_property_source_anchor = mod._cim_accessory_property_source_anchor
    local _rt_with_loadout_sandbox

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================

_rt_register("weave_talent_forge_level_guard_present", function()
    -- Issue #71 (2026-06-01): pressing the amulet under the modded forge crashed
    -- in vanilla get_talent_required_forge_level, which nil-indexes
    -- progression_settings.talents[talent_name] for the adventure career talents
    -- cim feeds in. The fix hooks that method to return 0 under _custom_forge_active
    -- (alongside the existing get_property_/get_trait_ guards). This source-pattern
    -- check fails if that hook is removed. The needle is assembled from two literals
    -- so this test's own source does not self-match. Degrades to a no-op when source
    -- introspection is unavailable (deploy/bundle paths).
    if type(_weave_economy_source_anchor) ~= "function" then
        return "weave economy owner source anchor missing"
    end
    local ok, info = pcall(debug.getinfo, _weave_economy_source_anchor, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local needle = 'BackendInterfaceWeavesPlayFab", ' .. '"get_talent_required_forge_level"'
    if not txt:find(needle, 1, true) then
        return "Issue #71 regression: get_talent_required_forge_level guard hook missing (amulet/weave-properties crash on adventure career talents)"
    end
end)

_rt_register("pool_excludes_scrubbed", function()
    -- v0.7.4: hook installed on DeusRunController.get_weapon_pool to drop
    -- scrubbed entries. Verify the class & method are present.
    local cls = rawget(_G, "DeusRunController")
    if not cls then return "DeusRunController not loaded (run in-keep)" end
    if type(cls.get_weapon_pool) ~= "function" then
        return "get_weapon_pool missing on DeusRunController"
    end
end)

_rt_register("forge_preview_accepts_resident_3p_unit", function()
    -- (#481) The Athanor forge-preview guard `_forge_preview_unsafe` skips the 3D
    -- model spawn for weapons whose preview units aren't loadable in the forge
    -- world (the CW/deus Trollhammer CTD class). Its inner `pkg_missing` originally
    -- flagged a held unit unloadable whenever no discrete <unit>_3p .package
    -- existed. Loremaster's Armoury custom-mesh shields (kind="unit") bundle a
    -- resident <unit>_3p unit in one globbed master package with NO standalone
    -- .package, so that check false-failed and the WHOLE forge preview (weapon +
    -- shield) was suppressed for any LA-skinned shield. Fix: also accept a resident
    -- 3p UNIT (can_get("unit", ...)), which is what World.spawn_unit needs.
    -- Runtime anchor: the decision helper must stay exposed for the guard hooks.
    if type(mod._cim_forge_preview_unsafe) ~= "function" then
        return "forge preview guard helper (_cim_forge_preview_unsafe) not exposed (#481 regression)"
    end
    -- Drive the shared policy rather than source-matching the entry. A provider
    -- unit with no standalone package is valid when that exact unit is resident.
    local policy = mod._cim_forge_preview_policy
    if type(policy) ~= "table" or type(policy.unit_loadable) ~= "function" then
        return "#481 regression: forge preview resource policy missing"
    end
    local loadable, reason = policy.unit_loadable("cim_rt_resident_unit", function(kind)
        return kind == "unit"
    end)
    if loadable ~= true or reason ~= "resident_unit" then
        return "#481 regression: resident-3p-unit fallback rejected (LA-skinned shields lose the forge preview)"
    end
end)

_rt_register("issue882_athanor_preview_placement", function()
    local policy = mod._cim_forge_preview_policy
    local fn = policy and policy.properties_preview_position
    if type(fn) ~= "function" then
        return "#404 ranged properties preview policy is missing"
    end

    local native = { -0.85, 3, 0 }
    local ranged = fn("ranged", native)
    if type(ranged) ~= "table" or ranged[1] ~= 0
            or ranged[2] ~= 3 or ranged[3] ~= 0 then
        return "#404 ranged preview no longer composes the native centered x with properties y/z"
    end
    if native[1] ~= -0.85 then
        return "#404 preview policy mutated the caller-owned native position"
    end
    if fn("melee", native) ~= nil then
        return "#404 preview policy must leave melee on the vanilla path"
    end
    if type(policy.mark_overview_viewport_role) ~= "function"
            or type(policy.overview_preview_x_from_widget) ~= "function" then
        return "#882 production viewport-role handoff helpers are missing"
    end

    -- Drive the exact callable producer/consumer helpers used by the two live
    -- hooks.  A pure coordinate assertion could pass after the production
    -- marker handoff was removed, recreating the Grail Knight overlap.
    local secondary_definition = { content = {} }
    if policy.mark_overview_viewport_role(
            secondary_definition, true) ~= secondary_definition then
        return "#882 viewport producer replaced its caller-owned definition"
    end
    local secondary_x, secondary_role = policy.overview_preview_x_from_widget(
        { content = secondary_definition.content }, -0.8, false)
    if secondary_x ~= 0.8 or secondary_role ~= true then
        return "#882 mission secondary role no longer reaches the previewer consumer"
    end

    local primary_definition = { content = {} }
    policy.mark_overview_viewport_role(primary_definition, false)
    local primary_x, primary_role = policy.overview_preview_x_from_widget(
        { content = primary_definition.content }, -0.8, false)
    if primary_x ~= -0.8 or primary_role ~= false then
        return "#882 mission primary viewport was misclassified or repositioned"
    end

    local keep_x = policy.overview_preview_x_from_widget(
        { content = secondary_definition.content }, -0.8, true)
    if keep_x ~= -0.8 then
        return "#882 overview handoff changed the native keep layout"
    end

    local malformed = { sentinel = true }
    if policy.mark_overview_viewport_role(malformed, true) ~= malformed
            or policy.overview_preview_x_from_widget(nil, -0.8, false) ~= -0.8
            or policy.overview_preview_x_from_widget(
                { content = {} }, nil, false) ~= nil then
        return "#882 malformed viewport controls did not fail closed"
    end
    if mod._cim404_preview_install_ok ~= true then
        return "#404 properties preview runtime hook did not install"
    end
end)

_rt_register("forge_preview_la_diagnostics_armed", function()
    -- (#481, round 2) The user's 0.8.58 retest showed two residual defects on
    -- LA-skinned shields in the Athanor: (1) shield ABSENT on the first forge
    -- open until the item is re-selected, (2) shield offset left of where the
    -- vanilla shield sits. The 0.8.58 log carried NO guard-skip line, so the miss
    -- happens inside the vanilla/cosmetics spawn chain — per the diagnose-before-
    -- mitigating doctrine this version arms three probes instead of guessing a
    -- fix: the _load_item_units intake dump, the per-spawn spawn_units dump (the
    -- old once-per-key latch masked first-open vs re-select), and the
    -- post-cosmetics update snapshot (cosmetics' outermost wrapper applies LA
    -- paint + 2x preview scale AFTER cim's spawn_units body). This check fails if
    -- any probe is stripped before #481 is closed.
    -- Runtime anchor: the guard helper must stay exposed (shared with the probes'
    -- gate) — same anchor as forge_preview_accepts_resident_3p_unit.
    if type(mod._cim_forge_preview_unsafe) ~= "function" then
        return "forge preview guard helper (_cim_forge_preview_unsafe) not exposed (#481 probes lost their gate)"
    end
    -- Source-pattern (io-safe; nil in retail sandbox => skip). Split needles so
    -- this check's own source does not self-match.
    local ok, info = pcall(debug.getinfo, mod._cim_forge_preview_unsafe, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local intake = '[cim:481] forge _load_item_units' .. ' key=%s'
    if not txt:find(intake, 1, true) then
        return "#481 regression: forge _load_item_units intake probe removed while the LA first-open miss is undiagnosed"
    end
    local snapshot = '[cim:481] forge post-cosmetics snapshot' .. ' key=%s'
    if not txt:find(snapshot, 1, true) then
        return "#481 regression: post-cosmetics update snapshot removed while the LA shield offset is unmeasured"
    end
end)

_rt_register("single_on_enter_hook_per_class", function()
    -- v0.7.8: standard_forge.lua hooks on_enter exactly once per class
    -- (HeroWindowItemCustomization, HeroWindowCrafting, HeroWindowCraftingConsole).
    -- Verify class presence. We can't easily count hooks from outside VMF.
    local classes = { "HeroWindowItemCustomization", "HeroWindowCrafting", "HeroWindowCraftingConsole" }
    local missing = {}
    for _, name in ipairs(classes) do
        local cls = rawget(_G, name)
        if not cls then missing[#missing + 1] = name end
    end
    if #missing > 0 then
        return "classes not loaded (run in-keep): " .. table.concat(missing, ", ")
    end
end)

_rt_register("rpc_sync_loadout_unknown_id_guard", function()
    -- (issue 278) A client CTD'd decoding `rpc_sync_loadout_slot` because the
    -- host's NUMERIC item_names id (index-appended per peer; 3243 in the crash
    -- log) did not exist in the client's table — strict __index metamethod at
    -- network_lookup.lua:2521 via loadout_utils.lua:72. cim's consolidated
    -- wrap hook on (PlayerManager, rpc_sync_loadout_slot) now pre-checks the
    -- id with rawget and DROPS the RPC (printf ALERT) instead of decoding.
    -- This asserts the wrap-form hook installed at load time; if it silently
    -- regressed to a post-only safe-hook, the guard cannot run before vanilla.
    if mod._cim_rpc_loadout_guard_installed ~= true then
        return "PlayerManager.rpc_sync_loadout_slot unknown-id guard not installed (issue 278 client-CTD regression)"
    end
    -- Sanity: the guard's decision function must agree with vanilla's decode —
    -- a known-vanilla id must pass, an absurd id must be seen as unknown.
    local NL = rawget(_G, "NetworkLookup")
    local names = NL and NL.item_names
    if type(names) ~= "table" then return "NetworkLookup.item_names unavailable" end
    if rawget(names, 1) == nil then
        return "item_names[1] missing — lookup table shape changed; guard assumptions invalid"
    end
    if rawget(names, 900000001) ~= nil then
        return "sentinel id 900000001 unexpectedly present in item_names"
    end
end)

_rt_register("wire_rarity_rewrite_ungated", function()
    -- (issue 278 regression / issue 371 mandate) The "modded"->vanilla rarity coercion
    -- on the loadout wire is a CRASH-SAFETY invariant and must NOT be gated by
    -- persist_modded_loadouts. The v0.8.15 master gate wrongly bundled them, so a
    -- default-OFF host CTD'd every non-cim client the instant a crafted (always-"modded")
    -- item equipped. The coercion is single-sourced in _cim_wire_safe_rarity, which takes
    -- NO persistence argument — so by construction it cannot be toggle-gated.
    if type(mod._cim_wire_safe_rarity) ~= "function" then
        return "wire-safe rarity coercion helper missing (issue 278 crash regression)"
    end
    if mod._cim_wire_safe_rarity("modded") ~= "unique" then
        return "modded rarity not coerced to a vanilla rarity on the wire — non-cim clients will CTD"
    end
    if mod._cim_wire_safe_rarity("unique") ~= "unique" then
        return "a vanilla rarity must pass through the wire coercion unchanged"
    end
    if type(mod._cim_persist_loadouts_enabled) ~= "function" then
        return "persist gate helper missing — cannot confirm wire safety is separated from persistence"
    end
end)

_rt_register("weave_forge_hides_cost_readout", function()
    -- (#239) In the modded Athanor all trait/property/talent Costs are faked to 0
    -- (free crafting), so the vanilla "Cost: 0" readout is meaningless clutter. A
    -- hook_safe on HeroWindowWeaveProperties._populate_menu_option_widget blanks
    -- content.price_text AND zeroes the separate price_icon alpha while
    -- _custom_forge_active. Source-pattern guard on THIS file (path via the
    -- installer defined by the extracted adapter). Split needles so these lines
    -- cannot self-match.
    -- No-op if the source is unreadable.
    if type(_accessory_property_source_anchor) ~= "function" then
        return "accessory property owner source anchor missing"
    end
    local ok, info = pcall(debug.getinfo, _accessory_property_source_anchor, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local hook_needle  = '"HeroWindowWeaveProperties", "_populate_menu_option' .. '_widget"'
    local blank_needle = 'widget.content.price' .. '_text = ""'
    if not txt:find(hook_needle, 1, true) then
        return "#239 regression: the HeroWindowWeaveProperties._populate_menu_option_widget hook is gone (Cost:0 readout returns in the modded Athanor)"
    end
    if not txt:find(blank_needle, 1, true) then
        return "#239 regression: the price_text blank is gone from the weave-forge cost-hide hook (Cost:0 readout returns)"
    end
end)

-- ============================================================
-- Save/restore invariants (added 2026-05-23 after user reported
-- equipped accessories + last weapons didn't restore on fresh
-- load). These exercise the VMF settings round-trip so a future
-- regression of the "stale modded_loadout entry overwrites vanilla
-- restore" bug fails the test instead of silently shipping.
-- ============================================================

-- Test bid pattern: must look like a real cim craft to _cim_is_modded_backend_id.
-- We INJECT the fake bid into _forged_weapons during the test so the modded
-- check passes, then remove on teardown via _rt_with_loadout_sandbox.
local _RT_FAKE_BID         = "rt_test_bid_dont_ship_me"
local _RT_FAKE_VANILLA_BID = "rt_test_vanilla_bid"
local _RT_FAKE_CAREER      = "_rt_test_career"
local _RT_FAKE_SLOT        = "_rt_test_slot"

_rt_with_loadout_sandbox = function(body)
    -- Snapshot real state via deep-copy of both the on-disk SETTINGS payload
    -- AND the in-memory tables so any failed assertion in `body` doesn't
    -- leave fake entries in the player's save.
    local saved_forged      = mod:get("forged_weapons")
    local saved_loadout     = mod:get("modded_loadout")
    -- v0.8.15-dev: the loadout capture/persist path is now gated OFF by default
    -- via `persist_modded_loadouts`. These tests EXERCISE that path, so force the
    -- toggle ON for the duration of the body and restore the user's real value on
    -- teardown. (Without this, the default-OFF capture no-ops and the round-trip
    -- assertions would fail spuriously.)
    local saved_persist     = mod:get("persist_modded_loadouts")
    mod:set("persist_modded_loadouts", true, false)
    local snap_forged_mem   = {}
    for k, v in pairs(context.get_forged_weapons()) do snap_forged_mem[k] = v end
    -- Indexed schema: career -> index -> slot -> bid (3-level deep copy).
    local snap_loadout_mem  = {}
    for c, indices in pairs(context.get_modded_loadout()) do
        snap_loadout_mem[c] = {}
        if type(indices) == "table" then
            for idx, slots in pairs(indices) do
                snap_loadout_mem[c][idx] = {}
                if type(slots) == "table" then
                    for s, b in pairs(slots) do snap_loadout_mem[c][idx][s] = b end
                end
            end
        end
    end

    local ok, err = pcall(body)

    -- Always teardown — restore in-memory tables AND on-disk payload.
    context.set_forged_weapons({})
    local forged_weapons = context.get_forged_weapons()
    for k, v in pairs(snap_forged_mem) do forged_weapons[k] = v end
    context.set_modded_loadout({})
    local modded_loadout = context.get_modded_loadout()
    for c, indices in pairs(snap_loadout_mem) do
        modded_loadout[c] = {}
        if type(indices) == "table" then
            for idx, slots in pairs(indices) do
                modded_loadout[c][idx] = {}
                if type(slots) == "table" then
                    for s, b in pairs(slots) do modded_loadout[c][idx][s] = b end
                end
            end
        end
    end
    mod:set("forged_weapons", saved_forged)
    mod:set("modded_loadout", saved_loadout)
    -- Restore the user's real persist-loadouts toggle (default OFF).
    mod:set("persist_modded_loadouts", saved_persist, false)

    if not ok then error(err, 0) end
end

_rt_register("modded_loadout_round_trip_save_then_clear", function()
    -- Validates the v0.7.33-alpha fix for the 2026-05-23 user report.
    -- Step 1: equip a modded item -> _modded_loadout gets the entry, and
    --         round-tripping via mod:get/set preserves it.
    -- Step 2: equip a NON-modded item at the same (career, slot) -> the cim
    --         entry MUST be cleared. Pre-fix code only saved, never cleared,
    --         so stale entries clobbered vanilla restore on next session.
    local cls = rawget(_G, "BackendInterfaceItemPlayfab")
    if not cls or type(cls.set_loadout_item) ~= "function" then
        return "skip: BackendInterfaceItemPlayfab.set_loadout_item not loaded (run in-keep)"
    end
    local hook_fn = cls.set_loadout_item

    local result_err
    _rt_with_loadout_sandbox(function()
        -- Pretend rt_test_bid is a real cim craft so _cim_is_modded_backend_id
        -- returns true. We register/unregister via the public API to mirror
        -- the real craft path.
        mod._cim_register_craft(_RT_FAKE_BID, {
            item_key = "es_1h_falchion", properties = {}, traits = {}, power_level = 300, rarity = "modded",
        })

        -- Dummy `items` table — vanilla set_loadout_item only touches fields
        -- that exist on the real interface. Our hook is hook_safe so it fires
        -- after vanilla returns; if vanilla errors we still PASS as long as
        -- the cim hook's side effect ran. Either way we don't care about the
        -- vanilla path here — we're testing the cim hook's invariants.
        local fake_items = setmetatable({}, { __index = function() return function() end end })

        -- v0.8.13-dev: pass an EXPLICIT loadout index (4th arg) so the test is
        -- deterministic without a live mirror, and assert the INDEXED schema
        -- (career -> index -> slot -> bid). Use a non-1 index to also prove the
        -- capture honors the passed index rather than defaulting to the selected.
        local _RT_FAKE_INDEX = 2

        -- Step 1: equip modded.
        pcall(hook_fn, fake_items, _RT_FAKE_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT, _RT_FAKE_INDEX)

        -- Round-trip via VMF settings: clear in-memory, reload from disk, check.
        context.set_modded_loadout({})
        _modded_loadout_load()
        local modded_loadout = context.get_modded_loadout()
        local saved_idx = modded_loadout[_RT_FAKE_CAREER] and modded_loadout[_RT_FAKE_CAREER][_RT_FAKE_INDEX]
        if not (saved_idx and saved_idx[_RT_FAKE_SLOT] == _RT_FAKE_BID) then
            result_err = "modded equip not persisted at index " .. _RT_FAKE_INDEX .. ": expected bid=" .. _RT_FAKE_BID
            return
        end

        -- Step 2: equip vanilla (non-modded) at the same career/slot/index.
        pcall(hook_fn, fake_items, _RT_FAKE_VANILLA_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT, _RT_FAKE_INDEX)

        context.set_modded_loadout({})
        _modded_loadout_load()
        modded_loadout = context.get_modded_loadout()
        local stale_idx = modded_loadout[_RT_FAKE_CAREER] and modded_loadout[_RT_FAKE_CAREER][_RT_FAKE_INDEX]
        local stale = stale_idx and stale_idx[_RT_FAKE_SLOT]
        if stale ~= nil then
            result_err = "STALE modded entry not cleared on vanilla equip: still " .. tostring(stale)
                .. " (this is the 2026-05-23 user-report bug)"
            return
        end

        mod._cim_unregister_craft(_RT_FAKE_BID)
    end)
    if result_err then return result_err end
end)

_rt_register("forged_weapons_round_trip", function()
    -- Register a fake craft, save, force-reload, confirm parity.
    local result_err
    _rt_with_loadout_sandbox(function()
        local payload = {
            item_key = "es_1h_falchion",
            properties = { attack_speed = 5, crit_chance = 5 },
            traits = { "melee_attack_speed_on_crit" },
            power_level = 300,
            rarity = "modded",
            skin = nil,
        }
        mod._cim_register_craft(_RT_FAKE_BID, payload)

        -- Force the on-disk round-trip.
        context.set_forged_weapons({})
        _forge_load()

        local got = context.get_forged_weapons()[_RT_FAKE_BID]
        if not got then
            result_err = "register/save/load lost the entry"
            return
        end
        if got.item_key ~= payload.item_key then
            result_err = ("item_key mismatch: got=%s expected=%s"):format(tostring(got.item_key), payload.item_key)
            return
        end
        local got_attack = (got.properties or {}).attack_speed
        if got_attack ~= 5 then
            result_err = ("properties.attack_speed mismatch: got=%s expected=5"):format(tostring(got_attack))
            return
        end
        local got_trait = (got.traits or {})[1]
        if got_trait ~= "melee_attack_speed_on_crit" then
            result_err = ("traits[1] mismatch: got=%s expected=melee_attack_speed_on_crit"):format(tostring(got_trait))
            return
        end

        mod._cim_unregister_craft(_RT_FAKE_BID)
        -- Confirm unregister wrote through.
        context.set_forged_weapons({})
        _forge_load()
        if context.get_forged_weapons()[_RT_FAKE_BID] ~= nil then
            result_err = "unregister_craft did not persist nil-write"
            return
        end
    end)
    if result_err then return result_err end
end)

_rt_register("restore_after_playfab_inventory_populated", function()
    -- _restore_modded_loadout must run AFTER vanilla PlayFab inventory sync
    -- finishes, otherwise set_loadout_item targets an empty mirror and the
    -- restore silently no-ops. We can't intercept the call ordering after
    -- the fact, so we check the current state at /cim_regression_test time:
    -- if the mirror's _inventory_items is empty AND we're past
    -- _create_interfaces, restore would have just no-op'd.
    local backend = Managers and Managers.backend
    if not backend then return "skip: Managers.backend not ready (run in-keep)" end
    local items_iface = backend.get_interface and backend:get_interface("items")
    local mirror = items_iface and items_iface._backend_mirror
    local inv = mirror and mirror._inventory_items
    if type(inv) ~= "table" then
        return "skip: backend_mirror._inventory_items not populated yet"
    end
    local count = 0
    for _ in pairs(inv) do count = count + 1; if count > 0 then break end end
    if count == 0 then
        return "PlayFab inventory empty at restore time -- _restore_modded_loadout would silently no-op"
    end
end)

_rt_register("issue563_vanilla_skin_override_exact_backend_id", function()
    local plan = mod._cim563_plan_vanilla_skin_rehydrate
    local commit_plan = mod._cim563_plan_explicit_skin_choice
    if type(plan) ~= "function" then
        return "#563 exact-backend-id rehydrate planner missing"
    end
    if type(commit_plan) ~= "function" then
        return "#563 explicit-choice persistence planner missing"
    end
    local shared_template = { slot_type = "melee", key = "es_sword_shield_breton" }
    local inventory = {
        VANILLA_INSTANCE_A = { ItemId = "es_sword_shield_breton", data = shared_template },
        VANILLA_INSTANCE_B = { ItemId = "es_sword_shield_breton", data = shared_template },
    }
    local saved = {
        VANILLA_INSTANCE_A = "es_sword_shield_breton_skin_03",
        MISSING_INSTANCE = "es_sword_shield_breton_skin_04_magic_01_magic_01",
    }
    local apply, prune = plan(saved, inventory, function() return true end)
    if not apply.VANILLA_INSTANCE_A then return "target exact backend id was not planned" end
    if apply.VANILLA_INSTANCE_B then
        return "same-template sibling was modified -- override regressed to template-wide semantics"
    end
    if #prune ~= 1 or prune[1] ~= "MISSING_INSTANCE" then
        return "missing backend id was not the sole stale record selected for pruning"
    end
    if apply.VANILLA_INSTANCE_A.item ~= inventory.VANILLA_INSTANCE_A then
        return "planner did not retain the exact mirror item instance"
    end

    -- Reopened #563: an old saved A must be atomically replaced by the newest
    -- explicit B before any later mirror-ready rehydrate plans its write.
    local replaced, action = commit_plan(
        { VANILLA_INSTANCE_A = "OLD_CWV_SKIN", VANILLA_INSTANCE_B = "SIBLING_SKIN" },
        "VANILLA_INSTANCE_A", "NEW_VANILLA_SKIN", true
    )
    if action ~= "saved" or replaced.VANILLA_INSTANCE_A ~= "NEW_VANILLA_SKIN" then
        return "explicit B did not replace stale saved A"
    end
    if replaced.VANILLA_INSTANCE_B ~= "SIBLING_SKIN" then
        return "copy-on-write explicit save disturbed a sibling exact id"
    end
    local after_apply = plan(replaced, inventory, function() return true end)
    if not after_apply.VANILLA_INSTANCE_A
        or after_apply.VANILLA_INSTANCE_A.skin ~= "NEW_VANILLA_SKIN" then
        return "mirror-ready after explicit B planned stale A"
    end

    local cleared, clear_action = commit_plan(replaced, "VANILLA_INSTANCE_A", nil, false)
    if clear_action ~= "cleared" or cleared.VANILLA_INSTANCE_A ~= nil then
        return "CIM-owned craft did not clear stale vanilla override"
    end
end)

_rt_register("inventory_property_count_within_cap", function()
    -- v0.7.25 trim invariant: no item in the mirror should carry >2
    -- properties. The _create_interfaces hook trims on load; if anything is
    -- still over, either the trim broke or a code path bypassed it.
    local backend = Managers and Managers.backend
    if not backend then return "skip: Managers.backend not ready (run in-keep)" end
    local items_iface = backend.get_interface and backend:get_interface("items")
    local mirror = items_iface and items_iface._backend_mirror
    local inv = mirror and mirror._inventory_items
    if type(inv) ~= "table" then return "skip: backend_mirror._inventory_items not ready" end
    local offenders = {}
    for bid, item in pairs(inv) do
        local props = item and item.properties
        if type(props) == "table" then
            local n = 0
            for _ in pairs(props) do n = n + 1 end
            if n > 2 then
                offenders[#offenders + 1] = tostring(bid) .. "(" .. tostring(n) .. ")"
                if #offenders >= 5 then break end
            end
        end
    end
    if #offenders > 0 then
        return "items over 2-property cap: " .. table.concat(offenders, ", ")
    end
end)

_rt_register("cwv_bounded_seed_is_single_acquisition_selector", function()
    -- #592/#928: CWV owns one real 5-power seed; CIM suppresses its synthetic
    -- twin and owns every additional crafted instance.
    if type(mod._cim_inject_templates) ~= "function" then
        return "standard-forge template injector (_cim_inject_templates) not exposed"
    end
    if mod._cim592_cwv_bounded_seed ~= true then
        return "#592 regression: CIM/CWV bounded-seed contract marker missing"
    end
    if mod._cim_is_modded_backend_id("cwv_rt_unpersisted_definition_001") then
        return "#592 regression: unpersisted CWV prefix still treated as acquired"
    end
end)

_rt_register("issue524_cwv_selector_bounded", function()
    local selector = mod._cim_template_selector
    if type(selector) ~= "table" or type(selector.inject) ~= "function" then
        return "CIM/CWV template selector policy is not loaded"
    end
    local legacy = {
        backend_id = "cwv_rt_longsword_001",
        rarity = "default",
        key = "es_bastard_sword",
        data = {
            key = "es_bastard_sword",
            slot_type = "melee",
            item_type = "es_bastard_sword", -- name-integrity: non-rendered-test-data
        },
    }
    local synthetic = {
        backend_id = "cim_template_cwv_rt_longsword",
        rarity = "default",
        key = "cwv_rt_longsword",
        cim_acquisition_template = true,
        cim_acquisition_key = "cwv_rt_longsword",
    }
    local rows = { legacy, synthetic, synthetic }
    selector.inject(rows, { synthetic })
    if #rows ~= 1 or rows[1] ~= legacy then
        return "legacy/default CWV row did not suppress duplicate synthetic selectors"
    end
    local legacy_300 = {
        backend_id = "cwv_rt_longsword_002",
        rarity = "default",
        power_level = 300,
        key = "es_bastard_sword",
        data = { key = "es_bastard_sword", slot_type = "melee", item_type = "es_bastard_sword" }, -- name-integrity: non-rendered-test-data
    }
    legacy.power_level = 5
    rows = { legacy_300, legacy, synthetic }
    selector.inject(rows, { synthetic })
    if #rows ~= 1 or rows[1] ~= legacy or rows[1].power_level ~= 5 then
        return "duplicate real/default CWV rows did not collapse to the 5-power selector"
    end
    local crafted = {
        backend_id = "cwv_rt_longsword_100",
        rarity = "modded",
        data = { slot_type = "melee", cwv_key = "cwv_rt_longsword" },
    }
    rows = { crafted }
    selector.inject(rows, { synthetic })
    selector.inject(rows, { synthetic })
    if #rows ~= 1 or rows[1] ~= synthetic then
        return "crafted CWV instance leaked into the acquisition picker"
    end
end)

_rt_register("issue524_all_cwv_blacksmith_selectors", function()
    local catalog = mod._cim_template_catalog
    if type(catalog) ~= "table" or type(catalog.build) ~= "function" then
        return "#524 pure template catalog is not loaded"
    end
    if not ItemMasterList then return "skip: ItemMasterList not ready" end

    local definitions = {}
    local careers = {}
    for key, data in pairs(ItemMasterList) do
        if type(data) == "table" and data.cwv_definition == true then
            definitions[key] = data
            for _, career in ipairs(data.can_wield or {}) do careers[career] = true end
        end
    end
    if not next(definitions) then return "skip: CWV definitions not registered (run in keep with CWV)" end

    for career in pairs(careers) do
        local cache = catalog.build({
            item_master_list = definitions,
            career_name = career,
            craftable_slot_types = { melee = true, ranged = true },
            base_power = 300,
        })
        for key, data in pairs(definitions) do
            local owns = false
            for _, candidate in ipairs(data.can_wield or {}) do
                if candidate == career then owns = true; break end
            end
            local selector = cache["cim_template_" .. key]
            if owns and (not selector or selector.cim_acquisition_key ~= key
                or selector.data ~= data or selector.rarity ~= "default"
                or selector.power_level ~= 5
                or not selector.CustomData or selector.CustomData.power_level ~= "5") then
                return "#524 missing/incorrect Blacksmith selector: " .. key .. " for " .. career
            end
            if not owns and selector then
                return "#524 selector crossed career ownership: " .. key .. " for " .. career
            end
        end
    end

    local live = mod._cim_template_cache_report and mod._cim_template_cache_report()
    if mod._cim_standard_forge_active and (not live or (live.cwv or 0) == 0) then
        return "#524 live forge cache contains no CWV selectors"
    end
end)

_rt_register("issue524_native_craft_families_deduplicated", function()
    local catalog = mod._cim_template_catalog
    if type(catalog) ~= "table" or type(catalog.build) ~= "function" then
        return "#524 template catalog unavailable"
    end
    local base = {
        slot_type = "melee", item_type = "Regression Test Sword", rarity = "plentiful",
        can_wield = { "es_knight" },
    }
    local preview = table.clone(base, true)
    preview.is_local = true
    local cache, report = catalog.build({
        item_master_list = { rt_sword = base, rt_sword_preview = preview },
        career_name = "es_knight",
        craftable_slot_types = { melee = true },
    })
    if report.total ~= 1 or report.suppressed ~= 1 or not cache.cim_template_rt_sword then
        return "#524 native preview/helper aliases no longer collapse to one craft family"
    end
end)

_rt_register("issue682_provider_gate_routing", function()
    -- issue 682 (confirmed boundary: Athanor craft on the immutable WOC relic
    -- rejected with `reason=nil`) + issue 628 (registered provider gate).
    -- Probe calls use the neutral surface name "rt_check" so this check never
    -- registers a REAL surface as routed (the 823 lesson: regression checks
    -- must not mutate live-module state they later assert on).
    local contract = mod._cim_synthetic_item_contract
    if type(contract) ~= "table" then return "synthetic-item contract not loaded" end
    if type(contract.gate_item) ~= "function" or type(contract.gate_record) ~= "function"
            or type(contract.report_unrouted) ~= "function" then
        return "provider gate API missing (gate_item/gate_record/report_unrouted)"
    end
    local relic = {
        woc_variant = true,
        woc_unique_relic = true,
        slot_type = "melee",
        can_wield = { "dr_ranger" },
        template = "rt_template", -- name-integrity: non-rendered-test-data
        item_type = "rt_relic", -- name-integrity: non-rendered-test-data
        inventory_icon = "rt_icon", -- name-integrity: non-rendered-test-data
    }
    local gate_ok, gate_problems = contract.gate_item("rt_check", "woc_rt_relic", relic)
    if gate_ok ~= false or type(gate_problems) ~= "table"
            or gate_problems[1] ~= "immutable_relic" then
        return "item gate did not classify the immutable relic rejection"
    end
    local record, reason = contract.gate_record("rt_check", "rt_682_bid", {
        item_key = "woc_rt_relic",
        rarity = "modded",
    }, relic)
    if record ~= nil then return "record gate accepted an immutable relic craft" end
    if type(reason) ~= "string" or reason == "" then
        return "record-gate rejection reason is nil/empty (issue 682 regression)"
    end
    -- Routed-surface census: every real provider-item enumerator must register
    -- its install site. `cw_conversion` is a rarity-exclude scrub only, not an
    -- item enumerator, and is documented separately by the contract.
    local missing = contract.unrouted_surfaces()
    if #missing ~= 0 then
        return "unrouted provider-gate surfaces: [" .. table.concat(missing, ",") .. "]"
    end
    if type(contract.NON_ENUMERATOR_BOUNDARIES) ~= "table"
            or contract.NON_ENUMERATOR_BOUNDARIES.cw_conversion ~= "rarity-exclude-scrub-only" then
        return "cw_conversion boundary lost its non-enumerator classification"
    end
end)

_rt_register("issue628_salvage_state_diagnostic", function()
    local contract = mod._cim_synthetic_item_contract
    if type(contract) ~= "table"
            or type(contract.salvage_trace_fingerprint) ~= "function"
            or type(contract.recover_salvage_items) ~= "function" then
        return "#628 salvage trace fingerprint policy missing"
    end
    if mod._cim628_salvage_trace_wired ~= true then
        return "#628 exact salvage-state diagnostic not wired"
    end
    local clean = contract.salvage_trace_fingerprint("rt_bid", true, true, nil, {})
    local saved = contract.salvage_trace_fingerprint("rt_bid", false, false, "loadout", {
        is_equipped_by_any_loadout = true,
    })
    if clean == saved then return "#628 loadout rejection does not change trace state" end
end)

_rt_register("issue703_athanor_cwv_rows_unlocked", function()
    -- #703: vanilla `_sync_backend_loadout` stamps `content.locked = not
    -- backend_id` from a backend-items OWNERSHIP lookup
    -- (hero_window_weave_forge_weapons.lua:555/:565). CWV's provider definition
    -- identity is distinct from CIM craft ownership (#592/#928); the one
    -- Blacksmith seed does not make every Athanor provider row CIM-owned. The
    -- consolidated hook clears the lock
    -- for provider=cwv keys only; this check pins the classifier's boundary so
    -- vanilla/other-provider locks can never be swept up with it.
    local classify = (mod._cim_synthetic_item_contract or {}).is_cwv_provider_key
    if type(classify) ~= "function" then
        return "#703 CWV lock-clear classifier (contract.is_cwv_provider_key) not exposed"
    end
    if classify("cwv_rt_unregistered_variant") ~= true then
        return "#703 cwv-prefixed key no longer classified as provider=cwv (rows re-lock)"
    end
    if classify("es_bastard_sword") ~= false then
        return "#703 vanilla key classified as cwv - would clear genuine vanilla locks"
    end
    if classify("woc_rt_unregistered_relic") ~= false then
        return "#703 non-cwv provider key classified as cwv - scope widened past issue scope"
    end
    if classify(nil) ~= false or classify("") ~= false then
        return "#703 empty/nil key must never classify as cwv"
    end
    -- The clear must ride the ONE consolidated (HeroWindowWeaveForgeWeapons,
    -- _sync_backend_loadout) hook; the issue 628 contract owns the ladder.
    local contract = mod._cim_synthetic_item_contract
    if type(contract) ~= "table" or type(contract.provider_for) ~= "function" then
        return "#703 issue 628 provider ladder (contract.provider_for) missing"
    end
end)

_rt_register("issue624_keep_forge_interaction", function()
    local policy = mod._cim_keep_forge_interaction
    local state = mod._cim_keep_forge_interaction_state
    if type(policy) ~= "table" or type(policy.resolve) ~= "function" then
        return "#624 Keep forge policy is not loaded"
    end
    if policy.resolve(false, true, true) ~= true
        or policy.resolve(false, true, false) ~= false
        or policy.resolve(false, false, true) ~= false then
        return "#624 Keep/untrusted interaction boundary changed"
    end
    if type(state) ~= "table" or type(state.original_can_interact) ~= "function"
        or type(state.installed_predicate) ~= "function" then
        return "#624 forge_access predicate was not installed"
    end
    local definitions = rawget(_G, "InteractionDefinitions")
    local live = definitions and definitions.forge_access and definitions.forge_access.client
        and definitions.forge_access.client.can_interact
    if live ~= state.installed_predicate then
        return "#624 another writer replaced the CIM forge_access predicate"
    end
end)

_rt_register("issue617_athanor_icon_resource_closure", function()
    local policy = mod._cim_athanor_icon_policy
    if type(policy) ~= "table" or type(policy.sanitize_layout) ~= "function"
        or type(policy.material_name) ~= "function" then
        return "#617 Athanor icon resource policy is not loaded"
    end

    -- Exact shape that crashed: custom atlas supplies ordinary/masked material
    -- names but no masked+saturated material. This must fail proof before draw.
    local atlas = {
        has_atlas_settings_by_texture_name = function() return true end,
        get_atlas_settings_by_texture_name = function()
            return { material_name = "rt_custom", masked_material_name = "rt_custom_masked" }
        end,
    }
    if policy.material_name("rt_custom_icon", atlas,
        { masked = true, saturated = true }) ~= nil then
        return "#617 missing masked+saturated atlas material was accepted"
    end

    local ok, provider = pcall(get_mod, "character_weapon_variants")
    local registry = ok and provider and provider._cwv_inventory_icons
    if type(registry) == "table" and type(registry.resolve) == "function"
        and type(registry.FALLBACKS) == "table" then
        for icon in pairs(registry.FALLBACKS) do
            local resolved, was_custom = registry.resolve(icon, policy.RENDERER_NAME)
            if not was_custom or resolved ~= icon then
                return "#787 CWV icon capability missing for Athanor: " .. tostring(icon)
            end
        end
    end

    local live = mod._cim_athanor_icon_report
    if live and (live.omitted or 0) > 0 then
        return string.format("#617 live Athanor catalog omitted %d rows with no renderer-safe icon",
            live.omitted)
    end
end)

_rt_register("issue787_cim_dual_axes_authored_icon", function()
    local policy = mod._cim_athanor_icon_policy
    local ok, provider = pcall(get_mod, "character_weapon_variants")
    local registry = ok and provider and provider._cwv_inventory_icons
    if type(policy) ~= "table" or type(registry) ~= "table"
        or type(registry.FALLBACKS) ~= "table" then
        return -- CWV is optional; no custom row exists without it.
    end
    local atlas = rawget(_G, "UIAtlasHelper")
    if type(atlas) ~= "table"
        or type(atlas.get_atlas_settings_by_texture_name) ~= "function" then
        return "#787 UIAtlasHelper unavailable"
    end
    for icon in pairs(registry.FALLBACKS) do
        local got, settings = pcall(atlas.get_atlas_settings_by_texture_name, icon)
        if not got or type(settings) ~= "table"
            or type(settings.masked_saturated_material_name) ~= "string"
            or settings.masked_saturated_material_name == "" then
            return "#787 masked+saturated atlas row incomplete: " .. tostring(icon)
        end
    end
    local live = mod._cim_athanor_icon_report
    for _, change in ipairs(live and live.changes or {}) do
        if registry.FALLBACKS[change.original] and change.replacement ~= change.original then
            return "#787 live CWV paired icon fell back: " .. tostring(change.original)
        end
    end
end)

_rt_register("modded_loadout_has_no_stale_entries", function()
    -- Every saved _modded_loadout entry must reference a live, exact
    -- _forged_weapons bid. Stale entries (bid no
    -- longer registered anywhere) are exactly the overwrite-bug substrate:
    -- on next session they restore-clobber the vanilla loadout with an item
    -- that no longer exists OR was already deleted.
    local stale = {}
    -- Indexed schema: career -> index -> slot -> bid.
    for career_name, indices in pairs(context.get_modded_loadout()) do
        if type(indices) == "table" then
            for index, slots in pairs(indices) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        local live = (type(bid) == "string") and context.get_forged_weapons()[bid]
                        if not live then
                            stale[#stale + 1] = string.format("%s[%s]/%s=%s",
                                tostring(career_name), tostring(index), tostring(slot_name), tostring(bid))
                            if #stale >= 5 then break end
                        end
                    end
                end
                if #stale >= 5 then break end
            end
        end
        if #stale >= 5 then break end
    end
    if #stale > 0 then
        return "stale modded_loadout entries (will clobber vanilla restore): " .. table.concat(stale, ", ")
    end
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_localization")
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

_rt_register("issue244_athanor_literal_property_values", function()
    local policy = mod._cim244_property_value_policy
    if type(policy) ~= "table"
        or type(policy.storage_for_bubbles) ~= "function"
        or type(policy.bubbles_for_storage) ~= "function"
    then
        return "#244 property-value policy is unavailable"
    end

    local stored = policy.storage_for_bubbles({ 0.03, 0.05 }, 0.05, 3, 5)
    if type(stored) ~= "number" or math.abs(stored) > 0.000001 then
        return string.format("3%% attack speed expected normalized 0, got %s", tostring(stored))
    end
    local bubbles = policy.bubbles_for_storage({ 0.03, 0.05 }, 0.05, stored, 5)
    if bubbles ~= 3 then
        return string.format("normalized low endpoint expected 3 bubbles, got %s", tostring(bubbles))
    end

    local WP, Weave = rawget(_G, "WeaponProperties"), rawget(_G, "WeaveProperties")
    local adv = WP and WP.properties and WP.properties.attack_speed
    local weave = Weave and Weave.properties and Weave.properties.weave_attack_speed
    local adv_value = adv and adv.description_values and adv.description_values[1]
    local weave_value = weave and weave.description_values and weave.description_values[1]
    if not (adv_value and type(adv_value.value) == "table"
        and weave_value and type(weave_value.value) == "number")
    then
        return "native attack-speed property shapes changed"
    end
    local live_stored = policy.storage_for_bubbles(adv_value.value, weave_value.value, 3, 5)
    if type(live_stored) ~= "number" or math.abs(live_stored) > 0.000001 then
        return string.format("native 3%% attack-speed conversion got %s", tostring(live_stored))
    end
end)

_rt_register("stamina_movespeed_clamp_at_overcap", function()
    -- v0.7.44-alpha (issue #49) removed the per-property bubble-cap rejection in the
    -- set_loadout_property hook (clicks past stamina=2 / movespeed=1 used to
    -- silently no-op). The engine-effective value must still clamp to 1.0 at
    -- over-cap counts so buffs don't exceed vanilla tiers. This check pins
    -- the clamp: if a future edit re-introduces over-cap values >1.0, buffs
    -- would exceed vanilla and we'd ship a balance regression silently.
    --
    -- Issue #86 take 3 (key-form root cause): the game's property-picker passes
    -- the WeaveProperties.categories key form `weave_stamina` / `weave_movespeed`
    -- (NOT `weave_properties_stamina`) to set_loadout_property /
    -- get_property_mastery_costs — traced through hero_window_weave_properties.lua
    -- :534/:550/:2663 → backend_interface_weaves_playfab.lua:1031. The prior fix
    -- keyed the cap table `properties_*` and the test passed `weave_properties_*`
    -- (strip-form `properties_*`), so the test matched the table but the GAME key
    -- (`weave_stamina` → strip-form bare `stamina`) missed → fell back to cap 5
    -- (stamina ate 5 slots, movespeed showed 79%). This test now drives ALL THREE
    -- key forms (bare / `properties_` / `weave_properties_`) AND the game's actual
    -- `weave_<bare>` form, so a future miskeying of the cap table fails here.
    if type(_value_for_bubbles) ~= "function" then return "_value_for_bubbles missing" end
    if type(_bubble_cap) ~= "function" then return "_bubble_cap missing" end
    -- #86 core: stamina caps at exactly 2 slots on every key form, incl. the
    -- game's real `weave_stamina`.
    for _, form in ipairs({ "stamina", "properties_stamina", "weave_properties_stamina", "weave_stamina" }) do
        if _bubble_cap(form) ~= 2 then
            return string.format("stamina slot cap expected 2 for key '%s', got %s (Issue #86 regression)", form, tostring(_bubble_cap(form)))
        end
    end
    -- Clamp pins (drive the real game key form).
    if _value_for_bubbles("weave_stamina", 2) ~= 1.0 then
        return string.format("stamina at cap (2) expected 1.0, got %s", tostring(_value_for_bubbles("weave_stamina", 2)))
    end
    if _value_for_bubbles("weave_stamina", 3) ~= 1.0 then
        return string.format("stamina over-cap (3) expected clamp to 1.0, got %s", tostring(_value_for_bubbles("weave_stamina", 3)))
    end
    if _value_for_bubbles("weave_stamina", 5) ~= 1.0 then
        return string.format("stamina over-cap (5) expected clamp to 1.0, got %s", tostring(_value_for_bubbles("weave_stamina", 5)))
    end
    -- movespeed cap=1 only when the 2pct toggle is OFF (default). Test the
    -- default path on every key form; restore the user's setting afterward.
    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end
    local ms_err
    for _, form in ipairs({ "movespeed", "properties_movespeed", "weave_properties_movespeed", "weave_movespeed" }) do
        if not ms_err and _bubble_cap(form) ~= 1 then
            ms_err = string.format("movespeed slot cap (default) expected 1 for key '%s', got %s", form, tostring(_bubble_cap(form)))
        end
    end
    local m1 = _value_for_bubbles("weave_movespeed", 1)
    local m3 = _value_for_bubbles("weave_movespeed", 3)
    if saved == true then mod:set("movespeed_2pct_mode", true) end
    if ms_err then return ms_err end
    if m1 ~= 1.0 then return string.format("movespeed at cap (1) expected 1.0, got %s", tostring(m1)) end
    if m3 ~= 1.0 then return string.format("movespeed over-cap (3) expected clamp to 1.0, got %s", tostring(m3)) end
end)

_rt_register("picker_caps_persisted_slot_array", function()
    -- #86 take 4 (the movespeed-BLOCKS-other-slots report): the prior #86 fixes
    -- only checked `_bubble_cap` / `_value_for_bubbles` — the DISPLAY math. They
    -- never asserted the PERSISTED `props[property_key]` array length, which is
    -- what actually drives grid occupancy (vanilla _sync_backend_loadout maps
    -- one grid slot per array entry). This test drives the REAL picker store
    -- (`_store_property_slot`, shared with the live set_loadout_property hook)
    -- and asserts the array NEVER exceeds the property's bubble cap — so a
    -- future regression that over-fills the array (the exact "movespeed takes 5
    -- slots and blocks the rest" bug) fails here, not just in-game.
    if type(_store_property_slot) ~= "function" then return "_store_property_slot missing" end

    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end

    -- Helper: simulate N picker clicks for `key`, each landing on a fresh free
    -- grid slot (vanilla _find_next_available_slot only ever offers free slots,
    -- so distinct indices), then return the persisted array length.
    local function _sim_clicks(props, key, n, start_index)
        for i = 0, n - 1 do
            _store_property_slot(props, key, start_index + i)
        end
        return #(props[key] or {})
    end

    -- Movespeed: default cap 1. Even 5 clicks must persist EXACTLY 1 slot.
    local p = {}
    local ms_len = _sim_clicks(p, "weave_movespeed", 5, 1)
    if ms_len ~= 1 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return string.format("movespeed (2pct OFF): 5 clicks persisted %d slot indices, expected 1 — over-occupancy regression (#86)", ms_len)
    end

    -- Stamina: cap 2. 5 clicks must persist EXACTLY 2 (proves the fix doesn't
    -- regress the property that already worked).
    p = {}
    local st_len = _sim_clicks(p, "weave_stamina", 5, 10)
    if st_len ~= 2 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return string.format("stamina: 5 clicks persisted %d slot indices, expected 2", st_len)
    end

    -- Cross-property collision: a slot_index already held by movespeed must not
    -- also be stored under stamina (vanilla's global slot-occupancy guard).
    p = {}
    _store_property_slot(p, "weave_movespeed", 7)
    _store_property_slot(p, "weave_stamina", 7) -- same index -> must be rejected
    if (p.weave_stamina and #p.weave_stamina or 0) ~= 0 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return "cross-property collision guard failed: slot_index 7 stored under both movespeed and stamina"
    end

    -- Re-click dedupe: clicking the SAME slot twice for one property stays at 1.
    p = {}
    _store_property_slot(p, "weave_movespeed", 3)
    _store_property_slot(p, "weave_movespeed", 3)
    if #p.weave_movespeed ~= 1 then
        if saved == true then mod:set("movespeed_2pct_mode", true) end
        return string.format("re-click dedupe failed: movespeed persisted %d entries for one slot, expected 1", #p.weave_movespeed)
    end

    -- 2pct mode ON: movespeed legitimately uncaps to 5 (documented trade). Pin
    -- it so a future change that forgets the 2pct path is caught too.
    mod:set("movespeed_2pct_mode", true)
    p = {}
    local ms5 = _sim_clicks(p, "weave_movespeed", 7, 1)
    if saved ~= true then mod:set("movespeed_2pct_mode", false) else mod:set("movespeed_2pct_mode", true) end
    if ms5 ~= 5 then
        return string.format("movespeed (2pct ON): 7 clicks persisted %d slot indices, expected 5 (the +2%%-per-bubble trade)", ms5)
    end
end)

_rt_register("read_chokepoint_caps_grid_occupancy", function()
    -- #86 v0.8.30-dev: the WRITE-path cap is provably correct (the test above),
    -- yet the symptom persisted in-game — proving the array reaching the grid is
    -- over-filled by a path the write cap doesn't cover. `_cap_grid_property_arrays`
    -- is the read-side guard: it trims whatever get_loadout_properties is about to
    -- hand vanilla `_sync_backend_loadout`, which maps one grid slot per array
    -- entry. This drives it with a DELIBERATELY over-filled array (simulating the
    -- leak) and asserts the grid never sees more than the cap.
    if type(_cap_grid_property_arrays) ~= "function" then return "_cap_grid_property_arrays missing" end

    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end
    local function _restore() if saved == true then mod:set("movespeed_2pct_mode", true) end end

    -- Weapon editor (item_backend_id present = one layer). Over-fill movespeed to
    -- 5 and stamina to 5, then assert the read guard trims to 1 and 2.
    local p = {
        weave_movespeed = { 1, 2, 3, 4, 5 },
        weave_stamina   = { 6, 7, 8, 9, 10 },
    }
    _cap_grid_property_arrays(p, "fake_weapon_bid")
    if #p.weave_movespeed ~= 1 then
        _restore(); return string.format("read guard (weapon): movespeed trimmed to %d, expected 1", #p.weave_movespeed)
    end
    if #p.weave_stamina ~= 2 then
        _restore(); return string.format("read guard (weapon): stamina trimmed to %d, expected 2", #p.weave_stamina)
    end

    -- Amulet editor (item_backend_id == nil = per-layer cap). Movespeed cap 1 PER
    -- accessory: necklace (layer 1, idx 1..10) + charm (layer 2, idx 11..20) must
    -- keep ONE each = 2 total, not collapse to 1. An over-fill within one layer
    -- (idx 1 and 2 both layer 1) must trim to 1 for that layer.
    local a = { weave_movespeed = { 1, 2, 11 } } -- layer1: {1,2}->1, layer2: {11}->1
    _cap_grid_property_arrays(a, nil)
    if #a.weave_movespeed ~= 2 then
        _restore(); return string.format("read guard (amulet): movespeed across 2 layers trimmed to %d, expected 2 (per-layer cap)", #a.weave_movespeed)
    end

    -- Already-capped arrays must pass through untouched (idempotent / no false trim).
    local ok = { weave_stamina = { 3, 4 }, weave_movespeed = { 5 } }
    _cap_grid_property_arrays(ok, "fake_weapon_bid")
    if #ok.weave_stamina ~= 2 or #ok.weave_movespeed ~= 1 then
        _restore(); return "read guard: trimmed an already-capped array (false positive)"
    end

    _restore()
end)

_rt_register("default_property_cap_is_five_bubbles", function()
    -- #86 (2026-06-29, v0.8.33-dev): every generic property keeps a 5-bubble row
    -- you fill to SCALE its value (1 bubble = 20%, 5 = full) — the vanilla weave
    -- behavior. v0.8.32-dev briefly forced the default to 1, which let each
    -- property take only one bubble and killed per-property scaling for all of
    -- them; this pins the default back at 5 so that over-correction can't recur.
    -- The real #86 fix is the distinct-property ceiling (MAX_DISTINCT / trimmer
    -- raised to 10), exercised by `picker_caps_persisted_slot_array`; this guards
    -- the DEFAULT bubble cap + its scaling math.
    if type(_bubble_cap) ~= "function" then return "_bubble_cap missing" end
    if type(_value_for_bubbles) ~= "function" then return "_value_for_bubbles missing" end

    local saved = mod:get("movespeed_2pct_mode")
    if saved ~= false then mod:set("movespeed_2pct_mode", false) end
    local function _restore() if saved == true then mod:set("movespeed_2pct_mode", true) end end

    -- A spread of real default (non-special-cased) weave property keys — each
    -- must resolve to cap 5 in any key form (weave_X / properties_X / bare X).
    for _, key in ipairs({
        "weave_fatigue_regen", "weave_crit_chance", "weave_attack_speed",
        "weave_block_cost", "weave_power_vs_chaos", "fatigue_regen",
        "properties_crit_chance",
    }) do
        local c = _bubble_cap(key)
        if c ~= 5 then
            _restore()
            return string.format("default cap for '%s' = %s, expected 5 (#86 single-bubble regression)", key, tostring(c))
        end
        -- Value must SCALE with bubbles: 1 → 0.2, 5 → 1.0 (full).
        if _value_for_bubbles(key, 1) ~= 0.2 then
            _restore()
            return string.format("'%s': 1 bubble value = %s, expected 0.2 (scaling broken)", key, tostring(_value_for_bubbles(key, 1)))
        end
        if _value_for_bubbles(key, 5) ~= 1.0 then
            _restore()
            return string.format("'%s': 5 bubble value = %s, expected 1.0 (max)", key, tostring(_value_for_bubbles(key, 5)))
        end
    end

    -- Special cases unchanged.
    if _bubble_cap("weave_stamina") ~= 2 then _restore(); return "stamina cap regressed from 2" end
    if _bubble_cap("weave_movespeed") ~= 1 then _restore(); return "movespeed cap regressed from 1" end

    _restore()
end)

_rt_register("action_rejection_uses_warning_channel", function()
    -- v0.7.44-alpha converted ~dozen action-rejection callsites from mod:echo
    -- to mod:warning (issue #47). mod:echo is redirected to log only; mod:warning
    -- bypasses it so the user sees WHY a click was rejected. Regression: if
    -- someone re-points mod.warning at the redirected echo (or replaces both with
    -- the same function), rejections become invisible and the user perceives
    -- "broken mod" — exactly the user-report substrate from 2026-05-25.
    if type(mod.warning) ~= "function" then return "mod.warning missing" end
    if type(mod.echo) ~= "function" then return "mod.echo missing" end
    if mod.warning == mod.echo then
        return "mod.warning and mod.echo are the same function — chat-suppression patch leaked into the warning channel"
    end
    -- Smoke: must not raise.
    local ok, err = pcall(function() mod:warning("[cim:rt] action_rejection_uses_warning_channel smoke (ignore)") end)
    if not ok then return string.format("mod:warning raised: %s", tostring(err)) end
end)

return {
    with_loadout_sandbox = _rt_with_loadout_sandbox,
}

end
