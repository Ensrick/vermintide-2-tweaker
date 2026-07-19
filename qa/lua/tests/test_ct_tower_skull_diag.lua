return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local diag = read("_ct_diag_skull52.lua")
    local entry = read("chaos_wastes_tweaker_dev.lua")

    H.test("CT #52 Tower skull diagnostic is source-backed, not pickup-backed", function()
        H.truthy(diag:find('TARGET_LEVEL = "dlc_wizards_tower"', 1, true))
        H.truthy(diag:find("flow_callback_on_tower_skull_found", 1, true))
        H.truthy(diag:find("on_tower_skull_found", 1, true))
        H.truthy(diag:find('if not rawget(_G, "_ct_skull52_flow_wrapped") then M.install() end', 1, true))
        H.equal(diag:find("Pickups.level_events.gargoyle_head", 1, true), nil)
        H.equal(diag:find("mission_restore_the_gargoyle_heads", 1, true), nil)
        H.truthy(diag:find("not a guessed", 1, true))
    end)

    H.test("CT #52 object-set census records Adventure-vs-Deus comparison fields", function()
        for _, needle in ipairs({
            "mode=%s key=%s base=%s level_name=%s object_sets=%d spawned=%d cap=%d",
            "source=GameModeHelper.get_object_sets",
            "set=%s spawned=%s units=%d kind=%s suspect=%d",
            "LevelResource.unit_data",
            "unit_sample level_name=%s set=%s index=%s data=%s",
            "injected_base_from_key",
        }) do
            H.truthy(diag:find(needle, 1, true), "missing #52 diagnostic field: " .. needle)
        end
    end)

    H.test("CT #52 diagnostic is bounded, deduplicated, and log-only", function()
        H.truthy(diag:find("local RECORD_CAP = 160", 1, true))
        H.truthy(diag:find("local SAMPLE_CAP_PER_SET = 4", 1, true))
        H.truthy(diag:find("records >= RECORD_CAP or seen[key]", 1, true))
        H.truthy(diag:find("[ct:skull52]", 1, true))
        H.equal(diag:find("mod:echo", 1, true), nil, "diagnostic must not pollute chat")
        H.equal(diag:find("mod:command", 1, true), nil, "diagnostic must not require a command")
    end)

    H.test("CT #52 diagnostic is modular and the #156 behavior hook remains single-owner", function()
        H.truthy(entry:find('mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_diag_skull52")', 1, true))
        H.truthy(entry:find("pcall(mod._ct_diag_skull52.install)", 1, true))
        H.truthy(entry:find("pcall(mod._ct_diag_skull52.census, level_name, game_mode_key,", 1, true))
        H.truthy(entry:find('spawned_object_sets[#spawned_object_sets + 1] = "adventure"', 1, true))
        H.equal(entry:find("collectibles are the `gargoyle_head`", 1, true), nil)
    end)
end
