return function(H, repo_root)
    local policy_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_start_shrine_policy.lua"
    local runtime_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_start_shrine_runtime.lua"
    local main_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
    -- #1159: the consolidated _try_buy_power_up purchase hook #458 shares moved
    -- out of the entry into the boon-grant owner. The singleton invariant is now
    -- asserted THERE, plus an entry-side absence assertion below so a future
    -- re-add to the entry (a silently shadowed second VMF hook) fails this test.
    local grant_owner_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_grant_owner.lua"
    local data_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua"
    local policy = dofile(policy_path)

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_runtime(setting_overrides)
        local hooks = {}
        local settings = {
            ct_buy_starting_boons = true,
            ct_start_shrine_boon_count = 4,
            ct_start_shrine_miracle_count = 0,
            ct_start_shrine_cost_percent = 150,
            ct_start_shrine_purchase_limit = 1,
        }
        for key, value in pairs(setting_overrides or {}) do settings[key] = value end
        local mock_mod = {
            _ct_start_shrine_policy = policy,
            get = function(_, key) return settings[key] end,
            hook = function(_, class, method, callback)
                hooks[class .. "." .. method] = callback
            end,
            hook_safe = function(_, class, method, callback)
                hooks[class .. "." .. method] = callback
            end,
            command = function() end,
        }
        mock_mod._ct_effective_setting = function(key) return settings[key] end

        local table_env = {}
        for key, value in pairs(table) do table_env[key] = value end
        table_env.clone = function(value)
            local copy = {}
            for key, item in pairs(value) do copy[key] = item end
            return copy
        end
        local env = {
            get_mod = function() return mock_mod end,
            printf = function() end,
            table = table_env,
            DeusShopSettings = { shop_types = {} },
            DeusCostSettings = { shop = { power_ups = { rare = 250 } } },
        }
        env._G = env
        setmetatable(env, { __index = _G })
        local chunk = assert(loadfile(runtime_path))
        setfenv(chunk, env)
        return assert(chunk()), hooks
    end

    H.test("CT #458 price policy accepts exactly 0-200 percent in 10-percent steps", function()
        for percent = 0, 200, 10 do
            H.equal(policy.cost_percent(percent), percent)
        end
        for _, invalid in ipairs({ -10, 5, 15, 201, 210, 0 / 0 }) do
            H.equal(policy.cost_percent(invalid), nil)
        end
    end)

    H.test("CT #458 displayed and charged price helper preserves vanilla discount order", function()
        local costs = { shop = { power_ups = { rare = 200, exotic = 250 } } }
        H.equal(policy.shop_cost(costs, "rare", 0, 0), 0)
        H.equal(policy.shop_cost(costs, "rare", 0, 100), 200)
        H.equal(policy.shop_cost(costs, "rare", 0, 200), 400)
        H.equal(policy.shop_cost(costs, "exotic", 0.5, 150), 188)
        H.equal(policy.shop_cost(costs, "missing", 0, 100), nil)
        H.equal(policy.shop_cost(costs, "rare", 2, 100), nil)
    end)

    H.test("CT #458 purchase ledger is isolated by run peer and local player", function()
        local ledger = {}
        H.equal(policy.count(ledger, 10, "peer-a", 1), 0)
        H.equal(policy.record_purchase(ledger, 10, "peer-a", 1), 1)
        H.equal(policy.record_purchase(ledger, 10, "peer-a", 2), 1)
        H.equal(policy.record_purchase(ledger, 10, "peer-b", 1), 1)
        local allowed, count = policy.can_purchase(ledger, 10, "peer-a", 1, 1)
        H.equal(allowed, false)
        H.equal(count, 1)
        allowed, count = policy.can_purchase(ledger, 10, "peer-a", 2, 2)
        H.equal(allowed, true)
        H.equal(count, 1)
        H.equal(policy.count(ledger, 11, "peer-a", 1), 0)
        H.equal(policy.can_purchase(ledger, 11, "peer-a", 1, 0), true)
    end)

    H.test("CT #458 runtime owns one exact synthetic identity and never mutates global costs", function()
        local source = read(runtime_path)
        H.truthy(source:find('local START_LEVEL = "dlc_morris_map"', 1, true))
        H.truthy(source:find('local START_NODE = "start"', 1, true))
        H.truthy(source:find('if not active then return false end', 1, true))
        H.equal(source:find("DeusCostSettings.shop.power_ups[", 1, true), nil)
        H.truthy(source:find("local price = power_up and M.price", 1, true))
        H.truthy(source:find("local price = entry and entry.power_up and M.price", 1, true))
        H.truthy(source:find('mod:hook("DeusShopView", "_get_power_up_costs"', 1, true))
        H.truthy(source:find("return M.price(rarity, discount) or math.huge", 1, true))
        H.truthy(source:find('mod:hook_safe("DeusShopView", "_update_shop_widgets"', 1, true))
    end)

    H.test("CT #458 runtime requires both exact start level and exact start node", function()
        local runtime = load_runtime()

        local function controller(level, node_key, run_id)
            return {
                get_current_node = function() return { level = level } end,
                get_current_node_key = function() return node_key end,
                get_run_id = function() return run_id end,
            }
        end

        H.equal(runtime.is_context(controller("dlc_morris_map", "start", 7)), true)
        H.equal(runtime.is_context(controller("dlc_morris_map", "shop", 7)), false)
        H.equal(runtime.is_context(controller("dlc_morris_map", nil, 7)), false)
        H.equal(runtime.is_context(controller("dlc_morris_map", "start", nil)), false)
        H.equal(runtime.is_context(controller("dlc_morris_map_01", "start", 7)), false)
    end)

    H.test("CT #458 runtime uses one price for UI and bounded purchase mutation", function()
        local runtime, hooks = load_runtime()
        local state = {
            coins = 1000,
            power_ups = {},
            bought = {},
            get_player_profile = function() return 1, 1 end,
            get_player_soft_currency = function(self) return self.coins end,
            set_player_soft_currency = function(self, _, _, value) self.coins = value end,
            get_player_power_ups = function(self) return self.power_ups end,
            set_player_power_ups = function(self, _, _, _, _, value) self.power_ups = value end,
            get_bought_power_ups = function(self) return self.bought end,
            set_bought_power_ups = function(self, value) self.bought = value end,
            is_server = function() return true end,
        }
        local drc = {
            _run_state = state,
            get_current_node = function()
                return { level = "dlc_morris_map", system_seeds = { blessings = 12 } }
            end,
            get_current_node_key = function() return "start" end,
            get_run_id = function() return 77 end,
            has_power_up = function() return false end,
            _add_coin_tracking_entry = function(_, _, _, amount) state.tracked = amount end,
        }
        H.truthy(runtime.prepare(drc))
        H.equal(runtime.price("rare", 0.5), 188)

        local cost_hook = assert(hooks["DeusShopView._get_power_up_costs"])
        local vanilla_calls = 0
        local function vanilla_cost() vanilla_calls = vanilla_calls + 1; return 125 end
        H.equal(cost_hook(vanilla_cost,
            { _shop_type = "dlc_morris_map", _deus_run_controller = drc }, "rare", 0.5), 188)
        H.equal(vanilla_calls, 1)

        local handled, bought, charged = runtime.try_buy(drc, "peer-a",
            { name = "boon-a", rarity = "rare", client_id = 1 }, 0.5)
        H.equal(handled, true)
        H.equal(bought, true)
        H.equal(charged, 188)
        H.equal(state.coins, 812)
        H.equal(state.tracked, -188)

        handled, bought = runtime.try_buy(drc, "peer-a",
            { name = "boon-b", rarity = "rare", client_id = 2 }, 0.5)
        H.equal(handled, true)
        H.equal(bought, false)
        H.equal(state.coins, 812)

        local later_drc = {
            get_current_node = function() return { level = "shop_strife" } end,
            get_current_node_key = function() return "shop" end,
            get_run_id = function() return 77 end,
        }
        H.equal(cost_hook(vanilla_cost,
            { _shop_type = "shop_strife", _deus_run_controller = later_drc }, "rare", 0.5), 125)
        H.equal(vanilla_calls, 2)
    end)

    H.test("CT #458 decorates initial cards and disables them at the per-player limit", function()
        local runtime = load_runtime()
        local drc = {
            get_current_node = function()
                return { level = "dlc_morris_map", system_seeds = { blessings = 12 } }
            end,
            get_current_node_key = function() return "start" end,
            get_run_id = function() return 78 end,
            get_own_peer_id = function() return "peer-a" end,
        }
        H.truthy(runtime.prepare(drc))
        local view = {
            _shop_type = "dlc_morris_map",
            _deus_run_controller = drc,
            _shop_items = { power_ups = {
                {
                    power_up = { rarity = "rare" },
                    discount = 0.5,
                    widget = { content = {
                        price_text = "vanilla",
                        button_hotspot = { disable_button = false },
                    } },
                },
            } },
        }
        runtime.decorate_shop(view)
        H.equal(view._shop_items.power_ups[1].widget.content.price_text, "188")
        H.equal(view._shop_items.power_ups[1].widget.content.button_hotspot.disable_button, false)

        H.equal(runtime.record_purchase(drc, "peer-a", 1), 1)
        runtime.enforce_limit(view)
        H.equal(view._shop_items.power_ups[1].widget.content.button_hotspot.disable_button, true)
    end)

    H.test("CT #458 client prediction and host replay charge and count identically", function()
        local function buy_once(is_server)
            local runtime = load_runtime()
            local state = {
                coins = 1000,
                power_ups = {},
                bought = {},
                get_player_profile = function() return 1, 1 end,
                get_player_soft_currency = function(self) return self.coins end,
                set_player_soft_currency = function(self, _, _, value) self.coins = value end,
                get_player_power_ups = function(self) return self.power_ups end,
                set_player_power_ups = function(self, _, _, _, _, value) self.power_ups = value end,
                get_bought_power_ups = function(self) return self.bought end,
                set_bought_power_ups = function(self, value) self.bought = value end,
                is_server = function() return is_server end,
            }
            local drc = {
                _run_state = state,
                get_current_node = function()
                    return { level = "dlc_morris_map", system_seeds = { blessings = 12 } }
                end,
                get_current_node_key = function() return "start" end,
                get_run_id = function() return 79 end,
                has_power_up = function() return false end,
                _add_coin_tracking_entry = function(_, _, _, amount) state.tracked = amount end,
            }
            H.truthy(runtime.prepare(drc))
            local handled, bought, charged = runtime.try_buy(drc, "peer-a",
                { name = "boon-a", rarity = "rare", client_id = 1 }, 0.5)
            return handled, bought, charged, state.coins, state.tracked,
                runtime.purchase_count(drc, "peer-a", 1)
        end

        local client = { buy_once(false) }
        local host = { buy_once(true) }
        H.equal(#client, #host)
        for i = 1, #client do H.equal(client[i], host[i]) end
        H.equal(client[3], 188)
        H.equal(client[4], 812)
        H.equal(client[6], 1)
    end)

    H.test("CT #458 malformed exact-start policy fails closed without mutation", function()
        local runtime, hooks = load_runtime({ ct_start_shrine_cost_percent = 155 })
        local state = { coins = 1000 }
        local drc = {
            _run_state = state,
            get_current_node = function()
                return { level = "dlc_morris_map", system_seeds = { blessings = 12 } }
            end,
            get_current_node_key = function() return "start" end,
            get_run_id = function() return 80 end,
            has_power_up = function() error("must reject before duplicate lookup") end,
        }
        H.equal(runtime.prepare(drc), nil)

        local cost_hook = assert(hooks["DeusShopView._get_power_up_costs"])
        local vanilla_calls = 0
        local value = cost_hook(function()
            vanilla_calls = vanilla_calls + 1
            return 125
        end, { _shop_type = "dlc_morris_map", _deus_run_controller = drc }, "rare", 0.5)
        H.equal(value, math.huge)
        H.equal(vanilla_calls, 1)

        local handled, bought = runtime.try_buy(drc, "peer-a",
            { name = "boon-a", rarity = "rare", client_id = 1 }, 0.5)
        H.equal(handled, true)
        H.equal(bought, false)
        H.equal(state.coins, 1000)
    end)

    H.test("CT #458 malformed boon identity and missing profile fail before mutation", function()
        local runtime = load_runtime()
        local state = {
            coins = 1000,
            power_ups = {},
            bought = {},
            get_player_profile = function() return nil, nil end,
            get_player_soft_currency = function(self) return self.coins end,
            set_player_soft_currency = function() error("must not mutate coins") end,
            get_player_power_ups = function(self) return self.power_ups end,
            set_player_power_ups = function() error("must not mutate boons") end,
            get_bought_power_ups = function(self) return self.bought end,
            set_bought_power_ups = function() error("must not mutate ledger") end,
            is_server = function() return true end,
        }
        local drc = {
            _run_state = state,
            get_current_node = function()
                return { level = "dlc_morris_map", system_seeds = { blessings = 12 } }
            end,
            get_current_node_key = function() return "start" end,
            get_run_id = function() return 81 end,
            has_power_up = function() return false end,
            _add_coin_tracking_entry = function() error("must not track coins") end,
        }
        H.truthy(runtime.prepare(drc))
        local handled, bought = runtime.try_buy(drc, "peer-a",
            { rarity = "rare", client_id = 1 }, 0.5)
        H.equal(handled, true)
        H.equal(bought, false)
        handled, bought = runtime.try_buy(drc, "peer-a",
            { name = "boon-a", rarity = "rare", client_id = 1 }, 0.5)
        H.equal(handled, true)
        H.equal(bought, false)
        H.equal(state.coins, 1000)
    end)

    H.test("CT #458 preserves config-before-full-sync and consolidated purchase hook", function()
        local runtime = read(runtime_path)
        local prepare = assert(runtime:find("if at_start then prepared, cfg = pcall(M.prepare, drc) end", 1, true))
        local vanilla = assert(runtime:find("func(self, player, loading_context)", 1, true))
        H.truthy(prepare < vanilla)
        H.truthy(runtime:find("M.config_valid(cfg)", 1, true))
        H.truthy(runtime:find("restored MAP_DECISION", 1, true))

        local grant_owner = read(grant_owner_path)
        H.truthy(grant_owner:find("_ct_consolidated_try_buy_power_up_hook", 1, true))
        H.truthy(grant_owner:find("_ct_start_shrine_runtime.try_buy", 1, true))
        local _, hook_count = grant_owner:gsub(
            'mod:hook%("DeusRunController", "_try_buy_power_up"', "")
        H.equal(hook_count, 1)

        -- The entry must no longer carry the hook or the delegation: a second
        -- registration on the same Class/method pair is silently dropped by VMF,
        -- so "present in both files" would be an invisible behaviour change.
        local main = read(main_path)
        local _, entry_hook_count = main:gsub(
            'mod:hook%("DeusRunController", "_try_buy_power_up"', "")
        H.equal(entry_hook_count, 0)
        H.equal(main:find("_ct_consolidated_try_buy_power_up_hook", 1, true), nil)
        H.equal(main:find("_ct_start_shrine_runtime.try_buy", 1, true), nil)
        -- The entry still dofiles the runtime this owner delegates to, and does so
        -- BEFORE the owner loads, so mod._ct_start_shrine_runtime is populated by
        -- the time the hook body first runs.
        local runtime_at = assert(main:find(
            "mods/chaos_wastes_tweaker_dev/_ct_start_shrine_runtime", 1, true))
        local owner_at = assert(main:find(
            "mods/chaos_wastes_tweaker_dev/_ct_boon_grant_owner", 1, true))
        H.truthy(runtime_at < owner_at)
    end)

    H.test("CT #458 settings expose stepped price and bounded purchase limit", function()
        local data = read(data_path)
        H.truthy(data:find('setting_id = "ct_start_shrine_cost_percent", type = "dropdown", default_value = 100', 1, true))
        H.truthy(data:find("for percent = 0, 200, 10 do", 1, true))
        H.truthy(data:find('setting_id = "ct_start_shrine_purchase_limit", type = "dropdown", default_value = 0', 1, true))
        H.truthy(data:find('{ text = "ct_start_shrine_limit_unlimited", value = 0 }', 1, true))
    end)
end
