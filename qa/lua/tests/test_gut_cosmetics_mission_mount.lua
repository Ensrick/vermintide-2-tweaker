return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local mission = read("gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_inventory.lua")
    local contracts = read("gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts.lua")
    local cosmetics = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    -- #1159: cosmetics' half of the #89 companion contract (the in-mission
    -- preview-world guard) moved verbatim out of the entry into its own owner.
    local cosmetics_view = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua")

    H.test("GUT #89 allows Cosmetics-only mission customization", function()
        H.truthy(mission:find('return in_keep or (get_mod("cosmetics_tweaker") ~= nil)', 1, true))
        H.truthy(mission:find("mod._gut89_customize_allowed = _gut_customize_allowed", 1, true))
        H.truthy(contracts:find('issue89_cosmetics_only_customize_mount', 1, true))
    end)

    H.test("GUT #89 owns both no-CIM level-free mount surfaces", function()
        H.truthy(mission:find('mod:hook("HeroWindowItemCustomization", "_create_item_preview_widget_definition"', 1, true))
        H.truthy(mission:find('mod:hook("HeroWindowItemCustomization", "_register_object_sets"', 1, true))
        H.truthy(mission:find("mod._gut89_mount_fix_active = _gut_mount_fix_active", 1, true))
        H.truthy(mission:find("mod._gut89_mount_surfaces.create_item_preview_widget_definition = true", 1, true))
        H.truthy(mission:find("mod._gut89_mount_surfaces.register_object_sets = true", 1, true))
        H.truthy(mission:find("object_sets = {}", 1, true))
        for line in mission:gmatch("[^\r\n]+") do
            local code = line:match("^%s*(.-)%s*$")
            if code:sub(1, 2) ~= "--" then
                H.equal(code:find('level_name = "levels/ui_store_preview/world"', 1, true), nil)
            end
        end
    end)

    H.test("Cosmetics #89 companion render path remains mission-aware", function()
        H.truthy(cosmetics_view:find('mod:hook_safe("HeroWindowItemCustomization", "_create_preview_widget"', 1, true))
        H.truthy(cosmetics_view:find('local store_env = "environment/ui_store_preview"', 1, true))
        H.truthy(cosmetics_view:find("if in_keep then return end", 1, true))
        -- The guard must live in exactly one place: a re-inlined copy in the entry
        -- would be a second registration on the same pair, which VMF drops.
        H.equal(cosmetics:find('"HeroWindowItemCustomization", "_create_preview_widget"', 1, true), nil)
        H.truthy(cosmetics:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle").install(mod, {', 1, true))
    end)
end
