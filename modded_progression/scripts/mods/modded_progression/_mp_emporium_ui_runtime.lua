-- #1684/#577: exact plain-SM presentation and action ownership.
-- Native store_purchase_popup._change_state enters before assigning its state;
-- the existing local exchange callback is synchronous. Settle after native
-- update returns, never from inside poll_result_on_enter.
local M = { CHECK_NAME = "issue1684_local_emporium_action_boundary" }
local TYPES = { frame = true, hat = true, skin = true, weapon_skin = true, weapon_pose = true }

local function capture(...) return select("#", ...), { ... } end
local function plain(value)
    return type(value) == "table" and getmetatable(value) == nil
end
local function only_sm(prices)
    if not plain(prices) then return false end
    local count = 0
    for currency, price in pairs(prices) do
        count = count + 1
        if currency ~= "SM" or type(price) ~= "number" or price ~= price
                or price < 0 or price == math.huge or price ~= math.floor(price) then
            return false
        end
    end
    return count == 1
end

-- All external readers are called within the installer's fail-closed pcall.
-- Identity is source-qualified: native stock and its shallow presentation
-- projection share the data and price tables. A stock rebuild invalidates it.
function M.resolve(deps, product)
    if not plain(product) or product.type ~= "item" or product.product_item ~= nil then
        return nil, "product_not_plain"
    end
    local settings = product.settings
    if settings ~= nil and (not plain(settings) or settings.acquire_disabled
            or settings.acquire_hidden or settings.part_of_bundle) then
        return nil, "acquisition_disabled"
    end
    local item = product.item
    if not plain(item) or type(item.key) ~= "string" or product.product_id ~= item.key then
        return nil, "product_identity"
    end
    local peddler = deps.get_peddler()
    if type(peddler) ~= "table" or rawget(peddler, "_stock_ready") ~= true
            or not deps.mirror_ready(rawget(peddler, "_backend_mirror")) then
        return nil, "stock_unavailable"
    end
    local stock, offer, count = rawget(peddler, "_peddler_stock"), nil, 0
    if not plain(stock) then return nil, "stock_unavailable" end
    for _, candidate in ipairs(stock) do
        if plain(candidate) and candidate.key == item.key then
            offer, count = candidate, count + 1
        end
    end
    if count ~= 1 or item.data ~= offer.data
            or item.current_prices ~= offer.current_prices
            or item.regular_prices ~= offer.regular_prices then
        return nil, "stale_product"
    end
    local data = offer.data
    if not plain(data) or not TYPES[data.item_type] or offer.dlc_name
            or offer.steam_itemdefid or item.dlc_name or item.steam_itemdefid
            or data.dlc_name or data.steam_itemdefid or data.bundle ~= nil
            or (data.bundle_contains ~= nil
                and (not plain(data.bundle_contains) or next(data.bundle_contains) ~= nil))
            or not only_sm(offer.current_prices) or not only_sm(offer.regular_prices) then
        return nil, "offer_not_plain_sm"
    end
    local expiry = offer.end_time
    if expiry ~= nil then
        local now = deps.clock()
        if type(expiry) ~= "number" or expiry ~= expiry or expiry == math.huge
                or type(now) ~= "number" or now ~= now or expiry / 1000 <= now then
            return nil, "offer_expired"
        end
    end
    local dlc_owned = data.required_dlc == nil or deps.dlc_owned(data.required_dlc) == true
    local projected = deps.policy.project_offer(offer, "SM", deps.local_owned)
    local plan, reason = deps.policy.validate({
        offer = projected, currency = "SM", expected_price = offer.current_prices.SM,
        balance = deps.balance(), owned = deps.local_owned(item.key),
        available = true, dlc_owned = dlc_owned,
    })
    if not plan then return nil, reason end
    return plan, peddler, offer
end

