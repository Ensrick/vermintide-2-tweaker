-- Issue #309: bounded host-side disconnect lifecycle diagnostic.
--
-- Vanilla synchronously tears down a disconnected peer from
-- PeerStates.Disconnecting.on_enter. Delaying that method would also defer
-- GameSession, EAC, game-object, player, party, profile and mechanism cleanup.
-- This module therefore observes one explicitly armed disconnect without
-- mutating the lifecycle. The trace establishes whether any damageable unit
-- actually survives detection and when the ordinary replacement bot appears.
-- luacheck: globals PeerStates Managers Unit printf

local mod = get_mod("gt_dev")
local core = mod:dofile("scripts/mods/general_tweaker_dev/_gt_disconnect_grace_core")
local trace_state = core.new()
local clock = 0

mod._gt_disconnect_grace_trace_state = trace_state

local function _safe_call(fn)
    local ok, value = pcall(fn)
    return ok and value or nil
end

local function _alive(unit)
    if not unit or not Unit or not Unit.alive then
        return false
    end

    return _safe_call(function() return Unit.alive(unit) end) and true or false
end

local function _snapshot(peer_id, local_player_id, slot_hint, observed_unit)
    local snapshot = {
        peer = tostring(peer_id),
        player = false,
        unit_alive = false,
        party = "nil",
        slot = tostring(slot_hint or "nil"),
        slot_kind = "unknown",
        observed_unit_alive = observed_unit and _alive(observed_unit) or nil,
        observed_unit_owned = nil,
    }
    local player_manager = Managers and Managers.player
    local party_manager = Managers and Managers.party
    local player = player_manager and _safe_call(function()
        return player_manager:player_from_peer_id(peer_id, local_player_id)
    end)

    if player then
        snapshot.player = true
        snapshot.player_controlled = _safe_call(function() return player:is_player_controlled() end) and true or false
        snapshot.unit_alive = _alive(player.player_unit)
    end

    if observed_unit and player_manager then
        snapshot.observed_unit_owned = _safe_call(function()
            return player_manager:unit_owner(observed_unit) ~= nil
        end) and true or false
    end

    local status = party_manager and _safe_call(function()
        return party_manager:get_player_status(peer_id, local_player_id)
    end)
    if status then
        snapshot.party = tostring(status.party_id or "nil")
        snapshot.slot = tostring(status.slot_id or slot_hint or "nil")
        slot_hint = status.slot_id or slot_hint
    end

    local party = party_manager and _safe_call(function() return party_manager:get_party(1) end)
    local slot = party and slot_hint and party.slots and party.slots[slot_hint]
    if not slot or not slot.peer_id then
        snapshot.slot_kind = "empty"
    elseif slot.peer_id == peer_id then
        snapshot.slot_kind = slot.is_bot and "same-peer-bot" or "same-peer-human"
    else
        snapshot.slot_kind = slot.is_bot and "replacement-bot" or "other-human"
    end

    return snapshot, player and player.player_unit or nil, slot_hint
end

local function _emit(phase, elapsed, snapshot)
    pcall(printf,
        "[gt:309] phase=%s t=%.2f peer=%s player=%s controlled=%s unit_alive=%s party=%s slot=%s slot_kind=%s observed_alive=%s observed_owned=%s",
        tostring(phase), elapsed or 0, tostring(snapshot.peer), tostring(snapshot.player),
        tostring(snapshot.player_controlled), tostring(snapshot.unit_alive), tostring(snapshot.party),
        tostring(snapshot.slot), tostring(snapshot.slot_kind), tostring(snapshot.observed_unit_alive),
        tostring(snapshot.observed_unit_owned))
end

local function _record(trace, phase, snapshot)
    if core.record(trace, phase, clock, snapshot) then
        _emit(phase, math.max(0, clock - trace.started_at), snapshot)
    end
end

-- Duplicate-hook preflight: repository grep found no existing hook on
-- PeerStates.Disconnecting.on_enter. This wrapper is observation-only and calls
-- vanilla exactly once before taking the post snapshot.
local disconnecting = PeerStates and PeerStates.Disconnecting
if disconnecting and type(disconnecting.on_enter) == "function" then
    mod:hook(disconnecting, "on_enter", function(func, self, previous_state)
        if not trace_state.armed then
            return func(self, previous_state)
        end

        local peer_id = self and self.peer_id
        local pre, observed_unit, slot_id = _snapshot(peer_id, 1)
        local trace = core.begin(trace_state, peer_id, slot_id, clock)
        _record(trace, "pre_on_enter", pre)

        func(self, previous_state)

        local post = _snapshot(peer_id, 1, slot_id, observed_unit)
        _record(trace, "post_on_enter", post)
    end)
    mod._gt_disconnect_grace_hook_installed = true
    pcall(printf, "[gt:309] disconnect lifecycle probe installed (inert until /gt_disconnect_grace_probe)")
else
    pcall(printf, "[gt:309] PeerStates.Disconnecting.on_enter unavailable; probe NOT installed")
end

mod._gt_disconnect_grace_on_remote_join = function(peer_id)
    local snapshot = _snapshot(peer_id, 1, trace_state.active and trace_state.active.slot_id)
    if core.note_rejoin(trace_state, peer_id, clock, snapshot) then
        _emit("rejoin", math.max(0, clock - trace_state.active.started_at), snapshot)
    end
end

local function _update(dt)
    clock = clock + (tonumber(dt) or 0)
    local trace, offset = core.take_due(trace_state, clock)
    if not trace then
        return
    end

    local snapshot = _snapshot(trace.peer_id, 1, trace.slot_id)
    _record(trace, string.format("sample_%.2f", offset), snapshot)

    local finished = core.finish_if_complete(trace_state)
    if finished then
        pcall(printf, "[gt:309] trace complete peer=%s records=%d window=30.00",
            tostring(finished.peer_id), #finished.records)
    end
end

if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt309_disconnect_grace_probe", _update)
    mod._gt_disconnect_grace_update_registered = true
end

mod:command("gt_disconnect_grace_probe", "Arm one bounded host-side peer-disconnect lifecycle trace", function()
    local player_manager = Managers and Managers.player
    if not (player_manager and player_manager.is_server) then
        mod:echo("[gt] Disconnect grace probe must be armed by the host.")
        return
    end

    core.arm(trace_state)
    mod:echo("[gt] Armed one disconnect lifecycle trace. Ask one client to disconnect, then reconnect within 30 seconds.")
    pcall(printf, "[gt:309] ARMED next remote disconnect; sample window=30.00s max_records=%d", core.MAX_RECORDS)
end)

if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("issue309_disconnect_grace_diagnostics_armed", function()
        -- Runner contract: nil == PASS, a reason string == FAIL. Returning the
        -- boolean `ok` scored a healthy probe as "FAIL -- true" (issue #1153).
        local ok = mod._gt_disconnect_grace_hook_installed == true
            and mod._gt_disconnect_grace_update_registered == true
            and type(mod._gt_disconnect_grace_on_remote_join) == "function"
            and core.MAX_RECORDS == 10
        if not ok then
            return "disconnect trace wiring incomplete"
        end
    end)
end

return core
