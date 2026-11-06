-- Non-discovered fragment for test_ct_official_verify_rollup.lua.
-- load_production(relative_path, env) must execute the actual overlay file,
-- return its value AND resolved filename, and resolve nested mod:dofile calls
-- through the same overlay-only loader. No production-source substitution.
return function(H, load_production)
    local VM_ROOT = "scripts/mods/chaos_wastes_tweaker/"
    local function pack(...) return { n = select("#", ...), ... } end
    local function clone(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for key, item in pairs(value) do out[key] = clone(item) end
        return out
    end
    local function fixture(overrides)
        local hooks, checks, loads, commands = {}, {}, {}, {}
        local settings = {
            ct_buy_starting_boons = true,
            ct_start_shrine_boon_count = 4,
            ct_start_shrine_miracle_count = 0,
            ct_start_shrine_cost_percent = 100,
            ct_start_shrine_purchase_limit = 1,
            ct_individual_boon_prices = false,
        }
        for key, value in pairs(overrides or {}) do settings[key] = value end
        local mod, env = {}, {}
        function mod:get(key) return settings[key] end
        mod._ct_effective_setting = function(key) return settings[key] end
        local function register(_, class, method, callback)
            local key = class .. "." .. method
            assert(hooks[key] == nil, "duplicate real shop hook: " .. key)
            hooks[key] = callback
        end
        mod.hook, mod.hook_safe = register, register
        function mod:command(name, _, callback) commands[name] = callback end
        mod._ct_rt_register = function(name, fn)
            assert(checks[name] == nil, "duplicate runtime check")
            checks[name] = fn
        end
        function mod:dofile(path)
            assert(path:sub(1, #VM_ROOT) == VM_ROOT, "mod:dofile requires a native VM-root path")
            path = "chaos_wastes_tweaker/" .. path .. ".lua"
            loads[path] = (loads[path] or 0) + 1
            local value, actual = load_production(path, env)
            assert(type(actual) == "string" and actual:gsub("\\", "/"):find("/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/", 1, true),
                "test did not load actual production overlay: " .. path)
            return value
        end
        env.get_mod = function(id) assert(id == "ct"); return mod end
        env.printf = function() end
        env.DeusShopSettings = { shop_types = {} }
        env.DeusCostSettings = { shop = { power_ups = { rare = 200, exotic = 250, unique = 300 } } }
        env.table = {}
        for key, value in pairs(table) do env.table[key] = value end
        env.table.clone = clone
        env._G = env
        setmetatable(env, { __index = _G })
        local leaf = mod:dofile(VM_ROOT .. "_ct_official_shop")
        local state = { coins = 1000, owned = {}, bought = {}, writes = 0, tracking = {} }
        function state:get_player_profile() return 2, 3 end
        function state:get_player_soft_currency() return self.coins end
        function state:get_player_power_ups() return self.owned end
        function state:get_bought_power_ups() return self.bought end
        function state:set_player_power_ups(_, _, _, _, value) self.owned = value; self.writes = self.writes + 1 end
        function state:set_player_soft_currency(_, _, value) self.coins = value; self.writes = self.writes + 1 end
        function state:set_bought_power_ups(value) self.bought = value; self.writes = self.writes + 1 end
        function state:is_server() return true end
        local drc = { _run_state = state, node = { level = "dlc_morris_map", system_seeds = { blessings = 9 } },
            node_key = "start", run_id = "run-a" }
        function drc:get_current_node() return self.node end
        function drc:get_current_node_key() return self.node_key end
        function drc:get_run_id() return self.run_id end
        function drc:get_own_peer_id() return "peer-a" end
        function drc:get_player_soft_currency() return state.coins end
        function drc:has_power_up(_, client_id)
            for _, row in ipairs(state.owned) do if row.client_id == client_id then return true end end
            return false
        end
        function drc:reached_max_power_ups() return false end
        function drc:_add_coin_tracking_entry(_, _, amount, event)
            state.tracking[#state.tracking + 1] = { amount = amount, event = event }
        end
        local function view(power_up, discount)
            return { _shop_type = drc.node.level, _deus_run_controller = drc,
                _shop_items = { power_ups = { { power_up = power_up, discount = discount,
                    widget = { content = { price_text = "old", button_hotspot = {} } } } } } }
        end
        return { mod = mod, env = env, hooks = hooks, checks = checks, loads = loads,
            settings = settings, state = state, drc = drc, leaf = leaf, view = view, commands = commands }
    end

    H.test("CT official shop installs only six unowned seams and finite regression helpers", function()
        local f = fixture()
        local count = 0
        for _ in pairs(f.hooks) do count = count + 1 end
        H.equal(count, 6)
        H.equal(f.hooks["DeusRunController._try_buy_power_up"], nil)
        H.equal(f.hooks["DeusShopView._create_ui_elements"], nil)
        for _, count in pairs(f.loads) do H.equal(count, 1) end
        H.equal(f.checks.issue458_start_shrine_config(), nil)
        H.equal(f.checks.issue467_individual_boon_prices(), nil)
        H.equal(f.checks.issue1146_false_discount(), nil)
        H.equal(type(f.commands.ct_verify_start_shrine), "function")
    end)

    H.test("CT #458 actual startup callback prepares before native full_sync and preserves tuple", function()
        local f = fixture()
        local shared = { server = {} }
        function shared:get_key(key) return key end
        function shared:set_server(key, value) self.server[key] = value end
        local owner = { _deus_run_controller = f.drc, _shared_state = shared, _is_server = true }
        local calls = 0
        local callback = f.hooks["GameModeMapDeus.local_player_game_starts"]
        local result = pack(callback(function(self, player, loading, extra, hole)
            calls = calls + 1
            H.equal(self, owner); H.equal(player, "player"); H.equal(loading, "load")
            H.equal(extra, "extra"); H.equal(hole, nil)
            H.equal(f.leaf.start.config_valid(f.env.DeusShopSettings.shop_types.dlc_morris_map), true)
            H.equal(shared.server.state, nil, "SHOP must not publish before native startup")
            return "first", nil, "third", nil
        end, owner, "player", "load", "extra", nil))
        H.equal(calls, 1); H.equal(result.n, 4); H.equal(result[1], "first")
        H.equal(result[2], nil); H.equal(result[3], "third"); H.equal(result[4], nil)
        H.equal(shared.server.state, 3)
        H.equal(f.drc.node_key, "start"); H.equal(f.drc.node.level, "dlc_morris_map")
    end)

    H.test("CT #458 actual view guard rejects invalid config before native dereference", function()
        local f = fixture({ ct_start_shrine_cost_percent = 15 })
        local shared = { server = {}, own = {} }
        function shared:get_key(key) return key end
        function shared:set_server(key, value) self.server[key] = value end
        function shared:set_own(key, value) self.own[key] = value end
        local view = f.view({ name = "barkskin", rarity = "rare", client_id = 1 }, false)
        view._shared_state, view._is_server = shared, true
        local calls = 0
        f.hooks["DeusShopView.start"](function() calls = calls + 1 end, view, {})
        H.equal(calls, 0); H.equal(shared.server.state, 1); H.equal(shared.own.state, 1)
        H.equal(f.state.writes, 0)
    end)

    H.test("CT #1146 false discount has numeric display exact debit and isolated limit", function()
        local f = fixture()
        H.truthy(f.leaf.start.prepare(f.drc))
        local power = { name = "barkskin", rarity = "rare", client_id = 1 }
        local view = f.view(power, false)
        f.mod._ct_official_shop_refresh(view)
        H.equal(view._shop_items.power_ups[1].widget.content.price_text, "200")
        local owned, bought = f.state.owned, f.state.bought
        local handled, accepted = f.mod._ct_official_shop_try_buy(f.drc, "peer-a", power, false)
        H.equal(handled, true); H.equal(accepted, true); H.equal(f.state.coins, 800)
        H.equal(#owned, 0); H.equal(#bought, 0, "native state lists are cloned, not mutated")
        H.equal(f.state.tracking[1].amount, -200); H.equal(f.state.tracking[1].event, "rare_power_up")
        H.equal(f.leaf.start.purchase_count(f.drc, "peer-a", 1), 1)
        H.equal(f.leaf.start.purchase_count(f.drc, "peer-b", 1), 0)
        handled, accepted = f.mod._ct_official_shop_try_buy(f.drc, "peer-a",
            { name = "money_magnet", rarity = "rare", client_id = 2 }, false)
        H.equal(handled, true); H.equal(accepted, false); H.equal(f.state.coins, 800)
        f.hooks["DeusShopView._update_shop_widgets"](view)
        H.equal(view._shop_items.power_ups[1].widget.content.button_hotspot.disable_button, true)
        f.drc.run_id = "run-b"
        H.equal(f.leaf.start.purchase_count(f.drc, "peer-a", 1), 0)
    end)

    H.test("CT #458 malformed rarity-price state rejects without writes; later shrine passes through", function()
        local f = fixture()
        f.leaf.start.prepare(f.drc)
        for _, discount in ipairs({ true, "bad", -1, 2, math.huge }) do
            local handled, accepted = f.mod._ct_official_shop_try_buy(f.drc, "peer-a",
                { name = "barkskin", rarity = "rare", client_id = 1 }, discount)
            H.equal(handled, true); H.equal(accepted, false)
        end
        H.equal(f.state.writes, 0); H.equal(f.state.coins, 1000)
        f.drc.node_key, f.drc.node.level = "shop", "shop_strife"
        H.equal(f.mod._ct_official_shop_try_buy(f.drc, "peer-a", {}, false), false)
        local view = f.view({}, false)
        local got = pack(f.hooks["DeusShopView._get_power_up_costs"](function(_, _, _, extra)
            H.equal(extra, "extra"); return 77, nil, "tail", nil
        end, view, "rare", false, "extra"))
        H.equal(got.n, 4); H.equal(got[1], 77); H.equal(got[2], nil); H.equal(got[3], "tail")
    end)

    H.test("CT #467 exact-name price composes start scale and matches authoritative charge", function()
        local f = fixture({ ct_individual_boon_prices = true, ct_start_shrine_cost_percent = 50 })
        f.leaf.start.prepare(f.drc)
        local power = { name = "barkskin", rarity = "rare", client_id = 1 }
        local view = f.view(power, false)
        f.mod._ct_official_shop_refresh(view)
        H.equal(view._shop_items.power_ups[1].widget.content.price_text, "113")
        local handled, accepted = f.mod._ct_official_shop_try_buy(f.drc, "peer-a", power, false)
        H.equal(handled, true); H.equal(accepted, true); H.equal(f.state.coins, 887)
        H.equal(power.rarity, "rare"); H.equal(power.name, "barkskin")
        H.equal(f.mod._ct_boon_pricing_policy.price("money_magnet", "rare", false, 100), 150)
        H.equal(f.mod._ct_boon_pricing_policy.price("barkskin", "rare", 0.5, 100), 112)
        -- Donor characterization, not a new correction: nonnumeric discount
        -- becomes zero in exact-name pricing; the start-rarity policy is stricter.
        H.equal(f.mod._ct_boon_pricing_policy.price("barkskin", "rare", true, 100), 225)
    end)

    H.test("CT #467 actual card and telemetry callbacks preserve native tuples", function()
        local f = fixture({ ct_individual_boon_prices = true })
        f.drc.node_key, f.drc.node.level = "shop", "shop_strife"
        local power = { name = "barkskin", rarity = "rare", client_id = 1 }
        local view = f.view(power, false)
        local widget = view._shop_items.power_ups[1].widget
        local got = pack(f.hooks["DeusShopView._init_power_up_widget"](function(_, _, _, _, _, _, _, _, extra)
            H.equal(extra, "extra"); return "card", nil, "tail", nil
        end, view, widget, power, false, 0, 1, 2, 3, "extra"))
        H.equal(got.n, 4); H.equal(got[1], "card"); H.equal(got[3], "tail")
        H.equal(widget.content.price_text, "225")
        view._telemetry_data = { purchased_boons = {} }
        got = pack(f.hooks["DeusShopView._on_power_up_bought"](function(self, _, _, extra)
            H.equal(extra, "extra"); self._telemetry_data.purchased_boons[1] = { cost = 200 }
            return false, nil, "telemetry", nil
        end, view, power, false, "extra"))
        H.equal(got.n, 4); H.equal(got[1], false); H.equal(got[3], "telemetry")
        H.equal(view._telemetry_data.purchased_boons[1].cost, 225)
        f.state.coins = 224
        f.hooks["DeusShopView._update_shop_widgets"](view)
        H.equal(widget.content.button_hotspot.disable_button, true)
        local handled, accepted = f.mod._ct_official_shop_try_buy(f.drc, "peer-a", power, false)
        H.equal(handled, true); H.equal(accepted, false); H.equal(f.state.writes, 0)
        f.state.coins = 225
        handled, accepted = f.mod._ct_official_shop_try_buy(f.drc, "peer-a", power, false)
        H.equal(handled, true); H.equal(accepted, true); H.equal(f.state.coins, 0)
        H.equal(f.state.tracking[1].amount, -225)
    end)

    H.test("CT shop host-effective false never falls back to a saved true", function()
        local f = fixture()
        f.drc.node_key, f.drc.node.level = "shop", "shop_strife"
        f.mod.get = function() return true end
        H.equal(f.mod._ct_official_shop_try_buy(f.drc, "peer-a", {}, false), false)
        H.equal(f.state.writes, 0)
    end)
end