function M.install(mod, deps)
    assert(type(mod) == "table" and type(mod.hook) == "function", "MP hook owner missing")
    assert(type(deps) == "table" and type(deps.policy) == "table", "MP offer policy missing")
    for _, name in ipairs({ "is_modded_realm", "get_peddler", "mirror_ready",
        "clock", "dlc_owned", "local_owned", "balance", "local_exchange" }) do
        assert(type(deps[name]) == "function", "MP Emporium reader missing: " .. name)
    end
    local authorization, pending, busy, processing, requesting = nil, nil, false, nil, false
    local warned = {}
    local function deny(stage, reason)
        if not warned[stage] then
            warned[stage] = true
            if type(deps.print_log) == "function" then
                pcall(deps.print_log,
                    "[mp:1684] emporium_denied stage=%s reason=%s backend=none",
                    stage, tostring(reason))
            end
        end
    end
    local function realm()
        if pending then
            local owner = pending.owner
            local state = rawget(owner, "_state")
            if rawget(owner, "_destroyed") or state == "exit" or state == "aborted" then
                pending = nil
            end
        end
        local ok, value = pcall(deps.is_modded_realm)
        if ok and type(value) == "boolean" then return value end
        return nil
    end
    local function resolve(product)
        local ok, plan, peddler, offer = pcall(M.resolve, deps, product)
        if not ok then return nil, "offer_reader_failed" end
        return plan, peddler, offer
    end
    local function authorized(product)
        if not authorization or authorization.product ~= product or busy then return nil end
        local plan, peddler, offer = resolve(product)
        if not plan or peddler ~= authorization.peddler or offer ~= authorization.offer
                or plan.price ~= authorization.price then
            return nil
        end
        return plan, peddler, offer
    end
    local function reject(self, stage, reason)
        deny(stage, reason)
        if type(self) == "table" and self ~= processing then
            rawset(self, "_mp1684_emporium_rejected", true)
        end
    end

    mod:hook("StoreWindowItemPreview", "_set_unlock_button_states",
        function(func, self, ...)
            local context = realm()
            if context == false then return func(self, ...) end
            local already_owned, can_afford, dlc_unlocked,
                acquire_disabled, acquire_hidden, owns_required_dlc = ...
            authorization = nil
            local n, values = capture(func(self, ...))
            local product = type(self) == "table" and rawget(self, "_selected_product")
            local plan, peddler, offer
            if context == true and already_owned == false and can_afford == true
                    and dlc_unlocked == true and not acquire_disabled and not acquire_hidden
                    and owns_required_dlc == true and not pending and not busy then
                plan, peddler, offer = resolve(product)
            end
            local widgets = type(self) == "table" and rawget(self, "_top_widgets_by_name")
            local button = type(widgets) == "table" and rawget(widgets, "unlock_button")
            local content = type(button) == "table" and rawget(button, "content")
            local hotspot = type(content) == "table" and rawget(content, "button_hotspot")
            if type(hotspot) == "table" then
                rawset(hotspot, "disable_button", plan == nil)
                if plan then
                    authorization = { product = product, peddler = peddler,
                        offer = offer, price = plan.price }
                end
            end
            return unpack(values, 1, n)
        end)

    mod:hook("HeroViewStateStore", "product_purchase_request",
        function(func, self, product, ...)
            local context = realm()
            if context == false then return func(self, product, ...) end
            if context ~= true or pending or busy or requesting or not authorized(product) then
                deny("request", "product_not_authorized")
                return nil
            end
            -- This exact plain item has no native platform/DLC branch.
            requesting = true
            local n, values = capture(pcall(func, self, product, ...))
            requesting = false
            if not values[1] then error(values[2], 0) end
            return unpack(values, 2, n)
        end)

    mod:hook("StoreItemPurchasePopup", "_create_ui_elements",
        function(func, self, ...)
            local context = realm()
            if context == false then return func(self, ...) end
            local n, values = capture(func(self, ...))
            local widgets = type(self) == "table" and rawget(self, "_widgets_by_name")
            local button = type(widgets) == "table" and rawget(widgets, "purchase_button")
            local content = type(button) == "table" and rawget(button, "content")
            local hotspot = type(content) == "table" and rawget(content, "button_hotspot")
            local allowed = context == true and not pending and not busy
                and authorized(type(self) == "table" and rawget(self, "_product"))
            if type(hotspot) == "table" then rawset(hotspot, "disable_button", not allowed) end
            return unpack(values, 1, n)
        end)

    mod:hook("StoreItemPurchasePopup", "_poll_result_on_enter",
        function(func, self, ...)
            local context = realm()
            if context == false then return func(self, ...) end
            if pending and pending.owner == self then return nil end
            local product = type(self) == "table" and rawget(self, "_product")
            if context ~= true or pending or busy or not authorized(product) then
                reject(self, "action", "product_not_authorized")
                return nil
            end
            pending = { owner = self, product = product, authorization = authorization }
            return nil
        end)

    mod:hook("StoreItemPurchasePopup", "update",
        function(func, self, ...)
            local context = realm()
            local owns_pending = pending and pending.owner == self
            local rejected = type(self) == "table" and rawget(self, "_mp1684_emporium_rejected")
            if context == false and not owns_pending and not rejected then return func(self, ...) end
            local n, values = capture(pcall(func, self, ...))
            if not values[1] then
                if pending and pending.owner == self then pending = nil end
                if type(self) == "table" then rawset(self, "_mp1684_emporium_rejected", nil) end
                error(values[2], 0)
            end
            if not busy then
                local row = pending and pending.owner == self and pending
                rejected = type(self) == "table" and rawget(self, "_mp1684_emporium_rejected")
                if row or rejected then
                    if row then pending = nil end
                    rawset(self, "_mp1684_emporium_rejected", nil)
                    local success, answered = false, false
                    local plan, peddler
                    if row and realm() == true and authorization == row.authorization
                            and rawget(self, "_product") == row.product
                            and rawget(self, "_state") == "poll_result"
                            and not rawget(self, "_destroyed") then
                        plan, peddler = authorized(row.product)
                    end
                    if plan then
                        busy, processing = true, self
                        local ok = pcall(deps.local_exchange, peddler, plan.item_key,
                            plan.price, function(result)
                                if not answered then answered, success = true, result == true end
                            end)
                        busy, processing = false, nil
                        success = ok and answered and success
                        authorization = nil -- successful or uncertain action cannot be replayed
                    end
                    if not rawget(self, "_destroyed") then
                        -- Deliberately do not call the native success callback,
                        -- which emits an official purchase telemetry event.
                        self:_change_state(success and "approved" or "exit")
                    end
                end
            end
            return unpack(values, 2, n)
        end)

    if type(deps.rt_register) == "function" then
        deps.rt_register(M.CHECK_NAME, function()
            return M.runtime_check(deps.policy)
        end)
    end
