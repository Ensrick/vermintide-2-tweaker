-- _gut_default_reset_refresh.lua -- issue #1033 presentation half (engine owner).
--
-- After a DEFAULT/reset persistence transaction (reset_modded_loadouts in
-- _gut_native_loadouts.lua) the saved rows are correct but the LIVE character
-- keeps rendering the pre-reset equipment: the reset ends at _dirtify(), which
-- rebuilds backend interfaces only. Vanilla republishes live equipment ONLY on
-- equip events -- HeroViewStateOverview queues an equip request that drains into
-- SimpleInventoryExtension.create_equipment_in_slot (hero_view_state_overview.lua
-- :697-716 / :1108-1123; the peer publish is send_rpc_clients("rpc_add_equipment"),
-- simple_inventory_extension.lua:1372/:1455) -- and refreshes SKIN changes with one
-- profile respawn (update_skin_sync, hero_view_state_overview.lua:1158-1162 ->
-- IngameUI.respawn, ingame_ui.lua:1290-1303). A DEFAULT reset can change every
-- slot including slot_skin, so this owner mirrors the respawn path: ONE bounded
-- re-request of the CURRENT profile+career with force_respawn = true, exactly what
-- IngameUI.respawn does (profile_name = profile.display_name, career_name =
-- career.name per hero_and_career_name_from_index, sp_profiles.lua:482-489;
-- ProfileRequester.request_profile is host-mediated, profile_requester.lua:46-58).
-- The respawned unit re-reads the reset rows, and because the request is networked
-- every peer's husk refreshes too -- the lobby-visible half of #1033.
--
-- KEEP ONLY: GameModeAdventure.force_respawn teleports to the level start with
-- fresh health/ammo (see _gut_career_swap.lua's caveat), so outside the keep the
-- reset DEFERS -- the durable rows stand and the next spawn boundary consumes them.
-- Classification lives in the pure _gut_default_refresh_core.lua (offline-locked).
--
-- Receipt: one [gut:1033] line before the request (desired vs live slot keys) and
-- one when the respawned unit is observed (bounded watch, 15 s), so a stale render
-- AFTER a confirmed respawn is distinguishable from a refused/failed request
-- (issue #1033 Fallback 1's falsifier).
--
-- HOOK PRE-FLIGHT: this module registers NO mod:hook/mod:hook_safe (nothing to
-- collide with; grep confirms). Its only per-frame work rides the standard
-- capture-prev mod.update chain, active solely while a watch is armed.
--
-- Owned by: _gut_native_loadouts.lua. Consumed via: mod:dofile (single call).

local mod = get_mod("gut_dev")
local Core = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_default_refresh_core")

local M = { MARKER = "default_reset_refresh_v1", core = Core }

local RECEIPT_SLOTS = Core.RECEIPT_SLOTS

-- Card-cited evidence lines (engine printf; user runs with mod-logging OFF).
local function _pf(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    pcall(printf, "[gut:1033] " .. (ok and s or tostring(fmt)))
end

local function _local_player()
    local ok, player = pcall(function()
        return Managers.player and Managers.player:local_player()
    end)
    return ok and player or nil
end

-- profile.display_name + career.name -- the exact pair FindProfileIndex /
-- career_index_from_name match on (sp_profiles.lua:470-489).
local function _player_identity(player)
    local ok, profile_name, career_name = pcall(function()
        local pi = player:profile_index()
        local ci = player:career_index()
        local profiles = rawget(_G, "SPProfiles")
        local profile = pi and profiles and profiles[pi]
        local career = profile and profile.careers and profile.careers[ci]
        return profile and profile.display_name, career and career.name
    end)
    if not ok then return nil, nil end
    return profile_name, career_name
end

local function _unit_alive(unit)
    if unit == nil then return false end
    local ok, alive = pcall(Unit.alive, unit)
    return ok and alive == true
end

local function _game_mode_key()
    local ok, key = pcall(function()
        local gm = Managers.state and Managers.state.game_mode
        return gm and gm:game_mode_key()
    end)
    return ok and key or nil
end

-- Mid-mission-and-keep-safe ProfileRequester accessor -- the exact path vanilla's
-- ImguiCareerDebug uses (imgui_career_debug.lua:28-42; NetworkServer/NetworkClient
-- .profile_requester return self._profile_requester). Same accessor
-- _gut_career_swap.lua already field-verified.
local function _profile_requester()
    local ok, requester = pcall(function()
        local nm = Managers.state and Managers.state.network
        local network = nm and (nm.network_server or nm.network_client)
        return network and network:profile_requester()
    end)
    return ok and requester or nil
end

-- Live rendered identities: melee/ranged from SimpleInventoryExtension.equipment()
-- .slots[slot].item_data (simple_inventory_extension.lua:504, the same slot_data
-- create_equipment_in_slot compares at :1381-1391); hat from
-- PlayerUnitAttachmentExtension.get_slot_data (player_unit_attachment_extension.lua
-- :186-192). Read-only; never mutates either extension.
local function _live_keys(unit)
    local out = {}
    pcall(function()
        local inv = ScriptUnit.has_extension(unit, "inventory_system")
        local equipment = inv and inv.equipment and inv:equipment()
        local slots = equipment and equipment.slots
        if slots then
            for i = 1, #RECEIPT_SLOTS do
                local slot = RECEIPT_SLOTS[i]
                if slot ~= "slot_hat" then
                    local sd = slots[slot]
                    out[slot] = sd and sd.item_data and sd.item_data.key
                end
            end
        end
    end)
    pcall(function()
        local att = ScriptUnit.has_extension(unit, "attachment_system")
        local sd = att and att.get_slot_data and att:get_slot_data("slot_hat")
        out.slot_hat = sd and sd.item_data and sd.item_data.key
    end)
    return out
end

-- Desired identities: the just-reset SELECTED row, read through the per-slot
-- LA-aware reader (BackendUtils.get_loadout_item) -- the same reader the exit
-- snapshot uses; NOT a mirror-read context, so no get_item_from_id recursion risk.
local function _desired_keys(career_name)
    local out = {}
    local BU = rawget(_G, "BackendUtils")
    if not (career_name and BU and BU.get_loadout_item) then return out end
    for i = 1, #RECEIPT_SLOTS do
        local slot = RECEIPT_SLOTS[i]
        local ok, item = pcall(BU.get_loadout_item, career_name, slot)
        if ok and item then
            out[slot] = (item.data and item.data.key) or item.key
        end
    end
    return out
end

local function _k(t, slot) return tostring(t and t[slot] or "-") end

-- One armed watch at a time; re-arming replaces (a second DEFAULT supersedes).
local _watch = nil

-- request(source, mirror_live, career_arg) -> requested (bool), action, reason
-- Called by reset_modded_loadouts after its bounded persistence transaction.
-- career_arg mirrors the reset scope: nil/"" = all careers; a named career only
-- refreshes when it IS the active one (refresh only the active career, #1033).
function M.request(source, mirror_live, career_arg)
    local player = _local_player()
    local unit = player and player.player_unit
    local alive = _unit_alive(unit)
    local profile_name, career_name
    if player then profile_name, career_name = _player_identity(player) end
    local mode_key = _game_mode_key()
    local requester = _profile_requester()
    local scope_active = career_arg == nil or career_arg == ""
        or (career_name ~= nil and career_arg == career_name)

    local action, reason = Core.classify({
        mirror_live = mirror_live and true or false,
        reset_scope_active = scope_active,
        has_player = profile_name ~= nil and career_name ~= nil,
        unit_alive = alive,
        game_mode_key = mode_key,
        requester_available = requester ~= nil,
    })

    local desired = _desired_keys(career_name)
    local live = alive and _live_keys(unit) or {}
    _pf("refresh=%s source=%s reason=%s mode=%s career=%s desired m/r/h=%s/%s/%s live m/r/h=%s/%s/%s",
        tostring(action), tostring(source or "?"), tostring(reason), tostring(mode_key),
        tostring(career_name),
        _k(desired, "slot_melee"), _k(desired, "slot_ranged"), _k(desired, "slot_hat"),
        _k(live, "slot_melee"), _k(live, "slot_ranged"), _k(live, "slot_hat"))

    if action ~= "respawn" then
        return false, action, reason
    end

    local peer_id
    local ok_peer, pid = pcall(function() return player:network_id() end)
    peer_id = ok_peer and pid or nil
    if not peer_id then
        local ok_np, np = pcall(function() return Network.peer_id() end)
        peer_id = ok_np and np or nil
    end
    local local_player_id = 1
    local ok_lpid, lpid = pcall(function() return player:local_player_id() end)
    if ok_lpid and lpid then local_player_id = lpid end
    if not peer_id then
        _pf("refresh=request_failed career=%s error=no-peer-id", tostring(career_name))
        return false, "defer", "no-peer-id"
    end

    -- The exact IngameUI.respawn call shape (ingame_ui.lua:1302): current profile,
    -- current career, force_respawn = true. Host-mediated; a refusal is a no-op.
    local ok_req, req_err = pcall(function()
        requester:request_profile(peer_id, local_player_id, profile_name, career_name, true)
    end)
    if not ok_req then
        _pf("refresh=request_failed career=%s error=%s", tostring(career_name), tostring(req_err))
        return false, "defer", "request-threw"
    end

    _watch = {
        t = 0,
        career_name = career_name,
        desired = desired,
        prev_unit = unit,
    }
    _pf("refresh=requested career=%s force_respawn=true watch=%ds",
        tostring(career_name), Core.WATCH_BUDGET_SECONDS)
    return true, action, reason
end

-- Bounded after-receipt watch. Rides the standard capture-prev mod.update chain;
-- does nothing while unarmed, self-disarms on completion, timeout, or error. Reads
-- only Managers.player + the new unit's extensions (no world lookups; dead-world
-- safe per section 32 discipline).
local _gut1033_prev_update = mod.update
mod.update = function(dt)
    if _gut1033_prev_update then _gut1033_prev_update(dt) end
    local w = _watch
    if not w then return end
    w.t = w.t + (tonumber(dt) or 0)
    local ok = pcall(function()
        local player = _local_player()
        local unit = player and player.player_unit
        if unit and unit ~= w.prev_unit and _unit_alive(unit) then
            local live = _live_keys(unit)
            local matched, mismatched = Core.match(w.desired, live, RECEIPT_SLOTS)
            _pf("refresh=complete career=%s after=%.1fs live m/r/h=%s/%s/%s match=%s%s",
                tostring(w.career_name), w.t,
                _k(live, "slot_melee"), _k(live, "slot_ranged"), _k(live, "slot_hat"),
                tostring(matched),
                matched and "" or (" mismatched=" .. table.concat(mismatched, ",")))
            _watch = nil
        end
    end)
    if not ok then
        _pf("refresh=watch_error career=%s (watch disarmed)", tostring(w.career_name))
        _watch = nil
        return
    end
    if _watch and Core.expired(w.t, Core.WATCH_BUDGET_SECONDS) then
        _pf("refresh=timeout career=%s after=%.1fs (no respawned unit observed; rows stand, next spawn boundary reconciles)",
            tostring(w.career_name), w.t)
        _watch = nil
    end
end

return M
