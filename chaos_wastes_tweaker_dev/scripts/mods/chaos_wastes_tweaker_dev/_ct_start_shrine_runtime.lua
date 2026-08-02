-- _ct_start_shrine_runtime.lua — synthetic starting-shrine lifecycle and policy.
--
-- Owns the #458 start-node shop config, prepare-before-full-sync crash guard,
-- exact-node price/purchase policy, and per-run/player accounting. Normal later
-- shrines are strict pass-throughs. The existing consolidated
-- DeusRunController._try_buy_power_up hook calls try_buy so host and client use
-- one charged-price function without adding a duplicate hook.
--
-- Owned by: chaos_wastes_tweaker_dev.lua. Consumed via: one manifest dofile.

local mod = get_mod("ct_dev")
local policy = mod._ct_start_shrine_policy
local M = {}
local REAL_PLAYER_LOCAL_ID = 1
local START_LEVEL = "dlc_morris_map"
local START_NODE = "start"
local MAP_DECISION = 1
local SHOP = 3
local report_count = 0
local ledger = {}

local MIRACLE_KEYS = {
    "blessing_of_power", "blessing_of_shallya", "blessing_of_grimnir",
    "blessing_of_isha", "blessing_of_ranald", "blessing_of_abundance",
    "blessing_holy_hand_grenade", "blessing_rally_flag",
}

local function report(fmt, ...)
    if report_count >= 32 then return end
    report_count = report_count + 1
    pcall(printf, "[ct:458] " .. fmt, ...)
end

local function effective(setting_id)
    local reader = mod._ct_effective_setting
    return reader and reader(setting_id) or mod:get(setting_id)
end

local function server_flag(drc)
    local run_state = drc and drc._run_state
    if not run_state or type(run_state.is_server) ~= "function" then return "unknown" end
    local ok, value = pcall(run_state.is_server, run_state)
    return ok and tostring(value) or "unknown"
end

local function seeded_shuffle(list, seed)
    local s = (tonumber(seed) or 0) % 2147483647
    if s <= 0 then s = s + 2147483646 end
    for i = #list, 2, -1 do
        s = s * 16807 % 2147483647
        local j = s % i + 1
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function read_context(drc)
    if not drc or type(drc.get_current_node) ~= "function" then return false end
    local ok, node = pcall(drc.get_current_node, drc)
    if not ok or type(node) ~= "table" or node.level ~= START_LEVEL then return false end

    local node_key
    if type(drc.get_current_node_key) == "function" then
        local key_ok, value = pcall(drc.get_current_node_key, drc)
        if key_ok then node_key = value end
    end
    -- The level key alone is insufficient: later/foreign graph nodes can reuse a
    -- level.  If the exact start-node identity is unavailable, fail closed.
    if node_key ~= START_NODE then return false end

    local run_id
    if type(drc.get_run_id) == "function" then
        local run_ok, value = pcall(drc.get_run_id, drc)
        if run_ok then run_id = value end
    end
    if run_id == nil then return false end
    return true, run_id, node
end

local function config()
    local settings = rawget(_G, "DeusShopSettings")
    return type(settings) == "table" and type(settings.shop_types) == "table"
        and settings.shop_types[START_LEVEL] or nil
end

function M.config_valid(cfg)
    return type(cfg) == "table"
        and type(cfg.power_up_count) == "number"
        and cfg.power_up_count >= 0
        and type(cfg.blessings) == "table"
        and policy.cost_percent(cfg.ct_cost_percent) ~= nil
        and policy.purchase_limit(cfg.ct_purchase_limit) ~= nil
end

function M.is_context(drc)
    local active, run_id, node = read_context(drc)
    if not active then return false end
    return true, run_id, node
end

