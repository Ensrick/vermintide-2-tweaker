local mod = get_mod("event_tweaker")

-- _evt_guard430_curse_parity.lua — issue 430: Cursed Adventure curse wire safety
--
-- THE CRASH (wire path). The package-bearing Cursed Adventure curses
-- (Curses.MANAGED_CURSES) ride the SAME live-event injection as every other
-- mutator: selected_curse_mutators() -> gather_mutators()/add() (_evt_selection)
-- -> the injected special_event's `mutators` list -> GameModeBase.
-- append_live_event_mutators (game_mode_base.lua:264) -> MutatorHandler
-- activates each one and broadcasts it to every peer via
-- rpc_activate_mutator_client. The mutator NAME itself resolves on a vanilla
-- client (NetworkLookup.mutator_templates is built from the full template table
-- at boot, network_lookup.lua:266), so the RPC does not crash. The RESOURCE
-- PACKAGE is what crashes: the curse spawns a network-replicated husk
-- (spawn_network_unit) whose unit lives in resource_packages/mutators/<name>,
-- and that package is loaded ONLY by _evt_cursed_adventure.lua's
-- MutatorHandler._activate_mutator / init hooks — which exist only on a peer
-- running event_tweaker. A non-ET peer activates the curse, the husk spawns
-- from the unloaded package, and the engine hard-CTDs it ("Resource '#ID[..]'
-- not found"). Confirmed by the mod's own header (_evt_selection.lua:30-40) and
-- issue 430 (audit F1).
--
-- THE FLOOR (unconditional, sender-side). This is a GAMEPLAY axis — the curse
-- spawns real units — so substitution to a vanilla-safe value is not applicable
-- (issue 371 / BUG_CLASSES 31). The only crash-safe floor is the issue 413
-- lesson: a host-only mod cannot make an injected package-bearing curse safe on
-- a vanilla client, it can only REFUSE to inject it while any lobby peer lacks
-- the mod. So selected_curse_mutators() drops ALL curses whenever
-- curse_wire_safe() is false. The gate is UNCONDITIONAL: never coupled to a
-- menu toggle (memory reference_vt2_wire_safety_never_toggle_gated) — the curse
-- checkbox being ON is necessary but the parity check is a hard AND the user
-- cannot override.
--
-- Detection is the shared exact peer-parity beacon (tools/shared_lib/_lib_peer_parity,
-- issue 371 framework): "does every OTHER human peer run event_tweaker with the
-- same committed 11-row mutator catalog?" proven
-- over VMF's own mod-to-mod channel — wire-safe BY CONSTRUCTION (no vanilla
-- NetworkLookup key, no vanilla RPC; a non-ET peer never acks, so absence-of-ack
-- == absence-of-mod). The floor consumes applied_state() only after the beacon
-- has settled: enabled means solo or every other human peer acknowledged this
-- exact identity; a missing/erroring/mid-transition beacon reads unsafe
-- (fail-safe = curses stay inert). The floor read is LIVE at injection, so a peer
-- who joined moments before the mission remains unconfirmed and the curses are
-- dropped. The beacon's debounced chat notice names the missing peer
-- (register_gated_feature below drives its label).
--
-- HOT-JOIN CONTRACT. A roster beacon is too late for a new peer: vanilla adds
-- the peer to GameSession (which starts game-object replication) before
-- PlayerManager.add_remote_player makes it visible to the beacon. While a
-- package-bearing curse is selected or active, GameModeBase.is_joinable is
-- therefore forced false. PeerStates.Connecting checks that method before it
-- sends rpc_notify_connected, well before GameSession.add_peer. Existing peers
-- still need positive parity, and any already-pending, not-yet-represented peer
-- makes the selection fail closed. This deliberately blocks ALL hot joins for
-- the cursed session; an ET-capable peer is not admitted through a race-prone
-- exception. Uncheck the curses to reopen the lobby.
--
-- Owned by: event_tweaker.lua entry point (dofile'd before _evt_selection, which
-- localizes ET.curse_wire_safe at its top). Consumed via mod._evt export:
-- curse_wire_safe. Also publishes mod._et_peer_parity (the beacon instance) for
-- the regression suite. Owns GameModeBase.is_joinable and the
-- GameNetworkManager.remove_peer retirement hook. The beacon polls the player
-- roster and drives itself off the preserved mod.update chain.

