return function(H, repo_root)
    local economy = dofile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_economy.lua")

    H.test("CT #466 independent ledger credits and charges atomically", function()
        H.equal(economy.credit(100, 25), 125)
        H.equal(economy.credit(nil, 25.9), 25)
        local allowed, balance = economy.charge(125, 100)
        H.equal(allowed, true)
        H.equal(balance, 25)
        allowed, balance = economy.charge(25, 100)
        H.equal(allowed, false)
        H.equal(balance, 25)
        allowed, balance = economy.charge(0, -50)
        H.equal(allowed, true)
        H.equal(balance, 0)
    end)

    H.test("CT #466 weapon cost is per-bot rarity and fails closed", function()
        local costs = { deus_chest = { upgrade = {
            common = { rare = 150 },
            rare = { rare = 100 },
        } } }
        H.equal(economy.weapon_cost(costs, "upgrade", "common", "rare", 999), 150)
        H.equal(economy.weapon_cost(costs, "upgrade", "rare", "rare", 999), 100)
        H.equal(economy.weapon_cost(costs, "upgrade", "missing", "rare", 999), 999)
    end)

    H.test("CT #466 shrine and free reward costs preserve source semantics", function()
        local costs = { shop = { power_ups = { rare = 200 } } }
        H.equal(economy.shop_boon_cost(costs, "rare", 0), 200)
        H.equal(economy.shop_boon_cost(costs, "rare", 0.25), 150)
        H.equal(economy.shop_boon_cost(costs, "rare", 10), 0)
        H.equal(economy.grant_cost("boon_altar", 225), 225)
        H.equal(economy.grant_cost("cot_view_pick", 225), 0)
        H.equal(economy.grant_cost("end_of_level", 225), 0)
    end)

    H.test("CT #466 production owns every requested economy boundary", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        local owner_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_weapon_chest_owner.lua"
        local owner_file = assert(io.open(owner_path, "rb"))
        source = source .. "\n" .. owner_file:read("*a")
        owner_file:close()
        H.truthy(source:find("CT_BOT_ECONOMY_MARKER", 1, true))
        H.truthy(source:find("mod._ct_bot_economy_credit_all(self._run_state, args[1])", 1, true))
        H.truthy(source:find('mod:hook("DeusRunController", "_try_buy_power_up"', 1, true))
        H.truthy(source:find('mod:hook("DeusChestExtension", "open_chest"', 1, true))
        H.truthy(source:find("mod._ct_bot_altar_cost = _opened_cost", 1, true))
        H.truthy(source:find("mod._ct_bot_economy_charge(run_state", 1, true))
        H.truthy(source:find("mod._ct_bot_economy.weapon_cost", 1, true))
        H.truthy(source:find("bot_boon_economy_installed", 1, true))
    end)
end
