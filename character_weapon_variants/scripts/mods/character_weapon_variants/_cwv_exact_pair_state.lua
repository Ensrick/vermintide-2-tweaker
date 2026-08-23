-- Exact generated-pair presentation state (#567).
--
-- Vanilla equipment RPCs encode weapon skins through a strict, boot-order-
-- sensitive NetworkLookup. CWV must null that id while peer parity is unknown,
-- but a mission transition can remain unknown long enough for the replay to
-- expire. This VMF channel carries only the already-registered skin string to
-- peers which have this module. Unknown/non-CWV peers never decode a modded
-- NetworkLookup id. Traffic is transition-driven: no update loop.

local M = {}

local CHANNEL = "cwv_exact_pair_state_v1"
local SCHEMA = 1
local BASE_ITEM = "es_dual_wield_hammer_sword"
local SKIN_PREFIX = "cwv_es_sword_and_mace_"
local TRACKED_TX_REASONS = {
    gameplay_enter = true,
    game_object_initialized = true,
    hot_join_sync = true,
    query_reply = true,
    spawn_resynced_loadout = true,
    wield = true,
}

local function is_exact_skin(skin)
    return type(skin) == "string" and skin:sub(1, #SKIN_PREFIX) == SKIN_PREFIX
end

function M.install(mod, om)
    local by_peer = {}
    local diagnostics = {}
    local diagnostic_count = 0
    local applying = setmetatable({}, { __mode = "k" })
    local published_exact = {}
    local evidence = {
        tx_reasons = {},
        apply_surfaces = {},
        tx_clear = false,
        rx_state = false,
        rx_cached_absent = false,
        rx_clear = false,
    }

    local function log_once(key, fmt, ...)
        if diagnostics[key] or diagnostic_count >= 40 then return end
        diagnostics[key], diagnostic_count = true, diagnostic_count + 1
        pcall(printf, "[cwv:567] " .. fmt, ...)
    end

    local function send(recipient, op, slot_name, skin)
        if type(mod.network_send) ~= "function" then return false end
        return pcall(function()
            mod:network_send(CHANNEL, recipient or "others", SCHEMA, op,
                slot_name or "", skin or "")
        end)
    end

    local function equipment_of(inv)
        if not inv then return nil end
        if type(inv.equipment) == "function" then
            local ok, equipment = pcall(inv.equipment, inv)
            if ok then return equipment end
        end
        return inv._equipment
    end

    function om._exact_pair_publish_inventory(inv, reason, recipient)
        local equipment = equipment_of(inv)
        local slots = equipment and equipment.slots
        if type(slots) ~= "table" then return 0 end
        local sent = 0
        for slot_name, slot in pairs(slots) do
            if type(slot_name) == "string" and type(slot) == "table" then
                local exact = is_exact_skin(slot.skin)
                local sent_ok = send(recipient, exact and "state" or "clear", slot_name,
                    exact and slot.skin or "")
                if sent_ok then sent = sent + 1 end
                if exact and sent_ok then
                    published_exact[slot_name] = slot.skin
                    if TRACKED_TX_REASONS[reason] then evidence.tx_reasons[reason] = true end
                    log_once("tx:" .. tostring(slot_name) .. ":" .. slot.skin .. ":" .. tostring(reason),
                        "exact-pair tx slot=%s skin=%s reason=%s",
                        tostring(slot_name), slot.skin, tostring(reason))
                elseif sent_ok and published_exact[slot_name] then
                    published_exact[slot_name] = nil
                    evidence.tx_clear = true
                    log_once("tx-clear:" .. tostring(slot_name),
                        "exact-pair clear tx slot=%s reason=%s",
                        tostring(slot_name), tostring(reason))
                end
            end
        end
        return sent
    end

    function om._exact_pair_publish_local(reason, recipient)
        local pm = Managers and Managers.player
        local ok, player = false, nil
        if pm then ok, player = pcall(pm.local_player, pm, 1) end
        player = ok and player or nil
        local unit = player and player.player_unit
        if not unit or not Unit.alive(unit) then return 0 end
        local iok, inv = pcall(ScriptUnit.extension, unit, "inventory_system")
        return iok and om._exact_pair_publish_inventory(inv, reason, recipient) or 0
    end

    local function peer_for_owner(owner_unit)
        local pm = Managers and Managers.player
        local ok, player = false, nil
        if pm then ok, player = pcall(pm.owner, pm, owner_unit) end
        player = ok and player or nil
        if not player then return nil end
        if type(player.peer_id) == "string" then return player.peer_id end
        local nok, peer_id = pcall(player.network_id, player)
        return nok and peer_id or nil
    end

    local function apply(inv, slot_name, skin, surface)
        if not inv or applying[inv] or not is_exact_skin(skin) then return false end
        local equipment = equipment_of(inv)
        local slot = equipment and equipment.slots and equipment.slots[slot_name]
        local item = slot and slot.item_data
        if not item or (item.name ~= BASE_ITEM and item.key ~= BASE_ITEM) then return false end
        if slot.skin == skin then
            evidence.apply_surfaces[surface] = true
            log_once("apply-retained:" .. tostring(inv) .. ":" .. slot_name .. ":" .. skin .. ":" .. surface,
                "exact-pair apply surface=%s slot=%s skin=%s accepted=true retained=true",
                surface, slot_name, skin)
            return true
        end
        applying[inv] = true
        local was_wielded = equipment.wielded_slot == slot_name or inv.wielded_slot == slot_name
        local add_ok = pcall(inv.add_equipment, inv, slot_name, BASE_ITEM, skin)
        local after = equipment_of(inv)
        local retained = after and after.slots and after.slots[slot_name]
            and after.slots[slot_name].skin == skin
        local ok = add_ok and retained
        -- #1145: `add_equipment` is the state change and stays synchronous; only
        -- the re-wield is deferred through the per-wearer coalescer, so this
        -- arrival edge can no longer stack a wield on top of the identity-arrival
        -- and la-state pulses landing in the same frame. The drain re-checks the
        -- husk game object, so a mid-destroy wearer is skipped rather than
        -- re-entering wield on a dead id. The deferred wield runs outside this
        -- `applying` bracket by design: it re-enters `apply` only through
        -- `_exact_pair_on_husk_wield`, which short-circuits on `slot.skin == skin`.
        local owner_unit = inv.owner_unit or inv._unit
        if ok and was_wielded then
            if owner_unit and mod._cwv_rewield then
                mod._cwv_rewield.request(owner_unit,
                    "exact-pair:" .. tostring(surface) .. ":" .. slot_name,
                    function() pcall(inv.wield, inv, slot_name) end)
            else
                ok = pcall(inv.wield, inv, slot_name)
            end
        end
        applying[inv] = nil
        if ok then evidence.apply_surfaces[surface] = true end
        log_once("apply:" .. tostring(inv) .. ":" .. slot_name .. ":" .. skin .. ":" .. surface,
            "exact-pair apply surface=%s slot=%s skin=%s accepted=%s wielded=%s",
            surface, slot_name, skin, tostring(ok), tostring(was_wielded))
        return ok
    end

    function om._exact_pair_on_husk_wield(inv, slot_name)
        local peer_id = peer_for_owner(inv and (inv.owner_unit or inv._unit))
        local skin = peer_id and by_peer[peer_id] and by_peer[peer_id][slot_name]
        if skin then apply(inv, slot_name, skin, "husk_reconstruction") end
    end

    if type(mod.network_register) == "function" then
        pcall(function()
            mod:network_register(CHANNEL, function(sender_peer_id, schema, op, slot_name, skin)
                if schema ~= SCHEMA then return end
                if op == "query" then
                    om._exact_pair_publish_local("query_reply", sender_peer_id)
                    return
                end
                if type(slot_name) ~= "string" or slot_name == "" then return end
                local slots = by_peer[sender_peer_id] or {}
                if op == "clear" then
                    if is_exact_skin(slots[slot_name]) then
                        evidence.rx_clear = true
                        log_once("rx-clear:" .. tostring(sender_peer_id) .. ":" .. slot_name,
                            "exact-pair clear rx peer=%s slot=%s",
                            tostring(sender_peer_id), slot_name)
                    end
                    by_peer[sender_peer_id], slots[slot_name] = slots, nil
                    return
                end
                if op ~= "state" or not is_exact_skin(skin) then return end
                by_peer[sender_peer_id], slots[slot_name] = slots, skin
                evidence.rx_state = true
                local pm = Managers and Managers.player
                local ok, player = false, nil
                if pm then
                    ok, player = pcall(pm.player_from_peer_id, pm, sender_peer_id, 1)
                end
                player = ok and player or nil
                local unit = player and player.player_unit
                local iok, inv = false, nil
                if unit and Unit.alive(unit) then
                    iok, inv = pcall(ScriptUnit.extension, unit, "inventory_system")
                end
                if iok then
                    apply(inv, slot_name, skin, "remote_transition")
                else
                    evidence.rx_cached_absent = true
                end
                log_once("rx:" .. tostring(sender_peer_id) .. ":" .. slot_name .. ":" .. skin,
                    "exact-pair rx peer=%s slot=%s skin=%s",
                    tostring(sender_peer_id), slot_name, skin)
            end)
        end)
    end

    function om._exact_pair_query(reason)
        local ok = send("others", "query")
        log_once("query:" .. tostring(reason), "exact-pair query reason=%s", tostring(reason))
        return ok
    end

    function om._exact_pair_on_gameplay_enter()
        om._exact_pair_query("gameplay_enter")
        return om._exact_pair_publish_local("gameplay_enter")
    end

    function om._exact_pair_on_hot_join_sync(recipient)
        return om._exact_pair_publish_local("hot_join_sync", recipient)
    end

    function om._exact_pair_live_evidence()
        local snapshot = {
            tx_reasons = {},
            apply_surfaces = {},
            tx_clear = evidence.tx_clear,
            rx_state = evidence.rx_state,
            rx_cached_absent = evidence.rx_cached_absent,
            rx_clear = evidence.rx_clear,
        }
        for reason in pairs(evidence.tx_reasons) do snapshot.tx_reasons[reason] = true end
        for surface in pairs(evidence.apply_surfaces) do snapshot.apply_surfaces[surface] = true end
        return snapshot
    end

    function om._exact_pair_live_verdict()
        local missing = {}
        for _, reason in ipairs({ "gameplay_enter", "wield", "hot_join_sync" }) do
            if not evidence.tx_reasons[reason] then missing[#missing + 1] = "tx:" .. reason end
        end
        if not evidence.rx_state then missing[#missing + 1] = "rx:state" end
        if not (evidence.apply_surfaces.remote_transition
                or evidence.apply_surfaces.husk_reconstruction) then
            missing[#missing + 1] = "apply:accepted"
        end
        if not evidence.tx_clear then missing[#missing + 1] = "tx:clear" end
        if not evidence.rx_clear then missing[#missing + 1] = "rx:clear" end
        if #missing > 0 then
            return "live exact-pair lifecycle not yet complete: " .. table.concat(missing, ",")
        end
    end
    om._exact_pair_query("install")

    om._exact_pair_channel = CHANNEL
    om._exact_pair_schema = SCHEMA
    om._exact_pair_skin_predicate = is_exact_skin
    om._exact_pair_state_by_peer = by_peer
end

return M
