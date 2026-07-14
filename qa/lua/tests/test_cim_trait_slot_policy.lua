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

    H.test("CIM production reroll and Athanor paths thread exact slot identity", function()
        local function read(path)
            local f = assert(io.open(path, "rb"))
            local text = f:read("*a")
            f:close()
            return text
        end
        local standard = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/standard_forge.lua")
        local entry = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua")
        H.truthy(standard:find("_cim_cw_trait_entries%(master%.slot_type%)"))
        H.truthy(entry:find("selected_item%.data%.slot_type"))
        H.truthy(entry:find("_cim_apply_forge_freedom, slots_progression, slot_type", 1, true))
    end)
end
