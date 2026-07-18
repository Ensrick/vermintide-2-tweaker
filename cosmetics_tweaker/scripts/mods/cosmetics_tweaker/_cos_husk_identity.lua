-- _cos_husk_identity.lua -- career-scoped remote appearance identity (#698).
--
-- The Cosmetics peer store is addressed by Steam peer because VMF transports
-- mod state peer-to-peer, but a peer can change career without changing that
-- address and host-owned bots can share it.  This pure policy stamps every
-- appearance record with the human wearer's career and fails closed whenever
-- the active render target cannot prove the same identity.
--
-- Owned by: cosmetics_tweaker.lua. Consumed by: LA store/transport/reconcile.

local M = {}

local function normalize_career(value)
    if type(value) ~= "string" or value == "" then return nil end
    return value
end

function M.new_entry(kind, armoury_key, vanilla_key, hand_field, wearer_career)
    return {
        kind = kind,
        armoury_key = armoury_key,
        vanilla_key = vanilla_key,
        hand_field = hand_field,
        wearer_career = normalize_career(wearer_career),
    }
end

function M.entry_matches_career(entry, active_career)
    if type(entry) ~= "table" then return false, "entry-unavailable" end
    local recorded = normalize_career(entry.wearer_career)
    local active = normalize_career(active_career)
    if not recorded then return false, "career-unproven" end
    if not active then return false, "active-career-unproven" end
    if recorded ~= active then
        return false, "career-mismatch:" .. recorded .. "->" .. active
    end
    return true, "career-match"
end

function M.transport_career_valid(recorded_career, active_career)
    local recorded = normalize_career(recorded_career)
    local active = normalize_career(active_career)
    if not recorded then return false, "career-unproven" end
    if active and active ~= recorded then
        return false, "career-mismatch:" .. recorded .. "->" .. active
    end
    return true, active and "career-match" or "active-career-deferred"
end

-- Only a human render target can invalidate its peer-addressed state. Bots can
-- share their owner's peer id, so their different career is an ownership alias,
-- not evidence that the human changed career (the verified #513 boundary).
function M.invalidate_for_career(store, wearer_peer, active_career, is_player_controlled)
    if is_player_controlled ~= true then return 0, "non-human-owner-alias", {} end
    if not normalize_career(active_career) then
        return 0, "active-career-unproven", {}
    end
    local slots = type(store) == "table" and store[wearer_peer]
    if type(slots) ~= "table" then return 0, "no-store", {} end

    local removed = {}
    for slot_name, entry in pairs(slots) do
        local matches = M.entry_matches_career(entry, active_career)
        if not matches then
            slots[slot_name] = nil
            removed[#removed + 1] = tostring(slot_name)
        end
    end
    table.sort(removed)
    if next(slots) == nil then store[wearer_peer] = nil end
    return #removed, (#removed > 0 and "career-invalidated" or "career-match"), removed
end

-- Runtime adapters keep engine traversal out of the oversized entry module.
-- Globals are passed explicitly so the policy remains loadable under Lua 5.1
-- tests and no boot-time engine object is captured across state transitions.
function M.career_for_unit(unit, script_unit, managers, persistence)
    if not unit then return nil end
    local inv = script_unit and script_unit.has_extension
        and script_unit.has_extension(unit, "inventory_system")
    if inv and normalize_career(inv._career_name) then return inv._career_name end
    local pm = managers and managers.player
    local owner = pm and pm.owner and pm:owner(unit)
    if owner and persistence and persistence._career_name_for_player then
        return normalize_career(persistence._career_name_for_player(owner))
    end
    return nil
end

function M.player_for_unit(player_manager, unit)
    if not (player_manager and unit) then return nil end
    if player_manager.owner then
        local owner = player_manager:owner(unit)
        if owner then return owner end
    end
    for _, player in pairs(player_manager._players or {}) do
        if player.player_unit == unit then return player end
    end
    return nil
end

function M.player_controlled(player)
    if not (player and type(player.is_player_controlled) == "function") then
        return nil
    end
    local ok, controlled = pcall(player.is_player_controlled, player)
    return ok and controlled or nil
end

-- The peer-shared slot: a host owns local_player_id 1 (its human) plus 2..4 for
-- its bots, and every one of those players carries the host's peer_id
-- [src: scripts/managers/player/player_manager.lua:361-372,297-326]. So a peer
-- id alone cannot tell a human from a host bot; local_player_id CAN
-- (RemotePlayer.local_player_id -> self._local_player_id, remote_player.lua:135).
-- Returned as a field or via the method, whichever the player object exposes.
function M.local_player_id(player)
    if type(player) ~= "table" then return nil end
    local fn = player.local_player_id
    if type(fn) == "function" then
        local ok, id = pcall(fn, player)
        if ok and id ~= nil then return id end
    end
    return player._local_player_id
end

-- Positive human-wearer test that does NOT trust the peer id alone. A human is
-- proven by is_player_controlled()==true OR by owning local_player_id 1 at its
-- peer (bots are never local_player_id 1, so this can never mis-accept a bot).
-- The second arm rescues a human whose controlled flag is transiently unproven
-- during the spawn/sync window - the #698 gate skipping a real human because
-- is_player_controlled briefly read nil is exactly the misclassification the
-- peer-only view produced. Returns (is_human, reason).
function M.wearer_is_human(player)
    if M.player_controlled(player) == true then return true, "player-controlled" end
    if M.local_player_id(player) == 1 then return true, "local-player-1" end
    return false, "non-human-owner-alias"
end

function M.validate_live_entry(entry, unit, script_unit, managers, persistence)
    local player = M.player_for_unit(managers and managers.player, unit)
    if M.player_controlled(player) ~= true then
        return false, "non-human-owner-alias", nil, player
    end
    local career = M.career_for_unit(unit, script_unit, managers, persistence)
    local ok, reason = M.entry_matches_career(entry, career)
    return ok, reason, career, player
end

local function resolve_owner_char(unit, player, script_unit, profiles)
    local ext = script_unit and script_unit.has_extension
        and script_unit.has_extension(unit, "attachment_system")
    local slot = ext and ext._attachments and ext._attachments.slots
        and ext._attachments.slots.slot_hat
    local item_unit = slot and slot.item_data and slot.item_data.unit
    if item_unit then
        return string.match(item_unit, "^units/beings/player/([^/]+)/"), "slot_hat"
    end
    local profile_index = player and player.profile_index
    if type(profile_index) == "function" then
        local ok, index = pcall(profile_index, player)
        profile_index = ok and index or nil
    end
    local profile = profile_index and profiles and profiles[profile_index]
    return profile and profile.unit_name, "profile_base"
end

function M.make_spawn_monitor(deps)
    local bot_alias_seen = {}
    return function(unit)
        if not (unit and deps.unit_api.alive(unit))
            or not (deps.bridge and deps.bridge.registered) then return end
        local managers = deps.managers()
        local pm = managers and managers.player
        local owner = pm and pm.owner and pm:owner(unit)
        local wearer_peer = owner and owner.peer_id
        if not wearer_peer then return end
        local controlled = M.player_controlled(owner)
        local career = deps.persistence and deps.persistence._career_name_for_player
            and deps.persistence._career_name_for_player(owner)
        local removed, reason, removed_slots = M.invalidate_for_career(
            deps.store, wearer_peer, career, controlled)
        if removed > 0 then
            deps.print("[cos:698] SPAWN career-change invalidated wearer=%s active=%s slots=%s reason=%s",
                tostring(wearer_peer), tostring(career), table.concat(removed_slots, ","),
                tostring(reason))
        end
        local equips = deps.store[wearer_peer]
        if not equips then
            deps.debug("[la-spawn-monitor] unit=%s wearer=%s career=%s -- no cached LA equips",
                tostring(unit), tostring(wearer_peer), tostring(career))
            return
        end
        local owner_char, source = resolve_owner_char(
            unit, owner, deps.script_unit, deps.profiles())
        local entry_keys = {}
        for key in pairs(equips) do entry_keys[#entry_keys + 1] = key end
        table.sort(entry_keys)
        deps.debug("[la-spawn-monitor] unit=%s wearer=%s career=%s owner_char=%s (via %s) cached_slots={%s}",
            tostring(unit), tostring(wearer_peer), tostring(career), tostring(owner_char),
            tostring(source), table.concat(entry_keys, ","))
        local hat_entry = equips.slot_hat
        if not (hat_entry and hat_entry.armoury_key) then return end
        local variant = deps.resolve_variant(hat_entry.armoury_key)
        local la_unit_path = variant and variant.new_units and variant.new_units[1]
        if not la_unit_path then return end
        local profile_base = source == "profile_base" and owner_char or nil
        local owner_char_path
        if source == "slot_hat" then
            local ext = deps.script_unit.has_extension(unit, "attachment_system")
            local slot = ext and ext._attachments and ext._attachments.slots
                and ext._attachments.slots.slot_hat
            owner_char_path = slot and slot.item_data and slot.item_data.unit
        end
        local compatible, mismatch = deps.chars_compatible(
            owner_char_path, la_unit_path, profile_base)
        if compatible then return end
        deps.warning("[la-spawn-monitor] CROSS-SKELETON MISMATCH wearer=%s career=%s cached_armoury=%s la_path=%s -- %s.",
            tostring(wearer_peer), tostring(career), tostring(hat_entry.armoury_key),
            tostring(la_unit_path), tostring(mismatch))
        if deps.score_identity.should_purge_mismatch(controlled) then
            deps.purge(deps.store, wearer_peer, "slot_hat")
        else
            local token = tostring(wearer_peer) .. "|" .. tostring(career)
            if bot_alias_seen[token] then return end
            bot_alias_seen[token] = true
            deps.print("[la-state] BOT-OWNER-ALIAS retained peer=%s career=%s slot=slot_hat player_controlled=%s",
                tostring(wearer_peer), tostring(career), tostring(controlled))
        end
    end
end

return M
