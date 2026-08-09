-- _cos_glow_transport.lua — host-authoritative per-peer glow transport and replay.
--
-- Owns the two existing glow RPC registrations, the coalesced local publisher,
-- the bounded material-only hot-join rehydrate queue, and the two hot-join
-- replay helpers. It deliberately does not own render hooks, material writes,
-- persistence, or mod lifecycle/update callbacks; those call the stable public
-- functions installed on mod at the historical entry-file seams.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed via: one ordered
-- mod:dofile(...).install call after the LA transport and presentation owner.

local Transport = {}

function Transport.install(mod, deps)
    if mod._cos_glow_transport_owner then
        return mod._cos_glow_transport_owner
    end

    deps = deps or {}
    local glow_by_peer = assert(deps.glow_by_peer, "glow_by_peer is required")
    local rpc_schema = assert(deps.rpc_schema, "rpc_schema is required")
    local is_local_server = assert(deps.is_local_server, "is_local_server is required")
    local host_peer_id = assert(deps.host_peer_id, "host_peer_id is required")
    local log = assert(deps.log, "log is required")
    local dbg = assert(deps.dbg, "dbg is required")
    local dbg_alert = assert(deps.dbg_alert, "dbg_alert is required")
    local clock = deps.clock or os.clock
    local get_managers = deps.get_managers or function() return Managers end
    local get_printf = deps.get_printf or function() return rawget(_G, "printf") end

    -- v0.9.37-dev: emptied. These were the GLOBAL glow-override VMF settings
    -- broadcast to peers so a wearer's chosen global preset painted on remote
    -- husks. The menu no longer owns those settings; per-item state below is
    -- the active payload. Keep the list and collector so future additions have
    -- one bounded transport owner.
    local GLOW_SETTING_KEYS = {}

    local function active_glow_skin(state)
        local identity = type(state) == "table" and state.active_per_item_glow_identity
        return type(identity) == "string" and identity:match("|skin:(.*)$") or nil
    end

    local function collect_local_glow_state()
        local state = {}
        for _, key in ipairs(GLOW_SETTING_KEYS) do
            state[key] = mod:get(key)
        end
        state.active_per_item_glow = mod._active_per_item_glow
        state.active_per_item_glow_identity = mod._active_per_item_glow_identity
        -- The exact identity carries the illusion skin. The wielded slot is the
        -- only additional live discriminator; backend ids stay owner-local.
        state.active_per_item_glow_slot = mod._active_per_item_glow_slot
        return state
    end

    local glow_emit_pending = false
    local glow_last_emit_at = 0
    local GLOW_EMIT_THROTTLE = 0.3
    local COS574_REHYDRATE_INTERVAL = 0.25
    local COS574_REHYDRATE_MAX_ATTEMPTS = 40
    local COS574_REHYDRATE_WINDOW = 10

    -- A hot-join snapshot can beat the husk inventory's hand units. This queue
    -- retries local material application only; it never emits network traffic.
    mod._cos574_glow_rehydrate_pending = mod._cos574_glow_rehydrate_pending or {}
    mod._cos574_glow_join_contract = {
        state_pull = "piggyback_cos_la_state_req",
        new_rpc_channels = 0,
        retry_network = false,
        interval = COS574_REHYDRATE_INTERVAL,
        max_attempts = COS574_REHYDRATE_MAX_ATTEMPTS,
        window = COS574_REHYDRATE_WINDOW,
    }

    local function arm_glow_rehydrate(wearer_peer)
        if not wearer_peer then return end
        if mod._cos574_glow_rehydrate_pending[wearer_peer] then return end
        local now = clock()
        mod._cos574_glow_rehydrate_pending[wearer_peer] = {
            attempts = 0,
            next_at = now,
            deadline = now + COS574_REHYDRATE_WINDOW,
        }
        log("rehydrate armed wearer=%s window=%ss network_retry=false",
            tostring(wearer_peer), tostring(COS574_REHYDRATE_WINDOW))
    end

    local function complete_glow_rehydrate(wearer_peer, path, units)
        if not wearer_peer then return end
        local pending = mod._cos574_glow_rehydrate_pending
        if pending and pending[wearer_peer] then
            pending[wearer_peer] = nil
            log("rehydrate complete wearer=%s path=%s units=%s",
                tostring(wearer_peer), tostring(path), tostring(units or "?"))
        end
    end

    mod._cos574_glow_rehydrate_tick = function()
        local pending = mod._cos574_glow_rehydrate_pending
        if type(pending) ~= "table" or not next(pending) then return end
        local now = clock()
        for wearer_peer, job in pairs(pending) do
            if now >= (job.next_at or 0) then
                if now >= (job.deadline or 0)
                        or (job.attempts or 0) >= COS574_REHYDRATE_MAX_ATTEMPTS then
                    pending[wearer_peer] = nil
                    log("rehydrate expired wearer=%s attempts=%d",
                        tostring(wearer_peer), job.attempts or 0)
                else
                    job.attempts = (job.attempts or 0) + 1
                    job.next_at = now + COS574_REHYDRATE_INTERVAL
                    local ok, applied = pcall(mod._reapply_glow_for_peer, wearer_peer)
                    if ok and type(applied) == "number" and applied > 0 then
                        complete_glow_rehydrate(wearer_peer, "equipment_ready", applied)
                    end
                end
            end
        end
    end

    mod._emit_per_item_glow = function()
        glow_emit_pending = true
    end

    local function send_local_glow_state()
        -- The network backend may not exist at title/pre-keep time. Keep the
        -- pending bit set and retry from the existing mod.update owner.
        local managers = get_managers()
        local pm = managers and managers.player
        if not pm or not pm.local_player then
            glow_emit_pending = true
            return
        end
        local ok, lp = pcall(pm.local_player, pm)
        if not ok or not lp then
            glow_emit_pending = true
            return
        end
        local local_peer = lp.peer_id
        if not local_peer then
            glow_emit_pending = true
            return
        end
        local state = collect_local_glow_state()
        log("sync send role=%s peer=%s identity=%s skin=%s slot=%s",
            is_local_server() and "host" or "client", tostring(local_peer),
            tostring(state.active_per_item_glow_identity),
            tostring(active_glow_skin(state)),
            tostring(state.active_per_item_glow_slot))
        if is_local_server() then
            glow_by_peer[local_peer] = state
            mod:network_send("cos_glow_apply", "all", rpc_schema, {
                wearer_peer_id = local_peer,
                state = state,
            })
        else
            local host = host_peer_id()
            if not host then
                glow_emit_pending = true
                return
            end
            mod:network_send("cos_glow_apply_req", host, rpc_schema, {
                state = state,
            })
        end
        glow_emit_pending = false
        glow_last_emit_at = clock()
    end

    mod._glow_sync_tick = function(dt)
        if not glow_emit_pending then return end
        local now = clock()
        if (now - glow_last_emit_at) < GLOW_EMIT_THROTTLE then return end
        local managers = get_managers()
        local network = managers and managers.state and managers.state.network
        if not network or not network.game then return end
        send_local_glow_state()
    end

    -- HOST: receive client state, validate it, then rebroadcast authoritatively.
    mod:network_register("cos_glow_apply_req", function(sender_peer_id, schema_version, payload)
        if schema_version ~= rpc_schema then
            dbg_alert("[rpc:schema] cos_glow_apply_req mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
                tostring(sender_peer_id), tostring(schema_version), rpc_schema)
            local print_fn = get_printf()
            if print_fn then print_fn("[rpc:schema] cos_glow_apply_req DROP peer=%s sent=v%s expect=v%d",
                tostring(sender_peer_id), tostring(schema_version), rpc_schema) end
            return
        end
        if not is_local_server() then return end
        if type(payload) ~= "table" or type(payload.state) ~= "table" then return end
        if not sender_peer_id then return end
        glow_by_peer[sender_peer_id] = payload.state
        log("sync host-recv wearer=%s identity=%s skin=%s slot=%s",
            tostring(sender_peer_id), tostring(payload.state.active_per_item_glow_identity),
            tostring(active_glow_skin(payload.state)),
            tostring(payload.state.active_per_item_glow_slot))
        mod:network_send("cos_glow_apply", "all", rpc_schema, {
            wearer_peer_id = sender_peer_id,
            state = payload.state,
        })
    end)

    -- ALL PEERS: accept the authoritative broadcast from the host only.
    mod:network_register("cos_glow_apply", function(sender_peer_id, schema_version, payload)
        if schema_version ~= rpc_schema then
            dbg_alert("[rpc:schema] cos_glow_apply mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
                tostring(sender_peer_id), tostring(schema_version), rpc_schema)
            local print_fn = get_printf()
            if print_fn then print_fn("[rpc:schema] cos_glow_apply DROP peer=%s sent=v%s expect=v%d",
                tostring(sender_peer_id), tostring(schema_version), rpc_schema) end
            return
        end
        if type(payload) ~= "table" or type(payload.state) ~= "table" then return end
        local host = host_peer_id()
        if host and sender_peer_id ~= host then
            dbg_alert("[cos_glow_apply] reject non-host sender %s (host=%s)",
                tostring(sender_peer_id), tostring(host))
            return
        end
        local wearer = payload.wearer_peer_id
        if not wearer then return end
        glow_by_peer[wearer] = payload.state
        log("sync recv wearer=%s identity=%s skin=%s slot=%s",
            tostring(wearer), tostring(payload.state.active_per_item_glow_identity),
            tostring(active_glow_skin(payload.state)),
            tostring(payload.state.active_per_item_glow_slot))
        local applied = 0
        if mod._reapply_glow_for_peer then
            local ok_reapply, count = pcall(mod._reapply_glow_for_peer, wearer)
            if ok_reapply and type(count) == "number" then applied = count end
        end
        if applied > 0 then
            complete_glow_rehydrate(wearer, "network_recv", applied)
        elseif payload.state.active_per_item_glow ~= nil then
            arm_glow_rehydrate(wearer)
        else
            mod._cos574_glow_rehydrate_pending[wearer] = nil
        end
    end)

    local function glow_rebroadcast_all_for_hot_join()
        if not is_local_server() then return end
        for wearer_peer, state in pairs(glow_by_peer) do
            mod:network_send("cos_glow_apply", "all", rpc_schema, {
                wearer_peer_id = wearer_peer,
                state = state,
            })
        end
    end
    mod._glow_rebroadcast_all_for_hot_join = glow_rebroadcast_all_for_hot_join

    local function glow_rebroadcast_targeted(target_peer_id)
        if not is_local_server() then return end
        if not target_peer_id then return end
        local n = 0
        for wearer_peer, state in pairs(glow_by_peer) do
            mod:network_send("cos_glow_apply", target_peer_id, rpc_schema, {
                wearer_peer_id = wearer_peer,
                state = state,
            })
            n = n + 1
        end
        if n > 0 then
            dbg("[hot-join glow replay] sent %d cos_glow_apply entries targeted at joiner=%s",
                n, tostring(target_peer_id))
        end
    end
    mod._glow_rebroadcast_targeted = glow_rebroadcast_targeted

    mod._on_glow_setting_changed = function()
        glow_emit_pending = true
    end

    local owner = {
        complete_rehydrate = complete_glow_rehydrate,
    }
    mod._cos_glow_transport_owner = owner
    return owner
end

return Transport
