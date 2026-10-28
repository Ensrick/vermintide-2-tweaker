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

    local function pack(...) return { n = select("#", ...), ... } end
    local function production_source()
        local file = assert(io.open(root .. "modded_progression.lua", "rb"))
        local source = file:read("*a"); file:close()
        return (source:gsub("\r\n", "\n"))
    end
    local function section(source, first, last)
        local at = assert(source:find(first, 1, true), first)
        local stop = assert(source:find(last, at + #first, true), last)
        H.equal(source:find(first, at + #first, true), nil, "duplicate #577 source owner")
        return source:sub(at, stop - 1)
    end
    local function installed_exchange(stage, options, source)
        options, source = options or {}, source or production_source()
        -- Execute the complete production helper, installed hook and authority
        -- query. Only ledger persistence, overlay sync and native delegation
        -- are recording collaborators; this does not prove a live item grant.
        local query = section(source, "local function _progression_realm(",
            "local function _route_store_login_claim_for_realm(")
        local transaction = section(source, "local function _mp577_local_exchange(",
            '_rt_register("mp577_backend_free_emporium_purchase"')
        local s = { receipts = {}, callbacks = {}, purchase_calls = 0, overlay_calls = 0,
            native_calls = 0, fallback_calls = 0, owner = {}, peddler = {}, result = nil }
        s.peddler._peddler_stock = stage == "plan_reject" and {} or { offer("receipt_hat", 25) }
        s.peddler._backend_mirror = {}
        function s.owner:hook(class, method, fn)
            H.equal(class, "BackendInterfacePeddlerPlayFab")
            H.equal(method, "exchange_chips"); H.equal(s.hook, nil)
            s.hook = fn
        end
        local env = setmetatable({}, { __index = _G }); env._G = env
        env.MODDED_REALM = options.realm
        if options.realm == nil then env.MODDED_REALM = true end
        env.Managers = false -- never inherit a live manager through __index
        env.printf = function(format, ...)
            s.receipts[#s.receipts + 1] = { format = format, args = pack(...) }
            if options.print_error then error(options.print_error) end
        end
        local dailies = {
            REWARD_KIND = "SM", balance = function() return 60 end,
            purchase = function(plan)
                s.purchase_calls = s.purchase_calls + 1; s.plan = plan
                if not plan or stage == "purchase_reject" then return nil, "persist_refused" end
                return plan.item, 35
            end,
        }
        local loader = assert(loadstring("return function(mod, _is_mp_realm, Dailies, Emporium, _mp577_ui, _mp577_mirror_ready, _mp577_sync_overlay)\n"
            .. query .. "\n" .. transaction .. "\nend", "@actual-mp577-helper-and-hook"))
        setfenv(loader, env)
        loader()(s.owner, function() s.fallback_calls = s.fallback_calls + 1; return false end,
            dailies, Policy, { local_owned = function() return false end },
            function(mirror) H.equal(mirror, s.peddler._backend_mirror); return true end,
            function(peddler)
                H.equal(peddler, s.peddler); s.overlay_calls = s.overlay_calls + 1
                return options.overlay_ready ~= false, "mirror_pending"
            end)
        H.equal(type(s.hook), "function")
        local callback
        if not options.no_callback then
            callback = function(...)
                s.callbacks[#s.callbacks + 1] = pack(...)
                if options.callback_error then error(options.callback_error) end
            end
        end
        s.callback = callback
        s.ok, s.failure = pcall(function()
            s.result = pack(s.hook(function(...)
                s.native_calls = s.native_calls + 1; s.native_args = pack(...)
                return "native", nil, s, nil
            end, s.peddler, "receipt_hat", options.currency or "SM", 25, callback, "tail"))
        end)
        return s
    end
    local function assert_attempt(stage, options, source)
        options = options or {}
        local s = installed_exchange(stage, options, source)
        local committed = stage == "commit"
        -- These SAME oracles are used by the deliberate source controls below.
        H.equal(#s.receipts, 1, "#577 once-per-attempt receipt count")
        H.equal(s.native_calls, 0, "#577 local attempt delegated to native")
        H.equal(s.purchase_calls, stage == "plan_reject" and 0 or 1, "#577 no post-plan-rejection purchase")
        H.equal(s.overlay_calls, committed and 1 or 0, "#577 no post-rejection overlay")
        H.equal(#s.callbacks, options.no_callback and 0 or 1, "#577 once-per-attempt callback count")
        H.equal(s.fallback_calls, 0)
        local receipt = s.receipts[1]
        H.equal(receipt.format, committed
            and "[mp:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none"
            or "[mp:577] purchase_rejected item=%s reason=%s backend=none")
        H.equal(receipt.args[1], "receipt_hat")
        H.equal(receipt.args.n, committed and 4 or 2)
        if committed then
            H.equal(receipt.args[2], 25); H.equal(receipt.args[3], 35)
            H.equal(receipt.args[4], options.overlay_ready == false and "mirror_pending" or "ready")
            H.equal(s.owner._mp577_last_purchase.item_key, "receipt_hat")
            H.equal(s.owner._mp577_last_purchase.backend_id, s.plan.item.ItemInstanceId)
            H.equal(s.owner._mp577_last_purchase.balance, 35)
            H.equal(s.owner._mp577_last_purchase.overlaid, options.overlay_ready ~= false)
        else
            H.equal(receipt.args[2], stage == "plan_reject" and "offer_unavailable" or "persist_refused")
            H.equal(s.owner._mp577_last_purchase, nil)
        end
        if not options.no_callback then
            H.equal(s.callbacks[1][1], committed)
            H.equal(s.callbacks[1].n, committed and 2 or 1)
            if committed then H.equal(#s.callbacks[1][2], 1); H.equal(s.callbacks[1][2][1], s.plan.item) end
        end
        if options.callback_error then
            H.equal(s.ok, false, "#577 callback throw was swallowed")
            H.equal(s.failure, options.callback_error, "#577 callback error identity")
        else
            H.equal(s.ok, true, "#577 actual helper/hook execution failed")
            H.equal(s.result.n, 0, "#577 local helper fell through to denial")
        end
        return s
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

    for _, name in ipairs({ "plan_reject", "purchase_reject", "commit" }) do
        local stage = name
        H.test("#577 actual helper and hook emits one terminal receipt " .. stage, function()
            assert_attempt(stage)
        end)
        H.test("#577 actual helper receipt survives absent callback " .. stage, function()
            assert_attempt(stage, { no_callback = true })
        end)
        H.test("#577 actual helper callback throw stays once and exact " .. stage, function()
            assert_attempt(stage, { callback_error = {} })
        end)
    end
    H.test("#577 actual helper pending overlay still has one committed terminal", function()
        assert_attempt("commit", { overlay_ready = false })
    end)
    H.test("#577 actual helper receipt logger throw cannot repeat callback", function()
        assert_attempt("commit", { print_error = {} })
    end)
    H.test("#577 actual installed hook preserves official tuple without local receipt", function()
        local s = installed_exchange("commit", { realm = false })
        H.equal(s.ok, true); H.equal(s.native_calls, 1); H.equal(#s.receipts, 0)
        H.equal(s.fallback_calls, 0)
        H.equal(s.purchase_calls, 0); H.equal(s.overlay_calls, 0); H.equal(#s.callbacks, 0)
        H.equal(s.result.n, 4); H.equal(s.result[1], "native"); H.equal(s.result[2], nil)
        H.equal(s.result[3], s); H.equal(s.result[4], nil)
        H.equal(s.native_args.n, 6); H.equal(s.native_args[1], s.peddler)
        H.equal(s.native_args[2], "receipt_hat"); H.equal(s.native_args[3], "SM")
        H.equal(s.native_args[4], 25); H.equal(s.native_args[5], s.callback)
        H.equal(s.native_args[6], "tail")
    end)
    H.test("#577 actual installed hook refuses unsupported currency without transaction receipt", function()
        local s = installed_exchange("commit", { currency = "VS" })
        H.equal(s.ok, true); H.equal(s.native_calls, 0); H.equal(#s.receipts, 0)
        H.equal(s.fallback_calls, 0)
        H.equal(s.purchase_calls, 0); H.equal(s.overlay_calls, 0)
        H.equal(#s.callbacks, 1); H.equal(s.callbacks[1].n, 1); H.equal(s.callbacks[1][1], false)
        H.equal(s.result.n, 1); H.equal(s.result[1], nil)
    end)
    local terminal_controls = {
        { name = "plan return", stage = "plan_reject", oracle = "#577 once-per-attempt receipt count",
            from = "tostring(item_id), tostring(reason))\n        if callback_fn then callback_fn(false) end\n        return",
            to = "tostring(item_id), tostring(reason))\n        if callback_fn then callback_fn(false) end" },
        { name = "purchase return", stage = "purchase_reject", oracle = "#577 no post-rejection overlay",
            from = "tostring(item_id), tostring(balance_or_reason))\n        if callback_fn then callback_fn(false) end\n        return",
            to = "tostring(item_id), tostring(balance_or_reason))\n        if callback_fn then callback_fn(false) end" },
        { name = "hook return", stage = "commit", oracle = "#577 once-per-attempt callback count",
            from = "return _mp577_local_exchange(self, item_id, price, callback_fn)",
            to = "_mp577_local_exchange(self, item_id, price, callback_fn)" },
        { name = "duplicate committed receipt", stage = "commit", oracle = "#577 once-per-attempt receipt count",
            from = 'pcall(printf, "[mp:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none",',
            to = 'pcall(printf, "[mp:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none"); pcall(printf, "[mp:577] purchase_committed item=%s price=%d balance=%d overlay=%s backend=none",' },
    }
    for _, spec in ipairs(terminal_controls) do
        local control = spec
        H.test("#577 same terminal oracle rejects source control " .. control.name, function()
            local source = production_source()
            local at = assert(source:find(control.from, 1, true), control.name)
            H.equal(source:find(control.from, at + #control.from, true), nil, "ambiguous terminal control")
            local changed = source:sub(1, at - 1) .. control.to .. source:sub(at + #control.from)
            local ok, failure = pcall(assert_attempt, control.stage, nil, changed)
            H.equal(ok, false, "#577 control escaped the unchanged terminal oracle")
            H.truthy(tostring(failure):find(control.oracle, 1, true), "#577 control failed outside its terminal oracle")
        end)
    end

    H.test("Emporium overlay waits for peddler registration without warning probes", function()
        local file = assert(io.open(root .. "modded_progression.lua", "rb"))
        local source = file:read("*a"); file:close()
        H.truthy(source:find("backend._interfaces", 1, true))
        H.truthy(source:find("interfaces.peddler", 1, true))
        H.equal(source:find('pcall(backend.get_interface, backend, "peddler")', 1, true), nil)
    end)
end
