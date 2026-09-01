-- test_wt_history_patch_6_11_2_runtime.lua
-- Deterministic #1436 runtime coverage for the bounded Hotfix 6.11.2 slice.

local function register(H, context)
    local Policy = assert(context.Policy)
    local Runtime = assert(context.Runtime)
    local clone = assert(context.clone)
    local mod_fixture = assert(context.mod_fixture)
    local script_root = assert(context.script_root)
    local with_profile_globals = assert(context.with_profile_globals)

    H.test("WT #1436 Hotfix 6.11.2 restores three native routes exactly", function()
        with_profile_globals(function()
            local public_catalog = assert(loadfile(script_root
                .. "_wt_history_6_11_2_catalog.lua"))()
            local dev_root, replacements = script_root:gsub(
                "weapon_tweaker/scripts/mods/weapon_tweaker/$",
                "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/")
            H.equal(replacements, 1,
                "the runtime harness must resolve the paired dev catalog")
            local dev_catalog = assert(loadfile(dev_root
                .. "_wt_history_6_11_2_catalog.lua"))()
            H.deep_equal(dev_catalog, public_catalog,
                "public and dev Hotfix 6.11.2 catalogs must be data-identical")

            local function roots_with_profile(damage_profile, axe_h1, axe_h2)
                local heavy_metadata = { marker = "preserve heavy sibling identity" }
                local light_sibling = {
                    damage_profile = "light_burning_smiter",
                    total_time = 0.47,
                }
                local template_metadata = {
                    marker = "preserve template sibling identity",
                }
                local heavy = {
                    anim_event = "attack_heavy_02",
                    damage_profile = damage_profile,
                    metadata = heavy_metadata,
                    total_time = 1.15,
                }
                local action_one = {
                    heavy_attack_right = heavy,
                    light_attack_left = light_sibling,
                }
                local actions = { action_one = action_one }
                local template = {
                    actions = actions,
                    metadata = template_metadata,
                    weapon_type = "DAGGER_1H",
                }
                local axe_h1_attack = {
                    damage_profile_left = "light_slashing_smiter_dual",
                    damage_profile_right = axe_h1
                        or "light_slashing_smiter_dual",
                    total_time = 1.01,
                }
                local axe_h2_attack = {
                    damage_profile_left = "light_slashing_smiter_dual",
                    damage_profile_right = axe_h2
                        or "light_slashing_smiter_dual",
                    total_time = 1.02,
                }
                local axe_action_one = {
                    heavy_attack = axe_h1_attack,
                    heavy_attack_2 = axe_h2_attack,
                }
                local axe_actions = { action_one = axe_action_one }
                local axe_template = {
                    actions = axe_actions,
                    marker = "preserve axe template sibling identity",
                }
                local buff_templates = { sentinel = { marker = "buff root" } }
                local explosion_templates = {
                    sentinel = { marker = "explosion root" },
                }
                local player_status = { sentinel = { marker = "status root" } }
                local vortex_templates = { sentinel = { marker = "vortex root" } }
                local weapons = {
                    one_handed_daggers_template_1 = template,
                    dual_wield_axe_falchion_template = axe_template,
                }
                return {
                    BuffTemplates = buff_templates,
                    ExplosionTemplates = explosion_templates,
                    PlayerUnitStatusSettings = player_status,
                    VortexTemplates = vortex_templates,
                    Weapons = weapons,
                }, {
                    action_one = action_one,
                    actions = actions,
                    axe_action_one = axe_action_one,
                    axe_actions = axe_actions,
                    axe_h1_attack = axe_h1_attack,
                    axe_h2_attack = axe_h2_attack,
                    axe_template = axe_template,
                    buff_templates = buff_templates,
                    explosion_templates = explosion_templates,
                    heavy = heavy,
                    heavy_metadata = heavy_metadata,
                    light_sibling = light_sibling,
                    player_status = player_status,
                    template = template,
                    template_metadata = template_metadata,
                    vortex_templates = vortex_templates,
                    weapons = weapons,
                }
            end

            local function assert_identities(roots, refs, label)
                H.equal(roots.BuffTemplates, refs.buff_templates,
                    label .. " must preserve BuffTemplates identity")
                H.equal(roots.ExplosionTemplates, refs.explosion_templates,
                    label .. " must preserve ExplosionTemplates identity")
                H.equal(roots.PlayerUnitStatusSettings, refs.player_status,
                    label .. " must preserve PlayerUnitStatusSettings identity")
                H.equal(roots.VortexTemplates, refs.vortex_templates,
                    label .. " must preserve VortexTemplates identity")
                H.equal(roots.Weapons, refs.weapons,
                    label .. " must preserve Weapons identity")
                H.equal(roots.Weapons.one_handed_daggers_template_1,
                    refs.template, label .. " must preserve template identity")
                H.equal(refs.template.actions, refs.actions,
                    label .. " must preserve actions identity")
                H.equal(refs.actions.action_one, refs.action_one,
                    label .. " must preserve action_one identity")
                H.equal(refs.action_one.heavy_attack_right, refs.heavy,
                    label .. " must preserve H2 identity")
                H.equal(refs.heavy.metadata, refs.heavy_metadata,
                    label .. " must preserve H2 sibling identity")
                H.equal(refs.action_one.light_attack_left, refs.light_sibling,
                    label .. " must preserve sibling attack identity")
                H.equal(refs.template.metadata, refs.template_metadata,
                    label .. " must preserve template sibling identity")
                H.equal(roots.Weapons.dual_wield_axe_falchion_template,
                    refs.axe_template, label .. " must preserve Axe & Falchion template identity")
                H.equal(refs.axe_template.actions, refs.axe_actions,
                    label .. " must preserve Axe & Falchion actions identity")
                H.equal(refs.axe_actions.action_one, refs.axe_action_one,
                    label .. " must preserve Axe & Falchion action_one identity")
                H.equal(refs.axe_action_one.heavy_attack, refs.axe_h1_attack,
                    label .. " must preserve Axe & Falchion H1 identity")
                H.equal(refs.axe_action_one.heavy_attack_2, refs.axe_h2_attack,
                    label .. " must preserve Axe & Falchion H2 identity")
            end

            local profile_root = DamageProfileTemplates
            local native_profile = DamageProfileTemplates.native_profile
            local lookup_root = NetworkLookup
            local lookup = NetworkLookup.damage_profiles
            local profile_before = clone(profile_root)
            local lookup_before = clone(lookup_root)

            for _, case in ipairs({
                { catalog = public_catalog, label = "public" },
                { catalog = dev_catalog, label = "dev" },
            }) do
                H.equal(case.catalog.catalog_id,
                    "wt_history_patch_6_11_2_reversions_v2")
                H.equal(next(case.catalog.profile_specs), nil,
                    case.label .. " catalog must own no private profiles")
                H.equal(next(case.catalog.derived_profiles), nil,
                    case.label .. " catalog must own no derived profiles")
                H.equal(case.catalog.generation.global_operations, 0,
                    case.label .. " catalog must own no global operations")

                local family = case.catalog.families[1]
                H.equal(family.id, "sienna_dagger")
                H.equal(family.setting_id, "wt_history_sienna_dagger")
                local state = family.states["6_11_1"]
                H.equal(#state.operations, 1)
                H.equal(#state.profile_names, 0)
                H.equal(#state.direct_profile_names, 0)
                local operation = state.operations[1]
                H.equal(operation.root, "Weapons")
                H.equal(operation.template, "one_handed_daggers_template_1")
                H.deep_equal(operation.path, {
                    "actions", "action_one", "heavy_attack_right",
                    "damage_profile",
                })
                H.equal(operation.expected_current,
                    "medium_burning_smiter_stab_H")
                H.equal(operation.result, "dagger_h1_medium_smiter_diag")
                local axe_family = case.catalog.families[2]
                H.equal(axe_family.id, "axe_and_falchion")
                H.equal(axe_family.setting_id, "wt_history_axe_and_falchion")
                H.equal(#axe_family.states["6_11_1"].operations, 2)

                local current_roots, current_refs = roots_with_profile(
                    "medium_burning_smiter_stab_H")
                local current_before = clone(current_roots)
                local current_runtime = Runtime.install({
                    catalog = case.catalog,
                    mod = mod_fixture({
                            wt_history_sienna_dagger = "current",
                            wt_history_axe_and_falchion = "current",
                        },
                        { value = true }),
                    policy = Policy,
                    roots = current_roots,
                })
                H.equal(current_runtime.fatal_error, nil)
                H.equal(current_runtime.last_error, nil)
                H.equal(current_runtime.registration.count, 0)
                H.equal(#current_runtime.registration.names, 0)
                H.equal(#(current_runtime.ledgers.sienna_dagger or {}), 0)
                H.equal(#(current_runtime.ledgers.axe_and_falchion or {}), 0)
                H.deep_equal(current_roots, current_before,
                    case.label .. " Current must perform zero gameplay writes")
                assert_identities(current_roots, current_refs,
                    case.label .. " Current")
                local current_reapply = assert(current_runtime:reapply())
                H.equal(current_reapply.changed, false)
                H.equal(current_reapply.writes, 0)
                H.deep_equal(current_roots, current_before,
                    case.label .. " repeated Current must remain a no-op")
                local current_restore = assert(current_runtime:restore())
                H.equal(current_restore.changed, false)
                H.equal(current_restore.writes, 0)
                assert_identities(current_roots, current_refs,
                    case.label .. " restored Current")

                local dagger_only_roots, dagger_only_refs = roots_with_profile(
                    "medium_burning_smiter_stab_H")
                local dagger_only_runtime = Runtime.install({
                    catalog = case.catalog,
                    mod = mod_fixture({
                            wt_history_sienna_dagger = "6_11_1",
                            wt_history_axe_and_falchion = "current",
                        }, { value = true }),
                    policy = Policy,
                    roots = dagger_only_roots,
                })
                H.equal(dagger_only_runtime.last_error, nil)
                H.equal(#dagger_only_runtime.ledgers.sienna_dagger, 1)
                H.equal(#(dagger_only_runtime.ledgers.axe_and_falchion or {}), 0)
                H.equal(dagger_only_refs.heavy.damage_profile,
                    "dagger_h1_medium_smiter_diag")
                H.equal(dagger_only_refs.axe_h1_attack.damage_profile_right,
                    "light_slashing_smiter_dual")
                H.equal(dagger_only_refs.axe_h2_attack.damage_profile_right,
                    "light_slashing_smiter_dual")

                local axe_only_roots, axe_only_refs = roots_with_profile(
                    "medium_burning_smiter_stab_H")
                local axe_only_runtime = Runtime.install({
                    catalog = case.catalog,
                    mod = mod_fixture({
                            wt_history_sienna_dagger = "current",
                            wt_history_axe_and_falchion = "6_11_1",
                        }, { value = true }),
                    policy = Policy,
                    roots = axe_only_roots,
                })
                H.equal(axe_only_runtime.last_error, nil)
                H.equal(#(axe_only_runtime.ledgers.sienna_dagger or {}), 0)
                H.equal(#axe_only_runtime.ledgers.axe_and_falchion, 2)
                H.equal(axe_only_refs.heavy.damage_profile,
                    "medium_burning_smiter_stab_H")
                H.equal(axe_only_refs.axe_h1_attack.damage_profile_right,
                    "axe_falcion_heavy_smiter_vertical_right")
                H.equal(axe_only_refs.axe_h2_attack.damage_profile_right,
                    "axe_falcion_heavy_smiter_vertical_right")

                local history_roots, history_refs = roots_with_profile(
                    "medium_burning_smiter_stab_H")
                local history_before = clone(history_roots)
                local history_runtime = Runtime.install({
                    catalog = case.catalog,
                    mod = mod_fixture({
                            wt_history_sienna_dagger = "6_11_1",
                            wt_history_axe_and_falchion = "6_11_1",
                        },
                        { value = true }),
                    policy = Policy,
                    roots = history_roots,
                })
                H.equal(history_runtime.fatal_error, nil)
                H.equal(history_runtime.last_error, nil)
                H.equal(history_runtime.registration.count, 0)
                H.equal(#history_runtime.ledgers.sienna_dagger, 1,
                    case.label .. " 6.11.1 must own exactly one write")
                H.equal(#history_runtime.ledgers.axe_and_falchion, 2,
                    case.label .. " 6.11.1 must own both Axe & Falchion writes")
                H.equal(history_refs.heavy.damage_profile,
                    "dagger_h1_medium_smiter_diag")
                H.equal(history_refs.heavy.anim_event, "attack_heavy_02")
                H.equal(history_refs.heavy.total_time, 1.15)
                H.equal(history_refs.axe_h1_attack.damage_profile_right,
                    "axe_falcion_heavy_smiter_vertical_right")
                H.equal(history_refs.axe_h2_attack.damage_profile_right,
                    "axe_falcion_heavy_smiter_vertical_right")
                H.equal(history_refs.axe_h1_attack.damage_profile_left,
                    "light_slashing_smiter_dual")
                H.equal(history_refs.axe_h2_attack.total_time, 1.02)
                assert_identities(history_roots, history_refs,
                    case.label .. " 6.11.1")

                local ledger = history_runtime.ledgers.sienna_dagger
                local reapplied = assert(history_runtime:reapply())
                H.equal(reapplied.changed, false,
                    case.label .. " repeated 6.11.1 must be a no-op")
                H.equal(history_runtime.ledgers.sienna_dagger, ledger,
                    case.label .. " no-op must preserve ledger identity")
                H.equal(#ledger, 1)
                H.equal(history_refs.heavy.damage_profile,
                    "dagger_h1_medium_smiter_diag")
                H.equal(history_refs.axe_h1_attack.damage_profile_right,
                    "axe_falcion_heavy_smiter_vertical_right")
                H.equal(history_refs.axe_h2_attack.damage_profile_right,
                    "axe_falcion_heavy_smiter_vertical_right")
                assert_identities(history_roots, history_refs,
                    case.label .. " repeated 6.11.1")

                local restored = assert(history_runtime:restore())
                H.equal(restored.refused, 0)
                H.equal(restored.changed, true)
                H.equal(restored.writes, 0)
                H.deep_equal(history_roots, history_before,
                    case.label .. " restore must recover the exact current state")
                H.equal(history_refs.heavy.damage_profile,
                    "medium_burning_smiter_stab_H")
                H.equal(history_refs.axe_h1_attack.damage_profile_right,
                    "light_slashing_smiter_dual")
                H.equal(history_refs.axe_h2_attack.damage_profile_right,
                    "light_slashing_smiter_dual")
                assert_identities(history_roots, history_refs,
                    case.label .. " restore")
                local second_restore = assert(history_runtime:restore())
                H.equal(second_restore.changed, false)
                H.equal(second_restore.writes, 0)
                H.deep_equal(history_roots, history_before,
                    case.label .. " repeated restore must remain a no-op")

                local foreign_roots, foreign_refs = roots_with_profile(
                    "foreign_dagger_h2_profile")
                local foreign_before = clone(foreign_roots)
                local foreign_runtime = Runtime.install({
                    catalog = case.catalog,
                    mod = mod_fixture({
                            wt_history_sienna_dagger = "6_11_1",
                            wt_history_axe_and_falchion = "current",
                        },
                        { value = true }),
                    policy = Policy,
                    roots = foreign_roots,
                })
                H.equal(foreign_runtime.fatal_error, nil)
                H.truthy(foreign_runtime.last_error
                    and foreign_runtime.last_error:find(
                        "current guard mismatch", 1, true) ~= nil)
                H.equal(#(foreign_runtime.ledgers.sienna_dagger or {}), 0)
                H.deep_equal(foreign_roots, foreign_before,
                    case.label .. " foreign current must refuse before mutation")
                H.equal(foreign_refs.heavy.damage_profile,
                    "foreign_dagger_h2_profile")
                assert_identities(foreign_roots, foreign_refs,
                    case.label .. " foreign refusal")

                local axe_foreign_roots, axe_foreign_refs = roots_with_profile(
                    "medium_burning_smiter_stab_H",
                    "light_slashing_smiter_dual", "foreign_axe_h2_profile")
                local axe_foreign_before = clone(axe_foreign_roots)
                local axe_foreign_runtime = Runtime.install({
                    catalog = case.catalog,
                    mod = mod_fixture({
                            wt_history_sienna_dagger = "current",
                            wt_history_axe_and_falchion = "6_11_1",
                        }, { value = true }),
                    policy = Policy,
                    roots = axe_foreign_roots,
                })
                H.equal(axe_foreign_runtime.fatal_error, nil)
                H.truthy(axe_foreign_runtime.last_error
                    and axe_foreign_runtime.last_error:find(
                        "current guard mismatch", 1, true) ~= nil)
                H.equal(#(axe_foreign_runtime.ledgers.axe_and_falchion or {}), 0)
                H.deep_equal(axe_foreign_roots, axe_foreign_before,
                    case.label .. " foreign H2 must refuse both Axe & Falchion writes")
                H.equal(axe_foreign_refs.axe_h1_attack.damage_profile_right,
                    "light_slashing_smiter_dual")
                H.equal(axe_foreign_refs.axe_h2_attack.damage_profile_right,
                    "foreign_axe_h2_profile")
                assert_identities(axe_foreign_roots, axe_foreign_refs,
                    case.label .. " Axe & Falchion atomic refusal")

                local axe_missing_roots, axe_missing_refs = roots_with_profile(
                    "medium_burning_smiter_stab_H")
                axe_missing_refs.axe_action_one.heavy_attack_2 = nil
                local axe_missing_before = clone(axe_missing_roots)
                local axe_missing_runtime = Runtime.install({
                    catalog = case.catalog,
                    mod = mod_fixture({
                            wt_history_sienna_dagger = "current",
                            wt_history_axe_and_falchion = "6_11_1",
                        }, { value = true }),
                    policy = Policy,
                    roots = axe_missing_roots,
                })
                H.equal(axe_missing_runtime.fatal_error, nil)
                H.truthy(axe_missing_runtime.last_error
                    and axe_missing_runtime.last_error:find(
                        "missing parent", 1, true) ~= nil)
                H.equal(#(axe_missing_runtime.ledgers.axe_and_falchion or {}), 0)
                H.deep_equal(axe_missing_roots, axe_missing_before,
                    case.label .. " missing H2 must refuse before the H1 write")
                H.equal(axe_missing_refs.axe_h1_attack.damage_profile_right,
                    "light_slashing_smiter_dual")
            end

            H.equal(DamageProfileTemplates, profile_root,
                "6.11.2 history must not replace the global profile registry")
            H.equal(DamageProfileTemplates.native_profile, native_profile,
                "6.11.2 history must not replace a native profile")
            H.equal(NetworkLookup, lookup_root,
                "6.11.2 history must not replace NetworkLookup")
            H.equal(NetworkLookup.damage_profiles, lookup,
                "6.11.2 history must not replace the damage-profile lookup")
            H.deep_equal(DamageProfileTemplates, profile_before,
                "6.11.2 history must not add a private global profile")
            H.deep_equal(NetworkLookup, lookup_before,
                "6.11.2 history must not add a global lookup row")
        end)
    end)

end

return register
