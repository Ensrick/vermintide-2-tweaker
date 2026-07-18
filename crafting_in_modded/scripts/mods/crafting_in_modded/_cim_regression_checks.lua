-- _cim_regression_checks.lua - runtime regression registrations for CIM dev
--
-- Owns only the issue-locking/runtime invariant closures consumed by
-- /cim_regression_test. Production state stays in the entry and is supplied
-- through narrow accessors so reassigned persistence tables cannot go stale.
-- Registration names and order are preserved from the former inline block.
--
-- Owned by: crafting_in_modded.lua. Consumed via: one late manifest dofile.

return function(context)
    local mod = context.mod
    local _rt_register = context.rt_register
    local _rt_src_read = context.rt_src_read
    local _dbg = context.dbg
    local _dbg_alert = context.dbg_alert
    local _bubble_cap = context.bubble_cap
    local _value_for_bubbles = context.value_for_bubbles
    local _cap_grid_property_arrays = context.cap_grid_property_arrays
    local _ensure_item_adventure_visible = context.ensure_item_adventure_visible
    local _forge_load = context.forge_load
    local _is_in_keep = context.is_in_keep
    local _store_property_slot = context.store_property_slot
    local _AccessoryPanel = context.accessory_panel
    local _OVERVIEW_BTN_RENDER_FIELD = context.overview_btn_render_field
    local _OVERVIEW_DRAWN_FIELDS = context.overview_drawn_fields
    local _modded_loadout_load = context.modded_loadout_load
    local CIM_RPC_SCHEMA = context.rpc_schema
    local _rt_with_loadout_sandbox

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================

_rt_register("issue277_bulk_cleanup_exact_owner_transaction", function()
    local core = mod._cim277_bulk_core
    if type(core) ~= "table" or type(core.classify) ~= "function"
            or type(core.partition_equipped) ~= "function"
            or type(core.clear_loadout_refs) ~= "function"
            or type(mod._cim277_delete_owned_ids) ~= "function"
            or mod.CIM277_BULK_CLEANUP_MARKER_v0_8_68 ~= true then
        return "#277 cleanup policy/runtime wiring missing"
    end

    local weapons, retained, unresolved = core.classify({
        owned_weapon = { item_key = "weapon" },
        owned_accessory = { item_key = "accessory" },
        owned_missing = { item_key = "missing" },
    }, {
        weapon = { slot_type = "melee" },
        accessory = { slot_type = "necklace" },
        rarity_only_not_owned = { slot_type = "ranged", rarity = "modded" },
    })
    if #weapons ~= 1 or weapons[1] ~= "owned_weapon"
            or #retained ~= 1 or retained[1] ~= "owned_accessory"
            or #unresolved ~= 1 or unresolved[1] ~= "owned_missing" then
        return "exact-owner weapon classification failed"
    end

    local deletable, blocked, uncertain = core.partition_equipped(
        { "free", "equipped", "unknown" },
        function(id)
            if id == "free" then return false end
            if id == "equipped" then return true end
            return nil
        end
    )
    if #deletable ~= 1 or deletable[1] ~= "free"
            or #blocked ~= 1 or blocked[1] ~= "equipped"
            or #uncertain ~= 1 or uncertain[1] ~= "unknown" then
        return "equipped/uncertain fail-closed partition failed"
    end
    if core.signature({ "b", "a" }) ~= core.signature({ "a", "b" }) then
        return "confirmation signature changed with iteration order"
    end
end)

_rt_register("issue246_tab_preview_exact_skin_icon", function()
    local core = mod._cim246_tab_preview_core
    if type(core) ~= "table" or type(core.resolve) ~= "function"
            or type(mod._cim246_apply_player_weapon_icons) ~= "function" then
        return "#246 Tab-preview policy/runtime wiring missing"
    end

    local authoritative, skin, icon = core.resolve({}, {
        slots = { slot_melee = { skin = "issue246_test_skin" } },
    }, "slot_melee", {
        issue246_test_skin = { inventory_icon = "issue246_test_icon" },
    })
    if not authoritative or skin ~= "issue246_test_skin"
            or icon ~= "issue246_test_icon" then
        return "exact live-equipment skin did not win over base loadout identity"
    end

    authoritative, skin, icon = core.resolve({}, {
        slots = { slot_melee = { skin = "n/a" } },
    }, "slot_melee", {})
    if not authoritative or skin ~= nil or icon ~= nil then
        return "default skin did not clear stale preview identity"
    end
end)

