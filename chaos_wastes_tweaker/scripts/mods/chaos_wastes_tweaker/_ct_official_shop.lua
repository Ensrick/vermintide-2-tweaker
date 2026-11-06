-- Selective official shop integration for #458/#1146/#467.
-- Owns only previously-unowned card/telemetry seams and leaf module loading.
-- The official #426 owner remains the sole purchase-hook registration; its
-- existing gate must call _ct_official_shop_try_buy only AFTER wire validation.
-- The existing _create_ui_elements body calls _ct_official_shop_refresh.

local mod = get_mod("ct")
local root = "scripts/mods/chaos_wastes_tweaker/"
mod._ct_start_shrine_policy = mod:dofile(root .. "_ct_start_shrine_policy")
mod._ct_boon_pricing_policy = mod:dofile(root .. "_ct_boon_pricing_policy")
mod._ct_start_shrine_runtime = mod:dofile(root .. "_ct_start_shrine_runtime")
mod._ct_boon_pricing_runtime = mod:dofile(root .. "_ct_boon_pricing_runtime")

local start = mod._ct_start_shrine_runtime
local pricing = mod._ct_boon_pricing_runtime

local function pack(...)
    return { n = select("#", ...), ... }
end

function mod._ct_official_shop_try_buy(controller, buyer, power_up, discount)
    local handled, bought = start.try_buy(controller, buyer, power_up, discount)
    if handled then return true, bought end
    handled, bought = pricing.try_buy(controller, buyer, power_up, discount)
    return handled, bought
end

function mod._ct_official_shop_refresh(view)
    start.decorate_shop(view)
    pricing.enforce_shop(view)
    start.enforce_limit(view)
end

-- Neither pair exists in the official baseline. Do not copy the Dev purchase
-- owner: it also installs unrelated #466 bot-economy behavior.
mod:hook("DeusShopView", "_init_power_up_widget", function(func, self, widget,
        power_up, discount, current_value, max_value, profile_index, career_index, ...)
    local result = pack(func(self, widget, power_up, discount, current_value,
        max_value, profile_index, career_index, ...))
    local price = pricing.view_price(self, power_up, discount)
    if price and widget and widget.content then widget.content.price_text = tostring(price) end
    return unpack(result, 1, result.n)
end)

mod:hook("DeusShopView", "_on_power_up_bought", function(func, self, power_up, discount, ...)
    local result = pack(func(self, power_up, discount, ...))
    local rows = self and self._telemetry_data and self._telemetry_data.purchased_boons
    local price = pricing.view_price(self, power_up, discount)
    if price and type(rows) == "table" and type(rows[#rows]) == "table" then
        rows[#rows].cost = price
    end
    return unpack(result, 1, result.n)
end)

if type(mod._ct_rt_register) == "function" then
    mod._ct_rt_register("issue458_start_shrine_config", start.regression)
    mod._ct_rt_register("issue467_individual_boon_prices", pricing.regression)
    mod._ct_rt_register("issue1146_false_discount", function()
        local costs = { shop = { power_ups = { rare = 200 } } }
        if mod._ct_start_shrine_policy.shop_cost(costs, "rare", false, 100) ~= 200
                or mod._ct_boon_pricing_policy.price("barkskin", "rare", false, 100) ~= 225 then
            return "#1146 REGRESSION: false discount normalization drifted"
        end
    end)
end

return { start = start, pricing = pricing }