local ET = mod._evt
local rt_register = ET.rt_register
local JoinPolicy = require("scripts/mods/event_tweaker/event_tweaker_curse_join_policy")
local Curses = require("scripts/mods/event_tweaker/event_tweaker_curses")
local WirePolicy = require("scripts/mods/event_tweaker/event_tweaker_curse_wire_policy")

local ET_PEER_PARITY_CHANNEL = "et_curse_catalog_exact_v1"
local ET_PEER_PARITY_SCHEMA  = 3

local _curse_requested = false
local _curse_active = false
local _shadow_requested = false
local _shadow_active = false
local _curse_session_locked = false

local function _refresh_session_lock()
    local locked = _curse_requested or _curse_active or _shadow_requested or _shadow_active
    if locked ~= _curse_session_locked then
        _curse_session_locked = locked
        pcall(printf, "[et:430] peer-required session hot-join contract %s (curse=%s/%s shadow=%s/%s)",
            locked and "LOCKED" or "OPEN", tostring(_curse_requested), tostring(_curse_active),
            tostring(_shadow_requested), tostring(_shadow_active))
    end
end

local function _set_curse_requested(value)
    _curse_requested = value == true
    _refresh_session_lock()
end

local function _set_curse_active(value)
    _curse_active = value == true
    _refresh_session_lock()
end
local function _set_shadow_requested(value)
    _shadow_requested = value == true
    _refresh_session_lock()
end
local function _set_shadow_active(value)
    _shadow_active = value == true
    _refresh_session_lock()
end
local function _pending_remote_peer()
    local managers = rawget(_G, "Managers")
    local pm = managers and managers.player
    local network_manager = managers and managers.state and managers.state.network
    local server = network_manager and network_manager.network_server
    if not (pm and type(pm.player_from_peer_id) == "function"
            and server and type(server.peer_state_machines) == "table") then
        return nil
    end

    local ok_peer, local_peer_id = pcall(function() return Network.peer_id() end)
    if not ok_peer then return nil end

    return JoinPolicy.has_pending_remote(server.peer_state_machines, local_peer_id,
        function(peer_id) return pm:player_from_peer_id(peer_id) end)
end

ET.set_curse_session_requested = _set_curse_requested
ET.set_curse_session_active = _set_curse_active
ET.set_shadow_session_requested = _set_shadow_requested
ET.set_shadow_session_active = _set_shadow_active
ET.curse_session_locked = function() return _curse_session_locked end

-- Pre-flight completed before adding a new hook: event_tweaker had no existing
-- GameModeBase.is_joinable hook. Adventure inherits this implementation.
mod:hook("GameModeBase", "is_joinable", function(func, self, ...)
    local vanilla_joinable = func(self, ...)
    return JoinPolicy.allow_join(vanilla_joinable, _curse_session_locked)
end)

-- Capture the complete local wire proof before the beacon exists. Presence is
-- not compatibility: the same names may have different process-local numeric
-- ids, and a missing/wrong package is independently fatal. Any capture failure
-- leaves the beacon absent and every managed curse inert.
local wire_proof
local wire_proof_err
do
    local ok_catalog, catalog = pcall(function()
        return mod:dofile("scripts/mods/event_tweaker/_lib_wire_catalog")
    end)
    if ok_catalog and type(catalog) == "table" then
        wire_proof, wire_proof_err = WirePolicy.capture(
            Curses,
            rawget(_G, "MutatorTemplates"),
            rawget(_G, "NetworkLookup") and NetworkLookup.mutator_templates,
            catalog)
    else
        wire_proof_err = "wire-catalog-load-failed:" .. tostring(catalog)
    end
