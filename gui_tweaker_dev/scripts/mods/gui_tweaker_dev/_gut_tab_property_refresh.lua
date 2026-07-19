-- Single live-session Hold-Tab loadout provider (#245 properties/traits,
-- #246 equipped illusion, #250 Chaos Wastes talents, #533 CW collectible rows).
-- File name is historical (#245 shipped first); this module is the ONE owner of
-- gut's hooks on the held-Tab player list and replaces the per-symptom patches.
--
-- MECHANISM (decompile-verified): the held-Tab panel does NOT read the live
-- backend. Its per-player rows render from Managers.player:player_loadouts()
-- [src: ingame_player_list_ui_v2.lua:1450,1507,1527-1539], a table populated
-- ONLY at SimpleInventoryExtension.add_equipment time via
-- LoadoutUtils.sync_loadout_slot -> rpc_sync_loadout_slot (send_rpc_all loops
-- back locally through queue_local_rpc, network_transmit.lua:514) [src:
-- simple_inventory_extension.lua:883-885; player_manager.lua:69-84]. The
-- reconstructed row carries ONLY data/key/ItemId/power_level/rarity/
-- properties/traits - the wire format has NO skin field [src:
-- loadout_utils.lua:13-43,70-88] - and is never re-synced by a mid-session
-- reforge (#245) or illusion change (#246: the icon pass shows an illusion
-- only when item.skin is set, ui_utils.lua:238-245). Talents (#250) are
-- already LIVE (talent_extension:get_talent_ids(), deus-aware, re-synced on
-- boon grants via rpc_sync_talents) - the panel's fixed six positional widgets
-- are what mis-render the deus flat list; _gut_tab_talent_refresh.lua owns
-- that repair. Collectible rows (#533) build from adventure loot objectives
-- with no mechanism gate [src: ingame_player_list_ui_v2.lua:436-514].
--
-- WHAT THIS PROVIDER DOES, per refresh tick while the panel is active:
--   * LOCAL player weapon slots (exact-instance evidence, allowed per
--     docs/WEAPON_APPEARANCE_STANDARD section 2): re-resolve the equipped
--     backend item from the live inventory extension's backend_id and
--     reconcile the cached row's properties, traits, and skin from it.
--   * EVERY player's weapon slots (synchronized (wearer, slot) evidence):
--     resolve the equipped skin from CosmeticUtils.get_cosmetic_slot (the
--     player sync-data written at add_equipment, cosmetic_utils.lua:230-294)
--     and decorate the cached row's skin. Absent/unresolvable evidence
--     preserves the vanilla reconstruction; a skin name is written ONLY when
--     its template is locally resident (the vanilla icon pass derefs
--     WeaponSkins.skins[skin] unguarded).
--   * DISPLAY-ONLY: the cache mutation feeds the panel's own icon + tooltip
--     passes; no RPC is sent, no NetworkLookup table is touched, and the
--     wire-safety filters in _gut_tab_property_policy keep any vanilla
--     hot-join resync of the row serializable.
-- Plus two panel-scoped hooks:
--   * IngamePlayerListUI._update_dynamic_widget_information [hook] - the ONE
--     shared update seam (pre-flight: no other gut hook on it; grep before
--     adding any). Refresh runs BEFORE vanilla renders; the #250 talent
--     repair runs AFTER vanilla populated the talent widgets.
--   * IngamePlayerListUI._setup_mission_data [hook] (#533) - inside the deus
--     mechanism the adventure tome/grim/dice rows are suppressed (skip leaves
--     self._mission_count at its init 0, so the Collectibles header hides,
--     ingame_player_list_ui_v2.lua:94-97,1663-1666). Pre-flight: no other gut
--     hook on this method.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_tab_property_policy")
local talent_ok, TalentRefresh = pcall(mod.dofile, mod,
    "scripts/mods/gui_tweaker_dev/_gut_tab_talent_refresh")
local window = rawget(_G, "IngamePlayerListUI")
local slots = { "slot_melee", "slot_ranged" }
local _printf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end
local log_count = 0
local skin_log_count = 0
local hook_installed = false
local mission_rows_hook_installed = false

local function skin_template_exists(skin_name)
    local weapon_skins = rawget(_G, "WeaponSkins")
    local skins = weapon_skins and weapon_skins.skins
    return skins ~= nil and rawget(skins, skin_name) ~= nil
end

-- Live equipped backend item for the LOCAL player's slot (exact instance):
-- the same backend_id read vanilla itself performs at add_equipment
-- [src: simple_inventory_extension.lua:882-883]. Plain call-time read, not a
-- mirror hook, so the get_item_from_id recursion trap does not apply here.
local function live_local_item(items, equipment, slot_name)
    local slot = equipment and equipment.slots and equipment.slots[slot_name]
    local backend_id = slot and slot.item_data and slot.item_data.backend_id
    return backend_id and items:get_item_from_id(backend_id) or nil, backend_id
end

-- Synchronized (wearer, slot) skin evidence for ANY player: CosmeticUtils sync
-- data (player:get_data(slot .. "_skin"), set at add_equipment and replicated
-- cross-peer) [src: cosmetic_utils.lua:230-294]. Returns known, skin_name -
-- known=false means NO evidence (preserve), known=true with nil skin means the
-- wearer has no illusion applied (clear a stale decoration).
local function synced_skin(player, slot_name)
    local cosmetic_utils = rawget(_G, "CosmeticUtils")
    if not (cosmetic_utils and cosmetic_utils.get_cosmetic_slot) then
        return false, nil
    end
    local ok, data = pcall(cosmetic_utils.get_cosmetic_slot, player, slot_name)
    if not ok or type(data) ~= "table" then
        return false, nil
    end
    return true, data.skin_name
end

local function refresh_local(self)
    local manager = Managers and Managers.player
    local loadouts = manager and manager:player_loadouts()
    local items = Managers and Managers.backend
        and Managers.backend:get_interface("items")
    if type(loadouts) ~= "table" then return 0 end

    local network_lookup = rawget(_G, "NetworkLookup")
    local changed = 0
    for _, player_data in ipairs(self._players or {}) do
        local player = player_data.player
        local unit = player and player.player_unit
        if player and unit and ALIVE[unit] then
            local is_local = player.local_player and true or false
            local inventory = ScriptUnit.has_extension(unit, "inventory_system")
            local equipment = inventory and inventory:equipment()
            local cached = loadouts[player:unique_id()]
            for _, slot_name in ipairs(slots) do
                local cached_item = cached and cached[slot_name]
                if cached_item then
                    local live_item, backend_id
                    if is_local and items then
                        live_item, backend_id = live_local_item(items, equipment, slot_name)
                    end
                    -- #245: properties + traits from the exact live instance
                    -- (local player only - remote reforges never re-sync and
                    -- carry no live evidence on this machine; their row keeps
                    -- the vanilla snapshot).
                    if live_item then
                        local apply, properties = Policy.refresh(cached_item, live_item)
                        if apply then
                            cached_item.properties = Policy.wire_safe_properties(
                                properties, network_lookup and network_lookup.properties)
                            changed = changed + 1
                            if log_count < Policy.MAX_LOGS then
                                log_count = log_count + 1
                                _printf("[gut:245] slot=%s backend_id=%s properties=%s refresh=%d/%d",
                                    slot_name, tostring(backend_id),
                                    Policy.fingerprint(cached_item.properties), log_count, Policy.MAX_LOGS)
                            end
                        end
                        local tapply, traits = Policy.refresh_traits(cached_item, live_item)
                        if tapply then
                            cached_item.traits = Policy.wire_safe_traits(
                                traits, network_lookup and network_lookup.traits)
                            changed = changed + 1
                            if log_count < Policy.MAX_LOGS then
                                log_count = log_count + 1
                                _printf("[gut:245] slot=%s backend_id=%s traits=%s refresh=%d/%d",
                                    slot_name, tostring(backend_id),
                                    Policy.traits_fingerprint(cached_item.traits), log_count, Policy.MAX_LOGS)
                            end
                        end
                    end
                    -- #246: equipped illusion. Exact instance first (local),
                    -- else the synchronized (wearer, slot) cosmetic identity,
                    -- else preserve the vanilla reconstruction.
                    local synced_known, synced_name = synced_skin(player, slot_name)
                    local new_skin, source, skin_changed = Policy.resolve_skin(
                        live_item ~= nil, live_item and live_item.skin,
                        synced_known, synced_name,
                        cached_item.skin, skin_template_exists)
                    if skin_changed then
                        cached_item.skin = new_skin
                        changed = changed + 1
                        if skin_log_count < Policy.MAX_LOGS then
                            skin_log_count = skin_log_count + 1
                            _printf("[gut:246] slot=%s local=%s source=%s skin=%s refresh=%d/%d",
                                slot_name, tostring(is_local), tostring(source),
                                tostring(new_skin), skin_log_count, Policy.MAX_LOGS)
                        end
                    end
                end
            end
        end
    end
    return changed
end

if window and type(window._update_dynamic_widget_information) == "function" then
    mod:hook(window, "_update_dynamic_widget_information", function(func, self, dt, t)
        if self._active == true then
            local now = tonumber(t) or 0
            if not self._gut245_next_refresh or now >= self._gut245_next_refresh then
                self._gut245_next_refresh = now + Policy.INTERVAL
                refresh_local(self)
            end
        end
        local result = func(self, dt, t)
        if talent_ok and type(TalentRefresh) == "table" then
            TalentRefresh.refresh(self)
        end
        return result
    end)
    hook_installed = true
end

-- #533: suppress the adventure tome/grim/dice collectible rows inside the deus
-- mechanism (Chaos Wastes, including ct-injected adventure maps): those rows
-- read adventure bonus-mission counters that do not track the CW run's
-- pilgrim-coin/chest collectibles. Skipping the builder leaves
-- self._mission_count at its _create_ui_elements init of 0, which also hides
-- the Collectibles header + divider [src: ingame_player_list_ui_v2.lua:94-97,
-- 507-514,1663-1666]. The deus check mirrors the panel's own CW-info gate
-- [src: ingame_player_list_ui_v2.lua:292-309].
if window and type(window._setup_mission_data) == "function" then
    mod:hook(window, "_setup_mission_data", function(func, self, level_settings)
        local mechanism = Managers and Managers.mechanism
        local mechanism_name = mechanism and mechanism.current_mechanism_name
            and mechanism:current_mechanism_name()
        if Policy.suppress_adventure_loot_rows(mechanism_name) then
            _printf("[gut:533] adventure collectible rows suppressed (mechanism=%s, loot_objectives=%s)",
                tostring(mechanism_name),
                tostring(level_settings and level_settings.loot_objectives ~= nil))
            return
        end
        return func(self, level_settings)
    end)
    mission_rows_hook_installed = true
end

return {
    policy = Policy,
    refresh_local = refresh_local,
    rt_checks = {
        {
            name = "issue245_tab_weapon_property_refresh",
            fn = function()
                if not hook_installed then
                    return "IngamePlayerListUI dynamic-update hook missing"
                end
                if Policy.INTERVAL < 0.25 or Policy.MAX_LOGS > 16 then
                    return "refresh/log performance bounds drifted"
                end
                local changed, values = Policy.refresh({ key = "weapon", properties = { a = 1 } },
                    { key = "weapon", properties = { a = 2 } })
                if not changed or not values or values.a ~= 2 then
                    return "property refresh policy failed"
                end
                local tchanged, tvalues = Policy.refresh_traits(
                    { key = "weapon", traits = { "old_trait" } },
                    { key = "weapon", traits = { "new_trait" } })
                if not tchanged or not tvalues or tvalues[1] ~= "new_trait" then
                    return "trait refresh policy failed"
                end
                return nil
            end,
        },
        {
            name = "issue246_tab_equipped_illusion_refresh",
            fn = function()
                local exists = function(name) return name == "known_skin" end
                local skin, source, changed = Policy.resolve_skin(
                    true, "known_skin", true, "other", nil, exists)
                if skin ~= "known_skin" or source ~= "live_backend" or not changed then
                    return "issue 246 regression: exact-instance skin does not win"
                end
                skin, source, changed = Policy.resolve_skin(
                    false, nil, true, "unknown_skin", "kept", exists)
                if skin ~= "kept" or source ~= "unresolved_template" or changed then
                    return "issue 246 regression: unresolvable skin template not preserved"
                end
                skin, source, changed = Policy.resolve_skin(
                    false, nil, false, nil, "kept", exists)
                if skin ~= "kept" or source ~= "preserved" or changed then
                    return "issue 246 regression: no-evidence row not preserved"
                end
                return nil
            end,
        },
        {
            name = "issue250_deus_tab_talent_module_loaded",
            fn = function()
                if not talent_ok or type(TalentRefresh) ~= "table" then
                    return "Tab talent normalization module failed to load: "
                        .. tostring(TalentRefresh)
                end
                local check = TalentRefresh.rt_checks and TalentRefresh.rt_checks[1]
                return check and check.fn() or "Tab talent runtime check missing"
            end,
        },
        {
            name = "issue533_cw_collectible_rows_suppressed",
            fn = function()
                if not mission_rows_hook_installed then
                    return "IngamePlayerListUI._setup_mission_data hook missing"
                end
                if not Policy.suppress_adventure_loot_rows("deus") then
                    return "issue 533 regression: deus mechanism does not suppress adventure loot rows"
                end
                if Policy.suppress_adventure_loot_rows("adventure")
                    or Policy.suppress_adventure_loot_rows(nil) then
                    return "issue 533 regression: non-deus mechanisms must keep vanilla rows"
                end
                return nil
            end,
        },
    },
}
