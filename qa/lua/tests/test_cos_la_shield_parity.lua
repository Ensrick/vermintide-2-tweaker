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
        -- #200 final-two options on Spear+Shield/Mace+Shield are texture
        -- variants with explicit canonical models.  They own their UV surface
        -- and therefore follow the same safe fan-out as a unit variant.
        local canonical_texture = {}
        Harness.truthy(policy.add_compatible_targets(
            "Kruber", "texture", "empire", canonical_texture, true))
        Harness.truthy(canonical_texture.es_deus_01,
            "canonical LA model missing Spear+Shield")
        Harness.truthy(canonical_texture.es_1h_mace_shield,
            "canonical LA model missing Mace+Shield")
        Harness.truthy(canonical_texture.cwv_es_axe_shield,
            "canonical LA model missing compatible CWV shield family")
        local bardin = { dr_1h_axe_shield = true }
        Harness.equal(policy.add_compatible_targets("Bardin", "texture", "dwarf", bardin), false)
        Harness.truthy(bardin.dr_1h_axe_shield)
        Harness.equal(bardin.es_1h_sword_shield, nil)
    end)

    Harness.test("cos LA magic shield receivers are exact and family-safe (#373)", function()
        local bret_magic = "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01_magic_01"
        local bret_base = "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01"
        local empire_magic = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01"
        local empire_base = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04"
        local spear_magic = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic"
        local spear_base = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02"

        Harness.equal(policy.magic_texture_receiver("breton", bret_magic), bret_base)
        Harness.equal(policy.magic_texture_receiver("empire", empire_magic), empire_base)
        Harness.equal(policy.magic_texture_receiver("empire", spear_magic), spear_base)
        Harness.equal(policy.magic_texture_receiver("empire", bret_magic), nil,
            "Breton magic mesh must never receive an Empire texture")
        Harness.equal(policy.magic_texture_receiver("breton", empire_magic), nil,
            "Empire magic mesh must never receive a Breton texture")
        Harness.equal(policy.magic_texture_receiver("breton", bret_base), nil,
            "ordinary paintable shields must not be replaced")
        Harness.equal(policy.magic_texture_receiver("breton", "units/unknown_magic"), nil,
            "receiver policy must not guess from a generic magic suffix")
    end)

    Harness.test("cos LA weave/runed receiver rows cover every shield family (#373)", function()
        -- Complete decompile-derived inventory (scripts/settings skin tables).
        -- Every magic/runed shield unit maps to its same-directory plain
        -- sibling within its authored family.
        local expected = {
            breton = {
                ["units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01_magic_01"] =
                    "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01",
                ["units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01"] =
                    "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02",
            },
            empire = {
                ["units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01"] =
                    "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",
                ["units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic"] =
                    "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02",
                ["units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01"] =
                    "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
                ["units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01"] =
                    "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",
                ["units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_runed"] =
                    "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02",
                ["units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03_runed"] =
                    "units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03",
            },
            dwarf = {
                ["units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01"] =
                    "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04",
                ["units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01"] =
                    "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02",
                ["units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_e_shield_02_runed_01"] =
                    "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_e_shield_02",
                ["units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01"] =
                    "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05",
                ["units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_e_shield_05_runed_01"] =
                    "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_e_shield_05",
            },
            wood_elf = {
                ["units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01"] =
                    "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02",
                ["units/weapons/player/wpn_we_shield_01/wpn_we_shield_01_runed_01"] =
                    "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01",
            },
            imperial = {
                ["units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic"] =
                    "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1",
                ["units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed"] =
                    "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1",
            },
        }
        for family, rows in pairs(expected) do
            for unit, receiver in pairs(rows) do
                Harness.equal(policy.magic_texture_receiver(family, unit), receiver,
                    family .. " row missing/wrong for " .. unit)
                -- Same-directory suffix-strip invariant: geometrically
                -- identical receiver, never a cross-mesh guess.
                local dir = unit:match("^(.*)/[^/]+$")
                Harness.equal(receiver:match("^(.*)/[^/]+$"), dir,
                    "receiver left its unit directory: " .. receiver)
            end
        end
        -- Cross-family isolation stays absolute (the #204/#266 rule).
        Harness.equal(policy.magic_texture_receiver("empire",
            "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01"), nil)
        Harness.equal(policy.magic_texture_receiver("dwarf",
            "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic"), nil)
    end)

    Harness.test("cos LA receiver-gap validator flags dead-ends and passes covered rows (#373)", function()
        local family_for_item_type = function(item_type)
            return ({ es_1h_sword_shield_breton = "breton",
                      es_1h_mace_shield = "empire" })[item_type]
        end
        local item_type_for_skin = function(skin_key)
            local prefix = tostring(skin_key):match("^(.-)_skin_")
            if prefix == "es_sword_shield_breton" then
                return "es_1h_sword_shield_breton"
            end
            return prefix
        end
        local skins = {
            -- Covered weave row: no gap.
            es_sword_shield_breton_skin_04_magic_01 = {
                left_hand_unit = "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01_magic_01",
            },
            -- Magic unit with NO receiver row in its family: flagged.
            es_1h_mace_shield_skin_09_magic_09 = {
                left_hand_unit = "units/weapons/player/wpn_fake/wpn_fake_magic_09",
            },
            -- Plain unit: never flagged.
            es_1h_mace_shield_skin_02 = {
                left_hand_unit = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
            },
            -- Magic unit outside any mapped family: not this validator's call.
            wh_flail_skin_01_magic_01 = {
                left_hand_unit = "units/weapons/player/wpn_x/wpn_x_magic_01",
            },
            -- data-wrapped skin records resolve identically.
            es_1h_mace_shield_skin_10_runed_09 = {
                data = { left_hand_unit = "units/weapons/player/wpn_fake2/wpn_fake2_runed_09" },
            },
        }
        local gaps = policy.find_receiver_gaps(skins, family_for_item_type, item_type_for_skin)
        Harness.equal(#gaps, 2)
        Harness.equal(gaps[1].skin, "es_1h_mace_shield_skin_09_magic_09")
        Harness.equal(gaps[1].family, "empire")
        Harness.equal(gaps[2].skin, "es_1h_mace_shield_skin_10_runed_09")
        Harness.equal(policy.find_receiver_gaps(nil, family_for_item_type, item_type_for_skin)[1], nil)
    end)

    Harness.test("CWV Axe+Shield receives vanilla Empire pool before LA merge", function()
        local f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua", "rb"))
        local source = f:read("*a"); f:close()
        Harness.truthy(source:find('item_type ~= "es_1h_sword_shield_breton"', 1, true))
        Harness.truthy(source:find('left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield)', 1, true))
        Harness.truthy(source:find('if not variant.new_units then', 1, true),
            "pure texture variants must pass through the magic-receiver gate")
        Harness.truthy(source:find('return actual == tostring(variant.new_units[1])', 1, true),
            "declared LA mesh must gate texture paint as well as unit variants")
        Harness.truthy(source:find('authored_family = la_opt.authored_family', 1, true),
            "selection must retain pool provenance")
        Harness.truthy(source:find('variant_kind    = la_opt.variant_kind', 1, true),
            "selection must retain mesh ownership kind")
        Harness.truthy(source:find('_offhand_paint_mesh_ok(u, sel.la_armoury_key,', 1, true),
            "every render paint path must consume the exact mesh gate")
        Harness.truthy(source:find('proven_unit_paths and proven_unit_paths[unit_index]', 1, true),
            "loot previews must pass their exact queued hand path to the mesh gate")
    end)
end
