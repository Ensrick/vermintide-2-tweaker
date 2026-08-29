-- Exact peer/catalog floor for Enemy Tweaker custom breeds (#451B).
-- Loaded after both registrar transactions and before every hot-join or spawn
-- hook. The canonical copied parity library owns transport/replay semantics;
-- this file owns only Enemy's identity, engine seams, and vanilla-donor floor.

local mod = get_mod("enemy_tweaker")
local ET = mod._et
local Identity = ET.CustomBreedIdentity
local Registrar = ET.CustomBreedRegistrar

local snapshot, snapshot_reason = Identity.capture({
    breeds = rawget(_G, "Breeds"),
    network_lookup = rawget(_G, "NetworkLookup"),
    marker_key = Registrar.marker_key,
    registrar_schema = Registrar.schema,
})
ET.CustomBreedIdentitySnapshot = snapshot

local parity
if snapshot then
    local load_ok, factory = pcall(function()
        return mod:dofile("scripts/mods/enemy_tweaker/_lib_peer_parity")
    end)
    if load_ok and type(factory) == "function" then
        local create_ok, instance = pcall(factory, mod, {
            channel = "et_custom_breeds_exact_v1",
            schema = ET.rpc_schema,
            mod_id = "enemy_tweaker",
            mod_label = "Enemy Tweaker",
            echo_prefix = "[et]",
            wire_identity = snapshot.identity,
        })
        if create_ok and type(instance) == "table" then
            local install_ok, committed = pcall(instance.install, instance)
            local status_ok, installed = false, false
            if install_ok and committed == true
                    and type(instance.is_installed) == "function" then
                status_ok, installed = pcall(instance.is_installed, instance)
            end
            if status_ok and installed == true then parity = instance end
        end
    end
end

ET.CustomBreedParity = parity
mod._et_custom_breed_peer_parity = parity

if parity then
    pcall(printf, "[et:451] exact custom-breed parity installed identity=%s",
        snapshot.identity)
else
    pcall(printf, "[et:451] WARN exact custom-breed parity unavailable (%s); custom spawns use vanilla donors",
        tostring(snapshot_reason or "install-failed"))
end

local function _exact_safe()
    if type(parity) ~= "table" then return false, "parity-unavailable" end
    if type(parity.is_installed) ~= "function"
            or type(parity.applied_state) ~= "function"
            or type(parity.all_peers_have) ~= "function" then
        return false, "parity-api-invalid"
    end
    local ok_installed, installed = pcall(parity.is_installed, parity)
    if not ok_installed or installed ~= true then return false, "parity-uninstalled" end
    local ok_state, state = pcall(parity.applied_state, parity)
    if not ok_state or state ~= "enabled" then return false, "parity-unconfirmed" end
    local ok_live, all_exact = pcall(parity.all_peers_have, parity)
    if not ok_live or all_exact ~= true then return false, "parity-live-mismatch" end
    local ok_identity, intact, identity_reason = pcall(Identity.intact, snapshot, {
        breeds = rawget(_G, "Breeds"),
        network_lookup = rawget(_G, "NetworkLookup"),
    })
    if not ok_identity or intact ~= true then
        return false, identity_reason or "identity-check-threw"
    end
    local ok_registrar, registered, registrar_reason = pcall(
        Registrar.validate_all_registered)
    if not ok_registrar or registered ~= true then
        return false, registrar_reason or "registrar-check-threw"
    end
    return true
end

ET.custom_breeds_exact_safe = _exact_safe

-- Bounded sender-floor diagnostics. The floor itself remains active after the
-- cap; only repetitive rows stop. This is intentionally global across both
-- surfaces and breeds so hostile callers cannot produce an unbounded log.
local FALLBACK_LOG_CAP = 8
local fallback_logs = 0
ET.custom_breed_spawn_floor = function(requested, surface)
    local name = type(requested) == "table" and rawget(requested, "name")
    if not Identity.spec_for(name) then return requested, "vanilla" end
    local safe, safe_reason = _exact_safe()
    local resolved, decision = Identity.resolve_spawn_breed(requested, safe,
        rawget(_G, "Breeds"), rawget(_G, "NetworkLookup"))
    if not resolved then
        if fallback_logs < FALLBACK_LOG_CAP then
            fallback_logs = fallback_logs + 1
            pcall(printf, "[et:451] custom spawn REJECTED surface=%s wanted=%s reason=%s row=%d/%d",
                tostring(surface), tostring(name), tostring(decision),
                fallback_logs, FALLBACK_LOG_CAP)
        end
        return nil, decision
    end
    if decision == "vanilla-donor" and fallback_logs < FALLBACK_LOG_CAP then
        fallback_logs = fallback_logs + 1
        pcall(printf, "[et:451] custom spawn substituted surface=%s wanted=%s donor=%s reason=%s row=%d/%d",
            tostring(surface), tostring(requested and requested.name),
            tostring(resolved.name), tostring(safe_reason), fallback_logs,
            FALLBACK_LOG_CAP)
    end
    return resolved, decision
end
ET.CUSTOM_BREED_FALLBACK_LOG_CAP = FALLBACK_LOG_CAP

-- Pre-roster hot-join fence. set_peer_synchronizing is earlier than
-- GameNetworkManager.hot_join_sync. Canonical require_peer(false) means only
-- "challenge pending" -- it is not proof of a mismatch and must never start an
-- irreversible vanilla kick by itself. With no live or queued custom unit,
-- native sync is safe immediately because the non-exact parity state keeps
-- every later custom emission on its validated donor. With custom state already
-- live or committed to the queue, keep the peer outside GameSession until exact
-- proof arrives or the bounded deadline expires. A real disconnect clears this
-- record and retires canonical proof.
local HOT_JOIN_LOG_CAP = 8
local HOT_JOIN_TIMEOUT = 10
local hot_join_logs = 0
local hot_join_clock = 0
local hot_join_peers = {}

local previous_update = mod.update
mod.update = function(dt)
    if type(dt) == "number" and dt == dt and dt > 0 and dt < math.huge then
        hot_join_clock = hot_join_clock + dt
    end
    if previous_update then previous_update(dt) end
end

local function _hot_join_log(format, ...)
    if hot_join_logs >= HOT_JOIN_LOG_CAP then return end
    hot_join_logs = hot_join_logs + 1
    local ok, message = pcall(string.format, format, ...)
    if ok then
        pcall(printf, "%s row=%d/%d", message, hot_join_logs,
            HOT_JOIN_LOG_CAP)
    end
end

-- The engine census is the authority for whether a live OR already-queued
-- custom game object could enter after hot-join. spawn_queued_unit stores its
-- breed in ConflictDirector.spawn_queue, and the drain consumes that stored
-- row without re-entering our sender hook, so a positive queued counter is as
-- unsafe as a live unit. No ConflictDirector means there is no active mission
-- state. Once a director exists, every count must be a readable non-negative
-- integer; missing or malformed state is conservatively treated as occupied.
local function _custom_state_live()
    local managers = rawget(_G, "Managers")
    local state = type(managers) == "table" and rawget(managers, "state")
    local conflict = type(state) == "table" and rawget(state, "conflict")
    if type(conflict) ~= "table" then return false, "conflict-absent" end
    if type(conflict.count_units_by_breed) ~= "function" then
        return true, "census-unavailable"
    end
    local queued_by_breed = rawget(conflict, "num_queued_spawn_by_breed")
    if type(queued_by_breed) ~= "table" then
        return true, "queued-census-unavailable"
    end
    for i = 1, #Identity.SPECS do
        local name = Identity.SPECS[i].name
        local ok, live_count = pcall(
            conflict.count_units_by_breed, conflict, name)
        if not ok or type(live_count) ~= "number"
                or live_count ~= live_count or live_count < 0
                or live_count == math.huge
                or live_count ~= math.floor(live_count) then
            return true, "live-census-invalid:" .. tostring(name)
        end
        local queued_count = rawget(queued_by_breed, name)
        if type(queued_count) ~= "number"
                or queued_count ~= queued_count or queued_count < 0
                or queued_count == math.huge
                or queued_count ~= math.floor(queued_count) then
            return true, "queued-census-invalid:" .. tostring(name)
        end
        if live_count > 0 then
            return true, "live:" .. name
        end
        if queued_count > 0 then return true, "queued:" .. name end
    end
    return false, "no-live-or-queued-custom"
end

local function _peer_exact(peer_id)
    local instance = ET.CustomBreedParity
    if type(instance) ~= "table" or type(instance.peer_has) ~= "function" then
        return false
    end
    local ok, exact = pcall(instance.peer_has, instance, peer_id)
    return ok and exact == true
end

local function _call_native_once(record, admission)
    if record.phase == "kicked" or record.native_called then return end
    record.native_called = true
    record.phase = "admitted"
    record.admission = admission
    record.had_exact = admission == "exact"
    return record.native_func(record.manager, record.peer_id)
end

local function _kick_once(record, reason)
    if record.phase == "kicked" or record.kick_called then return end
    record.kick_called = true
    record.phase = "kicked"
    record.kick_reason = reason
    _hot_join_log(
        "[et:451] hot-join sync KICKED peer=%s reason=%s",
        tostring(record.peer_id), tostring(reason))
    local server = record.manager and record.manager.network_server
    if server and type(server.kick_peer) == "function" then
        pcall(server.kick_peer, server, record.peer_id)
    end
end

local function _advance_pending(record)
    if record.phase ~= "pending" then return end
    local live = _custom_state_live()
    if not live then
        return _call_native_once(record, "donor-safe")
    end
    if _peer_exact(record.peer_id) then
        return _call_native_once(record, "exact")
    end
    if hot_join_clock - record.started_at >= HOT_JOIN_TIMEOUT then
        _kick_once(record, "exact-proof-timeout")
    end
end

mod:hook("GameNetworkManager", "set_peer_synchronizing",
    function(func, self, peer_id)
        if type(peer_id) ~= "string" or peer_id == "" then
            return func(self, peer_id)
        end
        local record = hot_join_peers[peer_id]
        if record then
            if record.phase == "pending" then _advance_pending(record) end
            return
        end

        local instance = ET.CustomBreedParity
        local confirmed = false
        local reason = "parity-unavailable"
        if type(instance) == "table"
                and type(instance.require_peer) == "function" then
            local ok, result = pcall(instance.require_peer, instance, peer_id)
            confirmed = ok and result == true
            reason = ok and "exact-preack-missing" or "require-peer-threw"
        end
        record = {
            phase = "pending",
            peer_id = peer_id,
            manager = self,
            native_func = func,
            started_at = hot_join_clock,
            native_called = false,
            kick_called = false,
        }
        hot_join_peers[peer_id] = record
        if confirmed then return _call_native_once(record, "exact") end

        local live, live_reason = _custom_state_live()
        if not live then return _call_native_once(record, "donor-safe") end
        _hot_join_log(
            "[et:451] hot-join sync HELD peer=%s reason=%s/%s",
            tostring(peer_id), tostring(reason), tostring(live_reason))
        -- First false is pending. Hold only; never kick here.
    end)
mod._et_custom_breed_hot_join_fence = true
mod:hook("NetworkServer", "is_network_state_fully_synced_for_peer",
    function(func, self, peer_id)
        local record = type(peer_id) == "string" and hot_join_peers[peer_id]
        if record then
            if record.phase == "pending" then _advance_pending(record) end
            if record.phase == "pending" then return false end
            if record.phase == "kicked" then return false end
            -- A peer that was exact and then sent a definitive bad proof loses
            -- canonical acknowledgement. If custom state is still live, this
            -- is the one non-timeout transition allowed to start a kick.
            if record.phase == "admitted" then
                local exact_now = _peer_exact(peer_id)
                if exact_now then
                    record.had_exact = true
                elseif record.had_exact then
                    local live = _custom_state_live()
                    if live then
                        _kick_once(record, "exact-proof-revoked")
                        return false
                    end
                end
            end
        end
        return func(self, peer_id)
    end)
mod._et_custom_breed_rejected_peer_hold = true
ET.CUSTOM_BREED_HOT_JOIN_LOG_CAP = HOT_JOIN_LOG_CAP
ET.CUSTOM_BREED_HOT_JOIN_TIMEOUT = HOT_JOIN_TIMEOUT
ET.custom_breed_state_live = _custom_state_live
ET.custom_breed_hot_join_phase = function(peer_id)
    local record = hot_join_peers[peer_id]
    return record and record.phase or nil
end

-- Real disconnect boundary: retire the peer epoch immediately so a rapid
-- same-id rejoin cannot reuse a delayed exact acknowledgement.
mod:hook_safe("GameNetworkManager", "remove_peer", function(_, peer_id)
    if type(peer_id) == "string" then
        hot_join_peers[peer_id] = nil
    end
    local instance = ET.CustomBreedParity
    if type(instance) == "table" and type(instance.forget_peer) == "function" then
        pcall(instance.forget_peer, instance, peer_id)
    end
end)
mod._et_custom_breed_disconnect_forget = true

ET.rt_register("issue451_exact_custom_breed_parity", function()
    if type(ET.CustomBreedIdentitySnapshot) ~= "table" then
        return "custom breed identity unavailable: " .. tostring(snapshot_reason)
    end
    local intact, reason = Identity.intact(ET.CustomBreedIdentitySnapshot, {
        breeds = rawget(_G, "Breeds"),
        network_lookup = rawget(_G, "NetworkLookup"),
    })
    if not intact then return tostring(reason) end
    if type(ET.custom_breed_spawn_floor) ~= "function" then
        return "custom breed sender floor missing"
    end
    if not mod._et_custom_breed_hot_join_fence then
        return "pre-roster hot-join fence missing"
    end
    if not mod._et_custom_breed_rejected_peer_hold then
        return "hot-join GameSession state machine missing"
    end
    if not mod._et_custom_breed_disconnect_forget then
        return "disconnect epoch retirement missing"
    end
end)
