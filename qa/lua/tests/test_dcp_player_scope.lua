return function(H, repo_root)
    local root = repo_root .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/"
    local resolver = assert(loadfile(root .. "_dcp_portrait_resolver.lua"))()
    local file = assert(io.open(root .. "dynamic_cosmetic_portraits.lua", "rb"))
    local source = file:read("*a")
    file:close()

    local skin_set = { hud = "skin_portrait" }
    local hat_set = { hud = "hat_portrait" }
    local skins = { tracked_skin = skin_set }
    local hats = { tracked_hat = hat_set }

    H.test("DCP player portraits prefer a tracked skin over a tracked hat", function()
        H.equal(resolver.resolve_keys(
            "tracked_skin", "tracked_hat", skins, hats), skin_set)
    end)

    H.test("DCP player portraits fall back to a tracked hat", function()
        H.equal(resolver.resolve_keys(
            "untracked_skin", "tracked_hat", skins, hats), hat_set)
    end)

    H.test("DCP player portrait resolution fails closed on malformed identity", function()
        H.equal(resolver.resolve_keys(nil, nil, skins, hats), nil)
        H.equal(resolver.resolve_keys({}, "tracked_hat", skins, hats), hat_set)
        H.equal(resolver.resolve_keys("tracked_skin", nil, nil, hats), nil)
        H.equal(resolver.resolve_score_record(nil, skins, hats), nil)
    end)

    H.test("DCP player-scope production consumes one pure resolver", function()
        H.truthy(source:find(
            'scripts/mods/dynamic_cosmetic_portraits/_dcp_portrait_resolver',
            1, true))
        H.truthy(source:find('_portrait_resolver.resolve_keys(', 1, true))
        H.truthy(source:find('_portrait_resolver.resolve_score_record(', 1, true))
        H.equal(source:find("_dcp_player_scope_probe", 1, true), nil)
        H.equal(source:find("[dcp:435]", 1, true), nil)
    end)

    H.test("DCP local-player lookups are safe across title transitions", function()
        local executable = source:gsub("%-%-[^\n]*", "")
        H.truthy(source:find('local function _local_player_safe(player_manager)', 1, true))
        H.truthy(source:find('pm.local_player_safe', 1, true))
        H.truthy(source:find('_rt_register("local_player_safe_network_lifecycle_609"', 1, true))
        H.truthy(source:find('title state must yield nil', 1, true))
        H.truthy(source:find('ingame state lost player', 1, true))
        H.equal(executable:find(':local_player%(%s*%)'), nil)
    end)
end
