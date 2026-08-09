-- _cos_la_replay_runtime.lua -- bounded Loremaster appearance replay owner.
--
-- Owns the existing #660 replay state plus its per-record apply and bounded
-- edge coordinator. Runtime rendering, persistence, transport, and lifecycle
-- triggers remain with their established owners and arrive as dependencies.
-- Repeated installation is deliberately idempotent.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: mod:dofile(.../_cos_la_replay_runtime).install(mod, deps).

local M = {}

function M.install(mod, deps)
    if mod._cos_la_replay_runtime_owner then
        return mod._cos_la_replay_runtime_owner
    end

    deps = deps or {}
    local policy = assert(deps.policy, "policy required")
    local wearer_unit_for_peer = assert(deps.wearer_unit_for_peer,
        "wearer_unit_for_peer required")
    local unit_alive = assert(deps.unit_alive, "unit_alive required")
    local is_local_server = assert(deps.is_local_server,
        "is_local_server required")
    local la_equips_by_peer = assert(deps.la_equips_by_peer,
        "la_equips_by_peer required")
    local log = deps.printf

    mod._cos_replay_state = mod._cos_replay_state or policy.new_replay_state()
    mod._cos_replay = mod._cos_replay or {}
    local replay = mod._cos_replay
    replay.policy = policy

    -- Per-record apply. Reuses the proven machinery and maps its result to the
    -- reconciler's three-state status so coalescing/deferral stays in the pure
    -- policy:
    --   "applied" - engine re-drove the render for a spawned, ready wearer
    --   "defer"   - wearer/husk not ready - retry on the NEXT bounded edge
    --   "skip"    - terminal (store entry gone / deus-yield) - never retry
    replay.apply = function(peer, slot, record)
        if type(record) ~= "table" then return "skip" end
        local wearer_unit = wearer_unit_for_peer(peer)
        -- Peer-readiness gate (BUG_CLASSES husk-skeleton-readiness): never
        -- write to a husk that is not alive; defer to the next bounded edge,
        -- do not poll.
        if not (wearer_unit and unit_alive(wearer_unit)) then return "defer" end
        if record.offhand_unit ~= nil then
            -- #416 vanilla offhand mesh: a re-wield pulse re-drives the husk
            -- get_item_units branch which reads the surviving store.
            if mod._la_native_pulse then
                mod._la_native_pulse(wearer_unit, "replay")
            end
            return "applied"
        end
        local applied, reason = mod._la_reconcile(peer, slot, "replay", true)
        if applied then return "applied" end
        if reason == "no-entry" or reason == "deus-yield" then return "skip" end
        return "defer"
    end

    -- Fire one bounded replay edge. invalidate_all (husk-recreating
    -- transition) or invalidate_peer reset only the relevant coalescing scope.
    replay.on_edge = function(edge_name, opts)
        opts = opts or {}
        local state = mod._cos_replay_state
        if not state then return end
        -- #267: a client whose hot-join state pull exhausted all attempts gets
        -- another bounded window at an explicit edge rather than polling.
        if mod._la_state_pull_exhausted and not is_local_server() then
            mod._la_state_pull_exhausted = nil
            mod._la_state_pull_pending = { attempts = 0, next_at = 0 }
            if log then
                log("[cos:replay] edge=%s state-pull re-armed after prior exhaustion",
                    tostring(edge_name))
            end
        end
        if opts.invalidate_all then
            policy.invalidate_all(state)
        elseif opts.invalidate_peer ~= nil then
            policy.invalidate(state, opts.invalidate_peer)
        end
        local records = policy.build_records(la_equips_by_peer,
            mod._offhand_mesh_by_peer, { only_peer = opts.only_peer })
        local result = policy.reconcile_edge(state, edge_name, records,
            replay.apply)
        if log then
            local emitted = false
            for peer, count in pairs(result.per_peer) do
                if (tonumber(count) or 0) > 0 then
                    log("[cos:replay] edge=%s peer=%s applied=%d",
                        tostring(edge_name), tostring(peer), count)
                    emitted = true
                end
            end
            if not emitted then
                log("[cos:replay] edge=%s peer=none applied=0 (deferred=%d coalesced=%d)",
                    tostring(edge_name), result.deferred, result.coalesced)
            end
        end
        return result
    end

    local owner = {
        policy = policy,
        replay = replay,
    }
    mod._cos_la_replay_runtime_owner = owner
    return owner
end

return M
