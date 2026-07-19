return function(H, repo_root)
    local core = dofile(repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_behavior_core.lua")

    local function ready(overrides)
        local state = {
            triggered = false,
            enabled = true,
            is_server = true,
            game_mode = "adventure",
            level_key = "ground_zero",
            difficulty_rank = 6,
            in_boss_arena = true,
            health_percent = 0.5,
        }
        for key, value in pairs(overrides or {}) do state[key] = value end
        return state
    end

    H.test("ET #450 Halescourge trigger opens exactly at half health", function()
        local allowed, reason = core.halescourge_gate(ready())
        H.equal(allowed, true)
        H.equal(reason, "ready")
        allowed, reason = core.halescourge_gate(ready({ health_percent = 0.5001 }))
        H.equal(allowed, false)
        H.equal(reason, "above_threshold")
    end)

    H.test("ET #450 Halescourge trigger is a host Adventure Cata arena one-shot", function()
        local cases = {
            { { triggered = true }, "already_triggered" },
            { { enabled = false }, "disabled" },
            { { is_server = false }, "not_server" },
            { { game_mode = "deus" }, "not_adventure" },
            { { level_key = "inn_level" }, "wrong_level" },
            { { difficulty_rank = 5 }, "below_cataclysm" },
            { { in_boss_arena = false }, "outside_boss_arena" },
            { { health_percent = false }, "health_missing" },
            { { health_percent = 0 }, "boss_dead" },
        }
        for _, case in ipairs(cases) do
            local allowed, reason = core.halescourge_gate(ready(case[1]))
            H.equal(allowed, false)
            H.equal(reason, case[2])
        end
    end)

    H.test("ET #450 Halescourge add catalog is only troll or spawn", function()
        H.equal(#core.HALESCOURGE_MONSTERS, 2)
        H.equal(core.monster_for_roll(1), "chaos_troll")
        H.equal(core.monster_for_roll(2), "chaos_spawn")
        H.equal(core.monster_for_roll(0), nil)
        H.equal(core.monster_for_roll(3), nil)
    end)

    H.test("ET #450 Skarrik ranged resistance is exact and fail-closed", function()
        H.equal(core.skarrik_ranged_damage(100, true, true, true), 70)
        H.equal(core.skarrik_ranged_damage(100, false, true, true), 100)
        H.equal(core.skarrik_ranged_damage(100, true, false, true), 100)
        H.equal(core.skarrik_ranged_damage(100, true, true, false), 100)
        H.equal(core.skarrik_ranged_damage(nil, true, true, true), nil)
    end)

    H.test("ET #450 Deathrattler tracking halves only the boss ratling paths", function()
        H.equal(core.deathrattler_tracking_dt(0.1, true, true, true), 0.05)
        H.equal(core.deathrattler_tracking_dt(0.1, false, true, true), 0.1)
        H.equal(core.deathrattler_tracking_dt(0.1, true, false, true), 0.1)
        H.equal(core.deathrattler_tracking_dt(0.1, true, true, false), 0.1)
        H.equal(core.deathrattler_rotation_time(2, true), 1)
        H.equal(core.deathrattler_rotation_time(2, false), 2)
    end)

    H.test("ET #450 production shares the existing post-spawn owner", function()
        local base = repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/"
        local behavior_file = assert(io.open(base .. "_et_boss_behavior.lua", "rb"))
        local behavior = behavior_file:read("*a")
        behavior_file:close()
        local grudge_file = assert(io.open(base .. "_et_boss_grudge.lua", "rb"))
        local grudge = grudge_file:read("*a")
        grudge_file:close()
        local champion_file = assert(io.open(base .. "_et_champion_warlord.lua", "rb"))
        local champion = champion_file:read("*a")
        champion_file:close()
        H.equal(behavior:find('mod:hook_safe("ConflictDirector"', 1, true), nil)
        H.equal(behavior:find('mod:hook("ConflictDirector"', 1, true), nil)
        H.truthy(behavior:find('mod:hook("BTStormfiendShootAction"', 1, true))
        H.truthy(behavior:find("boss_behavior_update", 1, true))
        H.truthy(behavior:find('time_manager, "main"', 1, true))
        H.truthy(grudge:find("observe_boss_behavior_spawn", 1, true))
        H.truthy(behavior:find("et_boss_balance_no_pool_swap", 1, true))
        H.truthy(champion:find("optional_data.et_boss_balance_no_pool_swap", 1, true))
    end)

    H.test("ET #450 remaining behaviors compose existing owners", function()
        local base = repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/"
        local function text(name)
            local file = assert(io.open(base .. name, "rb"))
            local value = file:read("*a")
            file:close()
            return value
        end
        local behavior = text("_et_boss_behavior.lua")
        local handicap = text("_et_personal_handicap.lua")
        local balance = text("_et_boss_balance.lua")
        local commands = text("_et_commands.lua")
        local data = text("enemy_tweaker_data.lua")

        H.truthy(handicap:find("boss_behavior_scale_incoming_damage", 1, true))
        H.truthy(behavior:find("RangedAttackTypes", 1, true))
        H.truthy(behavior:find("DEATHRATTLER_BREED", 1, true))
        H.truthy(balance:find("_apply_deathrattler_tracking", 1, true))
        H.truthy(commands:find('pcall(engine_printf, "[et:450] " .. fmt, ...)', 1, true))
        H.truthy(commands:find('mod:command("verify_boss_balance"', 1, true))
        H.truthy(data:find('setting_id    = "boss_behavior_skarrik_ranged_dr"', 1, true))
        H.truthy(data:find('setting_id    = "boss_behavior_deathrattler_tracking"', 1, true))
    end)
end
