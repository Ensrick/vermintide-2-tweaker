-- Owns CIM's vanilla-safe rarity substitution, same-mod presentation metadata
-- side channel, schema gate, and pre-decode unknown-item guard.

return function(context)
    assert(type(context) == "table", "_cim_loadout_wire_owner requires context")
    local mod = assert(context.mod, "_cim_loadout_wire_owner requires mod")
    local rpc_schema = assert(context.rpc_schema,
        "_cim_loadout_wire_owner requires rpc_schema")
    local dbg_alert = assert(context.dbg_alert,
        "_cim_loadout_wire_owner requires dbg_alert")
    local print_line = context.print_line or printf
    local get_managers = context.get_managers or function() return Managers end

    local modded_slot_state = {}
    local log_count = 0
    local LOG_LIMIT = 24

    local function unique_id(peer_id, local_player_id)
        return tostring(peer_id) .. ":" .. tostring(local_player_id)
    end

    local function apply_modded_slot_metadata(peer_id, local_player_id,
            slot_name, is_modded, source)
        if type(slot_name) ~= "string"
                or (is_modded ~= true and is_modded ~= false) then
            if log_count < LOG_LIMIT then
                log_count = log_count + 1
                print_line("[cim:921] dropped invalid rarity metadata source=%s peer=%s slot=%s value=%s count=%d/%d",
                    tostring(source), tostring(peer_id), tostring(slot_name),
                    tostring(is_modded), log_count, LOG_LIMIT)
            end
            return false
        end

        local uid = unique_id(peer_id, local_player_id)
        local slot_state = modded_slot_state[uid]
        if not slot_state then
            slot_state = {}
            modded_slot_state[uid] = slot_state
        end
        local prior = slot_state[slot_name]
        slot_state[slot_name] = is_modded

        local before, after
        local managers = get_managers()
        local player_manager = managers and managers.player
        local loadouts = player_manager and player_manager._player_loadouts
        local stored = loadouts and loadouts[uid] and loadouts[uid][slot_name]
        if stored then
            before = stored.rarity
            local core = mod._cim246_tab_preview_core
            if core and core.resolve_rarity then
                after = core.resolve_rarity(before, true, is_modded)
            elseif is_modded then
                after = "modded"
            elseif before == "modded" then
                after = "unique"
            else
                after = before
            end
            stored.rarity = after
        end

        if log_count < LOG_LIMIT
                and (prior ~= is_modded or (before ~= nil and before ~= after)) then
            log_count = log_count + 1
            print_line("[cim:921] rarity metadata source=%s peer=%s slot=%s prior=%s current=%s stored=%s->%s count=%d/%d",
                tostring(source), tostring(peer_id), tostring(slot_name),
                tostring(prior), tostring(is_modded), tostring(before),
                tostring(after), log_count, LOG_LIMIT)
        end
        return true
    end
    mod._cim_apply_modded_slot_metadata = apply_modded_slot_metadata

    mod:set("persist_modded_loadouts", false, false)
    local function persist_loadouts_enabled()
        return mod:get("persist_modded_loadouts") == true
    end
    mod._cim_persist_loadouts_enabled = persist_loadouts_enabled

    local function wire_safe_rarity(rarity)
        if rarity == "modded" then return "unique" end
        return rarity
    end
    mod._cim_wire_safe_rarity = wire_safe_rarity

    local loadout_utils = rawget(_G, "LoadoutUtils")
    if loadout_utils and loadout_utils.sync_loadout_slot then
        mod:hook(loadout_utils, "sync_loadout_slot",
            function(func, player, slot_name, item, sync_to_specific_peer_id)
                local is_modded = item and item.rarity == "modded" or false
                local peer_id = player:network_id()
                local local_player_id = player:local_player_id()
                apply_modded_slot_metadata(peer_id, local_player_id, slot_name,
                    is_modded, "sender")
                local target = sync_to_specific_peer_id or "others"
                local ok_send, err_send = pcall(mod.network_send, mod,
                    "cim_modded_slot", target, rpc_schema, peer_id,
                    local_player_id, slot_name, is_modded)
                if not ok_send then
                    mod:info("[cim] side-channel send failed: %s",
                        tostring(err_send))
                end
                if not is_modded then
                    return func(player, slot_name, item,
                        sync_to_specific_peer_id)
                end
                local original = item.rarity
                item.rarity = wire_safe_rarity(original)
                local ok, err = pcall(func, player, slot_name, item,
                    sync_to_specific_peer_id)
                item.rarity = original
                if not ok then
                    mod:info("[cim] sync_loadout_slot rewrite error: %s",
                        tostring(err))
                end
            end)
    end

    local function rpc_modded_slot(sender_peer_id, schema_version, peer_id,
            local_player_id, slot_name, is_modded)
        if schema_version ~= rpc_schema then
            dbg_alert("[rpc:schema] cim_modded_slot mismatch from peer=%s: peer sent v%s, we expect v%s. Dropping.",
                tostring(sender_peer_id), tostring(schema_version),
                tostring(rpc_schema))
            return
        end
        apply_modded_slot_metadata(peer_id, local_player_id, slot_name,
            is_modded, "receiver")
    end
    mod:network_register("cim_modded_slot", rpc_modded_slot)
    mod._cim_rpc_modded_slot = rpc_modded_slot
    mod._cim_modded_slot_state = modded_slot_state

    mod:hook("PlayerManager", "rpc_sync_loadout_slot", function(func, self,
            channel_id, peer_id, local_player_id, slot_id, item_id, rarity_id,
            power_level, buff_ids, buff_value_type_ids, buff_values)
        local network_lookup = rawget(_G, "NetworkLookup")
        local names = network_lookup and network_lookup.item_names
        if names and item_id ~= nil and rawget(names, item_id) == nil then
            print_line("[cim:278] ALERT dropped rpc_sync_loadout_slot: item_names id %s unknown on this peer (from peer=%s slot_id=%s rarity_id=%s). Host/client modded-item registration diverges — make sure every peer runs the same mods and current builds.",
                tostring(item_id), tostring(peer_id), tostring(slot_id),
                tostring(rarity_id))
            return
        end

        func(self, channel_id, peer_id, local_player_id, slot_id, item_id,
            rarity_id, power_level, buff_ids, buff_value_type_ids, buff_values)

        local uid = unique_id(peer_id, local_player_id)
        local slot_state = modded_slot_state[uid]
        if not slot_state then return end
        local slot_name = network_lookup and network_lookup.equipment_slots
            and network_lookup.equipment_slots[slot_id]
        if not slot_name or slot_state[slot_name] == nil then return end
        local stored = self._player_loadouts and self._player_loadouts[uid]
            and self._player_loadouts[uid][slot_name]
        if stored then
            local is_modded = slot_state[slot_name]
            stored.rarity = mod._cim246_tab_preview_core
                and mod._cim246_tab_preview_core.resolve_rarity(
                    stored.rarity, true, is_modded)
                or (is_modded and "modded"
                    or (stored.rarity == "modded" and "unique"
                        or stored.rarity))
        end
    end)
    mod._cim_rpc_loadout_guard_installed = true

    return {
        apply_modded_slot_metadata = apply_modded_slot_metadata,
        get_modded_slot_state = function() return modded_slot_state end,
        persist_loadouts_enabled = persist_loadouts_enabled,
        rpc_modded_slot = rpc_modded_slot,
        wire_safe_rarity = wire_safe_rarity,
    }
end
