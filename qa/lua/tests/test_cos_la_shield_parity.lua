return function(Harness, repo_root)
    local policy = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_shield_parity.lua")

    Harness.test("cos LA Kruber shield catalogue is complete and unique (#266)", function()
        local expected = {
            es_1h_sword_shield = true,
            es_1h_mace_shield = true,
            es_1h_sword_shield_breton = true,
            es_deus_01 = true,
            cwv_es_axe_shield = true,
            cwv_es_longsword_shield = true,
            cwv_es_warpriest_hammer_shield = true,
        }
        local seen = {}
        for _, item_type in ipairs(policy.KRUBER_SHIELD_ITEM_TYPES) do
            Harness.truthy(expected[item_type], "unexpected Kruber shield item_type: " .. item_type)
            Harness.equal(seen[item_type], nil, "duplicate Kruber shield item_type: " .. item_type)
            seen[item_type] = true
        end
        for item_type in pairs(expected) do
            Harness.truthy(seen[item_type], "missing Kruber shield item_type: " .. item_type)
        end
    end)

    Harness.test("cos LA texture pools preserve authored shield UV families (#204)", function()
        local empire = { es_1h_mace_shield = true }
        local breton = { es_1h_sword_shield_breton = true }
        Harness.truthy(policy.add_compatible_targets("Kruber", "texture", "empire", empire))
        Harness.truthy(policy.add_compatible_targets("Kruber", "texture", "breton", breton))
        for _, item_type in ipairs(policy.KRUBER_SHIELD_FAMILIES.empire) do
            Harness.truthy(empire[item_type], "Empire-authored variant missing " .. item_type)
            Harness.equal(breton[item_type], nil,
                "Breton texture leaked onto Empire receiver " .. item_type)
        end
        Harness.truthy(breton.es_1h_sword_shield_breton)
        Harness.equal(empire.es_1h_sword_shield_breton, nil)

        local custom_unit = { es_1h_sword_shield = true }
        Harness.truthy(policy.add_compatible_targets("Kruber", "unit", "empire", custom_unit))
        for _, item_type in ipairs(policy.KRUBER_SHIELD_ITEM_TYPES) do
            Harness.truthy(custom_unit[item_type], "custom-unit variant missing " .. item_type)
        end
        local bardin = { dr_1h_axe_shield = true }
        Harness.equal(policy.add_compatible_targets("Bardin", "texture", "dwarf", bardin), false)
        Harness.truthy(bardin.dr_1h_axe_shield)
        Harness.equal(bardin.es_1h_sword_shield, nil)
    end)

    Harness.test("CWV Axe+Shield receives vanilla Empire pool before LA merge", function()
        local f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua", "rb"))
        local source = f:read("*a"); f:close()
        Harness.truthy(source:find('item_type ~= "es_1h_sword_shield_breton"', 1, true))
        Harness.truthy(source:find('left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield)', 1, true))
        Harness.truthy(source:find('if not (variant and variant.new_units) then return true end', 1, true),
            "declared LA mesh must gate texture paint as well as unit variants")
        Harness.truthy(source:find('authored_family = la_opt.authored_family', 1, true),
            "selection must retain pool provenance")
        Harness.truthy(source:find('variant_kind    = la_opt.variant_kind', 1, true),
            "selection must retain mesh ownership kind")
        Harness.truthy(source:find('_offhand_paint_mesh_ok(u, sel.la_armoury_key)', 1, true),
            "every render paint path must consume the exact mesh gate")
    end)
end
