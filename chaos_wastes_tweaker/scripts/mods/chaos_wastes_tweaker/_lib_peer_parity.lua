-- ============================================================================
-- SHARED LIBRARY  --  peer-parity beacon (issue 371 / issue 424 / BUG_CLASSES 31)
-- ----------------------------------------------------------------------------
-- MASTER SOURCE: tools/shared_lib/_lib_peer_parity.lua
-- DO NOT EDIT THE COPIES. Per-mod copies live at
--     scripts/mods/<mod>/_lib_peer_parity.lua
-- and are loaded via `mod:dofile("scripts/mods/<mod>/_lib_peer_parity")`.
-- Edit the master here, then re-copy the whole file (verbatim) to every
-- consumer. The standalone invariant (MOD_DEPENDENCIES.md) forbids a runtime
-- `get_mod()` dependency between our mods, so this is a COPIED single-source
-- file, never a shared `require`. `mod:dofile` returns a FRESH module per call
-- (memory: `reference_vmf_dofile_not_singleton`), so the module is a FACTORY:
-- call `new_peer_parity(mod, opts)` once per host mod to get one instance.
-- ============================================================================
--
-- WHAT THIS IS
--   A per-mod "everyone in the lobby has my mod?" beacon. Gameplay features that
--   put mod-only NetworkLookup indices onto vanilla RPCs (spawn a modded pickup,
--   send a modded buff, etc.) crash any lobby peer who lacks the mod: their
--   NetworkLookup table has no such index, so the strict `__index` fatals
--   (BUG_CLASSES 31). Substitution fixes the COSMETIC axes; a GAMEPLAY axis
--   (where the substitute would change what happens) cannot be substituted, so
--   the feature must go INERT while any peer lacks the mod, and re-activate once
--   everyone has it. This lib is that gate.
--
-- WHY VMF network, not lobby-data / a vanilla RPC
--   Presence is proven by VMF's OWN mod-to-mod messaging: `mod:network_send`
--   is delivered ONLY to peers that have a mod of the SAME id with a matching
--   `mod:network_register` handler (the same property et's `et_br_fingerprint`
--   handshake relies on). So a peer WITHOUT the mod never receives our ping and
--   never replies -> ABSENCE of a reply == absence of the mod. We NEVER add a
--   key to any vanilla NetworkLookup table and NEVER ride a vanilla RPC, so the
--   beacon is wire-safe BY CONSTRUCTION (VMF_RECIPES section 3 / section 10).
--
-- HOW peer join/leave is detected (poll, not hook -- deliberate)
--   The tick polls `Managers.player:human_players()` (player_manager.lua:477 ->
--   `_human_players`, populated in add_remote_player:312, cleared in
--   remove_player:430) and diffs the peer-id set frame-over-frame. Each player's
--   peer id is the `peer_id` FIELD (remote_player.lua:8, bulldozer_player.lua:16;
--   bots go only to `_players`, never `_human_players`, so they are excluded for
--   free). We poll rather than `mod:hook_safe("PlayerManager","add_remote_player")`
--   / `"remove_player"` because this file is COPIED into the host mod and its
--   hooks would register under the HOST mod's id -- if that mod already hooks
--   either method, VMF silently DROPS the second registration on the same
--   (Class, method) (CLAUDE.md NON-NEGOTIABLE 8 / VMF_RECIPES section 1) and one
--   side vanishes with no error. Polling has zero hook-collision surface and is
--   the same approach gt's `_gt_lobby_modded_manifest.lua` takes (POLL 1.0s).
--
-- FAIL-SAFE POSTURE (chosen)  --  "feature inert until positively confirmed"
--   * The applied state initialises to "disabled". A feature is only ENABLED
--     after a positive all-peers-present evaluation; it is DISABLED immediately
--     the moment an un-acked peer is seen. Disable is instant (the crash-safe
--     direction); enable waits a short settle (absorbs ack races, no flicker).
--   * `all_peers_have()` returns true ONLY on positive evidence: solo / no other
--     humans (nothing to crash), or every other human peer acked. Zero
--     information (can't enumerate, or peers present but none acked) -> false.
--   * Any error inside the tick force-disables every feature (pcall-wrapped per
--     PROJECT_STANDARDS section 4). Erroring can only ever turn features OFF.
--
-- API (on the instance returned by the factory)
--   inst:install()  -> bool                          -- register the VMF channel + wire the update tick (once)
--   inst:register_gated_feature(id, { on_enable=fn, on_disable=fn, label=loc_key })
--   inst:all_peers_have()  -> bool                   -- true = safe to run gated features
--   inst:require_peer(peer_id)                       -- synchronous pre-roster join fence
--   inst:peer_has(peer_id) -> bool                   -- positive VMF acknowledgement only
--   inst:forget_peer(peer_id)                        -- real disconnect; prevents stale-id reuse
--   inst:tick(dt)                                    -- driven automatically by install(); safe to call manually too
--   introspection for the host's regression suite:
--     inst:is_installed() / inst:feature_count() / inst:applied_state() / inst.__classify
--
-- INSTALL IS ONE TRANSACTION (issue 371 / issue 1158)
--   `install()` owns TWO side effects: it hands the channel receiver to VMF and
--   it takes ownership of `mod.update`. Either can throw (a host transport can
--   retain the receiver and then fail; a hostile `__newindex` can store the
--   wrapper and then fail), which would leave a beacon that LOOKS built but can
--   never close its floor. So both happen inside ONE pcall, `_installed` commits
--   only after both return, and the receiver is INERT until that commit. On a
--   throw the exact previous `mod.update` is restored if the wrapper had already
--   become externally visible. The attempt is then TERMINAL for the instance
--   (`_install_attempted`): a retry could double-register a receiver the
--   transport already retained, so a partial install never gets a second try.
--   `install()` returns the commit boolean; every consumer floor consumes it.
--   Every peer query (`all_peers_have`/`peer_has`/`require_peer`) and `tick()`
--   hard-gate on `_installed`, so an uninstalled instance is fail-closed by
--   construction rather than by caller discipline.
--
-- OPTIONAL EXACT-CATALOG MODE
--   Pass opts.wire_identity to require byte-exact feature/catalog identity in
--   addition to same-mod presence. Legacy consumers that omit it keep the
--   original two-field [schema, reply] payload exactly. Exact mode uses
--   [schema, reply, identity, session_epoch, challenge, reply_echo], rejects
--   stale/replayed proof, and bounds retired epoch history.
--
-- MODULE-LEVEL REGISTRY  --  registry.all_peers_have(mod_id)   (OOP plan WS1.5)
--   The chunk returns TWO values: the factory (value 1, unchanged -- every
--   consumer keeps `local factory = mod:dofile(...)` and its
--   `type(factory) == "function"` guard) and a small registry module (value 2).
--   Each instance also carries it as `inst.registry`, which is the reachable
--   path in-game because `mod:dofile` is not guaranteed to propagate a chunk's
--   second return value.
--   Instances enter the registry at their install COMMIT, keyed by
--   `opts.mod_id` (or the host mod's VMF name). `registry.all_peers_have(id)`
--   returns false for an unknown id and otherwise AND-folds every instance
--   registered under it -- a mod with several beacons (cwv runs a presence
--   channel plus two exact channels) is "all peers have it" only when EVERY
--   one of its beacons says so. Fail-closed on unknown id, empty registry, or
--   any error. It is a QUERY ONLY: it never installs, mutates, or reaches into
--   another mod, so it adds no cross-mod coupling and cannot violate the
--   standalone invariant.
--   SCOPE: `mod:dofile` returns a FRESH module per call, so the registry spans
--   exactly the instances built from ONE dofile of this file. That is the
--   correct scope for the copied-lib design -- there is no shared runtime to
--   host a repo-wide registry, and inventing one would be the get_mod()
--   dependency MOD_DEPENDENCIES.md forbids.
-- ============================================================================

-- Module-level registry. Chunk-scoped upvalue (see SCOPE above), populated only
-- at an install commit; instances are per-session and are never de-registered.
local registry = {}
local _registered = {}   -- mod_id -> array of committed instances

local function _registry_add(mod_id, instance)
    if type(mod_id) ~= "string" or mod_id == "" or type(instance) ~= "table" then
        return false
    end
    local bucket = _registered[mod_id]
    if not bucket then
        bucket = {}
        _registered[mod_id] = bucket
    end
    for i = 1, #bucket do
        if bucket[i] == instance then return true end
    end
    bucket[#bucket + 1] = instance
    return true
end

-- Fail closed: unknown id, no committed instance, or any error -> false.
function registry.all_peers_have(mod_id)
    if type(mod_id) ~= "string" or mod_id == "" then return false end
    local bucket = _registered[mod_id]
    if type(bucket) ~= "table" or #bucket == 0 then return false end
    for i = 1, #bucket do
        local instance = bucket[i]
        local ok, res = pcall(instance.all_peers_have, instance)
        if not ok or res ~= true then return false end
    end
    return true
end

-- Introspection for the offline suite; never a gameplay input.
function registry.instance_count(mod_id)
    local bucket = type(mod_id) == "string" and _registered[mod_id]
    return type(bucket) == "table" and #bucket or 0
end

local function new_peer_parity(mod, opts)
    opts = opts or {}

    -- Per-host configuration. The CHANNEL must be UNIQUE to the host mod (VMF
    -- namespaces messages by mod id, but a distinct name keeps intent clear and
    -- avoids clashing with any other channel the mod already defines).
    local CHANNEL         = opts.channel            or "peer_parity_present"
    local SCHEMA          = opts.schema             or 1        -- RPC schema (VMF_RECIPES section 10)
    local MOD_LABEL       = opts.mod_label          or "this mod" -- human name used in the chat notice
    local ECHO_PREFIX     = opts.echo_prefix        or "[mod]"
    local POLL_INTERVAL   = opts.poll_interval      or 0.5      -- seconds between roster evaluations
    local SETTLE_ENABLE   = opts.settle_enable      or 2.0      -- seconds an all-present state must hold before re-enabling
    local NOTIFY_GRACE    = opts.notify_grace       or 10.0     -- longer than observed normal join handshakes; safety still disables immediately
    local ABSENCE_GRACE   = opts.absence_grace      or 15.0     -- retain a positive ack across bounded PlayerManager level-transition gaps
    local ANNOUNCE_EVERY  = opts.announce_interval  or 10.0     -- heal-broadcast cadence

    -- Registry key. Explicit `opts.mod_id` wins; otherwise fall back to the
    -- host's VMF name. A mod whose name cannot be read simply stays unqueryable
    -- by id -- its own instance methods are unaffected.
    local MOD_ID = opts.mod_id
    if type(MOD_ID) ~= "string" or MOD_ID == "" then
        MOD_ID = nil
        if mod and type(mod.get_name) == "function" then
            local ok_name, name = pcall(mod.get_name, mod)
            if ok_name and type(name) == "string" and name ~= "" then MOD_ID = name end
        end
    end

    local api = {}   -- the instance; methods below take an implicit `self` == api

    -- Exact mode is strictly opt-in. These limits are shared with the proven
    -- WT #431 transport and keep the VMF JSON envelope below Stingray's 500
    -- character string cap. The restricted alphabet also prevents JSON escape
    -- expansion from invalidating the calculation.
    local MAX_SAFE_STRING = 64
    local MAX_VMF_JSON_LENGTH = 500
    local MAX_RETIRED_EPOCHS_PER_PEER = 8
    local MAX_RETIRED_PEERS = 32
    local EXACT_MODE = opts.wire_identity ~= nil
    local WIRE_IDENTITY = opts.wire_identity

    local function _safe_wire_string(value)
        return type(value) == "string" and value ~= "" and #value <= MAX_SAFE_STRING
            and value:match("^[%w_.:%-]+$") ~= nil
    end

    if EXACT_MODE and not _safe_wire_string(WIRE_IDENTITY) then
        return nil, "wire-identity-invalid"
    end

    local function _default_epoch()
        local sequences = mod and rawget(mod, "_peer_parity_epoch_sequences")
        if type(sequences) ~= "table" then
            sequences = {}
            if mod then rawset(mod, "_peer_parity_epoch_sequences", sequences) end
        end
        local sequence = tonumber(sequences[CHANNEL]) or 0
        sequence = sequence + 1
        sequences[CHANNEL] = sequence
        local entropy = tostring(api):match("0x(%x+)") or "0"
        return string.format("e%d-%s", sequence, entropy:lower()):sub(1, MAX_SAFE_STRING)
    end

    local LOCAL_EPOCH = EXACT_MODE and (opts.session_epoch or _default_epoch()) or nil
    if EXACT_MODE and not _safe_wire_string(LOCAL_EPOCH) then
        return nil, "session-epoch-invalid"
    end

    -- State ------------------------------------------------------------------
    local _features       = {}          -- feature_id -> { on_enable, on_disable, label }
    local _feature_order  = {}          -- deterministic apply order
    local _acked          = {}          -- peer_id -> true (peer proven to run this mod)
    local _pending        = {}          -- peer_id -> true (join sync began before PlayerManager exposed it)
    local _seen           = {}          -- peer_id -> true (last polled roster, for diffing)
    local _absent_since   = {}          -- acked peer temporarily absent from PlayerManager roster -> monotonic time
    local _applied        = "disabled"  -- fail-safe default; NEVER auto-starts enabled
    local _installed      = false
    local _install_attempted = false     -- terminal transaction latch; partial registration is never retried
    local _clock          = 0
    local _poll_accum     = 0
    local _last_announce  = -1e9
    local _enable_at      = nil         -- monotonic time a pending enable fires
    local _notify_at      = nil         -- grace deadline for a disable notice
    local _notified_state = nil         -- last state we told the user about
    local _peer_epoch     = {}          -- exact mode: peer_id -> current process epoch
    local _retired_epoch  = {}          -- exact mode: bounded peer -> { set, order }
    local _retired_peers  = {}          -- exact mode: FIFO peer ids
    local _outstanding    = {}          -- exact mode: recipient/broadcast -> challenge
    local _reply_to       = {}          -- exact mode: peer -> challenge to echo
    local _challenge_seq  = 0
    local _reject_logged  = {}
    local _reject_count   = 0

    -- Immutable record of the chosen posture (asserted by the regression suite).
    api._initial_applied  = "disabled"
    api.FAILSAFE_POSTURE  = "feature_inert_until_confirmed"
    api.EXACT_MODE = EXACT_MODE
    api.WIRE_IDENTITY = WIRE_IDENTITY
    api.LOCAL_EPOCH = LOCAL_EPOCH
    api.MAX_SAFE_STRING = MAX_SAFE_STRING
    api.MAX_VMF_JSON_LENGTH = MAX_VMF_JSON_LENGTH
    api.MAX_RETIRED_EPOCHS_PER_PEER = MAX_RETIRED_EPOCHS_PER_PEER
    api.MAX_RETIRED_PEERS = MAX_RETIRED_PEERS
    api.MOD_ID = MOD_ID
    -- The reachable in-game handle on the module registry (the chunk's second
    -- return value is not guaranteed to survive mod:dofile).
    api.registry = registry

    function api:max_json_envelope_length()
        -- Exact upper bound for the restricted-alphabet payload:
        -- [schema,reply,"identity","epoch","challenge","reply_echo"]
        return EXACT_MODE and (2 + 5 + 10 + (MAX_SAFE_STRING + 2) * 4) or 0
    end

    -- Logging (log-only debug channel; never chat). Self-contained + guarded so
    -- the lib works even if the host's helpers differ.
    local function _log(fmt, ...)
        if mod and type(mod.debug) == "function" then
            pcall(mod.debug, mod, fmt, ...)
        end
    end

    -- User-facing chat notice. mod:echo is correct here (PROJECT_STANDARDS 3.6
    -- chat-echo matrix: high-impact operational state change the user must see,
    -- like on_disabled). We pre-build the string and escape '%' because VMF runs
    -- the argument through string.format (a peer name could contain a literal %).
    local function _echo(text)
        if not (mod and type(mod.echo) == "function") then return end
        local safe = tostring(text):gsub("%%", "%%%%")
        pcall(mod.echo, mod, safe)
    end

    -- Roster enumeration -----------------------------------------------------
    local function _local_peer()
        -- Network.peer_id() THROWS "Network backend has not been set" on early
        -- boot / menu states (see character_weapon_variants.lua on_game_state_changed
        -- note), so guard it.
        local ok, id = pcall(function() return Network.peer_id() end)
        if ok then return id end
        return nil
    end

    -- Set of OTHER human peers in the lobby (excludes self + bots). Bots are
    -- never in _human_players, so human_players() is already humans-only.
    local function _other_human_peers()
        local out = {}
        local visible = {}
        local roster_known = false
        local pm = Managers and Managers.player
        if pm and type(pm.human_players) == "function" then
            local ok, humans = pcall(function() return pm:human_players() end)
            if ok and type(humans) == "table" then
                roster_known = true
                local me = _local_peer()
                for _, player in pairs(humans) do
                    local pid = player and player.peer_id
                    if type(pid) == "string" and pid ~= me then
                        out[pid] = true
                        visible[pid] = true
                    end
                end
            end
        end
        -- GameNetworkManager.hot_join_sync runs before PlayerManager adds the
        -- remote player (peer_states.lua:432 vs :450). A host feature can call
        -- require_peer() at that synchronous seam so the new peer is fail-closed
        -- during the otherwise invisible pre-roster interval.
        for pid in pairs(_pending) do
            out[pid] = true
        end
        return out, roster_known, visible
    end

    local function _peer_name(peer_id)
        local pm = Managers and Managers.player
        if pm and type(pm.human_players) == "function" then
            local ok, humans = pcall(function() return pm:human_players() end)
            if ok and type(humans) == "table" then
                for _, player in pairs(humans) do
                    if player and player.peer_id == peer_id and type(player.name) == "function" then
                        local ok2, n = pcall(function() return player:name() end)
                        if ok2 and type(n) == "string" and n ~= "" then return n end
                    end
                end
            end
        end
        return "Player " .. tostring(peer_id):sub(-4)
    end

    -- Pure classifier: with a peer set and an ack set, is everyone present?
    -- Exposed for the host regression suite (fail-safe posture assertions).
    local function _classify(peers, acked)
        for pid in pairs(peers) do
            if not acked[pid] then return false end
        end
        return true
    end
    api.__classify = _classify

    -- Pure retention policy exposed for regression tests. A positive VMF ack is
    -- process/session evidence; PlayerManager temporarily drops the same Steam
    -- peer id while changing levels. Retain only for a bounded window so a real
    -- later rejoin still has to answer a fresh beacon.
    local function _retain_ack(was_acked, absent_for)
        return was_acked == true and type(absent_for) == "number"
            and absent_for >= 0 and absent_for < ABSENCE_GRACE
    end
    api.__retain_ack = _retain_ack
    api.ABSENCE_GRACE = ABSENCE_GRACE
    api.NOTIFY_GRACE = NOTIFY_GRACE

    function api:all_peers_have()
        if not _installed then return false end
        local ok, res = pcall(function()
            local peers, roster_known = _other_human_peers()
            return roster_known and _classify(peers, _acked)
        end)
        if not ok then return false end   -- fail-safe: no information -> not-all-have
        return res
    end

    -- Feature registry -------------------------------------------------------
    function api:register_gated_feature(feature_id, spec)
        if type(feature_id) ~= "string" or type(spec) ~= "table" then return end
        if not _features[feature_id] then
            _feature_order[#_feature_order + 1] = feature_id
        end
        _features[feature_id] = {
            on_enable  = spec.on_enable,
            on_disable = spec.on_disable,
            label      = spec.label or feature_id,
        }
        -- Late-registration coherence: if the gate is already ENABLED (an
        -- all-present mission), bring the new feature up to match. If DISABLED
        -- (the init / fail-safe state), leave it inert -- the next tick promotes
        -- it once all peers are confirmed.
        if _applied == "enabled" then
            local cb = _features[feature_id].on_enable
            if cb then pcall(cb) end
        end
    end

    function api:feature_count()
        local n = 0
        for _ in pairs(_features) do n = n + 1 end
        return n
    end

    function api:applied_state() return _applied end
    function api:is_installed()  return _installed end

    -- Apply / notify ---------------------------------------------------------
    local function _apply(state)
        -- Commit the applied state BEFORE invoking callbacks (issue 506). A
        -- callback that reads inst:applied_state() -- or the late-registration
        -- coherence path in register_gated_feature, which also reads _applied --
        -- must observe the transition it is part of, not the previous one.
        -- Writing _applied first makes the accessor consistent inside a callback;
        -- crt formerly carried a private mirror flag to dodge the old stale read.
        -- Callbacks are pcall-wrapped, so _applied is committed regardless of a
        -- callback error (identical to the prior unconditional trailing write).
        _applied = state
        for _, fid in ipairs(_feature_order) do
            local f  = _features[fid]
            local cb = (state == "enabled") and f.on_enable or f.on_disable
            if cb then
                local ok, err = pcall(cb)
                if not ok then
                    _log("%s feature '%s' %s callback errored: %s", ECHO_PREFIX, fid, state, tostring(err))
                end
            end
        end
    end

    local function _force_disable()
        if _applied ~= "disabled" then _apply("disabled") end
    end

    local function _feature_label_list()
        local parts = {}
        for _, fid in ipairs(_feature_order) do
            local label = _features[fid].label
            if mod and type(mod.localize) == "function" then
                local ok, l = pcall(function() return mod:localize(label) end)
                -- VMF returns "<key>" for an unregistered key; fall back to raw.
                if ok and type(l) == "string" and l ~= "" and l:sub(1, 1) ~= "<" then
                    label = l
                end
            end
            parts[#parts + 1] = tostring(label)
        end
        return table.concat(parts, ", ")
    end

    -- Presence / exact-catalog protocol --------------------------------------
    local function _challenge()
        _challenge_seq = _challenge_seq + 1
        -- Monotonic prefix cannot be truncated away by a maximum-length epoch.
        return string.format("q%d-%s", _challenge_seq, LOCAL_EPOCH):sub(1, MAX_SAFE_STRING)
    end

    local function _retire_epoch(peer_id, epoch)
        if not EXACT_MODE or type(peer_id) ~= "string" or not _safe_wire_string(epoch) then return end
        local retired = _retired_epoch[peer_id]
        if not retired then
            retired = { set = {}, order = {} }
            _retired_epoch[peer_id] = retired
            _retired_peers[#_retired_peers + 1] = peer_id
            if #_retired_peers > MAX_RETIRED_PEERS then
                local oldest_peer = table.remove(_retired_peers, 1)
                _retired_epoch[oldest_peer] = nil
            end
        end
        if retired.set[epoch] then return end
        retired.set[epoch] = true
        retired.order[#retired.order + 1] = epoch
        if #retired.order > MAX_RETIRED_EPOCHS_PER_PEER then
            local oldest = table.remove(retired.order, 1)
            retired.set[oldest] = nil
        end
    end

    local function _transport_forget(peer_id)
        if not EXACT_MODE or type(peer_id) ~= "string" then return end
        _retire_epoch(peer_id, _peer_epoch[peer_id])
        _peer_epoch[peer_id] = nil
        _outstanding[peer_id] = nil
        _reply_to[peer_id] = nil
    end

    local function _accept_epoch(peer_id, epoch, challenged)
        if not _safe_wire_string(epoch) then return false end
        local retired = _retired_epoch[peer_id]
        if retired and retired.set[epoch] then return false end
        local current = _peer_epoch[peer_id]
        if current == nil or current == epoch then
            _peer_epoch[peer_id] = epoch
            return true
        end
        if not challenged then return false end
        _retire_epoch(peer_id, current)
        _peer_epoch[peer_id] = epoch
        return true
    end

    local function _reject(peer_id, reason)
        if type(peer_id) == "string" and peer_id ~= "" then
            _acked[peer_id] = nil
            _pending[peer_id] = true
            _enable_at = nil
            _force_disable()
        end
        local key = tostring(peer_id) .. ":" .. tostring(reason)
        if _reject_count < 64 and not _reject_logged[key] then
            _reject_logged[key] = true
            _reject_count = _reject_count + 1
            _log("%s %s exact proof rejected from %s (%s)",
                ECHO_PREFIX, CHANNEL, tostring(peer_id), tostring(reason))
        end
    end

    -- Legacy mode retains its original two-field payload. Exact mode appends
    -- identity/session/challenge proof; replies echo the received challenge.
    local function _announce(is_reply, recipient)
        if not (mod and type(mod.network_send) == "function") then return end
        pcall(function()
            if not EXACT_MODE then
                mod:network_send(CHANNEL, recipient or "others", SCHEMA, is_reply)
                return
            end
            local query, echo = "", ""
            if is_reply == 0 or is_reply == nil then
                query = _challenge()
                if type(recipient) == "string" and recipient ~= "others" then
                    _outstanding[recipient] = query
                else
                    _outstanding.__broadcast = query
                end
            elseif type(recipient) == "string" then
                echo = _reply_to[recipient] or ""
            end
            mod:network_send(CHANNEL, recipient or "others", SCHEMA, is_reply,
                WIRE_IDENTITY, LOCAL_EPOCH, query, echo)
        end)
    end

    -- Synchronous join-fence API --------------------------------------------
    -- Polling remains the collision-free normal roster detector. These three
    -- methods close the earlier engine seam where a hot-join full sync occurs
    -- before PlayerManager can be polled. `require_peer` never waits: an
    -- unacknowledged peer disables gated features immediately. The owning mod
    -- then uses its vanilla-safe fallback before allowing the native sync.
    function api:peer_has(peer_id)
        return _installed and type(peer_id) == "string" and _acked[peer_id] == true
    end

    function api:require_peer(peer_id)
        if not _installed then return false end
        if type(peer_id) ~= "string" or peer_id == "" then return false end
        _pending[peer_id] = true
        if _acked[peer_id] ~= true then
            _enable_at = nil
            _force_disable()
            _announce(0, peer_id)
            return false
        end
        return true
    end

    function api:forget_peer(peer_id)
        if type(peer_id) ~= "string" then return end
        _transport_forget(peer_id)
        _pending[peer_id] = nil
        _acked[peer_id] = nil
        _seen[peer_id] = nil
        _absent_since[peer_id] = nil
    end

    function api:retired_peer_count() return #_retired_peers end
    function api:is_epoch_retired(peer_id, epoch)
        local retired = _retired_epoch[peer_id]
        return retired ~= nil and retired.set[epoch] == true
    end

    function api:install()
        if _installed then return true end
        -- Terminal latch: a partial attempt is never retried. The transport may
        -- already hold the receiver from the failed attempt, so a second
        -- install() could double-register it.
        if _install_attempted then return false end
        _install_attempted = true

        if not mod or type(mod.network_register) ~= "function" then return false end

        -- Drive the tick from VMF's per-frame update, preserving any existing
        -- mod.update. (Host mods that already own mod.update should instead call
        -- inst:tick(dt) from their own update and skip this by pre-setting
        -- mod.update before install(); this preserving wrap covers the common
        -- case where the host has no mod.update.)
        local previous_update = mod.update
        local wrapped_update = function(dt)
            if previous_update then pcall(previous_update, dt) end
            api:tick(dt)
        end

        local receiver = function(sender_peer_id, schema, is_reply,
                remote_identity, remote_epoch, remote_query, remote_echo)
            -- A host transport can partially retain this callback and then
            -- throw. Until registration commits, the callback is inert: no
            -- acknowledgement, reply, or state mutation.
            if not _installed then return end
            -- Schema gate (VMF_RECIPES section 10): drop a mismatched peer
            -- rather than mis-parse its payload. Never error().
            if schema ~= SCHEMA then
                _log("%s %s schema mismatch from %s (got %s, want %d) -- dropping",
                    ECHO_PREFIX, CHANNEL, tostring(sender_peer_id), tostring(schema), SCHEMA)
                if EXACT_MODE then _reject(sender_peer_id, "schema") end
                return
            end
            if type(sender_peer_id) == "string" then
                if EXACT_MODE then
                    if remote_identity ~= WIRE_IDENTITY then
                        _reject(sender_peer_id, "identity")
                        return
                    end
                    local is_query = is_reply == 0 or is_reply == nil
                    if is_query then
                        if not _safe_wire_string(remote_query)
                                or not _accept_epoch(sender_peer_id, remote_epoch, false) then
                            _reject(sender_peer_id, "query-or-epoch")
                            return
                        end
                        _reply_to[sender_peer_id] = remote_query
                    else
                        local expected = _outstanding[sender_peer_id]
                            or _outstanding.__broadcast
                        if not _safe_wire_string(remote_echo) or remote_echo ~= expected
                                or not _accept_epoch(sender_peer_id, remote_epoch, true) then
                            _reject(sender_peer_id, "echo-or-epoch")
                            return
                        end
                        _outstanding[sender_peer_id] = nil
                    end
                end
                _acked[sender_peer_id] = true
                if is_reply == 0 or is_reply == nil then
                    _announce(1, sender_peer_id)   -- answer a query; never answer an answer
                end
            end
        end

        local ok = pcall(function()
            -- Registration and update ownership are ONE transaction. A transport
            -- may retain the receiver before a later assignment fails, so the
            -- callback stays inert until both operations have returned and
            -- `_installed` commits below.
            mod:network_register(CHANNEL, receiver)
            mod.update = wrapped_update
        end)
        if not ok then
            -- A hostile __newindex fixture can store and then throw. Restore the
            -- exact previous function when the wrapper became externally
            -- visible; if assignment itself was impossible, the old value is
            -- already intact. The terminal latch prevents a second receiver.
            local read_ok, current_update = pcall(function() return mod.update end)
            if read_ok and current_update == wrapped_update then
                pcall(function() mod.update = previous_update end)
            end
            return false
        end

        -- Commit boundary: update ownership, ticks, the first query, and registry
        -- visibility become reachable only after receiver registration AND update
        -- ownership return successfully.
        _installed = true
        _registry_add(MOD_ID, api)
        _announce(0)   -- initial query (covers installing mid-session)
        return true
    end

    -- Core evaluation --------------------------------------------------------
    local function _tick_impl(dt)
        _clock      = _clock + (dt or 0)
        _poll_accum = _poll_accum + (dt or 0)
        if _poll_accum < POLL_INTERVAL then return end
        _poll_accum = 0

        local peers, roster_known, visible = _other_human_peers()

        -- Roster diff: detect arrivals and bounded transition absences. The game
        -- removes still-connected humans from PlayerManager while changing
        -- levels; their VMF ack remains positive evidence for the same peer id.
        -- A long absence expires it, so a later rejoin must handshake again.
        local new_peer = false
        for pid in pairs(peers) do
            if not _seen[pid] then new_peer = true end
            -- Once PlayerManager exposes the joining peer, the ordinary roster
            -- owns its lifetime. `forget_peer` handles a real disconnect before
            -- a pending peer ever reaches this point.
            if visible[pid] then
                _pending[pid] = nil
            end
            _absent_since[pid] = nil
        end
        for pid in pairs(_seen) do
            if not peers[pid] and _absent_since[pid] == nil then
                _absent_since[pid] = _clock
            end
        end
        for pid, since in pairs(_absent_since) do
            if not peers[pid] and not _retain_ack(_acked[pid], _clock - since) then
                -- Expiry is a real proof boundary in exact mode: retire the
                -- process epoch so a delayed pre-expiry acknowledgement cannot
                -- authorize a later peer-id reuse.
                api:forget_peer(pid)
            end
        end
        _seen = peers

        if new_peer or (_clock - _last_announce) >= ANNOUNCE_EVERY then
            _last_announce = _clock
            _announce(0)
        end

        -- Who is present-but-unconfirmed?
        local missing = {}
        for pid in pairs(peers) do
            if not _acked[pid] then missing[#missing + 1] = pid end
        end
        local desired = (roster_known and #missing == 0) and "enabled" or "disabled"

        if desired == "disabled" then
            _enable_at = nil
            if _applied ~= "disabled" then _apply("disabled") end   -- immediate (fail-safe)
            -- Debounced notice: only tell the user once the missing set has
            -- persisted past the grace window (so a cwv peer mid-handshake does
            -- not flash a spurious "disabled" line).
            if roster_known and _notify_at == nil then _notify_at = _clock + NOTIFY_GRACE end
            if roster_known and _notify_at and _clock >= _notify_at and _notified_state ~= "disabled" then
                local names = {}
                for _, pid in ipairs(missing) do names[#names + 1] = _peer_name(pid) end
                _echo(string.format(
                    "%s Peer-parity: disabled %s. Missing %s: %s. It would crash them; auto re-enables when everyone has it.",
                    ECHO_PREFIX, _feature_label_list(), MOD_LABEL, table.concat(names, ", ")))
                _notified_state = "disabled"
            end
        else
            _notify_at = nil
            if _applied ~= "enabled" then
                -- Pure solo (no other humans) never has an ack race: enable at
                -- once so solo behaves exactly as an ungated build. A populated
                -- all-acked lobby gets the short settle to absorb a dropped ack.
                local settle = (next(peers) == nil) and 0 or SETTLE_ENABLE
                if _enable_at == nil then _enable_at = _clock + settle end
                if _clock >= _enable_at then
                    _apply("enabled")
                    _enable_at = nil
                    if _notified_state == "disabled" then
                        _echo(string.format("%s Peer-parity: re-enabled %s (all players now have %s).",
                            ECHO_PREFIX, _feature_label_list(), MOD_LABEL))
                    end
                    _notified_state = "enabled"
                end
            else
                _enable_at = nil
            end
        end
    end

    function api:tick(dt)
        if not _installed then return end
        local ok, err = pcall(_tick_impl, dt)
        if not ok then
            pcall(_force_disable)   -- any beacon error -> features OFF (fail-safe)
            _log("%s tick errored (features forced off): %s", ECHO_PREFIX, tostring(err))
        end
    end

    return api
end

-- Value 1 stays the factory FUNCTION so every consumer's
-- `type(factory) == "function"` guard is unchanged; value 2 is the registry.
return new_peer_parity, registry
