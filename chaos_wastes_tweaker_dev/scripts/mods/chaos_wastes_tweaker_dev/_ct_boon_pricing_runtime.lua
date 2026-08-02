-- Runtime owner for issue #467.  One exact-name policy drives card display,
-- affordability, telemetry, authoritative charging, and bot charging.

local mod = get_mod("ct_dev")
local policy = mod._ct_boon_pricing_policy
local M = {}
local REAL_PLAYER_LOCAL_ID = 1
local report_count = 0

local function enabled()
    local reader = mod._ct_effective_setting
    return (reader and reader("ct_individual_boon_prices") or mod:get("ct_individual_boon_prices")) == true
end

local function report(fmt, ...)
    if report_count >= 24 then return end
    report_count = report_count + 1
    pcall(printf, "[ct:467] " .. fmt, ...)
end

function M.price(power_up, discount, percent)
    if not enabled() or type(power_up) ~= "table" then return nil end
    return policy.price(power_up.name, power_up.rarity, discount, percent)
end

local function current_percent(view_or_controller)
    local start = mod._ct_start_shrine_runtime
    if start and start.is_context then
        local drc = view_or_controller and (view_or_controller._deus_run_controller or view_or_controller)
        if start.is_context(drc) then
            local cfg = rawget(_G, "DeusShopSettings")
            cfg = cfg and cfg.shop_types and cfg.shop_types.dlc_morris_map
            return type(cfg) == "table" and cfg.ct_cost_percent or 100
        end
    end
    return 100
end

function M.view_price(view, power_up, discount)
    return M.price(power_up, discount, current_percent(view))
end

-- Exact post-pass because vanilla's _get_power_up_costs receives only rarity.
function M.enforce_shop(view)
    if not enabled() or not view then return end
    local offers = view._shop_items and view._shop_items.power_ups
    local drc = view._deus_run_controller
    if type(offers) ~= "table" or not drc then return end
    local peer = drc.get_own_peer_id and drc:get_own_peer_id()
    local coins = peer and drc.get_player_soft_currency and drc:get_player_soft_currency(peer)
    for i = 1, #offers do
        local entry = offers[i]
        local power_up = entry and entry.power_up
        local content = entry and entry.widget and entry.widget.content
        local price = M.view_price(view, power_up, entry and entry.discount)
        if content and price then
            content.price_text = tostring(price)
            local maxed = peer and drc.reached_max_power_ups and power_up
                and drc:reached_max_power_ups(peer, power_up.name)
            local bought = peer and drc.has_power_up and power_up
                and drc:has_power_up(peer, power_up.client_id)
            content.is_bought = maxed or bought or false
            if content.button_hotspot then
                content.button_hotspot.disable_button = content.is_bought
                    or type(coins) ~= "number" or coins < price
            end
        end
    end
end

-- Returns handled, bought, charged_cost. Start-shrine policy owns its exact
-- purchase limit and calls the same price policy separately.
function M.try_buy(drc, buyer, power_up, discount)
    if not enabled() then return false end
    local start = mod._ct_start_shrine_runtime
    if start and start.is_context and start.is_context(drc) then return false end
    local price = M.price(power_up, discount, 100)
    if not price or buyer == nil or type(power_up) ~= "table"
            or type(power_up.name) ~= "string" or power_up.client_id == nil
            or type(drc.has_power_up) ~= "function" then
        report("purchase rejected: invalid exact-price state boon=%s", tostring(power_up and power_up.name))
        return true, false, price
    end
    if drc:has_power_up(buyer, power_up.client_id) then return true, false, price end

    local state = drc._run_state
    if not state or type(state.get_player_profile) ~= "function"
            or type(state.get_player_soft_currency) ~= "function"
            or type(state.get_player_power_ups) ~= "function"
            or type(state.set_player_power_ups) ~= "function"
            or type(state.set_player_soft_currency) ~= "function"
            or type(state.get_bought_power_ups) ~= "function"
            or type(state.set_bought_power_ups) ~= "function"
            or type(drc._add_coin_tracking_entry) ~= "function"
            or type(table.clone) ~= "function" then
        report("purchase rejected: run-state contract unavailable")
        return true, false, price
    end
    local profile, career = state:get_player_profile(buyer, REAL_PLAYER_LOCAL_ID)
    local coins = state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
    local owned = profile and career and state:get_player_power_ups(
        buyer, REAL_PLAYER_LOCAL_ID, profile, career)
    local bought = state:get_bought_power_ups()
    if type(coins) ~= "number" or coins < price then return true, false, price end
    if type(owned) ~= "table" or type(bought) ~= "table" then
        report("purchase rejected: boon ledgers unavailable")
        return true, false, price
    end

    owned = table.clone(owned, true)
    bought = table.clone(bought, true)
    table.insert(owned, power_up)
    bought[#bought + 1] = power_up.name
    state:set_player_power_ups(buyer, REAL_PLAYER_LOCAL_ID, profile, career, owned)
    state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, coins - price)
    local rarity = tostring(power_up.rarity)
    local event = (tonumber(discount) or 0) == 0 and rarity .. "_power_up"
        or rarity .. "_discounted_power_up"
    drc:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -price, event)
    state:set_bought_power_ups(bought)
    report("purchase accepted boon=%s price=%d tier=%s", power_up.name, price,
        tostring(policy.tier(power_up.name, power_up.rarity)))
    return true, true, price
end

function M.regression()
    if type(policy) ~= "table" or type(policy.price) ~= "function" then
        return "#467 REGRESSION: exact-name price policy unavailable"
    end
    local report = policy.audit_catalog(rawget(_G, "DeusPowerUpsArrayByRarity"))
    if report.total > 0 and (report.priced ~= report.total or #report.missing > 0) then
        return string.format("#467 REGRESSION: catalog coverage %d/%d missing=%s",
            report.priced, report.total, table.concat(report.missing, ","))
    end
    if policy.price("barkskin", "rare", 0, 100) ~= 225
            or policy.price("barkskin", "rare", 0.5, 100) ~= 112
            or policy.price("barkskin", "rare", 0, 50) ~= 113 then
        return "#467 REGRESSION: exact price/discount/start multiplier composition drifted"
    end
end

function M.summary()
    local audit = policy.audit_catalog(rawget(_G, "DeusPowerUpsArrayByRarity"))
    report("pricing active=%s catalog=%d/%d overrides=%d missing=%d",
        tostring(enabled()), audit.priced, audit.total, audit.overrides, #audit.missing)
    return audit
end

return M
