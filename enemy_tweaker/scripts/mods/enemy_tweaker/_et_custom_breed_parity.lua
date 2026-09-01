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

-- The pre-roster fence is for remote hot joins only. Vanilla creates a peer
-- state machine for the listen server's own peer too, but never adds that peer
-- through the remote-only GameSession.add_peer branch. Holding the local peer
-- here therefore deadlocks WaitingForEnterGame. NetworkServer.my_peer_id is
-- the source-qualified authority; Network.peer_id is only a guarded fallback
-- for the earlier GameNetworkManager seam when its server is unavailable.
local function _current_local_server_peer_id(server)
    local own_peer_id = type(server) == "table"
        and rawget(server, "my_peer_id") or nil
    if type(own_peer_id) == "string" and own_peer_id ~= "" then
        return own_peer_id
    end

    local network = rawget(_G, "Network")
    local peer_id_fn = type(network) == "table"
        and rawget(network, "peer_id") or nil
    if type(peer_id_fn) ~= "function" then return nil end

    local ok, fallback_peer_id = pcall(peer_id_fn)
    if ok and type(fallback_peer_id) == "string" and fallback_peer_id ~= "" then
        return fallback_peer_id
    end
end

local function _is_local_server_peer(peer_id, server)
    if type(peer_id) ~= "string" or peer_id == "" then return false end
    return peer_id == _current_local_server_peer_id(server)
end

-- A peer that was conservatively classified as remote before the server owner
-- id became readable may already exist in BOTH state owners: this module's
-- synchronous fence and the canonical parity instance's pre-roster `_pending`
-- set. Clearing only the fence leaves all_peers_have() false forever because
-- the listen server is intentionally absent from the other-human roster.
-- `forget_peer` is the canonical, idempotent proof retirement operation: it
-- clears pending/acked/roster state and retires exact transport proof without
-- sending or logging. Run it at every local ingress because a delayed response
-- to a pre-cleanup challenge can make the canonical receiver reject and
-- reintroduce `_pending` without recreating this module's fence row. Repeated
-- clean calls do not grow retired history or emit traffic. Keep native admission
-- independent of retirement success so a defensive cleanup error can never
-- recreate the local-host deadlock.

local function _current_parity_instance()
    return type(ET) == "table" and rawget(ET, "CustomBreedParity") or nil
end

local function _retire_local_server_peer(peer_id, server)
    if not _is_local_server_peer(peer_id, server) then return false, false end

    local instance = _current_parity_instance()
    hot_join_peers[peer_id] = nil
    local forget_peer = type(instance) == "table"
        and rawget(instance, "forget_peer") or nil
    if type(forget_peer) ~= "function" then return true, false end
    local ok = pcall(forget_peer, instance, peer_id)
    if not ok then return true, false end
    return true, true
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

-- Runtime evidence is retained from the two callbacks actually handed to VMF,
-- and each observed bit is written only inside that callback's local branch.
-- The #1497 check therefore fails if either hook is disconnected or its bypass
-- is relocated; detached classifier/constant checks are not sufficient proof.
local local_bypass_provenance = {
    set_peer_synchronizing = {
        callback = nil, observed = false, retirement_observed = false,
        last_local_peer_id = nil,
    },
    fully_synced_for_peer = {
        callback = nil, observed = false, retirement_observed = false,
        last_local_peer_id = nil,
    },
}

local function _set_peer_synchronizing_hook(func, self, peer_id)
        if type(peer_id) ~= "string" or peer_id == "" then
            return func(self, peer_id)
        end
        local server = type(self) == "table"
            and rawget(self, "network_server") or nil
        local is_local, retired = _retire_local_server_peer(peer_id, server)
        if is_local then
            local evidence = local_bypass_provenance.set_peer_synchronizing
            evidence.observed = true
            evidence.last_local_peer_id = peer_id
            if retired then
                evidence.retirement_observed = true
            end
            -- Also recovers a stale row after a live dofile or a previously
            -- unreadable owner id, including canonical parity proof state.
            -- Preserve the complete prior VMF hook chain.
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
end
mod:hook("GameNetworkManager", "set_peer_synchronizing",
    _set_peer_synchronizing_hook)
