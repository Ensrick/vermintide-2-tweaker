return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local main = read(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua")
    local data = read(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants_data.lua")
    local atlas = read(repo_root
        .. "/character_weapon_variants/materials/character_weapon_variants/cwv_weapon_icons.lua")

    local icon_pairs = {
        icon_axe_hatchet_t2_magic_01 = "icon_axe_hatchet_t2_magic_01_dual_cwv",
        icon_wh_1h_axe_skin_06_magic_02 = "icon_wh_1h_axe_skin_06_magic_02_dual_cwv",
        icon_wpn_axe_02_t1 = "icon_wpn_axe_02_t1_dual_cwv",
        icon_wpn_axe_02_t2 = "icon_wpn_axe_02_t2_dual_cwv",
        icon_wpn_axe_02_t2_runed_06 = "icon_wpn_axe_02_t2_runed_06_dual_cwv",
        icon_wpn_axe_03_t1 = "icon_wpn_axe_03_t1_dual_cwv",
        icon_wpn_axe_03_t2 = "icon_wpn_axe_03_t2_dual_cwv",
        icon_wpn_axe_hatchet_t1 = "icon_wpn_axe_hatchet_t1_dual_cwv",
        icon_wpn_axe_hatchet_t2 = "icon_wpn_axe_hatchet_t2_dual_cwv",
    }

    H.test("CWV Dual Axes has a packaged atlas entry for every primary axe icon", function()
        for source_icon, dual_icon in pairs(icon_pairs) do
            H.truthy(main:find(source_icon .. ' = "' .. dual_icon .. '"', 1, true),
                "missing primary icon mapping: " .. source_icon)
            H.truthy(atlas:find(dual_icon .. " = {", 1, true),
                "missing atlas entry: " .. dual_icon)
        end
        H.truthy(data:find('"cwv_weapon_icons"', 1, true))
        H.truthy(data:find('"hero_view", "materials/character_weapon_variants/cwv_weapon_icons"', 1, true))
    end)

    H.test("CWV Dual Axes base and generated skins use primary-owned paired icons", function()
        local _, base_count = main:gsub(
            'inventory_icon  = "icon_wpn_axe_hatchet_t1_dual_cwv"', "")
        H.equal(base_count, 2, "both Kruber and Saltzpyre base items need the paired icon")
        H.truthy(main:find("local dual_inventory_icon = dual_inventory_icons[source.inventory_icon]", 1, true))
        H.truthy(main:find("inventory_icon    = dual_inventory_icon", 1, true))
        H.truthy(main:find("inventory_icon  = dual_inventory_icon", 1, true))
        H.truthy(main:find("dual-axes primary icon mismatch", 1, true))
    end)
end
