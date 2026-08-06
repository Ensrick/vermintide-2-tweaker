-- _cim_command_owner.lua -- CIM-dev forge diagnostics and maintenance commands.
--
-- Behavior-neutral extraction from the entry. This owner retains the original
-- 13 command registration order, the private pending-forge transaction, the
-- public exact-owner deletion surface, and the existing bulk-cleanup adapter.
-- Reassigned entry stores arrive through accessors so no module can retain a
-- stale table after load/restore.
return function(ctx)
    assert(type(ctx) == "table", "CIM command owner requires context")

    local mod = assert(ctx.mod, "CIM command owner requires mod")
    local _is_custom_forge_active = assert(ctx.is_custom_forge_active,
        "CIM command owner requires custom-forge accessor")
    local _get_forged_weapons = assert(ctx.get_forged_weapons,
        "CIM command owner requires forged-weapon accessor")
    local _get_modded_loadout = assert(ctx.get_modded_loadout,
        "CIM command owner requires loadout accessor")
    local _get_more_items_lib = assert(ctx.get_more_items_lib,
        "CIM command owner requires MoreItemsLibrary accessor")
    local _forge_inject_item = assert(ctx.forge_inject_item,
        "CIM command owner requires forge injection")
    local _forge_create_item = assert(ctx.forge_create_item,
        "CIM command owner requires legacy entry builder")
    local _forge_detect_mil = assert(ctx.forge_detect_mil,
        "CIM command owner requires MIL detector")
    local _forge_save = assert(ctx.forge_save,
        "CIM command owner requires craft persistence")
    local _modded_loadout_save = assert(ctx.modded_loadout_save,
        "CIM command owner requires loadout persistence")

    -- This state was entry-local and is consumed only by the manual /forge*
    -- command family. Moving it with its sole owner preserves one transaction.
    local _forge_pending = nil

