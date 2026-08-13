return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_trait_slot_policy.lua")

    H.test("CIM CW trait policy classifies exact vanilla category families", function()
        for _, category in ipairs({
            "deus_melee", "deus_shield_melee", "deus_heavy_melee",
        }) do
            H.equal(policy.category_slot(category), "melee", category)
        end
        for _, category in ipairs({
            "deus_ranged", "deus_ranged_ammo", "deus_ranged_heat",
            "ranged_energy", "deus_ranged_energy", "deus_trollhammer_torpedo",
        }) do
            H.equal(policy.category_slot(category), "ranged", category)
        end
    end)

    H.test("CIM CW trait policy rejects adventure, accessory, and lookalike categories", function()
        for _, category in ipairs({
            "melee", "ranged", "necklace", "charm", "trinket",
            "deus_unknown", "trollhammer", "some_ranged_energy_variant",
        }) do
            H.equal(policy.category_slot(category), nil, category)
        end
        H.equal(policy.category_matches_slot("deus_melee", nil), false)
        H.equal(policy.category_matches_slot("deus_ranged", "necklace"), false)
    end)

    H.test("CIM CW trait family preserves shared boons without cross-slot exclusives", function()
        local pools = {
            deus_melee = { "shared", "melee_only" },
            deus_ranged = { "shared", "ranged_only" },
        }
        local function collect(slot_type)
            local out = {}
            for category, traits in pairs(pools) do
                if policy.category_matches_slot(category, slot_type) then
                    for _, trait in ipairs(traits) do out[trait] = true end
                end
            end
            return out
        end
        local melee, ranged = collect("melee"), collect("ranged")
        H.truthy(melee.shared)
        H.truthy(ranged.shared)
        H.truthy(melee.melee_only)
        H.equal(melee.ranged_only, nil)
        H.truthy(ranged.ranged_only)
        H.equal(ranged.melee_only, nil)
    end)

    H.test("CIM #1122 independently detects unmapped boon-bearing families", function()
        local traits = {
            shared_boon = { crafting_disabled = true },
            new_boon = { crafting_disabled = true },
            adventure_trait = { crafting_disabled = false },
        }
        local combinations = {
            deus_melee = { { "shared_boon" } },
            z_new_family = { { "new_boon" } },
            a_new_family = { { "shared_boon" } },
            adventure_family = { { "adventure_trait" } },
            malformed_family = { "new_boon", {}, { "missing_trait" } },
        }
        local missing = policy.unmapped_boon_categories(combinations, traits)
        H.equal(#missing, 2)
        H.equal(missing[1], "a_new_family")
        H.equal(missing[2], "z_new_family")
    end)

    H.test("CIM #1122 census is total over malformed or absent live tables", function()
        H.equal(#policy.unmapped_boon_categories(nil, {}), 0)
        H.equal(#policy.unmapped_boon_categories({}, nil), 0)
        H.equal(#policy.unmapped_boon_categories({ broken = false }, {}), 0)
    end)

    H.test("CIM production reroll and Athanor paths thread exact slot identity", function()
        local function read(path)
            local f = assert(io.open(path, "rb"))
            local text = f:read("*a")
            f:close()
            return text
        end
        local standard = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/standard_forge.lua")
        local picker = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_forge_picker_owner.lua")
        H.truthy(standard:find("_cim_cw_trait_entries%(master%.slot_type%)"))
        H.truthy(picker:find("selected_item%.data"))
        H.truthy(picker:find("dispatch.apply_forge_freedom, slots_progression, slot_type", 1, true))
    end)
end
