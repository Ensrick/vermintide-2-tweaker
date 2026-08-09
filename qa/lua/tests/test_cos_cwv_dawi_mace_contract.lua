return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_cwv_family_contract.lua")

    H.test("Dawi Mace family has stable item and skin-table identities", function()
        for _, key in ipairs({
            "cwv_dr_dawi_mace",
            "cwv_dr_dawi_dual_maces",
            "cwv_dr_dawi_mace_shield",
        }) do
            local family = policy.get(key)
            H.truthy(family, key .. " contract missing")
            H.equal(family.item_type, key)
            H.equal(family.skin_table, key .. "_skins")
            H.equal(family.primary_source, "dr_1h_hammer")
        end
    end)

    H.test("Dawi Dual Maces keep primary icon ownership and independent hands", function()
        local dual = policy.dual_sources().cwv_dr_dawi_dual_maces
        H.equal(policy.icon_ownership("cwv_dr_dawi_dual_maces"), "primary")
        H.equal(dual.right_hand_unit.matching_item_key, "dr_1h_hammer")
        H.equal(dual.left_hand_unit.matching_item_key, "dr_1h_hammer")
        H.equal(dual.right_hand_unit.unit_field, "right_hand_unit")
        H.equal(dual.left_hand_unit.unit_field, "right_hand_unit")
        H.truthy(dual.right_hand_unit ~= dual.left_hand_unit,
            "hand records must remain independently addressable")
    end)

    H.test("Dawi Mace and Shield delegates icon and pool ownership to shield", function()
        H.equal(policy.icon_ownership("cwv_dr_dawi_mace_shield"), "shield")
        H.equal(policy.shield_pool_source("cwv_dr_dawi_mace_shield"),
            "dr_1h_axe_shield")
        H.equal(policy.dual_sources().cwv_dr_dawi_mace_shield, nil)
    end)

    H.test("Dawi appearance contract reuses canonical Cosmetics registries", function()
        local path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local catalog = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_catalog.lua", "rb"))
        source = source .. catalog:read("*a")
        catalog:close()
        H.truthy(source:find("CWV_FAMILY_CONTRACT.dual_sources()", 1, true))
        H.truthy(source:find("CWV_FAMILY_CONTRACT.shield_pool_source", 1, true))
        H.equal(source:find('mod:network_register("cos_dawi', 1, true), nil)
        H.equal(source:find('mod:hook("Dawi', 1, true), nil)
    end)
end
