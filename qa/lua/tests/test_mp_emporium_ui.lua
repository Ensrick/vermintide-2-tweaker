return function(H, repo_root, runtime_path, entry_source)
local root = repo_root .. "/modded_progression/scripts/mods/modded_progression/"
local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local value = f:read("*a"); f:close()
    return (value:gsub("\r\n", "\n"))
end
local entry = entry_source or assert(read(root .. "modded_progression.lua"))
local Policy = dofile(root .. "_mp_emporium_policy.lua")
local protection_reads, protection_writes = 0, 0
local protection = setmetatable({}, {
    __index = function() protection_reads = protection_reads + 1; error("protection read") end,
    __newindex = function() protection_writes = protection_writes + 1; error("protection write") end,
})
local runtime_environment = setmetatable({
    GameSettingsDevelopment = protection, script_data = protection, MODDED_REALM = true,
}, { __index = _G })
runtime_environment._G = runtime_environment
local runtime_chunk = assert(loadfile(runtime_path or (root .. "_mp_emporium_ui_runtime.lua")))
setfenv(runtime_chunk, runtime_environment)
local Runtime = runtime_chunk()
local PREVIEW = "StoreWindowItemPreview._set_unlock_button_states"
local REQUEST = "HeroViewStateStore.product_purchase_request"
local CREATE = "StoreItemPurchasePopup._create_ui_elements"
local ENTER = "StoreItemPurchasePopup._poll_result_on_enter"
local UPDATE = "StoreItemPurchasePopup.update"
local function pack(...) return { n = select("#", ...), ... } end
local transaction = assert(entry:match("(local function _mp577_local_exchange%b().-\nend)\n\nmod:hook"),
    "shared local exchange missing")
local transaction_factory = assert(loadstring(
    "local Dailies, Emporium, _mp577_ui, _mp577_mirror_ready, _mp577_sync_overlay, mod, Managers, printf = ...\n"
        .. transaction .. "\nreturn _mp577_local_exchange", "=mp1684_actual_local_exchange"))
setfenv(transaction_factory, runtime_environment)

