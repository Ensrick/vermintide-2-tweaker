return function(H, repo_root)
    local Policy = dofile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_coin_pickup.lua")

    H.test("CT #331 bot coin polling mirrors vanilla Money Magnet bounds", function()
        H.equal(Policy.pickup_name, "deus_soft_currency")
        H.equal(Policy.range, 10)
        H.equal(Policy.poll_interval, 1)
        local due, next_t = Policy.poll_due(10, 9)
        H.equal(due, true)
        H.equal(next_t, 11)
        due = Policy.poll_due(10.5, 11)
        H.equal(due, false)
    end)

    H.test("CT #331 claim policy prevents bot races and rejects other pickups", function()
        H.equal(Policy.can_claim("deus_soft_currency", nil, 5), true)
        H.equal(Policy.can_claim("deus_soft_currency", 6, 5), false)
        H.equal(Policy.can_claim("deus_soft_currency", 5, 5), true)
        H.equal(Policy.can_claim("healing_draught", 0, 5), false)
        H.equal(Policy.claim_until(5), 6.5)
    end)

    H.test("CT #331 production consolidates bot features in one hook", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_blessed_bots.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find('mod:hook_safe("PlayerBotBase", "update"', 1, true))
        H.truthy(source:find('mod:get("bots_pick_up_pilgrims_coins")', 1, true))
        H.truthy(source:find('pickup_extension.pickup_name', 1, true))
        H.truthy(source:find('pcall(interactor_extension.start_interaction, interactor_extension,', 1, true))
        H.truthy(source:find('false, pickup_unit, "pickup_object", forced)', 1, true))
        local _, count = source:gsub('mod:hook_safe%("PlayerBotBase", "update"', "")
        H.equal(count, 1)
    end)

    H.test("CT #331 Bots category owns every bot-facing setting", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        local start = assert(source:find('setting_id = "bots_group"', 1, true))
        local finish = assert(source:find("-- Reworks", start, true))
        local group = source:sub(start, finish)
        for _, id in ipairs({
            "ct_blessed_bots", "bots_pick_up_pilgrims_coins", "announce_bot_boons",
            "bots_mirror_host_boons", "bots_get_random_boons",
            "bots_mirror_host_weapon_upgrades",
        }) do
            H.truthy(group:find('setting_id = "' .. id .. '"', 1, true))
        end
    end)
end