end
ET.curse_wire_identity = wire_proof and wire_proof.identity or nil
ET.curse_wire_count = wire_proof and wire_proof.count or 0
if not wire_proof then
    pcall(printf, "[et:430] WARNING exact curse catalog unavailable (%s); managed curses stay inert (fail-safe)",
        tostring(wire_proof_err))
else
    pcall(printf, "[et:430] exact curse catalog identity=%s entries=%d",
        wire_proof.identity, wire_proof.count)
end

-- Build + install the beacon. pcall-guarded end to end: a catalog, lib-load,
-- factory, or install failure must leave curse_wire_safe() false, never fault
-- the mod.
local inst
do
    local ok_lib, factory = false, nil
    if wire_proof then
        ok_lib, factory = pcall(function()
            return mod:dofile("scripts/mods/event_tweaker/_lib_peer_parity")
        end)
    end
    if wire_proof and ok_lib and type(factory) == "function" then
        local ok_inst, built = pcall(factory, mod, {
            channel     = ET_PEER_PARITY_CHANNEL,
            schema      = ET_PEER_PARITY_SCHEMA,
            mod_label   = "Tweaker: Events",
            echo_prefix = "[Events]",
            wire_identity = wire_proof.identity,
        })
        if ok_inst and type(built) == "table" then
            inst = built
        else
            pcall(printf, "[et:430] peer-parity factory failed: %s", tostring(built))
        end
    else
        pcall(printf, "[et:430] peer-parity lib failed to load: %s", tostring(factory))
    end
end

mod._et_peer_parity = inst
local parity_feature_registered = false

-- The UI and gameplay floor deliberately consume this same complete predicate:
-- committed receiver, exact peer set, closed pre-session roster, and the live
-- local catalog still matching the identity advertised to peers.
local function _peer_feature_wire_safe(pp)
    if not pp then return false end
    local ok_installed, installed = pcall(pp.is_installed, pp)
    if not ok_installed or installed ~= true then return false end
    local ok, state = pcall(pp.applied_state, pp)
    if not ok or state ~= "enabled" then return false end

    local pending = _pending_remote_peer()
    return JoinPolicy.can_arm(true, pending)
end

local function _curse_wire_safe()
    if not parity_feature_registered then return false end
    local templates = rawget(_G, "MutatorTemplates")
    local lookup_root = rawget(_G, "NetworkLookup")
    local lookup = lookup_root and lookup_root.mutator_templates
    local ok_intact, intact = pcall(
        WirePolicy.integrity, Curses, templates, lookup, wire_proof)
    if not ok_intact or intact ~= true then return false end
    return _peer_feature_wire_safe(mod._et_peer_parity)
end

if inst then
    -- install() is the commit boundary. The shared helper may have installed a
    -- preserving update wrapper before a later network registration throws, so
    -- a non-throwing factory result is not sufficient proof. Treat a failed or
    -- partial install as terminal for this session: keep the sender floor shut
    -- and do not attach downstream hooks to an uninstalled instance.
    local ok_install, install_err = pcall(inst.install, inst)
    local ok_status, installed = pcall(inst.is_installed, inst)
    if not ok_install or not ok_status or installed ~= true then
        pcall(printf,
            "[et:430] exact beacon install failed terminally; managed curses remain inert: %s",
            tostring(ok_install and (ok_status and installed or "status-error")
                or install_err))
        inst = nil
        mod._et_peer_parity = nil
    end
end