function M.build_blessings(seed)
    local count = math.floor(tonumber(effective("ct_start_shrine_miracle_count")) or 0)
    if count <= 0 then return {} end
    local eligible = {}
    for _, key in ipairs(MIRACLE_KEYS) do
        if effective("ct_start_shrine_miracle_" .. key) then
            eligible[#eligible + 1] = key
        end
    end
    if #eligible == 0 then return {} end
    table.sort(eligible)
    seeded_shuffle(eligible, seed)
    local out = {}
    for i = 1, math.min(count, #eligible) do out[i] = eligible[i] end
    return out
end

function M.build_config(blessings_seed)
    local settings = rawget(_G, "DeusShopSettings")
    if type(settings) ~= "table" or type(settings.shop_types) ~= "table" then return nil end
    local boon_count = math.floor(tonumber(effective("ct_start_shrine_boon_count")) or 4)
    if boon_count < 0 then boon_count = 0 end
    local cost_percent = policy.cost_percent(effective("ct_start_shrine_cost_percent"))
    local purchase_limit = policy.purchase_limit(effective("ct_start_shrine_purchase_limit"))
    if not cost_percent or not purchase_limit then return nil end

    local cfg = settings.shop_types[START_LEVEL]
    if type(cfg) ~= "table" then
        cfg = {}
        settings.shop_types[START_LEVEL] = cfg
    end
    cfg.max_discounts = 0
    cfg.power_up_discount = 0.5
    cfg.twitch_icon = "twitch_icon_shrine"
    cfg.power_up_count = boon_count
    cfg.blessings = M.build_blessings(blessings_seed)
    cfg.ct_cost_percent = cost_percent
    cfg.ct_purchase_limit = purchase_limit
    return cfg
end

function M.prepare(drc)
    local active, run_id, node = read_context(drc)
    if not active then return nil end
    policy.begin_run(ledger, run_id)
    local seed = node.system_seeds and node.system_seeds.blessings or 0
    local cfg = M.build_config(seed)
    if not M.config_valid(cfg) then return nil end
    return cfg
end

function M.price(rarity, discount, name)
    local cfg = config()
    if not M.config_valid(cfg) then return nil end
    local exact = mod._ct_boon_pricing_policy
    local reader = mod._ct_effective_setting
    local exact_enabled = (reader and reader("ct_individual_boon_prices")
        or mod:get("ct_individual_boon_prices")) == true
    if exact_enabled and exact and type(exact.price) == "function" then
        return exact.price(name, rarity, discount, cfg.ct_cost_percent)
    end
    return policy.shop_cost(rawget(_G, "DeusCostSettings"), rarity, discount, cfg.ct_cost_percent)
end

function M.purchase_count(drc, peer_id, local_player_id)
    local active, run_id = M.is_context(drc)
    if not active then return nil end
    return policy.count(ledger, run_id, peer_id, local_player_id)
end

function M.can_purchase(drc, peer_id, local_player_id)
    local active, run_id = M.is_context(drc)
    local cfg = config()
    if not active or not M.config_valid(cfg) then return false end
    return policy.can_purchase(ledger, run_id, peer_id, local_player_id, cfg.ct_purchase_limit)
end

function M.record_purchase(drc, peer_id, local_player_id)
    local active, run_id = M.is_context(drc)
    if not active then return nil end
    return policy.record_purchase(ledger, run_id, peer_id, local_player_id)
end

-- Returns handled, bought, charged_cost. Once the exact synthetic start-node
-- identity is proven, every malformed policy/state branch rejects the purchase
-- instead of falling through to vanilla. Normal later shrines return handled=false.
function M.try_buy(drc, buyer, power_up, discount)
    local active, run_id = M.is_context(drc)
    if not active then return false end
    local cfg = config()
    local price = power_up and M.price(power_up.rarity, discount, power_up.name)
    if not M.config_valid(cfg) or not price or buyer == nil or type(power_up) ~= "table"
            or type(power_up.name) ~= "string" or power_up.name == ""
            or power_up.client_id == nil or type(drc.has_power_up) ~= "function" then
        report("purchase rejected: invalid synthetic policy/state (host=%s)",
            server_flag(drc))
        return true, false, price
    end
    if drc:has_power_up(buyer, power_up.client_id) then return true, false, price end

    local allowed, count = policy.can_purchase(ledger, run_id, buyer,
        REAL_PLAYER_LOCAL_ID, cfg.ct_purchase_limit)
    if not allowed then
        report("purchase rejected: limit reached run=%s buyer=%s count=%s limit=%s host=%s",
            tostring(run_id), tostring(buyer), tostring(count), tostring(cfg.ct_purchase_limit),
            server_flag(drc))
        return true, false, price
    end

    local run_state = drc._run_state
    if not run_state or type(run_state.get_player_profile) ~= "function"
            or type(run_state.get_player_soft_currency) ~= "function"
            or type(run_state.get_player_power_ups) ~= "function"
            or type(run_state.set_player_power_ups) ~= "function"
            or type(run_state.set_player_soft_currency) ~= "function"
            or type(run_state.get_bought_power_ups) ~= "function"
            or type(run_state.set_bought_power_ups) ~= "function"
            or type(run_state.is_server) ~= "function"
            or type(drc._add_coin_tracking_entry) ~= "function" then
        report("purchase rejected: run-state contract unavailable buyer=%s", tostring(buyer))
        return true, false, price
    end

    local profile_index, career_index = run_state:get_player_profile(buyer, REAL_PLAYER_LOCAL_ID)
    if profile_index == nil or career_index == nil then
        report("purchase rejected: player profile unavailable buyer=%s", tostring(buyer))
        return true, false, price
    end
    local coins = run_state:get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)
    if type(coins) ~= "number" or coins < price then return true, false, price end

    local power_ups = run_state:get_player_power_ups(buyer, REAL_PLAYER_LOCAL_ID,
        profile_index, career_index)
    if type(power_ups) ~= "table" or type(table.clone) ~= "function" then
        report("purchase rejected: player boon list unavailable buyer=%s", tostring(buyer))
        return true, false, price
    end
    local bought = run_state:get_bought_power_ups()
    if type(bought) ~= "table" then
        report("purchase rejected: bought-boon ledger unavailable buyer=%s", tostring(buyer))
        return true, false, price
    end
    local cloned = table.clone(power_ups, true)
    bought = table.clone(bought, true)
    table.insert(cloned, power_up)
    bought[#bought + 1] = power_up.name

    run_state:set_player_power_ups(buyer, REAL_PLAYER_LOCAL_ID,
        profile_index, career_index, cloned)
    run_state:set_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID, coins - price)

    local rarity = tostring(power_up.rarity)
    local normalized_discount = tonumber(discount) or 0
    local tracking_event = normalized_discount == 0 and rarity .. "_power_up"
        or rarity .. "_discounted_power_up"
    drc:_add_coin_tracking_entry(buyer, REAL_PLAYER_LOCAL_ID, -price, tracking_event)
    run_state:set_bought_power_ups(bought)

    local new_count = policy.record_purchase(ledger, run_id, buyer, REAL_PLAYER_LOCAL_ID)
    report("purchase accepted run=%s buyer=%s boon=%s price=%d count=%d limit=%d host=%s",
        tostring(run_id), tostring(buyer), tostring(power_up.name), price, new_count or -1,
        cfg.ct_purchase_limit, tostring(run_state:is_server()))
    return true, true, price
end

function M.decorate_shop(view)
    if not view or view._shop_type ~= START_LEVEL or not M.is_context(view._deus_run_controller) then return end
    local offers = view._shop_items and view._shop_items.power_ups
    if type(offers) ~= "table" then return end
    for i = 1, #offers do
        local entry = offers[i]
        local content = entry and entry.widget and entry.widget.content
        local price = entry and entry.power_up and M.price(entry.power_up.rarity,
            entry.discount, entry.power_up.name)
        if content then
            content.price_text = price and tostring(price) or "-"
            if not price and content.button_hotspot then content.button_hotspot.disable_button = true end
        end
    end
end

function M.enforce_limit(view)
    if not view or view._shop_type ~= START_LEVEL or not M.is_context(view._deus_run_controller) then return end
    local drc = view._deus_run_controller
    local peer = drc and drc.get_own_peer_id and drc:get_own_peer_id()
    local allowed = peer and M.can_purchase(drc, peer, REAL_PLAYER_LOCAL_ID)
    if allowed then return end
    local offers = view._shop_items and view._shop_items.power_ups
    if type(offers) ~= "table" then return end
    for i = 1, #offers do
        local hotspot = offers[i] and offers[i].widget and offers[i].widget.content
            and offers[i].widget.content.button_hotspot
        if hotspot then hotspot.disable_button = true end
    end
end

-- Price display, affordability, and telemetry all use this method. The charged
-- price in try_buy calls the same M.price helper, pinning display==charge.
mod:hook("DeusShopView", "_get_power_up_costs", function(func, self, rarity, discount)
    local vanilla = func(self, rarity, discount)
    if self and self._shop_type == START_LEVEL and M.is_context(self._deus_run_controller) then
        -- Once the exact synthetic identity is proven, malformed policy must
        -- never silently charge vanilla while the card shows a custom value.
        -- `math.huge` keeps affordability closed; decorate_shop renders "-".
        return M.price(rarity, discount) or math.huge
    end
    return vanilla
end)

mod:hook_safe("DeusShopView", "_update_shop_widgets", function(self)
    if mod._ct_boon_pricing_runtime then mod._ct_boon_pricing_runtime.enforce_shop(self) end
    M.enforce_limit(self)
end)

local view_guard_reports = 0
mod:hook("DeusShopView", "start", function(func, self, params)
    local drc = self and self._deus_run_controller
    local active = read_context(drc)
    if active then
        local prepared, cfg = pcall(M.prepare, drc)
        if not prepared then cfg = nil end
        if not M.config_valid(cfg) then
            local shared_state = self._shared_state
            if shared_state and shared_state.get_key then
                local state_key = shared_state:get_key("state")
                if self._is_server and shared_state.set_server then
                    shared_state:set_server(state_key, MAP_DECISION)
                end
                if shared_state.set_own then shared_state:set_own(state_key, MAP_DECISION) end
            end
            if view_guard_reports < 4 then
                view_guard_reports = view_guard_reports + 1
                report("start shrine view blocked: config unavailable; restored MAP_DECISION (peer=%s report=%d/4)",
                    self._is_server and "host" or "client", view_guard_reports)
            end
            return
        end
    end
    return func(self, params)
end)
M.view_guard_installed = true

mod:hook("GameModeMapDeus", "local_player_game_starts", function(func, self, player, loading_context)
    local drc = self._deus_run_controller
    local start_ok, at_start = pcall(function()
        return drc and drc.get_current_node_key and drc:get_current_node_key() == START_NODE
    end)
    if not start_ok then at_start = false end
    local prepared, cfg = true, nil
    if at_start then prepared, cfg = pcall(M.prepare, drc) end
    if not prepared then cfg = nil end

    func(self, player, loading_context)

    local ok, err = pcall(function()
        if not at_start or not self._is_server or not mod:get("ct_buy_starting_boons") then return end
        if not M.config_valid(cfg) then
            report("start shrine not published: host config validation failed; staying in MAP_DECISION")
            return
        end
        local run_id = drc.get_run_id and drc:get_run_id()
        if run_id ~= nil and M.fired_run_id == run_id then return end
        local shared_state = self._shared_state
        if not shared_state or not shared_state.set_server or not shared_state.get_key then
            report("start shrine not published: shared state unavailable; staying in MAP_DECISION")
            return
        end
        shared_state:set_server(shared_state:get_key("state"), SHOP)
        M.fired_run_id = run_id
        report("Buy Starting Boons applied: forced SHOP at run start (run_id=%s boons=%d miracles=%d cost=%d%% limit=%d)",
            tostring(run_id), cfg.power_up_count, #cfg.blessings,
            cfg.ct_cost_percent, cfg.ct_purchase_limit)
    end)
    if not ok then
        report("start-shrine trigger errored (%s); vanilla map decision unaffected", tostring(err))
    end
end)
M.prepared_before_vanilla = true

mod:command("ct_verify_start_shrine", "Report the Buy Starting Boons configuration and current purchase count", function()
    local cfg = config()
    mod:echo("[ct] Buy Starting Boons -- host controls whether the shrine appears:")
    mod:echo("%s", string.format("  toggle=%s  boons=%s  miracles=%s  cost=%s%%  limit=%s",
        tostring(effective("ct_buy_starting_boons")),
        tostring(effective("ct_start_shrine_boon_count")),
        tostring(effective("ct_start_shrine_miracle_count")),
        tostring(effective("ct_start_shrine_cost_percent")),
        tostring(effective("ct_start_shrine_purchase_limit"))))
    if M.config_valid(cfg) then
        mod:echo("%s", string.format("  registered: boons=%s blessings=[%s] cost=%s%% limit=%s PASS",
            tostring(cfg.power_up_count), table.concat(cfg.blessings, ","),
            tostring(cfg.ct_cost_percent), tostring(cfg.ct_purchase_limit)))
    else
        mod:echo("  registered start-shrine config: none yet (built at run start)")
    end
    local ok, count = pcall(function()
        local mechanism = Managers and Managers.mechanism
            and Managers.mechanism:game_mechanism()
        local drc = mechanism and mechanism.get_deus_run_controller
            and mechanism:get_deus_run_controller()
        local peer = drc and drc.get_own_peer_id and drc:get_own_peer_id()
        return peer and M.purchase_count(drc, peer, REAL_PLAYER_LOCAL_ID) or nil
    end)
    mod:echo("%s", string.format("  this hero's purchases this run: %s",
        ok and count ~= nil and tostring(count) or "not in the starting shrine"))
end)

function M.regression()
    if type(policy) ~= "table" or type(policy.shop_cost) ~= "function" then
        return "#458 REGRESSION: pure start-shrine policy missing"
    end
    if #MIRACLE_KEYS ~= 8 or type(M.build_blessings(12345)) ~= "table" then
        return "#458 REGRESSION: miracle policy missing or malformed"
    end
    if type(mod:get("ct_buy_starting_boons")) ~= "boolean" then
        return "#458 REGRESSION: Buy Starting Boons setting not registered"
    end
    if policy.cost_percent(mod:get("ct_start_shrine_cost_percent")) == nil
            or policy.purchase_limit(mod:get("ct_start_shrine_purchase_limit")) == nil then
        return "#458 REGRESSION: price or purchase-limit setting invalid"
    end
    if M.config_valid(nil) or M.config_valid({ power_up_count = 4, blessings = {} }) then
        return "#458 REGRESSION: config validator accepts incomplete policy"
    end
    if not M.prepared_before_vanilla or not M.view_guard_installed then
        return "#458 REGRESSION: prepare-before-sync or view guard missing"
    end
end

-- Compatibility names retained for existing diagnostics and external tests.
mod._ct_start_shrine_miracle_keys = MIRACLE_KEYS
mod._ct_build_start_shrine_blessings = M.build_blessings
mod._ct_build_start_shrine_config = M.build_config
mod._ct_start_shrine_config_valid = M.config_valid
mod._ct_prepare_start_shrine = M.prepare
mod._ct_start_shrine_prepared_before_vanilla = true
mod._ct_start_shrine_view_guard_installed = true

return M