_rt_register("weave_talent_forge_level_guard_present", function()
    -- Issue #71 (2026-06-01): pressing the amulet under the modded forge crashed
    -- in vanilla get_talent_required_forge_level, which nil-indexes
    -- progression_settings.talents[talent_name] for the adventure career talents
    -- cim feeds in. The fix hooks that method to return 0 under _custom_forge_active
    -- (alongside the existing get_property_/get_trait_ guards). This source-pattern
    -- check fails if that hook is removed. The needle is assembled from two literals
    -- so this test's own source does not self-match. Degrades to a no-op when source
    -- introspection is unavailable (deploy/bundle paths).
    local ok, info = pcall(debug.getinfo, _rt_register, "S")
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
    -- Source-pattern (io-safe #511; nil in retail sandbox => skip): the residency
    -- fallback must remain in pkg_missing. Split needle so this line can't self-match.
    local ok, info = pcall(debug.getinfo, _rt_register, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local needle = 'if Application.can_get("unit", p) then ' .. 'return false end'
    if not txt:find(needle, 1, true) then
        return "#481 regression: pkg_missing dropped the resident-3p-unit fallback (LA-skinned shields lose the forge preview)"
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
    local ok, info = pcall(debug.getinfo, _rt_register, "S")
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
    -- file-local _rt_register). Split needles so these lines can't self-match.
    -- No-op if the source is unreadable.
    local ok, info = pcall(debug.getinfo, _rt_register, "S")
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

_rt_register("cwv_registration_is_not_acquisition", function()
    -- #592 supersedes #524's two-template workaround. CWV now owns only the
    -- ItemMasterList definition; CIM injects exactly one synthetic selector.
    if type(mod._cim_inject_templates) ~= "function" then
        return "standard-forge template injector (_cim_inject_templates) not exposed"
    end
    if mod._cim592_cwv_registration_only ~= true then
        return "#592 regression: CIM/CWV registration-only contract marker missing"
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
        data = { key = "es_bastard_sword" },
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
    legacy.data.slot_type = "melee"
    legacy.data.item_type = "es_bastard_sword" -- name-integrity: non-rendered-test-data
    legacy.power_level = 5
    rows = { legacy_300, legacy, synthetic }
    selector.inject(rows, { synthetic })
    if #rows ~= 1 or rows[1] ~= legacy or rows[1].power_level ~= 5 then
        return "duplicate real/default CWV rows did not collapse to the 5-power selector"
    end
    local crafted = {
        backend_id = "cwv_rt_longsword_100",
        rarity = "modded",
        data = { cwv_key = "cwv_rt_longsword" },
    }
    rows = { crafted }
    selector.inject(rows, { synthetic })
    selector.inject(rows, { synthetic })
    if #rows ~= 2 or rows[1] ~= crafted or rows[2] ~= synthetic then
        return "crafted CWV instance changed the one-selector acquisition bound"
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

_rt_register("issue524_render_diagnostics_armed", function()
    -- The three checks above exercise catalog.build / inject with synthetic
    -- inputs. None observes the list vanilla actually renders at menu-open, which
    -- is precisely the blind spot behind ten failed #524 ships. This check fails
    -- if the render-seam probe (_cim_diag_524 + its inject-seam call) is stripped
    -- while #524 is open, so the rendered-list evidence stays armed.
    local diag = mod._cim_diag_524
    if type(diag) ~= "table" or type(diag.dump) ~= "function" then
        return "#524 render-seam diagnostic (_cim_diag_524.dump) not loaded"
    end
    if mod._cim524_render_probe_wired ~= true then
        return "#524 render-seam probe not wired into the inject seam"
    end
    -- The probe classifies rows via the selector's canonical_family; that shared
    -- helper must stay exposed or the dump would mislabel every family.
    local selector = mod._cim_template_selector
    if type(selector) ~= "table" or type(selector.canonical_family) ~= "function" then
        return "#524 render probe lost its canonical_family classifier"
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
        for icon, expected in pairs(registry.FALLBACKS) do
            local resolved, was_custom = registry.resolve(icon, policy.RENDERER_NAME)
            if not was_custom or resolved ~= expected then
                return "#617 CWV icon not fail-closed for Athanor: " .. tostring(icon)
            end
        end
    end

    local live = mod._cim_athanor_icon_report
    if live and (live.omitted or 0) > 0 then
        return string.format("#617 live Athanor catalog omitted %d rows with no renderer-safe icon",
            live.omitted)
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded/crafting_in_modded_localization")
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

_rt_register("morris_hub_passes_open_forge_gate", function()
    -- v0.7.47-alpha removed the blanket `mech == "deus" -> block` early return
    -- in mod.open_forge. The CW staging hub (morris_hub) is part of the deus
    -- mechanism but DamageUtils.is_in_inn returns true there, so the keep-gate
    -- correctly permits it. Regression: if the deus block sneaks back, the
    -- staging-hub forge breaks again. This check is a state-witness — it
    -- skips unless we're actually in morris_hub, then asserts the inn-gate passes.
    if not (rawget(_G, "DamageUtils") and Managers) then
        return "skip: DamageUtils / Managers not loaded"
    end
    local mech_mgr = Managers.mechanism
    if not mech_mgr or not mech_mgr.current_mechanism_name then
        return "skip: Managers.mechanism not ready"
    end
    local mech = mech_mgr:current_mechanism_name()
    if mech ~= "deus" then
        return "skip: not in CW mechanism (currently " .. tostring(mech) .. ")"
    end
    if not DamageUtils.is_in_inn then
        return "skip: in active CW expedition (run from morris_hub staging)"
    end
    if type(mod.open_forge) ~= "function" then return "mod.open_forge missing" end
    -- We're in morris_hub and is_in_inn=true → open_forge's keep-gate permits.
    -- We do NOT call open_forge here (it would trigger a UI transition).
end)

_rt_register("trim_logging_emits_per_item_detail", function()
    -- v0.7.33-alpha added per-item `[trim] <key> (bid=...) kept=[...] dropped=[...]`
    -- log lines so user reports of "my weapon lost properties" are diagnosable
    -- from the log alone. Guards the mod:info channel that carries the per-item
    -- detail — if a future edit silences mod:info or removes the logger, the
    -- diagnostic chain breaks.
    if type(mod.info) ~= "function" then return "mod.info missing — per-item trim detail would not log" end
    local ok, err = pcall(function() mod:info("[cim:rt] trim_logging_emits_per_item_detail smoke (ignore)") end)
    if not ok then return string.format("mod:info raised: %s", tostring(err)) end
end)

_rt_register("no_duplicate_hook_safe_registrations", function()
    -- v0.7.51-dev: the rehook-warning interceptor at the top of this file
    -- captures every `mod:warning("...rehook active hook...")` VMF emits at
    -- boot. If any are present, we have two sibling `hook_safe` registrations
    -- on the same Class+method — VMF silently drops one, breaking whichever
    -- callback registered later. Caught HeroWindowLoadoutInventory.on_enter
    -- being double-hooked (modded_rarities.lua + cim_debug.lua) on 2026-05-27.
    --
    -- This is a state-witness, not a static check: the interceptor must be
    -- installed BEFORE any of cim's `hook_safe` calls (it is — the
    -- interceptor sits right after the `mod.echo` patch at the top of this
    -- file, before any module loads or hook registrations).
    local warns = mod._cim_rehook_warnings or {}
    if #warns > 0 then
        local first = warns[1]
        if #warns > 1 then
            first = first .. string.format(" (and %d more)", #warns - 1)
        end
        return "VMF rehook warnings at boot — duplicate hook_safe registration: " .. first
    end
end)

_rt_register("accessories_label_on_overview", function()
    -- v0.7.50-dev (issue #38): the modded Athanor overview viewport_title_2 was
    -- hardcoded as "JEWELLERY"; fixed to "ACCESSORIES". This check can't read
    -- the live widget text (overview is constructed mid-state-transition), but
    -- we can defend the source: if a future edit re-introduces the literal
    -- "JEWELLERY" anywhere in this file or standard_forge.lua, the user-facing
    -- regression would silently ship. Static-source check via mod.dofile of
    -- the localization file (the only place the loc key lives) is a layer; we
    -- also pin the loc override here for the standard forge recipe title.
    local ok = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded/modded_rarities")
    if not ok then return end  -- module load failed elsewhere; skip
    -- modded_rarities sets cat.display_name = "Accessories" on jewellery
    -- category at HeroWindowLoadoutInventory.on_enter. The Localize override
    -- table maps crafting_recipe_craft_jewellery -> "Craft Accessories".
    -- Both are layered defenses; this check only catches gross regressions
    -- (e.g. someone reverts the table back to "Jewellery").
    local rarity_func = rawget(_G, "Localize")
    if type(rarity_func) ~= "function" then return "skip: Localize not loaded" end
    local localized = rarity_func("crafting_recipe_craft_jewellery")
    if type(localized) ~= "string" then return "Localize did not return a string" end
    if localized:find("[Jj]ewel") then
        return string.format("crafting_recipe_craft_jewellery still localizes to %q — Accessories override broken", localized)
    end
end)

_rt_register("overview_btn_render_target", function()
    -- v0.7.60-dev: HeroWindowWeaveForgeOverview has NO `_widgets` array — it
    -- draws from _top_widgets / _bottom_widgets / _top_hdr_widgets /
    -- _bottom_hdr_widgets (vanilla _draw, hero_window_weave_forge_overview.lua).
    -- v0.7.57/.58 appended the 3 jewelry buttons to overview._widgets, so they
    -- went into a collection the window never iterates and NEVER rendered
    -- ("nothing changed" report). Pin the append target to the valid drawn set
    -- so a regression can't silently re-break it.
    if not _OVERVIEW_DRAWN_FIELDS[_OVERVIEW_BTN_RENDER_FIELD] then
        return string.format(
            "overview jewelry buttons append to %q, which is NOT a drawn array on HeroWindowWeaveForgeOverview (must be one of _top_widgets/_bottom_widgets/_top_hdr_widgets/_bottom_hdr_widgets) — buttons will not render",
            tostring(_OVERVIEW_BTN_RENDER_FIELD))
    end
end)

_rt_register("forge_tooltip_no_equipped_compare", function()
    -- v0.8.62-dev (issue 521): the Athanor hover tooltip widget must carry
    -- content.no_equipped_item = true, or the vanilla item_tooltip pass appends
    -- "currently equipped" comparison boxes from the career loadout
    -- (ui_passes.lua:3599-3645) and hovering one weapon slot pops BOTH weapons'
    -- popups. The widget only exists while a forge overview instance is alive,
    -- so the creation site anchors its content table on mod._cim_tooltip_content
    -- for this check.
    local content = mod._cim_tooltip_content
    if content then
        if content.no_equipped_item ~= true then
            return "forge hover tooltip lost no_equipped_item = true - the vanilla item_tooltip pass will append equipped-compare popups (double popup, issue 521)"
        end
        return
    end
    -- Forge not opened this session: source needle (io-safe #511; nil in retail
    -- sandbox => skip). Split needle so this line can't self-match.
    local ok, info = pcall(debug.getinfo, _rt_register, "S")
    if not ok or type(info) ~= "table" or not info.source then return "skip: forge not opened; no source introspection" end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)
    if not txt then return "skip: forge not opened this session; source unreadable (retail)" end
    local needle = 'tt.content.no_equipped_item' .. ' = true'
    if not txt:find(needle, 1, true) then
        return "issue 521 regression: forge tooltip widget no longer sets no_equipped_item = true (double popup returns)"
    end
end)

_rt_register("issue521_tooltip_follows_hovered_weapon", function()
    -- Vanilla scenegraph: viewport panels 1/2/3 sit at x=-545/0/+545.
    -- CIM's tooltip is parented to panel 2 with a 10px inset, so the exact
    -- melee/ranged anchors must be -535/+555.
    local melee_x = ((1 - 2) * 545) + 10
    local ranged_x = ((3 - 2) * 545) + 10
    if melee_x ~= -535 or ranged_x ~= 555 or ranged_x - melee_x ~= 1090 then
        return "#521 tooltip weapon-panel anchors drifted"
    end
    local live_x = mod._cim_tooltip_anchor_x
    if live_x ~= nil and live_x ~= melee_x and live_x ~= ranged_x then
        return "#521 live tooltip anchor is not a weapon viewport: " .. tostring(live_x)
    end
end)

_rt_register("adventure_visible_stamp_and_mechanism_clear", function()
    -- v0.7.62-dev: _ensure_item_adventure_visible must (1) APPEND the crafting
    -- career to ItemMasterList[key].can_wield exactly once (idempotent), and
    -- (2) CLEAR a non-adventure `mechanisms` field (e.g. {"versus"}) so the
    -- Adventure inventory grid stops hiding the crafted item. Tested against a
    -- throwaway fake key (rawset/rawget bypass the ItemMasterList Crashify
    -- metatable), removed afterward so there's zero side effect on real data.
    local IML = rawget(_G, "ItemMasterList")
    if not IML then return "skip: ItemMasterList not loaded" end
    local fake_key = "__cim_rt_fake_advvis__"
    rawset(IML, fake_key, { can_wield = { "es_mercenary", "es_huntsman" }, mechanisms = { "versus" } })
    local ok, errmsg = pcall(function()
        _ensure_item_adventure_visible(fake_key, "es_questingknight")   -- append career + clear mechanisms
        _ensure_item_adventure_visible(fake_key, "es_questingknight")   -- no-op (present + already cleared)
        _ensure_item_adventure_visible(fake_key, "es_mercenary")        -- no-op (already wieldable)
    end)
    local entry = IML[fake_key] or {}
    local cw = entry.can_wield or {}
    local count_qk = 0
    for _, c in ipairs(cw) do if c == "es_questingknight" then count_qk = count_qk + 1 end end
    local total = #cw
    local mechanisms_cleared = (entry.mechanisms == nil)
    rawset(IML, fake_key, nil)  -- cleanup: no lingering fake entry
    if not ok then return "adventure-visible helper errored: " .. tostring(errmsg) end
    if count_qk ~= 1 then
        return string.format("can_wield stamp not idempotent: es_questingknight appears %d times (expected 1)", count_qk)
    end
    if total ~= 3 then
        return string.format("can_wield stamp wrong size: expected 3 entries (2 original + 1 appended), got %d", total)
    end
    if not mechanisms_cleared then
        return "mechanisms not cleared — Versus item would stay hidden in Adventure grid"
    end
end)

_rt_register("versus_twin_rehidden_from_inventory", function()
    -- v0.8.22-dev: the global `mechanisms = nil` clear above (intended — makes a
    -- CRAFTED vs_* adventure-visible) also leaks the player's RAW OWNED vs_* twin
    -- into the adventure inventory grid, because item.data is a SHARED reference
    -- to the cleared IML entry (PlayFabMirrorBase._update_data:1786). The
    -- get_filtered_items hook re-hides the owned twin at the DISPLAY layer.
    -- Assert _cim_is_leaked_versus_twin distinguishes the two:
    --   owned vs_* twin (vanilla bid)   -> hidden  (true)
    --   cim-crafted vs_* (modded bid)   -> visible (false — stays craftable/shown)
    --   non-versus item                 -> visible (false)
    local twin_fn = mod._cim_is_leaked_versus_twin
    if type(twin_fn) ~= "function" then
        return "mod._cim_is_leaked_versus_twin missing — versus-twin inventory re-hide not wired"
    end
    -- Owned twin: vs_ key, NON-modded backend_id -> must be re-hidden.
    local owned_twin = { key = "vs_gutter_runner_claws", backend_id = "vanilla-owned-bid-12345" }
    if not twin_fn(owned_twin) then
        return "owned vs_* twin not flagged for re-hide — would leak into the adventure inventory grid"
    end
    -- Crafted vs_*: register a fake modded bid so _cim_is_modded_backend_id
    -- returns true, then it must NOT be re-hidden (stays visible/craftable).
    local crafted_bid = "__cim_rt_fake_vs_craft__"
    context.get_forged_weapons()[crafted_bid] = { item_key = "vs_gutter_runner_claws" }
    local crafted = { key = "vs_gutter_runner_claws", backend_id = crafted_bid }
    local crafted_hidden = twin_fn(crafted)
    context.get_forged_weapons()[crafted_bid] = nil  -- cleanup
    if crafted_hidden then
        return "cim-crafted vs_* incorrectly flagged for re-hide — deliberately-surfaced craft would vanish from inventory"
    end
    -- Non-versus item: never touched.
    if twin_fn({ key = "es_1h_sword", backend_id = "whatever" }) then
        return "non-versus item incorrectly flagged for re-hide"
    end
end)

_rt_register("overview_btns_created_when_forge_opened", function()
    -- State-witness (like no_duplicate_hook_safe_registrations): if the weave
    -- forge overview has been opened this session, _ensure_overview_jewelry_buttons
    -- must have succeeded in creating the 3 buttons. mod._cim_overview_btn_created
    -- is set to the count on success and to false on a create/init failure.
    -- nil = forge never opened this session → skip (can't assert).
    local created = mod._cim_overview_btn_created
    if created == nil then return "skip: weave forge overview not opened this session" end
    if created == false then
        return "weave forge overview opened but jewelry buttons failed to create (see [cim] overview jewelry button ... failed log lines)"
    end
    if type(created) == "number" and created ~= 3 then
        return string.format("expected 3 overview jewelry buttons, created %d", created)
    end
end)

_rt_register("accessory_panel_module_loaded", function()
    -- v0.7.65-dev: the accessory craft buttons are an own-scenegraph overlay
    -- module (_accessory_craft_panel.lua), the CORRECT pattern (vs the disabled
    -- create_default_button approach). This pins: the module loaded, exposes its
    -- draw API + button-count, and the 3 slot mappings are intact (necklace /
    -- charm=ring / trinket_1) so a future edit can't silently break the wiring.
    if _AccessoryPanel == nil then
        return "accessory craft panel module failed to load (mod.dofile error at boot)"
    end
    if type(_AccessoryPanel.draw) ~= "function" then
        return "accessory panel missing draw() — overlay can't render"
    end
    if _AccessoryPanel.NUM_BUTTONS ~= 3 then
        return string.format("accessory panel NUM_BUTTONS expected 3, got %s", tostring(_AccessoryPanel.NUM_BUTTONS))
    end
    local want = { slot_necklace = true, slot_ring = true, slot_trinket_1 = true }
    local defs = _AccessoryPanel.BUTTONS or {}
    if #defs ~= 3 then return string.format("accessory panel BUTTONS expected 3 entries, got %d", #defs) end
    for _, b in ipairs(defs) do
        if not (b.slot and want[b.slot]) then
            return string.format("accessory panel has unexpected slot mapping: %s", tostring(b and b.slot))
        end
        want[b.slot] = nil  -- ensure no duplicate slot
    end
    if next(want) ~= nil then
        return "accessory panel missing a slot mapping (necklace/charm/trinket)"
    end
end)

_rt_register("accessory_panel_built_when_accessories_opened", function()
    -- State-witness: if the accessories (amulet) view drew this session, the
    -- panel's lazy _build() must have produced exactly NUM_BUTTONS widgets. nil
    -- _built = accessories view never opened → skip (can't assert).
    if _AccessoryPanel == nil then return "skip: panel module not loaded" end
    if not _AccessoryPanel._built then
        return "skip: accessories view not opened this session (panel not built yet)"
    end
    local n = _AccessoryPanel._widgets and #_AccessoryPanel._widgets or 0
    if n ~= _AccessoryPanel.NUM_BUTTONS then
        return string.format("accessory panel built %d widgets, expected %d", n, _AccessoryPanel.NUM_BUTTONS)
    end
end)

_rt_register("backendutils_capture_installed", function()
    -- v0.7.68-dev (issue #22): with Loremaster's Armoury active, menu equips
    -- dispatch through BackendUtils.set_loadout_item, bypassing the
    -- BackendInterfaceItemPlayfab hook. The deferred BackendUtils capture is THE
    -- fix that records the player's equips into _modded_loadout. It installs from
    -- mod.update once the backend is up. nil = backend not up yet this session
    -- (e.g. tests run at main menu) → skip. false should never persist once in
    -- the keep — if it does, equips aren't being captured and won't be restored.
    if mod._cim_backendutils_capture_installed == nil then
        return "skip: BackendUtils capture not installed yet (backend not ready / not in keep)"
    end
    if mod._cim_backendutils_capture_installed ~= true then
        return "BackendUtils.set_loadout_item capture FAILED to install — menu equips won't be saved/restored"
    end
end)

_rt_register("persist_loadouts_gate_off_is_passthrough", function()
    -- v0.8.15-dev: the `persist_modded_loadouts` master toggle defaults OFF, and
    -- when OFF cim must NOT touch the loadout path — _capture_loadout_equip records
    -- nothing and _restore_modded_loadout no-ops, so vanilla player AND bot loadouts
    -- are byte-identical to not having cim. Pin both invariants:
    --   1. the gate helper reflects the live setting value, and
    --   2. with the toggle forced OFF, a real set_loadout_item call for a modded
    --      bid leaves _modded_loadout empty (no capture).
    if type(mod._cim_persist_loadouts_enabled) ~= "function" then
        return "persist-loadouts gate helper missing"
    end
    local cls = rawget(_G, "BackendInterfaceItemPlayfab")
    if not cls or type(cls.set_loadout_item) ~= "function" then
        return "skip: BackendInterfaceItemPlayfab.set_loadout_item not loaded (run in-keep)"
    end
    local hook_fn = cls.set_loadout_item

    local result_err
    -- The sandbox forces the toggle ON for its body; we deliberately flip it OFF
    -- INSIDE to assert the OFF behavior, and the sandbox restores everything.
    _rt_with_loadout_sandbox(function()
        mod:set("persist_modded_loadouts", false, false)
        if mod._cim_persist_loadouts_enabled() ~= false then
            result_err = "gate helper says enabled while setting is OFF"
            return
        end
        mod._cim_register_craft(_RT_FAKE_BID, {
            item_key = "es_1h_falchion", properties = {}, traits = {}, power_level = 300, rarity = "modded",
        })
        local fake_items = setmetatable({}, { __index = function() return function() end end })
        context.set_modded_loadout({})
        -- Equip a MODDED bid while the master toggle is OFF.
        pcall(hook_fn, fake_items, _RT_FAKE_BID, _RT_FAKE_CAREER, _RT_FAKE_SLOT, 1)
        local captured = context.get_modded_loadout()[_RT_FAKE_CAREER]
        if captured ~= nil and next(captured) ~= nil then
            result_err = "OFF gate leaked a capture into _modded_loadout (should be untouched)"
            return
        end
    end)
    if result_err then return result_err end
end)

_rt_register("reequip_live_api_ok", function()
    -- v0.7.67-dev (issue #22): _reequip_live_avatar re-equips the keep avatar
    -- after restore via the vanilla create_equipment_in_slot /
    -- create_attachment_in_slot API. If that API errored this session (wrong
    -- signature, called at a bad time), _cim_reequip_last_err captures it — a
    -- state-witness that the live-unit re-equip is misbehaving. nil = no error
    -- (either it worked or never ran) → pass.
    local err = mod._cim_reequip_last_err
    if err then
        return "live re-equip API errored this session: " .. tostring(err)
    end
end)

_rt_register("forge_preview_guard_present", function()
    -- v0.7.70-dev: the weave-forge weapon previewer (LootItemUnitPreviewer)
    -- spawns the selected weapon's 3D model, which HARD-CRASHES (no Lua trace)
    -- on weapons whose preview units aren't loadable in the forge world — the
    -- Trollhammer Torpedo (dr_deus_01, "torpedo cannon") being the reported
    -- case. _forge_preview_unsafe gates both spawn sites. Verify the guard is
    -- wired AND fails safe (treats anything it can't resolve as UNSAFE) so an
    -- unknown / garbage item can never reach the engine spawn.
    local fn = mod._cim_forge_preview_unsafe
    if type(fn) ~= "function" then
        return "forge preview guard (_cim_forge_preview_unsafe) missing — torpedo CTD guard not installed"
    end
    if fn(nil) ~= true then
        return "guard must treat a nil item as UNSAFE (skip preview); returned non-true"
    end
    if fn({ key = "cim_definitely_not_a_real_item_key_zzz" }) ~= true then
        return "guard must treat an unknown item key as UNSAFE (master nil); returned non-true"
    end
end)

_rt_register("weave_category_pool_guard_present", function()
    -- v0.7.75-dev: opening the forge stat editor for a weapon whose
    -- property/trait/talent table-name isn't a weave category (Trollhammer
    -- Torpedo dr_deus_01 the reported case) made vanilla _setup_menu_options do
    -- ipairs(WeaveTraits.categories[category]) on nil -> "bad argument #1 to
    -- 'ipairs' (table expected, got nil)". The guard seeds an empty {} pool for
    -- unknown categories so the picker renders empty instead of crashing. Verify
    -- the seeder is wired and idempotently fills the trait + property pools for
    -- an unknown category (then clean up the synthetic key).
    local fn = mod._cim_ensure_weave_category_pools
    if type(fn) ~= "function" then
        return "weave category pool guard (_cim_ensure_weave_category_pools) missing"
    end
    local wt = rawget(_G, "WeaveTraits")
    local wp = rawget(_G, "WeaveProperties")
    if not (wt and wt.categories and wp and wp.categories) then
        return "skip: WeaveTraits/WeaveProperties not loaded"
    end
    local cat = "cim_rt_not_a_weave_category_zzz"
    wt.categories[cat], wp.categories[cat] = nil, nil
    fn("es_mercenary", { traits = { { category = cat } }, properties = { { category = cat } } })
    local seeded = type(wt.categories[cat]) == "table" and #wt.categories[cat] == 0
        and type(wp.categories[cat]) == "table" and #wp.categories[cat] == 0
    wt.categories[cat], wp.categories[cat] = nil, nil  -- don't leave RT residue in the weave tables
    if not seeded then
        return "guard did not seed empty trait+property pools for an unknown category"
    end
end)

_rt_register("forge_freedom_settings_and_helpers_present", function()
    -- v0.8.44-dev: both freedom toggles must be registered (mod:get returns a
    -- boolean, not nil) and every helper the two surfaces route through must be
    -- exposed on the mod handle.
    if type(mod:get("allow_cw_traits")) ~= "boolean" then
        return "allow_cw_traits setting not registered"
    end
    if type(mod:get("allow_any_trait_property")) ~= "boolean" then
        return "allow_any_trait_property setting not registered"
    end
    for _, name in ipairs({
        "_cim_cw_trait_entries", "_cim_all_trait_entries", "_cim_all_property_keys",
        "_cim_trait_pool_for", "_cim_property_pool_for", "_cim_apply_forge_freedom",
        "_cim_restore_forge_freedom", "_cim_ensure_trait_twin", "_cim_ensure_property_twin",
    }) do
        if type(mod[name]) ~= "function" then
            return "missing exposed helper: " .. name
        end
    end
end)

_rt_register("native_pool_seeded_into_picker_with_toggles_off", function()
    -- #404: the Athanor picker reads WeaveTraits/WeaveProperties.categories[cat],
    -- where cat == the item's trait_table_name / property_table_name. With both
    -- freedom toggles OFF the picker must STILL be filled with the weapon's own
    -- native pool (empty picker => "menus don't appear"). Drive _cim_apply_forge_
    -- freedom for a melee-category weapon and assert the category array is non-empty
    -- afterwards, then restore so no residue leaks into real weave play.
    if mod:get("allow_cw_traits") or mod:get("allow_any_trait_property") then
        return "skip: a freedom toggle is ON (native-seed baseline test not applicable)"
    end
    local WT = rawget(_G, "WeaveTraits")
    if not (WT and WT.categories and rawget(_G, "WeaponTraits")
            and rawget(_G, "WeaponTraits").combinations and rawget(_G, "WeaponTraits").combinations.melee) then
        return "skip: WeaponTraits melee combinations not loaded"
    end
    local cat = "melee"
    local had_before = WT.categories[cat] ~= nil
    mod._cim_apply_forge_freedom({ traits = { { category = cat } }, properties = {} })
    local seeded = type(WT.categories[cat]) == "table" and #WT.categories[cat] > 0
    mod._cim_restore_forge_freedom()
    if not had_before and WT.categories[cat] ~= nil then
        WT.categories[cat] = nil  -- belt-and-suspenders: don't leave residue if restore missed it
    end
    if not seeded then
        return "native trait pool was NOT seeded into the picker category with toggles off (#404)"
    end
end)

_rt_register("cw_trait_pool_includes_boons", function()
    -- The Chaos Wastes trait set must be non-empty and contain at least one real
    -- crafting_disabled boon (that is exactly what allow_cw_traits surfaces).
    local WT = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and WT.combinations) then return "skip: WeaponTraits not loaded" end
    for _, slot_type in ipairs({ "melee", "ranged" }) do
        local entries = mod._cim_cw_trait_entries(slot_type)
        if type(entries) ~= "table" or #entries == 0 then
            return slot_type .. " cw trait set is empty (expected deus/boon traits)"
        end
        local found_boon = false
        for _, e in ipairs(entries) do
            local k = e and e[1]
            local td = k and WT.traits[k]
            if td and td.crafting_disabled then found_boon = true; break end
        end
        if not found_boon then
            return slot_type .. " cw trait set contains no crafting_disabled boon trait"
        end
    end
end)

_rt_register("issue414_cw_traits_preserve_slot_family", function()
    local WT = rawget(_G, "WeaponTraits")
    local policy = mod._cim_trait_slot_policy
    if not (WT and WT.traits and WT.combinations and policy) then
        return "skip: WeaponTraits or slot policy not loaded"
    end
    local expected = { melee = {}, ranged = {} }
    for category, pool in pairs(WT.combinations) do
        local slot_type = policy.category_slot(category)
        if slot_type and type(pool) == "table" then
            for _, entry in ipairs(pool) do
                local key = entry and entry[1]
                if key and WT.traits[key] then expected[slot_type][key] = true end
            end
        end
    end
    for _, slot_type in ipairs({ "melee", "ranged" }) do
        local actual = {}
        for _, entry in ipairs(mod._cim_cw_trait_entries(slot_type)) do
            local key = entry and entry[1]
            if key then
                if not expected[slot_type][key] then
                    return slot_type .. " pool leaked cross-slot trait " .. tostring(key)
                end
                actual[key] = true
            end
        end
        for key in pairs(expected[slot_type]) do
            if not actual[key] then
                return slot_type .. " pool omitted slot-eligible trait " .. tostring(key)
            end
        end
    end
    if #mod._cim_cw_trait_entries(nil) ~= 0 then
        return "non-weapon/accessory context received CW traits"
    end
end)

_rt_register("default_trait_pool_excludes_boons_when_toggles_off", function()
    -- With both freedom toggles OFF, a melee weapon's trait pool must still be
    -- boon-filtered (unchanged base behavior). Skip if a toggle is live-ON.
    if mod:get("allow_cw_traits") or mod:get("allow_any_trait_property") then
        return "skip: a freedom toggle is ON (default-behavior test not applicable)"
    end
    local WT = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and WT.combinations and WT.combinations.melee) then
        return "skip: WeaponTraits melee pool not loaded"
    end
    local pool = mod._cim_trait_pool_for({ trait_table_name = "melee", slot_type = "melee" })
    if type(pool) ~= "table" then return "trait pool for melee was nil" end
    for _, e in ipairs(pool) do
        local k = e and e[1]
        local td = k and WT.traits[k]
        if td and td.crafting_disabled then
            return "default melee pool leaked a crafting_disabled boon: " .. tostring(k)
        end
    end
end)

_rt_register("trait_twin_stub_has_display_name", function()
    -- Injecting a weave twin for a boon (no native weave twin) must yield an entry
    -- with a string display_name — the one field whose absence crashes the picker.
    local WT = rawget(_G, "WeaveTraits")
    local adv = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and adv and adv.traits) then return "skip: trait tables not loaded" end
    local bare
    for _, e in ipairs(mod._cim_cw_trait_entries("melee")) do
        local k = e and e[1]
        if k and adv.traits[k] and adv.traits[k].display_name and not WT.traits["weave_" .. k] then
            bare = k; break
        end
    end
    if not bare then return "skip: no injectable boon trait found" end
    local wk = mod._cim_ensure_trait_twin(bare)
    if not wk then return "ensure_trait_twin returned nil for " .. bare end
    local ok = WT.traits[wk] and type(WT.traits[wk].display_name) == "string"
    WT.traits[wk] = nil  -- injected by this test only; remove to avoid RT residue
    if not ok then return "twin for " .. bare .. " lacks a string display_name" end
end)

_rt_register("trait_twin_copies_description_pair", function()
    -- #238: an injected trait twin must copy advanced_description + description_values
    -- TOGETHER from the adventure entry, so the Athanor picker shows a description
    -- (not just the trait name). Use a boon with a description that has no native
    -- weave twin (so this exercises the INJECT path); clean up after.
    local WT = rawget(_G, "WeaveTraits")
    local adv = rawget(_G, "WeaponTraits")
    if not (WT and WT.traits and adv and adv.traits) then return "skip: trait tables not loaded" end
    local bare
    for _, e in ipairs(mod._cim_cw_trait_entries("melee")) do
        local k = e and e[1]
        if k and adv.traits[k] and adv.traits[k].advanced_description and not WT.traits["weave_" .. k] then
            bare = k; break
        end
    end
    if not bare then return "skip: no injectable boon trait with a description found" end
    local wk = mod._cim_ensure_trait_twin(bare)
    local twin = wk and WT.traits[wk]
    local advd = adv.traits[bare]
    local ok = twin
        and twin.advanced_description == advd.advanced_description
        and twin.description_values == advd.description_values
    WT.traits[wk] = nil  -- injected by this test only; clean up
    if not ok then
        return "twin for " .. bare .. " did not copy the advanced_description + description_values pair"
    end
end)

_rt_register("forge_freedom_restore_is_safe", function()
    -- Restore must always run without error (it fires on every forge exit).
    local ok, err = pcall(mod._cim_restore_forge_freedom)
    if not ok then return "restore raised: " .. tostring(err) end
end)

_rt_register("heroview_hdr_renderer_guard_failsafe", function()
    -- v0.7.71-dev: in-mission forge crashed at HeroView.hdr_renderer /
    -- hdr_top_renderer because vanilla _setup_hdr_gui only builds
    -- self._hdr_gui_data when is_in_inn (false in mission), and the forge
    -- windows dereference _hdr_gui_data.bottom/.top every frame. The accessor
    -- hooks must fall back to the view's own renderer when _hdr_gui_data is nil
    -- rather than letting vanilla index a nil. Drive the (hooked) accessors with
    -- a synthetic self that has nil _hdr_gui_data and assert no raise + fallback.
    local hero_view = rawget(_G, "HeroView")
    if type(hero_view) ~= "table" or type(hero_view.hdr_renderer) ~= "function"
        or type(hero_view.hdr_top_renderer) ~= "function" then
        return "skip: HeroView not loaded"
    end
    local r_sentinel, t_sentinel = {}, {}
    local fake = { _hdr_gui_data = nil, ui_renderer = r_sentinel, ui_top_renderer = t_sentinel }
    local ok, ret = pcall(hero_view.hdr_renderer, fake)
    if not ok then
        return "hdr_renderer guard missing — raised on nil _hdr_gui_data: " .. tostring(ret)
    end
    if ret ~= r_sentinel then
        return "hdr_renderer did not fall back to self.ui_renderer on nil _hdr_gui_data"
    end
    local ok2, ret2 = pcall(hero_view.hdr_top_renderer, fake)
    if not ok2 then
        return "hdr_top_renderer guard missing — raised on nil _hdr_gui_data: " .. tostring(ret2)
    end
    if ret2 ~= t_sentinel then
        return "hdr_top_renderer did not fall back to self.ui_top_renderer on nil _hdr_gui_data"
    end
end)

_rt_register("heroview_hdr_failed_setup_sweeps_leaked_worlds", function()
    -- v0.7.73 (Issue #73): when the in-mission _setup_hdr_gui pcall fails after a
    -- world was created but before vanilla stored it in self._hdr_gui_data, the
    -- sweep must destroy the orphaned world by name or the NEXT forge open dies
    -- on world_manager's "World already exists" fassert. Drive the sweep with a
    -- stub world manager.
    local sweep = mod._cim_sweep_leaked_hdr_worlds
    if type(sweep) ~= "function" then
        return "_cim_sweep_leaked_hdr_worlds missing (Issue #73 sweep regressed)"
    end
    local destroyed = {}
    local stub_wm = {
        has_world = function(_, name) return name == "hero_view_hdr" end,  -- only bottom leaked
        destroy_world = function(_, name) destroyed[#destroyed + 1] = name end,
    }
    local swept = sweep(stub_wm, nil)
    if swept ~= 1 or destroyed[1] ~= "hero_view_hdr" or destroyed[2] ~= nil then
        return string.format("expected exactly the leaked 'hero_view_hdr' destroyed, got swept=%s destroyed=%s,%s",
            tostring(swept), tostring(destroyed[1]), tostring(destroyed[2]))
    end
    -- With _hdr_gui_data present the worlds are referenced — destroy_hdr_gui owns
    -- them and the sweep must NOT touch anything.
    destroyed = {}
    if sweep(stub_wm, { bottom = {} }) ~= 0 or destroyed[1] ~= nil then
        return "sweep ran despite _hdr_gui_data being set (would destroy worlds destroy_hdr_gui still owns)"
    end
    -- Nil / incomplete world manager must be a safe no-op.
    if sweep(nil, nil) ~= 0 or sweep({}, nil) ~= 0 then
        return "sweep not nil-safe on missing world manager"
    end
end)

_rt_register("heroview_hdr_not_forcebuilt_in_mission", function()
    -- v0.8.16-dev (LA armoury_atlas crash): the in-mission HeroView._setup_hdr_gui
    -- hook must NOT force-build the HDR worlds anymore. Force-building them mid-
    -- mission is what lets VMF custom_textures inject Loremaster's Armoury's global
    -- `armoury_atlas` material into a fresh world that can't resolve it -> C-level
    -- assert at c_api_world.cpp:568 (bypasses the pcall -> hard crash, session
    -- b688f241). Fix B skips vanilla in mission and falls through to the
    -- hdr_renderer/hdr_top_renderer ui_renderer fallback instead.
    --
    -- Source-pattern check: the _setup_hdr_gui hook body must (a) contain the Fix B
    -- skip marker and (b) NOT contain the old "flip is_in_inn=true then pcall the
    -- vanilla builder" force-build sequence. Needles are assembled from split
    -- literals so this test's own source does not self-match. No-ops when source
    -- introspection is unavailable (deploy/bundle paths).
    local ok, info = pcall(debug.getinfo, mod._cim_sweep_leaked_hdr_worlds or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- (a) Fix B skip marker present in the hook body.
    local skip_needle = "_setup_hdr_gui skipped in mission (Fix B" .. ": avoid LA armoury_atlas HDR-world crash)"
    if not txt:find(skip_needle, 1, true) then
        return "Fix B regression: in-mission _setup_hdr_gui no longer skips vanilla — the LA armoury_atlas HDR-world crash guard is gone"
    end
    -- (b) The old force-build sequence must be gone from the _setup_hdr_gui hook.
    --     Key off two tokens that were UNIQUE to that hook body and never appeared
    --     in the still-valid _setup_gamepad_gui force-build (which keeps its own
    --     is_in_inn flip for a different, non-LA crash class): the `saved_is_in_inn`
    --     local and the post-failure HDR-world sweep call. Split the literals so this
    --     test's own source does not self-match.
    local saved_flag_needle = "saved_is_in_inn = self.is_in_inn" .. "\n    self.is_in_inn = true"
    if txt:find(saved_flag_needle, 1, true) then
        return "Fix B regression: in-mission _setup_hdr_gui still flips is_in_inn to force-build the HDR worlds (would crash on LA armoury_atlas)"
    end
    local sweep_in_hook_needle = "_cim_sweep_leaked_hdr_worlds(Managers.world" .. ", self._hdr_gui_data)"
    if txt:find(sweep_in_hook_needle, 1, true) then
        return "Fix B regression: in-mission _setup_hdr_gui still pcall-builds then sweeps the HDR worlds (force-build path is back)"
    end
end)

_rt_register("hdr_glow_widgets_suppressed_in_mission", function()
    -- v0.8.17-dev (weave_menu_* "Material not found in Gui" cascade): after Fix B
    -- drops the in-mission HDR worlds, the forge's HDR glow widgets fall through to
    -- the BASE mission renderer, which lacks the three keep-only raw materials
    -- (weave_menu_upgrade_skull_circle{,_shade}, weave_menu_athanor_upgrade_bg) ->
    -- ui_passes.lua:134 fatal. The create_ui_elements suppression must EMPTY the
    -- HDR draw arrays in mission and LEAVE THEM INTACT in the keep.
    --
    -- Drive the exposed helper synthetically against fake windows so the check runs
    -- anywhere (no live forge needed).
    local fn = mod._cim_suppress_hdr_glow_in_mission
    if type(fn) ~= "function" then return "suppression helper mod._cim_suppress_hdr_glow_in_mission not exposed" end

    -- (1) In mission (in_keep=false): populated HDR arrays must be emptied, and the
    --     helper reports it cleared.
    local mission_win = { _top_hdr_widgets = { {}, {} }, _bottom_hdr_widgets = { {}, {} } }
    local cleared = fn(mission_win, false)
    if cleared ~= true then
        return "helper did not report clearing populated HDR arrays in mission"
    end
    if #mission_win._top_hdr_widgets ~= 0 or #mission_win._bottom_hdr_widgets ~= 0 then
        return "in-mission HDR draw arrays NOT emptied — weave_menu_* materials would still resolve on the base renderer and crash"
    end

    -- (2) In the keep (in_keep=true): arrays must be left fully intact (full HDR glow).
    local keep_win = { _top_hdr_widgets = { {}, {} }, _bottom_hdr_widgets = { {}, {}, {} } }
    if fn(keep_win, true) ~= false then
        return "helper claimed to clear HDR arrays in the keep — keep forge must keep its full HDR glow"
    end
    if #keep_win._top_hdr_widgets ~= 2 or #keep_win._bottom_hdr_widgets ~= 3 then
        return "keep HDR draw arrays were mutated — keep path must be untouched"
    end

    -- (3) Idempotent / robust: a window with already-empty or missing arrays in
    --     mission is a safe no-op (no error, reports nothing cleared).
    if fn({ _top_hdr_widgets = {}, _bottom_hdr_widgets = {} }, false) ~= false then
        return "helper reported clearing already-empty arrays"
    end
    if fn({}, false) ~= false then
        return "helper not safe on a window with no HDR arrays"
    end
end)

_rt_register("hdr_cluster_glow_resuppressed_on_props_enter", function()
    -- v0.8.17-dev (Fix B2, second vector): create_ui_elements empties the HDR
    -- glow arrays, but HeroWindowWeaveProperties.on_enter then calls
    -- _create_slot_grid -> _create_cluster_background, which RE-APPENDS the raw,
    -- inn-only `athanor_skilltree_cluster_effect_*` glow widgets to
    -- _bottom_hdr_widgets AFTER suppression. The cim_debug.lua on_enter (post)
    -- hook re-runs the shared helper to re-empty it in mission. That hook is in a
    -- DIFFERENT source file, so verify the wiring it depends on instead:
    --   (1) the in-keep detector is exposed cross-file as mod._cim_is_in_keep,
    --   (2) it returns a boolean, and
    --   (3) the suppression helper, driven with that detector's CURRENT value on
    --       a synthetic props window carrying a freshly re-appended cluster-effect
    --       widget, leaves the array intact in the keep and empties it in mission.
    local in_keep = mod._cim_is_in_keep
    if type(in_keep) ~= "function" then
        return "mod._cim_is_in_keep not exposed — cim_debug on_enter re-suppression can't detect the keep (second-vector fix dead)"
    end
    local live = in_keep()
    if type(live) ~= "boolean" then
        return "mod._cim_is_in_keep did not return a boolean"
    end
    local fn = mod._cim_suppress_hdr_glow_in_mission
    if type(fn) ~= "function" then return "suppression helper not exposed" end
    -- Synthetic props window mirroring the post-_create_slot_grid state: one
    -- cluster-effect widget re-appended to _bottom_hdr_widgets.
    local props = { _top_hdr_widgets = {}, _bottom_hdr_widgets = { { _cim_rt_cluster_effect = true } } }
    fn(props, live)
    if live then
        -- In the keep the cluster glow must survive (full HDR there).
        if #props._bottom_hdr_widgets ~= 1 then
            return "keep: re-appended cluster-effect glow was wrongly stripped"
        end
    else
        -- In mission it must be re-emptied or the inn-only material faults.
        if #props._bottom_hdr_widgets ~= 0 then
            return "mission: re-appended cluster-effect glow NOT re-suppressed — athanor_skilltree_cluster_effect_* would fault on the base renderer"
        end
    end
end)

_rt_register("skilltree_ring_widgets_suppressed_in_mission", function()
    -- v0.8.19-dev (Fix B5, ui_passes.lua:805 "Material 'athanor_skilltree_ring_3'
    -- not found in Gui", in-mission skill tree): the NON-HDR _bottom_widgets array
    -- (drawn on the BASE mission ui_renderer) carries raw, inn-only skill-tree
    -- decorations alongside FUNCTIONAL widgets; the helper must rebuild the array
    -- minus ONLY the raw textures and leave the keep fully intact.
    -- v0.8.49-dev (#83, session 9cc7ebf2) EXTENDED: (a) the raw family now also
    -- includes forge_overview_top_glow_effect_* (panel smoke, the crash the first
    -- in-mission Athanor test hit); (b) uv-texture widgets carry
    -- content.texture_id as a TABLE ({texture_id=..., uvs=...}) and must still be
    -- matched; (c) the prune covers _top_widgets too (panel's third draw loop,
    -- holding raw athanor_power_bg / athanor_decoration_corner).
    local fn = mod._cim_suppress_skilltree_rings_in_mission
    if type(fn) ~= "function" then return "suppression helper mod._cim_suppress_skilltree_rings_in_mission not exposed" end

    local function make_win()
        return {
            _bottom_widgets = {
                { content = { texture_id = "athanor_background_write_mask" } },  -- raw write-mask, DROP in mission (the 7th crash vector)
                { content = { texture_id = "athanor_skilltree_ring_1" } },       -- raw decoration, drop
                { content = { texture_id = "athanor_skilltree_ring_3" } },       -- raw decoration, drop (earlier reported crash)
                { content = { texture_id = "athanor_skilltree_background" } },    -- raw decoration, drop
                { content = { texture_id = "athanor_skilltree_cluster_2" } },     -- raw decoration, drop
                { content = { texture_id = { texture_id = "forge_overview_top_glow_effect_smoke_1", uvs = {{0,0},{1,1}} } } }, -- raw uv-table smoke (session 9cc7ebf2 crash), drop
                { content = { texture_id = "athanor_skilltree_slot_1" } },        -- atlas-backed slot, KEEP (convergent rule must not over-prune)
                { content = { texture_id = "edge_fade_small" } },                 -- functional (atlas, non-athanor), keep
                { content = {} },                                                -- viewport_background rect (no texture_id), keep
            },
            _top_widgets = {
                { content = { texture_id = "athanor_power_bg" } },                -- raw power-bar bg (panel top array), drop
                { content = { texture_id = { texture_id = "athanor_decoration_corner", uvs = {{1,0},{0,1}} } } }, -- raw uv-table corner, drop
                { content = { texture_id = "athanor_skilltree_slot_2" } },        -- atlas-backed slot, keep
                { content = { text = "essence_counter" } },                       -- functional text widget (no texture_id), keep
            },
        }
    end

    -- (1) In mission (in_keep=false): raw textures dropped from BOTH arrays,
    --     functional widgets survive, helper reports removal.
    local mission_win = make_win()
    local removed = fn(mission_win, false)
    if removed ~= true then
        return "helper did not report removing raw forge decorations in mission"
    end
    if #mission_win._bottom_widgets ~= 3 then
        return "in-mission _bottom_widgets not filtered to exactly the 3 keep-safe widgets (slot + edge_fade + viewport rect); raw textures would still resolve on the base renderer and crash"
    end
    if #mission_win._top_widgets ~= 2 then
        return "in-mission _top_widgets not filtered to exactly the 2 keep-safe widgets (slot + text); raw athanor_power_bg/decoration_corner would fault on ui_top_renderer (the latent panel crash)"
    end
    for _, arr in ipairs({ mission_win._bottom_widgets, mission_win._top_widgets }) do
        for _, w in ipairs(arr) do
            local tid = w.content and w.content.texture_id
            if type(tid) == "table" then tid = tid.texture_id end
            if type(tid) == "string" then
                local raw_athanor = tid:sub(1, 8) == "athanor_" and tid:sub(1, 22) ~= "athanor_skilltree_slot"
                local raw_smoke = tid:sub(1, 31) == "forge_overview_top_glow_effect_"
                if raw_athanor or raw_smoke then
                    return "a raw inn-only texture survived the in-mission filter: " .. tid
                end
            end
        end
    end

    -- (2) In the keep (in_keep=true): both arrays left fully intact.
    local keep_win = make_win()
    if fn(keep_win, true) ~= false then
        return "helper claimed to filter draw arrays in the keep — keep forge must keep its full decoration"
    end
    if #keep_win._bottom_widgets ~= 9 or #keep_win._top_widgets ~= 4 then
        return "keep draw arrays were mutated — keep path must be untouched"
    end

    -- (3) Idempotent / robust: empty or missing arrays in mission are a safe no-op.
    if fn({ _bottom_widgets = {}, _top_widgets = {} }, false) ~= false then
        return "helper reported filtering already-empty draw arrays"
    end
    if fn({}, false) ~= false then
        return "helper not safe on a window with no draw arrays"
    end
end)

_rt_register("hdr_bloom_setscalar_skipped_in_mission", function()
    -- v0.8.18-dev (Fix B3, panel.lua:392 set_scalar nil crash, crashify 12a6d563):
    -- HeroWindowWeaveForgePanel / HeroWindowWeaveProperties run a per-frame bloom
    -- pulse (_set_background_bloom_intensity) that reads _widgets_by_name directly
    -- and writes a material scalar on parent:hdr_renderer().gui. After Fix B that
    -- renderer is the base mission Gui, which lacks the inn-only weave_menu_* wheel
    -- materials, so Gui.material(...) returns nil and Material.set_scalar(nil, ...)
    -- fatals. The guard must SKIP vanilla in mission and RUN it in the keep.
    --
    -- Source-pattern check (the live hook can't be driven synthetically — it
    -- dereferences a real HDR Gui — so assert (1) the decision helper is exposed
    -- and gates on the keep, and (2) the hook is registered with the skip path
    -- for BOTH windows).
    local decide = mod._cim_skip_bloom_intensity_in_mission
    if type(decide) ~= "function" then
        return "decision helper mod._cim_skip_bloom_intensity_in_mission not exposed (Fix B3 dead)"
    end
    -- In the keep the bloom pulse must run (helper returns false -> don't skip).
    -- Drive through the real _is_in_keep by checking it agrees with the live state.
    local in_keep = _is_in_keep()
    local skip = decide({})
    if in_keep and skip ~= false then
        return "in keep: bloom-intensity skip helper returned true — would wrongly drop the keep's HDR bloom pulse"
    end
    if not in_keep and skip ~= true then
        return "in mission: bloom-intensity skip helper returned false — Material.set_scalar(nil,...) would fatal on the base mission renderer"
    end
    -- Hook presence: the skip guard must be wired on both windows' bloom method.
    -- Verify via the mod source (the bodies are closures, so check the registration
    -- pattern is intact in the loaded file text is not available at runtime; instead
    -- confirm the two target methods still exist on the vanilla classes so a future
    -- rename surfaces here).
    local panel = rawget(_G, "HeroWindowWeaveForgePanel")
    local properties = rawget(_G, "HeroWindowWeaveProperties")
    if type(panel) ~= "table"
        or type(panel._set_background_bloom_intensity) ~= "function" then
        return "HeroWindowWeaveForgePanel._set_background_bloom_intensity missing — bloom-crash guard target renamed/gone"
    end
    if type(properties) ~= "table"
        or type(properties._set_background_bloom_intensity) ~= "function" then
        return "HeroWindowWeaveProperties._set_background_bloom_intensity missing — bloom-crash guard target renamed/gone"
    end
end)

_rt_register("hdr_upgrade_anim_skipped_in_mission", function()
    -- v0.8.18-dev (Fix B4, second deref site of the same B3 crash class): the
    -- forge-upgrade "upgrade" transition animation's HDR closures deref the
    -- inn-only weave_menu_* materials via params.parent:hdr_renderer().gui; after
    -- Fix B that Gui lacks them in mission -> Material.set_scalar(nil,...) fatal.
    -- The guard must DROP only the "upgrade" animation, only in mission, only on
    -- the two windows whose upgrade anim touches HDR materials.
    local decide = mod._cim_skip_upgrade_anim_in_mission
    if type(decide) ~= "function" then
        return "decision helper mod._cim_skip_upgrade_anim_in_mission not exposed (Fix B4 dead)"
    end
    local in_keep = _is_in_keep()
    -- (1) Non-"upgrade" animations must NEVER be skipped (they're HDR-free; e.g.
    --     "on_enter" / text fades drive the normal forge fade-in).
    if decide("on_enter") ~= false then
        return "guard skipped a non-upgrade animation (on_enter) — would break the forge fade-in"
    end
    -- (2) The "upgrade" animation: skipped in mission, run in the keep.
    local skip_upgrade = decide("upgrade")
    if in_keep and skip_upgrade ~= false then
        return "in keep: upgrade-anim guard returned true — would drop the keep's upgrade flourish"
    end
    if not in_keep and skip_upgrade ~= true then
        return "in mission: upgrade-anim guard returned false — the upgrade flourish's HDR set_scalar(nil,...) would fatal"
    end
    -- (3) Target methods still exist (a future rename surfaces here).
    local overview = rawget(_G, "HeroWindowWeaveForgeOverview")
    local weapons = rawget(_G, "HeroWindowWeaveForgeWeapons")
    if type(overview) ~= "table"
        or type(overview._start_transition_animation) ~= "function" then
        return "HeroWindowWeaveForgeOverview._start_transition_animation missing — upgrade-anim guard target renamed/gone"
    end
    if type(weapons) ~= "table"
        or type(weapons._start_transition_animation) ~= "function" then
        return "HeroWindowWeaveForgeWeapons._start_transition_animation missing — upgrade-anim guard target renamed/gone"
    end
end)

_rt_register("forge_preview_guard_allows_loaded_weapon", function()
    -- Complement to forge_preview_guard_present: a normal weapon whose units ARE
    -- loadable must NOT be flagged unsafe, or we'd strip the 3D preview from
    -- every weapon. Only meaningful inside the modded forge (the weapon's
    -- display unit is resident only there) — skips otherwise.
    local fn = mod._cim_forge_preview_unsafe
    if type(fn) ~= "function" then return "guard missing" end
    if not context.get_custom_forge_active() then
        return "skip: not in modded forge (preview units only resident there)"
    end
    local items_backend = Managers.backend and Managers.backend:get_interface("items")
    local pl = Managers.player and Managers.player:local_player()
    if not (items_backend and pl) then return "skip: backend/player not ready" end
    local profile = SPProfiles[pl:profile_index()]
    local career = profile and profile.careers[pl:career_index()]
    if not career then return "skip: no career" end
    -- Melee slot: a standard melee weapon is never the torpedo, so it should be
    -- previewable when the forge is open.
    local bid = items_backend:get_loadout_item_id(career.name, "slot_melee")
    local item = bid and items_backend:get_item_from_id(bid)
    if not item then return "skip: no melee item equipped" end
    if fn(item) == true then
        return "guard flagged a normally-equipped melee weapon as unsafe — would wrongly strip its 3D preview"
    end
end)

_rt_register("rpc_schema_gate_drops_on_mismatch", function()
    -- audit 2026-06-07 (v0.7.72-dev): the cim_modded_slot RPC must carry a schema
    -- version (CIM_RPC_SCHEMA) as its first wire arg and the receiver must DROP a
    -- mismatched payload without mutating _cim_modded_slot_state (VMF_RECIPES § 10).
    -- Drives the exposed receiver synthetically: a wrong schema_version must leave
    -- state untouched; the correct one must record the per-slot flag.
    local recv = mod._cim_rpc_modded_slot
    local state = mod._cim_modded_slot_state
    if type(recv) ~= "function" then return "receiver mod._cim_rpc_modded_slot not exposed" end
    if type(state) ~= "table" then return "state table mod._cim_modded_slot_state not exposed" end

    -- Synthetic identifiers unlikely to collide with any live peer/slot.
    local FAKE_PEER, FAKE_LPID, FAKE_SLOT = "rt_schema_peer", 7, "slot_melee"
    local uid = tostring(FAKE_PEER) .. ":" .. tostring(FAKE_LPID)
    local had_uid = state[uid] ~= nil          -- preserve any pre-existing entry
    local saved = state[uid]
    state[uid] = nil

    local result_err
    -- (1) Mismatched schema -> dropped, no state write.
    recv(FAKE_PEER, CIM_RPC_SCHEMA + 1, FAKE_PEER, FAKE_LPID, FAKE_SLOT, true)
    if state[uid] ~= nil then
        result_err = "schema-mismatch packet was NOT dropped — receiver mutated _cim_modded_slot_state"
    end

    -- (2) Matching schema -> flag recorded.
    if not result_err then
        recv(FAKE_PEER, CIM_RPC_SCHEMA, FAKE_PEER, FAKE_LPID, FAKE_SLOT, true)
        if not (state[uid] and state[uid][FAKE_SLOT] == true) then
            result_err = "matching-schema packet did not record the per-slot modded flag"
        end
    end

    -- Teardown: restore whatever was there before (don't leak the synthetic entry).
    if had_uid then state[uid] = saved else state[uid] = nil end

    return result_err
end)

_rt_register("issue88_inventory_access_flip_is_scoped", function()
    -- Issue #88: open_standard_crafting must NOT permanently mutate
    -- InventorySettings.inventory_loadout_access_supported_game_modes (that
    -- leaked the loadout inventory onto the ESC-menu backout mid-mission). The
    -- flip is now scoped to cim's own HeroView open via the one-shot
    -- `_cim_open_standard_inv_pending` flag + a save/restore HeroView.on_enter
    -- hook. This source-pattern guard fails if the persistent flip is
    -- reintroduced or the scoped pieces are removed. Degrades to a no-op when
    -- source introspection is unavailable (bundle/deploy path).
    -- (#511) Runtime marker: the anchor must be wired (proves the module loaded).
    if type(mod.open_standard_crafting) ~= "function" then
        return "#88 regression: mod.open_standard_crafting not wired (standard-crafting module failed to load)"
    end
    local ok, info = pcall(debug.getinfo, mod.open_standard_crafting or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- The one-shot handshake flag must be set in open_standard_crafting.
    if not txt:find("_cim_open_standard_inv_pending", 1, true) then
        return "Issue #88 regression: one-shot inventory-access flag _cim_open_standard_inv_pending missing"
    end
    -- The scoped HeroView.on_enter hook (assembled from two literals so this
    -- test's own source doesn't self-match) must exist.
    local hook_needle = 'mod:hook("' .. 'HeroView", "on_enter"'
    if not txt:find(hook_needle, 1, true) then
        return "Issue #88 regression: scoped HeroView.on_enter inventory-access hook missing"
    end
    -- And the restore must be present (modes saved + put back).
    if not txt:find("saved_adventure", 1, true) then
        return "Issue #88 regression: inventory-access restore (saved_adventure) missing — flip may no longer be scoped"
    end
    return nil
end)

_rt_register("issue96_allow_in_mission_widget_moved_to_gut", function()
    -- Issue #96 epilogue (2026-07-02, user direction): the "Allow standard
    -- crafting bench in mission" WIDGET must NOT exist in cim's data tree at
    -- all - the option lives in gut's In-Mission Menus group (cim-gated
    -- there), and gut writes through to cim's `allow_in_mission` SETTING.
    -- Two invariants:
    --   1. no `setting_id = "allow_in_mission"` widget in _data.lua, and
    --   2. the main-lua readers still honor mod:get("allow_in_mission")
    --      (gut's write-through target - removing the readers would silently
    --      orphan gut's toggle).
    -- Source-pattern guard; degrades to a no-op when source introspection is
    -- unavailable (bundle/deploy path).
    -- (#511) Runtime marker: the anchor must be wired (proves the module loaded).
    if type(mod.open_standard_crafting) ~= "function" then
        return "allow_in_mission regression: mod.open_standard_crafting not wired (standard-crafting module failed to load)"
    end
    local ok, info = pcall(debug.getinfo, mod.open_standard_crafting or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src_path:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip
    local data_txt = read_all(dir .. "crafting_in_modded_data.lua")
    if data_txt then
        -- needle split so this test's own source never self-matches
        if data_txt:find('setting_id = ' .. '"allow_in_mission"', 1, true) then
            return "Issue #96 regression: allow_in_mission widget re-appeared in _data.lua — it must live ONLY in gut's In-Mission Menus"
        end
    end
    local main_txt = read_all(src_path)
    if main_txt then
        if not main_txt:find('mod:get("allow_in_mission")', 1, true) then
            return "Issue #96 regression: no mod:get(\"allow_in_mission\") reader left in main lua — gut's write-through toggle is orphaned"
        end
    end
    return nil
end)

_rt_register("forge_mission_env_picker_prefers_resident", function()
    -- v0.8.48-dev (#83): the mission forge/preview worlds must get their
    -- shading env from the residency-probed picker, preferring the studio-lit
    -- ui_store_preview, then ui_hdr, then the boot-assets environment/blank
    -- (engine default, resident everywhere). Drive the exposed helper with
    -- injected probes so the preference order is pinned without a live engine.
    if type(mod._cim_pick_mission_env) ~= "function" then
        return "mod._cim_pick_mission_env missing"
    end
    local pick = mod._cim_pick_mission_env(function(n) return n == "environment/ui_store_preview" end)
    if pick ~= "environment/ui_store_preview" then
        return "expected ui_store_preview when resident, got " .. tostring(pick)
    end
    pick = mod._cim_pick_mission_env(function(n) return n == "environment/ui_hdr" end)
    if pick ~= "environment/ui_hdr" then
        return "expected ui_hdr when only it is resident, got " .. tostring(pick)
    end
    pick = mod._cim_pick_mission_env(function() return false end)
    if pick ~= "environment/blank" then
        return "expected environment/blank final fallback, got " .. tostring(pick)
    end
    pick = mod._cim_pick_mission_env(function() return true end)
    if pick ~= "environment/ui_store_preview" then
        return "expected ui_store_preview to win when everything is resident, got " .. tostring(pick)
    end
end)

_rt_register("customization_variation_pin_decision", function()
    -- v0.8.48-dev (#83 / #228 class): the _update_environment hook must allow
    -- vanilla's per-weapon blend variation ONLY on an env that defines it
    -- (ui_store_preview) or after cosmetics_tweaker's #235 re-point. An
    -- undefined variation on any other env is a native ShadingEnvironment.blend
    -- access violation — the fatal that forced the v0.8.23 keep-only gate.
    if type(mod._cim_env_allows_variation) ~= "function" then
        return "mod._cim_env_allows_variation missing"
    end
    if not mod._cim_env_allows_variation("environment/ui_store_preview", false) then
        return "ui_store_preview must allow vanilla's variation (it defines weapons_default_01)"
    end
    if mod._cim_env_allows_variation("environment/ui_hdr", false) then
        return "ui_hdr must NOT allow per-weapon variations (undefined variation = blend AV, #228)"
    end
    if mod._cim_env_allows_variation("environment/blank", false) then
        return "environment/blank must NOT allow per-weapon variations"
    end
    if not mod._cim_env_allows_variation("environment/ui_hdr", true) then
        return "a cosmetics_tweaker re-point (cos_preview_env_repointed) must unlock the variation"
    end
    if mod._cim_env_allows_variation(nil, false) then
        return "nil env must pin to default (fail-safe)"
    end
end)

_rt_register("open_forge_gate_honors_allow_in_mission", function()
    -- v0.8.48-dev (#83): the v0.8.23 HARD keep-only gate in mod.open_forge is
    -- replaced by the allow_in_mission opt-in. Source-pattern check so the
    -- hard gate can't silently come back. Needles split so this test's own
    -- source never self-matches. No-ops when source introspection is
    -- unavailable (bundle/deploy path).
    -- (#511) Runtime marker: the anchor must be wired (proves the module loaded).
    if type(mod.open_forge) ~= "function" then
        return "#83 regression: mod.open_forge not wired (forge module failed to load)"
    end
    local ok, info = pcall(debug.getinfo, mod.open_forge or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- (a) the opt-in gate shape must be present TWICE (open_forge AND
    --     open_standard_crafting), plain-text finds, no pattern escapes.
    local optin_needle = 'if not in_keep and not mod:get("allow_in_mission")' .. ' then'
    local first = txt:find(optin_needle, 1, true)
    local second = first and txt:find(optin_needle, first + 1, true)
    if not second then
        return "#83 regression: expected the allow_in_mission opt-in gate in BOTH open_forge and open_standard_crafting"
    end
    -- (b) the old hard-gate echo must be gone.
    local hard_needle = "The Athanor (weave forge) only opens" .. " in the Keep."
    if txt:find(hard_needle, 1, true) then
        return "#83 regression: the v0.8.23 hard keep-only gate echo is back in open_forge"
    end
end)

_rt_register("cim390_cwv_craft_render_fix", function()
    -- (#390) CWV variants crafted via cim rendered as the BASE weapon (Nordland
    -- Claymore -> Bretonnian sword; Kruber Rapier kept the Saltzpyre pistol),
    -- because the crafted copy got a guid backend_id that matched none of CWV's
    -- render-rescue hooks. Two guards:
    --   (a) synthetic-template injection is keyed on item KEY, not item_type,
    --       so every CWV family member is individually craftable (was: one
    --       random member per item_type).
    --   (b) the cim-side units rescue hook is installed, forcing the variant's
    --       per-hand meshes onto crafted CWV copies (mesh correct even before
    --       the CWV-side backend_id pattern widen lands).
    -- Both flags are set at load time in standard_forge.lua.
    if mod._cim390_inject_key_keyed ~= true then
        return "#390 regression: template injection is not key-keyed (CWV families collapse to one random craftable member)"
    end
    -- BackendUtils is a plain table loaded at boot; if the rescue hook didn't
    -- install, BackendUtils was somehow unavailable at load (never observed) —
    -- surface it rather than silently ship the base-mesh bug.
    if mod._cim390_units_rescue_installed ~= true then
        return "#390 regression: cim-side get_item_units rescue for crafted CWV variants not installed (crafted copies render base mesh)"
    end
end)

_rt_register("console_craft_item_nil_recipe_resolves", function()
    -- (#407) The console/gamepad "Craft Item" page calls parent:craft(items) with
    -- recipe_override=nil (craft_page_craft_item_console.lua:325) and relies on
    -- vanilla backend recipe auto-detection. cim's craft() hook can't fall through
    -- to vanilla (EAC kick), so it re-derives the recipe from the dropped item's
    -- slot_type. Before the fix, cim dropped EVERY console craft-item — no CWV
    -- (or any) weapon could be crafted on the gamepad UI. The PC page passes
    -- self._recipe_name explicitly, which is why crafting worked on M+K only.
    local f = mod._cim407_craft_item_recipe_for_slot
    if type(f) ~= "function" then
        return "mod._cim407_craft_item_recipe_for_slot missing — console craft-item nil-recipe fix regressed; gamepad crafting drops every item"
    end
    if f("melee")    ~= "craft_weapon"   then return "melee -> "    .. tostring(f("melee"))    .. " (want craft_weapon)"   end
    if f("ranged")   ~= "craft_weapon"   then return "ranged -> "   .. tostring(f("ranged"))   .. " (want craft_weapon)"   end
    if f("necklace") ~= "craft_necklace" then return "necklace -> " .. tostring(f("necklace")) .. " (want craft_necklace)" end
    if f("ring")     ~= "craft_charm"    then return "ring -> "     .. tostring(f("ring"))     .. " (want craft_charm)"    end
    if f("trinket")  ~= "craft_trinket"  then return "trinket -> "  .. tostring(f("trinket"))  .. " (want craft_trinket)"  end
    -- Non-craftable slots must return nil so the craft still drops cleanly (no
    -- accidental synth for hat/skin/frame drops).
    if f("hat") ~= nil or f("skin") ~= nil then
        return "non-craftable slot resolved to a recipe — would mis-synth a cosmetic drop"
    end
    -- Every resolved recipe name must have a live synth, or the craft() hook
    -- would set recipe_override then still drop at the synth-lookup stage.
    local synth_names = mod._cim407_synth_names_for_rt
    if type(synth_names) == "table" then
        for _, slot in ipairs({ "melee", "ranged", "necklace", "ring", "trinket" }) do
            local rn = f(slot)
            if not synth_names[rn] then
                return string.format("resolved recipe %s (slot %s) has no synth registered", tostring(rn), slot)
            end
        end
    end
end)

_rt_register("issue562_auto_equip_contract", function()
    -- The feature is deliberately weapon-only: exact primary/secondary slot
    -- mapping, never jewelry/accessory paths. Pin the pure dispatch contract so
    -- future craft-surface edits cannot silently equip a different slot.
    local slot_type = mod._cim_auto_equip_slot_type
    if type(slot_type) ~= "function" then
        return "#562 auto-equip slot resolver missing"
    end
    if slot_type("slot_melee") ~= "melee" then return "slot_melee no longer maps to melee" end
    if slot_type("slot_ranged") ~= "ranged" then return "slot_ranged no longer maps to ranged" end
    if slot_type("slot_necklace") ~= nil or slot_type("slot_ring") ~= nil
       or slot_type("slot_trinket_1") ~= nil then
        return "#562 auto-equip leaked onto an accessory slot"
    end
    if type(mod._cim_auto_equip_crafted_weapon) ~= "function" then
        return "#562 exact-bid auto-equip helper missing"
    end

    -- Verify the realized VMF widget, including the user-requested default ON.
    local ok, data = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded/crafting_in_modded_data")
    if not ok or type(data) ~= "table" then
        return "#562 settings data did not load"
    end
    local found
    local function walk(node)
        if type(node) ~= "table" or found then return end
        if node.setting_id == "auto_equip_new_weapons" then found = node return end
        for _, child in ipairs(node.widgets or {}) do walk(child) end
        for _, child in ipairs(node.sub_widgets or {}) do walk(child) end
        if node.options then walk(node.options) end
    end
    walk(data)
    if not found then return "#562 auto_equip_new_weapons widget missing" end
    if found.type ~= "checkbox" then return "#562 auto-equip setting is not a checkbox" end
    if found.default_value ~= true then return "#562 auto-equip setting no longer defaults ON" end

    -- If the feature fired this session, its state witness must preserve the
    -- exact crafted bid and one of the two legal target slots.
    local last = mod._cim_auto_equip_last
    if last then
        if not last.backend_id then return "#562 state witness lost the exact crafted backend id" end
        if slot_type(last.slot_name) == nil then return "#562 state witness recorded an invalid target slot" end
        if type(last.loadout_index) ~= "number" then return "#562 state witness lost the selected loadout index" end
    end
end)

end
