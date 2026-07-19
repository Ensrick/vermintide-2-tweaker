-- _ct_progressive_difficulty.lua -- pure advanced policy for issue #460.

local M = {}

M.TIERS = {
    "normal", "hard", "harder", "hardest", "cataclysm",
    "cataclysm_2", "cataclysm_3", "cataclysm_4", "cataclysm_5",
}

function M.step_count(completed_level_count)
    local completed = math.max(0, math.floor(tonumber(completed_level_count) or 0))
    if completed >= 4 then return 2 end -- map 5+
    if completed >= 2 then return 1 end -- maps 3-4
    return 0
end

local function registered(key, difficulties, lookup)
    local index = type(lookup) == "table" and rawget(lookup, key) or nil
    return type(index) == "number"
        and type(difficulties) == "table"
        and rawget(difficulties, index) == key
end

function M.cap_tier(start_tier, difficulties, lookup)
    -- Only tiers contiguous with the starting tier are reachable. A provider
    -- that registers Cata 5 but omits Cata 4 must not make map five jump across
    -- the missing tier; stop at the first gap instead.
    if type(start_tier) ~= "number" then return nil end
    local cap = start_tier
    for i = start_tier + 1, #M.TIERS do
        if not registered(M.TIERS[i], difficulties, lookup) then break end
        cap = i
    end
    return cap, M.TIERS[cap]
end

function M.difficulty(start_key, completed_level_count, difficulties, lookup)
    if type(difficulties) ~= "table" or type(lookup) ~= "table" then return start_key end
    local start_tier
    for i = 1, #M.TIERS do
        if M.TIERS[i] == start_key then start_tier = i; break end
    end
    if not start_tier or not registered(start_key, difficulties, lookup) then
        return start_key
    end
    local cap_tier = M.cap_tier(start_tier, difficulties, lookup)
    if not cap_tier then return start_key end
    local key = M.TIERS[math.min(start_tier + M.step_count(completed_level_count), cap_tier)]
    return registered(key, difficulties, lookup) and key or start_key
end

function M.coin_multiplier(base_multiplier, reduction_percent, completed_level_count)
    local base = tonumber(base_multiplier) or 1
    if M.step_count(completed_level_count) == 0 then return base end
    local reduction = tonumber(reduction_percent) or -25
    reduction = math.max(-100, math.min(0, reduction))
    return math.max(0, base * (1 + reduction / 100))
end

function M.install_hot_join(mod, rpc_schema)
    -- Vanilla DeusMechanism.sync_mechanism_data serializes the live (already
    -- stepped) getter. Carry the immutable original tier immediately before
    -- vanilla's setup RPC and consume it once in the joining controller.
    mod:network_register("ct_progdiff_start", function(sender_peer_id, schema_version, start_key)
        if schema_version ~= rpc_schema or type(start_key) ~= "string" then return end
        local nm = Managers and Managers.state and Managers.state.network
        local host_peer = Managers and Managers.mechanism and Managers.mechanism.server_peer_id
            and Managers.mechanism:server_peer_id()
        host_peer = host_peer or (nm and nm.network_client and nm.network_client.server_peer_id)
        if not host_peer or sender_peer_id ~= host_peer then return end
        mod._ct_progdiff_pending_host_start = start_key
        pcall(printf, "[ct:460] received hot-join original difficulty=%s from host=%s",
            tostring(start_key), tostring(sender_peer_id))
    end)

    mod:hook("DeusMechanism", "sync_mechanism_data", function(func, self, peer_id, newly_initialized)
        local controller = self and self._deus_run_controller
        local start_key = controller and controller._ct_progdiff_start
        local run_state = controller and controller._run_state
        local is_server = run_state and run_state.is_server and run_state:is_server()
        if newly_initialized and is_server and type(start_key) == "string" then
            mod:network_send("ct_progdiff_start", peer_id, rpc_schema, start_key)
            pcall(printf, "[ct:460] sent hot-join original difficulty=%s to peer=%s",
                tostring(start_key), tostring(peer_id))
        end
        return func(self, peer_id, newly_initialized)
    end)
end

return M
