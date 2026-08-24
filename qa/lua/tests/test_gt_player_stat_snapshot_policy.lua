return function(H, repo_root)
    local core = dofile(repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_player_stat_snapshot_policy.lua")
    local hud = dofile(repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_player_stat_hud_policy.lua")
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    H.test("GT #797 preserves retained stage keys and active source identity", function()
        local snapshot = core.normalize({
            attack_speed = {
                [0] = { bonus = 0, multiplier = 0.1, proc_chance = 1 },
                swift_stage = { bonus = 0, multiplier = 0.2, proc_chance = 1 },
            },
        }, { attack_speed = "stacking_multiplier_multiplicative" }, {
            [41] = {
                id = 41,
                buff_template_name = "trait_parent",
                buff_type = "trait_child",
                stat_buff_index = "swift_stage",
                template = {
                    name = "trait_child",
                    stat_buff = "attack_speed",
                },
            },
        })
        local row = snapshot.by_stat.attack_speed
        H.equal(#row.stages, 2)
        local by_key = {}
        for _, stage in ipairs(row.stages) do by_key[stage.key] = stage end
        H.truthy(by_key[0])
        H.truthy(by_key.swift_stage)
        H.equal(by_key.swift_stage.sources[1].parent, "trait_parent")
        H.equal(by_key.swift_stage.sources[1].child, "trait_child")
        H.equal(by_key.swift_stage.sources[1].lifetime, "persistent")
        H.equal(snapshot.contributions, 2)
        H.equal(snapshot.stat_types, 1)
    end)

    H.test("GT #797 uses native ordered-stage then root-stage math", function()
        local row = {
            method = "stacking_bonus_and_multiplier",
            stages = {
                {
                    key = 2, key_text = "2", bonus = 2,
                    multiplier = 0.1, proc_chance = 1, sources = {},
                },
                {
                    key = 0, key_text = "0", bonus = 5,
                    multiplier = 0.2, proc_chance = 1, sources = {},
                },
            },
        }
        local value = core.evaluate(row, 100)
        H.equal(value.supported, true)
        H.truthy(math.abs(value.final - 139.4) < 0.000001)
        H.truthy(math.abs(value.contributions[1].delta - 12) < 0.000001)
        H.truthy(math.abs(value.contributions[2].delta - 27.4) < 0.000001)
        H.equal(value.contributions[1].kind, "ordered-stage")
        H.equal(value.contributions[2].kind, "root-aggregate")
    end)

    H.test("GT #797 refuses proc dynamic and unavailable-base finals", function()
        local function row(multiplier, chance, method)
            return {
                method = method or "stacking_multiplier",
                stages = {
                    {
                        key = 1, key_text = "1", bonus = 0,
                        multiplier = multiplier, proc_chance = chance, sources = {},
                    },
                },
            }
        end
        H.equal(core.evaluate(row(0.2, 0.5), 1).reason, "proc-stage")
        H.equal(core.evaluate(row(function() end, 1), 1).reason, "function-multiplier")
        H.equal(core.evaluate(row({}, 1), 1).reason, "table-multiplier")
        H.equal(core.evaluate(row(0.2, 1, "proc"), 1).reason, "proc-stage")
        H.equal(core.evaluate(row(0.2, 1), nil).reason, "base-unavailable")
    end)

    H.test("GT #797 census bounds stat types and stages", function()
        local rows = {}
        for i = 1, core.MAX_STAT_TYPES + 10 do
            rows[string.format("stat_%04d", i)] = {}
        end
        local snapshot = core.normalize(rows, {}, {})
        H.equal(snapshot.stat_types, core.MAX_STAT_TYPES)
        H.equal(snapshot.truncated, true)
    end)

    H.test("GT #797 bounds active-source enumeration before sorting", function()
        local buffs = {}
        for i = 1, core.MAX_ACTIVE_BUFFS + 10 do
            buffs[i] = {
                id = i,
                buff_template_name = "parent",
                buff_type = "child",
                stat_buff_index = 0,
                template = { stat_buff = "attack_speed" },
            }
        end
        local snapshot = core.normalize({
            attack_speed = {
                [0] = { bonus = 0, multiplier = 0.1, proc_chance = 1 },
            },
        }, { attack_speed = "stacking_multiplier" }, buffs)
        H.equal(snapshot.source_truncated, true)
        H.equal(#snapshot.by_stat.attack_speed.stages[1].sources,
            core.MAX_ACTIVE_BUFFS)
    end)

    H.test("GT #797 composes current action speed and crit in engine order", function()
        local normalized = core.normalize({
            attack_speed = {
                [0] = { bonus = 0, multiplier = 0.1, proc_chance = 1 },
            },
            attack_speed_melee = {
                [0] = { bonus = 0, multiplier = 0.2, proc_chance = 1 },
            },
            critical_strike_chance_melee = {
                [0] = { bonus = 0.05, multiplier = 0, proc_chance = 1 },
            },
            critical_strike_chance = {
                [0] = { bonus = 0.05, multiplier = 0, proc_chance = 1 },
            },
        }, {
            attack_speed = "stacking_multiplier",
            attack_speed_melee = "stacking_multiplier",
            critical_strike_chance_melee = "stacking_bonus",
            critical_strike_chance = "stacking_bonus",
        }, {})
        local context = {
            action_available = true,
            action_anim_time_scale = 1.2,
            is_melee = true,
            critical_base = 0.05,
            action_additional_crit = 0.1,
            critical_is_melee = true,
            max_fatigue = 6,
        }
        local speed = hud.action_speed_value(normalized, context, core.evaluate)
        H.truthy(math.abs(speed.final - 1.584) < 0.000001)
        H.equal(speed.contributions[1].stat, "attack_speed")
        H.equal(speed.contributions[2].stat, "attack_speed_melee")
        local critical = hud.critical_value(normalized, context, core.evaluate)
        H.truthy(math.abs(critical.final - 0.25) < 0.000001)
        H.equal(critical.contributions[1].kind, "action-base-bonus")
        local rows = hud.build_rows(normalized, {
            health = 100, stamina = 6, cooldown = 80,
            critical = 0.05, fatigue_regen_amount = 1.5,
            character_power = 650, ability_max_charges = 1,
        }, core.evaluate, nil, context)
        local by_stat = {}
        for _, row in ipairs(rows) do by_stat[row.stat] = row end
        H.truthy(math.abs(by_stat.attack_speed_chain.value.final - 1.584)
            < 0.000001)
        H.truthy(math.abs(by_stat.attack_speed_animation.value.final - 1.584)
            < 0.000001)
        H.equal(by_stat.critical_strike_chance.value.supported, false)
        H.equal(by_stat.critical_strike_chance.value.reason,
            "runtime-overrides-unobservable")
        H.truthy(hud.row_text(by_stat.critical_settings_chance)
            :find("settings=0.25", 1, true))
    end)

    H.test("GT #797 action charge-time truth table matches native call paths", function()
        -- ActionUtils.get_action_time_scale applies charge speed for:
        -- chain-window OR (animation-window AND is_animation).
        local normalized = core.normalize({
            reduced_ranged_charge_time = {
                [0] = { bonus = 0, multiplier = -0.5, proc_chance = 1 },
            },
        }, {
            reduced_ranged_charge_time = "stacking_multiplier",
        }, {})
        local function value(chain_window, animation_window, is_animation)
            return hud.action_speed_value(normalized, {
                action_available = true,
                action_anim_time_scale = 1,
                is_ranged = true,
                scale_chain_window_by_charge_time = chain_window,
                scale_anim_by_charge_time = animation_window,
            }, core.evaluate, is_animation)
        end
        H.equal(value(false, false, false).final, 1)
        H.equal(value(false, false, true).final, 1)
        H.equal(value(true, false, false).final, 2)
        H.equal(value(true, false, true).final, 2)
        H.equal(value(true, true, false).final, 2)
        H.equal(value(false, true, false).final, 1)
        H.equal(value(false, true, true).final, 2)
        local unknown = value(false, true, nil)
        H.equal(unknown.supported, false)
        H.equal(unknown.reason,
            "charge-time-is_animation-callsite-unobservable")
    end)

    H.test("GT #797 partial-cost ability exposes activation factor, not max-cooldown final", function()
        -- Pinned c5e4968 career_extension.lua:353-358,417-429:
        -- new = current + max * (modified_cost or cost)
        --     - max * cost * refund_percent; activated_cooldown applies to new.
        local normalized = core.normalize({
            activated_cooldown = {
                [0] = { bonus = 0, multiplier = -0.1, proc_chance = 1 },
            },
        }, { activated_cooldown = "stacking_multiplier" }, {})
        local rows = hud.build_rows(normalized, {
            health = 100, stamina = 6, cooldown = 80,
            critical = 0.05, fatigue_regen_amount = 1.5,
            character_power = 650, ability_max_charges = 1,
        }, core.evaluate, nil, { max_fatigue = 6 })
        local by_stat = {}
        for _, row in ipairs(rows) do by_stat[row.stat] = row end
        local activation = by_stat.activated_cooldown
        H.equal(activation.display, "factor")
        H.truthy(math.abs(activation.value.final - 0.9) < 0.000001)
        H.truthy(hud.row_text(activation):find("factor=0.9", 1, true))
        H.equal(hud.row_text(activation):find("final=72", 1, true), nil)

        local max_cooldown, current, cost, refund_percent = 80, 0, 0.5, 0
        local pre_buff = current + max_cooldown * cost
            - max_cooldown * cost * refund_percent
        local exact = core.evaluate(normalized.by_stat.activated_cooldown, pre_buff)
        H.equal(pre_buff, 40)
        H.truthy(math.abs(exact.final - 36) < 0.000001)
    end)

    H.test("GT #797 six-point stamina derives exact gauge regen before buffs", function()
        -- Pinned c5e4968 generic_status_extension.lua:327-336:
        -- base = 1.5 / max_fatigue_points * 100, then fatigue_regen, then dt.
        local normalized = core.normalize({
            fatigue_regen = {
                [0] = { bonus = 0, multiplier = 0.2, proc_chance = 1 },
            },
        }, { fatigue_regen = "stacking_multiplier" }, {})
        local value = hud.fatigue_regen_value(
            normalized, { max_fatigue = 6 }, 1.5, core.evaluate)
        H.equal(value.supported, true)
        H.truthy(math.abs(value.base - 25) < 0.000001)
        H.truthy(math.abs(value.final - 30) < 0.000001)
        local unavailable = hud.fatigue_regen_value(
            normalized, {}, 1.5, core.evaluate)
        H.equal(unavailable.supported, false)
        H.equal(unavailable.reason, "max-fatigue-unavailable")
    end)

    H.test("GT #797 engine-alive death state fails closed", function()
        H.equal(hud.unit_is_dead({ state = "alive" }, { dead = false }), false)
        H.equal(hud.unit_is_dead({ state = "dead" }, { dead = false }), true)
        H.equal(hud.unit_is_dead({ state = "alive" }, {
            is_dead = function() return true end,
        }), true)
        H.equal(hud.unit_is_dead(nil, { dead = true }), true)
        H.equal(hud.unit_is_dead({
            is_dead = function() error("unavailable") end,
        }, nil), false)
    end)

    H.test("GT #797 authoritative getter deltas reconcile visibly", function()
        local value = {
            supported = true,
            base = 100,
            final = 120,
            contributions = {
                {
                    key_text = "0", kind = "root-aggregate",
                    delta = 20, sources = {},
                },
            },
        }
        hud.reconcile(value, 90, "HealthExtension.get_max_health")
        H.equal(value.final, 90)
        H.equal(value.contributions[2].kind, "unattributed-engine-delta")
        H.equal(value.contributions[2].delta, -30)
        local sum = value.base
        for _, contribution in ipairs(value.contributions) do
            sum = sum + contribution.delta
        end
        H.equal(sum, value.final)
    end)

    H.test("GT #797 labels retained factors and unsupported downstream finals", function()
        local normalized = core.normalize({
            power_level_skaven = {
                [0] = { bonus = 0, multiplier = 0.1, proc_chance = 1 },
            },
        }, { power_level_skaven = "stacking_multiplier" }, {})
        local rows = hud.build_rows(normalized, {
            health = 100, stamina = 6, cooldown = 80,
            critical = 0.05, fatigue_regen_amount = 1.5,
            character_power = 650, ability_max_charges = 1,
        }, core.evaluate, nil, {})
        local by_stat = {}
        for _, row in ipairs(rows) do by_stat[row.stat] = row end
        H.truthy(hud.row_text(by_stat.power_level_skaven)
            :find("factor=1.1", 1, true))
        H.equal(by_stat.effective_power.value.supported, false)
        H.equal(by_stat.effective_power.value.reason,
            "difficulty-profile-target-dependent")
        H.equal(by_stat.attack_speed_chain.value.reason, "action-unavailable")
        H.equal(by_stat.attack_speed_animation.value.reason, "action-unavailable")
        H.equal(by_stat.movement_speed.value.supported, false)
        H.equal(by_stat.movement_speed.value.reason,
            "stance/status/current_movement_speed_scale/player_speed_scale-dependent")
    end)

    H.test("GT #797 cache measures bounded samples rebuilds and allocations", function()
        local cache = core.new_cache()
        local due_count = 0
        for i = 0, 100 do
            local due, edge = core.cache_due(cache, i * 0.05, "unit/item/action", "buff-a")
            if due then
                due_count = due_count + 1
                H.equal(edge, due_count == 1)
            end
        end
        H.truthy(due_count >= 18 and due_count <= 22)
        H.equal(cache.rebuilds, 1)
        local due, edge = core.cache_due(cache, 6, "unit/item/action", "buff-b")
        H.equal(due, true)
        H.equal(edge, true)
        H.equal(cache.rebuilds, 2)
        core.record_allocation(cache, 25, 73)
        core.record_allocation(cache, 25, 70)
        H.equal(cache.formatted, 2)
        H.equal(cache.allocated_rows, 50)
        H.equal(cache.max_lines, 73)
    end)

    H.test("GT #797 trace cadence and record count stay hard bounded", function()
        local trace = core.new_trace(5)
        H.equal(core.take_due(trace, 4.99), nil)
        for i, offset in ipairs(core.TRACE_OFFSETS) do
            H.equal(core.take_due(trace, 5 + offset), offset)
            H.equal(core.record(trace, offset, "fp" .. i), true)
        end
        H.equal(core.take_due(trace, 100), nil)
        H.equal(core.record(trace, 99, "overflow"), false)
        H.equal(#trace.records, 5)
        H.equal(core.complete(trace), true)
    end)

    H.test("GT #797 expanded pages expose every row and contribution", function()
        local normalized = core.normalize({
            attack_speed = {
                named_stage = {
                    bonus = 0, multiplier = 0.2, proc_chance = 1,
                },
            },
        }, { attack_speed = "stacking_multiplier_multiplicative" }, {})
        local bases = {
            health = 100, stamina = 6, cooldown = 80,
            critical = 0.05, fatigue_regen_amount = 1.5,
            character_power = 650, ability_max_charges = 1,
        }
        local context = {
            action_available = true,
            action_anim_time_scale = 1,
            is_melee = true,
            critical_base = 0.05,
            action_additional_crit = 0,
            critical_is_melee = true,
            max_health = 100,
            max_fatigue = 6,
            cooldown_remaining = 0,
            ability_ready_charges = 1,
        }
        local snapshot = {
            rows = hud.build_rows(normalized, bases, core.evaluate, nil, context),
            context = {
                career = "es_knight", slot = "slot_melee", item = "es_sword",
                template = "one_handed_sword_template_1",
                style = "MELEE_1H", action = "action_one",
                subaction = "light_attack_left", damage_profile = "light_slashing",
            },
        }
        local lines = hud.all_lines(snapshot, true)
        local _, _, pages = hud.page(lines, 1)
        local body_seen = 0
        for page = 1, pages do
            local visible = hud.page(lines, page)
            body_seen = body_seen + #visible - 4
        end
        H.equal(body_seen, #lines - 3)
        H.truthy(lines[2]:find("style=MELEE_1H", 1, true))
        H.truthy(lines[2]:find("template=one_handed_sword_template_1", 1, true))
        H.truthy(lines[3]:find("action_one/light_attack_left", 1, true))
        H.truthy(table.concat(lines, "\n")
            :find("stage[attack_speed/named_stage]", 1, true))
        H.truthy(table.concat(lines, "\n"):find("base=1  final=1.2", 1, true))
    end)

    H.test("GT #797 wraps every rendered line before pagination", function()
        local source = string.rep("very_long_source_identity_", 8)
        local lines = {
            "PLAYER STATS - READ ONLY",
            "career | template=" .. source,
            "action=" .. source,
            "  stage[root] root-aggregate delta=1 src=" .. source,
        }
        local wrapped = hud.wrap_lines(lines, 40)
        H.truthy(wrapped.header_count > 3)
        for _, line in ipairs(wrapped) do H.truthy(#line <= 40, line) end
        local visible, _, pages = hud.page(wrapped, 1)
        H.truthy(#visible <= wrapped.header_count + 1 + hud.PAGE_ROWS)
        H.truthy(pages >= 1)
    end)

    H.test("GT #797 bottom layout avoids existing top overlay occupancy", function()
        local left = hud.layout(22, 75, "bottom_left")
        local right = hud.layout(22, 125, "bottom_right")
        H.equal(left.x, 28)
        H.truthy(right.x > left.x)
        H.truthy(right.x + right.width <= 1920)
        H.truthy(left.top < 900)
        H.truthy(right.top < 900)
        H.truthy(left.top - left.height >= 0)
        H.equal(hud.REFRESH_SECONDS, 0.25)
    end)

    H.test("GT #797 runtime remains local read-only and lifecycle cached", function()
        local source = read(repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_player_stats.lua")
        for _, marker in ipairs({
            'mod:dofile("scripts/mods/general_tweaker_dev/_gt_player_stat_snapshot_policy")',
            'mod._gt_register_update("gt797_player_stat_probe", _update)',
            'mod:command("gt_stat_probe"',
            'mod:command("gt_stat_trace"',
            'mod:command("gt_stat_hud_page"',
            'mod:command("gt_stat_hud_metrics"',
            'current_action_settings',
            'scale_chain_window_by_charge_time_buff',
            'hud.unit_is_dead(health, status)',
            '"local-player-dead"',
            'lookup.action_name',
            'damage_profile',
            'source_parent=%s source_child=%s source_id=%s',
            'next_poll = clock + core.SAMPLE_SECONDS',
            'core.cache_due',
            'if edge or not plan then plan = _build_plan(buff) end',
            '_clear_panel()',
            'hud.wrap_lines',
            'get_career_power_level',
            'PlayerUnitStatusSettings.FATIGUE_POINTS_DEGEN_AMOUNT',
            'equipment.max_fatigue = _call(status, "get_max_fatigue_points")',
            'mod._gt_player_stat_hud_draw = _draw',
            'mod._gt_player_stat_hud_reset = _reset_hud',
        }) do
            H.truthy(source:find(marker, 1, true), marker)
        end
        H.equal(source:find("mod:network_", 1, true), nil)
        H.equal(source:find("mod:hook", 1, true), nil)
        H.equal(source:find("mod:echo", 1, true), nil)
        H.equal(source:find("_gt_player_stat_probe_core", 1, true), nil)
        H.equal(source:find("buff:apply_buffs_to_value", 1, true), nil)
        H.equal(source:find("UIRenderer.draw_rect", 1, true), nil)

        local melee = read(repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_melee_warning.lua")
        H.truthy(melee:find("mod._gt_player_stat_hud_draw", 1, true))
        local main = read(repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua")
        H.truthy(main:find("mod._gt_player_stat_hud_reset()", 1, true))
        H.truthy(main:match('local MOD_VERSION = "0%.2%.%d+%-dev"'))
    end)
end
