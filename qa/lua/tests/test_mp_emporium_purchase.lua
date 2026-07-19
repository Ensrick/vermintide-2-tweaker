return function(H, repo_root)
    local root = repo_root .. "/modded_progression/scripts/mods/modded_progression/"
    local Policy = assert(loadfile(root .. "_mp_emporium_policy.lua"))()

    local function offer(key, price)
        return {
            key = key,
            data = { slot_type = "hat" },
            regular_prices = { SM = price },
            current_prices = { SM = price },
        }
    end

    local function load_dailies()
        local storage, fail_next = {}, false
        local fake_mod = {
            get = function(_, key) return storage[key] end,
            set = function(_, key, value)
                if fail_next then fail_next = false; error("injected persistence failure") end
                storage[key] = value
            end,
        }
        local old_get_mod, old_settings, old_printf = _G.get_mod, _G.QuestSettings, _G.printf
        local preload_key = "scripts/managers/quest/quest_templates"
        local old_preload, old_loaded = package.preload[preload_key], package.loaded[preload_key]
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
            templates.quests[name] = { name = name, stat_mappings = {{ qualifying_event = true }} }
        end
        _G.get_mod, _G.QuestSettings, _G.printf = function() return fake_mod end, settings, function() end
        package.loaded[preload_key] = nil
        package.preload[preload_key] = function() return templates end
        local D = assert(loadfile(root .. "mp_dailies.lua"))()
        local function restore()
            _G.get_mod, _G.QuestSettings, _G.printf = old_get_mod, old_settings, old_printf
            package.preload[preload_key], package.loaded[preload_key] = old_preload, old_loaded
        end
        return D, storage, function() fail_next = true end, restore
    end

    H.test("Emporium resolves exact local offer and price", function()
        local stock = { offer("hat_alpha", 25), offer("hat_beta", 40) }
        H.equal(Policy.find_offer(stock, "hat_beta"), stock[2])
        local plan = Policy.validate({ offer = stock[2], currency = "SM", expected_price = 40,
            balance = 50, owned = false, available = true, dlc_owned = true })
        H.equal(plan.item_key, "hat_beta")
        H.equal(plan.item.ItemId, "hat_beta")
        H.equal(plan.item.UnitCurrency, "SM")
        H.equal(plan.item.UnitPrice, 40)
    end)

    H.test("Emporium projects official ownership onto local state without mutating stock", function()
        local official = offer("hat_officially_owned", 25)
        official.owned = true
        local platform = offer("platform", 25)
        platform.owned = true
        platform.steam_itemdefid = "123"
        local projected = Policy.project_stock({ official, platform }, "SM", function(key)
            return key == "locally_owned"
        end)
        H.equal(projected[1].owned, false)
        H.equal(projected[2].owned, true)
        H.equal(official.owned, true)
        H.equal(projected[1] == official, false)
        H.equal(projected[2], platform)
    end)

    H.test("Emporium local ownership ignores official mirror inventory", function()
        local unlocks = { hat_unlock = true }
        local inventory = { bid = { ItemId = "hat_inventory" } }
        H.equal(Policy.is_locally_owned("hat_unlock", unlocks, inventory), true)
        H.equal(Policy.is_locally_owned("hat_inventory", unlocks, inventory), true)
        H.equal(Policy.is_locally_owned("official_only", unlocks, inventory), false)
    end)

    H.test("Emporium cleanup preserves borrowed official unlocks", function()
        local mirror = {
            _inventory_items = { official_bid = true },
            _fake_inventory_items = { official_bid = true },
            _unlocked_cosmetics = { hat = "official_bid" },
        }
        local removed = Policy.cleanup_overlay_record(mirror, {
            item_key = "hat", actual_id = "official_bid", kind = "cosmetic", preexisting = true,
        })
        H.equal(removed, false)
        H.equal(mirror._inventory_items.official_bid, true)
        H.equal(mirror._fake_inventory_items.official_bid, true)
        H.equal(mirror._unlocked_cosmetics.hat, "official_bid")
    end)

    H.test("Emporium cleanup removes only MP-created overlay rows", function()
        local mirror = {
            _inventory_items = { local_bid = true },
            _fake_inventory_items = { local_bid = true },
            _unlocked_cosmetics = { hat = "local_bid" },
        }
        local removed = Policy.cleanup_overlay_record(mirror, {
            item_key = "hat", actual_id = "local_bid", kind = "cosmetic", preexisting = false,
        })
        H.equal(removed, true)
        H.equal(mirror._inventory_items.local_bid, nil)
        H.equal(mirror._fake_inventory_items.local_bid, nil)
        H.equal(mirror._unlocked_cosmetics.hat, nil)
    end)

    H.test("Emporium rejects stale ownership unavailable DLC bundle and platform offers", function()
        local base = offer("hat", 25)
        local function reason(overrides)
            local args = { offer = base, currency = "SM", expected_price = 25,
                balance = 25, owned = false, available = true, dlc_owned = true }
            for key, value in pairs(overrides) do args[key] = value end
            local _, why = Policy.validate(args)
            return why
        end
        H.equal(reason({ expected_price = 24 }), "price_mismatch")
        H.equal(reason({ owned = true }), "already_owned")
        H.equal(reason({ balance = 24 }), "insufficient_funds")
        H.equal(reason({ available = false }), "offer_unavailable")
        H.equal(reason({ dlc_owned = false }), "dlc_not_owned")
        H.equal(reason({ currency = "VS" }), "currency_not_local")
        local platform = offer("dlc", 25); platform.dlc_name = "paid"
        H.equal(reason({ offer = platform }), "platform_offer")
        local bundle = offer("bundle", 25); bundle.data.bundle_contains = { child = true }
        H.equal(reason({ offer = bundle }), "bundle_not_local")
        local punctuated = Policy.validate({ offer = offer("h-at", 25), currency = "SM",
            expected_price = 25, balance = 25, owned = false, available = true, dlc_owned = true })
        local underscored = Policy.validate({ offer = offer("h_at", 25), currency = "SM",
            expected_price = 25, balance = 25, owned = false, available = true, dlc_owned = true })
        H.equal(punctuated.backend_id == underscored.backend_id, false)
    end)

    H.test("Emporium purchase atomically persists debit grant unlock and marker", function()
        local D, storage, _, restore = load_dailies()
        local ok, failure = pcall(function()
            H.truthy(D.credit(60))
            local plan = Policy.validate({ offer = offer("hat_exact", 25), currency = "SM",
                expected_price = 25, balance = D.balance(), owned = false,
                available = true, dlc_owned = true })
            local item, balance = D.purchase(plan)
            H.equal(balance, 35)
            H.equal(item.ItemId, "hat_exact")
            local state = storage[D.STATE_KEY]
            H.truthy(state.emporium.inventory[plan.backend_id])
            H.truthy(state.emporium.unlocks.hat_exact)
            H.truthy(state.emporium.transactions[plan.tx_id])
            H.truthy(state.ledger.transactions[plan.tx_id])
        end)
        restore()
        if not ok then error(failure, 0) end
    end)

    H.test("Emporium duplicate callback cannot double spend or grant", function()
        local D, _, _, restore = load_dailies()
        local ok, failure = pcall(function()
            H.truthy(D.credit(50))
            local plan = Policy.validate({ offer = offer("hat_once", 20), currency = "SM",
                expected_price = 20, balance = 50, owned = false, available = true, dlc_owned = true })
            H.truthy(D.purchase(plan))
            H.equal(D.purchase(plan), nil)
            H.equal(D.balance(), 30)
            local count = 0
            for _ in pairs(D.emporium_inventory()) do count = count + 1 end
            H.equal(count, 1)
        end)
        restore()
        if not ok then error(failure, 0) end
    end)

    H.test("Emporium injected persistence failure leaves all state unchanged", function()
        local D, storage, fail, restore = load_dailies()
        local ok, failure = pcall(function()
            H.truthy(D.credit(50))
            local before = storage[D.STATE_KEY]
            local plan = Policy.validate({ offer = offer("hat_fail", 20), currency = "SM",
                expected_price = 20, balance = 50, owned = false, available = true, dlc_owned = true })
            fail()
            H.equal(D.purchase(plan), nil)
            H.equal(storage[D.STATE_KEY], before)
            H.equal(D.balance(), 50)
            H.equal(D.emporium_unlocked("hat_fail"), false)
        end)
        restore()
        if not ok then error(failure, 0) end
    end)

    H.test("production owns modded SM purchase and delegates official realm", function()
        local file = assert(io.open(root .. "modded_progression.lua", "rb"))
        local source = file:read("*a"); file:close()
        H.truthy(source:find("Dailies.purchase(plan)", 1, true))
        H.truthy(source:find("callback_fn(true, { granted })", 1, true))
        H.truthy(source:find("return func(self, item_id, chip_type, price, callback_fn, ...)", 1, true))
        H.equal(source:find('enqueue_api_request("PurchaseItem"', 1, true), nil)
        H.truthy(source:find('"get_peddler_stock"', 1, true))
        H.truthy(source:find('"get_filtered_items"', 1, true))
        H.truthy(source:find("_mp577_ui.with_local_ownership", 1, true))
        H.truthy(source:find('"_populate_item_widget", _mp577_ui.with_local_ownership', 1, true))
        H.truthy(source:find('"_populate_pose_item", _mp577_ui.with_local_ownership', 1, true))
        H.truthy(source:find("mp577_store_ownership_facade_restores", 1, true))
        H.truthy(source:find("Emporium.cleanup_overlay_record(mirror, record)", 1, true))
        H.truthy(source:find("official unlock was deleted or replaced", 1, true))
        H.equal(source:find("\n        offer.owned = true", 1, true), nil)
    end)

    H.test("Emporium overlay waits for peddler registration without warning probes", function()
        local file = assert(io.open(root .. "modded_progression.lua", "rb"))
        local source = file:read("*a"); file:close()
        H.truthy(source:find("backend._interfaces", 1, true))
        H.truthy(source:find("interfaces.peddler", 1, true))
        H.equal(source:find('pcall(backend.get_interface, backend, "peddler")', 1, true), nil)
    end)
end