local_bypass_provenance.set_peer_synchronizing.callback =
    _set_peer_synchronizing_hook
mod._et_custom_breed_hot_join_fence = true

local function _fully_synced_for_peer_hook(func, self, peer_id)
        local is_local, retired = _retire_local_server_peer(peer_id, self)
        if is_local then
            local evidence = local_bypass_provenance.fully_synced_for_peer
            evidence.observed = true
            evidence.last_local_peer_id = peer_id
            if retired then
                evidence.retirement_observed = true
            end
            -- Independent recovery is required because a stale pending/kicked
            -- row or canonical pending proof would otherwise keep returning
            -- false without re-entering the GameNetworkManager seam.
            return func(self, peer_id)
        end
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
end
mod:hook("NetworkServer", "is_network_state_fully_synced_for_peer",
    _fully_synced_for_peer_hook)
local_bypass_provenance.fully_synced_for_peer.callback =
    _fully_synced_for_peer_hook
mod._et_custom_breed_local_host_provenance = local_bypass_provenance
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

-- Retained evidence from the two installed callbacks. The check itself is
-- observation-only: it neither invokes a network hook nor mutates peer state.
-- This issue check is intentionally SOLO: with no remote humans,
-- all_peers_have()==true plus peer_has(local)==false independently proves the
-- local id is absent from canonical `_pending` as well as `_acked`.
local function _local_retirement_postcondition(evidence, label)
    local peer_id = type(evidence) == "table"
        and rawget(evidence, "last_local_peer_id") or nil
    if type(peer_id) ~= "string" or peer_id == "" then
        return label .. " local peer evidence missing"
    end
    if hot_join_peers[peer_id] ~= nil then
        return label .. " local fence state retained"
    end
    local instance = _current_parity_instance()
    local peer_has = type(instance) == "table"
        and rawget(instance, "peer_has") or nil
    local all_peers_have = type(instance) == "table"
        and rawget(instance, "all_peers_have") or nil
    if type(peer_has) ~= "function" or type(all_peers_have) ~= "function" then
        return label .. " parity postcondition reader missing"
    end
    local ok_peer, acknowledged = pcall(peer_has, instance, peer_id)
    if not ok_peer or type(acknowledged) ~= "boolean" then
        return label .. " peer acknowledgement unreadable"
    end
    if acknowledged then return label .. " local acknowledgement retained" end
    local ok_all, all_exact = pcall(all_peers_have, instance)
    if not ok_all or type(all_exact) ~= "boolean" then
        return label .. " parity consensus unreadable"
    end
    if all_exact ~= true then
        return label .. " canonical pending state retained or check is not solo"
    end
end

