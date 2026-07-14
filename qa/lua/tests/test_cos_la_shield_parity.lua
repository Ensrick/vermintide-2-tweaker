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

    Harness.test("cos LA parity expands every Kruber variant identically (#266)", function()
        local empire = { es_1h_mace_shield = true }
        local breton = { es_1h_sword_shield_breton = true }
        Harness.truthy(policy.add_character_parity("Kruber", empire))
        Harness.truthy(policy.add_character_parity("Kruber", breton))
        for _, item_type in ipairs(policy.KRUBER_SHIELD_ITEM_TYPES) do
            Harness.truthy(empire[item_type], "Empire-authored variant missing " .. item_type)
            Harness.truthy(breton[item_type], "Breton-authored variant missing " .. item_type)
        end
        local bardin = { dr_1h_axe_shield = true }
        Harness.equal(policy.add_character_parity("Bardin", bardin), false)
        Harness.truthy(bardin.dr_1h_axe_shield)
        Harness.equal(bardin.es_1h_sword_shield, nil)
    end)
end
