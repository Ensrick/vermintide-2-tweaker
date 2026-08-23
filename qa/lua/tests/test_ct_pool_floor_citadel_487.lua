-- #487 Chaos Wastes load freeze - pool-floor sizing regression (engine-free).
--
-- ROOT CAUSE (proven from the 2026-07-13 host console log + decompiled source):
-- the baked deus journeys (citadel/cave/ice/ruin) assign each labeled TRAVEL/
-- SIGNATURE node a level by INDEXING `shuffled_levels_for_labels[type][node_label]`
-- (deus_populate_graph.lua:460), where that list is `get_random_key_list(pool)` (:987)
-- - an array of the pool's DISTINCT keys - and node_label is a 1-based index. A pool
-- floored below the highest label leaves the high-labeled node's level nil, so :462
-- `levels_available[nil].paths` throws "attempt to index a nil value", the graph comes
-- back nil, and the CW run/finale transition deadlocks (the freeze). journey_citadel's
-- baked TRAVEL nodes use labels up to 6, so the floor must mint at least 6 distinct
-- keys. The pre-fix POOL_SAFETY_THRESHOLD=4 left the citadel finale two keys short.
--
-- This gate pins the floor at >= the max baked-journey node_label so a future edit
-- cannot silently drop it back below the citadel requirement.
return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- _adventure_pool.lua only touches get_mod at module scope; stub it with a no-op.
    local old_get_mod = get_mod
    get_mod = function()
        return setmetatable({}, { __index = function() return function() end end })
    end
    local ok, pool = pcall(function()
        return assert(loadfile(base .. "_adventure_pool.lua"))()
    end)
    get_mod = old_get_mod
    assert(ok, "failed to load _adventure_pool.lua offline: " .. tostring(pool))

    -- Max node_label per type across every baked journey, verified against the
    -- decompiled scripts/settings/dlcs/morris/deus_map_baked_base_graphs_*.lua.
    local MAX_BAKED_TRAVEL_LABEL = 6      -- journey_citadel (also cave/ice/ruin)
    local MAX_BAKED_SIGNATURE_LABEL = 5   -- journey_cave/ice/ruin

    H.test("CT #487 pool floor covers the baked-journey max node_label", function()
        H.equal(type(pool.POOL_SAFETY_THRESHOLD), "number")
        -- Must reach the highest TRAVEL label any baked journey uses, or the citadel
        -- finale re-hits the deus_populate_graph.lua:462 nil-index freeze.
        H.equal(pool.POOL_SAFETY_THRESHOLD >= MAX_BAKED_TRAVEL_LABEL, true)
        H.equal(MAX_BAKED_TRAVEL_LABEL >= MAX_BAKED_SIGNATURE_LABEL, true)
    end)

    H.test("CT #487 classify_pool_floor boundaries at the raised threshold", function()
        local cpf = pool.classify_pool_floor
        H.equal(type(cpf), "function")
        local thr = pool.POOL_SAFETY_THRESHOLD
        H.equal(cpf(0), "fallback")         -- zero enabled: nothing to clone -> vanilla
        H.equal(cpf(1), "duplicate")        -- one enabled: repeat it up to the floor
        -- The observed freeze had 4 distinct TRAVEL keys (1 real + 3 dups) yet needed
        -- 6; it must classify as still-needing-duplication, not "ok".
        H.equal(cpf(4), "duplicate")
        H.equal(cpf(thr - 1), "duplicate")  -- one short of the floor still duplicates
        H.equal(cpf(thr), "ok")             -- exactly the floor is satisfied
    end)

    H.test("CT #487 root fix survives retirement of automatic freeze telemetry", function()
        local entry = read(base .. "chaos_wastes_tweaker_dev.lua")
        local run_owner = read(base .. "_ct_run_creation_owner.lua")
        local update_owner = read(base .. "_ct_host_state_transport_owner.lua")
        H.equal(entry:find("_ct_diag_freeze487", 1, true), nil)
        H.equal(entry:find("mod._ct_freeze487", 1, true), nil)
        H.equal(run_owner:find("mod._ct_freeze487", 1, true), nil)
        H.equal(update_owner:find("mod._ct_freeze487", 1, true), nil)
        H.equal(pool.POOL_SAFETY_THRESHOLD >= MAX_BAKED_TRAVEL_LABEL, true)
    end)
end
