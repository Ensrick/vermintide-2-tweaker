-- Source-bound direct-operation coverage for the early Patch 3.1, 3.2, and
-- 4.1.1 weapon-history slices. Keeping these adjacent-boundary contracts in a
-- focused suite prevents the composite history owner from regrowing past the
-- repository's 1,500-line test target.

local function register(H, repo_root)
    local script_root = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local Policy = assert(loadfile(script_root .. "_wt_history_policy.lua"))()

    local function read_file(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("WT #1436 generated Patch 3.2 catalog pins one absent-current Axe change", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_3_2_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_3_2_v1")
        H.equal(catalog.current_source.revision,
            "038498af2b565bcb10bf5ed225638293a7640c83")
        H.equal(#catalog.families, 1)
        H.equal(next(catalog.profile_specs), nil)
        H.equal(next(catalog.derived_profiles), nil)

        local family = catalog.families[1]
        H.equal(family.id, "elf_one_handed_axe")
        H.equal(family.setting_id, "wt_history_elf_one_handed_axe")
        H.equal(family.display_name, "Kerillian's One-handed Axe")
        H.deep_equal(family.templates, { "we_one_hand_axe_template" })
        H.deep_equal(family.state_order, { "3_1_0" })
        H.equal(catalog.states["3_1_0"].source_revision,
            "3f0e3ba442d8dcafb8b5f829ff6c2a95ae24ae63")
        H.equal(catalog.states["3_1_0"].official_patch_notes,
            "https://www.vermintide.com/news/patch-32-quality-of-life-update")

        local state = family.states["3_1_0"]
        H.deep_equal(state.profile_names, {})
        H.deep_equal(state.direct_profile_names, {})
        H.equal(#state.operations, 1)
        local row = state.operations[1]
        H.equal(row.root, "Weapons")
        H.equal(row.template, "we_one_hand_axe_template")
        H.deep_equal(row.path, {
            "actions", "action_one", "light_attack_bopp",
            "additional_critical_strike_chance",
        })
        H.equal(row.expected_present, false)
        H.equal(rawget(row, "expected_current"), nil)
        H.equal(row.result_present, true)
        H.equal(row.result, 0.1)
        H.equal(row.family_id, family.id)
        H.equal(row.state_id, "3_1_0")
        H.equal(row.official_change_id, "P320-ELF1HA-BOPP-CRIT")
        H.equal(row.change_class, "official_weapon_balance")
        H.equal(row.source_blob,
            "d8a526f548596c8915826352cd7f1cb9a03486f8")
        H.equal(row.current_source_blob,
            "25c9ac9c38d51cb7b588c20d46e2773ca67149eb")
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 1,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })
        H.equal(read_file(script_root .. "_wt_history_3_2_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_3_2_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 3.2 data")
    end)

    H.test("WT #1436 generated Patch 3.1 catalog pins two bounded family deltas", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_3_1_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_3_1_v1")
        H.equal(catalog.current_source.revision,
            "038498af2b565bcb10bf5ed225638293a7640c83")
        H.equal(#catalog.families, 2)
        H.equal(next(catalog.profile_specs), nil)
        H.equal(next(catalog.derived_profiles), nil)

        local family = catalog.families[1]
        H.equal(family.id, "kruber_blunderbuss")
        H.equal(family.setting_id, "wt_history_kruber_blunderbuss")
        H.deep_equal(family.templates, { "blunderbuss_template_1" })
        H.deep_equal(family.state_order, { "pre_3_1_delta" })
        H.equal(catalog.states.pre_3_1_delta.display_name,
            "Pre-Patch 3.1 (3.0.x source) — bounded patch delta")
        H.equal(catalog.states.pre_3_1_delta.official_patch_notes,
            "https://www.vermintide.com/news/patch-31")

        local state = family.states.pre_3_1_delta
        H.deep_equal(state.profile_names, {})
        H.deep_equal(state.direct_profile_names, {})
        H.equal(#state.operations, 1)
        local row = state.operations[1]
        H.equal(row.root, "Weapons")
        H.equal(row.template, "blunderbuss_template_1")
        H.deep_equal(row.path, { "ammo_data", "max_ammo" })
        H.equal(row.expected_present, true)
        H.equal(row.expected_current, 16)
        H.equal(row.result_present, true)
        H.equal(row.result, 12)
        H.equal(row.source_revision,
            "c96aa3858011ecd557d55d80b66fe3bb8342eeb2")
        H.equal(row.source_blob,
            "f8f6ec97a974bd5767c1ccabf9fc593dba785d34")
        H.equal(row.current_source_blob,
            "87dca4018c18051d653a80b7aff501ed9815a5d0")
        H.equal(row.official_change_id, "P310-BLUNDERBUSS-MAX-AMMO")
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 2,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })
        H.equal(read_file(script_root .. "_wt_history_3_1_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_3_1_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 3.1 data")

        local roots = {
            BuffTemplates = {}, ExplosionTemplates = {},
            PlayerUnitStatusSettings = {}, VortexTemplates = {},
            Weapons = {
                blunderbuss_template_1 = { ammo_data = { max_ammo = 16 } },
                blunderbuss_template_1_vs = { ammo_data = { max_ammo = 9 } },
                two_handed_heavy_spears_template = {
                    block_fatigue_point_multiplier = 0.5,
                    metadata = { owner = "tuskgor" },
                    outer_block_fatigue_point_multiplier = 2,
                },
            },
        }
        local plan = assert(Policy.build_family_plan(
            catalog, family, "pre_3_1_delta", roots))
        H.equal(#plan, 1)
        local ledger = assert(Policy.commit(plan))
        H.equal(roots.Weapons.blunderbuss_template_1.ammo_data.max_ammo, 12)
        H.equal(roots.Weapons.two_handed_heavy_spears_template
            .block_fatigue_point_multiplier, 0.5,
            "Blunderbuss selection must not alter the Tuskgor family")
        H.equal(roots.Weapons.blunderbuss_template_1_vs.ammo_data.max_ammo, 9,
            "current-only Versus template must remain excluded")
        H.equal(Policy.restore(ledger), true)
        H.equal(roots.Weapons.blunderbuss_template_1.ammo_data.max_ammo, 16)

        roots.Weapons.blunderbuss_template_1.ammo_data.max_ammo = 12
        local refused, refusal = Policy.build_family_plan(
            catalog, family, "pre_3_1_delta", roots)
        H.equal(refused, nil)
        H.truthy(refusal and refusal:find("current guard mismatch", 1, true))

        roots.Weapons.blunderbuss_template_1.ammo_data.max_ammo = 16
        local spear = catalog.families[2]
        H.equal(spear.id, "tuskgor_spear")
        H.equal(spear.setting_id, "wt_history_tuskgor_spear")
        H.equal(spear.label_key, "wt_history_family_tuskgor_spear")
        H.equal(spear.display_name, "Kruber's Tuskgor Spear")
        H.deep_equal(spear.templates, { "two_handed_heavy_spears_template" })
        H.deep_equal(spear.state_order, { "pre_3_1_delta" })
        local spear_state = spear.states.pre_3_1_delta
        H.deep_equal(spear_state.profile_names, {})
        H.deep_equal(spear_state.direct_profile_names, {})
        H.equal(#spear_state.operations, 1)
        local spear_row = spear_state.operations[1]
        H.equal(spear_row.root, "Weapons")
        H.equal(spear_row.template, "two_handed_heavy_spears_template")
        H.deep_equal(spear_row.path, { "block_fatigue_point_multiplier" })
        H.equal(spear_row.expected_present, true)
        H.equal(spear_row.expected_current, 0.5)
        H.equal(spear_row.result_present, true)
        H.equal(spear_row.result, 0.25)
        H.equal(spear_row.source_revision,
            "c96aa3858011ecd557d55d80b66fe3bb8342eeb2")
        H.equal(spear_row.source_blob,
            "bdd5a9bed6cf3e4a826206318a090cc198ccf7de")
        H.equal(spear_row.current_source_blob,
            "7575b5035a40d9957514667538d253af46e18c9a")
        H.equal(spear_row.source_path,
            "scripts/settings/equipment/weapon_templates/2h_heavy_spears.lua")
        H.equal(spear_row.official_change_id, "P310-TUSKGOR-BLOCK-COST")
        H.equal(spear_row.family_id, "tuskgor_spear")
        H.equal(spear_row.state_id, "pre_3_1_delta")

        local spear_template = roots.Weapons.two_handed_heavy_spears_template
        local spear_metadata = spear_template.metadata
        local spear_plan = assert(Policy.build_family_plan(
            catalog, spear, "pre_3_1_delta", roots))
        H.equal(#spear_plan, 1)
        local spear_ledger = assert(Policy.commit(spear_plan))
        H.equal(spear_template.block_fatigue_point_multiplier, 0.25)
        H.equal(spear_template.outer_block_fatigue_point_multiplier, 2)
        H.equal(spear_template.metadata, spear_metadata,
            "Tuskgor projection must preserve sibling identity")
        H.equal(roots.Weapons.blunderbuss_template_1.ammo_data.max_ammo, 16,
            "Tuskgor selection must not alter the Blunderbuss family")
        H.equal(Policy.restore(spear_ledger), true)
        H.equal(spear_template.block_fatigue_point_multiplier, 0.5)

        spear_template.block_fatigue_point_multiplier = 0.25
        refused, refusal = Policy.build_family_plan(
            catalog, spear, "pre_3_1_delta", roots)
        H.equal(refused, nil)
        H.truthy(refusal and refusal:find("current guard mismatch", 1, true))
        spear_template.block_fatigue_point_multiplier = nil
        refused, refusal = Policy.build_family_plan(
            catalog, spear, "pre_3_1_delta", roots)
        H.equal(refused, nil)
        H.truthy(refusal and refusal:find("current guard mismatch", 1, true))
        H.equal(spear_template.outer_block_fatigue_point_multiplier, 2,
            "failed plans must not write sibling leaves")
    end)

    H.test("WT #1436 generated Patch 4.1.1 catalog preserves a present-false guard", function()
        local catalog = assert(loadfile(script_root
            .. "_wt_history_4_1_1_catalog.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.schema, 2)
        H.equal(catalog.catalog_id, "wt_history_patch_4_1_1_v1")
        H.equal(catalog.current_source.revision,
            "038498af2b565bcb10bf5ed225638293a7640c83")
        H.equal(#catalog.families, 1)
        H.equal(next(catalog.profile_specs), nil)
        H.equal(next(catalog.derived_profiles), nil)

        local family = catalog.families[1]
        H.equal(family.id, "masterwork_pistol")
        H.equal(family.setting_id, "wt_history_masterwork_pistol")
        H.equal(family.label_key, "wt_history_family_masterwork_pistol")
        H.equal(family.display_name, "Bardin's Masterwork Pistol")
        H.deep_equal(family.templates, { "heavy_steam_pistol_template_1" })
        H.deep_equal(family.state_order, { "4_0_1" })
        local state = family.states["4_0_1"]
        H.deep_equal(state.profile_names, {})
        H.deep_equal(state.direct_profile_names, {})
        H.equal(#state.operations, 1)
        local row = state.operations[1]
        H.equal(row.root, "Weapons")
        H.equal(row.template, "heavy_steam_pistol_template_1")
        H.deep_equal(row.path, { "ammo_data", "reload_on_ammo_pickup" })
        H.equal(row.expected_present, true)
        H.equal(rawget(row, "expected_current") ~= nil, true)
        H.equal(row.expected_current, false)
        H.equal(row.result_present, true)
        H.equal(rawget(row, "result") ~= nil, true)
        H.equal(row.result, true)
        H.equal(row.family_id, family.id)
        H.equal(row.state_id, "4_0_1")
        H.equal(row.official_change_id, "P411-MASTERWORK-PISTOL-AMMO-RELOAD")
        H.equal(row.source_revision,
            "872027662e076477451c8c4bf077473d8ab9e27d")
        H.equal(row.source_blob,
            "25a4db5545750c0a5eb590e8d1bfc9882c80d30a")
        H.equal(row.current_source_blob,
            "d68819bb59bdece50b69c9401a9feb5ae238b3cb")
        H.equal(row.source_path,
            "scripts/settings/equipment/weapon_templates/heavy_steam_pistol.lua")
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 1,
            global_operations = 0,
            profile_route_count = 0,
            unsupported_count = 0,
        })
        H.equal(read_file(script_root .. "_wt_history_4_1_1_catalog.lua"),
            read_file(repo_root
                .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
                .. "_wt_history_4_1_1_catalog.lua"),
            "public and dev must carry byte-identical pure Patch 4.1.1 data")
    end)
end

return register
