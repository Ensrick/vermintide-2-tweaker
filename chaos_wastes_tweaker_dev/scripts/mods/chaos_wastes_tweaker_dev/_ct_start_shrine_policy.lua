-- _ct_start_shrine_policy.lua — pure pricing and purchase-ledger policy for #458.
--
-- This module owns only deterministic Lua-value transformations: validation of
-- the two player settings, vanilla-compatible shop-price calculation, and a
-- per-run/per-player purchase ledger. Runtime hooks and engine mutations live
-- in _ct_start_shrine_runtime.lua.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: one manifest dofile.

local M = {}

M.DEFAULT_COST_PERCENT = 100
M.DEFAULT_PURCHASE_LIMIT = 0
M.MAX_PURCHASE_LIMIT = 8

local function finite_number(value)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

function M.cost_percent(value)
    value = finite_number(value)
    if not value or value < 0 or value > 200 or value % 10 ~= 0 then return nil end
    return value
end

function M.purchase_limit(value)
    value = finite_number(value)
    if not value or value < 0 or value > M.MAX_PURCHASE_LIMIT or value % 1 ~= 0 then return nil end
    return value
end

function M.scaled_cost(cost, percent)
    cost = finite_number(cost)
    percent = M.cost_percent(percent)
    if not cost or cost < 0 or not percent then return nil end
    return math.floor(cost * percent / 100 + 0.5)
end

function M.shop_cost(cost_settings, rarity, discount, percent)
    local shop = type(cost_settings) == "table" and cost_settings.shop
    local costs = type(shop) == "table" and shop.power_ups
    local base = type(costs) == "table" and finite_number(costs[rarity])
    discount = discount == nil and 0 or finite_number(discount)
    if not base or base < 0 or not discount or discount < 0 or discount > 1 then return nil end

    -- Match DeusRunController._try_buy_power_up exactly: discount is rounded
    -- before the start-shrine multiplier is applied.
    local discounted = base - math.floor(base * discount + 0.5)
    return M.scaled_cost(discounted, percent)
end

function M.begin_run(ledger, run_id)
    if type(ledger) ~= "table" or run_id == nil then return nil end
    if ledger.run_id ~= run_id then
        ledger.run_id = run_id
        ledger.counts = {}
    elseif type(ledger.counts) ~= "table" then
        ledger.counts = {}
    end
    return ledger
end

local function peer_counts(ledger, peer_id, create)
    if type(ledger) ~= "table" or type(ledger.counts) ~= "table" or peer_id == nil then return nil end
    local counts = ledger.counts[peer_id]
    if not counts and create then
        counts = {}
        ledger.counts[peer_id] = counts
    end
    return counts
end

function M.count(ledger, run_id, peer_id, local_player_id)
    if not M.begin_run(ledger, run_id) then return nil end
    local counts = peer_counts(ledger, peer_id, false)
    return counts and counts[local_player_id or 1] or 0
end

function M.can_purchase(ledger, run_id, peer_id, local_player_id, limit)
    limit = M.purchase_limit(limit)
    local count = M.count(ledger, run_id, peer_id, local_player_id)
    if not limit or count == nil then return false, count end
    return limit == 0 or count < limit, count
end

function M.record_purchase(ledger, run_id, peer_id, local_player_id)
    if not M.begin_run(ledger, run_id) then return nil end
    local counts = peer_counts(ledger, peer_id, true)
    local_player_id = local_player_id or 1
    counts[local_player_id] = (counts[local_player_id] or 0) + 1
    return counts[local_player_id]
end

return M
