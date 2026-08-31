-- test_wt_history_runtime.lua - deterministic #1436 runtime and lifecycle coverage.
--
-- This module owns the history runtime, authority, restore, and overlay-composition
-- cases split from test_wt_history.lua. It consumes the parent's exact production
-- modules and real fixtures so the split changes only test ownership and file size.
--
-- Owned by: test_wt_history.lua. Consumed via: require("test_wt_history_runtime")

local function register(H, context)
    local AxeBalance = assert(context.AxeBalance)
    local HistoryOwner = assert(context.HistoryOwner)
    local Policy = assert(context.Policy)
    local Runtime = assert(context.Runtime)
    local catalog_fixture = assert(context.catalog_fixture)
    local clone = assert(context.clone)
    local deepwood_roots_fixture = assert(context.deepwood_roots_fixture)
    local materialize_expected_roots = assert(context.materialize_expected_roots)
    local mod_fixture = assert(context.mod_fixture)
    local roots_fixture = assert(context.roots_fixture)
    local script_root = assert(context.script_root)
    local with_profile_globals = assert(context.with_profile_globals)
    H.test("WT #1436 Patch 6.5.4 applies and restores one atomic host projection", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_6_catalog.lua"))()

            local current_roots, current_refs = deepwood_roots_fixture()
            local current_before = clone(current_roots)
            local current_runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return false end,
                mod = mod_fixture({ wt_history_deepwood_staff = "current" },
                    { value = true }),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.deepwood_staff or {}), 0)
            H.deep_equal(current_roots, current_before,
                "Current must remain a no-op even on a client")
            H.equal(current_refs.life_metadata,
                current_roots.Weapons.staff_life.metadata)

            local roots, refs = deepwood_roots_fixture()
            local before = clone(roots)
            local runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return true end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = roots,
            })
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#runtime.ledgers.deepwood_staff, 3)
            H.equal(refs.life_priorities.chaos_bulwark, nil)
            H.equal(refs.versus_priorities.chaos_bulwark, nil)
            H.equal(refs.vortex_reductions.chaos_bulwark, nil)
            H.equal(refs.life_priorities.chaos_tether_sorcerer, 1,
                "later Deepwood targeting rows must survive the old projection")
            H.equal(refs.versus_priorities.chaos_tether_sorcerer, 1,
                "the Versus clone must preserve later targeting rows too")
            H.equal(refs.life_priorities.chaos_warrior, 1)
            H.equal(refs.versus_priorities.chaos_warrior, 1)
            H.equal(refs.vortex_reductions.chaos_warrior, 0.5)
            H.equal(roots.Weapons.staff_life.metadata, refs.life_metadata)
            H.equal(roots.Weapons.staff_life_vs.metadata, refs.versus_metadata)
            H.equal(roots.VortexTemplates.spirit_storm.metadata,
                refs.vortex_metadata)

            local restored = assert(runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.deep_equal(roots, before,
                "restore must recover all three exact current leaves")
            H.equal(refs.life_priorities.chaos_bulwark, 1)
            H.equal(refs.versus_priorities.chaos_bulwark, 1)
            H.equal(refs.vortex_reductions.chaos_bulwark, 0.5)
            H.equal(assert(runtime:restore()).changed, false)
        end)
    end)

    H.test("WT #1436 Patch 6.6 preflight and client authority both fail before writes", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_6_catalog.lua"))()

            local mismatch_roots, mismatch_refs = deepwood_roots_fixture({
                staff_life_vs = 2,
            })
            local mismatch_before = clone(mismatch_roots)
            local mismatch_runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return true end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = mismatch_roots,
            })
            H.truthy(mismatch_runtime.last_error
                and mismatch_runtime.last_error:find(
                    "current guard mismatch", 1, true) ~= nil)
            H.equal(#(mismatch_runtime.ledgers.deepwood_staff or {}), 0)
            H.deep_equal(mismatch_roots, mismatch_before,
                "a late staff_life_vs guard mismatch must leak zero earlier removals")
            H.equal(mismatch_refs.vortex_reductions.chaos_bulwark, 0.5)
            H.equal(mismatch_refs.life_priorities.chaos_bulwark, 1)
            H.equal(mismatch_refs.versus_priorities.chaos_bulwark, 2)

            local client_roots, client_refs = deepwood_roots_fixture()
            local client_before = clone(client_roots)
            local client_runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return false end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = client_roots,
            })
            H.truthy(client_runtime.last_error
                and client_runtime.last_error:find(
                    "server authority required", 1, true) ~= nil)
            H.equal(#(client_runtime.ledgers.deepwood_staff or {}), 0)
            H.deep_equal(client_roots, client_before,
                "a joining client must not project any host-owned Deepwood leaf")
            H.equal(client_refs.life_priorities.chaos_bulwark, 1)
            H.equal(client_refs.versus_priorities.chaos_bulwark, 1)
            H.equal(client_refs.vortex_reductions.chaos_bulwark, 0.5)
        end)
    end)

    H.test("WT #1436 Patch 6.6 authority loss restores before refusing", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_6_catalog.lua"))()
            local roots, refs = deepwood_roots_fixture()
            local before = clone(roots)
            local server = true
            local runtime = Runtime.install({
                catalog = catalog,
                is_server = function() return server end,
                mod = mod_fixture({ wt_history_deepwood_staff = "6_5_4" },
                    { value = true }),
                policy = Policy,
                roots = roots,
            })
            H.equal(runtime:verify(), nil)
            H.equal(refs.life_priorities.chaos_bulwark, nil)

            server = false
            local refused = assert(runtime:reapply())
            H.equal(refused.refused, 1)
            H.equal(refused.changed, true,
                "authority-loss restoration is a gameplay change")
            H.deep_equal(roots, before,
                "role loss must restore the exact host-owned projection")
            H.equal(#(runtime.ledgers.deepwood_staff or {}), 0)

            server = true
            local reapplied = assert(runtime:reapply())
            H.equal(reapplied.refused, 0)
            H.equal(reapplied.changed, true)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(refs.life_priorities.chaos_bulwark, nil)
        end)
    end)

    H.test("WT #1436 Patch 3.1 Axe adds and restores an absent current leaf", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_3_2_catalog.lua"))()

            local function roots_with_crit(present, value)
                local bopp_sibling = { damage_profile = "light_slashing_smiter" }
                local template_sibling = { marker = "preserve axe identity" }
                local bopp = {
                    damage_profile = bopp_sibling.damage_profile,
                    metadata = bopp_sibling,
                }
                if present then
                    bopp.additional_critical_strike_chance = value
                end
                local template = {
                    actions = { action_one = { light_attack_bopp = bopp } },
                    metadata = template_sibling,
                    weapon_type = "AXE_1H",
                }
                return {
                    BuffTemplates = {},
                    ExplosionTemplates = {},
                    PlayerUnitStatusSettings = {},
                    Weapons = { we_one_hand_axe_template = template },
                }, {
                    bopp = bopp,
                    bopp_sibling = bopp_sibling,
                    template = template,
                    template_sibling = template_sibling,
                }
            end

            local current_roots, current_refs = roots_with_crit(false)
            local current_before = clone(current_roots)
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_elf_one_handed_axe = "current" },
                    { value = true }),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.elf_one_handed_axe or {}), 0)
            H.deep_equal(current_roots, current_before,
                "Current must leave the absent critical-chance leaf absent")
            H.equal(current_refs.bopp.metadata, current_refs.bopp_sibling)

            local history_roots, history_refs = roots_with_crit(false)
            local history_before = clone(history_roots)
            local history_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_elf_one_handed_axe = "3_1_0" },
                    { value = true }),
                policy = Policy,
                roots = history_roots,
            })
            H.equal(history_runtime.fatal_error, nil)
            H.equal(history_runtime.last_error, nil)
            H.equal(history_runtime:verify(), nil)
            H.equal(#history_runtime.ledgers.elf_one_handed_axe, 1)
            H.equal(history_refs.bopp.additional_critical_strike_chance, 0.1)
            H.equal(history_refs.bopp.metadata, history_refs.bopp_sibling)
            H.equal(history_roots.Weapons.we_one_hand_axe_template,
                history_refs.template)
            H.equal(history_refs.template.metadata, history_refs.template_sibling)

            local restored = assert(history_runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.equal(rawget(history_refs.bopp,
                "additional_critical_strike_chance"), nil)
            H.deep_equal(history_roots, history_before,
                "restore must remove the historically inserted leaf exactly")
            H.equal(assert(history_runtime:restore()).changed, false)

            local mismatch_roots, mismatch_refs = roots_with_crit(true, 0.2)
            local mismatch_before = clone(mismatch_roots)
            local mismatch_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_elf_one_handed_axe = "3_1_0" },
                    { value = true }),
                policy = Policy,
                roots = mismatch_roots,
            })
            H.truthy(mismatch_runtime.last_error
                and mismatch_runtime.last_error:find(
                    "current guard mismatch", 1, true) ~= nil)
            H.equal(#(mismatch_runtime.ledgers.elf_one_handed_axe or {}), 0)
            H.deep_equal(mismatch_roots, mismatch_before,
                "a stale present leaf must refuse before any write")
            H.equal(mismatch_refs.bopp.additional_critical_strike_chance, 0.2)
        end)
    end)

    H.test("WT #1436 Patch 3.1 Tuskgor block cost is atomic and fail-closed", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_3_1_catalog.lua"))()

            local function roots_with_block_cost(present, value)
                local metadata = { marker = "preserve Tuskgor identity" }
                local template = {
                    metadata = metadata,
                    outer_block_fatigue_point_multiplier = 2,
                    weapon_type = "SPEAR_2H",
                }
                if present then
                    template.block_fatigue_point_multiplier = value
                end
                return {
                    BuffTemplates = {},
                    ExplosionTemplates = {},
                    PlayerUnitStatusSettings = {},
                    Weapons = {
                        two_handed_heavy_spears_template = template,
                    },
                }, {
                    metadata = metadata,
                    template = template,
                }
            end

            local current_roots, current_refs = roots_with_block_cost(true, 0.5)
            local current_before = clone(current_roots)
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_tuskgor_spear = "current" },
                    { value = true }),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.tuskgor_spear or {}), 0)
            H.deep_equal(current_roots, current_before)
            H.equal(current_roots.Weapons.two_handed_heavy_spears_template,
                current_refs.template)
            H.equal(current_refs.template.metadata, current_refs.metadata)

            local history_roots, history_refs = roots_with_block_cost(true, 0.5)
            local history_before = clone(history_roots)
            local history_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({
                    wt_history_tuskgor_spear = "pre_3_1_delta",
                }, { value = true }),
                policy = Policy,
                roots = history_roots,
            })
            H.equal(history_runtime.fatal_error, nil)
            H.equal(history_runtime.last_error, nil)
            H.equal(history_runtime:verify(), nil)
            H.equal(#history_runtime.ledgers.tuskgor_spear, 1)
            H.equal(history_refs.template.block_fatigue_point_multiplier, 0.25)
            H.equal(history_refs.template.outer_block_fatigue_point_multiplier, 2)
            H.equal(history_refs.template.metadata, history_refs.metadata)
            H.equal(history_roots.Weapons.two_handed_heavy_spears_template,
                history_refs.template)
            local unchanged = assert(history_runtime:reapply())
            H.equal(unchanged.refused, 0)
            H.equal(unchanged.changed, false)
            H.equal(#history_runtime.ledgers.tuskgor_spear, 1)

            local restored = assert(history_runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.equal(history_refs.template.block_fatigue_point_multiplier, 0.5)
            H.deep_equal(history_roots, history_before)
            H.equal(assert(history_runtime:restore()).changed, false)

            for _, hostile in ipairs({
                { present = true, value = 0.25, label = "historical" },
                { present = true, value = 0.49, label = "foreign" },
                { present = false, label = "absent" },
            }) do
                local hostile_roots, hostile_refs = roots_with_block_cost(
                    hostile.present, hostile.value)
                local hostile_before = clone(hostile_roots)
                local hostile_runtime = Runtime.install({
                    catalog = catalog,
                    mod = mod_fixture({
                        wt_history_tuskgor_spear = "pre_3_1_delta",
                    }, { value = true }),
                    policy = Policy,
                    roots = hostile_roots,
                })
                H.truthy(hostile_runtime.last_error
                    and hostile_runtime.last_error:find(
                        "current guard mismatch", 1, true) ~= nil,
                    hostile.label .. " guard must refuse")
                H.equal(#(hostile_runtime.ledgers.tuskgor_spear or {}), 0)
                H.deep_equal(hostile_roots, hostile_before,
                    hostile.label .. " refusal must occur before writes")
                H.equal(hostile_refs.template.metadata, hostile_refs.metadata)
                H.equal(hostile_refs.template.outer_block_fatigue_point_multiplier, 2)
            end
        end)
    end)

    H.test("WT #1436 Patch 2.0.5 Handguns apply and restore as one six-leaf unit", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_2_0_6_catalog.lua"))()

            local function handgun_roots(hostile_template, hostile_leaf)
                local function template(owner)
                    return {
                        actions = { action_one = {
                            default = {
                                ignore_shield_hit = true,
                                sibling = { owner = owner .. " hipfire" },
                            },
                            zoomed_shot = {
                                ignore_shield_hit = true,
                                sibling = { owner = owner .. " aimed" },
                            },
                        } },
                        presentation = { owner = owner },
                    }
                end
                local roots = {
                    BuffTemplates = {}, ExplosionTemplates = {},
                    PlayerUnitStatusSettings = {}, VortexTemplates = {},
                    Weapons = {
                        handgun_template_1 = template("kruber"),
                        handgun_template_2 = template("bardin"),
                    },
                }
                if hostile_template and hostile_leaf == "armour_present" then
                    roots.Weapons[hostile_template].actions.action_one.zoomed_shot
                        .ignore_armour_hit = true
                elseif hostile_template and hostile_leaf == "hipfire_false" then
                    roots.Weapons[hostile_template].actions.action_one.default
                        .ignore_shield_hit = false
                elseif hostile_template and hostile_leaf == "aimed_absent" then
                    roots.Weapons[hostile_template].actions.action_one.zoomed_shot
                        .ignore_shield_hit = nil
                end
                return roots
            end

            local current_roots = handgun_roots()
            local current_before = clone(current_roots)
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_handgun_shared = "current" },
                    { value = true }),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.handgun_shared or {}), 0)
            H.deep_equal(current_roots, current_before,
                "Current must not touch either Handgun clone")

            local historical_roots = handgun_roots()
            local historical_before = clone(historical_roots)
            local runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_handgun_shared = "2_0_5" },
                    { value = true }),
                policy = Policy,
                roots = historical_roots,
            })
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#runtime.ledgers.handgun_shared, 6)
            for template_name, template in pairs(historical_roots.Weapons) do
                local actions = template.actions.action_one
                H.equal(actions.default.ignore_shield_hit, nil,
                    template_name .. " hipfire must return to shield-blockable")
                H.equal(actions.zoomed_shot.ignore_shield_hit, nil,
                    template_name .. " aimed shield route must be absent")
                H.equal(actions.zoomed_shot.ignore_armour_hit, true,
                    template_name .. " aimed armour route must be restored")
                H.truthy(actions.default.sibling)
                H.truthy(actions.zoomed_shot.sibling)
                H.truthy(template.presentation)
            end
            H.equal(assert(runtime:reapply()).changed, false)
            local restored = assert(runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.deep_equal(historical_roots, historical_before,
                "restore must recover both exact current Handgun clones")
            H.equal(assert(runtime:restore()).changed, false)

            for _, hostile in ipairs({
                { template = "handgun_template_1", leaf = "armour_present" },
                { template = "handgun_template_2", leaf = "hipfire_false" },
                { template = "handgun_template_2", leaf = "aimed_absent" },
            }) do
                local hostile_roots = handgun_roots(
                    hostile.template, hostile.leaf)
                local hostile_before = clone(hostile_roots)
                local hostile_runtime = Runtime.install({
                    catalog = catalog,
                    mod = mod_fixture({
                        wt_history_handgun_shared = "2_0_5",
                    }, { value = true }),
                    policy = Policy,
                    roots = hostile_roots,
                })
                H.truthy(hostile_runtime.last_error
                    and hostile_runtime.last_error:find(
                        "current guard mismatch", 1, true), hostile.leaf)
                H.equal(#(hostile_runtime.ledgers.handgun_shared or {}), 0)
                H.deep_equal(hostile_roots, hostile_before,
                    "one hostile clone must refuse before all six writes")
            end
        end)
    end)

    H.test("WT #1436 Patch 6.7.2 changes only Greatsword first-heavy range", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_6_8_catalog.lua"))()

            local function roots_with_range(range_mod)
                local heavy_sibling = { damage_profile = "heavy_slashing_linesman" }
                local light_sibling = { range_mod = 1.25 }
                local template_sibling = { marker = "preserve exact identity" }
                local heavy = {
                    damage_profile = heavy_sibling.damage_profile,
                    range_mod = range_mod,
                    total_time = 1.4,
                }
                local template = {
                    actions = {
                        action_one = {
                            heavy_attack_down_first = heavy,
                            light_attack_left = light_sibling,
                        },
                    },
                    metadata = template_sibling,
                    weapon_type = "SWORD_2H",
                }
                return {
                    BuffTemplates = {},
                    ExplosionTemplates = {},
                    PlayerUnitStatusSettings = {},
                    Weapons = {
                        two_handed_swords_wood_elf_template = template,
                    },
                }, {
                    heavy = heavy,
                    light_sibling = light_sibling,
                    template = template,
                    template_sibling = template_sibling,
                }
            end

            local current_roots, current_refs = roots_with_range(1.55)
            local current_before = clone(current_roots)
            local current_mod = mod_fixture({
                wt_history_elf_greatsword = "current",
            }, { value = true })
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = current_mod,
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.elf_greatsword or {}), 0)
            H.deep_equal(current_roots, current_before,
                "Current must perform no gameplay writes")
            H.equal(current_roots.Weapons.two_handed_swords_wood_elf_template,
                current_refs.template)
            H.equal(current_refs.template.metadata, current_refs.template_sibling)
            local current_restore = assert(current_runtime:restore())
            H.equal(current_restore.changed, false)
            H.deep_equal(current_roots, current_before,
                "restoring an already-current family must remain a no-op")

            local history_roots, history_refs = roots_with_range(1.55)
            local history_before = clone(history_roots)
            local expected_historical = clone(history_before)
            expected_historical.Weapons.two_handed_swords_wood_elf_template
                .actions.action_one.heavy_attack_down_first.range_mod = 1.45
            local history_mod = mod_fixture({
                wt_history_elf_greatsword = "6_7_2",
            }, { value = true })
            local history_runtime = Runtime.install({
                catalog = catalog,
                mod = history_mod,
                policy = Policy,
                roots = history_roots,
            })
            H.equal(history_runtime.fatal_error, nil)
            H.equal(history_runtime.last_error, nil)
            H.equal(history_runtime:verify(), nil)
            H.equal(#history_runtime.ledgers.elf_greatsword, 1)
            H.deep_equal(history_roots, expected_historical,
                "6.7.2 must alter only heavy_attack_down_first.range_mod")
            H.equal(history_refs.heavy.range_mod, 1.45)
            H.equal(history_refs.heavy.total_time, 1.4)
            H.equal(history_refs.light_sibling,
                history_refs.template.actions.action_one.light_attack_left)
            H.equal(history_refs.template_sibling, history_refs.template.metadata)

            local restored = assert(history_runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.deep_equal(history_roots, history_before,
                "history restore must recover the exact current source state")
            H.equal(history_refs.heavy.range_mod, 1.55)
            local second_restore = assert(history_runtime:restore())
            H.equal(second_restore.changed, false)
            H.deep_equal(history_roots, history_before,
                "repeated restore must not introduce writes")

            local mismatch_roots, mismatch_refs = roots_with_range(1.56)
            local mismatch_before = clone(mismatch_roots)
            local mismatch_mod = mod_fixture({
                wt_history_elf_greatsword = "6_7_2",
            }, { value = true })
            local mismatch_runtime = Runtime.install({
                catalog = catalog,
                mod = mismatch_mod,
                policy = Policy,
                roots = mismatch_roots,
            })
            H.equal(mismatch_runtime.fatal_error, nil)
            H.truthy(mismatch_runtime.last_error
                and mismatch_runtime.last_error:find(
                    "current guard mismatch", 1, true) ~= nil)
            H.equal(#(mismatch_runtime.ledgers.elf_greatsword or {}), 0)
            H.deep_equal(mismatch_roots, mismatch_before,
                "guard mismatch must refuse before the first mutation")
            H.equal(mismatch_refs.heavy.range_mod, 1.56)
            H.equal(mismatch_refs.light_sibling,
                mismatch_refs.template.actions.action_one.light_attack_left)
            H.equal(mismatch_refs.template_sibling, mismatch_refs.template.metadata)
        end)
    end)

    H.test("WT #1436 Patch 4.0.1 restores Masterwork Pistol present false exactly", function()
        with_profile_globals(function()
            local catalog = assert(loadfile(script_root
                .. "_wt_history_4_1_1_catalog.lua"))()

            local function roots_with_reload(present, value)
                local ammo_sibling = { marker = "ammo sibling" }
                local template_sibling = { marker = "template sibling" }
                local ammo_data = { metadata = ammo_sibling }
                if present then ammo_data.reload_on_ammo_pickup = value end
                local template = {
                    ammo_data = ammo_data,
                    metadata = template_sibling,
                    weapon_type = "MASTERWORK_PISTOL",
                }
                return {
                    BuffTemplates = {}, ExplosionTemplates = {},
                    PlayerUnitStatusSettings = {}, VortexTemplates = {},
                    Weapons = { heavy_steam_pistol_template_1 = template },
                }, {
                    ammo_data = ammo_data,
                    ammo_sibling = ammo_sibling,
                    template = template,
                    template_sibling = template_sibling,
                }
            end

            local current_roots, current_refs = roots_with_reload(true, false)
            local current_before = clone(current_roots)
            local current_runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_masterwork_pistol = "current" },
                    { value = true }),
                policy = Policy,
                roots = current_roots,
            })
            H.equal(current_runtime.fatal_error, nil)
            H.equal(current_runtime.last_error, nil)
            H.equal(current_runtime:verify(), nil)
            H.equal(#(current_runtime.ledgers.masterwork_pistol or {}), 0)
            H.equal(rawget(current_refs.ammo_data,
                "reload_on_ammo_pickup") ~= nil, true)
            H.equal(current_refs.ammo_data.reload_on_ammo_pickup, false)
            H.deep_equal(current_roots, current_before,
                "Current must leave the present-false source value untouched")
            H.equal(current_roots.Weapons.heavy_steam_pistol_template_1,
                current_refs.template)
            H.equal(current_refs.ammo_data.metadata, current_refs.ammo_sibling)
            H.equal(current_refs.template.metadata, current_refs.template_sibling)

            local roots, refs = roots_with_reload(true, false)
            local before = clone(roots)
            local runtime = Runtime.install({
                catalog = catalog,
                mod = mod_fixture({ wt_history_masterwork_pistol = "4_0_1" },
                    { value = true }),
                policy = Policy,
                roots = roots,
            })
            H.equal(runtime.fatal_error, nil)
            H.equal(runtime.last_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#runtime.ledgers.masterwork_pistol, 1)
            H.equal(rawget(refs.ammo_data, "reload_on_ammo_pickup") ~= nil, true)
            H.equal(refs.ammo_data.reload_on_ammo_pickup, true)
            H.equal(roots.Weapons.heavy_steam_pistol_template_1, refs.template)
            H.equal(refs.ammo_data.metadata, refs.ammo_sibling)
            H.equal(refs.template.metadata, refs.template_sibling)

            local reapplied = assert(runtime:reapply())
            H.equal(reapplied.changed, false,
                "an unchanged historical selection must be idempotent")
            H.equal(rawget(refs.ammo_data, "reload_on_ammo_pickup") ~= nil, true)
            H.equal(refs.ammo_data.reload_on_ammo_pickup, true)
            H.equal(roots.Weapons.heavy_steam_pistol_template_1, refs.template)
            H.equal(refs.ammo_data.metadata, refs.ammo_sibling)

            local restored = assert(runtime:restore())
            H.equal(restored.refused, 0)
            H.equal(restored.changed, true)
            H.equal(rawget(refs.ammo_data, "reload_on_ammo_pickup") ~= nil, true)
            H.equal(refs.ammo_data.reload_on_ammo_pickup, false)
            H.deep_equal(roots, before,
                "restore must recover present false, not collapse it to absence")
            H.equal(roots.Weapons.heavy_steam_pistol_template_1, refs.template)
            H.equal(refs.ammo_data.metadata, refs.ammo_sibling)
            H.equal(refs.template.metadata, refs.template_sibling)
            H.equal(assert(runtime:restore()).changed, false)

            for _, hostile in ipairs({
                { present = false, label = "absent" },
                { present = true, value = true, label = "true" },
            }) do
                local hostile_roots, hostile_refs = roots_with_reload(
                    hostile.present, hostile.value)
                local hostile_before = clone(hostile_roots)
                local hostile_runtime = Runtime.install({
                    catalog = catalog,
                    mod = mod_fixture({ wt_history_masterwork_pistol = "4_0_1" },
                        { value = true }),
                    policy = Policy,
                    roots = hostile_roots,
                })
                H.equal(hostile_runtime.fatal_error, nil)
                H.truthy(hostile_runtime.last_error
                    and hostile_runtime.last_error:find(
                        "current guard mismatch", 1, true) ~= nil,
                    hostile.label .. " guard must reject")
                H.equal(#(hostile_runtime.ledgers.masterwork_pistol or {}), 0)
                H.deep_equal(hostile_roots, hostile_before,
                    hostile.label .. " guard mismatch must write nothing")
                H.equal(hostile_roots.Weapons.heavy_steam_pistol_template_1,
                    hostile_refs.template)
                H.equal(hostile_refs.ammo_data.metadata, hostile_refs.ammo_sibling)
            end
        end)
    end)

    H.test("WT #1436 commit rollback restores an original present false", function()
        local original_parent = { flag = false }
        local plan = {
            {
                applied_value = true,
                key = "flag",
                original_present = true,
                original_value = false,
                parent = original_parent,
            },
            {
                applied_value = true,
                key = "forced_failure",
                original_present = false,
                parent = false,
            },
        }
        local committed, commit_error = Policy.commit(plan)
        H.equal(committed, nil)
        H.truthy(commit_error
            and commit_error:find("history commit failed at 2", 1, true) ~= nil)
        H.equal(rawget(original_parent, "flag") ~= nil, true,
            "rollback must preserve the original key presence")
        H.equal(original_parent.flag, false,
            "rollback must restore false rather than delete the key")
    end)

    H.test("WT #1436 Current registers profiles but performs no gameplay writes", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "current" }, parity)
            local template = roots.Weapons.we_1h_axe_template_1
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.equal(runtime.fatal_error, nil)
            H.equal(runtime:verify(), nil)
            H.equal(#(runtime.ledgers.elf_one_handed_axe or {}), 0)
            H.equal(template.stats.tuning, original_tuning,
                "Current must preserve exact native table identity")
            H.equal(template.stats.tempo, 10)
            H.equal(template.actions.action_one.default.damage_profile, "native_profile")
            H.truthy(DamageProfileTemplates.wt_hist_5_1_1_native_profile ~= nil,
                "private profiles must be catalogued before #431 fingerprints them")
        end)
    end)

    H.test("WT #1436 family preflight guard failure performs zero gameplay writes", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local template = roots.Weapons.we_1h_axe_template_1
            template.stats.tempo = 999
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "5_1_1" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.truthy(runtime.last_error
                and runtime.last_error:find("current guard mismatch", 1, true))
            H.equal(#(runtime.ledgers.elf_one_handed_axe or {}), 0)
            H.equal(template.stats.tuning, original_tuning,
                "an earlier valid operation must not leak past a later failed guard")
            H.equal(template.stats.tempo, 999)
            H.equal(template.actions.action_one.default.damage_profile, "native_profile")
        end)
    end)

    H.test("WT #1436 missing direct profile route refuses the whole family", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local template = roots.Weapons.we_1h_axe_template_1
            template.actions.action_one.default.damage_profile = "renamed_profile"
            local parity = { value = true }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "5_1_1" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.truthy(runtime.last_error
                and runtime.last_error:find("native profile route not found native_profile",
                    1, true))
            H.equal(#(runtime.ledgers.elf_one_handed_axe or {}), 0,
                "a missing direct route must refuse before any family commit")
            H.equal(template.stats.tuning, original_tuning)
            H.equal(template.stats.tempo, 10)
            H.equal(template.actions.action_one.default.damage_profile, "renamed_profile")
        end)
    end)

    H.test("WT #1436 settings are restart-latched and never hot-apply", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "current" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })
            mod.selections.wt_history_elf_one_handed_axe = "5_1_1"
            H.equal(runtime:on_setting_changed("wt_history_elf_one_handed_axe"), true)
            H.equal(runtime.pending.wt_history_elf_one_handed_axe, true)
            H.equal(roots.Weapons.we_1h_axe_template_1.stats.tuning, original_tuning)
            H.equal(roots.Weapons.we_1h_axe_template_1.stats.tempo, 10)
            H.equal(runtime:on_setting_changed("unrelated_setting"), false)

            mod.selections.wt_history_elf_one_handed_axe = "current"
            H.equal(runtime:on_setting_changed("wt_history_elf_one_handed_axe"), true)
            H.equal(runtime.pending.wt_history_elf_one_handed_axe, nil)
        end)
    end)

    H.test("WT #1436 lifecycle owner reconciles history before ordinary overlays", function()
        local events = {}
        local runtime = {
            reapply = function()
                events[#events + 1] = "history_reapply"
                return { refused = 0 }
            end,
            restore = function()
                events[#events + 1] = "history_restore"
                return { refused = 0 }
            end,
        }
        local catalog = catalog_fixture()
        local policy = {}
        local runtime_config
        local modules = {
            ["test/_wt_history_catalog"] = {
                load = function() return catalog end,
            },
            ["test/_wt_history_policy"] = policy,
            ["test/_wt_history_runtime"] = {
                install = function(config)
                    runtime_config = config
                    return runtime
                end,
            },
        }
        local mod = {}
        function mod:dofile(path) return assert(modules[path], path) end
        function mod._wt_apply_axe_balance(_, revert)
            events[#events + 1] = revert and "axe_revert" or "axe_reapply"
        end
        function mod._wt_reset_axe_balance_baselines()
            events[#events + 1] = "axe_reset"
            return true
        end

        local owner = HistoryOwner.install({ mod = mod, module_root = "test/" })
        H.equal(owner.runtime, runtime)
        H.equal(mod._wt_history_runtime, runtime)
        H.equal(runtime_config.catalog, catalog)
        H.equal(runtime_config.policy, policy)
        H.equal(type(runtime_config.is_server), "function")
        H.equal(type(runtime_config.roots), "function")

        local prior_managers = rawget(_G, "Managers")
        local manager_outcome = { xpcall(function()
            rawset(_G, "Managers", nil)
            H.equal(runtime_config.is_server(), false,
                "missing Managers must fail closed as a client")
            rawset(_G, "Managers", {})
            H.equal(runtime_config.is_server(), false,
                "missing player manager must fail closed as a client")
            local player = { is_server = false }
            rawset(_G, "Managers", { player = player })
            H.equal(runtime_config.is_server(), false)
            player.is_server = true
            H.equal(runtime_config.is_server(), true,
                "live host promotion must be observed without reinstall")
            player.is_server = false
            H.equal(runtime_config.is_server(), false,
                "live authority loss must be observed without reinstall")
            rawset(_G, "Managers", { player = { is_server = true } })
            H.equal(runtime_config.is_server(), true,
                "manager replacement must be read at call time")
        end, debug.traceback) }
        rawset(_G, "Managers", prior_managers)
        if not manager_outcome[1] then error(manager_outcome[2], 0) end

        H.equal(owner:reconcile("test"), true)
        H.deep_equal(events, {
            "axe_revert", "axe_reset", "history_reapply", "axe_reapply",
        })
        events = {}
        H.equal(owner:restore(), true)
        H.deep_equal(events, { "axe_revert", "axe_reset", "history_restore" })
        H.equal(type(mod._wt_reconcile_history_owner_stack), "function")
    end)

    H.test("WT #1436 private profile registration is idempotent and isolated", function()
        with_profile_globals(function(native_profile)
            local catalog = catalog_fixture()
            local roots = roots_fixture()
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "current" }, parity)
            local first = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })
            local private = DamageProfileTemplates.wt_hist_5_1_1_native_profile
            local lookup_count = #NetworkLookup.damage_profiles
            local second = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy, roots = roots,
            })

            H.equal(first.registration.count, 1)
            H.equal(second.registration.count, 1)
            H.equal(DamageProfileTemplates.wt_hist_5_1_1_native_profile, private,
                "idempotent install must retain the registered object")
            H.equal(#NetworkLookup.damage_profiles, lookup_count,
                "idempotent install must not append another network row")
            H.equal(NetworkLookup.damage_profiles[private.name], lookup_count)
            H.truthy(private ~= catalog.profile_specs["5_1_1"].native_profile.historical_profile)
            H.truthy(private ~= native_profile)
            H.truthy(private.default_target
                ~= catalog.profile_specs["5_1_1"].native_profile.historical_profile.default_target)
            private.default_target.power_distribution.attack = 123
            H.equal(catalog.profile_specs["5_1_1"].native_profile
                .historical_profile.default_target.power_distribution.attack, 5,
                "registered mutations must not contaminate generated evidence")
            H.equal(native_profile.default_target.power_distribution.attack, 3,
                "registered mutations must not contaminate the native fallback")
            H.equal(mod._wt431_custom_profile_fallback[private.name], "native_profile")
        end)
    end)

    H.test("WT #1436 profile assignment gates on parity and lifecycle replacement reapplies", function()
        with_profile_globals(function()
            local catalog = catalog_fixture()
            local roots, original_tuning = roots_fixture()
            local old_roots = roots
            local parity = { value = false }
            local mod = mod_fixture({ wt_history_elf_one_handed_axe = "5_1_1" }, parity)
            local runtime = Runtime.install({
                catalog = catalog, mod = mod, policy = Policy,
                roots = function() return roots end,
            })
            local old_template = roots.Weapons.we_1h_axe_template_1
            H.equal(runtime:verify(), nil)
            H.equal(old_template.stats.tempo, 8)
            H.equal(old_template.actions.action_one.default.damage_profile, "native_profile",
                "mixed/mismatched peers must retain the native profile")
            H.equal(runtime.active.elf_one_handed_axe.parity, false)

            parity.value = true
            local parity_result = assert(runtime:reapply())
            H.equal(parity_result.refused, 0)
            H.equal(old_template.actions.action_one.default.damage_profile,
                "wt_hist_5_1_1_native_profile")
            H.equal(runtime:verify(), nil)

            local replacement_tuning
            roots, replacement_tuning = roots_fixture()
            local replacement = roots.Weapons.we_1h_axe_template_1
            local lifecycle_result = assert(runtime:reapply())
            H.equal(lifecycle_result.refused, 0)
            H.equal(old_roots.Weapons.we_1h_axe_template_1.stats.tuning, original_tuning,
                "reapply must restore the exact superseded native reference")
            H.equal(old_template.stats.tempo, 10)
            H.equal(old_template.actions.action_one.default.damage_profile, "native_profile")
            H.equal(replacement.stats.tempo, 8)
            H.equal(replacement.actions.action_one.default.damage_profile,
                "wt_hist_5_1_1_native_profile")
            H.equal(runtime:verify(), nil)

            local restore_result = assert(runtime:restore())
            H.equal(restore_result.refused, 0)
            H.equal(replacement.stats.tuning, replacement_tuning,
                "disable restore must preserve the exact replacement baseline reference")
            H.equal(replacement.stats.tempo, 10)
            H.equal(replacement.actions.action_one.default.damage_profile, "native_profile")
        end)
    end)

    H.test("WT #1436 generated Elf Axe moveset is one exact atomic plan", function()
        local catalog = assert(loadfile(script_root .. "_wt_history_5_2_catalog.lua"))()
        local family
        for _, candidate in ipairs(catalog.families) do
            if candidate.id == "elf_one_handed_axe" then family = candidate end
        end
        H.truthy(family, "generated catalog must own Elf 1H Axe")
        local state = family.states["5_1_1"]
        H.equal(state.atomic_group, "P520-ELF1HA-MOVESET")
        H.truthy(#state.operations > 1)

        local roots, originals = materialize_expected_roots(state)
        local corrupt = originals[#originals]
        rawset(corrupt.parent, corrupt.key, { deliberately = "wrong" })
        local rejected, rejection = Policy.build_family_plan(
            catalog, family, "5_1_1", roots, { validated = true })
        H.equal(rejected, nil)
        H.truthy(rejection and rejection:find("current guard mismatch", 1, true))
        for index = 1, #originals - 1 do
            H.equal(rawget(originals[index].parent, originals[index].key),
                originals[index].value,
                "failed atomic preflight must not touch any earlier Elf Axe member")
        end

        rawset(corrupt.parent, corrupt.key, corrupt.value)
        local plan = assert(Policy.build_family_plan(
            catalog, family, "5_1_1", roots, { validated = true }))
        H.equal(#plan, #state.operations,
            "the entire source-exact moveset must commit as one plan")
        H.equal(plan[1].original_value, originals[1].value,
            "planning must retain the exact original table identity")
        H.truthy(plan[1].applied_value ~= plan[1].applied_snapshot,
            "applied table value and ownership snapshot must be separate clones")
        local ledger = assert(Policy.commit(plan))
        H.equal(Policy.ledger_status(ledger, roots), "same")
        H.equal(Policy.restore(ledger), true)
        for index, original in ipairs(originals) do
            H.equal(rawget(original.parent, original.key), original.value,
                "restore must recover exact pre-patch reference at operation " .. index)
        end
    end)

    H.test("WT #1436 nested mutation loses history restore ownership", function()
        local catalog = catalog_fixture()
        local roots, original_tuning = roots_fixture()
        local family = catalog.families[1]
        local plan = assert(Policy.build_family_plan(
            catalog, family, "5_1_1", roots))
        local ledger = assert(Policy.commit(plan))
        local applied_tuning = roots.Weapons.we_1h_axe_template_1.stats.tuning

        H.equal(Policy.ledger_status(ledger, roots), "same")
        applied_tuning.cleave[1] = 999
        H.equal(Policy.ledger_status(ledger, roots), "drift",
            "in-place mutation of a history-owned table must be detected")

        local restored, restore_error = Policy.restore(ledger)
        H.equal(restored, nil,
            "history must not overwrite a value whose nested ownership was lost")
        H.truthy(restore_error
            and restore_error:find("restore ownership lost", 1, true))
        H.equal(roots.Weapons.we_1h_axe_template_1.stats.tuning, applied_tuning,
            "failed restore must leave the third-party-mutated reference untouched")
        H.equal(original_tuning.cleave[1], 1,
            "history application and drift must not mutate the native baseline")
    end)

    H.test("WT #1436 historical 1H Axe profiles prewarm and compose safely", function()
        local state = AxeBalance.new()
        local history_name = "wt_hist_5_1_1_medium_slashing_smiter_1h_axe"
        local native_name = "medium_slashing_smiter_1h_axe"
        local weapon = {
            actions = { action_one = { light_attack_left = {
                damage_profile = history_name, kind = "sweep",
            } } },
            buff_type = "MELEE_1H",
            state_machine = "units/beings/player/first_person_base/state_machines/melee/1h_axe",
            weapon_type = "AXE_1H",
        }
        local weapons = { one_hand_axe_template_1 = weapon }
        local profiles = {
            [native_name] = { cleave_distribution = { attack = 1, impact = 2 } },
            [history_name] = { cleave_distribution = { attack = 3, impact = 4 } },
        }
        local power_levels, registered = {}, {}
        local fallbacks = { [history_name] = native_name }
        local function register(name) registered[name] = true end
        state:apply_one_hand_axe_cleave(false, weapons, profiles, power_levels,
            clone, register, fallbacks, false, { history_name })
        local derived = "wt_1h_axe_cleave_90_" .. history_name
        H.truthy(profiles[derived] ~= nil,
            "history composition profile must exist before #431 capture")
        H.equal(fallbacks[derived], native_name,
            "derived history profile must fall back directly to a native donor")
        H.equal(registered[derived], true)

        state:apply_one_hand_axe_cleave(true, weapons, profiles, power_levels,
            clone, register, fallbacks, true, { history_name })
        H.equal(weapon.actions.action_one.light_attack_left.damage_profile, derived)
        state:apply_one_hand_axe_cleave(false, weapons, profiles, power_levels,
            clone, register, fallbacks, false, { history_name })
        H.equal(weapon.actions.action_one.light_attack_left.damage_profile, history_name)
        H.equal(state:reset_baselines(), true)
    end)
end

return register
