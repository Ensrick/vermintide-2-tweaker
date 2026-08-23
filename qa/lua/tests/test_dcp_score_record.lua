return function(H, repo_root)
    local path = repo_root
        .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/_dcp_portrait_resolver.lua"
    local portrait_resolver = assert(loadfile(path))()
    local main_path = repo_root
        .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua"
    local main_file = assert(io.open(main_path, "rb"))
    local main_source = main_file:read("*a")
    main_file:close()

    local skin_set = { hud = "skin_portrait" }
    local hat_set = { hud = "hat_portrait" }
    local skins = { tracked_skin = skin_set }
    local hats = { tracked_hat = hat_set }

    H.test("DCP score records prefer a tracked skin over the hat (#435)", function()
        local resolved = portrait_resolver.resolve_score_record({
            hero_skin = "tracked_skin",
            hat = { item_name = "tracked_hat" },
        }, skins, hats)
        H.equal(resolved, skin_set)
    end)

    H.test("DCP score records fall back to the recorded hat (#435)", function()
        local resolved = portrait_resolver.resolve_score_record({
            hero_skin = "untracked_skin",
            hat = { item_name = "tracked_hat" },
        }, skins, hats)
        H.equal(resolved, hat_set)
    end)

    H.test("DCP score records fail closed for missing cosmetics (#435)", function()
        H.equal(portrait_resolver.resolve_score_record({
            hero_skin = "untracked_skin",
            hat = { item_name = "untracked_hat" },
        }, skins, hats), nil)
        H.equal(portrait_resolver.resolve_score_record(nil, skins, hats), nil)
        H.equal(portrait_resolver.resolve_score_record({}, nil, hats), nil)
    end)

    H.test("DCP score hook consumes the record resolver and readiness gate (#435)", function()
        H.truthy(main_source:find(
            '_portrait_resolver.resolve_score_record(', 1, true))
        local hook_start = assert(main_source:find(
            'mod:hook_safe("EndViewStateScore", "_setup_player_scores"', 1, true))
        local gate = assert(main_source:find(
            'if not _check_portrait_materials_ready() then return end', hook_start, true))
        local resolver = assert(main_source:find(
            '_portrait_resolver.resolve_score_record(', hook_start, true))
        H.truthy(gate < resolver, "material readiness must gate score assignment")
    end)
end
