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
--   inst:install()                                   -- register the VMF channel + wire the update tick (once)
--   inst:register_gated_feature(id, { on_enable=fn, on_disable=fn, label=loc_key })
--   inst:all_peers_have()  -> bool                   -- true = safe to run gated features
--   inst:require_peer(peer_id)                       -- synchronous pre-roster join fence
--   inst:peer_has(peer_id) -> bool                   -- positive VMF acknowledgement only
--   inst:forget_peer(peer_id)                        -- real disconnect; prevents stale-id reuse
--   inst:tick(dt)                                    -- driven automatically by install(); safe to call manually too
--   introspection for the host's regression suite:
--     inst:is_installed() / inst:feature_count() / inst:applied_state() / inst.__classify
-- ============================================================================

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

    local api = {}   -- the instance; methods below take an implicit `self` == api

    -- State ------------------------------------------------------------------
    local _features       = {}          -- feature_id -> { on_enable, on_disable, label }
    local _feature_order  = {}          -- deterministic apply order
    local _acked          = {}          -- peer_id -> true (peer proven to run this mod)
    local _pending        = {}          -- peer_id -> true (join sync began before PlayerManager exposed it)
    local _seen           = {}          -- peer_id -> true (last polled roster, for diffing)
    local _absent_since   = {}          -- acked peer temporarily absent from PlayerManager roster -> monotonic time
    local _applied        = "disabled"  -- fail-safe default; NEVER auto-starts enabled
    local _installed      = false
    local _clock          = 0
    local _poll_accum     = 0
    local _last_announce  = -1e9
    local _enable_at      = nil         -- monotonic time a pending enable fires
    local _notify_at      = nil         -- grace deadline for a disable notice
    local _notified_state = nil         -- last state we told the user about

    -- Immutable record of the chosen posture (asserted by the regression suite).
    api._initial_applied  = "disabled"
    api.FAILSAFE_POSTURE  = "feature_inert_until_confirmed"

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

    -- Presence protocol ------------------------------------------------------
    -- One channel, one payload flag. is_reply=0 is a broadcast query; a peer
    -- that has the mod records the sender and replies is_reply=1 directly. We
    -- do NOT reply to a reply, so there is no ping-pong loop.
    local function _announce(is_reply, recipient)
        if not (mod and type(mod.network_send) == "function") then return end
        pcall(function()
            mod:network_send(CHANNEL, recipient or "others", SCHEMA, is_reply)
        end)
    end

    -- Synchronous join-fence API --------------------------------------------
    -- Polling remains the collision-free normal roster detector. These three
    -- methods close the earlier engine seam where a hot-join full sync occurs
    -- before PlayerManager can be polled. `require_peer` never waits: an
    -- unacknowledged peer disables gated features immediately. The owning mod
    -- then uses its vanilla-safe fallback before allowing the native sync.
    function api:peer_has(peer_id)
        return type(peer_id) == "string" and _acked[peer_id] == true
    end

    function api:require_peer(peer_id)
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
        _pending[peer_id] = nil
        _acked[peer_id] = nil
        _seen[peer_id] = nil
        _absent_since[peer_id] = nil
    end

    function api:install()
        if _installed then return end
        if mod and type(mod.network_register) == "function" then
            local ok = pcall(function()
                mod:network_register(CHANNEL, function(sender_peer_id, schema, is_reply)
                    -- Schema gate (VMF_RECIPES section 10): drop a mismatched peer
                    -- rather than mis-parse its payload. Never error().
                    if schema ~= SCHEMA then
                        _log("%s %s schema mismatch from %s (got %s, want %d) -- dropping",
                            ECHO_PREFIX, CHANNEL, tostring(sender_peer_id), tostring(schema), SCHEMA)
                        return
                    end
                    if type(sender_peer_id) == "string" then
                        _acked[sender_peer_id] = true
                        if is_reply == 0 or is_reply == nil then
                            _announce(1, sender_peer_id)   -- answer a query; never answer an answer
                        end
                    end
                end)
            end)
            if ok then _installed = true end
        end
        -- Drive the tick from VMF's per-frame update, preserving any existing
        -- mod.update. (Host mods that already own mod.update should instead call
        -- inst:tick(dt) from their own update and skip this by pre-setting
        -- mod.update before install(); this preserving wrap covers the common
        -- case where the host has no mod.update.)
        if mod then
            local prev = mod.update
            mod.update = function(dt)
                if prev then pcall(prev, dt) end
                self:tick(dt)
            end
        end
        _announce(0)   -- initial query (covers installing mid-session)
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
                _acked[pid] = nil
                _absent_since[pid] = nil
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
        local ok, err = pcall(_tick_impl, dt)
        if not ok then
            pcall(_force_disable)   -- any beacon error -> features OFF (fail-safe)
            _log("%s tick errored (features forced off): %s", ECHO_PREFIX, tostring(err))
        end
    end

    return api
end

return new_peer_parity