if inst then
    -- Real disconnects retire the acknowledged process epoch. Level transitions
    -- do not call remove_peer, so the shared bounded transition retention still
    -- works while peer-id reuse cannot replay an old exact proof.
    mod:hook_safe("GameNetworkManager", "remove_peer", function(_, peer_id)
        inst:forget_peer(peer_id)
    end)
    pcall(printf, "[et:430] exact peer-parity beacon installed (channel=%s, schema=%d identity=%s); Cursed Adventure curses inert until every lobby peer proves the same catalog",
        ET_PEER_PARITY_CHANNEL, ET_PEER_PARITY_SCHEMA, wire_proof.identity)
    -- ONE gated feature covering the whole Cursed Adventure curse group. Its
    -- callbacks are log-only: the actual injection block is the live
    -- curse_wire_safe() read at selected_curse_mutators(), not these callbacks —
    -- there is no persistent keep-side "applied" curse state to tear down (each
    -- level-load re-evaluates), and in-mission a host cannot un-spawn curse
    -- units. The feature exists to (a) drive the lib's debounced, peer-naming
    -- chat notice (its label is the group name below) and (b) give the
    -- regression suite a registered feature to assert the fail-safe posture on.
    local ok_feature = pcall(function()
        inst:register_gated_feature("et_cursed_adventure_curses", {
            label = "peer_parity_curse_feature_label",
            on_enable = function()
                pcall(printf, "[et:430] peer parity established: Cursed Adventure curses may inject at the next mission load")
            end,
            on_disable = function()
                pcall(printf, "[et:430] peer parity degraded (a lobby peer lacks event_tweaker): Cursed Adventure curses will NOT inject")
            end,
        })
    end)

    -- The registered feature owns the debounced, peer-naming notification.
    -- Installation alone is not completion of the #371 contract: if this
    -- registration seam fails, keep the authoritative injection floor shut
    -- rather than silently enabling package-bearing curses with no warning.
    local ok_count, feature_count = pcall(inst.feature_count, inst)
    parity_feature_registered = ok_feature and ok_count and feature_count >= 1
    if not parity_feature_registered then
        pcall(printf,
            "[et:430] peer-parity feature registration failed; managed curses remain inert")
    end

    -- Optional Mod Tweaker presentation bridge. This only greys the exact 11
    -- managed curse rows; saved values are never rewritten and the injection
    -- floor below remains authoritative even if GUI Tweaker is absent. Retry
    -- because mod load order is not a dependency contract, preserving any
    -- existing update owner.
    local setting_ids = {}
    for i = 1, #Curses.MANAGED_CURSES do
        setting_ids[i] = Curses.MANAGED_CURSES[i].id
    end
    local runtime_gate_registered = false
    local runtime_gate_retry = 0
    local runtime_gate_attempts = 0
    local runtime_gate_terminal = false
    local runtime_gate_id = "event_tweaker:430:exact-curse-catalog"
    local function try_runtime_gate()
        if runtime_gate_registered or runtime_gate_terminal then return end
        runtime_gate_attempts = runtime_gate_attempts + 1
        local spec = WirePolicy.runtime_gate_spec("event_tweaker", setting_ids, function()
            local available = _curse_wire_safe() == true
            return available, available and nil
                or "Unavailable until every player has the same Tweaker: Events curse catalog."
        end)
        local ok_register, registered = pcall(WirePolicy.try_register_runtime_gate,
            rawget(_G, "get_mod"), runtime_gate_id, spec)
        runtime_gate_registered = ok_register and registered == true
        if runtime_gate_registered or runtime_gate_attempts >= 30 then
            runtime_gate_terminal = true
        end
        ET.curse_wire_runtime_gate_registered = runtime_gate_registered
    end
    if parity_feature_registered then
        try_runtime_gate()
        local previous_update = mod.update
        mod.update = function(dt)
            if previous_update then previous_update(dt) end
            if not runtime_gate_terminal then
                runtime_gate_retry = runtime_gate_retry + (dt or 0)
                if runtime_gate_retry >= 1 then
                    runtime_gate_retry = 0
                    try_runtime_gate()
                end
            end
        end
    end
end

ET.curse_wire_safe = _curse_wire_safe
ET.peer_feature_wire_safe = _peer_feature_wire_safe

