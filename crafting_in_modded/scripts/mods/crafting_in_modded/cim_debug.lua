--[[
cim_debug — autodump diagnostic helpers gated on the universal
`enable_debug_logging` VMF setting (PROJECT_STANDARDS.md § 3.6;
v0.7.37-alpha: renamed from `debug_mode`).

When `enable_debug_logging` is OFF (default), every entrypoint in this file is a fast no-op.
When ON, the autodump_* hooks fire at well-known UI/state transitions and emit
log-only (`mod:info`) diagnostic snapshots labelled with a context string. No
chat spam — output goes to `%appdata%\Fatshark\Vermintide 2\console_logs\`.

Purpose: when a user reports "X didn't appear" or "Y wasn't restored", the most
recent log already contains the state snapshot at the moment the relevant menu
was opened. No need to ask the user to remember `/inv_dump` etc.

The autodumps are intentionally SEPARATE from the on-demand `/inv_dump` /
`/mirror_dump` / `/cim_dump_loadout` / `/forge_list` / `/salvage_debug`
commands — the commands echo to chat for interactive use; the autodumps go
log-only and are tuned for diagnosing post-hoc from a forwarded log file.
]]

local mod = get_mod("cim")

local function _enabled()
    return mod:get("enable_debug_logging")
end

local function _info(label, fmt, ...)
    mod:info(("[cim-debug] [%s] " .. fmt):format(label, ...))
end

local function _local_career()
    local pl = Managers.player and Managers.player:local_player()
    if not pl then return nil, nil end
    local profile_index = pl:profile_index()
    local career_index = pl:career_index()
    local profile = SPProfiles and SPProfiles[profile_index]
    local career  = profile and profile.careers and profile.careers[career_index]
    return career and career.name, profile and profile.display_name
end

-- Track the bids crafted THIS session (ring buffer, capped) so the
-- get_filtered_items probe can ask "did my just-crafted item survive the
-- filter the inventory grid actually uses?". Always-on + capped — negligible
-- cost when debug is off; the probe that reads it is still debug-gated.
mod._cim_recent_craft_bids = mod._cim_recent_craft_bids or {}
mod._cim_note_craft_bid = function(bid)
    if not bid then return end
    local t = mod._cim_recent_craft_bids
    t[#t + 1] = bid
    while #t > 12 do table.remove(t, 1) end
end

-- v0.7.62-dev: instrument the EXACT layer the inventory grid reads — the
-- vanilla `get_filtered_items` result. Every older probe checked
-- get_all_backend_items (the BROAD view), which is why they reported
-- found_in_all=true while the grid showed nothing: get_filtered_items applies
-- the grid's filter string (e.g. "slot_type == melee and item_rarity ~= magic"
-- + a hero-specific can_wield_career macro). This probe reports, for each bid
-- crafted this session, whether it survived that filter; if ABSENT it dumps the
-- live item's filterable fields so we see WHICH token rejected it. If the
-- inventory grid never triggers this probe at all (no slot_type filter logged
-- when the user opens inventory), the grid is querying a different backend
-- (LA-clone dispatch) and our hook is being bypassed.
mod._cim_autodump_filtered_items = function(self, filter, params, result)
    if not _enabled() then return end
    if type(filter) ~= "string" or not filter:find("slot_type", 1, true) then return end
    local recent = mod._cim_recent_craft_bids
    if not recent or #recent == 0 then return end

    local n = (type(result) == "table") and #result or -1
    local present = {}
    if type(result) == "table" then
        for _, it in ipairs(result) do
            if it and it.backend_id then present[it.backend_id] = true end
        end
    end

    local all = (self.get_all_backend_items and self:get_all_backend_items()) or {}
    for _, bid in ipairs(recent) do
        if present[bid] then
            _info("filtered_items", "bid=%s PRESENT in grid result | filter=%q n=%d", tostring(bid), filter, n)
        else
            local item = all[bid]
            if not item then
                for _, it in pairs(all) do
                    if it and it.backend_id == bid then item = it break end
                end
            end
            local d = item and item.data
            local cw = d and d.can_wield
            local cw_str = (type(cw) == "table") and table.concat(cw, ",") or tostring(cw)
            local mech = d and d.mechanisms
            local mech_str = (type(mech) == "table") and table.concat(mech, ",") or tostring(mech)
            _info("filtered_items",
                "bid=%s ABSENT from grid result | filter=%q n=%d | in_get_all=%s slot_type=%s item_type=%s rarity=%s can_wield=[%s] mechanisms=%s required_dlc=%s",
                tostring(bid), filter, n, tostring(item ~= nil),
                tostring(d and d.slot_type), tostring(d and d.item_type),
                tostring(item and item.rarity), cw_str, mech_str,
                tostring(d and d.required_dlc))
        end
    end
end

-- ============================================================
-- Per-context autodumps
-- ============================================================

-- Standard forge or customization menu open (HeroWindowCrafting,
-- HeroWindowCraftingConsole, HeroWindowItemCustomization). Called from the
-- consolidated `on_enter` callback in standard_forge.lua. `window_self` is
-- optional — passed when the caller wants the JEWELRY-probe to run on the
-- window's widgets too.
mod._cim_autodump_forge_open = function(class_name, window_self)
    if not _enabled() then return end
    local label = "forge_open/" .. tostring(class_name)
    _info(label, "===== forge surface opened =====")

    if window_self and mod._cim_autodump_jewelry_probe then
        pcall(mod._cim_autodump_jewelry_probe, window_self, class_name)
    end

    local eac      = script_data and script_data["eac-untrusted"] and "true" or "false"
    local sf       = mod._cim_standard_forge_active and "true" or "false"
    local show_only = mod:get("show_only_modded_weapons") and "true" or "false"
    local mech     = Managers.mechanism and Managers.mechanism:current_mechanism_name() or "?"
    local career_name, profile_name = _local_career()
    _info(label, "eac_untrusted=%s sf_active=%s show_only_modded=%s mech=%s career=%s/%s",
        eac, sf, show_only, mech, tostring(profile_name), tostring(career_name))

    -- Mirror health (modded vs vanilla item counts).
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if items_iface and items_iface.get_all_backend_items then
        local all = items_iface:get_all_backend_items() or {}
        local n_mod, n_van = 0, 0
        for _, item in pairs(all) do
            if mod._cim_is_modded_item and mod._cim_is_modded_item(item) then
                n_mod = n_mod + 1
            else
                n_van = n_van + 1
            end
        end
        _info(label, "mirror: modded=%d vanilla=%d total=%d", n_mod, n_van, n_mod + n_van)
    end

    -- Current-career loadout (every slot — what's actually equipped right now).
    if items_iface and items_iface.get_loadout_item_id and career_name then
        local slots = { "slot_melee", "slot_ranged", "slot_necklace", "slot_ring",
                        "slot_trinket_1", "slot_hat", "slot_skin" }
        for _, slot in ipairs(slots) do
            local bid = items_iface:get_loadout_item_id(career_name, slot)
            local item = bid and items_iface:get_item_from_id(bid)
            local key = item and (item.key or (item.data and item.data.key)) or "<empty>"
            local rarity = item and item.rarity or "-"
            _info(label, "equipped %s = %s [%s] bid=%s", slot, tostring(key), tostring(rarity), tostring(bid))
        end
    end
end

-- Athanor (custom WoM forge) open.
mod._cim_autodump_athanor_open = function()
    if not _enabled() then return end
    local label = "athanor_open"
    _info(label, "===== Athanor opened =====")

    local fw = mod:get("forged_weapons") or {}
    local fw_count = 0
    for _ in pairs(fw) do fw_count = fw_count + 1 end
    _info(label, "_forged_weapons saved=%d", fw_count)

    local career_name = _local_career()
    _info(label, "career=%s", tostring(career_name))
end

-- Property editor (HeroWindowWeaveProperties on_enter).
mod._cim_autodump_props_open = function(self)
    if not _enabled() then return end
    local label = "props_open"
    local ok, item = pcall(self._selected_item, self)
    if not ok or not item then
        _info(label, "no selected_item (amulet layout)")
        return
    end
    local data    = item.data or {}
    local props   = item.properties or {}
    local traits  = item.traits or {}
    local pkeys = {}
    for k in pairs(props) do pkeys[#pkeys + 1] = k end
    _info(label, "item bid=%s key=%s rarity=%s slot=%s skin=%s props=[%s] traits=[%s] power=%s",
        tostring(item.backend_id), tostring(data.key or item.key),
        tostring(item.rarity), tostring(data.slot_type), tostring(item.skin),
        table.concat(pkeys, ","), table.concat(traits, ","), tostring(item.power_level))
end

-- Salvage page open (CraftPageSalvage / CraftPageSalvageConsole on_enter).
mod._cim_autodump_salvage_open = function()
    if not _enabled() then return end
    local label = "salvage_open"
    local backend = Managers.backend
    local items_iface = backend and backend:get_interface("items")
    local common = backend and backend:get_interface("common")
    if not (items_iface and common and common.filter_items) then
        _info(label, "backend interfaces not ready")
        return
    end
    local all = items_iface:get_all_backend_items() or {}
    -- Vanilla salvage filter (vanilla excludes equipped / loadout-equipped / promo).
    local pl = Managers.player and Managers.player:local_player()
    local profile_index = pl and pl:profile_index()
    local career_index  = pl and pl:career_index()
    local result = common:filter_items(all,
        "available_in_current_mechanism and ( can_salvage and not is_equipped and not is_equipped_by_any_loadout )",
        { profile_index = profile_index, career_index = career_index })
    local n_total = type(result) == "table" and #result or 0
    local n_mod = 0
    if type(result) == "table" then
        for _, it in ipairs(result) do
            if mod._cim_is_modded_item and mod._cim_is_modded_item(it) then n_mod = n_mod + 1 end
        end
    end
    _info(label, "salvage filter result: total=%d modded=%d (cim's filter override adds modded items unconditionally)", n_total, n_mod)
end

-- Restore pass completion (called from _restore_modded_loadout).
mod._cim_autodump_restore_done = function(stage)
    if not _enabled() then return end
    local label = "restore_done/" .. tostring(stage)
    -- The restore loop already logged per-entry; here we summarize the saved
    -- table state per-career so the user can spot careers with 0 saved entries
    -- (potential candidates for "my X career loadout wasn't restored" reports).
    local ml = mod:get("modded_loadout") or {}
    local careers = 0
    for career_name, slots in pairs(ml) do
        careers = careers + 1
        local n = 0
        for _ in pairs(slots) do n = n + 1 end
        _info(label, "saved %s: %d slot(s)", career_name, n)
    end
    _info(label, "%d career(s) have saved modded loadouts", careers)
end

-- Standard-forge recipe page change (HeroWindowCrafting._change_recipe_page).
-- Fires whenever the user clicks a different recipe tile (salvage, craft_random_item,
-- reroll_weapon_properties, etc.) — captures which page they're now on and the
-- active recipe metadata.
mod._cim_autodump_recipe_page_change = function(self, current_page)
    if not _enabled() then return end
    local label = "recipe_page"
    local recipe = self and self._active_recipe
    local name = recipe and recipe.name or "?"
    local display = recipe and recipe.display_name or "?"
    _info(label, "page=%s recipe=%s display=%s",
        tostring(current_page), tostring(name), tostring(display))
end

-- Athanor overview (HeroWindowWeaveForgeOverview on_enter). The 3-viewport
-- landing page (melee / amulet / ranged).
mod._cim_autodump_athanor_overview_open = function(self)
    if not _enabled() then return end
    local label = "athanor_overview"
    local career_name = _local_career()
    _info(label, "career=%s amulet_introduced=%s",
        tostring(career_name), tostring(self and self.amulet_introduced))
end

-- Athanor weapon-select pane (HeroWindowWeaveForgeWeapons on_enter). Where
-- the user picks a weapon to craft a new modded item.
mod._cim_autodump_athanor_weapons_open = function(self)
    if not _enabled() then return end
    local label = "athanor_weapons"
    local career = self and self._career_name
    local slot   = self and self._selected_slot_name
    _info(label, "career=%s selected_slot=%s", tostring(career), tostring(slot))
end

-- Customization (gear-icon) selected-item snapshot. Called from inside the
-- consolidated `HeroWindowItemCustomization` on_enter callback in
-- standard_forge.lua AFTER the vanilla setup runs (when `_selected_item` is
-- populated). Gives the per-item dump on top of the generic forge_open dump.
mod._cim_autodump_customization_item = function(self)
    if not _enabled() then return end
    local label = "customization_item"
    local sel_ok, sel = pcall(function() return self and self._selected_item end)
    if not sel_ok or not sel then
        _info(label, "no _selected_item yet (window initializing)")
        return
    end
    local data = sel.data or {}
    _info(label, "item bid=%s key=%s rarity=%s slot=%s skin=%s power=%s",
        tostring(sel.backend_id), tostring(data.key or sel.key),
        tostring(sel.rarity), tostring(data.slot_type),
        tostring(sel.skin), tostring(sel.power_level))
end

-- JEWELRY/ACCESSORIES label-hunt probe (issue #38). User reports "JEWELRY"
-- still visible on the main forge page after multiple fix attempts. The
-- literal "Jewellery" only exists in `hero_window_loadout_definitions.lua:602`
-- per UI source grep — but the user is clearly seeing it elsewhere. This probe
-- walks every active window's `_widgets_by_name` on menu entry and logs every
-- widget whose content contains "jewel" / "jewellery" / "jewelry" so the next
-- session's log tells us EXACTLY which widget needs the patch.
--
-- Recursive walk inspects content + style + every nested table value at depth
-- ≤ 3 so it catches strings buried inside hotspots, nested content tables,
-- etc. Strings up to 80 chars are logged verbatim; longer ones are truncated.
local function _walk_for_jewelry(parent_path, value, depth, found)
    if depth > 3 or type(value) ~= "table" then return end
    for k, v in pairs(value) do
        local key_str = tostring(k)
        local sub_path = parent_path == "" and key_str or (parent_path .. "." .. key_str)
        if type(v) == "string" then
            local lower = v:lower()
            if lower:find("jewel", 1, true) then
                found[#found + 1] = string.format("    %s = %q", sub_path,
                    #v > 80 and (v:sub(1, 77) .. "...") or v)
            end
        elseif type(v) == "table" then
            _walk_for_jewelry(sub_path, v, depth + 1, found)
        end
    end
end

mod._cim_autodump_jewelry_probe = function(window_self, context_label)
    if not _enabled() then return end
    if not window_self or type(window_self) ~= "table" then return end
    local label = "jewelry_probe/" .. tostring(context_label or "?")
    local widgets = window_self._widgets_by_name
    if not widgets then
        _info(label, "no _widgets_by_name on window (NAME=%s)", tostring(window_self.NAME))
        return
    end
    local hits = 0
    for widget_name, w in pairs(widgets) do
        if type(w) == "table" then
            local found = {}
            _walk_for_jewelry("", w, 1, found)
            if #found > 0 then
                hits = hits + 1
                _info(label, "  widget [%s] -- %d match(es):", widget_name, #found)
                for _, line in ipairs(found) do _info(label, "%s", line) end
            end
        end
    end
    if hits == 0 then
        _info(label, "no widgets contain 'jewel' text on %s",
            tostring(window_self.NAME or "<unnamed>"))
    else
        _info(label, "scan complete: %d widget(s) with 'jewel' text on %s",
            hits, tostring(window_self.NAME or "<unnamed>"))
    end
end

-- Bubble-click property write. Called from cim's `set_loadout_property` /
-- `set_loadout_trait` / `remove_loadout_property` / `remove_loadout_trait`
-- hooks. Gated on debug logging so the hot path costs nothing when off.
mod._cim_autodump_property_write = function(verb, career_name, key, slot_index, item_bid)
    if not _enabled() then return end
    local label = "property_write/" .. tostring(verb)
    _info(label, "career=%s key=%s slot=%s bid=%s",
        tostring(career_name), tostring(key), tostring(slot_index), tostring(item_bid))
end

-- Comprehensive craft-synth result probe (v0.7.52-dev). Called immediately
-- AFTER a craft path (Athanor `_equip_item` or standard forge `_make_craft_synth`)
-- writes the new item to the backend mirror. Captures everything we need to
-- diagnose "weapon doesn't appear in inventory" reports:
--   - Mirror state (was the write accepted? is item in `_inventory_items`?)
--   - Item resolution (does `get_item_from_id` return a record? what fields?)
--   - Career visibility (does `can_wield` include the current career?)
--   - BID heuristic (does `_cim_is_modded_backend_id` accept the new BID?)
--   - Persistence (is `_forged_weapons[bid]` set?)
--   - Property/trait counts
-- Schedules a 1-frame-later visibility check via `mod._cim_pending_visibility_checks`
-- so we can also assert the item shows up in the inventory grid filter pass.
mod._cim_pending_visibility_checks = mod._cim_pending_visibility_checks or {}

mod._cim_autodump_craft_synth_result = function(path, career_name, item_key, backend_id, weapon_data, mirror_write_ok, mirror_write_err)
    if not _enabled() then return end
    local label = "craft_synth_result/" .. tostring(path)

    -- Mirror state
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    local in_mirror = false
    if mirror and mirror._inventory_items and mirror._inventory_items[backend_id] then
        in_mirror = true
    end

    -- Item resolution (the path inventory queries also use)
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    local resolved = items_iface and items_iface.get_item_from_id
        and items_iface:get_item_from_id(backend_id) or nil
    local resolved_key = "<nil>"
    local resolved_slot = "<nil>"
    local resolved_rarity = "<nil>"
    local can_wield_str = "<nil>"
    if resolved then
        resolved_key = tostring(resolved.key or (resolved.data and resolved.data.key) or "<no-key>")
        resolved_rarity = tostring(resolved.rarity or "<no-rarity>")
        if resolved.data then
            resolved_slot = tostring(resolved.data.slot_type or "<no-slot>")
            local cw = resolved.data.can_wield
            if type(cw) == "table" then
                can_wield_str = table.concat(cw, ",")
            end
        end
    end

    -- Career visibility from can_wield
    local visible_to_career = false
    if resolved and resolved.data and type(resolved.data.can_wield) == "table" then
        for _, c in ipairs(resolved.data.can_wield) do
            if c == career_name then visible_to_career = true; break end
        end
    end

    -- BID heuristic check (the filter gate)
    local is_modded_bid = false
    if mod._cim_is_modded_backend_id then
        local ok, result = pcall(mod._cim_is_modded_backend_id, backend_id)
        is_modded_bid = ok and result and true or false
    end

    -- Persistence check
    local saved = mod:get("forged_weapons") or {}
    local persisted = saved[backend_id] ~= nil

    -- Property/trait counts
    local n_props = 0
    if weapon_data and type(weapon_data.properties) == "table" then
        for _ in pairs(weapon_data.properties) do n_props = n_props + 1 end
    end
    local n_traits = 0
    if weapon_data and type(weapon_data.traits) == "table" then
        n_traits = #weapon_data.traits
    end

    _info(label, "career=%s item_key=%s bid=%s",
        tostring(career_name), tostring(item_key), tostring(backend_id))
    _info(label, "  mirror_write: ok=%s err=%s in_mirror=%s",
        tostring(mirror_write_ok), tostring(mirror_write_err), tostring(in_mirror))
    _info(label, "  resolved: key=%s slot=%s rarity=%s",
        resolved_key, resolved_slot, resolved_rarity)
    _info(label, "  can_wield=[%s] visible_to_career=%s (current=%s)",
        can_wield_str, tostring(visible_to_career), tostring(career_name))
    _info(label, "  is_modded_bid=%s persisted=%s n_props=%d n_traits=%d",
        tostring(is_modded_bid), tostring(persisted), n_props, n_traits)

    -- Schedule a 2-frame-later visibility check — gives any filter side
    -- effects + UI refresh a chance to run before we assert presence.
    mod._cim_pending_visibility_checks[#mod._cim_pending_visibility_checks + 1] = {
        bid = backend_id,
        item_key = item_key,
        career_name = career_name,
        path = path,
        frames_until_check = 2,
    }
end

-- Athanor weapon-list setup dump (v0.7.53-dev). Called from cim's
-- `HeroWindowWeaveForgeWeapons._setup_weapon_list` hook, AFTER `_populate_list`
-- has run. Captures two complete views:
--   (1) The actual menu list cim built (what the user CAN click)
--   (2) The full ItemMasterList sweep for the current career + slot (what
--       vanilla data says SHOULD be possible)
--   Plus per-rejection-reason counts so user reports of "weapon X didn't
--   appear" are diagnosable without further code changes.
--
-- This is the INPUT probe complement to `_cim_autodump_craft_synth_result` —
-- without this, we only see crafts that fired; with this, we also see what
-- WOULD HAVE BEEN craftable and what got filtered out at menu-population time.
mod._cim_autodump_weapon_list_setup = function(career_name, selected_slot_name, item_slot_types, weapon_layout, dlc_check_fn)
    if not _enabled() then return end
    local label = "weapon_list_setup"

    -- Section 1: menu contents (what the user can actually click)
    local in_menu_keys = {}
    local in_menu_set = {}
    for _, entry in ipairs(weapon_layout or {}) do
        local k = entry and entry.key
        if k then
            in_menu_keys[#in_menu_keys + 1] = k
            in_menu_set[k] = entry.item_data
        end
    end
    table.sort(in_menu_keys)
    _info(label, "career=%s slot=%s slot_types=%s menu_count=%d",
        tostring(career_name),
        tostring(selected_slot_name),
        type(item_slot_types) == "table" and table.concat(item_slot_types, ",") or "?",
        #in_menu_keys)
    for _, k in ipairs(in_menu_keys) do
        local d = in_menu_set[k]
        local dn = d and d.display_name or k
        local slot = d and d.slot_type or "?"
        local rarity = d and d.rarity or "?"
        local cw = d and type(d.can_wield) == "table" and table.concat(d.can_wield, ",") or "?"
        _info(label, "  MENU: %s [%s] slot=%s rarity=%s can_wield=[%s]",
            k, tostring(dn), tostring(slot), tostring(rarity), cw)
    end

    -- Section 2: the full ItemMasterList sweep against the same filters cim
    -- applies in `_setup_weapon_list` — but WITHOUT the can_wield gate. This
    -- shows every weapon that matches the slot family for this career, and
    -- whether each passes or fails each filter. That's how we tell "weapon X
    -- isn't in the menu because [reason]" — DLC-locked, wrong slot family,
    -- not in can_wield for this career, deduped on display_name, etc.
    local IML = rawget(_G, "ItemMasterList")
    if type(IML) ~= "table" then
        _info(label, "  ItemMasterList missing — cannot run full sweep")
        return
    end
    local slot_types_set = {}
    if type(item_slot_types) == "table" then
        for _, st in ipairs(item_slot_types) do slot_types_set[st] = true end
    end
    local n_total, n_wrong_slot, n_no_cw, n_not_career, n_skin, n_magic, n_promo, n_dlc = 0, 0, 0, 0, 0, 0, 0, 0
    local missing_from_menu = {}
    for k, d in pairs(IML) do
        if type(d) == "table" then
            n_total = n_total + 1
            local slot = d.slot_type
            if not slot or not slot_types_set[slot] then
                n_wrong_slot = n_wrong_slot + 1
            else
                local cw = d.can_wield
                if type(cw) ~= "table" then
                    n_no_cw = n_no_cw + 1
                else
                    local has_career = false
                    for _, c in ipairs(cw) do
                        if c == career_name then has_career = true; break end
                    end
                    if not has_career then
                        n_not_career = n_not_career + 1
                    elseif d.item_type == "weapon_skin" then
                        n_skin = n_skin + 1
                    elseif d.rarity == "magic" then
                        n_magic = n_magic + 1
                    elseif d.rarity == "promo" then
                        n_promo = n_promo + 1
                    elseif dlc_check_fn and dlc_check_fn(k) then
                        n_dlc = n_dlc + 1
                    elseif not in_menu_set[k] then
                        -- Passes every filter but ISN'T in the menu —
                        -- most likely dedupe on display_name. Log it.
                        missing_from_menu[#missing_from_menu + 1] = {
                            key = k,
                            display_name = d.display_name or k,
                            rarity = d.rarity or "default",
                        }
                    end
                end
            end
        end
    end
    _info(label, "  ItemMasterList sweep: total=%d wrong_slot=%d no_can_wield=%d not_career=%d skin=%d magic=%d promo=%d dlc_locked=%d",
        n_total, n_wrong_slot, n_no_cw, n_not_career, n_skin, n_magic, n_promo, n_dlc)
    if #missing_from_menu > 0 then
        _info(label, "  PASS-FILTERS-BUT-DEDUPED (%d items — same display_name as something already in menu):",
            #missing_from_menu)
        for i, m in ipairs(missing_from_menu) do
            _info(label, "    DEDUPED: %s [%s] rarity=%s", m.key, tostring(m.display_name), tostring(m.rarity))
            if i >= 20 then
                _info(label, "    ... (%d more deduped — truncated)", #missing_from_menu - 20)
                break
            end
        end
    end
end

-- Full widget-list dump (v0.7.56-dev). Called from cim's on_enter hooks on
-- inventory + forge-inventory windows. Walks `_widgets_by_name` and logs every
-- widget name plus its content table top-level keys (so we see which widgets
-- have button_hotspots, text fields, disabled flags, etc.). One-shot per
-- window open. Gated on enable_debug_logging — zero cost when off.
--
-- Purpose: unblock the "disabled search bar" investigation. Static grep of
-- vanilla source + workshop bundles couldn't locate it; this dumps the live
-- widget tree so we can see exactly what's there next session and hook the
-- right widget.
mod._cim_autodump_full_widget_list = function(window_self, window_label)
    if not _enabled() then return end
    if not window_self or type(window_self) ~= "table" then return end
    local label = "widget_list/" .. tostring(window_label or "?")
    local widgets = window_self._widgets_by_name
    if type(widgets) ~= "table" then
        _info(label, "no _widgets_by_name on window (NAME=%s)", tostring(window_self.NAME))
        return
    end
    -- Sort names for stable output
    local names = {}
    for name in pairs(widgets) do names[#names + 1] = tostring(name) end
    table.sort(names)
    _info(label, "===== %d widgets =====", #names)
    for _, name in ipairs(names) do
        local w = widgets[name]
        local content = w and w.content
        if type(content) ~= "table" then
            _info(label, "  %s -- no content table", name)
        else
            -- Top-level content keys (truncate to first ~12 so noisy widgets
            -- don't blow up the log)
            local keys = {}
            for k in pairs(content) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            local n = #keys
            if n > 12 then
                local trimmed = {}
                for i = 1, 12 do trimmed[i] = keys[i] end
                trimmed[#trimmed + 1] = string.format("(+%d more)", n - 12)
                keys = trimmed
            end
            -- Flag interactive widgets (button_hotspot present means clickable)
            local hs = content.button_hotspot
            local hs_state = ""
            if type(hs) == "table" then
                hs_state = string.format(" [hotspot disabled=%s visible=%s]",
                    tostring(hs.disable_button), tostring(content.visible))
            end
            -- Flag text-input widgets (caret / input_text / keystroke fields)
            local text_marker = ""
            if content.caret_position ~= nil or content.input_text ~= nil
                    or content.text or content.text_field then
                text_marker = " [TEXT-LIKE]"
            end
            _info(label, "  %s%s%s -- content keys: %s",
                name, hs_state, text_marker, table.concat(keys, ","))
        end
    end
end

-- Equip event probe (v0.7.54-dev). Called from cim's `BackendInterfaceItemPlayfab.set_loadout_item`
-- hook_safe POST callback. Fires on EVERY equip — vanilla or modded — so we
-- see the full equip cycle. The hook itself runs AFTER vanilla wrote to
-- `_backend_mirror:set_character_data`, so a read-back via `get_loadout_item_id`
-- captures the post-write state.
mod._cim_autodump_equip_event = function(career_name, slot_name, item_id, items_iface)
    if not _enabled() then return end
    local label = "equip_event"

    -- Resolve the item we just equipped
    local resolved = items_iface and items_iface.get_item_from_id
        and items_iface:get_item_from_id(item_id) or nil
    local item_key = "<nil>"
    local item_rarity = "<nil>"
    if resolved then
        item_key = tostring(resolved.key or resolved.ItemId or (resolved.data and resolved.data.key) or "<no-key>")
        item_rarity = tostring(resolved.rarity or "<no-rarity>")
    end

    -- BID heuristic + persistence state
    local is_modded_bid = false
    if mod._cim_is_modded_backend_id then
        local ok, r = pcall(mod._cim_is_modded_backend_id, item_id)
        is_modded_bid = ok and r and true or false
    end
    local saved = mod:get("forged_weapons") or {}
    local in_forged = saved[item_id] ~= nil

    -- Immediate read-back: does the mirror reflect what we just wrote?
    local read_back = "<no-iface>"
    if items_iface and items_iface.get_loadout_item_id then
        local ok, r = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot_name)
        if ok then read_back = tostring(r) end
    end
    local readback_matches = read_back == tostring(item_id)

    _info(label, "career=%s slot=%s item_id=%s key=%s rarity=%s is_modded_bid=%s in_forged_weapons=%s readback=%s matches=%s",
        tostring(career_name),
        tostring(slot_name),
        tostring(item_id),
        item_key,
        item_rarity,
        tostring(is_modded_bid),
        tostring(in_forged),
        read_back,
        tostring(readback_matches))

    -- Loud signal if the mirror didn't accept our write.
    if not readback_matches then
        mod:warning("[cim:diag] Equip read-back MISMATCH — wrote %s but mirror reports %s for career=%s slot=%s. Vanilla rejected or wrote to a different layer.",
            tostring(item_id), tostring(read_back), tostring(career_name), tostring(slot_name))
    end
end

-- Restore pass probe (v0.7.54-dev). Dumps the FULL `_modded_loadout` table
-- contents at the entry of every `_restore_modded_loadout` call, plus a
-- post-restore read-back per restored entry so we can prove whether the
-- mirror write actually stuck. The existing `[restore] OK ...` lines say
-- the write returned true — they DON'T verify the mirror reflects the change.
mod._cim_autodump_restore_pass = function(label_suffix, modded_loadout_table)
    if not _enabled() then return end
    local label = "restore_pass/" .. tostring(label_suffix)
    if type(modded_loadout_table) ~= "table" then
        _info(label, "modded_loadout table is %s", type(modded_loadout_table))
        return
    end
    local total_careers, total_slots = 0, 0
    for career_name, slots in pairs(modded_loadout_table) do
        total_careers = total_careers + 1
        if type(slots) == "table" then
            for slot_name, bid in pairs(slots) do
                total_slots = total_slots + 1
                _info(label, "  saved: %s/%s -> %s",
                    tostring(career_name), tostring(slot_name), tostring(bid))
            end
        end
    end
    _info(label, "total: careers=%d slots=%d", total_careers, total_slots)
end

-- Per-entry restore probe (v0.7.54-dev). Called from `_restore_modded_loadout`
-- AFTER each `items:set_loadout_item(items, bid, career, slot)` call.
-- Immediately reads back via `get_loadout_item_id` to confirm the write stuck.
-- This is the proof-of-write check — if `set_loadout_item` returns ok but the
-- read-back doesn't match, the mirror silently rejected our write.
mod._cim_autodump_restore_entry = function(career_name, slot_name, expected_bid, items_iface, set_ok, set_err)
    if not _enabled() then return end
    local label = "restore_entry"

    local read_back = "<no-iface>"
    if items_iface and items_iface.get_loadout_item_id then
        local ok, r = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot_name)
        if ok then read_back = tostring(r) end
    end
    local matches = read_back == tostring(expected_bid)

    _info(label, "career=%s slot=%s expected_bid=%s read_back=%s matches=%s set_ok=%s err=%s",
        tostring(career_name),
        tostring(slot_name),
        tostring(expected_bid),
        read_back,
        tostring(matches),
        tostring(set_ok),
        tostring(set_err))

    if set_ok and not matches then
        mod:warning("[cim:diag] Restore WRITE-NO-READ — set_loadout_item returned ok for %s/%s -> %s but get_loadout_item_id reads back %s. Mirror silently rejected the write OR a different layer is being read.",
            tostring(career_name), tostring(slot_name), tostring(expected_bid), read_back)
    end
end

-- Drain pending visibility checks. Called from `mod.update` once per frame
-- when there are queued checks. Each check counts down `frames_until_check`;
-- when it hits zero, queries the backend mirror + filter heuristic to confirm
-- the freshly-crafted BID is reachable through the same path the inventory
-- grid uses. Records a SUCCESS or FAIL line so post-hoc diagnosis can tell
-- whether the item became visible after the mirror write settled.
mod._cim_autodump_run_visibility_checks = function()
    if not _enabled() then return end
    local pending = mod._cim_pending_visibility_checks
    if not pending or #pending == 0 then return end
    local still_pending = {}
    for _, check in ipairs(pending) do
        check.frames_until_check = check.frames_until_check - 1
        if check.frames_until_check <= 0 then
            local label = "craft_visibility/" .. tostring(check.path)
            local items_iface = Managers.backend and Managers.backend:get_interface("items")

            -- Re-resolve through the interface (post any reconciliation step)
            local item = items_iface and items_iface.get_item_from_id
                and items_iface:get_item_from_id(check.bid) or nil

            -- Check against get_all_backend_items (the broadest interface view)
            local found_in_all = false
            if items_iface and items_iface.get_all_backend_items then
                local all = items_iface:get_all_backend_items() or {}
                if all[check.bid] then
                    found_in_all = true
                else
                    for _, it in pairs(all) do
                        if it and it.backend_id == check.bid then
                            found_in_all = true; break
                        end
                    end
                end
            end

            local visible_to_career = false
            if item and item.data and type(item.data.can_wield) == "table" then
                for _, c in ipairs(item.data.can_wield) do
                    if c == check.career_name then
                        visible_to_career = true; break
                    end
                end
            end

            local is_modded_bid = false
            if mod._cim_is_modded_backend_id then
                local ok, r = pcall(mod._cim_is_modded_backend_id, check.bid)
                is_modded_bid = ok and r and true or false
            end

            _info(label, "bid=%s 2-frames-post-craft: found_in_all=%s visible_to_career=%s is_modded_bid=%s career=%s",
                tostring(check.bid), tostring(found_in_all), tostring(visible_to_career),
                tostring(is_modded_bid), tostring(check.career_name))
            -- Loud signal if the new item is NOT discoverable — the bug we
            -- chase whenever a user reports "I crafted but it's not there".
            if not found_in_all then
                mod:warning("[cim:diag] Post-craft visibility FAIL — bid=%s (key=%s) not in backend_mirror items 2 frames after craft. Inventory will NOT show it.",
                    tostring(check.bid), tostring(check.item_key))
            elseif not visible_to_career then
                mod:warning("[cim:diag] Post-craft career-gate FAIL — bid=%s (key=%s) is in mirror but can_wield does not include current career '%s'. Switch careers to see it.",
                    tostring(check.bid), tostring(check.item_key), tostring(check.career_name))
            end
        else
            still_pending[#still_pending + 1] = check
        end
    end
    mod._cim_pending_visibility_checks = still_pending
end

-- Craft button press entry-point (v0.7.50-dev). Called from
-- `BackendInterfaceCraftingPlayfab.craft` hook in standard_forge.lua at the
-- top of the cim-active branch, BEFORE any of the three discriminating drop
-- checks. Captures all three inputs and the first 3 item bids so post-hoc
-- diagnosis of "crafts failed and I don't know why" reports has the full
-- input state, not just the rejection reason.
mod._cim_autodump_craft_attempt = function(career_name, item_backend_ids, recipe_override)
    if not _enabled() then return end
    local label = "craft_attempt"
    local items_len = (item_backend_ids and #item_backend_ids) or 0
    local bid1 = item_backend_ids and item_backend_ids[1]
    local bid2 = item_backend_ids and item_backend_ids[2]
    local bid3 = item_backend_ids and item_backend_ids[3]
    _info(label, "career=%s recipe=%s items_len=%d bid1=%s bid2=%s bid3=%s",
        tostring(career_name),
        tostring(recipe_override),
        items_len,
        tostring(bid1),
        tostring(bid2),
        tostring(bid3))
    -- Also dump the item key/slot for the first item so we can tell whether
    -- it was a real template (wpn_dr_dr_handgun_01 etc.) or some stale BID.
    if bid1 then
        local items_iface = Managers.backend and Managers.backend:get_interface("items")
        local item = items_iface and items_iface.get_item_from_id and items_iface:get_item_from_id(bid1)
        if item then
            local key = item.key or (item.data and item.data.key) or "<no key>"
            local slot = (item.data and item.data.slot_type) or "<no slot>"
            local rarity = item.rarity or "<no rarity>"
            _info(label, "bid1 resolves to: key=%s slot=%s rarity=%s",
                tostring(key), tostring(slot), tostring(rarity))
        else
            _info(label, "bid1=%s does NOT resolve via items interface (stale or unknown bid)",
                tostring(bid1))
        end
    end
end

-- Backend interfaces ready (BackendManagerPlayFab._create_interfaces hook).
mod._cim_autodump_backend_ready = function()
    if not _enabled() then return end
    local label = "backend_ready"
    local fw = mod:get("forged_weapons") or {}
    local fw_count = 0
    for _ in pairs(fw) do fw_count = fw_count + 1 end
    local ml = mod:get("modded_loadout") or {}
    local ml_total = 0
    for _, slots in pairs(ml) do
        for _ in pairs(slots) do ml_total = ml_total + 1 end
    end
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    local mirror_size = 0
    if items_iface and items_iface.get_all_backend_items then
        for _ in pairs(items_iface:get_all_backend_items() or {}) do mirror_size = mirror_size + 1 end
    end
    _info(label, "backend interfaces created: mirror_size=%d forged_weapons=%d modded_loadout_entries=%d",
        mirror_size, fw_count, ml_total)
end

-- ============================================================
-- Hook wiring
-- ============================================================
-- The HeroWindowCrafting / HeroWindowCraftingConsole / HeroWindowItemCustomization
-- `on_enter` autodumps live in the consolidated lifecycle callback in
-- `standard_forge.lua` (VMF silently drops sibling hook_safe registrations on
-- the same Class+method — feedback_vmf_hook_safe_no_chain). The restore-done
-- and backend-ready autodumps are wired inline at their call sites in
-- `crafting_in_modded.lua`. The remaining three classes have no existing cim
-- on_enter hook, so we register them here.

mod:hook_safe("HeroViewStateWeaveForge", "on_enter", function(self)
    if mod._cim_autodump_athanor_open then pcall(mod._cim_autodump_athanor_open) end
end)

mod:hook_safe("HeroWindowWeaveProperties", "on_enter", function(self)
    if mod._cim_autodump_props_open then pcall(mod._cim_autodump_props_open, self) end
    if mod._cim_autodump_jewelry_probe then
        pcall(mod._cim_autodump_jewelry_probe, self, "HeroWindowWeaveProperties")
    end
end)

-- Athanor sub-window opens. Both are siblings in the WeaveForge state.
mod:hook_safe("HeroWindowWeaveForgeOverview", "on_enter", function(self)
    if mod._cim_autodump_athanor_overview_open then
        pcall(mod._cim_autodump_athanor_overview_open, self)
    end
    if mod._cim_autodump_jewelry_probe then
        pcall(mod._cim_autodump_jewelry_probe, self, "HeroWindowWeaveForgeOverview")
    end
end)

mod:hook_safe("HeroWindowWeaveForgeWeapons", "on_enter", function(self)
    if mod._cim_autodump_athanor_weapons_open then
        pcall(mod._cim_autodump_athanor_weapons_open, self)
    end
    if mod._cim_autodump_jewelry_probe then
        pcall(mod._cim_autodump_jewelry_probe, self, "HeroWindowWeaveForgeWeapons")
    end
end)

-- Loadout / inventory / crafting-list surfaces where "JEWELRY" might still
-- render. The following classes are NOT in this list because they already
-- have a sibling `hook_safe` on `on_enter` elsewhere in cim — a duplicate
-- registration here would be silently dropped by VMF (and emits a noisy
-- `Attempting to rehook active hook` warning at boot):
--
--   - HeroWindowCrafting / HeroWindowCraftingConsole / HeroWindowItemCustomization:
--     hooked by standard_forge.lua's consolidated lifecycle callback. Probe is
--     invoked from within `_cim_autodump_forge_open`.
--   - HeroWindowLoadoutInventory: hooked by modded_rarities.lua's
--     "Accessories" category mutation. Probe is invoked from that callback.
--
-- Caught at v0.7.50-dev when the boot log showed `[cim][WARNING]
-- (hook_safe): Attempting to rehook active hook [on_enter]` — the
-- HeroWindowLoadoutInventory entry was here AND in modded_rarities.lua.
-- The new `no_duplicate_hook_safe_registrations` regression check fails on
-- any future re-introduction.
for _, klass in ipairs({
    "HeroWindowLoadoutInventoryConsole",
    "HeroWindowCraftingList",
    "HeroWindowCraftingListConsole",
    "HeroWindowCraftingInventoryConsole",
}) do
    if rawget(_G, klass) then
        local class_name = klass
        mod:hook_safe(klass, "on_enter", function(self)
            if mod._cim_autodump_jewelry_probe then
                pcall(mod._cim_autodump_jewelry_probe, self, class_name)
            end
        end)
    end
end

-- Standard-forge recipe page changes. Vanilla `_change_recipe_page` writes
-- `self._active_recipe` before returning, so a hook_safe post-callback can
-- read the new recipe from `self`. No collision with cim's existing hooks
-- on this class (we hook `update` for the accessory buttons in standard_forge.lua;
-- _change_recipe_page is a separate method).
mod:hook_safe("HeroWindowCrafting", "_change_recipe_page", function(self, current_page)
    if mod._cim_autodump_recipe_page_change then
        pcall(mod._cim_autodump_recipe_page_change, self, current_page)
    end
end)
if rawget(_G, "HeroWindowCraftingConsole") then
    mod:hook_safe("HeroWindowCraftingConsole", "_change_recipe_page", function(self, current_page)
        if mod._cim_autodump_recipe_page_change then
            pcall(mod._cim_autodump_recipe_page_change, self, current_page)
        end
    end)
end

for _, klass in ipairs({ "CraftPageSalvage", "CraftPageSalvageConsole" }) do
    if rawget(_G, klass) then
        mod:hook_safe(klass, "on_enter", function(self)
            if mod._cim_autodump_salvage_open then pcall(mod._cim_autodump_salvage_open) end
        end)
    end
end

mod:info("[cim-debug] module loaded (enable_debug_logging=%s)", _enabled() and "ON" or "OFF")
