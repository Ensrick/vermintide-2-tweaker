-- Source and runtime coverage for issue #1436's Patch 2.0.10 slice.

local function register(H, repo_root)
    local script_root = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local dev_root = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
    local Policy = assert(loadfile(script_root .. "_wt_history_policy.lua"))()
    local Runtime = assert(loadfile(script_root .. "_wt_history_runtime.lua"))()

    local function read_file(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    local function clone(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local copy = {}
        seen[value] = copy
        for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
        return copy
    end

    local function mod_fixture(selection, parity)
        local mod = {}
        function mod:get(setting_id)
            if setting_id == "wt_history_sword_and_dagger" then return selection end
        end
        function mod._wt431_profiles_allowed() return parity == true end
        return mod
    end

    local function roots_fixture(mismatch)
        local linesman = "light_slashing_linesman_dual_medium"
        local smiter = "light_slashing_smiter_stab_dual"
        local actions = {
            heavy_attack = {
                damage_profile_left = linesman,
                damage_profile_right = linesman,
                total_time = 1.25,
            },
            heavy_attack_2 = {
                damage_profile_left = smiter,
                damage_profile_right = smiter,
                total_time = 1.3,
            },
            light_attack = { damage_profile = "unrelated_light_profile" },
        }
        if mismatch then
            actions[assert(mismatch.attack)][assert(mismatch.hand)] =
                assert(mismatch.value)
        end
        return {
            BuffTemplates = {}, ExplosionTemplates = {},
            PlayerUnitStatusSettings = {}, VortexTemplates = {},
            Weapons = {
                dual_wield_sword_dagger_template_1 = {
                    actions = { action_one = actions },
                    presentation = { marker = "current" },
                },
            },
        }
    end

    local function with_profile_globals(callback)
        local old_profiles = rawget(_G, "DamageProfileTemplates")
        local old_lookup = rawget(_G, "NetworkLookup")
        local linesman = "light_slashing_linesman_dual_medium"
        local smiter = "light_slashing_smiter_stab_dual"
        rawset(_G, "DamageProfileTemplates", {
            [linesman] = { melee_boost_override = 3.5, current = true },
            [smiter] = { melee_boost_override = 4, current = true },
        })
        rawset(_G, "NetworkLookup", { damage_profiles = {
            [1] = linesman, [linesman] = 1,
            [2] = smiter, [smiter] = 2,
        } })
        local ok, result = pcall(callback)
        rawset(_G, "DamageProfileTemplates", old_profiles)
        rawset(_G, "NetworkLookup", old_lookup)
        assert(ok, result)
    end

    H.test("WT #1436 Patch 2.0.10 catalog is an exact four-route private-profile slice", function()
        local catalog = assert(loadfile(script_root
            .. "_wt_history_2_0_10_catalog.lua"))()
        local source = assert(loadfile(repo_root
            .. "/tools/weapon-history/evidence/patch_2_0_10/"
            .. "_wt_history_2_0_10_source_catalog.lua"))()
        local routes = assert(loadfile(repo_root
            .. "/tools/weapon-history/evidence/patch_2_0_10/"
            .. "_wt_history_2_0_10_routes_oracle.lua"))()
        local valid, validation_error = Policy.validate(catalog)
        H.equal(validation_error, nil)
        H.equal(valid, true)
        H.equal(catalog.catalog_id,
            "wt_history_patch_2_0_10_sword_and_dagger_v1")
        H.equal(source.boundary.historical_revision,
            "90c7c21adb7aa2b7de5fcdca5094727895fbeb1a")
        H.equal(source.boundary.post_revision,
            "67d593c4f98653e1d511105b6adeebb5d6619c58")
        H.equal(source.official_patch_notes,
            "https://forums.fatsharkgames.com/t/vermintide-2-patch-2-0-10/36215")
        H.deep_equal(catalog.generation, {
            adjacent_operation_count = 2,
            excluded_operation_count = 0,
            global_operations = 0,
            profile_route_count = 4,
            unsupported_count = 0,
        })
        local family = catalog.families[1]
        H.equal(family.id, "sword_and_dagger")
        H.equal(family.setting_id, "wt_history_sword_and_dagger")
        H.deep_equal(family.templates, {
            "dual_wield_sword_dagger_template_1",
        })
        local state = family.states["2_0_9_1"]
        H.equal(#state.operations, 4)
        H.deep_equal(state.direct_profile_names, {})
        H.deep_equal(state.profile_names, {
            "light_slashing_linesman_dual_medium",
            "light_slashing_smiter_stab_dual",
        })
        H.equal(#routes.routes.sword_and_dagger["2_0_9_1"], 4)
        for _, operation in ipairs(state.operations) do
            H.equal(operation.synthetic_profile_route, true)
            H.equal(operation.expected_current, operation.result)
            H.equal(operation.root, "Weapons")
        end
        local profiles = catalog.profile_specs["2_0_9_1"]
        H.equal(profiles.light_slashing_linesman_dual_medium
            .historical_profile.melee_boost_override, 4)
        H.equal(profiles.light_slashing_smiter_stab_dual
            .historical_profile.melee_boost_override, 3.5)
        H.equal(read_file(script_root .. "_wt_history_2_0_10_catalog.lua"),
            read_file(dev_root .. "_wt_history_2_0_10_catalog.lua"),
            "public and dev must carry byte-identical generated data")
        H.equal(read_file(script_root .. "_wt_history_policy.lua"),
            read_file(dev_root .. "_wt_history_policy.lua"),
            "public and dev must share the exact profile-route policy")
    end)

    H.test("WT #1436 Patch 2.0.9.1 is atomic, restorable, gated, and layers before ordinary tweaks", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_2_0_10_catalog.lua"))()

            local current = roots_fixture()
            local current_before = clone(current)
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("current", true),
                policy = Policy,
                roots = current,
            })
            H.equal(current_runtime:verify(), nil)
            H.deep_equal(current, current_before,
                "Current must not write any gameplay route")

            local gated = roots_fixture()
            local gated_before = clone(gated)
            local gated_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("2_0_9_1", false),
                policy = Policy,
                roots = gated,
            })
            H.equal(gated_runtime:verify(), nil)
            H.deep_equal(gated, gated_before,
                "a peer mismatch must retain all native profile routes")

            local roots = roots_fixture()
            local before = clone(roots)
            local runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("2_0_9_1", true),
                policy = Policy,
                roots = roots,
            })
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#runtime.ledgers.sword_and_dagger, 4)
            local actions = roots.Weapons.dual_wield_sword_dagger_template_1
                .actions.action_one
            local linesman = "wt_hist_2_0_9_1_light_slashing_linesman_dual_medium"
            local smiter = "wt_hist_2_0_9_1_light_slashing_smiter_stab_dual"
            H.equal(actions.heavy_attack.damage_profile_left, linesman)
            H.equal(actions.heavy_attack.damage_profile_right, linesman)
            H.equal(actions.heavy_attack_2.damage_profile_left, smiter)
            H.equal(actions.heavy_attack_2.damage_profile_right, smiter)
            H.equal(DamageProfileTemplates[linesman].melee_boost_override, 4)
            H.equal(DamageProfileTemplates[smiter].melee_boost_override, 3.5)
            H.equal(DamageProfileTemplates.light_slashing_linesman_dual_medium
                .melee_boost_override, 3.5,
                "the native shared profile must remain current")
            actions.heavy_attack.total_time = 9.75
            H.equal(assert(runtime:reapply()).changed, false)
            H.equal(actions.heavy_attack.total_time, 9.75,
                "ordinary WT tweaks applied afterward must remain layered")
            local restored = assert(runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(actions.heavy_attack.damage_profile_left,
                "light_slashing_linesman_dual_medium")
            H.equal(actions.heavy_attack_2.damage_profile_right,
                "light_slashing_smiter_stab_dual")
            H.equal(actions.heavy_attack.total_time, 9.75,
                "restore must own only the four profile routes")
            before.Weapons.dual_wield_sword_dagger_template_1.actions.action_one
                .heavy_attack.total_time = 9.75
            H.deep_equal(roots, before)

            local hostile = roots_fixture({
                attack = "heavy_attack_2",
                hand = "damage_profile_left",
                value = "foreign_profile",
            })
            local hostile_before = clone(hostile)
            local refused = Runtime.install({
                catalog = catalog,
                mod = mod_fixture("2_0_9_1", true),
                policy = Policy,
                roots = hostile,
            })
            H.truthy(refused.last_error and refused.last_error:find(
                "current guard mismatch", 1, true))
            H.equal(#(refused.ledgers.sword_and_dagger or {}), 0)
            H.deep_equal(hostile, hostile_before,
                "one hostile hand must refuse before all four route writes")
        end)
    end)

    H.test("WT #1436 synthetic profile routes reject foreign profile ownership", function()
        local catalog = clone(assert(loadfile(script_root
            .. "_wt_history_2_0_10_catalog.lua"))())
        catalog.families[1].states["2_0_9_1"].operations[1].result =
            "unowned_profile"
        local valid, validation_error = Policy.validate(catalog)
        H.equal(valid, nil)
        H.truthy(validation_error and validation_error:find(
            "invalid synthetic profile route", 1, true))
    end)
end

return register
