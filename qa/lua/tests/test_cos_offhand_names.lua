return function(H, repo_root)
    local policy_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_names.lua"
    local entry_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
    local gk_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_grail_knight_set.lua"

    local policy = assert(dofile(policy_path))
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end
    local runtime_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua"
    local entry, gk = read(entry_path) .. read(runtime_path), read(gk_path)

    H.test("component localization keys are stable and independently qualified", function()
        H.equal(policy.SCHEMA_VERSION, 1)
        H.equal(policy.localization_key("wh_dual_hammer_skin_01", "left_hand_unit"),
            "cos_offhand_weapon_wh_dual_hammer_skin_01_left_name")
        H.equal(policy.localization_key("units/example/shield", "left_hand_unit", "shield"),
            policy.localization_key("units/example/shield", "left_hand_unit", "shield"))
        H.equal(policy.localization_key("x", "left_hand_unit", "primary_weapon"), nil)
    end)

    H.test("authored component name wins without changing identity", function()
        local name, key, source = policy.resolve(
            "wh_dual_hammer_skin_01", "left_hand_unit", "Source Illusion",
            function() return "The Named Offhand" end)
        H.equal(name, "The Named Offhand")
        H.equal(key, "cos_offhand_weapon_wh_dual_hammer_skin_01_left_name")
        H.equal(source, "authored")
    end)

    H.test("missing component localization falls back deterministically", function()
        local function missing(key) return "<" .. key .. ">" end
        local name, _, source = policy.resolve(
            "wh_dual_hammer_skin_01", "left_hand_unit", "Source Illusion", missing)
        H.equal(name, "Source Illusion")
        H.equal(source, "source")
        name, _, source = policy.resolve(
            "wh_dual_hammer_skin_01", "left_hand_unit", "wh_dual_hammer_skin_01", missing)
        H.equal(name, "Dual Hammer 01")
        H.equal(source, "generated")
    end)

    H.test("primary name is reused from an identical-model illusion", function()
        local records = {
            { key = "skin_b", primary_unit = "units/primary", name = "Second Name" },
            { key = "skin_a", primary_unit = "units/primary", name = "Existing Primary Name" },
            { key = "skin_c", primary_unit = "units/other", name = "Wrong Model" },
        }
        H.equal(policy.primary_name_for_unit("units/primary", records), "Existing Primary Name")
        H.equal(policy.primary_name_for_unit("units/missing", records), nil)
        H.equal(policy.compose("Existing Primary Name", "Named Shield"),
            "Existing Primary Name + Named Shield")
        records[1].is_pair = false
        records[2].is_pair = true
        H.equal(policy.primary_name_for_unit("units/primary", records), "Second Name")
        records[1].name = "Standalone Primary"
        records[2].name = "Pair Name"
        H.equal(policy.primary_name_for_unit("units/primary", records), "Standalone Primary")
    end)

    H.test("component records resolve by authored key, mesh, or source skin", function()
        local options = {
            { name = "Shield A", la_armoury_key = "la_a" },
            { name = "Shield B", unit = "units/shield_b", skin_key = "skin_b" },
        }
        H.equal(policy.match_option({ armoury_key = "la_a" }, options), options[1])
        H.equal(policy.match_option({ unit_path = "units/shield_b" }, options), options[2])
        H.equal(policy.match_option({ vanilla_key = "skin_b" }, options), options[2])
        local key, combined = policy.presentation_key("Sword", "Shield A")
        H.truthy(key:find("cos_component_presentation_", 1, true) == 1)
        H.equal(combined, "Sword + Shield A")
    end)

    H.test("decorated weapon and shield records remain presentation-only", function()
        local weapon = { unit = "units/example/offhand", skin_key = "skin_01", rarity = "rare" }
        policy.decorate(weapon, "skin_01", "left_hand_unit", "Source Illusion",
            "source_display_key", function(key) return key end)
        H.equal(weapon.component_kind, "weapon_offhand")
        H.equal(weapon.unit, "units/example/offhand")
        H.equal(weapon.skin_key, "skin_01")

        local shield = { unit = "units/example/shield", name = "Existing Shield" }
        policy.decorate(shield, shield.unit, "left_hand_unit", shield.name, nil,
            function(key) return key end, "shield")
        H.equal(shield.component_kind, "shield")
        H.equal(shield.name, "Existing Shield")
        H.equal(shield.unit, "units/example/shield")
        H.equal(shield.source_skin_key, nil)
    end)

    H.test("generated inventory separates weapon offhands from shields", function()
        local rows = policy.inventory_rows({
            { item_type = "dual", hand_field = "left_hand_unit", component_kind = "weapon_offhand",
              component_identity = "skin_01", source_skin_key = "skin_01", source_name = "Weapon" },
            { item_type = "shield_a", hand_field = "left_hand_unit", component_kind = "shield",
              component_identity = "units/shield", source_name = "Shield" },
            { item_type = "shield_b", hand_field = "left_hand_unit", component_kind = "shield",
              component_identity = "units/shield", source_name = "Shield", status = "authored" },
        })
        H.equal(#rows, 2)
        H.equal(rows[1].component_kind, "shield")
        H.deep_equal(rows[1].item_types, { "shield_a", "shield_b" })
        H.equal(rows[2].component_kind, "weapon_offhand")
    end)

    H.test("runtime integration composes primary then independently named component", function()
        H.truthy(entry:find("_decorate_dual_component", 1, true))
        H.truthy(entry:find("_decorate_shield_option", 1, true))
        H.truthy(entry:find("OFFHAND_NAMES.compose", 1, true))
        H.truthy(entry:find("mod._cos.offhand_name_inventory", 1, true))
        H.truthy(entry:find("issue641_independent_offhand_names", 1, true))
        H.truthy(gk:find('cos_gk_purpure_azure_shield_name = "The Blood-Bloomed Bouclier"', 1, true))
    end)
end