end

-- Detached installed-callback smoke. No live catalog, ledger, UI or account
-- interface is consulted; the transaction is an explicit test-local stub.
function M.runtime_check(policy)
    local hooks, purchases = {}, 0
    local item = { key = "mp1684_smoke", type = "item",
        data = { item_type = "hat", slot_type = "hat" },
        current_prices = { SM = 2 }, regular_prices = { SM = 2 } }
    local stock = { _stock_ready = true, _backend_mirror = {},
        _peddler_stock = { item } }
    local product = { type = "item", product_id = item.key, item = item }
    M.install({ hook = function(_, class, method, fn) hooks[class .. "." .. method] = fn end }, {
        policy = policy, is_modded_realm = function() return true end,
        get_peddler = function() return stock end, mirror_ready = function() return true end,
        clock = function() return 1 end, dlc_owned = function() return true end,
        local_owned = function() return false end, balance = function() return 3 end,
        local_exchange = function(_, key, price, callback)
            if key ~= item.key or price ~= 2 then error("wrong local offer") end
            purchases = purchases + 1
            callback(true)
        end,
    })
    local window = { _selected_product = product,
        _top_widgets_by_name = { unlock_button = { content = { button_hotspot = {} } } } }
    hooks["StoreWindowItemPreview._set_unlock_button_states"](
        function() end, window, false, true, true, false, false, true)
    if window._top_widgets_by_name.unlock_button.content.button_hotspot.disable_button ~= false then
        return "plain local offer was not enabled"
    end
    local popup = { _product = product, _state = "popup",
        _change_state = function(self, state) self._state = state end }
    hooks["StoreItemPurchasePopup._poll_result_on_enter"](function() error("native purchase") end, popup)
    if purchases ~= 0 then return "local action ran before native state assignment" end
    popup._state = "poll_result"
    hooks["StoreItemPurchasePopup.update"](function() end, popup)
    hooks["StoreItemPurchasePopup.update"](function() end, popup)
    if purchases ~= 1 or popup._state ~= "approved" then
        return "local action did not settle exactly once after native update"
    end
end

return M
