-- _cim_regression_forge_surfaces.lua - late forge-surface regression checks for CIM dev
--
-- Owns the ordered runtime invariants that exercise Athanor, standard-forge,
-- inventory, loadout, and mission-safe presentation surfaces after every
-- production owner is installed. It depends on the core regression installer's
-- exact loadout-sandbox helper and validates its narrow context before it can
-- register a partial suffix.
--
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via:
-- scripts/mods/crafting_in_modded_dev/_cim_regression_forge_surfaces

return function(context)
    assert(type(context) == "table", "CIM forge-surface regression context must be a table")
    assert(type(context.mod) == "table", "CIM forge-surface regression mod is required")
    assert(type(context.rt_register) == "function", "CIM forge-surface rt_register is required")
    assert(type(context.rt_src_read) == "function", "CIM forge-surface rt_src_read is required")
    assert(type(context.ensure_item_adventure_visible) == "function",
        "CIM forge-surface ensure_item_adventure_visible is required")
    assert(type(context.is_in_keep) == "function", "CIM forge-surface is_in_keep is required")
    assert(type(context.rpc_schema) == "number", "CIM forge-surface rpc_schema is required")
    assert(type(context.with_loadout_sandbox) == "function",
        "CIM forge-surface with_loadout_sandbox is required")
    assert(type(context.get_custom_forge_active) == "function",
        "CIM forge-surface get_custom_forge_active is required")
    assert(type(context.get_forged_weapons) == "function",
        "CIM forge-surface get_forged_weapons is required")
    assert(type(context.get_modded_loadout) == "function",
        "CIM forge-surface get_modded_loadout is required")
    assert(type(context.set_modded_loadout) == "function",
        "CIM forge-surface set_modded_loadout is required")

    local mod = context.mod
    local _rt_register = context.rt_register
    local _rt_src_read = context.rt_src_read
    local _ensure_item_adventure_visible = context.ensure_item_adventure_visible
    local _is_in_keep = context.is_in_keep
    local _AccessoryPanel = context.accessory_panel
    local _OVERVIEW_BTN_RENDER_FIELD = context.overview_btn_render_field
    local _OVERVIEW_DRAWN_FIELDS = context.overview_drawn_fields
    local CIM_RPC_SCHEMA = context.rpc_schema
    local _rt_with_loadout_sandbox = context.with_loadout_sandbox
    local _forge_ui_source_anchor = mod._cim_forge_ui_owner
        and mod._cim_forge_ui_owner.apply_ui_polish

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
    -- regression would silently ship. Do NOT `mod:dofile` modded_rarities.lua
    -- from this check: that file owns live hooks, and re-executing it caused
    -- issue #823's duplicate Localize/_state_setup_upgrade/on_enter/get_weapon_pool
    -- registrations. Read only the API table published during the single
    -- production load.
    local overrides = mod._cim_rarity_loc_overrides
    if type(overrides) ~= "table" then
        return "modded_rarities localization override API missing — do not reload hook-owning module from regression checks"
    end
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
    if overrides.crafting_recipe_craft_jewellery ~= "Craft Accessories" then
        return "crafting_recipe_craft_jewellery override table no longer maps to Craft Accessories"
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
    if type(_forge_ui_source_anchor) ~= "function" then
        return "forge UI owner source anchor missing"
    end
    local ok, info = pcall(debug.getinfo, _forge_ui_source_anchor, "S")
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

