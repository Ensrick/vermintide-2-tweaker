-- Behavioral coverage for the #943 Fire Sword heavy-attack policy.
--
-- Drives the shipped policy module against a fixture shaped from the
-- decompiled vanilla template (1h_swords_wizard.lua :28-65 default edges,
-- :394-472 heavy_attack_spell) plus the shipped settings-runtime dispatch.
return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_fire_sword.lua")

    local function clone(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local copy = {}
        seen[value] = copy
        for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
        return copy
    end

    -- Vanilla-shaped Fire Sword template (values from the decompile).
    local function fire_sword_template()
        return {
            actions = {
                action_one = {
                    default = {
                        kind = "melee_start",
                        total_time = math.huge,
                        allowed_chain_actions = {
                            { action = "action_one", end_time = 0.3, input = "action_one_release", start_time = 0, sub_action = "light_attack_left" },
                            { action = "action_one", input = "action_one_release", start_time = 0.5, sub_action = "heavy_attack_spell" },
                            { action = "action_two", input = "action_two_hold", start_time = 0, sub_action = "default" },
                            { action = "action_wield", input = "action_wield", start_time = 0, sub_action = "default" },
                            { blocker = true, end_time = 1.2, input = "action_one_hold", start_time = 0.3 },
                            { action = "action_one", auto_chain = true, start_time = 1.2, sub_action = "heavy_attack_spell" },
                        },
                    },
                    default_right = {
                        kind = "melee_start",
                        allowed_chain_actions = {
                            { action = "action_one", input = "action_one_release", start_time = 0.7, sub_action = "heavy_attack_spell" },
                            { action = "action_one", auto_chain = true, start_time = 1.2, sub_action = "heavy_attack_spell" },
                        },
                    },
                    heavy_attack_spell = {
                        kind = "shield_slam",
                        anim_time_scale = 1.4,
                        total_time = 1.5,
                        hit_time = 0.35,
                        damage_window_start = 0.2,
                        damage_window_end = 0.25,
                        damage_profile = "dagger_burning_slam",
                        buff_data = {
                            { buff_name = "planted_fast_decrease_movement", end_time = 0.2, external_multiplier = 1.1, start_time = 0 },
                        },
                        allowed_chain_actions = {
                            { action = "action_one", end_time = 1.25, input = "action_one", release_required = "action_one_hold", start_time = 0.65, sub_action = "default_right_heavy" },
                            { action = "action_one", end_time = 1.25, input = "action_one_hold", release_required = "action_one_hold", start_time = 0.65, sub_action = "default_right_heavy" },
                            { action = "action_one", input = "action_one", start_time = 1, sub_action = "default" },
                            { action = "action_two", input = "action_two_hold", start_time = 0.55, sub_action = "default" },
                            { action = "action_wield", input = "action_wield", start_time = 0.5, sub_action = "default" },
                        },
                    },
                    heavy_attack_left = {
                        kind = "sweep",
                        anim_time_scale = 1.25,
                        total_time = 2.25,
                        damage_window_start = 0.13,
                        damage_window_end = 0.27,
                    },
                    light_attack_left = {
                        kind = "sweep",
                        anim_time_scale = 1.25,
                        total_time = 2.1,
                    },
                    push = { kind = "push_stagger" },
                },
            },
        }
    end

    H.test("WT #943 sweep opener repoints only the two idle heavy edges", function()
        local template = fire_sword_template()
        local pristine = clone(template)
        local weapons = { flaming_sword_template_1 = template }
        local state = policy.new()

        local edges, novas = state:apply(true, false, weapons)
        H.equal(edges, 2)
        H.equal(novas, 1)
        local chain = template.actions.action_one.default.allowed_chain_actions
        H.equal(chain[2].sub_action, "heavy_attack_left", "charged release must open with the sweep")
        H.equal(chain[6].sub_action, "heavy_attack_left", "auto-chain must open with the sweep")
        -- Everything else — light release, block/wield edges, the blocker, the
        -- sweep-to-nova continuation, and every action's timing — stays vanilla.
        chain[2].sub_action = "heavy_attack_spell"
        chain[6].sub_action = "heavy_attack_spell"
        H.deep_equal(template, pristine,
            "sweep opener must not touch anything beyond the two idle edges")
    end)

    H.test("WT #943 nova slowdown stretches exactly the nova's bounded clock", function()
        local template = fire_sword_template()
        local pristine = clone(template)
        local weapons = { flaming_sword_template_1 = template }
        local state = policy.new()

        state:apply(false, true, weapons)
        local nova = template.actions.action_one.heavy_attack_spell
        local function near(actual, expected, label)
            H.truthy(math.abs(actual - expected) < 0.000001, label
                .. " expected " .. tostring(expected) .. " got " .. tostring(actual))
        end
        near(nova.anim_time_scale, 1.4 / 1.10, "anim_time_scale")
        near(nova.total_time, 1.5 * 1.10, "total_time")
        near(nova.hit_time, 0.35 * 1.10, "hit_time")
        near(nova.damage_window_start, 0.2 * 1.10, "damage_window_start")
        near(nova.damage_window_end, 0.25 * 1.10, "damage_window_end")
        near(nova.buff_data[1].end_time, 0.2 * 1.10, "buff end_time")
        H.equal(nova.buff_data[1].start_time, 0)
        near(nova.allowed_chain_actions[1].start_time, 0.65 * 1.10, "chain start_time")
        near(nova.allowed_chain_actions[1].end_time, 1.25 * 1.10, "chain end_time")
        near(nova.allowed_chain_actions[3].start_time, 1 * 1.10, "combo reset start_time")
        -- The opener still routes to the nova and no other action drifted.
        local chain = template.actions.action_one.default.allowed_chain_actions
        H.equal(chain[2].sub_action, "heavy_attack_spell")
        H.equal(chain[6].sub_action, "heavy_attack_spell")
        H.deep_equal(template.actions.action_one.heavy_attack_left,
            pristine.actions.action_one.heavy_attack_left,
            "sweep timing must stay vanilla under the nova slowdown")
        H.deep_equal(template.actions.action_one.light_attack_left,
            pristine.actions.action_one.light_attack_left,
            "light timing must stay vanilla under the nova slowdown")
        H.deep_equal(template.actions.action_one.default_right,
            pristine.actions.action_one.default_right,
            "non-idle chain sources must stay vanilla")
    end)

    H.test("WT #943 both options compose and project without compounding", function()
        local template = fire_sword_template()
        local weapons = { flaming_sword_template_1 = template }
        local state = policy.new()

        state:apply(true, true, weapons)
        state:apply(true, true, weapons)
        state:apply(true, true, weapons)
        local chain = template.actions.action_one.default.allowed_chain_actions
        local nova = template.actions.action_one.heavy_attack_spell
        H.equal(chain[2].sub_action, "heavy_attack_left")
        H.equal(chain[6].sub_action, "heavy_attack_left")
        H.truthy(math.abs(nova.anim_time_scale - 1.4 / 1.10) < 0.000001,
            "repeated applies must never divide the anim scale twice")
        H.truthy(math.abs(nova.total_time - 1.65) < 0.000001,
            "repeated applies must never stretch the clock twice")
    end)

    H.test("WT #943 toggling off restores the exact captured baseline", function()
        local template = fire_sword_template()
        local pristine = clone(template)
        local weapons = { flaming_sword_template_1 = template }
        local state = policy.new()

        -- Exercise every reachable menu order, ending disabled.
        state:apply(true, false, weapons)
        state:apply(true, true, weapons)
        state:apply(false, true, weapons)
        state:apply(true, true, weapons)
        state:apply(false, false, weapons)
        H.deep_equal(template, pristine,
            "off-off must restore the vanilla template exactly")

        -- A second full cycle from the SAME state proves the baseline is
        -- immutable: the second capture never happens, the projection still
        -- lands on baseline values.
        state:apply(true, true, weapons)
        state:apply(false, false, weapons)
        H.deep_equal(template, pristine,
            "repeated cycles must not drift the restored values")
    end)

    H.test("WT #943 capture is per template identity, never shared", function()
        local first = fire_sword_template()
        local second = fire_sword_template()
        local pristine = clone(second)
        local state = policy.new()

        state:apply(true, true, { flaming_sword_template_1 = first })
        H.deep_equal(second, pristine,
            "projecting one template identity must not touch another")

        -- A replaced (late-loaded) template gets its own fresh vanilla capture.
        state:apply(true, false, { flaming_sword_template_1 = second })
        local chain = second.actions.action_one.default.allowed_chain_actions
        H.equal(chain[2].sub_action, "heavy_attack_left")
        H.equal(second.actions.action_one.heavy_attack_spell.anim_time_scale, 1.4,
            "slowdown off must leave the replacement template's clock vanilla")
        state:apply(false, false, { flaming_sword_template_1 = second })
        H.deep_equal(second, pristine)
    end)

    H.test("WT #943 settings runtime dispatches both fire sword toggles", function()
        local runtime = assert(loadfile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_settings_runtime.lua"))()
        local applied = {}
        local mod = {
            _wt_apply_fire_sword = function(setting_id, force_off)
                applied[#applied + 1] = { setting_id = setting_id, force_off = force_off }
            end,
            _wt_apply_axe_balance = function() end,
        }
        runtime.install({
            mod = mod,
            rework_runtime = {
                is_batching = function() return false end,
                on_master_changed = function() return false end,
                sync_for_leaf = function() end,
                prepare_batch = function() return true end,
            },
            master_toggles = {
                reconcile_batch = function() end,
                on_master_changed = function() end,
                on_child_changed = function() end,
            },
            backend = {
                refresh_on_setting_change = function() end,
                clear_loadout_cache = function() end,
            },
            apply_weapon_unlocks = function() end,
            patch_career_actions = function() end,
            apply_trait_filters = function() end,
            bolt_policy = { SETTING_ID = "bolt" },
            bolt_runtime = { apply = function() end },
            balance_policy = {},
            fire_sword_policy = policy,
        })

        mod.on_setting_changed(policy.SWEEP_OPENER_SETTING)
        mod.on_setting_changed(policy.NOVA_SLOWDOWN_SETTING)
        mod.on_setting_changed("unrelated_setting")
        H.equal(#applied, 2, "exactly the two fire sword settings must dispatch")
        H.equal(applied[1].setting_id, policy.SWEEP_OPENER_SETTING)
        H.equal(applied[1].force_off, false)
        H.equal(applied[2].setting_id, policy.NOVA_SLOWDOWN_SETTING)

        mod.on_settings_batch_changed({ "unlock_a", policy.SWEEP_OPENER_SETTING })
        H.equal(#applied, 3, "an owner batch must rerun the bounded apply once")
        H.equal(applied[3].setting_id, nil)
        H.equal(applied[3].force_off, false)
    end)
end
