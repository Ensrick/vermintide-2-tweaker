-- _cim_dump_commands.lua -- read-only diagnostic chat commands.
--
-- Two engine-read-only dump commands lifted verbatim from the entry:
--   * /cim_dump_active_window -- walk the open hero_view's active windows and log
--     every widget name + hotspot / disabled / text state (UI-layout debugging).
--   * /craft_dump -- log the equipped melee / ranged item's rarity / localization
--     / NetworkLookup / RaritySettings / mirror-promo state (crafted-item triage).
-- Neither mutates any cim state; both read only engine globals + the backend
-- interfaces, so they have NO dependency on the entry's file-locals. Distinct
-- from cim_debug.lua (which owns the mod._cim_autodump_* helpers) and from the
-- forge_dump* commands (those gate on the entry-local _custom_forge_active and
-- therefore stay in the entry).
--
-- Extracted verbatim from crafting_in_modded_dev.lua (v0.8.55-dev OOP split).
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via: mod:dofile.
local mod = get_mod("cim_dev")
mod:command("cim_dump_active_window", "Dump the currently-open hero_view active windows + their widgets to log (use while a menu is open)", function()
    local ui = Managers.ui
    local ingame_ui = ui and ui._ingame_ui
    if not ingame_ui then mod:echo("No ingame_ui"); return end
    local hero_view = ingame_ui.views and ingame_ui.views.hero_view
    if not hero_view then mod:echo("hero_view not active"); return end
    -- hero_view holds the active state inside `_machine._state` (a GameStateMachine
    -- inheriting StateMachine — see hero_view.lua:94). My v0.7.11 dump used the
    -- nonexistent `_current_state`, which always reported nil. Walk the machine
    -- path and fall back to a few alternatives in case the field name varies
    -- across UI states.
    local state = hero_view._machine and hero_view._machine._state
        or hero_view._current_state
        or hero_view._state
    if not state then
        mod:echo("No active state on hero_view (machine=" ..
            tostring(hero_view._machine) .. "). Open the menu first then re-run.")
        return
    end
    mod:echo(string.format("[cim] hero_view state class: %s", tostring(state.NAME or state.__class_name or "?")))
    mod:info("================ CIM ACTIVE WINDOW DUMP ================")
    mod:info("hero_view._machine._state = %s", tostring(state.NAME or "?"))
    local windows = state._active_windows or state.active_windows
    if not windows then mod:echo("No _active_windows on state"); return end
    for slot_idx, win in pairs(windows) do
        mod:info("--- window[%s] NAME=%s ---", tostring(slot_idx), tostring(win.NAME or "?"))
        mod:echo(string.format("  window[%s] = %s", tostring(slot_idx), tostring(win.NAME or "?")))
        local widgets = win._widgets_by_name
        if widgets then
            local names = {}
            for n in pairs(widgets) do names[#names + 1] = n end
            table.sort(names)
            for _, name in ipairs(names) do
                local w = widgets[name]
                local content = w and w.content
                local hot = content and content.button_hotspot
                local disabled = hot and hot.disable_button
                local has_text = content and (content.text or content.title or content.label)
                local line = string.format("    %-50s hotspot=%s disabled=%s text=%s",
                    name,
                    tostring(hot ~= nil),
                    tostring(disabled),
                    tostring(has_text or ""))
                mod:info(line)
                if hot then
                    mod:echo("    " .. name .. " disable_button=" .. tostring(disabled))
                end
            end
        end
        if win._params then
            for k, v in pairs(win._params) do
                mod:info("    _params.%s = %s", tostring(k), tostring(v))
            end
        end
    end
    mod:info("======================== END ===========================")
    mod:echo("[cim] Window dump written to log (see logs for full widget list).")
end)

-- Dump everything relevant to the equipped melee/ranged so we can reason about rarity/icons together.
mod:command("craft_dump", "Dump equipped item + rarity/localization/network data", function()
    local items = Managers.backend and Managers.backend:get_interface("items")
    local weaves = Managers.backend and Managers.backend:get_interface("weaves")
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not items or not mirror then
        mod:echo("Backend not ready")
        return
    end
    local player = Managers.player:local_player()
    local profile_index = player:profile_index()
    local profile = SPProfiles[profile_index]
    local career_index = player:career_index()
    local career = profile.careers[career_index]
    local career_name = career.name

    local NL2 = rawget(_G, "NetworkLookup")
    local nl_rarities = NL2 and NL2.rarities
    local nl_promo_idx = nl_rarities and rawget(nl_rarities, "promo")

    mod:info("=== CRAFT DUMP career=%s ===", career_name)
    mod:info("[NetworkLookup] rarities.promo index = %s", tostring(nl_promo_idx))
    mod:info("[UISettings.item_rarity_textures]")
    if UISettings and UISettings.item_rarity_textures then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo","default"}) do
            mod:info("  [%s] = %s", r, tostring(UISettings.item_rarity_textures[r]))
        end
    end
    mod:info("[RaritySettings]")
    local RS = rawget(_G, "RaritySettings")
    if RS then
        for _, r in ipairs({"plentiful","common","rare","exotic","unique","magic","promo"}) do
            local entry = rawget(RS, r)
            mod:info("  [%s] exists=%s display=%s", r, tostring(entry ~= nil),
                entry and tostring(entry.display_name) or "<nil>")
        end
    end

    for _, slot in ipairs({"slot_melee","slot_ranged"}) do
        mod:info("--- slot=%s ---", slot)
        local items_bid = items:get_loadout_item_id(career_name, slot)
        local weaves_bid = weaves and weaves:get_loadout_item_id(career_name, slot)
        mod:info("  items.get_loadout_item_id  = %s", tostring(items_bid))
        mod:info("  weaves.get_loadout_item_id = %s", tostring(weaves_bid))
        local item = items_bid and items:get_item_from_id(items_bid)
        if item then
            local data = item.data or (item.key and rawget(ItemMasterList, item.key)) or {}
            mod:info("  item.key       = %s", tostring(item.key))
            mod:info("  item.ItemId    = %s", tostring(item.ItemId))
            mod:info("  item.rarity    = %s", tostring(item.rarity))
            mod:info("  data.rarity    = %s", tostring(data.rarity))
            mod:info("  display_name   = %s -> %s", tostring(data.display_name), tostring(Localize(data.display_name or "")))
            mod:info("  inventory_icon = %s", tostring(data.inventory_icon))
            mod:info("  power_level    = %s", tostring(item.power_level))
            local resolved_bg = UISettings and UISettings.item_rarity_textures and UISettings.item_rarity_textures[item.rarity]
            mod:info("  -> rarity_bg lookup = %s", tostring(resolved_bg))
            if item.CustomData then
                for k, v in pairs(item.CustomData) do
                    mod:info("  CustomData[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  CustomData = nil")
            end
            if item.properties then
                for k, v in pairs(item.properties) do
                    mod:info("  properties[%s] = %s", tostring(k), tostring(v))
                end
            else
                mod:info("  properties = nil")
            end
            if item.traits then
                for i, t in ipairs(item.traits) do
                    mod:info("  traits[%d] = %s", i, tostring(t))
                end
            else
                mod:info("  traits = nil")
            end
        else
            mod:info("  no item resolved for backend_id=%s", tostring(items_bid))
        end
    end

    mod:info("--- recently-added items (rarity=promo) ---")
    local inv = mirror._inventory_items or {}
    local count = 0
    for bid, it in pairs(inv) do
        if it and it.rarity == "promo" then
            count = count + 1
            mod:info("  [%s] key=%s rarity=%s pl=%s", tostring(bid), tostring(it.key), tostring(it.rarity), tostring(it.power_level))
            if count >= 10 then mod:info("  ...truncated"); break end
        end
    end
    if count == 0 then mod:info("  (none found)") end
    mod:info("=== END CRAFT DUMP ===")
    mod:echo(string.format("Craft dump written. promo items: %d, NL.rarities.promo idx: %s", count, tostring(nl_promo_idx)))
end)