rt_register("issue430_peer_parity_beacon_installed", function()
    -- The beacon must be built, installed, hold the fail-safe posture, and carry
    -- the one gated feature (the Cursed Adventure curse group). Mirrors ct's
    -- peer_parity_beacon_installed check.
    local pp = mod._et_peer_parity
    if type(pp) ~= "table" then return "mod._et_peer_parity missing (beacon not built)" end
    if not pp:is_installed() then return "beacon not installed (network_register failed?)" end
    if pp._initial_applied ~= "disabled" then return "fail-safe posture changed: initial applied state must be 'disabled'" end
    if pp.FAILSAFE_POSTURE ~= "feature_inert_until_confirmed" then return "fail-safe posture constant changed" end
    if pp.EXACT_MODE ~= true then return "exact catalog mode not active" end
    if type(ET.curse_wire_identity) ~= "string" then return "exact curse identity missing" end
    if ET.curse_wire_count ~= 11 then return "exact curse identity must cover 11 rows" end
    if pp:feature_count() < 1 then return "no gated feature registered (Cursed Adventure curse group)" end
end)

rt_register("issue430_curse_floor_failsafe", function()
    -- The curse floor read must be a function, must never throw, and must
    -- fail-safe to false when the beacon is absent. A solo lobby becomes true
    -- only after the beacon's normal settling tick; this synchronous check
    -- therefore validates type and containment rather than assuming tick order.
    if type(ET.curse_wire_safe) ~= "function" then return "ET.curse_wire_safe not exported" end
    local ok, res = pcall(ET.curse_wire_safe)
    if not ok then return "curse_wire_safe threw (must fail-safe to false, never error)" end
    if type(res) ~= "boolean" then return "curse_wire_safe must return a boolean, got " .. type(res) end
    -- Fail-safe: with the beacon swapped out, the read is false.
    local saved = mod._et_peer_parity
    mod._et_peer_parity = nil
    local ok2, res2 = pcall(ET.curse_wire_safe)
    mod._et_peer_parity = saved
    if not ok2 then return "curse_wire_safe threw with no beacon (must return false)" end
    if res2 ~= false then return "curse_wire_safe must be false with no beacon (fail-safe)" end
end)

rt_register("issue430_curse_floor_classify", function()
    -- Exercise the beacon's pure classifier against simulated peer sets so the
    -- floor's decision logic is asserted without a live lobby (issue 371 spec).
    local pp = mod._et_peer_parity
    local classify = pp and pp.__classify
    if type(classify) ~= "function" then return "__classify not exposed" end
    if classify({}, {}) ~= true then return "solo (no other peers) must classify safe" end
    if classify({ p1 = true }, {}) ~= false then return "un-acked peer (lacks ET) must classify unsafe" end
    if classify({ p1 = true }, { p1 = true }) ~= true then return "all-acked lobby must classify safe" end
    if classify({ p1 = true, p2 = true }, { p1 = true }) ~= false then return "partially-acked lobby must classify unsafe" end
end)

rt_register("issue430_hotjoin_session_contract", function()
    if type(ET.set_curse_session_requested) ~= "function" then return "curse session request setter missing" end
    if type(ET.set_curse_session_active) ~= "function" then return "curse session active setter missing" end
    if type(ET.curse_session_locked) ~= "function" then return "curse session lock accessor missing" end
    if JoinPolicy.allow_join(true, true) ~= false then return "locked cursed session must reject joins" end
    if JoinPolicy.allow_join(true, false) ~= true then return "open session must preserve vanilla joinability" end
    if JoinPolicy.can_arm(true, nil) ~= false then return "unknown pending-peer state must fail closed" end
    if JoinPolicy.can_arm(true, true) ~= false then return "pending peer must block curse arming" end
    if JoinPolicy.can_arm(true, false) ~= true then return "confirmed closed peer set should arm" end
end)
