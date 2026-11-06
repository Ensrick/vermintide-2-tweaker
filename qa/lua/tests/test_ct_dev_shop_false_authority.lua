-- Execute actual Dev shop modules and the exact entry-owned effective reader.
-- Optional load_production(relative_path, env) supports a bounded overlay run;
-- normal repository QA loads the installed production paths directly.
return function(H, repo_root, load_production)
    local ROOT = "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local function read(path)
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local source = file:read("*a"); file:close()
        return source:gsub("\r\n", "\n")
    end
    local main = read(ROOT .. "chaos_wastes_tweaker_dev.lua")
    local first = assert(main:find("effective_setting = function(name)", 1, true))
    local last = assert(main:find("\nend", first, true)) + #"\nend" - 1
    local actual_reader_source = main:sub(first + #"effective_setting = ", last)
    local function load(path, env)
        if load_production then
            local value, actual = load_production(path, env)
            assert(type(actual) == "string" and actual:gsub("\\", "/"):sub(-#path) == path,
                "loader did not execute named production file")
            return value
        end
        local chunk = assert(loadfile(repo_root .. "/" .. path))
        setfenv(chunk, env)
        return chunk()
    end
    local function fixture(options)
        options = options or {}
        local saved = {
            ct_buy_starting_boons = true, ct_start_shrine_boon_count = 4,
            ct_start_shrine_miracle_count = 1, ct_start_shrine_cost_percent = 100,
            ct_start_shrine_purchase_limit = 0, ct_individual_boon_prices = true,
            ct_start_shrine_miracle_blessing_of_power = true,
        }
        local host = {}
        for key, value in pairs(saved) do host[key] = value end
        host.ct_individual_boon_prices = false
        host.ct_start_shrine_miracle_blessing_of_power = false
        if options.host then for key, value in pairs(options.host) do host[key] = value end end
        if options.saved then for key, value in pairs(options.saved) do saved[key] = value end end
        local mod = { get = function(_, key) return saved[key] end,
            hook = function() end, hook_safe = function() end, command = function() end }
        local env = { get_mod = function(id) assert(id == "ct_dev"); return mod end,
            mod = mod, Managers = { player = { is_server = false } },
            _ct_host_settings = host, printf = function() end,
            DeusShopSettings = { shop_types = {} },
            DeusCostSettings = { shop = { power_ups = { rare = 200 } } } }
        env._G = env
        setmetatable(env, { __index = _G })
        local reader = assert(loadstring("return " .. actual_reader_source, "@ct_actual_effective_reader"))
        setfenv(reader, env)
        mod._ct_effective_setting = reader()
        if options.no_reader then mod._ct_effective_setting = nil end
        mod._ct_start_shrine_policy = load(ROOT .. "_ct_start_shrine_policy.lua", env)
        mod._ct_boon_pricing_policy = load(ROOT .. "_ct_boon_pricing_policy.lua", env)
        mod._ct_start_shrine_runtime = load(ROOT .. "_ct_start_shrine_runtime.lua", env)
        mod._ct_boon_pricing_runtime = load(ROOT .. "_ct_boon_pricing_runtime.lua", env)
        local state = { coins = 1000, owned = {}, bought = {}, writes = 0 }
        function state:get_player_profile() return 1, 1 end
        function state:get_player_soft_currency() return self.coins end
        function state:get_player_power_ups() return self.owned end
        function state:get_bought_power_ups() return self.bought end
        function state:set_player_power_ups(_, _, _, _, value) self.owned = value; self.writes = self.writes + 1 end
        function state:set_player_soft_currency(_, _, value) self.coins = value; self.writes = self.writes + 1 end
        function state:set_bought_power_ups(value) self.bought = value; self.writes = self.writes + 1 end
        function state:is_server() return false end
        env.table = {}
        for key, value in pairs(table) do env.table[key] = value end
        env.table.clone = function(value)
            local out = {}; for key, item in pairs(value) do out[key] = item end; return out
        end
        local drc = { _run_state = state, node_key = "start", node_level = "dlc_morris_map" }
        function drc:get_current_node() return { level = self.node_level } end
        function drc:get_current_node_key() return self.node_key end
        function drc:get_run_id() return "false-authority-run" end
        function drc:has_power_up() return false end
        function drc:_add_coin_tracking_entry() end
        return { mod = mod, env = env, state = state, drc = drc,
            start = mod._ct_start_shrine_runtime, pricing = mod._ct_boon_pricing_runtime }
    end

    H.test("CT Dev authority host-false miracle pool does not use saved true", function()
        local f = fixture()
        H.equal(f.mod._ct_effective_setting("ct_start_shrine_miracle_blessing_of_power"), false)
        H.equal(#f.start.build_blessings(123), 0)
    end)

    H.test("CT Dev authority host-false exact pricing keeps start rarity price", function()
        local f = fixture()
        H.truthy(f.start.prepare(f.drc))
        H.equal(f.start.price("rare", false, "barkskin"), 200)
    end)

    H.test("CT Dev authority host-false exact pricing leaves later card native", function()
        local f = fixture()
        f.drc.node_key, f.drc.node_level = "shop", "shop_strife"
        H.equal(f.pricing.view_price({ _deus_run_controller = f.drc },
            { name = "barkskin", rarity = "rare", client_id = 1 }, false), nil)
    end)

    H.test("CT Dev authority host-false exact pricing never performs predicted debit", function()
        local f = fixture()
        f.drc.node_key, f.drc.node_level = "shop", "shop_strife"
        local handled = f.pricing.try_buy(f.drc, "peer-a",
            { name = "barkskin", rarity = "rare", client_id = 1 }, false)
        H.equal(f.state.coins, 1000); H.equal(f.state.writes, 0)
        H.equal(handled, false)
    end)

    H.test("CT Dev authority host-true exact pricing overrides saved false", function()
        local f = fixture({ host = { ct_individual_boon_prices = true },
            saved = { ct_individual_boon_prices = false } })
        f.drc.node_key, f.drc.node_level = "shop", "shop_strife"
        H.equal(f.pricing.price({ name = "barkskin", rarity = "rare" }, false, 100), 225)
    end)

    H.test("CT Dev authority absent reader keeps saved local fallback", function()
        local f = fixture({ no_reader = true })
        H.equal(f.pricing.price({ name = "barkskin", rarity = "rare" }, false, 100), 225)
        H.equal(#f.start.build_blessings(123), 1)
    end)
end