-- The postcondition below is intentionally meaningful only on a stable listen
-- server with no remote human present or still joining. Source ownership:
-- PlayerManager:human_players() returns the live human-player table, while
-- NetworkServer.peer_state_machines includes the local server state machine and
-- any pre-roster remote state machines. Require both independent surfaces so a
-- joining peer cannot be mistaken for solo merely because it is not visible in
-- PlayerManager yet. Any unavailable, throwing, or malformed surface skips the
-- diagnostic rather than turning an uncertain roster into a false PASS/FAIL.
local function _issue1497_stable_solo_precondition()
    local managers = rawget(_G, "Managers")
    local state = type(managers) == "table" and rawget(managers, "state") or nil
    local network_manager = type(state) == "table"
        and rawget(state, "network") or nil
    if type(network_manager) ~= "table"
            or rawget(network_manager, "is_server") ~= true then
        return false, "listen-server network state unavailable"
    end

    local server = rawget(network_manager, "network_server")
    local peer_state_machines = type(server) == "table"
        and rawget(server, "peer_state_machines") or nil
    if type(peer_state_machines) ~= "table" then
        return false, "peer-state-machine roster unavailable"
    end

    local network = rawget(_G, "Network")
    local peer_id_fn = type(network) == "table"
        and rawget(network, "peer_id") or nil
    if type(peer_id_fn) ~= "function" then
        return false, "local peer identity unavailable"
    end
    local id_ok, local_peer_id = pcall(peer_id_fn)
    if not id_ok or type(local_peer_id) ~= "string" or local_peer_id == "" then
        return false, "local peer identity unreadable"
    end
    if rawget(server, "my_peer_id") ~= local_peer_id then
        return false, "listen-server peer identity unstable"
    end

    local player_manager = type(managers) == "table"
        and rawget(managers, "player") or nil
    if type(player_manager) ~= "table" then
        return false, "human-player roster unavailable"
    end
    -- PlayerManager methods live on its class lookup rather than necessarily
    -- as raw instance fields, so guard the source-owned method resolution too.
    local lookup_ok, human_players_fn = pcall(function()
        return player_manager.human_players
    end)
    if not lookup_ok or type(human_players_fn) ~= "function" then
        return false, "human-player roster unavailable"
    end
    local players_ok, human_players = pcall(human_players_fn, player_manager)
    if not players_ok or type(human_players) ~= "table" then
        return false, "human-player roster unreadable"
    end

    local inspect_ok, present, reason = pcall(function()
        local human_count = 0
        for _, player in pairs(human_players) do
            if type(player) ~= "table" then
                return false, "human-player roster malformed"
            end
            local player_peer_id = rawget(player, "peer_id")
            if type(player_peer_id) ~= "string" or player_peer_id == "" then
                return false, "human-player identity malformed"
            end
            human_count = human_count + 1
            if player_peer_id ~= local_peer_id then
                return false, "remote human player visible"
            end
        end
        if human_count ~= 1 then
            return false, "stable solo human roster not established"
        end

        for peer_id, machine in pairs(peer_state_machines) do
            if type(peer_id) ~= "string" or peer_id == ""
                    or type(machine) ~= "table" then
                return false, "peer-state-machine roster malformed"
            end
            if peer_id ~= local_peer_id then
                return false, "remote peer still joining"
            end
        end
        if type(rawget(peer_state_machines, local_peer_id)) ~= "table" then
            return false, "local peer state machine not established"
        end
        return true
    end)
    if not inspect_ok then return false, "solo roster traversal failed" end
    return present, reason
end

ET.rt_register("issue1497_local_host_hot_join_bypass", function()
    local evidence = rawget(mod, "_et_custom_breed_local_host_provenance")
    if evidence ~= local_bypass_provenance then
        return "local-host bypass provenance missing"
    end
    local set_evidence = rawget(evidence, "set_peer_synchronizing")
    if type(set_evidence) ~= "table"
            or rawget(set_evidence, "callback") ~= _set_peer_synchronizing_hook then
        return "set_peer_synchronizing bypass hook disconnected"
    end
    local synced_evidence = rawget(evidence, "fully_synced_for_peer")
    if type(synced_evidence) ~= "table"
            or rawget(synced_evidence, "callback") ~= _fully_synced_for_peer_hook then
        return "fully-synced bypass hook disconnected"
    end
    if rawget(set_evidence, "observed") ~= true then
        return "set_peer_synchronizing local bypass not observed"
    end
    if rawget(synced_evidence, "observed") ~= true then
        return "fully-synced local bypass not observed"
    end
    if rawget(set_evidence, "last_local_peer_id") ~=
            rawget(synced_evidence, "last_local_peer_id") then
        return "local peer evidence disagrees across bypass hooks"
    end
    local managers = rawget(_G, "Managers")
    local state = type(managers) == "table" and rawget(managers, "state") or nil
    local network_manager = type(state) == "table"
        and rawget(state, "network") or nil
    local server = type(network_manager) == "table"
        and rawget(network_manager, "network_server") or nil
    local current_peer_id = _current_local_server_peer_id(server)
    if type(current_peer_id) ~= "string" or current_peer_id == "" then
        return "current local peer identity unavailable"
    end
    if rawget(set_evidence, "last_local_peer_id") ~= current_peer_id
            or rawget(synced_evidence, "last_local_peer_id") ~= current_peer_id then
        return "local peer evidence stale for current listen server"
    end
    if rawget(set_evidence, "retirement_observed") ~= true
            and rawget(synced_evidence, "retirement_observed") ~= true then
        return "canonical parity retirement not observed"
    end
    return _local_retirement_postcondition(set_evidence, "local-host")
end, { precondition = _issue1497_stable_solo_precondition })
