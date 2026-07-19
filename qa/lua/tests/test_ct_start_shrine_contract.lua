return function(H, repo_root)
    local function read(path)
        local f = assert(io.open(path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    local base = repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    H.test("CT #458 start shrine crash floor prepares shop config before sync", function()
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
        local start_hook = assert(source:find('mod:hook("GameModeMapDeus", "local_player_game_starts"', 1, true))
        local prepare_at = assert(source:find("mod._ct_prepare_start_shrine, drc", start_hook, true))
        local vanilla_at = assert(source:find("func(self, player, loading_context)", prepare_at, true))
        local host_publish_at = assert(source:find("ss:set_server(ss:get_key(\"state\"), 3)", vanilla_at, true))

        H.truthy(prepare_at < vanilla_at,
            "#458: every peer must prepare dlc_morris_map shop config before vanilla full_sync")
        H.truthy(vanilla_at < host_publish_at,
            "#458: host must publish SHOP only after local prep and vanilla startup")
        H.truthy(source:find("mod._ct_start_shrine_config_valid(cfg)", vanilla_at, true),
            "#458: SHOP publication must be gated by validated config")
        H.truthy(source:find("DeusShopView\", \"start\"", 1, true),
            "#458: final DeusShopView.start nil-config guard must stay installed")
        H.truthy(source:find("start shrine view blocked: config unavailable", 1, true),
            "#458: fail-closed guard needs a bounded diagnostic row")
    end)

    H.test("CT #458 start shrine keeps graph identity and uses vanilla dlc_morris_map key", function()
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
        H.truthy(source:find('settings.shop_types["dlc_morris_map"]', 1, true))
        H.truthy(source:find('node.level ~= "dlc_morris_map"', 1, true))
        H.truthy(source:find("handle_shrine_entered", 1, true),
            "#458 design note should keep the no-node-mutation boundary explicit")
        H.equal(source:find('node.node_type = "shop"', 1, true), nil,
            "#458 must not mutate the start node into a shop node")
    end)

    H.test("CT #458 incomplete price and pick-limit scope stays visibly deferred", function()
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
        local data = read(base .. "chaos_wastes_tweaker_dev_data.lua")
        local loc = read(base .. "chaos_wastes_tweaker_dev_localization.lua")

        H.truthy(source:find("Per-shrine COST multiplier and a PICK LIMIT are deferred", 1, true),
            "#458 issue state depends on deferred cost/limit scope being explicit")
        H.equal(data:find("ct_start_shrine_cost_multiplier", 1, true), nil,
            "#458 cost multiplier must not appear as a dead setting before runtime exists")
        H.equal(data:find("ct_start_shrine_pick_limit", 1, true), nil,
            "#458 pick limit must not appear as a dead setting before runtime exists")
        H.equal(loc:find("ct_start_shrine_cost_multiplier", 1, true), nil)
        H.equal(loc:find("ct_start_shrine_pick_limit", 1, true), nil)
    end)
end