local function fixture()
    local f = { realm = true, hooks = {}, storage = {}, exchanges = 0,
        native_writes = 0, native_requests = 0, logs = {}, checks = {}, states = {} }
    local mod = {
        get = function(_, key) return f.storage[key] end,
        set = function(_, key, value)
            if f.fail_write then f.fail_write = false; error("injected persistence failure") end
            f.storage[key] = value
        end,
    }
    local names = {
        "daily_collect_grimoires", "daily_collect_loot_die", "daily_collect_painting_scrap",
        "daily_collect_tomes", "daily_complete_levels_hero_bright_wizard",
        "daily_complete_levels_hero_dwarf_ranger", "daily_complete_levels_hero_empire_soldier",
        "daily_complete_levels_hero_witch_hunter", "daily_complete_levels_hero_wood_elf",
        "daily_complete_quickplay_missions", "daily_kill_bosses", "daily_kill_critters",
        "daily_kill_elites", "daily_score_headshots",
    }
    local templates, settings = { quests = {} }, { stat_mappings = {} }
    for _, name in ipairs(names) do
        settings[name] = 2
        templates.quests[name] = { stat_mappings = { { qualifying_event = true } } }
    end
    local env = setmetatable({
        get_mod = function() return mod end, QuestSettings = settings,
        require = function(name)
            assert(name == "scripts/managers/quest/quest_templates")
            return templates
        end, printf = function() end,
    }, { __index = _G })
    env._G = env
    local chunk = assert(loadfile(root .. "mp_dailies.lua"))
    setfenv(chunk, env)
    f.D = chunk()
    assert(f.D.credit(100))
    f.item = { key = "hat_alpha", type = "item",
        data = { item_type = "hat", slot_type = "hat" },
        current_prices = { SM = 20 }, regular_prices = { SM = 20 } }
    f.peddler = { _stock_ready = true, _peddler_stock = { f.item },
        _backend_mirror = { ready = function() return true end,
            request_queue = function()
                f.native_writes = f.native_writes + 1
                error("real backend touched")
            end } }
    f.product = { type = "item", product_id = "hat_alpha",
        item = Policy.project_offer(f.item, "SM", function() return false end) }
    f.preview = { _selected_product = f.product,
        _top_widgets_by_name = { unlock_button = { content = { button_hotspot = {} } } } }
    f.popup = { _product = f.product, _state = "popup",
        _widgets_by_name = { purchase_button = { content = { button_hotspot = {} } } },
        _change_state = function(self, state)
            f.states[#f.states + 1] = state
            self._state = state
        end }
    local function local_owned(key) return f.D.emporium_unlocked(key) end
    local real_exchange = transaction_factory(f.D, Policy, { local_owned = local_owned },
        function(mirror) return mirror:ready() == true end,
        function() return true end, mod, { unlock = { is_dlc_unlocked = function() return true end } },
        function() end)
    f.deps = {
        policy = Policy, is_modded_realm = function()
            if f.throw_realm then error("private realm failure") end
            return f.realm
        end,
        get_peddler = function() return f.peddler end,
        mirror_ready = function(mirror) return mirror:ready() == true end,
        clock = function() return 100 end, dlc_owned = function() return f.dlc ~= false end,
        local_owned = local_owned, balance = f.D.balance,
        local_exchange = function(...)
            f.exchanges = f.exchanges + 1
            return real_exchange(...)
        end,
        print_log = function(fmt, ...) f.logs[#f.logs + 1] = string.format(fmt, ...) end,
        rt_register = function(name, fn) f.checks[name] = fn end,
    }
    Runtime.install({ hook = function(_, class, method, fn)
        local key = class .. "." .. method
        assert(f.hooks[key] == nil, "duplicate hook")
        f.hooks[key] = fn
    end }, f.deps)
    function f:authorize(...)
        local args = pack(...)
        if args.n == 0 then args = pack(false, true, true, false, false, true) end
        return self.hooks[PREVIEW](function() return 1, nil, 3, nil end,
            self.preview, unpack(args, 1, args.n))
    end
    function f:request()
        return self.hooks[REQUEST](function(_, product)
            H.equal(product, self.product)
            self.native_requests = self.native_requests + 1
        end, {}, self.product)
    end
    function f:enter()
        return self.hooks[ENTER](function()
            self.native_writes = self.native_writes + 1
            error("native currency/platform action entered")
        end, self.popup)
    end
    function f:update(native)
        return self.hooks[UPDATE](native or function() end, self.popup)
    end
    function f:purchase()
        self:enter()
        self.popup._state = "poll_result" -- native assigns this AFTER on_enter
        self:update()
    end
    return f
end

H.test("MP #1684 Emporium installs five owned singleton seams and detached smoke", function()
    local f = fixture()
    local count = 0
    for _ in pairs(f.hooks) do count = count + 1 end
    H.equal(count, 5)
    H.equal(f.checks[Runtime.CHECK_NAME](), nil)
    H.equal(f.D.balance(), 100)
end)

for _, key in ipairs({ PREVIEW, REQUEST, CREATE, ENTER, UPDATE }) do
    local method = key
    H.test("MP #1684 Emporium official tuple and exception passthrough " .. method, function()
        local f = fixture()
        f.realm = false
        local self, tail, seen = {}, {}, nil
        local result = pack(f.hooks[method](function(...)
            seen = pack(...)
            return tail, nil, 3, nil
        end, self, "a", nil, tail, nil))
        H.equal(seen.n, 5)
        H.equal(seen[1], self)
        H.equal(seen[2], "a")
        H.equal(seen[4], tail)
        H.equal(result.n, 4)
        H.equal(result[1], tail)
        H.equal(result[3], 3)
        local token = {}
        local ok, err = pcall(f.hooks[method], function() error(token) end, self)
        H.equal(ok, false)
        H.equal(err, token)
        H.equal(f.exchanges + f.native_writes, 0)
    end)
end

H.test("MP #1684 Emporium validates then purchases through actual local ledger once", function()
    local f = fixture()
    local result = pack(f:authorize())
    H.equal(result.n, 4)
    H.equal(result[3], 3)
    H.equal(f.preview._top_widgets_by_name.unlock_button.content.button_hotspot.disable_button, false)
    f:request()
    H.equal(f.native_requests, 1)
    f.hooks[CREATE](function() return 1, nil, 3 end, f.popup)
    H.equal(f.popup._widgets_by_name.purchase_button.content.button_hotspot.disable_button, false)
    f:enter()
    H.equal(f.exchanges, 0)
    f.popup._state = "poll_result"
    f:update()
    f:update()
    H.equal(f.exchanges, 1)
    H.equal(f.native_writes, 0)
    H.equal(f.D.balance(), 80)
    H.equal(f.D.emporium_unlocked("hat_alpha"), true)
    H.equal(f.popup._state, "approved")
end)

for _, case in ipairs({
    { "platform", function(f) f.item.steam_itemdefid = 42 end },
    { "dlc", function(f) f.item.dlc_name = "dlc" end },
    { "bundle", function(f) f.item.data.bundle_contains = { "child" } end },
    { "mixed", function(f) f.item.current_prices.VS = 1 end },
    { "nonSM", function(f) f.item.current_prices = { VS = 1 } end },
    { "foreign", function(f) f.peddler._peddler_stock = {} end },
    { "not ready", function(f) f.peddler._stock_ready = false end },
    { "hidden", function(f) f.product.settings = { acquire_hidden = true } end },
    { "disabled", function(f) f.product.settings = { acquire_disabled = true } end },
    { "required DLC", function(f) f.item.data.required_dlc = "needed"; f.dlc = false end },
    { "unaffordable", function(f) f.D.spend(100) end },
    { "owned", function(f) f.deps.local_owned = function() return true end end },
    { "expired", function(f) f.item.end_time = 99999 end },
    { "malformed", function(f) f.product.item = false end },
    { "product item", function(f) f.product.product_item = f.item end },
    { "duplicate key", function(f) f.peddler._peddler_stock[2] = f.item end },
}) do
    local spec = case
    H.test("MP #1684 Emporium denies " .. spec[1] .. " at presentation and action", function()
        local f = fixture()
        spec[2](f)
        local before = f.D.balance()
        f:authorize()
        H.equal(f.preview._top_widgets_by_name.unlock_button.content.button_hotspot.disable_button, true)
        f:request()
        f:purchase()
        H.equal(f.native_requests + f.native_writes + f.exchanges, 0)
        H.equal(f.D.balance(), before)
        H.equal(f.popup._state, "exit")
    end)
end

for index = 1, 6 do
    local slot = index
    H.test("MP #1684 Emporium keeps native acquisition gate " .. slot, function()
        local f = fixture()
        local args = { false, true, true, false, false, true }
        args[slot] = not args[slot]
        f:authorize(unpack(args, 1, 6))
        H.equal(f.preview._top_widgets_by_name.unlock_button.content.button_hotspot.disable_button, true)
        f:purchase()
        H.equal(f.exchanges + f.native_writes, 0)
    end)
end

for _, change in ipairs({
    { "price", function(f) f.item.current_prices.SM = 21 end },
    { "stock identity", function(f)
        local copy = {}
        for k, v in pairs(f.item) do copy[k] = v end
        f.peddler._peddler_stock[1] = copy
    end },
    { "ownership", function(f) f.deps.local_owned = function() return true end end },
    { "funds", function(f) f.D.spend(100) end },
}) do
    local spec = change
    H.test("MP #1684 Emporium revalidates " .. spec[1] .. " after preview", function()
        local f = fixture()
        f:authorize()
        spec[2](f)
        f:purchase()
        H.equal(f.exchanges + f.native_writes, 0)
        H.equal(f.popup._state, "exit")
    end)
end

H.test("MP #1684 Emporium pending input cannot double-buy or change approved state back", function()
    local f = fixture()
    f:authorize()
    f:enter()
    f:enter()
    f:request()
    H.equal(f.native_requests, 0)
    f.popup._state = "poll_result"
    f:update()
    H.equal(f.exchanges, 1)
    H.equal(f.D.balance(), 80)
    H.equal(f.popup._state, "approved")
end)

H.test("MP #1684 Emporium persistence failure exits without debit then permits new preview", function()
    local f = fixture()
    f:authorize()
    f.fail_write = true
    f:purchase()
    H.equal(f.D.balance(), 100)
    H.equal(f.D.emporium_unlocked("hat_alpha"), false)
    H.equal(f.popup._state, "exit")
    f:authorize()
    f:purchase()
    H.equal(f.D.balance(), 80)
end)

H.test("MP #1684 Emporium throwing or missing local callback cannot leave polling stuck", function()
    for _, mode in ipairs({ "throw", "silent" }) do
        local f = fixture()
        f.deps.local_exchange = function()
            if mode == "throw" then error("local transaction failed") end
        end
        f:authorize()
        f:purchase()
        H.equal(f.popup._state, "exit")
        H.equal(f.D.balance(), 100)
        H.equal(f.native_writes, 0)
    end
end)

H.test("MP #1684 Emporium reentrant request and poll cannot replay the local transaction", function()
    local f = fixture()
    local real = f.deps.local_exchange
    f.deps.local_exchange = function(...)
        f:request()
        f:enter()
        f:update()
        return real(...)
    end
    f:authorize()
    f:purchase()
    H.equal(f.exchanges, 1)
    H.equal(f.native_requests, 0)
    H.equal(f.D.balance(), 80)
    H.equal(f.popup._state, "approved")
end)


H.test("MP #1684 Emporium destroyed pending popup cannot lock later purchases", function()
    local f = fixture()
    f:authorize()
    f:enter()
    f.popup._destroyed = true
    f:authorize()
    H.equal(f.preview._top_widgets_by_name.unlock_button.content.button_hotspot.disable_button, false)
    f.popup = { _product = f.product, _state = "popup",
        _change_state = function(self, state) self._state = state end }
    f:purchase()
    H.equal(f.D.balance(), 80)
    H.equal(f.popup._state, "approved")
end)

H.test("MP #1684 Emporium rejected competing popup cannot consume pending owner", function()
    local f = fixture()
    f:authorize()
    f:enter()
    local other = { _product = f.product, _state = "poll_result",
        _change_state = function(self, state) self._state = state end }
    f.hooks[ENTER](function() error("native action entered") end, other)
    f.hooks[UPDATE](function() end, other)
    H.equal(other._state, "exit")
    H.equal(f.exchanges, 0)
    f.popup._state = "poll_result"
    f:update()
    H.equal(f.exchanges, 1)
    H.equal(f.popup._state, "approved")
end)

H.test("MP #1684 Emporium exception after committed grant cannot replay debit", function()
    local f = fixture()
    local real = f.deps.local_exchange
    f.deps.local_exchange = function(...)
        real(...)
        error("injected post-commit overlay failure")
    end
    f:authorize()
    f:purchase()
    H.equal(f.D.balance(), 80)
    H.equal(f.D.emporium_unlocked("hat_alpha"), true)
    H.equal(f.popup._state, "exit")
    f:authorize()
    f:purchase()
    H.equal(f.D.balance(), 80)
    H.equal(f.exchanges, 1)
end)

H.test("MP #1684 Emporium request exceptions restore reentrancy ownership", function()
    local f = fixture()
    f:authorize()
    local token = {}
    local ok, err = pcall(f.hooks[REQUEST], function() error(token) end, {}, f.product)
    H.equal(ok, false)
    H.equal(err, token)
    f:request()
    H.equal(f.native_requests, 1)
end)

H.test("MP #1684 Emporium update exception cancels pending before rethrow", function()
    local f = fixture()
    f:authorize()
    f:enter()
    local token = {}
    local ok, err = pcall(function() f:update(function() error(token) end) end)
    H.equal(ok, false)
    H.equal(err, token)
    H.equal(f.exchanges, 0)
    f:authorize()
    f:purchase()
    H.equal(f.exchanges, 1)
end)

for _, invalid in ipairs({ "malformed", "throw" }) do
    local kind = invalid
    H.test("MP #1684 Emporium " .. kind .. " realm cannot authorize any action", function()
        local f = fixture()
        f.realm, f.throw_realm = "false", kind == "throw"
        f:authorize()
        f:request()
        f:purchase()
        H.equal(f.exchanges + f.native_writes + f.native_requests, 0)
        H.equal(f.popup._state, "exit")
    end)
end

H.test("MP #1684 Emporium unreadable readers fail closed", function()
    for _, key in ipairs({ "get_peddler", "mirror_ready", "balance", "local_owned" }) do
        local f = fixture()
        f.deps[key] = function() error("private reader failure") end
        f:authorize()
        f:purchase()
        H.equal(f.exchanges + f.native_writes, 0)
        H.equal(f.popup._state, "exit")
    end
end)

H.test("MP #1684 Emporium realm changes cancel adapter-owned pending work", function()
    local f = fixture()
    f:authorize()
    f:enter()
    f.popup._state, f.realm = "poll_result", false
    f:update()
    H.equal(f.popup._state, "exit")
    H.equal(f.exchanges + f.native_writes, 0)
end)


local install_expression = assert(entry:match("(EmporiumUi%.install%b())"),
    "entry-to-Emporium UI owner install missing")
local wiring = assert(loadstring(
    "local EmporiumUi, mod, Emporium, _is_mp_realm, Managers, _mp577_mirror_ready, _mp577_ui, Dailies, _mp577_local_exchange, _rt_register, printf, rawget, _G, type, os = ...\nreturn "
        .. install_expression, "=mp1684_actual_emporium_entry"))
for _, case in ipairs({
    { name = "native modded", native = true, legacy = false, allowed = false },
    { name = "native official", native = false, legacy = true, allowed = true },
    { name = "malformed native", native = "false", legacy = false, allowed = false },
    { name = "legacy modded", legacy = true, allowed = false },
    { name = "legacy official", legacy = false, allowed = true },
}) do
    local spec = case
    H.test("MP #1684 Emporium actual entry respects " .. spec.name .. " authority", function()
        local f, hooks, legacy = fixture(), {}, 0
        wiring(Runtime, { hook = function(_, class, method, fn)
            hooks[class .. "." .. method] = fn
        end }, Policy, function() legacy = legacy + 1; return spec.legacy end,
            { backend = { _interfaces = { peddler = f.peddler } },
                unlock = { is_dlc_unlocked = function() return true end } },
            f.deps.mirror_ready, { local_owned = f.deps.local_owned }, f.D,
            f.deps.local_exchange, function() end, function() end, rawget,
            { MODDED_REALM = spec.native }, type, { time = function() return 100 end })
        hooks[REQUEST](function() f.native_requests = f.native_requests + 1 end, {}, f.product)
        H.equal(f.native_requests, spec.allowed and 1 or 0)
        H.equal(legacy, spec.native == nil and 1 or 0)
        H.equal(f.exchanges + f.native_writes, 0)
    end)
end


H.test("MP #1684 Emporium preserves owned required-DLC tuple through actual local owner", function()
    local f = fixture()
    f.item.data.required_dlc = "owned_dlc"
    f:authorize()
    f:purchase()
    H.equal(f.D.balance(), 80)
    H.equal(f.popup._state, "approved")
    H.equal(f.exchanges, 1)
    H.equal(f.native_writes, 0)
end)

H.test("MP #1684 Emporium revalidates live stock again after pending action entry", function()
    local f = fixture()
    f:authorize()
    f:enter()
    f.item.current_prices.SM = 21
    f.popup._state = "poll_result"
    f:update()
    H.equal(f.exchanges, 0)
    H.equal(f.D.balance(), 100)
    H.equal(f.popup._state, "exit")
end)

H.test("MP #1684 Emporium never reads or writes account protection", function()
    local f = fixture()
    f:authorize()
    f:purchase()
    H.equal(protection_reads, 0)
    H.equal(protection_writes, 0)
    H.equal(rawget(runtime_environment, "MODDED_REALM"), true)
    H.equal(rawget(runtime_environment, "GameSettingsDevelopment"), protection)
    H.equal(rawget(runtime_environment, "script_data"), protection)
end)

-- Optional exact native semantic paths. Rendering/animation are explicit stubs;
-- branch selection, input route, state ordering and writer reachability are native.
local native_root = repo_root .. "/../Vermintide-2-Source-Code/"
local popup_source = read(native_root .. "scripts/ui/views/store_item_purchase_popup.lua")
local request_source = read(native_root .. "scripts/ui/views/hero_view/states/hero_view_state_store.lua")
local function native_method(source, class, name, environment)
    local needle = class .. "%." .. name .. " = (function.-)\n\n" .. class .. "%."
    local chunk = assert(loadstring("return " .. assert(source:match(needle)), "=mp1684_native_" .. name))
    setfenv(chunk, environment)
    return chunk()
end
for _, input in ipairs({ { "desktop", false }, { "controller", false },
    { "desktop", true }, { "controller", true } }) do
    local device, unsafe = input[1], input[2]
    H.test_if(popup_source ~= nil and request_source ~= nil,
        "MP #1684 exact native " .. device .. (unsafe and " rejects stale mixed offer" or " completes local purchase after state assignment"), function()
        local f = fixture()
        f:authorize()
        if unsafe then
            f.item.current_prices.VS, f.item.regular_prices.VS = 1, 1
            f.popup._widgets_by_name.purchase_button.content.button_hotspot.disable_button = true
        end
        local environment = {
            print = function() end,
            UIWidgetUtils = { animate_default_button = function() end },
        }
        local update = native_method(popup_source, "StoreItemPurchasePopup", "update", environment)
        local change = native_method(popup_source, "StoreItemPurchasePopup", "_change_state", environment)
        local popup_update = native_method(popup_source, "StoreItemPurchasePopup", "_popup_update", environment)
        local popup = f.popup
        popup._menu_input_description, popup._render_settings = {}, {}
        popup._widgets_by_name.close_button = {}
        popup._update_animations, popup._draw = function() end, function() end
        popup._play_sound = function() end
        popup._change_state = change
        popup._popup_update = popup_update
        popup._popup_on_exit = function() end
        popup._approved_on_enter = function() end
        popup._poll_result_on_enter = function(self)
            return f.hooks[ENTER](function() error("native purchase entered") end, self)
        end
        popup._is_button_hover_enter = function() return false end
        popup._is_button_pressed = function(_, widget)
            return device == "desktop" and widget == popup._widgets_by_name.purchase_button
        end
        local service = { get = function(_, key)
            return device == "controller" and key == "confirm_press"
        end }
        f.hooks[UPDATE](update, popup, service, 0.1, 1)
        H.equal(popup._state, unsafe and "exit" or "approved", "settlement must survive native state ordering")
        H.equal(f.D.balance(), unsafe and 100 or 80)
        H.equal(f.exchanges, unsafe and 0 or 1)
        H.equal(f.native_writes, 0)
    end, "optional native source checkout unavailable")
end

H.test_if(request_source ~= nil,
    "MP #1684 exact native product request platform writers are guarded", function()
    local f, steam, storepage, created = fixture(), 0, 0, 0
    local env = { Managers = { steam = { request_purchase_item = function() steam = steam + 1 end } },
        StoreItemPurchasePopup = { new = function() created = created + 1; return f.popup end } }
    local native = native_method(request_source, "HeroViewStateStore", "product_purchase_request", env)
    local owner = { _show_storepage = function() storepage = storepage + 1 end,
        block_input = function() end }
    f:authorize()
    f.hooks[REQUEST](native, owner, f.product)
    H.equal(created, 1)
    local platform = { type = "item", item = { steam_itemdefid = 42 } }
    -- Positive isolated native control proves the Steam producer is connected.
    native(owner, platform)
    H.equal(steam, 1)
    f.hooks[REQUEST](native, owner, platform)
    H.equal(steam, 1)
    local dlc = { type = "dlc", dlc_settings = { dlc_name = "paid" } }
    native(owner, dlc)
    H.equal(storepage, 1)
    f.hooks[REQUEST](native, owner, dlc)
    H.equal(storepage, 1)
    H.equal(f.exchanges, 0)
end, "optional native source checkout unavailable")

local preview_source = read(native_root
    .. "scripts/ui/views/hero_view/windows/store/store_window_item_preview.lua")
H.test_if(preview_source ~= nil and popup_source ~= nil,
    "MP #1684 exact native preview and popup gates change only owned button fields", function()
    local f = fixture()
    local protection_state = { read_only_backend = true }
    local native_preview = native_method(preview_source, "StoreWindowItemPreview",
        "_set_unlock_button_states", { GameSettingsDevelopment = protection_state })
    f.hooks[PREVIEW](native_preview, f.preview, false, true, true, false, false, true)
    local content = f.preview._top_widgets_by_name.unlock_button.content
    H.equal(content.button_hotspot.disable_button, false)
    H.equal(content.owned, false)
    H.equal(content.visible, true)
    H.equal(content.dlc_unlocked, true)
    H.equal(protection_state.read_only_backend, true)
    local native_create = native_method(popup_source, "StoreItemPurchasePopup", "_create_ui_elements", {
        UISceneGraph = { init_scenegraph = function() return {} end },
        scenegraph_definition = {}, static_widget_definitions = {},
        widget_definitions_by_state = { popup = {
            purchase_button = { content = { button_hotspot = {} } },
        } },
        pairs = pairs, UIWidget = { init = function(definition) return definition end },
        UIRenderer = { clear_scenegraph_queue = function() end },
        UIAnimator = { new = function() return {} end },
        GameSettingsDevelopment = protection_state,
    })
    f.hooks[CREATE](native_create, f.popup)
    H.equal(f.popup._widgets_by_name.purchase_button.content.button_hotspot.disable_button, false)
    H.equal(protection_state.read_only_backend, true)
    f.hooks[PREVIEW](native_preview, f.preview, false, true, true, false, true, true)
    H.equal(content.visible, false)
    H.equal(content.button_hotspot.disable_button, true)
end, "optional native source checkout unavailable")

H.test_if(popup_source ~= nil,
    "MP #1684 exact native currency iteration is unreachable for modded mixed offers", function()
    local f, calls, selected = fixture(), 0, nil
    f:authorize()
    f.item.current_prices.VS, f.item.regular_prices.VS = 1, 1
    local environment = {
        DLCSettings = { store = { currency_ui_settings = { VS = {}, SM = {} } } },
        pairs = function()
            local emitted = false
            return function()
                if not emitted then emitted = true; return "VS", {} end
            end
        end,
        callback = function() return function() end end,
        Managers = { backend = { get_interface = function() return {
            exchange_chips = function(_, _, currency)
                calls, selected = calls + 1, currency
            end,
        } end } },
    }
    local native = native_method(popup_source, "StoreItemPurchasePopup",
        "_poll_result_on_enter", environment)
    native(f.popup)
    H.equal(calls, 1)
    H.equal(selected, "VS", "positive control pins the non-SM native route")
    f.hooks[ENTER](native, f.popup)
    f.popup._state = "poll_result"
    f:update()
    H.equal(calls, 1)
    H.equal(f.exchanges, 0)
    H.equal(f.popup._state, "exit")
end, "optional native source checkout unavailable")
end
