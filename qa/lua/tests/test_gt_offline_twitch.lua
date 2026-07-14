return function(H, repo_root)
    local policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_offline_twitch_policy.lua"
    local P = assert(loadfile(policy_path))()

    H.test("GT #333 classifies native Twitch template families", function()
        H.equal(P.category("twitch_give_potion", {}), "items")
        H.equal(P.category("twitch_spawn_skaven", {}), "spawns")
        H.equal(P.category("dlc_boss", { boss = true }), "spawns")
        H.equal(P.category("curse", { description = "description_mutator_curse" }), "mutators")
        H.equal(P.category("ordinary_vote", {}), "buffs")
        H.equal(P.category(nil, nil), "buffs")
    end)

    H.test("GT #333 category allow-list fails closed per disabled family", function()
        local allowed = { buffs = true, items = false, mutators = true, spawns = false }
        H.equal(P.is_allowed("twitch_give_bomb", {}, allowed), false)
        H.equal(P.is_allowed("twitch_spawn_horde", {}, allowed), false)
        H.equal(P.is_allowed("curse", { text = "display_name_mutator_curse" }, allowed), true)
        H.equal(P.is_allowed("twitch_vote_speed", {}, allowed), true)
        H.equal(P.is_allowed("anything", {}, nil), true)
        H.equal(P.any_allowed(allowed), true)
        H.equal(P.any_allowed({ buffs = false, items = false, mutators = false, spawns = false }), false)
    end)

    H.test("GT #333 owns one native whitelist gate and no RPC schema", function()
        local runtime_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_offline_twitch.lua"
        local f = assert(io.open(runtime_path, "rb"))
        local runtime = f:read("*a")
        f:close()
        local _, whitelist_hooks = runtime:gsub('mod:hook%("TwitchGameMode", "_in_whitelist"', "")
        local _, activate_hooks = runtime:gsub('mod:hook%("TwitchManager", "activate_twitch_game_mode"', "")
        H.equal(whitelist_hooks, 1)
        H.equal(activate_hooks, 1)
        H.truthy(runtime:find("game_mode_class:new(self)", 1, true) ~= nil)
        H.truthy(runtime:find("_gt333_offline_active", 1, true) ~= nil)
        H.equal(runtime:find("network_register", 1, true), nil)
        H.equal(runtime:find("mod:network_register", 1, true), nil)
    end)
end
