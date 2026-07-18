return function(H, repo_root)
    local path = repo_root
        .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/_dcp_score_record.lua"
    local score_record = assert(loadfile(path))()
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
        local resolved = score_record.resolve_portrait_set({
            hero_skin = "tracked_skin",
            hat = { item_name = "tracked_hat" },
        }, skins, hats)
        H.equal(resolved, skin_set)
    end)

    H.test("DCP score records fall back to the recorded hat (#435)", function()
        local resolved = score_record.resolve_portrait_set({
            hero_skin = "untracked_skin",
            hat = { item_name = "tracked_hat" },
        }, skins, hats)
        H.equal(resolved, hat_set)
    end)

    H.test("DCP score records fail closed for missing cosmetics (#435)", function()
        H.equal(score_record.resolve_portrait_set({
            hero_skin = "untracked_skin",
            hat = { item_name = "untracked_hat" },
        }, skins, hats), nil)
        H.equal(score_record.resolve_portrait_set(nil, skins, hats), nil)
        H.equal(score_record.resolve_portrait_set({}, nil, hats), nil)
    end)

    H.test("DCP score evidence distinguishes bot and remote subjects (#435)", function()
        H.equal(score_record.subject({ is_player_controlled = false, local_player_id = 6 }), "bot:6")
        H.equal(score_record.subject({ is_player_controlled = true, local_player_id = 1 }), "remote:1")
        H.equal(score_record.subject(nil), "unknown")
    end)

    H.test("DCP score hook consumes the record resolver and readiness gate (#435)", function()
        H.truthy(main_source:find(
            '_score_record.resolve_portrait_set(', 1, true))
        H.truthy(main_source:find(
            '_scope_evidence("score", _score_record.subject(rec)', 1, true))
        local hook_start = assert(main_source:find(
            'mod:hook_safe("EndViewStateScore", "_setup_player_scores"', 1, true))
        local gate = assert(main_source:find(
            'if not _check_portrait_materials_ready() then return end', hook_start, true))
        local resolver = assert(main_source:find(
            '_score_record.resolve_portrait_set(', hook_start, true))
        H.truthy(gate < resolver, "material readiness must gate score assignment")
    end)
end