-- ============================================================
-- Diagnostic commands
-- ============================================================

    local function _forge_dump_widgets(window_name, win)
    local w = win._widgets_by_name
    if not w then
        mod:info("DUMP [%s] _widgets_by_name=nil, checking fields:", window_name)
        for k, v in pairs(win) do
            if type(v) == "table" and k:find("widget") then
                mod:info("  field: %s (table, #%d)", k, #v)
            elseif type(v) ~= "function" then
                mod:info("  field: %s = %s", k, tostring(v))
            end
        end
        return
    end
    mod:info("=== DUMP [%s] ===", window_name)
    for name, widget in pairs(w) do
        local parts = {}
        if widget.content then
            for k, v in pairs(widget.content) do
                if type(v) == "string" and #v < 60 then
                    parts[#parts + 1] = k .. '="' .. v .. '"'
                elseif type(v) == "boolean" or type(v) == "number" then
                    parts[#parts + 1] = k .. "=" .. tostring(v)
                end
            end
        end
        local sparts = {}
        if widget.style then
            for sk, sv in pairs(widget.style) do
                if type(sv) == "table" then
                    if sv.color then
                        local c = sv.color
                        sparts[#sparts + 1] = sk .. ".color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.text_color then
                        local c = sv.text_color
                        sparts[#sparts + 1] = sk .. ".text_color={" .. tostring(c[1]) .. "," .. tostring(c[2]) .. "," .. tostring(c[3]) .. "," .. tostring(c[4]) .. "}"
                    end
                    if sv.font_size then
                        sparts[#sparts + 1] = sk .. ".font_size=" .. tostring(sv.font_size)
                    end
                end
            end
        end
        mod:info("  [%s] content: %s", name, table.concat(parts, ", "))
        if #sparts > 0 then
            mod:info("    style: %s", table.concat(sparts, ", "))
        end
    end
    mod:info("=== END [%s] ===", window_name)
end

mod:command("forge_dump", "Dump all forge window widget names to log", function()
    if not _is_custom_forge_active() then
        mod:echo("Open the forge first (B key), then run this command")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then
        mod:echo("No ingame_ui")
        return
    end
    local view_name = ingame_ui.current_view
    if not view_name then
        mod:echo("No current_view")
        return
    end
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view then
        mod:echo("No view object for: " .. tostring(view_name))
        return
    end
    mod:info("=== FORGE UI DUMP ===")
    mod:info("current_view = %s", tostring(view_name))

    local forge_state = nil
    if hero_view._machine and hero_view._machine._state then
        forge_state = hero_view._machine._state
        mod:info("forge_state via _machine._state: %s (NAME=%s)", tostring(forge_state), tostring(forge_state.NAME))
    end
    if not forge_state then
        mod:echo("Could not find forge state on hero_view._machine._state")
        return
    end

    mod:info("--- forge_state fields ---")
    for k, v in pairs(forge_state) do
        if type(v) ~= "function" then
            local vstr = tostring(v)
            if type(v) == "table" then
                local count = 0
                for _ in pairs(v) do count = count + 1 end
                vstr = "table(" .. count .. ")"
            end
            mod:info("  state.%s = %s (%s)", k, vstr, type(v))
        end
    end

    local found = 0
    local active_windows = forge_state._active_windows
    if active_windows then
        mod:info("--- _active_windows ---")
        for idx, win in pairs(active_windows) do
            local win_name = win.NAME or win.__class_name or tostring(win)
            mod:info("Window[%s]: %s", tostring(idx), tostring(win_name))
            _forge_dump_widgets(tostring(idx) .. "_" .. tostring(win_name), win)
            found = found + 1
        end
    else
        mod:info("_active_windows is nil, scanning forge_state for _widgets_by_name:")
        for k, v in pairs(forge_state) do
            if type(v) == "table" and rawget(v, "_widgets_by_name") then
                mod:info("  Found _widgets_by_name on state.%s", k)
                _forge_dump_widgets(k, v)
                found = found + 1
            end
        end
    end
    mod:info("=== END FORGE UI DUMP (found %d windows) ===", found)
    mod:echo("Dump written to log (" .. found .. " windows found)")
end)

mod:command("forge_dump_props", "Dump properties sub-menu widgets and seed data", function()
    if not _is_custom_forge_active() then
        mod:echo("Open the forge first (B key)")
        return
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if not ingame_ui then mod:echo("No ingame_ui") return end
    local view_name = ingame_ui.current_view
    local hero_view = ingame_ui.views and ingame_ui.views[view_name]
    if not hero_view or not hero_view._machine then mod:echo("No hero_view") return end
    local forge_state = hero_view._machine._state
    if not forge_state then mod:echo("No forge_state") return end
    local windows = forge_state._active_windows
    if not windows then mod:echo("No _active_windows") return end

    mod:echo("Layout: " .. tostring(forge_state._selected_layout_name))
    local found_props = false
    for idx, win in pairs(windows) do
        mod:echo("Window[" .. tostring(idx) .. "]: " .. tostring(win.NAME))
        if win.NAME == "HeroWindowWeaveProperties" then
            found_props = true
            local wbn = win._widgets_by_name
            if wbn then
                local names = {}
                for name, widget in pairs(wbn) do
                    local info = name
                    if widget.content then
                        if widget.content.text then
                            info = info .. "=" .. tostring(widget.content.text)
                        end
                        if widget.content.visible == false then
                            info = info .. " [HIDDEN]"
                        end
                    end
                    names[#names + 1] = info
                end
                table.sort(names)
                for _, n in ipairs(names) do
                    mod:echo("  " .. n)
                end
            end
            mod:echo("_item_backend_id: " .. tostring(win._item_backend_id))
            mod:echo("_career_name: " .. tostring(win._career_name))
            local p = win._params
            if p then
                mod:echo("params.selected_item: " .. tostring(p.selected_item))
                if p.selected_item then
                    mod:echo("  .key: " .. tostring(p.selected_item.key or p.selected_item.data and p.selected_item.data.key))
                    mod:echo("  .backend_id: " .. tostring(p.selected_item.backend_id))
                end
                mod:echo("params.selected_unit_name: " .. tostring(p.selected_unit_name))
                mod:echo("params.selected_slot_name: " .. tostring(p.selected_slot_name))
            end
            mod:echo("_viewport_widget: " .. tostring(win._viewport_widget))
            mod:echo("_viewport_widget_definition: " .. tostring(win._viewport_widget_definition))
            mod:echo("_item_previewer: " .. tostring(win._item_previewer))
            mod:echo("_unit_previewer: " .. tostring(win._unit_previewer))
            mod:echo("_previewer_initialized: " .. tostring(win._previewer_initialized))
        end
    end
    if not found_props then
        mod:echo("HeroWindowWeaveProperties not active — click a weapon first")
    end

    local items_backend = Managers.backend and Managers.backend:get_interface("items")
    if items_backend then
        local player = Managers.player and Managers.player:local_player()
        if player then
            local pi = player:profile_index()
            local profile = SPProfiles[pi]
            local ci = player:career_index()
            local career_name = profile.careers[ci].name
            for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
                local bid = items_backend:get_loadout_item_id(career_name, slot)
                if bid then
                    local item = items_backend:get_item_from_id(bid)
                    if item then
                        mod:echo(slot .. ": " .. tostring(item.key) .. " power=" .. tostring(item.power_level))
                        if item.properties then
                            for pk, pv in pairs(item.properties) do
                                local wk = "weave_" .. pk
                                local wp = rawget(_G, "WeaveProperties")
                                local mapped = wp and wp.properties and wp.properties[wk] and "YES" or "NO"
                                mod:echo("  prop: " .. pk .. "=" .. tostring(pv) .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                        if item.traits then
                            for i, tk in ipairs(item.traits) do
                                local wk = "weave_" .. tk
                                local wt = rawget(_G, "WeaveTraits")
                                local mapped = wt and wt.traits and wt.traits[wk] and "YES" or "NO"
                                mod:echo("  trait: " .. tk .. " -> " .. wk .. " mapped=" .. mapped)
                            end
                        end
                    end
                end
            end
        end
    end
end)

mod:command("forge_dump_backend", "Dump forge backend hook returns to log", function()
    if not _is_custom_forge_active() then
        mod:echo("Open the forge first (B key)")
        return
    end
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local items = Managers.backend and Managers.backend:get_interface("items")
    if not weaves or not items then
        mod:echo("Backend not available")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name
    mod:info("=== FORGE BACKEND DUMP career=%s ===", career_name)
    for _, slot in ipairs({"slot_melee", "slot_ranged"}) do
        local bid = weaves:get_loadout_item_id(career_name, slot)
        mod:info("  get_loadout_item_id(%s, %s) = %s", career_name, slot, tostring(bid))
        if bid then
            local item = items:get_item_from_id(bid)
            mod:info("  item from backend: %s", item and tostring(item.key) or "nil")
            if item then
                mod:info("    power_level: %s", tostring(item.power_level))
                mod:info("    rarity: %s", tostring(item.rarity))
                if item.properties then
                    for pk, pv in pairs(item.properties) do
                        mod:info("    prop: %s = %s", pk, tostring(pv))
                    end
                else
                    mod:info("    properties: nil")
                end
                if item.traits then
                    for i, t in ipairs(item.traits) do
                        mod:info("    trait[%d]: %s", i, tostring(t))
                    end
                else
                    mod:info("    traits: nil")
                end
            end
            local props = weaves:get_loadout_properties(career_name, bid)
            mod:info("  get_loadout_properties result:")
            if props then
                for pk, pv in pairs(props) do
                    mod:info("    %s = %s", pk, tostring(pv))
                end
            else
                mod:info("    nil")
            end
            local traits = weaves:get_loadout_traits(career_name, bid)
            mod:info("  get_loadout_traits result:")
            if traits then
                for tk, tv in pairs(traits) do
                    mod:info("    %s = %s", tostring(tk), tostring(tv))
                end
            else
                mod:info("    nil")
            end
        end
    end
    mod:info("  get_forge_level: %s", tostring(weaves:get_forge_level()))
    mod:info("  get_essence: %s", tostring(weaves:get_essence()))
    mod:info("=== END FORGE BACKEND DUMP ===")
    mod:echo("Backend dump written to log")
end)


-- ============================================================
-- Manual console crafting commands (/forge*)
-- ============================================================

mod:command("forge", "Start forging a weapon (usage: /forge <weapon_key>)", function(item_key)
    if not item_key then
        mod:echo("Usage: /forge <weapon_key>")
        mod:echo("  Then: /forge_trait <trait_name>")
        mod:echo("  Then: /forge_props <prop1>=<value> <prop2>=<value>")
        mod:echo("  Then: /forge_confirm")
        mod:echo("Use /dump_weapons to see available weapon keys.")
        return
    end
    if not ItemMasterList then
        mod:echo("Forge: ItemMasterList not loaded yet")
        return
    end
    local master = rawget(ItemMasterList, item_key)
    if not master then
        mod:echo("Forge: unknown weapon key '" .. item_key .. "'")
        return
    end
    _forge_pending = {
        item_key = item_key,
        properties = {},
        trait = nil,
        skin = nil,
        -- Default to the base_power_level setting (overridable via the power
        -- command); was hardcoded 300. 2026-06-30.
        power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
    }
    local display = item_key
    if master.display_name then
        local ok, loc = pcall(Localize, master.display_name)
        if ok and loc then display = loc end
    end
    mod:echo("Forge: preparing " .. display .. " (" .. item_key .. ")")
    mod:echo("  Set trait: /forge_trait <trait_name>")
    mod:echo("  Set props: /forge_props <prop>=<0-1> ...")
    mod:echo("  Set skin:  /forge_skin <skin_key>")
    mod:echo("  Set power: /forge_power <1-300>")
    mod:echo("  Confirm:   /forge_confirm")
    mod:echo("  Cancel:    /forge_cancel")
end)

mod:command("forge_trait", "Set trait for pending forge (usage: /forge_trait <trait_name>)", function(trait)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    if not trait then
        mod:echo("Usage: /forge_trait <trait_name>")
        return
    end
    _forge_pending.trait = trait
    mod:echo("Forge: trait set to " .. trait)
end)

mod:command("forge_props", "Set properties for pending forge (usage: /forge_props crit_chance=0.5 attack_speed=1)", function(...)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    local args = {...}
    if #args == 0 then
        mod:echo("Usage: /forge_props <prop>=<value> ...")
        mod:echo("  Values are 0.0-1.0 (fraction of max)")
        return
    end
    for _, arg in ipairs(args) do
        local key, val = arg:match("^([^=]+)=(.+)$")
        if key and val then
            local num = tonumber(val)
            if num then
                _forge_pending.properties[key] = num
                mod:echo("  " .. key .. " = " .. tostring(num))
            else
                mod:echo("  Invalid value for " .. key .. ": " .. val)
            end
        else
            mod:echo("  Invalid format: " .. arg .. " (expected key=value)")
        end
    end
end)

mod:command("forge_skin", "Set skin for pending forge (usage: /forge_skin <skin_key>)", function(skin)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    if not skin then
        _forge_pending.skin = nil
        mod:echo("Forge: skin cleared")
        return
    end
    _forge_pending.skin = skin
    mod:echo("Forge: skin set to " .. skin)
end)

mod:command("forge_power", "Set power level for pending forge (usage: /forge_power <1-300>)", function(val)
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end
    local num = tonumber(val)
    if not num or num < 1 or num > 300 then
        mod:echo("Usage: /forge_power <1-300>")
        return
    end
    _forge_pending.power_level = math.floor(num)
    mod:echo("Forge: power level set to " .. _forge_pending.power_level)
end)

mod:command("forge_cancel", "Cancel pending forge", function()
    if not _forge_pending then
        mod:echo("Forge: nothing pending")
        return
    end
    _forge_pending = nil
    mod:echo("Forge: cancelled")
end)

mod:command("forge_confirm", "Create the forged weapon", function()
    if not _forge_pending then
        mod:echo("Forge: no weapon pending — run '/forge <weapon_key>' first")
        return
    end

    local rnd = math.random(1000000)
    local backend_id = _forge_pending.item_key .. "_" .. rnd .. "_forged"

    if _forge_inject_item(_forge_pending, backend_id) then
        local registered, register_err = mod._cim_register_craft(backend_id, {
            item_key = _forge_pending.item_key,
            properties = _forge_pending.properties,
            trait = _forge_pending.trait,
            skin = _forge_pending.skin,
            power_level = _forge_pending.power_level,
            via_mirror = false,
        })
        if not registered then
            mod:warning("Forge: persistence rejected: " .. tostring(register_err))
            return
        end

        local master = rawget(ItemMasterList, _forge_pending.item_key)
        local display = _forge_pending.item_key
        if master and master.display_name then
            local ok, loc = pcall(Localize, master.display_name)
            if ok and loc then display = loc end
        end
        mod:echo("Forge: created " .. display .. " [" .. backend_id .. "]")
        _forge_pending = nil
    end
end)

-- Diagnostic for salvage visibility: dumps every saved craft + whether it's
-- currently in the backend mirror, what rarity the mirror says, what
-- slot_type it has, and whether our salvage filter would surface it.
mod:command("salvage_debug", "Why isn't my modded craft showing in salvage?", function()
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not items_iface or not mirror then
        mod:echo("Backend not ready")
        return
    end

    local inv = mirror._inventory_items or {}
    local saved_count, in_mirror, promo_in_mirror = 0, 0, 0
    mod:echo("--- saved crafts (_forged_weapons) ---")
    for bid, w in pairs(_get_forged_weapons()) do
        saved_count = saved_count + 1
        local item = inv[bid]
        local in_inv = item ~= nil
        if in_inv then in_mirror = in_mirror + 1 end
        local rarity = item and item.rarity or "<not in mirror>"
        local slot_type = item and item.data and item.data.slot_type or "<no data>"
        if rarity == "promo" then promo_in_mirror = promo_in_mirror + 1 end
        local in_inv_str = in_inv and "Y" or "N"
        mod:echo(string.format("  inv=%s  rarity=%s  slot=%s  key=%s  bid=%s",
            in_inv_str, tostring(rarity), tostring(slot_type), tostring(w.item_key), tostring(bid)))
    end
    mod:echo(string.format("Saved: %d  In mirror: %d  Promo in mirror: %d",
        saved_count, in_mirror, promo_in_mirror))

    mod:echo("--- all promo-rarity items in mirror ---")
    local extra_promo = 0
    for bid, item in pairs(inv) do
        if item and item.rarity == "promo" and not _get_forged_weapons()[bid] then
            extra_promo = extra_promo + 1
            local slot_type = item.data and item.data.slot_type or "<no data>"
            mod:echo(string.format("  rarity=promo  slot=%s  key=%s  bid=%s",
                tostring(slot_type), tostring(item.key or item.ItemId), tostring(bid)))
        end
    end
    if extra_promo == 0 then mod:echo("  (none beyond saved crafts)") end
end)

mod:command("forge_list", "List all forged weapons and accessories", function()
    local count = 0
    for bid, w in pairs(_get_forged_weapons()) do
        count = count + 1
        local display = w.item_key
        local _entry = ItemMasterList and rawget(ItemMasterList, w.item_key)
        if _entry and _entry.display_name then
            local ok, loc = pcall(Localize, _entry.display_name)
            if ok and loc then display = loc end
        end
        local parts = { display }
        if w.trait then parts[#parts + 1] = "trait=" .. w.trait end
        local prop_strs = {}
        for k, v in pairs(w.properties) do
            prop_strs[#prop_strs + 1] = k .. "=" .. tostring(v)
        end
        if #prop_strs > 0 then parts[#parts + 1] = table.concat(prop_strs, ", ") end
        parts[#parts + 1] = "power=" .. tostring(w.power_level or 300)
        mod:echo("[" .. count .. "] " .. table.concat(parts, " | ") .. "  id=" .. bid)
    end
    if count == 0 then
        mod:echo("Forge: no forged crafts")
    else
        mod:echo("Forge: " .. count .. " craft(s)")
    end
end)

-- Issues #277/#628: one local transaction shared by single delete, bulk
-- cleanup, and Salvage. It snapshots exact `_inventory_items` rows plus
-- PlayerData's global and career/slot new-item markers, then mutates those
-- tables directly. Rollback never calls PlayFabMirrorBase.add_item, whose
-- normalization, callbacks, power evaluation, skin routing, new marking, and
-- autosave would not reproduce the pre-delete state (decompile :2494-2555).
-- Owned persistence/reference stores and foreign session-only Salvage rows
-- therefore commit or compensate as one selected set. Presentation convergence
-- is a success-only `dirtify_interfaces` flag; rollback never calls the eager
-- item `_refresh` normalizer.
mod._cim277_delete_owned_ids = function(backend_ids, foreign_ids)
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    local items = Managers.backend and Managers.backend:get_interface("items")
    if not mirror or type(mirror._inventory_items) ~= "table" or not items then
        return 0, "backend mirror is not ready"
    end

    local deletion = mod._cim277_owned_deletion
    if not deletion or type(deletion.execute) ~= "function" then
        return 0, "CIM ownership contract is unavailable"
    end

    return deletion.execute({
        records = _get_forged_weapons(),
        item_master = ItemMasterList,
        contract = mod._cim_synthetic_item_contract,
        inventory_items = mirror._inventory_items,
        new_item_ids = PlayerData and PlayerData.new_item_ids,
        new_item_ids_by_career = PlayerData
            and PlayerData.new_item_ids_by_career,
        loadouts = _get_modded_loadout(),
        clear_loadout_refs = mod._cim277_bulk_core
            and mod._cim277_bulk_core.clear_loadout_refs,
        persist_loadouts = _modded_loadout_save,
        get_overrides = function()
            return mod:get("vanilla_skin_overrides_by_backend_id")
        end,
        clear_override_refs = mod._cim277_bulk_core
            and mod._cim277_bulk_core.clear_map_keys,
        persist_overrides = function(overrides)
            mod:set("vanilla_skin_overrides_by_backend_id", overrides)
        end,
        build_legacy_entry = _forge_create_item,
        remove_legacy_item = function(backend_id)
            if not _forge_detect_mil() then
                error("MoreItemsLibrary is unavailable")
            end
            _get_more_items_lib():remove_mod_items_from_local_backend(
                { backend_id }, "crafting_in_modded_dev")
        end,
        restore_legacy_item = function(_, entry)
            if not _forge_detect_mil() then
                error("MoreItemsLibrary is unavailable")
            end
            _get_more_items_lib():add_mod_items_to_local_backend(
                { entry }, "crafting_in_modded_dev")
        end,
        save = _forge_save,
        invalidate = function()
            Managers.backend:dirtify_interfaces()
        end,
    }, backend_ids, foreign_ids)
end

mod:command("forge_delete", "Delete a forged weapon or accessory (usage: /forge_delete <backend_id or index>)", function(id_or_idx)
    if not id_or_idx then
        mod:echo("Usage: /forge_delete <backend_id or index from /forge_list>")
        return
    end

    local idx = tonumber(id_or_idx)
    local target_bid = nil

    if idx then
        local count = 0
        for bid, _ in pairs(_get_forged_weapons()) do
            count = count + 1
            if count == idx then
                target_bid = bid
                break
            end
        end
        if not target_bid then
            mod:echo("Forge: no craft at index " .. tostring(idx))
            return
        end
    else
        if _get_forged_weapons()[id_or_idx] then
            target_bid = id_or_idx
        else
            mod:echo("Forge: no craft with id '" .. id_or_idx .. "'")
            return
        end
    end

    local items = Managers.backend and Managers.backend:get_interface("items")
    if not items then
        mod:echo("Forge: backend is not ready")
        return
    end
    local ok_current, current = pcall(items.equipped_by, items, target_bid)
    local ok_saved, saved = pcall(items.is_equipped_by_any_loadout, items, target_bid)
    if not ok_current or not ok_saved
            or type(current) ~= "table" or type(saved) ~= "table" then
        mod:echo("Forge: could not prove the item is unequipped; nothing was deleted")
        return
    end
    if #current > 0 or #saved > 0 then
        mod:echo("Forge: unequip this item from every current and saved loadout before deleting it")
        return
    end

    local removed, err = mod._cim277_delete_owned_ids({ target_bid })
    if err then
        mod:echo("Forge: delete refused: " .. err)
    elseif removed == 1 then
        mod:echo("Forge: deleted " .. target_bid)
    else
        mod:echo("Forge: item was no longer owned by CIM; nothing was deleted")
    end
end)

local _install_bulk_cleanup_command = mod:dofile(
    "scripts/mods/crafting_in_modded_dev/_cim_bulk_cleanup_command")
_install_bulk_cleanup_command({
    mod = mod,
    core = mod._cim277_bulk_core,
    contract = mod._cim_synthetic_item_contract,
    get_forged_weapons = function() return _get_forged_weapons() end,
    get_item_master = function() return ItemMasterList end,
    get_backend_items = function()
        return Managers.backend and Managers.backend:get_interface("items")
    end,
    get_backend_mirror = function()
        return Managers.backend and Managers.backend:get_backend_mirror()
    end,
    delete_owned_ids = function(ids) return mod._cim277_delete_owned_ids(ids) end,
})

end