_rt_register("adventure_visible_preserves_availability_and_clears_mechanism", function()
    -- #661: _ensure_item_adventure_visible must preserve can_wield byte-for-byte
    -- (WT/native/CWV own availability + paired career actions) while clearing a
    -- non-adventure `mechanisms` field (e.g. {"versus"}) so the
    -- Adventure inventory grid stops hiding the crafted item. Tested against a
    -- throwaway fake key (rawset/rawget bypass the ItemMasterList Crashify
    -- metatable), removed afterward so there's zero side effect on real data.
    local IML = rawget(_G, "ItemMasterList")
    if not IML then return "skip: ItemMasterList not loaded" end
    local fake_key = "__cim_rt_fake_advvis__"
    rawset(IML, fake_key, { can_wield = { "es_mercenary", "es_huntsman" }, mechanisms = { "versus" } })
    local ok, errmsg = pcall(function()
        _ensure_item_adventure_visible(fake_key, "es_questingknight")
        _ensure_item_adventure_visible(fake_key, "es_questingknight")
        _ensure_item_adventure_visible(fake_key, "es_mercenary")
    end)
    local entry = IML[fake_key] or {}
    local cw = entry.can_wield or {}
    local mechanisms_cleared = (entry.mechanisms == nil)
    rawset(IML, fake_key, nil)  -- cleanup: no lingering fake entry
    if not ok then return "adventure-visible helper errored: " .. tostring(errmsg) end
    if #cw ~= 2 or cw[1] ~= "es_mercenary" or cw[2] ~= "es_huntsman" then
        return "CIM mutated provider-owned can_wield — career action contract can diverge"
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

_rt_register("issue1117_bulk_accessory_button_layout", function()
    local state = mod._cim_temper_runtime_state
    local apply = state and state.set_accessory_button_presentation
    if type(apply) ~= "function" then
        return "#1117 Temper Item button-presentation owner is unavailable"
    end
    local button = {
        content = { icon = "athanor_icon_upgrade" },
        style = {
            title_text = { offset = { -15, 1, 6 }, default_offset = { 20, 0, 6 } },
            title_text_disabled = { offset = { -16, 1, 6 }, default_offset = { 20, 0, 6 } },
            title_text_shadow = { offset = { -13, -1, 5 }, default_offset = { 22, -2, 5 } },
        },
    }
    apply(button, true)
    local style = button.style
    if button.content.icon ~= nil
            or style.title_text.offset[1] ~= 20
            or style.title_text_disabled.offset[1] ~= 20
            or style.title_text_shadow.offset[1] ~= 22 then
        return "#1117 accessory state retained an arrow or non-centered title"
    end
    apply(button, false)
    if button.content.icon ~= "athanor_icon_upgrade" then
        return "#1117 weapon state did not restore the exact native arrow"
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
    local unmapped = policy.unmapped_boon_categories(WT.combinations, WT.traits)
    if #unmapped > 0 then
        return "slot policy omitted boon-bearing categor"
            .. (#unmapped == 1 and "y " or "ies ") .. table.concat(unmapped, ",")
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

_rt_register("issue83_dynamic_forge_widget_material_closure", function()
    local policy = mod._cim83_forge_widget_policy
    if type(policy) ~= "table" or type(policy.sanitize_widgets) ~= "function" then
        return "#83 dynamic forge widget policy missing"
    end

    -- Keep must return before consulting even the pure sanitizer. Temporarily
    -- install a spy to prove the production helper is an exact no-op there.
    local production = mod._cim83_sanitize_dynamic_forge_widgets
    if type(production) ~= "function" then
        return "#83 production dynamic-widget sanitizer missing"
    end
    local saved_policy = mod._cim83_forge_widget_policy
    local policy_called = false
    mod._cim83_forge_widget_policy = {
        sanitize_widgets = function()
            policy_called = true
            return {}
        end,
    }
    local ok_keep, keep_result = pcall(production, {}, true)
    mod._cim83_forge_widget_policy = saved_policy
    if not ok_keep or keep_result ~= nil or policy_called then
        return "Keep path consulted or ran the mission-only widget policy"
    end

    -- Mirrors the post-_setup_weapon_stats shape. This widget is reachable only
    -- through `_scrollbars.stats.list_widgets`, so static create_ui_elements
    -- pruning cannot see it. Suppressing the raw arch pass must not suppress its
    -- safe slot icon, text, or hotspot siblings.
    local arch_pass = { pass_type = "rotated_texture", style_id = "arch",
        texture_id = "arch_texture" }
    local slot_pass = { pass_type = "texture", style_id = "slot",
        texture_id = "slot_texture" }
    local text_pass = { pass_type = "text", style_id = "title", text_id = "title" }
    local hotspot_pass = { pass_type = "hotspot", content_id = "hotspot" }
    local window = { _scrollbars = { stats = { list_widgets = { {
        element = { passes = { arch_pass, slot_pass, text_pass, hotspot_pass } },
        content = {
            arch_texture = "icon_block_arch_masked",
            slot_texture = "icon_block",
            title = "Block angle",
            hotspot = {},
        },
        style = { arch = {}, slot = { masked = true }, title = {} },
    } } } } }
    local widgets = window._scrollbars.stats.list_widgets
    local report = policy.sanitize_widgets(widgets, function(texture)
        return texture == "icon_block"
    end)
    local passes = widgets[1].element.passes
    if report.suppressed ~= 1 or passes[1].content_check_function() ~= false then
        return "non-resident dynamic block-arch pass was not suppressed"
    end
    if passes[2].content_check_function ~= nil
            or passes[3].content_check_function ~= nil
            or passes[4].content_check_function ~= nil then
        return "safe texture/text/hotspot sibling was modified"
    end
    if arch_pass.content_check_function ~= nil then
        return "shared source pass mutated instead of instance-local clone-on-write"
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
    -- #404: static forge safety must be pass-level and renderer-proven. Prefix
    -- pruning removed atlas-backed panels such as athanor_power_bg and
    -- athanor_decoration_corner. Keep remains an unconditional no-op.
    local fn = mod._cim_suppress_skilltree_rings_in_mission
    if type(fn) ~= "function" then
        return "renderer-proof static forge suppression helper not exposed"
    end
    local keep_widget = { marker = true }
    local keep_win = { _bottom_widgets = { keep_widget }, _top_widgets = {} }
    if fn(keep_win, true) ~= false or keep_win._bottom_widgets[1] ~= keep_widget then
        return "keep static forge widgets were mutated"
    end
    if type(mod._cim83_forge_widget_policy) ~= "table"
            or type(mod._cim83_forge_widget_policy.sanitize_widgets) ~= "function"
            or type(mod._cim_athanor_icon_policy) ~= "table"
            or type(mod._cim_athanor_icon_policy.renderer_has_texture) ~= "function" then
        return "static forge renderer-material proof dependencies unavailable"
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

_rt_register("issue921_tab_rarity_state_is_tristate", function()
    local apply = mod._cim_apply_modded_slot_metadata
    local state = mod._cim_modded_slot_state
    local core = mod._cim246_tab_preview_core
    if type(apply) ~= "function" or type(state) ~= "table"
            or type(core) ~= "table" or type(core.resolve_rarity) ~= "function" then
        return "#921 rarity metadata policy/runtime wiring missing"
    end

    local peer_id, local_player_id, slot_name = "rt_issue921_peer", 7, "slot_melee"
    local uid = tostring(peer_id) .. ":" .. tostring(local_player_id)
    local saved = state[uid]
    state[uid] = nil

    local result_err
    if apply(peer_id, local_player_id, slot_name, true, "regression") ~= true
            or not (state[uid] and state[uid][slot_name] == true) then
        result_err = "modded=true metadata was not retained"
    elseif apply(peer_id, local_player_id, slot_name, false, "regression") ~= true
            or not state[uid] or state[uid][slot_name] ~= false then
        result_err = "modded=false metadata collapsed to absence; stale frame can survive"
    elseif core.resolve_rarity("modded", true, false) ~= "unique" then
        result_err = "authoritative false did not clear a cached modded rarity"
    elseif core.resolve_rarity("modded", true, nil) ~= "modded" then
        result_err = "missing metadata did not fail closed"
    end

    state[uid] = saved
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
    local data_txt = read_all(dir .. "crafting_in_modded_dev_data.lua")
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
    local ok, data = pcall(mod.dofile, mod, "scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_data")
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
